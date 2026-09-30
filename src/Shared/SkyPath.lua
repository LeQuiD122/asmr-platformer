--!strict
-- ReplicatedStorage/Shared/SkyPath.lua
-- Sky Pools' slide: where the trough goes, and where a rider is at any moment of the ride.
--
-- === Why a shared module ===
--
-- The ride used to be driven by the server writing the rider's root CFrame every frame. That is a
-- character assembly moved sixty times a second from the server, replicated to everyone, and it
-- was the reason the slide stuttered: the client kept being corrected to where the server had just
-- put it, and the rider stood upright through the whole thing because nothing ever sat them down.
--
-- Now the ride is a SLED: a seat the rider sits in (so the character sits, like any Roblox seat),
-- carried along the slide. The server starts it, keeps the clock and decides where the ride ends,
-- and hands the sled to the rider's own client; that client then works out where the sled should be
-- from the numbers here and the ride's start time and writes it each frame, so what you see is
-- smooth and costs no replication at all. Until it answers -- or if it never does -- the server
-- moves the sled itself from these same numbers, so the ride happens either way. This is what
-- SeaService does for City Shore's sea and SunkenPath does for the thing in the Sunken City.

local SkyPath = {}

-- The trough.
SkyPath.WIDE = 10
SkyPath.STEP = 9 -- studs of trough per segment
SkyPath.BANK = 0.3 -- how far it leans into the turn

-- The ride. A speed rather than a duration: the slide's length depends on how the run came out.
-- Half what it first was: the slide is played as a scene, slow enough to be watched.
SkyPath.SPEED = 36
SkyPath.MIN_SECONDS, SkyPath.MAX_SECONDS = 16, 30
SkyPath.RAMP = 0.15 -- the share of the ride spent getting up to speed
SkyPath.SAMPLES = 200
SkyPath.SIT_HEIGHT = 1.6 -- the sled's seat, this far over the trough's floor

export type Spec = {
	centre: Vector3,
	angle0: number,
	radius0: number,
	radius1: number,
	y0: number,
	y1: number,
	turns: number,
}

-- The slide's shape, as SkyPoolsService wrote it onto the level's model.
function SkyPath.read(model: Instance): Spec?
	local function num(name: string): number?
		local value = model:GetAttribute(name)
		return if typeof(value) == "number" then value else nil
	end
	local centre = model:GetAttribute("SlideCentre")
	local angle0, radius0, radius1 = num("SlideAngle0"), num("SlideRadius0"), num("SlideRadius1")
	local y0, y1, turns = num("SlideY0"), num("SlideY1"), num("SlideTurns")
	if typeof(centre) ~= "Vector3" or not (angle0 and radius0 and radius1 and y0 and y1 and turns) then
		return nil
	end
	return { centre = centre, angle0 = angle0, radius0 = radius0, radius1 = radius1, y0 = y0, y1 = y1, turns = turns }
end

-- A point on the trough's floor at f in [0, 1]: round the tower, in from the mouth to over the
-- pool, and down on a smoothstep, so it leaves the deck level, is steepest in the clouds, and
-- levels out over the water.
function SkyPath.point(spec: Spec, f: number): Vector3
	local theta = spec.angle0 + f * spec.turns * 2 * math.pi
	local radius = spec.radius0 + (spec.radius1 - spec.radius0) * f
	local ease = f * f * (3 - 2 * f)
	return Vector3.new(spec.centre.X + math.cos(theta) * radius, spec.y0 + (spec.y1 - spec.y0) * ease,
		spec.centre.Z + math.sin(theta) * radius)
end

-- The trough's up, banked into the turn so a rider leans the way a slide makes you lean.
function SkyPath.up(spec: Spec, f: number): Vector3
	local here = SkyPath.point(spec, f)
	local inward = Vector3.new(spec.centre.X - here.X, 0, spec.centre.Z - here.Z)
	if inward.Magnitude < 0.01 then
		return Vector3.yAxis
	end
	return (Vector3.yAxis + inward.Unit * SkyPath.BANK).Unit
end

-- Distance along the slide at even steps of f. The ring is several times further round at the top
-- than at the bottom, so riding f evenly would be fastest at the start and slowest into the pool,
-- which is backwards.
function SkyPath.distances(spec: Spec): { number }
	local out = { 0 }
	local last = SkyPath.point(spec, 0)
	for index = 1, SkyPath.SAMPLES do
		local here = SkyPath.point(spec, index / SkyPath.SAMPLES)
		out[index + 1] = out[index] + (here - last).Magnitude
		last = here
	end
	return out
end

function SkyPath.length(distances: { number }): number
	return distances[#distances]
end

-- How long the ride takes: the slide's length at the ride's speed, kept inside its bounds.
function SkyPath.seconds(distances: { number }): number
	return math.clamp(SkyPath.length(distances) / SkyPath.SPEED, SkyPath.MIN_SECONDS, SkyPath.MAX_SECONDS)
end

-- Where `s` studs along the slide falls, as an f.
function SkyPath.at(distances: { number }, s: number): number
	if s <= 0 then
		return 0
	end
	local total = distances[#distances]
	if s >= total then
		return 1
	end
	local low, high = 1, #distances
	while high - low > 1 do
		local mid = (low + high) // 2
		if distances[mid] <= s then
			low = mid
		else
			high = mid
		end
	end
	local span = distances[high] - distances[low]
	local within = if span > 0 then (s - distances[low]) / span else 0
	return ((low - 1) + within) / SkyPath.SAMPLES
end

-- How far along the slide the rider is at `u` of the ride: speeding up from standing over the first
-- stretch, then steady, so it sets off like a slide rather than firing you off the deck.
function SkyPath.share(u: number): number
	local ramp = SkyPath.RAMP
	local norm = 1 - ramp / 2
	if u < ramp then
		return (u * u / (2 * ramp)) / norm
	end
	return (u - ramp / 2) / norm
end

-- ===== THE SKIM =====
--
-- THE SLIDE DOES NOT JUST STOP AT THE WATER. Where the trough runs out, level, at the pool's surface,
-- the sled carries on across the pool: it skips, three hops each lower than the last, throwing spray at
-- every touch, slews round as it slows, and settles; then you tip out into the water. The end of the
-- ride was a stop and a splash; this is the part with the action in it. Straight on from the trough's
-- last stretch, so it only ever goes further round the pool, never in at the tower.
SkyPath.SKIM_SECONDS = 2.8
-- Each hop: when it leaves the water, when it comes down, and how high it goes.
SkyPath.HOPS = {
	{ 0, 0.8, 3.4 },
	{ 0.8, 1.45, 1.8 },
	{ 1.45, 1.9, 0.7 },
}

-- The way the trough is going as it runs out, level.
local function runOut(spec: Spec): Vector3
	local last = SkyPath.point(spec, 1)
	local before = SkyPath.point(spec, 0.985)
	local flat = Vector3.new(last.X - before.X, 0, last.Z - before.Z)
	return if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
end

-- Where the sled is `s` seconds into the skim.
function SkyPath.skimFrame(spec: Spec, s: number): CFrame
	local skim = SkyPath.SKIM_SECONDS
	local t = math.clamp(s, 0, skim)
	local dir = runOut(spec)
	local speed = SkyPath.SPEED
	-- Slowing evenly to a stop at the end.
	local along = speed * t - 0.5 * (speed / skim) * t * t
	local hop = 0
	for _, h in ipairs(SkyPath.HOPS) do
		if t >= h[1] and t < h[2] then
			local u = (t - h[1]) / (h[2] - h[1])
			hop = h[3] * 4 * u * (1 - u)
		end
	end
	-- Settling into the water over the last half second.
	local sink = if t > skim - 0.5 then (t - (skim - 0.5)) / 0.5 * 1.2 else 0
	local at = SkyPath.point(spec, 1) + Vector3.new(0, SkyPath.SIT_HEIGHT, 0) + dir * along + Vector3.new(0, hop - sink, 0)
	local slew = 1.3 * (t / skim) ^ 1.6
	-- Nose up on the way up a hop and down on the way down, a little.
	local pitch = 0
	for _, h in ipairs(SkyPath.HOPS) do
		if t >= h[1] and t < h[2] then
			pitch = 0.18 * (1 - 2 * (t - h[1]) / (h[2] - h[1])) * h[3] / 3.4
		end
	end
	return CFrame.lookAt(at, at + dir) * CFrame.Angles(0, slew, 0) * CFrame.Angles(pitch, 0, 0)
end

-- Where the skim stops, on the water's surface: where the rider tips out.
function SkyPath.skimEnd(spec: Spec): Vector3
	local speed = SkyPath.SPEED
	return SkyPath.point(spec, 1) + runOut(spec) * (speed * SkyPath.SKIM_SECONDS * 0.5)
end

-- Where the sled sits at `u` of the ride, facing the way it is going and leaning with the trough.
function SkyPath.rideFrame(spec: Spec, distances: { number }, u: number): CFrame
	local total = distances[#distances]
	local travelled = math.clamp(SkyPath.share(math.clamp(u, 0, 1)), 0, 1) * total
	local f = SkyPath.at(distances, travelled)
	local up = SkyPath.up(spec, f)
	local here = SkyPath.point(spec, f) + up * SkyPath.SIT_HEIGHT
	local ahead = SkyPath.point(spec, SkyPath.at(distances, math.min(total, travelled + 4))) + up * SkyPath.SIT_HEIGHT
	if (ahead - here).Magnitude < 0.05 then
		return CFrame.new(here)
	end
	return CFrame.lookAt(here, ahead, up)
end

return SkyPath
