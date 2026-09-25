--!strict
-- ReplicatedStorage/Shared/SeaRig.lua
-- The Sunken City's meshes: finding them, checking them, putting them in the world, and bending
-- the rigged ones. SunkenCityClient draws the animals, the kelp and the gulls with it;
-- SunkenCityService stands the Ferris wheel with it.
--
-- === Where the meshes come from ===
--
-- blender/gen_sealife.py and blender/gen_ferris.py. They are imported by hand into
-- ReplicatedStorage/Assets/TileMeshes, the FBX with its Bone children. Anything not imported, or
-- imported wrong, is simply not drawn from a mesh: the caller builds the old part-built one
-- instead, so importing goes one mesh at a time and nothing breaks in between.
--
-- "Imported wrong" is checked, not hoped about. A mesh whose size is not what the generator built
-- is an old import or a wrongly scaled one -- and a rig CANNOT be resized, because setting Size
-- moves the drawn mesh and leaves every Bone where it was (ChunkBuilder learned that) -- so it is
-- refused. A rigged mesh imported without its bones cannot move the way it is meant to, so it is
-- refused too. Each refusal says why, once, in the summary the client prints.
--
-- === How a rig is bent ===
--
-- Every bend is about the ANIMAL'S OWN AXES -- ACROSS it (X), UP (Y), FORWARD out of its nose
-- (-Z, the part's LookVector) -- turned into each bone's rest frame. How a bone's own axes come
-- out of Blender, the FBX and the importer is never assumed. The rest frames are worked out once
-- from the bones' own CFrames, parent to child, and never read back from anything the engine
-- updates while it animates.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SeaRig = {}

SeaRig.ACROSS = Vector3.xAxis
SeaRig.UP = Vector3.yAxis
SeaRig.FORWARD = -Vector3.zAxis

export type Rig = { model: Instance, part: MeshPart, bones: { [string]: Bone }, rest: { [Bone]: CFrame } }
export type Chain = { bones: { Bone }, heads: { Vector3 }, tails: { Vector3 }, base: CFrame }

local function numbered(prefix: string, count: number): { string }
	local names = {}
	for index = 1, count do
		table.insert(names, prefix .. index)
	end
	return names
end
SeaRig.numbered = numbered

-- What each one measures as the generators build it, in Roblox axes (gen_sealife.py and
-- gen_ferris.py print the same numbers).
SeaRig.SIZE = {
	Sea_Shark = Vector3.new(6.4, 6.4, 15.6),
	Sea_Dolphin = Vector3.new(4, 4, 9.2),
	Sea_Grouper = Vector3.new(4.4, 4.4, 8.8),
	Sea_Eel = Vector3.new(2.8, 2.8, 13.2),
	Sea_Fish = Vector3.new(1.2, 1.4, 3.2),
	Sea_FishLarge = Vector3.new(2.4, 2.8, 6.4),
	Sea_Ray = Vector3.new(12.8, 6, 15.2),
	Sea_TurtleShell = Vector3.new(8.4, 3.2, 8.8),
	Sea_Turtle = Vector3.new(8.4, 3.2, 8.8),
	Sea_Jelly = Vector3.new(3.6, 12.8, 3.6),
	Sea_Gull = Vector3.new(8.6, 2, 5.6),
	Sea_GullWings = Vector3.new(8.6, 2, 5.6),
	Sea_Kelp = Vector3.new(10, 95.5, 10),
	Sea_KelpCanopy = Vector3.new(26, 6, 14),
	Sea_Serpent = Vector3.new(18, 22, 220),
	Ferris_Wheel = Vector3.new(14, 74, 74),
	Ferris_Frame = Vector3.new(24, 254, 68),
	Ferris_Gondola = Vector3.new(4.4, 6.6, 4.4),
} :: { [string]: Vector3 }

-- The bones each rigged one has to arrive with.
local spine = numbered("Spine_", 7)
SeaRig.BONES = {
	Sea_Shark = { "Spine_1", "Spine_2", "Spine_3" },
	Sea_Dolphin = { "Spine_1", "Spine_2", "Flukes" },
	Sea_Grouper = { "Spine_1", "Tail" },
	Sea_Eel = spine,
	Sea_Fish = { "Tail" },
	Sea_FishLarge = { "Tail" },
	Sea_Ray = { "Wing_L1", "Wing_L2", "Wing_R1", "Wing_R2", "Tail" },
	Sea_Turtle = { "Head", "Flipper_FL", "Flipper_FR", "Flipper_BL", "Flipper_BR" },
	Sea_Jelly = { "Rim_1", "Rim_2", "Rim_3", "Rim_4", "Arm_1", "Arm_2", "Arm_3", "Arm_4",
		"ArmTip_1", "ArmTip_2", "ArmTip_3", "ArmTip_4" },
	Sea_GullWings = { "Wing_L1", "Wing_L2", "Wing_R1", "Wing_R2" },
	Sea_Kelp = numbered("Kelp_", 12),
	Sea_KelpCanopy = numbered("Frond_", 4),
	Sea_Serpent = numbered("Spine_", 18),
} :: { [string]: { string } }

local templates: { [string]: Instance | false } = {}
local notes: { [string]: string } = {}

-- The imported mesh called `name`, checked, or nil. Looked up once.
function SeaRig.template(name: string): Instance?
	local known = templates[name]
	if known ~= nil then
		return if known then known else nil
	end
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("TileMeshes")
	local found = folder and folder:FindFirstChild(name)
	-- The importer usually wraps a mesh in a Model; reach through it, as ChunkBuilder does.
	local part = if found and found:IsA("MeshPart") then found elseif found then found:FindFirstChildWhichIsA("MeshPart", true) else nil
	local why: string? = nil
	if not part then
		why = "not imported"
	else
		local want, got = SeaRig.SIZE[name], part.Size
		if want and (math.abs(got.X - want.X) > want.X * 0.15 or math.abs(got.Y - want.Y) > want.Y * 0.15
			or math.abs(got.Z - want.Z) > want.Z * 0.15) then
			why = ("imported at %.1f x %.1f x %.1f, built %.1f x %.1f x %.1f: an old or rescaled import"):format(
				got.X, got.Y, got.Z, want.X, want.Y, want.Z)
		else
			local have: { [string]: boolean } = {}
			for _, item in ipairs(part:GetDescendants()) do
				if item:IsA("Bone") then
					have[item.Name] = true
				end
			end
			for _, bone in ipairs(SeaRig.BONES[name] or {}) do
				if not have[bone] then
					why = "imported without its bone " .. bone .. " (import the FBX with its rig)"
					break
				end
			end
		end
	end
	templates[name] = if why then false else (found :: Instance)
	notes[name] = why or "drawn"
	return if why then nil else found
end

-- A copy of the mesh in `holder`, anchored and out of everyone's way, or nil if it is not there.
function SeaRig.place(holder: Instance, name: string, colour: Color3?): Rig?
	local template = SeaRig.template(name)
	if not template then
		return nil
	end
	local copy = template:Clone()
	local part = (if copy:IsA("MeshPart") then copy else copy:FindFirstChildWhichIsA("MeshPart", true)) :: MeshPart?
	if not part then
		copy:Destroy()
		return nil
	end
	local everything = copy:GetDescendants()
	table.insert(everything, copy)
	for _, item in ipairs(everything) do
		if item:IsA("BasePart") then
			item.Anchored = true
			item.CanCollide = false
			item.CanTouch = false
			item.CanQuery = false
			item.CastShadow = false
			if item ~= part then
				item.Transparency = 1
			end
		end
	end
	part.Name = name
	if colour then
		part.Color = colour
		part.Material = Enum.Material.SmoothPlastic
	end
	local bones: { [string]: Bone } = {}
	local rest: { [Bone]: CFrame } = {}
	local function restOf(bone: Bone): CFrame
		local known = rest[bone]
		if known then
			return known
		end
		local parent = bone.Parent
		local frame = (if parent and parent:IsA("Bone") then restOf(parent) else CFrame.identity) * bone.CFrame
		rest[bone] = frame
		return frame
	end
	for _, item in ipairs(part:GetDescendants()) do
		if item:IsA("Bone") then
			bones[item.Name] = item
			restOf(item)
		end
	end
	copy.Parent = holder
	return { model = copy, part = part, bones = bones, rest = rest }
end

-- Turns one bone by `angle` about `axis` (the animal's own), from its rest pose.
function SeaRig.bend(rig: Rig, name: string, axis: Vector3, angle: number)
	local bone = rig.bones[name]
	if bone then
		bone.Transform = CFrame.fromAxisAngle(rig.rest[bone]:VectorToObjectSpace(axis), angle)
	end
end

-- The same about two axes at once, the first applied first: a flipper that rows AND flaps.
function SeaRig.bend2(rig: Rig, name: string, axisA: Vector3, angleA: number, axisB: Vector3, angleB: number)
	local bone = rig.bones[name]
	if bone then
		local rest = rig.rest[bone]
		bone.Transform = CFrame.fromAxisAngle(rest:VectorToObjectSpace(axisB), angleB)
			* CFrame.fromAxisAngle(rest:VectorToObjectSpace(axisA), angleA)
	end
end

-- A chain of bones laid head to tail (the kelp's stipe, a frond), for `follow`. The last bone's
-- tail is where the chain would go on to at the same spacing.
function SeaRig.chain(rig: Rig, names: { string }): Chain?
	local bones, heads = {}, {}
	for index, name in ipairs(names) do
		local bone = rig.bones[name]
		if not bone then
			return nil
		end
		bones[index] = bone
		heads[index] = rig.rest[bone].Position
	end
	if #bones < 2 then
		return nil
	end
	local tails = {}
	for index = 1, #bones do
		tails[index] = if index < #bones then heads[index + 1] else heads[index] + (heads[index] - heads[index - 1])
	end
	local parent = bones[1].Parent
	return { bones = bones, heads = heads, tails = tails,
		base = if parent and parent:IsA("Bone") then rig.rest[parent] else CFrame.identity }
end

-- The shortest turn taking direction `a` onto `b`. Where they point nearly opposite ways the
-- shortest turn is any half-turn at all, and the axis a cross product picks is noise -- so it is a
-- half-turn about UP when `a` lies level (a body turning round stays the right way up) and about
-- ACROSS when it does not.
local function shortest(a: Vector3, b: Vector3): CFrame
	local axis = a:Cross(b)
	local sin, cos = axis.Magnitude, a:Dot(b)
	if sin > 1e-4 then
		return CFrame.fromAxisAngle(axis / sin, math.atan2(sin, cos))
	elseif cos > 0 then
		return CFrame.identity
	end
	local level = math.abs(a.Y) < 0.9
	return CFrame.fromAxisAngle(if level then Vector3.yAxis else Vector3.xAxis, math.pi)
end

-- The same, KEEPING UP UP: the heading first, a turn about UP, and then only the rise or fall in
-- the vertical plane that is left. A long body lying level -- the thing under the route -- has to
-- turn right round where it doubles back at the end of its patrol, and the shortest turn there
-- rolls it onto its back.
local function upright(a: Vector3, b: Vector3): CFrame
	local ah, bh = Vector3.new(a.X, 0, a.Z), Vector3.new(b.X, 0, b.Z)
	if ah.Magnitude < 1e-4 or bh.Magnitude < 1e-4 then
		return shortest(a, b)
	end
	ah, bh = ah.Unit, bh.Unit
	local yaw = CFrame.fromAxisAngle(Vector3.yAxis, math.atan2(ah:Cross(bh).Y, ah:Dot(bh)))
	return shortest(yaw:VectorToWorldSpace(a), b) * yaw
end

-- Poses a chain so each bone runs from one joint to the next: `joints[1]` is where the first
-- bone's head goes and `joints[i + 1]` where bone i ends, in the part's own space. Each bone is
-- turned from its rest direction onto its joint-to-joint one (the shortest way, or `level`, keeping
-- up up) and moved so its head is on its joint -- which is also what stretches a chain to a strand
-- of another height. `posed`, if given, gets each bone's posed frame in the part's space. Returns
-- how the last bone has moved from its rest frame, for whatever it carries on its end.
function SeaRig.follow(chain: Chain, rest: { [Bone]: CFrame }, joints: { Vector3 }, level: boolean?,
	posed: { CFrame }?): CFrame
	local above = chain.base
	local frame = CFrame.identity
	for index, bone in ipairs(chain.bones) do
		local from = chain.tails[index] - chain.heads[index]
		local to = joints[index + 1] - joints[index]
		local turn = CFrame.identity
		if from.Magnitude > 1e-4 and to.Magnitude > 1e-4 then
			turn = if level then upright(from.Unit, to.Unit) else shortest(from.Unit, to.Unit)
		end
		frame = CFrame.new(joints[index]) * turn * rest[bone].Rotation
		bone.Transform = (above * bone.CFrame):Inverse() * frame
		above = frame
		if posed then
			posed[index] = frame
		end
	end
	return frame * rest[chain.bones[#chain.bones]]:Inverse()
end

-- One line: which meshes are drawn, and why any are not.
function SeaRig.summary(): string
	local drawn, missing, wrong = 0, {}, {}
	for name, note in pairs(notes) do
		if note == "drawn" then
			drawn += 1
		elseif note == "not imported" then
			table.insert(missing, name)
		else
			table.insert(wrong, name .. " " .. note)
		end
	end
	table.sort(missing)
	table.sort(wrong)
	local line = ("%d meshes drawn"):format(drawn)
	if #missing > 0 then
		line ..= "; part-built because not imported: " .. table.concat(missing, ", ")
	end
	if #wrong > 0 then
		line ..= "; REFUSED: " .. table.concat(wrong, "; ")
	end
	return line
end

return SeaRig
