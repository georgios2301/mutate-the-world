-- Settings: sound, popups, reduced effects, UI size, tutorial replay/skip. Saved server-side.
local Client = script.Parent.Parent.Parent
local ClientState = require(Client.ClientState)
local Net = require(Client.Net)

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Kit = require(UI.Kit)

local Settings = {}
local C = Theme.Colors

local panel
local toggles = {}
local scaleLabel: TextLabel
local saveLabel: TextLabel
local tutorialSkip: TextButton

local OPTIONS = {
	{ key = "sfx", title = "Sound effects", desc = "Clicks, pickups, alarms and discovery chimes." },
	{ key = "popups", title = "Info popups", desc = "Small notifications. Warnings and heist alerts always show." },
	{ key = "reducedEffects", title = "Reduced effects", desc = "Turns off particles for smoother play on older devices." },
}

function Settings.refresh()
	local data = ClientState.data
	if not data or not panel.frame.Visible then
		return
	end
	for key, button in pairs(toggles) do
		local on = data.settings[key] == true
		Kit.setText(button, if on then "ON" else "OFF")
		button:SetAttribute("BaseColor", if on then C.green else C.panel3)
		button.BackgroundColor3 = if on then C.green else C.panel3
	end
	scaleLabel.Text = string.format("UI size: %d%%", math.floor((data.settings.uiScale or 1) * 100 + 0.5))
	saveLabel.Text = if data.persistent
		then "<font color='#7cff4f'>✔ Progress saves automatically.</font>"
		else "<font color='#ff9a3c'>⚠ Saving is off on this server (DataStores unavailable). Progress is session-only.</font>"
	Kit.setEnabled(tutorialSkip, not data.tutorial.done)
end

function Settings.build(root: Instance, Panels)
	panel = Kit.panel(root, "Settings", function()
		Panels.close()
	end)
	Settings.frame = panel.frame
	local list = Kit.scroll(panel.content, {})
	Kit.list(list, false, 8)

	for i, option in ipairs(OPTIONS) do
		local row = Kit.frame(list, { Size = UDim2.new(1, -8, 0, 60), BackgroundColor3 = C.panel2, LayoutOrder = i })
		Kit.padding(row, 12, 6)
		Kit.label(row, option.title, { size = UDim2.new(1, -120, 0, 24), font = Theme.Fonts.bold })
		local d = Kit.label(row, option.desc, { size = UDim2.new(1, -120, 0, 22), textSize = Theme.TextSize.tiny, color = C.muted, wrap = true })
		d.Position = UDim2.fromOffset(0, 24)
		local button = Kit.button(row, "ON", {
			size = UDim2.fromOffset(100, 40),
			color = C.green,
			onClick = function()
				local data = ClientState.data
				if data then
					Net.silent("SetSetting", option.key, not data.settings[option.key])
				end
			end,
		})
		button.AnchorPoint = Vector2.new(1, 0.5)
		button.Position = UDim2.fromScale(1, 0.5)
		toggles[option.key] = button
	end

	local scaleRow = Kit.frame(list, { Size = UDim2.new(1, -8, 0, 56), BackgroundColor3 = C.panel2, LayoutOrder = 10 })
	Kit.padding(scaleRow, 12, 6)
	scaleLabel = Kit.label(scaleRow, "UI size", { size = UDim2.new(1, -240, 1, 0), font = Theme.Fonts.bold })
	local holder = Kit.frame(scaleRow, { Size = UDim2.fromOffset(220, 40), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(1, 0.5), BackgroundTransparency = 1 })
	Kit.list(holder, true, 10, Enum.HorizontalAlignment.Right)
	local function changeScale(delta: number)
		local data = ClientState.data
		if data then
			local value = math.clamp(math.floor(((data.settings.uiScale or 1) + delta) * 10 + 0.5) / 10, 0.7, 1.6)
			Net.silent("SetSetting", "uiScale", value)
		end
	end
	Kit.button(holder, "−", { size = UDim2.fromOffset(100, 40), color = C.panel3, textSize = 24, onClick = function()
		changeScale(-0.1)
	end })
	Kit.button(holder, "+", { size = UDim2.fromOffset(100, 40), color = C.panel3, textSize = 24, order = 1, onClick = function()
		changeScale(0.1)
	end })

	local tutorialRow = Kit.frame(list, { Size = UDim2.new(1, -8, 0, 56), BackgroundColor3 = C.panel2, LayoutOrder = 11 })
	Kit.padding(tutorialRow, 12, 6)
	Kit.label(tutorialRow, "Tutorial", { size = UDim2.new(1, -240, 1, 0), font = Theme.Fonts.bold })
	local tHolder = Kit.frame(tutorialRow, { Size = UDim2.fromOffset(220, 40), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(1, 0.5), BackgroundTransparency = 1 })
	Kit.list(tHolder, true, 10, Enum.HorizontalAlignment.Right)
	Kit.button(tHolder, "Replay", { size = UDim2.fromOffset(100, 40), color = C.cyan, textColor = C.bg, onClick = function()
		Net.request("TutorialAction", "restart")
		Panels.close()
	end })
	tutorialSkip = Kit.button(tHolder, "Skip", { size = UDim2.fromOffset(100, 40), color = C.orange, textColor = C.bg, order = 1, onClick = function()
		Net.request("TutorialAction", "skip")
	end })

	saveLabel = Kit.label(list, "", { size = UDim2.new(1, -8, 0, 40), wrap = true, textSize = Theme.TextSize.small, order = 20 })
	Kit.label(list, "Controls: E interact · F steal · B creatures · C chamber · U shop · T travel · G security · K index · J journal · Y trade · M menu · Backspace close. Gamepad: Y menu, B close.", {
		size = UDim2.new(1, -8, 0, 54),
		wrap = true,
		textSize = Theme.TextSize.tiny,
		color = C.muted,
		order = 21,
	})
end

function Settings.onOpen()
	Settings.refresh()
end

return Settings
