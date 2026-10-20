"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 55: Near the end on the test panel, and the client's Self-test looking at the pads and the VIP tag. Near the
end in the live game, answering other buttons, moving someone not in a run, leaving no stretch to walk, landing off
a checkpoint, not setting the checkpoint, counting a skipped run (unmarked, marked late, or not refused); no button;
the self-test not checking City Shore, the boards and signs, or the VIP tag.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
BOOT = S / "Server/Bootstrap.server.lua"
DEV = S / "Client/Services/DevPanelClient.lua"
CHECK, PARSE = "check_shop.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (CHECK, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ("in the live game", BOOT, CHECK,
     '-- nothing (walkedRoute refuses it: no tokens, no time, no level opened), so a test cannot fake its way into a save.\n'
     'if game:GetService("RunService"):IsStudio() then',
     '-- nothing (walkedRoute refuses it: no tokens, no time, no level opened), so a test cannot fake its way into a save.\n'
     'if true then'),
    ("answering other buttons", BOOT, CHECK, 'if action ~= "nearEnd" then', 'if action == "tokens" then'),
    ("someone not in a run", BOOT, CHECK, "HubService.isInRun(player) and state and not state.hasCompletedLevel",
     "state and not state.hasCompletedLevel"),
    ("no stretch to walk", BOOT, CHECK, "local last = math.max(#chunks - 8, 2)", "local last = #chunks"),
    ("off a checkpoint", BOOT, CHECK, 'if def and def.category == "stable" and entry.index <= last',
     "if def and entry.index <= last"),
    ("the checkpoint not set", BOOT, CHECK, "\t\t\tPlayerStateService.setCheckpoint(player, at, target.index, -tangent)\n", ""),
    ("a skipped run unmarked", BOOT, CHECK, "\t\t\tstate.skipped = true\n", ""),
    ("marked after the move", BOOT, CHECK,
     "\t\t\tstate.skipped = true\n\t\t\tPlayerStateService.setCheckpoint(player, at, target.index, -tangent)\n"
     "\t\t\troot.AssemblyLinearVelocity = Vector3.zero\n"
     "\t\t\troot.CFrame = CFrame.lookAt(at + Vector3.new(0, 2, 0), at + Vector3.new(0, 2, 0) + tangent)\n",
     "\t\t\tPlayerStateService.setCheckpoint(player, at, target.index, -tangent)\n"
     "\t\t\troot.AssemblyLinearVelocity = Vector3.zero\n"
     "\t\t\troot.CFrame = CFrame.lookAt(at + Vector3.new(0, 2, 0), at + Vector3.new(0, 2, 0) + tangent)\n"
     "\t\t\tstate.skipped = true\n"),
    ("a skipped run counted", BOOT, CHECK, "\tif state.skipped then\n", "\tif state.skipped == 1 then\n"),
    ("no button", DEV, CHECK, '\t{ action = "nearEnd", text = "Near the end" },\n', ""),
    ("City Shore not checked", DEV, CHECK, '\t\t\t\tcheck("City Shore is open", not locked)\n', ""),
    ("boards not checked", DEV, CHECK, "boards == 2 and up == wanted and says == locked", "boards >= 0"),
    ("VIP tag not checked", DEV, CHECK, "(tag ~= nil) == vip and shownRight", "true"),
    ("a name never declared", BOOT, PARSE, "local last = math.max(#chunks - 8, 2)", "local last = math.max(#chunk - 8, 2)"),
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
