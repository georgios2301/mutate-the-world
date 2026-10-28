-- Runs the mutation chamber: start requests, timers, completion, effects and resume after rejoin.
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Creatures = require(Shared.Config.Creatures)
local Mutations = require(Shared.Config.Mutations)
local Rarity = require(Shared.Config.Rarity)
local Format = require(Shared.Util.Format)

local Core = script.Parent.Parent.Core
local MutationLogic = require(Core.MutationLogic)
local Validate = require(Core.Validate)

local MutationService = {}
local S

local lastLabel = {} -- [userId] = text

local function now(): number
	return workspace:GetServerTimeNow()
end

local function setChamberLabel(player: Player, text: string)
	local island = S.Island.get(player)
	if island and lastLabel[player.UserId] ~= text then
		lastLabel[player.UserId] = text
		island.chamber.label.Text = text
	end
end

local function updateLabel(player: Player, profile)
	local job = profile.activeMutation
	if job then
		local remaining = math.max(0, job.endsAt - now())
		setChamberLabel(player, "MUTATION CHAMBER\n<font size='18' color='#7cff4f'>Mutating... " .. Format.time(remaining) .. "</font>")
	else
		setChamberLabel(player, "MUTATION CHAMBER\n<font size='18' color='#3ee6ff'>Ready</font>")
	end
end

local function burst(player: Player, color: Color3)
	local island = S.Island.get(player)
	if not island then
		return
	end
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 1
	emitter.Speed = NumberRange.new(12, 22)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Lifetime = NumberRange.new(0.6, 1.2)
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 0) })
	emitter.Rate = 0
	emitter.Parent = island.chamber.core
	emitter:Emit(45)
	Debris:AddItem(emitter, 3)
end

local function finish(player: Player, profile, offline: boolean)
	local result = MutationLogic.complete(profile, now())
	if not result then
		return
	end
	S.Data.markDirty(player)
	S.Creature.refreshIsland(player)
	if result.refunded then
		S.Net.notify(player, "The mutation fizzled and your resources were refunded.", "warn")
		S.State.push(player)
		return
	end
	local creature = result.creature
	local species = Creatures.Species[creature.species]
	local mutation = Mutations.Types[creature.mutation]
	local color = if mutation.color then mutation.color else Rarity.color(species.rarity)
	burst(player, color)
	S.Net.event("MutationEvent"):FireClient(player, "completed", {
		creature = {
			id = creature.id,
			species = creature.species,
			mutation = creature.mutation,
			level = creature.level,
			seed = creature.seed,
		},
		kind = result.kind,
		newRecipe = result.newRecipe,
		newSpecies = result.newSpecies,
		newCombo = result.newCombo,
		xp = result.xp,
		leveledUp = result.leveledUp,
		level = result.level,
		offline = offline,
	})
	S.Discovery.onMutation(player, result)
	S.Tutorial.event(player, "mutation")
	S.State.push(player)
end

function MutationService.onPlayerReady(player: Player, profile)
	if profile.activeMutation then
		if now() >= profile.activeMutation.endsAt then
			task.delay(3, function()
				if player.Parent then
					finish(player, profile, true)
				end
			end)
		end
	end
	updateLabel(player, profile)
end

function MutationService.init(services)
	S = services
end

function MutationService.start()
	S.Net.on("StartMutation", { rate = { 4, 2 } }, function(player, profile, creatureId, ingredientId)
		if not Validate.id(creatureId) or not Validate.oneOf(ingredientId, Mutations.Ingredients) then
			return false, "Invalid request"
		end
		local island = S.Island.get(player)
		if not island or not S.Island.isNear(player, island) then
			return false, "You need to be at your island's Mutation Chamber"
		end
		local ok, job = MutationLogic.start(profile, creatureId, ingredientId, now())
		if not ok then
			return false, job
		end
		S.Creature.refreshIsland(player)
		updateLabel(player, profile)
		S.Net.event("MutationEvent"):FireClient(player, "started", job)
		return true, "Mutation started!"
	end)

	task.spawn(function()
		while true do
			task.wait(0.5)
			local t = now()
			for _, player in ipairs(Players:GetPlayers()) do
				local profile = S.Data.get(player)
				if profile and S.Island.get(player) then
					local job = profile.activeMutation
					if job and t >= job.endsAt then
						finish(player, profile, false)
					end
					updateLabel(player, profile)
				end
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastLabel[player.UserId] = nil
	end)
end

return MutationService
