-- World resources: DNA orbs (touch), crystal nodes (hold prompt) and wild creatures (capture).
-- Every pickup is validated on the server: alive character, distance, biome unlocked,
-- per-node availability and per-player cooldowns.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Biomes = require(Shared.Config.Biomes)
local Creatures = require(Shared.Config.Creatures)
local Economy = require(Shared.Config.Economy)
local Heist = require(Shared.Config.Heist)
local Rarity = require(Shared.Config.Rarity)
local CreatureModels = require(Shared.CreatureModels)

local Core = script.Parent.Parent.Core
local Wallet = require(Core.Wallet)
local Inventory = require(Core.Inventory)
local EconomyLogic = require(Core.EconomyLogic)

local Build = require(script.Parent.Parent.World.Build)

local ResourceService = {}
local S

local rng = Random.new()
local orbCooldown = {} -- [userId] = time of last orb
local captureCooldown = {} -- [userId] = time

local function now(): number
	return workspace:GetServerTimeNow()
end

local function rootNear(player: Player, position: Vector3, maxDistance: number): boolean
	local root = S.Travel.getRoot(player)
	return root ~= nil and (root.Position - position).Magnitude <= maxDistance
end

local function zoneUnlocked(profile, zone: string): boolean
	return zone == "hub" or EconomyLogic.isBiomeUnlocked(profile, zone)
end

-- DNA orbs ---------------------------------------------------------------------

local function spawnOrb(cf: CFrame, zone: string, amount: number)
	local orb = Build.part({
		Name = "DnaOrb",
		Shape = "Ball",
		Size = Vector3.new(2.2, 2.2, 2.2),
		CFrame = cf,
		Color = Color3.fromRGB(255, 120, 200),
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = S.World.pickupFolder,
	})
	Build.light(orb, Color3.fromRGB(255, 120, 200), 1, 8)
	CollectionService:AddTag(orb, "Bobbing")
	local available = true
	orb.Touched:Connect(function(hit)
		if not available then
			return
		end
		local character = hit.Parent
		local player = character and Players:GetPlayerFromCharacter(character)
		if not player then
			return
		end
		local profile = S.Data.get(player)
		if not profile or not zoneUnlocked(profile, zone) or not rootNear(player, orb.Position, 10) then
			return
		end
		local t = now()
		if (orbCooldown[player.UserId] or 0) + 0.25 > t then
			return
		end
		orbCooldown[player.UserId] = t
		available = false
		orb.Transparency = 1
		Wallet.add(profile, { dna = amount })
		S.Tutorial.event(player, "dna", amount)
		S.Data.markDirty(player)
		S.State.push(player)
		S.Net.event("Notify"):FireClient(player, { text = "+" .. amount .. " DNA", kind = "pickup" })
		task.delay(Economy.Pickups.orbRespawn, function()
			available = true
			orb.Transparency = 0
		end)
	end)
end

-- Crystal nodes ----------------------------------------------------------------

local function spawnNode(cf: CFrame, zone: string, currency: string, color: Color3, respawn: number)
	local model, shards = Build.crystal(S.World.pickupFolder, cf, color, 1, rng)
	model.Name = "CrystalNode"
	local currencyInfo = Economy.CurrencyInfo[currency]
	local prompt = Build.prompt(shards[1], "Harvest", currencyInfo.name, {
		name = "HarvestPrompt",
		hold = 1,
		distance = 10,
		attributes = { Role = "Harvest" },
	})
	local available = true
	prompt.Triggered:Connect(function(player)
		if not available then
			return
		end
		local profile = S.Data.get(player)
		if not profile then
			return
		end
		if not zoneUnlocked(profile, zone) then
			S.Net.notify(player, "Unlock this biome first", "warn")
			return
		end
		if not rootNear(player, shards[1].Position, 14) then
			return
		end
		available = false
		prompt.Enabled = false
		for _, shard in ipairs(shards) do
			shard.Transparency = 0.85
		end
		local amount = if zone == "hub" then 1 else (Biomes.Defs[zone] and Biomes.Defs[zone].crystalYield or 1)
		Wallet.add(profile, { [currency] = amount })
		if currency == "ice" then
			S.Tutorial.event(player, "ice", amount)
		end
		S.Data.markDirty(player)
		S.State.push(player)
		S.Net.event("Notify"):FireClient(player, { text = "+" .. amount .. " " .. currencyInfo.name, kind = "pickup" })
		task.delay(respawn, function()
			available = true
			prompt.Enabled = true
			for _, shard in ipairs(shards) do
				shard.Transparency = 0.1
			end
		end)
	end)
end

-- Wild creatures ---------------------------------------------------------------

local function rollSpecies(spawnTable): string
	local total = 0
	for _, entry in ipairs(spawnTable) do
		total += entry.weight
	end
	local roll = rng:NextNumber(0, total)
	for _, entry in ipairs(spawnTable) do
		roll -= entry.weight
		if roll <= 0 then
			return entry.species
		end
	end
	return spawnTable[1].species
end

local function spawnWild(cf: CFrame, zone: string, spawnTable)
	local current: Model? = nil

	local function respawn()
		local speciesId = rollSpecies(spawnTable)
		local species = Creatures.Species[speciesId]
		local seed = rng:NextInteger(1, 2 ^ 30)
		local model = CreatureModels.build({ species = speciesId, mutation = "none", level = 1, seed = seed })
		model:PivotTo(cf * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0) + Vector3.new(0, 0.2, 0))
		CollectionService:AddTag(model, "Creature")
		local cost = Rarity.Info[species.rarity].captureDna
		local root = model.PrimaryPart :: BasePart
		Build.billboard(root, string.format("<font color='#%s'>Wild %s</font>\n<font size='14'>%s · %d DNA</font>", Rarity.color(species.rarity):ToHex(), species.name, species.rarity, cost), {
			offset = Vector3.new(0, CreatureModels.height(model) + 2, 0),
			size = UDim2.fromOffset(200, 50),
			maxDistance = 60,
		})
		local prompt = Build.prompt(root, "Capture (" .. cost .. " DNA)", species.name, {
			name = "CapturePrompt",
			hold = 1.2,
			distance = 12,
			attributes = { Role = "Capture" },
		})
		local taken = false
		prompt.Triggered:Connect(function(player)
			if taken then
				return
			end
			local profile = S.Data.get(player)
			if not profile then
				return
			end
			if not zoneUnlocked(profile, zone) then
				S.Net.notify(player, "Unlock this biome first", "warn")
				return
			end
			if not rootNear(player, root.Position, 16) then
				return
			end
			local t = now()
			if (captureCooldown[player.UserId] or 0) + 2 > t then
				return
			end
			if not Inventory.hasSpace(profile) then
				S.Net.notify(player, "Creature storage is full! Upgrade storage or release a creature.", "warn")
				return
			end
			local ok, err = Wallet.spend(profile, { dna = cost })
			if not ok then
				S.Net.notify(player, err .. " (" .. cost .. " DNA needed)", "warn")
				return
			end
			captureCooldown[player.UserId] = t
			taken = true
			local creature = Inventory.newCreature(speciesId, {
				now = t,
				seed = seed,
				source = "wild",
				protection = Heist.NewCreatureProtection,
			})
			local _, discovery = Inventory.add(profile, creature)
			profile.stats.captures += 1
			EconomyLogic.addXP(profile, Economy.XP.capture + (if discovery.newSpecies then Economy.XP.newSpecies else 0))
			local placed = Inventory.place(profile, creature.id)
			S.Creature.refreshIsland(player)
			S.Data.markDirty(player)
			S.State.push(player)
			S.Net.notify(player, "Captured " .. species.name .. "!" .. (if placed then " It's earning on your island." else " Sent to storage."), "success")
			if discovery.newSpecies then
				S.Discovery.announceSpecies(player, creature)
			end
			model:Destroy()
			current = nil
			task.delay(rng:NextNumber(Economy.Pickups.wildRespawnMin, Economy.Pickups.wildRespawnMax), respawn)
		end)
		model.Parent = S.World.pickupFolder
		current = model
	end

	respawn()
	return function()
		return current
	end
end

function ResourceService.init(services)
	S = services
end

function ResourceService.start()
	local world = S.World
	for _, cf in ipairs(world.hub.orbPoints) do
		spawnOrb(cf, "hub", Economy.Pickups.hubOrbDna)
	end
	for _, cf in ipairs(world.hub.nodePoints) do
		spawnNode(cf, "hub", "ice", Color3.fromRGB(150, 220, 255), Economy.Pickups.hubNodeRespawn)
	end
	for _, cf in ipairs(world.hub.wildPoints) do
		spawnWild(cf, "hub", Biomes.HubWild)
	end
	for id, biome in pairs(world.biomes) do
		local def = Biomes.Defs[id]
		for _, cf in ipairs(biome.orbPoints) do
			spawnOrb(cf, id, Economy.Pickups.biomeOrbDna)
		end
		for _, cf in ipairs(biome.nodePoints) do
			spawnNode(cf, id, def.crystal, def.color, Economy.Pickups.nodeRespawn)
		end
		for _, cf in ipairs(biome.wildPoints) do
			spawnWild(cf, id, def.wild)
		end
	end

	Players.PlayerRemoving:Connect(function(player)
		orbCooldown[player.UserId] = nil
		captureCooldown[player.UserId] = nil
	end)
end

return ResourceService
