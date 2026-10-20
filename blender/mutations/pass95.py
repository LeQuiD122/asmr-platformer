"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 95, from the fourth test: the mouth's dark you can see in, and the drain under the water. The dark
black again, or lit so the halls show, or its exposure turned right down; the lamp over you not falling with you, left
hanging, too faint, or reaching the walls; the light in your head faint again; the mouth's own glow gone (shadowed off
its outside), on before it comes, warm (the pumpkin), or bright enough to light the shaft; the drain not under the
water, still under it in the culvert, or left on the screen when the character changes; the water too thin (the sky
shows) or too thick, or not the sea's colour; the air, the tint or the thickening not put back; a name never
declared.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
HC = S / "Client/Services/FloodedHallsClient.lua"
MAW = S / "Client/Services/Maw.lua"
SUNK = S / "Client/Services/SunkenCityClient.lua"
HALLS, SUNKCHECK, PARSE = "check_halls.py", "check_sunkencity.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (HALLS, SUNKCHECK, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('the dark black again', HC, HALLS, 'local DARK = { ambient = Color3.fromRGB(24, 26, 34),', 'local DARK = { ambient = Color3.fromRGB(5, 5, 7),'),
    ('the halls lit up', HC, HALLS, 'local DARK = { ambient = Color3.fromRGB(24, 26, 34),', 'local DARK = { ambient = Color3.fromRGB(90, 92, 100),'),
    ('the exposure turned right down', HC, HALLS, 'exposure = -0.1, colour', 'exposure = -0.35, colour'),
    ('the lamp not falling with you', HC, HALLS, 'lit.lamp.WorldPosition = pos + Vector3.new(0, DARK.over, 0) + inward * 2', 'lit.lamp.WorldPosition = lit.lamp.WorldPosition'),
    ('the lamp left hanging', HC, HALLS, '\tif lit.lamp then\n\t\tlit.lamp:Destroy()', '\tif lit.lamp then\n\t\tlocal _ = lit.lamp'),
    ('the lamp too faint', HC, HALLS, 'over.Brightness = 1.4', 'over.Brightness = 0.3'),
    ('the lamp reaching the walls', HC, HALLS, 'over.Range = 18', 'over.Range = 60'),
    ('the light in your head faint again', HC, HALLS, 'glimmer.Brightness = 1.2', 'glimmer.Brightness = 0.6'),
    ('its glow shadowed off its outside', MAW, HALLS, 'faint.Shadows = false', 'faint.Shadows = true'),
    ('its glow on before it comes', MAW, HALLS, '\t\tfaint.Brightness = 0\n', '\t\tfaint.Brightness = 0.7\n'),
    ('a warm glow, the pumpkin', MAW, HALLS, 'faint.Color = Color3.fromRGB(120, 210, 180)', 'faint.Color = Color3.fromRGB(255, 150, 60)'),
    ('a glow that lights the shaft', MAW, HALLS, 'faint.Brightness = 0.7 * amount * pulse', 'faint.Brightness = 3 * amount * pulse'),
    ('the drain not under the water', SUNK, SUNKCHECK, '\t\tsubmerge(frame.Position.Y < current.spec.funnelY)\n', '\t\tsubmerge(false)\n'),
    ('under the water in the culvert', SUNK, SUNKCHECK, '\tsubmerge(false)\n\tif not o then', '\tif not o then'),
    ('the water left on a new character', SUNK, SUNKCHECK, '\t\tcutscene.finish()\n\t\tsubmerge(false)\n\t\treturn', '\t\tcutscene.finish()\n\t\treturn'),
    ('water so thin the sky shows', SUNK, SUNKCHECK, 'local UNDER = { density = 0.62,', 'local UNDER = { density = 0.2,'),
    ('water too thick to see the whirlpool', SUNK, SUNKCHECK, 'local UNDER = { density = 0.62,', 'local UNDER = { density = 0.95,'),
    ("not the sea's colour", SUNK, SUNKCHECK, 'colour = Color3.fromRGB(34, 82, 86)', 'colour = Color3.fromRGB(120, 60, 40)'),
    ('the air not put back', SUNK, SUNKCHECK, 'Density = was.density, Offset = was.offset, Color = was.colour,', 'Density = UNDER.density, Offset = was.offset, Color = was.colour,'),
    ('the sea tint left on', SUNK, SUNKCHECK, 'game:GetService("Debris"):AddItem(was.grade, UNDER.out + 0.2)', 'local _ = was.grade'),
    ('the thickening carrying on', SUNK, SUNKCHECK, 'for _, made in ipairs(was.tweens) do\n\t\tmade:Cancel()', 'for _, made in ipairs(was.tweens) do\n\t\tlocal _ = made'),
    ('a name never declared', SUNK, PARSE, 'local was = under :: Under', 'local was = unders :: Under'),
    ('a name never declared', MAW, PARSE, 'table.insert(aura, faint)', 'table.insert(auras, faint)'),
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
