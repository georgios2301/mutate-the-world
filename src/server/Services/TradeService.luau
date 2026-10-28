-- Secure player-to-player trading. Clients only send intentions (request, offer, accept);
-- the server owns the session, locks offered creatures, resets confirmations on any change,
-- runs a short countdown after both accept and revalidates everything before swapping.
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Rules = require(Shared.Rules)

local Core = script.Parent.Parent.Core
local TradeLogic = require(Core.TradeLogic)
local Validate = require(Core.Validate)
local Wallet = require(Core.Wallet)

local TradeService = {}
local S

local REQUEST_DISTANCE = 30
local REQUEST_TTL = 20
local REQUEST_COOLDOWN = 5
local COUNTDOWN = 3
local IDLE_TIMEOUT = 180

local sessions = {} -- [sessionId] = { session, players = {[userId] = Player}, countdownEndsAt }
local byUser = {} -- [userId] = sessionId
local requests = {} -- [targetUserId] = { [fromUserId] = expiresAt }
local lastRequest = {} -- [userId] = time

local function now(): number
	return workspace:GetServerTimeNow()
end

local function distanceBetween(a: Player, b: Player): number
	local ra, rb = S.Travel.getRoot(a), S.Travel.getRoot(b)
	if not ra or not rb then
		return math.huge
	end
	return (ra.Position - rb.Position).Magnitude
end

local function offerView(profile, offer)
	local creatures = {}
	for _, id in ipairs(offer.creatures) do
		local c = profile and profile.creatures[id]
		if c then
			table.insert(creatures, {
				id = c.id,
				species = c.species,
				mutation = c.mutation,
				level = c.level,
				income = Rules.creatureIncome(c),
			})
		end
	end
	return { creatures = creatures, coins = offer.coins, dna = offer.dna }
end

local function send(entry)
	local session = entry.session
	for _, userId in ipairs(session.users) do
		local player = entry.players[userId]
		local otherId = TradeLogic.other(session, userId)
		local other = entry.players[otherId]
		if player.Parent then
			S.Net.event("TradeEvent"):FireClient(player, "update", {
				id = session.id,
				state = session.state,
				countdownEndsAt = entry.countdownEndsAt,
				lastChange = session.lastChange,
				you = {
					offer = offerView(S.Data.get(player), session.offers[userId]),
					accepted = session.accepted[userId],
				},
				them = {
					name = other.DisplayName,
					userId = otherId,
					offer = offerView(S.Data.get(other), session.offers[otherId]),
					accepted = session.accepted[otherId],
				},
			})
		end
	end
end

local function close(entry, reason: string?, success: boolean?)
	local session = entry.session
	if session.state == "open" then
		TradeLogic.cancel(session)
	end
	sessions[session.id] = nil
	for userId, player in pairs(entry.players) do
		if byUser[userId] == session.id then
			byUser[userId] = nil
		end
		if player.Parent then
			S.Net.event("TradeEvent"):FireClient(player, "closed", { success = success == true, reason = reason })
			S.State.push(player)
		end
	end
end

local function execute(entry)
	local session = entry.session
	local a = entry.players[session.users[1]]
	local b = entry.players[session.users[2]]
	local pa, pb = S.Data.get(a), S.Data.get(b)
	if not pa or not pb then
		close(entry, "A player left")
		return
	end
	local ok, result = TradeLogic.execute(session, pa, pb, now())
	if not ok then
		close(entry, result)
		S.Net.notify(a, "Trade cancelled: " .. tostring(result), "warn")
		S.Net.notify(b, "Trade cancelled: " .. tostring(result), "warn")
		return
	end
	S.Data.markDirty(a)
	S.Data.markDirty(b)
	S.Creature.refreshIsland(a)
	S.Creature.refreshIsland(b)
	close(entry, "Trade complete!", true)
	S.Net.notify(a, "Trade with " .. b.DisplayName .. " complete!", "success")
	S.Net.notify(b, "Trade with " .. a.DisplayName .. " complete!", "success")
	S.Data.saveInOrder({ a, b })
end

local function sessionFor(player: Player)
	local id = byUser[player.UserId]
	return id and sessions[id]
end

local function startCountdownIfReady(entry)
	local session = entry.session
	if not TradeLogic.bothAccepted(session) then
		entry.countdownEndsAt = nil
		return
	end
	local version = session.version
	entry.countdownEndsAt = now() + COUNTDOWN
	task.delay(COUNTDOWN, function()
		if sessions[session.id] == entry and session.state == "open" and session.version == version and TradeLogic.bothAccepted(session) then
			execute(entry)
		end
	end)
end

function TradeService.onLeave(player: Player)
	local entry = sessionFor(player)
	if entry then
		close(entry, player.DisplayName .. " left the game")
	end
	requests[player.UserId] = nil
	for _, pending in pairs(requests) do
		pending[player.UserId] = nil
	end
	lastRequest[player.UserId] = nil
end

function TradeService.init(services)
	S = services
end

function TradeService.start()
	S.Net.on("TradeRequest", { rate = { 3, 0.5 }, push = false }, function(player, profile, targetUserId)
		if not Validate.int(targetUserId, 1) then
			return false, "Invalid player"
		end
		local target = Players:GetPlayerByUserId(targetUserId)
		if not target or target == player or not S.Data.get(target) then
			return false, "That player isn't available"
		end
		if byUser[player.UserId] or byUser[target.UserId] then
			return false, "One of you is already trading"
		end
		local t = now()
		if (lastRequest[player.UserId] or 0) + REQUEST_COOLDOWN > t then
			return false, "Wait a moment before sending another request"
		end
		if distanceBetween(player, target) > REQUEST_DISTANCE then
			return false, "Get closer to " .. target.DisplayName .. " to trade"
		end
		lastRequest[player.UserId] = t
		requests[target.UserId] = requests[target.UserId] or {}
		requests[target.UserId][player.UserId] = t + REQUEST_TTL
		S.Net.event("TradeEvent"):FireClient(target, "request", {
			fromUserId = player.UserId,
			fromName = player.DisplayName,
			expiresAt = t + REQUEST_TTL,
		})
		return true, "Trade request sent to " .. target.DisplayName
	end)

	S.Net.on("TradeRespond", { rate = { 4, 1 }, push = false }, function(player, profile, fromUserId, accept)
		if not Validate.int(fromUserId, 1) or not Validate.bool(accept) then
			return false, "Invalid response"
		end
		local pending = requests[player.UserId]
		local expires = pending and pending[fromUserId]
		if pending then
			pending[fromUserId] = nil
		end
		if not expires or expires < now() then
			return false, "That request expired"
		end
		local from = Players:GetPlayerByUserId(fromUserId)
		if not from or not S.Data.get(from) then
			return false, "That player left"
		end
		if not accept then
			S.Net.notify(from, player.DisplayName .. " declined your trade request", "info")
			return true
		end
		if byUser[player.UserId] or byUser[from.UserId] then
			return false, "One of you is already trading"
		end
		if distanceBetween(player, from) > REQUEST_DISTANCE + 10 then
			return false, "You moved too far apart"
		end
		local id = HttpService:GenerateGUID(false)
		local session = TradeLogic.newSession(id, from.UserId, player.UserId, now())
		local entry = { session = session, players = { [from.UserId] = from, [player.UserId] = player } }
		sessions[id] = entry
		byUser[from.UserId] = id
		byUser[player.UserId] = id
		send(entry)
		return true
	end)

	S.Net.on("TradeSetOffer", { rate = { 8, 3 }, push = false }, function(player, profile, offer)
		local entry = sessionFor(player)
		if not entry then
			return false, "You're not trading"
		end
		if type(offer) ~= "table" or not Validate.idList(offer.creatures, TradeLogic.MaxCreatures) then
			return false, "Invalid offer"
		end
		if not Wallet.isValidAmount(offer.coins) or not Wallet.isValidAmount(offer.dna) then
			return false, "Invalid amount"
		end
		local ok, err = TradeLogic.setOffer(entry.session, player.UserId, profile, {
			creatures = offer.creatures,
			coins = offer.coins,
			dna = offer.dna,
		}, now())
		if not ok then
			return false, err
		end
		entry.countdownEndsAt = nil
		send(entry)
		return true
	end)

	S.Net.on("TradeAccept", { rate = { 6, 2 }, push = false }, function(player, _profile, accepted)
		local entry = sessionFor(player)
		if not entry then
			return false, "You're not trading"
		end
		if not Validate.bool(accepted) then
			return false, "Invalid"
		end
		local ok, err = TradeLogic.setAccepted(entry.session, player.UserId, accepted, now())
		if not ok then
			return false, err
		end
		startCountdownIfReady(entry)
		send(entry)
		return true
	end)

	S.Net.on("TradeCancel", { rate = { 4, 1 }, push = false }, function(player)
		local entry = sessionFor(player)
		if not entry then
			return false, "You're not trading"
		end
		close(entry, player.DisplayName .. " cancelled the trade")
		return true
	end)

	task.spawn(function()
		while true do
			task.wait(5)
			local t = now()
			for _, entry in pairs(sessions) do
				if t - entry.session.lastChange > IDLE_TIMEOUT and not entry.countdownEndsAt then
					close(entry, "Trade timed out")
				end
			end
		end
	end)
end

return TradeService
