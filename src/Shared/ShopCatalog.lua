--!strict
-- ReplicatedStorage/Shared/ShopCatalog.lua
-- EVERYTHING THE SHOP SELLS, AT ONE PRICE. The shop on your screen draws its tiles from this and the
-- server checks every request against it, so the two can never disagree about what something costs.
-- To change a price, change it here and paste this file; nothing else holds a number.
--
-- TOKENS are earned by finishing a level (REWARD below) and spent on cosmetics. ROBUX buys token
-- packs, the passes and private servers. Robux items need their ids from the Creator Dashboard
-- (Monetization: Passes and Developer Products): `passId` for a pass, `productId` for a developer
-- product. Until an id is pasted in, the shop shows the item and says it is not on sale yet.
--
-- `soon`: drawn in the shop with its price, not yet buyable, because what it does is still being
-- built. Nothing is sold that does nothing. (Nothing is soon at the moment.)

export type Item = {
	id: string,
	tab: string,
	name: string,
	blurb: string,
	kind: string, -- "trail", "aura", "pal", "steps", "sound", "emote", "pass", "product", "tokens", "background", "crate"
	price: number?, -- in tokens
	robux: number?, -- the price in Robux shown until Roblox has said its own for you (robuxFor, below)
	passId: number?,
	productId: number?,
	tokens: number?, -- what a token pack gives
	colour: Color3,
	accent: Color3,
	soon: boolean?,
	earn: string?, -- earned, never sold: "story", given for finishing the story (EconomyService.finishStory);
	-- "starter", given with the starter pack (EconomyService.grantStarter); "crate", out of the background crate
	-- (EconomyService's "crate")
	gives: string?, -- what else a pass gives, once (the starter pack's trail)
	once: boolean?, -- bought once only: off the Featured tab once it is yours
	rarity: string?, -- a background's (RARITY below): how often the crate gives it
	theme: string?, -- a background's look (ShopLook.THEMES)
}

local ShopCatalog = {}

-- The tabs, in the order they are shown. Featured is a pick from the others.
ShopCatalog.TABS = { "Featured", "Pals", "Steps", "Trails", "Sounds", "Auras", "Emotes", "Passes", "Tokens", "Backgrounds", "Wear" }

ShopCatalog.FEATURED = { "StarterPack", "VIP", "PalNeedoh", "PalLava", "BgCrate", "Aura", "DoubleTokens", "HoneyPaw", "Poppy", "HoneyDrip", "Embers",
	"Pack300" }

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local ITEMS: { Item } = {
	-- STEPS: the stamp your foot leaves wherever you walk, seen by everyone (StepService draws them).
	{ id = "HeartStep", tab = "Steps", kind = "steps", name = "Heart steps", blurb = "Little hearts where you walk",
		price = 60, colour = rgb(237, 147, 177), accent = rgb(114, 36, 62) },
	{ id = "StarStep", tab = "Steps", kind = "steps", name = "Star steps", blurb = "A star in every print",
		price = 90, colour = rgb(250, 199, 117), accent = rgb(99, 56, 6) },
	{ id = "HoneyPaw", tab = "Steps", kind = "steps", name = "Honey paw", blurb = "Paw prints, slow to fill",
		price = 120, colour = rgb(239, 159, 39), accent = rgb(99, 56, 6) },
	-- CAT PAWS (the two-hundred-and-sixteenth pass): pink jelly toe beans pressed where you walk (Cos_CatPaw).
	{ id = "CatPaw", tab = "Steps", kind = "steps", name = "Cat paws", blurb = "Soft pink toe beans where you walk",
		price = 160, colour = rgb(255, 196, 214), accent = rgb(120, 40, 70) },
	{ id = "BubbleSole", tab = "Steps", kind = "steps", name = "Bubble sole", blurb = "Prints that fizz away",
		price = 150, colour = rgb(181, 212, 244), accent = rgb(12, 68, 124) },
	{ id = "SlimeStep", tab = "Steps", kind = "steps", name = "Slime steps", blurb = "Green blobs that drip as they go",
		price = 130, colour = rgb(151, 196, 89), accent = rgb(39, 80, 10) },
	{ id = "EmberStep", tab = "Steps", kind = "steps", name = "Ember steps", blurb = "Glowing prints that cool to ash",
		price = 170, colour = rgb(255, 128, 48), accent = rgb(113, 43, 19) },
	-- PENGUIN STEPS (limited, January's into February, the two-hundred-and-fourteenth pass).
	{ id = "PenguinSteps", tab = "Steps", kind = "steps", name = "Penguin steps", blurb = "A little penguin's prints in the snow",
		price = 300, limited = { from = "2027-01-29", to = "2027-02-12" }, colour = rgb(206, 230, 250), accent = rgb(24, 50, 90) },
	-- VIP ONLY (the two-hundred-and-thirteenth pass): never sold, yours while you have VIP (EconomyService.owns).
	{ id = "GildedSteps", tab = "Steps", kind = "steps", name = "Gilded steps", blurb = "Gold leaf pressed where you walk. VIP only",
		earn = "vip", colour = rgb(250, 214, 130), accent = rgb(110, 70, 8) },

	-- TRAILS: a ribbon of your chosen material behind you, seen by everyone.
	{ id = "SoapSuds", tab = "Trails", kind = "trail", name = "Soap suds", blurb = "A clean white ribbon",
		price = 100, colour = rgb(236, 244, 250), accent = rgb(12, 68, 124) },
	{ id = "HoneyDrip", tab = "Trails", kind = "trail", name = "Honey drip", blurb = "Warm and slow behind you",
		price = 140, colour = rgb(239, 159, 39), accent = rgb(99, 56, 6) },
	{ id = "SlimeGlow", tab = "Trails", kind = "trail", name = "Slime glow", blurb = "Bright green, a bit sticky",
		price = 180, colour = rgb(151, 196, 89), accent = rgb(39, 80, 10) },
	{ id = "CloudPuff", tab = "Trails", kind = "trail", name = "Cloud puff", blurb = "Soft as the Sky Pools",
		price = 250, colour = rgb(206, 203, 246), accent = rgb(60, 52, 137) },
	{ id = "JellyRibbon", tab = "Trails", kind = "trail", name = "Jelly", blurb = "Wobbly pink, dropping jelly beads",
		price = 220, colour = rgb(236, 96, 120), accent = rgb(114, 36, 62) },
	{ id = "Sprinkles", tab = "Trails", kind = "trail", name = "Sprinkles", blurb = "A shower of sugar sprinkles behind you",
		price = 260, colour = rgb(255, 236, 246), accent = rgb(114, 36, 62) },
	{ id = "LavaRibbon", tab = "Trails", kind = "trail", name = "Lava ribbon", blurb = "Molten, glowing, throwing sparks",
		price = 320, colour = rgb(255, 128, 32), accent = rgb(113, 43, 19) },
	-- THE TWO-HUNDRED-AND-SIXTEENTH PASS (from your note of 2026-11-14: "add more stuff to the shop for tokens"):
	-- blossom petals drifting down behind you, and cookie crumbs tossed and bouncing (Cos_Petal, Cos_CookieBit).
	{ id = "Petals", tab = "Trails", kind = "trail", name = "Blossom", blurb = "Cherry blossom petals drifting down behind you",
		price = 280, colour = rgb(255, 206, 222), accent = rgb(130, 46, 80) },
	{ id = "CookieCrumbs", tab = "Trails", kind = "trail", name = "Cookie crumbs", blurb = "Crumbs and chunks of cookie behind you",
		price = 240, colour = rgb(226, 176, 110), accent = rgb(90, 52, 20) },
	-- EARNED, NOT BOUGHT: the key's green ribbon, for finishing the story (EconomyService.finishStory). The shop shows
	-- it with what it takes instead of a price.
	{ id = "GreenRibbon", tab = "Trails", kind = "trail", name = "Green ribbon", blurb = "The key's ribbon. Finish the story",
		earn = "story", colour = rgb(58, 150, 88), accent = rgb(14, 60, 32) },
	-- EARNED, NOT BOUGHT: the swatch, for every material found on the levels (EconomyService.foundMaterial).
	{ id = "Swatch", tab = "Trails", kind = "trail", name = "Swatch", blurb = "Every material at once. Find them all",
		earn = "materials", colour = rgb(222, 170, 220), accent = rgb(86, 34, 92) },
	-- IN THE STARTER PACK ONLY (the pass below), never sold on its own.
	{ id = "SeaGlass", tab = "Trails", kind = "trail", name = "Sea glass", blurb = "Soft green glass. In the starter pack",
		earn = "starter", colour = rgb(130, 212, 190), accent = rgb(8, 80, 65) },
	-- HERE FOR A SEASON (the two-hundred-and-thirteenth pass, `limited`: on sale from the first day to the day before the
	-- last, UTC; first in Featured while it is here; kept for good by whoever has it). AUTUMN LEAVES: real leaves turning
	-- as they fall behind you.
	{ id = "AutumnLeaves", tab = "Trails", kind = "trail", name = "Autumn leaves", blurb = "Leaves turning as they fall behind you",
		price = 350, limited = { from = "2026-11-14", to = "2026-11-28" }, colour = rgb(252, 196, 140), accent = rgb(120, 46, 16) },
	-- JANUARY'S (limited, the two-hundred-and-fourteenth pass): WINTER WOOL, a knitted cord and pom-poms tumbling behind.
	{ id = "WinterWool", tab = "Trails", kind = "trail", name = "Winter wool", blurb = "Knitted wool, pom-poms tumbling behind you",
		price = 350, limited = { from = "2027-01-01", to = "2027-01-15" }, colour = rgb(250, 200, 196), accent = rgb(130, 24, 36) },
	-- VIP ONLY (the two-hundred-and-thirteenth pass).
	{ id = "GoldLeaf", tab = "Trails", kind = "trail", name = "Gold leaf", blurb = "Ribbons of gold, flakes drifting down. VIP only",
		earn = "vip", colour = rgb(255, 222, 140), accent = rgb(110, 70, 8) },

	-- SOUNDS: what your steps sound like, in place of Roblox's own footsteps (StepService plays them).
	{ id = "Crunchy", tab = "Sounds", kind = "sound", name = "Crunchy", blurb = "A soft salt and snow crunch now and then",
		price = 150, colour = rgb(250, 199, 117), accent = rgb(99, 56, 6) },
	{ id = "Gloopy", tab = "Sounds", kind = "sound", name = "Gloopy", blurb = "A slow honey squish now and then",
		price = 200, colour = rgb(93, 202, 165), accent = rgb(8, 80, 65) },
	{ id = "Poppy", tab = "Sounds", kind = "sound", name = "Poppy", blurb = "A soft bubble wrap pop now and then",
		price = 250, colour = rgb(237, 147, 177), accent = rgb(114, 36, 62) },
	{ id = "Velvet", tab = "Sounds", kind = "sound", name = "Velvet", blurb = "A soft fuzzy brush now and then",
		price = 90, colour = rgb(176, 190, 170), accent = rgb(44, 64, 40) },
	{ id = "Thock", tab = "Sounds", kind = "sound", name = "Thock", blurb = "A creamy keyboard thock now and then",
		price = 300, colour = rgb(127, 119, 221), accent = rgb(38, 33, 92) },

	-- AURAS: a soft glow or particles round you, seen by everyone.
	{ id = "Bubbles", tab = "Auras", kind = "aura", name = "Bubbles", blurb = "Bubbles drifting up round you",
		price = 200, colour = rgb(181, 212, 244), accent = rgb(12, 68, 124) },
	{ id = "Mist", tab = "Auras", kind = "aura", name = "Sea mist", blurb = "A cool haze at your feet",
		price = 250, colour = rgb(225, 245, 238), accent = rgb(8, 80, 65) },
	{ id = "Embers", tab = "Auras", kind = "aura", name = "Embers", blurb = "Sparks off the lava",
		price = 300, colour = rgb(240, 153, 123), accent = rgb(113, 43, 19) },
	{ id = "Sparkle", tab = "Auras", kind = "aura", name = "Gold sparkle", blurb = "Glints all round you",
		price = 400, colour = rgb(250, 199, 117), accent = rgb(99, 56, 6) },
	{ id = "Snowfall", tab = "Auras", kind = "aura", name = "Snowfall", blurb = "Your own little snowfall",
		price = 280, colour = rgb(236, 244, 255), accent = rgb(12, 68, 124) },
	{ id = "Fireflies", tab = "Auras", kind = "aura", name = "Fireflies", blurb = "Soft lights drifting round you",
		price = 350, colour = rgb(220, 255, 140), accent = rgb(39, 80, 10) },
	-- HERE FOR A SEASON (limited): the first frost, then lantern night to the year's end.
	{ id = "FirstFrost", tab = "Auras", kind = "aura", name = "First frost", blurb = "Frost glinting round you, snowflakes turning",
		price = 400, limited = { from = "2026-11-28", to = "2026-12-12" }, colour = rgb(214, 236, 250), accent = rgb(30, 70, 110) },
	{ id = "LanternNight", tab = "Auras", kind = "aura", name = "Lantern night", blurb = "Warm lanterns drifting up round you",
		price = 450, limited = { from = "2026-12-12", to = "2027-01-01" }, colour = rgb(255, 214, 160), accent = rgb(110, 50, 10) },
	{ id = "HotCocoa", tab = "Auras", kind = "aura", name = "Hot cocoa", blurb = "Marshmallows bobbing up through the steam",
		price = 400, limited = { from = "2027-01-15", to = "2027-01-29" }, colour = rgb(236, 206, 176), accent = rgb(96, 50, 24) },
	-- RUBBER DUCKS (the two-hundred-and-sixteenth pass): a little parade of them going round you (Cos_Duck).
	{ id = "RubberDucks", tab = "Auras", kind = "aura", name = "Duck parade", blurb = "Rubber ducks paddling round you in a ring",
		price = 380, colour = rgb(255, 226, 110), accent = rgb(120, 76, 10) },
	-- VIP ONLY (the two-hundred-and-fourteenth pass): THE GILDED CROWN, a real crown of gold over your head.
	{ id = "GildedCrown", tab = "Auras", kind = "aura", name = "Gilded crown", blurb = "A crown of gold floating over you. VIP only",
		earn = "vip", colour = rgb(255, 226, 150), accent = rgb(110, 70, 8) },
	{ id = "Starlight", tab = "Auras", kind = "aura", name = "Starlight", blurb = "Stars twinkling all round you",
		price = 450, colour = rgb(206, 196, 255), accent = rgb(38, 33, 92) },

	-- PALS (the two-hundred-and-sixteenth pass, from your note of 2026-11-14: "add more stuff to the shop for tokens, make
	-- it good quality"): a little friend made of one of the bay's materials, following you about at your side, seen by
	-- everyone. Each a model made in Studio's generator (Assets.Cosmetics.Pal_*), moving its own way (PALS below,
	-- CosmeticsClient): the squishy ones hop after you and squash as they land, the bee buzzes, the cloud drifts and the
	-- lava rock floats, glowing. One at a time.
	{ id = "PalNeedoh", tab = "Pals", kind = "pal", name = "Squish", blurb = "A squishy little ball that hops along after you",
		price = 350, colour = rgb(170, 206, 246), accent = rgb(30, 70, 120) },
	{ id = "PalSlime", tab = "Pals", kind = "pal", name = "Gloop", blurb = "A slime that splats along behind you",
		price = 450, colour = rgb(170, 236, 120), accent = rgb(39, 90, 20) },
	{ id = "PalJelly", tab = "Pals", kind = "pal", name = "Wibble", blurb = "A jelly cube that wobbles as it hops",
		price = 550, colour = rgb(255, 170, 196), accent = rgb(120, 30, 64) },
	{ id = "PalBee", tab = "Pals", kind = "pal", name = "Bumble", blurb = "A chubby honey bee buzzing at your shoulder",
		price = 700, colour = rgb(255, 214, 96), accent = rgb(90, 60, 6) },
	{ id = "PalCloud", tab = "Pals", kind = "pal", name = "Nimbus", blurb = "A sleepy cloud drifting along over you",
		price = 850, colour = rgb(226, 236, 255), accent = rgb(60, 80, 140) },
	{ id = "PalLava", tab = "Pals", kind = "pal", name = "Cinder", blurb = "A warm lava rock that glows and throws sparks",
		price = 1200, colour = rgb(255, 150, 70), accent = rgb(90, 30, 12) },

	-- EMOTES: played from the emote picker (G, D-pad right, or the pause menu), seen by everyone
	-- (EmoteService poses them on every client; moving ends one).
	-- TEN NOW, every one in keys with the whole body in it (the hundred-and-fifty-eighth pass, from your notes of
	-- 2026-10-31: "improve the existing emotes that can be bought, and add even more of them"; Poses, gen_poses.py).
	{ id = "Wave", tab = "Emotes", kind = "emote", name = "Wave", blurb = "Say hello, and mean it",
		price = 80, colour = rgb(159, 225, 203), accent = rgb(8, 80, 65) },
	{ id = "Shrug", tab = "Emotes", kind = "emote", name = "Shrug", blurb = "Palms up: who knows",
		price = 90, colour = rgb(214, 214, 230), accent = rgb(52, 52, 84) },
	{ id = "Bow", tab = "Emotes", kind = "emote", name = "Bow", blurb = "A slow bow, a hand on your heart",
		price = 100, colour = rgb(240, 214, 176), accent = rgb(96, 60, 20) },
	{ id = "SitSquish", tab = "Emotes", kind = "emote", name = "Sit and squish", blurb = "Sit down, squeeze a toy",
		price = 80, colour = rgb(244, 192, 209), accent = rgb(114, 36, 62) },
	{ id = "Stretch", tab = "Emotes", kind = "emote", name = "Stretch", blurb = "Up on your toes, and a long slow stretch",
		price = 100, colour = rgb(192, 221, 151), accent = rgb(39, 80, 10) },
	{ id = "Cheer", tab = "Emotes", kind = "emote", name = "Cheer", blurb = "Both arms up, and a bounce",
		price = 120, colour = rgb(255, 214, 120), accent = rgb(110, 64, 0) },
	{ id = "Spin", tab = "Emotes", kind = "emote", name = "Spin", blurb = "A wind-up, a spin and a ta-da",
		price = 150, colour = rgb(175, 169, 236), accent = rgb(38, 33, 92) },
	{ id = "Flex", tab = "Emotes", kind = "emote", name = "Flex", blurb = "Show them what you've got",
		price = 160, colour = rgb(246, 170, 150), accent = rgb(110, 40, 26) },
	{ id = "Groove", tab = "Emotes", kind = "emote", name = "Groove", blurb = "A little dance on the spot",
		price = 260, colour = rgb(160, 222, 246), accent = rgb(16, 72, 110) },
	-- THE AURA: calm, slow and sure of itself, a hand on the hip and the other arm rolling in slow waves, and a warm glow
	-- coming up round you while it plays (EmoteService). The one to want.
	{ id = "Aura", tab = "Emotes", kind = "emote", name = "Aura", blurb = "Calm, slow, unbothered. A glow comes with it",
		price = 450, colour = rgb(255, 228, 170), accent = rgb(120, 76, 10) },
	-- THE ROYAL WAVE (VIP only, the two-hundred-and-thirteenth pass): a hand behind the back, the other raised and
	-- turning at the wrist, the chin up and the head slowly crossing the crowd (gen_poses.py).
	{ id = "RoyalWave", tab = "Emotes", kind = "emote", name = "Royal wave", blurb = "The wave of someone they came to see. VIP only",
		earn = "vip", colour = rgb(206, 203, 246), accent = rgb(38, 33, 92) },

	-- PASSES: bought once, kept forever.
	-- THE STARTER PACK: a pass, so Roblox sells it only once; its tokens and the sea glass trail are given once a save
	-- (EconomyService.grantStarter). First in Featured, and gone from there once it is yours.
	{ id = "StarterPack", tab = "Passes", kind = "pass", name = "Starter pack", blurb = "500 tokens and the sea glass trail",
		robux = 99, passId = 2088020365, tokens = 500, gives = "SeaGlass", once = true, colour = rgb(130, 212, 190),
		accent = rgb(8, 80, 65) },
	{ id = "DoubleTokens", tab = "Passes", kind = "pass", name = "2x tokens", blurb = "Every run pays double",
		robux = 199, passId = 2088932368, colour = rgb(250, 199, 117), accent = rgb(99, 56, 6) },
	{ id = "VIP", tab = "Passes", kind = "pass", name = "VIP",
		blurb = "A fifth more every run, a free crate and half again from the chest daily, limited things early, the VIP "
			.. "lounge, VIP-only things, and a VIP tag over your head",
		robux = 299, passId = 2088644360, colour = rgb(206, 203, 246), accent = rgb(38, 33, 92) },
	{ id = "SecondChance", tab = "Passes", kind = "product", name = "Second chance", blurb = "Hardcore: back to your last checkpoint once",
		robux = 25, productId = 3730806011, colour = rgb(247, 193, 193), accent = rgb(121, 31, 31) },

	-- TOKEN PACKS: developer products, bought as often as you like.
	-- THE RUN BOOST (the two-hundred-and-thirteenth pass): your next finished run pays double, on top of anything else.
	-- Free for watching a short ad (ADS below), a few a day, or bought; kept until a run is finished. Never tokens
	-- outright, so an ad never floods the bay with them.
	{ id = "RunBoost", tab = "Tokens", kind = "product", name = "Run boost", blurb = "Your next finished run pays double",
		robux = 19, productId = 3731060443, ad = "boost", colour = rgb(176, 236, 160), accent = rgb(10, 70, 30) },
	{ id = "Pack100", tab = "Tokens", kind = "tokens", name = "100 tokens", blurb = "A handful",
		robux = 49, productId = 3730806017, tokens = 100, colour = rgb(250, 199, 117), accent = rgb(99, 56, 6) },
	{ id = "Pack300", tab = "Tokens", kind = "tokens", name = "300 tokens", blurb = "A jar full",
		robux = 129, productId = 3730806020, tokens = 300, colour = rgb(239, 159, 39), accent = rgb(99, 56, 6) },
	{ id = "Pack800", tab = "Tokens", kind = "tokens", name = "800 tokens", blurb = "A bucket of them",
		robux = 299, productId = 3730806026, tokens = 800, colour = rgb(186, 117, 23), accent = rgb(65, 36, 2) },
	{ id = "Pack2000", tab = "Tokens", kind = "tokens", name = "2000 tokens", blurb = "The whole till",
		robux = 649, productId = 3730806031, tokens = 2000, colour = rgb(133, 79, 11), accent = rgb(250, 238, 218) },

	-- BACKGROUNDS (the hundred-and-sixth pass, from your notes: "buy a very detailed highly sophisticated background
	-- ... with rarities"): the shop's own backdrop, one of the game's materials drawn behind it (ShopLook.THEMES, by
	-- `theme`), seen by you alone. With none on, the shop opens on one of the three everyone has, at random. All but the
	-- mythic one come out of the crate (never sold one by one); the mythic one is a Roblox pass.
	{ id = "BgCrate", tab = "Backgrounds", kind = "crate", name = "Background crate",
		blurb = "A background you do not have yet, at random", price = 250, colour = rgb(214, 160, 100),
		accent = rgb(92, 54, 26) },
	{ id = "BgHoney", tab = "Backgrounds", kind = "background", name = "Honey", blurb = "Honey dripping slowly down behind it all",
		theme = "honey", rarity = "common", earn = "crate", colour = rgb(250, 206, 96), accent = rgb(120, 66, 8) },
	{ id = "BgSlime", tab = "Backgrounds", kind = "background", name = "Slime", blurb = "Wobbling blobs that splat where you press",
		theme = "slime", rarity = "common", earn = "crate", colour = rgb(176, 244, 140), accent = rgb(30, 100, 40) },
	{ id = "BgSand", tab = "Backgrounds", kind = "background", name = "Sculpting sand", blurb = "Soft grains, and a footprint or two",
		theme = "sand", rarity = "common", earn = "crate", colour = rgb(240, 214, 160), accent = rgb(120, 86, 40) },
	{ id = "BgJelly", tab = "Backgrounds", kind = "background", name = "Jelly", blurb = "Pink jelly wobbling behind everything",
		theme = "jello", rarity = "rare", earn = "crate", colour = rgb(255, 150, 170), accent = rgb(120, 20, 50) },
	{ id = "BgBubbleWrap", tab = "Backgrounds", kind = "background", name = "Bubble wrap",
		blurb = "A whole sheet of it. Pop it anywhere", theme = "bubbleWrap", rarity = "rare", earn = "crate",
		colour = rgb(230, 244, 255), accent = rgb(70, 110, 160) },
	{ id = "BgCloud", tab = "Backgrounds", kind = "background", name = "Cloud", blurb = "Soft clouds drifting past, as high as the pools",
		theme = "cloud", rarity = "epic", earn = "crate", colour = rgb(176, 214, 244), accent = rgb(80, 120, 170) },
	{ id = "BgLava", tab = "Backgrounds", kind = "background", name = "Lava", blurb = "Glowing cracks, and sparks where you press",
		theme = "lava", rarity = "epic", earn = "crate", colour = rgb(230, 90, 30), accent = rgb(64, 22, 16) },
	{ id = "BgBackRooms", tab = "Backgrounds", kind = "background", name = "The back rooms",
		blurb = "Yellow wallpaper under a failing light. Something walks past", theme = "backRooms", rarity = "legendary",
		earn = "crate", colour = rgb(222, 204, 116), accent = rgb(96, 84, 40) },
	{ id = "BgHold", tab = "Backgrounds", kind = "background", name = "The Hold",
		blurb = "The deep under Harrow Bay, where the light goes out. It looks back", theme = "hold", rarity = "mythic",
		robux = 399, passId = 2088176373, colour = rgb(30, 110, 110), accent = rgb(4, 10, 14) },
}

local byId: { [string]: Item } = {}
for _, item in ipairs(ITEMS) do
	byId[item.id] = item
end

-- WHAT A FINISHED RUN PAYS, by the run length the lobby voted for. Hardcore pays half as much again,
-- a new personal best adds BEST_BONUS, a Roblox friend in the run a fifth more (FRIEND), and the 2x pass doubles
-- the lot. MIN_SECONDS: a run finished
-- faster than this was not played (a teleport to the finish), and pays nothing.
ShopCatalog.REWARD = {
	BASE = { short = 10, medium = 20, long = 30 },
	HARDCORE = 1.5,
	BEST_BONUS = 10,
	STORY = 150, -- finishing the story (all four levels): Hardcore and the 2x pass multiply it as they do a run
	TRUE = 300, -- the true ending (clocked in, the gates opened, his face seen), once a save: the 2x pass doubles it
	-- THE DAILY CHEST (EconomyService.claimDaily), by day of the streak; day seven's from then on while it lasts.
	DAILY = { 20, 30, 40, 50, 60, 80, 120 },
	CACHE = 25, -- a hidden cache found (one a level, Interactables.cache), once a save
	TELEPRINTER = 75, -- the teleprinter answered YES on a creamy keyboard (EconomyService.answeredTeleprinter), once a save
	MATERIAL = 5, -- a material stood on in a level for the first time (EconomyService.foundMaterial), once a save
	MATERIALS_ALL = 100, -- the last of them all found, on top of its own, with the swatch trail
	FRIEND = 1.2, -- a run finished with a Roblox friend in it (EconomyService.withFriend): a fifth more, before the 2x
	MIN_SECONDS = { short = 45, medium = 90, long = 135 },
}

-- ROBLOX BADGES (EconomyService.awardBadge), 0 until made. Make each one on the Creator Dashboard (the game, then
-- Engagement, Badges; a few a day are free), then put its id here. With 0 nothing is awarded and nothing errors, and
-- the paste check lists the ones still to make.
ShopCatalog.BADGES = {
	-- A level played to its end, by its level id: City Shore, Sky Pools, the Sunken City, the Flooded Halls, Hill House.
	level = { [1] = 0, [2] = 0, [3] = 0, [4] = 0, [5] = 0 },
	story = 0, -- the story played to its end
	storyHardcore = 0, -- a whole story in Hardcore, from City Shore, every level's time counted
	backRooms = 0, -- found the back rooms (too many falls in one run): a secret
	materials = 0, -- every material stood on in a level (EconomyService.foundMaterial)
	trueEnding = 0, -- the true ending: clocked in, the gates opened, his face seen (EconomyService.trueEnding)
}

function ShopCatalog.all(): { Item }
	return ITEMS
end

function ShopCatalog.get(id: any): Item?
	if typeof(id) ~= "string" then
		return nil
	end
	return byId[id]
end

function ShopCatalog.inTab(tab: string): { Item }
	local list = {}
	if tab == "Featured" then
		for _, id in ipairs(ShopCatalog.FEATURED) do
			local item = byId[id]
			if item then
				table.insert(list, item)
			end
		end
		return list
	end
	for _, item in ipairs(ITEMS) do
		if item.tab == tab then
			table.insert(list, item)
		end
	end
	return list
end

-- The item a pass id or product id belongs to (for the server's purchase handling).
function ShopCatalog.byPass(passId: number): Item?
	for _, item in ipairs(ITEMS) do
		if item.passId == passId and passId ~= 0 then
			return item
		end
	end
	return nil
end

function ShopCatalog.byProduct(productId: number): Item?
	for _, item in ipairs(ITEMS) do
		if item.productId == productId and productId ~= 0 then
			return item
		end
	end
	return nil
end

-- ===== THE PRICE ROBLOX CHARGES (the hundred-and-sixtieth pass) =====
--
-- An item's `robux` is a number written here, and the shop drew it as the price. Roblox sets its own prices now: each
-- country's, and the ones it tries out by itself for you when price testing is on (the Creator Dashboard's price
-- optimization, which wants the price shown to be the one Roblox gives), so for many players the button said one thing
-- and Roblox's window another. Now each item's price is asked of Roblox once a session on your screen
-- (askPrices, from ShopService), where Roblox answers with yours, and that is what is drawn (robuxFor); until it has
-- answered, or if it cannot, the number here. Roblox's window is what charges either way. A pass Roblox says is not for
-- sale (taken off sale on the Dashboard) is not on sale here either (onSale). On the server nothing is asked.
local said: { [string]: { robux: number?, onSale: boolean } } = {}
local asked = "not yet" -- "not yet", "asking", "answered"
local whenSaid: { () -> () } = {}

-- The Robux to show for `item`: Roblox's own price for you once it has said, this file's until then.
function ShopCatalog.robuxFor(item: Item): number?
	local known = said[item.id]
	return if known and known.robux then known.robux else item.robux
end

-- False only when Roblox has said the item is not for sale.
function ShopCatalog.onSale(item: Item): boolean
	local known = said[item.id]
	return not (known and not known.onSale)
end

-- Every Robux item with an id asked of Roblox, once; `answered` (if given) once they have been, or at once if they
-- have already.
function ShopCatalog.askPrices(answered: (() -> ())?)
	if asked == "answered" then
		if answered then
			task.spawn(answered)
		end
		return
	end
	if answered then
		table.insert(whenSaid, answered)
	end
	if asked == "asking" then
		return
	end
	asked = "asking"
	task.spawn(function()
		local MarketplaceService = game:GetService("MarketplaceService")
		for _, item in ipairs(ITEMS) do
			local isPass = item.passId ~= nil
			local id = if isPass then item.passId else item.productId
			if item.robux and type(id) == "number" and id ~= 0 then
				local ok, info = pcall(function()
					return MarketplaceService:GetProductInfo(id, if isPass then Enum.InfoType.GamePass else Enum.InfoType.Product)
				end)
				if ok and type(info) == "table" then
					local robux = tonumber((info :: any).PriceInRobux)
					said[item.id] = { robux = robux, onSale = robux ~= nil and (info :: any).IsForSale ~= false }
				end
			end
		end
		asked = "answered"
		for _, fn in ipairs(whenSaid) do
			task.spawn(fn)
		end
		table.clear(whenSaid)
	end)
end

-- ===== THE BACKGROUNDS' RARITIES AND THEIR CRATE (the hundred-and-sixth pass) =====
--
-- RARITY: each one's name on a tile, its word in a sentence, and its colour (a tile's pill, the crate's card).
export type Rarity = { name: string, word: string, colour: Color3 }
local RARITY: { [string]: Rarity } = {
	common = { name = "Common", word = "common", colour = rgb(112, 164, 96) },
	rare = { name = "Rare", word = "rare", colour = rgb(66, 134, 214) },
	epic = { name = "Epic", word = "epic", colour = rgb(146, 88, 214) },
	legendary = { name = "Legendary", word = "legendary", colour = rgb(222, 150, 28) },
	mythic = { name = "Mythic", word = "mythic", colour = rgb(214, 64, 84) },
}
ShopCatalog.RARITY = RARITY

-- THE CRATE: always a background you do not have yet. Its rarity comes by these odds (out of 100); once you have every
-- background of a rarity, the rarities you still lack something of share its chance, in proportion. Rolled on the
-- server only (EconomyService's "crate"), and its odds for you said before you pay (crateOdds). The mythic one is
-- never in it.
local CRATE: { id: string, order: { string }, odds: { [string]: number } } = {
	id = "BgCrate",
	order = { "common", "rare", "epic", "legendary" },
	odds = { common = 60, rare = 25, epic = 11, legendary = 4 },
}
ShopCatalog.CRATE = CRATE

-- What a crate could give someone who has what `has` says: for each rarity, in order, with a background still lacking,
-- those backgrounds and the rarity's odds; and the odds in all.
local function lacking(has: (string) -> boolean): ({ { rarity: string, items: { Item }, odds: number } }, number)
	local list = {}
	local total = 0
	for _, rarity in ipairs(CRATE.order) do
		local items = {}
		for _, item in ipairs(ITEMS) do
			if item.earn == "crate" and item.rarity == rarity and not has(item.id) then
				table.insert(items, item)
			end
		end
		local odds = CRATE.odds[rarity] or 0
		if #items > 0 and odds > 0 then
			table.insert(list, { rarity = rarity, items = items, odds = odds })
			total += odds
		end
	end
	return list, total
end

-- True once there is nothing left in the crate for you.
function ShopCatalog.crateDone(has: (string) -> boolean): boolean
	local _, total = lacking(has)
	return total <= 0
end

-- The background a crate gives, from two numbers from 0 to 1 (the server's own dice): `roll` picks the rarity by its
-- share of the odds, `pick` one of that rarity's you lack. Nil once you have them all.
function ShopCatalog.rollCrate(has: (string) -> boolean, roll: number, pick: number): Item?
	local list, total = lacking(has)
	if total <= 0 then
		return nil
	end
	local at = math.clamp(roll, 0, 0.999999) * total
	for _, entry in ipairs(list) do
		if at < entry.odds then
			local count = #entry.items
			return entry.items[math.clamp(math.floor(math.clamp(pick, 0, 0.999999) * count) + 1, 1, count)]
		end
		at -= entry.odds
	end
	local last = list[#list].items
	return last[#last]
end

-- THE ODDS IN WORDS, for someone who has what `has` says (a new player, without it): "Common 60%, rare 25%, ...", the
-- rarities you have every one of left out and the rest sharing their chance. Said before a crate is paid for.
function ShopCatalog.crateOdds(has: ((string) -> boolean)?): string
	local list, total = lacking(has or function(_: string): boolean
		return false
	end)
	local parts = {}
	for k, entry in ipairs(list) do
		local rarity = RARITY[entry.rarity]
		local share = entry.odds / total * 100
		local whole = math.floor(share + 0.5)
		local shown = if math.abs(share - whole) < 0.05 then tostring(whole) else ("%.1f"):format(share)
		table.insert(parts, ("%s %s%%"):format(if k == 1 then rarity.name else rarity.word, shown))
	end
	return table.concat(parts, ", ")
end

-- ===== HOW EACH TRAIL AND AURA LOOKS =====
--
-- Made of layers, so each one reads as the thing it is from across a room: a trail's RIBBON (its colours along it,
-- how wide, how long it lasts, how much it glows) and whatever it leaves behind (honey dripping, suds rising, sparks
-- flying); an aura's layers of motes around you, and a soft REAL light where the thing would glow. All of it from
-- Roblox's own particle textures, so nothing has to be uploaded.
local TEX = {
	sparkle = "rbxasset://textures/particles/sparkles_main.dds",
	smoke = "rbxasset://textures/particles/smoke_main.dds",
	fire = "rbxasset://textures/particles/fire_main.dds",
	spark = "rbxasset://textures/particles/fire_sparks_main.dds",
}
-- One layer of motes. Sizes and fades are spread evenly over a mote's life; colours too.
type Motes = { texture: string, colours: { Color3 }, size: { number }, fade: { number }, life: { number }, rate: number,
	speed: { number }, spread: number?, accel: Vector3?, drag: number?, spin: { number }?, light: number?, at: Vector3?,
	trailing: boolean?, streak: boolean? }
type Glow = { colour: Color3, brightness: number, range: number }
-- A STRAND of a trail (the hundred-and-seventh pass, from your notes: "the trail should be less wide ... more creative"):
-- a thin ribbon `width` studs across (the trail's, unless its own), drawn from `at` about your middle and moved there on
-- every screen by CosmeticsClient: "helix" round you (`radius` out, `speed` a second), "wave" side to side, "bob" up and
-- down, "bounce" hopping, "zigzag" crackling, "flutter" in a figure of eight, or "still". Its own colours along it, or
-- the trail's; `fade` how see-through it starts; `texture` one of Roblox's own, repeated along it.
type Strand = { at: Vector3, motion: string, radius: number?, speed: number?, phase: number?, colours: { Color3 }?,
	width: number?, fade: number?, texture: string? }
-- `spread`: each strand one of the trail's colours, spread along the list (the swatch).
type Ribbon = { colours: { Color3 }, width: number, life: number, light: number, strands: { Strand }, spread: boolean? }
type Look = { ribbon: Ribbon?, motes: { Motes }, glow: Glow? }

-- The swatch trail: every material's colour along one ribbon (the catalogue's own, filled in below).
local swatchColours: { Color3 } = {}

local LOOKS: { [string]: Look } = {
	-- TRAILS
	SoapSuds = {
		-- NO LINES (the two-hundred-and-twentieth pass, from your note of 2026-11-18: "do the same for the other trails too"):
		-- its wake on the ground instead (the first motes), as the cloud's.
		ribbon = { colours = { rgb(255, 255, 255), rgb(222, 238, 252), rgb(180, 212, 240) }, width = 0, life = 0, light = 0, strands = {} },
		motes = {
			-- Suds on the ground, spreading and going, and little bubbles lifting off them.
			{ texture = TEX.smoke, colours = { rgb(255, 255, 255), rgb(232, 244, 255) }, size = { 0.6, 1.3, 1.7 },
				fade = { 0.35, 0.6, 1 }, life = { 1.2, 1.8 }, rate = 12, speed = { 0.3, 0.8 }, spread = 80,
				accel = Vector3.new(0, 0.2, 0), drag = 1.6, spin = { -30, 30 }, at = Vector3.new(0, -2.6, 0), trailing = true },
			{ texture = TEX.sparkle, colours = { rgb(255, 255, 255), rgb(206, 232, 255) }, size = { 0.22, 0.3, 0 },
				fade = { 0.2, 0.5, 1 }, life = { 1, 1.6 }, rate = 6, speed = { 1, 2 }, spread = 30,
				accel = Vector3.new(0, 1.4, 0), drag = 0.8, spin = { -30, 30 }, light = 0.3, at = Vector3.new(0, -2.2, 0), trailing = true },
			{ texture = TEX.smoke, colours = { rgb(255, 255, 255), rgb(214, 234, 252) }, size = { 0.25, 0.45 },
				fade = { 0.35, 0.6, 1 }, life = { 0.9, 1.5 }, rate = 7, speed = { 0.2, 0.7 }, spread = 180,
				accel = Vector3.new(0, 1.4, 0), trailing = true },
			{ texture = TEX.sparkle, colours = { rgb(255, 255, 255) }, size = { 0.22, 0 }, fade = { 0.2, 1 },
				life = { 0.3, 0.6 }, rate = 3, speed = { 0, 0.3 }, light = 0.6, trailing = true },
		},
	},
	HoneyDrip = {
		-- NO LINES (the two-hundred-and-twentieth pass, from your note of 2026-11-18: "do the same for the other trails too"):
		-- its wake on the ground instead (the first motes), as the cloud's.
		ribbon = { colours = { rgb(255, 222, 130), rgb(239, 159, 39), rgb(168, 92, 10) }, width = 0, life = 0, light = 0, strands = {} },
		motes = {
			-- A warm amber sheen low behind you, and drops of it falling off your heels.
			{ texture = TEX.smoke, colours = { rgb(255, 214, 120), rgb(240, 160, 40) }, size = { 0.5, 1.1, 1.4 },
				fade = { 0.45, 0.7, 1 }, life = { 1.4, 2.2 }, rate = 9, speed = { 0.1, 0.4 }, spread = 70,
				accel = Vector3.new(0, -0.1, 0), drag = 2, spin = { -30, 30 }, light = 0.15, at = Vector3.new(0, -2.6, 0), trailing = true },
			{ texture = TEX.sparkle, colours = { rgb(255, 196, 70), rgb(236, 150, 30) }, size = { 0.2, 0.16, 0 },
				fade = { 0, 0.3, 1 }, life = { 0.6, 0.9 }, rate = 6, speed = { 0.2, 0.6 }, spread = 20,
				accel = Vector3.new(0, -14, 0), drag = 0.4, spin = { -30, 30 }, light = 0.4, at = Vector3.new(0, -1.2, 0), trailing = true },
			-- Honey dripping off it: round golden drops, falling.
			{ texture = TEX.smoke, colours = { rgb(255, 206, 90), rgb(214, 128, 20) }, size = { 0.26, 0.2, 0.14 },
				fade = { 0.05, 0.15, 1 }, life = { 0.7, 1.1 }, rate = 6, speed = { 0, 0.3 }, spread = 20,
				accel = Vector3.new(0, -24, 0), light = 0.35, at = Vector3.new(0, -0.4, 0), trailing = true },
			-- And a slow glint in it.
			{ texture = TEX.sparkle, colours = { rgb(255, 236, 170) }, size = { 0.28, 0 }, fade = { 0.2, 1 },
				life = { 0.4, 0.8 }, rate = 3, speed = { 0, 0.2 }, light = 0.9, trailing = true },
		},
		glow = { colour = rgb(255, 190, 90), brightness = 0.5, range = 7 },
	},
	SlimeGlow = {
		-- NO LINES (the two-hundred-and-twentieth pass, from your note of 2026-11-18: "do the same for the other trails too"):
		-- its wake on the ground instead (the first motes), as the cloud's.
		ribbon = { colours = { rgb(214, 255, 130), rgb(151, 196, 89), rgb(58, 140, 30) }, width = 0, life = 0, light = 0, strands = {} },
		motes = {
			-- A green ooze low behind you, and goo flicked off your feet.
			{ texture = TEX.smoke, colours = { rgb(190, 250, 120), rgb(120, 210, 70) }, size = { 0.6, 1.3, 1.6 },
				fade = { 0.4, 0.65, 1 }, life = { 1.3, 2 }, rate = 11, speed = { 0.2, 0.6 }, spread = 80,
				accel = Vector3.new(0, -0.05, 0), drag = 1.8, spin = { -30, 30 }, light = 0.25, at = Vector3.new(0, -2.6, 0), trailing = true },
			{ texture = TEX.sparkle, colours = { rgb(170, 245, 90) }, size = { 0.24, 0.18, 0 },
				fade = { 0, 0.3, 1 }, life = { 0.6, 1 }, rate = 6, speed = { 2, 3.5 }, spread = 45,
				accel = Vector3.new(0, -16, 0), drag = 0.3, spin = { -30, 30 }, light = 0.5, at = Vector3.new(0, -2.2, 0), trailing = true },
			{ texture = TEX.smoke, colours = { rgb(190, 255, 110), rgb(90, 180, 40) }, size = { 0.24, 0.16 },
				fade = { 0.05, 1 }, life = { 0.6, 0.9 }, rate = 5, speed = { 0, 0.3 }, spread = 25,
				accel = Vector3.new(0, -20, 0), light = 0.7, at = Vector3.new(0, -0.4, 0), trailing = true },
		},
		glow = { colour = rgb(160, 255, 100), brightness = 0.9, range = 8 },
	},
	-- NO LINES (the two-hundred-and-nineteenth pass, from your screenshot of 2026-11-18: "can you do something better
	-- instead of the 3 lines tailing at the back?"): its three wisps were thin ribbons, and read as three lines drawn
	-- behind you. Now a cloud's own wake: a soft mist rolling along the ground where you went, swelling as it thins, and
	-- little wisps curling up off your feet, with its puffs (PIECES) dropped in it.
	CloudPuff = {
		ribbon = { colours = { rgb(255, 255, 255), rgb(232, 230, 252) }, width = 0, life = 0, light = 0, strands = {} },
		motes = {
			-- The mist on the ground: big soft puffs left behind, spreading low, white into lilac.
			{ texture = TEX.smoke, colours = { rgb(246, 244, 255), rgb(226, 220, 255), rgb(200, 192, 248) }, size = { 1.1, 2.4, 3.2 },
				fade = { 0.3, 0.55, 1 }, life = { 1.8, 2.6 }, rate = 14, speed = { 0.3, 0.9 }, spread = 80,
				accel = Vector3.new(0, 0.12, 0), drag = 1.6, spin = { -20, 20 }, at = Vector3.new(0, -2.6, 0), trailing = true },
			-- The wisps: small, curling up and gone.
			{ texture = TEX.smoke, colours = { rgb(255, 255, 255), rgb(228, 226, 252) }, size = { 0.35, 0.9, 0 },
				fade = { 0.3, 0.55, 1 }, life = { 1, 1.6 }, rate = 7, speed = { 0.8, 1.5 }, spread = 25,
				accel = Vector3.new(0, 0.5, 0), drag = 1.2, spin = { -60, 60 }, at = Vector3.new(0, -2.2, 0), trailing = true },
			-- And a glint or two, as the Sky Pools' clouds have in the sun.
			{ texture = TEX.sparkle, colours = { rgb(255, 255, 255) }, size = { 0.16, 0 }, fade = { 0.3, 1 },
				life = { 0.5, 0.9 }, rate = 2, speed = { 0.2, 0.6 }, spread = 180, light = 0.4, at = Vector3.new(0, -1.8, 0),
				trailing = true },
		},
	},
	GreenRibbon = {
		-- NO LINES (the two-hundred-and-twentieth pass, from your note of 2026-11-18: "do the same for the other trails too"):
		-- its wake on the ground instead (the first motes), as the cloud's.
		ribbon = { colours = { rgb(150, 225, 160), rgb(58, 150, 88), rgb(30, 100, 60) }, width = 0, life = 0, light = 0, strands = {} },
		motes = {
			-- The key's green, a soft haze behind you with gold glints turning in it.
			{ texture = TEX.smoke, colours = { rgb(150, 230, 170), rgb(70, 170, 100) }, size = { 0.5, 1.1, 1.4 },
				fade = { 0.5, 0.75, 1 }, life = { 1.3, 2 }, rate = 8, speed = { 0.2, 0.5 }, spread = 80,
				accel = Vector3.new(0, 0.15, 0), drag = 1.6, spin = { -30, 30 }, at = Vector3.new(0, -2.6, 0), trailing = true },
			{ texture = TEX.sparkle, colours = { rgb(255, 226, 140), rgb(120, 220, 150) }, size = { 0.2, 0.26, 0 },
				fade = { 0.1, 0.4, 1 }, life = { 0.8, 1.4 }, rate = 5, speed = { 0.5, 1.2 }, spread = 60,
				accel = Vector3.new(0, 0.6, 0), drag = 1, spin = { -200, 200 }, light = 0.6, at = Vector3.new(0, -2.2, 0), trailing = true },
			{ texture = TEX.sparkle, colours = { rgb(200, 255, 200) }, size = { 0.2, 0 }, fade = { 0.3, 1 },
				life = { 0.4, 0.7 }, rate = 3, speed = { 0, 0.2 }, light = 0.6, trailing = true },
		},
	},
	SeaGlass = {
		-- NO LINES (the two-hundred-and-twentieth pass, from your note of 2026-11-18: "do the same for the other trails too"):
		-- its wake on the ground instead (the first motes), as the cloud's.
		ribbon = { colours = { rgb(214, 250, 238), rgb(130, 212, 190), rgb(70, 160, 140) }, width = 0, life = 0, light = 0, strands = {} },
		motes = {
			-- Sea foam on the ground behind you, pale green, and glints like wet glass.
			{ texture = TEX.smoke, colours = { rgb(230, 252, 246), rgb(170, 232, 214) }, size = { 0.6, 1.3, 1.7 },
				fade = { 0.4, 0.65, 1 }, life = { 1.3, 2 }, rate = 11, speed = { 0.3, 0.8 }, spread = 80,
				accel = Vector3.new(0, 0.1, 0), drag = 1.6, spin = { -30, 30 }, at = Vector3.new(0, -2.6, 0), trailing = true },
			{ texture = TEX.sparkle, colours = { rgb(220, 255, 246) }, size = { 0.2, 0 },
				fade = { 0.1, 1 }, life = { 0.4, 0.8 }, rate = 5, speed = { 0.3, 0.8 }, spread = 90,
				accel = Vector3.new(0, 0.4, 0), drag = 1, spin = { -30, 30 }, light = 0.6, at = Vector3.new(0, -2.2, 0), trailing = true },
			{ texture = TEX.sparkle, colours = { rgb(235, 255, 250), rgb(150, 230, 210) }, size = { 0, 0.32, 0 },
				fade = { 0.1, 1 }, life = { 0.4, 0.8 }, rate = 7, speed = { 0, 0.3 }, light = 1, trailing = true },
		},
	},
	Swatch = {
		-- NO LINES (the two-hundred-and-twentieth pass, from your note of 2026-11-18: "do the same for the other trails too"):
		-- its wake on the ground instead (the first motes), as the cloud's.
		ribbon = { colours = { rgb(255, 255, 255) }, width = 0, life = 0, light = 0, strands = {} },
		motes = {
			-- Every material's colour in a soft mist behind you, glittering.
			{ texture = TEX.smoke, colours = { rgb(255, 196, 214), rgb(196, 220, 255), rgb(214, 250, 190), rgb(255, 236, 170) }, size = { 0.6, 1.3, 1.6 },
				fade = { 0.45, 0.7, 1 }, life = { 1.4, 2.1 }, rate = 11, speed = { 0.3, 0.7 }, spread = 80,
				accel = Vector3.new(0, 0.15, 0), drag = 1.6, spin = { -30, 30 }, at = Vector3.new(0, -2.6, 0), trailing = true },
			{ texture = TEX.sparkle, colours = { rgb(255, 150, 190), rgb(140, 200, 255), rgb(170, 240, 140), rgb(255, 220, 110) }, size = { 0.2, 0.26, 0 },
				fade = { 0.1, 0.4, 1 }, life = { 0.7, 1.2 }, rate = 7, speed = { 0.8, 1.6 }, spread = 70,
				accel = Vector3.new(0, 0.8, 0), drag = 1, spin = { -200, 200 }, light = 0.6, at = Vector3.new(0, -2.2, 0), trailing = true },
			{ texture = TEX.sparkle, colours = { rgb(255, 255, 255) }, size = { 0.24, 0 }, fade = { 0.2, 1 },
				life = { 0.4, 0.8 }, rate = 4, speed = { 0, 0.3 }, light = 0.8, trailing = true },
		},
	},
	LavaRibbon = {
		-- NO LINES (the two-hundred-and-twentieth pass, from your note of 2026-11-18: "do the same for the other trails too"):
		-- its wake on the ground instead (the first motes), as the cloud's.
		ribbon = { colours = { rgb(255, 236, 150), rgb(255, 128, 32), rgb(176, 34, 12), rgb(52, 22, 22) }, width = 0, life = 0, light = 0, strands = {} },
		motes = {
			-- Smoke rolling off the ground where you went, dark into ash, and the heat shimmering low.
			{ texture = TEX.smoke, colours = { rgb(120, 90, 80), rgb(70, 60, 60) }, size = { 0.6, 1.4, 2 },
				fade = { 0.45, 0.7, 1 }, life = { 1.4, 2.2 }, rate = 9, speed = { 0.5, 1 }, spread = 50,
				accel = Vector3.new(0, 1, 0), drag = 1.4, spin = { -30, 30 }, at = Vector3.new(0, -2.6, 0), trailing = true },
			{ texture = TEX.fire, colours = { rgb(255, 170, 70), rgb(255, 110, 40) }, size = { 0.5, 1, 0 },
				fade = { 0.6, 0.8, 1 }, life = { 0.4, 0.7 }, rate = 10, speed = { 0.2, 0.5 }, spread = 60,
				accel = Vector3.new(0, 0.6, 0), drag = 1.2, spin = { -30, 30 }, light = 0.8, at = Vector3.new(0, -2.6, 0), trailing = true },
			{ texture = TEX.spark, colours = { rgb(255, 214, 110), rgb(255, 96, 24) }, size = { 0.2, 0.12, 0 },
				fade = { 0, 0.2, 1 }, life = { 0.5, 1.1 }, rate = 12, speed = { 1, 3 }, spread = 60,
				accel = Vector3.new(0, 3, 0), spin = { -120, 120 }, light = 1, trailing = true },
			{ texture = TEX.smoke, colours = { rgb(70, 60, 60) }, size = { 0.3, 0.8 }, fade = { 0.6, 1 },
				life = { 1, 1.6 }, rate = 3, speed = { 0.2, 0.5 }, accel = Vector3.new(0, 1.5, 0), trailing = true },
		},
		glow = { colour = rgb(255, 128, 48), brightness = 1.1, range = 9 },
	},
	JellyRibbon = {
		-- NO LINES (the two-hundred-and-twentieth pass, from your note of 2026-11-18: "do the same for the other trails too"):
		-- its wake on the ground instead (the first motes), as the cloud's.
		ribbon = { colours = { rgb(255, 196, 214), rgb(236, 96, 120), rgb(186, 50, 84) }, width = 0, life = 0, light = 0, strands = {} },
		motes = {
			-- A pink jelly sheen low behind you, and beads of it bouncing off your feet.
			{ texture = TEX.smoke, colours = { rgb(255, 196, 214), rgb(240, 120, 150) }, size = { 0.5, 1.1, 1.4 },
				fade = { 0.45, 0.7, 1 }, life = { 1.3, 2 }, rate = 10, speed = { 0.2, 0.5 }, spread = 80,
				accel = Vector3.new(0, -0.05, 0), drag = 1.8, spin = { -30, 30 }, light = 0.2, at = Vector3.new(0, -2.6, 0), trailing = true },
			{ texture = TEX.sparkle, colours = { rgb(255, 150, 180) }, size = { 0.24, 0.2, 0 },
				fade = { 0, 0.3, 1 }, life = { 0.7, 1.1 }, rate = 6, speed = { 2.5, 4 }, spread = 40,
				accel = Vector3.new(0, -18, 0), drag = 0.2, spin = { -30, 30 }, light = 0.4, at = Vector3.new(0, -2.2, 0), trailing = true },
			{ texture = TEX.smoke, colours = { rgb(255, 150, 180), rgb(236, 96, 120) }, size = { 0.3, 0.22 },
				fade = { 0.15, 0.3, 1 }, life = { 0.6, 1 }, rate = 5, speed = { 0, 0.3 }, spread = 25,
				accel = Vector3.new(0, -12, 0), light = 0.4, at = Vector3.new(0, -0.4, 0), trailing = true },
		},
	},
	Sprinkles = {
		-- NO LINES (the two-hundred-and-twentieth pass, from your note of 2026-11-18: "do the same for the other trails too"):
		-- its wake on the ground instead (the first motes), as the cloud's.
		ribbon = { colours = { rgb(255, 255, 255), rgb(255, 236, 246) }, width = 0, life = 0, light = 0, strands = {} },
		motes = {
			-- A dusting of sugar on the ground behind you, glittering.
			{ texture = TEX.smoke, colours = { rgb(255, 246, 250), rgb(255, 226, 240) }, size = { 0.4, 0.9, 1.2 },
				fade = { 0.5, 0.75, 1 }, life = { 1.1, 1.7 }, rate = 9, speed = { 0.2, 0.6 }, spread = 80,
				accel = Vector3.new(0, 0.1, 0), drag = 1.6, spin = { -30, 30 }, at = Vector3.new(0, -2.6, 0), trailing = true },
			{ texture = TEX.sparkle, colours = { rgb(255, 255, 255) }, size = { 0.14, 0 },
				fade = { 0.1, 1 }, life = { 0.4, 0.8 }, rate = 6, speed = { 0.2, 0.6 }, spread = 90,
				accel = Vector3.new(0, 0.2, 0), drag = 1, spin = { -30, 30 }, light = 0.7, at = Vector3.new(0, -2.2, 0), trailing = true },
			{ texture = TEX.sparkle, colours = { rgb(255, 120, 170) }, size = { 0.2, 0.2 }, fade = { 0, 1 }, life = { 0.8, 1.2 },
				rate = 5, speed = { 1, 2.5 }, spread = 70, accel = Vector3.new(0, -16, 0), spin = { -260, 260 }, trailing = true },
			{ texture = TEX.sparkle, colours = { rgb(110, 190, 255) }, size = { 0.2, 0.2 }, fade = { 0, 1 }, life = { 0.8, 1.2 },
				rate = 5, speed = { 1, 2.5 }, spread = 70, accel = Vector3.new(0, -16, 0), spin = { -260, 260 }, trailing = true },
			{ texture = TEX.sparkle, colours = { rgb(255, 214, 90) }, size = { 0.2, 0.2 }, fade = { 0, 1 }, life = { 0.8, 1.2 },
				rate = 5, speed = { 1, 2.5 }, spread = 70, accel = Vector3.new(0, -16, 0), spin = { -260, 260 }, trailing = true },
		},
	},
	-- AURAS
	Bubbles = {
		motes = {
			{ texture = TEX.smoke, colours = { rgb(240, 248, 255), rgb(181, 212, 244) }, size = { 0.3, 0.55 },
				fade = { 0.45, 0.6, 1 }, life = { 1.4, 2.2 }, rate = 8, speed = { 0.4, 1 }, spread = 180,
				accel = Vector3.new(0, 1.6, 0) },
			{ texture = TEX.sparkle, colours = { rgb(255, 255, 255) }, size = { 0.2, 0 }, fade = { 0.2, 1 },
				life = { 0.4, 0.8 }, rate = 5, speed = { 0.2, 0.6 }, spread = 180, light = 0.8, accel = Vector3.new(0, 1, 0) },
		},
	},
	Mist = {
		motes = {
			{ texture = TEX.smoke, colours = { rgb(235, 250, 244), rgb(200, 232, 222) }, size = { 1.6, 3.4 },
				fade = { 0.72, 0.8, 1 }, life = { 2, 3.2 }, rate = 6, speed = { 0.2, 0.6 }, spread = 180,
				accel = Vector3.new(0, 0.15, 0), drag = 1, at = Vector3.new(0, -1.8, 0) },
			{ texture = TEX.sparkle, colours = { rgb(225, 245, 255) }, size = { 0.12, 0 }, fade = { 0.3, 1 },
				life = { 0.6, 1 }, rate = 3, speed = { 0.2, 0.5 }, spread = 180, light = 0.4, accel = Vector3.new(0, -1, 0) },
		},
	},
	Embers = {
		motes = {
			-- THE EMBERS, many and bright, rising and turning as they cool: white-hot, then gold, then orange, then a
			-- dull red, then out.
			{ texture = TEX.spark, colours = { rgb(255, 250, 222), rgb(255, 200, 90), rgb(255, 112, 30), rgb(150, 30, 12) },
				size = { 0.34, 0.24, 0.12, 0 }, fade = { 0, 0.05, 0.3, 1 }, life = { 1.4, 2.6 }, rate = 34, speed = { 1.5, 4 },
				spread = 180, accel = Vector3.new(0, 5, 0), drag = 1.4, spin = { -120, 120 }, light = 1 },
			-- SPARKS SPITTING UP out of it: fast and thin, drawn out along their flight, falling back.
			{ texture = TEX.spark, colours = { rgb(255, 244, 200), rgb(255, 150, 50) }, size = { 0.14, 0.06 },
				fade = { 0, 1 }, life = { 0.35, 0.7 }, rate = 12, speed = { 7, 11 }, spread = 28,
				accel = Vector3.new(0, -6, 0), light = 1, streak = true, at = Vector3.new(0, -1.6, 0) },
			-- FLAME licking up round your feet.
			{ texture = TEX.fire, colours = { rgb(255, 214, 110), rgb(255, 120, 30), rgb(200, 50, 20) }, size = { 0.9, 0.55, 0 },
				fade = { 0.25, 0.45, 1 }, life = { 0.5, 0.9 }, rate = 14, speed = { 0.8, 1.8 }, spread = 35,
				accel = Vector3.new(0, 3, 0), light = 1, at = Vector3.new(0, -2.3, 0) },
			-- THE HEAT round you: a faint warm haze in the air.
			{ texture = TEX.smoke, colours = { rgb(255, 150, 70), rgb(200, 90, 40) }, size = { 1.8, 3.2 },
				fade = { 0.88, 0.94, 1 }, life = { 1.2, 1.8 }, rate = 4, speed = { 0.4, 0.9 }, spread = 180,
				accel = Vector3.new(0, 1.5, 0), light = 0.4 },
			-- Ash drifting off.
			{ texture = TEX.smoke, colours = { rgb(96, 84, 84) }, size = { 0.2, 0.45 }, fade = { 0.6, 1 },
				life = { 1.5, 2.5 }, rate = 4, speed = { 0.3, 0.8 }, spread = 180, accel = Vector3.new(0, 1.2, 0) },
		},
		glow = { colour = rgb(255, 136, 56), brightness = 1.4, range = 11 },
	},
	-- AUTUMN LEAVES (limited): a rust and amber ribbon fluttering, and a little dust of gold off it.
	AutumnLeaves = {
		-- NO LINES (the two-hundred-and-twentieth pass, from your note of 2026-11-18: "do the same for the other trails too"):
		-- its wake on the ground instead (the first motes), as the cloud's.
		ribbon = { colours = { rgb(255, 214, 140), rgb(236, 128, 52), rgb(150, 50, 24) }, width = 0, life = 0, light = 0, strands = {} },
		motes = {
			-- A warm dust kicked up behind you, gold in the low sun.
			{ texture = TEX.smoke, colours = { rgb(250, 214, 160), rgb(220, 150, 90) }, size = { 0.5, 1.2, 1.5 },
				fade = { 0.5, 0.75, 1 }, life = { 1.3, 2 }, rate = 9, speed = { 0.3, 0.8 }, spread = 70,
				accel = Vector3.new(0, 0.2, 0), drag = 1.5, spin = { -30, 30 }, at = Vector3.new(0, -2.6, 0), trailing = true },
			{ texture = TEX.sparkle, colours = { rgb(255, 214, 150) }, size = { 0.16, 0 }, fade = { 0.2, 1 },
				life = { 0.5, 0.9 }, rate = 3, speed = { 0, 0.2 }, light = 0.5, trailing = true },
		},
	},
	-- FIRST FROST (limited): frost glinting round you and fine snow, cold and slow; a pale blue light.
	FirstFrost = {
		motes = {
			{ texture = TEX.sparkle, colours = { rgb(240, 250, 255), rgb(190, 226, 255) }, size = { 0, 0.32, 0 },
				fade = { 0, 1 }, life = { 0.8, 1.4 }, rate = 12, speed = { 0.6, 1.4 }, spread = 180, drag = 3, light = 0.8 },
			{ texture = TEX.sparkle, colours = { rgb(255, 255, 255) }, size = { 0.12, 0.1 }, fade = { 0.2, 1 },
				life = { 2, 3 }, rate = 8, speed = { 0.4, 0.9 }, spread = 180, accel = Vector3.new(0, -1.2, 0), drag = 1,
				at = Vector3.new(0, 2.8, 0) },
		},
		glow = { colour = rgb(200, 230, 255), brightness = 0.45, range = 8 },
	},
	-- WINTER WOOL (limited, January's): two strands of wool, red and cream, twisting round each other like a knitted
	-- cord, and a few snowflakes off it.
	WinterWool = {
		-- NO LINES (the two-hundred-and-twentieth pass, from your note of 2026-11-18: "do the same for the other trails too"):
		-- its wake on the ground instead (the first motes), as the cloud's.
		ribbon = { colours = { rgb(236, 90, 84), rgb(200, 40, 48), rgb(150, 24, 36) }, width = 0, life = 0, light = 0, strands = {} },
		motes = {
			-- A soft powder of snow kicked up behind you, and little flakes of it drifting down.
			{ texture = TEX.smoke, colours = { rgb(255, 255, 255), rgb(255, 230, 230) }, size = { 0.5, 1.2, 1.5 },
				fade = { 0.4, 0.7, 1 }, life = { 1.3, 2 }, rate = 11, speed = { 0.3, 0.8 }, spread = 80,
				accel = Vector3.new(0, 0.15, 0), drag = 1.6, spin = { -30, 30 }, at = Vector3.new(0, -2.6, 0), trailing = true },
			{ texture = TEX.sparkle, colours = { rgb(255, 255, 255) }, size = { 0.18, 0.12 },
				fade = { 0.1, 1 }, life = { 1.4, 2.2 }, rate = 5, speed = { 0.2, 0.5 }, spread = 180,
				accel = Vector3.new(0, -0.6, 0), drag = 1, spin = { -60, 60 }, light = 0.4, at = Vector3.new(0, 0, 0), trailing = true },
			{ texture = TEX.sparkle, colours = { rgb(255, 255, 255) }, size = { 0.14, 0.1 }, fade = { 0.2, 1 },
				life = { 1.2, 1.8 }, rate = 4, speed = { 0.1, 0.4 }, spread = 180, accel = Vector3.new(0, -1.2, 0),
				trailing = true },
		},
	},
	-- HOT COCOA (limited, January's): the steam curling up off you, and a warm, low light.
	HotCocoa = {
		motes = {
			{ texture = TEX.smoke, colours = { rgb(255, 250, 244), rgb(240, 230, 220) }, size = { 0.3, 0.9 },
				fade = { 0.6, 0.8, 1 }, life = { 2.2, 3.2 }, rate = 5, speed = { 0.3, 0.6 }, spread = 25,
				accel = Vector3.new(0, 0.5, 0), drag = 0.6, at = Vector3.new(0, 1.2, 0) },
		},
		glow = { colour = rgb(255, 196, 140), brightness = 0.5, range = 8 },
	},
	-- THE GILDED CROWN (VIP): slow gold glints falling from the crown, and its light on your face.
	GildedCrown = {
		motes = {
			{ texture = TEX.sparkle, colours = { rgb(255, 236, 170), rgb(250, 199, 117) }, size = { 0, 0.3, 0 },
				fade = { 0, 1 }, life = { 0.8, 1.4 }, rate = 6, speed = { 0.2, 0.6 }, spread = 180,
				accel = Vector3.new(0, -0.8, 0), light = 0.9, at = Vector3.new(0, 2.5, 0) },
		},
		glow = { colour = rgb(255, 214, 130), brightness = 0.55, range = 7 },
	},
	-- LANTERN NIGHT (limited): warm motes rising like sparks off paper lanterns, and their light.
	LanternNight = {
		motes = {
			{ texture = TEX.sparkle, colours = { rgb(255, 220, 160), rgb(255, 170, 90) }, size = { 0, 0.3, 0 },
				fade = { 0, 1 }, life = { 1.6, 2.6 }, rate = 7, speed = { 0.5, 1 }, spread = 40, accel = Vector3.new(0, 0.8, 0),
				light = 0.9 },
		},
		glow = { colour = rgb(255, 196, 120), brightness = 0.7, range = 9 },
	},
	-- THE GOLD LEAF (VIP): two gold ribbons fluttering out of step, one glinting all along, gold flakes turning as they
	-- drift down behind you, and a warm light.
	GoldLeaf = {
		-- NO LINES (the two-hundred-and-twentieth pass, from your note of 2026-11-18: "do the same for the other trails too"):
		-- its wake on the ground instead (the first motes), as the cloud's.
		ribbon = { colours = { rgb(255, 240, 190), rgb(250, 199, 117), rgb(196, 140, 40) }, width = 0, life = 0, light = 0, strands = {} },
		motes = {
			-- Gold dust settling behind you, catching the light.
			{ texture = TEX.smoke, colours = { rgb(255, 236, 170), rgb(240, 196, 90) }, size = { 0.4, 1, 1.3 },
				fade = { 0.5, 0.75, 1 }, life = { 1.3, 2 }, rate = 9, speed = { 0.2, 0.5 }, spread = 80,
				accel = Vector3.new(0, 0.1, 0), drag = 1.6, spin = { -30, 30 }, light = 0.3, at = Vector3.new(0, -2.6, 0), trailing = true },
			{ texture = TEX.sparkle, colours = { rgb(255, 226, 140), rgb(255, 246, 200) }, size = { 0.2, 0 },
				fade = { 0.1, 1 }, life = { 1, 1.6 }, rate = 9, speed = { 0.2, 0.6 }, spread = 180,
				accel = Vector3.new(0, -0.8, 0), drag = 1, spin = { -200, 200 }, light = 0.8, at = Vector3.new(0, -0.6, 0), trailing = true },
			{ texture = TEX.sparkle, colours = { rgb(255, 240, 180), rgb(250, 199, 117) }, size = { 0.18, 0.26, 0 },
				fade = { 0.1, 1 }, life = { 1.2, 1.8 }, rate = 8, speed = { 0.1, 0.4 }, spread = 180,
				accel = Vector3.new(0, -1.4, 0), drag = 1.5, spin = { -120, 120 }, light = 0.7, trailing = true },
		},
		glow = { colour = rgb(255, 214, 140), brightness = 0.55, range = 8 },
	},
	Sparkle = {
		motes = {
			{ texture = TEX.sparkle, colours = { rgb(255, 240, 180), rgb(250, 199, 117) }, size = { 0, 0.4, 0 },
				fade = { 0, 1 }, life = { 0.6, 1.2 }, rate = 16, speed = { 1.5, 2.5 }, spread = 180, drag = 4, light = 1 },
			{ texture = TEX.sparkle, colours = { rgb(255, 226, 150) }, size = { 0.12, 0 }, fade = { 0.2, 1 },
				life = { 1, 1.6 }, rate = 8, speed = { 0.2, 0.6 }, spread = 180, accel = Vector3.new(0, -0.6, 0), light = 0.8 },
		},
		glow = { colour = rgb(255, 214, 130), brightness = 0.6, range = 8 },
	},
	Snowfall = {
		motes = {
			{ texture = TEX.sparkle, colours = { rgb(255, 255, 255), rgb(225, 238, 255) }, size = { 0.16, 0.14 },
				fade = { 0.15, 1 }, life = { 2.2, 3.2 }, rate = 14, speed = { 1, 2 }, spread = 180,
				accel = Vector3.new(0, -2.4, 0), drag = 1.2, spin = { -60, 60 }, light = 0.3, at = Vector3.new(0, 3.2, 0) },
		},
	},
	Fireflies = {
		motes = {
			{ texture = TEX.smoke, colours = { rgb(236, 255, 150), rgb(200, 255, 110) }, size = { 0, 0.26, 0.2, 0 },
				fade = { 1, 0.1, 0.15, 1 }, life = { 2, 3.5 }, rate = 5, speed = { 0.4, 0.9 }, spread = 180,
				accel = Vector3.new(0, 0.2, 0), drag = 1, light = 1 },
		},
		glow = { colour = rgb(220, 255, 140), brightness = 0.45, range = 7 },
	},
	-- THE TWO-HUNDRED-AND-SIXTEENTH PASS
	Petals = {
		-- NO LINES (the two-hundred-and-twentieth pass, from your note of 2026-11-18: "do the same for the other trails too"):
		-- its wake on the ground instead (the first motes), as the cloud's.
		ribbon = { colours = { rgb(255, 236, 242), rgb(255, 196, 214), rgb(240, 150, 180) }, width = 0, life = 0, light = 0, strands = {} },
		motes = {
			-- A blush of pink haze low behind you, where the petals fall.
			{ texture = TEX.smoke, colours = { rgb(255, 230, 240), rgb(255, 196, 220) }, size = { 0.5, 1.2, 1.5 },
				fade = { 0.45, 0.7, 1 }, life = { 1.4, 2.1 }, rate = 10, speed = { 0.3, 0.7 }, spread = 80,
				accel = Vector3.new(0, 0.15, 0), drag = 1.6, spin = { -30, 30 }, at = Vector3.new(0, -2.6, 0), trailing = true },
			{ texture = TEX.sparkle, colours = { rgb(255, 214, 228) }, size = { 0.18, 0 }, fade = { 0.2, 1 },
				life = { 0.6, 1 }, rate = 3, speed = { 0, 0.3 }, light = 0.4, trailing = true },
		},
	},
	CookieCrumbs = {
		-- NO LINES (the two-hundred-and-twentieth pass, from your note of 2026-11-18: "do the same for the other trails too"):
		-- its wake on the ground instead (the first motes), as the cloud's.
		ribbon = { colours = { rgb(240, 206, 150), rgb(214, 160, 96) }, width = 0, life = 0, light = 0, strands = {} },
		motes = {
			-- A puff of flour and fine crumbs behind you.
			{ texture = TEX.smoke, colours = { rgb(250, 236, 214), rgb(226, 196, 150) }, size = { 0.4, 1, 1.3 },
				fade = { 0.45, 0.7, 1 }, life = { 1.1, 1.8 }, rate = 10, speed = { 0.4, 1 }, spread = 70,
				accel = Vector3.new(0, 0.1, 0), drag = 1.8, spin = { -30, 30 }, at = Vector3.new(0, -2.6, 0), trailing = true },
			{ texture = TEX.sparkle, colours = { rgb(226, 182, 120), rgb(110, 66, 36) }, size = { 0.14, 0.1 }, fade = { 0, 1 },
				life = { 0.5, 0.9 }, rate = 6, speed = { 1, 2 }, spread = 60, accel = Vector3.new(0, -18, 0), trailing = true },
		},
	},
	RubberDucks = {
		motes = {
			{ texture = TEX.smoke, colours = { rgb(220, 240, 255) }, size = { 0.2, 0.5, 0 }, fade = { 0.6, 0.85, 1 },
				life = { 1.2, 2 }, rate = 4, speed = { 0.2, 0.5 }, spread = 180, at = Vector3.new(0, -2.4, 0) },
		},
	},
	Starlight = {
		motes = {
			{ texture = TEX.sparkle, colours = { rgb(255, 255, 255), rgb(206, 196, 255) }, size = { 0, 0.42, 0 },
				fade = { 0, 1 }, life = { 0.8, 1.6 }, rate = 12, speed = { 2, 3 }, spread = 180, drag = 4, light = 1 },
			{ texture = TEX.sparkle, colours = { rgb(190, 180, 255) }, size = { 0.1, 0 }, fade = { 0.3, 1 },
				life = { 1.2, 2 }, rate = 6, speed = { 0.3, 0.8 }, spread = 180, light = 0.6 },
		},
		glow = { colour = rgb(200, 190, 255), brightness = 0.5, range = 8 },
	},
}

-- ===== THE THINGS THEMSELVES (the ninety-seventh pass) =====
--
-- Every trail, aura and set of steps as small modelled things too (blender/gen_cosmetics.py: ReplicatedStorage.Assets.
-- Cosmetics), drawn and moved on every screen by CosmeticsClient (trails and auras) and StepService (steps), over the
-- looks above. A piece: its mesh ("Ball" is a plain ball), its largest side in studs, its colours (one picked each
-- time), Glass or not, how see-through and how glossy, and for the hot ones the colour they cool to. A trail lets one go
-- every `every` studs you cover, `life` seconds each; an aura keeps `count` round you, `radius` out. Motions: a trail's
-- "toss" (thrown, tumbling, bouncing once), "drip" (falls, spreads where it lands), "splat" (lands flat, wobbling),
-- "bounce" (bounces twice), "rise" (floats up wobbling and pops), "puff" (swells and thins where it was left),
-- "flutter" (drifts down turning); an aura's "orbit" (circling, twinkling), "rise", "fall", "hover" (wandering) and
-- "drift" (low, slow, at your feet); steps' "press" (pressed into the ground).
export type Piece = { mesh: string, size: number, colours: { Color3 }, material: string?, alpha: number?, shine: number?,
	cool: Color3?, wings: string?, light: Color3?, lights: number?, yaw: number? }
-- AN AURA'S RING (the hundred-and-seventh pass: "auras ... even cooler, more pronounced"): `count` of `piece` lying in a
-- circle round your feet, `radius` out, turning `spin` a second; or with `halo`, over your head, `height` above your
-- middle.
export type Ring = { count: number, radius: number, spin: number, halo: boolean?, height: number?, piece: Piece }
export type Pieces = { motion: string, life: number, every: number?, count: number?, radius: number?, spin: number?,
	pieces: { Piece }, ring: Ring? }
local ASH = rgb(70, 62, 60)
local PIECES: { [string]: Pieces } = {
	-- TRAILS
	-- MADE FOR THEM (the two-hundred-and-fourteenth pass, from your note of 2026-11-14: "improve the existing trails and
	-- steps with your new tools"): every piece below a textured mesh from Studio's generator (Assets.Cosmetics: soap
	-- foam, a slime blob, a cloud, a jelly bean, a satin bow, sea glass; for the steps a jelly heart, a star
	-- cookie, a honey paw, a foam sole), where there were glass beads and plain shapes. A textured piece is its own
	-- colour; its `colours` are what a screen without it draws.
	SoapSuds = { motion = "rise", every = 1.0, life = 1.8, pieces = {
		{ mesh = "Cos_SoapFoam", size = 0.55, colours = { rgb(244, 250, 255) }, shine = 0.08 } } },
	HoneyDrip = { motion = "drip", every = 1.0, life = 3.2, pieces = {
		-- (Its own drop, amber and glossy: the generator made honey red, twice.)
		{ mesh = "Cos_HoneyDrop", size = 0.46, colours = { rgb(255, 196, 70), rgb(236, 154, 32) }, shine = 0.35 } } },
	SlimeGlow = { motion = "splat", every = 1.4, life = 3.4, pieces = {
		{ mesh = "Cos_SlimeBlob", size = 0.95, colours = { rgb(170, 245, 90) }, shine = 0.3 } } },
	CloudPuff = { motion = "puff", every = 1.2, life = 2.3, pieces = {
		{ mesh = "Cos_CloudPuff", size = 1.0, colours = { rgb(255, 255, 255) }, shine = 0 } } },
	JellyRibbon = { motion = "bounce", every = 0.8, life = 2.4, pieces = {
		{ mesh = "Cos_JellyBean", size = 0.42, colours = { rgb(255, 150, 180) }, shine = 0.3 } } },
	Sprinkles = { motion = "toss", every = 0.45, life = 2.6, pieces = {
		{ mesh = "Cos_Sprinkle", size = 0.34, colours = { rgb(255, 120, 170), rgb(110, 190, 255), rgb(255, 214, 90),
			rgb(255, 255, 255), rgb(140, 230, 140), rgb(196, 150, 255) }, shine = 0.15 } } },
	LavaRibbon = { motion = "toss", every = 0.85, life = 2.2, pieces = {
		{ mesh = "Cos_Ember_1", size = 0.34, colours = { rgb(255, 170, 70), rgb(255, 120, 40) }, cool = ASH, shine = 0.05 },
		{ mesh = "Cos_Ember_2", size = 0.3, colours = { rgb(255, 196, 96), rgb(255, 140, 50) }, cool = ASH, shine = 0.05 } } },
	GreenRibbon = { motion = "flutter", every = 1.1, life = 2.0, pieces = {
		{ mesh = "Cos_Bow", size = 0.4, colours = { rgb(96, 196, 126) }, shine = 0.3 } } },
	Swatch = { motion = "toss", every = 0.75, life = 2.3, pieces = {
		{ mesh = "Cos_Gem", size = 0.3, colours = swatchColours, shine = 0.2 } } },
	SeaGlass = { motion = "toss", every = 0.9, life = 2.6, pieces = {
		{ mesh = "Cos_SeaPebble", size = 0.42, colours = { rgb(160, 232, 214) }, shine = 0.3 },
		{ mesh = "Cos_SeaPebble", size = 0.3, colours = { rgb(186, 236, 226) }, shine = 0.3 } } },
	-- WINTER WOOL (limited, January's): knitted pom-poms tumbling off behind you.
	WinterWool = { motion = "toss", every = 0.7, life = 2.6, pieces = {
		{ mesh = "Cos_PomPom", size = 0.45, colours = { rgb(220, 60, 60) }, shine = 0 } } },
	-- AUTUMN LEAVES (limited): maple leaves, made for it (Cos_Leaf), let go behind you and turning as they fall.
	AutumnLeaves = { motion = "flutter", every = 0.45, life = 2.8, pieces = {
		{ mesh = "Cos_Leaf", size = 0.6, colours = { rgb(236, 128, 52), rgb(214, 76, 40), rgb(246, 176, 64) }, shine = 0.05 } } },
	-- THE GOLD LEAF (VIP): little leaves of gold tossed behind you, glinting.
	GoldLeaf = { motion = "flutter", every = 0.7, life = 2.4, pieces = {
		{ mesh = "Cos_Gem", size = 0.26, colours = { rgb(255, 226, 140), rgb(250, 199, 117), rgb(232, 176, 70) }, shine = 0.6 },
		{ mesh = "Cos_Star", size = 0.24, colours = { rgb(255, 236, 170) }, shine = 0.5 } } },
	-- BLOSSOM and COOKIE CRUMBS (the two-hundred-and-sixteenth pass), made for them.
	Petals = { motion = "flutter", every = 0.4, life = 2.8, pieces = {
		{ mesh = "Cos_Petal", size = 0.5, colours = { rgb(255, 206, 222), rgb(255, 226, 236) }, shine = 0.05 } } },
	CookieCrumbs = { motion = "toss", every = 0.6, life = 2.4, pieces = {
		{ mesh = "Cos_CookieBit", size = 0.5, colours = { rgb(214, 160, 96) }, shine = 0.02 },
		{ mesh = "Cos_CookieBit", size = 0.3, colours = { rgb(226, 176, 110) }, shine = 0.02 } } },
	-- AURAS
	Bubbles = { motion = "rise", count = 6, radius = 2.1, life = 3.2, pieces = {
		{ mesh = "Ball", size = 0.55, colours = { rgb(244, 250, 255), rgb(206, 230, 255) }, material = "Glass", alpha = 0.6,
			shine = 0.45 } },
		-- A ring of little bubbles round your feet.
		ring = { count = 10, radius = 1.7, spin = 0.35, piece = { mesh = "Ball", size = 0.24,
			colours = { rgb(244, 250, 255), rgb(206, 230, 255), rgb(236, 226, 255) }, material = "Glass", alpha = 0.45, shine = 0.5 } } },
	Mist = { motion = "drift", count = 4, radius = 2.2, life = 6, pieces = {
		{ mesh = "Cos_Cloud_1", size = 1.6, colours = { rgb(236, 250, 244) }, alpha = 0.72, shine = 0 },
		{ mesh = "Cos_Cloud_2", size = 1.4, colours = { rgb(222, 242, 236) }, alpha = 0.75, shine = 0 } } },
	Embers = { motion = "rise", count = 7, radius = 1.7, life = 2.4, pieces = {
		{ mesh = "Cos_Ember_1", size = 0.26, colours = { rgb(255, 214, 120), rgb(255, 150, 50) }, cool = ASH, shine = 0.05 },
		{ mesh = "Cos_Ember_2", size = 0.22, colours = { rgb(255, 236, 160), rgb(255, 170, 60) }, cool = ASH, shine = 0.05 } },
		-- A smouldering ring of coals round your feet, turning the other way.
		ring = { count = 12, radius = 1.5, spin = -0.5, piece = { mesh = "Cos_Ember_1", size = 0.18,
			colours = { rgb(255, 170, 70), rgb(255, 120, 40), rgb(255, 214, 120) }, shine = 0.05 } } },
	Sparkle = { motion = "orbit", count = 6, radius = 2.3, life = 1, spin = 0.8, pieces = {
		{ mesh = "Cos_Gem", size = 0.34, colours = { rgb(255, 226, 140), rgb(250, 199, 117) }, material = "Glass", alpha = 0.1,
			shine = 0.6 },
		{ mesh = "Cos_Star", size = 0.36, colours = { rgb(255, 230, 150) }, shine = 0.4 } },
		-- A crown of gold over your head.
		ring = { count = 8, radius = 0.85, spin = 0.9, halo = true, height = 3, piece = { mesh = "Cos_Gem", size = 0.17,
			colours = { rgb(255, 226, 140), rgb(250, 199, 117) }, material = "Glass", alpha = 0.1, shine = 0.6 } } },
	-- FIRST FROST (limited): flakes and glints of ice circling you, and a ring of frost at your feet.
	FirstFrost = { motion = "orbit", count = 6, radius = 2.1, life = 1.2, spin = 0.5, pieces = {
		{ mesh = "Cos_Snowflake", size = 0.42, colours = { rgb(236, 246, 255), rgb(210, 232, 255) }, shine = 0.5 },
		{ mesh = "Cos_Gem", size = 0.24, colours = { rgb(206, 232, 255) }, shine = 0.6 } },
		ring = { count = 12, radius = 1.6, spin = -0.25, piece = { mesh = "Cos_Snowflake", size = 0.26,
			colours = { rgb(244, 250, 255), rgb(214, 236, 255) }, shine = 0.4 } } },
	-- HOT COCOA (limited, January's): marshmallows bobbing up round you through the steam, and a ring of them at your feet.
	HotCocoa = { motion = "rise", count = 5, radius = 1.9, life = 3.4, pieces = {
		{ mesh = "Cos_Marshmallow", size = 0.42, colours = { rgb(252, 246, 236) }, shine = 0.05 } },
		ring = { count = 8, radius = 1.6, spin = 0.25, piece = { mesh = "Cos_Marshmallow", size = 0.3,
			colours = { rgb(252, 246, 236) }, shine = 0.05 } } },
	-- THE GILDED CROWN (VIP): a crown of gold floating over your head, turning slowly, with gold glints going round you.
	GildedCrown = { motion = "orbit", count = 4, radius = 1.9, life = 1, spin = 0.6, pieces = {
		{ mesh = "Cos_Gem", size = 0.22, colours = { rgb(255, 226, 140), rgb(250, 199, 117) }, shine = 0.6 } },
		ring = { count = 1, radius = 0, spin = 0.5, halo = true, height = 2.55, piece = { mesh = "Cos_Crown", size = 1.3,
			colours = { rgb(240, 196, 80) }, shine = 0.3 } } },
	-- LANTERN NIGHT (limited): little paper lanterns rising round you, warm and slow, and a ring of them at your feet.
	LanternNight = { motion = "rise", count = 5, radius = 2, life = 3.6, pieces = {
		{ mesh = "Ball", size = 0.45, colours = { rgb(255, 200, 120), rgb(255, 170, 96), rgb(255, 222, 160) }, shine = 0.2 } },
		ring = { count = 8, radius = 1.7, spin = 0.2, piece = { mesh = "Ball", size = 0.28,
			colours = { rgb(255, 196, 120), rgb(255, 214, 150) }, shine = 0.2 } } },
	Snowfall = { motion = "fall", count = 8, radius = 2.5, life = 3.4, pieces = {
		{ mesh = "Cos_Snowflake", size = 0.42, colours = { rgb(255, 255, 255), rgb(226, 238, 255) }, shine = 0.3 } },
		-- A circle of frost at your feet.
		ring = { count = 10, radius = 1.9, spin = 0.2, piece = { mesh = "Cos_Snowflake", size = 0.26,
			colours = { rgb(255, 255, 255), rgb(226, 238, 255) }, shine = 0.3 } } },
	Fireflies = { motion = "hover", count = 5, radius = 2.4, life = 1, pieces = {
		{ mesh = "Cos_Firefly", size = 0.3, colours = { rgb(70, 64, 40) }, wings = "Cos_FireflyWings",
			light = rgb(220, 255, 140), lights = 2, shine = 0.1 } } },
	Starlight = { motion = "orbit", count = 6, radius = 2.5, life = 1, spin = 0.45, pieces = {
		{ mesh = "Cos_Star", size = 0.42, colours = { rgb(255, 255, 255), rgb(214, 204, 255) }, shine = 0.35 } },
		-- A halo of little stars over your head, turning against the ones round you.
		ring = { count = 7, radius = 1, spin = -0.6, halo = true, height = 3.1, piece = { mesh = "Cos_Star", size = 0.2,
			colours = { rgb(255, 255, 255), rgb(214, 204, 255) }, shine = 0.35 } } },
	-- THE DUCK PARADE (the two-hundred-and-sixteenth pass): rubber ducks going round you at your feet, nose to tail.
	RubberDucks = { motion = "orbit", count = 5, radius = 2.4, life = 1, spin = 0.5, pieces = {
		{ mesh = "Cos_Duck", size = 0.62, colours = { rgb(255, 214, 60) }, shine = 0.25 } } },
	-- STEPS. How long a print lies (the two-hundred-and-thirty-second pass, from your note of 2026-11-20, "not sure the
	-- paws should stay for that long"): five to ten seconds left a long trail of twenty-odd pieces behind you, over
	-- the marks the ground itself now keeps (GroundMarks). About three seconds now, a few steps behind you; the honey
	-- paw, "slow to fill", and the VIP's gold a little longer.
	HeartStep = { motion = "press", life = 3, pieces = { { mesh = "Cos_JellyHeart", size = 1.1, colours = { rgb(240, 150, 182) },
		shine = 0.25 } } },
	StarStep = { motion = "press", life = 3, pieces = { { mesh = "Cos_StarCookie", size = 1.15, colours = { rgb(250, 202, 120) },
		shine = 0.1 } } },
	-- (yaw 180: made toe forward, where the old prints were made toe back; the two-hundred-and-fifteenth pass, from your
	-- note of 2026-11-14: "the steps are 180 degrees reversed".)
	HoneyPaw = { motion = "press", life = 4.5, pieces = { { mesh = "Cos_HoneyPaw", size = 1.2, colours = { rgb(246, 170, 50) },
		shine = 0.3, yaw = 180 } } },
	-- (Its own sole again, foam blue and a little see-through, not glass: the generated "foam sole" was a whole shoe.)
	BubbleSole = { motion = "press", life = 2.6, pieces = { { mesh = "Cos_Sole", size = 1.5, colours = { rgb(206, 230, 252) },
		alpha = 0.25, shine = 0.15 } } },
	SlimeStep = { motion = "press", life = 3, pieces = { { mesh = "Cos_SlimeBlob", size = 1.35, colours = { rgb(160, 214, 96) },
		shine = 0.3 } } },
	-- PENGUIN STEPS (limited, January's): a little penguin's three-toed print, pressed in the snow.
	PenguinSteps = { motion = "press", life = 3.2, pieces = { { mesh = "Flat", size = 1.0, colours = { rgb(206, 230, 250) },
		shine = 0.1 } } },
	-- CAT PAWS (the two-hundred-and-sixteenth pass): pink toe beans.
	CatPaw = { motion = "press", life = 3, pieces = { { mesh = "Cos_CatPaw", size = 1.0, colours = { rgb(255, 190, 210) },
		shine = 0.2 } } },
	-- GILDED (VIP): a print of beaten gold, catching the light, slow to go.
	GildedSteps = { motion = "press", life = 4, pieces = { { mesh = "Cos_Sole", size = 1.5, colours = { rgb(250, 206, 110),
		rgb(240, 190, 90) }, material = "Foil", shine = 0.55 } } },
	EmberStep = { motion = "press", life = 3, pieces = { { mesh = "Cos_Sole", size = 1.5, colours = { rgb(255, 140, 56) },
		cool = ASH, shine = 0.05 } } },
}

-- ===== THE PALS (the two-hundred-and-sixteenth pass) =====
--
-- Each: its model (Assets.Cosmetics), its largest side in studs, how it moves, where it keeps to (`side` studs to your
-- right, `back` behind, `height` over your middle for the ones that fly; the hoppers keep to the ground), how quickly it
-- catches you up (`follow`, a second), `yaw` (degrees) if its model was made facing another way, and for the warm one
-- a light and sparks. Moves: "hop" (hops after you, squashes as it lands, a small hop now and then standing), "buzz"
-- (hovers, darting a little), "drift" (floats slow and high, swaying), "float" (bobs at your shoulder).
export type Pal = { mesh: string, size: number, motion: string, side: number, back: number, height: number?, follow: number,
	yaw: number?, squash: number?, light: Color3?, sparks: boolean? }
local PALS: { [string]: Pal } = {
	PalNeedoh = { mesh = "Pal_Needoh", size = 1.5, motion = "hop", side = 2.6, back = 1.4, follow = 6, squash = 0.3 },
	PalSlime = { mesh = "Pal_Slime", size = 1.7, motion = "hop", side = 2.8, back = 1.6, follow = 5, squash = 0.42 },
	PalJelly = { mesh = "Pal_Jelly", size = 1.5, motion = "hop", side = 2.6, back = 1.4, follow = 6, squash = 0.36 },
	PalBee = { mesh = "Pal_Bee", size = 1.4, motion = "buzz", side = 2.4, back = 0.8, height = 1.4, follow = 7 },
	PalCloud = { mesh = "Pal_Cloud", size = 2.2, motion = "drift", side = 2.2, back = 1.8, height = 3.2, follow = 2.6 },
	PalLava = { mesh = "Pal_Lava", size = 1.5, motion = "float", side = 2.6, back = 1.2, height = 1.1, follow = 5,
		light = rgb(255, 140, 60), sparks = true },
}

-- What a pal is made of and how it moves (nil for anything that is not one).
function ShopCatalog.pal(id: any): Pal?
	return if typeof(id) == "string" then PALS[id] else nil
end

-- What a trail, an aura or a set of steps is made of (nil for anything that has no pieces).
function ShopCatalog.pieces(id: any): Pieces?
	return if typeof(id) == "string" then PIECES[id] else nil
end

local function sequence(values: { number }): NumberSequence
	local points = {}
	for index, value in ipairs(values) do
		table.insert(points, NumberSequenceKeypoint.new((index - 1) / math.max(1, #values - 1), value))
	end
	if #points == 1 then
		table.insert(points, NumberSequenceKeypoint.new(1, values[1]))
	end
	return NumberSequence.new(points)
end

local function colourSequence(list: { Color3 }): ColorSequence
	local points = {}
	for index, colour in ipairs(list) do
		table.insert(points, ColorSequenceKeypoint.new((index - 1) / math.max(1, #list - 1), colour))
	end
	if #points == 0 then
		return ColorSequence.new(Color3.new(1, 1, 1))
	elseif #points == 1 then
		return ColorSequence.new(list[1])
	end
	return ColorSequence.new(points)
end

local function motesOn(parent: Attachment, spec: Motes, name: string, tag: string)
	local m = Instance.new("ParticleEmitter")
	m.Name = name
	m.Texture = spec.texture
	m.Color = colourSequence(spec.colours)
	m.Size = sequence(spec.size)
	m.Transparency = sequence(spec.fade)
	m.Lifetime = NumberRange.new(spec.life[1], spec.life[2])
	m.Rate = spec.rate
	m.Speed = NumberRange.new(spec.speed[1], spec.speed[2])
	m.SpreadAngle = Vector2.new(spec.spread or 180, spec.spread or 180)
	m.Acceleration = spec.accel or Vector3.zero
	m.Drag = spec.drag or 0
	if spec.spin then
		m.RotSpeed = NumberRange.new(spec.spin[1], spec.spin[2])
		m.Rotation = NumberRange.new(0, 360)
	end
	m.LightEmission = spec.light or 0
	m.LightInfluence = if (spec.light or 0) > 0.5 then 0.2 else 0.8
	-- A TRAIL'S motes stay where they were let go (behind you); an aura's go with you.
	m.LockedToPart = not spec.trailing
	-- A STREAK is drawn out along the way it flies (a spark, not a dot).
	if spec.streak then
		m.Orientation = Enum.ParticleOrientation.VelocityParallel
		pcall(function()
			(m :: any).Squash = NumberSequence.new(1.4)
		end)
	end
	m:SetAttribute(tag, true)
	m.Parent = parent
end

local function glowOn(parent: Attachment, glow: Glow, name: string, tag: string)
	local light = Instance.new("PointLight")
	light.Name = name
	light.Color = glow.colour
	light.Brightness = glow.brightness
	light.Range = glow.range
	light.Shadows = false
	light:SetAttribute(tag, true)
	light.Parent = parent
end

-- PUTS A TRAIL AND AN AURA ON A CHARACTER'S ROOT, after taking off whatever this `tag` put there
-- before. The server wears what you own with tag "Cosmetic" (everyone sees it); the shop's try-on
-- wears with tag "ShopPreview" on your own screen only. One builder, so the preview is the real thing.
function ShopCatalog.wear(root: BasePart, trail: Item?, aura: Item?, tag: string, pal: Item?)
	for _, old in ipairs(root:GetChildren()) do
		if old:GetAttribute(tag) then
			old:Destroy()
		end
	end
	-- A PAL (the two-hundred-and-sixteenth pass): only named here, on an attachment of its own (PiecePal); CosmeticsClient
	-- makes it and moves it on every screen.
	if pal and pal.kind == "pal" and PALS[pal.id] then
		local at = Instance.new("Attachment")
		at.Name = tag .. "Pal"
		at:SetAttribute(tag, true)
		at:SetAttribute("PiecePal", pal.id)
		at.Parent = root
	end
	if trail and trail.kind == "trail" then
		local look = LOOKS[trail.id]
		local ribbon = look and look.ribbon
		-- ITS STRANDS (the hundred-and-seventh pass): each a thin ribbon between two attachments its `width` apart, which
		-- CosmeticsClient moves about you every frame by the strand's motion (named on the top one: StrandMotion and the
		-- rest). The first top is the trail's own (PieceTrail, for its pieces). A trail with no look is one still strand.
		local strands: { Strand } = if ribbon then ribbon.strands else { { at = Vector3.new(0, -0.2, 0), motion = "still" } }
		-- NONE AT ALL (a trail that is mist, not ribbons: the cloud's): only the marker its pieces are drawn by.
		if #strands == 0 then
			local marker = Instance.new("Attachment")
			marker.Name = tag .. "TrailTop"
			marker.Position = Vector3.new(0, -0.2, 0)
			marker:SetAttribute(tag, true)
			marker:SetAttribute("PieceTrail", trail.id)
			marker.Parent = root
		end
		for index, strand in ipairs(strands) do
			local suffix = if index == 1 then "" else tostring(index)
			local half = (strand.width or (if ribbon then ribbon.width else 0.3)) / 2
			local top = Instance.new("Attachment")
			top.Name = tag .. "TrailTop" .. suffix
			top.Position = strand.at + Vector3.new(0, half, 0)
			top:SetAttribute(tag, true)
			if index == 1 then
				-- What it is, for CosmeticsClient to draw its pieces (the server's look and the shop's try-on alike).
				top:SetAttribute("PieceTrail", trail.id)
			end
			top:SetAttribute("StrandMotion", strand.motion)
			top:SetAttribute("StrandAt", strand.at)
			top:SetAttribute("StrandHalf", half)
			top:SetAttribute("StrandRadius", strand.radius or 0)
			top:SetAttribute("StrandSpeed", strand.speed or 0)
			top:SetAttribute("StrandPhase", strand.phase or 0)
			top.Parent = root
			local bottom = Instance.new("Attachment")
			bottom.Name = tag .. "TrailBottom" .. suffix
			bottom.Position = strand.at - Vector3.new(0, half, 0)
			bottom:SetAttribute(tag, true)
			bottom.Parent = root
			local band = Instance.new("Trail")
			band.Name = tag .. "Trail" .. suffix
			band.Attachment0 = top
			band.Attachment1 = bottom
			local colours = strand.colours
			if not colours and ribbon and ribbon.spread and #ribbon.colours > 0 then
				local pick = math.clamp(math.floor((index - 1) / #strands * #ribbon.colours) + 1, 1, #ribbon.colours)
				colours = { ribbon.colours[pick] }
			end
			colours = colours or (if ribbon then ribbon.colours else nil)
			band.Color = if colours then colourSequence(colours)
				else ColorSequence.new(trail.colour, trail.colour:Lerp(Color3.new(1, 1, 1), 0.5))
			local fade = strand.fade or 0.1
			band.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, fade),
				NumberSequenceKeypoint.new(0.55, fade + (1 - fade) * 0.5), NumberSequenceKeypoint.new(1, 1) })
			-- Full width where it leaves you, to nothing at its end (a scale over 1 is not drawn wider).
			band.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) })
			band.Lifetime = if ribbon then ribbon.life else 0.7
			band.MinLength = 0.05
			-- NEVER A COLUMN (the hundred-and-eighty-first pass, from your test of 2026-11-04: "big white columns"): falling,
			-- a ribbon that lives a second and more drew a white pillar a hundred studs up over you. Running, it is still
			-- its whole length; falling or flung, it stops at this. (A teleport is cleared on every screen: CosmeticsClient.)
			band.MaxLength = 16
			band.LightEmission = if ribbon then ribbon.light else 0.25
			band.FaceCamera = true
			if strand.texture then
				band.Texture = strand.texture
				band.TextureMode = Enum.TextureMode.Wrap
				band.TextureLength = 1.6
			end
			band:SetAttribute(tag, true)
			band.Parent = root
		end
		if look then
			local from = Instance.new("Attachment")
			from.Name = tag .. "TrailMotes"
			from.Position = Vector3.new(0, -0.2, 0)
			from:SetAttribute(tag, true)
			from.Parent = root
			for index, spec in ipairs(look.motes) do
				local at = from
				if spec.at then
					local own = Instance.new("Attachment")
					own.Name = tag .. "TrailMotesAt" .. index
					own.Position = spec.at
					own:SetAttribute(tag, true)
					own.Parent = root
					at = own
				end
				motesOn(at, spec, tag .. "TrailMotes" .. index, tag)
			end
			if look.glow then
				glowOn(from, look.glow, tag .. "TrailGlow", tag)
			end
		end
	end
	local look = aura and LOOKS[aura.id]
	if aura and aura.kind == "aura" and look then
		local at = Instance.new("Attachment")
		at.Name = tag .. "Aura"
		at.Position = Vector3.new(0, -0.6, 0)
		at:SetAttribute(tag, true)
		at:SetAttribute("PieceAura", aura.id)
		at.Parent = root
		for index, spec in ipairs(look.motes) do
			local from = at
			if spec.at then
				local own = Instance.new("Attachment")
				own.Name = tag .. "AuraAt" .. index
				own.Position = spec.at
				own:SetAttribute(tag, true)
				own.Parent = root
				from = own
			end
			motesOn(from, spec, tag .. "AuraMotes" .. index, tag)
		end
		if look.glow then
			glowOn(at, look.glow, tag .. "AuraGlow", tag)
		end
	end
end

-- Whether a trail or an aura has its own look (check_shop holds every one to having one).
function ShopCatalog.hasLook(id: string): boolean
	return LOOKS[id] ~= nil
end

-- ===== CODES =====
--
-- The codes you post (on social media, in your group, in a video), typed into the lobby's post box: each pays its
-- tokens once a save, until the end of its `ends` day (UTC). Capitals, letters and digits only. Add a line to add a
-- code; set `ends` to an earlier day to end one. Nothing else holds a code.
export type Code = { code: string, tokens: number, ends: string }
ShopCatalog.CODES = {
	{ code = "HARROWBAY", tokens = 100, ends = "2026-12-31" },
} :: { Code }

-- A CODE AS TYPED, in the list's form: spaces gone, in capitals. Nil for anything that cannot be a code.
function ShopCatalog.codeKey(typed: any): string?
	if typeof(typed) ~= "string" or #typed > 40 then
		return nil
	end
	local key = string.upper((string.gsub(typed, "%s", "")))
	if #key < 3 or #key > 20 or not string.match(key, "^%w+$") then
		return nil
	end
	return key
end

function ShopCatalog.code(key: string): Code?
	for _, entry in ipairs(ShopCatalog.CODES) do
		if entry.code == key then
			return entry
		end
	end
	return nil
end

-- WHEN A CODE ENDS: the first second after its `ends` day, UTC (os.time's clock). Nil for a date that is not one.
function ShopCatalog.codeEnds(entry: Code): number?
	local y, m, d = string.match(entry.ends, "^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
	if not (y and m and d) then
		return nil
	end
	local ok, at = pcall(function()
		return DateTime.fromUniversalTime(tonumber(y) :: number, tonumber(m) :: number, tonumber(d) :: number).UnixTimestamp
	end)
	return if ok then at + 86400 else nil
end

-- ===== THE MATERIALS, AS A COLLECTION =====
--
-- Every material in MaterialConfig, in its order, with the name a player reads (on the lobby's board and in the
-- journal) and a colour for its swatch on the board. Found by standing on one in a level (EconomyService.foundMaterial,
-- seen by the server itself); each pays REWARD.MATERIAL once a save, and the last of them REWARD.MATERIALS_ALL and the
-- swatch trail.
--
-- NO BRAND NAMES (the hundred-and-fiftieth pass, from your notes of 2026-10-31): four of these were trade marks (Lego,
-- NeeDoh, Kinetic Sand, Jell-O), and a game that sells things should not put another company's mark on its board. The
-- names a player reads are plain words now; the keys (what a save and every script know them by) are unchanged.
export type Material = { key: string, name: string, colour: Color3 }
ShopCatalog.MATERIALS = {
	{ key = "Honey", name = "Honey", colour = rgb(228, 158, 40) },
	{ key = "ButterWax", name = "Waxed butter", colour = rgb(244, 222, 150) },
	{ key = "KineticSand", name = "Sculpting sand", colour = rgb(214, 180, 140) },
	{ key = "Slime", name = "Slime", colour = rgb(130, 214, 90) },
	{ key = "Soap", name = "Soap", colour = rgb(236, 232, 246) },
	{ key = "Cookie", name = "Cookie", colour = rgb(212, 156, 92) },
	{ key = "CreamyKeyboard", name = "Creamy keyboard", colour = rgb(240, 232, 214) },
	{ key = "Salt", name = "Salt crust", colour = rgb(232, 232, 226) },
	{ key = "Lava", name = "Lava crust", colour = rgb(214, 80, 40) },
	{ key = "Oobleck", name = "Oobleck", colour = rgb(240, 240, 232) },
	{ key = "Buttons", name = "Arcade buttons", colour = rgb(90, 200, 230) },
	{ key = "Snow", name = "Snow", colour = rgb(246, 250, 255) },
	{ key = "Foam", name = "Memory foam", colour = rgb(238, 226, 200) },
	{ key = "LightSwitch", name = "Light switches", colour = rgb(244, 244, 236) },
	{ key = "Lego", name = "Toy bricks", colour = rgb(220, 50, 50) },
	{ key = "Charcoal", name = "Charcoal", colour = rgb(60, 58, 58) },
	{ key = "Chocolate", name = "Chocolate", colour = rgb(110, 64, 36) },
	{ key = "ChocolateSolid", name = "Solid chocolate", colour = rgb(84, 48, 26) },
	{ key = "Clay", name = "Clay", colour = rgb(196, 120, 80) },
	{ key = "Cloud", name = "Cloud", colour = rgb(236, 240, 252) },
	{ key = "LambsEar", name = "Lamb's ear", colour = rgb(176, 190, 170) },
	{ key = "Ice", name = "Ice", colour = rgb(190, 226, 246) },
	{ key = "JelloSoda", name = "Jelly", colour = rgb(236, 96, 120) },
	{ key = "Jellyfish", name = "Jellyfish", colour = rgb(200, 170, 240) },
	{ key = "LavaKeys", name = "Keys over lava", colour = rgb(70, 66, 72) },
	{ key = "ButterStick", name = "Butter", colour = rgb(248, 226, 130) },
	{ key = "Needoh", name = "Stress ball", colour = rgb(247, 170, 200) },
	{ key = "BubbleWrap", name = "Bubble wrap", colour = rgb(210, 236, 248) },
} :: { Material }

local materialByKey: { [string]: Material } = {}
for _, material in ipairs(ShopCatalog.MATERIALS) do
	materialByKey[material.key] = material
end
-- The swatch trail's ribbon: eight of the materials' own colours along it.
for _, key in ipairs({ "Honey", "Lava", "JelloSoda", "Jellyfish", "Buttons", "Slime", "Clay", "Needoh" }) do
	local material = materialByKey[key]
	if material then
		table.insert(swatchColours, material.colour)
	end
end

function ShopCatalog.material(key: any): Material?
	if typeof(key) ~= "string" then
		return nil
	end
	return materialByKey[key]
end

-- ===== DAILY CHALLENGES =====
--
-- Three a day for each player (EconomyService picks them the first time their save sees the day, UTC as the daily
-- chest's, from the ones they can do: a level's only once that level is open to them). Each is done by finishing a
-- run (challengeMet) and pays its tokens once that day. Their words are on the lobby's board, drawn by each player's
-- own screen (HubVoteService).
export type Challenge = { id: string, text: string, reward: number, level: number?, kind: string?, count: number? }
ShopCatalog.CHALLENGES_A_DAY = 3
ShopCatalog.CHALLENGES = {
	{ id = "shore", text = "Finish City Shore", reward = 30, level = 1 },
	{ id = "pools", text = "Finish the Sky Pools", reward = 35, level = 2 },
	{ id = "city", text = "Finish the Sunken City", reward = 40, level = 3 },
	{ id = "halls", text = "Finish the Flooded Halls", reward = 45, level = 4 },
	{ id = "hardcore", text = "Finish a run in Hardcore", reward = 40, kind = "hardcore" },
	{ id = "best", text = "Set a new best in Hardcore", reward = 50, kind = "best" },
	{ id = "long", text = "Finish a long run", reward = 40, kind = "long" },
	{ id = "friend", text = "Finish a run with a friend", reward = 40, kind = "friend" },
	{ id = "three", text = "Finish 3 runs", reward = 50, kind = "runs", count = 3 },
} :: { Challenge }

local challengeById: { [string]: Challenge } = {}
for _, challenge in ipairs(ShopCatalog.CHALLENGES) do
	challengeById[challenge.id] = challenge
end

function ShopCatalog.challenge(id: string): Challenge?
	return challengeById[id]
end

-- TODAY'S THREE for one player: every challenge shuffled by the day (the same order for everyone that day), and the
-- first three they can do (canDo) taken.
function ShopCatalog.pickChallenges(day: number, canDo: (Challenge) -> boolean): { string }
	local order = table.clone(ShopCatalog.CHALLENGES)
	local random = Random.new(day)
	for i = #order, 2, -1 do
		local j = random:NextInteger(1, i)
		order[i], order[j] = order[j], order[i]
	end
	local picked = {}
	for _, challenge in ipairs(order) do
		if #picked < ShopCatalog.CHALLENGES_A_DAY and canDo(challenge) then
			table.insert(picked, challenge.id)
		end
	end
	return picked
end

-- WHETHER A FINISHED RUN DOES A CHALLENGE: run is what it was (levelId, hardcore, best, friend, length), runs how many
-- this player has finished today, this one included.
function ShopCatalog.challengeMet(challenge: Challenge, run: { [string]: any }, runs: number): boolean
	if challenge.level then
		return run.levelId == challenge.level
	elseif challenge.kind == "hardcore" then
		return run.hardcore == true
	elseif challenge.kind == "best" then
		return run.best == true
	elseif challenge.kind == "long" then
		return run.length == "long"
	elseif challenge.kind == "friend" then
		return run.friend == true
	elseif challenge.kind == "runs" then
		return runs >= (challenge.count or 1)
	end
	return false
end

-- Tokens for a run: `length` as the lobby names it, whether it was hardcore, whether it was a new
-- personal best, and whether the player has the 2x pass.
-- WHAT THE DAILY CHEST PAYS on day `streak` of a streak (1 the first day, or the day after one missed).
function ShopCatalog.dailyReward(streak: number): number
	local table_ = ShopCatalog.REWARD.DAILY
	return table_[math.clamp(math.floor(streak), 1, #table_)]
end

-- WHAT FINISHING THE STORY PAYS, on top of its last level's own run.
function ShopCatalog.storyReward(hardcore: boolean, double: boolean): number
	local amount = ShopCatalog.REWARD.STORY
	if hardcore then
		amount = math.floor(amount * ShopCatalog.REWARD.HARDCORE + 0.5)
	end
	if double then
		amount *= 2
	end
	return amount
end

-- WHAT VIP GIVES (the two-hundred-and-thirteenth pass, from your note of 2026-11-13: VIP should be worth having): every
-- run's tokens a fifth more (after the 2x, so the two stack), a free background crate once a day in the VIP lounge (or
-- `crateTokens` when there is no background left for you, or crates are not offered where you are), the lounge itself,
-- and the things marked earn = "vip" (the Royal wave, the Gold leaf trail, Gilded steps) with the gold sparkle.
-- THE BOUTIQUE (the two-hundred-and-thirteenth pass, the shop's Wear tab): real avatar items from the Roblox catalog, in
-- the bay's own collections, found by the server with these words (EconomyService, AvatarEditorService) and sold in
-- Roblox's own window; the game's owner earns 40% of each. `per` items for each word, at `min` Robux or more, of the
-- kinds a character wears (`kinds`, the catalog's AssetType names); the shelves found again every `refresh` seconds.
-- A new collection is a new line here (a new level's: its own words and colours).
ShopCatalog.BOUTIQUE = {
	collections = {
		{ name = "Seaside", words = { "sailor hat", "yellow raincoat", "seashell" }, colour = rgb(170, 224, 230),
			accent = rgb(14, 80, 96) },
		{ name = "Squishy", words = { "slime", "jelly", "bubble wrap" }, colour = rgb(248, 196, 220), accent = rgb(110, 30, 70) },
		{ name = "Lighthouse keeper", words = { "lighthouse", "lantern", "fisherman" }, colour = rgb(250, 214, 140),
			accent = rgb(100, 60, 8) },
		{ name = "Cosy", words = { "knit beanie", "cozy scarf", "cozy sweater" }, colour = rgb(214, 204, 246),
			accent = rgb(52, 40, 110) },
	},
	per = 3,
	min = 1,
	refresh = 3600,
	kinds = { Hat = true, HairAccessory = true, FaceAccessory = true, NeckAccessory = true, ShoulderAccessory = true,
		FrontAccessory = true, BackAccessory = true, WaistAccessory = true, JacketAccessory = true, SweaterAccessory = true,
		ShirtAccessory = true, TShirtAccessory = true, PantsAccessory = true, ShortsAccessory = true,
		DressSkirtAccessory = true },
}

-- HERE FOR A SEASON (the two-hundred-and-thirteenth pass): a limited item's window, its first and last days as UTC
-- dates ("2026-11-14"), on sale from the first day's start to the last day's start. The same answer on the server
-- (which refuses a buy outside it) and on every screen (which shows the time left and hides it once it is gone).
local function dayStart(text: string): number
	local y, m, d = string.match(text, "^(%d+)%-(%d+)%-(%d+)$")
	return DateTime.fromUniversalTime(tonumber(y) or 1970, tonumber(m) or 1, tonumber(d) or 1).UnixTimestamp
end

-- "soon", "on" or "gone" for a limited item at `now` (seconds, UTC; os.time() by default), and the second it ends.
function ShopCatalog.season(item: any, now: number?, vip: boolean?): (string, number)
	local window = item and item.limited
	if not window then
		return "on", math.huge
	end
	local at = now or os.time()
	local from, to = dayStart(window.from), dayStart(window.to)
	-- VIP EARLY (the two-hundred-and-fourteenth pass): on sale to a VIP ShopCatalog.VIP.early days before its first day.
	if vip and at < from and at >= from - ShopCatalog.VIP.early * 86400 then
		return "early", to
	end
	return (if at < from then "soon" elseif at < to then "on" else "gone"), to
end

-- The limited items on sale now, newest first (Featured shows them before anything else).
function ShopCatalog.inSeason(now: number?, vip: boolean?): { Item }
	local list = {}
	for _, item in ipairs(ITEMS) do
		local state = if item.limited then ShopCatalog.season(item, now, vip) else "gone"
		if state == "on" or state == "early" then
			table.insert(list, item)
		end
	end
	return list
end

-- REWARDED VIDEO ADS (the two-hundred-and-thirteenth pass): what an ad can be watched for, and how many a day each:
-- a second chance on the hardcore card, and a run boost in the shop. Their products are the ones sold (SecondChance,
-- RunBoost), as Roblox asks: an ad gives what Robux would buy, never something only an ad gives, never at random.
ShopCatalog.ADS = { chance = { product = "SecondChance", perDay = 3 }, boost = { product = "RunBoost", perDay = 3 } }

-- And since the two-hundred-and-fourteenth pass: the daily chest pays half as much again (`daily`), every season's thing
-- is on sale to a VIP `early` days before anyone else, and the Gilded crown.
ShopCatalog.VIP = { tokens = 1.2, crateTokens = 250, daily = 1.5, early = 3,
	items = { "RoyalWave", "GoldLeaf", "GildedSteps", "GildedCrown", "Sparkle" } }

function ShopCatalog.vipReward(amount: number): number
	return math.floor(amount * ShopCatalog.VIP.tokens + 0.5)
end

function ShopCatalog.reward(length: string, hardcore: boolean, best: boolean, double: boolean, friend: boolean?): number
	local base = ShopCatalog.REWARD.BASE[length] or ShopCatalog.REWARD.BASE.medium
	local amount = base
	if hardcore then
		amount = math.floor(amount * ShopCatalog.REWARD.HARDCORE + 0.5)
	end
	if best then
		amount += ShopCatalog.REWARD.BEST_BONUS
	end
	if friend then
		amount = math.floor(amount * ShopCatalog.REWARD.FRIEND + 0.5)
	end
	if double then
		amount *= 2
	end
	return amount
end

ShopCatalog.STAMP = "4bba8e94"
return ShopCatalog
