"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 68: the story's reward. Not the catalogue's bonus; no ribbon; paid without a word; given elsewhere; to a last
level not walked, or to someone who joined at the end; read after the place is put back; the ribbon sold, or priced
too; earned by nothing; no bonus; the ribbon's tile and press; the bonus pill on the run's; the self-test not looking;
a new way for tokens to go up.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
CAT = S / "Shared/ShopCatalog.lua"
ECON = S / "Server/Services/EconomyService.lua"
BOOT = S / "Server/Bootstrap.server.lua"
SHOPC = S / "Client/Services/ShopService.lua"
CHECK, PARSE = "check_shop.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (CHECK, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ("not the catalogue's bonus", ECON, CHECK, "local amount = ShopCatalog.storyReward(hardcore, double)", "local amount = 1000"),
    ("no ribbon", ECON, CHECK, '\t\tif item.earn == "story" and not profile.Data.Owned[item.id] then\n\t\t\tprofile.Data.Owned[item.id] = true\n',
     '\t\tif item.earn == "story" and not profile.Data.Owned[item.id] then\n'),
    ("paid without a word", ECON, CHECK, "earnedRemote:FireClient(player, amount, { story = true,", "earnedRemote:FireClient(player, amount, { tale = true,"),
    ("given elsewhere", ECON, CHECK, "\tpush(player)\n\tdress(player)\n\tstepGear(player)\n\ttellLevels()\n",
     "\tpush(player)\n\tdress(player)\n\tstepGear(player)\n\ttellLevels()\n\tEconomyService.finishStory(player, true)\n"),
    ("a last level not walked", BOOT, CHECK, "if walked and reached >= of and EconomyService and EconomyService.finishStory then",
     "if reached >= of and EconomyService and EconomyService.finishStory then"),
    ("joined at the end", BOOT, CHECK, "if walked and reached >= of and EconomyService and EconomyService.finishStory then",
     "if walked and EconomyService and EconomyService.finishStory then"),
    ("read after the place is put back", BOOT, CHECK, "\t\t\tlocal reached = 0\n\t\t\tif EconomyService and EconomyService.storyAt then\n",
     "\t\t\tlocal reached = 4\n\t\t\tif false then\n"),
    ("the ribbon sold", ECON, CHECK, '\tif action == "buy" and item.earn then\n\t\treturn answer(player, false, "earned")\n\tend\n', ""),
    ("the ribbon priced too", CAT, CHECK, '\t\tearn = "story", colour = rgb(58, 150, 88)', '\t\tearn = "story", price = 10, colour = rgb(58, 150, 88)'),
    ("earned by nothing", CAT, CHECK, '\t\tearn = "story", colour = rgb(58, 150, 88)', '\t\tearn = "luck", colour = rgb(58, 150, 88)'),
    ("no bonus", CAT, CHECK, "\tSTORY = 150, -- finishing the story", "\tSTORIES = 150, -- finishing the story"),
    ("the ribbon's tile", SHOPC, CHECK, 'fill, edge, ink, words = LOOK.soon, LOOK.soonEdge, LOOK.soonInk, "Finish the story"',
     'fill, edge, ink, words = LOOK.soon, LOOK.soonEdge, LOOK.soonInk, "?"'),
    ("the ribbon's press", SHOPC, CHECK, '\t\ttoast("Finish the story to get " .. item.name .. ".")\n\t\treturn\n', ""),
    ("the bonus on the run's pay", SHOPC, CHECK, "{ Position = UDim2.new(0.5, 0, 1, if story then -92 else -28) }",
     "{ Position = UDim2.new(0.5, 0, 1, -28) }"),
    ("the self-test not looking", ECON, CHECK, 'check("the green ribbon is never sold", result.ok == false and result.reason == "earned",',
     'check("the green ribbon is never sold", true,'),
    ("a new way for tokens to go up", ECON, CHECK, "\tprofile.Data.Earned += amount\n\tlogEconomy(player, true, amount, Enum.AnalyticsEconomyTransactionType.Gameplay.Name, \"Story\")\n",
     "\tprofile.Data.Earned += amount\n\tprofile.Data.Tokens += 5\n\tlogEconomy(player, true, amount, Enum.AnalyticsEconomyTransactionType.Gameplay.Name, \"Story\")\n"),
    ("a name never declared", ECON, PARSE, "local amount = ShopCatalog.storyReward(hardcore, double)", "local amount = ShopCatalog.storyReward(hardcore, dubble)"),
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
