-- Client side of ActionRequest. Sends intentions only; the server decides the outcome.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local Net = {}

local ActionRequest = Remotes.func("ActionRequest")
local notifier: ((string, string) -> ())? = nil

function Net.setNotifier(fn: (string, string) -> ())
	notifier = fn
end

-- Returns { ok, msg, data }. Shows the server's message as a toast unless `silent`.
function Net.request(action: string, ...)
	local args = table.pack(...)
	local ok, result = pcall(function()
		return ActionRequest:InvokeServer(action, table.unpack(args, 1, args.n))
	end)
	if not ok or type(result) ~= "table" then
		if notifier then
			(notifier :: any)("Connection problem. Please try again.", "error")
		end
		return { ok = false }
	end
	if result.msg and notifier then
		(notifier :: any)(result.msg, if result.ok then "success" else "warn")
	end
	return result
end

-- Same as request, but never shows a toast (caller handles feedback).
function Net.silent(action: string, ...)
	local args = table.pack(...)
	local ok, result = pcall(function()
		return ActionRequest:InvokeServer(action, table.unpack(args, 1, args.n))
	end)
	if not ok or type(result) ~= "table" then
		return { ok = false }
	end
	return result
end

function Net.event(name: string): RemoteEvent
	return Remotes.event(name)
end

return Net
