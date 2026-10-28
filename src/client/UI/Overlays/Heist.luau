-- Heist UI: progress bar for the thief, red alert with defense buttons for the island owner.
local Client = script.Parent.Parent.Parent
local ClientState = require(Client.ClientState)
local Net = require(Client.Net)

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Kit = require(UI.Kit)
local Sound = require(UI.Sound)
local Scaler = require(UI.Scaler)

local HeistOverlay = {}
local C = Theme.Colors

local attackerFrame: Frame
local attackerLabel: TextLabel
local setAttackerBar
local defenderFrame: Frame
local defenderLabel: TextLabel
local defenderTimer: TextLabel
local current = nil -- { role = "attacker" | "defender" | "breach", endsAt, duration, hideAt }

local function hideAll()
	attackerFrame.Visible = false
	defenderFrame.Visible = false
	current = nil
end

function HeistOverlay.build(root: Instance)
	attackerFrame = Kit.frame(root, {
		Name = "HeistAttacker",
		Size = UDim2.fromOffset(460, 92),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 206),
		BackgroundColor3 = C.panel,
		Visible = false,
		radius = 16,
	})
	Kit.stroke(attackerFrame, C.orange, 2, 0)
	Scaler.attach(attackerFrame)
	Kit.padding(attackerFrame, 12, 8)
	attackerLabel = Kit.label(attackerFrame, "", { size = UDim2.new(1, -110, 0, 24), font = Theme.Fonts.bold, color = C.orange })
	local bar, set = Kit.bar(attackerFrame, C.orange, UDim2.new(1, -110, 0, 18))
	bar.Position = UDim2.fromOffset(0, 32)
	setAttackerBar = set
	Kit.label(attackerFrame, "Stay close! Moving away cancels.", { size = UDim2.new(1, -110, 0, 18), textSize = Theme.TextSize.tiny, color = C.muted }).Position = UDim2.fromOffset(0, 54)
	local cancel = Kit.button(attackerFrame, "Back off", { size = UDim2.fromOffset(96, 60), color = C.panel3, textSize = Theme.TextSize.small, onClick = function()
		Net.request("CancelHeist")
	end })
	cancel.AnchorPoint = Vector2.new(1, 0.5)
	cancel.Position = UDim2.fromScale(1, 0.5)

	defenderFrame = Kit.frame(root, {
		Name = "HeistAlert",
		Size = UDim2.fromOffset(560, 116),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 206),
		BackgroundColor3 = Color3.fromRGB(70, 10, 25),
		Visible = false,
		radius = 16,
	})
	Kit.stroke(defenderFrame, C.red, 3, 0)
	Scaler.attach(defenderFrame)
	Kit.padding(defenderFrame, 12, 8)
	defenderLabel = Kit.label(defenderFrame, "", { size = UDim2.new(1, -80, 0, 44), font = Theme.Fonts.title, textSize = Theme.TextSize.h2, wrap = true, color = Color3.fromRGB(255, 220, 225) })
	defenderTimer = Kit.label(defenderFrame, "", { size = UDim2.fromOffset(80, 44), align = Enum.TextXAlignment.Right, font = Theme.Fonts.title, textSize = 26, color = C.red })
	defenderTimer.AnchorPoint = Vector2.new(1, 0)
	defenderTimer.Position = UDim2.fromScale(1, 0)
	local buttons = Kit.frame(defenderFrame, { Size = UDim2.new(1, 0, 0, 46), Position = UDim2.new(0, 0, 1, -46), BackgroundTransparency = 1 })
	Kit.list(buttons, true, 10, Enum.HorizontalAlignment.Center)
	Kit.button(buttons, "🛡 Shield", { size = UDim2.fromOffset(160, 44), color = C.cyan, textColor = C.bg, onClick = function()
		Net.request("ActivateShield")
	end })
	Kit.button(buttons, "⚡ Zap Thief", { size = UDim2.fromOffset(160, 44), color = C.green, textColor = C.bg, order = 1, onClick = function()
		Net.request("TriggerTrap")
	end })
	Kit.button(buttons, "🏠 Go Home", { size = UDim2.fromOffset(160, 44), color = C.purple, order = 2, onClick = function()
		Net.request("Travel", "island")
	end })

	task.spawn(function()
		local beat = 0
		while true do
			task.wait(0.1)
			if current then
				local t = ClientState.now()
				if current.role == "attacker" then
					local left = current.endsAt - t
					setAttackerBar(1 - left / current.duration, if left > 0 then string.format("%.1fs", left) else "...")
				else
					local left = (current.endsAt or current.hideAt) - t
					defenderTimer.Text = if current.endsAt then string.format("%ds", math.max(0, math.ceil(left))) else ""
					beat += 0.1
					defenderFrame.BackgroundColor3 = Color3.fromRGB(70, 10, 25):Lerp(Color3.fromRGB(140, 20, 40), (math.sin(beat * 8) + 1) / 2)
					if beat >= 1 then
						beat = 0
						Sound.play("Alarm")
					end
					if current.hideAt and t > current.hideAt then
						hideAll()
					end
				end
			end
		end
	end)
end

function HeistOverlay.onEvent(kind: string, data)
	if kind == "start" then
		hideAll()
		current = { role = "attacker", endsAt = data.endsAt, duration = data.duration }
		attackerLabel.Text = "Stealing " .. data.creature .. " from " .. data.victim .. "..."
		attackerFrame.Visible = true
	elseif kind == "alert" then
		hideAll()
		current = { role = "defender", endsAt = data.endsAt, duration = data.duration }
		defenderLabel.Text = "THIEF! " .. data.attacker .. " is stealing your " .. data.creature .. "!"
		defenderFrame.Visible = true
		Sound.play("Alarm")
	elseif kind == "breach" then
		if current and current.role ~= "breach" then
			return -- a live heist alert is more important
		end
		current = { role = "breach", hideAt = ClientState.now() + 8 }
		defenderLabel.Text = data.attacker .. " is breaching your vault door!"
		defenderFrame.Visible = true
		Sound.play("Alarm")
	elseif kind == "ended" then
		hideAll()
	end
end

return HeistOverlay
