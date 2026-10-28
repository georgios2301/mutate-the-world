-- Argument validation for anything that arrives from a client. Never trust remote input.
local Validate = {}

function Validate.finite(v): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

function Validate.int(v, min: number?, max: number?): boolean
	if not Validate.finite(v) or v % 1 ~= 0 then
		return false
	end
	if min and v < min then
		return false
	end
	if max and v > max then
		return false
	end
	return true
end

function Validate.str(v, maxLen: number?): boolean
	return type(v) == "string" and #v > 0 and #v <= (maxLen or 64)
end

-- Creature ids, config keys, etc: short, alphanumeric plus - and _.
function Validate.id(v): boolean
	return type(v) == "string" and #v >= 1 and #v <= 64 and string.match(v, "^[%w%-_]+$") ~= nil
end

function Validate.oneOf(v, set): boolean
	return type(v) == "string" and set[v] ~= nil
end

function Validate.bool(v): boolean
	return type(v) == "boolean"
end

-- A dense array of unique ids, at most maxCount long.
function Validate.idList(v, maxCount: number): boolean
	if type(v) ~= "table" then
		return false
	end
	local count = 0
	for _ in pairs(v) do
		count += 1
	end
	if count ~= #v or count > maxCount then
		return false
	end
	local seen = {}
	for _, id in ipairs(v) do
		if not Validate.id(id) or seen[id] then
			return false
		end
		seen[id] = true
	end
	return true
end

return Validate
