"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 53: the Flooded Halls lamps behind you. Roof lights not saying where they hang; a failed lamp going dark;
the one over you failing; changes at once; a stutter that goes out or drags; the windows failing too; the
server's failing fitting fought over; failing off the level or in the ending; only the panel dimmed; never
coming back; a late join stuttering; an old fade fighting a new one; never stepped.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
SERVICE = S / "Server/Services/FloodedHallsService.lua"
CLIENT = S / "Client/Services/FloodedHallsClient.lua"
CHECK, PARSE = "check_halls.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (CHECK, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ("not saying where it hangs", SERVICE, CHECK, '\t\troof:SetAttribute("Along", leg.startAt + along)\n', ""),
    ("a failed lamp goes dark", CLIENT, CHECK, "local LAMP_GLOW = 0.3", "local LAMP_GLOW = 0.05"),
    ("the one over you fails", CLIENT, CHECK, "local LAMPS_KEPT = 2", "local LAMPS_KEPT = 0"),
    ("off at once", CLIENT, CHECK, "local LAMP_FADE = 1.2", "local LAMP_FADE = 0.1"),
    ("on at once", CLIENT, CHECK, "local LAMP_BACK = 0.8", "local LAMP_BACK = 0"),
    ("a stutter that goes out", CLIENT, CHECK, "{ { 0.18, 0.06 }, { 1, 0.08 }", "{ { 0, 0.06 }, { 1, 0.08 }"),
    ("a stutter that drags", CLIENT, CHECK, "{ 0.85, 0.12 } }", "{ 0.85, 2 } }"),
    ("the windows fail too", CLIENT, CHECK, '(item.Name == "RoofLight" or item.Name == "PendantLight") and not lamps[item]',
     '(item.Name == "LightSlot" or item.Name == "PendantLight") and not lamps[item]'),
    ("the failing fitting fought over", CLIENT, CHECK, 'not lamps[item]\n\t\t\t\tand not item:GetAttribute("Failing")', 'not lamps[item]'),
    ("on every level", CLIENT, CHECK, 'Players.LocalPlayer:GetAttribute("InLevel") ~= "floodedHalls" or scene ~= nil',
     'Players.LocalPlayer:GetAttribute("InLevel") == nil'),
    ("only the panel dimmed", CLIENT, CHECK, "light.Brightness = lamp.bright * level", "light.Brightness = lamp.bright"),
    ("never back", CLIENT, CHECK, "\t\t\trelightLamp(part, lamp)\n", "\t\t\tlamp.fresh = false\n"),
    ("a late join stutters", CLIENT, CHECK, "\t\t\t\tsetLamp(part, lamp, LAMP_GLOW)\n", "\t\t\t\tfailLamp(part, lamp)\n"),
    ("an old fade fights", CLIENT, CHECK, "if lamp.turn ~= turn or not part.Parent then", "if not part.Parent then"),
    ("never stepped", CLIENT, CHECK, "local ok, err = pcall(stepLamps)", "local ok, err = true, nil"),
    ("a name never declared", CLIENT, PARSE, "local behind = here - (LAMPS_KEPT + 0.5) * LAMP_BAY",
     "local behind = hear - (LAMPS_KEPT + 0.5) * LAMP_BAY"),
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
               if line.startswith("  ") or line.startswith("FAIL") or line.startswith("FloodedHalls")][:2]
        print("%-8s %s  %s" % ("caught" if caught else "MISSED", label, "; ".join(why)[:170]))
        if not caught:
            missed.append(label)
finally:
    for path, data in originals.items():
        path.write_bytes(data)
print("\n%d of %d caught" % (len(MUTATIONS) - len(missed), len(MUTATIONS)))
sys.exit(1 if missed else 0)
