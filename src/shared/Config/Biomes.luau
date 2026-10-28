-- Biome definitions: unlock requirements, resources and wild creature spawn tables.
-- Spawn weights are shown to players in the Travel menu (no hidden odds).
local Biomes = {}

Biomes.Order = { "frozen_peaks", "toxic_swamp", "plasma_rift", "cosmic_void" }

Biomes.Defs = {
	frozen_peaks = {
		id = "frozen_peaks",
		name = "Frozen Peaks",
		element = "Ice",
		crystal = "ice",
		color = Color3.fromRGB(120, 210, 255),
		description = "Snowy cliffs full of Ice Crystals and Frostlings.",
		unlockedByDefault = true,
		requirements = {},
		crystalYield = 1,
		wild = {
			{ species = "frostling", weight = 75 },
			{ species = "crystal_mite", weight = 25 },
		},
	},
	toxic_swamp = {
		id = "toxic_swamp",
		name = "Toxic Swamp",
		element = "Toxic",
		crystal = "toxic",
		color = Color3.fromRGB(124, 255, 79),
		description = "Bubbling bogs with Toxic Crystals and Toxic Slimes.",
		requirements = { level = 2, coins = 600 },
		crystalYield = 1,
		wild = {
			{ species = "toxic_slime", weight = 80 },
			{ species = "basic_blob", weight = 20 },
		},
	},
	plasma_rift = {
		id = "plasma_rift",
		name = "Plasma Rift",
		element = "Plasma",
		crystal = "plasma",
		color = Color3.fromRGB(255, 90, 220),
		description = "A crackling tear in the sky. Plasma Crystals, Wisps and Ember Beasts.",
		requirements = { level = 5, coins = 6000, recipes = 2 },
		crystalYield = 1,
		wild = {
			{ species = "plasma_wisp", weight = 70 },
			{ species = "ember_beast", weight = 30 },
		},
	},
	cosmic_void = {
		id = "cosmic_void",
		name = "Cosmic Void",
		element = "Cosmic",
		crystal = "cosmic",
		color = Color3.fromRGB(150, 110, 255),
		description = "The edge of the world. Cosmic Energy and the elusive Voidling.",
		requirements = { level = 9, coins = 60000, chamber = 3 },
		crystalYield = 1,
		wild = {
			{ species = "voidling", weight = 100 },
		},
	},
}

-- The hub grove also has wild creatures.
Biomes.HubWild = {
	{ species = "basic_blob", weight = 70 },
	{ species = "crystal_mite", weight = 30 },
}

return Biomes
