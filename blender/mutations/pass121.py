"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 121, from your test: the thing in the back rooms, jointed and walking. His seam left behind; not stooped;
not bowed; no knees; no elbows; his limbs fixed; no screen told he rushes or stops; jumped along in jerks again. On your
screen: never drawn walking; his stiff body drawn under it; jumping from place to place; the knees the ordinary way; legs
not walking; not reaching for you as he rushes; his head never turning to you, or only as far as a neck goes; feet
silent; not tipping his head as he stops; his breath twice; never started; a name never declared.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
CBOOT = S / "Client/Bootstrap.client.lua"
ROOMS = S / "Server/Services/BackRoomsService.lua"
STALK = S / "Client/Services/StalkerClient.lua"
ROOMSCHECK, PARSE = "check_backrooms.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (ROOMSCHECK, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('his seam left behind', ROOMS, ROOMSCHECK, 'welded(head, seam, CFrame.new(0, -0.08, -0.56))', 'seam.CFrame = head.CFrame'),
    ('not stooped', ROOMS, ROOMSCHECK, 'joint("Spine", hips, torso, CFrame.new(0, 0.2, 0) * CFrame.Angles(math.rad(-16), 0, 0)', 'joint("Spine", hips, torso, CFrame.new(0, 0.2, 0) * CFrame.Angles(math.rad(0), 0, 0)'),
    ('not bowed', ROOMS, ROOMSCHECK, 'joint("HeadJ", neck, head, CFrame.new(0, 0.45, 0) * CFrame.Angles(math.rad(-18), 0, 0)', 'joint("HeadJ", neck, head, CFrame.new(0, 0.45, 0) * CFrame.Angles(math.rad(0), 0, 0)'),
    ('no knees', ROOMS, ROOMSCHECK, 'joint("Knee" .. tag, thigh, shin,', 'welded(thigh, shin, CFrame.new(0, -2.55, 0))\n\t\tlocal _ = ('),
    ('no elbows', ROOMS, ROOMSCHECK, 'joint("Elbow" .. tag, upper, lower,', 'welded(upper, lower, CFrame.new(0, -2.3, 0))\n\t\tlocal _ = ('),
    ('his limbs fixed', ROOMS, ROOMSCHECK, '\tp.Anchored = false\n\tp.Massless = true', '\tp.Anchored = true\n\tp.Massless = true'),
    ('no screen told he rushes', ROOMS, ROOMSCHECK, 'model:SetAttribute("Rushing", now < rushUntil)', 'local _ = rushUntil'),
    ('no screen told he stops', ROOMS, ROOMSCHECK, 'model:SetAttribute("Paused", not walking)', 'local _ = walking'),
    ('never drawn walking', STALK, ROOMSCHECK, '\t\tanimate(one, dt, now, camera)\n', '\t\tlocal _ = animate\n'),
    ('his stiff body drawn under it', STALK, ROOMSCHECK, '\thide(real)\n', ''),
    ('jumping from place to place', STALK, ROOMSCHECK, 'one.at = one.at:Lerp(root.CFrame, 1 - math.exp(-dt * FOLLOW))', 'one.at = root.CFrame'),
    ('the knees the ordinary way', STALK, ROOMSCHECK, 'CFrame.Angles(0.75 * math.max(0, -leg) * math.min(pace, 1.2), 0, 0)', 'CFrame.Angles(-0.75 * math.max(0, -leg) * math.min(pace, 1.2), 0, 0)'),
    ('legs not walking', STALK, ROOMSCHECK, 'drive(one, "Hip" .. side, CFrame.Angles(leg * swing, 0, 0))', 'local _ = swing'),
    ('not reaching for you as he rushes', STALK, ROOMSCHECK, 'CFrame.Angles(1.4 + 0.12 * late, 0, -0.15 * sign)', 'CFrame.Angles(0.12 * late, 0, -0.15 * sign)'),
    ('his head never turning to you', STALK, ROOMSCHECK, 'if to.Magnitude < LOOK_NEAR and camera.CFrame.LookVector:Dot(-to.Unit) > 0.55 then', 'if false then'),
    ('only as far as a neck goes', STALK, ROOMSCHECK, 'local LOOK_TURN, LOOK_PITCH, LOOK_NEAR = math.rad(150),', 'local LOOK_TURN, LOOK_PITCH, LOOK_NEAR = math.rad(80),'),
    ('feet silent', STALK, ROOMSCHECK, '\t\tthud(one.at.Position, math.clamp(pace, 0.4, 1.2))\n', ''),
    ('not tipping his head as he stops', STALK, ROOMSCHECK, 'one.tilt += ((if paused then 0.7 else 0) - one.tilt)', 'one.tilt += (0 - one.tilt)'),
    ('his breath twice', STALK, ROOMSCHECK, '\t\tif item:IsA("Sound") then\n\t\t\titem:Destroy()\n\t\telseif', '\t\tif false then\n\t\t\titem:Destroy()\n\t\telseif'),
    ('never started', CBOOT, ROOMSCHECK, '"PlayerLife", "StalkerClient" }) do', '"PlayerLife" }) do'),
    ('a name never declared', STALK, PARSE, 'local pace = math.clamp(one.speed / PACE, 0, 1.8)', 'local pace = math.clamp(one.speed / PACES, 0, 1.8)'),
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
