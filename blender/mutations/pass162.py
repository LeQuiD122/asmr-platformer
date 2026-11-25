"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 162: less motion when asked. Roblox's Reduce Motion never read; a scene's jolt, swimming picture or speed
lines as big; an impact flashing still; more than half kept; the slime's launch as wide; a level finished as loud; the
keypad's burst as hard.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
CBOOT = S / "Client/Bootstrap.client.lua"
CINEMA = S / "Client/Services/Cinema.lua"
RENDER = S / "Client/Services/DeformationRenderer.lua"
STYLE = S / "Shared/Style.lua"
STANDARDS = "check_standards.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (STANDARDS,):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('Reduce Motion never read', STYLE, STANDARDS, '\t\treturn game:GetService("GuiService").ReducedMotionEnabled\n\tend)\n\treturn ok and on == true', '\t\treturn false\n\tend)\n\treturn ok and on == true'),
    ('the jolt as big', CINEMA, STANDARDS, 'amount * (if Style.lessMotion() then CALM.shake else 1))', 'amount)'),
    ('an impact flashing still', CINEMA, STANDARDS, '\tif Style.lessMotion() then\n\t\tcurrent.kick = math.max(current.kick, 9 * s * CALM.kick)\n\t\tcurrent.shake = math.max(current.shake, 1.2 * s * CALM.shake)\n\t\treturn\n\tend\n', ''),
    ('more than half kept', CINEMA, STANDARDS, 'local CALM = { shake = 0.2,', 'local CALM = { shake = 0.8,'),
    ('the picture swimming as much', CINEMA, STANDARDS, ' * (if Style.lessMotion() then CALM.waver else 1)', ''),
    ('the speed lines as many', CINEMA, STANDARDS, ' * (if Style.lessMotion() then CALM.lines else 1)', ''),
    ("the slime's launch as wide", CBOOT, STANDARDS, '{ FieldOfView = base + (if calm then 3 else 9) }', '{ FieldOfView = base + 9 }'),
    ('a level finished as loud', CBOOT, STANDARDS, 'return game:GetService("GuiService").ReducedMotionEnabled\n\t\t\tor UserSettings():GetService("UserGameSettings").ReducedMotion', 'return UserSettings():GetService("UserGameSettings").ReducedMotion'),
    ("the keypad's burst as hard", RENDER, STANDARDS, '\t\t\t\t\tstrength *= 0.2\n', '\t\t\t\t\tstrength *= 1\n'),
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
