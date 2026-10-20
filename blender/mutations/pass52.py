"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 52: the storm by the Sky Pools slide. Beginning in the first half of a run or never reached; jumping instead
of easing; too dark (light or clouds); not clearing under the clouds; shown off Sky Pools or left on in the lobby;
the clouds kept grey; written every frame; lightning that is fake, harsh, left behind or always on; never moved.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
CLIENT = S / "Client/Services/SkyPoolsClient.lua"
CHECK, PARSE = "check_skypools.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (CHECK, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ("begins halfway", CLIENT, CHECK, "local STORM_FROM = 200 --", "local STORM_FROM = 420 --"),
    ("never reached", CLIENT, CHECK, "local STORM_FROM = 200 --", "local STORM_FROM = 40 --"),
    ("jumps", CLIENT, CHECK, "storm += (target - storm) * math.min(1, STORM_EASE * dt)", "storm = target"),
    ("the light drops too far", CLIENT, CHECK, "cc.Brightness = -0.06 * s", "cc.Brightness = -0.3 * s"),
    ("the clouds go too dark", CLIENT, CHECK, "local STORM_DARKEST = 0.5", "local STORM_DARKEST = 0.9"),
    ("a storm grey near black", CLIENT, CHECK, "local STORM_GREY = Color3.fromRGB(122, 130, 150)",
     "local STORM_GREY = Color3.fromRGB(40, 44, 52)"),
    ("not clearing under the clouds", CLIENT, CHECK,
     "\t\tif typeof(bottom) == \"number\" then\n\t\t\ttarget *= math.clamp((root.Position.Y - (bottom - 30)) / 30, 0, 1)\n\t\tend\n",
     ""),
    ("on every level", CLIENT, CHECK, 'Players.LocalPlayer:GetAttribute("InLevel") == "skyPools"',
     'Players.LocalPlayer:GetAttribute("InLevel") ~= nil'),
    ("left on in the lobby", CLIENT, CHECK, "\t\tif stormShade then\n\t\t\tstormGone()\n\t\tend\n\t\treturn", "\t\treturn"),
    ("the clouds kept grey", CLIENT, CHECK, "\tif next(cloudBase) ~= nil then\n\t\tpaintClouds(0)\n\tend\n", ""),
    ("written every frame", CLIENT, CHECK, "\tif key == stormWritten then\n\t\treturn\n\tend\n", ""),
    ("harsh lightning", CLIENT, CHECK, "local LIGHTNING_BRIGHT = 1.3", "local LIGHTNING_BRIGHT = 4"),
    ("lightning left behind", CLIENT, CHECK, "\t\tspot:Destroy()\n", ""),
    ("lightning all the time", CLIENT, CHECK, "if storm < 0.6 or now < nextFlash", "if now < nextFlash"),
    ("never moved", CLIENT, CHECK, "\tmoveFalls(now)\n\tmoveStorm(now)\n", "\tmoveFalls(now)\n"),
    ("a name never declared", CLIENT, PARSE, "local s = key / 100", "local s = kye / 100"),
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
