--!strict
-- StarterPlayerScripts/Services/AdOffers.lua
-- REWARDED VIDEO ADS (the two-hundred-and-thirteenth pass, from your note of 2026-11-13). A short video ad a player
-- chooses to watch, for something the game sells anyway: a second chance on the hardcore card (DeathService), or a run
-- boost in the shop (ShopService: the next finished run pays double). Never forced, never a gate, never while a body is
-- in danger, the reward said on the button before it is pressed, and given as soon as the ad finishes: Roblox's own
-- rules for them (create.roblox.com/docs/production/promotion/rewarded-video-ads).
--
-- How it goes: a screen asks AdOffers.ready() when it is about to offer one (Roblox asks for that as late as possible);
-- the button, if there is an ad, is shown and registered as an ad opportunity; pressed, AdOffers.watch(what) asks the
-- server (WatchAd), which checks the daily allowance (ShopCatalog.ADS) and plays the ad with the developer product as
-- its reward. The reward lands as a purchase does (EconomyService.receipt) and is saved before it is given. The server
-- says how the ad went (WatchAd back to this client), and AdOffers.finished passes that on.
--
-- In Studio Roblox serves no ads; there the server pretends one was watched to the end, so the whole way can be tested.

local AdService = game:GetService("AdService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AdOffers = {}

local remote: RemoteEvent? = nil
local listeners: { (what: string, ok: boolean, outcome: string) -> () } = {}

local function event(): RemoteEvent?
	if remote then
		return remote
	end
	local events = ReplicatedStorage:FindFirstChild("RemoteEvents")
	local found = events and events:FindFirstChild("WatchAd")
	if found and found:IsA("RemoteEvent") then
		remote = found
		found.OnClientEvent:Connect(function(what: any, ok: any, outcome: any)
			for _, listener in ipairs(listeners) do
				task.spawn(listener, tostring(what), ok == true, tostring(outcome))
			end
		end)
	end
	return remote
end

-- Whether an ad can be shown to this player right now. Yields; false on any doubt.
function AdOffers.ready(): boolean
	if RunService:IsStudio() then
		return event() ~= nil
	end
	local ok, result = pcall(function(): any
		return AdService:GetAdAvailabilityNowAsync(Enum.AdFormat.RewardedVideo)
	end)
	return ok and type(result) == "table" and result.AdAvailabilityResult == Enum.AdAvailabilityResult.IsAvailable
end

-- Tells Roblox this button is a chance to watch an ad (its own dashboard counts how often one is taken).
function AdOffers.register(button: GuiButton)
	task.spawn(function()
		pcall(function()
			AdService:RegisterAdOpportunityAsync(button)
		end)
	end)
end

function AdOffers.unregister(button: GuiButton)
	pcall(function()
		AdService:UnregisterAdOpportunity(button)
	end)
end

-- Asks the server to play an ad for `what` ("chance" or "boost").
function AdOffers.watch(what: string): boolean
	local r = event()
	if not r then
		return false
	end
	r:FireServer(what)
	return true
end

-- Called with (what, ok, outcome) when the server says how an ad went: outcome is Roblox's ShowAdResult by name, or
-- "limit" (today's are used), "busy", "unknown".
function AdOffers.finished(listener: (what: string, ok: boolean, outcome: string) -> ())
	event()
	table.insert(listeners, listener)
end

AdOffers.STAMP = "2a031c81"
return AdOffers
