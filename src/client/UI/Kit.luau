-- UI component kit: every panel is built from these so the look stays consistent.
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local Creatures = require(Shared.Config.Creatures)
local Mutations = require(Shared.Config.Mutations)
local Rarity = require(Shared.Config.Rarity)

local Theme = require(script.Parent.Theme)
local Sound = require(script.Parent.Sound)

local Kit = {}
local C = Theme.Colors

function Kit.new(className: string, props, children)
	local inst = Instance.new(className)
	for k, v in pairs(props or {}) do
		if k ~= "Parent" then
			(inst :: any)[k] = v
		end
	end
	for _, child in ipairs(children or {}) do
		child.Parent = inst
	end
	if props and props.Parent then
		inst.Parent = props.Parent
	end
	return inst
end

function Kit.tween(obj: Instance, props, time: number?, style: Enum.EasingStyle?)
	local t = TweenService:Create(obj, TweenInfo.new(time or 0.15, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

function Kit.corner(parent: Instance, radius: number?)
	return Kit.new("UICorner", { CornerRadius = UDim.new(0, radius or Theme.Radius), Parent = parent })
end

function Kit.stroke(parent: Instance, color: Color3?, thickness: number?, transparency: number?)
	return Kit.new("UIStroke", {
		Color = color or C.stroke,
		Thickness = thickness or 1.5,
		Transparency = transparency or 0.2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

function Kit.padding(parent: Instance, px: number, py: number?)
	return Kit.new("UIPadding", {
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
		PaddingTop = UDim.new(0, py or px),
		PaddingBottom = UDim.new(0, py or px),
		Parent = parent,
	})
end

function Kit.list(parent: Instance, horizontal: boolean?, gap: number?, align: Enum.HorizontalAlignment?)
	return Kit.new("UIListLayout", {
		FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical,
		Padding = UDim.new(0, gap or 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = align or Enum.HorizontalAlignment.Left,
		VerticalAlignment = if horizontal then Enum.VerticalAlignment.Center else Enum.VerticalAlignment.Top,
		Parent = parent,
	})
end

function Kit.grid(parent: Instance, cell: Vector2, gap: number?)
	return Kit.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(cell.X, cell.Y),
		CellPadding = UDim2.fromOffset(gap or 10, gap or 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = parent,
	})
end

-- opts: size (UDim2), textSize, color, font, align, wrap, rich, order, autoY
function Kit.label(parent: Instance, text: string, opts)
	opts = opts or {}
	local label = Kit.new("TextLabel", {
		Name = opts.name or "Label",
		Size = opts.size or UDim2.new(1, 0, 0, (opts.textSize or Theme.TextSize.body) + 8),
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = opts.color or C.text,
		TextSize = opts.textSize or Theme.TextSize.body,
		Font = opts.font or Theme.Fonts.body,
		TextXAlignment = opts.align or Enum.TextXAlignment.Left,
		TextYAlignment = opts.alignY or Enum.TextYAlignment.Center,
		TextWrapped = opts.wrap == true,
		RichText = opts.rich ~= false,
		LayoutOrder = opts.order or 0,
		AutomaticSize = if opts.autoY then Enum.AutomaticSize.Y else Enum.AutomaticSize.None,
		Parent = parent,
	})
	return label
end

-- props: Frame properties plus `radius` (corner radius in px)
function Kit.frame(parent: Instance, props)
	props = props or {}
	local radius = props.radius
	props.radius = nil
	props.BackgroundColor3 = props.BackgroundColor3 or C.panel2
	props.BorderSizePixel = 0
	props.Parent = parent
	local f = Kit.new("Frame", props)
	if props.BackgroundTransparency ~= 1 then
		Kit.corner(f, radius)
	end
	return f
end

local function darken(c: Color3, a: number): Color3
	return c:Lerp(Color3.new(0, 0, 0), a)
end

function Kit.setEnabled(button: GuiButton, enabled: boolean)
	button:SetAttribute("Disabled", not enabled)
	local base = button:GetAttribute("BaseColor") :: Color3?
	button.BackgroundColor3 = if enabled then (base or C.purple) else C.disabled
	button.AutoButtonColor = false
	local label = button:FindFirstChild("Text") :: TextLabel?
	if label then
		label.TextTransparency = if enabled then 0 else 0.35
	end
end

-- opts: color, size (UDim2), textSize, order, onClick, textColor, font
function Kit.button(parent: Instance, text: string, opts)
	opts = opts or {}
	local color = opts.color or C.purple
	local button = Kit.new("TextButton", {
		Name = opts.name or "Button",
		Size = opts.size or UDim2.fromOffset(140, 40),
		BackgroundColor3 = color,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = opts.order or 0,
		Selectable = true,
		Parent = parent,
	})
	button:SetAttribute("BaseColor", color)
	Kit.corner(button, opts.radius or 10)
	Kit.new("UIGradient", {
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(200, 200, 215)),
		Rotation = 90,
		Parent = button,
	})
	Kit.label(button, text, {
		name = "Text",
		size = UDim2.fromScale(1, 1),
		textSize = opts.textSize or Theme.TextSize.body,
		font = opts.font or Theme.Fonts.bold,
		align = Enum.TextXAlignment.Center,
		color = opts.textColor or Color3.new(1, 1, 1),
		wrap = true,
	})
	local scale = Kit.new("UIScale", { Parent = button })
	-- BaseColor can change later (tabs, toggles), so read it on every hover.
	local function baseColor(): Color3
		return (button:GetAttribute("BaseColor") :: Color3?) or color
	end
	button.MouseEnter:Connect(function()
		if not button:GetAttribute("Disabled") then
			Kit.tween(button, { BackgroundColor3 = baseColor():Lerp(Color3.new(1, 1, 1), 0.15) }, 0.1)
		end
	end)
	button.MouseLeave:Connect(function()
		if not button:GetAttribute("Disabled") then
			Kit.tween(button, { BackgroundColor3 = baseColor() }, 0.1)
		end
	end)
	button.MouseButton1Down:Connect(function()
		Kit.tween(scale, { Scale = 0.94 }, 0.06)
	end)
	button.MouseButton1Up:Connect(function()
		Kit.tween(scale, { Scale = 1 }, 0.08)
	end)
	button.Activated:Connect(function()
		Kit.tween(scale, { Scale = 1 }, 0.08)
		if button:GetAttribute("Disabled") then
			Sound.play("Error")
			if opts.onDisabled then
				opts.onDisabled()
			end
			return
		end
		Sound.play("Click")
		if opts.onClick then
			opts.onClick()
		end
	end)
	return button
end

function Kit.setText(button: GuiButton, text: string)
	local label = button:FindFirstChild("Text") :: TextLabel?
	if label then
		label.Text = text
	end
end

function Kit.scroll(parent: Instance, props)
	props = props or {}
	local scroll = Kit.new("ScrollingFrame", {
		Name = props.name or "Scroll",
		Size = props.size or UDim2.fromScale(1, 1),
		Position = props.position or UDim2.new(),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = C.stroke,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = props.horizontal and Enum.AutomaticSize.X or Enum.AutomaticSize.Y,
		ScrollingDirection = props.horizontal and Enum.ScrollingDirection.X or Enum.ScrollingDirection.Y,
		LayoutOrder = props.order or 0,
		Parent = parent,
	})
	Kit.padding(scroll, 4, 4)
	return scroll
end

-- Progress bar: returns container and a setter(fraction, text?)
function Kit.bar(parent: Instance, color: Color3?, size: UDim2?)
	local back = Kit.frame(parent, { Name = "Bar", Size = size or UDim2.new(1, 0, 0, 14), BackgroundColor3 = C.bg, radius = 7 })
	local fill = Kit.frame(back, { Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundColor3 = color or C.cyan, radius = 7 })
	local text = Kit.label(back, "", {
		size = UDim2.fromScale(1, 1),
		textSize = Theme.TextSize.tiny,
		font = Theme.Fonts.bold,
		align = Enum.TextXAlignment.Center,
	})
	local function set(fraction: number, label: string?)
		fill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
		text.Text = label or ""
	end
	return back, set
end

function Kit.clear(container: Instance)
	for _, child in ipairs(container:GetChildren()) do
		if not child:IsA("UIComponent") and not child:IsA("UILayout") then
			child:Destroy()
		end
	end
end

-- Tab strip. Returns frame and select(name).
function Kit.tabs(parent: Instance, names: { string }, onSelect: (string) -> ())
	local strip = Kit.frame(parent, { Name = "Tabs", Size = UDim2.new(1, 0, 0, 38), BackgroundTransparency = 1 })
	Kit.list(strip, true, 8)
	local buttons = {}
	local function select(name: string)
		for n, b in pairs(buttons) do
			local active = n == name
			b:SetAttribute("BaseColor", if active then C.purple else C.panel3)
			b.BackgroundColor3 = if active then C.purple else C.panel3
		end
		onSelect(name)
	end
	for i, name in ipairs(names) do
		buttons[name] = Kit.button(strip, name, {
			size = UDim2.fromOffset(math.max(110, #name * 11 + 30), 34),
			color = C.panel3,
			order = i,
			textSize = Theme.TextSize.small,
			onClick = function()
				select(name)
			end,
		})
	end
	return strip, select
end

-- Standard centered panel with header + close button. Returns { frame, content, title }.
function Kit.panel(parent: Instance, title: string, onClose: () -> ())
	local size = Theme.PanelSize
	local frame = Kit.frame(parent, {
		Name = "Panel_" .. title,
		Size = UDim2.fromOffset(size.X, size.Y),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		BackgroundColor3 = C.panel,
		Visible = false,
		radius = 18,
	})
	Kit.stroke(frame, C.stroke, 2, 0.1)
	Kit.new("UIGradient", {
		Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(190, 180, 230)),
		Rotation = 90,
		Parent = frame,
	})
	local header = Kit.frame(frame, { Name = "Header", Size = UDim2.new(1, 0, 0, 54), BackgroundTransparency = 1 })
	local titleLabel = Kit.label(header, title, {
		size = UDim2.new(1, -80, 1, 0),
		textSize = Theme.TextSize.title,
		font = Theme.Fonts.title,
	})
	titleLabel.Position = UDim2.fromOffset(20, 0)
	local close = Kit.button(header, "✕", {
		size = UDim2.fromOffset(40, 40),
		color = C.red,
		textSize = 20,
		onClick = onClose,
	})
	close.AnchorPoint = Vector2.new(1, 0.5)
	close.Position = UDim2.new(1, -10, 0.5, 0)
	local content = Kit.frame(frame, {
		Name = "Content",
		Size = UDim2.new(1, -32, 1, -70),
		Position = UDim2.fromOffset(16, 58),
		BackgroundTransparency = 1,
	})
	return { frame = frame, content = content, title = titleLabel, close = close }
end

-- Circular creature badge: species color + initial + rarity ring. Cheap enough for big lists.
function Kit.creatureIcon(parent: Instance, creature, size: number)
	local species = Creatures.Species[creature.species]
	local mutation = Mutations.Types[creature.mutation or "none"]
	local color = species.look.primary
	if mutation and mutation.color then
		color = color:Lerp(mutation.color, 0.55)
	end
	local icon = Kit.frame(parent, {
		Name = "Icon",
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = color,
		radius = size,
	})
	Kit.stroke(icon, Rarity.color(species.rarity), 3, 0)
	Kit.label(icon, string.sub(species.name, 1, 1), {
		size = UDim2.fromScale(1, 1),
		textSize = math.floor(size * 0.5),
		font = Theme.Fonts.title,
		align = Enum.TextXAlignment.Center,
		color = Color3.new(1, 1, 1),
	})
	if mutation and mutation.id ~= "none" then
		local dot = Kit.frame(icon, {
			Size = UDim2.fromOffset(size * 0.36, size * 0.36),
			Position = UDim2.new(1, -size * 0.3, 1, -size * 0.3),
			BackgroundColor3 = mutation.color,
			radius = size,
		})
		Kit.stroke(dot, C.bg, 2, 0)
	end
	return icon
end

function Kit.creatureName(creature): string
	local species = Creatures.Species[creature.species]
	return Mutations.displayName(species.name, creature.mutation or "none")
end

function Kit.rarityHex(speciesId: string): string
	return Rarity.color(Creatures.Species[speciesId].rarity):ToHex()
end

-- Modal yes/no dialog.
function Kit.confirm(root: Instance, text: string, onYes: () -> ())
	local blocker = Kit.new("TextButton", {
		Name = "Confirm",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 50,
		Parent = root,
	})
	local box = Kit.frame(blocker, {
		Size = UDim2.fromOffset(420, 190),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = C.panel,
		ZIndex = 51,
		radius = 16,
	})
	Kit.stroke(box, C.orange, 2, 0)
	Kit.padding(box, 18)
	if Kit.scaleHook then
		Kit.scaleHook(box)
	end
	local label = Kit.label(box, text, { size = UDim2.new(1, 0, 0, 90), wrap = true, align = Enum.TextXAlignment.Center })
	label.ZIndex = 52
	local row = Kit.frame(box, { Size = UDim2.new(1, 0, 0, 44), Position = UDim2.new(0, 0, 1, -44), BackgroundTransparency = 1, ZIndex = 52 })
	Kit.list(row, true, 16, Enum.HorizontalAlignment.Center)
	local yes = Kit.button(row, "Yes", {
		color = C.green,
		textColor = C.bg,
		onClick = function()
			blocker:Destroy()
			onYes()
		end,
	})
	local no = Kit.button(row, "Cancel", {
		color = C.panel3,
		onClick = function()
			blocker:Destroy()
		end,
	})
	for _, b in ipairs({ yes, no }) do
		b.ZIndex = 53
		for _, d in ipairs(b:GetDescendants()) do
			if d:IsA("GuiObject") then
				d.ZIndex = 54
			end
		end
	end
	Kit.focus(yes)
	return blocker
end

-- Rebuilds a container without dropping gamepad selection: re-selects the element with the
-- same Name afterwards (list rows/cards are named by id), else the first button.
function Kit.preserveSelection(container: Instance, rebuild: () -> ())
	local selected = GuiService.SelectedObject
	local name = if selected and selected:IsDescendantOf(container) then selected.Name else nil
	rebuild()
	if name then
		local match = container:FindFirstChild(name, true)
		if match and match:IsA("GuiObject") and match.Selectable and match.Visible then
			GuiService.SelectedObject = match
		else
			GuiService.SelectedObject = container:FindFirstChildWhichIsA("GuiButton", true)
		end
	end
end

-- True only if the object and every GuiObject ancestor are Visible.
function Kit.isShown(object: Instance): boolean
	local current: Instance? = object
	while current and current:IsA("GuiObject") do
		if not current.Visible then
			return false
		end
		current = current.Parent
	end
	return current ~= nil
end

-- Gamepad support: move selection into a newly opened UI.
function Kit.focus(object: GuiObject?)
	if object and UserInputService.GamepadEnabled and UserInputService:GetLastInputType().Name:find("Gamepad") then
		GuiService.SelectedObject = object
	end
end

Kit.darken = darken
Kit.scaleHook = nil :: ((GuiObject) -> any)?

return Kit
