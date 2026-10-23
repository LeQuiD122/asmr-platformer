"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 135, from your test: livelier tiles. No sunburst, or it never turning; no sheen, or it never sweeping; a price
you can pay unsaid; the old tiles' animations piling up.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
SHOPC = S / "Client/Services/ShopService.lua"
SHOP = "check_shop.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (SHOP,):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('no sunburst', SHOPC, SHOP, 'rays.Name = "Rays"', 'rays.Name = "Back"'),
    ('the sunbursts still', SHOPC, SHOP, 'table.insert(shop.rays, rays)', 'local _ = rays'),
    ('no sheen', SHOPC, SHOP, 'sheen.Name = "Sheen"', 'sheen.Name = "Gloss"'),
    ('the sheens still', SHOPC, SHOP, 'sheen.grad.Offset = Vector2.new(if p < 1 then -1 + 2 * p else -2, 0)', 'sheen.grad.Offset = Vector2.new(-2, 0)'),
    ('a price you can pay unsaid', SHOPC, SHOP, 'if not item.soon and tokens() >= item.price then', 'if false then'),
    ('the animations piling up', SHOPC, SHOP, '\ttable.clear(shop.rays)\n', '\n'),
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
