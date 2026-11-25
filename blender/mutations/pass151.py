"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 151: the floor going behind you. Sculpting sand with no crumble; a cookie that takes three and a half
seconds; snow's holes thirty seconds filling; a coal three seconds to ash; a foot that never starts the crumble; a crumble
that only takes a cell still stood on; no shake before; a hole filled back in keeping its crumble; the shake taken for a
footstep; the shake that never judders.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
DEFORMS = S / "Server/Services/DeformationService.lua"
MATS = S / "Shared/MaterialConfig.lua"
RENDER = S / "Client/Services/DeformationRenderer.lua"
FEEL = "check_feel.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (FEEL,):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('sculpting sand never crumbles', MATS, FEEL, '\t\tcrumbleAfter = 1.4,\n\t\tregrowAfter = 6,\n\t\tstepsToCollapse = 2,', '\t\tregrowAfter = 6,\n\t\tstepsToCollapse = 2,'),
    ('a cookie slow to go', MATS, FEEL, 'dissolveTime = 0.9,\n\t\tcrumbleAfter = 0.9,', 'dissolveTime = 0.9,\n\t\tcrumbleAfter = 3.5,'),
    ("snow's holes slow to fill", MATS, FEEL, '\t\tcrumbleAfter = 1.5,\n\t\tregrowAfter = 6,', '\t\tcrumbleAfter = 1.5,\n\t\tregrowAfter = 30,'),
    ('a coal slow to ash', MATS, FEEL, 'igniteAfter = 0.6,\n\t\tburnFor = 1.3,', 'igniteAfter = 0.9,\n\t\tburnFor = 1.9,'),
    ('a foot never starts the crumble', DEFORMS, FEEL, '\t\tcell.crumbleAt = os.clock() + crumble\n', ''),
    ('the crumble only takes a cell stood on', DEFORMS, FEEL, '\t\t\t\tif now >= crumbleAt then\n', '\t\t\t\tif now >= crumbleAt and cell.count > 0 then\n'),
    ('no shake before it goes', DEFORMS, FEEL, '\t\t\t\t\treplicate(platform, cell, nil, "warn")\n', ''),
    ('a filled hole keeps its crumble', DEFORMS, FEEL, '\tcell.crumbleAt = nil\n\tcell.warned = nil\n', '\tcell.warned = nil\n'),
    ('the shake taken for a footstep', RENDER, FEEL, '\tif payload.cause == "warn" then\n\t\tDeformationRenderer.tremble(tile, material)\n\t\treturn\n\tend\n', ''),
    ('the shake never judders the cell', RENDER, FEEL, '\t\t\t\t\tboneOffset(bone, info, base + by)\n', ''),
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
