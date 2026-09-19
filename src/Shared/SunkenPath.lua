--!strict
-- ReplicatedStorage/Shared/SunkenPath.lua
-- Where the Sunken City's thing is, and when it surfaces: one answer for the server and every client.
--
-- === Why a shared module ===
--
-- The clients draw the thing (SunkenCityClient) and the server decides who it takes (SunkenCityService).
-- Both have to agree to the stud about where it is and to the second about when it comes up, or a
-- player would be taken by a surfacing they saw happen somewhere else. So the path and the schedule
-- live here, once, and both sides work them out from the same numbers (the attributes
-- SunkenCityService puts on the sea model) and the same clock (workspace:GetServerTimeNow).
--
-- === The surfacing (ROADMAP section 6: a monster that resets you to spawn, telegraphed first) ===
--
-- Every SURFACE_EVERY seconds, while it is on the boulevard under the route and not swinging round
-- the harbour, it comes up. For WARN seconds first the sound goes, bubbles rise and the water
-- darkens over the spot. Then its back heaves up just under the surface and its fins cut through
-- it, and WASH_AT seconds in a surge of spray goes over the route. A Hardcore player standing within
-- WASH_RADIUS of the spot is taken back to the start; in Chill it only watches.

local SunkenPath = {}

-- The body, as the client draws it.
SunkenPath.SEGMENTS = 18
SunkenPath.SPACING = 11 -- studs between segments along the path
SunkenPath.SWAY = 2.5 -- side to side, a wave travelling down the body
SunkenPath.SWAY_WAVE = 48
SunkenPath.SWAY_PERIOD = 5

-- The surfacing.
SunkenPath.SURFACE_FIRST = 45 -- seconds after the level is built
SunkenPath.SURFACE_EVERY = 80
SunkenPath.WARN = 5
SunkenPath.BREACH = 3.5
SunkenPath.WASH_AT = 1.2
SunkenPath.WASH_RADIUS = 26
-- At the top of the surfacing its centre line is this far under the water: its back just under
-- the surface and its fins through it, and still clear of the undersides of the chunks overhead.
SunkenPath.CREST = 7
SunkenPath.CREST_REACH = 40 -- how far along its body from the spot the heave reaches
SunkenPath.QUIET_MARGIN = 12 -- and how much further than that it keeps from a road sign

export type Brief = {
	centre: Vector3,
	radius: number,
	speed: number,
	depth: number,
	bob: number,
	bobPeriod: number,
	girth: number,
	harbour: number,
	swerve: number,
	swerveHalf: number,
	waterY: number,
	epoch: number,
	startAngle: number,
	-- Angles round the ring where it never surfaces: the road signs hang there, just under the water,
	-- and its back would come up through them.
	quiet: { number },
}

-- The brief from the sea model's attributes, or nil if any of it is missing.
function SunkenPath.read(model: Instance): Brief?
	local function num(name: string): number?
		local value = model:GetAttribute(name)
		return if typeof(value) == "number" then value else nil
	end
	local centre = model:GetAttribute("MonsterCentre")
	local radius, speed, depth = num("MonsterRadius"), num("MonsterSpeed"), num("MonsterDepth")
	local harbour, waterY, epoch = num("HarbourAngle"), num("WaterY"), num("Epoch")
	if typeof(centre) ~= "Vector3" or not (radius and speed and depth and harbour and waterY and epoch) then
		return nil
	end
	local quiet = {}
	local list = model:GetAttribute("QuietAngles")
	if typeof(list) == "string" then
		for word in string.gmatch(list, "[^,]+") do
			local value = tonumber(word)
			if value then
				table.insert(quiet, value)
			end
		end
	end
	return {
		quiet = quiet,
		centre = centre,
		radius = radius,
		speed = speed,
		depth = depth,
		bob = num("MonsterBob") or 5,
		bobPeriod = num("MonsterBobPeriod") or 47,
		girth = num("MonsterGirth") or 8,
		harbour = harbour,
		swerve = num("HarbourSwerve") or 80,
		swerveHalf = num("HarbourSwerveHalf") or 0.6,
		waterY = waterY,
		epoch = epoch,
		-- Setting off from across the ring from the harbour.
		startAngle = harbour + math.pi,
	}
end

-- How far out it swings at this angle: a smooth bump round the harbour, nothing elsewhere.
function SunkenPath.swerveAt(b: Brief, theta: number): number
	local d = (theta - b.harbour + math.pi) % (2 * math.pi) - math.pi
	if math.abs(d) >= b.swerveHalf then
		return 0
	end
	return b.swerve * 0.5 * (1 + math.cos(math.pi * d / b.swerveHalf))
end

-- The angle round the ring of the point `behind` studs back from its head, `t` seconds after it set
-- off. It swims the other way to the route, so the angle falls as time goes on.
function SunkenPath.angle(b: Brief, t: number, behind: number): number
	return b.startAngle - (b.speed / b.radius) * t + behind / b.radius
end

-- The surfacing under way at time `t`, if any: how far into it (negative while the warning runs)
-- and the spot, on the water's surface, where its head was when it broke it. Never in the harbour,
-- where it is swinging wide of the drain and nowhere near the route.
function SunkenPath.surfacing(b: Brief, t: number): (number?, Vector3?, number?)
	local warn, every, breach = SunkenPath.WARN, SunkenPath.SURFACE_EVERY, SunkenPath.BREACH
	if t < SunkenPath.SURFACE_FIRST - warn then
		return nil, nil, nil
	end
	local index = math.floor((t - SunkenPath.SURFACE_FIRST + warn) / every)
	local start = SunkenPath.SURFACE_FIRST + index * every
	local into = t - start
	if into < -warn or into > breach then
		return nil, nil, nil
	end
	local theta = SunkenPath.angle(b, start, 0)
	if SunkenPath.swerveAt(b, theta) > 0 then
		return nil, nil, nil
	end
	-- Nor anywhere its heave would reach a road sign: the heave runs CREST_REACH either way along it.
	local clear = (SunkenPath.CREST_REACH + SunkenPath.QUIET_MARGIN) / b.radius
	for _, angle in ipairs(b.quiet) do
		if math.abs((theta - angle + math.pi) % (2 * math.pi) - math.pi) < clear then
			return nil, nil, nil
		end
	end
	return into, Vector3.new(b.centre.X + math.cos(theta) * b.radius, b.waterY, b.centre.Z + math.sin(theta) * b.radius), index
end

-- How much of the heave there is at `into` seconds into a surfacing: none before it, rising to all
-- of it halfway through, and gone at the end.
function SunkenPath.heave(into: number): number
	if into <= 0 or into >= SunkenPath.BREACH then
		return 0
	end
	return math.sin(math.pi * into / SunkenPath.BREACH)
end

-- A point on its body `behind` studs back from the head, at time `t` since it set off.
function SunkenPath.point(b: Brief, t: number, behind: number): Vector3
	local theta = SunkenPath.angle(b, t, behind)
	local r = b.radius + SunkenPath.swerveAt(b, theta)
		+ SunkenPath.SWAY * math.sin(2 * math.pi * (behind / SunkenPath.SWAY_WAVE - t / SunkenPath.SWAY_PERIOD))
	local y = b.waterY - b.depth + b.bob * math.sin(2 * math.pi * (t - behind / b.speed) / b.bobPeriod)
	local here = Vector3.new(b.centre.X + math.cos(theta) * r, y, b.centre.Z + math.sin(theta) * r)
	-- THE HEAVE: near the spot, while it is surfacing, the body rises toward the crest.
	local into, spot = SunkenPath.surfacing(b, t)
	if into and spot then
		local lift = SunkenPath.heave(into)
		if lift > 0 then
			local near = Vector3.new(here.X - spot.X, 0, here.Z - spot.Z).Magnitude
			local reach = math.max(0, 1 - near / SunkenPath.CREST_REACH)
			local crest = b.waterY - SunkenPath.CREST
			here = Vector3.new(here.X, y + (crest - y) * lift * reach, here.Z)
		end
	end
	return here
end

return SunkenPath
