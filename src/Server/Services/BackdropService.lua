--!strict
-- ServerScriptService/Services/BackdropService.lua
-- The world beyond the level: colossal liminal structures on the horizon.
--
-- === Why it is static, and on the server ===
--
-- This used to be a CLIENT service that re-centred the whole backdrop on the player every
-- frame, so the horizon travelled with you and could never be reached. That bought one
-- real thing -- perfect unreachability -- and cost three:
--
--   * it VANISHED on focus loss, because a per-frame client model of small parts is
--     exactly what aggressive distance culling drops first;
--   * it appeared late, because it could not be placed until a character existed;
--   * every client paid to build and pivot several hundred parts, forever.
--
-- Static geometry built once on the server has none of those problems, and the thing it
-- gives up turns out to be nearly free. A level runs about 240 studs end to end. The
-- nearest ring here is 1900 studs out, so walking a level from start to finish closes
-- roughly 12% of the distance to it -- a size change of about a tenth, spread over
-- several minutes, through 0.3-density haze. It is not perfect parallax lock. It is not
-- visible either, and it is the trade the levels' actual size makes available.
--
-- === Why everything is enormous ===
--
-- Not only for the look. Roblox drops distant geometry by SCREEN size, so a 15-stud-wide
-- column at 300 studs is in the first size class to go -- which is what the old backdrop
-- was made of and why it flickered out whenever quality dropped. Nothing here is under
-- about 90 studs across, and the towers are 150 to 320. Big and far survives what small
-- and near did not.
--
-- === Why it does not touch the lighting ===
--
-- LightingService's atmosphere already gives a 240-stud level depth, and it is exactly
-- the right fog for this: structures thousands of studs out arrive half-dissolved into
-- it. The backdrop therefore adds no fog, no ceiling and no enclosure. It must not,
-- either -- five of the six materials read through EnvironmentSpecularScale picking up
-- the SKY, so roofing the level over would flatten every glossy surface in the game.
--
-- === What it is made of ===
--
-- A PASTEL BEACH CITY AT GOLDEN HOUR, since the second version. A crescent of land holds the
-- city, placed with its back to the sun: a beach sloping out of the bay, a promenade of palms,
-- a row of deco hotels facing the water, and towers rising behind them into the haze. The
-- other side is open sea toward the low sun, where the sandbars, the float rings and the
-- ordinary objects at hundreds of studs tall stand in the glitter. The aquapark fills the bay
-- round the level. Softly coloured, never dark.
--
-- The first version was a city standing IN the sea all the way round, with a ring of columns,
-- 500 opaque balls for clouds and 126 banks of vapour between the level and the water. Seen
-- from the level it came out as pale boxes in a pink wash with white eggs floating in front of
-- them -- nothing said where the shore was, or which way anything faced.
--
-- The water is what makes the level feel airborne. Everything else here says "far away";
-- only a floor a long way DOWN says "high up".

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BackdropService = {}

-- World height the backdrop's ORIGIN sits at: the WATER LINE, and the plane every tower
-- stands in.
--
-- This was -160, which put the horizon 184 studs under your feet -- close enough that it
-- read as ground you happened to be standing above rather than as distance. Height is not
-- a property of the level, it is a property of how far away the thing beneath you is, so
-- the only way to feel high up is to put the floor a long way down.
--
-- 700 studs is roughly a skyscraper's worth. The consequence worth understanding: at this
-- depth the near band sits BELOW eye level and only the far towers rise past you, so you
-- look down on one city and up at another. That is the composition, not a side effect.
--
-- The kill plane sits at about -16 (the level's lowest surface, less 40), so you die
-- roughly 680 studs before touching the water. It is scenery and stays scenery.
local BASE_Y = -700

-- ===== THE COAST =====
--
-- The city stands on a CRESCENT of land and the sea comes right round the level in front of it,
-- so the bay is the water under the spiral and the dive lands in it. At each end of the crescent
-- a harbour wall runs straight out to sea, and past them is open water.
--
-- NO HEADLANDS. The coast first curved away into two capes, and the land is built in 4-degree
-- slices from the level's centre: where the shoreline moved outward by hundreds of studs per
-- slice, every slice's beach sat at a different distance and the capes came out as a staircase
-- with sea showing between the treads. One radius all the way round is a smooth beach, and a
-- straight quay is what a city coast ends in anyway.
--
-- Radii are from the level's centre, in the backdrop's own frame (the sea's mean surface is 0).
local SHORE_NEAR = 1150 -- the bay: water under and around the level, out to the beach
local LAND_FAR = 6000 -- where the land ends, just inside the sea's own reach
-- Ground height over mean water. The swell reaches 36 either way, so the land stands clear of
-- every crest and the beach ramps down under every trough.
local LAND_TOP = 46
local CITY_HALF = math.rad(112) -- land either side of the city's centre line
local BEACH_WET, BEACH_DRY = 170, 170 -- the beach reaches this far into the water, and inland
local PROMENADE = 90
-- The city's centre line, facing AWAY from the sun: set at the start of every build, from where
-- the sun actually is, so the towers are lit on the side you look at and the sun sets over
-- open water. See sunBearing.
local cityBearing = 0

-- A beach city's pastels: pool mint, coral, cream, lemon, sky and lilac. A step richer than the
-- first version's, which were chosen to be taken the rest of the way by a heavy haze -- and
-- under clear late light they arrived as one pale pink.
local PALETTE = {
	Color3.fromRGB(164, 214, 194),
	Color3.fromRGB(240, 178, 168),
	Color3.fromRGB(240, 232, 214),
	Color3.fromRGB(240, 222, 160),
	Color3.fromRGB(166, 202, 228),
	Color3.fromRGB(202, 186, 226),
}

-- Deterministic, so the horizon is the same place every session. A backdrop that
-- reshuffled on each join would undercut the one thing it is for: being a fixed,
-- familiar, unreachable somewhere.
local rng = Random.new(20260812)

local function pick(): Color3
	return PALETTE[rng:NextInteger(1, #PALETTE)]
end

-- SHAPE IS A REAL PARAMETER NOW, and its absence was a silent bug worth recording.
--
-- This function used to take five arguments while four callers passed six, handing it
-- Enum.PartType.Ball and Enum.PartType.Cylinder as a trailing argument that Lua discards
-- without a word. Every sphere and every cylinder in the backdrop -- the playplace balls,
-- the lamp shades, the plinth caps -- had been rendering as BLOCKS. The variety was
-- written and simply never reached the screen, which is why the horizon looked like a
-- field of pale rectangles.
-- === Concrete variant for the architecture ===
--
-- The towers, colonnade and facades are Parts, and SurfaceAppearance does nothing on a Part
-- -- silently. MaterialVariant is what works there, and it splits the same way everything
-- else has: the variant's maps need the Plugin capability, so it is built by hand under
-- MaterialService and this only ever writes its NAME.
--
-- Blank means not made yet, and blank is safe: the architecture renders exactly as it does
-- today. A name that does not exist is also safe -- Roblox falls back to plain Concrete
-- without complaint, which is why the check below says so out loud instead.
--
-- ONE variant for all of it. Every tint out here comes from part.Color and the pastel
-- palette, and a MaterialVariant's ColorMap MULTIPLIES that rather than replacing it, so a
-- single near-white concrete serves all six palette entries.
local CONCRETE_VARIANT = "ConcreteBackdrop"

-- Glazed mosaic, for the aquapark structures. Same manual story as the concrete one: make a
-- MaterialVariant with this name under MaterialService and paste the PoolTile_* ids in.
--
-- Two variants rather than one because the horizon is now two kinds of place. Concrete is
-- the municipal shell around it; tile is the pool itself, and a leisure centre is exactly
-- the building where those two materials meet at a hard line.
local POOLTILE_VARIANT = "PoolTileBackdrop"

local concreteUsable = CONCRETE_VARIANT ~= ""
local concreteChecked = false

local function useVariant(part: BasePart, name: string)
	if not concreteUsable then
		return
	end
	if not concreteChecked then
		concreteChecked = true
		local service = game:GetService("MaterialService")
		for _, wanted in ipairs({ CONCRETE_VARIANT, POOLTILE_VARIANT }) do
			if not service:FindFirstChild(wanted) then
				warn(
					("[server] No MaterialVariant named '%s' under MaterialService; that part "
						.. "of the backdrop renders untextured. Harmless, but the name is set in "
						.. "BackdropService so one of the two is a typo."):format(wanted)
				)
			end
		end
	end
	-- Guarded once, then disabled. This is the third property in this project that turned
	-- out to need a capability, and the last one took out an entire ChunkBuilder run. The
	-- backdrop draws about a thousand of these, so a pcall per part is not affordable and a
	-- boolean afterwards is.
	local ok = pcall(function()
		part.Material = Enum.Material.Concrete
		part.MaterialVariant = name
	end)
	if not ok then
		concreteUsable = false
		warn("[server] MaterialVariant could not be written; backdrop textures disabled.")
	end
end

local function piece(
	parent: Instance,
	size: Vector3,
	cf: CFrame,
	colour: Color3,
	material: Enum.Material,
	shape: Enum.PartType?
): Part
	local part = Instance.new("Part")
	part.Size = size
	part.CFrame = cf
	part.Color = colour
	part.Material = material
	if shape then
		part.Shape = shape
	end
	part.Anchored = true
	-- Scenery in every sense: nothing here collides, senses touch, answers a raycast or
	-- casts a shadow. A backdrop that could be landed on would be a gameplay surface
	-- thousands of studs off the route.
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Parent = parent
	return part
end

-- An UPRIGHT cylinder, which Roblox does not give you directly.
--
-- Enum.PartType.Cylinder extrudes along the part's X axis, so its Size is
-- (length, diameter, diameter) and it arrives lying on its side. Every upright cylinder
-- therefore needs both a swapped Size and a 90-degree roll, and doing that at each call
-- site is how you end up with a lamp post lying in the grass. It is done once, here.
local function pillar(parent: Instance, diameter: number, height: number, cf: CFrame, colour: Color3, material: Enum.Material)
	return piece(
		parent,
		Vector3.new(height, diameter, diameter),
		cf * CFrame.Angles(0, 0, math.pi / 2),
		colour,
		material,
		Enum.PartType.Cylinder
	)
end

-- === The wave surface, duplicated from blender/gen_sea.py ===
--
-- KEEP THESE IN STEP WITH THAT FILE. It prints this exact block on every run for that
-- reason; change WAVES or HEIGHT there and paste the new numbers here. There is no way to
-- share them -- nothing syncs to Studio and the mesh is baked in Blender -- so the coupling
-- is real and the failure is silent: mismatched constants leave the foam floating above the
-- water or buried inside it, everywhere at once, with nothing logged.
--
-- Why Luau needs the spectrum at all: the foam is placed at the wave's ACTUAL height and
-- tilted to its ACTUAL slope. Without that it hovers at a fixed altitude over a surface
-- that rises and falls 60 studs beneath it, which is what made the old flecks read as
-- decals stuck on a photograph rather than as anything floating.
local SEA_TILE_HEIGHT = 72
local WAVE_TILE = 1600
local WAVE_LOW, WAVE_SPAN = -3.597824, 6.858241
local WAVES = {
	{ 2, 1, 1.00, 0.00 },
	{ 1, 2, 0.88, 1.10 },
	{ 3, 2, 0.66, 2.30 },
	{ 2, -3, 0.54, 0.60 },
	{ 4, 3, 0.38, 3.00 },
	{ 3, -4, 0.30, 1.80 },
	{ 5, 2, 0.22, 2.60 },
	{ 2, 6, 0.17, 0.40 },
	{ 7, 4, 0.12, 1.20 },
	{ 6, -7, 0.09, 2.90 },
}

-- Surface height and slope at a world position, in the backdrop's local frame.
--
-- u and v are NOT taken relative to a tile. Every frequency is an integer over the tile, so
-- adding a whole tile to u leaves every sine unchanged -- the field is continuous across
-- the whole sea and there is no tile to look up. That is the same property that makes the
-- mesh seamless, used a second time.
--
-- Height and both derivatives come out of ONE loop. sin and cos of the same angle are
-- wanted together, so evaluating them separately would double the trigonometry for nothing.
local function waveSurface(x: number, z: number): (number, Vector3)
	local u, v = x / WAVE_TILE + 0.5, z / WAVE_TILE + 0.5
	local height, slopeX, slopeZ = 0, 0, 0
	for _, wave in ipairs(WAVES) do
		local nx, nz, amplitude, phase = wave[1], wave[2], wave[3], wave[4]
		local angle = math.pi * 2 * (nx * u + nz * v) + phase
		height += amplitude * math.sin(angle)
		local common = amplitude * math.cos(angle) * math.pi * 2 / WAVE_TILE
		slopeX += common * nx
		slopeZ += common * nz
	end
	local scale = SEA_TILE_HEIGHT / WAVE_SPAN
	-- CENTRED ON ZERO, not topping out at it.
	--
	-- The tiles used to sit with their crests at y = 0 and their troughs 60 below, which put
	-- the entire sea AT OR UNDER the plane everything else stands on. Towers, facades and
	-- objects all began at exactly 0, so they met the water at their own base and looked
	-- set on top of it -- and wherever a trough fell they hung over open air. With the
	-- surface oscillating around zero instead, anything placed below it is genuinely in the
	-- water and the waves close over its base.
	local y = ((height - WAVE_LOW) / WAVE_SPAN - 0.5) * SEA_TILE_HEIGHT
	-- The surface normal of y = f(x, z) is (-df/dx, 1, -df/dz), normalised.
	return y, Vector3.new(-slopeX * scale, 1, -slopeZ * scale).Unit
end

-- How far a flat thing of this width has to sit above the surface it was laid tangent to.
--
-- A disc laid tangent to a curved surface departs from it QUADRATICALLY with radius, and
-- these waves are 72 studs peak to trough. Measured: a 120-stud ring's rim ends up 10 studs
-- off its own tangent plane, a 400-stud one 77, a 670-stud one 142. Everything here used a
-- flat 2-stud lift, so every waterline ring and every surf crescent was completely under
-- water -- present, animated, replicated, and invisible.
--
-- Lifted by about HALF the worst departure rather than all of it. Clearing it entirely
-- would leave the big rings visibly hovering above the sea; at half, the swell buries part
-- of each one and the rest shows, which is what a waterline in moving water looks like.
local function clearance(span: number): number
	-- BARELY ANY LIFT AT ALL, which is the third and last version of this number.
	--
	-- It started at a flat 2, which buried everything. Then it scaled with width, which sent
	-- a 1920-stud streak 196 studs into the air. Then it was capped at 35, which still left
	-- a visible hover -- and the cap was treating a symptom, because the real problem was
	-- never the lift.
	--
	-- Foam is not an object resting ON water, it is a mark IN its surface. It should straddle
	-- the waterline and let the swell cut into it: hidden where the sea rises over it, showing
	-- where the sea falls away. That needs a lift of almost nothing, and it needs the overlay
	-- to be THIN -- see the thickness clamps at each call site, which is where the actual
	-- hovering came from.
	return math.min(2 + span * 0.02, 8)
end

-- Lays a flat thing ON the water: at the wave's height, in its tangent plane, pointing
-- along `heading`. The heading is projected onto the tangent plane rather than used
-- directly, because a direction that is not perpendicular to the normal cannot be an axis
-- of the frame and CFrame.fromMatrix would silently shear the mesh.
local function onWave(x: number, z: number, heading: number, lift: number): CFrame
	local y, up = waveSurface(x, z)
	local along = Vector3.new(math.cos(heading), 0, math.sin(heading))
	local right = (along - up * along:Dot(up)).Unit
	return CFrame.fromMatrix(Vector3.new(x, y + lift, z), right, up)
end

-- Drops a standing thing INTO the water at its own position, sunk by `draft` below the
-- local surface. Keeps whatever rotation it already had.
--
-- Per-position rather than a flat height, because the surface is not flat: an object placed
-- at a fixed y stands proud in every trough it happens to fall in, which is the artefact
-- that made the first sunken pass look like furniture on a blue floor.
local function afloat(at: CFrame, draft: number): CFrame
	local spot = at.Position
	local y = waveSurface(spot.X, spot.Z)
	return (at - spot) + Vector3.new(spot.X, y - draft, spot.Z)
end

-- === The waterline ring, and what it must NOT be ===
--
-- This was a FILLED cylinder at 1.7 to 2.6 times the building's width, and it was wrong in
-- the way that is hardest to see from inside the code: it looked like a foam collar in
-- isolation and like a pale pad the building had been set on top of in the scene. Which is
-- the exact impression it was added to remove.
--
-- Look at a structure standing in calm water and there is no pale area around it at all --
-- a clean line where the two meet, and at most a narrow band of ripple hugging it. Foam
-- happens where water is being BROKEN, at surf and at piers in a current, not around
-- something merely standing there.
--
-- So it is an annulus, it hugs at 1.15 to 1.45 times the width instead of spreading to
-- 2.6, it is far more transparent, and fewer than half of the buildings get one at all.
--
-- No mesh, no ring. A cylinder fallback here would be the filled disc again, and nothing
-- is better than the artefact this exists to stop.
local seaRing: BasePart? = nil
local seaSurf: BasePart? = nil

-- === Everything pale moves, or none of it does ===
--
-- This used to be a closure inside sea(), so only the flecks, patches and glitter could be
-- animated. The sandbars and the waterline rings were built elsewhere and therefore sat
-- perfectly still -- and a static white shape beside a moving one does not read as calm
-- water, it reads as a decal someone forgot to hook up. The biggest pale objects in the
-- whole sea were the ones holding still.
--
-- Lives at module level now, with the folder as an upvalue, so a builder at any depth can
-- hand a part over without threading it through.
-- === Where the solid things are ===
--
-- The sea decoration had no idea. Sandbars were scattered on a ring at random angles and
-- towers on another ring at random angles, and nothing stopped the two picking the same
-- spot -- so an 870-stud surf crescent could be placed straight through a skyscraper. It
-- looked exactly as wrong as it was.
--
-- Every solid thing standing in the water registers a footprint circle here, and anything
-- laid ON the water asks before it commits. Circles rather than rectangles because these
-- are all roughly as wide as they are deep and the test runs a few hundred thousand times
-- at build; an exact overlap test would cost more and buy a stud or two.
type Footprint = { x: number, z: number, radius: number }
local occupied: { Footprint } = {}

local function occupy(x: number, z: number, radius: number)
	table.insert(occupied, { x = x, z = z, radius = radius })
end

-- True when nothing solid is within `margin` of this spot.
local function clearOf(x: number, z: number, margin: number): boolean
	for _, spot in ipairs(occupied) do
		local dx, dz = x - spot.x, z - spot.z
		local reach = spot.radius + margin
		if dx * dx + dz * dz < reach * reach then
			return false
		end
	end
	return true
end

-- Rejection sampling: hand back a clear spot, or nil after `tries`. Nil is a real outcome
-- rather than a failure -- 116 towers leave genuinely crowded stretches of sea, and the
-- honest answer there is one less sandbar rather than one placed inside a building.
local function findClear(near: number, far: number, margin: number, tries: number): (number?, number?)
	for _ = 1, tries do
		local angle = rng:NextNumber(0, math.pi * 2)
		local out = math.sqrt(rng:NextNumber(0, 1)) * (far - near) + near
		local x, z = math.cos(angle) * out, math.sin(angle) * out
		if clearOf(x, z, margin) then
			return x, z
		end
	end
	return nil, nil
end

-- ===== THE COAST, built =====
--
-- Where the sun is, as a bearing in plan, so the city can be put with its back to it. Read from
-- Lighting at build time rather than assumed: the level's palette sets the clock before this runs
-- (see Bootstrap), and working out Roblox's sun from ClockTime and latitude by hand is exactly the
-- kind of guess that lands the city in its own shadow.
local function sunBearing(): number
	local ok, direction = pcall(function()
		return game:GetService("Lighting"):GetSunDirection()
	end)
	if ok and typeof(direction) == "Vector3" and math.abs(direction.X) + math.abs(direction.Z) > 1e-3 then
		return math.atan2(direction.Z, direction.X)
	end
	return 0
end

-- A bearing measured from the city's centre line, wrapped to -pi..pi.
local function fromCity(angle: number): number
	return (angle - cityBearing + math.pi) % (math.pi * 2) - math.pi
end

-- How far out the waterline is at this offset from the city's centre line, or nil over open sea.
local function shoreAt(offset: number): number?
	return if math.abs(offset) <= CITY_HALF then SHORE_NEAR else nil
end

-- True on land at least `behind` studs back from the waterline.
local function onLand(x: number, z: number, behind: number): boolean
	local shore = shoreAt(fromCity(math.atan2(z, x)))
	return shore ~= nil and math.sqrt(x * x + z * z) >= shore + behind
end

-- A clear spot on land, `behind` studs back from the water.
local function landSpot(near: number, far: number, behind: number, margin: number, tries: number): (number?, number?)
	for _ = 1, tries do
		local angle = cityBearing + rng:NextNumber(-CITY_HALF, CITY_HALF)
		local out = math.sqrt(rng:NextNumber()) * (far - near) + near
		local x, z = math.cos(angle) * out, math.sin(angle) * out
		if onLand(x, z, behind) and clearOf(x, z, margin) then
			return x, z
		end
	end
	return nil, nil
end

-- A clear spot on the water, kept off the beach. `seaOnly` keeps it to the open sea beyond the
-- harbour walls, for the things that belong out in the glitter rather than in the bay.
local function waterSpot(near: number, far: number, margin: number, tries: number, seaOnly: boolean?): (number?, number?)
	for _ = 1, tries do
		local angle = rng:NextNumber(0, math.pi * 2)
		local out = math.sqrt(rng:NextNumber()) * (far - near) + near
		local shore = shoreAt(fromCity(angle))
		local wet = if seaOnly then shore == nil else (shore == nil or out < shore - BEACH_WET * 0.5 - margin * 0.5)
		if wet then
			local x, z = math.cos(angle) * out, math.sin(angle) * out
			if clearOf(x, z, margin) then
				return x, z
			end
		end
	end
	return nil, nil
end

-- A wedge that is scenery like everything else here. Roblox's WedgePart slopes from its back top
-- edge down to its FRONT (LookVector) bottom edge, so a ramp that rises away from the level is
-- one whose front faces the level.
local function ramp(parent: Instance, size: Vector3, cf: CFrame, colour: Color3): WedgePart
	local part = Instance.new("WedgePart")
	part.Size = size
	part.CFrame = cf
	part.Color = colour
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Parent = parent
	return part
end

local SAND = Color3.fromRGB(240, 218, 178)
local PROMENADE_STONE = Color3.fromRGB(242, 234, 220)
local GROUND = Color3.fromRGB(214, 206, 194)
local PARK = Color3.fromRGB(150, 190, 142)

-- THE LAND: a beach ramping up out of the bay, the promenade along its top, and the ground the
-- city stands on, in 4-degree slices round the crescent. Slices overlap a little so no seam of
-- sea shows between them, and every face of the ground is flat SmoothPlastic in one colour --
-- where two overlap they are the same surface, so there is nothing for them to fight over.
local function land(parent: Instance)
	local step = math.rad(4)
	for index = 0, math.floor(CITY_HALF * 2 / step) do
		local offset = -CITY_HALF + index * step
		local shore = shoreAt(offset)
		if not shore then
			continue
		end
		local angle = cityBearing + offset
		local out = Vector3.new(math.cos(angle), 0, math.sin(angle))
		-- Wide enough at a radius to meet its neighbours, with a little to spare.
		local function across(radius: number): number
			return 2 * radius * math.sin(step / 2) * 1.08 + 4
		end
		local function facing(radius: number, y: number): CFrame
			local at = out * radius + Vector3.new(0, y, 0)
			return CFrame.lookAt(at, Vector3.new(0, y, 0))
		end

		-- The beach, from under the lowest trough to the top of the land.
		local low = -40
		ramp(parent, Vector3.new(across(shore + BEACH_DRY), LAND_TOP - low, BEACH_WET + BEACH_DRY),
			facing(shore + (BEACH_DRY - BEACH_WET) / 2, (LAND_TOP + low) / 2), SAND)

		-- The promenade, a step up and paler, so the beach has an edge to stop at.
		local walk = shore + BEACH_DRY + PROMENADE / 2
		piece(parent, Vector3.new(across(shore + BEACH_DRY + PROMENADE), 10, PROMENADE),
			facing(walk, LAND_TOP - 3), PROMENADE_STONE, Enum.Material.SmoothPlastic)

		-- The ground, in three rings so the slices do not have to be as wide at the back as
		-- they need to be at the front.
		local from = shore + BEACH_DRY + PROMENADE
		for _, to in ipairs({ 2600, 4200, LAND_FAR }) do
			if to > from then
				piece(parent, Vector3.new(across(to), 80, to - from), facing((from + to) / 2, LAND_TOP - 40),
					GROUND, Enum.Material.SmoothPlastic)
				from = to
			end
		end
	end
end

-- THE HARBOUR WALLS at the two ends of the crescent: a pale quay from the wet edge of the beach
-- straight out to the far edge of the land, where the beach stops and the open sea starts. Laid
-- a little seaward of the last slice's edge, so it also covers the corners the slices leave there.
local QUAY = Color3.fromRGB(228, 222, 212)

local function quays(parent: Instance)
	local edge = CITY_HALF + math.rad(2)
	for _, side in ipairs({ -1, 1 }) do
		local angle = cityBearing + side * edge
		local along = Vector3.new(math.cos(angle), 0, math.sin(angle))
		-- Square to the wall and out toward the open sea, which lies at larger offsets either side.
		local seaward = Vector3.new(-along.Z, 0, along.X) * side
		local low, high = -70, LAND_TOP + 6
		local from = SHORE_NEAR - BEACH_WET
		while from < LAND_FAR do
			local to = math.min(from + 600, LAND_FAR)
			local mid = along * ((from + to) / 2) + seaward * 20 + Vector3.new(0, (low + high) / 2, 0)
			piece(parent, Vector3.new(60, high - low, to - from + 4), CFrame.lookAt(mid, mid + along),
				QUAY, Enum.Material.SmoothPlastic)
			from = to
		end
	end
end

-- A DECO HOTEL on the promenade: a pastel block, white eyebrow ledges over every floor band, and
-- a fin rising out of the middle of its front with a mast on top. The beachfront is the row that
-- tells you this is a shore, and it is the one row of buildings near enough to have any detail.
-- `at` stands at ground level with its front (LookVector) toward the bay.
local DECO = {
	Color3.fromRGB(244, 176, 164),
	Color3.fromRGB(168, 220, 200),
	Color3.fromRGB(166, 206, 232),
	Color3.fromRGB(246, 226, 160),
	Color3.fromRGB(204, 186, 230),
	Color3.fromRGB(250, 204, 170),
	Color3.fromRGB(246, 242, 234),
}
local TRIM = Color3.fromRGB(252, 250, 244)

local function decoHotel(parent: Instance, at: CFrame, width: number, depth: number, height: number)
	local body = DECO[rng:NextInteger(1, #DECO)]
	useVariant(piece(parent, Vector3.new(width, height + 12, depth), at * CFrame.new(0, (height - 12) / 2, 0),
		body, Enum.Material.Concrete), CONCRETE_VARIANT)
	local floors = math.clamp(math.floor(height / 46), 3, 7)
	for index = 1, floors do
		piece(parent, Vector3.new(width * 1.04, 3, depth * 1.12),
			at * CFrame.new(0, height * index / (floors + 1), -depth * 0.06), TRIM, Enum.Material.SmoothPlastic)
	end
	-- Dark glass between the eyebrows, down the whole front, so the ledges read as shading windows.
	piece(parent, Vector3.new(width * 0.9, height * 0.82, 2),
		at * CFrame.new(0, height * 0.46, -depth / 2 - 1), body:Lerp(Color3.fromRGB(40, 50, 70), 0.72),
		Enum.Material.Glass)
	local fin = height * rng:NextNumber(0.28, 0.45)
	piece(parent, Vector3.new(width * 0.2, height + fin, depth * 0.5),
		at * CFrame.new(0, (height + fin) / 2, -depth * 0.3), TRIM, Enum.Material.SmoothPlastic)
	pillar(parent, math.max(4, width * 0.035), fin * 0.5,
		at * CFrame.new(0, height + fin * 1.25, -depth * 0.3), TRIM, Enum.Material.Metal)
end

-- === Speed, not period ===
--
-- Every animated thing out here used to take a period straight out of a random range, and
-- its drift distance from a different one. Peak speed is 2*pi*drift/period, so those two
-- rolls multiplied into anything: flecks reached 94 studs a second and the surf 120, while
-- the sea sheet they sit on sways at 9.5. Small marks tearing across a slow surface is
-- exactly the wrong read -- it is the one thing that makes a still image of this look
-- calm and the moving version look frantic.
--
-- The period is derived from the distance now, so a mark that has further to go simply
-- takes longer over it and everything on the water shares a speed.
local function periodFor(drift: number, speed: number): number
	return math.pi * 2 * drift / math.max(speed, 0.01)
end

local swellFolder: Folder? = nil

-- `phase` is optional and almost always omitted: random phases are what stop a few hundred
-- marks pulsing in lockstep. It is passed explicitly only by things that MUST move together
-- -- see the sea tiles, where a phase difference of any size would open the seams.
-- `lockstep` marks a part that must be refreshed on EVERY frame rather than on the client's
-- rotating third. Only the sea tiles need it, and they need it absolutely: SeaService
-- updates a third of its parts per frame, so tiles landing in different thirds would sit a
-- frame apart from each other, and a frame apart is a seam. A fixed phase makes them agree
-- on where to be; lockstep makes them agree on when.
local function animate(
	part: BasePart,
	drift: Vector3,
	period: number,
	fade: number,
	phase: number?,
	lockstep: boolean?
)
	part:SetAttribute("Drift", drift)
	part:SetAttribute("Period", period)
	part:SetAttribute("Phase", phase or rng:NextNumber(0, math.pi * 2))
	if lockstep then
		part:SetAttribute("Lockstep", true)
	end
	part:SetAttribute("Fade", fade)
	if swellFolder then
		part.Parent = swellFolder
	end
end

local missingWarned: { [string]: boolean } = {}

local function noteMissingSeaMesh(name: string, what: string)
	if missingWarned[name] then
		return
	end
	missingWarned[name] = true
	warn(
		("[server] No '%s' in ReplicatedStorage.Assets.Backdrop, so %s are not drawn at all. "
			.. "Run blender/gen_sea.py and import it. Harmless, but silent until now."):format(name, what)
	)
end

local function collar(parent: Instance, x: number, z: number, diameter: number, alpha: number)
	local template = seaRing
	if not template then
		noteMissingSeaMesh("Sea_Ring", "waterline rings around the buildings")
		return
	end
	local ring = template:Clone()
	ring.Size = Vector3.new(diameter, math.clamp(diameter * 0.03, 2, 8), diameter)
	ring.CFrame = onWave(x, z, 0, clearance(diameter))
	ring.Anchored = true
	ring.CanCollide, ring.CanTouch, ring.CanQuery = false, false, false
	ring.CastShadow = false
	ring.Color = Color3.fromRGB(214, 234, 240)
	ring.Material = Enum.Material.SmoothPlastic
	ring.Transparency = alpha
	ring.Reflectance = 0.3
	ring.Parent = parent
	-- Mostly VERTICAL drift: a ring around a fixed building cannot slide sideways without
	-- leaving the building behind, but the water surging up and down its base is exactly
	-- what you see. The transparency swing carries most of the read.
	local surge = Vector3.new(rng:NextNumber(-4, 4), rng:NextNumber(5, 13), rng:NextNumber(-4, 4))
	animate(ring, surge, periodFor(surge.Magnitude, rng:NextNumber(2, 3.5)),
		rng:NextNumber(0.05, 0.11))
end

-- Surf: a crescent of broken foam on the windward side, washing in and back out.
local function surf(parent: Instance, x: number, z: number, diameter: number, bearing: number)
	local template = seaSurf
	if not template then
		noteMissingSeaMesh("Sea_Surf", "surf crescents on the sandbars")
		return
	end
	local crest = template:Clone()
	-- SCALED FROM THE TEMPLATE'S OWN PROPORTIONS. The crescent is roughly twice as deep as
	-- it is wide; forcing it into a square footprint stretches one axis and squashes the
	-- other, and what comes out is a fat ring rather than a crescent.
	local plan = math.max(template.Size.X, template.Size.Z)
	local ratio = diameter / plan
	crest.Size = Vector3.new(
		template.Size.X * ratio,
		math.clamp(diameter * 0.03, 2, 8),
		template.Size.Z * ratio
	)
	crest.CFrame = onWave(x, z, bearing, clearance(diameter))
	crest.Anchored = true
	crest.CanCollide, crest.CanTouch, crest.CanQuery = false, false, false
	crest.CastShadow = false
	crest.Color = Color3.fromRGB(242, 252, 252)
	crest.Material = Enum.Material.SmoothPlastic
	crest.Transparency = rng:NextNumber(0.30, 0.55)
	crest.Reflectance = 0.2
	crest.Parent = parent
	-- Washing RADIALLY, along the bearing it faces, with a big transparency swing. Surf is
	-- the one thing out here that should visibly appear and disappear rather than drift.
	local wash = Vector3.new(math.cos(bearing), 0, math.sin(bearing))
		* diameter * rng:NextNumber(0.05, 0.11)
	-- Surf gets the highest speed of anything out here, and it is still under the tiles'
	-- 9.5. Breaking water is the one thing that should look livelier than the sea around it.
	animate(crest, wash, periodFor(wash.Magnitude, rng:NextNumber(6, 9)),
		rng:NextNumber(0.10, 0.18))
end

-- === The skyline ===

-- Stacked footprints, bottom to top, as {widthFraction, depthFraction, heightFraction}.
-- The height fractions of a style sum to under 1, leaving the remainder for its crown.
local TOWER_STAGES: { [string]: { { number } } } = {
	-- The 1960s tower block: one unbroken extrusion, all its character in the ribbing.
	slab = { { 1.00, 1.00, 0.94 } },
	-- Art deco: three setbacks and a spire. The most obviously "skyscraper" silhouette
	-- there is, and the one that reads at the greatest distance.
	setback = { { 1.00, 1.00, 0.50 }, { 0.76, 0.76, 0.27 }, { 0.52, 0.52, 0.14 } },
	-- A tapering prism under a mast.
	prism = { { 1.00, 1.00, 0.60 }, { 0.68, 0.68, 0.30 } },
}
-- WEIGHTED AWAY FROM `slab`, which was two entries in five.
--
-- A slab is the one style whose whole silhouette is a rectangle, and a skyline that is
-- 40% rectangles reads as rectangles -- which is exactly the complaint the towers were
-- built to answer. Setbacks and spires are what make a shape unmistakably a building, so
-- they carry the ring and the slab is the occasional plain note between them.
local TOWER_STYLES = { "setback", "prism", "setback", "prism", "slab" }

-- A skyscraper.
--
-- What makes a box read as a building at four thousand studs is not detail, it is
-- SILHOUETTE and RIBBING. Setbacks and a crown give a profile no natural object has, and
-- vertical mullions give the face a scale -- without them a tower is a monolith, and the
-- eye has nothing to measure it against. Windows are pointless here; at this range a
-- window grid averages out to flat grey, which is exactly what the old plain columns
-- looked like.
local function tower(parent: Instance, at: CFrame, style: string, width: number, depth: number, height: number)
	-- CONTRAST HAS TO BE OVERBUILT AT THIS RANGE.
	--
	-- The first version lightened the body 35% toward white and darkened the ribs only
	-- halfway, which looked correct in isolation and arrived as uniform pale grey: 0.3
	-- density haze compresses everything toward the fog colour, so whatever contrast you
	-- author is roughly what you have LEFT after it, not what you start with. The body
	-- keeps its palette colour now and the ribs go most of the way to dark.
	-- ONE IN THREE IS GLASS: a dark curtain wall with light mullions, which catches the low sun
	-- and throws it back. A city of nothing but painted concrete reads as a model of a city.
	local glassy = rng:NextNumber() < 0.34
	local body = if glassy then Color3.fromRGB(66, 104, 124) else pick():Lerp(Color3.fromRGB(236, 238, 244), 0.12)
	local glass = if glassy then Color3.fromRGB(226, 230, 236) else body:Lerp(Color3.fromRGB(44, 52, 74), 0.78)

	local y = 0
	local topWidth, topDepth = width, depth
	for index, stage in ipairs(TOWER_STAGES[style]) do
		local w, d, h = width * stage[1], depth * stage[2], height * stage[3]
		-- Towers keep concrete, unless they are glass. They are the shell around the park.
		local stage = piece(parent, Vector3.new(w, h, d), at * CFrame.new(0, y + h / 2, 0), body,
			if glassy then Enum.Material.Glass else Enum.Material.Concrete)
		if glassy then
			stage.Reflectance = 0.3
		else
			useVariant(stage, CONCRETE_VARIANT)
		end

		-- Ribs on the bottom stage only, and each rib spans the FULL DEPTH of the tower so
		-- one part stripes both broad faces. Three parts per tower buys the mullion read
		-- on every side you can actually see it from; doing it per-face, per-stage would
		-- cost six times as much for a difference the haze eats.
		if index == 1 then
			for r = 1, 3 do
				piece(
					parent,
					Vector3.new(w * 0.14, h * 0.96, d * 1.03),
					at * CFrame.new((r - 2) * w * 0.31, y + h / 2, 0),
					glass,
					if glassy then Enum.Material.Concrete else Enum.Material.Glass
				)
			end
		end

		y += h
		topWidth, topDepth = w, d
	end

	-- The crown. A flat-topped tower reads as unfinished, and a skyline of flat tops reads
	-- as a bar chart.
	if style == "slab" then
		-- A parapet: a thin lip overhanging the roofline, plus the plant room every real
		-- tower block has on top of it.
		piece(parent, Vector3.new(width * 1.06, height * 0.02, depth * 1.06),
			at * CFrame.new(0, y, 0), body:Lerp(Color3.new(0, 0, 0), 0.12), Enum.Material.Concrete)
		piece(parent, Vector3.new(width * 0.42, height * 0.05, depth * 0.42),
			at * CFrame.new(0, y + height * 0.025, 0), body, Enum.Material.Concrete)
	elseif style == "setback" then
		piece(parent, Vector3.new(topWidth * 0.30, height * 0.09, topDepth * 0.30),
			at * CFrame.new(0, y + height * 0.045, 0), body, Enum.Material.Concrete)
		pillar(parent, topWidth * 0.10, height * 0.11,
			at * CFrame.new(0, y + height * 0.145, 0), Color3.fromRGB(206, 204, 198), Enum.Material.Metal)
	else
		pillar(parent, topWidth * 0.07, height * 0.16,
			at * CFrame.new(0, y + height * 0.08, 0), Color3.fromRGB(206, 204, 198), Enum.Material.Metal)
	end
end

-- The skyline as a whole: a deep BAND rather than a ring, and ON LAND now.
--
-- Depth is the entire point. Towers all at one radius read as a fence of posts, however well
-- modelled each one is; towers at scattered distances overlap each other, and the overlaps are
-- what say "city" -- you are seeing past the front row to more of it, and the ones behind are
-- already fading into the haze.
--
-- `behind` keeps each band back from the beach, so the promenade and the hotels stay the front
-- row. The first version stood these in the sea, a fifth of them "drowned" to half their height;
-- on a coast that reads as a flood rather than a city, so that is gone with the water under them.
local function skyline(
	parent: Instance,
	count: number,
	near: number,
	far: number,
	behind: number,
	widthLow: number,
	widthHigh: number,
	heightLow: number,
	heightHigh: number
)
	for _ = 1, count do
		local width = rng:NextNumber(widthLow, widthHigh)
		local x, z = landSpot(near, far, behind, width * 0.8, 60)
		if not x or not z then
			continue
		end
		local height = rng:NextNumber(heightLow, heightHigh)
		-- Faced squarely at the middle, so the ribbed broad side is the side you see, and set a
		-- little into the ground so no foundation line shows.
		local base = LAND_TOP - 12
		local at = CFrame.lookAt(Vector3.new(x, base, z), Vector3.new(0, base, 0))
		tower(parent, at, TOWER_STYLES[rng:NextInteger(1, #TOWER_STYLES)], width,
			width * rng:NextNumber(0.55, 1.0), height + 12)
		occupy(x, z, width * 0.72)
	end
end

-- A blank facade with a grid of darker panels: the empty-office, empty-mall silhouette.
-- The grid is what makes it architecture rather than a slab -- a regular repeat at a
-- scale that implies floors, and therefore implies a building nobody is in.
local function facade(parent: Instance, at: CFrame, width: number, height: number)
	local body = pick()
	-- Standing on the land now, sunk a little so no foundation line shows.
	useVariant(piece(parent, Vector3.new(width, height + 12, 42),
		at * CFrame.new(0, LAND_TOP - 12 + (height + 12) / 2, 0), body, Enum.Material.Concrete),
		CONCRETE_VARIANT)
	occupy(at.Position.X, at.Position.Z, width * 0.55)

	-- Deliberately coarse. At this distance the haze eats anything finer, so extra panels
	-- cost parts and buy nothing.
	local cols = math.max(3, math.floor(width / 150))
	local rows = math.max(3, math.floor(height / 140))
	local panel = body:Lerp(Color3.fromRGB(70, 78, 92), 0.5)
	for c = 1, cols do
		for r = 1, rows do
			-- Some windows missing, some lit. An unbroken grid reads as a texture; the
			-- gaps are what make it a building with rooms in it.
			local roll = rng:NextNumber()
			if roll > 0.22 then
				local lit = roll > 0.93
				piece(
					parent,
					Vector3.new(width / cols * 0.5, height / rows * 0.42, 8),
					at * CFrame.new(-width / 2 + (c - 0.5) * (width / cols), LAND_TOP + (r - 0.35) * (height / rows), -24),
					if lit then Color3.fromRGB(248, 244, 214) else panel,
					if lit then Enum.Material.Neon else Enum.Material.Glass
				)
			end
		end
	end
end

-- The floor of wherever this is: a checkerboard receding into the haze.
--
-- Checkerboard because it is the single strongest liminal signal there is -- every
-- reference has one, and it carries the read at a distance where nothing else survives
-- the fog.
--
-- The two tones used to be a hair apart, on the theory that it should register as pattern
-- rather than as a chessboard. Through the haze, 184 studs below eye level, that arrived
-- as a single flat sheet of grey and the floor may as well not have been a checkerboard
-- at all. Same lesson as the towers: author the contrast you want to survive the fog, not
-- the contrast you want up close.
-- === The sea ===
--
-- Roblox terrain water animates and would look better up close, and it is the wrong tool
-- here by two orders of magnitude: terrain is 4-stud voxels, so covering this radius would
-- be tens of millions of them, replicated to every client, for a surface that is 700 studs
-- below you and never reachable. Sixty-odd transparent parts do the same job.
--
-- Transparency is what makes it water rather than a blue floor. You see the checkerboard
-- through it, dimmed and coloured, and that read -- a patterned bottom under a tinted
-- surface -- is worth more than waves at this distance.
local function sea(parent: Instance, reach: number, tile: number, waveMesh: BasePart?, foamMesh: BasePart?)
	-- ONE COLOUR FOR EVERY TILE, and this is what made the grid visible.
	--
	-- Each tile used to take its own random lerp between a deep and a shallow blue, on the
	-- theory that it would read as light and dark patches. It does not: the patches are
	-- square, they are 1600 studs across, and they line up -- so what you see is the grid
	-- the sea is built from. Variation has to come from something whose edges do NOT fall
	-- on tile boundaries, which is what the flecks and patches below are for.
	--
	-- DEEPER AND MORE SATURATED than it looks like it should be at ground level. Fog
	-- blends everything toward the horizon colour with distance, so a mid-tone blue at
	-- 2000 studs arrives as pale lavender. Contrast has to be spent before the fog takes
	-- its cut, which is the same lesson the towers taught two rounds ago.
	local surface = Color3.fromRGB(46, 106, 146)
	local span = math.ceil(reach / tile)
	for gx = -span, span do
		for gz = -span, span do
			local x, z = gx * tile, gz * tile
			if math.sqrt(x * x + z * z) <= reach then
				local water: BasePart
				if waveMesh then
					-- A DISPLACED MESH, which is the only thing here that makes water look
					-- like water rather than like a painted floor. Every tile is the same
					-- MeshId, so Roblox instances them: one mesh drawn 45 times.
					--
					-- The reason it works is normals, not silhouette. A flat plane returns
					-- one lighting answer across its whole surface no matter what is drawn
					-- on it; a surface with slopes returns a different one per slope, and at
					-- 0.58 reflectance a few degrees of tilt swings the reflected sky a long
					-- way. That variation is what the eye reads as a moving liquid.
					local shaped = waveMesh:Clone()
					shaped.Size = Vector3.new(tile, SEA_TILE_HEIGHT, tile)
					shaped.Anchored = true
					shaped.CanCollide, shaped.CanTouch, shaped.CanQuery = false, false, false
					shaped.CastShadow = false
					shaped.Color = surface
					shaped.Material = Enum.Material.SmoothPlastic
					shaped.CFrame = CFrame.new(x, 0, z)
					shaped.Parent = parent
					water = shaped
				else
					water = piece(
						parent,
						Vector3.new(tile, 6, tile),
						-- Tiles BUTT rather than overlap: two stacked transparent parts
						-- double up and the seam becomes a visible line.
						CFrame.new(x, 0, z),
						surface,
						Enum.Material.SmoothPlastic
					)
				end
				-- OPAQUE, and this is what kills the mosaic.
				--
				-- 45 transparent plates each sort and shade independently, so every shared
				-- edge picks up a slightly different value and the grid draws itself back
				-- in however uniform the colour is. Opaque, identical, butted parts render
				-- as one surface. It also matches the reference: a real sea seen from above
				-- is not see-through, and the pool floor it was revealing is gone with it.
				water.Transparency = 0
				-- The shine. Reflectance blends the part toward the skybox, so this is what
				-- puts the pink-to-blue gradient onto the water and makes it read as a wet
				-- surface rather than as blue floor. It is also why the sea changes colour
				-- as you turn: that is the sky moving across it, and it is most of the
				-- reason a flat plane can pass for water at all.
				water.Reflectance = 0.58

				-- === The tiles move too, and ONLY in perfect unison ===
				--
				-- These are 1600-stud plates butted edge to edge, and for twelve rounds the
				-- rule here was that they must never move: a tile sliding independently
				-- tears its own seams open, which is the artefact the uniform colour and the
				-- opaque surface were both introduced to remove.
				--
				-- Identical drift, identical period, and an explicitly FIXED PHASE of zero
				-- sidesteps that entirely. Every tile is displaced by exactly the same vector
				-- on every frame, so the whole sheet translates as one body and no two
				-- neighbours ever disagree about where their shared edge is. The seams are as
				-- safe in motion as they were standing still.
				--
				-- Deliberately small. 14 studs of sway against wavelengths of 61 to 297 is a
				-- surface breathing, not a tide -- and the buildings do not move with it, so
				-- the water visibly slides past them, which is the part that sells it.
				animate(water, Vector3.new(14, 3.5, 9), 11, 0, 0, true)
			end
		end
	end

	-- === Swell, patches and glitter: the detail that hides the grid, and moves ===
	--
	-- All three are scattered by ANGLE AND RADIUS rather than by cell, so nothing about
	-- them lines up with the tiles underneath. sqrt() on the radius roll is not decoration
	-- -- without it the samples bunch toward the middle, because a ring at radius r has
	-- area proportional to r and a uniform roll does not know that.
	--
	-- They live in their own folder because the CLIENT ANIMATES THEM. The base tiles never
	-- move: 45 huge plates sliding independently would tear their own seams open, which is
	-- the exact artefact the uniform colour was meant to remove. Motion belongs on the
	-- overlay, where a part drifting 80 studs has no neighbour to misalign with -- and from
	-- 700 studs up, drifting swell IS what moving water looks like. Individual wavelets are
	-- far below the resolution you are viewing this at.
	--
	-- Each part carries its own drift vector, period and phase as attributes, so the motion
	-- is authored here with everything else and the client is a dumb player of it.

	-- SIX TINTS, not one. A single pale blue at 700 flecks reads as a stencil pattern; real
	-- water is mottled because each facet reflects a different part of the sky, so the
	-- flecks run from near-white glare through mid blue to a green cast and two shades
	-- DARKER than the sea. The dark ones matter most -- highlights alone read as spray.
	local TINTS = {
		Color3.fromRGB(216, 240, 244),
		Color3.fromRGB(178, 222, 232),
		Color3.fromRGB(142, 202, 218),
		Color3.fromRGB(156, 208, 196),
		Color3.fromRGB(74, 134, 172),
		Color3.fromRGB(40, 96, 134),
	}
	local pale = Color3.fromRGB(168, 214, 226)
	local deep = Color3.fromRGB(34, 78, 112)
	local glint = Color3.fromRGB(255, 250, 232)

	local animated = animate

	-- TWO SCALES, and the small one is doing the real work.
	--
	-- There used to be 80 streaks up to 2100 studs long at 0.62 transparency, and at that
	-- size a rectangle reads as exactly what it is: a plank lying on the water. Hard
	-- straight edges are the other half of the mosaic. Broad tonal drift wants to be almost
	-- invisible individually, and the ripple texture wants many small marks rather than a
	-- few big ones -- the same reason a stipple reads as tone and a stripe does not.
	-- One foam mark, riding the wave it sits on.
	local function streak(baseLong: number, baseWide: number, low: number, high: number, drift: number, speed: number)
		local heading = rng:NextNumber(0, math.pi * 2)
		-- Retried a few times against the buildings, then abandoned. A mark whose centre is
		-- inside a tower is not merely clipping -- it is inside an opaque box, so most of it
		-- never draws and the part that does is a sliver poking out of a wall.
		-- FOURTEEN TRIES, not five. The buildings and props between them exclude roughly a
		-- third of the sea once their margins are counted, so five tries abandoned about one
		-- fleck in eight -- a visible thinning of the foam anywhere near the city, which is
		-- the one place foam ought to gather. Each try is 205 distance comparisons and this
		-- runs once at build; the retries are free and the missing marks were not.
		local x, z = findClear(0, reach, baseLong * 1.2, 14)
		if not x or not z then
			return
		end
		local out = math.sqrt(x * x + z * z)

		-- SIZE GROWS WITH DISTANCE, and this is not a stylistic choice.
		--
		-- Roblox culls geometry by SCREEN size, so a 30-stud fleck at 5000 studs is dropped
		-- entirely -- the far sea would go bare while the near sea stayed busy. Scaling with
		-- range keeps every fleck at roughly the same size ON SCREEN, which is both what
		-- survives culling and what perspective would do anyway.
		-- The near end used to bottom out at 0.4, which made a 16-stud fleck 6 studs across
		-- at the closest range -- half a degree of arc, four pixels, gone. The floor matters
		-- more than the ceiling here.
		-- OVERCORRECTED ONCE IN EACH DIRECTION. At 0.4 the near flecks were four pixels
		-- and invisible; at 0.9 with a 2.1 slope the far ones reached 600 studs across and
		-- merged into solid white pads that the towers appeared to be standing on. The
		-- ceiling matters as much as the floor: these have to stay separate marks.
		local grow = 0.8 + (out / reach) * 1.6
		local long, wide = baseLong * grow, baseWide * grow
		local tint = TINTS[rng:NextInteger(1, #TINTS)]

		-- Sitting IN the surface, not above it. `lift` is small and positive so a mark
		-- never sinks through a crest, but it is nothing like the fixed 34-stud altitude
		-- the flecks used to hover at regardless of what the water was doing underneath.
		local lift = clearance(long)
		local pose = onWave(x, z, heading, lift)

		local part: BasePart
		if foamMesh then
			-- An irregular lens instead of a rectangle. Foam has no straight edges and no
			-- corners, and at 900 marks the repeated silhouette of a box is the thing that
			-- gives the whole surface away as stamped.
			local shaped = foamMesh:Clone()
			-- CLAMPED, not just floored. Thickness scaled with length and nothing stopped
			-- it, so a 1920-stud swell streak came out 96 studs thick -- a solid translucent
			-- slab the size of a building, which is exactly what it looked like floating over
			-- the sea. A foam mark is thin at every length; only its footprint grows.
			shaped.Size = Vector3.new(long, math.clamp(long * 0.05, 3, 10), wide)
			shaped.Anchored = true
			shaped.CanCollide, shaped.CanTouch, shaped.CanQuery = false, false, false
			shaped.CastShadow = false
			shaped.Color = tint
			shaped.Material = Enum.Material.SmoothPlastic
			shaped.CFrame = pose
			shaped.Parent = parent
			part = shaped
		else
			part = piece(parent, Vector3.new(long, 4, wide), pose, tint, Enum.Material.SmoothPlastic)
		end
		part.Transparency = rng:NextNumber(low, high)
		part.Reflectance = 0.5

		-- === Drift measured ALONG the surface, which is what makes it ride ===
		--
		-- The client only knows how to add `drift * sin(t)` to a stored CFrame, and that is
		-- deliberately all it knows -- 354 parts a frame cannot afford to re-evaluate twelve
		-- sines each. So the vertical component is baked in HERE: sample the wave at both
		-- ends of the mark's travel and hand over the chord between them. The result climbs
		-- and falls across the swell as it slides, at no client cost whatsoever.
		--
		-- Drifting ACROSS its own length, not along it. A streak sliding lengthwise is
		-- invisible -- it just overlaps where it already was.
		local across = Vector3.new(math.sin(heading), 0, math.cos(heading)) * drift
		local aheadY = waveSurface(x + across.X, z + across.Z)
		local behindY = waveSurface(x - across.X, z - across.Z)
		animated(
			part,
			Vector3.new(across.X, (aheadY - behindY) / 2, across.Z),
			periodFor(drift, speed),
			-- Fade halved as well. A transparency swing IS motion as far as the eye is
			-- concerned, and a fast one on a thousand marks reads as static rather than as
			-- water.
			rng:NextNumber(0.015, 0.05)
		)
	end

	-- Broad swell: barely there, just enough to stop the plane reading as one flat tone.
	for _ = 1, 90 do
		streak(rng:NextNumber(300, 800), rng:NextNumber(60, 150),
			0.82, 0.94, rng:NextNumber(40, 110), rng:NextNumber(3.5, 6.5))
	end
	-- The fleck layer: an order of magnitude smaller and denser than the planks it
	-- replaces. Individually none of these is legible, which is the point -- many small
	-- marks become texture, a few big ones stay objects.
	for _ = 1, 900 do
		streak(rng:NextNumber(35, 120), rng:NextNumber(9, 32),
			0.45, 0.82, rng:NextNumber(8, 30), rng:NextNumber(4.5, 8))
	end

	for _ = 1, 44 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local out = math.sqrt(rng:NextNumber(0, 1)) * reach
		local patchWidth = rng:NextNumber(420, 1300)
		local patch = pillar(
			parent,
			patchWidth,
			5,
			onWave(math.cos(angle) * out, math.sin(angle) * out, 0, clearance(patchWidth)),
			deep,
			Enum.Material.SmoothPlastic
		)
		patch.Transparency = rng:NextNumber(0.68, 0.86)
		patch.Reflectance = 0.3
		local wander = Vector3.new(rng:NextNumber(-70, 70), 0, rng:NextNumber(-70, 70))
		animated(patch, wander, periodFor(wander.Magnitude, rng:NextNumber(2, 4)),
			rng:NextNumber(0.03, 0.08))
	end

	-- === Sun glitter ===
	--
	-- A wedge of bright specks running out along ONE bearing, dense near the horizon end
	-- and sparse close in. This is the strongest realism cue available on a flat plane:
	-- real water is only bright where it happens to be angled at the sun, so the glare is
	-- a path rather than an even sheen, and a path is something Reflectance alone will
	-- never produce because it has no idea where the sun is.
	--
	-- The bearing is fixed rather than read from the sun's position: Lighting's ClockTime
	-- moves, this does not, and a glitter path that swings around the horizon during play
	-- would be far more distracting than one that is slightly off.
	local bearing = 2.1
	for _ = 1, 48 do
		local out = math.sqrt(rng:NextNumber(0.02, 1)) * reach
		-- The wedge NARROWS with distance, which is what perspective does to a path
		-- running away from you, and is why this reads as a corridor of light.
		local spread = rng:NextNumber(-0.30, 0.30) * (1 - out / reach * 0.65)
		local angle = bearing + spread
		local size = rng:NextNumber(60, 300)
		local speck = piece(
			parent,
			Vector3.new(size, 4, size * rng:NextNumber(0.25, 0.7)),
			onWave(math.cos(angle) * out, math.sin(angle) * out, rng:NextNumber(0, math.pi * 2), 3),
			glint,
			Enum.Material.Neon
		)
		speck.Transparency = rng:NextNumber(0.45, 0.8)
		-- Fast and twitchy, unlike the swell. Glitter is the surface catching the light for
		-- an instant, so it wants a short period and a big transparency swing.
		-- Glitter was the worst offender at 112 studs a second, and the fastest transparency
		-- swing on top of that. Sun on water does flicker -- but it flickers in PLACE, so the
		-- brightness carries it and the travel should be almost nothing.
		local shimmer = Vector3.new(rng:NextNumber(-25, 25), 0, rng:NextNumber(-25, 25))
		animated(speck, shimmer, periodFor(shimmer.Magnitude, rng:NextNumber(2.5, 5)),
			rng:NextNumber(0.09, 0.18))
	end
end

-- A sandbar breaking the surface, with its shallow shelf spreading out underwater.
--
-- The shelf is the important half. An island that meets the water at a hard edge looks
-- like a coin dropped on a table; a pale disc spreading out under the surface reads as
-- depth, and depth is the entire cue that says the blue plane is water.
local function sandbar(parent: Instance, at: CFrame, diameter: number)
	-- Dropped onto the wave like everything else, so a sandbar in a trough sits lower than
	-- one on a crest instead of every island floating at exactly the same altitude.
	local waterY = waveSurface(at.Position.X, at.Position.Z)
	at = CFrame.new(at.Position.X, waterY, at.Position.Z)
	-- Warm sand against a turquoise shelf, which is the one high-contrast pairing on the
	-- whole horizon. Everything else out there is a pastel against a pastel; this is what
	-- gives the eye something to land on when it looks down.
	-- ON TOP of the water, not under it. The shelf used to sit at -2 and show through a
	-- transparent sea; with an opaque one it would simply be buried, so shallows are now
	-- painted onto the surface the same way the ripples are.
	-- The shelf was 2.1x the island and barely transparent, which made it the largest pale
	-- object in the sea and a completely static one. Tighter and fainter.
	local shelf = pillar(parent, diameter * 1.45, 8,
		at * CFrame.new(0, clearance(diameter * 1.45), 0),
		Color3.fromRGB(150, 214, 210), Enum.Material.SmoothPlastic)
	shelf.Transparency = 0.46
	pillar(parent, diameter, 26, at * CFrame.new(0, 6, 0),
		Color3.fromRGB(242, 228, 186), Enum.Material.Sand)
	-- SURF, not a collar. An even pale ring around an island is a bathtub; breaking water
	-- piles up on the side it arrives from and leaves the lee almost clear. Two crescents
	-- on neighbouring bearings, so the break has some width to it.
	local bearing = rng:NextNumber(0, math.pi * 2)
	surf(parent, at.Position.X, at.Position.Z, diameter * rng:NextNumber(1.1, 1.4), bearing)
	if rng:NextNumber() < 0.6 then
		surf(parent, at.Position.X, at.Position.Z,
			diameter * rng:NextNumber(0.95, 1.25), bearing + rng:NextNumber(-0.8, 0.8))
	end
end

-- === Modelled props ===
--
-- Shapes the primitives could not be: a mushroom, a gabled roof, a canopy. Generated by
-- blender/gen_backdrop.py and imported into ReplicatedStorage/Assets/Backdrop.
--
-- MISSING PROPS ARE NOT AN ERROR. The folder may not exist yet, or may be half imported,
-- and the backdrop still has to draw -- so anything absent falls back to a primitive
-- object. That keeps the horizon populated mid-import instead of emptying out, and it
-- means a typo'd name degrades rather than breaks.
local propFolder: Instance? = nil
local propChecked = false
local propCache: { [string]: BasePart } = {}
local propMissing: { [string]: boolean } = {}

local function propTemplate(name: string): BasePart?
	if not propChecked then
		propChecked = true
		local assets = ReplicatedStorage:FindFirstChild("Assets")
		propFolder = assets and assets:FindFirstChild("Backdrop")
		if not propFolder then
			warn(
				"[server] No ReplicatedStorage.Assets.Backdrop folder; the horizon will use "
					.. "primitive shapes only. Run blender/gen_backdrop.py and import the Backdrop_* OBJs."
			)
		end
	end
	if propCache[name] then
		return propCache[name]
	end
	if not propFolder or propMissing[name] then
		return nil
	end
	local found = propFolder:FindFirstChild(name)
	-- The importer commonly wraps a mesh in a Model, same as every other asset here.
	if found and not found:IsA("BasePart") then
		found = found:FindFirstChildWhichIsA("BasePart", true)
	end
	if found and found:IsA("BasePart") then
		propCache[name] = found
		return found
	end
	propMissing[name] = true
	return nil
end

-- Places a modelled prop, or returns false so the caller can fall back.
local function prop(parent: Instance, name: string, at: CFrame, scale: number, colour: Color3?): boolean
	local template = propTemplate(name)
	if not template then
		return false
	end
	local copy = template:Clone()
	-- Sized from the template's own dimensions, so a prop can be re-generated at a
	-- different size in Blender without every call site here needing to know.
	copy.Size = template.Size * scale

	-- PLACED BY ITS BASE, not its centre. This was the bug that drowned the aquapark.
	--
	-- A MeshPart's CFrame is the middle of its bounding box, so `copy.CFrame = at` put HALF
	-- of every prop below the point it was asked to stand at -- and every one of these is
	-- asked to stand at the waterline. A slide tower sank 50% before its own draft was
	-- applied on top, and the deeper the draft the more it looked like a deliberate choice
	-- rather than an off-by-a-half.
	--
	-- The primitive builders never had this problem: lamp, plinth, pylon and the rest all
	-- build UPWARD from the CFrame they are given, which is why they sat correctly beside
	-- meshes that did not.
	copy.CFrame = at * CFrame.new(0, copy.Size.Y / 2, 0)
	copy.Anchored = true
	copy.CanCollide = false
	copy.CanTouch = false
	copy.CanQuery = false
	copy.CastShadow = false
	if colour then
		copy.Color = colour
	end
	copy.Parent = parent
	return true
end

-- The plan size and height of a prop, before scaling. Zero when it is not imported.
local function propSpan(name: string): (number, number)
	local template = propTemplate(name)
	if not template then
		return 0, 0
	end
	return math.max(template.Size.X, template.Size.Z), template.Size.Y
end

-- Roblox's own volumetric clouds for the sky itself: one instance, effectively free, and
-- it covers the whole sky in a way a few hundred spheres never could.
local function ensureSkyClouds()
	local terrain = workspace:FindFirstChildOfClass("Terrain")
	if not terrain or terrain:FindFirstChildOfClass("Clouds") then
		return
	end
	local clouds = Instance.new("Clouds")
	clouds.Cover = 0.62
	clouds.Density = 0.55
	clouds.Color = Color3.fromRGB(248, 246, 246)
	clouds.Parent = terrain
end

-- Where to centre the horizon.
--
-- Levels run along +Z from zero, so their midpoint is NOT the world origin -- centring on
-- the origin would put the level at one edge of the backdrop and you would walk toward
-- one side of it for the whole run. Measured from the built level rather than passed in,
-- so this stays correct as level lengths change and nothing has to be kept in sync.
local function levelCentre(): Vector3
	local levels = workspace:FindFirstChild("Levels")
	if not levels then
		return Vector3.new(0, 0, 0)
	end
	local minX, maxX = math.huge, -math.huge
	local minZ, maxZ = math.huge, -math.huge
	local found = false
	for _, item in ipairs(levels:GetDescendants()) do
		if item:IsA("BasePart") then
			local at = item.Position
			found = true
			minX, maxX = math.min(minX, at.X), math.max(maxX, at.X)
			minZ, maxZ = math.min(minZ, at.Z), math.max(maxZ, at.Z)
		end
	end
	if not found then
		return Vector3.new(0, 0, 0)
	end
	return Vector3.new((minX + maxX) / 2, 0, (minZ + maxZ) / 2)
end


local function build(): Model
	local model = Instance.new("Model")
	model.Name = "Backdrop"
	-- Footprints from any earlier build in this server would stand in for buildings that are gone.
	table.clear(occupied)

	-- Resolved before any ring is drawn. Held in an upvalue rather than passed down because
	-- collars are raised from several builders at several depths, and threading one optional
	-- template through all of them buys nothing.
	swellFolder = Instance.new("Folder")
	swellFolder.Name = "Swell"
	swellFolder.Parent = model

	seaRing = propTemplate("Sea_Ring")
	seaSurf = propTemplate("Sea_Surf")

	-- THE CITY TURNS ITS BACK TO THE SUN, so every tower is lit on the side you see and the sun
	-- goes down over open water, which is where the glitter is.
	cityBearing = sunBearing() + math.pi

	-- === The land, the beach and promenade along its edge, and the harbour walls at its ends ===
	land(model)
	quays(model)

	-- Parks first, so the towers leave room for them: green in among the pastel, which is most of
	-- what makes a skyline read as a place people live rather than a stack of blocks.
	for _ = 1, 12 do
		local wide = rng:NextNumber(220, 460)
		local x, z = landSpot(1700, 4600, 480, wide * 0.6, 40)
		if x and z then
			pillar(model, wide, 6, CFrame.new(x, LAND_TOP + 2, z), PARK, Enum.Material.SmoothPlastic)
			occupy(x, z, wide * 0.5)
		end
	end

	-- === The beachfront: deco hotels in a row facing the bay, palms along the promenade ===
	--
	-- Hotels every six degrees or so along the whole crescent, set back behind the promenade,
	-- nudged in and out so the row is a street rather than a wall. Well below eye level: the level is 700 up, and these are 150 to 340 tall, so you
	-- look DOWN at the beachfront and UP at the towers behind it.
	local hotelStep = math.rad(5.8)
	local hotelEdge = CITY_HALF - math.rad(4)
	local offset = -hotelEdge
	while offset <= hotelEdge do
		local shore = shoreAt(offset)
		if shore then
			local width = rng:NextNumber(150, 240)
			local depth = rng:NextNumber(110, 170)
			local reach = shore + BEACH_DRY + PROMENADE + 50 + depth / 2 + rng:NextNumber(0, 60)
			local angle = cityBearing + offset + rng:NextNumber(-0.012, 0.012)
			local x, z = math.cos(angle) * reach, math.sin(angle) * reach
			if clearOf(x, z, width * 0.5) then
				decoHotel(model, CFrame.lookAt(Vector3.new(x, LAND_TOP, z), Vector3.new(0, LAND_TOP, 0)),
					width, depth, rng:NextNumber(150, 340))
				occupy(x, z, width * 0.6)
			end
		end
		offset += hotelStep * rng:NextNumber(0.85, 1.15)
	end

	-- Palms on the seaward edge of the promenade, sized from the template so they come out about
	-- 150 studs tall whatever size the mesh was exported at. Nothing is drawn if the palm has not
	-- been imported.
	local _, palmTall = propSpan("Backdrop_Palm")
	if palmTall > 0 then
		local palmEdge = CITY_HALF - math.rad(2)
		local at = -palmEdge
		while at <= palmEdge do
			local shore = shoreAt(at)
			if shore then
				local reach = shore + BEACH_DRY + 24
				local angle = cityBearing + at
				prop(model, "Backdrop_Palm",
					CFrame.new(math.cos(angle) * reach, LAND_TOP, math.sin(angle) * reach)
						* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
					rng:NextNumber(130, 175) / palmTall, Color3.fromRGB(176, 212, 170))
			end
			at += math.rad(2.6) * rng:NextNumber(0.8, 1.2)
		end
	end

	-- === The city behind them: three bands of towers, deeper and taller going back ===
	--
	-- Denser than the first version's 46 all the way round, because they only stand on the
	-- crescent now: a skyline is its overlaps, and a thin one is a row of posts.
	skyline(model, 14, 1500, 2500, 480, 110, 190, 700, 1300)
	skyline(model, 20, 2500, 3800, 480, 150, 260, 1100, 2200)
	skyline(model, 22, 3800, 5500, 480, 190, 340, 1500, 3000)

	-- Facades among them, turned toward the bay.
	for _ = 1, 9 do
		local width = rng:NextNumber(480, 900)
		local x, z = landSpot(1700, 3200, 520, width * 0.6, 40)
		if x and z then
			facade(model, CFrame.lookAt(Vector3.new(x, 0, z), Vector3.new(0, 0, 0)), width, rng:NextNumber(750, 1600))
		end
	end

	-- === The aquapark, in the bay ===
	--
	-- In the water between the level and the beach, so it is the subject of the view straight
	-- down, and smaller than it was out on the open sea: these stand in a bay 1150 studs across,
	-- and at the old sizes three of them would have filled it. From 800 out, clear of the dive's
	-- landing circle (about 414 out from the middle, 300 across the radius), so nobody splashes
	-- down through a flume.
	local aquapark = {
		{ mesh = "Backdrop_SlideTower", tint = Color3.fromRGB(214, 232, 240) },
		{ mesh = "Backdrop_Flume", tint = Color3.fromRGB(176, 214, 226) },
		{ mesh = "Backdrop_SplashBucket", tint = Color3.fromRGB(232, 226, 196) },
		{ mesh = "Backdrop_SlideTower", tint = Color3.fromRGB(228, 206, 214) },
		{ mesh = "Backdrop_LifeguardChair", tint = Color3.fromRGB(238, 232, 214) },
		{ mesh = "Backdrop_Flume", tint = Color3.fromRGB(206, 224, 208) },
		{ mesh = "Backdrop_DivingPlatform", tint = Color3.fromRGB(222, 228, 232) },
		{ mesh = "Backdrop_MushroomFountain", tint = Color3.fromRGB(210, 232, 234) },
		{ mesh = "Backdrop_PlayStructure", tint = Color3.fromRGB(226, 208, 196) },
		{ mesh = "Backdrop_PirateShip", tint = Color3.fromRGB(206, 186, 164) },
		{ mesh = "Backdrop_WaveSlide", tint = Color3.fromRGB(184, 220, 216) },
		{ mesh = "Backdrop_SplashBucket", tint = Color3.fromRGB(220, 206, 226) },
		{ mesh = "Backdrop_PlayStructure", tint = Color3.fromRGB(202, 216, 232) },
		{ mesh = "Backdrop_WaveSlide", tint = Color3.fromRGB(224, 210, 216) },
	}
	for _, entry in ipairs(aquapark) do
		local wide = propSpan(entry.mesh)
		if wide > 0 then
			local scale = rng:NextNumber(3.5, 6.5)
			local radius = wide * scale * 0.5
			local x, z = waterSpot(800, 1080, radius, 40)
			if x and z then
				local spun = CFrame.new(x, 0, z) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
				local placed = afloat(spun, rng:NextNumber(6, 24))
				if prop(model, entry.mesh .. "_Detail", placed, scale, entry.tint)
					or prop(model, entry.mesh, placed, scale, entry.tint)
				then
					occupy(x, z, radius)
					collar(model, x, z, wide * scale * rng:NextNumber(1.05, 1.3), rng:NextNumber(0.66, 0.9))
				end
			end
		end
	end

	-- Float rings and lane ropes lie ON the water, in the bay and out to sea.
	for _, spec in ipairs({
		{ mesh = "Backdrop_FloatRing", count = 14, near = 820, far = 3200, low = 2.5, high = 6.0, width = 58 },
		{ mesh = "Backdrop_LaneRope", count = 9, near = 860, far = 3600, low = 3.0, high = 7.5, width = 136 },
	}) do
		for _ = 1, spec.count do
			local scale = rng:NextNumber(spec.low, spec.high)
			local x, z = waterSpot(spec.near, spec.far, spec.width * scale * 0.5, 30)
			if x and z then
				prop(model, spec.mesh, onWave(x, z, rng:NextNumber(0, math.pi * 2), clearance(spec.width * scale)),
					scale, pick())
			end
		end
	end

	-- === Objects at the wrong size, out on the open sea ===
	--
	-- The game's own things -- a keyboard, a microphone, a honey dipper, a bar of soap -- standing
	-- in the glitter toward the sunset, where they are silhouettes against the brightest part of
	-- the sky. MODELLED OR NOTHING: the primitive stand-ins that used to fill in for props that had
	-- not been imported were the plain white balls and the glowing lamp in the middle of the view,
	-- and a gap is better than a placeholder.
	local HONEY = Color3.fromRGB(236, 190, 104)
	local SLIME = Color3.fromRGB(166, 214, 158)
	local SOAP = Color3.fromRGB(214, 226, 220)
	local KEYCAP = Color3.fromRGB(206, 210, 224)
	local METAL = Color3.fromRGB(150, 154, 164)
	local WAX = Color3.fromRGB(240, 232, 212)
	local FOAM = Color3.fromRGB(158, 190, 176)
	local objects = {
		{ mesh = "Backdrop_Keyboard", tint = KEYCAP },
		{ mesh = "Backdrop_Microphone", tint = METAL },
		{ mesh = "Backdrop_HoneyDipper", tint = HONEY },
		{ mesh = "Backdrop_Soap", tint = SOAP },
		{ mesh = "Backdrop_SlimeJar", tint = SLIME },
		{ mesh = "Backdrop_Candle", tint = WAX },
		{ mesh = "Backdrop_Foam", tint = FOAM },
		{ mesh = "Backdrop_Island", lift = 320 },
		{ mesh = "Backdrop_Statue" },
		{ mesh = "Backdrop_Umbrella" },
		{ mesh = "Backdrop_WaterTower" },
		{ mesh = "Backdrop_Arch" },
		{ mesh = "Backdrop_Hoop" },
	}
	for _, band in ipairs({ { near = 1400, far = 2600, low = 5.5, high = 9.5, detail = true },
		{ near = 2600, far = 4200, low = 8.0, high = 13.0, detail = false } }) do
		for _, entry in ipairs(objects) do
			local wide, tall = propSpan(entry.mesh)
			if wide > 0 then
				local scale = rng:NextNumber(band.low, band.high)
				local radius = wide * scale * 0.5
				local ox, oz = waterSpot(band.near, band.far, radius, 30, true)
				if ox and oz then
					local spun = CFrame.new(ox, 0, oz) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
					-- A prop much wider than it is tall is an object LYING DOWN, and belongs on the
					-- surface; islands float; everything else stands in the water.
					local placed
					if entry.lift then
						placed = spun * CFrame.new(0, entry.lift, 0)
					elseif tall < wide * 0.42 then
						placed = onWave(ox, oz, rng:NextNumber(0, math.pi * 2), clearance(wide * scale))
					else
						placed = afloat(spun, rng:NextNumber(6, 26) * scale / 7)
					end
					local tint = entry.tint or pick()
					if (band.detail and prop(model, entry.mesh .. "_Detail", placed, scale, tint))
						or prop(model, entry.mesh, placed, scale, tint)
					then
						occupy(ox, oz, radius)
					end
				end
			end
		end
	end

	-- Where the sandbars ended up, so the furniture below can be put on their edges rather
	-- than scattered into open water.
	local shores: { { x: number, z: number, radius: number } } = {}

	-- Sandbars out on the open sea, beyond the harbour walls.
	for _ = 1, 14 do
		local diameter = rng:NextNumber(180, 460)
		local x, z = waterSpot(1500, 5200, diameter * 0.75, 90, true)
		if x and z then
			sandbar(model, CFrame.new(x, 0, z), diameter)
			occupy(x, z, diameter * 0.8)
			table.insert(shores, { x = x, z = z, radius = diameter * 0.5 })
		end
	end

	-- === Poolside furniture goes ON THE SANDBARS ===
	--
	-- Small things read by their CONTEXT rather than their silhouette -- a lounger beside a
	-- beach is a lounger, and the same lounger alone in the sea is a rectangle nobody can
	-- identify -- so they cluster on the wet edge of each sandbar.
	local FURNITURE = {
		"Backdrop_Lounger", "Backdrop_Palm", "Backdrop_PoolLadder",
		"Backdrop_Cabana", "Backdrop_Lounger", "Backdrop_Umbrella",
		"Backdrop_WaterCannon", "Backdrop_SprayDome", "Backdrop_WaterCannon",
		"Backdrop_Surfboard", "Backdrop_Dinghy", "Backdrop_BeachHut",
		"Backdrop_BeachFlags", "Backdrop_Sandcastle", "Backdrop_Surfboard",
		"Backdrop_Palm", "Backdrop_Umbrella", "Backdrop_Dinghy",
	}
	for _, shore in ipairs(shores) do
		for _ = 1, rng:NextInteger(4, 9) do
			local name = FURNITURE[rng:NextInteger(1, #FURNITURE)]
			local angle = rng:NextNumber(0, math.pi * 2)
			local out = shore.radius * rng:NextNumber(0.75, 1.25)
			local x, z = shore.x + math.cos(angle) * out, shore.z + math.sin(angle) * out
			local scale = rng:NextNumber(2.0, 4.5)
			local wide, tall = propSpan(name)
			local footprint = if wide > 0 then wide else 40
			if not clearOf(x, z, footprint * scale * 0.5) then
				continue
			end
			local pose = if tall > 0 and tall < wide * 0.42
				then onWave(x, z, rng:NextNumber(0, math.pi * 2), clearance(wide * scale))
				else afloat(
					CFrame.new(x, 0, z) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
					rng:NextNumber(2, 12)
				)
			prop(model, name, pose, scale, pick())
		end
	end

	-- The wave mesh is looked up ONCE here rather than per tile, and nil is fine: sea() falls
	-- back to flat plates. The sea runs under the land too; the land hides it.
	sea(model, 6200, 1600, propTemplate("Sea_Tile"), propTemplate("Sea_Foam"))

	-- NO CLOUD BANKS AND NO VAPOUR. The banks were fifty opaque balls each, and from the level
	-- the near ones were the white eggs floating in front of everything; the vapour was 126 flat
	-- translucent masses stacked between the level and the water, which is most of why the sea
	-- came out as a pink soup. Height reads from seeing the water far below clearly, not from
	-- things in the way of it. Terrain.Clouds still carries the sky.

	-- AN EXPLICIT PIVOT, and its absence is what once made the backdrop invisible.
	--
	-- Model:PivotTo with no PrimaryPart pivots about the model's BOUNDING BOX CENTRE. The
	-- towers rise to 3000 studs, so that centre sits far up -- and pivoting it to BASE_Y would
	-- drive the entire backdrop that much further down than intended. A zero-size anchor at the
	-- origin makes the pivot mean what the code says it means.
	local anchor = Instance.new("Part")
	anchor.Name = "Origin"
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.CFrame = CFrame.new()
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.CastShadow = false
	anchor.Parent = model
	model.PrimaryPart = anchor

	return model
end

-- Bumped whenever the backdrop's GEOMETRY changes, which is the only way a change to this
-- file can ever reach the screen.
--
-- The backdrop is built once and then lives in the workspace, and a saved place file keeps
-- it -- so the guard below, which exists to stop a second horizon being built, also meant
-- that editing a generator did nothing at all. The cloud banks were rewritten from spheres
-- into cumulus and the old spheres stayed on screen, because the new code was never asked
-- to run. There was no error and no warning; it just silently reused what was there.
--
-- Stamping the model and comparing on build turns "delete workspace.Backdrop by hand and
-- remember to do it every time" into something that happens on its own. Same trap as
-- ServerStorage.ChunkTemplates, and the same fix.
local BACKDROP_VERSION = 5

-- Built once per server, AFTER the level exists so its centre can be measured. Safe to call
-- more than once: a second call with a matching version is a no-op rather than a second
-- horizon, and a mismatched one replaces what is there.
function BackdropService.build()
	local existing = workspace:FindFirstChild("Backdrop")
	if existing then
		if existing:GetAttribute("BuildVersion") == BACKDROP_VERSION then
			return
		end
		warn(("[BackdropService] rebuilding: the backdrop in the workspace is version %s and "
			.. "this build is %d. The old one is being removed."):format(
			tostring(existing:GetAttribute("BuildVersion")), BACKDROP_VERSION))
		existing:Destroy()
	end

	ensureSkyClouds()

	local model = build()
	local centre = levelCentre()
	-- Placed before it is parented, so it is never briefly visible in the wrong spot.
	model:SetAttribute("BuildVersion", BACKDROP_VERSION)
	model:PivotTo(CFrame.new(centre.X, BASE_Y, centre.Z))

	-- PERSISTENT, AND THIS IS THE WHOLE REASON THE HORIZON ARRIVED A MINUTE LATE AND THEN
	-- LEFT AGAIN.
	--
	-- Workspace.StreamingEnabled is ON by default in every place made since 2021, and
	-- nothing in this project ever turned it off. Under streaming the server sends a client
	-- only the parts near its character; StreamingTargetRadius defaults to 1024 studs.
	-- Every piece of this backdrop is 800 to 5200 studs out, so essentially none of it
	-- qualified. Roblox trickled the distant regions in at low priority -- the minute of
	-- waiting -- evicted them again under memory pressure or a quality drop -- the
	-- disappearing -- and never had more than a fraction resident at once -- three
	-- buildings where there were meant to be dozens. One cause, all three symptoms, and no
	-- amount of contrast or silhouette work could touch any of them.
	--
	-- Persistent means: replicated to every client on join, at any distance, and NEVER
	-- streamed out. It is the mode Roblox added for precisely this case, distant scenery
	-- and skyboxes that have to be there from the first frame.
	--
	-- Set BEFORE parenting, so the model is never briefly streamable, and in a pcall so a
	-- client too old to have the property loses the guarantee rather than the horizon.
	local persistentOk = pcall(function()
		model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	end)

	model.Parent = workspace

	print(("[server] Backdrop built: %d parts, centred on (%d, %d, %d), streaming=%s persistent=%s")
		:format(
			#model:GetDescendants(),
			centre.X,
			BASE_Y,
			centre.Z,
			tostring(workspace.StreamingEnabled),
			tostring(persistentOk)
		))

	-- Loud, because the failure it describes looks like a rendering problem and is not.
	if workspace.StreamingEnabled and not persistentOk then
		warn(
			"[server] StreamingEnabled is on and ModelStreamingMode could not be set, so the "
				.. "horizon will load late and stream out again. Turn off Workspace.StreamingEnabled."
		)
	end
end

-- HOW HIGH THE SEA IS at a world position, or nil when there is no backdrop standing.
--
-- The sea is not flat: waveSurface gives a 72-stud range of swell, and the one thing that has
-- to land ON it -- the dive that finishes City Shore -- would otherwise splash at a height the
-- water only happens to be at in some places. The model is pivoted to (centre, BASE_Y, centre)
-- with no rotation, so world and local differ by exactly that.
function BackdropService.waterLevelAt(x: number, z: number): number?
	local backdrop = workspace:FindFirstChild("Backdrop")
	if not backdrop then
		return nil
	end
	local pivot = backdrop:GetPivot().Position
	local height = waveSurface(x - pivot.X, z - pivot.Z)
	return pivot.Y + height
end

return BackdropService
