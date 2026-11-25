"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 184: a drowned battlefield. At the deck, crowded, shadowed, floating, never laid, a shield drowned, the smoke thick.
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
    ('at the deck', HUB, MADE, 'local WAR = { near = 250,', 'local WAR = { near = 120,'),
    ('crowded', HUB, MADE, 'far = 640, clear = 70,', 'far = 640, clear = 20,'),
    ('shadowed', HUB, MADE, 'piece.CastShadow = false\n\t\tpiece.Size = template.Size * scale', 'piece.CastShadow = true\n\t\tpiece.Size = template.Size * scale'),
    ('floating', HUB, MADE, 'piece.CFrame = turned * CFrame.new(0, piece.Size.Y * (0.5 - under), 0)', 'piece.CFrame = turned'),
    ('never laid', HUB, MADE, 'warField(folder, bladeAt)', '-- (no war)'),
    ('a shield drowned', HUB, MADE, '{ name = "War_Shield", count = 4, scale = { 16, 21 }, under = 0.35,', '{ name = "War_Shield", count = 4, scale = { 16, 21 }, under = 0.9,'),
    ('the smoke thick', HUB, MADE, 'smoke.Rate = 1.6', 'smoke.Rate = 12'),
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
