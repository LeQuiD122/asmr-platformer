"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 72: daily challenges. The board's posts, panel, frame or roof not holding together, facing away, written on by
the server, never built, in the way, off the deck or past the inlay; nobody's screen finding it, writing on its back
or for everyone, or off its panel; one done not noticed, a save loading told as done, the card silent, no countdown,
or one on the wrong clock. The list: a level without one, two with one id, a dash, a reward out of line, one no run
can do; not three a day, not shuffled by the day, picked past three; the first level's never given, a level's given
before it is open; yesterday's kept, ones a player cannot do given; the screen not told; runs not counted, paid every
time or never, off the dashboard twice over, not told; a run never doing one, its tokens or its word off the pill; a
new save with nowhere to keep them, a save loading without them, midnight never coming; the self-test not looking,
not doing one, or leaving its own on screen; the test panel's new three doing nothing, or no button for it.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
HUB = S / "Server/Services/HubService.lua"
LAYOUT = S / "Shared/LobbyLayout.lua"
VOTE = S / "Client/Services/HubVoteService.lua"
CAT = S / "Shared/ShopCatalog.lua"
ECON = S / "Server/Services/EconomyService.lua"
SHOPC = S / "Client/Services/ShopService.lua"
DEV = S / "Client/Services/DevPanelClient.lua"
HUBCHECK, SHOP, PARSE = "check_hub.py", "check_shop.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (HUBCHECK, SHOP, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

PLACE = "buildChallengeBoard(HUB_ORIGIN + AT.challenges, folder)"
SPOT = "challenges = Vector3.new(-114, 1, -26)"

MUTATIONS = [
    ("posts off the deck", HUB, HUBCHECK, "CFrame.new(x, 4.3, 0)", "CFrame.new(x, 5.3, 0)"),
    ("the panel not between the posts", HUB, HUBCHECK, 'plank("Panel", Vector3.new(7, 4.6, 0.3)',
     'plank("Panel", Vector3.new(6, 4.6, 0.3)'),
    ("the frame off the panel", HUB, HUBCHECK, 'plank("FrameTop", Vector3.new(7, 0.3, 0.4), CFrame.new(0, 7.85, 0)',
     'plank("FrameTop", Vector3.new(7, 0.3, 0.4), CFrame.new(0, 8.15, 0)'),
    ("the frame past the posts", HUB, HUBCHECK, 'plank("FrameBottom", Vector3.new(7, 0.3, 0.4)',
     'plank("FrameBottom", Vector3.new(8, 0.3, 0.4)'),
    ("the roof floating", HUB, HUBCHECK, "CFrame.new(0, 8.775, 0)", "CFrame.new(0, 9.775, 0)"),
    ("the roof narrower than the posts", HUB, HUBCHECK, 'plank("Roof", Vector3.new(8.4,', 'plank("Roof", Vector3.new(7.4,'),
    ("no roof", HUB, HUBCHECK,
     '\tplank("Roof", Vector3.new(8.4, 0.35, 1.4), CFrame.new(0, 8.775, 0), walnut, Enum.Material.Wood, false)\n', ""),
    ("facing away", HUB, HUBCHECK, "local facing = CFrame.lookAt(at, Vector3.new(ARCADE.X, at.Y, ARCADE.Z))",
     "local facing = CFrame.lookAt(at, Vector3.new(ARCADE.X, at.Y, ARCADE.Z + 80))"),
    ("pieces not set by its facing", HUB, HUBCHECK, "part.CFrame = facing * offset", "part.CFrame = CFrame.new(at) * offset"),
    ("written on by the server", HUB, HUBCHECK, "\tmodel.PrimaryPart = panel\n",
     '\tInstance.new("SurfaceGui").Parent = panel\n\tmodel.PrimaryPart = panel\n'),
    ("never built", HUB, HUBCHECK, "\t" + PLACE + "\n", ""),
    ("in the way of the chest", LAYOUT, HUBCHECK, SPOT, SPOT.replace("(-114, 1, -26)", "(-97, 1, -22)")),
    ("off the deck", LAYOUT, HUBCHECK, SPOT, SPOT.replace("(-114, 1, -26)", "(-114, 3, -26)")),
    ("past the inlay", LAYOUT, HUBCHECK, SPOT, SPOT.replace("(-114, 1, -26)", "(-114, 1, -32)")),
    ("nobody's screen finding it", VOTE, HUBCHECK, 'hub:FindFirstChild("ChallengeBoard")', 'hub:FindFirstChild("ChallengeBoards")'),
    ("written on its back", VOTE, HUBCHECK, "gui.Face = Enum.NormalId.Front", "gui.Face = Enum.NormalId.Back"),
    ("written for everyone", VOTE, HUBCHECK, 'gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")', "gui.Parent = workspace"),
    ("off its panel", VOTE, HUBCHECK, "gui.Adornee = panel", "gui.Adornee = nil"),
    ("one done not noticed", VOTE, HUBCHECK,
     '\t\t\tif name == "Challenges" or name == "ChallengesDone" then\n\t\t\t\tnoticeDone()\n\t\t\tend\n', ""),
    ("a save loading told as done", VOTE, HUBCHECK, 'if type(ids) == "string" and ids == knownIds and seenDone then',
     'if type(ids) == "string" and seenDone then'),
    ("the card silent", VOTE, HUBCHECK, 'HubVoteService.say("+" .. reward, title,', 'print("+" .. reward, title,'),
    ("no countdown", VOTE, HUBCHECK, 'foot.Text = ("New ones in %dh %02dm")', 'foot.Text = ("%dh %02dm")'),
    ("the countdown on the wrong clock", VOTE, HUBCHECK, "nextAt - workspace:GetServerTimeNow()", "nextAt - os.time()"),
    ("a level without one", CAT, SHOP, '\t{ id = "halls", text = "Finish the Flooded Halls", reward = 45, level = 4 },\n', ""),
    ("two with one id", CAT, SHOP, '{ id = "pools",', '{ id = "shore",'),
    ("a dash in the words", CAT, SHOP, '"Finish a long run"', '"Finish a long run -- any level"'),
    ("a reward out of line", CAT, SHOP, 'reward = 50, kind = "best"', 'reward = 500, kind = "best"'),
    ("one no run can do", CAT, SHOP, 'elseif challenge.kind == "long" then', 'elseif challenge.kind == "lengthy" then'),
    ("not three a day", CAT, SHOP, "ShopCatalog.CHALLENGES_A_DAY = 3", "ShopCatalog.CHALLENGES_A_DAY = 5"),
    ("not shuffled by the day", CAT, SHOP, "local random = Random.new(day)", "local random = Random.new()"),
    ("picked past three", CAT, SHOP, "if #picked < ShopCatalog.CHALLENGES_A_DAY and canDo(challenge) then",
     "if canDo(challenge) then"),
    ("the first level's never given", ECON, SHOP, "\tif at == 1 then\n\t\treturn true\n\tend\n", ""),
    ("a level's given before it is open", ECON, SHOP, "for index = at - 1, #LevelDefinitions.All do",
     "for index = 1, #LevelDefinitions.All do"),
    ("yesterday's kept", ECON, SHOP, "state.day ~= now", "state.day == nil"),
    ("ones a player cannot do", ECON, SHOP,
     "ids = ShopCatalog.pickChallenges(now, function(challenge)\n\t\t\t\treturn canChallenge(data, challenge)",
     "ids = ShopCatalog.pickChallenges(now, function(challenge)\n\t\t\t\treturn true"),
    ("the screen not told", ECON, SHOP, 'player:SetAttribute("ChallengeNext",', 'player:SetAttribute("ChallengeNxt",'),
    ("runs not counted", ECON, SHOP, "state.runs = (tonumber(state.runs) or 0) + 1", "state.runs = tonumber(state.runs) or 0"),
    ("paid every time", ECON, SHOP, "\t\t\tstate.done[id] = true\n", ""),
    ("paid never", ECON, SHOP, "\t\tdata.Tokens += prize\n", ""),
    ("off the economy view", ECON, SHOP, 'Gameplay.Name, "Challenge")', 'Gameplay.Name, "Challenges")'),
    ("off the custom events", ECON, SHOP, 'LogCustomEvent(player, "ChallengeDone", challenge.reward,',
     'LogCustomEvent(player, "Challenge", challenge.reward,'),
    ("not told when done", ECON, SHOP, "\tchallengeAttributes(player)\n\treturn prize, done", "\treturn prize, done"),
    ("a run never doing one", ECON, SHOP,
     "local prize, done = EconomyService.challengeRun(player, { levelId = levelId, hardcore = hardcore, best = best,\n"
     "\t\tfriend = friend, length = run.length })", "local prize, done = 0, {}"),
    ("its tokens off the pill", ECON, SHOP, "FireClient(player, amount + prize + foundTokens, {", "FireClient(player, amount + foundTokens, {"),
    ("its word off the pill", ECON, SHOP, "friend = friend, challenges = #done,", "friend = friend,"),
    ("a new save with nowhere to keep them", ECON, SHOP, "\tChallenges = {} :: { [string]: any },", "\tChallenge = {} :: { [string]: any },"),
    ("a save loading without them", ECON, SHOP, "profiles[player] = ready\n\tdailyAttributes(player)\n\tchallengeAttributes(player)\n",
     "profiles[player] = ready\n\tdailyAttributes(player)\n"),
    ("midnight never coming", ECON, SHOP, "if today() ~= shown then", "if false then"),
    ("the self-test not looking", ECON, SHOP, "#picked.ids == ShopCatalog.CHALLENGES_A_DAY\n\t\t\tand #locked == 0,", "true,"),
    ("the self-test not doing one", ECON, SHOP, "paidLong == long.reward and paidAgain == 0\n\t\t\tand paidThird == three.reward",
     "paidLong == long.reward\n\t\t\tand paidThird == three.reward"),
    ("the self-test leaving its own on screen", ECON, SHOP,
     "tellLevels()\n\tdailyAttributes(player)\n\tchallengeAttributes(player)\n", "tellLevels()\n\tdailyAttributes(player)\n"),
    ("the new three doing nothing", ECON, SHOP, "ShopCatalog.pickChallenges(today() + math.random(1, 9999)",
     "ShopCatalog.pickChallenges(today()"),
    ("no button for it", DEV, SHOP, '\t{ action = "challengesNew", text = "Challenges: new three" },\n', ""),
    ("the pill not saying", SHOPC, SHOP, '\t\t\ttable.insert(reasons, "Challenge done")\n', ""),
    ("a name never declared", ECON, PARSE, "local state = challengesToday(profile.Data)",
     "local state = challengeToday(profile.Data)"),
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
