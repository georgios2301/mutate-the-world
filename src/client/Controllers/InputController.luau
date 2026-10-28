-- Keyboard and gamepad shortcuts for the main panels.
local UserInputService = game:GetService("UserInputService")

local InputController = {}

local KEYS = {
	[Enum.KeyCode.B] = "Inventory",
	[Enum.KeyCode.C] = "Chamber",
	[Enum.KeyCode.U] = "Shop",
	[Enum.KeyCode.T] = "Travel",
	[Enum.KeyCode.G] = "Defense",
	[Enum.KeyCode.K] = "Collection",
	[Enum.KeyCode.J] = "Journal",
	[Enum.KeyCode.Y] = "Trade",
	[Enum.KeyCode.M] = "Menu",
}

-- onBack: optional function that closes a modal and returns true if it handled the press.
function InputController.init(Panels, onBack: (() -> boolean)?)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or UserInputService:GetFocusedTextBox() then
			return
		end
		local key = input.KeyCode
		if key == Enum.KeyCode.Backspace or key == Enum.KeyCode.ButtonB then
			if onBack and onBack() then
				return
			end
			if Panels.isOpen() then
				Panels.close()
			end
			return
		end
		if key == Enum.KeyCode.ButtonY then
			Panels.toggle("Menu")
			return
		end
		local panel = KEYS[key]
		if panel then
			Panels.toggle(panel)
		end
	end)
end

return InputController
