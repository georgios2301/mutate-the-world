-- Pure game rules shared by server (authoritative) and client (display only).
-- Takes plain data tables, never Instances, so it can be unit-tested outside Roblox.
local Config = script.Parent.Config
local Creatures = require(Config.Creatures)
local Mutations = require(Config.Mutations)
local Economy = require(Config.Economy)
local Rarity = require(Config.Rarity)
local Biomes = require(Config.Biomes)

local Rules = {}

-- Player level -------------------------------------------------------------

function Rules.xpForLevel(level: number): number
	if level <= 1 then
		return 0
	end
	return math.floor(80 * (level - 1) ^ 1.7)
end

function Rules.levelFromXP(xp: number): number
	local level = 1
	while level < 200 and xp >= Rules.xpForLevel(level + 1) do
		level += 1
	end
	return level
end

-- Returns level, xp into this level, xp needed for the next level.
function Rules.levelProgress(xp: number)
	local level = Rules.levelFromXP(xp)
	local base = Rules.xpForLevel(level)
	local nextXp = Rules.xpForLevel(level + 1)
	return level, xp - base, nextXp - base
end

-- Creatures ----------------------------------------------------------------

function Rules.creatureIncome(creature): number
	local species = Creatures.Species[creature.species]
	if not species then
		return 0
	end
	local mutation = Mutations.Types[creature.mutation] or Mutations.Types.none
	local levelMult = 1 + (math.max(1, creature.level or 1) - 1) * Economy.CreatureLevel.incomePerLevel
	local income = species.baseIncome * mutation.multiplier * levelMult
	if creature.mutation ~= "none" and mutation.element == species.element then
		income *= Mutations.ResonanceBonus
	end
	return income
end

function Rules.hasResonance(creature): boolean
	local species = Creatures.Species[creature.species]
	local mutation = Mutations.Types[creature.mutation]
	return species ~= nil and mutation ~= nil and creature.mutation ~= "none" and mutation.element == species.element
end

function Rules.levelUpCost(creature)
	local species = Creatures.Species[creature.species]
	if not species then
		return nil
	end
	local level = creature.level or 1
	if level >= Economy.CreatureLevel.maxLevel then
		return nil
	end
	local rarity = Rarity.Info[species.rarity]
	local cfg = Economy.CreatureLevel
	return {
		coins = math.floor(cfg.baseCoins * rarity.levelCostMult * cfg.growth ^ (level - 1)),
		dna = math.ceil(2 * rarity.rank * level),
	}
end

function Rules.isStealableSpecies(speciesId: string): boolean
	local species = Creatures.Species[speciesId]
	if not species then
		return false
	end
	if species.stealable ~= nil then
		return species.stealable
	end
	return Rarity.Info[species.rarity].stealable == true
end

function Rules.releaseReward(creature)
	local species = Creatures.Species[creature.species]
	if not species then
		return { dna = 0 }
	end
	return { dna = Rarity.Info[species.rarity].releaseDna * (creature.level or 1) }
end

-- Upgrades -----------------------------------------------------------------

function Rules.upgradeValue(upgrades, upgradeId: string): number
	local def = Economy.Upgrades[upgradeId]
	local level = math.clamp(upgrades[upgradeId] or 1, 1, #def.levels)
	return def.levels[level].value
end

function Rules.padCount(upgrades, passBonuses): number
	return Rules.upgradeValue(upgrades, "pads") + ((passBonuses and passBonuses.pads) or 0)
end

function Rules.storageCapacity(upgrades, passBonuses): number
	return Rules.upgradeValue(upgrades, "storage") + ((passBonuses and passBonuses.storage) or 0)
end

function Rules.collectorCapacity(upgrades): number
	return Rules.upgradeValue(upgrades, "collector")
end

-- Pads can only be bought up to the island's pad limit.
function Rules.maxUpgradeLevel(upgrades, upgradeId: string): number
	local def = Economy.Upgrades[upgradeId]
	if upgradeId == "pads" then
		local maxPads = Rules.upgradeValue(upgrades, "island")
		local maxLevel = 1
		for i, lvl in ipairs(def.levels) do
			if lvl.value <= maxPads then
				maxLevel = i
			end
		end
		return maxLevel
	end
	return #def.levels
end

-- Describes the next level of an upgrade: { level, maxLevel, value, nextValue, price, blocked }
function Rules.upgradeInfo(upgrades, upgradeId: string)
	local def = Economy.Upgrades[upgradeId]
	if not def then
		return nil
	end
	local level = upgrades[upgradeId] or 1
	local hardMax = #def.levels
	local allowedMax = Rules.maxUpgradeLevel(upgrades, upgradeId)
	local info = {
		id = upgradeId,
		name = def.name,
		level = level,
		maxLevel = hardMax,
		value = def.levels[math.clamp(level, 1, hardMax)].value,
	}
	if level >= hardMax then
		info.blocked = "Maxed out"
	elseif level >= allowedMax then
		info.blocked = "Expand your island first"
		info.nextValue = def.levels[level + 1].value
		info.price = def.levels[level + 1].price
	else
		info.nextValue = def.levels[level + 1].value
		info.price = def.levels[level + 1].price
	end
	return info
end

-- Biomes -------------------------------------------------------------------

function Rules.recipeCount(discovered): number
	local n = 0
	for _ in pairs(discovered.recipes) do
		n += 1
	end
	return n
end

function Rules.countKeys(t): number
	local n = 0
	for _ in pairs(t) do
		n += 1
	end
	return n
end

-- data needs: biomes, xp, upgrades, currencies, discovered
function Rules.biomeStatus(data, biomeId: string)
	local def = Biomes.Defs[biomeId]
	if not def then
		return nil
	end
	local req = def.requirements
	local status = {
		id = biomeId,
		unlocked = def.unlockedByDefault == true or data.biomes[biomeId] == true,
		checks = {},
		cost = req.coins and { coins = req.coins } or {},
	}
	local level = Rules.levelFromXP(data.xp)
	if req.level then
		table.insert(status.checks, { text = "Player level " .. req.level, met = level >= req.level })
	end
	if req.chamber then
		table.insert(status.checks, { text = "Chamber level " .. req.chamber, met = (data.upgrades.chamber or 1) >= req.chamber })
	end
	if req.recipes then
		table.insert(status.checks, {
			text = req.recipes .. " recipes discovered",
			met = Rules.recipeCount(data.discovered) >= req.recipes,
		})
	end
	if req.coins then
		table.insert(status.checks, { text = req.coins .. " coins", met = (data.currencies.coins or 0) >= req.coins })
	end
	local allMet = true
	for _, check in ipairs(status.checks) do
		if not check.met then
			allMet = false
		end
	end
	status.canUnlock = not status.unlocked and allMet
	return status
end

-- Milestones ---------------------------------------------------------------

function Rules.statValue(data, stat: string): number
	if stat == "recipes" then
		return Rules.recipeCount(data.discovered)
	end
	return data.stats[stat] or 0
end

function Rules.collectionValue(data, kind: string): number
	if kind == "species" then
		return Rules.countKeys(data.discovered.species)
	end
	return Rules.countKeys(data.discovered.combos)
end

return Rules
