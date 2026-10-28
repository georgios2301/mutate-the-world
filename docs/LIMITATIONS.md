# Known limitations

## Not verified in Roblox itself

This project was built without access to Roblox Studio. Everything that could be checked
outside Roblox was (see [TESTING.md](TESTING.md)), but the game has **not been played**: world
visuals, UI layout on real screens, physics, prompts and multiplayer timing are unverified until
someone runs the Studio checklist.

## Design / technical limits

- **Cross-player saves are two DataStore writes.** Trades and heists change two profiles in one
  atomic in-memory step and then save both immediately (heists save the victim first, so a crash
  between the two writes can lose a creature but never duplicate it). For trades both sides give
  something, so a server crash in the ~second between the two writes could duplicate one side's
  items. Closing that fully needs a cross-key transaction ledger; it is not implemented.
  (For heists every later save of the thief, including autosaves, waits for the victim's save.)
- **Character movement is client-authoritative** (standard Roblox). `MovementGuard` snaps back
  blatant teleports/speed hacks, and every pickup/heist re-checks distance, but a noclip exploit
  could walk through vault walls. The door adds delay and alerts, not a hard barrier.
- **Prompt visibility is filtered on the client** (owner vs visitor). That's cosmetic; the server
  validates every trigger.
- **8 islands per server.** Set Max Players to 8; a 9th player is kicked with a message.
- **Wild creatures idle in place** (bob and respawn) rather than roaming with pathfinding.
- **Leaderboards**: global boards use OrderedDataStores refreshed every 2 minutes; without
  DataStores they show this server only.
- **Session-only fallback**: on an unpublished place or with Studio API access off, progress lives
  only as long as the server. Players get a warning.
- **English only**, no localization tables.
- **Balance** comes from spreadsheet-style tuning, not playtests. All numbers are in
  `src/shared/Config`.

## Assets and IDs you may want to supply

None are required to play.

| What | Where | Default |
| --- | --- | --- |
| Game pass / developer product IDs | `src/shared/Config/Products.luau` | `0` = shown as "Coming soon" |
| Sound effects | `src/shared/Config/Sounds.luau` | Roblox built-in `rbxasset://sounds/...` files |
| Background music | not included | none |
| Custom creature meshes | `src/shared/CreatureModels.luau` | procedural parts (8 archetypes) |
| UI icons | HUD / panels | emoji glyphs and letter badges |
| Skybox | `WorldBuilder.setupLighting` | default sky + atmosphere tint |
