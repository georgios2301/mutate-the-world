-- Creature ownership inside a profile. A creature exists in exactly one profile at a time;
-- add/remove are the only ways ownership changes.
local Shared = game:GetService("ReplicatedStorage").Shared
local Creatures = require(Shared.Config.Creatures)
local Mutations = require(Shared.Config.Mutations)
local Rules = require(Shared.Rules)

local Locks = require(script.Parent.Locks)

local Inventory = {}

local idGenerator: (() -> string)? = nil
local counter = 0

-- The server injects HttpService:GenerateGUID; tests use the counter fallback.
function Inventory.setIdGenerator(fn: () -> string)
	idGenerator = fn
end

function Inventory.newId(): string
	if idGenerator then
		return (idGenerator :: () -> string)()
	end
	counter += 1
	return "c" .. counter
end

-- opts: { id, mutation, level, seed, now, protection, starter, source }
function Inventory.newCreature(speciesId: string, opts)
	opts = opts or {}
	local now = opts.now or 0
	return {
		id = opts.id or Inventory.newId(),
		species = speciesId,
		mutation = opts.mutation or "none",
		level = opts.level or 1,
		seed = opts.seed or 1,
		acquiredAt = now,
		protectedUntil = now + (opts.protection or 0),
		starter = opts.starter == true,
		source = opts.source or "unknown",
	}
end

function Inventory.get(profile, id: string)
	return profile.creatures[id]
end

function Inventory.count(profile): number
	local n = 0
	for _ in pairs(profile.creatures) do
		n += 1
	end
	return n
end

function Inventory.capacity(profile): number
	return Rules.storageCapacity(profile.upgrades, profile.passBonuses)
end

function Inventory.padCount(profile): number
	return Rules.padCount(profile.upgrades, profile.passBonuses)
end

function Inventory.hasSpace(profile, extra: number?): boolean
	return Inventory.count(profile) + (extra or 1) <= Inventory.capacity(profile)
end

-- Records species / species+mutation discoveries. Returns { newSpecies, newCombo }.
function Inventory.recordDiscovery(profile, speciesId: string, mutationId: string)
	local d = profile.discovered
	local newSpecies = not d.species[speciesId]
	d.species[speciesId] = true
	local combo = speciesId .. ":" .. mutationId
	local newCombo = not d.combos[combo]
	d.combos[combo] = true
	return { newSpecies = newSpecies, newCombo = newCombo }
end

-- opts: { ignoreCapacity = boolean }
function Inventory.add(profile, creature, opts)
	opts = opts or {}
	if type(creature) ~= "table" or type(creature.id) ~= "string" then
		return false, "Invalid creature"
	end
	if profile.creatures[creature.id] then
		return false, "Duplicate creature id"
	end
	if not Creatures.Species[creature.species] then
		return false, "Unknown species"
	end
	if not Mutations.Types[creature.mutation] then
		return false, "Unknown mutation"
	end
	if not opts.ignoreCapacity and not Inventory.hasSpace(profile) then
		return false, "Creature storage is full"
	end
	creature.slot = nil
	profile.creatures[creature.id] = creature
	return true, Inventory.recordDiscovery(profile, creature.species, creature.mutation)
end

function Inventory.remove(profile, id: string)
	local creature = profile.creatures[id]
	if not creature then
		return nil
	end
	profile.creatures[id] = nil
	creature.slot = nil
	return creature
end

function Inventory.slotOccupant(profile, slot: number)
	for _, creature in pairs(profile.creatures) do
		if creature.slot == slot then
			return creature
		end
	end
	return nil
end

function Inventory.firstFreeSlot(profile): number?
	local used = {}
	for _, creature in pairs(profile.creatures) do
		if creature.slot then
			used[creature.slot] = true
		end
	end
	for slot = 1, Inventory.padCount(profile) do
		if not used[slot] then
			return slot
		end
	end
	return nil
end

-- Places a creature on a display pad. slot = nil picks the first free pad.
function Inventory.place(profile, id: string, slot: number?)
	local creature = profile.creatures[id]
	if not creature then
		return false, "You don't own that creature"
	end
	if profile.activeMutation and profile.activeMutation.creatureId == id then
		return false, "That creature is in the Mutation Chamber"
	end
	local lock = Locks.get(id)
	if lock and lock.kind == "trade" then
		return false, "That creature is offered in a trade"
	end
	if lock and lock.kind == "heist" then
		return false, "Someone is stealing it right now! Defend it!"
	end
	local pads = Inventory.padCount(profile)
	if slot == nil then
		if creature.slot then
			return true, creature.slot
		end
		slot = Inventory.firstFreeSlot(profile)
		if not slot then
			return false, "All pads are full. Buy more pads or remove a creature"
		end
	end
	if type(slot) ~= "number" or slot % 1 ~= 0 or slot < 1 or slot > pads then
		return false, "That pad isn't unlocked"
	end
	local occupant = Inventory.slotOccupant(profile, slot)
	if occupant and occupant.id ~= id then
		return false, "That pad is taken"
	end
	creature.slot = slot
	return true, slot
end

function Inventory.unplace(profile, id: string)
	local creature = profile.creatures[id]
	if not creature then
		return false, "You don't own that creature"
	end
	local lock = Locks.get(id)
	if lock and lock.kind == "heist" then
		return false, "Someone is stealing it right now! Defend it!"
	end
	creature.slot = nil
	return true
end

-- Removes slots that are out of range or duplicated (after loading or a pad change).
function Inventory.validateSlots(profile)
	local pads = Inventory.padCount(profile)
	local used = {}
	for _, creature in pairs(profile.creatures) do
		local slot = creature.slot
		if slot ~= nil then
			if type(slot) ~= "number" or slot < 1 or slot > pads or slot % 1 ~= 0 or used[slot] then
				creature.slot = nil
			else
				used[slot] = true
			end
		end
	end
end

function Inventory.incomePerSecond(profile): number
	local total = 0
	local pads = Inventory.padCount(profile)
	for _, creature in pairs(profile.creatures) do
		if creature.slot and creature.slot <= pads then
			total += Rules.creatureIncome(creature)
		end
	end
	return total
end

function Inventory.placedCount(profile): number
	local n = 0
	for _, creature in pairs(profile.creatures) do
		if creature.slot then
			n += 1
		end
	end
	return n
end

return Inventory
