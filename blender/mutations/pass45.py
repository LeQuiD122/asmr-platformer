"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 45: the self-test's client half. Never run; the shop not opened (or unguarded); the journal's close not
seen; the emote picker opened unguarded; nothing said.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
DEV = S / "Client/Services/DevPanelClient.lua"
SHOP, PARSE = "check_shop.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (SHOP, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ("never run", DEV, SHOP, "\t\t\t\ttask.spawn(clientSelfTest)\n", "\t\t\t\ttask.spawn(print)\n"),
    ("the shop not opened", DEV, SHOP, "local opened, err = pcall(shop.open)", "local opened, err = true, nil"),
    ("the journal's close not seen", DEV, SHOP, 'check("the journal closes", closed and journal.isOpen() == false',
     'check("the journal closes", closed'),
    ("the emote picker unguarded", DEV, SHOP, "local opened, err = pcall(emotes.open)", "local opened, err = true, emotes.open()"),
    ("nothing said", DEV, SHOP, '("SELF-TEST (client): %d of %d passed.', '("SELF-TEST: %d of %d.'),
    ("a name never declared", DEV, PARSE, 'local journal = service("JournalService")', 'local journal = servic("JournalService")'),
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
