# Game Design

All numbers below are generated from `src/shared/Config/*.luau` (the single source of truth).
Change the config, not the scripts.

## Core loop

1. Join → you get one of 8 floating islands and a **Basic Blob** on display pad 1.
2. Creatures on pads earn coins every second into your island's **Collector** (capped by
   Collector level, so idling can't earn forever; offline earnings are 50% for at most 2 hours).
3. Collect coins → buy upgrades (pads, collector, chamber, island expansion, security, storage).
4. Travel to the **Hub** and **biomes** to collect DNA orbs, harvest crystals and capture wild creatures.
5. In the **Mutation Chamber** combine a creature with an element. Defined recipes give a new
   mutation (income multiplier) or, for specific species, an **evolution** into a new species.
6. Fill the **Collection Index** (15 species × 9 mutations) and the **Discovery Journal**
   (12 recipes + 8 evolutions), claim milestones, unlock biomes, climb the leaderboards.
7. Raid other players' islands for rare creatures, defend your own, trade safely.

Higher rarity earns more, but other decisions stay relevant: limited pads, resonance bonus
(+25% when a creature's element matches its mutation), level-ups (+12%/level, 10 levels),
and the fact that only Uncommon+ creatures on pads can be stolen.

## First five minutes (tutorial)

| Step | Goal | Completes when |
| --- | --- | --- |
| 1 | Welcome to your island | Next |
| 2 | Meet Basic Blob (arrow points at it) | Next |
| 3 | Collect coins at the Collector | server sees a collect |
| 4 | Hub: grab 3 DNA orbs + harvest 1 Ice Crystal in the Grove | server counts pickups (or you already own 5 DNA + 1 ice) |
| 5 | Go home, open the Mutation Chamber | chamber panel opened |
| 6 | Mutate Basic Blob + Ice Crystal (preselected) | mutation completes |
| 7 | Guard your island: Shield or door lock | shield/door used, or "Got it" |
| 8 | Long-term goals | Finish → +150 coins, +15 DNA (only if a mutation was really done) |

A guide beam and ▼ marker point at each objective. "Skip tutorial" is always visible and
Settings can replay it. Tutorial progress is saved.

### Creatures

| # | Species | Rarity | Element | Base income/s | Model | How to get |
|---|---|---|---|---|---|---|
| 1 | Basic Blob | Common | Normal | 1 | Blob | Starter creature. Wanders the Hub Grove. Shop: 120 coins. |
| 2 | Crystal Mite | Common | Normal | 2 | Insect | Scuttles around the Hub Grove. Shop: 450 coins. |
| 3 | Frostling | Uncommon | Ice | 4 | Sprite | Lives in the Frozen Peaks. |
| 4 | Toxic Slime | Uncommon | Toxic | 4 | Blob | Oozes through the Toxic Swamp. |
| 5 | Plasma Wisp | Rare | Plasma | 9 | Wisp | Drifts through the Plasma Rift. |
| 6 | Ember Beast | Rare | Plasma | 11 | Quadruped | Prowls the Plasma Rift (uncommon sighting). |
| 7 | Voidling | Epic | Cosmic | 25 | Wisp | Hides in the Cosmic Void. |
| 8 | Glacial Golem | Epic | Ice | 22 | Golem | Evolve a Frost-mutated Frostling. |
| 9 | Toxic Hydra | Epic | Toxic | 22 | Serpent | Evolve a Toxic-mutated Toxic Slime. |
| 10 | Quantum Blob | Rare | Plasma | 12 | Blob | Evolve a Quantum-mutated Basic Blob. |
| 11 | Neon Phantom | Legendary | Plasma | 60 | Wisp | Evolve a Volatile-mutated Plasma Wisp. |
| 12 | Star Eater | Legendary | Cosmic | 70 | Quadruped | Evolve a Cosmic-mutated Voidling. |
| 13 | Rift Guardian | Legendary | Plasma | 65 | Golem | Evolve a Quantum-mutated Ember Beast. |
| 14 | Celestial Mimic | Mythic | Cosmic | 160 | Mimic | Evolve a Cosmic-mutated Quantum Blob. |
| 15 | World Eater | Cosmic | Cosmic | 400 | Serpent | Evolve a Supernova-mutated Star Eater. |

### Mutation types

| Mutation | Tier | Income × | Element (resonance) |
|---|---|---|---|
| Normal | 0 | 1 | Normal |
| Frost | 1 | 1.6 | Ice |
| Toxic | 1 | 1.6 | Toxic |
| Plasma | 1 | 1.9 | Plasma |
| Quantum | 2 | 3 | Plasma |
| Volatile | 2 | 3 | Toxic |
| Blight | 2 | 2.6 | Ice |
| Cosmic | 3 | 5.5 | Cosmic |
| Supernova | 3 | 7 | Cosmic |

### Mutation recipes

| Id | Current mutation + Ingredient | Result | Chamber | Base time | Cost |
|---|---|---|---|---|---|
| frost | Normal + Ice Crystal | Frost | 1 | 8s | 25 Coins · 5 DNA · 1 Ice |
| toxic | Normal + Toxic Crystal | Toxic | 1 | 8s | 25 Coins · 5 DNA · 1 Toxic |
| plasma | Normal + Plasma Crystal | Plasma | 1 | 12s | 150 Coins · 15 DNA · 1 Plasma |
| quantum_fp | Frost + Plasma Crystal | Quantum | 2 | 30s | 800 Coins · 40 DNA · 2 Plasma |
| quantum_pi | Plasma + Ice Crystal | Quantum | 2 | 30s | 800 Coins · 40 DNA · 2 Ice |
| volatile_tp | Toxic + Plasma Crystal | Volatile | 2 | 30s | 800 Coins · 40 DNA · 2 Plasma |
| volatile_pt | Plasma + Toxic Crystal | Volatile | 2 | 30s | 800 Coins · 40 DNA · 2 Toxic |
| blight_ft | Frost + Toxic Crystal | Blight | 2 | 25s | 500 Coins · 30 DNA · 2 Toxic |
| blight_ti | Toxic + Ice Crystal | Blight | 2 | 25s | 500 Coins · 30 DNA · 2 Ice |
| cosmic_q | Quantum + Cosmic Energy | Cosmic | 3 | 60s | 6,000 Coins · 150 DNA · 3 Cosmic |
| cosmic_b | Blight + Cosmic Energy | Cosmic | 3 | 60s | 6,000 Coins · 150 DNA · 3 Cosmic |
| supernova_v | Volatile + Cosmic Energy | Supernova | 3 | 75s | 12K Coins · 250 DNA · 5 Cosmic |

### Evolutions

| Id | Species [mutation] + Ingredient | Becomes | Chamber | Base time | Cost |
|---|---|---|---|---|---|
| evo_glacial_golem | Frostling [Frost] + Ice Crystal | Glacial Golem | 2 | 45s | 3,000 Coins · 80 DNA · 6 Ice |
| evo_toxic_hydra | Toxic Slime [Toxic] + Toxic Crystal | Toxic Hydra | 2 | 45s | 3,000 Coins · 80 DNA · 6 Toxic |
| evo_quantum_blob | Basic Blob [Quantum] + Pure DNA | Quantum Blob | 2 | 45s | 2,500 Coins · 60 DNA |
| evo_neon_phantom | Plasma Wisp [Volatile] + Plasma Crystal | Neon Phantom | 3 | 90s | 25K Coins · 300 DNA · 10 Plasma |
| evo_rift_guardian | Ember Beast [Quantum] + Plasma Crystal | Rift Guardian | 3 | 90s | 30K Coins · 350 DNA · 12 Plasma |
| evo_star_eater | Voidling [Cosmic] + Cosmic Energy | Star Eater | 3 | 120s | 60K Coins · 500 DNA · 10 Cosmic |
| evo_celestial_mimic | Quantum Blob [Cosmic] + Cosmic Energy | Celestial Mimic | 4 | 150s | 150K Coins · 1,200 DNA · 20 Cosmic |
| evo_world_eater | Star Eater [Supernova] + Cosmic Energy | World Eater | 4 | 240s | 600K Coins · 3,000 DNA · 40 Cosmic |

### Upgrades

- **Display Pads**: values 3 → 4 → 5 → 6 → 7 → 8 → 9 → 10 → 11 → 12; prices 250, 700, 1,800, 6,000, 15K, 40K, 120K, 300K, 750K
- **Coin Collector**: values 400 → 1,200 → 3,500 → 10K → 30K → 90K → 270K → 800K → 2.5M; prices 300, 1,200, 4,000, 12K, 40K, 120K, 400K, 1.2M
- **Mutation Chamber**: values 1 → 2 → 3 → 4; prices 2,000, 25K, 250K
- **Island Expansion**: values 6 → 9 → 12; prices 6,000, 80K
- **Security System**: values 1 → 2 → 3 → 4; prices 1,500, 10K, 60K
- **Creature Storage**: values 20 → 30 → 40 → 55 → 70; prices 800, 5,000, 25K, 100K

### Biomes

| Biome | Requirements | Crystal | Wild creatures |
|---|---|---|---|
| Frozen Peaks | free | Ice Crystals | Frostling (75), Crystal Mite (25) |
| Toxic Swamp | level 2, 600 coins | Toxic Crystals | Toxic Slime (80), Basic Blob (20) |
| Plasma Rift | level 5, 2 recipes, 6000 coins | Plasma Crystals | Plasma Wisp (70), Ember Beast (30) |
| Cosmic Void | level 9, chamber 3, 60000 coins | Cosmic Energy | Voidling (100) |

## Heists (`Config/Heist.luau`)

- Only creatures **on display pads** that are **Uncommon or rarer** can be stolen. Starters never.
- Island vault doors are locked by default. Visitors must **hold to breach** (5/8/11/14 s by
  security level). The owner is alerted the moment a breach starts.
- Steal: from **inside the vault**, hold F next to a creature, then stay inside and within 16 studs for the channel time
  (8 s + 2 s per security level above 1). One heist per island and per creature at a time.
- Cancelled by: moving away, dying, leaving, teleporting, the owner's shield, the owner's zap trap.
- Success chance after a full channel: 80% − 10% per security level above 1 (minimum 45%).
  Failure stuns the thief 3 s and fines 5% of their coins (max 500, destroyed, not transferred).
- Anti-griefing: new players (< 20 min playtime or first tutorial run unfinished; replaying it later doesn't count) can't be raided;
  newly acquired creatures are protected 10 min; a robbed island is protected 10 min; victims
  must own more than 3 creatures; thief cooldown 60 s (fail) / 180 s (success); same victim
  15 min; no targets more than 15 levels below you.
- Defenses: Shield (60–180 s, recharge 300–180 s), lockable door, intruder alarm (security 2+),
  slime floor slows intruders (security 3+), zap trap (stun 4 s, cancels the heist, 45 s recharge).

## Trading

- Request a player within 30 studs; they accept or decline (requests expire after 20 s).
- Offer up to 6 storage creatures (not on pads, not starters) plus coins and DNA.
- Offered creatures are locked (can't be placed, mutated, released or offered elsewhere).
- Any offer change resets both confirmations; accepting is blocked for 2 s after a change.
- Both accept → 3 s countdown → the server revalidates ownership, balances and storage space,
  then swaps everything atomically. Any failure cancels with nothing moved.
- Traded creatures get the 10-minute new-owner theft protection.
- Leaving, cancelling or 3 minutes of inactivity closes the trade safely.
