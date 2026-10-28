-- Procedural low-poly creature models built from Parts. Used by the server (island pads,
-- wild creatures, chamber) and the client (ViewportFrame previews).
-- One model = an anchored invisible "Root" part with every visual part welded to it,
-- so moving Root moves the whole creature (the client uses this for idle bobbing).
local Config = script.Parent.Config
local Creatures = require(Config.Creatures)
local Mutations = require(Config.Mutations)
local Rarity = require(Config.Rarity)

local CreatureModels = {}

local EFFECTS = {
	frost = { color = Color3.fromRGB(220, 245, 255), texture = "sparkles", rate = 4, speed = 1, life = 1.6, size = 0.35 },
	bubbles = { color = Color3.fromRGB(150, 255, 110), texture = "sparkles", rate = 3, speed = 2, life = 1.2, size = 0.45 },
	sparks = { color = Color3.fromRGB(255, 120, 240), texture = "sparkles", rate = 6, speed = 4, life = 0.45, size = 0.3 },
	glitch = { color = Color3.fromRGB(90, 240, 255), texture = "sparkles", rate = 5, speed = 0.5, life = 0.3, size = 0.7 },
	embers = { color = Color3.fromRGB(255, 150, 50), texture = "fire", rate = 5, speed = 3, life = 0.8, size = 0.4 },
	smoke = { color = Color3.fromRGB(90, 120, 70), texture = "smoke", rate = 3, speed = 1, life = 2, size = 1.2 },
	stars = { color = Color3.fromRGB(200, 170, 255), texture = "sparkles", rate = 5, speed = 1.5, life = 1.5, size = 0.4 },
	flare = { color = Color3.fromRGB(255, 240, 200), texture = "sparkles", rate = 8, speed = 2.5, life = 0.8, size = 0.5 },
	aura = { color = Color3.fromRGB(255, 240, 160), texture = "sparkles", rate = 5, speed = 0.8, life = 1.4, size = 0.3 },
}

local TEXTURES = {
	sparkles = "rbxasset://textures/particles/sparkles_main.dds",
	fire = "rbxasset://textures/particles/fire_main.dds",
	smoke = "rbxasset://textures/particles/smoke_main.dds",
}

local function shiftHue(color: Color3, amount: number): Color3
	local h, s, v = color:ToHSV()
	return Color3.fromHSV((h + amount) % 1, s, v)
end

-- Builder context: keeps the root, scale and colors so archetype functions stay short.
local Builder = {}
Builder.__index = Builder

function Builder.new(model: Model, root: BasePart, scale: number, palette)
	return setmetatable({ model = model, root = root, s = scale, palette = palette, height = 0 }, Builder)
end

-- shape: "Block" | "Ball" | "Ellipsoid" | "Wedge" | "Cylinder"
function Builder:add(shape: string, size: Vector3, offset: CFrame, colorKey: string, extra)
	extra = extra or {}
	local s = self.s
	local p: BasePart
	if shape == "Wedge" then
		p = Instance.new("WedgePart")
	else
		local part = Instance.new("Part")
		if shape == "Ball" then
			part.Shape = Enum.PartType.Ball
		elseif shape == "Cylinder" then
			part.Shape = Enum.PartType.Cylinder
		end
		p = part
	end
	p.Name = extra.name or shape
	p.Size = size * s
	local pos = offset.Position * s
	p.CFrame = self.root.CFrame * (CFrame.new(pos) * offset.Rotation)
	local color = self.palette[colorKey] or colorKey
	if typeof(color) ~= "Color3" then
		color = self.palette.primary
	end
	p.Color = color
	local material = extra.material
	if not material then
		if colorKey == "primary" then
			material = self.palette.bodyMaterial
		elseif colorKey == "glow" then
			material = Enum.Material.Neon
		else
			material = Enum.Material.SmoothPlastic
		end
	end
	p.Material = material
	p.Transparency = extra.transparency or 0
	p.Anchored = false
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = true
	p.CastShadow = size.Magnitude * s > 3
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape == "Ellipsoid" then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	end
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = self.root
	weld.Part1 = p
	weld.Parent = p
	p.Parent = self.model
	local top = (pos.Y + p.Size.Y / 2)
	if top > self.height then
		self.height = top
	end
	return p
end

-- Eyes facing -Z. `spread` is the horizontal distance between eyes, `count` 1-4.
function Builder:eyes(count: number, center: Vector3, spread: number, size: number)
	count = math.clamp(count or 2, 1, 4)
	for i = 1, count do
		local x = 0
		if count > 1 then
			x = (i - 1) / (count - 1) * spread - spread / 2
		end
		local y = center.Y + (if count >= 3 and i % 2 == 0 then size * 0.6 else 0)
		local eyeSize = if count == 1 then size * 1.7 else size
		self:add("Ball", Vector3.new(eyeSize, eyeSize, eyeSize), CFrame.new(center.X + x, y, center.Z), "eyeWhite", {
			material = Enum.Material.SmoothPlastic,
			name = "Eye",
		})
		self:add(
			"Ball",
			Vector3.new(eyeSize * 0.5, eyeSize * 0.5, eyeSize * 0.5),
			CFrame.new(center.X + x, y, center.Z - eyeSize * 0.32),
			"pupil",
			{ material = Enum.Material.SmoothPlastic, name = "Pupil" }
		)
	end
end

function Builder:spikes(count: number, positions)
	for i = 1, math.min(count or 0, #positions) do
		local pos = positions[i]
		self:add(
			"Block",
			Vector3.new(0.5, 1.4, 0.5),
			CFrame.new(pos) * CFrame.Angles(math.rad(-15 + i * 7), math.rad(45), math.rad((i % 2 == 0 and 1 or -1) * 12)),
			"glow",
			{ material = Enum.Material.Glass, name = "Spike" }
		)
	end
end

local Archetypes = {}

function Archetypes.Blob(b, look)
	b:add("Ellipsoid", Vector3.new(4.2, 3.4, 4.2), CFrame.new(0, 1.7, 0), "primary", { name = "Body" })
	b:add("Ellipsoid", Vector3.new(2.6, 1.8, 0.8), CFrame.new(0, 1.3, -1.7), "secondary", { name = "Belly" })
	for i = 0, 3 do
		local a = math.rad(45 + i * 90)
		b:add("Ball", Vector3.new(1, 1, 1), CFrame.new(math.cos(a) * 1.8, 0.45, math.sin(a) * 1.8), "accent")
	end
	b:eyes(look.eyes or 2, Vector3.new(0, 2.4, -1.75), 1.4, 0.8)
	b:add("Block", Vector3.new(0.8, 0.15, 0.1), CFrame.new(0, 1.7, -2.05), "pupil", { name = "Mouth" })
	if look.glow then
		b:add("Ball", Vector3.new(1.2, 1.2, 1.2), CFrame.new(0, 3.5, 0), "glow", { name = "Core" })
	end
end

function Archetypes.Insect(b, look)
	b:add("Ellipsoid", Vector3.new(3.2, 2, 3.6), CFrame.new(0, 1.5, 0.8), "primary", { name = "Body" })
	b:add("Ball", Vector3.new(1.8, 1.8, 1.8), CFrame.new(0, 1.6, -1.4), "secondary", { name = "Head" })
	for side = -1, 1, 2 do
		for i, z in ipairs({ -0.4, 0.6, 1.6 }) do
			b:add(
				"Block",
				Vector3.new(0.25, 0.25, 2.2),
				CFrame.new(side * 1.7, 0.7, z) * CFrame.Angles(0, math.rad(side * (90 + (i - 2) * 20)), math.rad(side * 25)),
				"secondary",
				{ name = "Leg" }
			)
		end
		b:add(
			"Block",
			Vector3.new(0.15, 1.2, 0.15),
			CFrame.new(side * 0.4, 2.7, -1.8) * CFrame.Angles(math.rad(-25), 0, math.rad(side * 20)),
			"accent",
			{ name = "Antenna" }
		)
	end
	b:spikes(look.spikes or 3, { Vector3.new(0, 2.6, 0.4), Vector3.new(-0.7, 2.4, 1.2), Vector3.new(0.7, 2.4, 1.2), Vector3.new(0, 2.3, 1.9) })
	b:eyes(look.eyes or 2, Vector3.new(0, 1.9, -2.15), 0.9, 0.55)
end

function Archetypes.Sprite(b, look)
	b:add("Ellipsoid", Vector3.new(2.2, 2.6, 1.8), CFrame.new(0, 2.3, 0), "primary", { name = "Body" })
	b:add("Ball", Vector3.new(2.3, 2.3, 2.3), CFrame.new(0, 4.3, 0), "secondary", { name = "Head" })
	for side = -1, 1, 2 do
		b:add("Block", Vector3.new(0.7, 1.2, 0.7), CFrame.new(side * 0.55, 0.6, 0), "primary", { name = "Leg" })
		b:add(
			"Block",
			Vector3.new(0.5, 1.5, 0.5),
			CFrame.new(side * 1.35, 2.4, 0) * CFrame.Angles(0, 0, math.rad(side * 18)),
			"primary",
			{ name = "Arm" }
		)
	end
	b:spikes(look.spikes or 2, { Vector3.new(-0.6, 5.5, 0), Vector3.new(0.6, 5.5, 0), Vector3.new(0, 5.7, 0.4) })
	b:eyes(look.eyes or 2, Vector3.new(0, 4.4, -1.05), 0.9, 0.6)
end

function Archetypes.Wisp(b, look)
	b:add("Ball", Vector3.new(2.6, 2.6, 2.6), CFrame.new(0, 3, 0), if look.glow then "glow" else "primary", { name = "Core" })
	b:add("Ball", Vector3.new(3.6, 3.6, 3.6), CFrame.new(0, 3, 0), "secondary", { name = "Shell", transparency = 0.65 })
	local tail = { { 1.6, Vector3.new(0, 2.2, 1.6) }, { 1.1, Vector3.new(0, 1.5, 2.5) }, { 0.7, Vector3.new(0, 1.0, 3.2) } }
	for _, t in ipairs(tail) do
		b:add("Ball", Vector3.new(t[1], t[1], t[1]), CFrame.new(t[2]), "primary", { name = "Tail" })
	end
	for side = -1, 1, 2 do
		b:add("Ball", Vector3.new(0.6, 0.6, 0.6), CFrame.new(side * 2.4, 3.6, 0.4), "accent", { name = "Orbit", material = Enum.Material.Neon })
	end
	b:eyes(look.eyes or 2, Vector3.new(0, 3.2, -1.75), 1.0, 0.6)
end

function Archetypes.Quadruped(b, look)
	b:add("Ellipsoid", Vector3.new(2.6, 2.2, 4.2), CFrame.new(0, 2.4, 0), "primary", { name = "Body" })
	b:add("Ellipsoid", Vector3.new(2.2, 2, 2.2), CFrame.new(0, 3.4, -2.4), "primary", { name = "Head" })
	b:add("Block", Vector3.new(1.2, 0.8, 1), CFrame.new(0, 3.0, -3.5), "secondary", { name = "Snout" })
	for _, x in ipairs({ -0.9, 0.9 }) do
		for _, z in ipairs({ -1.4, 1.4 }) do
			b:add("Block", Vector3.new(0.8, 1.7, 0.8), CFrame.new(x, 0.85, z), "secondary", { name = "Leg" })
		end
	end
	b:add("Block", Vector3.new(0.5, 0.5, 2), CFrame.new(0, 3.0, 2.6) * CFrame.Angles(math.rad(35), 0, 0), "secondary", { name = "Tail" })
	local mane = {}
	local n = math.max(1, look.spikes or 4)
	for i = 1, n do
		local a = math.rad(-70 + (i - 1) * (140 / math.max(1, n - 1)))
		table.insert(mane, Vector3.new(math.sin(a) * 1.1, 4.2 + math.cos(a) * 0.4, -1.7))
	end
	b:spikes(n, mane)
	b:eyes(look.eyes or 2, Vector3.new(0, 3.8, -3.4), 0.9, 0.5)
end

function Archetypes.Golem(b, look)
	b:add("Block", Vector3.new(3.6, 3.4, 2.4), CFrame.new(0, 3.6, 0), "primary", { name = "Body" })
	b:add("Block", Vector3.new(2, 1.8, 1.8), CFrame.new(0, 6.2, 0), "secondary", { name = "Head" })
	for side = -1, 1, 2 do
		b:add("Block", Vector3.new(1.2, 3.2, 1.2), CFrame.new(side * 2.6, 3.4, 0) * CFrame.Angles(0, 0, math.rad(side * 6)), "primary", {
			name = "Arm",
		})
		b:add("Block", Vector3.new(1.3, 1.9, 1.3), CFrame.new(side * 0.9, 0.95, 0), "secondary", { name = "Leg" })
	end
	b:add("Ball", Vector3.new(1, 1, 1), CFrame.new(0, 3.9, -1.2), "glow", { name = "Core" })
	b:spikes(look.spikes or 4, {
		Vector3.new(-2.6, 5.4, 0),
		Vector3.new(2.6, 5.4, 0),
		Vector3.new(-1, 5.6, 0.9),
		Vector3.new(1, 5.6, 0.9),
		Vector3.new(0, 7.4, 0),
		Vector3.new(0, 5.2, 1.3),
	})
	local count = look.eyes or 2
	for i = 1, count do
		local x = if count == 1 then 0 else (i - 1) / (count - 1) * 0.8 - 0.4
		b:add("Block", Vector3.new(0.35, 0.25, 0.1), CFrame.new(x, 6.4, -0.92), "glow", { name = "Eye" })
	end
end

function Archetypes.Serpent(b, look)
	for i = 0, 5 do
		local a = math.rad(i * 60)
		local size = 2.2 - i * 0.18
		b:add("Ball", Vector3.new(size, size, size), CFrame.new(math.cos(a) * 1.7, 0.9 + i * 0.25, math.sin(a) * 1.7), "primary", {
			name = "Coil",
		})
	end
	local heads = math.clamp(look.heads or 1, 1, 3)
	for h = 1, heads do
		local x = if heads == 1 then 0 else (h - 1) / (heads - 1) * 3 - 1.5
		local lean = x * 0.15
		b:add("Ball", Vector3.new(1.4, 1.4, 1.4), CFrame.new(x * 0.6, 2.7, -0.6), "primary", { name = "Neck" })
		b:add("Ball", Vector3.new(1.2, 1.2, 1.2), CFrame.new(x * 0.85, 3.8, -1.0), "primary", { name = "Neck" })
		b:add("Ellipsoid", Vector3.new(1.6, 1.3, 2.1), CFrame.new(x, 4.8, -1.5) * CFrame.Angles(0, 0, lean), "secondary", {
			name = "Head",
		})
		b:add("Block", Vector3.new(1.1, 0.25, 0.9), CFrame.new(x, 4.25, -2.2), "pupil", { name = "Jaw" })
		b:eyes(if heads == 1 then (look.eyes or 2) else 2, Vector3.new(x, 5.1, -2.35), 0.7, 0.4)
	end
	b:spikes(look.spikes or 3, {
		Vector3.new(0, 2.2, 1.6),
		Vector3.new(-1.4, 1.9, 0.8),
		Vector3.new(1.4, 1.9, 0.8),
		Vector3.new(0, 1.6, -1.6),
		Vector3.new(-1.6, 1.2, -0.6),
		Vector3.new(1.6, 1.2, -0.6),
		Vector3.new(-0.8, 2.6, 0.9),
		Vector3.new(0.8, 2.6, 0.9),
	})
end

function Archetypes.Mimic(b, look)
	b:add("Block", Vector3.new(3.6, 2.2, 2.6), CFrame.new(0, 1.1, 0), "primary", { name = "Body" })
	b:add("Block", Vector3.new(3.7, 0.35, 2.7), CFrame.new(0, 1.1, 0), "secondary", { name = "Trim" })
	b:add("Block", Vector3.new(3.6, 0.9, 2.6), CFrame.new(0, 3.0, 0.6) * CFrame.Angles(math.rad(35), 0, 0), "primary", {
		name = "Lid",
	})
	for i = 0, 5 do
		b:add("Wedge", Vector3.new(0.4, 0.5, 0.3), CFrame.new(-1.5 + i * 0.6, 2.45, -1.15) * CFrame.Angles(math.rad(180), 0, 0), "eyeWhite", {
			name = "Tooth",
		})
	end
	b:add("Ellipsoid", Vector3.new(1.4, 0.4, 1.6), CFrame.new(0, 2.25, -0.6), "tongue", { name = "Tongue" })
	b:add("Ball", Vector3.new(1.1, 1.1, 1.1), CFrame.new(0, 2.6, 0.2), "glow", { name = "Star" })
	b:eyes(look.eyes or 2, Vector3.new(0, 3.9, -0.1), 1.6, 0.6)
end

local function addEffect(root: BasePart, effectId: string)
	local e = EFFECTS[effectId]
	if not e then
		return
	end
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Effect"
	emitter.Texture = TEXTURES[e.texture]
	emitter.Color = ColorSequence.new(e.color)
	emitter.LightEmission = 0.6
	emitter.Rate = e.rate
	emitter.Lifetime = NumberRange.new(e.life * 0.7, e.life)
	emitter.Speed = NumberRange.new(e.speed * 0.5, e.speed)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, e.size),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Parent = root
end

-- data = { species, mutation, level, seed, aura? }
-- opts = { effects = boolean (default true) }
function CreatureModels.build(data, opts): Model
	opts = opts or {}
	local species = Creatures.Species[data.species] or Creatures.Species.basic_blob
	local mutation = Mutations.Types[data.mutation or "none"] or Mutations.Types.none
	local look = species.look
	local rng = Random.new(data.seed or 1)

	local primary = shiftHue(look.primary, rng:NextNumber(-0.025, 0.025))
	local secondary = look.secondary
	local bodyMaterial = Enum.Material[look.material or "SmoothPlastic"]
	if mutation.id ~= "none" then
		primary = primary:Lerp(mutation.color, 0.55)
		secondary = secondary:Lerp(mutation.color, 0.25)
		bodyMaterial = Enum.Material[mutation.material] or bodyMaterial
	end

	local palette = {
		primary = primary,
		secondary = secondary,
		accent = look.accent,
		glow = if mutation.id ~= "none" then mutation.color else look.accent,
		eyeWhite = Color3.fromRGB(250, 250, 255),
		pupil = Color3.fromRGB(25, 20, 35),
		tongue = Color3.fromRGB(255, 110, 150),
		bodyMaterial = bodyMaterial,
	}

	local scale = look.scale * (1 + ((data.level or 1) - 1) * 0.03) * rng:NextNumber(0.95, 1.05)

	local model = Instance.new("Model")
	model.Name = species.name
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(1, 1, 1)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanTouch = false
	root.CanQuery = false
	root.CFrame = CFrame.new()
	root.Parent = model
	model.PrimaryPart = root

	local b = Builder.new(model, root, scale, palette)
	local build = Archetypes[look.archetype] or Archetypes.Blob
	build(b, look)

	local rarityInfo = Rarity.Info[species.rarity]
	if rarityInfo.rank >= 5 then
		b:add("Cylinder", Vector3.new(0.15, 6.5, 6.5), CFrame.new(0, 0.1, 0) * CFrame.Angles(0, 0, math.rad(90)), "halo", {
			material = Enum.Material.Neon,
			transparency = 0.45,
			name = "Halo",
		}).Color = rarityInfo.color
	end

	if opts.effects ~= false then
		if mutation.effect then
			addEffect(root, mutation.effect)
		elseif data.aura then
			addEffect(root, "aura")
		end
		if mutation.tier >= 2 or rarityInfo.rank >= 4 or look.glow then
			local light = Instance.new("PointLight")
			light.Color = palette.glow
			light.Brightness = 1
			light.Range = 8 + mutation.tier * 2
			light.Shadows = false
			light.Parent = root
		end
	end

	model:SetAttribute("Species", species.id)
	model:SetAttribute("Mutation", mutation.id)
	model:SetAttribute("Height", b.height)
	return model
end

function CreatureModels.height(model: Model): number
	return (model:GetAttribute("Height") :: number?) or 4
end

return CreatureModels
