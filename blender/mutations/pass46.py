"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 46: the client's self-test sees the cursor, the pause menu and the death card. The cursor read with the
test panel still freeing it, or never looked at; the death card's cursor not checked; the pause menu not opened,
its close not seen, or not openable from outside; the death card not shown, or its going not seen.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
DEV = S / "Client/Services/DevPanelClient.lua"
PAUSE = S / "Client/Services/PauseMenuService.lua"
SHOP, PARSE = "check_shop.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (SHOP, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ("the cursor read with the panel open", DEV, SHOP, "\tclose()\n\ttask.wait(0.3)\n\tlocal locked", "\tlocal locked"),
    ("the cursor never looked at", DEV, SHOP,
     'check(label .. ": the cursor free to press it", UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter)',
     'check(label .. ": the cursor free to press it", true)'),
    ("the death card's cursor not checked", DEV, SHOP, '\t\tcursorFree("the death card")\n', ""),
    ("the pause menu not opened", DEV, SHOP, "local opened, err = pcall(pause.setOpen, true)", "local opened, err = true, nil"),
    ("the pause menu's close not seen", DEV, SHOP, 'check("the pause menu closes", closed and pause.isOpen() == false',
     'check("the pause menu closes", closed'),
    ("the pause menu shut from outside", PAUSE, SHOP, "function PauseMenuService.setOpen(on: boolean)",
     "function PauseMenuService.openTo(on: boolean)"),
    ("the death card not shown", DEV, SHOP, "local shown, err = pcall(death.show, false)", "local shown, err = true, nil"),
    ("the death card's going not seen", DEV, SHOP, 'check("the death card goes", hidden and cardGui ~= nil',
     'check("the death card goes", hidden or cardGui ~= nil'),
    ("a name never declared", DEV, PARSE, 'local death = service("DeathService")', 'local death = servce("DeathService")'),
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
