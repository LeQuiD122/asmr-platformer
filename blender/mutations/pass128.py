"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 128, from your test: Hill House. The grass filled over, not taken away, in the house or up the path, or
changed off the terrain's grid; the ceiling not solid; the camera kept in the hall before it has moved, or held in it
in the scene; the key taken from behind your head; never turning to the clock; no start; the arm up at the hook; the
clock's shot changed, not restated.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
HILLC = S / "Client/Services/HillHouseClient.lua"
HOUSE = S / "Server/Services/HillHouseService.lua"
HILL, SHOTS = "check_hillhouse.py", "check_shots.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (HILL, SHOTS):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('grass in the hall', HOUSE, HILL, 'bareGround(houseMid, inward, HOUSE_W + 2, HOUSE_D + 2)', 'local _ = houseMid'),
    ('grass up the path', HOUSE, HILL, 'bareGround(pathMid, inward, 4.5, pathLong + 3)', 'local _ = pathMid'),
    ("off the terrain's grid", HOUSE, HILL, 'local y0 = math.floor((mid.Y - 8) / 4) * 4', 'local y0 = mid.Y - 8'),
    ('the ceiling not solid', HOUSE, HILL, 'centre * CFrame.new(0, STOREY, 0), PALETTE.timber,\n\t\tEnum.Material.WoodPlanks, true)', 'centre * CFrame.new(0, STOREY, 0), PALETTE.timber,\n\t\tEnum.Material.WoodPlanks)'),
    ('the camera kept in before it moves', HILLC, HILL, 'RunService:BindToRenderStep("HillHallCamera", Enum.RenderPriority.Camera.Value + 1, function()', 'RunService:BindToRenderStep("HillHallCamera", Enum.RenderPriority.Camera.Value - 1, function()'),
    ("a scene's camera held in the hall", HILLC, HILL, 'if scene or (Cinema and Cinema.active()) or Players.LocalPlayer:GetAttribute("InLevel") == nil then', 'if Players.LocalPlayer:GetAttribute("InLevel") == nil then'),
    ('taken from behind your head', HILLC, HILL, 'local eye = head + side * 3 + facing * 1.5 + Vector3.new(0, -0.5, 0)', 'local eye = head + side * 3.6 - facing * 1.2 + Vector3.new(0, 0.1, 0)'),
    ('never turning to the clock', HILLC, HILL, ';(root :: BasePart).CFrame = (root :: BasePart).CFrame:Lerp(CFrame.lookAt(here, here + toClock), 0.12)', 'local _ = toClock'),
    ('no start', HILLC, HILL, '+ 0.22 * start, 0, 0)', '+ 0 * start, 0, 0)'),
    ('the arm up at the hook', HILLC, HILL, 'return CFrame.Angles(1.7 * reach * (1 - bring) + 0.85 * bring * (1 - lower) + 0.3 * lower, 0,', 'return CFrame.Angles(2.25 * reach * (1 - bring) + 1.15 * bring * (1 - lower) + 0.45 * lower, 0,'),
    ("the clock's shot changed, not restated", HILLC, SHOTS, 'Cinema.point(CFrame.lookAt(eye, face + Vector3.new(0, -1.6, 0)), 50)', 'Cinema.point(CFrame.lookAt(eye, face + Vector3.new(0, -1.6, 0)), 40)'),
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
