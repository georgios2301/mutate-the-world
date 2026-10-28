-- Rarity tiers. Higher rank = rarer. Colors are used by UI, billboards and announcements.
local Rarity = {}

Rarity.Order = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Cosmic" }

Rarity.Info = {
	Common = {
		rank = 1,
		color = Color3.fromRGB(176, 183, 195),
		stealable = false, -- commons are never stealable (protects new players)
		captureDna = 3,
		releaseDna = 1,
		levelCostMult = 1,
		announce = false,
	},
	Uncommon = {
		rank = 2,
		color = Color3.fromRGB(91, 227, 125),
		stealable = true,
		captureDna = 12,
		releaseDna = 5,
		levelCostMult = 3,
		announce = false,
	},
	Rare = {
		rank = 3,
		color = Color3.fromRGB(63, 169, 255),
		stealable = true,
		captureDna = 35,
		releaseDna = 14,
		levelCostMult = 8,
		announce = false,
	},
	Epic = {
		rank = 4,
		color = Color3.fromRGB(179, 107, 255),
		stealable = true,
		captureDna = 90,
		releaseDna = 40,
		levelCostMult = 20,
		announce = true,
	},
	Legendary = {
		rank = 5,
		color = Color3.fromRGB(255, 178, 63),
		stealable = true,
		captureDna = 220,
		releaseDna = 100,
		levelCostMult = 50,
		announce = true,
	},
	Mythic = {
		rank = 6,
		color = Color3.fromRGB(255, 79, 163),
		stealable = true,
		captureDna = 500,
		releaseDna = 250,
		levelCostMult = 120,
		announce = true,
	},
	Cosmic = {
		rank = 7,
		color = Color3.fromRGB(107, 255, 242),
		stealable = true,
		captureDna = 1200,
		releaseDna = 600,
		levelCostMult = 300,
		announce = true,
	},
}

function Rarity.rank(name: string): number
	local info = Rarity.Info[name]
	return info and info.rank or 0
end

function Rarity.color(name: string): Color3
	local info = Rarity.Info[name]
	return info and info.color or Color3.fromRGB(255, 255, 255)
end

return Rarity
