"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 94: the butter sticks, from the test. A step sinking a stick deeper than it stands over its grooves; the
wave of dips across the chunk back; the wrapper not driven, or not going down with the butter, not holding its dent,
or never coming back up; a bed with no wave sending one anyway; a name never declared.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
RENDER = S / "Client/Services/DeformationRenderer.lua"
STORY, PARSE = "check_story.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (STORY, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('deeper than the stick stands', RENDER, STORY, 'BUTTER_STICK.PRESS = 0.9', 'BUTTER_STICK.PRESS = 1.62'),
    ('the wave of dips back', RENDER, STORY, 'BUTTER_STICK.RIPPLE = nil', 'BUTTER_STICK.RIPPLE = RippleProfiles.ButterStick'),
    ('the wrapper left up', RENDER, STORY, 'BUTTER_STICK.SHELL = true', 'BUTTER_STICK.SHELL = false'),
    ('the wrapper not going down', RENDER, STORY, 'driveShell(tile, down, -profile.PRESS, false)', 'driveShell(tile, down, 0, false)'),
    ('the wrapper not holding the dent', RENDER, STORY, 'driveShell(tile, keep, -profile.PRESS * profile.RESIDUAL_FRACTION, false)', 'driveShell(tile, keep, 0, false)'),
    ('the wrapper never back up', RENDER, STORY, '\t\t\t\tdriveShell(tile, back, 0, false)\n', '\t\t\t\tlocal _ = back\n'),
    ('a bed with no wave sending one', RENDER, STORY, 'if bone and onSlab and profile.RIPPLE then', 'if bone and onSlab then'),
    ('a name never declared', RENDER, PARSE, 'driveShell(tile, down, -profile.PRESS, false)', 'driveShell(tile, downs, -profile.PRESS, false)'),
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
