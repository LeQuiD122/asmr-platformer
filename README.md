# ASMR Platformer (Roblox)

A 3D platformer where every platform is a different tactile material. Each one reacts
to the player in its own way: honey dents and slowly recovers, soap crumbles under your
feet, wax cracks and lets you sink into the butter underneath, bubble wrap pops.

**Status:** in development, not yet published. 26 materials across 65 chunk templates
and 4 levels, chosen from a lobby. Sound is in for 7 materials, and the keypad has its own synthesized sound set waiting to be uploaded.

## Screenshots

| | |
|---|---|
| ![Lobby](screenshots/lobby.jpg) | ![Flooded Halls corridor](screenshots/flooded-halls.jpg) |
| **The lobby**, where players vote on level, mode and run length | **The Flooded Halls**, a bathhouse level built along the platform route |
| ![Flume chamber](screenshots/flume-chamber.jpg) | ![Soap crumbling](screenshots/soap.jpg) |
| **The final chamber**, where the run ends on a water slide | **Soap** breaking into cubes under the player |
| ![Kinetic sand](screenshots/kinetic-sand.jpg) | ![Butter-wax](screenshots/butter-wax.jpg) |
| **Kinetic sand** holding footprints and shedding clumps | **Butter-wax** coating cracking into shards |

### Materials in motion

| Soap | Butter-wax | Kinetic sand |
|---|---|---|
| ![Soap crumbling](screenshots/soap-crumble.gif) | ![Butter-wax cracking](screenshots/butter-wax-crack.gif) | ![Kinetic sand](screenshots/kinetic-sand.gif) |
| Cubes break off and fall as debris, opening a hole you drop through | The wax coating cracks into shards and the butter keeps the dent | Footprints stay, and the surface sheds clumps from the rim |

| Jello | Lego | Lava |
|---|---|---|
| ![Jello wobbling](screenshots/jello-wobble.gif) | ![Lego brick](screenshots/lego.gif) | ![Lava cracking](screenshots/lava.gif) |
| Wobbles and ripples outward from each step | Studs press down under your feet | Crust cracks open to glowing lava beneath |

| Honey | Memory foam |
|---|---|
| ![Honey footprints](screenshots/honey-prints.gif) | ![Memory foam](screenshots/memory-foam.gif) |
| Footprints sink in and slowly flow closed | Presses in and holds the dent |

## What's built

The six original materials, and how each one works:

| Material | How it works |
|---|---|
| Honey | Rigged mesh with one bone per cell; footsteps push dents that recover over time |
| Slime | Rigged mesh with springy bone waves that snap back |
| Soap | Built from small cubes that break off one by one as physics debris, dropping you through |
| Butter-wax | Butter block under a wax coating split into Voronoi shards; shards push apart where you stand |
| Kinetic sand | Rig presses a bowl, a stamped sole sits inside it; cells collapse after 3 footsteps |
| Bubble wrap | One bone per pocket; pockets under your foot pop flat |

Other systems:

- **Lobby:** one pad per level, plus mode (Chill or Hardcore) and run length pads. Players
  vote to start, and the server builds the run from their choices.
- **Levels:** three spiral levels and the Flooded Halls, a bathhouse level whose corridor walls
  are built along the same route the platforms follow, ending on a water slide.
- **Procedural generation** from chunk templates, server/client split for deformation state,
  a timer, personal bests and a leaderboard.
- **Level 1 finale:** the run ends with a high dive off a springboard into the sea, followed by a
  splash, a fade to black and a return to the lobby.

## Newer material mechanics

Later materials go beyond denting under your feet. Each one changes how you have to move:

| Material | Mechanic |
|---|---|
| Clay | Each step squeezes clay into the cells around it; an edge lip that takes too much tears off and falls with whoever is on it |
| Salt | Packing a cell pushes brine sideways, cracking, tilting and finally sinking the crust around you |
| Arcade keypads | Three switch types: clicky buttons give a speed surge, linear buttons store charge that the next clicky press releases, tactile buttons act as springs for chained bounces |
| Needoh | Standing still squeezes the bed and charges a jump up to 2.2x normal height |
| Charcoal | Stepping lights a coal; fire spreads to neighbours and burnt coal turns to ash and gives way |
| Oobleck | Players slowly wade in unless they keep moving; a hard landing hardens the whole pool for everyone |

Cracks on soap and charcoal now grow outward from the footstep that caused them, and every
collapse drops the player immediately instead of waiting on the server.

## Tech

- **Luau** (Roblox) for all gameplay code in `src/`
- **Python + Blender** scripts in `blender/` that generate every rigged mesh, validate
  the geometry before export, and render previews
- **Python checkers** (`check_lua.py`, `check_chunk_forms.py`, `check_hub.py`, `check_halls.py` in `blender/`) that catch
  layout and code bugs without opening Roblox Studio
- **Python + NumPy/SciPy** in `audio/gen_button_sfx.py`, which synthesizes the keypad's sound
  effects instead of using stock audio

## Repo layout

```
src/        Luau source (Client, Server, Shared)
blender/    mesh generators, render scripts, checkers
meshes/     exported FBX/OBJ files
textures/   generated PBR texture maps
audio/      sound effect generator and its WAV output
```

See `DEVELOPMENT.md` for Studio setup and run steps, and `HANDOFF.md` for detailed
design notes on each material.
