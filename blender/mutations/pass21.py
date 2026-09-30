"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 21: the Needoh's own sound (it had clay's), the lava about to go (glow, embers, bubbles, a
fountain), every ending scored with sounds of its own, and the high dive shot properly (Maren, the
gulls, the rushing air, the sun, the light and fish under the water).
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
CONFIG = S / "Shared/MaterialConfig.lua"
AUDIO = S / "Client/Services/AudioService.lua"
RENDER = S / "Client/Services/DeformationRenderer.lua"
CINEMA = S / "Client/Services/Cinema.lua"
SHORE = S / "Client/Services/CityShoreClient.lua"
SKYC = S / "Client/Services/SkyPoolsClient.lua"
SUNKC = S / "Client/Services/SunkenCityClient.lua"
HALLSC = S / "Client/Services/FloodedHallsClient.lua"
STORY, PARSE = "check_story.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (STORY, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    # The Needoh.
    ("the Needoh on clay's sound again", CONFIG, STORY, '\t\tsfxEvent = "needohSquish",\n\t\tsfxFallback',
     '\t\tsfxEvent = "claySquish",\n\t\tsfxFallback'),
    ("the Needoh's stand-in at clay's pitch", CONFIG, STORY, "sfxFallbackPitch = 0.68,", "sfxFallbackPitch = 1,"),
    ("a borrowed sound at the lender's pitch", AUDIO, STORY, "\t\tpitch = pitch or matDef.sfxFallbackPitch\n", "\t\tpitch = pitch\n"),
    # The lava.
    ("the lava never comes alive", RENDER, STORY, "\nlavaLife.start()\n", "\n\n"),
    ("no embers off the lava", RENDER, STORY, 'embers.Name = "Embers"', 'embers.Name = "Sparks"'),
    ("the lava never bubbles", RENDER, STORY, "lavaLife.bubble(platform, at)", "lavaLife.flare(platform, 0.1)"),
    ("a burst without a flare", RENDER, STORY, "lavaLife.flare(tile, 1)", "lavaLife.flare(tile, 0)"),
    # The endings' sounds.
    ("a scene's sounds left playing", CINEMA, STORY, "\tfor _, s in ipairs(current.sounds) do\n\t\tCinema.fade(s, 2.5)",
     "\tfor _, s in ipairs(current.sounds) do\n\t\tCinema.fade(s, 60)"),
    ("a silent splash", SHORE, STORY, 'Cinema.sound("DiveSplash"', 'Cinema.sound("DiveSplosh"'),
    ("the wind blowing under the water", SHORE, STORY, "Cinema.fade(current.wind, 0.3)", "Cinema.fade(nil, 0.3)"),
    ("no chord over the pool", SKYC, STORY, 'Cinema.sound("PoolsChord"', 'Cinema.sound("PoolChord"'),
    ("the whirlpool roaring down the culvert", SUNKC, STORY, "Cinema.fade(current.roar, 2.5)", "Cinema.fade(current.wash, 2.5)"),
    ("a silent flume", HALLSC, STORY, 'sound("FlumeRush", nil, 0, 1, true)', "sound(nil, nil, 0, 1, true)"),
    # The dive.
    ("no cut back to Maren", SHORE, STORY, 'shot("maren")', 'shot("deck")'),
    ("gulls that never scatter", SHORE, STORY, "here.Y - gull.home.Y < 24", "here.Y - gull.home.Y < -24"),
    ("the sun left flared", SHORE, STORY, "rays.Intensity = current.sunWas", "rays.Intensity = 0.32"),
    # The code still reads.
    ("a name never declared in the gulls", SHORE, PARSE, "* (if gull.fled then 16 else 6) + gull.flap) * 0.6",
     "* (if gull.fled then 16 else 6) + gull.flap) * sway"),
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
