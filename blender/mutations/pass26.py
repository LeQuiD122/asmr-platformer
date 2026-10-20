"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 26: emotes and the second chance. An emote played without owning it, spammed, never let go of, not
ended by moving, or over an ending; a pose that does not exist; a picker a controller or a phone cannot
reach; a second chance given without being spent, usable any time, setting a best or buying a leaderboard
place, offered with nowhere to go back to, or bought and not used.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
EMOTE = S / "Client/Services/EmoteService.lua"
POSES = S / "Shared/Poses.lua"
ECON = S / "Server/Services/EconomyService.lua"
BOOT = S / "Server/Bootstrap.server.lua"
DEATH = S / "Client/Services/DeathService.lua"
PAUSE = S / "Client/Services/PauseMenuService.lua"
TIMER = S / "Server/Services/TimerService.lua"
SHOP, DEVICES, PARSE = "check_shop.py", "check_devices.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (SHOP, DEVICES, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    # Emotes.
    ("an emote played without owning it", ECON, SHOP, 'item.kind ~= "emote" or item.soon or not owns(player, item.id) then',
     'item.kind ~= "emote" or item.soon then'),
    ("an emote spammed", ECON, SHOP, "if now - (lastEmote[player] or 0) < EMOTE_GAP", "if now - (lastEmote[player] or 0) < 0"),
    ("an emote nobody else sees", ECON, SHOP, "remote:FireAllClients(player, item.id, workspace:GetServerTimeNow())",
     "remote:FireClient(player, item.id, workspace:GetServerTimeNow())"),
    ("a pose that does not exist", POSES, SHOP, "function Poses.stretch(", "function Poses.stretchh("),
    ("a pose never let go of", EMOTE, SHOP, "\t\t\tPoses.drive(joint, CFrame.identity)\n", "\n"),
    ("moving not ending it", EMOTE, SHOP, "Vector3.new(v.X, 0, v.Z).Magnitude > MOVING", "Vector3.new(v.X, 0, v.Z).Magnitude > 9e9"),
    ("an emote over an ending", EMOTE, SHOP, "return not (cinema and cinema.active and cinema.active())", "return true"),
    ("no picker on a controller", EMOTE, DEVICES, "Enum.KeyCode.G, Enum.KeyCode.DPadRight)", "Enum.KeyCode.G)"),
    ("no picker on a phone", PAUSE, DEVICES, 'local emotesButton = button("Emotes", 236', 'local emotesButton = button("Moods", 236'),
    ("B not closing the picker", EMOTE, DEVICES, "Enum.KeyCode.Escape, Enum.KeyCode.ButtonB)", "Enum.KeyCode.Escape)"),
    # The second chance.
    ("a chance used without one", ECON, SHOP, "(profile.Data.SecondChances or 0) < 1 then", "(profile.Data.SecondChances or 0) < -1 then"),
    ("a chance bought and not kept", ECON, SHOP, "\t\t\tprofile.Data.SecondChances += 1\n", "\n"),
    ("a chance given without spending", BOOT, SHOP, "if not EconomyService.spendChance(player) then", "if false then"),
    ("a chance any time after", BOOT, SHOP, "if os.clock() - fall.at > secondChance.WINDOW", "if os.clock() - fall.at > 9e9"),
    ("a chance that sets a best", BOOT, SHOP, "local counted = not usedChance and fairTime(player, state)",
     "local counted = fairTime(player, state)"),
    ("a leaderboard place bought", BOOT, SHOP, "\t\t\tif counted then\n\t\t\t\tLeaderboardService.submitTime(",
     "\t\t\tif true then\n\t\t\t\tLeaderboardService.submitTime("),
    ("a chance with nowhere to go", BOOT, SHOP, 'state.mode ~= "hardcore" or state.checkpointChunkIndex < 2 then',
     'state.mode ~= "hardcore" then'),
    ("the clock not put back", BOOT, SHOP, "TimerService.resume(player, fall.elapsed)", "TimerService.resetTimer(player)"),
    ("a chance bought on the card and not used", DEATH, SHOP, "MarketplaceService.PromptProductPurchaseFinished:Connect(",
     "MarketplaceService.PromptGamePassPurchaseFinished:Connect("),
    ("no way to put a clock back", TIMER, SHOP, "function TimerService.resume(player: Player, elapsed: number)",
     "function TimerService.restore(player: Player, elapsed: number)"),
    # The code still reads.
    ("a name never declared in the toy", EMOTE, PARSE, "\tlocal squeeze = math.max(0, math.sin(t * 3.2)) ^ 2\n\tlocal between",
     "\tlocal squeeze = math.max(0, math.sin(tt * 3.2)) ^ 2\n\tlocal between"),
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
