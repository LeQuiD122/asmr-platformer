"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 38: a readable Output. A step that runs every frame saying its error every frame (emotes, onboarding,
footsteps, the view, the lava), or saying it every time anyway; a failed leaderboard read tried again, and
warned about, on every redraw.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
C = S / "Client/Services"
LEAD = S / "Server/Services/LeaderboardService.lua"
DEVICES, HUBCHECK, PARSE = "check_devices.py", "check_hub.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (DEVICES, HUBCHECK, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ("the emotes every frame", C / "EmoteService.lua", DEVICES, 'warnOnce("EmoteService: " .. tostring(err))',
     'warn("EmoteService: " .. tostring(err))'),
    ("the onboarding four times a second", C / "OnboardingService.lua", DEVICES,
     'warnOnce("OnboardingService: " .. tostring(err))', 'warn("OnboardingService: " .. tostring(err))'),
    ("the footsteps every frame", C / "StepService.lua", DEVICES, 'warnOnce("StepService: " .. tostring(err))',
     'warn("StepService: " .. tostring(err))'),
    ("the view every frame", C / "ViewModeService.lua", DEVICES, 'warnOnce("ViewModeService: " .. tostring(err))',
     'warn("ViewModeService: " .. tostring(err))'),
    ("the lava every frame", C / "DeformationRenderer.lua", DEVICES,
     'warnOnce("DeformationRenderer: the lava\'s life failed: " .. tostring(err))',
     'warn("DeformationRenderer: the lava\'s life failed: " .. tostring(err))'),
    ("once that is every time", C / "StepService.lua", DEVICES, "if not warnedOnce[text] then\n\t\twarnedOnce[text] = true",
     "if true then\n\t\twarnedOnce[text] = true"),
    ("a failed read tried every redraw", LEAD, HUBCHECK, "if failed and os.clock() - failed < RETRY then", "if false then"),
    ("a failed read warned every redraw", LEAD, HUBCHECK, "if not saidAt[key] or os.clock() - saidAt[key] > 60 then",
     "if true then"),
    ("a name never declared", LEAD, PARSE, "local failed = failedAt[key]", "local failed = failedAt[kee]"),
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
