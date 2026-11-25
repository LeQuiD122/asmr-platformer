"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 198: the siege, the ships, where they fell together, the sky's clouds. No siege towers, no masts, no clusters,
a cluster reaching into the next piece, every piece a cluster, a cluster laid on its first, pieces all called Mesh,
the banks back by the deck, a bare sky before a first run, a sky unlike the levels', clouds made over a level's, a crowd.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
HUB = S / "Server/Services/HubService.lua"
MADE = "check_made.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (MADE,):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('no siege towers', HUB, MADE, '{ name = "War_SiegeTower", count = 2,', '{ name = "War_Tower", count = 2,'),
    ('no masts', HUB, MADE, '{ name = "War_Mast", count = 2,', '{ name = "War_Pole", count = 2,'),
    ('no clusters', HUB, MADE, 'local WAR_CLUSTERS = { War_Shield = { extra = 3, radius = 34 }, War_Spear = { extra = 4, radius = 26 } }', 'local WAR_CLUSTERS = {}'),
    ('a cluster into the next piece', HUB, MADE, 'War_Shield = { extra = 3, radius = 34 }', 'War_Shield = { extra = 3, radius = 60 }'),
    ('every piece a cluster', HUB, MADE, 'if cluster and count == 1 then', 'if cluster then'),
    ('a cluster laid on its first', HUB, MADE, '* rng:NextNumber(cluster.radius * 0.45, cluster.radius)', '* rng:NextNumber(0, 0)'),
    ('pieces all called Mesh', HUB, MADE, 'piece.Name = if template.Parent then template.Parent.Name else template.Name', 'piece.Name = template.Name'),
    ('the banks back by the deck', HUB, MADE, '		sky.Parent = terrain\n	end\n', '		sky.Parent = terrain\n	end\n	decorPart("FarCloud_1", Vector3.new(96, 5, 54), HUB_ORIGIN, folder)\n'),
    ('a bare sky before a first run', HUB, MADE, '		local sky = Instance.new("Clouds")\n		sky.Cover = 0.62\n		sky.Density = 0.55\n		sky.Color = Color3.fromRGB(248, 246, 246)\n', '		local sky = Instance.new("Folder")\n'),
    ("a sky unlike the levels'", HUB, MADE, '		sky.Cover = 0.62\n', '		sky.Cover = 0.9\n'),
    ("clouds made over a level's", HUB, MADE, 'if terrain and not terrain:FindFirstChildOfClass("Clouds") then', 'if terrain then'),
    ('a crowd', HUB, MADE, '{ name = "War_Spear", count = 5,', '{ name = "War_Spear", count = 15,'),
]

paths = {m[1] for m in MUTATIONS}
originals = {path: path.read_bytes() for path in paths}
missed = []
try:
    for label, path, checker, old, new in MUTATIONS:
        text = originals[path].decode("utf-8").replace("\r\n", "\n")
        assert text.count(old) == 1, "%s: anchor found %d times" % (label, text.count(old))
        path.write_bytes(text.replace(old, new).encode("utf-8"))
        result = run(checker)
        path.write_bytes(originals[path])
        caught = result.returncode != 0
        why = [line.strip() for line in (result.stdout + result.stderr).splitlines()
               if line.startswith("  ") or line.startswith("FAIL")][:2]
        print("%-8s %s  %s" % ("caught" if caught else "MISSED", label, "; ".join(why)[:170]))
        if not caught:
            missed.append(label)
finally:
    for path, data in originals.items():
        path.write_bytes(data)
print("\n%d of %d caught" % (len(MUTATIONS) - len(missed), len(MUTATIONS)))
sys.exit(1 if missed else 0)
