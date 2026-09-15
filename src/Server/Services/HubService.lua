--!strict
-- ServerScriptService/Services/HubService.lua
-- The lobby: the room, its pads, the current selection, and the run lifecycle.
--
-- Owns everything about CHOOSING. It knows nothing about how a level is built beyond calling
-- a function Bootstrap hands it, and nothing about how a chunk is built at all.
--
-- === Why the room is pads and not a menu ===
--
-- Every other choice in this game is made by standing on something, and each level pad is
-- made of that level's headline material using MaterialAppearance.apply -- the same call
-- every chunk surface goes through. So you feel what a level is made of before you commit to
-- it, which no menu can do, and the room costs no new UI system.

-- ===== HOISTED, and this is a bug class rather than a style preference =====
--
-- Both of these were declared `local` a THOUSAND LINES BELOW the code that reads them. Luau
-- resolves a name at the point it is written, so a read above the declaration does not see
-- the local at all -- it compiles to a GLOBAL, which is nil, and nothing warns about it.
--
-- What that cost, concretely:
--
--   inRun         hubPlayers() indexed it to decide who is in the lobby. Indexing nil throws,
--                 so the one function that decides who sees the vote banner errored every
--                 time it was called.
--   modeNotifier  the mode readout in the corner is fired through it. The guard read
--                 `if ... and modeNotifier then`, which was ALWAYS false, so standing on the
--                 Hardcore pad updated the pad, the halo and the banner and left the corner
--                 saying Chill. That is the "why is it such a big issue" bug, and the answer
--                 is that the code was never running, not that it was wrong.
--
-- Declared here, assigned where they were before. check_lua now fails on this pattern.
local inRun: { [Player]: boolean } = {}
local modeNotifier: ((Player, string) -> ())? = nil

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local LevelDefinitions = require(Shared:WaitForChild("LevelDefinitions"))
local MaterialAppearance = require(Shared:WaitForChild("MaterialAppearance"))
local ChunkDefinitions = require(Shared:WaitForChild("ChunkDefinitions"))

local HubService = {}

-- One message per distinct problem. The hub builds four pads in a loop, so an unguarded warn
-- would print the same line four times and bury anything else in the log.
local warned: { [string]: boolean } = {}

local function warnOnce(key: string, message: string)
	if warned[key] then
		return
	end
	warned[key] = true
	warn(message)
end

-- WHAT A RUN IS, as plain data.
--
-- No Instances, no functions, no references to anything in the world. That is not tidiness:
-- sub-project C hands this exact table to TeleportService:TeleportToPrivateServer, teleport
-- data is serialised, and an Instance in here could not cross. check_hub.py enforces it,
-- because the constraint is invisible until the day it is expensive.
export type RunRequest = {
	levelId: number,
	mode: string,
	length: string,
}

-- WHAT AN UNSET LOBBY OFFERS. Chill because that is what PlayerStateService defaults a new
-- player to, and medium because it is the level at its authored length.
local request: RunRequest = {
	levelId = 1,
	mode = "chill",
	length = "medium",
}

-- SERVER-WIDE, not per player. One level exists per server, so one selection does too: the
-- last pad pressed wins and the start pad launches it for everyone in the room. That is a
-- real limitation and it goes away with sub-project C, not before.
--
-- Returned as a COPY so a caller cannot write to the selection by accident. The setters
-- below are the only way in.
function HubService.getRequest(): RunRequest
	return {
		levelId = request.levelId,
		mode = request.mode,
		length = request.length,
	}
end

function HubService.setLevel(levelId: number)
	request.levelId = levelId
end

function HubService.setMode(mode: string)
	request.mode = mode
end

function HubService.setLength(length: string)
	request.length = length
end

-- Every level the hub builds a pad for: the shippable set, plus the sandbox.
--
-- The sandbox is not in LevelDefinitions.All and is deliberately added here rather than put
-- into it. `All` is the list a real game mode draws from; the sandbox is a development route
-- and the only way to walk every material in one run, so the difference should stay visible
-- in the data rather than only on a sign.
function HubService.padLevels()
	local levels = {}
	for _, level in ipairs(LevelDefinitions.All) do
		table.insert(levels, level)
	end
	table.insert(levels, LevelDefinitions.Sandbox)
	return levels
end

function HubService.levelById(levelId: number)
	for _, level in ipairs(HubService.padLevels()) do
		if level.levelId == levelId then
			return level
		end
	end
	return nil
end

-- HOW LONG THE RUN IS, as a multiplier on the level's own authored chunk count.
--
-- Scaling rather than replacing, because a level's identity is its material mix and that
-- does not change with how far you walk it. Level3 is 50 chunks; short is 25 of the same
-- level rather than a different, shorter one.
function HubService.lengthScale(length: string): number
	if length == "short" then
		return 0.5
	elseif length == "long" then
		return 1.5
	end
	return 1.0
end

-- ===== the room =====

-- WHERE THE ROOM IS, and it is a long way from the spiral on purpose.
--
-- LevelService centres a run on its origin with SPIRAL_RADIUS 90, so a run occupies roughly
-- a 200-stud circle. 600 studs clear of it and 200 up leaves the hub well outside that
-- circle, with room for the backdrop, which centres itself on the level and would otherwise
-- enclose both.
local HUB_ORIGIN = Vector3.new(0, 200, -600)

-- WHERE A RUN IS BUILT: the world origin, which is where LevelService has always put it. So
-- this module changes nothing about where a level appears. The separation from the room
-- comes from HUB_ORIGIN, not from moving the level.
-- A FRESH PATCH OF GROUND PER RUN, rather than always the same one.
--
-- Every level was built at the world origin, so run two was assembled exactly on top of run
-- one -- and if anything at all survived the teardown, the new spawn point put you inside it.
-- That is "I picked a different map and it teleported me into the old one".
--
-- Clearing properly is the other half and it is already meant to happen; this makes the
-- failure harmless instead of confusing. Two runs cannot occupy the same space if they are
-- never given the same space, and a stale level left behind is then simply somewhere else,
-- visible as a bug rather than experienced as one.
--
-- 4000 studs apart and marching in a straight line. Far enough that neither level's backdrop
-- or kill plane reaches the other, and cheap: a spiral is a few hundred studs across, so the
-- hundredth run is 400,000 studs out, which is well inside Roblox's usable range.
local LEVEL_ORIGIN = Vector3.zero
local RUN_SPACING = 4000
local runsStarted = 0

local function nextLevelOrigin(): Vector3
	runsStarted += 1
	return LEVEL_ORIGIN + Vector3.new(runsStarted * RUN_SPACING, 0, 0)
end

local FLOOR_SIZE = Vector3.new(110, 2, 96)
local PAD_SIZE = Vector3.new(10, 1.4, 10)
-- WIDE ENOUGH TO READ, NARROW ENOUGH TO FIT, and now derived rather than fixed.
--
-- 24 was chosen when there were three level pads and it was right for three. A fourth level
-- makes five pads counting Sandbox, and five at 24 apart span 96 against a deck inlay 100
-- wide -- so the outermost two hung over the edge, which check_hub caught the moment Level4
-- was added.
--
-- Picking a bigger number by hand would just move the failure to the sixth level. This asks
-- how much room there actually is and divides it, so the row fits whatever the count becomes
-- and never has to be revisited again. Capped at 24 so a short row does not sprawl.
local PAD_SPACING = 24
local SIGN_HEIGHT = 7

-- Built once and never destroyed. Everything else in the world comes and goes around it.
local hubFolder: Folder? = nil

-- FIXED TEXT SIZE, NOT TextScaled, and this is the whole reason the first version was
-- unreadable.
--
-- A BillboardGui sized in OFFSET pixels keeps that pixel size at every distance, so a 340px
-- label with TextScaled fills 340 pixels of screen whether you are next to it or across the
-- room. Four of them at once covered the entire view and overlapped each other.
--
-- Sized in STUDS instead (the fourth and second arguments), so the sign scales with distance
-- like the thing it is labelling, and the text is pinned at a size that is legible without
-- being a headline.
-- `lift` is how far ABOVE the thing the sign floats, and it has to be passed rather than
-- fixed. A sign is occluded by whatever it labels, so one height cannot serve a flat option
-- key, a plinth with a window on it, and a statue with a person standing on top.
-- ROUNDED AND ON A PLATE, rather than stroked text floating in mid-air.
--
-- The first version was bold Gotham with a text stroke and nothing behind it, which is the
-- look you get by default and reads as debug output: the stroke fights the letterforms, and
-- over a busy floor there is no ground for the text to sit on.
--
-- Nunito because it is the one rounded family in Roblox's default set, and this is a game
-- about soft materials. A plate behind it does the legibility work the stroke was failing at.
local SIGN_TITLE = Font.new("rbxasset://fonts/families/Nunito.json", Enum.FontWeight.Bold)
local SIGN_DETAIL = Font.new("rbxasset://fonts/families/Nunito.json", Enum.FontWeight.Medium)

-- Called by setHighlight, so a chosen pad says so in words as well as in light.
local function setSignSelected(parent: BasePart, on: boolean)
	local gui = parent:FindFirstChild("Sign")
	local plate = gui and gui:FindFirstChild("Plate")
	if not (plate and plate:IsA("Frame")) then
		return
	end
	plate.BackgroundColor3 = if on then Color3.fromRGB(250, 238, 198) else Color3.fromRGB(24, 22, 32)
	plate.BackgroundTransparency = if on then 0.08 else 0.32
	local title = plate:FindFirstChild("Title")
	if title and title:IsA("TextLabel") then
		title.TextColor3 = if on then Color3.fromRGB(38, 32, 26) else Color3.fromRGB(245, 245, 250)
	end
	local detail = plate:FindFirstChild("Detail")
	if detail and detail:IsA("TextLabel") then
		detail.TextColor3 = if on then Color3.fromRGB(104, 88, 62) else Color3.fromRGB(184, 190, 208)
		detail.Text = if on then "selected" else (detail:GetAttribute("Subtitle") or "")
	end
	local edge = plate:FindFirstChild("Edge")
	if edge and edge:IsA("UIStroke") then
		edge.Color = if on then Color3.fromRGB(255, 224, 150) else Color3.fromRGB(120, 116, 142)
		edge.Transparency = if on then 0 else 0.45
	end
end

-- `width` lets a crowded row ask for a smaller plate. The pose keys sit 6 studs apart, so a
-- 9-stud sign on each one overlapped its neighbours on both sides and the row turned into a
-- wall of text.
local function makeSign(parent: BasePart, title: string, subtitle: string, lift: number?,
	width: number?)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Sign"
	gui.Size = UDim2.new(width or 9, 0, (width or 9) * 0.29, 0)
	-- ALWAYS ON TOP, and this is the fix for text disappearing behind the pads.
	--
	-- A BillboardGui is depth-tested by default, so a label sitting a few studs over a raised
	-- cylinder is hidden by the cylinder next to it the moment you stand at head height. The
	-- earlier version of this looked fine from above and unreadable from where you play.
	--
	-- It is safe here only because MaxDistance is short: drawing through walls matters when
	-- there are walls between you and the label, and at 60 studs there are not.
	gui.AlwaysOnTop = true
	gui.StudsOffsetWorldSpace = Vector3.new(0, lift or SIGN_HEIGHT, 0)
	-- Fades out well before the far side of the room, so standing at one end does not stack
	-- every sign in the lobby on top of each other.
	gui.MaxDistance = 60
	-- ADORNEE SET EXPLICITLY. A BillboardGui without one falls back to its parent, which is
	-- the same part here -- but "falls back to" and "is told" are not the same thing when the
	-- parent is a rotated cylinder, and the pose labels were reported sitting one pad to the
	-- side of the key they name. Saying it outright costs a line and removes the question.
	-- HUNG ON ITS OWN ANCHOR, dead centre of the pad.
	--
	-- The labels have been reported sitting to the left of their key three times, and reading
	-- the code has not explained it: the sign is parented to the key, the key's position is
	-- correct, and a BillboardGui centres on its adornee. Rather than guess a fourth time, this
	-- removes every variable at once -- an invisible cube at exactly the pad's centre, with the
	-- billboard adorned to that. A cube has no rotation to misread and no size to be offset by.
	--
	-- If the label still lands beside its pad after this, the pads are what is displaced, not
	-- the labels, and that is worth knowing.
	local anchorPart = Instance.new("Part")
	anchorPart.Name = "SignAnchor"
	anchorPart.Anchored = true
	anchorPart.CanCollide = false
	anchorPart.CanTouch = false
	anchorPart.CanQuery = false
	anchorPart.Transparency = 1
	anchorPart.Size = Vector3.new(0.2, 0.2, 0.2)
	anchorPart.CFrame = CFrame.new(parent.Position)
	anchorPart.Parent = parent

	gui.Adornee = anchorPart
	gui.SizeOffset = Vector2.new(0, 0)
	gui.Parent = anchorPart

	-- The plate is inset rather than filling the billboard, so the rounded corners have room
	-- to be corners instead of touching the edge of the drawn area.
	local plate = Instance.new("Frame")
	plate.Name = "Plate"
	plate.AnchorPoint = Vector2.new(0.5, 0.5)
	plate.Position = UDim2.new(0.5, 0, 0.5, 0)
	plate.Size = UDim2.new(0.72, 0, 0.86, 0)
	plate.BackgroundColor3 = Color3.fromRGB(24, 22, 32)
	plate.BackgroundTransparency = 0.32
	plate.BorderSizePixel = 0
	plate.Parent = gui

	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.34, 0)
	round.Parent = plate

	local edge = Instance.new("UIStroke")
	edge.Name = "Edge"
	edge.Thickness = 2
	edge.Color = Color3.fromRGB(120, 116, 142)
	edge.Transparency = 0.45
	edge.Parent = plate

	local name = Instance.new("TextLabel")
	name.Name = "Title"
	name.Size = UDim2.new(1, -10, 0.56, 0)
	name.Position = UDim2.new(0, 5, 0.04, 0)
	name.BackgroundTransparency = 1
	name.FontFace = SIGN_TITLE
	name.TextScaled = true
	name.TextColor3 = Color3.fromRGB(245, 245, 250)
	name.Text = title
	name.Parent = name.Parent or plate

	-- TextScaled with a ceiling. Unbounded, a short word like "Wave" would be drawn twice the
	-- height of "Hardcore" on the pad beside it and the row would look ransom-noted.
	local cap = Instance.new("UITextSizeConstraint")
	cap.MaxTextSize = 26
	cap.Parent = name

	local detail = Instance.new("TextLabel")
	detail.Name = "Detail"
	detail.Size = UDim2.new(1, -10, 0.34, 0)
	detail.Position = UDim2.new(0, 5, 0.6, 0)
	detail.BackgroundTransparency = 1
	detail.FontFace = SIGN_DETAIL
	detail.TextScaled = true
	detail.TextColor3 = Color3.fromRGB(184, 190, 208)
	detail.Text = subtitle
	detail:SetAttribute("Subtitle", subtitle)
	detail.Parent = plate

	local detailCap = Instance.new("UITextSizeConstraint")
	detailCap.MaxTextSize = 16
	detailCap.Parent = detail
end

-- Shared by every kind of pad: a box around whichever one is currently chosen.
--
-- A SelectionBox rather than a colour change, because the level pads ARE their materials and
-- recolouring one would mean the chosen level is made of something else.
-- A HALO, NOT A BOX.
--
-- SelectionBox draws the part's axis-aligned bounding box, so a round key got a square cage
-- around it and a plinth got a wire crate. The outline has to follow the shape it is marking
-- or it reads as a debug overlay, which is what it looked like.
--
-- So the highlight is geometry: a flat neon disc under a round pad, a flat neon slab under a
-- rectangular one. It sits just below the surface and lights up, which also reads better at
-- standing height than any outline does.
local function setHighlight(pad: BasePart, on: boolean)
	local halo = pad:FindFirstChild("Halo")
	if not halo then
		local made = Instance.new("Part")
		made.Name = "Halo"
		made.Anchored = true
		made.CanCollide = false
		made.CanTouch = false
		made.CanQuery = false
		made.Material = Enum.Material.Neon
		made.Color = Color3.fromRGB(255, 236, 168)
		if pad.Shape == Enum.PartType.Cylinder then
			-- CONCENTRIC, not stacked underneath.
			--
			-- This used to offset the halo along the pad's own X by half its thickness. For a
			-- cylinder lying flat that axis points DOWN, so the ring was placed at y = 0.85
			-- under a pad at y = 1.7 -- and the deck's top face is at y = 1.0. Every selection
			-- ring in this room has been buried inside the floor since it was written, which
			-- is why stepping on a pad looked like it did nothing at all.
			--
			-- Sharing the pad's centre and orientation and simply being wider puts the ring
			-- around the key's rim, where it is visible from standing height.
			made.Shape = Enum.PartType.Cylinder
			made.Size = Vector3.new(pad.Size.X * 0.86, pad.Size.Y + 2.4, pad.Size.Z + 2.4)
			made.CFrame = pad.CFrame
		else
			made.Size = Vector3.new(pad.Size.X + 2.2, pad.Size.Y * 0.86, pad.Size.Z + 2.2)
			made.CFrame = pad.CFrame
		end
		made.Parent = pad

		-- Light as well as colour. The ring is the state; the glow is what makes you notice
		-- the state changed while you were looking somewhere else.
		-- BRIGHTNESS PULLED WAY BACK across every fixture in this room.
		--
		-- The first pass set a halo to 6 and a surface beam to 5 on top of eight column lamps
		-- and four lanterns, and the result was a white room: the pool blew out, the marble
		-- lost its veining and the signs stopped reading. Roblox lights are additive, so the
		-- number that looks right on one fixture alone is far too high once there are twenty.
		--
		-- These are set so that a lit pad is clearly the brightest thing near it and nothing
		-- else in shot is clipping.
		local glow = Instance.new("PointLight")
		glow.Name = "HaloGlow"
		glow.Color = made.Color
		glow.Range = 18
		glow.Shadows = false
		glow.Parent = made

		-- A SurfaceLight as well, aimed up. The PointLight makes the ring glow; this is what
		-- throws a shaft of light off the pad, which is the part of the level pads' doorway
		-- effect that actually reads from across the room.
		local beam = Instance.new("SurfaceLight")
		beam.Name = "HaloBeam"
		beam.Face = Enum.NormalId.Left
		beam.Color = made.Color
		beam.Range = 14
		beam.Brightness = 1.2
		beam.Angle = 120
		beam.Shadows = false
		beam.Enabled = false
		beam.Parent = made
		halo = made
	end
	-- RED WHEN THE ROOM IS ON HARDCORE. The lever, the board chip and the result banner all
	-- turn red already; the ring you are standing in was the one thing still saying nothing
	-- about which run this is about to be.
	local hot = HubService.resolveVote().mode == "hardcore"
	local shade = if hot then Color3.fromRGB(244, 96, 84) else Color3.fromRGB(255, 236, 168)
	local part = halo :: BasePart
	part.Color = shade
	part.Transparency = if on then 0.1 else 1
	local glow = part:FindFirstChild("HaloGlow")
	if glow and glow:IsA("PointLight") then
		glow.Color = shade
		glow.Enabled = on
		-- MATCHED TO THE LEVEL PADS, whose lit doorway is the brightest thing in the room and
		-- reads as chosen from anywhere in it. A selection that is only visible when you are
		-- standing on it is not telling you what is selected, it is confirming what you just
		-- did -- and those are different jobs.
		glow.Brightness = 1.6
		glow.Range = 18
	end
	local surface = part:FindFirstChild("HaloBeam")
	if surface and surface:IsA("SurfaceLight") then
		surface.Color = shade
		surface.Enabled = on
	end
	setSignSelected(pad, on)
end

-- Declared above makeLevelPad because that function's touch handler calls it, and check_lua
-- reads declaration order as text: a definition below its caller fails the
-- use-before-declaration check even though Lua resolves it fine at runtime.
function HubService.refreshPads()
	local folder = hubFolder
	if not folder then
		return
	end
	-- THE LEADING VOTE, not the resolved request.
	--
	-- getRequest only changes when a ballot RESOLVES, so between votes it holds whatever the
	-- last run used. Standing on a pad recorded your vote correctly and then lit nothing,
	-- which is indistinguishable from a pad that does not work -- and was reported as one.
	local chosen = HubService.resolveVote().levelId
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("BasePart") and child.Name:sub(1, 9) == "LevelPad_" then
			-- The same tally the option pads print. A level pad with three votes on it is the
			-- single most useful thing in this room while a ballot is open.
			local levelVotes = HubService.counts("level")[child:GetAttribute("LevelId")] or 0
			local sign = child:FindFirstChild("Sign")
			local plate = sign and sign:FindFirstChild("Plate")
			local detail = plate and plate:FindFirstChild("Detail")
			if detail and detail:IsA("TextLabel") then
				detail.Text = if levelVotes == 0
					then (detail:GetAttribute("Subtitle") or "")
					else (if levelVotes == 1 then "1 vote" else levelVotes .. " votes")
			end
			local on = child:GetAttribute("LevelId") == chosen
			setHighlight(child, on)
			-- The window lights up as well as the box. A row of dim panes with one bright
			-- one reads from across the room, where a thin outline does not.
			local window = child:FindFirstChild("ThemeWindow")
			if window and window:IsA("BasePart") then
				window.Transparency = if on then 0.05 else 0.45
			end
		end
	end
	HubService.refreshBoard()
end

function HubService.refreshOptionPads()
	local folder = hubFolder
	if not folder then
		return
	end
	local leading = HubService.resolveVote()
	for _, child in ipairs(folder:GetChildren()) do
		local field = child:GetAttribute("OptionField")
		if child:IsA("BasePart") and field then
			local value = child:GetAttribute("OptionValue")
			local counts = HubService.counts(field)
			local votes = counts[value] or 0
			-- THE PAD SHOWS ITS VOTE COUNT, which is the one thing about a ballot that is the
			-- same for everyone in the room and therefore the one thing a shared object in the
			-- world can honestly display. Your own pick lives in your own banner.
			local sign = child:FindFirstChild("Sign")
			local plate = sign and sign:FindFirstChild("Plate")
			local detail = plate and plate:FindFirstChild("Detail")
			if detail and detail:IsA("TextLabel") then
				detail.Text = if votes == 0
					then (detail:GetAttribute("Subtitle") or "")
					else (if votes == 1 then "1 vote" else votes .. " votes")
			end
			local wanted = if field == "mode" then leading.mode else leading.length
			local on = child:GetAttribute("OptionValue") == wanted
			setHighlight(child, on)
			local inlay = child:FindFirstChild("Inlay")
			if inlay and inlay:IsA("BasePart") then
				inlay.Transparency = if on then 0 else 0.72
			end
		end
	end
	HubService.refreshBoard()
end

-- WHAT A LEVEL PAD SHOWS, now that a level is a PLACE rather than a set of chunks.
--
-- These pads used to be real chunks of a "headline material" -- a honey slab for one level,
-- soap for another. That made sense while a level meant a restricted material pool, and
-- stopped making sense the moment levels became backdrops: honey has nothing to do with
-- whether the horizon is a city or empty sky, so four giant material blocks in the lobby
-- were saying something untrue about what you were picking.
--
-- What a pad shows now is the SKY you would be standing under. Only one backdrop exists, so
-- the others are honest about being empty rather than dressed up as something.
local THEME_LOOKS = {
	cityShore = {
		sky = Color3.fromRGB(196, 178, 226),
		ground = Color3.fromRGB(120, 96, 150),
		label = "city, beach and waterpark",
	},
	none = {
		sky = Color3.fromRGB(96, 100, 118),
		ground = Color3.fromRGB(58, 60, 72),
		label = "no horizon yet",
	},
}

local function themeLook(level)
	return THEME_LOOKS[level.backdrop or "none"] or THEME_LOOKS.none
end

local function makeLevelPad(level, index: number, parent: Folder): BasePart
	local look = themeLook(level)

	local pad = Instance.new("Part")
	pad.Name = "LevelPad_" .. tostring(level.levelId)
	pad.Anchored = true
	pad.CanCollide = true
	pad.CanTouch = true
	pad.Size = PAD_SIZE
	-- CENTRED ON THE ROOM, which it never was. The minus 30 was written for a row of three at
	-- 24 apart, and a row of three at 24 apart spans 48 -- so it should have been minus 24.
	-- Every level pad sat 6 studs left of where it belonged, and the whole row looked skewed
	-- against a floor whose inlay, path and start pad are all symmetric about x = 0.
	--
	-- Derived from the count instead of hard-coded, so adding a fourth level re-centres the
	-- row rather than pushing it further off.
	local count = #HubService.padLevels()
	-- The widest spacing that still leaves the outermost pad clear of the inlay, or the
	-- comfortable spacing, whichever is smaller. FLOOR_SIZE.X / 2 - 5 is the inlay edge, which
	-- is the same figure check_hub measures against.
	local room = FLOOR_SIZE.X / 2 - 5 - PAD_SIZE.X / 2
	local spacing = if count > 1
		then math.min(PAD_SPACING, room * 2 / (count - 1))
		else PAD_SPACING
	local offset = (index - 1 - (count - 1) / 2) * spacing
	pad.Position = HUB_ORIGIN + Vector3.new(offset, 1.7, -20)
	pad:SetAttribute("LevelId", level.levelId)
	-- Polished stone, deliberately neutral. The pad is the plinth; the window behind it is
	-- what carries the theme.
	pad.Material = Enum.Material.Slate
	pad.Color = look.ground
	pad.Parent = parent

	-- THE WINDOW: a tall pane standing behind the plinth, tinted with the theme's sky and lit
	-- from inside, so a row of pads reads as a row of places rather than a row of platforms.
	local window = Instance.new("Part")
	window.Name = "ThemeWindow"
	window.Anchored = true
	window.CanCollide = false
	window.CanTouch = false
	window.CanQuery = false
	window.Size = Vector3.new(PAD_SIZE.X * 0.92, 11, 0.6)
	window.Position = pad.Position + Vector3.new(0, 6.2, -PAD_SIZE.Z / 2)
	window.Material = Enum.Material.Neon
	window.Color = look.sky
	window.Transparency = 0.25
	window.Parent = pad

	local frame = Instance.new("Part")
	frame.Name = "ThemeFrame"
	frame.Anchored = true
	frame.CanCollide = false
	frame.CanTouch = false
	frame.CanQuery = false
	frame.Size = window.Size + Vector3.new(0.9, 0.9, -0.2)
	frame.Position = window.Position
	frame.Material = Enum.Material.Metal
	frame.Color = Color3.fromRGB(38, 36, 46)
	frame.Parent = pad

	local par = level.parTime or 0
	makeSign(pad, level.name,
		("par %d:%02d  |  %s"):format(math.floor(par / 60), par % 60, look.label), 14)

	-- SELECTION IS A TOUCH, not a prompt. Touched fires many times per second while a player
	-- stands still, so the guard is on the VALUE rather than on a debounce timer: setting the
	-- same level twice is free, and the highlight only moves when the selection changes.
	pad.Touched:Connect(function(hit: BasePart)
		local character = hit.Parent
		if not (character and character:FindFirstChildWhichIsA("Humanoid")) then
			return
		end
		local player = Players:GetPlayerFromCharacter(character)
		if not player then
			return
		end
		if HubService.ballotOf(player).levelId == level.levelId then
			return
		end
		HubService.vote(player, "level", level.levelId)
	end)

	return pad
end

-- The two option rows. Each is a set where exactly one is chosen, which is the same shape as
-- the level row, so they share setHighlight and refreshOptionPads.
local OPTION_ROWS = {
	{
		field = "mode",
		values = { "chill", "hardcore" },
		labels = { chill = "Chill", hardcore = "Hardcore" },
		colour = Color3.fromRGB(96, 142, 210),
		-- The three rows used to sit at z = -22, 2 and 14, which crowded the choices into the
		-- middle of the room and left the ends empty. Spread to -20, -4 and 8: twelve studs
		-- between rows is enough to read them as three separate decisions.
		z = -4,
	},
	{
		field = "length",
		values = { "short", "medium", "long" },
		labels = { short = "Short", medium = "Medium", long = "Long" },
		colour = Color3.fromRGB(120, 108, 150),
		z = 8,
	},
}

local function makeOptionPads(row, parent: Folder)
	for index, value in ipairs(row.values) do
		-- A ROUND KEY IN A HOUSING, rather than a flat square.
		--
		-- Three pieces doing three jobs: a dark ring that reads as a socket the key sits in,
		-- a cylinder you actually stand on, and a neon inlay that lights when it is chosen.
		-- The inlay is what does the work -- an outline around a flat slab is invisible from
		-- standing height, and a lit disc is not.
		local housing = Instance.new("Part")
		housing.Name = "OptionHousing_" .. row.field .. "_" .. value
		housing.Anchored = true
		housing.CanCollide = true
		housing.Shape = Enum.PartType.Cylinder
		-- SMALLER. At 9.4 across with a 12-stud pitch these read as three dinner plates laid
		-- end to end, and with a sign over each one the whole row was a wall. Seven and a half
		-- leaves real floor between them and the labels stop overlapping.
		housing.Size = Vector3.new(0.9, 7.6, 7.6)
		housing.CFrame = CFrame.new(HUB_ORIGIN + Vector3.new((index - 1) * 12 - 12, 1.35, row.z))
			* CFrame.Angles(0, 0, math.rad(90))
		housing.Material = Enum.Material.Metal
		housing.Color = Color3.fromRGB(38, 36, 46)
		housing.Parent = parent

		local pad = Instance.new("Part")
		pad.Name = "OptionPad_" .. row.field .. "_" .. value
		pad.Anchored = true
		pad.CanCollide = true
		pad.CanTouch = true
		pad.Shape = Enum.PartType.Cylinder
		pad.Size = Vector3.new(1.5, 6.4, 6.4)
		pad.CFrame = CFrame.new(HUB_ORIGIN + Vector3.new((index - 1) * 12 - 12, 1.7, row.z))
			* CFrame.Angles(0, 0, math.rad(90))
		pad.Material = Enum.Material.SmoothPlastic
		pad.Color = row.colour
		pad:SetAttribute("OptionField", row.field)
		pad:SetAttribute("OptionValue", value)
		pad.Parent = parent

		local inlay = Instance.new("Part")
		inlay.Name = "Inlay"
		inlay.Anchored = true
		inlay.CanCollide = false
		inlay.CanTouch = false
		inlay.CanQuery = false
		inlay.Shape = Enum.PartType.Cylinder
		inlay.Size = Vector3.new(0.35, 4.3, 4.3)
		inlay.CFrame = CFrame.new(pad.Position + Vector3.new(0, 0.7, 0))
			* CFrame.Angles(0, 0, math.rad(90))
		inlay.Material = Enum.Material.Neon
		inlay.Color = row.colour
		inlay.Transparency = 0.6
		inlay.Parent = pad

		-- LOW, so the label reads as belonging to the pad under it.
		--
		-- At six studs up a sign is directly overhead in world space and nowhere near the pad
		-- ON SCREEN: from a player's eye height the projection throws it off to one side, which
		-- is exactly how it was reported. Three studs keeps it over its own key from any angle
		-- you actually stand at.
		-- STACKED, NOT SHARING A HEIGHT. The label and the YOUR PICK chip are both centred over
		-- the pad, so the only thing keeping them apart is the gap between their lifts -- and
		-- at 3.0 against 1.5 the two plates overlapped and read as one jumbled block.
		--
		-- Sign high, chip low, three studs between them: a column of two labels over the key
		-- they belong to, which is what "on top of the button" means once there are two.
		-- SIX STUDS APART, not three. Both plates are centred over the pad, so vertical
		-- separation is the only thing keeping them apart -- and at 4.4 against 1.3 they still
		-- crossed on screen from a standing camera, because perspective compresses vertical
		-- gaps far more than it compresses the plates themselves.
		makeSign(pad, row.labels[value], row.field, 5.4, 6.4)

		pad.Touched:Connect(function(hit: BasePart)
			local character = hit.Parent
			if not (character and character:FindFirstChildWhichIsA("Humanoid")) then
				return
			end
			local player = Players:GetPlayerFromCharacter(character)
			if not player then
				return
			end
			-- YOUR vote, not the room's setting. The pad used to write straight into the
			-- shared request, which is why the last person to step on one decided for
			-- everybody.
			local ballot = HubService.ballotOf(player)
			local already = if row.field == "mode" then ballot.mode else ballot.length
			if already == value then
				return
			end
			HubService.vote(player, row.field, value)
		end)
	end
end

-- ===== sound =====
--
-- Everything here is an engine sound shipped with Roblox under rbxasset://sounds/, so none of
-- it depends on an upload and none of it can 404 into silence. Those are also the only IDs I
-- can honestly promise exist -- see LOBBY_MUSIC_ID below.
local TICK_SOUND = "rbxasset://sounds/electronicpingshort.wav"
local VOTE_SOUND = "rbxasset://sounds/switch3.wav"
local START_SOUND = "rbxasset://sounds/bass.mp3"

-- DELIBERATELY EMPTY. A lobby wants a real piece of music and there is no ambient track
-- bundled with the engine to point at; every candidate is a marketplace asset whose id I
-- cannot verify from here, and a wrong id is not an error, it is silence you then go hunting
-- for. Upload a track, paste its id here, and the loop below starts working.
local LOBBY_MUSIC_ID = ""

-- SEAGULLS AND JAZZ BOTH NEED AN UPLOAD, and neither has an engine equivalent worth faking.
--
-- Every other sound in this room is an rbxasset path that ships with Roblox, which is why
-- none of them can silently fail. There is no gull in that set and nothing close enough --
-- pitching a water impact up until it squawks would be a worse gull than no gull -- and there
-- is certainly no jazz.
--
-- So the wiring is here and the ids are not. Paste an asset id into either constant and it
-- starts working; leave them empty and nothing is created, which is why an unfilled one costs
-- exactly nothing rather than producing a silent Sound you find three weeks later.
local GULL_SOUND_ID = ""
local GULL_GAP = NumberRange.new(14, 46)

local function playAt(parent: Instance, id: string, volume: number, pitch: number)
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = volume
	sound.PlaybackSpeed = pitch
	sound.Parent = parent
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	-- Belt and braces: Ended does not fire if the asset fails to load, and an orphaned Sound
	-- per tick would accumulate for as long as the server runs.
	game:GetService("Debris"):AddItem(sound, 6)
end

local function buildAmbience(folder: Folder)
	if LOBBY_MUSIC_ID ~= "" then
		local music = Instance.new("Sound")
		music.Name = "LobbyMusic"
		music.SoundId = LOBBY_MUSIC_ID
		music.Looped = true
		music.Volume = 0.25
		-- In SoundService rather than in the room, so it does not fall off with distance:
		-- music is not coming from a place, it is the lobby having a mood.
		music.Parent = game:GetService("SoundService")
		music:Play()
	end

	-- THE SEA, as several voices rather than one.
	--
	-- A single looping sample is recognisable as a loop within about two passes, and once you
	-- have heard the seam you cannot stop hearing it. Three copies at different pitches and
	-- volumes, started at staggered offsets, have a combined period long enough that there is
	-- no seam to find -- the same trick a wave machine uses, and it costs two extra Sounds.
	--
	-- Parented to the deck rather than to a point, because the sea is on every side of this
	-- room and should not get louder as you walk toward one edge of it.
	-- QUIETER AND SPARSER. Three loops at 0.30, 0.22 and 0.16 was a sea you had to talk over;
	-- the variety was right and the level was not. Halved, with the top voice pulled back
	-- furthest, because it is the one that was doing the nagging.
	for index, voice in ipairs({
		{ 0.72, 0.15, 0.0 },
		{ 0.94, 0.10, 3.7 },
		{ 1.23, 0.06, 8.1 },
	}) do
		local swell = Instance.new("Sound")
		swell.Name = "SeaSwell_" .. index
		swell.SoundId = "rbxasset://sounds/impact_water.mp3"
		swell.Looped = true
		swell.PlaybackSpeed = voice[1] :: number
		swell.Volume = voice[2] :: number
		swell.Parent = folder
		-- Staggered starts, so the three never line up on the same beat.
		task.delay(voice[3] :: number, function()
			if swell.Parent then
				swell:Play()
			end
		end)
	end

	-- WIND OVER THE WATER, under everything else. The sea gives the room a floor of sound and
	-- nothing gives it a ceiling, so at rest the lobby is three wave loops and silence. A low,
	-- slow, very quiet layer is what stops that reading as an absence.
	local wind = Instance.new("Sound")
	wind.Name = "SeaWind"
	-- THE SAME SAMPLE AS THE SWELL, pitched right down. I was about to reach for a file named
	-- smooth.mp3 and I cannot actually confirm that ships with the engine -- and a SoundId that
	-- does not resolve is not an error, it is silence you go hunting for later.
	--
	-- impact_water at 0.35 speed is a low rumble rather than a splash, which is what wind over
	-- open water sounds like anyway, and it is a path this file already relies on.
	wind.SoundId = "rbxasset://sounds/impact_water.mp3"
	wind.Looped = true
	wind.PlaybackSpeed = 0.35
	wind.Volume = 0.12
	wind.Parent = folder
	wind:Play()

	-- And a slow swell in that wind's volume, so even the quietest layer is not a flat tone.
	task.spawn(function()
		while wind.Parent do
			local now = time()
			wind.Volume = 0.09 + math.sin(now * 0.08) * 0.04
			task.wait(0.5)
		end
	end)

	-- Occasional single breakers over the loops. Irregular on purpose: a sound at a fixed
	-- interval becomes part of the loop it was added to disguise.
	task.spawn(function()
		while folder.Parent do
			-- Twice as far apart as before: a breaker every six seconds is weather, one every
			-- fifteen to forty is a coastline.
			task.wait(math.random(150, 400) / 10)
			local crest = Instance.new("Sound")
			crest.SoundId = "rbxasset://sounds/impact_water.mp3"
			crest.PlaybackSpeed = math.random(55, 88) / 100
			crest.Volume = math.random(5, 11) / 100
			crest.Parent = folder
			crest:Play()
			game:GetService("Debris"):AddItem(crest, 8)
		end
	end)

	-- Gulls, if an id has been pasted in. Positioned randomly around the deck each time rather
	-- than played from a fixed point: a bird that always calls from the same spot is a speaker.
	if GULL_SOUND_ID ~= "" then
		task.spawn(function()
			while folder.Parent do
				task.wait(math.random(GULL_GAP.Min * 10, GULL_GAP.Max * 10) / 10)
				-- Built by hand rather than through decorPart: buildAmbience is declared well
				-- above the scenery section, so the helper does not exist yet at this point in
				-- the file. Four lines is cheaper than moving a whole block to satisfy one call.
				local away = Instance.new("Part")
				away.Name = "GullPerch"
				away.Anchored = true
				away.CanCollide = false
				away.CanTouch = false
				away.CanQuery = false
				away.Transparency = 1
				away.Size = Vector3.new(1, 1, 1)
				away.Position = HUB_ORIGIN + Vector3.new(math.random(-90, 90),
					math.random(10, 40), math.random(-90, 90))
				away.Parent = folder

				local call = Instance.new("Sound")
				call.SoundId = GULL_SOUND_ID
				call.Volume = 0.28
				call.PlaybackSpeed = math.random(88, 116) / 100
				call.RollOffMaxDistance = 220
				call.Parent = away
				call:Play()
				game:GetService("Debris"):AddItem(away, 8)
			end
		end)
	end

	-- The fountain, on the other hand, IS coming from a place, so it is a 3D sound that
	-- fades as you walk away from the water.
	local water = folder:FindFirstChild("FountainJet")
	if water and water:IsA("BasePart") then
		local splash = Instance.new("Sound")
		splash.Name = "FountainLoop"
		splash.SoundId = "rbxasset://sounds/impact_water.mp3"
		splash.Looped = true
		splash.Volume = 0.35
		splash.RollOffMaxDistance = 70
		splash.Parent = water
		splash:Play()
	end
end

-- ===== the ballot =====
--
-- THE CHOICE USED TO BE ONE SHARED VALUE, and with more than one person in the room that is
-- not a choice, it is a race: the last player to stand on a pad decided the run for everyone,
-- silently, and could be overruled a second later by someone across the floor.
--
-- Every player now carries their own three picks and the room resolves them by plurality when
-- the vote is called. That makes standing on a pad mean something on your own account, and it
-- makes the pads' numbers -- which everyone can see -- the thing that builds consensus.
--
-- The winning combination is still a plain RunRequest, so nothing downstream of this knows a
-- vote happened.
export type Ballot = { levelId: number, mode: string, length: string }

local ballots: { [Player]: Ballot } = {}

-- FORWARD-DECLARED, because the two halves of the ballot are mutually dependent and something
-- has to be named first: casting a vote broadcasts the new tally, and building that tally
-- needs the vote counts. Declared here and defined once the counting exists.
local tellState: () -> ()

-- Ties break toward the FIRST option in declaration order, which is deliberate and not
-- arbitrary: for mode that is chill, and a room that cannot agree should get the gentler run
-- rather than a coin toss that sends half of it somewhere it did not ask to go.
local MODE_ORDER = { "chill", "hardcore" }
local LENGTH_ORDER = { "short", "medium", "long" }

local function ballotFor(player: Player): Ballot
	local existing = ballots[player]
	if existing then
		return existing
	end
	local levels = HubService.padLevels()
	-- THE DEFAULT AND THE TIE-BREAK HAVE TO AGREE.
	--
	-- The ballot defaulted to medium while winner() breaks a tie toward the first option in
	-- LENGTH_ORDER, which is short. So on a fresh server your chip said "YOUR PICK: Medium"
	-- next to a lit Short pad -- both correct, from two different rules.
	--
	-- Taken from the same lists the tie-break uses, so they cannot drift apart again.
	local made: Ballot = {
		levelId = if levels[1] then levels[1].levelId else 1,
		mode = MODE_ORDER[1],
		length = LENGTH_ORDER[1],
	}
	ballots[player] = made
	return made
end

function HubService.vote(player: Player, field: string, value: any)
	local ballot = ballotFor(player)
	if field == "level" then
		ballot.levelId = value :: number
	elseif field == "mode" then
		ballot.mode = value :: string
	elseif field == "length" then
		ballot.length = value :: string
	else
		return
	end
	local folder = hubFolder
	if folder then
		playAt(folder, VOTE_SOUND, 0.5, 1.0)
	end
	-- THE READOUT FOLLOWS YOUR BALLOT WHILE YOU ARE IN THE LOBBY.
	--
	-- It was only updated when a run started, so standing on the Hardcore pad changed the pad,
	-- the halo, the chip and the banner, and left the corner panel saying Chill until the
	-- countdown finished. What the panel means in the lobby is "the mode you have asked for",
	-- and that is exactly what a ballot is.
	-- THE ROOM'S MODE, NOT YOUR BALLOT, and the difference is what the panel is FOR.
	--
	-- It was firing your own pick, so standing on Chill while the room led Hardcore left the
	-- corner saying Chill -- true about you, and wrong about the run you were about to play.
	-- What that panel answers is "what am I about to be in", and that is the tally.
	--
	-- Sent to EVERYONE, because one person's vote can change the leader for the whole room and
	-- a readout only that person sees update is worse than one nobody trusts.
	if field == "mode" and modeNotifier then
		local leading = HubService.resolveVote().mode
		for _, watcher in ipairs(Players:GetPlayers()) do
			pcall(modeNotifier :: any, watcher, leading)
		end
	end
	HubService.refreshPads()
	HubService.refreshOptionPads()
	HubService.markBallot(player)
	-- Everyone sees the tally move the moment anyone votes, whether a countdown is running or
	-- not. A ballot you cannot watch is a ballot nobody joins in on.
	tellState()
end

function HubService.ballotOf(player: Player): Ballot
	return ballotFor(player)
end

-- Counts for one field, keyed by the value voted for. Read by the pads to print their own
-- tally and by the client banner to show the room where it stands.
function HubService.counts(field: string): { [any]: number }
	local out: { [any]: number } = {}
	for player, ballot in pairs(ballots) do
		if player.Parent then
			local value: any = if field == "level"
				then ballot.levelId
				else (if field == "mode" then ballot.mode else ballot.length)
			out[value] = (out[value] or 0) + 1
		end
	end
	return out
end

local function winner(field: string, order: { any }): any
	local counts = HubService.counts(field)
	local best, bestCount = order[1], -1
	for _, option in ipairs(order) do
		local votes = counts[option] or 0
		-- Strictly greater, so a tie leaves the earlier option standing.
		if votes > bestCount then
			best, bestCount = option, votes
		end
	end
	return best
end

-- The room's decision, as a RunRequest. With nobody voting this is the first level, chill,
-- medium -- the same defaults a single player would have had before any of this existed.
function HubService.resolveVote(): RunRequest
	local levelOrder = {}
	for _, level in ipairs(HubService.padLevels()) do
		table.insert(levelOrder, level.levelId)
	end
	return {
		levelId = winner("level", levelOrder) :: number,
		mode = winner("mode", MODE_ORDER) :: string,
		length = winner("length", LENGTH_ORDER) :: string,
	}
end

function HubService.clearBallot(player: Player)
	ballots[player] = nil
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	local marks = playerGui and playerGui:FindFirstChild("HubPicks")
	if marks then
		marks:Destroy()
	end
end

-- YOUR THREE PICKS, MARKED ON THE PADS THEMSELVES.
--
-- The halo on a pad is shared geometry, so it can only ever show what the ROOM is leading
-- toward. That is the right thing for it to show and it is not enough: standing on Short while
-- the room leads Medium left no trace of your own vote anywhere in the world.
--
-- A BillboardGui parented into your PlayerGui and adorned to a pad renders on that pad for you
-- alone. Three of them, moved rather than rebuilt, is the cheapest honest answer.
local PICK_FIELDS = { "level", "mode", "length" }

function HubService.markBallot(player: Player)
	local folder = hubFolder
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not (folder and playerGui) then
		return
	end
	local marks = playerGui:FindFirstChild("HubPicks")
	if not marks then
		local made = Instance.new("Folder")
		made.Name = "HubPicks"
		made.Parent = playerGui
		marks = made
	end

	local ballot = HubService.ballotOf(player)
	for _, field in ipairs(PICK_FIELDS) do
		local target: BasePart? = nil
		for _, child in ipairs(folder:GetChildren()) do
			if child:IsA("BasePart") then
				if field == "level" then
					if child:GetAttribute("LevelId") == ballot.levelId then
						target = child
					end
				elseif child:GetAttribute("OptionField") == field then
					local want = if field == "mode" then ballot.mode else ballot.length
					if child:GetAttribute("OptionValue") == want then
						target = child
					end
				end
			end
		end
		if target then
			local tag = marks:FindFirstChild(field)
			if not tag then
				local made = Instance.new("BillboardGui")
				made.Name = field
				-- DOWN ON THE PAD, not floating in the sign's lap.
				--
				-- At 1.6 studs up this sat inside the label plate above it and the two read as
				-- one jumbled block. The chip belongs at the key's own surface -- it is about
				-- the thing you are standing on -- and the sign belongs above it. Both moved,
				-- because moving only one of them just makes a smaller collision.
				made.Size = UDim2.new(2.8, 0, 0.85, 0)
				made.StudsOffsetWorldSpace = Vector3.new(0, 0.4, 0)
				made.AlwaysOnTop = true
				made.MaxDistance = 70
				made.Parent = marks

				local chip = Instance.new("TextLabel")
				chip.Name = "Chip"
				chip.Size = UDim2.new(1, 0, 1, 0)
				chip.BackgroundColor3 = Color3.fromRGB(250, 226, 150)
				chip.BorderSizePixel = 0
				chip.FontFace = Font.new("rbxasset://fonts/families/Nunito.json",
					Enum.FontWeight.Bold)
				chip.TextScaled = true
				chip.TextColor3 = Color3.fromRGB(40, 33, 22)
				chip.Text = "YOUR PICK"
				chip.Parent = made

				local round = Instance.new("UICorner")
				round.CornerRadius = UDim.new(0.5, 0)
				round.Parent = chip

				local cap = Instance.new("UITextSizeConstraint")
				cap.MaxTextSize = 13
				cap.Parent = chip
				tag = made
			end
			(tag :: BillboardGui).Adornee = target
		end
	end
end

-- ===== calling the vote =====
--
-- Ten seconds, and votes stay OPEN for all of them. Locking them at zero would be tidier and
-- much less fun: the last five seconds of an open ballot is where a room actually talks to
-- itself, and someone switching their pick at four seconds is the whole appeal.
local COUNTDOWN_SECONDS = 10
local ANNOUNCE_SECONDS = 3

local countdown: number? = nil
local announcer: ((string, any) -> ())? = nil

function HubService.setAnnouncer(fn)
	announcer = fn
end

-- WHO IS IN THE ROOM. The ballot is a hub thing and only hub people should see it: a runner
-- halfway down a spiral has no vote, no way to reach a pad, and no use for a countdown telling
-- them what someone else is about to start.
function HubService.hubPlayers(): { Player }
	local here = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if not inRun[player] then
			table.insert(here, player)
		end
	end
	return here
end

local function tell(kind: string, payload: any)
	if announcer then
		local ok, err = pcall(announcer :: any, kind, payload)
		if not ok then
			warn("HubService: announcing the vote failed: " .. tostring(err))
		end
	end
end

-- Broadcast whenever anything about the ballot changes, countdown or not. "idle" is the state
-- with no countdown running: the banner shows the tally and tells you where the start pad is,
-- so the room is never silently waiting for someone to guess what to do.
function tellState()
	tell(if countdown ~= nil then "tick" else "idle", HubService.voteState())
end

function HubService.voteState()
	local levels = {}
	for _, level in ipairs(HubService.padLevels()) do
		table.insert(levels, { levelId = level.levelId, name = level.name })
	end
	-- COUNTS TRAVEL INSIDE THE LEVEL LIST, not in a table keyed by level id.
	--
	-- The banner read "Open Sky (0)" while Open Sky was winning, which is a contradiction the
	-- server cannot produce: resolveVote counted the votes correctly and then the count was
	-- looked up again on the client and came back nothing. A table like {[2] = 1} is a sparse
	-- array, and sparse arrays are exactly what remote serialisation is worst at -- City Shore
	-- happened to be id 1, so {[1] = n} survived as a one-element array and it alone worked.
	--
	-- An array of records has no keys to lose.
	local levelCounts = HubService.counts("level")
	for _, entry in ipairs(levels) do
		entry.votes = levelCounts[entry.levelId] or 0
	end
	local leading = HubService.resolveVote()
	return {
		secondsLeft = countdown,
		leading = leading,
		-- The leader's own counts, resolved server-side, so the banner never has to look
		-- anything up in a table that crossed the wire.
		leadingVotes = {
			level = levelCounts[leading.levelId] or 0,
			mode = HubService.counts("mode")[leading.mode] or 0,
			length = HubService.counts("length")[leading.length] or 0,
		},
		levels = levels,
		modeCounts = HubService.counts("mode"),
		lengthCounts = HubService.counts("length"),
	}
end

function HubService.isVoting(): boolean
	return countdown ~= nil
end

-- Idempotent on purpose: the start pad is a Touched trigger and four people walking across it
-- together must call one vote, not four.
-- ONE INSTANCE PER SERVER, and this line is here to prove it.
--
-- The countdown was reported ticking in PAIRS -- "tick..tick.....tick..tick" -- which one
-- coroutine on a one-second wait cannot produce. Two can. This module guards against being
-- entered twice (`countdown ~= nil` below), so a doubled tick means two separate COPIES of the
-- module, each with its own state -- and the log already showed ButterWaxSquish printing its
-- ready line twice, which is the same symptom in a different script.
--
-- Printed once at require time. If it appears twice in Output, there are two HubService
-- ModuleScripts in the place and the second one wants deleting.
print("HubService: module loaded (this line should appear exactly once per server)")

function HubService.callVote()
	if countdown ~= nil then
		return
	end
	countdown = COUNTDOWN_SECONDS
	task.spawn(function()
		-- AGAINST A DEADLINE, not by adding up waits.
		--
		-- `task.wait(1)` does not sleep one second, it sleeps AT LEAST one second and returns
		-- on the first heartbeat after that -- so every tick was a frame or two late and the
		-- lateness accumulated. Ten ticks in, the numbers and the beeps had drifted well off
		-- the seconds they were supposed to mark, which is what "not counting down second by
		-- second" is.
		--
		-- Sleeping until an absolute time instead means an overrun on one tick is absorbed by
		-- the next rather than passed on to it, so tick N always lands N seconds after the
		-- start no matter what the server was doing in between.
		local startedAt = os.clock()
		local step = 0
		while countdown ~= nil and (countdown :: number) > 0 do
			tell("tick", HubService.voteState())
			local folder = hubFolder
			if folder then
				-- Rising pitch over the last three seconds. A metronome that speeds up is the
				-- oldest trick there is for making a countdown feel like one, and it costs a
				-- single number.
				local left = countdown :: number
				playAt(folder, TICK_SOUND, 0.4, if left <= 3 then 1.5 else 1.0)
			end
			step += 1
			-- The number and the sound above are one event, and the wait below is the whole
			-- gap to the next one -- so they cannot separate.
			local target = startedAt + step
			while os.clock() < target do
				if countdown == nil then
					return
				end
				task.wait(math.min(0.1, target - os.clock()))
			end
			if countdown == nil then
				return
			end
			countdown = (countdown :: number) - 1
		end
		if countdown == nil then
			return
		end

		local decision = HubService.resolveVote()
		HubService.setLevel(decision.levelId)
		HubService.setMode(decision.mode)
		HubService.setLength(decision.length)

		local level = HubService.levelById(decision.levelId)
		if hubFolder then
			playAt(hubFolder, START_SOUND, 0.7, 1.0)
		end
		tell("result", {
			levelName = if level then level.name else "?",
			mode = decision.mode,
			length = decision.length,
			voters = HubService.voterCount(),
		})
		task.wait(ANNOUNCE_SECONDS)
		countdown = nil
		HubService.beginRun()
	end)
end

function HubService.voterCount(): number
	local total = 0
	for player in pairs(ballots) do
		if player.Parent then
			total += 1
		end
	end
	return total
end

-- Cancelled when the room empties, so a countdown started by someone who then left does not
-- fire a run into an empty lobby.
function HubService.cancelVote()
	if countdown == nil then
		return
	end
	countdown = nil
	tell("cancelled", HubService.voteState())
end

-- ===== starting a run =====

-- HOW A RUN ACTUALLY STARTS, injected by Bootstrap rather than required here.
--
-- HubService could require LevelService directly and this would be one line shorter. It does
-- not, for two reasons: the hub would then depend on the whole level-building stack in order
-- to draw a room, and sub-project C replaces this function with a teleport. Keeping it a
-- seam means C changes one assignment in Bootstrap rather than the inside of the hub.
local runner: ((level: any, players: { Player }, origin: Vector3) -> any)? = nil

function HubService.setRunner(fn)
	runner = fn
end

function HubService.spawnPosition(): Vector3
	return HUB_ORIGIN + Vector3.new(0, 4, 18)
end

-- Everyone standing in the room, which is who a run starts for. Distance rather than a
-- membership list, because a player who joined mid-selection is in the room without ever
-- having been added to anything.
local function playersInHub(): { Player }
	local found: { Player } = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") and (root.Position - HUB_ORIGIN).Magnitude < 120 then
			table.insert(found, player)
		end
	end
	return found
end

function HubService.beginRun(): boolean
	if not runner then
		warn("HubService: no runner installed, so the start pad does nothing. Bootstrap "
			.. "should call HubService.setRunner during startup.")
		return false
	end

	local current = HubService.getRequest()
	local level = HubService.levelById(current.levelId)
	if not level then
		warn(("HubService: no level with id %d. The start pad selected something that is in "
			.. "neither LevelDefinitions.All nor the Sandbox."):format(current.levelId))
		return false
	end

	-- A SCALED COPY, never the definition itself. LevelDefinitions tables are shared module
	-- state: writing minChunks onto one would make every later run on this server inherit
	-- whatever length the last player picked, which is the kind of bug that looks like the
	-- generator being random.
	local scale = HubService.lengthScale(current.length)
	local scaled = {}
	for key, value in pairs(level) do
		scaled[key] = value
	end
	local authoredMin = level.minChunks or 12
	scaled.minChunks = math.max(4, math.floor(authoredMin * scale))
	scaled.maxChunks = math.max(scaled.minChunks, math.floor((level.maxChunks or authoredMin) * scale))

	local players = playersInHub()
	-- PACK THE BANNER AWAY BEFORE THE RUN STARTS, not after.
	--
	-- Nothing ever sent "clear", so the result card was left to time out on its own -- and a
	-- second ballot after returning to the lobby found the first one's card still up, which is
	-- the "the second vote does not disappear" that was reported.
	--
	-- Sent here rather than after the runner because markInRun happens inside it: a moment
	-- later these players are no longer hub players, and the announcer would skip them.
	tell("clear", {})

	local ok, result = pcall(runner :: any, scaled, players, nextLevelOrigin())
	if not ok then
		-- The same rule Bootstrap already applies to lighting and the backdrop: a failure
		-- here must leave players standing in the room, not nowhere.
		warn("HubService: starting the run failed, players stay in the hub: " .. tostring(result))
		return false
	end
	return true
end

-- ===== how you stand on your own plinth =====

-- MODELLED, NOT ASSEMBLED FROM PRIMITIVES.
--
-- The first planter was a cylinder, a square slab of soil that did not fit the circle, and
-- five green spheres. Every part of that was a placeholder: a square inside a circle is
-- wrong at any size, and spheres are not leaves.
--
-- Hub_Planter, Hub_Soil and Hub_Plant come out of gen_hub_props.py. A tapered bowl with a
-- rolled rim, a round mounded soil disc that fits it, and a three-tier leaf rosette.
local function propMesh(name: string): BasePart?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("TileMeshes")
	if not folder then
		return nil
	end
	local found = folder:FindFirstChild(name)
	if found and found:IsA("BasePart") then
		return found
	end
	-- The importer wraps each mesh in a Model, which the rest of this codebase unwraps the
	-- same way.
	if found then
		local inner = found:FindFirstChildWhichIsA("BasePart", true)
		if inner then
			return inner
		end
	end
	return nil
end

-- The Backdrop folder, not TileMeshes. City Shore's horizon props are imported there, and the
-- lobby borrows from them rather than shipping a second copy of a sea.
local function backdropProp(name: string): BasePart?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("Backdrop")
	local found = folder and folder:FindFirstChild(name)
	if found and not found:IsA("BasePart") then
		found = found:FindFirstChildWhichIsA("BasePart", true)
	end
	if found and found:IsA("BasePart") then
		return found
	end
	warnOnce("nobackdrop_" .. name, "HubService: " .. name .. " is not in "
		.. "ReplicatedStorage/Assets/Backdrop, so the lobby falls back to a plain slab.")
	return nil
end

-- One mesh, placed. Returns nil rather than throwing when the asset is not imported, so a
-- missing prop costs that prop and nothing else in the room.
local function propAt(name: string, at: Vector3, parent: Folder, turn: number?): BasePart?
	local template = propMesh(name)
	if not template then
		warnOnce("noprop_" .. name, "HubService: " .. name .. " is not imported, so the lobby "
			.. "is missing it. Import it into ReplicatedStorage/Assets/TileMeshes.")
		return nil
	end
	local prop = template:Clone()
	prop.Name = name
	prop.Anchored = true
	prop.CanCollide = false
	prop.CanTouch = false
	prop.CanQuery = false
	prop.CFrame = CFrame.new(at) * CFrame.Angles(0, turn or 0, 0)
	prop.Parent = parent
	return prop
end

-- POSES, as joint rotations rather than animations.
--
-- An Animation needs an uploaded asset and a running Animator, and the figure on the plinth
-- is deliberately neither -- it is an anchored rig with no state machine. Rotating the
-- Motor6Ds directly is what a static pose actually is, and it costs no assets at all.
--
-- Named for what they say rather than for the joints they move, because that is how someone
-- picks one.
-- THE ANGLES WERE FAR TOO SMALL. Hero rotated a shoulder by 18 degrees and tipped the waist
-- by 6; Lean moved a hip by 7. Those are the numbers you would use to blend BETWEEN poses, not
-- to make one, and on a figure eight studs away across a room they are invisible. Every pose
-- looked like Stand with a slight list.
--
-- A pose that has to read at a distance needs the silhouette to change, which in practice
-- means the limbs leave the body's outline: 60 degrees and up on a shoulder, not 18.
--
-- R15 AND R6 NAMES IN THE SAME TABLE. An R15 rig calls its arm joint RightShoulder; an R6 rig
-- calls it "Right Shoulder", with a space, and hangs it off the torso. Listing both costs
-- nothing -- applyPose looks each joint up by its own name, so whichever rig the player has,
-- the entries for the other one simply never match.
-- POSES AS DIRECTIONS, NOT ANGLES. This is the fourth attempt at this table and the first one
-- that cannot be wrong about a convention, because it does not depend on one.
--
-- === What the axis probe found ===
--
-- Every limb on this rig runs along its joint's -Y, give or take a splay:
--
--     RightShoulder ( 0.56, -0.81,  0.18)      RightHip   (-0.24, -0.97, 0.02)
--     RightElbow    ( 0.43, -0.90, -0.00)      RightKnee  (-0.27, -0.96, 0.03)
--
-- So the axis convention was RIGHT all along, and three rounds of suspecting it were wasted.
-- But look at the numbers again: an arm at rest is already 34 degrees off -Y, and a leg 14. An
-- angle table adds to whatever the rest pose happens to be, so "rotate the shoulder 62 degrees"
-- lands somewhere different on every rig -- and on two joints of the SAME rig, if their splay
-- differs. That is why Lean and Wave came out looking alike: both were adding large rotations
-- to limbs that were not where the numbers assumed they started.
--
-- === What this does instead ===
--
-- Each entry says where the limb should POINT, as a direction in the figure's own frame:
-- X is its right, Y is up, Z is the way it faces. The code measures where the limb actually
-- points at rest and computes the rotation between the two. Whatever the rig's rest pose is,
-- the arm ends up where the table says.
--
-- A direction cannot express a twist about the limb's own axis, which is a real limitation and
-- costs nothing here: no pose below turns a forearm over.
-- A JOINT LEFT OUT OF A POSE INHERITS ITS PARENT, and that is what makes the head follow.
--
-- Targets are absolute directions in the figure's frame, which is right for a limb and wrong
-- for a head: "point the neck up" stays true however far the chest leans, so the chest tipped
-- 23 degrees and the head stayed bolt upright, looking detached from the body under it.
--
-- Omitting Neck rotates it by nothing, so it keeps its rest relationship to the chest and goes
-- wherever the chest goes. Lean and Ready therefore say nothing about the neck at all. Hero and
-- Wave still do, because their chests barely move and the chin and the turn are the pose.
local POSES: { [string]: { [string]: Vector3 } } = {
	-- Rest. Every joint left exactly where the rig puts it.
	Stand = {},

	-- Arms out and down, chest open, chin up.
	-- ARMS UP, NOT ARMS OUT.
	--
	-- This read as Stand, and the numbers say why: the shoulders were at (0.82, -0.57), which
	-- is 55 degrees out from vertical but still pointing DOWNWARD, and the waist and neck moved
	-- 8 and 14 degrees. Arms hanging a bit wide with an almost imperceptible lean is not a
	-- different pose from arms hanging straight -- it is the same pose with worse posture.
	--
	-- The problem was that every entry was a modest adjustment to rest. A pose has to commit to
	-- something. This one commits to the one shape that cannot be mistaken for standing: both
	-- arms raised in a wide V, above the shoulder line, where an arm never is by accident.
	--
	-- It also has to stay clear of Wave, which is the other pose with a raised arm. Wave raises
	-- ONE arm and drops the other; this raises both and braces the legs, so the two are
	-- distinguishable from behind, in silhouette, at any distance.
	Hero = {
		-- Above the horizontal. Positive Y is what makes this a different pose.
		RightShoulder = Vector3.new(0.66, 0.75, 0),
		LeftShoulder = Vector3.new(-0.66, 0.75, 0),
		-- Forearms carry on up rather than bending away, so the V reads as one clean line from
		-- hand to hand rather than as two elbows.
		RightElbow = Vector3.new(0.40, 0.91, 0.10),
		LeftElbow = Vector3.new(-0.40, 0.91, 0.10),
		-- Chest opened by leaning the torso back. 18 degrees rather than 8: enough to see, and
		-- with no Neck entry the head rides it, so the chin comes up as well.
		--
		-- WAIST POINTS UP, because the walk is rooted at the lower torso: the joint's far side
		-- is the chest, and a chest points upward.
		Waist = Vector3.new(0, 0.95, -0.31),
		-- Braced. Feet apart under a raised body is what stops this looking like someone
		-- reaching for something on a high shelf.
		RightHip = Vector3.new(0.32, -0.95, 0),
		LeftHip = Vector3.new(-0.32, -0.95, 0),
	},

	-- One arm straight up, the other hanging, head turned toward it.
	Wave = {
		RightShoulder = Vector3.new(0.36, 0.93, 0),
		RightElbow = Vector3.new(0.12, 0.99, 0.05),
		LeftShoulder = Vector3.new(-0.22, -0.97, 0),
		Neck = Vector3.new(0.30, 0.95, 0),
	},

	-- Weight on the left leg, hip pushed right, right hand resting on it, head tipped away.
	--
	-- THE TILT WAS TOO SMALL TO BE A LEAN. A waist of (0.30, 0.95, 0) is 17 degrees off
	-- vertical, and 17 degrees on a blocky rig seen from across the lobby is not a pose, it is
	-- a rounding error -- which is why this kept coming back as "the torso is not moving". It
	-- WAS moving. It was moving by an amount nobody can see.
	--
	-- 0.62 across against 0.78 up is 38 degrees, and 38 degrees is unmistakably a lean. The
	-- head now counters it: a real lean tips the body and keeps the head nearer level, and
	-- with no Neck entry the skull just went along for the ride, which reads as falling over.
	Lean = {
		Waist = Vector3.new(0.62, 0.78, 0),
		-- NO NECK ENTRY, and that is deliberate rather than an omission.
		--
		-- A joint with no entry is not posed, and an unposed joint inherits its parent
		-- exactly -- so the head rides the chest and a lean tips the whole upper body as one
		-- piece. That is what was asked for and it is the simplest thing the rig can do.
		--
		-- Every attempt to be cleverer here made it worse. A Neck target is written in the
		-- FIGURE's frame, not relative to the chest it hangs off, so aiming the head at some
		-- absolute angle while the chest leans asks the neck for the DIFFERENCE between the
		-- two -- which is how "a slight counter-tilt" turned into a 58-degree bend and a head
		-- that looked stuck on at the wrong angle.
		-- The legs stay planted and take the weight. Both hips splay the same way their own
		-- side's shoulder does, which is the rule the rest of this table keeps.
		RightHip = Vector3.new(0.30, -0.95, 0),
		LeftHip = Vector3.new(-0.10, -0.99, 0.05),
		LeftKnee = Vector3.new(-0.05, -0.99, -0.10),
		RightShoulder = Vector3.new(0.58, -0.81, 0),
		RightElbow = Vector3.new(0.20, -0.72, 0.66),
		LeftShoulder = Vector3.new(-0.28, -0.96, 0),
	},

	-- Crouched, arms forward, knees bent. The knees are the tell: nothing else reads as ready.
	Ready = {
		-- The chest pitched forward over planted legs: the crouch.
		Waist = Vector3.new(0, 0.90, 0.44),
		-- NO NECK ENTRY, for the same reason as Lean: the head follows the chest. A 26-degree
		-- forward pitch carried through to the skull is a person looking at the ground just
		-- ahead of them, which is exactly where somebody about to move is looking.
		-- MODERATED. The first version put the thighs 35 degrees forward and the shins 30 back,
		-- which is a deep squat -- and a deep squat on a rig whose ankles are not posed leaves
		-- the feet pointing into the plinth, which is what the screenshot showed.
		--
		-- Half the bend reads as ready and keeps the feet under the body. A crouch that is
		-- legible beats a crouch that is athletic.
		RightShoulder = Vector3.new(0.30, -0.55, 0.78),
		LeftShoulder = Vector3.new(-0.30, -0.55, 0.78),
		RightElbow = Vector3.new(0.22, -0.15, 0.96),
		LeftElbow = Vector3.new(-0.22, -0.15, 0.96),
		-- THE LEGS WERE SIGNED BACKWARDS, and against this pose's own arms.
		--
		-- Right went -X and left went +X while the shoulders two rows up went +X and -X.
		-- Positive X is the figure's right everywhere else in this table, so the two thighs
		-- were aimed ACROSS each other: the knees crossed, the shins splayed out from the
		-- crossing point, and that tangle is what the screenshot shows.
		RightHip = Vector3.new(0.16, -0.90, 0.40),
		LeftHip = Vector3.new(-0.16, -0.90, 0.40),
		RightKnee = Vector3.new(0.14, -0.95, -0.28),
		LeftKnee = Vector3.new(-0.14, -0.95, -0.28),
	},
}

local POSE_ORDER = { "Stand", "Hero", "Wave", "Lean", "Ready" }
local poseFor: { [Player]: string } = {}

-- Cleared when a figure is (re)built, so RestC0 is never carried over from a rig that had
-- not finished scaling. See the comment in buildStatue for why that mattered.
local function forgetRest(model: Model)
	for _, item in ipairs(model:GetDescendants()) do
		if item:IsA("Motor6D") then
			item:SetAttribute("RestC0", nil)
		end
	end
end

-- Returns placed joints, joints actually turned, and joints whose NAME the pose asked for.
--
-- The third number is the one the "matched none of the figure's joints" warning is about, and
-- until now that warning was reading the second. Those are different questions: turning
-- nothing means the figure is already in this pose, while matching nothing means the pose is
-- addressing joints that do not exist on this rig. Only the second is a bug, and testing for
-- it with the first is what made Hero warn five times about a pose it had applied correctly.
local function applyPose(model: Model, poseName: string): (number, number, number)
	local pose = POSES[poseName] or POSES.Stand
	local joints, moved = 0, 0
	-- ONE POSE PATH, NOT THREE. The Motor6D C0 loop, the AnimationConstraint Transform loop
	-- and the Bone loop all used to run here, each writing the same pose through a different
	-- mechanism on the theory that whichever the rig had would win.
	--
	-- Two of them were dead on this rig and the third did not move anything -- Transform is an
	-- animation channel and nothing was evaluating it. Meanwhile the forward kinematics below
	-- moved the parts directly and correctly, so all three were noise: they doubled the joint
	-- counts in the log (30 of 30 on a rig with 15 joints) and, now that the pose table holds
	-- directions rather than CFrames, they would throw rather than merely idle.
	local function poseByParts(): (number, number)
		-- ===== REWRITTEN TO WORK IN THE FIGURE'S OWN SPACE =====
		--
		-- Every earlier version converted the target direction INTO the joint's attachment
		-- frame, rotated there, and converted back. That is where four rounds of "the pose is
		-- still wrong" came from, and the reason is simple: an attachment's orientation is
		-- authored per rig and I have no way to see it from here. Get it wrong and the
		-- rotation is about the wrong axis -- which does not look like a bug, it looks like a
		-- pose that is nearly right and subtly broken, every single time.
		--
		-- NOTHING HERE READS AN ATTACHMENT'S ORIENTATION. An attachment is used for one thing
		-- only: its POSITION, which is where the joint physically is. That is a fact about the
		-- rig I can measure and cannot misread.
		--
		-- The method is plain forward kinematics:
		--
		--   1. Find where the joint is (the attachment's world position).
		--   2. Measure which way the limb currently points, in world space.
		--   3. Work out the single rotation carrying that onto the direction the pose asks
		--      for -- also in world space.
		--   4. Rotate the joint's whole subtree about the joint position by that rotation.
		--
		-- Step 4 is the other half of the fix. The old code set each part from its parent's
		-- frame one edge at a time, so a mistake anywhere propagated outward and the head
		-- ended up somewhere its own joint had never asked for. Rotating a subtree as a rigid
		-- body cannot separate anything: the head stays exactly where it is relative to the
		-- neck, because they move together.
		type Edge = { constraint: any, other: BasePart }

		-- Where a joint IS, right now. Read fresh every time rather than remembered, for the
		-- reason set out where the edges are built.
		local function pivotOf(edge: Edge): Vector3
			return (edge.constraint.Attachment0.WorldPosition
				+ edge.constraint.Attachment1.WorldPosition) / 2
		end
		local edges: { [BasePart]: { Edge } } = {}

		for _, item in ipairs(model:GetDescendants()) do
			if item:IsA("AnimationConstraint") and item.Attachment0 and item.Attachment1 then
				local one = item.Attachment0.Parent
				local two = item.Attachment1.Parent
				if one and one:IsA("BasePart") and two and two:IsA("BasePart") then
					-- NO PIVOT CACHED HERE, and that was the whole of the last failure.
					--
					-- The joint's position was measured once, while the figure was still at
					-- rest, and then used later to rotate about. But by the time a joint is
					-- reached its ancestors have already moved, and the joint moved with them
					-- -- so every limb below the first rotation was being turned about a point
					-- the joint had long since left. A rotation about the wrong centre does not
					-- just aim wrong, it TRANSLATES: the limb swings away from the body.
					--
					-- That is why fixing two poses broke all five. Stand has no entries and was
					-- untouched; every pose that turned anything displaced everything below it.
					--
					-- The position is read live at the moment it is used instead. It stays
					-- correct because a subtree is rotated RIGIDLY -- parent and child move by
					-- the same transform, so their two attachments remain coincident and the
					-- average of them remains the joint.
					edges[one] = edges[one] or {}
					edges[two] = edges[two] or {}
					table.insert(edges[one], { constraint = item, other = two })
					table.insert(edges[two], { constraint = item, other = one })
				end
			end
		end

		-- ROOTED AT THE LOWER TORSO. The walk holds its root still and moves everything
		-- outward from it, so the root decides what a waist rotation moves. Rooted at the
		-- UPPER torso the waist swings the hips and legs while the chest stays put, which is
		-- a lean of the legs and not a lean.
		local root: BasePart? = nil
		for _, name in ipairs({ "LowerTorso", "UpperTorso", "Torso", "HumanoidRootPart" }) do
			local candidate = model:FindFirstChild(name)
			if candidate and candidate:IsA("BasePart") and edges[candidate] then
				root = candidate
				break
			end
		end
		if not root then
			local best = 0
			for part, list in pairs(edges) do
				if #list > best then
					root, best = part, #list
				end
			end
		end
		if not root then
			return 0, 0
		end

		-- The tree, as parent -> children, discovered outward from the root. Direction comes
		-- from the traversal rather than from which attachment the rig happened to use.
		local order: { BasePart } = { root }
		local parentOf: { [BasePart]: BasePart } = {}
		local jointOf: { [BasePart]: Edge } = {}
		local kids: { [BasePart]: { BasePart } } = {}
		local seen: { [BasePart]: boolean } = { [root] = true }
		local at = 1
		while at <= #order do
			local here = order[at]
			at += 1
			for _, edge in ipairs(edges[here] or {}) do
				if not seen[edge.other] then
					seen[edge.other] = true
					parentOf[edge.other] = here
					jointOf[edge.other] = edge
					kids[here] = kids[here] or {}
					table.insert(kids[here], edge.other)
					table.insert(order, edge.other)
				end
			end
		end

		-- Everything at or below a part, so a joint can move its limb in one piece.
		local function subtree(part: BasePart): { BasePart }
			local out: { BasePart } = {}
			local stack: { BasePart } = { part }
			while #stack > 0 do
				local here = table.remove(stack) :: BasePart
				table.insert(out, here)
				for _, child in ipairs(kids[here] or {}) do
					table.insert(stack, child)
				end
			end
			return out
		end

		-- ===== EVERY POSE STARTS FROM REST =====
		--
		-- THIS IS WHY STAND LOOKED LIKE HERO. Stand has no entries, and an entry is the only
		-- thing that moves a joint -- so applying Stand did nothing at all and the figure kept
		-- standing in whatever pose it was already holding. Step off Hero onto Stand and you
		-- got Hero, every time. Stand was not copying Hero; it was failing to undo it.
		--
		-- It also fixes something quieter. Poses were being applied ON TOP of each other, so
		-- Lean-then-Ready started from Lean's limbs rather than from the rig's. The aiming is
		-- absolute so it mostly converged, but "mostly" is doing real work in that sentence:
		-- any joint a pose does not mention kept the previous pose's angle forever.
		--
		-- Rest is captured once, the first time a figure is posed, while it is still the fresh
		-- clone -- and stored RELATIVE TO THE ROOT so that moving the statue onto its plinth
		-- afterwards does not invalidate it.
		local restKey = "RestPose"
		if not model:GetAttribute(restKey) then
			model:SetAttribute(restKey, true)
			for _, part in ipairs(order) do
				part:SetAttribute("Rest", root.CFrame:Inverse() * part.CFrame)
			end
		end
		for _, part in ipairs(order) do
			local rest = part:GetAttribute("Rest")
			if typeof(rest) == "CFrame" then
				part.CFrame = root.CFrame * rest
			end
		end

		-- OUTWARD FROM THE ROOT, so a joint is aimed after everything above it has already
		-- moved. `order` is breadth-first from the root, which is exactly that order.
		local facing = root.CFrame
		local placed, turned, matched = 0, 0, 0

		-- WHERE THE HEAD STARTS, so the report below can say whether it actually went
		-- anywhere. "The head is not moving" has come back four times now and I have been
		-- answering it by reasoning about the code rather than by measuring the head, which
		-- is exactly the habit that made it take four rounds.
		local headPart = model:FindFirstChild("Head")
		local headWas = if headPart and headPart:IsA("BasePart") then headPart.Position else nil
		for index = 2, #order do
			local part = order[index]
			local edge = jointOf[part]
			placed += 1
			local want = pose[edge.constraint.Name]
			if want then
				-- Counted whether or not the joint has to move. A limb already pointing where
				-- it was asked to point has still MATCHED; it simply has nothing to do.
				matched += 1
				-- Which way the limb points NOW. Measured live rather than from a stored rest
				-- pose, because "now" already includes every rotation applied above it -- that
				-- is what makes the chain add up instead of fighting itself.
				local pivot = pivotOf(edge)
				local reach = part.Position - pivot
				if reach.Magnitude > 0.05 then
					local from = reach.Unit
					-- The target is written in the figure's frame, so a pose reads the same
					-- whichever way the statue is turned on its plinth.
					local to = facing:VectorToWorldSpace(want.Unit)
					local axis = from:Cross(to)
					local rotation
					if axis.Magnitude < 1e-4 then
						if from:Dot(to) > 0 then
							rotation = CFrame.identity
						else
							-- Exactly opposed: no unique axis, so any perpendicular will do.
							local other = if math.abs(from.Y) < 0.9
								then Vector3.new(0, 1, 0)
								else Vector3.new(1, 0, 0)
							rotation = CFrame.fromAxisAngle(from:Cross(other).Unit, math.pi)
						end
					else
						rotation = CFrame.fromAxisAngle(axis.Unit,
							math.acos(math.clamp(from:Dot(to), -1, 1)))
					end
					if rotation ~= CFrame.identity then
						turned += 1
						-- THE WHOLE LIMB, ROTATED AS ONE PIECE, about the joint. Conjugating
						-- by the pivot turns the rotation about that point rather than about
						-- the world origin, and applying it to every part below means the
						-- limb keeps its own shape exactly.
						local about = CFrame.new(pivot)
						local move = about * rotation * about:Inverse()
						for _, item in ipairs(subtree(part)) do
							item.CFrame = move * item.CFrame
						end
					end
				end
			end
		end

		-- THE REST OF THE BODY, which the constraint graph does not reach.
		--
		-- Hair, hats, faces and any other accessory hang off a Weld, not an AnimationConstraint
		-- -- so the walk above never touched them. With every part anchored they simply stayed
		-- where the clone was made, which is why the statue kept its pose and lost its hair,
		-- and why a stray head of hair turned up hovering over the spawn pad.
		--
		-- A Weld says the same thing a constraint does, in different words: Part1 sits at
		-- Part0's frame, through C0 and C1. Repeated until nothing moves, because an accessory
		-- can hang off another accessory and one pass would leave the outer one behind.
		-- WHAT THE WALK ALREADY PLACED, so the pass below cannot undo it.
		--
		-- THIS IS THE HEAD BUG, and it is why four rounds of fixing the posing changed
		-- nothing. The pass below moves the Part1 of every Weld and the host of every
		-- RigidConstraint, and it does not ask whether that part is an accessory. On a
		-- constraint-rig avatar the head carries rigid attachments of its own, so the pose
		-- would turn the head correctly and then this loop -- running immediately afterwards,
		-- six times over -- would snap it straight back to a frame computed from a part that
		-- had not moved.
		--
		-- The pose was never failing. It was being applied and then reverted, half a
		-- millisecond later, by the code meant to bring the hair along with it.
		--
		-- Accessories are exactly the parts the constraint graph does NOT reach, so the set
		-- the walk placed is precisely the set this must leave alone.
		local posed: { [BasePart]: boolean } = {}
		for _, part in ipairs(order) do
			posed[part] = true
		end

		for _ = 1, 6 do
			local settled = true
			for _, item in ipairs(model:GetDescendants()) do
				-- WHICHEVER END IS THE ACCESSORY, moved to follow whichever end is the body.
				--
				-- Skipping any joint that touched a posed part was too blunt. A constraint can
				-- be authored either way round -- the hair's may well hold the HEAD as its
				-- Part1 -- and in that case skipping it moved neither: the head stayed
				-- correct and the hair stayed behind, floating where the figure had been.
				--
				-- What actually has to be true is only this: the posed part wins and the other
				-- one follows. So the direction is decided by which side was posed, rather
				-- than by which side the rig happened to write first.
				if (item:IsA("Weld") or item:IsA("Motor6D")) and item.Part0 and item.Part1 then
					local zero, one = item.Part0, item.Part1
					local follower, anchorPart, c0, c1 = one, zero, item.C0, item.C1
					if posed[one] and not posed[zero] then
						follower, anchorPart, c0, c1 = zero, one, item.C1, item.C0
					end
					if not posed[follower] then
						local want = anchorPart.CFrame * c0 * c1:Inverse()
						if not follower.CFrame:FuzzyEq(want, 0.001) then
							follower.CFrame = want
							settled = false
						end
					end

				-- RIGIDCONSTRAINT, which is how a modern avatar attaches its accessories.
				--
				-- The Weld pass alone did not bring the hair back, and the census is why: 54
				-- Attachments against 15 joint constraints leaves a great many attachment pairs
				-- doing something else, and on a constraint-rig avatar that something is
				-- RigidConstraint holding each accessory to its body part.
				--
				-- It is the same arithmetic as a Weld written in attachment terms: put
				-- Attachment1's part where Attachment0 already is.
				elseif item:IsA("RigidConstraint") and item.Attachment0 and item.Attachment1 then
					-- Same rule as the welds above. On this rig the hair is held by a
					-- RigidConstraint whose posed end may be either attachment, so the one that
					-- moves is chosen by what was posed rather than by its number.
					local anchorAt, followAt = item.Attachment0, item.Attachment1
					local host = followAt.Parent
					if host and host:IsA("BasePart") and posed[host] then
						anchorAt, followAt = item.Attachment1, item.Attachment0
						host = followAt.Parent
					end
					if host and host:IsA("BasePart") and not posed[host] then
						local want = anchorAt.WorldCFrame * followAt.CFrame:Inverse()
						if not host.CFrame:FuzzyEq(want, 0.001) then
							host.CFrame = want
							settled = false
						end
					end
				end
			end
			if settled then
				break
			end
		end

		model:SetAttribute("AxesLogged", true)
		-- ONE LINE PER POSE, once per figure. If the head did not move this says so in
		-- studs, and it lists the joints the pose asked for against the joints the rig
		-- actually has -- so a name that does not exist on this rig shows up as a name in
		-- the first list and not the second, instead of as a limb that quietly does nothing.
		-- PER POSE, not once per figure. Logged once per model, the very first thing it
		-- caught was Stand -- which has no entries at all -- so it printed an empty pose and
		-- a head that had correctly not moved, and said nothing about the poses being asked
		-- about. A probe that reports the one case nobody is asking about is not a probe.
		local logKey = "PoseLogged_" .. poseName
		if not model:GetAttribute(logKey) then
			model:SetAttribute(logKey, true)
			local asked, found = {}, {}
			for name in pairs(pose) do
				table.insert(asked, name)
			end
			for index = 2, #order do
				table.insert(found, jointOf[order[index]].constraint.Name)
			end
			table.sort(asked)
			table.sort(found)
			local moved = if headWas and headPart and headPart:IsA("BasePart")
				then (headPart.Position - headWas).Magnitude
				else -1
			print(("HubService: pose turned %d of %d joints; head moved %.2f studs"):format(
				turned, placed, moved))
			print("HubService:   pose asks for: " .. table.concat(asked, ", "))
			print("HubService:   rig provides:  " .. table.concat(found, ", "))
		end
		return placed, turned, matched
	end

	if not model:GetAttribute("Rigid") then
		-- ANCHOR EVERYTHING, once, and only after the pose has been computed. Anchoring before
		-- body scaling is what put a head in the wrong place several rounds ago; anchoring
		-- after the parts are already where they belong is just freezing a finished statue.
		for _, item in ipairs(model:GetDescendants()) do
			if item:IsA("BasePart") then
				item.Anchored = true
			end
		end
		model:SetAttribute("Rigid", true)
	end

	local placedParts, turnedJoints = poseByParts()
	if placedParts > 0 then
		joints += placedParts
		moved += turnedJoints
	end
	-- WAKE THE ASSEMBLY. The figure has an anchored root and unanchored limbs, so it is a
	-- simulated assembly, and a simulated assembly that has come to rest is asleep. Writing a
	-- Motor6D on a sleeping assembly changes the joint without the solver ever being asked to
	-- move the parts, so nothing visibly happens -- which is a very good description of the
	-- symptom this has had for three rounds.
	--
	-- Reassigning the root's own CFrame is the cheap way to ask for a re-solve.
	local root = model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		root.CFrame = root.CFrame
	end
	return joints, moved
end

-- THE FIGURE, as its own function so it can be rebuilt on demand.
--
-- CreateHumanoidModelFromDescription was the wrong tool and it took four rounds to prove:
-- the model it returns carries the parts and their rig attachments, and the engine only
-- builds the Motor6Ds joining them when that model becomes a live character. This one never
-- does -- anchored root, state machine off, parented under a plinth -- so it stayed a pile of
-- limbs and every pose was applied to a rig that did not exist.
--
-- player.Character is a rig Roblox has already assembled, so cloning it cannot produce a
-- jointless figure. The original objection was that a clone drags along whatever the character
-- is carrying, which is a few lines to strip and a far smaller problem than a statue that
-- cannot be posed.
local function attachFigure(player: Player, stand: BasePart)
	local existing = stand:FindFirstChild("Figure")
	if existing then
		existing:Destroy()
	end
	local character = player.Character or player.CharacterAdded:Wait()
	if not (character and stand.Parent) then
		return
	end
	-- ARCHIVABLE ON EVERY DESCENDANT, not just the model.
	--
	-- This is why the clone had no Motor6Ds. Clone() silently SKIPS any descendant whose
	-- Archivable is false, and the joints Roblox assembles when a character spawns are created
	-- at runtime with Archivable off. So the copy came back with every limb present and
	-- nothing holding them together -- which is exactly what the diagnostic reported, and it
	-- reported it against a rig that was demonstrably fine, because the original still had its
	-- joints. The flag is on the things being skipped, not on the thing being copied.
	character.Archivable = true
	for _, item in ipairs(character:GetDescendants()) do
		item.Archivable = true
	end

	-- COUNTED ON BOTH SIDES, once. Six attempts have gone into why the copy has no Motor6Ds,
	-- and every one of them assumed the ORIGINAL had some. That has never actually been
	-- checked, and it is one line: if the live character also reports zero, the bug was never
	-- in Clone at all and every fix so far has been aimed at the wrong half of the problem.
	local before = 0
	for _, item in ipairs(character:GetDescendants()) do
		if item:IsA("Motor6D") then
			before += 1
		end
	end

	local cloneOk, clone = pcall(function()
		return character:Clone()
	end)
	if not cloneOk or not clone then
		warn("HubService: could not clone the character for the statue: " .. tostring(clone))
		return
	end

	local model = clone :: Model
	model.Name = "Figure"

	local after = 0
	for _, item in ipairs(model:GetDescendants()) do
		if item:IsA("Motor6D") then
			after += 1
		end
	end
	-- A CENSUS, ONCE. Seven rounds have gone into this and each one narrowed the question
	-- without answering it: no Motor6Ds on either side means the rig is made of something
	-- else, and Bone was an educated guess. This lists what is ACTUALLY in there, so the next
	-- report either confirms the guess or names the thing nobody has thought of.
	local census: { [string]: number } = {}
	for _, item in ipairs(model:GetDescendants()) do
		local class = item.ClassName
		if class == "Motor6D" or class == "Bone" or class == "Weld" or class == "WeldConstraint"
			or class == "MeshPart" or class == "Part" or class == "Humanoid"
			or class == "Attachment" or class == "AnimationConstraint" then
			census[class] = (census[class] or 0) + 1
		end
	end
	local parts = {}
	for class, count in pairs(census) do
		table.insert(parts, ("%s x%d"):format(class, count))
	end
	table.sort(parts)
	print(("HubService: %s's live character has %d Motor6Ds, the clone has %d. Clone contains: %s")
		:format(player.Name, before, after, table.concat(parts, ", ")))

	-- PARENTED BEFORE ANY OF IT IS TOUCHED, and this is the ordering lesson of the whole
	-- statue saga. Every operation below -- stripping scripts, unanchoring parts, rebuilding
	-- the rig -- was being performed on a model sitting outside the DataModel, where Roblox's
	-- own rig machinery has nothing to work against. That is how a copy of a demonstrably
	-- rigged character kept arriving with no joints in it.
	--
	-- In the world first, one frame to settle, then the surgery.
	model.Parent = stand
	task.wait()
	if not stand.Parent then
		model:Destroy()
		return
	end

	-- Strip everything that would try to BE a character: scripts, tools, the state
	-- machine, and anything that would make it walk off its own plinth.
	for _, item in ipairs(model:GetDescendants()) do
		if item:IsA("BaseScript") or item:IsA("Tool") or item:IsA("Sound") then
			item:Destroy()
		end
	end
	local humanoid = model:FindFirstChildWhichIsA("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.EvaluateStateMachine = false
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		-- THE ONE WAY A CLONED RIG CAN STILL LOSE ITS JOINTS. A Humanoid that reaches zero
		-- health severs every Motor6D under it, and a clone parented into the world with
		-- its state machine off can end up counted as dead. Turning that off makes the
		-- jointless-figure failure impossible rather than merely unlikely.
		humanoid.BreakJointsOnDeath = false
		humanoid.RequiresNeck = false
		humanoid.Health = humanoid.MaxHealth
	end

	-- ANCHOR THE ROOT ONLY, and let the Motor6Ds hold everything else.
	--
	-- Anchoring every part is what put the head in the wrong place two rounds ago: body
	-- scaling is applied THROUGH the joints, so freezing each part in place leaves limbs
	-- at offsets that no longer match the torso.
	for _, item in ipairs(model:GetDescendants()) do
		if item:IsA("BasePart") then
			item.Anchored = false
			item.CanCollide = false
			item.CanQuery = false
		end
	end
	local rootPart = model:FindFirstChild("HumanoidRootPart")
	if rootPart and rootPart:IsA("BasePart") then
		rootPart.Anchored = true
	end

	-- BELT AND BRACES: if the copy still came back jointless, rebuild the joints by hand from
	-- the original. Every Motor6D is a named link between two named parts, so it can be
	-- reconstructed exactly as long as both models have the same part names -- which they do,
	-- being copies of each other.
	local hasJoints = false
	for _, item in ipairs(model:GetDescendants()) do
		if item:IsA("Motor6D") then
			hasJoints = true
			break
		end
	end
	if not hasJoints then
		for _, source in ipairs(character:GetDescendants()) do
			if source:IsA("Motor6D") and source.Part0 and source.Part1 then
				local part0 = model:FindFirstChild(source.Part0.Name, true)
				local part1 = model:FindFirstChild(source.Part1.Name, true)
				if part0 and part0:IsA("BasePart") and part1 and part1:IsA("BasePart") then
					local joint = Instance.new("Motor6D")
					joint.Name = source.Name
					joint.Part0 = part0
					joint.Part1 = part1
					joint.C0 = source.C0
					joint.C1 = source.C1
					joint.Parent = part1
				end
			end
		end
	end

	-- RESET TO THE RIG'S REST POSE BEFORE ANYTHING IS REMEMBERED.
	--
	-- The clone is a snapshot of a LIVE character, so its joints hold whatever mid-stride
	-- transform the player happened to be in when they walked onto the pad. RestC0 then
	-- captures that stride as "the original", every pose is built on top of it, and Stand --
	-- which applies no rotation at all -- comes out as a frozen run. That is exactly the
	-- report: every pose looking like the same running pose.
	--
	-- BuildRigFromAttachments rebuilds each Motor6D from the rig attachments, which is the
	-- definition of the rest pose. It failed on the description model because that had no
	-- joints to rebuild; on a real cloned rig it is the right tool.

	-- AFTER PARENTING, and this was very likely the last of it. BuildRigFromAttachments tears
	-- the Motor6Ds down and rebuilds them from the rig attachments -- and on a model whose
	-- Parent is still nil there is no DataModel for it to rebuild them in, so it can take them
	-- apart and leave them apart. Which is precisely the symptom: no Motor6Ds at all, on a rig
	-- that had them a moment earlier.
	-- ONLY WHEN THE JOINTS CAME WITH THE CLONE. If the block above had to rebuild them by
	-- hand, BuildRigFromAttachments would tear that work down and try to redo it from
	-- attachments that were evidently not sufficient the first time -- which is a good way to
	-- turn a working statue back into a pile of limbs.
	if humanoid and hasJoints then
		pcall(function()
			humanoid:BuildRigFromAttachments()
		end)
	end

	forgetRest(model)
	applyPose(model, poseFor[player] or "Stand")

	-- MOVED AFTER THE POSE, AS ONE RIGID PIECE. This ran before it, and the ordering was the
	-- whole problem: PivotTo put the figure on the plinth, and applyPose then rebuilt every
	-- part outward from its root -- so anything the root had drifted by while the clone was
	-- still unanchored got baked into the finished statue, and the statue got built around
	-- wherever that was. Which is the character's spawn, because that is where it was cloned.
	--
	-- Posing first and moving afterwards cannot go wrong that way round: by this line every
	-- part is anchored and correctly placed relative to every other, so PivotTo translates a
	-- finished object rather than seeding one.
	--
	-- Later pose changes do not repeat this, and do not need to: the root never moves again,
	-- and the forward kinematics are relative to it.
	model:PivotTo(CFrame.new(stand.Position + Vector3.new(0, stand.Size.Y / 2 + 3, 0))
		* CFrame.Angles(0, math.rad(180), 0))
end

-- THE POSED MESH, when the rigged statue cannot be made to work.
--
-- Five rounds went into posing a copy of the player's own avatar and it kept arriving with no
-- joints in it, which no amount of pose code can survive. Hub_Pose_Stand and its four siblings
-- are the same five poses baked in Blender as static meshes, and a mesh has no joints to lose.
--
-- The trade is real: a mannequin is not your avatar. So this is a FALLBACK, not a replacement
-- -- the rigged path still runs first, and the day it works the statues go back to being
-- personal with nothing further to do.
-- YOUR COLOUR, on the fallback figure.
--
-- A mannequin is not your avatar and never will be, but a mannequin in YOUR torso colour is
-- recognisably yours from across the room, and it is one web call. Cached per player because
-- GetHumanoidDescriptionFromUserId yields and can fail, and the statue is rebuilt on every
-- pose change.
local POSE_TINT = Color3.fromRGB(198, 194, 216)
local tintFor: { [Player]: Color3 } = {}

local function poseTint(player: Player): Color3
	local known = tintFor[player]
	if known then
		return known
	end
	-- STONE, NOT YOUR SKIN TONE. Tinting the figure with TorsoColor was meant to make it
	-- recognisably yours and instead produced a bright green man on a marble plinth: a body
	-- colour is chosen to sit under a face, hair and clothes, and on a bare untextured solid
	-- at statue scale it is just a loud colour with nothing to justify it.
	--
	-- A statue is stone. What makes it yours is the name on the plinth and the pose you set,
	-- and both of those already work.
	local ok, description = pcall(function()
		return Players:GetHumanoidDescriptionFromUserId(player.UserId)
	end)
	local colour = POSE_TINT
	if ok and description then
		-- A whisper of it, no more: 12 per cent is enough that two statues side by side are
		-- not identical, and not enough to stop either of them reading as marble.
		colour = POSE_TINT:Lerp(description.TorsoColor, 0.12)
	end
	tintFor[player] = colour
	return colour
end

local function attachPoseMesh(stand: BasePart, poseName: string, tint: Color3?): boolean
	local shown = propAt("Hub_Pose_" .. poseName,
		stand.Position + Vector3.new(0, stand.Size.Y / 2, 0), stand.Parent :: Folder,
		math.rad(180))
	if not shown then
		return false
	end
	-- The meshes are exported with their feet at the origin, so one offset places every pose;
	-- a Lean and a Ready are different heights and neither should sink into the plinth.
	shown.Name = "PoseFigure"
	shown.Material = Enum.Material.Marble
	shown.Color = tint or POSE_TINT
	shown.CFrame = CFrame.new(stand.Position + Vector3.new(0, stand.Size.Y / 2 + 2.6, 0))
		* CFrame.Angles(0, math.rad(180), 0)
	shown.Parent = stand
	return true
end

local function clearPoseMesh(stand: BasePart)
	local old = stand:FindFirstChild("PoseFigure")
	if old then
		old:Destroy()
	end
end

-- SAYS WHY IT DID NOTHING, because three rounds of fixing this have been guesses.
--
-- Every branch here fails silently in the original: no statue, no figure, no matching joints
-- -- all of them just return, and all of them look identical from inside the game. The prints
-- cost nothing and they turn "the poses still do not work" into a line naming which half is
-- broken, which is the difference between fixing it and guessing again.
function HubService.setPose(player: Player, poseName: string)
	poseFor[player] = poseName
	local folder = hubFolder
	local plinth = folder and folder:FindFirstChild("Statue_" .. player.UserId)
	-- Already on the baked meshes: swap which one is shown and skip the rigging path entirely.
	if plinth and plinth:IsA("BasePart") and plinth:FindFirstChild("PoseFigure") then
		clearPoseMesh(plinth)
		attachPoseMesh(plinth, poseName, poseTint(player))
		return
	end
	if not folder then
		warn("HubService.setPose: there is no hub folder, so there is no statue to pose.")
		return
	end
	local stand = folder:FindFirstChild("Statue_" .. player.UserId)
	if not stand then
		warn(("HubService.setPose: no Statue_%d in the hub. The plinth is built by "
			.. "Bootstrap on join, so either buildStatue threw or this ran before it."):format(
			player.UserId))
		return
	end
	local figure = stand:FindFirstChild("Figure")
	if not (figure and figure:IsA("Model")) then
		warn(("HubService.setPose: Statue_%d has no Figure. The avatar is loaded by a web "
			.. "call in buildStatue, which fails silently in Studio without API access."):format(
			player.UserId))
		return
	end

	local joints, moved, matched = applyPose(figure :: Model, poseName)

	-- REBUILDS RATHER THAN JUST COMPLAINING.
	--
	-- A jointless figure is recoverable -- the live character is right there and it is rigged
	-- -- so the useful response is to build a new one and try again, not to log the same
	-- warning seventy times while the player keeps standing on pads. Guarded so a genuinely
	-- unfixable figure cannot loop.
	-- ONCE, NOT EVERY TOUCH. The old guard cleared itself after 0.6 seconds, so a figure that
	-- genuinely could not be rigged rebuilt itself on every single pad you stood on and filled
	-- the log with the same pair of lines forever. A counter that only goes up cannot do that.
	-- ONE ATTEMPT, NOT TWO. Rebuilding twice was hedging: if a clone of a live rig comes back
	-- jointless once it will come back jointless again, and all the second try bought was
	-- another pass of warnings and a longer wait before the statue did anything at all.
	local tries = (stand:GetAttribute("RebuildTries") or 0) :: number

	-- OUT OF REBUILDS: show the baked mesh instead and stop complaining. A statue that poses
	-- is worth more than a statue that is definitely your avatar and definitely does not move,
	-- and the log has said its piece.
	if joints == 0 and tries >= 1 then
		local figureModel = figure :: Model
		figureModel:Destroy()
		clearPoseMesh(stand :: BasePart)
		if attachPoseMesh(stand :: BasePart, poseName, poseTint(player)) then
			-- Said out loud, once. Two rounds were spent unable to tell whether the fallback
			-- had engaged or the statue was simply broken in a new way.
			print(("HubService: %s's statue is using the baked %s mesh -- the cloned rig had "
				.. "no joints."):format(player.Name, poseName))
		else
			warnOnce("noposemesh", "HubService: the statue has no usable rig and Hub_Pose_"
				.. poseName .. " is not imported either, so it cannot be posed at all.")
		end
		return
	end

	if joints == 0 and tries < 1 then
		stand:SetAttribute("RebuildTries", tries + 1)
		warn("HubService.setPose: the figure had no joints, rebuilding it from the live "
			.. "character. If this repeats, the clone is failing rather than the rig.")
		attachFigure(player, stand :: BasePart)
		task.delay(0.6, function()
			local rebuilt = stand:FindFirstChild("Figure")
			if rebuilt and rebuilt:IsA("Model") then
				applyPose(rebuilt, poseFor[player] or "Stand")
			end
		end)
		return
	end

	if joints == 0 then
		-- Left in place deliberately. This is the message that finally identified the bug
		-- after three rounds of guessing at it, and if the rig ever fails to build again it
		-- is the one line that will say so.
		warn("HubService.setPose: the figure has no Motor6Ds at all, so it is not a rig. "
			.. "BuildRigFromAttachments should have constructed them in buildStatue.")
	elseif matched == 0 and poseName ~= "Stand" then
		-- TESTS WHAT IT SAYS. This asked whether anything MOVED, and warned about names
		-- when the answer was no.
		--
		-- Those are different questions. Standing on a pad re-applies the same pose many
		-- times and the later applications correctly turn nothing -- every limb is already
		-- pointing where it was asked to, so the rotation is the identity. Warning on that
		-- filled the log with "matched none of the figure's joints" about poses that had
		-- matched every one of them a frame earlier.
		--
		-- Guarding it with "unless we already recorded this pose" was not enough either,
		-- because Stand has no entries: applying Stand changes nothing and leaves the figure
		-- standing in Hero, so the next Hero touch found everything already correct while the
		-- record said Stand. Counting name matches directly sidesteps all of it.
		warn(("HubService.setPose: %s matched none of the figure's %d joints. The pose table "
			.. "is written for R15 names such as RightShoulder and Waist."):format(
			poseName, joints))
	else
		-- The joint names, once per statue. If a pose ever looks wrong again this is the line
		-- that settles whether the table is addressing the rig it actually has: an R15 rig
		-- says RightShoulder, an R6 rig says "Right Shoulder", and a pose written for one is
		-- silently a no-op on the other.
		if not stand:GetAttribute("Listed") then
			stand:SetAttribute("Listed", true)
			-- LISTS EVERY JOINT TYPE, not just Motor6D. This printed an empty list every time
			-- -- which was itself the answer and went unread: there are no Motor6Ds in this
			-- rig, so a Motor6D-only listing had nothing to say.
			--
			-- The names matter because the pose table is keyed by them. If Lean and Wave look
			-- alike it is because the entries that should distinguish them are addressing
			-- joints under different names, and this line is what shows that.
			local names = {}
			for _, item in ipairs((figure :: Model):GetDescendants()) do
				if item:IsA("Motor6D") or item:IsA("AnimationConstraint") or item:IsA("Bone") then
					table.insert(names, item.ClassName:sub(1, 4) .. ":" .. item.Name)
				end
			end
			table.sort(names)
			print("HubService: statue joints are " .. table.concat(names, ", "))
		end
		stand:SetAttribute("PosedAs", poseName)
		print(("HubService.setPose: %s -> %s, %d of %d joints moved."):format(
			player.Name, poseName, moved, joints))
	end
end

-- ===== coming back =====

-- Installed by Bootstrap, same reasoning as `runner`: the hub should not have to know how a
-- level is destroyed in order to send someone home.
local ender: (() -> ())? = nil

function HubService.setEnder(fn)
	ender = fn
end

-- THE HUB HAS TO LEAVE THE WORKSPACE WHILE A RUN IS ON.
--
-- It never did. The room, its parapet, its pads, its columns and its entire horizon -- sea,
-- islands and clouds -- stayed in the world for the whole of every run, sitting in the same
-- coordinate space as the level. That is why the lobby's ocean turned up in City Shore: it was
-- not a stray part, it was the whole lobby, still there.
--
-- And it is why the lobby went bare when the sea was pushed down to -420 to get it out of the
-- level's way. That was treating the symptom. With the room actually put away during a run,
-- its scenery can sit wherever looks best from the deck, because it is not sharing the world
-- with anything.
--
-- Reparenting rather than hiding. Transparency would leave every part still colliding, still
-- raycastable and still drawn; ServerStorage takes the lot out in one move and brings it back
-- intact, with no per-part state to save and restore and get wrong.
local hubHidden = false

function HubService.isHidden(): boolean
	return hubHidden
end

function HubService.setVisible(on: boolean)
	local folder = hubFolder
	if not folder then
		return
	end
	if on and hubHidden then
		folder.Parent = workspace
		hubHidden = false
	elseif not on and not hubHidden then
		folder.Parent = ServerStorage
		hubHidden = true
	end
end

function HubService.isInRun(player: Player): boolean
	return inRun[player] == true
end

function HubService.markInRun(players: { Player })
	for _, player in ipairs(players) do
		inRun[player] = true
	end
end

-- TEARS DOWN ON THE LAST PLAYER OUT, not on the first.
--
-- One level per server means one shared run, so destroying it when the first player finishes
-- would delete the floor from under everyone still on it. Tracking who is in the run is what
-- makes "last" answerable at all; a plain count would drift the moment somebody disconnected
-- mid-run and never be zero again.
function HubService.returnToHub(player: Player)
	inRun[player] = nil

	-- BEFORE the teleport, not after. spawnPosition is a constant so it does not need the
	-- room to exist, but the player is about to be put down on a floor -- and if the floor is
	-- still in ServerStorage when they arrive, they arrive in mid-air over the level.
	HubService.setVisible(true)

	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		hrp.CFrame = CFrame.new(HubService.spawnPosition())
	end

	if next(inRun) == nil and ender then
		local ok, err = pcall(ender :: any)
		if not ok then
			warn("HubService: tearing the run down failed: " .. tostring(err))
		end
	end
end

-- A DISCONNECT IS A PLAYER LEAVING THE RUN. Without this the run never reaches the "last
-- player out" case again, so the spiral stays in the world for the rest of the server's life
-- and the next run stacks on it.
Players.PlayerRemoving:Connect(function(player: Player)
	if inRun[player] then
		HubService.returnToHub(player)
	end
end)

-- ===== what the room reports =====

-- THE BOARD READS WHATEVER THE PADS CURRENTLY SAY, so walking between level pads changes it.
--
-- Injected rather than required, for the same reason the runner is: LeaderboardService talks
-- to DataStores, and the hub should be able to draw a room without that being reachable. A
-- server with DataStores unavailable still gets a lobby.
local boardReader: ((levelId: number, mode: string, count: number) -> any)? = nil
-- ONE BOARD, ONE VIEW PER PLAYER.
--
-- These were single values, so throwing the lever changed what EVERYONE was looking at. That
-- is wrong for the same reason the level pads are not shared: two people standing in the same
-- room want different things on screen, and neither should be able to move the other's.
--
-- Keyed by Player. The board part is one object in the world; what is drawn on it is not.
local boardLabels: { [Player]: Frame } = {}
local boardPart: BasePart? = nil

-- WHICH MODE THE BOARD IS SHOWING, and it is NOT the mode you are about to play.
--
-- Tying it to the selection was the obvious thing and it is the wrong one: the times you most
-- want to look at are usually the ones you are not about to set. A chill player checking what
-- hardcore looks like should not have to change what they are about to run in order to see
-- it, so the arrow moves this and nothing else.
local boardModes: { [Player]: string } = {}

local function otherMode(mode: string): string
	return if mode == "hardcore" then "chill" else "hardcore"
end

function HubService.setBoardReader(fn)
	boardReader = fn
end

-- YOUR OWN TIME, which the top eight will not show you once you are ninth.
--
-- A leaderboard that only lists the winners tells most of the room nothing about themselves.
-- The footer is the line that makes the board worth walking up to when you are not on it.
local bestReader: ((Player, number, string) -> number?)? = nil

function HubService.setBestReader(fn)
	bestReader = fn
end

-- Installed by Bootstrap, same reasoning as `runner` and `ender`: the hub owns what the mode
-- IS, and knows nothing about the RemoteEvent that tells a client to move its lever.
local boardNotifier: ((Player, string) -> ())? = nil

-- Installed by Bootstrap, same seam as the others: the hub owns what mode you have asked
-- for and knows nothing about the RemoteEvent that tells your HUD about it.

function HubService.setModeNotifier(fn)
	modeNotifier = fn
end

function HubService.setBoardNotifier(fn)
	boardNotifier = fn
end

function HubService.boardModeFor(player: Player): string
	return boardModes[player] or "chill"
end

-- Cosmetic, so every failure is a message ON the board rather than an error. A leaderboard
-- that cannot load must not stop anyone starting a run.
-- ===== the leaderboard, as a board rather than a wall of text =====
--
-- It was one TextLabel holding a string built with string.format: a heading, a blank line,
-- then eight rows padded with %-16s. That is a terminal printout hung on a wall. Monospace
-- padding is the only alignment it has, so the times only line up while every name is short,
-- and there is no way to make the first place look like first place.
--
-- Real rows instead: a header band, a ruled column head, and eight striped rows each holding
-- a rank badge, a name and a right-aligned time. It costs a few more instances and every one
-- of them is doing something the string could not.
local BOARD_ROWS = 8
local BOARD_FONT = Font.new("rbxasset://fonts/families/Nunito.json", Enum.FontWeight.Bold)
local BOARD_BODY = Font.new("rbxasset://fonts/families/Nunito.json", Enum.FontWeight.Medium)
-- Digits only line up in a face whose digits are all one width, which Nunito's are not.
local BOARD_TIME = Font.new("rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.Medium)

local MEDALS = {
	Color3.fromRGB(238, 199, 96),
	Color3.fromRGB(198, 202, 212),
	Color3.fromRGB(198, 142, 92),
}

local function clockText(seconds: number): string
	return ("%d:%05.2f"):format(math.floor(seconds / 60), seconds % 60)
end

local function refreshBoardFor(player: Player)
	local view = boardLabels[player]
	local mode = boardModes[player] or "chill"
	if not view or not view.Parent or not boardReader then
		return
	end

	local current = HubService.getRequest()
	local level = HubService.levelById(current.levelId)
	local hardcore = mode == "hardcore"
	local accent = if hardcore then Color3.fromRGB(232, 96, 88) else Color3.fromRGB(124, 196, 236)

	local title = view:FindFirstChild("Title") :: TextLabel?
	local chip = view:FindFirstChild("ModeChip") :: Frame?
	-- SEARCHED RECURSIVELY, and the shallow lookup was a real bug: Empty is parented to Rows,
	-- not to the panel, so this returned nil and refreshBoardFor bailed out at the guard below
	-- before touching anything. The board sat on its placeholder text -- heading still reading
	-- "LEADERBOARD", chip still reading CHILL with the lever thrown to hardcore -- and looked
	-- for all the world like a refresh that had run and found nothing.
	local empty = view:FindFirstChild("Empty", true) :: TextLabel?
	local rows = view:FindFirstChild("Rows")
	if not (title and chip and empty and rows) then
		return
	end

	title.Text = (level and level.name or "?"):upper()
	local chipText = chip:FindFirstChild("Label") :: TextLabel?
	if chipText then
		chipText.Text = if hardcore then "HARDCORE" else "CHILL"
	end
	chip.BackgroundColor3 = accent

	local rule = view:FindFirstChild("Rule")
	if rule and rule:IsA("Frame") then
		rule.BackgroundColor3 = accent
	end

	-- Cosmetic, so every failure is a message ON the board. A leaderboard that cannot load
	-- must not stop anyone starting a run.
	local ok, result = pcall(boardReader :: any, current.levelId, mode, BOARD_ROWS)
	local entries = if ok and typeof(result) == "table" then result else nil

	for index = 1, BOARD_ROWS do
		local row = rows:FindFirstChild("Row" .. index)
		if row and row:IsA("Frame") then
			local entry = entries and entries[index]
			row.Visible = entry ~= nil
			if entry then
				local badge = row:FindFirstChild("Badge") :: Frame?
				local rank = badge and badge:FindFirstChild("Rank") :: TextLabel?
				local name = row:FindFirstChild("Runner") :: TextLabel?
				local time = row:FindFirstChild("Time") :: TextLabel?
				if badge then
					badge.BackgroundColor3 = MEDALS[index] or Color3.fromRGB(72, 74, 92)
				end
				if rank then
					rank.Text = tostring(index)
					rank.TextColor3 = if index <= 3
						then Color3.fromRGB(28, 26, 34)
						else Color3.fromRGB(214, 218, 234)
				end
				if name then
					name.Text = tostring(entry.name or entry.key or "?")
				end
				if time then
					time.Text = clockText(tonumber(entry.timeSeconds or entry.value) or 0)
				end
			end
		end
	end

	local footName = view:FindFirstChild("YouName", true) :: TextLabel?
	local footTime = view:FindFirstChild("YouTime", true) :: TextLabel?
	if footName and footTime then
		footName.Text = player.DisplayName
		local best: number? = nil
		if bestReader then
			local gotOk, got = pcall(bestReader :: any, player, current.levelId, mode)
			best = if gotOk then got else nil
		end
		footTime.Text = if best then clockText(best) else "--:--"
		footTime.TextColor3 = if best
			then accent
			else Color3.fromRGB(120, 124, 146)
	end
	local footBadge = view:FindFirstChild("YouBadge", true)
	if footBadge and footBadge:IsA("Frame") then
		footBadge.BackgroundColor3 = accent
	end

	if not entries then
		empty.Visible = true
		empty.Text = "leaderboard unavailable"
	elseif #entries == 0 then
		empty.Visible = true
		empty.Text = if hardcore then "no hardcore times yet" else "no chill times yet"
	else
		empty.Visible = false
	end
end

-- Every caller in this file and in Bootstrap says "the selection changed, redraw the board",
-- and now that means redrawing several. Kept under the old name so those callers do not have
-- to know how many views exist.
function HubService.refreshBoard()
	for _, player in ipairs(Players:GetPlayers()) do
		refreshBoardFor(player)
	end
end

-- A VIEW OF THE BOARD THAT BELONGS TO ONE PLAYER.
--
-- A SurfaceGui parented into PlayerGui and pointed at the board part with Adornee renders on
-- that part for that player alone. It is still the server drawing it -- the lobby is defined
-- in one place and stays that way -- but the text is no longer shared state.
--
-- The lever indicator rides along for the same reason. The stem and head are one physical
-- object so their POSE cannot differ between players; the lit ring and the label in front of
-- the head can, and those carry the state now.
function HubService.attachBoard(player: Player)
	local board = boardPart
	if not board then
		return
	end
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return
	end

	local existing = playerGui:FindFirstChild("HubBoardView")
	if existing then
		existing:Destroy()
	end
	local surface = Instance.new("SurfaceGui")
	surface.Name = "HubBoardView"
	surface.Adornee = board
	surface.Face = Enum.NormalId.Left
	-- Taller canvas than before at the same board size, so the rows have room to be rows.
	surface.CanvasSize = Vector2.new(760, 480)
	surface.Parent = playerGui

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.Size = UDim2.new(1, 0, 1, 0)
	panel.BackgroundColor3 = Color3.fromRGB(22, 21, 30)
	panel.BorderSizePixel = 0
	panel.Parent = surface
	boardLabels[player] = panel

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 22)
	pad.PaddingBottom = UDim.new(0, 18)
	pad.PaddingLeft = UDim.new(0, 26)
	pad.PaddingRight = UDim.new(0, 26)
	pad.Parent = panel

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -160, 0, 44)
	title.BackgroundTransparency = 1
	title.FontFace = BOARD_FONT
	title.TextSize = 38
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Color3.fromRGB(240, 242, 250)
	title.Text = "LEADERBOARD"
	title.Parent = panel

	-- The mode as a coloured chip rather than a word in the heading. It is the one thing on
	-- this board that changes when you throw the lever, so it should be the one thing that
	-- looks like a control's state.
	local chip = Instance.new("Frame")
	chip.Name = "ModeChip"
	chip.AnchorPoint = Vector2.new(1, 0)
	chip.Position = UDim2.new(1, 0, 0, 6)
	chip.Size = UDim2.new(0, 148, 0, 34)
	chip.BorderSizePixel = 0
	chip.Parent = panel

	local chipRound = Instance.new("UICorner")
	chipRound.CornerRadius = UDim.new(0.5, 0)
	chipRound.Parent = chip

	local chipText = Instance.new("TextLabel")
	chipText.Name = "Label"
	chipText.Size = UDim2.new(1, 0, 1, 0)
	chipText.BackgroundTransparency = 1
	chipText.FontFace = BOARD_FONT
	chipText.TextSize = 19
	chipText.TextColor3 = Color3.fromRGB(24, 22, 30)
	chipText.Text = "CHILL"
	chipText.Parent = chip

	local rule = Instance.new("Frame")
	rule.Name = "Rule"
	rule.Position = UDim2.new(0, 0, 0, 54)
	rule.Size = UDim2.new(1, 0, 0, 2)
	rule.BorderSizePixel = 0
	rule.Parent = panel

	local rows = Instance.new("Frame")
	rows.Name = "Rows"
	rows.Position = UDim2.new(0, 0, 0, 68)
	rows.Size = UDim2.new(1, 0, 1, -122)
	rows.BackgroundTransparency = 1
	rows.Parent = panel

	local stack = Instance.new("UIListLayout")
	stack.Padding = UDim.new(0, 4)
	stack.SortOrder = Enum.SortOrder.LayoutOrder
	stack.Parent = rows

	for index = 1, BOARD_ROWS do
		local row = Instance.new("Frame")
		row.Name = "Row" .. index
		row.LayoutOrder = index
		row.Size = UDim2.new(1, 0, 0, 40)
		-- Alternating stripe, faint. Strong enough to follow a name across to its time,
		-- quiet enough not to become the thing you look at.
		row.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		row.BackgroundTransparency = if index % 2 == 0 then 0.97 else 0.93
		row.BorderSizePixel = 0
		row.Visible = false
		row.Parent = rows

		local rowRound = Instance.new("UICorner")
		rowRound.CornerRadius = UDim.new(0, 6)
		rowRound.Parent = row

		local badge = Instance.new("Frame")
		badge.Name = "Badge"
		badge.AnchorPoint = Vector2.new(0, 0.5)
		badge.Position = UDim2.new(0, 10, 0.5, 0)
		badge.Size = UDim2.new(0, 28, 0, 28)
		badge.BorderSizePixel = 0
		badge.Parent = row

		local badgeRound = Instance.new("UICorner")
		badgeRound.CornerRadius = UDim.new(0.5, 0)
		badgeRound.Parent = badge

		local rank = Instance.new("TextLabel")
		rank.Name = "Rank"
		rank.Size = UDim2.new(1, 0, 1, 0)
		rank.BackgroundTransparency = 1
		rank.FontFace = BOARD_FONT
		rank.TextSize = 17
		rank.Text = tostring(index)
		rank.Parent = badge

		local runner = Instance.new("TextLabel")
		runner.Name = "Runner"
		runner.Position = UDim2.new(0, 50, 0, 0)
		runner.Size = UDim2.new(1, -210, 1, 0)
		runner.BackgroundTransparency = 1
		runner.FontFace = BOARD_BODY
		runner.TextSize = 22
		runner.TextXAlignment = Enum.TextXAlignment.Left
		runner.TextTruncate = Enum.TextTruncate.AtEnd
		runner.TextColor3 = Color3.fromRGB(226, 230, 244)
		runner.Text = "-"
		runner.Parent = row

		local timeText = Instance.new("TextLabel")
		timeText.Name = "Time"
		timeText.AnchorPoint = Vector2.new(1, 0)
		timeText.Position = UDim2.new(1, -12, 0, 0)
		timeText.Size = UDim2.new(0, 140, 1, 0)
		timeText.BackgroundTransparency = 1
		timeText.FontFace = BOARD_TIME
		timeText.TextSize = 22
		timeText.TextXAlignment = Enum.TextXAlignment.Right
		timeText.TextColor3 = Color3.fromRGB(240, 242, 250)
		timeText.Text = "-"
		timeText.Parent = row
	end

	-- PINNED TO THE BOTTOM, outside the row stack, so it stays put whether the board has
	-- eight entries or none. Separated by its own rule: it is about you, not about the room.
	local footRule = Instance.new("Frame")
	footRule.Name = "FootRule"
	footRule.AnchorPoint = Vector2.new(0, 1)
	footRule.Position = UDim2.new(0, 0, 1, -46)
	footRule.Size = UDim2.new(1, 0, 0, 1)
	footRule.BackgroundColor3 = Color3.fromRGB(70, 72, 90)
	footRule.BorderSizePixel = 0
	footRule.Parent = panel

	local foot = Instance.new("Frame")
	foot.Name = "You"
	foot.AnchorPoint = Vector2.new(0, 1)
	foot.Position = UDim2.new(0, 0, 1, 0)
	foot.Size = UDim2.new(1, 0, 0, 40)
	foot.BackgroundTransparency = 1
	foot.Parent = panel

	local youBadge = Instance.new("Frame")
	youBadge.Name = "YouBadge"
	youBadge.AnchorPoint = Vector2.new(0, 0.5)
	youBadge.Position = UDim2.new(0, 10, 0.5, 0)
	youBadge.Size = UDim2.new(0, 6, 0, 26)
	youBadge.BorderSizePixel = 0
	youBadge.Parent = foot

	local youBadgeRound = Instance.new("UICorner")
	youBadgeRound.CornerRadius = UDim.new(0.5, 0)
	youBadgeRound.Parent = youBadge

	-- YOUR FACE ON YOUR OWN ROW.
	--
	-- The footer said YOUR BEST and then your name, which is information you already have --
	-- you know who you are. A headshot is what makes the row read as YOURS at a glance rather
	-- than as one more line of text, and it is the same thumbnail Roblox draws everywhere else.
	--
	-- Fetched asynchronously and dropped quietly on failure: GetUserThumbnailAsync is a web
	-- call, and a board that errors because an image did not load is a bad trade.
	local shot = Instance.new("ImageLabel")
	shot.Name = "Headshot"
	shot.AnchorPoint = Vector2.new(0, 0.5)
	shot.Position = UDim2.new(0, 24, 0.5, 0)
	shot.Size = UDim2.new(0, 34, 0, 34)
	shot.BackgroundColor3 = Color3.fromRGB(44, 46, 60)
	shot.BorderSizePixel = 0
	shot.Parent = foot

	local shotRound = Instance.new("UICorner")
	shotRound.CornerRadius = UDim.new(0.5, 0)
	shotRound.Parent = shot

	local shotEdge = Instance.new("UIStroke")
	shotEdge.Color = Color3.fromRGB(120, 196, 236)
	shotEdge.Thickness = 1.5
	shotEdge.Transparency = 0.3
	shotEdge.Parent = shot

	task.spawn(function()
		local gotOk, url = pcall(function()
			return Players:GetUserThumbnailAsync(player.UserId,
				Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
		end)
		if gotOk and url and shot.Parent then
			shot.Image = url
		end
	end)

	local youLabel = Instance.new("TextLabel")
	youLabel.Name = "YouTag"
	youLabel.Position = UDim2.new(0, 66, 0, 0)
	youLabel.Size = UDim2.new(0, 76, 1, 0)
	youLabel.BackgroundTransparency = 1
	youLabel.FontFace = BOARD_FONT
	youLabel.TextSize = 15
	youLabel.TextXAlignment = Enum.TextXAlignment.Left
	youLabel.TextColor3 = Color3.fromRGB(140, 144, 168)
	youLabel.Text = "YOUR BEST"
	youLabel.Parent = foot

	local youName = Instance.new("TextLabel")
	youName.Name = "YouName"
	youName.Position = UDim2.new(0, 148, 0, 0)
	youName.Size = UDim2.new(1, -308, 1, 0)
	youName.BackgroundTransparency = 1
	youName.FontFace = BOARD_BODY
	youName.TextSize = 21
	youName.TextXAlignment = Enum.TextXAlignment.Left
	youName.TextTruncate = Enum.TextTruncate.AtEnd
	youName.TextColor3 = Color3.fromRGB(214, 218, 234)
	youName.Text = "-"
	youName.Parent = foot

	local youTime = Instance.new("TextLabel")
	youTime.Name = "YouTime"
	youTime.AnchorPoint = Vector2.new(1, 0)
	youTime.Position = UDim2.new(1, -12, 0, 0)
	youTime.Size = UDim2.new(0, 140, 1, 0)
	youTime.BackgroundTransparency = 1
	youTime.FontFace = BOARD_TIME
	youTime.TextSize = 21
	youTime.TextXAlignment = Enum.TextXAlignment.Right
	youTime.Text = "--:--"
	youTime.Parent = foot

	local empty = Instance.new("TextLabel")
	empty.Name = "Empty"
	empty.Position = UDim2.new(0, 0, 0, 40)
	empty.Size = UDim2.new(1, 0, 0, 40)
	empty.BackgroundTransparency = 1
	empty.FontFace = BOARD_BODY
	empty.TextSize = 22
	empty.TextXAlignment = Enum.TextXAlignment.Left
	empty.TextColor3 = Color3.fromRGB(150, 154, 176)
	empty.Text = "no times yet"
	empty.Parent = rows

		boardModes[player] = boardModes[player] or "chill"
	refreshBoardFor(player)
	HubService.markBallot(player)
	tellState()
	if boardNotifier then
		boardNotifier(player, boardModes[player])
	end
end

function HubService.detachBoard(player: Player)
	boardLabels[player] = nil
	boardModes[player] = nil
end

-- THE ONE PLACE THE MODE CHANGES, whether it came from the lever in the room or from the
-- client's own copy of it. Debounced by the caller, not here.
function HubService.setBoardMode(player: Player, mode: string)
	if mode ~= "chill" and mode ~= "hardcore" then
		return
	end
	boardModes[player] = mode
	refreshBoardFor(player)
	if boardNotifier then
		boardNotifier(player, mode)
	end
end

function HubService.toggleBoardMode(player: Player)
	HubService.setBoardMode(player, otherMode(boardModes[player] or "chill"))
end

-- YOUR OWN RESULT, on a stand beside the pads.
--
-- Cosmetic too, so the DataStore reads are pcall'ed one at a time rather than as a batch: a
-- single level failing to load should cost that line, not the whole statue.
--
-- The layout deliberately stops at best times. Advancements go here when they get their own
-- spec, and guessing at them now would pick a progression model by accident.
function HubService.buildStatue(player: Player, bestTimeFor: (Player, number, string) -> number?)
	local folder = hubFolder
	if not folder then
		return
	end

	local previous = folder:FindFirstChild("Statue_" .. player.UserId)
	if previous then
		previous:Destroy()
	end

	local stand = Instance.new("Part")
	stand.Name = "Statue_" .. player.UserId
	stand.Anchored = true
	stand.CanCollide = true
	stand.Size = Vector3.new(6, 5, 6)
	stand.Material = Enum.Material.Marble
	stand.Color = Color3.fromRGB(74, 70, 86)
	stand.Position = HUB_ORIGIN + Vector3.new(-34, 3.5, 4)
	stand.Parent = folder

	-- SIZED IN STUDS, like every other sign in the room. The first version used offset
	-- pixels with TextScaled, so "no runs yet" stayed 300 pixels wide from across the lobby
	-- and covered the pads behind it.
	local gui = Instance.new("BillboardGui")
	gui.Name = "Record"
	gui.Size = UDim2.new(8, 0, 4, 0)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 7.5, 0)
	gui.MaxDistance = 70
	gui.Parent = stand

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 16
	label.TextColor3 = Color3.fromRGB(238, 240, 248)
	label.TextStrokeTransparency = 0.5
	label.Parent = gui

	attachFigure(player, stand)

	local lines = { player.DisplayName }
	for _, level in ipairs(HubService.padLevels()) do
		local ok, best = pcall(bestTimeFor, player, level.levelId, "chill")
		if ok and best then
			table.insert(lines,
				("%s  %d:%05.2f"):format(level.name, math.floor(best / 60), best % 60))
		end
	end
	if #lines == 1 then
		table.insert(lines, "no runs yet")
	end
	label.Text = table.concat(lines, "\n")
end

-- ===== building the room =====

-- ===== the room itself =====
--
-- A LOBBY IS A PLACE, and until now it was a grey slab with controls on it. Everything below
-- is scenery: it has no collisions worth speaking of, sets no state and is never read back.
--
-- The palette is taken from the backdrop it floats above -- the pale lilacs and warm sands of
-- the city, beach and waterpark horizon -- so the room reads as part of the same world rather
-- than as a menu that happens to be in it. The one warm colour in the set is used sparingly,
-- on the things you are meant to walk toward.
local PALETTE = {
	deck = Color3.fromRGB(64, 60, 78),
	inlay = Color3.fromRGB(86, 80, 106),
	trim = Color3.fromRGB(150, 140, 200),
	stone = Color3.fromRGB(206, 200, 222),
	warm = Color3.fromRGB(246, 206, 148),
	water = Color3.fromRGB(126, 186, 214),
	leaf = Color3.fromRGB(150, 196, 154),
}

local function decorPart(name: string, size: Vector3, position: Vector3, parent: Folder): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	-- Scenery does not collide. A lobby full of things to catch on is a lobby people get
	-- stuck in, and nothing here is meant to be stood on.
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Size = size
	part.Position = position
	part.Parent = parent
	return part
end

-- A column, its capital, and the light it carries. Repeated around the perimeter, which is
-- the cheapest way to make a flat plane read as a room with edges.
local function buildColumn(at: Vector3, parent: Folder)
	local shaft = decorPart("Column", Vector3.new(3.2, 22, 3.2), at + Vector3.new(0, 11, 0), parent)
	shaft.Material = Enum.Material.Marble
	shaft.Color = PALETTE.stone

	local base = decorPart("ColumnBase", Vector3.new(4.6, 1.4, 4.6), at + Vector3.new(0, 0.7, 0), parent)
	base.Material = Enum.Material.Slate
	base.Color = PALETTE.deck

	local capital = decorPart("ColumnCap", Vector3.new(4.6, 1.6, 4.6), at + Vector3.new(0, 22.6, 0), parent)
	capital.Material = Enum.Material.Slate
	capital.Color = PALETTE.deck

	-- A DISH THAT THROWS LIGHT UP AT THE CANOPY, not a glowing ball.
	--
	-- The ball was the shape you reach for when the light matters and the fixture does not,
	-- and in a room this bare the fixture is most of what you can actually see. Hub_LampBowl
	-- is a shallow uplighter on a stem; the bounce off the canopy is what stops the top of
	-- the room going black, which a downlight on a 22-stud column cannot do.
	local lamp = propAt("Hub_LampBowl", at + Vector3.new(0, 21.4, 0), parent, 2.2)
	if lamp then
		lamp.Material = Enum.Material.Metal
		lamp.Color = PALETTE.stone
	end

	local pool = decorPart("ColumnLampPool", Vector3.new(2.1, 0.35, 2.1),
		at + Vector3.new(0, 22.5, 0), parent)
	pool.Shape = Enum.PartType.Cylinder
	pool.CFrame = CFrame.new(at + Vector3.new(0, 22.5, 0)) * CFrame.Angles(0, 0, math.rad(90))
	pool.Size = Vector3.new(0.35, 2.1, 2.1)
	pool.Material = Enum.Material.Neon
	pool.Color = PALETTE.warm

	local light = Instance.new("PointLight")
	light.Color = PALETTE.warm
	light.Range = 24
	light.Brightness = 0.9
	-- Shadows off on every lamp here. Eight shadow-casting lights over a room this size is a
	-- real frame cost for an effect nobody looks at, and the room is lit for mood rather than
	-- for reading anything by.
	light.Shadows = false
	light.Parent = pool
end

-- A planter with a soft canopy. The shapes are deliberately round and slightly irregular:
-- this is a game about materials that give, and a lobby full of hard boxes says the opposite.
local function buildPlanter(at: Vector3, seed: number, parent: Folder)
	local rng = Random.new(seed)
	-- THESE HEIGHTS ARE MEASURED, NOT CHOSEN. The soil floated a clear half-stud above the
	-- rim on the first attempt because the offsets were guesses.
	--
	-- A MeshPart is centred on its own bounding box, so what matters is each mesh's extent
	-- either side of its centre, and those come straight out of Blender:
	--
	--     Hub_Planter   base 0.00  top 3.00   (centre 1.50)
	--     Hub_Soil      base -0.50 top 0.42   (centre -0.04, so 0.46 above centre)
	--     Hub_Plant     base 0.00  top 2.68   (centre 1.34)
	--
	-- From those: the bowl's base rests on the deck at +1.50. The soil's dome top wants to
	-- sit 0.25 under the rim at +2.75, so its centre is 2.75 - 0.46 = +2.29. The plant's base
	-- sinks 0.25 into the soil at +2.50, so its centre is 2.50 + 1.34 = +3.84.
	local pieces = {
		{ "Hub_Planter", Vector3.new(0, 1.5, 0), PALETTE.stone, Enum.Material.Marble },
		{ "Hub_Soil", Vector3.new(0, 2.29, 0), Color3.fromRGB(78, 64, 56), Enum.Material.Ground },
		{ "Hub_Plant", Vector3.new(0, 3.84, 0), PALETTE.leaf, Enum.Material.Grass },
	}

	local built = 0
	for _, piece in ipairs(pieces) do
		local template = propMesh(piece[1] :: string)
		if template then
			local prop = template:Clone()
			prop.Name = piece[1] :: string
			prop.Anchored = true
			prop.CanCollide = false
			prop.CanTouch = false
			prop.CanQuery = false
			-- FOLIAGE IS ONE LAYER OF GEOMETRY, so from behind it culls to nothing -- and half
			-- the leaves on a rosette are always facing away from you. DoubleSided renders both
			-- windings, which is the fix Roblox provides for exactly this and the reason the
			-- mesh does not carry mirrored faces of its own (bmesh refuses them: two windings
			-- over the same four verts are one face to it).
			if prop:IsA("MeshPart") and piece[1] == "Hub_Plant" then
				prop.DoubleSided = true
			end
			prop.Material = piece[4] :: Enum.Material
			prop.Color = (piece[3] :: Color3):Lerp(Color3.new(1, 1, 1), rng:NextNumber(0, 0.12))
			-- Turned a different way in each planter, so four copies of one mesh do not read
			-- as four copies of one mesh.
			prop.CFrame = CFrame.new(at + (piece[2] :: Vector3))
				* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
			prop.Parent = parent
			built += 1
		end
	end

	if built < #pieces then
		warnOnce("noprops", "HubService: the planter meshes are not imported, so the lobby has "
			.. "empty plinths where its plants go. Import Hub_Planter, Hub_Soil and Hub_Plant "
			.. "into ReplicatedStorage/Assets/TileMeshes.")
	end
end

-- THE POOL, with a coping the water sits BELOW.
--
-- The first one was a slab of glass laid on a slab of slate, and its top surface finished
-- 0.2 studs ABOVE the basin it was supposed to be inside: water standing proud of its own
-- container, which reads as a blue tile rather than as a pool. The rim is what makes water
-- water -- you need to see that it is held.
local function buildPool(centre: Vector3, parent: Folder)
	-- Heights, all measured from the deck surface at `centre`:
	--   0.00 - 0.80   the basin floor
	--   0.80 - 1.90   the water
	--   0.00 - 2.40   the coping around it, so the surface sits 0.5 under the rim
	local floorSlab = decorPart("PoolFloor", Vector3.new(22, 0.8, 9),
		centre + Vector3.new(0, 0.4, 0), parent)
	floorSlab.Material = Enum.Material.Slate
	floorSlab.Color = Color3.fromRGB(38, 44, 58)

	-- Four coping stones rather than a hollow box, so the corners are mitred by overlap and
	-- there is no seam to see into.
	for _, piece in ipairs({
		{ Vector3.new(26, 2.4, 2), Vector3.new(0, 1.2, -5.5) },
		{ Vector3.new(26, 2.4, 2), Vector3.new(0, 1.2, 5.5) },
		{ Vector3.new(2, 2.4, 13), Vector3.new(-12, 1.2, 0) },
		{ Vector3.new(2, 2.4, 13), Vector3.new(12, 1.2, 0) },
	}) do
		local stone = decorPart("PoolCoping", piece[1] :: Vector3,
			centre + (piece[2] :: Vector3), parent)
		stone.Material = Enum.Material.Marble
		stone.Color = PALETTE.stone
		-- The one piece of scenery here that IS solid: a rim you walk through is a rim that
		-- is not holding anything.
		stone.CanCollide = true
	end

	local water = decorPart("PoolWater", Vector3.new(22, 1.1, 9),
		centre + Vector3.new(0, 1.35, 0), parent)
	water.Material = Enum.Material.Glass
	water.Color = PALETTE.water
	water.Transparency = 0.42
	water.Reflectance = 0.45

	local glow = Instance.new("PointLight")
	glow.Color = PALETTE.water
	glow.Range = 18
	glow.Brightness = 0.5
	glow.Shadows = false
	glow.Parent = water

	-- WATER HAS TO MOVE, or it is a blue slab however reflective it is. Three things
	-- together, none of them enough alone: a caustic pattern that drifts, a surface that
	-- rises and falls, and mist at the rim.
	--
	-- The texture is the important one. A flat colour reads as painted, and a slowly sliding
	-- pattern of light is what the eye actually uses to decide something is liquid.
	local caustics = Instance.new("Texture")
	caustics.Name = "Caustics"
	caustics.Face = Enum.NormalId.Top
	caustics.Texture = "rbxasset://textures/water/normal_1.dds"
	caustics.StudsPerTileU = 9
	caustics.StudsPerTileV = 9
	caustics.Transparency = 0.55
	caustics.Parent = water

	local mist = Instance.new("ParticleEmitter")
	mist.Name = "PoolMist"
	mist.Texture = "rbxasset://textures/particles/smoke_main.dds"
	mist.Color = ColorSequence.new(PALETTE.water)
	mist.Size = NumberSequence.new(2.4)
	mist.Transparency = NumberSequence.new(0.93)
	mist.Lifetime = NumberRange.new(2.4, 4.4)
	mist.Rate = 3
	mist.Speed = NumberRange.new(0.3, 0.9)
	mist.SpreadAngle = Vector2.new(30, 30)
	mist.Acceleration = Vector3.new(0, 0.6, 0)
	mist.Parent = water

	-- DRIVEN ON THE SERVER because everything in this room is: the hub is built once,
	-- server-side, and a client script purely to slide a texture would be a second place the
	-- lobby is defined. Heartbeat rather than a wait loop, so the drift is frame-rate
	-- independent and stops cleanly if the pool is ever destroyed.
	local restY = water.Position.Y
	RunService.Heartbeat:Connect(function()
		if not water.Parent then
			return
		end
		local now = time()
		caustics.OffsetStudsU = now * 0.35
		caustics.OffsetStudsV = math.sin(now * 0.21) * 1.4
		water.Position = Vector3.new(water.Position.X, restY + math.sin(now * 0.7) * 0.06,
			water.Position.Z)
	end)
end

-- A JET IN THE MIDDLE OF THE POOL, because still water reads as a floor tile however well it
-- is shaded. Something has to disturb it.
--
-- Particles rather than parts: a column of thin parts is visibly a column of thin parts, and
-- water is the one material that never holds an edge.
local function buildFountain(centre: Vector3, parent: Folder)
	-- MODELLED, because a fountain is its RIMS.
	--
	-- This was a cylinder with two flat discs stacked on it, and from standing height a flat
	-- disc is a line: what you saw was a glowing white lozenge hovering over the pool with a
	-- wisp of particles above it. Hub_Fountain is two shallow bowls on a baluster stem, and
	-- the tiers are what make the silhouette read as a fountain from across the room.
	--
	-- Heights are measured from the mesh, whose base sits at -0.10 and finial at 5.62, so its
	-- bounding centre is 2.76 above the base. The pool floor is 0.80 above `centre`, giving a
	-- centre offset of 0.80 + 2.86.
	local body = propAt("Hub_Fountain", centre + Vector3.new(0, 3.66, 0), parent)
	if body then
		body.Material = Enum.Material.Marble
		body.Color = PALETTE.stone
	end

	-- WATER IS PARTICLES, not parts. A column of thin parts is visibly a column of thin
	-- parts, and water is the one material that never holds an edge.
	--
	-- Three emitters doing three different jobs, which is what a real fountain looks like: a
	-- jet from the finial, a ring of spills over the upper rim, and a wider ring off the
	-- lower rim into the basin.
	local function emitter(at: Vector3, name: string, rate: number, speed: NumberRange,
		size: number, spread: number, up: boolean): ParticleEmitter
		local anchor = decorPart(name, Vector3.new(0.8, 0.8, 0.8), at, parent)
		anchor.Transparency = 1

		local jet = Instance.new("ParticleEmitter")
		jet.Name = name
		jet.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		jet.Color = ColorSequence.new(PALETTE.water)
		jet.LightEmission = 0.5
		jet.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, size),
			NumberSequenceKeypoint.new(1, size * 0.15),
		})
		jet.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.3),
			NumberSequenceKeypoint.new(1, 1),
		})
		jet.Lifetime = NumberRange.new(0.7, 1.3)
		jet.Rate = rate
		jet.Speed = speed
		jet.SpreadAngle = Vector2.new(spread, spread)
		-- Thrown and pulled back down, so water ARCS. No acceleration gives a beam.
		jet.Acceleration = Vector3.new(0, if up then -26 else -34, 0)
		jet.EmissionDirection = Enum.NormalId.Top
		jet.Parent = anchor
		return jet
	end

	emitter(centre + Vector3.new(0, 6.4, 0), "FountainJet", 70, NumberRange.new(9, 11),
		0.5, 7, true)

	-- The rims: six spills over the upper bowl at radius 2.1, eight off the lower at 3.3.
	-- Offset half a step from each other so the two rings do not line up into columns.
	for index = 1, 6 do
		local angle = (index / 6) * math.pi * 2
		emitter(centre + Vector3.new(math.cos(angle) * 2.1, 5.5, math.sin(angle) * 2.1),
			"FountainUpperSpill", 14, NumberRange.new(1.4, 2.2), 0.3, 4, false)
	end
	for index = 1, 8 do
		local angle = (index / 8) * math.pi * 2 + math.pi / 8
		emitter(centre + Vector3.new(math.cos(angle) * 3.3, 3.1, math.sin(angle) * 3.3),
			"FountainLowerSpill", 12, NumberRange.new(1.0, 1.7), 0.26, 4, false)
	end

	local splash = Instance.new("PointLight")
	splash.Color = PALETTE.water
	splash.Range = 14
	splash.Brightness = 0.7
	splash.Shadows = false
	splash.Parent = parent:FindFirstChild("FountainJet") or parent
end

local function buildBench(at: Vector3, facing: number, parent: Folder)
	local turn = CFrame.new(at) * CFrame.Angles(0, facing, 0)

	local seat = Instance.new("Seat")
	seat.Name = "BenchSeat"
	seat.Anchored = true
	seat.CanCollide = true
	seat.Size = Vector3.new(9, 0.5, 2.6)
	seat.Material = Enum.Material.WoodPlanks
	seat.Color = Color3.fromRGB(158, 128, 100)
	seat.Parent = parent
	-- TURNED TO FACE OUT OF THE BENCH, not into its own backrest.
	--
	-- A Seat sits the character along its Front face, which is local -Z, and the back rail is
	-- also at local -Z. So everyone sat down facing the plank behind them. The extra half turn
	-- points the sitter away from the rail, which is the only arrangement a bench has.
	seat.CFrame = turn * CFrame.new(0, 2.2, 0) * CFrame.Angles(0, math.pi, 0)

	local backRail = decorPart("BenchBack", Vector3.new(9, 2.2, 0.4), at, parent)
	backRail.Material = Enum.Material.WoodPlanks
	backRail.Color = Color3.fromRGB(146, 118, 92)
	backRail.CFrame = turn * CFrame.new(0, 3.4, -1.1)

	for _, side in ipairs({ -3.4, 3.4 }) do
		local leg = decorPart("BenchLeg", Vector3.new(0.7, 2.2, 2.2), at, parent)
		leg.Material = Enum.Material.Metal
		leg.Color = PALETTE.deck
		leg.CFrame = turn * CFrame.new(side, 1.1, 0)
	end

	-- HOLD E, WITH THE RING THAT FILLS.
	--
	-- A Seat already seats anyone who walks into it, which is the problem: you sit down by
	-- accident every time you cross the terrace. A ProximityPrompt makes sitting deliberate,
	-- and its hold behaviour draws the filling circle for free -- it is the same control
	-- every other game uses for this, so nobody has to be taught it.
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "SitPrompt"
	prompt.ActionText = "Sit"
	prompt.ObjectText = "Bench"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	-- Long enough that the ring is visibly a ring rather than a flicker, short enough that
	-- it never feels like being made to wait.
	prompt.HoldDuration = 0.6
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = false
	prompt.Parent = seat

	prompt.Triggered:Connect(function(player: Player)
		local character = player.Character
		local humanoid = character and character:FindFirstChildWhichIsA("Humanoid")
		if humanoid and humanoid:IsA("Humanoid") and seat.Occupant == nil then
			seat:Sit(humanoid)
		end
	end)
end

-- THE DOOR THAT SHOULD NOT BE THERE.
--
-- Backrooms Level 0 is the one worth borrowing from, and specifically for its palette:
-- mono-yellow wallpaper, damp beige carpet, buzzing fluorescent ceiling panels. Nothing else
-- in this lobby is warm -- it is built out of cool lilac and pale marble -- so a doorway
-- leaking that yellow is not decoration, it is a WRONGNESS, and it reads as a place at once
-- without a sign explaining anything.
--
-- A frame with nothing in it rather than a door, because the point of Level 0 is that nothing
-- is stopping you, which is worse than a lock.
--
-- === WHY THE ROOM BENDS ===
--
-- The first version was a six-stud box: one look through the frame and you had seen all of
-- it, so it read as a yellow cupboard. The entire effect of the reference is that space keeps
-- going and you cannot see how far -- so the corridor now runs back fourteen studs and TURNS,
-- with the second stretch lit by its own tube out of sight around the corner. What you get
-- through the doorway is a lit wall and light spilling from somewhere you cannot see, which
-- is the whole trick and costs four extra slabs.
--
-- Deliberately inert. The fall-out counter that opens it does not exist yet, and building the
-- teaser first is the right order: it seeds the idea now and costs nothing to wire up later.
local function buildBackDoor(at: Vector3, parent: Folder)
	local WALL = Color3.fromRGB(206, 186, 96)
	local WALL_LOW = Color3.fromRGB(184, 162, 78)
	local CARPET = Color3.fromRGB(126, 112, 74)
	local TRIM = Color3.fromRGB(150, 132, 74)
	-- FACING OUTWARD, so the corridor hangs off the deck rather than lying across it.
	--
	-- At minus a quarter turn the whole fourteen-stud run extended INTO the lobby, which puts
	-- a large yellow box in the middle of a room built out of lilac and marble. Turned the
	-- other way it leaves through the parapet: from inside you see a door in the corner with
	-- light coming out of it, and the corridor itself is somewhere that is not the lobby --
	-- which is the correct relationship for a door to somewhere else to have.
	local facing = math.pi / 2
	local turn = CFrame.new(at) * CFrame.Angles(0, facing, 0)

	-- A LANDING IN FRONT OF IT. The deck's own floor stops at the inlay, and the frame stands
	-- past that with its corridor over the edge -- so without this you could see the doorway
	-- and not stand in it, which was the complaint.
	local landing = decorPart("BackDoorStep", Vector3.new(7, 1, 6), at + Vector3.new(1, -0.4, 0),
		parent)
	landing.Material = Enum.Material.Slate
	landing.Color = PALETTE.deck
	landing.CanCollide = true

	local frame = propAt("Hub_Doorframe", at, parent, facing)
	if frame then
		frame.Material = Enum.Material.Wood
		frame.Color = Color3.fromRGB(96, 84, 58)
	end

	-- One helper, because every surface in here is a coloured slab and the only things that
	-- differ are where it goes and what it is called.
	local function slab(name: string, size: Vector3, offset: CFrame, colour: Color3,
		material: Enum.Material): BasePart
		local part = decorPart(name, size, at, parent)
		part.CFrame = turn * offset
		part.Color = colour
		part.Material = material
		return part
	end

	-- THE FIRST STRETCH, straight back from the door.
	slab("BackWall", Vector3.new(0.4, 6.6, 14), CFrame.new(-2.3, 3.3, 6), WALL, Enum.Material.Fabric)
	slab("BackWall", Vector3.new(0.4, 6.6, 8), CFrame.new(2.3, 3.3, 3), WALL, Enum.Material.Fabric)
	slab("BackCeiling", Vector3.new(4.6, 0.3, 14), CFrame.new(0, 6.5, 6), WALL, Enum.Material.Fabric)
	slab("BackFloor", Vector3.new(4.6, 0.2, 14), CFrame.new(0, 0.1, 6), CARPET, Enum.Material.Fabric)

	-- THE TURN. The corridor carries on to the right, out of sight from the doorway, and only
	-- its far wall is visible through the opening -- lit, with no visible source.
	slab("BackWall", Vector3.new(0.4, 6.6, 9), CFrame.new(-2.3, 3.3, 13.2), WALL, Enum.Material.Fabric)
	slab("BackWall", Vector3.new(9, 6.6, 0.4), CFrame.new(2.3, 3.3, 12.8), WALL, Enum.Material.Fabric)
	slab("BackWall", Vector3.new(9, 6.6, 0.4), CFrame.new(2.3, 3.3, 7.2), WALL, Enum.Material.Fabric)
	slab("BackCeiling", Vector3.new(9, 0.3, 6), CFrame.new(6.4, 6.5, 10), WALL, Enum.Material.Fabric)
	slab("BackFloor", Vector3.new(9, 0.2, 6), CFrame.new(6.4, 0.1, 10), CARPET, Enum.Material.Fabric)
	slab("BackWall", Vector3.new(0.4, 6.6, 6), CFrame.new(10.6, 3.3, 10), WALL, Enum.Material.Fabric)

	-- SKIRTING AND A DADO RAIL. Level 0 is not a bare box -- it is an office corridor that has
	-- been left alone, and the two horizontal lines are what say "building" rather than
	-- "corridor asset". The lower band is also darker, which reads as damp rising up the wall.
	for _, run in ipairs({
		{ Vector3.new(0.5, 1.1, 14), CFrame.new(-2.28, 0.55, 6) },
		{ Vector3.new(0.5, 1.1, 8), CFrame.new(2.28, 0.55, 3) },
		{ Vector3.new(0.5, 0.22, 14), CFrame.new(-2.26, 2.5, 6) },
		{ Vector3.new(0.5, 0.22, 8), CFrame.new(2.26, 2.5, 3) },
	}) do
		local band = slab("BackTrim", run[1] :: Vector3, run[2] :: CFrame, TRIM,
			Enum.Material.WoodPlanks)
		band.Color = if (run[1] :: Vector3).Y > 0.5 then WALL_LOW else TRIM
	end

	-- TWO TUBES. The near one is seen; the far one is round the corner and only its light
	-- reaches the doorway, which is what makes the corridor feel like it continues.
	local function tube(offset: CFrame, size: Vector3, range: number): (BasePart, PointLight)
		local fitting = slab("BackRoomLight", size, offset, Color3.fromRGB(248, 240, 190),
			Enum.Material.Neon)
		local buzz = Instance.new("PointLight")
		buzz.Color = Color3.fromRGB(250, 236, 160)
		buzz.Range = range
		buzz.Brightness = 1.6
		buzz.Shadows = false
		buzz.Parent = fitting
		return fitting, buzz
	end

	local nearTube, nearBuzz = tube(CFrame.new(0, 6.28, 3), Vector3.new(2.6, 0.16, 3.4), 18)
	local farTube, farBuzz = tube(CFrame.new(6.4, 6.28, 10), Vector3.new(3.4, 0.16, 2.6), 20)

	-- IRREGULAR ON PURPOSE, and the two tubes are deliberately not in step. A sine wave reads
	-- as a pulse, which is a machine working; a failing tube is mostly ON with sudden
	-- unpredictable dropouts. Two of them failing independently is what makes a corridor sound
	-- and look inhabited by nothing.
	local function flicker(fitting: BasePart, buzz: PointLight, steady: number)
		task.spawn(function()
			while fitting.Parent do
				task.wait(math.random(12, 90) / 10)
				for _ = 1, math.random(1, 4) do
					fitting.Transparency = 0.75
					buzz.Brightness = 0.15
					task.wait(math.random(3, 9) / 100)
					fitting.Transparency = 0
					buzz.Brightness = steady
					task.wait(math.random(4, 14) / 100)
				end
			end
		end)
	end

	flicker(nearTube, nearBuzz, 1.6)
	flicker(farTube, farBuzz, 1.9)
end

local function buildSurroundings(folder: Folder)
	-- THE DECK, in three layers rather than one slab. A border, an inlay and a lighter field
	-- give the floor a middle and an edge, which is most of what makes a space feel composed
	-- rather than sized.
	local inlay = decorPart("DeckInlay", Vector3.new(FLOOR_SIZE.X - 10, 0.35, FLOOR_SIZE.Z - 10),
		HUB_ORIGIN + Vector3.new(0, 1.15, 0), folder)
	inlay.Material = Enum.Material.Marble
	inlay.Color = PALETTE.inlay

	local trim = decorPart("DeckTrim", Vector3.new(FLOOR_SIZE.X - 4, 0.5, FLOOR_SIZE.Z - 4),
		HUB_ORIGIN + Vector3.new(0, 1.05, 0), folder)
	trim.Material = Enum.Material.Neon
	trim.Color = PALETTE.trim
	trim.Transparency = 0.72

	-- COLUMNS at the corners and the long-side midpoints. Not a full colonnade: the room has
	-- to stay open enough to see the level below it, and eight is enough to say "edge".
	-- ON THE PURPLE LINE, which is the trim ring the deck draws around itself.
	--
	-- The trim runs from FLOOR_SIZE minus 4 inward to the inlay at FLOOR_SIZE minus 10, so
	-- the visible band is 3 studs wide and its centre is 2.5 studs in from the deck edge.
	-- The columns were at minus 5, which put them just inside the band with a sliver of
	-- purple showing past them -- close enough to look like a mistake rather than a choice.
	local halfX, halfZ = FLOOR_SIZE.X / 2 - 2.5, FLOOR_SIZE.Z / 2 - 2.5
	local columns = {
		Vector3.new(-halfX, 0, -halfZ), Vector3.new(halfX, 0, -halfZ),
		Vector3.new(-halfX, 0, halfZ), Vector3.new(halfX, 0, halfZ),
		Vector3.new(-halfX, 0, 0), Vector3.new(halfX, 0, 0),
		Vector3.new(-halfX / 2, 0, halfZ), Vector3.new(halfX / 2, 0, halfZ),
		Vector3.new(-halfX / 2, 0, -halfZ), Vector3.new(halfX / 2, 0, -halfZ),
	}
	for _, offset in ipairs(columns) do
		buildColumn(HUB_ORIGIN + offset + Vector3.new(0, 1, 0), folder)
	end

	-- A CANOPY RING rather than a roof. A roof would cut out the sky, and the sky is the one
	-- thing every level in this game is played against.
	-- A CONTINUOUS OVAL RESTING ON THE COLUMNS, not a ring floating in the middle of the room.
	--
	-- The canopy was 16 straight beams on a 34 by 30 ellipse while the columns stand on a 51.5
	-- by 44.5 one. So it hung over the centre of the floor, touching nothing, and the gaps
	-- between its segments made it read as a dashed line rather than a structure.
	--
	-- Matched to the column ring and segmented finely enough that consecutive beams OVERLAP at
	-- their ends: the chord of a 28-segment ellipse is shorter than the beam drawn along it, so
	-- the ring closes into one continuous band with no seams to count.
	-- AN ELLIPSE CANNOT TOUCH ALL EIGHT COLUMNS, and no convex ring can.
	--
	-- Four of them stand at the corners, at the maximum of BOTH axes at once, and four at the
	-- axis midpoints. Any convex curve through the midpoints passes inside the corners by
	-- definition -- so the previous ellipse met four columns and floated past the other four,
	-- which is exactly what the screenshot shows.
	--
	-- So the ring is not a curve fitted to the columns; it is a curve DRAWN THROUGH them. The
	-- radius is interpolated from one column to the next with a cosine, which reaches each one
	-- exactly and bows gently inward between them. That bow is the wiggle: it is what a ring
	-- has to do to touch eight points that are not on any circle, and it reads as deliberate
	-- scalloping rather than as a shape that missed.
	local ringStops = {}
	for _, offset in ipairs(columns) do
		local angle = math.atan2(offset.Z, offset.X)
		table.insert(ringStops, { angle = angle, reach = Vector2.new(offset.X, offset.Z).Magnitude })
	end
	table.sort(ringStops, function(a, b)
		return a.angle < b.angle
	end)

	local function ringReach(theta: number): number
		if #ringStops == 0 then
			return FLOOR_SIZE.X / 2 - 2.5
		end
		-- NORMALISED INTO THE STOPS' OWN RANGE, at both ends.
		--
		-- This only wrapped upward, so an angle PAST the last stop -- which the final segment
		-- of the loop always is, since it asks for (n+1)/n of a turn -- fell through the search
		-- below and got handed ringStops[1].reach: a radius belonging to the opposite side of
		-- the room. That produced one straight chord cutting across a corner, disconnected
		-- from the columns either side of it.
		local base = ringStops[1].angle
		theta = base + ((theta - base) % (math.pi * 2))
		for i = 1, #ringStops do
			local here = ringStops[i]
			local nextStop = ringStops[if i == #ringStops then 1 else i + 1]
			local nextAngle = if i == #ringStops
				then nextStop.angle + math.pi * 2
				else nextStop.angle
			if theta >= here.angle and theta <= nextAngle then
				local span = nextAngle - here.angle
				local t = if span > 0 then (theta - here.angle) / span else 0
				-- Cosine rather than linear: linear gives a polygon with a visible kink at
				-- every column, and the whole point is that this reads as one flowing band.
				local eased = (1 - math.cos(t * math.pi)) / 2
				local blended = here.reach + (nextStop.reach - here.reach) * eased
				-- The inward bow, deepest halfway between two columns and zero at each.
				return blended - math.sin(t * math.pi) * 5.5
			end
		end
		return ringStops[1].reach
	end

	local RING_SEGMENTS = 64
	for index = 1, RING_SEGMENTS do
		local angle = (index / RING_SEGMENTS) * math.pi * 2
		local nextAngle = ((index + 1) / RING_SEGMENTS) * math.pi * 2
		local here = Vector3.new(math.cos(angle) * ringReach(angle), 0,
			math.sin(angle) * ringReach(angle))
		local there = Vector3.new(math.cos(nextAngle) * ringReach(nextAngle), 0,
			math.sin(nextAngle) * ringReach(nextAngle))
		-- 1.3 rather than exactly the chord: the overlap is what removes the seam.
		local span = (there - here).Magnitude * 1.3

		local beam = decorPart("CanopyBeam", Vector3.new(2.4, 1.1, span),
			HUB_ORIGIN + (here + there) / 2 + Vector3.new(0, 23.4, 0), folder)
		beam.Material = Enum.Material.Metal
		beam.Color = PALETTE.deck
		beam.CFrame = CFrame.lookAt(beam.Position, beam.Position + (there - here).Unit)

		-- Every seventh of twenty-eight rather than every fourth of sixteen, so the ring
		-- carries four lanterns as it did before rather than seven.
		-- No lanterns on the outer band any more: they hang from the inner ring below, which
		-- is where they can be seen from under the canopy rather than from beyond its edge.
		if false then
			-- A LANTERN IN TWO PARTS: a dark hexagonal frame and the lit drum inside it.
			-- One MeshPart carries one material, and a lantern needs two -- matte metal
			-- for the ribs and neon for the panels. A single glowing box has neither.
			local hang = beam.Position - Vector3.new(0, 3.4, 0)
			local frame = propAt("Hub_Lantern", hang, folder, angle)
			if frame then
				frame.Material = Enum.Material.Metal
				frame.Color = Color3.fromRGB(40, 38, 48)
			end
			local glass = propAt("Hub_LanternGlass", hang, folder, angle)
			if glass then
				glass.Material = Enum.Material.Neon
				glass.Color = PALETTE.warm
				glass.Transparency = 0.25
			end

			local chain = decorPart("LanternChain", Vector3.new(0.16, 1.2, 0.16),
				beam.Position - Vector3.new(0, 1.0, 0), folder)
			chain.Material = Enum.Material.Metal
			chain.Color = Color3.fromRGB(40, 38, 48)

			local glow = Instance.new("PointLight")
			glow.Color = PALETTE.warm
			glow.Range = 16
			glow.Brightness = 0.8
			glow.Shadows = false
			glow.Parent = (glass or chain)
		end
	end

	-- THE POOL MOVED IN from z = -40 to z = -36. Its coping now reaches 8 studs further out
	-- than the old basin did, and at -40 the far edge would have crossed the deck's trim ring
	-- at -46 -- the same overhang the pose keys were pulled back from.
	-- SEPARATED FROM THE LEVEL ROW. The pads end at z = -24 and the coping used to begin at
	-- -29.5: five studs, which from inside the room read as the pool being part of the level
	-- selection rather than a separate corner of it.
	local poolCentre = HUB_ORIGIN + Vector3.new(0, 1, -36)
	-- A SKY AND SOME AIR, which is what the horizon was still missing.
	--
	-- The sea and the islands gave the room something to be above; they did not give it
	-- weather. Atmosphere is what turns a row of distant objects into distance -- without it
	-- an island 400 studs away is drawn at exactly the same contrast as the parapet in front
	-- of you, and the eye reads them as the same distance no matter how the geometry is laid
	-- out.
	--
	-- Set on Lighting, so it applies to the levels too. That is deliberate: the levels are the
	-- same sky seen from lower down, and two different atmospheres would make the lobby feel
	-- like a different game rather than a different altitude.
	local lighting = game:GetService("Lighting")
	local haze = lighting:FindFirstChildOfClass("Atmosphere")
	if not haze then
		local made = Instance.new("Atmosphere")
		made.Parent = lighting
		haze = made
	end
	if haze then
		haze.Density = 0.32
		haze.Offset = 0.1
		-- Haze warm, glare low. A cold haze over a lilac room turns everything grey; a warm
		-- one keeps the pale marble reading as marble at distance.
		haze.Color = Color3.fromRGB(226, 216, 232)
		haze.Decay = Color3.fromRGB(146, 140, 178)
		haze.Glare = 0.15
		haze.Haze = 1.6
	end

	local sky = lighting:FindFirstChildOfClass("Sky")
	if not sky then
		-- No SkyboxUp assets are set: Roblox draws its own gradient, and the point here is the
		-- SUN and MOON, which give the sky a direction. A skybox without one reads as a dome
		-- painted around you rather than as an outdoors.
		local made = Instance.new("Sky")
		made.SunAngularSize = 14
		made.MoonAngularSize = 9
		made.StarCount = 1400
		made.Parent = lighting
	end

	-- COLOSSAL BLADES DRIVEN INTO THE SEA, not a skyline.
	--
	-- The far distance was a ring of rectangular pillars, which is the same mistake the lamps
	-- and the fountain each made first time round: a shape that says something is there
	-- without saying what. A box at 400 studs can only read as a building, and this room is
	-- not a city -- so the horizon was quietly turning the lobby into somewhere it is not.
	--
	-- Point DOWN, hilt above the water. Sunk the other way up the guard and grip would be
	-- underwater and every bit of modelled detail with them; this way the crossguard breaks
	-- the outline where the eye lands, and the blade below it is the part that goes on for a
	-- long time. Tilted, at four different scales and depths, because a row of identical
	-- verticals is a fence.
	-- THE LEVIATHAN, and it is placed here rather than left as two files to drop in by hand.
	--
	-- The meshes were built two rounds ago and nothing put them in the world, so the lobby has
	-- had a horizon of blades and no creature on it. A model that exists only in the meshes
	-- folder is not a feature.
	--
	-- ONE, and off to one side rather than centred. A monster directly ahead of the spawn is a
	-- set piece the room is arranged around; one you have to turn your head to notice is
	-- something you caught sight of, which is the whole feeling being aimed at. Far enough out
	-- that the blades read as nearer than it -- so it is the biggest thing on the horizon and
	-- also the furthest, which is the arithmetic that makes it enormous.
	--
	-- Head and body are separate MeshParts modelled in one coordinate space, so both go down
	-- at the same point with the same rotation and line up with no adjustment.
	local LEVIATHAN_ANGLE = 2.25
	local LEVIATHAN_FAR = 620
	local LEVIATHAN_Y = -190
	local LEVIATHAN_SCALE = 1.35
	-- HOW FAR TO LIFT IT, as a fraction of the part's own height.
	--
	-- The creature is modelled around z = 0 being the surface: the back breaks it, the neck
	-- rises out of it, the belly hangs under it. But Roblox places the part by its BOUNDING-BOX
	-- centre, and that box is dominated by the reared neck and the crest -- which are entirely
	-- above water. So its centre sits 0.30 of the box's height above the modelled surface, and
	-- dropping that centre at sea level sank the whole animal by exactly that much. What was
	-- showing was the little that happened to poke back out.
	--
	-- 0.3008 puts the modelled waterline exactly on the sea. Measured by
	-- gen_hub_leviathan.py, and a fraction rather than a stud count so it survives the export
	-- scale, the import fitting and the Size multiplier above.
	local LEVIATHAN_WATERLINE = 0.3008
	-- AND A LITTLE MORE ON TOP, which is the part that is taste rather than arithmetic. At the
	-- modelled waterline the back is awash and the humps read as three low ridges. Another
	-- twelfth of the height lifts the shoulder and the coils clear enough to see the body they
	-- belong to, without turning it into something beached.
	local LEVIATHAN_LIFT = 0.085
	-- WHICH WAY IT FACES, as its own number rather than folded into the position angle. A
	-- quarter turn further round than before: side-on to the lobby, so what you see is the
	-- reared neck and the whole length behind it. Nose-on shows a head and nothing that says
	-- how long the thing is.
	local LEVIATHAN_FACING = LEVIATHAN_ANGLE + math.pi
	-- HOW FAR THE HEAD SITS FROM THE BODY, and this is the line that was missing.
	--
	-- Both meshes are modelled in one coordinate space, and I took that to mean dropping them
	-- at the same point would line them up. It does not. Roblox positions a MeshPart by its
	-- BOUNDING-BOX CENTRE, so two parts at one CFrame have their centres stacked and every
	-- bit of the distance between them in the original scene is thrown away -- which put the
	-- head in the middle of its own body instead of on the end of the neck.
	--
	-- The head's centre is 129 studs along and 44 up from the body's, because it is at the
	-- top of a reared neck. Printed by gen_hub_leviathan.py, already in Roblox axes.
	-- NO OFFSET AT ALL ANY MORE, and that is the fix rather than a simplification.
	--
	-- Roblox positions a MeshPart by its bounding-box CENTRE, so two meshes modelled in one
	-- scene do not line up when dropped at one point: their centres stack and the distance
	-- between them is discarded. I tried to measure that distance and add it back twice --
	-- first in studs, which assumed a Blender unit arrives as a stud, then as a fraction of
	-- the body, which fixed the scale but still leaned on my reading of how the exporter
	-- maps Blender's axes onto Roblox's. The head came out on the wrong END of the animal,
	-- which is exactly what a sign error in that mapping looks like.
	--
	-- Both attempts were answering the wrong question. gen_hub_leviathan.py now gives the
	-- two meshes the SAME bounding box, by putting an invisible speck at each corner of the
	-- box that encloses both. One box means one centre, and one centre means the same CFrame
	-- puts them exactly where they were modelled -- with no offset to compute, no axis
	-- convention to get right, and nothing left for me to get the sign of wrong.

	local leviathanAt = HUB_ORIGIN + Vector3.new(
		math.cos(LEVIATHAN_ANGLE) * LEVIATHAN_FAR,
		LEVIATHAN_Y,
		math.sin(LEVIATHAN_ANGLE) * LEVIATHAN_FAR)
	-- The shared frame both pieces are placed in. Built after the first piece exists, because
	-- the lift is a fraction of that piece's height and there is no honest way to know the
	-- height before the part is there to measure.
	local leviathanFrame = CFrame.new(leviathanAt) * CFrame.Angles(0, LEVIATHAN_FACING, 0)
	for _, piece in ipairs({ "Hub_Leviathan_Body", "Hub_Leviathan_Head" }) do
		local part = propAt(piece, leviathanAt, folder, LEVIATHAN_FACING)
		if part then
			-- Same size, same frame, both pieces. They share a bounding box, so this is all
			-- the assembly there is.
			part.Size = part.Size * LEVIATHAN_SCALE
			-- Lifted out of the water by a fraction of its own height. Both pieces get the
			-- identical treatment because they are the identical box, so raising them cannot
			-- pull them apart.
			part.CFrame = leviathanFrame + Vector3.new(0,
				(LEVIATHAN_WATERLINE + LEVIATHAN_LIFT) * part.Size.Y, 0)
			-- Dark and wet, and barely reflective. A shine on something this size reads as
			-- plastic; what sells wet hide at distance is that it is DARKER than the water
			-- behind it, not shinier.
			part.Color = Color3.fromRGB(38, 48, 52)
			part.Material = Enum.Material.Slate
			part.Reflectance = 0.05
			-- Never in the way. It is scenery three field-lengths out, and a player who
			-- somehow reached it should pass through rather than stand on its back.
			part.CastShadow = false
			-- THE FRILL IS A FILM. Skin stretched between two spines has no thickness -- at
			-- this size it should not have any -- but a zero-thickness sheet only renders
			-- from the side its faces point at, so half the crest would disappear depending
			-- on where you stood in the lobby. This is the property that exists for that, and
			-- it costs no geometry.
			part.DoubleSided = true
		end
	end

	local BLADE_Y = -190
	for index = 1, 7 do
		local angle = (index / 7) * math.pi * 2 + 0.7
		local far = 300 + (index % 4) * 70
		local scale = 2.4 + (index % 3) * 1.1
		-- LESS SUNK. At up to 64 studs under, the shortest blades showed barely more than a
		-- point and read as debris. Half that leaves the crossguard clear of the water on
		-- every one of them, which is the part worth seeing.
		local sunk = (index % 4) * 8

		local blade = propAt("Hub_SunkenBlade",
			HUB_ORIGIN + Vector3.new(math.cos(angle) * far, BLADE_Y + 46 * scale - sunk,
				math.sin(angle) * far), folder)
		if blade then
			-- REAL PBR, WITHOUT AN UPLOAD.
			--
			-- A SurfaceAppearance needs four uploaded texture maps and I cannot upload
			-- anything, so a custom material is not on the table. What IS on the table is the
			-- fact that Roblox's built-in materials already ship full PBR sets -- CorrodedMetal
			-- has a real normal, roughness and metalness map, and it responds to light exactly
			-- the way an authored material would.
			--
			-- It also happens to be the right material: these have been standing in seawater
			-- for a very long time.
			-- CorrodedMetal ONLY UNTIL THE AUTHORED MAPS ARE IN. A built-in material tiles at
			-- a fixed world scale and knows nothing about where this blade's fuller runs or
			-- which end has been underwater -- gen_blade_pbr.py writes four maps that do.
			--
			-- Once a SurfaceAppearance exists on the mesh it owns the surface completely, and
			-- leaving a material set underneath it is just a value that no longer applies.
			-- SmoothPlastic is the neutral thing to leave there.
			local authored = blade:FindFirstChildWhichIsA("SurfaceAppearance")
			blade.Material = if authored
				then Enum.Material.SmoothPlastic
				else Enum.Material.CorrodedMetal
			-- Varied per blade so the ring does not read as one object repeated: the pitted
			-- ones catch almost nothing, the cleaner ones throw the sky back.
			blade.Reflectance = 0.08 + (index % 3) * 0.13
			blade.Color = Color3.fromRGB(108, 114, 132):Lerp(Color3.fromRGB(176, 178, 198),
				(index % 3) / 3)
			blade.CastShadow = false
			-- Turned point-down and leaned over. The lean is small: a sword at 40 degrees
			-- reads as dropped, and one at 8 reads as driven.
			blade.CFrame = CFrame.new(blade.Position)
				* CFrame.Angles(0, angle + 1.2, 0)
				* CFrame.Angles(math.rad(180 + (index % 5) * 3 - 6), 0, 0)
			blade.Size = blade.Size * scale
		end
	end

	-- AN OCEAN UNDER THE WHOLE THING, which is what the islands were missing.
	--
	-- Distant rock at the same altitude as the deck reads as debris floating in a void; the
	-- same rock standing IN something reads as an archipelago, and the room reads as being
	-- above it. One enormous plane a long way down does that for one part.
	--
	-- Far enough below that its surface never fights the level spiral for attention, and matte
	-- rather than reflective: a mirror at this scale shows the underside of the deck.
	-- THE SAME SEA THE CITY SHORE BACKDROP USES, borrowed rather than rebuilt.
	--
	-- A flat slab was the first attempt and it read as painted lino, for the reason the
	-- backdrop's own comments already spell out: a flat plane returns one lighting answer
	-- across its whole surface however it is coloured, and it is the VARIATION IN NORMALS that
	-- the eye reads as a moving liquid. Sea_Tile is a displaced mesh that already solves that,
	-- and it is already imported for City Shore, so this costs no new asset.
	--
	-- Changed for altitude: colder and darker than the beach version, because this is open
	-- water seen from 200 studs up rather than a shore, and lower reflectance so it does not
	-- mirror the underside of the deck.
	local seaTile = backdropProp("Sea_Tile")
	-- MINUS 420, NOT MINUS 170, and the difference is the whole bug.
	--
	-- HUB_ORIGIN is at y = 200 and the spiral climbs from 0, so a sea 170 studs below the deck
	-- sat at y = 30 -- which is not under the level, it is INSIDE it. Running City Shore meant
	-- wading through the lobby's ocean at chest height.
	--
	-- The level's kill plane is around -16, so anything below that is out of play. 420 puts
	-- the water at -220: clear of the spiral, still plainly visible from the deck, and read
	-- from inside a run as the ocean the whole thing is suspended over.
	-- BACK UP TO -190 now that the room is put away during a run. This was pushed down to
	-- -420 to stop it appearing inside the level, which worked and made the view from the deck
	-- a flat blue smear a long way off. The hiding is the real fix; this is the number that
	-- actually looks right from the parapet.
	local SEA_Y, SEA_SPAN, SEA_STEP = -190, 3, 620
	for gx = -SEA_SPAN, SEA_SPAN do
		for gz = -SEA_SPAN, SEA_SPAN do
			local at = HUB_ORIGIN + Vector3.new(gx * SEA_STEP, SEA_Y, gz * SEA_STEP)
			local water: BasePart
			if seaTile then
				local shaped = seaTile:Clone()
				shaped.Name = "FarSea"
				shaped.Anchored = true
				shaped.CanCollide = false
				shaped.CanTouch = false
				shaped.CanQuery = false
				-- Every tile the same MeshId, so Roblox instances them: one mesh, 49 draws.
				-- Turned in quarter steps so the displacement does not tile visibly.
				shaped.CFrame = CFrame.new(at)
					* CFrame.Angles(0, math.rad(90 * ((gx + gz) % 4)), 0)
				shaped.Parent = folder
				water = shaped
			else
				water = decorPart("FarSea", Vector3.new(SEA_STEP, 6, SEA_STEP), at, folder)
			end
			water.Material = Enum.Material.Glass
			water.Color = Color3.fromRGB(38, 82, 122)
			water.Transparency = 0.1
			water.Reflectance = 0.34
			water.CastShadow = false
		end
	end

	-- A PLACE FOR THE ROOM TO BE.
	--
	-- The lobby is a slab 200 studs up with nothing round it, so from inside it the world ends
	-- at the parapet. A ring of distant rock, well outside the rail and well below the deck,
	-- gives the eye something past the edge and turns "floating in a void" into "on top of
	-- something".
	--
	-- Deliberately far out and unlit: this is a horizon, not scenery to be examined, and
	-- anything detailed at that distance is polygons nobody looks at.
	for index = 1, 9 do
		local angle = (index / 9) * math.pi * 2 + 0.4
		local far = 190 + (index % 3) * 55
		-- Dropped to meet the water at -170 rather than hanging in mid-air: an island with its
		-- feet in the sea is an island, and one without is a rock someone forgot to delete.
		-- Follows the water down, so the islands still stand in it.
		local drop = 172 + (index % 4) * 14
		local island = decorPart("FarIsland_" .. index,
			Vector3.new(70 + (index % 3) * 26, 70, 58 + (index % 2) * 30),
			HUB_ORIGIN + Vector3.new(math.cos(angle) * far, -drop, math.sin(angle) * far), folder)
		island.Material = Enum.Material.Rock
		island.Color = Color3.fromRGB(96, 92, 122):Lerp(Color3.fromRGB(170, 166, 200),
			(index % 3) / 3)
		island.CFrame = CFrame.new(island.Position) * CFrame.Angles(0, angle, 0)

		local cap = decorPart("FarIslandTop_" .. index,
			island.Size * Vector3.new(0.86, 0.12, 0.86),
			island.Position + Vector3.new(0, island.Size.Y / 2, 0), folder)
		cap.Material = Enum.Material.Grass
		cap.Color = Color3.fromRGB(126, 158, 138)
		cap.CFrame = CFrame.new(cap.Position) * CFrame.Angles(0, angle, 0)
	end

	-- Cloud banks at deck height, so the room reads as being AT altitude rather than merely
	-- drawn high up. Wide, thin and very transparent: a cloud you can make out the edges of
	-- is a slab.
	for index = 1, 7 do
		local angle = (index / 7) * math.pi * 2
		local far = 150 + (index % 3) * 40
		-- The clouds go down too, for the same reason: at 12 studs below the deck they were
		-- level with the top of the spiral and a run flew through them.
		local cloud = decorPart("FarCloud_" .. index,
			Vector3.new(96 + (index % 3) * 30, 5, 54),
			HUB_ORIGIN + Vector3.new(math.cos(angle) * far, -34 - (index % 3) * 26,
				math.sin(angle) * far), folder)
		cloud.Material = Enum.Material.SmoothPlastic
		cloud.Color = Color3.fromRGB(226, 224, 244)
		cloud.Transparency = 0.62
		cloud.CFrame = CFrame.new(cloud.Position) * CFrame.Angles(0, angle, 0)
	end

	-- ON THE DECK, not past the rail. At x = 50 the frame sat on the inlay's edge with the
	-- corridor hanging beyond the parapet, so the door was something you could see and not
	-- reach -- which is the opposite of the point. At 42 you can walk up to it and stand in
	-- the opening; the corridor still runs out past the edge, which is where a corridor to
	-- somewhere that is not here belongs.
	-- WHOLLY INSIDE THE DECK. The corridor is fourteen studs plus a nine-stud turn, and every
	-- placement so far has run it out past the parapet -- so the door was reachable and the
	-- room behind it was hanging in the sky, which looks like a mistake rather than a mystery.
	--
	-- The strip between the level pads and the east rail is empty, 20 studs wide and 20 deep.
	-- The whole thing fits in it with room to walk round, and running the corridor toward the
	-- start pad keeps it in the corner of your eye rather than in front of you.
	-- THERE ARE FOUR LEVEL PADS, NOT THREE. padLevels appends the Sandbox to the three
	-- shippable levels, so the centred row sits at x = -36, -12, 12 and 36 -- and 36 is
	-- exactly where this door was, which is why the corridor grew out of a lit portal.
	--
	-- The free ground is the block from x = 26 to 48 between the pads and the east rail: the
	-- benches stop at 21, the pool coping at 15, and the pads at 40. The corridor runs east
	-- along it and turns south into the corner, entirely inside the deck.
	-- MOVED AGAIN, and further this time. At (30, -30) the corridor cleared the level row by
	-- 3.7 studs, which is not an overlap but is close enough to read as one from inside the
	-- room -- and it was still being reported as touching the pads. Three and a half studs is
	-- the sort of margin that is correct on paper and wrong in play.
	--
	-- At (28, -32) the gap is 5.5 studs to the nearest pad and 3.5 to the nearest bench, with
	-- the turn finishing at z = -42.6 against an inlay edge at -43.
	-- NORTH-EAST CORNER, because the south-east one is not big enough and never was.
	--
	-- Between the level row at z = -20 and the inlay edge at -43 there are 19 studs, and the
	-- corridor plus its turn needs about 25 in one axis. Every placement down there was a
	-- compromise between clipping a pad and hanging off the deck.
	--
	-- The block between the planter at (46, 22) and the north edge is 26 by 14 and empty. The
	-- corridor runs east along it and turns south into the gap behind the start pad.
	-- FOUR WAVING ARMS AND A LANTERN RING.
	--
	-- The outer band touches the columns, which is what makes it structural -- but a single
	-- band over a room this size is a hoop, not a canopy. Four arms running inward to a small
	-- ring at the centre turn it into a frame with a middle, and the middle is where the light
	-- belongs: hung over the floor people stand on rather than out at the perimeter.
	--
	-- The arms WAVE rather than run straight, on the same reasoning as the outer band's
	-- scalloping: a straight spoke reads as a strut holding something up, and nothing here is
	-- holding anything up. A curve reads as decoration, which is what it is.
	local INNER_RING = 15
	for arm = 1, 4 do
		local armAngle = (arm / 4) * math.pi * 2 + math.pi / 4
		local outer = ringReach(armAngle)
		local pieces = 16
		for step = 0, pieces - 1 do
			local t0, t1 = step / pieces, (step + 1) / pieces
			local function armPoint(t: number): Vector3
				local radius = outer + (INNER_RING - outer) * t
				-- Two full waves along the arm, fading to nothing at both ends so it meets the
				-- outer band and the inner ring cleanly.
				local swing = math.sin(t * math.pi * 4) * 0.13 * math.sin(t * math.pi)
				local angle = armAngle + swing
				return Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
			end
			local here, there = armPoint(t0), armPoint(t1)
			local span = (there - here).Magnitude * 1.35
			local rib = decorPart("CanopyArm", Vector3.new(1.8, 0.9, span),
				HUB_ORIGIN + (here + there) / 2 + Vector3.new(0, 23.4, 0), folder)
			rib.Material = Enum.Material.Metal
			rib.Color = PALETTE.deck
			rib.CFrame = CFrame.lookAt(rib.Position, rib.Position + (there - here).Unit)
		end
	end

	for index = 1, 20 do
		local angle = (index / 20) * math.pi * 2
		local nextAngle = ((index + 1) / 20) * math.pi * 2
		local here = Vector3.new(math.cos(angle) * INNER_RING, 0, math.sin(angle) * INNER_RING)
		local there = Vector3.new(math.cos(nextAngle) * INNER_RING, 0,
			math.sin(nextAngle) * INNER_RING)
		local hoop = decorPart("CanopyHub", Vector3.new(2.0, 1.0, (there - here).Magnitude * 1.4),
			HUB_ORIGIN + (here + there) / 2 + Vector3.new(0, 23.4, 0), folder)
		hoop.Material = Enum.Material.Metal
		hoop.Color = PALETTE.deck
		hoop.CFrame = CFrame.lookAt(hoop.Position, hoop.Position + (there - here).Unit)

		-- Five lanterns around the inner ring, evenly spaced.
		if index % 4 == 0 then
			local hang = HUB_ORIGIN + here + Vector3.new(0, 19.6, 0)
			local frame = propAt("Hub_Lantern", hang, folder, angle)
			if frame then
				frame.Material = Enum.Material.Metal
				frame.Color = Color3.fromRGB(40, 38, 48)
			end
			local glass = propAt("Hub_LanternGlass", hang, folder, angle)
			if glass then
				glass.Material = Enum.Material.Neon
				glass.Color = PALETTE.warm
				glass.Transparency = 0.25
			end

			local chain = decorPart("LanternChain", Vector3.new(0.16, 3.2, 0.16),
				HUB_ORIGIN + here + Vector3.new(0, 22.0, 0), folder)
			chain.Material = Enum.Material.Metal
			chain.Color = Color3.fromRGB(40, 38, 48)

			local glow = Instance.new("PointLight")
			glow.Color = PALETTE.warm
			glow.Range = 20
			glow.Brightness = 0.9
			glow.Shadows = false
			glow.Parent = (glass or chain)
		end
	end

	buildBackDoor(HUB_ORIGIN + Vector3.new(24, 1, 34), folder)
	buildPool(poolCentre, folder)
	buildFountain(poolCentre, folder)

	-- FOUR BENCHES FACING THE WATER, two down each side.
	--
	-- They used to be scattered: two near the pool and two at x = +/-38 beside the pads,
	-- which put them nowhere in particular and one of them inside the pose row. Furniture
	-- pointed at something reads as a place to sit; furniture in the middle of a floor reads
	-- as an obstacle.
	--
	-- Backs to the outside, so the row frames the pool rather than blocking the way round it.
	-- INSIDE THE INLAY. A bench turned side-on runs 9 studs along Z, so a pair at z = -29 and
	-- -41 put the far one's end at -45.5, over the deck's inlay edge at -43 -- the same
	-- overhang the pose keys and the pool were both pulled back from.
	--
	-- One down each side of the water and two facing it across the near end, which also gives
	-- the terrace a front rather than two parallel rows.
	-- TWO SEATING AREAS, not four benches crammed round one pool.
	--
	-- The near pair sat at z = -27, between a level pad whose edge is at -24 and a pool coping
	-- that begins at -29.5. Five and a half studs is not a gap you can put a bench in and have
	-- it look placed rather than wedged.
	--
	-- So: one down each side of the water, where there is real room, and a pair flanking the
	-- start pad, which is where people stand around waiting for a vote to resolve anyway.
	for _, seat in ipairs({
		{ Vector3.new(-20, 0, -36), math.pi / 2 },
		{ Vector3.new(20, 0, -36), -math.pi / 2 },
		{ Vector3.new(-16, 0, 24), 0 },
		{ Vector3.new(16, 0, 24), 0 },
	}) do
		buildBench(HUB_ORIGIN + (seat[1] :: Vector3) + Vector3.new(0, 1, 0),
			seat[2] :: number, folder)
	end

	-- A LIT PATH FROM THE SPAWN TO THE START PAD, which is the one piece of scenery here that
	-- is also instruction. You arrive facing a room full of things to press; a line of light
	-- running to the pad that begins a run answers "what do I do" without a sign saying it.
	--
	-- TWO ROWS FLANKING THE OPTION PADS, at x = +/-6.5, rather than one row up the middle.
	-- The middle is where the length keys are: a strip straight down it would lie under them
	-- and read as clutter. Flanking them makes the same line and turns the option row into a
	-- walkway with the keys along it.
	-- CHEVRONS, NOT STRIPES.
	--
	-- The first version was a row of plain rectangles, and a rectangle does not point. They
	-- read as unexplained yellow blocks on the floor -- which is exactly what they were, since
	-- the only thing carrying the meaning was a brightness gradient nobody could see.
	--
	-- An arrowhead points. Two bars meeting at an angle is the sign every floor in the world
	-- uses for "that way", and it needs no key.
	-- BUILT FROM ITS TWO ENDPOINTS, because mirroring an angle does not mirror a bar.
	--
	-- The first version rotated each bar by `side * 34 degrees`. That is right for the bar on
	-- the right and wrong for the one on the left: negating the yaw sweeps local +X the other
	-- way round, so the left bar pointed forward-and-right instead of back-and-left and the
	-- pair came out as a broken zigzag rather than an arrowhead.
	--
	-- Given a tip and a tail, CFrame.lookAt cannot get the direction wrong, and the length
	-- falls out of the two points instead of being a number that has to agree with the angle.
	local SPREAD, DEPTH = 3.4, 2.4
	for index = 1, 5 do
		-- ONE SHAPE WITH A NOTCH IN IT, which is what makes an arrow an arrow.
		--
		-- Two bars set at an angle is what this was, and it is what it looked like: two bars.
		-- The inside corner is the whole signal, and no arrangement of rectangles has one --
		-- a rectangle has no concave vertex to give. Hub_Chevron is a single solid outline.
		--
		-- The pair of bars stays below as a fallback for an unimported mesh, because an arrow
		-- made of sticks still points better than no arrow at all.
		local chevron = propAt("Hub_Chevron",
			Vector3.new(HUB_ORIGIN.X, HUB_ORIGIN.Y + 1.3, HUB_ORIGIN.Z + 12 + index * 2.4),
			folder, 0)
		if chevron then
			chevron.Material = Enum.Material.Neon
			chevron.Color = PALETTE.warm
			chevron.Transparency = 0.78 - index * 0.08
			continue
		end
		-- BACKED AWAY FROM THE PAD. The last chevron used to finish at z = 33, which is inside
		-- the start pad itself, so the arrow appeared to be pointing at its own tip. The row
		-- now runs 14 to 24 and stops a clear 4 studs short of the pad's edge, which is what
		-- makes it read as pointing AT something rather than as decoration on it.
		local tip = Vector3.new(HUB_ORIGIN.X, HUB_ORIGIN.Y + 1.32, HUB_ORIGIN.Z + 12 + index * 2.4)
		for _, side in ipairs({ -1, 1 }) do
			local tail = tip + Vector3.new(side * SPREAD, 0, -DEPTH)
			local bar = decorPart("PathChevronFallback",
				Vector3.new(1.1, 0.12, (tip - tail).Magnitude), (tip + tail) / 2, folder)
			bar.Material = Enum.Material.Neon
			bar.Color = PALETTE.warm
			bar.CFrame = CFrame.lookAt((tip + tail) / 2, tip)
			bar.Transparency = 0.82 - index * 0.07
		end
	end

	-- MOTES. A room this size with nothing moving in it looks like a screenshot, and dust in
	-- slow drifting light is the cheapest way to say the air is real. Rate is deliberately
	-- tiny: this should be noticed only if you stop and look.
	local air = decorPart("AirVolume", Vector3.new(4, 4, 4), HUB_ORIGIN + Vector3.new(0, 12, 0), folder)
	air.Transparency = 1

	local motes = Instance.new("ParticleEmitter")
	motes.Name = "Motes"
	motes.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	motes.Color = ColorSequence.new(PALETTE.warm)
	motes.LightEmission = 0.8
	motes.Size = NumberSequence.new(0.35)
	motes.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.3, 0.72),
		NumberSequenceKeypoint.new(1, 1),
	})
	motes.Lifetime = NumberRange.new(9, 15)
	motes.Rate = 14
	motes.Speed = NumberRange.new(0.4, 1.4)
	motes.SpreadAngle = Vector2.new(180, 180)
	motes.Acceleration = Vector3.new(0.3, 0.15, 0)
	-- A box the size of the room, so they fill it rather than streaming from a point.
	motes.Shape = Enum.ParticleEmitterShape.Box
	motes.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	motes.EmissionDirection = Enum.NormalId.Top
	motes.Parent = air
	air.Size = Vector3.new(FLOOR_SIZE.X - 20, 20, FLOOR_SIZE.Z - 20)

	for _, offset in ipairs({
		Vector3.new(-46, 0, 22), Vector3.new(46, 0, 22),
		Vector3.new(-46, 0, -10), Vector3.new(46, 0, -10),
	}) do
		buildPlanter(HUB_ORIGIN + offset + Vector3.new(0, 1, 0), 2026 + offset.X + offset.Z, folder)
	end
end

-- Idempotent: calling it twice returns the room that already exists rather than a second
-- one, because Bootstrap runs it at server start and nothing should be able to stack it.
function HubService.build(): { spawnPosition: Vector3 }
	-- The stashed room counts as existing. This looked only in the workspace, and the room now
	-- spends every run in ServerStorage -- so a build() during a run would have found nothing
	-- and quietly assembled a SECOND lobby on top of the level.
	if hubFolder then
		return { spawnPosition = HubService.spawnPosition() }
	end
	local existing = workspace:FindFirstChild("Hub")
	if existing and existing:IsA("Folder") then
		hubFolder = existing
		return { spawnPosition = HubService.spawnPosition() }
	end

	local folder = Instance.new("Folder")
	folder.Name = "Hub"
	folder.Parent = workspace
	hubFolder = folder

	local floor = Instance.new("Part")
	floor.Name = "HubFloor"
	floor.Anchored = true
	floor.CanCollide = true
	floor.Size = FLOOR_SIZE
	floor.Position = HUB_ORIGIN
	floor.Material = Enum.Material.SmoothPlastic
	floor.Color = Color3.fromRGB(58, 54, 68)
	floor.Parent = folder

	-- A PARAPET, because catching a fall is a worse answer than not falling.
	--
	-- The lobby is a slab in the sky and every edge of it was a cliff. The Heartbeat catch
	-- below is a safety net and stays, but a net you hit regularly is a design problem: you
	-- are meant to be reading signs and standing on keys here, not watching your footing.
	--
	-- Waist height rather than a wall, so the room still reads as open and the view of the
	-- level below is not lost.
	local rail = {
		{ Vector3.new(FLOOR_SIZE.X, 5, 1.4), Vector3.new(0, 3.5, FLOOR_SIZE.Z / 2) },
		{ Vector3.new(FLOOR_SIZE.X, 5, 1.4), Vector3.new(0, 3.5, -FLOOR_SIZE.Z / 2) },
		{ Vector3.new(1.4, 5, FLOOR_SIZE.Z), Vector3.new(FLOOR_SIZE.X / 2, 3.5, 0) },
		{ Vector3.new(1.4, 5, FLOOR_SIZE.Z), Vector3.new(-FLOOR_SIZE.X / 2, 3.5, 0) },
	}
	for index, piece in ipairs(rail) do
		local wall = Instance.new("Part")
		wall.Name = "HubRail_" .. index
		wall.Anchored = true
		wall.CanCollide = true
		wall.CanTouch = false
		wall.Size = piece[1]
		wall.Position = HUB_ORIGIN + piece[2]
		wall.Material = Enum.Material.Metal
		wall.Color = Color3.fromRGB(52, 50, 62)
		wall.Transparency = 0.25
		wall.Parent = folder

		local cap = Instance.new("Part")
		cap.Name = "HubRailCap_" .. index
		cap.Anchored = true
		cap.CanCollide = false
		cap.CanTouch = false
		cap.CanQuery = false
		cap.Size = piece[1] + Vector3.new(0.3, -4.6, 0.3)
		cap.Position = wall.Position + Vector3.new(0, 2.5, 0)
		cap.Material = Enum.Material.Neon
		cap.Color = Color3.fromRGB(150, 140, 200)
		cap.Transparency = 0.45
		cap.Parent = folder
	end

	-- A REAL SpawnLocation, not just a teleport target. Bootstrap teleports on
	-- CharacterAdded, but a respawn that lands before that hook fires would otherwise put the
	-- player on the baseplate. The level's own spawn exists only while a run does, so between
	-- runs this is the only one in the world.
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "HubSpawn"
	spawn.Anchored = true
	spawn.CanCollide = false
	spawn.Transparency = 1
	spawn.Size = Vector3.new(10, 1, 10)
	spawn.CFrame = CFrame.new(HUB_ORIGIN + Vector3.new(0, 1.5, 18))
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = folder

	for index, level in ipairs(HubService.padLevels()) do
		makeLevelPad(level, index, folder)
	end

	for _, row in ipairs(OPTION_ROWS) do
		makeOptionPads(row, folder)
	end

	-- POSE KEYS, in a short row at the foot of the plinths.
	--
	-- Per player, unlike every other pad in the room: the level, mode and length are one
	-- shared decision because one level runs per server, but how YOUR figure stands is only
	-- ever about your own statue. So these set state keyed on the player who stepped on them
	-- and never touch the RunRequest.
	for index, poseName in ipairs(POSE_ORDER) do
		local key = Instance.new("Part")
		key.Name = "PosePad_" .. poseName
		key.Anchored = true
		key.CanCollide = true
		key.CanTouch = true
		key.Shape = Enum.PartType.Cylinder
		key.Size = Vector3.new(1.2, 4.2, 4.2)
		-- MOVED CLEAR OF THE LENGTH ROW, which is why poses appeared not to work at all.
		--
		-- These sat at z = 16 with the length keys at z = 14, and both are around nine studs
		-- across -- so three of the five pose keys were buried inside a length key and could
		-- not be stepped on. Nothing was wrong with setPose; the pads were unreachable.
		--
		-- They belong beside the statue anyway. It is the thing they change.
		--
		-- The row runs -46 to -22 at z = 11, and every number in that is a constraint.
		--
		-- LEFT EDGE: the deck inlay stops at x = -50, and the first attempt put "Stand" at
		-- -48. With a 5-stud key that is -50.5, so the pad hung over the inlay's edge and
		-- broke the line the floor draws around the room.
		--
		-- RIGHT EDGE: the nearest length key is at (-12, 14) and needs 6.5 studs of clearance;
		-- ending at -22 gives 10.4.
		--
		-- z = 12 rather than 4: the statue plinth is at (-30, 4) and the row would run
		-- straight through it. Eleven studs looked like enough and was not -- the key at
		-- x = -28 came within half a stud of the plinth's corner -- so twelve.
		key.CFrame = CFrame.new(HUB_ORIGIN + Vector3.new(-46 + (index - 1) * 6, 1.5, 12))
			* CFrame.Angles(0, 0, math.rad(90))
		key.Material = Enum.Material.SmoothPlastic
		key.Color = Color3.fromRGB(148, 132, 176)
		key.Parent = folder

		-- A SOCKET AND AN INLAY, like the option keys have. These were the only bare cylinders
		-- left in the room -- five flat lilac discs in a row, which read as five patches of
		-- floor rather than as five things to stand on.
		local socket = decorPart("PoseSocket_" .. poseName, Vector3.new(0.8, 5.2, 5.2),
			key.Position - Vector3.new(0, 0.34, 0), folder)
		socket.Shape = Enum.PartType.Cylinder
		socket.CFrame = CFrame.new(key.Position - Vector3.new(0, 0.34, 0))
			* CFrame.Angles(0, 0, math.rad(90))
		socket.Material = Enum.Material.Metal
		socket.Color = Color3.fromRGB(38, 36, 46)

		local mark = decorPart("PoseInlay_" .. poseName, Vector3.new(0.3, 2.6, 2.6),
			key.Position + Vector3.new(0, 0.62, 0), folder)
		mark.Shape = Enum.PartType.Cylinder
		mark.CFrame = CFrame.new(key.Position + Vector3.new(0, 0.62, 0))
			* CFrame.Angles(0, 0, math.rad(90))
		mark.Material = Enum.Material.Neon
		mark.Color = Color3.fromRGB(206, 190, 240)
		mark.Transparency = 0.5

		-- 5.2 studs wide against a 6-stud pitch, so the plates have air between them.
		makeSign(key, poseName, "pose", 4.6, 4.6)

		-- THE KEY LIGHTS WHEN YOU STAND ON IT, whatever happens to the statue afterwards.
		--
		-- These two things were indistinguishable from the floor: a pad that never fired, and
		-- a pad that fired at a statue that could not be posed. Lighting the key separates
		-- them -- if it lights and the figure does not move, the touch is fine and the problem
		-- is downstream.
		local lit = key.Color
		key.Touched:Connect(function(hit: BasePart)
			local character = hit.Parent
			local humanoid = character and character:FindFirstChildWhichIsA("Humanoid")
			if not humanoid then
				return
			end
			local player = Players:GetPlayerFromCharacter(character)
			if not player then
				return
			end
			key.Material = Enum.Material.Neon
			key.Color = Color3.fromRGB(250, 236, 190)
			task.delay(0.35, function()
				if key.Parent then
					key.Material = Enum.Material.SmoothPlastic
					key.Color = lit
				end
			end)
			HubService.setPose(player, poseName)
		end)
	end

	local startPad = Instance.new("Part")
	startPad.Name = "StartPad"
	startPad.Anchored = true
	startPad.CanCollide = true
	startPad.CanTouch = true
	startPad.Size = Vector3.new(14, 1.6, 8)
	startPad.Material = Enum.Material.Neon
	startPad.Color = Color3.fromRGB(120, 220, 140)
	startPad.Position = HUB_ORIGIN + Vector3.new(0, 1.8, 32)
	startPad.Parent = folder
	makeSign(startPad, "START", "step on to begin")

	-- DEBOUNCED, unlike the selection pads. Those are idempotent, so a repeated Touched costs
	-- nothing; building a level twice would leave two spirals and a very confused teleport.
	local starting = false
	startPad.Touched:Connect(function(hit: BasePart)
		local character = hit.Parent
		if starting or not (character and character:FindFirstChildWhichIsA("Humanoid")) then
			return
		end
		starting = true
		-- CALLS THE VOTE rather than starting the run. Everything about which run it is now
		-- gets decided in the ten seconds after this, by the room.
		HubService.callVote()
		task.delay(2, function()
			starting = false
		end)
	end)

	local board = Instance.new("Part")
	board.Name = "LeaderboardBoard"
	board.Anchored = true
	board.CanCollide = true
	board.Size = Vector3.new(1, 14, 22)
	board.Material = Enum.Material.Slate
	board.Color = Color3.fromRGB(40, 38, 48)
	board.Position = HUB_ORIGIN + Vector3.new(34, 8, 4)
	board.Parent = folder
	-- NO SurfaceGui HERE. One parented to the board would be the same text for everybody,
	-- which is the thing being fixed; attachBoard puts a private one in each PlayerGui and
	-- points it back at this part.
	boardPart = board

	-- A BEZEL, so the panel is mounted in something. A SurfaceGui on a bare slab reads as a
	-- texture; a frame standing slightly proud of it reads as a screen.
	for _, edge in ipairs({
		{ Vector3.new(1.4, 15.2, 0.7), Vector3.new(-0.3, 0, 11.15) },
		{ Vector3.new(1.4, 15.2, 0.7), Vector3.new(-0.3, 0, -11.15) },
		{ Vector3.new(1.4, 0.7, 22.7), Vector3.new(-0.3, 7.55, 0) },
		{ Vector3.new(1.4, 0.7, 22.7), Vector3.new(-0.3, -7.55, 0) },
	}) do
		local trimPiece = Instance.new("Part")
		trimPiece.Name = "BoardTrim"
		trimPiece.Anchored = true
		trimPiece.CanCollide = false
		trimPiece.CanTouch = false
		trimPiece.CanQuery = false
		trimPiece.Size = edge[1]
		trimPiece.Position = board.Position + edge[2]
		trimPiece.Material = Enum.Material.Metal
		trimPiece.Color = Color3.fromRGB(78, 76, 96)
		trimPiece.Parent = folder
	end

	local stand = Instance.new("Part")
	stand.Name = "BoardStand"
	stand.Anchored = true
	stand.CanCollide = true
	stand.Size = Vector3.new(3, 8, 6)
	stand.Position = board.Position - Vector3.new(0, 11, 0)
	stand.Material = Enum.Material.Marble
	stand.Color = PALETTE.stone
	stand.Parent = folder

	-- THE ARROW, as a real object with a ClickDetector rather than a button in the SurfaceGui.
	--
	-- A GuiButton's Activated fires on the CLIENT, so a button on the board would need a
	-- RemoteEvent and a server-side guard to stop anyone spamming DataStore reads. A
	-- ClickDetector fires on the server already, which is where the board is built and where
	-- the read happens, so the whole round trip disappears.
	-- THE MODE SWITCH: a lever standing at the near corner of the board, not a floating
	-- block eight studs under it.
	--
	-- It reads as a switch because it has a base, a stem and a head, and because the head
	-- MOVES when you throw it. Colour alone would be a light; the travel is what makes it a
	-- control you have operated rather than a status you are being shown.
	local switchBase = Instance.new("Part")
	switchBase.Name = "BoardSwitchBase"
	switchBase.Anchored = true
	switchBase.CanCollide = true
	switchBase.Shape = Enum.PartType.Cylinder
	switchBase.Size = Vector3.new(1.2, 4.4, 4.4)
	switchBase.CFrame = CFrame.new(board.Position + Vector3.new(-3.2, -6.4, 8))
		* CFrame.Angles(0, 0, math.rad(90))
	switchBase.Material = Enum.Material.Metal
	switchBase.Color = Color3.fromRGB(46, 44, 54)
	switchBase.Parent = folder
	-- The clickable cylinder above stays -- it is the hitbox and it has to be a simple shape
	-- the ClickDetector can own -- but it is made invisible and a modelled socket is dropped
	-- over it. Hub_LeverBase has a raised collar with a hole for the shaft, which is what
	-- makes the handle read as hinged INSIDE something rather than stuck onto a plate.
	local socket = propAt("Hub_LeverBase", switchBase.Position, folder)
	if socket then
		switchBase.Transparency = 1
		socket.Material = Enum.Material.Metal
		socket.Color = Color3.fromRGB(52, 50, 62)
	end

	-- THE MOVING HALF OF THE LEVER IS NOT BUILT HERE.
	--
	-- The state is per player now, and a part has exactly one CFrame: two people wanting the
	-- lever thrown different ways cannot both be served by one object in the world. A pip
	-- floating in front of a static head was the previous compromise and it is a worse switch
	-- -- the travel is the whole point, because it is what tells you that you operated
	-- something rather than that you were shown something.
	--
	-- So the base and its socket are server-side and shared (they never move, and the
	-- ClickDetector on the base has to be here to know WHO clicked), and the stem and head are
	-- built by HubLeverService on each client under workspace.CurrentCamera, which is the one
	-- parent whose contents are never replicated. Each player gets a lever that really swings,
	-- and swings only for them.
	--
	-- This part is the contract between the two halves: an invisible marker naming where the
	-- stem is hinged, so the client is not repeating a position the server chose.
	local pivot = Instance.new("Part")
	pivot.Name = "BoardSwitchPivot"
	pivot.Anchored = true
	pivot.CanCollide = false
	pivot.CanTouch = false
	pivot.CanQuery = false
	pivot.Transparency = 1
	pivot.Size = Vector3.new(0.6, 0.6, 0.6)
	pivot.CFrame = CFrame.new(switchBase.Position)
	pivot.Parent = folder

	local click = Instance.new("ClickDetector")
	click.MaxActivationDistance = 40
	click.Parent = switchBase

	-- DEBOUNCED PER PLAYER, not globally. Every throw is a DataStore read, so it still needs a
	-- guard, but a shared flag would mean one person clicking locks everyone else out of a
	-- control that is now theirs individually.
	--
	-- MouseClick hands us the player who clicked, which is the whole reason the base is a
	-- ClickDetector: a GuiButton would fire on the client and need a remote to say who.
	local switching: { [Player]: boolean } = {}
	click.MouseClick:Connect(function(player: Player)
		if switching[player] then
			return
		end
		switching[player] = true
		HubService.toggleBoardMode(player)
		task.delay(0.5, function()
			switching[player] = nil
		end)
	end)

	-- Anyone already standing in the room when the hub is built gets their view now; the rest
	-- are attached by Bootstrap as they join.
	for _, player in ipairs(Players:GetPlayers()) do
		pcall(HubService.attachBoard, player)
	end

	-- LAST, so a failure in scenery cannot stop the controls from existing. Everything above
	-- this line is something you press; everything in here is something you look at, and the
	-- room is still usable without any of it.
	local decorOk, decorErr = pcall(buildSurroundings, folder)
	if not decorOk then
		warn("HubService: the surroundings failed to build, the lobby still works: " .. tostring(decorErr))
	end

	-- AFTER the surroundings, not before: the fountain loop attaches to FountainJet, and
	-- buildSurroundings is what creates it. Run first, this found nothing and the water was
	-- silent -- a bug with no error message, which is the kind that survives a long time.
	local soundOk, soundErr = pcall(buildAmbience, folder)
	if not soundOk then
		warn("HubService: the lobby ambience failed to start: " .. tostring(soundErr))
	end

	HubService.refreshPads()
	HubService.refreshOptionPads()
	HubService.refreshBoard()
	return { spawnPosition = HubService.spawnPosition() }
end

return HubService
