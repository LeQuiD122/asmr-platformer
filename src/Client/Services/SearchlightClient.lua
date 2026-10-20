--!strict
-- StarterPlayerScripts/Services/SearchlightClient.lua
-- THE LAUNCH IN THE HARBOUR: somebody is still looking. A rescue launch stands off in the basin past
-- the end of the Sunken City's street, bow towards you, rocking on the swell, and its searchlight goes
-- slowly back and forth over the water you are coming down. When it rains, the light counts for more.
-- When the thing on the horizon comes up, the lamp swings round to it and holds there until it has
-- gone down again, and then goes back to searching.
--
-- WHERE it is, SunkenCityService decides (a marker tagged "SunkenLaunch" in the harbour, clear of the
-- drain and the buoys, with the point it watches); everything else is drawn here, on every client,
-- from the clock every player shares (GetServerTimeNow and the sea's Epoch), so two players see the
-- beam in the same place and nothing moves on the server. Nothing here collides or can be touched.
--
-- THE LIGHT IS REAL: a SpotLight in the lamp lights what is in front of it, and a light where the beam
-- meets the water lights the water there (and you, if it finds you), which a SpotLight cannot do at
-- that distance. The beam drawn through the air is the haze it catches. No Neon anywhere.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local SearchlightClient = {}
SearchlightClient.VERSION = "the harbour launch, 2026-10-07"

-- The thing on the horizon's timing, as SunkenCityClient draws it (its RISE, HOLD, SINK):
-- check_sunkencity.py holds the two files to the same numbers.
local THING_RISE, THING_HOLD, THING_SINK = 9, 12, 10

local S = 1.5 -- the launch is laid out below at 1:1, and built at this scale
local BEAM_LONGEST = 190
local LAMP_HEIGHT = 5.8 -- the lamp's middle above the waterline, before scaling
local LAMP_BACK = 0.4 -- and how far aft of the launch's middle

local NAVY = Color3.fromRGB(38, 50, 70)
local BAND = Color3.fromRGB(206, 74, 54)
local WHITE = Color3.fromRGB(226, 230, 232)
local GLASS = Color3.fromRGB(46, 60, 72)
local DARK = Color3.fromRGB(46, 50, 56)
local DECK = Color3.fromRGB(150, 128, 98)
local RING = Color3.fromRGB(232, 112, 44)
-- THE SEARCHLIGHT IS COLD: a white with blue in it, the way a lamp like that is. The lantern at the end of the
-- pier stays the one warm light in the harbour.
local COLD = Color3.fromRGB(222, 234, 255)

type Piece = { part: BasePart, at: CFrame }
type Launch = {
	marker: BasePart,
	sea: Instance?,
	folder: Folder,
	pieces: { Piece },
	lamp: BasePart,
	far: Attachment,
	beam: Beam,
	spot: SpotLight,
	pool: PointLight,
	watch: Vector3,
	phase: number,
	attention: number,
	held: Vector3?,
	rain: number,
	shownRain: number,
}
local launches: { [Instance]: Launch } = {}

local function quiet(p: BasePart)
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
end

-- One launch, laid out from its own frame (waterline at 0, bow towards -Z) and placed every frame by
-- `stepLaunch`, so the whole of it rocks together. Each piece sits on the one under it.
local function buildLaunch(folder: Folder): ({ Piece }, BasePart)
	local pieces: { Piece } = {}
	local function add(name: string, size: Vector3, colour: Color3, at: CFrame, kind: string?): BasePart
		local p = Instance.new(kind or "Part") :: BasePart
		p.Name = name
		p.Size = size * S
		p.Color = colour
		quiet(p)
		p.Parent = folder
		table.insert(pieces, { part = p, at = at.Rotation + at.Position * S })
		return p
	end
	-- The hull, with a band along it, and the bow: a wedge upside down, so its foot rakes back under it.
	add("Hull", Vector3.new(4.6, 2.2, 10), NAVY, CFrame.new(0, 0.4, 1))
	add("Bow", Vector3.new(4.6, 2.2, 3.2), NAVY, CFrame.new(0, 0.4, -5.6) * CFrame.Angles(0, 0, math.pi), "WedgePart")
	add("Band", Vector3.new(4.7, 0.3, 10), BAND, CFrame.new(0, 1.1, 1))
	add("Deck", Vector3.new(4.3, 0.15, 9.6), DECK, CFrame.new(0, 1.575, 1))
	-- The wheelhouse on the deck, its windows on its walls, its roof on it.
	add("Wheelhouse", Vector3.new(3.4, 2.6, 3.6), WHITE, CFrame.new(0, 2.95, 1.2))
	add("Window", Vector3.new(3, 0.8, 0.12), GLASS, CFrame.new(0, 3.5, -0.64))
	for _, x in ipairs({ -1.74, 1.74 }) do
		add("Window", Vector3.new(0.12, 0.8, 2.6), GLASS, CFrame.new(x, 3.5, 1.2))
	end
	add("Roof", Vector3.new(3.8, 0.25, 4), WHITE, CFrame.new(0, 4.375, 1.2))
	-- A life ring on the wheelhouse's back wall.
	local ring = add("LifeRing", Vector3.new(0.2, 1.2, 1.2), RING, CFrame.new(0, 3.1, 3.1) * CFrame.Angles(0, math.pi / 2, 0))
	if ring:IsA("Part") then
		ring.Shape = Enum.PartType.Cylinder
	end
	-- The mast on the roof, with its white light at the top.
	add("Mast", Vector3.new(0.3, 3, 0.3), DARK, CFrame.new(0, 6, 2.6))
	local top = add("MastLight", Vector3.new(0.4, 0.4, 0.4), WHITE, CFrame.new(0, 7.7, 2.6))
	local anchor = Instance.new("PointLight")
	anchor.Color = COLD
	anchor.Range = 8
	anchor.Brightness = 0.8
	anchor.Parent = top
	-- Running lights on the wheelhouse walls, port red and starboard green.
	for _, side in ipairs({ { x = -1.78, colour = Color3.fromRGB(255, 70, 60) }, { x = 1.78, colour = Color3.fromRGB(70, 255, 120) } }) do
		local holder = add("RunningLight", Vector3.new(0.15, 0.4, 0.4), side.colour, CFrame.new(side.x, 4, -0.3))
		local glow = Instance.new("PointLight")
		glow.Color = side.colour
		glow.Range = 6
		glow.Brightness = 1
		glow.Parent = holder
	end
	-- The lamp's pedestal on the roof. The lamp itself sits on it, and is turned on its own (stepLaunch).
	add("LampPedestal", Vector3.new(0.5, 0.8, 0.5), DARK, CFrame.new(0, 4.9, LAMP_BACK))
	local lamp = Instance.new("Part")
	lamp.Name = "Lamp"
	lamp.Size = Vector3.new(1, 1, 1.3) * S
	lamp.Color = DARK
	quiet(lamp)
	lamp.Parent = folder
	return pieces, lamp
end

local function dressLamp(lamp: BasePart): (Attachment, Beam, SpotLight, PointLight)
	local glass = Instance.new("Attachment")
	glass.Name = "Glass"
	glass.Position = Vector3.new(0, 0, -0.66 * S)
	glass.Parent = lamp
	local far = Instance.new("Attachment")
	far.Name = "Far"
	far.Position = Vector3.new(0, 0, -BEAM_LONGEST)
	far.Parent = lamp
	local spot = Instance.new("SpotLight")
	spot.Face = Enum.NormalId.Front
	spot.Angle = 22
	spot.Range = 60
	spot.Brightness = 2.5
	spot.Color = COLD
	spot.Shadows = false
	spot.Parent = lamp
	-- THE BEAM through the air: widening, fading along its length.
	local beam = Instance.new("Beam")
	beam.Attachment0 = glass
	beam.Attachment1 = far
	beam.Width0 = 1.2
	beam.Width1 = 20
	beam.FaceCamera = true
	beam.LightEmission = 0.5
	beam.LightInfluence = 0
	beam.Segments = 2
	beam.Color = ColorSequence.new(COLD)
	beam.Parent = lamp
	-- WHERE IT MEETS THE WATER, the pool of light, just above the surface.
	local pool = Instance.new("PointLight")
	pool.Color = COLD
	pool.Range = 22
	pool.Brightness = 1.2
	pool.Shadows = false
	pool.Parent = far
	return far, beam, spot, pool
end

-- The beam's fade, a little stronger when it is raining (the light is lower, and the rain catches it).
local function fade(rain: number): NumberSequence
	local near = 0.72 - 0.14 * rain
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, near),
		NumberSequenceKeypoint.new(0.55, 0.9 - 0.04 * rain),
		NumberSequenceKeypoint.new(1, 1),
	})
end

local function remove(marker: Instance)
	local launch = launches[marker]
	if launch then
		launches[marker] = nil
		launch.folder:Destroy()
	end
end

local function add(item: Instance)
	if not item:IsA("BasePart") or launches[item] then
		return
	end
	local marker = item :: BasePart
	local watch = marker:GetAttribute("Watch")
	if typeof(watch) ~= "Vector3" then
		return
	end
	-- The sea the marker is in carries the clock and the schedules.
	local sea: Instance? = nil
	local up = marker.Parent
	while up and up ~= workspace do
		if CollectionService:HasTag(up, "SunkenSea") then
			sea = up
			break
		end
		up = up.Parent
	end
	local folder = Instance.new("Folder")
	folder.Name = "HarbourLaunch"
	folder.Parent = workspace
	local pieces, lamp = buildLaunch(folder)
	local far, beam, spot, pool = dressLamp(lamp)
	beam.Transparency = fade(0)
	launches[marker] = {
		marker = marker,
		sea = sea,
		folder = folder,
		pieces = pieces,
		lamp = lamp,
		far = far,
		beam = beam,
		spot = spot,
		pool = pool,
		watch = watch,
		phase = (marker.Position.X * 0.37 + marker.Position.Z * 0.11) % (2 * math.pi),
		attention = 0,
		held = nil,
		rain = 0,
		shownRain = 0,
	}
end

local function num(sea: Instance?, name: string): number?
	if not sea then
		return nil
	end
	local value = sea:GetAttribute(name)
	return if typeof(value) == "number" then value else nil
end

-- Raining now, on the sea's schedule (the same sum SunkenCityClient's `raining` does).
local function raining(sea: Instance?, t: number): boolean
	local first, every, length = num(sea, "RainFirst"), num(sea, "RainEvery"), num(sea, "RainLength")
	if not (first and every and length) or t < first or every <= 0 then
		return false
	end
	return ((t - first) % every) < length
end

-- Where the thing on the horizon is while it is up, or nil: watched while it rises and holds, and let
-- go halfway through its going down.
local function thing(sea: Instance?, t: number): Vector3?
	local first, every = num(sea, "LeviathanFirst"), num(sea, "LeviathanEvery")
	local from, to = sea and sea:GetAttribute("LeviathanFrom"), sea and sea:GetAttribute("LeviathanTo")
	if not (first and every) or typeof(from) ~= "Vector3" or typeof(to) ~= "Vector3" or t < first or every <= 0 then
		return nil
	end
	local into = (t - first) % every
	if into > THING_RISE + THING_HOLD + THING_SINK * 0.5 then
		return nil
	end
	return ((from :: Vector3) + (to :: Vector3)) / 2 + Vector3.new(0, 18, 0)
end

local function ease(current: number, target: number, rate: number, dt: number): number
	if current < target then
		return math.min(target, current + rate * dt)
	end
	return math.max(target, current - rate * dt)
end

local function stepLaunch(launch: Launch, now: number, dt: number)
	local sea = launch.sea
	local epoch = num(sea, "Epoch")
	local t = if epoch then now - epoch else -1
	local water = launch.marker.Position.Y
	local p = launch.phase

	-- ON THE SWELL: a slow heave, roll and pitch, and a little swing at anchor.
	local swing = math.sin(now * 0.021 + p) * 0.12
	local heave = math.sin(now * 0.7 + p) * 0.3
	local roll = math.sin(now * 0.53 + p * 1.7) * 0.045
	local pitch = math.sin(now * 0.41 + p * 0.9) * 0.025
	local frame = launch.marker.CFrame * CFrame.Angles(0, swing, 0) * CFrame.new(0, heave, 0) * CFrame.Angles(pitch, 0, roll)
	for _, piece in ipairs(launch.pieces) do
		piece.part.CFrame = frame * piece.at
	end
	local lampAt = (frame * CFrame.new(0, LAMP_HEIGHT * S, LAMP_BACK * S)).Position

	-- SEARCHING: back and forth across where you come in, never quite the same twice, and down at the
	-- water, the end of the beam walking in and out across it.
	local toWatch = Vector3.new(launch.watch.X - lampAt.X, 0, launch.watch.Z - lampAt.Z)
	toWatch = if toWatch.Magnitude > 1 then toWatch.Unit else frame.LookVector
	local yaw = math.sin(now * 0.11 + p) * 0.5 + math.sin(now * 0.037 + p * 2.3) * 0.15
	local down = 0.075 + 0.03 * math.sin(now * 0.07 + p + 1.3)
	local flat = CFrame.Angles(0, yaw, 0):VectorToWorldSpace(toWatch)
	local search = (flat * math.cos(down) - Vector3.yAxis * math.sin(down)).Unit

	-- THE THING ON THE HORIZON: the lamp goes round to it, slowly, and holds it.
	local far = if t >= 0 then thing(sea, t) else nil
	launch.attention = ease(launch.attention, if far then 1 else 0, 0.35, dt)
	if far then
		launch.held = (far - lampAt).Unit
	elseif launch.attention <= 0 then
		launch.held = nil
	end
	local look = search
	local held = launch.held
	if held and launch.attention > 0 then
		-- Going round to it, holding it, and coming back from the last place it was once it has gone.
		local u = launch.attention * launch.attention * (3 - 2 * launch.attention)
		local mixed = search:Lerp(held, u)
		look = if mixed.Magnitude > 0.1 then mixed.Unit else held
	end
	launch.lamp.CFrame = CFrame.lookAt(lampAt, lampAt + look)

	-- The beam ends where it meets the water, and the pool of light is there; aimed above the water it
	-- runs out into the haze and there is no pool.
	local height = lampAt.Y - water
	local long = BEAM_LONGEST
	if look.Y < -0.02 then
		long = math.min(BEAM_LONGEST, (height - 1) / -look.Y)
	end
	launch.far.Position = Vector3.new(0, 0, -long)
	launch.beam.Width1 = math.clamp(long * 0.14, 4, 26)
	launch.pool.Enabled = look.Y < -0.02 and long < BEAM_LONGEST

	-- RAIN: the lamp a little stronger, the beam a little more there.
	launch.rain = ease(launch.rain, if t >= 0 and raining(sea, t) then 1 else 0, 0.2, dt)
	launch.spot.Brightness = 2.5 + 1.2 * launch.rain
	launch.pool.Brightness = 1.2 + 0.6 * launch.rain
	if math.abs(launch.rain - launch.shownRain) > 0.02 then
		launch.shownRain = launch.rain
		launch.beam.Transparency = fade(launch.rain)
	end
end

function SearchlightClient.start()
	for _, marker in ipairs(CollectionService:GetTagged("SunkenLaunch")) do
		add(marker)
	end
	CollectionService:GetInstanceAddedSignal("SunkenLaunch"):Connect(add)
	CollectionService:GetInstanceRemovedSignal("SunkenLaunch"):Connect(remove)
	RunService.Heartbeat:Connect(function(dt: number)
		if next(launches) == nil then
			return
		end
		local now = workspace:GetServerTimeNow()
		for marker, launch in pairs(launches) do
			if not marker.Parent then
				remove(marker)
			else
				local ok, err = pcall(stepLaunch, launch, now, dt)
				if not ok then
					-- One warning, and the launch taken down, rather than a warning every frame.
					warn("SearchlightClient: " .. tostring(err))
					remove(marker)
				end
			end
		end
	end)
	print("SearchlightClient: running, " .. SearchlightClient.VERSION)
end

SearchlightClient.STAMP = "25ab1038"
return SearchlightClient
