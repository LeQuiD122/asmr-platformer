"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 116: what the true ending gives. It paying a pittance, or no badge; the save not keeping it; given
again and again, never kept, paying other than the catalogue says, never told to the screen, no plaque, no badge given,
or no word of what the tokens were for; not given to the rider who clocked in, or given elsewhere too; the plaque over
anyone's head, huge far away, drawn from anywhere, shown on a level, on top of the VIP tag, saying nothing, not put on
with the rest, or not put away on a level; a save's true ending not told to its screen; the test panel's actions or
buttons gone; the wrong one hidden, his ledge never emptied, what arrives later missed, or never looked for; the shop
silent about it; it paying from the run's own as well; a name never declared.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
BOOT = S / "Server/Bootstrap.server.lua"
CAT = S / "Shared/ShopCatalog.lua"
DEVP = S / "Client/Services/DevPanelClient.lua"
ECON = S / "Server/Services/EconomyService.lua"
SHOPC = S / "Client/Services/ShopService.lua"
STORYC = S / "Client/Services/StoryClient.lua"
SHOP, TRUE, PARSE = "check_shop.py", "check_trueending.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (SHOP, TRUE, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('paying a pittance', CAT, TRUE, '\tTRUE = 300, --', '\tTRUE = 5, --'),
    ('no badge', CAT, TRUE, '\ttrueEnding = 0, --', '\ttrueEnd = 0, --'),
    ('the save not keeping it', ECON, TRUE, '\tTrueEnding = false,\n}', '}'),
    ('given again and again', ECON, TRUE, 'if not (profile and profile:IsActive()) or profile.Data.TrueEnding == true then', 'if not (profile and profile:IsActive()) then'),
    ('never kept', ECON, TRUE, '\tprofile.Data.TrueEnding = true\n', ''),
    ('paying other than the catalogue says', ECON, TRUE, 'local amount = ShopCatalog.REWARD.TRUE * (if double then 2 else 1)', 'local amount = ShopCatalog.REWARD.STORY * (if double then 2 else 1)'),
    ('never told to the screen', ECON, TRUE, '\tplayer:SetAttribute("TrueEnding", true)\n', ''),
    ('no plaque', ECON, TRUE, '\tpush(player)\n\tkeyTag(player)\n\ttask.spawn(EconomyService.awardBadge, player, ShopCatalog.BADGES.trueEnding)', '\tpush(player)\n\ttask.spawn(EconomyService.awardBadge, player, ShopCatalog.BADGES.trueEnding)'),
    ('no badge given', ECON, TRUE, 'task.spawn(EconomyService.awardBadge, player, ShopCatalog.BADGES.trueEnding)', 'local _ = ShopCatalog.BADGES'),
    ('no word of what the tokens were for', ECON, TRUE, '{ trueEnding = true, double = double }', '{ double = double }'),
    ('not given to the rider who clocked in', BOOT, TRUE, 'if player:GetAttribute("ClockedIn") == true and EconomyService and EconomyService.trueEnding then', 'if player:GetAttribute("ClockedIn") == false and EconomyService and EconomyService.trueEnding then'),
    ('given elsewhere too', BOOT, TRUE, '\t\t\t\tif finishRunFor then\n\t\t\t\t\tfinishRunFor(player)\n\t\t\t\tend\n\t\t\tend)\n\t\t\tif typeof(unride) == "function" then', '\t\t\t\tif finishRunFor then\n\t\t\t\t\tpcall(EconomyService.trueEnding, player)\n\t\t\t\t\tfinishRunFor(player)\n\t\t\t\tend\n\t\t\tend)\n\t\t\tif typeof(unride) == "function" then'),
    ("the plaque over anyone's head", ECON, TRUE, 'if not (profile and profile.Data.TrueEnding == true) then', 'if not profile then'),
    ('huge far away', ECON, TRUE, 'gui.Size = UDim2.new(3.6, 0, 0.95, 0)', 'gui.Size = UDim2.fromOffset(360, 95)'),
    ('drawn from anywhere', ECON, TRUE, '\t\tgui.MaxDistance = 80\n\t\tgui.LightInfluence = 0\n\t\tgui.AlwaysOnTop = false\n\t\tlocal pill = Instance.new("Frame")\n\t\tpill.Name = "Pill"\n\t\tpill.Size = UDim2.fromScale(1, 1)', '\t\tgui.LightInfluence = 0\n\t\tgui.AlwaysOnTop = false\n\t\tlocal pill = Instance.new("Frame")\n\t\tpill.Name = "Pill"\n\t\tpill.Size = UDim2.fromScale(1, 1)'),
    ('on top of the VIP tag', ECON, TRUE, 'if head:FindFirstChild(VIP_TAG) then 4.75 else 3.35', '3.35'),
    ('saying nothing', ECON, TRUE, 'word.Text = "KEY HOLDER"', 'word.Text = ""'),
    ('not put on with the rest', ECON, TRUE, '\tvipTag(player)\n\tkeyTag(player)\nend', '\tvipTag(player)\nend'),
    ('not put away on a level', ECON, TRUE, '\t\t\tvipTag(player)\n\t\t\tkeyTag(player)\n\t\tend)', '\t\t\tvipTag(player)\n\t\tend)'),
    ("a save's true ending not told to its screen", ECON, TRUE, '\tplayer:SetAttribute("TrueEnding", ready.Data.TrueEnding == true)\n', ''),
    ("the test panel's action gone", ECON, TRUE, 'elseif action == "storyKnown" then', 'elseif action == "storyKnownX" then'),
    ("the test panel's button gone", DEVP, TRUE, '\t{ action = "trueEnding", text = "True ending on/off" },\n', ''),
    ('the wrong one hidden', STORYC, TRUE, 'if model.Name ~= "Watcher" then', 'if model.Name ~= "Marsh" then'),
    ('his ledge never emptied', STORYC, TRUE, '\t\t\titem.LocalTransparencyModifier = 1\n\t\tend\n\tend\n\tfor _, item in ipairs(model:GetDescendants()) do', '\t\t\tlocal _ = item\n\t\tend\n\tend\n\tfor _, item in ipairs(model:GetDescendants()) do'),
    ('what arrives later missed', STORYC, TRUE, '\tmodel.DescendantAdded:Connect(hide)\n', ''),
    ('never looked for', STORYC, TRUE, '\t\t\tstoppedWaiting(model)\n', ''),
    ('the shop silent about it', SHOPC, TRUE, 'table.insert(reasons, "The true ending")', 'table.insert(reasons, "")'),
    ("it paying from the run's own as well", ECON, SHOP, '\tprofile.Data.Tokens += amount\n\tprofile.Data.Earned += amount\n\tlogEconomy(player, true, amount, Enum.AnalyticsEconomyTransactionType.Gameplay.Name, "TrueEnding")', '\tprofile.Data.Tokens += amount\n\tprofile.Data.Tokens += amount\n\tprofile.Data.Earned += amount\n\tlogEconomy(player, true, amount, Enum.AnalyticsEconomyTransactionType.Gameplay.Name, "TrueEnding")'),
    ('a name never declared', STORYC, PARSE, '\tmodel.DescendantAdded:Connect(hide)\n', '\tmodel.DescendantAdded:Connect(hider)\n'),
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
