"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 78: the sounds, after the first test. A step sound on a level again, on every step, pitched up into a squeak,
an electronic blip, a pack with nothing to play, not from the chunks' own takes, too often, Roblox's footstep
silenced again, no way for a pack to have the takes; a remade chunk sound written by the old generator again (so a
re-run puts it back), not written at all, with a buzzing tone in it, or four takes that differ only by seed.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
STEPS = S / "Client/Services/StepService.lua"
AUDIO = S / "Client/Services/AudioService.lua"
OLDGEN = ROOT / "audio/gen_material_sfx.py"
NEWGEN = ROOT / "audio/gen_chunk_sfx.py"
SHOP, PARSE = "check_shop.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (SHOP, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ("a step sound on a level", STEPS, SHOP, ' and player:GetAttribute("InLevel") == nil\n', "\n"),
    ("a step sound on every step", STEPS, SHOP, "\t\t\tif w.count >= w.nextSound then\n", "\t\t\tif true then\n"),
    ("pitched up into a squeak", STEPS, SHOP, "s.PlaybackSpeed = 1 - PITCH_SPREAD + math.random() * PITCH_SPREAD * 2",
     "s.PlaybackSpeed = 1.8 + math.random() * PITCH_SPREAD"),
    ("pitched far either way", STEPS, SHOP, "local PITCH_SPREAD = 0.06", "local PITCH_SPREAD = 0.5"),
    ("an electronic blip", STEPS, SHOP, 'local FALLBACK = "rbxasset://sounds/action_footsteps_plastic.mp3"',
     'local FALLBACK = "rbxasset://sounds/electronicpingshort.wav"'),
    ("a pack with nothing to play", STEPS, SHOP, '\tPoppy = { events = { "bubblePop" }, volume = 0.26 },', '\tPoppy = { events = {  }, volume = 0.26 },'),
    ("not the chunks' own takes", STEPS, SHOP, "\t\t\tfor _, id in ipairs(audio.takesFor(event)) do",
     "\t\t\tfor _, id in ipairs({}) do"),
    ("too often to be now and then", STEPS, SHOP, "local EVERY_LOW, EVERY_HIGH = 3, 5", "local EVERY_LOW, EVERY_HIGH = 1, 1"),
    ("Roblox's footstep silenced", STEPS, SHOP, "\t\tmuteRunning(root, false)\n", "\t\tmuteRunning(root, wearsSound)\n"),
    ("no way to the takes", AUDIO, SHOP, "function AudioService.takesFor(event: string): { string }", "function AudioService.takes(event: string): { string }"),
    ("salt back in the old generator", OLDGEN, SHOP, '    ("ooblSquelch", oobleck_squelch),\n]',
     '    ("ooblSquelch", oobleck_squelch), ("saltCrunch", salt_crunch),\n]'),
    ("clay not written", NEWGEN, SHOP, '("claySquish", clay_squish), ', ""),
    ("a buzzing tone in the clay", NEWGEN, SHOP, "    press = filt(brown(d, rng), \"low\", 520) * swell(t, 0.025, 0.06, 0.09)\n",
     "    press = np.sin(phase(np.full_like(t, 150.0))) * swell(t, 0.025, 0.06, 0.09)\n"),
    ("four takes alike", NEWGEN, SHOP, "    tilt = 1.0 if take % 2 else 0.6", "    tilt = 1.0"),
    ("a name never declared", STEPS, PARSE, "\tlocal library = takes(pack)\n\tlocal s = Instance.new(\"Sound\")",
     "\tlocal library = take(pack)\n\tlocal s = Instance.new(\"Sound\")"),
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
