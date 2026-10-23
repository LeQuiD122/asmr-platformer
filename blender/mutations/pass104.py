"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 104: what you say to them. A dash in a line; a clue nothing gives, or that puts nothing in the journal; a
topic after one nobody can be asked; the thread broken (your father never learnable); a choice not offered being said;
talking from across the level; what you learn not written down; walking away not putting the choices away; the Talk
remote never made; a name never declared.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
BOOT = S / "Server/Bootstrap.server.lua"
CONV = S / "Shared/Conversations.lua"
TALK = S / "Client/Services/TalkClient.lua"
TOWNS = S / "Server/Services/Townsfolk.lua"
STORY, PARSE = "check_story.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (STORY, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('a dash in a line', CONV, STORY, '"Then you go and get mine. Before he forgets the way back."', '"Then you go and get mine -- before he forgets the way back."'),
    ('a clue nothing gives', CONV, STORY, 'needs = "father", clue = "price", reply', 'needs = "father", reply'),
    ('a topic after nothing', CONV, STORY, 'after = "wick_marsh", clue = "father"', 'after = "wick_nobody", clue = "father"'),
    ('a clue with no note', CONV, STORY, 'price = { title = "What it cost him"', 'cost = { title = "What it cost him"'),
    ('the thread broken', CONV, STORY, 'say = "Why are you looking at me like that?", after = "wick_marsh"', 'say = "Why are you looking at me like that?", after = "wick_you"'),
    ('a choice not offered being said', TOWNS, STORY, 'for _, offered in ipairs(Conversations.offered(name, knownBy(player), saidBy(npc, player))) do', 'for _, offered in ipairs(Conversations.TOPICS[name] or {}) do'),
    ('talking from across the level', TOWNS, STORY, '> Conversations.REACH + 6 then', '> 1e6 then'),
    ('what you learn not written down', TOWNS, STORY, '\t\t\t\tpcall(book.take, player, { title = note.title, body = note.body }, nil, "note", { from = note.from })', '\t\t\t\tpcall(print, note.title)'),
    ('walking away not putting them away', TALK, STORY, '(root.Position - head.Position).Magnitude > reach then\n\t\t\thide()', '(root.Position - head.Position).Magnitude > reach * 100 then\n\t\t\thide()'),
    ('the Talk remote never made', BOOT, STORY, 'ensureRemoteEvent(remoteEventsFolder, "Talk")', 'ensureRemoteEvent(remoteEventsFolder, "Talks")'),
    ('a name never declared', TALK, PARSE, 'local reach = if Conversations then Conversations.REACH else 16', 'local reach = if Conversation then Conversations.REACH else 16'),
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
