"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 130, from your test of 2026-10-23. The lobby's sounds in a level, or a stand-in heard everywhere at once;
the hardcore clock up in Chill, or never folding; a scene walked out of, the prompts over it, a scene going on over the
lobby, a kept sound going on, the drain going on; a thought bubble emptied by its fade; you standing in a shot's way;
the bricks' hole shot from its sill; a name never declared.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
AMB = S / "Client/Services/AmbienceService.lua"
CINEMA = S / "Client/Services/Cinema.lua"
HUBS = S / "Server/Services/HubService.lua"
INTERACT = S / "Server/Services/Interactables.lua"
STORYC = S / "Client/Services/StoryClient.lua"
SUNK = S / "Client/Services/SunkenCityClient.lua"
UIS = S / "Client/Services/UIService.lua"
ROOMSCHECK, STORY, PARSE = "check_backrooms.py", "check_story.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (ROOMSCHECK, STORY, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('lobby sounds in a level', AMB, ROOMSCHECK, 'hushLobby(wanted ~= nil)', 'hushLobby(wanted == "backRooms")'),
    ('a placed lobby sound in a level', AMB, STORY, 'if item:IsA("Sound") then\n\t\titem.SoundGroup = lobbyGroup()', 'if item:IsA("Sound") and not item:FindFirstAncestorWhichIsA("BasePart") then\n\t\titem.SoundGroup = lobbyGroup()'),
    ('a stand-in everywhere at once', HUBS, STORY, 'fromLobby(swell, 60, 320)', 'swell.Parent = folder'),
    ('the clock up in Chill', UIS, STORY, 'if not hardcore then\n\t\tUIService.setTimerVisible(false)', 'if false then\n\t\tUIService.setTimerVisible(false)'),
    ('the clock never folding', UIS, STORY, 'timerFold.Activated:Connect(function()\n\ttimerFolded = true', 'timerFold.Activated:Connect(function()\n\ttimerFolded = false'),
    ('walking out of a scene', CINEMA, STORY, '\tholdStill(true)\n', '\n'),
    ('prompts over a scene', CINEMA, STORY, 'ProximityPromptService.Enabled = false', 'ProximityPromptService.Enabled = true'),
    ('a scene over the lobby', CINEMA, STORY, 'if wasIn ~= nil and now ~= wasIn and now ~= "backRooms" then', 'if false then'),
    ('a kept sound over the lobby', CINEMA, STORY, 'table.insert(kept, made)', 'local _ = made'),
    ('the drain over the lobby', SUNK, STORY, 'Cinema.onLeave(function()\n\t\t\tlocal current = drain', 'Cinema.onLeave(function()\n\t\t\tlocal current = nil'),
    ('a bubble emptied by its fade', CINEMA, STORY, 'TweenService:Create(pop, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0 }):Play()', 'local _ = pop'),
    ('standing in the way', STORYC, STORY, 'Cinema.stepAside(focus + out * ((span or reach) + 1.4), focus, 2.4)', 'local _ = span'),
    ('the hole shot from its sill', INTERACT, STORY, 'Interactables.reveal(player, secret, eye, paper.Position, paper, nil, nil, 1.3)', 'Interactables.reveal(player, secret, eye, paper.Position, paper)'),
    ('a name never declared', CINEMA, PARSE, '\tholdStill(false)\n', '\tholdStil(false)\n'),
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
