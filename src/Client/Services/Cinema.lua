--!strict
-- StarterPlayerScripts/Services/Cinema.lua
-- The camera, when a level takes it: the four finales (City Shore's dive, the Sky Pools' slide, the
-- Sunken City's drain, the Flooded Halls' flume and the gates under it) are played as scenes rather
-- than as a player being moved about. This is what they share, so each only has to say where the
-- camera goes.
--
--   begin()     black bars close in across the top and bottom of the screen, your controls are
--               turned off and the camera is the scene's (Scriptable), whatever you had it zoomed to.
--   point()     where the camera is this frame, and how wide it sees. Within a shot it turns smoothly
--               (a camera operator's pan, not a snap); a new shot is a clean cut. `clear` pulls a shot
--               in if something stands between it and what it is looking at.
--   cut()       the next point() is a new shot, whatever it looks like.
--   dip()       the picture fades to black and back, for going somewhere else in the same scene.
--   caption()   a title low on the screen, a film's kind: a place in capitals and a line under it.
--   finish()    all of it given back: the camera behind you, the bars gone, your controls yours.
--
-- AND A CAMERA OPERATOR'S KIT, for the scenes that need more than a place to stand:
--
--   spline()    a point along a smooth curve through several (Catmull-Rom): a crane move, an orbit,
--               a push in, without the corners a straight line from mark to mark has.
--   shake()     a jolt that dies away: a door giving, jaws closing.
--   focus()     depth of field: what the shot is about sharp, the rest soft.
--   black()     the picture to black (or back) at once or over a moment: a cut to black.
--   impact()    an IMPACT FRAME, the kind a comic or an action game hits a big moment with: two frames in
--               hard black and white, a soft white flash, a burst of speed lines from the edges, the lens
--               punched in and a jolt, then the colour back, a little punchier, settling. A leap, a crash.
--   speedLines() lines streaming in from the edges of the picture while something is going fast (0 to 1).
--   think()     a thought over a character's head, in a little bubble, written out as if being thought: what
--               they make of it ("These bricks are loose."), what they are afraid of ("Where does this go?").
--
-- AN ENDING SILENCES THE LEVEL. begin() fades out every ambient sound (tagged Ambience, and the
-- player's ambience beds: AmbienceService) and they stay gone: the scene's own sounds are all you hear.
-- A short scene that is not an ending (finding something: StoryClient) says { hush = false }.
--
-- YOU ARE ALWAYS IN SHOT. A player zoomed right in is in first person, and Roblox hides their own body
-- from them there; in a scene that would be a camera following nobody down a slide. While a scene is
-- on, every part of your character is drawn, however close your own camera was.
--
-- SLOW ENOUGH TO READ. A caption stays up for as long as its words take to read twice (never under
-- seven seconds), and a caption that arrives while the last one is still being read WAITS its turn
-- instead of replacing it. A scene that finishes while a caption is still up holds its last shot until
-- the caption has been read. Bigger type than before, on a soft dark band, so it reads over snow,
-- cloud and sky alike.
--
-- AN ENDING TELLS THE SERVER WHEN IT HAS BEEN WATCHED. begin() says so when a scene that is an ending
-- starts, done() when its story is told (once its captions are read) and finish() if it never said
-- done. The server waits for that before it takes you back to the lobby, and the banner waits for it
-- before it comes up, so neither lands on a scene still being told (SceneState; Bootstrap).
--
-- THE CAMERA COMES BACK BEHIND YOU. finish() puts it over your shoulder before handing it back: the
-- default camera carries on from wherever it is given, and given a shot looking straight down it went
-- on looking straight down.
--
-- A library, not a service: the level clients require it. Nothing here runs until one calls it.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ContextActionService = game:GetService("ContextActionService")
local ProximityPromptService = game:GetService("ProximityPromptService")

local Cinema = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- One look for the whole game (the ninety-ninth pass): every face, colour, corner and outline.
local Style = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Style"))

local BARS = 0.11 -- each bar, as a share of the screen's height
local CAPTION_SECONDS = 7 -- how long a caption stays up unless a scene says
-- READING TIME: a caption is up for at least READ_BASE plus READ_WORD a word (twice through at an easy
-- pace), and another may not replace it before FIRST_BASE plus FIRST_WORD a word (once through).
local READ_BASE, READ_WORD = 3, 0.42
local FIRST_BASE, FIRST_WORD = 2.4, 0.3
-- WITHIN A SHOT the camera's aim follows its target at this rate (per second); a shot whose eye
-- jumps further than CUT_STUDS, or turns further than CUT_ANGLE, in one frame is a new shot and cuts.
local AIM_RATE = 7
local CUT_STUDS = 14
local CUT_ANGLE = math.rad(40)
local SHOW = "CinemaKeepsYouInShot"

type Live = { gui: ScreenGui, top: Frame, bottom: Frame, veil: Frame, fov: number, controls: any, words: Frame,
	aim: CFrame?, eye: Vector3?, at: number, cut: boolean, shake: number, focus: DepthOfFieldEffect?,
	ending: boolean, told: boolean, finishing: boolean, readUntil: number, freeAt: number, queue: number,
	sounds: { Sound }, lines: { Frame }, lineAmount: number, burst: number, kick: number, flash: Frame,
	impactFx: ColorCorrectionEffect?, waver: number }
-- THE SPEED LINES: this many, streaming in from the edges of the picture.
local LINE_COUNT = 36
local live: Live? = nil

-- An ending's word to the server: "began" when it starts, "done" when it has been watched.
local function tell(state: string)
	local folder = ReplicatedStorage:FindFirstChild("RemoteEvents")
	local remote = folder and folder:FindFirstChild("SceneState")
	if remote and remote:IsA("RemoteEvent") then
		remote:FireServer(state)
	end
end

-- The default controls, to turn off and on; nil where the place has its own.
local function findControls(): any
	local scripts = Players.LocalPlayer:FindFirstChildOfClass("PlayerScripts")
	local module = scripts and scripts:FindFirstChild("PlayerModule")
	if not (module and module:IsA("ModuleScript")) then
		return nil
	end
	local ok, found = pcall(function()
		return (require(module) :: any):GetControls()
	end)
	return if ok then found else nil
end

-- Every part of your own character drawn, after the camera has decided what to hide.
local function showYou()
	local character = Players.LocalPlayer.Character
	if not character then
		return
	end
	for _, item in ipairs(character:GetDescendants()) do
		if item:IsA("BasePart") or item:IsA("Decal") then
			item.LocalTransparencyModifier = 0
		end
	end
end

function Cinema.active(): boolean
	return live ~= nil
end

-- HELD STILL (the hundred-and-thirtieth pass, from your test: "I can walk around during animations"): the controls are
-- switched off when a scene begins, and the shop and the welcome switch them back on as they close, so a scene could be
-- walked out of. While a scene has the camera, moving and jumping go nowhere, whoever else has the controls (a scene's
-- own MoveTo still walks you where it wants you).
local STILL = "CinemaHoldsYouStill"
local function holdStill(on: boolean)
	if on then
		ContextActionService:BindActionAtPriority(STILL, function()
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value + 100, Enum.PlayerActions.CharacterForward,
			Enum.PlayerActions.CharacterBackward, Enum.PlayerActions.CharacterLeft, Enum.PlayerActions.CharacterRight,
			Enum.PlayerActions.CharacterJump, Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D, Enum.KeyCode.Up,
			Enum.KeyCode.Down, Enum.KeyCode.Left, Enum.KeyCode.Right, Enum.KeyCode.Space, Enum.KeyCode.Thumbstick1)
	else
		ContextActionService:UnbindAction(STILL)
	end
end

-- WHEN THE LOBBY TAKES YOU (the same pass, from your test: "when I leave to lobby every animation should stop even if it
-- is playing"): whatever scene is on is over at once, its camera given back, its sounds and the ones it kept faded, and
-- every scene's own things (registered with Cinema.onLeave) put away, so nothing plays on over the lobby or moves you
-- back. Going down into the back rooms is not leaving.
local leaving: { () -> () } = {}
local kept: { Sound } = {}
function Cinema.onLeave(fn: () -> ())
	table.insert(leaving, fn)
end
local function left()
	for _, s in ipairs(kept) do
		Cinema.fade(s, 1.5)
	end
	table.clear(kept)
	if live then
		Cinema.finish(true)
	end
	for _, fn in ipairs(leaving) do
		local ok, err = pcall(fn)
		if not ok then
			warn("Cinema: a scene could not be put away on leaving: " .. tostring(err))
		end
	end
end
local wasIn = Players.LocalPlayer:GetAttribute("InLevel")
Players.LocalPlayer:GetAttributeChangedSignal("InLevel"):Connect(function()
	local now = Players.LocalPlayer:GetAttribute("InLevel")
	if wasIn ~= nil and now ~= wasIn and now ~= "backRooms" then
		left()
	end
	wasIn = now
end)

-- True once an ending's story has been told (done(), its captions read), or when there is no scene:
-- what the banner waits for before it comes up.
function Cinema.told(): boolean
	local current = live
	return current == nil or not current.ending or current.told
end

-- The level's ambience, out: every ambient sound faded to nothing on this screen, and the player
-- marked Hushed so what writes ambience every frame (AmbienceService, the Sunken City's mood) leaves it
-- at nothing. It comes back with the next level.
function Cinema.hush()
	Players.LocalPlayer:SetAttribute("Hushed", true)
	for _, item in ipairs(CollectionService:GetTagged("Ambience")) do
		if item:IsA("Sound") then
			TweenService:Create(item, TweenInfo.new(2.5, Enum.EasingStyle.Sine), { Volume = 0 }):Play()
		end
	end
end

function Cinema.begin(options: { hush: boolean? }?)
	if live then
		return
	end
	-- An ending unless it says it is not (a secret found is a short scene, not an ending).
	local ending = not (options and options.hush == false)
	if ending then
		Cinema.hush()
	end
	local camera = workspace.CurrentCamera
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not camera or not playerGui then
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "Cinema"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 40
	-- The black the picture dips to, under the bars and the captions.
	local veil = Instance.new("Frame")
	veil.Name = "Veil"
	veil.Size = UDim2.fromScale(1, 1)
	veil.BackgroundColor3 = Color3.new(0, 0, 0)
	veil.BackgroundTransparency = 1
	veil.BorderSizePixel = 0
	veil.ZIndex = 1
	veil.Parent = gui
	local function bar(edge: number): Frame
		local frame = Instance.new("Frame")
		frame.AnchorPoint = Vector2.new(0, edge)
		frame.Position = UDim2.fromScale(0, edge)
		frame.Size = UDim2.fromScale(1, 0)
		frame.BackgroundColor3 = Color3.new(0, 0, 0)
		frame.BorderSizePixel = 0
		frame.ZIndex = 2
		frame.Parent = gui
		return frame
	end
	local top, bottom = bar(0), bar(1)
	-- THE SPEED LINES and THE IMPACT'S FLASH, over the picture, under the bars and the words.
	local lineBox = Instance.new("Frame")
	lineBox.Name = "SpeedLines"
	lineBox.Size = UDim2.fromScale(1, 1)
	lineBox.BackgroundTransparency = 1
	lineBox.ZIndex = 1
	lineBox.Parent = gui
	local lines: { Frame } = {}
	for _ = 1, LINE_COUNT do
		local line = Instance.new("Frame")
		line.AnchorPoint = Vector2.new(0.5, 0.5)
		line.BackgroundColor3 = Color3.new(1, 1, 1)
		line.BackgroundTransparency = 1
		line.BorderSizePixel = 0
		line.ZIndex = 1
		line.Parent = lineBox
		table.insert(lines, line)
	end
	local flash = Instance.new("Frame")
	flash.Name = "ImpactFlash"
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundColor3 = Color3.new(1, 1, 1)
	flash.BackgroundTransparency = 1
	flash.BorderSizePixel = 0
	flash.ZIndex = 1
	flash.Parent = gui
	-- A SOFT DARK BAND over the bottom of the picture, under the captions: white type over snow, cloud
	-- or sky was unreadable. Shown only while a caption is.
	local band = Instance.new("Frame")
	band.Name = "CaptionBand"
	band.AnchorPoint = Vector2.new(0, 1)
	band.Position = UDim2.fromScale(0, 1 - BARS)
	band.Size = UDim2.new(1, 0, 0, 150)
	band.BackgroundColor3 = Color3.new(0, 0, 0)
	band.BackgroundTransparency = 1
	band.BorderSizePixel = 0
	band.ZIndex = 2
	band.Parent = gui
	local fade = Instance.new("UIGradient")
	fade.Rotation = 90
	fade.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.25) })
	fade.Parent = band
	-- Where captions go: inside the bottom bar's height, over the picture.
	local words = Instance.new("Frame")
	words.Name = "Captions"
	words.BackgroundTransparency = 1
	words.AnchorPoint = Vector2.new(0.5, 1)
	words.Position = UDim2.new(0.5, 0, 1 - BARS, -20)
	words.Size = UDim2.new(0.8, 0, 0, 84)
	words.ZIndex = 3
	words.Parent = gui
	gui.Parent = playerGui
	local close = TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(top, close, { Size = UDim2.fromScale(1, BARS) }):Play()
	TweenService:Create(bottom, close, { Size = UDim2.fromScale(1, BARS) }):Play()
	local found = findControls()
	if found then
		pcall(function()
			found:Disable()
		end)
	end
	holdStill(true)
	-- The prompts put away while a scene plays: "Look" hung over the locker all through its scene.
	pcall(function()
		ProximityPromptService.Enabled = false
	end)
	live = { gui = gui, top = top, bottom = bottom, veil = veil, fov = camera.FieldOfView, controls = found,
		words = words, aim = nil, eye = nil, at = os.clock(), cut = true, shake = 0, focus = nil,
		ending = ending, told = false, finishing = false, readUntil = 0, freeAt = 0, queue = 0, sounds = {},
		lines = lines, lineAmount = 0, burst = 0, kick = 0, flash = flash, impactFx = nil, waver = 0 }
	if ending then
		tell("began")
	end
	camera.CameraType = Enum.CameraType.Scriptable
	pcall(function()
		RunService:UnbindFromRenderStep(SHOW)
	end)
	RunService:BindToRenderStep(SHOW, Enum.RenderPriority.Camera.Value + 2, showYou)
end

-- A point `eye` looking at `at` would see it from, pulled in toward `at` if something solid is
-- between them (`ignore` is who the shot is of).
function Cinema.clear(eye: Vector3, at: Vector3, ignore: { Instance }?): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore or {}
	local hit = workspace:Raycast(at, eye - at, params)
	return if hit then hit.Position + hit.Normal * 0.6 else eye
end

-- OUT OF THE SHOT (the hundred-and-thirtieth pass, from your test: "it just gets covered if I stand in front of it, move
-- me out the way if I'm in the way and do the same for every animation where it makes sense"): if you stand between a
-- shot's eye and what it looks at, you take a step aside to whichever side has room, clear of the line by `clearance`,
-- and turn to look at it. Nothing happens if you are not in the way.
function Cinema.stepAside(eye: Vector3, at: Vector3, clearance: number?)
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (root and root:IsA("BasePart") and humanoid) then
		return
	end
	local need = clearance or 2.4
	local here = root.Position
	local a = Vector3.new(eye.X, here.Y, eye.Z)
	local b = Vector3.new(at.X, here.Y, at.Z)
	local line = b - a
	if line.Magnitude < 0.1 then
		return
	end
	local u = (here - a):Dot(line) / line:Dot(line)
	local nearest = a + line * math.clamp(u, 0, 1)
	local off = here - nearest
	if u <= 0.02 or u >= 0.98 or off.Magnitude >= need then
		return
	end
	local side = Vector3.yAxis:Cross(line.Unit)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character :: Instance }
	local function room(dir: Vector3): number
		local hit = workspace:Raycast(here, dir * (need + 1.5), params)
		return if hit then hit.Distance else need + 1.5
	end
	local sign = if off:Dot(side) >= 0 then 1 else -1
	if room(side * sign) < need + 0.6 and room(-side * sign) > room(side * sign) then
		sign = -sign
	end
	local to = nearest + side * sign * need
	humanoid:MoveTo(to)
	task.delay(0.45, function()
		if root.Parent then
			local look = Vector3.new(at.X - root.Position.X, 0, at.Z - root.Position.Z)
			if look.Magnitude > 0.2 then
				root.CFrame = CFrame.lookAt(root.Position, root.Position + look.Unit)
			end
		end
	end)
end

-- The next point() starts a new shot: no pan from wherever the last one was looking.
function Cinema.cut()
	local current = live
	if current then
		current.cut = true
	end
end

-- The speed lines this frame: some of them redrawn somewhere new each frame, so they stream and flicker.
local function drawLines(current: Live, dt: number)
	local amount = math.max(current.lineAmount, current.burst)
	current.burst = current.burst * math.exp(-6 * dt)
	local size = current.gui.AbsoluteSize
	if amount < 0.02 or size.X < 1 then
		for _, line in ipairs(current.lines) do
			line.BackgroundTransparency = 1
		end
		return
	end
	local cx, cy = size.X / 2, size.Y / 2
	local reach = math.sqrt(cx * cx + cy * cy)
	for _, line in ipairs(current.lines) do
		if math.random() < 0.45 then
			local a = math.random() * math.pi * 2
			local r = reach * (0.55 + math.random() * 0.45)
			local length = reach * (0.12 + math.random() * 0.3) * (0.6 + amount)
			line.Position = UDim2.fromOffset(cx + math.cos(a) * r, cy + math.sin(a) * r)
			line.Size = UDim2.fromOffset(length, 1 + math.random() * 2.5 * amount)
			line.Rotation = math.deg(a)
			line.BackgroundTransparency = 1 - amount * (0.25 + math.random() * 0.45)
		end
	end
end

-- The camera this frame. A little hand-held drift unless `steady`; within a shot the aim pans after
-- its target rather than snapping to it, and a jump is taken as a cut.
function Cinema.point(cf: CFrame, fov: number?, steady: boolean?)
	local camera = workspace.CurrentCamera
	local current = live
	if not current or not camera then
		return
	end
	camera.CameraType = Enum.CameraType.Scriptable
	local now = os.clock()
	local dt = math.clamp(now - current.at, 0, 0.1)
	current.at = now
	local aim = current.aim
	local eye = current.eye
	local wanted = cf - cf.Position
	if current.cut or not aim or not eye or (cf.Position - eye).Magnitude > CUT_STUDS
		or math.acos(math.clamp(aim.LookVector:Dot(wanted.LookVector), -1, 1)) > CUT_ANGLE then
		aim = wanted
		current.cut = false
	else
		aim = aim:Lerp(wanted, 1 - math.exp(-AIM_RATE * dt))
	end
	current.aim = aim
	current.eye = cf.Position
	local drift = if steady then CFrame.identity
		else CFrame.Angles(math.sin(now * 1.3) * 0.004 + math.sin(now * 23) * 0.0015, math.sin(now * 1.1) * 0.004, 0)
	-- A JOLT, dying away: noise rather than a sine, so it does not read as a wobble.
	local jolt = current.shake
	if jolt > 0.001 then
		drift *= CFrame.Angles(math.noise(now * 22, 1.3) * jolt * 0.06, math.noise(now * 22, 7.1) * jolt * 0.06,
			math.noise(now * 22, 3.7) * jolt * 0.03)
		current.shake = jolt * math.exp(-4.5 * dt)
	end
	-- SEEN THROUGH WATER (Cinema.waver): a slow roll and the lens breathing, as moving water bends a view.
	local w = current.waver
	if w > 0 then
		drift *= CFrame.Angles(math.sin(now * 1.4) * 0.01 * w, 0, (math.sin(now * 1.9) * 0.028 + math.sin(now * 3.3) * 0.01) * w)
	end
	camera.CFrame = CFrame.new(cf.Position) * (aim :: CFrame) * drift
	-- AN IMPACT's punch in, dying away.
	local kick = current.kick
	current.kick = kick * math.exp(-7 * dt)
	if fov then
		camera.FieldOfView = math.max(8, fov - kick + math.sin(now * 2.1) * 2.4 * w)
	end
	drawLines(current, dt)
end

-- THE PICTURE SWIMMING, `amount` 0 to 1 (the hundred-and-twenty-sixth pass, under the Sunken City's water): what a scene
-- sees through moving water, a slow roll and the lens breathing. 0 puts it right.
function Cinema.waver(amount: number)
	local current = live
	if current then
		current.waver = math.clamp(amount, 0, 1)
	end
end

-- AN IMPACT FRAME (`strength` about 1; 1.5 for a crash): two frames in hard black and white, a soft white
-- flash, a burst of speed lines, the lens punched in and a jolt; then the colour comes back a little punchier
-- and settles. Brief, and never a full white: a beat, not a strobe.
function Cinema.impact(strength: number?)
	local current = live
	if not current then
		return
	end
	local s = math.clamp(strength or 1, 0.2, 2)
	current.burst = math.max(current.burst, math.min(1, 0.9 * s))
	current.kick = math.max(current.kick, 9 * s)
	current.shake = math.max(current.shake, 1.2 * s)
	local fx = current.impactFx
	if not fx then
		local made = Instance.new("ColorCorrectionEffect")
		made.Name = "CinemaImpact"
		made.Parent = Lighting
		current.impactFx = made
		fx = made
	end
	local effect = fx :: ColorCorrectionEffect
	effect.Saturation = -1
	effect.Contrast = 0.9
	effect.Brightness = 0.12
	current.flash.BackgroundTransparency = 0.55
	TweenService:Create(current.flash, TweenInfo.new(0.22, Enum.EasingStyle.Quad), { BackgroundTransparency = 1 }):Play()
	task.delay(0.07, function()
		if live == current and effect.Parent then
			effect.Saturation = 0.35
			effect.Contrast = 0.3
			effect.Brightness = 0
			TweenService:Create(effect, TweenInfo.new(0.45, Enum.EasingStyle.Quad), { Saturation = 0, Contrast = 0 }):Play()
		end
	end)
end

-- A THOUGHT over `character`'s head for `seconds`: a soft bubble with a little trail of dots down to them, the
-- words written out as if being thought. A new thought replaces the last. Only on this screen.
function Cinema.think(character: Model?, text: string, seconds: number?)
	local head = character and character:FindFirstChild("Head")
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not (head and head:IsA("BasePart") and playerGui) then
		return
	end
	local old = playerGui:FindFirstChild("CinemaThought")
	if old then
		old:Destroy()
	end
	local board = Instance.new("BillboardGui")
	board.Name = "CinemaThought"
	board.Adornee = head
	board.Size = UDim2.fromOffset(250, 96)
	board.StudsOffset = Vector3.new(0, 2.9, 0)
	board.AlwaysOnTop = true
	board.MaxDistance = 80
	board.ResetOnSpawn = false
	board.Parent = playerGui
	local bubble = Instance.new("Frame")
	bubble.Name = "Bubble"
	bubble.AnchorPoint = Vector2.new(0.5, 0)
	bubble.Position = UDim2.fromScale(0.5, 0)
	bubble.Size = UDim2.new(1, 0, 0, 62)
	bubble.BackgroundColor3 = Color3.fromRGB(252, 250, 244)
	bubble.BackgroundTransparency = 1
	bubble.BorderSizePixel = 0
	bubble.Parent = board
	local round = Instance.new("UICorner")
	round.CornerRadius = Style.RADIUS.panel
	round.Parent = bubble
	local edge = Instance.new("UIStroke")
	edge.Color = Color3.fromRGB(60, 54, 48)
	edge.Thickness = Style.STROKE.panel
	edge.Transparency = 1
	edge.Parent = bubble
	local words = Instance.new("TextLabel")
	words.BackgroundTransparency = 1
	words.Position = UDim2.fromOffset(12, 6)
	words.Size = UDim2.new(1, -24, 1, -12)
	words.FontFace = Style.FONT.body
	words.TextScaled = true
	words.TextWrapped = true
	words.TextColor3 = Color3.fromRGB(40, 36, 32)
	words.TextTransparency = 1
	words.Text = text
	words.MaxVisibleGraphemes = 0
	words.Parent = bubble
	local most = Instance.new("UITextSizeConstraint")
	most.MaxTextSize = 22
	most.Parent = words
	local dots: { Frame } = {}
	for k, d in ipairs({ 12, 8 }) do
		local dot = Instance.new("Frame")
		dot.AnchorPoint = Vector2.new(0.5, 0)
		dot.Position = UDim2.new(0.5, -6 * k, 0, 62 + 4 + (k - 1) * 13)
		dot.Size = UDim2.fromOffset(d, d)
		dot.BackgroundColor3 = Color3.fromRGB(252, 250, 244)
		dot.BackgroundTransparency = 1
		dot.BorderSizePixel = 0
		dot.Parent = board
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.5, 0)
		c.Parent = dot
		table.insert(dots, dot)
	end
	-- POPPED IN, and out (the hundred-and-thirtieth pass, from your test): faded in and out, the bubble went grey and its
	-- words vanished into it before it did, and for a moment there was an empty bubble over your head. Now it is all
	-- there at once, words with it, swelling up from your head, and shrinks away back into it.
	local pop = Instance.new("UIScale")
	pop.Scale = 0.4
	pop.Parent = bubble
	bubble.BackgroundTransparency = 0.05
	edge.Transparency = 0.2
	words.TextTransparency = 0
	words.MaxVisibleGraphemes = 1
	for _, dot in ipairs(dots) do
		dot.BackgroundTransparency = 0.05
	end
	TweenService:Create(pop, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	-- Written out as it is thought: a letter at a time, about thirty a second.
	local length = utf8.len(text) or #text
	TweenService:Create(words, TweenInfo.new(length / 30, Enum.EasingStyle.Linear), { MaxVisibleGraphemes = length }):Play()
	task.delay(seconds or 3.5, function()
		if board.Parent then
			TweenService:Create(pop, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0 }):Play()
			for _, dot in ipairs(dots) do
				TweenService:Create(dot, TweenInfo.new(0.12), { BackgroundTransparency = 1 }):Play()
			end
			task.delay(0.18, function()
				board:Destroy()
			end)
		end
	end)
end

-- SPEED LINES streaming in from the edges while something goes fast: `amount` 0 (none) to 1 (a dive at full pelt).
function Cinema.speedLines(amount: number)
	local current = live
	if current then
		current.lineAmount = math.clamp(amount, 0, 1)
	end
end

-- A point `u` (0 to 1) of the way along a smooth curve through `points` (Catmull-Rom, uniform): the
-- camera passes through every mark without stopping at any of them.
function Cinema.spline(points: { Vector3 }, u: number): Vector3
	local n = #points
	if n == 0 then
		return Vector3.zero
	elseif n == 1 then
		return points[1]
	end
	local span = math.clamp(u, 0, 1) * (n - 1)
	local i = math.min(math.floor(span) + 1, n - 1)
	local t = span - (i - 1)
	local p0, p1, p2, p3 = points[math.max(1, i - 1)], points[i], points[i + 1], points[math.min(n, i + 2)]
	local t2, t3 = t * t, t * t * t
	return 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
end

-- A jolt of `amount` (about 1 for a door giving way, 3 for something enormous), dying away.
function Cinema.shake(amount: number)
	local current = live
	if current then
		current.shake = math.max(current.shake, amount)
	end
end

-- Depth of field: sharp at `distance` studs from the camera, soft before and beyond it. nil turns it off.
function Cinema.focus(distance: number?, strength: number?)
	local current = live
	if not current then
		return
	end
	if not distance then
		if current.focus then
			current.focus:Destroy()
			current.focus = nil
		end
		return
	end
	local effect = current.focus
	if not effect then
		effect = Instance.new("DepthOfFieldEffect")
		effect.Name = "CinemaFocus"
		effect.Parent = Lighting
		current.focus = effect
	end
	local dof = effect :: DepthOfFieldEffect
	dof.FocusDistance = distance
	dof.InFocusRadius = math.max(2, distance * 0.35)
	dof.FarIntensity = strength or 0.45
	dof.NearIntensity = (strength or 0.45) * 0.6
end

-- The picture to black (`on`) or back from it, at once or over `seconds`: a cut to black.
function Cinema.black(on: boolean, seconds: number?)
	local current = live
	if not current then
		return
	end
	local goal = if on then 0 else 1
	if not seconds or seconds <= 0 then
		current.veil.BackgroundTransparency = goal
	else
		TweenService:Create(current.veil, TweenInfo.new(seconds, Enum.EasingStyle.Sine), { BackgroundTransparency = goal }):Play()
	end
end

-- The picture to black over the first part of `seconds`, `atBlack` run while it is black (to move
-- something where nobody sees it move), and back over the rest.
function Cinema.dip(seconds: number, atBlack: (() -> ())?)
	local current = live
	if not current then
		if atBlack then
			atBlack()
		end
		return
	end
	local veil = current.veil
	task.spawn(function()
		local fade = seconds * 0.4
		local tween = TweenService:Create(veil, TweenInfo.new(fade, Enum.EasingStyle.Sine), { BackgroundTransparency = 0 })
		tween:Play()
		tween.Completed:Wait()
		if atBlack then
			local ok, err = pcall(atBlack)
			if not ok then
				warn("Cinema: something run in the dark failed: " .. tostring(err))
			end
		end
		Cinema.cut()
		task.wait(seconds * 0.2)
		if veil.Parent then
			TweenService:Create(veil, TweenInfo.new(fade, Enum.EasingStyle.Sine), { BackgroundTransparency = 1 }):Play()
		end
	end)
end

local function wordCount(text: string): number
	local count = 0
	for _ in string.gmatch(text, "%S+") do
		count += 1
	end
	return count
end

-- One caption on the screen: the one before it (already read once) fades out first.
local function showCaption(current: Live, ticket: number, place: string, line: string?, hold: number)
	for _, old in ipairs(current.words:GetChildren()) do
		if old:IsA("TextLabel") then
			TweenService:Create(old, TweenInfo.new(0.4), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			game:GetService("Debris"):AddItem(old, 0.5)
		end
	end
	if not current.words:FindFirstChildOfClass("UIListLayout") then
		local list = Instance.new("UIListLayout")
		list.HorizontalAlignment = Enum.HorizontalAlignment.Center
		list.VerticalAlignment = Enum.VerticalAlignment.Bottom
		list.Padding = UDim.new(0, 6)
		list.SortOrder = Enum.SortOrder.LayoutOrder
		list.Parent = current.words
	end
	local band = current.gui:FindFirstChild("CaptionBand")
	if band and band:IsA("Frame") then
		TweenService:Create(band, TweenInfo.new(0.8), { BackgroundTransparency = 0 }):Play()
	end
	local labels = {}
	for index, text in ipairs({ place, line or "" }) do
		if text ~= "" then
			local label = Instance.new("TextLabel")
			label.BackgroundTransparency = 1
			label.Size = UDim2.new(1, 0, 0, if index == 1 then 30 else 26)
			label.FontFace = if index == 1 then Style.FONT.heading else Style.FONT.body
			label.TextSize = if index == 1 then 26 else 21
			label.TextColor3 = if index == 1 then Color3.fromRGB(248, 244, 232) else Color3.fromRGB(226, 230, 224)
			label.TextStrokeColor3 = Color3.fromRGB(8, 10, 12)
			label.TextStrokeTransparency = 1
			label.TextTransparency = 1
			label.TextWrapped = true
			-- A long line wraps onto a second one rather than running off the edges.
			label.AutomaticSize = Enum.AutomaticSize.Y
			label.ZIndex = 3
			label.Text = if index == 1 then string.upper(text):gsub(".", "%0 "):sub(1, -2) else text
			-- Ticketed, so a later caption's list never sorts in among an earlier one's lines.
			label.LayoutOrder = ticket * 10 + index
			label.Parent = current.words
			table.insert(labels, label)
		end
	end
	local fadeIn = TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for index, label in ipairs(labels) do
		task.delay(0.4 + (index - 1) * 0.5, function()
			if label.Parent then
				TweenService:Create(label, fadeIn, { TextTransparency = 0, TextStrokeTransparency = 0.35 }):Play()
			end
		end)
	end
	task.delay(hold, function()
		for _, label in ipairs(labels) do
			if label.Parent then
				TweenService:Create(label, TweenInfo.new(1.4), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			end
		end
		-- The band goes with the last caption, not with one a newer caption has replaced.
		if current.queue == ticket and band and band:IsA("Frame") and band.Parent then
			TweenService:Create(band, TweenInfo.new(1.4), { BackgroundTransparency = 1 }):Play()
		end
	end)
end

-- A title low on the screen: `place` in spaced capitals, `line` under it, for `seconds` or for as long
-- as its words take to read twice, whichever is longer. If the last caption has not been up long
-- enough to read once, this one waits for it.
function Cinema.caption(place: string, line: string?, seconds: number?)
	local current = live
	if not current then
		return
	end
	local count = wordCount(place) + wordCount(line or "")
	local hold = math.max(seconds or CAPTION_SECONDS, READ_BASE + READ_WORD * count)
	local now = os.clock()
	local start = math.max(now, current.freeAt)
	current.freeAt = start + FIRST_BASE + FIRST_WORD * count
	current.readUntil = math.max(current.readUntil, start + hold + 1.4)
	current.queue += 1
	local ticket = current.queue
	local function show()
		if live == current then
			showCaption(current, ticket, place, line, hold)
		end
	end
	if start <= now + 0.02 then
		show()
	else
		task.delay(start - now, show)
	end
end

-- ===== THE SCENE'S OWN SOUNDS =====
--
-- Every ending is scored with sounds of its own (audio/gen_ending_sfx.py: the board letting you go, the
-- wind of the fall, the whirlpool's roar, the last chord). `name` is looked up in SoundService.StorySounds;
-- if it is not there, `fallback` (a built-in sound, slowed by `speed`) stands in, and with no fallback
-- nothing plays. A scene's sounds fade out when it finishes, unless `keep` (the last chord, which should
-- ring on past the bars opening). `pitch` scales whichever plays.
export type SoundOptions = { fallback: string?, speed: number?, looped: boolean?, keep: boolean?, pitch: number?,
	fadeIn: number?, alt: string?, altPitch: number? }

function Cinema.sound(name: string, volume: number, options: SoundOptions?): Sound?
	local folder = game:GetService("SoundService"):FindFirstChild("StorySounds")
	local own = folder and folder:FindFirstChild(name)
	local made: Sound
	-- ANOTHER OF THE STORY'S SOUNDS standing in, at its own pitch: the endings' chords fall back on the one
	-- EndChord, so one upload brings all four last notes back.
	local alt = options and options.alt and folder and folder:FindFirstChild(options.alt)
	if own and own:IsA("Sound") then
		made = own:Clone()
		made.PlaybackSpeed = (options and options.pitch) or 1
	elseif alt and alt:IsA("Sound") and options then
		made = alt:Clone()
		made.PlaybackSpeed = (options.altPitch or 1) * (options.pitch or 1)
	elseif options and options.fallback then
		made = Instance.new("Sound")
		made.SoundId = options.fallback
		made.PlaybackSpeed = (options.speed or 1) * (options.pitch or 1)
	else
		return nil
	end
	made.Name = "Scene_" .. name
	made.Looped = options ~= nil and options.looped == true
	local fadeIn = options and options.fadeIn
	made.Volume = if fadeIn then 0 else volume
	made.Parent = game:GetService("SoundService")
	made:Play()
	if fadeIn then
		TweenService:Create(made, TweenInfo.new(fadeIn, Enum.EasingStyle.Sine), { Volume = volume }):Play()
	end
	local current = live
	if current and not (options and options.keep) then
		table.insert(current.sounds, made)
	elseif not made.Looped then
		-- Gone once it has played out: a fixed twenty seconds cut the Sky Pools' song off halfway (your test of
		-- 2026-10-22), and a sound that never loads is cleared after two minutes. Faded at once if the lobby takes you.
		table.insert(kept, made)
		made.Ended:Once(function()
			local index = table.find(kept, made)
			if index then
				table.remove(kept, index)
			end
			made:Destroy()
		end)
		game:GetService("Debris"):AddItem(made, 120)
	end
	return made
end

-- One of the scene's sounds faded out over `seconds` and gone.
function Cinema.fade(s: Sound?, seconds: number?)
	if not (s and s.Parent) then
		return
	end
	local out = TweenService:Create(s, TweenInfo.new(seconds or 1.5, Enum.EasingStyle.Sine), { Volume = 0 })
	out.Completed:Once(function()
		s:Destroy()
	end)
	out:Play()
end

-- Seconds until every caption asked for so far has been read (0 when there is nothing to read).
function Cinema.readingLeft(): number
	local current = live
	return if current then math.max(0, current.readUntil - os.clock()) else 0
end

-- THE STORY IS TOLD: once the captions are read, the server hears that this ending has been watched
-- (and may take you to the lobby), and the banner may come up. The scene may go on holding its last
-- shot; finish() gives the camera back.
function Cinema.done()
	local current = live
	if not current or current.told then
		return
	end
	task.spawn(function()
		while live == current and os.clock() < current.readUntil do
			task.wait(0.2)
		end
		if not current.told then
			current.told = true
			if current.ending then
				tell("done")
			end
		end
	end)
end

-- Everything given back. A caption still being read holds the last shot until it has been, unless
-- `now` (the lobby has already taken you, or the scene has failed).
function Cinema.finish(now: boolean?)
	local current = live
	if not current then
		return
	end
	if not now and os.clock() < current.readUntil then
		if not current.finishing then
			current.finishing = true
			task.delay(current.readUntil - os.clock(), function()
				if live == current then
					Cinema.finish(true)
				end
			end)
		end
		return
	end
	live = nil
	if current.ending and not current.told then
		current.told = true
		tell("done")
	end
	-- The scene's own sounds, faded out with it.
	for _, s in ipairs(current.sounds) do
		Cinema.fade(s, 2.5)
	end
	pcall(function()
		RunService:UnbindFromRenderStep(SHOW)
	end)
	if current.focus then
		current.focus:Destroy()
	end
	if current.impactFx then
		current.impactFx:Destroy()
	end
	local camera = workspace.CurrentCamera
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if camera then
		-- Over the shoulder first, so the default camera carries on from a sensible place.
		if root and root:IsA("BasePart") then
			local flat = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
			flat = if flat.Magnitude > 0.05 then flat.Unit else Vector3.new(0, 0, -1)
			local at = root.Position + Vector3.new(0, 1.5, 0)
			camera.CFrame = CFrame.lookAt(at - flat * 11 + Vector3.new(0, 3.5, 0), at)
		end
		camera.CameraType = Enum.CameraType.Custom
		camera.FieldOfView = current.fov
		if humanoid then
			camera.CameraSubject = humanoid
		end
	end
	local found = current.controls
	if found then
		pcall(function()
			found:Enable()
		end)
	end
	holdStill(false)
	pcall(function()
		ProximityPromptService.Enabled = true
	end)
	local open = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	TweenService:Create(current.top, open, { Size = UDim2.fromScale(1, 0) }):Play()
	TweenService:Create(current.bottom, open, { Size = UDim2.fromScale(1, 0) }):Play()
	TweenService:Create(current.veil, open, { BackgroundTransparency = 1 }):Play()
	task.delay(4, function()
		current.gui:Destroy()
	end)
end

Cinema.STAMP = "87246380"
return Cinema
