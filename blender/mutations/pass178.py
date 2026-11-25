"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 178: leaving lets go. A late arrival finishing the next run; a ride, a slide or a drain moving you or finishing a run after you left; a ride left behind owning the next level's falls; the scene's words over the lobby.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
BOOT = S / "Server/Bootstrap.server.lua"
CINEMA = S / "Client/Services/Cinema.lua"
CITY = S / "Server/Services/SunkenCityService.lua"
DIVE = S / "Server/Services/DiveFinaleService.lua"
HALLS = S / "Server/Services/FloodedHallsService.lua"
SKY = S / "Server/Services/SkyPoolsService.lua"
LETGO = "check_letgo.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (LETGO,):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('finishFrom taking any level', BOOT, LETGO, 'if run == nil or levelInstance ~= run or not finishRunFor then', 'if run == nil or not finishRunFor then'),
    ('the slide finishing straight', BOOT, LETGO, 'local unride = SkyPoolsService.attachSlide(built :: Model, finishFrom(levelInstance))', 'local unride = SkyPoolsService.attachSlide(built :: Model, function(player) if finishRunFor then finishRunFor(player) end end)'),
    ('completeRun for someone home', BOOT, LETGO, 'if not levelInstance or not HubService.isInRun(player) then', 'if not levelInstance then'),
    ('the flume running on', HALLS, LETGO, 'if f >= 1 or not root.Parent or not stillHere() then', 'if f >= 1 or not root.Parent then'),
    ('the gate chamber after you left', HALLS, LETGO, 'if stillHere() then\n\t\t\t\t\troot.AssemblyLinearVelocity = Vector3.zero\n\t\t\t\t\troot.CFrame = arrive', 'if true then\n\t\t\t\t\troot.AssemblyLinearVelocity = Vector3.zero\n\t\t\t\t\troot.CFrame = arrive'),
    ('the flume arriving after you left', HALLS, LETGO, 'if stillHere() then\n\t\t\t\tarrivedAt[player] = os.clock()', 'if true then\n\t\t\t\tarrivedAt[player] = os.clock()'),
    ('the halls not asking InLevel', HALLS, LETGO, 'and halls.Parent ~= nil and player:GetAttribute("InLevel") == "floodedHalls"', 'and halls.Parent ~= nil'),
    ('a flume left behind owning falls', HALLS, LETGO, 'if player:GetAttribute("InLevel") ~= "floodedHalls" then\n\t\treturn false', 'if false then\n\t\treturn false'),
    ('the slide setting you down after you left', SKY, LETGO, 'local here = stillHere()\n\t\t\tif root.Parent and here then', 'local here = stillHere()\n\t\t\tif root.Parent then'),
    ('a slide left behind owning falls', SKY, LETGO, 'if player:GetAttribute("InLevel") ~= "skyPools" then\n\t\treturn false', 'if false then\n\t\treturn false'),
    ('the drain running on', CITY, LETGO, 'while root.Parent and stillHere() do', 'while root.Parent do'),
    ('the drain finishing after you left', CITY, LETGO, 'if onArrive and stillHere() then\n\t\tonArrive(player)', 'if onArrive then\n\t\tonArrive(player)'),
    ('a drain left behind owning falls', CITY, LETGO, 'if player:GetAttribute("InLevel") ~= "sunkenCity" then\n\t\treturn false', 'if false then\n\t\treturn false'),
    ('a dive left behind owning falls', DIVE, LETGO, 'if level == nil or level == "backRooms" then\n\t\treturn false', 'if level == "backRooms" then\n\t\treturn false'),
    ('the words staying over the lobby', CINEMA, LETGO, 'if now and current.words then', 'if false and current.words then'),
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
