-- Discovery journal: every recipe and evolution, revealed once discovered, with hints otherwise.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Creatures = require(Shared.Config.Creatures)
local Mutations = require(Shared.Config.Mutations)
local Rarity = require(Shared.Config.Rarity)
local Rules = require(Shared.Rules)

local Client = script.Parent.Parent.Parent
local ClientState = require(Client.ClientState)

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Kit = require(UI.Kit)

local Journal = {}
local C = Theme.Colors

local panel
local list: ScrollingFrame
local summary: TextLabel
local tab = "Mutations"

local function row(order: number, discovered: boolean, title: string, body: string, accent: Color3)
	local frame = Kit.frame(list, {
		Size = UDim2.new(1, -8, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = if discovered then C.panel2 else C.bg,
		LayoutOrder = order,
	})
	Kit.stroke(frame, accent, 1.2, if discovered then 0.3 else 0.75)
	Kit.padding(frame, 12, 8)
	Kit.list(frame, false, 2)
	Kit.label(frame, (if discovered then "✔ " else "🔒 ") .. title, {
		size = UDim2.new(1, 0, 0, 22),
		font = Theme.Fonts.bold,
		textSize = Theme.TextSize.small,
		color = if discovered then accent else C.muted,
	})
	Kit.label(frame, body, { size = UDim2.new(1, 0, 0, 0), autoY = true, wrap = true, textSize = Theme.TextSize.tiny, color = C.text, order = 1 })
end

local function elementOf(mutationId: string): string
	return Mutations.Types[mutationId].name
end

function Journal.refresh()
	local data = ClientState.data
	if not data or not panel.frame.Visible then
		return
	end
	summary.Text = string.format("Discovered <b>%d / %d</b> reactions", Rules.recipeCount(data.discovered), Mutations.TotalDiscoveries)
	Kit.clear(list)
	if tab == "Mutations" then
		for i, r in ipairs(Mutations.Recipes) do
			local discovered = data.discovered.recipes[r.id] == true
			local result = Mutations.Types[r.result]
			local ingredient = Mutations.Ingredients[r.ingredient].name
			local title = if discovered
				then string.format("%s + %s → %s", elementOf(r.from), ingredient, result.name)
				else string.format("??? (Chamber %d)", r.chamberLevel)
			local body = if discovered
				then string.format("Income ×%.1f · %s element · Chamber level %d", result.multiplier, result.element, r.chamberLevel)
				else "Hint: " .. r.hint
			row(i, discovered, title, body, result.color or C.text)
		end
	else
		for i, e in ipairs(Mutations.Evolutions) do
			local discovered = data.discovered.recipes[e.id] == true
			local from = Creatures.Species[e.species]
			local to = Creatures.Species[e.result]
			local knowsFrom = data.discovered.species[e.species] == true
			local title = if discovered
				then string.format("%s %s + %s → %s", Mutations.Types[e.from].name, from.name, Mutations.Ingredients[e.ingredient].name, to.name)
				else string.format("??? → a %s creature (Chamber %d)", to.rarity, e.chamberLevel)
			local body = if discovered
				then to.description
				elseif knowsFrom then "Hint: " .. e.hint
				else "Hint: discover more species to reveal this clue."
			row(i, discovered, title, body, Rarity.color(to.rarity))
		end
	end
end

function Journal.build(root: Instance, Panels)
	panel = Kit.panel(root, "Discovery Journal", function()
		Panels.close()
	end)
	Journal.frame = panel.frame
	local content = panel.content
	local top = Kit.frame(content, { Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1 })
	local tabs, select = Kit.tabs(top, { "Mutations", "Evolutions" }, function(name)
		tab = name
		Journal.refresh()
	end)
	tabs.Size = UDim2.new(0.55, 0, 1, 0)
	summary = Kit.label(top, "", { size = UDim2.new(0.45, 0, 1, 0), align = Enum.TextXAlignment.Right, color = C.cyan, textSize = Theme.TextSize.small })
	summary.Position = UDim2.fromScale(0.55, 0)
	list = Kit.scroll(content, { size = UDim2.new(1, 0, 1, -48), position = UDim2.fromOffset(0, 48) })
	Kit.list(list, false, 6)
	select("Mutations")
end

function Journal.onOpen()
	Journal.refresh()
end

return Journal
