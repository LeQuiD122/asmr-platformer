--!strict
-- ServerScriptService/Services/LightingService.lua
-- Environment lighting and post-processing.
--
-- Why this is a service and not a set of properties left in the Explorer: the values
-- interact, and several of them only do anything in combination. Keeping them in one
-- readable place with the reasoning attached is worth more than saving a file, and it
-- means a fresh place file gets the right look by running rather than by remembering.
--
-- === Why lighting matters so much here ===
--
-- Five of the six materials are defined by how they interact with light rather than by
-- shape: honey and slime are glossy and translucent, butter-wax is slick, soap is
-- waxy, bubble wrap is near-colourless film. Reflectance and transparency only mean
-- something if there is contrast in the environment to reflect and light behind the
-- surface to transmit. Under flat default lighting a 0.38-reflectance honey surface
-- reflects an even grey sky and reads as matte paint, which is exactly what it did.
--
-- EnvironmentSpecularScale is the single most important value below. It controls how
-- much of the sky a glossy surface picks up, and it is what turns "amber plastic" into
-- "wet amber".
--
-- === LIGHTING ENGINE ===
--
-- ShadowSoftness and both Environment*Scale values only do anything under the
-- high-fidelity lighting engine (what older Studio called Technology = Future). Nothing
-- here can check or change it: a script can neither write Lighting.Technology NOR read
-- it, since touching it needs an internal capability, and attempting to read it throws.
--
-- On Studio versions that still expose a lighting engine selector, pick the
-- highest-fidelity option. On current versions the property appears to be gone, which
-- most likely means that engine is now the default and nothing needs doing.
--
-- Verify by eye either way: when it is active, honey and slime carry a bright specular
-- streak that moves with the camera, and shadows soften the further they fall from
-- whatever casts them. If surfaces look like matte paint regardless of viewing angle,
-- it is not active.

local Lighting = game:GetService("Lighting")

local LightingService = {}

-- Find-or-create, so re-running is safe and hand edits in the Explorer are not
-- duplicated into a second instance.
local function ensure(className: string, name: string): any
	local existing = Lighting:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing
	end
	local instance = Instance.new(className)
	instance.Name = name
	instance.Parent = Lighting
	return instance
end

-- Per-region sky palettes. `sky` is the upper atmosphere, `horizon` is what it decays
-- toward at distance; see the atmosphere block below for why those are not the same
-- thing. Add a region here and pass its name to apply().
LightingService.palettes = {
	-- Pale blue overhead falling to a dusty pink at the horizon. Warm enough at eye
	-- level to keep the liminal backdrop restful rather than cold, and it leaves the
	-- pastel platforms sitting against a complementary field instead of a grey one.
	default = {
		sky = Color3.fromRGB(196, 212, 238),
		horizon = Color3.fromRGB(228, 172, 184),
		-- FOG, and the ceiling on it is set by the sea rather than by taste.
		--
		-- 0.42 density with 1.75 haze was tried and it erased the water completely: the
		-- whole view went to one lavender wash. The reason is structural, not a matter of
		-- degree -- the sea is the FURTHEST thing in the scene, 700 studs down and out to
		-- 6200, so every stud of it sits deep in the falloff. Anything dense enough to read
		-- as a fog wall at the horizon has already eaten the ocean on the way there.
		--
		-- So this sits slightly BELOW the 0.3 it started at. The far skyline still softens
		-- into the horizon colour, which is the part worth having; what is gone is the wall.
		-- Turning it back up is a two-number edit, and the water is what pays for it.
		density = 0.26,
		haze = 1.05,
		offset = 0.08,
	},
	-- Kept as what the game looked like before the gradient, so the change is revertible
	-- by name rather than by memory.
	overcast = {
		sky = Color3.fromRGB(205, 205, 218),
		horizon = Color3.fromRGB(110, 116, 130),
		density = 0.28,
		haze = 1.1,
		offset = 0.05,
	},
	-- ===== CITY SHORE: late afternoon over the water =====
	--
	-- The level is a spiral climbing seven hundred studs above a sea, and it ends by diving into
	-- that sea. Mid-afternoon light (the default) puts the sun overhead, which is the one position
	-- that gives a flat sea nothing to do: no long glitter on the water, no colour in the sky, and
	-- a horizon that reads as a line rather than as distance. Dropping the sun to 16.9 lights the
	-- whole level along its climb, throws the glitter across the water toward the camera, and
	-- gives the towers a lit face and a shadowed one, which is what makes them look like objects
	-- rather than cut-outs.
	--
	-- LESS HAZE THAN THE LEVEL HAS TODAY, not more. The lobby sets the atmosphere for the whole
	-- game (see HubService) and the levels inherit it: density 0.32 with haze 1.6, tuned for a
	-- room whose horizon is 400 studs away. Out here that sits over a sea that reaches 6200 and
	-- turns it into one pale wash. This is a touch above the default and well under the room's.
	--
	-- The sun is also drawn LARGER. A low sun is in the picture on the dive, and Roblox's default
	-- angular size is a pinprick that reads as a lens artefact rather than as the sun.
	--
	-- CLEARER STILL, after a screenshot. The level under the old air was a PINK WALL: everything
	-- below the horizon -- sea, beach, the whole city -- went to one flat wash, because the
	-- horizon colour was pink and density and haze were high enough to paint it over everything
	-- 700 studs down. Density 0.2 and haze 0.45 keep the far skyline softening into warm light
	-- without erasing the water; the horizon is a pale gold, so what fog there is reads as late
	-- sun rather than as a coloured filter; and Offset 0.25 keeps distant silhouettes solid
	-- against the sky instead of melting into it.
	cityShore = {
		sky = Color3.fromRGB(160, 196, 236),
		horizon = Color3.fromRGB(255, 214, 176),
		density = 0.2,
		haze = 0.45,
		offset = 0.25,
		clock = 16.9,
		brightness = 2.05,
		exposure = -0.02,
		ambient = Color3.fromRGB(40, 34, 42),
		outdoor = Color3.fromRGB(130, 121, 126),
		glare = 0.6,
		sunSize = 18,
		bloom = 0.55,
		bloomThreshold = 1.0,
		rays = 0.1,
		tint = Color3.fromRGB(255, 246, 230),
		saturation = 0.09,
		contrast = 0.09,
	},
	-- ===== SKY POOLS: late morning above the clouds =====
	--
	-- The calm level, so the plainest light: the sun high and a little behind the morning, a clear
	-- blue overhead fading to a pale one at the horizon, and very little haze, because the whole
	-- view is the cloud sea and a haze thick enough to read would turn it grey. Offset keeps the
	-- tower and the far pools solid against the sky rather than melting into it.
	--
	-- CLOSE TO THE DEFAULT on purpose. Brightness, exposure and bloom are within a step of what
	-- every level already has; the pale clouds and white decks carry the brightness themselves, and
	-- pushing the light as well would take them to white.
	skyPools = {
		sky = Color3.fromRGB(150, 194, 240),
		horizon = Color3.fromRGB(214, 230, 248),
		-- See the note by EnvironmentSpecularScale: this is the level whose whole lower
		-- hemisphere is white cloud, so a glossy top face mirrors white on white. A step
		-- down, not a switch off -- the materials still need their highlight.
		specular = 0.5,
		diffuse = 0.7,
		density = 0.18,
		haze = 0.35,
		offset = 0.22,
		clock = 10.8,
		brightness = 2.1,
		exposure = -0.03,
		ambient = Color3.fromRGB(36, 40, 50),
		outdoor = Color3.fromRGB(124, 132, 146),
		glare = 0.35,
		sunSize = 14,
		bloom = 0.45,
		bloomThreshold = 1.05,
		rays = 0.06,
		tint = Color3.fromRGB(248, 252, 255),
		saturation = 0.08,
		contrast = 0.06,
	},
	-- ===== THE SUNKEN CITY: a grey afternoon over still water =====
	--
	-- The eerie level, and the eeriness is mostly AIR: a low grey-green sky and a real haze, so the
	-- far towers and the crane come out of the mist rather than standing against a hard horizon, and
	-- the city's edge is never seen. The sun is low and weak, so the water is dull rather than
	-- glittering and the eye goes down into it instead of across it.
	--
	-- SMALL STEPS, as the Flooded Halls taught: brightness and exposure only a little under the
	-- default, bloom and rays almost off, and the colour cooled and greyed by a few points. Dim, not
	-- dark. The thing's darkening of the water is the client's (SunkenCityClient), on top of this.
	sunkenCity = {
		sky = Color3.fromRGB(150, 168, 170),
		horizon = Color3.fromRGB(128, 146, 146),
		density = 0.34,
		haze = 1.3,
		offset = 0.12,
		clock = 16.2,
		brightness = 1.75,
		exposure = -0.08,
		ambient = Color3.fromRGB(34, 40, 42),
		outdoor = Color3.fromRGB(110, 120, 122),
		glare = 0.1,
		sunSize = 10,
		bloom = 0.3,
		bloomThreshold = 1.2,
		rays = 0.02,
		tint = Color3.fromRGB(232, 244, 240),
		saturation = -0.08,
		contrast = 0.08,
	},
	-- ===== THE LOBBY, and these numbers are HubService's =====
	--
	-- The room sets its own atmosphere while it builds, and says there why: the levels are meant
	-- to be the same sky from lower down. That worked while nothing else touched it. Now City
	-- Shore has a sky of its own, so the room needs a way to get its air BACK when a run ends,
	-- and that is this. If the numbers here and the ones in HubService ever disagree, HubService
	-- is the one that built the room and this is the copy to correct.
	lobby = {
		sky = Color3.fromRGB(226, 216, 232),
		horizon = Color3.fromRGB(146, 140, 178),
		density = 0.32,
		haze = 1.6,
		offset = 0.1,
		glare = 0.15,
	},
}

-- THE THREE EFFECTS THIS SERVICE OWNS. Anything else of that kind in Lighting was put there by a
-- level, and a level's look must not outlive it.
local OURS = { Bloom = true, SunRays = true, Grade = true }

-- ANYTHING A LEVEL ADDED, TAKEN AWAY AGAIN.
--
-- The Flooded Halls hang their own bloom, depth of field and grade on Lighting, and their teardown
-- only ran when the NEXT level was built -- so finishing the level and going back to the lobby left
-- the room under the halls' air, with the far end of it blurred. It is not the halls' mistake to
-- fix in one place: any level may add to the look, and every one of them can be stopped mid-run.
-- So the rule is here, where the look is owned: applying a region first takes away every
-- post-processing effect that is not one of this service's own.
function LightingService.clearLevelLook()
	for _, item in ipairs(Lighting:GetChildren()) do
		if item:IsA("PostEffect") and not OURS[item.Name] then
			item:Destroy()
		end
	end
	-- Fog is legacy and ignored while an Atmosphere exists, but a level that set it leaves it set,
	-- and anything that later removes the Atmosphere would find the halls' green.
	Lighting.FogEnd = 100000
	Lighting.FogStart = 0
end

function LightingService.apply(region: string?)
	LightingService.clearLevelLook()
	-- === Sun position ===
	-- Mid-afternoon. A high sun flattens everything and a low one throws long shadows
	-- across the whole level; this angle puts a readable specular streak on horizontal
	-- glossy surfaces, which is where every material in this game lives.
	local palette = LightingService.palettes[region or "default"] or LightingService.palettes.default
	Lighting.ClockTime = palette.clock or 14.5
	Lighting.GeographicLatitude = 12

	-- === Exposure ===
	-- Pulled back from 2.4 / 0.12. A pastel palette has most of its values already
	-- near the top of the range, so extra brightness and positive exposure have
	-- nowhere to go but toward white: the honey went paler and peachier rather than
	-- deeper. Headroom matters more than brightness when everything is light already.
	Lighting.Brightness = palette.brightness or 1.9
	Lighting.ExposureCompensation = palette.exposure or -0.05

	-- Shadows stay coloured rather than grey, and are lifted well off black: a pastel
	-- palette dies if its shadows go neutral and dark.
	Lighting.Ambient = palette.ambient or Color3.fromRGB(38, 36, 44)
	Lighting.OutdoorAmbient = palette.outdoor or Color3.fromRGB(122, 120, 134)

	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.32 -- Future only

	-- === The important two (Future/ShadowMap only) ===
	-- Specular is deliberately higher than diffuse. Diffuse ambient flattens form;
	-- specular is what gives a glossy surface its highlight and therefore its read as
	-- wet. This is the difference between honey and orange plastic.
	--
	-- PER REGION, because on one level it went too far. Environment specular is the sky
	-- reflected in a surface, and on Sky Pools the sky is white cloud in every direction
	-- you look DOWN -- so a translucent chunk seen from above was a sheet of reflected
	-- white over a background of white cloud, and vanished. From the side and from
	-- underneath the same chunk read perfectly, which is the signature of a reflection
	-- rather than of a transparency. Lower it where the sky is the background.
	Lighting.EnvironmentDiffuseScale = palette.diffuse or 0.65
	Lighting.EnvironmentSpecularScale = palette.specular or 0.8

	-- === Atmosphere: the sky gradient ===
	--
	-- Gives distance a soft falloff so a 240-stud level reads as having depth instead of
	-- every chunk sitting in the same flat plane -- and it is also where the sky's COLOUR
	-- comes from, which is what makes the gradient buildable at all.
	--
	-- The two colours are not interchangeable. `Color` tints the atmosphere as a whole and
	-- carries the upper sky; `Decay` is what light decays TOWARD over distance, so it
	-- lands at the horizon. Blue above and pink at the horizon is therefore
	-- Color = blue, Decay = pink -- and swapping them gives a sunset, not a mistake.
	--
	-- Region is a parameter because it will need to be. Levels are meant to differ later,
	-- and a palette threaded through one table now is a change of argument then, rather
	-- than a hunt through this file for every hardcoded colour.
	-- ROBLOX IGNORES FogStart/FogEnd/FogColor WHENEVER AN ATMOSPHERE EXISTS, which is the
	-- one thing to know before trying to add fog here. The obvious way to get Minecraft's
	-- hard distance fog is those three legacy properties; setting them while the Atmosphere
	-- below is present does nothing at all, silently. Deleting the Atmosphere to reach them
	-- would work and would also throw away the sky gradient, since Color and Decay are what
	-- paint blue overhead and pink at the horizon. The fog is therefore built out of
	-- Density, Haze and Offset instead.
	local atmosphere = ensure("Atmosphere", "Atmosphere")
	atmosphere.Density = palette.density
	atmosphere.Offset = palette.offset
	atmosphere.Color = palette.sky
	atmosphere.Decay = palette.horizon
	atmosphere.Glare = palette.glare or 0.4
	atmosphere.Haze = palette.haze

	-- THE SUN ITSELF, for a level that puts it in frame. Left alone unless a palette asks, so the
	-- lobby's own Sky (which sets the moon and the stars with it) is not overwritten by this.
	if palette.sunSize then
		local sky = Lighting:FindFirstChildOfClass("Sky")
		if sky then
			sky.SunAngularSize = palette.sunSize
		end
	end

	-- === Bloom ===
	-- Threshold just above 1 so only genuine highlights bloom. Lower and the whole
	-- pastel palette glows, which reads as fog rather than as gloss.
	local bloom = ensure("BloomEffect", "Bloom")
	bloom.Enabled = true
	bloom.Intensity = palette.bloom or 0.45
	bloom.Size = 24
	bloom.Threshold = palette.bloomThreshold or 1.05

	-- === Sun rays ===
	-- Very low. This is atmosphere, not a lens effect; at high intensity it washes the
	-- screen whenever the sun clips the edge of frame.
	local sunRays = ensure("SunRaysEffect", "SunRays")
	sunRays.Enabled = true
	sunRays.Intensity = palette.rays or 0.06
	sunRays.Spread = 0.55

	-- === Grade ===
	-- Slight warmth and a little saturation, to push the palette toward "confectionery"
	-- rather than "plastic toy". Contrast stays low on purpose: this is a calm game.
	local grade = ensure("ColorCorrectionEffect", "Grade")
	grade.Enabled = true
	grade.Brightness = 0.01
	grade.Contrast = palette.contrast or 0.08
	grade.Saturation = palette.saturation or 0.05
	grade.TintColor = palette.tint or Color3.fromRGB(255, 252, 246)

	-- NO Technology CHECK HERE.
	--
	-- Lighting.Technology cannot be read by a normal script either, not just written:
	-- it requires an internal capability, and touching it throws
	-- "cannot read 'Technology' (lacking capability RobloxScript)". That error took out
	-- the rest of Bootstrap, including level generation, which is a very expensive way
	-- to deliver a reminder. It stays documented in the header instead.
end

return LightingService
