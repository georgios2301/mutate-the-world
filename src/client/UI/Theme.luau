-- UI design tokens: one place for colors, fonts and sizes.
local Theme = {}

Theme.Colors = {
	bg = Color3.fromRGB(14, 11, 31),
	panel = Color3.fromRGB(24, 19, 48),
	panel2 = Color3.fromRGB(36, 28, 70),
	panel3 = Color3.fromRGB(50, 40, 92),
	stroke = Color3.fromRGB(120, 88, 220),
	text = Color3.fromRGB(242, 238, 255),
	muted = Color3.fromRGB(165, 155, 205),
	purple = Color3.fromRGB(138, 92, 255),
	cyan = Color3.fromRGB(62, 230, 255),
	green = Color3.fromRGB(124, 255, 79),
	orange = Color3.fromRGB(255, 154, 60),
	red = Color3.fromRGB(255, 80, 100),
	gold = Color3.fromRGB(255, 205, 70),
	disabled = Color3.fromRGB(70, 64, 95),
}

Theme.Fonts = {
	title = Enum.Font.FredokaOne,
	body = Enum.Font.GothamMedium,
	bold = Enum.Font.GothamBold,
}

Theme.TextSize = {
	title = 28,
	h2 = 21,
	body = 18,
	small = 15,
	tiny = 13,
}

Theme.Radius = 12
Theme.PanelSize = Vector2.new(780, 520)

-- Notification kinds -> accent color
Theme.Kinds = {
	info = Theme.Colors.cyan,
	success = Theme.Colors.green,
	warn = Theme.Colors.orange,
	error = Theme.Colors.red,
	rare = Theme.Colors.gold,
	pickup = Color3.fromRGB(255, 120, 200),
}

return Theme
