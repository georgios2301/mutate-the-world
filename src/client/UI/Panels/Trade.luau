-- Trading UI: request nearby players, build an offer, confirm. The server owns the session;
-- this panel only shows what the server sends and forwards the player's choices.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Creatures = require(Shared.Config.Creatures)
local Rarity = require(Shared.Config.Rarity)
local Format = require(Shared.Util.Format)

local Client = script.Parent.Parent.Parent
local ClientState = require(Client.ClientState)
local Net = require(Client.Net)

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Kit = require(UI.Kit)

local Trade = {}
local C = Theme.Colors
local LocalPlayer = Players.LocalPlayer

local panel
local lobby: Frame
local sessionFrame: Frame
local refs: { [string]: any } = {}
local requests = {} -- { fromUserId, fromName, expiresAt }
local session = nil
local draft = { creatures = {}, coins = 0, dna = 0 }
local Panels
local ticking = false
local NEARBY = 30

-- Rebuilds the local draft from what the server says we are offering.
local function syncDraft()
	if not session then
		return
	end
	local offer = session.you.offer
	draft.creatures = {}
	for _, c in ipairs(offer.creatures) do
		draft.creatures[c.id] = true
	end
	if not (refs.coinsBox and refs.coinsBox:IsFocused()) then
		draft.coins = offer.coins
	end
	if not (refs.dnaBox and refs.dnaBox:IsFocused()) then
		draft.dna = offer.dna
	end
end

local function sendOffer()
	local ids = {}
	for id in pairs(draft.creatures) do
		table.insert(ids, id)
	end
	table.sort(ids)
	local result = Net.request("TradeSetOffer", { creatures = ids, coins = draft.coins, dna = draft.dna })
	if not result.ok then
		-- Rejected (rate limit, balance, ...): show the offer the server will actually trade.
		syncDraft()
		Trade.refresh()
	end
end

local function dropRequest(req)
	local index = table.find(requests, req)
	if index then
		table.remove(requests, index)
	end
end

local function nearbyPlayers()
	local out = {}
	local me = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not me then
		return out
	end
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer then
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root and (root.Position - me.Position).Magnitude <= NEARBY then
				table.insert(out, player)
			end
		end
	end
	return out
end

local function creatureRow(parent: Instance, c, order: number, selected: boolean?, onClick)
	local species = Creatures.Species[c.species]
	local row = Kit.new("TextButton", {
		Size = UDim2.new(1, -8, 0, 42),
		BackgroundColor3 = if selected then C.panel3 else C.panel2,
		AutoButtonColor = onClick ~= nil,
		Text = "",
		LayoutOrder = order,
		Parent = parent,
	})
	Kit.corner(row, 10)
	if selected then
		Kit.stroke(row, C.green, 2, 0)
	end
	local icon = Kit.creatureIcon(row, c, 32)
	icon.Position = UDim2.fromOffset(5, 5)
	local name = Kit.label(row, Kit.creatureName(c) .. "  <font color='#a59bcd'>Lv " .. c.level .. " · " .. Format.number(c.income or 0) .. "/s</font>", {
		size = UDim2.new(1, -46, 1, 0),
		textSize = Theme.TextSize.tiny,
		font = Theme.Fonts.bold,
		color = Rarity.color(species.rarity),
	})
	name.Position = UDim2.fromOffset(44, 0)
	if onClick then
		row.Activated:Connect(onClick)
	end
	return row
end

local function renderLobby()
	Kit.clear(refs.nearby)
	local players = nearbyPlayers()
	if #players == 0 then
		Kit.label(refs.nearby, "Nobody within " .. NEARBY .. " studs. Walk up to a player to trade.", { size = UDim2.new(1, -8, 0, 40), wrap = true, color = C.muted, textSize = Theme.TextSize.small })
	end
	for i, player in ipairs(players) do
		local row = Kit.frame(refs.nearby, { Size = UDim2.new(1, -8, 0, 46), BackgroundColor3 = C.panel2, LayoutOrder = i })
		Kit.padding(row, 10, 4)
		Kit.label(row, player.DisplayName, { size = UDim2.new(1, -140, 1, 0), font = Theme.Fonts.bold })
		local b = Kit.button(row, "Request", { name = "Request_" .. player.UserId, size = UDim2.fromOffset(120, 36), color = C.cyan, textColor = C.bg, onClick = function()
			Net.request("TradeRequest", player.UserId)
		end })
		b.AnchorPoint = Vector2.new(1, 0.5)
		b.Position = UDim2.fromScale(1, 0.5)
	end
	Kit.clear(refs.incoming)
	local t = ClientState.now()
	local shown = 0
	for i, req in ipairs(requests) do
		if req.expiresAt > t then
			shown += 1
			local row = Kit.frame(refs.incoming, { Size = UDim2.new(1, -8, 0, 46), BackgroundColor3 = C.panel2, LayoutOrder = i })
			Kit.padding(row, 10, 4)
			Kit.label(row, req.fromName .. " wants to trade", { size = UDim2.new(1, -220, 1, 0), textSize = Theme.TextSize.small })
			local holder = Kit.frame(row, { Size = UDim2.fromOffset(210, 36), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(1, 0.5), BackgroundTransparency = 1 })
			Kit.list(holder, true, 8, Enum.HorizontalAlignment.Right)
			Kit.button(holder, "Accept", { size = UDim2.fromOffset(100, 36), color = C.green, textColor = C.bg, onClick = function()
				dropRequest(req)
				Net.request("TradeRespond", req.fromUserId, true)
			end })
			Kit.button(holder, "Decline", { size = UDim2.fromOffset(100, 36), color = C.red, order = 1, onClick = function()
				dropRequest(req)
				Net.request("TradeRespond", req.fromUserId, false)
				Trade.refresh()
			end })
		end
	end
	if shown == 0 then
		Kit.label(refs.incoming, "No incoming requests.", { size = UDim2.new(1, -8, 0, 30), color = C.muted, textSize = Theme.TextSize.small })
	end
end

local function renderSession()
	local data = ClientState.data
	refs.themTitle.Text = "Their offer — " .. session.them.name .. (if session.them.accepted then "  <font color='#7cff4f'>✔ Accepted</font>" else "")
	refs.youTitle.Text = "Your offer" .. (if session.you.accepted then "  <font color='#7cff4f'>✔ Accepted</font>" else "")

	-- Your selectable storage creatures
	Kit.clear(refs.yourList)
	local order = 0
	for _, c in ipairs(ClientState.sortedCreatures()) do
		local inThisTrade = c.lock == "trade" and draft.creatures[c.id]
		if not c.starter and not c.slot and (c.lock == nil or inThisTrade) then
			order += 1
			creatureRow(refs.yourList, c, order, draft.creatures[c.id] ~= nil, function()
				if draft.creatures[c.id] then
					draft.creatures[c.id] = nil
				else
					draft.creatures[c.id] = true
				end
				sendOffer()
			end)
		end
	end
	if order == 0 then
		Kit.label(refs.yourList, "Only creatures in storage can be traded (remove them from pads first). Starters can't be traded.", {
			size = UDim2.new(1, -8, 0, 54),
			wrap = true,
			textSize = Theme.TextSize.tiny,
			color = C.muted,
		})
	end
	if not refs.coinsBox:IsFocused() then
		refs.coinsBox.Text = tostring(draft.coins)
	end
	if not refs.dnaBox:IsFocused() then
		refs.dnaBox.Text = tostring(draft.dna)
	end

	-- Their offer (read-only)
	Kit.clear(refs.theirList)
	for i, c in ipairs(session.them.offer.creatures) do
		creatureRow(refs.theirList, c, i, false, nil)
	end
	Kit.label(refs.theirList, string.format("● %s coins   § %s DNA", Format.number(session.them.offer.coins), Format.number(session.them.offer.dna)), {
		size = UDim2.new(1, -8, 0, 30),
		order = 100,
		color = C.gold,
		font = Theme.Fonts.bold,
	})

	Kit.setText(refs.accept, if session.you.accepted then "Unaccept" else "Accept Trade")
	Trade.updateStatus()
	local _ = data
end

function Trade.updateStatus()
	if not session then
		return
	end
	local t = ClientState.now()
	if session.countdownEndsAt and session.countdownEndsAt > t then
		refs.status.Text = "<font color='#7cff4f'>Both accepted! Trading in " .. math.ceil(session.countdownEndsAt - t) .. "...</font>"
	elseif t - session.lastChange < 2 then
		refs.status.Text = "<font color='#ff9a3c'>Offer changed — review it before accepting.</font>"
	else
		refs.status.Text = "Any change resets both confirmations."
	end
end

-- Lobby contents change when players walk in/out of range or requests arrive/expire.
local lastLobbyKey = ""
local function lobbyKey(): string
	local parts = {}
	for _, player in ipairs(nearbyPlayers()) do
		table.insert(parts, tostring(player.UserId))
	end
	local t = ClientState.now()
	for _, req in ipairs(requests) do
		if req.expiresAt > t then
			table.insert(parts, "r" .. req.fromUserId)
		end
	end
	return table.concat(parts, ",")
end

function Trade.render()
	if not ClientState.data or not panel.frame.Visible then
		return
	end
	lobby.Visible = session == nil
	sessionFrame.Visible = session ~= nil
	if session then
		renderSession()
	else
		lastLobbyKey = lobbyKey()
		renderLobby()
	end
end

function Trade.onEvent(kind: string, data)
	if kind == "request" then
		table.insert(requests, data)
		Trade.notify(data.fromName .. " wants to trade! Open More → Trade to respond.", "info")
	elseif kind == "update" then
		local wasNil = session == nil
		session = data
		syncDraft()
		if wasNil then
			Panels.open("Trade")
		end
	elseif kind == "closed" then
		session = nil
		draft = { creatures = {}, coins = 0, dna = 0 }
		if data.reason then
			Trade.notify(data.reason, if data.success then "success" else "warn")
		end
	end
	Trade.refresh()
end

function Trade.build(root: Instance, panels)
	Panels = panels
	panel = Kit.panel(root, "Trading", function()
		Panels.close()
	end)
	Trade.frame = panel.frame
	local content = panel.content

	lobby = Kit.frame(content, { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 })
	Kit.label(lobby, "Players nearby", { font = Theme.Fonts.title, textSize = Theme.TextSize.h2, color = C.cyan })
	refs.nearby = Kit.scroll(lobby, { size = UDim2.new(1, 0, 0.5, -40), position = UDim2.fromOffset(0, 30) })
	Kit.list(refs.nearby, false, 6)
	local incomingTitle = Kit.label(lobby, "Incoming requests", { font = Theme.Fonts.title, textSize = Theme.TextSize.h2, color = C.cyan })
	incomingTitle.Position = UDim2.new(0, 0, 0.5, 0)
	refs.incoming = Kit.scroll(lobby, { size = UDim2.new(1, 0, 0.5, -34), position = UDim2.new(0, 0, 0.5, 30) })
	Kit.list(refs.incoming, false, 6)

	sessionFrame = Kit.frame(content, { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false })
	local you = Kit.frame(sessionFrame, { Size = UDim2.new(0.5, -6, 1, -56), BackgroundColor3 = C.panel2 })
	Kit.padding(you, 10)
	refs.youTitle = Kit.label(you, "Your offer", { font = Theme.Fonts.bold, color = C.cyan })
	refs.yourList = Kit.scroll(you, { size = UDim2.new(1, 0, 1, -76), position = UDim2.fromOffset(0, 28) })
	Kit.list(refs.yourList, false, 4)
	local currencyRow = Kit.frame(you, { Size = UDim2.new(1, 0, 0, 40), Position = UDim2.new(0, 0, 1, -40), BackgroundTransparency = 1 })
	Kit.list(currencyRow, true, 8)
	local function box(label: string, order: number, onCommit)
		Kit.label(currencyRow, label, { size = UDim2.fromOffset(46, 36), textSize = Theme.TextSize.small, order = order, color = C.gold })
		local tb = Kit.new("TextBox", {
			Size = UDim2.fromOffset(110, 36),
			BackgroundColor3 = C.bg,
			Text = "0",
			TextColor3 = C.text,
			Font = Theme.Fonts.bold,
			TextSize = Theme.TextSize.small,
			ClearTextOnFocus = false,
			LayoutOrder = order + 1,
			Parent = currencyRow,
		}) :: TextBox
		Kit.corner(tb, 8)
		tb.FocusLost:Connect(function()
			local n = math.max(0, math.floor(tonumber(tb.Text) or 0))
			tb.Text = tostring(n)
			onCommit(n)
		end)
		return tb
	end
	refs.coinsBox = box("Coins", 1, function(n)
		if n ~= draft.coins then
			draft.coins = n
			sendOffer()
		end
	end)
	refs.dnaBox = box("DNA", 3, function(n)
		if n ~= draft.dna then
			draft.dna = n
			sendOffer()
		end
	end)

	local them = Kit.frame(sessionFrame, { Size = UDim2.new(0.5, -6, 1, -56), Position = UDim2.new(0.5, 6, 0, 0), BackgroundColor3 = C.panel2 })
	Kit.padding(them, 10)
	refs.themTitle = Kit.label(them, "Their offer", { font = Theme.Fonts.bold, color = C.orange })
	refs.theirList = Kit.scroll(them, { size = UDim2.new(1, 0, 1, -28), position = UDim2.fromOffset(0, 28) })
	Kit.list(refs.theirList, false, 4)

	local bottom = Kit.frame(sessionFrame, { Size = UDim2.new(1, 0, 0, 46), Position = UDim2.new(0, 0, 1, -46), BackgroundTransparency = 1 })
	refs.status = Kit.label(bottom, "", { size = UDim2.new(1, -330, 1, 0), textSize = Theme.TextSize.small, wrap = true })
	local buttons = Kit.frame(bottom, { Size = UDim2.fromOffset(320, 44), AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), BackgroundTransparency = 1 })
	Kit.list(buttons, true, 10, Enum.HorizontalAlignment.Right)
	refs.accept = Kit.button(buttons, "Accept Trade", { size = UDim2.fromOffset(170, 44), color = C.green, textColor = C.bg, onClick = function()
		if session then
			Net.request("TradeAccept", not session.you.accepted)
		end
	end })
	Kit.button(buttons, "Cancel", { size = UDim2.fromOffset(120, 44), color = C.red, order = 1, onClick = function()
		Net.request("TradeCancel")
	end })
end

function Trade.onOpen()
	Trade.refresh()
	if not ticking then
		ticking = true
		task.spawn(function()
			while panel.frame.Visible do
				task.wait(1)
				-- Only cheap updates per tick; lists rebuild on events or when the lobby changes.
				if session then
					Trade.updateStatus()
				elseif lobbyKey() ~= lastLobbyKey then
					Trade.refresh()
				end
			end
			ticking = false
		end)
	end
end

function Trade.setNotifier(fn)
	Trade.notify = fn
end

Trade.notify = function(_text: string, _kind: string) end

function Trade.refresh()
	Kit.preserveSelection(panel.frame, Trade.render)
end

return Trade
