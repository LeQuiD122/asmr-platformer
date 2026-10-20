"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 36: the paste check. A module, a script or a sound the game has and the check does not look for, one it
looks for that the game does not have, an optional sound it never looks for, a module taken out that it no
longer says to delete; ProfileStore not looked for, a sound imported twice or a module pasted as the wrong
kind of script let through; and the check never run.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
BOOT = S / "Server/Bootstrap.server.lua"
HUBCHECK, PARSE = "check_hub.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (HUBCHECK, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ("a module not looked for", BOOT, HUBCHECK, '"LeaderboardService", "LevelService",', '"LevelService",'),
    ("a sound the game has not got", BOOT, HUBCHECK, '"RoofWind", "ShoreSea" }', '"RoofWind", "ShoreSea", "Gong" }'),
    ("a module taken out, not named", BOOT, HUBCHECK, 'local GONE = { "KeepsakeService", "PromptStyleService" }',
     'local GONE = { "KeepsakeService" }'),
    ("an optional sound never looked for", BOOT, HUBCHECK, "CountdownTock_x3 = true, JournalAdd = true,",
     "CountdownTock_x3 = true, JournalAdd = true, Gong = true,"),
    ("a script not looked for", BOOT, HUBCHECK, '\tscriptAt(ServerScriptService, "ServerScriptService", "ChunkProps", "Script")\n', ""),
    ("ProfileStore not looked for", BOOT, HUBCHECK, 'local profileStore = ServerScriptService:FindFirstChild("ProfileStore")',
     'local profileStore = ServerScriptService:FindFirstChild("Profiles")'),
    ("a sound twice let through", BOOT, HUBCHECK, "elseif copies > 1 then", "elseif copies > 99 then"),
    ("the wrong kind let through", BOOT, HUBCHECK, 'elseif not found:IsA("ModuleScript") then', "elseif false then"),
    ("never run", BOOT, HUBCHECK, "local ok, err = pcall(pasteCheck)", "local ok, err = true, nil"),
    ("a name never declared", BOOT, PARSE, "for _, name in ipairs(SHARED_MODULES) do\n\t\tmoduleAt(shared,",
     "for _, name in ipairs(SHARED_MODULES) do\n\t\tmoduleAt(shard,"),
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
