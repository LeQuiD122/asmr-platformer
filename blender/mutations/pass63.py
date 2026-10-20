"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 63: Roblox badges. None to set, or one starting set; a badge not made yet asked for; asked on every finish;
never awarded; a refusal unguarded; a level's badge missing, or given for a run too fast to be played; the story's
not given, or the Hardcore one for any story; kept after leaving; given for a last level not walked; the paste
check silent.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
CAT = S / "Shared/ShopCatalog.lua"
ECON = S / "Server/Services/EconomyService.lua"
BOOT = S / "Server/Bootstrap.server.lua"
SHOP, PARSE = "check_shop.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (SHOP, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

LEVEL_BADGE = ("\t-- THE LEVEL'S BADGE (ShopCatalog.BADGES), for a run really played.\n\tlocal badges = ShopCatalog.BADGES\n"
               "\tif levelId ~= nil and type(badges) == \"table\" and type(badges.level) == \"table\" then\n"
               "\t\tEconomyService.awardBadge(player, badges.level[levelId])\n\tend\n")

MUTATIONS = [
    ("none to set", CAT, SHOP, "level = { [1] = 0, [2] = 0, [3] = 0, [4] = 0 },", "level = {},"),
    ("one starting set", CAT, SHOP, "level = { [1] = 0, [2] = 0, [3] = 0, [4] = 0 },", "level = { [1] = 123, [2] = 0, [3] = 0, [4] = 0 },"),
    ("a badge not made asked for", ECON, SHOP, 'if type(badgeId) ~= "number" or badgeId == 0 then', 'if type(badgeId) ~= "number" then'),
    ("asked on every finish", ECON, SHOP, "\tif asked[badgeId] then\n\t\treturn\n\tend\n", ""),
    ("never awarded", ECON, SHOP, "BadgeService:AwardBadge(player.UserId, badgeId)", "print(player.UserId, badgeId)"),
    ("a refusal unguarded", ECON, SHOP,
     "\t\tlocal ok, err = pcall(function()\n\t\t\tBadgeService:AwardBadge(player.UserId, badgeId)\n\t\tend)\n",
     "\t\tBadgeService:AwardBadge(player.UserId, badgeId)\n\t\tlocal ok, err = true, nil\n"),
    ("a level's badge missing", ECON, SHOP, LEVEL_BADGE, ""),
    ("a badge for a run too fast", ECON, SHOP, "\tlocal least = ShopCatalog.REWARD.MIN_SECONDS[run.length]",
     LEVEL_BADGE.replace("\t-- THE LEVEL'S BADGE", "\t-- EARLY BADGE") + "\tlocal least = ShopCatalog.REWARD.MIN_SECONDS[run.length]"),
    ("the story's not given", ECON, SHOP, "\tEconomyService.awardBadge(player, badges.story)\n", ""),
    ("the Hardcore one for any story", ECON, SHOP,
     "\tif wholeHardcore then\n\t\tEconomyService.awardBadge(player, badges.storyHardcore)\n\tend\n",
     "\tEconomyService.awardBadge(player, badges.storyHardcore)\n"),
    ("kept after leaving", ECON, SHOP, "\tbadgeAsked[player] = nil\n", ""),
    ("for a last level not walked", BOOT, SHOP, "if walked and EconomyService and EconomyService.awardStoryBadges then",
     "if EconomyService and EconomyService.awardStoryBadges then"),
    ("the paste check silent", BOOT, SHOP, 'print("PASTE CHECK: badges not made yet, no id in ShopCatalog.BADGES',
     'print("PASTE CHECK: badges: ShopCatalog.BADGES'),
    ("a name never declared", ECON, PARSE, "\tlocal asked = badgeAsked[player] or {}\n", "\tlocal asked = badgeAskd[player] or {}\n"),
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
