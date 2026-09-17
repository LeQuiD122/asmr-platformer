--!strict
-- StarterPlayerScripts/Services/AudioService.lua
-- Per-material SFX pool with max polyphony (4 concurrent). Triggers within
-- the same sub-region are queued and spaced out to prevent overlapping noise.
-- Mixes per-material volume sliders + ambient music toggle.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MaterialConfigModule = require(Shared:WaitForChild("MaterialConfig"))
local Materials = MaterialConfigModule.Materials
local Constants = MaterialConfigModule.Constants

local AudioService = {}

-- Every material, so a settings UI that iterates this to build sliders gets a row for each
-- one. CreamyKeyboard was missing: `volumeByMaterial[material] or 1` meant it still played
-- at full volume, so nothing sounded broken -- it just had no slider.
local volumeByMaterial: { [string]: number } = {
	Honey = 1,
	ButterWax = 1,
	KineticSand = 1,
	Slime = 1,
	Soap = 1,
	BubbleWrap = 1,
	CreamyKeyboard = 1,
}
local ambientEnabled = true

-- The sounds currently playing for each material, oldest first. A LIST rather than a
-- count, because hitting the cap has to steal the oldest voice and a number cannot tell
-- you which one that is.
local activeSounds: { [string]: { Sound } } = {}
-- WHEN EACH MATERIAL LAST MADE A NOISE. This is the gate that actually matters, and its
-- absence is why a sand platform could sound like nothing at all.
--
-- Sounds are triggered per SUB-REGION, and sub-regions are 2.5 studs. A character is about
-- two studs wide with two feet and a moving torso, so a single stride enters two to four
-- cells within the same frame -- and the old throttle was keyed by REGION, so four
-- different regions each passed it cleanly and fired four sounds at once.
--
-- Four copies of one file starting on the same frame do not sound four times louder. They
-- sum to a single transient at four times the amplitude, which clips, and any sub-frame
-- offset between them comb-filters the result into something thin and hollow. That is why
-- "more sounds" produced less sound.
--
-- Gating per material collapses that cluster into one deliberate sound. The interval is
-- per material because they want genuinely different things: bubble wrap should crackle
-- with overlapping pops, honey should not chatter.
local lastMaterialAt: { [string]: number } = {}

-- Spaces out repeated triggers on the same region. Kept as a second, narrower gate: it
-- stops one cell retriggering on re-contact, which the material gate would allow whenever
-- the material had been quiet.
--
-- WEAK KEYS, because sub-regions are destroyed constantly -- soap dissolves, bubble wrap
-- collapses, a hardcore restart repairs a whole level. A strong table here pins every part
-- this service has ever made a noise on for the lifetime of the session.
local lastTriggerTime: { [BasePart]: number } = setmetatable({}, { __mode = "k" }) :: any

-- A LIST PER EVENT, not one id.
--
-- One id meant every footfall on a material replayed the identical file, and identical
-- repetition is what makes a good sound become an irritating one -- the ear stops hearing
-- "honey" and starts hearing "that sample again". Several takes of the same action fixes it
-- for the price of uploading them, which is the cheapest quality win available here.
--
-- Fill each list with your own uploaded asset IDs:
--   honeySquish = { "rbxassetid://123", "rbxassetid://124", "rbxassetid://125" },
--
-- An empty list, or an event absent from this table, is skipped silently. A partly filled
-- list is fine: the empties are dropped at load and the material varies across whatever is
-- actually there.
--
-- Do NOT use "rbxassetid://0" as a placeholder. It is a real request for a nonexistent
-- asset, so Roblox retries it and logs "Failed to load sound" on every single trigger.
local SOUND_IDS_BY_EVENT: { [string]: { string } } = {
	-- TWO DISTINCT TAKES NOW, which matters more here than anywhere else: honey halves
	-- your speed, so you are on it longer than on anything else and you hear it more
	-- often than anything else. A single take repeating under a slow crossing is the
	-- case where one sound stops reading as the material and starts reading as a loop.
	--
	-- These were the same id until now, and the loader was dropping the duplicate and
	-- warning about it.
	honeySquish = {
		"rbxassetid://87506169781305",
		"rbxassetid://95170946442632",
	},
	butterWaxCrack = {
		"rbxassetid://123614467603004",
	},
	kineticSandImprint = {
		"rbxassetid://131098267683015",
		"rbxassetid://71179877926997",
		"rbxassetid://105224579763037",
		"rbxassetid://115380362938824",
		"rbxassetid://114903170246023",
		"rbxassetid://111721764708471",
	},
	slimeBoing = {
		"rbxassetid://103838779923701",
	},
	soapCrumble = {
		"rbxassetid://135061782882830",
	},
	bubblePop = {
		"rbxassetid://132175495859275",
		"rbxassetid://80684165559661",
		"rbxassetid://115724525200013",
	},
	-- This table is keyed by MaterialConfig's `sfxEvent`, and a material whose event has no
	-- key here is not "silent until you upload a sound" -- the lookup misses entirely and
	-- the material can never make a noise however many ids are filled in. Adding the creamy
	-- keyboard without adding its row left exactly that hole.
	-- Empty until recorded. See SOUND_BRIEF.md for what each wants: ice is a bright
	-- brittle crack with a hollow ring under it (butter-wax's crack without the soft
	-- give), jello is a low wet wobble with a faint carbonated fizz on the tail.
	-- ...and lamb's ear is the quietest thing in the game: a dry brush, almost under the
	-- floor of what you notice, with no attack at all. If a take of it sounds like a
	-- footstep it is the wrong take.
	iceCrack = {},
	jelloWobble = {},
	leafBrush = {},
	-- The seven newest, all empty until recorded. SOUND_BRIEF.md has what each wants;
	-- the short version is that foam is almost nothing, switches are the hardest attack
	-- in the game, lego is a dry tick, charcoal is a dull snap with grit after it,
	-- chocolate is a clean crack that gets duller as it warms, clay is a wet press with
	-- no tail, and cloud is a breath.
	foamCompress = {},
	switchClack = {},
	legoClick = {},
	charcoalSnap = {},
	chocolateSnap = {},
	claySquish = {},
	cloudHush = {},
	-- The five newest. SOUND_BRIEF.md carries each in full; briefly, salt is a dry crunch
	-- that dulls as the cell packs, lava is a low hiss with a glassy tick as crust forms,
	-- oobleck is a thick squelch with no splash at all, the buttons are the sharpest click
	-- in the game after the switches, and snow is a soft compressing squeak.
	saltCrunch = {},
	lavaCrust = {},
	ooblSquelch = {},
	-- THE KEYPAD SET, synthesised by audio/gen_button_sfx.py into audio/buttons/. Upload each
	-- button_<kind>_N.wav and paste its id into the matching list: clicky -> buttonClick, then
	-- linear, tactile, release, combo and circuit. Until a list has an id, the keypad falls back to
	-- buttonClick, then to the keyboard's thock.
	buttonClick = {},
	buttonLinear = {},
	buttonTactile = {},
	buttonRelease = {},
	buttonCombo = {},
	buttonCircuit = {},
	snowPack = {},
	keyThock = {
		"rbxassetid://119301623227187",
		"rbxassetid://109818821124474",
		"rbxassetid://116558339662139",
		"rbxassetid://74249540133028",
	},
}

-- The filled-in ids, resolved ONCE at load rather than on every trigger.
--
-- A half-filled list is the normal state while sounds are still being recorded, and the
-- alternative -- picking from the raw list and bailing when the draw lands on an empty
-- string -- would make a material drop a random fraction of its footsteps. That reads as an
-- audio bug rather than as unfinished work, and it would be blamed on the polyphony cap.
local usableIds: { [string]: { string } } = {}
for event, ids in pairs(SOUND_IDS_BY_EVENT) do
	local filled = {}
	local seen: { [string]: boolean } = {}
	local duplicated = false
	for _, id in ipairs(ids) do
		if id ~= "" then
			-- DUPLICATES ARE DROPPED, and the warning matters more than the drop. Listing
			-- the same id twice looks like two takes and buys nothing: the picker would
			-- alternate between two entries that are the same file, so the material sounds
			-- exactly as repetitive as it did with one -- and silently, which is the part
			-- worth a line in the output.
			if seen[id] then
				duplicated = true
			else
				seen[id] = true
				table.insert(filled, id)
			end
		end
	end
	if duplicated then
		warn(
			("[client] Audio: '%s' lists the same sound id more than once. Duplicates are "
				.. "ignored, so it has %d distinct take(s), not %d."):format(event, #filled, #ids)
		)
	end
	usableIds[event] = filled
end

local rng = Random.new()

-- PRELOADED AT STARTUP, and this is half of why sounds arrived late.
--
-- A Sound created with a SoundId that is not cached does not play when you call Play() --
-- Roblox fetches the asset first and the sound arrives whenever that finishes, which on a
-- first hit is comfortably long enough to land after the step that caused it. Every id is
-- a separate asset, so twelve ids means twelve late first plays scattered through a run,
-- and it looks exactly like random skipping.
--
-- Fetched once here, so the first footfall on each material is as prompt as the fiftieth.
-- In a spawned thread because PreloadAsync yields, and in a pcall because a bad or
-- unpublished id should cost that one sound rather than the whole audio service.
-- Backstop for a sound that neither ends nor is destroyed -- one that was unparented, or
-- whose asset never loaded so Ended never comes. Generous, because it is a safety net and
-- not the normal path: the brief targets clips well under a second.
local SOUND_LIFETIME = 5

local ContentProvider = game:GetService("ContentProvider")

task.spawn(function()
	local probes = {}
	for _, ids in pairs(usableIds) do
		for _, id in ipairs(ids) do
			local probe = Instance.new("Sound")
			probe.SoundId = id
			table.insert(probes, probe)
		end
	end
	if #probes == 0 then
		return
	end
	local ok, err = pcall(function()
		ContentProvider:PreloadAsync(probes)
	end)
	for _, probe in ipairs(probes) do
		probe:Destroy()
	end
	if ok then
		print(("[client] Audio: %d sound ids preloaded"):format(#probes))
	else
		warn("[client] Audio: preload failed, first plays may be late: " .. tostring(err))
	end
end)
-- The index each event played last, so it can be excluded next time.
local lastPick: { [string]: number } = {}

local function pickSoundId(event: string): string?
	local ids = usableIds[event]
	if not ids or #ids == 0 then
		return nil
	end
	if #ids == 1 then
		return ids[1]
	end

	-- NEVER THE SAME TAKE TWICE RUNNING, which is not the same as picking at random.
	--
	-- A uniform draw over n takes repeats the previous one 1-in-n times, and an immediate
	-- repeat is the single case the ear reliably catches -- with three takes you would hear
	-- a doubled sample every third step, which is worse than no variation at all because it
	-- sounds like a glitch rather than like sameness. Drawing from the other n-1 and
	-- shifting past the excluded index costs nothing and removes it entirely.
	local previous = lastPick[event]
	local index
	if previous then
		index = rng:NextInteger(1, #ids - 1)
		if index >= previous then
			index += 1
		end
	else
		index = rng:NextInteger(1, #ids)
	end
	lastPick[event] = index
	return ids[index]
end

function AudioService.setVolume(material: string, volume01: number)
	volumeByMaterial[material] = math.clamp(volume01, 0, 1)
end

function AudioService.setAmbientMusic(enabled: boolean)
	ambientEnabled = enabled
	local ambient = SoundService:FindFirstChild("AmbientMusic")
	if ambient and ambient:IsA("Sound") then
		if enabled and not ambient.IsPlaying then
			ambient:Play()
		elseif not enabled and ambient.IsPlaying then
			ambient:Stop()
		end
	end
end

-- True when an event has at least one uploaded take.
function AudioService.hasTakes(event: string): boolean
	local ids = usableIds[event]
	return ids ~= nil and #ids > 0
end

-- For the few triggers that are not a plain footstep:
--   `pitch` replaces the random playback-speed jitter, because a note that wanders is a wrong note;
--   `gain` scales the volume;
--   `event` plays a different event of the same material -- a keypad's release, or its combo;
--   `force` skips the per-material gap, so a combo lands on top of the click that caused it.
export type SfxOptions = { pitch: number?, gain: number?, event: string?, force: boolean? }

function AudioService.playSfx(material: string, region: BasePart, mine: boolean?, options: SfxOptions?)
	local matDef = Materials[material]
	if not matDef then
		return
	end
	local pitch = options and options.pitch
	local gain = options and options.gain

	-- Is there anything to play at all? Checked without picking, because picking has a
	-- SIDE EFFECT and must not happen for a trigger that is about to be thrown away.
	--
	-- The event asked for, else the material's own, else its stand-in (`sfxFallback`): a material
	-- is not silent while its recordings are still to be made.
	local event = matDef.sfxEvent
	local asked = options and options.event
	if asked and AudioService.hasTakes(asked) then
		event = asked
	elseif not AudioService.hasTakes(event) and matDef.sfxFallback then
		event = matDef.sfxFallback
	end
	local ids = usableIds[event]
	if not ids or #ids == 0 then
		return -- no audio wired up for this material yet
	end

	local now = os.clock()

	-- The material gate first: one sound per footfall, not one per cell touched. A forced sound --
	-- a keypad combo landing on the click that caused it -- goes through.
	local forced = options ~= nil and options.force == true
	local materialGap = matDef.sfxMinGap or 0.08
	if not forced and now - (lastMaterialAt[material] or 0) < materialGap then
		return
	end

	-- Then the per-region gate, for a single cell retriggering on re-contact.
	if not forced and now - (lastTriggerTime[region] or 0) < 0.08 then
		return
	end

	lastMaterialAt[material] = now
	lastTriggerTime[region] = now

	-- PICKED ONLY ONCE THE SOUND IS CERTAIN TO PLAY, and the order is the whole point.
	--
	-- This used to run at the top of the function, before both gates. `pickSoundId`
	-- advances `lastPick`, so every trigger the gates discarded still moved the picker on
	-- -- and a stride touches three or four cells, so three or four picks happened per
	-- step and only one of them became a sound. The "never the same take twice running"
	-- rule was therefore true of PICKS and meaningless for what you actually heard: with
	-- two takes alternating, an odd number of discarded picks between audible ones replays
	-- the same file, and a varying number produces runs of it. That is the reported "plays
	-- the second sound many times before the first, then they take turns".
	--
	-- A side-effecting function called speculatively is the bug in one line. Moved below
	-- the gates, every advance of the picker corresponds to exactly one audible sound.
	local soundId = pickSoundId(event)
	if not soundId then
		return
	end

	local playing = activeSounds[material]
	if not playing then
		playing = {}
		activeSounds[material] = playing
	end

	-- STEAL THE OLDEST VOICE; DO NOT DROP THE NEW ONE.
	--
	-- This used to return early at the cap, so a step that arrived while four sounds were
	-- still running made no noise at all. That is the wrong trade for footsteps: the cap
	-- exists to stop the mix turning to mush, and silently dropping the sound the player
	-- just caused is a worse outcome than cutting short one they have already heard. It is
	-- also why long clips made it look broken -- an untrimmed two-second sample keeps four
	-- voices busy for two seconds, which is several steps.
	while #playing >= Constants.AUDIO_MAX_POLYPHONY do
		local oldest = table.remove(playing, 1)
		if oldest then
			oldest:Destroy() -- fires Destroying, which releases its slot
		end
	end

	-- YOUR OWN FOOTSTEPS ARE 2D. EVERYONE ELSE'S ARE POSITIONED.
	--
	-- Every sound used to be parented to the sub-region with RollOffMaxDistance 15, on the
	-- reasoning that the GDD wants close-proximity 3D audio. That is right for other
	-- players and wrong for you, and slime is where it showed: launchVelocity is 100
	-- studs/sec against a 15-stud audible radius, so you clear the radius in 0.15s and hear
	-- roughly the first third of the boing, fading the whole way. It reads exactly like a
	-- sound being cut off, and no amount of picker or gate work could have touched it.
	--
	-- You cannot walk away from your own feet, so your own material sounds are flat: no
	-- attenuation, full level, the whole clip every time. This is what games do -- your
	-- footsteps are non-diegetic, other people's are in the world. It also happens to fix
	-- the general case, since walking at 16 studs/sec put you out of range in under a
	-- second and quietly thinned every long sample.
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	-- PITCH AND GAIN JITTER, which is the cheapest trick in game audio and the one that
	-- does most for a small sample set. A footstep replayed at exactly the same pitch and
	-- level is recognisably the same FILE within about three hearings; nudged a couple of
	-- semitones either way it reads as the same surface being stepped on differently.
	--
	-- +/- 6% playback speed is roughly a semitone each way -- enough to break the sameness,
	-- little enough that it never sounds like a pitch effect. Volume moves less, because
	-- level changes read as distance and this is always underfoot.
	--
	-- It matters most where there is one take: honey, sand, butter and slime each have a
	-- single upload, so this is doing the work a second recording would.
	sound.Volume = (volumeByMaterial[material] or 1) * rng:NextNumber(0.92, 1.0) * (gain or 1)
	sound.PlaybackSpeed = if pitch then pitch * rng:NextNumber(0.995, 1.005) else rng:NextNumber(0.94, 1.06)
	if mine then
		-- Parented to SoundService, which makes it 2D and ignores rolloff entirely.
		sound.Parent = SoundService
	else
		sound.RollOffMode = Enum.RollOffMode.Inverse
		-- 15 was far too tight even for a bystander: a platform is 16 studs across, so a
		-- player at the far end of the one you are on was already inaudible. 70 keeps
		-- another player's steps audible across a chunk or two and silent across the level.
		sound.RollOffMaxDistance = 70
		sound.RollOffMinDistance = 12
		sound.Parent = region
	end

	table.insert(playing, sound)

	-- RELEASED EXACTLY ONCE, FROM WHICHEVER COMES FIRST, and this is the other half of the
	-- bug -- the half that made a material go permanently silent.
	--
	-- The slot used to be returned only by `Ended`, with a 3-second sweeper guarded on
	-- `sound.Parent`. Neither fires when the REGION is destroyed underneath the sound, and
	-- in this game regions are destroyed all the time: soap dissolves, bubble wrap
	-- collapses, a hardcore restart repairs the level. The sound went with its parent,
	-- `Ended` never came, and the sweeper's guard saw a nil Parent and skipped the
	-- decrement. Four of those and the counter sat at the cap forever -- that material
	-- never made another sound for the rest of the session, however many ids were in the
	-- table. Adding more ids could not help, because nothing was ever reaching Play().
	--
	-- `Destroying` covers the destroyed-region case and propagates from an ancestor, the
	-- timeout covers a sound that is unparented rather than destroyed, and the flag makes
	-- all three paths idempotent.
	local released = false
	local function release()
		if released then
			return
		end
		released = true
		local index = table.find(playing, sound)
		if index then
			table.remove(playing, index)
		end
	end

	sound.Ended:Once(release)
	sound.Destroying:Once(release)
	sound:Play()

	task.delay(SOUND_LIFETIME, function()
		release()
		if sound.Parent then
			sound:Destroy()
		end
	end)
end

return AudioService
