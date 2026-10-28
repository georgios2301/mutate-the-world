-- Tutorial steps. `advance` says what completes the step:
--   manual   = the player presses Next
--   collect  = server: player collected island coins
--   resources= server: player picked up enough DNA + an Ice Crystal (or already owns them)
--   chamber  = client opened the Mutation Chamber
--   mutation = server: a mutation finished
--   defense  = server: shield activated or door toggled (Next also works)
-- `target` tells the client where to point the guide arrow.
local Tutorial = {}

Tutorial.Steps = {
	{
		id = "welcome",
		title = "Welcome, Mutator!",
		text = "This floating island is yours. Let's turn it into a creature empire.",
		advance = "manual",
		target = "island",
	},
	{
		id = "blob",
		title = "Meet Basic Blob",
		text = "Your first creature sits on a display pad. Creatures on pads earn coins.",
		advance = "manual",
		target = "starter",
	},
	{
		id = "income",
		title = "Collect your coins",
		text = "Coins pile up in the Collector. Walk to it and collect them.",
		advance = "collect",
		target = "collector",
	},
	{
		id = "resources",
		title = "Gather resources",
		text = "Travel to the Hub. Grab 3 pink DNA orbs and harvest 1 Ice Crystal in the Grove.",
		advance = "resources",
		target = "resources",
		needDna = 6, -- 3 hub orbs x 2 DNA
		needIce = 1,
	},
	{
		id = "chamber",
		title = "Open the Chamber",
		text = "Go home and open your Mutation Chamber.",
		advance = "chamber",
		target = "chamber",
	},
	{
		id = "mutate",
		title = "Your first mutation",
		text = "Pick Basic Blob, add an Ice Crystal and press MUTATE.",
		advance = "mutation",
		target = "chamber",
	},
	{
		id = "protect",
		title = "Guard your island",
		text = "Thieves can raid rare creatures. Use the Shield and door lock in Security.",
		advance = "defense",
		target = "security",
	},
	{
		id = "goals",
		title = "Mutate the World!",
		text = "Unlock biomes, discover every recipe and fill your Collection. Good luck!",
		advance = "manual",
		target = "hub",
	},
}

Tutorial.CompletionReward = { coins = 150, dna = 15 }

return Tutorial
