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
-- === It follows the route now, because the route goes somewhere ===
--
-- The level used to be a ring and the thing swam the ring, so its position was an angle and the
-- whole of this module was trigonometry. The route is a meander now -- a line that sets off and
-- keeps going -- so the thing PATROLS it: up the line and back down it, out of sight past either
-- end, wandering a little off it as it goes. A line has no angles, so everything here is measured
-- in studs travelled along it instead. Its shape is the same and so is what it does.
--
-- It turns back short of the far end, because the far end is the harbour and the drain, and the
-- drain is not somewhere anything should be swimming.
--
-- === The surfacing (ROADMAP section 6: a monster that resets you to spawn, telegraphed first) ===
--
-- Every SURFACE_EVERY seconds, while it is under the route and not near the harbour, it comes up.
-- For WARN seconds first the sound goes, bubbles rise and the water darkens over the spot. Then its
-- back heaves up just under the surface and its fins cut through it, and WASH_AT seconds in a surge
-- of spray goes over the route. A Hardcore player standing within WASH_RADIUS of the spot is taken
-- back to the start; in Chill it only watches.

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
	-- The route's line in plan, and how long it is. Everything else is measured along it.
	points: { Vector3 },
	steps: { number },
	total: number,
	keep: number, -- it turns back this far short of the end, where the harbour is
	speed: number,
	depth: number,
	bob: number,
	bobPeriod: number,
	girth: number,
	swing: number, -- how far off the line it wanders
	swingWave: number,
	waterY: number,
	epoch: number,
	-- Distances along the route where the road signs hang, just under the water: it never surfaces
	-- there, because its back would come up through them.
	quiet: { number },
}

-- The brief from the sea model's attributes, or nil if any of it is missing.
function SunkenPath.read(model: Instance): Brief?
	local function num(name: string): number?
		local value = model:GetAttribute(name)
		return if typeof(value) == "number" then value else nil
	end
	local function numbers(name: string): { number }
		local out = {}
		local list = model:GetAttribute(name)
		if typeof(list) == "string" then
			for word in string.gmatch(list, "[^,]+") do
				local value = tonumber(word)
				if value then
					table.insert(out, value)
				end
			end
		end
		return out
	end

	local speed, depth = num("MonsterSpeed"), num("MonsterDepth")
	local waterY, epoch = num("WaterY"), num("Epoch")
	if not (speed and depth and waterY and epoch) then
		return nil
	end
	-- THE LINE, as "x,z;x,z;...". A string rather than a folder of parts: it is read once on each
	-- client, it never changes while the level stands, and an attribute replicates with the model.
	local points: { Vector3 } = {}
	local line = model:GetAttribute("MonsterLine")
	if typeof(line) == "string" then
		for pair in string.gmatch(line, "[^;]+") do
			local x, z = string.match(pair, "([^,]+),([^,]+)")
			local px, pz = tonumber(x), tonumber(z)
			if px and pz then
				table.insert(points, Vector3.new(px, waterY, pz))
			end
		end
	end
	if #points < 2 then
		return nil
	end
	local steps = { 0 }
	for index = 2, #points do
		steps[index] = steps[index - 1] + (points[index] - points[index - 1]).Magnitude
	end
	return {
		points = points,
		steps = steps,
		total = steps[#steps],
		keep = num("MonsterKeep") or 140,
		speed = speed,
		depth = depth,
		bob = num("MonsterBob") or 5,
		bobPeriod = num("MonsterBobPeriod") or 47,
		girth = num("MonsterGirth") or 8,
		swing = num("MonsterSwing") or 26,
		swingWave = num("MonsterSwingWave") or 340,
		waterY = waterY,
		epoch = epoch,
		quiet = numbers("QuietAlong"),
	}
end

-- The point on the route's line `s` studs along it, and the way the line runs there.
function SunkenPath.walk(b: Brief, s: number): (Vector3, Vector3)
	local total = b.total
	local at = math.clamp(s, 0, total)
	local low, high = 1, #b.steps
	while high - low > 1 do
		local mid = (low + high) // 2
		if b.steps[mid] <= at then
			low = mid
		else
			high = mid
		end
	end
	local span = b.steps[high] - b.steps[low]
	local within = if span > 0 then (at - b.steps[low]) / span else 0
	local from, to = b.points[low], b.points[high]
	local run = to - from
	local dir = if run.Magnitude > 0.001 then run.Unit else Vector3.new(0, 0, 1)
	return from + run * within, dir
end

-- How far along the line a point `behind` studs back from the head is, `t` seconds after it set
-- off: up the line and back down it, for ever. The body folds round the turn, which is what a long
-- animal doubling back actually does.
function SunkenPath.along(b: Brief, t: number, behind: number): number
	local span = math.max(60, b.total - b.keep)
	local travelled = b.speed * t - behind
	local cycle = 2 * span
	local within = travelled % cycle
	return if within <= span then within else cycle - within
end

-- The surfacing under way at time `t`, if any: how far into it (negative while the warning runs)
-- and the spot, on the water's surface, where its head was when it broke it. Never where a road
-- sign hangs, and never so near either end of the patrol that it comes up outside the city.
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
	local s = SunkenPath.along(b, start, 0)
	local edge = SunkenPath.CREST_REACH + SunkenPath.QUIET_MARGIN
	if s < edge or s > math.max(60, b.total - b.keep) - edge then
		return nil, nil, nil
	end
	for _, quiet in ipairs(b.quiet) do
		if math.abs(s - quiet) < edge then
			return nil, nil, nil
		end
	end
	local at = SunkenPath.walk(b, s)
	return into, Vector3.new(at.X, b.waterY, at.Z), index
end

-- How much of the heave there is at `into` seconds into a surfacing: none before it, rising to all
-- of it halfway through, and gone at the end.
function SunkenPath.heave(into: number): number
	if into <= 0 or into >= SunkenPath.BREACH then
		return 0
	end
	return math.sin(math.pi * into / SunkenPath.BREACH)
end

-- A point on its body `behind` studs back from the head, at time `t` since it set off, given the
-- surfacing under way at `t` (`into` and `spot`, nil when there is none).
local function placed(b: Brief, t: number, behind: number, into: number?, spot: Vector3?): Vector3
	local s = SunkenPath.along(b, t, behind)
	local at, dir = SunkenPath.walk(b, s)
	-- Off the line: a slow wander that depends on where it is rather than when, so the whole body
	-- follows the same curve, plus the sway travelling down it.
	local side = Vector3.new(-dir.Z, 0, dir.X)
	local wander = b.swing * math.sin(2 * math.pi * s / b.swingWave)
	local sway = SunkenPath.SWAY * math.sin(2 * math.pi * (behind / SunkenPath.SWAY_WAVE - t / SunkenPath.SWAY_PERIOD))
	local y = b.waterY - b.depth + b.bob * math.sin(2 * math.pi * (t - behind / b.speed) / b.bobPeriod)
	local here = at + side * (wander + sway)
	here = Vector3.new(here.X, y, here.Z)
	-- THE HEAVE: near the spot, while it is surfacing, the body rises toward the crest.
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

function SunkenPath.point(b: Brief, t: number, behind: number): Vector3
	local into, spot = SunkenPath.surfacing(b, t)
	return placed(b, t, behind, into, spot)
end

-- THE WHOLE BODY AT ONCE: `count` points `spacing` apart from `first` studs behind the head, written
-- into `out` and returned. The same points `point` gives, with the surfacing worked out once for all
-- of them rather than once a point: the client asks for nineteen of them every frame.
function SunkenPath.body(b: Brief, t: number, first: number, spacing: number, count: number,
	out: { Vector3 }): { Vector3 }
	local into, spot = SunkenPath.surfacing(b, t)
	for index = 1, count do
		out[index] = placed(b, t, first + (index - 1) * spacing, into, spot)
	end
	return out
end

-- ===== THE DRAIN'S RIDE =====
--
-- Where a rider is at `u` of the way down: round and in, down the funnel, then straight down the
-- current, still turning. Here rather than in the service because the rider's OWN CLIENT draws it,
-- for the reason Sky Pools' slide is drawn there -- a character moved from the server sixty times a
-- second stutters, and the one client that owns that character can move it for nothing. The server
-- still keeps the clock and still says where you land.
SunkenPath.DRAIN_SECONDS = 6.5

export type Drain = {
	vortex: Vector3,
	from: Vector3,
	funnelY: number,
	bottomY: number,
}

function SunkenPath.drainFrame(d: Drain, u: number): CFrame
	local flat = Vector3.new(d.from.X - d.vortex.X, 0, d.from.Z - d.vortex.Z)
	local r0 = math.max(2, flat.Magnitude)
	local a0 = math.atan2(flat.Z, flat.X)
	local here: Vector3
	local facing: Vector3
	if u < 0.5 then
		-- Round and in, down the funnel.
		local s = u / 0.5
		local r = r0 + (1.5 - r0) * s
		local a = a0 + s * 2.2 * 2 * math.pi
		here = Vector3.new(d.vortex.X + math.cos(a) * r, d.from.Y + (d.funnelY - d.from.Y) * s * s,
			d.vortex.Z + math.sin(a) * r)
		facing = Vector3.new(-math.sin(a), 0, math.cos(a))
	else
		-- Straight down the current, faster and faster, still turning.
		local s = (u - 0.5) / 0.5
		local a = a0 + 2.2 * 2 * math.pi + s * 3 * 2 * math.pi
		here = Vector3.new(d.vortex.X + math.cos(a) * 1.2, d.funnelY + (d.bottomY - d.funnelY) * s * s,
			d.vortex.Z + math.sin(a) * 1.2)
		facing = Vector3.new(math.cos(a), 0, math.sin(a))
	end
	return CFrame.lookAt(here, here + facing)
end

return SunkenPath
