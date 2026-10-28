-- Client-side world presentation:
--   * shows only the prompts that make sense for this player (owner vs visitor)
--   * lets the owner walk through their own vault door (local collision only)
--   * idle bobbing for creatures/orbs, reduced-effects mode, alarm sound
--   * opens UI panels from ProximityPrompts tagged with OpensPanel
-- Everything here is cosmetic; the server re-validates every action.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local TweenService = game:GetService("TweenService")

local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local Sound = require(Client.UI.Sound)

local WorldController = {}
local LocalPlayer = Players.LocalPlayer

local reducedEffects = false
local Panels

local function islandOf(instance: Instance): Instance?
	local current: Instance? = instance
	while current and current ~= workspace do
		if current:GetAttribute("IslandIndex") then
			return current
		end
		current = current.Parent
	end
	return nil
end

-- Decides whether this client should see a prompt.
local function wantPrompt(prompt: ProximityPrompt): boolean?
	local me = LocalPlayer.UserId
	local creatureOwner = prompt:GetAttribute("OwnerUserId")
	if creatureOwner ~= nil then
		return creatureOwner ~= me -- steal prompts: never on your own creatures
	end
	local island = islandOf(prompt)
	if not island then
		return nil -- not an island prompt: leave it alone
	end
	local owner = island:GetAttribute("OwnerUserId")
	if prompt:GetAttribute("OwnerOnly") then
		return owner == me
	end
	if prompt:GetAttribute("VisitorOnly") then
		return owner ~= me
	end
	return nil
end

local function applyPrompt(prompt: ProximityPrompt)
	local want = wantPrompt(prompt)
	if want == false and prompt.Enabled then
		prompt.Enabled = false
	end
end

local function watchPrompt(prompt: ProximityPrompt)
	applyPrompt(prompt)
	-- The server may re-enable prompts (e.g. door relocks); re-apply our local filter.
	prompt:GetPropertyChangedSignal("Enabled"):Connect(function()
		applyPrompt(prompt)
	end)
end

local function applyDoor(island: Instance)
	local door = island:FindFirstChild("Door") :: BasePart?
	if door and island:GetAttribute("OwnerUserId") == LocalPlayer.UserId and door.CanCollide then
		door.CanCollide = false
	end
end

local function watchIsland(island: Instance)
	local door = island:FindFirstChild("Door") :: BasePart?
	if door then
		door:GetPropertyChangedSignal("CanCollide"):Connect(function()
			applyDoor(island)
		end)
	end
	island:GetAttributeChangedSignal("OwnerUserId"):Connect(function()
		for _, d in ipairs(island:GetDescendants()) do
			if d:IsA("ProximityPrompt") then
				applyPrompt(d)
			end
		end
		applyDoor(island)
	end)
	island:GetAttributeChangedSignal("Alarm"):Connect(function()
		if island:GetAttribute("Alarm") and island:GetAttribute("OwnerUserId") == LocalPlayer.UserId then
			Sound.play("Alarm")
		end
	end)
	applyDoor(island)
end

local function bob(target: Instance)
	local part: BasePart? = nil
	if target:IsA("Model") then
		part = target.PrimaryPart
	elseif target:IsA("BasePart") then
		part = target
	end
	if not part or not part.Anchored then
		return
	end
	local base = part.CFrame
	local rng = Random.new()
	task.delay(rng:NextNumber(0, 1.2), function()
		if part.Parent then
			local tween = TweenService:Create(part, TweenInfo.new(rng:NextNumber(1.1, 1.6), Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
				CFrame = base * CFrame.new(0, 0.6, 0) * CFrame.Angles(0, math.rad(rng:NextNumber(-12, 12)), 0),
			})
			tween:Play()
			part.AncestryChanged:Connect(function()
				if not part:IsDescendantOf(workspace) then
					tween:Cancel()
				end
			end)
		end
	end)
end

local function applyEffect(inst: Instance)
	if inst:IsA("ParticleEmitter") then
		inst.Enabled = not reducedEffects
	end
end

function WorldController.setReducedEffects(on: boolean)
	if on == reducedEffects then
		return
	end
	reducedEffects = on
	for _, d in ipairs(workspace:GetDescendants()) do
		applyEffect(d)
	end
end

function WorldController.init(panels)
	Panels = panels
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("ProximityPrompt") then
			watchPrompt(d)
		end
	end
	workspace.DescendantAdded:Connect(function(d)
		if d:IsA("ProximityPrompt") then
			watchPrompt(d)
		elseif reducedEffects and d:IsA("ParticleEmitter") then
			applyEffect(d)
		end
	end)

	local islands = workspace:WaitForChild("Islands", 30)
	if islands then
		for _, island in ipairs(islands:GetChildren()) do
			watchIsland(island)
		end
		islands.ChildAdded:Connect(watchIsland)
	end

	for _, tag in ipairs({ "Creature", "Bobbing" }) do
		for _, inst in ipairs(CollectionService:GetTagged(tag)) do
			bob(inst)
		end
		CollectionService:GetInstanceAddedSignal(tag):Connect(bob)
	end

	ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
		if player ~= LocalPlayer then
			return
		end
		local panel = prompt:GetAttribute("OpensPanel")
		if type(panel) == "string" then
			Panels.open(panel, prompt:GetAttribute("Tab"))
		end
	end)

	ClientState.changed:Connect(function(kind)
		if kind == "full" and ClientState.data then
			WorldController.setReducedEffects(ClientState.data.settings.reducedEffects == true)
		end
	end)
end

return WorldController
