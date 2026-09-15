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
}

function LightingService.apply(region: string?)
	-- === Sun position ===
	-- Mid-afternoon. A high sun flattens everything and a low one throws long shadows
	-- across the whole level; this angle puts a readable specular streak on horizontal
	-- glossy surfaces, which is where every material in this game lives.
	Lighting.ClockTime = 14.5
	Lighting.GeographicLatitude = 12

	-- === Exposure ===
	-- Pulled back from 2.4 / 0.12. A pastel palette has most of its values already
	-- near the top of the range, so extra brightness and positive exposure have
	-- nowhere to go but toward white: the honey went paler and peachier rather than
	-- deeper. Headroom matters more than brightness when everything is light already.
	Lighting.Brightness = 1.9
	Lighting.ExposureCompensation = -0.05

	-- Shadows stay coloured rather than grey, and are lifted well off black: a pastel
	-- palette dies if its shadows go neutral and dark.
	Lighting.Ambient = Color3.fromRGB(38, 36, 44)
	Lighting.OutdoorAmbient = Color3.fromRGB(122, 120, 134)

	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.32 -- Future only

	-- === The important two (Future/ShadowMap only) ===
	-- Specular is deliberately higher than diffuse. Diffuse ambient flattens form;
	-- specular is what gives a glossy surface its highlight and therefore its read as
	-- wet. This is the difference between honey and orange plastic.
	Lighting.EnvironmentDiffuseScale = 0.65
	Lighting.EnvironmentSpecularScale = 0.8

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
	local palette = LightingService.palettes[region or "default"] or LightingService.palettes.default
	local atmosphere = ensure("Atmosphere", "Atmosphere")
	atmosphere.Density = palette.density
	atmosphere.Offset = palette.offset
	atmosphere.Color = palette.sky
	atmosphere.Decay = palette.horizon
	atmosphere.Glare = 0.4
	atmosphere.Haze = palette.haze

	-- === Bloom ===
	-- Threshold just above 1 so only genuine highlights bloom. Lower and the whole
	-- pastel palette glows, which reads as fog rather than as gloss.
	local bloom = ensure("BloomEffect", "Bloom")
	bloom.Enabled = true
	bloom.Intensity = 0.45
	bloom.Size = 24
	bloom.Threshold = 1.05

	-- === Sun rays ===
	-- Very low. This is atmosphere, not a lens effect; at high intensity it washes the
	-- screen whenever the sun clips the edge of frame.
	local sunRays = ensure("SunRaysEffect", "SunRays")
	sunRays.Enabled = true
	sunRays.Intensity = 0.06
	sunRays.Spread = 0.55

	-- === Grade ===
	-- Slight warmth and a little saturation, to push the palette toward "confectionery"
	-- rather than "plastic toy". Contrast stays low on purpose: this is a calm game.
	local grade = ensure("ColorCorrectionEffect", "Grade")
	grade.Enabled = true
	grade.Brightness = 0.01
	grade.Contrast = 0.08
	grade.Saturation = 0.05
	grade.TintColor = Color3.fromRGB(255, 252, 246)

	-- NO Technology CHECK HERE.
	--
	-- Lighting.Technology cannot be read by a normal script either, not just written:
	-- it requires an internal capability, and touching it throws
	-- "cannot read 'Technology' (lacking capability RobloxScript)". That error took out
	-- the rest of Bootstrap, including level generation, which is a very expensive way
	-- to deliver a reminder. It stays documented in the header instead.
end

return LightingService
