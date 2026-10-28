# Testing

## What was verified without Roblox Studio

| Check | Tool | Result |
| --- | --- | --- |
| Pure game logic (47 tests: data, wallet, inventory, economy, mutations, trades, heists, rewards, tutorial, validation, rate limits, config integrity) | `python3 tests/run_tests.py` (bundles the ModuleScripts with a fake Instance tree and runs them on the `luau` CLI) | 47 passed |
| Every script type-checked against the Roblox API (property/method names, argument types, require paths) | `luau-lsp analyze` with Roblox definitions + Rojo sourcemap | clean |
| Every key in dynamic property tables (`Kit.new`, `Kit.frame`, `Build.part`, `Build.disc`) is a real property of its class | `python3 tests/check_props.py` | 579 keys, 0 problems |
| Place builds | `rojo build` | `build/MutateTheWorld.rbxlx` |
| Independent code review (server security/consistency, client runtime) | two review agents | 24 findings, all fixed or documented (list below) |

Run everything with `scripts/verify.sh` (set `LUAU_LSP` and `LUAU_DEFS` for the type check).

## Review findings fixed

Server: tutorial replay granted permanent raid immunity (now a sticky `everDone` flag);
creatures could be stolen through the glass vault walls (thief must now be inside the vault
for the whole heist); a late save after leaving re-took the session lock; rejoining the same
server during a slow save lost the new session; the owner could cancel a heist by moving the
creature to another pad; one odd error string could switch a live server to memory-only saving;
rejoining reset the thief cooldown; pass themes reset on rejoin; pass bonuses were dropped when
the ownership check errored; pass purchases are now re-verified; heist saves now wait for the
victim's save (autosave included).

Client: trade panel could show an offer different from the server's; the tutorial card covered
panel buttons; the goal card sat under Roblox's player list; text was too small on phones;
menu overlapped currencies on phones; trade lists rebuilt every second (lost taps, broken
gamepad selection); scaled blocks overlapped at large scales; gamepad selection was lost on
list rebuilds and the reveal card couldn't be dismissed with B; inventory details overflowed;
the tutorial guide broke after a target was rebuilt or the player respawned; hidden previews
kept spinning; milestone text and shop icons overlapped; the upgrade console opened the wrong
tab; unconfigured Robux items looked clickable.

## Acceptance tests

"Logic-tested" = covered by `tests/spec.luau`. "Studio" = needs a manual run (checklist below).

| Acceptance test | Status |
| --- | --- |
| A new player can join and receive an island | Logic-tested (starter, defaults); island assignment needs Studio |
| Two or more players can play simultaneously | Studio |
| A player can earn coins | Logic-tested (accrue, cap, collect, offline cap) |
| A player can buy an upgrade | Logic-tested (prices, levels, island pad limit, max level) |
| A player can complete a mutation | Logic-tested (tutorial recipe, evolution, chamber speed, resume after reload) |
| Invalid mutation requests are rejected | Logic-tested (no recipe, forged ingredient, not owned, chamber too low, unaffordable, busy, locked) |
| A player's inventory updates correctly | Logic-tested (add/remove/place/unique ids/capacity); UI needs Studio |
| A player cannot steal a protected creature | Logic-tested (starter, common, new creature, stored, newbie, post-theft, shield, cooldowns, min collection) |
| Two attackers cannot steal the same creature simultaneously | Logic-tested (lock + single transfer) |
| A defender can activate a shield | Shield blocks heists in logic tests; activation needs Studio |
| A trade can be completed without duplicating items | Logic-tested (swap, double execute, revalidation cancel, capacity, locks) |
| Invalid currency requests are rejected | Logic-tested (negative, NaN, fractional, unknown currency, overdraw) |
| Progress survives leaving and rejoining (DataStores configured) | Serialization/migration logic-tested; real DataStore needs Studio (published + API access) |
| The UI works at different screen sizes | Responsive scale implemented; needs Studio device emulator |
| The tutorial can be completed and skipped | Logic-tested (walkthrough, skip, replay without double reward or regained raid immunity) |
| No core button is nonfunctional | Every button is wired to a registered action or panel (reviewed); Studio click-through below |
| No essential feature depends on a placeholder | Only optional Robux items wait for IDs (shown as "Coming soon") |

## Studio checklist

Setup: open `build/MutateTheWorld.rbxlx`, publish, enable Studio API access (for saving).

**Solo (Play)**
1. You spawn on your island with Basic Blob on pad 1, tutorial card at the bottom, guide beam visible.
2. Tutorial: Next, Next, wait ~10 s, collect at the Collector (prompt or HUD Collect).
3. HUD ⇄ Hub. Touch 3 pink orbs (+2 DNA each), hold E on an ice crystal in the Grove.
4. HUD 🏠 Home, open the chamber (prompt). Basic Blob + Ice Crystal are preselected. MUTATE.
   After 8 s: reveal card, Blob turns frosty on its pad, Journal shows "Normal + Ice → Frost".
5. Security panel: activate Shield (dome appears), toggle the door. Finish the tutorial (+150 coins).
6. Shop > Upgrades: buy Display Pads (250). Pad 4 lights up.
7. Hub grove: capture a wild Basic Blob (3 DNA). It auto-places on a free pad.
8. Shop > Rewards: claim the daily reward. Try again → "Come back tomorrow".
9. Travel: Frozen Peaks open, Toxic Swamp locked with requirements; reach level 2 + 600 coins → Unlock.
10. Settings: toggle SFX, popups, reduced effects; UI size − / +; replay tutorial.
11. Leave and rejoin (published + API access): coins, creatures, discoveries, tutorial state persist.

**Multiplayer (Test > Clients and Servers, 2–3 players)**
1. Each player gets a different colored island; signs show names.
2. Player A gives a Frostling to a pad (needs 20 min playtime + finished tutorial on A to be raidable;
   for testing lower `Heist.NewPlayerProtectionSeconds` in `Config/Heist.luau`).
3. Player B: Travel > Other islands > Visit A. Hold E on the door (breach). A sees the alert.
   Trying to steal from outside the vault glass says "Get inside the vault first".
4. Inside the vault, B holds F on the Frostling. A sees the red THIEF banner with Shield / Zap / Go Home.
   - A presses Zap → B is stunned, heist fails, B fined.
   - Or wait → success (80%) moves the creature to B's storage; A's island becomes protected.
5. Player C tries the same creature while B is stealing → "Someone else is already raiding this island".
6. Trade: A and B stand together in the Hub. A: More → Trade → Request. B accepts.
   Change offers (both checkmarks reset), accept both, 3 s countdown, items swap once.
7. Leave mid-trade → the other player sees "left the game", nothing moves.

**Screens**: Studio Test > Device emulator: iPhone (landscape), iPad, 1080p. HUD and panels
should scale and stay on screen; every button reachable by touch.

## Not testable here

Real DataStore throttling, MarketplaceService purchases (need real IDs), network latency,
exploit tools and device performance.
