"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 204: the Sky Pools' water, clouds and stone, and the City Shore's horizon. A fall's ribbons to the clouds, running
up, back to sheets of plastic, turned to the camera, never fading, the front one slower; an arc a bent pipe, the jet a
glass rod; the overflow plastic again, its water over its kerbs, deep enough to swim; the clouds' domes up into the
slide camera's clear air, a dome no Cloud, every cloud to the horizon heaped, the towering clouds by the slide; the
pools in the drowned city's ashlar, the marble scribbled black again; no hills, hills under the eye line, sky between
them, a hill bigger than a part; the towers with no windows, Neon windows, the backdrop's version not bumped.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
SKY = S / "Server/Services/SkyPoolsService.lua"
LOOK = S / "Shared/MaterialAppearance.lua"
BACK = S / "Server/Services/BackdropService.lua"
SKYCHECK = "check_skypools.py"
MADE = "check_made.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (SKYCHECK, MADE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ("a fall's ribbons to the clouds", SKY, SKYCHECK, 'local reach = math.min(height, RIBBON_REACH)', 'local reach = height'),
    ("a fall's water running up", SKY, SKYCHECK, 'speed = 1.1, alpha = 0.06', 'speed = -1.1, alpha = 0.06'),
    ('the glass sheets back', SKY, SKYCHECK, '\t\tribbon.Name = "FallRibbon"\n',
     '\t\tribbon.Name = "FallRibbon"\n\t\tblock(parent, "Waterfall", Vector3.one, lipAt, FALL, SHEEN, false)\n'),
    ('the ribbons turned to the camera', SKY, SKYCHECK, '-Vector3.yAxis, across)', '-Vector3.yAxis, nil)'),
    ('a long fall never fading', SKY, SKYCHECK, 'NumberSequenceKeypoint.new(1, if long then 1 else',
     'NumberSequenceKeypoint.new(1, if long then layer.alpha else'),
    ('the front ribbon slower', SKY, SKYCHECK, 'scale = 3.4, speed = 1.9,', 'scale = 3.4, speed = 0.9,'),
    ('an arc a bent pipe', SKY, SKYCHECK, 'stream.CurveSize0 = throw.Magnitude / 3', 'stream.CurveSize0 = throw.Magnitude / 2'),
    ('the jet a glass rod', SKY, SKYCHECK, 'jet.Transparency = 1', 'jet.Transparency = 0.45'),
    ('the overflow a film on the deck', SKY, SKYCHECK,
     'fillWater(frame * CFrame.new(rillMid, RILL_DEEP - 2, 0), Vector3.new(rillLong, 4, channel + 2))',
     'fillWater(frame * CFrame.new(rillMid, RILL_DEEP - 0.5, 0), Vector3.new(rillLong, 1, channel))'),
    ('the overflow over its kerbs', SKY, SKYCHECK, 'local kerbHigh = RILL_DEEP + 0.25', 'local kerbHigh = RILL_DEEP - 0.2'),
    ('the overflow deep enough to swim', SKY, SKYCHECK, 'local RILL_DEEP = 0.4', 'local RILL_DEEP = 3'),
    ("the domes up in the camera's clear air", SKY, SKYCHECK, 'local CLOUD_HEAD_ABOVE = 7', 'local CLOUD_HEAD_ABOVE = 20'),
    ('a dome no Cloud', SKY, SKYCHECK, 'local dome = ellipsoid(folder, "Cloud", ', 'local dome = ellipsoid(folder, "CloudDome", '),
    ('every cloud to the horizon heaped', SKY, SKYCHECK, 'local CLOUD_DETAIL = 1100', 'local CLOUD_DETAIL = 2400'),
    ('the towering clouds by the slide', SKY, SKYCHECK, 'local reach = rng:NextNumber(1500, 2200)',
     'local reach = rng:NextNumber(150, 2200)'),
    ("the pools in the drowned city's ashlar", LOOK, MADE, '[Enum.Material.Concrete] = { "SkyStone", "HarrowCast" },',
     '[Enum.Material.Concrete] = { "HarrowCast", "CityAshlar" },'),
    ('the marble scribbled black again', LOOK, MADE, '\t\t[Enum.Material.Marble] = "SkyMarble",\n', ''),
    ('no hills', BACK, MADE, '\tquays(model)\n\thills(model)\n', '\tquays(model)\n'),
    ('hills under the eye line', BACK, MADE, 'rise = { 760, 1000 }', 'rise = { 560, 1000 }'),
    ('sky between the hills', BACK, MADE, 'offset += wide * 0.5 / radius', 'offset += wide * 1.4 / radius'),
    ('a hill bigger than a part', BACK, MADE, 'rise = { 880, 1010 }', 'rise = { 880, 1300 }'),
    ('the towers with no windows', BACK, MADE, 'useVariant(stage, WINDOWS_VARIANT)', 'useVariant(stage, CONCRETE_VARIANT)'),
    ('Neon windows', BACK, MADE, 'if lit then Enum.Material.SmoothPlastic else Enum.Material.Glass',
     'if lit then Enum.Material.Neon else Enum.Material.Glass'),
    ("the backdrop's version not bumped", BACK, MADE, 'local BACKDROP_VERSION = 6', 'local BACKDROP_VERSION = 5'),
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
