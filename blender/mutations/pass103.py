"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 103: the back rooms. The lights going out round him; the way back open to someone who fell in; how you came
forgotten; the way back putting you at the spawn, or on the corridor's way in; the carpet felt again; him seen moving
smoothly, his face with no seam; the screamer silent; your heart not quickening; the door lit for someone who fell
in; the back rooms' light left on.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
BOOT = S / "Server/Bootstrap.server.lua"
HUBS = S / "Server/Services/HubService.lua"
ROOMS = S / "Server/Services/BackRoomsService.lua"
STORYC = S / "Client/Services/StoryClient.lua"
ROOMSCHECK = "check_backrooms.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (ROOMSCHECK,):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('the lights out round him', ROOMS, ROOMSCHECK, 'light.Brightness = LIGHT_BRIGHTNESS * (if math.random() < 0.6 then 0.12 else 0.4)', 'light.Brightness = LIGHT_BRIGHTNESS * (if math.random() < 0.6 then 0 else 0.4)'),
    ('the way back for someone who fell in', ROOMS, ROOMSCHECK, 'walker:GetAttribute("BackRoomsFrom") == "lobby"', 'walker:GetAttribute("BackRoomsFrom") ~= nil'),
    ('how you came forgotten', BOOT, ROOMSCHECK, 'player:SetAttribute("BackRoomsFrom", how or "fall")', 'player:SetAttribute("BackRoomsFrom", "lobby")'),
    ('back to the spawn', HUBS, ROOMSCHECK, 'hrp.CFrame = at or CFrame.new(HubService.spawnPosition())', 'hrp.CFrame = CFrame.new(HubService.spawnPosition())'),
    ('back onto the way in', HUBS, ROOMSCHECK, 'backReturnAt = CFrame.lookAt((turn * CFrame.new(5.2, 3, 10)).Position', 'backReturnAt = CFrame.lookAt((turn * CFrame.new(9.0, 3, 10)).Position'),
    ('the carpet felt again', ROOMS, ROOMSCHECK, 'CARPET, Enum.Material.Carpet, made)', 'CARPET, Enum.Material.Fabric, made)'),
    ('him moving smoothly', ROOMS, ROOMSCHECK, 'nextFrame = now + 0.14 + math.random() * 0.18', 'nextFrame = now'),
    ('his face with no seam', ROOMS, ROOMSCHECK, 'local seam = decor(model, "Seam"', 'local seam = decor(model, "Mark"'),
    ('the screamer silent', STORYC, ROOMSCHECK, 'sound("ScreamerStab", "rbxasset://sounds/bass.mp3", 1, 1)', 'sound("ScreamerStab", nil, 0, 1)'),
    ('your heart not quickening', STORYC, ROOMSCHECK, 'heart.PlaybackSpeed = 0.85 + 0.6 * near', 'heart.PlaybackSpeed = 1'),
    ('the door lit for a faller', STORYC, ROOMSCHECK, 'local open = Players.LocalPlayer:GetAttribute("BackRoomsFrom") == "lobby"', 'local open = true'),
    ("the back rooms' light left on", STORYC, ROOMSCHECK, 'backRoomsLight(down)', 'backRoomsLight(true)'),
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
