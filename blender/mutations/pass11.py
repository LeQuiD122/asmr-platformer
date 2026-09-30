"""Each mutation must make its checker fail. Files are restored byte for byte whatever happens."""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
SERVER = ROOT / "src/Server/Services/SunkenCityService.lua"
CLIENT = ROOT / "src/Client/Services/SunkenCityClient.lua"
NPC = ROOT / "src/Server/Services/Townsfolk.lua"
RIG = ROOT / "src/Shared/SeaRig.lua"
DEFORM = ROOT / "src/Client/Services/DeformationRenderer.lua"
CINEMA = ROOT / "src/Client/Services/Cinema.lua"
CITY = "check_sunkencity.py"

MUTATIONS = [
    ("the client waits forever for SeaRig", CLIENT, CITY, 'WaitForChild("SeaRig", 15)', 'WaitForChild("SeaRig")'),
    ("the gallery fills in a flash again", SERVER, CITY, "\trise = 8,", "\trise = 3.5,"),
    ("the pane just vanishes", SERVER, CITY, "\t\tshatter(pane, inward, was)\n", "\t\tlocal _ = inward\n"),
    ("the shards made before the glass's Random", SERVER, CITY,
     "\tlocal rng = Random.new(1847)\n\n\t-- ===== THE SEA", "\tlocal rng0 = Random.new(1847)\n\n\t-- ===== THE SEA"),
    ("the teeth left in a whole pane", SERVER, CITY, "for _, bit in ipairs(flood.bits) do", "for _, bit in ipairs({}) do"),
    ("the client drawing its own water too", CLIENT, CITY, "local function clearFlood()",
     'local _ = function() return localPart(workspace, "FloodWater", Vector3.one, BODY, false) end\nlocal function clearFlood()'),
    ("nobody else sees the rider flail", SERVER, CITY,
     'remote:FireAllClients("flail", player, began, total, seconds)', 'remote:FireClient(player, "flail", player, began, total, seconds)'),
    ("a stale client unexplained", SERVER, CITY, "did not take the ride down the drain", "never rode"),
    ("the client mistaking the flail for a ride", CLIENT, CITY, 'if first == "flail" then', 'if first == "flails" then'),
    ("the rider stiff and upright again", CLIENT, CITY,
     "SunkenPath.drainFrame(current.spec, u) * SunkenPath.tumble(u, clock)",
     "SunkenPath.drainFrame(current.spec, u)"),
    ("the flail set before the animations", CLIENT, CITY,
     "RunService.Stepped:Connect(function()", "RunService.Heartbeat:Connect(function()"),
    ("the rider's joints left flailing", CLIENT, CITY, "Poses.drive(joint, CFrame.identity)", "local _ = joint"),
    ("the camera never given back", CINEMA, CITY,
     "camera.CameraType = Enum.CameraType.Custom", "camera.CameraType = Enum.CameraType.Scriptable"),
    ("the next character dragged down the drain", CLIENT, CITY,
     "if character ~= current.who or not (root", "if not (root"),
    ("the scene running on after the ride", CLIENT, CITY,
     "\tdrain = nil\n\tcutscene.finish()\nend\n\n-- ===== WHAT LIVES", "\tdrain = nil\nend\n\n-- ===== WHAT LIVES"),
    ("one broken animal stopping the rest", CLIENT, CITY,
     "local ok, err = pcall(moveOneSwimmer, s, clock)", "local ok, err = true, moveOneSwimmer(s, clock)"),
    ("the Studio panel in a published game", CLIENT, CITY, "if not RunService:IsStudio() then", "if false then"),
    ("the jellyfish's rings green", DEFORM, CITY,
     "SLIME.JELLY_RING = Color3.fromRGB(176, 118, 255)", "SLIME.JELLY_RING = Color3.fromRGB(96, 200, 90)"),
    ("the jellyfish's rings slime's again", DEFORM, CITY,
     'local ringColour = if ctx.material == "Jellyfish" then SLIME.JELLY_RING', 'local ringColour = if false then SLIME.JELLY_RING'),
    ("the jellyfish not lighting up", DEFORM, CITY, "\t\t\tSLIME.glow(tile)\n", "\t\t\tlocal _ = tile\n"),
    ("SeaRig not knowing the gold", RIG, CITY, "\tTreasure_Gold = Vector3.new(9, 12, 9),\n", ""),
    ("SeaRig expecting the gems on their side", RIG, CITY,
     "Treasure_Gems = Vector3.new(9, 12, 9)", "Treasure_Gems = Vector3.new(9, 9, 12)"),
    ("the Ferris wheel back in the window", SERVER, CITY, "\twindow = 190,", "\twindow = 120,"),
    ("a speech bubble behind the room again", NPC, CITY, "gui.AlwaysOnTop = true", "gui.AlwaysOnTop = false"),
    ("a double dash in what they say", NPC, CITY, "It's leaking! Get back from it!", "It's leaking -- get back from it!"),
]

paths = {m[1] for m in MUTATIONS}
originals = {path: path.read_bytes() for path in paths}
missed = []
try:
    for label, path, checker, old, new in MUTATIONS:
        text = originals[path].decode("utf-8").replace("\r\n", "\n")
        assert text.count(old) == 1, "%s: anchor found %d times" % (label, text.count(old))
        path.write_bytes(text.replace(old, new).encode("utf-8"))
        run = subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                             cwd=str(ROOT / "blender"))
        path.write_bytes(originals[path])
        caught = run.returncode != 0
        why = [line.strip() for line in (run.stdout + run.stderr).splitlines() if line.startswith("  ")][:2]
        print("%-8s %s  %s" % ("caught" if caught else "MISSED", label, "; ".join(why)[:170]))
        if not caught:
            missed.append(label)
finally:
    for path, data in originals.items():
        path.write_bytes(data)
print("\n%d of %d caught" % (len(MUTATIONS) - len(missed), len(MUTATIONS)))
