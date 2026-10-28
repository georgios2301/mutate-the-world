-- Player data shape, defaults, migrations and sanitizing of loaded data.
local Shared = game:GetService("ReplicatedStorage").Shared
local Creatures = require(Shared.Config.Creatures)
local Mutations = require(Shared.Config.Mutations)
local Economy = require(Shared.Config.Economy)
local Biomes = require(Shared.Config.Biomes)
local Products = require(Shared.Config.Products)
local Tutorial = require(Shared.Config.Tutorial)

local Inventory = require(script.Parent.Inventory)

local DataSchema = {}

DataSchema.VERSION = 2

function DataSchema.default(now: number)
	local currencies = {}
	for id, amount in pairs(Economy.StartingCurrencies) do
		currencies[id] = amount
	end
	local biomes = {}
	for id, def in pairs(Biomes.Defs) do
		if def.unlockedByDefault then
			biomes[id] = true
		end
	end
	return {
		version = DataSchema.VERSION,
		createdAt = now,
		lastSeen = now,
		playSeconds = 0,
		currencies = currencies,
		pendingCoins = 0,
		creatures = {},
		upgrades = { pads = 1, collector = 1, chamber = 1, island = 1, security = 1, storage = 1 },
		biomes = biomes,
		discovered = { species = {}, recipes = {}, combos = {} },
		stats = {
			totalEarned = 0,
			mutations = 0,
			evolutions = 0,
			captures = 0,
			steals = 0,
			stolenFrom = 0,
			defended = 0,
			failedHeists = 0,
			trades = 0,
		},
		xp = 0,
		tutorial = { step = 1, done = false, skipped = false, rewarded = false, everDone = false, dna = 0, ice = 0 },
		daily = { lastDay = 0, streak = 0 },
		claimed = { research = {}, collection = {} },
		settings = { sfx = true, popups = true, reducedEffects = false, uiScale = 1 },
		heist = { protectedUntil = 0, shieldCooldownUntil = 0 },
		cosmetics = { themes = { default = true }, theme = "default", auras = {}, aura = "" },
		purchases = { ids = {}, order = {} },
		passBonuses = { storage = 0, pads = 0 },
		flags = { starterGiven = false },
		-- activeMutation = { creatureId, reactionId, kind, resultSpecies, resultMutation, startedAt, endsAt, cost }
	}
end

-- Migrations: index n upgrades data from version n to n + 1.
local MIGRATIONS = {
	[1] = function(data)
		-- v1 -> v2: settings gained uiScale, tutorial tracks pickups, heist protection moved into a table.
		data.settings = data.settings or {}
		data.settings.uiScale = data.settings.uiScale or 1
		if type(data.heistProtectedUntil) == "number" then
			data.heist = { protectedUntil = data.heistProtectedUntil }
			data.heistProtectedUntil = nil
		end
	end,
}

-- Copies missing keys from `template` into `target` (recursively for tables).
local function reconcile(target, template)
	for key, value in pairs(template) do
		if target[key] == nil then
			if type(value) == "table" then
				local copy = {}
				reconcile(copy, value)
				target[key] = copy
			else
				target[key] = value
			end
		elseif type(value) == "table" and type(target[key]) == "table" then
			-- Only reconcile "record" tables, not open maps such as creatures/discoveries.
			if next(value) ~= nil then
				reconcile(target[key], value)
			end
		elseif type(target[key]) ~= type(value) then
			target[key] = value
		end
	end
end

local function cleanNumber(v, min, max, default)
	if type(v) ~= "number" or v ~= v then
		return default
	end
	return math.clamp(v, min, max)
end

-- Repairs anything a bad save, config change or exploit could have left behind.
function DataSchema.sanitize(data, now: number)
	for _, id in ipairs(Economy.CurrencyIds) do
		data.currencies[id] = math.floor(cleanNumber(data.currencies[id], 0, Economy.MaxCurrency, 0))
	end
	data.pendingCoins = cleanNumber(data.pendingCoins, 0, Economy.MaxCurrency, 0)
	data.xp = math.floor(cleanNumber(data.xp, 0, 1e12, 0))

	for id, def in pairs(Economy.Upgrades) do
		data.upgrades[id] = math.floor(cleanNumber(data.upgrades[id], 1, #def.levels, 1))
	end

	for id, creature in pairs(data.creatures) do
		if type(creature) ~= "table" or creature.id ~= id then
			data.creatures[id] = nil
		else
			if not Creatures.Species[creature.species] then
				warn("[DataSchema] Unknown species", creature.species, "-> basic_blob")
				creature.species = "basic_blob"
			end
			if not Mutations.Types[creature.mutation] then
				creature.mutation = "none"
			end
			creature.level = math.floor(cleanNumber(creature.level, 1, Economy.CreatureLevel.maxLevel, 1))
			creature.seed = math.floor(cleanNumber(creature.seed, 0, 2 ^ 31, 1))
			creature.protectedUntil = cleanNumber(creature.protectedUntil, 0, now + 86400, 0)
			creature.acquiredAt = cleanNumber(creature.acquiredAt, 0, now + 60, now)
			creature.starter = creature.starter == true
			if type(creature.source) ~= "string" then
				creature.source = "unknown"
			end
		end
	end
	Inventory.validateSlots(data)

	for id in pairs(data.biomes) do
		if not Biomes.Defs[id] then
			data.biomes[id] = nil
		end
	end
	for id, def in pairs(Biomes.Defs) do
		if def.unlockedByDefault then
			data.biomes[id] = true
		end
	end

	for id in pairs(data.discovered.recipes) do
		if not Mutations.RecipeById[id] and not Mutations.EvolutionById[id] then
			data.discovered.recipes[id] = nil
		end
	end

	-- Ownership of pass themes is verified each session by MonetizationService.
	if not Products.Themes[data.cosmetics.theme] then
		data.cosmetics.theme = "default"
	end
	data.cosmetics.themes.default = true

	-- Bounded receipt history (oldest dropped first).
	local purchases = data.purchases
	while #purchases.order > 100 do
		local old = table.remove(purchases.order, 1)
		purchases.ids[old] = nil
	end

	local job = data.activeMutation
	if job ~= nil then
		if type(job) ~= "table" or not data.creatures[job.creatureId] then
			DataSchema.refundJob(data, job)
			data.activeMutation = nil
		end
	end

	data.tutorial.step = math.floor(cleanNumber(data.tutorial.step, 1, #Tutorial.Steps, 1))
	if data.tutorial.done then
		data.tutorial.everDone = true -- sticky: replaying the tutorial never restores protection
	end
	return data
end

-- If a saved mutation lost its creature (should never happen), give the resources back.
function DataSchema.refundJob(data, job)
	if type(job) == "table" and type(job.cost) == "table" then
		for id, amount in pairs(job.cost) do
			if data.currencies[id] ~= nil and type(amount) == "number" and amount > 0 then
				data.currencies[id] = math.min(Economy.MaxCurrency, data.currencies[id] + math.floor(amount))
			end
		end
	end
end

-- Takes whatever came out of the DataStore and returns valid current-version data.
function DataSchema.load(raw, now: number)
	if type(raw) ~= "table" then
		return DataSchema.default(now), true
	end
	local version = tonumber(raw.version) or 1
	while version < DataSchema.VERSION do
		local migrate = MIGRATIONS[version]
		if migrate then
			migrate(raw)
		end
		version += 1
	end
	raw.version = DataSchema.VERSION
	reconcile(raw, DataSchema.default(now))
	DataSchema.sanitize(raw, now)
	return raw, false
end

-- Gives the starter creature exactly once per account.
function DataSchema.ensureStarter(data, now: number, seed: number)
	if data.flags.starterGiven then
		return nil
	end
	data.flags.starterGiven = true
	local creature = Inventory.newCreature(Creatures.StarterSpecies, {
		now = now,
		seed = seed,
		starter = true,
		source = "starter",
	})
	Inventory.add(data, creature, { ignoreCapacity = true })
	creature.slot = 1
	return creature
end

return DataSchema
