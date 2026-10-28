-- Pause / "More" menu: big buttons for every screen (mobile-friendly hub of the UI).
local Client = script.Parent.Parent.Parent
local Net = require(Client.Net)

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Kit = require(UI.Kit)

local Menu = {}
local C = Theme.Colors

local ITEMS = {
	{ "🎒", "Creatures", "Inventory", C.purple },
	{ "🧪", "Chamber", "Chamber", C.green },
	{ "📜", "Journal", "Journal", C.cyan },
	{ "📖", "Index", "Collection", C.orange },
	{ "🛒", "Shop", "Shop", C.gold },
	{ "🎁", "Rewards", "Shop:rewards", C.gold },
	{ "🌍", "Travel", "Travel", C.cyan },
	{ "🛡️", "Security", "Defense", C.red },
	{ "🤝", "Trade", "Trade", C.green },
	{ "💎", "Store", "Shop:store", C.purple },
	{ "⚙️", "Settings", "Settings", C.panel3 },
	{ "🏠", "Go Home", "@island", C.purple },
}

function Menu.build(root: Instance, Panels)
	local panel = Kit.panel(root, "Menu", function()
		Panels.close()
	end)
	Menu.frame = panel.frame
	local grid = Kit.frame(panel.content, { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 })
	Kit.grid(grid, Vector2.new(172, 100), 12)
	for i, item in ipairs(ITEMS) do
		local b = Kit.button(grid, "", {
			color = item[4],
			order = i,
			radius = 16,
			onClick = function()
				local target = item[3]
				if target == "@island" then
					Panels.close()
					Net.request("Travel", "island")
					return
				end
				local name, arg = string.match(target, "^(%w+):(%w+)$")
				if name then
					Panels.open(name, arg)
				else
					Panels.open(target)
				end
			end,
		})
		local icon = Kit.label(b, item[1], { size = UDim2.new(1, 0, 0, 48), textSize = 34, align = Enum.TextXAlignment.Center })
		icon.Position = UDim2.fromOffset(0, 10)
		local label = Kit.label(b, item[2], { size = UDim2.new(1, 0, 0, 26), textSize = Theme.TextSize.body, font = Theme.Fonts.title, align = Enum.TextXAlignment.Center })
		label.Position = UDim2.new(0, 0, 1, -34)
	end
end

return Menu
