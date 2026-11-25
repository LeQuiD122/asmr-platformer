"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 166: the camera, everywhere. The lobby zooming again; held at its distance in a run only; a zoom set
somewhere else in the game.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
CBOOT = S / "Client/Bootstrap.client.lua"
VIEWC = S / "Client/Services/ViewModeService.lua"
STORY = "check_story.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (STORY,):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('the lobby zooming again', VIEWC, STORY, '\t\tplayer.CameraMaxZoomDistance = THIRD_DISTANCE\n\t\tplayer.CameraMinZoomDistance = THIRD_DISTANCE\n\tend', '\t\tplayer.CameraMaxZoomDistance = 36\n\t\tplayer.CameraMinZoomDistance = THIRD_DISTANCE\n\tend'),
    ('held at its distance in a run only', VIEWC, STORY, '\telse\n\t\tplayer.CameraMode = Enum.CameraMode.Classic\n\t\tplayer.CameraMaxZoomDistance = THIRD_DISTANCE', '\telseif Players.LocalPlayer:GetAttribute("InLevel") ~= nil then\n\t\tplayer.CameraMode = Enum.CameraMode.Classic\n\t\tplayer.CameraMaxZoomDistance = THIRD_DISTANCE'),
    ('a zoom set somewhere else', CBOOT, STORY, '\tif camera and camera.CameraType == Enum.CameraType.Custom then\n\t\tlaunchKick.base', '\tPlayers.LocalPlayer.CameraMaxZoomDistance = 40\n\tif camera and camera.CameraType == Enum.CameraType.Custom then\n\t\tlaunchKick.base'),
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
