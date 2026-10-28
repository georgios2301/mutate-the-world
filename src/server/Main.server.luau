-- MUTATE THE WORLD - server entry point.
-- Builds the world, initializes every service, then handles player join/leave in a fixed order.
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local Core = script.Parent.Core
local DataSchema = require(Core.DataSchema)
local Inventory = require(Core.Inventory)
local WorldBuilder = require(script.Parent.World.WorldBuilder)

local ServicesFolder = script.Parent.Services

-- Init/start order matters: later services may use earlier ones during start().
local ORDER = {
	{ "Net", "Net" },
	{ "Data", "DataService" },
	{ "State", "StateService" },
	{ "Island", "IslandService" },
	{ "Travel", "TravelService" },
	{ "Movement", "MovementGuard" },
	{ "Creature", "CreatureService" },
	{ "Economy", "EconomyService" },
	{ "Discovery", "DiscoveryService" },
	{ "Mutation", "MutationService" },
	{ "Resource", "ResourceService" },
	{ "Defense", "DefenseService" },
	{ "Heist", "HeistService" },
	{ "Trade", "TradeService" },
	{ "Monetization", "MonetizationService" },
	{ "Leaderboard", "LeaderboardService" },
	{ "Tutorial", "TutorialService" },
}

Inventory.setIdGenerator(function()
	return HttpService:GenerateGUID(false)
end)

local S: any = {}
S.World = WorldBuilder.build()

for _, entry in ipairs(ORDER) do
	S[entry[1]] = require(ServicesFolder[entry[2]])
end
for _, entry in ipairs(ORDER) do
	local service = S[entry[1]]
	if service.init then
		service.init(S)
	end
end
for _, entry in ipairs(ORDER) do
	local service = S[entry[1]]
	if service.start then
		service.start()
	end
end

local rng = Random.new()

local function onPlayerAdded(player: Player)
	local profile = S.Data.load(player)
	if not profile or not player.Parent then
		return
	end
	local now = workspace:GetServerTimeNow()
	DataSchema.ensureStarter(profile, now, rng:NextInteger(1, 2 ^ 30))

	local island = S.Island.assign(player)
	if not island then
		S.Data.release(player)
		player:Kick("Every island on this server is taken. Please join another server.")
		return
	end

	S.Defense.setupPlayer(player)
	S.Monetization.onPlayerReady(player, profile)
	S.Economy.onPlayerReady(player, profile)
	S.Creature.refreshIsland(player)
	S.Mutation.onPlayerReady(player, profile)
	S.Leaderboard.onPlayerReady(player, profile)
	S.Tutorial.onPlayerReady(player, profile)
	S.Travel.setupPlayer(player)
	S.State.setReady(player)

	if not S.Data.isPersistent() then
		S.Net.notify(player, "Saving is unavailable on this server (DataStores off). Progress is session-only.", "warn")
	elseif not S.Data.isNewPlayer(player) then
		S.Net.notify(player, "Welcome back, " .. player.DisplayName .. "!", "info")
	end
end

local function onPlayerRemoving(player: Player)
	-- Cancel anything that touches other players before the final save.
	S.Heist.onLeave(player)
	S.Trade.onLeave(player)
	S.Defense.cleanup(player)
	S.Creature.clear(player)
	S.Island.release(player)
	S.Data.release(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

print("[MutateTheWorld] Server ready. Persistent data:", S.Data.isPersistent())
