-- Server-side teleports between the hub, islands and biomes (portals, HUD buttons, respawns).
-- Biome access is checked here; locked biomes cannot be entered.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Biomes = require(Shared.Config.Biomes)
local World = require(Shared.Config.World)

local Core = script.Parent.Parent.Core
local EconomyLogic = require(Core.EconomyLogic)
local Validate = require(Core.Validate)

local TravelService = {}
local S

local COOLDOWN = 2
local lastTravel = {} -- [userId] = time

local function now(): number
	return workspace:GetServerTimeNow()
end

function TravelService.getRoot(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

function TravelService.teleport(player: Player, cf: CFrame)
	local character = player.Character
	if not character then
		return false
	end
	S.Movement.grace(player, 3)
	character:PivotTo(cf + Vector3.new(0, 3, 0))
	return true
end

-- destination: "hub" | "island" | "visit:<index>" | "biome:<id>"
function TravelService.travel(player: Player, destination: string)
	local profile = S.Data.get(player)
	if not profile then
		return false, "Still loading"
	end
	local t = now()
	if (lastTravel[player.UserId] or 0) + COOLDOWN > t then
		return false, "Portal recharging..."
	end
	if not TravelService.getRoot(player) then
		return false, "You can't travel right now"
	end

	local target: CFrame? = nil
	local label = ""
	if destination == "hub" then
		target = S.World.hubSpawn
		label = "the Hub"
	elseif destination == "island" then
		local island = S.Island.get(player)
		if not island then
			return false, "You don't have an island"
		end
		target = island.ownerSpawn
		label = "your island"
	elseif string.sub(destination, 1, 6) == "visit:" then
		local index = tonumber(string.sub(destination, 7))
		if not Validate.int(index, 1, World.MaxIslands) then
			return false, "Unknown island"
		end
		local island = S.Island.getByIndex(index :: number)
		if not island or not island.owner then
			return false, "Nobody lives there right now"
		end
		if island.owner == player then
			target = island.ownerSpawn
		else
			target = island.dock
		end
		label = if island.owner == player then "your island" else island.owner.DisplayName .. "'s island"
	elseif string.sub(destination, 1, 6) == "biome:" then
		local biomeId = string.sub(destination, 7)
		local def = Biomes.Defs[biomeId]
		if not def then
			return false, "Unknown biome"
		end
		if not EconomyLogic.isBiomeUnlocked(profile, biomeId) then
			return false, def.name .. " is locked. Unlock it in the Travel menu"
		end
		target = S.World.biomes[biomeId].spawn
		label = def.name
	else
		return false, "Unknown destination"
	end

	lastTravel[player.UserId] = t
	TravelService.teleport(player, target :: CFrame)
	S.Heist.onTravel(player)
	return true, "Travelled to " .. label
end

local function onCharacterAdded(player: Player, character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not root or not player.Parent then
		return
	end
	task.wait(0.1)
	local island = S.Island.get(player)
	if island then
		TravelService.teleport(player, island.ownerSpawn)
	end
end

function TravelService.setupPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end
end

function TravelService.init(services)
	S = services
end

function TravelService.start()
	S.Net.on("Travel", { rate = { 3, 1 }, push = false }, function(player, _profile, destination)
		if not Validate.str(destination, 40) then
			return false, "Bad destination"
		end
		return TravelService.travel(player, destination)
	end)

	for _, prompt in ipairs(S.World.portals) do
		prompt.Triggered:Connect(function(player)
			local destination = prompt:GetAttribute("Destination")
			if type(destination) == "string" then
				local ok, msg = TravelService.travel(player, destination)
				if msg then
					S.Net.notify(player, msg, if ok then "info" else "warn")
				end
			end
		end)
	end
	for _, island in pairs(S.Island.all()) do
		island.hubPrompt.Triggered:Connect(function(player)
			local ok, msg = TravelService.travel(player, "hub")
			if not ok and msg then
				S.Net.notify(player, msg, "warn")
			end
		end)
	end

	Players.PlayerRemoving:Connect(function(player)
		lastTravel[player.UserId] = nil
	end)
end

return TravelService
