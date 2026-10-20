"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 75: what the review of passes 50 to 74 found. A challenge done earlier today told again on joining (what is done
never seen first, or never noted as seen); a material no longer in the save keeping its page in the journal, still
counting, or still lighting the book's badge.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
VOTE = S / "Client/Services/HubVoteService.lua"
JOURNAL = S / "Client/Services/JournalService.lua"
HUBCHECK, SHOP, PARSE = "check_hub.py", "check_shop.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (HUBCHECK, SHOP, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ("what is done never seen first", VOTE, HUBCHECK, 'if type(ids) == "string" and ids == knownIds and seenDone then',
     'if type(ids) == "string" and ids == knownIds then'),
    ("never noted as seen", VOTE, HUBCHECK, '\tseenDone = type(doneValue) == "string"\n', ""),
    ("a page kept after the save lost it", JOURNAL, SHOP,
     '\t\t\tif entry.kind == "material" and not keep[entry.id] then\n\t\t\t\ttable.remove(entries, index)\n',
     '\t\t\tif false then\n\t\t\t\ttable.remove(entries, index)\n'),
    ("still in the list by id", JOURNAL, SHOP, "\t\t\t\tbyId[entry.id] = nil\n", ""),
    ("still counting", JOURNAL, SHOP, "\t\t\t\tcounts.material = math.max(0, (counts.material or 0) - 1)\n", ""),
    ("still lighting the badge", JOURNAL, SHOP, "\t\tif gone then\n\t\t\trefreshBadge()\n", "\t\tif gone then\n"),
    ("a name never declared", VOTE, PARSE, "\tlocal doneList = split(doneValue)\n", "\tlocal doneList = split(doneValues)\n"),
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
