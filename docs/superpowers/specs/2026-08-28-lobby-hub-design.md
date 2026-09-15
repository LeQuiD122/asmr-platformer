# Lobby hub with preset levels

Design spec, 2026-08-28. Covers sub-project **A** only. B, C and D are scoped at the bottom
and are explicitly not designed here.

## What this is

A room players spawn into, containing one pad per shippable level. Standing on a pad selects
that level; a start pad builds it and teleports everyone in. Finishing or leaving returns you
to the room. A statue shows your personal best; a board shows the leaderboard.

The room replaces the current arrangement, where `Bootstrap` holds a hardcoded
`CURRENT_LEVEL = LevelDefinitions.Sandbox` and builds it once at server start.

## Why pads and not a menu

Every choice in this game is made by touching something, and the pads are made of the
material they represent, using its real deformation. You feel what a level is made of before
you commit to it. It also reuses the chunk system wholesale rather than introducing a second
way to present the same information.

## Decisions taken

| Question | Decision |
|---|---|
| What is selected | A preset level, from `LevelDefinitions.All` |
| How | One pad per level, built from that level's headline material, with a sign |
| Room contents | Level pads, start pad, mode pad, run-length pad, statue, leaderboard board |
| Default pad | Belongs with B. It resets the material selection to all-on, and spec A has no material selection to reset — in A it would be a pad that does nothing |
| Lifecycle | Hub is permanent; runs are built and torn down around it |
| Death | Unchanged. Hardcore resets to level start, chill to 3 tiles behind the checkpoint |
| Leaving a run | Explicit only, via the settings icon's "leave level" button |
| Finishing | Existing time panel, then back to the hub |
| Chill leaderboard | Its own store, separate from hardcore. Off by default in chill, player-toggleable |
| Advancements | Deferred to their own spec. The statue leaves room for them |

## The Sandbox keeps a pad

`LevelDefinitions.All` holds `Level1`, `Level2` and `Level3`. The Sandbox is not in it, and
it is also the only way to walk every material in one run — it is the tool this whole
project has been inspected with.

So the hub builds a pad for each level in `All`, plus one for the Sandbox, marked as a
development route rather than presented as a fourth level. Removing it would mean rebuilding
a sandbox by hand out of the custom area every time something needs looking at, and the
custom area does not exist yet.

## Architecture

Four pieces, three of them edits to things that exist.

### `HubService` — new, `ServerScriptService/Services`

Builds the room once at server start and owns the pads, the selection, and the run lifecycle.
It knows nothing about how a level is built beyond calling `LevelService`.

Its single outward seam is:

```
HubService.beginRun(request: RunRequest)
```

`RunRequest` is **pure data** — no Instance references, no functions:

```
type RunRequest = {
    levelId: number,
    mode: "chill" | "hardcore",
    length: "short" | "medium" | "long",
}
```

That constraint exists for sub-project C. When multiple servers land, `beginRun` stops
building locally and hands this table to `TeleportService:TeleportToPrivateServer` as teleport
data instead. If the selection held Instances it could not cross a teleport, and C would
require rewriting the hub rather than extending it.

`length` maps onto the `minChunks` / `maxChunks` that `LevelService` already reads, scaling
each level's authored count rather than replacing it: short is roughly half, medium is the
level as authored, long is roughly half again. A level's identity is its material mix, and
that does not change with how long you walk it.

### `LevelService` — two changes

**`startLevel(level, players, origin)` takes an origin.** Today `SPIRAL_RADIUS = 90` is
centred on the world origin and `startPosition` is the fixed coordinate
`(SPIRAL_RADIUS, BASE_SURFACE_Y + 4, 8)`. Both become relative to a passed-in origin,
defaulting to the current value so no existing behaviour changes.

This is a small edit now and an awkward one later. It is what lets the hub and a run coexist
in world space, and it is also the in-server half of C.

**`endLevel(instance)` is new.** It destroys `workspace.Levels` and clears the run's
`SpawnLocation`. Without it, starting a second run stacks a second spiral on the first —
`startLevel` currently clears only the baseplate. It must be safe to call twice.

### `Bootstrap` — stops choosing

`CURRENT_LEVEL` is removed. Bootstrap builds the hub, wires `HubService` to `LevelService`,
and moves its `finishPart` / `LevelCompleted` wiring from once-at-startup to once-per-run.

### Personal best store — new, small

One persistent DataStore key per player per level, written on completion in **both** modes,
read by the statue.

Separate from `LeaderboardService` on purpose. That store is an `OrderedDataStore` scoped to
the active season and archived at rollover, so a best time read from it disappears when the
season turns. A statue that forgets your best time every season is worse than no statue.

## Data flow

1. Server start: Bootstrap builds the hub. No level exists.
2. Players spawn in the hub, which owns its own `SpawnLocation`. The level's spawn exists only
   while a run does.
3. Stepping on a level pad sets the server's selection and lights that pad. The mode and
   length pads set their own fields on the same `RunRequest`.
4. The start pad calls `HubService.beginRun`, which calls
   `LevelService.startLevel(level, playersInHub, LEVEL_ORIGIN)`, rebuilds the backdrop, and
   teleports everyone in.
5. The run is unchanged: deformation, timer, mode, checkpoints and per-mode death all behave
   exactly as they do today.
6. Finishing hits the existing `finishPart`, fires `LevelCompleted` with the time, shows the
   existing panel, then returns the player to the hub. `endLevel` fires when the last player
   leaves.
7. "Leave level" in the settings menu takes the same return path.

### The limitation, stated plainly

**One level exists per server.** The selection is therefore server-wide: the last level pad
pressed wins, and the start pad launches it for everyone in the hub.

This matches the intent for presets — solo players share an instance and can see each other —
but two players cannot be on different levels until C lands. Spec A does not work around this;
it documents it.

## Chill leaderboard

`LeaderboardService` is hardcore-only by construction. Chill times are never submitted.

`submitTime` gains a mode argument and writes to a per-mode store, so chill has its own real
ranking. A chill time and a hardcore time are not comparable — hardcore resets you to the
level start on every fall — so ranking them together would be meaningless.

The chill board defaults to off and is toggled in the settings menu. Hardcore's is always on.

## Failure behaviour

The codebase already has the right instinct: `LightingService.apply` and `BackdropService.build`
are each wrapped in `pcall` in `Bootstrap`, specifically so a cosmetic failure cannot stop a
level from generating. It has happened once.

The same rule applies here:

- A failed `startLevel` leaves players standing in the hub, not nowhere.
- `endLevel` is safe to call twice, and safe to call when no level exists.
- The statue and leaderboard board are cosmetic and are `pcall`ed. A DataStore failure must
  not stop the room being built or a run being started.
- If `LevelDefinitions.All` is empty the hub builds with no level pads and says so, rather
  than erroring.

## Testing

Nothing here can be tested outside Studio, so the checkers cover what is static and the rest
is a manual list.

**Static, added to the Python checkers:**

- Every level in `LevelDefinitions.All` has a pad, and every pad names a level that exists.
- Each pad's headline material exists in `MaterialConfig` and `MaterialAppearance`.
- `RunRequest` carries no Instance-typed fields — the constraint C depends on.

**Manual, in Studio:**

1. Server starts into the hub with no level in `workspace`.
2. Each level pad selects and lights; the last press wins.
3. Start builds the level and teleports; the backdrop rebuilds around it.
4. Chill death returns you near the same chunk. Hardcore death returns you to the level start.
5. Finishing shows the time panel, then returns to the hub, and `workspace.Levels` is gone.
6. Starting a second run does not stack a second spiral.
7. Leaving mid-run via the settings icon returns you to the hub and tears the run down.
8. The statue shows your best time and survives a rejoin.

## Not in this spec

- **B — custom area.** The 23 material pads and a custom run. Reuses this spec's pad mechanic
  and `RunRequest`, with a material list added to it.
- **C — multiple servers.** Teleporting a `RunRequest` to a reserved server so different
  players and parties can be on different levels at once. The origin parameter and the
  pure-data `RunRequest` are the two hooks it needs, and both are in spec A.
- **D — parties.** Invite a friend, customise together, play together. Depends entirely on C.
- **Advancements.** A progression system: what earns one, how many, storage, display.
- **Fall-out hint and the backrooms unlock.** Falling out of bounds repeatedly near the same
  chunk unlocks a secret level, with a dismissible hint.
- **Per-level backdrops**, including an unusual one specific to the backrooms level.
