-- Client copy of the player's own data, received from the server. Read-only on the client:
-- it is only used for display, never sent back as the truth.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rules = require(ReplicatedStorage.Shared.Rules)

local ClientState = {}

local changed = Instance.new("BindableEvent")
ClientState.changed = changed.Event -- fires ("full" | "tick")
ClientState.data = nil :: any

function ClientState.apply(kind: string, payload)
	if kind == "full" then
		ClientState.data = payload
	elseif kind == "tick" then
		local data = ClientState.data
		if not data then
			return
		end
		data.pendingCoins = payload.pendingCoins
		data.currencies.coins = payload.coins
	else
		return
	end
	changed:Fire(kind)
end

function ClientState.ready(): boolean
	return ClientState.data ~= nil
end

function ClientState.now(): number
	return workspace:GetServerTimeNow()
end

function ClientState.creature(id: string)
	local data = ClientState.data
	if not data then
		return nil
	end
	for _, c in ipairs(data.creatures) do
		if c.id == id then
			return c
		end
	end
	return nil
end

function ClientState.level(): number
	return if ClientState.data then Rules.levelFromXP(ClientState.data.xp) else 1
end

function ClientState.currency(id: string): number
	local data = ClientState.data
	return data and data.currencies[id] or 0
end

function ClientState.canAfford(cost): boolean
	for id, amount in pairs(cost) do
		if ClientState.currency(id) < amount then
			return false
		end
	end
	return true
end

-- Creatures sorted for display: placed first, then rarity, then income.
function ClientState.sortedCreatures()
	local data = ClientState.data
	if not data then
		return {}
	end
	local Creatures = require(ReplicatedStorage.Shared.Config.Creatures)
	local Rarity = require(ReplicatedStorage.Shared.Config.Rarity)
	local list = table.clone(data.creatures)
	table.sort(list, function(a, b)
		if (a.slot ~= nil) ~= (b.slot ~= nil) then
			return a.slot ~= nil
		end
		local ra = Rarity.rank(Creatures.Species[a.species].rarity)
		local rb = Rarity.rank(Creatures.Species[b.species].rarity)
		if ra ~= rb then
			return ra > rb
		end
		if a.income ~= b.income then
			return a.income > b.income
		end
		return a.id < b.id
	end)
	return list
end

return ClientState
