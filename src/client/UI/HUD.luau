-- Always-visible HUD. Layout avoids Roblox's own UI (player list top-right, chat top-left,
-- mobile thumbstick/jump at the bottom corners):
--   top-center:    currencies
--   left-center:   menu buttons
--   bottom-center: level + next goal bar, collector bar with travel buttons, status line
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Economy = require(Shared.Config.Economy)
local Rules = require(Shared.Rules)
local Format = require(Shared.Util.Format)

local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local Net = require(Client.Net)
local Progression = require(Client.Progression)

local Theme = require(script.Parent.Theme)
local Kit = require(script.Parent.Kit)
local Scaler = require(script.Parent.Scaler)

local HUD = {}
local C = Theme.Colors

local refs: { [string]: any } = {}

local MENU = {
	{ panel = "Inventory", icon = "🎒", label = "Creatures", key = "B" },
	{ panel = "Chamber", icon = "🧪", label = "Chamber", key = "C" },
	{ panel = "Shop", icon = "🛒", label = "Shop", key = "U" },
	{ panel = "Travel", icon = "🌍", label = "Travel", key = "T" },
	{ panel = "Defense", icon = "🛡️", label = "Security", key = "G" },
	{ panel = "Collection", icon = "📖", label = "Index", key = "K" },
	{ panel = "Menu", icon = "☰", label = "More", key = "M" },
}
HUD.Menu = MENU

local function chip(parent: Instance, currency: string, big: boolean, order: number)
	local info = Economy.CurrencyInfo[currency]
	local frame = Kit.frame(parent, {
		Name = currency,
		Size = if big then UDim2.fromOffset(220, 44) else UDim2.fromOffset(94, 36),
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.12,
		LayoutOrder = order,
		radius = if big then 14 else 10,
	})
	Kit.stroke(frame, info.color, 1.5, 0.35)
	local glyph = Kit.label(frame, info.glyph, {
		size = UDim2.fromOffset(if big then 38 else 26, if big then 44 else 36),
		textSize = if big then 26 else 17,
		color = info.color,
		align = Enum.TextXAlignment.Center,
		font = Theme.Fonts.bold,
	})
	glyph.Position = UDim2.fromOffset(2, 0)
	local value = Kit.label(frame, "0", {
		size = UDim2.new(1, if big then -42 else -28, 1, 0),
		textSize = if big then 23 else 16,
		font = if big then Theme.Fonts.title else Theme.Fonts.bold,
	})
	value.Position = UDim2.fromOffset(if big then 38 else 26, 0)
	return frame, value
end

function HUD.build(root: Instance, Panels)
	-- Currencies (top-center, below the Roblox top bar)
	local currencies = Kit.frame(root, {
		Name = "Currencies",
		Size = UDim2.fromOffset(720, 44),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 62),
		BackgroundTransparency = 1,
	})
	Kit.list(currencies, true, 6, Enum.HorizontalAlignment.Center)
	local coinChip, coinsValue = chip(currencies, "coins", true, 1)
	refs.coins = coinsValue
	coinsValue.Size = UDim2.new(1, -110, 1, 0)
	refs.income = Kit.label(coinChip, "", {
		size = UDim2.fromOffset(70, 44),
		textSize = Theme.TextSize.tiny,
		color = C.gold,
		align = Enum.TextXAlignment.Right,
		font = Theme.Fonts.bold,
	})
	refs.income.AnchorPoint = Vector2.new(1, 0)
	refs.income.Position = UDim2.new(1, -8, 0, 0)
	refs.small = {}
	for i, id in ipairs({ "dna", "ice", "toxic", "plasma", "cosmic" }) do
		local _, v = chip(currencies, id, false, i + 1)
		refs.small[id] = v
	end

	-- Menu buttons (left-center)
	local menu = Kit.frame(root, {
		Name = "Menu",
		Size = UDim2.fromOffset(66, #MENU * 68),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 14, 0.5, 20),
		BackgroundTransparency = 1,
	})
	Kit.list(menu, false, 6)
	for i, item in ipairs(MENU) do
		local b = Kit.button(menu, "", {
			name = item.panel,
			size = UDim2.fromOffset(62, 62),
			color = C.panel2,
			order = i,
			radius = 14,
			onClick = function()
				Panels.toggle(item.panel)
			end,
		})
		Kit.stroke(b, C.stroke, 1.5, 0.3)
		local icon = Kit.label(b, item.icon, { size = UDim2.new(1, 0, 0, 36), textSize = 24, align = Enum.TextXAlignment.Center })
		icon.Position = UDim2.fromOffset(0, 4)
		local text = Kit.label(b, item.label, { size = UDim2.new(1, 0, 0, 16), textSize = 12, font = Theme.Fonts.bold, align = Enum.TextXAlignment.Center })
		text.Position = UDim2.new(0, 0, 1, -20)
	end

	-- Collector + travel (bottom-center)
	local bottom = Kit.frame(root, {
		Name = "Bottom",
		Size = UDim2.fromOffset(480, 64),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.1,
		radius = 16,
	})
	Kit.stroke(bottom, C.gold, 1.5, 0.35)
	Kit.padding(bottom, 10, 8)
	local collectorInfo = Kit.frame(bottom, { Size = UDim2.new(0, 190, 1, 0), BackgroundTransparency = 1 })
	refs.pendingLabel = Kit.label(collectorInfo, "● 0 / 0", { size = UDim2.new(1, 0, 0, 22), textSize = Theme.TextSize.small, font = Theme.Fonts.bold, color = C.gold })
	local cbar, setCollector = Kit.bar(collectorInfo, C.gold, UDim2.new(1, 0, 0, 12))
	cbar.Position = UDim2.fromOffset(0, 28)
	refs.setCollector = setCollector
	local buttons = Kit.frame(bottom, { Size = UDim2.new(1, -200, 1, 0), Position = UDim2.fromOffset(200, 0), BackgroundTransparency = 1 })
	Kit.list(buttons, true, 8, Enum.HorizontalAlignment.Right)
	refs.collect = Kit.button(buttons, "Collect", {
		size = UDim2.fromOffset(96, 44),
		color = C.gold,
		textColor = C.bg,
		order = 1,
		onClick = function()
			Net.request("CollectCoins")
		end,
	})
	Kit.button(buttons, "🏠 Home", {
		size = UDim2.fromOffset(78, 44),
		color = C.purple,
		textSize = Theme.TextSize.small,
		order = 2,
		onClick = function()
			Net.request("Travel", "island")
		end,
	})
	Kit.button(buttons, "⇄ Hub", {
		size = UDim2.fromOffset(78, 44),
		color = C.cyan,
		textColor = C.bg,
		textSize = Theme.TextSize.small,
		order = 3,
		onClick = function()
			Net.request("Travel", "hub")
		end,
	})

	-- Level + next goal (bottom-center, above the collector; the tutorial card takes this spot)
	local goal = Kit.new("TextButton", {
		Name = "Goal",
		Size = UDim2.fromOffset(480, 58),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -84),
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.1,
		AutoButtonColor = true,
		Text = "",
		Parent = root,
	})
	Kit.corner(goal, 14)
	Kit.stroke(goal, C.green, 1.5, 0.3)
	refs.goal = goal
	local badge = Kit.frame(goal, { Size = UDim2.fromOffset(46, 46), Position = UDim2.fromOffset(6, 6), BackgroundColor3 = C.purple, radius = 23 })
	Kit.stroke(badge, C.cyan, 2, 0)
	refs.level = Kit.label(badge, "1", {
		size = UDim2.fromScale(1, 1),
		textSize = 22,
		font = Theme.Fonts.title,
		align = Enum.TextXAlignment.Center,
	})
	local bar, setBar = Kit.bar(goal, C.cyan, UDim2.new(1, -72, 0, 14))
	bar.Position = UDim2.fromOffset(62, 7)
	refs.setXp = setBar
	refs.goalText = Kit.label(goal, "", {
		size = UDim2.new(1, -72, 0, 30),
		textSize = Theme.TextSize.small,
		wrap = true,
	})
	refs.goalText.Position = UDim2.fromOffset(62, 24)
	goal.Activated:Connect(function()
		if refs.goalAction then
			refs.goalAction()
		end
	end)

	-- Status line (mutation timer, save warning)
	refs.status = Kit.label(root, "", {
		size = UDim2.fromOffset(480, 22),
		textSize = Theme.TextSize.small,
		font = Theme.Fonts.bold,
		color = C.green,
		align = Enum.TextXAlignment.Center,
	})
	refs.status.AnchorPoint = Vector2.new(0.5, 0)
	refs.status.Position = UDim2.new(0.5, 0, 0, 110)

	for _, block in ipairs({ currencies, menu, bottom, goal, refs.status }) do
		Scaler.attach(block)
	end
	refs.Panels = Panels
end

function HUD.refresh()
	local data = ClientState.data
	if not data then
		return
	end
	refs.coins.Text = Format.number(data.currencies.coins)
	refs.income.Text = "+" .. Format.number(data.income) .. "/s"
	for id, label in pairs(refs.small) do
		label.Text = Format.number(data.currencies[id] or 0)
	end
	local level, into, needed = Rules.levelProgress(data.xp)
	refs.level.Text = tostring(level)
	refs.setXp(into / math.max(1, needed), "Level " .. level .. " · " .. Format.number(into) .. " / " .. Format.number(needed) .. " XP")

	local pending = math.floor(data.pendingCoins)
	refs.pendingLabel.Text = "● " .. Format.number(pending) .. " / " .. Format.number(data.collectorCapacity)
	refs.setCollector(pending / math.max(1, data.collectorCapacity))
	Kit.setEnabled(refs.collect, pending >= 1)

	-- The tutorial card replaces the goal bar while the tutorial runs.
	refs.goal.Visible = data.tutorial.done
	local goalText, action = Progression.nextGoal(data, refs.Panels)
	refs.goalText.Text = "<font color='#7cff4f'><b>NEXT:</b></font> " .. goalText
	refs.goalAction = action

	local status = ""
	local job = data.activeMutation
	if job then
		status = "🧪 Mutating... " .. Format.time(job.endsAt - ClientState.now())
	end
	if not data.persistent then
		status = (if status ~= "" then status .. "   " else "") .. "<font color='#ff9a3c'>⚠ Saving disabled on this server</font>"
	end
	refs.status.Text = status
end

return HUD
