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
	kind: string, -- "trail", "aura", "steps", "sound", "emote", "pass", "product", "tokens", "background", "crate"
	price: number?, -- in tokens
	robux: number?, -- shown price in Robux (the real price is whatever the Dashboard says)
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
ShopCatalog.TABS = { "Featured", "Steps", "Trails", "Sounds", "Auras", "Emotes", "Passes", "Tokens", "Backgrounds" }

ShopCatalog.FEATURED = { "StarterPack", "VIP", "BgCrate", "DoubleTokens", "HoneyPaw", "Poppy", "HoneyDrip", "Embers",
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
	{ id = "BubbleSole", tab = "Steps", kind = "steps", name = "Bubble sole", blurb = "Prints that fizz away",
		price = 150, colour = rgb(181, 212, 244), accent = rgb(12, 68, 124) },
	{ id = "SlimeStep", tab = "Steps", kind = "steps", name = "Slime steps", blurb = "Green blobs that drip as they go",
		price = 130, colour = rgb(151, 196, 89), accent = rgb(39, 80, 10) },
	{ id = "EmberStep", tab = "Steps", kind = "steps", name = "Ember steps", blurb = "Glowing prints that cool to ash",
		price = 170, colour = rgb(255, 128, 48), accent = rgb(113, 43, 19) },

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
	{ id = "Starlight", tab = "Auras", kind = "aura", name = "Starlight", blurb = "Stars twinkling all round you",
		price = 450, colour = rgb(206, 196, 255), accent = rgb(38, 33, 92) },

	-- EMOTES: played from the emote picker (G, D-pad right, or the pause menu), seen by everyone
	-- (EmoteService poses them on every client; moving ends one).
	{ id = "Wave", tab = "Emotes", kind = "emote", name = "Wave", blurb = "Say hello",
		price = 80, colour = rgb(159, 225, 203), accent = rgb(8, 80, 65) },
	{ id = "SitSquish", tab = "Emotes", kind = "emote", name = "Sit and squish", blurb = "Sit down, squeeze a toy",
		price = 80, colour = rgb(244, 192, 209), accent = rgb(114, 36, 62) },
	{ id = "Stretch", tab = "Emotes", kind = "emote", name = "Stretch", blurb = "A long slow stretch",
		price = 100, colour = rgb(192, 221, 151), accent = rgb(39, 80, 10) },
	{ id = "Spin", tab = "Emotes", kind = "emote", name = "Spin", blurb = "A happy spin",
		price = 150, colour = rgb(175, 169, 236), accent = rgb(38, 33, 92) },

	-- PASSES: bought once, kept forever.
	-- THE STARTER PACK: a pass, so Roblox sells it only once; its tokens and the sea glass trail are given once a save
	-- (EconomyService.grantStarter). First in Featured, and gone from there once it is yours.
	{ id = "StarterPack", tab = "Passes", kind = "pass", name = "Starter pack", blurb = "500 tokens and the sea glass trail",
		robux = 99, passId = 0, tokens = 500, gives = "SeaGlass", once = true, colour = rgb(130, 212, 190),
		accent = rgb(8, 80, 65) },
	{ id = "DoubleTokens", tab = "Passes", kind = "pass", name = "2x tokens", blurb = "Every run pays double",
		robux = 199, passId = 0, colour = rgb(250, 199, 117), accent = rgb(99, 56, 6) },
	{ id = "VIP", tab = "Passes", kind = "pass", name = "VIP", blurb = "A VIP tag over your head and in chat, and the gold sparkle",
		robux = 299, passId = 0, colour = rgb(206, 203, 246), accent = rgb(38, 33, 92) },
	{ id = "SecondChance", tab = "Passes", kind = "product", name = "Second chance", blurb = "Hardcore: back to your last checkpoint once",
		robux = 25, productId = 0, colour = rgb(247, 193, 193), accent = rgb(121, 31, 31) },

	-- TOKEN PACKS: developer products, bought as often as you like.
	{ id = "Pack100", tab = "Tokens", kind = "tokens", name = "100 tokens", blurb = "A handful",
		robux = 49, productId = 0, tokens = 100, colour = rgb(250, 199, 117), accent = rgb(99, 56, 6) },
	{ id = "Pack300", tab = "Tokens", kind = "tokens", name = "300 tokens", blurb = "A jar full",
		robux = 129, productId = 0, tokens = 300, colour = rgb(239, 159, 39), accent = rgb(99, 56, 6) },
	{ id = "Pack800", tab = "Tokens", kind = "tokens", name = "800 tokens", blurb = "A bucket of them",
		robux = 299, productId = 0, tokens = 800, colour = rgb(186, 117, 23), accent = rgb(65, 36, 2) },
	{ id = "Pack2000", tab = "Tokens", kind = "tokens", name = "2000 tokens", blurb = "The whole till",
		robux = 649, productId = 0, tokens = 2000, colour = rgb(133, 79, 11), accent = rgb(250, 238, 218) },

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
	{ id = "BgSand", tab = "Backgrounds", kind = "background", name = "Kinetic sand", blurb = "Soft grains, and a footprint or two",
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
		robux = 399, passId = 0, colour = rgb(30, 110, 110), accent = rgb(4, 10, 14) },
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
		ribbon = { colours = { rgb(255, 255, 255), rgb(222, 238, 252), rgb(180, 212, 240) }, width = 0.22, life = 0.85, light = 0.15,
			-- Two threads of suds twisting round each other.
			strands = { { at = Vector3.new(0, -0.3, 0), motion = "helix", radius = 0.7, speed = 5 },
				{ at = Vector3.new(0, -0.3, 0), motion = "helix", radius = 0.7, speed = 5, phase = math.pi,
					colours = { rgb(236, 226, 255), rgb(206, 220, 250) } } } },
		motes = {
			{ texture = TEX.smoke, colours = { rgb(255, 255, 255), rgb(214, 234, 252) }, size = { 0.25, 0.45 },
				fade = { 0.35, 0.6, 1 }, life = { 0.9, 1.5 }, rate = 7, speed = { 0.2, 0.7 }, spread = 180,
				accel = Vector3.new(0, 1.4, 0), trailing = true },
			{ texture = TEX.sparkle, colours = { rgb(255, 255, 255) }, size = { 0.22, 0 }, fade = { 0.2, 1 },
				life = { 0.3, 0.6 }, rate = 3, speed = { 0, 0.3 }, light = 0.6, trailing = true },
		},
	},
	HoneyDrip = {
		ribbon = { colours = { rgb(255, 222, 130), rgb(239, 159, 39), rgb(168, 92, 10) }, width = 0.34, life = 1.3, light = 0.3,
			-- One thick thread of honey, sagging slowly as it is drawn out.
			strands = { { at = Vector3.new(0, -0.5, 0), motion = "bob", radius = 0.22, speed = 1.6 } } },
		motes = {
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
		ribbon = { colours = { rgb(214, 255, 130), rgb(151, 196, 89), rgb(58, 140, 30) }, width = 0.3, life = 0.95, light = 0.85,
			-- A wobbling string of slime, and a darker one under it, out of step.
			strands = { { at = Vector3.new(0, -0.3, 0), motion = "wave", radius = 0.45, speed = 7 },
				{ at = Vector3.new(0, -0.75, 0), motion = "wave", radius = 0.3, speed = 7, phase = 2.2, width = 0.18,
					colours = { rgb(120, 200, 60), rgb(58, 140, 30) } } } },
		motes = {
			{ texture = TEX.smoke, colours = { rgb(190, 255, 110), rgb(90, 180, 40) }, size = { 0.24, 0.16 },
				fade = { 0.05, 1 }, life = { 0.6, 0.9 }, rate = 5, speed = { 0, 0.3 }, spread = 25,
				accel = Vector3.new(0, -20, 0), light = 0.7, at = Vector3.new(0, -0.4, 0), trailing = true },
		},
		glow = { colour = rgb(160, 255, 100), brightness = 0.9, range = 8 },
	},
	CloudPuff = {
		ribbon = { colours = { rgb(255, 255, 255), rgb(232, 230, 252), rgb(206, 203, 246) }, width = 0.42, life = 1.3, light = 0.1,
			-- Three faint wisps, drifting apart and together.
			strands = { { at = Vector3.new(0, 0.6, 0), motion = "wave", radius = 0.35, speed = 1.1, fade = 0.45 },
				{ at = Vector3.new(0, -0.2, 0), motion = "wave", radius = 0.4, speed = 0.9, phase = 2, fade = 0.4 },
				{ at = Vector3.new(0, -1, 0), motion = "wave", radius = 0.3, speed = 1.3, phase = 4, fade = 0.5 } } },
		motes = {
			{ texture = TEX.smoke, colours = { rgb(255, 255, 255), rgb(228, 226, 252) }, size = { 0.6, 1.5 },
				fade = { 0.5, 0.7, 1 }, life = { 1.2, 2 }, rate = 6, speed = { 0.1, 0.4 }, spread = 180,
				accel = Vector3.new(0, 0.4, 0), drag = 2, trailing = true },
		},
	},
	GreenRibbon = {
		ribbon = { colours = { rgb(150, 225, 160), rgb(58, 150, 88), rgb(30, 100, 60) }, width = 0.3, life = 1.05, light = 0.2,
			-- The key's ribbon, fluttering in a figure of eight.
			strands = { { at = Vector3.new(0, 0.2, 0), motion = "flutter", radius = 0.55, speed = 4 } } },
		motes = {
			{ texture = TEX.sparkle, colours = { rgb(200, 255, 200) }, size = { 0.2, 0 }, fade = { 0.3, 1 },
				life = { 0.4, 0.7 }, rate = 3, speed = { 0, 0.2 }, light = 0.6, trailing = true },
		},
	},
	SeaGlass = {
		ribbon = { colours = { rgb(214, 250, 238), rgb(130, 212, 190), rgb(70, 160, 140) }, width = 0.24, life = 1, light = 0.4,
			-- Two glassy threads turning slowly, one of them glinting all along.
			strands = { { at = Vector3.new(0, -0.2, 0), motion = "helix", radius = 0.55, speed = 2.5 },
				{ at = Vector3.new(0, -0.2, 0), motion = "helix", radius = 0.55, speed = 2.5, phase = math.pi, width = 0.4,
					texture = TEX.sparkle, fade = 0.2, colours = { rgb(235, 255, 250), rgb(150, 230, 210) } } } },
		motes = {
			{ texture = TEX.sparkle, colours = { rgb(235, 255, 250), rgb(150, 230, 210) }, size = { 0, 0.32, 0 },
				fade = { 0.1, 1 }, life = { 0.4, 0.8 }, rate = 7, speed = { 0, 0.3 }, light = 1, trailing = true },
		},
	},
	Swatch = {
		ribbon = { colours = swatchColours, width = 0.16, life = 1.1, light = 0.25, spread = true,
			-- Every material's colour, five threads one over another: a band of all of them, rippling.
			strands = { { at = Vector3.new(0, 0.2, 0), motion = "wave", radius = 0.14, speed = 3 },
				{ at = Vector3.new(0, 0.02, 0), motion = "wave", radius = 0.14, speed = 3, phase = 0.35 },
				{ at = Vector3.new(0, -0.16, 0), motion = "wave", radius = 0.14, speed = 3, phase = 0.7 },
				{ at = Vector3.new(0, -0.34, 0), motion = "wave", radius = 0.14, speed = 3, phase = 1.05 },
				{ at = Vector3.new(0, -0.52, 0), motion = "wave", radius = 0.14, speed = 3, phase = 1.4 } } },
		motes = {
			{ texture = TEX.sparkle, colours = { rgb(255, 255, 255) }, size = { 0.24, 0 }, fade = { 0.2, 1 },
				life = { 0.4, 0.8 }, rate = 4, speed = { 0, 0.3 }, light = 0.8, trailing = true },
		},
	},
	LavaRibbon = {
		ribbon = { colours = { rgb(255, 236, 150), rgb(255, 128, 32), rgb(176, 34, 12), rgb(52, 22, 22) }, width = 0.26,
			life = 1.05, light = 0.95,
			-- A white-hot thread crackling, and the heat round it: dull red, wide and faint.
			strands = { { at = Vector3.new(0, -0.4, 0), motion = "zigzag", radius = 0.22, speed = 9 },
				{ at = Vector3.new(0, -0.4, 0), motion = "still", width = 0.7, fade = 0.6,
					colours = { rgb(255, 120, 40), rgb(150, 30, 12), rgb(52, 22, 22) } } } },
		motes = {
			{ texture = TEX.spark, colours = { rgb(255, 214, 110), rgb(255, 96, 24) }, size = { 0.2, 0.12, 0 },
				fade = { 0, 0.2, 1 }, life = { 0.5, 1.1 }, rate = 12, speed = { 1, 3 }, spread = 60,
				accel = Vector3.new(0, 3, 0), spin = { -120, 120 }, light = 1, trailing = true },
			{ texture = TEX.smoke, colours = { rgb(70, 60, 60) }, size = { 0.3, 0.8 }, fade = { 0.6, 1 },
				life = { 1, 1.6 }, rate = 3, speed = { 0.2, 0.5 }, accel = Vector3.new(0, 1.5, 0), trailing = true },
		},
		glow = { colour = rgb(255, 128, 48), brightness = 1.1, range = 9 },
	},
	JellyRibbon = {
		ribbon = { colours = { rgb(255, 196, 214), rgb(236, 96, 120), rgb(186, 50, 84) }, width = 0.28, life = 1, light = 0.4,
			-- Two jelly threads hopping, one after the other.
			strands = { { at = Vector3.new(-0.25, -0.9, 0), motion = "bounce", radius = 0.7, speed = 5 },
				{ at = Vector3.new(0.25, -0.9, 0), motion = "bounce", radius = 0.7, speed = 5, phase = 1.57 } } },
		motes = {
			{ texture = TEX.smoke, colours = { rgb(255, 150, 180), rgb(236, 96, 120) }, size = { 0.3, 0.22 },
				fade = { 0.15, 0.3, 1 }, life = { 0.6, 1 }, rate = 5, speed = { 0, 0.3 }, spread = 25,
				accel = Vector3.new(0, -12, 0), light = 0.4, at = Vector3.new(0, -0.4, 0), trailing = true },
		},
	},
	Sprinkles = {
		ribbon = { colours = { rgb(255, 255, 255), rgb(255, 236, 246) }, width = 0.12, life = 0.8, light = 0.1,
			-- A candy stripe: three thin threads, pink, blue and yellow, twisting fast.
			strands = { { at = Vector3.new(0, -0.2, 0), motion = "helix", radius = 0.45, speed = 7, colours = { rgb(255, 120, 170) } },
				{ at = Vector3.new(0, -0.2, 0), motion = "helix", radius = 0.45, speed = 7, phase = 2.09,
					colours = { rgb(110, 190, 255) } },
				{ at = Vector3.new(0, -0.2, 0), motion = "helix", radius = 0.45, speed = 7, phase = 4.19,
					colours = { rgb(255, 214, 90) } } } },
		motes = {
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
	cool: Color3?, wings: string?, light: Color3?, lights: number? }
-- AN AURA'S RING (the hundred-and-seventh pass: "auras ... even cooler, more pronounced"): `count` of `piece` lying in a
-- circle round your feet, `radius` out, turning `spin` a second; or with `halo`, over your head, `height` above your
-- middle.
export type Ring = { count: number, radius: number, spin: number, halo: boolean?, height: number?, piece: Piece }
export type Pieces = { motion: string, life: number, every: number?, count: number?, radius: number?, spin: number?,
	pieces: { Piece }, ring: Ring? }
local ASH = rgb(70, 62, 60)
local PIECES: { [string]: Pieces } = {
	-- TRAILS
	SoapSuds = { motion = "rise", every = 1.1, life = 1.7, pieces = {
		{ mesh = "Ball", size = 0.5, colours = { rgb(244, 250, 255), rgb(214, 236, 255), rgb(236, 226, 255) }, material = "Glass",
			alpha = 0.6, shine = 0.45 } } },
	HoneyDrip = { motion = "drip", every = 1.0, life = 3.2, pieces = {
		{ mesh = "Cos_HoneyDrop", size = 0.44, colours = { rgb(255, 196, 70), rgb(236, 154, 32) }, material = "Glass",
			alpha = 0.1, shine = 0.3 } } },
	SlimeGlow = { motion = "splat", every = 1.5, life = 3.4, pieces = {
		{ mesh = "Cos_SlimeSplat", size = 0.9, colours = { rgb(170, 245, 90), rgb(126, 214, 64) }, material = "Glass",
			alpha = 0.15, shine = 0.35 } } },
	CloudPuff = { motion = "puff", every = 1.3, life = 2.2, pieces = {
		{ mesh = "Cos_Cloud_1", size = 0.95, colours = { rgb(255, 255, 255), rgb(238, 236, 252) }, alpha = 0.1, shine = 0 },
		{ mesh = "Cos_Cloud_2", size = 0.85, colours = { rgb(255, 255, 255), rgb(230, 228, 250) }, alpha = 0.1, shine = 0 } } },
	JellyRibbon = { motion = "bounce", every = 0.9, life = 2.4, pieces = {
		{ mesh = "Ball", size = 0.36, colours = { rgb(255, 150, 180), rgb(240, 100, 128), rgb(255, 196, 214) }, material = "Glass",
			alpha = 0.22, shine = 0.35 } } },
	Sprinkles = { motion = "toss", every = 0.45, life = 2.6, pieces = {
		{ mesh = "Cos_Sprinkle", size = 0.34, colours = { rgb(255, 120, 170), rgb(110, 190, 255), rgb(255, 214, 90),
			rgb(255, 255, 255), rgb(140, 230, 140), rgb(196, 150, 255) }, shine = 0.15 } } },
	LavaRibbon = { motion = "toss", every = 0.85, life = 2.2, pieces = {
		{ mesh = "Cos_Ember_1", size = 0.34, colours = { rgb(255, 170, 70), rgb(255, 120, 40) }, cool = ASH, shine = 0.05 },
		{ mesh = "Cos_Ember_2", size = 0.3, colours = { rgb(255, 196, 96), rgb(255, 140, 50) }, cool = ASH, shine = 0.05 } } },
	GreenRibbon = { motion = "flutter", every = 1.2, life = 1.9, pieces = {
		{ mesh = "Cos_Gem", size = 0.24, colours = { rgb(160, 232, 170), rgb(96, 196, 126) }, material = "Glass", alpha = 0.2,
			shine = 0.45 } } },
	Swatch = { motion = "toss", every = 0.75, life = 2.3, pieces = {
		{ mesh = "Cos_Gem", size = 0.3, colours = swatchColours, shine = 0.2 } } },
	SeaGlass = { motion = "toss", every = 0.95, life = 2.6, pieces = {
		{ mesh = "Cos_SeaGlass_1", size = 0.4, colours = { rgb(160, 232, 214), rgb(110, 204, 182) }, material = "Glass",
			alpha = 0.3, shine = 0.35 },
		{ mesh = "Cos_SeaGlass_2", size = 0.36, colours = { rgb(186, 236, 226), rgb(126, 196, 210) }, material = "Glass",
			alpha = 0.3, shine = 0.35 } } },
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
	-- STEPS
	HeartStep = { motion = "press", life = 6, pieces = { { mesh = "Cos_Heart", size = 1.1, colours = { rgb(240, 150, 182) },
		shine = 0.2 } } },
	StarStep = { motion = "press", life = 6, pieces = { { mesh = "Cos_Star", size = 1.15, colours = { rgb(250, 202, 120) },
		shine = 0.25 } } },
	HoneyPaw = { motion = "press", life = 10, pieces = { { mesh = "Cos_PawPrint", size = 1.2, colours = { rgb(246, 170, 50) },
		material = "Glass", alpha = 0.08, shine = 0.3 } } },
	BubbleSole = { motion = "press", life = 2.6, pieces = { { mesh = "Cos_Sole", size = 1.5, colours = { rgb(190, 220, 248) },
		material = "Glass", alpha = 0.45, shine = 0.4 } } },
	SlimeStep = { motion = "press", life = 5, pieces = { { mesh = "Cos_SlimeSplat", size = 1.35, colours = { rgb(160, 214, 96) },
		material = "Glass", alpha = 0.12, shine = 0.35 } } },
	EmberStep = { motion = "press", life = 5, pieces = { { mesh = "Cos_Sole", size = 1.5, colours = { rgb(255, 140, 56) },
		cool = ASH, shine = 0.05 } } },
}

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
function ShopCatalog.wear(root: BasePart, trail: Item?, aura: Item?, tag: string)
	for _, old in ipairs(root:GetChildren()) do
		if old:GetAttribute(tag) then
			old:Destroy()
		end
	end
	if trail and trail.kind == "trail" then
		local look = LOOKS[trail.id]
		local ribbon = look and look.ribbon
		-- ITS STRANDS (the hundred-and-seventh pass): each a thin ribbon between two attachments its `width` apart, which
		-- CosmeticsClient moves about you every frame by the strand's motion (named on the top one: StrandMotion and the
		-- rest). The first top is the trail's own (PieceTrail, for its pieces). A trail with no look is one still strand.
		local strands: { Strand } = if ribbon then ribbon.strands else { { at = Vector3.new(0, -0.2, 0), motion = "still" } }
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
export type Material = { key: string, name: string, colour: Color3 }
ShopCatalog.MATERIALS = {
	{ key = "Honey", name = "Honey", colour = rgb(228, 158, 40) },
	{ key = "ButterWax", name = "Waxed butter", colour = rgb(244, 222, 150) },
	{ key = "KineticSand", name = "Kinetic sand", colour = rgb(214, 180, 140) },
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
	{ key = "Lego", name = "Lego", colour = rgb(220, 50, 50) },
	{ key = "Charcoal", name = "Charcoal", colour = rgb(60, 58, 58) },
	{ key = "Chocolate", name = "Chocolate", colour = rgb(110, 64, 36) },
	{ key = "ChocolateSolid", name = "Solid chocolate", colour = rgb(84, 48, 26) },
	{ key = "Clay", name = "Clay", colour = rgb(196, 120, 80) },
	{ key = "Cloud", name = "Cloud", colour = rgb(236, 240, 252) },
	{ key = "LambsEar", name = "Lamb's ear", colour = rgb(176, 190, 170) },
	{ key = "Ice", name = "Ice", colour = rgb(190, 226, 246) },
	{ key = "JelloSoda", name = "Jello", colour = rgb(236, 96, 120) },
	{ key = "Jellyfish", name = "Jellyfish", colour = rgb(200, 170, 240) },
	{ key = "LavaKeys", name = "Keys over lava", colour = rgb(70, 66, 72) },
	{ key = "ButterStick", name = "Butter", colour = rgb(248, 226, 130) },
	{ key = "Needoh", name = "Needoh", colour = rgb(247, 170, 200) },
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

ShopCatalog.STAMP = "a893da9c"
return ShopCatalog
