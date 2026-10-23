"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 129, from your test: City Shore. The bricks levered, not struck, the way out not told, the prompt on a brick,
sliding out flat; never struck, the bar never meeting the wall, struck from out of reach, no chips, silent blows, the last
blow after the bricks, no blow to act; Maren unmoved, facing away, or the deck again; the hit cut straight under, the
under-water look over it, no foam, no air; the butter in glass; the strike's sounds not looked for; a name never
declared.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
BOOT = S / "Server/Bootstrap.server.lua"
BUILDER = S / "Server/ChunkBuilder.server.lua"
INTERACT = S / "Server/Services/Interactables.lua"
POSES = S / "Shared/Poses.lua"
SHORE = S / "Client/Services/CityShoreClient.lua"
STORYC = S / "Client/Services/StoryClient.lua"
HUB, SHOTS, STORY, PARSE = "check_hub.py", "check_shots.py", "check_story.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (HUB, SHOTS, STORY, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('levered, not struck', INTERACT, STORY, '\t\tstrike = true,\n', '\t\tstrike = false,\n'),
    ('the way out not told', INTERACT, STORY, 'strike = on.strike == true, out = host.CFrame.LookVector', 'strike = on.strike == true'),
    ('the prompt on a brick', INTERACT, STORY, 'openable(patch, "Prise out", "Loose bricks", true,', 'openable(bricks[1], "Prise out", "Loose bricks", true,'),
    ('the bricks sliding out flat', INTERACT, STORY, 'b.AssemblyAngularVelocity = Vector3.new(math.random(-8, 8), math.random(-8, 8), math.random(-8, 8))', 'local _ = b'),
    ('never struck', STORYC, STORY, 'if data.strike == true and typeof(data.out) == "Vector3" and Poses and Poses.STRIKES then', 'if false then'),
    ('the bar never meeting the wall', STORYC, STORY, 'bar.CFrame = CFrame.lookAt(grip, grip + dir) * CFrame.new(0, 0, -(BAR_LONG / 2 - 0.25))', 'local _ = dir'),
    ('struck from out of reach', STORYC, STORY, 'local STRIKE_STAND = 4.2', 'local STRIKE_STAND = 7'),
    ('no chips', STORYC, STORY, 'chips(at, flatOut, 6, 1)', 'local _ = flatOut'),
    ('silent blows', STORYC, STORY, 'Cinema.sound("BarStrike", 0.7,', 'Cinema.sound("BarKnock", 0.7,'),
    ('the last blow after the bricks', POSES, STORY, 'Poses.STRIKES = { 0.45, 0.95, 1.45 }', 'Poses.STRIKES = { 0.45, 0.95, 1.7 }'),
    ('no blow to act', POSES, STORY, 'function Poses.strike(name: string, t: number, w: number, r6: boolean): CFrame?', 'function Poses.swing(name: string, t: number, w: number, r6: boolean): CFrame?'),
    ('Maren unmoved', SHORE, STORY, 'pcall(marenReacts, current, toward, t - 1.6)', 'local _ = marenReacts'),
    ('Maren facing away', SHORE, STORY, 'figure:PivotTo(CFrame.lookAt(pivot.Position, pivot.Position + toward))', 'local _ = pivot'),
    ('into the deck again', SHORE, SHOTS, 'local toward = Vector3.new(current.tip.X - head.X, 0, current.tip.Z - head.Z)', 'local toward = Vector3.new(here.X - head.X, 0, here.Z - head.Z)'),
    ('the hit cut straight under', SHORE, STORY, 'current.shot = "splash"', 'current.shot = "under"'),
    ('the under-water look over the hit', SHORE, STORY, '\t\t\t\tfx.Enabled = true\n', '\t\t\t\tfx.Enabled = fx.Enabled\n'),
    ('no foam', SHORE, STORY, '"SplashFoam"', '"SplashFlat"'),
    ('no air', SHORE, STORY, 'burst:Emit(140)', 'burst:Emit(0)'),
    ("Maren's shot too far, not restated", SHORE, SHOTS, 'head + toward * 6 + Vector3.new(-toward.Z, 0, toward.X) * 1.5', 'head + toward * 9 + Vector3.new(-toward.Z, 0, toward.X) * 1.5'),
    ('a glass case of butter', BUILDER, STORY, 'ButterWax = { whiten = 0.5, transparency = 0.06, reflectance = 0.12 },', 'ButterWax = { whiten = 0.62, transparency = 0.3, reflectance = 0.10 },'),
    ('the sticks in glass', BUILDER, STORY, 'ButterStick = { whiten = 0.35, transparency = 0.06, reflectance = 0.12 },', 'ButterStick = { whiten = 0.35, transparency = 0.3, reflectance = 0.12 },'),
    ("the strike's sounds not looked for", BOOT, HUB, '"PoolsSong", "BarStrike", "BrickBurst" }', '"PoolsSong" }'),
    ('a name never declared', SHORE, PARSE, 'foam.Shape = Enum.PartType.Cylinder', 'foams.Shape = Enum.PartType.Cylinder'),
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
