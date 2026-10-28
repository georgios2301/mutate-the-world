-- Keeps each island's display pads in sync with the owner's placed creatures, shows the
-- creature inside the mutation chamber, and owns the creature inventory actions.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Creatures = require(Shared.Config.Creatures)
local Mutations = require(Shared.Config.Mutations)
local Rarity = require(Shared.Config.Rarity)
local Rules = require(Shared.Rules)
local Format = require(Shared.Util.Format)
local CreatureModels = require(Shared.CreatureModels)

local Core = script.Parent.Parent.Core
local Inventory = require(Core.Inventory)
local EconomyLogic = require(Core.EconomyLogic)
local Validate = require(Core.Validate)

local Build = require(script.Parent.Parent.World.Build)

local CreatureService = {}
local S

local displayed = {} -- [userId] = { [creatureId] = { model, key, protectedUntil, label } }
local chamberModels = {} -- [userId] = Model
local rates = {} -- [userId] = cached income per second

local function now(): number
	return workspace:GetServerTimeNow()
end

local function auraOf(profile): string?
	local aura = profile.cosmetics.aura
	return if aura ~= "" then aura else nil
end

local function displayKey(creature, profile): string
	return table.concat({ creature.species, creature.mutation, creature.level, creature.slot or 0, auraOf(profile) or "" }, "|")
end

local function labelText(creature, protected: boolean): string
	local species = Creatures.Species[creature.species]
	local color = Rarity.color(species.rarity):ToHex()
	local name = Mutations.displayName(species.name, creature.mutation)
	local shield = if protected then " 🛡" else ""
	return string.format(
		"<font color='#%s'>%s</font>%s\n<font size='14'>%s · Lv %d · %s/s</font>",
		color,
		name,
		shield,
		species.rarity,
		creature.level,
		Format.number(Rules.creatureIncome(creature))
	)
end

local function spawnOnPad(player: Player, island, creature, profile)
	local pad = island.pads[creature.slot]
	if not pad then
		return nil
	end
	local model = CreatureModels.build({
		species = creature.species,
		mutation = creature.mutation,
		level = creature.level,
		seed = creature.seed,
		aura = auraOf(profile),
	})
	model:PivotTo(pad.standCFrame)
	model:SetAttribute("CreatureId", creature.id)
	model:SetAttribute("OwnerUserId", player.UserId)
	CollectionService:AddTag(model, "Creature")
	local root = model.PrimaryPart :: BasePart
	local t = now()
	local protected = creature.starter or creature.protectedUntil > t
	local _, label = Build.billboard(root, labelText(creature, protected), {
		offset = Vector3.new(0, CreatureModels.height(model) + 2, 0),
		size = UDim2.fromOffset(200, 56),
		maxDistance = 70,
	})
	if not creature.starter and Rules.isStealableSpecies(creature.species) then
		Build.prompt(root, "Steal", Creatures.Species[creature.species].name, {
			name = "StealPrompt",
			hold = 0.6,
			distance = 10,
			key = Enum.KeyCode.F,
			attributes = { Role = "Steal", CreatureId = creature.id, OwnerUserId = player.UserId },
		}).Triggered:Connect(function(attacker)
			S.Heist.tryStart(attacker, player, creature.id)
		end)
	end
	model.Parent = island.creatureFolder
	return {
		model = model,
		key = displayKey(creature, profile),
		protectedUntil = if creature.starter then 0 else creature.protectedUntil,
		label = label,
	}
end

local function refreshChamber(player: Player, island, profile)
	local job = profile.activeMutation
	local current = chamberModels[player.UserId]
	local wantId = job and job.creatureId
	if current and current:GetAttribute("CreatureId") ~= wantId then
		current:Destroy()
		chamberModels[player.UserId] = nil
		current = nil
	end
	if wantId and not current then
		local creature = profile.creatures[wantId]
		if creature then
			local model = CreatureModels.build({ species = creature.species, mutation = creature.mutation, level = 1, seed = creature.seed }, { effects = false })
			model:ScaleTo(0.75)
			model:PivotTo(island.chamber.standCFrame)
			model:SetAttribute("CreatureId", wantId)
			CollectionService:AddTag(model, "Creature")
			model.Parent = island.creatureFolder
			chamberModels[player.UserId] = model
		end
	end
	local resultColor = nil
	if job then
		local m = Mutations.Types[job.resultMutation]
		resultColor = if m and m.color then m.color else Rarity.color(Creatures.Species[job.resultSpecies].rarity)
	end
	S.Island.setChamberVisual(player, job ~= nil, resultColor)
end

-- Syncs pad models with data. Cheap when nothing changed (keys compared).
function CreatureService.refreshIsland(player: Player)
	local island = S.Island.get(player)
	local profile = S.Data.get(player)
	if not island or not profile then
		return
	end
	local entry = displayed[player.UserId]
	if not entry then
		entry = {}
		displayed[player.UserId] = entry
	end
	local padCount = Inventory.padCount(profile)
	local wanted = {}
	for id, creature in pairs(profile.creatures) do
		if creature.slot and creature.slot <= padCount then
			wanted[id] = creature
		end
	end
	for id, shown in pairs(entry) do
		local creature = wanted[id]
		if not creature or shown.key ~= displayKey(creature, profile) then
			shown.model:Destroy()
			entry[id] = nil
		end
	end
	for id, creature in pairs(wanted) do
		if not entry[id] then
			entry[id] = spawnOnPad(player, island, creature, profile)
		end
	end
	refreshChamber(player, island, profile)
	rates[player.UserId] = Inventory.incomePerSecond(profile)
end

function CreatureService.getRate(player: Player): number
	return rates[player.UserId] or 0
end

function CreatureService.getModel(ownerUserId: number, creatureId: string): Model?
	local entry = displayed[ownerUserId]
	local shown = entry and entry[creatureId]
	return shown and shown.model
end

-- Called once a second by the economy loop: flips the 🛡 marker when protection ends.
function CreatureService.updateProtectionLabels(player: Player, profile)
	local entry = displayed[player.UserId]
	if not entry then
		return
	end
	local t = now()
	for id, shown in pairs(entry) do
		if shown.protectedUntil > 0 and t >= shown.protectedUntil then
			shown.protectedUntil = 0
			local creature = profile.creatures[id]
			if creature then
				shown.label.Text = labelText(creature, false)
			end
		end
	end
end

function CreatureService.clear(player: Player)
	displayed[player.UserId] = nil
	rates[player.UserId] = nil
	local chamber = chamberModels[player.UserId]
	if chamber then
		chamber:Destroy()
		chamberModels[player.UserId] = nil
	end
end

function CreatureService.init(services)
	S = services
end

function CreatureService.start()
	S.Net.on("PlaceCreature", { rate = { 8, 4 } }, function(player, profile, creatureId, slot)
		if not Validate.id(creatureId) then
			return false, "Bad creature"
		end
		if slot ~= nil and not Validate.int(slot, 1, 64) then
			return false, "Bad pad"
		end
		local ok, result = Inventory.place(profile, creatureId, slot)
		if not ok then
			return false, result
		end
		CreatureService.refreshIsland(player)
		return true
	end)

	S.Net.on("UnplaceCreature", { rate = { 8, 4 } }, function(player, profile, creatureId)
		if not Validate.id(creatureId) then
			return false, "Bad creature"
		end
		local ok, err = Inventory.unplace(profile, creatureId)
		if not ok then
			return false, err
		end
		CreatureService.refreshIsland(player)
		return true
	end)

	S.Net.on("LevelUpCreature", { rate = { 6, 3 } }, function(player, profile, creatureId)
		if not Validate.id(creatureId) then
			return false, "Bad creature"
		end
		local ok, result = EconomyLogic.levelUpCreature(profile, creatureId)
		if not ok then
			return false, result
		end
		CreatureService.refreshIsland(player)
		return true, "Level up! Now level " .. result.level
	end)

	S.Net.on("ReleaseCreature", { rate = { 4, 1 } }, function(player, profile, creatureId)
		if not Validate.id(creatureId) then
			return false, "Bad creature"
		end
		local ok, result = EconomyLogic.releaseCreature(profile, creatureId)
		if not ok then
			return false, result
		end
		CreatureService.refreshIsland(player)
		return true, "Released into the wild (+" .. result.dna .. " DNA)"
	end)

	Players.PlayerRemoving:Connect(function(player)
		CreatureService.clear(player)
	end)
end

return CreatureService
