"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 203: the teleprinter's tape across the screen, and the test panel sized, moved and sending you to a level. A box in
the middle again, a rounded box, letters stopping short, no fade at the end, the print head at the left; the panel not
movable, not sizable, sized to nothing, not scrolling, no way to a level; two levels at once, a level started over the
run you are in, the level buttons answered in the live game.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
TELE = S / "Client/Services/Teleprinter.lua"
DEV = S / "Client/Services/DevPanelClient.lua"
BOOT = S / "Server/Bootstrap.server.lua"
TOUCH = "check_touch.py"
SHOP = "check_shop.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (TOUCH, SHOP):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    # (The tape is a slip since the two-hundred-and-eighth pass: the faults now are a line, and letters cut off dead.)
    ('a line across the screen again', TELE, TOUCH, 'strip.Size = UDim2.new(0, STRIP.pad * 2, 0, STRIP.height)', 'strip.Size = UDim2.new(1, 0, 0, STRIP.height)'),
    ("letters cut off dead at a full slip's end", TELE, TOUCH, 'fading.Enabled = need > most', 'fading.Enabled = false'),
    ('letters stopping short', TELE, TOUCH, 'shown = 160,', 'shown = 30,'),
    ('no fade at the end', TELE, TOUCH, 'NumberSequenceKeypoint.new(STRIP.fade, 0),', 'NumberSequenceKeypoint.new(STRIP.fade, 1),'),
    ('a slip as wide as the screen', TELE, TOUCH, 'wide = 340, share = 0.6,', 'wide = 3400, share = 1,'),
    ('the panel not movable', DEV, SHOP, 'title.InputBegan:Connect(begin("move"))', 'title.InputBegan:Connect(begin("none"))'),
    ('the panel not sizable', DEV, SHOP, 'grip.InputBegan:Connect(begin("size"))', 'grip.InputBegan:Connect(begin("none"))'),
    ('the panel sized to nothing', DEV, SHOP, 'math.clamp(to.X, SIZE.minWidth, math.max(SIZE.minWidth, screen.X - at.X))', 'to.X'),
    ('the panel not scrolling', DEV, SHOP, 'local scroll = Instance.new("ScrollingFrame")', 'local scroll = Instance.new("Frame")'),
    ('no way to a level', DEV, SHOP, 'remote:FireServer("level", level.levelId)', 'remote:FireServer("lvl", level.levelId)'),
    ('two levels at once', BOOT, SHOP, 'if action ~= "level" or typeof(levelId) ~= "number" or starting then',
     'if action ~= "level" or typeof(levelId) ~= "number" then'),
    ('a level over the run you are in', BOOT, SHOP,
     '\t\t\t\tgoHome(player, function()\n\t\t\t\t\tstoryLeave(player)\n\t\t\t\t\ttask.defer(begin)\n\t\t\t\tend)\n',
     '\t\t\t\tbegin()\n'),
    ('the level buttons in the live game', BOOT, SHOP,
     'if game:GetService("RunService"):IsStudio() then\n\tlocal dev = remoteEventsFolder:FindFirstChild("DevPanel")\n\tif dev and dev:IsA("RemoteEvent") then\n\t\tlocal starting = false',
     'if true then\n\tlocal dev = remoteEventsFolder:FindFirstChild("DevPanel")\n\tif dev and dev:IsA("RemoteEvent") then\n\t\tlocal starting = false'),
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
