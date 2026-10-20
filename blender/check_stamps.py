"""The paste check's fingerprints, checked without Studio.

    python blender/check_stamps.py

What it holds:
  * EVERY STAMP IS CURRENT: a module with a STAMP carries the fingerprint of its own contents (tools/stamp.py), so
    a file changed since it was stamped is caught here, before it can make a current copy in Studio look old.
  * EVERY CHANGED MODULE IS STAMPED: anything changed since the last commit is part of the next paste, so it
    carries a stamp the paste check can compare.
  * BOOTSTRAP EXPECTS EXACTLY THEM: the PASTE STAMPS list in Bootstrap.server is every stamped module, by kind,
    with its stamp; nothing more.
  * BOTH HALVES ARE WIRED: the server compares the server and shared modules and publishes the client's stamps;
    the client compares its own; both in Studio only, guarded, and naming the old copies.

Run `python tools/stamp.py` after changing a module. Exits non-zero on any failure.
"""
import importlib.util
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("stamp", ROOT / "tools" / "stamp.py")
stamp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(stamp)

problems = []


def fail(message):
    problems.append(message)


found = stamp.modules()
stamped = {}
for name, (kind, path) in sorted(found.items()):
    text, _ = stamp.read(path)
    have = stamp.stamp_of(text)
    if have is None:
        continue
    stamped[name] = (kind, have)
    if have != stamp.fingerprint(text):
        fail("%s has changed since it was stamped: run python tools/stamp.py" % name)
    if stamp.place(name, text, have) != text:
        fail("%s's stamp is not where tools/stamp.py puts it (before its last return)" % name)
for name in sorted(stamp.changed_since_baseline() & set(found)):
    if name not in stamped:
        fail("%s has changed since %s and carries no stamp: python tools/stamp.py --add %s"
             % (name, stamp.BASELINE, name))

boot, _ = stamp.read(stamp.BOOT)
start, finish = boot.find(stamp.BEGIN), boot.find(stamp.END)
if start < 0 or finish < 0:
    fail("Bootstrap.server has no PASTE STAMPS block")
else:
    listed = boot[start:finish + len(stamp.END)]
    if listed != stamp.block(stamped):
        fail("Bootstrap.server's PASTE STAMPS are not the modules' stamps: run python tools/stamp.py")

client_boot, _ = stamp.read(stamp.SRC / "Client" / "Bootstrap.client.lua")
for needle, why, text in (
    ('ReplicatedStorage:SetAttribute("PasteStamps", game:GetService("HttpService"):JSONEncode(PASTE_STAMPS.client or {}))',
     "the server does not hand the client its stamps", boot),
    ("local stamp = if ok and type(loaded) == \"table\" then loaded.STAMP else nil\n\t\t\t\tif stamp ~= expected[name] and not misplaced[name] then\n"
     "\t\t\t\t\ttable.insert(problems, (\"out of date", "the server does not compare its modules' stamps", boot),
    # ANOTHER MODULE'S CODE IN IT: a module whose stamp is another module's, stamped or not itself, on both sides.
    ("local whose = if type(stamp) == \"string\" then owner[stamp] else nil\n\t\t\t\tif whose and whose ~= name then",
     "the server never notices a module with another module's code pasted into it", boot),
    ("local whose = if type(stamp) == \"string\" then owner[stamp] else nil\n\t\t\tif whose and whose ~= found.Name then",
     "the client never notices a module with another module's code pasted into it", client_boot),
    ("for _, side in ipairs({ { names = SERVER_MODULES, folder = serverServices,",
     "the server looks for another module's code only in the stamped modules (BackdropService has no stamp)", boot),
    ("\tfor _, name in ipairs(ours) do\n\t\tlocal found = Services:FindFirstChild(name)",
     "the client requires every module it finds (one taken out of the game would be started up)", client_boot),
    ('local raw = ReplicatedStorage:GetAttribute("PasteStamps")', "the client never reads its stamps", client_boot),
    ("local stamp = if ok and type(loaded) == \"table\" then loaded.STAMP else nil\n\t\t\tif stamp ~= expected[name] then\n"
     "\t\t\t\ttable.insert(stale, name)", "the client does not compare its modules' stamps", client_boot),
    ('warn(("PASTE CHECK (client): %d old cop%s in StarterPlayerScripts/Services', "the client never names its old copies",
     client_boot),
    ("if game:GetService(\"RunService\"):IsStudio() then\n\ttask.delay(6, function()\n\t\tlocal ok, err = pcall(pasteCheckClient)",
     "the client's half is not run (in Studio, after the start, guarded)", client_boot),
):
    if needle not in text:
        fail(why)

# THE CLIENT'S UNSTAMPED MODULES, named in Bootstrap.client so it looks at them for another module's code (and at
# nothing else it does not know): exactly the client modules in src with no STAMP.
listed = re.search(r'local UNSTAMPED = \{ ([^}]*) \}', client_boot)
unstamped = sorted(p.stem for p in (stamp.SRC / "Client" / "Services").glob("*.lua")
                   if not re.search(r'^(?:\w+\.STAMP = "|\tSTAMP = ")', p.read_text(encoding="utf-8"), re.M))
if not listed:
    fail("Bootstrap.client no longer lists its unstamped modules (UNSTAMPED)")
elif sorted(re.findall(r'"(\w+)"', listed.group(1))) != unstamped:
    fail("Bootstrap.client's UNSTAMPED is %s; the client modules with no stamp are %s"
         % (sorted(re.findall(r'"(\w+)"', listed.group(1))), unstamped))

if problems:
    for problem in problems:
        print("FAIL: " + problem)
    sys.exit(1)
print("stamps: %d modules stamped and current, Bootstrap expects exactly them, both halves of the check wired."
      % len(stamped))
