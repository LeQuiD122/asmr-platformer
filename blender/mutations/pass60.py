"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 60: story mode. No Story pad; a story started as a level, or a level leaving one running; going on from the
furthest-ahead player; a time from a story begun partway; the wrong level or length; the squish room pulled in; a
level for nobody; a level built over the last; nobody sent home at the end; the last finisher sent to the lobby; no
waiting message; the wait started twice, or never ending; the left-behind kept; leaving leaving the others waiting;
a time from a level whose time did not count; a place saved for a level not walked; no leaderboard; LEVEL COMPLETE
not told; a late joiner's time; the save's place out of range; no test button; the card not told.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
HUB = S / "Server/Services/HubService.lua"
BOOT = S / "Server/Bootstrap.server.lua"
ECON = S / "Server/Services/EconomyService.lua"
UI = S / "Client/Services/UIService.lua"
CBOOT = S / "Client/Bootstrap.client.lua"
BANNER = S / "Client/Services/HubVoteService.lua"
CHECK, PARSE = "check_hub.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (CHECK, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ("no Story pad", HUB, CHECK, "\ttable.insert(levels, STORY)\n", ""),
    ("started as a level", BOOT, CHECK, "\tif level.story then\n\t\treturn startStory(players, origin)\n\tend\n", ""),
    ("a level leaves a story running", BOOT, CHECK, "\tend\n\tstoryRun = nil\n\treturn startChosenLevel(level, players, origin)",
     "\tend\n\treturn startChosenLevel(level, players, origin)"),
    ("from the furthest ahead", BOOT, CHECK, "from = math.min(from, at)", "from = math.max(from, at)"),
    ("a time from partway", BOOT, CHECK, "run.fair[player] = from == 1", "run.fair[player] = true"),
    ("the wrong level", BOOT, CHECK, "\tHubService.setLevel(level.levelId)\n\tlocal going = {}", "\tlocal going = {}"),
    ("the wrong length", BOOT, CHECK, "startChosenLevel(HubService.scaledLevel(level, run.length), going,",
     "startChosenLevel(level, going,"),
    ("the squish room pulled in", BOOT, CHECK, '\t\telseif player:GetAttribute("InSquishRoom") then\n\t\t\trun.players[player] = nil\n\t\t\ttellStory(player, "behind")\n',
     ""),
    ("a level for nobody", BOOT, CHECK, "\tif #going == 0 then\n\t\tstoryRun = nil\n", "\tif #going < 0 then\n\t\tstoryRun = nil\n"),
    ("built over the last", BOOT, CHECK, "\ttask.wait(STORY_FADE)\n\tendLevelWorld()\n", "\ttask.wait(STORY_FADE)\n"),
    ("nobody sent home", BOOT, CHECK,
     "\t\tstoryRun = nil\n\t\tfor player in pairs(run.players) do\n\t\t\tif player.Parent == Players and HubService.isInRun(player) then\n\t\t\t\tHubService.returnToHub(player)\n\t\t\tend\n\t\tend\n\t\treturn\n",
     "\t\tstoryRun = nil\n\t\treturn\n"),
    ("the last sent to the lobby", BOOT, CHECK, "\tif playing == 0 then\n\t\tstoryNext(run)\n\t\treturn\n\tend\n", ""),
    ("no waiting message", BOOT, CHECK, '\ttellStory(player, "waiting", { playing = playing, level = LevelDefinitions.Story[run.index].name })\n', ""),
    ("the wait started twice", BOOT, CHECK, "\tif not run.waiting then\n", "\tif true then\n"),
    ("waiting for ever", BOOT, CHECK, "\t\ttask.delay(STORY_WAIT, function()\n\t\t\tstoryTimeUp(run, index)\n\t\tend)\n", ""),
    ("the left behind kept", BOOT, CHECK, "\t\t\tHubService.returnToHub(player)\n\t\t\ttellStory(player, \"behind\")\n", "\t\t\ttellStory(player, \"behind\")\n"),
    ("leaving from the menu", BOOT, CHECK,
     "\t-- AND OUT OF THE STORY (storyLeave), so whoever is waiting in the lobby can go on.\n\tstoryLeave(player)\n", ""),
    ("leaving the server", BOOT, CHECK,
     "\t-- OUT OF THE STORY too (storyLeave): the hub has already had them back, so the rest may go on.\n\tstoryLeave(player)\n", ""),
    ("to the lobby every level", BOOT, CHECK, "\t\t\tif going and going.players[player] and player.Parent then\n\t\t\t\tstoryStep(player)\n\t\t\t\treturn\n\t\t\tend\n",
     ""),
    ("a time that did not count", BOOT, CHECK, 'if state.mode == "hardcore" and counted then\n\t\t\t\tstory.total[player] =',
     'if state.mode == "hardcore" then\n\t\t\t\tstory.total[player] ='),
    ("a place for a level not walked", BOOT, CHECK, "if walked and EconomyService and EconomyService.setStoryAt then",
     "if EconomyService and EconomyService.setStoryAt then"),
    ("no leaderboard", BOOT, CHECK, '\t\t\t\t\t\tpcall(LeaderboardService.submitTime, player, HubService.STORY_ID, "hardcore", total)\n', ""),
    ("an unfair time on it", BOOT, CHECK, "\t\t\t\tif fair then\n\t\t\t\t\tlocal total = story.total[player]",
     "\t\t\t\tif true then\n\t\t\t\t\tlocal total = story.total[player]"),
    ("LEVEL COMPLETE not told", BOOT, CHECK, "time = elapsed, story = storyInfo })", "time = elapsed })"),
    ("a late joiner's time", BOOT, CHECK, "\t\tstoryRun.fair[player] = false\n", "\t\tstoryRun.fair[player] = true\n"),
    ("the place out of range", ECON, CHECK, "return math.clamp(math.floor(at or 1), 1, #LevelDefinitions.Story)", "return at or 1"),
    ("no test button", ECON, CHECK, '\telseif action == "storyStart" then\n\t\t-- The story from the start again next time, Hill House since the hundred-and-eleventh pass (its place put back).\n\t\tdata.StoryAt = 1\n', ""),
    ("the card says nothing", UI, CHECK, '\t\t\tcompletionMode.Text = "Story complete"\n', ""),
    ("never reaches the card", CBOOT, CHECK, "UIService.showCompletion(payload.levelId, payload.time, payload.story)",
     "UIService.showCompletion(payload.levelId, payload.time)"),
    ("the vote card not told", BANNER, CHECK, '\t\telseif kind == "story" then\n\t\t\tHubVoteService.onStory(payload)\n', ""),
    ("a name never declared", BOOT, PARSE, "\tlocal playing = storyPlaying(run, player)\n", "\tlocal playing = storyPlaying(rn, player)\n"),
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
