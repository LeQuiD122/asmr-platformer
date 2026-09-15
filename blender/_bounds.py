import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_honey_skinned as gen
gen.clear_scene()
obj, top_idx, static = gen.build_surface()
zs = [v.co.z for v in obj.data.vertices]
lo, hi = min(zs), max(zs)
centre = (lo + hi) / 2.0
# The plane you actually stand on: the interior surface away from the rim bead.
walk = gen.THICK + gen.DOME * 0.5
print(f"bbox z: {lo:.3f} .. {hi:.3f}   height {hi-lo:.3f}   centre {centre:.3f}")
print(f"walkable plane z ~ {walk:.3f}")
print(f"OFFSET surface->centre = {walk - centre:.3f}  (mesh centre sits this far BELOW the walk plane)")
