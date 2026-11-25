"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 141: the small things. The scenes' sounds fetched late, or nothing but the materials' fetched; the game's
own sounds destroyed once fetched; a Reset in Chill back to the start, or a jump cut; a Reset in Hardcore free; a
Reset after the finish taken as a fall; five seconds in pieces.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
AUDIO = S / "Client/Services/AudioService.lua"
BOOT = S / "Server/Bootstrap.server.lua"
POLISH = "check_polish.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (POLISH,):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ("the scenes' sounds fetched late", AUDIO, POLISH, 'local PRELOAD_FOLDERS = { "LobbySounds", "ShopSounds", "StorySounds", "AmbienceSounds", "WaterSounds" }', 'local PRELOAD_FOLDERS = { "LobbySounds", "ShopSounds" }'),
    ("nothing but the materials' fetched", AUDIO, POLISH, 'ContentProvider:PreloadAsync(fetch)', 'ContentProvider:PreloadAsync(probes)'),
    ("the game's own sounds destroyed", AUDIO, POLISH, 'for _, probe in ipairs(probes) do\n\t\tprobe:Destroy()', 'for _, probe in ipairs(fetch) do\n\t\tprobe:Destroy()'),
    ('a Chill reset back to the start', BOOT, POLISH, '\t\t\t\tlocal at = recoverAtCheckpoint(player)\n', '\t\t\t\tlocal at = nil\n'),
    ('a Chill reset a jump cut', BOOT, POLISH, '\t\t\t\t\thrp.CFrame = CFrame.new(at)\n\t\t\t\t\tScreenFade:FireClient(player, { dip = true, time = DIP.fall })', '\t\t\t\t\thrp.CFrame = CFrame.new(at)'),
    ('a Hardcore reset free', BOOT, POLISH, 'and sendBackToStart then\n\t\t\t\t\tsendBackToStart(player)', 'and sendBackToStart then\n\t\t\t\t\tlocal _ = player'),
    ('a reset after the finish taken as a fall', BOOT, POLISH, 'if inRunNow and state and not state.hasCompletedLevel then', 'if inRunNow and state then'),
    ('five seconds in pieces', BOOT, POLISH, 'Players.RespawnTime = 1.5', 'Players.RespawnTime = 5'),
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
