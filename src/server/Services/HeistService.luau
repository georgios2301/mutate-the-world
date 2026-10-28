-- Interactive creature theft. Flow:
--   1. Attacker triggers a creature's Steal prompt (server-side Triggered event).
--   2. Server validates (HeistLogic.canTarget + distance) and locks the creature.
--   3. A channel timer runs; the defender is alerted and can shield, zap or come home.
--   4. Moving away, dying, leaving, the shield or the trap cancels it.
--   5. On completion the server rolls success and transfers ownership exactly once.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Creatures = require(Shared.Config.Creatures)
local Mutations = require(Shared.Config.Mutations)
local Heist = require(Shared.Config.Heist)
local Format = require(Shared.Util.Format)

local Core = script.Parent.Parent.Core
local HeistLogic = require(Core.HeistLogic)
local Locks = require(Core.Locks)

local IslandBuilder = require(script.Parent.Parent.World.IslandBuilder)

local HeistService = {}
local S

local rng = Random.new()
local active = {} -- [attackerUserId] = heist
local byVictim = {} -- [victimUserId] = heist
local attackerCooldown = {} -- [userId] = time
local pairCooldown = {} -- ["attacker:victim"] = time

local function now(): number
	return workspace:GetServerTimeNow()
end

-- The thief must be inside the victim's vault (prompts reach through the glass walls,
-- so distance alone would let them skip breaching the door).
local function insideVault(victim: Player, position: Vector3): boolean
	local island = S.Island.get(victim)
	return island ~= nil and IslandBuilder.isInVault(island, position)
end

local function pairKey(attacker: Player, victim: Player): string
	return attacker.UserId .. ":" .. victim.UserId
end

local function creatureLabel(creature): string
	local species = Creatures.Species[creature.species]
	return Mutations.displayName(species.name, creature.mutation)
end

local function heistEvent(player: Player, kind: string, data)
	if player.Parent then
		S.Net.event("HeistEvent"):FireClient(player, kind, data)
	end
end

local function cleanup(heist)
	heist.done = true
	Locks.release(heist.creatureId, "heist", heist.attacker.UserId)
	if active[heist.attacker.UserId] == heist then
		active[heist.attacker.UserId] = nil
	end
	if byVictim[heist.victim.UserId] == heist then
		byVictim[heist.victim.UserId] = nil
	end
	if heist.highlight then
		heist.highlight:Destroy()
	end
	heistEvent(heist.attacker, "ended", {})
	heistEvent(heist.victim, "ended", {})
	if heist.victim.Parent then
		S.State.push(heist.victim)
	end
	if heist.attacker.Parent then
		S.State.push(heist.attacker)
	end
end

function HeistService.isIslandProtected(owner: Player, profile): boolean
	return HeistLogic.isNewPlayer(profile) or (profile.heist.protectedUntil or 0) > now() or S.Defense.isShielded(owner)
end

function HeistService.getAttackerOnVictim(victim: Player): Player?
	local heist = byVictim[victim.UserId]
	return heist and heist.attacker
end

function HeistService.cancel(heist, reason: string)
	if heist.done then
		return
	end
	cleanup(heist)
	attackerCooldown[heist.attacker.UserId] = math.max(attackerCooldown[heist.attacker.UserId] or 0, now() + 15)
	if heist.attacker.Parent then
		S.Net.notify(heist.attacker, "Heist cancelled: " .. reason, "warn")
	end
	if heist.victim.Parent then
		S.Net.notify(heist.victim, "The thief gave up! (" .. reason .. ")", "success")
	end
end

local function resolve(heist)
	if heist.done then
		return
	end
	local attacker, victim = heist.attacker, heist.victim
	local aProfile, vProfile = S.Data.get(attacker), S.Data.get(victim)
	if not aProfile or not vProfile then
		HeistService.cancel(heist, "player left")
		return
	end
	local t = now()
	local outcome, result = HeistLogic.resolve(aProfile, vProfile, heist.creatureId, rng:NextNumber(), t)
	cleanup(heist)
	if outcome == "success" then
		attackerCooldown[attacker.UserId] = t + Heist.AttackerCooldownSuccess
		pairCooldown[pairKey(attacker, victim)] = t + Heist.SameVictimCooldown
		local name = creatureLabel(result)
		S.Creature.refreshIsland(victim)
		S.Creature.refreshIsland(attacker)
		S.Net.notify(attacker, "Heist successful! You stole " .. name .. ".", "success")
		S.Net.notify(victim, attacker.DisplayName .. " stole your " .. name .. "! Your island is protected for 10 minutes.", "error")
		heistEvent(attacker, "result", { outcome = "success", creature = name })
		heistEvent(victim, "result", { outcome = "stolen", creature = name, attacker = attacker.DisplayName })
		S.Net.notifyAll(attacker.DisplayName .. " pulled off a heist on " .. victim.DisplayName .. "'s island!", "info")
		S.Data.markDirty(attacker)
		S.Data.markDirty(victim)
		-- Victim first: a crash between the two saves can never duplicate the creature.
		S.Data.saveInOrder({ victim, attacker })
	elseif outcome == "fail" then
		attackerCooldown[attacker.UserId] = t + Heist.AttackerCooldownFail
		pairCooldown[pairKey(attacker, victim)] = t + Heist.SameVictimCooldown / 3
		S.Defense.stun(attacker, Heist.StunTime)
		S.Net.notify(attacker, "The creature slipped away! You were caught" .. (if result > 0 then " and fined " .. Format.number(result) .. " coins." else "."), "error")
		S.Net.notify(victim, "Your security stopped " .. attacker.DisplayName .. "'s heist!", "success")
		heistEvent(attacker, "result", { outcome = "fail" })
		heistEvent(victim, "result", { outcome = "defended", attacker = attacker.DisplayName })
		S.Data.markDirty(attacker)
		S.Data.markDirty(victim)
	else
		S.Net.notify(attacker, "Heist failed: " .. tostring(result), "warn")
	end
end

local function monitor(heist)
	while not heist.done do
		task.wait(0.25)
		if heist.done then
			return
		end
		local attacker, victim = heist.attacker, heist.victim
		if not attacker.Parent or not victim.Parent then
			HeistService.cancel(heist, "player left")
			return
		end
		local root = S.Travel.getRoot(attacker)
		if not root then
			HeistService.cancel(heist, "you were knocked out")
			return
		end
		local model = S.Creature.getModel(victim.UserId, heist.creatureId)
		if not model or not model.PrimaryPart then
			HeistService.cancel(heist, "the creature is gone")
			return
		end
		if (root.Position - model.PrimaryPart.Position).Magnitude > Heist.MaxDistance or not insideVault(victim, root.Position) then
			HeistService.cancel(heist, "you moved too far away")
			return
		end
		if S.Defense.isShielded(victim) then
			HeistService.cancel(heist, "the island shield went up")
			return
		end
		if now() >= heist.endsAt then
			resolve(heist)
			return
		end
	end
end

function HeistService.tryStart(attacker: Player, victim: Player, creatureId: string)
	if attacker == victim or not victim.Parent then
		return
	end
	local aProfile, vProfile = S.Data.get(attacker), S.Data.get(victim)
	if not aProfile or not vProfile then
		return
	end
	if active[attacker.UserId] then
		S.Net.notify(attacker, "You're already in the middle of a heist", "warn")
		return
	end
	if byVictim[victim.UserId] then
		S.Net.notify(attacker, "Someone else is already raiding this island", "warn")
		return
	end
	local model = S.Creature.getModel(victim.UserId, creatureId)
	local root = S.Travel.getRoot(attacker)
	if not model or not model.PrimaryPart or not root then
		return
	end
	if not insideVault(victim, root.Position) then
		S.Net.notify(attacker, "Get inside the vault first (breach the door)", "warn")
		return
	end
	if (root.Position - model.PrimaryPart.Position).Magnitude > Heist.StartDistance then
		S.Net.notify(attacker, "Get closer to the creature", "warn")
		return
	end
	local t = now()
	local ok, reason = HeistLogic.canTarget(aProfile, vProfile, creatureId, {
		now = t,
		attackerId = attacker.UserId,
		victimId = victim.UserId,
		attackerCooldownUntil = attackerCooldown[attacker.UserId],
		pairCooldownUntil = pairCooldown[pairKey(attacker, victim)],
		shieldUntil = S.Defense.shieldUntil(victim),
	})
	if not ok then
		S.Net.notify(attacker, reason or "You can't steal that", "warn")
		return
	end
	if not Locks.acquire(creatureId, "heist", attacker.UserId) then
		S.Net.notify(attacker, "Someone else is already after that creature", "warn")
		return
	end

	local duration = HeistLogic.channelTime(vProfile.upgrades.security)
	local creature = vProfile.creatures[creatureId]
	local heist = {
		attacker = attacker,
		victim = victim,
		creatureId = creatureId,
		startedAt = t,
		endsAt = t + duration,
		done = false,
	}
	active[attacker.UserId] = heist
	byVictim[victim.UserId] = heist

	if attacker.Character then
		local highlight = Instance.new("Highlight")
		highlight.FillColor = Color3.fromRGB(255, 60, 80)
		highlight.OutlineColor = Color3.fromRGB(255, 220, 220)
		highlight.FillTransparency = 0.6
		highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		highlight.Parent = attacker.Character
		heist.highlight = highlight
	end

	local name = creatureLabel(creature)
	heistEvent(attacker, "start", { endsAt = heist.endsAt, duration = duration, creature = name, victim = victim.DisplayName })
	heistEvent(victim, "alert", { endsAt = heist.endsAt, duration = duration, creature = name, attacker = attacker.DisplayName })
	S.Net.notify(victim, "THIEF! " .. attacker.DisplayName .. " is stealing your " .. name .. "!", "error")
	S.Defense.raiseAlarm(victim, duration + 2)
	S.State.push(victim)
	task.spawn(monitor, heist)
end

-- Trap hit: counts as a failed attempt (fine + cooldown).
function HeistService.failByTrap(attacker: Player)
	local heist = active[attacker.UserId]
	if not heist or heist.done then
		return
	end
	local aProfile, vProfile = S.Data.get(attacker), S.Data.get(heist.victim)
	cleanup(heist)
	local fine = 0
	if aProfile and vProfile then
		fine = HeistLogic.applyFailure(aProfile, vProfile)
		S.Data.markDirty(attacker)
		S.Data.markDirty(heist.victim)
	end
	local t = now()
	attackerCooldown[attacker.UserId] = t + Heist.AttackerCooldownFail
	pairCooldown[pairKey(attacker, heist.victim)] = t + Heist.SameVictimCooldown / 3
	S.Net.notify(attacker, "ZAPPED by a security trap!" .. (if fine > 0 then " Fined " .. fine .. " coins." else ""), "error")
	heistEvent(attacker, "result", { outcome = "fail" })
	heistEvent(heist.victim, "result", { outcome = "defended", attacker = attacker.DisplayName })
end

function HeistService.cancelForVictim(victim: Player, reason: string)
	local heist = byVictim[victim.UserId]
	if heist then
		HeistService.cancel(heist, reason)
	end
end

function HeistService.onTravel(player: Player)
	local heist = active[player.UserId]
	if heist then
		HeistService.cancel(heist, "you left the island")
	end
end

function HeistService.onLeave(player: Player)
	local heist = active[player.UserId]
	if heist then
		HeistService.cancel(heist, "player left")
	end
	heist = byVictim[player.UserId]
	if heist then
		HeistService.cancel(heist, "the owner left")
	end
	-- attackerCooldown is kept on purpose: rejoining must not reset it.
end

function HeistService.init(services)
	S = services
end

function HeistService.start()
	S.Net.on("CancelHeist", { rate = { 3, 1 }, push = false }, function(player)
		local heist = active[player.UserId]
		if not heist then
			return false, "No heist in progress"
		end
		HeistService.cancel(heist, "you backed off")
		return true
	end)

	Players.PlayerAdded:Connect(function(player)
		player.CharacterRemoving:Connect(function()
			local heist = active[player.UserId]
			if heist then
				HeistService.cancel(heist, "you were knocked out")
			end
		end)
	end)
end

return HeistService
