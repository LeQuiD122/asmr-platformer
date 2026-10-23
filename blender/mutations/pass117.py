"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 117: every Enum the Luau names is one Roblox has (Style named a font weight Roblox has no such thing as,
Black, and in Studio Style and everything that needs it failed to load). Black back; a material misspelt; an enum Roblox
does not have at all; an easing style that is not one; a key that is not one.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
DEVP = S / "Client/Services/DevPanelClient.lua"
HILLC = S / "Client/Services/HillHouseClient.lua"
HOUSE = S / "Server/Services/HillHouseService.lua"
STYLE = S / "Shared/Style.lua"
PARSE = "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (PARSE,):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('the big words in a weight Roblox does not have', STYLE, PARSE, 'display = nunito(Enum.FontWeight.Heavy)', 'display = nunito(Enum.FontWeight.Black)'),
    ('a shout in it too', STYLE, PARSE, 'shout = nunito(Enum.FontWeight.Heavy, true)', 'shout = nunito(Enum.FontWeight.Black, true)'),
    ('a material misspelt', HOUSE, PARSE, 'part(parent, "PendulumRod", Vector3.new(0.08, 3, 0.08), pivot * CFrame.new(0, -1.5, 0), brass, Enum.Material.Metal)', 'part(parent, "PendulumRod", Vector3.new(0.08, 3, 0.08), pivot * CFrame.new(0, -1.5, 0), brass, Enum.Material.Metallic)'),
    ('an enum Roblox does not have', HILLC, PARSE, 'local RunService = game:GetService("RunService")\n', 'local RunService = game:GetService("RunService")\nlocal _ = Enum.FontThickness.Heavy\n'),
    ('an easing style that is not one', HOUSE, PARSE, 'Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Value = turn }', 'Enum.EasingStyle.Quadratic, Enum.EasingDirection.Out), { Value = turn }'),
    ('a key that is not one', DEVP, PARSE, '{ action = "tokens", text = "+500 tokens" },', '{ action = "tokens", text = "+500 tokens", key = Enum.KeyCode.Ctrl },'),
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
