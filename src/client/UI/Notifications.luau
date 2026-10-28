-- Toast notifications (right side), pickup popups (bottom) and rare-discovery banners (top).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rarity = require(ReplicatedStorage.Shared.Config.Rarity)

local Theme = require(script.Parent.Theme)
local Kit = require(script.Parent.Kit)
local Sound = require(script.Parent.Sound)
local Scaler = require(script.Parent.Scaler)

local Notifications = {}
local C = Theme.Colors

local stack: Frame
local pickupLayer: Frame
local bannerLayer: Frame
local counter = 0
local popupsEnabled = true
local MAX_TOASTS = 5

function Notifications.setPopups(enabled: boolean)
	popupsEnabled = enabled
end

function Notifications.init(root: Instance)
	stack = Kit.frame(root, {
		Name = "Toasts",
		Size = UDim2.fromOffset(340, 420),
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -14, 1, -150),
		BackgroundTransparency = 1,
	})
	local layout = Kit.list(stack, false, 8, Enum.HorizontalAlignment.Right)
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom

	pickupLayer = Kit.frame(root, {
		Name = "Pickups",
		Size = UDim2.fromOffset(300, 160),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -240),
		BackgroundTransparency = 1,
	})

	bannerLayer = Kit.frame(root, {
		Name = "Banners",
		Size = UDim2.fromOffset(640, 80),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 138),
		BackgroundTransparency = 1,
	})
	for _, block in ipairs({ stack, pickupLayer, bannerLayer }) do
		Scaler.attach(block)
	end
end

local function pickup(text: string)
	local label = Kit.label(pickupLayer, text, {
		size = UDim2.new(1, 0, 0, 30),
		textSize = 22,
		font = Theme.Fonts.title,
		color = Theme.Kinds.pickup,
		align = Enum.TextXAlignment.Center,
	})
	label.Position = UDim2.new(0, 0, 1, -30)
	Kit.new("UIStroke", { Color = C.bg, Thickness = 2, Parent = label })
	Kit.tween(label, { Position = UDim2.new(0, 0, 0, 0), TextTransparency = 1 }, 1.4, Enum.EasingStyle.Sine)
	task.delay(1.5, function()
		label:Destroy()
	end)
	Sound.play("Collect")
end

-- kind: info | success | warn | error | rare | pickup
function Notifications.show(text: string, kind: string?)
	kind = kind or "info"
	if kind == "pickup" then
		pickup(text)
		return
	end
	local important = kind == "error" or kind == "warn" or kind == "rare"
	if not popupsEnabled and not important then
		return
	end
	counter += 1
	local accent = Theme.Kinds[kind :: string] or C.cyan
	local toast = Kit.frame(stack, {
		Name = "Toast",
		Size = UDim2.fromOffset(330, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.05,
		LayoutOrder = counter, -- newest at the bottom of the bottom-anchored stack
	})
	Kit.stroke(toast, accent, 1.5, 0.2)
	Kit.padding(toast, 12, 10)
	Kit.frame(toast, { Size = UDim2.new(0, 4, 1, 0), Position = UDim2.fromOffset(-6, 0), BackgroundColor3 = accent, radius = 2 })
	Kit.label(toast, text, {
		size = UDim2.new(1, 0, 0, 0),
		autoY = true,
		wrap = true,
		textSize = Theme.TextSize.small,
	})
	local scale = Kit.new("UIScale", { Scale = 0.8, Parent = toast })
	Kit.tween(scale, { Scale = 1 }, 0.18, Enum.EasingStyle.Back)
	Sound.play(if kind == "error" or kind == "warn" then "Error" else "Notify")

	local toasts = {}
	for _, child in ipairs(stack:GetChildren()) do
		if child:IsA("Frame") then
			table.insert(toasts, child)
		end
	end
	if #toasts > MAX_TOASTS then
		table.sort(toasts, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		toasts[1]:Destroy() -- oldest
	end

	task.delay(if important then 5 else 3.5, function()
		if toast.Parent then
			Kit.tween(scale, { Scale = 0 }, 0.2)
			task.wait(0.22)
			toast:Destroy()
		end
	end)
end

function Notifications.announce(text: string, rarity: string?)
	local color = if rarity then Rarity.color(rarity) else C.gold
	Kit.clear(bannerLayer)
	local banner = Kit.frame(bannerLayer, {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.bg,
		BackgroundTransparency = 0.1,
		radius = 20,
	})
	Kit.stroke(banner, color, 3, 0)
	Kit.new("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, color:Lerp(C.bg, 0.6)),
			ColorSequenceKeypoint.new(0.5, C.bg),
			ColorSequenceKeypoint.new(1, color:Lerp(C.bg, 0.6)),
		}),
		Parent = banner,
	})
	Kit.label(banner, (if rarity then string.upper(rarity) .. "!  " else "") .. text, {
		size = UDim2.fromScale(1, 1),
		textSize = 24,
		font = Theme.Fonts.title,
		color = color,
		align = Enum.TextXAlignment.Center,
		wrap = true,
	})
	local scale = Kit.new("UIScale", { Scale = 0.5, Parent = banner })
	Kit.tween(scale, { Scale = 1 }, 0.3, Enum.EasingStyle.Back)
	Sound.play("Discovery")
	task.delay(4.5, function()
		if banner.Parent then
			Kit.tween(scale, { Scale = 0 }, 0.25)
			task.wait(0.3)
			banner:Destroy()
		end
	end)
end

return Notifications
