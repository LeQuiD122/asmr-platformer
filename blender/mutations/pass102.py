"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 102: one family, and every screen. A face that is not Nunito; another family named; a fitted panel larger
than the screen; the pause menu not fitted; the shop not measured by the Self-test, or words not fitting not looked
for.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
DEVP = S / "Client/Services/DevPanelClient.lua"
PAUSE = S / "Client/Services/PauseMenuService.lua"
STYLE = S / "Shared/Style.lua"
DEVICES, STYLECHECK = "check_devices.py", "check_style.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (DEVICES, STYLECHECK):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('a face that is not Nunito', STYLE, STYLECHECK, 'display = nunito(Enum.FontWeight.Black),', 'display = Font.fromEnum(Enum.Font.FredokaOne),'),
    ('another family', STYLE, STYLECHECK, 'local NUNITO = "rbxasset://fonts/families/Nunito.json"', 'local NUNITO = "rbxasset://fonts/families/GothamSSm.json"'),
    ('a panel larger than the screen', STYLE, DEVICES, 'local fits = math.min(room.X / design.X, room.Y / design.Y)', 'local fits = 2'),
    ('the pause menu not fitted', PAUSE, DEVICES, '\tStyle.fit(card, Vector2.new(380, 304))\n', '\n'),
    ('the shop not measured', DEVP, DEVICES, '\t\tonScreen("the shop")\n', '\n'),
    ('words not fitting not looked for', DEVP, DEVICES, 'and item.TextTransparency < 1 and not item.TextFits then', 'and item.TextTransparency < 1 and false then'),
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
