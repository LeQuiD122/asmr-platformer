"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 127, from your test: the Sky Pools' song, and you in the slide's shots. A kept sound cut at twenty seconds;
no song, or not landing with you, or two last chords; SONG_LANDS off the song; the song not looked for; nobody in the
cloud, the cloud left thin or thinned away, the camera far off in it; the landing far off again.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
BOOT = S / "Server/Bootstrap.server.lua"
CINEMA = S / "Client/Services/Cinema.lua"
SKY = S / "Client/Services/SkyPoolsClient.lua"
HUB, SHOTS, SKYCHECK, STORY = "check_hub.py", "check_shots.py", "check_skypools.py", "check_story.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (HUB, SHOTS, SKYCHECK, STORY):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('kept sounds cut at twenty', CINEMA, STORY, 'game:GetService("Debris"):AddItem(made, 120)', 'game:GetService("Debris"):AddItem(made, 20)'),
    ('no song', SKY, STORY, 'scene.song = Cinema.sound("PoolsSong", 0.5, { keep = true, fadeIn = 1.5 })', 'scene.song = nil'),
    ('the song not landing with you', SKY, STORY, 'song.TimePosition = math.max(0, SONG_LANDS - landsIn)', 'song.TimePosition = 0'),
    ('two last chords', SKY, STORY, 'if not (scene.song and scene.song.Parent) then', 'if true then'),
    ('SONG_LANDS off the song', SKY, STORY, 'local SONG_LANDS = 36', 'local SONG_LANDS = 30'),
    ('the song not looked for', BOOT, HUB, '"MorningChord", "PoolsSong", "BarStrike", "BrickBurst" }', '"MorningChord", "BarStrike", "BrickBurst" }'),
    ('nobody in the cloud', SKY, SKYCHECK, 'scene.thin({ here, here:Lerp(marks.outAt, 0.5), marks.outAt })', 'scene.thin(nil)'),
    ('the cloud left thin', SKY, SKYCHECK, '\t\tif scene.shot == "mist" then\n\t\t\tscene.thin(nil)', '\t\tif scene.shot == "never" then\n\t\t\tscene.thin(nil)'),
    ('the cloud thinned away', SKY, SKYCHECK, 'local MIST_THIN = 0.72', 'local MIST_THIN = 0.98'),
    ('the camera far off in the cloud', SKY, SKYCHECK, 'here - flat * 8 + out * 2.5 + Vector3.new(0, 3.5, 0)', 'here - flat * 18 + out * 2.5 + Vector3.new(0, 3.5, 0)'),
    ('the landing far off again', SKY, SHOTS, 'landing + away * (14 - 4 * k) + side * 4', 'landing + away * (40 - 4 * k) + side * 4'),
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
