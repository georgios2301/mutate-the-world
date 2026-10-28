-- Generates the central hub, the four biomes, lighting and ambient effects at server start.
-- Returns a `world` table with spawn points the gameplay services use.
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local World = require(Shared.Config.World)
local Biomes = require(Shared.Config.Biomes)

local Build = require(script.Parent.Build)

local WorldBuilder = {}

local Y = World.GroundY

local function setupLighting()
	Lighting.ClockTime = 14.5
	Lighting.Brightness = 2.2
	Lighting.Ambient = Color3.fromRGB(90, 80, 120)
	Lighting.OutdoorAmbient = Color3.fromRGB(150, 130, 180)
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.6
	Lighting.GlobalShadows = true

	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.32
	atmosphere.Offset = 0.15
	atmosphere.Color = Color3.fromRGB(205, 175, 255)
	atmosphere.Decay = Color3.fromRGB(110, 80, 170)
	atmosphere.Glare = 0.25
	atmosphere.Haze = 1.4
	atmosphere.Parent = Lighting

	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.6
	bloom.Size = 24
	bloom.Threshold = 1.6
	bloom.Parent = Lighting

	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "WorldColor"
	cc.Saturation = 0.15
	cc.Contrast = 0.05
	cc.Parent = Lighting

	local rays = Instance.new("SunRaysEffect")
	rays.Intensity = 0.04
	rays.Spread = 0.6
	rays.Parent = Lighting

	local clouds = Instance.new("Clouds")
	clouds.Cover = 0.55
	clouds.Density = 0.5
	clouds.Color = Color3.fromRGB(235, 215, 255)
	clouds.Parent = workspace.Terrain
end

local function floatingRocks(parent: Instance, rng: Random, center: Vector3, radius: number, count: number)
	for _ = 1, count do
		local angle = rng:NextNumber(0, math.pi * 2)
		local dist = rng:NextNumber(radius * 0.6, radius)
		local pos = center + Vector3.new(math.cos(angle) * dist, rng:NextNumber(-60, 40), math.sin(angle) * dist)
		Build.rock(parent, CFrame.new(pos), rng:NextNumber(4, 12), Color3.fromRGB(120, 105, 150), rng)
	end
end

local function surfaceBoard(parent: Instance, cf: CFrame, size: Vector2, title: string, accent: Color3)
	local board = Build.part({
		Name = title,
		Size = Vector3.new(size.X, size.Y, 1),
		CFrame = cf,
		Color = Color3.fromRGB(25, 18, 45),
		Material = Enum.Material.SmoothPlastic,
		Parent = parent,
	})
	Build.part({
		Name = "Frame",
		Size = Vector3.new(size.X + 1, size.Y + 1, 0.6),
		CFrame = cf * CFrame.new(0, 0, 0.5),
		Color = accent,
		Material = Enum.Material.Neon,
		Parent = board,
	})
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.LightInfluence = 0
	gui.Parent = board
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Size = UDim2.new(1, 0, 0.16, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = title
	titleLabel.TextScaled = true
	titleLabel.Font = Enum.Font.FredokaOne
	titleLabel.TextColor3 = accent
	titleLabel.Parent = gui
	local list = Instance.new("Frame")
	list.Name = "List"
	list.Size = UDim2.new(0.92, 0, 0.8, 0)
	list.Position = UDim2.new(0.04, 0, 0.18, 0)
	list.BackgroundTransparency = 1
	list.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0.01, 0)
	layout.Parent = list
	return board, list
end

local function boardRows(list: Frame, count: number)
	local rows = {}
	for i = 1, count do
		local row = Instance.new("TextLabel")
		row.Name = "Row" .. i
		row.LayoutOrder = i
		row.Size = UDim2.new(1, 0, 1 / count - 0.01, 0)
		row.BackgroundTransparency = 1
		row.Text = ""
		row.TextScaled = true
		row.RichText = true
		row.Font = Enum.Font.GothamMedium
		row.TextColor3 = Color3.fromRGB(235, 230, 255)
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.Parent = list
		rows[i] = row
	end
	return rows
end

local function portal(parent: Instance, cf: CFrame, color: Color3, title: string, subtitle: string, destination: string)
	local model = Instance.new("Model")
	model.Name = "Portal_" .. destination
	for side = -1, 1, 2 do
		Build.part({
			Name = "Pillar",
			Size = Vector3.new(2, 15, 2),
			CFrame = cf * CFrame.new(side * 6, 7.5, 0),
			Color = Color3.fromRGB(60, 50, 90),
			Material = Enum.Material.Slate,
			Parent = model,
		})
	end
	Build.part({ Name = "Lintel", Size = Vector3.new(14, 2, 2.4), CFrame = cf * CFrame.new(0, 15.5, 0), Color = color, Material = Enum.Material.Neon, Parent = model })
	local surface = Build.part({
		Name = "Surface",
		Size = Vector3.new(10, 13, 0.4),
		CFrame = cf * CFrame.new(0, 7.5, 0),
		Color = color,
		Material = Enum.Material.ForceField,
		Transparency = 0.1,
		CanCollide = false,
		Parent = model,
	})
	Build.light(surface, color, 2, 16)
	Build.billboard(surface, string.format("%s\n<font size='16'>%s</font>", title, subtitle), {
		offset = Vector3.new(0, 11, 0),
		size = UDim2.fromOffset(240, 70),
		color = color,
		maxDistance = 200,
	})
	local prompt = Build.prompt(surface, "Travel", title, {
		name = "PortalPrompt",
		distance = 12,
		attributes = { Role = "Portal", Destination = destination },
	})
	model.Parent = parent
	return prompt
end

local function ringPoints(rng: Random, center: CFrame, minR: number, maxR: number, count: number, y: number)
	local points = {}
	for i = 1, count do
		local angle = (i / count) * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
		local r = rng:NextNumber(minR, maxR)
		table.insert(points, center * CFrame.new(math.cos(angle) * r, y, math.sin(angle) * r))
	end
	return points
end

local function buildHub(parent: Instance, world)
	local rng = Random.new(42)
	local hub = Instance.new("Model")
	hub.Name = "Hub"
	local center = CFrame.new(0, Y, 0)

	Build.disc(center * CFrame.new(0, -3, 0), 6, World.HubRadius * 2, {
		Name = "Plaza",
		Color = Color3.fromRGB(200, 190, 225),
		Material = Enum.Material.Cobblestone,
		Parent = hub,
	})
	Build.disc(center * CFrame.new(0, -0.1, 0), 0.4, 44, { Name = "Inner", Color = Color3.fromRGB(70, 55, 120), Parent = hub })
	Build.disc(center * CFrame.new(0, -0.05, 0), 0.5, 46, {
		Name = "InnerRing",
		Color = Color3.fromRGB(62, 230, 255),
		Material = Enum.Material.Neon,
		Parent = hub,
	})
	for i, d in ipairs({ 150, 110, 70, 30 }) do
		Build.part({
			Name = "Under",
			Size = Vector3.new(d, 14, d),
			CFrame = center * CFrame.new(0, -6 - i * 12, 0) * CFrame.Angles(0, math.rad(i * 25), 0),
			Color = Color3.fromRGB(110, 96, 130),
			Material = Enum.Material.Slate,
			Parent = hub,
		})
	end

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "HubSpawn"
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.CFrame = center * CFrame.new(0, 0.5, 0)
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Color = Color3.fromRGB(150, 90, 255)
	spawn.Material = Enum.Material.Neon
	spawn.Parent = hub
	world.hubSpawn = center * CFrame.new(0, 4, 8)

	local titleAnchor = Build.part({ Name = "Title", Size = Vector3.new(1, 1, 1), CFrame = center * CFrame.new(0, 30, 0), Transparency = 1, CanCollide = false, Parent = hub })
	Build.billboard(titleAnchor, "MUTATE THE WORLD", {
		size = UDim2.fromOffset(700, 110),
		offset = Vector3.new(0, 0, 0),
		maxDistance = 900,
		color = Color3.fromRGB(190, 140, 255),
	})

	-- Creature Grove (north): wild creatures + DNA orbs + starter crystals
	local grove = center * CFrame.new(0, 0, -52)
	Build.disc(grove * CFrame.new(0, 0.1, 0), 0.4, 62, { Name = "Grove", Color = Color3.fromRGB(110, 200, 120), Material = Enum.Material.Grass, Parent = hub })
	for i = 1, 7 do
		local a = math.rad(i * 51)
		Build.tree(hub, grove * CFrame.new(math.cos(a) * 30, 0, math.sin(a) * 30 - 4), rng:NextNumber(0.9, 1.3), Color3.fromRGB(150, 110, 230), Color3.fromRGB(100, 70, 60), rng)
	end
	local groveSign = Build.part({ Name = "GroveSign", Size = Vector3.new(1, 1, 1), CFrame = grove * CFrame.new(0, 12, 0), Transparency = 1, CanCollide = false, Parent = hub })
	Build.billboard(groveSign, "CREATURE GROVE\n<font size='16'>Capture creatures · Grab DNA orbs</font>", {
		size = UDim2.fromOffset(320, 70),
		offset = Vector3.new(0, 0, 0),
		color = Color3.fromRGB(124, 255, 79),
		maxDistance = 250,
	})
	world.hub = {
		center = center.Position,
		radius = World.HubRadius,
		orbPoints = ringPoints(rng, grove, 8, 24, 12, 2.5),
		wildPoints = ringPoints(rng, grove, 10, 20, 5, 0),
		nodePoints = { grove * CFrame.new(-14, 0, -18), grove * CFrame.new(14, 0, -18) },
	}

	-- Market (west)
	local market = center * CFrame.new(-56, 0, 0) * CFrame.Angles(0, math.rad(-90), 0)
	for side = -1, 1, 2 do
		for depth = -1, 1, 2 do
			Build.part({ Name = "Post", Size = Vector3.new(1, 10, 1), CFrame = market * CFrame.new(side * 12, 5, depth * 5), Color = Color3.fromRGB(110, 75, 50), Material = Enum.Material.Wood, Parent = hub })
		end
	end
	Build.part({
		Name = "Roof",
		ClassName = "WedgePart",
		Size = Vector3.new(26, 4, 12),
		CFrame = market * CFrame.new(0, 12, 0),
		Color = Color3.fromRGB(255, 154, 60),
		Parent = hub,
	})
	local function stall(x: number, label: string, tab: string, color: Color3)
		local counter = Build.part({
			Name = "Stall_" .. tab,
			Size = Vector3.new(7, 3.5, 3),
			CFrame = market * CFrame.new(x, 1.75, -3),
			Color = color,
			Material = Enum.Material.SmoothPlastic,
			Parent = hub,
		})
		Build.billboard(counter, label, { offset = Vector3.new(0, 4, 0), size = UDim2.fromOffset(200, 40), color = color })
		Build.prompt(counter, "Open", label, { attributes = { Role = "Market", OpensPanel = "Shop", Tab = tab } })
	end
	stall(-8, "CREATURE MARKET", "creatures", Color3.fromRGB(124, 255, 79))
	stall(0, "UPGRADES", "upgrades", Color3.fromRGB(62, 230, 255))
	stall(8, "DAILY REWARDS", "rewards", Color3.fromRGB(255, 205, 70))

	-- Hall of fame (east): discovery board + two leaderboards
	local hall = center * CFrame.new(60, 0, 0)
	local function facingCenter(offset: Vector3)
		local pos = (hall * CFrame.new(offset)).Position
		return CFrame.lookAt(pos, Vector3.new(0, pos.Y, 0))
	end
	local _, discoveryList = surfaceBoard(hub, facingCenter(Vector3.new(0, 10, 0)), Vector2.new(24, 16), "DISCOVERY BOARD", Color3.fromRGB(124, 255, 79))
	world.discoveryRows = boardRows(discoveryList, 9)
	local _, lb1 = surfaceBoard(hub, facingCenter(Vector3.new(-6, 9, -28)), Vector2.new(16, 14), "TOP DISCOVERERS", Color3.fromRGB(179, 107, 255))
	local _, lb2 = surfaceBoard(hub, facingCenter(Vector3.new(-6, 9, 28)), Vector2.new(16, 14), "TOP EARNERS", Color3.fromRGB(255, 205, 70))
	world.leaderboards = { discoveries = boardRows(lb1, 10), earned = boardRows(lb2, 10) }

	-- Portals (south)
	world.portals = {}
	local portalArc = { { "island", "MY ISLAND", "Home sweet home", Color3.fromRGB(150, 90, 255) } }
	for _, id in ipairs(Biomes.Order) do
		local def = Biomes.Defs[id]
		local req = def.requirements
		local subtitle = if def.unlockedByDefault then "Open to all" else string.format("Lv %d · %s coins", req.level or 1, tostring(req.coins or 0))
		table.insert(portalArc, { "biome:" .. id, string.upper(def.name), subtitle, def.color })
	end
	for i, info in ipairs(portalArc) do
		local angle = math.rad(90 + (i - (#portalArc + 1) / 2) * 24)
		local pos = Vector3.new(math.cos(angle) * 62, Y, math.sin(angle) * 62)
		local cf = CFrame.lookAt(pos, Vector3.new(0, Y, 0))
		table.insert(world.portals, portal(hub, cf, info[4], info[2], info[3], info[1]))
	end

	-- Lamps
	for i = 1, 8 do
		local a = math.rad(i * 45 + 22.5)
		local base = center * CFrame.new(math.cos(a) * 78, 0, math.sin(a) * 78)
		Build.part({ Name = "Lamp", Size = Vector3.new(0.8, 9, 0.8), CFrame = base * CFrame.new(0, 4.5, 0), Color = Color3.fromRGB(60, 50, 90), Material = Enum.Material.Metal, Parent = hub })
		local bulb = Build.part({ Name = "Bulb", Shape = "Ball", Size = Vector3.new(2, 2, 2), CFrame = base * CFrame.new(0, 9.5, 0), Color = Color3.fromRGB(62, 230, 255), Material = Enum.Material.Neon, CanCollide = false, Parent = hub })
		Build.light(bulb, Color3.fromRGB(120, 230, 255), 1.5, 18)
	end

	floatingRocks(hub, rng, Vector3.new(0, Y, 0), 220, 14)
	hub.Parent = parent
end

local BIOME_STYLE = {
	frozen_peaks = { ground = Color3.fromRGB(235, 245, 255), material = Enum.Material.Snow, rock = Color3.fromRGB(150, 170, 200), leaf = Color3.fromRGB(240, 250, 255) },
	toxic_swamp = { ground = Color3.fromRGB(70, 95, 55), material = Enum.Material.Mud, rock = Color3.fromRGB(60, 70, 50), leaf = Color3.fromRGB(110, 160, 60) },
	plasma_rift = { ground = Color3.fromRGB(45, 30, 60), material = Enum.Material.Basalt, rock = Color3.fromRGB(40, 25, 55), leaf = Color3.fromRGB(255, 90, 220) },
	cosmic_void = { ground = Color3.fromRGB(25, 15, 50), material = Enum.Material.Glass, rock = Color3.fromRGB(35, 25, 70), leaf = Color3.fromRGB(150, 110, 255) },
}

local function ambientParticles(parent: Instance, cf: CFrame, color: Color3, texture: string, rate: number, direction)
	local emitterPart = Build.part({
		Name = "Ambient",
		Size = Vector3.new(200, 1, 200),
		CFrame = cf,
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Parent = parent,
	})
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Ambient"
	emitter.Shape = Enum.ParticleEmitterShape.Box
	emitter.EmissionDirection = direction
	emitter.Texture = texture
	emitter.Color = ColorSequence.new(color)
	emitter.Rate = rate
	emitter.Lifetime = NumberRange.new(6, 9)
	emitter.Speed = NumberRange.new(3, 6)
	emitter.Size = NumberSequence.new(0.6)
	emitter.LightEmission = 0.4
	emitter.Parent = emitterPart
end

local function decorateBiome(id: string, model: Model, cf: CFrame, rng: Random, style)
	local function L(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end
	local terrain = workspace.Terrain
	if id == "frozen_peaks" then
		for i = 1, 5 do
			local x = -80 + i * 32
			Build.part({
				Name = "Peak",
				ClassName = "WedgePart",
				Size = Vector3.new(26, rng:NextNumber(30, 55), 30),
				CFrame = L(x, 20, 95) * CFrame.Angles(0, math.pi, 0),
				Color = Color3.fromRGB(225, 240, 255),
				Material = Enum.Material.Glacier,
				Parent = model,
			})
		end
		for _ = 1, 12 do
			Build.tree(model, L(rng:NextNumber(-95, 95), 0, rng:NextNumber(-60, 80)), rng:NextNumber(0.8, 1.4), style.leaf, Color3.fromRGB(90, 70, 60), rng)
		end
		for _ = 1, 10 do
			Build.crystal(model, L(rng:NextNumber(-100, 100), 0, rng:NextNumber(-100, 100)), Color3.fromRGB(170, 225, 255), rng:NextNumber(0.8, 1.6), rng)
		end
		terrain:FillBall(L(-60, -6, 40).Position, 18, Enum.Material.Snow)
		terrain:FillBall(L(70, -8, -10).Position, 22, Enum.Material.Snow)
		ambientParticles(model, L(0, 45, 0), Color3.fromRGB(255, 255, 255), "rbxasset://textures/particles/sparkles_main.dds", 40, Enum.NormalId.Bottom)
	elseif id == "toxic_swamp" then
		for _ = 1, 6 do
			local pos = L(rng:NextNumber(-80, 80), 0.6, rng:NextNumber(-60, 80)).Position
			terrain:FillBlock(CFrame.new(pos), Vector3.new(rng:NextNumber(16, 30), 1.2, rng:NextNumber(16, 30)), Enum.Material.Water)
		end
		for _ = 1, 14 do
			local base = L(rng:NextNumber(-95, 95), 0, rng:NextNumber(-80, 95))
			local h = rng:NextNumber(3, 7)
			Build.part({ Name = "Stem", Size = Vector3.new(1, h, 1), CFrame = base * CFrame.new(0, h / 2, 0), Color = Color3.fromRGB(220, 230, 200), Parent = model })
			local cap = Build.part({
				Name = "Cap",
				Shape = "Ball",
				Size = Vector3.new(h, h * 0.5, h),
				CFrame = base * CFrame.new(0, h, 0),
				Color = Color3.fromRGB(124, 255, 79),
				Material = Enum.Material.Neon,
				CanCollide = false,
				Parent = model,
			})
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = cap
		end
		for _ = 1, 8 do
			Build.tree(model, L(rng:NextNumber(-95, 95), 0, rng:NextNumber(-60, 95)), rng:NextNumber(1, 1.5), style.leaf, Color3.fromRGB(50, 40, 35), rng)
		end
		ambientParticles(model, L(0, 2, 0), Color3.fromRGB(150, 255, 100), "rbxasset://textures/particles/sparkles_main.dds", 25, Enum.NormalId.Top)
	elseif id == "plasma_rift" then
		for _ = 1, 10 do
			Build.part({
				Name = "Crack",
				Size = Vector3.new(rng:NextNumber(20, 60), 0.3, rng:NextNumber(1, 2.5)),
				CFrame = L(rng:NextNumber(-80, 80), 0.1, rng:NextNumber(-80, 80)) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0),
				Color = Color3.fromRGB(255, 90, 220),
				Material = Enum.Material.Neon,
				CanCollide = false,
				Parent = model,
			})
		end
		for _ = 1, 16 do
			Build.part({
				Name = "Shard",
				Size = Vector3.new(rng:NextNumber(3, 8), rng:NextNumber(8, 18), rng:NextNumber(3, 8)),
				CFrame = L(rng:NextNumber(-100, 100), rng:NextNumber(12, 40), rng:NextNumber(-100, 100))
					* CFrame.Angles(rng:NextNumber(-0.6, 0.6), rng:NextNumber(0, 3), rng:NextNumber(-0.6, 0.6)),
				Color = style.rock,
				Material = Enum.Material.Basalt,
				Parent = model,
			})
		end
		terrain:FillBlock(L(0, -1, 60), Vector3.new(50, 2, 30), Enum.Material.CrackedLava)
		ambientParticles(model, L(0, 2, 0), Color3.fromRGB(255, 120, 240), "rbxasset://textures/particles/sparkles_main.dds", 30, Enum.NormalId.Top)
	elseif id == "cosmic_void" then
		for i = 1, 6 do
			Build.disc(L(rng:NextNumber(-70, 70), rng:NextNumber(20, 45), rng:NextNumber(-70, 70)) * CFrame.Angles(rng:NextNumber(0, 1), 0, rng:NextNumber(0, 1)), 0.6, 14 + i * 3, {
				Name = "Ring",
				Color = Color3.fromRGB(150, 110, 255),
				Material = Enum.Material.Neon,
				Transparency = 0.4,
				CanCollide = false,
				Parent = model,
			})
		end
		for _ = 1, 10 do
			local h = rng:NextNumber(10, 30)
			Build.part({
				Name = "Monolith",
				Size = Vector3.new(4, h, 4),
				CFrame = L(rng:NextNumber(-95, 95), h / 2, rng:NextNumber(-95, 95)) * CFrame.Angles(0, rng:NextNumber(0, 3), 0),
				Color = Color3.fromRGB(20, 10, 40),
				Material = Enum.Material.Glass,
				Parent = model,
			})
		end
		ambientParticles(model, L(0, 30, 0), Color3.fromRGB(220, 200, 255), "rbxasset://textures/particles/sparkles_main.dds", 35, Enum.NormalId.Top)
	end
end

local function buildBiome(parent: Instance, id: string, world)
	local def = Biomes.Defs[id]
	local style = BIOME_STYLE[id]
	local cf = World.biomeCFrame(id)
	local rng = Random.new(#id * 1000 + 7)
	local half = World.BiomeHalfSize
	local model = Instance.new("Model")
	model.Name = def.name

	Build.part({ Name = "Ground", Size = Vector3.new(half * 2, 4, half * 2), CFrame = cf * CFrame.new(0, -2, 0), Color = style.ground, Material = style.material, Parent = model })
	for i, size in ipairs({ 200, 140, 80 }) do
		Build.part({
			Name = "Under",
			Size = Vector3.new(size, 18, size),
			CFrame = cf * CFrame.new(0, -4 - i * 16, 0) * CFrame.Angles(0, math.rad(i * 30), 0),
			Color = style.rock,
			Material = Enum.Material.Slate,
			Parent = model,
		})
	end
	Build.part({
		Name = "Edge",
		Size = Vector3.new(half * 2 + 1, 0.5, half * 2 + 1),
		CFrame = cf * CFrame.new(0, -0.3, 0),
		Color = def.color,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = model,
	})

	decorateBiome(id, model, cf, rng, style)

	local returnPrompt = portal(model, cf * CFrame.new(0, 0, -half + 12), Color3.fromRGB(150, 90, 255), "RETURN TO HUB", def.name, "hub")
	table.insert(world.portals, returnPrompt)

	world.biomes[id] = {
		id = id,
		spawn = cf * CFrame.new(0, 4, -half + 24) * CFrame.Angles(0, math.pi, 0),
		center = cf.Position,
		radius = half + 10,
		orbPoints = ringPoints(rng, cf, 20, 80, 8, 2.5),
		wildPoints = ringPoints(rng, cf, 25, 70, 5, 0),
		nodePoints = ringPoints(rng, cf, 30, 90, 6, 0),
	}
	model.Parent = parent
end

function WorldBuilder.build()
	setupLighting()
	local folder = Instance.new("Folder")
	folder.Name = "World"
	folder.Parent = workspace

	local world = { biomes = {}, portals = {} }
	buildHub(folder, world)
	for _, id in ipairs(Biomes.Order) do
		buildBiome(folder, id, world)
	end

	local pickups = Instance.new("Folder")
	pickups.Name = "Pickups"
	pickups.Parent = folder
	world.pickupFolder = pickups
	world.folder = folder
	return world
end

-- "hub", a biome id, or nil (islands / void).
function WorldBuilder.zoneAt(world, position: Vector3): string?
	local flat = Vector3.new(position.X, 0, position.Z)
	if (flat - Vector3.new(world.hub.center.X, 0, world.hub.center.Z)).Magnitude <= world.hub.radius + 5 then
		return "hub"
	end
	for id, biome in pairs(world.biomes) do
		if (flat - Vector3.new(biome.center.X, 0, biome.center.Z)).Magnitude <= biome.radius * 1.42 then
			return id
		end
	end
	return nil
end

return WorldBuilder
