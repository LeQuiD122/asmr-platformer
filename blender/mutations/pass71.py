"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 71: a friend in the run. No more for one, or far too much; the share left out, or not doubled by the 2x pass;
never asked, or not paid; the save not looked at again after asking; paid without a word; not on the dashboard; the
pretend friend live; yourself as your own friend; a friend who left still counting; asked unguarded; a failed ask
kept; the last run's crew kept; nobody in a crew; kept after leaving; told every time; nobody told at the start; a
late joiner starting a new crew; the card never told, too early, deaf to it, or not saying what it pays; the pill not
saying; the self-test losing the crew or not checking; the test panel's friend doing nothing, or no button for it;
the invite promising more, or saying nothing; a dash in the words; the first visit silent about it.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
CAT = S / "Shared/ShopCatalog.lua"
ECON = S / "Server/Services/EconomyService.lua"
BOOT = S / "Server/Bootstrap.server.lua"
VOTE = S / "Client/Services/HubVoteService.lua"
SHOPC = S / "Client/Services/ShopService.lua"
DEV = S / "Client/Services/DevPanelClient.lua"
PAUSE = S / "Client/Services/PauseMenuService.lua"
ONBOARD = S / "Client/Services/OnboardingService.lua"
SHOP, PARSE = "check_shop.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (SHOP, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

FRIEND_STEP = "\tif friend then\n\t\tamount = math.floor(amount * ShopCatalog.REWARD.FRIEND + 0.5)\n\tend\n"
DOUBLE_STEP = "\tif double then\n\t\tamount *= 2\n\tend\n"

MUTATIONS = [
    ("no more for a friend", CAT, SHOP, "\tFRIEND = 1.2,", "\tFRIEND = 1.0,"),
    ("far too much for a friend", CAT, SHOP, "\tFRIEND = 1.2,", "\tFRIEND = 3,"),
    ("the share left out", CAT, SHOP, FRIEND_STEP, ""),
    ("the 2x pass not doubling it", CAT, SHOP, FRIEND_STEP + DOUBLE_STEP, DOUBLE_STEP + FRIEND_STEP),
    ("never asked", ECON, SHOP, "\tlocal friend = EconomyService.withFriend(player)\n", "\tlocal friend = false\n"),
    ("asked and not paid", ECON, SHOP, "ShopCatalog.reward(run.length, hardcore, best, double, friend)",
     "ShopCatalog.reward(run.length, hardcore, best, double)"),
    ("the save not looked at again", ECON, SHOP,
     "\tlocal friend = EconomyService.withFriend(player)\n\tif not profile:IsActive() then\n\t\treturn\n\tend\n",
     "\tlocal friend = EconomyService.withFriend(player)\n"),
    ("paid without a word", ECON, SHOP, "double = double, friend = friend, challenges", "double = double, challenges"),
    ("not on the dashboard", ECON, SHOP, 'LogCustomEvent(player, "RunWithFriend", levelId or 0)',
     'LogCustomEvent(player, "RunWithFriends", levelId or 0)'),
    ("the pretend friend live", ECON, SHOP, "if devFriend[player] and RunService:IsStudio() then", "if devFriend[player] then"),
    ("yourself as your own friend", ECON, SHOP, "\t\tif other ~= player then\n\t\t\ttable.insert(others, other)\n",
     "\t\tif other then\n\t\t\ttable.insert(others, other)\n"),
    ("a friend who left still counts", ECON, SHOP,
     "other.Parent == Players and player.Parent == Players and isFriend(player, other)", "isFriend(player, other)"),
    ("asked unguarded", ECON, SHOP, "local ok, yes = pcall(player.IsFriendsWith, player, other.UserId)",
     "local ok, yes = true, player:IsFriendsWith(other.UserId)"),
    ("a failed ask kept", ECON, SHOP,
     "\tif not ok then\n\t\treturn false\n\tend\n\tremember(player, other.UserId, yes == true)\n",
     "\tremember(player, other.UserId, yes == true)\n"),
    ("the last run's crew kept", ECON, SHOP, "\tif not joining then\n\t\ttable.clear(crew)\n\tend\n", ""),
    ("nobody in a crew", ECON, SHOP, "\t\tcrew[player] = true\n", ""),
    ("kept after leaving", ECON, SHOP, "\tcrew[player] = nil\n\tfriendOf[player] = nil\n", "\tfriendOf[player] = nil\n"),
    ("told every time", ECON, SHOP, "\t\t\ttoldFriend[player] = true\n", ""),
    ("nobody told at the start", BOOT, SHOP,
     "\t\tpcall(EconomyService.runStarted, players, HubService.getRequest().length)\n\t\ttellRunFriends()\n",
     "\t\tpcall(EconomyService.runStarted, players, HubService.getRequest().length)\n"),
    ("a late joiner starting a new crew", BOOT, SHOP, "pcall(EconomyService.runStarted, { player }, runLength, true)",
     "pcall(EconomyService.runStarted, { player }, runLength)"),
    ("the card never told", BOOT, SHOP, 'HubVoteState:FireClient(player, "friend",', 'HubVoteState:FireClient(player, "friends",'),
    ("told before the run arrives", BOOT, SHOP, "task.delay(FRIEND_TELL_AFTER, function()", "task.spawn(function()"),
    ("the card deaf to it", VOTE, SHOP, '\t\telseif kind == "friend" then\n\t\t\tHubVoteService.onFriend(payload)\n', ""),
    ("the card not saying what it pays", VOTE, SHOP,
     '"A friend of yours is on this run. Reach the end and it pays %d%% more tokens."', '"A friend of yours is on this run."'),
    ("the pill not saying", SHOPC, SHOP, '\t\t\ttable.insert(reasons, "With a friend")\n', ""),
    ("the self-test losing the crew", ECON, SHOP, "\tlocal realCrew = table.clone(crew)\n", "\tlocal realCrew = crew\n"),
    ("the self-test not checking", ECON, SHOP,
     'check("a friend in the run pays a fifth more", together == math.floor(plain * ShopCatalog.REWARD.FRIEND + 0.5)',
     'check("a friend in the run pays a fifth more", true'),
    ("the test panel's friend doing nothing", ECON, SHOP,
     "\t\tdevFriend[player] = if devFriend[player] then nil else true\n", ""),
    ("no button for it", DEV, SHOP, '\t{ action = "friend", text = "Friend in runs on/off" },\n', ""),
    ("the invite promising more", PAUSE, SHOP, "pays 20% more tokens", "pays 50% more tokens"),
    ("the invite saying nothing", PAUSE, SHOP, "\t\tmade.PromptMessage = INVITE_WORDS\n", ""),
    ("a dash in the words", VOTE, SHOP, "A friend of yours is on this run.", "A friend of yours -- on this run."),
    ("the first visit silent about it", ONBOARD, SHOP, "a friend running with you", "more"),
    ("a name never declared", ECON, PARSE, "\tlocal others = {}\n\tfor other in pairs(crew) do",
     "\tlocal others = {}\n\tfor other in pairs(crowd) do"),
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
