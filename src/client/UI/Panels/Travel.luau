-- Travel & biome selection: hub, home, biomes (unlock + travel) and other players' islands.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Biomes = require(Shared.Config.Biomes)
local Creatures = require(Shared.Config.Creatures)
local Rules = require(Shared.Rules)
local Format = require(Shared.Util.Format)

local Client = script.Parent.Parent.Parent
local ClientState = require(Client.ClientState)
local Net = require(Client.Net)

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Kit = require(UI.Kit)

local Travel = {}
local C = Theme.Colors

local panel
local list: ScrollingFrame
local islands = {}
local Panels

local function go(destination: string)
	local result = Net.request("Travel", destination)
	if result.ok then
		Panels.close()
	end
end

local function wildText(spawns): string
	local total = 0
	for _, s in ipairs(spawns) do
		total += s.weight
	end
	local parts = {}
	for _, s in ipairs(spawns) do
		table.insert(parts, string.format("%s %d%%", Creatures.Species[s.species].name, math.floor(s.weight / total * 100 + 0.5)))
	end
	return table.concat(parts, ", ")
end

local function biomeRow(id: string, order: number)
	local data = ClientState.data
	local def = Biomes.Defs[id]
	local status = Rules.biomeStatus(data, id)
	local frame = Kit.frame(list, { Size = UDim2.new(1, -8, 0, 96), BackgroundColor3 = C.panel2, LayoutOrder = order })
	Kit.stroke(frame, def.color, 1.5, if status.unlocked then 0.1 else 0.6)
	Kit.padding(frame, 12, 8)
	Kit.label(frame, def.name .. (if status.unlocked then "" else "  🔒"), {
		size = UDim2.new(1, -170, 0, 24),
		font = Theme.Fonts.title,
		textSize = Theme.TextSize.h2,
		color = def.color,
	})
	local desc = Kit.label(frame, def.description .. "\nCreatures: " .. wildText(def.wild), {
		size = UDim2.new(1, -170, 0, 34),
		textSize = Theme.TextSize.tiny,
		wrap = true,
		color = C.text,
		alignY = Enum.TextYAlignment.Top,
	})
	desc.Position = UDim2.fromOffset(0, 26)
	if not status.unlocked then
		local checks = {}
		for _, check in ipairs(status.checks) do
			table.insert(checks, (if check.met then "<font color='#7cff4f'>✔</font> " else "<font color='#ff6b6b'>✖</font> ") .. check.text)
		end
		local req = Kit.label(frame, table.concat(checks, "   "), { size = UDim2.new(1, -170, 0, 18), textSize = Theme.TextSize.tiny })
		req.Position = UDim2.fromOffset(0, 62)
	end
	local button
	if status.unlocked then
		button = Kit.button(frame, "Travel", {
			size = UDim2.fromOffset(150, 44),
			color = def.color,
			textColor = C.bg,
			onClick = function()
				go("biome:" .. id)
			end,
		})
	else
		local price = status.cost.coins or 0
		button = Kit.button(frame, "Unlock · ● " .. Format.number(price), {
			size = UDim2.fromOffset(150, 44),
			color = C.gold,
			textColor = C.bg,
			textSize = Theme.TextSize.small,
			onClick = function()
				Net.request("UnlockBiome", id)
			end,
		})
		Kit.setEnabled(button, status.canUnlock)
	end
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Position = UDim2.fromScale(1, 0.5)
end

function Travel.refresh()
	if not ClientState.data or not panel.frame.Visible then
		return
	end
	Kit.clear(list)
	local quick = Kit.frame(list, { Size = UDim2.new(1, -8, 0, 54), BackgroundTransparency = 1, LayoutOrder = 0 })
	Kit.list(quick, true, 10)
	Kit.button(quick, "⇄  Central Hub", { size = UDim2.fromOffset(240, 50), color = C.cyan, textColor = C.bg, onClick = function()
		go("hub")
	end })
	Kit.button(quick, "🏠  My Island", { size = UDim2.fromOffset(240, 50), color = C.purple, order = 1, onClick = function()
		go("island")
	end })
	for i, id in ipairs(Biomes.Order) do
		biomeRow(id, i)
	end
	Kit.label(list, "Other islands", { size = UDim2.new(1, -8, 0, 30), font = Theme.Fonts.title, textSize = Theme.TextSize.h2, color = C.cyan, order = 10 })
	if #islands == 0 then
		Kit.label(list, "No other players on this server right now.", { size = UDim2.new(1, -8, 0, 24), color = C.muted, order = 11, textSize = Theme.TextSize.small })
	end
	for i, info in ipairs(islands) do
		local frame = Kit.frame(list, { Size = UDim2.new(1, -8, 0, 52), BackgroundColor3 = C.panel2, LayoutOrder = 10 + i })
		Kit.padding(frame, 12, 6)
		local tags = {}
		if info.shielded then
			table.insert(tags, "🛡 Shield up")
		end
		if info.protected then
			table.insert(tags, "🔰 Protected")
		end
		Kit.label(frame, string.format("<b>%s</b>  ·  Lv %d   <font color='#a59bcd'>%s</font>", info.name, info.level, table.concat(tags, "  ")), {
			size = UDim2.new(1, -140, 1, 0),
			textSize = Theme.TextSize.small,
		})
		local visit = Kit.button(frame, "Visit", { size = UDim2.fromOffset(120, 38), color = C.orange, textColor = C.bg, onClick = function()
			go("visit:" .. info.index)
		end })
		visit.AnchorPoint = Vector2.new(1, 0.5)
		visit.Position = UDim2.fromScale(1, 0.5)
	end
end

function Travel.build(root: Instance, panels)
	Panels = panels
	panel = Kit.panel(root, "Travel", function()
		Panels.close()
	end)
	Travel.frame = panel.frame
	list = Kit.scroll(panel.content, {})
	Kit.list(list, false, 8)
end

function Travel.onOpen()
	Travel.refresh()
	task.spawn(function()
		local result = Net.silent("ListIslands")
		if result.ok and type(result.data) == "table" then
			islands = result.data
			Travel.refresh()
		end
	end)
end

return Travel
