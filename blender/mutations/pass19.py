"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 19: third person as the game's view, first person only through the lobby's seaside viewer and never
on the screen, Ctrl toggling the cursor, prompts in the game's own style, the slime's camera kick, and
the Sky Pools' cloud sea moving.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
VIEW = S / "Client/Services/ViewModeService.lua"
SUNK = S / "Server/Services/SunkenCityService.lua"
CBOOT = S / "Client/Bootstrap.client.lua"
HUB = S / "Server/Services/HubService.lua"
SKY = S / "Server/Services/SkyPoolsService.lua"
STORY, SKYCHECK, PARSE = "check_story.py", "check_skypools.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (STORY, SKYCHECK, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    # The view.
    ("a viewer that does nothing", VIEW, STORY, 'if prompt.Name == "ViewScopePrompt" and who == Players.LocalPlayer then',
     'if prompt.Name == "ViewScope" and who == Players.LocalPlayer then'),
    ("no viewer in the lobby", HUB, STORY, 'scope.Name = "ViewScope"', 'scope.Name = "Telescope"'),
    ("a switch back on the screen", VIEW, STORY, "\tui.word = word\n",
     "\tui.word = word\n\tlocal switch = Instance.new(\"TextButton\")\n\tswitch.Parent = screen\n"),
    ("Ctrl doing nothing", VIEW, STORY, "input.KeyCode == Enum.KeyCode.LeftControl or", "input.KeyCode == Enum.KeyCode.F13 or"),
    ("a locked cursor that wanders", VIEW, STORY, "\t\tUserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter\n",
     "\t\tlocal _ = Enum.MouseBehavior.LockCenter\n"),
    ("the cursor locked over the journal", VIEW, STORY, "\tlocal menu = menuOpen()\n", "\tlocal menu = false\n"),
    ("turned while riding", VIEW, STORY, "not humanoid.Sit and not humanoid.PlatformStand and not root.Anchored",
     "not root.Anchored"),
    # The prompts are Roblox's own (twentieth pass).
    ("a restyled prompt back", VIEW, STORY, "\tui.word = word\n", "\tui.word = word\n\tlocal _ = Enum.ProximityPromptStyle.Custom\n"),
    # Back from first person into a proper third person view.
    ("left inside your head", VIEW, STORY, "\t\tsettleThird()\n\telse", "\t\tapply()\n\telse"),
    ("first person by a scroll", VIEW, STORY, "player.CameraMinZoomDistance = LOBBY_NEAR", "player.CameraMinZoomDistance = 0.5"),
    # The drain's cries.
    ("cries in a warning sign's letters", SUNK, STORY, "piece.Font = if quiet then Enum.Font.Kalam else Enum.Font.PermanentMarker",
     "piece.Font = Enum.Font.GothamBlack"),
    ("cries too fast to read", SUNK, STORY, "task.wait(if quiet then 2.8 else 1.7)", "task.wait(if quiet then 0.85 else 0.85)"),
    # The slime's kick.
    ("a kick that fights a scene", CBOOT, STORY, "if camera and camera.CameraType == Enum.CameraType.Custom then",
     "if camera then"),
    # The clouds.
    ("a still cloud sea", SKY, SKYCHECK, 'block(folder, "MistBank"', 'block(folder, "MistBanks"'),
    ("mist with no wind", SKY, SKYCHECK, "\t\t\tmist.Acceleration = wind * 0.35\n", "\t\t\tmist.Acceleration = Vector3.zero\n"),
    # The code still reads.
    ("a name never declared in the view", VIEW, PARSE, "\tstate.view = view\n\tstate.free = false\n",
     "\tstate.view = views\n\tstate.free = false\n"),
    ("a block left open in the view", VIEW, PARSE, "\tif view ~= \"first\" and view ~= \"third\" then\n\t\treturn\n\tend\n",
     "\tif view ~= \"first\" and view ~= \"third\" then\n\t\treturn\n"),
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
