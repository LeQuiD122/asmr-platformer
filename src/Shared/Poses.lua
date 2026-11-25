--!strict
-- ReplicatedStorage/Shared/Poses.lua
-- What a body does in this game's cut-scenes and its people's lives: the joints of a character,
-- whichever kind they are, and the poses the rides and the people put them in. Shared, because the
-- server poses the people and a rider whose own client is not running, and every client poses the
-- riders it sees -- from the same numbers.
--
-- === A character's joints, whichever kind they are ===
--
-- A character's joints are Motor6Ds -- or, with Roblox's newer avatar joints, AnimationConstraints
-- between a rig attachment on each part, and a character built that way has no Motor6D at all. A
-- player here has fifteen AnimationConstraints and not one Motor6D, so anything that turns only
-- Motor6Ds turns nothing (the drain's rider once went down with their arms still, and the fisherman
-- stood beside his crate instead of sitting on it). So a joint is found either way:
--
--   `drive`   sets it the client's way, through what an animation writes (its Transform), smooth,
--             and seen by that client only;
--   `turn`    offsets it from its rest on the server (a Motor6D's C0, or the AnimationConstraint's
--             parent-side attachment), which every client is sent.
--
-- === The poses ===
--
-- Each is a joint's turn from its rest, `t` seconds in, at `w` of its full swing, by the joint's
-- name: R15's in the character's own axes (a shoulder's +Z lifts the right arm out and up and -Z the
-- left, +X swings a limb forward, a knee's -X bends it back, the neck's +X tips the head back), R6's
-- about their own Z, which is how the default animations turn them. nil for a joint a pose leaves
-- alone.

local Poses = {}

export type Joint = { name: string, driver: Instance, motor: Motor6D?, attachment: Attachment?, rest: CFrame }

function Poses.joints(model: Instance): { [string]: Joint }
	local found: { [string]: Joint } = {}
	for _, item in ipairs(model:GetDescendants()) do
		if item:IsA("Motor6D") then
			found[item.Name] = { name = item.Name, driver = item, motor = item, rest = item.C0 }
		elseif item:IsA("AnimationConstraint") and not found[item.Name] then
			local attachment = item.Attachment0
			if attachment then
				found[item.Name] = { name = item.Name, driver = item, attachment = attachment, rest = attachment.CFrame }
			end
		end
	end
	return found
end

-- Turns `joint` from its rest by `by`, on the server; CFrame.identity puts it back.
function Poses.turn(joint: Joint, by: CFrame)
	local motor, attachment = joint.motor, joint.attachment
	if motor then
		motor.C0 = joint.rest * by
	elseif attachment then
		attachment.CFrame = joint.rest * by
	end
end

-- Sets `joint` to `by` the client's way; CFrame.identity lets the animations have it back.
function Poses.drive(joint: Joint, by: CFrame)
	(joint.driver :: any).Transform = by
end

-- Whether a set of joints is an R6 body (which has a Neck too, turning about a different axis).
function Poses.isR6(joints: { [string]: Joint }): boolean
	return joints.RightShoulder == nil and joints["Right Shoulder"] ~= nil
end

-- How much of a pose there is, `t` seconds into `seconds` of it: in over the first 0.3, out over the
-- last 0.4.
function Poses.weight(t: number, seconds: number): number
	return math.clamp(math.min(t / 0.3, (seconds - t) / 0.4), 0, 1)
end

-- THE FLAIL: pulled away by the water. Arms thrown up and out and waving, elbows working, legs
-- kicking, head thrown back shouting.
function Poses.flail(name: string, t: number, w: number, r6: boolean): CFrame?
	if r6 then
		if name == "Right Shoulder" then
			return CFrame.Angles(0, 0, (2.6 + 0.6 * math.sin(t * 13)) * w)
		elseif name == "Left Shoulder" then
			return CFrame.Angles(0, 0, -(2.6 + 0.6 * math.sin(t * 13 + 2)) * w)
		elseif name == "Right Hip" or name == "Left Hip" then
			return CFrame.Angles(0, 0, 0.8 * math.sin(t * 11) * w)
		elseif name == "Neck" then
			return CFrame.Angles(-0.45 * w, 0, 0.35 * math.sin(t * 5) * w)
		end
		return nil
	end
	if name == "RightShoulder" then
		return CFrame.Angles(0.3 * math.sin(t * 9) * w, 0, (2.3 + 0.55 * math.sin(t * 13)) * w)
	elseif name == "LeftShoulder" then
		return CFrame.Angles(0.3 * math.sin(t * 9 + 1.3) * w, 0, -(2.3 + 0.55 * math.sin(t * 13 + 2)) * w)
	elseif name == "RightElbow" then
		return CFrame.Angles((0.5 + 0.5 * math.sin(t * 15)) * w, 0, 0)
	elseif name == "LeftElbow" then
		return CFrame.Angles((0.5 + 0.5 * math.sin(t * 15 + 1.6)) * w, 0, 0)
	elseif name == "RightHip" then
		return CFrame.Angles(0.7 * math.sin(t * 11) * w, 0, 0.2 * w)
	elseif name == "LeftHip" then
		return CFrame.Angles(0.7 * math.sin(t * 11 + math.pi) * w, 0, -0.2 * w)
	elseif name == "RightKnee" then
		return CFrame.Angles(-(0.35 + 0.55 * math.abs(math.sin(t * 11))) * w, 0, 0)
	elseif name == "LeftKnee" then
		return CFrame.Angles(-(0.35 + 0.55 * math.abs(math.sin(t * 11 + 1.2))) * w, 0, 0)
	elseif name == "Neck" then
		return CFrame.Angles((0.45 + 0.12 * math.sin(t * 7)) * w, 0.35 * math.sin(t * 5) * w, 0)
	elseif name == "Waist" then
		return CFrame.Angles(0.15 * math.sin(t * 6) * w, 0.25 * math.sin(t * 4.3) * w, 0)
	end
	return nil
end

-- THE DIVE: off the board in a swan -- arms spread wide, back arched, head up -- and then, as the
-- body turns over, arms together over the head and legs straight together, to go in clean. The swan
-- is held for most of a second and closes over a whole one, since the fall is slowed to be watched.
-- AND IT IS A BODY IN THE AIR, NOT A STATUE: the push off the board (knees driving straight over the first
-- third of a second), and once it has closed, the wind buffeting it all the way down (a little flutter in the
-- arms, the legs working against each other, the head braced), so the fall looks fought, not floated.
function Poses.dive(name: string, t: number, w: number, r6: boolean): CFrame?
	local close = math.clamp((t - 0.8) / 1.0, 0, 1)
	close = close * close * (3 - 2 * close)
	local spread = 1.55 + (2.95 - 1.55) * close
	local push = 1 - math.clamp(t / 0.32, 0, 1)
	local buffet = close * math.clamp((t - 1.8) / 0.6, 0, 1)
	local function gust(seed: number, rate: number): number
		return math.noise(t * rate, seed) * buffet
	end
	if r6 then
		if name == "Right Shoulder" then
			return CFrame.Angles(0, 0, math.pi * close * w)
		elseif name == "Left Shoulder" then
			return CFrame.Angles(0, 0, -math.pi * close * w)
		elseif name == "Neck" then
			return CFrame.Angles(-0.35 * (1 - close) * w, 0, 0)
		end
		return nil
	end
	if name == "RightShoulder" then
		return CFrame.Angles(0.12 * gust(1.1, 5) * w, 0, (spread + 0.14 * gust(2.3, 6)) * w)
	elseif name == "LeftShoulder" then
		return CFrame.Angles(0.12 * gust(3.7, 5) * w, 0, -(spread + 0.14 * gust(4.1, 6)) * w)
	elseif name == "RightElbow" then
		return CFrame.Angles((0.1 * (1 - close) + 0.18 * math.abs(gust(5.9, 7))) * w, 0, 0)
	elseif name == "LeftElbow" then
		return CFrame.Angles((0.1 * (1 - close) + 0.18 * math.abs(gust(6.3, 7))) * w, 0, 0)
	elseif name == "Neck" then
		return CFrame.Angles((0.4 - 0.9 * close + 0.08 * gust(7.7, 4)) * w, 0.1 * gust(8.2, 3) * w, 0)
	elseif name == "Waist" then
		return CFrame.Angles((0.25 * (1 - close) + 0.06 * gust(9.4, 3)) * w, 0.08 * gust(9.9, 2.5) * w, 0)
	elseif name == "RightHip" then
		return CFrame.Angles((-0.12 * (1 - close) + 0.5 * push + 0.16 * gust(10.6, 6)) * w, 0, 0)
	elseif name == "LeftHip" then
		return CFrame.Angles((-0.12 * (1 - close) + 0.5 * push - 0.16 * gust(10.6, 6)) * w, 0, 0)
	elseif name == "RightKnee" or name == "LeftKnee" then
		return CFrame.Angles(-1.0 * push * w, 0, 0)
	end
	return nil
end

-- THE SLED: sat in it, arms up the way everyone rides a slide, head back into the wind, and every so
-- often a wave. Joints the sitting animation already has (hips, knees) are left to it.
function Poses.sled(name: string, t: number, w: number, r6: boolean): CFrame?
	local wave = math.sin(t * 7)
	if r6 then
		if name == "Right Shoulder" then
			return CFrame.Angles(0, 0, (2.8 + 0.2 * wave) * w)
		elseif name == "Left Shoulder" then
			return CFrame.Angles(0, 0, -(2.8 - 0.2 * wave) * w)
		end
		return nil
	end
	if name == "RightShoulder" then
		return CFrame.Angles(0.15 * wave * w, 0, (2.6 + 0.25 * wave) * w)
	elseif name == "LeftShoulder" then
		return CFrame.Angles(-0.15 * wave * w, 0, -(2.6 - 0.25 * wave) * w)
	elseif name == "RightElbow" or name == "LeftElbow" then
		return CFrame.Angles(0.35 * w, 0, 0)
	elseif name == "Neck" then
		return CFrame.Angles((0.3 + 0.08 * math.sin(t * 3)) * w, 0.25 * math.sin(t * 1.3) * w, 0)
	end
	return nil
end

-- THE FLUME, the way a person rides one, not a statue stood in it. The rider's own client lays the body
-- back in the trough, feet first (FloodedHallsClient: RECLINE, over FLUME_LIE seconds); this is what the
-- body does inside that, `t` seconds into the ride:
--   THE PUSH OFF (to 0.9)   sat up and laid back, hands on the trough's edges, head forward.
--   BALANCING (to 3)        arms out wide along the walls, legs together along the floor, watching ahead.
--   PANIC (to the tube's end) it does not stop going down: grabbing at the walls one hand and then the
--                           other, heels scrabbling for grip, the head snapping round, leaning into the turn.
--   THE FALL (after it)     out of the end of the tube into the dark: arms windmilling, legs kicking.
-- The hips are bent by exactly what keeps the legs along the floor while the back is laid back.
Poses.FLUME_SECONDS = 11 -- FloodedHallsService's SLIDE_SECONDS
Poses.FLUME_TUBE = 0.68 * 11 -- its SLIDE_HELIX of it: the tube, and then the fall
Poses.FLUME_LIE = 0.6 -- seconds to lie back after the push off
Poses.FLUME_RECLINE = math.rad(62) -- how far back the body lies (FloodedHallsClient turns the root by it)

function Poses.flume(name: string, t: number, w: number, r6: boolean): CFrame?
	local function ease(x: number): number
		x = math.clamp(x, 0, 1)
		return x * x * (3 - 2 * x)
	end
	local toBalance = ease((t - 0.7) / 0.4)
	local toPanic = ease((t - 2.8) / 0.8)
	local toFall = ease((t - (Poses.FLUME_TUBE - 0.2)) / 0.4)
	-- grip, balance, panic, fall: one joint's three angles in each, blended in that order.
	local function blend(grip: { number }, balance: { number }, panic: { number }, fall: { number }): CFrame
		local out = {}
		for k = 1, 3 do
			local v = grip[k] + (balance[k] - grip[k]) * toBalance
			v += (panic[k] - v) * toPanic
			v += (fall[k] - v) * toFall
			out[k] = v * w
		end
		return CFrame.Angles(out[1], out[2], out[3])
	end
	if r6 then
		local flap = 0.6 * math.sin(t * 13)
		if name == "Right Shoulder" then
			return blend({ 0, 0, 0.8 }, { 0, 0, 1.4 }, { 0, 0, 1.4 + 0.7 * math.max(0, math.sin(t * 2.7)) }, { 0, 0, 2.4 + flap })
		elseif name == "Left Shoulder" then
			return blend({ 0, 0, -0.8 }, { 0, 0, -1.4 }, { 0, 0, -1.4 - 0.7 * math.max(0, -math.sin(t * 2.7)) }, { 0, 0, -2.4 - flap })
		end
		return nil
	end
	-- What keeps the thighs on the floor: sat up (a right angle) as the push off begins, laid back after.
	local lie = ease(t / Poses.FLUME_LIE)
	local hip = math.pi / 2 - Poses.FLUME_RECLINE * lie
	local grab = math.sin(t * 2.7) -- which hand is grabbing at the wall
	local scrabble = math.sin(t * 6.5)
	local wobble = 0.12 * math.sin(t * 5.3)
	if name == "RightShoulder" then
		return blend({ 0.25, 0, 0.75 }, { -0.15, 0, 1.25 + wobble },
			{ 0.4 + 1.3 * math.max(0, grab), 0, 1.25 - 0.5 * math.max(0, grab) },
			{ 1.5 * math.sin(t * 9), 0, 1.6 + 0.6 * math.sin(t * 13) })
	elseif name == "LeftShoulder" then
		return blend({ 0.25, 0, -0.75 }, { -0.15, 0, -1.25 - wobble },
			{ 0.4 + 1.3 * math.max(0, -grab), 0, -1.25 + 0.5 * math.max(0, -grab) },
			{ 1.5 * math.sin(t * 9 + math.pi), 0, -1.6 - 0.6 * math.sin(t * 13 + 2) })
	elseif name == "RightElbow" then
		return blend({ 0.6, 0, 0 }, { 0.25, 0, 0 }, { 0.3 + 0.7 * math.max(0, grab), 0, 0 }, { 0.6 + 0.4 * math.sin(t * 15), 0, 0 })
	elseif name == "LeftElbow" then
		return blend({ 0.6, 0, 0 }, { 0.25, 0, 0 }, { 0.3 + 0.7 * math.max(0, -grab), 0, 0 },
			{ 0.6 + 0.4 * math.sin(t * 15 + 1.6), 0, 0 })
	elseif name == "Neck" then
		return blend({ -0.3, 0, 0 }, { -0.5, 0.2 * math.sin(t * 1.4), 0 },
			{ -0.5 + 0.25 * math.sin(t * 4), 0.5 * math.sin(t * 3.1), 0 }, { -0.6, 0.4 * math.sin(t * 6), 0 })
	elseif name == "Waist" then
		return blend({ -0.15, 0, 0 }, { -0.25, 0, 0.08 * math.sin(t * 1.9) },
			{ -0.25 + 0.1 * math.sin(t * 5), 0, 0.15 * math.sin(t * 1.9) }, { -0.1 + 0.15 * math.sin(t * 6), 0.2 * math.sin(t * 4.3), 0 })
	elseif name == "RightHip" then
		return blend({ hip, 0, 0.05 }, { hip, 0, 0.05 }, { hip + 0.2 * scrabble, 0, 0.12 },
			{ hip + 0.7 * math.sin(t * 10), 0, 0.2 })
	elseif name == "LeftHip" then
		return blend({ hip, 0, -0.05 }, { hip, 0, -0.05 }, { hip - 0.2 * scrabble, 0, -0.12 },
			{ hip + 0.7 * math.sin(t * 10 + math.pi), 0, -0.2 })
	elseif name == "RightKnee" then
		return blend({ -0.2, 0, 0 }, { -0.15, 0, 0 }, { -(0.25 + 0.45 * math.max(0, scrabble)), 0, 0 },
			{ -(0.4 + 0.5 * math.abs(math.sin(t * 10))), 0, 0 })
	elseif name == "LeftKnee" then
		return blend({ -0.2, 0, 0 }, { -0.15, 0, 0 }, { -(0.25 + 0.45 * math.max(0, -scrabble)), 0, 0 },
			{ -(0.4 + 0.5 * math.abs(math.sin(t * 10 + 1.2))), 0, 0 })
	end
	return nil
end

-- THE KEY: the right hand out at chest height, holding something small into a lock, head bowed to
-- look at it. `t` is unused; the reach is all in `w`.
function Poses.key(name: string, t: number, w: number, r6: boolean): CFrame?
	if r6 then
		if name == "Right Shoulder" then
			return CFrame.Angles(0, 0, 1.5 * w)
		end
		return nil
	end
	if name == "RightShoulder" then
		return CFrame.Angles(1.45 * w, 0, -0.2 * w)
	elseif name == "RightElbow" then
		return CFrame.Angles(0.35 * w, 0, 0)
	elseif name == "RightWrist" then
		-- The turn of the key, a quarter round and back.
		return CFrame.Angles(0, 0, -1.2 * math.clamp(t - 1, 0, 1) * w)
	elseif name == "Neck" then
		return CFrame.Angles(-0.3 * w, 0, 0)
	end
	return nil
end

-- THE WHEEL: both hands on a big iron handwheel, turning it hand over hand, leaning into it.
function Poses.wheel(name: string, t: number, w: number, r6: boolean): CFrame?
	local a = t * 2.4
	if r6 then
		if name == "Right Shoulder" then
			return CFrame.Angles(0, 0, (1.6 + 0.3 * math.sin(a)) * w)
		elseif name == "Left Shoulder" then
			return CFrame.Angles(0, 0, -(1.6 - 0.3 * math.sin(a)) * w)
		end
		return nil
	end
	if name == "RightShoulder" then
		return CFrame.Angles((1.35 + 0.3 * math.sin(a)) * w, 0, 0.3 * math.cos(a) * w)
	elseif name == "LeftShoulder" then
		return CFrame.Angles((1.35 - 0.3 * math.sin(a)) * w, 0, 0.3 * math.cos(a) * w)
	elseif name == "RightElbow" or name == "LeftElbow" then
		return CFrame.Angles(0.55 * w, 0, 0)
	elseif name == "Waist" then
		return CFrame.Angles(0.2 * w, 0.18 * math.sin(a) * w, 0)
	elseif name == "RightKnee" or name == "LeftKnee" then
		return CFrame.Angles(-0.25 * w, 0, 0)
	elseif name == "Neck" then
		return CFrame.Angles(-0.1 * w, 0, 0)
	end
	return nil
end

-- CLIMBING OUT: hands up a ladder one over the other, hauling out of the water.
function Poses.climb(name: string, t: number, w: number, r6: boolean): CFrame?
	local a = t * 5
	if r6 then
		if name == "Right Shoulder" then
			return CFrame.Angles(0, 0, (2.5 + 0.4 * math.sin(a)) * w)
		elseif name == "Left Shoulder" then
			return CFrame.Angles(0, 0, -(2.5 - 0.4 * math.sin(a)) * w)
		end
		return nil
	end
	if name == "RightShoulder" then
		return CFrame.Angles((2.4 + 0.45 * math.sin(a)) * w, 0, 0)
	elseif name == "LeftShoulder" then
		return CFrame.Angles((2.4 - 0.45 * math.sin(a)) * w, 0, 0)
	elseif name == "RightElbow" then
		return CFrame.Angles((0.4 + 0.4 * math.max(0, math.sin(a))) * w, 0, 0)
	elseif name == "LeftElbow" then
		return CFrame.Angles((0.4 + 0.4 * math.max(0, -math.sin(a))) * w, 0, 0)
	elseif name == "RightHip" then
		return CFrame.Angles(0.6 * math.max(0, -math.sin(a)) * w, 0, 0)
	elseif name == "LeftHip" then
		return CFrame.Angles(0.6 * math.max(0, math.sin(a)) * w, 0, 0)
	elseif name == "RightKnee" then
		return CFrame.Angles(-0.8 * math.max(0, -math.sin(a)) * w, 0, 0)
	elseif name == "LeftKnee" then
		return CFrame.Angles(-0.8 * math.max(0, math.sin(a)) * w, 0, 0)
	end
	return nil
end

-- ===== FINDING THINGS (StoryClient: a secret's scene, with you in it) =====

-- THE PRY BAR AT WORK: both hands low on the bar, leaning in, and three hard tugs a little over half a second
-- apart, the body hauling back on each; then held, straining, until it gives.
function Poses.pry(name: string, t: number, w: number, r6: boolean): CFrame?
	local p = (t % 0.55) / 0.55
	local tug = if t < 1.65 then math.sin(math.pi * p) ^ 2 else 0.6 + 0.08 * math.sin(t * 30)
	if r6 then
		if name == "Right Shoulder" then
			return CFrame.Angles(0, 0, (1.3 - 0.3 * tug) * w)
		elseif name == "Left Shoulder" then
			return CFrame.Angles(0, 0, -(1.2 - 0.3 * tug) * w)
		elseif name == "Neck" then
			return CFrame.Angles(0.2 * w, 0, 0)
		end
		return nil
	end
	if name == "RightShoulder" then
		return CFrame.Angles((1.05 - 0.3 * tug) * w, 0, -0.15 * w)
	elseif name == "LeftShoulder" then
		return CFrame.Angles((0.95 - 0.3 * tug) * w, 0, 0.2 * w)
	elseif name == "RightElbow" or name == "LeftElbow" then
		return CFrame.Angles((0.45 + 0.4 * tug) * w, 0, 0)
	elseif name == "Waist" then
		return CFrame.Angles((-0.38 + 0.32 * tug) * w, 0.1 * tug * w, 0)
	elseif name == "Neck" then
		return CFrame.Angles((-0.25 + 0.12 * tug) * w, 0, 0)
	elseif name == "RightKnee" or name == "LeftKnee" then
		return CFrame.Angles(-0.3 * w, 0, 0)
	end
	return nil
end

-- ===== THE BAR AS A LEVER (the two-hundred-and-seventh pass, from your note of 2026-11-10: "improve the animation
-- drastically for the level 2 chest that should be prised up with a bar") =====
--
-- The tin box in the Sky Pools' first pool was opened by the same three tugs as a locker, standing, the lid not moving
-- until it flew open. A lid is levered: down on your haunches in front of it, the bar's claw set under the lid's front
-- edge, and your weight borne DOWN on the handle, so the lid strains up. Twice it lifts and drops back, a little
-- further the second time; the third heave is long, held and shaking, and then the clasp goes. LEVER is when each thing
-- happens, seconds in (Interactables moves the lid by it, StoryClient the bar and the camera): the bar set, the three
-- heaves beginning, and the lid giving.
Poses.LEVER = { set = 0.6, heaves = { 1.0, 1.75, 2.6 }, gives = 3.4 }

-- How hard the bar is being borne down on, `t` seconds in: 0 at rest, 1 the whole of your weight. The first two a quick
-- shove and a slower let-up; the last built over a third of a second and held, shaking, until the lid gives.
function Poses.leverPull(t: number): number
	local timing = Poses.LEVER
	local last = timing.heaves[3]
	if t >= last then
		local u = math.clamp((t - last) / 0.35, 0, 1)
		local build = u * u * (3 - 2 * u)
		local held = math.clamp((t - last - 0.35) / math.max(0.05, timing.gives - last - 0.35), 0, 1)
		return build * (0.85 + 0.15 * held) + (if u >= 1 and t < timing.gives then 0.03 * math.sin(t * 38) else 0)
	end
	for index = 2, 1, -1 do
		local at = timing.heaves[index]
		if t >= at then
			local since = t - at
			local strength = if index == 1 then 0.55 else 0.75
			if since < 0.16 then
				local u = since / 0.16
				return strength * (1 - (1 - u) * (1 - u))
			end
			local u = math.clamp((since - 0.16) / 0.42, 0, 1)
			return strength * (1 - u * u * (3 - 2 * u))
		end
	end
	return 0
end

-- DOWN ON YOUR HAUNCHES, bearing on the bar: the hips forward and the knees right back under you (the Root let down as
-- far as that takes the body, so the feet stay where they are), the head down to the lid, and both hands brought
-- together on the bar's handle out in front of your chest. Each heave drops you further and drives the hands down and
-- in toward your belly, the elbows folding as your weight comes over them.
--
-- THE ARMS ARE FITTED, not guessed (measured on a wide R15 in Studio, 2026-11-11): at rest the hands a third of a stud
-- apart, 1.5 studs ahead of the root and level with it; at the whole of your weight a tenth apart, 0.85 ahead and 0.7
-- under it. Those two points are where a 2.8 stud bar's handle is with its claw under the lid of a box 3.75 studs
-- ahead (StoryClient's LEVER.stand): at about 48 degrees with the lid shut, and about 15 with its front edge half a
-- stud up. The first guess had the hands a stud and a quarter either side of the bar and a stud from its claw.
function Poses.lever(name: string, t: number, w: number, r6: boolean): CFrame?
	local pull = Poses.leverPull(t)
	local into = math.clamp(t / Poses.LEVER.set, 0, 1)
	local down = into * into * (3 - 2 * into) * w
	if r6 then
		if name == "Right Shoulder" then
			return CFrame.Angles(0, 0, (1.15 - 0.45 * pull) * down)
		elseif name == "Left Shoulder" then
			return CFrame.Angles(0, 0, -(1.15 - 0.45 * pull) * down)
		elseif name == "Neck" then
			return CFrame.Angles(0.25 * down, 0, 0)
		end
		return nil
	end
	local squat = (0.95 + 0.18 * pull) * down
	if name == "Root" then
		return CFrame.new(0, -(0.62 + 0.23 * pull) * down, 0)
	elseif name == "RightHip" or name == "LeftHip" then
		return CFrame.Angles(squat, 0, 0)
	elseif name == "RightKnee" or name == "LeftKnee" then
		return CFrame.Angles(-2 * squat, 0, 0)
	elseif name == "RightAnkle" or name == "LeftAnkle" then
		return CFrame.Angles(squat * 0.9, 0, 0)
	elseif name == "Neck" then
		return CFrame.Angles(-(0.3 + 0.1 * pull) * down, 0, 0)
	elseif name == "RightShoulder" then
		return CFrame.Angles((1.2 - 0.9 * pull) * down, 0.6 * pull * down, -(0.9 + 0.4 * pull) * down)
	elseif name == "LeftShoulder" then
		return CFrame.Angles((1.2 - 0.9 * pull) * down, -0.6 * pull * down, (0.9 + 0.4 * pull) * down)
	elseif name == "RightElbow" or name == "LeftElbow" then
		return CFrame.Angles((0.3 + 1.0 * pull) * down, 0, 0)
	end
	return nil
end

-- THE BAR SWUNG INTO A WALL (the hundred-and-twenty-ninth pass, from your test: "I should actually hit the bricks"): three
-- blows half a second apart, each drawn back over the right shoulder and brought down hard into the wall, the body
-- turning into it, the left hand out to brace; the last held, leaning on it, as the bricks go. STRIKES is when each lands
-- (StoryClient draws the bar from the hand with strikeBack, and hits the wall on these).
Poses.STRIKES = { 0.45, 0.95, 1.45 }

-- How far the bar is drawn back `t` seconds in: 0 at the wall, 1 right back over the shoulder. Drawn back over a third
-- of a second, held a moment, and brought in fast (quickening into the wall); held on the wall a moment after each.
function Poses.strikeBack(t: number): number
	local previous = -0.4
	for _, at in ipairs(Poses.STRIKES) do
		if t < at + 0.12 then
			if t >= at then
				return 0
			end
			local from = math.max(previous + 0.12, 0.05)
			if t < at - 0.1 then
				local u = math.clamp((t - from) / math.max(0.05, at - 0.1 - from), 0, 1)
				return u * u * (3 - 2 * u)
			end
			local u = (t - (at - 0.1)) / 0.1
			return 1 - u * u
		end
		previous = at
	end
	return 0
end

function Poses.strike(name: string, t: number, w: number, r6: boolean): CFrame?
	local back = Poses.strikeBack(t)
	if r6 then
		if name == "Right Shoulder" then
			return CFrame.Angles(0, 0, (1.4 + 1.4 * back) * w)
		elseif name == "Left Shoulder" then
			return CFrame.Angles(0, 0, -0.9 * w)
		elseif name == "Neck" then
			return CFrame.Angles(0.1 * w, 0, 0)
		end
		return nil
	end
	if name == "RightShoulder" then
		return CFrame.Angles((1.35 + 1.5 * back) * w, 0, -0.1 * w)
	elseif name == "RightElbow" then
		return CFrame.Angles((0.15 + 1.1 * back) * w, 0, 0)
	elseif name == "LeftShoulder" then
		return CFrame.Angles(0.75 * w, 0, 0.25 * w)
	elseif name == "LeftElbow" then
		return CFrame.Angles(0.6 * w, 0, 0)
	elseif name == "Waist" then
		return CFrame.Angles((-0.15 + 0.23 * back) * w, 0.22 * back * w, 0)
	elseif name == "Neck" then
		return CFrame.Angles(-0.1 * w, -0.1 * back * w, 0)
	elseif name == "RightKnee" or name == "LeftKnee" then
		return CFrame.Angles(-0.25 * w, 0, 0)
	end
	return nil
end

-- THE DETECTIVE: one hand at the chin, the other arm across under it, the head tilting slowly one way and
-- then the other, leaning in a little: working out what this is and who left it.
function Poses.ponder(name: string, t: number, w: number, r6: boolean): CFrame?
	if r6 then
		if name == "Right Shoulder" then
			return CFrame.Angles(0, 0, 2.3 * w)
		elseif name == "Left Shoulder" then
			return CFrame.Angles(0, 0, -0.9 * w)
		elseif name == "Neck" then
			return CFrame.Angles(0.12 * w, 0, 0.25 * math.sin(t * 1.2) * w)
		end
		return nil
	end
	if name == "RightShoulder" then
		return CFrame.Angles(1.5 * w, 0, -0.25 * w)
	elseif name == "RightElbow" then
		return CFrame.Angles(2.05 * w, 0, 0)
	elseif name == "LeftShoulder" then
		return CFrame.Angles(0.55 * w, 0, 0.35 * w)
	elseif name == "LeftElbow" then
		return CFrame.Angles(1.5 * w, 0, 0)
	elseif name == "Neck" then
		return CFrame.Angles(-0.15 * w, 0.3 * math.sin(t * 0.9) * w, 0.22 * math.sin(t * 1.3) * w)
	elseif name == "Waist" then
		return CFrame.Angles(-0.12 * w, 0.08 * math.sin(t * 0.7) * w, 0)
	end
	return nil
end

-- STARTLED: a jolt back, the arms coming up and out, the head back. `w` dies away as it passes.
function Poses.startle(name: string, t: number, w: number, r6: boolean): CFrame?
	if r6 then
		if name == "Right Shoulder" then
			return CFrame.Angles(0, 0, 1.4 * w)
		elseif name == "Left Shoulder" then
			return CFrame.Angles(0, 0, -1.4 * w)
		elseif name == "Neck" then
			return CFrame.Angles(-0.3 * w, 0, 0)
		end
		return nil
	end
	if name == "RightShoulder" then
		return CFrame.Angles(0.6 * w, 0, 1.0 * w)
	elseif name == "LeftShoulder" then
		return CFrame.Angles(0.6 * w, 0, -1.0 * w)
	elseif name == "RightElbow" or name == "LeftElbow" then
		return CFrame.Angles(0.9 * w, 0, 0)
	elseif name == "Waist" then
		return CFrame.Angles(0.3 * w, 0, 0)
	elseif name == "Neck" then
		return CFrame.Angles(0.3 * w, 0, 0)
	elseif name == "RightKnee" or name == "LeftKnee" then
		return CFrame.Angles(-0.2 * w, 0, 0)
	end
	return nil
end

-- PEERING DOWN over an edge: bent at the waist, hands braced on the knees, the head down to see.
function Poses.peer(name: string, t: number, w: number, r6: boolean): CFrame?
	if r6 then
		if name == "Neck" then
			return CFrame.Angles(0.5 * w, 0, 0)
		end
		return nil
	end
	if name == "Waist" then
		return CFrame.Angles(-0.55 * w, 0, 0)
	elseif name == "Neck" then
		return CFrame.Angles((-0.45 + 0.04 * math.sin(t * 2)) * w, 0, 0)
	elseif name == "RightShoulder" then
		return CFrame.Angles(0.7 * w, 0, -0.1 * w)
	elseif name == "LeftShoulder" then
		return CFrame.Angles(0.7 * w, 0, 0.1 * w)
	elseif name == "RightElbow" or name == "LeftElbow" then
		return CFrame.Angles(0.3 * w, 0, 0)
	elseif name == "RightKnee" or name == "LeftKnee" then
		return CFrame.Angles(-0.35 * w, 0, 0)
	elseif name == "RightHip" or name == "LeftHip" then
		return CFrame.Angles(0.3 * w, 0, 0)
	end
	return nil
end

-- ===== TELLING IT: the townsfolk's gestures =====
--
-- Every line anyone in Harrow Bay says comes with one of these (Townsfolk picks it from what they are saying,
-- StoryClient plays it on every client, on top of how they stand and the head turned to you). `hands` is which
-- of theirs is free: "both", "right", "left" or "none" (a scoop, a bucket, a lantern, a rod), and the one that
-- gestures is the free one; a hand that is holding something is left alone. Each is in R15's axes for the RIGHT
-- arm (the left is mirrored). And under all of them the small nods of somebody talking.
--   greet     a wave hello, the head tilted
--   explain   both hands out in front, palms up, beating time with what they say
--   point     an arm out, pointing, the head and the body turned after it: the gates, the key, the drain
--   shrug     both arms out, palms up, a lift and a tilt of the head: who knows
--   worry     hands clasped at the chest, wringing, the head down: the water, the tide
--   remember  a hand at the chin, looking up and away: years ago
--   warn      a hand up, the finger wagging, leaning in: mind the honey
--   lean      bent in close, a hand by the mouth: between you and me
--   sad       the head down and the shoulders after it, a sigh: my dad
Poses.GESTURES = { "greet", "explain", "point", "shrug", "worry", "remember", "warn", "lean", "sad" }

type Arm = { shoulder: { number }, elbow: { number } }
type Gesture = { main: Arm?, other: Arm?, neck: { number }, waist: { number } }

local function gestureAt(gesture: string, t: number): Gesture
	local function rise(seconds: number): number
		local x = math.clamp(t / seconds, 0, 1)
		return x * x * (3 - 2 * x)
	end
	if gesture == "greet" then
		local up = rise(0.4) * (1 - math.clamp((t - 1.9) / 0.5, 0, 1))
		return { main = { shoulder = { 0.2 * up, 0.38 * math.sin(t * 9) * up, 2.5 * up }, elbow = { 1.1 * up } },
			neck = { -0.05, 0, 0.12 }, waist = { 0, 0, 0 } }
	elseif gesture == "point" then
		local up = rise(0.5)
		return { main = { shoulder = { 1.5 * up, 0, 0.35 * up }, elbow = { 0.08 } }, other = { shoulder = { 0.1, 0, 0.05 }, elbow = { 0.2 } },
			neck = { -0.08 * up, 0.25 * up, 0 }, waist = { 0, 0.18 * up, 0 } }
	elseif gesture == "shrug" then
		local lift = math.clamp(math.sin(math.clamp((t - 0.25) / 0.8, 0, 1) * math.pi), 0, 1)
		local arm = { shoulder = { 0.35, 0, 0.5 + 0.15 * lift }, elbow = { 1.25 } }
		return { main = arm, other = arm, neck = { 0.05, 0, 0.18 * lift + 0.06 }, waist = { 0.04 * lift, 0, 0 } }
	elseif gesture == "worry" then
		return { main = { shoulder = { 0.95, 0, -0.32 }, elbow = { 1.75 + 0.1 * math.sin(t * 3) } },
			other = { shoulder = { 0.95, 0, -0.32 }, elbow = { 1.75 - 0.1 * math.sin(t * 3) } },
			neck = { -0.28 + 0.05 * math.sin(t * 1.2), 0.1 * math.sin(t * 0.8), 0 }, waist = { -0.06, 0, 0.05 * math.sin(t * 1.3) } }
	elseif gesture == "remember" then
		local up = rise(0.6)
		return { main = { shoulder = { 1.05 * up, 0, -0.42 * up }, elbow = { 2.25 * up } },
			other = { shoulder = { 0.6 * up, 0, -0.35 * up }, elbow = { 1.5 * up } },
			neck = { 0.18 * up, 0.28 * up, 0.08 * up }, waist = { 0.03, 0, 0 } }
	elseif gesture == "warn" then
		local up = rise(0.35)
		return { main = { shoulder = { 1.25 * up, 0, 0.15 * up }, elbow = { (1.4 + 0.25 * math.sin(t * 10)) * up } },
			neck = { -0.1, 0, 0 }, waist = { -0.08 * up, 0, 0 } }
	elseif gesture == "lean" then
		local up = rise(0.5)
		return { main = { shoulder = { 1.0 * up, 0, -0.2 * up }, elbow = { 2.0 * up } },
			neck = { -0.05, 0.2 * up, 0.1 * up }, waist = { -0.28 * up, 0.12 * up, 0 } }
	elseif gesture == "sad" then
		local down = rise(0.9)
		local arm = { shoulder = { 0.12 * down, 0, -0.04 * down }, elbow = { 0.25 * down } }
		return { main = arm, other = arm, neck = { -0.42 * down, 0, 0 }, waist = { (-0.14 + 0.04 * math.sin(t * 0.9)) * down, 0, 0 } }
	end
	-- EXPLAIN, and anything not known: both hands out in front, beating time, never quite together.
	return { main = { shoulder = { 0.55 + 0.15 * math.sin(t * 4.1), 0, 0.25 + 0.1 * math.sin(t * 2.3) }, elbow = { 1.15 + 0.2 * math.sin(t * 5.2) } },
		other = { shoulder = { 0.45 + 0.12 * math.sin(t * 3.7 + 1), 0, 0.2 }, elbow = { 1.0 + 0.18 * math.sin(t * 4.6 + 2) } },
		neck = { 0, 0.12 * math.sin(t * 1.3), 0 }, waist = { 0, 0.06 * math.sin(t * 1.1), 0 } }
end

-- One joint's turn for `gesture`, `t` seconds into it, at `w` of its full swing, with `hands` free.
function Poses.tell(gesture: string, name: string, t: number, w: number, hands: string, r6: boolean): CFrame?
	local g = gestureAt(gesture, t)
	-- Which arm gestures: the free one, the right if both are. The other moves only if it is free too.
	local mainSide = if hands == "left" then "Left" elseif hands == "none" then nil else "Right"
	local otherSide = if hands == "both" then "Left" else nil
	if r6 then
		if mainSide and name == mainSide .. " Shoulder" and g.main then
			local z = g.main.shoulder[3] + 0.5 * g.main.shoulder[1]
			return CFrame.Angles(0, 0, (if mainSide == "Left" then -z else z) * w)
		elseif name == "Neck" then
			return CFrame.Angles(0, 0, g.neck[2] * w)
		end
		return nil
	end
	local nod = 0.06 * math.sin(t * 6.3) * math.sin(t * 1.7 + 0.4)
	if name == "Neck" then
		return CFrame.Angles((g.neck[1] + nod) * w, g.neck[2] * w, g.neck[3] * w)
	elseif name == "Waist" then
		return CFrame.Angles(g.waist[1] * w, g.waist[2] * w, g.waist[3] * w)
	end
	for _, pick in ipairs({ { mainSide, g.main }, { otherSide, g.other } }) do
		local side, arm = pick[1] :: string?, pick[2] :: Arm?
		if side and arm then
			-- The left arm is the right's mirror: its turn about Y and Z the other way.
			local flip = if side == "Left" then -1 else 1
			if name == side .. "Shoulder" then
				return CFrame.Angles(arm.shoulder[1] * w, arm.shoulder[2] * flip * w, arm.shoulder[3] * flip * w)
			elseif name == side .. "Elbow" then
				return CFrame.Angles(arm.elbow[1] * w, 0, 0)
			end
		end
	end
	return nil
end

-- ===== THE WAVE (yours, back to Marsh at the end of the true ending; the shop's emotes are keyed, below) =====

-- WAVE: the right arm up and waving from side to side, head turned a little towards whoever it is for.
function Poses.wave(name: string, t: number, w: number, r6: boolean): CFrame?
	local swing = 0.3 * math.sin(t * 8)
	if r6 then
		if name == "Right Shoulder" then
			return CFrame.Angles(0, 0, (2.7 + swing) * w)
		end
		return nil
	end
	if name == "RightShoulder" then
		return CFrame.Angles(0, 0, (2.55 + swing) * w)
	elseif name == "RightElbow" then
		return CFrame.Angles(0.35 * w, 0, 0)
	elseif name == "Neck" then
		return CFrame.Angles(0.05 * w, 0.18 * w, 0)
	end
	return nil
end

-- ===== KEYED POSES (the hundred-and-fifty-seventh and fifty-eighth passes) =====
--
-- From your notes of 2026-10-31: "make more variations to the poses the player does by itself when standing afk, improve
-- the quality of the existing ones and make sure they are very high quality overall, some might be like an aura-farming
-- emote; and improve the existing emotes that can be bought, and add even more of them".
--
-- The poses above are a sine or two on a few joints. These are KEYS through time: each joint's turns at the moments that
-- matter (where a move starts, the far end of a swing, a hold), and a smooth curve through them that eases into and out
-- of every turn back, the way a body slows at the end of a reach, with the whole body in it (the weight in the hips and
-- knees, the shoulders after the arms, the head after the eyes). Arms are written as where the hand and the elbow go and
-- solved onto R15 (blender/gen_poses.py, which writes the table below), so a hand on a hip is on it and not in it.
--
-- Every keyed pose starts and ends at rest by its own first and last keys, so it is played as it is and never scaled by
-- Poses.weight (a spin scaled down on its way out would turn back the way it came). A LOOP is played from its first moment
-- to its last over and over while the pose lasts, and the keys after it are the way out, played once at the end.
--
-- On an R6 body, which has no elbows, waist or knees, the R15 turns are read as near as R6 has: the arms raised by how far
-- they are lifted forward or out, the hips by how far forward, the head turned and tipped, the root's turn.
export type Keyed = { seconds: number, loop: { number }?, keys: { [string]: { { number } } } }

-- One value of a joint's curve at `t` (k: 2, 3, 4 its turns about X, Y and Z; 5, 6, 7 the root's move).
local function curve(track: { { number } }, t: number, k: number): number
	local n = #track
	if t <= track[1][1] then
		return track[1][k] or 0
	end
	if t >= track[n][1] then
		return track[n][k] or 0
	end
	local i = 1
	while i < n - 1 and track[i + 1][1] <= t do
		i += 1
	end
	local a, b = track[i], track[i + 1]
	local d = b[1] - a[1]
	local u = (t - a[1]) / d
	-- Still where a value turns back, and at either end; elsewhere the slope through the keys either side.
	local function slope(j: number): number
		if j <= 1 or j >= n then
			return 0
		end
		local before, here, after = track[j - 1][k] or 0, track[j][k] or 0, track[j + 1][k] or 0
		if (here - before) * (after - here) <= 0 then
			return 0
		end
		return (after - before) / (track[j + 1][1] - track[j - 1][1])
	end
	local ma, mb = slope(i) * d, slope(i + 1) * d
	local u2, u3 = u * u, u * u * u
	return (2 * u3 - 3 * u2 + 1) * (a[k] or 0) + (u3 - 2 * u2 + u) * ma + (-2 * u3 + 3 * u2) * (b[k] or 0) + (u3 - u2) * mb
end

-- Where in its keys a pose is, `t` seconds in: round its loop while it lasts, then out.
local function keyTime(spec: Keyed, t: number): number
	local loop = spec.loop
	if not loop or t <= loop[2] then
		return t
	end
	local last = 0
	for _, track in pairs(spec.keys) do
		last = math.max(last, track[#track][1])
	end
	local tail = spec.seconds - t
	if tail <= last - loop[2] then
		return last - tail
	end
	return loop[1] + (t - loop[2]) % (loop[2] - loop[1])
end

local function turnOf(spec: Keyed, joint: string, t: number): CFrame?
	local track = spec.keys[joint]
	if not track then
		return nil
	end
	local angles = CFrame.Angles(curve(track, t, 2), curve(track, t, 3), curve(track, t, 4))
	if joint == "Root" then
		return CFrame.new(curve(track, t, 5), curve(track, t, 6), curve(track, t, 7)) * angles
	end
	return angles
end

-- R6's few joints, from the R15 turns of the same pose.
local function r6Turn(spec: Keyed, name: string, t: number): CFrame?
	local function value(joint: string, k: number): number
		local track = spec.keys[joint]
		return if track then curve(track, t, k) else 0
	end
	if name == "Right Shoulder" and spec.keys.RightShoulder then
		return CFrame.Angles(0, 0, value("RightShoulder", 2) + 0.85 * value("RightShoulder", 4))
	elseif name == "Left Shoulder" and spec.keys.LeftShoulder then
		return CFrame.Angles(0, 0, -(value("LeftShoulder", 2) - 0.85 * value("LeftShoulder", 4)))
	elseif name == "Right Hip" and spec.keys.RightHip then
		return CFrame.Angles(0, 0, value("RightHip", 2))
	elseif name == "Left Hip" and spec.keys.LeftHip then
		return CFrame.Angles(0, 0, -value("LeftHip", 2))
	elseif name == "Neck" and spec.keys.Neck then
		return CFrame.Angles(-value("Neck", 2), 0, 0.9 * value("Neck", 3))
	elseif name == "RootJoint" and spec.keys.Root then
		return CFrame.Angles(0, 0, value("Root", 3))
	end
	return nil
end

-- A keyed pose's turn for one joint, `t` seconds in.
local function play(spec: Keyed, name: string, t: number, r6: boolean): CFrame?
	local at = keyTime(spec, t)
	if r6 then
		return r6Turn(spec, name, at)
	end
	return turnOf(spec, name, at)
end

-- KEYED BEGIN (written by blender/gen_poses.py: edit the poses there, not here)
-- spec ae067f148039
local KEYED: { [string]: Keyed } = {
	idleLook = { seconds = 4.8, keys = {
		Waist = { { 0, 0, 0, 0 }, { 0.8, 0, 0.2, 0 }, { 1.7, 0, 0.22, 0 }, { 2.35, 0, 0, 0 }, { 2.9, 0, -0.18, 0 }, { 3.9, 0, -0.2, 0 }, { 4.7, 0, 0, 0 } },
		Neck = { { 0, 0, 0, 0 }, { 0.55, 0.05, 0.7, -0.03 }, { 1.55, 0.07, 0.76, -0.04 }, { 2.15, -0.05, 0.02, 0 }, { 2.65, 0.04, -0.68, 0.04 }, { 3.7, 0.06, -0.72, 0.05 }, { 4.5, 0, 0, 0 } },
		RightShoulder = { { 0, 0, 0, 0 }, { 0.9, 0.06, 0, 0.03 }, { 2.3, 0, 0, 0 }, { 3, -0.05, 0, 0.02 }, { 4.7, 0, 0, 0 } },
		LeftShoulder = { { 0, 0, 0, 0 }, { 0.9, -0.05, 0, -0.02 }, { 2.3, 0, 0, 0 }, { 3, 0.06, 0, -0.03 }, { 4.7, 0, 0, 0 } },
	} },
	idleShift = { seconds = 4.2, keys = {
		Root = { { 0, 0, 0, 0 }, { 0.7, 0, 0.05, 0.05 }, { 3.4, 0, 0.05, 0.05 }, { 4.2, 0, 0, 0 } },
		Waist = { { 0, 0, 0, 0 }, { 0.8, 0, -0.03, -0.07 }, { 3.3, 0, -0.03, -0.07 }, { 4.2, 0, 0, 0 } },
		Neck = { { 0, 0, 0, 0 }, { 0.9, -0.04, 0.08, 0.1 }, { 3.2, -0.04, 0.08, 0.1 }, { 4.2, 0, 0, 0 } },
		RightShoulder = { { 0, 0, 0, 0 }, { 1.3, 0, 0, 0.04 }, { 1.8, -0.24, 0, 0.1 }, { 2.3, 0.06, 0, 0.04 }, { 2.8, 0, 0, 0.03 }, { 4.2, 0, 0, 0 } },
		LeftShoulder = { { 0, 0, 0, 0 }, { 1.3, 0, 0, -0.04 }, { 1.8, -0.24, 0, -0.1 }, { 2.3, 0.06, 0, -0.04 }, { 2.8, 0, 0, -0.03 }, { 4.2, 0, 0, 0 } },
		RightHip = { { 0, 0, 0, 0 }, { 0.7, 0.13, -0.1, 0.02 }, { 3.4, 0.13, -0.1, 0.02 }, { 4.2, 0, 0, 0 } },
		RightKnee = { { 0, 0, 0, 0 }, { 0.7, -0.28, 0, 0 }, { 3.4, -0.28, 0, 0 }, { 4.2, 0, 0, 0 } },
		RightAnkle = { { 0, 0, 0, 0 }, { 0.7, 0.14, 0, 0 }, { 3.4, 0.14, 0, 0 }, { 4.2, 0, 0, 0 } },
		LeftHip = { { 0, 0, 0, 0 }, { 0.7, 0, 0, -0.04 }, { 3.4, 0, 0, -0.04 }, { 4.2, 0, 0, 0 } },
	} },
	idlePonder = { seconds = 4.6, keys = {
		Waist = { { 0, 0, 0, 0 }, { 0.8, -0.08, 0.05, 0 }, { 3.7, -0.08, 0.05, 0 }, { 4.5, 0, 0, 0 } },
		Neck = { { 0, 0, 0, 0 }, { 0.8, -0.12, 0.1, 0.12 }, { 2, -0.08, 0.24, -0.06 }, { 3.3, -0.12, 0.05, 0.14 }, { 4.4, 0, 0, 0 } },
		RightShoulder = { { 0, 0, 0, 0 }, { 0.65, 1.157, 0.818, -1.143 }, { 3.9, 1.157, 0.818, -1.143 }, { 4.6, 0, 0, 0 } },
		RightElbow = { { 0, 0, 0, 0 }, { 0.65, 1.752, 0, 0 }, { 3.9, 1.752, 0, 0 }, { 4.6, 0, 0, 0 } },
		RightWrist = { { 0, 0, 0, 0 }, { 0.7, 0.2, 0, 0 }, { 1.15, 0.42, 0, 0 }, { 1.45, 0.16, 0, 0 }, { 1.75, 0.42, 0, 0 }, { 2.05, 0.16, 0, 0 }, { 2.4, 0.36, 0, 0 }, { 3.9, 0.2, 0, 0 }, { 4.6, 0, 0, 0 } },
		LeftShoulder = { { 0, 0, 0, 0 }, { 0.75, 1.181, -0.844, 1.113 }, { 3.8, 1.181, -0.844, 1.113 }, { 4.6, 0, 0, 0 } },
		LeftElbow = { { 0, 0, 0, 0 }, { 0.75, 0.8, 0, 0 }, { 3.8, 0.8, 0, 0 }, { 4.6, 0, 0, 0 } },
		LeftWrist = { { 0, 0, 0, 0 }, { 0.75, 0, 0, 0 }, { 3.8, 0, 0, 0 }, { 4.6, 0, 0, 0 } },
	} },
	idleYawn = { seconds = 4.6, keys = {
		Waist = { { 0, 0, 0, 0 }, { 1, 0.14, 0, 0 }, { 1.8, 0.1, 0, 0.15 }, { 2.55, 0.1, 0, -0.13 }, { 3.3, 0, 0, 0 }, { 4.6, 0, 0, 0 } },
		Neck = { { 0, 0, 0, 0 }, { 1, 0.34, 0, 0 }, { 1.8, 0.26, 0, 0.08 }, { 2.55, 0.26, 0, -0.08 }, { 3.3, -0.06, 0, 0 }, { 4.6, 0, 0, 0 } },
		RightShoulder = { { 0, 0, 0, 0 }, { 0.95, 0.2, 0, 2.75 }, { 1.7, 0.2, 0, 2.86 }, { 2.7, 0.2, 0, 2.8 }, { 3.5, 0, 0, 0.4 }, { 4, -0.2, 0, 0.1 }, { 4.6, 0, 0, 0 } },
		RightElbow = { { 0, 0, 0, 0 }, { 0.95, 0.4, 0, 0 }, { 2.7, 0.3, 0, 0 }, { 3.5, 0.15, 0, 0 }, { 4.6, 0, 0, 0 } },
		LeftShoulder = { { 0, 0, 0, 0 }, { 0.95, 0.2, 0, -2.75 }, { 1.7, 0.2, 0, -2.86 }, { 2.7, 0.2, 0, -2.8 }, { 3.5, 0, 0, -0.4 }, { 4, -0.2, 0, -0.1 }, { 4.6, 0, 0, 0 } },
		LeftElbow = { { 0, 0, 0, 0 }, { 0.95, 0.4, 0, 0 }, { 2.7, 0.3, 0, 0 }, { 3.5, 0.15, 0, 0 }, { 4.6, 0, 0, 0 } },
	} },
	idleHand = { seconds = 3.8, keys = {
		Waist = { { 0, 0, 0, 0 }, { 0.7, -0.04, -0.06, 0 }, { 2.7, -0.04, -0.06, 0 }, { 3.6, 0, 0, 0 } },
		Neck = { { 0, 0, 0, 0 }, { 0.7, -0.28, -0.14, 0.06 }, { 2.6, -0.25, -0.1, 0.04 }, { 3.5, 0, 0, 0 } },
		RightShoulder = { { 0, 0, 0, 0 }, { 0.6, 0.716, 0.561, -0.596 }, { 1.6, 0.716, 0.561, -0.596 }, { 2, 0.752, 0.58, -0.613 }, { 2.15, 0.782, 0.596, -0.628 }, { 2.35, 0.746, 0.585, -0.611 }, { 2.8, 0.681, 0.589, -0.58 }, { 3.8, 0, 0, 0 } },
		RightElbow = { { 0, 0, 0, 0 }, { 0.6, 1.635, 0, 0 }, { 1.6, 1.635, 0, 0 }, { 2, 1.761, 0, 0 }, { 2.15, 1.631, 0, 0 }, { 2.35, 1.716, 0, 0 }, { 2.8, 1.67, 0, 0 }, { 3.8, 0, 0, 0 } },
		RightWrist = { { 0, 0, 0, 0 }, { 0.6, 0.1, 0.9, 0 }, { 1.6, 0.1, 0.9, 0 }, { 2, -0.3, 0.2, 0 }, { 2.15, 0.4, 0.2, 0 }, { 2.35, -0.1, 0.2, 0 }, { 2.8, 0, 0, 0 }, { 3.8, 0, 0, 0 } },
	} },
	idleTap = { seconds = 4.4, keys = {
		Waist = { { 0, 0, 0, 0 }, { 0.7, 0.04, 0, 0.03 }, { 2.3, 0.08, 0, 0.03 }, { 2.6, 0.02, 0, 0.03 }, { 3.9, 0.04, 0, 0.03 }, { 4.4, 0, 0, 0 } },
		Neck = { { 0, 0, 0, 0 }, { 0.7, 0.02, 0.1, 0.12 }, { 2.3, 0.08, 0.06, 0.1 }, { 2.55, -0.04, 0.06, 0.1 }, { 3.9, 0.02, 0.1, 0.12 }, { 4.4, 0, 0, 0 } },
		RightShoulder = { { 0, 0, 0, 0 }, { 0.55, -0.764, 0.611, 0.226 }, { 3.8, -0.764, 0.611, 0.226 }, { 4.4, 0, 0, 0 } },
		RightElbow = { { 0, 0, 0, 0 }, { 0.55, 1.18, 0, 0 }, { 3.8, 1.18, 0, 0 }, { 4.4, 0, 0, 0 } },
		RightWrist = { { 0, 0, 0, 0 }, { 0.55, 0, 0, 0 }, { 3.8, 0, 0, 0 }, { 4.4, 0, 0, 0 } },
		LeftShoulder = { { 0, 0, 0, 0 }, { 0.6, -0.764, -0.611, -0.226 }, { 3.8, -0.764, -0.611, -0.226 }, { 4.4, 0, 0, 0 } },
		LeftElbow = { { 0, 0, 0, 0 }, { 0.6, 1.179, 0, 0 }, { 3.8, 1.179, 0, 0 }, { 4.4, 0, 0, 0 } },
		LeftWrist = { { 0, 0, 0, 0 }, { 0.6, 0, 0, 0 }, { 3.8, 0, 0, 0 }, { 4.4, 0, 0, 0 } },
		RightKnee = { { 0, 0, 0, 0 }, { 0.7, -0.12, 0, 0 }, { 3.9, -0.12, 0, 0 }, { 4.4, 0, 0, 0 } },
		RightAnkle = { { 0, 0, 0, 0 }, { 0.8, 0, 0, 0 }, { 1, 0.32, 0, 0 }, { 1.2, 0, 0, 0 }, { 1.45, 0.32, 0, 0 }, { 1.65, 0, 0, 0 }, { 1.9, 0.32, 0, 0 }, { 2.1, 0, 0, 0 }, { 2.9, 0, 0, 0 }, { 3.1, 0.3, 0, 0 }, { 3.3, 0, 0, 0 }, { 3.55, 0.3, 0, 0 }, { 3.75, 0, 0, 0 }, { 4.4, 0, 0, 0 } },
	} },
	idleAuraCrossed = { seconds = 6.4, keys = {
		Root = { { 0, 0, 0, 0 }, { 1, 0, 0.06, 0.05 }, { 5.4, 0, 0.06, 0.05 }, { 6.3, 0, 0, 0 } },
		Waist = { { 0, 0, 0, 0 }, { 1, 0.07, -0.12, -0.05 }, { 5.4, 0.07, -0.14, -0.05 }, { 6.3, 0, 0, 0 } },
		Neck = { { 0, 0, 0, 0 }, { 0.9, 0.14, 0, 0 }, { 1.8, 0.16, -0.5, -0.04 }, { 3.9, 0.16, -0.55, -0.05 }, { 4.4, 0.06, -0.5, -0.04 }, { 4.75, 0.18, -0.45, -0.04 }, { 5.6, 0.12, 0, 0 }, { 6.3, 0, 0, 0 } },
		RightShoulder = { { 0, 0, 0, 0 }, { 0.7, 1.195, 1.221, -0.998 }, { 5.7, 1.195, 1.221, -0.998 }, { 6.4, 0, 0, 0 } },
		RightElbow = { { 0, 0, 0, 0 }, { 0.7, 1.213, 0, 0 }, { 5.7, 1.213, 0, 0 }, { 6.4, 0, 0, 0 } },
		RightWrist = { { 0, 0, 0, 0 }, { 0.7, 0, 0, 0 }, { 5.7, 0, 0, 0 }, { 6.4, 0, 0, 0 } },
		LeftShoulder = { { 0, 0, 0, 0 }, { 0.8, 1.405, -1.171, 1.043 }, { 5.6, 1.405, -1.171, 1.043 }, { 6.4, 0, 0, 0 } },
		LeftElbow = { { 0, 0, 0, 0 }, { 0.8, 1.14, 0, 0 }, { 5.6, 1.14, 0, 0 }, { 6.4, 0, 0, 0 } },
		LeftWrist = { { 0, 0, 0, 0 }, { 0.8, 0, 0, 0 }, { 5.6, 0, 0, 0 }, { 6.4, 0, 0, 0 } },
		RightHip = { { 0, 0, 0, 0 }, { 1, 0.1, -0.12, 0.03 }, { 5.4, 0.1, -0.12, 0.03 }, { 6.3, 0, 0, 0 } },
		RightKnee = { { 0, 0, 0, 0 }, { 1, -0.22, 0, 0 }, { 5.4, -0.22, 0, 0 }, { 6.3, 0, 0, 0 } },
		RightAnkle = { { 0, 0, 0, 0 }, { 1, 0.1, 0, 0 }, { 5.4, 0.1, 0, 0 }, { 6.3, 0, 0, 0 } },
	} },
	idleAuraBreeze = { seconds = 5.8, keys = {
		Root = { { 0, 0, 0, 0 }, { 1, 0, 0, -0.03 }, { 5, 0, 0, -0.03 }, { 5.8, 0, 0, 0 } },
		Waist = { { 0, 0, 0, 0 }, { 0.9, 0.05, 0.12, 0 }, { 4.9, 0.05, 0.14, 0 }, { 5.7, 0, 0, 0 } },
		Neck = { { 0, 0, 0, 0 }, { 0.8, 0.16, 0.32, 0.02 }, { 2, 0.2, 0.36, -0.06 }, { 3, 0.2, 0.4, -0.08 }, { 4.8, 0.16, 0.34, 0 }, { 5.7, 0, 0, 0 } },
		RightShoulder = { { 0, 0, 0, 0 }, { 1.2, 0, 0, 0 }, { 1.75, 0.867, 0.713, 0.814 }, { 2.25, 1.439, 0.758, 1.085 }, { 2.7, 1.804, 0.758, 1.295 }, { 3.4, 0, 0, 0 } },
		RightElbow = { { 0, 0, 0, 0 }, { 1.2, 0, 0, 0 }, { 1.75, 2.153, 0, 0 }, { 2.25, 1.793, 0, 0 }, { 2.7, 1.884, 0, 0 }, { 3.4, 0, 0, 0 } },
		RightWrist = { { 0, 0, 0, 0 }, { 1.75, 0.3, 0, 0 }, { 2.25, -0.2, 0, 0 }, { 2.7, -0.3, 0, 0 }, { 3.4, 0, 0, 0 } },
		LeftShoulder = { { 0, 0, 0, 0 }, { 1, -0.04, 0, -0.06 }, { 5, -0.04, 0, -0.06 }, { 5.8, 0, 0, 0 } },
		LeftKnee = { { 0, 0, 0, 0 }, { 1, -0.14, 0, 0 }, { 5, -0.14, 0, 0 }, { 5.8, 0, 0, 0 } },
	} },
	idleAuraPockets = { seconds = 5.4, keys = {
		Root = { { 0, 0, 0, 0 }, { 0.9, 0, 0.04, -0.04 }, { 4.6, 0, 0.04, -0.04 }, { 5.3, 0, 0, 0 } },
		Waist = { { 0, 0, 0, 0 }, { 0.9, 0.08, 0.06, 0.04 }, { 4.6, 0.08, 0.06, 0.04 }, { 5.3, 0, 0, 0 } },
		Neck = { { 0, 0, 0, 0 }, { 1, 0.04, -0.12, 0.12 }, { 2.2, 0.08, -0.14, 0.13 }, { 2.55, -0.06, -0.14, 0.13 }, { 2.9, 0.06, -0.14, 0.12 }, { 4.6, 0.04, -0.12, 0.12 }, { 5.3, 0, 0, 0 } },
		RightShoulder = { { 0, 0, 0, 0 }, { 0.7, 0.055, -0.03, -0.415 }, { 4.7, 0.055, -0.03, -0.415 }, { 5.4, 0, 0, 0 } },
		RightElbow = { { 0, 0, 0, 0 }, { 0.7, 0.414, 0, 0 }, { 4.7, 0.414, 0, 0 }, { 5.4, 0, 0, 0 } },
		RightWrist = { { 0, 0, 0, 0 }, { 0.7, 0, 0, 0 }, { 4.7, 0, 0, 0 }, { 5.4, 0, 0, 0 } },
		LeftShoulder = { { 0, 0, 0, 0 }, { 0.75, 0.055, 0.031, 0.415 }, { 4.7, 0.055, 0.031, 0.415 }, { 5.4, 0, 0, 0 } },
		LeftElbow = { { 0, 0, 0, 0 }, { 0.75, 0.414, 0, 0 }, { 4.7, 0.414, 0, 0 }, { 5.4, 0, 0, 0 } },
		LeftWrist = { { 0, 0, 0, 0 }, { 0.75, 0, 0, 0 }, { 4.7, 0, 0, 0 }, { 5.4, 0, 0, 0 } },
		LeftHip = { { 0, 0, 0, 0 }, { 0.9, 0.12, 0.1, -0.02 }, { 4.6, 0.12, 0.1, -0.02 }, { 5.3, 0, 0, 0 } },
		LeftKnee = { { 0, 0, 0, 0 }, { 0.9, -0.24, 0, 0 }, { 4.6, -0.24, 0, 0 }, { 5.3, 0, 0, 0 } },
		LeftAnkle = { { 0, 0, 0, 0 }, { 0.9, 0.11, 0, 0 }, { 4.6, 0.11, 0, 0 }, { 5.3, 0, 0, 0 } },
	} },
	idleAuraBrush = { seconds = 3.9, keys = {
		Waist = { { 0, 0, 0, 0 }, { 0.6, 0, 0.1, 0 }, { 1.6, 0, 0.1, 0 }, { 2.1, 0.05, -0.08, 0 }, { 3.2, 0.05, -0.08, 0 }, { 3.9, 0, 0, 0 } },
		Neck = { { 0, 0, 0, 0 }, { 0.5, -0.1, 0.22, 0.06 }, { 1.5, -0.1, 0.24, 0.06 }, { 2, 0.16, -0.28, -0.04 }, { 3.2, 0.16, -0.3, -0.04 }, { 3.8, 0, 0, 0 } },
		RightShoulder = { { 0, 0, 0, 0 }, { 0.55, 1.633, 1.051, -1.312 }, { 0.85, 0.573, 0.746, -0.588 }, { 1.15, 1.47, 1.004, -1.232 }, { 1.45, 0.565, 0.749, -0.579 }, { 2.2, 0, 0, 0 } },
		RightElbow = { { 0, 0, 0, 0 }, { 0.55, 1.415, 0, 0 }, { 0.85, 1.917, 0, 0 }, { 1.15, 1.434, 0, 0 }, { 1.45, 1.92, 0, 0 }, { 2.2, 0, 0, 0 } },
		RightWrist = { { 0, 0, 0, 0 }, { 0.55, 0.2, 0, 0 }, { 0.85, -0.3, 0, 0 }, { 1.15, 0.2, 0, 0 }, { 1.45, -0.3, 0, 0 }, { 2.2, 0, 0, 0 } },
		LeftShoulder = { { 0, 0, 0, 0 }, { 0.5, 0, 0, -0.08 }, { 1.6, 0, 0, -0.08 }, { 2.2, 0, 0, 0 }, { 3.9, 0, 0, 0 } },
	} },
	emoteWave = { seconds = 2.9, keys = {
		Waist = { { 0, 0, 0, 0 }, { 0.6, 0.03, 0.05, -0.06 }, { 2.1, 0.03, 0.05, -0.06 }, { 2.8, 0, 0, 0 } },
		Neck = { { 0, 0, 0, 0 }, { 0.6, 0.06, 0.16, 0.12 }, { 2.1, 0.06, 0.16, 0.12 }, { 2.8, 0, 0, 0 } },
		RightShoulder = { { 0, 0, 0, 0 }, { 0.22, 0.205, -0.266, 0.049 }, { 0.6, 1.609, 0.706, 0.705 }, { 0.85, 1.898, 0.357, 0.76 }, { 1.1, 1.723, 0.696, 0.6 }, { 1.35, 1.982, 0.316, 0.702 }, { 1.6, 1.747, 0.689, 0.573 }, { 1.85, 2.003, 0.305, 0.688 }, { 2.1, 1.801, 0.503, 0.572 }, { 2.9, 0, 0, 0 } },
		RightElbow = { { 0, 0, 0, 0 }, { 0.22, 0.025, 0, 0 }, { 0.6, 1.332, 0, 0 }, { 0.85, 0.656, 0, 0 }, { 1.1, 1.299, 0, 0 }, { 1.35, 0.653, 0, 0 }, { 1.6, 1.292, 0, 0 }, { 1.85, 0.652, 0, 0 }, { 2.1, 1.197, 0, 0 }, { 2.9, 0, 0, 0 } },
		RightWrist = { { 0, 0, 0, 0 }, { 0.22, 0, 0, 0 }, { 0.6, 0, 0, 0 }, { 0.85, 0, 0, 0 }, { 1.1, 0, 0, 0 }, { 1.35, 0, 0, 0 }, { 1.6, 0, 0, 0 }, { 1.85, 0, 0, 0 }, { 2.1, 0, 0, 0 }, { 2.9, 0, 0, 0 } },
		LeftShoulder = { { 0, 0, 0, 0 }, { 0.6, 0, 0, -0.08 }, { 2.1, 0, 0, -0.08 }, { 2.8, 0, 0, 0 } },
	} },
	emoteStretch = { seconds = 4, keys = {
		Root = { { 0, 0, 0, 0, 0, 0, 0 }, { 0.8, 0, 0, 0, 0, 0.22, 0 }, { 1.4, 0, 0, 0, 0, 0.22, 0 }, { 1.8, 0, 0, 0, 0, 0, 0 }, { 4, 0, 0, 0, 0, 0, 0 } },
		Waist = { { 0, 0, 0, 0 }, { 0.8, 0.14, 0, 0 }, { 1.5, 0.1, 0, 0 }, { 2, 0.08, 0, 0.24 }, { 2.6, 0.08, 0, -0.22 }, { 3.2, 0, 0, 0 }, { 4, 0, 0, 0 } },
		Neck = { { 0, 0, 0, 0 }, { 0.8, 0.3, 0, 0 }, { 2, 0.2, 0, 0.1 }, { 2.6, 0.2, 0, -0.1 }, { 3.3, -0.1, 0.2, 0.12 }, { 3.7, -0.1, -0.2, -0.12 }, { 4, 0, 0, 0 } },
		RightShoulder = { { 0, 0, 0, 0 }, { 0.8, 0.15, 0, 2.9 }, { 2.7, 0.15, 0, 2.9 }, { 3.3, 0, 0, 0.5 }, { 4, 0, 0, 0 } },
		RightElbow = { { 0, 0, 0, 0 }, { 0.8, 0.2, 0, 0 }, { 2.7, 0.2, 0, 0 }, { 3.3, 0.1, 0, 0 }, { 4, 0, 0, 0 } },
		LeftShoulder = { { 0, 0, 0, 0 }, { 0.8, 0.15, 0, -2.9 }, { 2.7, 0.15, 0, -2.9 }, { 3.3, 0, 0, -0.5 }, { 4, 0, 0, 0 } },
		LeftElbow = { { 0, 0, 0, 0 }, { 0.8, 0.2, 0, 0 }, { 2.7, 0.2, 0, 0 }, { 3.3, 0.1, 0, 0 }, { 4, 0, 0, 0 } },
		RightAnkle = { { 0, 0, 0, 0 }, { 0.8, -0.34, 0, 0 }, { 1.4, -0.34, 0, 0 }, { 1.8, 0, 0, 0 }, { 4, 0, 0, 0 } },
		LeftAnkle = { { 0, 0, 0, 0 }, { 0.8, -0.34, 0, 0 }, { 1.4, -0.34, 0, 0 }, { 1.8, 0, 0, 0 }, { 4, 0, 0, 0 } },
	} },
	emoteSpin = { seconds = 2.1, keys = {
		Root = { { 0, 0, 0, 0, 0, 0, 0 }, { 0.22, 0, -0.35, 0, 0, -0.18, 0 }, { 0.75, 0, 3, 0, 0, 0.35, 0 }, { 1.25, 0, 6.283, 0, 0, 0, 0 }, { 2.1, 0, 6.283, 0, 0, 0, 0 } },
		Neck = { { 0, 0, 0, 0 }, { 0.22, -0.12, 0, 0 }, { 0.75, 0.1, 0, 0 }, { 1.5, 0.16, 0, 0 }, { 2.1, 0, 0, 0 } },
		RightShoulder = { { 0, 0, 0, 0 }, { 0.22, 0.2, 0, 0.2 }, { 0.55, 0, 0, 1.5 }, { 1.15, 0, 0, 1.45 }, { 1.5, 0.1, 0, 2.3 }, { 1.85, 0.1, 0, 2.3 }, { 2.1, 0, 0, 0 } },
		LeftShoulder = { { 0, 0, 0, 0 }, { 0.22, 0.2, 0, -0.2 }, { 0.55, 0, 0, -1.5 }, { 1.15, 0, 0, -1.45 }, { 1.5, 0.1, 0, -2.3 }, { 1.85, 0.1, 0, -2.3 }, { 2.1, 0, 0, 0 } },
		RightHip = { { 0, 0, 0, 0 }, { 0.22, 0.22, 0, 0 }, { 0.6, 0.05, 0, 0 }, { 1.25, 0.15, 0, 0 }, { 1.5, 0, 0, 0 }, { 2.1, 0, 0, 0 } },
		RightKnee = { { 0, 0, 0, 0 }, { 0.22, -0.45, 0, 0 }, { 0.6, -0.1, 0, 0 }, { 1.25, -0.3, 0, 0 }, { 1.5, 0, 0, 0 }, { 2.1, 0, 0, 0 } },
		LeftHip = { { 0, 0, 0, 0 }, { 0.22, 0.22, 0, 0 }, { 0.6, 0.05, 0, 0 }, { 1.25, 0.15, 0, 0 }, { 1.5, 0, 0, 0 }, { 2.1, 0, 0, 0 } },
		LeftKnee = { { 0, 0, 0, 0 }, { 0.22, -0.45, 0, 0 }, { 0.6, -0.1, 0, 0 }, { 1.25, -0.3, 0, 0 }, { 1.5, 0, 0, 0 }, { 2.1, 0, 0, 0 } },
	} },
	emoteSitSquish = { seconds = 20, loop = { 1, 2 }, keys = {
		Root = { { 0, 0, 0, 0, 0, 0, 0 }, { 0.4, 0, 0, 0, 0, -0.75, 0 }, { 0.8, 0, 0, 0, 0, -1.85, 0 }, { 2, 0, 0, 0, 0, -1.85, 0 }, { 2.4, 0, 0, 0, 0, -0.75, 0 }, { 3, 0, 0, 0, 0, 0, 0 } },
		Waist = { { 0, 0, 0, 0 }, { 1, -0.12, 0, 0 }, { 1.5, -0.18, 0, 0.03 }, { 2, -0.12, 0, 0 }, { 3, 0, 0, 0 } },
		Neck = { { 0, 0, 0, 0 }, { 1, -0.32, 0.06, 0.06 }, { 1.5, -0.36, -0.04, -0.04 }, { 2, -0.32, 0.06, 0.06 }, { 3, 0, 0, 0 } },
		RightShoulder = { { 0, 0, 0, 0 }, { 1, 0.458, 0.063, -0.704 }, { 1.5, 0.454, 0.094, -0.745 }, { 2, 0.459, 0.077, -0.703 }, { 3, 0, 0, 0 } },
		RightElbow = { { 0, 0, 0, 0 }, { 1, 0.331, 0, 0 }, { 1.5, 0.341, 0, 0 }, { 2, 0.339, 0, 0 }, { 3, 0, 0, 0 } },
		RightWrist = { { 0, 0, 0, 0 }, { 1, 0, 0, 0 }, { 1.5, 0, 0, 0 }, { 2, 0, 0, 0 }, { 3, 0, 0, 0 } },
		LeftShoulder = { { 0, 0, 0, 0 }, { 1, 0.458, -0.063, 0.704 }, { 1.5, 0.454, -0.094, 0.745 }, { 2, 0.459, -0.075, 0.703 }, { 3, 0, 0, 0 } },
		LeftElbow = { { 0, 0, 0, 0 }, { 1, 0.331, 0, 0 }, { 1.5, 0.341, 0, 0 }, { 2, 0.338, 0, 0 }, { 3, 0, 0, 0 } },
		LeftWrist = { { 0, 0, 0, 0 }, { 1, 0, 0, 0 }, { 1.5, 0, 0, 0 }, { 2, 0, 0, 0 }, { 3, 0, 0, 0 } },
		RightHip = { { 0, 0, 0, 0 }, { 0.4, 0.95, 0, 0.3 }, { 0.8, 1.5, 0, 0.72 }, { 2, 1.5, 0, 0.72 }, { 2.4, 0.95, 0, 0.3 }, { 3, 0, 0, 0 } },
		RightKnee = { { 0, 0, 0, 0 }, { 0.4, -1.9, 0, 0 }, { 0.8, -2.65, 0, 0 }, { 2, -2.65, 0, 0 }, { 2.4, -1.9, 0, 0 }, { 3, 0, 0, 0 } },
		RightAnkle = { { 0, 0, 0, 0 }, { 0.4, 0.3, 0, 0 }, { 0.8, -1, 0, 0 }, { 2, -1, 0, 0 }, { 2.4, 0.3, 0, 0 }, { 3, 0, 0, 0 } },
		LeftHip = { { 0, 0, 0, 0 }, { 0.4, 0.95, 0, -0.3 }, { 0.8, 1.5, 0, -0.72 }, { 2, 1.5, 0, -0.72 }, { 2.4, 0.95, 0, -0.3 }, { 3, 0, 0, 0 } },
		LeftKnee = { { 0, 0, 0, 0 }, { 0.4, -1.9, 0, 0 }, { 0.8, -2.65, 0, 0 }, { 2, -2.65, 0, 0 }, { 2.4, -1.9, 0, 0 }, { 3, 0, 0, 0 } },
		LeftAnkle = { { 0, 0, 0, 0 }, { 0.4, 0.3, 0, 0 }, { 0.8, -1, 0, 0 }, { 2, -1, 0, 0 }, { 2.4, 0.3, 0, 0 }, { 3, 0, 0, 0 } },
	} },
	emoteAura = { seconds = 10.8, loop = { 0.9, 3.9 }, keys = {
		Root = { { 0, 0, 0, 0 }, { 0.9, 0, 0, 0.04 }, { 2.4, 0, 0.05, -0.04 }, { 3.9, 0, 0, 0.04 }, { 4.8, 0, 0, 0 } },
		Waist = { { 0, 0, 0, 0 }, { 0.9, 0.05, -0.05, -0.05 }, { 2.4, 0.05, 0.1, 0.05 }, { 3.9, 0.05, -0.05, -0.05 }, { 4.8, 0, 0, 0 } },
		Neck = { { 0, 0, 0, 0 }, { 0.9, 0.16, -0.25, -0.06 }, { 2.4, 0.12, 0.1, 0.06 }, { 3.9, 0.16, -0.25, -0.06 }, { 4.8, 0, 0, 0 } },
		RightShoulder = { { 0, 0, 0, 0 }, { 0.9, 0.994, -0.175, 0.853 }, { 1.65, 1.317, 0.02, 0.835 }, { 2.4, 1.004, 0.125, 0.213 }, { 3.15, 1.318, -0.018, 0.82 }, { 3.9, 1.135, -0.263, 0.853 }, { 4.8, 0, 0, 0 } },
		RightElbow = { { 0, 0, 0, 0 }, { 0.9, 0.262, 0, 0 }, { 1.65, 0.537, 0, 0 }, { 2.4, 0.641, 0, 0 }, { 3.15, 0.612, 0, 0 }, { 3.9, 0.322, 0, 0 }, { 4.8, 0, 0, 0 } },
		RightWrist = { { 0, 0, 0, 0 }, { 0.9, 0.2, 0, 0 }, { 1.65, -0.35, 0, 0 }, { 2.4, 0.3, 0, 0 }, { 3.15, -0.35, 0, 0 }, { 3.9, 0.2, 0, 0 }, { 4.8, 0, 0, 0 } },
		LeftShoulder = { { 0, 0, 0, 0 }, { 0.7, -0.764, -0.611, -0.226 }, { 3.9, -0.764, -0.611, -0.226 }, { 4.8, 0, 0, 0 } },
		LeftElbow = { { 0, 0, 0, 0 }, { 0.7, 1.179, 0, 0 }, { 3.9, 1.179, 0, 0 }, { 4.8, 0, 0, 0 } },
		LeftWrist = { { 0, 0, 0, 0 }, { 0.7, 0, 0, 0 }, { 3.9, 0, 0, 0 }, { 4.8, 0, 0, 0 } },
		RightKnee = { { 0, 0, 0, 0 }, { 0.9, -0.08, 0, 0 }, { 1.65, -0.26, 0, 0 }, { 2.4, -0.08, 0, 0 }, { 3.15, -0.26, 0, 0 }, { 3.9, -0.08, 0, 0 }, { 4.8, 0, 0, 0 } },
		LeftKnee = { { 0, 0, 0, 0 }, { 0.9, -0.2, 0, 0 }, { 1.65, -0.06, 0, 0 }, { 2.4, -0.2, 0, 0 }, { 3.15, -0.06, 0, 0 }, { 3.9, -0.2, 0, 0 }, { 4.8, 0, 0, 0 } },
	} },
	emoteCheer = { seconds = 2.8, keys = {
		Root = { { 0, 0, 0, 0, 0, 0, 0 }, { 0.35, 0, 0, 0, 0, 0.05, 0 }, { 0.65, 0, 0, 0, 0, -0.14, 0 }, { 0.95, 0, 0, 0, 0, 0.05, 0 }, { 1.25, 0, 0, 0, 0, -0.14, 0 }, { 1.55, 0, 0, 0, 0, 0.05, 0 }, { 2.8, 0, 0, 0, 0, 0, 0 } },
		Waist = { { 0, 0, 0, 0 }, { 0.35, 0.1, 0, 0 }, { 2.1, 0.1, 0, 0 }, { 2.8, 0, 0, 0 } },
		Neck = { { 0, 0, 0, 0 }, { 0.35, 0.3, 0, 0 }, { 1.55, 0.3, 0, 0 }, { 2.1, 0.22, 0, 0.08 }, { 2.8, 0, 0, 0 } },
		RightShoulder = { { 0, 0, 0, 0 }, { 0.35, 2.777, 0.466, -0.234 }, { 0.65, 1.889, 0.579, 0.316 }, { 0.95, 2.434, 0.875, 0.079 }, { 1.25, 1.769, 0.63, 0.436 }, { 1.55, 2.33, 0.955, 0.192 }, { 2.1, 2.552, 0.828, -0.022 }, { 2.8, 0, 0, 0 } },
		RightElbow = { { 0, 0, 0, 0 }, { 0.35, 0.33, 0, 0 }, { 0.65, 1.179, 0, 0 }, { 0.95, 0.647, 0, 0 }, { 1.25, 1.243, 0, 0 }, { 1.55, 0.686, 0, 0 }, { 2.1, 0.544, 0, 0 }, { 2.8, 0, 0, 0 } },
		RightWrist = { { 0, 0, 0, 0 }, { 0.35, 0, 0, 0 }, { 0.65, 0, 0, 0 }, { 0.95, 0, 0, 0 }, { 1.25, 0, 0, 0 }, { 1.55, 0, 0, 0 }, { 2.1, 0, 0, 0 }, { 2.8, 0, 0, 0 } },
		LeftShoulder = { { 0, 0, 0, 0 }, { 0.35, 2.777, -0.465, 0.235 }, { 0.65, 1.891, -0.578, -0.315 }, { 0.95, 2.443, -0.867, -0.07 }, { 1.25, 1.771, -0.629, -0.434 }, { 1.55, 2.346, -0.943, -0.174 }, { 2.1, 2.56, -0.818, 0.031 }, { 2.8, 0, 0, 0 } },
		LeftElbow = { { 0, 0, 0, 0 }, { 0.35, 0.329, 0, 0 }, { 0.65, 1.178, 0, 0 }, { 0.95, 0.643, 0, 0 }, { 1.25, 1.243, 0, 0 }, { 1.55, 0.681, 0, 0 }, { 2.1, 0.539, 0, 0 }, { 2.8, 0, 0, 0 } },
		LeftWrist = { { 0, 0, 0, 0 }, { 0.35, 0, 0, 0 }, { 0.65, 0, 0, 0 }, { 0.95, 0, 0, 0 }, { 1.25, 0, 0, 0 }, { 1.55, 0, 0, 0 }, { 2.1, 0, 0, 0 }, { 2.8, 0, 0, 0 } },
		RightHip = { { 0, 0, 0, 0 }, { 0.65, 0.16, 0, 0 }, { 0.95, 0.03, 0, 0 }, { 1.25, 0.16, 0, 0 }, { 1.55, 0.03, 0, 0 }, { 2.8, 0, 0, 0 } },
		RightKnee = { { 0, 0, 0, 0 }, { 0.35, -0.05, 0, 0 }, { 0.65, -0.3, 0, 0 }, { 0.95, -0.05, 0, 0 }, { 1.25, -0.3, 0, 0 }, { 1.55, -0.05, 0, 0 }, { 2.8, 0, 0, 0 } },
		LeftHip = { { 0, 0, 0, 0 }, { 0.65, 0.16, 0, 0 }, { 0.95, 0.03, 0, 0 }, { 1.25, 0.16, 0, 0 }, { 1.55, 0.03, 0, 0 }, { 2.8, 0, 0, 0 } },
		LeftKnee = { { 0, 0, 0, 0 }, { 0.35, -0.05, 0, 0 }, { 0.65, -0.3, 0, 0 }, { 0.95, -0.05, 0, 0 }, { 1.25, -0.3, 0, 0 }, { 1.55, -0.05, 0, 0 }, { 2.8, 0, 0, 0 } },
	} },
	emoteBow = { seconds = 2.8, keys = {
		Waist = { { 0, 0, 0, 0 }, { 0.55, 0, 0, 0 }, { 1.1, -0.62, 0, 0 }, { 1.6, -0.6, 0, 0 }, { 2.15, 0, 0, 0 }, { 2.8, 0, 0, 0 } },
		Neck = { { 0, 0, 0, 0 }, { 0.6, 0, 0, 0 }, { 1.15, -0.28, 0, 0 }, { 1.6, -0.25, 0, 0 }, { 2.15, 0.04, 0, 0 }, { 2.8, 0, 0, 0 } },
		RightShoulder = { { 0, 0, 0, 0 }, { 0.5, 0.472, 1.394, -0.371 }, { 2.2, 0.47, 1.394, -0.369 }, { 2.8, 0, 0, 0 } },
		RightElbow = { { 0, 0, 0, 0 }, { 0.5, 1.912, 0, 0 }, { 2.2, 1.912, 0, 0 }, { 2.8, 0, 0, 0 } },
		RightWrist = { { 0, 0, 0, 0 }, { 0.5, 0, 0, 0 }, { 2.2, 0, 0, 0 }, { 2.8, 0, 0, 0 } },
		LeftShoulder = { { 0, 0, 0, 0 }, { 0.5, -0.812, -1.384, 0.328 }, { 2.2, -0.813, -1.384, 0.327 }, { 2.8, 0, 0, 0 } },
		LeftElbow = { { 0, 0, 0, 0 }, { 0.5, 1.125, 0, 0 }, { 2.2, 1.126, 0, 0 }, { 2.8, 0, 0, 0 } },
		LeftWrist = { { 0, 0, 0, 0 }, { 0.5, 0, 0, 0 }, { 2.2, 0, 0, 0 }, { 2.8, 0, 0, 0 } },
		RightHip = { { 0, 0, 0, 0 }, { 1.1, 0.12, 0, 0 }, { 1.6, 0.12, 0, 0 }, { 2.15, 0, 0, 0 } },
		LeftHip = { { 0, 0, 0, 0 }, { 1.1, 0.12, 0, 0 }, { 1.6, 0.12, 0, 0 }, { 2.15, 0, 0, 0 } },
	} },
	emoteRoyalWave = { seconds = 3.8, keys = {
		Waist = { { 0, 0, 0, 0 }, { 0.55, 0.06, 0, 0 }, { 1.3, 0.06, 0.08, 0 }, { 2.4, 0.06, -0.08, 0 }, { 3.1, 0.05, 0, 0 }, { 3.8, 0, 0, 0 } },
		Neck = { { 0, 0, 0, 0 }, { 0.55, 0.12, 0, 0 }, { 1.3, 0.12, 0.28, 0 }, { 2.4, 0.12, -0.28, 0 }, { 3.1, 0.1, 0, 0 }, { 3.8, 0, 0, 0 } },
		RightShoulder = { { 0, 0, 0, 0 }, { 0.55, 0.461, 0.5, 0.216 }, { 0.95, 0.461, 0.5, 0.216 }, { 1.4, 0.461, 0.5, 0.216 }, { 1.85, 0.461, 0.5, 0.216 }, { 2.3, 0.461, 0.5, 0.216 }, { 2.75, 0.461, 0.5, 0.216 }, { 3.1, 0.461, 0.5, 0.216 }, { 3.8, 0, 0, 0 } },
		RightElbow = { { 0, 0, 0, 0 }, { 0.55, 2.5, 0, 0 }, { 0.95, 2.5, 0, 0 }, { 1.4, 2.5, 0, 0 }, { 1.85, 2.5, 0, 0 }, { 2.3, 2.5, 0, 0 }, { 2.75, 2.5, 0, 0 }, { 3.1, 2.5, 0, 0 }, { 3.8, 0, 0, 0 } },
		RightWrist = { { 0, 0, 0, 0 }, { 0.55, 0, 0, 0 }, { 0.95, 0, 0.55, 0 }, { 1.4, 0, -0.4, 0 }, { 1.85, 0, 0.55, 0 }, { 2.3, 0, -0.4, 0 }, { 2.75, 0, 0.3, 0 }, { 3.1, 0, 0, 0 }, { 3.8, 0, 0, 0 } },
		LeftShoulder = { { 0, 0, 0, 0 }, { 0.5, -1.06, -1.267, 0.265 }, { 3.1, -1.057, -1.266, 0.268 }, { 3.8, 0, 0, 0 } },
		LeftElbow = { { 0, 0, 0, 0 }, { 0.5, 1.028, 0, 0 }, { 3.1, 1.027, 0, 0 }, { 3.8, 0, 0, 0 } },
		LeftWrist = { { 0, 0, 0, 0 }, { 0.5, 0, 0, 0 }, { 3.1, 0, 0, 0 }, { 3.8, 0, 0, 0 } },
	} },
	emoteGroove = { seconds = 8.9, loop = { 0.4, 2.4 }, keys = {
		Root = { { 0, 0, 0, 0, 0, 0, 0 }, { 0.4, 0, 0.1, 0.05, 0, -0.1, 0 }, { 0.9, 0, 0, 0, 0, 0, 0 }, { 1.4, 0, -0.1, -0.05, 0, -0.1, 0 }, { 1.9, 0, 0, 0, 0, 0, 0 }, { 2.4, 0, 0.1, 0.05, 0, -0.1, 0 }, { 2.9, 0, 0, 0, 0, 0, 0 } },
		Waist = { { 0, 0, 0, 0 }, { 0.4, 0.04, -0.16, -0.06 }, { 0.9, 0, 0, 0 }, { 1.4, 0.04, 0.16, 0.06 }, { 1.9, 0, 0, 0 }, { 2.4, 0.04, -0.16, -0.06 }, { 2.9, 0, 0, 0 } },
		Neck = { { 0, 0, 0, 0 }, { 0.4, 0.04, 0, 0.06 }, { 0.65, -0.1, 0, 0.06 }, { 0.9, 0.04, 0, -0.06 }, { 1.15, -0.1, 0, -0.06 }, { 1.4, 0.04, 0, 0.06 }, { 1.65, -0.1, 0, 0.06 }, { 1.9, 0.04, 0, -0.06 }, { 2.15, -0.1, 0, -0.06 }, { 2.4, 0.04, 0, 0.06 }, { 2.9, 0, 0, 0 } },
		RightShoulder = { { 0, 0, 0, 0 }, { 0.4, 0.55, 0, 0.25 }, { 0.9, 0.1, 0, 0.3 }, { 1.4, -0.3, 0, 0.25 }, { 1.9, 0.1, 0, 0.3 }, { 2.4, 0.55, 0, 0.25 }, { 2.9, 0, 0, 0 } },
		RightElbow = { { 0, 0, 0, 0 }, { 0.4, 1.3, 0, 0 }, { 0.9, 1.1, 0, 0 }, { 1.4, 1.3, 0, 0 }, { 1.9, 1.1, 0, 0 }, { 2.4, 1.3, 0, 0 }, { 2.9, 0, 0, 0 } },
		LeftShoulder = { { 0, 0, 0, 0 }, { 0.4, -0.3, 0, -0.25 }, { 0.9, 0.1, 0, -0.3 }, { 1.4, 0.55, 0, -0.25 }, { 1.9, 0.1, 0, -0.3 }, { 2.4, -0.3, 0, -0.25 }, { 2.9, 0, 0, 0 } },
		LeftElbow = { { 0, 0, 0, 0 }, { 0.4, 1.3, 0, 0 }, { 0.9, 1.1, 0, 0 }, { 1.4, 1.3, 0, 0 }, { 1.9, 1.1, 0, 0 }, { 2.4, 1.3, 0, 0 }, { 2.9, 0, 0, 0 } },
		RightHip = { { 0, 0, 0, 0 }, { 0.4, 0.18, 0, 0 }, { 0.9, 0.03, 0, 0 }, { 1.4, 0.06, 0, 0 }, { 1.9, 0.03, 0, 0 }, { 2.4, 0.18, 0, 0 }, { 2.9, 0, 0, 0 } },
		RightKnee = { { 0, 0, 0, 0 }, { 0.4, -0.32, 0, 0 }, { 0.9, -0.06, 0, 0 }, { 1.4, -0.12, 0, 0 }, { 1.9, -0.06, 0, 0 }, { 2.4, -0.32, 0, 0 }, { 2.9, 0, 0, 0 } },
		LeftHip = { { 0, 0, 0, 0 }, { 0.4, 0.06, 0, 0 }, { 0.9, 0.03, 0, 0 }, { 1.4, 0.18, 0, 0 }, { 1.9, 0.03, 0, 0 }, { 2.4, 0.06, 0, 0 }, { 2.9, 0, 0, 0 } },
		LeftKnee = { { 0, 0, 0, 0 }, { 0.4, -0.12, 0, 0 }, { 0.9, -0.06, 0, 0 }, { 1.4, -0.32, 0, 0 }, { 1.9, -0.06, 0, 0 }, { 2.4, -0.12, 0, 0 }, { 2.9, 0, 0, 0 } },
	} },
	emoteShrug = { seconds = 2, keys = {
		Waist = { { 0, 0, 0, 0 }, { 0.4, 0.04, 0, 0.03 }, { 1.3, 0.04, 0, 0.03 }, { 2, 0, 0, 0 } },
		Neck = { { 0, 0, 0, 0 }, { 0.4, -0.06, 0.08, 0.2 }, { 1.3, -0.04, 0.08, 0.22 }, { 2, 0, 0, 0 } },
		RightShoulder = { { 0, 0, 0, 0 }, { 0.4, 0.429, -0.541, 0.004 }, { 1.3, 0.432, -0.514, 0.024 }, { 2, 0, 0, 0 } },
		RightElbow = { { 0, 0, 0, 0 }, { 0.4, 1.355, 0, 0 }, { 1.3, 1.396, 0, 0 }, { 2, 0, 0, 0 } },
		RightWrist = { { 0, 0, 0, 0 }, { 0.4, 0, -0.6, 0 }, { 1.3, 0, -0.6, 0 }, { 2, 0, 0, 0 } },
		LeftShoulder = { { 0, 0, 0, 0 }, { 0.4, 0.429, 0.541, -0.004 }, { 1.3, 0.432, 0.514, -0.024 }, { 2, 0, 0, 0 } },
		LeftElbow = { { 0, 0, 0, 0 }, { 0.4, 1.355, 0, 0 }, { 1.3, 1.396, 0, 0 }, { 2, 0, 0, 0 } },
		LeftWrist = { { 0, 0, 0, 0 }, { 0.4, 0, 0.6, 0 }, { 1.3, 0, 0.6, 0 }, { 2, 0, 0, 0 } },
	} },
	emoteFlex = { seconds = 2.8, keys = {
		Waist = { { 0, 0, 0, 0 }, { 0.45, 0.06, 0, 0 }, { 1.3, 0.06, 0.32, 0 }, { 1.9, 0.06, -0.32, 0 }, { 2.3, 0.04, 0, 0 }, { 2.8, 0, 0, 0 } },
		Neck = { { 0, 0, 0, 0 }, { 0.45, 0.1, 0, 0 }, { 1.3, 0.1, 0.2, 0 }, { 1.9, 0.1, -0.2, 0 }, { 2.3, 0.05, 0, 0 }, { 2.8, 0, 0, 0 } },
		RightShoulder = { { 0, 0, 0, 0 }, { 0.45, 1.094, 0.134, 0.979 }, { 0.75, 0.92, 0.107, 0.965 }, { 1.05, 1.079, 0.128, 0.985 }, { 2.2, 1.093, 0.133, 0.98 }, { 2.8, 0, 0, 0 } },
		RightElbow = { { 0, 0, 0, 0 }, { 0.45, 1.945, 0, 0 }, { 0.75, 2.047, 0, 0 }, { 1.05, 1.957, 0, 0 }, { 2.2, 1.946, 0, 0 }, { 2.8, 0, 0, 0 } },
		RightWrist = { { 0, 0, 0, 0 }, { 0.45, 0, 0, 0 }, { 0.75, 0, 0, 0 }, { 1.05, 0, 0, 0 }, { 2.2, 0, 0, 0 }, { 2.8, 0, 0, 0 } },
		LeftShoulder = { { 0, 0, 0, 0 }, { 0.45, 1.094, -0.134, -0.979 }, { 0.75, 0.92, -0.107, -0.965 }, { 1.05, 1.079, -0.128, -0.985 }, { 2.2, 1.093, -0.133, -0.98 }, { 2.8, 0, 0, 0 } },
		LeftElbow = { { 0, 0, 0, 0 }, { 0.45, 1.945, 0, 0 }, { 0.75, 2.047, 0, 0 }, { 1.05, 1.957, 0, 0 }, { 2.2, 1.946, 0, 0 }, { 2.8, 0, 0, 0 } },
		LeftWrist = { { 0, 0, 0, 0 }, { 0.45, 0, 0, 0 }, { 0.75, 0, 0, 0 }, { 1.05, 0, 0, 0 }, { 2.2, 0, 0, 0 }, { 2.8, 0, 0, 0 } },
		RightKnee = { { 0, 0, 0, 0 }, { 0.45, -0.14, 0, 0 }, { 2.3, -0.14, 0, 0 }, { 2.8, 0, 0, 0 } },
		LeftKnee = { { 0, 0, 0, 0 }, { 0.45, -0.14, 0, 0 }, { 2.3, -0.14, 0, 0 }, { 2.8, 0, 0, 0 } },
	} },
}

-- How long each lasts, for whoever plays it (EmoteService, PlayerLife).
Poses.LENGTH = {
	idleLook = 4.8,
	idleShift = 4.2,
	idlePonder = 4.6,
	idleYawn = 4.6,
	idleHand = 3.8,
	idleTap = 4.4,
	idleAuraCrossed = 6.4,
	idleAuraBreeze = 5.8,
	idleAuraPockets = 5.4,
	idleAuraBrush = 3.9,
	emoteWave = 2.9,
	emoteStretch = 4,
	emoteSpin = 2.1,
	emoteSitSquish = 20,
	emoteAura = 10.8,
	emoteCheer = 2.8,
	emoteBow = 2.8,
	emoteRoyalWave = 3.8,
	emoteGroove = 8.9,
	emoteShrug = 2,
	emoteFlex = 2.8,
}

function Poses.idleLook(name: string, t: number, w: number, r6: boolean): CFrame?
	return play(KEYED.idleLook, name, t, r6)
end

function Poses.idleShift(name: string, t: number, w: number, r6: boolean): CFrame?
	return play(KEYED.idleShift, name, t, r6)
end

function Poses.idlePonder(name: string, t: number, w: number, r6: boolean): CFrame?
	return play(KEYED.idlePonder, name, t, r6)
end

function Poses.idleYawn(name: string, t: number, w: number, r6: boolean): CFrame?
	return play(KEYED.idleYawn, name, t, r6)
end

function Poses.idleHand(name: string, t: number, w: number, r6: boolean): CFrame?
	return play(KEYED.idleHand, name, t, r6)
end

function Poses.idleTap(name: string, t: number, w: number, r6: boolean): CFrame?
	return play(KEYED.idleTap, name, t, r6)
end

function Poses.idleAuraCrossed(name: string, t: number, w: number, r6: boolean): CFrame?
	return play(KEYED.idleAuraCrossed, name, t, r6)
end

function Poses.idleAuraBreeze(name: string, t: number, w: number, r6: boolean): CFrame?
	return play(KEYED.idleAuraBreeze, name, t, r6)
end

function Poses.idleAuraPockets(name: string, t: number, w: number, r6: boolean): CFrame?
	return play(KEYED.idleAuraPockets, name, t, r6)
end

function Poses.idleAuraBrush(name: string, t: number, w: number, r6: boolean): CFrame?
	return play(KEYED.idleAuraBrush, name, t, r6)
end

function Poses.emoteWave(name: string, t: number, w: number, r6: boolean): CFrame?
	return play(KEYED.emoteWave, name, t, r6)
end

function Poses.emoteStretch(name: string, t: number, w: number, r6: boolean): CFrame?
	return play(KEYED.emoteStretch, name, t, r6)
end

function Poses.emoteSpin(name: string, t: number, w: number, r6: boolean): CFrame?
	return play(KEYED.emoteSpin, name, t, r6)
end

function Poses.emoteSitSquish(name: string, t: number, w: number, r6: boolean): CFrame?
	return play(KEYED.emoteSitSquish, name, t, r6)
end

function Poses.emoteAura(name: string, t: number, w: number, r6: boolean): CFrame?
	return play(KEYED.emoteAura, name, t, r6)
end

function Poses.emoteCheer(name: string, t: number, w: number, r6: boolean): CFrame?
	return play(KEYED.emoteCheer, name, t, r6)
end

function Poses.emoteBow(name: string, t: number, w: number, r6: boolean): CFrame?
	return play(KEYED.emoteBow, name, t, r6)
end

function Poses.emoteRoyalWave(name: string, t: number, w: number, r6: boolean): CFrame?
	return play(KEYED.emoteRoyalWave, name, t, r6)
end

function Poses.emoteGroove(name: string, t: number, w: number, r6: boolean): CFrame?
	return play(KEYED.emoteGroove, name, t, r6)
end

function Poses.emoteShrug(name: string, t: number, w: number, r6: boolean): CFrame?
	return play(KEYED.emoteShrug, name, t, r6)
end

function Poses.emoteFlex(name: string, t: number, w: number, r6: boolean): CFrame?
	return play(KEYED.emoteFlex, name, t, r6)
end
-- KEYED END

Poses.STAMP = "21531f97"
return Poses
