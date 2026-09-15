# ASMR Platformer (Roblox)

A 3D platformer where every platform is a different tactile material. Each one reacts
to the player in its own way: honey dents and slowly recovers, soap crumbles under your
feet, wax cracks and lets you sink into the butter underneath, bubble wrap pops.

**Status:** in development, not yet published. Six materials are playable. Sound is
wired up but has no audio assets yet.

## What's built

| Material | How it works |
|---|---|
| Honey | Rigged mesh with one bone per cell; footsteps push dents that recover over time |
| Slime | Rigged mesh with springy bone waves that snap back |
| Soap | Built from small cubes that break off one by one as physics debris, dropping you through |
| Butter-wax | Butter block under a wax coating split into Voronoi shards; shards push apart where you stand |
| Kinetic sand | Rig presses a bowl, a stamped sole sits inside it; cells collapse after 3 footsteps |
| Bubble wrap | One bone per pocket; pockets under your foot pop flat |

Other systems: procedural level generation from chunk templates, server/client split for
deformation state, chill and hardcore modes, timer, and a leaderboard.

## Tech

- **Luau** (Roblox) for all gameplay code in `src/`
- **Python + Blender** scripts in `blender/` that generate every rigged mesh, validate
  the geometry before export, and render previews
- **Python checkers** (`blender/check_lua.py`, `blender/check_chunk_forms.py`) that catch
  layout and code bugs without opening Roblox Studio

## Repo layout

```
src/        Luau source (Client, Server, Shared)
blender/    mesh generators, render scripts, checkers
meshes/     exported FBX/OBJ files
textures/   generated PBR texture maps
```

See `DEVELOPMENT.md` for Studio setup and run steps, and `HANDOFF.md` for detailed
design notes on each material.
