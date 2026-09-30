--!strict
-- ServerScriptService/Services/Interactables.lua
-- THINGS YOU CAN PUT YOUR HANDS ON, and the secrets they keep. What the story leaves lying about, as
-- objects rather than words on a screen: environmental storytelling, a layer at a time (LORE.md, "How
-- the story is told"). A leaf module: StoryService builds with it, and nothing here needs StoryService.
--
--   take()          into your JOURNAL: what a note, a letter, a keepsake or a secret says goes into the
--                   book you carry (JournalService, on your screen), with a small line in the corner to
--                   say so. Nothing is put in front of you: you read it when you choose to (J).
--   letter()        a letter lying on the ground, a stone on it so it does not blow away. Take it (E).
--   keepsake()      A KEEPSAKE, as a thing you can see and pick up: the squeeze toy, the jar of honey,
--                   Dev's parcel, sitting where somebody put it down (StoryService puts them in the
--                   nooks off the route). Pick it up (E) and it is in your journal.
--   pryBar()        MR BARLOW'S PRY BAR, lying somewhere on every level. Take it (E) and it goes on
--                   your back for the rest of the session: some things only open to it.
--   locker()        a tall steel locker; lockbox(): a small box with a lid. Open (E), unless it is
--                   rusted shut and wants the bar.
--   looseBricks()   a patch of bricks in a wall that are not quite like the rest; the bar has them out.
--   loosePlank()    a board in a floor that somebody has been lifting; the bar has it up.
--   reveal()        a SECRET: the first time someone opens it, a short scene on their screen (the
--                   camera moving in on what they have found, its name and a line under it:
--                   StoryClient), a card "Secret 2 of 5", and what it says goes into the journal.
--
-- Everything here is anchored or welded to something that is, stands on what it stands on, and
-- changes for everyone when it opens: a door somebody has opened is open. What you pick up is gone
-- from YOUR screen only (JournalService hides it), so the next player can still find it.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local Interactables = {}

-- What each keepsake is (ReplicatedStorage.Shared.Keepsakes): looked for, not waited on forever.
local keepsakeData: { [string]: any } = (function()
	local shared = ReplicatedStorage:FindFirstChild("Shared") or ReplicatedStorage:WaitForChild("Shared", 10)
	local module = shared and shared:FindFirstChild("Keepsakes")
	if module and module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok and typeof(result) == "table" then
			return result
		end
	end
	return {}
end)()

export type Note = { title: string, body: string }
export type Secret = { order: number, title: string, line: string, note: Note? }

-- ===== THE SECRETS =====
--
-- One or more a level, in the order a player would come to them. No dashes in anything read.
Interactables.SECRETS = {
	siren = { order = 1, title = "The Siren Room", line = "Somebody has been sounding it every midnight.", note = {
		title = "Behind the bricks",
		body = "TO WHOEVER HOLDS THE KEY NEXT.\n\nThe siren is tested at twelve noon, every day, and has been since 1911. "
			.. "On the eleventh I sounded it at midnight, because the water was coming, and nobody came.\n\nI have sounded it "
			.. "every midnight since. I do not know how many midnights that is.\n\nIf you can read this it is still morning up "
			.. "here and still midnight down there. Go down. It is the only way on.\n\nR. Pell, Siren Keeper",
	} },
	photograph = { order = 2, title = "At the bottom of the pool", line = "Somebody put it where nobody would look.", note = {
		title = "A photograph",
		body = "Dry, inside the box. Tobi and Pip on the Front, a sandcastle between them, both squinting into the sun. "
			.. "Stamped on the back: 13 AUGUST.\n\nUnder it, in pencil:\n\nFor the key holder. So you know what you are "
			.. "opening the gates for.",
	} },
	marsh = { order = 3, title = "Staff locker, aquarium", line = "It has not been opened since 1979.", note = {
		title = "A letter in the locker",
		body = "A peaked cap, a torch that still works, and this.\n\nE. MARSH, OUTFALL 3.\n\nI waited for somebody to come and "
			.. "help. I waited so long I forgot what I looked like.\n\nDo not wait. Nobody comes. You are the one who comes.",
	} },
	locker = { order = 4, title = "Locker 3", line = "Yours. You knew which one before you looked.", note = {
		title = "Locker 3",
		body = "Your coat, on the hook, still wet. Your Waterworks card: KEY HOLDER, OUTFALL 3, %s.\n\nIn the pocket, a note in "
			.. "your own handwriting:\n\nI'll go in tomorrow.",
	} },
	boards = { order = 5, title = "Under the boards", line = "Something down there is breathing." },
}
local TOTAL = 5

local found: { [Player]: { [string]: boolean } } = {}
local holding: { [Player]: boolean } = {}

local function storyRemote(): RemoteEvent?
	local folder = ReplicatedStorage:FindFirstChild("RemoteEvents")
	local event = folder and folder:FindFirstChild("StoryMoment")
	return if event and event:IsA("RemoteEvent") then event else nil
end

-- A part that is part of something: anchored, and not in anyone's way unless `solid`.
local function piece(parent: Instance, name: string, size: Vector3, cf: CFrame, colour: Color3, material: Enum.Material,
	solid: boolean?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	if shape then
		p.Shape = shape
	end
	p.Size = size
	p.CFrame = cf
	p.Color = colour
	p.Material = material
	p.Anchored = true
	p.CanCollide = solid == true
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end
Interactables.piece = piece

local function prompt(host: Instance, action: string, object: string, key: Enum.KeyCode?, hold: number?): ProximityPrompt
	local p = Instance.new("ProximityPrompt")
	p.ActionText = action
	p.ObjectText = object
	p.HoldDuration = hold or 0
	p.MaxActivationDistance = 9
	p.RequiresLineOfSight = false
	p.KeyboardKeyCode = key or Enum.KeyCode.E
	p.Parent = host
	return p
end

-- A line on one player's screen for a few seconds: "It won't give."
function Interactables.whisper(player: Player, text: string)
	local remote = storyRemote()
	if remote then
		remote:FireClient(player, "whisper", text)
	end
end

-- ===== INTO THE JOURNAL =====
--
-- A NOTE USED TO GO STRAIGHT ONTO YOUR SCREEN, over the level, until R put it down, and it was
-- reported as too much: notes came up every few chunks, and after a secret's scene R did not put the
-- sheet down at all (the scene had the controls when the key was pressed). Now nothing is put in front
-- of you. What you take goes into your journal, a line in the corner says so, and you read it when you
-- choose to (JournalService: J, or the book at the top right).
local taken: { [Player]: { [string]: boolean } } = {}

-- `entry` into `player`'s journal as a `kind` ("note", "keepsake", "secret"); `%s` in it is their own
-- name. `object` is the thing they picked up, which their own screen then stops drawing. `extra` goes
-- along as it is (a keepsake's number, a secret's order). `quiet`: no line in the corner (a secret has
-- its own card).
function Interactables.take(player: Player, entry: Note, object: Instance?, kind: string?, extra: { [string]: any }?,
	quiet: boolean?)
	local sort = kind or "note"
	local id = sort .. ":" .. entry.title
	local mine = taken[player] or {}
	taken[player] = mine
	local again = mine[id] == true
	mine[id] = true
	local remote = storyRemote()
	if not remote then
		return
	end
	local name = string.upper(player.DisplayName)
	local data: { [string]: any } = { id = id, kind = sort, title = entry.title, body = (entry.body:gsub("%%s", name)),
		object = object, again = again, quiet = quiet == true }
	if extra then
		for key, value in pairs(extra) do
			data[key] = value
		end
	end
	remote:FireClient(player, "journal", data)
end

Players.PlayerRemoving:Connect(function(player: Player)
	taken[player] = nil
	found[player] = nil
	holding[player] = nil
end)

-- A letter on the ground at `cf` (its face up), a stone holding one corner down.
function Interactables.letter(parent: Instance, cf: CFrame, entry: Note)
	local sheet = piece(parent, "Letter", Vector3.new(1.6, 0.04, 2.1), cf * CFrame.new(0, 0.02, 0) * CFrame.Angles(0, 0.3, 0),
		Color3.fromRGB(236, 228, 206), Enum.Material.SmoothPlastic)
	local ink = Instance.new("SurfaceGui")
	ink.Face = Enum.NormalId.Top
	ink.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	ink.PixelsPerStud = 50
	ink.Parent = sheet
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.TextScaled = true
	text.Font = Enum.Font.Garamond
	text.TextColor3 = Color3.fromRGB(70, 60, 50)
	text.Text = entry.title
	text.Parent = ink
	piece(parent, "Stone", Vector3.new(0.5, 0.35, 0.45), sheet.CFrame * CFrame.new(0.55, 0.19, 0.8) * CFrame.Angles(0, 0.7, 0),
		Color3.fromRGB(110, 108, 102), Enum.Material.Slate)
	-- Taken, not read on the spot: the sheet goes into the journal and off your screen; the stone stays.
	local p = prompt(sheet, "Take", entry.title)
	p.Triggered:Connect(function(player: Player)
		Interactables.take(player, entry, sheet, "note")
	end)
	return sheet
end

-- A LITTLE GLINT on something worth walking over to: a few sparkles a second, and a small warm light
-- (a real one, and small) so it catches the eye from the route without shouting.
function Interactables.glint(host: BasePart, colour: Color3?)
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Name = "Glint"
	sparkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkle.Color = ColorSequence.new(colour or Color3.fromRGB(255, 240, 200))
	sparkle.LightEmission = 0.7
	sparkle.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 0.32),
		NumberSequenceKeypoint.new(1, 0) })
	sparkle.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	sparkle.Lifetime = NumberRange.new(0.8, 1.4)
	sparkle.Speed = NumberRange.new(0.3, 0.9)
	sparkle.SpreadAngle = Vector2.new(180, 180)
	sparkle.Rate = 2.5
	sparkle.Parent = host
	local light = Instance.new("PointLight")
	light.Name = "GlintLight"
	light.Color = colour or Color3.fromRGB(255, 226, 170)
	light.Brightness = 0.55
	light.Range = 7
	light.Shadows = false
	light.Parent = host
end

-- ===== THE KEEPSAKES, AS THINGS =====
--
-- Every keepsake used to be a card that came up the first time you stepped on its material, with
-- nothing in the level to show for it: a squeeze toy you were told about and never saw. Now each is an
-- object somebody put down (StoryService leaves a few in the nooks off the route): made of a few
-- parts, in the material's own colour, sitting on something, with a glint. Pick it up and it is in
-- your journal.
--
-- A shape for each material, from a handful of pieces: { shape, size, offset from the base, colour
-- (nil for the material's own), material, transparency }. Anything not listed is a jar.
type Piece = { any }
local TOYS: { [string]: { Piece } } = {
	Needoh = {
		{ "Ball", Vector3.new(1.3, 1.1, 1.3), Vector3.new(0, 0.55, 0), nil, Enum.Material.SmoothPlastic, 0 },
		{ "Ball", Vector3.new(0.5, 0.35, 0.5), Vector3.new(0.3, 1.05, 0.1), nil, Enum.Material.SmoothPlastic, 0.2 },
	},
	Honey = {
		{ "Cylinder", Vector3.new(1.1, 0.9, 0.9), Vector3.new(0, 0.55, 0), nil, Enum.Material.Glass, 0.25 },
		{ "Cylinder", Vector3.new(0.2, 0.95, 0.95), Vector3.new(0, 1.2, 0), Color3.fromRGB(196, 150, 70), Enum.Material.Fabric, 0 },
		{ "Block", Vector3.new(0.6, 0.5, 0.05), Vector3.new(0, 0.55, -0.46), Color3.fromRGB(240, 228, 196), Enum.Material.SmoothPlastic, 0 },
	},
	BubbleWrap = {
		{ "Block", Vector3.new(1.6, 0.9, 1.2), Vector3.new(0, 0.45, 0), Color3.fromRGB(196, 160, 116), Enum.Material.Cardboard, 0 },
		{ "Block", Vector3.new(1.7, 0.2, 1.3), Vector3.new(0, 0.95, 0), nil, Enum.Material.Glass, 0.45 },
		{ "Block", Vector3.new(0.08, 0.95, 1.25), Vector3.new(0, 0.5, 0), Color3.fromRGB(236, 222, 190), Enum.Material.Fabric, 0 },
	},
	Slime = {
		{ "Cylinder", Vector3.new(0.9, 1, 1), Vector3.new(0, 0.45, 0), Color3.fromRGB(180, 186, 190), Enum.Material.Metal, 0 },
		{ "Ball", Vector3.new(0.9, 0.5, 0.9), Vector3.new(0, 1, 0), nil, Enum.Material.Glass, 0.15 },
	},
	Soap = {
		{ "Block", Vector3.new(1.4, 0.55, 0.9), Vector3.new(0, 0.28, 0), nil, Enum.Material.SmoothPlastic, 0 },
	},
	KineticSand = {
		{ "Cylinder", Vector3.new(1, 1, 1), Vector3.new(0, 0.5, 0), Color3.fromRGB(230, 70, 60), Enum.Material.SmoothPlastic, 0 },
		{ "Cylinder", Vector3.new(0.12, 0.9, 0.9), Vector3.new(0, 1.02, 0), nil, Enum.Material.Sand, 0 },
	},
	ButterWax = {
		{ "Cylinder", Vector3.new(1.5, 0.45, 0.45), Vector3.new(0, 0.75, 0), nil, Enum.Material.SmoothPlastic, 0 },
		{ "Block", Vector3.new(0.06, 0.3, 0.06), Vector3.new(0, 1.63, 0), Color3.fromRGB(40, 34, 30), Enum.Material.Fabric, 0 },
	},
	Lego = {
		{ "Block", Vector3.new(1.6, 0.6, 0.8), Vector3.new(0, 0.3, 0), nil, Enum.Material.SmoothPlastic, 0 },
		{ "Cylinder", Vector3.new(0.2, 0.34, 0.34), Vector3.new(-0.4, 0.7, 0), nil, Enum.Material.SmoothPlastic, 0 },
		{ "Cylinder", Vector3.new(0.2, 0.34, 0.34), Vector3.new(0.4, 0.7, 0), nil, Enum.Material.SmoothPlastic, 0 },
	},
	Chocolate = {
		{ "Block", Vector3.new(1.6, 0.18, 0.8), Vector3.new(0, 0.09, 0), nil, Enum.Material.SmoothPlastic, 0 },
		{ "Block", Vector3.new(1.0, 0.2, 0.84), Vector3.new(0.3, 0.12, 0), Color3.fromRGB(196, 60, 60), Enum.Material.Foil, 0 },
	},
	Ice = {
		{ "Block", Vector3.new(1.1, 1.1, 1.1), Vector3.new(0, 0.55, 0), nil, Enum.Material.Glass, 0.3 },
	},
	Snow = {
		{ "Ball", Vector3.new(1.1, 1.1, 1.1), Vector3.new(0, 0.55, 0), nil, Enum.Material.Snow, 0 },
	},
	Foam = {
		{ "Block", Vector3.new(1.8, 0.4, 1.2), Vector3.new(0, 0.2, 0), nil, Enum.Material.Fabric, 0 },
		{ "Block", Vector3.new(0.7, 0.2, 1.0), Vector3.new(-0.45, 0.5, 0), Color3.fromRGB(246, 246, 240), Enum.Material.Fabric, 0 },
	},
	Cloud = {
		{ "Block", Vector3.new(1.4, 0.5, 1), Vector3.new(0, 0.25, 0), Color3.fromRGB(246, 248, 252), Enum.Material.Fabric, 0 },
		{ "Block", Vector3.new(1.3, 0.4, 0.95), Vector3.new(0, 0.7, 0), Color3.fromRGB(220, 230, 246), Enum.Material.Fabric, 0 },
	},
	Charcoal = {
		{ "Ball", Vector3.new(1.1, 0.8, 0.9), Vector3.new(0, 0.4, 0), nil, Enum.Material.Slate, 0 },
	},
	Lava = {
		{ "Ball", Vector3.new(1.1, 0.8, 1), Vector3.new(0, 0.4, 0), Color3.fromRGB(60, 40, 36), Enum.Material.Basalt, 0 },
	},
	Clay = {
		{ "Block", Vector3.new(1.4, 0.6, 0.7), Vector3.new(0, 0.3, 0), nil, Enum.Material.Brick, 0 },
	},
	LambsEar = {
		{ "Block", Vector3.new(0.5, 0.06, 1.2), Vector3.new(0, 0.05, 0), nil, Enum.Material.Grass, 0 },
	},
	Jellyfish = {
		{ "Cylinder", Vector3.new(1.3, 1, 1), Vector3.new(0, 0.65, 0), Color3.fromRGB(220, 236, 240), Enum.Material.Glass, 0.55 },
		{ "Ball", Vector3.new(0.6, 0.45, 0.6), Vector3.new(0, 0.8, 0), nil, Enum.Material.Glass, 0.2 },
	},
}

-- THE KEEPSAKE FOR `material`, sitting at `cf` (its base on a floor), for anyone to pick up. Returns the
-- model, or nil if the material has no keepsake.
function Interactables.keepsake(parent: Instance, cf: CFrame, material: string): Model?
	local entry = keepsakeData[material]
	if not entry then
		return nil
	end
	local looks = ReplicatedStorage:FindFirstChild("Shared")
	local appearance = looks and looks:FindFirstChild("MaterialAppearance")
	local own = Color3.fromRGB(220, 200, 170)
	if appearance and appearance:IsA("ModuleScript") then
		local ok, result = pcall(require, appearance)
		local look = ok and typeof(result) == "table" and result.Appearances and result.Appearances[material]
		if look and typeof(look.color) == "Color3" then
			own = look.color
		end
	end
	local model = Instance.new("Model")
	model.Name = "Keepsake_" .. material
	local recipe = TOYS[material] or {
		{ "Cylinder", Vector3.new(1.1, 0.9, 0.9), Vector3.new(0, 0.55, 0), nil, Enum.Material.Glass, 0.3 },
		{ "Cylinder", Vector3.new(0.2, 0.95, 0.95), Vector3.new(0, 1.2, 0), Color3.fromRGB(120, 110, 100), Enum.Material.Metal, 0 },
	}
	local first: BasePart? = nil
	for index, spec in ipairs(recipe) do
		local shape = spec[1] :: string
		local size = spec[2] :: Vector3
		local offset = spec[3] :: Vector3
		-- A cylinder lies along X; stood up here. A "ball" is a sphere mesh on a block, so it can be squashed
		-- (a Ball part is always round).
		local turn = if shape == "Cylinder" then CFrame.Angles(0, 0, math.pi / 2) else CFrame.identity
		local p = piece(model, "Toy" .. index, size, cf * CFrame.new(offset) * turn, (spec[4] :: Color3?) or own,
			spec[5] :: Enum.Material, false, if shape == "Cylinder" then Enum.PartType.Cylinder else nil)
		if shape == "Ball" then
			local round = Instance.new("SpecialMesh")
			round.MeshType = Enum.MeshType.Sphere
			round.Parent = p
		end
		p.Transparency = spec[6] :: number
		first = first or p
	end
	model.Parent = parent
	local host = first :: BasePart
	host.CanQuery = true
	Interactables.glint(host)
	local p = prompt(host, "Pick up", entry.thing)
	p.MaxActivationDistance = 8
	p.Triggered:Connect(function(player: Player)
		Interactables.take(player, { title = entry.thing, body = entry.line }, model, "keepsake",
			{ material = material, from = entry.from })
	end)
	return model
end

-- ===== MR BARLOW'S PRY BAR =====

-- Does `player` have the bar?
function Interactables.hasBar(player: Player): boolean
	return holding[player] == true
end

-- The bar on `character`'s back, across the shoulders.
local function carry(character: Model)
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	if not (torso and torso:IsA("BasePart")) or character:FindFirstChild("PryBarCarried") then
		return
	end
	local bar = Instance.new("Part")
	bar.Name = "PryBarCarried"
	bar.Size = Vector3.new(0.22, 3.4, 0.22)
	bar.Color = Color3.fromRGB(46, 44, 48)
	bar.Material = Enum.Material.Metal
	bar.CanCollide = false
	bar.CanTouch = false
	bar.CanQuery = false
	bar.Massless = true
	bar.CFrame = torso.CFrame * CFrame.new(0, 0, 0.62) * CFrame.Angles(0, 0, math.rad(38))
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = torso
	weld.Part1 = bar
	weld.Parent = bar
	bar.Parent = character
	local claw = bar:Clone()
	claw.Name = "PryBarClaw"
	claw.Size = Vector3.new(0.22, 0.7, 0.22)
	claw.CFrame = bar.CFrame * CFrame.new(0, 1.8, -0.2) * CFrame.Angles(math.rad(-50), 0, 0)
	claw:ClearAllChildren()
	local weld2 = Instance.new("WeldConstraint")
	weld2.Part0 = bar
	weld2.Part1 = claw
	weld2.Parent = claw
	claw.Parent = character
end

-- Something `player` has taken, off their own screen (JournalService hides it there); everyone else
-- still sees it where it was.
function Interactables.hideFor(player: Player, object: Instance)
	local remote = storyRemote()
	if remote then
		remote:FireClient(player, "hide", object)
	end
end

-- The bar, lying at `cf` (on a floor), for anyone to take. It stays for the next player.
function Interactables.pryBar(parent: Instance, cf: CFrame)
	local holder = Instance.new("Model")
	holder.Name = "PryBarLying"
	holder.Parent = parent
	local bar = piece(holder, "PryBar", Vector3.new(3.4, 0.22, 0.22), cf * CFrame.new(0, 0.11, 0) * CFrame.Angles(0, 0.5, 0),
		Color3.fromRGB(46, 44, 48), Enum.Material.Metal)
	piece(holder, "PryBarClaw", Vector3.new(0.7, 0.22, 0.22), bar.CFrame * CFrame.new(1.85, 0.15, 0) * CFrame.Angles(0, 0, math.rad(40)),
		Color3.fromRGB(46, 44, 48), Enum.Material.Metal)
	local tag = piece(holder, "PryBarTag", Vector3.new(0.5, 0.05, 0.3), bar.CFrame * CFrame.new(-1.3, 0.12, 0),
		Color3.fromRGB(196, 160, 84), Enum.Material.Metal)
	tag.Transparency = 0
	-- Something catches the light on it, from the route: the one thing every secret needs.
	Interactables.glint(tag, Color3.fromRGB(255, 226, 170))
	local p = prompt(bar, "Take", "Pry bar")
	p.Triggered:Connect(function(player: Player)
		if holding[player] then
			Interactables.whisper(player, "You already have one. It is the same one.")
			return
		end
		holding[player] = true
		player:SetAttribute("HasPryBar", true)
		local character = player.Character
		if character then
			carry(character)
		end
		player.CharacterAdded:Connect(function(again: Model)
			if holding[player] then
				task.defer(carry, again)
			end
		end)
		Interactables.hideFor(player, holder)
		Interactables.whisper(player, "A pry bar. BARLOW is scratched into the handle. Some things here only open to it.")
	end)
end

-- ===== OPENING THINGS =====

-- `door` (anchored, with welded fittings) swung about `hinge` by `angle` over `seconds`.
local function swing(door: BasePart, hinge: CFrame, angle: number, seconds: number)
	local rel = hinge:ToObjectSpace(door.CFrame)
	local turn = Instance.new("NumberValue")
	turn.Changed:Connect(function(value: number)
		door.CFrame = hinge * CFrame.Angles(0, value, 0) * rel
	end)
	local tween = TweenService:Create(turn, TweenInfo.new(seconds, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Value = angle })
	tween:Play()
	tween.Completed:Connect(function()
		turn:Destroy()
	end)
end

-- The first opening, and anyone's look after it: the secret's scene on their screen, and what it says
-- into their journal (quietly: the scene ends on its own card, which says where the words went).
function Interactables.reveal(player: Player, id: string, eye: CFrame, focus: Vector3, anchor: BasePart, kind: string?)
	local secret = Interactables.SECRETS[id]
	if not secret then
		return
	end
	local mine = found[player] or {}
	found[player] = mine
	mine[id] = true
	local count = 0
	for _ in pairs(mine) do
		count += 1
	end
	local remote = storyRemote()
	if remote then
		remote:FireClient(player, kind or "moment", {
			id = id, title = secret.title, line = secret.line, eye = eye, focus = focus, index = secret.order,
			found = count, total = TOTAL,
		})
	end
	local note = secret.note or { title = secret.title, body = secret.line }
	Interactables.take(player, note, nil, "secret", { secret = secret.title, order = secret.order, total = TOTAL,
		line = secret.line }, true)
end

-- Something that opens: `open(player)` runs once, the first time, and every trigger after that (and
-- the first) is `look(player)`. `needsBar` refuses without the bar, with `refusal`.
type Handlers = { open: (Player) -> (), look: (Player) -> () }
local function openable(host: BasePart, action: string, object: string, needsBar: boolean, refusal: string, on: Handlers)
	local opened = false
	local p = prompt(host, action, object, Enum.KeyCode.E, if needsBar then 0.9 else 0)
	p.Triggered:Connect(function(player: Player)
		if not opened then
			if needsBar and not holding[player] then
				Interactables.whisper(player, refusal)
				return
			end
			opened = true
			p.ActionText = "Look"
			p.HoldDuration = 0
			on.open(player)
			task.delay(1.2, function()
				on.look(player)
			end)
		else
			on.look(player)
		end
	end)
end

-- A staff locker standing on `base` (its floor, front along base's LookVector). `opts.label` is
-- stencilled on the door; `opts.bar` wants the pry bar; `opts.secret` is what is in it.
function Interactables.locker(parent: Instance, base: CFrame, opts: { label: string, bar: boolean?, secret: string?,
	eye: CFrame?, dud: boolean? })
	local steel = Color3.fromRGB(88, 104, 110)
	local body = piece(parent, "Locker", Vector3.new(1.5, 6, 1.4), base * CFrame.new(0, 3, 0), steel, Enum.Material.DiamondPlate, true)
	piece(parent, "LockerBack", Vector3.new(1.3, 5.6, 0.05), base * CFrame.new(0, 3, 0.62), Color3.fromRGB(30, 34, 36),
		Enum.Material.SmoothPlastic)
	local door = piece(parent, "LockerDoor", Vector3.new(1.4, 5.8, 0.1), base * CFrame.new(0, 3, -0.75), steel, Enum.Material.Metal, true)
	for k = 0, 3 do
		local vent = piece(parent, "LockerVent", Vector3.new(0.9, 0.08, 0.04), door.CFrame * CFrame.new(0, 2.2 - k * 0.25, -0.06),
			Color3.fromRGB(30, 34, 36), Enum.Material.SmoothPlastic)
		vent.Anchored = false
		local weld = Instance.new("WeldConstraint")
		weld.Part0, weld.Part1 = door, vent
		weld.Parent = vent
	end
	local plate = piece(parent, "LockerLabel", Vector3.new(0.7, 0.4, 0.04), door.CFrame * CFrame.new(0, 1.2, -0.06),
		Color3.fromRGB(226, 222, 206), Enum.Material.SmoothPlastic)
	plate.Anchored = false
	local plateWeld = Instance.new("WeldConstraint")
	plateWeld.Part0, plateWeld.Part1 = door, plate
	plateWeld.Parent = plate
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 60
	gui.Parent = plate
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.TextScaled = true
	text.Font = Enum.Font.GothamBold
	text.TextColor3 = Color3.fromRGB(40, 44, 46)
	text.Text = opts.label
	text.Parent = gui
	local hinge = base * CFrame.new(-0.7, 3, -0.75)
	local inside = base * CFrame.new(0, 3.4, 0)
	-- The one with something in it catches the light at its label, from along the gallery.
	if opts.secret then
		Interactables.glint(plate, Color3.fromRGB(240, 230, 200))
	end
	openable(door, "Open", "Locker " .. opts.label, opts.bar == true, "It is rusted shut. It would take something to prise it.", {
		open = function()
			swing(door, hinge, -math.rad(105), 0.9)
		end,
		look = function(player: Player)
			if opts.secret then
				Interactables.reveal(player, opts.secret, opts.eye or (base * CFrame.new(1.2, 4.2, -4.5)), inside.Position, body)
			elseif opts.dud then
				Interactables.whisper(player, "Empty. A wire hanger, and the smell of the sea.")
			end
		end,
	})
	return body
end

-- A small tin box with a lid, on `base`, that the bar opens.
function Interactables.lockbox(parent: Instance, base: CFrame, secret: string, eye: CFrame)
	local tin = Color3.fromRGB(96, 110, 104)
	local box = piece(parent, "Lockbox", Vector3.new(2.2, 1.2, 1.5), base * CFrame.new(0, 0.6, 0), tin, Enum.Material.Metal, true)
	local lid = piece(parent, "LockboxLid", Vector3.new(2.25, 0.2, 1.55), base * CFrame.new(0, 1.3, 0), tin, Enum.Material.Metal)
	piece(parent, "LockboxClasp", Vector3.new(0.3, 0.4, 0.08), base * CFrame.new(0, 1.05, -0.78), Color3.fromRGB(196, 160, 84),
		Enum.Material.Metal)
	-- Bubbles off it, a few at a time: what catches the eye of someone swimming over.
	local bubbles = Instance.new("ParticleEmitter")
	bubbles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	bubbles.Color = ColorSequence.new(Color3.fromRGB(220, 244, 240))
	bubbles.Size = NumberSequence.new(0.18)
	bubbles.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	bubbles.Lifetime = NumberRange.new(2, 3.5)
	bubbles.Speed = NumberRange.new(1.5, 3)
	bubbles.EmissionDirection = Enum.NormalId.Top
	bubbles.Rate = 1.5
	bubbles.Parent = lid
	local hinge = base * CFrame.new(0, 1.3, 0.75)
	openable(box, "Prise open", "Tin box", true, "The lid is rusted down. It would take something to prise it.", {
		open = function()
			local rel = hinge:ToObjectSpace(lid.CFrame)
			local turn = Instance.new("NumberValue")
			turn.Changed:Connect(function(value: number)
				lid.CFrame = hinge * CFrame.Angles(value, 0, 0) * rel
			end)
			TweenService:Create(turn, TweenInfo.new(0.8, Enum.EasingStyle.Back), { Value = math.rad(-110) }):Play()
			bubbles.Rate = 30
			task.delay(1.5, function()
				bubbles.Rate = 1
			end)
		end,
		look = function(player: Player)
			Interactables.reveal(player, secret, eye, box.Position, box)
		end,
	})
end

-- A patch of loose bricks in a wall at `face` (its LookVector out of the wall), `size` across; the bar
-- has them out onto the floor, and behind them a dark niche.
function Interactables.looseBricks(parent: Instance, face: CFrame, secret: string, eye: CFrame)
	local cols, rows = 3, 4
	local brick = Vector3.new(1.1, 0.5, 0.6)
	local bricks: { BasePart } = {}
	-- The niche behind them, dark, and in it the folded letter.
	piece(parent, "Niche", Vector3.new(cols * brick.X, rows * brick.Y, 0.2), face * CFrame.new(0, 0, 0.75), Color3.fromRGB(14, 12, 12),
		Enum.Material.SmoothPlastic)
	local paper = piece(parent, "NicheLetter", Vector3.new(0.9, 0.05, 0.6), face * CFrame.new(0, -rows * brick.Y / 2 + 0.05, 0.45),
		Color3.fromRGB(236, 228, 206), Enum.Material.SmoothPlastic)
	for r = 0, rows - 1 do
		for c = 0, cols - 1 do
			local shift = if r % 2 == 1 then 0.25 else 0
			local at = face * CFrame.new((c - (cols - 1) / 2) * brick.X + shift, (r - (rows - 1) / 2) * brick.Y, 0.15)
			local b = piece(parent, "LooseBrick", brick - Vector3.new(0.06, 0.06, 0), at,
				Color3.fromRGB(150 + (r * 7 + c * 13) % 20, 86, 70), Enum.Material.Brick, true)
			table.insert(bricks, b)
		end
	end
	-- Brick dust trickling out of the joints: what makes you look twice at this bit of wall.
	Interactables.glint(bricks[1], Color3.fromRGB(230, 200, 170))
	openable(bricks[1], "Prise out", "Loose bricks", true, "The bricks shift a little. It would take something to prise them.", {
		open = function()
			for index, b in ipairs(bricks) do
				task.delay(index * 0.05, function()
					b.Anchored = false
					b.CanCollide = true
					b.AssemblyLinearVelocity = face.LookVector * math.random(6, 12) + Vector3.new(0, math.random(2, 5), 0)
					Debris:AddItem(b, 20)
				end)
			end
		end,
		look = function(player: Player)
			Interactables.reveal(player, secret, eye, paper.Position, paper)
		end,
	})
end

-- A board in a deck at `base` (on the deck, along its LookVector) that somebody has been lifting. The
-- bar has it up, and under it the dark.
function Interactables.loosePlank(parent: Instance, base: CFrame, secret: string, hole: CFrame)
	local board = piece(parent, "LoosePlank", Vector3.new(1.3, 0.18, 4), base * CFrame.new(0, 0.1, 0), Color3.fromRGB(120, 92, 66),
		Enum.Material.WoodPlanks, true)
	for _, z in ipairs({ -1.7, 1.7 }) do
		local nail = piece(parent, "BentNail", Vector3.new(0.08, 0.3, 0.08), board.CFrame * CFrame.new(0.5, 0.2, z) * CFrame.Angles(0, 0, 0.6),
			Color3.fromRGB(70, 66, 60), Enum.Material.Metal)
		nail.Anchored = false
		local weld = Instance.new("WeldConstraint")
		weld.Part0, weld.Part1 = board, nail
		weld.Parent = nail
	end
	local gap = piece(parent, "Gap", Vector3.new(1.1, 0.05, 3.7), base * CFrame.new(0, 0.02, 0), Color3.fromRGB(2, 2, 3),
		Enum.Material.SmoothPlastic)
	gap.Transparency = 1
	-- A cold draught up between the boards, catching the light: something is down there.
	Interactables.glint(board, Color3.fromRGB(190, 230, 220))
	openable(board, "Prise up", "Loose board", true, "It lifts a little and drops back. It would take something to prise it.", {
		open = function()
			gap.Transparency = 0
			local hinge = base * CFrame.new(0.65, 0.1, 0)
			local rel = hinge:ToObjectSpace(board.CFrame)
			local turn = Instance.new("NumberValue")
			turn.Changed:Connect(function(value: number)
				board.CFrame = hinge * CFrame.Angles(0, 0, value) * rel
			end)
			TweenService:Create(turn, TweenInfo.new(0.7, Enum.EasingStyle.Quad), { Value = math.rad(-150) }):Play()
		end,
		look = function(player: Player)
			Interactables.reveal(player, secret, hole, (hole * CFrame.new(0, 0, -200)).Position, gap, "peek")
		end,
	})
end

return Interactables
