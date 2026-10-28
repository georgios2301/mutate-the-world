-- Server-authoritative economy: income accrual, collecting, upgrades, creature shop,
-- creature level-ups, releases, biome unlocks and XP.
local Shared = game:GetService("ReplicatedStorage").Shared
local Creatures = require(Shared.Config.Creatures)
local Economy = require(Shared.Config.Economy)
local Biomes = require(Shared.Config.Biomes)
local Rules = require(Shared.Rules)

local Wallet = require(script.Parent.Wallet)
local Inventory = require(script.Parent.Inventory)
local Locks = require(script.Parent.Locks)

local EconomyLogic = {}

function EconomyLogic.addXP(profile, amount: number)
	local before = Rules.levelFromXP(profile.xp)
	profile.xp = math.max(0, profile.xp + math.floor(amount))
	local after = Rules.levelFromXP(profile.xp)
	return after > before, after
end

-- Income -------------------------------------------------------------------

function EconomyLogic.collectorCapacity(profile): number
	return Rules.collectorCapacity(profile.upgrades)
end

-- Adds `seconds` of income to the collector, never past its capacity. Returns coins added.
function EconomyLogic.accrue(profile, seconds: number, rate: number?): number
	if seconds <= 0 then
		return 0
	end
	local capacity = EconomyLogic.collectorCapacity(profile)
	local room = capacity - profile.pendingCoins
	if room <= 0 then
		return 0
	end
	local incomeRate = rate or Inventory.incomePerSecond(profile)
	local added = math.min(room, incomeRate * seconds)
	profile.pendingCoins += added
	return added
end

-- Moves whole coins from the collector into the wallet. Returns the amount collected.
function EconomyLogic.collect(profile): number
	local amount = math.floor(profile.pendingCoins)
	if amount <= 0 then
		return 0
	end
	profile.pendingCoins -= amount
	Wallet.add(profile, { coins = amount })
	profile.stats.totalEarned += amount
	return amount
end

-- Offline earnings since lastSeen (reduced rate, limited duration, capped by the collector).
function EconomyLogic.applyOffline(profile, now: number): number
	local elapsed = math.clamp(now - (profile.lastSeen or now), 0, Economy.Offline.maxSeconds)
	if elapsed < 60 then
		return 0
	end
	local rate = Inventory.incomePerSecond(profile) * Economy.Offline.rate
	return EconomyLogic.accrue(profile, elapsed, rate)
end

-- Upgrades -----------------------------------------------------------------

function EconomyLogic.buyUpgrade(profile, upgradeId: string)
	local info = Rules.upgradeInfo(profile.upgrades, upgradeId)
	if not info then
		return false, "Unknown upgrade"
	end
	if info.blocked then
		return false, info.blocked
	end
	local cost = { coins = info.price }
	local ok, err = Wallet.spend(profile, cost)
	if not ok then
		return false, err
	end
	profile.upgrades[upgradeId] = info.level + 1
	EconomyLogic.addXP(profile, Economy.XP.upgrade)
	return true, info.name .. " upgraded to level " .. (info.level + 1)
end

-- Creatures ----------------------------------------------------------------

function EconomyLogic.buyCreature(profile, speciesId: string, now: number, seed: number)
	local allowed = false
	for _, id in ipairs(Economy.ShopSpecies) do
		if id == speciesId then
			allowed = true
		end
	end
	local species = Creatures.Species[speciesId]
	if not allowed or not species or not species.shopPrice then
		return false, "That creature isn't for sale"
	end
	if not Inventory.hasSpace(profile) then
		return false, "Creature storage is full"
	end
	local ok, err = Wallet.spend(profile, { coins = species.shopPrice })
	if not ok then
		return false, err
	end
	local creature = Inventory.newCreature(speciesId, { now = now, seed = seed, source = "shop" })
	local added, discovery = Inventory.add(profile, creature)
	if not added then
		-- Should be impossible after the space check; refund to stay consistent.
		Wallet.add(profile, { coins = species.shopPrice })
		return false, discovery
	end
	return true, creature, discovery
end

function EconomyLogic.levelUpCreature(profile, creatureId: string)
	local creature = profile.creatures[creatureId]
	if not creature then
		return false, "You don't own that creature"
	end
	if not Locks.isFree(profile, creatureId) then
		return false, "That creature is busy right now"
	end
	local cost = Rules.levelUpCost(creature)
	if not cost then
		return false, "Already max level"
	end
	local ok, err = Wallet.spend(profile, cost)
	if not ok then
		return false, err
	end
	creature.level += 1
	return true, creature
end

function EconomyLogic.releaseCreature(profile, creatureId: string)
	local creature = profile.creatures[creatureId]
	if not creature then
		return false, "You don't own that creature"
	end
	if creature.starter then
		return false, "Your starter Blob is too loyal to leave"
	end
	if not Locks.isFree(profile, creatureId) then
		return false, "That creature is busy right now"
	end
	if Inventory.count(profile) <= 1 then
		return false, "You must keep at least one creature"
	end
	local reward = Rules.releaseReward(creature)
	Inventory.remove(profile, creatureId)
	Wallet.add(profile, reward)
	return true, reward
end

-- Biomes -------------------------------------------------------------------

function EconomyLogic.unlockBiome(profile, biomeId: string)
	local status = Rules.biomeStatus(profile, biomeId)
	if not status then
		return false, "Unknown biome"
	end
	if status.unlocked then
		return false, "Already unlocked"
	end
	if not status.canUnlock then
		for _, check in ipairs(status.checks) do
			if not check.met then
				return false, "Requires " .. check.text
			end
		end
		return false, "Requirements not met"
	end
	local ok, err = Wallet.spend(profile, status.cost)
	if not ok then
		return false, err
	end
	profile.biomes[biomeId] = true
	return true, Biomes.Defs[biomeId].name .. " unlocked!"
end

function EconomyLogic.isBiomeUnlocked(profile, biomeId: string): boolean
	local def = Biomes.Defs[biomeId]
	return def ~= nil and (def.unlockedByDefault == true or profile.biomes[biomeId] == true)
end

return EconomyLogic
