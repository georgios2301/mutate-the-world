-- Shop: upgrades, creature market, daily/research rewards and the optional Robux store.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Creatures = require(Shared.Config.Creatures)
local Economy = require(Shared.Config.Economy)
local Products = require(Shared.Config.Products)
local Rarity = require(Shared.Config.Rarity)
local Rules = require(Shared.Rules)
local Format = require(Shared.Util.Format)

local Client = script.Parent.Parent.Parent
local ClientState = require(Client.ClientState)
local Net = require(Client.Net)

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Kit = require(UI.Kit)

local Shop = {}
local C = Theme.Colors

local panel
local list: ScrollingFrame
local selectTab
local tab = "Upgrades"

local TAB_BY_ARG = { upgrades = "Upgrades", creatures = "Creatures", rewards = "Rewards", store = "Store" }

local function costText(cost): string
	return Format.cost(cost, Economy.CurrencyInfo, Economy.CurrencyIds)
end

local function heading(text: string, order: number)
	Kit.label(list, text, { size = UDim2.new(1, -8, 0, 28), font = Theme.Fonts.title, textSize = Theme.TextSize.h2, color = C.cyan, order = order })
end

-- Generic row: title, subtitle, right-side button.
-- `inset` reserves room on the left (e.g. for an icon).
local function row(order: number, title: string, subtitle: string, buttonText: string, enabled: boolean, onClick, accent: Color3?, inset: number?)
	local left = inset or 0
	local frame = Kit.frame(list, { Size = UDim2.new(1, -8, 0, 68), BackgroundColor3 = C.panel2, LayoutOrder = order })
	Kit.stroke(frame, accent or C.stroke, 1.2, 0.5)
	Kit.padding(frame, 12, 8)
	local t = Kit.label(frame, title, { size = UDim2.new(1, -190 - left, 0, 24), font = Theme.Fonts.bold })
	t.Position = UDim2.fromOffset(left, 0)
	local s = Kit.label(frame, subtitle, { size = UDim2.new(1, -190 - left, 0, 28), textSize = Theme.TextSize.tiny, color = C.muted, wrap = true, alignY = Enum.TextYAlignment.Top })
	s.Position = UDim2.fromOffset(left, 24)
	local button = Kit.button(frame, buttonText, {
		name = "Row_" .. order,
		size = UDim2.fromOffset(176, 44),
		color = accent or C.green,
		textColor = C.bg,
		textSize = Theme.TextSize.small,
		onClick = onClick,
	})
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Position = UDim2.fromScale(1, 0.5)
	Kit.setEnabled(button, enabled)
	return frame
end

local function renderUpgrades()
	local data = ClientState.data
	for i, id in ipairs(Economy.UpgradeOrder) do
		local def = Economy.Upgrades[id]
		local info = Rules.upgradeInfo(data.upgrades, id)
		local current = info.value
		local subtitle = def.description .. "\nLv " .. info.level .. "/" .. info.maxLevel .. ":  " .. Format.number(current)
		if info.nextValue then
			subtitle ..= " → " .. Format.number(info.nextValue)
		end
		local buttonText, enabled
		if info.blocked == "Maxed out" then
			buttonText, enabled = "MAX", false
		elseif info.blocked then
			buttonText, enabled = info.blocked, false
		else
			buttonText = "● " .. Format.number(info.price)
			enabled = data.currencies.coins >= info.price
		end
		row(i, def.name, subtitle, buttonText, enabled, function()
			Net.request("BuyUpgrade", id)
		end, C.gold)
	end
end

local function renderCreatures()
	local data = ClientState.data
	heading("Creature Market", 0)
	for i, id in ipairs(Economy.ShopSpecies) do
		local species = Creatures.Species[id]
		local frame = row(i, species.name, string.format("%s · earns %s/s base · %s", species.rarity, Format.number(species.baseIncome), species.description), "● " .. Format.number(species.shopPrice), data.currencies.coins >= species.shopPrice, function()
			Net.request("BuyCreature", id)
		end, Rarity.color(species.rarity), 50)
		local icon = Kit.creatureIcon(frame, { species = id, mutation = "none" }, 40)
		icon.AnchorPoint = Vector2.new(0, 0.5)
		icon.Position = UDim2.new(0, 0, 0.5, 0)
	end
	Kit.label(list, "Rarer creatures live in the biomes, or can be created in the Mutation Chamber.", {
		size = UDim2.new(1, -8, 0, 40),
		wrap = true,
		textSize = Theme.TextSize.small,
		color = C.muted,
		order = 100,
	})
end

local function renderRewards()
	local data = ClientState.data
	local daily = data.daily
	heading("Daily Reward", 0)
	local track = Kit.frame(list, { Size = UDim2.new(1, -8, 0, 64), BackgroundTransparency = 1, LayoutOrder = 1 })
	Kit.list(track, true, 6)
	for day = 1, #Economy.Daily do
		local isNext = day == daily.streakDay
		local box = Kit.frame(track, {
			Size = UDim2.fromOffset(96, 60),
			BackgroundColor3 = if isNext then C.panel3 else C.panel2,
			LayoutOrder = day,
		})
		Kit.stroke(box, if isNext then C.gold else C.stroke, if isNext then 2 else 1, if isNext then 0 else 0.6)
		Kit.label(box, "Day " .. day, { size = UDim2.new(1, 0, 0, 22), font = Theme.Fonts.bold, textSize = Theme.TextSize.tiny, align = Enum.TextXAlignment.Center })
		local reward = Kit.label(box, costText(Economy.Daily[day]), {
			size = UDim2.new(1, -6, 0, 34),
			textSize = 11,
			wrap = true,
			align = Enum.TextXAlignment.Center,
			color = C.muted,
		})
		reward.Position = UDim2.fromOffset(3, 22)
	end
	local claimText = if daily.canClaim then "Claim Day " .. daily.streakDay .. ": " .. costText(daily.reward) else "Next reward in " .. Format.time(daily.nextIn - (ClientState.now() - data.serverNow))
	local claim = Kit.button(list, claimText, {
		size = UDim2.new(1, -8, 0, 40),
		color = C.gold,
		textColor = C.bg,
		textSize = Theme.TextSize.small,
		order = 2,
		onClick = function()
			Net.request("ClaimDaily")
		end,
	})
	Kit.setEnabled(claim, daily.canClaim)

	heading("Research Milestones", 3)
	for i, def in ipairs(Economy.Research) do
		local value = Rules.statValue(data, def.stat)
		local claimed = data.claimed.research[def.id] == true
		row(10 + i, def.name, string.format("%s / %s %s  ·  Reward: %s", Format.number(math.min(value, def.goal)), Format.number(def.goal), def.stat, costText(def.reward)), if claimed then "Claimed" else "Claim", not claimed and value >= def.goal, function()
			Net.request("ClaimResearch", def.id)
		end, C.cyan)
	end
end

local function sortedByOrder(map)
	local keys = {}
	for key in pairs(map) do
		table.insert(keys, key)
	end
	table.sort(keys, function(a, b)
		return (map[a].order or 0) < (map[b].order or 0)
	end)
	return keys
end

local function renderStore()
	local data = ClientState.data
	Kit.label(list, "Everything here is optional: cosmetics and convenience only. The full game is free.", {
		size = UDim2.new(1, -8, 0, 24),
		textSize = Theme.TextSize.small,
		color = C.muted,
		order = 0,
		wrap = true,
	})
	heading("Game Passes", 1)
	local order = 2
	for _, key in ipairs(sortedByOrder(Products.GamePasses)) do
		local def = Products.GamePasses[key]
		local owned = data.passes[key] == true
		local label = if owned then "Owned" elseif def.id == 0 then "Coming soon" else "Buy (Robux)"
		row(order, def.name, def.description, label, not owned and def.id ~= 0, function()
			Net.request("PromptPurchase", "pass", key)
		end, C.purple)
		order += 1
	end
	heading("Cosmetics", order)
	order += 1
	for _, key in ipairs(sortedByOrder(Products.DevProducts)) do
		local def = Products.DevProducts[key]
		local owned = (def.grant.theme and data.cosmetics.themes[def.grant.theme]) or (def.grant.aura and data.cosmetics.auras[def.grant.aura])
		local label = if owned then "Owned" elseif def.id == 0 then "Coming soon" else "Buy (Robux)"
		row(order, def.name, def.description, label, not owned and def.id ~= 0, function()
			Net.request("PromptPurchase", "product", key)
		end, C.orange)
		order += 1
	end
	heading("Island Themes", order)
	order += 1
	for _, themeId in ipairs(Products.ThemeOrder) do
		local theme = Products.Themes[themeId]
		local ownedByPass = false
		for passKey in pairs(data.passes) do
			local pass = Products.GamePasses[passKey]
			if pass and pass.themes and table.find(pass.themes, themeId) then
				ownedByPass = true
			end
		end
		local owned = data.cosmetics.themes[themeId] or ownedByPass
		local equipped = data.cosmetics.theme == themeId
		row(order, theme.name, if owned then "Owned" else "Unlock via the store", if equipped then "Equipped" else "Equip", owned and not equipped, function()
			Net.request("EquipTheme", themeId)
		end, theme.trim or C.green)
		order += 1
	end
	if data.cosmetics.auras.sparkle then
		local on = data.cosmetics.aura == "sparkle"
		row(order, "Sparkle Aura", "Cosmetic sparkles on your creatures", if on then "Turn off" else "Turn on", true, function()
			Net.request("EquipAura", if on then "" else "sparkle")
		end, C.gold)
	end
end

function Shop.render()
	if not ClientState.data or not panel.frame.Visible then
		return
	end
	local position = list.CanvasPosition
	Kit.clear(list)
	if tab == "Upgrades" then
		renderUpgrades()
	elseif tab == "Creatures" then
		renderCreatures()
	elseif tab == "Rewards" then
		renderRewards()
	else
		renderStore()
	end
	list.CanvasPosition = position
end

function Shop.build(root: Instance, Panels)
	panel = Kit.panel(root, "Shop", function()
		Panels.close()
	end)
	Shop.frame = panel.frame
	local content = panel.content
	local _, select = Kit.tabs(content, { "Upgrades", "Creatures", "Rewards", "Store" }, function(name)
		tab = name
		if list then
			list.CanvasPosition = Vector2.zero
		end
		Shop.refresh()
	end)
	selectTab = select
	list = Kit.scroll(content, { size = UDim2.new(1, 0, 1, -48), position = UDim2.fromOffset(0, 48) })
	Kit.list(list, false, 8)
	select("Upgrades")
end

function Shop.onOpen(arg)
	if type(arg) == "string" and TAB_BY_ARG[arg] then
		selectTab(TAB_BY_ARG[arg])
	else
		Shop.refresh()
	end
end

function Shop.refresh()
	Kit.preserveSelection(panel.frame, Shop.render)
end

return Shop
