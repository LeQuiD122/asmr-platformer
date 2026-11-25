"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 165: the teleprinter. No Y on a board; a key typed in the air, over and over, or under a foot rather than the
middle; an R6 body never typing, or stood on short legs; the line between two keys typing both, a key taken before you
are into it, counted at its very edge, or so deep a walk skips it; the footing finding no ground under an R6 body, or
standing one on no legs; a body's height read without an R6 body's legs; a trail a stud above an R6 body; the townsfolk
made R6 and stood as R15; an answer that cannot be typed; one YES heard as many; a failed save stopping the typing; the lava keys typed;
the line of someone gone kept, or of someone standing still forgotten; the remote waited for, missing or never paid;
paid twice, or before it is marked; a save loaded not said; the tokens not said; a secret paying too much; the message
printed for someone who has answered, or not the keepsake's; lines run together; the strip's remote waited for without
end; the strip never going, or sounding twice; the pill silent; no button on the test panel, or it doing nothing; the
strip never started, or not looked for by the paste check; its face not Style's; it over the arrival's black; the
keyboard's first hint not saying the keys type.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
BOOT = S / "Server/Bootstrap.server.lua"
BUILDER = S / "Server/ChunkBuilder.server.lua"
CAT = S / "Shared/ShopCatalog.lua"
CBOOT = S / "Client/Bootstrap.client.lua"
COSM = S / "Client/Services/CosmeticsClient.lua"
DEFORMS = S / "Server/Services/DeformationService.lua"
DEVP = S / "Client/Services/DevPanelClient.lua"
ECON = S / "Server/Services/EconomyService.lua"
KEEPS = S / "Shared/Keepsakes.lua"
ONBOARD = S / "Client/Services/OnboardingService.lua"
RUNFEEL = S / "Client/Services/RunFeel.lua"
SHOPC = S / "Client/Services/ShopService.lua"
TELE = S / "Client/Services/Teleprinter.lua"
TOWNS = S / "Server/Services/Townsfolk.lua"
HUB, SHOP, STANDARDS, STYLECHECK, TOUCH = "check_hub.py", "check_shop.py", "check_standards.py", "check_style.py", "check_touch.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (HUB, SHOP, STANDARDS, STYLECHECK, TOUCH):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('no Y on a board', BUILDER, TOUCH, 'local KEY_FROM = 2', 'local KEY_FROM = 1'),
    ('a key typed in the air', DEFORMS, TOUCH, 'if root.Position.Y - top > legs + root.Size.Y / 2 + TYPING.above then', 'if root.Position.Y - top > legs + root.Size.Y / 2 + 50 then'),
    ('an R6 body never typing', DEFORMS, TOUCH, 'local legs = if humanoid.RigType == Enum.HumanoidRigType.R6 then TYPING.legsR6 else humanoid.HipHeight', 'local legs = humanoid.HipHeight'),
    ('an R6 body stood on short legs', DEFORMS, TOUCH, '\tlegsR6 = 2,', '\tlegsR6 = 1,'),
    ('the line between two keys typing both', DEFORMS, TOUCH, '\tif math.abs(into.X) > half.X - TYPING.inside or math.abs(into.Z) > half.Z - TYPING.inside then\n\t\treturn\n\tend\n', ''),
    ('a key taken before you are into it', DEFORMS, TOUCH, '\tif key == mine.key then\n\t\treturn\n\tend\n\t-- Well into a key', '\tif key == mine.key then\n\t\treturn\n\tend\n\tmine.key = key\n\t-- Well into a key'),
    ('a key counted at its very edge', DEFORMS, TOUCH, '\tinside = 0.5,', '\tinside = 0,'),
    ('a key counted so deep a walk skips it', DEFORMS, TOUCH, '\tinside = 0.5,', '\tinside = 0.9,'),
    ('the footing finding no ground under an R6 body', RUNFEEL, TOUCH, 'local legs = if humanoid.RigType == Enum.HumanoidRigType.R6 then 2 else humanoid.HipHeight', 'local legs = humanoid.HipHeight'),
    ('the footing standing an R6 body on no legs', RUNFEEL, TOUCH, 'Enum.HumanoidRigType.R6 then 2 else humanoid.HipHeight', 'Enum.HumanoidRigType.R6 then 0 else humanoid.HipHeight'),
    ("a body's height read without an R6 body's legs", RUNFEEL, TOUCH, '\tfootRay.FilterDescendantsInstances = { character, printFolder() }\n', '\tfootRay.FilterDescendantsInstances = { character, printFolder() }\n\tlocal reach = humanoid.HipHeight + 2\n'),
    ('a trail a stud above an R6 body', COSM, TOUCH, 'local hip = if humanoid and humanoid.RigType ~= Enum.HumanoidRigType.R6 then humanoid.HipHeight else 2', 'local hip = if humanoid then humanoid.HipHeight else 2'),
    ('the townsfolk made R6 and stood as R15', TOWNS, TOUCH, 'Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)', 'Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R6)'),
    ('a key typed over and over', DEFORMS, TOUCH, '\tif key == mine.key then\n\t\treturn\n\tend\n', ''),
    ('a key under a foot, not the middle', DEFORMS, TOUCH, 'local col, row = SubRegionGrid.getActiveRegion(root.Position, platform.CFrame, state.grid)', 'local col, row = SubRegionGrid.getActiveRegion(root.Position + root.CFrame.LookVector * 2, platform.CFrame, state.grid)'),
    ('an answer that cannot be typed', DEFORMS, TOUCH, '\tanswer = "YES",', '\tanswer = "YEZ",'),
    ('one YES heard as many', DEFORMS, TOUCH, '\t\tmine.line = ""\n\tend\nend', '\t\tmine.line = mine.line\n\tend\nend'),
    ('a failed save stopping the typing', DEFORMS, TOUCH, 'local ok, amount = pcall(answeredBy :: any, player)', 'local ok, amount = true, (answeredBy :: any)(player)'),
    ('the lava keys typed', DEFORMS, TOUCH, 'if state.material == "CreamyKeyboard" and platform.Parent then', 'if (state.material == "CreamyKeyboard" or state.material == "LavaKeys") and platform.Parent then'),
    ('the line of someone gone kept', DEFORMS, TOUCH, '\ttyping[player] = nil\nend)', '\tlocal _ = typing[player]\nend)'),
    ('the line of someone standing still forgotten', DEFORMS, TOUCH, '\t-- Kept while you are on a keyboard at all, so standing still on one key never forgets the line.\n\tmine.at = now\n', ''),
    ('the remote waited for', DEFORMS, TOUCH, 'local remote = RemoteEvents:FindFirstChild("Teleprinter")', 'local remote = RemoteEvents:WaitForChild("Teleprinter")'),
    ('never paid', BOOT, TOUCH, '\tDeformationService.setAnswered(EconomyService.answeredTeleprinter)\n', ''),
    ('no remote', BOOT, TOUCH, 'ensureRemoteEvent(remoteEventsFolder, "Teleprinter")', 'ensureRemoteEvent(remoteEventsFolder, "Teleprinters")'),
    ('paid twice', ECON, SHOP, '\tif not (profile and profile:IsActive()) or profile.Data.Teleprinter == true then\n\t\treturn 0', '\tif not (profile and profile:IsActive()) then\n\t\treturn 0'),
    ('paid before it is marked', ECON, SHOP, '\tprofile.Data.Teleprinter = true\n\tlocal amount = ShopCatalog.REWARD.TELEPRINTER\n\tprofile.Data.Tokens += amount\n', '\tlocal amount = ShopCatalog.REWARD.TELEPRINTER\n\tprofile.Data.Tokens += amount\n\tprofile.Data.Teleprinter = true\n'),
    ('a save loaded not said', ECON, TOUCH, 'player:SetAttribute("Teleprinter", ready.Data.Teleprinter == true)', 'player:SetAttribute("Teleprinter", false)'),
    ('the tokens not said', ECON, TOUCH, '{ teleprinter = true }', '{ cache = true }'),
    ('a secret paying too much', CAT, TOUCH, '\tTELEPRINTER = 75,', '\tTELEPRINTER = 750,'),
    ('the message printed for someone who has answered', TELE, TOUCH, 'if me:GetAttribute("Teleprinter") ~= true then', 'if true then'),
    ("the message not the keepsake's", TELE, TOUCH, 'asked = "KEY HOLDER PLEASE CONFIRM"', 'asked = "KEY HOLDER CONFIRM"'),
    ('lines run together', TELE, TOUCH, '\t\ttape = ""\n\t\tqueue = {}', '\t\tqueue = {}'),
    ("the strip's remote waited for without end", TELE, TOUCH, 'remotes:WaitForChild("Teleprinter", 30)', 'remotes:WaitForChild("Teleprinter")'),
    ('the strip never going', TELE, TOUCH, '\t\thideAfter(if confirmed then PRINT.answeredStays else PRINT.stays)\n', ''),
    ('the answer sounding twice', TELE, TOUCH, 'quietAnswer = not (type(paid) == "number" and paid > 0)', 'quietAnswer = true'),
    ('the pill silent', SHOPC, TOUCH, 'table.insert(reasons, "The teleprinter answered")', 'table.insert(reasons, "Hidden cache")'),
    ('no button on the test panel', DEVP, TOUCH, '\t{ action = "teleprinter", text = "Teleprinter answered on/off" },\n', ''),
    ("the test panel's button doing nothing", ECON, TOUCH, 'elseif action == "teleprinter" then', 'elseif action == "teleprinterOff" then'),
    ('the strip never started', CBOOT, TOUCH, '"Haptics", "Teleprinter", "RunFeel"', '"Haptics", "RunFeel"'),
    ('the paste check not looking for the strip', BOOT, HUB, '"RunFeel", "Haptics", "Teleprinter",', '"RunFeel", "Haptics",'),
    ("the strip's face not Style's", TELE, STYLECHECK, 'words.FontFace = Style.FONT.heading', 'words.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json")'),
    ("the strip over the arrival's black", TELE, STANDARDS, 'gui.DisplayOrder = 19', 'gui.DisplayOrder = 90'),
    ('the keepsake saying another message', KEEPS, TOUCH, 'KEY HOLDER PLEASE CONFIRM', 'KEY HOLDER, PLEASE CONFIRM'),
    ('the hint not saying the keys type', ONBOARD, TOUCH, 'goes down, types its letter, and springs back.', 'goes down and springs back.'),
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
