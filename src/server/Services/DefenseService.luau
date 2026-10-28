-- Island defenses: temporary shield, lockable vault door (breachable by visitors), intruder
-- alarm, slime floor and the zap trap. Also owns WalkSpeed effects (stuns / slows) so they
-- never fight each other.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Heist = require(Shared.Config.Heist)

local Core = script.Parent.Parent.Core
local HeistLogic = require(Core.HeistLogic)

local IslandBuilder = require(script.Parent.Parent.World.IslandBuilder)

local DefenseService = {}
local S

local DEFAULT_SPEED = 16

local state = {} -- [userId] = island defense state
local speedState = {} -- [Player] = { stunnedUntil, slowedBy = {[islandOwnerId]=true} }
local alarmUntil = {} -- [userId] = time

local function now(): number
	return workspace:GetServerTimeNow()
end

local function getState(player: Player)
	local s = state[player.UserId]
	if not s then
		s = {
			shieldUntil = 0,
			trapCooldownUntil = 0,
			doorLocked = true,
			doorOpenUntil = 0,
			breachStarts = {},
			intruderNotified = {},
		}
		state[player.UserId] = s
	end
	return s
end

local function securityLevel(player: Player): number
	local profile = S.Data.get(player)
	return profile and profile.upgrades.security or 1
end

-- WalkSpeed effects -------------------------------------------------------------

local function applySpeed(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local st = speedState[player]
	local speed = DEFAULT_SPEED
	if st then
		if st.stunnedUntil > now() then
			speed = 0
		elseif next(st.slowedBy) ~= nil then
			speed = Heist.SlimeFloorWalkSpeed
		end
	end
	humanoid.WalkSpeed = speed
end

local function speedEntry(player: Player)
	local st = speedState[player]
	if not st then
		st = { stunnedUntil = 0, slowedBy = {} }
		speedState[player] = st
	end
	return st
end

function DefenseService.stun(player: Player, seconds: number)
	local st = speedEntry(player)
	st.stunnedUntil = math.max(st.stunnedUntil, now() + seconds)
	applySpeed(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root then
		local sparks = Instance.new("ParticleEmitter")
		sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sparks.Color = ColorSequence.new(Color3.fromRGB(120, 230, 255))
		sparks.Rate = 40
		sparks.Lifetime = NumberRange.new(0.3, 0.6)
		sparks.Speed = NumberRange.new(4, 8)
		sparks.SpreadAngle = Vector2.new(180, 180)
		sparks.Parent = root
		task.delay(seconds, function()
			sparks:Destroy()
		end)
	end
	task.delay(seconds + 0.05, function()
		if player.Parent then
			applySpeed(player)
		end
	end)
end

-- Alarm -------------------------------------------------------------------------

function DefenseService.raiseAlarm(owner: Player, seconds: number)
	local island = S.Island.get(owner)
	if not island then
		return
	end
	alarmUntil[owner.UserId] = math.max(alarmUntil[owner.UserId] or 0, now() + seconds)
	IslandBuilder.setAlarm(island, true)
end

-- Status ------------------------------------------------------------------------

function DefenseService.isShielded(player: Player): boolean
	local s = state[player.UserId]
	return s ~= nil and s.shieldUntil > now()
end

function DefenseService.shieldUntil(player: Player): number
	local s = state[player.UserId]
	return s and s.shieldUntil or 0
end

function DefenseService.status(player: Player)
	local s = getState(player)
	local level = securityLevel(player)
	local profile = S.Data.get(player)
	return {
		securityLevel = level,
		shieldUntil = s.shieldUntil,
		shieldCooldownUntil = profile and profile.heist.shieldCooldownUntil or 0,
		shieldDuration = Heist.Shield.duration[level],
		shieldCooldown = Heist.Shield.cooldown[level],
		trapCooldownUntil = s.trapCooldownUntil,
		doorLocked = s.doorLocked,
		doorOpenUntil = s.doorOpenUntil,
		breachTime = Heist.DoorBreachTime[level],
		alarm = level >= Heist.AlarmMinSecurity,
		slimeFloor = level >= Heist.SlimeFloorMinSecurity,
	}
end

-- Actions -----------------------------------------------------------------------

function DefenseService.activateShield(player: Player)
	local profile = S.Data.get(player)
	local island = S.Island.get(player)
	if not profile or not island then
		return false, "Still loading"
	end
	local s = getState(player)
	local t = now()
	if s.shieldUntil > t then
		return false, "Shield is already up"
	end
	if profile.heist.shieldCooldownUntil > t then
		return false, "Shield recharging: " .. math.ceil(profile.heist.shieldCooldownUntil - t) .. "s"
	end
	local level = securityLevel(player)
	local duration = Heist.Shield.duration[level]
	s.shieldUntil = t + duration
	profile.heist.shieldCooldownUntil = t + Heist.Shield.cooldown[level]
	IslandBuilder.setShield(island, true)
	S.Heist.cancelForVictim(player, "The island shield slammed shut!")
	S.Tutorial.event(player, "defense")
	task.delay(duration, function()
		if state[player.UserId] == s and s.shieldUntil <= now() + 0.05 then
			local current = S.Island.get(player)
			if current then
				IslandBuilder.setShield(current, false)
			end
			if player.Parent then
				S.Net.notify(player, "Your shield is down.", "warn")
				S.State.push(player)
			end
		end
	end)
	return true, "Shield up for " .. duration .. "s!"
end

function DefenseService.setDoor(player: Player, locked: boolean)
	local island = S.Island.get(player)
	if not island then
		return
	end
	local s = getState(player)
	s.doorLocked = locked
	s.doorOpenUntil = 0
	IslandBuilder.setDoor(island, locked)
end

function DefenseService.toggleDoor(player: Player)
	local s = getState(player)
	DefenseService.setDoor(player, not s.doorLocked or s.doorOpenUntil > now())
	S.Tutorial.event(player, "defense")
	return true, if s.doorLocked then "Vault door locked" else "Vault door opened"
end

function DefenseService.triggerTrap(player: Player)
	local s = getState(player)
	local t = now()
	if securityLevel(player) < Heist.Trap.minSecurity then
		return false, "Upgrade Security to unlock the trap"
	end
	if s.trapCooldownUntil > t then
		return false, "Trap recharging: " .. math.ceil(s.trapCooldownUntil - t) .. "s"
	end
	local attacker = S.Heist.getAttackerOnVictim(player)
	if not attacker then
		return false, "No thief to zap right now"
	end
	s.trapCooldownUntil = t + Heist.Trap.cooldown
	DefenseService.stun(attacker, Heist.Trap.stun)
	S.Heist.failByTrap(attacker)
	return true, "ZAP! The thief is stunned."
end

-- Door breach (visitors) ---------------------------------------------------------

local function islandBlocked(owner: Player): string?
	local profile = S.Data.get(owner)
	if not profile then
		return "Not available"
	end
	if DefenseService.isShielded(owner) then
		return "The island shield is up"
	end
	if HeistLogic.isNewPlayer(profile) then
		return "New players are protected while they learn"
	end
	if (profile.heist.protectedUntil or 0) > now() then
		return "This island was raided recently and is protected"
	end
	return nil
end

local function setupDoorPrompts(island)
	island.doorPrompt.Triggered:Connect(function(player)
		if island.owner == player then
			local _, msg = DefenseService.toggleDoor(player)
			S.Net.notify(player, msg, "info")
			S.State.push(player)
		end
	end)
	island.breachPrompt.PromptButtonHoldBegan:Connect(function(player)
		local owner = island.owner
		if not owner or owner == player then
			return
		end
		local blocked = islandBlocked(owner)
		if blocked then
			S.Net.notify(player, blocked, "warn")
			return
		end
		local s = getState(owner)
		s.breachStarts[player.UserId] = now()
		S.Net.notify(owner, player.DisplayName .. " is breaching your vault door!", "error")
		S.Net.event("HeistEvent"):FireClient(owner, "breach", { attacker = player.DisplayName })
		DefenseService.raiseAlarm(owner, 8)
	end)
	island.breachPrompt.Triggered:Connect(function(player)
		local owner = island.owner
		if not owner or owner == player then
			return
		end
		local s = getState(owner)
		local started = s.breachStarts[player.UserId]
		s.breachStarts[player.UserId] = nil
		local required = Heist.DoorBreachTime[securityLevel(owner)]
		if not started or now() - started < required * 0.9 then
			return -- hold time not genuinely completed
		end
		if islandBlocked(owner) or not s.doorLocked then
			return
		end
		local root = S.Travel.getRoot(player)
		if not root or (root.Position - island.door.Position).Magnitude > 14 then
			return
		end
		s.doorOpenUntil = now() + Heist.DoorOpenAfterBreach
		IslandBuilder.setDoor(island, false)
		S.Net.notify(owner, player.DisplayName .. " broke through your vault door!", "error")
		S.Net.notify(player, "Door breached! It relocks in " .. Heist.DoorOpenAfterBreach .. "s", "success")
		S.State.push(owner)
		local openUntil = s.doorOpenUntil
		task.delay(Heist.DoorOpenAfterBreach, function()
			if state[owner.UserId] == s and s.doorOpenUntil == openUntil and s.doorLocked then
				s.doorOpenUntil = 0
				if island.owner == owner then
					IslandBuilder.setDoor(island, true)
					S.State.push(owner)
				end
			end
		end)
	end)
end

function DefenseService.onUpgrade(player: Player)
	local island = S.Island.get(player)
	if island then
		island.breachPrompt.HoldDuration = Heist.DoorBreachTime[securityLevel(player)]
	end
end

function DefenseService.setupPlayer(player: Player)
	getState(player)
	DefenseService.setDoor(player, true)
	DefenseService.onUpgrade(player)
end

function DefenseService.cleanup(player: Player)
	state[player.UserId] = nil
	alarmUntil[player.UserId] = nil
	for other, st in pairs(speedState) do
		if st.slowedBy[player.UserId] then
			st.slowedBy[player.UserId] = nil
			applySpeed(other)
		end
	end
	speedState[player] = nil
end

-- Intruder detection loop -------------------------------------------------------

local function scan()
	local t = now()
	local roots = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local root = S.Travel.getRoot(player)
		if root then
			roots[player] = root.Position
		end
	end
	for _, owner in ipairs(Players:GetPlayers()) do
		local island = S.Island.get(owner)
		local s = state[owner.UserId]
		if island and s then
			local level = securityLevel(owner)
			for player, pos in pairs(roots) do
				if player ~= owner then
					local inside = IslandBuilder.isInVault(island, pos)
					local st = speedState[player]
					if inside and level >= Heist.SlimeFloorMinSecurity then
						st = speedEntry(player)
						if not st.slowedBy[owner.UserId] then
							st.slowedBy[owner.UserId] = true
							applySpeed(player)
						end
					elseif st and st.slowedBy[owner.UserId] then
						st.slowedBy[owner.UserId] = nil
						applySpeed(player)
					end
					if inside and level >= Heist.AlarmMinSecurity then
						local last = s.intruderNotified[player.UserId] or 0
						if t - last > Heist.AlarmThrottle then
							s.intruderNotified[player.UserId] = t
							S.Net.notify(owner, "Intruder alert: " .. player.DisplayName .. " is inside your vault!", "error")
							DefenseService.raiseAlarm(owner, 6)
						end
					end
				end
			end
			if (alarmUntil[owner.UserId] or 0) > 0 and alarmUntil[owner.UserId] <= t then
				alarmUntil[owner.UserId] = 0
				IslandBuilder.setAlarm(island, false)
			end
		end
	end
end

function DefenseService.init(services)
	S = services
end

function DefenseService.start()
	for _, island in pairs(S.Island.all()) do
		setupDoorPrompts(island)
	end

	S.Net.on("ActivateShield", { rate = { 3, 1 } }, function(player)
		return DefenseService.activateShield(player)
	end)
	S.Net.on("ToggleDoor", { rate = { 4, 2 } }, function(player)
		return DefenseService.toggleDoor(player)
	end)
	S.Net.on("TriggerTrap", { rate = { 3, 1 } }, function(player)
		return DefenseService.triggerTrap(player)
	end)

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			speedState[player] = nil
		end)
	end)

	task.spawn(function()
		while true do
			task.wait(0.5)
			scan()
		end
	end)
end

return DefenseService
