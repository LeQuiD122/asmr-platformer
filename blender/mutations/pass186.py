"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 186: the streets. The lamp on the sign, the street prop in the camera's way, a lamp in something, anchors everywhere.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
CITY = S / "Server/Services/SunkenCityService.lua"
MADE = "check_made.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (MADE,):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('the lamp on the sign', CITY, MADE, 'local lampFoot = spot - route.forward * (STREET / 2 + 1.2)', 'local lampFoot = spot + route.forward * (STREET / 2 + 1.2)'),
    ("in the camera's way", CITY, MADE, '\tpiece.CanQuery = false\n\tpiece.Parent = parent\n\treturn piece', '\tpiece.Parent = parent\n\treturn piece'),
    ('a lamp in something', CITY, MADE, 'if not blocked(lampFoot, 3) and streetKit.place(', 'if streetKit.place('),
    ('anchors everywhere', CITY, MADE, 'if row % 3 == 0 and step == 40 then', 'if step == 40 then'),
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
