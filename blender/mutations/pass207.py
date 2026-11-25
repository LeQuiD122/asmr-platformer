"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 207 (and the endings' score of 211): sand fills its holes on screen, butter is slow and sure-footed where its wax
is broken, home only once after an ending, the score under each ending. A hole never remembered; a print left in the
air; a filled hole held down; holes kept forever; butter as fast broken as whole; butter's softSpeed honey-slow; broken
wax never asked; still sliding on soft butter; home twice; an ending waited out after leaving; no climax; no score.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
RENDER = S / "Client/Services/DeformationRenderer.lua"
DEFORM = S / "Server/Services/DeformationService.lua"
FEEL = S / "Client/Services/RunFeel.lua"
MATS = S / "Shared/MaterialConfig.lua"
BOOT = S / "Server/Bootstrap.server.lua"
CINEMA = S / "Client/Services/Cinema.lua"
HILL = S / "Client/Services/HillHouseClient.lua"
SHORE = S / "Client/Services/CityShoreClient.lua"
BUILDER = S / "Server/ChunkBuilder.server.lua"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in ("check_feel.py", "check_story.py"):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('a sand hole never remembered', "check_feel.py", RENDER, 'SAND.holes[tile] = true', 'local _ = true'),
    ('holes kept after their chunk', "check_feel.py", RENDER, 'SAND.holes = (setmetatable({}, { __mode = "k" }) :: any)',
     'SAND.holes = ({} :: any)'),
    ('butter as fast broken as whole', "check_feel.py", DEFORM,
     'humanoid.WalkSpeed = Constants.DEFAULT_WALKSPEED * (if cell and cell.broken then matDef.softSpeed else 1)',
     'humanoid.WalkSpeed = Constants.DEFAULT_WALKSPEED'),
    ("butter's softSpeed honey-slow", "check_feel.py", MATS, 'softSpeed = 0.72,', 'softSpeed = 0.3,'),
    ('a mended cell still broken', "check_feel.py", DEFORM, '\tcell.broken = nil\n', '\n'),
    ('still sliding on soft butter', "check_feel.py", FEEL, 'local rate = if f and f.on and not f.soft then FOOTING.grip[f.on] else nil',
     'local rate = if f and f.on then FOOTING.grip[f.on] else nil'),
    ('home twice after an ending', "check_story.py", BOOT,
     'return player.Parent ~= Players or not HubService.isInRun(player) or levelInstance ~= finished',
     'return player.Parent ~= Players'),
    ('an ending waited out after leaving', "check_story.py", BOOT,
     'while sceneState[player] == "began" and waited < SCENE_WAIT and not homeAlready() do',
     'while sceneState[player] == "began" and waited < SCENE_WAIT do'),
    ('no climax under Hill House', "check_feel.py", HILL, 'Cinema.climax(1.06)', 'local _ = 1.06'),
    ('no score under City Shore', "check_feel.py", SHORE, 'Cinema.score("Shore")', 'local _ = "Shore"'),
    ("the score's bed left playing", "check_feel.py", CINEMA, "\tscoring.bed = nil\n\tscoring.token += 1\n\tif current.ending",
     "\tscoring.token += 1\n\tif current.ending"),
    ('chunked chocolate looks for a mesh', "check_feel.py", BUILDER, 'if MESHLESS[materialName] or CHUNKED[materialName] then',
     'if MESHLESS[materialName] then'),
]

paths = {m[2] for m in MUTATIONS}
originals = {path: path.read_bytes() for path in paths}
missed = []
try:
    for label, checker, path, old, new in MUTATIONS:
        text = originals[path].decode("utf-8").replace("\r\n", "\n")
        assert text.count(old) == 1, "%s: anchor found %d times" % (label, text.count(old))
        path.write_bytes(text.replace(old, new).encode("utf-8"))
        result = run(checker)
        path.write_bytes(originals[path])
        caught = result.returncode != 0
        why = [line.strip() for line in (result.stdout + result.stderr).splitlines() if "FAIL" in line or "fail" in line][:2]
        print("%-8s %s  %s" % ("caught" if caught else "MISSED", label, "; ".join(why)[:170]))
        if not caught:
            missed.append(label)
finally:
    for path, data in originals.items():
        path.write_bytes(data)
print("\n%d of %d caught" % (len(MUTATIONS) - len(missed), len(MUTATIONS)))
sys.exit(1 if missed else 0)
