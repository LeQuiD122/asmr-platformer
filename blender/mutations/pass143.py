"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 143: what is open put away for the black, and nothing over it. Nothing put away for a dip or a move, or
by a list of its own; the list kept inside Cinema; the post box's card left up, or shut only from inside; the journal
left open; the black under the journal or the shop again, or over the squish room's own cover; the helper never
declared.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
CBOOT = S / "Client/Bootstrap.client.lua"
CINEMA = S / "Client/Services/Cinema.lua"
SHOPC = S / "Client/Services/ShopService.lua"
UIS = S / "Client/Services/UIService.lua"
POLISH, PARSE = "check_polish.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (POLISH, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('nothing put away for a dip', CBOOT, POLISH, '\t\tif payload.dip then\n\t\t\tputAway()\n', '\t\tif payload.dip then\n'),
    ('nothing put away for a move', CBOOT, POLISH, '\t\telseif payload.black == true then\n\t\t\tputAway()\n', '\t\telseif payload.black == true then\n'),
    ('put away by another list', CBOOT, POLISH, 'local cinema = Services:FindFirstChild("Cinema")', 'local cinema = Services:FindFirstChild("ShopService")'),
    ('the list kept inside Cinema', CINEMA, POLISH, 'Cinema.closeOverlays = closeOverlays\n', ''),
    ('the post box left up', CINEMA, POLISH, '\t\tif m.closeCodes then\n\t\t\tm.closeCodes()\n\t\tend\n', ''),
    ('the post box shut from inside only', SHOPC, POLISH, 'function ShopService.closeCodes()\n\tcloseCodes()\nend\n', ''),
    ('the journal left open', CINEMA, POLISH, '\tbesideDo("JournalService", function(m)', '\tbesideDo("JournalBook", function(m)'),
    ('the black under the journal', UIS, POLISH, 'fadeGui.DisplayOrder = 46', 'fadeGui.DisplayOrder = 44'),
    ('the black under the shop again', UIS, POLISH, 'fadeGui.DisplayOrder = 46', 'fadeGui.DisplayOrder = 30'),
    ("the black over the squish room's cover", UIS, POLISH, 'fadeGui.DisplayOrder = 46', 'fadeGui.DisplayOrder = 55'),
    ('the helper never declared', CBOOT, PARSE, 'local function putAway()', 'local function putAwayAll()'),
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
