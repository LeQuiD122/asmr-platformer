"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 77: codes and the post box. A code nobody can post, listed twice, paying far too much, ending on no day; typed
in small letters refused, anything looked for, its last day not read, ending at the start of it; no way to post one,
nowhere in a new save; a code not in the list paying, paying after it ends, every time, or not kept; a second way for
a request to add tokens; off the dashboard twice over, paid without a word; the self-test not posting one or leaving
its own; the test panel's doing nothing, no button; the card never asking, not saying why, nothing selected, no B,
the selection kept, outside the safe area, wider than a phone, you held still after; no word for a code used; a dash
in its words; the pill not saying which; the cursor locked over it; the post box off the deck, in the way, never
built, its plinth, body or cap not stacked, lying on its side, its slot off its face, no prompt, or a prompt that
opens nothing.
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
VIEW = S / "Client/Services/ViewModeService.lua"
HUB = S / "Server/Services/HubService.lua"
LAYOUT = S / "Shared/LobbyLayout.lua"
SHOP, HUBCHECK, PARSE = "check_shop.py", "check_hub.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (SHOP, HUBCHECK, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

LINE = '\t{ code = "HARROWBAY", tokens = 100, ends = "2026-12-31" },\n'
PLACE = "buildPostBox(HUB_ORIGIN + AT.postBox, folder)"
SPOT = "postBox = Vector3.new(-92, 1, 22)"

MUTATIONS = [
    ("a code nobody can post", CAT, SHOP, LINE, LINE.replace("HARROWBAY", "Harrow-Bay")),
    ("a code listed twice", CAT, SHOP, LINE, LINE + LINE),
    ("a code paying far too much", CAT, SHOP, LINE, LINE.replace("tokens = 100", "tokens = 100000")),
    ("a code ending on no day", CAT, SHOP, LINE, LINE.replace("2026-12-31", "2026-13-45")),
    ("small letters refused", CAT, SHOP, 'local key = string.upper((string.gsub(typed, "%s", "")))',
     'local key = (string.gsub(typed, "%s", ""))'),
    ("anything looked for", CAT, SHOP, 'if #key < 3 or #key > 20 or not string.match(key, "^%w+$") then', "if #key < 1 then"),
    ("its last day not read", CAT, SHOP, "DateTime.fromUniversalTime(tonumber(y) :: number, tonumber(m) :: number, tonumber(d) :: number).UnixTimestamp",
     "os.time()"),
    ("ending at the start of its last day", CAT, SHOP, "return if ok then at + 86400 else nil", "return if ok then at else nil"),
    ("no way to post one", ECON, SHOP, "local ACTIONS = { buy = true, equip = true, unequip = true, code = true }",
     "local ACTIONS = { buy = true, equip = true, unequip = true }"),
    ("nowhere in a new save", ECON, SHOP, "\tCodes = {} :: { [string]: boolean },", "\tCode = {} :: { [string]: boolean },"),
    ("a code not in the list paying", ECON, SHOP, "\t\tif not (key and entry) then\n\t\t\treturn answer(player, false, \"unknown\")",
     "\t\tif not key then\n\t\t\treturn answer(player, false, \"unknown\")"),
    ("paying after it ends", ECON, SHOP, "if not ends or os.time() >= ends then", "if not ends then"),
    ("paying every time", ECON, SHOP, '\t\tif data.Codes[key] then\n\t\t\treturn answer(player, false, "used")\n\t\tend\n', ""),
    ("not kept", ECON, SHOP, "\t\tdata.Codes[key] = true\n", ""),
    ("a second way to add tokens", ECON, SHOP, "\t\tprofile.Data.Tokens -= price\n", "\t\tprofile.Data.Tokens -= price\n\t\tprofile.Data.Tokens += 1\n"),
    ("off the economy view", ECON, SHOP, 'codeTokens, Enum.AnalyticsEconomyTransactionType.Gameplay.Name, "Code")',
     'codeTokens, Enum.AnalyticsEconomyTransactionType.Gameplay.Name, "Codes")'),
    ("off the custom events", ECON, SHOP, 'LogCustomEvent(player, "CodeRedeemed", codeTokens,', 'LogCustomEvent(player, "Code", codeTokens,'),
    ("paid without a word", ECON, SHOP, "earnedRemote:FireClient(player, codeTokens, { code = key })",
     "earnedRemote:FireClient(player, codeTokens, {})"),
    ("the self-test not posting one", ECON, SHOP, 'codeFirst.ok == true and codeAgain.reason == "used"', 'true and codeAgain.reason == "used"'),
    ("the self-test leaving its own", ECON, SHOP, "\t\t\t\ttable.remove(ShopCatalog.CODES, index)\n", ""),
    ("the test panel's doing nothing", ECON, SHOP, "\t\t-- Every code as if never posted, to post them again.\n\t\tdata.Codes = {}\n",
     "\t\t-- Every code as if never posted, to post them again.\n"),
    ("no button", DEV, SHOP, '\t{ action = "codesForget", text = "Codes: post again" },\n', ""),
    ("the card never asking", SHOPC, SHOP, 'local result = ask("code", box.Text)', "local result = nil"),
    ("not saying why", SHOPC, SHOP, "said.Text = CODE_WORDS[tostring(result.reason)]", "said.Text = CODE_WORDS.busy"),
    ("nothing selected", SHOPC, SHOP, "\t\tGuiService.SelectedObject = codes.box\n", ""),
    ("no B", SHOPC, SHOP, "Enum.KeyCode.ButtonB, Enum.KeyCode.Escape)", "Enum.KeyCode.Escape)"),
    ("the selection kept", SHOPC, SHOP, "\tif GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(screen) then\n\t\tGuiService.SelectedObject = nil\n\tend\n\thold(false)",
     "\thold(false)"),
    ("outside the safe area", SHOPC, SHOP, "\tcodeScreen.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets\n", ""),
    ("wider than a phone", SHOPC, SHOP, "codeMost.MaxSize = Vector2.new(400, 236)", "codeMost.MaxSize = Vector2.new(900, 236)"),
    ("held still after", SHOPC, SHOP, "\t\tGuiService.SelectedObject = nil\n\tend\n\thold(false)\nend\n\nlocal function buildCodes()",
     "\t\tGuiService.SelectedObject = nil\n\tend\nend\n\nlocal function buildCodes()"),
    ("no word for a code used", SHOPC, SHOP, '\tused = "You\'ve posted that code already.",\n', ""),
    ("a dash in its words", SHOPC, SHOP, '"That code has ended."', '"That code -- has ended."'),
    ("the pill not saying which", SHOPC, SHOP, '\t\t\ttable.insert(reasons, "Code " .. info.code)\n', ""),
    ("the cursor locked over it", VIEW, SHOP, '\t\tor (codeBox ~= nil and codeBox:IsA("ScreenGui") and codeBox.Enabled)\n', ""),
    ("off the deck", LAYOUT, HUBCHECK, SPOT, SPOT.replace("(-92, 1, 22)", "(-92, 2, 22)")),
    ("in the way", LAYOUT, HUBCHECK, SPOT, SPOT.replace("(-92, 1, 22)", "(-86, 1, 24)")),
    ("never built", HUB, HUBCHECK, "\t" + PLACE + "\n", ""),
    ("the plinth off the deck", HUB, HUBCHECK, 'pillar("Plinth", Vector3.new(0.3, 2.4, 2.4), CFrame.new(0, 0.15, 0)',
     'pillar("Plinth", Vector3.new(0.3, 2.4, 2.4), CFrame.new(0, 0.5, 0)'),
    ("the body off its plinth", HUB, HUBCHECK, 'pillar("Body", Vector3.new(4, 2, 2), CFrame.new(0, 2.3, 0)',
     'pillar("Body", Vector3.new(4, 2, 2), CFrame.new(0, 2.6, 0)'),
    ("the cap off its body", HUB, HUBCHECK, 'pillar("Cap", Vector3.new(0.4, 2.3, 2.3), CFrame.new(0, 4.5, 0)',
     'pillar("Cap", Vector3.new(0.4, 2.3, 2.3), CFrame.new(0, 5, 0)'),
    ("lying on its side", HUB, HUBCHECK, "(if round then CFrame.Angles(0, 0, math.rad(90)) else CFrame.identity)", "CFrame.identity"),
    ("the slot off its face", HUB, HUBCHECK, 'pillar("Slot", Vector3.new(1, 0.16, 0.12), CFrame.new(0, 3.4, -1)',
     'pillar("Slot", Vector3.new(1, 0.16, 0.12), CFrame.new(0, 3.4, -2)'),
    ("no prompt", HUB, HUBCHECK, '\tprompt.Name = "CodePrompt"\n', ""),
    ("a prompt that opens nothing", SHOPC, HUBCHECK, '\t\telseif prompt.Name == "CodePrompt" and who == Players.LocalPlayer then\n\t\t\tShopService.openCodes()\n',
     ""),
    ("a name never declared", SHOPC, PARSE, "\tlocal screen = codes.screen\n\tif not screen or screen.Enabled then",
     "\tlocal screen = code.screen\n\tif not screen or screen.Enabled then"),
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
