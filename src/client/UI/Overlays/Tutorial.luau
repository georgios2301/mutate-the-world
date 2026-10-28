-- Tutorial card + guide beam pointing at the current objective.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Tutorial = require(Shared.Config.Tutorial)
local World = require(Shared.Config.World)

local Client = script.Parent.Parent.Parent
local ClientState = require(Client.ClientState)
local Net = require(Client.Net)

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Kit = require(UI.Kit)
local Scaler = require(UI.Scaler)

local TutorialOverlay = {}
local C = Theme.Colors
local LocalPlayer = Players.LocalPlayer

local card: Frame
local title: TextLabel
local body: TextLabel
local stepLabel: TextLabel
local nextButton: TextButton
local Panels: any = nil
local beam: any = nil
local marker: any = nil
local sourceAttachment: any = nil
local targetAttachment: any = nil

local function myIsland(): Model?
	local data = ClientState.data
	local folder = workspace:FindFirstChild("Islands")
	if not data or not folder or data.islandIndex == 0 then
		return nil
	end
	return folder:FindFirstChild("Island" .. data.islandIndex) :: Model?
end

local function rootPart(): BasePart?
	local character = LocalPlayer.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function nearest(parts: { BasePart }, from: Vector3): BasePart?
	local best, bestDist = nil, math.huge
	for _, p in ipairs(parts) do
		local d = (p.Position - from).Magnitude
		if d < bestDist then
			best, bestDist = p, d
		end
	end
	return best
end

local function hubPortalToIsland(): BasePart?
	local world = workspace:FindFirstChild("World")
	local hub = world and world:FindFirstChild("Hub")
	local portal = hub and hub:FindFirstChild("Portal_island")
	return portal and portal:FindFirstChild("Surface") :: BasePart?
end

local function onIsland(island: Model, pos: Vector3): boolean
	local index = island:GetAttribute("IslandIndex") :: number
	return (World.islandPosition(index) - pos).Magnitude < World.IslandZoneRadius + 10
end

-- Resolves the part the guide arrow should point at for the current step.
local function findTarget(step): BasePart?
	local island = myIsland()
	local root = rootPart()
	if not island or not root then
		return nil
	end
	local pos = root.Position
	local target = step.target
	if target == "starter" then
		local creatures = island:FindFirstChild("Creatures")
		for _, model in ipairs(if creatures then creatures:GetChildren() else {}) do
			local c = ClientState.creature(model:GetAttribute("CreatureId") or "")
			if c and c.starter and model:IsA("Model") then
				return model.PrimaryPart
			end
		end
	elseif target == "collector" then
		return island:FindFirstChild("Collector") :: BasePart?
	elseif target == "resources" then
		local inHub = (pos - World.HubCenter).Magnitude < World.HubRadius + 20
		if not inHub then
			return if onIsland(island, pos) then island:FindFirstChild("HubPortal") :: BasePart? else nil
		end
		local worldFolder = workspace:FindFirstChild("World")
		local pickups = worldFolder and worldFolder:FindFirstChild("Pickups")
		if not pickups then
			return nil
		end
		local data = ClientState.data
		local wantDna = data.tutorial.dna < step.needDna and data.currencies.dna < 5
		local candidates = {}
		for _, child in ipairs(pickups:GetChildren()) do
			if wantDna and child.Name == "DnaOrb" and child:IsA("BasePart") and child.Transparency < 1 then
				table.insert(candidates, child)
			elseif not wantDna and child.Name == "CrystalNode" and child:IsA("Model") and child.PrimaryPart then
				local prompt = child.PrimaryPart:FindFirstChildOfClass("ProximityPrompt")
				if prompt and prompt.Enabled and (child.PrimaryPart.Position - World.HubCenter).Magnitude < World.HubRadius + 10 then
					table.insert(candidates, child.PrimaryPart)
				end
			end
		end
		return nearest(candidates, pos)
	elseif target == "chamber" then
		if onIsland(island, pos) then
			local chamber = island:FindFirstChild("MutationChamber")
			return chamber and chamber:FindFirstChild("Base") :: BasePart?
		end
		return hubPortalToIsland()
	elseif target == "security" then
		return island:FindFirstChild("SecurityConsole") :: BasePart?
	elseif target == "hub" then
		return island:FindFirstChild("HubPortal") :: BasePart?
	end
	return nil
end

local function clearGuide()
	if beam then
		beam.Enabled = false
	end
	if marker then
		marker.Enabled = false
	end
end

local function updateGuide()
	local data = ClientState.data
	if not data or data.tutorial.done then
		clearGuide()
		return
	end
	local step = Tutorial.Steps[data.tutorial.step]
	local target = step and findTarget(step)
	local root = rootPart()
	if not target or not root then
		clearGuide()
		return
	end
	if not sourceAttachment or sourceAttachment.Parent ~= root then
		sourceAttachment = Instance.new("Attachment")
		sourceAttachment.Name = "TutorialSource"
		sourceAttachment.Parent = root
	end
	-- Targets get rebuilt (e.g. creature models), so recreate instead of re-parenting.
	if not targetAttachment or targetAttachment.Parent ~= target then
		if targetAttachment then
			targetAttachment:Destroy()
		end
		targetAttachment = Instance.new("Attachment")
		targetAttachment.Name = "TutorialTarget"
		targetAttachment.Parent = target
	end
	if not beam or not beam.Parent then
		beam = Instance.new("Beam")
		beam.Width0 = 0.6
		beam.Width1 = 0.6
		beam.FaceCamera = true
		beam.LightEmission = 1
		beam.Color = ColorSequence.new(C.cyan, C.green)
		beam.Transparency = NumberSequence.new(0.2, 0.5)
		beam.Segments = 1
		beam.Parent = workspace.Terrain
		marker = Instance.new("BillboardGui")
		marker.Size = UDim2.fromOffset(60, 60)
		marker.StudsOffsetWorldSpace = Vector3.new(0, 6, 0)
		marker.AlwaysOnTop = true
		marker.ResetOnSpawn = false
		marker.Parent = LocalPlayer:WaitForChild("PlayerGui")
		Kit.label(marker, "▼", { size = UDim2.fromScale(1, 1), textSize = 44, color = C.green, align = Enum.TextXAlignment.Center, font = Theme.Fonts.title })
	end
	beam.Attachment0 = sourceAttachment
	beam.Attachment1 = targetAttachment
	beam.Enabled = true
	marker.Adornee = target
	marker.Enabled = true
end

function TutorialOverlay.refresh()
	local data = ClientState.data
	if not data or data.tutorial.done then
		card.Visible = false
		clearGuide()
		return
	end
	if Panels and Panels.isOpen() then
		card.Visible = false -- never cover a panel's buttons
		return
	end
	local index = data.tutorial.step
	local step = Tutorial.Steps[index]
	if not step then
		card.Visible = false
		return
	end
	card.Visible = true
	title.Text = step.title
	local text = step.text
	if step.advance == "resources" then
		text ..= string.format("\n<font color='#ff78c8'>DNA %d/%d</font>  ·  <font color='#78d2ff'>Ice %d/%d</font>", math.min(data.tutorial.dna, step.needDna), step.needDna, math.min(data.tutorial.ice, step.needIce), step.needIce)
	end
	body.Text = text
	stepLabel.Text = index .. "/" .. #Tutorial.Steps
	local manual = step.advance == "manual" or step.advance == "defense"
	nextButton.Visible = manual
	Kit.setText(nextButton, if index == #Tutorial.Steps then "Finish" elseif step.advance == "defense" then "Got it" else "Next")
end

function TutorialOverlay.build(root: Instance, panels)
	Panels = panels
	panels.changed:Connect(function()
		TutorialOverlay.refresh()
	end)
	card = Kit.frame(root, {
		Name = "Tutorial",
		Size = UDim2.fromOffset(540, 128),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -84),
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.05,
		Visible = false,
		radius = 16,
	})
	Kit.stroke(card, C.green, 2, 0)
	Kit.padding(card, 14, 10)
	Scaler.attach(card)
	title = Kit.label(card, "", { size = UDim2.new(1, -60, 0, 26), font = Theme.Fonts.title, textSize = Theme.TextSize.h2, color = C.green })
	stepLabel = Kit.label(card, "", { size = UDim2.fromOffset(60, 26), align = Enum.TextXAlignment.Right, color = C.muted, textSize = Theme.TextSize.small })
	stepLabel.AnchorPoint = Vector2.new(1, 0)
	stepLabel.Position = UDim2.fromScale(1, 0)
	body = Kit.label(card, "", { size = UDim2.new(1, -150, 0, 70), wrap = true, textSize = Theme.TextSize.small, alignY = Enum.TextYAlignment.Top })
	body.Position = UDim2.fromOffset(0, 30)
	local buttons = Kit.frame(card, { Size = UDim2.fromOffset(130, 76), AnchorPoint = Vector2.new(1, 1), Position = UDim2.fromScale(1, 1), BackgroundTransparency = 1 })
	Kit.list(buttons, false, 6)
	nextButton = Kit.button(buttons, "Next", { size = UDim2.new(1, 0, 0, 40), color = C.green, textColor = C.bg, onClick = function()
		Net.request("TutorialAction", "next")
	end })
	local skip = Kit.button(buttons, "Skip tutorial", { size = UDim2.new(1, 0, 0, 28), color = C.panel3, textSize = Theme.TextSize.tiny, order = 1, onClick = function()
		Net.request("TutorialAction", "skip")
	end })
	skip.Name = "Skip"

	task.spawn(function()
		while true do
			task.wait(0.5)
			local ok, err = pcall(updateGuide)
			if not ok then
				warn("[Tutorial] guide error: " .. tostring(err))
			end
		end
	end)
end

return TutorialOverlay
