--!strict
-- StarterPlayerScripts/Services/CloudService.lua
-- Drifts the backdrop's vapour banks across the sky and recycles them out of sight.
--
-- WHY THIS IS NOT PART OF SeaService, which already animates backdrop parts: that loop
-- sways things about a FIXED ORIGIN on a sine, which is right for water and wrong for
-- weather. A cloud has to travel in one direction indefinitely, and the only way to do
-- that with a finite number of parts is to wrap them round -- take the one that has just
-- left at the far edge and put it back at the near edge. Minecraft's cloud layer is
-- exactly this, and so is every flight-sim sky since the nineties.
--
-- The wrap is the part that has to be invisible, and this is where the Atmosphere earns
-- its keep: a cloud is faded out over the last stretch before the boundary and faded back
-- in after it, so the swap happens inside haze that was already hiding it. Pop it in at
-- full opacity and the recycling is the only thing anyone will look at.
--
-- CLIENT SIDE ON PURPOSE. The banks belong to the server's Persistent backdrop model, and
-- moving 300 parts on the server would replicate every one of those CFrames to every
-- player forever, for scenery. Nothing about a cloud's position needs to agree between
-- clients, so each one drifts its own copy for free.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CloudService = {}

-- Studs per second. Slow: a full lap of the field takes about eleven minutes, which is
-- roughly the rate real high cloud crosses a horizon. Fast enough that the sky is never
-- static, far too slow to catch anything moving if you look for it.
local SPEED = 14

-- The wind, as a unit vector. One direction for the entire field, because that is what a
-- cloud deck is -- air moving as a body. Per-cloud directions would look like litter.
local WIND = Vector3.new(0.82, 0, 0.57).Unit

-- Half the wrap corridor. Banks are seeded out to 4600 studs, so this sits beyond the
-- furthest of them and the recycle happens well past anything the player can resolve.
local REACH = 5200
local SPAN = REACH * 2

-- The fraction of REACH over which a cloud fades to nothing at each end. 0.22 is about
-- 1150 studs of travel to disappear over -- long enough that no single frame shows a
-- visible step in opacity.
local FADE_BAND = 0.22

-- Updated in thirds, like the sea. At 14 studs per second a part moves 0.7 studs between
-- updates at 20Hz, which is invisible at this distance, and it keeps 300 parts from
-- costing 300 CFrame writes every frame.
local STRIDE = 3

type Cloud = {
	part: BasePart,
	base: Vector3,
	along: number,
	transparency: number,
}

local clouds: { Cloud } = {}

local function collect(folder: Instance, centre: Vector3)
	for _, item in ipairs(folder:GetChildren()) do
		if item:IsA("BasePart") then
			local base = item.Position
			table.insert(clouds, {
				part = item,
				base = base,
				-- Where this part starts along the wind axis. Held so the wrap can be
				-- computed as a pure function of time rather than by accumulating a delta,
				-- which would drift apart between parts updated on different frames.
				along = (base - centre):Dot(WIND),
				transparency = (item:GetAttribute("BaseTransparency") :: number?) or item.Transparency,
			})
		end
	end
end

function CloudService.start()
	local backdrop = Workspace:WaitForChild("Backdrop", 30)
	local folder = backdrop and backdrop:FindFirstChild("Clouds")
	if not folder then
		-- Quiet rather than loud: a place without the vapour banks is a place with an older
		-- backdrop, not a broken one, and the sky simply stays still.
		return
	end

	-- The banks are built around the backdrop's own pivot, so that is the centre of the
	-- corridor they wrap in.
	local centre = backdrop:GetPivot().Position
	collect(folder, centre)
	if #clouds == 0 then
		return
	end

	print(("[client] Clouds drifting: %d banks"):format(#clouds))

	local frame = 0
	RunService.RenderStepped:Connect(function()
		frame += 1
		-- Wall clock rather than accumulated delta, so a client that stalls for a second
		-- resumes with the sky where it should be instead of a second behind.
		local shift = (os.clock() * SPEED) % SPAN

		for index = (frame % STRIDE) + 1, #clouds, STRIDE do
			local cloud = clouds[index]

			-- Position along the wind axis, folded into [-REACH, REACH). The modulo is
			-- what makes this a loop rather than a line: a cloud leaving one side is the
			-- same cloud arriving at the other, so a finite set covers infinite sky.
			local along = ((cloud.along + shift + REACH) % SPAN) - REACH
			cloud.part.Position = cloud.base + WIND * (along - cloud.along)

			-- Faded near both ends, so the wrap happens behind haze. Distance from the
			-- middle, normalised -- 0 in the centre of the corridor, 1 at the boundary.
			local edge = math.abs(along) / REACH
			local hidden = math.clamp((edge - (1 - FADE_BAND)) / FADE_BAND, 0, 1)
			cloud.part.Transparency = cloud.transparency + (1 - cloud.transparency) * hidden
		end
	end)
end

return CloudService
