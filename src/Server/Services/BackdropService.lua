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
-- A SEA 700 studs below, opaque and rippled, with sandbars breaking through. Standing in
-- it: a skyline of blank towers, colonnades receding past the fog,
-- slab facades with regular window grids, and ordinary objects at hundreds of studs tall.
-- Softly coloured, never dark. Liminal spaces are unsettling because they were made for
-- people and hold none; they are RESTFUL when they are also warm and quiet, which is the
-- line this palette walks.
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

-- How far the base of anything standing in the sea sits BELOW the mean waterline.
--
-- Comfortably more than the wave amplitude (22 studs either side of zero), so no trough
-- ever exposes a floating edge. This is what makes the towers read as rising out of the
-- water rather than as resting on it, and it is cheap: the same amount is added back to
-- their height, so nothing gets shorter.
local SEA_DRAFT = 90

-- Pulled from the references: swimming-pool mint, playplace pink, corridor cream, faded
-- lemon, dusty locker-room blue. Desaturated enough that the haze can take them the rest
-- of the way, and light enough that nothing in the distance ever reads as a threat.
local PALETTE = {
	Color3.fromRGB(168, 205, 190),
	Color3.fromRGB(226, 196, 200),
	Color3.fromRGB(232, 226, 206),
	Color3.fromRGB(226, 219, 172),
	Color3.fromRGB(180, 200, 212),
	Color3.fromRGB(199, 190, 208),
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
	local body = pick():Lerp(Color3.fromRGB(236, 238, 244), 0.12)
	local glass = body:Lerp(Color3.fromRGB(44, 52, 74), 0.78)

	local y = 0
	local topWidth, topDepth = width, depth
	for index, stage in ipairs(TOWER_STAGES[style]) do
		local w, d, h = width * stage[1], depth * stage[2], height * stage[3]
		-- Towers keep concrete. They are the shell around the park, not the park.
		useVariant(
			piece(parent, Vector3.new(w, h, d), at * CFrame.new(0, y + h / 2, 0), body, Enum.Material.Concrete),
			CONCRETE_VARIANT
		)

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
					Enum.Material.Glass
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

-- The skyline as a whole: a deep BAND rather than a ring.
--
-- Depth is the entire point. Towers all at one radius read as a fence of posts, however
-- well modelled each one is; towers at scattered distances overlap each other, and the
-- overlaps are what say "city" -- you are seeing past the front row to more of it, and
-- the ones behind are already fading into the haze.
local function skyline(
	parent: Instance,
	count: number,
	near: number,
	far: number,
	widthLow: number,
	widthHigh: number,
	heightLow: number,
	heightHigh: number
)
	for i = 1, count do
		-- JITTER WIDER THAN ONE SPOKE, deliberately: at +/- 1.6 spokes a tower can cross
		-- its neighbour's slot, so the ring comes out CLUMPED -- runs of three or four
		-- crowded together, then a gap. Tight jitter gives evenly spaced towers, which is
		-- the one thing no real skyline has, and it reads as a fence however many you add.
		local spoke = math.pi * 2 / count
		local angle = (i / count) * math.pi * 2 + rng:NextNumber(-spoke * 1.6, spoke * 1.6)
		local reach = rng:NextNumber(near, far)
		local position = Vector3.new(math.cos(angle) * reach, 0, math.sin(angle) * reach)
		-- Faced squarely at the middle, so the ribbed broad side is the side you see.
		local at = CFrame.lookAt(position, Vector3.new(0, 0, 0))
		local width = rng:NextNumber(widthLow, widthHigh)
		local height = rng:NextNumber(heightLow, heightHigh)

		-- === Draft: how deep this one sits, and one in five is DROWNED ===
		--
		-- A uniform 90-stud draft is invisible on a 2000-stud tower -- 4% underwater reads
		-- as a building that happens to touch the sea, which is what it looked like. What
		-- says SUBMERGED is a waterline that cuts across buildings at obviously different
		-- points: some barely wet, some with half their height gone. A drowned city is
		-- irregular, and the irregularity is the whole signal.
		--
		-- Sinking a normal tower costs nothing because the draft is added back to its
		-- height. A drowned one is not compensated -- losing the top is the point.
		local drowned = rng:NextNumber() < 0.22
		local draft = if drowned
			then height * rng:NextNumber(0.4, 0.68)
			else SEA_DRAFT * rng:NextNumber(0.7, 1.6)
		tower(
			parent,
			at * CFrame.new(0, -draft, 0),
			TOWER_STYLES[rng:NextInteger(1, #TOWER_STYLES)],
			width,
			width * rng:NextNumber(0.55, 1.0),
			if drowned then height else height + draft
		)

		-- The collar, and it is doing more work than the draft is.
		--
		-- Nothing sitting in water meets it at a clean edge; there is always a disturbed
		-- ring where the two argue. One translucent disc at the actual wave height, a
		-- little wider than the footprint, is what turns "tower next to water" into "tower
		-- standing in water" -- and unlike the draft it is visible no matter how tall the
		-- building is.
		-- The footprint is the tower's half-diagonal, so a mark cleared against it cannot
		-- clip a corner.
		occupy(position.X, position.Z, width * 0.72)

		-- EVERY building gets one now. Applying it to 42% was meant to avoid a repeating
		-- pattern, and it bought a worse problem: two identical towers standing in the same
		-- water, one with a waterline and one without, reads as a missing piece rather than
		-- as variety. Anything sitting in water HAS a waterline -- that is not the sort of
		-- detail that is present on some objects and absent on others.
		--
		-- The variation moves into strength instead, over a much wider range than before.
		-- At the faint end these are barely perceptible, which is the honest look for a
		-- structure in calm water, and it gets the irregularity without the absences.
		collar(parent, position.X, position.Z,
			width * rng:NextNumber(1.1, 1.5), rng:NextNumber(0.62, 0.93))
	end
end

-- A colonnade: one ring of enormous square columns.
--
-- Columns rather than walls because a colonnade is READ THROUGH. You see gaps, and past
-- the gaps more columns, and past those the skyline -- which is what makes a space feel
-- endless rather than merely large. A solid ring at this distance would just be a wall
-- around the level, and would say "edge of the map" instead of "it keeps going".
local function colonnade(parent: Instance, radius: number, count: number, height: number, width: number)
	for i = 1, count do
		-- Jittered off the exact spoke, so the ring does not read as a turntable of
		-- evenly spaced posts when you move along it.
		local angle = (i / count) * math.pi * 2 + rng:NextNumber(-0.03, 0.03)
		local reach = radius + rng:NextNumber(-radius * 0.06, radius * 0.06)
		local tall = height * rng:NextNumber(0.7, 1.3)
		local x, z = math.cos(angle) * reach, math.sin(angle) * reach
		-- Each column sunk by its own amount below its own bit of water, so the ring meets
		-- the sea at a ragged line instead of a machined one.
		local draft = SEA_DRAFT * rng:NextNumber(0.6, 1.8)
		local waterY = waveSurface(x, z)
		-- Concrete rather than SmoothPlastic now, so the colonnade can take the same variant
		-- as everything else it stands beside. Without a variant the two look near enough
		-- identical at this distance that the change costs nothing.
		-- The colonnade is TILED. It stands in the water, so it is the part of the
		-- structure a swimmer would touch, and that is where a pool is tiled.
		useVariant(piece(
			parent,
			Vector3.new(width, tall + draft, width),
			CFrame.new(x, waterY + tall / 2 - draft, z) * CFrame.Angles(0, -angle, 0),
			pick(),
			Enum.Material.Concrete
		), POOLTILE_VARIANT)
		occupy(x, z, width * 0.72)
		collar(parent, x, z, width * rng:NextNumber(1.15, 1.5), rng:NextNumber(0.66, 0.93))
	end
end

-- A blank facade with a grid of darker panels: the empty-office, empty-mall silhouette.
-- The grid is what makes it architecture rather than a slab -- a regular repeat at a
-- scale that implies floors, and therefore implies a building nobody is in.
local function facade(parent: Instance, at: CFrame, width: number, height: number)
	local body = pick()
	local waterY = waveSurface(at.Position.X, at.Position.Z)
	useVariant(piece(parent, Vector3.new(width, height + SEA_DRAFT, 42),
		at * CFrame.new(0, waterY + height / 2 - SEA_DRAFT, 0), body, Enum.Material.Concrete),
		CONCRETE_VARIANT)
	occupy(at.Position.X, at.Position.Z, width * 0.55)
	collar(parent, at.Position.X, at.Position.Z, width * 1.18, 0.78)

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
					at * CFrame.new(-width / 2 + (c - 0.5) * (width / cols), (r - 0.35) * (height / rows), 24),
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

-- === Objects at the wrong size ===
--
-- The architecture alone reads as "somewhere big and abandoned". These are what make it
-- DREAMLIKE: the wrongness is not that the space is empty, it is that the ordinary things
-- standing in it have the wrong size and nobody has remarked on it.
--
-- Each is authored at furniture PROPORTIONS and then multiplied. Getting the proportions
-- from the real object and the size from the dream is what keeps them legible -- a lounger
-- built to be huge just reads as a shape, while a correct lounger at the wrong scale is
-- unmistakably a lounger and unmistakably wrong.
--
-- All of these must stand on their own, because the modelled props above are OPTIONAL and
-- may never be imported. Everything below is what the horizon looks like with an empty
-- Assets/Backdrop folder, so it has to carry the variety by itself.

-- A standing lamp lighting nothing. Neon rather than a real light source: a PointLight
-- this far out costs a shadow pass and lands on nothing to illuminate.
local function lamp(parent: Instance, at: CFrame, scale: number)
	local stem = Color3.fromRGB(178, 176, 170)
	pillar(parent, 30 * scale, 4 * scale, at * CFrame.new(0, 2 * scale, 0), stem, Enum.Material.Metal)
	piece(parent, Vector3.new(3 * scale, 96 * scale, 3 * scale), at * CFrame.new(0, 48 * scale, 0), stem, Enum.Material.Metal)
	pillar(parent, 40 * scale, 30 * scale, at * CFrame.new(0, 110 * scale, 0),
		Color3.fromRGB(246, 238, 208), Enum.Material.Neon)
end

-- A playplace ball, half-sunk as though it had always been there.
local function ball(parent: Instance, at: CFrame, scale: number)
	piece(parent, Vector3.new(70, 70, 70) * scale, at * CFrame.new(0, 22 * scale, 0),
		pick(), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
end

-- A plinth with nothing on it: the quietest wrongness here. Every other object has a
-- purpose it is failing at; this one is a pedestal for an absence.
local function plinth(parent: Instance, at: CFrame, scale: number)
	local stone = Color3.fromRGB(216, 212, 202)
	piece(parent, Vector3.new(58, 10, 58) * scale, at * CFrame.new(0, 5 * scale, 0), stone, Enum.Material.Marble)
	piece(parent, Vector3.new(44, 84, 44) * scale, at * CFrame.new(0, 52 * scale, 0), stone, Enum.Material.Marble)
	piece(parent, Vector3.new(56, 8, 56) * scale, at * CFrame.new(0, 98 * scale, 0), stone, Enum.Material.Marble)
end

-- A door frame standing on its own, with nothing on either side of it. The wall it
-- belonged to is not missing so much as never mentioned.
local function doorway(parent: Instance, at: CFrame, scale: number)
	local frame = pick()
	local wide, tall, thick = 62 * scale, 104 * scale, 9 * scale
	piece(parent, Vector3.new(thick, tall, thick * 1.6), at * CFrame.new(-wide / 2, tall / 2, 0), frame, Enum.Material.WoodPlanks)
	piece(parent, Vector3.new(thick, tall, thick * 1.6), at * CFrame.new(wide / 2, tall / 2, 0), frame, Enum.Material.WoodPlanks)
	piece(parent, Vector3.new(wide + thick, thick * 1.4, thick * 1.6), at * CFrame.new(0, tall, 0), frame, Enum.Material.WoodPlanks)
end

-- A diving board over no pool: from the drained-poolroom references, and the object that
-- most wants water underneath it.
local function divingBoard(parent: Instance, at: CFrame, scale: number)
	local metal = Color3.fromRGB(198, 202, 206)
	local board = Color3.fromRGB(238, 236, 226)
	piece(parent, Vector3.new(7 * scale, 74 * scale, 7 * scale), at * CFrame.new(-16 * scale, 37 * scale, 0), metal, Enum.Material.Metal)
	piece(parent, Vector3.new(7 * scale, 74 * scale, 7 * scale), at * CFrame.new(16 * scale, 37 * scale, 0), metal, Enum.Material.Metal)
	-- The board itself, cantilevered well past its supports and tilted a couple of degrees
	-- under its own weight.
	piece(parent, Vector3.new(30 * scale, 4 * scale, 120 * scale),
		at * CFrame.new(0, 76 * scale, 44 * scale) * CFrame.Angles(-0.04, 0, 0), board, Enum.Material.WoodPlanks)
	piece(parent, Vector3.new(4 * scale, 34 * scale, 4 * scale), at * CFrame.new(-15 * scale, 93 * scale, -22 * scale), metal, Enum.Material.Metal)
	piece(parent, Vector3.new(4 * scale, 34 * scale, 4 * scale), at * CFrame.new(15 * scale, 93 * scale, -22 * scale), metal, Enum.Material.Metal)
end

-- A lattice mast. Not a building, which is the point: it breaks a horizon of solid
-- rectangles with something you can see straight through.
local function pylon(parent: Instance, at: CFrame, scale: number)
	local metal = Color3.fromRGB(190, 192, 198)
	local tall, spread, leg = 190 * scale, 30 * scale, 5 * scale
	for _, corner in ipairs({ Vector2.new(1, 1), Vector2.new(1, -1), Vector2.new(-1, 1), Vector2.new(-1, -1) }) do
		-- Legs lean inward, so the mast tapers instead of being a box of sticks.
		piece(
			parent,
			Vector3.new(leg, tall, leg),
			at * CFrame.new(corner.X * spread * 0.6, tall / 2, corner.Y * spread * 0.6)
				* CFrame.Angles(corner.Y * 0.09, 0, -corner.X * 0.09),
			metal,
			Enum.Material.Metal
		)
	end
	for i = 1, 4 do
		local y = tall * (i / 5)
		local width = spread * (1.5 - 0.22 * i)
		piece(parent, Vector3.new(width, leg * 0.8, leg * 0.8), at * CFrame.new(0, y, spread * 0.55), metal, Enum.Material.Metal)
		piece(parent, Vector3.new(leg * 0.8, leg * 0.8, width), at * CFrame.new(spread * 0.55, y, 0), metal, Enum.Material.Metal)
	end
	pillar(parent, leg * 1.2, tall * 0.2, at * CFrame.new(0, tall * 1.1, 0), metal, Enum.Material.Metal)
end

-- Cloud banks at height, INSIDE the colonnades, so they read as being in the space rather
-- than as sky.
--
-- === Why the first two attempts came out as balloons ===
--
-- Version one was four to seven opaque balls of 90 to 170 studs, scattered at random. That
-- is a balloon cluster and looked like one. Version two fixed the MASSING -- flat base,
-- lobes shrinking with height, more of them -- and still read as spheres, because it left
-- the single number that actually decides this alone: each lobe was still about a THIRD of
-- the cloud's width. At that ratio every lobe is individually identifiable no matter how
-- they are arranged, and a shape you can count the parts of is not a cloud.
--
-- The fix is a ratio, not an arrangement. A lobe is now 5 to 13 per cent of the cloud's
-- width, and there are fifty of them instead of fourteen. Nothing about the silhouette is
-- decided by any one sphere any more, which is the whole trick -- and it is why real
-- volumetric clouds look the way they do at any scale.
--
-- === What the rest of it is doing ===
--
--   THE BASE IS FLAT. Cloud forms where rising air hits its condensation level, and that
--   level is a plane -- so every cumulus is sliced off underneath at the same height. Each
--   lobe's centre is held far enough above the base that its own underside cannot dip
--   below it. This does more work than anything else here.
--
--   LOBES SHRINK OUTWARD AND UPWARD. Big in the core, small at the surface and smaller
--   still at the crown. That gradient gives a finely lumpy outline where equal lobes give
--   a knobbly ball, and it is what makes cauliflower read as cauliflower.
--
--   IT LEANS. Real cumulus is asymmetric -- one side is growing and stands taller. The
--   crown is offset horizontally so no bank is a symmetrical mound.
--
--   IT IS TINTED BY HEIGHT, not lit. Cool grey at the base, near-white at the top. That
--   gradient is where a solid cloud gets its depth from, and it costs nothing.
local CLOUD_LOBES = 50
local CLOUD_WIDTH = 300      -- studs before `scale`, and everything below is a fraction of it
local CLOUD_FLATNESS = 0.36  -- height as a fraction of width. Cumulus is wide, not tall.
local CLOUD_LOBE_MIN = 0.05
local CLOUD_LOBE_MAX = 0.13
local CLOUD_SQUASH = 0.70    -- a lobe is wider than it is tall
local CLOUD_LEAN = 0.22      -- how far the crown is offset from the base


local function cloudBank(parent: Instance, at: CFrame, scale: number)
	local width = CLOUD_WIDTH * scale
	local height = width * CLOUD_FLATNESS
	local depth = width * 0.72
	-- The direction this one is growing in, so the crown leans off the base.
	local leanAngle = rng:NextNumber(0, math.pi * 2)
	local leanX, leanZ = math.cos(leanAngle), math.sin(leanAngle)

	for _ = 1, CLOUD_LOBES do
		-- `out` biased toward 1 puts more lobes near the surface than in the core, which is
		-- where they are needed: the outline is the only part anyone sees.
		local out = rng:NextNumber() ^ 0.55
		local yaw = rng:NextNumber(0, math.pi * 2)
		-- `up` biased LOW, because a cumulus is mostly base with a crown on top rather than
		-- an even column.
		local up = rng:NextNumber() ^ 1.6

		-- Footprint pulls in as it rises, so the stack narrows into a dome.
		local reach = out * (1 - up * 0.55)
		local x = math.cos(yaw) * reach * width * 0.5 + leanX * up * width * CLOUD_LEAN
		local z = math.sin(yaw) * reach * depth * 0.5 + leanZ * up * width * CLOUD_LEAN

		-- Smaller at the surface and smaller again at the crown.
		local radius = width * rng:NextNumber(CLOUD_LOBE_MIN, CLOUD_LOBE_MAX)
			* (1 - out * 0.45) * (1 - up * 0.35)
		local lobeH = radius * CLOUD_SQUASH

		-- THE FLAT BASE. The centre is lifted by the lobe's own half-height so its underside
		-- lands ON the base plane and never below it. Without this one line the bottom of
		-- the cloud is as knobbly as the top and it stops reading as cumulus entirely.
		local y = lobeH * 0.5 + up * height

		local tint = Color3.fromRGB(206, 214, 230):Lerp(Color3.fromRGB(252, 253, 255),
			math.min(1, up * 0.75 + 0.25))
		piece(
			parent,
			Vector3.new(radius * 2, lobeH * 2, radius * 2 * rng:NextNumber(0.82, 1.0)),
			at * CFrame.new(x, y, z) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0),
			tint,
			Enum.Material.SmoothPlastic,
			Enum.PartType.Ball
		)
	end
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

-- Scattered onto a ring, at an angle and distance, facing the middle. Every ring in here
-- wants the same four lines, and writing them out each time is how the jitter ends up
-- inconsistent between one ring and the next.
local function ringSpot(near: number, far: number, index: number, count: number, jitter: number): (CFrame, number)
	local angle = (index / count) * math.pi * 2 + rng:NextNumber(-jitter, jitter)
	local reach = rng:NextNumber(near, far)
	return CFrame.new(math.cos(angle) * reach, 0, math.sin(angle) * reach), angle
end

-- ===== Vapour banks =====
--
-- THE MIDDLE OF THE WORLD WAS EMPTY, and that is the gap this fills. Terrain.Clouds
-- already puts a volumetric deck far overhead, and the sea is 700 studs down; between them
-- sat several hundred studs of flat blue with nothing in it, so the level read as floating
-- in a void rather than as being HIGH UP. Height is only legible when something occupies
-- the space you are above.
--
-- Roblox's own Clouds cannot do this: they render as a single deck at one altitude, above
-- everything, and cannot be layered or placed below the player. Banks of geometry can.
--
-- A BANK IS ONE MASS, NOT A CONSTELLATION. This is the thing two earlier attempts got
-- wrong. Puffs scattered across the bank's full width -- even a lot of them, even in three
-- size classes -- do not become a cloud; they stay a handful of separate balls with sky
-- between them, which is exactly what they looked like. Overlap is not decoration here, it
-- is the entire mechanism: the puffs must sit close enough that most of the bank is under
-- two or three of them at once, so their alphas accumulate into a soft interior while the
-- rim, covered by one, stays faint. That gradient is the cloud. Hence CLUSTER, which is
-- small, and the wide flat puffs that go with it.
local CLOUD_HI = Color3.fromRGB(250, 248, 252)
local CLOUD_LO = Color3.fromRGB(203, 216, 236)

-- How far from the bank centre a puff may sit, as a fraction of the bank's own span. Small
-- ON PURPOSE -- see above. At 0.55 the earlier version scattered them; at 0.22 they pile up.
local CLOUD_CLUSTER = 0.22

local function vapour(parent: Instance, bands: { number }, perBand: number, radius: number)
	-- A folder of its own this time, and NOT routed through `animate`. The swell loop only
	-- knows how to sway a part about a fixed origin; clouds have to travel and wrap, which
	-- is CloudService's job, and it finds them here.
	local folder = Instance.new("Folder")
	folder.Name = "Clouds"
	folder.Parent = parent

	for index, height in ipairs(bands) do
		-- Depth, 0 at the top band and 1 at the bottom. Lower banks are bluer and more
		-- transparent -- aerial perspective, and the same rule the three skyline bands
		-- already follow. Without it the lowest layer reads as being the nearest.
		local depth = (index - 1) / math.max(1, #bands - 1)
		local tint = CLOUD_HI:Lerp(CLOUD_LO, depth)

		for _ = 1, perBand do
			local angle = rng:NextNumber(0, math.pi * 2)
			-- sqrt, so banks spread evenly over AREA. Sampling the radius uniformly piles
			-- them up near the middle, which is the one place the player can see clearly.
			local distance = 160 + (radius - 160) * math.sqrt(rng:NextNumber())
			local cx = math.cos(angle) * distance
			local cz = math.sin(angle) * distance
			local cy = height + rng:NextNumber(-34, 34)

			local span = rng:NextNumber(240, 420)
			local yaw = rng:NextNumber(0, math.pi * 2)
			local squash = rng:NextNumber(0.5, 0.85)

			for _ = 1, rng:NextInteger(5, 7) do
				-- All puffs are large and similar. A wide size range reintroduces the
				-- problem the clustering solves: a small puff beside a big one reads as a
				-- separate object rather than as part of the same mass.
				local wide = span * rng:NextNumber(0.62, 0.88)
				-- FLAT. A cloud is far wider than it is deep, and this is most of what
				-- separates vapour from a ball: at a seventh of its width a puff has no
				-- readable sphere silhouette left, only a soft horizontal mass.
				local tall = wide * rng:NextNumber(0.11, 0.17)

				local ra = rng:NextNumber(0, math.pi * 2)
				local rr = span * CLOUD_CLUSTER * math.sqrt(rng:NextNumber())
				local ox, oz = math.cos(ra) * rr, math.sin(ra) * rr * squash
				local rx = ox * math.cos(yaw) - oz * math.sin(yaw)
				local rz = ox * math.sin(yaw) + oz * math.cos(yaw)

				local blob = piece(
					folder,
					Vector3.new(wide, tall, wide * rng:NextNumber(0.66, 1.0)),
					CFrame.new(cx + rx, cy + rng:NextNumber(-tall * 0.7, tall * 0.7), cz + rz)
						* CFrame.Angles(0, yaw + rng:NextNumber(-0.5, 0.5), 0),
					tint,
					Enum.Material.SmoothPlastic,
					Enum.PartType.Ball
				)
				-- Very transparent, because several of them stack. A puff that looks right
				-- on its own is far too solid once three overlap.
				blob.Transparency = math.clamp(0.86 + depth * 0.03 + rng:NextNumber(-0.02, 0.02), 0, 0.97)
				-- The client fades toward this as a cloud nears the wrap boundary, and
				-- needs to know what to fade back TO.
				blob:SetAttribute("BaseTransparency", blob.Transparency)
			end
		end
	end
end

local function build(): Model
	local model = Instance.new("Model")
	model.Name = "Backdrop"

	-- Resolved before any ring is drawn. Held in an upvalue rather than passed down because
	-- collars are raised from three different builders at three different depths, and
	-- threading one optional template through all of them buys nothing.
	swellFolder = Instance.new("Folder")
	swellFolder.Name = "Swell"
	swellFolder.Parent = model

	seaRing = propTemplate("Sea_Ring")
	seaSurf = propTemplate("Sea_Surf")

	-- THE CITY, IN THREE BANDS: 116 towers from 900 studs out to 5200.
	--
	-- One band at one distance was the mistake, and adding contrast to it was never going
	-- to fix it. A city is a DEPTH, not a ring -- what makes it read as continuing forever
	-- is near towers overlapping mid towers overlapping far ones, each band hazier than the
	-- one in front. Thirty-four towers on a single ring gave about six in view at any time,
	-- spaced like fence posts, and no amount of silhouette work saves that.
	--
	-- Nearer is safe. The level runs 344 studs end to end, so the closest tower is over 700
	-- studs from anywhere you can stand, and there is no floor between here and there --
	-- walking off the level drops you through the kill plane long before distance matters.
	--
	-- Each band is shorter and narrower than the one behind it, so the far band still reads
	-- as the biggest thing out there even though it is the most dissolved by haze.
	--
	-- HEIGHTS ROUGHLY DOUBLED when the water went to -700, and this is the part that broke
	-- on the first try. A 600-stud tower standing at -700 tops out 100 studs BELOW your
	-- feet; the horizon is 6.7 degrees down, so the entire near band collapsed into a
	-- sliver along it and the sea looked empty. Dropping the floor does not just move the
	-- floor -- everything standing on it has to grow by the same amount or it sinks out of
	-- the composition.
	-- CUT FROM 116 TOWERS TO 46, and pushed back.
	--
	-- A skyline is made of repeated verticals, and 116 of them is a skyline whatever else is
	-- standing between them -- the towers were not too tall or too plain, there were simply
	-- too many for anything else to be the subject. They are the city AROUND the park now:
	-- present at the back, thinned out in front, and the near band left almost empty for the
	-- aquapark structures to occupy.
	skyline(model, 8, 1400, 2400, 110, 190, 800, 1500)
	skyline(model, 16, 2500, 3600, 150, 280, 1200, 2400)
	skyline(model, 22, 3700, 5200, 190, 360, 1600, 3200)

	-- ONE colonnade now, not two, and pulled in front of the whole city. Its job was always
	-- to be the thing you read the distance THROUGH; with 116 towers behind it, a second
	-- ring buried in the middle band was just more rectangles.
	-- TALLER THAN IT WAS. From 700 studs up, a 520-stud colonnade standing at the water
	-- line tops out 180 below your feet -- the whole ring would sit under the horizon and
	-- stop being something you read the distance THROUGH, which is its only job.
	colonnade(model, 1400, 24, 1150, 140)

	-- Facades scattered through the near and middle bands, turned to face roughly inward.
	for i = 1, 9 do
		local at, angle = ringSpot(1500, 2700, i, 9, 0.3)
		facade(model, at * CFrame.Angles(0, -angle + math.pi / 2, 0), rng:NextNumber(480, 900), rng:NextNumber(750, 1600))
	end

	-- The objects, scattered BETWEEN the rings so they are read against the architecture.
	-- A lounger alone on a plain is just a lounger; one as tall as the colonnade standing
	-- behind it is the whole idea.
	--
	-- MODELLED FIRST, PRIMITIVE SECOND. Each entry names a prop and the primitive that
	-- stands in when that prop has not been imported, so the ring is populated either way
	-- and no two adjacent slots collapse to the same fallback shape.
	-- TINTED, not palette-picked. The liminal props take a random pastel because any of
	-- them could plausibly be any colour, but these six are recognisable BY colour as much
	-- as by shape -- a butter block in mint green is a shed, and amber is doing half the
	-- work of saying honey. Where a `tint` is present it overrides the random pick.
	local HONEY = Color3.fromRGB(236, 190, 104)
	local SLIME = Color3.fromRGB(166, 214, 158)
	local SOAP = Color3.fromRGB(214, 226, 220)
	local KEYCAP = Color3.fromRGB(206, 210, 224)
	local METAL = Color3.fromRGB(150, 154, 164)
	local WAX = Color3.fromRGB(240, 232, 212)
	local FOAM = Color3.fromRGB(158, 190, 176)

	local objects = {
		-- The ASMR set: the game's own materials, and the genre's own objects, standing in
		-- the same field as the architecture.
		{ mesh = "Backdrop_Keyboard", fallback = plinth, lift = 0, tint = KEYCAP },
		{ mesh = "Backdrop_Microphone", fallback = lamp, lift = 0, tint = METAL },
		{ mesh = "Backdrop_HoneyDipper", fallback = lamp, lift = 0, tint = HONEY },
		{ mesh = "Backdrop_Soap", fallback = plinth, lift = 0, tint = SOAP },
		{ mesh = "Backdrop_SlimeJar", fallback = ball, lift = 0, tint = SLIME },
		{ mesh = "Backdrop_Candle", fallback = lamp, lift = 0, tint = WAX },
		{ mesh = "Backdrop_Foam", fallback = plinth, lift = 0, tint = FOAM },

		{ mesh = "Backdrop_Island", fallback = plinth, lift = 320 },
		{ mesh = "Backdrop_Mushroom", fallback = lamp, lift = 0 },
		{ mesh = "Backdrop_Statue", fallback = plinth, lift = 0 },
		{ mesh = "Backdrop_Tree", fallback = doorway, lift = 0 },
		{ mesh = "Backdrop_Slide", fallback = doorway, lift = 0 },
		{ mesh = "Backdrop_Umbrella", fallback = lamp, lift = 0 },
		{ mesh = "Backdrop_WaterTower", fallback = pylon, lift = 0 },
		{ mesh = "Backdrop_Arch", fallback = doorway, lift = 0 },
		{ mesh = "Backdrop_Island", fallback = ball, lift = 470 },
		{ mesh = "Backdrop_Hoop", fallback = divingBoard, lift = 0 },
		{ mesh = "Backdrop_Mushroom", fallback = ball, lift = 0 },
		{ mesh = "Backdrop_Statue", fallback = plinth, lift = 0 },
		{ mesh = "Backdrop_Tree", fallback = divingBoard, lift = 0 },
		{ mesh = "Backdrop_Slide", fallback = pylon, lift = 0 },
	}
	-- RUN TWICE, over two different distance bands: once close in among the near towers and
	-- once out among the middle ones. Two passes over one table rather than a table twice
	-- as long, because what was thin was the SPACING, not the choice of objects -- sixteen
	-- spread over a full circle is one every 22 degrees and you see about four at a time.
	-- === The aquapark, in the space the towers used to fill ===
	--
	-- Placed NEARER and LARGER than the scattered objects below, because these are the
	-- subject now rather than decoration. A slide tower at 900 studs and eleven times scale
	-- is 700 studs of spiralling tube, which is the single most legible silhouette out here.
	local aquapark = {
		{ mesh = "Backdrop_SlideTower", tint = Color3.fromRGB(214, 232, 240) },
		{ mesh = "Backdrop_Flume", tint = Color3.fromRGB(176, 214, 226) },
		{ mesh = "Backdrop_SplashBucket", tint = Color3.fromRGB(232, 226, 196) },
		{ mesh = "Backdrop_SlideTower", tint = Color3.fromRGB(228, 206, 214) },
		{ mesh = "Backdrop_LifeguardChair", tint = Color3.fromRGB(238, 232, 214) },
		{ mesh = "Backdrop_Flume", tint = Color3.fromRGB(206, 224, 208) },
		{ mesh = "Backdrop_SlideTower", tint = Color3.fromRGB(196, 220, 232) },
		{ mesh = "Backdrop_SplashBucket", tint = Color3.fromRGB(220, 206, 226) },
		{ mesh = "Backdrop_LifeguardChair", tint = Color3.fromRGB(232, 236, 228) },
		{ mesh = "Backdrop_Flume", tint = Color3.fromRGB(214, 218, 236) },
		{ mesh = "Backdrop_DivingPlatform", tint = Color3.fromRGB(222, 228, 232) },
		{ mesh = "Backdrop_MushroomFountain", tint = Color3.fromRGB(210, 232, 234) },
		{ mesh = "Backdrop_Palm", tint = Color3.fromRGB(178, 210, 176) },
		{ mesh = "Backdrop_DivingPlatform", tint = Color3.fromRGB(232, 220, 210) },
		{ mesh = "Backdrop_MushroomFountain", tint = Color3.fromRGB(230, 214, 222) },
		{ mesh = "Backdrop_Palm", tint = Color3.fromRGB(192, 216, 190) },
		{ mesh = "Backdrop_PlayStructure", tint = Color3.fromRGB(226, 208, 196) },
		{ mesh = "Backdrop_RockFall", tint = Color3.fromRGB(206, 204, 198) },
		{ mesh = "Backdrop_PirateShip", tint = Color3.fromRGB(206, 186, 164) },
		{ mesh = "Backdrop_WaveSlide", tint = Color3.fromRGB(184, 220, 216) },
		{ mesh = "Backdrop_PlayStructure", tint = Color3.fromRGB(202, 216, 232) },
		{ mesh = "Backdrop_WaveSlide", tint = Color3.fromRGB(224, 210, 216) },
		{ mesh = "Backdrop_RockFall", tint = Color3.fromRGB(196, 192, 190) },
		{ mesh = "Backdrop_Sandcastle", tint = Color3.fromRGB(234, 220, 184) },
	}
	for _, entry in ipairs(aquapark) do
		local scale = rng:NextNumber(6.0, 13.0)
		local wide = propSpan(entry.mesh)
		-- Its own footprint, from the mesh rather than a guess, so a 100-stud flume and a
		-- 25-stud ladder do not reserve the same circle.
		local span = if wide > 0 then wide else 90
		local radius = span * scale * 0.5

		-- CLEARANCE CHECKED, not just recorded. Every one of these called occupy() to log
		-- where it stood and none of them called clearOf() to ask first, so the footprint
		-- registry was write-only -- which is why a slide tower's helix ran straight through
		-- a butter block. Registering a footprint does nothing unless something reads it.
		local x, z = findClear(750, 2600, radius, 40)
		if x and z then
			local spun = CFrame.new(x, 0, z) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
			-- Measured from the BASE, so 8 to 34 studs against props 250 to 900 studs tall
			-- is an ankle in the water, which is what a poolside structure should look like.
			local placed = afloat(spun, rng:NextNumber(8, 34))
			if prop(model, entry.mesh .. "_Detail", placed, scale, entry.tint)
				or prop(model, entry.mesh, placed, scale, entry.tint)
			then
				occupy(x, z, radius)
			end
		end
	end

	-- Float rings and lane ropes lie ON the water rather than standing in it, so they take
	-- the wave surface and the same clearance the foam does.
	--
	-- These two are also the only props whose own height is near zero, which means placing
	-- them by their base -- as prop() now does -- and placing them by their centre are very
	-- nearly the same thing. That is why they looked right while the slide towers did not.
	for _, spec in ipairs({
		{ mesh = "Backdrop_FloatRing", count = 14, near = 700, far = 3200, low = 2.5, high = 6.0, width = 58 },
		{ mesh = "Backdrop_LaneRope", count = 9, near = 900, far = 3600, low = 3.0, high = 7.5, width = 136 },
	}) do
		for i = 1, spec.count do
			local at = ringSpot(spec.near, spec.far, i, spec.count, 0.5)
			local scale = rng:NextNumber(spec.low, spec.high)
			prop(
				model,
				spec.mesh,
				onWave(at.Position.X, at.Position.Z, rng:NextNumber(0, math.pi * 2),
					clearance(spec.width * scale)),
				scale,
				pick()
			)
		end
	end

	local bands = {
		-- The near band draws the HIGH-DETAIL meshes. A prop here can be 700 studs tall at
		-- 950 studs away, which subtends about 40 degrees -- at that size a 10-segment dome
		-- is visibly a polygon, and the low-poly budget that was right for the far horizon
		-- stops being right for something filling a third of the screen.
		{ near = 950, far = 1900, low = 5.5, high = 9.5, detail = true },
		{ near = 2000, far = 3400, low = 8.0, high = 14.0, detail = false },
	}
	for _, band in ipairs(bands) do
		for _, entry in ipairs(objects) do
			local scale = rng:NextNumber(band.low, band.high)
			local span = propSpan(entry.mesh)
			local footprint = if span > 0 then span else 80
			local radius = footprint * scale * 0.5
			local ox, oz = findClear(band.near, band.far, radius, 30)
			if not ox or not oz then
				continue
			end
			local spun = CFrame.new(ox, 0, oz) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
			-- Islands are LIFTED off the floor: a floating island resting on the ground is
			-- just a hill, and the gap under it is the entire point of the shape.
			-- === A prop's PROPORTIONS decide how it is placed ===
			--
			-- The giant keyboard was the thing that made this obvious: 95 studs long and 13
			-- tall, scaled ten times, sunk a few studs like everything else -- and the
			-- result was an 950-stud slab hanging in mid-air over open water with nothing
			-- under it and no reason to be there.
			--
			-- Anything much wider than it is tall is not a building, it is an OBJECT LYING
			-- DOWN, and a thing lying down belongs on the surface. Keyboard, soap, butter,
			-- foam and the lounger all fall on that side; slide towers, palms and diving
			-- platforms on the other. Measured rather than listed, so a new prop lands
			-- correctly without anyone remembering to classify it.
			local wide, tall = propSpan(entry.mesh)
			local lyingDown = tall > 0 and tall < wide * 0.42

			local placed
			if entry.lift > 0 then
				-- Floating islands, and only those.
				placed = spun * CFrame.new(0, entry.lift, 0)
			elseif lyingDown then
				placed = onWave(
					spun.Position.X,
					spun.Position.Z,
					rng:NextNumber(0, math.pi * 2),
					clearance(wide * scale)
				)
			else
				placed = afloat(spun, rng:NextNumber(6, 26) * scale / 7)
			end
			local tint = entry.tint or pick()

			-- THREE WAYS DOWN, and none of them is required to exist. Detail mesh, then
			-- plain mesh, then primitive. Props built only from boxes have no detail
			-- variant at all -- there would be nothing to add -- so the miss here is
			-- normal rather than a sign of a bad import.
			local drawn = band.detail and prop(model, entry.mesh .. "_Detail", placed, scale, tint)
			if not drawn then
				drawn = prop(model, entry.mesh, placed, scale, tint)
			end
			if not drawn then
				entry.fallback(model, spun, scale)
			end
			-- Roughly sized: these are 40 to 140 authored units across before scaling, so
			-- half of 90 is a fair circle for all of them. Being generous costs a fleck or
			-- two; being mean puts one inside a mushroom.
			occupy(ox, oz, radius)
		end
	end

	-- A SECOND SCATTER, primitives only and nearer in.
	--
	-- Not redundant with the fallbacks above: those disappear the moment the props are
	-- imported, and if they were the only primitives then a successful import would empty
	-- the middle distance of everything except architecture. These stay whatever happens.
	-- No staircase. A flight of steps rising to nothing was a good liminal object and a
	-- bad AQUAPARK one -- it read as ruined civic architecture, which is the note this
	-- horizon is trying to stop hitting.
	-- No chairs. A chair at the wrong size was a good dreamcore object and reads as
	-- domestic furniture, which is the one thing a waterpark has none of.
	local nearby = { divingBoard, doorway, ball, pylon, ball, doorway, divingBoard, lamp, plinth, divingBoard }
	for _, band in ipairs({ { 800, 1500, 3.2, 6.0 }, { 1600, 2900, 5.0, 9.0 } }) do
		for _, make in ipairs(nearby) do
			local size = rng:NextNumber(band[3], band[4])
			local radius = 40 * size
			local nx, nz = findClear(band[1], band[2], radius, 30)
			if nx and nz then
				make(
					model,
					afloat(CFrame.new(nx, 0, nz) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
						rng:NextNumber(10, 48) * size / 5),
					size
				)
				occupy(nx, nz, radius)
			end
		end
	end

	-- Where the sandbars ended up, so the furniture below can be put on their edges rather
	-- than scattered into open water.
	local shores: { { x: number, z: number, radius: number } } = {}

	-- === THE SEA IS BUILT LAST, and the order is the whole fix ===
	--
	-- It used to be first. Everything laid on the water -- flecks, sandbars, surf -- was
	-- therefore placed before a single building existed, so `clearOf` would have had an
	-- empty list to check against and the avoidance would have been a no-op that looked
	-- like working code. Registering footprints is useless unless the things that consult
	-- them are built afterwards.
	--
	-- Creation order has no bearing on how Roblox draws these, so this costs nothing.
	for _ = 1, 16 do
		local diameter = rng:NextNumber(180, 460)
		-- Cleared against the surf as well as the island: the crescents reach about 1.4
		-- times the sandbar's own radius, and a sandbar that fits where its surf does not
		-- is the same bug one step along.
		-- The margin only has to clear the surf, which reaches about 0.7 of the sandbar's
		-- own diameter. 90 tries because a sandbar is large and the sea is crowded, and one
		-- missing island is more obvious than one missing fleck.
		local x, z = findClear(900, 5200, diameter * 0.75, 90)
		if x and z then
			sandbar(model, CFrame.new(x, 0, z), diameter)
			occupy(x, z, diameter * 0.8)
			table.insert(shores, { x = x, z = z, radius = diameter * 0.5 })
		end
	end

	-- === Poolside furniture goes ON THE SHORES ===
	--
	-- Loungers, palms, ladders and cabanas were scattered on their own rings at random
	-- bearings, which put sun loungers in open water hundreds of studs from anything. They
	-- are small, and small things read by their CONTEXT rather than their silhouette -- a
	-- lounger beside a beach is a lounger, and the same lounger alone in the sea is a
	-- rectangle nobody can identify.
	--
	-- Clustered around the sandbars instead, at the edge rather than the middle, which is
	-- where furniture actually ends up.
	-- Poolside AND beach, mixed, because a sandbar is where the two meet. The beach half
	-- is things somebody LEFT -- a board pushed into the sand, a hull turned over, a line of
	-- flags -- against a poolside half of things that were installed. That contrast is most
	-- of what makes a shore read as a shore rather than as more scenery.
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
			-- Just outside the sand, on the wet edge.
			local out = shore.radius * rng:NextNumber(0.75, 1.25)
			local x, z = shore.x + math.cos(angle) * out, shore.z + math.sin(angle) * out
			local scale = rng:NextNumber(2.0, 4.5)
			local wide, tall = propSpan(name)
			-- Hoisted out of the condition below. An if-EXPRESSION inside an if-STATEMENT
			-- puts two `if`s and two `then`s on one line, and the second `then` belongs to
			-- the first `if` only by precedence -- check_lua paired them the other way and
			-- reported the block's `end` as orphaned. It was right to: nobody should have to
			-- work that out mid-line.
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

	-- The wave mesh is looked up ONCE here rather than per tile, and nil is fine: sea()
	-- falls back to flat plates.
	sea(model, 6200, 1600, propTemplate("Sea_Tile"), propTemplate("Sea_Foam"))

	for i = 1, 10 do
		local at = ringSpot(900, 3600, i, 10, 0.5)
		-- Measured from the water, so these have to clear 700 studs before they are even
		-- level with you. Cloud banks below the horizon are sea foam.
		cloudBank(model, at * CFrame.new(0, rng:NextNumber(900, 1900), 0), rng:NextNumber(2.0, 4.5))
	end

	-- AN EXPLICIT PIVOT, and its absence is what once made the backdrop invisible.
	--
	-- Model:PivotTo with no PrimaryPart pivots about the model's BOUNDING BOX CENTRE. The
	-- towers rise to 1900 studs, so that centre sits roughly 900 up -- and pivoting it to
	-- BASE_Y would drive the entire backdrop about 900 studs further down than intended,
	-- burying it where nothing can see it. A zero-size anchor at the origin makes the
	-- pivot mean what the code says it means.
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

	-- FOUR BANDS BETWEEN THE WATER AND THE LEVEL. Local Y here is height above the
	-- waterline (the model is pivoted to BASE_Y afterwards), and the lowest walkable
	-- surface sits near 700 -- so 160 to 580 fills the gap without ever putting vapour
	-- where the player is standing. Layered rather than one deck on purpose: what makes
	-- altitude read is passing SEVERAL strata, which is exactly the trick Minecraft's
	-- cloud layer plays at a much simpler fidelity.
	-- FIVE BANDS, TEN BANKS EACH, OUT TO 4600. Local Y here is height above the waterline
	-- (the model is pivoted to BASE_Y afterwards), and the lowest walkable surface sits
	-- near 700 -- so 150 to 620 fills the gap without ever putting vapour where the player
	-- is standing. Layered rather than one deck: what makes altitude read is passing
	-- SEVERAL strata, the trick Minecraft's cloud layer plays at much simpler fidelity.
	-- SEVEN BANDS, EIGHTEEN BANKS EACH. Up from five and ten, because at that density the
	-- strata were far enough apart to be countable -- you could see the gap between one
	-- layer and the next, which turns "flying through weather" back into "passing some
	-- props". Nearly two and a half times the banks closes those gaps, and the two extra
	-- heights fill the thinnest part of the range without going above 700, where the player
	-- actually stands.
	vapour(model, { 660, 570, 490, 410, 330, 240, 150 }, 18, 4600)

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
local BACKDROP_VERSION = 4

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
