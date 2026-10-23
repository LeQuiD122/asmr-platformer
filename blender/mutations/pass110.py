"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 110: the cookie. Not built of crumbs; chips in every layer, too many, too few, too tall, or not dark; the
chunk not one round cookie; its outline not a shape the plan check walks, or pinched where it meets its neighbours;
lasting as long as soap, slippery, or with soap's sound; its crunch not looked for; not cracking, its cracks not
running on, or not crumbling; crumbling at soap's pace, with soap's dust, crumbs or rising flakes, or not knowing what
it is; missing from City Shore, Sky Pools or the sandbox's front; the sandbox's count wrong; no keepsake, so the
shelf's count is off; the shelf too small; a name never declared.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
BOOT = S / "Server/Bootstrap.server.lua"
BUILDER = S / "Server/ChunkBuilder.server.lua"
KEEPS = S / "Shared/Keepsakes.lua"
LEVELS = S / "Shared/LevelDefinitions.lua"
MATS = S / "Shared/MaterialConfig.lua"
RENDER = S / "Client/Services/DeformationRenderer.lua"
SHAPES = S / "Shared/PlanShapes.lua"
SQUISHS = S / "Server/Services/SquishRoomService.lua"
FORMS, PLAN, SQUISHCHECK, STORY, PARSE = "check_chunk_forms.py", "check_plan_shapes.py", "check_squishroom.py", "check_story.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (FORMS, PLAN, SQUISHCHECK, STORY, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('not built of crumbs', BUILDER, FORMS, '{ Soap = true, Cookie = true }', '{ Soap = true }'),
    ('chips in every layer', BUILDER, FORMS, 'if chips and layer == 1 and (seed * 3 + seed2)', 'if chips and (seed * 3 + seed2)'),
    ('too many chips', BUILDER, FORMS, 'every = 7, proud = 0.12', 'every = 2, proud = 0.12'),
    ('too few chips', BUILDER, FORMS, 'every = 7, proud = 0.12', 'every = 40, proud = 0.12'),
    ('chips too tall', BUILDER, FORMS, 'every = 7, proud = 0.12', 'every = 7, proud = 0.6'),
    ('chips not dark', BUILDER, FORMS, 'Cookie = { colour = Color3.fromRGB(66, 38, 22)', 'Cookie = { colour = Color3.fromRGB(230, 200, 160)'),
    ('not one round cookie', BUILDER, FORMS, 'material = "Cookie", width = 20, length = 20, form = "cookie" }', 'material = "Cookie", width = 20, length = 20 }'),
    ('not a shape the plan check walks', SHAPES, FORMS, '\tcookie = cookie,\n', ''),
    ('pinched where it meets its neighbours', SHAPES, PLAN, 'local rim = 1.06 + 0.03 * math.cos(11 * angle)', 'local rim = 0.97 + 0.03 * math.cos(11 * angle)'),
    ('lasting as long as soap', MATS, FORMS, '\t\tdissolveTime = 1.7,\n\t\tdecayDuration = 8,', '\t\tdissolveTime = 2.4,\n\t\tdecayDuration = 8,'),
    ('slippery', MATS, FORMS, '\t\tdissolveTime = 1.7,\n', '\t\tdissolveTime = 1.7,\n\t\tfrictionOverride = 0.12,\n'),
    ("soap's sound", MATS, FORMS, 'sfxEvent = "cookieCrunch",', 'sfxEvent = "soapCrumble",'),
    ('its crunch not looked for', BOOT, FORMS, '"cookieCrunch_x4", ', ''),
    ('not cracking', RENDER, FORMS, 'Fissure.grow(tile, { from = Fissure.footOf(tile, ctx.who), arms = SOAP.CRACK_ARMS', 'local _ = ({ from = Fissure.footOf(tile, ctx.who), arms = SOAP.CRACK_ARMS'),
    ('its cracks not running on', RENDER, FORMS, '\t\t\tFissure.extend(tile, SOAP.CRACK_STEP, SOAP.CRACK_SPEED)\n', '\t\t\tlocal _ = SOAP.CRACK_STEP\n'),
    ('not crumbling', RENDER, FORMS, '\tEffects.Soap(ctx)\nend', '\tlocal _ = ctx\nend'),
    ("at soap's pace", RENDER, FORMS, 'local own = Materials[SOAP.OF[tile] or "Soap"] or Materials.Soap', 'local own = Materials.Soap'),
    ("soap's dust", RENDER, FORMS, 'local made = MaterialAppearance.Appearances[SOAP.OF[tile] or "Soap"] or MaterialAppearance.Appearances.Soap', 'local made = MaterialAppearance.Appearances.Soap'),
    ("soap's crumbs", RENDER, FORMS, 'frag.Name = (SOAP.OF[tile] or "Soap") .. "Crumb"', 'frag.Name = "SoapCrumb"'),
    ('rising flakes', RENDER, FORMS, 'puff(tile, own.color, 0.16, 4, SOAP.RISE[ctx.material] or 3, 7)', 'puff(tile, own.color, 0.16, 4, 3, 7)'),
    ('not knowing what it is', RENDER, FORMS, '\tSOAP.OF[tile] = ctx.material\n', ''),
    ('missing from City Shore', LEVELS, FORMS, '"R18_SoapRing", "R22_Cookie",', '"R18_SoapRing",'),
    ('missing from Sky Pools', LEVELS, FORMS, '\t\t"R18_SoapRing",\n\t\t"R22_Cookie",\n\t\t"R19_SoapWave",', '\t\t"R18_SoapRing",\n\t\t"R19_SoapWave",'),
    ("missing from the sandbox's front", LEVELS, FORMS, '\t\t"R22_Cookie",\n\t\t"S1_Straight",\n\t\t-- Then the Sunken City', '\t\t"S1_Straight",\n\t\t"S1_Straight",\n\t\t-- Then the Sunken City'),
    ("the sandbox's count wrong", LEVELS, FORMS, '\tminChunks = 87,\n\tmaxChunks = 87,', '\tminChunks = 85,\n\tmaxChunks = 85,'),
    ('no keepsake', KEEPS, STORY, '\tCookie = {\n\t\tthing = "A biscuit from the Promenade Hotel', '\tKookie = {\n\t\tthing = "A biscuit from the Promenade Hotel'),
    ('the shelf too small', SQUISHS, SQUISHCHECK, 'local SHELF_COLUMNS, SHELF_ROWS = 10, 3', 'local SHELF_COLUMNS, SHELF_ROWS = 9, 3'),
    ('a name never declared', RENDER, PARSE, '\tlocal tile = ctx.tile\n\tif ctx.state == "deformed" then\n\t\tif Fissure.has(tile) then', '\tlocal tile = ctx.tile\n\tif ctx.state == "deformed" then\n\t\tif Fissures.has(tile) then'),
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
