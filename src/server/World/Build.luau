-- Small helpers for building the low-poly world out of Parts (no external assets).
local Build = {}

local DEFAULTS = {
	Anchored = true,
	CanCollide = true,
	TopSurface = Enum.SurfaceType.Smooth,
	BottomSurface = Enum.SurfaceType.Smooth,
	Material = Enum.Material.SmoothPlastic,
}

-- props: any Part properties plus `Shape` ("Ball"/"Cylinder"/"Block") and `Parent`.
function Build.part(props): BasePart
	local className = props.ClassName or "Part"
	local p = Instance.new(className) :: BasePart
	for k, v in pairs(DEFAULTS) do
		(p :: any)[k] = v
	end
	for k, v in pairs(props) do
		if k == "Shape" then
			(p :: Part).Shape = (Enum.PartType :: any)[v]
		elseif k ~= "Parent" and k ~= "ClassName" then
			(p :: any)[k] = v
		end
	end
	p.Parent = props.Parent
	return p
end

-- Flat disc / pillar: a Cylinder part rotated so its axis points up.
function Build.disc(cf: CFrame, height: number, diameter: number, props)
	props = props or {}
	props.Shape = "Cylinder"
	props.Size = Vector3.new(height, diameter, diameter)
	props.CFrame = cf * CFrame.Angles(0, 0, math.rad(90))
	return Build.part(props)
end

function Build.billboard(adornee: Instance, text: string, opts)
	opts = opts or {}
	local gui = Instance.new("BillboardGui")
	gui.Name = opts.name or "Label"
	gui.Size = opts.size or UDim2.fromOffset(220, 50)
	gui.StudsOffsetWorldSpace = opts.offset or Vector3.new(0, 4, 0)
	gui.AlwaysOnTop = opts.alwaysOnTop == true
	gui.MaxDistance = opts.maxDistance or 120
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.RichText = true
	label.Font = opts.font or Enum.Font.FredokaOne
	label.TextColor3 = opts.color or Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.3
	label.TextStrokeColor3 = Color3.fromRGB(20, 10, 40)
	label.Parent = gui
	gui.Adornee = adornee :: any
	gui.Parent = adornee
	return gui, label
end

function Build.prompt(parent: Instance, actionText: string, objectText: string, opts)
	opts = opts or {}
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = opts.name or "Prompt"
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	prompt.HoldDuration = opts.hold or 0
	prompt.MaxActivationDistance = opts.distance or 10
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = opts.key or Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	if opts.attributes then
		for k, v in pairs(opts.attributes) do
			prompt:SetAttribute(k, v)
		end
	end
	prompt.Parent = parent
	return prompt
end

function Build.light(parent: Instance, color: Color3, brightness: number, range: number)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = brightness
	light.Range = range
	light.Shadows = false
	light.Parent = parent
	return light
end

-- Low-poly rock: a few rotated blocks.
function Build.rock(parent: Instance, cf: CFrame, size: number, color: Color3, rng: Random)
	for i = 1, 3 do
		Build.part({
			Name = "Rock",
			Size = Vector3.new(size * rng:NextNumber(0.6, 1), size * rng:NextNumber(0.4, 0.8), size * rng:NextNumber(0.6, 1)),
			CFrame = cf
				* CFrame.new(rng:NextNumber(-size, size) * 0.3, size * 0.2, rng:NextNumber(-size, size) * 0.3)
				* CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, math.pi), rng:NextNumber(-0.4, 0.4)),
			Color = color,
			Material = Enum.Material.Slate,
			Parent = parent,
		})
		if i == 1 and size < 3 then
			break
		end
	end
end

-- Low-poly tree: trunk + stacked rotated leaf blocks.
function Build.tree(parent: Instance, cf: CFrame, scale: number, leafColor: Color3, trunkColor: Color3, rng: Random)
	local model = Instance.new("Model")
	model.Name = "Tree"
	Build.part({
		Name = "Trunk",
		Size = Vector3.new(1.4, 7, 1.4) * scale,
		CFrame = cf * CFrame.new(0, 3.5 * scale, 0),
		Color = trunkColor,
		Material = Enum.Material.Wood,
		Parent = model,
	})
	for i = 0, 2 do
		local s = (5.5 - i * 1.5) * scale
		Build.part({
			Name = "Leaves",
			Size = Vector3.new(s, s * 0.7, s),
			CFrame = cf * CFrame.new(0, (6.5 + i * 2.2) * scale, 0) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0),
			Color = leafColor,
			Material = Enum.Material.SmoothPlastic,
			Parent = model,
		})
	end
	model.Parent = parent
	return model
end

-- Crystal cluster used for decoration and harvest nodes.
function Build.crystal(parent: Instance, cf: CFrame, color: Color3, scale: number, rng: Random)
	local model = Instance.new("Model")
	model.Name = "Crystal"
	local parts = {}
	for i = 1, 4 do
		local h = (i == 1 and 5 or rng:NextNumber(2.2, 3.8)) * scale
		local p = Build.part({
			Name = "Shard",
			Size = Vector3.new(1.3 * scale, h, 1.3 * scale),
			CFrame = cf
				* CFrame.new(if i == 1 then 0 else rng:NextNumber(-1.4, 1.4) * scale, h / 2 - 0.3, if i == 1 then 0 else rng:NextNumber(-1.4, 1.4) * scale)
				* CFrame.Angles(rng:NextNumber(-0.35, 0.35), math.rad(45), rng:NextNumber(-0.35, 0.35)),
			Color = color,
			Material = Enum.Material.Glass,
			Transparency = 0.1,
			CanCollide = false,
			Parent = model,
		})
		table.insert(parts, p)
	end
	model.PrimaryPart = parts[1]
	model.Parent = parent
	return model, parts
end

return Build
