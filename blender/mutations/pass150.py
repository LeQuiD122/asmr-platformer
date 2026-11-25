"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 150: what your Output said, and no trade marks. Cinema reaching for the LocalPlayer as it loads (the
server's check loads it), or hooking a new character there; Lego, Jello, NeeDoh or Kinetic Sand back on the board, in a hint,
in the shop's backgrounds or in the story's papers.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
CAT = S / "Shared/ShopCatalog.lua"
CINEMA = S / "Client/Services/Cinema.lua"
LOOK = S / "Client/Services/ShopLook.lua"
ONBOARD = S / "Client/Services/OnboardingService.lua"
STORYSV = S / "Server/Services/StoryService.lua"
FEEL = "check_feel.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (FEEL,):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('Cinema reaching for the LocalPlayer as it loads', CINEMA, FEEL, 'local me = Players.LocalPlayer\nif me then\n\tlocal wasIn = me:GetAttribute("InLevel")', 'local wasIn = Players.LocalPlayer:GetAttribute("InLevel")\nlocal me = Players.LocalPlayer\nif me then\n\tlocal _ = wasIn'),
    ('a new character hooked on the server too', CINEMA, FEEL, 'if me then\n\tme.CharacterAdded:Connect(function()', 'Players.LocalPlayer.CharacterAdded:Connect(function() end)\nif me then\n\tme.CharacterAdded:Connect(function()'),
    ('Lego on the board again', CAT, FEEL, '{ key = "Lego", name = "Toy bricks",', '{ key = "Lego", name = "Lego",'),
    ('Jello on the board again', CAT, FEEL, '{ key = "JelloSoda", name = "Jelly",', '{ key = "JelloSoda", name = "Jello",'),
    ('NeeDoh in a hint', ONBOARD, FEEL, 'Needoh = "A stress ball:', 'Needoh = "NeeDoh:'),
    ("Kinetic sand among the shop's backgrounds", LOOK, FEEL, 'name = "Sculpting sand", rarity', 'name = "Kinetic sand", rarity'),
    ('Kinetic sand in the Novelty Works list', STORYSV, FEEL, 'Sculpting sand, as used by Pip Okafor.', 'Kinetic sand, as used by Pip Okafor.'),
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
