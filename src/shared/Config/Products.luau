-- Monetization configuration. All products are optional and cosmetic or convenience only.
--
-- HOW TO CONFIGURE: create the game passes / developer products on the Creator Dashboard
-- (create.roblox.com > your experience > Monetization) and paste their numeric IDs below.
-- An id of 0 means "not configured": the store shows the item but buying it is disabled.
local Products = {}

-- Game passes (one-time, ownership re-verified every session with UserOwnsGamePassAsync).
Products.GamePasses = {
	big_backpack = {
		id = 0, -- REPLACE with your game pass ID
		name = "Big Backpack",
		description = "+25 creature storage slots.",
		bonuses = { storage = 25 },
		order = 1,
	},
	display_deluxe = {
		id = 0, -- REPLACE with your game pass ID
		name = "Display Deluxe",
		description = "+2 extra display pads on your island.",
		bonuses = { pads = 2 },
		order = 2,
	},
	theme_pack = {
		id = 0, -- REPLACE with your game pass ID
		name = "Island Theme Pack",
		description = "Unlocks the Neon, Crystal and Sunset island themes.",
		themes = { "neon", "crystal", "sunset" },
		order = 3,
	},
}

-- Developer products (processed with ProcessReceipt, idempotent by PurchaseId).
-- These grant permanent cosmetic unlocks stored in player data.
Products.DevProducts = {
	aura_sparkle = {
		id = 0, -- REPLACE with your developer product ID
		name = "Sparkle Aura",
		description = "Cosmetic sparkle effect around all your creatures.",
		grant = { aura = "sparkle" },
		order = 1,
	},
	theme_magma = {
		id = 0, -- REPLACE with your developer product ID
		name = "Magma Island Theme",
		description = "A molten cosmetic theme for your island.",
		grant = { theme = "magma" },
		order = 2,
	},
}

-- Cosmetic island themes. `default` is always owned.
Products.Themes = {
	default = {
		name = "Meadow",
		grass = Color3.fromRGB(110, 200, 110),
		rock = Color3.fromRGB(110, 96, 120),
		trim = nil, -- nil = use the island's identity color
		material = "Grass",
	},
	neon = {
		name = "Neon",
		grass = Color3.fromRGB(30, 20, 60),
		rock = Color3.fromRGB(20, 15, 40),
		trim = Color3.fromRGB(60, 255, 240),
		material = "SmoothPlastic",
	},
	crystal = {
		name = "Crystal",
		grass = Color3.fromRGB(200, 235, 255),
		rock = Color3.fromRGB(140, 170, 210),
		trim = Color3.fromRGB(160, 120, 255),
		material = "Glacier",
	},
	sunset = {
		name = "Sunset",
		grass = Color3.fromRGB(255, 170, 110),
		rock = Color3.fromRGB(150, 80, 90),
		trim = Color3.fromRGB(255, 90, 160),
		material = "Sand",
	},
	magma = {
		name = "Magma",
		grass = Color3.fromRGB(60, 30, 30),
		rock = Color3.fromRGB(40, 25, 25),
		trim = Color3.fromRGB(255, 120, 30),
		material = "Basalt",
	},
}
Products.ThemeOrder = { "default", "neon", "crystal", "sunset", "magma" }

Products.Auras = {
	sparkle = { name = "Sparkle Aura", color = Color3.fromRGB(255, 240, 160) },
}

function Products.findByProductId(productId: number)
	for key, def in pairs(Products.DevProducts) do
		if def.id ~= 0 and def.id == productId then
			return key, def
		end
	end
	return nil
end

return Products
