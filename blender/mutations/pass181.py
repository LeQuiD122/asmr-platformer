"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 181: no white columns. A ribbon with no greatest length, a teleport drawn, the haze run to the water, near-opaque, or its end left behind.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
COSMETIC = S / "Client/Services/CosmeticsClient.lua"
SEARCH = S / "Client/Services/SearchlightClient.lua"
SHOP = S / "Shared/ShopCatalog.lua"
LETGO = "check_letgo.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (LETGO,):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('a ribbon of any length', SHOP, LETGO, 'band.MaxLength = 16', 'band.MaxLength = 0'),
    ('a teleport drawn', COSMETIC, LETGO, 'child:Clear()', 'child.Enabled = child.Enabled'),
    ('the haze to the water', SEARCH, LETGO, 'beam.Attachment1 = haze', 'beam.Attachment1 = far'),
    ('the haze near-opaque', SEARCH, LETGO, 'local near = 0.88 - 0.06 * rain', 'local near = 0.72 - 0.06 * rain'),
    ("the haze's end left behind", SEARCH, LETGO, 'hazeEnd.Position = Vector3.new(0, 0, -math.min(long, HAZE_LONGEST))', 'hazeEnd.Position = Vector3.new(0, 0, -long)'),
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
