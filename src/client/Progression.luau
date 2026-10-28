-- Picks the single most useful next step for the HUD "Next Goal" card.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Economy = require(Shared.Config.Economy)
local Mutations = require(Shared.Config.Mutations)
local Biomes = require(Shared.Config.Biomes)
local Creatures = require(Shared.Config.Creatures)
local Tutorial = require(Shared.Config.Tutorial)
local Rules = require(Shared.Rules)
local Format = require(Shared.Util.Format)

local Net = require(script.Parent.Net)

local Progression = {}

local function affordable(data, cost): boolean
	for id, amount in pairs(cost) do
		if (data.currencies[id] or 0) < amount then
			return false
		end
	end
	return true
end

local function claimable(data): (string?, string?)
	for _, r in ipairs(Economy.Research) do
		if not data.claimed.research[r.id] and Rules.statValue(data, r.stat) >= r.goal then
			return "Shop", "rewards"
		end
	end
	for _, c in ipairs(Economy.Collection) do
		if not data.claimed.collection[c.id] and Rules.collectionValue(data, c.kind) >= c.goal then
			return "Collection", nil
		end
	end
	return nil
end

-- Finds an affordable reaction, preferring undiscovered ones.
local function suggestMutation(data)
	local best = nil
	for _, creature in ipairs(data.creatures) do
		if not creature.lock then
			for _, ingredientId in ipairs(Mutations.IngredientOrder) do
				local reaction = Mutations.findReaction(creature.species, creature.mutation, ingredientId)
				if reaction and (data.upgrades.chamber or 1) >= reaction.def.chamberLevel and affordable(data, reaction.def.cost) then
					local isNew = not data.discovered.recipes[reaction.id]
					if not best or (isNew and not best.isNew) then
						best = { creature = creature, ingredient = ingredientId, isNew = isNew }
					end
				end
			end
		end
	end
	return best
end

function Progression.nextGoal(data, Panels): (string, (() -> ())?)
	if not data.tutorial.done then
		local step = Tutorial.Steps[data.tutorial.step]
		return "Tutorial: " .. (step and step.title or ""), nil
	end
	if data.daily.canClaim then
		return "Claim your daily reward!", function()
			Panels.open("Shop", "rewards")
		end
	end
	if data.pendingCoins >= data.collectorCapacity * 0.95 then
		return "Collector is full! Go home and collect.", function()
			Net.request("Travel", "island")
		end
	end
	local placed, stored = 0, nil
	for _, c in ipairs(data.creatures) do
		if c.slot then
			placed += 1
		elseif not c.lock then
			stored = stored or c
		end
	end
	if stored and placed < data.padCount then
		return "Place " .. Creatures.Species[stored.species].name .. " on a free pad", function()
			Panels.open("Inventory", stored.id)
		end
	end
	local panel, arg = claimable(data)
	if panel then
		return "A milestone reward is ready to claim!", function()
			Panels.open(panel, arg)
		end
	end
	if not data.activeMutation then
		local suggestion = suggestMutation(data)
		if suggestion then
			local name = Creatures.Species[suggestion.creature.species].name
			local ingredient = Mutations.Ingredients[suggestion.ingredient].name
			return (if suggestion.isNew then "Experiment: " else "Mutate ") .. name .. " + " .. ingredient, function()
				Panels.open("Chamber", { creatureId = suggestion.creature.id, ingredient = suggestion.ingredient })
			end
		end
	end
	local cheapest = nil
	for _, id in ipairs(Economy.UpgradeOrder) do
		local info = Rules.upgradeInfo(data.upgrades, id)
		if info and not info.blocked and info.price and (not cheapest or info.price < cheapest.price) then
			cheapest = info
		end
	end
	if cheapest and data.currencies.coins >= cheapest.price then
		return "Buy " .. cheapest.name .. " (" .. Format.number(cheapest.price) .. ")", function()
			Panels.open("Shop", "upgrades")
		end
	end
	for _, id in ipairs(Biomes.Order) do
		local status = Rules.biomeStatus(data, id)
		if status and not status.unlocked then
			local missing = {}
			for _, check in ipairs(status.checks) do
				if not check.met then
					table.insert(missing, check.text)
				end
			end
			local text = if status.canUnlock
				then "Unlock " .. Biomes.Defs[id].name .. "!"
				else "Next biome: " .. Biomes.Defs[id].name .. " (" .. table.concat(missing, ", ") .. ")"
			return text, function()
				Panels.open("Travel")
			end
		end
	end
	if cheapest then
		return "Save up for " .. cheapest.name .. " (" .. Format.number(cheapest.price) .. ")", function()
			Panels.open("Shop", "upgrades")
		end
	end
	return "Discover every recipe in your Journal!", function()
		Panels.open("Journal")
	end
end

return Progression
