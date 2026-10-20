"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 69: the daily chest. Opened twice a day; a streak that never grows, or never starts again; not the catalogue's
tokens; not kept as opened; the screen never told, or not on joining; paid without a word; days that are not UTC
days; rewards that shrink; no test button; the self-test not opening it; the pill not saying the day; the chest
off the deck, its lid floating, no prompt, a prompt that does nothing; not wired; the card, the prompt's words, the
server clock and the lid on the client; the chest standing in the way of something else in the lobby.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
CAT = S / "Shared/ShopCatalog.lua"
ECON = S / "Server/Services/EconomyService.lua"
HUB = S / "Server/Services/HubService.lua"
LAYOUT = S / "Shared/LobbyLayout.lua"
BOOT = S / "Server/Bootstrap.server.lua"
BANNER = S / "Client/Services/HubVoteService.lua"
SHOPC = S / "Client/Services/ShopService.lua"
DEV = S / "Client/Services/DevPanelClient.lua"
SHOP, HUBCHECK, PARSE = "check_shop.py", "check_hub.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (SHOP, HUBCHECK, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ("opened twice a day", ECON, SHOP, "\tif last == now then\n\t\treturn { opened = false,", "\tif last == now + 99 then\n\t\treturn { opened = false,"),
    ("a streak that never grows", ECON, SHOP, "local streak = if last == now - 1 then (tonumber(data.DailyStreak) or 0) + 1 else 1",
     "local streak = 1"),
    ("a streak that never starts again", ECON, SHOP, "local streak = if last == now - 1 then (tonumber(data.DailyStreak) or 0) + 1 else 1",
     "local streak = (tonumber(data.DailyStreak) or 0) + 1"),
    ("not the catalogue's tokens", ECON, SHOP, "\tlocal amount = ShopCatalog.dailyReward(streak)\n", "\tlocal amount = 500\n"),
    ("not kept as opened", ECON, SHOP, "\tdata.DailyDay = now\n", ""),
    ("the screen never told", ECON, SHOP, "\tpush(player)\n\tdailyAttributes(player)\n\tif earnedRemote then\n\t\tearnedRemote:FireClient(player, amount, { daily = true",
     "\tpush(player)\n\tif earnedRemote then\n\t\tearnedRemote:FireClient(player, amount, { daily = true"),
    ("not on joining", ECON, SHOP, "\tprofiles[player] = ready\n\tdailyAttributes(player)\n", "\tprofiles[player] = ready\n"),
    ("paid without a word", ECON, SHOP, "earnedRemote:FireClient(player, amount, { daily = true, streak = streak })",
     "earnedRemote:FireClient(player, amount, { streak = streak })"),
    ("days that are not UTC days", ECON, SHOP, "\treturn math.floor(os.time() / DAY)\n", "\treturn math.floor(os.clock() / DAY)\n"),
    ("rewards that shrink", CAT, SHOP, "DAILY = { 20, 30, 40, 50, 60, 80, 120 },", "DAILY = { 120, 80, 60, 50, 40, 30, 20 },"),
    ("no test button", DEV, SHOP, '\t{ action = "dailyNext", text = "Daily: next day" },\n', ""),
    ("the self-test not opening it", ECON, SHOP, 'check("the daily chest: once a day, its streak the next day, and again from day one after a day missed",',
     'check("the daily chest",'),
    ("the pill not saying the day", SHOPC, SHOP, '\t\t\ttable.insert(reasons, ("Daily chest, day %d"):format(tonumber(info.streak) or 1))\n', ""),
    ("off the deck", HUB, HUBCHECK, 'piece("Body", Vector3.new(3.2, 1.8, 2), CFrame.new(0, 0.9, 0)', 'piece("Body", Vector3.new(3.2, 1.8, 2), CFrame.new(0, 2, 0)'),
    ("the lid floating", HUB, HUBCHECK, 'piece("Lid", Vector3.new(3.2, 0.5, 2), CFrame.new(0, 2.05, 0)', 'piece("Lid", Vector3.new(3.2, 0.5, 2), CFrame.new(0, 3, 0)'),
    ("no prompt", HUB, HUBCHECK, '\tprompt.ActionText = "Open"\n\tprompt.ObjectText = "Daily chest"\n', '\tprompt.ObjectText = "Daily chest"\n'),
    ("a prompt that does nothing", HUB, HUBCHECK, "\t\tlocal open = dailyChest\n", "\t\tlocal open = nil\n"),
    ("not wired", BOOT, HUBCHECK, '\t\tHubVoteState:FireClient(player, "daily", result)\n', ""),
    ("the card never told", BANNER, HUBCHECK, '\t\telseif kind == "daily" then\n\t\t\tHubVoteService.onDaily(payload)\n', ""),
    ("the prompt's words", BANNER, HUBCHECK, 'prompt.ActionText = if ready then "Open" else "Opened today"', 'prompt.ActionText = "Open"'),
    ("the client's own clock", BANNER, HUBCHECK, "workspace:GetServerTimeNow() >= nextAt", "os.clock() >= nextAt"),
    ("the lid never lifts", BANNER, HUBCHECK, "\tTweenService:Create(lid, TweenInfo.new(0.5,", "\tlocal _ = (lid, TweenInfo.new(0.5,"),
    ("in the way", LAYOUT, HUBCHECK, "chest = Vector3.new(-92, 1, -22)", "chest = Vector3.new(-98, 1, -24)"),
    ("a name never declared", ECON, PARSE, "\tlocal last = tonumber(data.DailyDay) or 0\n", "\tlocal last = tonumber(dta.DailyDay) or 0\n"),
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
