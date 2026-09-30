--!strict
-- StarterPlayerScripts/Services/AmbienceService.lua
-- WHAT EACH LEVEL SOUNDS LIKE WHEN NOTHING IS HAPPENING: a bed of sound under it, on this player's own
-- screen, and under every level the same thing, very low: the Hold itself, a drone you notice only
-- when it stops (LORE.md). It fades in when you arrive on a level (the server marks the player
-- InLevel) and goes when an ending's scene starts (Cinema.hush marks them Hushed), and does not come
-- back until the next level. The lobby has its own sound and none of this.
--
--   City Shore      the sea on the sands far below, and the Hold.
--   Sky Pools       wind across the roof, the party's one song far off through a wall, and the Hold.
--   Sunken City     the harbour at night, water lapping, a bell somewhere, and the Hold.
--   Flooded Halls   the baths: a hum like old strip lights, air moving, far water, and the Hold.
--
-- THE SOUNDS are audio/gen_material_sfx.py's (audio/ambience/). Import them and put them in a Folder
-- named AmbienceSounds in SoundService; each is used by name. Without them, Roblox's own sounds stand
-- in, slowed, where there is one that will do, and a bed with nothing to stand in for it is left out.

local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local AmbienceService = {}

local WATER = "rbxasset://sounds/impact_water.mp3"
local BASS = "rbxasset://sounds/bass.mp3"
local WIND = "rbxasset://sounds/action_falling.mp3"

type Bed = { name: string, volume: number, fallback: string?, speed: number? }
local BEDS: { [string]: { Bed } } = {
	cityShore = {
		{ name = "ShoreSea", volume = 0.5, fallback = WATER, speed = 0.22 },
		{ name = "HoldDrone", volume = 0.22, fallback = BASS, speed = 0.3 },
	},
	skyPools = {
		{ name = "RoofWind", volume = 0.4, fallback = WIND, speed = 0.35 },
		{ name = "PartyFar", volume = 0.28 },
		{ name = "HoldDrone", volume = 0.18, fallback = BASS, speed = 0.3 },
	},
	sunkenCity = {
		{ name = "HarbourNight", volume = 0.42, fallback = WATER, speed = 0.16 },
		{ name = "HoldDrone", volume = 0.28, fallback = BASS, speed = 0.26 },
	},
	floodedHalls = {
		{ name = "BathsHum", volume = 0.3 },
		{ name = "HoldDrone", volume = 0.3, fallback = BASS, speed = 0.24 },
	},
}

local playing: { Sound } = {}
local level: string? = nil

local function stopAll(seconds: number)
	for _, s in ipairs(playing) do
		if s.Parent then
			TweenService:Create(s, TweenInfo.new(seconds, Enum.EasingStyle.Sine), { Volume = 0 }):Play()
			game:GetService("Debris"):AddItem(s, seconds + 0.5)
		end
	end
	table.clear(playing)
end

local function bed(spec: Bed): Sound?
	local folder = SoundService:FindFirstChild("AmbienceSounds")
	local own = folder and folder:FindFirstChild(spec.name)
	local s: Sound
	if own and own:IsA("Sound") then
		s = own:Clone()
	elseif spec.fallback then
		s = Instance.new("Sound")
		s.SoundId = spec.fallback
		s.PlaybackSpeed = spec.speed or 1
	else
		return nil
	end
	s.Name = "Ambience_" .. spec.name
	s.Looped = true
	s.Volume = 0
	s.Parent = SoundService
	s:Play()
	TweenService:Create(s, TweenInfo.new(3, Enum.EasingStyle.Sine), { Volume = spec.volume }):Play()
	return s
end

local function refresh()
	local player = Players.LocalPlayer
	local now = player:GetAttribute("InLevel")
	local wanted = if typeof(now) == "string" then now else nil
	if wanted ~= level then
		-- A NEW LEVEL (or the lobby): whatever hushed the last one is over.
		level = wanted
		stopAll(1.5)
		player:SetAttribute("Hushed", nil)
		local beds = wanted and BEDS[wanted]
		if beds then
			for _, spec in ipairs(beds) do
				local s = bed(spec)
				if s then
					table.insert(playing, s)
				end
			end
		end
	end
end

function AmbienceService.start()
	local player = Players.LocalPlayer
	player:GetAttributeChangedSignal("InLevel"):Connect(refresh)
	player:GetAttributeChangedSignal("Hushed"):Connect(function()
		if player:GetAttribute("Hushed") then
			stopAll(2.5)
		end
	end)
	refresh()
	print("AmbienceService: running")
end

return AmbienceService
