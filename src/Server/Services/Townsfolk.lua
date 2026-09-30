--!strict
-- ServerScriptService/Services/Townsfolk.lua
-- The people of Harrow Bay: the few still here, on every level. Each level's service stands its own
-- when it builds (StoryService for City Shore's, SkyPoolsService, SunkenCityService, DiveFinaleService)
-- and they go with the level. This replaces SunkenNPCs, which was the Sunken City's alone.
--
-- === THE STORY ===
--
-- What the player calls the backrooms is HARROW BAY, a seaside town, on 14 August: the day the sea
-- came in and did not go out. The levels are that one day, later each time, in the order they are
-- numbered:
--
--   LEVEL 1  CITY SHORE          9:14 in the morning. The tide has not gone out in three days.
--   LEVEL 2  THE SKY POOLS       three in the afternoon. The street went under at lunchtime; the
--                                party on the roof has not stopped since.
--   LEVEL 3  THE SUNKEN CITY     eight minutes to midnight. Every clock in town stopped at 11:52.
--   LEVEL 4  THE CORPORATION     four minutes to midnight, under the pumping station, where the
--            BATHS (the Flooded  town's old baths were built to be warmed by its engines. The clocks
--            Halls)              are moving again down here, and at the bottom are the gates.
--
-- The people are living it. To them nothing is strange but the water, and the water is only weather:
-- the tide that has not gone out, the street that went under, the siren the council keeps testing at
-- twelve. They are polite, ordinary and a little stuck, and every one of them half recognises you.
--
-- Because you are the KEY HOLDER: the one on call at the Harrow Bay Waterworks that day, with the only
-- key to the gates at OUTFALL 3, who took it home the night before and never came in. Everyone is
-- waiting on you. Tobi Okafor went down in the morning to find you; by three his wife is still keeping
-- his seat at the pools and his daughter Pip is still building her sandcastle on the front; by
-- midnight the fisherman has watched a lot of people go down the harbour drain looking for you, and
-- none came back up. They are in the baths, still looking. The drain takes you down Outfall 3 to the
-- pumping station, where your name is on the time card, not clocked in (SunkenCityService); the baths
-- under it take you down the flume to the gates, where the key is in your pocket after all
-- (FloodedHallsService). You open them. The tide goes out. And it is 9:14 in the morning again.
--
-- Nobody says any of that outright. It comes a line at a time, in the order below, from people who
-- think it is an ordinary day. The one who comes closest is Mrs Venn at the baths, who knows what the
-- people from up there call this place: to her it is the back rooms of the baths. Staff only.
--
-- THE HOLD is the old-timers' word for it (Mr Wick, Mrs Venn, Mr Barlow): the water held behind the
-- gates, and the day held with it. The Hold keeps whatever anyone was holding when the water came, and
-- that is what the levels are built of (ReplicatedStorage.Shared.Keepsakes: every material is somebody's
-- soap, sand, parcel or honey). The faceless WATCHER on the Deco tower is E. MARSH, the key holder before
-- you, who waited too long. Mr Wick held the key before him. LORE.md is the whole of it.
--
-- === Who ===
--
--   CITY SHORE        SAL sells ice cream at the start. PIP OKAFOR, eight, with a bucket, on a
--                     checkpoint. MAREN the lifeguard, on the dive deck.
--   SKY POOLS         DEV hands out towels on the first terrace. MRS OKAFOR (Pip's mum) sits on a
--                     lounger keeping her husband's seat. RUDY plays the same song at the top of the
--                     slide.
--   SUNKEN CITY       THE ATTENDANT in the aquarium, beside the notice asking you not to tap the glass
--                     (and when it goes they run). THE FISHERMAN on a crate on the pier. THE WATCHER,
--                     faceless, on a ledge of the Deco tower, whose head follows you from far away.
--   CORPORATION BATHS MRS VENN, the baths attendant, at the first checkpoint with her ticket desk.
--                     TOBI OKAFOR, Pip's dad, in his trunks with his red towel, halfway, still
--                     looking. MR BARLOW, the night engineer, with his lamp at the flume.
--
-- Each GREETS you with their first line the first time you come near, and after that says the next
-- line each time you talk to them (F). While you are near, they turn their head to you, and they talk
-- with their hands. What they say stays up for twice as long as it used to (READ, below).
--
-- === How, and why nothing has to be done by hand ===
--
-- Each is a real Roblox character, built on the server from a HumanoidDescription
-- (Players:CreateHumanoidModelFromDescription): the default R15 body in the colours given here, with a
-- hat or a rod made of parts. They are POSED BY THEIR JOINTS, not by animations: nothing has to be
-- uploaded and nothing can fail to load. A joint is a Motor6D or, with Roblox's newer avatar joints,
-- an AnimationConstraint; ReplicatedStorage.Shared.Poses finds and turns either kind.
--
-- To give one of them your own look, build the character in Studio (Avatar > Rig Builder, dress it)
-- and put it in ServerStorage.Townsfolk named exactly as the `name` below: that model is used
-- instead of the generated one, posed and placed the same way.
--
-- If the character cannot be built at all, a plain figure of parts stands in, so the level never
-- waits on it.

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

-- The joints (Poses.joints / Poses.turn), looked for with a timeout: without it the people still stand
-- and talk, they just do not move.
local posesModule = game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Poses", 10)
local Poses: any = if posesModule and posesModule:IsA("ModuleScript") then require(posesModule) else nil
if not (Poses and Poses.joints and Poses.turn) then
	warn("Townsfolk: there is no ReplicatedStorage.Shared.Poses, so the people cannot move their joints. Paste "
		.. "src/Shared/Poses.lua in as a ModuleScript named exactly Poses.")
	Poses = nil
end

local Townsfolk = {}

export type Person = { name: string, model: Model, head: BasePart, root: BasePart, joints: { [string]: any },
	lines: { string }, next: number, bubble: BillboardGui?, post: CFrame, lift: number, route: { Vector3 }?,
	busy: boolean, worn: { [string]: { part: BasePart, to: BasePart, offset: CFrame } },
	greeted: { [Player]: boolean }, watch: number, yaw: number, pitch: number, relax: { [string]: CFrame },
	hands: boolean, talking: number }

local living: { [string]: Person } = {}

-- WHAT EACH SAYS, in turn: the first when you first come near, the next each time you talk to them.
-- The story (above) is in the order of these lines, level by level. No double dashes in anything said.
local LINES: { [string]: { string } } = {
	-- LEVEL 1, CITY SHORE, 9:14 in the morning.
	Sal = {
		"Morning! You're my first customer since... well. Since this morning.",
		"Tide's in again. Hasn't gone out in three days. Council says the pump man's on his way.",
		"Backrooms? Never heard it called that, love. It's Harrow Bay. Always has been.",
		"The siren went at twelve yesterday. And the day before. Council says it's only a test.",
		"The key holder? Everyone's asking after him today. Took the key home, they say, and never came in.",
		"Mind the honey on the steps, love. I dropped a jar at twelve past nine and it's been running ever since.",
		"Funny. Every time I look up, the sea's a bit closer.",
	},
	Pip = {
		"Are you the key man? My dad went to find the key man.",
		"My dad's called Tobi. He's got a red towel. He said he'd be back before the siren.",
		"The siren goes at twelve. Then it's twelve again. Then it goes again.",
		"Mum says the water's scared of the gates. Nobody's opened the gates.",
		"If you press the sand it keeps your footprint. Then it forgets. Everything here forgets. Not me.",
		"If you see my dad down there, tell him the sandcastle's still standing.",
	},
	Maren = {
		"You're from the pumping station. You've got the look. You're very late.",
		"The water's deeper than it was yesterday. It's deeper every time I look down.",
		"The gates at Outfall 3. Everyone's waiting on you. Only you've got the key.",
		"When the siren goes at midnight, that's the real one. Be at the gates by then.",
		"The siren's in the tower in the middle there. Mr Pell sounds it every midnight. Nobody's seen him in days.",
		"Go on, then. It's the quickest way down. It's the only way down.",
	},
	-- LEVEL 2, THE SKY POOLS, three in the afternoon.
	Dev = {
		"Welcome to the Sky Pools. Towels are free. Everything's free now.",
		"We came up for the party when the street went under. Nobody's gone down since.",
		"It's three o'clock. It's been three o'clock for a while. Lovely, isn't it?",
		"Some people call this the backrooms. It's a pool bar, mate.",
		"Everything up here's gone soft. Everything's been touched too many times.",
		"You're not on the guest list. You're on the other list. The one down at the pumps.",
	},
	Okafor = {
		"My husband went down to find the man with the keys. He said he'd be back by three.",
		"Is it three yet? It's always nearly three.",
		"You've got his face, you know. The key man's. Have you got the keys, dear?",
		"Our Pip's down on the front with her bucket. She's not frightened of anything.",
		"Tobi took his red towel. He only takes it when he means to go swimming. Down in the old baths.",
		"If you see Tobi down there, tell him I kept his seat.",
	},
	Rudy = {
		"Last song! Same as the first song. Nobody minds.",
		"I've played it four hundred times. The crowd loves it. What crowd?",
		"The slide's the only way off the roof. Everyone takes it in the end.",
		"Down there it's the city. Under the city it's the pumps. Under the pumps... ask the key man.",
		"Tell them we're fine up here. We're always fine up here.",
	},
	-- LEVEL 3, THE SUNKEN CITY, eight minutes to midnight.
	Attendant = {
		"Welcome to the aquarium. Please don't tap on the glass.",
		"We're still open. Technically. The clocks all stopped at eight minutes to midnight.",
		"The fish don't like it when you tap. Neither does whatever comes up to the window.",
		"People come down here looking for the pump man. Outfall 3's under the harbour, if you're him.",
		"The rest of the staff went down to the old Corporation Baths when the water came. Warmest place in town.",
		"The tunnel's safe. The window... just don't tap the window.",
	},
	Fisherman = {
		"Not biting today. Nothing's biting. Something's eating them first.",
		"Used to be a bus stop here. Now it's the best fishing in town.",
		"Lot of folk went down that drain looking for the key man. None of them came back up.",
		"You feel the water go quiet? That's it passing under the street.",
		"The old ones call this the Hold. Water's held behind the gates, and the day's held with it.",
		"Something keeps the bay. Swims under the street at night. It isn't hungry. It's patient.",
		"Held the key myself once, forty years back. Wick, Outfall 3. Gave it back on time, mind.",
		"Don't go near the end of the pier. It pulls. Mind you... it's you it's pulling for, isn't it?",
	},
	-- LEVEL 4, THE CORPORATION BATHS, four minutes to midnight.
	Venn = {
		"Evening, love. Baths close at midnight. They've been closing at midnight for a very long time.",
		"Harrow Bay Corporation Baths. Warmed by the engines of the pumping station, right over our heads.",
		"You call it the backrooms, don't you. They all do, the ones who come down from up there.",
		"It's the back rooms of the baths, dear. Staff only. You're staff, aren't you? You've got the look.",
		"Every bar of soap in the Hold is one of mine. I cut them at nine. They come back uncut at nine.",
		"There's a board by the flume that won't stay down. I don't look under it. I'd advise the same.",
		"A lot of people came down today looking for the key holder. I sold them all a ticket.",
		"Nobody's asked for a refund. Nobody's come back out to ask.",
	},
	Tobi = {
		"Is it three yet? I promised my wife I'd be back by three.",
		"I came down to find the man with the keys. I've been round these halls a hundred times. They're longer every time.",
		"Pip's on the front with her bucket. Tell her the sandcastle has to wait. Tell her I'm nearly there.",
		"You've got his face. The key man's. Oh. Oh, it's you, isn't it.",
		"Go on. Open them. Then we can all go home.",
	},
	Barlow = {
		"There you are. Barlow, night engineer, Harrow Bay Waterworks. I've been on since the eleventh.",
		"I can start the engines. I can't open the gates. Outfall 3 takes the key, and the key goes home with the key holder.",
		"Your card's still in the rack upstairs. Not clocked in. Happens to the best of us.",
		"The Hold keeps whatever anyone was holding when it came. Soap, sand, a parcel, a jar of honey. Mind your feet.",
		"There was a key holder before you. Marsh. He waited too long for someone to come and help. Now he only watches.",
		"The flume takes you all the way down. Mind what's at the bottom. It's not the water.",
		"When they open, the whole bay goes out through them. Then it's morning. Then it's always morning.",
	},
}

-- HOW LONG anything said stays up: twice what a line was first given, so there is time to read it
-- twice and look at who said it.
local READ = 2
-- THE SPEECH BUBBLE'S TEXT: one size for everything anyone says (the longest line, 116 characters,
-- wraps to five lines at it), the bubble no wider than SPEECH_WIDE; a shout's, bigger.
local SPEECH_TEXT = 19
local SHOUT_TEXT = 34
local SPEECH_WIDE = 300

-- WHAT THEY SHOUT when you go: off the board, down the slide.
local SHOUTS: { [string]: { string } } = {
	Maren = { "OPEN THE GATES!", "DON'T COME BACK TILL THEY'RE OPEN!" },
	Rudy = { "SAY HI TO THE CITY!", "SEE YOU AT THE BOTTOM!", "WHEEEE!" },
}

-- What the attendant says when the glass is touched: `tap`, `crack`, `crack2`, `burst` and `mended`.
local REACTIONS: { [string]: { string } } = {
	tap = { "Please don't tap the glass.", "I said please.", "Hey. The glass.", "It says it right there." },
	crack = { "Stop! It's cracking!" },
	crack2 = { "It's leaking! Get back from it!" },
	burst = { "RUN!" },
	mended = { "...I'll get the mop." },
}

-- The joints this poses, by name in an R15 rig.
local JOINTS = { "Neck", "Waist", "LeftShoulder", "RightShoulder", "LeftElbow", "RightElbow", "LeftHip", "RightHip",
	"LeftKnee", "RightKnee", "RightWrist", "LeftWrist" }

-- ===== HOW EACH OF THEM LOOKS =====
--
-- Not a colour for the head and one for the body any more. Each person is dressed limb by limb, so a
-- short sleeve stops at the elbow and trousers reach the shoes; given hair (parts shaped as spheres,
-- round the head's own size), a beard or glasses where they have them; and built to their own
-- proportions (Pip is eight; Mr Barlow is broad). Fabric where they are clothed, skin where they are
-- not. Anything a level puts on them (a sunhat, a whistle, a rod) goes on top of this.
--
--   skin, hair, hairStyle   hairStyle is short, bun, ponytail, bob, afro, receding or none
--   top, sleeves            sleeves are none, short or long; no top is bare shoulders
--   bottom, legs            legs are shorts (bare below the knee), skirt (the same) or long
--   shoes                   nil for bare feet
--   scale                   HumanoidDescription's height, width, depth and head
--   beard, moustache, glasses
--   hands                   false when the level gives them something to hold, so they do not talk
--                           with the hand that is holding it
--   title                   what their Talk prompt calls them
type Look = { skin: Color3, hair: Color3?, hairStyle: string?, top: Color3?, sleeves: string?, bottom: Color3,
	legs: string?, shoes: Color3?, scale: { number }?, beard: Color3?, moustache: Color3?, glasses: boolean?,
	hands: boolean?, title: string? }
local LOOKS: { [string]: Look } = {
	Sal = { skin = Color3.fromRGB(226, 192, 158), hair = Color3.fromRGB(120, 78, 52), hairStyle = "bun",
		top = Color3.fromRGB(236, 120, 150), sleeves = "short", bottom = Color3.fromRGB(70, 74, 96), legs = "long",
		shoes = Color3.fromRGB(246, 242, 236), scale = { 0.97, 1.06, 1.04, 1 }, hands = false },
	Pip = { skin = Color3.fromRGB(150, 104, 74), hair = Color3.fromRGB(38, 26, 20), hairStyle = "ponytail",
		top = Color3.fromRGB(250, 214, 90), sleeves = "short", bottom = Color3.fromRGB(70, 130, 190), legs = "shorts",
		shoes = Color3.fromRGB(230, 70, 60), scale = { 0.72, 0.8, 0.8, 1.12 }, hands = false, title = "Pip" },
	Maren = { skin = Color3.fromRGB(198, 150, 112), hair = Color3.fromRGB(232, 198, 122), hairStyle = "ponytail",
		top = Color3.fromRGB(214, 52, 48), sleeves = "none", bottom = Color3.fromRGB(214, 52, 48), legs = "shorts",
		scale = { 1.04, 1, 1, 1 } },
	Dev = { skin = Color3.fromRGB(226, 192, 158), hair = Color3.fromRGB(62, 44, 34), hairStyle = "short",
		top = Color3.fromRGB(80, 170, 190), sleeves = "short", bottom = Color3.fromRGB(240, 240, 236), legs = "shorts",
		shoes = Color3.fromRGB(60, 62, 70), scale = { 1, 0.95, 0.95, 1 }, hands = false },
	Okafor = { skin = Color3.fromRGB(120, 84, 60), hair = Color3.fromRGB(28, 20, 16), hairStyle = "bob",
		top = Color3.fromRGB(214, 120, 60), sleeves = "none", bottom = Color3.fromRGB(240, 200, 120), legs = "skirt",
		shoes = Color3.fromRGB(196, 150, 96), scale = { 0.96, 1.08, 1.05, 1 }, title = "Mrs Okafor" },
	Rudy = { skin = Color3.fromRGB(110, 76, 56), hair = Color3.fromRGB(24, 18, 14), hairStyle = "afro",
		top = Color3.fromRGB(236, 120, 150), sleeves = "short", bottom = Color3.fromRGB(40, 42, 50), legs = "long",
		shoes = Color3.fromRGB(250, 250, 250), scale = { 1.02, 1.04, 1, 1 } },
	Attendant = { skin = Color3.fromRGB(226, 192, 158), hair = Color3.fromRGB(92, 66, 42), hairStyle = "short",
		top = Color3.fromRGB(34, 46, 80), sleeves = "long", bottom = Color3.fromRGB(34, 46, 80), legs = "long",
		shoes = Color3.fromRGB(20, 20, 24), title = "Aquarium attendant" },
	Fisherman = { skin = Color3.fromRGB(214, 170, 130), beard = Color3.fromRGB(184, 180, 172),
		top = Color3.fromRGB(226, 186, 44), sleeves = "long", bottom = Color3.fromRGB(52, 58, 66), legs = "long",
		shoes = Color3.fromRGB(30, 34, 30), scale = { 1.02, 1.1, 1.06, 1 }, hands = false, title = "Mr Wick" },
	Watcher = { skin = Color3.fromRGB(200, 196, 190), top = Color3.fromRGB(40, 40, 44), sleeves = "long",
		bottom = Color3.fromRGB(40, 40, 44), legs = "long", shoes = Color3.fromRGB(24, 24, 26), hands = false },
	Venn = { skin = Color3.fromRGB(232, 202, 178), hair = Color3.fromRGB(200, 200, 204), hairStyle = "bun",
		top = Color3.fromRGB(116, 138, 108), sleeves = "long", bottom = Color3.fromRGB(70, 70, 82), legs = "skirt",
		shoes = Color3.fromRGB(44, 32, 30), scale = { 0.94, 1.02, 1, 1 }, glasses = true, title = "Mrs Venn" },
	Tobi = { skin = Color3.fromRGB(120, 84, 60), hair = Color3.fromRGB(20, 16, 14), hairStyle = "short",
		moustache = Color3.fromRGB(20, 16, 14), sleeves = "none", bottom = Color3.fromRGB(40, 70, 140), legs = "shorts",
		scale = { 1.04, 1.04, 1, 1 }, hands = false, title = "Tobi Okafor" },
	Barlow = { skin = Color3.fromRGB(214, 170, 140), hair = Color3.fromRGB(150, 150, 152), hairStyle = "receding",
		moustache = Color3.fromRGB(150, 150, 152), top = Color3.fromRGB(62, 82, 112), sleeves = "long",
		bottom = Color3.fromRGB(62, 82, 112), legs = "long", shoes = Color3.fromRGB(42, 34, 30),
		scale = { 1.02, 1.12, 1.08, 1 }, hands = false, title = "Mr Barlow" },
}

local function quiet(model: Model)
	for _, item in ipairs(model:GetDescendants()) do
		if item:IsA("BasePart") then
			item.CanCollide = false
			item.CanTouch = false
			item.Massless = true
		end
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		humanoid.NameDisplayDistance = 0
		humanoid.BreakJointsOnDeath = false
		humanoid.RequiresNeck = false
	end
end

-- A figure of parts, for when a character cannot be built: enough to stand where one was meant to.
local function plainFigure(name: string, colours: { Color3 }): Model
	local model = Instance.new("Model")
	model.Name = name
	local function piece(partName: string, size: Vector3, offset: Vector3, colour: Color3): Part
		local p = Instance.new("Part")
		p.Name = partName
		p.Size = size
		p.CFrame = CFrame.new(offset)
		p.Color = colour
		p.Material = Enum.Material.SmoothPlastic
		p.Anchored = true
		p.Parent = model
		return p
	end
	local root = piece("HumanoidRootPart", Vector3.new(2, 2, 1), Vector3.new(0, 3, 0), colours[2])
	root.Transparency = 1
	piece("Torso", Vector3.new(2, 2, 1), Vector3.new(0, 3, 0), colours[2])
	piece("Head", Vector3.new(1.2, 1.2, 1.2), Vector3.new(0, 4.6, 0), colours[1])
	piece("Legs", Vector3.new(2, 2, 1), Vector3.new(0, 1, 0), colours[3])
	for _, x in ipairs({ -1.5, 1.5 }) do
		piece("Arm", Vector3.new(1, 2, 1), Vector3.new(x, 3, 0), colours[2])
	end
	model.PrimaryPart = root
	return model
end

-- The character: the one in ServerStorage.Townsfolk if there is one (or ServerStorage.SunkenNPCs, the
-- folder's old name), else the default body in `colours` (head and hands, body, legs), else the plain
-- figure.
local function character(name: string, colours: { Color3 }, look: Look?): Model
	local stored = ServerStorage:FindFirstChild("Townsfolk")
	local own = stored and stored:FindFirstChild(name)
	if not own then
		local older = ServerStorage:FindFirstChild("SunkenNPCs")
		own = older and older:FindFirstChild(name)
	end
	if own and own:IsA("Model") then
		return own:Clone()
	end
	local ok, made = pcall(function()
		local desc = Instance.new("HumanoidDescription")
		desc.HeadColor = colours[1]
		desc.LeftArmColor = colours[1]
		desc.RightArmColor = colours[1]
		desc.TorsoColor = colours[2]
		desc.LeftLegColor = colours[3]
		desc.RightLegColor = colours[3]
		local scale = look and look.scale
		if scale then
			desc.HeightScale = scale[1]
			desc.WidthScale = scale[2]
			desc.DepthScale = scale[3]
			desc.HeadScale = scale[4]
		end
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if ok and made then
		made.Name = name
		return made
	end
	warn(("Townsfolk: could not build %s as a character (%s), so a plain figure stands in."):format(name, tostring(made)))
	return plainFigure(name, colours)
end

-- A part of their hair or face, shaped as a sphere round the head's own size: `size` and `at` are in
-- head sizes, from the head's centre, its face toward -Z.
local function feature(model: Model, head: BasePart, name: string, size: Vector3, at: Vector3, colour: Color3,
	meshType: Enum.MeshType?, turned: CFrame?, see: number?)
	local s = head.Size
	local p = Instance.new("Part")
	p.Name = name
	p.Size = Vector3.new(size.X * s.X, size.Y * s.Y, size.Z * s.Z)
	p.Color = colour
	p.Material = if name == "Hair" or name == "Beard" or name == "Moustache" then Enum.Material.Fabric
		else Enum.Material.SmoothPlastic
	p.Transparency = see or 0
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = true
	p.CastShadow = false
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = meshType or Enum.MeshType.Sphere
	mesh.Parent = p
	p.CFrame = head.CFrame * CFrame.new(at.X * s.X, at.Y * s.Y, at.Z * s.Z) * (turned or CFrame.identity)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = head
	weld.Part1 = p
	weld.Parent = p
	p.Parent = model
end

-- Dressed, limb by limb, with hair and a face (LOOKS). Nothing here is needed to stand them up.
local function dress(model: Model, look: Look)
	local bodyColours = model:FindFirstChildOfClass("BodyColors")
	if bodyColours then
		bodyColours:Destroy()
	end
	local function paint(partName: string, colour: Color3?, cloth: boolean)
		local part = model:FindFirstChild(partName)
		if part and part:IsA("BasePart") then
			part.Color = colour or look.skin
			part.Material = if cloth and colour then Enum.Material.Fabric else Enum.Material.SmoothPlastic
		end
	end
	local sleeves = look.sleeves or "short"
	local legs = look.legs or "long"
	paint("Head", look.skin, false)
	paint("UpperTorso", look.top, true)
	paint("LowerTorso", look.bottom, true)
	for _, side in ipairs({ "Left", "Right" }) do
		paint(side .. "UpperArm", if sleeves ~= "none" then look.top else nil, true)
		paint(side .. "LowerArm", if sleeves == "long" then look.top else nil, true)
		paint(side .. "Hand", nil, false)
		paint(side .. "UpperLeg", look.bottom, true)
		paint(side .. "LowerLeg", if legs == "long" then look.bottom else nil, true)
		paint(side .. "Foot", look.shoes, true)
	end
	local head = model:FindFirstChild("Head")
	if not (head and head:IsA("BasePart")) then
		return
	end
	local hair = look.hair
	local style = look.hairStyle or "none"
	if hair then
		if style == "afro" then
			feature(model, head, "Hair", Vector3.new(1.32, 0.98, 1.3), Vector3.new(0, 0.36, 0.08), hair)
		elseif style == "receding" then
			feature(model, head, "Hair", Vector3.new(1.04, 0.52, 0.86), Vector3.new(0, 0.1, 0.2), hair)
		elseif style ~= "none" then
			feature(model, head, "Hair", Vector3.new(1.07, 0.56, 1.09), Vector3.new(0, 0.3, 0.05), hair)
			if style == "bun" then
				feature(model, head, "Hair", Vector3.new(0.42, 0.42, 0.42), Vector3.new(0, 0.46, 0.36), hair)
			elseif style == "ponytail" then
				feature(model, head, "Hair", Vector3.new(0.3, 0.3, 0.3), Vector3.new(0, 0.3, 0.52), hair)
				feature(model, head, "Hair", Vector3.new(0.26, 0.72, 0.26), Vector3.new(0, -0.08, 0.6), hair)
			elseif style == "bob" then
				feature(model, head, "Hair", Vector3.new(1.13, 0.76, 1), Vector3.new(0, 0.04, 0.12), hair)
			end
		end
	end
	if look.beard then
		feature(model, head, "Beard", Vector3.new(0.82, 0.42, 0.34), Vector3.new(0, -0.36, -0.4), look.beard)
	end
	if look.moustache then
		feature(model, head, "Moustache", Vector3.new(0.44, 0.1, 0.12), Vector3.new(0, -0.13, -0.53), look.moustache)
	end
	if look.glasses then
		local frame = Color3.fromRGB(40, 36, 34)
		for _, x in ipairs({ -0.19, 0.19 }) do
			feature(model, head, "Glasses", Vector3.new(0.05, 0.25, 0.25), Vector3.new(x, 0.07, -0.53), frame,
				Enum.MeshType.Cylinder, CFrame.Angles(0, math.pi / 2, 0), 0.25)
		end
		feature(model, head, "Glasses", Vector3.new(0.14, 0.035, 0.035), Vector3.new(0, 0.09, -0.54), frame,
			Enum.MeshType.Brick)
	end
end

-- Turns a joint from its rest by `by`, now or over `seconds`.
local function turn(npc: Person, name: string, by: CFrame, seconds: number?)
	local joint = npc.joints[name]
	if not joint then
		return
	end
	if seconds and seconds > 0 then
		local goal = joint.rest * by
		local target: Instance = joint.motor or joint.attachment
		TweenService:Create(target, TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
			{ [if joint.motor then "C0" else "CFrame"] = goal }):Play()
	else
		Poses.turn(joint, by)
	end
end

-- Every joint in `pose` turned at once; every joint of theirs that is not, at rest.
local function pose(npc: Person, shape: { [string]: CFrame })
	for name, joint in pairs(npc.joints) do
		Poses.turn(joint, shape[name] or npc.relax[name] or CFrame.identity)
	end
end

-- Says `text` over their head for `seconds`. A shout is bigger, redder and has no bubble round it.
function Townsfolk.say(npc: Person, text: string, seconds: number?, shout: boolean?)
	if npc.bubble then
		npc.bubble:Destroy()
	end
	-- READABLE WHEREVER THEY STAND: drawn over the room rather than in it (a speech bubble behind the
	-- window's frame was half hidden by it), big enough to read, and the text kept inside its box.
	--
	-- ONE SIZE OF TEXT FOR EVERYBODY, WHATEVER THEY SAY. The words used to be scaled to fill a fixed box,
	-- so "Evening, love." came up enormous and a long line came up small, and the same person seemed to
	-- shout and then mutter. Now the text is always SPEECH_TEXT (the size the longest line anyone says,
	-- 116 characters, reads well at in a bubble SPEECH_WIDE across), and it is the BUBBLE that changes:
	-- as wide as the words up to that width, as tall as the lines they wrap to, growing upward from
	-- over the head.
	local gui = Instance.new("BillboardGui")
	gui.Name = "Speech"
	gui.Size = UDim2.fromOffset(SPEECH_WIDE + 40, 240)
	-- Its bottom edge on the point over the head, so a bubble of more lines grows up, not down over the face.
	gui.SizeOffset = Vector2.new(0, 0.5)
	gui.StudsOffset = Vector3.new(0, 2.8, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = if shout then 90 else 48
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.fromScale(0.5, 1)
	label.Size = UDim2.new()
	label.AutomaticSize = Enum.AutomaticSize.XY
	label.TextWrapped = true
	label.TextSize = if shout then SHOUT_TEXT else SPEECH_TEXT
	label.Text = text
	local widest = Instance.new("UISizeConstraint")
	widest.MaxSize = Vector2.new(if shout then SPEECH_WIDE + 40 else SPEECH_WIDE, math.huge)
	widest.Parent = label
	if shout then
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBlack
		label.TextColor3 = Color3.fromRGB(255, 244, 236)
		label.TextStrokeColor3 = Color3.fromRGB(150, 24, 30)
		label.TextStrokeTransparency = 0
		label.Rotation = math.random(-7, 7)
	else
		label.BackgroundColor3 = Color3.fromRGB(250, 248, 242)
		label.BackgroundTransparency = 0
		label.TextColor3 = Color3.fromRGB(34, 38, 44)
		label.Font = Enum.Font.GothamBold
		local edge = Instance.new("UIStroke")
		edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		edge.Color = Color3.fromRGB(34, 38, 44)
		edge.Thickness = 2
		edge.Parent = label
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 10)
		corner.Parent = label
		local pad = Instance.new("UIPadding")
		for _, side in ipairs({ "PaddingLeft", "PaddingRight" }) do
			(pad :: any)[side] = UDim.new(0, 12)
		end
		for _, side in ipairs({ "PaddingTop", "PaddingBottom" }) do
			(pad :: any)[side] = UDim.new(0, 8)
		end
		pad.Parent = label
		label.LineHeight = 1.05
	end
	label.Parent = gui
	gui.Adornee = npc.head
	gui.Parent = npc.head
	npc.bubble = gui
	-- AND THEY TALK WITH THEIR HANDS: a hand out and back while they say it, unless it is holding
	-- something or they are running for their lives. Their habit (HABITS) leaves their arms alone meanwhile.
	npc.talking = os.clock() + 2.6
	if not shout and npc.hands and not npc.busy and Poses then
		local relax = npc.relax
		turn(npc, "RightShoulder", CFrame.Angles(0.6, 0, 0.12), 0.45)
		turn(npc, "RightElbow", CFrame.Angles(0.95, 0, 0), 0.45)
		task.delay(1.8, function()
			if not npc.busy and npc.model.Parent then
				turn(npc, "RightShoulder", relax.RightShoulder or CFrame.identity, 0.7)
				turn(npc, "RightElbow", relax.RightElbow or CFrame.identity, 0.7)
			end
		end)
	end
	task.delay((seconds or 4.5) * READ, function()
		if npc.bubble == gui then
			npc.bubble = nil
		end
		gui:Destroy()
	end)
end

-- Stands one up. `feet` is where they stand and which way they face; `pose` is "stand" or "sit".
function Townsfolk.spawn(parent: Instance, name: string, feet: CFrame, stance: string,
	colours: { Color3 }, faceless: boolean?, watch: number?): Person?
	local look = LOOKS[name]
	local model = character(name, colours, look)
	if look and model:FindFirstChildOfClass("Humanoid") and not (ServerStorage:FindFirstChild("Townsfolk")
		and (ServerStorage :: any).Townsfolk:FindFirstChild(name)) then
		local ok, err = pcall(dress, model, look)
		if not ok then
			warn(("Townsfolk: %s could not be dressed (%s), so they are in plain colours."):format(name, tostring(err)))
		end
	end
	quiet(model)
	local root = model:FindFirstChild("HumanoidRootPart")
	local head = model:FindFirstChild("Head")
	if not (root and root:IsA("BasePart") and head and head:IsA("BasePart")) then
		model:Destroy()
		return nil
	end
	root.Anchored = true
	model.PrimaryPart = root
	if faceless then
		for _, item in ipairs(head:GetChildren()) do
			if item:IsA("Decal") then
				item:Destroy()
			end
		end
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local hip = if humanoid then humanoid.HipHeight else 2
	-- Sitting, the root comes down by the length of the thigh that has swung forward.
	local lift = hip + root.Size.Y / 2 - (if stance == "sit" then 1.9 else 0)
	model:PivotTo(feet * CFrame.new(0, lift, 0))
	local npc: Person = { name = name, model = model, head = head, root = root, joints = {},
		lines = LINES[name] or {}, next = 1, post = root.CFrame, lift = lift, busy = false, worn = {},
		greeted = {}, watch = watch or 22, yaw = 0, pitch = 0, relax = {},
		hands = not (look and look.hands == false), talking = 0 }
	if Poses then
		for jointName, joint in pairs(Poses.joints(model)) do
			if table.find(JOINTS, jointName) then
				npc.joints[jointName] = joint
			end
		end
	end
	if stance == "sit" then
		turn(npc, "LeftHip", CFrame.Angles(math.rad(90), 0, 0))
		turn(npc, "RightHip", CFrame.Angles(math.rad(90), 0, 0))
		turn(npc, "LeftKnee", CFrame.Angles(math.rad(-90), 0, 0))
		turn(npc, "RightKnee", CFrame.Angles(math.rad(-90), 0, 0))
		if name == "Fisherman" then
			-- Both arms forward, holding the rod.
			npc.relax.RightShoulder = CFrame.Angles(math.rad(55), 0, 0)
			npc.relax.LeftShoulder = CFrame.Angles(math.rad(45), 0, math.rad(-10))
		else
			-- Hands in the lap.
			npc.relax.RightShoulder = CFrame.Angles(0.55, 0, 0.06)
			npc.relax.LeftShoulder = CFrame.Angles(0.55, 0, -0.06)
			npc.relax.RightElbow = CFrame.Angles(0.55, 0, 0)
			npc.relax.LeftElbow = CFrame.Angles(0.55, 0, 0)
		end
	else
		-- STANDING EASY, not as a shop dummy: the arms a little out from the sides and the elbows soft.
		npc.relax.RightShoulder = CFrame.Angles(0.07, 0, 0.09)
		npc.relax.LeftShoulder = CFrame.Angles(0.07, 0, -0.09)
		npc.relax.RightElbow = CFrame.Angles(0.2, 0, 0)
		npc.relax.LeftElbow = CFrame.Angles(0.16, 0, 0)
	end
	for jointName, by in pairs(npc.relax) do
		turn(npc, jointName, by)
	end
	model.Parent = parent
	living[name] = npc
	Townsfolk.live()
	if #npc.lines > 0 then
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Talk"
		prompt.ObjectText = if look and look.title then look.title else name
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		-- F, not E: the attendant stands by the glass, whose own prompt is E.
		prompt.KeyboardKeyCode = Enum.KeyCode.F
		prompt.GamepadKeyCode = Enum.KeyCode.ButtonY
		prompt.Parent = root
		prompt.Triggered:Connect(function()
			if npc.busy then
				return
			end
			Townsfolk.say(npc, npc.lines[npc.next])
			npc.next = npc.next % #npc.lines + 1
		end)
	end
	return npc
end

-- A hat, a rod: a part welded to one of them, placed relative to `to` (their Head, or a hand).
function Townsfolk.wear(npc: Person, partName: string, size: Vector3, colour: Color3, to: string, offset: CFrame,
	shape: Enum.PartType?): BasePart?
	local anchor = npc.model:FindFirstChild(to, true)
	if not (anchor and anchor:IsA("BasePart")) then
		return nil
	end
	local p = Instance.new("Part")
	p.Name = partName
	p.Size = size
	p.Color = colour
	p.Material = Enum.Material.SmoothPlastic
	p.CanCollide = false
	p.CanTouch = false
	p.Massless = true
	if shape then
		p.Shape = shape
	end
	p.CFrame = anchor.CFrame * offset
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = anchor
	weld.Part1 = p
	weld.Parent = p
	p.Parent = npc.model
	npc.worn[partName] = { part = p, to = anchor, offset = offset }
	return p
end

-- The way the attendant runs when the glass goes, from their post: points on the floor.
function Townsfolk.route(name: string, points: { Vector3 })
	local npc = living[name]
	if npc then
		npc.route = points
	end
end

-- The attendant's answer to the glass. `stage` is tap, crack, crack2, burst or mended.
local tapsHeard = 0
function Townsfolk.react(stage: string)
	local npc = living.Attendant
	if not (npc and npc.model.Parent) or npc.busy then
		return
	end
	local lines = REACTIONS[stage]
	if not lines then
		return
	end
	local line = lines[1]
	if stage == "tap" then
		tapsHeard += 1
		line = lines[(tapsHeard - 1) % #lines + 1]
	end
	Townsfolk.say(npc, line, if stage == "burst" then 3 else 3.5, stage == "burst")
	if not Poses then
		return
	end
	-- Pointing at the notice, and the arm back down after.
	turn(npc, "RightShoulder", CFrame.Angles(math.rad(80), 0, math.rad(stage == "burst" and 40 or 0)), 0.25)
	turn(npc, "RightElbow", CFrame.Angles(math.rad(10), 0, 0), 0.25)
	task.delay(1.6, function()
		if not npc.busy then
			turn(npc, "RightShoulder", npc.relax.RightShoulder or CFrame.identity, 0.5)
			turn(npc, "RightElbow", npc.relax.RightElbow or CFrame.identity, 0.5)
		end
	end)
end

-- ===== THE ATTENDANT, WHEN THE GLASS GOES =====
--
-- NOT STANDING THERE. They jump at the burst with their arms thrown up and their cap flying off, and
-- run: past the end of the bench, out through the tunnel's doorway and down the tunnel toward the
-- tower, arms up, screaming. Once the water is deep enough they swim -- under it in the tunnel,
-- blowing bubbles -- and in the tower they tread water at the surface and complain. When it has gone
-- down they walk back to their post, head down, put their cap back on and say something about a mop.
-- All of it by moving their root and turning their joints, every frame, from the server.
local PANIC = {
	screams = { "AAAAAH!", "THE GLASS!", "RUN! GET OUT!", "HELP!", "I TOLD YOU!", "NOT AGAIN!", "SWIM FOR IT!" },
	under = { "GLUB!", "BLBLBL!", "MMPH!" },
	treading = { "Somebody call maintenance!", "This is not in my job description.", "I can't feel my legs!",
		"Is it still coming in?!", "I'm not paid enough for this!" },
	RUN = 11, -- studs a second
	SWIM = 6.5,
	WALK = 4.5,
	DEEP = 2.6, -- water this deep and they swim
	HEADROOM = 5.5, -- the highest their middle rises off the floor while swimming along (a tunnel is low)
}

-- The poses, `t` seconds in: each joint's turn from its rest (R15, in the character's own axes: a
-- shoulder's +Z lifts the right arm out and up and -Z the left, +X swings a limb forward, a knee's -X
-- bends it back, the neck's +X tips the head back).
local POSES = {}
function POSES.startle(t: number): { [string]: CFrame }
	local shake = math.sin(t * 30) * 0.08
	return {
		RightShoulder = CFrame.Angles(0.2, 0, 2.6 + shake), LeftShoulder = CFrame.Angles(0.2, 0, -2.6 - shake),
		RightElbow = CFrame.Angles(0.9, 0, 0), LeftElbow = CFrame.Angles(0.9, 0, 0),
		Neck = CFrame.Angles(0.45, 0, 0), Waist = CFrame.Angles(0.15, 0, 0),
		RightHip = CFrame.Angles(0.35, 0, 0), LeftHip = CFrame.Angles(0.35, 0, 0),
		RightKnee = CFrame.Angles(-0.6, 0, 0), LeftKnee = CFrame.Angles(-0.6, 0, 0),
	}
end
function POSES.run(t: number): { [string]: CFrame }
	local stride = math.sin(t * 11)
	return {
		RightHip = CFrame.Angles(0.9 * stride, 0, 0), LeftHip = CFrame.Angles(-0.9 * stride, 0, 0),
		RightKnee = CFrame.Angles(-(0.2 + 0.9 * math.max(0, -stride)), 0, 0),
		LeftKnee = CFrame.Angles(-(0.2 + 0.9 * math.max(0, stride)), 0, 0),
		RightShoulder = CFrame.Angles(0.3 * math.sin(t * 14), 0, 2.5 + 0.4 * math.sin(t * 17)),
		LeftShoulder = CFrame.Angles(0.3 * math.sin(t * 14 + 1), 0, -(2.5 + 0.4 * math.sin(t * 17 + 2))),
		RightElbow = CFrame.Angles(0.5 + 0.4 * math.sin(t * 16), 0, 0), LeftElbow = CFrame.Angles(0.5 + 0.4 * math.sin(t * 16 + 1.4), 0, 0),
		Waist = CFrame.Angles(-0.15, 0.2 * stride, 0), Neck = CFrame.Angles(0.35 + 0.1 * math.sin(t * 9), 0.3 * math.sin(t * 5), 0),
	}
end
function POSES.swim(t: number): { [string]: CFrame }
	local kick = math.sin(t * 10)
	return {
		RightShoulder = CFrame.Angles(t * 6, 0, 0.3), LeftShoulder = CFrame.Angles(t * 6 + math.pi, 0, -0.3),
		RightElbow = CFrame.Angles(0.25, 0, 0), LeftElbow = CFrame.Angles(0.25, 0, 0),
		RightHip = CFrame.Angles(0.35 * kick, 0, 0), LeftHip = CFrame.Angles(-0.35 * kick, 0, 0),
		RightKnee = CFrame.Angles(-0.2, 0, 0), LeftKnee = CFrame.Angles(-0.2, 0, 0),
		Neck = CFrame.Angles(0.7, 0, 0),
	}
end
function POSES.tread(t: number): { [string]: CFrame }
	local scull = math.sin(t * 4)
	return {
		RightShoulder = CFrame.Angles(0.4 * scull, 0, 1.3 + 0.35 * scull), LeftShoulder = CFrame.Angles(-0.4 * scull, 0, -(1.3 + 0.35 * scull)),
		RightElbow = CFrame.Angles(0.4, 0, 0), LeftElbow = CFrame.Angles(0.4, 0, 0),
		RightHip = CFrame.Angles(0.6 * math.sin(t * 3), 0, 0), LeftHip = CFrame.Angles(0.6 * math.sin(t * 3 + math.pi), 0, 0),
		RightKnee = CFrame.Angles(-(0.7 + 0.4 * math.sin(t * 3)), 0, 0), LeftKnee = CFrame.Angles(-(0.7 + 0.4 * math.sin(t * 3 + math.pi)), 0, 0),
		Neck = CFrame.Angles(0.25, 0.4 * math.sin(t * 1.5), 0),
	}
end
function POSES.walk(t: number): { [string]: CFrame }
	local stride = math.sin(t * 6)
	return {
		RightHip = CFrame.Angles(0.45 * stride, 0, 0), LeftHip = CFrame.Angles(-0.45 * stride, 0, 0),
		RightKnee = CFrame.Angles(-(0.1 + 0.5 * math.max(0, -stride)), 0, 0), LeftKnee = CFrame.Angles(-(0.1 + 0.5 * math.max(0, stride)), 0, 0),
		RightShoulder = CFrame.Angles(-0.3 * stride, 0, 0.08), LeftShoulder = CFrame.Angles(0.3 * stride, 0, -0.08),
		Neck = CFrame.Angles(-0.4, 0, 0), Waist = CFrame.Angles(-0.1, 0, 0),
	}
end

-- A worn thing knocked off (it floats, the water being terrain water), or put back where it was.
local function knockOff(npc: Person, partName: string)
	local worn = npc.worn[partName]
	if not worn or not worn.part.Parent then
		return
	end
	for _, child in ipairs(worn.part:GetChildren()) do
		if child:IsA("WeldConstraint") then
			child:Destroy()
		end
	end
	worn.part.Massless = false
	worn.part.CanCollide = true
	worn.part.Anchored = false
	worn.part.AssemblyLinearVelocity = npc.root.CFrame.LookVector * -6 + Vector3.new(0, 16, 0)
	worn.part.AssemblyAngularVelocity = Vector3.new(math.random(-8, 8), math.random(-8, 8), math.random(-8, 8))
end
local function putBack(npc: Person)
	for _, worn in pairs(npc.worn) do
		if worn.part.Parent and worn.to.Parent and not worn.part:FindFirstChildOfClass("WeldConstraint") then
			worn.part.Anchored = false
			worn.part.CanCollide = false
			worn.part.Massless = true
			worn.part.CFrame = worn.to.CFrame * worn.offset
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = worn.to
			weld.Part1 = worn.part
			weld.Parent = worn.part
		end
	end
end

local function runPanic(npc: Person, levelAt: () -> number, seconds: number)
	local route = npc.route :: { Vector3 }
	local root = npc.root
	local start = (npc.post * CFrame.new(0, -npc.lift, 0)).Position
	local path = { start }
	for _, point in ipairs(route) do
		table.insert(path, point)
	end
	local function level(): number
		local ok, value = pcall(levelAt)
		return if ok and typeof(value) == "number" then value else -math.huge
	end
	-- Bubbles from their mouth while they are under.
	local bubbles = Instance.new("ParticleEmitter")
	bubbles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	bubbles.Color = ColorSequence.new(Color3.fromRGB(226, 244, 240))
	bubbles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 0.45) })
	bubbles.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	bubbles.Lifetime = NumberRange.new(0.8, 1.4)
	bubbles.Speed = NumberRange.new(2, 4)
	bubbles.EmissionDirection = Enum.NormalId.Top
	bubbles.SpreadAngle = Vector2.new(20, 20)
	bubbles.Acceleration = Vector3.new(0, 5, 0)
	bubbles.Rate = 0
	bubbles.Parent = npc.head

	knockOff(npc, "Cap")
	local began = os.clock()
	local last = 0
	local at = path[1]
	local leg = 2
	local heading = Vector3.new(npc.post.LookVector.X, 0, npc.post.LookVector.Z).Unit
	local phase = "startle"
	local phaseAt = 0
	local nextLine = 0
	local said = 0
	while npc.model.Parent do
		local t = os.clock() - began
		local dt = math.min(0.1, t - last)
		last = t
		local water = level()
		local depth = water - at.Y
		local swimming = depth > PANIC.DEEP
		local shape: { [string]: CFrame }
		local lift = npc.lift
		local body: CFrame
		if phase == "startle" then
			-- Turned to the burst (the window is behind the way out), jumping at it.
			local away = Vector3.new(path[2].X - at.X, 0, path[2].Z - at.Z)
			local toWindow = if away.Magnitude > 0.1 then -away.Unit else heading
			local up = at + Vector3.new(0, lift + math.sin(math.pi * math.min(1, t / 0.7)) * 1.4, 0)
			body = CFrame.lookAt(up, up + toWindow)
			shape = POSES.startle(t)
			if t >= 0.7 then
				phase = "flee"
			end
		else
			if phase == "flee" or phase == "back" then
				local target = path[leg]
				local flat = Vector3.new(target.X - at.X, 0, target.Z - at.Z)
				local speed = if swimming then PANIC.SWIM elseif phase == "flee" then PANIC.RUN else PANIC.WALK
				if flat.Magnitude <= speed * dt then
					at = target
					leg += if phase == "flee" then 1 else -1
					if phase == "flee" and leg > #path then
						phase, phaseAt = "tread", t
					elseif phase == "back" and leg < 1 then
						break
					end
				else
					at += flat.Unit * speed * dt
				end
				if flat.Magnitude > 0.05 then
					heading = heading:Lerp(flat.Unit, math.min(1, dt * 10))
					heading = Vector3.new(heading.X, 0, heading.Z).Unit
				end
			elseif phase == "tread" and water < at.Y + 0.5 and t - phaseAt > 3 then
				phase, leg = "back", #path - 1
			end
			if swimming then
				-- Along a tunnel, no higher than the headroom; at the end, in the tower, at the surface.
				local rise = if phase == "tread" then depth - 1.6 else math.clamp(depth - 1.4, 0.4, PANIC.HEADROOM)
				local centre = Vector3.new(at.X, at.Y + rise, at.Z)
				body = CFrame.lookAt(centre, centre + heading)
					* (if phase == "tread" then CFrame.identity else CFrame.Angles(-1.25, 0, 0))
				shape = if phase == "tread" then POSES.tread(t) else POSES.swim(t)
			else
				local running = phase == "flee"
				local bob = if running then math.abs(math.sin(t * 11)) * 0.3 else math.abs(math.sin(t * 6)) * 0.1
				local centre = at + Vector3.new(0, lift + bob, 0)
				body = CFrame.lookAt(centre, centre + heading)
				shape = if running then POSES.run(t) elseif phase == "back" then POSES.walk(t) else {}
			end
		end
		root.CFrame = body
		pose(npc, shape)
		local under = swimming and phase ~= "tread" and depth - 1.4 > PANIC.HEADROOM + 1
		bubbles.Rate = if under then 14 else 0
		-- What they shout, and when.
		if t >= nextLine then
			if phase == "startle" or phase == "flee" then
				local pool = if under then PANIC.under else PANIC.screams
				said += 1
				Townsfolk.say(npc, pool[(said - 1) % #pool + 1], 1.1, true)
				nextLine = t + 1.25
			elseif phase == "tread" then
				said += 1
				Townsfolk.say(npc, PANIC.treading[(said - 1) % #PANIC.treading + 1], 3)
				nextLine = t + 4
			elseif phase == "back" then
				Townsfolk.say(npc, "...", 2)
				nextLine = math.huge
			end
		end
		if t > seconds + 60 then
			break
		end
		RunService.Heartbeat:Wait()
	end
	bubbles:Destroy()
end

-- When the glass goes: the attendant runs, swims and comes back (above). `levelAt` is where the water
-- is now; `seconds` how long it will be there.
function Townsfolk.panic(levelAt: () -> number, seconds: number)
	local npc = living.Attendant
	if not (npc and npc.model.Parent and npc.route and #npc.route > 0 and Poses) or npc.busy then
		return
	end
	npc.busy = true
	task.spawn(function()
		local ok, err = pcall(runPanic, npc, levelAt, seconds)
		if not ok then
			warn("Townsfolk: the attendant's escape failed part-way: " .. tostring(err))
		end
		-- Whatever happened, back at their post with their cap on.
		if npc.model.Parent then
			npc.root.CFrame = npc.post
			pose(npc, {})
			putBack(npc)
			npc.busy = false
			Townsfolk.say(npc, REACTIONS.mended[1], 4)
		end
	end)
end

-- ===== WHAT THEY DO WITH THEMSELVES =====
--
-- Standing still and breathing is how a statue waits. Each of the Sky Pools' people has one small habit,
-- and each one is the story: it is always three o'clock up there, and nobody is quite at ease with it.
--   DEV looks at his watch every few seconds, as if it might have moved.
--   OKAFOR fans herself with her hand on her lounger: the heat, and the waiting.
--   RUDY nods to the one song, a hand on the deck, the record going round (SkyPoolsClient turns it).
-- Only while they are not talking (their hands are busy then) and not running for their lives.
local HABITS: { [string]: (Person, number) -> () } = {}

-- A joint of theirs turned by `by`, from how they rest (a seated arm is not a standing one).
local function lean(npc: Person, name: string, by: CFrame)
	local joint = npc.joints[name]
	if joint then
		Poses.turn(joint, (npc.relax[name] or CFrame.identity) * by)
	end
end

function HABITS.Dev(npc: Person, t: number)
	-- A look every seven seconds or so, held for a moment, then the arm back down.
	local cycle = t % 7.3
	local up = if cycle < 0.5 then cycle / 0.5 elseif cycle < 1.9 then 1 elseif cycle < 2.4 then (2.4 - cycle) / 0.5 else 0
	up = up * up * (3 - 2 * up)
	lean(npc, "LeftShoulder", CFrame.Angles(1.25 * up, 0.3 * up, -0.35 * up))
	lean(npc, "LeftElbow", CFrame.Angles(1.55 * up, 0, 0))
	if up > 0.05 then
		lean(npc, "Neck", CFrame.Angles(npc.pitch - 0.45 * up, npc.yaw * (1 - up) + 0.25 * up, 0))
	end
end

function HABITS.Okafor(npc: Person, t: number)
	-- A hand fanning in front of her face, in bursts.
	local burst = math.clamp(math.sin(t * 0.55) * 1.6, 0, 1)
	lean(npc, "RightShoulder", CFrame.Angles(1.9 * burst, 0, 0.35 * burst))
	lean(npc, "RightElbow", CFrame.Angles((1.5 + 0.35 * math.sin(t * 11)) * burst, 0, 0))
	lean(npc, "RightWrist", CFrame.Angles(0, 0, 0.5 * math.sin(t * 11) * burst))
end

function HABITS.Rudy(npc: Person, t: number)
	-- The beat: about a hundred and ten a minute.
	local beat = math.sin(t * math.pi * 2 * 1.85)
	lean(npc, "Neck", CFrame.Angles(npc.pitch * 0.5 - 0.12 * beat * beat, npc.yaw * 0.6, 0))
	lean(npc, "Waist", CFrame.Angles(0.04 * beat, npc.yaw * 0.2 + 0.05 * math.sin(t * 1.2), 0))
	-- A hand on the deck, nudging it.
	lean(npc, "LeftShoulder", CFrame.Angles(0.85, 0.15 * math.sin(t * 2.2), -0.12))
	lean(npc, "LeftElbow", CFrame.Angles(0.7, 0, 0))
end

-- ===== THEIR LIVES, between one line and the next =====
--
-- Twenty times a second, for everyone standing: who is near, and what they do about it. The first
-- time a player comes within GREET of someone they say their first line (so the story reaches you
-- whether or not you press anything), and anyone within their watching distance has their head
-- turned toward them, slowly, and a breath in their chest. Not while they are busy running.
local LIFE = {
	GREET = 12, -- studs: this near, the first time, and they say their first line
	EVERY = 0.05, -- seconds between one look round and the next
	connection = nil :: RBXScriptConnection?,
	next = 0,
}

local function nearestTo(npc: Person): (Player?, Vector3?, number)
	local best: Player?, at: Vector3?, gap = nil, nil, math.huge
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local head = character and character:FindFirstChild("Head")
		if head and head:IsA("BasePart") then
			local d = (head.Position - npc.head.Position).Magnitude
			if d < gap then
				best, at, gap = player, head.Position, d
			end
		end
	end
	return best, at, gap
end

function Townsfolk.live()
	if LIFE.connection then
		return
	end
	LIFE.connection = RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now < LIFE.next then
			return
		end
		LIFE.next = now + LIFE.EVERY
		for name, npc in pairs(living) do
			if not npc.model.Parent then
				living[name] = nil
				continue
			end
			local player, at, gap = nearestTo(npc)
			if player and gap < LIFE.GREET and not npc.greeted[player] and not npc.busy and #npc.lines > 0 then
				npc.greeted[player] = true
				Townsfolk.say(npc, npc.lines[npc.next])
				npc.next = npc.next % #npc.lines + 1
			end
			if npc.busy or not Poses then
				continue
			end
			-- The head, toward whoever is nearest within their watching distance, or back to rest.
			local yaw, pitch = 0, 0
			if at and gap < npc.watch then
				local rel = npc.root.CFrame:PointToObjectSpace(at)
				yaw = math.clamp(math.atan2(-rel.X, -rel.Z), -1.1, 1.1)
				pitch = math.clamp(math.atan2(rel.Y - 1.5, math.max(1, Vector2.new(rel.X, rel.Z).Magnitude)), -0.35, 0.35)
			end
			npc.yaw += (yaw - npc.yaw) * 0.12
			npc.pitch += (pitch - npc.pitch) * 0.12
			local neck = npc.joints.Neck
			if neck then
				Poses.turn(neck, CFrame.Angles(npc.pitch, npc.yaw, 0))
			end
			local waist = npc.joints.Waist
			if waist then
				Poses.turn(waist, CFrame.Angles(0.025 * math.sin(now * 1.6 + #name), npc.yaw * 0.25, 0))
			end
			-- THEIR HABIT, when their hands are their own.
			local habit = HABITS[name]
			if habit and now > npc.talking then
				habit(npc, now)
			end
		end
		if next(living) == nil and LIFE.connection then
			LIFE.connection:Disconnect()
			LIFE.connection = nil
		end
	end)
end

-- Shouted, by `name`, as a player goes: off the board, down the slide.
function Townsfolk.shout(name: string)
	local npc = living[name]
	local lines = SHOUTS[name]
	if not (npc and npc.model.Parent and lines) or npc.busy then
		return
	end
	Townsfolk.say(npc, lines[math.random(1, #lines)], 2.2, true)
	if Poses then
		-- An arm up, waving them off, and down again.
		turn(npc, "RightShoulder", CFrame.Angles(0, 0, 2.6), 0.2)
		task.delay(1.4, function()
			turn(npc, "RightShoulder", npc.relax.RightShoulder or CFrame.identity, 0.5)
		end)
	end
end

function Townsfolk.find(name: string): Person?
	local npc = living[name]
	return if npc and npc.model.Parent then npc else nil
end

return Townsfolk
