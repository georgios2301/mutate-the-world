# Monetization setup

Everything sold is optional cosmetics or convenience. Core gameplay never needs Robux.
All product definitions live in `src/shared/Config/Products.luau`. Every `id` ships as `0`,
which means "not configured": the store shows the item as "Coming soon" and the server refuses
to prompt a purchase. No fictitious IDs are hard-coded.

## Items

| Key | Type | Effect |
| --- | --- | --- |
| `big_backpack` | Game pass | +25 creature storage |
| `display_deluxe` | Game pass | +2 display pads (on top of the island limit) |
| `theme_pack` | Game pass | Neon, Crystal and Sunset island themes |
| `aura_sparkle` | Developer product (one-time unlock stored in data) | Sparkle effect on your creatures |
| `theme_magma` | Developer product (one-time unlock stored in data) | Magma island theme |

## Steps

1. Publish the place (File > Publish to Roblox).
2. Creator Dashboard > your experience > **Monetization** > **Passes** > Create a Pass for each
   game pass above. Put it on sale, copy its numeric ID.
3. Monetization > **Developer Products** > Create for each developer product, copy its ID.
4. Paste each ID into the matching `id = 0` in `src/shared/Config/Products.luau` and rebuild/sync.
5. Test in Studio: purchases in Studio are test purchases (no Robux charged).

## How it's processed (server, `MonetizationService`)

- **Game passes**: ownership is checked with `MarketplaceService:UserOwnsGamePassAsync` every
  time a player joins (never trusted from saved data). Bonuses are recomputed from verified
  ownership; if a pass is removed, its bonus disappears next session and creatures on bonus pads
  go back to storage. `PromptGamePassPurchaseFinished` (server event) applies a new pass at once.
- **Developer products**: `MarketplaceService.ProcessReceipt` looks up the product by ID, checks
  the player's saved list of processed `PurchaseId`s (idempotent: a retried receipt is
  acknowledged without granting twice), grants the unlock and records the `PurchaseId` in the
  same step, saves immediately, and only then returns `PurchaseGranted`. If the save fails it
  returns `NotProcessedYet` so Roblox retries.
- Purchase prompts are opened by the server (`PromptPurchase` action), so the client can only
  ask; it can never grant.

## Private servers

Enable them in Creator Dashboard > Monetization > Private Servers. No code needed: each private
server runs the same scripts and uses the same DataStore.
