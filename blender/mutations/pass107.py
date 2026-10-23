"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 107: trails as thin strands, auras with rings. A trail wide again; a strand moving by a motion the client
does not know; a trail with no strands; a wide strand that is not faint; a trail too tall; the strands never moved, or
found and left where they are; the motion never told to the screens; a strand not tapering; an aura's ring never
placed, too many in one, its limit loose, left behind when the aura changes, or not at its wearer's feet; a name
never declared.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
CAT = S / "Shared/ShopCatalog.lua"
COSM = S / "Client/Services/CosmeticsClient.lua"
SHOP, PARSE = "check_shop.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (SHOP, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('a trail wide again', CAT, SHOP, 'width = 0.22, life = 0.85', 'width = 1, life = 0.85'),
    ('a motion the client does not know', CAT, SHOP, 'motion = "bob", radius = 0.22', 'motion = "sag", radius = 0.22'),
    ('a trail with no strands', CAT, SHOP, 'strands = { { at = Vector3.new(0, 0.2, 0), motion = "flutter", radius = 0.55, speed = 4 } } },', 'strands = {} },'),
    ('a wide strand not faint', CAT, SHOP, 'width = 0.7, fade = 0.6', 'width = 0.7, fade = 0.2'),
    ('a trail too tall', CAT, SHOP, 'motion = "bounce", radius = 0.7, speed = 5 },', 'motion = "bounce", radius = 1.7, speed = 5 },'),
    ('the strands never moved', COSM, SHOP, '\t\t\tmoveStrands(w, root, now)\n', '\t\t\tlocal _ = moveStrands\n'),
    ('found and left where they are', COSM, SHOP, 's.top.Position = centre + Vector3.new(0, s.half, 0)', 's.top.Position = s.top.Position'),
    ('the motion never told', CAT, SHOP, 'top:SetAttribute("StrandMotion", strand.motion)', 'top:SetAttribute("StrandMotions", strand.motion)'),
    ('a strand not tapering', CAT, SHOP, 'band.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) })', 'band.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 1) })'),
    ('a ring never placed', COSM, SHOP, 'if motion == "ring" or motion == "halo" then', 'if motion == "rings" then'),
    ('too many in a ring', CAT, SHOP, 'ring = { count = 12, radius = 1.5,', 'ring = { count = 14, radius = 1.5,'),
    ("a ring's limit loose", COSM, SHOP, 'local RING_MAX = 12 ', 'local RING_MAX = 40 '),
    ('a ring left when the aura changes', COSM, SHOP, 'for _, one in ipairs(w.ringSet) do\n\t\t\t\t\tone.life = 0', 'for _, one in ipairs({}) do\n\t\t\t\t\tone.life = 0'),
    ("a ring not at its wearer's feet", COSM, SHOP, 'now, (w :: Wearer).drop)', 'now, 3)'),
    ('a name never declared', COSM, PARSE, 'return s.at + Vector3.new(tri * r,', 'return s.at + Vector3.new(trii * r,'),
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
