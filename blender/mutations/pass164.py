"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 164: felt in your hands. A material not felt; a shape left buzzing, over full or running backward; played on a
server; an effect, its waveform or a controller's motor unguarded or never let go; two materials felt as two steps; a
phone as hard as a controller; every jump felt as a hard landing; a fall watched after the character has gone; anyone's
steps felt; a press, an impact, a jolt, a checkpoint or the fling not felt; Haptics waited for or never started; the
paste check not looking for it; a haptic type Roblox does not have.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
AUDIO = S / "Client/Services/AudioService.lua"
BOOT = S / "Server/Bootstrap.server.lua"
CBOOT = S / "Client/Bootstrap.client.lua"
CINEMA = S / "Client/Services/Cinema.lua"
HAPTICS = S / "Client/Services/Haptics.lua"
RUNFEEL = S / "Client/Services/RunFeel.lua"
HUB, TOUCH, PARSE = "check_hub.py", "check_touch.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (HUB, TOUCH, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('a material not felt', HAPTICS, TOUCH, '\tJellyfish = "bounce",\n', ''),
    ('a shape left buzzing', HAPTICS, TOUCH, '{ 320, 0 } }, heavy = true },', '{ 320, 0.2 } }, heavy = true },'),
    ('a shape over full', HAPTICS, TOUCH, 'keys = { { 0, 1 }, { 60, 0.55 }', 'keys = { { 0, 1.4 }, { 60, 0.55 }'),
    ('a shape running backward', HAPTICS, TOUCH, 'keys = { { 0, 0.9 }, { 28, 0 } }', 'keys = { { 28, 0.9 }, { 0, 0 } }'),
    ('played on a server', HAPTICS, TOUCH, '\tif not RunService:IsClient() then\n\t\treturn\n\tend\n\tlocal shape = SHAPES[name]', '\tlocal shape = SHAPES[name]'),
    ('an effect made unguarded', HAPTICS, TOUCH, 'local ok, made = pcall(function()\n\t\t\tlocal new = (Instance.new :: any)("HapticEffect")', 'local ok, made = true, (function()\n\t\t\tlocal new = (Instance.new :: any)("HapticEffect")'),
    ('a waveform written unguarded', HAPTICS, TOUCH, '\t\tlocal ok = pcall(function()\n\t\t\t(effect :: any):SetWaveformKeys(keysFor(shape, scale))\n\t\tend)', '\t\t;(effect :: any):SetWaveformKeys(keysFor(shape, scale))\n\t\tlocal ok = true'),
    ('a motor never let go', HAPTICS, TOUCH, 'HapticService:SetMotor(PAD, motor, 0)', 'HapticService:SetMotor(PAD, motor, 0.5)'),
    ('two materials felt as two steps', HAPTICS, TOUCH, '\tif soon("underfoot") then\n\t\treturn\n\tend\n', ''),
    ('a phone as hard as a controller', HAPTICS, TOUCH, 'local PHONE = { underfoot = 0.7 }', 'local PHONE = { underfoot = 1 }'),
    ('every jump felt as a hard landing', HAPTICS, TOUCH, 'local LANDING = { from = 70, full = 150 }', 'local LANDING = { from = 40, full = 150 }'),
    ('a fall watched after the character has gone', HAPTICS, TOUCH, '\thumanoid.Destroying:Once(stopFalling)\n', ''),
    ("anyone's steps felt", AUDIO, TOUCH, '\tif mine then\n\t\tlocal hands = felt()', '\tif true then\n\t\tlocal hands = felt()'),
    ('a press not felt', AUDIO, TOUCH, '\t\tpcall(hands.press, kind)\n', ''),
    ('an impact not felt', CINEMA, TOUCH, '\tinHands(function(haptics)\n\t\thaptics.impact(s)\n\tend)\n', ''),
    ('a jolt not felt', CINEMA, TOUCH, '\t\tinHands(function(haptics)\n\t\t\thaptics.jolt(amount)\n\t\tend)\n', ''),
    ('Haptics waited for', CINEMA, TOUCH, 'local found = script.Parent and script.Parent:FindFirstChild("Haptics")', 'local found = script.Parent and script.Parent:WaitForChild("Haptics")'),
    ('a checkpoint not felt', RUNFEEL, TOUCH, '\t\tpcall(haptics.checkpoint)\n', ''),
    ('the fling not felt', CBOOT, TOUCH, '(require(haptics) :: any).launch(launchVelocity)', '(require(haptics) :: any).checkpoint()'),
    ('Haptics never started', CBOOT, TOUCH, '"PlayerLife", "Haptics", "Teleprinter", "RunFeel"', '"PlayerLife", "Teleprinter", "RunFeel"'),
    ('the paste check not looking for Haptics', BOOT, HUB, '"RunFeel", "Haptics", "Teleprinter",', '"RunFeel", "Teleprinter",'),
    ('a haptic type Roblox does not have', HAPTICS, PARSE, 'new.Type = Enum.HapticEffectType.Custom', 'new.Type = Enum.HapticEffectType.Waveform'),
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
