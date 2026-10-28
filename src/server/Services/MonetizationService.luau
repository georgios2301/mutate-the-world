-- Optional monetization: game passes (verified with UserOwnsGamePassAsync every session) and
-- developer products (ProcessReceipt, idempotent by PurchaseId). Nothing is ever granted
-- because a client says so. Product IDs live in Shared/Config/Products (0 = not configured).
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Products = require(Shared.Config.Products)

local Core = script.Parent.Parent.Core
local Validate = require(Core.Validate)
local Inventory = require(Core.Inventory)

local MonetizationService = {}
local S

local owned = {} -- [userId] = { [passKey] = true }

local function passKeyById(passId: number): string?
	for key, def in pairs(Products.GamePasses) do
		if def.id ~= 0 and def.id == passId then
			return key
		end
	end
	return nil
end

function MonetizationService.ownedPasses(player: Player)
	local out = {}
	for key in pairs(owned[player.UserId] or {}) do
		out[key] = true
	end
	return out
end

local function themeOwned(player: Player, profile, themeId: string): boolean
	if profile.cosmetics.themes[themeId] then
		return true
	end
	for key in pairs(owned[player.UserId] or {}) do
		local def = Products.GamePasses[key]
		if def.themes and table.find(def.themes, themeId) then
			return true
		end
	end
	return false
end

-- Recomputes pass bonuses from verified ownership (never from saved data alone).
local function applyPasses(player: Player)
	local profile = S.Data.get(player)
	if not profile then
		return
	end
	local bonuses = { storage = 0, pads = 0 }
	for key in pairs(owned[player.UserId] or {}) do
		local def = Products.GamePasses[key]
		if def.bonuses then
			for stat, amount in pairs(def.bonuses) do
				bonuses[stat] = (bonuses[stat] or 0) + amount
			end
		end
	end
	profile.passBonuses = bonuses
	Inventory.validateSlots(profile) -- creatures on pads a lost pass no longer covers go to storage
	if not themeOwned(player, profile, profile.cosmetics.theme) then
		profile.cosmetics.theme = "default"
	end
	S.Island.refresh(player)
	S.Creature.refreshIsland(player)
	S.State.push(player)
end

local function ownsPass(player: Player, passId: number): (boolean, boolean)
	local ok, has = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
	end)
	if not ok then
		warn("[Monetization] Pass check failed: " .. tostring(has))
	end
	return ok, ok and has == true
end

-- Saved bonuses stay in place until ownership is verified; a failed check never strips them.
function MonetizationService.onPlayerReady(player: Player, _profile)
	owned[player.UserId] = {}
	task.spawn(function()
		for attempt = 1, 3 do
			local allChecked = true
			local found = {}
			for key, def in pairs(Products.GamePasses) do
				if def.id ~= 0 then
					local checked, has = ownsPass(player, def.id)
					allChecked = allChecked and checked
					if has then
						found[key] = true
					end
				end
			end
			local current = owned[player.UserId]
			if not player.Parent or not current then
				return
			end
			if allChecked then
				for key in pairs(found) do
					current[key] = true
				end
				applyPasses(player)
				return
			end
			task.wait(5 * attempt)
		end
		warn("[Monetization] Keeping saved pass bonuses for " .. player.Name .. " (ownership check failed)")
	end)
end

local function processReceipt(receipt)
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local profile = S.Data.get(player)
	if not profile then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local purchases = profile.purchases
	if purchases.ids[receipt.PurchaseId] then
		return Enum.ProductPurchaseDecision.PurchaseGranted -- already granted earlier
	end
	local key, def = Products.findByProductId(receipt.ProductId)
	if not key or not def then
		warn("[Monetization] Unknown product id " .. tostring(receipt.ProductId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- Grant + record the receipt in the same synchronous step.
	if def.grant.aura then
		profile.cosmetics.auras[def.grant.aura] = true
		profile.cosmetics.aura = def.grant.aura
	end
	if def.grant.theme then
		profile.cosmetics.themes[def.grant.theme] = true
		profile.cosmetics.theme = def.grant.theme
	end
	purchases.ids[receipt.PurchaseId] = true
	table.insert(purchases.order, receipt.PurchaseId)
	S.Data.markDirty(player)

	if not S.Data.saveNow(player) then
		-- Roblox will retry; the recorded PurchaseId prevents a double grant in this session.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	S.Island.refresh(player)
	S.Creature.refreshIsland(player)
	S.State.push(player)
	S.Net.notify(player, "Thank you! " .. def.name .. " unlocked.", "success")
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function MonetizationService.init(services)
	S = services
end

function MonetizationService.start()
	MarketplaceService.ProcessReceipt = processReceipt

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if not purchased then
			return
		end
		local key = passKeyById(passId)
		if not key then
			return
		end
		-- Re-verify ownership instead of trusting the event (retry: ownership can lag a moment).
		for _ = 1, 4 do
			local _, has = ownsPass(player, passId)
			if has and owned[player.UserId] and player.Parent then
				owned[player.UserId][key] = true
				applyPasses(player)
				S.Net.notify(player, "Thank you! " .. Products.GamePasses[key].name .. " is active.", "success")
				return
			end
			task.wait(2)
		end
		warn("[Monetization] Purchase event for pass " .. passId .. " not confirmed by UserOwnsGamePassAsync")
	end)

	S.Net.on("PromptPurchase", { rate = { 3, 1 }, push = false }, function(player, profile, kind, key)
		if kind ~= "pass" and kind ~= "product" then
			return false, "Unknown item"
		end
		local list = if kind == "pass" then Products.GamePasses else Products.DevProducts
		if not Validate.oneOf(key, list) then
			return false, "Unknown item"
		end
		local def = list[key]
		if def.id == 0 then
			return false, "This item isn't available yet. (Developer: set its ID in Shared/Config/Products.)"
		end
		if kind == "pass" then
			if owned[player.UserId] and owned[player.UserId][key] then
				return false, "You already own this"
			end
			MarketplaceService:PromptGamePassPurchase(player, def.id)
		else
			if def.grant.theme and profile.cosmetics.themes[def.grant.theme] then
				return false, "You already own this"
			end
			if def.grant.aura and profile.cosmetics.auras[def.grant.aura] then
				return false, "You already own this"
			end
			MarketplaceService:PromptProductPurchase(player, def.id)
		end
		return true
	end)

	S.Net.on("EquipTheme", { rate = { 4, 2 } }, function(player, profile, themeId)
		if not Validate.oneOf(themeId, Products.Themes) then
			return false, "Unknown theme"
		end
		if not themeOwned(player, profile, themeId) then
			return false, "You don't own that theme"
		end
		profile.cosmetics.theme = themeId
		S.Island.refresh(player)
		return true, Products.Themes[themeId].name .. " theme applied"
	end)

	S.Net.on("EquipAura", { rate = { 4, 2 } }, function(player, profile, auraId)
		if auraId ~= "" and not (Validate.oneOf(auraId, Products.Auras) and profile.cosmetics.auras[auraId]) then
			return false, "You don't own that effect"
		end
		profile.cosmetics.aura = auraId
		S.Creature.refreshIsland(player)
		return true
	end)

	Players.PlayerRemoving:Connect(function(player)
		owned[player.UserId] = nil
	end)
end

return MonetizationService
