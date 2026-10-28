-- MUTATE THE WORLD - client entry point. Builds the UI, wires remotes to UI modules.
if not game:IsLoaded() then
	game.Loaded:Wait()
end

local Players = game:GetService("Players")

local Client = script.Parent
local ClientState = require(Client.ClientState)
local Net = require(Client.Net)

local UI = Client.UI
local Sound = require(UI.Sound)
local Scaler = require(UI.Scaler)
local Notifications = require(UI.Notifications)
local PanelManager = require(UI.PanelManager)
local HUD = require(UI.HUD)
local TutorialOverlay = require(UI.Overlays.Tutorial)
local HeistOverlay = require(UI.Overlays.Heist)
local MutationReveal = require(UI.Overlays.MutationReveal)
local Trade = require(UI.Panels.Trade)

local WorldController = require(Client.Controllers.WorldController)
local InputController = require(Client.Controllers.InputController)

local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui"):WaitForChild("MutateUI") :: ScreenGui
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.IgnoreGuiInset = true
gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets

-- Build UI ----------------------------------------------------------------------
Notifications.init(gui)
Net.setNotifier(Notifications.show)
Trade.setNotifier(Notifications.show)

HUD.build(gui, PanelManager)
PanelManager.init(gui)
for _, name in ipairs({ "Inventory", "Chamber", "Collection", "Journal", "Shop", "Travel", "Defense", "Trade", "Settings", "Menu" }) do
	PanelManager.register(name, require(UI.Panels[name]))
end
TutorialOverlay.build(gui, PanelManager)
HeistOverlay.build(gui)
MutationReveal.build(gui)

WorldController.init(PanelManager)
InputController.init(PanelManager, function()
	if MutationReveal.isOpen() then
		MutationReveal.hide()
		return true
	end
	return false
end)

-- Responsive scale --------------------------------------------------------------
local camera = workspace.CurrentCamera
local function updateScale()
	local data = ClientState.data
	local userScale = if data then data.settings.uiScale or 1 else 1
	Scaler.set(Scaler.forViewport(camera.ViewportSize, userScale))
end
camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
updateScale()

-- State -------------------------------------------------------------------------
local lastSettings = nil
ClientState.changed:Connect(function(kind)
	local data = ClientState.data
	HUD.refresh()
	if kind == "full" then
		PanelManager.refresh()
		TutorialOverlay.refresh()
		local settingsKey = tostring(data.settings.sfx) .. tostring(data.settings.popups) .. tostring(data.settings.uiScale)
		if settingsKey ~= lastSettings then
			lastSettings = settingsKey
			Sound.setEnabled(data.settings.sfx ~= false)
			Notifications.setPopups(data.settings.popups ~= false)
			updateScale()
		end
	end
end)

Net.event("StateUpdate").OnClientEvent:Connect(function(kind, payload)
	ClientState.apply(kind, payload)
end)

Net.event("Notify").OnClientEvent:Connect(function(payload)
	if type(payload) == "table" and type(payload.text) == "string" then
		Notifications.show(payload.text, payload.kind)
	end
end)

Net.event("Announcement").OnClientEvent:Connect(function(payload)
	if type(payload) == "table" and type(payload.text) == "string" then
		Notifications.announce(payload.text, payload.rarity)
	end
end)

Net.event("HeistEvent").OnClientEvent:Connect(function(kind, data)
	HeistOverlay.onEvent(kind, data or {})
end)

Net.event("TradeEvent").OnClientEvent:Connect(function(kind, data)
	Trade.onEvent(kind, data or {})
end)

Net.event("MutationEvent").OnClientEvent:Connect(function(kind, data)
	if kind == "completed" then
		MutationReveal.show(data)
	elseif kind == "started" then
		Sound.play("Mutate")
	end
end)

-- Live timers (mutation countdown in the HUD) without waiting for server pushes.
task.spawn(function()
	while true do
		task.wait(1)
		if ClientState.data then
			HUD.refresh()
		end
	end
end)

-- Initial state: the server pushes it when ready; poll as a fallback.
task.spawn(function()
	for _ = 1, 30 do
		if ClientState.ready() then
			return
		end
		local result = Net.silent("GetState")
		if result.ok and result.data then
			ClientState.apply("full", result.data)
			return
		end
		task.wait(2)
	end
	Notifications.show("Still loading your island... if this persists, rejoin.", "warn")
end)
