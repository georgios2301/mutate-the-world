-- Pure-logic test suite. Run with: python3 tests/run_tests.py
local passed, failed = 0, 0
local failures = {}

local function test(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		passed += 1
	else
		failed += 1
		table.insert(failures, name .. "\n    " .. tostring(err))
	end
end

local function eq(actual, expected, msg: string?)
	if actual ~= expected then
		error(string.format("%s: expected %s, got %s", msg or "eq", tostring(expected), tostring(actual)), 2)
	end
end

local function truthy(v, msg: string?)
	if not v then
		error((msg or "expected truthy") .. " (got " .. tostring(v) .. ")", 2)
	end
end

local function falsy(v, msg: string?)
	if v then
		error((msg or "expected falsy") .. " (got " .. tostring(v) .. ")", 2)
	end
end

local Shared = game:GetService("ReplicatedStorage").Shared
local Core = game:GetService("ServerScriptService").Server.Core

local Creatures = require(Shared.Config.Creatures)
local Mutations = require(Shared.Config.Mutations)
local Economy = require(Shared.Config.Economy)
local Biomes = require(Shared.Config.Biomes)
local Heist = require(Shared.Config.Heist)
local Rarity = require(Shared.Config.Rarity)
local Tutorial = require(Shared.Config.Tutorial)
local Products = require(Shared.Config.Products)
local Rules = require(Shared.Rules)
local Format = require(Shared.Util.Format)

local DataSchema = require(Core.DataSchema)
local Wallet = require(Core.Wallet)
local Inventory = require(Core.Inventory)
local Locks = require(Core.Locks)
local EconomyLogic = require(Core.EconomyLogic)
local MutationLogic = require(Core.MutationLogic)
local TradeLogic = require(Core.TradeLogic)
local HeistLogic = require(Core.HeistLogic)
local RewardLogic = require(Core.RewardLogic)
local RateLimiter = require(Core.RateLimiter)
local Validate = require(Core.Validate)

local NOW = 1_800_000_000

local function newProfile(now: number?)
	local p = DataSchema.default(now or NOW)
	DataSchema.ensureStarter(p, now or NOW, 7)
	return p
end

local function give(profile, speciesId: string, opts)
	opts = opts or {}
	opts.now = opts.now or (NOW - 10000)
	local c = Inventory.newCreature(speciesId, opts)
	local ok, err = Inventory.add(profile, c, { ignoreCapacity = true })
	assert(ok, err)
	return c
end

-- A victim that is fully eligible to be raided.
local function raidableVictim()
	local victim = newProfile()
	victim.tutorial.done = true
	victim.playSeconds = 99999
	victim.xp = Rules.xpForLevel(5)
	local target = give(victim, "frostling")
	target.slot = 2
	give(victim, "basic_blob")
	give(victim, "crystal_mite")
	return victim, target
end

local function attackerProfile()
	local a = newProfile()
	a.tutorial.done = true
	a.playSeconds = 99999
	a.xp = Rules.xpForLevel(6)
	a.currencies.coins = 4000
	return a
end

local function heistCtx(overrides)
	local ctx = { now = NOW, attackerId = 1, victimId = 2 }
	for k, v in pairs(overrides or {}) do
		ctx[k] = v
	end
	return ctx
end

---------------------------------------------------------------- Config integrity

test("config: at least 15 distinct species with valid data", function()
	eq(#Creatures.Order >= 15, true, "species count")
	local archetypes = {}
	for _, id in ipairs(Creatures.Order) do
		local s = Creatures.Species[id]
		truthy(Rarity.Info[s.rarity], id .. " rarity")
		truthy(Mutations.Elements[s.element], id .. " element")
		truthy(s.baseIncome > 0, id .. " income")
		truthy(s.look and s.look.archetype, id .. " look")
		archetypes[s.look.archetype] = true
	end
	local n = 0
	for _ in pairs(archetypes) do
		n += 1
	end
	truthy(n >= 6, "uses several reusable archetypes")
end)

test("config: all 7 rarities used", function()
	local used = {}
	for _, id in ipairs(Creatures.Order) do
		used[Creatures.Species[id].rarity] = true
	end
	for _, r in ipairs(Rarity.Order) do
		truthy(used[r], "rarity " .. r .. " has a species")
	end
end)

test("config: every species is obtainable (wild, shop or evolution chain)", function()
	local obtainable = { [Creatures.StarterSpecies] = true }
	for _, def in pairs(Biomes.Defs) do
		for _, w in ipairs(def.wild) do
			truthy(Creatures.Species[w.species], "wild species " .. w.species)
			obtainable[w.species] = true
		end
	end
	for _, w in ipairs(Biomes.HubWild) do
		obtainable[w.species] = true
	end
	for _, id in ipairs(Economy.ShopSpecies) do
		truthy(Creatures.Species[id].shopPrice, "shop price for " .. id)
		obtainable[id] = true
	end
	local changed = true
	while changed do
		changed = false
		for _, evo in ipairs(Mutations.Evolutions) do
			if obtainable[evo.species] and not obtainable[evo.result] then
				obtainable[evo.result] = true
				changed = true
			end
		end
	end
	for _, id in ipairs(Creatures.Order) do
		truthy(obtainable[id], id .. " obtainable")
	end
end)

test("config: every mutation type reachable from Normal", function()
	local reachable = { none = true }
	local changed = true
	while changed do
		changed = false
		for _, r in ipairs(Mutations.Recipes) do
			if reachable[r.from] and not reachable[r.result] then
				reachable[r.result] = true
				changed = true
			end
		end
	end
	for _, id in ipairs(Mutations.TypeOrder) do
		truthy(reachable[id], "mutation " .. id .. " reachable")
	end
end)

test("config: prompt-required recipes exist", function()
	eq(Mutations.findReaction("basic_blob", "none", "ice").resultMutation, "frost")
	eq(Mutations.findReaction("basic_blob", "none", "toxic").resultMutation, "toxic")
	eq(Mutations.findReaction("basic_blob", "none", "plasma").resultMutation, "plasma")
	eq(Mutations.findReaction("basic_blob", "frost", "plasma").resultMutation, "quantum")
	eq(Mutations.findReaction("basic_blob", "toxic", "plasma").resultMutation, "volatile")
	eq(Mutations.findReaction("crystal_mite", "quantum", "cosmic").resultMutation, "cosmic")
end)

test("config: recipe costs are valid wallet costs and include the ingredient", function()
	for _, list in ipairs({ Mutations.Recipes, Mutations.Evolutions }) do
		for _, r in ipairs(list) do
			truthy(Wallet.isValidCost(r.cost), r.id .. " cost valid")
			local currency = Mutations.Ingredients[r.ingredient].currency
			truthy((r.cost[currency] or 0) > 0, r.id .. " spends its ingredient")
			truthy(r.chamberLevel >= 1 and r.chamberLevel <= #Economy.Upgrades.chamber.levels, r.id .. " chamber level")
		end
	end
end)

test("config: products default to unconfigured id 0 (no fake ids)", function()
	for key, def in pairs(Products.GamePasses) do
		eq(type(def.id), "number", key)
	end
	for key, def in pairs(Products.DevProducts) do
		eq(type(def.id), "number", key)
	end
	eq(Products.findByProductId(0), nil, "id 0 never matches")
end)

test("config: upgrade prices increase", function()
	for id, def in pairs(Economy.Upgrades) do
		for i = 2, #def.levels do
			truthy(def.levels[i].price > def.levels[i - 1].price, id .. " price grows at " .. i)
		end
	end
end)

---------------------------------------------------------------- Data

test("data: new player gets exactly one starter Basic Blob on pad 1", function()
	local p = DataSchema.default(NOW)
	local c = DataSchema.ensureStarter(p, NOW, 3)
	truthy(c, "starter created")
	eq(c.species, "basic_blob")
	eq(c.starter, true)
	eq(c.slot, 1)
	eq(DataSchema.ensureStarter(p, NOW, 3), nil, "second call gives nothing")
	eq(Inventory.count(p), 1)
	eq(p.currencies.coins, Economy.StartingCurrencies.coins)
	truthy(p.biomes.frozen_peaks, "default biome")
end)

test("data: load(nil) returns defaults flagged as new", function()
	local data, isNew = DataSchema.load(nil, NOW)
	eq(isNew, true)
	eq(data.version, DataSchema.VERSION)
end)

test("data: migration + sanitize repairs corrupted v1 data", function()
	local raw = {
		version = 1,
		currencies = { coins = -50, dna = 0 / 0, ice = 3.7 },
		heistProtectedUntil = NOW + 30,
		upgrades = { pads = 99, chamber = 0 },
		creatures = {
			a = { id = "a", species = "does_not_exist", mutation = "frost", level = 1, slot = 1 },
			b = { id = "b", species = "frostling", mutation = "bogus", level = 50, slot = 1 },
			c = { id = "WRONG", species = "frostling", mutation = "none" },
		},
		biomes = { fake_biome = true },
		discovered = { species = {}, recipes = { frost = true, made_up = true }, combos = {} },
		activeMutation = { creatureId = "missing", cost = { coins = 25, dna = 5 } },
	}
	local data = DataSchema.load(raw, NOW)
	eq(data.version, DataSchema.VERSION)
	eq(data.currencies.coins, 25, "negative clamped to 0, then refund of 25")
	eq(data.currencies.dna, 5, "NaN -> 0 + refund 5")
	eq(data.currencies.ice, 3, "fractions floored")
	eq(data.heist.protectedUntil, NOW + 30, "v1 field migrated")
	eq(data.upgrades.pads, #Economy.Upgrades.pads.levels, "clamped")
	eq(data.upgrades.chamber, 1)
	eq(data.creatures.a.species, "basic_blob", "unknown species remapped")
	eq(data.creatures.b.mutation, "none", "unknown mutation reset")
	eq(data.creatures.b.level, Economy.CreatureLevel.maxLevel)
	eq(data.creatures.c, nil, "id mismatch removed")
	local slotOwners = 0
	for _, c in pairs(data.creatures) do
		if c.slot == 1 then
			slotOwners += 1
		end
	end
	eq(slotOwners, 1, "duplicate slot resolved")
	eq(data.biomes.fake_biome, nil)
	eq(data.discovered.recipes.made_up, nil)
	eq(data.activeMutation, nil, "orphaned job cleared")
	truthy(data.settings and data.tutorial and data.stats, "missing tables reconciled")
end)

---------------------------------------------------------------- Wallet

test("wallet: rejects invalid amounts and is atomic", function()
	local p = newProfile()
	p.currencies.coins = 100
	p.currencies.dna = 3
	falsy(Wallet.spend(p, { coins = -10 }), "negative")
	falsy(Wallet.spend(p, { coins = 0 / 0 }), "NaN")
	falsy(Wallet.spend(p, { coins = 1.5 }), "fraction")
	falsy(Wallet.spend(p, { gems = 1 }), "unknown currency")
	falsy(Wallet.spend(p, "100"), "not a table")
	falsy(Wallet.spend(p, { coins = 50, dna = 5 }), "insufficient dna")
	eq(p.currencies.coins, 100, "nothing spent on failure")
	truthy(Wallet.spend(p, { coins = 50, dna = 3 }))
	eq(p.currencies.coins, 50)
	eq(p.currencies.dna, 0)
	falsy(Wallet.add(p, { coins = -5 }), "negative reward rejected")
	Wallet.add(p, { coins = Economy.MaxCurrency })
	eq(p.currencies.coins, Economy.MaxCurrency, "capped")
end)

---------------------------------------------------------------- Inventory

test("inventory: unique ids, duplicates rejected, capacity enforced", function()
	local p = newProfile()
	local c = Inventory.newCreature("frostling", { now = NOW })
	truthy(Inventory.add(p, c))
	local dup = Inventory.newCreature("frostling", { id = c.id, now = NOW })
	falsy(Inventory.add(p, dup), "duplicate id")
	falsy(Inventory.add(p, Inventory.newCreature("nope", { now = NOW })), "unknown species")
	for _ = 1, Inventory.capacity(p) - Inventory.count(p) do
		truthy(Inventory.add(p, Inventory.newCreature("basic_blob", { now = NOW })))
	end
	local ok, err = Inventory.add(p, Inventory.newCreature("basic_blob", { now = NOW }))
	falsy(ok, "full")
	truthy(string.find(err, "full"), "message mentions full")
end)

test("inventory: placing respects unlocked pads", function()
	local p = newProfile()
	local c = give(p, "frostling")
	truthy(Inventory.place(p, c.id, 2))
	falsy(Inventory.place(p, c.id, 1), "pad 1 has the starter")
	falsy(Inventory.place(p, c.id, 4), "pad 4 locked at level 1")
	falsy(Inventory.place(p, c.id, 2.5), "fractional slot")
	falsy(Inventory.place(p, "ghost", 3), "not owned")
	truthy(Inventory.unplace(p, c.id))
	local ok, slot = Inventory.place(p, c.id)
	truthy(ok)
	eq(slot, 2, "first free pad")
end)

test("inventory: income uses mutation, level and resonance", function()
	local blob = { species = "basic_blob", mutation = "none", level = 1 }
	eq(Rules.creatureIncome(blob), 1)
	local frostBlob = { species = "basic_blob", mutation = "frost", level = 1 }
	eq(Rules.creatureIncome(frostBlob), 1.6, "no resonance for Normal species")
	local frostFrostling = { species = "frostling", mutation = "frost", level = 1 }
	eq(Rules.creatureIncome(frostFrostling), 4 * 1.6 * Mutations.ResonanceBonus, "resonance")
	local leveled = { species = "basic_blob", mutation = "none", level = 3 }
	eq(Rules.creatureIncome(leveled), 1 + 2 * Economy.CreatureLevel.incomePerLevel)
	local p = newProfile()
	eq(Inventory.incomePerSecond(p), 1, "starter on pad earns")
	local stored = give(p, "frostling")
	eq(Inventory.incomePerSecond(p), 1, "stored creatures earn nothing")
	Inventory.place(p, stored.id)
	eq(Inventory.incomePerSecond(p), 5)
end)

---------------------------------------------------------------- Economy

test("economy: collector accrues, caps, and collect moves whole coins", function()
	local p = newProfile()
	EconomyLogic.accrue(p, 10.5)
	eq(p.pendingCoins, 10.5)
	eq(EconomyLogic.collect(p), 10)
	eq(p.pendingCoins, 0.5)
	eq(p.currencies.coins, 110)
	eq(p.stats.totalEarned, 10)
	EconomyLogic.accrue(p, 1e9)
	eq(p.pendingCoins, EconomyLogic.collectorCapacity(p), "capped at capacity (no infinite idle)")
	eq(EconomyLogic.accrue(p, 100), 0, "full collector adds nothing")
end)

test("economy: offline earnings are limited", function()
	local p = newProfile()
	p.upgrades.collector = #Economy.Upgrades.collector.levels
	p.lastSeen = NOW - 10 * 86400
	local added = EconomyLogic.applyOffline(p, NOW)
	eq(added, Economy.Offline.maxSeconds * Economy.Offline.rate * 1, "max duration * reduced rate")
	p.lastSeen = NOW + 500 -- clock skew must not give coins
	eq(EconomyLogic.applyOffline(p, NOW), 0)
end)

test("economy: upgrades cost coins, level up, and respect island limits", function()
	local p = newProfile()
	p.currencies.coins = 100
	falsy(EconomyLogic.buyUpgrade(p, "pads"), "can't afford 250")
	falsy(EconomyLogic.buyUpgrade(p, "warp_drive"), "unknown upgrade")
	p.currencies.coins = 1e7
	truthy(EconomyLogic.buyUpgrade(p, "pads"))
	eq(p.upgrades.pads, 2)
	eq(p.currencies.coins, 1e7 - 250)
	eq(Inventory.padCount(p), 4)
	truthy(EconomyLogic.buyUpgrade(p, "pads"))
	truthy(EconomyLogic.buyUpgrade(p, "pads"))
	eq(Inventory.padCount(p), 6)
	local ok, err = EconomyLogic.buyUpgrade(p, "pads")
	falsy(ok, "island level 1 allows 6 pads")
	truthy(string.find(err, "island"), err)
	truthy(EconomyLogic.buyUpgrade(p, "island"))
	truthy(EconomyLogic.buyUpgrade(p, "pads"), "allowed after expansion")
	eq(Inventory.padCount(p), 7)
	for _ = 1, 10 do
		EconomyLogic.buyUpgrade(p, "chamber")
	end
	eq(p.upgrades.chamber, 4, "never exceeds max")
end)

test("economy: shop, level-up and release", function()
	local p = newProfile()
	p.currencies.coins = 1000
	local ok, creature = EconomyLogic.buyCreature(p, "basic_blob", NOW, 5)
	truthy(ok)
	eq(p.currencies.coins, 880)
	falsy(EconomyLogic.buyCreature(p, "world_eater", NOW, 5), "not sold")
	p.currencies.dna = 100
	local before = p.currencies.coins
	truthy(EconomyLogic.levelUpCreature(p, creature.id))
	eq(creature.level, 2)
	truthy(p.currencies.coins < before, "level-up costs coins")
	local starter
	for _, c in pairs(p.creatures) do
		if c.starter then
			starter = c
		end
	end
	falsy(EconomyLogic.releaseCreature(p, starter.id), "starter can't be released")
	local dnaBefore = p.currencies.dna
	truthy(EconomyLogic.releaseCreature(p, creature.id))
	eq(p.creatures[creature.id], nil)
	truthy(p.currencies.dna > dnaBefore, "release gives DNA")
end)

test("economy: biome unlock checks requirements and charges once", function()
	local p = newProfile()
	falsy(EconomyLogic.unlockBiome(p, "toxic_swamp"), "level too low")
	p.xp = Rules.xpForLevel(2)
	p.currencies.coins = 599
	falsy(EconomyLogic.unlockBiome(p, "toxic_swamp"), "not enough coins")
	p.currencies.coins = 700
	truthy(EconomyLogic.unlockBiome(p, "toxic_swamp"))
	eq(p.currencies.coins, 100)
	falsy(EconomyLogic.unlockBiome(p, "toxic_swamp"), "no double purchase")
	eq(p.currencies.coins, 100)
	falsy(EconomyLogic.unlockBiome(p, "moon"), "unknown biome")
	truthy(EconomyLogic.isBiomeUnlocked(p, "frozen_peaks"))
	falsy(EconomyLogic.isBiomeUnlocked(p, "cosmic_void"))
end)

---------------------------------------------------------------- Mutation

local function starterOf(p)
	for _, c in pairs(p.creatures) do
		if c.starter then
			return c
		end
	end
	return nil
end

test("mutation: tutorial path Basic Blob + Ice Crystal -> Frost", function()
	Locks.reset()
	local p = newProfile()
	p.currencies.dna = 5
	p.currencies.ice = 1
	local blob = starterOf(p)
	local ok, job = MutationLogic.start(p, blob.id, "ice", NOW)
	truthy(ok, job)
	eq(p.currencies.coins, 75)
	eq(p.currencies.dna, 0)
	eq(p.currencies.ice, 0)
	eq(blob.slot, nil, "creature sits in the chamber")
	falsy(Locks.isFree(p, blob.id), "locked while mutating")
	falsy(MutationLogic.start(p, blob.id, "ice", NOW), "chamber busy / no double start")
	eq(MutationLogic.complete(p, NOW + job.endsAt - NOW - 1), nil, "not finished yet")
	local result = MutationLogic.complete(p, job.endsAt)
	truthy(result and result.creature)
	eq(blob.mutation, "frost")
	eq(result.newRecipe, true)
	eq(result.newCombo, true)
	truthy(p.discovered.recipes.frost)
	eq(p.stats.mutations, 1)
	eq(blob.slot, 1, "returned to a free pad")
	eq(MutationLogic.complete(p, job.endsAt + 100), nil, "idempotent: no second reward")
	eq(p.stats.mutations, 1)
end)

test("mutation: invalid and forged requests are rejected without charging", function()
	Locks.reset()
	local p = newProfile()
	p.currencies = { coins = 10000, dna = 1000, ice = 10, toxic = 10, plasma = 10, cosmic = 10 }
	local blob = starterOf(p)
	local snapshot = table.clone(p.currencies)
	falsy(MutationLogic.start(p, blob.id, "cosmic", NOW), "cosmic on normal")
	falsy(MutationLogic.start(p, blob.id, "unobtainium", NOW), "forged ingredient")
	falsy(MutationLogic.start(p, "someone-elses-id", "ice", NOW), "not owned")
	blob.mutation = "frost"
	local ok, msg = MutationLogic.start(p, blob.id, "ice", NOW)
	falsy(ok, "frost + ice has no recipe")
	truthy(string.find(msg, "No reaction"), msg)
	ok, msg = MutationLogic.start(p, blob.id, "plasma", NOW)
	falsy(ok, "quantum needs chamber 2")
	truthy(string.find(msg, "Chamber level 2"), msg)
	for k, v in pairs(snapshot) do
		eq(p.currencies[k], v, "unchanged " .. k)
	end
	p.currencies.plasma = 1
	falsy(MutationLogic.start(p, blob.id, "plasma", NOW), "not enough plasma either")
	eq(p.activeMutation, nil)
end)

test("mutation: trade-locked creature cannot mutate", function()
	Locks.reset()
	local p = newProfile()
	p.currencies = { coins = 10000, dna = 1000, ice = 10, toxic = 0, plasma = 0, cosmic = 0 }
	local c = give(p, "frostling")
	Locks.acquire(c.id, "trade", "t1")
	falsy(MutationLogic.start(p, c.id, "ice", NOW))
	Locks.reset()
end)

test("mutation: evolution changes species and resets mutation", function()
	Locks.reset()
	local p = newProfile()
	p.upgrades.chamber = 2
	p.currencies = { coins = 100000, dna = 1000, ice = 20, toxic = 0, plasma = 0, cosmic = 0 }
	local f = give(p, "frostling", { mutation = "frost" })
	local ok, job = MutationLogic.start(p, f.id, "ice", NOW)
	truthy(ok, job)
	eq(job.kind, "evolution")
	eq(job.endsAt - NOW, Mutations.duration(Mutations.EvolutionById.evo_glacial_golem, 2), "chamber speed applied")
	local result = MutationLogic.complete(p, job.endsAt)
	eq(f.species, "glacial_golem")
	eq(f.mutation, "none")
	eq(result.newSpecies, true)
	eq(p.stats.evolutions, 1)
end)

test("mutation: interrupted session completes once after reload", function()
	Locks.reset()
	local p = newProfile()
	p.currencies.dna = 5
	p.currencies.ice = 1
	local blob = starterOf(p)
	local _, job = MutationLogic.start(p, blob.id, "ice", NOW)
	-- Simulate save + server shutdown + load on a new server later.
	local reloaded = DataSchema.load(p, job.endsAt + 3600)
	truthy(reloaded.activeMutation, "job survives the save")
	local result = MutationLogic.complete(reloaded, job.endsAt + 3600)
	truthy(result and result.creature)
	eq(reloaded.creatures[blob.id].mutation, "frost")
	eq(MutationLogic.complete(reloaded, job.endsAt + 7200), nil)
	eq(reloaded.currencies.ice, 0, "no refund on top of the result")
end)

---------------------------------------------------------------- Trading

local function tradePair()
	Locks.reset()
	local a, b = newProfile(), newProfile()
	a.currencies.coins = 1000
	b.currencies.coins = 1000
	local fa = give(a, "frostling")
	local tb = give(b, "toxic_slime")
	return a, b, fa, tb
end

local function allIds(...)
	local ids, count = {}, 0
	for _, p in ipairs({ ... }) do
		for id in pairs(p.creatures) do
			assert(not ids[id], "duplicate id across profiles: " .. id)
			ids[id] = true
			count += 1
		end
	end
	return count
end

test("trade: two-sided confirmation swaps exactly once", function()
	local a, b, fa, tb = tradePair()
	local total = allIds(a, b)
	local s = TradeLogic.newSession("t1", 1, 2, NOW)
	truthy(TradeLogic.setOffer(s, 1, a, { creatures = { fa.id }, coins = 100, dna = 0 }, NOW))
	truthy(TradeLogic.setOffer(s, 2, b, { creatures = { tb.id }, coins = 0, dna = 0 }, NOW))
	falsy(TradeLogic.setAccepted(s, 1, true, NOW), "too soon after a change")
	truthy(TradeLogic.setAccepted(s, 1, true, NOW + 3))
	falsy(TradeLogic.execute(s, a, b, NOW + 3), "needs both")
	truthy(TradeLogic.setAccepted(s, 2, true, NOW + 3))
	local ok = TradeLogic.execute(s, a, b, NOW + 4)
	truthy(ok)
	eq(a.creatures[fa.id], nil)
	truthy(b.creatures[fa.id], "B got frostling")
	truthy(a.creatures[tb.id], "A got slime")
	eq(a.currencies.coins, 900)
	eq(b.currencies.coins, 1100)
	eq(allIds(a, b), total, "no creature duplicated or lost")
	eq(Locks.get(fa.id), nil, "locks released")
	eq(b.creatures[fa.id].protectedUntil, NOW + 4 + Heist.NewCreatureProtection, "new owner protection")
	falsy(TradeLogic.execute(s, a, b, NOW + 5), "cannot execute twice")
	eq(allIds(a, b), total)
end)

test("trade: any offer change resets both confirmations", function()
	local a, b, fa = tradePair()
	local s = TradeLogic.newSession("t2", 1, 2, NOW)
	TradeLogic.setOffer(s, 1, a, { creatures = { fa.id }, coins = 0, dna = 0 }, NOW)
	TradeLogic.setAccepted(s, 1, true, NOW + 5)
	TradeLogic.setAccepted(s, 2, true, NOW + 5)
	truthy(TradeLogic.bothAccepted(s))
	TradeLogic.setOffer(s, 2, b, { creatures = {}, coins = 1, dna = 0 }, NOW + 6)
	falsy(TradeLogic.bothAccepted(s), "reset after change")
	eq(s.accepted[1], false)
end)

test("trade: rejects starter, placed, foreign and overdrawn offers", function()
	local a, b, fa = tradePair()
	local s = TradeLogic.newSession("t3", 1, 2, NOW)
	falsy(TradeLogic.setOffer(s, 1, a, { creatures = { starterOf(a).id }, coins = 0, dna = 0 }, NOW), "starter")
	fa.slot = 2
	falsy(TradeLogic.setOffer(s, 1, a, { creatures = { fa.id }, coins = 0, dna = 0 }, NOW), "placed")
	fa.slot = nil
	falsy(TradeLogic.setOffer(s, 1, a, { creatures = { starterOf(b).id }, coins = 0, dna = 0 }, NOW), "not mine")
	falsy(TradeLogic.setOffer(s, 1, a, { creatures = {}, coins = 5000, dna = 0 }, NOW), "more coins than owned")
	falsy(TradeLogic.setOffer(s, 1, a, { creatures = {}, coins = -1, dna = 0 }, NOW), "negative")
	falsy(TradeLogic.setOffer(s, 3, a, { creatures = {}, coins = 0, dna = 0 }, NOW), "outsider")
end)

test("trade: revalidation at execute cancels safely, nothing moves", function()
	local a, b, fa, tb = tradePair()
	local total = allIds(a, b)
	local s = TradeLogic.newSession("t4", 1, 2, NOW)
	TradeLogic.setOffer(s, 1, a, { creatures = { fa.id }, coins = 0, dna = 0 }, NOW)
	TradeLogic.setOffer(s, 2, b, { creatures = {}, coins = 500, dna = 0 }, NOW)
	TradeLogic.setAccepted(s, 1, true, NOW + 5)
	TradeLogic.setAccepted(s, 2, true, NOW + 5)
	b.currencies.coins = 100 -- spent elsewhere after accepting
	local ok = TradeLogic.execute(s, a, b, NOW + 6)
	falsy(ok)
	eq(s.state, "cancelled")
	truthy(a.creatures[fa.id], "A keeps creature")
	eq(b.currencies.coins, 100)
	eq(a.currencies.coins, 1000)
	eq(Locks.get(fa.id), nil, "lock released on cancel")
	eq(allIds(a, b), total)
	local _ = tb
end)

test("trade: locked offer cannot be placed, heisted or offered twice", function()
	local a, b, fa = tradePair()
	local s = TradeLogic.newSession("t5", 1, 2, NOW)
	TradeLogic.setOffer(s, 1, a, { creatures = { fa.id }, coins = 0, dna = 0 }, NOW)
	falsy(Inventory.place(a, fa.id), "can't place trade-locked creature")
	local s2 = TradeLogic.newSession("t6", 1, 3, NOW)
	falsy(TradeLogic.setOffer(s2, 1, a, { creatures = { fa.id }, coins = 0, dna = 0 }, NOW), "already in another trade")
	TradeLogic.cancel(s)
	eq(Locks.get(fa.id), nil)
	local _ = b
end)

test("trade: receiver storage capacity is checked", function()
	local a, b, fa = tradePair()
	while Inventory.count(b) < Inventory.capacity(b) do
		give(b, "basic_blob")
	end
	local s = TradeLogic.newSession("t7", 1, 2, NOW)
	TradeLogic.setOffer(s, 1, a, { creatures = { fa.id }, coins = 0, dna = 0 }, NOW)
	TradeLogic.setAccepted(s, 1, true, NOW + 5)
	TradeLogic.setAccepted(s, 2, true, NOW + 5)
	local ok, err = TradeLogic.execute(s, a, b, NOW + 6)
	falsy(ok)
	truthy(string.find(err, "storage"), err)
	truthy(a.creatures[fa.id])
end)

---------------------------------------------------------------- Heists

test("heist: eligible target passes all checks", function()
	Locks.reset()
	local victim, target = raidableVictim()
	local attacker = attackerProfile()
	local ok, err = HeistLogic.canTarget(attacker, victim, target.id, heistCtx())
	truthy(ok, err)
end)

test("heist: protections block unfair targets", function()
	Locks.reset()
	local victim, target = raidableVictim()
	local attacker = attackerProfile()
	local function blocked(label)
		local ok = HeistLogic.canTarget(attacker, victim, target.id, heistCtx())
		falsy(ok, label)
	end
	falsy(HeistLogic.canTarget(attacker, victim, starterOf(victim).id, heistCtx()), "starter protected")
	target.protectedUntil = NOW + 10
	blocked("newly acquired")
	target.protectedUntil = 0
	target.slot = nil
	blocked("stored creatures can't be stolen")
	target.slot = 2
	victim.tutorial.done = false
	blocked("new player (tutorial)")
	victim.tutorial.done = true
	victim.playSeconds = 60
	blocked("new player (playtime)")
	victim.playSeconds = 99999
	victim.heist.protectedUntil = NOW + 5
	blocked("post-theft protection")
	victim.heist.protectedUntil = 0
	falsy(HeistLogic.canTarget(attacker, victim, target.id, heistCtx({ shieldUntil = NOW + 30 })), "shield")
	falsy(HeistLogic.canTarget(attacker, victim, target.id, heistCtx({ attackerCooldownUntil = NOW + 30 })), "cooldown")
	falsy(HeistLogic.canTarget(attacker, victim, target.id, heistCtx({ pairCooldownUntil = NOW + 30 })), "same victim")
	falsy(HeistLogic.canTarget(attacker, victim, target.id, heistCtx({ victimId = 1 })), "self")
	local common = give(victim, "crystal_mite")
	common.slot = 3
	falsy(HeistLogic.canTarget(attacker, victim, common.id, heistCtx()), "commons never stealable")
	truthy(HeistLogic.canTarget(attacker, victim, target.id, heistCtx()), "still valid after all checks")
end)

test("heist: victim must keep a minimum collection", function()
	Locks.reset()
	local victim = newProfile()
	victim.tutorial.done = true
	victim.playSeconds = 99999
	local t = give(victim, "frostling")
	t.slot = 2
	eq(Inventory.count(victim), 2)
	falsy(HeistLogic.canTarget(attackerProfile(), victim, t.id, heistCtx()))
end)

test("heist: two attackers cannot claim the same creature", function()
	Locks.reset()
	local victim, target = raidableVictim()
	local a1, a2 = attackerProfile(), attackerProfile()
	truthy(HeistLogic.canTarget(a1, victim, target.id, heistCtx()))
	truthy(Locks.acquire(target.id, "heist", 1))
	falsy(HeistLogic.canTarget(a2, victim, target.id, heistCtx({ attackerId = 3 })), "second attacker blocked")
	falsy(Locks.acquire(target.id, "heist", 3), "lock held")
	local outcome = HeistLogic.resolve(a1, victim, target.id, 0, NOW)
	eq(outcome, "success")
	Locks.release(target.id, "heist", 1)
	eq(HeistLogic.resolve(a2, victim, target.id, 0, NOW), "invalid", "nothing left to steal")
	truthy(a1.creatures[target.id])
	eq(a2.creatures[target.id], nil)
	eq(victim.creatures[target.id], nil)
end)

test("heist: success transfers once with protections applied", function()
	Locks.reset()
	local victim, target = raidableVictim()
	local attacker = attackerProfile()
	local total = Inventory.count(victim) + Inventory.count(attacker)
	Locks.acquire(target.id, "heist", 1)
	local outcome, creature = HeistLogic.resolve(attacker, victim, target.id, 0.01, NOW)
	eq(outcome, "success")
	eq(creature.source, "stolen")
	eq(creature.slot, nil, "goes to storage")
	eq(creature.protectedUntil, NOW + Heist.NewCreatureProtection)
	eq(victim.heist.protectedUntil, NOW + Heist.VictimProtectionAfterTheft)
	eq(Inventory.count(victim) + Inventory.count(attacker), total, "conserved")
	eq(attacker.stats.steals, 1)
	eq(HeistLogic.resolve(attacker, victim, target.id, 0.01, NOW), "invalid", "second resolve does nothing")
	eq(Inventory.count(victim) + Inventory.count(attacker), total)
end)

test("heist: failure fines attacker (capped) and moves nothing", function()
	Locks.reset()
	local victim, target = raidableVictim()
	local attacker = attackerProfile()
	attacker.currencies.coins = 1e6
	victim.upgrades.security = 4
	Locks.acquire(target.id, "heist", 1)
	local chance = HeistLogic.successChance(4)
	eq(chance, math.max(Heist.MinSuccess, Heist.BaseSuccess + 3 * Heist.SuccessPerSecurityLevel), "security lowers odds")
	truthy(HeistLogic.successChance(50) >= Heist.MinSuccess, "never below the floor")
	local outcome, fine = HeistLogic.resolve(attacker, victim, target.id, 0.99, NOW)
	eq(outcome, "fail")
	eq(fine, Heist.FailFineMax)
	eq(attacker.currencies.coins, 1e6 - Heist.FailFineMax)
	truthy(victim.creatures[target.id], "victim keeps it")
	eq(victim.stats.defended, 1)
	eq(HeistLogic.channelTime(3), Heist.ChannelTime + 2 * Heist.ChannelPerSecurityLevel)
end)

test("heist: owner cannot pull or move a creature mid-heist", function()
	Locks.reset()
	local victim, target = raidableVictim()
	Locks.acquire(target.id, "heist", 1)
	falsy(Inventory.unplace(victim, target.id))
	falsy(Inventory.place(victim, target.id, 3), "moving to another pad would cancel the heist")
	eq(target.slot, 2)
	Locks.reset()
end)

test("heist: replaying the tutorial does not restore new-player protection", function()
	Locks.reset()
	local victim, target = raidableVictim()
	victim.tutorial.everDone = true
	victim.tutorial.done = false -- player pressed "Replay tutorial"
	truthy(HeistLogic.canTarget(attackerProfile(), victim, target.id, heistCtx()))
	local loaded = DataSchema.load({ version = 2, tutorial = { done = true } }, NOW)
	eq(loaded.tutorial.everDone, true, "existing finished players get the sticky flag")
end)

---------------------------------------------------------------- Rewards

test("rewards: daily claim once per day, streak and reset", function()
	local p = newProfile()
	local day = 86400
	local t0 = math.floor(NOW / day) * day + 100
	local ok, reward, streakDay = RewardLogic.claimDaily(p, t0)
	truthy(ok)
	eq(streakDay, 1)
	eq(reward.dna, Economy.Daily[1].dna)
	falsy(RewardLogic.claimDaily(p, t0 + 3600), "same day")
	ok, _, streakDay = RewardLogic.claimDaily(p, t0 + day)
	truthy(ok)
	eq(streakDay, 2, "streak continues")
	ok, _, streakDay = RewardLogic.claimDaily(p, t0 + 5 * day)
	truthy(ok)
	eq(streakDay, 1, "missed days reset the streak")
	local status = RewardLogic.dailyStatus(p, t0 + 5 * day + 10)
	falsy(status.canClaim)
	truthy(status.nextIn > 0 and status.nextIn <= day)
end)

test("rewards: daily income bonus is capped", function()
	local p = newProfile()
	for i = 1, 6 do
		local c = give(p, "world_eater", { level = 10 })
		c.slot = i
	end
	local reward = RewardLogic.dailyReward(p, 1)
	eq(reward.coins, Economy.Daily[1].coins * (1 + Economy.DailyIncomeCapMult))
end)

test("rewards: research and collection milestones claim once", function()
	local p = newProfile()
	falsy(RewardLogic.claimResearch(p, "first_mutation"), "not reached")
	p.stats.mutations = 1
	local dna = p.currencies.dna
	truthy(RewardLogic.claimResearch(p, "first_mutation"))
	eq(p.currencies.dna, dna + 30)
	falsy(RewardLogic.claimResearch(p, "first_mutation"), "double claim")
	falsy(RewardLogic.claimResearch(p, "made_up"))
	falsy(RewardLogic.claimCollection(p, "species_3"))
	p.discovered.species.frostling = true
	p.discovered.species.toxic_slime = true
	truthy(RewardLogic.claimCollection(p, "species_3"))
	falsy(RewardLogic.claimCollection(p, "species_3"))
end)

---------------------------------------------------------------- Helpers

test("validate: remote argument checks", function()
	truthy(Validate.id("a1b2-C3_d"))
	falsy(Validate.id("bad id"))
	falsy(Validate.id(string.rep("a", 65)))
	falsy(Validate.id(123))
	truthy(Validate.int(5, 0, 10))
	falsy(Validate.int(5.5))
	falsy(Validate.int(0 / 0))
	falsy(Validate.int(math.huge))
	truthy(Validate.idList({ "a", "b" }, 6))
	falsy(Validate.idList({ "a", "a" }, 6), "duplicates")
	falsy(Validate.idList({ "a", nil, "c" }, 6), "sparse")
	falsy(Validate.idList({ x = "a" }, 6), "dictionary")
	falsy(Validate.idList({ "a", "b", "c" }, 2), "too many")
end)

test("rate limiter: bursts then throttles then refills", function()
	local rl = RateLimiter.new(3, 1)
	truthy(rl:check(1, 0))
	truthy(rl:check(1, 0))
	truthy(rl:check(1, 0))
	falsy(rl:check(1, 0), "burst exhausted")
	truthy(rl:check(2, 0), "per-key buckets")
	truthy(rl:check(1, 1.01), "refilled")
end)

test("progression: levels are monotonic and tutorial fits", function()
	local last = -1
	for level = 1, 40 do
		local xp = Rules.xpForLevel(level)
		truthy(xp > last, "level " .. level)
		eq(Rules.levelFromXP(xp), level)
		last = xp
	end
	eq(#Tutorial.Steps, 8)
	eq(Format.number(1234), "1,234")
	eq(Format.number(12500), "12.5K")
	eq(Format.number(3_000_000), "3M")
	eq(Format.time(65), "1:05")
end)

---------------------------------------------------------------- Tutorial service (mocked registry)

local TutorialService = require(game:GetService("ServerScriptService").Server.Services.TutorialService)

local function tutorialHarness(profile)
	local handlers, notes = {}, {}
	local S = {
		Data = {
			get = function()
				return profile
			end,
			markDirty = function() end,
			isNewPlayer = function()
				return true
			end,
		},
		State = { push = function() end },
		Net = {
			notify = function(_, text)
				table.insert(notes, text)
			end,
			on = function(name, _opts, fn)
				handlers[name] = fn
			end,
		},
	}
	TutorialService.init(S)
	TutorialService.start()
	local player = {}
	local function action(kind)
		return handlers.TutorialAction(player, profile, kind)
	end
	local function event(name, amount)
		TutorialService.event(player, name, amount)
	end
	return action, event, notes
end

test("tutorial: full walkthrough completes and rewards once", function()
	local p = newProfile()
	local action, event = tutorialHarness(p)
	truthy(action("next"))
	eq(p.tutorial.step, 2)
	truthy(action("next"))
	eq(p.tutorial.step, 3)
	falsy(action("next"), "collect step needs a real collect")
	event("collect")
	eq(p.tutorial.step, 4)
	event("dna", 2)
	event("dna", 2)
	eq(p.tutorial.step, 4, "not enough yet")
	event("dna", 2)
	event("ice", 1)
	eq(p.tutorial.step, 5, "resources done")
	event("mutation") -- wrong step: ignored
	eq(p.tutorial.step, 5)
	truthy(action("chamberOpened"))
	eq(p.tutorial.step, 6)
	p.stats.mutations = 1
	event("mutation")
	eq(p.tutorial.step, 7)
	truthy(action("next"), "defense step allows Got it")
	eq(p.tutorial.step, 8)
	local coins = p.currencies.coins
	truthy(action("next"))
	eq(p.tutorial.done, true)
	eq(p.tutorial.rewarded, true)
	eq(p.currencies.coins, coins + Tutorial.CompletionReward.coins)
	truthy(action("restart"))
	eq(p.tutorial.done, false)
	for _ = 1, 10 do
		action("next")
		event("collect")
		event("chamberOpened")
		event("defense")
	end
	action("skip")
	eq(p.currencies.coins, coins + Tutorial.CompletionReward.coins, "replay never pays twice")
end)

test("tutorial: skip ends it without the reward; resources step auto-skips when owned", function()
	local p = newProfile()
	local action = tutorialHarness(p)
	truthy(action("skip"))
	eq(p.tutorial.done, true)
	eq(p.tutorial.skipped, true)
	eq(p.tutorial.rewarded, false)

	local q = newProfile()
	local action2, event2 = tutorialHarness(q)
	q.currencies.dna = 10
	q.currencies.ice = 2
	action2("next")
	action2("next")
	event2("collect")
	eq(q.tutorial.step, 5, "step 4 skipped because resources are already owned")
	falsy(action2("bogus"))
end)

---------------------------------------------------------------- Report

print(string.format("\n%d passed, %d failed", passed, failed))
for _, f in ipairs(failures) do
	print("FAIL " .. f)
end
if failed > 0 then
	error("test failures")
end
