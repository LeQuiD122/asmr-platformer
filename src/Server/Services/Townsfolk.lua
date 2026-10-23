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
--   HILL HOUSE        (level 5, eight in the morning, first in the story's clock; HillHouseService stands them)
--                     MR GALE the milkman at the top of the climb, his crate at his feet. MRS DUNN the
--                     postwoman inside the garden gate with her bag.
--
-- Each GREETS you with their first line the first time you come near, and after that says the next
-- line each time you talk to them (F). While you are near, they turn their head to you, and they TELL IT
-- WITH THEIR BODIES: every line comes with a gesture for what it says (a wave hello, pointing at the
-- gates, a shrug, hands wrung over the water, a hand at the chin remembering, leaning in close), made with
-- whichever hand is not holding something (GESTURE_WORDS, Poses.tell; each client plays it smoothly,
-- StoryClient). What they say stays up for twice as long as it used to (READ, below).
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
local CollectionService = game:GetService("CollectionService")

-- The joints (Poses.joints / Poses.turn), looked for with a timeout: without it the people still stand
-- and talk, they just do not move.
local posesModule = game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Poses", 10)
-- One look for the whole game (the ninety-ninth pass): every face, colour, corner and outline.
local Style = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Style"))
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
	holding: { right: boolean, left: boolean }, talking: number, said: { [Player]: { [string]: boolean } } }

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
	-- LEVEL 5, HILL HOUSE, eight in the morning (first in the story's clock: before any of it).
	Gale = {
		"Morning! Two pints on the step, same as every morning. Same as when he was here.",
		"Tide's still in. Third day. Mr Barlow's had the station lit all night, I saw it from the top road.",
		"Big day, the paper says. Key holder for Outfall 3. They'll want you at the station by nine.",
		"The key's on its hook where it always was. He used to say a key wants a place, so nobody has to look for it.",
		"Mind the bridge, it bounces. Always has. He was always going to fix it.",
		"Go on up, then. I'll not keep you.",
	},
	Dunn = {
		"Morning, love. Nothing for you today but the paper, and that's on the mat.",
		"You're on the front page. Key holder, Outfall 3. Half the town's read it before you have.",
		"Thirty years I've walked this hill. Same door, same green. He'd have it no other colour.",
		"Sal's card came yesterday. She'll be on the sea wall at nine with a cone. She always did look out for you.",
		"Nobody writes to Hill House now. The council, the dairy and Sal. That's the lot.",
		"Off you go. The day won't wait. Though round here, you never know.",
	},
}

-- HOW EACH LINE IS TOLD: the gesture that goes with it, line for line with LINES, chosen the way a director
-- would (Poses.GESTURES has what each looks like). Sal points out to the siren tower; Pip leans in to tell you
-- the sand forgets, but not her; Mr Wick remembers holding the key forty years back; Tobi points at you when
-- he sees whose face you have. Anything said that is not here (the attendant's reactions) is read for its
-- words instead (GESTURE_WORDS).
local TOLD: { [string]: { string } } = {
	Sal = { "greet", "worry", "shrug", "point", "lean", "warn", "worry" },
	Pip = { "greet", "explain", "worry", "explain", "lean", "sad" },
	Maren = { "greet", "worry", "point", "warn", "point", "explain" },
	Dev = { "greet", "remember", "shrug", "explain", "worry", "lean" },
	Okafor = { "greet", "shrug", "lean", "explain", "sad", "worry" },
	Rudy = { "greet", "shrug", "point", "lean", "explain" },
	Attendant = { "greet", "shrug", "warn", "point", "remember", "warn" },
	Fisherman = { "greet", "remember", "sad", "worry", "lean", "worry", "remember", "warn" },
	Venn = { "greet", "point", "shrug", "lean", "explain", "warn", "remember", "shrug" },
	Tobi = { "greet", "worry", "sad", "point", "explain" },
	Barlow = { "greet", "explain", "point", "lean", "sad", "warn", "explain" },
	Gale = { "greet", "worry", "point", "remember", "warn", "shrug" },
	Dunn = { "greet", "explain", "remember", "lean", "sad", "shrug" },
}

-- THEIR VOICES' PITCH: each says their lines with the same nine sounds (no words: audio/gen_voice_sfx.py, played by
-- StoryClient with each gesture), at their own pitch, so nobody sounds like anybody else. 1 is a grown-up's middle.
local VOICES: { [string]: number } = {
	Sal = 1.12, Pip = 1.45, Maren = 1.15, Dev = 1.0, Okafor = 1.1, Rudy = 0.95, Attendant = 1.04, Fisherman = 0.78,
	Venn = 1.08, Tobi = 0.9, Barlow = 0.8, Watcher = 0.7, Gale = 0.86, Dunn = 1.06,
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
--   holds                   "both" for someone whose hands are on something welded to them elsewhere
--                           (the fisherman's rod); a thing worn on a hand (Townsfolk.wear) marks that
--                           hand by itself, and they gesture with the other
--   title                   what their Talk prompt calls them
type Look = { skin: Color3, hair: Color3?, hairStyle: string?, top: Color3?, sleeves: string?, bottom: Color3,
	legs: string?, shoes: Color3?, scale: { number }?, beard: Color3?, moustache: Color3?, glasses: boolean?,
	holds: string?, title: string? }
local LOOKS: { [string]: Look } = {
	Sal = { skin = Color3.fromRGB(226, 192, 158), hair = Color3.fromRGB(120, 78, 52), hairStyle = "bun",
		top = Color3.fromRGB(236, 120, 150), sleeves = "short", bottom = Color3.fromRGB(70, 74, 96), legs = "long",
		shoes = Color3.fromRGB(246, 242, 236), scale = { 0.97, 1.06, 1.04, 1 } },
	Pip = { skin = Color3.fromRGB(150, 104, 74), hair = Color3.fromRGB(38, 26, 20), hairStyle = "ponytail",
		top = Color3.fromRGB(250, 214, 90), sleeves = "short", bottom = Color3.fromRGB(70, 130, 190), legs = "shorts",
		shoes = Color3.fromRGB(230, 70, 60), scale = { 0.72, 0.8, 0.8, 1.12 }, title = "Pip" },
	Maren = { skin = Color3.fromRGB(198, 150, 112), hair = Color3.fromRGB(232, 198, 122), hairStyle = "ponytail",
		top = Color3.fromRGB(214, 52, 48), sleeves = "none", bottom = Color3.fromRGB(214, 52, 48), legs = "shorts",
		scale = { 1.04, 1, 1, 1 } },
	Dev = { skin = Color3.fromRGB(226, 192, 158), hair = Color3.fromRGB(62, 44, 34), hairStyle = "short",
		top = Color3.fromRGB(80, 170, 190), sleeves = "short", bottom = Color3.fromRGB(240, 240, 236), legs = "shorts",
		shoes = Color3.fromRGB(60, 62, 70), scale = { 1, 0.95, 0.95, 1 } },
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
		shoes = Color3.fromRGB(30, 34, 30), scale = { 1.02, 1.1, 1.06, 1 }, holds = "both", title = "Mr Wick" },
	Watcher = { skin = Color3.fromRGB(200, 196, 190), top = Color3.fromRGB(40, 40, 44), sleeves = "long",
		bottom = Color3.fromRGB(40, 40, 44), legs = "long", shoes = Color3.fromRGB(24, 24, 26) },
	-- THE WATCHER WITH HIS FACE BACK (the true ending, the hundred-and-fifteenth pass): the same dark clothes, and his
	-- own face, hair and colour. He says nothing; he waves.
	Marsh = { skin = Color3.fromRGB(214, 176, 146), hair = Color3.fromRGB(70, 56, 46), hairStyle = "short",
		top = Color3.fromRGB(40, 40, 44), sleeves = "long", bottom = Color3.fromRGB(40, 40, 44), legs = "long",
		shoes = Color3.fromRGB(24, 24, 26), scale = { 1.02, 1, 1, 1 }, title = "Edwin Marsh" },
	Venn = { skin = Color3.fromRGB(232, 202, 178), hair = Color3.fromRGB(200, 200, 204), hairStyle = "bun",
		top = Color3.fromRGB(116, 138, 108), sleeves = "long", bottom = Color3.fromRGB(70, 70, 82), legs = "skirt",
		shoes = Color3.fromRGB(44, 32, 30), scale = { 0.94, 1.02, 1, 1 }, glasses = true, title = "Mrs Venn" },
	Tobi = { skin = Color3.fromRGB(120, 84, 60), hair = Color3.fromRGB(20, 16, 14), hairStyle = "short",
		moustache = Color3.fromRGB(20, 16, 14), sleeves = "none", bottom = Color3.fromRGB(40, 70, 140), legs = "shorts",
		scale = { 1.04, 1.04, 1, 1 }, title = "Tobi Okafor" },
	Barlow = { skin = Color3.fromRGB(214, 170, 140), hair = Color3.fromRGB(150, 150, 152), hairStyle = "receding",
		moustache = Color3.fromRGB(150, 150, 152), top = Color3.fromRGB(62, 82, 112), sleeves = "long",
		bottom = Color3.fromRGB(62, 82, 112), legs = "long", shoes = Color3.fromRGB(42, 34, 30),
		scale = { 1.02, 1.12, 1.08, 1 }, title = "Mr Barlow" },
	-- The milkman in his white coat; the postwoman in her navy, with her glasses on a chain.
	Gale = { skin = Color3.fromRGB(222, 182, 150), hair = Color3.fromRGB(170, 166, 160), hairStyle = "short",
		top = Color3.fromRGB(242, 240, 234), sleeves = "long", bottom = Color3.fromRGB(46, 52, 70), legs = "long",
		shoes = Color3.fromRGB(30, 28, 28), scale = { 1, 1.04, 1.02, 1 }, title = "Mr Gale" },
	Dunn = { skin = Color3.fromRGB(176, 128, 96), hair = Color3.fromRGB(70, 56, 50), hairStyle = "bob",
		top = Color3.fromRGB(40, 54, 92), sleeves = "long", bottom = Color3.fromRGB(40, 54, 92), legs = "skirt",
		shoes = Color3.fromRGB(26, 24, 24), scale = { 0.98, 1, 1, 1 }, glasses = true, title = "Mrs Dunn" },
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

-- ===== TELLING IT WITH THEIR BODIES =====
--
-- Which gesture goes with a line: the one TOLD gives it, or, for anything else, from its words: the first
-- group whose words are in it, in this order, so "I don't know" is a shrug before "don't" is a warning. A
-- question nobody has words for is a shrug; anything else is told with both hands (explain).
local GESTURE_WORDS: { { any } } = {
	{ "lean", { "between you and me", "don't tell", "they say", "word is", "i heard", "rumour", "secret" } },
	{ "shrug", { "don't know", "never heard", "no idea", "who knows", "funny", "backrooms", "always has been", "can't say" } },
	{ "warn", { "mind the", "careful", "please", "don't tap", "stay back", "get back", "keep clear", "don't go", "the glass" } },
	{ "sad", { "never came", "never come", "none came", "nobody came", "came back", "gone", "miss" } },
	{ "point", { "gates", "drain", "outfall", "down there", "up there", "over there", "tower" } },
	{ "remember", { "remember", "used to", "years", "when i was", "in my day", "1979", "back then" } },
	{ "worry", { "water", "tide", "the sea", "flood", "rain", "storm", "midnight" } },
}

-- The gesture its words call for (GESTURE_WORDS), for anything said that TOLD has nothing for: an answer to what you
-- said, the attendant's reactions, and your own lines.
local function gestureForText(text: string): string
	local lower = string.lower(text)
	for _, group in ipairs(GESTURE_WORDS) do
		for _, word in ipairs(group[2] :: { string }) do
			if string.find(lower, word, 1, true) then
				return group[1] :: string
			end
		end
	end
	return if string.find(text, "?", 1, true) then "shrug" else "explain"
end

local function gestureFor(npc: Person, text: string): string
	local told = TOLD[npc.name]
	local index = table.find(npc.lines, text)
	if told and index and told[index] then
		return told[index]
	end
	return gestureForText(text)
end

-- Which of their hands are free, for the gesture: "both", "right", "left" or "none".
local function handsFree(npc: Person): string
	local right, left = not npc.holding.right, not npc.holding.left
	return if right and left then "both" elseif right then "right" elseif left then "left" else "none"
end

-- The arms a habit or a gesture moves, set back to how they rest before a gesture starts.
local ARMS = { "RightShoulder", "RightElbow", "RightWrist", "LeftShoulder", "LeftElbow", "LeftWrist" }

-- Room inside a bubble's top for the speaker's name tag on its rim (dressBubble).
local BUBBLE_TOP = 14

-- THE ONE SPEECH BUBBLE (Style.BUBBLE, the hundred-and-nineteenth pass): `label`, over a head in `gui`, made the bubble
-- everyone speaks in, its rim `rim`, with a tail under it pointing down at whoever said it.
local function asBubble(gui: BillboardGui, label: TextLabel, rim: Color3)
	label.BackgroundColor3 = Style.BUBBLE.fill
	label.BackgroundTransparency = 0
	label.TextColor3 = Style.BUBBLE.ink
	label.FontFace = Style.BUBBLE.font
	label.LineHeight = 1.05
	label.ZIndex = 2
	local edge = Instance.new("UIStroke")
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Color = rim
	edge.Thickness = Style.BUBBLE.stroke
	edge.Parent = label
	local corner = Instance.new("UICorner")
	corner.CornerRadius = Style.BUBBLE.radius
	corner.Parent = label
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 12), UDim.new(0, 12)
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0, BUBBLE_TOP), UDim.new(0, 9)
	pad.Parent = label
	-- THE TAIL: a square turned to a diamond at the bubble's bottom middle, behind it, so its lower point and its two
	-- lower edges show under the bubble; and a cream patch over the bubble's rim where the two meet, so they are one.
	local tail = Instance.new("Frame")
	tail.Name = "Tail"
	tail.AnchorPoint = Vector2.new(0.5, 0.5)
	tail.Position = UDim2.new(0.5, 0, 1, 0)
	tail.Size = UDim2.fromOffset(14, 14)
	tail.Rotation = 45
	tail.BackgroundColor3 = Style.BUBBLE.fill
	tail.BorderSizePixel = 0
	tail.ZIndex = 1
	local tailEdge = Instance.new("UIStroke")
	tailEdge.Color = rim
	tailEdge.Thickness = Style.BUBBLE.stroke
	tailEdge.Parent = tail
	tail.Parent = gui
	local join = Instance.new("Frame")
	join.Name = "TailJoin"
	join.AnchorPoint = Vector2.new(0.5, 0)
	join.Position = UDim2.new(0.5, 0, 1, -1)
	join.Size = UDim2.fromOffset(13, Style.BUBBLE.stroke + 2)
	join.BackgroundColor3 = Style.BUBBLE.fill
	join.BorderSizePixel = 0
	join.ZIndex = 3
	join.Parent = gui
end

-- WHO IS SPEAKING, AND A LITTLE DEPTH (the hundred-and-twenty-third pass, from your test: "the text between character and
-- the player could be styled better"): a light from above across the bubble, a soft shadow under it so it stands off
-- whatever is behind, and the speaker's name on a tag on its top rim in their own colour (what they wear; yours in the
-- gold of your own rim). Tagged for every screen to write it out a letter at a time (TalkClient).
local function dressBubble(gui: BillboardGui, label: TextLabel, name: string, tint: Color3)
	local light = Instance.new("UIGradient")
	light.Rotation = 90
	light.Color = ColorSequence.new(Style.BUBBLE.top, Style.BUBBLE.fill)
	light.Parent = label
	-- The shadow: the same words, unseen, in a dark box the bubble's own size, a little lower.
	local shade = Instance.new("TextLabel")
	shade.Name = "Shade"
	shade.AnchorPoint = label.AnchorPoint
	shade.Position = label.Position + UDim2.fromOffset(0, 4)
	shade.Size = label.Size
	shade.AutomaticSize = label.AutomaticSize
	shade.TextWrapped = true
	shade.TextSize = label.TextSize
	shade.FontFace = label.FontFace
	shade.LineHeight = label.LineHeight
	shade.Text = label.Text
	shade.TextTransparency = 1
	shade.BackgroundColor3 = Style.BUBBLE.ink
	shade.BackgroundTransparency = Style.BUBBLE.shade
	shade.ZIndex = 0
	for _, kind in ipairs({ "UISizeConstraint", "UICorner", "UIPadding" }) do
		local found = label:FindFirstChildOfClass(kind)
		if found then
			found:Clone().Parent = shade
		end
	end
	shade.Parent = gui
	local tag = Instance.new("TextLabel")
	tag.Name = "Speaker"
	tag.AnchorPoint = Vector2.new(0, 0.5)
	tag.Position = UDim2.new(0, -2, 0, -BUBBLE_TOP)
	tag.Size = UDim2.fromOffset(0, 22)
	tag.AutomaticSize = Enum.AutomaticSize.X
	tag.BackgroundColor3 = tint
	tag.TextColor3 = if 0.299 * tint.R + 0.587 * tint.G + 0.114 * tint.B > 0.6 then Style.BUBBLE.ink else Color3.new(1, 1, 1)
	tag.FontFace = Style.FONT.display
	tag.TextSize = Style.BUBBLE.tag
	tag.Text = name
	tag.ZIndex = 4
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.5, 0)
	round.Parent = tag
	local rim = Instance.new("UIStroke")
	rim.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	rim.Color = Style.BUBBLE.rim
	rim.Thickness = Style.BUBBLE.stroke
	rim.Parent = tag
	local room = Instance.new("UIPadding")
	room.PaddingLeft, room.PaddingRight = UDim.new(0, 9), UDim.new(0, 9)
	room.Parent = tag
	tag.Parent = label
	CollectionService:AddTag(gui, "SpeechBubble")
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
	label.Name = "Words"
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
		label.FontFace = Style.FONT.shout
		label.TextColor3 = Color3.fromRGB(255, 244, 236)
		label.TextStrokeColor3 = Color3.fromRGB(150, 24, 30)
		label.TextStrokeTransparency = 0
		label.Rotation = math.random(-7, 7)
	else
		asBubble(gui, label, Style.BUBBLE.rim)
	end
	if not shout then
		local look = LOOKS[npc.name]
		dressBubble(gui, label, if look and look.title then look.title else npc.name,
			if look then (look.top or look.bottom) else Style.BUBBLE.rim)
	end
	label.Parent = gui
	gui.Adornee = npc.head
	gui.Parent = npc.head
	npc.bubble = gui
	-- AND THEY TELL IT WITH THEIR BODIES: the gesture for what they are saying, for as long as it takes to say,
	-- on every client (StoryClient plays it on their joints, smoothly, over how they stand). Their habit (HABITS)
	-- leaves their arms alone meanwhile, and lets go of them first. Not while running for their lives.
	npc.talking = os.clock() + 2.6
	if not shout and not npc.busy then
		local seconds = math.clamp(#text / 14, 2.4, 6)
		npc.talking = os.clock() + seconds
		for _, jointName in ipairs(ARMS) do
			if npc.joints[jointName] then
				turn(npc, jointName, npc.relax[jointName] or CFrame.identity)
			end
		end
		npc.model:SetAttribute("Hands", handsFree(npc))
		npc.model:SetAttribute("Gesture", gestureFor(npc, text))
		npc.model:SetAttribute("GestureFor", seconds)
		npc.model:SetAttribute("GestureAt", workspace:GetServerTimeNow())
	end
	task.delay((seconds or 4.5) * READ, function()
		if npc.bubble == gui then
			npc.bubble = nil
		end
		gui:Destroy()
	end)
end

-- ===== WHAT YOU SAY TO THEM (the hundred-and-fourth pass, your idea) =====
--
-- Talk to someone (F) and you choose what to say (ReplicatedStorage.Shared.Conversations: what each can be asked, and
-- what each answer tells you about your father). Your choices come up on your screen (TalkClient); choose one and you
-- say it, in a bubble of your own over your head for anyone near to see, and they answer it line by line; then what
-- else you could say comes up, while you are still there. Walk away and the choices go by themselves. What you have
-- said and learned is kept in your save (EconomyService.heard), and each thing you learn goes in your journal as a
-- note. Without the module or the remote, F says their next line, as it always did.
local conversationsModule = game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Conversations", 10)
local Conversations: any = if conversationsModule and conversationsModule:IsA("ModuleScript")
	then require(conversationsModule) else nil
local TALK = { remote = nil :: RemoteEvent?, wired = false, session = {} :: { [Player]: { [string]: boolean } },
	busy = {} :: { [Player]: boolean } }

-- A module beside this one (EconomyService, Interactables), found when it is first wanted: they need nothing of this.
local function sibling(name: string): any
	local module = script.Parent and script.Parent:FindFirstChild(name)
	if module and module:IsA("ModuleScript") then
		local ok, loaded = pcall(require, module)
		if ok and type(loaded) == "table" then
			return loaded
		end
	end
	return nil
end

-- What `player` has said and learned: kept in their save, and this session's besides (a save not loaded yet).
local function knownBy(player: Player): { [string]: boolean }
	local known = {}
	local save = sibling("EconomyService")
	if save and save.heard then
		for key in pairs(save.heard(player)) do
			known[key] = true
		end
	end
	for key in pairs(TALK.session[player] or {}) do
		known[key] = true
	end
	return known
end

local function learn(player: Player, key: string)
	local mine = TALK.session[player] or {}
	TALK.session[player] = mine
	mine[key] = true
	local save = sibling("EconomyService")
	if save and save.markHeard then
		pcall(save.markHeard, player, key)
	end
end

-- WHAT YOU KNOW, asked by the rest of the story (the time clock at the flume, the hundred-and-fourteenth pass): true once
-- `player` has said or learned `key` (a topic's id, or "clue:" and a clue's).
function Townsfolk.knows(player: Player, key: string): boolean
	return knownBy(player)[key] == true
end

-- A NOTE IN YOUR JOURNAL that nobody's answer gives (the time clock's): Conversations.NOTES[key], learned and written
-- once, as a clue from an answer is.
function Townsfolk.write(player: Player, key: string)
	if not Conversations or knownBy(player)["clue:" .. key] then
		return
	end
	learn(player, "clue:" .. key)
	local note = Conversations.NOTES[key]
	local book = sibling("Interactables")
	if note and book and book.take then
		pcall(book.take, player, { title = note.title, body = note.body }, nil, "note", { from = note.from })
	end
end

-- YOUR LINE, over your own head, for anyone near to see: in the one speech bubble everyone speaks in (since the
-- hundred-and-nineteenth pass; it was the screen's dark panel), its rim the warm accent so it is still told from
-- theirs, and the same size of text. And you TELL IT WITH YOUR BODY, as they do: the gesture its words call for and
-- your voice saying it, on every client (StoryClient plays it on your joints over how you stand or walk).
function Townsfolk.speakAs(player: Player, text: string)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not (head and head:IsA("BasePart")) then
		return
	end
	local old = head:FindFirstChild("YourLine")
	if old then
		old:Destroy()
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "YourLine"
	gui.Size = UDim2.fromOffset(SPEECH_WIDE + 40, 240)
	gui.SizeOffset = Vector2.new(0, 0.5)
	gui.StudsOffset = Vector3.new(0, 2.8, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 48
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Name = "Words"
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.fromScale(0.5, 1)
	label.Size = UDim2.new()
	label.AutomaticSize = Enum.AutomaticSize.XY
	label.TextWrapped = true
	label.TextSize = SPEECH_TEXT
	label.Text = text
	local widest = Instance.new("UISizeConstraint")
	widest.MaxSize = Vector2.new(SPEECH_WIDE, math.huge)
	widest.Parent = label
	asBubble(gui, label, Style.BUBBLE.rimMine)
	dressBubble(gui, label, player.DisplayName, Style.BUBBLE.rimMine)
	label.Parent = gui
	gui.Adornee = head
	gui.Parent = head
	local seconds = math.clamp(#text / 14, 2.4, 6)
	character:SetAttribute("Hands", "both")
	-- Your own voice: the people's nine sounds, at a pitch of your own (the same each time for you).
	character:SetAttribute("Voice", 0.9 + (player.UserId % 21) / 100)
	character:SetAttribute("Gesture", gestureForText(text))
	character:SetAttribute("GestureFor", seconds)
	character:SetAttribute("GestureAt", workspace:GetServerTimeNow())
	CollectionService:AddTag(character, "Teller")
	task.delay(seconds * READ * 0.6, function()
		gui:Destroy()
	end)
end

local function talkRemote(): RemoteEvent?
	if TALK.remote then
		return TALK.remote
	end
	local folder = game:GetService("ReplicatedStorage"):FindFirstChild("RemoteEvents")
	local found = folder and folder:FindFirstChild("Talk")
	if not (found and found:IsA("RemoteEvent")) then
		return nil
	end
	TALK.remote = found
	if not TALK.wired then
		TALK.wired = true
		found.OnServerEvent:Connect(function(player: Player, kind: any, name: any, id: any)
			if kind == "say" and typeof(name) == "string" and typeof(id) == "string" then
				local ok, err = pcall(Townsfolk.answer, player, name, id)
				TALK.busy[player] = nil
				if not ok then
					warn("Townsfolk: a conversation failed: " .. tostring(err))
				end
			end
		end)
	end
	return found
end

-- WHAT `player` HAS SAID TO `npc` IN THIS RUN of the level (the hundred-and-twenty-third pass, from your test: "after
-- the second time logging back into the level, the talk with characters does not reset, which should happen"). Each
-- level's people are made afresh, and with them what you have said to them, so every topic comes back each run. What
-- you LEARNED stays (the clues, your journal's notes, the story's place): a topic said before is offered as said
-- before (not `fresh`), and one waiting on another said in any run is offered at once.
local function saidBy(npc: Person, player: Player): { [string]: boolean }
	local mine = npc.said[player]
	if not mine then
		mine = {}
		npc.said[player] = mine
	end
	return mine
end

-- WHAT `player` CAN SAY TO `npc` NOW, to their screen: the topics ready for them (each marked `fresh` if never said in any
-- run), then smalltalk; and their colour, for the disc by their name.
function Townsfolk.offer(player: Player, npc: Person)
	local remote = talkRemote()
	if not (remote and Conversations) then
		return
	end
	local options = {}
	local known = knownBy(player)
	for _, topic in ipairs(Conversations.offered(npc.name, known, saidBy(npc, player))) do
		table.insert(options, { id = topic.id, say = topic.say, fresh = not known[topic.id] })
	end
	if #npc.lines > 0 then
		table.insert(options, { id = "smalltalk", say = Conversations.SMALLTALK })
	end
	local look = LOOKS[npc.name]
	remote:FireClient(player, "offer", { person = npc.name, title = if look and look.title then look.title else npc.name,
		head = npc.head, tint = if look then (look.top or look.bottom) else nil, options = options })
end

-- `player` CHOSE `id` to say to `name`: if it was theirs to say (offered, and they are near), said, and answered.
function Townsfolk.answer(player: Player, name: string, id: string)
	local npc = living[name]
	if not (npc and Conversations) or TALK.busy[player] or npc.busy then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) or (root.Position - npc.head.Position).Magnitude > Conversations.REACH + 6 then
		return
	end
	local said: string, replies: { string }
	local topic = nil
	if id == "smalltalk" then
		if #npc.lines == 0 then
			return
		end
		said, replies = Conversations.SMALLTALK, { npc.lines[npc.next] }
		npc.next = npc.next % #npc.lines + 1
	else
		local ready = false
		for _, offered in ipairs(Conversations.offered(name, knownBy(player), saidBy(npc, player))) do
			if offered.id == id then
				ready, topic = true, offered
			end
		end
		if not (ready and topic) then
			return
		end
		said, replies = topic.say, topic.reply
	end
	TALK.busy[player] = true
	Townsfolk.speakAs(player, said)
	task.wait(1.4)
	for index, line in ipairs(replies) do
		if not npc.model.Parent then
			break
		end
		Townsfolk.say(npc, line)
		if index < #replies then
			task.wait(math.clamp(#line / 16, 2.2, 5))
		end
	end
	if topic then
		local fresh = topic.clue ~= nil and not knownBy(player)["clue:" .. topic.clue]
		learn(player, topic.id)
		saidBy(npc, player)[topic.id] = true
		if fresh then
			learn(player, "clue:" .. topic.clue)
			local note = Conversations.NOTES[topic.clue]
			local book = sibling("Interactables")
			if note and book and book.take then
				pcall(book.take, player, { title = note.title, body = note.body }, nil, "note", { from = note.from })
			end
		end
	end
	task.wait(1.2)
	TALK.busy[player] = nil
	-- And on, while you are still there: what else you could say.
	local stillRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if stillRoot and stillRoot:IsA("BasePart") and npc.model.Parent
		and (stillRoot.Position - npc.head.Position).Magnitude <= Conversations.REACH then
		Townsfolk.offer(player, npc)
	end
end

Players.PlayerRemoving:Connect(function(player: Player)
	TALK.session[player] = nil
	TALK.busy[player] = nil
	for _, npc in pairs(living) do
		npc.said[player] = nil
	end
end)

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
		holding = { right = look ~= nil and (look.holds == "both" or look.holds == "right"),
			left = look ~= nil and (look.holds == "both" or look.holds == "left") }, talking = 0, said = {} }
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
	model:SetAttribute("Hands", handsFree(npc))
	model:SetAttribute("Voice", VOICES[name] or 1)
	model.Parent = parent
	-- Tagged for the clients, which play their gestures (StoryClient).
	CollectionService:AddTag(model, "Townsperson")
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
		prompt.Triggered:Connect(function(player: Player)
			if npc.busy then
				return
			end
			-- YOUR CHOICE OF WHAT TO SAY (the hundred-and-fourth pass), greeted first if they have not greeted you yet.
			if Conversations and talkRemote() then
				if not npc.greeted[player] then
					npc.greeted[player] = true
					Townsfolk.say(npc, npc.lines[npc.next])
					npc.next = npc.next % #npc.lines + 1
				end
				if not TALK.busy[player] then
					Townsfolk.offer(player, npc)
				end
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
	-- Something in a hand: that hand is holding it, and they gesture with the other.
	if to == "RightHand" or to == "LeftHand" then
		if to == "RightHand" then
			npc.holding.right = true
		else
			npc.holding.left = true
		end
		npc.model:SetAttribute("Hands", handsFree(npc))
	end
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

Townsfolk.STAMP = "0d6b3e76"
return Townsfolk
