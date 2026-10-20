"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 30: times that count, an invite and the favourite. Another go taken from anywhere in a run (the clock
started again near the end), a best from chill or from nothing, a time kept without the route walked or
impossibly fast, a 0 shown as a best; an invite that is missing, does nothing, opens unasked or fails in
silence; a favourite asked twice, during a run, at once, of someone it already is, before it is noted, never,
or with no way to see it again; and a client's hello kept however long.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
BOOT = S / "Server/Bootstrap.server.lua"
BEST = S / "Server/Services/BestTimeService.lua"
ECON = S / "Server/Services/EconomyService.lua"
CITY = S / "Server/Services/SunkenCityService.lua"
PAUSE = S / "Client/Services/PauseMenuService.lua"
ONBOARD = S / "Client/Services/OnboardingService.lua"
DEV = S / "Client/Services/DevPanelClient.lua"
SHOP, SUNK, PARSE = "check_shop.py", "check_sunkencity.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (SHOP, SUNK, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    # Times that count.
    ("another go from anywhere", BOOT, SHOP,
     "if not HubService.isInRun(player) or not PlayerStateService.canToggleMode(player) then",
     "if not HubService.isInRun(player) then"),
    ("a best from chill", BOOT, SHOP, 'if not levelInstance or state.mode ~= "hardcore" then\n\t\treturn false',
     "if not levelInstance then\n\t\treturn false"),
    ("a best from nothing", BOOT, SHOP, "if elapsed <= 0 then", "if elapsed < 0 then"),
    ("the route not walked", BOOT, SHOP, "if (state.checkpointChunkIndex or 0) < needed then", "if false then"),
    ("impossibly fast", BOOT, SHOP, "if floor and elapsed < floor * 0.5 then", "if floor and elapsed < 0 then"),
    ("the rule never asked", BOOT, SHOP, "local counted = not usedChance and fairTime(player, state)",
     "local counted = not usedChance"),
    ("the floor for any length", BOOT, SHOP, "\trunLength = HubService.getRequest().length\n", ""),
    ("a 0 saved as a best", BEST, SHOP, "if timeSeconds <= 0 then\n\t\treturn false", "if timeSeconds < 0 then\n\t\treturn false"),
    ("a 0 shown as 00:00", BEST, SHOP, 'typeof(value) == "number" and value > 0 then', 'typeof(value) == "number" then'),
    # The invite.
    ("no invite", PAUSE, SHOP, 'local inviteButton = button("Invite", 236', 'local inviteButton = button("Friends", 236'),
    ("an invite unasked", PAUSE, SHOP, "return SocialService:CanSendGameInviteAsync(me)", "return true"),
    ("an invite that does nothing", PAUSE, SHOP, "task.spawn(invite)", "task.spawn(function() end)"),
    ("a refusal in silence", PAUSE, SHOP, 'StarterGui:SetCore("SendNotification"', 'StarterGui:GetCore("SendNotification"'),
    # The favourite.
    ("the favourite noted again", ECON, SHOP,
     '\telseif what == "favourite" then\n\t\tif data.AskedFavourite then\n\t\t\treturn\n\t\tend\n',
     '\telseif what == "favourite" then\n'),
    ("the favourite not a note", ECON, SHOP, "shopIntro = true, favourite = true }", "shopIntro = true }"),
    ("the favourite asked again", ONBOARD, SHOP, "data.shopIntro and not data.askedFavourite and state.finishedRun",
     "data.shopIntro and state.finishedRun"),
    ("the favourite during a run", ONBOARD, SHOP, "and not state.favouriteAsked and inLobby() and",
     "and not state.favouriteAsked and"),
    ("the favourite at once", ONBOARD, SHOP, "if now - since < FAVOURITE_SETTLE then", "if false then"),
    ("the favourite of a favourite", ONBOARD, SHOP, "if ok and already == true then\n\t\t\treturn",
     "if false then\n\t\t\treturn"),
    ("the favourite before it is noted", ONBOARD, SHOP, '\tnote("favourite")\n', ""),
    ("the favourite straight after the kiosk", ONBOARD, SHOP,
     "if before and before.shopIntro and (data.earned or 0) > (before.earned or 0) then",
     "if before and (data.earned or 0) > (before.earned or 0) then"),
    ("the test panel's ask unseen", ECON, SHOP, "\t\tdata.AskedFavourite = true\n\t\tpush(player)\n", ""),
    ("the favourite never stepped", ONBOARD, SHOP, "stepShop()\n\t\t\tstepFavourite()", "stepShop()"),
    ("the favourite never seen again", DEV, SHOP, '\t{ action = "favourite", text = "Favourite ask again" },\n', ""),
    # A client's hello.
    ("a hello kept however long", CITY, SUNK, "string.sub(tostring(version), 1, 60)", "tostring(version)"),
    # The code still reads.
    ("a name never declared", PAUSE, PARSE, "local me = Players.LocalPlayer", "local me = Plyers.LocalPlayer"),
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
