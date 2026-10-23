"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 120, from your test: your character alive, and acting the key's scene. Your head never following, or
twisting round when you look back; a fidget or your head over a scene, a line being told, an emote, a seat, a ride or the
water; a fidget going on as you walk off; posed before the animations; a shop emote given away as a fidget, or one Poses
does not make; no way to ask who is emoting; never started. At Hill House: no door to go to, never going to it, the key
never in your hand, leaving its hook too soon, standing still to take it, posed before the animations, your walk left
slow, the last shot not following you; a name never declared.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
CBOOT = S / "Client/Bootstrap.client.lua"
EMOTEC = S / "Client/Services/EmoteService.lua"
HILLC = S / "Client/Services/HillHouseClient.lua"
HOUSE = S / "Server/Services/HillHouseService.lua"
PLIFE = S / "Client/Services/PlayerLife.lua"
HILL, SHOTS, STORY, PARSE = "check_hillhouse.py", "check_shots.py", "check_story.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (HILL, SHOTS, STORY, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('your head never following', PLIFE, STORY, 'Poses.drive(neck, CFrame.Angles(life.pitch, life.yaw * (1 - share), 0))', 'local _ = neck'),
    ('twisting round when you look back', PLIFE, STORY, 'if math.abs(yaw) > HEAD.behind then\n\t\tyaw, pitch = 0, 0', 'if false then\n\t\tyaw, pitch = 0, 0'),
    ('over a scene', PLIFE, STORY, 'if (mine and inScene) or busy(player, model, humanoid) then', 'if busy(player, model, humanoid) then'),
    ('over a line being told', PLIFE, STORY, 'model:GetAttribute("GestureAt"), model:GetAttribute("GestureFor")', 'model:GetAttribute("SaidAt"), model:GetAttribute("GestureFor")'),
    ('over an emote', PLIFE, STORY, 'emotes.isPlaying(player)', 'emotes.isPlaying(me)'),
    ('on a seat, a ride or the water', PLIFE, STORY, 'humanoid.Sit or humanoid.PlatformStand or state == Enum.HumanoidStateType.Swimming', 'humanoid.Sit'),
    ('a fidget going on as you walk off', PLIFE, STORY, 'if not standing or t >= fidget.seconds then', 'if t >= fidget.seconds then'),
    ('posed before the animations', PLIFE, STORY, 'RunService.Stepped:Connect(function(_, dt: number)', 'RunService.RenderStepped:Connect(function(dt: number)'),
    ('a shop emote given away', PLIFE, STORY, '{ pose = "ponder", seconds = 3.2 },', '{ pose = "stretch", seconds = 3.2 },'),
    ('one Poses does not make', PLIFE, STORY, '{ pose = "lookAround", seconds = 4 },', '{ pose = "lookRound", seconds = 4 },'),
    ('no way to ask who is emoting', EMOTEC, STORY, 'function EmoteService.isPlaying(player: Player): boolean', 'function EmoteService.emoting(player: Player): boolean'),
    ('never started', CBOOT, STORY, '"LobbyLife", "PlayerLife", "StalkerClient" }) do', '"LobbyLife", "StalkerClient" }) do'),
    ('no door to go to', HOUSE, HILL, 'model:SetAttribute("HallDoor", hall.door)', 'model:SetAttribute("HallExit", hall.door)'),
    ('never going to it', HILLC, HILL, 'humanoid:MoveTo(door)', 'local _ = door'),
    ('the key never in your hand', HILLC, HILL, 'current.handKey = keyInHand(character)', 'current.handKey = nil'),
    ('leaving its hook too soon', HILLC, HILL, 'if not current.keyed and t >= KEY_TAKEN then', 'if not current.keyed and t >= 0 then'),
    ('standing still to take it', HILLC, HILL, 'local function heldPose(name: string, t: number): CFrame?', 'local function heldPose(_: string, t: number): CFrame?\n\tlocal name = ""'),
    ('posed before the animations at Hill House', HILLC, HILL, 'RunService.Stepped:Connect(function()\n\t\tlocal ok, err = pcall(poseScene)', 'RunService.RenderStepped:Connect(function()\n\t\tlocal ok, err = pcall(poseScene)'),
    ('your walk left slow', HILLC, HILL, 'if humanoid and current.speed then\n\t\thumanoid.WalkSpeed = current.speed', 'if humanoid and current.speed then\n\t\tlocal _ = current.speed'),
    ('the last shot not following you', HILLC, SHOTS, 'Cinema.point(CFrame.lookAt(back, here + Vector3.new(0, 0.4, 0)), 50)', 'Cinema.point(CFrame.lookAt(back, spot.Position + Vector3.new(0, 0.4, 0)), 50)'),
    ('a name never declared', PLIFE, PARSE, 'local look = root.CFrame:VectorToObjectSpace(camera.CFrame.LookVector)', 'local look = root.CFrame:VectorToObjectSpace(cam.CFrame.LookVector)'),
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
