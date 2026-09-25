# ASMR Platformer: handoff

Roblox game from a locked GDD: a 3D platformer where every platform is a tactile,
ASMR-inspired material (honey, butter-wax, kinetic sand, slime, soap, bubble wrap), with
template-based procedural level generation, chill/hardcore modes and a leaderboard.

It has grown well past those six. `MaterialConfig` now carries 26 material entries across 65
chunks, there are four levels plus a Sandbox, and players choose a run in a lobby rather than
being dropped into a hardcoded level. See **Levels and the lobby** and **The Flooded Halls**
below for the parts this file did not cover before.

Last updated: 2026-09-18. What is planned next (the City Shore finale, story mode, the levels
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
    LevelService, LightingService, PlayerStateService, SkyPoolsService,
    SunkenCityService, TimerService                                   (ModuleScripts)
ReplicatedStorage
  Shared                  (Folder) -> 9 ModuleScripts: ChunkDefinitions, HallRoute,
                                      LevelDefinitions, MaterialAppearance, MaterialConfig,
                                      PlanShapes, SubRegionGrid, SunkenPath, Types
  Assets/TileMeshes       (Folder) -> imported MeshParts, exact names below
  Assets/Backdrop         (Folder) -> horizon props, OPTIONAL (see below)
StarterPlayerScripts
  Bootstrap               (LocalScript)
  Services                (Folder) -> AudioService, CloudService, DeathService,
                                      DeformationRenderer, HubLeverService, HubVoteService,
                                      InputService, PauseMenuService, ScreenEffects,
                                      SeaService, SkyPoolsClient, SunkenCityClient, UIService
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
| 1 | City Shore | spiral | 40 | the city, beach and waterpark horizon; ends on the high dive; the whole 65-chunk kit, all three rhythms, no repeat within six picks |
| 2 | Sky Pools | meander, going down | 44 | pool terraces on alternating sides of a route that sweeps down through a cloud sea; ends on a slide round a fountain tower into the final pool; the calm half of the kit |
| 3 | The Sunken City | ring, flat with a swell | 50 | a drowned city round the route, a thing under it, an aquarium off a checkpoint; ends down the harbour drain |
| 4 | Flooded Halls | path | 44 | inside a flooded tiled bathhouse, ending on a flume |
| Sandbox | all materials | spiral | 82 | development route, its own pad |

## City Shore's finale (Level 1)

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

- Nothing is seen in Studio yet: the look of the water and the depth tinting, the parts count, the
  thing's size and speed, the surfacing and whether it is fair, the stair, the tunnel, the flat,
  the face in the mirror, the whirlpool ride and the light.
- **Ninth pass, untested:** the serpent, above all whether it reads from the route through the
  water and whether it turns round cleanly at each end of its patrol; import `Sea_Serpent` WITH its
  bones. The client's report says `drawing the thing (the serpent mesh)` when it is. If anything
  pops in or freezes at a distance, the ranges are the client's `SEEN` table.
- **Eighth pass, untested:** the client's report line now ends with SeaRig's summary, which says
  which meshes are drawn and why any are not; the server's build line says whether the Ferris wheel
  stood. Import the 19 FBX files first (`Sea_*`, `Ferris_*`, `Jellyfish_*`, each WITH its Bone
  children). To judge by eye: whether the animals swim convincingly (the bend amplitudes are in the
  client's `SWIM` table, the kelp's in `KELP`), the wheel's size and speed from the route
  (`FERRIS`), and how the jellyfish bounce feels (`MaterialConfig.Jellyfish`). Top-level locals: the
  client 179, the service 182, of Luau's 200.
- **Seventh pass, untested:** the two report lines above are the first thing to read. The part
  count grows again (deep facades, vehicles, furniture, reef); `FACADE_FLOORS` and `DETAIL_NEAR` are
  the dials. SunkenCityService has 178 locals live at its top level, near Luau's 200: new tuning
  numbers go into its tables (`STAIR`, `TAP`, `SCHEDULE`, `ROADSIDE`, `GULL`), not new locals.
- In the recording, 0.3 seconds into the second run the view went a flat dark grey for the rest of
  the video while the top bar still drew: the 3D view stopped rendering. Not reproduced here and
  not explained yet; the Output from that moment is what would say.
- **Sixth pass, untested:** whether the ice now reads from above over the water and over Sky
  Pools' clouds; the kelp's look and cost (up to about 1,700 client parts on a long run, only the
  near ones moving; `KELP_NEAR` in SunkenCityClient is the dial); the flood; the thing at the window.
  Slime, honey and jello soda are still Glass at 0.1 to 0.3 transparency: they read, but if any of
  them still looks thin from above, the same change as ice is the fix.
- **Fifth pass, untested:** the part count. The last log said 6,494; the lanterns, clock tower,
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
| `gen_sealife.py` | The Sunken City's animals and kelp, rigged: `Sea_*` (14 files). Writes `sealife_extents.json` for the checker. `-- render` draws each at rest and posed. |
| `gen_ferris.py` | `Ferris_Wheel`, `Ferris_Frame`, `Ferris_Gondola`. Run AFTER `gen_sealife.py`: it adds itself to `sealife_extents.json`. |
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
