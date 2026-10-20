"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 74: the materials as a collection. A material missing from the catalogue, one that does not exist, a dash in a
name; nothing paid for one or for all, no badge; a made-up one counted, one paid every time or not kept; no bonus, no
swatch, no badge given, no tokens, off the dashboard twice over, not on the pill, not told; found off the levels or in
the squish room, the look hitting the runner, nobody looked under, nothing ever found, a client's word counting;
the screen not told, a save loading without them; a run's told again, its tokens or its word off the pill, ones from
before it on it; kept after leaving, nowhere in a new save; the self-test not finding one or the last, or losing the
real run's; the test panel doing nothing, no button; the pill silent, the swatch's tile and press saying the wrong
thing; the journal without its page, its tabs not fitting, a name cut off, a page without its number, what it does or
what it was, a word in the corner, never reaching it; no chime; the lobby's board missing, off the deck, named like
the other, never found, written on its back, for everyone or off its panel, giving the rest away, not counting, or
never changing.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
CAT = S / "Shared/ShopCatalog.lua"
ECON = S / "Server/Services/EconomyService.lua"
SHOPC = S / "Client/Services/ShopService.lua"
DEV = S / "Client/Services/DevPanelClient.lua"
JOURNAL = S / "Client/Services/JournalService.lua"
ONBOARD = S / "Client/Services/OnboardingService.lua"
HUB = S / "Server/Services/HubService.lua"
LAYOUT = S / "Shared/LobbyLayout.lua"
VOTE = S / "Client/Services/HubVoteService.lua"
SHOP, HUBCHECK, PARSE = "check_shop.py", "check_hub.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (SHOP, HUBCHECK, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

PLACE = 'buildChallengeBoard(HUB_ORIGIN + AT.materials, folder, "MaterialsBoard")'
SPOT = "materials = Vector3.new(-102, 1, -27)"

MUTATIONS = [
    ("a material missing", CAT, SHOP, '\t{ key = "Jellyfish", name = "Jellyfish", colour = rgb(200, 170, 240) },\n', ""),
    ("one that does not exist", CAT, SHOP, '{ key = "Jellyfish", name = "Jellyfish",', '{ key = "Marble", name = "Jellyfish",'),
    ("a dash in a name", CAT, SHOP, 'name = "Keys over lava"', 'name = "Keys -- over lava"'),
    ("nothing for one", CAT, SHOP, "\tMATERIAL = 5,", "\tMATERIAL = 0,"),
    ("nothing for all", CAT, SHOP, "\tMATERIALS_ALL = 100,", "\tMATERIALS_ALL = 0,"),
    ("no badge for all", CAT, SHOP, "\tmaterials = 0, -- every material", "\t-- every material"),
    ("a made-up one counted", ECON, SHOP, "if not (profile and profile:IsActive()) or ShopCatalog.material(name) == nil then",
     "if not (profile and profile:IsActive()) then"),
    ("paid every time", ECON, SHOP, "\tif data.Materials[name] then\n\t\treturn false\n\tend\n", ""),
    ("not kept", ECON, SHOP, "\tdata.Materials[name] = true\n", ""),
    ("no bonus for all", ECON, SHOP, "\t\tamount += ShopCatalog.REWARD.MATERIALS_ALL\n", ""),
    ("no swatch for all", ECON, SHOP, 'if item.earn == "materials" and not data.Owned[item.id] then',
     'if item.earn == "material" and not data.Owned[item.id] then'),
    ("no badge given", ECON, SHOP, "\t\ttask.spawn(EconomyService.awardBadge, player, ShopCatalog.BADGES.materials)\n", ""),
    ("no tokens", ECON, SHOP, "\tdata.Tokens += amount\n\tdata.Earned += amount\n\tlogEconomy(player, true, amount, Enum.AnalyticsEconomyTransactionType.Gameplay.Name, \"Material\")",
     "\tdata.Earned += amount\n\tlogEconomy(player, true, amount, Enum.AnalyticsEconomyTransactionType.Gameplay.Name, \"Material\")"),
    ("off the economy view", ECON, SHOP, 'Gameplay.Name, "Material")', 'Gameplay.Name, "Materials")'),
    ("off the custom events", ECON, SHOP, 'LogCustomEvent(player, "MaterialFound", count)', 'LogCustomEvent(player, "Material", count)'),
    ("not on the pill", ECON, SHOP, "\trun.tokens += amount\n", ""),
    ("not told", ECON, SHOP, "\tmaterialsAttribute(player)\n\tpush(player)\n\treturn true", "\tpush(player)\n\treturn true"),
    ("found off the levels", ECON, SHOP, 'if typeof(level) ~= "string" or level == "backRooms" or player:GetAttribute("InSquishRoom") then',
     'if level == "backRooms" or player:GetAttribute("InSquishRoom") then'),
    ("found in the squish room", ECON, SHOP, ' or level == "backRooms" or player:GetAttribute("InSquishRoom") then\n\t\treturn',
     ' or level == "backRooms" then\n\t\treturn'),
    ("the look hitting the runner", ECON, SHOP, "\tunderParams.FilterDescendantsInstances = { character }\n", ""),
    ("nobody looked under", ECON, SHOP, "pcall(lookUnder, player)", "pcall(print, player)"),
    ("nothing ever found", ECON, SHOP, "\t\t\t\tEconomyService.foundMaterial(player, name)\n", ""),
    ("a client's word counting", ECON, SHOP, "local NOTES = { welcomed = true, guided = true, hinted = true, shopIntro = true, favourite = true }",
     "local NOTES = { welcomed = true, guided = true, hinted = true, shopIntro = true, favourite = true, found = true }"),
    ("the screen not told", ECON, SHOP, 'player:SetAttribute("MaterialsFound", #keys)', 'player:SetAttribute("MaterialCount", #keys)'),
    ("a save loading without them", ECON, SHOP, "\tprofiles[player] = ready\n\tdailyAttributes(player)\n\tchallengeAttributes(player)\n\tmaterialsAttribute(player)\n",
     "\tprofiles[player] = ready\n\tdailyAttributes(player)\n\tchallengeAttributes(player)\n"),
    ("a run's told again", ECON, SHOP, "\tlocal found = foundRun[player]\n\tfoundRun[player] = nil\n", "\tlocal found = foundRun[player]\n"),
    ("its tokens off the pill", ECON, SHOP, "amount + prize + foundTokens, {", "amount + prize, {"),
    ("its word off the pill", ECON, SHOP, "materials = foundCount, gift = foundGift })", "gift = foundGift })"),
    ("ones from before the run on it", ECON, SHOP, "\t\tcrew[player] = true\n\t\tfoundRun[player] = nil\n", "\t\tcrew[player] = true\n"),
    ("kept after leaving", ECON, SHOP, "\tdevFriend[player] = nil\n\tfoundRun[player] = nil\n", "\tdevFriend[player] = nil\n"),
    ("nowhere in a new save", ECON, SHOP, "\tMaterials = {} :: { [string]: boolean },", "\tMaterial = {} :: { [string]: boolean },"),
    ("the self-test not finding one", ECON, SHOP, "and madeUp == false and data.Tokens == beforeMaterial + ShopCatalog.REWARD.MATERIAL",
     "and data.Tokens == beforeMaterial + ShopCatalog.REWARD.MATERIAL"),
    ("the self-test not finding the last", ECON, SHOP, 'check("the last material gives the swatch trail and the bonus", data.Owned.Swatch == true',
     'check("the last material gives the swatch trail and the bonus", true'),
    ("the self-test losing the run's", ECON, SHOP, "\tfoundRun[player] = realFound\n", ""),
    ("the test panel doing nothing", ECON, SHOP, "\t\t\t\tif material.key ~= \"Soap\" then\n\t\t\t\t\tdata.Materials[material.key] = true\n\t\t\t\tend\n\t\t\tend\n\t\tend\n\t\tmaterialsAttribute(player)\n",
     "\t\t\t\tif material.key ~= \"Soap\" then\n\t\t\t\t\tdata.Materials[material.key] = true\n\t\t\t\tend\n\t\t\tend\n\t\tend\n"),
    ("no button", DEV, SHOP, '\t{ action = "materials", text = "Materials: 26 / none" },\n', ""),
    ("the pill silent", SHOPC, SHOP, '\t\t\ttable.insert(reasons, "New material")\n', ""),
    ("the swatch's tile wrong", SHOPC, SHOP, 'words = LOOK.soon, LOOK.soonEdge, LOOK.soonInk, ("Find all %d"):format(#ShopCatalog.MATERIALS)',
     'words = LOOK.soon, LOOK.soonEdge, LOOK.soonInk, "Finish the story"'),
    ("the swatch's press wrong", SHOPC, SHOP, '\tif item.earn == "materials" and not owned(item.id) then\n\t\ttoast(("Stand on every material',
     '\tif false then\n\t\ttoast(("Stand on every material'),
    ("the journal without its page", JOURNAL, SHOP, '\t{ key = "material", name = "Materials", empty = "Nothing yet. Every material you stand on in a level is kept here." },\n', ""),
    ("its tabs not fitting", JOURNAL, SHOP, "button.Size = UDim2.new(1 / #KINDS, -5, 1, 0)", "button.Size = UDim2.new(1 / 3, -4, 1, 0)"),
    ("a name cut off", JOURNAL, SHOP, "\t\tbutton.TextScaled = true\n", ""),
    ("a page without its number", JOURNAL, SHOP, 'eyebrow = ("Material %d of %d"):format(counts[kind], keepsakeTotal)', 'eyebrow = "A material"'),
    ("a page without what it does", JOURNAL, SHOP, "\t\t\ttable.insert(lines, hints[key])\n", ""),
    ("a page without what it was", JOURNAL, SHOP, '("Kept by the Hold: %s, from %s."):format(kept.thing, kept.from)', '"Kept by the Hold."'),
    ("a word in the corner", JOURNAL, SHOP, "quiet = true, restored = first })", "restored = first })"),
    ("never reaching it", JOURNAL, SHOP, "\ttask.spawn(watchMaterials)\n", ""),
    ("no chime", ONBOARD, SHOP, "if shownFound ~= nil and now > shownFound and kit then", "if false then"),
    ("the journal cannot say", ONBOARD, SHOP, "OnboardingService.HINTS = HINTS\n", ""),
    ("the board missing", HUB, HUBCHECK, "\t" + PLACE + "\n", ""),
    ("the board off the deck", LAYOUT, HUBCHECK, SPOT, SPOT.replace("(-102, 1, -27)", "(-102, 2, -27)")),
    ("the board in the way", LAYOUT, HUBCHECK, SPOT, SPOT.replace("(-102, 1, -27)", "(-108, 1, -27)")),
    ("named like the other", HUB, HUBCHECK, 'model.Name = name or "ChallengeBoard"', 'model.Name = "ChallengeBoard"'),
    ("never found", VOTE, HUBCHECK, 'hub:FindFirstChild("MaterialsBoard")', 'hub:FindFirstChild("MaterialBoard")'),
    ("written on its back", VOTE, HUBCHECK, "face.Face = Enum.NormalId.Front", "face.Face = Enum.NormalId.Back"),
    ("written for everyone", VOTE, HUBCHECK, 'face.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")', "face.Parent = workspace"),
    ("off its panel", VOTE, HUBCHECK, "face.Adornee = panel", "face.Adornee = nil"),
    ("giving the rest away", VOTE, HUBCHECK, 'cell.name.Text = if got then material.name else "?"', "cell.name.Text = material.name"),
    ("not counting", VOTE, HUBCHECK, 'title.Text = ("Materials found  %d of %d"):format(found, #shop.MATERIALS)', 'title.Text = "Materials"'),
    ("never changing", VOTE, HUBCHECK, '\tPlayers.LocalPlayer:GetAttributeChangedSignal("Materials"):Connect(drawMaterials)\n', ""),
    ("a name never declared", ECON, PARSE, "\tlocal run = foundRun[player] or { count = 0, tokens = 0, gift = nil }",
     "\tlocal run = foundRuns[player] or { count = 0, tokens = 0, gift = nil }"),
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
