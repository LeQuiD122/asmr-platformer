"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 161: chat in the game's look. Roblox's white bubbles; the bubbles in Roblox's face; the window or the bar
left grey; Roblox's corners; the look set unguarded, or waited for without end.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
UIS = S / "Client/Services/UIService.lua"
STANDARDS = "check_standards.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (STANDARDS,):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ("Roblox's white bubbles", UIS, STANDARDS, 'BackgroundColor3 = Style.BUBBLE.fill,', 'BackgroundColor3 = Color3.new(1, 1, 1),'),
    ("the bubbles in Roblox's face", UIS, STANDARDS, '\t\tFontFace = Style.BUBBLE.font,\n', ''),
    ('the window left grey', UIS, STANDARDS, 'set("ChatWindowConfiguration", {', 'set("ChatWindowConfigurations", {'),
    ('the bar left grey', UIS, STANDARDS, '\t\tPlaceholderColor3 = Style.COLOUR.inkMuted,\n', ''),
    ("Roblox's corners", UIS, STANDARDS, 'corner.CornerRadius = Style.BUBBLE.radius', 'corner.CornerRadius = UDim.new(0, 4)'),
    ('the look set unguarded', UIS, STANDARDS, '\t\t\tpcall(function()\n\t\t\t\t(config :: any)[key] = value\n\t\t\tend)\n', '\t\t\t(config :: any)[key] = value\n'),
    ('waited for without end', UIS, STANDARDS, 'local config = chat:WaitForChild(name, 10)', 'local config = chat:WaitForChild(name)'),
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
