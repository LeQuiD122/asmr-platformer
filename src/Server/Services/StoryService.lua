--!strict
-- ServerScriptService/Services/StoryService.lua
-- The story's hand in each level: the words that open it, the things left lying about that tell the
-- rest of it, and the people on the levels that have no service of their own to stand them (City
-- Shore; and the Corporation Baths, whose people stand on the route rather than in the building). The
-- story itself -- Harrow Bay, the day the sea came in, and the key holder who never came -- is told in
-- Townsfolk.
--
-- === The words that open a level ===
--
-- Low on the screen as the run starts, the way a film puts a place and a time under its first shot:
-- which level it is, where you are and when. The same day each time, later each time, and a line of
-- what the people there would call the news. It fades in, holds for twelve seconds, and goes.
--
-- === The nooks, and the things to take ===
--
-- The route is for pressing things, so the story is kept OFF it: in NOOKS, small balconies built out
-- from the sides of chunks, each with a short gangway, a rail and a lamp you can see from the route.
-- In them: notice boards (the Harrow Bay Gazette, a council notice, a guest list, a tide table, the
-- waterworks rota), a letter left on a crate, MR BARLOW'S PRY BAR in the first one, and a few of the
-- KEEPSAKES, the things the levels are made of, sitting on stools where somebody put them down.
-- Take any of them (E) and it goes into your journal (JournalService): nothing comes up over the
-- level, and you read it when you choose to. One notice, in the baths, has your name on it. NOTES,
-- below, has every word.
--
-- === Things to find (Interactables) ===
--
-- And a SECRET on every level that the bar opens, told as a short scene when it is found:
--
--   City Shore      THE SIREN TOWER, standing out of the sea in the middle of the spiral, a footbridge
--                   to it from a chunk halfway up. Loose bricks in the Siren Room's wall.
--   Sky Pools       a tin box on the floor of the first pool, bubbles coming off it.
--   Sunken City     a staff locker in the aquarium gallery, shut since 1979.
--   Flooded Halls   the staff lockers on the gangway (yours is number 3), and a loose board by the far
--                   rail, over the shaft.
--
-- The level services only mark where (parts tagged StorySpot, with a Kind); everything is built here.
--
-- === The Corporation Baths' people ===
--
--   MRS VENN, the baths attendant, behind her ticket desk on the first stable chunk.
--   TOBI OKAFOR, Pip's dad, on a bench on a stable chunk about halfway, his red towel round his neck.
--   MR BARLOW, the night engineer, with a lit lantern on the gangway to the flume
--        (FloodedHallsService writes where: the halls' EngineerSpot).
--
-- === City Shore's people ===
--
--   SAL, at the start, with her ice cream cart: on the first stable chunk's cap, to one side.
--   PIP, eight, with her bucket and the sandcastle she is still building: on a stable chunk about
--        halfway up, to one side. Waiting for her dad, who went to find the key holder.
--   (MAREN the lifeguard is DiveFinaleService's, on the dive deck.)
--
-- Both stand on the SurfaceCap of a stable chunk -- the one surface in a level that never deforms --
-- well inside its edge, and everything of theirs is CanCollide off, so nobody is ever blocked by them.
-- They go with Workspace.Levels, as the chunks do.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local townsModule = script.Parent:FindFirstChild("Townsfolk") or script.Parent:WaitForChild("Townsfolk", 5)
local Townsfolk: any = if townsModule and townsModule:IsA("ModuleScript") then require(townsModule) else nil
-- The things you can put your hands on, and the secrets in them (letters, the pry bar, lockers, loose
-- bricks and boards). Optional: without it the notice boards still stand, and nothing else is hidden.
local interactModule = script.Parent:FindFirstChild("Interactables") or script.Parent:WaitForChild("Interactables", 5)
local Interactables: any = if interactModule and interactModule:IsA("ModuleScript") then require(interactModule) else nil
local CollectionService = game:GetService("CollectionService")

local StoryService = {}

-- Where and when, by level id (which is the order they happen in). No double dashes in anything shown.
local OPENINGS: { [number]: { string } } = {
	[1] = { "Harrow Bay", "14 August. 9:14 in the morning. The tide has not gone out in three days." },
	[2] = { "The Sky Pools, Harrow Bay", "14 August. Three o'clock. Nobody has gone down since the street went under." },
	[3] = { "Harrow Bay", "14 August. Eight minutes to midnight. The pumps never started." },
	[4] = { "The Corporation Baths", "14 August. Four minutes to midnight. Under the pumping station, where the clocks are moving again." },
}

-- THE THINGS TO READ, by level id: a title (what the board says from the route) and the words on it.
-- `%s` in a body is the reader's own name, in capitals. No double dashes.
type Note = { title: string, body: string, lying: boolean? }
local NOTES: { [number]: { Note } } = {
	[1] = {
		{ title = "Harrow Bay Gazette", body = "14 AUGUST. TIDE STAYS IN FOR THIRD DAY.\n\nThe Waterworks say the harbour pumps "
			.. "will be running by noon. Residents are asked to keep off the front until the siren has been tested. "
			.. "The key holder for the outfall gates could not be reached for comment." },
		{ title = "Notice from the Corporation", body = "FLOOD SIREN.\n\nThe siren will be tested at twelve noon each "
			.. "day until further notice. If the siren sounds at midnight, it is not a test. Make your way to high "
			.. "ground. The Sky Pools on the roof of the Promenade Hotel are open to everyone." },
		{ title = "A child's drawing", lying = true, body = "A crayon drawing, left under a stone so it would not blow away.\n\n"
			.. "My dad. The key man. The gates. The sea going out.\n\nBy Pip Okafor, age 8." },
		{ title = "Novelty Works list", body = "HARROW BAY NOVELTY WORKS, MILL LANE. SUMMER LIST.\n\nBubble wrap by the "
			.. "yard. Green slime in tins. Squeeze toys for worriers. Kinetic sand, as used by Pip Okafor.\n\n"
			.. "Everything on this list is made to be pressed." },
	},
	[2] = {
		{ title = "An invitation", body = "YOU ARE INVITED to the Rooftop Party at the Sky Pools, from 11 August until "
			.. "the water goes down.\n\nDress: swimwear. Towels provided. Music by Rudy.\n\nThe slide is the only "
			.. "way down." },
		{ title = "The guest list", body = "Sal. Maren. The Okafors (3). Rudy (music). Everyone from the front.\n\n"
			.. "NOT ON THE LIST: the key holder. See the other list, at the pumps." },
		{ title = "A note on a lounger", lying = true, body = "Gone down to find the man with the keys. Back by three. Keep my seat.\n\nT." },
		{ title = "Promenade Hotel", body = "A NOTE FROM THE MANAGEMENT.\n\nThe roof is open for the party until the water "
			.. "goes down. Guests are asked not to use the stairs. They only go down to the street, and the street is "
			.. "not there any more.\n\nThe slide is the way down." },
	},
	[3] = {
		{ title = "Tide table, August", body = "HARBOUR HIGH WATER.\n\n11th: 11:52 PM\n12th: 11:52 PM\n13th: 11:52 PM\n"
			.. "14th: 11:52 PM\n\nLow water: none recorded." },
		{ title = "Waterworks notice", body = "Outfall gates 1 and 2 have been opened by hand. Outfall 3 can only be "
			.. "opened with the key holder's key.\n\nKey holder on call, 14 August: the name has been scratched out, "
			.. "hard, many times." },
		{ title = "Missing", lying = true, body = "HAVE YOU SEEN OUR PEOPLE?\n\nMany went down the harbour drain on 14 August to fetch "
			.. "the key holder. If you find them, please send them home.\n\nHarrow Bay" },
		{ title = "Key holders, Outfall 3", body = "HARROW BAY WATERWORKS. KEY HOLDERS, 1911 TO DATE.\n\nJ. Harrow, 1911.\n"
			.. "A. Wick, 1946.\nE. Marsh, 1979. Did not come back up.\n%s, 14 August." },
	},
	[4] = {
		{ title = "Rules of the Baths", body = "HARROW BAY CORPORATION BATHS.\n\nNo running. No diving. No bathing after "
			.. "midnight. The baths are warmed by the engines of the pumping station above. When the engines stop, so "
			.. "do the baths.\n\nStaff only beyond the flume." },
		{ title = "A postcard", lying = true, body = "Dear Pip,\n\nThe halls go on and on. Every time I think I've found the gates, "
			.. "there is another pool. Tell Mum I'll be back by three.\n\nLove, Dad" },
		{ title = "Waterworks rota", body = "NIGHT ENGINEER: Barlow.\nKEY HOLDER, OUTFALL 3: %s.\n\n14 August: NOT "
			.. "CLOCKED IN.\n15 August: (blank)" },
		{ title = "Lost property", body = "CORPORATION BATHS. LOST PROPERTY, 14 AUGUST.\n\nOne red towel (T. Okafor). One bar "
			.. "of soap, used. One bucket and spade. One front door key on a green ribbon, marked HILL HOUSE.\n\nNot "
			.. "collected." },
	},
}

local SKIN = Color3.fromRGB(226, 192, 158)

-- THE WORDS THAT OPEN A LEVEL, on one player's screen.
function StoryService.opening(player: Player, levelId: number)
	local words = OPENINGS[levelId]
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not words or not playerGui then
		return
	end
	local old = playerGui:FindFirstChild("StoryOpening")
	if old then
		old:Destroy()
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "StoryOpening"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 20
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 1)
	holder.Position = UDim2.new(0.5, 0, 0.86, 0)
	holder.Size = UDim2.new(0.8, 0, 0, 86)
	holder.Parent = gui
	local list = Instance.new("UIListLayout")
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.Padding = UDim.new(0, 4)
	list.Parent = holder
	local labels = {}
	-- THE LEVEL'S NUMBER over its place: they are played in the order they happen.
	for index, text in ipairs({ ("Level %d"):format(levelId), words[1], words[2] }) do
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.new(1, 0, 0, if index == 2 then 28 elseif index == 1 then 18 else 22)
		label.Font = if index == 3 then Enum.Font.Gotham else Enum.Font.GothamBold
		label.TextSize = if index == 2 then 24 elseif index == 1 then 14 else 18
		label.TextColor3 = if index == 2 then Color3.fromRGB(246, 242, 230)
			elseif index == 1 then Color3.fromRGB(200, 204, 198) else Color3.fromRGB(214, 216, 210)
		label.TextStrokeTransparency = 0.55
		label.TextTransparency = 1
		label.TextStrokeColor3 = Color3.fromRGB(10, 12, 14)
		label.TextWrapped = true
		-- A long line wraps onto a second one on a narrow screen rather than being cut off.
		label.AutomaticSize = Enum.AutomaticSize.Y
		label.Text = if index < 3 then (string.upper(text):gsub(".", "%0 ")):sub(1, -2) else text
		label.LayoutOrder = index
		label.Parent = holder
		table.insert(labels, label)
	end
	gui.Parent = playerGui
	task.spawn(function()
		task.wait(1.2)
		for index, label in ipairs(labels) do
			TweenService:Create(label, TweenInfo.new(1.2 + index * 0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ TextTransparency = 0, TextStrokeTransparency = 0.55 }):Play()
		end
		task.wait(12)
		for _, label in ipairs(labels) do
			TweenService:Create(label, TweenInfo.new(1.6), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		end
		task.wait(1.8)
		gui:Destroy()
	end)
end

-- A part that stands for something: anchored, never in anyone's way.
local function prop(parent: Instance, name: string, size: Vector3, cf: CFrame, colour: Color3, material: Enum.Material,
	shape: Enum.PartType?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cf
	part.Color = colour
	part.Material = material
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		part.Shape = shape
	end
	part.Parent = parent
	return part
end

-- The cap of a placed chunk, if it is a stable one: the plate you stand on.
local function stableCap(entry: any): BasePart?
	local definitions = ReplicatedStorage:FindFirstChild("Shared")
	local module = definitions and definitions:FindFirstChild("ChunkDefinitions")
	if not (module and module:IsA("ModuleScript")) then
		return nil
	end
	local def = (require(module) :: any)[entry.chunkId]
	if not (def and def.category == "stable" and entry.model) then
		return nil
	end
	local cap = entry.model:FindFirstChild("SurfaceCap", true)
	return if cap and cap:IsA("BasePart") then cap else nil
end

-- A spot on a stable chunk's cap: to one side, `inset` studs inside its edge, facing across the route.
local function besideRoute(cap: BasePart, side: number, inset: number): CFrame
	local capCF = cap.CFrame
	local across = if cap.Size.X >= cap.Size.Z then capCF.RightVector else capCF.LookVector
	local half = math.min(cap.Size.X, cap.Size.Z) / 2
	local top = cap.Position.Y + cap.Size.Y / 2
	local at = Vector3.new(cap.Position.X, top, cap.Position.Z) + across * side * (half - inset)
	local inward = Vector3.new(-across.X * side, 0, -across.Z * side)
	return CFrame.lookAt(at, at + inward)
end

-- SAL AND HER CART.
local function sal(parent: Instance, cap: BasePart)
	local feet = besideRoute(cap, 1, 2.2)
	local cart = feet * CFrame.new(2.8, 0, -0.6)
	prop(parent, "IceCreamCart", Vector3.new(2.2, 2.4, 3.6), cart * CFrame.new(0, 1.9, 0), Color3.fromRGB(246, 240, 226), Enum.Material.SmoothPlastic)
	for _, dz in ipairs({ -1.3, 1.3 }) do
		prop(parent, "CartWheel", Vector3.new(0.4, 1.4, 1.4), cart * CFrame.new(0, 0.7, dz), Color3.fromRGB(60, 62, 66),
			Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	end
	-- The striped awning on two poles that stand on the cart.
	for _, dz in ipairs({ -1.5, 1.5 }) do
		prop(parent, "AwningPole", Vector3.new(0.2, 3, 0.2), cart * CFrame.new(0.8, 4.6, dz), Color3.fromRGB(200, 200, 196), Enum.Material.Metal)
	end
	for stripe = 0, 4 do
		prop(parent, "Awning", Vector3.new(2.8, 0.15, 0.8), cart * CFrame.new(0.2, 6.15, -1.6 + stripe * 0.8) * CFrame.Angles(0, 0, math.rad(-8)),
			if stripe % 2 == 0 then Color3.fromRGB(236, 120, 150) else Color3.fromRGB(250, 246, 240), Enum.Material.Fabric)
	end
	local sign = prop(parent, "CartSign", Vector3.new(0.1, 0.8, 2.6), cart * CFrame.new(-1.15, 2.4, 0), Color3.fromRGB(236, 120, 150),
		Enum.Material.SmoothPlastic)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Left
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.Parent = sign
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.TextScaled = true
	text.Font = Enum.Font.GothamBold
	text.TextColor3 = Color3.fromRGB(255, 255, 255)
	text.Text = "SAL'S ICES"
	text.Parent = gui
	local npc = Townsfolk.spawn(parent, "Sal", feet, "stand", { SKIN, Color3.fromRGB(236, 120, 150), Color3.fromRGB(70, 74, 96) })
	if npc then
		Townsfolk.wear(npc, "Apron", Vector3.new(1.7, 1.6, 0.1), Color3.fromRGB(250, 246, 240), "UpperTorso", CFrame.new(0, -0.3, -0.55))
		Townsfolk.wear(npc, "Scoop", Vector3.new(0.2, 1.1, 0.2), Color3.fromRGB(200, 200, 196), "RightHand", CFrame.new(0, -0.4, -0.3))
	end
end

-- PIP, HER BUCKET, AND THE SANDCASTLE.
local function pip(parent: Instance, cap: BasePart)
	local feet = besideRoute(cap, -1, 2.4)
	local castle = feet * CFrame.new(0, 0, -2.2)
	local sand = Color3.fromRGB(222, 196, 140)
	prop(parent, "Sandcastle", Vector3.new(1.2, 2.4, 2.4), castle * CFrame.new(0, 0.6, 0) * CFrame.Angles(0, 0, math.pi / 2), sand,
		Enum.Material.Sand, Enum.PartType.Cylinder)
	for _, corner in ipairs({ { -0.9, -0.9 }, { 0.9, -0.9 }, { -0.9, 0.9 }, { 0.9, 0.9 } }) do
		prop(parent, "SandTower", Vector3.new(1.6, 0.8, 0.8), castle * CFrame.new(corner[1], 1.4, corner[2]) * CFrame.Angles(0, 0, math.pi / 2),
			sand, Enum.Material.Sand, Enum.PartType.Cylinder)
	end
	prop(parent, "SandFlag", Vector3.new(0.08, 1.2, 0.08), castle * CFrame.new(0, 2, 0), Color3.fromRGB(120, 100, 80), Enum.Material.Wood)
	prop(parent, "SandFlagCloth", Vector3.new(0.05, 0.4, 0.6), castle * CFrame.new(0, 2.4, 0.3), Color3.fromRGB(230, 70, 60), Enum.Material.Fabric)
	local npc = Townsfolk.spawn(parent, "Pip", feet, "stand", { Color3.fromRGB(150, 104, 74), Color3.fromRGB(250, 214, 90), Color3.fromRGB(70, 130, 190) })
	if npc then
		Townsfolk.wear(npc, "Bucket", Vector3.new(0.9, 0.8, 0.8), Color3.fromRGB(230, 70, 60), "RightHand", CFrame.new(0, -0.7, 0),
			Enum.PartType.Cylinder)
		Townsfolk.wear(npc, "SunHat", Vector3.new(0.15, 2, 2), Color3.fromRGB(250, 246, 236), "Head",
			CFrame.new(0, 0.55, 0) * CFrame.Angles(0, 0, math.pi / 2), Enum.PartType.Cylinder)
	end
end

-- MRS VENN AND HER TICKET DESK: the desk between her and the route, a sign on its front.
local function venn(parent: Instance, cap: BasePart)
	local feet = besideRoute(cap, 1, 2.6)
	local desk = feet * CFrame.new(0, 0, -1.7)
	local wood = Color3.fromRGB(122, 90, 62)
	prop(parent, "TicketDesk", Vector3.new(3.4, 2.3, 1.2), desk * CFrame.new(0, 1.15, 0), wood, Enum.Material.WoodPlanks)
	prop(parent, "DeskTop", Vector3.new(3.7, 0.15, 1.45), desk * CFrame.new(0, 2.37, 0), Color3.fromRGB(96, 70, 48), Enum.Material.Wood)
	prop(parent, "TicketRoll", Vector3.new(0.5, 0.45, 0.45), desk * CFrame.new(1.1, 2.67, 0) * CFrame.Angles(0, 0, math.pi / 2),
		Color3.fromRGB(236, 214, 150), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	prop(parent, "DeskBell", Vector3.new(0.3, 0.5, 0.5), desk * CFrame.new(-1.1, 2.6, 0) * CFrame.Angles(0, 0, math.pi / 2),
		Color3.fromRGB(214, 180, 90), Enum.Material.Metal, Enum.PartType.Cylinder)
	local sign = prop(parent, "DeskSign", Vector3.new(3, 0.9, 0.1), desk * CFrame.new(0, 1.6, -0.66), Color3.fromRGB(236, 230, 212),
		Enum.Material.SmoothPlastic)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.Parent = sign
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.TextScaled = true
	text.Font = Enum.Font.GothamBold
	text.TextColor3 = Color3.fromRGB(40, 60, 70)
	text.Text = "CORPORATION BATHS. TICKETS"
	text.Parent = gui
	Townsfolk.spawn(parent, "Venn", feet, "stand", { SKIN, Color3.fromRGB(116, 138, 108), Color3.fromRGB(70, 70, 82) })
end

-- TOBI, on a bench, with his red towel round his neck.
local function tobi(parent: Instance, cap: BasePart)
	local bench = besideRoute(cap, -1, 2.4)
	local wood = Color3.fromRGB(150, 112, 74)
	prop(parent, "BenchSeat", Vector3.new(4.2, 0.25, 1.3), bench * CFrame.new(0, 1.5, 0.2), wood, Enum.Material.WoodPlanks)
	for _, x in ipairs({ -1.7, 1.7 }) do
		prop(parent, "BenchLeg", Vector3.new(0.3, 1.38, 1.1), bench * CFrame.new(x, 0.69, 0.2), Color3.fromRGB(70, 74, 78),
			Enum.Material.Metal)
	end
	-- A sitter's `feet` is the top of what they sit on (Townsfolk.spawn).
	local npc = Townsfolk.spawn(parent, "Tobi", bench * CFrame.new(0, 1.625, 0.35), "sit",
		{ Color3.fromRGB(120, 84, 60), Color3.fromRGB(120, 84, 60), Color3.fromRGB(40, 70, 140) })
	if npc then
		local red = Color3.fromRGB(196, 40, 40)
		Townsfolk.wear(npc, "Towel", Vector3.new(2.1, 0.45, 1.25), red, "UpperTorso", CFrame.new(0, 0.78, 0))
		for _, x in ipairs({ -0.5, 0.5 }) do
			Townsfolk.wear(npc, "TowelEnd", Vector3.new(0.5, 1.3, 0.12), red, "UpperTorso", CFrame.new(x, 0.05, -0.56))
		end
	end
end

-- MR BARLOW, the night engineer, on the gangway with his lantern (the halls say where).
local function barlow(parent: Instance)
	local halls = workspace:FindFirstChild("FloodedHalls")
	local spot = halls and halls:GetAttribute("EngineerSpot")
	if typeof(spot) ~= "CFrame" then
		return
	end
	local npc = Townsfolk.spawn(parent, "Barlow", spot, "stand",
		{ Color3.fromRGB(214, 170, 140), Color3.fromRGB(62, 82, 112), Color3.fromRGB(62, 82, 112) })
	if not npc then
		return
	end
	local ink = Color3.fromRGB(40, 40, 44)
	Townsfolk.wear(npc, "Cap", Vector3.new(0.35, 1.32, 1.32), Color3.fromRGB(52, 62, 80), "Head",
		CFrame.new(0, 0.55, 0.02) * CFrame.Angles(0, 0, math.pi / 2), Enum.PartType.Cylinder)
	Townsfolk.wear(npc, "CapPeak", Vector3.new(1.05, 0.08, 0.5), Color3.fromRGB(40, 46, 60), "Head", CFrame.new(0, 0.42, -0.72))
	Townsfolk.wear(npc, "LanternHandle", Vector3.new(0.12, 0.7, 0.12), ink, "LeftHand", CFrame.new(0, -0.45, 0))
	Townsfolk.wear(npc, "LanternCap", Vector3.new(0.7, 0.18, 0.7), ink, "LeftHand", CFrame.new(0, -0.85, 0))
	local glass = Townsfolk.wear(npc, "LanternGlass", Vector3.new(0.6, 0.8, 0.6), Color3.fromRGB(255, 226, 170), "LeftHand",
		CFrame.new(0, -1.35, 0))
	Townsfolk.wear(npc, "LanternBase", Vector3.new(0.72, 0.16, 0.72), ink, "LeftHand", CFrame.new(0, -1.83, 0))
	if glass then
		glass.Transparency = 0.35
		-- A real light, and a small one: a lantern on a gangway, not a floodlight.
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 200, 130)
		light.Brightness = 0.9
		light.Range = 14
		light.Shadows = false
		light.Parent = glass
	end
end

-- ===== THE NOOKS: THE OPTIONAL PLACES OFF THE ROUTE =====
--
-- THE ROUTE IS FOR PRESSING THINGS. Notice boards and letters used to stand on the stable chunks you
-- walk across, and every few chunks the story was in your way. So everything to read and every
-- keepsake is kept OFF the route now, in a NOOK: a small balcony built out from the side of a chunk,
-- with a short gangway across to it, a rail round it and a lamp on a post. It is somewhere you choose
-- to go; the lamp is what catches your eye from the route (a real light, and a small one). On some
-- runs a string of bunting runs out to it from the chunk as well, so now and then the level leads you
-- there on its own, and now and then it leaves you to notice.
--
-- HELD UP, NOT HUNG IN THE AIR. A nook is a cantilever: two steel joists under its floor run back into
-- the side of the chunk it stands off, and a strut under each goes from the joist's outer end back down
-- to the chunk's side. It is built only where it fits: the nook and its gangway, and the air round
-- them, must be clear of everything else in the level (asked of the engine, not guessed), and clear of
-- the other nooks. A chunk where neither side fits gets no nook.
--
-- In each nook's own frame: +X out from the route, Y up, the floor's top at y = 0.
local NOOK = {
	W = 12, -- along the route
	D = 10, -- out from it
	GAP = 3, -- the air between the chunk's side and the nook
	THICK = 0.8,
	RAIL = 3.2,
}
type Nook = { frame: CFrame, index: number, taken: { [string]: boolean } }
type Style = { floor: Color3, floorMaterial: Enum.Material, trim: Color3, rail: Color3, lamp: Color3 }
local STYLES: { [string]: Style } = {
	cityShore = {
		floor = Color3.fromRGB(226, 206, 180),
		floorMaterial = Enum.Material.WoodPlanks,
		trim = Color3.fromRGB(120, 176, 190),
		rail = Color3.fromRGB(244, 244, 238),
		lamp = Color3.fromRGB(255, 214, 160),
	},
	skyPools = {
		floor = Color3.fromRGB(222, 230, 236),
		floorMaterial = Enum.Material.CeramicTiles,
		trim = Color3.fromRGB(186, 172, 240),
		rail = Color3.fromRGB(220, 226, 236),
		lamp = Color3.fromRGB(255, 236, 206),
	},
	sunkenCity = {
		floor = Color3.fromRGB(102, 90, 74),
		floorMaterial = Enum.Material.WoodPlanks,
		trim = Color3.fromRGB(70, 74, 72),
		rail = Color3.fromRGB(96, 72, 56),
		lamp = Color3.fromRGB(255, 200, 140),
	},
	floodedHalls = {
		floor = Color3.fromRGB(214, 222, 214),
		floorMaterial = Enum.Material.CeramicTiles,
		trim = Color3.fromRGB(96, 150, 146),
		rail = Color3.fromRGB(196, 204, 204),
		lamp = Color3.fromRGB(226, 240, 236),
	},
}
local NOOK_LIGHTS = 0.85 -- the lamp's brightness: enough to be seen from the route, no more

-- A part of a nook: anchored, and SOLID where it says (floor, gangway, rails), so a nook is somewhere
-- you can stand and cannot walk off.
local function nookPart(parent: Instance, name: string, size: Vector3, cf: CFrame, colour: Color3, material: Enum.Material,
	solid: boolean, shape: Enum.PartType?): Part
	local part = prop(parent, name, size, cf, colour, material, shape)
	part.CanCollide = solid
	part.CanQuery = true
	return part
end

-- A rod from `a` to `b`, `thick` across.
local function strut(parent: Instance, name: string, a: Vector3, b: Vector3, thick: number, colour: Color3, solid: boolean): Part
	local length = (b - a).Magnitude
	return nookPart(parent, name, Vector3.new(thick, thick, length), CFrame.lookAt((a + b) / 2, b), colour, Enum.Material.Metal, solid)
end

-- Where a chunk's walkable top is at (x, z), near `near`: a ray down onto the chunk alone.
local function topOf(model: Instance, x: number, z: number, near: number): number?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { model }
	local hit = workspace:Raycast(Vector3.new(x, near + 6, z), Vector3.new(0, -12, 0), params)
	return if hit and math.abs(hit.Position.Y - near) < 4 then hit.Position.Y else nil
end

-- Is the box (`cf`, `size`) clear of everything in the level but `ignore`, and of the nooks already
-- built (`boxes`)?
local function clearBox(cf: CFrame, size: Vector3, ignore: { Instance }, boxes: { { cf: CFrame, size: Vector3 } }): boolean
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local skip = table.clone(ignore)
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			table.insert(skip, player.Character)
		end
	end
	params.FilterDescendantsInstances = skip
	for _, part in ipairs(workspace:GetPartBoundsInBox(cf, size, params)) do
		-- Anything solid, or anything you can see that is not the size of a sea or a cloud bank (the
		-- water and the cloud sea are single plates hundreds of studs across, and a nook may stand over
		-- them).
		if part.CanCollide or (part.Transparency < 0.95 and part.Size.Magnitude < 150) then
			return false
		end
	end
	for _, box in ipairs(boxes) do
		local rel = box.cf:PointToObjectSpace(cf.Position)
		local reach = (size + box.size) / 2
		if math.abs(rel.X) < reach.X + 2 and math.abs(rel.Y) < reach.Y and math.abs(rel.Z) < reach.Z + 2 then
			return false
		end
	end
	return true
end

-- A NOOK off chunk `index`, on whichever side fits (the side away from the level's middle first, where
-- there is a middle). Returns the nook, or nil where neither side does.
local function nookOff(parent: Instance, chunks: { any }, index: number, backdrop: string, centre: Vector3?,
	boxes: { { cf: CFrame, size: Vector3 } }, rng: Random): Nook?
	local entry = chunks[index]
	local model = entry and entry.model
	if not (model and model:IsA("Model")) then
		return nil
	end
	local boxCF, boxSize = model:GetBoundingBox()
	local before = chunks[math.max(1, index - 1)].model
	local after = chunks[math.min(#chunks, index + 1)].model
	local run = if before and after then (after:GetPivot().Position - before:GetPivot().Position) else boxCF.LookVector
	run = Vector3.new(run.X, 0, run.Z)
	if run.Magnitude < 0.1 then
		run = Vector3.new(boxCF.LookVector.X, 0, boxCF.LookVector.Z)
	end
	if run.Magnitude < 0.1 then
		return nil
	end
	run = run.Unit
	local across = Vector3.new(-run.Z, 0, run.X)
	local middle = boxCF.Position
	local surface = if typeof(entry.surfaceY) == "number" then entry.surfaceY else middle.Y + boxSize.Y / 2
	surface = topOf(model, middle.X, middle.Z, surface) or surface
	local sides = { 1, -1 }
	if centre then
		-- Out, away from the middle, first: a nook on the inside of a spiral is under the next turn.
		local outward = Vector3.new(middle.X - centre.X, 0, middle.Z - centre.Z)
		if outward.Magnitude > 0.1 and outward:Dot(across) < 0 then
			sides = { -1, 1 }
		end
	elseif rng:NextNumber() < 0.5 then
		sides = { -1, 1 }
	end
	local style = STYLES[backdrop] or STYLES.cityShore
	for _, side in ipairs(sides) do
		local out = across * side
		-- How far the chunk reaches this way (its box), and where its walkable edge actually is.
		local half = math.abs(boxCF.RightVector:Dot(out)) * boxSize.X / 2 + math.abs(boxCF.UpVector:Dot(out)) * boxSize.Y / 2
			+ math.abs(boxCF.LookVector:Dot(out)) * boxSize.Z / 2
		local edge = half - 1
		for step = 1, math.floor(half * 2) do
			local probe = middle + out * (step * 0.5)
			if topOf(model, probe.X, probe.Z, surface) then
				edge = step * 0.5
			end
		end
		edge = math.min(edge, half)
		local inner = half + NOOK.GAP
		local centreAt = Vector3.new(middle.X, surface, middle.Z) + out * (inner + NOOK.D / 2)
		local frame = CFrame.fromMatrix(centreAt, out, Vector3.yAxis)
		local body = CFrame.fromMatrix(centreAt + Vector3.new(0, 3.5, 0), out, Vector3.yAxis)
		local gangLong = inner - edge + 1.2
		local gangAt = Vector3.new(middle.X, surface + 3.5, middle.Z) + out * (edge + gangLong / 2 - 0.6)
		if clearBox(body, Vector3.new(NOOK.D + 3, 8.6, NOOK.W + 3), { model }, boxes)
			and clearBox(CFrame.fromMatrix(gangAt, out, Vector3.yAxis), Vector3.new(math.max(0.5, gangLong - 2.4), 6.5, 5),
				{ model }, boxes)
			and clearBox(frame * CFrame.new(-NOOK.D / 4, -3.5, 0), Vector3.new(NOOK.D / 2 + 2, 5, NOOK.W), { model }, boxes) then
			table.insert(boxes, { cf = body, size = Vector3.new(NOOK.D + 3, 8.6, NOOK.W + 3) })
			local folder = Instance.new("Model")
			folder.Name = "Nook"
			folder.Parent = parent
			-- THE FLOOR, with a trim round it in the level's colour.
			nookPart(folder, "NookFloor", Vector3.new(NOOK.D, NOOK.THICK, NOOK.W), frame * CFrame.new(0, -NOOK.THICK / 2, 0), style.floor,
				style.floorMaterial, true)
			for _, z in ipairs({ -1, 1 }) do
				nookPart(folder, "NookTrim", Vector3.new(NOOK.D + 0.3, 0.3, 0.3), frame * CFrame.new(0, -NOOK.THICK - 0.1, z * NOOK.W / 2),
					style.trim, Enum.Material.SmoothPlastic, false)
			end
			nookPart(folder, "NookTrim", Vector3.new(0.3, 0.3, NOOK.W + 0.3), frame * CFrame.new(NOOK.D / 2, -NOOK.THICK - 0.1, 0),
				style.trim, Enum.Material.SmoothPlastic, false)
			-- THE GANGWAY across the gap, its near end resting on the chunk.
			local gangCentre = -NOOK.D / 2 - gangLong / 2 + 0.4
			nookPart(folder, "NookGangway", Vector3.new(gangLong, 0.4, 4), frame * CFrame.new(gangCentre, -0.18, 0), style.floor,
				style.floorMaterial, true)
			-- THE BRACKETS: joists back into the chunk's side, and a strut down to it under each.
			local side0 = -NOOK.D / 2 - (inner - edge) -- the chunk's edge, in the nook's frame
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Include
			params.FilterDescendantsInstances = { model }
			for _, z in ipairs({ -NOOK.W / 2 + 1.5, NOOK.W / 2 - 1.5 }) do
				local joistFrom = frame * Vector3.new(side0 - 0.8, -NOOK.THICK - 0.3, z)
				local joistTo = frame * Vector3.new(NOOK.D / 2 - 0.5, -NOOK.THICK - 0.3, z)
				strut(folder, "NookJoist", joistFrom, joistTo, 0.5, style.trim, false)
				-- The strut's foot: on the chunk's side, as deep as the chunk goes there (asked of it).
				local foot = frame * Vector3.new(side0 + 0.2, -NOOK.THICK - 1.2, z)
				for _, depth in ipairs({ 4, 3, 2.2 }) do
					local from = frame * Vector3.new(side0 + 2.5, -NOOK.THICK - depth, z)
					local hit = workspace:Raycast(from, frame:VectorToWorldSpace(Vector3.new(-4, 0, 0)), params)
					if hit then
						foot = hit.Position
						break
					end
				end
				strut(folder, "NookStrut", frame * Vector3.new(NOOK.D / 2 - 1, -NOOK.THICK - 0.3, z), foot, 0.4, style.trim, false)
			end
			-- THE RAIL, on the three outer sides and on the inner side but for the gangway's opening, and along
			-- the gangway. Solid: a nook is a place to stand, not a ledge to fall off.
			local function railBetween(a: Vector3, b: Vector3)
				local long = (b - a).Magnitude
				local posts = math.max(1, math.ceil(long / 3))
				for k = 0, posts do
					local at = a:Lerp(b, k / posts)
					nookPart(folder, "NookPost", Vector3.new(0.25, NOOK.RAIL, 0.25), frame * CFrame.new(at + Vector3.new(0, NOOK.RAIL / 2, 0)),
						style.rail, Enum.Material.Metal, true)
				end
				for _, h in ipairs({ NOOK.RAIL, NOOK.RAIL * 0.5 }) do
					local lift = Vector3.new(0, h, 0)
					local rail = nookPart(folder, "NookRail", Vector3.new(0.22, 0.22, long), CFrame.new(), style.rail, Enum.Material.Metal, true)
					rail.CFrame = frame * CFrame.lookAt(a:Lerp(b, 0.5) + lift, b + lift)
				end
			end
			local hx, hz = NOOK.D / 2 - 0.15, NOOK.W / 2 - 0.15
			railBetween(Vector3.new(hx, 0, -hz), Vector3.new(hx, 0, hz))
			railBetween(Vector3.new(-hx, 0, -hz), Vector3.new(hx, 0, -hz))
			railBetween(Vector3.new(-hx, 0, hz), Vector3.new(hx, 0, hz))
			railBetween(Vector3.new(-hx, 0, -hz), Vector3.new(-hx, 0, -2.2))
			railBetween(Vector3.new(-hx, 0, 2.2), Vector3.new(-hx, 0, hz))
			if gangLong > 2.2 then
				for _, z in ipairs({ -2.1, 2.1 }) do
					railBetween(Vector3.new(side0 + 0.4, 0, z), Vector3.new(-hx, 0, z))
				end
			end
			-- THE LAMP, on a post in the far corner: what you see from the route.
			local post = Vector3.new(hx - 0.6, 0, hz - 0.6)
			nookPart(folder, "NookLampPost", Vector3.new(0.35, 7, 0.35), frame * CFrame.new(post + Vector3.new(0, 3.5, 0)), style.trim,
				Enum.Material.Metal, true)
			nookPart(folder, "NookLampArm", Vector3.new(1.4, 0.2, 0.2), frame * CFrame.new(post + Vector3.new(-0.6, 6.9, 0)), style.trim,
				Enum.Material.Metal, false)
			local head = nookPart(folder, "NookLamp", Vector3.new(0.8, 1, 0.8), frame * CFrame.new(post + Vector3.new(-1.2, 6.3, 0)),
				style.lamp, Enum.Material.Glass, false)
			head.Transparency = 0.25
			local light = Instance.new("PointLight")
			light.Color = style.lamp
			light.Brightness = NOOK_LIGHTS
			light.Range = 16
			light.Shadows = true
			light.Parent = head
			-- NOW AND THEN, BUNTING out to it from the chunk: the level leading you there on its own.
			if rng:NextNumber() < 0.6 then
				local startPost = frame * Vector3.new(side0 + 0.8, 0, -2.6)
				nookPart(folder, "BuntingPole", Vector3.new(0.25, 6, 0.25), CFrame.new(startPost + Vector3.new(0, 3, 0)), style.trim,
					Enum.Material.Metal, false)
				local a = startPost + Vector3.new(0, 5.8, 0)
				local b = frame * Vector3.new(post.X, 6.6, post.Z)
				strut(folder, "BuntingLine", a, b, 0.06, Color3.fromRGB(60, 56, 52), false)
				local flags = math.floor((b - a).Magnitude / 1.3)
				local colours = { Color3.fromRGB(236, 120, 150), Color3.fromRGB(250, 214, 90), Color3.fromRGB(120, 190, 220),
					Color3.fromRGB(246, 244, 236) }
				for k = 1, flags - 1 do
					local u = k / flags
					local sag = math.sin(u * math.pi) * 0.9
					local at = a:Lerp(b, u) - Vector3.new(0, sag + 0.35, 0)
					local flag = nookPart(folder, "BuntingFlag", Vector3.new(0.05, 0.7, 0.6), CFrame.lookAt(at, at + (b - a).Unit)
						* CFrame.Angles(0, math.pi / 2, 0), colours[(k % #colours) + 1], Enum.Material.Fabric, false)
					flag.CastShadow = false
				end
			end
			return { frame = frame, index = index, taken = {} }
		end
	end
	return nil
end

-- A NOTICE BOARD on a post at `at` (its face toward `at`'s -Z): the title on the paper, readable from
-- where it faces. TAKE THE NOTICE (E): it comes off the board into your journal, and off the board on
-- your screen (JournalService); everyone else still sees it pinned up.
local function noticeBoard(parent: Instance, at: CFrame, entry: Note)
	local wood = Color3.fromRGB(110, 84, 60)
	prop(parent, "NoticePost", Vector3.new(0.3, 3.3, 0.3), at * CFrame.new(0, 1.65, 0), wood, Enum.Material.Wood)
	local board = prop(parent, "NoticeBoard", Vector3.new(2.6, 1.8, 0.16), at * CFrame.new(0, 3.9, 0), wood, Enum.Material.WoodPlanks)
	local paper = prop(parent, "NoticePaper", Vector3.new(2.2, 1.45, 0.04), at * CFrame.new(0, 3.9, -0.1),
		Color3.fromRGB(240, 234, 216), Enum.Material.SmoothPlastic)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 60
	gui.Parent = paper
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.TextScaled = true
	text.Font = Enum.Font.Garamond
	text.TextColor3 = Color3.fromRGB(44, 38, 32)
	text.Text = entry.title
	text.Parent = gui
	local prompt = Instance.new("ProximityPrompt")
	-- TAKE THE NOTICE: it comes off the board into your journal, and off the board on your screen.
	prompt.ActionText = "Take"
	prompt.ObjectText = entry.title
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = board
	prompt.Triggered:Connect(function(player: Player)
		if Interactables then
			Interactables.take(player, entry, paper, "note")
		end
	end)
end

-- ===== THINGS TO READ =====
--
-- A notice board on a post at the back of a nook, facing the route so its title reads from there; or,
-- for a note marked `lying`, a letter on a crate in the middle of the nook (Interactables.letter). Take
-- it (E) and it goes into your journal (JournalService), where you read it when you choose to.
local function nookNote(parent: Instance, nook: Nook, entry: Note)
	local frame = nook.frame
	if entry.lying and Interactables then
		local wood = Color3.fromRGB(150, 116, 80)
		local crate = frame * CFrame.new(0.5, 0, -2) * CFrame.Angles(0, 0.2, 0)
		prop(parent, "NookCrate", Vector3.new(1.8, 1.3, 1.5), crate * CFrame.new(0, 0.65, 0), wood, Enum.Material.WoodPlanks)
		Interactables.letter(parent, crate * CFrame.new(0, 1.3, 0), entry)
		nook.taken.centre = true
		return
	end
	-- The board's -Z is its face: turned to look back along -X, at the route.
	local at = frame * CFrame.new(NOOK.D / 2 - 1.1, 0, 0) * CFrame.Angles(0, math.pi / 2, 0)
	nook.taken.back = true
	noticeBoard(parent, at, entry)
end

-- A KEEPSAKE in a nook, on a little stool beside the rail.
local function nookKeepsake(parent: Instance, nook: Nook, material: string): boolean
	if not Interactables then
		return false
	end
	local z = if nook.taken.stool then -NOOK.W / 2 + 2 else NOOK.W / 2 - 2.6
	nook.taken.stool = true
	local stool = nook.frame * CFrame.new(1.2, 0, z)
	local wood = Color3.fromRGB(140, 106, 74)
	prop(parent, "NookStool", Vector3.new(1.6, 0.25, 1.6), stool * CFrame.new(0, 1.6, 0), wood, Enum.Material.Wood)
	for _, corner in ipairs({ { -0.6, -0.6 }, { 0.6, -0.6 }, { -0.6, 0.6 }, { 0.6, 0.6 } }) do
		prop(parent, "NookStoolLeg", Vector3.new(0.2, 1.48, 0.2), stool * CFrame.new(corner[1], 0.74, corner[2]), wood, Enum.Material.Wood)
	end
	return Interactables.keepsake(parent, stool * CFrame.new(0, 1.725, 0), material) ~= nil
end

-- ===== THINGS TO READ ON THE ROUTE (only where there is nowhere else) =====
--
-- A notice board on a post, standing on a stable chunk's cap beside the route and facing it; or, for a
-- note marked `lying`, a letter on the ground. Only used when no nook could be built for a note.
local function note(parent: Instance, cap: BasePart, entry: Note)
	if entry.lying and Interactables then
		Interactables.letter(parent, besideRoute(cap, 1, 2.2), entry)
		return
	end
	noticeBoard(parent, besideRoute(cap, 1, 1.4), entry)
end

-- ===== THE SIREN TOWER (City Shore) =====
--
-- Out of the sea, seven hundred studs down, in the middle of the spiral, so the whole climb goes round
-- it: the tower that sounds Harrow Bay's flood siren. A red brick shaft with stone pilasters and string
-- courses and a few lit windows; at the height of a chunk about halfway up, the SIREN ROOM, which a
-- footbridge reaches from that chunk; over it a clock stage stopped at 9:14, a balcony, a copper dome,
-- the siren itself on top, and a small red lamp over everything. In the Siren Room: the keeper's desk
-- with the siren log on it, the control panel, a hanging lamp, a ladder to a shut hatch, and a patch of
-- bricks in the wall that are not quite like the rest (Interactables.looseBricks: the first secret).
--
-- The chunk is chosen so its bridge in passes clear of every other chunk; if none is, there is no
-- tower. Everything stands on the sea bed or on the shaft, and the bridge rests on the chunk and on
-- the Siren Room's sill.
local TOWER = {
	R = 15, -- the shaft's radius
	SEA = -720, -- where it stands, under the sea's surface
	ROOM = 11, -- the Siren Room's height
	WALL = 1.2,
}
local BRICK = Color3.fromRGB(140, 84, 66)
local STONE = Color3.fromRGB(204, 196, 178)
local IRON = Color3.fromRGB(44, 44, 48)
local COPPER = Color3.fromRGB(96, 150, 128)

local function towerFrom(parent: Instance, centre: Vector3, floorY: number, toward: Vector3, bridgeFrom: Vector3)
	local R, WALL, ROOM = TOWER.R, TOWER.WALL, TOWER.ROOM
	local base = Vector3.new(centre.X, TOWER.SEA, centre.Z)
	local shaftTop = floorY - 1.2
	local up = CFrame.Angles(0, 0, math.pi / 2)
	local function ring(name: string, y: number, radius: number, thick: number, colour: Color3, material: Enum.Material)
		prop(parent, name, Vector3.new(thick, radius * 2, radius * 2), CFrame.new(centre.X, y, centre.Z) * up, colour, material,
			Enum.PartType.Cylinder).CanCollide = true
	end
	-- THE SHAFT, out of the sea.
	local shaftH = shaftTop - TOWER.SEA
	local shaft = prop(parent, "TowerShaft", Vector3.new(shaftH, R * 2, R * 2), CFrame.new(centre.X, (TOWER.SEA + shaftTop) / 2, centre.Z) * up,
		BRICK, Enum.Material.Brick, Enum.PartType.Cylinder)
	shaft.CanCollide = true
	-- `toward` points from the tower's middle out to the bridge's chunk; the room's -Z is its door.
	local facing = CFrame.lookAt(Vector3.new(centre.X, floorY, centre.Z), Vector3.new(centre.X, floorY, centre.Z) + toward)
	for k = 0, 7 do
		local a = k * math.pi / 4
		local out = facing * CFrame.Angles(0, a, 0)
		prop(parent, "Pilaster", Vector3.new(1.8, shaftH, 1), (out * CFrame.new(0, 0, -R - 0.3)) - Vector3.new(0, floorY - (TOWER.SEA + shaftTop) / 2, 0),
			STONE, Enum.Material.Concrete)
	end
	local level = 0
	for y = TOWER.SEA + 60, shaftTop - 12, 50 do
		ring("StringCourse", y, R + 0.8, 1, STONE, Enum.Material.Concrete)
		level += 1
		-- Two slit windows a storey, on turning sides; a few of the high ones lit from within.
		for _, turn in ipairs({ level * 0.9, level * 0.9 + math.pi }) do
			local out = CFrame.new(centre.X, y + 22, centre.Z) * facing.Rotation * CFrame.Angles(0, turn, 0)
			local slit = prop(parent, "TowerWindow", Vector3.new(1.4, 5, 0.3), out * CFrame.new(0, 0, -R - 0.05), Color3.fromRGB(18, 16, 16),
				Enum.Material.SmoothPlastic)
			prop(parent, "WindowSill", Vector3.new(2, 0.35, 0.7), out * CFrame.new(0, -2.7, -R - 0.2), STONE, Enum.Material.Concrete)
			if y > shaftTop - 170 and turn < math.pi then
				slit.Color = Color3.fromRGB(255, 214, 150)
				local lamp = Instance.new("PointLight")
				lamp.Color = Color3.fromRGB(255, 200, 130)
				lamp.Brightness = 0.6
				lamp.Range = 12
				lamp.Parent = slit
			end
		end
	end
	-- The cornice under the Siren Room, and its floor.
	ring("Cornice", floorY - 1.8, R + 1.3, 1.4, STONE, Enum.Material.Concrete)
	ring("RoomFloor", floorY - 0.6, R, 1.2, Color3.fromRGB(120, 92, 66), Enum.Material.WoodPlanks)
	-- THE SIREN ROOM'S WALLS: sixteen panels round it, the door toward the bridge, windows either side,
	-- and on the right a panel with a hole in it where the loose bricks are.
	local room = facing -- -Z of the room is toward the door
	local panels = 16
	local width = 2 * math.pi * R / panels + 0.25
	local bricksFace: CFrame? = nil
	for k = 0, panels - 1 do
		local a = k * 2 * math.pi / panels
		local at = room * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -(R - WALL / 2))
		local function panel(y0: number, y1: number, w: number?, dx: number?)
			local p = prop(parent, "RoomWall", Vector3.new(w or width, y1 - y0, WALL), at * CFrame.new(dx or 0, (y0 + y1) / 2, 0), BRICK,
				Enum.Material.Brick)
			p.CanCollide = true
		end
		if k == 0 then
			-- The doorway: jambs, a lintel, a stone surround.
			local side = (width - 4) / 2
			panel(0, ROOM, side, -(2 + side / 2))
			panel(0, ROOM, side, 2 + side / 2)
			panel(8, ROOM)
			prop(parent, "DoorLintel", Vector3.new(4.8, 0.8, WALL + 0.4), at * CFrame.new(0, 8.2, 0), STONE, Enum.Material.Concrete)
			-- The door, open inward against the jamb.
			prop(parent, "TowerDoor", Vector3.new(0.3, 7.8, 3.8), at * CFrame.new(-2.1, 3.95, 2.2) * CFrame.Angles(0, 0.35, 0),
				Color3.fromRGB(96, 70, 50), Enum.Material.WoodPlanks).CanCollide = true
		elseif k == 4 or k == 12 or k == 8 then
			-- A window: wall under and over it, glass in it.
			panel(0, 4)
			panel(7.5, ROOM)
			local glass = prop(parent, "RoomWindow", Vector3.new(width - 0.4, 3.5, 0.15), at * CFrame.new(0, 5.75, 0),
				Color3.fromRGB(150, 176, 186), Enum.Material.Glass)
			glass.Transparency = 0.55
			glass.CanCollide = true
			prop(parent, "WindowFrame", Vector3.new(width - 0.3, 0.3, WALL + 0.2), at * CFrame.new(0, 4.1, 0), STONE, Enum.Material.Concrete)
		elseif k == 13 then
			-- The loose bricks: a hole in the wall at waist height, a skin of brick outside it.
			panel(0, 3.4)
			panel(5.6, ROOM)
			local side = (width - 3.5) / 2
			panel(3.4, 5.6, side, -(1.75 + side / 2))
			panel(3.4, 5.6, side, 1.75 + side / 2)
			prop(parent, "OuterSkin", Vector3.new(3.6, 2.3, 0.15), at * CFrame.new(0, 4.5, -WALL / 2 + 0.05), BRICK, Enum.Material.Brick)
			bricksFace = at * CFrame.new(0, 4.5, WALL / 2) * CFrame.Angles(0, math.pi, 0)
		else
			panel(0, ROOM)
		end
	end
	ring("RoomCeiling", floorY + ROOM + 0.6, R, 1.2, STONE, Enum.Material.Concrete)
	-- THE CLOCK STAGE, stopped at 9:14 on all four faces.
	local clockBase = floorY + ROOM + 1.2
	local clockR = R - 1.5
	prop(parent, "ClockStage", Vector3.new(14, clockR * 2, clockR * 2), CFrame.new(centre.X, clockBase + 7, centre.Z) * up, BRICK,
		Enum.Material.Brick, Enum.PartType.Cylinder).CanCollide = true
	for k = 0, 3 do
		local face = room * CFrame.Angles(0, k * math.pi / 2, 0)
		local at = CFrame.new(centre.X, clockBase + 7, centre.Z) * face.Rotation * CFrame.new(0, 0, -clockR - 0.2)
		prop(parent, "ClockRim", Vector3.new(0.5, 10, 10), at * CFrame.Angles(0, math.pi / 2, 0), IRON, Enum.Material.Metal, Enum.PartType.Cylinder)
		prop(parent, "ClockFace", Vector3.new(0.3, 9, 9), at * CFrame.new(0, 0, -0.2) * CFrame.Angles(0, math.pi / 2, 0), Color3.fromRGB(236, 230, 212),
			Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		for _, hand in ipairs({ { (9 + 14 / 60) * 30, 2.6, 0.45 }, { 14 * 6, 3.8, 0.3 } }) do
			prop(parent, "ClockHand", Vector3.new(hand[3], hand[2], 0.1), at * CFrame.new(0, 0, -0.45) * CFrame.Angles(0, 0, -math.rad(hand[1]))
				* CFrame.new(0, hand[2] / 2 - 0.3, 0), IRON, Enum.Material.Metal)
		end
	end
	-- THE BALCONY, its railing, the copper dome and the siren on it, and the red lamp over all.
	local deckY = clockBase + 14
	ring("Balcony", deckY + 0.4, R + 1.8, 0.8, STONE, Enum.Material.Concrete)
	for k = 0, 15 do
		local a = k * math.pi / 8
		local at = CFrame.new(centre.X, deckY + 0.8, centre.Z) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -(R + 1.4))
		prop(parent, "BalconyPost", Vector3.new(0.3, 3, 0.3), at * CFrame.new(0, 1.5, 0), IRON, Enum.Material.Metal)
		prop(parent, "BalconyRail", Vector3.new(2 * math.pi * (R + 1.4) / 16 + 0.3, 0.25, 0.25), at * CFrame.new(0, 3, 0), IRON,
			Enum.Material.Metal)
	end
	local dome = prop(parent, "Dome", Vector3.new(clockR * 2, clockR * 1.3, clockR * 2), CFrame.new(centre.X, deckY + 0.8, centre.Z), COPPER,
		Enum.Material.Metal)
	local domeMesh = Instance.new("SpecialMesh")
	domeMesh.MeshType = Enum.MeshType.Sphere
	domeMesh.Parent = dome
	local podY = deckY + 0.8 + clockR * 0.65
	prop(parent, "SirenPedestal", Vector3.new(5, 4.4, 4.4), CFrame.new(centre.X, podY + 1.5, centre.Z) * up, IRON, Enum.Material.Metal,
		Enum.PartType.Cylinder)
	prop(parent, "SirenDrum", Vector3.new(3, 7, 7), CFrame.new(centre.X, podY + 5.5, centre.Z) * up, Color3.fromRGB(150, 36, 34),
		Enum.Material.Metal, Enum.PartType.Cylinder)
	for k = 0, 5 do
		local a = k * math.pi / 3
		prop(parent, "SirenHorn", Vector3.new(3.4, 2.2, 2.2), CFrame.new(centre.X, podY + 5.5, centre.Z) * CFrame.Angles(0, a, 0)
			* CFrame.new(4.6, 0, 0), IRON, Enum.Material.Metal, Enum.PartType.Cylinder)
	end
	prop(parent, "SirenCap", Vector3.new(0.8, 5, 5), CFrame.new(centre.X, podY + 7.4, centre.Z) * up, IRON, Enum.Material.Metal,
		Enum.PartType.Cylinder)
	prop(parent, "Finial", Vector3.new(7, 0.5, 0.5), CFrame.new(centre.X, podY + 11.3, centre.Z) * up, IRON, Enum.Material.Metal,
		Enum.PartType.Cylinder)
	local beacon = prop(parent, "Beacon", Vector3.new(1, 1, 1), CFrame.new(centre.X, podY + 15.2, centre.Z), Color3.fromRGB(200, 40, 40),
		Enum.Material.Glass, Enum.PartType.Ball)
	beacon.Transparency = 0.2
	local red = Instance.new("PointLight")
	red.Color = Color3.fromRGB(255, 60, 50)
	red.Brightness = 0.8
	red.Range = 26
	red.Parent = beacon
	-- THE FOOTBRIDGE: planks from the chunk to the sill, stringers under, rails, and two stays up to
	-- the wall over the door.
	local sill = Vector3.new(centre.X, floorY, centre.Z) + toward * R
	local run = sill - bridgeFrom
	local span = run.Magnitude
	local along = CFrame.lookAt(bridgeFrom, sill)
	local planks = math.max(2, math.floor(span / 1.1))
	for k = 0, planks - 1 do
		prop(parent, "BridgePlank", Vector3.new(4.6, 0.4, span / planks - 0.12), along * CFrame.new(0, -0.2, -(k + 0.5) * span / planks),
			Color3.fromRGB(128 + (k * 37) % 20, 96, 68), Enum.Material.WoodPlanks).CanCollide = true
	end
	for _, x in ipairs({ -1.9, 1.9 }) do
		prop(parent, "BridgeStringer", Vector3.new(0.5, 0.8, span), along * CFrame.new(x, -0.8, -span / 2), IRON, Enum.Material.Metal)
		-- THE RAILS ARE SOLID, and so is the air over them. They were drawn and not there: you could walk
		-- straight through them and off the bridge, seven hundred studs down. Posts every two and a half
		-- studs, a top rail and a mid rail, and over them a guard you cannot see, up past head height, so
		-- nobody jumps the rail either (as along the Sunken City's pier). The bridge is the way to the tower,
		-- not a way off the level.
		for k = 0, math.floor(span / 2.5) do
			local z = -math.min(span, k * 2.5)
			local post = prop(parent, "BridgePost", Vector3.new(0.25, 3.4, 0.25), along * CFrame.new(x * 1.1, 1.7, z), IRON, Enum.Material.Metal)
			post.CanCollide = true
		end
		local rail = prop(parent, "BridgeRail", Vector3.new(0.25, 0.25, span), along * CFrame.new(x * 1.1, 3.4, -span / 2), IRON,
			Enum.Material.Metal)
		rail.CanCollide = true
		local midRail = prop(parent, "BridgeMidRail", Vector3.new(0.18, 0.18, span), along * CFrame.new(x * 1.1, 1.8, -span / 2), IRON,
			Enum.Material.Metal)
		midRail.CanCollide = true
		local guard = prop(parent, "BridgeGuard", Vector3.new(0.4, 9, span), along * CFrame.new(x * 1.1, 4.5, -span / 2), IRON,
			Enum.Material.SmoothPlastic)
		guard.Transparency = 1
		guard.CanCollide = true
		guard.CastShadow = false
		local anchor = sill + Vector3.new(0, 10, 0) + along.RightVector * x * 1.1
		for _, share in ipairs({ 0.35, 0.7 }) do
			local deck = (along * CFrame.new(x * 1.1, 3.4, -span * (1 - share))).Position
			local mid = (anchor + deck) / 2
			prop(parent, "BridgeStay", Vector3.new(0.15, 0.15, (anchor - deck).Magnitude), CFrame.lookAt(mid, anchor), IRON, Enum.Material.Metal)
		end
	end
	-- TWO LANTERNS AT THE BRIDGE'S HEAD, on the chunk it leaves from: from along the route, the way to
	-- the tower is lit. Real lights, and small.
	for _, hand in ipairs({ -1, 1 }) do
		local foot = bridgeFrom - along.LookVector * 0.7 + along.RightVector * hand * 2.9
		prop(parent, "BridgeLanternPost", Vector3.new(0.3, 5.2, 0.3), CFrame.new(foot + Vector3.new(0, 2.6, 0)), IRON, Enum.Material.Metal)
		local head = prop(parent, "BridgeLantern", Vector3.new(0.7, 0.9, 0.7), CFrame.new(foot + Vector3.new(0, 5.6, 0)),
			Color3.fromRGB(255, 220, 170), Enum.Material.Glass)
		head.Transparency = 0.2
		prop(parent, "BridgeLanternCap", Vector3.new(0.9, 0.2, 0.9), CFrame.new(foot + Vector3.new(0, 6.15, 0)), IRON, Enum.Material.Metal)
		local glow = Instance.new("PointLight")
		glow.Color = Color3.fromRGB(255, 206, 150)
		glow.Brightness = 0.8
		glow.Range = 14
		glow.Parent = head
	end
	-- THE SIREN ROOM, furnished.
	local floor = CFrame.new(centre.X, floorY, centre.Z) * room.Rotation
	local wood = Color3.fromRGB(106, 78, 56)
	local desk = floor * CFrame.new(0, 0, R - 3.4)
	prop(parent, "Desk", Vector3.new(4, 0.25, 2), desk * CFrame.new(0, 2.6, 0), wood, Enum.Material.Wood).CanCollide = true
	for _, corner in ipairs({ { -1.8, -0.8 }, { 1.8, -0.8 }, { -1.8, 0.8 }, { 1.8, 0.8 } }) do
		prop(parent, "DeskLeg", Vector3.new(0.25, 2.5, 0.25), desk * CFrame.new(corner[1], 1.25, corner[2]), wood, Enum.Material.Wood)
	end
	prop(parent, "Chair", Vector3.new(1.5, 0.2, 1.5), desk * CFrame.new(0.4, 1.6, -1.8), wood, Enum.Material.Wood)
	for _, corner in ipairs({ { -0.6, -0.6 }, { 0.6, -0.6 }, { -0.6, 0.6 }, { 0.6, 0.6 } }) do
		prop(parent, "ChairLeg", Vector3.new(0.2, 1.5, 0.2), desk * CFrame.new(0.4 + corner[1], 0.75, -1.8 + corner[2]), wood, Enum.Material.Wood)
	end
	if Interactables then
		Interactables.letter(parent, desk * CFrame.new(-0.6, 2.73, 0.1), {
			title = "Siren log",
			body = "HARROW BAY FLOOD SIREN. LOG.\n\n11 AUG. 12:00 test. 00:00 NOT A TEST.\n12 AUG. 12:00 test. 00:00 NOT A TEST.\n"
				.. "13 AUG. 12:00 test. 00:00 NOT A TEST.\n14 AUG. 12:00 test. 00:00\n14 AUG. 12:00 test. 00:00\n14 AUG. 12:00 test."
				.. "\n\nThe hand is the same all the way down, and it gets worse.",
		})
	end
	-- The control panel on the wall, its lever up; the ladder to the hatch; the lamp over the desk.
	local panelAt = floor * CFrame.Angles(0, -math.pi / 2, 0) * CFrame.new(0, 0, -(R - WALL - 0.4))
	prop(parent, "SirenPanel", Vector3.new(2.4, 3, 0.8), panelAt * CFrame.new(0, 3.6, 0), Color3.fromRGB(70, 84, 80), Enum.Material.Metal)
	prop(parent, "SirenLever", Vector3.new(0.2, 1.6, 0.2), panelAt * CFrame.new(0.6, 4.6, 0.55) * CFrame.Angles(math.rad(-25), 0, 0), IRON,
		Enum.Material.Metal)
	local dial = prop(parent, "SirenDial", Vector3.new(0.1, 0.9, 0.9), panelAt * CFrame.new(-0.5, 4.2, 0.45) * CFrame.Angles(0, math.pi / 2, 0),
		Color3.fromRGB(236, 230, 212), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	dial.CanCollide = false
	local ladderAt = floor * CFrame.new(-(R - 3.5), 0, 3)
	for _, x in ipairs({ -0.7, 0.7 }) do
		prop(parent, "HatchLadder", Vector3.new(0.2, ROOM, 0.2), ladderAt * CFrame.new(x, ROOM / 2, 0), IRON, Enum.Material.Metal)
	end
	for y = 1, ROOM - 1, 1.2 do
		prop(parent, "HatchRung", Vector3.new(1.6, 0.15, 0.15), ladderAt * CFrame.new(0, y, 0), IRON, Enum.Material.Metal)
	end
	prop(parent, "Hatch", Vector3.new(2.6, 0.3, 2.6), ladderAt * CFrame.new(0, ROOM - 0.1, 0), Color3.fromRGB(70, 60, 50), Enum.Material.WoodPlanks)
	prop(parent, "LampCable", Vector3.new(0.1, 3.6, 0.1), desk * CFrame.new(0, ROOM - 1.8, -0.4), IRON, Enum.Material.Metal)
	local shade = prop(parent, "LampShade", Vector3.new(0.8, 1.6, 1.6), desk * CFrame.new(0, ROOM - 3.8, -0.4) * up, Color3.fromRGB(60, 82, 70),
		Enum.Material.Metal, Enum.PartType.Cylinder)
	local lamp = Instance.new("PointLight")
	lamp.Color = Color3.fromRGB(255, 208, 150)
	lamp.Brightness = 0.9
	lamp.Range = 20
	lamp.Shadows = true
	lamp.Parent = shade
	-- The secret.
	local face = bricksFace
	if Interactables and face then
		Interactables.looseBricks(parent, face, "siren", CFrame.new((floor * CFrame.new(-3, 4.8, -4)).Position))
	end
end

-- Chooses the chunk and builds the tower, if a clear bridge in can be found.
local function sirenTower(parent: Instance, instance: any, chunks: { any }, used: { [number]: boolean },
	reserved: { { cf: CFrame, size: Vector3 } })
	local centre = instance.centre
	if typeof(centre) ~= "Vector3" then
		return
	end
	local boxes = {}
	for index, entry in ipairs(chunks) do
		local model = entry.model
		if model and model:IsA("Model") then
			local cf, size = model:GetBoundingBox()
			table.insert(boxes, { index = index, cf = cf, size = size })
		end
	end
	for index = math.floor(#chunks * 0.35), math.floor(#chunks * 0.7) do
		local entry = chunks[index]
		local cap = entry and not used[index] and stableCap(entry)
		if cap and math.min(cap.Size.X, cap.Size.Z) >= 8 then
			local capTop = cap.Position.Y + cap.Size.Y / 2
			local flat = Vector3.new(centre.X - cap.Position.X, 0, centre.Z - cap.Position.Z)
			if flat.Magnitude > TOWER.R + 14 then
				local toward = flat.Unit
				local cfc = cap.CFrame
				local reach = math.abs(cfc.RightVector:Dot(toward)) * cap.Size.X / 2 + math.abs(cfc.LookVector:Dot(toward)) * cap.Size.Z / 2
				local from = Vector3.new(cap.Position.X, capTop, cap.Position.Z) + toward * (reach - 0.4)
				local sill = Vector3.new(centre.X, capTop, centre.Z) - toward * TOWER.R
				local span = (sill - from).Magnitude
				local clear = true
				for step = 2, span, 3 do
					local point = from + toward * step + Vector3.new(0, 3.5, 0)
					for _, box in ipairs(boxes) do
						if box.index ~= index then
							local rel = box.cf:PointToObjectSpace(point)
							if math.abs(rel.X) < box.size.X / 2 + 3 and math.abs(rel.Y) < box.size.Y / 2 + 5
								and math.abs(rel.Z) < box.size.Z / 2 + 3 then
								clear = false
								break
							end
						end
					end
					if not clear then
						break
					end
				end
				if clear then
					used[index] = true
					towerFrom(parent, centre, capTop, -toward, from)
					-- KEPT CLEAR OF THE NOOKS, which cannot see the tower (nothing of the story's is
					-- queryable): the shaft all the way up, and the air over the bridge.
					table.insert(reserved, { cf = CFrame.new(centre.X, capTop, centre.Z),
						size = Vector3.new(TOWER.R * 2 + 16, 900, TOWER.R * 2 + 16) })
					table.insert(reserved, { cf = CFrame.lookAt((from + sill) / 2 + Vector3.new(0, 4, 0), sill + Vector3.new(0, 4, 0)),
						size = Vector3.new(10, 14, span + 4) })
					return
				end
			end
		end
	end
	warn("StoryService: no chunk halfway up City Shore had a clear way across to the Siren Tower, so it is not built this run.")
end

-- ===== THE SECRETS ON THE LEVELS' OWN SPOTS =====
local function spots()
	if not Interactables then
		return
	end
	for _, spot in ipairs(CollectionService:GetTagged("StorySpot")) do
		if spot:IsA("BasePart") and spot.Parent then
			local kind = spot:GetAttribute("Kind")
			local at = spot.CFrame
			local ok, err = pcall(function()
				if kind == "PoolBox" then
					Interactables.lockbox(spot.Parent, at, "photograph", CFrame.new((at * CFrame.new(3.4, 2.6, -3.4)).Position))
				elseif kind == "AquariumLocker" then
					Interactables.locker(spot.Parent, at, { label = "STAFF", bar = true, secret = "marsh",
						eye = CFrame.new((at * CFrame.new(1.8, 4.6, -5.2)).Position) })
				elseif kind == "StaffLockers" then
					for k = 1, 4 do
						Interactables.locker(spot.Parent, at * CFrame.new((k - 2.5) * 1.62, 0, 0), { label = tostring(k),
							secret = if k == 3 then "locker" else nil, dud = k ~= 3,
							eye = CFrame.new((at * CFrame.new((k - 2.5) * 1.62 + 1.6, 4.6, -5)).Position) })
					end
				elseif kind == "LoosePlank" then
					Interactables.loosePlank(spot.Parent, at, "boards", at * CFrame.new(0, 0.05, 0))
				end
			end)
			if not ok then
				warn(("StoryService: the %s could not be built: %s"):format(tostring(kind), tostring(err)))
			end
		end
	end
end

-- THE STORY'S HAND IN A LEVEL, as it starts: the opening words for everyone in it, and City Shore's
-- people on their chunks. `level` is the definition, `instance` what LevelService built.
function StoryService.stage(level: any, instance: any, players: { Player })
	for _, player in ipairs(players) do
		pcall(StoryService.opening, player, level.levelId)
	end
	if not instance or not instance.placedChunks then
		return
	end
	local levels = workspace:FindFirstChild("Levels")
	if not levels then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "Story"
	folder.Parent = levels
	local chunks = instance.placedChunks
	local used: { [number]: boolean } = {}
	-- The first stable chunk from `from` on that is wide enough to stand something beside the route,
	-- and not already somebody's.
	local function stableFrom(from: number, to: number): (number?, BasePart?)
		for index = math.max(1, from), math.min(#chunks, to) do
			local entry = chunks[index]
			local cap = entry and not used[index] and stableCap(entry)
			if cap and math.min(cap.Size.X, cap.Size.Z) >= 10 then
				used[index] = true
				return index, cap
			end
		end
		return nil, nil
	end
	if Townsfolk then
		if level.backdrop == "cityShore" then
			local _, first = stableFrom(1, #chunks)
			if first then
				pcall(sal, folder, first)
			end
			local _, mid = stableFrom(math.floor(#chunks * 0.45), #chunks - 2)
			if mid then
				pcall(pip, folder, mid)
			end
		elseif level.backdrop == "floodedHalls" then
			local _, first = stableFrom(1, #chunks)
			if first then
				pcall(venn, folder, first)
			end
			local _, mid = stableFrom(math.floor(#chunks * 0.5), #chunks - 2)
			if mid then
				pcall(tobi, folder, mid)
			end
			pcall(barlow, folder)
		end
	end
	-- CITY SHORE'S SIREN TOWER, and every level's secrets on the spots its service marked.
	local reserved: { { cf: CFrame, size: Vector3 } } = {}
	if level.backdrop == "cityShore" then
		local ok, err = pcall(sirenTower, folder, instance, chunks, used, reserved)
		if not ok then
			warn("StoryService: the Siren Tower could not be built: " .. tostring(err))
		end
	end
	spots()

	-- ===== THE NOOKS, AND WHAT IS IN THEM =====
	--
	-- Off the route, never on it: the pry bar, the things to read, and a few of the keepsakes, each in a
	-- nook off a chunk (see nookOff). A chunk somebody stands on, or the tower's, keeps its sides clear.
	local rng = Random.new()
	local centre = if typeof(instance.centre) == "Vector3" then instance.centre else nil
	local nooked: { [number]: boolean } = {}
	local nooks: { Nook } = {}
	local function nookNear(fraction: number, wants: ((number) -> boolean)?): Nook?
		local from = math.clamp(math.floor(#chunks * fraction), 2, math.max(2, #chunks - 2))
		for index = from, math.min(#chunks - 1, from + 8) do
			if not used[index] and not nooked[index] and not nooked[index - 1] and not nooked[index + 1]
				and (not wants or wants(index)) then
				local ok, made = pcall(nookOff, folder, chunks, index, level.backdrop, centre, reserved, rng)
				if not ok then
					warn("StoryService: a nook could not be built: " .. tostring(made))
				elseif made then
					nooked[index] = true
					table.insert(nooks, made)
					return made
				end
			end
		end
		return nil
	end
	-- MR BARLOW'S PRY BAR, early on, lying on the floor of the first nook, catching the light.
	if Interactables then
		local first = nookNear(0.1)
		if first then
			pcall(Interactables.pryBar, folder, first.frame * CFrame.new(-1.6, 0, 3) * CFrame.Angles(0, 0.4, 0))
		else
			local _, cap = stableFrom(math.max(2, math.floor(#chunks * 0.1)), #chunks)
			if cap then
				pcall(Interactables.pryBar, folder, besideRoute(cap, -1, 2.6))
			end
		end
	end
	-- THE THINGS TO READ, each in a nook of its own, spread along the route. Only where no nook would fit
	-- does one stand on a chunk beside the route, as they all used to.
	local notes = NOTES[level.levelId]
	if notes then
		for k, entry in ipairs(notes) do
			local nook = nookNear(0.18 + 0.64 * (k - 1) / math.max(1, #notes - 1))
			if nook then
				pcall(nookNote, folder, nook, entry)
			else
				local _, cap = stableFrom(math.floor(#chunks * (0.15 + 0.7 * (k - 1) / math.max(1, #notes))), #chunks)
				if cap then
					pcall(note, folder, cap, entry)
				end
			end
		end
	end
	-- THE KEEPSAKES: the thing a nook's own chunk is made of, sitting in it, where there is one; and a
	-- nook or two more, off chunks of a material not found yet, until the level has KEEPSAKES of them.
	local KEEPSAKES = 4
	local placed: { [string]: boolean } = {}
	local count = 0
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local keepsakeModule = shared and shared:FindFirstChild("Keepsakes")
	local keepsakes: { [string]: any } = if keepsakeModule and keepsakeModule:IsA("ModuleScript") then require(keepsakeModule) :: any else {}
	local defs = shared and shared:FindFirstChild("ChunkDefinitions")
	local definitions: { [string]: any } = if defs and defs:IsA("ModuleScript") then require(defs) :: any else {}
	-- A material chunk `index` is made of whose keepsake is not in this level yet.
	local function fresh(index: number): string?
		local def = definitions[chunks[index].chunkId]
		if not (def and typeof(def.materials) == "table") then
			return nil
		end
		for name in pairs(def.materials) do
			if keepsakes[name] and not placed[name] then
				return name
			end
		end
		return nil
	end
	local function leave(nook: Nook)
		local material = fresh(nook.index)
		if count < KEEPSAKES and material then
			local ok, made = pcall(nookKeepsake, folder, nook, material)
			if ok and made then
				placed[material] = true
				count += 1
			end
		end
	end
	for _, nook in ipairs(nooks) do
		leave(nook)
	end
	for _, fraction in ipairs({ 0.3, 0.55, 0.8 }) do
		if count >= KEEPSAKES then
			break
		end
		local nook = nookNear(fraction, function(index: number): boolean
			return fresh(index) ~= nil
		end)
		if nook then
			leave(nook)
		end
	end
	print(("StoryService: %d nooks off the route, %d keepsakes in them."):format(#nooks, count))
end

return StoryService
