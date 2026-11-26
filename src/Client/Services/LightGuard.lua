--!strict
-- StarterPlayerScripts/Services/LightGuard.lua
-- EVERY DARKNESS STAYS WHERE IT BELONGS (pass 266, from your note: "the darkness should not transfer anywhere, same with
-- every other darkness, they should stay on their own levels and do their own thing after which they will no longer
-- apply").
--
-- A level's client darkens your screen on its own: under the Sunken City's sea, in its aquarium's murk and its drain,
-- the Flooded Halls' hold and the Maw's throat, City Shore under the water, the Sky Pools' storm, the peek at the Maw, the
-- back rooms' grade and dread, and the dark while he has you. Each puts itself back as it ends; this is the net under
-- all of them. Two things it does:
--   * WHEN A PLACE IS SET (LightingService writes the place's look on Lighting with a new LookStamp each time): the air
--     and the light are put back to that place's own (its values, kept on Lighting as attributes), and every darkness
--     belonging to another place is taken away.
--   * WHEN YOU LEAVE A PLACE OF YOUR OWN (InLevel: the back rooms; InClimb), its darkness is taken away a moment later.
-- A darkness of the place you are in is never touched.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")

local LightGuard = {}

-- Each darkness (a child of Lighting, by name) and the place it belongs to: a LightingService region, or "backRooms".
LightGuard.OWNERS = {
	SunkenShade = "sunkenCity",
	SeaDark = "sunkenCity",
	SeaDarkBlur = "sunkenCity",
	AquariumMurk = "sunkenCity",
	DrainBlur = "sunkenCity",
	DrainUnder = "sunkenCity",
	UnderCityShore = "cityShore",
	SplashFlash = "cityShore",
	HoldDark = "floodedHalls",
	ThroatTint = "floodedHalls",
	PeekDark = "floodedHalls",
	SkyStorm = "skyPools",
	BackRoomsGrade = "backRooms",
	Dread = "backRooms",
	CaughtDark = "backRooms",
} :: { [string]: string }

local function region(): string
	local me = Players.LocalPlayer
	if me:GetAttribute("InLevel") == "backRooms" then
		return "backRooms"
	end
	local look = Lighting:GetAttribute("LookRegion")
	return if typeof(look) == "string" then look else "default"
end

-- Every darkness not of `here` taken away.
local function clearOthers(here: string): number
	local cleared = 0
	for _, item in ipairs(Lighting:GetChildren()) do
		local owner = LightGuard.OWNERS[item.Name]
		if owner and owner ~= here then
			item:Destroy()
			cleared += 1
		end
	end
	return cleared
end

-- The air and the light put back to the place's own, as LightingService set them.
local function restoreLook()
	if Players.LocalPlayer:GetAttribute("InClimb") then
		return -- (the climb's sky is the climb's: ClimbClient puts it back itself as you leave)
	end
	local air = Lighting:FindFirstChildOfClass("Atmosphere")
	local function put(target: Instance?, property: string, key: string)
		local value = Lighting:GetAttribute(key)
		if target and value ~= nil then
			pcall(function()
				if (target :: any)[property] ~= value then
					(target :: any)[property] = value
				end
			end)
		end
	end
	put(air, "Density", "LookDensity")
	put(air, "Offset", "LookOffset")
	put(air, "Color", "LookColor")
	put(air, "Decay", "LookDecay")
	put(air, "Glare", "LookGlare")
	put(air, "Haze", "LookHaze")
	put(Lighting, "Brightness", "LookBrightness")
	put(Lighting, "ExposureCompensation", "LookExposure")
	put(Lighting, "ClockTime", "LookClock")
	put(Lighting, "Ambient", "LookAmbient")
	put(Lighting, "OutdoorAmbient", "LookOutdoor")
end

local function settle(why: string)
	local cleared = clearOthers(region())
	if cleared > 0 then
		-- (Whatever left a darkness behind left its air behind with it.)
		restoreLook()
		print(("LightGuard: %d darkness(es) from another place cleared (%s)."):format(cleared, why))
	end
end

function LightGuard.start()
	local me = Players.LocalPlayer
	-- A PLACE SET: its own air back, and nothing of anywhere else.
	Lighting:GetAttributeChangedSignal("LookStamp"):Connect(function()
		restoreLook()
		settle("a new place")
	end)
	-- OUT OF THE BACK ROOMS: theirs gone a moment later (their own goodbye first), and the air back.
	local wasRooms = me:GetAttribute("InLevel") == "backRooms"
	me:GetAttributeChangedSignal("InLevel"):Connect(function()
		local inRooms = me:GetAttribute("InLevel") == "backRooms"
		if wasRooms and not inRooms then
			task.delay(1.5, function()
				if me:GetAttribute("InLevel") ~= "backRooms" then
					local cleared = clearOthers(region())
					if cleared > 0 then
						restoreLook()
						print(("LightGuard: %d darkness(es) of the back rooms cleared after leaving."):format(cleared))
					end
				end
			end)
		end
		wasRooms = inRooms
	end)
	-- AND NOW AND THEN, the net: anything of another place still about is taken away (never the place you are in).
	task.spawn(function()
		while true do
			task.wait(3)
			pcall(settle, "the check")
		end
	end)
	print("LightGuard: running")
end

LightGuard.STAMP = "3beebf02"
return LightGuard
