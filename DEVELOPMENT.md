# ASMR Platformer

A Roblox 3D platformer built from a locked GDD, where every platform is a tactile
ASMR material: honey, butter-wax, kinetic sand, slime, soap, bubble wrap, creamy
keyboard, cracking ice, soda jello, lamb's ear, memory foam, light switches, lego,
charcoal, chocolate, clay, cloud, rock salt, lava and obsidian, non-Newtonian fluid,
arcade buttons and melting snow.
Template-based procedural level generation, per-sub-region deformation shared between
server and client, chill/hardcore modes, a timer and an OrderedDataStore leaderboard.

Nothing here syncs to Studio. Luau is pasted in by hand and meshes are imported by hand.
The 18 chunk Models are not assets at all: they are built procedurally at runtime by
`Server/ChunkBuilder.server.lua`, because Studio geometry cannot be authored as text.

**`HANDOFF.md` is the document to read before changing anything.** This file covers
installing and running. That one covers the current state of each material, the mesh
pipeline, and the reasoning behind decisions that look arbitrary.

## Material forms

A platform's SHAPE is separate from its material: soap comes as a plain bar, a heart, a
star and a scatter of pebbles, kinetic sand comes plain or as a sculpted turtle, bubble
wrap comes standard or giant. All of it is driven by one word in `ChunkBuilder`'s
segment table:

```lua
R6_SoapHeart = {
    { name = "Platform", material = "Soap", width = 18, length = 22, form = "heart" },
},
```

**What that word costs depends entirely on the material, and the gap is large.**

*Granular materials — soap only.* The platform IS a field of cubes, so its outline is
just the cube-placement test. A new shape is a function in `Shared/PlanShapes.lua` and
nothing else: no mesh, no import, no size lock. This is why soap has four shapes and
everything else has at most two.

*Skinned materials — everything except soap.* The platform is one
rigged mesh whose bones are matched to sub-region cells by position, so its shape is
baked into an FBX at import time. A form here means a new mesh, a new generator recipe
and a manual import. It also means the platform must be a SINGLE untapered slab: a taper
is sliced into 4-stud pieces, and a turtle sawn into three strips is not a turtle.

`skinnedSpecFor` matches the slab's `Form` attribute first and falls back to the plain
mesh, so a form named in a chunk but never generated degrades to an ordinary platform
with a warning rather than to no mesh at all.

### Adding a variant: the whole pipeline, or none of it

A form variant is not finished when its mesh exports. Half a variant costs a play session
to discover, and this project has shipped meshes with no PBR and chunks that were never
registered for building. The full list, in order:

1. **Generate** the mesh. The generator validates its own output and prints the
   `SKINNED_PLATFORMS` line to paste - do not measure an offset by eye.
2. **PBR maps at the variant's own scale** (`blender/gen_pbr.py`), if the material has
   them. Reusing the base material's maps is wrong whenever the feature size changed: the
   giant sheet's pockets are twice the width at twice the pitch, so the standard maps
   would print a crease every 2 studs across geometry whose features are 4 apart.
   A SurfaceAppearance is per MESH, so the variant simply gets its own.
3. **Register it**: `ChunkBuilder` segment table and `SKINNED_PLATFORMS`,
   `ChunkDefinitions` (`AllIds` derives itself from the definitions), the level's
   sequence in `LevelDefinitions`, and `CHUNK_ORDER` in `blender/chunk_layout.py`.
4. **Run the checks**: `check_chunk_forms.py`, `check_lua.py`, and `check_form_slopes.py`
   for anything sculpted.
5. **Render it and look at it** with `render_forms.py`, before anyone imports anything.

### The sand turtle is sculpted, not cut out

Worth knowing before adding another one, because the obvious approach is wrong. A soap
heart's outline is also its floor. A skinned platform is decoration over a rectangular
slab — `CanCollide` is false on every mesh — so cutting a turtle silhouette out of the
plan would leave the player walking on thin air in the bays between the flippers. The
turtle lives entirely in the height field and the slab stays a full rectangle underfoot.

Three constraints govern any further sculpting, and each was got wrong once first:

- **The slab rim is the highest ground.** `edge_fade` pulls every face's relief to zero
  at the border so the six faces meet. Put the bed below that and the border becomes a
  lip taller than the sculpture, which reads as a basin. The bed is a bowl instead.
- **Slope budgets add up.** A smoothstep profile of rise `h` over half-width `w` peaks at
  `1.5 * h / w`, and past ~45 degrees the surface stair-steps at the sample step. The
  shell flank, the outline groove and the clumping each looked affordable and summed to
  55. Run `check_form_slopes.py`, which measures the total.
- **A feature must be several samples wide**, and on a curved band the width that counts
  is arc length. Radial scute grooves came out 0.4 studs against a 0.26-stud step and
  tore; that is why the shell has concentric rings and no spokes.

The tearing that survived all of the above was none of them: a **quad whose corners are
not coplanar** gets split downstream, and along a ridge running diagonally to the grid
consecutive quads fold opposite ways. Sculpted sheets now pick the flatter diagonal
themselves, which costs nothing since a quad was always going to be two triangles.

## Studio placement

| This repo path | Studio destination |
|---|---|
| `src/Shared/*.lua` | `ReplicatedStorage/Shared/` (6 ModuleScripts) |
| `src/Server/ChunkBuilder.server.lua` | `ServerScriptService/ChunkBuilder` (Script) |
| `src/Server/Bootstrap.server.lua` | `ServerScriptService/Bootstrap` (Script) |
| `src/Server/Services/*.lua` | `ServerScriptService/Services/` (ModuleScripts) |
| `src/Client/Bootstrap.client.lua` | `StarterPlayerScripts/Bootstrap` (LocalScript) |
| `src/Client/Services/*.lua` | `StarterPlayerScripts/Services/` (ModuleScripts) |
| `meshes/*.fbx`, `meshes/*.obj` | `ReplicatedStorage/Assets/TileMeshes/` |

**Line 2 of every source file states its intended destination.** Check it after pasting.
A file landing in the wrong object fails silently: a Script containing a module body
runs, returns a table, prints nothing and errors nothing.

RemoteEvents, RemoteFunctions, `ReplicatedStorage/Assets/Chunks` and
`ServerStorage/ChunkTemplates` are all created at runtime. Nothing to pre-wire by hand.

## Meshes

Import the FBX rigs with their Bone children intact, and delete the Workspace copy each
import leaves behind, since imported MeshParts arrive unanchored with collision on and
will rain onto spawn. An OBJ carries no armature, so a rig imported as OBJ comes in
rigid and silently never deforms. `ChunkBuilder` checks `HasSkinnedMesh` and warns.

`HANDOFF.md` carries the exact name list. Names must match exactly and are
case-sensitive.

## One manual property

`Lighting` needs its high-fidelity engine (older Studio called this
`Technology = Future`). No script can read or write that property, so it cannot be set
or checked in code. Verify by eye: honey and slime should carry a specular streak that
moves with the camera. Without it, `EnvironmentSpecularScale`, `EnvironmentDiffuseScale`
and `ShadowSoftness` do nothing.

## Run order

1. Paste `Shared/*.lua` into `ReplicatedStorage/Shared`.
2. Import the meshes into `ReplicatedStorage/Assets/TileMeshes`.
3. Paste `ChunkBuilder.server.lua` into `ServerScriptService`.
4. Paste the remaining `Server/` and `Client/` files. `Bootstrap.server.lua` requires
   `Services/` as a sibling folder, so keep those as ModuleScripts alongside it.
5. Play.

**After any `ChunkBuilder` change, delete the children of
`ServerStorage/ChunkTemplates` and `ReplicatedStorage/Assets/Chunks` before playing
again.** `ChunkBuilder` skips chunks that already exist, so without this you see the old
geometry and conclude the change did nothing.

`Bootstrap.server.lua` loads `LevelDefinitions.Sandbox` by default, a dev level running
every material in a fixed order. Set `CURRENT_LEVEL` to `LevelDefinitions.Level1` for
the real one.

## Before you paste

```bash
python blender/check_chunk_forms.py
```

Plain Python, no Blender needed. It asserts the chunk layout contract: entry and exit
faces wide enough to land on, no hole in a route bigger than a jump clears, slabs that
meet sharing enough width to walk across, no interpenetration, geometry inside each
chunk's published length, the ramp meeting flat chunks flush, and that every slab of a
rigged material has a rig its size. That last one matters most, because a missing rig
falls back to per-tile meshes in complete silence.

Mesh generators live beside it and each validates its own output before exporting, then
prints the `ChunkBuilder` entry it needs. Paste that entry rather than measuring an
offset by eye.

Two more, for the sculpted forms, which need Blender:

```bash
"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe" --background --python blender/check_form_slopes.py
```

Reports how much of a sculpted surface is steeper than 45 degrees and where. A render
tells you where a surface breaks; it does not tell you which feature did it, and the
turtle went through four rounds of fixing real problems that were not the problem.

```bash
"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe" --background --python blender/render_forms.py
```

Top-down and 3/4 renders of every shaped variant. The forms are the first meshes here
whose whole purpose is to be RECOGNISED, and no triangle count or passing validator
tells you whether a lump is a turtle.

## Known simplifications

- **M1 vs M2 slot distinction.** The generator treats both as "any whitelisted pace
  chunk" rather than tracking which pace material belongs in which named slot. The GDD
  randomises chunk choice within a slot and adjacency rules 1 to 7 are verified at the
  category level, so validity holds. Strict M1 different from M2 would be an added
  constraint, not an implied one.
- **Soap is permanent once dissolved.** The GDD gives a dissolve time but no grow-back
  path, so exhausted soap stays gone for that attempt. Cells that never reach exhausted
  do decay back.
- **Character-wide friction override.** Applied through `CustomPhysicalProperties` on
  every BasePart of the character. Standard Roblox practice, but the elasticity and
  weight arguments are worth tuning by feel.
- **Fail detection is a kill plane.** The GDD does not say how a missed jump is
  detected. `LevelService` puts it 40 studs below the lowest walkable surface in the
  level rather than at a fixed height, so a descending elevation profile cannot sink
  past it.

## The one real gap

**The repo ships no sound ids.** Every id in `AudioService.SOUND_ID_BY_EVENT` is an
empty string, so a fresh paste triggers all six materials silently. The wiring itself is
finished — per-material events, per-part throttling, volume control — and it needs
uploaded asset ids and nothing else. If you have filled these in inside Studio, that
edit lives only there; paste them back into this file or the next paste of
`AudioService.lua` will silence the game again.

Do not use `rbxassetid://0` as a placeholder. It is a real request for an asset that
does not exist, so Roblox retries it and logs a failure on every single trigger. An
empty string is skipped silently, which is why they are empty.
