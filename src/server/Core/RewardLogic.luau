-- Daily rewards, research milestones and collection milestones. Each can be claimed once.
local Shared = game:GetService("ReplicatedStorage").Shared
local Economy = require(Shared.Config.Economy)
local Rules = require(Shared.Rules)

local Wallet = require(script.Parent.Wallet)
local Inventory = require(script.Parent.Inventory)

local RewardLogic = {}

local DAY = 86400

local function dayIndex(now: number): number
	return math.floor(now / DAY)
end

-- Returns { canClaim, streakDay (1-7 of the reward to claim next), nextIn (seconds), reward }
function RewardLogic.dailyStatus(profile, now: number)
	local today = dayIndex(now)
	local last = profile.daily.lastDay
	local streak = profile.daily.streak
	local canClaim = today > last
	if canClaim and today > last + 1 then
		streak = 0 -- missed a day: streak resets
	end
	local nextDay = (streak % #Economy.Daily) + 1
	return {
		canClaim = canClaim,
		streakDay = nextDay,
		nextIn = if canClaim then 0 else (today + 1) * DAY - now,
		reward = RewardLogic.dailyReward(profile, nextDay),
	}
end

function RewardLogic.dailyReward(profile, streakDay: number)
	local base = Economy.Daily[streakDay]
	local reward = {}
	for id, amount in pairs(base) do
		reward[id] = amount
	end
	-- A little income scaling keeps late-game dailies relevant, with a hard cap.
	local bonus = Inventory.incomePerSecond(profile) * Economy.DailyIncomeSeconds
	local cap = base.coins * Economy.DailyIncomeCapMult
	reward.coins = math.floor(base.coins + math.min(bonus, cap))
	return reward
end

function RewardLogic.claimDaily(profile, now: number)
	local status = RewardLogic.dailyStatus(profile, now)
	if not status.canClaim then
		return false, "Come back tomorrow!"
	end
	local today = dayIndex(now)
	if today > profile.daily.lastDay + 1 then
		profile.daily.streak = 0
	end
	profile.daily.streak += 1
	profile.daily.lastDay = today
	Wallet.add(profile, status.reward)
	return true, status.reward, status.streakDay
end

local function findById(list, id)
	for _, entry in ipairs(list) do
		if entry.id == id then
			return entry
		end
	end
	return nil
end

function RewardLogic.claimResearch(profile, id: string)
	local def = findById(Economy.Research, id)
	if not def then
		return false, "Unknown milestone"
	end
	if profile.claimed.research[id] then
		return false, "Already claimed"
	end
	if Rules.statValue(profile, def.stat) < def.goal then
		return false, "Milestone not reached yet"
	end
	profile.claimed.research[id] = true
	Wallet.add(profile, def.reward)
	return true, def.reward
end

function RewardLogic.claimCollection(profile, id: string)
	local def = findById(Economy.Collection, id)
	if not def then
		return false, "Unknown milestone"
	end
	if profile.claimed.collection[id] then
		return false, "Already claimed"
	end
	if Rules.collectionValue(profile, def.kind) < def.goal then
		return false, "Keep collecting!"
	end
	profile.claimed.collection[id] = true
	Wallet.add(profile, def.reward)
	return true, def.reward
end

return RewardLogic
