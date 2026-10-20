"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 47: the self-test sees what was built, and the server answering. The shelf not counted against the
keepsakes; anyone's statue taken for this player's; the journal not asked; the server asked unguarded; a save
that is not ready taken as an answer.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
ECON = S / "Server/Services/EconomyService.lua"
DEV = S / "Client/Services/DevPanelClient.lua"
SHOP, PARSE = "check_shop.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (SHOP, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ("the shelf not counted", ECON, SHOP, "toys == keepsakes and cards == keepsakes", "toys >= 0 and cards >= 0"),
    ("anyone's statue", ECON, SHOP, 'if stand:GetAttribute("Owner") == player.UserId then', "if stand then"),
    ("the journal not asked", DEV, SHOP, '\t\t{ name = "JournalState", label = "the journal answers", ready = true },\n', ""),
    ("the server asked unguarded", DEV, SHOP, "local asked, answer = pcall(function()\n\t\t\t\treturn remote:InvokeServer()\n\t\t\tend)",
     "local asked, answer = true, remote:InvokeServer()"),
    ("not ready taken as an answer", DEV, SHOP, "(not ask.ready or answer.ready == true)", "(not ask.ready or answer.ready ~= nil)"),
    ("a name never declared", DEV, PARSE, 'local functions = ReplicatedStorage:FindFirstChild("RemoteFunctions")',
     'local functions = ReplicatedStorag:FindFirstChild("RemoteFunctions")'),
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
