"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 109: the lobby's look. A deck with no colours of its own; a band no lighter than its inlay; an inlay too
pale; two places one colour; the zones' colours not used; the festoons never hung, not from the poles, not corner to
corner, too low, against the rails, too bright, Neon; a pole you walk through; a festoon pole in a way in; the lobby's
life going on in a level, its bubbles left behind, not popped by walking into them or a tap, their pop not the bubble
wrap's or heard everywhere, never popping alone, blown for nobody, in the game's rays, too many; never started; a
name never declared.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
CBOOT = S / "Client/Bootstrap.client.lua"
HUBS = S / "Server/Services/HubService.lua"
LAYOUT = S / "Shared/LobbyLayout.lua"
LIFE = S / "Client/Services/LobbyLife.lua"
HUB, PARSE = "check_hub.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (HUB, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('a deck with no colours', LAYOUT, HUB, '\tgarden = { inlay = Color3.fromRGB(112, 150, 104), trim = Color3.fromRGB(196, 214, 170) }, -- the lawn\n', ''),
    ('a band no lighter', LAYOUT, HUB, 'trim = Color3.fromRGB(226, 202, 150) }', 'trim = Color3.fromRGB(140, 120, 90) }'),
    ('an inlay too pale', LAYOUT, HUB, 'inlay = Color3.fromRGB(158, 144, 134)', 'inlay = Color3.fromRGB(236, 226, 216)'),
    ('two places one colour', LAYOUT, HUB, 'inlay = Color3.fromRGB(138, 102, 128)', 'inlay = Color3.fromRGB(146, 124, 88)'),
    ('the zones not used', HUBS, HUB, 'inlay.Color = if zone then zone.inlay else PALETTE.inlay', 'inlay.Color = PALETTE.inlay'),
    ('the festoons never hung', HUBS, HUB, 'local festoonOk, festoonErr = pcall(buildFestoons, folder)', 'local festoonOk, festoonErr = true, nil'),
    ('not from the poles', HUBS, HUB, 'local poles = LobbyLayout.festoonPoles(w.to)', 'local poles = { Vector3.zero, Vector3.zero, Vector3.zero, Vector3.zero }'),
    ('not corner to corner', HUBS, HUB, 'festoonString(folder, tops[1], tops[4], hang.sag, index)', 'festoonString(folder, tops[1], tops[2], hang.sag, index)'),
    ('too low', LAYOUT, HUB, 'LobbyLayout.FESTOON = { inset = 1.8, pole = 12, sag = 2 }', 'LobbyLayout.FESTOON = { inset = 1.8, pole = 9, sag = 2 }'),
    ('against the rails', LAYOUT, HUB, 'LobbyLayout.FESTOON = { inset = 1.8, pole = 12, sag = 2 }', 'LobbyLayout.FESTOON = { inset = 1.0, pole = 12, sag = 2 }'),
    ('too bright', HUBS, HUB, 'local FESTOON_LIGHT = 0.3 ', 'local FESTOON_LIGHT = 1.5 '),
    ('Neon', HUBS, HUB, '\t\t\tbulb.Material = Enum.Material.SmoothPlastic\n', '\t\t\tbulb.Material = Enum.Material.Neon\n'),
    ('a pole you walk through', HUBS, HUB, '\t\t\tpole.CanCollide = true\n', '\t\t\tpole.CanCollide = false\n'),
    ('a festoon pole in a way in', LAYOUT, HUB, 'local a = length / 2 - LobbyLayout.FESTOON.inset', 'local a = length / 2 + 3'),
    ('going on in a level', LIFE, HUB, 'local inLobby = workspace:FindFirstChild("Hub") ~= nil and player:GetAttribute("InLevel") == nil', 'local inLobby = workspace:FindFirstChild("Hub") ~= nil'),
    ('bubbles left behind', LIFE, HUB, 'for index = #bubbles, 1, -1 do\n\t\t\tpop(index, false, false)', 'for index = #bubbles, 1, -1 do\n\t\t\tlocal _ = index'),
    ('not popped by walking into them', LIFE, HUB, 'if (point - at).Magnitude < size / 2 + POP_REACH then', 'if (point - at).Magnitude < 0 then'),
    ('not popped by a tap', LIFE, HUB, 'UserInputService.InputBegan:Connect(tapped)', 'local _ = tapped'),
    ("their pop not the bubble wrap's", LIFE, HUB, 'AudioService.takesFor("bubblePop")', 'AudioService.takesFor("foamCompress")'),
    ('heard everywhere', LIFE, HUB, 's.RollOffMode = Enum.RollOffMode.InverseTapered', 's.RollOffMode = Enum.RollOffMode.Linear'),
    ('never popping alone', LIFE, HUB, 'if age >= b.life or not b.part.Parent then', 'if not b.part.Parent then'),
    ('blown for nobody', LIFE, HUB, '(camera.CFrame.Position - fountain).Magnitude < BUBBLE_NEAR', '(camera.CFrame.Position - fountain).Magnitude < 1e9'),
    ("in the game's rays", LIFE, HUB, '\tball.Reflectance = 0.3\n', '\tball.Reflectance = 0.3\n\tball.CanQuery = true\n'),
    ('too many', LIFE, HUB, 'local BUBBLES_MAX = 14', 'local BUBBLES_MAX = 60'),
    ('never started', CBOOT, HUB, '"TalkClient", "LobbyLife", "PlayerLife", "StalkerClient" }) do', '"TalkClient", "PlayerLife", "StalkerClient" }) do'),
    ('a name never declared', LIFE, PARSE, 'local at = b.from + WIND * age', 'local at = b.from + WINDS * age'),
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
