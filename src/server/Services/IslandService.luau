-- Island ownership: one island per player (max 8). Islands are prebuilt and claimed on join,
-- released (and visually reset) on leave so the next player gets a clean island.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local World = require(Shared.Config.World)
local Rules = require(Shared.Rules)

local IslandBuilder = require(script.Parent.Parent.World.IslandBuilder)

local IslandService = {}
local S

local islands = {} -- [index] = island
local byUser = {} -- [userId] = island

function IslandService.init(services)
	S = services
	local folder = Instance.new("Folder")
	folder.Name = "Islands"
	folder.Parent = workspace
	for index = 1, World.MaxIslands do
		islands[index] = IslandBuilder.build(index, folder)
	end
end

function IslandService.assign(player: Player)
	if byUser[player.UserId] then
		return byUser[player.UserId]
	end
	for index = 1, World.MaxIslands do
		local island = islands[index]
		if island.owner == nil then
			IslandBuilder.setOwner(island, player)
			byUser[player.UserId] = island
			IslandService.refresh(player)
			return island
		end
	end
	return nil
end

function IslandService.release(player: Player)
	local island = byUser[player.UserId]
	if not island then
		return
	end
	byUser[player.UserId] = nil
	island.creatureFolder:ClearAllChildren()
	IslandBuilder.setOwner(island, nil)
	IslandBuilder.applyTheme(island, "default")
	IslandBuilder.applyLevel(island, 1, 0, 0)
	IslandBuilder.setAlarm(island, false)
end

-- Re-applies pads/expansions/theme after upgrades or purchases.
function IslandService.refresh(player: Player)
	local island = byUser[player.UserId]
	local profile = S.Data.get(player)
	if not island or not profile then
		return
	end
	local padCount = Rules.padCount(profile.upgrades, profile.passBonuses)
	local maxPads = Rules.upgradeValue(profile.upgrades, "island") + (profile.passBonuses.pads or 0)
	IslandBuilder.applyLevel(island, profile.upgrades.island, padCount, math.min(maxPads, World.MaxPadPositions))
	IslandBuilder.applyTheme(island, profile.cosmetics.theme)
end

function IslandService.setChamberVisual(player: Player, active: boolean, color: Color3?)
	local island = byUser[player.UserId]
	if island then
		IslandBuilder.setChamberActive(island, active, color)
	end
end

function IslandService.get(player: Player)
	return byUser[player.UserId]
end

function IslandService.getIndex(player: Player): number
	local island = byUser[player.UserId]
	return island and island.index or 0
end

function IslandService.getByIndex(index: number)
	return islands[index]
end

function IslandService.all()
	return islands
end

-- The island whose model contains `instance`, if any.
function IslandService.fromInstance(instance: Instance)
	local current: Instance? = instance
	while current and current ~= workspace do
		local index = current:GetAttribute("IslandIndex")
		if index then
			return islands[index]
		end
		current = current.Parent
	end
	return nil
end

-- Is the player's character standing on (or near) a given island?
function IslandService.isNear(player: Player, island): boolean
	local root = S.Travel.getRoot(player)
	return root ~= nil and IslandBuilder.isOnIsland(island, root.Position)
end

function IslandService.start()
	S.Net.on("ListIslands", { rate = { 4, 1 }, push = false }, function(player)
		local list = {}
		for index, island in ipairs(islands) do
			if island.owner and island.owner ~= player then
				local profile = S.Data.get(island.owner)
				table.insert(list, {
					index = index,
					name = island.owner.DisplayName,
					userId = island.owner.UserId,
					level = profile and Rules.levelFromXP(profile.xp) or 1,
					shielded = S.Defense.isShielded(island.owner),
					protected = profile ~= nil and S.Heist.isIslandProtected(island.owner, profile),
				})
			end
		end
		return true, nil, list
	end)

	Players.PlayerRemoving:Connect(function(player)
		-- Final cleanup happens in Main (after heists/trades are cancelled); this is a safety net.
		task.defer(function()
			if byUser[player.UserId] and not player.Parent then
				IslandService.release(player)
			end
		end)
	end)
end

return IslandService
