"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 98: the levels' water, its own. The same take twice running, or a take playing on into the next; a slot
the wrong length, the takes miscounted, a bed that is not there; the generator's slots not the module's; the pools' dips,
the falls and the slide's splash, the harbour's water or either of its drips, the halls' drips, or the dive as others
hear it, still the engine's one splash; the paste check calling the water's sounds required; a name never declared.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
BOOT = S / "Server/Bootstrap.server.lua"
DIVE = S / "Server/Services/DiveFinaleService.lua"
HS = S / "Server/Services/FloodedHallsService.lua"
SKY = S / "Client/Services/SkyPoolsClient.lua"
SKYS = S / "Server/Services/SkyPoolsService.lua"
SUNKS = S / "Server/Services/SunkenCityService.lua"
WATERGEN = ROOT / "audio/gen_water_sfx.py"
WSND = S / "Shared/WaterSounds.lua"
AUDIOCHECK, HUB, PARSE = "check_audio.py", "check_hub.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (AUDIOCHECK, HUB, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('the same take twice running', WSND, AUDIOCHECK, 'if pick == last[kind] then', 'if false then'),
    ('a take playing on', WSND, AUDIOCHECK, '(sound :: any).PlaybackRegion = NumberRange.new(from, from + slot - 0.05)', '(sound :: any).PlaybackRegion = NumberRange.new(from, from + 60)'),
    ('a slot the wrong length', WSND, AUDIOCHECK, 'splash = { sheet = "Splash_x6", slot = 2,', 'splash = { sheet = "Splash_x6", slot = 3,'),
    ('the takes miscounted', WSND, AUDIOCHECK, 'dip = { sheet = "Dip_x8", slot = 1, takes = 8 }', 'dip = { sheet = "Dip_x8", slot = 1, takes = 9 }'),
    ('a bed not there', WSND, AUDIOCHECK, 'lap = { bed = "Lap" }', 'lap = { bed = "Laps" }'),
    ("the generator's slots differ", WATERGEN, AUDIOCHECK, 'SLOTS = {"Splash": 2.0,', 'SLOTS = {"Splash": 2.5,'),
    ("the pools' dips the old splash", SKY, AUDIOCHECK, 'play("dip", ', 'play("splash", '),
    ('the falls the old splash', SKYS, AUDIOCHECK, 'if not (kind and WaterSounds.dress(s, kind)) then', 'if true then'),
    ("the slide's splash the old one", SKYS, AUDIOCHECK, 'if not WaterSounds.dress(s, "splash") then', 'if true then'),
    ("the harbour's water the old splash", SUNKS, AUDIOCHECK, 'if not (kind and WaterSounds.dress(s, kind)) then', 'if true then'),
    ('a stair drip the old splash', SUNKS, AUDIOCHECK, '\t\t\t\tif not WaterSounds.dress(drip, "drip") then', '\t\t\t\tif true then'),
    ("the halls' drips the old splash", HS, AUDIOCHECK, 'if not WaterSounds.dress(drip, "drip") then', 'if true then'),
    ('the dive the old splash', DIVE, AUDIOCHECK, 'if WaterSounds.dress(sound, "splash") then', 'if false then'),
    ("the water's sounds required", BOOT, HUB, 'sound("WaterSounds", name, true)', 'sound("WaterSounds", name)'),
    ('a name never declared', WSND, PARSE, 'local own = if folder and name then folder:FindFirstChild(name) else nil', 'local own = if folder and names then folder:FindFirstChild(name) else nil'),
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
