"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 196: the arrows let into the floor. Neon on the arrows again, Neon on the fallback bars, the arrows see-through,
the arrows any colour, no brass in the palette.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
HUB = S / "Server/Services/HubService.lua"
LETGO = "check_letgo.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (LETGO,):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('Neon on the arrows', HUB, LETGO, 'chevron.Material = Enum.Material.Metal', 'chevron.Material = Enum.Material.Neon'),
    ('Neon on the fallback bars', HUB, LETGO, 'bar.Material = Enum.Material.Metal', 'bar.Material = Enum.Material.Neon'),
    ('the arrows see-through', HUB, LETGO, 'chevron.Transparency = 0\n', 'chevron.Transparency = 0.6\n'),
    ('the arrows any colour', HUB, LETGO, 'chevron.Color = PALETTE.brass', 'chevron.Color = PALETTE.warm'),
    ('no brass in the palette', HUB, LETGO, '\tbrass = Color3.fromRGB(184, 146, 82),\n', ''),
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
