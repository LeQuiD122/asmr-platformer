--!strict
-- ReplicatedStorage/Shared/ChunkDefinitions.lua
-- Metadata for the 13 prototype chunks. Depends on MaterialConfig only for
-- material-name validation (not enforced at runtime here, but keeps the
-- two tables honest during authoring).

local ChunkDefinitions = {}

ChunkDefinitions.S1_Straight = {
	id = "S1_Straight", name = "Stable Straight", category = "stable",
	materials = {}, sizeX = 10, sizeZ = 4,
	connections = { "south", "north" }, tags = { "straight", "flat" },
	containsSlime = false, containsRisk = false,
}
ChunkDefinitions.S2_Junction = {
	id = "S2_Junction", name = "Stable Junction", category = "stable",
	materials = {}, sizeX = 8, sizeZ = 8,
	connections = { "south", "east", "north" }, tags = { "junction", "flat" },
	containsSlime = false, containsRisk = false,
}
ChunkDefinitions.P1_HoneyCorridor = {
	id = "P1_HoneyCorridor", name = "Honey Corridor", category = "pace",
	materials = { Honey = true }, sizeX = 6, sizeZ = 4,
	connections = { "south", "north" }, tags = { "straight", "flat", "honey" },
	containsSlime = false, containsRisk = false,
}
ChunkDefinitions.P2_ButterWaxCurve = {
	id = "P2_ButterWaxCurve", name = "Butter-wax Curve", category = "pace",
	materials = { ButterWax = true }, sizeX = 6, sizeZ = 6,
	connections = { "south", "east" }, tags = { "curve", "flat" },
	containsSlime = false, containsRisk = false,
}
ChunkDefinitions.P3_KineticSandRamp = {
	id = "P3_KineticSandRamp", name = "Kinetic Sand Ramp", category = "pace",
	materials = { KineticSand = true }, sizeX = 8, sizeZ = 4,
	connections = { "south", "north" }, tags = { "straight", "ramp" },
	containsSlime = false, containsRisk = false,
}
ChunkDefinitions.P4_PaceChain_H_KS = {
	id = "P4_PaceChain_H_KS", name = "Honey to Sand Chain", category = "pace",
	materials = { Honey = true, KineticSand = true }, sizeX = 10, sizeZ = 4,
	connections = { "south", "north" }, tags = { "straight", "flat", "pace-chain" },
	containsSlime = false, containsRisk = false,
}
ChunkDefinitions.R1_SlimeLaunch = {
	id = "R1_SlimeLaunch", name = "Slime Launcher", category = "risk",
	materials = { Slime = true }, sizeX = 6, sizeZ = 4,
	connections = { "south", "north" }, tags = { "straight", "gap" },
	containsSlime = true, containsRisk = true,
}
ChunkDefinitions.R2_SoapBridge = {
	id = "R2_SoapBridge", name = "Soap Bridge", category = "risk",
	materials = { Soap = true }, sizeX = 8, sizeZ = 4,
	connections = { "south", "north" }, tags = { "straight", "flat", "narrow" },
	containsSlime = false, containsRisk = true,
}
-- Shaped soap. Same material and category as R2, different outline -- see PlanShapes, and
-- the `form` field in ChunkBuilder's segment table.
ChunkDefinitions.R4_SoapStar = {
	-- 22 x 22, up from 18 x 18. One of the star's five points lands on the exit centre
	-- line, so the last cubes on the platform are that point's tip -- the wider the slab,
	-- the more studs those same few cubes are worth. See PlanShapes.star.
	id = "R4_SoapStar", name = "Soap Star", category = "risk",
	materials = { Soap = true }, sizeX = 22, sizeZ = 22,
	connections = { "south", "north" }, tags = { "straight", "flat", "wide" },
	containsSlime = false, containsRisk = true,
}
ChunkDefinitions.R5_SoapPebbles = {
	id = "R5_SoapPebbles", name = "Soap Pebbles", category = "risk",
	materials = { Soap = true }, sizeX = 12, sizeZ = 22,
	connections = { "south", "north" }, tags = { "straight", "flat", "narrow" },
	containsSlime = false, containsRisk = true,
}
ChunkDefinitions.R6_SoapHeart = {
	id = "R6_SoapHeart", name = "Soap Heart", category = "risk",
	materials = { Soap = true }, sizeX = 18, sizeZ = 22,
	connections = { "south", "north" }, tags = { "straight", "flat", "wide" },
	containsSlime = false, containsRisk = true,
}
ChunkDefinitions.R9_IceCrack = {
	id = "R9_IceCrack", name = "Cracking Ice", category = "risk",
	materials = { Ice = true }, sizeX = 16, sizeZ = 18,
	connections = { "south", "north" }, tags = { "straight", "flat" },
	containsSlime = false, containsRisk = true,
}
ChunkDefinitions.R14_ChocolateSnap = {
	id = "R14_ChocolateSnap", name = "Tempered Chocolate", category = "risk",
	materials = { ChocolateSolid = true }, sizeX = 16, sizeZ = 12,
	connections = { "south", "north" }, tags = { "straight", "flat", "wide" },
	containsSlime = false, containsRisk = true,
}
ChunkDefinitions.P11_SaltFlat = {
	id = "P11_SaltFlat", name = "Salt Flat", category = "pace",
	materials = { Salt = true }, sizeX = 16, sizeZ = 12,
	connections = { "south", "north" }, tags = { "straight", "flat", "wide" },
	containsSlime = false, containsRisk = false,
}
ChunkDefinitions.P12_ButtonPad = {
	id = "P12_ButtonPad", name = "Button Pad", category = "pace",
	materials = { Buttons = true }, sizeX = 16, sizeZ = 12,
	connections = { "south", "north" }, tags = { "straight", "flat", "wide" },
	containsSlime = false, containsRisk = false,
}
ChunkDefinitions.R15_LavaCrust = {
	id = "R15_LavaCrust", name = "Lava Crust", category = "risk",
	materials = { Lava = true }, sizeX = 16, sizeZ = 12,
	connections = { "south", "north" }, tags = { "straight", "flat", "wide" },
	containsSlime = false, containsRisk = true,
}
ChunkDefinitions.R16_Oobleck = {
	id = "R16_Oobleck", name = "Non-Newtonian", category = "risk",
	materials = { Oobleck = true }, sizeX = 16, sizeZ = 12,
	connections = { "south", "north" }, tags = { "straight", "flat", "wide" },
	containsSlime = false, containsRisk = true,
}
ChunkDefinitions.R17_MeltingSnow = {
	id = "R17_MeltingSnow", name = "Melting Snow", category = "risk",
	materials = { Snow = true }, sizeX = 16, sizeZ = 12,
	connections = { "south", "north" }, tags = { "straight", "flat", "wide" },
	containsSlime = false, containsRisk = true,
}
ChunkDefinitions.P8_Foam = {
	id = "P8_Foam", name = "Memory Foam", category = "pace",
	materials = { Foam = true }, sizeX = 16, sizeZ = 12,
	connections = { "south", "north" }, tags = { "straight", "flat", "wide" },
	containsSlime = false, containsRisk = false,
}
ChunkDefinitions.P9_LightSwitches = {
	id = "P9_LightSwitches", name = "Light Switches", category = "pace",
	materials = { LightSwitch = true }, sizeX = 16, sizeZ = 12,
	connections = { "south", "north" }, tags = { "straight", "flat", "wide" },
	containsSlime = false, containsRisk = false,
}
ChunkDefinitions.P10_ClayPress = {
	id = "P10_ClayPress", name = "Clay Press", category = "pace",
	materials = { Clay = true }, sizeX = 16, sizeZ = 12,
	connections = { "south", "north" }, tags = { "straight", "flat", "wide" },
	containsSlime = false, containsRisk = false,
}
ChunkDefinitions.R10_LegoStuds = {
	id = "R10_LegoStuds", name = "Lego Studs", category = "risk",
	materials = { Lego = true }, sizeX = 16, sizeZ = 12,
	connections = { "south", "north" }, tags = { "straight", "flat", "wide" },
	containsSlime = false, containsRisk = true,
}
ChunkDefinitions.R11_CharcoalSnap = {
	id = "R11_CharcoalSnap", name = "Charcoal Snap", category = "risk",
	materials = { Charcoal = true }, sizeX = 16, sizeZ = 12,
	connections = { "south", "north" }, tags = { "straight", "flat", "wide" },
	containsSlime = false, containsRisk = true,
}
ChunkDefinitions.R12_ChocolateMelt = {
	id = "R12_ChocolateMelt", name = "Melting Chocolate", category = "risk",
	materials = { Chocolate = true }, sizeX = 16, sizeZ = 12,
	connections = { "south", "north" }, tags = { "straight", "flat", "wide" },
	containsSlime = false, containsRisk = true,
}
ChunkDefinitions.R13_CloudSink = {
	id = "R13_CloudSink", name = "Cloud Sink", category = "risk",
	materials = { Cloud = true }, sizeX = 16, sizeZ = 12,
	connections = { "south", "north" }, tags = { "straight", "flat", "wide" },
	containsSlime = false, containsRisk = true,
}
ChunkDefinitions.P7_LambsEar = {
	id = "P7_LambsEar", name = "Lamb's Ear", category = "pace",
	materials = { LambsEar = true }, sizeX = 16, sizeZ = 18,
	connections = { "south", "north" }, tags = { "straight", "flat" },
	containsSlime = false, containsRisk = false,
}
-- The Sunken City's own: jellyfish bells (MaterialConfig.Jellyfish, gen_jellyfish.py).
ChunkDefinitions.R39_JellyfishHop = {
	id = "R39_JellyfishHop", name = "Jellyfish Hop", category = "risk",
	materials = { Jellyfish = true }, sizeX = 20, sizeZ = 46,
	connections = { "south", "north" }, tags = { "straight", "gap" },
	containsSlime = false, containsRisk = true,
}
ChunkDefinitions.P29_JellyfishBloom = {
	id = "P29_JellyfishBloom", name = "Jellyfish Bloom", category = "pace",
	materials = { Jellyfish = true }, sizeX = 16, sizeZ = 12,
	connections = { "south", "north" }, tags = { "straight", "flat" },
	containsSlime = false, containsRisk = false,
}
ChunkDefinitions.P6_JelloSoda = {
	id = "P6_JelloSoda", name = "Jello Soda", category = "pace",
	materials = { JelloSoda = true }, sizeX = 16, sizeZ = 12,
	connections = { "south", "north" }, tags = { "straight", "flat", "wide" },
	containsSlime = false, containsRisk = false,
}
ChunkDefinitions.P5_KeyboardRun = {
	id = "P5_KeyboardRun", name = "Creamy Keyboard Run", category = "pace",
	materials = { CreamyKeyboard = true }, sizeX = 16, sizeZ = 16,
	connections = { "south", "north" }, tags = { "straight", "flat", "wide" },
	containsSlime = false, containsRisk = false,
}
ChunkDefinitions.R7_SandTurtle = {
	id = "R7_SandTurtle", name = "Sand Turtle", category = "pace",
	materials = { KineticSand = true }, sizeX = 16, sizeZ = 16,
	connections = { "south", "north" }, tags = { "straight", "flat", "wide" },
	containsSlime = false, containsRisk = false,
}
ChunkDefinitions.R8_BubbleWrapGiant = {
	id = "R8_BubbleWrapGiant", name = "Giant Bubble Wrap", category = "risk",
	materials = { BubbleWrap = true }, sizeX = 16, sizeZ = 16,
	connections = { "south", "north" }, tags = { "straight", "flat", "wide" },
	containsSlime = false, containsRisk = true,
}
ChunkDefinitions.R3_BubbleWrapStairs = {
	id = "R3_BubbleWrapStairs", name = "Bubble Wrap Stairs", category = "risk",
	materials = { BubbleWrap = true }, sizeX = 3, sizeZ = 4,
	connections = { "south", "north" }, tags = { "stairs" },
	containsSlime = false, containsRisk = true,
}
ChunkDefinitions.C1_SlimeToPace = {
	id = "C1_SlimeToPace", name = "Slime to Honey Landing", category = "risk",
	materials = { Slime = true, Honey = true }, sizeX = 8, sizeZ = 4,
	connections = { "south", "north" }, tags = { "straight", "gap" },
	containsSlime = true, containsRisk = true,
}
ChunkDefinitions.C2_PaceToStable = {
	id = "C2_PaceToStable", name = "Sand to Stable Transition", category = "pace",
	materials = { KineticSand = true }, sizeX = 8, sizeZ = 4,
	connections = { "south", "north" }, tags = { "straight", "flat" },
	containsSlime = false, containsRisk = false,
}
ChunkDefinitions.C3_SoapWithWideLanding = {
	id = "C3_SoapWithWideLanding", name = "Soap w/ Safe Flanks", category = "risk",
	materials = { Soap = true }, sizeX = 12, sizeZ = 4,
	connections = { "south", "north" }, tags = { "straight", "flat", "wide" },
	containsSlime = false, containsRisk = true,
}
ChunkDefinitions.C4_BubbleWrapToStable = {
	id = "C4_BubbleWrapToStable", name = "Bubble Wrap to Stable Landing", category = "risk",
	materials = { BubbleWrap = true }, sizeX = 8, sizeZ = 4,
	connections = { "south", "north" }, tags = { "straight", "flat" },
	containsSlime = false, containsRisk = true,
}


-- ===== SHAPED PLATFORMS =====
--
-- Seventeen chunks that differ from the ones above in one word each: `form` in the recipe,
-- which names an outline in PlanShapes and cuts the platform to it. Nothing here needs a
-- mesh, because none of these materials has one -- soap is a field of cubes, lego is a
-- stack of bricks, buttons are caps on a plate, and an outline is just a test the placement
-- loop already runs.
--
-- ARRIVING HERE IS THE STEP THAT GETS FORGOTTEN. A chunk can have a recipe in ChunkBuilder,
-- a layout that passes every geometric check and a slot in a level sequence, and still never
-- ===== chunks built from the imported asset packs =====
--
-- These five reuse EXISTING rigs and add nothing to the deformation system. That is the whole
-- design: the Needoh, keycap and butter meshes are finished MeshParts with no bones in them,
-- so they cannot be walking surfaces here -- everything you stand on in this game deforms, and
-- deforming needs a skinned mesh authored for it.
--
-- So each of these is an existing material's slab with the imported meshes dressed on top by
-- ChunkProps, or the same slab in a different colour. A Needoh chunk is a jello platform with
-- Needohs resting in it; a lava keyboard is the keyboard rig wearing the free model's texture.
-- Nothing new has to deform, and nothing existing had to change to allow it.

-- THE EXCEPTION TO THE PARAGRAPH ABOVE. This one was a jello platform with Needohs resting
-- on it, and that got the look and none of the feel: the props were rigid decoration on a
-- surface deforming independently of them, so you pressed into the jello BETWEEN the Needohs
-- and the Needohs themselves stayed hard. A material here is a thing that gives when you
-- stand on it, and that one did not.
--
-- It is now its own material on its own skinned mesh, built by blender/gen_needoh.py.
ChunkDefinitions.P20_NeedohField = {
	id = "P20_NeedohField", name = "Needoh Field", category = "pace",
	materials = { Needoh = true }, sizeX = 16, sizeZ = 12,
	connections = { "south", "north" }, tags = { "straight", "flat", "wide" },
	containsSlime = false, containsRisk = false,
}
-- THE STICK GETS ITS OWN CHUNK. It was a prop lying on P24's butter slab, which made it
-- scenery on someone else's surface -- the same mistake the Needoh field started as. Here the
-- sticks ARE the platform, on their own rig, in their own material.
ChunkDefinitions.P25_ButterStick = {
	id = "P25_ButterStick", name = "Butter Sticks", category = "pace",
	materials = { ButterStick = true }, sizeX = 16, sizeZ = 12,
	connections = { "south", "north" }, tags = { "straight", "flat", "wide" },
	containsSlime = false, containsRisk = false,
}
-- THE OTHER THREE NEEDOH BEDS. Same material, same rig, different layout -- so they cost a
-- mesh each and nothing else, and the level generator treats them as four unrelated chunks
-- because as far as a player crossing them is concerned they are.
ChunkDefinitions.P26_NeedohBoulders = {
	id = "P26_NeedohBoulders", name = "Needoh Boulders", category = "pace",
	materials = { Needoh = true }, sizeX = 16, sizeZ = 12,
	connections = { "south", "north" }, tags = { "straight", "flat", "wide" },
	containsSlime = false, containsRisk = false,
}
ChunkDefinitions.P27_NeedohGrid = {
	id = "P27_NeedohGrid", name = "Needoh Grid", category = "pace",
	materials = { Needoh = true }, sizeX = 16, sizeZ = 12,
	connections = { "south", "north" }, tags = { "straight", "flat", "wide" },
	containsSlime = false, containsRisk = false,
}
ChunkDefinitions.P28_NeedohDrift = {
	id = "P28_NeedohDrift", name = "Needoh Drift", category = "pace",
	materials = { Needoh = true }, sizeX = 16, sizeZ = 12,
	connections = { "south", "north" }, tags = { "straight", "flat", "wide" },
	containsSlime = false, containsRisk = false,
}
ChunkDefinitions.P21_KeyboardDusk = {
	id = "P21_KeyboardDusk", name = "Dusk Keyboard", category = "pace",
	materials = { CreamyKeyboard = true }, sizeX = 16, sizeZ = 16,
	connections = { "south", "north" }, tags = { "straight", "flat", "wide" },
	containsSlime = false, containsRisk = false,
}
ChunkDefinitions.P22_KeyboardMint = {
	id = "P22_KeyboardMint", name = "Mint Keyboard", category = "pace",
	materials = { CreamyKeyboard = true }, sizeX = 16, sizeZ = 16,
	connections = { "south", "north" }, tags = { "straight", "flat", "wide" },
	containsSlime = false, containsRisk = false,
}
-- PACE, NOT RISK, despite the name. Lava here is a colourway on a keyboard, not a hazard: it
-- does not burn, it does not drop you, and filing it as risk would change how often the level
-- generator pairs it with a genuine hazard. What a chunk IS matters more than what it is called.
ChunkDefinitions.P23_KeyboardLava = {
	id = "P23_KeyboardLava", name = "Lava Keyboard", category = "pace",
	materials = { LavaKeys = true }, sizeX = 16, sizeZ = 16,
	connections = { "south", "north" }, tags = { "straight", "flat", "wide" },
	containsSlime = false, containsRisk = false,
}
ChunkDefinitions.P24_ButterBlocks = {
	id = "P24_ButterBlocks", name = "Butter Blocks", category = "pace",
	materials = { ButterWax = true }, sizeX = 16, sizeZ = 8,
	connections = { "south", "north" }, tags = { "straight", "flat" },
	containsSlime = false, containsRisk = false,
}

-- be built, because AllIds below is what ChunkBuilder iterates and AllIds is derived from
-- THIS file. That is exactly what happened to five chunks once; check_chunk_forms now cross-
-- checks the level lists against this one, and it caught all seventeen of these missing.
--
-- `sizeX`/`sizeZ` here are DOCUMENTATION and nothing reads them -- the real footprint comes
-- from the recipe in ChunkBuilder. Several of the oldest entries still carry the GDD's
-- nominal numbers (10 x 4 for a platform that is actually 16 x 20), which is why there is no
-- check cross-referencing them. The ones below are the real sizes.
ChunkDefinitions.R18_SoapRing = {
	id = "R18_SoapRing", name = "Soap Ring", category = "risk",
	materials = { Soap = true }, sizeX = 18, sizeZ = 20,
	connections = { "south", "north" }, tags = { "straight", "flat", "wide" },
	containsSlime = false, containsRisk = true,
}
ChunkDefinitions.R19_SoapWave = {
	id = "R19_SoapWave", name = "Soap Wave", category = "risk",
	materials = { Soap = true }, sizeX = 18, sizeZ = 22,
	connections = { "south", "north" }, tags = { "straight", "flat", "wide" },
	containsSlime = false, containsRisk = true,
}
ChunkDefinitions.R20_SoapBone = {
	id = "R20_SoapBone", name = "Soap Bone", category = "risk",
	materials = { Soap = true }, sizeX = 18, sizeZ = 22,
	connections = { "south", "north" }, tags = { "straight", "flat", "wide" },
	containsSlime = false, containsRisk = true,
}
ChunkDefinitions.R21_SoapCrescent = {
	id = "R21_SoapCrescent", name = "Soap Crescent", category = "risk",
	materials = { Soap = true }, sizeX = 18, sizeZ = 20,
	connections = { "south", "north" }, tags = { "straight", "flat", "wide" },
	containsSlime = false, containsRisk = true,
}
ChunkDefinitions.R31_SoapLeaf = {
	id = "R31_SoapLeaf", name = "Soap Leaf", category = "risk",
	materials = { Soap = true }, sizeX = 18, sizeZ = 22,
	connections = { "south", "north" }, tags = { "straight", "flat", "wide" },
	containsSlime = false, containsRisk = true,
}
ChunkDefinitions.R23_LegoCross = {
	id = "R23_LegoCross", name = "Lego Cross", category = "risk",
	materials = { Lego = true }, sizeX = 20, sizeZ = 20,
	connections = { "south", "north" }, tags = { "straight", "flat", "wide" },
	containsSlime = false, containsRisk = true,
}
ChunkDefinitions.R24_LegoRing = {
	id = "R24_LegoRing", name = "Lego Ring", category = "risk",
	materials = { Lego = true }, sizeX = 20, sizeZ = 20,
	connections = { "south", "north" }, tags = { "straight", "flat", "wide" },
	containsSlime = false, containsRisk = true,
}
ChunkDefinitions.R29_LegoBone = {
	id = "R29_LegoBone", name = "Lego Bone", category = "risk",
	materials = { Lego = true }, sizeX = 20, sizeZ = 20,
	connections = { "south", "north" }, tags = { "straight", "flat", "wide" },
	containsSlime = false, containsRisk = true,
}
ChunkDefinitions.R30_LegoCrescent = {
	id = "R30_LegoCrescent", name = "Lego Crescent", category = "risk",
	materials = { Lego = true }, sizeX = 20, sizeZ = 20,
	connections = { "south", "north" }, tags = { "straight", "flat", "wide" },
	containsSlime = false, containsRisk = true,
}


ChunkDefinitions.P14_ButtonDense = {
	id = "P14_ButtonDense", name = "Dense Keypad", category = "pace",
	materials = { Buttons = true }, sizeX = 16, sizeZ = 12,
	connections = { "south", "north" }, tags = { "straight", "flat", "wide" },
	containsSlime = false, containsRisk = false,
}
ChunkDefinitions.P15_ButtonDome = {
	id = "P15_ButtonDome", name = "Domed Keypad", category = "pace",
	materials = { Buttons = true }, sizeX = 16, sizeZ = 12,
	connections = { "south", "north" }, tags = { "straight", "flat", "wide" },
	containsSlime = false, containsRisk = false,
}

-- ===== THE TWO THAT POUR =====
--
-- Honey and slime with a form sculpted into the mesh. Each needs its FBX imported alongside
-- the plain one before it will build.
ChunkDefinitions.P18_HoneyComb = {
	id = "P18_HoneyComb", name = "Honeycomb", category = "pace",
	materials = { Honey = true }, sizeX = 16, sizeZ = 12,
	connections = { "south", "north" }, tags = { "straight", "flat", "wide" },
	containsSlime = false, containsRisk = false,
}
ChunkDefinitions.P19_HoneyPool = {
	id = "P19_HoneyPool", name = "Honey Pool", category = "pace",
	materials = { Honey = true }, sizeX = 16, sizeZ = 12,
	connections = { "south", "north" }, tags = { "straight", "flat", "wide" },
	containsSlime = false, containsRisk = false,
}
ChunkDefinitions.R37_SlimeBlister = {
	id = "R37_SlimeBlister", name = "Slime Blisters", category = "risk",
	materials = { Slime = true }, sizeX = 16, sizeZ = 12,
	connections = { "south", "north" }, tags = { "straight", "flat", "wide" },
	containsSlime = true, containsRisk = true,
}
ChunkDefinitions.R38_SlimeChannel = {
	id = "R38_SlimeChannel", name = "Slime Channel", category = "risk",
	materials = { Slime = true }, sizeX = 16, sizeZ = 12,
	connections = { "south", "north" }, tags = { "straight", "flat", "wide" },
	containsSlime = true, containsRisk = true,
}
-- ===== SCULPTED RIGS =====
--
-- The rigged half of the shape system. These six are ordinary bed materials with a form
-- sculpted into the mesh -- a vent, a rosette, a drift, three terraces, a spine, a swell --
-- and each needs its FBX imported alongside the plain one before it will build.
ChunkDefinitions.R32_LavaVent = {
	id = "R32_LavaVent", name = "Lava Vent", category = "risk",
	materials = { Lava = true }, sizeX = 16, sizeZ = 12,
	connections = { "south", "north" }, tags = { "straight", "flat", "wide" },
	containsSlime = false, containsRisk = true,
}
ChunkDefinitions.R33_ChocolateSwirl = {
	id = "R33_ChocolateSwirl", name = "Piped Chocolate", category = "risk",
	materials = { Chocolate = true }, sizeX = 16, sizeZ = 12,
	connections = { "south", "north" }, tags = { "straight", "flat", "wide" },
	containsSlime = false, containsRisk = true,
}
ChunkDefinitions.R34_SnowDrift = {
	id = "R34_SnowDrift", name = "Snow Drift", category = "risk",
	materials = { Snow = true }, sizeX = 16, sizeZ = 12,
	connections = { "south", "north" }, tags = { "straight", "flat", "wide" },
	containsSlime = false, containsRisk = true,
}
ChunkDefinitions.P17_ClayTerrace = {
	id = "P17_ClayTerrace", name = "Terraced Clay", category = "pace",
	materials = { Clay = true }, sizeX = 16, sizeZ = 12,
	connections = { "south", "north" }, tags = { "straight", "flat", "wide" },
	containsSlime = false, containsRisk = false,
}
ChunkDefinitions.R35_CharcoalSpine = {
	id = "R35_CharcoalSpine", name = "Charcoal Spine", category = "risk",
	materials = { Charcoal = true }, sizeX = 16, sizeZ = 12,
	connections = { "south", "north" }, tags = { "straight", "flat", "wide" },
	containsSlime = false, containsRisk = true,
}
ChunkDefinitions.R36_CloudSwell = {
	id = "R36_CloudSwell", name = "Cloud Swell", category = "risk",
	materials = { Cloud = true }, sizeX = 16, sizeZ = 12,
	connections = { "south", "north" }, tags = { "straight", "flat", "wide" },
	containsSlime = false, containsRisk = true,
}

-- Convenience: ordered list of all IDs (used by ChunkBuilder to iterate).
-- DERIVED, NOT TYPED, and the reason is a bug that cost a play session.
--
-- This list is the ONLY thing ChunkBuilder iterates, so it decides what actually gets
-- built. It used to be written out by hand, and five chunks were added to this file
-- across two sessions without any of them reaching it. Each one had a definition here, a
-- layout in ChunkBuilder, an entry in a level sequence, and passed every check -- and
-- then failed at PLAY time with "no template found for R4_SoapStar", because nothing had
-- ever asked it to be built.
--
-- Collecting the keys removes the step that can be forgotten. `def.id == name` is doing
-- double duty: it skips this field itself and any other non-chunk entry, and it catches
-- a definition whose id does not match the key it was filed under -- which would
-- otherwise build a template under one name and be looked up under another.
--
-- Sorted so the build order is stable between runs. Nothing depends on the order, but a
-- list that reshuffles itself makes two builds impossible to compare.
local ids: { string } = {}
for name, def in pairs(ChunkDefinitions) do
	if type(def) == "table" and (def :: any).id == name then
		table.insert(ids, name)
	end
end
table.sort(ids)
ChunkDefinitions.AllIds = ids

return ChunkDefinitions
