-- Runtime creature locks. A creature can be held by exactly one system at a time
-- ("trade" or "heist"); an active mutation is tracked in the profile itself.
-- Locks are never saved: they only exist while the owning server is running.
local Locks = {}

local held = {} -- [creatureId] = { kind = string, owner = any }

function Locks.acquire(creatureId: string, kind: string, owner): (boolean, string?)
	local current = held[creatureId]
	if current then
		if current.kind == kind and current.owner == owner then
			return true
		end
		return false, current.kind
	end
	held[creatureId] = { kind = kind, owner = owner }
	return true
end

function Locks.release(creatureId: string, kind: string?, owner)
	local current = held[creatureId]
	if not current then
		return
	end
	if kind and current.kind ~= kind then
		return
	end
	if owner ~= nil and current.owner ~= owner then
		return
	end
	held[creatureId] = nil
end

function Locks.get(creatureId: string)
	return held[creatureId]
end

-- True when no system is using the creature (including the mutation chamber).
function Locks.isFree(profile, creatureId: string): boolean
	if held[creatureId] then
		return false
	end
	local job = profile.activeMutation
	if job and job.creatureId == creatureId then
		return false
	end
	return true
end

function Locks.reset()
	held = {}
end

return Locks
