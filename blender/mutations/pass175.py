"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 175: his letters in order. Never gathered; one shown twice; one not found yet opening a page; a controller
stopping on one; two levels swapped; one not found yet saying nothing of where; a letter not told by its title.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
JOURNAL = S / "Client/Services/JournalService.lua"
STORY = "check_story.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (STORY,):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('never gathered', JOURNAL, STORY, 'if shownKind == "note" then\n\t\tfor _, entry in ipairs(entries) do', 'if false then\n\t\tfor _, entry in ipairs(entries) do'),
    ('one shown twice', JOURNAL, STORY, 'if entry.kind == shownKind and not isLetter[entry.id] then', 'if entry.kind == shownKind then'),
    ('one not found yet opening a page', JOURNAL, STORY, '\t\tif entry then\n\t\t\trow.Activated:Connect(function()', '\t\tdo\n\t\t\trow.Activated:Connect(function()'),
    ('a controller stopping on one', JOURNAL, STORY, 'row.Selectable = entry ~= nil', 'row.Selectable = true'),
    ('two levels swapped', JOURNAL, STORY, '"in the Sky Pools", "in the Sunken City"', '"in the Sunken City", "in the Sky Pools"'),
    ('one not found yet saying nothing of where', JOURNAL, STORY, 'addRow(nil, ("A green envelope, %d of %d"):format(number, #LETTER_AT), "Still to find, " .. where)', 'addRow(nil, ("A green envelope, %d of %d"):format(number, #LETTER_AT), "")'),
    ('a letter not told by its title', JOURNAL, STORY, 'local LETTER_TITLE = "^A green envelope, (%d) of 5$"', 'local LETTER_TITLE = "^A green envelope (%d)$"'),
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
