"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 112: Hill House's hall. The door still ending it, or its prompt staying up; the key's prompt saying
nothing, playing no scene, or left behind; his clock at another time; the scene not told where the clock is, or not
reading the way out; the pendulum hung elsewhere or renamed; the key not hidden; a bright light in the hall; no
HillScene remote; the client never started or not listed; the hall's sounds not listed; never saying it has been
watched; never listening; a sound the scene asks for not made; the key's shot moved without the check; the clock's
shot too short to read; the pendulum out of the clock's shot; a name never declared.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
BOOT = S / "Server/Bootstrap.server.lua"
CBOOT = S / "Client/Bootstrap.client.lua"
HILLC = S / "Client/Services/HillHouseClient.lua"
HOUSE = S / "Server/Services/HillHouseService.lua"
AUDIOCHECK, HILL, SHOTS, PARSE = "check_audio.py", "check_hillhouse.py", "check_shots.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (AUDIOCHECK, HILL, SHOTS, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('the door still ending it', HOUSE, HILL, '\t\t\topen.Enabled = false\n', '\t\t\topen.Enabled = false\n\t\t\tonArrive(_player)\n'),
    ("the door's prompt staying up", HOUSE, HILL, '\t\t\topen.Enabled = false\n', ''),
    ("the key's prompt saying nothing", HOUSE, HILL, 'take.ActionText = "Take the key"', 'take.ActionText = ""'),
    ('taking the key plays no scene', HOUSE, HILL, 'scene:FireClient(player, "key", model)', 'scene:FireClient(player, "keys", model)'),
    ("the key's prompt left behind", HOUSE, HILL, '\t\ttakePrompt:Destroy()\n', ''),
    ('his clock at another time', HOUSE, HILL, 'local CLOCK_STOPPED_HOUR, CLOCK_STOPPED_MINUTE = 11, 56', 'local CLOCK_STOPPED_HOUR, CLOCK_STOPPED_MINUTE = 3, 15'),
    ('the scene not told where the clock is', HOUSE, HILL, 'model:SetAttribute("ClockFace", hall.clockFace)', 'model:SetAttribute("ClockDial", hall.clockFace)'),
    ('the scene not reading the way out', HILLC, HILL, 'local back = model:GetAttribute("HallBack")', 'local back = model:GetAttribute("HallRear")'),
    ('the pendulum hung elsewhere', HOUSE, HILL, '"PendulumBob", Vector3.new(0.12, 0.8, 0.8), pivot * CFrame.new(0, -3.1, 0)', '"PendulumBob", Vector3.new(0.12, 0.8, 0.8), pivot * CFrame.new(0, -2.6, 0)'),
    ('the pendulum renamed', HOUSE, HILL, 'part(parent, "PendulumRod"', 'part(parent, "PendulumStick"'),
    ('the key not hidden', HOUSE, HILL, 'key.Name = "HallKey"', 'key.Name = "Key"'),
    ('a bright light in the hall', HOUSE, HILL, 'sun.Brightness = 1.2', 'sun.Brightness = 4'),
    ('no HillScene remote', BOOT, HILL, 'ensureRemoteEvent(remoteEventsFolder, "HillScene")', 'ensureRemoteEvent(remoteEventsFolder, "HillScenes")'),
    ('the client never started', CBOOT, HILL, '"HillHouseClient", "AmbienceService"', '"AmbienceService"'),
    ('the client not listed', BOOT, HILL, '"HillHouseClient", "HubLeverService"', '"HubLeverService"'),
    ("the hall's sounds not listed", BOOT, HILL, '"ArchPass", "KeyLift", "ClockStart", "ClockPunch",', '"ArchPass", "ClockPunch",'),
    ('never saying it has been watched', HILLC, HILL, '\t\t\tCinema.done()\n', ''),
    ('never listening', HILLC, HILL, 'kind == "key"', 'kind == "keys"'),
    ('a sound the scene asks for not made', HILLC, AUDIOCHECK, 'Cinema.sound("ClockStart"', 'Cinema.sound("ClockStarts"'),
    ("the key's shot moved without the check", HILLC, SHOTS, 'local eye = head + side * 3 + facing * 1.5 + Vector3.new(0, -0.5, 0)', 'local eye = head + side * 2.6 + facing * 1.5 + Vector3.new(0, -0.5, 0)'),
    ("the clock's shot too short to read", HILLC, SHOTS, 'local KEY_SHOT, CLOCK_SHOT, WAY_SHOT = 2.6, 3.4, 3.8', 'local KEY_SHOT, CLOCK_SHOT, WAY_SHOT = 2.6, 0.4, 3.8'),
    ("the pendulum out of the clock's shot", HOUSE, SHOTS, 'local pivot = clock * CFrame.new(0, 4.9, -0.3)', 'local pivot = clock * CFrame.new(0, 2.4, -0.3)'),
    ('a name never declared', HILLC, PARSE, 'local amount = SWING * math.min', 'local amount = SWINGG * math.min'),
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
