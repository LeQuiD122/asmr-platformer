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

-- ===== THE EMOTES (the shop's, played by EmoteService on every client) =====

local function ease(u: number): number
	u = math.clamp(u, 0, 1)
	return u * u * (3 - 2 * u)
end

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

-- STRETCH: both arms slowly up over the head, back arched and head back, then a lean to each side.
function Poses.stretch(name: string, t: number, w: number, r6: boolean): CFrame?
	local up = ease(t / 1.2)
	local lean = if t > 1.4 then 0.18 * math.sin((t - 1.4) * 2.6) else 0
	if r6 then
		if name == "Right Shoulder" then
			return CFrame.Angles(0, 0, 2.9 * up * w)
		elseif name == "Left Shoulder" then
			return CFrame.Angles(0, 0, -2.9 * up * w)
		end
		return nil
	end
	if name == "RightShoulder" then
		return CFrame.Angles(0, 0, 2.95 * up * w)
	elseif name == "LeftShoulder" then
		return CFrame.Angles(0, 0, -2.95 * up * w)
	elseif name == "RightElbow" or name == "LeftElbow" then
		return CFrame.Angles(0.1 * w, 0, 0)
	elseif name == "Waist" then
		return CFrame.Angles(0.18 * up * w, 0, lean * w)
	elseif name == "Neck" then
		return CFrame.Angles(0.3 * up * w, 0, 0)
	end
	return nil
end

-- SPIN: once round on the spot with the arms out, the whole body turning on its root joint (so every
-- client sees the same turn, and the character itself never moves). A full turn ends where it began.
function Poses.spin(name: string, t: number, w: number, r6: boolean): CFrame?
	local angle = 2 * math.pi * ease(t / 1.3)
	if r6 then
		if name == "RootJoint" then
			return CFrame.Angles(0, 0, angle)
		elseif name == "Right Shoulder" then
			return CFrame.Angles(0, 0, 1.5 * w)
		elseif name == "Left Shoulder" then
			return CFrame.Angles(0, 0, -1.5 * w)
		end
		return nil
	end
	if name == "Root" then
		return CFrame.Angles(0, angle, 0)
	elseif name == "RightShoulder" then
		return CFrame.Angles(0, 0, 1.5 * w)
	elseif name == "LeftShoulder" then
		return CFrame.Angles(0, 0, -1.5 * w)
	end
	return nil
end

-- SIT AND SQUISH: down on the floor cross-legged (the body lowered on its root joint, legs folded under),
-- hands together in front squeezing a little toy, head down to watch it. `squeeze` is 0 to 1, the toy's
-- own beat, so the hands close as it does.
function Poses.sitSquish(name: string, t: number, w: number, r6: boolean): CFrame?
	local squeeze = math.max(0, math.sin(t * 3.2)) ^ 2
	if r6 then
		if name == "Right Shoulder" then
			return CFrame.Angles(0, 0, 1.2 * w)
		elseif name == "Left Shoulder" then
			return CFrame.Angles(0, 0, -1.2 * w)
		elseif name == "Right Hip" then
			return CFrame.Angles(0, 0, 1.4 * w)
		elseif name == "Left Hip" then
			return CFrame.Angles(0, 0, -1.4 * w)
		end
		return nil
	end
	if name == "Root" then
		return CFrame.new(0, -1.75 * w, 0)
	elseif name == "RightHip" then
		return CFrame.Angles(1.45 * w, 0, 0.55 * w)
	elseif name == "LeftHip" then
		return CFrame.Angles(1.45 * w, 0, -0.55 * w)
	elseif name == "RightKnee" or name == "LeftKnee" then
		return CFrame.Angles(-1.9 * w, 0, 0)
	elseif name == "RightShoulder" then
		return CFrame.Angles((0.95 + 0.08 * squeeze) * w, 0, -0.25 * w)
	elseif name == "LeftShoulder" then
		return CFrame.Angles((0.95 + 0.08 * squeeze) * w, 0, 0.25 * w)
	elseif name == "RightElbow" or name == "LeftElbow" then
		return CFrame.Angles((0.95 + 0.2 * squeeze) * w, 0, 0)
	elseif name == "Neck" then
		return CFrame.Angles(-0.3 * w, 0, 0)
	end
	return nil
end

Poses.STAMP = "91b97109"
return Poses
