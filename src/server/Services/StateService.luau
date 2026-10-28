-- Sends each player a read-only snapshot of their own data. Snapshots are coalesced
-- (at most one per PUSH_INTERVAL) and only ever flow server -> client.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Rules = require(Shared.Rules)

local Core = script.Parent.Parent.Core
local Inventory = require(Core.Inventory)
local Locks = require(Core.Locks)
local RewardLogic = require(Core.RewardLogic)
local EconomyLogic = require(Core.EconomyLogic)

local StateService = {}
local S

local PUSH_INTERVAL = 0.2
local dirty = {} -- [Player] = true
local ready = {} -- [Player] = true once the player is fully set up

local function now(): number
	return workspace:GetServerTimeNow()
end

function StateService.snapshot(player: Player, profile)
	local t = now()
	local creatures = {}
	for _, c in pairs(profile.creatures) do
		local lock = Locks.get(c.id)
		table.insert(creatures, {
			id = c.id,
			species = c.species,
			mutation = c.mutation,
			level = c.level,
			slot = c.slot,
			seed = c.seed,
			starter = c.starter,
			source = c.source,
			protectedUntil = c.protectedUntil,
			income = Rules.creatureIncome(c),
			lock = lock and lock.kind or nil,
		})
	end
	return {
		serverNow = t,
		persistent = S.Data.isPersistent(),
		islandIndex = S.Island.getIndex(player),
		currencies = profile.currencies,
		pendingCoins = profile.pendingCoins,
		collectorCapacity = EconomyLogic.collectorCapacity(profile),
		income = Inventory.incomePerSecond(profile),
		padCount = Inventory.padCount(profile),
		storageCapacity = Inventory.capacity(profile),
		creatures = creatures,
		upgrades = profile.upgrades,
		biomes = profile.biomes,
		discovered = profile.discovered,
		stats = profile.stats,
		xp = profile.xp,
		tutorial = profile.tutorial,
		daily = RewardLogic.dailyStatus(profile, t),
		claimed = profile.claimed,
		settings = profile.settings,
		activeMutation = profile.activeMutation,
		cosmetics = profile.cosmetics,
		passBonuses = profile.passBonuses,
		passes = S.Monetization.ownedPasses(player),
		defense = S.Defense.status(player),
		heistProtectedUntil = profile.heist.protectedUntil,
		playSeconds = profile.playSeconds,
	}
end

function StateService.push(player: Player)
	if ready[player] then
		dirty[player] = true
	end
end

function StateService.pushNow(player: Player)
	local profile = S.Data.get(player)
	if profile and ready[player] then
		dirty[player] = nil
		S.Net.event("StateUpdate"):FireClient(player, "full", StateService.snapshot(player, profile))
	end
end

-- Small per-second update so the HUD coin counter feels live without full snapshots.
function StateService.pushTick(player: Player, profile)
	if ready[player] then
		S.Net.event("StateUpdate"):FireClient(player, "tick", {
			pendingCoins = profile.pendingCoins,
			coins = profile.currencies.coins,
			serverNow = now(),
		})
	end
end

function StateService.setReady(player: Player)
	ready[player] = true
	StateService.pushNow(player)
end

function StateService.init(services)
	S = services
end

function StateService.start()
	S.Net.on("GetState", { rate = { 3, 0.5 }, push = false }, function(player, profile)
		if not ready[player] then
			return false, "Loading..."
		end
		return true, nil, StateService.snapshot(player, profile)
	end)

	Players.PlayerRemoving:Connect(function(player)
		dirty[player] = nil
		ready[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(PUSH_INTERVAL)
			for player in pairs(dirty) do
				dirty[player] = nil
				if player.Parent then
					StateService.pushNow(player)
				end
			end
		end
	end)
end

return StateService
