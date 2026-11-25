"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 159: the arrival. Roblox's screen taken away before the black is up; the game not waited for; nothing
sending the card away in the end; up half a minute; a flicker; the ground not waited for; the fetch waited for without
end; Arriving never let go of; under another screen; a strip of the world under Roblox's bar; it going twice; the welcome
under the card, or waiting for it without end; a notice under the card; a face or a colour that is not Style's; the paste
check not looking for it; the paste list putting it under Other.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
ARRIVE = S / "ReplicatedFirst/Arrival.client.lua"
BOOT = S / "Server/Bootstrap.server.lua"
ONBOARD = S / "Client/Services/OnboardingService.lua"
PASTELIST = ROOT / "tools/paste_list.py"
UIS = S / "Client/Services/UIService.lua"
HUB, STANDARDS, STYLECHECK = "check_hub.py", "check_standards.py", "check_style.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (HUB, STANDARDS, STYLECHECK):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ("Roblox's screen taken away before the black is up", ARRIVE, STANDARDS, 'gui.Parent = me:WaitForChild("PlayerGui")\n-- Only now, with the black already up, so nothing of a half-built world shows between the two.\npcall(function()\n\tReplicatedFirst:RemoveDefaultLoadingScreen()\nend)', 'pcall(function()\n\tReplicatedFirst:RemoveDefaultLoadingScreen()\nend)\ngui.Parent = me:WaitForChild("PlayerGui")'),
    ('the game not waited for', ARRIVE, STANDARDS, '\tif not game:IsLoaded() then\n\t\tgame.Loaded:Wait()\n\tend\n', ''),
    ('nothing sending it away in the end', ARRIVE, STANDARDS, '\ttask.delay(ARRIVE.most, arrive)\n', ''),
    ('up half a minute', ARRIVE, STANDARDS, 'most = if RunService:IsStudio() then 4 else 12,', 'most = if RunService:IsStudio() then 4 else 30,'),
    ('a flicker', ARRIVE, STANDARDS, '\tleast = 1.2,', '\tleast = 0.2,'),
    ('the ground not waited for', ARRIVE, STANDARDS, 'if root.Parent and workspace:Raycast(root.Position, Vector3.new(0, -24, 0), below) then\n\t\t\t\tbreak', 'if root.Parent then\n\t\t\t\tbreak'),
    ('the fetch waited for without end', ARRIVE, STANDARDS, 'while not gone and os.clock() < untilAt and ContentProvider.RequestQueueSize > 0 do', 'while not gone and ContentProvider.RequestQueueSize > 0 do'),
    ('Arriving never let go of', ARRIVE, STANDARDS, '\t\t\tme:SetAttribute("Arriving", nil)\n', ''),
    ('under another screen', ARRIVE, STANDARDS, 'gui.DisplayOrder = 70', 'gui.DisplayOrder = 40'),
    ("a strip of the world under Roblox's bar", ARRIVE, STANDARDS, 'gui.IgnoreGuiInset = true', 'gui.IgnoreGuiInset = false'),
    ('it going twice', ARRIVE, STANDARDS, '\tif gone then\n\t\treturn\n\tend\n\tgone = true', '\tgone = true'),
    ('the welcome under the card', ONBOARD, STANDARDS, 'afterArrival(showWelcome)', 'task.delay(1.5, showWelcome)'),
    ('the welcome waiting for it without end', ONBOARD, STANDARDS, 'while me:GetAttribute("Arriving") == true and os.clock() < untilAt do', 'while me:GetAttribute("Arriving") == true do'),
    ('a notice under the card', UIS, STANDARDS, 'return (blackout.Visible and blackout.BackgroundTransparency < 0.6) or player:GetAttribute("Arriving") == true', 'return (blackout.Visible and blackout.BackgroundTransparency < 0.6)'),
    ("a face that is not Style's", ARRIVE, STYLECHECK, 'local BODY = Font.new(NUNITO, Enum.FontWeight.Medium, Enum.FontStyle.Normal)', 'local BODY = Font.new(NUNITO, Enum.FontWeight.Light, Enum.FontStyle.Normal)'),
    ("a colour that is not Style's", ARRIVE, STYLECHECK, 'local INK_MUTED = Color3.fromRGB(126, 128, 150)', 'local INK_MUTED = Color3.fromRGB(128, 128, 128)'),
    ('the paste check not looking for it', BOOT, HUB, '\tscriptAt(game:GetService("ReplicatedFirst"), "ReplicatedFirst", "Arrival", "LocalScript")\n', ''),
    ('the paste list putting it under Other', PASTELIST, STANDARDS, '    ("ReplicatedFirst", "First to load (ReplicatedFirst)"),\n', ''),
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
