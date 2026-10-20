"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 101: the lobby's sounds where they are, and three fixes. The fountain heard from across the promenade;
a press heard from nowhere, sounding again and again, a locked pad sounding open, the presses never listened for; a
press or the lever on slots their sheets do not have; the lever heard from elsewhere, or when nobody pulled it; Sky
Pools' falls a sheet to the clouds again, or not thinning; the bubble wrap's pops unseen again; the soap's generated
takes mixed in with your own.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
AMB = S / "Client/Services/AmbienceService.lua"
AUDIO = S / "Client/Services/AudioService.lua"
LEVER = S / "Client/Services/HubLeverService.lua"
RENDER = S / "Client/Services/DeformationRenderer.lua"
SKYS = S / "Server/Services/SkyPoolsService.lua"
AUDIOCHECK, SKYCHECK, STORY = "check_audio.py", "check_skypools.py", "check_story.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (AUDIOCHECK, SKYCHECK, STORY):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('the fountain from across the promenade', AMB, AUDIOCHECK, 'lobbyAt(s, fountain, 0.55, 1, 6, 55, 1e6)', 'lobbyAt(s, fountain, 0.55, 1, 10, 900, 1e6)'),
    ('a press from nowhere', AMB, AUDIOCHECK, 'lobbyAt(take, part.Position + Vector3.new(0, 1, 0), spec.volume, pitch, 6, 60, spec.slot / pitch)', 'lobbyAt(take, nil, spec.volume, pitch, 6, 60, spec.slot / pitch)'),
    ('a press again and again', AMB, AUDIOCHECK, 'if standing and standing ~= before then', 'if standing then'),
    ('a locked pad sounding open', AMB, AUDIOCHECK, 'return if part:GetAttribute("Locked") then "locked" else "pad"', 'return "pad"'),
    ('the presses never listened for', AMB, AUDIOCHECK, 'local ok, err = pcall(scanPresses)', 'local ok, err = true, nil'),
    ('a press on the wrong slots', AMB, AUDIOCHECK, 'pad = { sheet = "PadPress_x4", slot = 1.4,', 'pad = { sheet = "PadPress_x4", slot = 1.2,'),
    ('the lever on the wrong slots', LEVER, AUDIOCHECK, 'hardcore = { sheet = "LeverHardcore_x2", slot = 3.2,', 'hardcore = { sheet = "LeverHardcore_x2", slot = 3.0,'),
    ('the lever heard from elsewhere', LEVER, AUDIOCHECK, '\ts.Parent = at\n', '\ts.Parent = SoundService\n'),
    ('the lever when nobody pulled it', LEVER, AUDIOCHECK, 'local yours = os.clock() - pulledAt < 4', 'local yours = true'),
    ("a fall's sheet to the clouds", SKYS, SKYCHECK, 'local reach = math.min(height, VEIL_REACH)', 'local reach = height'),
    ("a long fall's sheet not thinning", SKYS, SKYCHECK, 'local alpha = veil.alpha + (1 - veil.alpha) * thin * 0.92', 'local alpha = veil.alpha'),
    ('the pops unseen', RENDER, STORY, 'flecks:Emit(7)', 'flecks:Emit(0)'),
    ('the pockets barely swelling', RENDER, STORY, 'POCKET.SWELL = 0.4', 'POCKET.SWELL = 0.26'),
    ("the soap's takes mixed in", AUDIO, AUDIOCHECK, 'if OWN_ONLY[event] and #list > 0 then', 'if false then'),
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
