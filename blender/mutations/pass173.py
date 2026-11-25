"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 173: the levels' worlds dressed where they are put. The Levels folder never watched; the workspace not
watching for it; any folder taken for it; a Levels folder already there left alone; a world already there never
dressed; a world dressed twice; the Sky Pools built somewhere nothing can tell.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
BOOT = S / "Server/Bootstrap.server.lua"
SURF = "check_surfaces.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (SURF,):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('the Levels folder never watched', BOOT, SURF, '\t\tfolder.ChildAdded:Connect(dressWorld)\n', ''),
    ('the workspace not watching for it', BOOT, SURF, '\tdressWorld(child)\n\twatchLevels(child)\nend)', '\tdressWorld(child)\nend)'),
    ('any folder taken for it', BOOT, SURF, 'if folder.Name == "Levels" and folder:IsA("Folder") then', 'if folder:IsA("Folder") then'),
    ('a Levels folder already there left alone', BOOT, SURF, '\t\tfor _, child in ipairs(folder:GetChildren()) do\n\t\t\tdressWorld(child)\n\t\tend\n', ''),
    ('a world already there never dressed', BOOT, SURF, 'for _, child in ipairs(workspace:GetChildren()) do\n\tdressWorld(child)\n\twatchLevels(child)\nend\n', ''),
    ('a world dressed twice', BOOT, SURF, '\tif LEVEL_WORLDS[child.Name] and not dressedWorlds[child] then\n\t\tdressedWorlds[child] = true\n', '\tif LEVEL_WORLDS[child.Name] then\n'),
    ('the Sky Pools built somewhere nothing can tell', BOOT, SURF, 'SkyPoolsService.build(levelInstance, workspace:WaitForChild("Levels"))', 'SkyPoolsService.build(levelInstance, workspace:WaitForChild("Worlds"))'),
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
