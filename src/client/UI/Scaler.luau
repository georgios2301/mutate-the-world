-- Responsive UI scale. Every top-level UI block gets one UIScale from here so the whole
-- interface shrinks on phones and grows on large screens (times the player's UI-size setting).
-- UIScale only scales sizes, so each block's position offset is scaled here as well; that
-- keeps blocks stacked at the edges from overlapping at large scales.
local Kit = require(script.Parent.Kit)

local Scaler = {}

Scaler.value = 1
local items: { { scale: UIScale, object: GuiObject, base: UDim2 } } = {}

local function place(item)
	local v = Scaler.value
	local base = item.base
	item.object.Position = UDim2.new(base.X.Scale, base.X.Offset * v, base.Y.Scale, base.Y.Offset * v)
	item.scale.Scale = v
end

function Scaler.attach(object: GuiObject): UIScale
	local scale = Kit.new("UIScale", { Name = "AutoScale", Scale = Scaler.value, Parent = object }) :: UIScale
	local item = { scale = scale, object = object, base = object.Position }
	table.insert(items, item)
	place(item)
	return scale
end

function Scaler.set(value: number)
	Scaler.value = value
	for i = #items, 1, -1 do
		local item = items[i]
		if item.scale.Parent then
			place(item)
		else
			table.remove(items, i)
		end
	end
end

Kit.scaleHook = Scaler.attach

-- Pop-in animation that ends at the current responsive scale.
function Scaler.pop(scale: UIScale, from: number?)
	scale.Scale = Scaler.value * (from or 0.85)
	Kit.tween(scale, { Scale = Scaler.value }, 0.18, Enum.EasingStyle.Back)
end

-- Base scale for a viewport: 1.0 at about 1100x620 and up to 1.25 on big monitors. Phones
-- are floored at 0.68 so text stays readable (a 780x520 panel still fits an 844x390 phone).
function Scaler.forViewport(size: Vector2, userScale: number): number
	local base = math.min(size.X / 1100, size.Y / 620)
	return math.clamp(base, 0.68, 1.25) * userScale
end

return Scaler
