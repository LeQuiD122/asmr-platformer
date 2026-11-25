"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 171: his letters. A level with no letter; a letter on a board, not lying; the last signed E. M.; the last
never telling you to sign; the first signed Dad.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
STORYSV = S / "Server/Services/StoryService.lua"
STORY = "check_story.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (STORY,):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('a level with no letter', STORYSV, STORY, '{ title = "A green envelope, 3 of 5", lying = true,', '{ title = "A green envelope, 3", lying = true,'),
    ('a letter on a board, not lying', STORYSV, STORY, '{ title = "A green envelope, 4 of 5", lying = true,', '{ title = "A green envelope, 4 of 5",'),
    ('the last signed E. M.', STORYSV, STORY, 'Then come back up. I could not.\\n\\nDad" },', 'Then come back up. I could not.\\n\\nE. M." },'),
    ('the last never telling you to sign', STORYSV, STORY, 'Sign it. Open "', 'Open "'),
    ('the first signed Dad', STORYSV, STORY, '.. "\\n\\nE. M." },', '.. "\\n\\nDad" },'),
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
