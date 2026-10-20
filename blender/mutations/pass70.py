"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 70: the hidden caches. A level without one; a dash in the words; hanging in the air; nothing to catch the eye;
showing again once taken; paying nothing; no journal line; never put in a nook, or left out of it; nowhere when no nook
fits; paying every time; not kept; not the catalogue's amount; paid without a word; no place in a new save; no bonus
in the catalogue; the self-test not finding one; the pill not saying.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
INTER = S / "Server/Services/Interactables.lua"
STORYS = S / "Server/Services/StoryService.lua"
ECON = S / "Server/Services/EconomyService.lua"
CAT = S / "Shared/ShopCatalog.lua"
SHOPC = S / "Client/Services/ShopService.lua"
STORY, SHOP, PARSE = "check_story.py", "check_shop.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (STORY, SHOP, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ("a level without one", INTER, STORY, '\t[4] = { title = "Tea money",', '\t[9] = { title = "Tea money",'),
    ("a dash in the words", INTER, STORY, '"A tea tin, warm from the boilers.', '"A tea tin -- warm from the boilers.'),
    ("hanging in the air", INTER, STORY, "cf * CFrame.new(0, spec.size.Y / 2, 0)", "cf * CFrame.new(0, spec.size.Y * 2, 0)"),
    ("nothing to catch the eye", INTER, STORY, "\tInteractables.glint(box, Color3.fromRGB(255, 226, 150))\n", ""),
    ("showing again once taken", INTER, STORY, '\tInteractables.mark(box, "note:" .. spec.title)\n', ""),
    ("paying nothing", INTER, STORY, "\t\t\tpcall(save.foundCache, player, levelId)\n", ""),
    ("no journal line", INTER, STORY, '\t\tInteractables.take(player, { title = spec.title, body = spec.body }, box, "note")\n', ""),
    ("never in a nook", STORYS, STORY, "local hidden = nookNear(0.66)", "local hidden = nil"),
    ("left out of its nook", STORYS, STORY, "\t\t\tpcall(nookCache, folder, hidden, level.levelId)\n", ""),
    ("nowhere when no nook fits", STORYS, STORY, "\t\t\t\tpcall(Interactables.cache, folder, besideRoute(cap, -1, 1.2), level.levelId)\n", ""),
    ("paying every time", ECON, SHOP, "\tif data.Caches[key] then\n\t\treturn false\n\tend\n", ""),
    ("not kept", ECON, SHOP, "\tdata.Caches[key] = true\n", ""),
    ("not the catalogue's amount", ECON, SHOP, "\tlocal amount = ShopCatalog.REWARD.CACHE\n", "\tlocal amount = 250\n"),
    ("paid without a word", ECON, SHOP, "earnedRemote:FireClient(player, amount, { cache = true })", "earnedRemote:FireClient(player, amount, {})"),
    ("no place in a new save", ECON, SHOP, "\tCaches = {} :: { [string]: boolean },", "\tCache = {} :: { [string]: boolean },"),
    ("no bonus in the catalogue", CAT, SHOP, "\tCACHE = 25,", "\tCACHED = 25,"),
    ("the self-test not finding one", ECON, SHOP, 'check("a hidden cache pays once a save", cacheFirst == true and cacheAgain == false',
     'check("a hidden cache pays once a save", true'),
    ("the pill not saying", SHOPC, SHOP, '\t\t\ttable.insert(reasons, "Hidden cache")\n', ""),
    ("a name never declared", INTER, PARSE, "\tlocal spec = CACHES[levelId]\n", "\tlocal spec = CACHE[levelId]\n"),
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
