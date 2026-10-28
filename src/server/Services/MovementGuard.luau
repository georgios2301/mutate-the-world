-- Lightweight anti-teleport check. Characters are physically simulated by their own client,
-- so an exploiter could teleport next to a creature or crystal. This samples positions and
-- snaps players back if they move horizontally much faster than they could walk.
-- It is tolerant on purpose (lag spikes, falling) and only guards against blatant teleports;
-- every distance-based action is also re-checked when it happens.
local Players = game:GetService("Players")

local MovementGuard = {}
local S

local SAMPLE = 0.5
local SLACK = 12 -- studs of tolerance per sample
local STRIKES_TO_SNAP = 2

local state = {} -- [Player] = { last = Vector3, strikes = number, graceUntil = number }

local function now(): number
	return workspace:GetServerTimeNow()
end

-- Server-authorized moves (portals, respawns) call this first.
function MovementGuard.grace(player: Player, seconds: number)
	local s = state[player]
	if not s then
		s = { strikes = 0, graceUntil = 0 }
		state[player] = s
	end
	s.graceUntil = math.max(s.graceUntil, now() + seconds)
	s.last = nil
	s.strikes = 0
end

local function check(player: Player)
	local root = S.Travel.getRoot(player)
	local s = state[player]
	if not root or not s then
		return
	end
	local pos = root.Position
	if now() < s.graceUntil or not s.last then
		s.last = pos
		return
	end
	local humanoid = (player.Character :: Model):FindFirstChildOfClass("Humanoid")
	local speed = math.max(16, humanoid and humanoid.WalkSpeed or 16)
	local flatDelta = Vector3.new(pos.X - s.last.X, 0, pos.Z - s.last.Z).Magnitude
	local allowed = speed * 1.6 * SAMPLE + SLACK
	if flatDelta > allowed then
		s.strikes += 1
		if s.strikes >= STRIKES_TO_SNAP then
			warn(string.format("[MovementGuard] %s moved %.0f studs in %.1fs; snapping back", player.Name, flatDelta, SAMPLE))
			local character = player.Character :: Model
			character:PivotTo(CFrame.new(s.last + Vector3.new(0, 3, 0)))
			s.strikes = 0
			return
		end
	else
		s.strikes = math.max(0, s.strikes - 1)
	end
	s.last = pos
end

function MovementGuard.init(services)
	S = services
end

function MovementGuard.start()
	Players.PlayerAdded:Connect(function(player)
		state[player] = { strikes = 0, graceUntil = now() + 10 }
		player.CharacterAdded:Connect(function()
			MovementGuard.grace(player, 5)
		end)
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		state[player] = { strikes = 0, graceUntil = now() + 10 }
	end
	Players.PlayerRemoving:Connect(function(player)
		state[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(SAMPLE)
			for player in pairs(state) do
				if player.Parent then
					check(player)
				end
			end
		end
	end)
end

return MovementGuard
