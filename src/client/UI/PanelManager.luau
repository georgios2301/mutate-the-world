-- Opens/closes the main panels (only one at a time) and refreshes the open one on state changes.
-- Panel module contract: build(root, Panels) sets M.frame; optional onOpen(arg), onClose(), refresh().
local Kit = require(script.Parent.Kit)
local Sound = require(script.Parent.Sound)
local Scaler = require(script.Parent.Scaler)

local PanelManager = {}

local panels = {}
local current: string? = nil
local root: Instance
local openedEvent = Instance.new("BindableEvent")
PanelManager.opened = openedEvent.Event -- (name)
local changedEvent = Instance.new("BindableEvent")
PanelManager.changed = changedEvent.Event -- fires on any open/close

function PanelManager.init(rootGui: Instance)
	root = rootGui
end

function PanelManager.register(name: string, module)
	module.build(root, PanelManager)
	module.popScale = Scaler.attach(module.frame)
	panels[name] = module
end

function PanelManager.get(name: string)
	return panels[name]
end

function PanelManager.close()
	if not current then
		return
	end
	local panel = panels[current]
	current = nil
	panel.frame.Visible = false
	if panel.onClose then
		panel.onClose()
	end
	changedEvent:Fire()
end

function PanelManager.open(name: string, arg)
	local panel = panels[name]
	if not panel then
		return
	end
	if current and current ~= name then
		PanelManager.close()
	end
	local wasOpen = current == name
	current = name
	panel.frame.Visible = true
	if not wasOpen then
		Scaler.pop(panel.popScale, 0.9)
		Sound.play("Open")
	end
	if panel.onOpen then
		panel.onOpen(arg)
	end
	Kit.focus(panel.frame:FindFirstChildWhichIsA("GuiButton", true))
	openedEvent:Fire(name)
	changedEvent:Fire()
end

function PanelManager.toggle(name: string, arg)
	if current == name then
		PanelManager.close()
	else
		PanelManager.open(name, arg)
	end
end

function PanelManager.isOpen(name: string?): boolean
	if name then
		return current == name
	end
	return current ~= nil
end

function PanelManager.refresh()
	if current then
		local panel = panels[current]
		if panel.refresh then
			panel.refresh()
		end
	end
end

return PanelManager
