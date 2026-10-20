"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 88: the chunk sounds, second round. A sheet not read as its takes, or its takes not given their slots;
old single takes picked alongside a sheet; the sand's and the bubble wrap's old uploads still picked; a take playing
on into the next; a sheet preloaded as nothing; a chunk's take played without its slot; the oobleck, lego and
keyboards not given their tone, or not louder; the solid chocolate or the jellyfish without an event of its own; the
bubble wrap faster than a footfall; a step sound from a sheet played from its start; the chocolate a tone again; a
name never declared.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
AUDIO = S / "Client/Services/AudioService.lua"
MATS = S / "Shared/MaterialConfig.lua"
SHEETGEN = ROOT / "audio/gen_sheet_sfx.py"
STEPS = S / "Client/Services/StepService.lua"
SHOP, PARSE = "check_shop.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (SHOP, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('a sheet not read', AUDIO, SHOP, 'string.match(item.Name, "^(.-)_x(%d+)$")', 'string.match(item.Name, "^(.-)_y(%d+)$")'),
    ('the takes without slots', AUDIO, SHOP, '("%s@%g"):format(item.SoundId, k * SHEET_SLOT)', '("%s@%g"):format(item.SoundId, 0)'),
    ('old takes alongside', AUDIO, SHOP, 'if not sheeted[event] then', 'if true then'),
    ('the old sand and wrap', AUDIO, SHOP, '{ kineticSandImprint = true, bubblePop = true }', '{ kineticSandImprint = true }'),
    ('a take playing on', AUDIO, SHOP, '(sound :: any).PlaybackRegion = NumberRange.new(from, from + SHEET_SLOT - 0.05)', '(sound :: any).PlaybackRegion = NumberRange.new(from, from + 4)'),
    ('preloaded as nothing', AUDIO, SHOP, 'local asset = string.match(id, "^(.-)@") or id', 'local asset = id'),
    ('a take without its slot', AUDIO, SHOP, '\tAudioService.applyTake(sound, soundId)\n', '\tsound.SoundId = soundId\n'),
    ('no tone', AUDIO, SHOP, '\tAudioService.dress(sound, event)\n', ''),
    ('the oobleck not louder', AUDIO, SHOP, 'ooblSquelch = { gain = 1.5,', 'ooblSquelch = { gain = 1,'),
    ('the solid chocolate without its event', MATS, SHOP, 'sfxEvent = "chocolateChunk"', 'sfxEvent = "chocolateSnap"'),
    ('the jellyfish without its event', MATS, SHOP, 'sfxEvent = "jellyBounce"', 'sfxEvent = "slimeBoing"'),
    ('the wrap faster than a footfall', MATS, SHOP, 'takes (audio/gen_sheet_sfx.py) each lands as the foot does.\n\t\tsfxMinGap = 0.2,', 'takes (audio/gen_sheet_sfx.py) each lands as the foot does.\n\t\tsfxMinGap = 0.1,'),
    ("a step from the sheet's start", STEPS, SHOP, 'audio.applyTake(s, library[math.random(1, #library)])', 's.SoundId = library[math.random(1, #library)]'),
    ('the chocolate a tone', SHEETGEN, SHOP, '    crumbs = {1: 5, 2: 6, 3: 14, 4: 7}[take]\n', '    layers.append((0.0, 0.3, np.sin(phase(1800, d))))\n    crumbs = {1: 5, 2: 6, 3: 14, 4: 7}[take]\n'),
    ('a name never declared', AUDIO, PARSE, '\tlocal from = tonumber(start) :: number\n', '\tlocal from = tonumber(starts) :: number\n'),
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
