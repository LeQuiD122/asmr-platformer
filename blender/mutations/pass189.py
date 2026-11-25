"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 189: the lobby's benches and urns. The bench short, facing its back, the seat showing, the urn huge.
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
    ('the bench short', HUB, MADE, 'bench.Size = look.Size * (9 / look.Size.X)', 'bench.Size = look.Size'),
    ('facing its back', HUB, MADE, 'bench.CFrame = turn * CFrame.Angles(0, math.pi, 0) * CFrame.new(0, bench.Size.Y / 2, 0)', 'bench.CFrame = turn * CFrame.new(0, bench.Size.Y / 2, 0)'),
    ('the seat showing', HUB, MADE, '\t\tseat.Transparency = 1\n', ''),
    ('the urn huge', HUB, MADE, 'urn.Size = urnLook.Size * (6 / urnLook.Size.Y)', 'urn.Size = urnLook.Size * 3'),
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
