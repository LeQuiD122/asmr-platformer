"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 158: the emotes. The Aura without its glow; its glow left on; an emote cut short; one left out of the
picker; one that cannot be bought; a looped one ending mid-loop.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
CAT = S / "Shared/ShopCatalog.lua"
EMOTEC = S / "Client/Services/EmoteService.lua"
POSES = S / "Shared/Poses.lua"
FEEL = "check_feel.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (FEEL,):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('the Aura without its glow', EMOTEC, FEEL, '\t\tif emote.aura then\n\t\t\tauraOn(entry, root :: BasePart)\n\t\tend\n', ''),
    ('the glow left on', EMOTEC, FEEL, '\tlocal glow = entry.glow\n\tif glow then', '\tlocal glow = nil\n\tif glow then'),
    ('an emote cut short', EMOTEC, FEEL, 'Groove = { pose = "emoteGroove", seconds = 8.9 },', 'Groove = { pose = "emoteGroove", seconds = 5 },'),
    ('an emote left out of the picker', EMOTEC, FEEL, '"Groove", "SitSquish", "Aura" }', '"Groove", "SitSquish" }'),
    ('an emote that cannot be bought', CAT, FEEL, '{ id = "Flex", tab = "Emotes", kind = "emote"', '{ id = "Flexx", tab = "Emotes", kind = "emote"'),
    ('a looped emote ending mid-loop', POSES, FEEL, 'emoteGroove = { seconds = 8.9, loop = { 0.4, 2.4 }', 'emoteGroove = { seconds = 8.5, loop = { 0.4, 2.4 }'),
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
