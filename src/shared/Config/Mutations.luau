-- Central mutation configuration: elements, ingredients, mutation types, recipes and evolutions.
-- Every reaction the server accepts is defined here and nowhere else.
local Mutations = {}

Mutations.Elements = {
	Normal = { name = "Normal", color = Color3.fromRGB(200, 205, 220) },
	Ice = { name = "Ice", color = Color3.fromRGB(120, 210, 255) },
	Toxic = { name = "Toxic", color = Color3.fromRGB(124, 255, 79) },
	Plasma = { name = "Plasma", color = Color3.fromRGB(255, 90, 220) },
	Cosmic = { name = "Cosmic", color = Color3.fromRGB(150, 110, 255) },
}

-- Things a player can put into the chamber next to a creature. `currency` is what gets spent.
Mutations.Ingredients = {
	ice = { id = "ice", name = "Ice Crystal", element = "Ice", currency = "ice", order = 1 },
	toxic = { id = "toxic", name = "Toxic Crystal", element = "Toxic", currency = "toxic", order = 2 },
	plasma = { id = "plasma", name = "Plasma Crystal", element = "Plasma", currency = "plasma", order = 3 },
	cosmic = { id = "cosmic", name = "Cosmic Energy", element = "Cosmic", currency = "cosmic", order = 4 },
	dna = { id = "dna", name = "Pure DNA", element = "Normal", currency = "dna", order = 5 },
}
Mutations.IngredientOrder = { "ice", "toxic", "plasma", "cosmic", "dna" }

-- Mutation types. `multiplier` scales income. `element` drives resonance (species element match = bonus).
Mutations.Types = {
	none = { id = "none", name = "Normal", tier = 0, multiplier = 1.0, element = "Normal" },
	frost = {
		id = "frost",
		name = "Frost",
		tier = 1,
		multiplier = 1.6,
		element = "Ice",
		color = Color3.fromRGB(150, 220, 255),
		material = "Ice",
		effect = "frost",
	},
	toxic = {
		id = "toxic",
		name = "Toxic",
		tier = 1,
		multiplier = 1.6,
		element = "Toxic",
		color = Color3.fromRGB(124, 255, 79),
		material = "SmoothPlastic",
		effect = "bubbles",
	},
	plasma = {
		id = "plasma",
		name = "Plasma",
		tier = 1,
		multiplier = 1.9,
		element = "Plasma",
		color = Color3.fromRGB(255, 90, 220),
		material = "Neon",
		effect = "sparks",
	},
	quantum = {
		id = "quantum",
		name = "Quantum",
		tier = 2,
		multiplier = 3.0,
		element = "Plasma",
		color = Color3.fromRGB(90, 240, 255),
		material = "ForceField",
		effect = "glitch",
	},
	volatile = {
		id = "volatile",
		name = "Volatile",
		tier = 2,
		multiplier = 3.0,
		element = "Toxic",
		color = Color3.fromRGB(255, 140, 40),
		material = "Neon",
		effect = "embers",
	},
	blight = {
		id = "blight",
		name = "Blight",
		tier = 2,
		multiplier = 2.6,
		element = "Ice",
		color = Color3.fromRGB(96, 120, 76),
		material = "Slate",
		effect = "smoke",
	},
	cosmic = {
		id = "cosmic",
		name = "Cosmic",
		tier = 3,
		multiplier = 5.5,
		element = "Cosmic",
		color = Color3.fromRGB(120, 60, 255),
		material = "Glass",
		effect = "stars",
	},
	supernova = {
		id = "supernova",
		name = "Supernova",
		tier = 3,
		multiplier = 7.0,
		element = "Cosmic",
		color = Color3.fromRGB(255, 236, 190),
		material = "Neon",
		effect = "flare",
	},
}
Mutations.TypeOrder = { "none", "frost", "toxic", "plasma", "quantum", "volatile", "blight", "cosmic", "supernova" }

-- Species element == mutation element gives this income bonus.
Mutations.ResonanceBonus = 1.25

-- Chamber level -> duration multiplier (faster chambers).
Mutations.ChamberSpeed = { 1.0, 0.8, 0.6, 0.45 }

-- Mutation recipes: (current mutation, ingredient) -> new mutation.
-- `cost` is the full price including the ingredient itself.
Mutations.Recipes = {
	{
		id = "frost",
		from = "none",
		ingredient = "ice",
		result = "frost",
		chamberLevel = 1,
		duration = 8,
		cost = { ice = 1, dna = 5, coins = 25 },
		hint = "Chill a plain creature with something from the Frozen Peaks.",
	},
	{
		id = "toxic",
		from = "none",
		ingredient = "toxic",
		result = "toxic",
		chamberLevel = 1,
		duration = 8,
		cost = { toxic = 1, dna = 5, coins = 25 },
		hint = "A plain creature plus a swamp crystal...",
	},
	{
		id = "plasma",
		from = "none",
		ingredient = "plasma",
		result = "plasma",
		chamberLevel = 1,
		duration = 12,
		cost = { plasma = 1, dna = 15, coins = 150 },
		hint = "Charge a plain creature with raw rift energy.",
	},
	{
		id = "quantum_fp",
		from = "frost",
		ingredient = "plasma",
		result = "quantum",
		chamberLevel = 2,
		duration = 30,
		cost = { plasma = 2, dna = 40, coins = 800 },
		hint = "What happens when ice meets lightning?",
	},
	{
		id = "quantum_pi",
		from = "plasma",
		ingredient = "ice",
		result = "quantum",
		chamberLevel = 2,
		duration = 30,
		cost = { ice = 2, dna = 40, coins = 800 },
		hint = "Freeze a charged creature solid.",
	},
	{
		id = "volatile_tp",
		from = "toxic",
		ingredient = "plasma",
		result = "volatile",
		chamberLevel = 2,
		duration = 30,
		cost = { plasma = 2, dna = 40, coins = 800 },
		hint = "Poison and plasma do not mix... or do they?",
	},
	{
		id = "volatile_pt",
		from = "plasma",
		ingredient = "toxic",
		result = "volatile",
		chamberLevel = 2,
		duration = 30,
		cost = { toxic = 2, dna = 40, coins = 800 },
		hint = "Drip swamp ooze onto something crackling.",
	},
	{
		id = "blight_ft",
		from = "frost",
		ingredient = "toxic",
		result = "blight",
		chamberLevel = 2,
		duration = 25,
		cost = { toxic = 2, dna = 30, coins = 500 },
		hint = "Frozen things rot in strange ways.",
	},
	{
		id = "blight_ti",
		from = "toxic",
		ingredient = "ice",
		result = "blight",
		chamberLevel = 2,
		duration = 25,
		cost = { ice = 2, dna = 30, coins = 500 },
		hint = "Put something poisonous on ice.",
	},
	{
		id = "cosmic_q",
		from = "quantum",
		ingredient = "cosmic",
		result = "cosmic",
		chamberLevel = 3,
		duration = 60,
		cost = { cosmic = 3, dna = 150, coins = 6000 },
		hint = "A creature in two places at once can reach the stars.",
	},
	{
		id = "cosmic_b",
		from = "blight",
		ingredient = "cosmic",
		result = "cosmic",
		chamberLevel = 3,
		duration = 60,
		cost = { cosmic = 3, dna = 150, coins = 6000 },
		hint = "Even decay glitters in the void.",
	},
	{
		id = "supernova_v",
		from = "volatile",
		ingredient = "cosmic",
		result = "supernova",
		chamberLevel = 3,
		duration = 75,
		cost = { cosmic = 5, dna = 250, coins = 12000 },
		hint = "Something unstable, fed with cosmic energy, might explode beautifully.",
	},
}

-- Evolutions: a specific species with a specific mutation + ingredient -> a new species (mutation resets).
Mutations.Evolutions = {
	{
		id = "evo_glacial_golem",
		species = "frostling",
		from = "frost",
		ingredient = "ice",
		result = "glacial_golem",
		chamberLevel = 2,
		duration = 45,
		cost = { ice = 6, dna = 80, coins = 3000 },
		hint = "A frosty Frostling craves even more ice.",
	},
	{
		id = "evo_toxic_hydra",
		species = "toxic_slime",
		from = "toxic",
		ingredient = "toxic",
		result = "toxic_hydra",
		chamberLevel = 2,
		duration = 45,
		cost = { toxic = 6, dna = 80, coins = 3000 },
		hint = "Double the poison, triple the heads?",
	},
	{
		id = "evo_quantum_blob",
		species = "basic_blob",
		from = "quantum",
		ingredient = "dna",
		result = "quantum_blob",
		chamberLevel = 2,
		duration = 45,
		cost = { dna = 60, coins = 2500 },
		hint = "A Quantum Basic Blob only needs pure DNA to stabilise.",
	},
	{
		id = "evo_neon_phantom",
		species = "plasma_wisp",
		from = "volatile",
		ingredient = "plasma",
		result = "neon_phantom",
		chamberLevel = 3,
		duration = 90,
		cost = { plasma = 10, dna = 300, coins = 25000 },
		hint = "Overcharge a Volatile Plasma Wisp.",
	},
	{
		id = "evo_rift_guardian",
		species = "ember_beast",
		from = "quantum",
		ingredient = "plasma",
		result = "rift_guardian",
		chamberLevel = 3,
		duration = 90,
		cost = { plasma = 12, dna = 350, coins = 30000 },
		hint = "An Ember Beast flickering between realities needs more rift energy.",
	},
	{
		id = "evo_star_eater",
		species = "voidling",
		from = "cosmic",
		ingredient = "cosmic",
		result = "star_eater",
		chamberLevel = 3,
		duration = 120,
		cost = { cosmic = 10, dna = 500, coins = 60000 },
		hint = "Feed a Cosmic Voidling the energy of the void itself.",
	},
	{
		id = "evo_celestial_mimic",
		species = "quantum_blob",
		from = "cosmic",
		ingredient = "cosmic",
		result = "celestial_mimic",
		chamberLevel = 4,
		duration = 150,
		cost = { cosmic = 20, dna = 1200, coins = 150000 },
		hint = "A Cosmic Quantum Blob wants to become... a treasure?",
	},
	{
		id = "evo_world_eater",
		species = "star_eater",
		from = "supernova",
		ingredient = "cosmic",
		result = "world_eater",
		chamberLevel = 4,
		duration = 240,
		cost = { cosmic = 40, dna = 3000, coins = 600000 },
		hint = "Only a Supernova Star Eater can grow large enough to swallow worlds.",
	},
}

-- Lookup tables built once.
Mutations.RecipeById = {}
Mutations.EvolutionById = {}
local recipeIndex = {}
local evolutionIndex = {}

for _, r in ipairs(Mutations.Recipes) do
	assert(Mutations.Types[r.from] and Mutations.Types[r.result], "Bad recipe " .. r.id)
	assert(Mutations.Ingredients[r.ingredient], "Bad ingredient in " .. r.id)
	local key = r.from .. "|" .. r.ingredient
	assert(recipeIndex[key] == nil, "Duplicate recipe key " .. key)
	recipeIndex[key] = r
	Mutations.RecipeById[r.id] = r
end

for _, e in ipairs(Mutations.Evolutions) do
	local key = e.species .. "|" .. e.from .. "|" .. e.ingredient
	assert(evolutionIndex[key] == nil, "Duplicate evolution key " .. key)
	evolutionIndex[key] = e
	Mutations.EvolutionById[e.id] = e
end

-- Returns the reaction for a creature state + ingredient, or nil if nothing reacts.
-- Evolutions take priority over plain mutation recipes.
function Mutations.findReaction(speciesId: string, mutationId: string, ingredientId: string)
	local evo = evolutionIndex[speciesId .. "|" .. mutationId .. "|" .. ingredientId]
	if evo then
		return {
			kind = "evolution",
			id = evo.id,
			def = evo,
			resultSpecies = evo.result,
			resultMutation = "none",
		}
	end
	local recipe = recipeIndex[mutationId .. "|" .. ingredientId]
	if recipe then
		return {
			kind = "mutation",
			id = recipe.id,
			def = recipe,
			resultSpecies = speciesId,
			resultMutation = recipe.result,
		}
	end
	return nil
end

function Mutations.duration(def, chamberLevel: number): number
	local speed = Mutations.ChamberSpeed[chamberLevel] or 1
	return math.max(3, math.floor(def.duration * speed + 0.5))
end

function Mutations.displayName(speciesName: string, mutationId: string): string
	local m = Mutations.Types[mutationId]
	if not m or mutationId == "none" then
		return speciesName
	end
	return m.name .. " " .. speciesName
end

Mutations.TotalDiscoveries = #Mutations.Recipes + #Mutations.Evolutions

return Mutations
