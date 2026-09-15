# ASMR Platformer: handoff

Roblox game from a locked GDD: a 3D platformer where every platform is a tactile,
ASMR-inspired material (honey, butter-wax, kinetic sand, slime, soap, bubble wrap), with
template-based procedural level generation, chill/hardcore modes and a leaderboard.

It has grown well past those six. `MaterialConfig` now carries 26 material entries across 65
chunks, there are four levels plus a Sandbox, and players choose a run in a lobby rather than
being dropped into a hardcoded level. See **Levels and the lobby** and **The Flooded Halls**
below for the parts this file did not cover before.

Last updated: 2026-09-14. What is planned next (the City Shore finale, story mode, the levels
still to come) is in `ROADMAP.md`.

## Where things are

| Path | What |
|---|---|
| `RobloxProject/src/` | All Luau source. Pasted by hand into Studio; nothing is synced. |
| `RobloxProject/blender/` | Python generators for meshes, plus render scripts. |
| `RobloxProject/meshes/` | Exported OBJ/FBX, imported by hand into Studio. |

**Line 2 of every source file states its intended Studio path.** Check it after pasting.
Several debugging rounds were lost to a file landing in the wrong object, and the symptom
is silent: a Script containing a module body runs, returns a table, prints nothing and
errors nothing.

## Studio setup this expects

```
ServerScriptService
  ChunkBuilder            (Script)
  ChunkProps              (Script)
  Bootstrap               (Script)
  Services                (Folder)
    BackdropService, BestTimeService, ChunkService, DeformationService,
    DiveFinaleService, FloodedHallsService, HubService, LeaderboardService,
    LevelService, LightingService, PlayerStateService, TimerService    (ModuleScripts)
ReplicatedStorage
  Shared                  (Folder) -> 8 ModuleScripts: ChunkDefinitions, HallRoute,
                                      LevelDefinitions, MaterialAppearance, MaterialConfig,
                                      PlanShapes, SubRegionGrid, Types
  Assets/TileMeshes       (Folder) -> imported MeshParts, exact names below
  Assets/Backdrop         (Folder) -> horizon props, OPTIONAL (see below)
StarterPlayerScripts
  Bootstrap               (LocalScript)
  Services                (Folder) -> AudioService, CloudService, DeathService,
                                      DeformationRenderer, HubLeverService, HubVoteService,
                                      InputService, PauseMenuService, ScreenEffects,
                                      SeaService, UIService
```

Line 2 of each file is the authority if this list and a file ever disagree.

`RemoteEvents` and `RemoteFunctions` are created at runtime by `Bootstrap`; do not make
them by hand. `Assets/Chunks` and `ServerStorage/ChunkTemplates` are created by
`ChunkBuilder`.

### Meshes to import into `Assets/TileMeshes`

Names must match exactly. The importer wraps each in a Model, which the code unwraps and
warns about; harmless. **Delete the Workspace copy after moving each one**, because
imported MeshParts are unanchored with collision on and will rain onto spawn.

```
Honey_Platform_Skinned   Honey_Platform_16x12   (FBX, Bone children)
Slime_Platform_Skinned   (FBX, must keep its Bone children)
Butter_Platform_16x8   Butter_Platform_12x10   (FBX, Bone children)
Wax_Shell_16x8_A   Wax_Shell_16x8_B   Wax_Shell_12x10_A   Wax_Shell_12x10_B   (FBX, Bone children)
BubbleWrap_Sheet_10x8   BubbleWrap_Sheet_12x4   BubbleWrap_Sheet_13x8      (FBX, Bone children)
BubbleWrap_Sheet_14x4   BubbleWrap_Sheet_16x4   BubbleWrap_Sheet_16x8      (FBX, Bone children)
Footprint_Sole   Footprint_Sand      (OBJ)
Sand_Surface_10x6_18   Sand_Surface_11x4   Sand_Surface_12x4     (FBX, Bone children)
Sand_Surface_12x6_18   Sand_Surface_13_5x4   Sand_Surface_14x4     (FBX, Bone children)
Sand_Surface_14x6_18   Sand_Surface_16x4   Sand_Surface_16x6_18    (FBX, Bone children)
Honey_Tile_Interior   Honey_Tile_Edge   Honey_Tile_Corner
Slime_Tile_Interior   Slime_Tile_Edge   Slime_Tile_Corner
```

Every `*_Platform_*` above is a rig and must be the **FBX**, not an OBJ: an OBJ carries no
armature so the mesh imports rigid and silently never deforms. `ChunkBuilder` checks
`HasSkinnedMesh` and warns.

The per-tile `Honey_Tile_*`, `Slime_Tile_*` and `Soap_Tile` meshes are FALLBACK ONLY,
used when a platform is not a rig size or the FBX has not been imported, and NONE of
them should be visible in normal play any more. `check_chunk_forms.py` fails on any slab
that would fall back -- its allow-list is empty and should stay empty, because that
failure is completely silent in game.

Honey ran with a single 16 x 18 rig for a long time, so `P4` and `C1` (both 16 x 12)
never deformed; the handoff called it deliberate, which was a rationalisation of a
missing asset. `Honey_Platform_16x12` exists now. ChunkBuilder's rig audit is what
surfaced it, as "Honey -- ONLY 1/3 slabs rigged".

### The Flooded Halls kit (Level 4)

`blender/gen_flooded_halls.py` builds the `Hall_*` meshes. They can go in `Assets/TileMeshes`
or `Assets/Backdrop`; `FloodedHallsService` looks in both. Seven are placed:

```
Hall_Column   Hall_Cove   Hall_Steps   Hall_Dome   Hall_Hand   Hall_Rail   Hall_Ripple
```

`Hall_ArchWall`, `Hall_Slide`, `Hall_Vault` and `Hall_CurveWall` are still generated and no
longer placed. The arch and the flume are built from parts in code now, because a stale or
mirrored import of either broke the level for several rounds and nothing in game could tell
that apart from a code bug. Every placed mesh is compared with the size the generator last built
(`EXPECTED_SIZE` in the service, printed by the generator and mirrored in `kit_sizes.txt`), and a
mismatch warns with the name of the file to re-import.

### Meshes to import into `Assets/Backdrop` (optional)

```
Backdrop_Island   Backdrop_Mushroom   Backdrop_House    Backdrop_Tree
Backdrop_Cloud    Backdrop_Arch       Backdrop_Statue   Backdrop_Umbrella
Backdrop_Slide    Backdrop_WaterTower Backdrop_Hoop

Backdrop_Keyboard Backdrop_Butter     Backdrop_Microphone   Backdrop_HoneyDipper
Backdrop_Soap     Backdrop_SlimeJar   Backdrop_Candle       Backdrop_Foam

Backdrop_SlideTower   Backdrop_Flume        Backdrop_SplashBucket
Backdrop_FloatRing    Backdrop_Cabana       Backdrop_LifeguardChair
Backdrop_DivingPlatform  Backdrop_PoolLadder   Backdrop_Lounger
Backdrop_MushroomFountain  Backdrop_LaneRope   Backdrop_Palm
Backdrop_PlayStructure  Backdrop_RockFall     Backdrop_WaterCannon
Backdrop_PirateShip   Backdrop_WaveSlide    Backdrop_SprayDome

Backdrop_Sandcastle   Backdrop_Surfboard    Backdrop_BeachHut
Backdrop_Dinghy       Backdrop_BeachFlags                                  (OBJ)
```

The last five are the BEACH set, and they belong on the sandbars rather than in the ring.
The waterpark half is things that were installed; the beach half is things somebody LEFT --
a board pushed into sand, a hull turned over, a line of flags. That contrast is most of what
makes a shore read as a shore instead of as more scenery.

The third group is the AQUAPARK set, and it changed what the horizon is. It used to be 116
towers, which is a skyline whatever else stands between them -- the towers were never too
tall or too plain, there were simply too many for anything else to be the subject. There are
**46** now, pushed back to 1400 studs and beyond, and the near band belongs to slide towers,
flumes and splash buckets.

A skyline is repeated verticals. A waterpark is curves and cantilevers: things that spiral,
lean out over water, and stop in mid-air. That is what makes the horizon read as somewhere
else rather than as the same city with different paint.

The second group is the ASMR set: the game's own materials and the genre's own objects at
a monstrous size, so the horizon reads as where the level came from rather than as generic
liminal architecture. `BackdropService` gives these eight a fixed tint rather than a random
pastel, because they are recognisable by colour as much as by shape.

**Plus a `*_Detail` mesh for most of them** -- 15 more files, same names with `_Detail`
appended. `BackdropService` draws the detail mesh in the near band (950-1900 studs, where a
prop can fill a third of the screen) and the plain one further out, so this is a real LOD
pair rather than a duplicate. Four props -- house, soap, foam, keyboard -- are built
entirely from boxes and have no segment counts to scale, so `gen_backdrop.py` detects that
their detail pass is identical and does not write the file at all. Their absence is
correct, not a missed export.

Everything here is optional in both directions: no detail mesh means the near band draws
the plain one, no plain mesh means a primitive stands in.

Unlike `TileMeshes`, **this folder is optional and may be half full**. `BackdropService`
clones what it finds and falls back to primitive shapes for anything absent, so the
horizon stays populated while you are mid-import and a mistyped name degrades instead of
erroring. It warns once if the folder is missing entirely. With an empty folder the
backdrop is still fully populated -- there is a second, primitive-only scatter that runs
regardless, so importing adds variety rather than being what makes the horizon appear.

**Every hard edge is chamfered.** `gen_backdrop.py` bevels any edge whose faces meet at
more than 45 degrees, one segment, before the smoothing split. That threshold is above the
~36 degrees between faces of a 10-segment tube, so curved surfaces are left alone and only
genuinely hard corners are touched.

This is the largest single quality difference available on these props and it is not detail:
a perfectly sharp 90-degree edge does not exist physically and cannot catch a highlight, so
an unchamfered box is two flat tones meeting at a seam -- which is exactly what an untextured
Roblox part looks like. One segment rather than more, because a single chamfer face gives two
edges at ~45 degrees, both above the split threshold, so the chamfer stays flat-shaded and
reads as a crisp bright line instead of a soft blur.

It roughly doubles a box-heavy prop, which is why the budgets are 3200 (plain) and 12000
(detail) rather than the 1200/6000 they were before the chamfer existed. These are still
small meshes drawn a handful of times each. OBJ, not FBX: nothing in the backdrop deforms.

### PBR maps: one manual step per material

`blender/gen_pbr.py` writes tiling ColorMap / NormalMap / RoughnessMap PNGs into
`RobloxProject/textures/` -- 27 files: three per material for all six, plus shared sets
for the slabs, the sea and the backdrop architecture (see below).

| Material | UV tile | Surface identity | Roughness |
|---|---|---|---|
| Honey | 9 studs | broad viscous swell, trapped bubbles | 0.03 - 0.13 |
| Slime | 7 studs | burst bubbles with crater rims | 0.14 - 0.44 |
| Butter | 8 studs | knife smears, stretched hard along one axis | 0.38 - 0.66 |
| Wax | 6 studs | Voronoi crazing, cracks read DULLER not shinier | 0.34 - 0.74 |
| Sand | 3 studs | six octaves of grain, narrow roughness range | 0.72 - 0.92 |
| BubbleWrap | 5 studs | film creases ONLY -- the pockets are geometry | 0.26 - 0.40 |

Roughness is the value that matters and the least obvious one. A wet surface is not defined
by being shiny, it is defined by being shiny UNEVENLY -- uniform gloss reads as plastic at
any level. Sand's range is deliberately narrow for the same reason inverted: a wide range
there would read as patches of wet sand.

**A runtime Script cannot apply them.** `SurfaceAppearance.ColorMap` and friends require the
Plugin capability and THROW when written from a normal script -- which took out ChunkBuilder
mid-build once already and left the level with six missing chunks. The maps go on the
template, by hand, once:

1. Upload the PNGs for one material (Asset Manager -> Images).
2. Select its mesh in `Assets/TileMeshes`, insert a **SurfaceAppearance**.
3. Set `AlphaMode = Overlay` and paste the three ids.
4. Repeat per material. Wax and sand have several meshes each and every one needs its own
   SurfaceAppearance -- copy the first and paste it onto the rest, the ids are shared.

A re-import replaces the MeshPart and takes its SurfaceAppearance with it. Copy the
SurfaceAppearance out first (Ctrl+C), then paste it onto the new part; the uploaded ids
stay valid, only the container changes.

`ChunkBuilder` clones these templates and `Clone()` carries children, so every platform in
the level inherits the maps from the one object you edited. `MaterialAppearance` warns once
per material if a template arrives without one.

**Every rigged mesh needs UVs for this**, and none of them had any before 2026-08-14.
Honey and slime project in `build_surface`; butter, wax, sand and bubble wrap project inside
`export_fbx`, which is the better hook -- anything leaving those files has UVs whatever route
it took to get built. If a textured surface looks smeared, the mesh in Studio predates the
change and needs re-importing. That is 24 FBXs in total, so it is worth doing one material
at a time rather than in one sitting.

### Slabs: MaterialVariant, not SurfaceAppearance

Slabs are `Part`s, and SurfaceAppearance does nothing on a Part -- silently, no warning.
`MaterialVariant` is the mechanism that works there, and it splits the same way: the maps
need the Plugin capability, so the variant is made by hand and `MaterialAppearance` only
writes its **name**, which is a plain string.

`Slab_Color`, `Slab_Normal`, `Slab_Roughness` -- ONE set for all six materials. The slab is
the cake, not the icing: the same stone under everything, only the tint changes. Its
ColorMap is near-white (0.72 to 1.0) because a MaterialVariant's ColorMap is MULTIPLIED by
`part.Color` rather than blended over it -- bake colour in and every slab in the game comes
out that colour whatever `baseColor` says.

Three variants, because a variant only applies to parts whose `Material` equals its
`BaseMaterial`, and the slabs use three. **All three point at the same three images.**

| Create under MaterialService | BaseMaterial | Used by |
|---|---|---|
| (name of your choice) | Concrete | stable, Honey, Slime |
| (name of your choice) | Plaster | ButterWax, Soap, BubbleWrap |
| (name of your choice) | Slate | KineticSand |

1. Upload `Slab_Color/Normal/Roughness`.
2. MaterialService -> insert three **MaterialVariant**s, one per BaseMaterial above.
3. Paste the same three ids into each. `StudsPerTile` around 4 suits these slabs.
4. Put the names into `SlabVariants` in `MaterialAppearance.lua`.

Blank names are safe -- slabs render as they do today. A name that does not exist is also
safe: Roblox falls back to the base material silently, which is why `MaterialAppearance`
warns once per name when it cannot find one.

MaterialVariant uses the part's own stud-based mapping, so **slabs need no UVs**. That is
only a MeshPart concern.

### The backdrop

Same split again, because the backdrop is made of both kinds of thing.

**Architecture -- `Part`s, so MaterialVariant. TWO of them now**, both on BaseMaterial
`Concrete`, named `ConcreteBackdrop` and `PoolTileBackdrop` (the names are already in
`BackdropService`; just match them in MaterialService).

| Variant | Maps | Used by |
|---|---|---|
| `ConcreteBackdrop` | `Concrete_*` | towers, facades -- the municipal shell |
| `PoolTileBackdrop` | `PoolTile_*` | the colonnade -- it stands IN the water |

Glazed mosaic is the single most aquapark surface there is: concrete says municipal
building, tile says leisure centre, and it does it from a long way off because a regular
grid at a legible size is something no natural surface has. Its roughness is 0.16 on the
tiles and 0.78 on the grout -- a uniform value over a tile pattern looks like printed lino.

One `Concrete_*` variant covers the rest: every tint out there comes from
`part.Color` and the pastel palette, and a variant's ColorMap multiplies rather than
replaces, so a single near-white concrete serves all six.

The colonnade changed from `SmoothPlastic` to `Concrete` so it can take the same variant.
Without a variant the two are near enough identical at that distance that it costs nothing.

**Sea tiles -- MeshParts, so SurfaceAppearance.** `Water_*` on the `Sea_Tile` template in
`Assets/Backdrop`; all 45 tiles are clones of it, so one SurfaceAppearance textures the
whole ocean. `AlphaMode = Overlay`.

The wave mesh already carries swell from 61 to 297 studs; `Water_*` is the scale below that,
capillary ripple at 40 studs per tile. 1600 / 40 = 40 exactly, so the texture seam lands on
the mesh seam and both wrap together. A UV scale that did not divide `TILE` would put a
visible break in every tile.

`gen_sea.py` and `gen_backdrop.py` now project UVs in their export functions, so the sea
meshes and the horizon props all carry them. **Re-export and re-import `Sea_Tile` before
adding its SurfaceAppearance** -- the copy in Studio predates the UVs.

### One manual property

`Lighting` needs its high-fidelity engine (older Studio called this
`Technology = Future`). A script can neither read nor write that property, so it cannot be
set or verified in code. Check by eye: honey and slime should carry a specular streak that
moves with the camera. Without it `EnvironmentSpecularScale`, `EnvironmentDiffuseScale` and
`ShadowSoftness` are inert.

## The run ritual

**After any `ChunkBuilder` change, delete the children of `ServerStorage/ChunkTemplates`
and `ReplicatedStorage/Assets/Chunks`, then Play.** `ChunkBuilder` skips chunks that
already exist, so without this you see the old geometry and conclude nothing worked.

Before pasting a geometry change, run `python blender/check_chunk_forms.py`. It catches the
boring failures without a Studio round trip; see the chunk layout tools below.

For Level 4, run `python blender/check_halls.py` as well, and `python blender/plan_halls.py`
if the route, the chamber or the pool changed.

`Bootstrap` no longer builds a fixed level. Players spawn into the lobby (`HubService`) and a
run is built from what they choose there; finishing or leaving returns everyone to the lobby.

## Where each material stands

| Material | Visual approach | State |
|---|---|---|
| Honey | Skinned mesh, 30 bones (one per cell), bone-driven dents + wave, overlay footprint | Done, iterated heavily |
| Slime | Skinned mesh, 20 bones, springy bone wave + ring train + shallow prints | Done |
| Soap | GRANULAR: 2 layers of small anchored cubes; break off under your foot as physics debris | Works |
| Kinetic sand | Skinned BLOCK of sand; rig opens a bowl with a raised rim, stamped sole sits in it, tracks permanent, cell COLLAPSES after 3 footfalls (or 3s standing) | Works |
| Butter-wax | Skinned butter block + Voronoi-fractured wax coating wrapping top, sides and bottom | Works |
| Bubble wrap | Skinned sheet, one bone per pocket; pockets under your foot burst flat | Works |

Wax is no longer one of those: it is a stick of butter under a wax coating, and both are
skinned meshes. `Butter_Platform_*` is the block; `Wax_Shell_*` is the coating, one mesh
fractured into Voronoi shards with a bone each, wrapping the top, all four sides and the
underside. Standing on a cell pushes its shards out and down, which opens real gaps onto
the butter and drops you into it. The butter keeps 60% of the dent afterwards and holds
it for `decayDuration = 13`, the longest of any material: butter is plastic, and that is
what separates it from honey recovering and slime snapping back. Collision is the tile
grid, not the meshes -- wax does not drop you through, it lets you sink.

The block is `THICK = 3.6`, which is a ceiling rather than a taste call. The mesh IS the
visible platform (the slab goes transparent as soon as a rig attaches) and the wax wraps
below the skirt, so the shell reaches `2.9 - (THICK + 1.17)` in slab-local Y against a
slab underside at -2. Past 3.73 the visible block hangs out of the collision volume. The
depth exists to give `WAX_SINK = 2.3` room: a dent can be no deeper than the body it is
pressed into, and the surface bottoms out around 71% of the bone travel once the
skinning blends, so ~1.6 studs of visible dip with 2.5 studs of body still under it.

`MESHLESS` now means NO PER-TILE MESH specifically, which is not the same as no mesh.
Sand, wax and bubble wrap are all in it and all three carry geometry, all three by rig.
What they have in common is that a mesh cut to the sub-region grid would fight their
identity -- a tile
mesh gets in the way of a footprint, and it draws a lattice across a surface whose
deformation has nothing to do with cells.

## Levels and the lobby

The lobby is a permanent room; runs are built and torn down around it. It has one pad per level
in `LevelDefinitions.All`, each made of that level's headline material, plus a pad for the
Sandbox as a development route. There are also a mode pad (Chill or Hardcore), a run-length pad,
a personal-best statue and a leaderboard board. Run length scales the level's chunk count by
0.5 / 1 / 1.5 for Short / Medium / Long. Starting a run is voted on (`HubVoteService` and
`HubLeverService` on the client). The run request is plain data on purpose, so a later
private-server teleport can carry it; `check_hub.py` enforces that. The design and the plan are
in `docs/superpowers/specs/2026-08-28-lobby-hub-design.md` and
`docs/superpowers/plans/2026-08-28-lobby-hub.md`.

| Level | Name | Shape | Chunks (Medium) | Setting |
|---|---|---|---|---|
| 1 | City Shore | spiral | 40 | the city, beach and waterpark horizon; ends on the high dive |
| 2 | Open Sky | spiral | 44 | no horizon |
| 3 | Far Water | spiral | 50 | no horizon, kept for a second backdrop |
| 4 | Flooded Halls | path | 44 | inside a flooded tiled bathhouse, ending on a flume |
| Sandbox | all materials | spiral | 82 | development route, its own pad |

## City Shore's finale (Level 1)

**State on 2026-09-15:** built, and `check_hub.py` passes. **Untested in Studio.** It lives in
`src/Server/Services/DiveFinaleService.lua`, and the level asks for it with `finale = "dive"`.

- **The platform.** The last chunk runs onto a tiled deck with a springboard cantilevered out
  past its outer edge, rails round the sides that are not the way in, and a flag at the corner.
  It is built in the frame `LevelService` now returns as `finishFrame`: the far end of the last
  chunk, on its exit surface, with **+X pointing away from the spiral's centre** -- the one
  direction at the top of the climb with nothing under it but sea.
- **The dive.** The column of air past the deck's edge and below the board is the trigger, so
  jumping off the board counts and walking off the deck does not. The fall is about 830 studs
  and three seconds, through the backdrop's cloud layers.
- **The finish is the sea.** The level completes on reaching the water, with spray, a spreading
  ring and a splash; the diver is left standing chest-deep on a hidden floor until the lobby
  takes them back four seconds later.
- **Three things that each fail silently on their own**, so `check_hub.py` gates all three:
  the splash is a HEIGHT TEST rather than a Touched (a diver crosses about nine studs a frame
  and a trigger part is skipped outright); the kill plane must leave a diver alone, since it
  sits 40 studs under the lowest chunk and 680 above the water, which Bootstrap does by asking
  `DiveFinaleService.ownsFall`; and the old finish line must stand down, or the run completes at
  the end of the route with the dive left as scenery.
- The sea's height comes from `BackdropService.waterLevelAt`, because the swell has a 72-stud
  range. With no backdrop standing it falls back to -700.

## The Flooded Halls (Level 4)

**State on 2026-09-14:** built, and every static check passes. It has been through many rounds
of in-Studio review; the latest interior pass (walls, ceiling, pool) and the open flume, gangway,
entrance and dome detail before it **have not been seen in Studio yet**. Everything is in
`src/Server/Services/FloodedHallsService.lua` plus `src/Shared/HallRoute.lua`.

### How it fits together

- **One shape, two readers.** `Shared/HallRoute` holds the route. `LevelService` lays chunks
  along it and `FloodedHallsService` builds walls along it, so the corridor turns exactly where
  the chunks do. The route zig-zags (left, right, right, left) and stays level
  (`layout = "path"`).
- **Corners turn on the `S2_Junction` chunk**: in by its main run and out by its arm for a left
  turn, the other way round for a right, with a 5-stud jump in and out. Every corner is a
  checkpoint. `LevelService` returns the real leg lengths as `routeLegs` and the halls are built
  from those, so there are no gaps to fill and no fill-in platforms.
- **The walkway is 56 studs above the flooded floor**, so a fall passes the kill plane instead
  of landing a player alive in the water.
- **The run ends on the flume.** Hold E at its mouth; the ride follows the helix down, runs off
  the end over a 400-stud shaft, and the finish is at the bottom.

### What is in it

- **Corridor:** a colonnade in the shallows, transverse arches every third bay (built from
  parts), rooflights over the walkway, one failing light, and a tall two-storey stretch with a
  glazed roof.
- **Walls:** a sea-green wainscot with cream tile above, and a dado, a teal stripe and a
  two-step cornice on every wall in the level. Pilasters with capitals and plinths behind the
  columns, and between them, alternately, a high window or a round-headed blind niche, with the
  water-level light slots and blind doorways below.
- **Ceiling:** coffered, with ribs down each leg on the column lines and beside the rooflights,
  carried round the corners.
- **Floor and pools:** a pool 40 studs deep down the middle of every leg under the walkway. It
  has a coping, a gutter, a depth band, underwater lamps, lane ropes and lane stripes, and steps
  down at the entrance end. It turns each corner as one pool. It is lined with the
  `PoolTileBackdrop` MaterialVariant if Studio has one, and plain tile if not. There are also
  sunken basins with steps along the walls, dry ledges and cubicle partitions.
- **Water:** translucent plates with a slow swell, drip rings, drifting debris and caustic
  lights, Bathroom reverb and water drips.
- **Behind the start:** one more bay ending in a wall with a dry deck, an empty lifeguard chair,
  a stopped clock, and a doorway into a flooded passage lit from a side room nobody can see
  into.
- **The last chamber:** a domed room with an oculus, ribs and a frame round the ceiling
  opening, windows set into its walls, a timber gangway on trestles out to the flume, and a
  pool ladder hanging into the shaft. The flume is an open, banked trough with a rolled lip and
  flanges, built from parts along the ride's own curve and held up by a steel mast with a
  bracket under every flange and a lamp on top.

### Checking it

- `python blender/check_halls.py` covers route/room agreement, the lane guard, arch clearance,
  the corners, the flume and rider geometry (bank included), the gangway, the shaft, the
  entrance, the dome, the dressed walls and the pool's fit. Every gate added since 2026-09 was
  proven by putting its bug back and watching it fail.
- `python blender/plan_halls.py` draws all three run lengths and a section into
  `halls_plan.png`, and exits with an error if two legs' pools overlap.

### Lessons from this level

- **Part-built beats imported for anything the route touches.** A helix's handedness cannot be
  verified through the FBX import, and a stale import looks exactly like a code bug.
- **No Glass anywhere near translucent chunks.** Its refraction made slime, honey and jello
  soda vanish from some angles. Water is SmoothPlastic, tiled into pieces no bigger than 320
  studs so the transparency sort holds.
- **Neon cannot fake light.** Light shafts and halos made of it read as solid slabs; light comes
  from SurfaceLight and PointLight.
- **Everything visibly supported.** Every floating light, lintel and platform came back as a bug
  report.
- **Lighting moves in small steps.** It has been called both too bright and too dark.
  `ROOF_GLOW`, `OCULUS_BRIGHTNESS` and the pool lamps' `glow.Brightness` are the dials.

### Open for this level

- The latest round is untested in Studio (see State above).
- Part count has grown a lot: the flume is about 900 parts and the interior pass adds a few
  hundred more. Watch frame rate in the last chamber and on Long runs; `FLUME_SEGMENTS` is the
  first thing to lower.
- Four generated `Hall_*` meshes are unused (see the kit above).

## Chunk silhouette

Chunks are no longer all 16-wide rectangles. Two segment fields do the work, and both only
ever add or resize slabs between the entry and exit faces, so neither changes `EntryZ`,
`EntrySurfaceY`, `Rise` or `Length`:

- **`widthEnd`** tapers a segment from `width` across its length, built as a run of pieces.
- **`shelf`** adds slabs alongside, dropped by `drop` (default `STEP_RISE`, walkable both
  ways). A run-off lane on risk chunks, pure profile on stable ones.

Two rules constrain every silhouette. Both are enforced by `check_chunk_forms.py`.

1. **Entry and exit faces stay wide and centred on X = 0.** Every chunk boundary is a jump
   and `LevelService` always leaves from and arrives at the centre line, so narrowing
   belongs in the middle of a chunk. Nothing goes below 10 studs at a face.
2. **Never taper honey or slime.** A taper is several slabs, so it is several sub-region
   grids, and their tiles are edge-matched: a new grid draws a meniscus lip across the
   middle of what should be one unbroken pour. `taperGuard` warns if you try.

Two things are load-bearing and look like ordinary numbers:

- `P1_HoneyCorridor`'s honey slab must stay **16 x 18**. That is the one size
  `Honey_Platform_Skinned` is rigged for, and a rig cannot be resized in code. Change it
  and the corridor silently drops to per-tile meshes, which looks merely worse rather than
  broken, so nothing in game tells you. Its variety is bought with shelves, which are
  separate slabs and leave the lock alone.
- The honey in `P4` and `C1` is 16 x 12 **on purpose**: it is deliberately not a rig size,
  which is what keeps the per-tile fallback visible in every run.

`R2_SoapBridge` is one plain 14 x 20 slab. It used to pinch to an 8-wide waist, which read
as an hourglass; soap now gets its shape from the material's own form, and the rounding is
done by omitting cubes rather than by tapering slabs.

## Blender

Blender 5.2 at `C:\Program Files\Blender Foundation\Blender 5.2\blender.exe`. Run headless:

```bash
"/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --python gen_honey_skinned.py
```

| Script | Produces |
|---|---|
| `gen_honey_skinned.py` | `Honey_Platform_Skinned.fbx`, the rigged honey platform (16 x 18) |
| `gen_slime_skinned.py` | `Slime_Platform_Skinned.fbx`, the rigged slime platform (16 x 12) |
| `gen_butter_skinned.py` | The TWO rigged butter bodies (16x8, 12x10) |
| `gen_wax_shell.py` | The FOUR Voronoi-fractured wax coatings (16x8 and 12x10, variants A and B) |
| `gen_bubble_wrap.py` | The SIX bubble wrap sheets. Reads its own size list back out of ChunkBuilder. |
| `gen_tile_meshes.py` | The ten per-tile OBJs |
| `gen_footprint.py` | `Footprint_Sole.obj` and `Footprint_Sand.obj` (the berm-rimmed one) |
| `gen_sand_surface.py` | The NINE kinetic sand surface skins. Reads its size list out of ChunkBuilder. |
| `gen_pbr.py` | Tiling PBR maps into `textures/`. Honey and slime. Uploaded and attached by hand. |
| `gen_sea.py` | `Sea_Tile`, `Sea_Foam`, `Sea_Ring`, `Sea_Surf`. Prints the Luau wave constants BackdropService must match. |
| `gen_backdrop.py` | The NINETEEN horizon props, each at two detail levels (34 files). Optional -- BackdropService falls back without them. |
| `gen_flooded_halls.py` | The `Hall_*` kit for Level 4. Writes `kit_sizes.txt` and prints the `EXPECTED_SIZE` table the service needs. |
| `gen_chunk_meshes.py` | Superseded platform-sized meshes; kept for reference |
| `render_*.py` | PNG previews |

**Always render and look before exporting.** The render scripts exist because meshes were
handed over broken twice: a self-intersecting outline from a mirrored arc, and a footprint
outline that was correct in maths but wrong in silhouette. A render catches both in
seconds.

FBX exports use `global_scale=0.01` because Roblox imports these at exactly 100x
(FBX is centimetre-native, Blender exports metres).

`gen_slime_skinned.py` runs `validate_mesh` before exporting, and it earns its place:
the first slime mesh exported and imported perfectly happily while being wrong. Its
tendrils are sparse and narrow enough that between them the skirt ring landed exactly on
the top ring, giving a wall of zero height — 37 degenerate faces, 43 duplicate vertices,
and an entire top surface of INVERTED normals, which Roblox would have culled. Honey
avoids this only by accident: its seven drips sit close enough that their gaussian tails
never quite reach zero between neighbours. Slime needs the explicit `SKIRT` constant.

Each skinned generator PRINTS the `SKINNED_PLATFORMS` entry it needs, including
`surfaceOffset`. Run it and paste; never measure that by eye. It is the distance from the
mesh's bounding-box centre to the walkable plane, and the hanging detail drags the
bounding box far below the surface — slime's tendrils reach 4.0 studs where honey's drips
reach 2.6, which is why the offset is per mesh (2.72 against 1.82) rather than shared.

### Chunk layout tools

Same idea applied to geometry instead of meshes, because the Studio loop for a
`ChunkBuilder` change is paste, clear both folders, Play, walk over there.

| Script | Does |
|---|---|
| `chunk_layout.py` | Parses `ChunkBuilder.server.lua` and reproduces the slab layout. Shared by the other two. |
| `check_chunk_forms.py` | `python check_chunk_forms.py` — asserts the layout contract. No Blender needed. |
| `check_lua.py` | `python check_lua.py` — eleven checks across `src/`, every one of them a bug that already shipped once: use-before-declaration, block balance, annotated fields, undeclared constants, undeclared calls, cross-module calls, a `local` declared twice in one scope, a field read off a constants table that has no such field, stage counts, staged effects that never read `ctx.stepCount`, and materials with no screen look. No Blender, no Luau needed. |
| `check_hub.py` | `python check_hub.py` -- the lobby: every level has its own distinct headline material for its pad, every level in `All` gets a pad, pads are far enough apart to stand on, and a run request stays plain data that can survive a teleport. |
| `check_halls.py` | `python check_halls.py` -- the Flooded Halls. See that section for what it covers. |
| `plan_halls.py` | `python plan_halls.py` -- `halls_plan.png`: the three run lengths in plan plus a section. Needs matplotlib. |
| `check_plan_shapes.py` | `python check_plan_shapes.py [--png]` — loads `PlanShapes.lua` into a real Lua interpreter (`pip install lupa`) and walks every outline at the cube grid each chunk actually builds: enterable, leavable, joined, no stranded floor, and no lane under 3.4 studs. `--png` writes `plan_shapes.png` (the vocabulary) and `chunk_shapes.png` (what each chunk builds). |
| `render_chunk_forms.py` | `chunk_forms_top.png` (footprints) and `chunk_forms_persp.png` (tiers) |

**Run the checker before pasting.** It covers the things with a right answer: entry and
exit faces wide enough to land on and straddling X = 0, no hole in a route bigger than a
jump, slabs that meet sharing enough width to walk across, no interpenetration, geometry
inside the published `Length`, the ramp's walkable surface starting at `SURFACE_Y` and
finishing `RAMP_RISE` above it, and the 16 x 18 honey lock. The renders are for the part
that is a judgement call — passing the contract and looking wrong are compatible.

Both read the Luau rather than restating it, so editing a chunk needs no second edit here.
The parser is strict on purpose and will raise rather than skip a field it does not know.

## Open items

- **The backdrop is LOCKED TO THE PLAYER, and that is the whole idea.** It re-centres
  horizontally every frame, so walking a level closes the distance by nothing and the
  horizon never grows or passes behind you: a place clearly there, clearly enormous, and
  permanently out of reach. Static placement fails from both ends of a level -- too far
  from one, visibly arrived at from the other. It follows X and Z ONLY; taking the
  player's height too would peg the horizon to your altitude and lift a thousand studs of
  architecture every time you climbed a step, which is the one move that gives it away.
- **The backdrop must never roof the level over.** Five of the six materials read
  through `EnvironmentSpecularScale` picking up the SKY, so enclosing the space would
  flatten every glossy surface in the game. It adds no fog and no ceiling either --
  LightingService's existing atmosphere (0.28 density, 1.1 haze) already dissolves
  anything a thousand studs out, which is exactly the fog this wants.
- **Part count is the backdrop's only real cost**, because the whole model is pivoted
  each frame. It sits near 320: a first pass at finer window grids and smaller floor
  tiles reached 880, which buys nothing the haze does not eat anyway. There is a 2-stud
  deadband on the pivot, well under a tenth of a degree of parallax at 900 studs, so
  standing still costs nothing at all.

- **Sand needs BOTH a rig and a stamp, and neither works alone.** Verified by render,
  twice, not reasoned about.
  - The RIG alone cannot make a footprint. At a 0.9-stud bone pitch only about three
    bones fall inside a sole and each spreads its influence 1.5 studs, so a press comes
    out a vague smudge. This is soap's lesson again: SKINNING STRETCHES, and a stretch
    cannot hold a sharp edge. Resolving a print with bones alone wants a ~0.45 pitch,
    which is 450 bones on the biggest slab.
  - The STAMP alone cannot make displacement. A sole-shaped part on an unbroken plane
    reads as a sticker however well modelled -- the same objection this file records
    against decals -- which is exactly what the rigid-OBJ version looked like.
  So the rig presses a broad shallow bowl with a raised rim, which is what skinning IS
  good at, and the stamp lays the sole's own shape inside it, which is what a mesh part
  is good at. `spawnFootprint` takes a `sink` so the sole sits on the bowl's floor
  instead of floating over the hollow it belongs in.
- **The sand skin is ONE MESH PER SLAB SIZE.** A single tile mesh repeated across the
  sub-region grid was the cheap alternative and does not work: a repeated noise field is
  highly legible, the eye finds the same clump arrangement over and over and reads a
  lattice. The resting relief is not trying to model grains either -- the Sand material
  already carries that texture. It supplies MESO scale, the unevenness at half a stud to
  two studs, so a print reads as a cut in uneven ground rather than a decal on a plane.
- **Superseded: `SURFACE_MESHES` / `attachSurfaceVisual`,** a rigid per-slab path added
  and removed within a session. Sand uses `SKINNED_PLATFORMS` and `OVERLAY` like bubble
  wrap: OVERLAY because the skin is 0.89 thick, and hiding the slab under it would leave
  a wafer floating over a four-stud drop.
- **Sand's resting surface is CLUMPS, and the noise has to be BILLOW.** Plain value
  noise gives rolling dunes -- every peak and trough equally soft -- which is sand after
  wind, not sand after being squeezed. Folding it about its midpoint (`1 - |2n - 1|`)
  puts a crease wherever the field crosses the middle, so the surface becomes rounded
  lumps meeting in sharp seams. Amplitude is 0.4, not the 0.075 it started at: that was
  a plane with a hint of texture on it, and it is why nine meshes made no visible
  difference.
- **The sand skin WRAPS the slab: top, four sides and underside.** It was a 0.9-thick lid
  with the slab showing below, so a platform was a sand-topped concrete block. Wrapping
  it makes a block OF sand -- and that is also what lifted the press ceiling from 0.45 to
  0.85, because a hollow can only be as deep as the material under it and a lid had 0.9
  studs in total. Sand is NOT in `OVERLAY` any more for the same reason: the slab is
  enclosed, so leaving it visible would only put concrete inside a closed sand box.
- **Relief is pushed INWARD on every face, and faded to zero at every face border.**
  Inward because relief standing proud of the nominal box would make the mesh wider than
  the slab, which is exactly what ChunkBuilder's import check measures. Faded because six
  faces each carrying their own relief would meet at six different heights along every
  shared rim and split the block open; taking each face to zero at its own border makes
  all six arrive at the nominal box and join with no stitching. The walls also use a
  coarser step than the top -- only the top has to hold the shape of a footprint, and at
  the top's resolution the four 4.9-deep walls were three quarters of the triangles.
- **Superseded: press depth capped by the skin.** Relief already hangs 0.4 below the walkable
  plane and the skin's floor is at 0.9, so a press past ~0.45 drives the deepest lumps
  through the bottom of the skin and into the slab. That ceiling is fine because depth
  is not what makes a print readable on a clumped surface -- SMOOTHNESS is. The
  reference photographs read as footprints because the sand inside them is compacted
  flat while everything around stays lumpy, and a rig cannot do that: bones translate
  vertices, they cannot un-rough a surface. That is what the stamped sole is for.
- **The stamp IS sunk on the clumped surface, and was NOT on the flat one.** Opposite
  calls, same reasoning applied to a changed surface: on a plane, sinking it buried the
  only crisp edge sand had; among lumps standing 0.4 proud, a sole at plane height
  perches on top of them instead of sitting in the ground.
- **Sand does not heal, and permanence needs a BUDGET not a lifetime.** Every other
  material recovers on the server's decay timer; sand declines to, and the two disagree
  on purpose -- the pleasure of the stuff is crossing a platform and looking back at
  your own tracks, which a seven-second reset destroys. "Permanent" and "unbounded" are
  the same thing without a cap, so prints retire oldest-first at `SAND_PRINT_CAP` and a
  permanent print must NOT be given a fade, which is a lifetime by another name.
- **A DISSOLVING PLATFORM MUST GIVE UP ITS SLAB AS FLOOR.** The slab's top face sits 0.9
  studs below the walkable plane, so clearing a cell's collision drops the player exactly
  that far onto solid concrete -- standing in mid-air over a hole. This was keyed on
  GRANULAR, true of soap alone, and broke the moment sand learned to collapse. It is
  keyed on `dissolveTime` now, the same field that opens the hole, so the two cannot
  drift apart again.
- **The collapse has to clear the block's own depth to read as a hole.** At 3.2 into a
  5.1-deep block it dug a crater with a floor and four walls still under it. Past the
  depth the surface passes out through the underside and the cell is empty; what faces
  you is the inside of the far wall, whose backfaces Roblox culls, so you see through.
- **A COLLAPSING CELL TAKES ITS WHOLE COLUMN, and pinches as it goes.** The underside
  sheet used to be entirely static, and it was the flat plane that stopped a hole being
  see-through: the top dropped away and the floor five studs below it stayed, so you were
  looking into a pocket. Freeing the underside and the wall is only half the fix, because
  A RIG CANNOT CUT A HOLE IN ITSELF -- soap's lesson, and it applies here exactly:
  MeshId is fixed at import and skinning STRETCHES, so a cell driven straight down stays
  joined to its neighbours and hangs beneath as a curtain as wide as the cell. Trading a
  flat plane for a fat sheet is not a fix. Each bone is also dragged toward the cell's
  centre (`COLLAPSE_PINCH`), which converges the surface to a spike -- sand funnelling
  out, and an opening you can see through.
- **A collapse has THREE beats, and the delays are the effect.** The cell drops; sand
  spills through the hole -- first from the middle, which is what was under your feet,
  then from the RIM over the following second as an unsupported edge keeps crumbling;
  and the ground AROUND the hole sags toward it half a second later. Fired together
  these are one event and read as a wider hole. Staggered, the collapse has a
  consequence that arrives after you have already fallen, which is the thing being
  simulated. The spill accelerates (Quad In) rather than falling linearly, so a chunk
  keeps pace with a falling character instead of visibly lagging behind it.
- **Sand collapses on FOOTFALLS, not only on a clock.** A timer wants continuous
  occupancy of one cell and walking leaves long before it fires, so in practice only
  standing still ever triggered anything. `stepsToCollapse` counts contacts instead --
  kinetic sand does not fail because you stood on it, it fails because it has been
  worked. The clock stays for the standing-still case; both call one `collapse()`.
- **Sand COLLAPSES under sustained contact, and `dissolveTime` is now generic.** The
  server used to test `state.material == "Soap"`; it tests for the material HAVING a
  dissolveTime instead. Two materials collapse now for different reasons -- soap
  dissolves, sand loses cohesion -- but the mechanic is identical: stand here too long
  and the floor stops being floor. Sand gets 4.0s against soap's 2.5 because soap is a
  risk chunk you are meant to hurry across, while sand sits in PACE slots where a trap
  that punishes normal walking would wreck the level's rhythm.
- **`MaterialConfig.category` IS DOCUMENTATION. Nothing reads it.** Slot eligibility
  comes entirely from the CHUNK's category in ChunkDefinitions. Sand was left at "pace"
  on purpose even though it now collapses: its three chunks (P3, P4, C2) sit in pace and
  connector slots, and flipping the material to "risk" without moving those would leave
  the two disagreeing about how dangerous the level's pace sections are. Making sand a
  real risk material means editing ChunkDefinitions, not this field.
- **A collapsed sand cell does NOT come back**, the same as soap. Only the cell you stood
  still on goes, so it is self-inflicted -- but the holes are permanent for that attempt,
  and on a 4-deep slab enough of them could block a route. Worth a playtest before
  keeping.
- **THE FOOT IS THE BLADE.** Kinetic sand ASMR is defined by the knife, but the knife is
  only the instrument: what is satisfying is the CLEAN SHEARED FACE it exposes and the
  slump that follows. A literal knife was considered and rejected -- there is none in the
  world, and every other material here responds to the player rather than to a third
  party, so it would read as something happening TO the sand while you watch. A footfall
  is a shear event instead, and gets the same payload. Three beats: a near-vertical wall
  (`SAND_RINGS`, 6% of the sole's width for 92% of its depth, and NOT smooth-shaded --
  smoothing rounds off the one edge the shape exists to have), a single settle to 86%
  over ~0.9s, and cohesive clumps shed from the rim.
- **Sand sheds CLUMPS, not grains.** Loose specks flying off is dry beach sand; the whole
  point of kinetic sand is cohesion. The clumps are real anchored parts that hop once and
  stop, because a particle cannot come to rest and sand that does not stay where it fell
  never had any weight. They are budgeted per session like the micro plates.
- **Kinetic sand was the only material not in `FootprintProfiles`,** which is why the
  one material whose entire identity is holding a footprint never stamped one. It had a
  3x3 grid of small square plates per cell instead: a lattice of squares laid over the
  sub-region lattice, pressing a whole square down under a foot that is nothing like
  square. The sole mesh had existed the whole time. The plate machinery stays because
  HONEY still uses it as its no-mesh fallback.
- **A sand print does not SEEP, and stamps its own sole.** Honey and slime close their
  hollow over the print's lifetime because they flow; animating sand shut is precisely
  what would make it read as soft, so `seep = false` holds the shape until the cell
  decays. `Footprint_Sand` carries a BERM -- a lip of displaced material standing above
  the surface around the rim. That lip is the only visible evidence the stuff was pushed
  out of the way rather than just pressed, and it is what separates a granular print
  from a shallow viscous one.
- **Sole templates are cached PER NAME.** The cache was a single slot, so with two soles
  it would hand whichever was requested first to every material after it and the second
  would silently never appear.

- **BUBBLE WRAP'S GRID IS THE ONE GRID THAT STAYS.** Every other material had its
  lattice hunted down and removed, because in every other case the grid was an artefact
  of how the surface happened to be built. Bubble wrap is two films heat sealed on an
  exact square pitch, and the sealed lattice BETWEEN the pockets is most of what makes
  it recognisable. Do not jitter it.
- **The pocket pitch is FIXED IN STUDS, not a division of the slab, and it is 2.0
  because 2.0 divides 4.** This is what makes C4's taper work. Divide the slab into N
  cells and a 16-wide piece and a 12-wide piece get different pocket sizes and different
  lattice PHASE, so the pattern jumps at every join. But a fixed pitch is only half of
  it: the taper is cut into 4-stud pieces, each its own slab with its own sheet centred
  on itself, so unless the pitch divides 4 the rows still land at different offsets in
  chunk space. Every slab depth in the game (4, 8, 12) is a multiple of 2. The lattice
  also STRADDLES the origin (centres at (i + 0.5) * pitch) rather than sitting on it,
  which is what stops a 4-deep piece fitting one lonely row down its middle.
- **Pocket size is capped by the tile layer.** The apexes are pinned to the walkable
  plane so the rest of the sheet hangs below it, and FILM_THICK + BUBBLE_H must stay
  under TILE_THICKNESS (0.9) or the film sinks through the top of the slab it lies on.
  With the height tied to the diameter at the real-world 0.4 ratio, that ceiling is what
  limits how big a pocket can get without changing ChunkBuilder's layer.
- **A pocket is a POLAR CAP, never sampled from a heightfield.** On a square grid fine
  enough to stay affordable a pocket spans about six cells, and a circle six cells wide
  on a square lattice is an OCTAGON -- every pocket came out visibly eight-sided from
  above. Radially it is exact at any segment count and cheaper with it.
- **Bubble wrap replicates on EVERY entry, not just on its state transitions.** It used
  to announce only the first entry and the fourth (the transitions into `deformed` and
  `exhausted`) and send nothing for the two between. That was survivable while the client
  flattened a fixed FRACTION of a cell's bubbles per event; it stopped being survivable
  when popping became geometric, because a pocket you did not step near on those two
  entries could never burst while the cell spent its four counts anyway. `announced`
  guards the double send on a first entry.
- **A burst pocket keeps a third of its height** (`POCKET_SLACK`). At 0.9 it was 0.06
  studs proud of the film, so popped sheet was indistinguishable from sheet that never
  had a pocket and you could not see where you had walked. Every other material leaves a
  trail; this one was erasing its own.
- **The pitch is exact and the FULLNESS is not.** Jittering the spacing would be wrong
  and would look it. But no machine inflates two pockets identically, and a sheet where
  all of them match is the tell that something was generated. Fullness is keyed to the
  pocket's lattice POSITION, not its index in the list, so sheets of different widths
  agree about the pocket at a given place instead of every sheet repeating the same
  first-pocket value at its left edge.
- **The pop's drama is in the SWELL, not in the overshoot.** The obvious dramatic beat is
  to punch past flat and recoil, and it is invisible: the film is a solid box, so a cap
  driven below it simply hides inside it and all that motion is wasted. Anticipation is
  the half that shows. The pocket bulges under the weight, then lets go, and the eye
  reads the swell as pressure and the drop as failure. The rest of the drama is in the
  parts that happen to things you did not step on -- the shockwave through the
  neighbouring pockets, and the stagger that turns a knot of them into a crackle.
- **The bubble wrap sheet WRAPS the slab: six faces, not one.** It used to be a mat on
  the top, so from any angle but straight down the platform was a bare slab with a
  bubbled lid. Only the TOP pockets are rigged -- you cannot step on a wall or on the
  underside, so a bone there would be a bone that never moves, and leaving them off also
  means every remaining bone still collapses along plain -Z.
- **Every pocket has a flat COLLAR ringing it, and the reason is shading not shape.**
  The profile is already tangential at the rim, but a cap's rim vertices belong to cap
  faces ONLY, so their normals average the steep outer band and come out tilted while
  the film a millimetre away shades flat. Two different normals in the same place is a
  hard line and no amount of reprofiling removes it. The collar gives those vertices a
  second, flat neighbour to average with, and its outer edge is coplanar with the film.
  It cannot reach further than half the gap between rims without meeting its neighbour's.
- **Rings are bunched toward the rim** (`t = (r/RINGS) ** 0.72`). Spaced evenly, one
  chord spans the outer band, which drops 59% of the pocket's height over the last
  quarter of its radius and reads as a facet however smoothly it is shaded.
- **The side band is ONE loop walked by arc length, not four flat runs.** Each pocket
  takes its outward direction from the point it sits on, so the band carries round the
  corners. As four runs with the arcs cut off their ends it left 2.56 studs of bare film
  at both ends of every long wall. The spacing is nudged to divide the perimeter exactly:
  a loop is closed, so holding the pitch at precisely 2.0 leaves one odd gap where the
  walk meets itself, and that reads far worse than every pocket being 2% out of step.
- **Side pockets are the SAME size as top ones, and scaling them was a mistake.** The
  scale only ever applied to the height, never the radius -- so a wall pocket was the
  same width at a third of the height, and a shallow cap of a given radius reads as a
  WIDER circle than a full dome of the same radius. The walls came out looking like big
  flat discs beside the top's bubbles, which is the opposite of the intent. The cost is
  overhang: the wrap stands a full stud proud of the slab on every side, so a 16-wide
  platform LOOKS 18 wide while only 16 of it holds you up.
- **CORNER is capped by WRAP_OUT, and the generator asserts it.** The slab is a Part with
  hard 90-degree corners. A rounded rectangle offset by `w` from a square one contains
  that square's corner only while the radius is at most `w / (sqrt2 - 1)`, so rounding
  the film's plan means pushing it further off the slab first. Past the limit each corner
  grows a nub of bare slab poking through the wrap, visible from four angles and no
  others. Pockets are left off the corner ARCS for the same family of reason: one there
  would need its own normal per chord, and wrap pulled round a corner is stretched flat.
- **A cap's second in-plane axis is DERIVED, never passed** (`v = normal x u`). Rings are
  wound in order of increasing angle from u toward v, so the winding is correct only
  when (u, v, normal) is right-handed. Handing both axes in built three of the six faces
  left-handed -- the +Y wall, the -X wall and the underside -- and every pocket on them
  was inside out, which Roblox culls and Blender renders perfectly happily.
- **`meshPad` on a SkinnedSpec is the wrap's oversize**, total across both sides. A wrap
  legitimately stands proud of the thing it wraps, and bubble wrap's mesh is about a
  stud wider than its slab. It is declared so the import size check stays exact instead
  of being widened into something that no longer catches a genuinely wrong mesh.
- **BubbleWrap is the one OVERLAY rig.** Every other skinned mesh IS the platform, so
  `attachSkinnedVisual` hides the slab behind it. A bubble wrap sheet is 0.6 studs thick
  and lives inside the tile layer: hide the slab and the platform becomes a sheet of
  plastic floating over a four-stud drop. It is also the one material whose appearance
  already defines a separate `baseColor`/`baseMaterial`, which is the slab showing
  through as the thing being wrapped.
- **Superseded: bubble wrap as spawned Parts, and as CONTINUOUS tiles.** Both are gone.
  Spheres could not be it for three reasons no tuning reaches -- they sat ON the surface
  rather than being part of it, a Part scales instead of deforming so a "pop" was a ball
  shrinking rather than a dome flattening under a fixed rim, and there was no film
  between them. Closing the tile seams to make the tiles themselves act as the film was
  a step toward that and is now moot: the tiles are invisible sensors under the rig.
- **The butter's plan corner is REAL GEOMETRY, and it has to stay that way.** The
  surface is sampled on a plain rectangular grid, so for a long time the rounded corner
  existed only in the height field: `rim` fell to zero near the plan corners, but the
  material was still there, 0.38 studs tall out at (half_x, half_z). The wax band wraps
  a ROUNDED outline and those square corners sat 0.27 studs outside it, so bare butter
  showed at all four corners from every angle. `clamp_to_plan` projects those grid
  points onto the arc. It cannot be fixed from the wax side: the only band that encloses
  a rectangle is a square one, and squaring the band squares the lid with it.
- **A band shard that spans a corner must be SPLIT, not just densified.** Shards are
  fractured in (arc length, height) and mapped onto the outline, so a shard lying across
  a corner arrives as one flat plate that chamfers the corner off -- 0.29 studs inside
  the outline for a shard spanning a quadrant, against 0.02 of clearance. Following the
  arc along the shard's own outline is not enough, because the fan interior stays flat;
  `split_at_corners` cuts the shard at every corner sample so no FACE spans an arc.
  Measuring shard AREA finds nothing wrong and never could: every shard is present and
  the band covers the block exactly in (arc, height) space. The hole opens in the
  mapping, and only a view of a corner shows it.
- **The butter is aligned to its PEAK, not its average height.** `surfaceOffset` used
  `THICK + CROWN * 0.4`, but the crown and the mould ridges put the real peak 0.052
  above that -- so the ridges pushed up through the wax's underside and showed as a
  chevron pattern across an intact platform. It reads as the coating being dirty rather
  than as two surfaces intersecting, which is what makes it hard to spot. There is now a
  0.02 clearance so the two never touch.
- **THE WAX COATING IS A VORONOI-FRACTURED SKINNED MESH. Do not rebuild it out of
  Parts.** Three generations tried that and all three read as squares, for a structural
  reason rather than a cosmetic one: EXACT TILING WITH BOXES FORCES AXIS-ALIGNED
  RECTANGLES, because rotating a box breaks the tiling. Varying the sizes, mixing in
  diagonal wedges and partitioning globally all left every crack line parallel to the
  platform's own edges. Voronoi cells have edges at whatever angle their seeds dictate,
  and one mesh has no part boundaries to draw outlines of their own.
  Each shard is weighted RIGIDLY to one bone -- the opposite of the honey and slime
  rigs, where blended influences make a dent melt into the surface. A shard of brittle
  wax must translate and tilt without deforming, or a crack looks like the surface
  sagging. The renderer matches bones to cells by WORLD POSITION, since the fracture
  knows nothing about the sub-region grid.
- **Superseded: the coating was one part until it shattered.** Shards butted together always draw
  their own outlines: each has side faces, and where two translucent ones meet the
  transparency doubles, so a seam shows however small the gap is. That is what a field of
  separate parts looks like and no tuning removes it. At rest the coating is a single
  `WaxSheet`; the shards are hidden and non-colliding, and the first crack anywhere on
  the platform swaps them in. Shattering is per PLATFORM, not per cell -- a wax film is
  one skin, and cracking part of it would put a visible boundary between the broken
  region and the intact one, which is the seam problem again.
  Collision moves with visibility. Sheet and shards sit at the same height, so the swap
  does not move the player, but exactly one of them must ever be solid.
- **Wax shards are IRREGULAR, and a uniform grid is the failure mode.** `shardCell`
  splits a cell recursively into 7 rectangles, choosing what to split WEIGHTED BY AREA.
  Always splitting the largest drives every piece toward the same size, which is the
  uniform grid again by a longer route -- and a uniform grid reads as tiling, not
  cracking. Wax breaks like a thin chocolate plate: straight-ish lines, pieces of
  visibly different sizes.
- **Butter-wax is the one material with TWO visuals at once**, a skinned body and a
  shell over it. `buildSubRegions` was a single if/elseif chain, so a skinned platform
  never got its shell; the shell branch is now separate from the skinned branch.
- **Wax's drawn cracks are gone, and should not come back.** `addCrackNetwork` on wax
  was the best a flat overlay could do and it was carefully tuned -- pale, cool, low
  contrast, because high contrast turns any line into an object lying on the surface --
  but a SurfaceGui is unlit and has no depth, and depth is the whole point of a crack.
  The plate seams replace it: a gap needs no contrast trick to read, because it is
  darker for the physical reason that it is a hole with butter at the bottom. Soap still
  uses `addCrackNetwork` and still wants it.
- **SOUND IS PARTLY IN.** Seven events in `AudioService.SOUND_IDS_BY_EVENT` have uploaded
  takes: honey (2), butter-wax (1), kinetic sand (6), slime (1), soap (1), bubble wrap (3) and
  the creamy keyboard (4). The other fifteen are empty lists, so those materials are still
  silent: ice, jello soda, lamb's ear, foam, light switch, lego, charcoal, chocolate, clay,
  cloud, salt, lava, oobleck, buttons and snow. `SOUND_BRIEF.md` says what each one wants.
  The wiring is finished; this is upload and paste, not code. Do NOT use `rbxassetid://0` as a
  placeholder; Roblox retries it and logs a failure on every trigger.
- **Raise slime's ripple amplitude now that it has a rig.** `RippleProfiles.Slime` is
  still at 0.6, which was the ceiling for the per-tile fallback: edge-matched tiles at
  different heights tear a visible seam. The rig has overlapping bone influences and no
  such limit, so the wave can go considerably deeper. It has not been re-tuned since the
  rig landed because that is an eyeball call in game.
- **SOAP IS GRANULAR. Do not give it a tile mesh or a rig.** Both were tried and both
  failed for one reason: they are ONE piece of geometry per cell, so the only failure
  they can express is the whole cell vanishing at once. A rig cannot even do that --
  skinning stretches rather than breaks, and a 9-stud bone pull against a ~3.5-stud
  influence radius drew the surface into vertical sheets. Crumbling needs the pieces to
  exist BEFORE they break off, so every soap cell is built as two stacked 3 x 3 blocks
  of small cubes (`attachGranules`). Depth comes from LAYERS, not from taller cubes --
  deepen the cubes and they read as standing blocks instead of pressed cubes.
- **On a granular platform the CUBES are the floor.** The tile is a pure sensor
  (grown 0.25 upward so it still fires Touched once it no longer holds anything up) and
  the slab is non-colliding. With collision on the tile, the cubes under your feet could
  all be gone while a full-cell collider held you there until the server's dissolve timer
  fired -- that was the delay before falling. Anything that hides a cube MUST clear its
  CanCollide too, or it becomes invisible floor.
- **`R2_SoapBridge` is one plain 14 x 20 slab, and that is deliberate.** It used to be
  a tapered run pinching to an 8-wide waist, which read as an hourglass from above. A
  taper cannot round anything -- pieces have to stay about 5 studs long or the cubes they
  carry come out under half a stud -- so the shaping moved to the cubes: a rounded-
  rectangle test clips the outline, and the outer ring of the top layer sits 0.35 lower
  so the rim rolls off instead of ending in a vertical wall. The rim is by far the
  stronger cue; plan rounding only clips four cubes.
- **Chunk shape variants (planned).** Regular bar, square, flower, animal, a Minecraft
  item, and so on. Cost depends entirely on the material:
  GRANULAR materials are nearly free -- there are no size-locked assets, so an outline is
  just the test inside `attachGranules`; swap it for any other mask and the same loop
  builds a different shape.
  RIGGED materials (honey, slime) are the opposite: a rig cannot be resized, so every
  distinct silhouette needs its own Blender rig and its own `SKINNED_PLATFORMS` entry.
  Put shape variety on the granular materials first.
- **Never write a granule's appearance from the material default.** Restoring a decayed
  cell used to fall back to `Appearances.Soap.transparency` for any cube with no recorded
  value -- which is every cube that never broke off -- so half the bar drifted lighter and
  lost its variation each time you walked over it. Only cubes that actually broke are
  restored, and only to the exact value they were authored with.
- **Soap is NOT Glass, and must not go back to it.** It looked translucent whatever
  Transparency said, because under the high-fidelity lighting engine a Glass part
  genuinely refracts and picks up the skybox -- against open sky the bar went pale blue
  and read as ice. It is now opaque SmoothPlastic in soft rose, which also separates it
  from the pale lavender stable platforms: the material that drops you and the one that
  never does used to be within a few values of each other.
- **The crumble rate is derived, not tuned.** `Materials.Soap.dissolveTime` divided by
  the cube count, so the cell empties exactly as the server stops it being floor. Change
  either and it stays in step; hardcode an interval and it silently drifts.
- **`Soap_Tile.obj` is now unused** (`gen_tile_meshes.py` still builds it). Left alone
  rather than deleted, since it predates the granular rewrite.
- **Platform-wide soap deterioration.** Cells still crumble independently; a cell only
  starts when you stand on it. Spreading failure to neighbours is untouched.- **Soap deterioration.** Currently one tile dissolves at a time. The platform should
  progressively degrade.
- **Chunk form variety, second pass.** Done once (see below), but two chunks came out of
  it as the same hourglass: `C2_PaceToStable` and `C4_BubbleWrapToStable` differ only in
  material and in one rising. `S1_Straight` and `S2_Junction` are still rectangles from
  above by design, so their only variety is the shelf. None of this is worth retuning
  before it has actually been played.
- **Textures.** No PBR maps anywhere. Deliberately last: maps painted for one geometry
  approach are wasted if the approach changes.
- **Honey variants for 16x12 platforms.** The skinned rig is size-locked to 16x18
  (`P1_HoneyCorridor`). The honey sections of `P4` and `C1` fall back to per-tile meshes
  automatically, so both approaches are visible in one run.
- **A `Shared/Remotes.lua` module.** Several modules do blocking `WaitForChild` at require
  time, so correctness depends on script execution order that Roblox does not guarantee.
  This already caused one deadlock. Worth doing before adding more services.

## Picking this up cold

Read this file, then the auto-loaded memory (`manual-studio-workflow`,
`visibly-supported-geometry`, `flooded-halls-feedback`). The short version:

1. **Run `python blender/check_chunk_forms.py` before pasting anything.** Nothing syncs
   to Studio and there is no Luau interpreter here, so it is the only thing standing
   between a change and a Studio round trip.
2. **Render before handing a mesh over.** Every generator validates its own topology and
   prints the `SKINNED_PLATFORMS` entry it needs. Paste that; never measure a
   `surfaceOffset` by eye. Four separate bugs were caught this way, including a mesh
   floating 1.6 studs above its platform.
3. **When a visual complaint repeats, change the primitive, not the numbers.** Boxes
   cannot tile except axis-aligned. A jittered lattice cannot produce varied areas.
   Separate translucent parts always draw their own outlines. Each of those cost several
   rounds of tuning before the structure was addressed.
4. **Every deviation that looks arbitrary has a comment saying what was tried.** Read it
   before overriding it.
5. **For Level 4, run `check_halls.py` and look at `halls_plan.png`,** and end every change with
   the exact list of files to paste. Most "it is still broken" reports on that level were a
   paste or an import that had not landed.

## Reading the code

The expensive findings are written as comments where they apply, not collected here. If
something looks arbitrary, the comment above it explains what was tried and why it failed.
`DeformationRenderer.lua` in particular carries the reasoning for: cracks being a
SurfaceGui rather than parts, `ClipsDescendants` being ignored on rotated GuiObjects, GUI
elements being unlit and therefore unable to reflect, why `CanvasGroup` was needed and then
dropped, and the surface-GUI axis convention needing a transpose rather than a flip.
