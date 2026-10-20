"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 33: what only shows with more than one player. Statues that say nobody's, are tagged for nobody, stay
after their player, keep a pose; a screen that hides its own statue or shows everyone's, names a hidden
figure, or misses one that loads later. A run that ends without a finish and leaves the level's sky or world;
the finish's old idea of "still running"; a player back in the lobby put on the level by a reset; a late
joiner not counted in, unpaid, in the wrong mode, never joined at all, or the squish room pulled in.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
HUB = S / "Server/Services/HubService.lua"
BOOT = S / "Server/Bootstrap.server.lua"
VOTE = S / "Client/Services/HubVoteService.lua"
HUBCHECK, PARSE = "check_hub.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (HUBCHECK, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    # The statues.
    ("a statue nobody's", HUB, HUBCHECK, '\tstand:SetAttribute("Owner", player.UserId)\n', ""),
    ("a statue tagged for nobody", HUB, HUBCHECK, 'CollectionService:AddTag(stand, "LobbyStatue")',
     'CollectionService:AddTag(stand, "Statue")'),
    ("a statue left standing", HUB, HUBCHECK, "\t\tstand:Destroy()\n\tend\nend\n\nfunction HubService.buildStatue(",
     "\t\tstand.Parent = stand.Parent\n\tend\nend\n\nfunction HubService.buildStatue("),
    ("a pose left behind", HUB, HUBCHECK, "\tposeFor[player] = nil\n\ttintFor[player] = nil\n", "\ttintFor[player] = nil\n"),
    ("never taken down", BOOT, HUBCHECK, "pcall(HubService.removeStatue, player)", "print(HubService.removeStatue, player)"),
    ("your own hidden too", VOTE, HUBCHECK, 'if stand:GetAttribute("Owner") == Players.LocalPlayer.UserId then\n\t\treturn',
     "if false then\n\t\treturn"),
    ("everyone's shown", VOTE, HUBCHECK, "(item :: any).LocalTransparencyModifier = 1", "(item :: any).LocalTransparencyModifier = 0"),
    ("a hidden figure's name", VOTE, HUBCHECK, "item.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None",
     "item.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer"),
    ("a figure that loads later", VOTE, HUBCHECK, "\tstand.DescendantAdded:Connect(hide)\n", ""),
    ("a statue built later", VOTE, HUBCHECK, '\tCollectionService:GetInstanceAddedSignal("LobbyStatue"):Connect(hideOthers)\n', ""),
    # A run's end.
    ("the level's sky over the lobby", BOOT, HUBCHECK,
     "\t-- level's sky over the lobby until the next run, and its world standing.\n\tpcall(LightingService.apply, \"lobby\")\nend)",
     "\t-- level's sky over the lobby until the next run, and its world standing.\nend)"),
    ("the level's world left standing", BOOT, HUBCHECK, "HubService.setEnder(function()\n\tendLevelWorld()\n",
     "HubService.setEnder(function()\n"),
    ("the old idea of running", BOOT, HUBCHECK, "if other ~= player and HubService.isInRun(other) then",
     "if other ~= player and not (PlayerStateService.getState(other) or {} :: any).hasCompletedLevel then"),
    # Where a player is put.
    ("a finisher reset onto the level", BOOT, HUBCHECK,
     "local target = if levelInstance and (inRunNow or lobbyAway) then levelInstance.startPosition else hub.spawnPosition",
     "local target = if levelInstance then levelInstance.startPosition else hub.spawnPosition"),
    ("a late joiner not counted", BOOT, HUBCHECK, "\tHubService.markInRun({ player })\n", ""),
    ("a late joiner unpaid", BOOT, HUBCHECK, "pcall(EconomyService.runStarted, { player }, runLength, true)", "pcall(print, { player }, runLength, true)"),
    ("a late joiner in the wrong mode", BOOT, HUBCHECK, "\tPlayerStateService.beginRun(player, request.mode :: any)\n\tHubService.markInRun",
     "\tHubService.markInRun"),
    ("the squish room pulled in", BOOT, HUBCHECK,
     'if levelInstance and not inRunNow and lobbyAway and not player:GetAttribute("InSquishRoom") then',
     "if levelInstance and not inRunNow and lobbyAway then"),
    ("never joined", BOOT, HUBCHECK, "\t\t\tjoinRunLate(player)\n", ""),
    # The code still reads.
    ("a name never declared", BOOT, PARSE, "\tTimerService.init(player)\n\tif not PlayerStateService.getState(player) then\n\t\tPlayerStateService.init(player, instance.startPosition)",
     "\tTimerSrvice.init(player)\n\tif not PlayerStateService.getState(player) then\n\t\tPlayerStateService.init(player, instance.startPosition)"),
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
