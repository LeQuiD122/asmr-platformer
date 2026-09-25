--!strict
-- ReplicatedStorage/Shared/LevelDefinitions.lua
-- The 3 hand-verified templates (T1-T3) and 3 launch levels built from them.
--
-- Template tokens map to slot categories at generation time:
--   "S"            -> category "stable"
--   "M1" / "M2"    -> category "pace"   (any pace chunk whose materials
--                                        are all whitelisted is eligible;
--                                        M1 vs M2 is not enforced as a
--                                        distinct sub-slot at runtime —
--                                        the templates were verified at
--                                        the category-placement level,
--                                        not per-exact-chunk, per the GDD's
--                                        "chunk choice within each slot is
--                                        randomized" note)
--   "R1" / "R2"    -> category "risk"
--   "W1", "O1"     -> category "risk", used only for readability in the
--                     GDD's per-template tables; treated identically to
--                     R1/R2 by the generator (both are just "risk" slots)

local LevelDefinitions = {}

-- ===== Templates =====

-- LENGTHENED TWICE: 12 -> 20 -> 40. The rhythm is unchanged throughout -- a stable landing
-- every third or fourth slot, risk slots kept apart -- there is simply more of it.
--
-- 40 is not an arbitrary round number. A full circuit of the spiral is 565 studs and a chunk
-- plus its gap is about 29, so 40 chunks is 1160 studs, which is almost exactly two turns.
-- Length is the only lever for that: tightening the radius instead would overlap chunks on
-- the inside of the curve (see SPIRAL_RADIUS in LevelService).
--
-- A risk slot never follows another risk slot, and never sits immediately before a stable
-- landing that is itself the takeoff for one. Over 40 slots that constraint matters more
-- than it did over 12 -- there is room for a bad run of them to appear by accident.
local T1_PaceChainSlimeSafety = {
	"S", "M1", "M1", "S", "R1", "M1", "S", "M2", "M1", "S",
	"M2", "S", "M1", "R1", "S", "M2", "M1", "S", "R2", "S",
	"M1", "M2", "S", "R1", "M1", "S", "M2", "M1", "S", "R2",
	"M2", "S", "M1", "M2", "S", "R1", "M1", "S", "M2", "S",
}

local T2_BubbleWrapWindow = {
	"S", "M1", "M2", "S", "R1", "M1", "S", "M2", "M1", "S", "R2", "M2",
	"S", "M1", "M2", "S", "R1", "M1", "S", "M2", "R2", "M1", "S", "M1",
	"S", "M2", "R1", "M1", "S", "M2", "M1", "S", "R2", "M2", "S", "M1",
	"M2", "S", "R1", "M1", "S", "M2", "M1", "S",
}

local T3_ExtendedSoapPressure = {
	"S", "M1", "M2", "S", "R1", "M1", "S", "R2", "M2", "S", "M1", "R1", "M2", "S",
	"M1", "S", "M2", "R1", "M1", "S", "R2", "M2", "S", "M1", "M2", "S", "R1", "M1",
	"S", "M2", "R2", "M1", "S", "M1", "M2", "S", "R1", "M2", "S", "M1", "R2", "M1",
	"S", "M2", "M1", "S", "R1", "M2", "S", "S",
}

-- ===== THE FLOODED HALLS =====
--
-- The same spiral, inside a building.
--
-- Every level so far differs only in what stands on the HORIZON -- a city, or nothing. This
-- one differs in what the run is INSIDE: a colossal tiled bathhouse standing in shallow water,
-- with the spiral climbing out through the light well in the middle of its roof.
--
-- The chunk pool is Level3's, unchanged and deliberately so. What is being tried here is
-- whether the same run feels different in a different room, and changing the chunks at the
-- same time would make that impossible to judge.
LevelDefinitions.Level4 = {
	levelId = 4,
	name = "Flooded Halls",
	description = "A walkway through a drowned tiled bathhouse. Arches, columns, still green "
		.. "water far below, and a flume down into the dark at the end of it.",
	backdrop = "floodedHalls",
	-- ===== NOT A SPIRAL, AND NOT A LINE EITHER =====
	--
	-- This field is what stops the chunks ending up inside the walls, and it has now been
	-- wrong twice.
	--
	-- A SPIRAL cannot be enclosed by a building: it climbs eighty studs while turning through
	-- five hundred degrees, and no room contains that without the route going through it.
	--
	-- A LINE could be enclosed, and still was not the answer, because the route being straight
	-- says nothing about the route being INSIDE anything. The corridor and the chunks agreed
	-- about direction and about nothing else, and the per-chunk climb was never suppressed --
	-- forty-four chunks at two and a half studs each went straight through the ceiling.
	--
	-- A PATH is the shape the building has. LevelService and FloodedHallsService both read
	-- Shared/HallRoute for it, so the corridor turns left exactly where the chunks do, and the
	-- route stays level because a building has floors.
	layout = "path",
	-- Slime, because it is the one material whose colour belongs in this room: everything here
	-- is tile, water and green light, and a green translucent pad reads as part of it.
	headlineMaterial = "Slime",
	minChunks = 44,
	maxChunks = 44,
	-- A SEED OF ITS OWN. Every level needs one -- LevelService adds it to a hash of the
	-- JobId to seed the generator -- and leaving it off is not a missing flourish, it is
	-- an arithmetic error on nil the moment anybody votes for this level.
	baseSeed = 40407,
	allowedMaterials = { "Honey", "KineticSand", "ButterWax", "Slime", "Soap", "BubbleWrap", "CreamyKeyboard", "Ice", "JelloSoda", "LambsEar", "Foam", "LightSwitch", "Clay", "Lego", "Charcoal", "Chocolate", "Cloud", "ChocolateSolid", "Salt", "Lava", "Oobleck", "Buttons", "Snow" },
	templates = { T3_ExtendedSoapPressure },
	parTime = 375,
	allowedChunkIds = {
		"S1_Straight",
		"P1_HoneyCorridor",
		"P2_ButterWaxCurve",
		"P3_KineticSandRamp",
		"P5_KeyboardRun",
		-- Built from the imported asset packs. In every pool: these are ordinary pace
		-- chunks on existing rigs, so there is no reason for one level to have them and
		-- another not.
		"P20_NeedohField",
		"P21_KeyboardDusk",
		"P22_KeyboardMint",
		"P23_KeyboardLava",
		"P24_ButterBlocks",
		"P25_ButterStick",
		"P26_NeedohBoulders",
		"P27_NeedohGrid",
		"P28_NeedohDrift",
		"P6_JelloSoda",
		"P7_LambsEar",
		"P8_Foam",
		"P9_LightSwitches",
		"P10_ClayPress",
		"R1_SlimeLaunch",
		"R2_SoapBridge",
		"R3_BubbleWrapStairs",
		"R4_SoapStar",
		"R5_SoapPebbles",
		"R6_SoapHeart",
		"R7_SandTurtle",
		"R8_BubbleWrapGiant",
		"R9_IceCrack",
		"R10_LegoStuds",
		"R11_CharcoalSnap",
		"R12_ChocolateMelt",
		"R13_CloudSink",
		"R14_ChocolateSnap",
		"P11_SaltFlat",
		"P12_ButtonPad",
		"R15_LavaCrust",
		"R16_Oobleck",
		"R17_MeltingSnow",
		"R18_SoapRing",
		"R23_LegoCross",
		"P14_ButtonDense",
"P18_HoneyComb",
				"R32_LavaVent",
		"R33_ChocolateSwirl",
		"R34_SnowDrift",
		"P17_ClayTerrace",
		"R35_CharcoalSpine",
		"R36_CloudSwell",
		"P18_HoneyComb",
		"P19_HoneyPool",
		"R37_SlimeBlister",
		"R38_SlimeChannel",
		-- Honey and slime, the two that pour. Last because they are the ones whose forms
		-- change the ROUTE rather than the surface.
		"S1_Straight",
		"S2_Junction",
		"P4_PaceChain_H_KS",
		"C1_SlimeToPace",
		"C2_PaceToStable",
		"C3_SoapWithWideLanding",
		"C4_BubbleWrapToStable",
	},
}

-- ===== Levels =====

LevelDefinitions.Level1 = {
	levelId = 1,
	name = "City Shore",
	description = "The spiral over the city, beach and waterpark horizon. The only backdrop that exists so far.",
	-- WHAT THE HUB PAD IS MADE OF. Not derived from allowedMaterials, because that list
	-- starts with Honey for this level and for Level2 both, and two identical pads would
	-- say the two levels are the same thing. Honey is this level's pacing spine.
	backdrop = "cityShore",
	-- ===== HOW IT ENDS =====
	--
	-- The spiral climbs seven hundred studs above the sea and the sea is the one thing you can
	-- see the whole way up and never reach. So the run ends by reaching it: the last chunk runs
	-- onto a tiled deck with a springboard out over the water, and the level completes when you
	-- hit it. See DiveFinaleService, which builds the platform and owns the fall.
	finale = "dive",
	headlineMaterial = "Honey",
	minChunks = 40,
	maxChunks = 40,
	-- ===== THE WHOLE KIT, ONCE EACH =====
	--
	-- City Shore is the level everybody plays first, and a forty-chunk climb kept coming back as the
	-- same handful of shapes. Three causes, all of them in this table:
	--
	--   SIX CHUNKS WERE LISTED AND COULD NEVER BE PICKED. The four Needohs, the butter sticks and
	--   the lava keyboard were here, but their materials were not in allowedMaterials, and a chunk
	--   whose materials are not all whitelisted is never a candidate. They did nothing.
	--   EIGHT WERE MISSING OUTRIGHT: the soap wave, bone, crescent and leaf, the lego ring, bone and
	--   crescent, and the domed keypad.
	--   TWO WERE LISTED TWICE, which quietly doubled their odds against everything else.
	--
	-- Every chunk in the kit is here now, once each. Grouped for reading only: each slot's category
	-- is what picks from this, so the order does not matter.
	allowedChunkIds = {
		-- Stable landings.
		"S1_Straight", "S2_Junction",
		-- Pace.
		"P1_HoneyCorridor", "P4_PaceChain_H_KS", "P18_HoneyComb", "P19_HoneyPool",
		"P2_ButterWaxCurve", "P24_ButterBlocks", "P25_ButterStick",
		"P3_KineticSandRamp", "R7_SandTurtle", "C2_PaceToStable",
		"P5_KeyboardRun", "P21_KeyboardDusk", "P22_KeyboardMint", "P23_KeyboardLava",
		"P20_NeedohField", "P26_NeedohBoulders", "P27_NeedohGrid", "P28_NeedohDrift",
		"P6_JelloSoda", "P7_LambsEar", "P8_Foam", "P9_LightSwitches",
		"P10_ClayPress", "P17_ClayTerrace", "P11_SaltFlat",
		"P12_ButtonPad", "P14_ButtonDense", "P15_ButtonDome",
		-- Risk.
		"R1_SlimeLaunch", "R37_SlimeBlister", "R38_SlimeChannel", "C1_SlimeToPace",
		"R2_SoapBridge", "R4_SoapStar", "R5_SoapPebbles", "R6_SoapHeart", "R18_SoapRing",
		"R19_SoapWave", "R20_SoapBone", "R21_SoapCrescent", "R31_SoapLeaf", "C3_SoapWithWideLanding",
		"R3_BubbleWrapStairs", "R8_BubbleWrapGiant", "C4_BubbleWrapToStable",
		"R10_LegoStuds", "R23_LegoCross", "R24_LegoRing", "R29_LegoBone", "R30_LegoCrescent",
		"R9_IceCrack", "R11_CharcoalSnap", "R35_CharcoalSpine",
		"R12_ChocolateMelt", "R14_ChocolateSnap", "R33_ChocolateSwirl",
		"R13_CloudSink", "R36_CloudSwell", "R15_LavaCrust", "R32_LavaVent",
		"R16_Oobleck", "R17_MeltingSnow", "R34_SnowDrift",
	},
	allowedMaterials = { "Honey", "KineticSand", "ButterWax", "Slime", "Soap", "BubbleWrap",
		"CreamyKeyboard", "Ice", "JelloSoda", "LambsEar", "Foam", "LightSwitch", "Clay", "Lego",
		"Charcoal", "Chocolate", "Cloud", "ChocolateSolid", "Salt", "Lava", "Oobleck", "Buttons",
		"Snow", "Needoh", "ButterStick", "LavaKeys" },
	-- NOTHING REPEATS WITHIN THE LAST SIX PICKS, whenever the slot has anything else to offer. A
	-- plain random draw from sixty-odd chunks still lands the same one twice in quick succession
	-- often enough to notice on a forty-chunk climb. LevelService honours this per level.
	avoidRecent = 6,
	parTime = 300,
	baseSeed = 1001,
	-- ALL THREE RHYTHMS, one picked per run, rather than always the first. Each spaces its stable
	-- landings and its risk slots differently, so the climb changes shape as well as material.
	templates = { T1_PaceChainSlimeSafety, T2_BubbleWrapWindow, T3_ExtendedSoapPressure },
}

LevelDefinitions.Level2 = {
	levelId = 2,
	name = "Sky Pools",
	description = "Pool decks going down through the sky round a fountain tower, and a slide into the clouds.",
	-- ===== SKY POOLS =====
	--
	-- Calm, bright and silent apart from water: the one level with no scares at all. The route winds
	-- DOWN -- the only level that does -- past pool decks standing on columns that rise out of a sea
	-- of cloud, alternating sides of the way down. It ends at a fountain tower standing ahead of the
	-- finish, on a slide that spirals down round it, through the clouds, into the pool at its foot. SkyPoolsService builds all
	-- of it round the route LevelService lays; see ROADMAP section 3 for the layout and
	-- blender/plan_skypools.py for the picture.
	backdrop = "skyPools",
	finale = "slide",
	-- ===== THE ROUTE: A DESCENDING MEANDER =====
	--
	-- Read by LevelService. The route was a ring, and it read as one: you came round to where you
	-- started, the terraces faced the middle, and on a short run a neighbour's columns stood past
	-- your own deck. It FOLLOWS A PATH now -- long S-curves sweeping away and back, going down the
	-- whole way -- so the level is a journey out rather than a lap.
	--
	-- `amplitude` is how far the heading swings either side of straight ahead, in radians;
	-- `wavelength` is how many studs one full S takes, so the bends are gentle enough that a chunk's
	-- entry face never turns more than the route's chunks can take (blender/check_skypools.py holds
	-- that, the same way it held the ring's turn rate). `descend` takes every step down instead of
	-- up and `stepScale` makes them bigger, because going down is what this level is about and the
	-- climb's steps were sized for climbing.
	layout = "meander",
	meander = { amplitude = 0.7, wavelength = 900, descend = true, stepScale = 1.6 },
	-- The bubble wrap windows are what this level is FOR.
	headlineMaterial = "BubbleWrap",
	minChunks = 44,
	maxChunks = 44,
	-- ===== THE CALM HALF OF THE KIT =====
	--
	-- Cloud, foam, bubble wrap and soap lead; honey, slime, jello, lamb's ear, the Needohs and the
	-- keypads round them out. None of the fierce ones -- no lava, no burning coal, no salt or clay
	-- tearing under you -- and none of the three chunks that climb inside themselves (the sand
	-- ramp, the bubble wrap stairs and its landing), which would put a step UP into the one route
	-- that goes down. The only stable chunk is the straight one, because every stable chunk here
	-- may be a pool deck's checkpoint, and a deck is laid along a straight side.
	allowedChunkIds = {
		"S1_Straight",
		"P1_HoneyCorridor",
		"P18_HoneyComb",
		"P19_HoneyPool",
		"P5_KeyboardRun",
		"P21_KeyboardDusk",
		"P22_KeyboardMint",
		"P6_JelloSoda",
		"P7_LambsEar",
		"P8_Foam",
		"P12_ButtonPad",
		"P14_ButtonDense",
		"P15_ButtonDome",
		"P20_NeedohField",
		"P26_NeedohBoulders",
		"P27_NeedohGrid",
		"P28_NeedohDrift",
		"R1_SlimeLaunch",
		"R37_SlimeBlister",
		"R38_SlimeChannel",
		"C1_SlimeToPace",
		"R2_SoapBridge",
		"R4_SoapStar",
		"R5_SoapPebbles",
		"R6_SoapHeart",
		"R18_SoapRing",
		"R19_SoapWave",
		"R20_SoapBone",
		"R21_SoapCrescent",
		"R31_SoapLeaf",
		"C3_SoapWithWideLanding",
		"R8_BubbleWrapGiant",
		"R13_CloudSink",
		"R36_CloudSwell",
	},
	allowedMaterials = { "Honey", "Slime", "Soap", "BubbleWrap", "CreamyKeyboard", "JelloSoda", "LambsEar",
		"Foam", "Cloud", "Buttons", "Needoh" },
	parTime = 330,
	baseSeed = 1002,
	templates = { T2_BubbleWrapWindow },
}

LevelDefinitions.Level3 = {
	levelId = 3,
	name = "The Sunken City",
	description = "A causeway just above the sea, through a drowned city, with something enormous under it.",
	-- ===== THE SUNKEN CITY =====
	--
	-- The route runs THROUGH a drowned city, just above the water, down the line of its drowned
	-- boulevard: blocks of flooded flats and offices either side, lamp posts and trams still
	-- standing in the street, a clock tower stopped at the hour the water came. Something enormous
	-- patrols the boulevard under the route and never chases you; when it passes beneath, the water
	-- darkens and the sound drops. The ending is the harbour at the far end: the route runs out onto
	-- a pier, and the whirlpool past it pulls you down into the dark. SunkenCityService builds all
	-- of it along the route LevelService lays; ROADMAP section 4 has the plan and
	-- blender/plan_sunkencity.py the picture.
	backdrop = "sunkenCity",
	finale = "drain",
	-- ===== THE ROUTE: A MEANDER THROUGH THE CITY =====
	--
	-- It was a ring round the city, seen from outside it the whole way; it is a line through the
	-- city now, which is the only way a city reads as one -- blocks either side of you, the street
	-- running ahead into the haze, and somewhere at the end of it the harbour.
	--
	-- Flat, not climbing: stepScale 0 turns the steps off, so the route stays near the water the
	-- whole way, and the swell lifts and lowers it 3.5 studs either way over every ten chunks, a
	-- road over low hills. The bend is gentler than Sky Pools' because this route is a street and
	-- the blocks are laid to it; blender/check_sunkencity.py holds it under what a chunk's entry
	-- face can take.
	layout = "meander",
	meander = { amplitude = 0.45, wavelength = 1300, stepScale = 0, wave = { height = 3.5, every = 10 } },
	headlineMaterial = "Oobleck",
	minChunks = 50,
	maxChunks = 50,
	avoidRecent = 4,
	-- ===== THE WET HALF OF THE KIT =====
	--
	-- The four this level is about (you): slime, jello soda, ice and oobleck. Only jello soda has a
	-- pace chunk, so the pace slots are filled out with the sea's own materials (suggested): salt
	-- flats, sea foam and the Needohs; and the risk slots with two soap chunks and bubble wrap, for
	-- the bubbles. Nothing that climbs inside itself and nothing that drops (the slime-to-pace
	-- chunk steps down two studs), so the route's height is the swell and nothing else, and it can
	-- never sink into the water. The only stable chunk is the straight one, which the aquarium's
	-- landing and the pier are laid along.
	allowedChunkIds = {
		"S1_Straight",
		"P6_JelloSoda",
		"P8_Foam",
		"P11_SaltFlat",
		"P20_NeedohField",
		"P26_NeedohBoulders",
		"P27_NeedohGrid",
		"P28_NeedohDrift",
		"R1_SlimeLaunch",
		"R37_SlimeBlister",
		"R38_SlimeChannel",
		"R9_IceCrack",
		"R16_Oobleck",
		"R2_SoapBridge",
		"R19_SoapWave",
		"R8_BubbleWrapGiant",
		-- And the sea's own: jellyfish bells to bounce across (MaterialConfig.Jellyfish).
		"R39_JellyfishHop",
		"P29_JellyfishBloom",
	},
	allowedMaterials = { "Slime", "JelloSoda", "Ice", "Oobleck", "Salt", "Foam", "Needoh", "Soap", "BubbleWrap", "Jellyfish" },
	parTime = 375,
	baseSeed = 1003,
	templates = { T3_ExtendedSoapPressure },
}

-- === A LEVEL IS A BACKDROP, NOT A SET OF CHUNKS ===
--
-- The first version of the lobby gave each level its own small pool of six to eight chunks,
-- which is backwards: a level is a PLACE, and every material should be reachable in all of
-- them. So all three share the sandbox's full pool and material list, and differ only in
-- `backdrop`.
--
-- Only "cityShore" exists today -- the city, beach and waterpark horizon. The others build
-- the same spiral against nothing, and are placeholders on purpose: what goes behind them,
-- how far away it sits, and whether the route stays a spiral or becomes a straight line
-- fading into fog are all open questions, and inventing answers now would mean throwing them
-- away later.

-- ===== Dev sandbox =====
-- NOT a shippable level: it breaks the GDD's 3-4 materials-per-level rule on purpose so
-- every material can be checked in one run. `fixedSequence` bypasses template selection and
-- random slot filling entirely, so nothing is left to chance -- which is what you want when
-- you are judging whether an effect looks right rather than playing.
LevelDefinitions.Sandbox = {
	levelId = 99,
	name = "Sandbox (all materials)",
	-- EXPLICITLY NONE. This was simply absent, which reads the same to Bootstrap -- nil is
	-- not "cityShore" either -- but it left the sandbox as the one level whose horizon was
	-- undecided rather than decided to be empty. check_hub now compares every level's fields
	-- against every other level's, and this is the gap it found first.
	backdrop = "none",
	description = "One shaped platform per construction first, then the six sculpted rigs, then the full material tour.",
	-- LEGO ON PURPOSE. The sandbox is a development route rather than a fourth level, and
	-- lego is the one rigid material in a set otherwise made of things that give -- so its
	-- pad feels unlike every other pad in the room the moment you stand on it.
	headlineMaterial = "Lego",
	minChunks = 85,
	maxChunks = 85,
	allowedChunkIds = {
		"S1_Straight",
		"R39_JellyfishHop",
		"P29_JellyfishBloom",
		"P1_HoneyCorridor",
		"P2_ButterWaxCurve",
		"P3_KineticSandRamp",
		"P5_KeyboardRun",
		-- Built from the imported asset packs. In every pool: these are ordinary pace
		-- chunks on existing rigs, so there is no reason for one level to have them and
		-- another not.
		"P20_NeedohField",
		"P21_KeyboardDusk",
		"P22_KeyboardMint",
		"P23_KeyboardLava",
		"P24_ButterBlocks",
		"P25_ButterStick",
		"P26_NeedohBoulders",
		"P27_NeedohGrid",
		"P28_NeedohDrift",
		"P6_JelloSoda",
		"P7_LambsEar",
		"P8_Foam",
		"P9_LightSwitches",
		"P10_ClayPress",
		"R1_SlimeLaunch",
		"R2_SoapBridge",
		"R3_BubbleWrapStairs",
		"R4_SoapStar",
		"R5_SoapPebbles",
		"R6_SoapHeart",
		"R7_SandTurtle",
		"R8_BubbleWrapGiant",
		"R9_IceCrack",
		"R10_LegoStuds",
		"R11_CharcoalSnap",
		"R12_ChocolateMelt",
		"R13_CloudSink",
		"R14_ChocolateSnap",
		"P11_SaltFlat",
		"P12_ButtonPad",
		"R15_LavaCrust",
		"R16_Oobleck",
		"R17_MeltingSnow",
		"R18_SoapRing",
		"R23_LegoCross",
		"P14_ButtonDense",
"P18_HoneyComb",
				"R32_LavaVent",
		"R33_ChocolateSwirl",
		"R34_SnowDrift",
		"P17_ClayTerrace",
		"R35_CharcoalSpine",
		"R36_CloudSwell",
		"P18_HoneyComb",
		"P19_HoneyPool",
		"R37_SlimeBlister",
		"R38_SlimeChannel",
		-- Honey and slime, the two that pour. Last because they are the ones whose forms
		-- change the ROUTE rather than the surface.
		"S1_Straight",
		"S2_Junction",
		"P4_PaceChain_H_KS",
		"C1_SlimeToPace",
		"C2_PaceToStable",
		"C3_SoapWithWideLanding",
		"C4_BubbleWrapToStable",
	},
	allowedMaterials = { "Honey", "KineticSand", "ButterWax", "Slime", "Soap", "BubbleWrap", "CreamyKeyboard", "Ice", "JelloSoda", "LambsEar", "Foam", "LightSwitch", "Clay", "Lego", "Charcoal", "Chocolate", "Cloud", "ChocolateSolid", "Salt", "Lava", "Oobleck", "Buttons", "Snow", "Jellyfish" },
	parTime = 420,
	baseSeed = 9999,
	templates = {},
	-- 85 chunks, 43 of them material-bearing, with a stable rest
	-- between every pair.
	--
	-- THE NEWEST EIGHT COME FIRST, and that is the only rule that really matters here. This
	-- is the level Bootstrap actually loads, so it is the level anyone judging new work
	-- walks -- and burying a new material forty chunks deep means checking it costs two
	-- minutes of walking past things that were already finished. Anything added from now on
	-- goes at the top of this list, not the bottom.
	--
	-- THE SHOWCASE IS ORDERED BY CONTRAST, not by category. Each new material is followed by
	-- the one that is least like it, because a material is easiest to judge against its
	-- opposite and hardest to judge against its neighbour:
	--   foam -> lego          soft, and endlessly giving, against the only hard surface here
	--   switches -> cloud     the hardest attack in the game against the one with no attack
	--   clay -> charcoal      takes an impression and keeps it, against one that takes none
	--   lamb's ear -> chocolate  the quietest thing here, against the one that melts
	--
	-- Then the established set, then a mixed pass that puts new against old -- charcoal
	-- after jello, foam after the sand turtle, cloud after soap -- because the pairs that
	-- expose a weak material are the ones nobody chose deliberately.
	--
	-- The tail exists for COVERAGE rather than for play: the four connectors and the
	-- composite pace chain are only ever placed by the template-driven levels, so until now
	-- nothing in the level anybody actually loads walked them. A break in one of those would
	-- have shown up first in a level nobody plays.
	--
	-- ON LENGTH: the spiral has a FIXED radius and climbs in Y, a step per chunk, so more
	-- chunks buys height rather than crowding. At about 29 studs of arc each this is
	-- roughly 4.2 turns of a 565-stud circuit, stacked well clear of itself.
	fixedSequence = {
		-- ONE STABLE SLAB, AND ONLY BECAUSE THE SPAWN NEEDS IT.
		--
		-- LevelService anchors the SpawnLocation at a fixed world position, so whatever chunk
		-- occupies the first slot is what you land on -- and landing on a granular platform
		-- that crumbles under you, or a risk material that dissolves on a timer, is not a
		-- start. This one slab is the only reason a stable chunk is here at all.
		"S1_Straight",
		-- THE NEWEST: the Sunken City's jellyfish bells, the hop and the bloom.
		"R39_JellyfishHop",
		"P29_JellyfishBloom",
		"S1_Straight",
		-- === THE SHAPED RUN, AND IT GOES FIRST ===
		--
		-- Moved to the front from the end, which is not a tidying decision. The sandbox is a
		-- long spiral and anything at the back of it is a five-minute walk away, so the newest
		-- work was the hardest thing in the level to look at. You now spawn into it.
		--
		-- ONE OF EACH, and nine more shaped chunks are benched rather than deleted. Five soaps
		-- in a row followed by four legos followed by three keypads reads as the same platform
		-- repeating, whatever the outlines are doing -- the differences between two soap shapes
		-- are smaller than the difference between soap and lego, so a run grouped by material
		-- buries its own variety. The benched ones are all still defined and buildable; put any
		-- of them into allowedChunkIds and the sequence together and they build.
		--
		-- The three that stay carry three DIFFERENT outlines, one per construction: cut ~18
		-- steps across in cubes, cut 6 steps across in bricks, and cutting nothing at all on a
		-- rigged plate where the shape only decides which keys exist.
		"R18_SoapRing",
		"R23_LegoCross",
		"P14_ButtonDense",
		"S1_Straight",
		-- AND THE SCULPTED ONES, which are the same idea bought the expensive way: these six
		-- are rigged meshes, so each shape is an FBX rather than a word, and each is a form the
		-- material would actually take.
		"R32_LavaVent",
		"R33_ChocolateSwirl",
		"R34_SnowDrift",
		"S2_Junction",
		"P21_KeyboardDusk",
		"P17_ClayTerrace",
		"R35_CharcoalSpine",
		"R36_CloudSwell",
		-- Honey and slime, the two that pour. Last of the sculpted run because their forms
		-- are the ones that change the ROUTE rather than the surface: a basin you drop into
		-- and climb out of, and a trough that picks your lane for you.
		"S1_Straight",
		"P18_HoneyComb",
		"P19_HoneyPool",
		"S2_Junction",
		"R37_SlimeBlister",
		"R38_SlimeChannel",
		"S1_Straight",
		-- Then the material tour, which is what the sandbox was before any of this.
		"R15_LavaCrust",
		"R17_MeltingSnow",
		"P11_SaltFlat",
		"S2_Junction",
		"R16_Oobleck",
		"P12_ButtonPad",
		"P8_Foam",
		"S1_Straight",
		"R10_LegoStuds",
		"P9_LightSwitches",
		"R13_CloudSink",
		"S2_Junction",
		"P10_ClayPress",
		"R11_CharcoalSnap",
		"P24_ButterBlocks",
		"P25_ButterStick",
		"P26_NeedohBoulders",
		"P27_NeedohGrid",
		"P28_NeedohDrift",
		"P7_LambsEar",
		"S1_Straight",
		"R12_ChocolateMelt",
		"R14_ChocolateSnap",
		"P1_HoneyCorridor",
		"S2_Junction",
		"R1_SlimeLaunch",
		"P23_KeyboardLava",
		"P2_ButterWaxCurve",
		"R3_BubbleWrapStairs",
		-- The imported-asset chunks, spread out rather than grouped. Three keyboards in a
		-- row would read as one platform repeating however differently they are coloured,
		-- which is the same trap the note above describes for soap.
		"P20_NeedohField",
		"S1_Straight",
		"P3_KineticSandRamp",
		"R9_IceCrack",
		"P22_KeyboardMint",
		"P5_KeyboardRun",
		"S2_Junction",
		"R8_BubbleWrapGiant",
		"P6_JelloSoda",
		"R11_CharcoalSnap",
		"S1_Straight",
		"R7_SandTurtle",
		"P8_Foam",
		"R2_SoapBridge",
		"S2_Junction",
		"R13_CloudSink",
		"R4_SoapStar",
		"P9_LightSwitches",
		"S1_Straight",
		"R12_ChocolateMelt",
		"R5_SoapPebbles",
		"P10_ClayPress",
		"S2_Junction",
		"R6_SoapHeart",
		"R10_LegoStuds",
		"P7_LambsEar",
		"S1_Straight",
		"P4_PaceChain_H_KS",
		"C1_SlimeToPace",
		"C2_PaceToStable",
		"S2_Junction",
		"C3_SoapWithWideLanding",
		"C4_BubbleWrapToStable",
	},
}

LevelDefinitions.All = {
	LevelDefinitions.Level1,
	LevelDefinitions.Level2,
	LevelDefinitions.Level3,
	LevelDefinitions.Level4,
}

return LevelDefinitions
