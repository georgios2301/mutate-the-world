-- Number / time / cost formatting shared by server messages and client UI.
local Format = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa" }

function Format.commas(n: number): string
	n = math.floor(n)
	local s = tostring(math.abs(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return (n < 0 and "-" or "") .. out
end

function Format.number(n: number): string
	if n ~= n then
		return "0"
	end
	local abs = math.abs(n)
	if abs < 10000 then
		if abs % 1 ~= 0 and abs < 100 then
			return string.format("%.1f", n):gsub("%.0$", "")
		end
		return Format.commas(n)
	end
	local tier = math.min(#SUFFIXES - 1, math.floor(math.log10(abs) / 3))
	local scaled = n / 10 ^ (tier * 3)
	local text = if math.abs(scaled) >= 100 then string.format("%d", scaled) else string.format("%.1f", scaled)
	text = text:gsub("%.0$", "")
	return text .. SUFFIXES[tier + 1]
end

function Format.time(seconds: number): string
	seconds = math.max(0, math.ceil(seconds))
	if seconds < 60 then
		return seconds .. "s"
	elseif seconds < 3600 then
		return string.format("%d:%02d", seconds // 60, seconds % 60)
	end
	local h = seconds // 3600
	local m = (seconds % 3600) // 60
	return string.format("%dh %02dm", h, m)
end

-- `info` is Economy.CurrencyInfo; passed in to keep this module dependency-free.
function Format.cost(cost, info, order): string
	local parts = {}
	for _, id in ipairs(order) do
		local amount = cost[id]
		if amount and amount > 0 then
			table.insert(parts, Format.number(amount) .. " " .. info[id].short)
		end
	end
	if #parts == 0 then
		return "Free"
	end
	return table.concat(parts, " · ")
end

return Format
