-- Server-side currency operations. All amounts must be non-negative integers.
-- spend() checks every currency before changing any, so a multi-currency price is atomic.
local Shared = game:GetService("ReplicatedStorage").Shared
local Economy = require(Shared.Config.Economy)

local Wallet = {}

local MAX = Economy.MaxCurrency
local VALID = {}
for _, id in ipairs(Economy.CurrencyIds) do
	VALID[id] = true
end

function Wallet.isCurrency(id): boolean
	return VALID[id] == true
end

function Wallet.get(profile, id: string): number
	return profile.currencies[id] or 0
end

function Wallet.isValidAmount(amount): boolean
	return type(amount) == "number" and amount == amount and amount >= 0 and amount <= MAX and amount % 1 == 0
end

-- A cost/reward table: { currencyId = non-negative integer }
function Wallet.isValidCost(cost): boolean
	if type(cost) ~= "table" then
		return false
	end
	for id, amount in pairs(cost) do
		if not VALID[id] or not Wallet.isValidAmount(amount) then
			return false
		end
	end
	return true
end

function Wallet.canAfford(profile, cost): (boolean, string?)
	if not Wallet.isValidCost(cost) then
		return false, "Invalid price"
	end
	for id, amount in pairs(cost) do
		if (profile.currencies[id] or 0) < amount then
			return false, "Not enough " .. Economy.CurrencyInfo[id].name
		end
	end
	return true
end

function Wallet.spend(profile, cost): (boolean, string?)
	local ok, err = Wallet.canAfford(profile, cost)
	if not ok then
		return false, err
	end
	for id, amount in pairs(cost) do
		profile.currencies[id] = (profile.currencies[id] or 0) - amount
	end
	return true
end

function Wallet.add(profile, rewards): boolean
	if not Wallet.isValidCost(rewards) then
		return false
	end
	for id, amount in pairs(rewards) do
		profile.currencies[id] = math.min(MAX, (profile.currencies[id] or 0) + amount)
	end
	return true
end

function Wallet.scale(cost, factor: number)
	local out = {}
	for id, amount in pairs(cost) do
		out[id] = math.floor(amount * factor)
	end
	return out
end

return Wallet
