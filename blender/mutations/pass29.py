"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 29: the launch in the Sunken City's harbour. A launch that may stand on the lighthouse, over the drain
or against a quay; a marker that can be seen or stood on, or tagged for nobody; a client never started, out
of step with the thing on the horizon or the rain, unguarded, solid, Neon, asking for more light than Roblox
gives, warm, shining on under the water or bringing a sound to import.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
CITY = S / "Server/Services/SunkenCityService.lua"
LAUNCH = S / "Client/Services/SearchlightClient.lua"
CBOOT = S / "Client/Bootstrap.client.lua"
SUNK, PARSE = "check_sunkencity.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (SUNK, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    # Where it may stand.
    ("a spot on the lighthouse", CITY, SUNK, "Vector2.new(170, 110)", "Vector2.new(150, 250)"),
    ("a spot over the drain", CITY, SUNK, "Vector2.new(150, -120)", "Vector2.new(40, -10)"),
    ("a spot against the quay, among the blocks", CITY, SUNK, "Vector2.new(90, -170)", "Vector2.new(-150, -300)"),
    ("the drain's clearance gone", CITY, SUNK, "Magnitude > VORTEX_R + 90", "Magnitude > VORTEX_R - 90"),
    ("the buoys forgotten", CITY, SUNK, "\t\t\ttable.insert(buoysAt, spot)\n", ""),
    # The marker.
    ("the marker seen", CITY, SUNK, "\t\t\tlaunch.Transparency = 1\n", "\t\t\tlaunch.Transparency = 0\n"),
    ("the marker solid", CITY, SUNK, "Enum.Material.SmoothPlastic, false)\n\t\t\tlaunch.Transparency = 1",
     "Enum.Material.SmoothPlastic, true)\n\t\t\tlaunch.Transparency = 1"),
    ("the marker tagged for nobody", CITY, SUNK, 'CollectionService:AddTag(launch, "SunkenLaunch")',
     'CollectionService:AddTag(launch, "SunkenBoat")'),
    ("what it watches never read", LAUNCH, SUNK, 'marker:GetAttribute("Watch")', 'marker:GetAttribute("Looks")'),
    # The client.
    ("the client never started", CBOOT, SUNK, ', "SearchlightClient", "CosmeticsClient",', ', "CosmeticsClient",'),
    ("out of step with the thing", LAUNCH, SUNK, "local THING_RISE, THING_HOLD, THING_SINK = 9, 12, 10",
     "local THING_RISE, THING_HOLD, THING_SINK = 9, 20, 10"),
    ("its own idea of the rain", LAUNCH, SUNK, "\treturn ((t - first) % every) < length\n",
     "\treturn ((t - first) % every) > length\n"),
    ("the step unguarded", LAUNCH, SUNK, "local ok, err = pcall(stepLaunch, launch, now, dt)",
     "local ok, err = true, stepLaunch(launch, now, dt)"),
    ("Neon on the launch", LAUNCH, SUNK, "\tp.Material = Enum.Material.SmoothPlastic\n",
     "\tp.Material = Enum.Material.Neon\n"),
    ("the launch solid", LAUNCH, SUNK, "\tp.CanCollide = false\n", "\tp.CanCollide = true\n"),
    ("more light than Roblox gives", LAUNCH, SUNK, "\tspot.Range = 60\n", "\tspot.Range = 90\n"),
    ("the beam on under the water", LAUNCH, SUNK, "long = math.min(BEAM_LONGEST, (height - 1) / -look.Y)",
     "long = BEAM_LONGEST"),
    ("a sound to import", LAUNCH, SUNK, "\tspot.Parent = lamp\n", '\tspot.Parent = lamp\n\tInstance.new("Sound").Parent = lamp\n'),
    ("a warm searchlight", LAUNCH, SUNK, "local COLD = Color3.fromRGB(222, 234, 255)",
     "local COLD = Color3.fromRGB(255, 240, 212)"),
    ("each player's own clock", LAUNCH, SUNK, "local now = workspace:GetServerTimeNow()", "local now = os.clock()"),
    # The code still reads.
    ("a name never declared", LAUNCH, PARSE, "local t = if epoch then now - epoch else -1",
     "local t = if epoch then now - epoch else -one"),
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
