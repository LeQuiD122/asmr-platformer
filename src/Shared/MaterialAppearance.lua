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
	Ice = {
		color = Color3.fromRGB(214, 238, 250),
		material = Enum.Material.Glass,
		transparency = 0.58,
		reflectance = 0.42,
		baseColor = Color3.fromRGB(74, 108, 138),
		baseMaterial = Enum.Material.Glass,
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
		baseColor = Color3.fromRGB(196, 194, 186),
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
	JelloSoda = {
		color = Color3.fromRGB(244, 158, 96),
		material = Enum.Material.Glass,
		transparency = 0.22,
		reflectance = 0.14,
		baseColor = Color3.fromRGB(198, 108, 58),
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
	LavaKeys = {
		color = Color3.fromRGB(46, 40, 38),
		material = Enum.Material.Neon,
		transparency = 0,
		reflectance = 0.03,
		baseColor = Color3.fromRGB(24, 20, 19),
		baseMaterial = Enum.Material.Slate,
	},
	ButterStick = {
		color = Color3.fromRGB(246, 232, 176),
		material = Enum.Material.SmoothPlastic,
		transparency = 0,
		reflectance = 0.02,
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
		material = Enum.Material.Glass,
		transparency = 0.10,
		-- Not raised past this: above roughly 0.45 a Glass surface starts mirroring
		-- the skybox and washes out again regardless of Color, which is the same trap
		-- that turned the old footfall marks pink.
		reflectance = 0.38,
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
		material = Enum.Material.Glass,
		transparency = 0.3,
		-- Reflectance kept low on purpose: above ~0.2 a Glass part mirrors the
		-- skybox and washes out to pale blue-white, which is what turned the
		-- honey smears pink. Wetness comes from transparency here, not mirroring.
		reflectance = 0.12,
		baseColor = Color3.fromRGB(64, 128, 60),
		baseMaterial = Enum.Material.Concrete,
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
		color = Color3.fromRGB(232, 243, 250),
		material = Enum.Material.SmoothPlastic,
		transparency = 0.45,
		-- GLOSS IS HOW A BUBBLE READS, the same thing that turned out to be true of the
		-- surface marks. A pocket has no colour of its own to set it apart -- it is the
		-- same film as the flat seal around it -- so the only thing separating them is
		-- that a curved surface gathers the sky into a tight highlight and a flat one
		-- does not. At 0.04 there was no highlight to gather and the domes rendered as
		-- pale discs barely lighter than the film they stood on.
		reflectance = 0.22,
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
local NO_MAPS_BY_DESIGN: { [string]: boolean } = { Needoh = true }

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
local PartVariants: { [string]: string } = {
	-- To texture lego: make a MaterialVariant under MaterialService named LegoABS with
	-- BaseMaterial = Plastic, paste the Lego_Color / Lego_Normal / Lego_Roughness ids into
	-- it, and this starts working with no code change.
	Lego = "LegoABS",
	Soap = "",
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
	applyPartVariant(part, materialName)
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
local SlabVariants: { [Enum.Material]: string } = {
	[Enum.Material.Concrete] = "",
	[Enum.Material.Plaster] = "",
	[Enum.Material.Slate] = "",
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
		if not service:FindFirstChild(wanted) then
			warn(
				("MaterialAppearance: no MaterialVariant named '%s' under MaterialService, so "
					.. "%s slabs render untextured. Harmless -- but the name is set in this file, "
					.. "so one of the two is a typo."):format(wanted, part.Material.Name)
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

return MaterialAppearance
