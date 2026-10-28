-- Passive income loop, coin collection and all purchase/claim actions.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Economy = require(Shared.Config.Economy)
local Creatures = require(Shared.Config.Creatures)
local Format = require(Shared.Util.Format)

local Core = script.Parent.Parent.Core
local EconomyLogic = require(Core.EconomyLogic)
local RewardLogic = require(Core.RewardLogic)
local Inventory = require(Core.Inventory)
local Validate = require(Core.Validate)

local EconomyService = {}
local S

local rng = Random.new()
local lastLabel = {} -- [userId] = last collector label text

local function now(): number
	return workspace:GetServerTimeNow()
end

local function rewardText(reward): string
	return Format.cost(reward, Economy.CurrencyInfo, Economy.CurrencyIds)
end

local function updateCollectorLabel(player: Player, profile)
	local island = S.Island.get(player)
	if not island then
		return
	end
	local capacity = EconomyLogic.collectorCapacity(profile)
	local pending = math.floor(profile.pendingCoins)
	local full = pending >= capacity
	local text = string.format(
		"COLLECTOR\n<font size='20' color='#%s'>● %s / %s</font>",
		if full then "ff6b6b" else "ffe17a",
		Format.number(pending),
		Format.number(capacity)
	)
	if lastLabel[player.UserId] ~= text then
		lastLabel[player.UserId] = text
		island.collector.label.Text = text
	end
end

function EconomyService.collect(player: Player)
	local profile = S.Data.get(player)
	local island = S.Island.get(player)
	if not profile or not island then
		return false, "Still loading"
	end
	if not S.Island.isNear(player, island) then
		return false, "Go to your island's Collector to collect coins"
	end
	local amount = EconomyLogic.collect(profile)
	if amount <= 0 then
		return false, "Nothing to collect yet"
	end
	if amount >= 10 then
		EconomyLogic.addXP(profile, Economy.XP.collect)
	end
	updateCollectorLabel(player, profile)
	S.Tutorial.event(player, "collect")
	S.Data.markDirty(player)
	S.State.push(player)
	return true, "+" .. Format.number(amount) .. " coins", { amount = amount }
end

function EconomyService.onPlayerReady(player: Player, profile)
	local offline = EconomyLogic.applyOffline(profile, now())
	if offline >= 1 then
		task.delay(4, function()
			if player.Parent then
				S.Net.notify(player, "While you were away your creatures earned " .. Format.number(offline) .. " coins!", "success")
			end
		end)
	end
	updateCollectorLabel(player, profile)
end

function EconomyService.init(services)
	S = services
end

function EconomyService.start()
	-- Passive income: one cheap pass per second over all loaded players.
	task.spawn(function()
		local last = now()
		while true do
			task.wait(1)
			local t = now()
			local dt = math.clamp(t - last, 0, 5)
			last = t
			for _, player in ipairs(Players:GetPlayers()) do
				local profile = S.Data.get(player)
				if profile and S.Island.get(player) then
					local added = EconomyLogic.accrue(profile, dt, S.Creature.getRate(player))
					if added > 0 then
						S.Data.markDirty(player)
					end
					updateCollectorLabel(player, profile)
					S.Creature.updateProtectionLabels(player, profile)
					S.State.pushTick(player, profile)
				end
			end
		end
	end)

	for _, island in pairs(S.Island.all()) do
		island.collectorPrompt.Triggered:Connect(function(player)
			if island.owner ~= player then
				return
			end
			local ok, msg = EconomyService.collect(player)
			if msg then
				S.Net.notify(player, msg, if ok then "success" else "info")
			end
		end)
	end

	S.Net.on("CollectCoins", { rate = { 4, 2 }, push = false }, function(player)
		return EconomyService.collect(player)
	end)

	S.Net.on("BuyUpgrade", { rate = { 5, 2 } }, function(player, profile, upgradeId)
		if not Validate.oneOf(upgradeId, Economy.Upgrades) then
			return false, "Unknown upgrade"
		end
		local ok, msg = EconomyLogic.buyUpgrade(profile, upgradeId)
		if ok then
			Inventory.validateSlots(profile)
			S.Island.refresh(player)
			S.Creature.refreshIsland(player)
			S.Defense.onUpgrade(player)
		end
		return ok, msg
	end)

	S.Net.on("BuyCreature", { rate = { 4, 2 } }, function(player, profile, speciesId)
		if not Validate.oneOf(speciesId, Creatures.Species) then
			return false, "Unknown creature"
		end
		local ok, creature, discovery = EconomyLogic.buyCreature(profile, speciesId, now(), rng:NextInteger(1, 2 ^ 30))
		if not ok then
			return false, creature
		end
		local placed = Inventory.place(profile, creature.id)
		S.Creature.refreshIsland(player)
		if discovery and discovery.newSpecies then
			S.Discovery.announceSpecies(player, creature)
		end
		return true, Creatures.Species[speciesId].name .. (if placed then " placed on a pad!" else " added to storage")
	end)

	S.Net.on("UnlockBiome", { rate = { 3, 1 } }, function(player, profile, biomeId)
		if not Validate.id(biomeId) then
			return false, "Unknown biome"
		end
		return EconomyLogic.unlockBiome(profile, biomeId)
	end)

	S.Net.on("ClaimDaily", { rate = { 3, 1 } }, function(player, profile)
		local ok, reward, day = RewardLogic.claimDaily(profile, now())
		if not ok then
			return false, reward
		end
		EconomyLogic.addXP(profile, Economy.XP.daily)
		return true, string.format("Day %d reward: %s", day, rewardText(reward))
	end)

	S.Net.on("ClaimResearch", { rate = { 4, 2 } }, function(player, profile, id)
		if not Validate.id(id) then
			return false, "Unknown milestone"
		end
		local ok, reward = RewardLogic.claimResearch(profile, id)
		if not ok then
			return false, reward
		end
		return true, "Research reward: " .. rewardText(reward)
	end)

	S.Net.on("ClaimCollection", { rate = { 4, 2 } }, function(player, profile, id)
		if not Validate.id(id) then
			return false, "Unknown milestone"
		end
		local ok, reward = RewardLogic.claimCollection(profile, id)
		if not ok then
			return false, reward
		end
		return true, "Collection reward: " .. rewardText(reward)
	end)

	local SETTINGS = {
		music = "boolean",
		sfx = "boolean",
		popups = "boolean",
		reducedEffects = "boolean",
		uiScale = "number",
	}
	S.Net.on("SetSetting", { rate = { 10, 4 } }, function(player, profile, key, value)
		if not Validate.oneOf(key, SETTINGS) or type(value) ~= SETTINGS[key] then
			return false, "Invalid setting"
		end
		if key == "uiScale" and not (Validate.finite(value) and value >= 0.7 and value <= 1.6) then
			return false, "Invalid setting"
		end
		profile.settings[key] = value
		return true
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastLabel[player.UserId] = nil
	end)
end

return EconomyService
