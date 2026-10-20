"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 27: the squish room. Slabs that are only pictures or float above the floor, a material left out, a
pit you cannot jump out of or no pit at all, a hall open to the sky, a room inside a level's horizon, a
lamp of Neon, a lobby lift left hanging during a run or standing on the pads, and a room that lets the
lobby's vote drag you out of it, drops you into the void on the way back, or forgets you on a respawn.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
ROOM = S / "Server/Services/SquishRoomService.lua"
CLIENT = S / "Client/Services/SquishRoomClient.lua"
HUB = S / "Server/Services/HubService.lua"
LAYOUT = S / "Shared/LobbyLayout.lua"
BOOT = S / "Server/Bootstrap.server.lua"
CBOOT = S / "Client/Bootstrap.client.lua"
CHECK, PARSE = "check_squishroom.py", "check_luau_syntax.py"
HUBCHECK = "check_hub.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (CHECK, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ("slabs that are only pictures", ROOM, CHECK, "DeformationService.registerPlatform(piece)", "DeformationService.restoreAll()"),
    ("a slab floating over the floor", ROOM, CHECK, "CFrame.new(Vector3.new(cx, y, cz) - pad.centreOffset) * rotation",
     "CFrame.new(Vector3.new(cx, y + 3, cz)) * rotation"),
    ("a list of materials kept by hand", ROOM, CHECK, "for name in pairs(Materials) do", 'for _, name in ipairs({ "Honey", "Soap" }) do'),
    ("a pit too deep to jump out of", ROOM, CHECK, "local PIT_MAX = 6.4", "local PIT_MAX = 12"),
    ("no pit floor", ROOM, CHECK, 'part(folder, "PitFloor"', 'part(folder, "PitLid"'),
    ("open to the sky", ROOM, CHECK, 'part(folder, "Ceiling"', 'part(folder, "Canopy"'),
    ("inside a level's horizon", ROOM, CHECK, "local ROOM_ORIGIN = Vector3.new(9000, 600, 9000)",
     "local ROOM_ORIGIN = Vector3.new(3000, 600, 3000)"),
    ("a Neon lamp", ROOM, CHECK, "PALETTE.lamp, false)\n\t\t\tlocal light", "PALETTE.lamp, false, Enum.Material.Neon)\n\t\t\tlocal light"),
    ("signs on nothing", ROOM, CHECK, 'part(folder, "SignLeg"', 'part(folder, "SignPeg"'),
    ("a lobby lift left hanging in a run", ROOM, CHECK, "local prompt = buildLift(hub, liftBase,", "local prompt = buildLift(workspace, liftBase,"),
    ("a lobby lift on the benches", LAYOUT, HUBCHECK, "lift = Vector3.new(-38, 1, 104)", "lift = Vector3.new(-26, 1, 113)"),
    ("a lobby lift facing away", ROOM, CHECK, "local liftBase = CFrame.lookAt(base, base + Vector3.new(1, 0, 0))",
     "local liftBase = CFrame.lookAt(base, base + Vector3.new(-1, 0, 0))"),
    ("dragged out by a vote", HUB, CHECK, 'if not inRun[player] and not player:GetAttribute("InSquishRoom") and ',
     "if not inRun[player] and "),
    ("back into the void", ROOM, CHECK, 'if not back or not workspace:FindFirstChild("Hub") then', "if not back then"),
    ("shut without a word", ROOM, CHECK, 'tell(player, "closed")', 'tell(player, "shut")'),
    ("forgotten on a respawn", ROOM, CHECK, '\t\t\tif not player:GetAttribute("InSquishRoom") then\n\t\t\t\treturn\n\t\t\tend\n',
     "\t\t\tdo return end\n"),
    ("never built", BOOT, CHECK, "(require(squishModule) :: any).build(HubService.origin())", "(require(squishModule) :: any).start()"),
    ("no fade on the client", CBOOT, CHECK, ', "SquishRoomClient",', ","),
    ("a name never declared in the hall", ROOM, PARSE, "\t\tlocal rowZ0, rowZ1 = z, z + row.depth\n",
     "\t\tlocal rowZ0, rowZ1 = z, z + row.deep + nope\n"),
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
