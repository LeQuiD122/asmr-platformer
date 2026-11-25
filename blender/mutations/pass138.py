"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 138: a checkpoint reached, felt. Never said, or said at every touch; not new ground after a run starts or
a Hardcore fall; RunFeel never started; the slab you start on said, or one said over a scene; the same take twice
running; the ring past the slab's edge, a lit block for a light, left lying there, or in your way; a slot the sheet
does not have, in the game or in its generator.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
BOOT = S / "Server/Bootstrap.server.lua"
CBOOT = S / "Client/Bootstrap.client.lua"
CHECKGEN = ROOT / "audio/gen_checkpoint_sfx.py"
RUNFEEL = S / "Client/Services/RunFeel.lua"
POLISH = "check_polish.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (POLISH,):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('a checkpoint never said', BOOT, POLISH, 'player:SetAttribute("Checkpoint", entry.index)', 'local _ = entry'),
    ('every touch said', BOOT, POLISH, 'if reached and entry.index > (reached.furthest or 0) then', 'if reached then'),
    ('not new ground after a run starts', BOOT, POLISH, 'progression(player, "start")\n\t\tplayer:SetAttribute("Checkpoint", 0)', 'progression(player, "start")'),
    ("a Hardcore fall's ground not new", BOOT, POLISH, '\t\t-- From nothing again: every checkpoint is new ground (RunFeel).\n\t\tplayer:SetAttribute("Checkpoint", 0)\n', ''),
    ('never started', CBOOT, POLISH, '"RunFeel", "StalkerClient" }) do', '"StalkerClient" }) do'),
    ("the start's own slab said", RUNFEEL, POLISH, 'local further = now > furthest and now > 1', 'local further = now > furthest'),
    ('said over a scene', RUNFEEL, POLISH, 'if level == nil or level == "backRooms" or inScene() then', 'if level == nil then'),
    ('the same take twice running', RUNFEEL, POLISH, 'if take == lastTake then', 'if false then'),
    ('the ring off the slab', RUNFEEL, POLISH, 'local RING = { reach = 0.92,', 'local RING = { reach = 1.6,'),
    ('a lit block for a light', RUNFEEL, POLISH, 'local glow = Instance.new("PointLight")', 'local glow = Instance.new("SpotLight")'),
    ('the ring left lying there', RUNFEEL, POLISH, 'game:GetService("Debris"):AddItem(plate, RING.seconds + RING.second + 0.6)', 'local _ = plate'),
    ('the plate in your way', RUNFEEL, POLISH, 'plate.CanCollide = false', 'plate.CanCollide = true'),
    ('a slot the sheet does not have', RUNFEEL, POLISH, 'local CHIME = { takes = 3, slot = 1.5,', 'local CHIME = { takes = 3, slot = 1.2,'),
    ('a slot its generator does not write', CHECKGEN, POLISH, 'SLOT = 1.5\n', 'SLOT = 1.3\n'),
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
