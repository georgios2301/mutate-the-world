-- Theft eligibility and resolution. The HeistService owns timers, distance checks and
-- notifications; this module decides who may steal what and performs the transfer once.
local Shared = game:GetService("ReplicatedStorage").Shared
local Creatures = require(Shared.Config.Creatures)
local Heist = require(Shared.Config.Heist)
local Economy = require(Shared.Config.Economy)
local Rules = require(Shared.Rules)

local Wallet = require(script.Parent.Wallet)
local Inventory = require(script.Parent.Inventory)
local Locks = require(script.Parent.Locks)
local EconomyLogic = require(script.Parent.EconomyLogic)

local HeistLogic = {}

function HeistLogic.channelTime(securityLevel: number): number
	return Heist.ChannelTime + math.max(0, securityLevel - 1) * Heist.ChannelPerSecurityLevel
end

function HeistLogic.successChance(securityLevel: number): number
	local chance = Heist.BaseSuccess + math.max(0, securityLevel - 1) * Heist.SuccessPerSecurityLevel
	return math.max(Heist.MinSuccess, chance)
end

-- True if the victim is covered by new-player protection.
function HeistLogic.isNewPlayer(victimProfile): boolean
	if (victimProfile.playSeconds or 0) < Heist.NewPlayerProtectionSeconds then
		return true
	end
	local tutorial = victimProfile.tutorial
	if Heist.NewPlayerRequiresTutorial and not (tutorial.done or tutorial.everDone) then
		return true
	end
	return false
end

-- ctx = {
--   now, attackerId, victimId,
--   attackerCooldownUntil, pairCooldownUntil, shieldUntil, -- runtime state from services
-- }
function HeistLogic.canTarget(attackerProfile, victimProfile, creatureId: string, ctx): (boolean, string?)
	local now = ctx.now
	if ctx.attackerId == ctx.victimId then
		return false, "That's your own creature!"
	end
	local creature = victimProfile.creatures[creatureId]
	if not creature or not creature.slot then
		return false, "That creature isn't on display"
	end
	if creature.starter then
		return false, "Starter creatures are protected"
	end
	if not Rules.isStealableSpecies(creature.species) then
		local species = Creatures.Species[creature.species]
		return false, (species and species.rarity or "This") .. " creatures can't be stolen"
	end
	if creature.protectedUntil > now then
		return false, "Recently acquired: protected for " .. math.ceil(creature.protectedUntil - now) .. "s"
	end
	if (ctx.shieldUntil or 0) > now then
		return false, "This island's shield is up"
	end
	if (victimProfile.heist.protectedUntil or 0) > now then
		return false, "This island was raided recently and is protected"
	end
	if HeistLogic.isNewPlayer(victimProfile) then
		return false, "New players are protected while they learn"
	end
	if Inventory.count(victimProfile) <= Heist.MinCreaturesKept then
		return false, "This player has too few creatures to raid"
	end
	local attackerLevel = Rules.levelFromXP(attackerProfile.xp)
	local victimLevel = Rules.levelFromXP(victimProfile.xp)
	if attackerLevel - victimLevel > Heist.MaxLevelGap then
		return false, "Pick on someone your own size!"
	end
	if (ctx.attackerCooldownUntil or 0) > now then
		return false, "Lay low for " .. math.ceil(ctx.attackerCooldownUntil - now) .. "s before your next heist"
	end
	if (ctx.pairCooldownUntil or 0) > now then
		return false, "You raided this island recently"
	end
	if not Inventory.hasSpace(attackerProfile) then
		return false, "Your creature storage is full"
	end
	if not Locks.isFree(victimProfile, creatureId) then
		return false, "Someone else is already after that creature"
	end
	return true
end

-- Resolves a finished heist. `roll` is a server random number in [0, 1).
-- Returns "success" + creature, "fail" + fine, or "invalid" + reason. Transfers at most once.
function HeistLogic.resolve(attackerProfile, victimProfile, creatureId: string, roll: number, now: number)
	local creature = victimProfile.creatures[creatureId]
	if not creature or not creature.slot then
		return "invalid", "The creature is gone"
	end
	local lock = Locks.get(creatureId)
	if not lock or lock.kind ~= "heist" then
		return "invalid", "The heist was interrupted"
	end
	local chance = HeistLogic.successChance(victimProfile.upgrades.security)
	if roll < chance then
		if not Inventory.hasSpace(attackerProfile) then
			return "invalid", "Your creature storage is full"
		end
		local moved = Inventory.remove(victimProfile, creatureId)
		moved.acquiredAt = now
		moved.protectedUntil = now + Heist.NewCreatureProtection
		moved.source = "stolen"
		Inventory.add(attackerProfile, moved, { ignoreCapacity = true })
		attackerProfile.stats.steals += 1
		victimProfile.stats.stolenFrom += 1
		victimProfile.heist.protectedUntil = now + Heist.VictimProtectionAfterTheft
		EconomyLogic.addXP(attackerProfile, Economy.XP.heistSuccess)
		return "success", moved
	end
	return "fail", HeistLogic.applyFailure(attackerProfile, victimProfile)
end

-- Failed or trapped attempt: attacker pays a capped fine (destroyed, not given to anyone,
-- so alt accounts can't farm it) and the defender gets credit.
function HeistLogic.applyFailure(attackerProfile, victimProfile): number
	local fine = math.min(Heist.FailFineMax, math.floor(Wallet.get(attackerProfile, "coins") * Heist.FailFinePercent))
	if fine > 0 then
		Wallet.spend(attackerProfile, { coins = fine })
	end
	attackerProfile.stats.failedHeists += 1
	victimProfile.stats.defended += 1
	EconomyLogic.addXP(victimProfile, Economy.XP.defend)
	return fine
end

return HeistLogic
