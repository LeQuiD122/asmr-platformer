"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 148: the story's days, and one name for each material. Wick's year back to 1946; the calendar on a
day that never comes; another date past the Hold's days; the squish room's signs with names of their own again, named
by their keys, or not looking for the collection at all.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
SQUISHS = S / "Server/Services/SquishRoomService.lua"
STORYSV = S / "Server/Services/StoryService.lua"
SUNKS = S / "Server/Services/SunkenCityService.lua"
POLISH = "check_polish.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (POLISH,):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ("Wick's year back to 1946", STORYSV, POLISH, 'A. Wick, 1969.', 'A. Wick, 1946.'),
    ('the calendar on a day that never comes', SUNKS, POLISH, 'THURSDAY 14\\n\\nThe water will not come up this far.', 'THURSDAY 16\\n\\nThe water will not come up this far.'),
    ("a date past the Hold's days", STORYSV, POLISH, '13 AUG. 12:00 test. 00:00 NOT A TEST.', '18 AUG. 12:00 test. 00:00 NOT A TEST.'),
    ("the signs' own names again", SQUISHS, POLISH, 'local function spaced(name: string): string\n', 'local NAMES = { LavaKeys = "Lava Keys" }\nlocal function spaced(name: string): string\n'),
    ('the signs named by their keys', SQUISHS, POLISH, '\t\t\t\treturn material.name\n', '\t\t\t\treturn material.key\n'),
    ('the collection never looked for', SQUISHS, POLISH, 'local found = Shared:FindFirstChild("ShopCatalog")', 'local found = Shared:FindFirstChild("Catalog")'),
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
