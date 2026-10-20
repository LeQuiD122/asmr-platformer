--!strict
-- StarterPlayerScripts/Services/StepService.lua
-- FOOTPRINTS AND STEP SOUNDS: the shop's Steps and Sounds, for everyone who wears them.
--
-- Every client draws and plays them for every player near it, from what the server wrote on the player
-- (EconomyService: the Footprint and StepSound attributes, set only for what they own and wear). So you
-- see other people's prints and hear their steps, and nobody can wear what they did not buy.
--
-- A STEP is a stride walked on something solid: every STRIDE studs of ground covered at a walk or a run,
-- the foot changes and the ground under it is found with a ray. There a FOOTPRINT is laid flat on the
-- surface, turned the way you are going, and fades (the honey paw slowly, the bubble sole fizzing off
-- fast). A STEP SOUND is a soft sound of the game's own materials now and then as you walk (every few steps,
-- at its own pitch, alongside your ordinary footsteps), and ONLY OFF THE LEVELS: in the lobby and the squish
-- room. On a level the chunks' own sounds are the game, and nothing bought plays over them. Its takes are
-- AudioService's (your recordings and the imported takes), so they are the sounds the chunks make; a gentle
-- built-in stands in where an event has none.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local ShopCatalog = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ShopCatalog")) :: any

local StepService = {}

-- AN ERROR ONCE, NOT EVERY FRAME: the step below runs every frame (or several times a second), and the same
-- failure said every frame buries everything else in Output, the paste check included.
local warnedOnce: { [string]: boolean } = {}
local function warnOnce(text: string)
	if not warnedOnce[text] then
		warnedOnce[text] = true
		warn(text .. " (shown once)")
	end
end
StepService.VERSION = "footprints as things, ninety-seventh pass, 2026-10-18"

local STRIDE = 2.4 -- studs of ground covered between two steps
local NEAR = 150 -- studs: steps further off than this are neither drawn nor heard
local MAX_PRINTS = 90 -- the oldest goes when there are more
local REACH = 6 -- studs below the root a foot can land
local PRINT_SIZE = Vector3.new(1.3, 0.05, 1.6)

-- How long each print lasts, and how it goes.
local PRINT_LIFE: { [string]: number } = { HeartStep = 6, StarStep = 6, HoneyPaw = 10, BubbleSole = 2.6, SlimeStep = 5,
	EmberStep = 5 }

-- THE PACKS: which material takes each one is made of, and how loud. Every pack plays its takes at their own pitch
-- (a little either side, PITCH_SPREAD), never pitched up: a chunk's sound sped up is a squeak, not a chunk.
type Pack = { events: { string }, volume: number }
local PACKS: { [string]: Pack } = {
	Crunchy = { events = { "saltCrunch", "snowPack" }, volume = 0.32 },
	Gloopy = { events = { "honeySquish", "needohSquish", "slimeBoing" }, volume = 0.3 },
	Poppy = { events = { "bubblePop" }, volume = 0.26 },
	Thock = { events = { "keyThock" }, volume = 0.3 },
	Velvet = { events = { "leafBrush", "cloudHush" }, volume = 0.55 },
}
-- Where an event has no takes at all: a soft step of Roblox's own, low. Never an electronic blip.
local FALLBACK = "rbxasset://sounds/action_footsteps_plastic.mp3"
local PITCH_SPREAD = 0.06
-- NOW AND THEN: a pack plays once every EVERY_LOW to EVERY_HIGH steps, not on every one.
local EVERY_LOW, EVERY_HIGH = 3, 5

type Walker = { last: Vector3, travelled: number, foot: number, count: number, nextSound: number }
local walkers: { [Model]: Walker } = {}
local prints: { BasePart } = {}
local folder: Folder? = nil
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true
local takesCache: { [string]: { string } } = {}
local takesAt = -100
local audio: any = nil

-- ===== THE PRINTS =====

local function printFolder(): Folder
	local existing = folder
	if existing and existing.Parent then
		return existing
	end
	local made = Instance.new("Folder")
	made.Name = "StepPrints"
	made.Parent = workspace
	folder = made
	return made
end

local function shape(canvas: Instance, size: UDim2, position: UDim2, colour: Color3, round: boolean, rotation: number?): Frame
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Size = size
	f.Position = position
	f.BackgroundColor3 = colour
	f.BackgroundTransparency = 0.12
	f.BorderSizePixel = 0
	f.Rotation = rotation or 0
	f.Parent = canvas
	local c = Instance.new("UICorner")
	c.CornerRadius = if round then UDim.new(0.5, 0) else UDim.new(0.18, 0)
	c.Parent = f
	if round then
		local square = Instance.new("UIAspectRatioConstraint")
		square.AspectRatio = 1
		square.Parent = f
	end
	return f
end

-- The shape of each print, drawn on the top of a flat part, its top towards the way you are going.
local function drawPrint(canvas: Frame, id: string, colour: Color3, accent: Color3)
	local ink = colour:Lerp(accent, 0.3)
	if id == "HeartStep" then
		shape(canvas, UDim2.fromScale(0.46, 0.46), UDim2.fromScale(0.32, 0.36), ink, true)
		shape(canvas, UDim2.fromScale(0.46, 0.46), UDim2.fromScale(0.68, 0.36), ink, true)
		shape(canvas, UDim2.fromScale(0.5, 0.42), UDim2.fromScale(0.5, 0.56), ink, false, 45)
	elseif id == "StarStep" then
		shape(canvas, UDim2.fromScale(0.56, 0.46), UDim2.fromScale(0.5, 0.5), ink, false, 0)
		shape(canvas, UDim2.fromScale(0.56, 0.46), UDim2.fromScale(0.5, 0.5), ink, false, 45)
		shape(canvas, UDim2.fromScale(0.2, 0.2), UDim2.fromScale(0.5, 0.5), accent, true)
	elseif id == "HoneyPaw" then
		shape(canvas, UDim2.fromScale(0.56, 0.4), UDim2.fromScale(0.5, 0.66), ink, false)
		for k, x in ipairs({ 0.2, 0.4, 0.6, 0.8 }) do
			local y = if k == 1 or k == 4 then 0.36 else 0.24
			shape(canvas, UDim2.fromScale(0.2, 0.2), UDim2.fromScale(x, y), ink, true)
		end
	elseif id == "SlimeStep" then
		-- A blob with two drips running off its heel.
		shape(canvas, UDim2.fromScale(0.62, 0.5), UDim2.fromScale(0.5, 0.4), ink, true)
		shape(canvas, UDim2.fromScale(0.16, 0.3), UDim2.fromScale(0.36, 0.72), ink, false)
		shape(canvas, UDim2.fromScale(0.12, 0.22), UDim2.fromScale(0.62, 0.68), ink, false)
		shape(canvas, UDim2.fromScale(0.14, 0.14), UDim2.fromScale(0.4, 0.32), Color3.new(1, 1, 1), true).BackgroundTransparency = 0.5
	elseif id == "EmberStep" then
		-- A sole glowing hot at its heart, cooling at its edge (lay cools it to ash).
		shape(canvas, UDim2.fromScale(0.56, 0.8), UDim2.fromScale(0.5, 0.5), accent, true).Name = "Edge"
		shape(canvas, UDim2.fromScale(0.34, 0.56), UDim2.fromScale(0.5, 0.5), colour, true).Name = "Heat"
		shape(canvas, UDim2.fromScale(0.16, 0.26), UDim2.fromScale(0.5, 0.48), Color3.fromRGB(255, 226, 150), true).Name = "Core"
	else -- BubbleSole: a ring with a glint
		local ring = shape(canvas, UDim2.fromScale(0.74, 0.74), UDim2.fromScale(0.5, 0.5), accent, true)
		ring.BackgroundTransparency = 1
		local edge = Instance.new("UIStroke")
		edge.Color = accent
		edge.Thickness = 3
		edge.Parent = ring
		shape(canvas, UDim2.fromScale(0.16, 0.16), UDim2.fromScale(0.36, 0.34), Color3.new(1, 1, 1), true)
	end
end

-- A print laid: kept, and the oldest gone once there are more than MAX_PRINTS.
local function keepPrint(part: BasePart)
	table.insert(prints, part)
	while #prints > MAX_PRINTS do
		local oldest = table.remove(prints, 1)
		if oldest then
			oldest:Destroy()
		end
	end
end

-- THE PRINT AS A THING (the ninety-seventh pass): the step's own piece from the shop (ShopCatalog.pieces: a heart, a
-- star, a honey paw, a slime splat, a sole), modelled (ReplicatedStorage.Assets.Cosmetics), pressed into the ground as
-- the foot comes down (from a little wide and high to flush), held, and gone as the flat print went: the honey paw
-- closing up, the bubble sole swelling and fizzing off, the ember cooling to ash. The flat print where the meshes are
-- not imported.
local function meshPrint(id: string, frame: CFrame, life: number): BasePart?
	local look = ShopCatalog.pieces(id)
	local piece = look and look.pieces[1]
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local cosmetics = assets and assets:FindFirstChild("Cosmetics")
	local found = piece and cosmetics and cosmetics:FindFirstChild(piece.mesh)
	local template = if found and found:IsA("MeshPart") then found
		elseif found then found:FindFirstChildWhichIsA("MeshPart", true) else nil
	if not (piece and template) then
		return nil
	end
	local part = (template :: MeshPart):Clone()
	part.Name = "StepPrint"
	local base = part.Size
	local size = base * (piece.size / math.max(base.X, base.Y, base.Z))
	part.Size = size * Vector3.new(1.25, 1, 1.25)
	part.CFrame = frame * CFrame.new(0, size.Y * 0.5 + 0.12, 0)
	part.Color = piece.colours[math.random(1, #piece.colours)]
	part.Material = if piece.material == "Glass" then Enum.Material.Glass else Enum.Material.SmoothPlastic
	part.Transparency = piece.alpha or 0
	part.Reflectance = piece.shine or 0
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Parent = printFolder()
	-- Pressed in: down to flush, and to its size, quickly.
	TweenService:Create(part, TweenInfo.new(0.12, Enum.EasingStyle.Quad), { Size = size,
		CFrame = frame * CFrame.new(0, size.Y * 0.35, 0) }):Play()
	local hold = life * 0.45
	local fade = TweenInfo.new(life - hold, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, hold)
	TweenService:Create(part, fade, { Transparency = 1 }):Play()
	if piece.cool then
		TweenService:Create(part, TweenInfo.new(life * 0.5, Enum.EasingStyle.Sine), { Color = piece.cool }):Play()
	end
	if id == "HoneyPaw" then
		TweenService:Create(part, TweenInfo.new(life, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, 0, false, 0.12),
			{ Size = size * Vector3.new(0.7, 0.6, 0.7) }):Play()
	elseif id == "BubbleSole" then
		TweenService:Create(part, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 0.12),
			{ Size = size * Vector3.new(1.45, 1, 1.45) }):Play()
	end
	return part
end

-- A print at `at` on a surface facing `up`, the toe towards `ahead`.
local function lay(id: string, at: Vector3, up: Vector3, ahead: Vector3)
	local item = ShopCatalog.get(id)
	if not item then
		return
	end
	local forward = ahead - up * ahead:Dot(up)
	if forward.Magnitude < 0.05 then
		return
	end
	forward = forward.Unit
	local right = up:Cross(-forward)
	local life = PRINT_LIFE[id] or 6
	local made = meshPrint(id, CFrame.fromMatrix(at, right, up), life)
	if made then
		game:GetService("Debris"):AddItem(made, life + 0.2)
		keepPrint(made)
		return
	end
	local part = Instance.new("Part")
	part.Name = "StepPrint"
	part.Size = PRINT_SIZE
	part.CFrame = CFrame.fromMatrix(at + up * 0.04, right, up)
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Parent = printFolder()
	local face = Instance.new("SurfaceGui")
	face.Face = Enum.NormalId.Top
	face.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	face.PixelsPerStud = 50
	face.LightInfluence = 1
	face.Parent = part
	local canvas = Instance.new("Frame")
	canvas.BackgroundTransparency = 1
	canvas.Size = UDim2.fromScale(1, 1)
	canvas.Parent = face
	local scale = Instance.new("UIScale")
	scale.Parent = canvas
	drawPrint(canvas, id, item.colour, item.accent)
	-- THE FADE: held, then gone; the honey paw slowly filling in, the bubble sole fizzing off.
	local hold = life * 0.45
	local fade = TweenInfo.new(life - hold, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, hold)
	for _, piece in ipairs(canvas:GetDescendants()) do
		if piece:IsA("Frame") then
			if piece.BackgroundTransparency < 1 then
				TweenService:Create(piece, fade, { BackgroundTransparency = 1 }):Play()
			end
		elseif piece:IsA("UIStroke") then
			TweenService:Create(piece, fade, { Transparency = 1 }):Play()
		end
	end
	if id == "EmberStep" then
		-- Cooling: the heat and the core going to the grey of ash before it fades.
		for _, piece in ipairs(canvas:GetChildren()) do
			if piece:IsA("Frame") and (piece.Name == "Heat" or piece.Name == "Core") then
				TweenService:Create(piece, TweenInfo.new(life * 0.5, Enum.EasingStyle.Sine), { BackgroundColor3 = Color3.fromRGB(96, 88, 86) }):Play()
			end
		end
	end
	if id == "HoneyPaw" then
		TweenService:Create(scale, TweenInfo.new(life, Enum.EasingStyle.Sine), { Scale = 0.7 }):Play()
	elseif id == "BubbleSole" then
		TweenService:Create(scale, TweenInfo.new(life, Enum.EasingStyle.Quad), { Scale = 1.45 }):Play()
	end
	game:GetService("Debris"):AddItem(part, life + 0.2)
	keepPrint(part)
end

-- ===== THE SOUNDS =====

local function takes(pack: Pack): { string }
	-- Looked for again every ten seconds, so takes imported while playing are picked up.
	if os.clock() - takesAt > 10 then
		takesAt = os.clock()
		takesCache = {}
	end
	local key = table.concat(pack.events, ",")
	local cached = takesCache[key]
	if cached then
		return cached
	end
	if audio == nil then
		local module = script.Parent and script.Parent:FindFirstChild("AudioService")
		local ok, loaded = false, nil
		if module and module:IsA("ModuleScript") then
			ok, loaded = pcall(require, module)
		end
		audio = if ok and type(loaded) == "table" then loaded else false
	end
	local found: { string } = {}
	if audio and audio.takesFor then
		for _, event in ipairs(pack.events) do
			for _, id in ipairs(audio.takesFor(event)) do
				table.insert(found, id)
			end
		end
	end
	takesCache[key] = found
	return found
end

local function playStep(id: string, root: BasePart)
	local pack = PACKS[id]
	if not pack then
		return
	end
	local library = takes(pack)
	local s = Instance.new("Sound")
	-- (takes() above has found AudioService.) A take of a sheet plays from its own slot.
	if #library > 0 and audio and audio.applyTake then
		audio.applyTake(s, library[math.random(1, #library)])
	else
		s.SoundId = FALLBACK
	end
	s.PlaybackSpeed = 1 - PITCH_SPREAD + math.random() * PITCH_SPREAD * 2
	s.Name = "PackStep"
	s.Volume = pack.volume
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMaxDistance = 45
	s.Parent = root
	s:Play()
	game:GetService("Debris"):AddItem(s, 3)
end

-- Roblox's own footstep, muted for anyone wearing a pack and given back when they take it off.
local function muteRunning(root: BasePart, muted: boolean)
	local running = root:FindFirstChild("Running")
	if not (running and running:IsA("Sound")) then
		return
	end
	if muted then
		if running.Volume > 0 then
			running:SetAttribute("StepVolume", running.Volume)
			running.Volume = 0
		end
	else
		local was = running:GetAttribute("StepVolume")
		if typeof(was) == "number" and running.Volume == 0 then
			running.Volume = was
			running:SetAttribute("StepVolume", nil)
		end
	end
end

-- ===== EVERY FRAME: who has stepped =====

local function step()
	local me = Players.LocalPlayer.Character
	local myRoot = me and me:FindFirstChild("HumanoidRootPart")
	local camera = workspace.CurrentCamera
	local here = if myRoot and myRoot:IsA("BasePart") then myRoot.Position elseif camera then camera.CFrame.Position else Vector3.zero
	local seen: { [Model]: boolean } = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not (character and root and root:IsA("BasePart")) then
			continue
		end
		local footprint = player:GetAttribute("Footprint")
		local sound = player:GetAttribute("StepSound")
		-- OFF THE LEVELS ONLY (no InLevel: the lobby, the squish room), and alongside Roblox's own footstep, which a
		-- pack no longer silences (given back to anyone it was taken from).
		local wearsSound = typeof(sound) == "string" and PACKS[sound] ~= nil and player:GetAttribute("InLevel") == nil
		muteRunning(root, false)
		if typeof(footprint) ~= "string" and not wearsSound then
			continue
		end
		if (root.Position - here).Magnitude > NEAR then
			continue
		end
		seen[character] = true
		local walker = walkers[character]
		if not walker then
			walker = { last = root.Position, travelled = 0, foot = 1, count = 0, nextSound = math.random(1, EVERY_HIGH) }
			walkers[character] = walker
		end
		local w = walker :: Walker
		local moved = Vector3.new(root.Position.X - w.last.X, 0, root.Position.Z - w.last.Z).Magnitude
		w.last = root.Position
		local v = root.AssemblyLinearVelocity
		local speed = Vector3.new(v.X, 0, v.Z).Magnitude
		-- A WALK OR A RUN on something solid: not standing, not a launch or a teleport, not the air.
		if speed < 2 or speed > 60 or moved > 8 or root.Anchored then
			continue
		end
		w.travelled += moved
		if w.travelled < STRIDE then
			continue
		end
		w.travelled = 0
		w.foot = -w.foot
		rayParams.FilterDescendantsInstances = { character, printFolder() }
		local hit = workspace:Raycast(root.Position, Vector3.new(0, -REACH, 0), rayParams)
		if not hit then
			continue
		end
		if typeof(footprint) == "string" and PRINT_LIFE[footprint] then
			local ahead = Vector3.new(v.X, 0, v.Z)
			local up = hit.Normal
			-- Along the surface the way you are going (nothing on a wall you are running into).
			local flat = ahead - up * ahead:Dot(up)
			if flat.Magnitude > 0.05 then
				local side = up:Cross(-flat.Unit)
				lay(footprint, hit.Position + side * (0.45 * w.foot), up, ahead)
			end
		end
		if wearsSound then
			w.count += 1
			if w.count >= w.nextSound then
				w.count = 0
				w.nextSound = math.random(EVERY_LOW, EVERY_HIGH)
				playStep(sound :: string, root)
			end
		end
	end
	for character in pairs(walkers) do
		if not seen[character] then
			walkers[character] = nil
		end
	end
end

-- ===== THE SHOP'S TRY-ON =====

-- A taste of a print or a pack on your own character: four prints walked out in front of you, or three
-- steps to listen to.
function StepService.preview(item: any)
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart") and type(item) == "table") then
		return
	end
	if item.kind == "steps" and PRINT_LIFE[item.id] then
		local ahead = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
		if ahead.Magnitude < 0.05 then
			ahead = Vector3.new(0, 0, -1)
		end
		ahead = ahead.Unit
		local side = Vector3.yAxis:Cross(-ahead)
		rayParams.FilterDescendantsInstances = { character, printFolder() }
		for k = 1, 4 do
			local from = root.Position + ahead * (1.5 + k * 1.6) + side * (if k % 2 == 0 then 0.45 else -0.45)
			local hit = workspace:Raycast(from, Vector3.new(0, -REACH, 0), rayParams)
			if hit then
				task.delay(k * 0.18, lay, item.id, hit.Position, hit.Normal, ahead)
			end
		end
	elseif item.kind == "sound" and PACKS[item.id] then
		-- Two of them, a little apart, as they come while you walk.
		for k = 0, 1 do
			task.delay(k * 0.9, playStep, item.id, root)
		end
	end
end

function StepService.start()
	RunService.Heartbeat:Connect(function()
		local ok, err = pcall(step)
		if not ok then
			warnOnce("StepService: " .. tostring(err))
		end
	end)
	print("StepService: running, " .. StepService.VERSION)
end

StepService.STAMP = "4c4558b7"
return StepService
