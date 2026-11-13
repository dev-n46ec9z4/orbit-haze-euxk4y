# Falling Tiles Survival

A Roblox multiplayer survival game: players wait in a sky lobby, get teleported onto a 10x10 tile arena, and try to outlast tiles that flash red and fall away in accelerating waves.

All Workspace geometry (lobby, spawn, barriers, neon trim, arena tiles) is created at runtime by `src/Server/World.luau` — no external assets, mesh IDs, or hand-written XML.

## Build

```sh
rojo build -o FallingTilesGame.rbxl   # Rojo 7.x
node scripts/validate.mjs             # JSON + require-path checks
node tests/run.mjs                    # standalone Luau tests (needs `luau` on PATH, or LUAU=/path/to/luau)
```

`default.project.json` maps:

| Instance | Source |
| --- | --- |
| `ReplicatedStorage.Shared` | `src/Shared` (Config, Catalog, Grid, Progression, Net, Format) |
| `ServerScriptService.Server` | `src/Server` (GameLoop, World, Environment, TileEffects, Hazards, PowerUps, Impulse, RoundStats, PlayerData) |
| `StarterPlayer.StarterPlayerScripts.Client` | `src/Client` (Hud) |

## Round flow

1. **Waiting** until at least `MIN_PLAYERS` (1) are in the server.
2. **Intermission** — 10s countdown (`INTERMISSION: 10s`).
3. **Grace** — alive players are tagged `Alive` (CollectionService tag + `Alive` attribute), teleported onto random tiles, and get 3s before anything falls (`GET READY: 3`).
4. **Survive** — every wave drops 3–5 random intact tiles; the wave interval eases from 1.2s to 0.5s across the 60s round. Tiles flash red for 0.6s, unanchor, and are destroyed 2s later (`SURVIVE!`).
5. **Results** — survivors get +1 Win and +25 Coins, the winner is announced (`WINNER: <Name>`), survivors return to the lobby, the arena is destroyed and the loop repeats.

Falling below Y = -20 (the kill plane, or the lava surface in Volcano rounds), dying, resetting, or leaving eliminates a player. Eliminated players respawn in the lobby after 3s. Late joiners spawn in the lobby and their HUD requests the current state on load.

## Modes, tiles, hazards and power-ups

Modes rotate each round: **Classic** (random waves, occasional hazards), **Shrinking Ring** (tiles fall from the edge inward) and **Hazard Storm** (smaller waves, a hazard every 6s). Each arena mixes in special tiles: Ice, Crumble, Reinforced, Bounce Pad and Conveyor. The hazards are Meteor, Sweeper and Row Collapse. Glowing orbs give Speed Boost, Super Jump or Rescue Wing. All of these are active only during Survive.

Each round also has a random **map** (Square, Donut, Cross, Islands, Pyramid), **environment** (Clear Sky; Low Gravity; Blizzard with wind gusts; Volcano with rising lava) and **modifier** (none, Overdrive, Power Surge, Regrowth, Ice Age). None of the three repeats from the previous round. The first round after a server starts is always Classic on Square with Clear Sky and no modifier. The HUD shows the plan on the banner and on a preview card during intermission and grace.

In game, press **G** or click **GUIDE** for descriptions of everything. Names and descriptions live in `src/Shared/Catalog.luau`, and tuning lives in `src/Shared/Config.luau`. See [FEATURES.md](FEATURES.md) for the numbered checklist and how each feature was verified.

### Last-survivor rule and solo testing

- Rounds that **start with 2+ players** end when 0 or 1 players remain, or at 60s.
- Rounds that **start with 1 player** (e.g. solo Play in Studio) do *not* end just because one player is alive. They end when that player is eliminated or when the 60s timer runs out; surviving the full minute counts as a win.

## Data and progression

Wins, Coins and Level show in `leaderstats`. They mirror a server-side profile that also holds XP, lifetime stats, daily quests, achievements and streaks (`src/Shared/Progression.luau`). Press **P** in game for the progress panel. [FEATURES.md](FEATURES.md) lists the rules and rewards.

Persistence still uses the `FallingTilesStats_v1` DataStore with the same key, so v1 `{Wins, Coins}` data migrates to schema v2 when it's loaded.
- Every DataStore call is wrapped in `pcall`.
- If DataStores are unavailable (e.g. Studio without API access), profiles stay session-only.
- A player whose load failed is never saved, so stored data isn't overwritten.
- Saves use `UpdateAsync` and never replace data from a newer schema.
- Round results that arrive while a profile is loading are queued until it loads, and each round is applied at most once.
