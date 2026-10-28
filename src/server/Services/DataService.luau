-- Persistent player data with session locking.
--
-- * One DataStore key per player: { data = <profile>, lock = { jobId, time }, saveCount }
-- * Loading takes the session lock with UpdateAsync. If another live server holds it, we wait
--   and retry; a lock older than LOCK_TIMEOUT is considered abandoned (crashed server).
-- * Saving uses UpdateAsync and refuses to write if another server took the lock, so an old
--   server can never overwrite newer data. Saves for one player are serialized.
-- * Saves happen on autosave (dirty profiles only), PlayerRemoving, BindToClose and right after
--   important transactions (trades, heists, purchases) - never on every small change.
-- * If DataStores are unavailable (unpublished place / Studio API access off) the game still
--   runs with session-only memory storage and tells the player progress won't be saved.
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local Core = script.Parent.Parent.Core
local DataSchema = require(Core.DataSchema)

local DataService = {}

local STORE_NAME = "MutateTheWorld_Players_v1"
local LOCK_TIMEOUT = 600
local AUTOSAVE_INTERVAL = 90
local MAX_RETRIES = 5
local LOAD_LOCK_ATTEMPTS = 6

local store: DataStore? = nil
local persistent = true
local everSucceeded = false -- once a DataStore call worked, never switch to memory mode
local entries = {} -- [userId] = { data, player, version, savedVersion, saving, lockLost, playTick }
local memoryStore = {} -- fallback when DataStores are unavailable (lives as long as the server)

local function now(): number
	return workspace:GetServerTimeNow()
end

local function keyFor(userId: number): string
	return "player_" .. userId
end

local function isAccessError(message: string): boolean
	return string.find(message, "StudioAccessToApisNotAllowed") ~= nil
		or string.find(message, "403") ~= nil
		or string.find(message, "publish") ~= nil
end

local function disablePersistence(reason: string)
	if persistent then
		persistent = false
		warn("[DataService] DataStores unavailable, using session-only storage: " .. reason)
	end
end

local function waitForBudget()
	local waited = 0
	while DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.UpdateAsync) < 1 and waited < 15 do
		task.wait(0.5)
		waited += 0.5
	end
end

-- Runs fn with exponential backoff. Returns success, results...
local function withRetries(label: string, fn)
	local delay = 1
	for attempt = 1, MAX_RETRIES do
		waitForBudget()
		local ok, result = pcall(fn)
		if ok then
			everSucceeded = true
			return true, result
		end
		local message = tostring(result)
		warn(string.format("[DataService] %s failed (attempt %d/%d): %s", label, attempt, MAX_RETRIES, message))
		if isAccessError(message) and not everSucceeded then
			disablePersistence(message)
			return false
		end
		if attempt < MAX_RETRIES then
			task.wait(delay)
			delay *= 2
		end
	end
	return false
end

local function deepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in pairs(value) do
		out[k] = deepCopy(v)
	end
	return out
end

function DataService.isPersistent(): boolean
	return persistent
end

function DataService.init(_services)
	if RunService:IsStudio() and game.GameId == 0 then
		disablePersistence("place is not published")
		return
	end
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if not ok then
		disablePersistence(tostring(result))
		return
	end
	store = result
end

-- Loads (and session-locks) a player's data. Yields. Returns the profile or nil (player kicked/left).
function DataService.load(player: Player)
	local userId = player.UserId
	local raw = nil

	-- Rejoined this same server while the previous session is still saving: wait for that
	-- save so we read the newest data (it also releases the lock we are about to take).
	local previous = entries[userId]
	while previous and entries[userId] == previous and previous.releasing do
		task.wait(0.1)
	end

	if persistent and store then
		local lockedElsewhere = false
		for attempt = 1, LOAD_LOCK_ATTEMPTS do
			lockedElsewhere = false
			local ok = withRetries("load " .. userId, function()
				return (store :: DataStore):UpdateAsync(keyFor(userId), function(old)
					old = old or {}
					local lock = old.lock
					if lock and lock.jobId ~= game.JobId and os.time() - (lock.time or 0) < LOCK_TIMEOUT then
						lockedElsewhere = true
						return nil -- cancel the write, keep their lock
					end
					old.lock = { jobId = game.JobId, time = os.time() }
					raw = old.data
					return old
				end)
			end)
			if not ok then
				if persistent then
					player:Kick("We couldn't load your data (Roblox DataStore error). Please rejoin.")
					return nil
				end
				break -- switched to memory mode
			end
			if not lockedElsewhere then
				break
			end
			if attempt < LOAD_LOCK_ATTEMPTS then
				task.wait(5)
			end
		end
		if lockedElsewhere then
			player:Kick("Your data is still being saved by another server. Please rejoin in a minute.")
			return nil
		end
	end

	if not persistent then
		raw = deepCopy(memoryStore[userId])
	end

	local t = now()
	local data, isNew = DataSchema.load(raw, t)
	local entry = {
		data = data,
		player = player,
		version = 1, -- bumped by markDirty
		savedVersion = 0,
		saving = false,
		lockLost = false,
		playTick = t,
		isNew = isNew,
	}
	entries[userId] = entry

	if not player.Parent then
		-- Left while loading: release the lock right away.
		DataService.release(player)
		return nil
	end
	return data
end

function DataService.get(player: Player)
	local entry = entries[player.UserId]
	return entry and entry.data
end

function DataService.getByUserId(userId: number)
	local entry = entries[userId]
	return entry and entry.data
end

function DataService.isNewPlayer(player: Player): boolean
	local entry = entries[player.UserId]
	return entry ~= nil and entry.isNew == true
end

function DataService.markDirty(player: Player)
	local entry = entries[player.UserId]
	if entry then
		entry.version += 1
	end
end

local function tickPlaytime(entry)
	local t = now()
	entry.data.playSeconds += math.max(0, t - entry.playTick)
	entry.playTick = t
end

-- Saves one player. Serialized per player; yields. release = also drop the session lock.
local function saveEntry(userId: number, release: boolean): boolean
	local entry = entries[userId]
	if not entry then
		return false
	end
	-- Ordered saves (see saveInOrder): wait until the predecessor's data is stored.
	local dependency = entry.waitFor
	if dependency then
		local started = os.clock()
		while dependency.entry.savedVersion < dependency.version and not dependency.entry.lockLost and os.clock() - started < 30 do
			task.wait(0.1)
		end
		if entry.waitFor == dependency then
			entry.waitFor = nil
		end
	end
	while entry.saving do
		task.wait(0.1)
	end
	-- A normal save that queued up behind the final release save must not run: it would
	-- re-take the session lock after the player left.
	if entry.lockLost or entries[userId] ~= entry or (entry.releasing and not release) then
		return false
	end
	entry.saving = true
	tickPlaytime(entry)
	entry.data.lastSeen = now()
	local versionAtStart = entry.version
	local dataToSave = entry.data
	local ok = true

	if persistent and store then
		local lockLost = false
		ok = withRetries("save " .. userId, function()
			return (store :: DataStore):UpdateAsync(keyFor(userId), function(old)
				old = old or {}
				if old.lock and old.lock.jobId ~= game.JobId then
					lockLost = true
					return nil -- another server owns this player now: never overwrite
				end
				old.data = dataToSave
				old.lock = if release then nil else { jobId = game.JobId, time = os.time() }
				old.saveCount = (old.saveCount or 0) + 1
				return old
			end)
		end)
		if lockLost then
			entry.lockLost = true
			ok = false
			warn("[DataService] Session lock lost for " .. userId .. "; this server will stop saving them.")
		end
	end
	if not persistent then
		memoryStore[userId] = deepCopy(dataToSave)
		ok = true
	end

	entry.saving = false
	if ok then
		entry.savedVersion = math.max(entry.savedVersion, versionAtStart)
	end
	return ok
end

-- Immediate save without releasing the lock. Yields; returns success.
function DataService.saveNow(player: Player): boolean
	return saveEntry(player.UserId, false)
end

-- Saves several players in order (first entry first) in a background thread. Every later
-- player's saves (autosave, release, saveNow) also wait until the earlier player's current
-- data is stored. Heists pass the victim first, so a crash between the two writes can lose
-- the stolen creature but never duplicate it. (Trades, where both sides give something,
-- can't be made crash-proof this way; see docs/LIMITATIONS.md.)
function DataService.saveInOrder(players: { Player })
	local chain = {}
	for _, player in ipairs(players) do
		local entry = entries[player.UserId]
		if entry then
			table.insert(chain, entry)
		end
	end
	for i = 2, #chain do
		chain[i].waitFor = { entry = chain[i - 1], version = chain[i - 1].version }
	end
	task.spawn(function()
		for _, entry in ipairs(chain) do
			local userId = entry.player.UserId
			if entries[userId] == entry and not entry.releasing then
				saveEntry(userId, false)
			end
		end
	end)
end

-- Final save + unlock. Call after every other service has cleaned up the player.
function DataService.release(player: Player)
	local userId = player.UserId
	local entry = entries[userId]
	if not entry or entry.releasing then
		return
	end
	entry.releasing = true
	saveEntry(userId, true)
	if entries[userId] == entry then
		entries[userId] = nil
	end
end

function DataService.start()
	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_INTERVAL)
			for userId, entry in pairs(entries) do
				if not entry.releasing then
					-- Autosave dirty profiles; also refresh the lock periodically for long sessions.
					local dirty = entry.version > entry.savedVersion
					if dirty or (now() - (entry.data.lastSeen or 0)) > LOCK_TIMEOUT / 2 then
						task.spawn(saveEntry, userId, false)
					end
				end
			end
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for userId, entry in pairs(entries) do
			if not entry.releasing then
				entry.releasing = true
				pending += 1
				task.spawn(function()
					saveEntry(userId, true)
					pending -= 1
				end)
			end
		end
		local started = os.clock()
		while pending > 0 and os.clock() - started < 25 do
			task.wait(0.1)
		end
	end)
end

return DataService
