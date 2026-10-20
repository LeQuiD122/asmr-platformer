"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 25: footprints and step sounds. A print or a pack sold with nothing to draw or play, worn without
being owned, Roblox's own footstep left playing over the pack, prints piling up or laid in a scene, the
Retro pack needing an upload, no try-on in the shop, and StepService never started.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
STEPS = S / "Client/Services/StepService.lua"
SHOP = S / "Client/Services/ShopService.lua"
ECON = S / "Server/Services/EconomyService.lua"
CAT = S / "Shared/ShopCatalog.lua"
CBOOT = S / "Client/Bootstrap.client.lua"
CHECK, PARSE = "check_shop.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (CHECK, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ("a paw with no shape", STEPS, CHECK, 'elseif id == "HoneyPaw" then', 'elseif id == "HoneyPaww" then'),
    ("a star never laid", STEPS, CHECK, "HeartStep = 6, StarStep = 6,", "HeartStep = 6,"),
    ("a pack with nothing to play", STEPS, CHECK, "\tGloopy = { events =", "\tGlooopy = { events ="),
    ("a footprint worn without owning it", ECON, CHECK, 'steps.kind == "steps" and owns(player, steps.id) then steps.id',
     'steps.kind == "steps" then steps.id'),
    ("a pack played without owning it", ECON, CHECK, 'sound.kind == "sound" and owns(player, sound.id) then sound.id',
     'sound.kind == "sound" then sound.id'),
    ("Roblox's footstep silenced by a pack", STEPS, CHECK, "muteRunning(root, false)", "muteRunning(root, wearsSound)"),
    ("prints piling up", STEPS, CHECK, "while #prints > MAX_PRINTS do", "while #prints > MAX_PRINTS * 1000 do"),
    ("prints laid in a scene", STEPS, CHECK, "if speed < 2 or speed > 60 or moved > 8 or root.Anchored then", "if speed < 2 then"),
    ("prints on the water", STEPS, CHECK, "rayParams.IgnoreWater = true", "rayParams.IgnoreWater = false"),
    ("built and still soon", CAT, CHECK, "price = 60, colour = rgb(237, 147, 177), accent = rgb(114, 36, 62) }",
     "price = 60, colour = rgb(237, 147, 177), accent = rgb(114, 36, 62), soon = true }"),
    ("an emote built and still soon", CAT, CHECK, 'name = "Wave", blurb = "Say hello",\n\t\tprice = 80, colour = rgb(159, 225, 203), accent = rgb(8, 80, 65) }',
     'name = "Wave", blurb = "Say hello",\n\t\tprice = 80, colour = rgb(159, 225, 203), accent = rgb(8, 80, 65), soon = true }'),
    ("any kind taken off", ECON, CHECK, 'if typeof(id) ~= "string" or not WEARABLE[id] then', 'if typeof(id) ~= "string" then'),
    ("no try-on in the shop", SHOP, CHECK, "(require(module) :: any).preview(item)", "(require(module) :: any).start()"),
    ("a pack pitched up into a squeak", STEPS, CHECK, "local PITCH_SPREAD = 0.06", "local PITCH_SPREAD = 0.9"),
    ("StepService never started", CBOOT, CHECK, '\t"StepService", "EmoteService"', '\t"EmoteService"'),
    ("a name never declared in the stride", STEPS, PARSE, "\t\tw.travelled += moved\n", "\t\tw.travelled += moves\n"),
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
