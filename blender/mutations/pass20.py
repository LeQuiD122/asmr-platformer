"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 20: speech bubbles with one size of text, the Sky Pools' slide clear of its rider, the Sky Pools'
light without the milky haze, its people's habits and Rudy's record. (The prompts back to Roblox's own,
the return to third person and the drain's cries are in pass19.)
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
TOWNS = S / "Server/Services/Townsfolk.lua"
SKY = S / "Server/Services/SkyPoolsService.lua"
SKYC = S / "Client/Services/SkyPoolsClient.lua"
LIGHT = S / "Server/Services/LightingService.lua"
STORY, SKYCHECK, CITYCHECK, PARSE = "check_story.py", "check_skypools.py", "check_sunkencity.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (STORY, SKYCHECK, CITYCHECK, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    # Speech bubbles.
    ("words scaled to the bubble again", TOWNS, CITYCHECK, "\tlabel.TextSize = if shout then SHOUT_TEXT else SPEECH_TEXT\n",
     "\tlabel.TextScaled = true\n"),
    ("a bubble that does not fit its words", TOWNS, CITYCHECK, "\tlabel.AutomaticSize = Enum.AutomaticSize.XY\n",
     "\tlabel.AutomaticSize = Enum.AutomaticSize.None\n"),
    # The slide.
    ("rods through the rider", SKY, SKYCHECK, "local inner = frame * Vector3.new(side * (wide / 2 + 0.4), 2.2, 0)",
     "local inner = frame * Vector3.new(0, 2.2, 0)"),
    ("hoops on the rider's head", SKY, SKYCHECK, "math.sin(a2) * (wide / 2 + 0.6) + 2.4, 0)", "math.sin(a2) * (wide / 2 + 0.6) + 1.4, 0)"),
    # The light.
    ("the milky haze back", LIGHT, SKYCHECK, "\t\thaze = 0,\n\t\toffset = 0.3,\n\t\tclock = 15,",
     "\t\thaze = 0.35,\n\t\toffset = 0.3,\n\t\tclock = 15,"),
    ("every shadow filled with white", LIGHT, SKYCHECK, "\t\tdiffuse = 0.4,\n\t\tdensity = 0.14,", "\t\tdiffuse = 0.7,\n\t\tdensity = 0.14,"),
    # The people.
    ("Dev a statue", TOWNS, STORY, "function HABITS.Dev(", "function HABITS.Devv("),
    ("a habit fighting a talker's hands", TOWNS, STORY, "if habit and now > npc.talking then", "if habit then"),
    ("the record still", SKYC, SKYCHECK, 'CollectionService:GetTagged("SkyTurntable")', 'CollectionService:GetTagged("SkyRecord")'),
    # The code still reads.
    ("a name never declared in the habits", TOWNS, PARSE, "\tlocal burst = math.clamp(math.sin(t * 0.55) * 1.6, 0, 1)\n",
     "\tlocal burst = math.clamp(math.sin(t * 0.55) * 1.6, 0, one)\n"),
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
