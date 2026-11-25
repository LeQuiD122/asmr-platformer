"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 169: Harrow Bay's surfaces. A part's own variant taken; a textured mesh dressed over; a character's clothes
dressed; a variant not yet made put on anyway; the missing said every time; a part added later left bare; the boards on
the wrong material; the manifest's boards on another material; the decks plastic again; the lobby never dressed.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
APPEAR = S / "Shared/MaterialAppearance.lua"
HUBS = S / "Server/Services/HubService.lua"
SURFGEN = ROOT / "blender/gen_surfaces.py"
SURF = "check_surfaces.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (SURF,):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ("a part's own variant taken", APPEAR, SURF, 'if not item:IsA("BasePart") or item.MaterialVariant ~= "" then', 'if not item:IsA("BasePart") then'),
    ('a textured mesh dressed over', APPEAR, SURF, 'if (item:IsA("MeshPart") and item.TextureID ~= "") or item:FindFirstChildOfClass("SurfaceAppearance") then', 'if false then'),
    ("a character's clothes dressed", APPEAR, SURF, 'if name and have[name] and not worn(item) then', 'if name and have[name] then'),
    ('a variant not yet made put on anyway', APPEAR, SURF, 'have[name] = variant ~= nil and variant:IsA("MaterialVariant")\n\t\tif not have[name] then', 'have[name] = true\n\t\tif not have[name] then'),
    ('the missing said every time', APPEAR, SURF, 'if #missing > 0 and not surfacesSaid then\n\t\tsurfacesSaid = true', 'if #missing > 0 then\n\t\tsurfacesSaid = true'),
    ('a part added later left bare', APPEAR, SURF, 'return root.DescendantAdded:Connect(one)', 'return root.ChildAdded:Connect(one)'),
    ('the boards on the wrong material', APPEAR, SURF, '[Enum.Material.WoodPlanks] = "HarrowBoards",', '[Enum.Material.Wood] = "HarrowBoards",'),
    ("the manifest's boards on another material", SURFGEN, SURF, "'HarrowBoards': (boards, 'WoodPlanks', 8,", "'HarrowBoards': (boards, 'Wood', 8,"),
    ('the decks plastic again', HUBS, SURF, 'Vector3.new(deck.x, 0, deck.z), Enum.Material.Slate,', 'Vector3.new(deck.x, 0, deck.z), Enum.Material.SmoothPlastic,'),
    ('the lobby never dressed', HUBS, SURF, '\tlocal dressOk, dressErr = pcall(MaterialAppearance.dress, folder)\n', '\tlocal dressOk, dressErr = true, nil\n'),
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
