-- Server-wide discovery feed (hub Discovery Board) and rarity announcements.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Creatures = require(Shared.Config.Creatures)
local Mutations = require(Shared.Config.Mutations)
local Rarity = require(Shared.Config.Rarity)

local DiscoveryService = {}
local S

local feed = {} -- newest first, plain strings (rich text)
local MAX_FEED = 9
local totalDiscoveries = 0

local function render()
	local rows = S.World.discoveryRows
	for i, row in ipairs(rows) do
		row.Text = feed[i] or ""
	end
	if #feed == 0 then
		rows[1].Text = "<font color='#a0a0c0'>No discoveries yet. Be the first!</font>"
	end
end

local function push(text: string)
	table.insert(feed, 1, text)
	while #feed > MAX_FEED do
		table.remove(feed)
	end
	totalDiscoveries += 1
	render()
end

local function creatureName(creature): (string, string)
	local species = Creatures.Species[creature.species]
	return Mutations.displayName(species.name, creature.mutation), species.rarity
end

-- Big banner for everyone (Epic+ or first-time evolutions).
function DiscoveryService.announce(text: string, rarity: string)
	S.Net.event("Announcement"):FireAllClients({ text = text, rarity = rarity })
end

function DiscoveryService.onMutation(player: Player, result)
	local name, rarity = creatureName(result.creature)
	local hex = Rarity.color(rarity):ToHex()
	if result.newRecipe or result.newSpecies then
		push(string.format("%s discovered <font color='#%s'>%s</font>", player.DisplayName, hex, name))
	end
	local rank = Rarity.rank(rarity)
	local tier = Mutations.Types[result.creature.mutation].tier
	if (result.kind == "evolution" and rank >= 4) or rank >= 5 or tier >= 3 then
		DiscoveryService.announce(string.format("%s created a %s %s!", player.DisplayName, rarity, name), rarity)
	end
end

-- New species obtained by capture, shop, trade or heist.
function DiscoveryService.announceSpecies(player: Player, creature)
	local name, rarity = creatureName(creature)
	if Rarity.rank(rarity) >= 3 then
		push(string.format("%s found a <font color='#%s'>%s</font>", player.DisplayName, Rarity.color(rarity):ToHex(), name))
	end
	if Rarity.Info[rarity].announce then
		DiscoveryService.announce(string.format("%s obtained a %s %s!", player.DisplayName, rarity, name), rarity)
	end
end

function DiscoveryService.init(services)
	S = services
end

function DiscoveryService.start()
	render()
end

return DiscoveryService
