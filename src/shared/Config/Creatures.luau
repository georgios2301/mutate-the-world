-- Data-driven creature species. Models are generated from `look` by Shared/CreatureModels,
-- so a new species only needs a new entry here (no new model files).
local Creatures = {}

Creatures.Species = {}
Creatures.Order = {} -- collection index order

export type Look = {
	archetype: string,
	primary: Color3,
	secondary: Color3,
	accent: Color3,
	material: string?,
	scale: number,
	eyes: number?,
	spikes: number?,
	heads: number?,
	glow: boolean?,
}

local function define(def)
	assert(Creatures.Species[def.id] == nil, "Duplicate species " .. def.id)
	def.index = #Creatures.Order + 1
	if def.tradable == nil then
		def.tradable = true
	end
	Creatures.Species[def.id] = def
	table.insert(Creatures.Order, def.id)
end

define({
	id = "basic_blob",
	name = "Basic Blob",
	rarity = "Common",
	element = "Normal",
	baseIncome = 1,
	description = "A wobbly lump of pure potential. Mutates eagerly.",
	origin = { kind = "wild", zones = { "hub" }, text = "Starter creature. Wanders the Hub Grove." },
	shopPrice = 120,
	look = {
		archetype = "Blob",
		primary = Color3.fromRGB(150, 165, 255),
		secondary = Color3.fromRGB(235, 240, 255),
		accent = Color3.fromRGB(90, 100, 200),
		scale = 1,
		eyes = 2,
	},
})

define({
	id = "crystal_mite",
	name = "Crystal Mite",
	rarity = "Common",
	element = "Normal",
	baseIncome = 2,
	description = "Grows tiny crystals on its back and sheds them as coins.",
	origin = { kind = "wild", zones = { "hub", "frozen_peaks" }, text = "Scuttles around the Hub Grove." },
	shopPrice = 450,
	look = {
		archetype = "Insect",
		primary = Color3.fromRGB(196, 160, 118),
		secondary = Color3.fromRGB(120, 92, 70),
		accent = Color3.fromRGB(110, 240, 255),
		scale = 0.9,
		eyes = 2,
		spikes = 3,
	},
})

define({
	id = "frostling",
	name = "Frostling",
	rarity = "Uncommon",
	element = "Ice",
	baseIncome = 4,
	description = "A cheerful sprite that leaves frost footprints.",
	origin = { kind = "wild", zones = { "frozen_peaks" }, text = "Lives in the Frozen Peaks." },
	look = {
		archetype = "Sprite",
		primary = Color3.fromRGB(170, 230, 255),
		secondary = Color3.fromRGB(245, 252, 255),
		accent = Color3.fromRGB(80, 170, 255),
		scale = 1,
		eyes = 2,
		spikes = 2,
	},
})

define({
	id = "toxic_slime",
	name = "Toxic Slime",
	rarity = "Uncommon",
	element = "Toxic",
	baseIncome = 4,
	description = "Bubbling, glowing and surprisingly affectionate.",
	origin = { kind = "wild", zones = { "toxic_swamp" }, text = "Oozes through the Toxic Swamp." },
	look = {
		archetype = "Blob",
		primary = Color3.fromRGB(124, 230, 79),
		secondary = Color3.fromRGB(200, 255, 140),
		accent = Color3.fromRGB(60, 120, 30),
		scale = 1.05,
		eyes = 3,
		spikes = 0,
	},
})

define({
	id = "plasma_wisp",
	name = "Plasma Wisp",
	rarity = "Rare",
	element = "Plasma",
	baseIncome = 9,
	description = "A crackling spark of living energy.",
	origin = { kind = "wild", zones = { "plasma_rift" }, text = "Drifts through the Plasma Rift." },
	look = {
		archetype = "Wisp",
		primary = Color3.fromRGB(255, 110, 230),
		secondary = Color3.fromRGB(255, 200, 250),
		accent = Color3.fromRGB(150, 60, 255),
		scale = 0.9,
		eyes = 2,
		glow = true,
	},
})

define({
	id = "ember_beast",
	name = "Ember Beast",
	rarity = "Rare",
	element = "Plasma",
	baseIncome = 11,
	description = "Its mane is a ring of plasma flames. Warm to the touch.",
	origin = { kind = "wild", zones = { "plasma_rift" }, text = "Prowls the Plasma Rift (uncommon sighting)." },
	look = {
		archetype = "Quadruped",
		primary = Color3.fromRGB(255, 122, 48),
		secondary = Color3.fromRGB(70, 34, 30),
		accent = Color3.fromRGB(255, 220, 90),
		scale = 1,
		eyes = 2,
		spikes = 5,
	},
})

define({
	id = "voidling",
	name = "Voidling",
	rarity = "Epic",
	element = "Cosmic",
	baseIncome = 25,
	description = "One enormous eye that has seen the edge of the world.",
	origin = { kind = "wild", zones = { "cosmic_void" }, text = "Hides in the Cosmic Void." },
	look = {
		archetype = "Wisp",
		primary = Color3.fromRGB(64, 24, 112),
		secondary = Color3.fromRGB(190, 120, 255),
		accent = Color3.fromRGB(255, 255, 255),
		scale = 1.1,
		eyes = 1,
		glow = true,
	},
})

define({
	id = "glacial_golem",
	name = "Glacial Golem",
	rarity = "Epic",
	element = "Ice",
	baseIncome = 22,
	description = "A Frostling that absorbed an entire glacier.",
	origin = { kind = "evolution", text = "Evolve a Frost-mutated Frostling." },
	look = {
		archetype = "Golem",
		primary = Color3.fromRGB(150, 210, 245),
		secondary = Color3.fromRGB(230, 248, 255),
		accent = Color3.fromRGB(60, 140, 230),
		material = "Ice",
		scale = 1.15,
		eyes = 2,
		spikes = 4,
	},
})

define({
	id = "toxic_hydra",
	name = "Toxic Hydra",
	rarity = "Epic",
	element = "Toxic",
	baseIncome = 22,
	description = "Three heads, one appetite, zero manners.",
	origin = { kind = "evolution", text = "Evolve a Toxic-mutated Toxic Slime." },
	look = {
		archetype = "Serpent",
		primary = Color3.fromRGB(90, 200, 70),
		secondary = Color3.fromRGB(190, 255, 120),
		accent = Color3.fromRGB(40, 90, 30),
		scale = 1,
		eyes = 2,
		heads = 3,
		spikes = 3,
	},
})

define({
	id = "quantum_blob",
	name = "Quantum Blob",
	rarity = "Rare",
	element = "Plasma",
	baseIncome = 12,
	description = "Exists in two places at once. Mostly in your pocket.",
	origin = { kind = "evolution", text = "Evolve a Quantum-mutated Basic Blob." },
	look = {
		archetype = "Blob",
		primary = Color3.fromRGB(80, 235, 255),
		secondary = Color3.fromRGB(200, 120, 255),
		accent = Color3.fromRGB(255, 255, 255),
		material = "Glass",
		scale = 1.1,
		eyes = 2,
		glow = true,
	},
})

define({
	id = "neon_phantom",
	name = "Neon Phantom",
	rarity = "Legendary",
	element = "Plasma",
	baseIncome = 60,
	description = "A Plasma Wisp that burned so bright it became a ghost.",
	origin = { kind = "evolution", text = "Evolve a Volatile-mutated Plasma Wisp." },
	look = {
		archetype = "Wisp",
		primary = Color3.fromRGB(255, 60, 200),
		secondary = Color3.fromRGB(60, 255, 240),
		accent = Color3.fromRGB(255, 255, 120),
		material = "Neon",
		scale = 1.25,
		eyes = 2,
		glow = true,
	},
})

define({
	id = "star_eater",
	name = "Star Eater",
	rarity = "Legendary",
	element = "Cosmic",
	baseIncome = 70,
	description = "Snacks on starlight. Purrs like a black hole.",
	origin = { kind = "evolution", text = "Evolve a Cosmic-mutated Voidling." },
	look = {
		archetype = "Quadruped",
		primary = Color3.fromRGB(40, 30, 90),
		secondary = Color3.fromRGB(255, 230, 120),
		accent = Color3.fromRGB(150, 110, 255),
		scale = 1.3,
		eyes = 3,
		spikes = 6,
		glow = true,
	},
})

define({
	id = "rift_guardian",
	name = "Rift Guardian",
	rarity = "Legendary",
	element = "Plasma",
	baseIncome = 65,
	description = "An ancient sentinel forged where the Plasma Rift tore open.",
	origin = { kind = "evolution", text = "Evolve a Quantum-mutated Ember Beast." },
	look = {
		archetype = "Golem",
		primary = Color3.fromRGB(70, 40, 90),
		secondary = Color3.fromRGB(255, 90, 210),
		accent = Color3.fromRGB(255, 200, 80),
		material = "Basalt",
		scale = 1.35,
		eyes = 1,
		spikes = 6,
		glow = true,
	},
})

define({
	id = "celestial_mimic",
	name = "Celestial Mimic",
	rarity = "Mythic",
	element = "Cosmic",
	baseIncome = 160,
	description = "Pretends to be a treasure chest. Is actually a galaxy.",
	origin = { kind = "evolution", text = "Evolve a Cosmic-mutated Quantum Blob." },
	look = {
		archetype = "Mimic",
		primary = Color3.fromRGB(60, 40, 140),
		secondary = Color3.fromRGB(255, 215, 110),
		accent = Color3.fromRGB(120, 255, 250),
		scale = 1.2,
		eyes = 2,
		glow = true,
	},
})

define({
	id = "world_eater",
	name = "World Eater",
	rarity = "Cosmic",
	element = "Cosmic",
	baseIncome = 400,
	description = "The final form. Legends say it once swallowed a biome.",
	origin = { kind = "evolution", text = "Evolve a Supernova-mutated Star Eater." },
	look = {
		archetype = "Serpent",
		primary = Color3.fromRGB(25, 15, 55),
		secondary = Color3.fromRGB(110, 255, 240),
		accent = Color3.fromRGB(255, 120, 230),
		material = "Glass",
		scale = 1.45,
		eyes = 4,
		heads = 1,
		spikes = 8,
		glow = true,
	},
})

Creatures.StarterSpecies = "basic_blob"

function Creatures.get(id: string)
	return Creatures.Species[id]
end

return Creatures
