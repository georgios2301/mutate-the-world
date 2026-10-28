-- Mutation Chamber: pick a creature + an element, preview the reaction, mutate.
-- The preview is computed from the shared recipe config; the server re-validates everything.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Creatures = require(Shared.Config.Creatures)
local Mutations = require(Shared.Config.Mutations)
local Economy = require(Shared.Config.Economy)
local Rarity = require(Shared.Config.Rarity)
local Format = require(Shared.Util.Format)

local Client = script.Parent.Parent.Parent
local ClientState = require(Client.ClientState)
local Net = require(Client.Net)

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Kit = require(UI.Kit)
local CreatureView = require(UI.CreatureView)

local Chamber = {}
local C = Theme.Colors

local panel
local list: ScrollingFrame
local ingredientButtons = {}
local preview: { [string]: any } = {}
local selectedCreature: string? = nil
local selectedIngredient: string? = nil
local Panels
local ticking = false

local function resultText(reaction): string
	local data = ClientState.data
	if not data.discovered.recipes[reaction.id] then
		return "Result: <b>???</b>  <font color='#7cff4f'>New discovery!</font>"
	end
	local species = Creatures.Species[reaction.resultSpecies]
	local name = Mutations.displayName(species.name, reaction.resultMutation)
	local hex = Rarity.color(species.rarity):ToHex()
	local mult = Mutations.Types[reaction.resultMutation].multiplier
	local extra = if reaction.kind == "evolution" then " (evolution!)" else " (×" .. mult .. " income)"
	return string.format("Result: <font color='#%s'><b>%s</b></font>%s", hex, name, extra)
end

local function updateJob()
	local data = ClientState.data
	local job = data and data.activeMutation
	preview.jobBox.Visible = job ~= nil
	if not job then
		return
	end
	local c = ClientState.creature(job.creatureId)
	local total = math.max(1, job.endsAt - job.startedAt)
	local left = job.endsAt - ClientState.now()
	local target = if data.discovered.recipes[job.reactionId]
		then Mutations.displayName(Creatures.Species[job.resultSpecies].name, job.resultMutation)
		else "???"
	preview.jobLabel.Text = string.format("Mutating %s → %s", if c then Kit.creatureName(c) else "creature", target)
	preview.setJob(1 - left / total, if left > 0 then Format.time(left) .. " left" else "Finishing...")
end

local function renderPreview()
	local data = ClientState.data
	local creature = selectedCreature and ClientState.creature(selectedCreature)
	preview.view:set(creature)
	local chamberLevel = data.upgrades.chamber or 1
	preview.level.Text = "Chamber level " .. chamberLevel .. "  ·  speed ×" .. string.format("%.2f", 1 / Mutations.ChamberSpeed[chamberLevel])
	Kit.setEnabled(preview.upgrade, chamberLevel < #Economy.Upgrades.chamber.levels)

	if not creature then
		preview.result.Text = "Choose a creature on the left."
		preview.cost.Text = ""
		Kit.setEnabled(preview.mutate, false)
		return
	end
	if not selectedIngredient then
		preview.result.Text = "Now add an element."
		preview.cost.Text = ""
		Kit.setEnabled(preview.mutate, false)
		return
	end
	local reaction = Mutations.findReaction(creature.species, creature.mutation, selectedIngredient)
	if not reaction then
		preview.result.Text = "<font color='#ff9a3c'>No reaction.</font> These don't combine. Check the Journal for hints."
		preview.cost.Text = ""
		Kit.setEnabled(preview.mutate, false)
		return
	end
	local def = reaction.def
	local affordable = ClientState.canAfford(def.cost)
	local chamberOk = chamberLevel >= def.chamberLevel
	preview.result.Text = resultText(reaction)
	local costColor = if affordable then "ffffff" else "ff6b6b"
	local lines = {
		string.format("Cost: <font color='#%s'>%s</font>", costColor, Format.cost(def.cost, Economy.CurrencyInfo, Economy.CurrencyIds)),
		"Time: " .. Format.time(Mutations.duration(def, chamberLevel)),
	}
	if not chamberOk then
		table.insert(lines, "<font color='#ff6b6b'>Needs Chamber level " .. def.chamberLevel .. "</font>")
	end
	preview.cost.Text = table.concat(lines, "\n")
	local busy = data.activeMutation ~= nil
	Kit.setEnabled(preview.mutate, affordable and chamberOk and not busy and creature.lock == nil)
	Kit.setText(preview.mutate, if busy then "Chamber busy" else "MUTATE!")
end

local function renderList()
	local data = ClientState.data
	Kit.clear(list)
	local job = data.activeMutation
	local order = 0
	for _, c in ipairs(ClientState.sortedCreatures()) do
		local mutating = job and job.creatureId == c.id
		if not c.lock and not mutating then
			order += 1
			if not selectedCreature then
				selectedCreature = c.id
			end
			local species = Creatures.Species[c.species]
			local selected = c.id == selectedCreature
			local row = Kit.new("TextButton", {
				Name = c.id,
				Size = UDim2.new(1, -8, 0, 48),
				BackgroundColor3 = if selected then C.panel3 else C.panel2,
				AutoButtonColor = true,
				Text = "",
				LayoutOrder = order,
				Parent = list,
			})
			Kit.corner(row, 10)
			if selected then
				Kit.stroke(row, C.cyan, 2, 0)
			end
			local icon = Kit.creatureIcon(row, c, 36)
			icon.Position = UDim2.fromOffset(6, 6)
			local name = Kit.label(row, Kit.creatureName(c), {
				size = UDim2.new(1, -52, 0, 22),
				textSize = Theme.TextSize.small,
				font = Theme.Fonts.bold,
				color = Rarity.color(species.rarity),
			})
			name.Position = UDim2.fromOffset(48, 3)
			local sub = Kit.label(row, "Lv " .. c.level .. " · " .. Mutations.Types[c.mutation].name, {
				size = UDim2.new(1, -52, 0, 18),
				textSize = Theme.TextSize.tiny,
				color = C.muted,
			})
			sub.Position = UDim2.fromOffset(48, 25)
			row.Activated:Connect(function()
				selectedCreature = c.id
				Chamber.refresh()
			end)
		end
	end
	if selectedCreature and not ClientState.creature(selectedCreature) then
		selectedCreature = nil
	end
end

local function renderIngredients()
	for id, button in pairs(ingredientButtons) do
		local ingredient = Mutations.Ingredients[id]
		local owned = ClientState.currency(ingredient.currency)
		local selected = id == selectedIngredient
		button.BackgroundColor3 = if selected then C.panel3 else C.panel2
		local stroke = button:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = if selected then C.cyan else Mutations.Elements[ingredient.element].color
			stroke.Transparency = if selected then 0 else 0.5
		end
		local countLabel = button:FindFirstChild("Count") :: TextLabel
		countLabel.Text = "You have " .. Format.number(owned)
	end
end

function Chamber.render()
	if not ClientState.data or not panel.frame.Visible then
		return
	end
	renderList()
	renderIngredients()
	renderPreview()
	updateJob()
end

function Chamber.build(root: Instance, panels)
	Panels = panels
	panel = Kit.panel(root, "Mutation Chamber", function()
		Panels.close()
	end)
	Chamber.frame = panel.frame
	local content = panel.content

	-- Column 1: creatures
	local col1 = Kit.frame(content, { Size = UDim2.new(0, 250, 1, 0), BackgroundTransparency = 1 })
	Kit.label(col1, "1. Choose a creature", { font = Theme.Fonts.bold, color = C.cyan })
	list = Kit.scroll(col1, { size = UDim2.new(1, 0, 1, -30), position = UDim2.fromOffset(0, 30) })
	Kit.list(list, false, 6)

	-- Column 2: ingredients
	local col2 = Kit.frame(content, { Size = UDim2.new(0, 206, 1, 0), Position = UDim2.fromOffset(262, 0), BackgroundTransparency = 1 })
	Kit.label(col2, "2. Add an element", { font = Theme.Fonts.bold, color = C.cyan })
	local ingredientsHolder = Kit.frame(col2, { Size = UDim2.new(1, 0, 1, -30), Position = UDim2.fromOffset(0, 30), BackgroundTransparency = 1 })
	Kit.list(ingredientsHolder, false, 8)
	for i, id in ipairs(Mutations.IngredientOrder) do
		local ingredient = Mutations.Ingredients[id]
		local color = Mutations.Elements[ingredient.element].color
		local b = Kit.new("TextButton", {
			Name = id,
			Size = UDim2.new(1, 0, 0, 60),
			BackgroundColor3 = C.panel2,
			AutoButtonColor = true,
			Text = "",
			LayoutOrder = i,
			Parent = ingredientsHolder,
		})
		Kit.corner(b, 12)
		Kit.stroke(b, color, 1.5, 0.5)
		local glyph = Kit.label(b, Economy.CurrencyInfo[ingredient.currency].glyph, {
			size = UDim2.fromOffset(40, 60),
			textSize = 28,
			color = color,
			align = Enum.TextXAlignment.Center,
		})
		glyph.Position = UDim2.fromOffset(4, 0)
		local name = Kit.label(b, ingredient.name, { size = UDim2.new(1, -50, 0, 24), font = Theme.Fonts.bold, textSize = Theme.TextSize.small })
		name.Position = UDim2.fromOffset(46, 8)
		local count = Kit.label(b, "", { name = "Count", size = UDim2.new(1, -50, 0, 20), textSize = Theme.TextSize.tiny, color = C.muted })
		count.Position = UDim2.fromOffset(46, 32)
		b.Activated:Connect(function()
			selectedIngredient = id
			Chamber.refresh()
		end)
		ingredientButtons[id] = b
	end

	-- Column 3: preview
	local col3 = Kit.frame(content, {
		Size = UDim2.new(1, -480, 1, 0),
		Position = UDim2.fromOffset(480, 0),
		BackgroundColor3 = C.panel2,
	})
	Kit.padding(col3, 10)
	Kit.list(col3, false, 6)
	preview.view = CreatureView.new(col3, UDim2.new(1, 0, 0, 120))
	preview.result = Kit.label(col3, "", { size = UDim2.new(1, 0, 0, 44), wrap = true, textSize = Theme.TextSize.small, order = 1 })
	preview.cost = Kit.label(col3, "", { size = UDim2.new(1, 0, 0, 58), wrap = true, textSize = Theme.TextSize.small, order = 2, alignY = Enum.TextYAlignment.Top })
	preview.mutate = Kit.button(col3, "MUTATE!", {
		size = UDim2.new(1, 0, 0, 46),
		color = C.green,
		textColor = C.bg,
		textSize = 20,
		font = Theme.Fonts.title,
		order = 3,
		onClick = function()
			if selectedCreature and selectedIngredient then
				Net.request("StartMutation", selectedCreature, selectedIngredient)
			end
		end,
	})
	local jobBox = Kit.frame(col3, { Size = UDim2.new(1, 0, 0, 46), BackgroundTransparency = 1, LayoutOrder = 4 })
	preview.jobBox = jobBox
	preview.jobLabel = Kit.label(jobBox, "", { size = UDim2.new(1, 0, 0, 22), textSize = Theme.TextSize.tiny, color = C.green, font = Theme.Fonts.bold })
	local bar, setJob = Kit.bar(jobBox, C.green, UDim2.new(1, 0, 0, 16))
	bar.Position = UDim2.fromOffset(0, 26)
	preview.setJob = setJob
	local footer = Kit.frame(col3, { Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, LayoutOrder = 5 })
	preview.level = Kit.label(footer, "", { size = UDim2.new(1, -96, 1, 0), textSize = Theme.TextSize.tiny, color = C.muted })
	preview.upgrade = Kit.button(footer, "Upgrade", {
		size = UDim2.fromOffset(90, 28),
		color = C.purple,
		textSize = Theme.TextSize.tiny,
		onClick = function()
			Panels.open("Shop", "upgrades")
		end,
	})
	preview.upgrade.AnchorPoint = Vector2.new(1, 0)
	preview.upgrade.Position = UDim2.new(1, 0, 0, 1)
end

function Chamber.onOpen(arg)
	if type(arg) == "table" then
		selectedCreature = arg.creatureId or selectedCreature
		selectedIngredient = arg.ingredient or selectedIngredient
	end
	local data = ClientState.data
	if data and not data.tutorial.done and data.tutorial.step and data.tutorial.step <= 6 then
		-- Tutorial: preselect the starter blob + ice.
		for _, c in ipairs(data.creatures) do
			if c.starter and c.mutation == "none" then
				selectedCreature = selectedCreature or c.id
				selectedIngredient = selectedIngredient or "ice"
			end
		end
		Net.silent("TutorialAction", "chamberOpened")
	end
	Chamber.refresh()
	if not ticking then
		ticking = true
		task.spawn(function()
			while panel.frame.Visible do
				updateJob()
				task.wait(0.2)
			end
			ticking = false
		end)
	end
end

function Chamber.refresh()
	Kit.preserveSelection(panel.frame, Chamber.render)
end

return Chamber
