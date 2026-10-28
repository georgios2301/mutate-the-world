-- Island security: shield, vault door, zap trap, security upgrades and protection status.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Heist = require(Shared.Config.Heist)
local Economy = require(Shared.Config.Economy)
local Rules = require(Shared.Rules)
local Format = require(Shared.Util.Format)

local Client = script.Parent.Parent.Parent
local ClientState = require(Client.ClientState)
local Net = require(Client.Net)

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Kit = require(UI.Kit)

local Defense = {}
local C = Theme.Colors

local panel
local refs: { [string]: any } = {}
local ticking = false

local function card(parent: Instance, order: number, icon: string, title: string, color: Color3, onClick)
	local frame = Kit.frame(parent, { Size = UDim2.new(1 / 3, -8, 1, 0), BackgroundColor3 = C.panel2, LayoutOrder = order })
	Kit.stroke(frame, color, 1.5, 0.3)
	Kit.padding(frame, 12)
	Kit.label(frame, icon, { size = UDim2.new(1, 0, 0, 40), textSize = 32, align = Enum.TextXAlignment.Center })
	local t = Kit.label(frame, title, { size = UDim2.new(1, 0, 0, 26), font = Theme.Fonts.title, textSize = Theme.TextSize.h2, align = Enum.TextXAlignment.Center, color = color })
	t.Position = UDim2.fromOffset(0, 42)
	local status = Kit.label(frame, "", { size = UDim2.new(1, 0, 0, 50), textSize = Theme.TextSize.small, align = Enum.TextXAlignment.Center, wrap = true })
	status.Position = UDim2.fromOffset(0, 70)
	local button = Kit.button(frame, "", { size = UDim2.new(1, 0, 0, 42), color = color, textColor = C.bg, onClick = onClick })
	button.AnchorPoint = Vector2.new(0, 1)
	button.Position = UDim2.fromScale(0, 1)
	return status, button
end

function Defense.refresh()
	local data = ClientState.data
	if not data or not panel.frame.Visible then
		return
	end
	local d = data.defense
	local t = ClientState.now()
	local level = d.securityLevel

	local info = Rules.upgradeInfo(data.upgrades, "security")
	refs.level.Text = string.format("Security level <b>%d/%d</b>", level, #Economy.Upgrades.security.levels)
	if info.price and not info.blocked then
		Kit.setText(refs.upgrade, "Upgrade · ● " .. Format.number(info.price))
		Kit.setEnabled(refs.upgrade, data.currencies.coins >= info.price)
	else
		Kit.setText(refs.upgrade, "Max level")
		Kit.setEnabled(refs.upgrade, false)
	end

	-- Shield
	if d.shieldUntil > t then
		refs.shieldStatus.Text = "<font color='#3ee6ff'>Shield UP</font>\n" .. Format.time(d.shieldUntil - t) .. " left"
		Kit.setText(refs.shieldButton, "Active")
		Kit.setEnabled(refs.shieldButton, false)
	elseif d.shieldCooldownUntil > t then
		refs.shieldStatus.Text = "Recharging\n" .. Format.time(d.shieldCooldownUntil - t)
		Kit.setText(refs.shieldButton, "Recharging")
		Kit.setEnabled(refs.shieldButton, false)
	else
		refs.shieldStatus.Text = "Blocks all heists for " .. d.shieldDuration .. "s\nRecharge " .. Format.time(d.shieldCooldown)
		Kit.setText(refs.shieldButton, "Activate Shield")
		Kit.setEnabled(refs.shieldButton, true)
	end

	-- Door
	local breached = d.doorOpenUntil > t
	if breached then
		refs.doorStatus.Text = "<font color='#ff6b6b'>BREACHED</font>\nRelocks in " .. Format.time(d.doorOpenUntil - t)
	elseif d.doorLocked then
		refs.doorStatus.Text = "<font color='#7cff4f'>Locked</font>\nThieves need " .. d.breachTime .. "s to breach"
	else
		refs.doorStatus.Text = "<font color='#ff9a3c'>Open</font>\nAnyone can walk in"
	end
	Kit.setText(refs.doorButton, if d.doorLocked and not breached then "Unlock Door" else "Lock Door")
	Kit.setEnabled(refs.doorButton, true)

	-- Trap
	if level < Heist.Trap.minSecurity then
		refs.trapStatus.Text = "Requires security level " .. Heist.Trap.minSecurity
		Kit.setEnabled(refs.trapButton, false)
	elseif d.trapCooldownUntil > t then
		refs.trapStatus.Text = "Recharging " .. Format.time(d.trapCooldownUntil - t)
		Kit.setEnabled(refs.trapButton, false)
	else
		refs.trapStatus.Text = "Stuns a thief mid-heist for " .. Heist.Trap.stun .. "s and stops the theft"
		Kit.setEnabled(refs.trapButton, true)
	end
	Kit.setText(refs.trapButton, "⚡ Zap Thief")

	-- Features + protection
	local lines = {
		string.format("Heist time on your creatures: <b>%ds</b>   ·   Thief success chance: <b>%d%%</b>", Heist.ChannelTime + (level - 1) * Heist.ChannelPerSecurityLevel, math.floor(math.max(Heist.MinSuccess, Heist.BaseSuccess + (level - 1) * Heist.SuccessPerSecurityLevel) * 100 + 0.5)),
		(if d.alarm then "✔" else "✖") .. " Intruder alarm (level " .. Heist.AlarmMinSecurity .. ")      " .. (if d.slimeFloor then "✔" else "✖") .. " Slime floor slows intruders (level " .. Heist.SlimeFloorMinSecurity .. ")",
	}
	local newbie = (data.playSeconds or 0) < Heist.NewPlayerProtectionSeconds or not (data.tutorial.done or data.tutorial.everDone)
	if newbie then
		table.insert(lines, "<font color='#7cff4f'>🔰 New-player protection is active: nobody can raid you yet.</font>")
	end
	if (data.heistProtectedUntil or 0) > t then
		table.insert(lines, "<font color='#7cff4f'>🔰 Recently raided: protected for " .. Format.time(data.heistProtectedUntil - t) .. "</font>")
	end
	table.insert(lines, "<font color='#a59bcd'>Only Uncommon+ creatures on pads can be stolen. Starters and new arrivals are always safe.</font>")
	refs.info.Text = table.concat(lines, "\n")
end

function Defense.build(root: Instance, Panels)
	panel = Kit.panel(root, "Island Security", function()
		Panels.close()
	end)
	Defense.frame = panel.frame
	local content = panel.content

	local top = Kit.frame(content, { Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1 })
	refs.level = Kit.label(top, "", { size = UDim2.new(1, -220, 1, 0), textSize = Theme.TextSize.h2 })
	refs.upgrade = Kit.button(top, "Upgrade", {
		size = UDim2.fromOffset(210, 40),
		color = C.gold,
		textColor = C.bg,
		textSize = Theme.TextSize.small,
		onClick = function()
			Net.request("BuyUpgrade", "security")
		end,
	})
	refs.upgrade.AnchorPoint = Vector2.new(1, 0)
	refs.upgrade.Position = UDim2.fromScale(1, 0)

	local cards = Kit.frame(content, { Size = UDim2.new(1, 0, 0, 232), Position = UDim2.fromOffset(0, 52), BackgroundTransparency = 1 })
	Kit.list(cards, true, 12)
	refs.shieldStatus, refs.shieldButton = card(cards, 1, "🛡️", "Shield", C.cyan, function()
		Net.request("ActivateShield")
	end)
	refs.doorStatus, refs.doorButton = card(cards, 2, "🚪", "Vault Door", C.orange, function()
		Net.request("ToggleDoor")
	end)
	refs.trapStatus, refs.trapButton = card(cards, 3, "⚡", "Zap Trap", C.green, function()
		Net.request("TriggerTrap")
	end)

	refs.info = Kit.label(content, "", {
		size = UDim2.new(1, 0, 1, -296),
		wrap = true,
		textSize = Theme.TextSize.small,
		alignY = Enum.TextYAlignment.Top,
	})
	refs.info.Position = UDim2.fromOffset(0, 296)
end

function Defense.onOpen()
	Defense.refresh()
	if not ticking then
		ticking = true
		task.spawn(function()
			while panel.frame.Visible do
				task.wait(0.5)
				Defense.refresh()
			end
			ticking = false
		end)
	end
end

return Defense
