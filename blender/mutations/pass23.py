"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 23: the first five minutes. A welcome that comes back every visit or never goes away, a guide that
points at nothing, a material with no hint, a hint line that takes presses, a note that pays, the funnel
broken, and the welcome on every device (the safe area, thumb-sized buttons, a controller's way out).
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
ONB = S / "Client/Services/OnboardingService.lua"
ECON = S / "Server/Services/EconomyService.lua"
BOOT = S / "Server/Bootstrap.server.lua"
CBOOT = S / "Client/Bootstrap.client.lua"
VIEW = S / "Client/Services/ViewModeService.lua"
CHECK, PARSE = "check_shop.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (CHECK, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    # The welcome.
    ("the welcome every visit", ONB, CHECK, "if not data.welcomed and not state.welcomeShown then",
     "if not state.welcomeShown then"),
    ("a finished welcome never noted", ONB, CHECK, '\tnote("welcomed")\n', "\n"),
    ("a skipped guide coming back", ONB, CHECK, '\telse\n\t\tnote("guided")\n\tend\nend',
     "\tend\nend"),
    ("no way out on a controller", ONB, CHECK, "Enum.KeyCode.Escape, Enum.KeyCode.ButtonB", "Enum.KeyCode.Escape"),
    ("frozen behind the welcome", ONB, CHECK, "\tfreeze(false)\n", "\n"),
    ("tiny welcome buttons", ONB, CHECK, "local height = kit.MIN_TOUCH + 9", "local height = 24"),
    ("no touch controls on a phone", ONB, CHECK, "UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled",
     "false"),
    # The guide and the hints.
    ("a guide to a pad that is not there", ONB, CHECK, 'pad = "OptionPad_length_short"', 'pad = "OptionPad_length_tiny"'),
    ("a material with no hint", ONB, CHECK, '\tNeedoh = "Needoh: stand still to squeeze it, then jump for a much bigger jump.",\n',
     ""),
    ("a hint with a dash", ONB, CHECK, "Honey slows you down and keeps your footprints. Keep moving.",
     "Honey slows you down -- keep moving."),
    ("a hint line that takes presses", ONB, CHECK, "pill.Active = false", "pill.Active = true"),
    ("hints in the lobby", ONB, CHECK, "if inLobby() or state.welcomeOpen then", "if state.welcomeOpen then"),
    ("hints every run", ONB, CHECK, 'note("hinted", name)', "note(\"seen\", name)"),
    # The server.
    ("a note that pays", ECON, CHECK, "\t\tdata.Guided = true\n", "\t\tdata.Guided = true\n\t\tdata.Tokens += 50\n"),
    ("any note accepted", ECON, CHECK, 'if typeof(what) ~= "string" or not NOTES[what] then', 'if typeof(what) ~= "string" then'),
    ("a stream of notes", ECON, CHECK, "if window.count > 8 then", "if window.count > 8000 then"),
    ("the funnel missing a step", ECON, CHECK, 'funnel(player, 6, "First run finished")', 'print("First run finished")'),
    ("no Onboarding remote", BOOT, CHECK, 'ensureRemoteEvent(remoteEventsFolder, "Onboarding")', 'ensureRemoteEvent(remoteEventsFolder, "Onboard")'),
    ("onboarding never started", CBOOT, CHECK, ', "OnboardingService",\n\t"StepService"', ',\n\t"StepService"'),
    ("the cursor locked over the welcome", VIEW, CHECK, 'playerGui:FindFirstChild("Welcome")', 'playerGui:FindFirstChild("Welcom")'),
    # The code still reads.
    ("a name never declared in the hints", ONB, PARSE, "\tline(HINTS[name] :: string, HINT_SECONDS)",
     "\tline(HINTS[name] :: string, HINT_SECOND)"),
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
