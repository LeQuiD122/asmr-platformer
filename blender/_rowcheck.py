import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_honey_skinned as gen
gen.clear_scene()
cols, rows, cx, cz = gen.compute_grid(gen.PLATFORM_X, gen.PLATFORM_Z)
obj, t, s = gen.build_surface()
arm, centres = gen.build_armature(cols, rows, cx, cz)
for r in (1, rows):
    name = f"Cell_1_{r}"
    by = centres[name][1]
    print(f"{name}: blender Y={by:+.2f}  -> roblox Z={-by:+.2f}")
