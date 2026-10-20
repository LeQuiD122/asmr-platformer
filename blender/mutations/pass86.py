"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 86: the lockers and the secrets' scenes. A locker's door swinging back into it; a locker solid again, or
without its lid; holding nothing, its lamp never on, or lit with Neon; your coat or your card not in Locker 3,
Marsh's locker empty, an empty one without even a hanger; a second look playing the whole scene, or one from an
earlier session, or the client never told; the two-shot not from the side, not choosing the side with room,
swapping sides, or keeping the last scene's; the close look not close or not in front; a second look as long as the
first, stinging again or putting its card up again; a name never declared.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
INTERACT = S / "Server/Services/Interactables.lua"
STORYC = S / "Client/Services/StoryClient.lua"
STORY, PARSE = "check_story.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (STORY, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('the door swinging in', INTERACT, STORY, 'swing(door, hinge, math.rad(105), 0.9)', 'swing(door, hinge, -math.rad(105), 0.9)'),
    ('a solid block again', INTERACT, STORY, 'piece(parent, "LockerSide"', 'piece(parent, "LockerPanel"'),
    ('no lid', INTERACT, STORY, 'piece(parent, "LockerLid"', 'piece(parent, "LockerCap"'),
    ('holding nothing', INTERACT, STORY, '\tlockerHolds(parent, base, door, opts.secret)\n', ''),
    ('the lamp never on', INTERACT, STORY, 'TweenInfo.new(0.5), { Brightness = 0.9 }):Play()', 'TweenInfo.new(0.5), { Brightness = 0 }):Play()'),
    ('lit with Neon', INTERACT, STORY, 'piece(parent, "LockerLid"', 'local _neon = Enum.Material.Neon\n\tpiece(parent, "LockerLid"'),
    ('your coat not there', INTERACT, STORY, 'if what == "locker" then', 'if what == "lockers" then'),
    ('your card not there', INTERACT, STORY, 'piece(parent, "KeyHolderCard"', 'piece(parent, "Card"'),
    ("Marsh's locker empty", INTERACT, STORY, 'elseif what == "marsh" then', 'elseif what == "marshes" then'),
    ('not even a hanger', INTERACT, STORY, 'bit("WireHanger"', 'bit("Wire"'),
    ('a second look in full', INTERACT, STORY, 'not the whole scene and its card over again.\n\tlocal again = mine[id] == true\n', 'not the whole scene and its card over again.\n\tlocal again = false\n'),
    ("an earlier session's look in full", INTERACT, STORY, '\t\tagain = again or kept["secret:" .. noteTitle] == true\n', ''),
    ('the client never told', INTERACT, STORY, 'think = if secret.think then secret.think[2] else nil, again = again,', 'think = if secret.think then secret.think[2] else nil,'),
    ('the two-shot from behind', STORYC, STORY, 'mid + right * side * reach - forward * reach * 0.35', 'mid + right * side * 0.4 - forward * reach'),
    ('no side with room', STORYC, STORY, 'twoShotSide = if math.max(rightRoom, leftRoom) < 3.2 then 0 elseif', 'twoShotSide = if false then 0 elseif'),
    ('swapping sides', STORYC, STORY, '\tif not twoShotSide then\n', '\tif true then\n'),
    ("the last scene's side kept", STORYC, STORY, '\tbarInHands(false)\n\ttwoShotSide = nil\n', '\tbarInHands(false)\n'),
    ('the close look not close', STORYC, STORY, 'Magnitude * 0.5, 1.9, 3.4)', 'Magnitude * 0.5, 6, 9)'),
    ('the close look not in front', STORYC, STORY, 'local want = focus + out * (reach - 0.7 * u)', 'local want = focus - out * (reach - 0.7 * u)'),
    ('a second look as long', STORYC, STORY, 'local closing = if again then 3 else MOMENT.close', 'local closing = MOMENT.close'),
    ('a second look stinging', STORYC, STORY, '\tif not again then\n\t\tsound("SecretSting"', '\tif true then\n\t\tsound("SecretSting"'),
    ("a second look's card", STORYC, STORY, '\t\t\tif not again then\n\t\t\t\tcard(', '\t\t\tif true then\n\t\t\t\tcard('),
    ('a name never declared', STORYC, PARSE, 'local reach = math.clamp((eye.Position - focus)', 'local reach = math.clamp((eyes.Position - focus)'),
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
