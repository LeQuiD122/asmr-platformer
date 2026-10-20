--!strict
-- ReplicatedStorage/Shared/WaterSounds.lua
-- THE LEVELS' WATER (the ninety-eighth pass, from "water splashing ... it is too repetitive"). Every splash, drip, lap
-- and pour in the levels was the engine's one splash, impact_water.mp3, at another pitch: all the water in the game was
-- one sound. Now each is water of its own kind (audio/gen_water_sfx.py, in a Folder SoundService.WaterSounds), and a
-- one-shot is one of several takes, never the same one twice running:
--
--   splash   a body going into water (Splash_x6: six takes in one upload, a slot each)
--   dip      a hand or a foot in water, a step into a pool, a kick (Dip_x8)
--   drip     a drip into a puddle, a pool, onto wet stone (Drip_x8)
--   lap      water lapping at a stone edge (Lap, a seamless bed)
--   pour     water falling into water: a waterfall's foot, a spout into a basin (Pour)
--   stream   water running fast and shallow (Stream)
--
-- Server and client alike: `WaterSounds.dress(sound, kind)` sets a Sound to it before it is played. Without the folder
-- (not imported yet), it sets the old splash and says so by returning false, so the caller keeps its old pitch for it.

local SoundService = game:GetService("SoundService")

local WaterSounds = {}

WaterSounds.FALLBACK = "rbxasset://sounds/impact_water.mp3"

type Family = { sheet: string?, bed: string?, slot: number?, takes: number? }
-- The sheets' slots and takes are gen_water_sfx.py's SLOTS (check_audio.py holds them to it).
local FAMILIES: { [string]: Family } = {
	splash = { sheet = "Splash_x6", slot = 2, takes = 6 },
	dip = { sheet = "Dip_x8", slot = 1, takes = 8 },
	drip = { sheet = "Drip_x8", slot = 1, takes = 8 },
	lap = { bed = "Lap" },
	pour = { bed = "Pour" },
	stream = { bed = "Stream" },
}
local last: { [string]: number } = {}

-- `sound` set to `kind`: a take of its sheet (only that take: PlaybackRegion) or its bed, from SoundService.WaterSounds,
-- at its own pitch give or take a little. False (and the old splash set) when the folder or the sound is not there.
function WaterSounds.dress(sound: Sound, kind: string): boolean
	local family = FAMILIES[kind]
	local folder = SoundService:FindFirstChild("WaterSounds")
	local name = family and (family.sheet or family.bed)
	local own = if folder and name then folder:FindFirstChild(name) else nil
	if not (family and own and own:IsA("Sound")) then
		sound.SoundId = WaterSounds.FALLBACK
		return false
	end
	sound.SoundId = own.SoundId
	sound.PlaybackSpeed = 0.94 + math.random() * 0.12
	local takes, slot = family.takes, family.slot
	if takes and slot then
		local pick = math.random(1, takes)
		if pick == last[kind] then
			pick = pick % takes + 1
		end
		last[kind] = pick
		local from = (pick - 1) * slot
		pcall(function()
			(sound :: any).PlaybackRegionsEnabled = true;
			(sound :: any).PlaybackRegion = NumberRange.new(from, from + slot - 0.05)
		end)
		sound.TimePosition = from
	end
	return true
end

-- How long a one-shot of `kind` lasts at most (a slot), for whoever cleans it up after.
function WaterSounds.length(kind: string): number
	local family = FAMILIES[kind]
	return if family and family.slot then family.slot else 3
end

WaterSounds.STAMP = "f8d3e842"
return WaterSounds
