"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 35: something to press under a locked cursor, and leaving what you are not in. The death card's choices
or the test panel left under a cursor locked to the middle of the screen, the card's row renamed out from
under the check; anyone leaving a run they are not in; a runner into the squish room, in silence.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
VIEW = S / "Client/Services/ViewModeService.lua"
DEATH = S / "Client/Services/DeathService.lua"
BOOT = S / "Server/Bootstrap.server.lua"
ROOM = S / "Server/Services/SquishRoomService.lua"
ROOM_CLIENT = S / "Client/Services/SquishRoomClient.lua"
DEVICES, HUBCHECK, SQUISH, PARSE = "check_devices.py", "check_hub.py", "check_squishroom.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (DEVICES, HUBCHECK, SQUISH, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ("the death card under a locked cursor", VIEW, DEVICES,
     '\t\tor (death ~= nil and death:IsA("ScreenGui") and death.Enabled and choices ~= nil and choices:IsA("GuiObject")\n'
     "\t\t\tand choices.Visible)\n", ""),
    ("the test panel under a locked cursor", VIEW, DEVICES,
     '\t\tor (devPanel ~= nil and devPanel:IsA("GuiObject") and devPanel.Visible)\n', ""),
    ("the card's row renamed", DEATH, DEVICES, 'row.Name = "Choices"', 'row.Name = "Row"'),
    ("leaving a run you are not in", BOOT, HUBCHECK,
     "in the middle of the run.\n\tif levelInstance and HubService.isInRun(player) then",
     "in the middle of the run.\n\tif levelInstance then"),
    ("into the squish room from a run", ROOM, SQUISH, 'if player:GetAttribute("InLevel") then\n\t\ttell(player, "running")',
     'if false then\n\t\ttell(player, "running")'),
    ("refused in silence", ROOM_CLIENT, SQUISH, 'elseif kind == "running" then', 'elseif kind == "racing" then'),
    ("a name never declared", VIEW, PARSE, 'local choices = death and death:FindFirstChild("Choices", true)',
     'local choices = deth and death:FindFirstChild("Choices", true)'),
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
