"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 16: the Hold and the keepsakes (LORE.md).
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
KEEP = S / "Shared/Keepsakes.lua"
INTER = S / "Server/Services/Interactables.lua"
JOURNAL = S / "Client/Services/JournalService.lua"
SCREEN = S / "Client/Services/ScreenEffects.lua"
TOWNS = S / "Server/Services/Townsfolk.lua"
STORY_SRC = S / "Server/Services/StoryService.lua"
HALLSC = S / "Client/Services/FloodedHallsClient.lua"
STORY, PARSE = "check_story.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (STORY, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ("a material nobody was holding", KEEP, STORY, "\tSoap = {\n", "\tSoapBar = {\n"),
    ("a keepsake with no line", KEEP, STORY, '\t\tline = "Made for the party on the eleventh. It is still fizzing.",\n', ""),
    ("a dash in a keepsake", KEEP, STORY, "Pip wanted the red set. Tobi said after the weekend.",
     "Pip wanted the red set -- Tobi said after the weekend."),
    # (Since the eighteenth pass the keepsakes are picked up into the journal, not cards on every step.)
    ("a card on every step again", SCREEN, STORY, "\tlocal look = LOOKS[materialName]\n\tif not look then",
     "\tservice.touched(materialName)\n\tlocal look = LOOKS[materialName]\n\tif not look then"),
    ("a keepsake nobody can pick up", INTER, STORY, "function Interactables.keepsake(", "function Interactables.keepsakes("),
    ("a line in the corner over a scene", JOURNAL, STORY, "while (Cinema and Cinema.active()) or isOpen do", "while isOpen do"),
    ("a dash in something Dev says", TOWNS, STORY, "Everything up here's gone soft. Everything's",
     "Everything up here's gone soft -- everything's"),
    ("a dash in a baths notice", STORY_SRC, STORY, "One front door key on a green ribbon, marked HILL HOUSE.",
     "One front door key -- green ribbon -- marked HILL HOUSE."),
    ("a dash in the flume's caption", HALLSC, STORY, '"Staff only beyond the flume."', '"Staff only -- beyond the flume."'),
    ("a block left open", JOURNAL, PARSE, "\t\ttoasting = false\n\tend)\nend\n", "\t\ttoasting = false\n\tend)\n"),
    ("a name never declared", JOURNAL, PARSE, "local entry: Entry = { id = id, kind = kind,",
     "local entry: Entry = { id = ident, kind = kind,"),
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
