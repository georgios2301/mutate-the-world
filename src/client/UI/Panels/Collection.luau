-- Collection index: every species, which mutations you've seen, and collection milestones.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Creatures = require(Shared.Config.Creatures)
local Mutations = require(Shared.Config.Mutations)
local Economy = require(Shared.Config.Economy)
local Rarity = require(Shared.Config.Rarity)
local Rules = require(Shared.Rules)
local Format = require(Shared.Util.Format)

local Client = script.Parent.Parent.Parent
local ClientState = require(Client.ClientState)
local Net = require(Client.Net)

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Kit = require(UI.Kit)

local Collection = {}
local C = Theme.Colors

local panel
local summary: TextLabel
local milestones: ScrollingFrame
local grid: ScrollingFrame
local detailLabel: TextLabel
local selected = "basic_blob"

local function speciesCard(id: string, order: number)
	local data = ClientState.data
	local species = Creatures.Species[id]
	local known = data.discovered.species[id] == true
	local rarityColor = Rarity.color(species.rarity)
	local card = Kit.new("TextButton", {
		Name = id,
		Size = UDim2.fromOffset(138, 150),
		BackgroundColor3 = if id == selected then C.panel3 else C.panel2,
		AutoButtonColor = true,
		Text = "",
		LayoutOrder = order,
		Parent = grid,
	})
	Kit.corner(card, 12)
	Kit.stroke(card, rarityColor, if id == selected then 2.5 else 1.2, if known then 0.2 else 0.7)
	if known then
		local icon = Kit.creatureIcon(card, { species = id, mutation = "none" }, 50)
		icon.AnchorPoint = Vector2.new(0.5, 0)
		icon.Position = UDim2.new(0.5, 0, 0, 8)
	else
		local unknown = Kit.frame(card, { Size = UDim2.fromOffset(50, 50), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 8), BackgroundColor3 = C.bg, radius = 25 })
		Kit.label(unknown, "?", { size = UDim2.fromScale(1, 1), textSize = 28, font = Theme.Fonts.title, align = Enum.TextXAlignment.Center, color = C.muted })
	end
	local name = Kit.label(card, if known then species.name else "???", {
		size = UDim2.new(1, -8, 0, 22),
		textSize = Theme.TextSize.small,
		font = Theme.Fonts.bold,
		align = Enum.TextXAlignment.Center,
		color = if known then rarityColor else C.muted,
	})
	name.Position = UDim2.fromOffset(4, 62)
	local rarity = Kit.label(card, string.format("#%d · %s", species.index, species.rarity), {
		size = UDim2.new(1, -8, 0, 18),
		textSize = Theme.TextSize.tiny,
		align = Enum.TextXAlignment.Center,
		color = rarityColor,
	})
	rarity.Position = UDim2.fromOffset(4, 84)
	local dots = Kit.frame(card, { Size = UDim2.new(1, -16, 0, 14), Position = UDim2.fromOffset(8, 110), BackgroundTransparency = 1 })
	Kit.list(dots, true, 3, Enum.HorizontalAlignment.Center)
	for i, mutationId in ipairs(Mutations.TypeOrder) do
		local m = Mutations.Types[mutationId]
		local seen = data.discovered.combos[id .. ":" .. mutationId] == true
		local dot = Kit.frame(dots, {
			Size = UDim2.fromOffset(10, 10),
			BackgroundColor3 = if seen then (m.color or C.text) else C.bg,
			LayoutOrder = i,
			radius = 5,
		})
		if not seen then
			Kit.stroke(dot, C.panel3, 1, 0)
		end
	end
	local income = Kit.label(card, if known then "Base " .. Format.number(species.baseIncome) .. "/s" else "", {
		size = UDim2.new(1, -8, 0, 14),
		textSize = Theme.TextSize.tiny,
		align = Enum.TextXAlignment.Center,
		color = C.muted,
	})
	income.Position = UDim2.fromOffset(4, 128)
	card.Activated:Connect(function()
		selected = id
		Collection.refresh()
	end)
end

local function milestoneCard(def, order: number)
	local data = ClientState.data
	local value = Rules.collectionValue(data, def.kind)
	local claimed = data.claimed.collection[def.id] == true
	local card = Kit.frame(milestones, { Size = UDim2.fromOffset(230, 92), BackgroundColor3 = C.panel2, LayoutOrder = order })
	Kit.padding(card, 8, 6)
	Kit.label(card, def.name, { size = UDim2.new(1, 0, 0, 18), textSize = Theme.TextSize.tiny, font = Theme.Fonts.bold })
	local goalLabel = Kit.label(card, string.format("%d/%d %s · %s", math.min(value, def.goal), def.goal, def.kind, Format.cost(def.reward, Economy.CurrencyInfo, Economy.CurrencyIds)), {
		size = UDim2.new(1, 0, 0, 32),
		textSize = 12,
		color = C.muted,
		wrap = true,
		alignY = Enum.TextYAlignment.Top,
	})
	goalLabel.Position = UDim2.fromOffset(0, 18)
	local button = Kit.button(card, if claimed then "Claimed" else "Claim", {
		name = "Claim_" .. def.id,
		size = UDim2.new(1, 0, 0, 22),
		color = C.gold,
		textColor = C.bg,
		textSize = Theme.TextSize.tiny,
		onClick = function()
			Net.request("ClaimCollection", def.id)
		end,
	})
	button.Position = UDim2.fromOffset(0, 54)
	Kit.setEnabled(button, not claimed and value >= def.goal)
end

function Collection.render()
	local data = ClientState.data
	if not data or not panel.frame.Visible then
		return
	end
	local speciesCount = Rules.countKeys(data.discovered.species)
	local comboCount = Rules.countKeys(data.discovered.combos)
	summary.Text = string.format(
		"Species <b>%d/%d</b>   ·   Variants <b>%d/%d</b>",
		speciesCount,
		#Creatures.Order,
		comboCount,
		#Creatures.Order * #Mutations.TypeOrder
	)
	Kit.clear(milestones)
	for i, def in ipairs(Economy.Collection) do
		milestoneCard(def, i)
	end
	Kit.clear(grid)
	for i, id in ipairs(Creatures.Order) do
		speciesCard(id, i)
	end
	local species = Creatures.Species[selected]
	local known = data.discovered.species[selected] == true
	if known then
		detailLabel.Text = string.format("<b>%s</b> (%s, %s): %s  <font color='#a59bcd'>%s</font>", species.name, species.rarity, species.element, species.description, species.origin.text)
	else
		detailLabel.Text = "<b>???</b> — " .. species.origin.text
	end
end

function Collection.build(root: Instance, Panels)
	panel = Kit.panel(root, "Collection Index", function()
		Panels.close()
	end)
	Collection.frame = panel.frame
	local content = panel.content
	summary = Kit.label(content, "", { size = UDim2.new(1, 0, 0, 24), color = C.cyan })
	milestones = Kit.scroll(content, { size = UDim2.new(1, 0, 0, 108), position = UDim2.fromOffset(0, 26), horizontal = true })
	Kit.list(milestones, true, 8)
	grid = Kit.scroll(content, { size = UDim2.new(1, 0, 1, -186), position = UDim2.fromOffset(0, 138) })
	Kit.grid(grid, Vector2.new(138, 150), 8)
	detailLabel = Kit.label(content, "", { size = UDim2.new(1, 0, 0, 44), wrap = true, textSize = Theme.TextSize.small })
	detailLabel.Position = UDim2.new(0, 0, 1, -44)
end

function Collection.onOpen()
	Collection.refresh()
end

function Collection.refresh()
	Kit.preserveSelection(panel.frame, Collection.render)
end

return Collection
