-- Two-sided trade sessions. The server owns the session; clients only send intentions.
-- Rules: offered creatures are locked; any offer change resets both confirmations;
-- execute() revalidates everything and swaps atomically (no yields, all-or-nothing).
local Shared = game:GetService("ReplicatedStorage").Shared
local Creatures = require(Shared.Config.Creatures)
local Heist = require(Shared.Config.Heist)

local Wallet = require(script.Parent.Wallet)
local Inventory = require(script.Parent.Inventory)
local Locks = require(script.Parent.Locks)

local TradeLogic = {}

TradeLogic.MaxCreatures = 6
TradeLogic.ConfirmDelayAfterChange = 2 -- seconds after an offer change before accepting is allowed
TradeLogic.TradeCurrencies = { coins = true, dna = true }

local function emptyOffer()
	return { creatures = {}, coins = 0, dna = 0 }
end

function TradeLogic.newSession(id: string, userA: number, userB: number, now: number)
	return {
		id = id,
		users = { userA, userB },
		offers = { [userA] = emptyOffer(), [userB] = emptyOffer() },
		accepted = { [userA] = false, [userB] = false },
		version = 0,
		lastChange = now,
		state = "open", -- open | completed | cancelled
	}
end

function TradeLogic.other(session, userId: number): number
	return if session.users[1] == userId then session.users[2] else session.users[1]
end

function TradeLogic.isMember(session, userId: number): boolean
	return session.users[1] == userId or session.users[2] == userId
end

local function canOffer(profile, creatureId: string, sessionId: string): (boolean, string?)
	local creature = profile.creatures[creatureId]
	if not creature then
		return false, "You don't own that creature"
	end
	if creature.starter then
		return false, "Starter creatures can't be traded"
	end
	local species = Creatures.Species[creature.species]
	if not species or species.tradable == false then
		return false, "That creature can't be traded"
	end
	if creature.slot then
		return false, "Remove it from its pad before trading"
	end
	if profile.activeMutation and profile.activeMutation.creatureId == creatureId then
		return false, "That creature is in the Mutation Chamber"
	end
	local lock = Locks.get(creatureId)
	if lock and not (lock.kind == "trade" and lock.owner == sessionId) then
		return false, "That creature is busy right now"
	end
	return true
end

-- offer = { creatures = {ids}, coins = int, dna = int } (already shape-validated by the service)
function TradeLogic.setOffer(session, userId: number, profile, offer, now: number)
	if session.state ~= "open" then
		return false, "This trade is closed"
	end
	if not TradeLogic.isMember(session, userId) then
		return false, "Not your trade"
	end
	if #offer.creatures > TradeLogic.MaxCreatures then
		return false, "You can offer up to " .. TradeLogic.MaxCreatures .. " creatures"
	end
	for _, id in ipairs(offer.creatures) do
		local ok, err = canOffer(profile, id, session.id)
		if not ok then
			return false, err
		end
	end
	for currency in pairs(TradeLogic.TradeCurrencies) do
		local amount = offer[currency] or 0
		if not Wallet.isValidAmount(amount) then
			return false, "Invalid amount"
		end
		if amount > Wallet.get(profile, currency) then
			return false, "You don't have that much"
		end
	end

	-- Swap locks: release the old ones, then lock the new selection.
	for _, id in ipairs(session.offers[userId].creatures) do
		Locks.release(id, "trade", session.id)
	end
	for _, id in ipairs(offer.creatures) do
		Locks.acquire(id, "trade", session.id)
	end
	session.offers[userId] = {
		creatures = table.clone(offer.creatures),
		coins = offer.coins or 0,
		dna = offer.dna or 0,
	}
	session.accepted[session.users[1]] = false
	session.accepted[session.users[2]] = false
	session.version += 1
	session.lastChange = now
	return true
end

function TradeLogic.setAccepted(session, userId: number, accepted: boolean, now: number)
	if session.state ~= "open" or not TradeLogic.isMember(session, userId) then
		return false, "This trade is closed"
	end
	if accepted and now - session.lastChange < TradeLogic.ConfirmDelayAfterChange then
		return false, "The offer just changed. Review it before accepting"
	end
	session.accepted[userId] = accepted
	return true
end

function TradeLogic.bothAccepted(session): boolean
	return session.accepted[session.users[1]] == true and session.accepted[session.users[2]] == true
end

local function releaseAll(session)
	for _, userId in ipairs(session.users) do
		for _, id in ipairs(session.offers[userId].creatures) do
			Locks.release(id, "trade", session.id)
		end
	end
end

function TradeLogic.cancel(session)
	if session.state == "open" then
		session.state = "cancelled"
	end
	releaseAll(session)
end

-- Full revalidation of one side right before the swap.
local function validateSide(session, userId: number, profile, otherProfile, otherOfferCount: number)
	local offer = session.offers[userId]
	for _, id in ipairs(offer.creatures) do
		local creature = profile.creatures[id]
		if not creature or creature.starter or creature.slot then
			return false, "An offered creature is no longer available"
		end
		local lock = Locks.get(id)
		if not lock or lock.kind ~= "trade" or lock.owner ~= session.id then
			return false, "An offered creature is no longer available"
		end
		if profile.activeMutation and profile.activeMutation.creatureId == id then
			return false, "An offered creature is in the chamber"
		end
	end
	if not Wallet.canAfford(profile, { coins = offer.coins, dna = offer.dna }) then
		return false, "Someone no longer has the offered currency"
	end
	-- Receiver capacity: they lose their own offered creatures and gain the other side's.
	local receiverCount = Inventory.count(otherProfile) - otherOfferCount + #offer.creatures
	if receiverCount > Inventory.capacity(otherProfile) then
		return false, "Not enough creature storage on the receiving side"
	end
	return true
end

function TradeLogic.execute(session, profileA, profileB, now: number)
	if session.state ~= "open" then
		return false, "This trade is closed"
	end
	if not TradeLogic.bothAccepted(session) then
		return false, "Both players must accept"
	end
	local userA, userB = session.users[1], session.users[2]
	local offerA, offerB = session.offers[userA], session.offers[userB]
	if #offerA.creatures == 0 and #offerB.creatures == 0 and offerA.coins + offerA.dna + offerB.coins + offerB.dna == 0 then
		return false, "The trade is empty"
	end

	local ok, err = validateSide(session, userA, profileA, profileB, #offerB.creatures)
	if ok then
		ok, err = validateSide(session, userB, profileB, profileA, #offerA.creatures)
	end
	if not ok then
		TradeLogic.cancel(session)
		return false, err
	end

	-- Atomic swap. Nothing below can fail after the validation above.
	local movedA, movedB = {}, {}
	for _, id in ipairs(offerA.creatures) do
		table.insert(movedA, Inventory.remove(profileA, id))
	end
	for _, id in ipairs(offerB.creatures) do
		table.insert(movedB, Inventory.remove(profileB, id))
	end
	Wallet.spend(profileA, { coins = offerA.coins, dna = offerA.dna })
	Wallet.spend(profileB, { coins = offerB.coins, dna = offerB.dna })
	Wallet.add(profileB, { coins = offerA.coins, dna = offerA.dna })
	Wallet.add(profileA, { coins = offerB.coins, dna = offerB.dna })
	for _, creature in ipairs(movedA) do
		creature.acquiredAt = now
		creature.protectedUntil = now + Heist.NewCreatureProtection
		creature.source = "trade"
		Inventory.add(profileB, creature, { ignoreCapacity = true })
	end
	for _, creature in ipairs(movedB) do
		creature.acquiredAt = now
		creature.protectedUntil = now + Heist.NewCreatureProtection
		creature.source = "trade"
		Inventory.add(profileA, creature, { ignoreCapacity = true })
	end
	profileA.stats.trades += 1
	profileB.stats.trades += 1
	session.state = "completed"
	releaseAll(session)
	return true, { toA = movedB, toB = movedA }
end

return TradeLogic
