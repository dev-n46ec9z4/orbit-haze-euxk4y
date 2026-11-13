# Feature checklist

What each gameplay batch added and how it was checked. "Static" means `luau-compile` syntax check + `luau-lsp analyze` against the Roblox API definitions + `rojo build`. "Unit" means a standalone Luau test in `tests/` (`node tests/run.mjs`). **Nothing in this list has been run in Roblox Studio yet**, so in-game behaviour, feel and tuning are untested.

## Base game (first PR)

Lobby, 10x10 arena, intermission → grace → survive → results loop, red-flash falling waves, kill plane, Alive tags, solo rule, Wins/Coins with DataStore fallback, phase/timer/Alive HUD. See README.

## Batch 1: gameplay expansion

Every special tile, hazard and power-up only acts during the Survive phase; the grace period stays safe. All decisions (tile triggers, hits, pickups, buffs) happen on the server.

| # | Feature | Category | Where | Verification |
| --- | --- | --- | --- | --- |
| 1 | **Ice tile**: near-zero friction, you slide | Tile | `World.styleTile` | Static |
| 2 | **Crumble tile**: starts falling 0.9s after a player stands on it (server raycast under each alive player) | Tile | `TileEffects.tick` | Static |
| 3 | **Reinforced tile**: first wave hit cracks it, second drops it | Tile | `World.dropWave` / `hitByWave` | Static |
| 4 | **Bounce pad**: launches the player upward (short server-created `LinearVelocity`), 0.8s cooldown | Tile | `TileEffects.tick`, `Impulse` | Static |
| 5 | **Conveyor**: pushes players toward its glowing edge once Survive starts | Tile | `World.activateTiles` | Static |
| 6 | **Meteor**: 1–3 red impact circles, meteor falls for 1.5s, smashes the tile + neighbours and knocks nearby players back | Hazard | `Hazards.runMeteor` | Static |
| 7 | **Sweeper**: low beam fades in, then spins for 8s; players who don't jump it get knocked away | Hazard | `Hazards.runSweeper` | Static; hit maths unit-tested (`Grid.beamDistance`) |
| 8 | **Row Collapse**: a random row or column flashes for 1.4s, then drops | Hazard | `Hazards.runRowCollapse` | Static |
| 9 | **Speed Boost** pickup: +50% WalkSpeed for 6s | Power-up | `PowerUps` | Static |
| 10 | **Super Jump** pickup: 1.8x JumpHeight (and matching JumpPower) for 6s | Power-up | `PowerUps` | Static |
| 11 | **Rescue Wing** pickup: one save; falling 10 studs below the arena puts you back on an intact tile | Power-up | `PowerUps.tryRescue` | Static |
| 12 | **Mode rotation**: Classic → Shrinking Ring → Hazard Storm; each mode sets wave pattern/size, hazard list and frequency, power-up frequency. Classic keeps the original 3–5 tile waves | Mode | `Config.Modes`, `GameLoop` | Static; config/catalog consistency unit-tested |
| 13 | **Shrinking Ring** mode: waves always take the outermost remaining ring first | Mode | `Grid.pickOuterFirst` | Static; ordering unit-tested |
| 14 | **Hazard Storm** mode: 2–3 tile waves, a hazard every 6s | Mode | `Config.Modes.HazardStorm` | Static; config unit-tested |
| 15 | **Guide panel** (G key or GUIDE button): goal, modes, tiles, hazards, power-ups with colour swatches, generated from `Shared.Catalog` | HUD | `Hud.client.luau` | Static; catalog completeness unit-tested |
| 16 | **Event toasts** under the banner: mode intro, hazard warnings, pickups, rescues, welcome hint | HUD | `Hud.client.luau`, `GameEvent` remote | Static |
| 17 | **Power-up tray** under the stats card with live countdowns | HUD | `Hud.client.luau` | Static |
| 18 | **Mode line** on the phase banner (`NEXT MODE:` during intermission, `MODE:` in round) | HUD | `Hud.client.luau` | Static |

Count: 14 gameplay features (5 tiles, 3 hazards, 3 power-ups, mode rotation + 2 new modes) and 4 HUD features that make them discoverable.

Supporting changes (not counted): weighted random tile mix per arena (`Config.TILE_TYPE_WEIGHTS`), spawning prefers Normal tiles, `GameEvent` remote (server → client only; client messages are ignored), pure arena maths in `Shared/Grid.luau`.

### Batch 1 risks to check in Studio

- **Impulses** (bounce, sweeper, meteor knockback) use a short `LinearVelocity` constraint created by the server on a client-owned character. This is a common pattern, but strength and feel are untuned.
- **Sweeper hit window** assumes the root part sits about 3 studs above the floor (standard R15/R6 rigs). Custom rigs may need `SWEEPER_HIT_HEIGHT` adjusted.
- **Crumble and pickup detection** run on the server at about 10 Hz, so high-latency players may see them trigger slightly late.
- **Conveyors** rely on anchored parts with `AssemblyLinearVelocity` carrying characters.

## Batch 2: maps, environments and round modifiers

Each round now has a **round plan**: the mode (still rotating), plus a map, environment and modifier. The server picks these, avoiding last round's choice, and shows them in the HUD from the start of intermission. The first round after the server starts is always Classic / Square / Clear Sky / No Modifier, which is the original game. Gusts, lava and regrowth only run during Survive. In the grace countdown you get the new layout, lighting and gravity, but nothing moves you or knocks out tiles.

| # | Feature | Category | Where | Verification |
| --- | --- | --- | --- | --- |
| 19 | **Donut** map: the centre 4x4 is a hole (84 tiles) | Map | `Grid.layoutCell` | Static; tile count + hole unit-tested |
| 20 | **Cross** map: two 4-wide bridges, no corners (64 tiles) | Map | `Grid.layoutCell` | Static; shape unit-tested |
| 21 | **Islands** map: nine islands split by one-tile channels (8-stud jumps, 64 tiles) | Map | `Grid.layoutCell` | Static; channel width unit-tested |
| 22 | **Pyramid** map: each inner ring 1.5 studs higher (6-stud peak). Meteors and pickups use each tile's own height; Sweeper is blocked here | Map | `Grid.layoutCell`, `Config.Maps.Pyramid` | Static; heights unit-tested |
| 23 | **Low Gravity** environment: 45% gravity and a night sky. Longer jumps, slower falls | Environment | `Environment.apply` | Static; settings unit-tested |
| 24 | **Blizzard** environment: fog, plus a white wind front that sweeps across every 8s, then a horizontal gust push on every alive player | Environment | `Environment.runGust`, `Impulse.push` | Static |
| 25 | **Volcano** environment: lava rises from Y=-20 to 6 studs under the tiles over the round, and its surface becomes the kill height | Environment | `Environment.runLava`, `GameLoop` Heartbeat | Static; lava/rescue height margins unit-tested |
| 26 | **Overdrive** modifier: waves 35% faster, +10 bonus Coins for survivors | Modifier | `Config.Modifiers`, `GameLoop` | Static; config unit-tested |
| 27 | **Power Surge** modifier: power-ups twice as often, up to 4 on the arena | Modifier | `PowerUps.startRound` | Static; config unit-tested |
| 28 | **Regrowth** modifier: every 4s a fallen tile grows back into an empty slot of the current layout, away from players. It's ghosted and non-solid for 1.2s, and only turns solid once nobody is inside it | Modifier | `World.regrowTile` | Static |
| 29 | **Ice Age** modifier: every Normal tile is Ice (regrown tiles too), +5 bonus Coins | Modifier | `World.buildArena` | Static |
| 30 | **Round plan**: mode rotation plus a no-repeat random map, environment and modifier; an original-game first round; the plan is kept across aborted intermissions; lighting and gravity are restored after every round, including error cleanup | System | `GameLoop.getNextPlan`, `Environment.clear` | Static; no-repeat picker + first-round defaults unit-tested |
| 31 | **Round info line** on the phase banner: map, environment, modifier | HUD | `Hud.client.luau` | Static |
| 32 | **Round preview card** (left side) during intermission (NEXT ROUND) and grace (THIS ROUND): all four choices with descriptions; plus intro toasts for environment and modifier when Survive starts, and a bonus-Coins toast at results | HUD | `Hud.client.luau`, `GameLoop.introToast` | Static |
| 33 | **Guide sections** for Maps, Environments and Round Modifiers | HUD | `Hud.client.luau`, `Catalog` | Static; catalog completeness unit-tested |

Count for this batch: 15 features (4 maps, 3 environments, 4 modifiers, the round plan system, 3 HUD). The baseline Square / Clear Sky / No Modifier options aren't counted. Cumulative: **33** (18 + 15).

How the new pieces interact with earlier features:
- **Spawn safety:** spawns prefer Normal tiles, then calm tiles (Normal, Ice, Reinforced), then any tile. Ice Age has no Normal tiles, so players spawn on Ice or Reinforced tiles, never on bounce pads, conveyors or crumble tiles unless the map has nothing else.
- **Wave size** scales with the map's tile count (`Grid.scaleWave`). For example, 3–5 tiles on Square becomes 2–3 on Cross and Islands, so smaller maps don't empty faster. Shrinking Ring still goes outside-in on every layout. On the Donut, the ring next to the hole is the last one left.
- **Hazards:**
  - Maps can block a hazard. Pyramid blocks the Sweeper, because its low beam needs a flat floor.
  - A test checks that every mode still has at least one hazard on every map.
  - Meteors aim at each tile's own height.
  - Row Collapse and Meteor ignore empty layout slots and ghost tiles that are still regrowing.
- **Rescue Wing** now triggers at whichever is higher: 10 studs below the arena, or 3 studs above the lava. A unit test checks that the highest lava level still leaves a rescue window below the tile bottoms.
- **Regrowth** only fills slots that belong to the current layout. A tile that's still falling keeps its slot until it's destroyed. A regrowing tile can't be picked by waves, hazards, crumble or pickups until it's solid.

### Batch 2 risks to check in Studio

- **Gravity** (`Workspace.Gravity`) is global, so lobby players also float during Low Gravity rounds until the round ends.
- **Lighting** is global too, so the lobby gets the round's look during the round. Both are restored in `cleanupRound`.
- **Low Gravity jumps:** with `JumpHeight` humanoids, jump height stays the same and only airtime grows (about 1.5x horizontal distance). With `JumpPower` humanoids, jumps also get higher. I haven't checked which one the built place uses.
- **Gusts** add to the player's current horizontal velocity for 0.4s through a planar `LinearVelocity`. The strength (28 studs/s) is untuned.
- **Islands gaps** are 8 studs. A default running jump should clear them, but that hasn't been checked in-game.
- **Pyramid steps** are 1.5 studs high, so players have to jump up each ring.

## Batch 3: progression

All progress comes from real rounds, and the server computes it. The client only displays the "Progress" attribute and toasts. The rules live in the pure module `Shared/Progression.luau`, which the server, the HUD and the tests all share.

| # | Feature | Category | Where | Verification |
| --- | --- | --- | --- | --- |
| 34 | **XP and levels**: XP for playing, every 10s survived, winning, power-ups and rescues, with a per-round breakdown. Each level needs 25 more XP than the last (100 for level 2), max level 50. `Level` is shown in leaderstats | Progression | `Progression.roundXp`, `levelInfo` | Static; level curve, cap and round XP unit-tested |
| 35 | **Level-up rewards**: 10 Coins x the new level, +50 every 5th level, paid automatically | Reward | `Progression.levelReward` | Static; unit-tested |
| 36 | **Win streak bonus**: +10 XP per consecutive win beyond the first (max +40); a loss resets it, and the best streak is kept | Progression | `Progression.recordRound` | Static; unit-tested |
| 37 | **Daily quests**: 3 of 8 quest templates per UTC day, chosen deterministically per player (the same on every server), progressed by round results and paid automatically when done | Quest | `Progression.questsFor`, `refreshQuests` | Static; determinism, rollover, completion and no-repeat unit-tested |
| 38 | **Achievements**: 12 one-time goals with Coin rewards (wins, rounds, time survived, power-ups, bounces, rescues, full rounds, best streak, win on every map, win in every environment, level 10) | Achievement | `Progression.checkAchievements` | Static; unlocks, no double grant, World Tour unit-tested |
| 39 | **Daily login streak**: Coins on the first session of each UTC day, rising over 7 days and reset by a missed day | Reward | `Progression.checkIn` | Static; same-day protection, growth, cap, reset unit-tested |
| 40 | **Lifetime stats**: rounds played, time survived, best round, power-ups, bounces, rescues, full rounds, wins per map and per environment | Progression | `Progression.recordRound`, `RoundStats` | Static; unit-tested |
| 41 | **Level + XP bar** on the stats card | HUD | `Hud.client.luau` | Static |
| 42 | **Progress panel** (P key or PROGRESS button): level and next reward, streaks, daily quests with bars, rewards and a reset countdown, achievements with progress, lifetime stats. Opening it closes the guide and vice versa | HUD | `Hud.client.luau` | Static |
| 43 | **Progress toasts**: round XP breakdown, level-up, quest complete, achievement unlocked, daily streak | HUD | `PlayerData.announce` | Static |
| 44 | **Guide PROGRESSION section** explaining XP sources (numbers from Config), win streaks, quests, achievements and the daily streak | HUD | `Hud.client.luau` | Static |

Count for this batch: 11 features (7 progression/reward systems, 4 HUD). Quests and achievements each count as one feature even though they have 8 and 12 entries. Cumulative: **44** (33 + 11).

Persistence and safety changes (supporting, not counted):
- **Schema v2** with migration (`Progression.migrate`):
  - It uses the same DataStore name and key as before, so existing Wins and Coins carry over.
  - v1 `{Wins, Coins}` data gets defaults for everything new.
  - Invalid numbers become 0, and unknown achievement and quest ids are dropped.
  - Data written by a newer schema is flagged, and that session is never saved.
  - Achievements already met by migrated data unlock on load. For example, a v1 player with wins gets First Victory.
- **Saves use `UpdateAsync`**, and the update function refuses to replace newer-schema data. Every DataStore call is still inside `pcall`.
- **A failed load means no saves** for that session, as before, and also no login reward, because it could never be saved and rejoining would grant it again.
  - In Studio, or when DataStores are unavailable, profiles are session-only and the login reward is granted every session.
- **Round results that arrive while the profile is loading are queued** and applied after the load. The old code added session stats on top of loaded data, which could have given rewards twice; that is replaced.
- **Each round result is applied at most once:**
  - `RoundStats.finalize` only returns one summary per player per round.
  - `PlayerData` tracks the round ids it has applied this session.
  - The profile stores `LastRoundId`, and `recordRound` rejects a repeat of it.
- **Leaving mid-round forfeits that round's progress.** Elimination finalizes the round as a loss, and survivors finalize it as a win. The previous Wins/Coins award is folded into the same single profile update.

### Batch 3 risks to check in Studio

- **Quick deaths still earn XP:** eliminations during the 3s countdown still give participation XP, so a solo player who keeps dying instantly still earns about 10 XP per cycle. This is intentional so solo play progresses, but it could be farmed slowly.
- **Daily resets use the server clock:** the UTC day comes from `os.time()` on the server, and the HUD countdown uses the client's clock, so they can disagree by however much the clocks differ.
- **Saves:** there's one `UpdateAsync` per player per round (roughly one every 75s), plus on leave and shutdown. That's inside normal DataStore limits, but rejoining quickly between servers has no session lock, so the last write wins.
- **HUD size:** the progress panel rebuilds its rows on every update. That's fine at this size (about 30 rows).
