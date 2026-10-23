"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 100: the lobby as a promenade. A level pad off the arc, its window on the wrong edge, the windows Neon
again; the rails' coping or the decks' bands Neon; a deck or a walk without its rails; piers short of the sea or too
far apart; who is in the room counted by distance again; a planter past its inlay, a lamp in the way onto a walk or on
the way to the start; two decks overlapping; the pads crowding on too narrow an arc; the statue off the deck; you
arriving off the plaza; the squish room's lift letting you out behind itself, or standing somewhere of its own; the
back corridor's turn walled off again, or the house's door shut; the doorframe sunk in the deck; the chest facing the
old room; the layout left out of the paste check; a name never declared.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
BOOT = S / "Server/Bootstrap.server.lua"
HUBS = S / "Server/Services/HubService.lua"
LAYOUT = S / "Shared/LobbyLayout.lua"
SQUISHS = S / "Server/Services/SquishRoomService.lua"
HUB, ROOMSCHECK, SQUISHCHECK, PARSE = "check_hub.py", "check_backrooms.py", "check_squishroom.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (HUB, ROOMSCHECK, SQUISHCHECK, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('a level pad off the arc', HUBS, HUB, 'pad.CFrame = CFrame.new(HUB_ORIGIN) * LobbyLayout.arc(count)[index]', 'pad.Position = HUB_ORIGIN + Vector3.new((index - 1) * 12, 1.7, -20)'),
    ('the window on the wrong edge', HUBS, HUB, 'window.CFrame = pad.CFrame * CFrame.new(0, 6.2, PAD_SIZE.Z / 2)', 'window.CFrame = pad.CFrame * CFrame.new(0, 6.2, -PAD_SIZE.Z / 2)'),
    ('the windows Neon again', HUBS, HUB, 'window.Material = Enum.Material.Glass', 'window.Material = Enum.Material.Neon'),
    ("the rails' coping Neon", HUBS, HUB, '\tcap.Material = Enum.Material.Marble\n', '\tcap.Material = Enum.Material.Neon\n'),
    ("the decks' bands Neon", HUBS, HUB, 'trim.Material = Enum.Material.Marble', 'trim.Material = Enum.Material.Neon'),
    ('a deck without its rail', HUBS, HUB, '\t\trailDeck(folder, name)\n', ''),
    ('a walk without its rails', HUBS, HUB, '\t\trailWalk(folder, w.to)\n', ''),
    ('piers short of the sea', HUBS, HUB, 'local drop = LobbyLayout.SEA_DROP + 4', 'local drop = LobbyLayout.SEA_DROP - 40'),
    ('piers too far apart', HUBS, HUB, 'local across = math.max(2, math.ceil((w - 6) / 30) + 1)', 'local across = math.max(2, math.ceil((w - 6) / 60) + 1)'),
    ('the room counted by distance', HUBS, HUB, 'LobbyLayout.over(offset, 6)', 'offset.Magnitude < 120'),
    ('a planter past its inlay', LAYOUT, HUB, '{ x = 120, z = 28 }', '{ x = 124, z = 30 }'),
    ('a lamp in the way onto a walk', LAYOUT, HUB, '{ x = 84, z = -16 }', '{ x = 84, z = -6 }'),
    ('a lamp on the way to the start', LAYOUT, HUB, '{ x = 10.5, z = -63 }', '{ x = 2, z = -63 }'),
    ('two decks overlapping', LAYOUT, HUB, 'fame = { x = 104, z = 0, w = 56, d = 76 }', 'fame = { x = 64, z = 0, w = 56, d = 76 }'),
    ('the pads crowding', LAYOUT, HUB, 'ARC = { radius = 30, spread = 172 }', 'ARC = { radius = 30, spread = 50 }'),
    ('the statue off the deck', LAYOUT, HUB, 'statue = Vector3.new(104, 3.5, -22)', 'statue = Vector3.new(104, 5, -22)'),
    ('arriving off the plaza', LAYOUT, HUB, 'spawn = Vector3.new(0, 1.5, -22)', 'spawn = Vector3.new(0, 1.5, -62)'),
    ('the lift letting you out behind it', SQUISHS, SQUISHCHECK, 'room.lobbyArrive = base + Vector3.new(7, 3.5, 0)', 'room.lobbyArrive = base + Vector3.new(-7, 3.5, 0)'),
    ('the lift somewhere of its own', SQUISHS, SQUISHCHECK, 'local LOBBY_LIFT_AT = LobbyLayout.AT.lift', 'local LOBBY_LIFT_AT = Vector3.new(38, 1, -35)'),
    ("the corridor's turn walled off", HUBS, ROOMSCHECK, 'slab("BackWall", Vector3.new(8.7, 6.6, 0.4), CFrame.new(6.45, 3.3, 7.2)', 'slab("BackWall", Vector3.new(9, 6.6, 0.4), CFrame.new(2.3, 3.3, 7.2)'),
    ("the house's door shut", HUBS, ROOMSCHECK, '{ Vector3.new(4.2, 1, 0.5), CFrame.new(0, 6.9, -1.25) }', '{ Vector3.new(4.2, 7.4, 0.5), CFrame.new(0, 3.7, -1.25) }'),
    ('the doorframe sunk', HUBS, ROOMSCHECK, 'propAt("Hub_Doorframe", at + Vector3.new(0, 3.2, 0), parent, facing)', 'propAt("Hub_Doorframe", at, parent, facing)'),
    ('the chest facing the old room', HUBS, HUB, 'local face = CFrame.lookAt(at, Vector3.new(ARCADE.X, at.Y, ARCADE.Z))', 'local face = CFrame.lookAt(at, Vector3.new(HUB_ORIGIN.X, at.Y, HUB_ORIGIN.Z + 20))'),
    ('the layout left out of the paste check', BOOT, HUB, '"LevelDefinitions",\n\t\t"LobbyLayout", ', '"LevelDefinitions",\n\t\t'),
    ('a name never declared', LAYOUT, PARSE, 'local deck = (LobbyLayout.DECKS :: any)[name]', 'local deck = (LobbyLayouts.DECKS :: any)[name]'),
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
