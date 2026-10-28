-- Tutorial progression. Steps advance on server-observed events (collect, pickups, mutation,
-- defense) or on the player's Next/Skip. Progress is saved in the profile.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Tutorial = require(Shared.Config.Tutorial)
local Format = require(Shared.Util.Format)
local Economy = require(Shared.Config.Economy)

local Core = script.Parent.Parent.Core
local Wallet = require(Core.Wallet)

local TutorialService = {}
local S

local function currentStep(profile)
	return Tutorial.Steps[profile.tutorial.step]
end

local function complete(player: Player, profile, skipped: boolean)
	local t = profile.tutorial
	if t.done then
		return
	end
	t.done = true
	t.everDone = true
	t.skipped = skipped
	if not skipped and not t.rewarded and profile.stats.mutations >= 1 then
		t.rewarded = true
		Wallet.add(profile, Tutorial.CompletionReward)
		S.Net.notify(player, "Tutorial complete! +" .. Format.cost(Tutorial.CompletionReward, Economy.CurrencyInfo, Economy.CurrencyIds), "success")
	end
	S.Data.markDirty(player)
	S.State.push(player)
end

local function resourcesDone(profile, step): boolean
	local t = profile.tutorial
	local dnaOk = t.dna >= step.needDna or profile.currencies.dna >= 5
	local iceOk = t.ice >= step.needIce or profile.currencies.ice >= 1
	return dnaOk and iceOk
end

local function advance(player: Player, profile)
	local t = profile.tutorial
	t.step += 1
	t.dna = 0
	t.ice = 0
	if t.step > #Tutorial.Steps then
		t.step = #Tutorial.Steps
		complete(player, profile, false)
		return
	end
	local step = currentStep(profile)
	-- Skip steps the player already satisfied (e.g. already owns the resources).
	if step.advance == "resources" and resourcesDone(profile, step) then
		advance(player, profile)
		return
	end
	if step.advance == "mutation" and profile.stats.mutations >= 1 then
		advance(player, profile)
		return
	end
	S.Data.markDirty(player)
	S.State.push(player)
end

-- name: "collect" | "dna" | "ice" | "chamberOpened" | "mutation" | "defense"
function TutorialService.event(player: Player, name: string, amount: number?)
	local profile = S.Data.get(player)
	if not profile or profile.tutorial.done then
		return
	end
	local step = currentStep(profile)
	if not step then
		return
	end
	local t = profile.tutorial
	if step.advance == "collect" and name == "collect" then
		advance(player, profile)
	elseif step.advance == "resources" then
		if name == "dna" then
			t.dna += amount or 0
		elseif name == "ice" then
			t.ice += amount or 0
		end
		if resourcesDone(profile, step) then
			advance(player, profile)
		else
			S.State.push(player)
		end
	elseif step.advance == "chamber" and name == "chamberOpened" then
		advance(player, profile)
	elseif step.advance == "mutation" and name == "mutation" then
		advance(player, profile)
	elseif step.advance == "defense" and name == "defense" then
		advance(player, profile)
	end
end

function TutorialService.onPlayerReady(player: Player, profile)
	local t = profile.tutorial
	if not t.done and S.Data.isNewPlayer(player) then
		t.step = 1
	end
end

function TutorialService.init(services)
	S = services
end

function TutorialService.start()
	S.Net.on("TutorialAction", { rate = { 6, 2 } }, function(player, profile, kind)
		local t = profile.tutorial
		if kind == "skip" then
			complete(player, profile, true)
			return true, "Tutorial skipped. You can replay it from Settings."
		elseif kind == "restart" then
			t.done = false
			t.skipped = false
			t.step = 1
			t.dna = 0
			t.ice = 0
			return true
		elseif kind == "chamberOpened" then
			TutorialService.event(player, "chamberOpened")
			return true
		elseif kind == "next" then
			if t.done then
				return false
			end
			local step = currentStep(profile)
			if step.advance ~= "manual" and step.advance ~= "defense" then
				return false, "Finish this step first"
			end
			advance(player, profile)
			return true
		end
		return false, "Unknown tutorial action"
	end)
end

return TutorialService
