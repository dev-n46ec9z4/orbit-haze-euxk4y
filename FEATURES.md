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

### Known risks to check in Studio

- **Impulses** (bounce, sweeper, meteor knockback) use a short `LinearVelocity` constraint created by the server on a client-owned character. This is a common pattern, but strength and feel are untuned.
- **Sweeper hit window** assumes the root part sits about 3 studs above the floor (standard R15/R6 rigs). Custom rigs may need `SWEEPER_HIT_HEIGHT` adjusted.
- **Crumble and pickup detection** run on the server at about 10 Hz, so high-latency players may see them trigger slightly late.
- **Conveyors** rely on anchored parts with `AssemblyLinearVelocity` carrying characters.
