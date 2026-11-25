"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 140: a scene always lets go. A scene with no end, or its time never kept; an ending cut short, a stuck
moment held too long; a new character left in the old one's scene; Reset in the middle of a scene, or never given back;
the journal or the choices left up over one, or nothing put away as it starts; the lens marks or the best times over
its picture; the screens never back after it.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
CINEMA = S / "Client/Services/Cinema.lua"
TALK = S / "Client/Services/TalkClient.lua"
UIS = S / "Client/Services/UIService.lua"
POLISH = "check_polish.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (POLISH,):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('a scene with no end', CINEMA, POLISH, 'if current and not current.overdue and os.clock() - current.began > current.most then', 'if false then'),
    ('the time never kept', CINEMA, POLISH, 'RunService:BindToRenderStep(SHOW, Enum.RenderPriority.Camera.Value + 2, sceneStep)', 'RunService:BindToRenderStep(SHOW, Enum.RenderPriority.Camera.Value + 2, showYou)'),
    ('an ending cut short', CINEMA, POLISH, 'local MOST = { ending = 150,', 'local MOST = { ending = 60,'),
    ('a stuck moment held too long', CINEMA, POLISH, 'moment = 45 }', 'moment = 200 }'),
    ('a new character in an old scene', CINEMA, POLISH, 'me.CharacterAdded:Connect(function()\n\t\tif live then\n\t\t\tleft()', 'me.CharacterAdded:Connect(function()\n\t\tif false then\n\t\t\tleft()'),
    ('reset in the middle of a scene', CINEMA, POLISH, '\tallowReset(false)\n', ''),
    ('reset never given back', CINEMA, POLISH, '\tallowReset(true)\n', ''),
    ('the journal left open over a scene', CINEMA, POLISH, 'besideDo("JournalService", function(m)', 'besideDo("Journal", function(m)'),
    ('the choices left up over a scene', TALK, POLISH, 'function TalkClient.dismiss()\n\thide()', 'function TalkClient.dismiss()\n\tlocal _ = hide'),
    ('nothing put away as a scene starts', CINEMA, POLISH, '\t-- What is open put away first, before the controls are taken: the shop gives them back as it closes.\n\tcloseOverlays()\n', ''),
    ('lens marks over the picture', CINEMA, POLISH, '{ "MaterialLensMarks", "Hints" }', '{ "Hints" }'),
    ('the best times over an ending', UIS, POLISH, 'return player:GetAttribute("InLevel") ~= nil and not sceneHeld', 'return player:GetAttribute("InLevel") ~= nil'),
    ('the screens never back', CINEMA, POLISH, '\tallowReset(true)\n\tquietScreens(false)', '\tallowReset(true)'),
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
