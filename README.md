# ASMR Platformer (Roblox)

A 3D platformer where every platform is a different tactile material. Each one reacts
to the player in its own way: honey dents and slowly recovers, soap crumbles under your
feet, wax cracks and lets you sink into the butter underneath, bubble wrap pops.

**Status:** in development, not yet published. 26 materials across 65 chunk templates
and 4 levels, chosen from a lobby. Sound is in for 7 materials, and the keypad has its own synthesized sound set waiting to be uploaded.
See [Status](#status) for what has been tested, what is waiting for a test, and what is not built yet.

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
| Arcade keypads | Three switch types: clicky (cyan) buttons give a speed surge, linear (violet) buttons store charge that the next clicky press releases as a bigger surge, and tactile (pink) buttons raise your jump, higher with each bounce from pink to pink |
| Needoh | Standing still squeezes the bed and charges a jump up to 2.2x normal height |
| Charcoal | Stepping lights a coal; fire spreads to neighbours and burnt coal turns to ash and gives way |
| Oobleck | Players slowly wade in unless they keep moving; a hard landing hardens the whole pool for everyone |

Cracks on soap and charcoal now grow outward from the footstep that caused them, and every
collapse drops the player immediately instead of waiting on the server.

## Status

Last updated: 2026-09-17. `ROADMAP.md` has the detail on everything not built yet.

### Tested in Studio and working

- **City Shore finale (level 1):** the diving board at the top of the spiral and the dive into the
  sea. Landing inside the circle on the water completes the level, with the splash and the fade to
  black.
- **Flooded Halls finale (level 4):** the water slide down into the shaft that ends the level.

### Built, waiting for a test in Studio

Added on 2026-09-17. The client renderer failed to load right after these went in (Luau's limit of
200 locals in one function, fixed the same day), so none of them has been seen in game yet.

- **Keypads:** violet buttons store a charge that the next cyan press releases as a bigger speed
  boost; pink buttons raise your jump, higher with each bounce from pink to pink; pink no longer
  slows you down.
- **Cracks that grow** out from your foot on soap and charcoal, instead of appearing all at once.
- **Oobleck without cracks.**
- **Clay's edge tearing off as one slab** again, back from the sagging version.
- **The renderer loading again.** Every material's visuals depend on it.

### Not built yet

Game features:

- **Story mode:** the levels played in order, starting with City Shore's dive leading into the
  Flooded Halls.
- **Level 2, Open Sky:** no background yet. Planned as Sky Pools, calm pools floating in the clouds.
- **Level 3, Far Water:** no background yet. Planned as The Sunken City, with a sea monster below
  the route.
- **The Backrooms:** a secret level you fall into after too many falls in one run.
- **Scares and secrets:** an eerie atmosphere, a monster that sends you back to spawn in Hardcore,
  a rare scary face in a mirror, and small places to explore off the route at checkpoints.
- **More worlds:** a kids' playground, office floors, a parking lot, a museum, an aquarium, a tiny
  world of bugs, and more.

Content and setup:

- **Sound for 15 materials:** ice, jello soda, lamb's ear, foam, light switch, lego, charcoal,
  chocolate, clay, cloud, salt, lava, oobleck, snow and Needoh are silent. `SOUND_BRIEF.md` says
  what each one needs.
- **The keypad's sounds** are made (`audio/buttons/`) but not uploaded, so it plays the keyboard's
  sound until they are.
- **Texture maps on the Buttons and ButterStick meshes:** each still needs a SurfaceAppearance
  added in Studio.
- **Soap giving way across the whole platform**, not only in the cells you stand on.
- **A shared module for remote events**, so services stop depending on the order scripts start in.

## Tech

- **Luau** (Roblox) for all gameplay code in `src/`
- **Python + Blender** scripts in `blender/` that generate every rigged mesh, validate
  the geometry before export, and render previews
- **Python checkers** in `blender/` (`check_lua.py`, `check_chunk_forms.py`, `check_plan_shapes.py`,
  `check_hub.py`, `check_halls.py`) that catch layout and code bugs without opening Roblox Studio.
  `check_lua.py` counts the locals live at once in every function the way Luau's compiler does, so
  a module that would fail to load with "Out of local registers" fails the check first
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
