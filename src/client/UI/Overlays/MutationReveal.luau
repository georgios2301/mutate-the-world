-- Mutation result reveal: rarity banner, spinning 3D creature, confetti and a light flash.
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Creatures = require(Shared.Config.Creatures)
local Mutations = require(Shared.Config.Mutations)
local Rarity = require(Shared.Config.Rarity)

local Client = script.Parent.Parent.Parent
local ClientState = require(Client.ClientState)

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Kit = require(UI.Kit)
local Sound = require(UI.Sound)
local CreatureView = require(UI.CreatureView)
local Scaler = require(UI.Scaler)

local MutationReveal = {}
local C = Theme.Colors

local overlay: TextButton
local card: Frame
local headline: TextLabel
local nameLabel: TextLabel
local rarityLabel: TextLabel
local detailLabel: TextLabel
local view
local confettiLayer: Frame
local flash: ColorCorrectionEffect
local cardScale: UIScale
local okButton: TextButton

local function confetti(color: Color3)
	Kit.clear(confettiLayer)
	local rng = Random.new()
	for _ = 1, 28 do
		local piece = Kit.frame(confettiLayer, {
			Size = UDim2.fromOffset(rng:NextInteger(6, 12), rng:NextInteger(10, 18)),
			Position = UDim2.new(rng:NextNumber(0.05, 0.95), 0, 0, -20),
			BackgroundColor3 = if rng:NextNumber() < 0.5 then color else C.cyan:Lerp(C.green, rng:NextNumber()),
			Rotation = rng:NextNumber(0, 360),
			radius = 2,
		})
		Kit.tween(piece, {
			Position = UDim2.new(piece.Position.X.Scale + rng:NextNumber(-0.1, 0.1), 0, 1, 20),
			Rotation = piece.Rotation + rng:NextNumber(-360, 360),
		}, rng:NextNumber(1.4, 2.4), Enum.EasingStyle.Quad)
	end
end

function MutationReveal.build(root: Instance)
	overlay = Kit.new("TextButton", {
		Name = "MutationReveal",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		Text = "",
		AutoButtonColor = false,
		Visible = false,
		ZIndex = 20,
		Parent = root,
	}) :: TextButton
	confettiLayer = Kit.frame(overlay, { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 21 })
	card = Kit.frame(overlay, {
		Size = UDim2.fromOffset(440, 430),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = C.panel,
		ZIndex = 22,
		radius = 20,
	})
	Kit.stroke(card, C.gold, 3, 0)
	Kit.padding(card, 16)
	cardScale = Scaler.attach(card)
	Kit.list(card, false, 6, Enum.HorizontalAlignment.Center)
	headline = Kit.label(card, "", { size = UDim2.new(1, 0, 0, 36), textSize = 30, font = Theme.Fonts.title, align = Enum.TextXAlignment.Center, color = C.green })
	view = CreatureView.new(card, UDim2.new(1, 0, 0, 200))
	view.frame.LayoutOrder = 1
	nameLabel = Kit.label(card, "", { size = UDim2.new(1, 0, 0, 30), textSize = 24, font = Theme.Fonts.title, align = Enum.TextXAlignment.Center, order = 2 })
	rarityLabel = Kit.label(card, "", { size = UDim2.new(1, 0, 0, 20), align = Enum.TextXAlignment.Center, font = Theme.Fonts.bold, order = 3 })
	detailLabel = Kit.label(card, "", { size = UDim2.new(1, 0, 0, 40), align = Enum.TextXAlignment.Center, wrap = true, textSize = Theme.TextSize.small, order = 4, color = C.muted })
	okButton = Kit.button(card, "Awesome!", { size = UDim2.fromOffset(200, 44), color = C.green, textColor = C.bg, order = 5, onClick = function()
		overlay.Visible = false
	end })
	for _, d in ipairs(overlay:GetDescendants()) do
		if d:IsA("GuiObject") then
			d.ZIndex = math.max(d.ZIndex, 22)
		end
	end
	overlay.Activated:Connect(function()
		overlay.Visible = false
	end)

	flash = Instance.new("ColorCorrectionEffect")
	flash.Name = "DiscoveryFlash"
	flash.Parent = Lighting
end

function MutationReveal.show(result)
	local creature = result.creature
	local species = Creatures.Species[creature.species]
	local color = Rarity.color(species.rarity)
	local mutation = Mutations.Types[creature.mutation]
	headline.Text = if result.kind == "evolution" then "EVOLUTION!" elseif result.newRecipe or result.newSpecies then "NEW DISCOVERY!" else "MUTATION COMPLETE"
	headline.TextColor3 = if result.newRecipe or result.newSpecies then C.gold else C.green
	nameLabel.Text = Mutations.displayName(species.name, creature.mutation)
	nameLabel.TextColor3 = color
	rarityLabel.Text = string.upper(species.rarity) .. (if mutation.id ~= "none" then "  ·  " .. mutation.name .. " ×" .. mutation.multiplier else "")
	rarityLabel.TextColor3 = color
	local extra = { "+" .. result.xp .. " XP" }
	if result.leveledUp then
		table.insert(extra, "LEVEL UP! You are now level " .. result.level)
	end
	if result.offline then
		table.insert(extra, "(finished while you were away)")
	end
	detailLabel.Text = table.concat(extra, "   ")
	view:set(creature)
	overlay.Visible = true
	local stroke = card:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = color
	end
	Scaler.pop(cardScale, 0.4)
	Kit.focus(okButton)

	local data = ClientState.data
	local reduced = data and data.settings.reducedEffects
	if not reduced then
		confetti(color)
		flash.Brightness = 0.35
		flash.TintColor = color:Lerp(Color3.new(1, 1, 1), 0.6)
		Kit.tween(flash, { Brightness = 0, TintColor = Color3.new(1, 1, 1) }, 0.8)
	end
	task.spawn(function()
		for i, speed in ipairs({ 1, 1.26, 1.5 }) do
			Sound.play("Discovery", speed / 1.5)
			if i < 3 then
				task.wait(0.12)
			end
		end
	end)
end

function MutationReveal.isOpen(): boolean
	return overlay.Visible
end

function MutationReveal.hide()
	overlay.Visible = false
end

return MutationReveal
