-- Server side of networking. All client requests go through one RemoteFunction
-- (ActionRequest) and are dispatched to registered handlers with:
--   * action whitelist, per-player global and per-action rate limits
--   * profile-loaded check, pcall isolation, automatic state push on success
-- Handlers validate their own arguments (see Core/Validate) and must not trust the client.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RateLimiter = require(script.Parent.Parent.Core.RateLimiter)

local Net = {}
local S

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local ActionRequest = remotes:WaitForChild("ActionRequest") :: RemoteFunction

local handlers = {}
local globalLimiter = RateLimiter.new(25, 12)

local function now(): number
	return workspace:GetServerTimeNow()
end

-- opts: { rate = {burst, perSecond}, needsProfile = true, push = true }
function Net.on(action: string, opts, fn)
	assert(handlers[action] == nil, "Duplicate action " .. action)
	local rate = opts.rate or { 6, 3 }
	handlers[action] = {
		fn = fn,
		limiter = RateLimiter.new(rate[1], rate[2]),
		needsProfile = opts.needsProfile ~= false,
		push = opts.push ~= false,
	}
end

local function onInvoke(player: Player, action, ...)
	if type(action) ~= "string" then
		return { ok = false, msg = "Bad request" }
	end
	local handler = handlers[action]
	if not handler then
		return { ok = false, msg = "Unknown action" }
	end
	local t = now()
	if not globalLimiter:check(player.UserId, t) or not handler.limiter:check(player.UserId, t) then
		return { ok = false, msg = "Slow down a little!" }
	end
	local profile = S.Data.get(player)
	if handler.needsProfile and not profile then
		return { ok = false, msg = "Your data is still loading..." }
	end
	local success, ok, msg, data = pcall(handler.fn, player, profile, ...)
	if not success then
		warn(string.format("[Net] %s failed for %s: %s", action, player.Name, tostring(ok)))
		return { ok = false, msg = "Something went wrong. Please try again." }
	end
	if ok and handler.push and profile then
		S.Data.markDirty(player)
		S.State.push(player)
	end
	return { ok = ok == true, msg = msg, data = data }
end

function Net.init(services)
	S = services
	ActionRequest.OnServerInvoke = onInvoke
	Players.PlayerRemoving:Connect(function(player)
		globalLimiter:forget(player.UserId)
		for _, h in pairs(handlers) do
			h.limiter:forget(player.UserId)
		end
	end)
end

function Net.event(name: string): RemoteEvent
	return remotes:WaitForChild(name) :: RemoteEvent
end

-- kind: "info" | "success" | "warn" | "error" | "rare"
function Net.notify(player: Player, text: string, kind: string?, extra)
	Net.event("Notify"):FireClient(player, { text = text, kind = kind or "info", extra = extra })
end

function Net.notifyAll(text: string, kind: string?)
	Net.event("Notify"):FireAllClients({ text = text, kind = kind or "info" })
end

return Net
