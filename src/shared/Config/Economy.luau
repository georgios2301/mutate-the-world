-- Prices, income values, upgrade tables and reward tables. All tuning lives here.
local Economy = {}

Economy.CurrencyIds = { "coins", "dna", "ice", "toxic", "plasma", "cosmic" }

Economy.CurrencyInfo = {
	coins = { name = "Coins", short = "Coins", color = Color3.fromRGB(255, 205, 70), glyph = "●" },
	dna = { name = "DNA", short = "DNA", color = Color3.fromRGB(255, 120, 200), glyph = "§" },
	ice = { name = "Ice Crystals", short = "Ice", color = Color3.fromRGB(120, 210, 255), glyph = "◆" },
	toxic = { name = "Toxic Crystals", short = "Toxic", color = Color3.fromRGB(124, 255, 79), glyph = "◆" },
	plasma = { name = "Plasma Crystals", short = "Plasma", color = Color3.fromRGB(255, 90, 220), glyph = "◆" },
	cosmic = { name = "Cosmic Energy", short = "Cosmic", color = Color3.fromRGB(160, 120, 255), glyph = "✦" },
}

-- Hard ceiling so numbers stay exact doubles and can never overflow UI or DataStores.
Economy.MaxCurrency = 1e15

Economy.StartingCurrencies = { coins = 100, dna = 0, ice = 0, toxic = 0, plasma = 0, cosmic = 0 }

Economy.BasePads = 3 -- pads at pad-upgrade level 1

-- Upgrade tables. levels[i] = { value = effect at level i, price = cost to reach level i }.
Economy.Upgrades = {
	pads = {
		name = "Display Pads",
		description = "More pads = more creatures earning coins.",
		order = 1,
		-- value = number of pads. Max level is limited by island level (see island.maxPads).
		levels = {
			{ value = 3, price = 0 },
			{ value = 4, price = 250 },
			{ value = 5, price = 700 },
			{ value = 6, price = 1800 },
			{ value = 7, price = 6000 },
			{ value = 8, price = 15000 },
			{ value = 9, price = 40000 },
			{ value = 10, price = 120000 },
			{ value = 11, price = 300000 },
			{ value = 12, price = 750000 },
		},
	},
	collector = {
		name = "Coin Collector",
		description = "How many coins your island stores before you collect.",
		order = 2,
		levels = {
			{ value = 400, price = 0 },
			{ value = 1200, price = 300 },
			{ value = 3500, price = 1200 },
			{ value = 10000, price = 4000 },
			{ value = 30000, price = 12000 },
			{ value = 90000, price = 40000 },
			{ value = 270000, price = 120000 },
			{ value = 800000, price = 400000 },
			{ value = 2500000, price = 1200000 },
		},
	},
	chamber = {
		name = "Mutation Chamber",
		description = "Unlocks advanced recipes and mutates faster.",
		order = 3,
		levels = {
			{ value = 1, price = 0 },
			{ value = 2, price = 2000 },
			{ value = 3, price = 25000 },
			{ value = 4, price = 250000 },
		},
	},
	island = {
		name = "Island Expansion",
		description = "Grows your island and raises the pad limit.",
		order = 4,
		levels = {
			{ value = 6, price = 0 }, -- value = max pads
			{ value = 9, price = 6000 },
			{ value = 12, price = 80000 },
		},
	},
	security = {
		name = "Security System",
		description = "Longer shields, slower door breaches, alarms and traps.",
		order = 5,
		levels = {
			{ value = 1, price = 0 },
			{ value = 2, price = 1500 },
			{ value = 3, price = 10000 },
			{ value = 4, price = 60000 },
		},
	},
	storage = {
		name = "Creature Storage",
		description = "How many creatures you can own.",
		order = 6,
		levels = {
			{ value = 20, price = 0 },
			{ value = 30, price = 800 },
			{ value = 40, price = 5000 },
			{ value = 55, price = 25000 },
			{ value = 70, price = 100000 },
		},
	},
}
Economy.UpgradeOrder = { "pads", "collector", "chamber", "island", "security", "storage" }

Economy.CreatureLevel = {
	maxLevel = 10,
	incomePerLevel = 0.12, -- +12% income per level above 1
	baseCoins = 60,
	growth = 1.6,
}

-- Offline earnings: a fraction of income for a limited time, still capped by the collector.
Economy.Offline = { maxSeconds = 2 * 3600, rate = 0.5 }

-- Daily reward track (7-day streak, loops). Coins also scale a little with income (capped).
Economy.Daily = {
	{ coins = 200, dna = 20 },
	{ coins = 400, dna = 30, ice = 2 },
	{ coins = 800, dna = 50, toxic = 2 },
	{ coins = 1500, dna = 80, plasma = 2 },
	{ coins = 3000, dna = 120, ice = 3, toxic = 3 },
	{ coins = 6000, dna = 200, plasma = 4 },
	{ coins = 12000, dna = 400, cosmic = 3 },
}
Economy.DailyIncomeSeconds = 120 -- bonus coins = income/s * this ...
Economy.DailyIncomeCapMult = 10 -- ... capped at base coins * this

-- Research milestones: one-time rewards for gameplay stats.
Economy.Research = {
	{ id = "first_mutation", name = "First Experiment", stat = "mutations", goal = 1, reward = { dna = 30, coins = 100 } },
	{ id = "captures_10", name = "Creature Wrangler", stat = "captures", goal = 10, reward = { dna = 60 } },
	{ id = "recipes_3", name = "Curious Mind", stat = "recipes", goal = 3, reward = { coins = 1000, ice = 2 } },
	{ id = "mutations_10", name = "Lab Regular", stat = "mutations", goal = 10, reward = { dna = 150, plasma = 2 } },
	{ id = "evolution_1", name = "Evolutionist", stat = "evolutions", goal = 1, reward = { coins = 5000, dna = 200 } },
	{ id = "defended_1", name = "Island Guardian", stat = "defended", goal = 1, reward = { coins = 500, dna = 40 } },
	{ id = "captures_50", name = "Beast Collector", stat = "captures", goal = 50, reward = { ice = 5, toxic = 5 } },
	{ id = "recipes_8", name = "Mad Scientist", stat = "recipes", goal = 8, reward = { cosmic = 3 } },
	{ id = "earned_100k", name = "Tycoon", stat = "totalEarned", goal = 100000, reward = { cosmic = 2, dna = 300 } },
	{ id = "mutations_50", name = "Mutation Master", stat = "mutations", goal = 50, reward = { cosmic = 5, dna = 600 } },
}

-- Collection milestones (species discovered / species+mutation combos discovered).
Economy.Collection = {
	{ id = "species_3", name = "Budding Collector", kind = "species", goal = 3, reward = { coins = 300, dna = 20 } },
	{ id = "combos_8", name = "Variant Hunter", kind = "combos", goal = 8, reward = { dna = 100, ice = 2, toxic = 2 } },
	{ id = "species_6", name = "Field Researcher", kind = "species", goal = 6, reward = { dna = 200, plasma = 3 } },
	{ id = "species_10", name = "Creature Scholar", kind = "species", goal = 10, reward = { cosmic = 5, coins = 20000 } },
	{ id = "combos_25", name = "Mutation Archivist", kind = "combos", goal = 25, reward = { cosmic = 8 } },
	{ id = "species_15", name = "World Mutator", kind = "species", goal = 15, reward = { cosmic = 25, coins = 250000 } },
}

Economy.XP = {
	mutation = 40,
	newRecipe = 120,
	newSpecies = 150,
	evolution = 200,
	capture = 15,
	upgrade = 25,
	collect = 2,
	daily = 30,
	heistSuccess = 60,
	defend = 60,
}

-- Creature shop (Hub market). Species must define shopPrice.
Economy.ShopSpecies = { "basic_blob", "crystal_mite" }

-- Hub/biome pickups.
Economy.Pickups = {
	hubOrbDna = 2,
	biomeOrbDna = 4,
	orbRespawn = 15,
	nodeRespawn = 25,
	hubNodeRespawn = 45,
	wildRespawnMin = 20,
	wildRespawnMax = 35,
}

-- Releasing a creature returns some DNA.
Economy.ReleaseCoinsPerIncome = 20

return Economy
