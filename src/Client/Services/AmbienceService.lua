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
-- THE SOUNDS are audio/gen_ambience_sfx.py's (audio/ambience/). Import them and put them in a Folder
-- named AmbienceSounds in SoundService; each is used by name. Without them, Roblox's own sounds stand
-- in, slowed, where there is one that will do, and a bed with nothing to stand in for it is left out.
--
-- AND THE LOBBY'S OWN (the ninety-sixth pass): audio/gen_lobby_sfx.py's seven files in a Folder named LobbySounds,
-- played on this screen while you are in the lobby (THE LOBBY'S OWN SOUND, below).

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
	-- THE BACK ROOMS OF THE BATHS (BackRoomsService): the baths' own tube-light hum, louder, and the Hold under it.
	backRooms = {
		{ name = "BathsHum", volume = 0.55 },
		{ name = "HoldDrone", volume = 0.2, fallback = BASS, speed = 0.24 },
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

-- THE LOBBY'S OWN SOUNDS (its sea and wind, which are heard everywhere at once by design, and its music) followed you
-- into the back rooms when you came down through the lobby's corridor. Down there: only the hum. Back when you leave.
-- THROUGH A SOUND GROUP of this screen's own, not their own volumes: the server keeps setting those (the wind's slow
-- swell every half second) and keeps making new ones (a breaker every so often), and either would have been heard
-- down there again. Everything everywhere-at-once in the lobby goes into the group, and so does anything new in it
-- while you are down there (the lobby itself, if it was put away for a run and comes back); the group goes quiet.
local lobbyHush: SoundGroup? = nil
local hushWatch: { RBXScriptConnection } = {}
local function lobbyGroup(): SoundGroup
	local group = lobbyHush
	if not group then
		group = Instance.new("SoundGroup")
		group.Name = "LobbyHush"
		group.Volume = 1
		group.Parent = SoundService
		lobbyHush = group
	end
	return group :: SoundGroup
end
local function intoHush(item: Instance)
	if item:IsA("Sound") and not item:FindFirstAncestorWhichIsA("BasePart") then
		item.SoundGroup = lobbyGroup()
	end
end
local function watchHub(hub: Instance)
	for _, item in ipairs(hub:GetDescendants()) do
		intoHush(item)
	end
	table.insert(hushWatch, hub.DescendantAdded:Connect(intoHush))
end
local function hushLobby(on: boolean)
	for _, connection in ipairs(hushWatch) do
		connection:Disconnect()
	end
	table.clear(hushWatch)
	local group = lobbyGroup()
	if on then
		local hub = workspace:FindFirstChild("Hub")
		if hub then
			watchHub(hub)
		end
		table.insert(hushWatch, workspace.ChildAdded:Connect(function(child: Instance)
			if child.Name == "Hub" then
				watchHub(child)
			end
		end))
		local music = SoundService:FindFirstChild("LobbyMusic")
		if music then
			intoHush(music)
		end
		TweenService:Create(group, TweenInfo.new(0.8), { Volume = 0 }):Play()
	else
		TweenService:Create(group, TweenInfo.new(1.5), { Volume = 1 }):Play()
	end
end

-- ===== THE LOBBY'S OWN SOUND =====
--
-- Every sound in the lobby was the engine's one splash (impact_water) at another pitch: the sea, the wind, the
-- breakers and the fountain alike, and in play it was "too repetitive". Its own now (audio/gen_lobby_sfx.py, in
-- SoundService.LobbySounds), played on this screen while you are in the lobby and never the same twice: two long sea
-- beds drifting louder and softer against each other, the fountain's water falling into its basin at the fountain,
-- and over them single things at random gaps, pitches, loudness and places: a wave breaking somewhere far below, a
-- plop or a plink or a spill at the fountain, a gust over the deck, now and then a bell on a buoy out to sea. Never
-- the same take twice running, nor one of the last two. The single things come as SHEETS, several takes in one
-- upload, each played from its own slot (`slot` seconds long, as gen_lobby_sfx.py's SLOTS). While the folder is not
-- imported the server's own stand-ins play instead (HubService.buildAmbience), and none of this does.
type Family = { sheet: string, slot: number, takes: number, every: { number }, volume: { number } }
local LOBBY: { [string]: Family } = {
	surf = { sheet = "Surf_x8", slot = 9, takes = 8, every = { 3.5, 8 }, volume = { 0.45, 0.7 } },
	splash = { sheet = "FountainSplash_x10", slot = 1.5, takes = 10, every = { 0.3, 1.4 }, volume = { 0.3, 0.55 } },
	gust = { sheet = "WindGust_x5", slot = 9, takes = 5, every = { 9, 22 }, volume = { 0.3, 0.5 } },
	bell = { sheet = "BuoyBell_x2", slot = 7.5, takes = 2, every = { 35, 80 }, volume = { 0.2, 0.3 } },
}
type LobbyScape = { token: number, beds: { Sound }, holder: BasePart?, recent: { [string]: { number } } }
local lobbyScape: LobbyScape = { token = 0, beds = {}, holder = nil, recent = {} }

local function lobbyFolder(): Instance?
	return SoundService:FindFirstChild("LobbySounds")
end

-- One take of a family: its sheet, set to play one slot only, never one of the last two taken.
local function lobbyTake(name: string, family: Family): Sound?
	local folder = lobbyFolder()
	local sheet = folder and folder:FindFirstChild(family.sheet)
	if not (sheet and sheet:IsA("Sound")) then
		return nil
	end
	local recent = lobbyScape.recent[name] or {}
	lobbyScape.recent[name] = recent
	local pick = math.random(1, family.takes)
	for _ = 1, 8 do
		if not table.find(recent, pick) then
			break
		end
		pick = math.random(1, family.takes)
	end
	table.insert(recent, pick)
	while #recent > math.min(2, family.takes - 1) do
		table.remove(recent, 1)
	end
	local take = sheet:Clone()
	local from = (pick - 1) * family.slot
	pcall(function()
		(take :: any).PlaybackRegionsEnabled = true;
		(take :: any).PlaybackRegion = NumberRange.new(from, from + family.slot - 0.05)
	end)
	take.TimePosition = from
	take.Looped = false
	return take
end

-- A sound at a place in the world, on this screen alone: on an attachment in one invisible holder, gone after `lasts`
-- seconds (a slot's length at its pitch: so a take is never heard running on into the next, region or not).
local function lobbyAt(sound: Sound, at: Vector3?, volume: number, pitch: number, near: number, far: number, lasts: number)
	sound.Volume = volume
	sound.PlaybackSpeed = pitch
	if at then
		local holder = lobbyScape.holder
		if not (holder and holder.Parent) then
			local made = Instance.new("Part")
			made.Name = "LobbySoundscape"
			made.Anchored = true
			made.CanCollide = false
			made.CanQuery = false
			made.CanTouch = false
			made.Transparency = 1
			made.Size = Vector3.new(0.2, 0.2, 0.2)
			made.Parent = workspace
			lobbyScape.holder = made
			holder = made
		end
		local spot = Instance.new("Attachment")
		spot.WorldPosition = at
		spot.Parent = holder
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.RollOffMinDistance = near
		sound.RollOffMaxDistance = far
		sound.Parent = spot
		sound:Play()
		game:GetService("Debris"):AddItem(spot, lasts)
	else
		sound.Parent = SoundService
		sound:Play()
		game:GetService("Debris"):AddItem(sound, lasts)
	end
end

local function lobbyRange(range: { number }): number
	return range[1] + math.random() * (range[2] - range[1])
end

-- The fountain (the middle of the room), if the lobby is there.
local function lobbyFountain(): Vector3?
	local hub = workspace:FindFirstChild("Hub")
	local jet = hub and hub:FindFirstChild("FountainJet", true)
	return if jet and jet:IsA("BasePart") then jet.Position else nil
end

local function lobbyOn(on: boolean)
	lobbyScape.token += 1
	local token = lobbyScape.token
	for _, s in ipairs(lobbyScape.beds) do
		if s.Parent then
			TweenService:Create(s, TweenInfo.new(1.5, Enum.EasingStyle.Sine), { Volume = 0 }):Play()
			game:GetService("Debris"):AddItem(s, 1.6)
		end
	end
	table.clear(lobbyScape.beds)
	-- The holder of the sounds at places goes once they have faded (the next lot get a new one).
	local holder = lobbyScape.holder
	if holder then
		game:GetService("Debris"):AddItem(holder, 1.6)
		lobbyScape.holder = nil
	end
	local folder = lobbyFolder()
	if not on or not folder then
		return
	end
	-- THE SEA BEDS, the two of them drifting louder and softer against each other, every twenty seconds or so.
	for k, start in ipairs({ 0.32, 0.22 }) do
		local own = folder:FindFirstChild("SeaBed_" .. k)
		if own and own:IsA("Sound") then
			local s = own:Clone()
			s.Looped = true
			s.Volume = 0
			s.TimePosition = math.random() * 20
			s.Parent = SoundService
			s:Play()
			TweenService:Create(s, TweenInfo.new(3, Enum.EasingStyle.Sine), { Volume = start }):Play()
			table.insert(lobbyScape.beds, s)
		end
	end
	task.spawn(function()
		while lobbyScape.token == token do
			task.wait(18 + math.random() * 14)
			for _, s in ipairs(lobbyScape.beds) do
				if lobbyScape.token == token and s.Parent and string.match(s.Name, "^SeaBed") then
					TweenService:Create(s, TweenInfo.new(8, Enum.EasingStyle.Sine), { Volume = 0.16 + math.random() * 0.22 }):Play()
				end
			end
		end
	end)
	-- THE FOUNTAIN'S WATER, at the fountain, and only near it (the hundred-and-first pass): full within 6 studs,
	-- fading as you walk away, gone by 55, so from the gates or the garden it is not there at all.
	local fountain = lobbyFountain()
	local bed = folder:FindFirstChild("FountainBed")
	if fountain and bed and bed:IsA("Sound") then
		local s = bed:Clone()
		s.Looped = true
		s.TimePosition = math.random() * 10
		lobbyAt(s, fountain, 0.55, 1, 6, 55, 1e6)
		table.insert(lobbyScape.beds, s)
	end
	-- AND THE THINGS THAT HAPPEN, each on its own clock.
	local function every(name: string, place: () -> (Vector3?, number, number))
		local family = LOBBY[name]
		task.spawn(function()
			task.wait(math.random() * family.every[2])
			while lobbyScape.token == token do
				local take = lobbyTake(name, family)
				if take then
					local at, near, far = place()
					local pitch = 0.93 + math.random() * 0.14
					lobbyAt(take, at, lobbyRange(family.volume), pitch, near, far, family.slot / pitch)
				end
				task.wait(lobbyRange(family.every))
			end
		end)
	end
	-- A wave breaking somewhere along the shore far below, all round the deck.
	every("surf", function()
		local centre = lobbyFountain()
		if not centre then
			return nil, 0, 0
		end
		local a = math.random() * math.pi * 2
		local r = 190 + math.random() * 90 -- beyond the promenade's edges
		return centre + Vector3.new(math.cos(a) * r, -150, math.sin(a) * r), 120, 700
	end)
	every("splash", function()
		local centre = lobbyFountain()
		if not centre then
			return nil, 0, 0
		end
		return centre + Vector3.new(math.random() * 6 - 3, -1 + math.random() * 2, math.random() * 6 - 3), 4, 45
	end)
	every("gust", function()
		return nil, 0, 0
	end)
	-- The buoy's bell out at sea, somewhere off the promenade's edge: far, and from where it is.
	every("bell", function()
		local centre = lobbyFountain()
		if not centre then
			return nil, 0, 0
		end
		local a = math.random() * math.pi * 2
		return centre + Vector3.new(math.cos(a) * 300, -150, math.sin(a) * 300), 120, 900
	end)
end

-- ===== THE PRESSES (the hundred-and-first pass) =====
--
-- Every level pad, mode and length key, pose key and the start make a sound of their own when anyone steps onto
-- them, heard from the pad itself (full within 6 studs, gone by 60), on every screen near enough: so a friend
-- choosing a level across the gates is heard from there. It was one stock switch, played from the lobby's folder
-- (everywhere at once, as loud at the garden as at the pad), and only when a vote changed; the pose keys and the
-- start had nothing. A locked pad knocks on its boards. audio/gen_press_sfx.py writes the sheets.
type Press = { sheet: string, slot: number, takes: number, volume: number }
local PRESSES: { [string]: Press } = {
	pad = { sheet = "PadPress_x4", slot = 1.4, takes = 4, volume = 0.6 },
	key = { sheet = "KeyPress_x4", slot = 0.8, takes = 4, volume = 0.55 },
	pose = { sheet = "PosePress_x4", slot = 1.2, takes = 4, volume = 0.55 },
	start = { sheet = "StartPress_x2", slot = 2.6, takes = 2, volume = 0.7 },
	locked = { sheet = "LockedPress_x2", slot = 1.0, takes = 2, volume = 0.6 },
}

local function pressKind(part: BasePart): string?
	local name = part.Name
	if string.sub(name, 1, 9) == "LevelPad_" then
		return if part:GetAttribute("Locked") then "locked" else "pad"
	elseif string.sub(name, 1, 10) == "OptionPad_" then
		return "key"
	elseif string.sub(name, 1, 8) == "PosePad_" then
		return "pose"
	elseif name == "StartPad" then
		return "start"
	end
	return nil
end

-- Who is standing on what, by player: a press is stepping ONTO a pad, so it sounds once as you arrive and again
-- only after you have stepped off.
local underFoot: { [Player]: BasePart? } = {}

local function press(kind: string, part: BasePart)
	local spec = PRESSES[kind]
	local family = { sheet = spec.sheet, slot = spec.slot, takes = spec.takes, every = { 0, 0 }, volume = { 0, 0 } }
	local take = lobbyTake("press_" .. kind, family)
	if take then
		local pitch = 0.97 + math.random() * 0.06
		lobbyAt(take, part.Position + Vector3.new(0, 1, 0), spec.volume, pitch, 6, 60, spec.slot / pitch)
	end
end

local function scanPresses()
	local hub = workspace:FindFirstChild("Hub")
	local camera = workspace.CurrentCamera
	if not (hub and camera) then
		return
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { hub }
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local standing: BasePart? = nil
		if root and root:IsA("BasePart") and (root.Position - camera.Focus.Position).Magnitude < 90 then
			local hit = workspace:Raycast(root.Position, Vector3.new(0, -6, 0), params)
			if hit and hit.Instance:IsA("BasePart") and pressKind(hit.Instance) then
				standing = hit.Instance
			end
		end
		local before = underFoot[player]
		underFoot[player] = standing
		if standing and standing ~= before then
			local kind = pressKind(standing)
			if kind then
				press(kind, standing)
			end
		end
	end
	for player in pairs(underFoot) do
		if player.Parent == nil then
			underFoot[player] = nil
		end
	end
end

local function refresh()
	local player = Players.LocalPlayer
	local now = player:GetAttribute("InLevel")
	local wanted = if typeof(now) == "string" then now else nil
	if wanted ~= level then
		-- A NEW LEVEL (or the lobby): whatever hushed the last one is over.
		level = wanted
		hushLobby(wanted == "backRooms")
		lobbyOn(wanted == nil)
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
	-- In the lobby from the start: refresh only acts on a change of place, and joining is not one.
	if level == nil then
		lobbyOn(true)
	end
	-- And again when the sounds are imported mid-session, or the lobby is put back after a run (its fountain moved).
	SoundService.ChildAdded:Connect(function(child: Instance)
		if child.Name == "LobbySounds" and level == nil then
			task.defer(lobbyOn, true)
		end
	end)
	workspace.ChildAdded:Connect(function(child: Instance)
		if child.Name == "Hub" and level == nil then
			task.defer(lobbyOn, true)
		end
	end)
	-- The presses, ten times a second, in the lobby only.
	task.spawn(function()
		while true do
			task.wait(0.1)
			if level == nil and lobbyFolder() then
				local ok, err = pcall(scanPresses)
				if not ok then
					warn("AmbienceService: the lobby's presses failed: " .. tostring(err))
					task.wait(5)
				end
			end
		end
	end)
	print("AmbienceService: running")
end

AmbienceService.STAMP = "1f86d816"
return AmbienceService
