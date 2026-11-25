"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 137: in and out of a run under a dip. A level's start not streamed in; a run from the lobby starting with a
cut, or a failed start left black; no name on the black; home from a run, from the menu or not streamed in, with a cut;
going home taken for a fall; one fall counted every frame; a Chill fall a jump cut, or its dip lingering; the fade short
of the top, under the menus, a dip never black, the name kept after it; the client deaf to a dip.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
BOOT = S / "Server/Bootstrap.server.lua"
CBOOT = S / "Client/Bootstrap.client.lua"
UIS = S / "Client/Services/UIService.lua"
POLISH = "check_polish.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (POLISH,):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('the start not streamed in', BOOT, POLISH, '\tstreamFor(players, levelInstance.startPosition)\n', '\n'),
    ('into a run with a cut', BOOT, POLISH, '\t\tScreenFade:FireClient(player, { black = true, time = DIP.out })\n\tend\n\ttask.wait(DIP.out)\n\tlocal ok, result', '\t\tlocal _ = player\n\tend\n\ttask.wait(DIP.out)\n\tlocal ok, result'),
    ('left in the dark when a start fails', BOOT, POLISH, '\tif not ok then\n\t\terror(result, 0)\n\tend\n\treturn result', '\treturn result'),
    ('no name on the black', BOOT, POLISH, 'startChosenLevel(level, players, origin, cardFor(level))', 'startChosenLevel(level, players, origin)'),
    ('home from a finished run with a cut', BOOT, POLISH, '\t\t\tgoHome(player)\n', '\t\t\tHubService.returnToHub(player)\n'),
    ("the menu's way out a cut", BOOT, POLISH, 'goHome(player, function()\n\t\t\tstoryLeave(player)\n\t\tend)', 'HubService.returnToHub(player)\n\t\tstoryLeave(player)'),
    ('home not streamed in', BOOT, POLISH, '\tstreamFor({ player }, HubService.spawnPosition())\n', '\n'),
    ('going home taken for a fall', BOOT, POLISH, '\t\tif homeGoing[player] then\n\t\t\tcontinue\n\t\tend\n', ''),
    ('a fall counted every frame', BOOT, POLISH, 'if last and os.clock() - last < CATCH_GAP then', 'if false then'),
    ('a Chill fall a jump cut', BOOT, POLISH, '\t\t\t\t-- SEEN AS A CUT (DIP.fall): black at once where you are set down, and the picture back.\n\t\t\t\tScreenFade:FireClient(player, { dip = true, time = DIP.fall })\n', ''),
    ('a dip that lingers', BOOT, POLISH, 'fall = 0.55 }', 'fall = 2 }'),
    ('a strip of the world over the fade', UIS, POLISH, 'fadeGui.IgnoreGuiInset = true', 'fadeGui.IgnoreGuiInset = false'),
    ('the fade under the menus', UIS, POLISH, 'fadeGui.DisplayOrder = 46', 'fadeGui.DisplayOrder = 5'),
    ('a dip never black', UIS, POLISH, '\tblackout.BackgroundTransparency = 0\n\tUIService.fadeFromBlack(seconds or 0.5)', '\tUIService.fadeFromBlack(seconds or 0.5)'),
    ('the name kept after the black', UIS, POLISH, 'showCard(false, math.min(0.3, over * 0.4))', 'local _ = over'),
    ('the client deaf to a dip', CBOOT, POLISH, 'if payload.dip then', 'if payload.dipped then'),
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
