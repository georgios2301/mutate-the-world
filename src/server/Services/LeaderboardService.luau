-- leaderstats (player list) + hub leaderboards. Values come only from server-side profiles.
-- Global boards use OrderedDataStores when available and fall back to this server's players.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Rules = require(Shared.Rules)
local Format = require(Shared.Util.Format)

local LeaderboardService = {}
local S

local REFRESH = 120
local stores = nil -- { discoveries = OrderedDataStore, earned = OrderedDataStore }
local nameCache = {}

local function discoveryCount(profile): number
	return Rules.recipeCount(profile.discovered) + Rules.countKeys(profile.discovered.species)
end

local function setupLeaderstats(player: Player)
	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"
	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Parent = folder
	local discoveries = Instance.new("IntValue")
	discoveries.Name = "Discoveries"
	discoveries.Parent = folder
	folder.Parent = player
end

local function updateLeaderstats(player: Player, profile)
	local folder = player:FindFirstChild("leaderstats")
	if not folder then
		return
	end
	local coins = folder:FindFirstChild("Coins") :: IntValue?
	local discoveries = folder:FindFirstChild("Discoveries") :: IntValue?
	if coins then
		coins.Value = math.floor(profile.currencies.coins)
	end
	if discoveries then
		discoveries.Value = discoveryCount(profile)
	end
end

local function nameFor(userId: number): string
	if nameCache[userId] then
		return nameCache[userId]
	end
	local player = Players:GetPlayerByUserId(userId)
	if player then
		nameCache[userId] = player.DisplayName
		return player.DisplayName
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	nameCache[userId] = if ok then name else "Player"
	return nameCache[userId]
end

local function render(rows, entries, suffix: string)
	for i, row in ipairs(rows) do
		local entry = entries[i]
		if entry then
			row.Text = string.format("<b>%d.</b> %s  <font color='#ffe17a'>%s</font>%s", i, entry.name, Format.number(entry.value), suffix)
		else
			row.Text = ""
		end
	end
end

local function serverEntries(stat: string)
	local list = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local profile = S.Data.get(player)
		if profile then
			local value = if stat == "discoveries" then discoveryCount(profile) else profile.stats.totalEarned
			table.insert(list, { name = player.DisplayName, value = value })
		end
	end
	table.sort(list, function(a, b)
		return a.value > b.value
	end)
	return list
end

local function globalEntries(store: OrderedDataStore)
	local ok, pages = pcall(function()
		return store:GetSortedAsync(false, 10)
	end)
	if not ok then
		return nil
	end
	local list = {}
	for _, item in ipairs(pages:GetCurrentPage()) do
		local userId = tonumber(string.match(item.key, "%d+"))
		table.insert(list, { name = if userId then nameFor(userId) else "?", value = item.value })
	end
	return list
end

local function refreshBoards()
	local boards = S.World.leaderboards
	if stores and S.Data.isPersistent() then
		for _, player in ipairs(Players:GetPlayers()) do
			local profile = S.Data.get(player)
			if profile then
				pcall(function()
					stores.discoveries:SetAsync("u" .. player.UserId, discoveryCount(profile))
					stores.earned:SetAsync("u" .. player.UserId, math.floor(profile.stats.totalEarned))
				end)
			end
		end
		local d = globalEntries(stores.discoveries)
		local e = globalEntries(stores.earned)
		render(boards.discoveries, d or serverEntries("discoveries"), "")
		render(boards.earned, e or serverEntries("earned"), "")
	else
		render(boards.discoveries, serverEntries("discoveries"), "")
		render(boards.earned, serverEntries("earned"), "")
	end
end

function LeaderboardService.onPlayerReady(player: Player, profile)
	setupLeaderstats(player)
	updateLeaderstats(player, profile)
end

function LeaderboardService.init(services)
	S = services
end

function LeaderboardService.start()
	local ok, result = pcall(function()
		return {
			discoveries = DataStoreService:GetOrderedDataStore("MTW_Discoveries_v1"),
			earned = DataStoreService:GetOrderedDataStore("MTW_Earned_v1"),
		}
	end)
	if ok then
		stores = result
	end

	task.spawn(function()
		while true do
			for _, player in ipairs(Players:GetPlayers()) do
				local profile = S.Data.get(player)
				if profile then
					updateLeaderstats(player, profile)
				end
			end
			task.wait(3)
		end
	end)

	task.spawn(function()
		task.wait(10)
		while true do
			refreshBoards()
			task.wait(REFRESH)
		end
	end)
end

return LeaderboardService
