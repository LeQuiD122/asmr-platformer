--!strict
-- StarterPlayerScripts/Services/SeaService.lua
-- Moves the sea. Everything else about the backdrop is static server geometry; this is the
-- one part of it that animates, and it animates only on the client.
--
-- === Why the client, when BackdropService is deliberately server-side ===
--
-- Because the alternative is replicating it. The server owns these parts, so animating
-- them there would push a CFrame update per part per tick to every client -- 1300 parts
-- at even 15Hz is nearly twenty thousand replicated property changes a second, forever,
-- for scenery nobody can reach. Anchored parts can be moved locally instead: the client writes
-- their CFrame, the server never writes it back, and the change simply stands. The cost is
-- one RenderStepped loop, most of it staggered, which is nothing.
--
-- This does not undo the reason the backdrop moved to the server. That was about the
-- horizon appearing late, vanishing under streaming, and every client rebuilding several
-- hundred parts from scratch. None of that applies to reading a folder that already exists
-- and adding an offset to it.
--
-- === Two kinds of motion, and the difference is not cosmetic ===
--
-- Most of what moves here is scattered marks -- flecks, swell, glitter, waterline rings.
-- Each gets its own drift, period and random phase, and they are updated a third at a time
-- because nothing bad happens when one lags a frame behind its neighbour.
--
-- The 45 base tiles are the opposite case. They are 1600-stud plates butted edge to edge,
-- and INDEPENDENT motion tears their seams open -- the artefact the sea's uniform colour
-- and its opaque surface were both introduced to remove. They move as one body instead:
-- identical drift, identical period, phase pinned to zero, and refreshed every frame rather
-- than on the rotating third. Fixed phase makes them agree on where to be; the separate
-- loop makes them agree on when. Either one alone is a seam.
--
-- From 700 studs up the sway can be small. Individual wavelets are far below the resolution
-- you are viewing the sea at; what reads as moving water from a height is large-scale swell
-- crossing the surface, light flickering off it, and the whole sheet breathing.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local SeaService = {}

type Wave = {
	part: BasePart,
	origin: CFrame,
	transparency: number,
	drift: Vector3,
	rate: number,
	phase: number,
	fade: number,
}

local waves: { Wave } = {}

-- Parts that must be refreshed on EVERY frame, never on the rotating third below.
--
-- The sea tiles are 1600-stud plates butted edge to edge. They are given identical drift,
-- period and phase so the whole sheet translates as one body -- but that only holds if they
-- are all written on the SAME frame. Spread across the stride, neighbours would sit one
-- frame apart from each other, and one frame apart is a visible seam. The staggering trick
-- is safe for scattered marks and unsafe for a tiled surface.
local locked: { Wave } = {}

-- Read once at startup rather than every frame. These are attributes on parts the server
-- authored, so the motion is designed alongside the geometry and this module is a dumb
-- player of it -- which also means retuning the sea never means editing this file.
local function collect(folder: Instance)
	for _, item in ipairs(folder:GetChildren()) do
		if item:IsA("BasePart") then
			local drift = item:GetAttribute("Drift")
			local period = item:GetAttribute("Period")
			if typeof(drift) == "Vector3" and typeof(period) == "number" and period > 0 then
				local into = if item:GetAttribute("Lockstep") == true then locked else waves
				table.insert(into, {
					part = item,
					-- The pose it was BUILT at. Offsets accumulate against this rather than
					-- against the last frame, so nothing drifts away over a long session
					-- and a dropped frame costs nothing.
					origin = item.CFrame,
					transparency = item.Transparency,
					drift = drift,
					rate = math.pi * 2 / period,
					phase = (item:GetAttribute("Phase") :: number?) or 0,
					fade = (item:GetAttribute("Fade") :: number?) or 0,
				})
			end
		end
	end
end

function SeaService.start()
	-- The backdrop is built on the server after the level, so it may not exist yet. Waiting
	-- rather than giving up: a client that loads fast would otherwise get a still sea for
	-- the whole session, which looks like the feature is broken rather than early.
	local backdrop = workspace:WaitForChild("Backdrop", 30)
	local folder = backdrop and backdrop:FindFirstChild("Swell")
	if not folder then
		-- Not an error. The backdrop is optional scenery and may be absent entirely.
		return
	end

	collect(folder)
	if #waves == 0 and #locked == 0 then
		return
	end

	print(("[client] Sea animating: %d staggered, %d in lockstep"):format(#waves, #locked))

	-- === Updated in thirds, not all at once ===
	--
	-- The fleck layer grew from 200 parts to about a thousand, and a thousand CFrame writes
	-- every frame is 60,000 a second for scenery 700 studs below the player. Each part is
	-- refreshed every third frame instead, which is 20Hz.
	--
	-- That is invisible here and would not be anywhere else: these move on periods of two
	-- to nineteen seconds, so a third of a frame's worth of lag is a fraction of a percent
	-- of a cycle. The same trick on anything the player interacts with would be obvious
	-- immediately -- it is affordable precisely because the sea is far away and slow.
	--
	-- Position still comes from the wall clock rather than from a step, so parts on
	-- different frames stay in the same wave rather than fanning out.
	local STRIDE = 3
	local frame = 0

	RunService.RenderStepped:Connect(function()
		frame += 1
		-- Wall clock, not accumulated delta, so every client's sea is at the same point in
		-- its cycle. Two players standing together should see one sea.
		local now = os.clock()

		-- The tiled surface first, all of it, every frame.
		for _, wave in ipairs(locked) do
			wave.part.CFrame = wave.origin + wave.drift * math.sin(now * wave.rate + wave.phase)
		end

		for index = (frame % STRIDE) + 1, #waves, STRIDE do
			local wave = waves[index]
			local swing = math.sin(now * wave.rate + wave.phase)
			wave.part.CFrame = wave.origin + wave.drift * swing
			if wave.fade > 0 then
				wave.part.Transparency = math.clamp(wave.transparency + wave.fade * swing, 0, 1)
			end
		end
	end)
end

return SeaService
