-- Mutation chamber logic. A mutation is a two-step transaction stored in the profile:
--   start():    validate everything, spend resources, store `activeMutation` (atomic, no yields)
--   complete(): when the timer is done, apply the stored result and clear the job (idempotent)
-- Because the job lives in the saved profile, a disconnect or server shutdown mid-mutation
-- resumes or completes it on the next load: never refunded twice, never rewarded twice.
local Shared = game:GetService("ReplicatedStorage").Shared
local Creatures = require(Shared.Config.Creatures)
local Mutations = require(Shared.Config.Mutations)
local Economy = require(Shared.Config.Economy)

local Wallet = require(script.Parent.Wallet)
local Inventory = require(script.Parent.Inventory)
local Locks = require(script.Parent.Locks)
local EconomyLogic = require(script.Parent.EconomyLogic)

local MutationLogic = {}

-- Explains why nothing reacts, so players learn instead of guessing blindly.
local function noReactionMessage(creature, ingredientId: string): string
	local ingredient = Mutations.Ingredients[ingredientId]
	local mutation = Mutations.Types[creature.mutation]
	if creature.mutation == "none" then
		if ingredientId == "cosmic" then
			return "Cosmic Energy is too strong for an unmutated creature. Try an elemental crystal first."
		end
		if ingredientId == "dna" then
			return "Pure DNA only stabilises special evolutions. Try an elemental crystal."
		end
	end
	if mutation and mutation.tier >= 3 then
		return mutation.name .. " creatures are already at their peak. Only special evolutions remain."
	end
	return "No reaction: " .. ingredient.name .. " doesn't combine with " .. (mutation and mutation.name or "this") .. " creatures. Check your Journal for hints."
end

-- Returns reaction + final cost + duration, or nil + reason.
function MutationLogic.preview(profile, creatureId: string, ingredientId: string)
	local creature = profile.creatures[creatureId]
	if not creature then
		return nil, "You don't own that creature"
	end
	if not Mutations.Ingredients[ingredientId] then
		return nil, "Unknown ingredient"
	end
	local reaction = Mutations.findReaction(creature.species, creature.mutation, ingredientId)
	if not reaction then
		return nil, noReactionMessage(creature, ingredientId)
	end
	local chamberLevel = profile.upgrades.chamber or 1
	return {
		reaction = reaction,
		cost = reaction.def.cost,
		duration = Mutations.duration(reaction.def, chamberLevel),
		chamberOk = chamberLevel >= reaction.def.chamberLevel,
	}
end

function MutationLogic.start(profile, creatureId: string, ingredientId: string, now: number)
	if profile.activeMutation then
		return false, "The chamber is already busy"
	end
	local creature = profile.creatures[creatureId]
	if not creature then
		return false, "You don't own that creature"
	end
	if not Locks.isFree(profile, creatureId) then
		return false, "That creature is busy right now"
	end
	local preview, reason = MutationLogic.preview(profile, creatureId, ingredientId)
	if not preview then
		return false, reason
	end
	if not preview.chamberOk then
		return false, "Requires Mutation Chamber level " .. preview.reaction.def.chamberLevel
	end
	local ok, err = Wallet.spend(profile, preview.cost)
	if not ok then
		return false, err
	end
	-- From here on nothing can fail: resources are spent and the job is recorded together.
	creature.slot = nil
	local costCopy = {}
	for id, amount in pairs(preview.cost) do
		costCopy[id] = amount
	end
	local job = {
		creatureId = creatureId,
		reactionId = preview.reaction.id,
		kind = preview.reaction.kind,
		resultSpecies = preview.reaction.resultSpecies,
		resultMutation = preview.reaction.resultMutation,
		startedAt = now,
		endsAt = now + preview.duration,
		cost = costCopy,
	}
	profile.activeMutation = job
	return true, job
end

-- Applies a finished job. Returns nil if there is nothing (yet) to complete.
function MutationLogic.complete(profile, now: number)
	local job = profile.activeMutation
	if not job or now < job.endsAt then
		return nil
	end
	profile.activeMutation = nil

	local creature = profile.creatures[job.creatureId]
	if not creature or not Creatures.Species[job.resultSpecies] or not Mutations.Types[job.resultMutation] then
		-- Defensive: the creature vanished (should be impossible while locked). Refund.
		Wallet.add(profile, job.cost or {})
		return { refunded = true }
	end

	local before = { species = creature.species, mutation = creature.mutation }
	creature.species = job.resultSpecies
	creature.mutation = job.resultMutation

	local newRecipe = not profile.discovered.recipes[job.reactionId]
	profile.discovered.recipes[job.reactionId] = true
	local discovery = Inventory.recordDiscovery(profile, creature.species, creature.mutation)

	profile.stats.mutations += 1
	local xp = Economy.XP.mutation
	if job.kind == "evolution" then
		profile.stats.evolutions += 1
		xp += Economy.XP.evolution
	end
	if newRecipe then
		xp += Economy.XP.newRecipe
	end
	if discovery.newSpecies then
		xp += Economy.XP.newSpecies
	end
	local leveledUp, level = EconomyLogic.addXP(profile, xp)

	-- Put it back on a pad if one is free so income resumes automatically.
	Inventory.place(profile, creature.id)

	return {
		creature = creature,
		before = before,
		kind = job.kind,
		reactionId = job.reactionId,
		newRecipe = newRecipe,
		newSpecies = discovery.newSpecies,
		newCombo = discovery.newCombo,
		xp = xp,
		leveledUp = leveledUp,
		level = level,
	}
end

return MutationLogic
