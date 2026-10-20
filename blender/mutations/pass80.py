"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 80: the trails and auras, and the new things to buy. A trail or an aura with no look of its own, the embers a
plain stream again or without their glow, a light too bright, Neon, shadows from every player's light, a trail's
drops following you; a new thing gone; a new print never drawn or never laid; a new pack with nothing to play.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
CAT = S / "Shared/ShopCatalog.lua"
STEPS = S / "Client/Services/StepService.lua"
SHOP, PARSE, LUA = "check_shop.py", "check_luau_syntax.py", "check_lua.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (SHOP, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ("an aura with no look", CAT, SHOP, "\tFireflies = {\n\t\tmotes = {", "\tFirefly = {\n\t\tmotes = {"),
    ("a trail with no look", CAT, SHOP, "\tHoneyDrip = {\n", "\tHoneyDripped = {\n"),
    ("the embers a plain stream", CAT, SHOP,
     "\t\t\t-- FLAME licking up round your feet.\n\t\t\t{ texture = TEX.fire,", "\t\t\t-- FLAME licking up round your feet.\n\t\t\t{ texture = \"\","),
    ("the embers without their glow", CAT, SHOP, "\t\tglow = { colour = rgb(255, 136, 56), brightness = 1.4, range = 11 },\n", ""),
    ("a light too bright", CAT, SHOP, "brightness = 1.1, range = 9 }", "brightness = 6, range = 9 }"),
    ("Neon", CAT, SHOP, "\tlight.Shadows = false\n", "\tlight.Shadows = false\n\tparent.Name = \"Neon\"\n"),
    ("shadows from every player's light", CAT, SHOP, "\tlight.Shadows = false\n", "\tlight.Shadows = true\n"),
    ("a trail's drops following you", CAT, SHOP, "m.LockedToPart = not spec.trailing", "m.LockedToPart = true"),
    ("a new thing gone", CAT, SHOP, '\t{ id = "Starlight", tab = "Auras", kind = "aura", name = "Starlight",', '\t{ id = "Starlit", tab = "Auras", kind = "aura", name = "Starlight",'),
    ("a new print never drawn", STEPS, SHOP, '\telseif id == "SlimeStep" then\n', '\telseif id == "SlimeSteps" then\n'),
    ("a new print never laid", STEPS, SHOP, "BubbleSole = 2.6, SlimeStep = 5,", "BubbleSole = 2.6,"),
    ("a new pack with nothing to play", STEPS, SHOP, '\tVelvet = { events = { "leafBrush", "cloudHush" }, volume = 0.55 },\n', ""),
    ("a name never declared", CAT, PARSE, "\tm.Color = colourSequence(spec.colours)\n", "\tm.Color = colourSequences(spec.colours)\n"),
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
