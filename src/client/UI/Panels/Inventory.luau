-- Creature inventory: browse, place/remove from pads, level up, release, send to chamber.
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
local CreatureView = require(UI.CreatureView)

local Inventory = {}
local C = Theme.Colors

local panel
local grid: ScrollingFrame
local countLabel: TextLabel
local detail: { [string]: any } = {}
local filter = "All"
local selectedId: string? = nil
local Panels
local rootGui

local function statusOf(c): (string, Color3)
	if c.lock == "heist" then
		return "Being stolen!", C.red
	elseif c.lock == "trade" then
		return "In a trade", C.orange
	end
	local job = ClientState.data.activeMutation
	if job and job.creatureId == c.id then
		return "Mutating", C.green
	end
	if c.slot then
		return "On pad " .. c.slot, C.cyan
	end
	return "In storage", C.muted
end

local function costText(cost): string
	return Format.cost(cost, Economy.CurrencyInfo, Economy.CurrencyIds)
end

local function renderDetail()
	local c = selectedId and ClientState.creature(selectedId)
	detail.holder.Visible = c ~= nil
	detail.empty.Visible = c == nil
	if not c then
		detail.view:set(nil)
		return
	end
	local species = Creatures.Species[c.species]
	local mutation = Mutations.Types[c.mutation]
	detail.view:set(c)
	detail.name.Text = Kit.creatureName(c)
	detail.name.TextColor3 = Rarity.color(species.rarity)
	detail.info.Text = string.format("%s · %s element · %s mutation", species.rarity, species.element, mutation.name)
	local resonance = if Rules.hasResonance(c) then "  <font color='#7cff4f'>Resonance ×" .. Mutations.ResonanceBonus .. "</font>" else ""
	detail.income.Text = string.format("Income: <b>%s/s</b>%s   ·   Level %d/%d", Format.number(c.income), resonance, c.level, Economy.CreatureLevel.maxLevel)
	local status, color = statusOf(c)
	local protectedText = ""
	if c.starter then
		protectedText = "  ·  🛡 Starter (can't be stolen or traded)"
	elseif not Rules.isStealableSpecies(c.species) then
		protectedText = "  ·  🛡 " .. species.rarity .. "s can't be stolen"
	elseif c.protectedUntil > ClientState.now() then
		protectedText = "  ·  🛡 Protected " .. Format.time(c.protectedUntil - ClientState.now())
	end
	detail.status.Text = status .. protectedText
	detail.status.TextColor3 = color

	Kit.setText(detail.place, if c.slot then "Remove from pad" else "Place on pad")
	Kit.setEnabled(detail.place, c.lock == nil and not (ClientState.data.activeMutation and ClientState.data.activeMutation.creatureId == c.id))

	local levelCost = Rules.levelUpCost(c)
	if levelCost then
		Kit.setText(detail.levelUp, "Level up · " .. costText(levelCost))
		Kit.setEnabled(detail.levelUp, ClientState.canAfford(levelCost) and c.lock == nil)
	else
		Kit.setText(detail.levelUp, "Max level")
		Kit.setEnabled(detail.levelUp, false)
	end
	local reward = Rules.releaseReward(c)
	Kit.setText(detail.release, "Release (+" .. reward.dna .. " DNA)")
	Kit.setEnabled(detail.release, not c.starter and c.lock == nil and #ClientState.data.creatures > 1)
end

local function card(c, order: number)
	local species = Creatures.Species[c.species]
	local selected = c.id == selectedId
	local button = Kit.new("TextButton", {
		Name = c.id,
		Size = UDim2.fromOffset(148, 118),
		BackgroundColor3 = if selected then C.panel3 else C.panel2,
		AutoButtonColor = true,
		Text = "",
		LayoutOrder = order,
		Parent = grid,
	})
	Kit.corner(button, 12)
	Kit.stroke(button, if selected then C.cyan else Rarity.color(species.rarity), if selected then 2.5 else 1.2, if selected then 0 else 0.5)
	local icon = Kit.creatureIcon(button, c, 44)
	icon.Position = UDim2.fromOffset(8, 8)
	local name = Kit.label(button, Kit.creatureName(c), {
		size = UDim2.fromOffset(84, 40),
		textSize = Theme.TextSize.tiny,
		font = Theme.Fonts.bold,
		wrap = true,
		color = Rarity.color(species.rarity),
	})
	name.Position = UDim2.fromOffset(58, 6)
	local stats = Kit.label(button, "Lv " .. c.level .. " · " .. Format.number(c.income) .. "/s", { size = UDim2.new(1, -16, 0, 18), textSize = Theme.TextSize.tiny })
	stats.Position = UDim2.fromOffset(8, 58)
	local status, color = statusOf(c)
	local chip = Kit.label(button, status, { size = UDim2.new(1, -16, 0, 22), textSize = Theme.TextSize.tiny, font = Theme.Fonts.bold, color = color })
	chip.Position = UDim2.fromOffset(8, 86)
	button.Activated:Connect(function()
		selectedId = c.id
		Inventory.refresh()
	end)
end

function Inventory.render()
	local data = ClientState.data
	if not data or not panel.frame.Visible then
		return
	end
	if selectedId and not ClientState.creature(selectedId) then
		selectedId = nil
	end
	local placed = 0
	for _, c in ipairs(data.creatures) do
		if c.slot then
			placed += 1
		end
	end
	countLabel.Text = string.format("Owned %d/%d  ·  Pads %d/%d", #data.creatures, data.storageCapacity, placed, data.padCount)
	Kit.clear(grid)
	local order = 0
	for _, c in ipairs(ClientState.sortedCreatures()) do
		local show = filter == "All" or (filter == "On Pads" and c.slot ~= nil) or (filter == "Storage" and c.slot == nil)
		if show then
			order += 1
			if not selectedId then
				selectedId = c.id
			end
			card(c, order)
		end
	end
	if order == 0 then
		Kit.label(grid, "Nothing here yet. Capture creatures in the Hub Grove!", { size = UDim2.fromOffset(460, 40), color = C.muted, wrap = true })
	end
	renderDetail()
end

function Inventory.build(root: Instance, panels)
	Panels = panels
	rootGui = root
	panel = Kit.panel(root, "Creatures", function()
		Panels.close()
	end)
	Inventory.frame = panel.frame
	local content = panel.content

	local top = Kit.frame(content, { Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1 })
	local tabs, select = Kit.tabs(top, { "All", "On Pads", "Storage" }, function(name)
		filter = name
		Inventory.refresh()
	end)
	tabs.Size = UDim2.new(0.6, 0, 1, 0)
	countLabel = Kit.label(top, "", { size = UDim2.new(0.4, 0, 1, 0), align = Enum.TextXAlignment.Right, color = C.muted, textSize = Theme.TextSize.small })
	countLabel.Position = UDim2.fromScale(0.6, 0)
	select("All")

	grid = Kit.scroll(content, { size = UDim2.new(0, 484, 1, -48), position = UDim2.fromOffset(0, 48) })
	Kit.grid(grid, Vector2.new(148, 118), 10)

	local side = Kit.frame(content, {
		Size = UDim2.new(1, -496, 1, -48),
		Position = UDim2.fromOffset(496, 48),
		BackgroundColor3 = C.panel2,
	})
	Kit.padding(side, 10)
	detail.empty = Kit.label(side, "Select a creature", { size = UDim2.fromScale(1, 1), align = Enum.TextXAlignment.Center, color = C.muted })
	local holder = Kit.scroll(side, {})
	detail.holder = holder
	Kit.list(holder, false, 4)
	detail.view = CreatureView.new(holder, UDim2.new(1, -8, 0, 110))
	detail.name = Kit.label(holder, "", { textSize = Theme.TextSize.h2, font = Theme.Fonts.title, order = 1 })
	detail.info = Kit.label(holder, "", { size = UDim2.new(1, -8, 0, 0), autoY = true, textSize = Theme.TextSize.tiny, color = C.muted, order = 2, wrap = true })
	detail.income = Kit.label(holder, "", { textSize = Theme.TextSize.tiny, order = 3, wrap = true, size = UDim2.new(1, 0, 0, 30) })
	detail.status = Kit.label(holder, "", { textSize = Theme.TextSize.tiny, order = 4, wrap = true, size = UDim2.new(1, 0, 0, 30), font = Theme.Fonts.bold })
	local function act(text: string, color: Color3, order: number, fn)
		return Kit.button(holder, text, { name = "Action" .. order, size = UDim2.new(1, -8, 0, 34), color = color, textSize = Theme.TextSize.small, order = order, onClick = fn })
	end
	detail.place = act("Place on pad", C.cyan, 5, function()
		local c = selectedId and ClientState.creature(selectedId)
		if c then
			Net.request(if c.slot then "UnplaceCreature" else "PlaceCreature", c.id)
		end
	end)
	detail.levelUp = act("Level up", C.green, 6, function()
		if selectedId then
			Net.request("LevelUpCreature", selectedId)
		end
	end)
	detail.mutate = act("Mutate in Chamber", C.purple, 7, function()
		if selectedId then
			Panels.open("Chamber", { creatureId = selectedId })
		end
	end)
	detail.release = act("Release", C.red, 8, function()
		local c = selectedId and ClientState.creature(selectedId)
		if c then
			Kit.confirm(rootGui, "Release " .. Kit.creatureName(c) .. " forever? You get some DNA back.", function()
				Net.request("ReleaseCreature", c.id)
			end)
		end
	end)
end

function Inventory.onOpen(arg)
	if type(arg) == "string" then
		selectedId = arg
	end
	Inventory.refresh()
end

function Inventory.refresh()
	Kit.preserveSelection(panel.frame, Inventory.render)
end

return Inventory
