"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 145: a long server stays quick. A level's platforms kept, or let go of and walked anyway; nothing
swept on the client, a table left out of the sweep (the tiles' rests, the bones), a new table that keeps everything, the
bone lists' cache strong again, the sweep put off for a quarter of an hour; a name in the sweep that is not a table.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
DEFORMS = S / "Server/Services/DeformationService.lua"
RENDER = S / "Client/Services/DeformationRenderer.lua"
POLISH, PARSE = "check_polish.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (POLISH, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ("a level's platforms kept for ever", DEFORMS, POLISH, '\t\tif platform.Parent == nil then\n\t\t\tplatformStates[platform] = nil\n\t\t\tcontinue\n\t\tend\n', ''),
    ('let go of and walked anyway', DEFORMS, POLISH, '\t\t\tplatformStates[platform] = nil\n\t\t\tcontinue\n', '\t\t\tplatformStates[platform] = nil\n'),
    ('nothing swept on the client', RENDER, POLISH, '\t\t\t\tif typeof(item) == "Instance" and item.Parent == nil then\n\t\t\t\t\tlist[item] = nil\n', '\t\t\t\tif typeof(item) == "Instance" and item.Parent == nil then\n\t\t\t\t\tlocal _ = list\n'),
    ("the tiles' rests left out of the sweep", RENDER, POLISH, '{ restCFrame, restSize, lastState,', '{ restSize, lastState,'),
    ('the bones left out of the sweep', RENDER, POLISH, 'sheetBones, burstBones }', 'sheetBones }'),
    ('a new table that keeps everything', RENDER, POLISH, 'local restCFrame: { [BasePart]: CFrame } = {}\n', 'local restCFrame: { [BasePart]: CFrame } = {}\nlocal restScale: { [BasePart]: number } = {}\n'),
    ("the bone lists' cache strong again", RENDER, POLISH, 'local reachCache: { [any]: number } = setmetatable({}, { __mode = "k" }) :: any', 'local reachCache: { [any]: number } = {}'),
    ('the sweep put off', RENDER, POLISH, '\t\ttask.wait(15)\n\t\tfor _, list in ipairs(kept) do', '\t\ttask.wait(900)\n\t\tfor _, list in ipairs(kept) do'),
    ('a name in the sweep that is not a table', RENDER, PARSE, 'granuleTotal, crumbling, sheetBones', 'granuleTotals, crumbling, sheetBones'),
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
