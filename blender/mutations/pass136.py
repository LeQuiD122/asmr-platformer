"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 136, from your test: the lobby's postcards. Blank windows; a level with no picture of its place; a locked
level's picture as bright as an open one.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
HUBS = S / "Server/Services/HubService.lua"
HUB = "check_hub.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (HUB,):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('blank windows', HUBS, HUB, 'postcard(window, level.backdrop or "none", look)', 'local _ = look'),
    ('a level with no picture', HUBS, HUB, 'elseif backdrop == "sunkenCity" then', 'elseif backdrop == "sunken" then'),
    ('a locked picture as bright', HUBS, HUB, 'veil.BackgroundTransparency = if open then 1 else 0.5', 'veil.BackgroundTransparency = 1'),
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
