"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 31: the journal kept between sessions, and tokens only for a route walked. Tokens paid for a jump to
the finish; a save with no journal, uncapped, keeping things twice, unchecked or with the first reader's name
in it; a journal asked for without end, never answered, never made, never asked for or never read back; read
back loudly or unread; nothing marked or tagged to show as taken; a secret's card counting this session only.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
BOOT = S / "Server/Bootstrap.server.lua"
ECON = S / "Server/Services/EconomyService.lua"
INTER = S / "Server/Services/Interactables.lua"
STORY_SRC = S / "Server/Services/StoryService.lua"
JOURNAL = S / "Client/Services/JournalService.lua"
SHOP, STORY, PARSE = "check_shop.py", "check_story.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (SHOP, STORY, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    # Tokens only for a route walked.
    ("tokens for a jump to the finish", BOOT, SHOP, "if EconomyService and walked then", "if EconomyService then"),
    ("a time without the walk", BOOT, SHOP, "if not walkedRoute(player, state) then\n\t\treturn false",
     "if false then\n\t\treturn false"),
    # The save.
    ("no journal in the save", ECON, STORY, "Journal = {} :: { any },", "Diary = {} :: { any },"),
    ("the journal uncapped", ECON, STORY, "if #journal >= JOURNAL_MOST then", "if #journal >= math.huge then"),
    ("kept twice", ECON, STORY, "if kept.id == id then\n\t\t\treturn", "if false then\n\t\t\treturn"),
    ("an id unchecked", ECON, STORY, 'if typeof(id) ~= "string" or #id > 160 then', 'if typeof(id) ~= "string" then'),
    ("words uncapped", ECON, STORY, "kept[field] = string.sub(value, 1, 4000)", "kept[field] = value"),
    ("asked for without end", ECON, STORY, "if last and now - last < 0.5 then", "if false then"),
    ("the name never put back", ECON, STORY, 'entry.body = (entry.body:gsub("%%s", name))', "entry.body = entry.body"),
    ("nothing answers", ECON, STORY, "journalState.OnServerInvoke = onJournal", "journalState.OnServerInvoke = nil"),
    ("no remote made", BOOT, STORY, 'ensureRemoteFunction(remoteFunctionsFolder, "JournalState")', "-- JournalState"),
    ("kept with the first reader's name", INTER, STORY, "title = entry.title, body = entry.body,",
     "title = entry.title, body = entry.body .. player.Name,"),
    # Shown as taken.
    ("a letter unmarked", INTER, STORY, '\tInteractables.mark(sheet, "note:" .. entry.title)\n', ""),
    ("a keepsake unmarked", INTER, STORY, '\tInteractables.mark(model, "keepsake:" .. entry.thing)\n', ""),
    ("a notice unmarked", STORY_SRC, STORY, '\t\tInteractables.mark(paper, "note:" .. entry.title)\n', ""),
    ("nothing tagged", INTER, STORY, 'CollectionService:AddTag(object, "JournalThing")',
     'CollectionService:AddTag(object, "Journal")'),
    ("a secret's card this session only", INTER, STORY,
     'count = math.max(count, before + (if kept["secret:" .. noteTitle] then 0 else 1))', "count = count"),
    # Read back.
    ("read back unread", JOURNAL, STORY, "read = data.restored == true", "read = false"),
    ("read back loudly", JOURNAL, STORY, "data.quiet = true\n\t\t\t\t\tdata.restored = true", "data.restored = true"),
    ("never asked for", JOURNAL, STORY, 'functions:WaitForChild("JournalState", 20)', 'functions:WaitForChild("JournalStates", 20)'),
    ("not shown as taken in view", JOURNAL, STORY,
     '\tCollectionService:GetInstanceAddedSignal("JournalThing"):Connect(hideIfKept)\n', ""),
    ("never read back", JOURNAL, STORY, "task.spawn(readBack)", "task.spawn(function() end)"),
    # The code still reads.
    ("a name never declared", ECON, PARSE, "local name = string.upper(player.DisplayName)\n\tlocal out = {}",
     "local name = string.upper(plyer.DisplayName)\n\tlocal out = {}"),
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
