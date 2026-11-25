"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 146: the levels' own sounds. The bell's ping back, the bell from nowhere or heard only close by; the
rain the engine's wind again, played fast again, or as loud as the wind; the key a switch again; the sump's splash the
engine's, or the water's own never asked for; a sound pitched up somewhere; the bell not in the paste check.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
BOOT = S / "Server/Bootstrap.server.lua"
HC = S / "Client/Services/FloodedHallsClient.lua"
SUNK = S / "Client/Services/SunkenCityClient.lua"
VOTE = S / "Client/Services/HubVoteService.lua"
HUB, POLISH = "check_hub.py", "check_polish.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (HUB, POLISH):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ("the bell's ping back", SUNK, POLISH, 'local own = folder and folder:FindFirstChild("HarbourBell")', 'local own = folder and folder:FindFirstChild("HarbourBells")'),
    ('the bell from nowhere', SUNK, POLISH, '\t\t\t\trung.Parent = part\n', '\t\t\t\trung.Parent = SoundService\n'),
    ('the bell heard only close by', SUNK, POLISH, 'rung.RollOffMaxDistance = 900', 'rung.RollOffMaxDistance = 90'),
    ('the rain the wind again', SUNK, POLISH, '\t\t\thiss = own:Clone()\n', '\t\t\thiss = Instance.new("Sound")\n'),
    ('the rain played fast again', SUNK, POLISH, '\t\thiss.Looped = true\n\t\thiss.Volume = 0\n', '\t\thiss.Looped = true\n\t\thiss.PlaybackSpeed = 1.4\n\t\thiss.Volume = 0\n'),
    ('the rain as loud as the wind', SUNK, POLISH, '(tonumber(rainSound:GetAttribute("Gain")) or 0.22) * rain', '0.22 * rain'),
    ('the key a switch again', HC, POLISH, 'sound("KeyTurn", CLICK, 0.9, 0.55, false)', 'sound(nil, CLICK, 0.9, 0.55, false)'),
    ("the sump's splash the engine's", HC, POLISH, 'keep(current, waterSound("splash", 0.8, 0.7))', 'keep(current, sound(nil, SPLASH, 0.8, 0.7, false))'),
    ("the water's own never asked for", HC, POLISH, 'water.dress(made, kind)', 'water.dress(made, "drip")'),
    ('a sound pitched up somewhere', VOTE, POLISH, 'TICK.PlaybackSpeed = 1.15', 'TICK.PlaybackSpeed = 1.6'),
    ('the bell not in the paste check', BOOT, HUB, '"HarbourRain", "HarbourBell",\n\t\t"KeyTurn" }', '"HarbourRain",\n\t\t"KeyTurn" }'),
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
