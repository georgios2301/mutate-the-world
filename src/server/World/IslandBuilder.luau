-- Builds the 8 floating player islands and updates their visual state (owner, pads,
-- expansions, theme, door, shield, alarm). Islands are built once at server start and
-- claimed/released as players join and leave.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local World = require(Shared.Config.World)
local Products = require(Shared.Config.Products)
local Heist = require(Shared.Config.Heist)

local Build = require(script.Parent.Build)

local IslandBuilder = {}

local LAYOUT = World.IslandLayout

function IslandBuilder.build(index: number, parent: Instance)
	local cf = World.islandCFrame(index)
	local color = World.IslandColors[index]
	local rng = Random.new(index * 7919)
	local function L(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end

	local model = Instance.new("Model")
	model.Name = "Island" .. index
	model:SetAttribute("IslandIndex", index)
	model:SetAttribute("OwnerUserId", 0)

	local island = {
		index = index,
		cframe = cf,
		color = color,
		model = model,
		grass = {},
		rock = {},
		trim = {},
		pads = {},
		alarmLights = {},
		wings = {},
		owner = nil,
	}

	local function grass(props)
		local p = Build.part(props)
		table.insert(island.grass, p)
		return p
	end
	local function rock(props)
		props.Material = props.Material or Enum.Material.Slate
		local p = Build.part(props)
		table.insert(island.rock, p)
		return p
	end
	local function trim(props)
		props.Material = Enum.Material.Neon
		local p = Build.part(props)
		table.insert(island.trim, p)
		return p
	end

	-- Floating rock body
	grass({ Name = "Grass", Size = Vector3.new(96, 2, 96), CFrame = L(0, -1, 0), Parent = model })
	rock({ Name = "Body", Size = Vector3.new(92, 10, 92), CFrame = L(0, -7, 0), Parent = model })
	rock({ Name = "Under1", Size = Vector3.new(66, 12, 66), CFrame = L(0, -17, 0) * CFrame.Angles(0, math.rad(20), 0), Parent = model })
	rock({ Name = "Under2", Size = Vector3.new(40, 12, 40), CFrame = L(0, -28, 0) * CFrame.Angles(0, math.rad(50), 0), Parent = model })
	rock({ Name = "Under3", Size = Vector3.new(18, 12, 18), CFrame = L(0, -38, 0) * CFrame.Angles(0, math.rad(10), 0), Parent = model })
	for _, edge in ipairs({ { 0, -48, 96, 1.2 }, { 0, 48, 96, 1.2 }, { -48, 0, 1.2, 96 }, { 48, 0, 1.2, 96 } }) do
		trim({ Name = "Edge", Size = Vector3.new(edge[3], 0.6, edge[4]), CFrame = L(edge[1], 0.05, edge[2]), Color = color, Parent = model })
	end

	-- Vault: floor, glass walls with neon trim, door gap in the front wall
	local vMin, vMax = LAYOUT.vaultMin, LAYOUT.vaultMax
	local vWidth = vMax.X - vMin.X
	local vDepth = vMax.Z - vMin.Z
	local vCenterZ = (vMin.Z + vMax.Z) / 2
	local wallH = vMax.Y
	island.vaultCFrame = L(0, wallH / 2, vCenterZ)
	island.vaultSize = Vector3.new(vWidth, wallH + 6, vDepth)

	Build.part({
		Name = "VaultFloor",
		Size = Vector3.new(vWidth, 0.4, vDepth),
		CFrame = L(0, 0.2, vCenterZ),
		Color = Color3.fromRGB(45, 38, 70),
		Material = Enum.Material.SmoothPlastic,
		Parent = model,
	})
	local wallProps = { Color = Color3.fromRGB(190, 220, 255), Material = Enum.Material.Glass, Transparency = 0.55, Parent = model }
	local function wall(size: Vector3, at: CFrame)
		local props = table.clone(wallProps)
		props.Name = "Wall"
		props.Size = size
		props.CFrame = at
		Build.part(props)
		trim({ Name = "WallTrim", Size = Vector3.new(size.X + 0.2, 0.5, size.Z + 0.2), CFrame = at * CFrame.new(0, size.Y / 2, 0), Color = color, Parent = model })
	end
	wall(Vector3.new(vWidth, wallH, 1), L(0, wallH / 2, vMax.Z + 0.5))
	wall(Vector3.new(1, wallH, vDepth), L(vMin.X - 0.5, wallH / 2, vCenterZ))
	wall(Vector3.new(1, wallH, vDepth), L(vMax.X + 0.5, wallH / 2, vCenterZ))
	local door = LAYOUT.doorHalfWidth
	local sideW = (vWidth / 2) - door
	wall(Vector3.new(sideW, wallH, 1), L(-(door + sideW / 2), wallH / 2, vMin.Z - 0.5))
	wall(Vector3.new(sideW, wallH, 1), L(door + sideW / 2, wallH / 2, vMin.Z - 0.5))

	local doorPart = Build.part({
		Name = "Door",
		Size = Vector3.new(door * 2, wallH, 0.8),
		CFrame = L(0, wallH / 2, vMin.Z - 0.5),
		Color = Color3.fromRGB(255, 70, 90),
		Material = Enum.Material.ForceField,
		Transparency = 0.2,
		Parent = model,
	})
	island.door = doorPart
	island.doorPrompt = Build.prompt(doorPart, "Lock / Unlock", "Vault Door", {
		name = "DoorPrompt",
		distance = 12,
		attributes = { Role = "Door", OwnerOnly = true },
	})
	island.breachPrompt = Build.prompt(doorPart, "Breach Door", "Locked Vault", {
		name = "BreachPrompt",
		hold = Heist.DoorBreachTime[1],
		distance = 10,
		attributes = { Role = "Breach", VisitorOnly = true },
	})

	for _, corner in ipairs({ { vMin.X, vMin.Z }, { vMax.X, vMin.Z }, { vMin.X, vMax.Z }, { vMax.X, vMax.Z } }) do
		local bulb = Build.part({
			Name = "AlarmLight",
			Shape = "Ball",
			Size = Vector3.new(1.6, 1.6, 1.6),
			CFrame = L(corner[1], wallH + 1, corner[2]),
			Color = Color3.fromRGB(80, 30, 40),
			Material = Enum.Material.Neon,
			CanCollide = false,
			Parent = model,
		})
		local light = Build.light(bulb, Color3.fromRGB(255, 40, 40), 4, 24)
		light.Enabled = false
		table.insert(island.alarmLights, bulb)
	end

	-- Display pads (15 positions; how many are active depends on upgrades)
	local padsFolder = Instance.new("Folder")
	padsFolder.Name = "Pads"
	padsFolder.Parent = model
	for slot = 1, World.MaxPadPositions do
		local lp = World.padLocalPosition(slot)
		local base = Build.disc(L(lp.X, 0.5, lp.Z), 1, 8, {
			Name = "Pad" .. slot,
			Color = Color3.fromRGB(60, 50, 95),
			Material = Enum.Material.SmoothPlastic,
			Parent = padsFolder,
		})
		local ring = Build.disc(L(lp.X, 0.55, lp.Z), 1.1, 8.6, {
			Name = "Ring",
			Color = color,
			Material = Enum.Material.Neon,
			CanCollide = false,
			Parent = base,
		})
		local _, lockLabel = Build.billboard(base, "🔒", { name = "Lock", offset = Vector3.new(0, 2.5, 0), size = UDim2.fromOffset(40, 40), maxDistance = 60 })
		island.pads[slot] = {
			part = base,
			ring = ring,
			lockLabel = lockLabel,
			standCFrame = L(lp.X, 1, lp.Z),
		}
	end

	-- Mutation chamber
	local ch = LAYOUT.chamber
	local chamberModel = Instance.new("Model")
	chamberModel.Name = "MutationChamber"
	local chamberBase = Build.disc(L(ch.X, 0.6, ch.Z), 1.2, 10, {
		Name = "Base",
		Color = Color3.fromRGB(50, 45, 70),
		Material = Enum.Material.Metal,
		Parent = chamberModel,
	})
	Build.disc(L(ch.X, 7, ch.Z), 12, 7, {
		Name = "Tube",
		Color = Color3.fromRGB(170, 230, 255),
		Material = Enum.Material.Glass,
		Transparency = 0.65,
		CanCollide = false,
		Parent = chamberModel,
	})
	Build.disc(L(ch.X, 13.6, ch.Z), 1.2, 9, { Name = "Cap", Color = Color3.fromRGB(50, 45, 70), Material = Enum.Material.Metal, Parent = chamberModel })
	local chamberRings = {}
	for _, y in ipairs({ 1.6, 12.6 }) do
		table.insert(
			chamberRings,
			Build.disc(L(ch.X, y, ch.Z), 0.5, 7.8, {
				Name = "Ring",
				Color = Color3.fromRGB(150, 90, 255),
				Material = Enum.Material.Neon,
				CanCollide = false,
				Parent = chamberModel,
			})
		)
	end
	local core = Build.part({
		Name = "Core",
		Shape = "Ball",
		Size = Vector3.new(3, 3, 3),
		CFrame = L(ch.X, 9, ch.Z),
		Color = Color3.fromRGB(150, 90, 255),
		Material = Enum.Material.Neon,
		Transparency = 1,
		CanCollide = false,
		Parent = chamberModel,
	})
	local coreLight = Build.light(core, Color3.fromRGB(150, 90, 255), 3, 20)
	coreLight.Enabled = false
	local _, chamberLabel = Build.billboard(chamberBase, "MUTATION CHAMBER", { offset = Vector3.new(0, 16, 0), size = UDim2.fromOffset(260, 60) })
	chamberModel.Parent = model
	island.chamber = {
		model = chamberModel,
		base = chamberBase,
		core = core,
		coreLight = coreLight,
		rings = chamberRings,
		label = chamberLabel,
		standCFrame = L(ch.X, 2.2, ch.Z),
	}
	island.chamberPrompt = Build.prompt(chamberBase, "Open", "Mutation Chamber", {
		name = "ChamberPrompt",
		distance = 12,
		attributes = { Role = "Chamber", OwnerOnly = true, OpensPanel = "Chamber" },
	})

	-- Coin collector
	local co = LAYOUT.collector
	local collectorBase = Build.disc(L(co.X, 0.75, co.Z), 1.5, 9, {
		Name = "Collector",
		Color = Color3.fromRGB(255, 205, 70),
		Material = Enum.Material.Metal,
		Parent = model,
	})
	for i = 0, 2 do
		Build.disc(L(co.X + (i - 1) * 1.6, 1.8 + i * 0.5, co.Z + (i % 2) * 1.2), 0.5, 2.4, {
			Name = "Coins",
			Color = Color3.fromRGB(255, 220, 90),
			Material = Enum.Material.Neon,
			CanCollide = false,
			Parent = collectorBase,
		})
	end
	local collectorGui, collectorLabel = Build.billboard(collectorBase, "COLLECTOR", {
		offset = Vector3.new(0, 6, 0),
		size = UDim2.fromOffset(240, 70),
		color = Color3.fromRGB(255, 225, 120),
	})
	island.collector = { part = collectorBase, gui = collectorGui, label = collectorLabel }
	island.collectorPrompt = Build.prompt(collectorBase, "Collect Coins", "Collector", {
		name = "CollectPrompt",
		distance = 12,
		attributes = { Role = "Collector", OwnerOnly = true },
	})

	-- Consoles
	local function console(name: string, at: Vector3, screenColor: Color3, text: string)
		local body = Build.part({
			Name = name,
			Size = Vector3.new(4, 4, 2.4),
			CFrame = L(at.X, 2, at.Z),
			Color = Color3.fromRGB(55, 48, 80),
			Material = Enum.Material.Metal,
			Parent = model,
		})
		Build.part({
			Name = "Screen",
			Size = Vector3.new(3.4, 2.2, 0.2),
			CFrame = L(at.X, 3, at.Z - 1.25) * CFrame.Angles(math.rad(-15), 0, 0),
			Color = screenColor,
			Material = Enum.Material.Neon,
			CanCollide = false,
			Parent = body,
		})
		Build.billboard(body, text, { offset = Vector3.new(0, 4.5, 0), size = UDim2.fromOffset(180, 40), color = screenColor })
		return body
	end
	local upgrades = console("UpgradeTerminal", LAYOUT.upgradeTerminal, Color3.fromRGB(62, 230, 255), "UPGRADES")
	island.upgradePrompt = Build.prompt(upgrades, "Open", "Upgrade Terminal", {
		name = "UpgradePrompt",
		attributes = { Role = "Upgrades", OwnerOnly = true, OpensPanel = "Shop", Tab = "upgrades" },
	})
	local security = console("SecurityConsole", LAYOUT.securityConsole, Color3.fromRGB(255, 154, 60), "SECURITY")
	island.securityPrompt = Build.prompt(security, "Open", "Security Console", {
		name = "SecurityPrompt",
		attributes = { Role = "Security", OwnerOnly = true, OpensPanel = "Defense" },
	})

	-- Hub portal pad (everyone)
	local hp = LAYOUT.hubPad
	local hubPad = Build.disc(L(hp.X, 0.3, hp.Z), 0.6, 8, {
		Name = "HubPortal",
		Color = Color3.fromRGB(150, 90, 255),
		Material = Enum.Material.Neon,
		Parent = model,
	})
	Build.billboard(hubPad, "⇄ HUB", { offset = Vector3.new(0, 3.5, 0), size = UDim2.fromOffset(120, 36) })
	island.hubPrompt = Build.prompt(hubPad, "Travel", "Hub Portal", { name = "HubPrompt", attributes = { Role = "Hub" } })

	-- Owner sign above the dock
	local signAnchor = Build.part({
		Name = "SignAnchor",
		Size = Vector3.new(1, 1, 1),
		CFrame = L(0, 16, -46),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		Parent = model,
	})
	local _, signLabel = Build.billboard(signAnchor, "Unclaimed Island", {
		size = UDim2.fromOffset(420, 70),
		offset = Vector3.new(0, 0, 0),
		maxDistance = 600,
		color = color,
	})
	island.signLabel = signLabel

	-- Shield dome (visual; the server rejects heists while it is up)
	island.shield = Build.part({
		Name = "Shield",
		Shape = "Ball",
		Size = Vector3.new(150, 150, 150),
		CFrame = L(0, 0, 6),
		Color = color,
		Material = Enum.Material.ForceField,
		Transparency = 1,
		CanCollide = false,
		CanTouch = false,
		CanQuery = false,
		CastShadow = false,
		Parent = model,
	})

	-- Expansion wings (shown when the island is upgraded, ghosted otherwise)
	for side = -1, 1, 2 do
		local wing = { parts = {}, ghost = nil }
		local x = side * 60
		local g = grass({ Name = "WingGrass", Size = Vector3.new(24, 2, 60), CFrame = L(x, -1, 10), Parent = model })
		local r = rock({ Name = "WingRock", Size = Vector3.new(22, 14, 56), CFrame = L(x, -9, 10) * CFrame.Angles(0, 0, math.rad(side * -8)), Parent = model })
		table.insert(wing.parts, g)
		table.insert(wing.parts, r)
		for i = 1, 3 do
			local tree = Build.tree(model, L(x + rng:NextNumber(-6, 6), 0, -10 + i * 14), rng:NextNumber(0.7, 1.1), Color3.fromRGB(90, 200, 120), Color3.fromRGB(110, 75, 50), rng)
			for _, p in ipairs(tree:GetChildren()) do
				table.insert(wing.parts, p)
			end
		end
		local ghost = Build.part({
			Name = "ExpansionGhost",
			Size = Vector3.new(24, 2, 60),
			CFrame = L(x, -1, 10),
			Color = color,
			Material = Enum.Material.ForceField,
			Transparency = 0.5,
			CanCollide = false,
			Parent = model,
		})
		Build.billboard(ghost, "EXPANSION\n<font size='14'>Upgrade Island Expansion</font>", {
			offset = Vector3.new(0, 6, 0),
			size = UDim2.fromOffset(200, 60),
			maxDistance = 90,
		})
		wing.ghost = ghost
		island.wings[side == -1 and "left" or "right"] = wing
	end

	-- Decoration
	for _, corner in ipairs({ { -40, -40 }, { 40, -40 }, { -42, 40 }, { 42, 40 } }) do
		Build.tree(model, L(corner[1], 0, corner[2]), rng:NextNumber(0.8, 1.2), Color3.fromRGB(120, 210, 120), Color3.fromRGB(110, 75, 50), rng)
	end
	for _ = 1, 4 do
		Build.rock(model, L(rng:NextNumber(-44, 44), 0, rng:NextNumber(-46, -30)), rng:NextNumber(1.5, 3), Color3.fromRGB(130, 120, 150), rng)
	end

	island.ownerSpawn = L(LAYOUT.ownerSpawn.X, LAYOUT.ownerSpawn.Y, LAYOUT.ownerSpawn.Z)
	island.dock = L(LAYOUT.dock.X, LAYOUT.dock.Y, LAYOUT.dock.Z) * CFrame.Angles(0, math.pi, 0)

	local creatureFolder = Instance.new("Folder")
	creatureFolder.Name = "Creatures"
	creatureFolder.Parent = model
	island.creatureFolder = creatureFolder

	model.Parent = parent
	IslandBuilder.applyTheme(island, "default")
	IslandBuilder.applyLevel(island, 1, 0, 0)
	IslandBuilder.setOwner(island, nil)
	return island
end

-- True if a world position is inside the island's vault walls.
function IslandBuilder.isInVault(island, position: Vector3): boolean
	local lp = island.cframe:PointToObjectSpace(position)
	local vMin, vMax = LAYOUT.vaultMin, LAYOUT.vaultMax
	return lp.X >= vMin.X and lp.X <= vMax.X and lp.Z >= vMin.Z and lp.Z <= vMax.Z and lp.Y >= -3 and lp.Y <= vMax.Y + 8
end

function IslandBuilder.isOnIsland(island, position: Vector3): boolean
	local lp = island.cframe:PointToObjectSpace(position)
	return math.abs(lp.X) <= World.IslandZoneRadius and math.abs(lp.Z) <= World.IslandHalfSize + 4 and lp.Y > -20 and lp.Y < 60
end

function IslandBuilder.setOwner(island, player: Player?)
	island.owner = player
	island.model:SetAttribute("OwnerUserId", player and player.UserId or 0)
	island.model:SetAttribute("OwnerName", player and player.DisplayName or "")
	local colorName = World.IslandColorNames[island.index]
	if player then
		island.signLabel.Text = string.format("%s's Island\n<font size='18'>%s Isle</font>", player.DisplayName, colorName)
	else
		island.signLabel.Text = string.format("Unclaimed Island\n<font size='18'>%s Isle</font>", colorName)
	end
	local owned = player ~= nil
	for _, prompt in ipairs({ island.doorPrompt, island.breachPrompt, island.chamberPrompt, island.collectorPrompt, island.upgradePrompt, island.securityPrompt }) do
		prompt.Enabled = owned
	end
	island.collector.label.Text = if owned then "COLLECTOR" else ""
	IslandBuilder.setDoor(island, true)
	IslandBuilder.setShield(island, false)
	IslandBuilder.setChamberActive(island, false, nil)
end

-- padCount = active pads, maxPads = pads possible at this island level (+ pass bonus)
function IslandBuilder.applyLevel(island, islandLevel: number, padCount: number, maxPads: number)
	for slot, pad in pairs(island.pads) do
		local active = slot <= padCount
		local buyable = slot <= maxPads
		pad.part.Transparency = if active then 0 elseif buyable then 0.6 else 1
		pad.ring.Transparency = if active then 0 elseif buyable then 0.85 else 1
		pad.part.CanCollide = buyable
		pad.lockLabel.Parent.Enabled = buyable and not active
	end
	local showLeft = islandLevel >= 2
	local showRight = islandLevel >= 3
	for side, wing in pairs(island.wings) do
		local shown = if side == "left" then showLeft else showRight
		for _, p in ipairs(wing.parts) do
			p.Transparency = if shown then 0 else 1
			p.CanCollide = shown
		end
		wing.ghost.Transparency = if shown then 1 else 0.6
		local gui = wing.ghost:FindFirstChildOfClass("BillboardGui")
		if gui then
			gui.Enabled = not shown
		end
	end
end

function IslandBuilder.applyTheme(island, themeId: string)
	local theme = Products.Themes[themeId] or Products.Themes.default
	local material = Enum.Material[theme.material] or Enum.Material.Grass
	for _, p in ipairs(island.grass) do
		p.Color = theme.grass
		p.Material = material
	end
	for _, p in ipairs(island.rock) do
		p.Color = theme.rock
	end
	local trimColor = theme.trim or island.color
	for _, p in ipairs(island.trim) do
		p.Color = trimColor
	end
end

function IslandBuilder.setDoor(island, locked: boolean)
	local door = island.door
	door.CanCollide = locked
	door.Transparency = if locked then 0.2 else 0.85
	door.Color = if locked then Color3.fromRGB(255, 70, 90) else Color3.fromRGB(90, 255, 140)
	island.model:SetAttribute("DoorLocked", locked)
	island.breachPrompt.Enabled = locked and island.owner ~= nil
end

function IslandBuilder.setShield(island, on: boolean)
	island.shield.Transparency = if on then 0.35 else 1
	island.model:SetAttribute("Shielded", on)
end

function IslandBuilder.setAlarm(island, on: boolean)
	for _, bulb in ipairs(island.alarmLights) do
		bulb.Color = if on then Color3.fromRGB(255, 40, 40) else Color3.fromRGB(80, 30, 40)
		local light = bulb:FindFirstChildOfClass("PointLight")
		if light then
			light.Enabled = on
		end
	end
	island.model:SetAttribute("Alarm", on)
end

function IslandBuilder.setChamberActive(island, active: boolean, color: Color3?)
	local chamber = island.chamber
	chamber.core.Transparency = if active then 0.15 else 1
	chamber.coreLight.Enabled = active
	local c = color or Color3.fromRGB(150, 90, 255)
	chamber.core.Color = c
	chamber.coreLight.Color = c
	for _, ring in ipairs(chamber.rings) do
		ring.Color = if active then c else Color3.fromRGB(150, 90, 255)
	end
	island.model:SetAttribute("ChamberActive", active)
end

return IslandBuilder
