# ASMR Platformer: handoff

Roblox game from a locked GDD: a 3D platformer where every platform is a tactile,
ASMR-inspired material (honey, butter-wax, kinetic sand, slime, soap, bubble wrap), with
template-based procedural level generation, chill/hardcore modes and a leaderboard.

It has grown well past those six. `MaterialConfig` now carries 28 material entries across 68
chunks, there are four levels plus a Sandbox, and players choose a run in a lobby rather than
being dropped into a hardcoded level. See **Levels and the lobby** and **The Flooded Halls**
below for the parts this file did not cover before.

Last updated: 2026-10-22. **Everything up to and including the ninety-second pass has been played in Studio (you).**
Built since, waiting for a test: the hundred-and-thirtieth to thirty-sixth passes, from your test of 2026-10-23 and its
video (**Your test of 2026-10-23**, first below); the hundred-and-twenty-third to twenty-ninth passes, from your test of
2026-10-22 (**Your test of 2026-10-22**); the hundred-and-seventeenth to twenty-second passes, from your test of
2026-10-21 (**Your test of 2026-10-21**); the hundred-and-fourteenth to sixteenth passes, the true ending (**Clocking in, and
his face**); the hundred-and-thirteenth pass, Hill House's people (**Mr Gale and Mrs Dunn**); the hundred-and-twelfth pass, Hill House's hall (**His key and his clock**); the hundred-and-eleventh pass, Hill House from the outside (**Hill House**); the hundred-and-tenth pass, the
cookie you asked for (**The cookie**);
the hundred-and-fifth to hundred-and-ninth passes, the rest of your notes of 2026-10-20: the shop made over with backgrounds and their crates, thin trails and auras with rings, Sky Pools' arches
and the lobby's look and feel (**The shop, the trails, the arches and the lobby**, first below); the hundred-and-first to
hundred-and-fourth passes, from the same notes:
sounds where they are, one font and every device, the back rooms, and what you say to people with the story under it
(**Your notes of 2026-10-20**, first below); the ninety-ninth and hundredth passes, one style on every screen and the
lobby as a promenade by the sea (**One style, and the lobby as a promenade**); the ninety-sixth to ninety-eighth,
every generated sound remade, the lobby's own sound, the shop's trails, auras and steps as modelled things and the
levels' water (**The sounds remade, the shop's things modelled, the levels' water**); the ninety-fifth, from your fourth test (the mouth's dark you can see in, and the drain under
the water: **What your fourth test found**); and the ninety-third and ninety-fourth, the camera checked shot by shot
and the butter sticks (**The camera, checked shot by shot**). Each round before them follows, newest first: what your third, second and first tests found (passes 92, 86 to
91 and 78 to 85), then the fiftieth to seventy-seventh passes (story mode the biggest of them) and the rest. What is
planned next (Hill House, then more worlds) is in `ROADMAP.md`.

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
  ProfileStore            (ModuleScript, by loleris: the saves; see The shop and the economy)
  Services                (Folder)
    BackdropService, BackRoomsService, BestTimeService, ChunkService, DeformationService,
    DiveFinaleService, EconomyService, FloodedHallsService, HubService, Interactables, SquishRoomService,
    LeaderboardService, LevelService, LightingService, PlayerStateService,
    SkyPoolsService, StoryService, SunkenCityService, TimerService,
    Townsfolk                                                         (ModuleScripts)
ReplicatedStorage
  Shared                  (Folder) -> 14 ModuleScripts: ChunkDefinitions, HallRoute,
                                      Keepsakes, LevelDefinitions, MaterialAppearance,
                                      MaterialConfig, PlanShapes, Poses, SeaRig, ShopCatalog,
                                      SkyPath, SubRegionGrid, SunkenPath, Types
  Assets/TileMeshes       (Folder) -> imported MeshParts, exact names below
  Assets/Backdrop         (Folder) -> horizon props, OPTIONAL (see below)
  Assets/Cosmetics        (Folder) -> OPTIONAL: the shop's things (meshes/cosmetics/, Cos_*), for CosmeticsClient
                                      and StepService; without them the particles and flat prints stand in
StarterPlayerScripts
  Bootstrap               (LocalScript)
  Services                (Folder) -> AmbienceService, AudioService, Cinema, CityShoreClient,
                                      CloudService, DeathService, DeformationRenderer,
                                      FloodedHallsClient, HubLeverService, HubVoteService,
                                      InputService, JournalService, Maw, OnboardingService, PauseMenuService, StepService, EmoteService, SquishRoomClient, DevPanelClient,
                                      ScreenEffects, SearchlightClient, SeaService, ShopService, SkyPoolsClient,
                                      StoryClient, SunkenCityClient, UIService, ViewModeService
ServerStorage
  Townsfolk               (Folder) -> OPTIONAL: your own character models for the people, named
                                      as they are (Sal, Pip, Maren, Dev, Okafor, Rudy, Attendant,
                                      Fisherman, Venn, Tobi, Barlow). The old name SunkenNPCs
                                      still works.
SoundService
  MaterialSounds          (Folder) -> OPTIONAL: the generated material takes (audio/materials/,
                                      audio/sheets/, and the keypad's audio/buttons/), imported and
                                      dropped in. Each Sound is played for the event its name starts
                                      with; a sheet (name_xN) is N takes, played by slot.
  StorySounds             (Folder) -> OPTIONAL: GateGroan, WaterRush, Siren, MawRumble, JawsShut,
                                      Heartbeat, SecretSting (audio/story/), for the scenes, and
                                      the endings' own 17 (audio/endings/: DiveBoard, DiveWind,
                                      DiveSplash, UnderwaterHum, ShoreChord, SlideRush,
                                      CloudWhoosh, SkimSlap, PoolPlunge, PoolsChord, WhirlRoar,
                                      DrainFall, CulvertWash, SunkenChord, FlumeRush, PlungeWind,
                                      HallsChord). Built-in sounds stand in where one will do.
  AmbienceSounds          (Folder) -> OPTIONAL: ShoreSea, RoofWind, PartyFar, HarbourNight,
                                      BathsHum, HoldDrone (audio/ambience/), the levels' beds.
  LobbySounds             (Folder) -> OPTIONAL: the lobby's own seven (audio/lobby/), played on each
                                      screen in the lobby; without them, the server's stand-ins.
```

`SunkenNPCs` (a ModuleScript in ServerScriptService.Services until the fourteenth pass) is now
`Townsfolk`: delete the old one after pasting the new one.

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
Whirl_Band1 ... Whirl_Band6   Whirl_Foam1 ... Whirl_Foam6   Whirl_Lip   (FBX, the Sunken City's whirlpool)
```

The `Whirl_*` thirteen are optional: without them (or with an old import, which SunkenCityService's `WHIRL_SIZE`
catches) the whirlpool is built of parts, as it used to be.

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
if the route, the chamber or the pool changed. For Level 2, run `python blender/check_skypools.py`,
and `python blender/plan_skypools.py` to see the result. For Level 3, run
`python blender/check_sunkencity.py`, and `python blender/plan_sunkencity.py` to see it.

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

### Clay and salt move material

Every other material answers a footfall on the cell you stepped on. **Clay and salt move material
into the cells around it**, and that is where their risk comes from. The rules live in the
DISPLACEMENT section of `DeformationService`; the numbers are `displacement`, `displaceSteps`,
`displaceFrom`, `displaceTilt`, `displaceLimit`, `sinkAfter` and `creepEvery` in `MaterialConfig`.
Standing still presses the cell under you again every `creepEvery` seconds. Both are still
PACE-slot chunks (P10, P11, P17): a steady crossing is safe, and stopping, doubling back, hugging
an edge and crowding are what break them.

- **Clay squeezes out.** A step sinks the cell (up to three presses deep) and pushes one unit of
  clay toward the nearest open side of the slab, split both ways down the exact middle. A cell with
  neighbours on both sides takes it as a ridge; an edge cell takes it as a lip that bulges out and
  droops over the side, shedding chips one squeeze before it goes. At three the lip TEARS OFF (a
  clay slab swings out on a hinge and falls) with whoever is on it, and the next cell in becomes
  the edge. Stepping on a ridge carries its clay on outward. Ridges and pits are physical: the
  collider follows 80% of the shape.
- **Salt sits on brine.** A step packs the cell (lower, firmer, and faster: walk speed goes from
  0.88 back to 1.0 as it packs). From the SECOND packing on, the brine is squeezed sideways into
  the unpacked crust around it: one push cracks a plate, two lift and tilt it (dark cracks,
  bubbles, the collider tilts), three sink it. A tilted plate breaks under a foot and sinks on its
  own after 8 seconds. Standing still for 2.4 seconds leaves you on an island of packed salt. A
  sunk plate is the bed funnelling down with bubbles and pieces of crust going under -- there used
  to be a translucent blue-grey "brine" part closing over the hole, and in play it read as dark blue
  squares floating beside the salt, so it is gone.
  Pushing from the first step broke a plate under the second foot of an ordinary crossing -- a
  player walking with a foot either side of a cell line strains the next cell from behind and
  from beside -- which `sim_displace.py` (scratch) found from the service's own rules.
- **A taller sensor.** A ridge or a heaved plate lifts the collider above the thin tile that
  senses footsteps, so every clay and salt cell gets a `Reach` part (1.8 below to 2.6 above the
  surface) created at registration, and that is what fires Touched. No template rebuild needed.
- The renderer draws both from the numbers each update carries (`depth`, `push`, `lean`,
  `cause`), in one section of `DeformationRenderer` with its own function (see "Luau's 200 locals"
  under Open items). A `push` update is a neighbour's weight arriving and plays no footstep.

### The keypads: three switches

The three button chunks (P12 Button Pad, P14 Dense Keypad, P15 Domed Keypad) are arcade keypads.
**`ChunkBuilder` changed, so clear both chunk folders before playing** (see the run ritual).

- **Every button is three parts**: a dark `CapBezel` that never moves, a see-through `Cap`, and a
  Neon `CapLed` core inside it. Cap and core travel together, about flush with the bezel, where the
  core still shows. Between presses every core breathes on a slow wave that runs along the route.
- **Every cell is a switch**, written on the tile as the `Switch` attribute by `switchFor`, and all
  three do something. CLICKY (cyan) is x1.22 walk speed and a SURGE that carries off the pad for
  1.4 s. Three clicky presses in a row, each within 0.8 s of the last, is a COMBO: x1.34 for 2.4 s
  and the whole pad lights up in a wave from your foot. The pad and the dome run a clicky lane down
  the middle (over the summit on the dome); the dense keypad braids it, so weaving collects every
  one. Numbers: `switchSpeeds`, `surgeLinger`, `comboAt`, `streakWindow`, `comboSpeed`,
  `comboLinger`. Violet and pink no longer cost you a surge (pink used to be x0.88 and cleared it),
  and a press never lowers a surge already running: it keeps whichever is bigger and lasts longer.
- **LINEAR (violet) is a CAPACITOR.** Each violet press stores a charge (up to `capacitorMax` 3,
  held `capacitorHold` 4 s from the last one); the next clicky press spends them all, +0.06 speed and
  +0.5 s per charge (`dischargeSpeed`, `dischargeLinger`), capped at `surgeCap` x1.6. The charge arcs
  up out of the violet button into you and you carry a violet crackle and glow that grows with each;
  the discharge arcs out of you into the cyan button with a violet flash wave and a combo zap.
  `sim_round4.py` (scratch): three violet then one cyan is x1.40 for 2.9 s, level with a straight
  circuit (x1.42 for 3.2 s); weaving violet into the dense keypad's braid makes x1.48 for 3.7 s.
- **TACTILE (pink) is a SPRING.** A pink button under you raises your jump to `springJump[1]`
  (x1.45 height) through JumpHeight and JumpPower, like the Needoh. Jump off pink and land on pink
  again within `springChain` (1 s) and it is a BOUNCE: x1.8, then x2.2. Walking off, landing on
  anything else, or the window closing puts the jump back. A launch is announced as `cause` "spring"
  with the level in `charge`: the caps fly up and ring down, a pink flash wave, sparks, a pink streak
  under the jumper, and the release sound at full voice. The server calls an exit a launch when the
  root is rising faster than `SPRING_RISING` (6) or is `SPRING_ABOVE` (6) studs over the button;
  `sim_round4.py` checked every jump level with the exit grace and a late audit, and that walking up
  onto the dome's raised violet cells (4.75 up at most) does not count.
- **Each switch feels different**: clicky snaps down, rings its bezel with light and flashes a
  point light; linear is smooth; tactile stops at a bump part way down and again on the way up.
  Every press ripples light to the buttons around it.
- **A CIRCUIT**: a clicky press in every row of the pad inside one streak. x1.42 for 3.2 s
  (`circuitSpeed`, `circuitLinger`), and the pad OVERLOADS: two waves of light, two flash waves,
  sparks off every clicky button and a camera shake for the player who did it (through
  `Humanoid.CameraOffset`, which nothing else uses). A combo gets a smaller version.
- **Electricity**: every clicky press throws sparks and an arc jumps to the next clicky button
  along the route, which flashes -- where to put your next foot.
- **Sounds.** `audio/gen_button_sfx.py` synthesises the keypad's set (numpy and scipy, no Blender)
  into `audio/buttons/`: 4 clicky, 3 linear, 3 tactile, 3 release, 2 combo, 2 circuit. Every sound
  is a pitch-dropping punch under an FM zap with a crackle tail, low-passed and tapered to silence.
  **They are not uploaded yet.** Upload each WAV and paste its id into `SOUND_IDS_BY_EVENT` in
  `AudioService.lua`: clicky -> `buttonClick`, then `buttonLinear`, `buttonTactile`,
  `buttonRelease`, `buttonCombo`, `buttonCircuit`. Until then the keypad falls back to
  `buttonClick`, then to the keyboard's thock, pitched up a pentatonic scale along the route; once
  the zaps are in, they rise gently instead. `AudioService.playSfx` now takes an options table
  (`pitch`, `gain`, `event`, `force`) and `AudioService.hasTakes(event)` exists.

### The Needoh squeeze

It has its own sound since the twenty-first pass (`needohSquish`; it used to borrow clay's files).

The mini jumps are gone (`microBounceHeight` and `bounceCooldown` removed). Walking on a Needoh bed
is just soft. **Standing still squeezes it**: after `chargeAfter` (0.25 s) the hollow deepens over
`chargeTime` (1.1 s) while the bed swells around it, and at full squeeze it shivers and glows teal.
Jumping out of it jumps up to `chargeJump` (2.2x) the normal height -- the server raises JumpHeight
and JumpPower in four steps and restores both the moment the player leaves the bed. Letting go
pops the hollow back past its footprint. Charge reaches clients as `charge` on the cell's update.

### The occupancy audit

TouchEnded is not guaranteed, and a cell that never hears it keeps a ghost occupant: buttons held
down with nobody on them (the most likely reason for a keypad whose middle buttons were missing in
a screenshot), a clay cell squeezing itself, a Needoh charging for nobody, walk speed stuck at the
last material's. Every 0.25 s `DeformationService` now checks each occupied cell's occupants are
still within 2.5 studs of it (and 9 above or below), and walks anyone who is not out of the cell.

### Charcoal: the grill that catches

Charcoal no longer snaps on the second step. A foot on a cold coal lights it (`fire` =
"smoulder"); after `igniteAfter` (0.9 s) it burns, with glowing cracks on the collider (see Growing
cracks below), a flickering light, sparks and smoke; `spreadAfter` (0.8 s) into burning it lights each cold
neighbour on a `spreadChance` (22%); `burnFor` (1.9 s) after it caught it is ash and gives way. A
foot on burning coal takes `stompBurn` off it and kicks up embers; burning coal is `hotSpeed`
(x1.15). A fresh coal settles into an ash hole after `regrowAfter` (5.5 s), through the new
`restoreCell`. `sim_round3.py` (scratch): a crossing at a walk is always safe and burns about 7
of the 20 coals, one player or two never burns the whole grill, standing still on it drops you
at 3 s, and following someone along the same line 3 s behind drops you.

### Oobleck: stamp it hard

Oobleck no longer runs a dissolve clock. Every player on the pool WADES: `wadeStill` (1.1 a
second) standing or under `wadeSlow` (8 studs/s), `wadeMoving` (0.45) moving, dragging speed by up
to `wadeDrag`, and a full wade gives way under them (`healAfter` 3.5 s to fill back in). A landing
faster than `shockFrom` (28 studs/s, remembered for 0.35 s because the landing itself zeroes it)
hardens the whole pool for `shockTime` (1.3 s): every wade drains, and the pool pops up flat in a
wave from the landing. **No cracks on oobleck**: they were removed on request, it is a liquid. Walking across at full speed gets you over with a visible wade,
stopping puts you under in about a second, hopping keeps you up indefinitely -- and one player's
landing is a floor for everyone. Oobleck cells get the tall `Reach` sensor, like clay and salt.

### Clay: the sag was tried and reverted

For one round an overloaded clay lip sagged for 0.65 s and then broke into rounded lumps. The user
preferred the version before it, so it is back: the lip tears off at once and swings out as one slab
on a hinge (`peelClay`, `tearClay` without `CLAY_SAG`). Do not bring the sag or the lumps back.

### Growing cracks: soap and charcoal

`Fissure` in `DeformationRenderer` (one table, after `canvasUV`) draws cracks that GROW instead of
appearing whole in random places. A crack starts at the foot that made it (`Fissure.footOf`: your
own foot, or another player's root), fans inward if that is near an edge, and runs out a 0.42-stud
segment at a time; a surface holds 48 segments. It draws on the same `crackGuis` overlay as
`addCrackNetwork`, so `clearCracks` still clears it. Calls: `grow`, `extend` (run the live tips on),
`widen`, `tint`, `glow` and `flare` (breathing brightness, unlit overlays only), `shatter` (a piece
of the surface falls out and takes its cracks, the rim opens up) and `heal` (fade and remove).

- **Soap**: the first step on a cell starts 3 cracks from the foot; a later step runs those on and
  adds a short pair under the new foot, instead of drawing nine more on top every time (it used to,
  which is how a busy cell became a scribble). They run on with every cube that falls, every top
  cube takes the cracks over it, and they fade as the bar mends. Numbers: `SOAP.CRACK_*`.
- **Charcoal**: dull red hairlines creep out from where the coal was lit, or in from the side of the
  burning coal that spread to it, over the ignite time; bursting into flame runs them on, opens them
  and turns them orange with the glow breathing; white-hot 62% of the way into the burn as the last
  warning; ash grey as it breaks. A stamp on burning coal splits new cracks out and flares them.
  Numbers: the crack fields in `NEW_MATS.Charcoal`.
- Salt, ice and wax are unchanged.

### Nothing stays broken: every hole fills itself in

`Constants.REGROW_DURATION` (30 s) is the promise: any cell that gives way comes back that long
after it broke, and `decayDuration` is capped by it so dents go too. Clay and salt drop from 600 s
(the whole session) to 30. Materials with their own faster return keep it: charcoal `regrowAfter`
5.5 s, oobleck `healAfter` 3.5 s, bubble wrap on its decay timer.

- **Why.** A clay lip tearing off at the one place a jump needs it made the level unfinishable for
  the rest of the run, and the only way on was to restart: a punishment for playing with the
  material the level is made of.
- **Server.** `collapseCell` stamps `cell.regrowAt`; the heartbeat calls `restoreCell` when it is
  due and `occupied(cell)` says nobody is in the hole (a repair under a falling player would push
  them out of a fall they have already lost). `restoreCell` now also gives the SLAB back -- its
  collision, and its visibility, which bubble wrap needs -- once that platform's last hole closes.
- **Client.** `revive` in `DeformationRenderer` is generic and runs for every material before the
  material's own pristine branch: it cancels the collapse's tweens, clears marks and cracks, rises
  the surface and its collider back to rest with a little overshoot, and puffs. Three materials had
  no picture for the way back at all (kinetic sand, solid chocolate, salt) and simply stayed as
  holes while the server counted them whole.

### The ending: a banner in the level's own language

Each level's completion banner now carries the SHAPE of its level as well as its colours: the panel
takes the level's own gradient, the vignette its colour, and a MOTIF is drawn inside it with one
thing moving. City Shore gets a sun going down behind a horizon; Sky Pools cloud along the bottom
edge and a ripple under the headline; the Sunken City caustics drifting over a panel that is nearly
black; the Flooded Halls tile and a dado line drawing itself along the wall. All of it is frames and
gradients -- nothing to import -- and `check_skypools.py` holds all four motifs in place.

### The ending: no blackout, a banner per level

The dive used to fade the screen to black at the splash. That threw away the best thing in the
level at the one moment worth watching and left a small grey banner alone on an empty screen. The
fade is gone from Bootstrap's dive callback (`ScreenFade` stays wired; nothing fires it), and
`UIService.showCompletion` carries the ending instead:

- `COMPLETION_LOOKS` is a look per level: its name, its accent colour, the panel's tint, and a line
  about what you just did ("You made the dive", "Down the flume"). Anything unlisted falls back.
- The banner rises 24 px as it fades in, the eyebrow, headline, rule and numbers arrive on four
  beats inside half a second, one sweep of light crosses the panel, and the run's time sits in mono
  at the right. Hardcore and chill colour the mode line.
- A VIGNETTE instead of a blackout: two gradient bands darken the top and bottom of the screen
  while the banner is up, so it reads against the sea with the level still playing behind it.
- `check_hub` gates the reverse of what it used to: a fade to black re-added at the splash now
  FAILS, and the dive's own callback must still call `finishRunFor`.

### City Shore, second version: a pastel beach city

A screenshot of the first version showed what it amounted to from the level: pale boxes in a pink
wash, and white eggs floating in front of everything. `BackdropService` builds something else now
(BACKDROP_VERSION 5, so a saved backdrop is replaced on the next run):

- **The composition turns on the sun.** `sunBearing` reads `Lighting:GetSunDirection()` at build
  time (the level's palette is applied first, in Bootstrap) and the city's centre line faces away
  from it, so every tower is lit on the side you see and the sun sets over open water.
- **A crescent of land**, 224 degrees round, from the bay's beach at 1150 out to 6000: a beach
  ramping out of the water (WedgeParts, front toward the level), a promenade, and flat ground, in
  4-degree slices of one-colour SmoothPlastic, so where slices overlap there is nothing to fight.
  Harbour walls run straight out to sea at both ends. The first version curved the coast away into
  headlands, and `plan_cityshore.py` showed the slices stepping out by hundreds of studs there --
  a staircase with sea between the treads -- so the coast is one radius all the way round.
- **The beachfront**: about twenty deco hotels (pastel blocks, white eyebrow ledges, a fin and a
  mast) facing the bay behind the promenade, and palms along it sized from the palm mesh.
- **The city**: 56 towers in three bands behind the hotels, on land, one in three a dark glass
  curtain wall with light mullions; twelve parks; the facades. No drowned towers and no collars.
- **The water**: the aquapark in the bay from 800 to 1080 -- clear of the dive's landing circle,
  which reaches about 714 from the middle -- smaller than before; float rings and lane ropes on the
  water; the giant objects and the sandbars out on the open sea only.
- **Removed**: the cloud banks (500 opaque balls: the eggs), the vapour (126 translucent banks
  between the level and the water: most of the pink soup; CloudService already returns when there
  is no Clouds folder), the always-built primitive scatter and every primitive fallback (the white
  ball and the glowing lamp), and the colonnade. A prop that has not been imported is now simply
  absent.
- **The air**: the cityShore palette is density 0.2, haze 0.45, offset 0.25, a pale gold horizon.
  The pink came from a pink horizon colour at high density and haze.

### The keypads already come back

Every button springs back up the moment you step off it (the release on `decaying`), and the cell
goes pristine two seconds later; nothing on a keypad can collapse, so the 30-second repair never
applies to one. Charges run out after four seconds and a spring when you land anywhere but pink.

### City Shore has its own light

`LightingService.palettes` now carry the sun, exposure, ambient, bloom, rays and grade as well as
the sky, and `Bootstrap` applies the palette named by the level's `backdrop` when a run starts.
That had to move out of boot: the lobby sets the atmosphere for the whole game while it builds the
room (HubService), so anything applied earlier was overwritten -- which is why City Shore has been
running under the room's haze (density 0.32, haze 1.6, lilac decay) all along.

- **cityShore**: ClockTime 16.9, a deeper blue overhead falling to warm amber at the horizon,
  density 0.28 with haze 1.3 (less than the room's, more than the default), glare 0.6, a larger sun
  (`sunSize` 18) because a low sun is in frame on the dive, slightly stronger bloom and a warmer
  grade. A low sun also gives the towers a lit face and a shadowed one.
- **lobby**: HubService's own numbers, mirrored, so the room gets its air back when the last runner
  leaves. If the two ever disagree, HubService built the room and this is the copy to correct.
- Small steps on purpose: these are a first pass over the level's look and meant to be tuned by eye.

### Faster to give way, faster to fall

- **Every collapse under your own character drops you at once**: the renderer sees the cell go,
  turns off its collider locally, puts you in free fall at 34 studs/s down and adds 1.1 g of extra
  weight for 0.55 s (`NEW_MATS.Fall`). No more standing on a collider that is waiting for the
  server's CanCollide to arrive.
- **Clocks shortened**: soap 2.5 -> 1.9 s, kinetic sand 3.0 -> 2.3, chocolate 5.0 -> 3.8, snow
  7.0 -> 5.5, cloud 1.6 -> 1.15 (and its visual sink rate raised to match). Step counts unchanged.
- **Collapse animations faster**: sand 0.5 -> 0.26 s with less stagger, snow 0.35 -> 0.18, melting
  chocolate 0.45 -> 0.24, sinking salt 0.9 -> 0.45, and cloud now actually drops out in a burst of
  vapour when it gives way (it had no picture for that at all).
- **Slabs under any hole-opening material no longer collide** (`ChunkBuilder`: step counts,
  displacement, wading and embers join the dissolve clock), and a re-inflated bubble wrap cell
  now gets its floor back -- it used to look whole and let you fall straight through.

## Your test of 2026-10-23 (hundred-and-thirtieth to thirty-sixth passes, 2026-10-23)

Everything in your message, the red screenshot, the clock screenshot and the video with them. How each is done is mine
**(suggested)**. Not played yet.

- **Lobby sounds in the levels (130)**: with the lobby's own sounds not imported, the server's stand-ins (the engine's
  one splash, over and over, for the sea, the wind and the breakers) played everywhere at once and followed you into
  every level; only the back rooms hushed them. Now every sound the lobby makes goes quiet the moment you are in any
  level, and the stand-ins are played from the lobby itself, falling off with distance (full near, gone by 260 to 320
  studs), as the fountain's own already did.
- **The hardcore clock (130)**: never up in Chill (a hardcore run put it up and a Chill vote left it there, still
  showing that run's time). In Hardcore, press it and it folds down to a small round stopwatch in its corner; press that
  and it opens again.
- **Walking during scenes (130)**: the shop and the welcome switched your controls back on as they closed, even in a
  scene. While a scene has the camera now, moving and jumping go nowhere whatever else does, and the prompts ("Look",
  "Talk") are put away until it ends.
- **Leaving to the lobby mid-scene (130)**: every scene ends at once when the lobby takes you, its camera, bars and
  sounds with it (the songs and chords it kept too), and each level's own scene puts its things away; the Sunken City's
  ride had gone on setting you along its culvert.
- **Out of the way (130)**: when you stand between a scene's camera and what it shows (Locker 3: your back filled the
  picture), you take a step aside to whichever side has room and turn to look at it. Every secret's scene does this.
- **The crowbar's last shot (130, the red screenshot)**: the look into the bricks' hole was down at the sill, all
  bricks; it looks into the hole from above now, at the letter.
- **Thought bubbles (130)**: they popped up and away instead of fading, which left an empty bubble over your head.
- **The Sunken City's fall (131)**: hit like the dive. A jolt and a burst of the whirlpool's water as it takes you, the
  speed coming on as it drags you round, a flash and a burst of water as it pulls you under, the picture shaking and
  the lines streaming down the shaft, a hard landing in the sluice in white water; a wake off you all the way down the
  culvert and a splash where it sets you down. Nothing through the walls: the alongside shot is kept in from the
  culvert's ribs (it was pulled into your hair), you no longer turn so far that your head goes into the bricks, and the
  station's camera never passes through a pump or a pillar.
- **The mouth (132)**: longer (thirteen and a half seconds, not eight and a half). The jaws creak shut, slam with
  everything (the roar, the impact, the shaft shaking) and crunch down twice more before the dark. Down its throat: its
  heart squeezes the walls in and flares its light on every beat, wet streaks rush up past you, the picture rolls and
  shakes, you think "Let me OUT!", and it heaves you out. The fall out of the flume starts with a jolt and shakes all
  the way down.
- **The back rooms' catch (133)**: you could not tell what it was: his face was made of flat boxes, a stud from a
  narrow lens. Now, after the lights die: side on, you and him folded down over you, his arms coming round you, and you
  think "What IS that?!"; then over your shoulder his round blank head, at a size you can read, splits open onto the
  fangs and the red light; it lunges; black. Three and a half seconds, not two; the server waits for the black.
- **The Flooded Halls (134)**: galleries down both walls, between the tiled dado and the windows, where spectators
  watched from: a timber deck on iron brackets let into the wall, a cast-iron railing with lifebuoys on it, benches
  along the back; the baths' enamel signs on their fronts (CORPORATION BATHS, NO DIVING, DEEP END, BATHS CLOSE AT
  MIDNIGHT, and more); and lamps hanging on chains over the walkway, each with a real light, failing behind you with the
  roof lights. They stop either side of every arch.
- **The shop (135)**: a sunburst turning slowly behind every item in its colour, a sheen sweeping across each card now
  and then, and a price you can pay breathing gently.
- **The lobby (136)**: the level windows were tinted glass, black slabs from the deck. Each carries a painted postcard of
  its place: the Siren Tower against the sun and sea, the Sky Pools' terraces in the clouds, the Sunken City's roofs
  under the whirlpool, the baths' arches, Hill House on its hill, the story's five skies. Dimmed behind the boards while
  a level is locked, brighter when chosen.

**Checked**: `check_story.py` (you held still and the prompts put away while a scene has the camera, every scene
ended when the lobby takes you and each level's cleanup called, the step aside, the thought's pop, the kept sounds let
go; the lobby's voices from the lobby itself, falling off, and hushed in every level; the catch side on, his round head
whole and yours hidden, three and a half seconds and the server waiting for it); `check_backrooms.py` (the lobby
hushed there, his face); `check_halls.py` (the mouth's slam with the impact and the shake, the galleries on their
brackets, the enamel signs in the town's print, the lamps on chains failing with the roof's); `check_shop.py` (the
sunburst, the sheen, the breathing price); `check_hub.py` (a postcard in every window, dimmed while locked);
`check_shots.py` (the culvert's alongside shot, the bite to the crunch and the throat after it restated; storyboards
redrawn); `roblox_enums.py` (`PlayerActions`, `DominantAxis`). `pass130.py` 14 of 14, `pass131.py` 9 of 9,
`pass132.py` 11 of 11, `pass133.py` 8 of 8, `pass134.py` 7 of 7, `pass135.py` 6 of 6, `pass136.py` 3 of 3; ten anchors
in the older suites moved to the lines as these passes left them. The full run after it: 129 suites, 2280 of 2282
caught, src, the Blender scripts and the sound generators put back byte for byte. The two it missed were rules made
too easy: the longer mouth let pass 92's "your face too brief" through (its replacement now breaks the beat), and the
catch's hidden head was looked for on a line written twice (the rule takes the one that hides his head now); both
suites rerun, 29 of 29 and 8 of 8.

## Before you test in Studio (passes 130 to 136)

**Paste**
1. The Luau: if you pasted `passes_123_129`, these are all that changed since (`SINCE_PASSES_123_129.txt` in the zip):
   **Shared** `SunkenPath`; **Server** `Bootstrap`, and Services `BackRoomsService`, `FloodedHallsService`,
   `HubService`, `Interactables`; **Client** Services `AmbienceService`, `Cinema`, `CityShoreClient`,
   `FloodedHallsClient`, `HillHouseClient`, `ShopService`, `SkyPoolsClient`, `StoryClient`, `SunkenCityClient`,
   `UIService` (16, none new).
   `python tools/paste_list.py` lists the same sixteen (your last `--mark` was after 123 to 129); then `--mark`.

**Import (UPLOADS: none)**

**Then play**
2. The lobby: walk away from the fountain (it fades), look at the level windows; start a level and listen (no lobby).
3. A hardcore run: press the clock (it folds); vote Chill after it (no clock).
4. City Shore: the bricks with the bar (the last look into the hole). Try to walk during a scene (you cannot).
5. The Sunken City: the whirlpool to the station; then leave to the lobby during a scene (everything stops).
6. The Flooded Halls: the galleries, the lamps; Locker 3 (you step aside); the mouth and its throat.
7. The back rooms: be caught. The shop: hover the tiles.

## Your test of 2026-10-22 (hundred-and-twenty-third to twenty-ninth passes, 2026-10-22)

Everything in your message and the video with it, every point. How each is done is mine **(suggested)**. Not played
yet.

- **The honey steps the wrong way round (123)**: Blender's modelled prints face back along the way you walk; each is
  turned a half turn about the ground now (`StepService`, `MESH_TURN`).
- **The fountain's bubbles (123)**: they were Glass, dull grey-blue balls against the sky. A soap film now: nearly clear,
  a faint colour each, a glint of the sun on it, blown from just over the water and drifting up slowly.
- **Talking again after the second run (123)**: what you have said is held by the person you said it to and made afresh
  each level, so every run their topics come back; what you learned stays in your save, and a topic you have never
  said is marked **New**.
- **The words between you and them, styled (123)**: each bubble has the speaker's name on a tag in their colour, a light
  across it and a shadow under it, and is written out a letter at a time; your choices have the person's disc, lift off
  their shadows with an arrow on the one you are on.
- **The shop's icons covering their names (123)**: an icon is held by its middle and swells evenly, measured to stay
  inside the gap over its name; the names and blurbs are bigger. **Arrow keys** change tab, as L1 and R1 do.
- **Locker 3 (124)**: lockers stand side by side and every prompt came up at once; only the one in front of you shows
  now. Inside, the close look backs off the locker's own width, so the coat is seen whole by its lamp, with brass
  buttons, a pocket and the note in it.
- **The monster scene in the Flooded Halls (124)**: you see the mouth and think "Is that... a MOUTH?!"; it bites, and the
  camera goes down its throat with you, turning over through its ribs; it spits you out into the Gate Chamber's sump,
  and you come up thinking "It... spat me out?".
- **The back rooms' catch (125)**: he stops and folds down over you on every screen, his knees giving, his arms round you
  and his head at yours; your screen goes from beside you to his face in front of you, bigger, the fangs a hand long and
  lit, splitting open; he lunges; black. The server waits for the black before the lobby.
- **The Sunken City's whirlpool from inside (126)**: under the water the picture swims (a slow roll and the lens
  breathing, `Cinema.waver`), soft with a little blur, the water thick and sea green with shafts of daylight slanting
  down round the throat and silt and bubbles going by, so it never reads as a thing hanging in the sky.
- **Oobleck's sound (126)**: one sheet of four takes of its own (`audio/sheets/ooblSquelch_x4.wav`): a muffled thup
  as it goes firm under the step, a slow creamy sink, thick blorps coming up through it and a soft sticky suck as the
  foot comes away; a quick step, a long sink, a stamp that stays firm, and one that holds on. The four old squelches are
  retired.
- **The Sky Pools' song (127)**: the music cut out partway down was the party heard through a wall. Now the party's own
  song plays in full over the slide (`PoolsSong`: the same four chords, the felt piano and strings, a soft kick and bass,
  then the tune), started so far in that its last chord lands with you in the pool; the pool's chord only stands in
  without it. A sound kept past its scene now plays out instead of being cut at twenty seconds.
- **Seeing yourself in Sky Pools' ending (127)**: the four seconds of empty sky in the cloud are you now, the camera
  riding close behind and over you, the cloud thinned round you on your screen and wisps streaming past; the wide shot
  under the cloud is short; the landing is close, easing in on you in the pool.
- **Hill House (128)**: no grass in the hall (filling ground over the grass left the top cells grass; each cell is
  changed outright now). Your camera can no longer go up through the ceiling (the upstairs floor is solid) or out
  through the windows (while your head is in the hall, the camera is kept inside its walls). The key's scene is shot
  again: in front of you and to one side as you take it, then over your shoulder as you turn to his clock, the whole
  clock in the picture, and you start when it ticks; you reach the key at your chest, hold it there, and carry it low
  to the door.
- **The bricks and the bar (129)**: you step up and swing the bar into the wall three times, its tip landing on the
  bricks each time, chips and dust flying out and the wall shaking, a dull knock each blow (`BarStrike`); on the last
  the patch bursts out, tumbling onto the floor (`BrickBurst`). The "Look" prompt stays at the hole.
- **City Shore's finale (129)**: the shot "covered by a plane" was Maren's: the camera was behind her looking down at you,
  and she stands thirty studs back from the tip, so it was the deck's floor. It is her reaction now, turned to the
  board and starting as you go. **The hit**: the camera holds at the surface a moment as you go in, the spray going up,
  foam racing out over the water, the flash and the jolt harder, then goes under after you into a burst of bubbles.
- **The butter (129)**: the wrapper was see-through (0.3), so it read as a glass case with a block of butter standing in
  it and the water showing through its edges. It is waxed paper now, cream and all but opaque; the butter shows where
  it cracks.

**Checked**: `check_shop.py` (the prints turned round, the arrow keys, the icon's swell measured against the gap
over its name); `check_hub.py` (the bubbles a film with a glint, blown low and rising slowly; the new sounds looked
for); `check_story.py` (talk afresh each run, the bubbles dressed and written out, the choices, one locker of a row,
the coat, the mouth and its throat, his catch and its beats, the water under the whirlpool, the song and kept sounds,
the strike and its chips, Maren, the hit held, the butter's paper); `check_skypools.py` (the ride in the cloud replayed,
nobody on screen for no more than a few seconds); `check_hillhouse.py` (the cells changed to ground, the solid
ceiling, the camera kept in the hall, the key's scene); `check_shots.py` (every new shot restated and measured: you in
the cloud, the landing close, the key and the clock, Maren's reaction, the hit; storyboards redrawn);
`check_audio.py` (the song, the strike, the burst and oobleck's sheet at their families' levels). Passes 124 to 126
had no rules of their own until now; they do. `pass123.py` 17 of 17, `pass124.py` 10 of 10, `pass125.py` 7 of 7,
`pass126.py` 5 of 5, `pass127.py` 11 of 11, `pass128.py` 11 of 11, `pass129.py` 23 of 23; fourteen anchors in the older
suites moved to the lines as these passes left them, and one rule tightened (a count of the two-shot's resets, which the
strike scene had made too easy). The full run after it: 122 suites, 2224 of 2224 caught, src, the Blender scripts and
the sound generators put back byte for byte.

## Before you test in Studio (passes 123 to 129)

**Paste**
1. The Luau: if you pasted `passes_117_122`, these are all that changed since (`SINCE_PASSES_117_122.txt` in the zip):
   **Shared** `Conversations`, `Poses`, `Style`; **Server** `Bootstrap`, `ChunkBuilder`, and Services
   `BackRoomsService`, `HillHouseService`, `Interactables`, `Townsfolk`; **Client** Services `Cinema`,
   `CityShoreClient`, `FloodedHallsClient`, `HillHouseClient`, `LobbyLife`, `Maw`, `ShopService`, `SkyPoolsClient`,
   `StalkerClient`, `StepService`, `StoryClient`, `SunkenCityClient`, `TalkClient` (22, none new).
   `python tools/paste_list.py` lists everything since your last `--mark` (all of 93 to 129); then `--mark`.

**Import (UPLOADS: 4)**
2. `audio/sheets/ooblSquelch_x4.wav` into **SoundService.MaterialSounds**, and delete the four old `ooblSquelch_1` to
   `ooblSquelch_4` there.
3. `audio/endings/PoolsSong.wav`, `audio/story/BarStrike.wav` and `audio/story/BrickBurst.wav` into
   **SoundService.StorySounds**.

**Then play**
4. The lobby: the fountain's bubbles; your prints in honey toes first; talk to Mrs Venn, finish a level, talk again
   (her topics back, the new ones marked); the shop's icons on hover, and the arrow keys.
5. City Shore: the Siren Room's bricks with the bar; the dive (Maren, and the hit). A butter platform.
6. Sky Pools: the slide (you in the cloud, the song to the end, the landing).
7. The Sunken City: the whirlpool from inside. The Flooded Halls: Locker 3, and the mouth.
8. Hill House: turn your camera hard about in the hall (it stays in), and take the key.
9. The back rooms: be caught.

## Your test of 2026-10-21 (hundred-and-eighteenth to twenty-second passes, 2026-10-22)

Everything in your message with the three screenshots, and what you answered after. How each is done is mine
**(suggested)**. Not played yet.

- **Sounds in the lobby (118)**: they were the soap bubbles off the fountain, popping aloud as you walked through them.
  Only a bubble you tap is heard now; one you walk into, or one that bursts by itself, pops in silence. (A step sound
  pack you have on from the shop also plays in the lobby and the squish room, never on a level: take it off in the
  shop's Sounds tab if that is what you heard.)
- **The see-through chunks in Sky Pools and Hill House (118)**: Roblox draws see-through things back to front by their
  middles, so the huge see-through cloud puffs, their undersides and Hill House's mist sheets, whose middles were
  nearer, were drawn over the honey, slime and soda and hid them. The clouds and their undersides are solid now; the
  mist is one solid sheet far below with the drifting mist made by emitters; and honey and slime (and the honey's
  strings, the slime's gobs and the jelly's bits) are SmoothPlastic rather than Glass, which vanished against a bright
  sky.
- **Grass in the house (118)**: the terrain's grass grew up through the hall's floorboards and the path. Under the
  house, the garden path and the step the ground is bare now (Ground), and it goes when the level does.
- **Hill House beside level 4 (118)**: the lobby's pads are in the levels' own numbers (Hill House is the fifth pad, by
  the Flooded Halls, and opens last there), while the story still plays it first: `LevelDefinitions.Story` is the
  story's order, the story's card names the right level next, and a save's place in the story is counted along it.
- **One speech bubble (119)**: what you can say is in the same bubble as what people say (`Style.BUBBLE`: the cream,
  the ink, the letters, the rim, yours rimmed in gold), with a tail, popping in; who you are talking to sits over them
  in a pill. Everyone tells a line with their body (a nod, a shrug, a point, hands as they talk), and your own lines are
  told the same way on everyone's screen; a player's gesture moves only the joints it uses, so your walk is never
  stiffened by it.
- **Your character, all the time (120)**: `PlayerLife.lua`, new. Your head turns toward where the camera looks (up to
  70 degrees, the waist taking a little), and comes back to the front rather than twisting when you look behind you.
  Standing still for four seconds, now and then a fidget: looking round, shifting your weight, thinking. Never over a
  gesture, an emote, a seat, the flume, the water or a scene of yours. **In Hill House's hall**: you walk to the key,
  your hand goes up and it leaves its hook as your hand reaches it, it is in your hand, and you walk out of the open door
  with it, the last shot following you.
- **The thing in the back rooms (121)**: one stiff block jumped along a few times a second before, his seam left behind
  when his head twitched. Now every limb is on a joint (the stoop and the bow in the joints' rests), the seam is welded
  to his face, the server moves him smoothly, and every screen draws him walking (`StalkerClient.lua`, new): long slow
  strides on legs like poles, the knees bending the wrong way as each leg comes through, his hips dropping and swaying,
  a heavy soft thud at every step; arms hanging past his knees, swinging late and loose, and reaching out at you when he
  rushes; his head bowed and lolling, now and then snapping to another angle for a moment, and when you can see him,
  turning toward you in stiff jerks, up to 150 degrees round; when he stops, his head tips slowly over, too far.
- **The shop (122)**: the tabs' outlines were cut along the top and on the left by the strip they scroll in. The strip
  has room inside it all round now (TAB_ROOM), measured by the checker against how far the widest tab grows when it is
  chosen, and the grid has room round its tiles the same way (TILE_ROOM). Each tab is a chunky key in its own colour,
  with its own little drawing on a white disc (a star, footprints, a trail, sound bars, a ring, a figure, a ticket, a
  coin, a swatch), on a lip of a deeper shade that it sinks into when pressed; the chosen one deeper still, white
  lettered, lifted and bounced; under the pointer they lift a little. A tab's colour runs through everything in it: its
  tiles washed pale in it and outlined and lettered in deeper shades of the same colour (its hue kept, never greyed; the
  checker measures every tab's words for contrast), the scroll bar, the "i" card, the confirm card and the toast. The
  tiles sit on a pale tray over the background, each a card on a lip: lifting under the pointer with its icon swelling,
  sinking under a press, and popping in one after another when a tab opens (not when the server's answer draws the
  grid again). The rare backgrounds (epic and up) and what is sold for Robux have a white gleam running round their
  outline. The pack with the most tokens for each Robux says **Best value** (worked out from the catalogue, never
  written in). Your tokens count up or down with the difference rising off the wallet; beside them, on a wide screen,
  how many of the tab are yours, with a bar. The dark behind the shop fades in and out, the confirm card swings in, the
  X turns under the pointer, and choosing a tab or buying something puffs a little of the background's material
  (`ShopLook.puff`).

**Checked**: `check_skypools.py` (the clouds and their undersides solid); `check_hillhouse.py` (the mist one solid
sheet, the ground bare under the house and the path and gone with the level, Hill House fifth in the lobby and first in
the story); `check_hub.py` (the lobby's pads in the levels' order, the story's own list not taken for a level); the
chunk looks (honey and slime off Glass); `check_story.py` (one bubble, the gestures, your character's life and the key
scene); `check_shots.py` (Hill House's last shot follows you out); `check_backrooms.py` (jointed, smooth, the seam on
his face, drawn walking on every screen: the stride, the wrong-way knees, the reach, the head, the thud);
`check_shop.py` (the room round the tabs and the tiles measured, the colours measured, the lips, the tray, the popping
in, the gleams, the best value, the counting). `pass118.py` 18 of 18, `pass119.py` 14 of 14, `pass120.py` 21 of 21,
`pass121.py` 21 of 21, `pass122.py` 43 of 43. The full run after it: 115 suites, 2140 of 2140 caught, src put back
byte for byte. (pass09's write failed for a moment on `blender/gen_serpent.py` and left its planted bug there, which the
runner did not guard; it was put back by hand, the eleven suites it held up run again clean, and `run_all.py` now keeps
and puts back the Blender scripts, their measurements and the sound generators as well as src.)

## Before you test in Studio (passes 117 to 122)

**Paste**
1. The Luau: if you pasted `passes_114_116`, these 21 are all that changed since. **New**: `PlayerLife` and
   `StalkerClient` (StarterPlayerScripts/Services, ModuleScripts). **Changed**: Shared `LevelDefinitions`,
   `MaterialAppearance`, `Poses`, `Style`; Server `Bootstrap`, and Services `BackRoomsService`, `EconomyService`,
   `HillHouseService`, `SkyPoolsService`, `Townsfolk`; Client `Bootstrap`, and Services `DeformationRenderer`,
   `EmoteService`, `HillHouseClient`, `LobbyLife`, `ShopLook`, `ShopService`, `StoryClient`, `TalkClient`.
   `python tools/paste_list.py` lists everything since your last `--mark` (all of 93 to 122); then `--mark`.

**Import (UPLOADS: none)**

**Then play**
2. The lobby: walk through the fountain's bubbles (silent), tap one (a pop); Hill House is the fifth pad, by the Flooded
   Halls. Stand still a few seconds (a fidget) and turn the camera (your head follows). Talk to anyone: your choices in
   the same cream bubble, everyone gesturing as they speak.
3. The shop: every tab whole at its edges, its colour through its tiles, the tiles popping in; hover and press a tile
   and a tab; open a crate or buy something cheap (your tokens counting down, the material's puff).
4. Sky Pools and Hill House: the honey, slime and soda seen from every side; no grass in the hall; take the key and
   walk out with it.
5. The back rooms (the seventh fall in one run, or the lobby's back corridor): watch him walk, rush and stop.

## Fixed from your Studio log (2026-10-21): the font weight

"Black is not a valid member of Enum.FontWeight" (Style:32), and with it every script that needs Style (ChunkBuilder,
UIService, the client Bootstrap) failed to load. Roblox has no weight called Black; its heaviest is **Heavy**, and Style
says Heavy now (it had been wrong since the hundred-and-second pass, when every word became Nunito). Nothing else
changed. The checks missed it because a wrong enum name still parses: `check_luau_syntax.py` now also holds every
`Enum.X.Y` in the game to Roblox's own lists (`blender/roblox_enums.py`), and every other one in the game is right.
`pass117.py` 6 of 6.

**Paste**: `src/Shared/Style.lua` (ReplicatedStorage/Shared/Style) and `src/Server/Bootstrap.server.lua` (its stamp
for Style). No uploads.

## Clocking in, and his face (hundred-and-fourteenth to sixteenth passes, 2026-10-21)

The true ending you chose with the plot on 2026-10-20 ("You are Marsh's child": clocking in, and the Watcher given his
face back). How it is done is mine **(suggested)**. Not played yet. Storyboards: `blender/shots_clock.png` (clocking
in) and `blender/shots_true.png` (the ending).

- **The time clock (114)**: beside Mr Barlow on the gangway to the flume, a cast-iron recorder on its own pillar, its
  hands at three minutes to midnight, a brass lever, and the card rack on its side with one card left in it: yours,
  NOT CLOCKED IN. **"Clock in"** takes it only once you know what it cost your father (the clue Mr Barlow gives when
  you ask him "Tell me about my father", which needs Mr Wick's "Why are you looking at me like that?" first). Too soon,
  Mr Barlow tells you: "Not yet. You'd want to know whose shift you're taking first. Mr Wick on the pier knew him." (or,
  once you know whose child you are, "Ask me about him first. Then sign."). Clocked in: a short scene on your screen
  (your card into the slot, a soft heavy punch, CLOCKED IN; then you and Mr Barlow, "Clocked in. 14 August. Three
  minutes to midnight. On shift."), he says "There. That's all the job is. Go and open them. Then come back up.", and
  a note goes in your journal (**Clocked in**). It lasts for this level only: every level starts with nobody clocked in.
- **His face (115)**: clocked in, the gates end differently, sixteen seconds longer. After midnight, someone walks up
  Outfall 3 out of the daylight ("Someone is walking up out of the morning."). Edwin Marsh, in the Watcher's dark
  clothes with his own face, the green ribbon at his neck ("Key holder, 1979. He has his face back."), and a chord that
  carries the Flooded Halls' own home. He stops at the gate and waves; you wave back ("He waved to you from the dive
  board, the night he went down. You wave back."). He turns and goes back into the light until he is gone: "15 August.
  The tide went out, and the day ended." On your screen only: every other screen and every other ending never shows
  him (he stands in the outfall behind the shut gate, hidden).
- **What it gives (116)**: once a save, 300 tokens (the 2x pass doubles them), the **KEY HOLDER plaque** over your head
  in the lobby and the squish room for everyone to see (the key's green, a brass rim and a small brass key; over the VIP
  tag if you have both; put away on a level), and its badge; and from then on his ledge on the Deco tower is empty on
  your screen. The token pill says "The true ending".
- **To test quickly**: the test panel (F8) has **Know the whole story** (every clue, so the clock takes your card at
  once) and **True ending on/off** (the plaque, and his ledge on your next Sunken City).

**Checked**: a new, nineteenth checker, `check_trueending.py` (the clock on the deck clear of the far rail and of the
way to the flume; earned and pointed to; clocked in for one level; the card punched; the note; Edwin Marsh inside
Outfall 3 facing the room, hidden from every screen but the clocked in rider's, given the time and waiting for it; the
beats in order and inside that time; he stops outside the room, waves, goes back up the outfall; 15 August; the
chord; once a save, the plaque, the Watcher gone, the test panel); `check_shots.py` (the two clocking in shots and the
four of the ending, frame by frame: the first framings of both clocking in shots and of the last shot of the ending
lost you under a bar, and were moved); `check_audio.py` (ClockPunch and MorningChord made, at their level);
`check_story.py` (he says nothing); `check_shop.py` (the true ending's tokens are the one new place tokens are paid).
`pass114.py` 24 of 24, `pass115.py` 31 of 31, `pass116.py` 29 of 29.

## Before you test in Studio (passes 114 to 116)

**Paste**
1. The Luau: `python tools/paste_list.py` lists it (StoryService, Townsfolk, Conversations, FloodedHallsService,
   FloodedHallsClient, EconomyService, ShopCatalog, ShopService, StoryClient, DevPanelClient and Bootstrap changed;
   nothing new). Then `--mark`.

**Import (UPLOADS: 2 sounds)**
2. **SoundService.StorySounds**: ClockPunch and MorningChord from `audio/endings/`.

**Make (optional)**
3. A badge for the true ending (Creator Dashboard, Engagement, Badges), its id in `ShopCatalog.BADGES.trueEnding`.

**Then play**
4. The Flooded Halls: press **Know the whole story** on the test panel (or ask Mr Wick and Mr Barlow), clock in at the
   time clock beside Mr Barlow, ride the flume, and watch the gates to the end. Back in the lobby: the plaque over
   your head, and 300 tokens.

## Mr Gale and Mrs Dunn (hundred-and-thirteenth pass, 2026-10-21)

Hill House's people, at eight in the morning, before any of it. Who they are and what they say is mine
**(suggested)**; `LORE.md` has them under The people. Not played yet. Where they stand: `blender/plan_hillhouse.png`.

- **Mr Gale**, the milkman, meets you at the top of the climb: on the landing, on the far side from the way over to
  the footbridge (never in it), his wire crate of milk at his feet and an empty bottle in his hand, in his white coat
  and cap. Two pints on the step every morning, "same as when he was here"; the tide still in; the paper says you are
  key holder for Outfall 3 and the station wants you by nine; the key on its hook where it always was; mind the
  bridge, it bounces.
- **Mrs Dunn**, the postwoman, inside the garden gate beside the path, in her navy with her red bag and the morning's
  letters: nothing for you but the paper, and your name is on its front; thirty years on this hill; Sal's card came
  yesterday; nobody writes to Hill House now.
- **What you can ask them**: Mr Gale, why he still brings the milk ("Two pints. One for him and one for the little
  one."), what the station wants you for, and then why the big clock stopped, which gives a new note for your journal,
  **His clock**. Mrs Dunn, what the paper says about you and why the door is green (the ribbon's green, so a key
  holder's door could be found in the dark). Once you know whose child you are (Mr Wick, in the Sunken City), each has
  one more thing on a later visit: the second pint was for you; and she saw you on the sea wall every evening.
- Both greet you as you come near, tell every line with a gesture, and have their own voice and their own look, as
  everyone in Harrow Bay does. Both know about the key, so the story's thread is heard on Hill House whoever you talk to.

**Checked**: `check_story.py` (Hill House's two stood up with lines, gestures, voices and looks, both knowing about
the key; their topics followable, the new clue with its note; the hall's captions read for dashes now too);
`check_hillhouse.py` (Mr Gale on the landing in from its edges, on the far side from the bridge and at least four studs
off the way from the top of the climb to the bridge; Mrs Dunn off the path and its lamb's ear, and out of the
gateway; both stood up when the house is built). `pass113.py` 17 of 17.

## Before you test in Studio (pass 113)

**Paste**
1. The Luau: `python tools/paste_list.py` lists it (Townsfolk, Conversations and HillHouseService changed; nothing
   new). Then `--mark`.

**Import (UPLOADS: none)**

**Then play**
2. Hill House: talk to Mr Gale at the top of the climb (F) and to Mrs Dunn inside the gate; ask Mr Gale why he brings
   the milk, then about the clock, and look for **His clock** in your journal.

## His key and his clock (hundred-and-twelfth pass, 2026-10-21)

Hill House's hall, as `LORE.md` has it: his clock stopped since 1979, his coat on the hook, the key on its green ribbon
by the door. How it is done is mine **(suggested)**. Not played yet. A storyboard of the scene: `blender/shots_hill.png`.

- **"Go in"** at his door swings it open now, and that is all it does: the level ends inside.
- **The hall**: floorboards on the plinth and a long red rug, a dado rail round the walls, the hall table with its lamp
  lit (a soft warm light) and a photograph, and the morning sun through the side window, a slant of light across the
  floor with dust turning in it. His coat and his cap on the hooks to the left of the door, as he left them. His
  longcase clock against the right-hand wall, its hands at four minutes to midnight, its pendulum still behind the
  glass of its trunk. And on its own brass hook to the right of the door, the key on its green ribbon.
- **"Take the key"** (hold it a moment) stands you in front of the hook and plays a scene on your screen, three shots:
  beside you as the key comes off its hook ("His key, on its green ribbon. Where you left it last night."); his clock,
  all of it, and a beat in, its pendulum starts and it ticks ("Four minutes to midnight since 1979. It is going
  again."); then from the back of the hall, you by the open door with the morning behind you. Then the banner, and
  the lobby once it has been watched, as every level's ending is. The key is gone from its hook on your screen, and the
  pendulum goes on swinging for as long as the house stands.
- **Two sounds of its own** (`audio/gen_hall_sfx.py`): KeyLift (the ribbon's soft brush and the key touching its hook
  once) and ClockStart (the movement freed with a wooden knock, then tick, tock, a second apart, fading as it goes on).
  Both have a quiet stand-in: without them the scene plays silent.

**Checked**: `check_hillhouse.py` (the door ends nothing now; the key does, once a player, after its scene has been
asked for; his clock at 11:56; everything the scene reads is set, by the names it reads, with the pendulum swung from
where the server hangs it; the hall's lights soft; the remote, the client and its sounds wired and made);
`check_shots.py` (the three shots, frame by frame as the camera sees them: you in the picture and the size each shot
means, the clock's face and its pendulum both in its shot; the first framing lost your head under the top bar and was
pulled back); `check_audio.py` (the two sounds made, at their level, soft enough). `pass112.py` 23 of 23.

## Before you test in Studio (pass 112)

**Paste**
1. The Luau: `python tools/paste_list.py` lists it. New: **HillHouseClient** (a ModuleScript in
   StarterPlayerScripts/Services). Then `--mark`.

**Import (UPLOADS: 2 sounds)**
2. **SoundService.StorySounds**: KeyLift and ClockStart from `audio/endings/`.

**Then play**
3. Hill House: "Go in" at the door, walk to the hook right of the door, "Take the key", and watch.

## Hill House (hundred-and-eleventh pass, 2026-10-21)

You chose it (`ROADMAP.md` section 8, item 7; `LORE.md`, level 5): your father's house on the hill at eight in the
morning, before any of it. This pass is the outside; the hall (his clock, his coat, the key, you deciding) is the next.
How it is done is mine **(suggested)**. Not played yet. A picture from above: `blender/plan_hillhouse.png`.

- **First in the story's clock**: Hill House comes before City Shore in the story and in the lobby's row of pads, so
  it is the first level everyone plays and finishing it opens City Shore. A save that has City Shore finished keeps
  it open. **One thing to know**: a story save from before this pass is one level behind where it was (its place
  counts from Hill House now); in Studio, the test panel's "Story from the start" puts it back at Hill House.
- **The climb**: the usual spiral, 24 chunks of a house and garden's things (honey, butter, a biscuit, lamb's ear,
  the clay of the pots, his bed, the landing's light switches, the bathroom's soap, a parcel), rising out of the
  morning mist that lies over the town. A fall goes down into the mist.
- **The end of it**: a stone landing at the route's end and a footbridge (braced off the rock) across to the top of a
  crag of real ground standing out of the mist beside the spiral, never near it. On the top: a picket fence round the
  edge with the gate open where the bridge comes in, the house's name on the gatepost, stepping stones through lamb's
  ear to the door, an apple tree, a bench looking out to sea. The house: two storeys of white render on a brick plinth,
  sash windows, a slate roof and a chimney, his green front door under a little porch, a brass knocker, two pints of
  milk on the step and the morning's paper on the mat. **"Go in"** at the door, it swings in, and you have finished.
- **Out in the mist**: St Brigid's on its own hill, and the top of the Deco tower over the town.
- **Its light, its sound, its words**: eight in the morning, the sun low and warm; a bed of its own (a breeze through
  the grass and the apple tree, the sea far under the mist, now and then a wood pigeon, low and slow) with the Hold's
  drone faint under it; "Hill House, Harrow Bay. 14 August. Eight in the morning. The day you are meant to clock in.";
  four things to read on the way up: the dairy's milk order on his account, the morning paper naming you key holder,
  a postcard from Sal ("See you on the sea wall at nine. I'll bring a cone."), and his name on the gatepost.
- Its pad in the lobby (the first in the arc, which is wider now for seven), its banner ("You stood at his door", a
  door opening onto warm light), its badge.

**Checked**: a new, eighteenth checker, `check_hillhouse.py` (first in the story at eight, ending at the house, its
light, banner, pad and badge; the crag pushed out until its edge is 26 studs outside the route's circle with its rocks
on the far side only, nothing going down through the spiral, the footbridge a short walk braced off the crag, the house
and garden inside the fence, the mist under the route; built, the old finish line stood down, taken down before the
next level and when it goes, its ground cleared; the door's prompt, swinging in, ending once; no Neon);
`check_story.py` (four things to read and a bed of its own on every level now, Hill House's included);
`check_hub.py` (seven pads in the arc). `pass111.py` 33 of 33.

## Before you test in Studio (pass 111)

**Paste**
1. The Luau: `python tools/paste_list.py` lists it. New: **HillHouseService** (a ModuleScript in
   ServerScriptService/Services). Then `--mark`.

**Import (UPLOADS: 1 sound)**
2. **SoundService.AmbienceSounds**: HillMorning from `audio/ambience/`.

**Then play**
3. Vote for Hill House (the first pad): climb out of the mist, look for the crag and the house as you near the top,
   cross the footbridge, walk up the garden and "Go in".
4. The story: it starts at Hill House now.

## The cookie (hundred-and-tenth pass, 2026-10-21)

You: "Add a cookie chunk yk." (`ROADMAP.md` section 9, item 10.) How it is done is mine **(suggested)**. Not played
yet.

- **A twenty-eighth material, Cookie**: a giant round biscuit, twenty studs across, with a bite out of one side (away
  from the way in and the way out), golden and matte, with chocolate chips pressed into its top.
- **Built of crumbs**, like the soap bar (the cubes are the floor), so it really breaks up under you. A cookie is dry
  and crisp where soap is waxy: your first step on a part of it **cracks** it, lines running out from your foot; every
  step after runs the cracks on; then it **crumbles** a crumb at a time, the cracked top pieces falling out first, the
  crumbs dropping (not drifting up like soap's flakes) and rolling where they land, chips and all, until you drop
  through. It gives way a little sooner than soap, and it is not slippery.
- **Its own crunch** (`cookieCrunch_x4`, one upload): a crisp break, often in two, a dry thud under it and crumbs
  skittering off. Until it is imported, the chocolate bar's snap stands in.
- **Where it is**: City Shore and Sky Pools, and first in the sandbox (the level Studio loads), so you meet it as you
  spawn. Its keepsake, a biscuit from the Promenade Hotel's tea room ("somebody had taken one bite and put it back on
  the plate"), goes on the squish room's shelf, which is ten cubbies across now (room for two more). It is in the
  materials collection, the swatch and the lobby's board, with its first-time hint.

**Checked**: `check_chunk_forms.py` (the cookie built of crumbs, its chips in the top layer only, dark, neither too many
nor tall enough to trip on, one round cookie, cracking then crumbling at its own pace with its own crumbs and dust, its
crunch, in the three levels and the sandbox's count), `check_plan_shapes.py` (its outline walked: it meets its
neighbours eight studs wide), `check_story.py` (its keepsake), `check_squishroom.py` (the shelf), `check_audio.py`
(its sheet). `pass110.py` 28 of 28.

**The full run after it**: 103 suites, and src put back byte for byte. One older suite stopped on a line the cookie had changed (the shelf, ten cubbies across now); moved onto it and run again: 1860 of 1860 planted bugs caught.

## Before you test in Studio (pass 110)

**Paste**
1. The Luau: `python tools/paste_list.py` (with 105 to 109's if you have not pasted those yet). Then `--mark`.

**Import (UPLOADS: 1 sound)**
2. **SoundService.MaterialSounds**: `cookieCrunch_x4` from `audio/sheets/`.

**Then play**
3. The sandbox: you spawn facing the cookie. Walk onto it, stand still on one spot and watch it crack and crumble,
   walk round the bite, and listen.
4. The squish room: the cookie's slab, and its keepsake's cubby on the shelf.

## The shop, the trails, the arches and the lobby (hundred-and-fifth to hundred-and-ninth passes, 2026-10-20 and 21)

The next four things from your notes of 2026-10-20 (`ROADMAP.md` section 9, items 5 to 8). How each is done is mine
**(suggested)** unless marked. Not played yet. What to paste and import is **Before you test in Studio (passes 105 to
109)**, below.

### The shop's look (the hundred-and-fifth pass, `Client/Services/ShopLook.lua`)

- **A material behind it** (you: "stylistically connect the shop UI ... with the rest of the level"): the shop's panel
  stands on one of the game's materials, drawn from shapes alone (no images to upload): cookie with its chips, soap
  with bubbles rising, ice with frost, honey dripping, slime and jelly wobbling, kinetic sand with a footprint or two,
  clouds drifting, bubble wrap, lava's glowing cracks, the back rooms' wallpaper under a failing tube (and now and then
  something tall crossing far behind), and the Hold. It opens on cookie, soap or ice at random (you: "a random
  background of set defaults"), or on the one you have on.
- **A press on the background answers** (you: "crack if it's ice, or sparkle if it's lava, or crumble if it's soap"):
  crumbs, flakes, cracks running out, a drip, a splat, a pop, sparks, the light failing, ripples; each with that
  material's own sound (your soap recording for soap). A press on a button or a tile does not.
- **The cursor, with a mouse** (you: "the mouse icon ... a cookie that crumbles"): a cookie, losing a bite and a shower
  of crumbs at every click, whole again after five. Not on a touch screen, where it would sit under your finger.
- **Every tab its own colour and sound** (you: "the colors need variety", "different sounds when you switch"):
  Featured a sparkle of notes, Steps two footfalls, Trails a swish, Sounds a squeak toy, Auras a bell's shimmer,
  Emotes a rubber boing, Passes a ticket stamped, Tokens coins, Backgrounds paper unrolling.
- **Opening and closing** (you: "a unique little animation and a unique sound"): it squashes up out of nothing, a
  little past full size and turned, and settles, with a sweet jar's lid popping off and a burst of its material;
  closing, it squeezes and drops away turning, with the lid going back on.

### Backgrounds and their crate (the hundred-and-sixth pass)

- **Nine to collect** (you chose token crates and Robux mythics): Honey, Slime and Kinetic sand (common), Jelly and
  Bubble wrap (rare), Cloud and Lava (epic), the Back rooms (legendary), and the Hold (mythic, a Robux pass). Their
  own tab, each tile with its rarity on a pill; tap one to try it behind the shop.
- **The crate**: 250 tokens, **always a background you do not have yet**. Common 60%, rare 25%, epic 11%, legendary 4%;
  once you have every one of a rarity, the others share its chance, and the card says your odds before you pay. Rolled
  by the server, never your screen. It shakes harder and harder while the server rolls it, throws its lid, and what
  came out bursts out of it in its own material and goes behind the shop: light turning behind it for an epic one and
  up, a flash for a legendary or the mythic, a sound for each rarity; then "Put it on" or "Later".
- **Found while building it (Roblox's rules):** a crate opened with tokens that Robux can buy is a *paid random item*,
  and Roblox requires games to keep those from players where they are restricted. The server asks Roblox's policy for
  each player on joining (`PolicyService`) and offers the crates only where it says yes; where it says no, or does not
  answer, the crate's tile says "Not here". In Studio they are offered anyway, with a warning in Output, so you can
  test them.
- **The Hold** needs its game pass made (below); bought, it is unboxed on the spot like a crate.

### Trails and auras (the hundred-and-seventh pass)

You: "less wide", "more specific effects, not just a line that fades out", auras "more pronounced". A trail was one
ribbon two studs tall; now each is thin strands (a quarter of a stud or so), each moved its own way about you on every
screen:
- **Soap suds** two threads twisting round each other; **Honey** one thick thread sagging; **Slime** a wobbling string
  and a darker one out of step; **Cloud** three faint wisps; the **Green ribbon** fluttering in a figure of eight; **Sea
  glass** two glassy threads turning, one glinting all along; the **Swatch** five threads one over another, every
  material's colour, rippling; **Lava** a white-hot thread crackling inside a dull red heat; **Jelly** two threads
  hopping; **Sprinkles** a pink, blue and yellow candy stripe.
- **Auras with a ring or a halo**: bubbles round your feet (Bubbles), a smouldering ring of coals turning the other way
  (Embers), a circle of frost (Snowfall), a crown of gold over your head (Gold sparkle, which comes with VIP), a halo
  of little stars (Starlight).

### Sky Pools' arches (the hundred-and-eighth pass)

You: "glowing or making these cool sparkling effects and kind of like shake my camera a little". On the way down, each
hoop over the slide starts to glow as you come toward it (a small real light in its crown); passing under it, it
flares, its hoop flashes pale, sparkles in its own colours burst off it, the air of it rushes past (a new sound,
ArchPass, a little different each arch) and the picture gives a small shake. It keeps a soft glow behind you, and all
of it fades out at the bottom.

### The lobby's look and feel (the hundred-and-ninth pass)

You: "greatly improve the vibe and aesthetics of the lobby". Picture: `blender/plan_lobby.png`.
- **Each place its own colours**, its floor and the band round it: warm stone round the fountain, the sea's green at
  the level gates, old gold in the hall of fame, candy pink in the arcade, the lawn in the garden. Mid tones, so the
  pads and stalls still stand out.
- **Festoons over every walk**: two strings criss-crossing corner to corner, warm bulbs and pastel bunting by turns,
  hung from four iron poles on the walk, high over your head. Every fourth bulb is a small real light.
- **On your screen only**: soap bubbles drifting up off the fountain on the breeze, wobbling and shimmering; walk into
  one or tap it and it pops, with the bubble wrap's soft pop. Gulls wheeling slowly round the promenade, gliding, now
  and then beating their wings. Fireflies blinking over the garden.

**Checked**: `check_shop.py` (every theme drawn and answering, the defaults, the tabs; the backgrounds against
ShopLook's themes, the crate's odds whole and never the mythic, always one you lack, rolled on the server, opened never
bought, the policy asked and obeyed, the odds said first; the trails' strands thin and moving by motions the client
knows; the rings within their limit), `check_audio.py` (the shop's sounds at their level, their slots the generator's,
a reveal for each rarity, ArchPass), `check_skypools.py` (the arches lit, passed, sparkling, heard, shaking, put
away, lit in small steps), `check_hub.py` (each place's colours, the festoons held at both ends and over your head, the
bubbles, gulls and fireflies only in the lobby and within their limits). `pass105.py` 31 of 31, `pass106.py` 33 of 33,
`pass107.py` 15 of 15, `pass108.py` 16 of 16, `pass109.py` 26 of 26.

**The full run after them**: 102 suites, and src put back byte for byte. Four older suites stopped before the end, each on a line these passes had changed under it (the paste check's Robux list, the Featured row, the shop's list of actions, and two of the ninety-seventh's lines now matching the new rings as well); each was moved onto the code as it is and run again: 1832 of 1832 planted bugs caught.

## Before you test in Studio (passes 105 to 109)

**Paste**
1. **The Luau**: `python tools/paste_list.py` lists them. New: **ShopLook** and **LobbyLife** (ModuleScripts in
   StarterPlayerScripts/Services). Then `python tools/paste_list.py --mark`.

**Import (UPLOADS: 7 sounds)**
2. **SoundService.ShopSounds** (a new Folder): the six files in `audio/shop/` (CookieCrunch_x4, CrateReveal_x5,
   CrateShake, ShopClose, ShopOpen, ShopTab_x9).
3. **SoundService.StorySounds**: ArchPass from `audio/endings/`.

**The Hold's game pass**
4. On the Creator Dashboard (the game, Monetization, Passes) make a pass for **The Hold** (I suggest 399 Robux), and put
   its id in `Shared/ShopCatalog.lua` at `BgHold`'s `passId = 0`. Until then it shows as not on sale yet, and the
   PASTE CHECK lists it.

**Then play**
5. **PASTE CHECK** names anything missing.
6. **The shop**: open and close it a few times (a different background each time), press its background, click with
   the mouse and watch the cookie, change tabs. With the Studio tokens, open crates in the Backgrounds tab, put one on,
   close and open the shop.
7. **Trails and auras**: try each on in the shop and walk about behind the shop; look at Bubbles, Embers, Snowfall,
   Gold sparkle and Starlight.
8. **Sky Pools**: ride the slide and watch the arches.
9. **The lobby**: walk the boardwalks; pop the fountain's bubbles by walking into them and by clicking or tapping.
10. **The Self-test (F8)**, here and in the Device Emulator on a phone (the crate's card and the shop on a small screen).

## Your notes of 2026-10-20 (hundred-and-first to hundred-and-fourth passes)

The first four things from your long list (`ROADMAP.md` section 9 has all of it, in order). How each is done is mine
**(suggested)** unless marked. Not played yet. What to paste and import is **Before you test in Studio (passes 101 to
104)**, below.

### Sounds where they are (the hundred-and-first pass)

- **The fountain is heard at the fountain**: full within 6 studs, fading as you walk away, gone by 55, so from the
  gates or the garden it is not there at all. Its splashes the same (gone by 45). The sea and the wind stay everywhere,
  as you asked; the buoy's bell is out at sea, far off, where it is.
- **Every press has its own sound, heard from the pad** (`audio/gen_press_sfx.py`, SoundService.LobbySounds): a level
  pad a soft stone thock with a note from its window, a mode or length key a round arcade key going down and coming
  back up, a pose key two quick notes on a wooden toy xylophone, the Start a plunger going home with a warm chord
  rising out of it, and a locked pad a dull knock on its boards. Anyone's step onto a pad is heard on every screen near
  it, once as they arrive (AmbienceService watches who is standing on what). The old sound played from the lobby's
  folder, everywhere at once, and only when a vote changed; it is gone.
- **The leaderboard's lever**: thrown to Hardcore it is cranked down notch by notch with a ratchet, slower each notch,
  then lands with a heavy iron clunk and a low boom, its light flaring; flicked back to Chill it is a light wooden
  click-clack and two soft notes. Only when you pulled it, and from the lever.
- **Sky Pools' "light bug"**: I am fairly sure it was the pools' long overflow falls. Each was one pale sheet from the
  pool's lip to the clouds hundreds of studs below, and seen from the side that is a thin white line through everything.
  A fall's sheet now goes down 36 studs at most, thinning to nothing as it goes, and below that the fall is its
  streaks and mist. **Tell me if the lines are still there**, and where you were standing.
- **The bubble wrap's pops are seen**: a puff you can see from behind you, the film's flecks thrown out and falling
  back, a glint at the instant, and the pocket swelling more before it goes. (If they still do not show, look in
  Output for "a BubbleWrap tile has no skinned sheet": that means the sheet was imported without its bones.)
- **Your soap**: the crumble you uploaded is played alone now, at a slightly different pitch each step; my four takes
  are not mixed in with it. To have more takes of it, see **Your sounds, sampled** below.

### One font, every device (the hundred-and-second pass)

- **Nunito for every word** (you chose it): menus, the shop, captions, the journal, signs in the world, letters,
  shouts. What tells one kind of word from another is its weight (Black for the big words, ExtraBold for signs, Bold
  for buttons and names, Medium for what is read) and its slant (italic for a page, a note, a hand, a murmur), never
  another face. `check_style.py` fails on any other face.
- **Fitted to every screen**: the panels drawn at a fixed size (the pause menu, LEVEL COMPLETE, the settings, the best
  times, the conversation choices) scale to fit any screen (`Style.fit`), never larger than it, not tiny on a phone,
  and a little larger on a big monitor or a television.
- **Measured on every device**: the test panel's Self-test (F8) now measures every screen it opens (the shop, the
  journal, the emotes, the pause menu, the death card, and the screen as it is) on the device it runs on, and says
  pass or FAIL for anything hanging off an edge, words that do not fit their box, and on a touch screen a button
  under a thumb. **Run it in Studio's Device Emulator** (Test, Device) on a phone, a tablet and a television.

### The back rooms (the hundred-and-third pass)

- **The way back** (you: "just like in the movie"): behind where you arrive there is a door frame now. If you came
  down the lobby's corridor it is open, its yellow light spilling into the room, and walking back into it takes you
  back up the corridor, to its turn, facing out. If you fell in, it is a frame round bare wall. Only on your screen.
- **The rooms**: carpet that is carpet, plaster walls and ceiling, the ceiling's T-bar grid on every tile's edge, a
  skirting board along the foot of every wall, damp rising up the walls and brown rings on the ceiling, a yellow haze
  in the air and their own light on your screen while you are down there.
- **Him, worse**: too tall for the rooms, so he goes stooped with his head bowed under the ceiling, legs like poles,
  arms hanging past his knees into long fingers, a pale head a size too big with a seam down the middle where a face
  would be. Seen only in jerks (he moves at his pace, but is shown a few times a second, never evenly), his head
  snapping to another angle now and then, rushing down a straight. The lights nearest him nearly die and stutter.
  When he comes, the staff door bangs open, the lights go out from it toward you and come back, and from then on your
  heart is louder and faster and the picture drains of colour the nearer he is.
- **The screamer**: every light near you goes out with a clunk; a beat of black; then he is there, an arm's length
  from your eyes, the lights flaring back too bright; his face splits down its seam and swings open onto rows of long
  teeth and a red throat, the stab and his roar at once, the picture punching in and shaking; he lunges into you;
  black, and the lobby.

### What you say, and the story under it (the hundred-and-fourth pass)

- **Your idea, as you described it**: talk to someone (F, or Y on a controller) and up to three things you could say
  come up low in the middle of the screen, numbered. Choose one (the mouse, a tap, its number key, or the controller)
  and you say it, in a dark bubble of your own over your head for anyone near to see, and they answer it line by
  line; then what else you could say comes up. Walk away and the choices fade by themselves; B or Escape puts them away
  too. "How are you keeping?" is always there for their ordinary lines. What you have said is kept in your save.
- **My suggestions on it, built in**: the choices change with what you know (some only appear once you have learned
  something from someone else, on another level); what you learn goes into your journal as a note; nobody is asked the
  same thing twice.
- **The story under it (you chose it)**: you are Edwin Marsh's child. The key holder before you went down in 1979,
  got the gates open, and the Hold kept him for it; you were the little one on the sea wall who waited for him, and
  the faceless Watcher on the tower is him. That is why you never came in. It is learned in pieces: the Marsh look
  (Sal), the name (Mrs Okafor, Mr Wick), the green ribbon (Maren, Mrs Venn), your father (Mr Wick), the one on the
  tower (Mr Wick), and what it cost him (Mr Barlow); and Pip is you, thirty years on. `LORE.md` has it as canon,
  `Shared/Conversations.lua` every line (37 things you can say to eleven people).

**Checked**: `check_audio.py` (the presses and the lever on their sheets' slots and heard where they are, your soap
alone), `check_skypools.py` (the falls break up), `check_story.py` (the pops seen; every conversation's line clean,
every clue learnable from the start and written in the journal, the Talk remote, walking away), `check_style.py` (one
family), `check_devices.py` (fitted panels, the Self-test measuring), `check_backrooms.py` (the way back from the lobby
only, the dressing, him, the dread and the screamer; and the lights never quite dark: an eighth at the least).
`pass101.py` 14 of 14, `pass102.py` 6 of 6, `pass103.py` 12 of 12, `pass104.py` 11 of 11; twelve older suites
moved onto what changed.

**The full run after them**: 97 suites, 1709 of 1711 planted bugs caught, and src put back byte for byte. The two missed were in `pass90.py`: two of `check_backrooms.py`'s rules looked for a line anywhere in a file, and the new code had put a second copy of each elsewhere (the way back calls him off too; the dressing's helper is not solid either), so taking one copy away went unseen. Each rule now looks in its own function; `pass90.py` and every suite on the back rooms were run again: 26 of 26, and 1711 of 1711 in all.

## Before you test in Studio (passes 101 to 104)

**Paste**
1. **The Luau**: `python tools/paste_list.py` lists them. New: **Conversations** (a ModuleScript in
   ReplicatedStorage/Shared) and **TalkClient** (a ModuleScript in StarterPlayerScripts/Services). Then
   `python tools/paste_list.py --mark`.

**Import (UPLOADS: 10 sounds)**
2. **SoundService.LobbySounds**: the seven new sheets in `audio/lobby/` (PadPress_x4, KeyPress_x4, PosePress_x4,
   StartPress_x2, LockedPress_x2, LeverHardcore_x2, LeverChill_x2).
3. **SoundService.StorySounds**: DoorSlam, TubeDie and ScreamerStab from `audio/story/`.

**Then play**
4. **PASTE CHECK** names anything missing.
5. **The lobby**: walk from the fountain to the gates and listen to it fade. Step on a level pad, a locked one, the
   keys, the pose keys and the Start. Throw the lever both ways.
6. **Sky Pools**: look for the white lines; watch the falls. **Bubble wrap**: watch your feet.
7. **A new save or the test panel's "Clear journal"**: talk to Sal, choose, walk away mid-choice; then Mrs Okafor,
   Mr Wick, Mr Barlow, and read your journal's notes.
8. **The back rooms from the lobby** (the test panel's "Back rooms" counts them as found): walk the corridor, look
   behind you as you arrive, go back through the door; go in again and wait for him.
9. **The Self-test (F8)**, here and in the Device Emulator on a phone and a television.

## Your sounds, sampled (waiting for your files)

You asked whether there is a tool to make the sounds better from your own recordings, and you chose your files plus
free tools. Installed: **librosa** (cutting a recording into its parts and reading its pitch, time and energy) and
**pedalboard** (Spotify's studio effects: EQ, compression, reverb, pitch and time). What I will do with them, once
your files are in **`audio/yours/`** (the soap crumble you uploaded first, and any others you like):
- cut each recording into its separate events (each crumble, each squish);
- make new takes from those pieces by reordering and layering grains, with small shifts of pitch and time and a little
  EQ each, so every take keeps your recording's real texture and none is an exact repeat;
- and match each take's loudness to what the game expects, checked by `check_audio.py` as every sound is.
The paid route (an AI sound API such as ElevenLabs' sound effects, with a key of yours) stays open if you want it later.

## One style, and the lobby as a promenade (ninety-ninth and hundredth passes, 2026-10-18)

From your notes **(you)**: "verify that the style of text, and their fonts and the textures and the stylistic choices
are similar throughout the game", and the lobby "expanded and better modelled", since it "gets way too cluttered"; you
chose the promenade with zones. How each is done is mine **(suggested)**. Not played yet. What to paste is **Before you
test in Studio (passes 99 and 100)**, below.

### One style (the ninety-ninth pass)

- **One module, `Shared/Style.lua` (new)**: the screen's faces (`FONT`: Nunito for headings and body, Fredoka One for
  the big words, RobotoMono for numbers and clocks, the journal's paper in Garamond, a shout in Permanent Marker and a
  murmur in Kalam), the palette (`COLOUR`: the panels, raised panels and their edge, the ink in three strengths, the
  warm accent, Chill and Hardcore, good and danger, the paper and its ink), the sizes, the corners (`RADIUS`) and the
  outlines (`STROKE`).
- **Every screen takes them from it** (24 files): the run's panels, the pause menu, the death card, the vote banner,
  the shop and its kit, the journal, the story's captions and cries, the squish room's words, the viewer's, the lever's.
  The run's panels had a purple of their own and the menus their own corners; they are one now.
- **The world's lettering stays its own**: the signs, letters and notices printed on parts (`Style.WORLD`, a
  SurfaceGui's only) are not the screen's, on purpose, and never appear on a screen.
- **`check_style.py`** (the seventeenth checker): no face named outside Style, the screen's family Nunito, the world's
  faces only by a SurfaceGui, the palette written once, the kit's faces from Style. `check_story.py` keeps the story's
  captions out of the paper's face. `pass99.py`: 12 of 12.

### The lobby as a promenade (the hundredth pass)

It was one deck, 110 by 96, with everything on it, each thing squeezed into the gap the last one left. Now
(`blender/plan_lobby.png` draws it from above, north up):

- **Five decks on piers over the sea, joined by boardwalks** (planks, railed both sides):
  - **the plaza** in the middle (84 by 84): you arrive facing north up the walk to the gates; the pool and its
    fountain, four benches round it, the canopy on twelve columns (one either side of each walk's way in), planters
    in the corners;
  - **the level gates** (north): the pads in an arc round the Start, each facing it with its window behind it; the
    length keys and then the mode keys across the way in, so you walk over them on the way to the Start;
  - **the hall of fame** (east): the leaderboard across from the way in, its lever at the corner, the statue and its
    pose keys;
  - **the arcade** (west): the kiosk facing the way in, the daily chest, the challenges and materials boards and the
    post box facing its middle, and the back corridor in a small closed house in its corner;
  - **the garden** (south): a lawn, four benches facing the sea, planters, the seaside viewer looking out east, and
    the squish room's lift, its door toward the garden.
- **Every place in one table, `Shared/LobbyLayout.lua` (new)**: HubService builds from it, SquishRoomService puts its
  lift by it, `blender/plan_lobby.py` draws it and `check_hub.py` measures it. No place is written into HubService.
- **Everything stands on something**: every deck and walk on concrete piers down into the sea, no more than 30 studs
  apart; the rails 0.7 in from the edges so they stand on the deck, with stone copings resting on them; the level
  pads' windows on their back edges.
- **Real light, not Neon**: the rails' copings and the decks' bands are stone (they were Neon, a glow with no light in
  it); the level pads' windows are tinted glass with a light behind each (off behind the boards of a locked level,
  brighter when it is chosen); fourteen lamp posts, each a lantern with a real light, on the four places and the walks;
  the plaza keeps its columns' lamps and the canopy's lanterns.
- **The way to the Start**: two runs of chevrons, across the plaza and up the walk, pointing north.
- **The back corridor, fixed and housed**: two of its turn's walls ran straight across the first stretch, so the
  corridor ended seven studs in at a yellow wall and its way into the back rooms could never be reached. They run
  from the corner now, and the corridor stands in a plaster house with a slate roof in the arcade's corner (it hung
  over the sea off the old deck). Its doorframe stands on the floor; it was sunk to its middle.
- **Who is in the room** is who is over the promenade (a deck or a walk), not who is within 120 studs of its middle:
  the gates are further off than that.
- **Pushed out**: the far islands (to 400 to 540 studs, turned so none stands on a blade) and the clouds below (240 to
  340), which would have stood among the piers; and the waves the lobby's soundscape breaks far below, beyond the
  promenade's edges.
- **The mode keys centred**: the pair sat at -12 and 0 on a row written for three; they are either side of the way in.

**Checked**: `check_hub.py` measures the promenade from `blender/lobby_layout.py` (which reads LobbyLayout.lua, never
copies it): HubService takes every place from the layout; every thing, at its footprint in HubService's own sizes,
inside a deck's inlay (a lamp on a walk); no two within a stud of each other; every walk's way onto each of its decks
clear, and the way from the spawn to the Start; the decks apart, each walk spanning the gap; everything standing on
the deck; the structure not Neon; the piers into the sea; the lift letting you out on clear floor.
`check_backrooms.py` walks the corridor from outside its door to its way in (it found the old walls across it).
`check_squishroom.py`: the lift where the layout puts it, facing the garden. `pass100.py`: 25 of 25; passes 27, 69,
72, 74 and 77 moved onto the layout (19, 24, 55, 61 and 45 of each caught); and `run_all.py` runs the three-digit
passes too (it looked for two digits only).

**The full run after them**: 93 suites, 1668 of 1668 planted bugs caught, and src put back byte for byte (compared with a copy taken before the run).

## Before you test in Studio (passes 99 and 100)

**Paste**
1. **The Luau**: `python tools/paste_list.py` lists them, by where each goes. New: **Style** and **LobbyLayout**, two
   ModuleScripts in ReplicatedStorage/Shared. Changed for the style: Cinema, DeathService, HubLeverService,
   HubVoteService, JournalService, PauseMenuService, ShopService, SkyPoolsClient, SquishRoomClient, StoryClient,
   SunkenCityClient, UIService, ViewModeService and the client Bootstrap (StarterPlayerScripts); ChunkBuilder,
   BackRoomsService, EconomyService, FloodedHallsService, HubService, Interactables, SkyPoolsService,
   SquishRoomService, StoryService, SunkenCityService, Townsfolk and the server Bootstrap (ServerScriptService).
   Changed for the lobby: HubService, SquishRoomService, AmbienceService and the server Bootstrap. Then
   `python tools/paste_list.py --mark`.

**Import (UPLOADS: none)**: nothing new; the lamp posts are the lanterns already in `Assets/TileMeshes`.

**Then play**
2. **PASTE CHECK** names anything missing (Style and LobbyLayout are new).
3. **The look**: the pause menu, the shop, the journal, the death card, the vote banner and the story's captions, all in
   the same faces on the same dark panels with the same corners; the signs in the world keep their own lettering.
4. **The lobby**: you arrive on the plaza facing up the walk to the gates. Walk each boardwalk: the gates (the arc of
   pads and their windows, the keys on the way in, the Start in the middle), the hall of fame (the board, the lever,
   the statue and its keys), the arcade (the kiosk, the chest, the boards, the post box, and the house with the yellow
   door: walk in, round the corner to its end) and the garden (the lawn, the benches, the viewer, the lift). Look over
   a rail: piers down to the sea. Tell me anything that looks crowded, empty or floating.
5. **A vote from the gates**: a pad, Chill, Short, Start; the countdown; the run; back on the plaza after it.
6. **The squish room**: the lift in the garden, and out again in front of it.
7. **The guide** (on a save that has not had it): the marker over City Shore up the walk, then Chill, Short, Start.

## The sounds remade, the shop's things modelled, the levels' water (ninety-sixth to ninety-eighth passes, 2026-10-18)

From your notes **(you)**: "more variety to the lobby ambience and water splashing, it is too repetitive", "make the
remaining generated sounds way better", "way better quality items in my shop ... using blender meshes and animations",
"make all of the cosmetics in the shop look better". How each is done is mine **(suggested)**. Not played yet. What
to import and paste is **Before you test in Studio (passes 96 to 98)**, below.

### How the sounds are made now (`audio/sfx_kit.py`)

The first generators built everything from band-passed noise, a sine that drops in pitch and a few echoes, and it
showed: water that was hiss, chords that were sine waves, rooms that were four taps. Everything remade is made of
parts modelled on how the real thing sounds:
- **Water is bubbles**: each one rings at its own pitch for its size and rises as it nears the surface (van den Doel's
  model), so a splash is the slap of the surface, a crown of spray fused into a fizz, the cavity closing with a
  thump, a burst of bubbles under it and drops pattering back; a drip is one bubble; a stream, thousands.
- **Struck things ring in their own modes** (wood, plastic, iron, a bell's hum, prime, tierce and nominal), hit as
  hard or soft as asked.
- **The chords are a felt piano and soft strings**: a piano string's stretched partials and two-stage decay, three
  strings a fraction of a cent apart, the felt rounding the top off.
- **Air is noise shaped by a spectrum that moves** (a gust brightens as it rises), and **rooms are real reverbs**: the
  tiled baths, a brick shaft, a culvert, the harbour at night, under the water, a hall for the chords.
- **Every remade sound is at the loudness of the one it replaces** (measured as BS.1770 measures it), so the mix the
  game sets does not move.

### What was remade, and what is new (the ninety-sixth pass)

- **The story's nine** (`gen_story_sfx.py`): the gate is iron dragged over iron (friction catching and slipping,
  ringing the gate's own plate), its screw clanking, water pouring off it; the bay going out is a river (it was a 5 kHz
  hiss); the siren is a motor siren winding up across the town; the thing in the shaft breathes, growls with a throat
  that catches and drags, and roars wet; the jaws are a vast soft thud and teeth; the heartbeat is lub, dub; the
  sting a breath drawn in backwards into a low felt-piano note. **New**: `JournalAdd`, a few pencil strokes on paper
  when something goes in your journal (it was a stock click).
- **The endings' eighteen** (`gen_ending_sfx.py`): all of them, the chords as piano and strings in a hall, the
  splashes and the plunges as water, the flume, the slide, the whirlpool and the culvert as running water in their own
  rooms.
- **The levels' six beds** (`gen_ambience_sfx.py`): the sea on the sands, each wave its own; wind on the terrace in
  gusts, no whistle; the party through a wall (a song, its kick, people talking); the harbour (laps, a hollow
  knocking under the quay, a mooring rope, a buoy's bell); the baths (a tube light's hum, air, drips in the dark
  ringing off the tiles); the Hold (low strings beating, voices that never become words).
- **The keypad** (`gen_keypad_sfx.py`): arcade buttons, not zaps: the microswitch's snap and the cap bottoming out with
  a rush of air (cyan), a creamy thock and a low wooden note (violet), a bump and a rubbery bounce (pink), the lighter
  click back up, three clicks into wooden bars (the combo), a domino run of buttons landing on a warm chord (the lane).
- **Not the lava crust, the Needoh, the lego or the oobleck**: you liked those as they were. The Needoh's and the
  lava's are the twenty-first pass's, their makers kept word for word in `gen_needoh_lava_sfx.py` (it rebuilds them
  byte for byte); the lego and the oobleck were made louder and creamier in the eighty-eighth pass, and left.
- **Sheets**: the keypad's four short sounds are sheets, several takes in one upload, as the chunk sounds have been
  since the eighty-eighth pass. AudioService plays a sheet in place of any single files of the
  same event, so the old ones in MaterialSounds are passed over (delete them if you like).
- **The lobby's own sound** (`gen_lobby_sfx.py`, SoundService.LobbySounds, seven files): two long sea beds drifting
  against each other, the fountain's water at the fountain, and over them, each at random gaps, pitches, loudness and
  places and never one of the last two again: a wave breaking far below (eight), a plop, a plink, a spill or a gurgle
  at the fountain (ten), a gust (five), a buoy's bell (two). Played on your screen, in the lobby only. While the
  folder is not imported the server's old stand-ins play, as now.
- **check_audio.py** (the sixteenth checker) holds every file to: mono 16-bit 44.1 kHz, no clipping or DC, clean ends,
  seamless loops, each family's loudness and softness, no bare tones outside music, takes that differ, every name the
  Luau asks a folder for there, and the lobby's sheets as AmbienceService plays them. Its own self-test shows each rule
  a sound made to break it.

### The levels' water (the ninety-eighth pass)

- **All the water in the game was one sound**: every splash, drip, lap and pour in the levels was the engine's
  impact_water at another pitch. Now it is water of its own kind (`audio/gen_water_sfx.py`, SoundService.WaterSounds,
  six files): six splashes, eight dips (a foot into a pool, a kick, a hand through it), eight drips (into water, onto
  wet stone), and beds of lapping, of water pouring into water and of a running stream.
- **Through one module** (`Shared/WaterSounds.lua`): a one-shot is one of its takes, never the same one twice running
  (a drip that drips again is another drip each time); without the folder, the old splash at its old pitch.
- **Where**: the Sky Pools' pools (your splash into one, your steps through them), their falls, the cabana's shower,
  the slide as others hear it and its splash; the Sunken City's harbour, its lapping, the drips in the stair and the
  flat, the sluice, the sump, the drain's rush and the torrent; the baths' drips off the columns; the dive's splash as
  the shore hears it. What the old splash was used for slowed right down (a wind, a hum, a deep rumble) is left as it
  is: it was never meant as water.

### The shop's things, modelled (the ninety-seventh pass)

- **Seventeen meshes** (`blender/gen_cosmetics.py`, `meshes/cosmetics/`, ReplicatedStorage.Assets.Cosmetics): a puffy
  star and heart, a snowflake, a honey drop, two clouds, a gem, two pieces of sea glass, a sprinkle, a firefly and its
  wings, two embers, a slime splat, a paw print and a sole. Small, soft and rounded, under 900 triangles each.
- **Every trail, aura and set of steps is made of them now**, over the particles (which stay as their haze and
  glints), drawn and moved on every screen near (`CosmeticsClient`, new): sprinkles tossed out tumbling and bouncing;
  honey drops falling and spreading where they land; soap bubbles floating up wobbling and popping; slime landing with
  a wobbling splat; cloud puffs swelling and thinning; jelly beads bouncing twice; sea glass and the swatch's chips in
  every material's colour; embers falling and cooling to ash; the green ribbon's glints fluttering down. Round you:
  stars and gold circling and twinkling, snowflakes falling and turning, bubbles and embers rising, fireflies
  wandering with their wings beating (two of them lit), mist drifting at your feet.
- **The steps pressed in**: a heart, a star, a honey paw (closing up as it goes), a slime splat, a bubble sole
  (swelling and fizzing away) and an ember sole (cooling to ash), each pressed into the ground as the foot comes down.
- **The try-on in the shop is the real thing** (ShopCatalog.wear tags what is worn, and the try-on over it).
- **Cheap**: on each screen only, players within 120 studs, at most 22 of a trail's and 8 of an aura's pieces each and
  260 in all, kept and reused rather than made each time, touching nothing.

**Checked**: `check_audio.py` (above); `check_hub.py` (the paste check's lists as audio/ has them: the sheets, the
lobby's sounds optional, JournalAdd); `check_shop.py` (every trail, aura and step has pieces of meshes that are made,
a motion it knows, sizes a person wears, never Neon, no flood; the client's limits, its pool, the try-on first; the
steps pressed in with the flat print kept for a place without the meshes); `check_story.py` and `check_halls.py`
(the sounds where they are made now); `check_audio.py` (the water's families as WaterSounds plays them, and every
level's water through it). `pass96.py`: 17 of 17, `pass97.py`: 19 of 19, `pass98.py`: 15 of 15.

**The full run after them**: 91 suites, 1630 of 1630 planted bugs caught (one gate in `check_shop.py` was found looking past the flat print into the new modelled one, and made to look at the flat print alone), and src put back byte for byte.

## Before you test in Studio (passes 96 to 98)

**Paste**
1. **The Luau**: `python tools/paste_list.py` lists them (ServerScriptService/Bootstrap, Services/HubService;
   Services/SkyPoolsService, SunkenCityService, FloodedHallsService, DiveFinaleService; ReplicatedStorage/Shared/
   ShopCatalog and **WaterSounds, new** (a ModuleScript in Shared); StarterPlayerScripts/Bootstrap, Services/
   AmbienceService, StepService, SkyPoolsClient, and **CosmeticsClient, new**: a ModuleScript in
   StarterPlayerScripts/Services). Then `python tools/paste_list.py --mark`.

**Import (UPLOADS: 55 sounds, 17 meshes)**
2. **SoundService.LobbySounds** (a new Folder): the 7 files in `audio/lobby/`.
3. **SoundService.StorySounds**: the 10 in `audio/story/` other than CountdownTock_x3 and TownsfolkVoice_x9 (each
   replacing the old one; `JournalAdd` is new) and the 18 in `audio/endings/` (replace each).
4. **SoundService.AmbienceSounds**: the 6 in `audio/ambience/` (replace each).
5. **SoundService.MaterialSounds**: from `audio/sheets/`, the four new sheets (`button_clicky_x4`, `button_linear_x3`,
   `button_tactile_x3`, `button_release_x3`), and from `audio/buttons/` the four remade (`button_combo_1`, `_2`,
   `button_circuit_1`, `_2`, replacing the old). The old single files of the four sheeted keypad sounds can be deleted
   from the folder (they are passed over now).
6. **SoundService.WaterSounds** (a new Folder): the 6 files in `audio/water/`.
7. **ReplicatedStorage.Assets.Cosmetics** (a new Folder): the 17 meshes in `meshes/cosmetics/`, each named as its
   file (Cos_Star, Cos_Heart, ...).

**Then play**
8. **PASTE CHECK** names anything missing (the lobby's and the water's sounds as optional).
9. **The lobby**: stand still and listen for a minute: the sea, waves breaking far off at their own times, the fountain
   with plops and plinks, a gust now and then, a bell far out. Nothing should repeat.
10. **The levels' sounds**: the endings (the chords, the splashes), the gate chamber, the mouth, the beds; and the
   water: walk through a Sky Pools pool and fall into one; listen to the drips in the baths and the Sunken City's stair.
11. **The shop**: try on every trail and aura and walk; try the steps. Then look at another player wearing them.

## What your fourth test found (ninety-fifth pass, 2026-10-18)

From your notes **(you)**: the fall into the mouth "too dark, I can't see anything other than the glowing light", and
"I need to be able to see the player but it should not be so bright that I can see the surroundings", "maybe you
could make the monster have a slight glow as well"; and in the Sunken City, looking up as you fall down the drain,
"there is just empty space around" the whirlpool, "a flying in the sky whirlpool": it should continue, or you should
be "fully submerged underwater". How each is done is mine **(suggested)**. Not played yet. What to paste is **Before
you test in Studio (pass 95)**, below.

### The mouth's dark, which you can see in (Flooded Halls)

- **Why it was all black**: pass 92 took the light from the air down to 5, 5, 7 (a sixth of the halls' own 32, 34, 32)
  and turned the exposure down besides, so the only things on the screen were the mouth's own lamps. The light on you
  was in your head, which lights your shoulders and not your face, and it was faint.
- **Now**: the air keeps about two thirds of the halls' light, cold (24, 26, 34), and the exposure is left nearly as
  it is. What hides the halls is the black air, no thicker than the level's own, which swallows anything a few tens of
  studs off: you and the mouth are seen, the halls round the shaft are not.
- **A lamp over you**, falling with you, seven studs above (as if from the tube's mouth): you are lit from above all
  the way down. Its reach is short (18 studs), so it finds you and not the walls. The light in your head is twice as
  strong as it was.
- **The mouth's own glow**: three faint lamps of its own, cold and sickly green, over its upper jaw, under its lower
  and out past its lips, with no shadows, so they reach its outside: the shape of it, wet, just there, as well as the
  green inside it and the red down its throat. Never warm (warm light through the jaws once made it a glowing
  pumpkin), and out with the rest of its light until the moment it comes for you, so it is still a surprise.

### Under the water down the drain (the Sunken City)

- **Why there was sky**: the harbour is a skin of glass plates over air, and from below glass is a window. The funnel
  of the whirlpool was all there was between you and the sky.
- **Now**: once you are through the bottom of the funnel, on your screen you are under the water. The air turns to
  sea, green-dark and thick enough to swallow the sky and anything far off, and a sea tint comes over everything,
  eased in. The whirlpool overhead fades up into water, not air. As the culvert carries you on, it eases back out,
  and the air is put back exactly as it was (or taken away again, if there was none).

**Checked**: `check_halls.py` (the dark not black, not lit, its exposure not turned right down; the light in your
head strong enough; the lamp over you there, falling with you, short in reach and taken away after; the mouth's own
glow faint, cold, on its outside and out until it comes); `check_sunkencity.py` (under the water from the funnel's
bottom, out of it in the culvert and when your character changes; thick enough to hide the sky and thin enough to see
the whirlpool; the sea's colour; the air, the tint and the thickening put back). `pass95.py`: 23 of 23, and the
older suites on these three files again (passes 8 to 30, 53, 83, 84, 87, 92 and 93): 23 suites, 513 of 513 planted bugs caught, and src put back byte for byte.

## Before you test in Studio (pass 95)

**Paste**
1. **3 files**, plus ServerScriptService/Bootstrap (its stamps): StarterPlayerScripts/Services/FloodedHallsClient, Maw
   and SunkenCityClient. Then `python tools/paste_list.py --mark`. No sounds, no meshes.

**Then play**
2. **The Flooded Halls, the fall**: you, lit from above, falling in the dark; the mouth coming up at you, its green
   inside and a faint cold sheen on its jaws and lips; the halls round the shaft still unseen. Say if it wants a
   little more or less: `DARK` in FloodedHallsClient (the air's light) and the `faint` lamps' 0.7 in Maw.light.
3. **The Sunken City, the drain**: through the funnel and down; looking up, the whirlpool over you in green water, no
   sky; back to normal air in the culvert.

## The camera, checked shot by shot (ninety-third and ninety-fourth passes, 2026-10-17)

From your notes **(you)**: "further improve the camera angles for level 4 and 1, and 3 and 2. Verify them extensively
and make them better", and the butter sticks' deformation. How each is done is mine **(suggested)**. Not played yet.
What to paste is **Before you test in Studio (passes 93 and 94)**, below.

### How the shots are checked now (`blender/check_shots.py`)

Every scripted shot in levels 1 to 4 (the dive, the slide, the drain and the outfall, the flume, the mouth and the
gate chamber: 44 shots) is restated line for line from its client (`blender/shots_shore.py`, `shots_skypools.py`,
`shots_sunken.py`, `shots_halls.py`) and played through `blender/shots.py`, which is Cinema's camera as the game has
it: put at the eye at once, the aim easing after its target unless the code cuts, a vertical field of view, and the
letterbox bars over the top and bottom 11% of the picture (`BARS`, read from Cinema.lua). Frame by frame, 60 a second,
it asks of every shot:
- **Seen**: you are in the picture and not under a bar, all the way through, with the aim's lag (a fast fall and a
  slow aim lose each other).
- **Size**: you are the size the shot means to show you at (a speck, wide, medium, close; or coming at it, or going
  away), so a close shot that is a speck, or a wide shot that is a nose, fails.
- **Not in you**: the camera never comes within a stud and a half of you.
- **Long enough**: no shot under 0.8 s, but for the beats meant to be quick (the bite).
- **Up to date**: if a shot's line changes in a client and is not restated here, it fails rather than checking a shot
  the game no longer has.
`python blender/check_shots.py --boards` also draws a storyboard for each level (`blender/shots_*.png`): every shot at
its start, middle and end, as the camera sees it, bars and all. The Sky Pools are checked on all three run lengths, on
several laid runs each. It is one of `check_all.py`'s checkers now (fifteen).

### What it found, and what changed

**Level 4, the Flooded Halls**
- **The flume, from ahead**: in its last moments the point it looked from was out past the end of the tube, and the
  camera hung over the end while you went through it. It keeps to the tube now, and ends a moment before the exit.
- **From below**: it waits under the end of the tube a moment before you reach it (where you are going), and you shoot
  out of it toward the camera.
- **The mouth, past you into it**: you were above the picture, under the top bar, the whole shot. Now you are in the
  top third, small, over a mouth that fills the rest.
- **The mouth's beats**: every shot in it was half a second or less, three and a half seconds of cuts. Time now all but
  stops over the open mouth for longer (you fall at 2 studs a second, from 0.8 s to 2.6 s), every shot in it is at
  least 0.8 s, and only the bite is a slam. It waits a little deeper (116 studs) so you still hang well over its teeth,
  and you are still in it before it shuts (`check_halls.py` restates the fall).
- **The key**: it panned in from the walk with you half out of the picture. It cuts to a low shot ahead of you and to
  your right, looking up: your face over the lock as the key goes in, the wheel beside you.
- **The wheel and the gate**: you were under the bottom bar while it looked up at the gate. From behind you and to your
  left now, easing in: you at the wheel, from the waist up, the gate going up behind you. The walk, the key and the
  wheel each cut in rather than swinging over from the shot before.

**Level 1, City Shore (the high dive)**
- **The leap**: close to the lens and falling, your feet went under the bottom bar for its first moment. A little lower
  and wider now, aimed under you.
- **The drop**: it looked a third of the way to the sea and you were under the top bar the whole time. It looks down
  past you now: you in the top half, the sea filling the rest.
- **The drop and your face**: the drop is only two seconds, and split three ways no part of it could be read. Two beats
  now: the drop, then your face.
- **The water**: aimed at you, the camera turned after you too slowly in the last moment and you fell out of the
  picture. It aims ahead of your fall now, and you are in it to the splash.
- **Under the water**: it was in front of you and turned to the lamp at once, so you were behind the camera within a
  second. It is behind you and a little over you now (never above the surface), on you as you sink for two seconds,
  then tilting down past you to the lamp on the drowned street.

**Level 2, the Sky Pools**
- **The landing**: held four and a half seconds looking up at the tower, with you under the bottom bar the whole time.
  Lower over the water and further off now: you in the pool in the lower third, the tower going up behind you. The
  rest of the slide passed on every run length.

**Level 3, the Sunken City**
- **The bottom of the drain**: the camera was in the shaft and you landed on the lens. It waits in the mouth of the
  culvert now, low, looking up into the sluice as you come down into it (where the water takes you next).
- **To the light**: you were under the bottom bar for the whole of it. From higher and further back over your shoulder
  now, you in the lower half and the culvert running on ahead to the light.

### The butter sticks (ninety-fourth pass)

- **What was wrong** (your words: the dent spread "as though the step was done in multiple locations", and the wax
  shell "sits too high up and is flat rather than the wavy model"): a step pressed 1.62 studs into a stick that stands
  only 1.45 over its grooves, so it caved in below the sticks beside it; every step sent a slow wave of dips across the
  whole chunk after it; and the wrapper over the sticks was never moved at all, so it stayed up as a flat lid over every
  dent (the wrapper mesh itself is right: it dips into both grooves, a constant 0.3 over the butter).
- **Now**: a dent of 0.9 (shallower than the stick is tall), no travelling wave, and the wrapper driven with the butter:
  down with it, holding its dent, and back up with it, on the same falloff as the sticks' own bones.

**Checked**: `check_shots.py` (above); `check_halls.py` (the hang no faster than 3 studs a second, the fall restated
with it); `check_story.py` (the dive's drop looks at the sea; the butter sticks' dent, wave and wrapper).
`pass93.py`: 13 of 13, `pass94.py`: 8 of 8.

**The full run after them**: 87 suites, 1556 of 1556 planted bugs caught, and src put back byte for byte.

## Before you test in Studio (passes 93 and 94)

**Paste**
1. **6 files**: StarterPlayerScripts/Services/CityShoreClient, SkyPoolsClient, SunkenCityClient, FloodedHallsClient and
   DeformationRenderer; and ServerScriptService/Bootstrap only if `tools/paste_list.py` lists it. Then
   `python tools/paste_list.py --mark`. No sounds, no meshes.

**Then play**
2. **City Shore's dive**: the leap, Maren, the turn, the drop looking down at the sea, your face, the water shot to the
   splash, and under the water: on you as you sink, then the lamp.
3. **The Sky Pools' slide**: the landing, you in the pool with the tower behind you.
4. **The Sunken City's drain**: the bottom, from the culvert's mouth; the culvert to the light.
5. **The Flooded Halls**: the flume's end from below; the mouth (longer, every shot readable); in the chamber, the key
   and the wheel.
6. **The butter sticks**: one dent where you step, the wrapper going down with it, no dips running off across the chunk.

## What your third test found (ninety-second pass, 2026-10-17)

From your Output after pasting passes 86 to 91, and your notes **(you)**: no terrain on City Shore, the mouth gone from
the Flooded Halls, and "improve the animation for level 1 and 4". How each is done is mine **(suggested)**.
Played in Studio on 2026-10-17 **(you)**. What was pasted is **Before you test in Studio (pass 92)**, below.

### What the Output showed

- **BackRoomsService's code was in BackdropService.** The line `BackRoomsService: built, 61 lights, 395 parts` came
  from `BackdropService:802`, which is where the new BackRoomsService prints it, while the real BackRoomsService
  printed the old count (244 parts, from line 312: the old copy, as the paste check said). BackdropService builds
  City Shore's backdrop, the land, the beach city, the sea and the clouds, so City Shore had none of it; and the
  dive's sea is part of it, so the dive went into nothing. **Fix**: paste `src/Server/Services/BackdropService.lua`
  back into BackdropService, and `BackRoomsService.lua` into BackRoomsService.
- **The paste check could not see it**: BackdropService has no stamp to compare. It now looks at every module, stamped
  or not, on the server and on your screen, for a STAMP that belongs to another module, and says
  `wrong code  ...BackdropService has BackRoomsService's code in it`.
- **SearchlightClient is missing** from StarterPlayerScripts/Services (the rescue launch and its searchlight in the Sunken
  City harbour are made by it): paste `src/Client/Services/SearchlightClient.lua` in as a ModuleScript.
- **"missing StarterPlayerScripts/Bootstrap"**: yours is named `BootStrap`. Nothing was wrong; the check now matches a
  name however it is written.
- **Nothing was being saved.** `ProfileStore.New failed ... attempt to call a nil value` means the module named
  ProfileStore in ServerScriptService is not loleris's ProfileStore (it has no `ProfileStore.New`; if it is his older
  ProfileService, it has `GetProfileStore` instead). Put ProfileStore from github.com/MadStudioRoblox/ProfileStore in
  its place, named exactly ProfileStore. EconomyService and the paste check both say this in plain words now.
- **Fine as they are**: the shop items and badges with no ids (needed before publishing, not for testing), the meshes
  wrapped in Models, ButterWax with no SurfaceAppearance, Roblox's own UIBlox and AnalyticsService lines, and the
  hub's pose line.

### The mouth, back in the dark (Flooded Halls)

- **It was there, and the dark hid it.** Pass 87 made the shaft dark by thickening its air to 0.82; the thickest any
  level uses is 0.34, and the halls' own notes say 0.42 already erased the water. Black air that thick hides
  everything past a few tens of studs, lit or not, and the mouth is never closer than that until the end.
- **Now the dark is not fog.** The air is made black at the level's own thickness or less; the sky's and the air's
  light are turned off on your screen; the shaft's own lamps go down to a tenth; the faint light on you stays. The
  mouth's own lights are then the only thing lit down there: the green inside it, the red down its throat, the cold
  light on its teeth. All of it is put back as the chamber starts (anything still fading stopped first).
- **The animation**: you were falling into it on your back (as you came out of the tube), so the shot from inside
  it saw your back. Now, as it lights and lunges, you twist over in the air to face down into it. Then a new beat:
  YOUR FACE, close, from under it, lit green from below, as you see what it is ("No. No no no no."); then the drop,
  seen from inside it, your face coming at it; then the bite, wide. The beats: dark 0.45 s, it lights and lunges
  0.75 s, the wide shot to 1.5 s, your face to 2.1 s, inside it to 2.95 s, shut at 3.35 s.

### The high dive (City Shore)

- **The drop looked up at the sky**, away from where you were going. It now looks down past you at the sea coming
  up, from over you and a little behind, leaning with the wind.
- **You act on the way down**: "Okay. Don't look down." as you leave the board, "I looked down." as you turn over and
  see it, and "Arms together. Arms together!" with the water coming. And a close look at your face, head first, the
  wind in it, partway down the drop, before the sea again and the shot from the water as you come in.
- Maren still shouts and waves you off from the deck, and the cut back up to her is kept.

**Checked**: `check_halls.py` (the dark no thicker than 0.4 and never set outright; the sky's light off; the lamps
dimmed and put back; the tweens stopped; you turned over; your face held long enough to read and the wide shot long
enough to see), `check_story.py` (the thoughts, no dashes, the drop looking at the sea, the face), `check_stamps.py`,
`check_hub.py` and `check_shop.py` (the paste check and ProfileStore). `pass92.py`: 29 of 29.

### Polished before you paste (2026-10-17)

- **The client's paste check** required every module it found in StarterPlayerScripts/Services to read its stamp, so
  a module taken out of the game and not yet deleted (KeepsakeService, PromptStyleService) would have been started up
  by it. It looks only at the game's own now: the stamped ones and the four with no stamp (CloudService,
  HubLeverService, InputService, SeaService), a list `check_stamps.py` keeps the same as src.
- **The look at your face** (Flooded Halls) was from straight under your head, and lying flat as you are, your chest
  or a flailing arm could have been in the way. It is from under your face and out past the crown of your head now.
- **The failing fitting** in the halls (the roof light that stutters) has its brightness set by the server many times
  a second, so dimming it on your screen would not hold; if it is near enough to the shaft, it is switched off for
  the scene instead, and back on after.

**The full run after it**: 85 suites, 1535 of 1535 planted bugs caught, and src put back byte for byte.

## Before you test in Studio (pass 92): tested 2026-10-17

**Paste**
1. **Fix the mix-up first**: `src/Server/Services/BackdropService.lua` into ServerScriptService/Services/BackdropService,
   and `src/Server/Services/BackRoomsService.lua` into ServerScriptService/Services/BackRoomsService.
2. **Put back** `src/Client/Services/SearchlightClient.lua` as a ModuleScript in StarterPlayerScripts/Services.
3. **The 5 changed this time**: ServerScriptService/Bootstrap, ServerScriptService/Services/EconomyService,
   StarterPlayerScripts/Bootstrap (yours is `BootStrap`, that is fine), StarterPlayerScripts/Services/CityShoreClient
   and StarterPlayerScripts/Services/FloodedHallsClient. Then `python tools/paste_list.py --mark`.
4. **ProfileStore**, if you want saves while testing: loleris's, named ProfileStore, in ServerScriptService (above).
   No new sounds.

**Then play**
5. **PASTE CHECK** should say `everything is in place`, or name exactly what is not.
6. **City Shore**: the land, the beach city and the sea are back; the dive: the thoughts, the drop looking down at
   the sea, your face, the splash.
7. **The Flooded Halls**: the flume, then the fall: black, then the mouth lighting and lunging, you turning over, your
   face lit green, the drop into it, the bite.

## What your second test asked for (eighty-sixth to ninety-first passes, 2026-10-16)

Everything here is from your notes and the recording after testing passes 78 to 85 **(you)**; how each is done is mine
**(suggested)**. Played in Studio by 2026-10-17 **(you)**. The list of what to paste and import is **Before you test in Studio
(passes 86 to 91)**, below.

### The lockers, and the secrets' scenes (eighty-sixth pass)

- **What was wrong**: a locker was a solid block, and its door swung back INTO it, so opened it showed a blank grey
  face: it read as a locker turned the wrong way round. The scene looked over your shoulder, so your back filled it,
  or your head when the wall behind you pulled the camera in.
- **Now** a locker is hollow: back, sides, lid, floor, a shelf and a hook, and a small lamp under the lid (a real
  light, no Neon) that comes on as the door swings OUT toward you. Locker 3 has your coat on a hanger, dripping, with
  your key holder card inside the door ("HARROW BAY WATERWORKS, KEY HOLDER, OUTFALL 3"); Marsh's has his cap, his
  torch and a letter; the empty ones a wire hanger.
- **The scene** is shot from the side with room (it picks it once and keeps it), you and the thing both in the
  picture; then a close look, in front of what you found. A secret you have already found (this session, or kept in
  your journal from before) is a short look, about three seconds, with no sting and no card.
- **Checked**: `check_story.py`, `pass86.py`: 23 of 23.

### The fall into the mouth, in the dark (eighty-seventh pass)

- **What was wrong** (from your recording): the mouth was lit before it had you, its lights cast no shadows so it
  glowed through its own jaws like a pumpkin, and the shots lost you against its rim.
- **Now** the shaft goes black on your screen as you are shot out of the tube (the light, the air and a colour grade,
  all put back before the chamber and whenever the scene ends), with a faint glimmer on you so you are not lost. The
  mouth waits far below, unseen, and as the light comes up in it, it LUNGES up at you, opening. The beats: falling
  into black, seen from above (0.75 s); from above at an angle past you, a speck over a mouth that fills the shaft,
  time all but stopped (to 2.1 s); from inside it, looking up at you coming down into it (to 2.95 s); from above,
  wide, as it shuts on you (3.35 s); then black and one line.
- Its lights cast shadows now, so the glow is inside it; the breath is darker, the saliva fainter. The water off the
  end of the flume stops a short way down the shaft instead of making a lit column in the dark.
- **Checked**: `check_halls.py` replays the fall (hanging over the open mouth for at least half a second, inside it
  before it shuts) and where every shot is taken from. `pass87.py`: 18 of 18.

### The chunk sounds, second round (eighty-eighth pass)

- **Eleven sounds, eleven uploads**: each is ONE file holding four takes, one second each, played by slot
  (`audio/gen_sheet_sfx.py`, written to `audio/sheets/<event>_x4.wav`). Chocolate bar and solid chocolate are dry
  breaks with a woody knock and crumbs, never a ring (the old ones rang like glass tapped with a fingernail; solid
  chocolate now has its own heavier crack). New takes for slime, soap, memory foam, the light switches, kinetic
  sand, the jellyfish (its own event now), ice, jelly soda and bubble wrap.
- **Bubble wrap** was behind your feet: its new pops start on the instant, and it pops once a footfall like every
  other surface (it used to be twice as often). Its old uploads, and the sand's, are no longer picked from.
- **Oobleck, lego and the keyboards**: the same sounds, louder (about 1.4 to 1.5 times) and creamier (more low end,
  less top).
- **Honestly**: I cannot hear any of it. Each take was measured (no ring after 80 ms for chocolate, nothing too low
  for a phone, little hiss above 6 kHz, the bubble pop starting within a millisecond).
- **Checked**: `check_shop.py`, `pass88.py`: 15 of 15.

### The people's voices (eighty-ninth pass)

- Nine mumbles, no words: one for each gesture (a hello, explaining, pointing, a shrug, worried, remembering, a
  warning, leaning in, sad), all in one upload (`audio/story/TownsfolkVoice_x9.wav`, from `audio/gen_voice_sfx.py`).
  Each person says them at their own pitch (Pip high, Mr Barlow and the watcher low) and they come from the person,
  as each line starts.
- **Checked**: `check_story.py`, `pass89.py`: 8 of 8.

### The back rooms, from the second test (ninetieth pass)

- **What the rooms have kept**: things from the game sunk into the walls, the carpet and the ceiling (a lifebuoy, a
  deckchair, a ladder, a locker, a bench, a slab, a parasol, a buoy), tilted, their colour gone toward the walls'
  yellow. Some are wrong: stretched tall and thin, flattened, too big, or the same thing three times in a row along a
  wall, sunk exactly as deep. None is solid or in your way, and none reaches across a corridor.
- **Something walks down here**: after 30 seconds lost (or, about one time in three, sooner), the staff door opens
  and E. Marsh comes out. You hear him, you think "...is someone there?", and the lights near him stutter and dim. He finds his way to you through the rooms but walks slower than you, so the way out can be reached first. If
  he catches you: a lunge, a roar, black, and you are in the lobby (in a run, the run is over).
- **"Leave to the lobby"** did nothing in the back rooms when you were not in a run; it takes you up now.
- **Only the hum**: the lobby's sea, wind and music are hushed while you are down there (through a sound group on
  your own screen, so the wind the server keeps adjusting and a breaker made while you are there stay quiet too), and
  brought back as you leave.
- **Checked**: `check_backrooms.py` (he can reach every tile you can, from the staff door), `pass90.py`: 26 of 26.

### The lobby, polished, and one text for the story (ninety-first pass)

- **The VIP tag**: a pill with a gold to lilac to pink gradient and a white rim, the letters outlined, a little gold
  crown of three points on top, and a shine that sweeps across it every few seconds.
- **The embers**: embers cooling from white through gold and orange to red, sparks spitting up drawn out along their
  flight, flame licking round your feet, a faint heat haze, ash, and a slightly stronger warm light on you.
- **The countdown**: a soft wooden tock each second, a quick double tock for the last three, and two warm marimba
  notes as it runs out (`audio/story/CountdownTock_x3.wav`, one upload). The same two notes greet a level you have
  just opened. It was the engine's electronic ping; until the file is in, a soft click stands in.
- **The keepsakes** said 27 of 28 with everything found: the journal counted its own version stamp as a keepsake.
  It counts only keepsakes now.
- **One text**: the thoughts over your head, the whispers and the secret's card were in Garamond and the captions in
  Gotham, so the Sunken City (told in captions) and the Flooded Halls (told in thoughts) read differently. All of
  the story on screen is Gotham now.
- **Checked**: `check_shop.py`, `check_story.py`, `check_hub.py`, `pass91.py`: 20 of 20.

### Polished before you paste (2026-10-17)

A read through everything above, line by line, before it went into Studio. What it found and fixed:
- **The back rooms' hush** turned each lobby sound's own volume down, and the server sets the wind's volume every half
  second and makes a new breaker every 15 to 40 seconds, so both would have been heard down there again. It goes
  through a sound group of your screen's own now (above).
- **The VIP tag's shine** was a bar inside the badge, and a frame clips its children square whatever its corners, so it
  would have shown past the badge's round ends. It is the badge's own rounded shape now with a band of light slid
  across it. The crown's middle point sat a hair off its band; it is seated now.
- **Being caught**: the cut to black came in a window of a twentieth of a second, which a slow frame could miss; it
  comes once now, whatever the frame rate. The lowest voices (the watcher, Mr Wick) were cleared away only a tenth of
  a second after their mumble ended, slowed as they are; each is kept for as long as it plays now, and a little more.
- **The mouth's lunge** carried every part of the mouth to its place on every frame of the scene, long after it had
  stopped rising; only while it rises now.
- **A checker gone blind**: the check that leaving a run from the menu is logged also matched the new code for being
  caught in the back rooms, so it could no longer tell if the menu's own line went missing. It looks at the menu's own
  now.

**The full run after them**: 84 suites, 1506 of 1506 planted bugs caught, and src put back byte for byte.

## Before you test in Studio (passes 86 to 91): tested 2026-10-17

**Paste and import**
1. **Paste** the 18 Luau files that changed (`tools/paste_list.py` lists them; line 2 of each names its place),
   then run `python tools/paste_list.py --mark`.
2. **Sounds, 13 files** (13 uploads):
   - into SoundService/MaterialSounds, the 11 in `audio/sheets/` (`chocolateSnap_x4`, `chocolateChunk_x4`,
     `slimeBoing_x4`, `jellyBounce_x4`, `soapCrumble_x4`, `foamCompress_x4`, `switchClack_x4`,
     `kineticSandImprint_x4`, `iceCrack_x4`, `jelloWobble_x4`, `bubblePop_x4`). Keep each name as it is: the `_x4`
     is what tells the game it is four takes. The old single takes for those events can stay or go: a sheet is
     picked instead of them.
   - into SoundService/StorySounds, `audio/story/TownsfolkVoice_x9.wav` and `audio/story/CountdownTock_x3.wav`
     (both have a stand-in until they are in).

**Then play**
3. **PASTE CHECK** should say `everything is in place` (the voices and the countdown are listed as optional).
4. **The lobby**: wear VIP (the tag and its shine), buy or wear Embers, and wait out a countdown (tock, double tock,
   chime).
5. **Chunks**: stand on the chocolate bar, solid chocolate, slime, soap, memory foam, a light switch, sand, a
   jellyfish, ice, jelly soda and bubble wrap (the pops under your feet, not behind); oobleck, lego and a keyboard.
6. **Talk to everyone** (F): a mumble with each line, in their own voice.
7. **The Flooded Halls**: Locker 3 (the door swings out, the lamp, your coat and card, the scene from the side), open
   it a second time (a short look); then the flume and the fall: black, the lunge, the shots.
8. **The journal**: the keepsakes' count.
9. **The back rooms**: the things in the walls; stay lost for 30 seconds (he comes); try "Leave to the lobby"; only
   the hum.

## What your first test asked for (seventy-eighth to eighty-fifth passes, 2026-10-16)

Everything here is from your notes after the first test of passes 18 to 77 **(you)**; how each is done is mine
**(suggested)**. Played in Studio by 2026-10-17 **(you)**. The list of what to paste and import is **Before you test in Studio
(passes 78 to 85)**, below.

### The chunk sounds, remade (seventy-eighth pass)

- **Salt and clay** ("a bit weird") are new, and so are the four weakest of the rest: **cloud, lamb's ear, snow and
  charcoal**. Four takes each, 24 files, made by `audio/gen_chunk_sfx.py` the way needoh and lava were: real grains
  and shaped noise, no tones, each take its own sound rather than the same one reseeded. Salt is a dry crunch, clay
  a soft wet squash, cloud a hush, lamb's ear a brush of leaves, snow a packed creak, charcoal a brittle snap.
  `gen_material_sfx.py` no longer writes those six, so running it does not put the old ones back.
- **Step sounds from the shop** play only in the lobby and the squish room, never on a level (your chunks' own
  sounds are the game there), and only every three to five steps, soft, at their natural pitch. **Poppy** was a
  computer blip, pitched up, because it never found a real sound; it now plays the bubble wrap chunk's own three
  pops, at their natural pitch. The packs: Crunchy (salt and
  snow), Gloopy, Poppy, Thock (a keyboard's thock, in place of Retro) and Velvet (lamb's ear and cloud).
- **Honestly**: I cannot hear any of it. Each was measured against needoh and lava (how bright, how much hiss above
  6 kHz, how different the takes are) and kept low and soft. If one is still wrong, say which and how.

### The shop's words and look (seventy-ninth pass)

- Every tile: the icon on a soft stage, the name under it in the shop's chunky font (not italic), and the line about
  it in the same font, sized to fit and never smaller than reads. An **"i"** in the corner of every tile: hover it or
  press it and a card says what the thing is and how you get it; press anywhere to close it.

### The trails and auras, and more to buy (eightieth pass)

- **Embers** are now embers: sparks rising and drifting, glowing, with a faint warm light on you. **Honey drip**
  drips and catches the light. Every trail and aura has its own look (`ShopCatalog.LOOKS`), not a plain stream.
- **New**: Slime step (130) and Ember step (170) footprints; Jelly ribbon (220), Sprinkles (260) and Lava ribbon
  (320) trails; Velvet (90) steps; Snowfall (280), Fireflies (350) and Starlight (450) auras.

### City Shore's dive and the bar's scenes (eighty-first pass)

- **The dive** is hit like an action game: impact frames (two frames in black and white, a soft flash, a punch in)
  leaving the board, bursting through the gulls and hitting the water; speed lines down the drop; wind streaks past
  you and air trails off your hands and feet; your body buffeted and rolled by the wind on the way down.
- **The pry bar** is seen at work: the first time it opens something you turn to it, set the bar, three hard tugs
  with dust coming out, and what you think over your head ("Rusted shut. Something rattles inside."); on the last
  tug it gives, with an impact frame, and you jump back. A secret's scene has you in it: hand at your chin, head
  tilting, working it out, what you make of it over your head. The loose board: you lean over the gap, and jolt.

### The Sky Pools slide says where it is going (eighty-second pass)

- **What was wrong**: the deck is only about twenty studs above the cloud tops, so the shot "from under the clouds,
  looking up at where the slide comes out" started straight after the push off and held for nine seconds: the bottom
  of a slide with nobody on it.
- **Now**: alongside you looking ahead, so you see the slide run on down into the cloud sea; held over the cloud tops
  as you plunge in (a whoosh); while you are in the cloud, a wide shot from under it of the slide coming down out of
  it and round into the pool it lands in (where you are going), drifting in; then a cut a moment before you come
  out, under the exit, and you burst through in a puff with an impact frame, the camera turning after you.
- **Checked**: `check_skypools.py` replays the shots on laid runs: no shot shorter than 0.8 s, the camera waits on the
  empty exit for 1.3 s at most, never sits inside a cloud, and the wide shot frames the exit, the cloud over it and
  the pool. `pass82.py`: 15 of 15.

### The Sunken City's whirlpool, smooth (eighty-third pass)

- **Thirteen meshes** from `blender/gen_whirlpool.py` (see the renders `blender/whirlpool_pier.png`,
  `whirlpool_top.png` and `whirlpool_inside.png`): the funnel's water in six smooth rings, each turning faster than
  the one outside it; spiral ripples wound tight into the hole, so as they turn the water reads as pouring in; threads
  and flecks of foam on each ring; a lumpy crest of foam round the rim. It was sixteen flat boards to a ring, stepping
  down, and turned like a stack of plates.
- **Import them** into ReplicatedStorage/Assets/TileMeshes (`meshes/Whirl_Band1.fbx` to `6`, `Whirl_Foam1` to `6`,
  `Whirl_Lip`). Without them, or with an old import, the old rings of parts stand in.
- **Checked**: `check_sunkencity.py` holds the meshes' sizes, speeds and colours to the generator, the spiral's
  winding against the client's turn, and replays the drain's ride over the new (opaque) water: you stay over it.
  `pass83.py`: 20 of 20.

### The Flooded Halls' flume and the mouth (eighty-fourth pass)

- **You were standing on the slide**: the ride's path is a standing rider's and only your arms were posed. Now you
  lie back in the trough, feet first, and ride it like a person: balancing with your arms out along the walls, then
  grabbing at them one hand after the other with your heels scrabbling and your head snapping round, then flailing
  as you shoot out of the end. What you think comes up over your head: "Staff only... and here I am.", "It just keeps
  going down.", "Too fast. Way too fast!", "Where is the bottom?!" and, after the growl, "...what was that?"
- **The jitter**: the ride went in straight lines between the 220 points of its path (a jolt at each), and read the
  server's clock afresh every frame (a hitch every time the clocks agreed again). It now follows a smooth curve
  through the points, on your own client's clock.
- **The slide**: water runs down the trough (a sheet of it across the bottom, which your legs go under) and pours off
  the end into the shaft; spray is thrown up behind you; speed lines, and an impact frame as you leave the tube.
  If the water seems to run uphill, change `FLUME_FLOW = 14` to `-14` in `FloodedHallsClient.lua`: which way a
  texture slides could not be checked outside Studio.
- **The mouth** stays dark until it has you. A low growl from far below as you fall (`MawGrowl`); then the light
  comes up in it all at once (a sick green glow, red down its throat, never steady) and it SPRINGS open with a roar
  (`MawRoar`) and an impact frame, and time all but stops: from over you, you are a speck over a mouth that fills the
  shaft; from beyond its lower teeth, you hang over it; you think "No. No no no no."; then you drop, and from inside
  it you are seen coming down into it; from its side, in profile, the jaws shut like a trap. Its breath comes up out
  of it, and strands of saliva stretch between the jaws and snap as it opens.
- **Checked**: `check_halls.py` restates the body lying in the trough (on the floor, not through it), the mouth's
  fall (hanging well over the teeth while it is open, inside it before it shuts), where every shot is taken from (in
  the pit, out of the jaws, short of the mast), and the rest. `pass84.py`: 36 of 36.

### The people tell it with their bodies (eighty-fifth pass)

- Every line anyone says now comes with a gesture, chosen line by line (`TOLD` in `Townsfolk.lua`): a wave hello;
  both hands out explaining; pointing (Sal to the siren tower, Tobi at you: "Oh, it's you, isn't it."); a shrug;
  hands wrung over the water; a hand at the chin remembering; a hand up warning; leaning in close; the head down when
  it is sad. And small nods as they talk. Made with whichever hand is free (Sal's scoop, Pip's bucket, Dev's towels,
  Mr Barlow's lantern stay where they are; Mr Wick keeps both hands on his rod and tells it with his head and
  shoulders). Played on every client, smoothly (StoryClient), on top of the head that turns to you.
- It used to be one hand out and back, and only for the people with nothing in their hands: most of them stood still.
- **Checked**: `check_story.py` holds every person's gestures line for line with their lines, no gesture twice
  running, none for more than a quarter of all lines. `pass85.py`: 25 of 25.

**The full run after them**: 78 suites, 1396 of 1396 planted bugs caught, and src put back byte for byte.

## Before you test in Studio (passes 78 to 85): tested 2026-10-17

**Paste and import**
1. **Paste** the 16 Luau files that changed (`tools/paste_list.py` lists them; line 2 of each names its place),
   then run `python tools/paste_list.py --mark`.
2. **Sounds, 26 files** (MaterialSounds and StorySounds): delete the old four of each of saltCrunch, claySquish,
   cloudHush, leafBrush, snowPack and charcoalSnap from MaterialSounds first, then import `audio/materials/<name>_1`
   to `_4` for those six (24 files); and `audio/story/MawGrowl.wav` and `MawRoar.wav` into StorySounds (2 files; both
   have a stand-in until they are in).
3. **Meshes, 13 files**: `meshes/Whirl_*.fbx` into ReplicatedStorage/Assets/TileMeshes.

**Then play**
4. **PASTE CHECK** should say `everything is in place` (MawGrowl and MawRoar are listed as optional until imported).
5. **Steps**: in the lobby, wear a step sound from the shop and walk: a soft sound every few steps. On a level, only
   the chunks' own sounds. Stand on salt, clay, cloud, lamb's ear, snow and charcoal and listen.
6. **The shop**: hover or press the "i" on a few tiles; buy Embers and a new trail or aura and look at them.
7. **City Shore's dive**: the impact frames, the speed lines, the wind past you.
8. **A secret** with the pry bar (the first nook's): the tugs, what you think, the jump back.
9. **Sky Pools' slide**: the slide ahead into the clouds, the plunge, the wide shot of the pool below, bursting out.
10. **The Sunken City's whirlpool** from the pier, then the drain: the rings turning, the water pouring in.
11. **The Flooded Halls' flume**: lying back, the thoughts over your head, the water (downhill?), no judder; the growl,
    the mouth.
12. **Talk to everyone** (F): a gesture with each line.

## Codes, and the post box (seventy-seventh pass, 2026-10-15)

From your notes **(you)**: redeem codes (you chose them). The post box and the wording are mine **(suggested)**.

- **A red pillar box** on the deck beside the start pad (a plinth, the box, its cap, a slot and a small CODES plate),
  with Roblox's own prompt, "Post a code". It opens a small card of your own: a box to type the code in, "Post it",
  and a line saying what came of it ("That code has ended.", "You've posted that code already."...). A code that
  pays: "+100 tokens (Code HARROWBAY)".
- **Your codes live in one list**, `ShopCatalog.CODES` in `ShopCatalog.lua`: one line each,
  `{ code = "HARROWBAY", tokens = 100, ends = "2026-12-31" }`. Capitals and digits, 3 to 20 of them; players can type
  them in any case and with spaces. Each pays once a save, until the end of its `ends` day (UTC). To add a code, add
  a line and paste ShopCatalog (live servers pick it up as they restart; Roblox's "Restart servers" on the Dashboard
  does it at once). To end one early, set `ends` to an earlier day. HARROWBAY is there as an example: change it or
  take it out before you publish.
- **On the dashboard**: the custom event `CodeRedeemed` with the code in its first custom field, so you can see which
  of your posts brought players back; the tokens as a gameplay source "Code".
- **Safe**: the server checks every code against its own list (nothing a client says is a code unless it is in it),
  and posting goes through the shop's own one-request-at-a-time limit, so codes cannot be guessed quickly. Codes are
  the only way a shop request ever adds tokens, and the checks hold that to the one place.
- **The test panel**: "Codes: post again" forgets the codes you have posted. The Self-test posts a code of its own
  (once, twice, an unknown one and an ended one) and takes it out of the list again.
- **On every device**: thumb-sized buttons, inside the safe area, a phone's width at most; a controller starts on the
  box and B closes it; the cursor is free while it is up.
- **Checks**: `check_shop.py` and `check_hub.py` (`check_post_box`, and the box in the lobby's layout check);
  `blender/mutations/pass77.py` plants 45 bugs and every one is caught. The full run after it: 70 suites, 1224 of
  1224 caught, and src put back byte for byte.

## A review of passes 18 to 49 (seventy-sixth pass, 2026-10-15)

From your notes **(you)**: the same review for the older half (you chose it). No new features. Passes 22 to 28 had a
review of their own (the twenty-ninth pass), so this read the rest, server first: what a client can send, what is
written to Roblox's stores, and what a run, a fall and a purchase do.

- **Three things fixed**:
  - **A best time could be lost.** The leaderboard and your personal best read the old time and then wrote the new
    one if it was faster; when the read failed (a busy server, Roblox throttling), the write went ahead anyway, so a
    slower time could replace a better one. Both now compare and write in one step (Roblox's UpdateAsync): a better
    time is never overwritten, and two servers cannot cross. If the store does not answer at all, nothing is written.
  - **A stored 0 blocked every best after it.** A personal best saved as 0 (chill's "best", before chill had no
    clock) counted as unbeatable. It is now no time, so the first real run writes over it.
  - **An emote's stop could be used to flood.** "Stop" was passed on to every player each time any client sent it,
    with no limit. It is now passed on once, for someone who has an emote playing; a real stop (you move) is never
    held back.
- **Looked at and sound**: the second chance (spent before it is given, only within its window, only in Hardcore, never
  after the finish; the seventh fall's way into the back rooms offers none); the times that count and the route
  walked; the journal read back with the reader's name; the scene's word before the lobby; leaving, retrying and the
  mode switch, each only for a runner or only in the lobby; the board's reads, kept and shared.
- **Checks**: `check_hub.py` and `check_shop.py`; `blender/mutations/pass76.py` plants 11 bugs and every one is caught.
  The full run after it: 69 suites, 1179 of 1179 caught, and src put back byte for byte.

## A review of passes 50 to 74 (seventy-fifth pass, 2026-10-15)

From your notes **(you)**: a review pass before the Studio test (you chose it). No new features.

- **Read end to end**, for what the checks cannot see (two players at once, someone leaving partway, saves, timing):
  the tokens' every way in (runs, the story's reward, the daily chest, the caches, the challenges, the materials, the
  starter pack), loading and leaving, the passes, the story's moves between levels and its waits, the back rooms'
  ways in and out, the friends in a run, the admin's /levels, the boards and the journal on your own screen.
- **Two things fixed**, both on your own screen:
  - **A challenge done earlier today was told again on joining.** A save's three challenges and what is done of them
    can reach your screen one after the other, in either order; the card now says nothing until it has seen what is
    done once for those three.
  - **The journal's Materials tab kept pages your save no longer has** (after the Self-test, which finds every
    material and then puts your save back, or the panel's "Materials: 26 / none" pressed for none) until you
    rejoined. The tab now follows your save: a page for a material not in it is taken out, and the book's badge with
    it.
- **Looked at and sound**: each reward is paid once and only while the save is open, and every table kept per player
  is cleared when they leave; a finish too fast to be real pays nothing and counts for no challenge; the story's
  reward needs the last level reached on foot; the end of a story gives the lobby its light back (through the hub's
  ender when the last runner is home); someone in the back rooms counts as still playing, so a story waits for them
  and then goes on; nothing is found in the back rooms or the squish room; the server's own /levels command fires on
  the server.
- **Checks**: `check_hub.py` and `check_shop.py`; `blender/mutations/pass75.py` plants 7 bugs and every one is caught.
  The full run after it: 68 suites, 1168 of 1168 caught, and src put back byte for byte.

## The materials, as a collection (seventy-fourth pass, 2026-10-15)

From your notes **(you)**: a material collection (you chose it). How it is found, told and paid is mine
**(suggested)**.

- **Found by standing on one in a level**, the first time in a save: 5 tokens each. The server itself looks under
  every runner's feet twice a second (the platform's Material), so nothing a client says counts, and it counts only on
  a level: never in the squish room, where all 27 stand side by side, and never in the back rooms. City Shore alone
  has 26 of them; the jellyfish is in the Sunken City.
- **All 27**: 100 tokens more, the **swatch** trail (earned only, like the green ribbon: its tile says "Find all 27")
  and a badge (`ShopCatalog.BADGES.materials`, 0 until you make it).
- **Told quietly**: a soft chime as each is found, nothing on the screen during the run; at the run's end the usual
  pill counts them in (a medium run and two found: "+30 tokens (2 new materials)"), with "and the swatch trail" when it finishes the set.
- **In the journal**: a fourth tab, Materials, a page for each found: "Material 5 of 27", what it does underfoot (the
  hint's words) and what the Hold kept it from ("Kept by the Hold: A jar of Hale's honey, from the hives on the
  Novelty Works roof."). The ones you had already come read; each new one is unread (the book's badge), with no line
  in the corner. The four tabs share the row and their names shrink to fit on a phone.
- **In the lobby**: a second notice board beside the challenges board (the same posts, frame and roof), "Materials
  found 12 of 27" and three columns of names, each beside its colour, and a "?" for one still to find. Yours only.
- **Kept in your save** (`Materials`). On the dashboard: custom events `MaterialFound` (how many so far) and
  `AllMaterials`; the tokens as a gameplay source "Material".
- **The test panel**: "Materials: 26 / none" marks every one found but soap (on City Shore, to finish the set on the
  next run); pressed again, none found and the swatch trail taken back. The Self-test finds one (paid once, a made-up
  one refused) and the last of them (the trail and the bonus), and puts your save back.
- **Checks**: `check_shop.py` and `check_hub.py` (the board in the lobby's layout and drawn on your own screen);
  `blender/mutations/pass74.py` plants 61 bugs and every one is caught. The full run after it: 67 suites, 1161 of
  1161 caught, and src put back byte for byte.

## The starter pack (seventy-third pass, 2026-10-14)

From your notes **(you)**: a starter pack (you chose it). What is in it and its price are mine **(suggested)**; change
them in `ShopCatalog.lua`.

- **A game pass, 99 Robux**: 500 tokens and the **sea glass** trail (soft green glass), a trail you cannot get any
  other way. A pass rather than a developer product because Roblox itself sells a pass only once, so nobody can buy
  it twice by accident. For comparison, 300 tokens on their own are 129 Robux.
- **Given once a save**, the moment the pass is found: on joining, on a late answer from Roblox, or the moment it is
  bought ("+500 tokens (Starter pack) and the sea glass trail"). If the server stops before the save is written, it
  is given again next time, and never twice once saved.
- **In the shop**: first in Featured with a "Once only" badge, and off Featured once it is yours (still in Passes,
  Owned). The sea glass tile says "Starter pack" where a price would be; pressing it says what is in the pack and
  "See it" opens Passes. The new player's way to the shop (after their first run) opens on Featured, so it is the
  first thing they see there. No pop-up anywhere.
- **Fixed on the way**: a pass you own (VIP, 2x tokens) now shows Owned in the shop; before, it still showed its
  price, and pressing it brought up Roblox's own "you already own this".
- **To sell it**: Creator Dashboard, your game, Monetization, Passes: create "Starter pack" at 99 Robux (an icon of
  sea glass would suit), then put its id in `passId` on the `StarterPack` line of `ShopCatalog.lua`. Until then the
  paste check lists it under "not on sale yet" and the shop says so.
- **On the dashboard**: its tokens as an in-app purchase source "StarterPack" in the economy view; its prompt
  closing as the custom event `PassPrompt` like every pass.
- **The test panel**: "Starter pack on/off" gives it as if bought (the pill, the trail in Trails, Owned in Passes, gone
  from Featured), and takes it all back when pressed again. The Self-test gives it twice (paid once), sees the pass
  Owned and tries to buy the trail on its own (refused); it puts your save back.
- **Checks**: `check_shop.py`; `blender/mutations/pass73.py` plants 34 bugs and every one is caught. The full run after
  it: 66 suites, 1100 of 1100 caught, and src put back byte for byte.

## Daily challenges (seventy-second pass, 2026-10-14)

From your notes **(you)**: daily challenges (you chose them). The list, the amounts and the board are mine
**(suggested)**.

- **Three a day for each player**, from nine (`ShopCatalog.CHALLENGES`): finish City Shore (30 tokens), the Sky Pools
  (35), the Sunken City (40), the Flooded Halls (45); finish a run in Hardcore (40); set a new best in Hardcore (50);
  finish a long run (40); finish a run with a friend (40); finish 3 runs (50). Shuffled by the day (UTC, the daily
  chest's clock), so players at the same point get the same three; a level's challenge is only given once that level
  is open in your own save. They are picked the first time your save sees the day and stay put until midnight UTC,
  when everyone in the server gets new ones.
- **Done by finishing runs**, each paid once that day, on the run's own pill (a medium run's 20 and a
  challenge's 40: "+60 tokens (Challenge done)"). The card says which: "+40, Challenge done, Finish City Shore. 1 of 3
  done today."
- **A notice board in the lobby**, by the daily chest in the back-left corner: two posts on the deck, the panel held
  between them in a frame, a little roof on the posts. What is written on it is your own (your three, each ticked
  green with "Done" as you do it, "Finish 3 runs (1 of 3)" as you go, and "New ones in 5h 12m"); anyone else sees
  theirs. No HUD element anywhere.
- **Kept in your save** (`Challenges`). On the dashboard: the custom event `ChallengeDone` (its reward, the challenge
  in the first custom field) and the tokens as a gameplay source "Challenge".
- **The test panel**: "Challenges: new three" gives you a fresh three with nothing done. The Self-test checks three
  are picked with none on a locked level, and that one pays once a day and the third run counts; it puts your save
  back.
- **Checks**: `check_shop.py`, and `check_hub.py` (`check_challenge_board`: the posts on the deck, the panel between
  them, the frame against it, the roof on the posts; and the board in the lobby's layout check);
  `blender/mutations/pass72.py` plants 55 bugs and every one is caught. The full run after it: 65 suites, 1066 of
  1066 caught, and src put back byte for byte.

## A friend in the run (seventy-first pass, 2026-10-14)

From your notes **(you)**: the friends bonus (you chose it). How it is told, and the numbers, are mine **(suggested)**.

- **A run finished with a Roblox friend in it pays a fifth more** (`ShopCatalog.REWARD.FRIEND = 1.2`: 20 tokens
  become 24), worked out after Hardcore and a new best and before the 2x pass, which doubles it with the rest. A
  friend counts when they have been in the same run (started it with you, or joined it late) and are still in the
  server when you reach the end; you need not finish together. Nobody counts as their own friend, and a friend who
  has left the server no longer counts. Roblox is asked once a pair (`Player:IsFriendsWith`); if it does not answer,
  that counts as no and it is asked again next time.
- **Told three ways, none of them new on screen**: the lobby's card, a few seconds into the run, "+20%, Running with a
  friend" (once while you are in the server, not every level of a story); the usual pill at the end, "+24 tokens (With
  a friend)"; and Roblox's own invite screen from the pause menu's Invite, which now says "Come and play Harrow Bay with
  me: a friend in your run pays 20% more tokens." The first visit's "Earn tokens" page mentions it too.
- **On the dashboard**: the custom event `RunWithFriend` (the level), to see whether bringing a friend catches on.
- **The test panel**: "Friend in runs on/off" (Studio only; the players in a Studio test are nobody's friends): with it
  on, the next run's card says a friend is with you and its pill says "With a friend". The Self-test checks a run
  alone pays no share, the panel's friend counts, and the share is a fifth; it puts the real run's players back.
- **Checks**: `check_shop.py`; `blender/mutations/pass71.py` plants 34 bugs and every one is caught. The full run after
  it: 64 suites, 1011 of 1011 caught, and src put back byte for byte.

## Hidden token caches (seventieth pass, 2026-10-14)

From your notes **(you)**: hidden token caches (you chose them). What each one is, and where, is mine **(suggested)**.

- **One on every level**, something somebody kept, with a few coins in it: on City Shore, Sal's float (a red biscuit
  tin, "SAL'S FLOAT. DO NOT TOUCH."); on Sky Pools, a swim bag with the pool money and a ticket for the roof; in the
  Sunken City, a jam jar of coins "FOR THE BUS HOME"; in the Flooded Halls, Mrs Venn's tea tin. Each stands in the far
  corner of a nook of its own (the little platforms off the route, like the pry bar's and the letters'), about two
  thirds of the way along, catching the eye with a small glint; where no nook fits, it is tucked beside the route on a
  stable chunk past that point.
- **Take it** (Roblox's own prompt): 25 tokens the first time in a save ("+25 tokens (Hidden cache)"), and a line in
  your journal saying what it was. Once taken it is gone from your screen for good (it is marked like a letter), so
  next time you know you have it; anyone else still sees theirs. Kept in your save (`Caches`), and on the dashboard
  as the custom event `CacheFound` (the level) and a gameplay source "Cache".
- **The Self-test** finds one (paid once, then nothing) and puts your save back.
- **Checks**: `check_story.py` (one for each level, no dashes in their words, on their floor, glinting, marked, paid,
  in the journal, in a nook or beside the route) and `check_shop.py` (once a save, the catalogue's 25);
  `blender/mutations/pass70.py` plants 19 bugs and every one is caught. The full run after it: 63 suites, 977 of 977 caught,
  and src put back byte for byte.

## The daily chest (sixty-ninth pass, 2026-10-14)

From your notes **(you)**: the daily reward (you chose it). The amounts and the chest are mine **(suggested)**.

- **A wooden chest banded in brass** on the lobby's deck (left of the start pad, mirroring the back door), with
  Roblox's own prompt. Open it once a day for tokens: 20, 30, 40, 50, 60, 80, then 120 on the seventh day and every
  day after while the streak lasts (`ShopCatalog.REWARD.DAILY`). Opened the day after the last time, the streak goes
  on; miss a day and it starts again from 20. Days are UTC days (Roblox's servers keep that clock), so the next chest
  opens at midnight UTC.
- **On your own screen**: the prompt says "Open" or "Opened today"; opening it lifts the lid (for you only), the usual
  "+N tokens (Daily chest, day 3)", and the vote card says "Come back tomorrow for day 4". Opened again too soon, the
  card says how long until the next one and which day you are on. No HUD element anywhere.
- **Kept in your save** (`DailyDay`, `DailyStreak`). On the dashboard: the custom event `DailyChest` (the streak's
  day), and the tokens as a gameplay source "Daily" in the economy view.
- **The test panel**: "Daily: next day" makes your last opening yesterday, so the next one goes on the streak. The
  Self-test opens it (once, too soon, the next day, and after a missed day) and puts your save back.
- **Checks**: `check_shop.py` and `check_hub.py` (`check_daily_chest`, and the chest in the lobby's layout check);
  `blender/mutations/pass69.py` plants 24 bugs and every one is caught. The full run after it: 62 suites, 958 of 958 caught,
  and src put back byte for byte.

## A reward for finishing the story (sixty-eighth pass, 2026-10-14)

From your notes **(you)**: the story reward (you chose it from the four next builds I offered). The amount and the
ribbon are mine **(suggested)**.

- **Finishing the story pays a bonus**, on top of the last level's own run: 150 tokens, 225 in Hardcore, and doubled
  by the 2x pass, the same rules a run follows (`ShopCatalog.REWARD.STORY`, `ShopCatalog.storyReward`). Its pill says
  "Story complete" and stands above the last level's own "+N tokens".
- **And the green ribbon**: a trail, the key's own green ribbon (the one by Hill House's door in the lore), the only
  thing in the shop that cannot be bought. It is in the shop under Trails from the start, its tile grey and saying
  "Finish the story" where a price would be; pressing it says what it takes. Finish the story and it is yours: "Put
  on" like any trail. The bonus is paid every time a story is finished; the ribbon the first time.
- **Only for a story really finished**: given at the end of its last level, for a route walked, and only to someone
  whose own walking reached that level (their saved place in the story), so joining a story late at its last level
  does not earn it. A story resumed from a save does, if you walked the levels before it.
- **The Self-test** checks the bonus and the ribbon are given, and that the ribbon is never sold.
- **Checks**: `check_shop.py` (an item earned and never sold is allowed, earned by the story only, and the story's
  bonus is the one new way tokens go up); `blender/mutations/pass68.py` plants 17 bugs and every one is caught. The full
  run after it: 61 suites, 934 of 934 caught, and src put back byte for byte.

## In the back rooms, not in the lobby (sixty-seventh pass, 2026-10-14)

From your notes **(you)**: work a bit more. What is mine **(suggested)**: a loose end of the corridor into the back
rooms.

- **Someone who went into the back rooms from the lobby** was still one of the lobby's players as far as the vote was
  concerned, so a countdown started by others in the lobby came up on their screen in yellow rooms a long way off
  (they were never pulled into the run). Now going in packs the vote card away, as a run's start does, and they are
  left out of what the lobby says until they are back (`HubService.hubPlayers`).
- **Checks**: `check_backrooms.py` (and `check_squishroom.py`'s squish room line, unchanged in what it holds);
  `blender/mutations/pass67.py` plants 3 bugs and every one is caught. The full run after it: 60 suites, 917 of 917 caught,
  and src put back byte for byte.

## The back rooms are the sixth secret (sixty-sixth pass, 2026-10-14)

From your notes **(you)**: work a bit more. What is mine **(suggested)**: finding the back rooms told the way every
other secret is.

- **The first time your save falls into the back rooms**, once the screen has come back, the secret's scene plays: the
  camera drifts in on Mrs Venn's notice, the low sting, "The back rooms. Staff only. You came down once too often.",
  and its card ("Secret 1 of 6", or however many you have). Her notice goes into your journal under Secrets. Never
  again after that, and not from the lobby's corridor (you have found them by then).
- **Six secrets now**: the five on the levels, and this one under all of them (`Interactables.SECRETS.backRooms`;
  `LORE.md`'s table has the row).
- **Checks**: `check_backrooms.py` and `check_story.py`; `blender/mutations/pass66.py` plants 10 bugs and every one is
  caught. The full run after it: 59 suites, 914 of 914 caught, and src put back byte for byte.

## The lobby's back corridor leads there (sixty-fifth pass, 2026-10-14)

From your notes **(you)**: work a bit more. What is mine **(suggested)**: the teaser door finally wired, as its own
comment always said it would be.

- **Once you have found the back rooms by falling** (kept in your save, `FoundBackRooms`), the lobby's yellow back
  corridor takes you there: walk to its end round the corner and you are in, with the same cut to black. The way out
  brings you back to the lobby. For anyone who has not found them it is only the end of a corridor, which is what
  keeps them a secret. From the lobby only (not from a run, not from the squish room).
- **The corridor is walkable now.** Lobby scenery does not collide, and the corridor was scenery: stepping through the
  frame dropped you through its carpet and the lobby's catch put you back at the spawn. Its floor and walls are solid.
- **Falling in is a cut to black**, at once, so the move is never seen: it reads as going through the floor.
- **The test panel**: "Back rooms" takes you there now (as a fall would, in a run) and counts them as found, so the
  corridor can be tried straight after.
- **The mutation runner** (`run_all.py`) runs a suite again, after putting src back, when it died on a Windows file
  error (a file held for a moment by a virus scanner or an indexer): twice in a row on the Sunken City's files in the
  last run, and clean on its own.
- **Checks**: `check_backrooms.py`; `blender/mutations/pass65.py` plants 10 bugs and every one is caught. The full run
  after it: 58 suites, 904 of 904 caught, and src put back byte for byte.

## The back rooms (sixty-fourth pass, 2026-10-14)

From your notes **(you)**: the Backrooms secret level, found by falling too many times in one run (ROADMAP section 5:
yellow rooms, humming lights, damp carpet, never announced). How is mine **(suggested)**, and in the lore it is
what Mrs Venn calls it: the back rooms of the baths. Staff only.

- **The way in**: the seventh fall in one run (`BACKROOMS_FALLS` in Bootstrap), in either mode, goes through the
  floor instead of back to the route: a blink of black and you are standing in the back rooms. Once a run, never
  announced. A Hardcore fall is still a fall (the clock goes back to nothing).
- **What is there** (`BackRoomsService`, new, built once at server start far from everything): a maze of yellow rooms
  and corridors (34 by 22 tiles of 4 studs), damp beige carpet, a low ceiling resting on the walls, and a tube panel
  set into it every third tile, each a real light shining down, warm, modest, and no floor further than three tiles
  from one; one tube near the middle stutters now and then (down to a third, never off). A sealed staff room with a
  locked door marked STAFF ONLY that nobody can get into. Mrs Venn's notice on the wall where you arrive. The hum is
  the baths' own (BathsHum, through AmbienceService), with the Hold's drone under it. The lobby's yellow back door,
  the teaser, is built in the same palette and stays a door.
- **The way out**: a door marked WAY OUT (a green sign with its own small light) in the far wall, fifty tiles' walk
  from where you arrive, with Roblox's default prompt, "Go back". It puts you where the fall that sent you would
  have: the start in Hardcore (clock reset), your checkpoint in Chill; the lobby if your run has ended meanwhile.
  Leaving from the pause menu works as anywhere. Reset there puts you back on the level.
- **While you are there** your client counts you as in the back rooms (`InLevel` is "backRooms"): their hum plays,
  the level's own weather (Sky Pools' storm, the Halls' lamps) waits, and the kill plane leaves you alone. In a
  story, the others wait for you as for anyone still playing.
- **Found**: a custom event `BackRoomsFound` on the dashboard, and a seventh badge, `ShopCatalog.BADGES.backRooms`,
  off until you make it like the others. The Self-test checks the back rooms were built with their one way out.
- **Checks**: `blender/check_backrooms.py`, new, the fourteenth checker (the map closed all round, every floor tile
  reachable, the sealed room sealed, the way out far; the light; nothing floating; far from everything; the way in
  and out); `blender/mutations/pass64.py` plants 26 bugs and every one is caught.

## Roblox badges, ready to switch on (sixty-third pass, 2026-10-14)

From your notes **(you)**: work a bit more (and the game is meant to earn). What is mine **(suggested)**: badges for
what the game now has an ending for, built so that nothing happens until you make them.

- **Six badges**: one for each level played to its end (City Shore, Sky Pools, the Sunken City, the Flooded Halls),
  one for the story played to its end, and one for a whole story in Hardcore (the one that goes on the story
  leaderboard). Awarded by the server only for what was really played: a level's for a run that pays its tokens (a
  walked route, not impossibly fast), the story's for a last level walked.
- **Switched off until you make them**: every id in `ShopCatalog.BADGES` is 0, and with 0 nothing is asked of
  Roblox. To switch one on, make the badge on the Creator Dashboard (your game, Engagement, Badges; a few a day are
  free, with an image you upload), copy its id into `ShopCatalog.BADGES` (the four levels by level number, then
  `story` and `storyHardcore`), and paste ShopCatalog again. The paste check lists the badges still without an id.
- **Each badge is asked for once per player a session** (Roblox limits badge calls); one already owned is Roblox's to
  ignore, so someone who finished a level before its badge existed gets it the next time they finish that level.
- **Checks**: `check_shop.py`; `blender/mutations/pass63.py` plants 14 bugs and every one is caught. The full run after
  it: 56 suites, 868 of 868 caught, and src put back byte for byte.

## The move between a story's levels, and the Self-test sees the story (sixty-first and sixty-second passes, 2026-10-14)

From your notes **(you)**: work a bit more. What is mine **(suggested)**: a fault in the sixtieth pass, found by
walking the story through, fixed; and the Self-test taught the story.

- **The move between a story's levels** used to take the last level down, build the next, and only then put
  everyone at its start. In between they stood on nothing: they fell through the space the last level had left (on
  City Shore, from the sea far below), and anyone who dropped past the new level's kill plane before being put on it
  took a Hardcore fall at its start, death card and all. Now the screen goes to black (0.6 seconds), everyone in the
  story is held where they stand (anchored, and passed over by the kill plane) while the levels change, then they
  are at the next start and the screen comes back. One move at a time: someone leaving during it cannot start a
  second. (The old gate that forbade any fade to black in Bootstrap, so the dive's blackout could not come back, now
  looks only at the dive.)
- **The Self-test** checks the story's place in your save is kept, read back and kept in range (the server's half),
  and that the Story pad is in the lobby and open (the client's half).
- **Checks**: `check_hub.py` and `check_shop.py`; `blender/mutations/pass61.py` and `pass62.py` plant 12 and 3 bugs
  and every one is caught. The full run after them: 55 suites, 854 of 854 caught, and src put back byte for
  byte.

## Story mode (sixtieth pass, 2026-10-13)

From your notes **(you)**: build story mode, with my suggestions for the four open questions (a Story pad; one
clock and a leaderboard of its own; a death restarts only the level you are on; progress saved, both modes). How the
pieces fit is mine **(suggested)**.

- **The Story pad**: a sixth pad on the lobby's level row, between the four levels and the sandbox ("Story, 9:14 am
  to midnight", a morning-gold window). Voted for like a level, with Chill or Hardcore and a length, and always
  open. Its leaderboard shows on the lobby board when it is chosen.
- **The four levels one after another**: when a level's ending has been watched, the next one is built and you are
  put at its start, with no lobby in between. LEVEL COMPLETE says "Story 2 of 4. Next: The Sunken City"; after the
  Flooded Halls it says "Story complete", with the story's time in Hardcore, and then everyone goes home.
- **Together**: a group plays it as one. Whoever finishes a level first waits in the lobby (their vote card says how
  many are still playing) and is brought back in for the next level when the rest are done. After 150 seconds the
  story goes on without anyone still playing; they are sent to the lobby and told. Leaving from the menu, or the
  server, takes you out of the story; if that leaves only people waiting, they go on.
- **The clock**: in Hardcore, the story's time is each level's own fair time added up, so a fall restarts only the
  level you are on (and its clock). It goes on the story's own leaderboard (and your best) only for a whole story,
  played from City Shore in one go with every level's time counted (no second chance, no Near the end, not joined
  late). Chill has no clock, as everywhere.
- **Saved**: where you got to is kept in your save (`StoryAt`, a level walked counts). Stopped partway, the story
  goes on from there next time: from the level the furthest-behind player in the room is on, so nobody misses one.
  After the last level it goes back to City Shore. Every level finished in the story counts as finished for the
  lobby's locks too, and pays its tokens as usual.
- **The test panel**: "Story from the start" puts your save's place back to City Shore. "Near the end" works in a
  story (that level's time and place then do not count; the story still goes on).
- **On the dashboard**: custom events `StoryStarted` (the level it began from) and `StoryFinished` (1 for a fair
  whole story).
- **Checks**: `check_hub.py` (`check_story_mode`; the pad row's width now counts the Story pad);
  `blender/mutations/pass60.py` plants 31 bugs and every one is caught. The full run after it: 53 suites, 839 of 839
  caught, and src put back byte for byte.

## One run at a time (fifty-ninth pass, 2026-10-13)

What is mine **(suggested)**: a bug found while building the story, fixed.

- **Nothing starts a run while anyone is still out on a level.** There is one level per server, and the lobby's Start
  pad did not check: someone who finished first, back in the lobby, could step on it and build a new level over the
  one the others were still playing, clearing the floor from under them. Now Start (and a vote, and a countdown that
  would end during a story's next level) waits until everyone is back, and whoever steps on it is told how many are
  still playing.
- **Checks**: `check_hub.py` (`check_one_run_at_a_time`); `blender/mutations/pass59.py` plants 10 bugs and every one
  is caught.

## Every level open for an admin (fifty-eighth pass, 2026-10-13)

From your notes **(you)**: a way to give yourself access to every level, locked or not, like an admin. How is mine
**(suggested)**.

- **Type `/levels` in chat** to open every level for yourself; type it again to go back to your own progress. Kept in
  your save (`AdminOpen`), so it stays on between sessions. Your real progress is untouched and still recorded when
  you finish a level. The vote card tells you which way it went.
- **Who is an admin**: you, the game's owner (for a group game, the group's owner), anyone whose user id you add to
  `ADMIN_IDS` at the top of the admin section in `EconomyService.lua`, and anyone in Studio. Anyone else typing
  `/levels` gets nothing.
- **What others see**: a run is the whole room's, so while you are in a server with it on, the room can vote for any
  level and play it with you. Nobody else's progress changes unless they finish a level themselves.
- **The chat**: a proper chat command where the place uses the new chat (the line is never shown to anyone); on the
  old chat, a chat line the server reads.
- **Checks**: `check_shop.py`; `blender/mutations/pass58.py` plants 14 bugs and every one is caught.

## Getting further keeps a level open, and new players are told (fifty-seventh pass, 2026-10-12)

From your notes **(you)**: work a bit more. What is mine **(suggested)**: a hole in the fifty-first pass, closed.

- **A level is open when anyone here has finished the level before it, or any level after that.** It used to look
  only at the one before, so a player carried into Sky Pools by a friend who then finished it would, alone later,
  find Sky Pools locked again (no City Shore finished) and the Sunken City open. Now getting further keeps
  everything behind you open: finishing Sky Pools keeps Sky Pools open and opens the Sunken City, City Shore or
  not. The signs still say what opens a locked level ("finish City Shore first"); the Self-test expects the same.
- **New players are told**: the welcome's second page now says "Each level is a route of materials to its end,
  and finishing one opens the next", and the guide's first step "Step on City Shore, the first level. Finishing
  it opens the next."
- **Checks**: `check_hub.py` and `check_shop.py`; `blender/mutations/pass57.py` plants 6 bugs and every one is
  caught. The full run after it: 50 suites, 783 of 783 caught, and src put back byte for byte.

## The climb through the levels, on the dashboard and in the Self-test (fifty-sixth pass, 2026-10-12)

From your notes **(you)**: work a bit more. What is mine **(suggested)**: now that levels open in order, the two
numbers worth watching once the game is live, and the Self-test exercising the locks for real.

- **On the Creator Dashboard** (Analytics, custom events; they appear once real players have played):
  `FirstFinish_1` to `FirstFinish_4`, each level's first finish in a save (City Shore, Sky Pools, the Sunken City,
  the Flooded Halls; so how many players open each level, and where they stop), and `LockedPad_2` to
  `LockedPad_4`, players who stepped on a level that was still locked for them (once per player and level a
  session). The second is the one to read before deciding whether anything to do with opening levels is worth
  selling.
- **The Self-test's server half** now opens and locks a level through the lobby itself: City Shore open; City
  Shore finished in your save opens Sky Pools; taken back, Sky Pools locks again (unless someone else in the server
  has finished City Shore). Your save is put back afterwards, as before, and the lobby looks at it again. (If your
  vote was on Sky Pools it moves back to City Shore.)
- **Checks**: `check_hub.py` (`check_dashboard`) and `check_shop.py`; `blender/mutations/pass56.py` plants 13
  bugs and every one is caught. The full run after it: 49 suites, 777 of 777 caught, and src put back byte
  for byte.

## Near the end, and the Self-test sees the pads (fifty-fifth pass, 2026-10-12)

From your notes **(you)**: work a bit more. What is mine **(suggested)**: a quicker way to test the last four
passes in Studio.

- **"Near the end"** on the test panel (Studio only): in a run, it puts you at a checkpoint about eight chunks
  before the finish, facing on, so a level's last stretch and its ending can be seen without playing all of it:
  the storm building by the Sky Pools slide, the lamps failing behind you in the halls (those already behind you
  are low at once, the next ones fail as you walk), and every level's ending. A run skipped like this counts for
  nothing: no tokens, no time, no level opened (Output says so), so a test cannot fake its way into a save. A fall
  after it sends you back to that checkpoint, not the start.
- **The client's half of the Self-test** also looks at the lobby (press it there): City Shore open, every locked
  pad boarded up and saying so, every open one without boards; and the VIP tag over your head when you have VIP
  (or after "VIP on/off"), and none without.
- **Checks**: `check_shop.py`; `blender/mutations/pass55.py` plants 14 bugs and every one is caught. The full run after
  it: 48 suites, 764 of 764 caught, and src put back byte for byte.

## A level opened is told as you come back (fifty-fourth pass, 2026-10-12)

From your notes **(you)**: work a bit more. What is mine **(suggested)**: finishing a level now says what it
opened.

- **Coming back to the lobby from a run that opened a level**, the vote card says so, with a two-note chime:
  "Sky Pools is open. A new level. Step on its pad to vote for it." (or two names, if one run opened two). Each
  player coming back is told what was shut when they went into the run and is open now, so it is said once,
  to everyone who was there (not only whoever finished), and a level opened by someone joining with it already
  finished is not announced. After five seconds the card goes back to the tally, or away; it can no longer come
  back to a countdown from before the run.
- **Checks**: `check_hub.py`; `blender/mutations/pass54.py` plants 12 bugs and every one is caught.

## The lamps behind you fail, in the Flooded Halls (fifty-third pass, 2026-10-12)

From your notes **(you)**: Flooded Halls, lights fail behind you (you chose it from the four). How is mine
**(suggested)**.

- **The roof lights two bays and more behind you** (the ceiling lamp over the walkway in every bay) stutter for
  half a second with a faint click, then sink over a second to a low glow (30% of their light, the panel a dim
  warm grey). The bay you are in, the one behind it and everything ahead stay lit, and the windows are never
  touched, so nothing is ever dark. Sent back past them (a checkpoint behind you), they come up again over a
  second. On your own screen only (`FloodedHallsClient`, "The lamps behind you"); each roof light now says how
  far along the route it hangs (`FloodedHallsService`, attribute `Along`). The one fitting that already fails for
  everyone stays the server's. Nothing during the ending, and nothing off the level.
- **Checks**: `check_halls.py` (a low glow, never under a quarter; the lamp over you kept; fades of at least half
  a second; a stutter that never goes out; only the roof lights; the light itself dimmed, not just the panel);
  `blender/mutations/pass53.py` plants 16 bugs and every one is caught. The full run after the four passes: 46 suites,
  738 of 738 caught, and src put back byte for byte.

## A storm by the slide, in Sky Pools (fifty-second pass, 2026-10-12)

From your notes **(you)**: Sky Pools, a storm near the slide (you chose it from the four). How is mine
**(suggested)**.

- **As you near the slide's mouth** (from 200 studs, all there at 60: the last stretch of any run, checked
  against every laid route), the cloud sea round the tower darkens toward a slate grey (the nearest clouds
  most, the far ones not at all; the mist over them too), the light drops a little (a colour correction:
  brightness down 0.06, a touch less colour, a cool tint), and every 9 to 16 seconds lightning lights the
  cloud tops below: a real light just over them, twice, soft and brief. Under the clouds, on the slide down to
  the final pool, it clears again. Eased over seconds and written in small steps; on your screen only
  (`SkyPoolsClient`, "The storm by the slide"); gone at once off the level, with the clouds given back their
  own colours.
- **Checks**: `check_skypools.py` (begins in the last half of every laid run and reaches its end; eased; never
  dark; clears under the clouds; only on Sky Pools; lightning real, soft, cleared and only at the height of it);
  `blender/mutations/pass52.py` plants 16 bugs and every one is caught.

## Levels open in order (fifty-first pass, 2026-10-12)

From your notes **(you)**: levels unlock in order (you chose it from the four). How is mine **(suggested)**.

- **City Shore is always open; each level after it opens once the one before is finished** (Sky Pools after City
  Shore, then the Sunken City, then the Flooded Halls; the sandbox is always open). What you have finished is
  kept in your save (`Finished`), marked when a run you really played ends (the same test that pays tokens: a
  walked route, not impossibly fast). **It opens for the whole server**: the room votes on one level for
  everyone, so a level is open when anyone here has finished the one before. Bring a friend who has, and it is
  open for you too.
- **On the lobby pads**: a locked level's window is dimmed and boarded up (two planks across it, lying on the
  pane with their ends on the frame), and its sign says "Locked: finish City Shore first". Stepping on it takes
  no vote; the vote card tells you (to you alone) which level it is and what opens it, then goes back to the
  tally. A locked level can never win a vote; a vote left on one that locks again (whoever opened it left) goes
  back to City Shore.
- **The test panel**: "Levels open/locked" finishes every level in your save, or none. The Self-test checks that
  a run finished at once opens nothing.
- **Checks**: `check_hub.py` (`check_levels_open_in_order`); `blender/mutations/pass51.py` plants 19 bugs and
  every one is caught.

## A VIP tag over your head (fiftieth pass, 2026-10-12)

From your notes **(you)**: a VIP tag over heads (you chose it from the four). How is mine **(suggested)**.

- **A VIP player has a "VIP" tag over their head** in the lobby and the squish room, for everyone in the server to
  see: a small rounded pill in the VIP pass's own lilac, sized in studs so it shrinks with distance, drawn to 80
  studs, over the name Roblox shows (`EconomyService.vipTag`). Put on with the rest of what they wear, put away
  on a level (a run has nothing over anyone) and back in the lobby, and taken off if the pass is not theirs. The
  shop's VIP tile says so: "A VIP tag over your head and in chat, and the gold sparkle".
- **The test panel**: "VIP on/off", since a pass cannot be owned in Studio.
- **Checks**: `check_shop.py`; `blender/mutations/pass50.py` plants 9 bugs and every one is caught.

## The self-test compares what is shown (forty-ninth pass, 2026-10-12)

From your notes **(you)**: work a bit more. What is mine **(suggested)**: the Self-test's server half also checks
that what other players and your own screen are shown matches your save, once it is put back: the Keepsakes count
in the player list against the journal's keepsakes, and the tokens your screen reads against the save's.
`check_shop.py`; `blender/mutations/pass49.py` plants 3 bugs and every one is caught. The full run after this pass: 43 suites,
678 of 678 caught, and src put back byte for byte.

## Your collection in the player list (forty-eighth pass, 2026-10-12)

From your notes **(you)**: work a bit more. The roadmap's "a way to show your collection to other players" is
built here; how is mine **(suggested)**. And the "Before you test in Studio" list below is rewritten in the order
you would do it.

- **A Keepsakes column in Roblox's own player list** (leaderstats, `EconomyService.showCollection`): how many of
  the 27 keepsakes each player has found, for everyone in the server to see. No interface of the game's own:
  it is the list Roblox already shows (top right; folded away on a phone until opened). Counted from the journal
  kept between sessions, so it is your whole collection; set when you join, raised the moment you pick a keepsake
  up, and right again after the test panel empties the journal or the self-test puts your save back.
- **Checks**: `check_story.py`; `blender/mutations/pass48.py` plants 6 bugs and every one is caught.

## The self-test sees what was built, and the server answering (forty-seventh pass, 2026-10-12)

From your notes **(you)**: work a bit more. What is mine **(suggested)**: two more things the Self-test checks for
real, both about pieces working together.

- **What was built at the start** (the server's half): the keepsake shelf in the squish room, a toy and a card for
  every keepsake and the board on top (if the room is still being built when you press it, this says 0 and
  fails, so press it again a little later); and your own statue in the lobby, marked as yours.
- **The server answering this screen** (the client's half): the save, the journal and the leaderboard, asked
  through the game's own remotes, each one answering (a save that says it is not ready yet does not count).
- **Checks**: `check_shop.py`; `blender/mutations/pass47.py` plants 6 bugs and every one is caught.

## The client's self-test sees the cursor, the pause menu and the death card (forty-sixth pass, 2026-10-12)

From your notes **(you)**: work a bit more. What is mine **(suggested)**: the client half of the Self-test covers
the last screens and the one bug a mouse player would feel most.

- **The cursor**: with third person locked (the usual view), every screen the self-test opens must free the
  cursor to press its buttons, checked for real: the shop, the journal, the emote picker, the pause menu and the
  death card (the one that was missed in the thirty-fifth pass). If you have freed the cursor yourself (Ctrl,
  or first person) the check says so and passes.
- **The pause menu** opened and closed (PauseMenuService.setOpen and isOpen, new, the same as the tab and keys),
  and **the death card** shown, its choices after their three seconds, then put away. The client's half now
  takes about ten seconds.
- **Checks**: `check_shop.py`; `blender/mutations/pass46.py` plants 9 bugs and every one is caught; all 39
  suites together catch 663 of 663.

## The self-test's client half (forty-fifth pass, 2026-10-11)

From your notes **(you)**: work a bit more. What is mine **(suggested)**: the same Self-test button now runs a
half on your own screen too.

- **The screens a player opens**, opened and closed for real: the shop, the journal (at the keepsakes) and the
  emote picker, each said `pass` or `FAIL` in Output under `SELF-TEST (client)`. A screen that throws, does not
  show, or will not go away is named, instead of being found only when someone presses it. It takes about three
  seconds and leaves everything closed.
- **Checks**: `check_shop.py`; `blender/mutations/pass45.py` plants 6 bugs and every one is caught.

## The self-test, wider (forty-fourth pass, 2026-10-11)

From your notes **(you)**: work a bit more. What is mine **(suggested)**: more of the game run for real by the
test panel's Self-test.

- **Now also**: a second chance spent once and refused the second time; a note the server does not know (a
  client asking for tokens through the first-five-minutes notes) changing nothing, and one it does know setting
  its flag; the shop told the save's tokens. Then, after the save is put back, **the stores**: the leaderboard
  read, then read again at once from what LeaderboardService kept (no second wait), and a personal best read.
  With the data stores off in Studio the board answers empty, which still counts as an answer.
- **Nothing waits while the save is changed** (checked): anything that happened to the save during a wait would
  be wiped when it is put back, so the store reads, which wait on Roblox, come after.
- **Checks**: `check_shop.py`; `blender/mutations/pass44.py` plants 6 bugs and every one is caught; all 37
  suites together catch 648 of 648.

## A self-test on the test panel (forty-third pass, 2026-10-11)

From your notes **(you)**: work a bit more. What is mine **(suggested)**: the checkers read the code; this runs
it, in the engine, on your Studio save.

- **Self-test** (the test panel, F8, Studio only): the shop's own handler, run for real, each step said `pass`
  or `FAIL` in Output: the cheapest thing you do not own bought (its price taken, worn at once), bought again
  (refused, nothing taken), taken off and put back on; something too dear refused; a Robux item refused for
  tokens; a run finished the moment it started paying nothing (EconomyService's own warning about it shows
  just above, and is expected); a journal entry kept with the reader's name left out. Then **the save is put
  back exactly as it was**, and any run you were really in, so it can be pressed at any time. If everything
  wearable is already owned, press Clear purchases first.
- **Checks**: `check_shop.py`; `blender/mutations/pass43.py` plants 7 bugs and every one is caught (all 36 suites
  together catch 642 of 642). The stamp check
  caught the two changed modules before they were stamped again, as it should.

## The paste check knows an old copy (forty-second pass, 2026-10-11)

From your notes **(you)**: work a bit more. What is mine **(suggested)**: the most likely way the coming test
goes wrong is not a bug but an old file, pasted over the wrong script or skipped as "probably the same", which
then looks exactly like a bug. The paste check found missing files; now it finds old ones.

- **Every module in the paste carries a fingerprint** (`Name.STAMP = "1a2b3c4d"`, the line before its last
  `return`): the start of a SHA-1 of its own contents, written by `python tools/stamp.py`. 42 modules carry one.
- **Bootstrap.server knows what each fingerprint should be** (the PASTE STAMPS list, written by the same tool).
  In Studio the paste check compares them: any server or shared module that is an old copy is named,
  `out of date ... paste the current one`. The client's modules are checked on the client the same way,
  six seconds in: `PASTE CHECK (client): every client module is the current copy.`, or the names of the old
  ones.
- **Kept honest** (`blender/check_stamps.py`, the thirteenth checker): a stamped file changed since it was stamped
  fails, a module changed since the last commit with no stamp fails, and Bootstrap must expect exactly the
  stamped modules. So after changing a module: `python tools/stamp.py`, then the checkers.
  `blender/mutations/pass42.py` plants 9 bugs and every one is caught; all 35 suites together catch 635 of 635.

## The paste check says what a test needs to know (forty-first pass, 2026-10-10)

From your notes **(you)**: work a bit more. What is mine **(suggested)**: two more lines from the paste check,
and a second look at the Robux receipts (sound: a purchase is granted once, and only after the save that has it
is written; a receipt that comes before the save has loaded is left for Roblox to send again).

- **Whether Studio can reach the data stores.** Without them nothing is kept in a Studio test (saves, the
  journal, best times, the leaderboard), which is worth knowing before judging whether saving works. The paste
  check asks once and, if not, says how to turn it on (publish the place, then Game Settings, Security, Enable
  Studio Access to API Services).
- **Which Robux items have no id yet** in `ShopCatalog.lua`: listed as "not on sale yet". Fine for testing (the
  shop says the same and opens no prompt), needed before the game is published.
- **Checks**: `check_hub.py`; `blender/mutations/pass41.py` plants 6 bugs and every one is caught; all 34
  suites together catch 626 of 626.

## A pass paid for is a pass had (fortieth pass, 2026-10-10)

From your notes **(you)**: work a bit more. What is mine **(suggested)**: two things about Robux.

- **A paid pass could go missing for a whole session.** On joining, the server asks Roblox whether you own each
  pass, and that ask can fail for a moment. A failure was taken as "not owned" and never asked again, so
  someone who had paid for VIP or 2x tokens played that session without it (the surest way to a refund
  request). Now a check that fails is asked again five more times, 2, 4, 8, 16 and 32 seconds apart, and the
  pass is applied (and its sparkle worn) the moment Roblox answers.
- **Every Robux prompt's close is on the dashboard**: custom events `PassPrompt` and `ProductPrompt`, 1 when
  bought and 0 when not, with the item's id in CustomField01. With the kiosk's visits from the last pass, that
  is the shop's whole funnel: came to the kiosk, saw a price, paid it.
- **Checks**: `check_shop.py`; `blender/mutations/pass40.py` plants 9 bugs and every one is caught; all 33
  suites together catch 620 of 620.

## The dashboard sees the levels (thirty-ninth pass, 2026-10-10)

From your notes **(you)**: work a bit more. What is mine **(suggested)**: since the game is meant to earn, the
Creator Dashboard should show where players stop, not only what they spend.

- **Progression** (`Bootstrap.server`, AnalyticsService): each run is a step on one path called "Levels", the
  level's id its step. A start is logged for everyone who starts a run (late joiners too), a completion for
  every finish, and a fail for leaving partway, from the pause menu or by leaving the server. The mode and the
  length go along as custom fields (CustomField01 and 02), so the dashboard can split by them. It answers:
  how many start City Shore, how many finish it, and which level loses people.
- **The kiosk counts its visits** (a custom event, `ShopKiosk`, from `HubService`): the top of the shop's
  funnel, beside the purchases EconomyService already logs.
- All of it guarded: analytics never get in the way of a run. Events show on the dashboard from the live
  game (Analytics, Progression and Custom events), not from Studio.
- **Checks**: `check_hub.py`; `blender/mutations/pass39.py` plants 9 bugs and every one is caught; all 32
  suites together catch 611 of 611.

## A readable Output (thirty-eighth pass, 2026-10-10)

From your notes **(you)**: work a bit more, before testing in Studio. What is mine **(suggested)**: keeping the
Output readable while you test, so the paste check and anything real are not buried.

- **An error once, not every frame.** Five steps run every frame or several times a second (the emotes, the
  first five minutes, the footsteps, the view, the lava), each guarded, and each would have said a lasting
  failure every time it ran: hundreds of identical lines a minute. Each says a given error once now, marked
  "(shown once)".
- **A leaderboard that cannot be read** (Studio without API access, or the store having a bad minute) is not
  asked again for 10 seconds, and is warned about once a minute at most; it was asked, and warned about, on
  every redraw of every player's board.
- **Checks**: `check_devices.py` and `check_hub.py`; `blender/mutations/pass38.py` plants 9 bugs and every one
  is caught (and pass 34's suite follows the leaderboard's new shape); all 31 suites together catch 602 of 602.

## The test panel fills the shelf (thirty-seventh pass, 2026-10-10)

From your notes **(you)**: work a bit more, before testing in Studio. What is mine **(suggested)**: two buttons
on the Studio test panel (F8) for testing the journal and the shelf without playing every level.

- **All keepsakes**: every keepsake into your journal as if each had been picked up (quietly), so the shelf in
  the squish room can be seen full.
- **Clear journal (rejoin)**: the saved journal emptied, to test pickups from fresh; the journal on screen
  keeps what it has until you rejoin.
- **The panel is two buttons to a row** now, so it stays on a phone's screen in the Device Emulator.
- **Checks**: `check_story.py`; `blender/mutations/pass37.py` plants 7 bugs and every one is caught; all 30
  suites together catch 593 of 593.

## The paste check (thirty-sixth pass, 2026-10-09)

From your notes **(you)**: work a bit more. What is mine **(suggested)**: something for the import itself,
which is 44 files and 26 sounds by hand, where one missed file is easy and hard to find.

- **The server checks the paste** (`Bootstrap.server`, in Studio only, four seconds after it starts) and says
  in Output, once, whether everything the game expects is in place:
  - every module (19 server, 14 shared, 28 client) where it goes and as a ModuleScript (a module pasted into a
    Script or LocalScript by mistake is named), the two Bootstraps, ChunkBuilder and ChunkProps;
  - every sound (60 material, 17 button, 25 story and ending, 6 ambience), and any imported twice (the old
    `lavaCrust` four not deleted, say), which would play old and new at random;
  - ProfileStore in ServerScriptService;
  - and that KeepsakeService and PromptStyleService are gone.
  When it is all there it says `PASTE CHECK: everything is in place` in one line; otherwise a yellow list of
  what to fix, each with where it goes. The four level chords and WhirlRoar, which have stand-ins, are listed
  separately as fine for now.
- **Kept honest** (`check_hub.py`): the check's lists must be exactly what `src/` and `audio/` hold, so a module
  or sound added to the game in a later round has to be added to it too. `blender/mutations/pass36.py` plants
  10 bugs and every one is caught; all 29 suites together catch 586 of 586.

## Something to press under a locked cursor, and leaving what you are not in (thirty-fifth pass, 2026-10-09)

From your notes **(you)**: work a bit more. What is mine **(suggested)**: the rest of the review of what a
player can do, and one fix to the checking itself.

- **The death card's buttons could not be clicked with a mouse.** In third person the cursor is locked to the
  middle of the screen, and it is freed only while a screen with buttons is up (`ViewModeService.menuOpen`).
  The death card was not on that list, so "Try again" and the second chance (the one that costs Robux) sat
  under a cursor that could not reach them unless you knew to press Ctrl. It frees the cursor now while its
  choices are showing, and so does the Studio test panel.
- **"Leave to the lobby" worked for people not in the run.** It was taken from anyone while any run was on:
  pressed in the squish room, it put you in the lobby still marked as in the squish room (so you were left out
  of every vote after), and it brought the lobby back into the world in the middle of the run. Only a runner
  leaves a run now.
- **Into the squish room from a run**: the Studio test panel could do it, and the run would have waited for
  you. It says "Finish or leave your run first." now.
- **The checking, made safer** (`blender/mutations/run_all.py`): a suite puts its own files back, but on
  Windows a write can fail for a moment (a virus scanner or an indexer holding the file), and the last full
  run hit exactly that: one planted bug was left in `SkyPoolsService.lua` and ten suites after it refused to
  start. It was put back from the copy taken before the run, and nothing with it in was sent to you. The
  runner now keeps its own copy of `src`, checks after every suite, and puts back anything that differs
  (trying again for a few seconds if the write fails).
- **Checks**: `check_devices.py` the cursor, `check_hub.py` the leaving, `check_squishroom.py` the refusal;
  `blender/mutations/pass35.py` plants 7 bugs and every one is caught; all 28 suites together (run again
  with the new guard) catch 576 of 576, with nothing to put back.

## What only shows with many players: the store (thirty-fourth pass, 2026-10-09)

From your notes **(you)**: work a bit more. What is mine **(suggested)**: the rest of the many-player review,
this time Roblox's limits on reading the data stores, which a Studio test never reaches.

- **The leaderboard ran the server out of reads.** Every step anyone took onto a level pad redrew every
  player's board, and each redraw read the ranking and that player's best from the store; so did every flip
  of the board's lever, and every client's `RequestLeaderboardData`, which nothing limited. Roblox lets a
  server read an ordered store only about 5 + 2 per player times a minute, so a lobby of ten stepping
  between pads ran out within seconds, and the board went blank for everyone; a client asking over and over
  could run it out on purpose. Now (`LeaderboardService`) each board is read once and kept for 30 seconds
  (its season in its name), a second look while one read is on its way waits for that read, a failed read
  shows the last good board instead of nothing, and a new time on a board clears it so the time shows at
  once. Your own best under the board (`BestTimeService`) is kept for a minute, set the moment a new one is
  written, and let go when you leave.
- **Checked as well, and fine**: the hardcore restart's guard (it never waits, so two falls cannot skip one
  another), and every client wait on something in the world has a timeout or is a shared module.
- **Checks**: `check_hub.py` holds the caching; `blender/mutations/pass34.py` plants 11 bugs and every one is
  caught. **One new file to paste this round**: `LeaderboardService` (ServerScriptService/Services) was not on
  the list before.

## What only shows with more than one player (thirty-third pass, 2026-10-09)

From your notes **(you)**: work a bit more. What is mine **(suggested)**: a look at what a Studio test with one
player can never show, because the live game will have several in a server. Four real bugs, all fixed:

- **Statues piled up in the lobby.** Every player who joined got a statue built on the same plinth, and nothing
  ever took one down, so a server collected a figure for everyone who had ever been in it, all standing
  inside each other. Now a statue goes with its player (`HubService.removeStatue`, from Bootstrap when they
  leave, with its pose and tint), and each screen shows only its own (`HubVoteService` hides the others,
  figure and all, as they load and as they change pose): one statue of you, as it is when you play alone.
- **The lobby kept a level's sky.** The lobby's light came back only when the last runner FINISHED. Leaving a
  run from the pause menu, or the last runner leaving the server, left the level's sky (the Sunken City's
  grey, the halls' dark) over the lobby until the next run, and the level's world standing. That one shows
  alone too. Now the moment the last runner is out, however they got out, the lobby gets its light back and
  the level's world goes.
- **"Still running" counted the wrong people.** The finish's check asked whether anyone at all had not
  finished, so anyone in the squish room, anyone who had left the run, and anyone who had joined and never
  run kept the lobby in the level's light. It asks whether anyone is still out on the level now.
- **A reset in the lobby put you on the level.** While any run was on, everyone who respawned was put at its
  start, including players who had finished and were back in the lobby. Now a player respawns on the level
  only if they are in its run (or the lobby is away), and in the lobby otherwise.
- **Joining while a run is on.** While the lobby is away (from a run's start until its first runner is back)
  there is nowhere to stand but the level, so someone who joins then is put on it. They were not one of its
  runners: the run could be torn down under them, and a finish paid them nothing. Now they are counted in,
  play it in its mode, on its clock, and are paid for finishing like everyone else. The squish room keeps
  its own.
- **Checks**: `check_hub.py` holds all of it; `blender/mutations/pass33.py` plants 20 bugs and every one is
  caught; all 26 suites together catch 558 of 558.

## The keepsake shelf (thirty-second pass, 2026-10-08)

From your notes **(you)**: work a bit more. The shelf was on the roadmap; where it stands and how it works are
mine **(suggested)**.

- **A shelf for the 27 keepsakes** (`SquishRoomService.buildShelf`), in the squish room against the front
  wall, left of the lift home: nine cubbies across, three high, in the order of the materials' names, on a
  plinth on the floor, with a board on top. In the squish room rather than the lobby because the lobby is
  an open deck crowded with pads, keys and props and a spot there could not be proved clear; the squish
  room is the calm room you go to from the lobby, and every stud of it is known.
- **Your own collection on it** (`JournalService`): the shelf is the same for everyone, and what is on it is
  yours, drawn on your screen only: the toys you have found (made exactly as they are out in the levels, by
  `Interactables.toy`, sized to the cubby and set down on its board), a "?" card leaning in each cubby you
  have not, and "KEEPSAKES 12 of 27" on the board on top. It fills in from the saved journal when you join
  and the moment you pick a keepsake up.
- **Roblox's own prompt** on its plinth ("Look", Keepsakes) opens your journal at the keepsakes, where each
  one's story is.
- **Checks**: `check_squishroom.py` holds the shelf's size (a cubby for every keepsake), its place (clear of
  the lift and the side wall, under the ceiling, against the wall), that it stands on the floor with every toy
  and card on a board, and the client's side; `blender/mutations/pass32.py` plants 23 bugs and every one is
  caught; all 25 suites together catch 538 of 538.

## The journal kept between sessions, and tokens for a route walked (thirty-first pass, 2026-10-08)

From your notes **(you)**: work a bit more. The journal kept between sessions is from your roadmap; how it
works, and the token rule, are mine **(suggested)**.

- **The journal is kept** (`EconomyService`, `Interactables`, `JournalService`): every note, keepsake and secret
  you pick up is saved with your profile, in the order you found it, so the collection carries on where you
  left off: "Keepsake 12 of 27" next week is still 12.
  - **What is saved** is what the story wrote, written by the server alone (`Interactables.take` calls
    `EconomyService.keepEntry`), so there is nothing in it for a client to forge. Capped at 200 entries and
    4000 characters a field, never the same thing twice. Letters are saved with the name left out and put back
    in when they are read, so they still say your name if you change it.
  - **Read back** when you join: the client asks once your save has loaded (`JournalState`, a new remote the
    server Bootstrap makes), and the entries go in quietly and already read, so joining does not light the
    badge up or fill the corner with lines.
  - **Shown as taken**: letters, keepsakes and notice-board notes are marked with their journal id
    (`Interactables.mark`, tag `JournalThing`), and anything already in your journal is shown as taken when it
    comes into view, so what is still there is what is left to find. Only on your screen, as before.
  - **A secret's card** counts the secrets from earlier sessions too ("3 of 5", not "1 of 5" again).
- **Tokens only for a route walked** (`Bootstrap.walkedRoute`): the same checkpoint rule a time needs to
  count. Before, waiting out the minimum time and jumping to the finish paid a full run's tokens; now it pays
  nothing, and the server's Output says why. A real run always passes that checkpoint.
- **Checks**: `check_story.py` holds the journal, `check_shop.py` the token rule; `blender/mutations/pass31.py`
  plants 23 bugs and every one is caught.

## Times that count, an invite and the favourite (thirtieth pass, 2026-10-07)

From your notes **(you)**: work a bit more. What is mine **(suggested)**: a review of everything a player's
client can ask the server for, and two cheap ways for the game to grow.

- **A real leaderboard exploit, closed**: the death card's "Try again" (`HardcoreRetry`) was taken from
  anywhere in a run. It stops the clock, and the next checkpoint starts it again from nothing, so firing it
  by hand just before the last checkpoint turned a full run into a few seconds: a personal best, its token
  bonus, and a place on everyone's leaderboard. It is taken only from the start now, which is where a
  hardcore fall has just put you, so the real button works exactly as before.
- **Only a fair time is kept** (`Bootstrap.fairTime`), for a personal best and for the leaderboard: a hardcore
  clock that ran; the runner seen by the server at the last checkpoint in the first three quarters of the
  route (a teleport to the finish skips it); and no faster than half the floor the tokens already use
  (ShopCatalog's `MIN_SECONDS`, 45, 90 and 135 seconds for short, medium and long). A run that fails this
  still finishes and still pays its tokens; its time is just not kept, and the server's Output says why.
- **Chill no longer saves a best of 0**: chill has no clock, so its "best" was saved as 0 and the lobby board
  showed it as 00:00 in your colour. Nothing is saved for chill now, and a 0 saved before reads as no time.
- **A client's hello to the Sunken City** is heard once and kept short, so a client sending it over and over
  cannot fill the server's log.
- **Invite friends**: the pause menu's bottom row is Shop, Emotes and **Invite** now (three to a row, because
  a fourth row would not fit a phone held sideways). Invite opens Roblox's own invite screen when the account
  may send one; in Studio, where it may not, Roblox's corner notification says "Invites open in the live
  game, not in Studio."
- **The favourite, asked once ever** (`OnboardingService`): not straight after the way to the kiosk, but
  after the next run you choose to play: back in the lobby from it, with nothing else on the screen for 6
  seconds, Roblox's own "favourite this game?" prompt. Not asked at all if the game is already a favourite, and noted in the save before it is asked, so
  it never comes twice. The test panel's **Favourite ask again** brings it back. Favourites are how a game
  comes back to someone's home screen. In Studio the place has no id yet, so nothing shows there; it
  needs the published game.
- **Checks**: `check_shop.py` holds the fair-time rules, the retry, the invite and the favourite;
  `check_sunkencity.py` the hello. `blender/mutations/pass30.py` plants 26 bugs and every one is caught; all
  23 suites together catch 492 of 492.

## The harbour launch, and a review of passes 22 to 28 (twenty-ninth pass, 2026-10-07)

From your notes **(you)**: work a bit more, and try hard. What is mine **(suggested)**:

- **A review of everything new since pass 22**, read as a player would meet it. What it found, all fixed:
  - **Gear put on before the character was there**: a new character was dressed the moment it was added,
    sometimes before its root part existed, so a trail or aura could fail to appear. EconomyService now waits
    for the root first.
  - **Two screens holding you still**: the shop and the welcome each stopped your controls, and closing one
    let you move while the other was still open. The hold is counted now (`ShopService.kit.hold`, which
    OnboardingService uses), so you move again only when the last one closes.
  - **The squish room's lift moved you into a place that might not have loaded**: with streaming on, the
    hall 9000 studs away may not be there yet. The server now asks for it first (`RequestStreamAroundAsync`)
    and runs the fade itself ("going", then "arrived"), so the screen uncovers only once you are standing in
    the room. If the hall is still being built when you ride, the lift says so instead of fading and going
    nowhere. A failsafe uncovers the screen after 8 seconds whatever happens.
  - **The squish room counted as the lobby** for the guide and the hints; it does not now.
  - **Hints could pile up** behind one another; at most three wait now.
- **The launch in the Sunken City's harbour** (`SearchlightClient`, StarterPlayerScripts.Services, new; placed
  by SunkenCityService): somebody is still looking. A rescue launch stands off in the basin past the end of the
  street, bow towards you, rocking on the swell, and its searchlight goes slowly back and forth over the water
  you are coming down. The beam ends where it meets the water, and there is a pool of real light there (it
  lights you if it finds you). When it rains, the light is a little stronger. When the thing on the horizon
  comes up, the lamp swings round to it and holds it until it goes down, then goes back to searching.
  - **Everyone sees the same thing**: the server only says where the launch is (a hidden marker, like the
    gulls, at the first of four spots in the basin clear of the drain and every buoy); each client builds it
    and moves it from the clock every player shares.
  - **Real light, nothing to import**: a SpotLight in the lamp, red and green running lights, a white light
    on the mast, no Neon, no mesh and no sound. Nothing on it collides. The searchlight is a cold white, so
    the lantern at the end of the pier stays the one warm light in the harbour.
- **Checks**: `check_sunkencity.py` holds the launch's spots clear of the lighthouse, the barge, the wrecks, the
  quay walls and the drain on every run, the marker hidden and not solid, and the client started and in step
  with the thing and the rain; `check_squishroom.py` holds the lift's new fade. `blender/mutations/pass29.py`
  plants 21 bugs and every one is caught; all 22 suites together catch 466 of 466.

## The test panel and the one chord (twenty-eighth pass, 2026-10-06)

From your notes **(you)**: a bit more work before the Studio test. What is mine **(suggested)**:

- **The Studio test panel** (`DevPanelClient`, StarterPlayerScripts.Services, new; F8, or the DEV tab top
  left for the Device Emulator's touch screens): +500 tokens, +1 second chance, clear purchases, the first
  visit again (the welcome, the guide and every hint come back, without a fresh save), the way to the shop,
  and the squish room and back. **Studio only, three times over**: its remote (`DevPanel`) is made only in
  Studio, EconomyService and SquishRoomService listen only in Studio and check again when they are called,
  and the client builds nothing outside Studio. `check_shop.py` holds all of that, and the panel's +500 is the
  only new place tokens are added.
- **One chord for all four endings**: `EndChord` (`audio/endings/EndChord.wav`), an open chord with no third,
  played by any ending whose own chord is not in StorySounds, at its own pitch (City Shore 0.89, the Sky
  Pools 1.19, the Sunken City 0.67, the Flooded Halls 1). `Cinema.sound` takes `alt` and `altPitch` for it.
  One upload brings all four last notes back. `audio/gen_ending_sfx.py EndChord` writes just that file.
- **Checks**: `check_shop.py` and `check_story.py`; `blender/mutations/pass28.py` plants 10 bugs and every one
  is caught.

## The squish room (twenty-seventh pass, 2026-10-05)

From your notes **(you)**: one more thing before testing in Studio; the squish room, behind a door. How it is
built is mine **(suggested)**.

- **`SquishRoomService`** (ServerScriptService.Services, new) builds a hall with a real slab of every
  material in MaterialConfig, cloned from ChunkBuilder's templates (visuals and all) and registered with
  DeformationService like a level's: honey dents, bubble wrap pops, soap crumbles, the Needoh charges your
  jump. It waits for the templates, picks each material's slab (the most cells that fits 18 by 18), and lays
  them out in rows across a 104-stud hall, alphabetically, each with its name on a sign on two legs.
  - **Set into the floor**: each slab's walking surface is flush with the floor, and under it is a pit the
    shape of all it hangs below, so nothing pokes through and anything that gives way drops you at most
    6.4 studs onto the pit's floor, from where you jump out. Walls, a ceiling on them, real lamps every 30
    studs (no Neon).
  - **Far away**: at (9000, 600, 9000), beyond every level's horizon and the lobby's, closed in, so it is
    never seen from anywhere else.
  - **The lifts**: a pink lift cabin in the lobby's clear front-right corner, (38, -35) from the lobby's
    origin, its door towards the pool, built into the lobby's own folder so it is put away with the lobby
    during a run; and one at the front of the hall, back to the lobby. Roblox's own prompt ("Ride"), a soft
    fade on your screen while it moves you (`SquishRoomClient`, new).
  - **It keeps you**: anyone in the room has `InSquishRoom` set and is left out of the lobby's vote
    (`HubService.hubPlayers`), so a run never drags you out; while the lobby is away for a run the way back
    is refused with a word why; a respawn in the room puts you back in it.
- **Checks**: `blender/check_squishroom.py` (new, in `check_all.py`, the twelfth checker);
  `blender/mutations/pass27.py` plants 18 bugs and every one is caught.

## Before you test in Studio (passes 18 to 77, pasted on 2026-10-16): tested 2026-10-17

In the order to do it. Each step says what you should see; anything red in Output, or anything that looks wrong,
is worth sending.

**Set up (once)**
1. **Paste** the 46 Luau files (the zip has them laid out like the repo; line 2 of each names its place). Every
   module changed at least once since your last test, so paste them all.
2. **Sounds**: `EndChord` first (one upload brings back all four endings' last chords), then the other files in
   `audio/endings`, into SoundService.StorySounds; `needohSquish_1` to `_4` and `lavaCrust_1` to `_4` into
   MaterialSounds, **deleting the old lavaCrust four first**.
3. **Delete** `KeepsakeService` and `PromptStyleService` (StarterPlayerScripts/Services).
4. **ProfileStore** in ServerScriptService, named exactly that; Game Settings, Security, **Enable Studio Access
   to API Services** (without it nothing is kept between tests). Optional: the Robux ids in `ShopCatalog.lua`, and
   the badge ids in `ShopCatalog.BADGES` (see **Roblox badges**).

**Press Play, and read Output first**
5. **PASTE CHECK** (four seconds in): fix anything it lists (missing, the wrong kind of script, an old copy, a
   sound twice) and play again until it says `everything is in place`. Its lines about the data stores and
   "not on sale yet" say what this test can and cannot show.
6. **PASTE CHECK (client)** (six seconds in): `every client module is the current copy`, or the old ones by name.
7. **The test panel** (F8, or the DEV tab top left): press **Self-test**. The server's half (`SELF-TEST:`) buys,
   wears and refuses things, tries the second chance and the notes, reads the stores, finds the shelf and your
   statue, then puts your save back; the client's half (`SELF-TEST (client):`, about ten seconds) opens and
   closes the shop, the journal, the emote picker, the pause menu and the death card, checks the cursor is free
   on each, and asks the server for the save, the journal and the leaderboard, and looks at the lobby's level pads
   and the VIP tag over your head (so press it in the lobby); the server's half also opens and locks Sky Pools
   through the lobby. Every line should say `pass`.
   (One expected warning in the server's half: "finished a short run in 0 s, faster than it can be played".)

**Then play**
8. **First visit**: the welcome's three pages, then the guide's markers (City Shore, Chill, Short, Start). Again:
   the panel's "First visit again".
   **Locked levels** (a fresh save): Sky Pools, the Sunken City and the Flooded Halls boarded up, their signs
   saying what opens them; step on one and the vote card says so. Finish City Shore and Sky Pools opens: back in
   the lobby the vote card says "Sky Pools is open", with a chime. The panel's "Levels open/locked" opens them all
   (and locks them again).
   **The VIP tag**: the panel's "VIP on/off", and a lilac VIP pill over your head; it goes on a level and comes
   back in the lobby.
   **Admin**: type `/levels` in chat: every level opens and the vote card says so; again, and they lock as before.
   **Story**: step on the Story pad, then Start. City Shore, then (after its ending) Sky Pools straight away, and so
   on, through a short fade to black; LEVEL COMPLETE says "Story 1 of 4. Next: Sky Pools". "Near the end" gets you
   through each quickly. **The back rooms**: on any level, jump off seven times; the seventh drops you into them
   (yellow rooms, humming tubes; the first time, the secret's scene on Mrs Venn's notice). Find the door marked WAY OUT and press its prompt. Then in the lobby, walk down the
   yellow corridor by the back door to its end: it takes you back in (the panel's "Back rooms" does both). Leave
   from the menu partway and join a new story: it goes on from the level you reached. "Story from the start" on the
   panel puts it back to City Shore. At the end of the story: "+150 tokens (Story complete)" over the last level's own,
   and the green ribbon in the shop's Trails (before that, its tile says "Finish the story").
   **The daily chest**, left of the start pad: open it ("+20 tokens (Daily chest, day 1)", the lid lifts), open it
   again ("Opened today", and how long until the next); the panel's "Daily: next day", then open it: day 2, 30 tokens.
   **A hidden cache** on each level, about two thirds along, in a nook off the route (look for the glint): take it,
   "+25 tokens (Hidden cache)" and a line in the journal; on the next run it is not there for you.
   **A friend in the run**: the panel's "Friend in runs on/off", then start a run: a few seconds in, the card says
   "+20%, Running with a friend"; finish it: "+24 tokens (With a friend)" on a medium run in Chill. The pause menu's
   Invite says "Invites open in the live game" in Studio; in the live game its screen carries the 20% line.
   **The challenges board**, back left by the daily chest: three challenges written on it, "New ones in ..." at the
   foot. Do one (say "Finish City Shore"): the pill says "Challenge done", the card says which, the board ticks it
   green. The panel's "Challenges: new three" puts up a fresh three.
   **The starter pack**: the shop's Featured tab starts with it ("Once only", R$ 99; pressing it says not on sale yet
   until its pass id is in). The panel's "Starter pack on/off": "+500 tokens (Starter pack) and the sea glass trail",
   the trail in Trails to put on, the pack Owned in Passes and gone from Featured; again, and it is all taken back.
   **The materials**: play City Shore; a soft chime the first time you stand on each material, and at the end
   "+N tokens (N new materials)". The board beside the challenges counts them with their names; the journal's
   Materials tab has a page for each. The panel's "Materials: 26 / none", then a run that crosses soap: the last one,
   "and the swatch trail".
   **The post box**, beside the start pad: "Post a code", type `harrow bay` (any case, spaces are fine): "+100 tokens
   (Code HARROWBAY)"; again: "You've posted that code already."; a made-up one: "That code isn't one we know." The
   panel's "Codes: post again" lets you post it once more.
9. **The shop** at the kiosk (and from the pause menu): buy and wear a trail, an aura, a footprint (walk), a
   step sound (walk, listen), an emote (G, then pick it); preview a tile.
10. **The squish room**: the pink lift in the lobby's front-right corner; walk the slabs, fall through soap or
    sand and jump out of the pit. Turn round as you arrive: the keepsake shelf, "?" in every cubby on a fresh
    save; the panel's "All keepsakes" fills it, and the **Keepsakes** count in Roblox's player list goes to 27.
11. **A run**: a hint the first time on each material; the ending's sounds; "+N tokens"; the way to the shop
    after the first. In the **Sunken City**, the launch past the end of the street with its light over the
    water (the rain about 70 seconds in, the thing on the horizon about 95, and the lamp swings to it).
    In **Sky Pools**, the last stretch: the clouds round the tower go grey, the light drops a little, lightning in
    the cloud tops; on the slide, it clears under the clouds. In the **Flooded Halls**, look back now and then:
    the roof lights two bays behind you click, stutter and sink to a glow. The panel's **Near the end** takes you
    to the last stretch of any run to see these and the endings quickly (that run then counts for nothing).
12. **Hardcore**: fall after a few checkpoints; the death card's buttons click with the mouse in third person
    (no Ctrl); Try again, finish, and your time is on the board. A chill finish leaves "your time" at --:--.
13. **The journal kept**: pick up a letter or a keepsake, leave, join again: still there, already read, and the
    thing shows as taken.
14. **The pause menu**: Shop, Emotes and Invite on its bottom row (Invite says it opens in the live game).
15. **Two players** (Test, Clients and Servers, 2): each window shows one statue, its own, and both names show a
    Keepsakes count in the player list; leave a run from the pause menu and the lobby has its own sky again; one
    finishes and resets in the lobby while the other is still on the level, and stays in the lobby, and stepping on
    Start there says a run is still on. A story with two: the first to finish waits in the lobby and is brought back
    for the next level when the other finishes.
16. **Devices**: the Device Emulator (a phone sideways and upright, a tablet), and a controller if you have one
    (D-pad up journal, D-pad down menu, D-pad right emotes, B closes, the bumpers change shop tabs).

**Afterwards**: `python tools/paste_list.py --mark`, so the next list is exactly what changed since.

## Emotes and the second chance (twenty-sixth pass, 2026-10-05)

From your notes **(you)**: the emotes and the second chance next. How they work is mine **(suggested)**.

- **Emotes** (`EmoteService`, StarterPlayerScripts.Services, new; four poses added to `Poses`): Wave, Sit
  and squish, Stretch and Spin. A player asks the server (`Emote` remote); EconomyService checks they own it
  (and not faster than every 0.6 s) and tells every client, which poses that character through the game's
  own joints (AnimationConstraints, `Poses.drive`), since a joint turned on one client is seen there only.
  Spin turns the body round on its root joint, so the character itself never moves. Sit and squish lowers
  the body on its root joint, folds the legs, and puts a pink squishy toy in the hands, squeezed on the beat.
  Moving ends an emote on every screen (each sees the character move, and your own client says stop at
  once); none play over an ending's scene.
  - **The picker**: G, D-pad right, or Emotes in the pause menu (beside Shop, the way in on a phone). A small
    card at the bottom with a button for each emote you own and More (or Get emotes) for the shop; B or
    Escape closes it. In the shop an emote tile shows the emote on you, and an owned one's button is Play.
- **The second chance** (a developer product, 25 R$): a hardcore fall past the first stretch can be undone.
  Bootstrap notes where you were and your clock before the fall resets them (`noteFall`), and the death card
  offers it: "Second chance (N)" with some owned, its Robux price otherwise (bought in Roblox's own window and
  used the moment it lands). Within 45 seconds it is spent and you are set down at your checkpoint with the
  clock where it was (`TimerService.resume`). **It can never buy a place**: that run is marked, and goes
  neither on the leaderboard nor down as a best (it still pays its tokens). Fall again and you are on a
  fresh, fair run from the start. The shop's tile says how many you have.
- **Checks**: `check_shop.py` and `check_devices.py` hold it all (every emote's pose, owned-only and
  shown to everyone, let go of and ended by moving, the picker on every device; the chance spent, kept,
  timed, never a best or a leaderboard place); `blender/mutations/pass26.py` plants 21 bugs and every one is
  caught.

**To set up**: in the Creator Dashboard, create the **Second chance** developer product (25 R$) and paste its
id into `ShopCatalog.lua` (`productId`), as with the token packs. Until then the death card offers it only to
someone who already owns some (in Studio: nobody), and the shop says it is not on sale yet.

## Footprints and step sounds (twenty-fifth pass, 2026-10-05)

From your notes **(you)**: the footprints and step sounds next. How they look and sound is mine
**(suggested)**.

- **`StepService`** (StarterPlayerScripts.Services, new). Every client draws and plays them for every
  player within 150 studs, from what the server wrote on the player, so you see other people's prints and
  hear their steps. A step is every 2.4 studs of ground covered at a walk or a run (not standing, not a
  launch, not a scene, not the air); the ground under the foot is found with a ray (through water, so
  nothing floats on the surface).
  - **Footprints** (Heart steps, Star steps, Honey paw, Bubble sole): a flat print on the surface under each
    foot, left and right in turn, turned the way you are going, drawn from shapes (two lobes and a
    diamond, two crossed squares, a pad and four toes, a ring with a glint). Each holds and fades: the honey
    paw for ten seconds, slowly closing up, the bubble sole fizzing off in under three. At most 90 at once.
  - **Step sounds** (Crunchy, Gloopy, Poppy, Retro): they SWAP your footstep. Roblox's own (the Running
    sound) is muted for anyone wearing a pack, and the pack plays at their feet instead, heard nearby.
    Crunchy is the salt, snow and chocolate takes, Gloopy the honey, Needoh and slime ones, Poppy the bubble
    wrap (all from SoundService.MaterialSounds, with built-in stand-ins); Retro is built-in blips on a
    pentatonic scale, so a walk is a little tune, and nothing needs uploading.
- **`EconomyService`**: footprints and step sounds can be bought, worn and taken off like trails and auras;
  what you wear is written on you as `Footprint` and `StepSound`, only for what you own.
- **The shop**: they come off "soon" (only the emotes and the second chance stay); tapping a footprint
  tile walks four prints out in front of you, a sound tile plays three steps; a pack's button says Use and
  Stop. Featured adds the Honey paw and Poppy.
- **Checks**: `check_shop.py` holds it (a shape and a life for every footprint, a pack for every sound,
  worn only if owned, Roblox's footstep swapped, prints capped and not laid in scenes or on water, Retro
  needing no upload); `blender/mutations/pass25.py` plants 16 bugs and every one is caught.

## Every screen on every device (twenty-fourth pass, 2026-10-04)

From your notes **(you)**: every button working on PC, phone, tablet and controller, starting with the
controller fix (the pause menu could not be opened on one). What was found and how it is fixed is mine
**(suggested)**:

- **A controller can do everything.** The pause menu opens on **D-pad down** (Start is Roblox's own menu)
  with "Keep running" selected, B closes it. The journal moves from Y to **D-pad up**: Y is Talk, so
  talking to anyone with a controller used to open the journal over them. It opens with its current tab
  selected; B closes it. The death card selects "Try again". Every menu lets go of the selection when it
  closes. The welcome and the journal's note name the right buttons.
- **A thumb can press everything.** The journal's close (30 to 44) and its tabs (30 to 44 high).
- **Nothing wider than a phone held upright.** The pause card, the death card's choices, the vote card and
  the LEVEL COMPLETE banner scale to the screen, capped at their old widths.
- **Nothing under a notch or a thumb.** The pause menu and the journal keep to the device's safe area. On
  a touch screen with no keyboard the hardcore clock, the mode and the tooltip move from the bottom right
  (the jump button) to the top right under the tabs, and the best times from the bottom left (the
  thumbstick) to the top left.
- **Checks**: `blender/check_devices.py` (new, in `check_all.py`) holds all of it across every client
  screen: menus open, select, close and let go on a controller; nothing always-on on X, Y or A; every
  fixed-size button at least 44 pixels (six exempt, each with its reason); no fixed width over 360 pixels.
  `blender/mutations/pass24.py` plants 18 bugs and every one is caught.

## The first five minutes (twenty-third pass, 2026-10-04)

From your notes **(you)**: a player should understand what to do and what is going on in their first five
minutes, with a welcome of some sort. How it is done is mine **(suggested)**, on your earlier rule that
nothing comes up over the level.

- **`OnboardingService`** (StarterPlayerScripts.Services, new), in the shop's look (it borrows
  `ShopService.kit`):
  - **The welcome**, on a first visit only: three pages (what the game is; getting to the end, with the
    controls for the device you are on, keyboard, touch or controller; what tokens are for), then "Show me
    how to start" or "I'll look around". Skip works from any page. Thumb-sized buttons, a controller
    selects the first button and B closes, you stand still while it is open, the cursor is freed.
  - **The lobby guide**: a bobbing marker over each thing to step on in turn (City Shore, Chill, Short,
    Start) and one line at the bottom saying why. Walking into a run ends it.
  - **The hints**: the first time you ever stand on a material, one line at the bottom says what it does
    (every one of the 27 has one, under 90 characters) and fades after five seconds. They queue, never take
    a press, never show in the lobby, and each is shown once ever.
  - **The way to the shop**: after your first finished run, back in the lobby, a marker over the kiosk and
    one line until you open the shop.
- **`EconomyService`** keeps what has been shown (`Welcomed`, `Guided`, `Hinted`, `ShopIntro` in the save)
  from one new remote, `Onboarding`: the client can note those four things and nothing else, a few at a
  time, and a note can never touch tokens or what is owned. It logs the **onboarding funnel** to the
  Creator Dashboard: 1 welcome shown, 2 welcome finished, 3 lobby guide finished, 4 first run started, 5
  first material hint, 6 first run finished, 7 shop after first run. That is where to look to see where new
  players stop.
- **Checks**: `check_shop.py` holds it too (a hint for every material, no dashes, the guide pointing at pads
  the lobby builds, the welcome once, the notes limited, the funnel's seven steps);
  `blender/mutations/pass23.py` plants 21 bugs and every one is caught.

## The shop and the economy (twenty-second pass, 2026-10-04)

The game is meant to make money, so it has a shop now. The design and every decision behind it are in
`docs/superpowers/specs/2026-10-04-shop-and-economy-design.md`. From your notes **(you)**: a shop in the
bold style of the reference reel; tokens earned by finishing levels, with Robux packs; ProfileStore for the
saves; footprints, trails, sound packs, passes, auras and emotes; every button working on PC, phone,
tablet and controller; nothing dupable. How each is done is mine **(suggested)**.

- **`ShopCatalog`** (ReplicatedStorage.Shared, new): every item, its tab, its price in tokens or Robux, its
  colours, the token packs, what a run pays (`REWARD`), and `wear`, the one builder for trails and auras
  (the server uses it for what you own, the shop for its try-on). Prices live here and nowhere else.
- **`EconomyService`** (ServerScriptService.Services, new): one session-locked ProfileStore profile per
  player (tokens, owned, worn, the welcome flag, tokens earned, recent Robux purchase ids). Studio saves to
  its own store (`PlayerData_Studio`) and gives a fresh Studio save 1000 tokens to test with; the live game
  saves to `PlayerData`. The client can only ask (`buy`, `equip`, `unequip`, with an item id), one request
  at a time. Tokens go up in two places only: a finished run the server watched (Short 10, Medium 20, Long
  30; Hardcore x1.5; a new hardcore best +10; 2x pass doubles; nothing for a run faster than 45 / 90 / 135
  s), and a Robux token pack, granted once per purchase id and confirmed to Roblox only after the save
  holding it. Every token earned and spent is logged to the Creator Dashboard (economy analytics).
- **`ShopService`** (StarterPlayerScripts.Services, new): the shop in look A, tactile chunky. Tabs,
  a grid of tiles with drawn icons, squishy price buttons that press down and spring back, a one-tap
  confirm, a bubble-wrap pop when you buy, "+20 tokens" at the end of a run, a try-on for trails and
  auras, a VIP tag in chat. Every device: inside the safe area, columns by width, thumb-sized buttons,
  controller selection with the bumpers for tabs and B to close, Escape to close, your character paused
  while it is open.
- **The kiosk** (`HubService.buildKiosk`): a striped seaside booth left of the spawn, opposite the viewer,
  with Roblox's own "Shop" prompt, four posts under the awning, the sign standing on it, a jar of tokens and
  a real lamp. **The pause menu** has a Shop button (the way in from a run, and on a phone). The cursor is
  freed while the shop is open (`ViewModeService`). `BestTimeService.submit` now says when a run is a new
  best.
- **Built and marked soon** (shown with their price, not yet for sale): footprints, sound packs, emotes and
  the Hardcore second chance. Trails, auras, the passes and the token packs work now.
- **Checks**: `blender/check_shop.py` (new, in `check_all.py`) holds the price list, the anti-dupe rules,
  the device rules and the wiring; `blender/mutations/pass22.py` plants 23 bugs and every one is caught.

**To set up**:
1. Get **ProfileStore** (by loleris: Creator Store, or github.com/MadStudioRoblox/ProfileStore) and put
   the ModuleScript in ServerScriptService, named exactly `ProfileStore`. Without it the shop works but
   nothing is saved, and Robux purchases are refused outside Studio.
2. Game Settings, Security: turn on **Enable Studio Access to API Services**, to test saving in Studio.
3. Creator Dashboard, your experience, Monetization: create the passes (2x tokens, VIP) and the developer
   products (the four token packs), and paste each id into `ShopCatalog.lua` (`passId`, `productId`). Until
   then those tiles say "not on sale yet".

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

**Where a pad's name and look come from:** the name is the level's `name` in `LevelDefinitions`
(ReplicatedStorage.Shared), and the window and label come from the level's `backdrop` in
HubService's `THEME_LOOKS`. If the lobby shows Open Sky or Far Water, the place's LevelDefinitions is
an older copy. Bootstrap prints `the lobby's levels are ...` at startup and warns when level 2 or 3
still has an old name. `check_hub.py` fails if a level's backdrop has no look.

| Level | Name | Shape | Chunks (Medium) | Setting |
|---|---|---|---|---|
| 1 | City Shore | spiral | 40 | the city, beach and waterpark horizon; ends on the high dive; the whole kit, all three rhythms, no repeat within six picks |
| 2 | Sky Pools | meander, going down | 44 | pool terraces on alternating sides of a route that sweeps down through a cloud sea; ends on a slide round a fountain tower into the final pool; the calm half of the kit |
| 3 | The Sunken City | ring, flat with a swell | 50 | a drowned city round the route, a thing under it, an aquarium off a checkpoint; ends down the harbour drain |
| 4 | Flooded Halls | path | 44 | inside a flooded tiled bathhouse, ending on a flume |
| Sandbox | all materials | spiral | 82 | development route, its own pad |

## The story: Harrow Bay, 14 August

**`LORE.md` is the canon now** (sixteenth pass): the Hold, the keepsakes, the timeline from 1911, the
key holders before you, the cast, the places, what is never explained, hooks for later and the rules
for writing more. This section is how the story is built into the game.

### Twenty-first pass (2026-09-30): the endings scored, the Needoh's own sound, lava about to go, the high dive

From your notes **(you)**: sounds made for each ending, playing while its scene plays, for a cinematic
feel; a better, more Needoh-like Needoh sound, and which files to replace; the Needoh and clay had the
same sound, which should not happen; the lava chunk should look about to burst, a hot surface; and a
better final sequence for City Shore. How each is done is mine **(suggested)**.

- **EVERY ENDING IS SCORED** (`Cinema.sound`, `Cinema.fade`). A scene plays sounds of its own, found by
  name in `SoundService.StorySounds`, a few with a built-in stand-in until imported. Looped beds fade in,
  and whatever the scene is still playing fades out over 2.5 s when it gives the camera back; a one-shot
  asked for with `keep` (the chords) is left to ring out. `audio/gen_ending_sfx.py` synthesises all 17
  into `audio/endings/`:
  - **City Shore**: `DiveBoard` as the board lets you go, `DiveWind` rising all the way down and cut at
    the water, `DiveSplash`, `UnderwaterHum` looped under the harbour, `ShoreChord` 2.6 s after the splash.
  - **Sky Pools**: `SlideRush` looped under the sled (gone at the first skip), `CloudWhoosh` into the
    cloud, `SkimSlap` at every skip (each softer and a little higher), `PoolPlunge` as you tip out,
    `PoolsChord` over the pool.
  - **The Sunken City**: `WhirlRoar` looped from the grab, `DrainFall` once as you go down the shaft,
    `CulvertWash` looped down Outfall 3 with the roar fading behind it, `SunkenChord` at the station.
  - **Flooded Halls**: `FlumeRush` looped down the tube, `PlungeWind` as you shoot out of it (the rush
    fades), `HallsChord` on the last line, the only chord of the four that resolves. The mouth's
    `MawRumble`, `JawsShut` and `Heartbeat` are as they were.
- **THE NEEDOH HAS ITS OWN SOUND.** It used `claySquish`, the same files as clay, which is why the two
  sounded identical. Now `sfxEvent = "needohSquish"`, with four takes (`audio/materials/needohSquish_1` to
  `_4`): gel shifting slowly inside a rubber skin, a creak as the skin stretches, a wet suck as it swells
  back, and no slap. Until they are imported it borrows clay's pitched down to 0.68 (`sfxFallback`,
  `sfxFallbackPitch`, read by `AudioService.playSfx`), so the two are never the same sound again.
- **LAVA ABOUT TO GO** (`lavaLife` in `DeformationRenderer`). Every lava platform gets an orange light that
  breathes, embers and heat haze rising off it, and bubbles that swell out of the crust and pop, spitting
  (one every 0.5 to 1.6 s, on platforms within 170 studs). A step spurts drops at your feet and flares the
  glow; a cell bursting throws a fountain of molten gobs and a smoke column and flares it fully. The four
  `lavaCrust` takes are new (bubbling glop, the crack with a hiss, a molten spit) and replace the old ones.
- **THE HIGH DIVE, SHOT PROPERLY** (`CityShoreClient`):
  - the sun flares as you leave the board (SunRays up for 1.8 s, then back, and put back at the end);
  - a cut back up to the deck, over Maren's shoulder, looking down past her at you dropping away (1.6 to
    2.7 s), before the turn, the drop and the water;
  - eleven gulls circling halfway down, out from the board, which burst outward and up as you drop
    through them;
  - wisps of air streaming up past you the whole way down;
  - under the water, seven shafts of light slanting down from the surface and swaying, and five fish
    crossing at the edge of the light, over the drowned street and its one lamp.
- **Checks**: `check_story` holds all of it (the Needoh's event and pitch, the takes, the lava's life,
  every ending's sounds and their files, the dive's shots); `blender/mutations/pass21.py` plants 17 bugs
  and every one is caught.

**To import this pass**: every `audio/endings/*.wav` (17) into `SoundService.StorySounds`, named as the
files; `audio/materials/needohSquish_1` to `_4` into `SoundService.MaterialSounds`; and
`audio/materials/lavaCrust_1` to `_4` in place of the old `lavaCrust` sounds there (delete the old four
first, or the old and new would be picked from at random).

### Twentieth pass (2026-09-30): default prompts, a proper third person, readable voices, the Sky Pools again

From your notes **(you)**: with Ctrl locked you do not turn to walk back or sideways (asked whether that
was meant); the mouse got stuck when the cursor was over an NPC; the lines your character says in the
endings should look better; Roblox's own prompt style was good enough; stepping back from the viewer left
the camera inside your head until you scrolled; NPC text should be one size whatever the line, with the
bubble changing size instead; the Sky Pools' light was still washed out; small improvements to the level
and its people; the slide's metal rods seemed to pass through you. How each is done is mine **(suggested)**.

- **Ctrl locked is standard mouse lock**: you face where the camera looks, so S walks back and A/D strafe.
  Left as it is (answered, not changed).
- **THE PROMPTS ARE ROBLOX'S OWN AGAIN.** `PromptStyleService` is deleted (delete it in Studio). Its card was
  an Active gui over the prompt: with the cursor over it, releasing the right mouse button was swallowed,
  so the camera went on dragging and the cursor stayed pinned. That was the "stuck near NPCs".
- **BACK FROM FIRST PERSON** (`ViewModeService.settleThird`): the zoom is held at 14 for a moment and the
  camera put behind and above you, then the lobby's range (6 to 36, so a scroll never slips you into first
  person) is given back.
- **YOUR VOICE IN THE DRAIN** (`SunkenCityService`, DrainCry): screams scrawled in Permanent Marker on a soft
  shadow, landing with a small jolt, 1.7 s each; once the culvert has you, quiet handwritten lines (Kalam),
  2.8 s each.
- **SPEECH BUBBLES** (`Townsfolk.say`): one text size for everyone (19; the longest line, 116 characters,
  wraps to five lines at it), the bubble up to 300 wide and as tall as its lines, growing upward from over
  the head. Shouts are 34.
- **THE SKY POOLS' LIGHT**: no haze in the air (it was a white film over everything), environment diffuse
  0.4 (the white cloud under the level was filling every shadow), a deeper horizon, less brightness and
  bloom, more contrast; decks, coping, stone, rail and clouds a step off white.
- **THE SLIDE**: its rods leave from the lip of the wall on the tower's side, not the trough's middle
  (they went straight through the rider); the hoops are a stud higher.
- **THE SKY POOLS' PEOPLE** (`Townsfolk` HABITS): Dev checks his watch every few seconds (it is always three
  o'clock), Okafor fans herself, Rudy nods to the beat with a hand on the deck. Not while they talk. Props:
  Dev's towel trolley and watch, Okafor's side table with a drink, a paper umbrella and a magazine, and
  Rudy's record with its label and tonearm, going round (`SkyTurntable`, SkyPoolsClient).
- **Checks**: `check_story`, `check_skypools` and `check_sunkencity` hold all of it; `pass19.py` now covers
  the prompts, the return to third person and the drain's voice, and `pass20.py` the rest (10 bugs).

### Nineteenth pass (2026-09-30): third person, the seaside viewer, Ctrl, the prompts, the moving clouds

From your notes **(you)**: the first/third person switch did nothing in the lobby; on reflection third
person suits the ASMR better, and if first person stays it must be entirely optional and not in the
interface but an option in the lobby; Ctrl should toggle the cursor between locked and free, as in
Squid Game; and more small details of that kind and big ones like the whirlpool. How each is done is mine
**(suggested)**.

- **THIRD PERSON IS THE GAME'S VIEW** (`ViewModeService`, rewritten): held at 14 studs in a run, free in
  the lobby. The on-screen switch and the V key are gone.
- **FIRST PERSON THROUGH THE SEASIDE VIEWER**: a coin-op promenade telescope on the lobby's terrace by the
  leaderboard (`HubService`, "ViewScope", at (26, 20) from the room's origin). "Look through" and it is
  first person at once, in the lobby too, and in every run after; "Step back" and it is third person.
  The prompt is heard on the client (ProximityPromptService.PromptTriggered), so the server does nothing.
- **CTRL**: in third person, the cursor locked in the middle, the camera turning with the mouse, you
  facing where you look, the camera over your right shoulder (a custom mouse lock, set each frame after
  the camera); free is the ordinary cursor. In first person Ctrl frees the cursor (an invisible Modal
  button) and locks it again. Never while a scene has the camera, never turning you while you ride or
  sit, and the cursor is always free over an open journal or pause menu. A word at the bottom of the
  screen says which, and goes.
- **THE PROMPTS** (`PromptStyleService`, new): every ProximityPrompt in the game is drawn as the journal and
  the pause menu are, a dark card with the key in a cap, a line filling under it for a hold, the card
  itself the button on a phone. Switched to Custom on the client, so no server code changed.
- **THE SLIME'S KICK**: the picture widens as a slime launches you and settles as you rise (the ordinary
  camera only, from one resting width however many launches come in a row).
- **WHAT YOU PICK UP FADES** off your screen instead of blinking out (`JournalService`).
- **THE SKY POOLS' CLOUD SEA MOVES** (`SkyPoolsService.cloudSea`): mist banks roll slowly across the tops
  on one wind, and wisps lift off them near the middle. About 250 particles live at once.
- **Checks**: `check_story` and `check_skypools` hold all of it; `blender/mutations/pass19.py` plants 15
  bugs and every one is caught.

### Eighteenth pass (2026-09-29): the journal, the nooks, endings you can read, and every ending redone

From four recordings in one session **(you)**: keepsakes showed no toy, only a card when you stepped on a
material; keepsakes and notes came up too often and should be picked up and read later from a menu, the
way Poppy Playtime keeps notes; notes and signs should be off the main passage, in optional places, and
the way to the secrets should sometimes lead you there on its own; a lobby choice of first or third
person, locked for the run; the aquarium's fish spun when the glass was tapped; bubble wrap's sound came
late; the Sunken City's whirlpool should look like real swirling water, like the aquarium's flood, and
its shaft better; the endings' text was too fast to read; a City Shore note could not be put down with R
after a secret's scene; you could fall off the Siren Tower's bridge; the dive should be more cinematic;
the Sky Pools' fountain tower should look better, its ending have more action, its light was washed out
and one shot was too close; the Flooded Halls' maw was covered by a circle and the slide lagged; soap
should crumble without black cracks. How each is done is mine **(suggested)**.

- **THE JOURNAL** (`JournalService`, new; J, the book beside the pause tab, or Y). Nothing goes on the
  screen over the level any more. `Interactables.take` sends what you took over `StoryMoment` ("journal");
  a small line comes up in the corner (never during a scene) and the book keeps Notes, Keepsakes and
  Secrets, unread ones dotted and counted on the tab. The thing you picked up is hidden on your screen
  only ("hide"), so the next player can still find it. `Interactables.read` and its paper overlay are
  gone, which is also the end of the note that R would not put down. Session only, not saved.
- **KEEPSAKES ARE THINGS** (`Interactables.keepsake`): a few parts in the material's colour on a stool,
  with a glint and a small real light. `KeepsakeService` is deleted (delete it in Studio too) and
  `ScreenEffects` no longer calls it.
- **THE NOOKS** (`StoryService.nookOff`): small balconies built out from the side of a chunk (outward on a
  ring), a gangway across, solid rails, joists back into the chunk and a strut under each (its foot found
  by a ray), and a lamp on a post. Only where the engine says the space is clear (GetPartBoundsInBox), and
  clear of the Siren Tower's shaft and bridge. The pry bar is in the first, each note in its own, and up
  to four keepsakes of the level's materials in them; a note only goes on a chunk if no nook fits. On
  six runs in ten a string of bunting runs out to a nook from the route. Loose bricks, the loose board
  and the locker with something in it glint.
- **THE SIREN TOWER'S BRIDGE** has solid posts, top and mid rails, and an invisible guard nine studs high
  (as the Sunken City's pier has), and two lanterns at its head.
- **CAPTIONS ARE READ** (`Cinema`): up for as long as their words take to read twice, a new one waits for
  the last to be read once, a scene holds its last shot while one is up, bigger type on a dark band.
  `Cinema.done()` / the `SceneState` remote: an ending says when it has been watched, the server waits
  for that (at most 50 s) before its six seconds to the lobby, and the banner waits too. `finish()` puts
  the camera over your shoulder before handing it back (it was left looking straight down in the lobby).
  The fall-ownership windows are a minute now for the same reason.
- **THE VIEW** (`ViewModeService`, new): third or first person, chosen in the lobby (or V), locked for the
  run (third held at 14 studs, first `LockFirstPerson`), free again in the lobby.
- **CITY SHORE'S DIVE**: the leap (the fall held back for its first second), a close orbit as you turn
  over, falling with you from underneath, the water shot only in the last 120 studs, a splash with a
  crown of spray and a flash, then the drowned street. The server's carry is drawn smoothly on the
  diver's screen. `DiveFinaleService.RELEASE_AFTER` is a minute.
- **THE SKY POOLS**: the fountain tower rebuilt (fluting, banded tiers with lit windows, two bowls above
  the basin spilling into each other, a jet, six arcing jets, eight separate streams with mist, and a
  faint rainbow). The slide ends in a **skim** across the pool (`SkyPath.skimFrame`, three hops, 2.8 s;
  the server stands you where it stops). The camera knows where the clouds are (`CloudTop`,
  `CloudBottom`) and shoots the cloud crossing from underneath; the face shot is 14 studs off. The light
  is a step down each (brightness, exposure, bloom) and the sun at three o'clock, as the story has it.
- **THE SUNKEN CITY**: the whirlpool's rings are see-through, and over them a swirl of spray carriers the
  client turns with the rings, each throwing spray in toward the middle, so the surface is spiral arms of
  foam; the hole pours down. The drain shaft is lined: wet brick, flanges, a ladder, caged lamps that
  flicker, and water streaming down its walls; the ride has a shot falling with you down it. The fish
  add up their turn instead of working it out from the clock, which was the spinning.
- **THE FLOODED HALLS**: the server writes the flume's path down once (`FlumePath`, 221 steps) and the
  rider's own client draws the ride from it; the server only moves a rider whose client never says so.
  New shots (a chase, from the shaft's wall, from ahead), never across the mast. The maw has no throat
  part (its end was the black disc), has a tongue, a glow inside and a spotlight from above, and is 90
  studs down; its scene and the gate chamber are slower (`GATES.MAW` 8.5, `SECONDS` 42, `KEY_AT` 14).
- **BUBBLE WRAP** is heard the moment your own foot touches a cell (`DeformationRenderer`, `pops`), and the
  server's word about the same step a moment later plays only the picture. **SOAP** has no cracks.
- **Checks**: `check_story`, `check_skypools`, `check_halls` and `check_sunkencity` hold all of it;
  `blender/mutations/pass18.py` plants 33 bugs and every one is caught.

### Seventeenth pass (2026-09-29): silence at the endings, secrets, and the mouth

From your notes **(you)**: the ambience should stop when an ending's scene plays, every level should
have ambience, the story should be written like a film, lore should come through letters, lockers,
doors and things broken open with a tool, every level should have a secret, City Shore a tall building
reached from a chunk, the Sky Pools something under a pool, the Flooded Halls something by the slide,
and the flume should end in a giant creature's mouth, only its teeth showing out of the dark, with a
really good scene. How each is done is mine **(suggested)**.

- **An ending silences the level.** `Cinema.begin` fades out every sound tagged Ambience (the Sky Pools'
  water, the Sunken City's water, the baths' drips) and marks the player Hushed, which the Sunken City's
  mood and `AmbienceService` both honour, so nothing brings it back until the next level. A secret's
  short scene does not (`{ hush = false }`).
- **Every level has ambience** (`AmbienceService`, new): the sea far below at City Shore, wind and the
  party's one song through a wall at the Sky Pools, the harbour at night with a buoy bell in the Sunken
  City, the baths' strip-light hum, and under all of them the Hold's drone. Generated as seamless loops
  (`audio/gen_material_sfx.py`, `audio/ambience/`); put them in `SoundService.AmbienceSounds`, or slowed
  built-in sounds stand in where one will do. The server marks each player InLevel so their own client
  knows which, and HubService clears it on the way home.
- **The screenplay**, `story/HARROW_BAY.fountain`: the game as a film, in Fountain, every scene and shot,
  with notes naming the code that plays it. LORE.md now says how the story is told, in layers.
- **Secrets** (`Interactables`, new; `StoryClient`, new): letters lying on the ground (one a level), MR
  BARLOW'S PRY BAR on an early chunk of every level (it goes on your back), lockers and a tin box that
  open, loose bricks and a loose board that only the bar opens. Five secrets, each played as a short
  scene when found (the camera drifting in along a curve, depth of field on what you found, a sting,
  its name and a line), then "Secret 2 of 5" and a note to read:
  - **City Shore: the Siren Tower**, out of the sea in the middle of the spiral, red brick with stone
    pilasters and string courses, lit slit windows, a clock stage at 9:14, a balcony, a copper dome,
    the mechanical siren and a red lamp. A footbridge on stays reaches its Siren Room from a chunk
    halfway up (chosen so it passes clear of every other chunk). Inside: the siren log on the desk,
    the control panel, a lamp, a ladder to a shut hatch, and loose bricks with R. Pell's letter behind.
  - **Sky Pools**: a tin box on the first pool's deep floor, bubbles coming off it: a photograph.
  - **Sunken City**: a staff locker in the aquarium gallery: E. Marsh's letter.
  - **Flooded Halls**: four staff lockers on the gangway (yours is 3: "I'll go in tomorrow."), and a
    loose board by the far rail: underneath, straight down into the shaft, something breathes.
  The level services only mark where (parts tagged StorySpot); StoryService builds everything.
- **The mouth** (`Maw`, new, client; `blender/gen_maw.py`, four new meshes): at the end of the fall the
  picture no longer just dips to black. Six seconds (`GATES.MAW`) on the rider's screen: from inside its
  throat looking up, its jaws opening under you, needle teeth in rows, a glow far down; falling with you
  from above, a dolly zoom as it rushes up; from the side, level with the teeth, as it shuts, with a
  jolt; black; a heartbeat; "The Hold. It keeps what it is given." Then the Gate Chamber, as if you had
  been spat out into its sump. Only its mouth, ever. Without the meshes a rougher mouth of parts stands
  in. The server holds the move into the chamber for those six seconds.
- **Cinema** has a camera operator's kit now: `spline` (Catmull-Rom paths), `shake`, `focus` (depth of
  field) and `black`.
- Checked: `check_story`, `check_halls`, `check_skypools` and `check_sunkencity` hold all of it; the
  pass 17 suite plants 25 bugs and all are caught.

### Sixteenth pass (2026-09-29): the Hold and the keepsakes

From your ask to make the lore unique to this game **(you)**; the idea is mine **(suggested)**: every
material is something somebody in Harrow Bay was holding when the water came, kept by the Hold and
grown into the stepping stones. That is why every surface wants to be pressed, why it remembers your
weight and then forgets it (the day comes round again), and why every level ends by going down.

- **Keepsakes** (`Shared/Keepsakes.lua`, new; `KeepsakeService`, new, on the client): one for each of
  the 27 materials, with what it was, where it came from and one line about who was holding it (Sal's
  honey, Pip's sand, Dev's parcel of bubble wrap, Mrs Venn's soap, the waterworks teleprinter...). The
  first time in a session you stand on a material, a card slides down at the top of the screen:
  "Keepsake 5 of 27". Cards queue, wait for any scene to finish, and stay up nine seconds.
  `ScreenEffects.onStep` hands it your own steps.
- **The Hold** is named by the old-timers (Mr Wick, Mrs Venn, Mr Barlow). **The Watcher** is E. Marsh,
  the key holder before you, who waited too long. **The fisherman** is Mr Wick, who held the key in
  1946. New lines for Sal, Pip, Dev, Mr Wick, Mrs Venn and Mr Barlow carry it.
- **A fourth thing to read on every level**: the Novelty Works' summer list, the Promenade Hotel's note
  about the stairs, the list of key holders since 1911 (your name last), and the baths' lost property
  (a front door key on a green ribbon, marked HILL HOUSE: a hook for a Level 5, in LORE.md).
- `check_story.py` now holds every material to a keepsake with a thing, a place and a line, every
  caption and keepsake to having no dash, and every source file to naming its Studio place in its
  first lines (seven had not).

Added in the fourteenth pass (2026-09-26), from your idea that the people on the levels are living
their ordinary lives and do not know they are in what the player calls the backrooms **(you)**. The
shape of it is mine **(suggested)**.

**The premise.** Harrow Bay is a seaside town on the day the sea came in and never went out. The
tide came in on the 11th and has not gone out since. The Harrow Bay Corporation Waterworks (1911)
could let it out, but the outfall gates only open with a key, and the key holder took it home and
never came to work. Everyone on the levels is still living that day, a little later each time you
meet them, and none of them thinks anything is wrong. Several of them think you might be the key
holder. At the end of the Sunken City, you find the time card, and it has your name on it. At the
end of the Corporation Baths you find the gates, and the key in your pocket, and you open them. The
tide goes out. And the last line on the screen is 14 August, 9:14 in the morning: the day begins
again.

**What the player calls the backrooms.** The townsfolk call it Harrow Bay. The one who comes
closest is Mrs Venn at the baths: the people who come down from up there always call it the
backrooms, she says, and it is the back rooms of the baths, dear. Staff only.

**The threads.** Tobi Okafor went down in the morning to find the key man, in his trunks with his
red towel: at nine his daughter Pip is waiting for him on the front, at three his wife is keeping
his seat at the pools, at midnight the fisherman says nobody who went down the drain came back, and
in the baths Tobi is still looking ("They're longer every time"). The flood siren is tested at noon
every day; at midnight it is not a test. Every clock in town stopped at 11:52; under the pumping
station they have started again, and they reach midnight when the gates open. Mr Barlow, the night
engineer, can start the engines but cannot open the gates.

**The same day, later each time, and numbered in that order.** Each level opens with its number, a
place and a time low on the screen (`StoryService.opening`, fading in over about two seconds, held
twelve). The lobby's pads say "Level 1: City Shore" and so on, with the time each is set at:

| Level | Opens on | The people there |
|---|---|---|
| 1 City Shore | 14 August, 9:14 in the morning | **Sal**, with her ice cream cart on the first stable chunk; **Pip**, eight, building a sandcastle on a stable chunk about halfway up while she waits for her dad, who went to find the key holder; **Maren** the lifeguard on the dive deck |
| 2 Sky Pools | 14 August, three o'clock | **Dev**, handing out towels on the first terrace; **Mrs Okafor**, on the edge of a lounger keeping her husband Tobi's seat (he went down to find the man with the keys); **Rudy**, playing the same song on a record deck at the top of the slide |
| 3 The Sunken City | 14 August, eight minutes to midnight | **the Attendant** in the aquarium (every clock stopped at 11:52); **the Fisherman** on the pier ("Lot of folk went down that drain looking for the key man"); the faceless **Watcher**, who says nothing |
| 4 Flooded Halls (the Corporation Baths) | 14 August, four minutes to midnight, under the pumping station | **Mrs Venn**, the baths attendant, behind her ticket desk on the first stable chunk; **Tobi Okafor** on a bench about halfway, red towel round his neck; **Mr Barlow**, the night engineer, with a lit lantern on the gangway to the flume |

**The reveal.** The drain ends in the harbour pumping station, at Outfall 3 (the Sunken City's
fourteenth pass). The pumps read zero, the gate lever is down, hook 3 on the key board is empty, and
the time card in the rack says `KEY HOLDER / <your display name> / 14 AUG / NOT CLOCKED IN`.

**How it is told.** You talk to anyone with a line by walking up and pressing F (a prompt; E is the
aquarium glass's). They greet you on their own the first time you come near, turn their heads to
follow you while you are close, and talk with their hands. What they say stays up for twice as long
as it first did (`Townsfolk.READ`). Maren shouts after you when you dive, and Rudy when you take the
slide. What they say is all in `Townsfolk.LINES` and `SHOUTS`: to change the story, change it there.

**Things to read.** Four notice boards on posts on every level, on stable chunks beside the route:
press R and the words come up like a sheet of paper; R again, or walking on, puts them down. City
Shore has the Harrow Bay Gazette, the council's siren notice, Pip's drawing and the Novelty Works'
summer list; the Sky Pools the party invitation, the guest list, Tobi's note on a lounger and the
Promenade Hotel's note about the stairs; the Sunken City the tide table (high water at 11:52 every
night), the waterworks notice with the key holder's name scratched out, a MISSING poster and the list
of key holders since 1911; the baths the rules of the baths, Tobi's postcard to Pip, the waterworks
rota with your own name on it and the lost property. Every word is in `StoryService.NOTES`.

**How they look.** Each person is dressed limb by limb from `Townsfolk.LOOKS`: sleeves that stop
where a short sleeve stops, trousers or shorts or a skirt, shoes or bare feet, hair (short, bun,
ponytail, bob, afro, receding) made of shaped parts round the head, a beard, a moustache or glasses
where they have them, and their own proportions (Pip is eight; Mr Barlow is broad). They stand easy
rather than as shop dummies, and sit with their hands in their laps.

`check_story.py` holds it together: everyone stood up has at least three lines and a look, at least
two people on each level mention the key holder, the openings are all on 14 August and numbered,
there are three things to read on every level, and no line anyone reads has a dash.

**Where it lives.**
- `ServerScriptService.Services.Townsfolk` (new; it replaces `SunkenNPCs`): who everyone is, what they
  say, how they stand, greet, look at you, shout, and (the attendant) panic. `spawn` stands anyone up;
  a sitter's `feet` is the top of what they sit on.
- `ServerScriptService.Services.StoryService`: the openings, the notes, and the people of the two
  levels whose services do not stand their own (City Shore's Sal and Pip, and the baths' Mrs Venn,
  Tobi and Mr Barlow). Bootstrap calls `StoryService.stage` once the level is built.
- `ReplicatedStorage.Shared.Poses`: joints of either kind (Motor6D or the newer AnimationConstraint)
  and the poses the endings use: `flail` (the drain), `dive` (City Shore), `sled` (the slide),
  `flume`, `climb`, `key` and `wheel` (the Flooded Halls).
- `StarterPlayerScripts.Services.Cinema`: the camera when an ending takes it. Black bars in, controls
  off, captions held seven seconds, a smooth pan within a shot and a clean cut between shots, a dip to
  black to go somewhere else, your own character always drawn (even if you were zoomed into first
  person), and everything given back at the end.
- To give someone your own look, build them in Studio and put the model in `ServerStorage.Townsfolk`
  under their name.

## City Shore's finale (Level 1)

### Fifteenth pass (2026-09-29): slower, and you are always in shot

- **Half speed.** The fall is held to 110 studs a second and 10 across on the diver's own screen,
  and the server's carry over the last 400 studs is 120 studs a second (was 350): the dive takes
  about three times as long and can be watched. The swan is held longer before it closes. A caption
  opens it ("The High Dive") and the one under the water is up for nine seconds.
- **Always in shot**, whatever your camera zoom (`Cinema`).

### Fourteenth pass (2026-09-26): the dive as a scene, and people on the shore

- **The dive is a scene** (`CityShoreClient`, new, on the client). Off the board from low at its tip;
  falling alongside, circling; from the water looking up as you come down; then the water closes
  over you and the camera follows you down to a street far below with one lamp still on ("Somewhere
  under the water, a street lamp is still on."). Held until the lobby takes you.
- **Head first.** Your own client turns you over as you fall (PlatformStand, so the humanoid does not
  right you), and `DiveFinaleService.commit` now keeps that angle for the last of the fall and the
  sink, where it used to stand you back up. Everyone sees a swan dive closing to arms over the head
  (`Poses.dive`).
- **Maren** on the deck, **Sal** at the start, **Pip** halfway up (see the story, above).
- Wired through a new remote, `DiveCinema`, made by the server Bootstrap. Not yet seen in Studio.

**State on 2026-09-16:** the board works in Studio. Diving was reported sending the player back
to the route in a Short Chill run; the cause and the fix are below and **not yet seen in Studio**.
It lives in
`src/Server/Services/DiveFinaleService.lua`, and the level asks for it with `finale = "dive"`.

- **The platform.** The last chunk runs onto a tiled deck with a springboard cantilevered out
  past its outer edge, rails round the sides that are not the way in, and a flag at the corner.
  It is built in the frame `LevelService` now returns as `finishFrame`: the far end of the last
  chunk, on its exit surface, with **+X pointing away from the spiral's centre** -- the one
  direction at the top of the climb with nothing under it but sea.
- **The dive is two checks.** A player is diving once they have passed through the air just
  under the board (out past the deck's edge, within 20 studs of it along the route, 3 to 70 studs
  down) AND are over the **landing circle**: an invisible 600-stud-wide disc on the water in front
  of the tower, `DiveLandingCircle` in the platform model, selectable in the Explorer. Its nearest
  edge is 24 studs from the route's centreline, clear of the far corner of the longest chunk
  (`R1_SlimeLaunch`, 38 long, reaches about 23). Leaving the circle -- steering back in towards the
  tower -- ends the dive and the kill plane has you again. The circle alone would finish the level
  for anyone who fell off a lower turn and drifted out, so both checks are needed.
- **The finish is the sea, and the server carries the diver into it.** 400 studs above the water
  (-300 at the sea's -700) the server anchors the diver and tweens them down at the speed they were
  falling. On reaching the surface: spray, a spreading ring and a splash, the diver sinks, the
  screen fades to black (`ScreenFade` remote, `UIService.fadeToBlack`), "Level 1 Complete" reads on
  the black, the lobby takes them four seconds later and the picture fades back. A held diver is
  let go once the lobby has moved them; if nothing has after 12 seconds they are put back on the
  deck with a warning, never let go under the sea.
- **`Workspace.FallenPartsDestroyHeight` CANNOT BE SET FROM A SCRIPT.** It is PluginSecurity: only
  plugins, the command bar and the Properties window can write it. Roblox deletes a falling part
  below it (default -500) and the sea is at -700, so the first fix moved it from the dive module --
  and that line threw. `start()` died after building the board and before connecting the watch,
  so nothing was ever watching for divers and the kill plane sent every one of them back. That is
  the "dive and get teleported back" report. The engine never deletes an ANCHORED part (the
  backdrop's sea sits at -700 because of that), which is why the server takes the diver over
  above -500 instead. `check_hub.py` fails on any script under `src` that assigns the property.
- **Three things that each fail silently on their own**, so `check_hub.py` gates all three:
  the splash is a HEIGHT TEST rather than a Touched (a diver crosses about nine studs a frame
  and a trigger part is skipped outright); the kill plane must leave a diver alone, since it
  sits 40 studs under the lowest chunk and 680 above the water, which Bootstrap does by asking
  `DiveFinaleService.ownsFall`; and the old finish line must stand down, or the run completes at
  the end of the route with the dive left as scenery.
- The sea's height comes from `BackdropService.waterLevelAt`, because the swell has a 72-stud
  range. With no backdrop standing it falls back to -700.
- **The dive holds its ground.** A restart was reported coming back with no board and with the
  route's finish line live, so the run completed on arriving at the deck. So: the dive stands
  down before a level is cleared, its watch puts the platform back if it finds it destroyed, it
  keeps the old finish line disarmed, and the finish-line handler refuses to complete anyone while
  `DiveFinaleService.isArmed()`. Each repair warns once. Every run prints which ending it armed,
  and a working dive prints `DiveFinaleService: high dive armed at ...` -- printed only after the
  watch is connected, so its absence means the dive is not armed whatever the level looks like.
- `sim_circle.py` (scratch, not in the repo) flew every combination of deck height, jump or step,
  take-off point and held direction: every dive that does not steer back in lands inside the
  circle except a pure sideways walk-off at the board's root, and the diver's own client stays
  above -415 before the anchor reaches it.

## Sky Pools (Level 2)

**State on 2026-09-18:** built, not yet seen in Studio. The calm level: no scares, water sounds
only. `src/Server/Services/SkyPoolsService.lua` builds it, and the level asks for it with
`backdrop = "skyPools"` and `finale = "slide"`. The picture is `blender/skypools_plan.png`.

### How it fits together

- **The ring (`LevelService`).** A level with `ring = { turn, descend, stepScale }` gets one wide
  circle instead of the 90-stud helix. Its radius is the run's planned length (each slot at the
  mean length of the chunks it can hold, plus the gaps) spread over `turn` of a circle, so short,
  medium and long runs all sweep the same three quarters. That works out to about 100, 200 and 300
  studs. `descend` turns every step down and `stepScale` makes the steps 1.6 times bigger.
  `startLevel` hands back `centre` and `radius` for anything built round the route.
- **The build (`SkyPoolsService.build(level, parent)`),** called by Bootstrap after the backdrop
  block and parented under `Workspace.Levels`, so it goes when the level does. Every height comes
  from `SkyPoolsService.heights(startY, killY)`: the clouds' top is 14 above the kill plane, the
  final pool 220 under that, and the sea 520 under the pool. The tower tops out 90 above the start.
  The pool never goes lower than 60 above `Workspace.FallenPartsDestroyHeight`, which is read at
  build time: a long run goes down far enough that it would otherwise sit 11 studs above the -500
  line where Roblox deletes a falling character.
- **The slide (`attachSlide`)** works like the Flooded Halls flume. You hold E for 0.8 s at the
  mouth. PlatformStand is set and the root's CFrame is written each frame. On arrival you stand in
  the pool, and `finishRunFor` runs. Bootstrap sets the old finish line's CanTouch to false once
  the slide is built, and `SkyPoolsService.ownsFall(player)` exempts the rider from the kill plane
  while riding and for 15 s after landing. The return to the lobby waits 4 s.
- **Light and banner:** LightingService's `skyPools` palette (late morning, little haze) and
  UIService's level 2 look ("Sky Pools / Down through the clouds").

### What is in it

- Five **pool terraces**: at the start, and at the stable chunks nearest each fifth of the route.
  Each steps off the outer side of its checkpoint, flush with the cap. A 9-stud neck, 7.4 deep,
  swallows the straight chunk's side shelves. The terrace is 46 by 36, with a 22 by 14 pool you can
  stand in, a spill channel, a waterfall to the sea and four columns to the sea. Its dressing is
  loungers, a parasol, a towel, a ladder and, on one terrace, a diving board over the pool.
- The **finale deck**: a walkway on from the last chunk, a pool terrace off its outer side, a rail
  with an invisible guard along the inner side and the end, and an arch over the slide's mouth.
- The **slide**: 0.85 of a turn from the mouth to 70 studs from the middle. It descends on a
  smoothstep and is banked into the turn. The trough is floor plus two walls, 8 wide, and none of
  it collides. Rods hang it from the tower. The ride runs at 70 studs/s by distance along the
  slide, clamped to 8 to 15 s.
- The **fountain tower** from the sea to its basin, with bands every 70 studs, a jet, and a curtain
  of twelve falls from the basin into the final pool.
- The **final pool**, 105 in radius, 3 deep, on a dish, 8 columns and the tower. Six falls go off
  its rim to the sea, and the sea is nine 2048-stud plates.
- The **cloud sea**: wide, low ellipsoids out to 2400 studs, with a bluer underside out to 900.
- Eight **scenery pools**, 300 to 760 studs beyond the route.

### Second pass (2026-09-18, same day)

- **Water you can hear.** Each terrace's fall roars within 90 studs. Every fourth sheet of the
  tower's curtain is heard faintly round the ring. The curtain landing in the final pool is the
  loudest water in the level, and two of the final pool's falls roar too. There is a rush on the
  slide rider and a splash sound on landing.
- **Pools that answer** (`SkyPoolsClient`, new, on the client). Stepping into any pool splashes;
  wading leaves spreading rings (twelve slivers, since Roblox has no ring shape) and a quieter
  slosh. It works for your own character only. The pools are tagged `SkyPoolWater`.
- **Pool toys.** A duck or a swim ring floats in most pools and three drift in the final pool. The
  client makes them bob, turn and wander inside their pool. They are tagged `SkyPoolToy`.
- **The pump room**, under the second terrace. The hatch is cut out of the inner deck, with its lid
  standing open (STAFF ONLY) and a truss ladder down. The room is slung under the deck and holds
  two pumps with pipes up into the pool, a downpipe to the sea for the overflow, a panel, a lamp,
  a mop and bucket, and the log: "PUMP ROOM 2. Keep the water moving. Overflow runs to the sea.
  The sea runs to the drain." That line points at the next level. That terrace has no parasol,
  because its inner deck is where the hatch is.
- `check_skypools.py` also holds these: the room clears the columns and sits under its hatch, the
  hatch avoids everything standing on that deck, and the room stays above the clouds. It also
  checks that toys cannot drift into a wall and that the client is started and follows every tag.

### Third pass (2026-09-18): more to find

- **The cabana** is on the fourth terrace (dressing `cabana`), 8 wide, on the deck beside the pool
  with its door toward the water and a striped fascia. Inside is a running shower (spray, steam,
  sound), three lockers with the middle one open (a hollow shell, so its towel and note show), a
  bench, a robe on a hook and a ceiling lamp.
- **The lifeguard's chair** is on the third terrace (dressing `lifeguard`), on the far side of the
  pool from the board, facing the water. It has four posts, a seat you can stand on, a truss ladder
  up the front, a shade, a NO RUNNING sign, and a lifebuoy on its own post.
- **Hot air balloons**: three, orbiting 600 to 1000 beyond the route at 90 to 140 above the start,
  so their baskets clear every scenery pool. They are tagged `SkyBalloon`, and the client moves them
  on the server clock and flares their burners (real PointLights).
- **Gulls**: two flocks of seven, made on the client from the level model's `TowerTop` and `Gulls`
  attributes (tag `SkyPoolsLevel`). They wheel round the tower above the basin and above every
  slide rod.
- `check_skypools.py` holds these too. The cabana and the chair stay on their decks, out of the
  pool and the overflow channel, and off everything else on their terrace. The baskets clear the
  scenery pools, and the gulls clear the basin and every rod of the slide.

### Checking it

- `python blender/check_skypools.py` lays the route the way LevelService does, for short, medium and
  long runs over 300 seeds each. It checks that the meander bends no harder than the ring it
  replaces and never comes back on itself, that the terraces clear every neighbour and each other,
  that every column stands under deck or under the pool it carries, that everything standing on a
  deck stands on it and clear of everything else, that the pool is deep enough to swim in and its
  steps shallow enough to walk out of, that the slide and its rods hit no chunk, terrace or column,
  that the mouth has nothing in front of it, that the slide clears the final pool's rim and lands
  between the curtain and the rim, and that it stays under 42 degrees and 95 studs/s. It also checks
  the heights are in order and the wiring is present, including the ride's remote, the shared path
  and the terrain water being cleared. A mutation run (25 cases) confirmed each gate fails when it
  should: the four it missed the first time are what the restatement guard and the read of the
  finale terrace's length were added for.
- `python blender/plan_skypools.py [seed]` draws one medium run from the same Python
  (`skypools_layout.py`).

### Lessons from this level

- **A Ball part cannot be flat.** Roblox forces a ball's three sizes equal. The flat clouds are
  blocks with a sphere SpecialMesh, and the check fails on `PartType.Ball` in the file.
- **Ride a long slide by distance, not by its parameter.** The ring is three times further round at
  the top than the bottom, so stepping the parameter evenly made the ride fastest at the start.
- **Do not move a character from the server every frame.** That is a whole assembly replicated sixty
  times a second and it stutters, because the client is being corrected to where the server just put
  it. Sit the rider in a seat, hand that one part to their own client, and let it draw the ride from
  numbers both sides have. Keep the clock and the landing on the server, and nothing is trusted that
  should not be.
- **An arc leaves its mouth sideways.** The tangent of a circle is across its radius, so building a
  spiral slide round a tower placed straight ahead of the mouth sends the first stud of the ride off
  the side of the deck. The tower belongs beside the mouth.
- **Terrain is not part of the level.** Water filled for a level does not go when the level's model
  is destroyed, and neither does the terrain's global water colour; both have to be put back by
  hand, which is what `clearWater` is for.
- **A check that RESTATES the Luau only checks itself.** `skypools_layout.terrace_plan` is a copy of
  the terrace's geometry in Python; moving the loungers in the Luau alone broke nothing that the
  check could see. The mutation run is what found that, and the fix is the list of exact source
  lines in `check_skypools.py` that must still be in `SkyPoolsService.lua` -- the same trick the
  `heights` formula already used. Anything the Python restates needs one.
- **Model what is actually solid.** The first check treated each terrace as solid to the sea and
  "found" the slide running into the start terrace on a short ring. Only the four columns go down,
  and they are well clear.
- **A new ending reuses the old one's words.** The slide's block also stands the finish line down
  and calls `finishRunFor`. That quietly satisfied two of `check_hub.py`'s dive gates, which now
  read only the dive's own block.

### Fourth pass (2026-09-22): seen in Studio, and rebuilt from what it looked like

Played, and it showed. The route read as a lap, the terraces were squares with a square pool in the
middle, the water was a sheet of glass you walked through, neighbouring terraces' columns stood past
the deck you were on, and the slide stuttered and rode standing up. All of that is what this pass is.

- **The route is a MEANDER, not a ring** (`layout = "meander"`, `meander = { amplitude = 0.7,
  wavelength = 900, descend = true, stepScale = 1.6 }`). `LevelService` walks it in 2-stud steps
  (`MEANDER_STEP`), because the heading is a function of distance travelled and there is no closed
  form to jump to: the heading swings `amplitude` radians either side of straight ahead on a sine
  of `wavelength` studs. The route never crosses itself and never comes back on itself, so what is
  ahead of you is somewhere you have not been. `startLevel` returns `radius = nil` and
  `layout = "meander"`; anything built along the route is placed from the chunks and the finish
  frame, which every layout has.
- **Terraces take alternating sides** of the route (`terraceBeside` now takes the outward direction
  rather than a centre). That is the fix for the columns standing past a deck: on a short ring the
  next terrace round was barely a hundred studs away and its columns rose right beside yours.
- **The terrace is not a square.** A narrow walk off the checkpoint, shoulders where it flares, a
  wide middle with a sun deck either side of the pool, and a rounded prow past the pool that the
  water goes over. Nine columns to the sea: four under the pool's corners, four under the sun decks
  and one under the prow. The walk in needs none -- it is a short span between the neck, which is
  part of the chunk, and the pool block, which is on columns.
- **The water is Roblox terrain water, and you swim in it** -- the terrace pools and the final pool
  the slide lands in, which is ten deep now instead of waist deep. The terrace pool is 9 deep with four steps
  at the inner end to walk in down and back out of, a ladder at the deep end, a waterline band and
  two lights set into the walls under the surface. `fillWater` remembers every region and
  `SkyPoolsService.clearWater()` takes it all out again -- terrain is global and does not go when
  the level's model does, so Bootstrap's teardown calls it and `build` calls it first. The terrain's
  own water colour and waves are saved and put back the same way the lighting is. What is left where
  the water is, is an invisible marker part still tagged `SkyPoolWater`, so the client's splash and
  ripples and the floating toys still know where the surface is.
- **Better things on the deck.** Loungers are a frame on feet with slats, a back on its hinge with a
  prop and a pillow, and a folded towel; the parasol has eight ribs, eight two-tone panels with
  scallops, a vent and a finial. New: a pergola with a climber up one post, stone planters with
  small trees, and a rinse shower over the queue at the slide's mouth. The sun side of a deck holds
  either the loungers and what goes with them or the cabana, never both; the shade side holds one of
  the pergola, the board or the lifeguard's chair.
- **The waterfalls are three sheets, not one**: bright and nearly solid at the lip, wider and softer
  behind, widening as they fall, with a rolled lip of foam, spray off it and mist drifting back up
  in the long ones.
- **The slide's shape and timing are shared** in `src/Shared/SkyPath.lua`, because both sides now
  work the ride out from the same numbers. The trough has a film of water running down it, a rolled
  lip along each wall, hoops with pennants and the rods that hang it off the tower.
- **The ride is a sled you sit in.** The server sits you in a Seat, keeps the clock, and hands the
  sled to your own client over the new `SkyRide` remote; from then on your client writes the sled's
  CFrame every frame from `SkyPath` and the start time, which is smooth and replicates nothing. If
  your client never answers -- the file is not pasted in, or it is loading -- the server drives the
  sled itself and the ride is the same length and ends in the same place. The server decides where
  you land whatever the client did with the sled.
- **The tower stands beside the slide's mouth** (`TOWER_ASIDE = 150`), not ahead of it. An arc's
  tangent is across its radius, so a tower straight ahead would have thrown the first stud of the
  ride sideways off the end of the deck. The mouth is kept clear: nothing may stand within
  `MOUTH_CLEAR` of the trough ahead of it, the terrace off the walkway stops eight studs short, and
  the arch stands behind the mouth and wider than the trough.
- **Scenery pools keep off the route.** They used to be laid at a radius outside the ring, which a
  route that wanders has no equivalent of, so each one is now tried at a few angles until it finds
  one at least 300 studs from every chunk.

### Fifteenth pass (2026-09-29): half speed

- `SkyPath.SPEED` is 36 (was 70), clamped to 16 to 30 seconds, so the slide takes about eighteen
  seconds; the pool is held for 3.2 seconds after the splash, and the caption for seven.
- Mrs Okafor, Dev and Rudy are dressed (see the story), and there are three things to read.

### Fourteenth pass (2026-09-26): the slide as a scene, and people at the pools

- **The slide is a scene** on the rider's screen (`SkyPoolsClient` with `Cinema`), captioned "The Long
  Way Down / Everyone takes it in the end.": over your shoulder down the slide as you push off; from
  far out in the sky, going round the tower with you; from just ahead of the sled looking back at you;
  from the pool as you come down into it; and the pool with the tower rising out of it held for 1.6
  seconds after the splash, then the camera is yours. The bands and the drop counter give way to the
  scene's bars (they still show, and the splash still flashes, in a place without `Cinema`). If the
  sled goes mid-ride, the camera is given back at once.
- **Arms up the whole way down**, seen by everyone (`Poses.sled`): the server tells every client
  (`SkyRide`, `"pose"`), since joints turned on one client are seen on that client only.
- **Dev** at the first terrace's walk in with towels, **Mrs Okafor** sitting on the edge of a lounger
  in her sunhat, **Rudy** at a record deck between two speakers beside the queue for the slide, clear
  of its painted lane (see the story, above). Rudy shouts after you when you go.
- Not yet seen in Studio.

### Sixth pass (2026-09-23): what play found

- **The flanking shelves are gone from the chunk kit** (`ChunkBuilder`, `S1_Straight`,
  `P1_HoneyCorridor`, and `C1_SlimeToPace`'s honey landing). They were five and four studs of dry
  ground each side, a stud below the top, and they did two things nobody wanted: the stable chunk's
  shelf ran level with its neighbour, so you could walk alongside the honey instead of over it, and
  stepping off the Needoh field landed you on the next chunk's shelf instead of falling. The
  butter-wax bend keeps its catch on the outside of the turn and the soap chunk keeps its flanks
  (soap dissolves; the chunk has to stay crossable). `check_chunk_forms.py` holds the rest out.
  **This changes the chunk templates, so ChunkBuilder has to be re-run in Studio.**
- **The pump room's hatch is six studs, not four**, its ladder runs past the deck rather than up to
  it, and there is a grab rail either side of the opening. At four studs through a ten-deep deck it
  was a shaft you got stuck in.
- **You can lie on the loungers and sit in the lifeguard's chair.** Both were blocks shaped like
  furniture; the cushion and the seat are Seats now, and the lounger's is tipped back with the bed.
- **Translucent chunks seen from ABOVE.** They read from the side and from underneath and vanished
  from overhead, which is the signature of a reflection rather than a transparency: the whole lower
  hemisphere of this level is white cloud, so a glossy top face was mirroring white onto white. Two
  small steps: the `skyPools` palette turns `EnvironmentSpecularScale` down to 0.5 (it is per-palette
  now), and the cloud sea is two steps off paper white with no reflectance of its own. If it is
  still washing out, the next lever is this level's own transparency on the glass materials.

### Fifth pass (2026-09-22): the water moves and the ride says something

- **The falls fall.** Three sheets of glass is the right shape and none of the motion, so: streaks
  thrown off the lip that live long enough to travel the fall and squash into lines as they gather
  speed; a landing at the bottom with foam, a boil and spray going back up; and, on each client, a
  bright band travelling down every sheet (tag `SkyFall`, `SkyPoolsClient.moveFalls`). The shower
  heads over the queue at the slide's mouth are falls too, so a fall narrower than four studs
  leaves out the foam and the mist.
- **The ride has something on screen.** Eight to fifteen seconds of slide used to be silent. Now
  the edges draw in, two soft bands give the speed somewhere to read, one line counts the drop down
  to the water, and the splash flashes white as you hit it. It is built and torn down by
  `SkyPoolsClient` alone, and it is gone before the completion banner comes up.

### Open for this level

- The fourth pass has not been seen in Studio: the meander's shape from inside it, swimming in the
  terrace pools, the new ride, and whether the terrain water's edges read well against the tiling.
- The pool tile MaterialVariant (`PoolTileBackdrop`, shared with City Shore) is used on the pool
  floors when it exists, taking its base material from the variant.

## The Sunken City (Level 3)

**State on 2026-09-18:** first version built, not yet seen in Studio. The eerie level. It was Far
Water, a spiral with no background. `src/Server/Services/SunkenCityService.lua` builds it on the
server, `src/Client/Services/SunkenCityClient.lua` moves its parts on each client, and the level
asks for it with `backdrop = "sunkenCity"` and `finale = "drain"`. The picture is
`blender/sunkencity_plan.png`.

### How it fits together

- **The ring (`LevelService`).** It uses the same ring as Sky Pools, but flat: `stepScale = 0` turns
  the steps off, and the new `wave = { height, every }` adds a swell. The route rises and dips 3.5
  studs either way over every ten chunks, never more than 2.2 from one chunk to the next. The ring
  sweeps 0.8 of a turn, leaving a fifth open for the harbour.
- **The pool** is slime, jello soda, ice and oobleck **(you)**, filled out with salt, foam, the
  Needohs, two soap chunks and bubble wrap **(suggested)**, because jello soda is the only pace
  chunk among the four. Nothing in it climbs or drops, so the route's height is the swell alone.
  The headline material (the lobby pad) is Oobleck.
- **Heights (`SunkenCityService.heights`).** The surface is 9 under the lowest chunk's origin, and
  every chunk's underside clears it by 5. The kill plane is 31 under the surface, so a fall goes
  visibly into the water first. The murk layer is at 35, the sea floor at 100, and the drain's
  shaft ends 60 below the floor, well above -500.
- **Bootstrap** builds the city after the backdrop block, parented under `Workspace.Levels`. It
  attaches the drain with `SunkenCityService.attach`, sets the old finish line's CanTouch to false,
  and exempts a rider from the kill plane with `SunkenCityService.ownsFall`. The undo runs before
  the next run is built.
- **The client** starts from the client Bootstrap with a timeout, as `SkyPoolsClient` does, so a
  place without it loses only this level's moving parts.

### What is in it

- **The water.** The surface is glass plates with two round holes, one for the aquarium's tower and
  one for the whirlpool. Each hole is cut square and its corners filled back with strips that stop
  inside the hole's own wall band. Under the surface are a murk layer and the sea floor, and the
  floor has a hole for the drain. Underwater parts are coloured darker and bluer by depth
  (`drowned`), because glass does not dim what is behind it.
- **The city.** Bands of lots in rings round a plaza, cut by eight avenues, with none outside the
  ring in the harbour sector.
  - Next to the boulevard, flats are flooded and roofless, their top storeys 2 to 3 studs under
    the surface with the furniture still in them.
  - Further out, apartments and offices break the surface, but only where the whole lot is
    `EMERGE_CLEAR` (40) beyond the route's reach.
  - Houses have pitched roofs made of two tilted slabs.
  - The multi-storey car park has four decks, with its top deck of cars 4 under the surface.
  - Ten lone towers stand out in the haze.
  - Every part of the city is non-collidable, so a fall is never stranded on a submerged roof.
- **The clock tower** stands in the plaza, stopped at 4:12. Every half minute the client moves all
  four minute hands forward one minute and back.
- **The boulevard** under the route has road-sign gantries whose signs hang 5 to 11 studs down.
- **The harbour** has quay walls, a gantry crane standing out of the water, a fishing boat with its
  bow out, and buoys chained to the floor that bob on the client.
- **The thing.** It swims the boulevard against the route, 6 studs inside the centre line, at 12
  studs/s, 24 to 34 under the surface. It swings 85 studs out round the harbour to stay clear of
  the whirlpool. Its body is 18 segments with pale eyes, back fins and a fluke, drawn only on
  clients from the attributes on the Sea model and the server clock.
  - As it comes within 95 studs, the lapping and the wind fall away and a low rumble comes up.
    Then the water darkens and a small colour shade comes in.
  - A Hardcore fall while it is under you gets a deep thud and a darker moment. Chill never gets
    the fall event, so it only watches.
- **The aquarium** is off the checkpoint nearest two fifths of the way round.
  - A landing leads to a round stair tower standing in the water, with a door and a sign.
  - Inside, a stair spirals down 30-odd steps to the tunnel level, 22 under the surface and 9 above
    the kill plane. It has three lamps and drips.
  - A glass tunnel 64 long runs on pillars to the sea floor, with kelp and three shoals of fish
    that the client makes and moves.
  - The gallery at the end has a window onto the deep, a bench, and a PLEASE DO NOT TAP ON THE
    GLASS sign.
  - Tapping thuds (`ClickDetector`). Tap three times within 5 s as a Hardcore player, once a run,
    and something taps back: a heavy thud, the glass shivers and the lamp stutters. In Chill
    nothing answers.
  - The client tints the view teal while you are in the tower below the water, the tunnel or the
    gallery.
- **The drain.**
  - The pier runs on from the last chunk, with bollards, chains and an invisible guard along each
    side, so the end is the only way off. It has a sign: HARBOUR DRAIN. KEEP CLEAR.
  - The whirlpool starts 20 past the pier's end: a foam rim and five rings turning faster inward
    (turned by the client), with the rush sound.
  - Stepping off the end (inside 20 of the axis, below the pier) sets off the ride. It goes round
    and in down the funnel, then straight down the current into the drain and 60 down a black
    shaft, 6.5 s in all.
  - `finishRunFor` runs at the bottom, in the dark, and the banner reads "The Sunken City / Pulled
    down into the dark". There is no forced blackout: the darkness is the shaft.
- **Sound** is `impact_water` everywhere, pitched per use. The thud is the character's own
  `action_jump_land`, the one new built-in path. The ambience sits on a part at the city's middle,
  never loose in the model, so the lobby does not hear the harbour.
- **Light** comes from LightingService's `sunkenCity` palette: a grey-green afternoon with real
  haze, a step under the default.

### Checking it (third pass)

- `python blender/check_sunkencity.py` lays the street the way LevelService does, for short, medium
  and long runs over 120 seeds each. It checks that the meander bends no harder than the ring it
  replaces and never comes back on itself; that every block's frontage is on the kerb and nothing
  that may break the surface stands within EMERGE_CLEAR of the route's reach; that the thing's body
  and its wander stay inside the street, clear of the gantry legs, the lamp posts, the aquarium's
  tower and the dry flat, under the road signs, and that it turns back long before the whirlpool;
  that the aquarium and the dry flat clear their neighbours and stay out of the harbour; and that
  the wiring is there, including the drain's remote, the shared path, and the prompt on the glass
  being connected to something. A mutation run (23 cases) confirmed each gate fails when it should.
- `python blender/plan_sunkencity.py [seed]` draws one medium run: every lot as the ground it stands
  on, the street through them, the thing's patrol, and sections through the aquarium and the drain.

### Checking it (first pass, for the record)

- `python blender/check_sunkencity.py` lays the ring for short, medium and long runs over 300 seeds
  each. It checks that the route stays out of the water and that falls are seen and caught. It
  checks that nothing breaks the surface near the route. It checks that the thing touches nothing:
  boulevard, gantry legs and signs, the tower, the whirlpool, the buoys, quays, boat and crane. It
  checks that the aquarium and the pier fit, and that the wiring is complete: every attribute the
  server writes is read and every tag is followed. A mutation run (22 cases) confirmed each gate.
- `sunkencity_layout.py` restates a few literals from inside the Luau (gantry legs, pier piles, the
  crane's distance...). Each carries its exact Luau text, and the check fails if that text changes.
- `python blender/plan_sunkencity.py [seed]` draws it from above and in section.

### Second pass (2026-09-18, same day): the thing surfaces, the dry flat, the mirror

- **`src/Shared/SunkenPath.lua` (new, ReplicatedStorage.Shared).** It holds where the thing is and
  when it surfaces, used by both the server and every client, so a player can only be taken by a
  surfacing they saw. The body constants moved here from the client.
- **The surfacing.** It starts 45 s after the build, then every 80 s.
  - The first 5 s are the warning: the sound drops, bubbles rise and a dark patch spreads.
  - Then comes the heave: the body near the spot rises until its centre is 7 under the water. Its
    back stays just under the surface and its fins come through, clear of the chunks' undersides.
  - At 1.2 s the surge sprays over the route.
  - It never surfaces in the harbour or within its heave's reach (plus 12) of a road sign. The
    server writes the signs' angles as `QuietAngles`.
  - The server (`attach`) takes, once per surfacing, every player who is Hardcore, above the water,
    within 26 of the spot and not inside a `SunkenShelter` box (the aquarium, its tower, the flat).
    It calls Bootstrap's new `sendBackToStart`, which runs the kill plane's Hardcore reset step for
    step, and `check_sunkencity.py` holds the two to the same steps.
- **The last dry flat**, off the checkpoint nearest 0.7 of the way round (never the aquarium's, never
  in the harbour).
  - A plank gangway with rope rails and guards leads in.
  - The building stands from the sea floor, solid except for the stairwell's shaft (cut with the
    same `subtract` the water uses). Its top floor is 24 by 26 by 9, with a door, a window and a
    parapet roof with a water tank.
  - The lamp by the door is on. Inside are a sofa facing the window, a radio, a counter, a kettle, a
    fridge and the calendar.
  - The stairwell has a railing with a guard. The spiral stair goes down to a landing 1.5 under the
    water, where a doorway is blocked by a fallen wardrobe and the notice reads FLOODED. NO ACCESS.
    The water laps and drips there.
  - The bathroom has the sink, **the mirror** (tagged `SunkenMirror`), a tub of dark water, and a
    cold lamp (tagged `SunkenMirrorLamp`) that stutters on its own every 12 to 30 s.
- **The face in the mirror.** A Hardcore player who stands in the `SunkenMirrorZone` for 1.6 s
  gets one 50% roll per run, while it has never happened on the server. `mirrorShown` is a
  module-level flag, so it is once a server. On success the server stamps `MirrorFace` on the
  player. That client stutters the lamp, shows a pale face with dark hollows on the mirror for half
  a second over a low drone, then puts the light out for 0.8 s, and the face is gone. Chill players
  never roll.
- **The pier's lantern** hangs from its own post and arm at the far end: a warm PointLight.

### Fifteenth pass (2026-09-29): half speed, and F7

- The drain takes 13 seconds (was 6.5), the outfall 16 (was 9) and the reveal 7 (was 3.4); the
  station's caption stays up for seven.
- **F7 did not hide the Studio panel**, because the listener skipped any key Roblox had marked as
  handled. It now starts hidden, F7 shows and hides it whatever Roblox thinks of the key (except
  while you are typing), and it has an x to click.
- The attendant and the fisherman are dressed, and there are three things to read along the route.

### Fourteenth pass (2026-09-26): on through Outfall 3 to the pumping station, and more fish

From a recording: "much better", with the fish and the scenes finally showing. Asked for **(you)**: an
ending that is properly cinematic and goes on to the end of the tunnel, five seconds to stand there
after LEVEL COMPLETE, more to the fish, and then the story and scenes for the other two levels (see
the story section, City Shore and Sky Pools).

**The ride goes on.** At the bottom of the sluice, the door marked OUTFALL 3 has burst open, and the
water carries you out through it: on your back, feet first, lifted off the floor and swaying, 140
studs down a culvert of ribs and caged lamps (`SunkenPath.outfallAt` and `outfallFrame`, nine
seconds). The walls are written on: OUTFALL 3, WHERE IS THE KEY MAN, a long tally, and KEY HOLDER
ONLY BEYOND THIS POINT. The camera goes ahead of you looking back, alongside, over your shoulder, and
then into the hall as the water sets you down on your feet in it.

**The Harbour Pumping Station.** A hall 32 by 36, 16 high: three pumps with their gauges on zero; the
control desk with its lever down, GATES: CLOSED, and a note ("If the water comes, open the gates.
The key is with the key holder."); a key board with hook 3 empty; the clock on 11:52; a rack of time
cards; a sump grate churning; one hanging lamp; a green emergency lamp over a shut door marked LOWER
GALLERY. NO ENTRY. (the Flooded Halls). As you land, "Harbour Pumping Station / Outfall 3. The gates
are still closed." comes up and the camera closes in on the one card that is out of the rack. It
says `KEY HOLDER / <your display name> / 14 AUG / NOT CLOCKED IN`. After 3.4 seconds the camera is
yours, LEVEL COMPLETE comes up, and you have **six seconds** in the station before the lobby
(Bootstrap's return delay went from four to six for every level).

**Nothing kills you on the way.** The kill plane leaves riders alone, and arrivals for 30 seconds
(`SunkenCityService.ownsFall`); the rider's speed is cleared every step on both sides, as before.

**More fish.** A shoal every 45 studs of the route, of 14 to 22 fish, and they dart out of your way
when you swim within 13 studs of them, drifting back into the shoal as you go.

**`SunkenNPCs` is now `Townsfolk`**, the people of every level (see the story). Delete
`ServerScriptService.Services.SunkenNPCs` after pasting `Townsfolk`.

Checked: `check_story.py` is new, `check_sunkencity.py` now holds the outfall's and the reveal's
lengths, the fish scattering and the shoal spacing, and 32 new mutations are caught against a clean
baseline. The earlier suites (passes 8 to 13) were pointed at the renamed modules and all catch.

### Thirteenth pass (2026-09-26): the client found, joints of either kind, the attendant runs, the drain as a sequence

From two recordings and their Output. The flood worked (terrain water, swimming, spray, leaflets).

**Why SunkenCityClient never ran: an old client Bootstrap.** The server's Studio check reported
`SunkenCityClient loads (twelfth pass)`, so the module was fine; the client printed `[client] Bootstrap
ready` from line 255 where the current file prints it from line 272 -- and the seventeen lines missing
are exactly the loop that starts SkyPoolsClient and SunkenCityClient. The place's Bootstrap is a copy
from before those levels existed, so neither level's client has ever started. Paste
`src/Client/Bootstrap.client.lua` over it. It now also says `[client] started SunkenCityClient` (or why
it failed); and the Studio notice, which was cut off at a narrow screen's edges, now fits and says
exactly this when the module loads but no client says hello.

**Joints of either kind.** The same Output showed a player's character with fifteen
AnimationConstraints and no Motor6D (Roblox's newer avatar joints). Everything that turned joints --
the ride's flail on the server and on the client, the people's poses -- turned Motor6Ds only, so the
rider's arms never moved and the fisherman stood beside his crate instead of sitting on it.
`SunkenPath.joints` finds either kind; `SunkenPath.turn` offsets one on the server (a Motor6D's C0, or
the AnimationConstraint's parent-side attachment); `SunkenPath.drive` sets one the client's way
(its Transform).

**The drain, as a sequence.** Grabbed (thrown right back), spun round the funnel three times, sent
head over heels twice down the shaft and righted to land on their feet (`SunkenPath.tumble`), with a
trail of bubbles and spray streaming off the rider for everyone and a splash and a thud where they
land. The camera cuts between four shots: close on the face at the grab, circling in the funnel, from
over the shaft looking down, and from low in the sluice looking up -- held while they land. And they
no longer fall THROUGH the sluice's floor: the server's ride took no speed away, so the rider's own
client kept adding gravity under every position it was handed and landed at hundreds of studs a
second. Now both rides clear the rider's speed every step, the server takes the rider's physics while
it draws the ride, and the floor is six studs thick. The whirlpool's throat breathes a column of
bubbles, whatever the client is doing.

**The attendant runs.** When the glass goes they jump with their arms thrown up and their cap flying
off, and run screaming (`AAAAAH!`, `THE GLASS!`, `RUN! GET OUT!`...) past the bench, through the tunnel's
doorway and down the tunnel; once the water is deep enough they swim (under it in the tunnel,
blowing bubbles: `GLUB!`), tread water at the surface in the tower complaining about their job, and
when it has drained walk back with their head down, put their cap back on and say something about a
mop (`SunkenNPCs.panic`, on `aq.escape`).

**More water where they stand.** Jets through the cracks round the frame, fanned to the sides (bubble
streams once under), the sea sheeting down the wall under the window, a foaming surge racing across
the floor, and the notice asking you not to tap the glass torn off its wall and floating.

**Found on the way, and a new check.** The flood's setup read `flood` in a loop above its own `local
flood`, which Luau takes as a nil global -- the glass would have thrown on every run. Neither checker
could see it, so `check_luau_syntax.py` now RESOLVES every name: each must be a local in scope at that
line, a parameter, a loop variable or a Roblox global. And the Ferris wheel (still "NO Ferris wheel"
in play, though the layout model finds a place on 6000 sampled layouts, so the model and the game
disagree somewhere) now tries both sides of the street at three distances, and the report says why
each place was refused when none fits.

Checked: 27 new mutations caught against a clean baseline, and the earlier suites again.

### Twelfth pass (2026-09-26): a flood to swim in, a ride that moves without the client, and why the client does not run

From two recordings and the Output of the same session: `SunkenCityService: ...'s client did not take
the ride down the drain`, no Studio panel, no `SunkenCityClient: running` line. So SunkenCityClient is
not running at all on that client, and every recording since the sea life went in has shown exactly
that: no animals, no flood, and the server's stiff ride.

**Finding out why, for certain.** It is not a syntax error: `blender/check_luau_syntax.py` (new) is a
real parser for Luau's grammar, types and all, with the compiler's own extra refusals (a statement
after `return`/`break`/`continue`, `break`/`continue` outside a loop, assigning to a call, and a call
whose `(` starts a new line), and every file in `src` parses. Proven on 22 kinds of broken Luau it
rejects and 16 tricky valid ones it accepts. So the cause is in the place, and the server now finds
it: in Studio, SunkenCityService looks for `StarterPlayerScripts.Services.SunkenCityClient`, says
where it is if it is somewhere else, says if it is a LocalScript or Script instead of a ModuleScript,
and REQUIRES it the way Bootstrap does, printing its own load error or saying it never finished
loading (an infinite yield); and it warns if StarterPlayerScripts has no LocalScript to start it.
Each client says hello as it starts (`SunkenCityService: SunkenCityClient is running for ...`), and in
Studio anyone whose client never does gets a notice on screen after 25 seconds. Pasted as a
LocalScript by mistake, the client now starts itself.

**The ride moves without the client.** The flail and the lean are `SunkenPath.flail` and
`SunkenPath.tumble` now, shared: the rider's client turns the joints through their Transform, and
when it is not running the server turns them through C0 (which every client is sent) and leans and
rocks the rider itself. The camera scene still needs the client.

**The flood is water you swim in.** Terrain water, like the flooded floor under the flat: one level
rising through the gallery, the tunnel and the tower (the gallery full in `TAP.rise`, 8 s, the tower
on up to the sea), rewritten only while it moves. A torrent pours through the hole (falling water
streaked by its speed, spray), foam churns where it lands and follows the water up, bubbles rise
through every room, the aquarium's leaflets float up and drift, and once the hole is under, the sea
comes through it as a rush of bubbles. Under it the view goes murky (Roblox) and every sound goes dull
(the client's UnderWater reverb, from one terrain voxel at the camera). It stays until `TAP.hold` (40
s), drains over `TAP.drain` (6 s) and the glass is whole. Nobody is washed out any more, and the boxes
of see-through parts that "filled up" are gone. Registered with the level's swimmable water, so a
level torn down mid-flood leaves none behind.

**And:** the chest turned to face the window; the Ferris wheel has sixteen places to try instead of
five (the window rule left it nowhere on 12 of the modelled layouts, and "NO Ferris wheel" in play;
the checker's model of its placement now includes that rule); the hub statue has no score sign over
it (four overlapping lines, 0:00.00 for any level without a record, and the leaderboard already says
it); and in Sky Pools the water is no longer Glass, which hid every see-through chunk behind a pool
or a waterfall, nor is the soda jelly, which mirrored the open sky at a low angle and washed out.

Checked: 31 new mutations caught against a baseline that must pass first, and the 70 before them.

### Eleventh pass (2026-09-26): the ride as a scene, the sea coming in, and why nothing moved

From four screenshots of play: the attendant's words cut off by the window frame, a jellyfish ringed
in slime green, a stiff figure going down the drain, and a plain chest.

**Why the animals, the flood and the ride all failed together.** SunkenCityClient's second line was
`require(ReplicatedStorage.Shared:WaitForChild("SeaRig"))`, with no timeout. In a place without
SeaRig pasted in (or with an older copy that failed as it loaded) that line waits forever: the whole
client stops there, with nothing in Output but an "Infinite yield possible" line. Every animal, the
flood, the Ferris wheel turning, the serpent and the ride's own drawing are the client's, so all of
them were missing at once, and the server's plain ride (upright, turning, stiff) was all anyone saw.
Now SeaRig is looked for with a timeout and checked for everything the client calls; without the
whole of it the animals are built from parts and Output says why. The client says which version is
running as it starts; in Studio a panel at the top left (F7 hides it) shows what it is drawing:
SeaRig's state, the animals and the nearest one, shoals, kelp, gulls, the Ferris wheel, the thing,
the flood, the ride and anything that failed. Each animal now moves on its own, so one that throws
stops only itself. And the server warns when a rider's client never takes the ride.

**The sea coming in is the server's.** Drawn only on the clients, it was never seen by a client
that was not running. Now SunkenCityService draws it for everyone: the pane cracks right across and
groans, then bursts into shards that are thrown in and land on the floor; jagged teeth of glass stay
in the frame; the sea pours in through the hole as a sheet of falling water with drops streaming
down it, foam where it lands and the roar of it; and one level of water rises through the gallery,
the tunnel and the tower at one rate, the gallery full after `TAP.rise` (8 seconds now, slow enough
to stand in and watch; it was 3.5). The pour's foot rises with the water. `TAP.wash` (1.5) later
anyone inside is washed out: the sea closes over the screen ("The sea carried you out"), you are
carried to the checkpoint, and it clears. At `TAP.hold` (24) the water goes down over `TAP.drain`
(4) and the glass is whole. The client only scrolls the water's textures smoothly and turns the view
green and soft under it.

**The drain is a little scene.** Your camera leaves you: it circles in close while the whirlpool drags
you round, then looks straight down the shaft from over its top as you drop away, with black bars
across the top and bottom of the screen and your controls off until you land. You go round leaning
back against the pull, rocked about, instead of stood upright. Every client flails you (arms thrown
up and waving, elbows working, legs kicking, head thrown back; R15 and R6), because joints turned on
one client are seen on that client only; and over your head, for everyone, you shout HELP!, AAAAH!,
HELP ME!, NOOOO!... A reset part-way down ends the scene.

**The jellyfish is its own**: violet rings instead of slime's green, violet tendrils that hang
further, a real light that flashes where you land and fades, and motes of it drifting up.

**The chest** (`blender/gen_treasure.py`, five meshes): a planked sea chest with its barrel lid thrown
open, iron bands, brackets and a torn hasp, a heap of coins with a crown and a goblet on it, rubies,
a string of pearls over the edge and coins spilled on the rock, with a faint warm light on the gold.

**Smaller things.** The people's speech is drawn over the room (it was hidden by the window frame),
bigger, bolder and boxed; the attendant's Talk key is F (the glass's is E). The Ferris wheel keeps
190 studs from what the gallery's window looks at.

Checked: the client starts without SeaRig and says which code is running; the panel exists only in
Studio; each animal is guarded; the server draws the water, the pour, the shards and the teeth, and
washes nobody out before the gallery is full; the scene finishes the moment the ride does, gives the
camera and controls back and puts the joints back to rest; the jellyfish's colours are violet; the
chest's meshes are sizes SeaRig knows. 30 new mutations caught, and the 45 before them again.

### Tenth pass (2026-09-25): the glass, the animals, landmarks, the side streets and people

From a recorded play-through (the gallery, the tap, and a run down the street).

**What the tap did, from the video.** The pane cracked at the third tap, cracked further and wept at
the fifth, and went at the seventh; three and a half seconds later the server washed the player out
to the checkpoint, exactly on schedule. But no water was drawn at all -- no rising water, no shards,
no jet -- because the client only ever learned of the flood through one attribute signal, and that
signal was missed. It now ASKS: `stepFlood` reads the level's `Flood` every frame, starts the flood
when it changes and drains it when it goes to 0, and says once in Output that it is filling N spaces
(or warns that none have arrived). And the sea now visibly comes in: a sheet of water pouring from
the hole to wherever the water has reached, with spray where it lands and the rush of it, and the
rising surface rippling like the sea's.

**Only the window with the notice can be tapped.** The prompt was on the tunnel's panes as well;
now it is on the gallery's window alone.

**The animals were there and could not be seen.** They wandered up to SWIM_REACH either side of the
centre line, so half the time they were under the chunks; they were dark greys and greens; and the
big ones were up to twenty studs down. Now each swims in a lane BESIDE the route (`SWIM_LANE`, 15 to
19 out, never nearer than the route's edge), the shoals likewise, a little nearer the top, in the
palest colours their kinds come in, with more of the ones you see best (dolphins, turtles). If they
still do not show, the client's report line says whether their meshes were drawn, refused (and
why) or never imported.

**Landmarks** (`blender/gen_landmarks.py`, ten meshes): the Deco tower (stone piers over dark glass,
a brass crown of sunburst arches, a needle), the Needle (an observation tower: tapering shaft on
three fins, saucer pod with a band of glass, mast), the Twin towers and their skybridge, and a glass
block that has started to go over, its top floors broken at one corner. Each stands on the sea floor
in its own square, 300 to 330 off the route, short of where the things at the back swim; the spires
carry real aviation lights. Tiers of parts stand in when the meshes are not imported.

**The side streets** have things in them now: utility poles down every other one, wires sagging
between them; boats in the others (`blender/gen_boats.py`: rowboats and motor launches, some turned
over), bobbing like the buoys; a street sign at every corner on the boulevard, the street's name on
one blade and SEA BOULEVARD on the other; METRO totems on the boulevard's pavement; and now and then
a lettered sign on a roof (HOTEL, BANK, CINEMA...). All of it stands past EMERGE_CLEAR of the route.

**People** (`ServerScriptService.Services.SunkenNPCs`, new; `Townsfolk` since the fourteenth pass): the aquarium's attendant beside the
notice (talk to them; tap the glass and they object, then shout, then tell you to run), a fisherman
on a crate on the pier with his rod over the rail, and someone on the Deco tower's first ledge,
facing the street, with no face. Built on the server as real R15 characters from a
HumanoidDescription and posed by turning their joints, so no animation or asset has to be uploaded;
a plain figure of parts stands in if a character cannot be built. To dress one yourself, make the
character in Studio (Avatar > Rig Builder), dress it, and put it in `ServerStorage.SunkenNPCs` named
`Attendant`, `Fisherman` or `Watcher`.

Checked: the window alone is tappable; the client asks for the flood and pours it; swimmers and
shoals keep to their lanes; every landmark's height is its mesh's, it fits its square (the lean
counted), the leaning one's front edge stays on the floor, and each has somewhere to stand on every
run; everything in the side streets and the metro keeps off the route; the people are wired in and
the attendant hears the glass. 15 new mutations caught, and the 32 before them again.

### Ninth pass (2026-09-25): the thing as a serpent, and the client made cheaper

**The thing under the route is one body now** (`blender/gen_serpent.py`, `Sea_Serpent`): a blunt
skull, heavy brows over the pale eyes, barbels hanging from the jaw, gill grooves, a body of faint
rings with a keel down the back, a scalloped crest of raked spines that fades toward the tail, and a
fluke. Eighteen bones, one per segment, and the client lays them through the same nineteen points
SunkenPath gives the part-built body, so it is where it always was; it bends along its length
instead of hinging at eighteen joints. The eyes are still the client's pale parts, carried on the
posed head. Where it doubles back at each end of its patrol it turns about UP (`SeaRig.follow`'s
`level`) rather than the shortest way, which would have rolled it onto its back. Part-built, as
before, when the mesh is not imported.

It is held to exactly the envelope the part-built body had. No pectoral fins, because the body
turns up to 0.42 radians off the path and a fin swept back off its side would swing out past the
2.7 studs the dry flat leaves; the fluke's reach under that turn is measured by the generator
(`side_reach`) and `monster_reach` uses it; the crest stays under 1.3 girths and the barbels over
0.75 under. The checker also holds the generator's joints, spacing and girth to SunkenPath's and
the service's.

**Bugs fixed.**
- `step()` only moved the thing when it had part-built segments, so a mesh-drawn serpent would
  never have moved, and the mood would never have darkened as it came near.
- `SeaRig.follow`'s shortest turn had no answer for a bone pointing back the way it came: it did
  nothing, or rolled the bone over. A half-turn about UP is taken there now.
- The slime effect, which the jellyfish share, stretches the platform mesh 2.6 times its height
  while you stand on it; on a bell that plunged the tentacles twenty studs into the sea. The
  jellyfish no longer stretch.

**Cheaper to run.**
- The thing's nineteen points are worked out together (`SunkenPath.body`), the surfacing once a
  frame instead of nineteen times.
- The mood (the shade, the rumble, every plate of the sea and every ambient sound) was written
  every frame, and found the ambient sounds with `GetTagged`, a new table a frame. It is written
  only when it moves by a two-hundredth, and the sounds are kept by their tag.
- Lit windows and aviation lights were written every frame whatever their state; now only when it
  changes.
- Nothing is animated far from the camera (`SEEN`): swimmers and shoals past 420 studs under the
  water, gulls past 700, the harbour's whirlpool, its water and its buoys past 700, the caustics,
  the shafts and the lanterns past 500, the tank's panes unless you are in the aquarium. All of it
  runs on the clock, so it is exactly where it should be when it comes back into range.
- The mesh fish move together (`BulkMoveTo`), and each kelp strand reuses one joint table.
- The checker now fails if any function the frame runs searches the game (`GetTagged` or
  `GetDescendants`), or if the mood is written whether it has changed or not.

Mutation-tested: 9 new, and the eighth pass's 23 again, all caught.

### Eighth pass (2026-09-25): the animals as meshes, a Ferris wheel, and jellyfish to bounce on

**The crash first.** `SunkenCityService:1536: attempt to perform arithmetic (add) on number and table`
was the seventh pass's street table: it was declared `local STREET = { vehicleLane, furnitureAt }`,
and a second top-level `local STREET` silently shadows the first one for everything after it, so
`BLOCK + STREET` (the city's grid pitch, where `STREET` is the 26-stud gap between blocks) added a
table. It is `ROADSIDE` now. `check_lua.py` fails on any name declared twice at a file's top level
(a `local` or a `type`), which is the check that would have caught it.

**The animals are meshes** (`blender/gen_sealife.py`), rigged and bent by their bones on the client:
a shark whose body waves to the tail, a pod of dolphins beating up and down, a grouper with a
spiny dorsal, an eel that wriggles along its own length, a ray whose wing tips ripple a beat behind
the roots, a turtle (shell and body) rowing and flapping its front flippers and lifting its head
out to breathe, a jellyfish whose bell pulls in and lets go, fish that beat their tails (a large
one for the street's shoals, a small one for the tank's and the flat's), and gulls whose wing tips
follow the roots. Each kind is drawn from the mesh when it is imported and from the parts it has
always had when it is not, so importing goes one mesh at a time and nothing breaks in between.

**`ReplicatedStorage.Shared.SeaRig`** (new) is how: it finds a mesh in `Assets/TileMeshes`, REFUSES one
imported at the wrong size (an old or rescaled import; a rig cannot be resized, because setting
Size moves the mesh and leaves the bones) or without its bones, places copies, and bends a bone
about the animal's own axes turned into that bone's rest frame, worked out from the bones' own
CFrames and never from anything the engine updates. The client's report line ends with its
summary: `N meshes drawn; part-built because not imported: ...; REFUSED: ... <why>`.

**The kelp is two meshes.** `Sea_Kelp` is the stipe, its small blades and the float, and the client
bends its twelve bones so the joints fall exactly where the part-built strand's did (`kelpJoint`,
which the checker already holds), stretching the chain to the strand's height. `Sea_KelpCanopy` is
the fronds streaming off the float, rippling on four bones; the street's strands carry one, laid
down the street's current (the server now writes `Along` and `Canopy` on each strand), and the
tank's do not, because in the tank a canopy would lie over the tunnel's roof.

**The dolphins' leap** tops out exactly `LEAP_HIGH` over the water from wherever the dolphin is (its
bob included), and it points along its arc but never steeper than `SWIM.pitch` (0.7): at the turn
of its wander a dolphin barely moves along, and judged by that alone it stood on its tail. They
swim a little deeper (4 to 6) for the mesh's taller fin.

**A drowned Ferris wheel** (`blender/gen_ferris.py`), 250 off the street on the side away from the
plaza and the thing on the horizon, in its own square of open water (`blocked` keeps the city off
it): two braced A-frames standing on the sea floor, the wheel 74 across on its axle 26 over the
water, sixteen pastel cabins, the lowest under the surface, going round once in five minutes on the
server's clock, every cabin hanging level and swinging a little. One cabin's light is still on (a
real PointLight, dipping now and then like the other lanterns). It is placed at the first of
`FERRIS.shares` along the street that is clear of the aquarium, the flat and the harbour and far
enough off the route for something that breaks the surface. Built from parts in the same place if
the meshes are not imported.

**Jellyfish, a new material and two new chunks.** `MaterialConfig.Jellyfish` bounces you on EVERY
landing (five studs up, a jump's height, with a 0.45 s cooldown so it bounces rather than buzzes),
through the same `microBounceHeight` path bubble wrap and jello use; it is pace, since nothing
about a bell drops you. `blender/gen_jellyfish.py` builds two bells on slime's 16 x 12 cell rig: a
compass jelly (a high round bell with sixteen raised canals, warts toward the margin and twelve
long tentacles) and a moon jelly (flatter, with the four horseshoe rings and a fringe). The bell
rises out of a thin membrane that fills the platform's corners, so there is visible floor under
every tile; the drops take the colliders down the dome. It is SmoothPlastic and not Glass, because
its level's sea is Glass. `R39_JellyfishHop` (risk) is two bells with a GAP_LENGTH gap between them
and one to a wide landing; `P29_JellyfishBloom` (pace) is one moon jelly. Both are in the Sunken
City's pool, and at the front of the sandbox.

**The checker measures the meshes.** `gen_sealife.py` and `gen_ferris.py` write
`blender/sealife_extents.json`, every mesh's real geometry box; `check_sunkencity.py` reads it, so
every clearance the part-built animals were held to (a fin under the surface, a wing over the
tunnel's roof, the widest reach across the street, the leap under the chunks, the gulls short of
the blocks) is held for the meshes too, with the bends the client gives them. New gates: SeaRig
expects the sizes the generators build; the canopy stays inside the street and 1 stud under the
surface as it ripples; nothing hanging under a rigged platform (the jellyfish's tentacles, 7.8 under
the bell) comes within 1.5 of the water (worst 3.2); the Ferris wheel's frame reaches exactly the
floor, the service and the generator agree on its radius, hang and cabins, it fits its square, and
on every seed there is somewhere clear to stand it. 23 mutations, one per new gate, all caught.

### Seventh pass (2026-09-24): the surface, the street, the whirlpool, and a report

From screenshots and a recorded play-through (no voice in it: the video's audio is the game).

**The flickering green roofs were two flat faces at one height.** The weed band every building wore
was a slab its own size whose top lay exactly on the water's surface: on a drowned building it was a
green roof lying on the water, and the two fought for the same pixels. Warehouse roofs could also
sit within a stud of the surface, and a wide house's ridge could come out of it. Now nothing is
within `SURFACE_CLEAR` (2.5) of the surface: a building stands clear or is plainly under, the weed
band is four strips on the walls ending under the surface, and the foam and weed mats sit clear of
it. The checker restates every building's top and what it carries.

**The street's own buildings stand.** Which lots may break the surface was judged from where the block
STARTED, minus half a block, so the whole front row counted as too near the route and drowned just
under the surface. It is judged from the lot's real frontage now, which is 62 from the route's line,
48 past any chunk's edge and far out of jumping reach. More of the blocks along the street stand.

**Buildings are detailed all the way down** near the street (`FACADE_FLOORS`, 14): sills at every
storey and a window band a side on the deep storeys, where they used to stop 26 under the surface.

**The street under the water:** vehicles at their own size (cars, vans and buses; they were two thirds
of a car and looked like toys), a tram on the rails, street furniture on the pavement edge (bus
shelters, phone boxes, benches and bins, dead trees in their planters, an amber traffic light still
blinking), the reef the road has become (coral heads, anemones, urchins), and bubbles rising a
hundred studs from the kelp beds to the surface.

**Life you can see from the route.** Everything alive used to be twenty studs down or deeper. Now
jellyfish float just under the surface, a pod of three dolphins leaps out of it one after another
every thirteen seconds with a splash each way, turtles come up to breathe, the fish shoals swim
three to ten under in four colours, and gulls circle over the street, flapping and gliding. The
dolphins' leap stays under every chunk and the gulls stay above them; the checker holds both.

**The flooded floor is swimmable.** Past the FLOODED. NO ACCESS. sign, the flat's stairwell now goes on
down in real Roblox terrain water, through the doorway at its foot (the wardrobe no longer blocks it)
and into the flooded flat a storey under: furniture lifted and turned over, a lamp still on, a teddy
bear, a few fish, and a note on the wall. The water is remembered and cleared with the level
(`SunkenCityService.clearWater`), as Sky Pools does with its pools.

**The whirlpool moves like water.** Its rings were Glass (each hid the others) and sixteen identical
segments turning look like nothing turning. Now the funnel carries the engine's water texture sliding
round and in, faster toward the middle (`SunkenWhirlFlow`); foam streaks on every ring show it
turning; the foam arms are thin fading skins, not planks you pass through; spray blows off the rim;
and it roars.

**The lobby countdown ticks on the second.** The video's audio showed the ticks in pairs, 0.8 then 1.2
seconds apart: each tick was a sound made on the server, heard when it replicated. The server now
says when the countdown ends on the shared clock, and each client shows the numeral and plays the
tick together, every second (`HubVoteService`).

**A report, and every piece guarded.** Nothing moving in the Sunken City (whirlpool, animals, kelp)
points at `SunkenCityClient` failing: it ran everything in one function, so one error stopped every
piece after it, every frame. Each piece now runs guarded and names itself once if it fails, and ten
seconds into the level the client prints what it is drawing:
`SunkenCityClient: drawing the thing (...), N swimmers, N shoals, N strands of kelp, N gulls, N
whirlpool rings; nothing has failed` (or `FAILED: ...`). The server's build line counts the same
things. Those two lines together say where the fault is.

### Sixth pass (2026-09-24): what the fifth one looked like, and the aquarium

**Invisible ice was Glass.** Roblox's Glass material draws only what is OPAQUE behind it and leaves out
every transparent part. Looking down on a sheet of ice, the only thing behind it is transparent water
(or Sky Pools' cloud and pools), so the ice showed the drowned city straight through and read as
open water; from the side, with scenery behind it, it looked fine. Ice is Roblox's Ice material now
(`MaterialAppearance`, the shell finish in `ChunkBuilder`, the shards in `DeformationRenderer`). The
white puffs and sparkles in the screenshot were the ice's own mist and drips.

**The same rule was hiding the aquarium.** The tunnel's panes, the viewing window and the tint
layers were all Glass, so from inside the tunnel the tinted water outside, the bubbles, the specks
and even the sea's surface overhead were not drawn, and one tint layer hid the next. They are a plain
translucent material now (`PANE`). And for the same reason, the street's jellyfish are solid: the sea's
surface is still Glass, and a clear jellyfish under it is invisible from the route. Only the tank's
(`Clear`) are clear.

**The entrance was blocked by the stair.** The spiral was laid from the top at a fixed 18 degrees a
step, and its last turn crossed the TUNNEL'S MOUTH four studs off the floor (the pointed opening in
the screenshot is the tunnel's roof). `stairPlan` now lays it from both ends: the head leaves the
landing by the door, the foot comes down 50 degrees short of the mouth, and it picks the step count
and angle that join them. The check walks the stair for every seed: nothing over the mouth under 7.5,
nothing over the way from the foot to the mouth under 6.5, nothing in the doorway, and even the
shallowest plan it may choose leaves 7 studs under the turn above.

**No animals because they were inside the walls.** The fish shoals were placed 54 to 90 studs off the
street, which is inside the drowned blocks. And on a short run, the rule that kept the new swimmers
off the road signs' legs threw nearly all of them out. Now the street's animals keep within
`SWIM_REACH` (24) of the centre line, under the route where you look down on them, and at 6 to 24
under the surface, where the light still reaches. The shoals circle loops laid along the street.
The swimmers are drawn bigger (rays 1.6, turtles and groupers 1.4), there are more of them (every 38
studs), and there is a shark.

**The glass (your design).** Every pane in the aquarium can be tapped now, the tunnel's sides as well
as the window: before, only the window at the far end was tappable, and the blocked tunnel kept you
from it. A tap thuds and the tank's fish bolt. Keep tapping one pane and it takes the strain (`TAP`
in SunkenCityService): at 3 a crack stars out, at 5 it spreads and weeps, at 7 it BREAKS. The pane
bursts inward in shards, water jets through, and the tower, tunnel and gallery fill to the top in 3.5
seconds, the view going green and soft underwater. Everyone still inside is washed out: back to
their checkpoint in Chill, to the start in Hardcore. After 14 seconds the water goes down and every
pane is whole; a crack left alone mends on its own. The Hardcore knock-back after three quick taps is
still there.

**The aquarium, better:**
- **Kelp** that is a plant: a stipe from the sea floor to just under the surface, blades on
  alternating sides, gas floats, dark low down and gold at the top, swaying with a wave running up
  it, all leaning with one current (`SunkenKelp`, grown and swayed on each client). Sixteen strands
  in the tank, kept 13 off the tunnel's line and out of the rocks, and a band past the window.
- **Rock stacks** beside the tunnel with coral on their tops at eye level: branching coral, a sea fan,
  a brain coral, a starfish.
- **A diver's helmet and a treasure chest** past the window on their own rocks, each breathing a
  stream of bubbles.
- **A brass rail** down both sides of the tunnel with plaques (THE KELP FOREST, OPEN WATER, THE DEEP).
- **Bubble vents** along the tunnel's foot outside the glass.
- **Animals in the tank**: rays, a turtle, a shark and a grouper over the tunnel's roof, where you
  look up at them, and clear jellyfish past the window.
- **What looks in**: every 110 seconds (first at 45), for anyone near the gallery, a head as wide as
  the gallery with one pale eye rises out of the dark past the window, holds level with it, and sinks
  away. It stays 62 studs out, behind the kelp.

**The street, more of it:** kelp beds along both kerbs halfway between lamp posts, their fronds moving
at the top of the water; flotsam bobbing under the route (planks, crates, barrels, a ball, and now and
then a child's rubber duck); weed mats on the surface by the kerbs. Lamp posts and cars now keep out
of the aquarium and the dry flat too (one run in a dozen put a post through the tunnel).

**Checking it.** New gates: the stair walk above; the swimmers' and shoals' reach against the road
signs' legs; nothing breaking the surface, up or down; the tank's animals over the roof and under the
surface; the kelp's worst-case sway against the legs, the blocks, the tunnel's glass, the chest and
what looks in; the glass's order and its washing out; no Glass in the aquarium's panes or in ice; and
Squash within Roblox's range. Twenty-five mutations, all caught.

### Fifth pass (2026-09-23): the frames in the sky, found; and the city comes alive

**The frames in the sky were a unit bug, not a design.** `facadeOf` took world heights and the tower
passed it a height over its own floor. With the sea floor a hundred studs down, every tower's sills,
pilasters and windows were drawn about ninety studs above its roof: the floor plates on thin posts
in the screenshots were facades with no building inside them. The old window bands had the same
bug. `facadeOf` now takes heights over the building's own floor, like everything else in a frame,
and the check follows every call's arguments back to `floorY`.

**The aquarium square.** The tank's tint panes rose thirteen studs out of the water and four more
lay flat over the tunnel, three of them above the surface, so from the route there was a rectangle
of different-looking water. The panes are upright only now and stop three studs under the surface,
edge-on from above.

**Nothing is hollow.** Every block of flats has a roof. One in four has partly fallen in, with the
roof lying in the room and the furniture showing, which is wear rather than an open box.

**Better pieces:**
- **Lanterns** are street lanterns: glass between four corner posts, a tray, a stepped cap and a
  finial, hung from a scrolled arm with a brace, on a post with a collar and a ring of weed where it
  leaves the water. Every eighth one is lit, and the lit ones gutter now and then (`SunkenLantern`).
  The pier's lantern is the same.
- **Skyscrapers** have a top: a setback storey, a crown of fins, a plant room, and a mast with a red
  aviation light that still blinks (`SunkenBlink`).
- **The clock tower** is built in stages: a quoined shaft with string courses and arched windows, a
  clock stage with a face on each side (bezel, twelve marks, hands, boss), an open belfry with
  louvres and the bell on its headstock, pinnacles, a green copper spire and a weathervane. Every
  137 seconds, on a schedule every player shares, the bell tolls once and swings. Nobody is up there
  (`SunkenBell`, swung about its `Hang` attribute).
- **Containers** are corrugated with ribs; the harbour's have a door end with locking bars and
  corner castings.

**The water moves.** Each surface plate carries the engine's water texture at two scales, and the
client slides them different ways (`SunkenSurface`), so they interfere like ripples. Foam skirts
every building where it comes out of the water.

**Animals that swim like characters** (`SunkenSwimmer`, made and moved on each client): a ray whose
wings beat from the body, a turtle paddling, jellyfish pulsing with their tendrils trailing, an eel
whose body follows its head, and an old grouper. They wander the street's open water, mostly along
it, never further across than 10 studs inside the kerb (`SWIM_KERB`), and never where their wander
would reach the aquarium, the dry flat, a gantry's legs or the harbour.

**The eerie half:**
- **The thing on the horizon.** At 95 seconds and then every 260, far out on one side of the city,
  a back 760 studs long breaks the surface like a line of dark hills over nine seconds, breathes out
  once, lies there twelve seconds and sinks. A double moan comes first, heard everywhere. It is laid
  in the city's own frame at `LEVIATHAN_OUT` (1300), and the lone towers on that side stop at
  `FAR_OPEN` (160) past the city's edge, so it always comes up in open sea. The check holds the gap.
- **Rain.** At 70 seconds and then every 230, for 75 seconds, the same for everyone: streaks round
  the camera, a hiss, rings on the water round you, the ripples running faster, and the light one
  small step lower (brightness -0.04, saturation -0.1).
- **Windows that should not be lit.** Seven windows above the water (`LIT_WINDOWS`) with a real
  light in them that goes on and off at odd intervals (`SunkenLitWindow`).
- **Strange sounds** every 22 to 57 seconds, each from a real spot a few hundred studs off: a long
  moan, metal giving, masonry letting go, something breathing out.

**Also:** LevelService's log line for a meander gives its length in studs instead of "59816
degrees round". The horrors' unused `Floor` attribute is gone; the new marker check found it.

**Checking it.** `check_sunkencity.py` gained gates for: every facade call in the building's own
frame; a roof on every block of flats; the tank held under the surface with one kind of pane; lit
windows counted and capped; swimmers held inside the lamp posts and clear of the aquarium, flat,
gantries and harbour; the thing on the horizon clear of the lone towers; `rain` declared before
`applyMood` reads it; and every attribute a marker is given is read by the client. Thirteen
mutations, including the original facade bug, all fail the check.

### Fourth pass (2026-09-23): buildings, not platforms

The city was read back as "ugly platforms in the sky". It was a fair description of what a box with
a stripe of window colour round it looks like, and the answer is four things every building now
gets, spent by distance so a three-hundred-building city stays affordable:

- **A facade** (`facadeOf`): a sill course at every storey, pilasters standing the full height
  between them, a cornice on top, and window panes set INTO the wall -- some dark, some boarded,
  some with glass still in them.
- **Wear** (`wearOn`): rust running from the fixings, render fallen off in patches, a corner gone
  with its rubble at the foot of the wall.
- **Growth** (`growthOn`): the weed line every drowned building wears at the waterline, algae up the
  faces under it, ivy up the side that gets light, and a tree out of a roof nobody is coming back to.
- **Holding out** (`holdingOut`): the half that makes it a city rather than a ruin -- sandbags along
  a frontage, scaffolding where somebody was shoring a wall up, a pump on a parapet with its hose
  over the side, a floodlight still burning, and a gauge painted on the wall with the marks of how
  far the water came.
- **Heights vary.** Blocks of flats used to top out two or three studs under the surface without
  exception, which is what made a street of them read as a field of platforms; they now run from a
  storey under the water to thirty above it, with a roof, a parapet, a tank and a stair head on the
  ones that stand. A building may only rise out of the water where its lot is allowed to break the
  surface, which the check holds.
- **Detail is spent by distance** (`DETAIL_NEAR` 300, `DETAIL_MID` 620): everything on the frontages
  you run past, storeys and ribs in the middle distance, a silhouette out in the haze. Those two
  numbers are the dial if the part count needs to come down.

### Third pass (2026-09-22): it is a street now, and there is something living in it

Played, and the level read as a grey plane with slabs floating on it. Every part of this pass comes
from that.

- **THE ROUTE IS A MEANDER THROUGH THE CITY**, not a ring round it (`layout = "meander"`,
  `meander = { amplitude = 0.45, wavelength = 1300, stepScale = 0, wave = ... }`). A ring meant the
  whole run was spent looking at the place from its edge; a line means blocks either side of you and
  the street running ahead into the haze.
- **The city is a grid laid in the route's direction.** Blocks of 118 studs with 26-stud streets,
  out to 940 either side and 460 past each end, and any lot the boulevard runs into is pushed back
  and shortened until its frontage is on the kerb -- which is how a curving street through a square
  grid actually looks. A block on the kerb turns to face the street; one further back keeps the
  grid's own direction. Each block holds two or three buildings rather than one. 125 to 215 lots on
  a run.
- **New things in it:** warehouses with sawtooth roofs and loading banks, a church whose spire comes
  out of the water, roof hoardings, and the boulevard itself -- road surface, kerbs, tram rails,
  lamp posts whose heads break the surface (every eighth one still lit) and the cars that never got
  out.
- **The harbour is at the END of the street** rather than a sector of a ring: quay walls with
  bollards, a gantry crane with its hook down, a container yard, a lighthouse whose beacon sweeps
  (tag `SunkenBeacon`), a fishing boat gone down by the quay, a half-sunk barge and an older wreck
  out on the silt.
- **The water reads as water.** The flat dark murk sheet is gone -- it was a lid, and from the route
  the city under you was one black plane. In its place: shafts of light leaning down from the
  surface with specks hanging in them (`SunkenShaft`), and the buildings' own drowned colours doing
  the depth.
- **Things living in it.** Shoals of fish along the street, made and swum on each client from
  markers the server places (`SunkenFishShoal`); the fish have bellies, fins, an eye and a tail that
  beats. And, far out where the haze takes over, four long dark things turning slowly on their own
  circles (`SunkenHorror`) -- never near the route, never lit, never explained.
- **The thing patrols the street** instead of swimming a ring. `SunkenPath` is rewritten round a
  polyline: it reads the route's line off the sea model as an attribute, walks up it and back down
  it for ever, wanders five studs either side, and turns back 200 studs short of the harbour. Its
  surfacing works the same way, keyed to distance along the street rather than an angle.
- **The aquarium.** The water outside the glass is four layers of tint at increasing distance, so
  the view out has depth; caustics slide across the tunnel; specks hang in the light; the tunnel is
  lit by a fitting in the roof of every bay and two uplights in the floor throwing light up through
  the water. **And tapping the glass does something**: it had only a ClickDetector, which shows no
  prompt and answered only in Hardcore after three taps, so a player could stand in front of the
  notice asking them not to tap the glass, tap it, and be told nothing. There is a prompt on it now,
  every tap thuds and startles the fish in both modes, and three taps in Hardcore still bring the
  other answer.
- **The ending.** The whirlpool has three spiral arms of foam wound into the middle, debris turning
  on it, and mist over it. At the bottom of the shaft there is now a SLUICE: a brick chamber with
  the water still coming down one wall, a grating underfoot, a bulkhead lamp that stutters
  (`SunkenSluiceLamp`), a ladder nobody is coming down and a door marked OUTFALL 3. The ride down is
  drawn by the rider's own client from `SunkenPath.drainFrame` over the new `SunkenRide` remote, for
  the reason Sky Pools' slide is: the server moving a character every frame stutters.

### Open for this level

- Tested in Studio by 2026-10-17, with every pass through the ninety-second: the look of the water and the depth tinting, the parts count, the
  thing's size and speed, the surfacing and whether it is fair, the stair, the tunnel, the flat,
  the face in the mirror, the whirlpool ride and the light.
- **Fourteenth pass, tested by 2026-10-17:** Output should show `SunkenCityClient: running, fourteenth pass`
  (and `CityShoreClient: running, fourteenth pass`). Ride the drain to the end: out through the
  OUTFALL 3 door, down the culvert on your back, set down in the pumping station with the camera on
  your time card, then LEVEL COMPLETE and six seconds before the lobby. Swim at a shoal and watch it
  scatter. Talk to the attendant and the fisherman (F) and check the new lines read well in the
  bubbles. Then the other two levels: dive at City Shore (head first, the scene, the street lamp),
  slide at Sky Pools (the scene, arms up), and talk to Sal, Pip, Maren, Dev, Mrs Okafor and Rudy.
  Whether Mrs Okafor sits on her cushion rather than in it or over it is worth a look.
- **Thirteenth pass, tested by 2026-10-17:** FIRST paste `src/Client/Bootstrap.client.lua` over the Bootstrap
  LocalScript in StarterPlayerScripts (the place's copy predates the Sky Pools and Sunken City clients).
  Output should then show `[client] started SunkenCityClient` and `SunkenCityClient: running,
  thirteenth pass`. Then: animals; the drain's four shots; the fisherman sitting; break the glass and
  watch the attendant; and if the report still says NO Ferris wheel, it now says why.
- **Twelfth pass, tested by 2026-10-17:** press Play and read Output first. The server now says, in Studio,
  exactly why SunkenCityClient is or is not running (search Output for `SunkenCity`); each client
  that runs prints `SunkenCityService: SunkenCityClient is running for ...`. Then: break the glass and
  swim in the flood; ride the drain (the rider should flail even without the client); in Sky Pools,
  look at the soda chunk through a pool or a fall.
- **Eleventh pass, tested by 2026-10-17:** play in Studio and read the panel at the top left first: it says
  whether SeaRig was found (and if not, why), how many animals there are and how many are meshes,
  and what has failed. Output starts with `SunkenCityClient: running, eleventh pass`; if that line
  is missing, the client is not running at all. Then: tap the window seven times and stand in the
  gallery (it should fill over 8 seconds, then fade out and in at the checkpoint); ride the drain
  (camera, bars, flailing, shouting). Import the five `Treasure_*` meshes.
- **Tenth pass, tested by 2026-10-17:** first, the two report lines (the server's `SunkenCityService: water
  at...` and, ten seconds in, the client's `SunkenCityClient: drawing the thing...`): together they
  say how many animals were placed, how many are drawn and from what, and which meshes were refused
  and why. Then: whether the flood now pours and rises; the landmarks' heights and colours from the
  route; the people (Output warns if one could not be built as a character). Import the new meshes
  (`Landmark_*`, `Boat_*`) and paste `SunkenNPCs` (now `Townsfolk`) as a ModuleScript next to SunkenCityService.
  SunkenCityService has 187 locals live at its top level: new tuning goes into its tables.
- **Ninth pass, tested by 2026-10-17:** the serpent, above all whether it reads from the route through the
  water and whether it turns round cleanly at each end of its patrol; import `Sea_Serpent` WITH its
  bones. The client's report says `drawing the thing (the serpent mesh)` when it is. If anything
  pops in or freezes at a distance, the ranges are the client's `SEEN` table.
- **Eighth pass, tested by 2026-10-17:** the client's report line now ends with SeaRig's summary, which says
  which meshes are drawn and why any are not; the server's build line says whether the Ferris wheel
  stood. Import the 19 FBX files first (`Sea_*`, `Ferris_*`, `Jellyfish_*`, each WITH its Bone
  children). To judge by eye: whether the animals swim convincingly (the bend amplitudes are in the
  client's `SWIM` table, the kelp's in `KELP`), the wheel's size and speed from the route
  (`FERRIS`), and how the jellyfish bounce feels (`MaterialConfig.Jellyfish`). Top-level locals: the
  client 179, the service 182, of Luau's 200.
- **Seventh pass, tested by 2026-10-17:** the two report lines above are the first thing to read. The part
  count grows again (deep facades, vehicles, furniture, reef); `FACADE_FLOORS` and `DETAIL_NEAR` are
  the dials. SunkenCityService has 178 locals live at its top level, near Luau's 200: new tuning
  numbers go into its tables (`STAIR`, `TAP`, `SCHEDULE`, `ROADSIDE`, `GULL`), not new locals.
- In the recording, 0.3 seconds into the second run the view went a flat dark grey for the rest of
  the video while the top bar still drew: the 3D view stopped rendering. Not reproduced here and
  not explained yet; the Output from that moment is what would say.
- **Sixth pass, tested by 2026-10-17:** whether the ice now reads from above over the water and over Sky
  Pools' clouds; the kelp's look and cost (up to about 1,700 client parts on a long run, only the
  near ones moving; `KELP_NEAR` in SunkenCityClient is the dial); the flood; the thing at the window.
  Slime, honey and jello soda are still Glass at 0.1 to 0.3 transparency: they read, but if any of
  them still looks thin from above, the same change as ice is the fix.
- **Fifth pass, tested by 2026-10-17:** the part count. The last log said 6,494; the lanterns, clock tower,
  skyscraper tops, roofs and containers add roughly a thousand to fifteen hundred, so expect about
  7,500 to 8,000. `DETAIL_NEAR` and `DETAIL_MID` are still the dials.
- Whether the thing on the horizon reads through the haze at 1300 studs. To bring it nearer, lower
  `FAR_OPEN` first and then `LEVIATHAN_OUT`; the check says how far it can go.
- The sounds are the engine's own, pitched: the bell is the lobby's ping at 0.26 over a thud, the
  rain is the falling-wind loop at 1.4. If either sounds wrong, those are the lines to change.
- `WASH_RADIUS`, `SURFACE_EVERY` and `WARN` in `SunkenPath.lua`, and `MIRROR_CHANCE` in
  `SunkenCityService.lua`, are the numbers to turn if the threat or the scare is too much or too
  little.

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

### Fixed on 2026-09-22, both found by playing it

- **The flume teleported you onto a platform instead of finishing the level.** The ride ends in the
  void under the far chamber, well below the kill plane, and `FloodedHallsService` had no
  `ownsFall` -- so the plane caught the rider part way down and did what it does: put them back on
  the last chunk they had touched. It has one now, and Bootstrap's kill plane exempts a rider the
  way it already exempted the dive, the slide and the drain. `check_halls.py` holds both ends of
  that.
- **The halls followed you home.** Their bloom, depth of field and grade hang on Lighting and their
  model is its own thing in the workspace; all of it was torn down only when the NEXT level was
  built. So finishing the level and going back to the lobby left the room under the halls' air with
  the halls still in the world. Two fixes: Bootstrap now tears the level's world down on the way
  home as well (`tearDownLevelWorld`, which also clears Sky Pools' terrain water), and
  `LightingService.apply` sweeps away any post-processing effect that is not one of its own three
  before it applies a region. A level may add to the look; no level's look outlives it.

### Fifteenth pass (2026-09-29): the gates at the bottom of it all

From your note that the end of the level was "just a void" and that it should have an animation of
its own, people and a part in the story **(you)**. The gate chamber and the ending are mine
**(suggested)**.

- **The flume is a scene** (`FloodedHallsClient`, new, on the client), twice as slow as it was
  (`SLIDE_SECONDS` 9.2): over your shoulder into the tube, round the helix from across the shaft, from
  below as you shoot out of the end, from above as you fall into the dark. Everyone sees you lying
  back with your arms crossed (`Poses.flume`).
- **The void is still there, and it is not the end.** The shaft keeps its unseen bottom, but at the
  end of the fall the picture dips to black and you come up in the **Gate Chamber**: the lowest room
  of the Harrow Bay Waterworks, built far off the end of the building and 150 studs under it, where
  nothing of it can be seen from the halls (`buildGates`). A concrete room with a sump, a ladder, pipes
  on brackets, beams under the roof, caged lamps (off), one green emergency lamp (on), a clock at one
  minute to midnight, the rota with your name on it, and in the far wall three outfalls: 1 and 2
  already open, and OUTFALL 3 shut behind a steel gate, its handwheel on a pedestal in front of it
  with a brass lock under the wheel.
- **The last scene** (34 seconds, `GATES.SECONDS`): you climb out of the sump; the room, one minute to
  midnight; you walk to the wheel; the key comes out of your pocket ("It was in your pocket the whole
  time"; the server puts a brass key in your hand, which everyone sees); you turn the wheel, the gate
  grinds up, the bay starts going out under it, daylight comes up at the end of the outfall, the
  lamps come on one by one and the sump drains; the clock reaches midnight; and the last line is
  "Harrow Bay. 14 August. 9:14 in the morning." Then LEVEL COMPLETE, and the room is yours for six
  seconds. The gate, the lamps, the clock and the water change on the rider's own screen only: every
  rider opens their own gates.
- **The run is finished by the scene**, not by the fall: the finish part is put under the chamber's
  floor where nothing can touch it, and the kill plane leaves anyone in the chamber alone
  (`ownsFall`, `insideGates`). The sump's water is terrain, and is taken out with the level.
- **People**: Mrs Venn, Tobi Okafor and Mr Barlow (see the story). The halls' clock now says four
  minutes to midnight rather than thirteen minutes to five.
- **Sounds**: the gate's groan, the rush of water and the siren are generated
  (`audio/gen_material_sfx.py` writes them to `audio/story/`); put them in `SoundService.StorySounds`
  and the scene uses them. Until then it uses Roblox's built-in bass and water sounds, and there is
  no siren.
- **The Hall_Column warning.** Output said the `Hall_Column` in Assets is 8.3 wide where the
  generator builds it 10.3. `meshes/Hall_Column.fbx` on disk IS the current one (measured: 10.3 by
  22), so nothing needs regenerating: re-import that one file into the Flooded Halls kit in Studio,
  replacing the old one.
- **"placed 23/22 chunks"** was the corner junction LevelService lays itself, counted with the
  level's own list. The line now says "22 of its 22 chunks, plus 1 corner piece".

### Open for this level

- The fifteenth pass is tested in Studio (by 2026-10-17): the flume as a scene, the dip, the gate chamber and the
  whole last scene, the three people, and the frame rate in the chamber.
- Every round through the ninety-second pass is tested in Studio (2026-10-17).
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
| `gen_sealife.py` | The Sunken City's animals and kelp, rigged: `Sea_*` (14 files). Writes `sealife_extents.json` for the checker. `-- render` draws each at rest and posed. |
| `gen_ferris.py` | `Ferris_Wheel`, `Ferris_Frame`, `Ferris_Gondola`. Run AFTER `gen_sealife.py`: it adds itself to `sealife_extents.json`. |
| `gen_landmarks.py` | The four landmarks as ten `Landmark_*` meshes. After `gen_sealife.py` (adds itself to `sealife_extents.json`). `-- render` draws each. |
| `gen_treasure.py` | The sunken chest as five `Treasure_*` meshes (wood, iron, gold, gems, pearls), one box, base at the middle. After `gen_sealife.py`. |
| `gen_boats.py` | `Boat_Row`, `Boat_LaunchHull`, `Boat_LaunchTop`, pivoted on the waterline. After `gen_sealife.py`. |
| `gen_serpent.py` | `Sea_Serpent`, the thing under the route. Also after `gen_sealife.py` (it adds itself to `sealife_extents.json`, with its `side_reach`). `-- render` draws it whole, posed and its head. |
| `gen_jellyfish.py` | The two jellyfish bells on slime's 16 x 12 rig. Prints their `SKINNED_PLATFORMS` entries. `-- render` draws them. |
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
| `check_luau_syntax.py` | `python check_luau_syntax.py` — parses every file in `src/` as Luau (statements, if-expressions, casts, compound assignment, `continue`, interpolated strings, generics and the whole type language) and refuses what the compiler refuses beyond the grammar: a statement after `return`/`break`/`continue`, those outside a loop, assigning to a call, a call whose `(` starts a new line. Names the file and line of the first thing Studio would reject. |
| `check_lua.py` | `python check_lua.py` — twelve checks across `src/`, every one of them a bug that already shipped once: use-before-declaration, block balance, annotated fields, undeclared constants, undeclared calls, cross-module calls, a `local` declared twice in one scope, a field read off a constants table that has no such field, stage counts, staged effects that never read `ctx.stepCount`, materials with no screen look, and locals live at once past Luau's 200 in any function (a NOTE from 178). No Blender, no Luau needed. |
| `check_hub.py` | `python check_hub.py` -- the lobby: every level has its own distinct headline material for its pad, every level in `All` gets a pad, pads are far enough apart to stand on, and a run request stays plain data that can survive a teleport. |
| `check_halls.py` | `python check_halls.py` -- the Flooded Halls. See that section for what it covers. |
| `plan_halls.py` | `python plan_halls.py` -- `halls_plan.png`: the three run lengths in plan plus a section. Needs matplotlib. |
| `plan_cityshore.py` | `python plan_cityshore.py` -- `cityshore_plan.png`: City Shore's backdrop from above and in section, placed by BackdropService's own rules and numbers (random draws differ). It is what caught the stair-stepped headlands. Needs matplotlib. |
| `check_skypools.py` | `python check_skypools.py` -- Sky Pools. See that section for what it covers. |
| `skypools_layout.py` | Lays the Sky Pools route in Python the way LevelService and SkyPoolsService do, including the shape of a terrace and the slide. Shared by the check and the plan. |
| `check_sunkencity.py` | `python check_sunkencity.py` -- the Sunken City. See that section for what it covers. |
| `ring_layout.py` | Lays any level with a `ring` in Python the way LevelService does. Shared by the two layouts below. |
| `sunkencity_layout.py` | The Sunken City's heights, aquarium, pier and the thing's path, from the Luau. Shared by its check and plan. |
| `plan_sunkencity.py` | `python plan_sunkencity.py [seed]` -- `sunkencity_plan.png`: one medium run from above, and sections through the aquarium and the drain. Needs matplotlib. |
| `plan_skypools.py` | `python plan_skypools.py [seed]` -- `skypools_plan.png`: one medium run of Sky Pools as built, from above and unrolled. Needs matplotlib. |
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

What is not built yet, as a list, is the Status section of `README.md` and in `ROADMAP.md`. Tested
and working as of 2026-09-17: the City Shore dive and the Flooded Halls slide. Built and not yet
seen in Studio: the keypads' capacitor and spring, growing cracks, oobleck without cracks, the
restored clay peel, the renderer's section fix, cells repairing themselves, the completion banner
without its blackout, City Shore's own lighting palette and second version, all of Sky Pools
(including its second pass), and all of the Sunken City. The Sunken City's open question, whether
the thing should be a real threat, is in its section.

- **Luau's 200 locals, and why `DeformationRenderer`'s sections are functions.** Luau refuses to
  compile a function with more than 200 locals LIVE AT ONCE, and a module's main chunk is a
  function. A local inside a top-level `do` block still counts toward the main chunk for as long
  as the block runs, on top of every top-level local above it, and so do `for` loop variables.
  The keypad section was a bare `do` block: adding the capacitor and the spring put 205 locals
  live inside it, the renderer failed to load ("Out of local registers when trying to allocate _",
  line 5878), and with it every material's visuals. `check_lua` had counted only top-level
  `local`s (188) and passed it. Now every section of the renderer that keeps locals is
  `do local function section() ... end section() end`, whose body has its own 200, and the main
  chunk peaks at 188; `check_lua` counts live locals per function the way the compiler does,
  names the exact line and local Studio would, and fails the file. The renderer's top-level count
  is still 188 of 200: a new section must be a function too, and new top-level locals should go
  into an existing table.

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
  darker for the physical reason that it is a hole with butter at the bottom. Soap and
  charcoal now use `Fissure` (growing cracks); salt still uses `addCrackNetwork`.
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
- **Chunk shape variants: done for granular materials.** `PlanShapes.lua` has fourteen
  outlines (heart, star, turtle, ring, cog, bone and more) and 29 chunk segments use one. Cost
  still depends entirely on the material:
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
  starts when you stand on it. The platform should progressively degrade, with failure spreading
  to neighbours, and nothing does that yet.
- **Chunk form variety, second pass.** Done once (see below), but two chunks came out of
  it as the same hourglass: `C2_PaceToStable` and `C4_BubbleWrapToStable` differ only in
  material and in one rising. `S1_Straight` and `S2_Junction` are still rectangles from
  above by design, so their only variety is the shelf. None of this is worth retuning
  before it has actually been played.
- **Texture maps: two templates left.** The maps exist (see PBR maps above), and in Studio every
  mesh template that should carry them has its SurfaceAppearance except `Buttons` and
  `ButterStick`, the only two `MaterialAppearance` still warns about at startup (Needoh has none
  by design).
- **Honey 16x12: done.** `Honey_Platform_16x12` and its comb and pool forms are rigs of their
  own, so no honey chunk falls back to per-tile meshes any more.
- **A `Shared/Remotes.lua` module.** Several modules do blocking `WaitForChild` at require
  time, so correctness depends on script execution order that Roblox does not guarantee.
  This already caused one deadlock. Worth doing before adding more services.

## Tools for a round

- `python blender/check_all.py` runs every checker, one line each, one exit code. Run it before
  pasting anything.
- `python blender/mutations/run_all.py` (or `run_all.py 15 16` for some) runs the mutation suites:
  each plants small deliberate bugs one at a time, runs the checker that should notice and puts the
  file back byte for byte. A MISSED line is a checker with a hole in it. They used to live in a
  session's scratch folder and were lost between sessions; they are in the repo now.
- `python tools/paste_list.py` lists what to paste since you last pasted, with where each file goes
  (line 2) and whether it is new; `--zip paste.zip` bundles them; `--mark` once you have pasted
  everything makes that the baseline for next time. With no baseline it falls back to git.

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
