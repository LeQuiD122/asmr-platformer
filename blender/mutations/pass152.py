"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 152: your footing. Ice with a grip like a floor; a cloud leaving your soles dry; lamb's ear wiping
nothing; sticky soles sliding; a slide in a scene; the slide reading the walk it gives (feeding on itself); ordinary ground
taken over; the slide before Roblox reads your keys; the prints never thinned; the cloud's hint silent about wet shoes.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
ONBOARD = S / "Client/Services/OnboardingService.lua"
RUNFEEL = S / "Client/Services/RunFeel.lua"
FEEL = "check_feel.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (FEEL,):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('ice not slippery', RUNFEEL, FEEL, 'grip = { Ice = 1.6, Soap = 2.6,', 'grip = { Ice = 9, Soap = 2.6,'),
    ('a cloud leaves your soles dry', RUNFEEL, FEEL, 'leaves = { Cloud = "wet", ', 'leaves = { '),
    ("lamb's ear wipes nothing", RUNFEEL, FEEL, 'wipes = { LambsEar = true }', 'wipes = {}'),
    ('sticky soles slide', RUNFEEL, FEEL, 'if residue.holds then\n\t\t\treturn nil,', 'if residue.never then\n\t\t\treturn nil,'),
    ('the slide in a scene', RUNFEEL, FEEL, '\t\tor state == Enum.HumanoidStateType.Seated or inScene() then', '\t\tor state == Enum.HumanoidStateType.Seated then'),
    ('the slide feeding on itself', RUNFEEL, FEEL, 'local move = controls:GetMoveVector()', 'local move = humanoid.MoveDirection'),
    ('ordinary ground taken over', RUNFEEL, FEEL, '\t\tif speed < 1 then\n\t\t\thumanoid:Move(wanted * speed, false)\n\t\tend\n', '\t\thumanoid:Move(wanted * speed, false)\n'),
    ('the slide before the keys are read', RUNFEEL, FEEL, 'Enum.RenderPriority.Input.Value + 1,', 'Enum.RenderPriority.Input.Value - 1,'),
    ('the prints never thinned', RUNFEEL, FEEL, 'while #slide.prints > FOOTING.kept do', 'while #slide.prints > FOOTING.kept * 100 do'),
    ("the cloud's hint silent about wet shoes", ONBOARD, FEEL, 'Cloud = "Cloud wets your shoes,', 'Cloud = "Cloud is soft,'),
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
