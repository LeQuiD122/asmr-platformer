--!strict
-- ReplicatedStorage/Shared/MaterialAppearance.lua
-- Visual identity per material: pastel palette, glossy/matte shaders per the
-- GDD's Visual Direction section. Shared by ChunkBuilder (server, sets look
-- at construction time) and DeformationRenderer (client, drives per-material
-- tween "feel" on deformation).

export type Appearance = {
	color: Color3,
	material: Enum.Material,
	transparency: number,
	reflectance: number,
	-- The base slab beneath the deformable surface tiles. Darker and matte, so
	-- the platform reads as a solid object with a material layer on top rather
	-- than as one flat-shaded box. Built-in Roblox materials are used
	-- deliberately: Sand, Ice, Glass, ForceField and Plaster carry real
	-- albedo/normal detail with no texture upload required.
	baseColor: Color3,
	baseMaterial: Enum.Material,
}

export type TweenProfile = {
	duration: number,
	easingStyle: Enum.EasingStyle,
	easingDirection: Enum.EasingDirection,
	sinkY: number,       -- how far the sub-region visually sinks/dips
	squashScale: number, -- XZ scale multiplier applied during "deformed" (1 = none)
}

local Appearances: { [string]: Appearance } = {
	-- stable / no material: soft lavender-pink, gentle gloss
	["stable"] = {
		color = Color3.fromRGB(235, 225, 240),
		material = Enum.Material.Plaster, -- matte with real surface grain
		transparency = 0,
		reflectance = 0.02,
		baseColor = Color3.fromRGB(176, 166, 190),
		baseMaterial = Enum.Material.Concrete,
	},
	-- Warm ivory keycaps on a slightly deeper chassis. SmoothPlastic rather than Plastic:
	-- Roblox's Plastic carries a faint moulded speckle that fights the PBR map, and a
	-- keycap's whole surface story is a fine even grain the map is supplying itself.
	--
	-- Reflectance is deliberately low. "Creamy" describes a MATTE plastic -- PBT, not the
	-- shiny ABS that goes greasy under a thumb -- so the material has to read as soft and
	-- dry. A gloss here would make it look like the slime.
	-- CREAM CAPS ON A BLUSH CASE. `color` is the mesh (the keycaps), `baseColor` is the
	-- slab showing through beneath it (the case) -- the material is an OVERLAY precisely so
	-- these can differ.
	--
	-- Blush rather than the mint or lilac the reference boards also come in, because the
	-- palette is already spoken for: slime owns green, soap owns pale blue, butter owns
	-- yellow, sand owns tan, bubble wrap owns white, honey owns amber. Pink is the one
	-- hue left, and against a blue sea and a lavender skyline it is the one that reads from
	-- furthest away.
	--
	-- Reflectance stays low. "Creamy" describes MATTE plastic -- PBT, not the shiny ABS
	-- that goes greasy under a thumb -- so a gloss here would make it look like slime.
	CreamyKeyboard = {
		color = Color3.fromRGB(247, 240, 228),
		material = Enum.Material.SmoothPlastic,
		transparency = 0,
		reflectance = 0.03,
		baseColor = Color3.fromRGB(233, 156, 174),
		baseMaterial = Enum.Material.SmoothPlastic,
	},
	-- Pale glacial blue, genuinely translucent, and the most reflective surface in the
	-- game. Ice is the only material here that should look COLD, and the palette has no
	-- other cold colour -- soap's pale blue is chalky and matte, which reads as powder.
	-- The separation is transparency and reflectance, not hue.
	-- A LID OVER NOTHING, not a block of frozen butter.
	--
	-- The first version borrowed butter's numbers along with its meshes and looked like
	-- exactly that: a solid pale slab. But the whole point of the material is that the
	-- sheet is the only thing holding you, so it has to LOOK like a sheet -- you should be
	-- able to see down through it and find no floor there. Hence transparency well past
	-- half and the highest reflectance in the game: the surface reads by what it reflects
	-- rather than by its own colour, which is how real ice reads.
	--
	-- The base is darker and colder than the surface, so what shows through the sheet is
	-- deep water rather than more ice.
	--
	-- ICE IS NOT GLASS, and that is why it vanished from above. A Glass part draws only what is
	-- OPAQUE behind it: every transparent part behind it -- the Sunken City's sea, Sky Pools' cloud
	-- and pools, the ice's own coating -- is simply left out. Looking down on a sheet of ice, the only
	-- thing behind it IS transparent water, so the ice showed the drowned city straight through with
	-- a faint pale wash and read as open water: you were standing on something that was not there.
	-- From the side, with opaque scenery behind it, it looked fine, which is exactly how it was
	-- reported. Roblox's own Ice material is translucent without that rule, and it is ice. A little
	-- less transparent than the glass was, a little bluer, and less mirrored (the Ice material has its
	-- own sheen), so the sheet reads as a sheet over the water rather than as a hole in it.
	Ice = {
		color = Color3.fromRGB(196, 228, 248),
		material = Enum.Material.Ice,
		transparency = 0.38,
		reflectance = 0.2,
		baseColor = Color3.fromRGB(74, 108, 138),
		baseMaterial = Enum.Material.Ice,
	},
	-- Amber soda, translucent and glossy, over a deeper syrup base. Warm on purpose: it
	-- sits next to ice in the material list and the two should never be mistaken for each
	-- other at a glance, which is a real risk when both are shiny and see-through.
	-- Near-white, and Sand as the base material rather than Plastic: it has the faint grain
	-- that keeps a white surface from reading as paper. The sparkle lives in the roughness
	-- map, not here.
	Salt = {
		color = Color3.fromRGB(244, 245, 246),
		material = Enum.Material.Sand,
		transparency = 0,
		reflectance = 0.06,
		baseColor = Color3.fromRGB(206, 208, 212),
		baseMaterial = Enum.Material.Sand,
	},
	-- NEON, and it is the only material in the game that uses it.
	--
	-- Neon ignores lighting and renders at full brightness, which is wrong for almost
	-- everything and exactly right for incandescent rock -- lava is not lit, it is a light
	-- source. The Lava_Color map is what carries the shape: near-black over the obsidian
	-- rafts, blinding orange in the channels. On any other material this would look like a
	-- mistake; here it is the only way the melt reads as hot rather than as painted.
	Lava = {
		color = Color3.fromRGB(255, 148, 52),
		material = Enum.Material.Neon,
		transparency = 0,
		reflectance = 0,
		baseColor = Color3.fromRGB(28, 22, 24),
		baseMaterial = Enum.Material.Slate,
	},
	-- Pale slurry, matte, faintly translucent. Nothing about oobleck is striking and it
	-- should not be: the whole material is a behaviour, and a loud surface would promise
	-- something the mechanic does not deliver.
	Oobleck = {
		color = Color3.fromRGB(236, 234, 226),
		material = Enum.Material.SmoothPlastic,
		transparency = 0.06,
		reflectance = 0.10,
		baseColor = Color3.fromRGB(198, 196, 186),
		baseMaterial = Enum.Material.SmoothPlastic,
	},
	-- VIOLET, and the reason is the rest of the roster rather than the buttons themselves.
	--
	-- These were arcade red, which put them next to lego red in a game that already runs
	-- amber, butter yellow, slime green, terracotta, two browns and four whites. Red was the
	-- one hue already spoken for, and two red chunks at distance are one chunk seen twice.
	--
	-- Violet is the only part of the wheel this game has never used, so a button pad is
	-- identifiable from across the spiral with nothing else to confuse it with. The housing
	-- stays near-black, which is what a control panel actually looks like and what makes the
	-- caps read as lit from within.
	Buttons = {
		color = Color3.fromRGB(148, 92, 226),
		material = Enum.Material.Plastic,
		transparency = 0,
		reflectance = 0.14,
		baseColor = Color3.fromRGB(44, 40, 54),
		baseMaterial = Enum.Material.SmoothPlastic,
	},
	-- White with a cold base. The blue in the hollows comes from Snow_Color; what this sets
	-- is the crown, which has to stay genuinely white or the whole chunk reads as ice.
	Snow = {
		color = Color3.fromRGB(250, 251, 255),
		material = Enum.Material.Snow,
		transparency = 0,
		reflectance = 0.04,
		baseColor = Color3.fromRGB(178, 194, 218),
		baseMaterial = Enum.Material.Snow,
	},
	-- Cream, and Foam is a real Roblox material -- it is matte and slightly porous, which
	-- is the whole read here. Nothing shiny anywhere: foam has no specular at all and is
	-- the least reflective surface in the game.
	Foam = {
		color = Color3.fromRGB(238, 232, 218),
		material = Enum.Material.Foil,
		transparency = 0,
		reflectance = 0,
		baseColor = Color3.fromRGB(196, 188, 170),
		baseMaterial = Enum.Material.Foil,
	},
	-- Off-white wall plastic. The colour that matters on this material is not here at all
	-- -- it is the light that comes on when a switch latches, which the renderer adds.
	LightSwitch = {
		color = Color3.fromRGB(242, 240, 232),
		material = Enum.Material.SmoothPlastic,
		transparency = 0,
		reflectance = 0.04,
		-- DARK BEHIND THE PLATES (the two-hundred-and-eighth pass): the board they are screwed to, seen in the gaps
		-- between them. It was the plates' own cream a shade down, and twenty switches read as one sheet.
		baseColor = Color3.fromRGB(104, 98, 92),
		baseMaterial = Enum.Material.SmoothPlastic,
	},
	-- Lego red, and Plastic rather than SmoothPlastic: ABS has a slight sheen with a
	-- little depth to it, where SmoothPlastic reads as vinyl.
	Lego = {
		color = Color3.fromRGB(206, 62, 54),
		material = Enum.Material.Plastic,
		transparency = 0,
		reflectance = 0.06,
		baseColor = Color3.fromRGB(148, 40, 34),
		baseMaterial = Enum.Material.Plastic,
	},
	-- Nearly black, but NOT black. A true black surface has no shape -- there is nothing
	-- for light to fall off -- so this sits a few points above it, and the graphite sheen
	-- in Charcoal_Roughness does the rest of the work.
	Charcoal = {
		color = Color3.fromRGB(44, 42, 41),
		material = Enum.Material.Slate,
		transparency = 0,
		reflectance = 0.05,
		baseColor = Color3.fromRGB(24, 23, 22),
		baseMaterial = Enum.Material.Slate,
	},
	-- Dark milk chocolate, glossy. The reflectance is high for an opaque material because
	-- tempered chocolate really is close to a mirror, and that gloss is the thing the
	-- melt has to visibly take away.
	Chocolate = {
		color = Color3.fromRGB(94, 58, 34),
		material = Enum.Material.SmoothPlastic,
		transparency = 0,
		reflectance = 0.20,
		baseColor = Color3.fromRGB(58, 34, 20),
		baseMaterial = Enum.Material.SmoothPlastic,
	},
	-- COLDER AND HARDER than the warm bar: a shade darker, and the highest reflectance of
	-- any opaque surface in the game. Properly tempered chocolate is close to a mirror, and
	-- that mirror is what the warm version spends its whole life losing -- so the pair reads
	-- as a temperature difference at a glance, before either has been stepped on.
	ChocolateSolid = {
		color = Color3.fromRGB(78, 47, 27),
		material = Enum.Material.SmoothPlastic,
		transparency = 0,
		reflectance = 0.30,
		baseColor = Color3.fromRGB(48, 28, 16),
		baseMaterial = Enum.Material.SmoothPlastic,
	},
	-- Terracotta, and the most matte thing here after foam. Deliberately unremarkable:
	-- the footprints are what you are meant to look at.
	Clay = {
		color = Color3.fromRGB(178, 116, 88),
		material = Enum.Material.Sandstone,
		transparency = 0,
		reflectance = 0,
		baseColor = Color3.fromRGB(128, 80, 60),
		baseMaterial = Enum.Material.Sandstone,
	},
	-- Nearly white and PARTLY TRANSPARENT, which no other solid surface here is. You have
	-- to be able to half see through the thing you are standing on, because the whole
	-- proposition is that it is not really holding you.
	Cloud = {
		color = Color3.fromRGB(246, 249, 255),
		material = Enum.Material.SmoothPlastic,
		transparency = 0.22,
		reflectance = 0.02,
		baseColor = Color3.fromRGB(198, 212, 232),
		baseMaterial = Enum.Material.SmoothPlastic,
	},
	-- Silvery sage, and FABRIC rather than plastic or grass. Roblox's Fabric material
	-- gives a matte, slightly fibrous surface with no specular hit, which is the closest
	-- the engine gets to felt -- and the absence of a highlight is most of what separates
	-- a furry leaf from a waxy one. Grass would have been the obvious pick and is wrong:
	-- it is coarse and dark, and this plant is neither.
	--
	-- The base under it is a deeper green, so where the nap parts the colour that shows
	-- through is blade rather than more silver.
	LambsEar = {
		color = Color3.fromRGB(176, 187, 152),
		material = Enum.Material.Fabric,
		transparency = 0,
		reflectance = 0,
		baseColor = Color3.fromRGB(108, 124, 92),
		baseMaterial = Enum.Material.Fabric,
	},
	-- NOT GLASS, for the reason soap is not: under this lighting a Glass part refracts and mirrors the
	-- sky, and against Sky Pools' open sky, at a low angle, the soda washed out to the colour of the
	-- sky behind it and the chunk vanished. SmoothPlastic with a transparency is still see-through
	-- jelly and keeps its orange from every side.
	JelloSoda = {
		color = Color3.fromRGB(244, 158, 96),
		material = Enum.Material.SmoothPlastic,
		transparency = 0.2,
		reflectance = 0.08,
		baseColor = Color3.fromRGB(198, 108, 58),
		baseMaterial = Enum.Material.SmoothPlastic,
	},
	-- A pale violet bell, see-through enough to show the tentacles hanging under it.
	--
	-- NOT GLASS, unlike jello and slime, and on purpose: its level is the Sunken City, where
	-- the sea under the route is Glass, and Glass leaves out anything transparent behind it
	-- -- a Glass bell would show no sea through itself, only a hole in it. SmoothPlastic with a
	-- transparency shows everything behind it. A little reflectance for the wet sheen.
	Jellyfish = {
		color = Color3.fromRGB(222, 190, 240),
		material = Enum.Material.SmoothPlastic,
		transparency = 0.24,
		reflectance = 0.08,
		baseColor = Color3.fromRGB(168, 126, 196),
		baseMaterial = Enum.Material.SmoothPlastic,
	},
	-- OPAQUE, and that is the point of the colour choice as much as the hue. Every other
	-- soft surface in this game you can see into -- jello, slime, soap and honey are all
	-- glass with a transparency. A Needoh is a sealed skin with dough behind it: nothing
	-- passes through it, and the light it does return is a broad satin sheen rather than a
	-- highlight. Reflectance is low but not zero for that sheen.
	--
	-- Teal because it is the one region of the palette nothing else occupies. Twenty-three
	-- materials in, "a colour nobody else has" is a real constraint: a new surface that
	-- reads at a glance as an existing one is a new surface nobody notices.
	-- Warmer and paler than ButterWax's 240,212,130, which is the wax coating rather than
	-- the butter. Cut butter is nearly cream with only a hint of yellow, and it is matte:
	-- the wax is the shiny half of that pairing, so any reflectance here would read as the
	-- shell this material exists to be without.
	-- Nearly black, because the GLOW is the colour. A keycap that is already bright orange
	-- has nowhere to go when you stand on it, and the whole effect here is the difference
	-- between a key you have touched and one you have not. Cooled basalt is the resting
	-- state; the heat is applied by the deformation renderer, on top of this.
	--
	-- Neon rather than a plain material so the hot state actually emits rather than merely
	-- being a lighter grey.
	-- (The keys' own colours are their colourway's now, KEYCAPS below; this is the tile under each, never seen. Not Neon:
	-- nothing in the game glows by being Neon.)
	LavaKeys = {
		color = Color3.fromRGB(46, 40, 38),
		material = Enum.Material.Basalt,
		transparency = 0,
		reflectance = 0.03,
		baseColor = Color3.fromRGB(24, 20, 19),
		baseMaterial = Enum.Material.Slate,
	},
	-- Bare butter (the hundred-and-fifty-third pass): the soft pale yellow of a stick out of the fridge a while, with the
	-- faint sheen of its own fat on it, and nothing over it.
	ButterStick = {
		color = Color3.fromRGB(248, 232, 168),
		material = Enum.Material.SmoothPlastic,
		transparency = 0,
		reflectance = 0.07,
		baseColor = Color3.fromRGB(198, 176, 116),
		baseMaterial = Enum.Material.SmoothPlastic,
	},
	Needoh = {
		color = Color3.fromRGB(72, 200, 196),
		material = Enum.Material.SmoothPlastic,
		transparency = 0,
		reflectance = 0.06,
		baseColor = Color3.fromRGB(34, 128, 128),
		baseMaterial = Enum.Material.SmoothPlastic,
	},
	Honey = {
		-- Deeper and more saturated than before, and less transparent.
		--
		-- At 255,186,56 and 0.18 transparency the surface rendered as pale cream: a
		-- light colour seen through a translucent material with nothing behind it
		-- washes out toward white. Thick honey is dark and saturated, and it reads as
		-- deep because of that darkness plus the highlight, not because you can see
		-- through it. Transparency is kept low rather than removed so the drips and
		-- the thin rim still glow at the edges where the material is genuinely thin.
		color = Color3.fromRGB(238, 148, 24),
		-- NOT GLASS (the hundred-and-eighteenth pass), for the reason soda and soap are not: under this
		-- lighting a Glass part shows the sky behind it more than its own colour, and against Sky Pools'
		-- and Hill House's open sky the honey went the colour of the sky and vanished. SmoothPlastic with a
		-- little transparency keeps its amber from every side; the sheen is reflectance.
		material = Enum.Material.SmoothPlastic,
		transparency = 0.08,
		reflectance = 0.24,
		baseColor = Color3.fromRGB(122, 74, 12),
		baseMaterial = Enum.Material.Concrete,
	},
	ButterWax = {
		-- THE BUTTER, not the wax. This is the body of the platform, and it is what
		-- shows through once the shell cracks -- so it is the warm yellow of a stick of
		-- butter, and the pale wax coating is derived from it in ChunkBuilder rather
		-- than being a second entry here.
		--
		-- Was near-white cream on Ice, which is a crystalline blue-tinted material: it
		-- read as a slab of ice, and the whole surface was one flat value with nothing
		-- underneath to reveal.
		color = Color3.fromRGB(240, 212, 130),
		material = Enum.Material.SmoothPlastic,
		transparency = 0,
		-- Soft sheen. Butter is not glossy and it is certainly not crystalline.
		reflectance = 0.05,
		baseColor = Color3.fromRGB(198, 168, 96),
		baseMaterial = Enum.Material.Plaster,
	},
	KineticSand = {
		color = Color3.fromRGB(206, 176, 126),
		material = Enum.Material.Sand, -- granular, genuinely textured
		transparency = 0,
		reflectance = 0,
		baseColor = Color3.fromRGB(140, 116, 80),
		baseMaterial = Enum.Material.Slate,
	},
	Slime = {
		color = Color3.fromRGB(126, 220, 116),
		-- NOT GLASS (the hundred-and-eighteenth pass), as honey is not: against open sky a Glass slime went
		-- the sky's colour and vanished. SmoothPlastic, see-through enough to read as wet.
		material = Enum.Material.SmoothPlastic,
		transparency = 0.22,
		reflectance = 0.12,
		baseColor = Color3.fromRGB(64, 128, 60),
		baseMaterial = Enum.Material.Concrete,
	},
	-- A BAKED BISCUIT: golden and matte, its crumbs a grain (Sand) that catches the light unevenly, the way a cookie's
	-- top does; darker underneath, where it was on the tray. The chips are ChunkBuilder's (CHIPS), not a colour here.
	Cookie = {
		color = Color3.fromRGB(212, 156, 92),
		material = Enum.Material.Sand,
		transparency = 0,
		reflectance = 0,
		baseColor = Color3.fromRGB(150, 100, 54),
		baseMaterial = Enum.Material.Sand,
	},
	Soap = {
		-- Soft rose. Near-white before, which put it within a few values of the pale
		-- lavender stable platforms -- the one material that drops you and the one that
		-- never does, looking alike at a glance. Pink is also simply what a pressed
		-- soap bar looks like, and it is now the only warm pastel in the set: honey is
		-- orange, wax cream, sand tan, slime green, bubble wrap near-colourless.
		color = Color3.fromRGB(240, 176, 194),
		-- NOT Glass, and this is the whole reason soap looked "translucent" no matter
		-- what Transparency said. Under the high-fidelity lighting engine a Glass part
		-- genuinely refracts and picks up the skybox, so against open sky the bar went
		-- pale blue and read as ice. A bar of soap is opaque and satin, not glassy.
		material = Enum.Material.SmoothPlastic,
		transparency = 0,
		-- A soft sheen rather than a mirror. At 0.3 on Glass it was reflecting enough
		-- sky to wash out toward white on its own.
		reflectance = 0.06,
		baseColor = Color3.fromRGB(198, 134, 152),
		baseMaterial = Enum.Material.Plaster,
	},
	BubbleWrap = {
		-- Real bubble wrap is near-colourless polythene: you read it from the
		-- bubbles and the highlights, not from a tint. ForceField was wrong here
		-- and produced the deep blue: it renders as a tinted energy shell with an
		-- edge glow no matter what Color is set, ignoring the pale blue entirely.
		-- A touch bluer and a touch less clear (the hundred-and-fifty-fourth pass): in the squish room the domes read as
		-- milky bowls, the film and the body under it one pale mass.
		-- Less clouded and brighter (the two-hundred-and-thirty-sixth pass, seen in play on 2026-11-21: at 0.36 the
		-- sheet was one milky grey tray, the domes and the film between them the same pale mass). Nearly opaque, as
		-- you asked of anything wrapped ("no glass look"), and each dome told from the next by its own glint.
		color = Color3.fromRGB(232, 244, 252),
		material = Enum.Material.SmoothPlastic,
		transparency = 0.12,
		-- GLOSS IS HOW A BUBBLE READS, the same thing that turned out to be true of the
		-- surface marks. A pocket has no colour of its own to set it apart -- it is the
		-- same film as the flat seal around it -- so the only thing separating them is
		-- that a curved surface gathers the sky into a tight highlight and a flat one
		-- does not. At 0.04 there was no highlight to gather and the domes rendered as
		-- pale discs barely lighter than the film they stood on. 0.3 now, for a sharper glint on each.
		reflectance = 0.34,
		-- Darkened, because a translucent sheet is only as legible as whatever is behind
		-- it. At (176, 192, 206) the slab sat almost exactly at the film's own value, so
		-- 45% transparency revealed nothing and the wrap and the thing being wrapped
		-- read as a single pale mass.
		baseColor = Color3.fromRGB(138, 154, 172),
		baseMaterial = Enum.Material.Plaster,
	},
}

local TweenProfiles: { [string]: TweenProfile } = {
	Honey = {
		duration = 0.35,
		easingStyle = Enum.EasingStyle.Sine,
		easingDirection = Enum.EasingDirection.InOut,
		sinkY = -0.7, -- sinks deepest, slow settle (sticky-drag read)
		squashScale = 0.94,
	},
	ButterWax = {
		duration = 0.08,
		easingStyle = Enum.EasingStyle.Back,
		easingDirection = Enum.EasingDirection.Out,
		sinkY = -0.35, -- fast snap-crack, shallow
		squashScale = 1.0,
	},
	KineticSand = {
		duration = 0.25,
		easingStyle = Enum.EasingStyle.Quad,
		easingDirection = Enum.EasingDirection.Out,
		sinkY = -0.5, -- gentle imprint
		squashScale = 0.97,
	},
	Slime = {
		duration = 0.18,
		easingStyle = Enum.EasingStyle.Elastic,
		easingDirection = Enum.EasingDirection.Out,
		sinkY = -0.85, -- stretch-down before launch reads as anticipation
		squashScale = 0.8,
	},
	Cookie = {
		duration = 0.45,
		easingStyle = Enum.EasingStyle.Quad,
		easingDirection = Enum.EasingDirection.In,
		sinkY = -1.0, -- it cracks, then crumbles toward the hole
		squashScale = 0.9,
	},
	Soap = {
		duration = 0.5,
		easingStyle = Enum.EasingStyle.Quad,
		easingDirection = Enum.EasingDirection.In,
		sinkY = -1.1, -- crumble sinks progressively toward dissolve
		squashScale = 0.86,
	},
	BubbleWrap = {
		duration = 0.06,
		easingStyle = Enum.EasingStyle.Back,
		easingDirection = Enum.EasingDirection.Out,
		sinkY = -0.6, -- sharp punchy pop per hit
		squashScale = 0.85,
	},
}

local MaterialAppearance = {
	Appearances = Appearances,
	TweenProfiles = TweenProfiles,
}

-- ===== KEYCAP COLOURWAYS (the hundred-and-fifty-fifth pass) =====
--
-- From your test of 2026-10-31: "there could be more colour palettes". A keyboard's keys are parts of their own now, one to
-- a cell, each with its letter printed on it (attachKeycap in ChunkBuilder), so a colourway is nothing but colours: the
-- letter keys', the number row's, the two accent keys' (the corners, where an Esc and an Enter would be), each with its
-- letter's colour, and the case under them. Every creamy keyboard is painted one of CREAMY_WAYS as it is placed in a level
-- (ChunkService), so two in a row are seldom the same; the keys over lava are always Lava. Named for what they look like,
-- never after anybody's keycap set.
type Colourway = { alpha: Color3, alphaInk: Color3, mod: Color3, modInk: Color3, accent: Color3, accentInk: Color3,
	case: Color3 }
local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end
local KEYCAPS: { [string]: Colourway } = {
	StrawberryMilk = { alpha = rgb(248, 241, 230), alphaInk = rgb(206, 92, 128), mod = rgb(240, 172, 190), modInk = rgb(255, 246, 240),
		accent = rgb(230, 98, 140), accentInk = rgb(255, 244, 246), case = rgb(233, 156, 174) },
	Dusk = { alpha = rgb(86, 56, 148), alphaInk = rgb(222, 206, 255), mod = rgb(46, 38, 96), modInk = rgb(206, 190, 255),
		accent = rgb(255, 176, 136), accentInk = rgb(70, 40, 110), case = rgb(30, 26, 62) },
	Mint = { alpha = rgb(184, 238, 218), alphaInk = rgb(24, 112, 98), mod = rgb(244, 250, 246), modInk = rgb(30, 130, 112),
		accent = rgb(44, 168, 146), accentInk = rgb(240, 255, 250), case = rgb(56, 152, 134) },
	PeachSoda = { alpha = rgb(255, 222, 196), alphaInk = rgb(214, 96, 74), mod = rgb(248, 160, 128), modInk = rgb(255, 244, 234),
		accent = rgb(255, 214, 104), accentInk = rgb(170, 70, 50), case = rgb(242, 176, 148) },
	LilacCloud = { alpha = rgb(232, 222, 252), alphaInk = rgb(112, 82, 176), mod = rgb(248, 246, 254), modInk = rgb(130, 100, 196),
		accent = rgb(156, 116, 226), accentInk = rgb(250, 246, 255), case = rgb(196, 182, 236) },
	Matcha = { alpha = rgb(240, 238, 222), alphaInk = rgb(82, 122, 62), mod = rgb(156, 186, 114), modInk = rgb(246, 244, 230),
		accent = rgb(72, 112, 62), accentInk = rgb(240, 238, 222), case = rgb(124, 154, 98) },
	Retro = { alpha = rgb(234, 228, 210), alphaInk = rgb(62, 60, 58), mod = rgb(180, 178, 170), modInk = rgb(48, 46, 44),
		accent = rgb(232, 124, 54), accentInk = rgb(250, 244, 230), case = rgb(204, 198, 180) },
	Midnight = { alpha = rgb(54, 58, 74), alphaInk = rgb(132, 222, 242), mod = rgb(36, 40, 58), modInk = rgb(110, 200, 226),
		accent = rgb(92, 202, 232), accentInk = rgb(26, 32, 48), case = rgb(24, 26, 38) },
	Honeycomb = { alpha = rgb(252, 214, 126), alphaInk = rgb(122, 72, 22), mod = rgb(232, 164, 64), modInk = rgb(255, 246, 222),
		accent = rgb(132, 82, 32), accentInk = rgb(252, 214, 126), case = rgb(202, 142, 54) },
	-- The keys over lava: cooled rock, letters the heat coming through (lit from inside, ChunkBuilder), and no case (a pool).
	Lava = { alpha = rgb(46, 40, 38), alphaInk = rgb(255, 150, 58), mod = rgb(34, 30, 30), modInk = rgb(255, 128, 44),
		accent = rgb(84, 40, 30), accentInk = rgb(255, 204, 110), case = rgb(24, 20, 19) },
}
MaterialAppearance.KEYCAPS = KEYCAPS
MaterialAppearance.CREAMY_WAYS = { "StrawberryMilk", "Dusk", "Mint", "PeachSoda", "LilacCloud", "Matcha", "Retro", "Midnight",
	"Honeycomb" }

-- Every keyboard under `container` (or `container` itself) painted: the keys over lava always Lava, a creamy board `way`, or
-- one of CREAMY_WAYS at random. Each key keeps its colours as attributes (KeyColour, KeyInk), so what heats or lights one
-- can give it back.
function MaterialAppearance.paintKeys(container: Instance, way: string?)
	local slabs: { BasePart } = {}
	local function consider(item: Instance)
		if item:IsA("BasePart") then
			local material = item:GetAttribute("Material")
			if material == "CreamyKeyboard" or material == "LavaKeys" then
				table.insert(slabs, item)
			end
		end
	end
	consider(container)
	for _, item in ipairs(container:GetDescendants()) do
		consider(item)
	end
	for _, slab in ipairs(slabs) do
		local material = slab:GetAttribute("Material")
		local ways = MaterialAppearance.CREAMY_WAYS
		local name = if material == "LavaKeys" then "Lava" else way or ways[math.random(1, #ways)]
		local colours = KEYCAPS[name]
		if not colours then
			continue
		end
		slab:SetAttribute("Colourway", name)
		if material == "CreamyKeyboard" then
			slab.Color = colours.case
			for _, child in ipairs(slab:GetChildren()) do
				if child:IsA("BasePart") and child.Name:match("^CornerBevel") then
					child.Color = colours.case
				end
			end
		end
		for _, tile in ipairs(slab:GetChildren()) do
			local cap = tile:FindFirstChild("Keycap")
			if cap and cap:IsA("BasePart") then
				local role = cap:GetAttribute("Role")
				local colour = if role == "accent" then colours.accent elseif role == "mod" then colours.mod else colours.alpha
				local ink = if role == "accent" then colours.accentInk elseif role == "mod" then colours.modInk else colours.alphaInk
				cap.Color = colour
				cap:SetAttribute("KeyColour", colour)
				cap:SetAttribute("KeyInk", ink)
				local gui = cap:FindFirstChild("Legend")
				local letter = gui and gui:FindFirstChild("Letter")
				if letter and letter:IsA("TextLabel") then
					letter.TextColor3 = ink
				end
			end
		end
	end
end

-- Surface look, for the deformable sub-region tiles.
-- === PBR surface maps are attached BY HAND, in Studio ===
--
-- Not a preference. SurfaceAppearance.ColorMap, NormalMap and RoughnessMap all require the
-- Plugin capability, so a runtime Script cannot write them:
--
--   The current thread cannot write 'ColorMap' (lacking capability Plugin)
--
-- and that error is thrown, not returned. Trying it from here aborted attachSkinnedVisual,
-- which aborted buildSubRegions, which aborted the whole ChunkBuilder run -- six of thirteen
-- chunk templates never got built and the level came up with holes in it. A cosmetic
-- feature took out level generation, which is precisely the failure LightingService is
-- wrapped in a pcall to prevent.
--
-- THE RIGHT PLACE IS THE TEMPLATE, and it needs no code at all. Add one SurfaceAppearance
-- by hand to each imported mesh in ReplicatedStorage/Assets/TileMeshes:
--
--   Honey_Platform_Skinned   -> SurfaceAppearance   AlphaMode = Overlay
--                               ColorMap     = rbxassetid://... (Honey_Color.png)
--                               NormalMap    = rbxassetid://... (Honey_Normal.png)
--                               RoughnessMap = rbxassetid://... (Honey_Roughness.png)
--   Slime_Platform_Skinned   -> the same, with the Slime maps
--
-- ChunkBuilder clones these templates, and Clone() takes children with it, so every
-- platform in the level inherits the maps from the one object you edited.
--
-- Overlay rather than Transparency, so the ColorMap's alpha blends it OVER part.Color
-- instead of replacing it. That keeps the palette above in charge of the hue.

-- Warns once per material when a rigged template arrives without maps. Advisory only: the
-- material renders exactly as it did before, which is why this cannot be left to be noticed.
local surfaceWarned: { [string]: boolean } = {}

-- MATERIALS THAT ARE FINISHED WITHOUT MAPS, so the warning below stays a real warning.
--
-- The advisory exists to catch a rigged mesh that was MEANT to have PBR maps and arrived
-- without them. A material that was never going to have any is not that, and warning about
-- it every session trains the reader to skim past the line that matters.
--
-- Needoh qualifies for a reason, not as an exemption of convenience: honey needs maps
-- because its surface detail IS the drips and the film, and slime because its is the
-- stringing. A Needoh is a smooth satin skin -- all of its detail is the six blocks in the
-- geometry, and a normal map over that would be inventing texture the object does not have.
-- A jellyfish's likewise: its canals, warts and horseshoes are geometry (gen_jellyfish.py), and
-- the rest of it is a clear skin, which is the one thing a normal map cannot add to.
local NO_MAPS_BY_DESIGN: { [string]: boolean } = { Needoh = true, Jellyfish = true }

local function noteMissingSurface(part: BasePart, materialName: string?)
	if not materialName or surfaceWarned[materialName] or not part:IsA("MeshPart") then
		return
	end
	if NO_MAPS_BY_DESIGN[materialName] then
		surfaceWarned[materialName] = true
		return
	end
	if part:FindFirstChildOfClass("SurfaceAppearance") then
		surfaceWarned[materialName] = true
		return
	end
	surfaceWarned[materialName] = true
	warn(
		("MaterialAppearance: %s has no SurfaceAppearance on its mesh, so its PBR maps are "
			.. "not applied. Add one to the template in Assets/TileMeshes -- see the notes in "
			.. "this file. Harmless: the material renders as it did before."):format(materialName)
	)
end

-- === Textures on PARTS, per material ===
--
-- SurfaceAppearance does nothing on a Part -- no warning, no error, just the old look -- so
-- every material built out of Parts rather than meshes has been going untextured. That was
-- fine while soap was the only one; lego joining it made it worth solving properly.
--
-- MaterialVariant is the mechanism that works, and it splits the same way SurfaceAppearance
-- does: a variant's ColorMap needs the Plugin capability, so the VARIANT is authored by hand
-- under MaterialService and a script only ever writes its NAME, which is a plain string.
--
-- KEYED BY MATERIAL, not by base material like SlabVariants below. A variant only applies to
-- parts whose Material matches its BaseMaterial, and several of these share a base -- lego
-- and the loose bricks are both Plastic -- so keying on the base would hand one material's
-- texture to another's parts. The name is looked up by what the part IS.
--
-- Blank means not authored yet, and blank is safe: the part renders exactly as it does now.
-- A name that does not exist is also safe -- Roblox falls back to the base material silently
-- -- which is why applyPartVariant says so out loud the first time.
-- THE CHUNKS' OWN SURFACES (the two-hundred-and-first pass, from your note of 2026-11-05: "you can also improve the
-- textures of the chunks themselves"). Made in Studio's material generator, one kept of the four it offers, under
-- MaterialService.ChunkSurfaces: Needoh's soft-touch silicone, fine-grained (it was bare smooth plastic), soap's waxy
-- bar with its soft dents (soap's name was blank here, so it never wore one), and the plain stable chunks' trowelled
-- plaster ("stable" is what a part with no material is dressed as, apply). Each is near-white and Organic, so the part's
-- own colour still says which material it is and no tile repeats.
local PartVariants: { [string]: string } = {
	-- To texture lego: make a MaterialVariant under MaterialService named LegoABS with
	-- BaseMaterial = Plastic, paste the Lego_Color / Lego_Normal / Lego_Roughness ids into
	-- it, and this starts working with no code change.
	Lego = "LegoABS",
	Soap = "ChunkSoap",
	Needoh = "ChunkNeedoh",
	stable = "ChunkStable",
}

local partVariantsUsable = true
local partVariantWarned: { [string]: boolean } = {}

local function applyPartVariant(part: BasePart, materialName: string?)
	if not (partVariantsUsable and materialName) then
		return
	end
	local wanted = PartVariants[materialName]
	if not wanted or wanted == "" then
		return
	end

	local ok = pcall(function()
		part.MaterialVariant = wanted
	end)
	if not ok then
		-- Off permanently after one failure. This module already took out a whole
		-- ChunkBuilder run by writing a property that turned out to need a capability --
		-- six chunk templates never built and the level came up with holes -- and this
		-- runs per part, thousands of times, so a pcall every call is not affordable but
		-- a boolean afterwards is.
		partVariantsUsable = false
		warn("[MaterialAppearance] MaterialVariant could not be written; part textures disabled.")
		return
	end
	if part.MaterialVariant ~= wanted and not partVariantWarned[wanted] then
		partVariantWarned[wanted] = true
		warn(("[MaterialAppearance] No MaterialVariant named '%s' under MaterialService, so %s "
			.. "parts are showing their base material. Create it and paste the %s_* ids in.")
			:format(wanted, materialName, materialName))
	end
end

function MaterialAppearance.apply(part: BasePart, materialName: string?)
	local appearance = (materialName and Appearances[materialName]) or Appearances["stable"]
	part.Color = appearance.color
	part.Material = appearance.material
	part.Transparency = appearance.transparency
	part.Reflectance = appearance.reflectance
	-- A part with no material is dressed as "stable" above, and wears stable's surface too.
	applyPartVariant(part, materialName or "stable")
	noteMissingSurface(part, materialName)
end

-- === Slab textures, via MaterialVariant ===
--
-- The slabs are Parts, not MeshParts, and SurfaceAppearance does NOTHING on a Part -- no
-- warning, no error, just the old look. MaterialVariant is the mechanism that works there,
-- and it splits along the same line as SurfaceAppearance did: a variant's ColorMap needs the
-- Plugin capability, so the VARIANT is built by hand under MaterialService and a script only
-- ever writes its NAME, which is a plain string and perfectly writable.
--
-- One name per base material, because a variant only applies to parts whose Material equals
-- its BaseMaterial. All three can point at the SAME three uploaded images: a variant's maps
-- are independent of its base, so this is three small objects sharing one texture set rather
-- than three sets.
--
-- Blank means not made yet, and blank is safe -- the slab renders exactly as it does today.
-- A name that does not exist in MaterialService is also safe: Roblox silently falls back to
-- the base material, which is why the check below exists to say so out loud.
-- NAMED (the hundred-and-seventieth pass): blank until then, so no slab ever wore its stone. YOURS (the
-- hundred-and-seventy-seventh): you made all three in Studio long ago, Slab maps on, under names of your own, and the
-- names never reached this table; read through the Studio MCP on 2026-11-04, they are these. tools/make_variants.lua
-- makes any that are missing under the same names.
local SlabVariants: { [Enum.Material]: string } = {
	[Enum.Material.Concrete] = "ConcreteMeshTile",
	[Enum.Material.Plaster] = "PlasterMeshTile",
	[Enum.Material.Slate] = "SlateMeshTile",
}

-- Turns off permanently after one failure.
--
-- Writing MaterialVariant is a string assignment and should never throw, but this module
-- already took out an entire ChunkBuilder run by writing a property that turned out to need
-- a capability -- six chunk templates never built, level came up with holes. applyBase runs
-- per slab, thousands of times, so a pcall on every call is not affordable; a single boolean
-- afterwards is. Cheap insurance against exactly the mistake already made once.
local variantsUsable = true
local variantWarned: { [string]: boolean } = {}

local function applySlabVariant(part: BasePart)
	if not variantsUsable then
		return
	end
	local wanted = SlabVariants[part.Material]
	if not wanted or wanted == "" then
		return
	end

	if not variantWarned[wanted] then
		variantWarned[wanted] = true
		local service = game:GetService("MaterialService")
		if not service:FindFirstChild(wanted, true) then
			warn(
				("MaterialAppearance: no MaterialVariant named '%s' under MaterialService yet, so %s slabs are "
					.. "untextured. Harmless; tools/make_variants.lua makes it (HANDOFF, Harrow Bay's surfaces).")
					:format(wanted, part.Material.Name)
			)
		end
	end

	local ok = pcall(function()
		part.MaterialVariant = wanted
	end)
	if not ok then
		variantsUsable = false
		warn("MaterialAppearance: MaterialVariant could not be written; slab textures disabled.")
	end
end

-- Base slab look, for the solid body under the tiles. Always opaque: the slab
-- is what gives the platform visible thickness from the side.
function MaterialAppearance.applyBase(part: BasePart, materialName: string?)
	local appearance = (materialName and Appearances[materialName]) or Appearances["stable"]
	part.Color = appearance.baseColor
	part.Material = appearance.baseMaterial
	part.Transparency = 0
	part.Reflectance = 0
	applySlabVariant(part)
end

function MaterialAppearance.getTweenProfile(materialName: string?): TweenProfile?
	if not materialName then
		return nil
	end
	return TweenProfiles[materialName]
end

-- ===== HARROW BAY'S SURFACES (the hundred-and-sixty-ninth pass) =====
--
-- From your note of 2026-11-03: "improve the textures of the lobby and the overall texture quality of the levels, I want
-- it to be a very pleasant looking game". The lobby and the levels' buildings were Roblox's own materials, the lobby's
-- decks plain plastic. Now nine textures made for this game (blender/gen_surfaces.py: deck boards with their grain,
-- knots and nails; timber; flagstones; the sea wall's coursed stone; render; veined marble; cast stone; canvas; painted
-- iron), each a MaterialVariant under MaterialService, and dress() gives every part the one for its material: the
-- lobby all nine (HubService), a level's own buildings only the stone, wood, render and marble (its metal is machinery
-- and its cloth is costume: LEVEL_SURFACES, Bootstrap). A MaterialVariant's maps are Studio's to set and never a
-- script's, so the nine are made once by hand (HANDOFF, Harrow Bay's surfaces); until one is there its parts are
-- Roblox's own material, as before, and the server says once which are missing. A part that already wears a variant (a
-- slab's, the pool tile), a textured mesh, or anything worn by a character keeps its own.
MaterialAppearance.SURFACES = {
	[Enum.Material.WoodPlanks] = "HarrowBoards",
	[Enum.Material.Wood] = "HarrowTimber",
	[Enum.Material.Slate] = "HarrowFlags",
	[Enum.Material.Rock] = "HarrowStone",
	[Enum.Material.Marble] = "HarrowMarble",
	[Enum.Material.Plaster] = "HarrowRender",
	[Enum.Material.Concrete] = "HarrowCast",
	[Enum.Material.Fabric] = "HarrowCanvas",
	[Enum.Material.Metal] = "HarrowPaint",
} :: { [Enum.Material]: string }
MaterialAppearance.LEVEL_SURFACES = {
	[Enum.Material.WoodPlanks] = true,
	[Enum.Material.Wood] = true,
	[Enum.Material.Slate] = true,
	[Enum.Material.Rock] = true,
	[Enum.Material.Marble] = true,
	[Enum.Material.Plaster] = true,
	[Enum.Material.Concrete] = true,
} :: { [Enum.Material]: boolean }

local surfacesSaid = false

-- Worn by a character (a townsperson, a statue of you): its clothes are its own.
local function worn(item: Instance): boolean
	local model = item:FindFirstAncestorWhichIsA("Model")
	while model do
		if model:FindFirstChildOfClass("Humanoid") then
			return true
		end
		model = model:FindFirstAncestorWhichIsA("Model")
	end
	return false
end

-- A chunk's own (the squish room's samples among them, the hundred-and-seventy-sixth pass): its slab carries its
-- material's name (ChunkBuilder), and everything on the slab hangs from it. Never dressed: the chunks are the game's
-- materials and wear their own.
local function chunkPart(item: Instance): boolean
	local at: Instance? = item
	while at and at:IsA("BasePart") do
		if at:GetAttribute("Material") ~= nil then
			return true
		end
		at = at.Parent
	end
	return false
end

-- ===== EACH LEVEL ITS OWN SURFACES (the hundred-and-eighty-fifth pass) =====
--
-- From your note of 2026-11-04: "use your new skills to generate better looking textures and models and stuff for the
-- existing levels, right now I think the priority to generate them for levels 4 and 3". Surfaces made in Studio's
-- material generator for what those two levels are built of, each a MaterialVariant under MaterialService.LevelSurfaces
-- (one kept of the four it offers): the Flooded Halls' damp waterworks concrete, the bath-house iron's worn off-white
-- enamel and its glazed white tile; the Sunken City's sea-stained cast stone, salt-bitten brick, rough render and wet
-- slate. A level's own wins over Harrow Bay's for that material where it has been made (and reaches the halls' metal,
-- which Harrow Bay's leaves alone); where it has not, the level is as it was. (Its timber is Harrow Bay's boards, and its
-- cars and trams keep their paint: the rust it made was red and cyan, and would have coloured all of them.)
-- NOT ONE SURFACE ON EVERYTHING (the hundred-and-ninety-second pass, from your note of 2026-11-05: "add variety to the
-- textures of the boxed buildings ... they look ugly rn and repetitive ... look into this repetitiveness overall on all
-- the levels"). A level's surface for a material may be a POOL: each building (the Sunken City numbers its buildings as it
-- builds them, their parts' Look) or else each part (by where it stands) takes one of the pool's that are made, so a
-- street is not one wall of the same stone. Harrow Bay's own are in the pools; a name not made yet is passed over.
MaterialAppearance.WORLD_SURFACES = {
	FloodedHalls = {
		[Enum.Material.Concrete] = "HallsConcrete",
		[Enum.Material.Metal] = "HallsPaint",
		-- HallsGlaze since the two-hundred-and-fifty-sixth pass ("polish level 4's textures and models in the pools"):
		-- small cream glazed tiles in running bond. HallsTile's big khaki tiles with bright grout read as brick under the
		-- halls' green light, on every wall and column. HallsTile is kept in LevelSurfaces to go back to.
		[Enum.Material.CeramicTiles] = "HallsGlaze",
	},
	SunkenCity = {
		-- (No CityStone since the two-hundred-and-forty-first pass: on a wall it read as blue-black camouflage
		-- blotches at any scale, the aquarium's tower worst of all. Its thousand-odd parts take these two.)
		[Enum.Material.Concrete] = { "HarrowCast", "CityAshlar" },
		[Enum.Material.Brick] = "CityBrick",
		[Enum.Material.Plaster] = { "CityRender", "HarrowRender", "CityWash" },
		[Enum.Material.Slate] = { "CitySlate", "HarrowFlags" },
	},
	-- THE SKY POOLS IN THEIR OWN STONE (the two-hundred-and-fourth pass, from your note of 2026-11-06: "I want the texture
	-- colours to be better"). They wore what was made for other places: Harrow Bay's marble, veined black in heavy
	-- scribbles, on the basin, the bowls and every pool's coping; the drowned city's dark blue ashlar on half the columns
	-- and the tower; Harrow Bay's grey flagstones with their dark joints underfoot. A lido in the sky is white marble with
	-- soft grey veins, pale warm stone, and cream travertine round the water. Its cast stone still shares with Harrow
	-- Bay's pale one, so it is never one surface on everything.
	SkyPools = {
		[Enum.Material.Concrete] = { "SkyStone", "HarrowCast" },
		[Enum.Material.Plaster] = { "HarrowRender", "CityWash" },
		[Enum.Material.Marble] = "SkyMarble",
		[Enum.Material.Slate] = "SkyPaving",
	},
	HillHouse = {
		[Enum.Material.Plaster] = { "HarrowRender", "CityWash" },
		[Enum.Material.Slate] = { "HarrowFlags", "CitySlate" },
	},
} :: { [string]: { [Enum.Material]: string | { string } } }

-- LAID WITHOUT A REPEAT (the two-hundred-and-first pass, from your note of 2026-11-05: "they look good but they are too
-- repetitive"). Harrow Bay's own surfaces were laid square: every ten to sixteen studs the same blotch of cast stone, the
-- same swirl in the marble, in a grid any wall wider than a few tiles shows. Roblox will lay a surface Organic, the same
-- maps turned and shifted patch by patch so that nothing repeats; asked for here, once, for those with no courses, joints
-- or grain to keep in line. The sea wall's coursed stone, the flagstones, the boards and the timber stay square.
MaterialAppearance.ORGANIC = { "HarrowCast", "HarrowRender", "HarrowMarble", "HarrowPaint" }
local laidOrganic = false
local function layOrganic(MaterialService: MaterialService)
	if laidOrganic then
		return
	end
	laidOrganic = true
	for _, name in ipairs(MaterialAppearance.ORGANIC) do
		local variant = MaterialService:FindFirstChild(name, true)
		if variant and variant:IsA("MaterialVariant") then
			pcall(function()
				variant.MaterialPattern = Enum.MaterialPattern.Organic
			end)
		end
	end
end

-- Every part under `root` given the surface for its material (only those in `only`, if given, or in `own`), and every part
-- added under it later; a level's `own` surface (WORLD_SURFACES), or one of its pool, first where it is made. Returns the
-- connection that dresses the ones added later.
function MaterialAppearance.dress(root: Instance, only: { [Enum.Material]: boolean }?,
	own: { [Enum.Material]: string | { string } }?): RBXScriptConnection
	local MaterialService = game:GetService("MaterialService")
	layOrganic(MaterialService)
	local have: { [string]: boolean } = {}
	local missing: { string } = {}
	for _, name in pairs(MaterialAppearance.SURFACES) do
		local variant = MaterialService:FindFirstChild(name, true)
		have[name] = variant ~= nil and variant:IsA("MaterialVariant")
		if not have[name] then
			table.insert(missing, name)
		end
	end
	-- A level's own, each material's pool of the ones that are made.
	local pools: { [Enum.Material]: { string } } = {}
	for material, entry in pairs(own or {}) do
		local names: { string } = if type(entry) == "table" then entry else { entry :: string }
		local made: { string } = {}
		for _, name in ipairs(names) do
			local variant = MaterialService:FindFirstChild(name, true)
			have[name] = variant ~= nil and variant:IsA("MaterialVariant")
			if have[name] then
				table.insert(made, name)
			end
		end
		pools[material] = made
	end
	if #missing > 0 and not surfacesSaid then
		surfacesSaid = true
		table.sort(missing)
		warn(("[server] Harrow Bay's surfaces: %d of 9 MaterialVariants are not under MaterialService yet (%s), so "
			.. "those parts are Roblox's own materials. Upload the maps in textures/, then paste tools/make_variants.lua "
			.. "into Studio's Command Bar (HANDOFF, Make the surfaces).")
			:format(#missing, table.concat(missing, ", ")))
	end
	local function one(item: Instance)
		if not item:IsA("BasePart") or item.MaterialVariant ~= "" then
			return
		end
		if (item:IsA("MeshPart") and item.TextureID ~= "") or item:FindFirstChildOfClass("SurfaceAppearance") then
			return
		end
		-- Which of the pool: the building's own number where it has one, or else where the part stands.
		local pool = pools[item.Material]
		local ownName: string? = nil
		if pool and #pool > 0 then
			local look = item:GetAttribute("Look")
			local at = item.Position
			local index = if typeof(look) == "number" then look else math.floor(at.X / 37) + math.floor(at.Z / 41) * 7
			ownName = pool[(math.floor(index) % #pool) + 1]
		end
		local useOwn = ownName ~= nil and have[ownName] == true
		if only and not only[item.Material] and not useOwn then
			return
		end
		if chunkPart(item) then
			return
		end
		local name = if useOwn then ownName else MaterialAppearance.SURFACES[item.Material]
		if name and have[name] and not worn(item) then
			item.MaterialVariant = name
		end
	end
	for _, item in ipairs(root:GetDescendants()) do
		one(item)
	end
	return root.DescendantAdded:Connect(one)
end

MaterialAppearance.STAMP = "6bdd71ba"
return MaterialAppearance
