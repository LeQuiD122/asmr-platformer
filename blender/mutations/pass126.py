"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 126, from your test: the water under the whirlpool, and oobleck's own sound. The picture never swimming, or
swimming on after; the lens still; the shafts never placed; oobleck's sheet not made.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
CINEMA = S / "Client/Services/Cinema.lua"
SHEETGEN = ROOT / "audio/gen_sheet_sfx.py"
SUNK = S / "Client/Services/SunkenCityClient.lua"
AUDIOCHECK, STORY = "check_audio.py", "check_story.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (AUDIOCHECK, STORY):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('the picture never swimming', SUNK, STORY, 'Cinema.waver(1)', 'local _ = 1'),
    ('swimming on after the water', SUNK, STORY, 'Cinema.waver(0)', 'local _ = 0'),
    ('the lens still', CINEMA, STORY, 'math.sin(now * 2.1) * 2.4 * w', '0 * w'),
    ('the shafts never placed', SUNK, STORY, 'deep.spec = current.spec', 'deep.spec = nil'),
    ("oobleck's sheet not made", SHEETGEN, AUDIOCHECK, '("ooblSquelch", oobleck)', '("ooblSquelchOld", oobleck)'),
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
