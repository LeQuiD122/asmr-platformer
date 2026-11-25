"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 157: standing about, keyed. The idles' table not written from their poses; an idle short of the ten;
one twice running; the curve overshooting its keys; a loop never played round.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
PLIFE = S / "Client/Services/PlayerLife.lua"
POSEGEN = ROOT / "blender/gen_poses.py"
POSES = S / "Shared/Poses.lua"
FEEL = "check_feel.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (FEEL,):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('the idles not written from their poses', POSEGEN, FEEL, 'POSES["idleLook"] = P(4.8, {', 'POSES["idleLook"] = P(4.9, {'),
    ('an idle short of the ten', PLIFE, FEEL, '\t{ pose = "idleAuraBrush", seconds = 3.9, often = 1 },\n', ''),
    ('an idle twice running', PLIFE, FEEL, '\t\tif fidget ~= last then\n\t\t\ttotal += fidget.often', '\t\tif true then\n\t\t\ttotal += fidget.often'),
    ('the curve overshooting', POSES, FEEL, 'if (here - before) * (after - here) <= 0 then', 'if false then'),
    ('a loop never played round', POSES, FEEL, 'return loop[1] + (t - loop[2]) % (loop[2] - loop[1])', 'return loop[2]'),
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
