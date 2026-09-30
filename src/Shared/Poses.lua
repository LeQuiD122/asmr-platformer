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
function Poses.dive(name: string, t: number, w: number, r6: boolean): CFrame?
	local close = math.clamp((t - 0.8) / 1.0, 0, 1)
	close = close * close * (3 - 2 * close)
	local spread = 1.55 + (2.95 - 1.55) * close
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
		return CFrame.Angles(0, 0, spread * w)
	elseif name == "LeftShoulder" then
		return CFrame.Angles(0, 0, -spread * w)
	elseif name == "RightElbow" or name == "LeftElbow" then
		return CFrame.Angles(0.1 * (1 - close) * w, 0, 0)
	elseif name == "Neck" then
		return CFrame.Angles((0.4 - 0.9 * close) * w, 0, 0)
	elseif name == "Waist" then
		return CFrame.Angles(0.25 * (1 - close) * w, 0, 0)
	elseif name == "RightHip" or name == "LeftHip" then
		return CFrame.Angles(-0.12 * (1 - close) * w, 0, 0)
	elseif name == "RightKnee" or name == "LeftKnee" then
		return CFrame.identity
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

-- THE FLUME: on your back, feet first, arms crossed over your chest the way the sign at every flume
-- tells you to, head up a little to watch where you are going.
function Poses.flume(name: string, t: number, w: number, r6: boolean): CFrame?
	if r6 then
		if name == "Right Shoulder" then
			return CFrame.Angles(0, 0, 1.2 * w)
		elseif name == "Left Shoulder" then
			return CFrame.Angles(0, 0, -1.2 * w)
		end
		return nil
	end
	local breathe = 0.04 * math.sin(t * 2.2)
	if name == "RightShoulder" then
		return CFrame.Angles((1.25 + breathe) * w, 0, -0.55 * w)
	elseif name == "LeftShoulder" then
		return CFrame.Angles((1.25 + breathe) * w, 0, 0.55 * w)
	elseif name == "RightElbow" or name == "LeftElbow" then
		return CFrame.Angles(1.9 * w, 0, 0)
	elseif name == "Neck" then
		return CFrame.Angles(-0.35 * w, 0.15 * math.sin(t * 0.9) * w, 0)
	elseif name == "RightHip" or name == "LeftHip" then
		return CFrame.identity
	elseif name == "RightKnee" or name == "LeftKnee" then
		return CFrame.identity
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

return Poses
