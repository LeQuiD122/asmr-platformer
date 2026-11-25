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

-- OVER AND UNDER ITSELF AT EACH END (the hundred-and-ninety-seventh pass). It used to turn back on the
-- very line it came up, so for as long as its body took to come round -- two hundred studs of it, two
-- thirds of every patrol -- the half going back lay in the half still coming, its head halfway along
-- its own length and its tail out past its nose. The street gives it no room to turn wide (a couple of
-- studs either side of the aquarium's tower and the dry flat), but the water under it is deep: so it
-- goes up the street at its depth and comes back down it DIVE deeper, turning over and under itself at
-- each end, and leans TURN_SIDE to one side as it goes round, so it rolls through the turn rather than
-- flipping over at the bottom of it.
-- FORTY-EIGHT, NOT TWENTY-FOUR (the hundred-and-ninety-ninth pass, seen in play): a turn twelve studs round
-- is no wider than the body is thick (nine to eleven studs from its middle to its skin), so the inside of
-- the bend had nowhere to go. Twenty-four studs round leaves the inside of the bend thirteen, and lays the
-- turn over seven joints, not three. The floor allows fifty-five. (The flat striped web seen across the
-- loop was not this but the bones' own turn flipping half over at the bottom: SeaRig.follow's `across`,
-- the two-hundred-and-first pass.)
SunkenPath.DIVE = 48
SunkenPath.TURN_SIDE = 1

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
-- off, how much deeper than its depth it is there, and how far it leans to one side: up the line,
-- over and down at the far end, back down the line DIVE deeper, and up and over at the near end, for
-- ever. Each turn is half a circle DIVE across, so no part of it is ever where another part is.
function SunkenPath.along(b: Brief, t: number, behind: number): (number, number, number)
	local span = math.max(60, b.total - b.keep)
	local r = SunkenPath.DIVE / 2
	local run = span - 2 * r -- each straight, between the middles of the two turns
	local turn = math.pi * r
	local within = (b.speed * t - behind) % (2 * run + 2 * turn)
	if within < run then
		return r + within, 0, 0
	elseif within < run + turn then
		local a = (within - run) / r
		return span - r + r * math.sin(a), r - r * math.cos(a), SunkenPath.TURN_SIDE * math.sin(a)
	elseif within < 2 * run + turn then
		return span - r - (within - run - turn), 2 * r, 0
	end
	local a = (within - 2 * run - turn) / r
	return r - r * math.sin(a), r + r * math.cos(a), SunkenPath.TURN_SIDE * math.sin(a)
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
	local s, drop, lean = SunkenPath.along(b, t, behind)
	local at, dir = SunkenPath.walk(b, s)
	-- Off the line: a slow wander that depends on where it is rather than when, so the whole body
	-- follows the same curve, plus the sway travelling down it, plus its lean through a turn.
	local side = Vector3.new(-dir.Z, 0, dir.X)
	local wander = b.swing * math.sin(2 * math.pi * s / b.swingWave)
	local sway = SunkenPath.SWAY * math.sin(2 * math.pi * (behind / SunkenPath.SWAY_WAVE - t / SunkenPath.SWAY_PERIOD))
	local y = b.waterY - b.depth - drop + b.bob * math.sin(2 * math.pi * (t - behind / b.speed) / b.bobPeriod)
	local here = at + side * (wander + sway + lean)
	here = Vector3.new(here.X, y, here.Z)
	-- THE HEAVE: near the spot, while it is surfacing, the body rises toward the crest. From the deeper
	-- way back it has further to come, so the heave reaches as much further along it: the same rise
	-- over each stud of its length either way, a back arching up and not a spike.
	if into and spot then
		local lift = SunkenPath.heave(into)
		if lift > 0 then
			local near = Vector3.new(here.X - spot.X, 0, here.Z - spot.Z).Magnitude
			local deeper = 1 + drop / math.max(1, b.depth - SunkenPath.CREST)
			local reach = math.max(0, 1 - near / (SunkenPath.CREST_REACH * deeper))
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

-- WHICH WAY IS ACROSS, AT EACH JOINT IN A TURN (the two-hundred-and-first pass, seen in play): for the same `count`
-- joints as `body`, the street's own across (its side, as `placed` leans toward it) where that joint is in a turn, and
-- nothing where it is on a straight; written into `out` and returned. The client rolls the body toward it through
-- each turn (SeaRig.follow), so it comes round on its side and back upright, and is never flipped half over between
-- one bone and the next. In a world direction that is the street's, never the direction of travel, so it does not
-- change as the serpent comes back.
function SunkenPath.across(b: Brief, t: number, first: number, spacing: number, count: number,
	out: { Vector3 }): { Vector3 }
	for index = 1, count do
		local s, _, lean = SunkenPath.along(b, t, first + (index - 1) * spacing)
		if lean ~= 0 then
			local _, dir = SunkenPath.walk(b, s)
			out[index] = Vector3.new(-dir.Z, 0, dir.X)
		else
			out[index] = Vector3.zero
		end
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
-- Twice what it first was, so the ride can be watched and its captions read. (A second less since the
-- two-hundred-and-fifth pass, taken off the funnel: see FUNNEL_TIME.)
SunkenPath.DRAIN_SECONDS = 12

-- THE PULL IS QUICK (the two-hundred-and-fifth pass, from your note of 2026-11-07: "the whirlpool should suck me down
-- in the first animation a bit faster"). The ride's first half, round and in down the funnel, took half its time: six
-- and a half seconds of going round before it took you under. It takes FUNNEL_TIME of the ride's time now (under five
-- seconds) and the shaft the rest, so the drop down the shaft is as long as it was. Every shot, pose and sound is
-- placed by `u`, the share of the ride's SHAPE, so they all keep their places in it; only the clock runs faster
-- through the funnel.
SunkenPath.FUNNEL_TIME = 0.4

-- `u` (the share of the ride's shape, which drainFrame and tumble take) `t` seconds into a ride of `seconds`.
function SunkenPath.drainShare(t: number, seconds: number): number
	local w = math.clamp(t / seconds, 0, 1)
	local split = SunkenPath.FUNNEL_TIME
	if w < split then
		return 0.5 * w / split
	end
	return 0.5 + 0.5 * (w - split) / (1 - split)
end

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

-- THE RIDER IS NOT STOOD STIFF AND TURNING. On top of drainFrame, `u` of the way down, `t` any clock
-- in seconds, a sequence:
--   THE GRAB (the first twentieth): thrown right back as it takes them, fighting it.
--   ROUND THE FUNNEL: still leaning back against the pull, rocked, and spun round on the spot faster
--   and faster, three whole turns by the time the funnel runs out.
--   DOWN THE SHAFT: head over heels, twice, still turning, and righted by the last tenth so they land
--   on their feet.
function SunkenPath.tumble(u: number, t: number): CFrame
	local rock = math.sin(t * 2.3)
	if u < 0.5 then
		local grab = 1 - math.clamp(u / 0.05, 0, 1)
		local settle = 1 - math.clamp((u - 0.42) / 0.08, 0, 1)
		local lean = (-0.55 - 0.45 * grab + math.sin(t * 3.1) * 0.12) * settle
		local spin = (u / 0.5) ^ 2 * 6 * math.pi
		return CFrame.Angles(0, spin, 0) * CFrame.Angles(lean, 0, rock * 0.35 * settle)
	end
	local s = (u - 0.5) / 0.5
	local e = math.min(1, s / 0.9)
	local flip = 4 * math.pi * e * e * (3 - 2 * e)
	return CFrame.Angles(0, 6 * math.pi + s * 3 * math.pi, 0) * CFrame.Angles(-flip, 0, rock * 0.2 * (1 - e))
end

-- (The flail and the joints it turns are Poses' now: ReplicatedStorage.Shared.Poses, shared with the
-- other levels' rides and the people.)

-- ===== AND ON, DOWN THE OUTFALL =====
--
-- The shaft is not the end of it. The water at the bottom goes somewhere -- out through the sluice's
-- burst door and down OUTFALL 3, a long brick culvert with a lamp every twenty studs, to the pumping
-- station at its end -- and it takes the rider with it: lifted off the grating, laid on their back in
-- the current, feet first, turning a little as it carries them, and set down on the landing in the
-- pump hall on their feet. Then the station is held on screen for REVEAL_SECONDS before the level is
-- over. `v` is how far through the outfall, `t` any clock in seconds.
SunkenPath.OUTFALL_SECONDS = 16
SunkenPath.REVEAL_SECONDS = 7

export type Outfall = { from: Vector3, mouth: Vector3, to: Vector3, waterY: number }

-- Where along the culvert `v` of the way through is, and which way it runs there: out of the sluice
-- to the culvert's mouth, then down it to the landing. Quick off the grating, slowing to the landing.
function SunkenPath.outfallAt(o: Outfall, v: number): (Vector3, Vector3)
	local e = 1 - (1 - math.clamp(v, 0, 1)) ^ 1.6
	local first, second = (o.mouth - o.from).Magnitude, (o.to - o.mouth).Magnitude
	local along = e * (first + second)
	local at, run
	if along <= first then
		at, run = o.from:Lerp(o.mouth, along / math.max(0.01, first)), o.mouth - o.from
	else
		at, run = o.mouth:Lerp(o.to, (along - first) / math.max(0.01, second)), o.to - o.mouth
	end
	local flat = Vector3.new(run.X, 0, run.Z)
	return at, if flat.Magnitude > 0.01 then flat.Unit else Vector3.xAxis
end

function SunkenPath.outfallFrame(o: Outfall, v: number, t: number): CFrame
	local at, run = SunkenPath.outfallAt(o, v)
	-- Lifted into the current over the first moments, set down on their feet over the last.
	local lift = math.clamp(v / 0.08, 0, 1) * (1 - math.clamp((v - 0.88) / 0.12, 0, 1))
	local floating = o.waterY + 0.9 + math.sin(t * 2.1) * 0.25
	local y = at.Y + (floating - at.Y) * lift
	local here = Vector3.new(at.X, y, at.Z)
	-- On their back, feet first (facing downstream and tipped back, so the head trails), turning in it, but never so far
	-- round that their head goes into the culvert's wall (it did, at half a radian: your test of 2026-10-23).
	return CFrame.lookAt(here, here + run) * CFrame.Angles(0, math.sin(t * 0.7) * 0.22 * lift, 0)
		* CFrame.Angles(math.rad(78) * lift, 0, math.sin(t * 1.4) * 0.3 * lift)
end

SunkenPath.STAMP = "4fb174ad"
return SunkenPath
