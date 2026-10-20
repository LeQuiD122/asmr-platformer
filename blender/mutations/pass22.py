"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 22: the shop and its economy. The classic Roblox dupes (a price the client names, a purchase
granted before it is saved or granted twice, a buy that skips the balance or ownership, a request that
races itself, a run paid twice or paid for a teleport to the finish, Studio saves mixed with live ones),
the shop on every device (the safe area, a thumb-sized button, a controller's way out, a character left
frozen), and the wiring (paid, built, the cursor freed).
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
ECON = S / "Server/Services/EconomyService.lua"
SHOP = S / "Client/Services/ShopService.lua"
BOOT = S / "Server/Bootstrap.server.lua"
HUB = S / "Server/Services/HubService.lua"
VIEW = S / "Client/Services/ViewModeService.lua"
CHECK, PARSE = "check_shop.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (CHECK, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    # The dupes.
    ("the client names the price", ECON, CHECK, "local price = item.price", "local price = tonumber(id) or item.price"),
    ("granted before it is saved", ECON, CHECK, "return savedCache ~= nil and table.find(savedCache, purchaseId) ~= nil",
     "return true"),
    ("a receipt granted twice", ECON, CHECK, "if not table.find(cache, purchaseId) then", "if true then"),
    ("worn without owning it", ECON, CHECK, "if not owns(player, item.id) then", "if false then"),
    ("bought without the tokens", ECON, CHECK, "if profile.Data.Tokens < price then", "if false then"),
    ("a soon item sold", ECON, CHECK, "if item.soon then", "if false then"),
    ("a request racing itself", ECON, CHECK, "if busy[player] or now - (lastAsk[player] or 0) < REQUEST_GAP then",
     "if false then"),
    ("a request that pays", ECON, CHECK, "\t\tprofile.Data.Equipped[id] = nil\n",
     "\t\tprofile.Data.Equipped[id] = nil\n\t\tprofile.Data.Tokens += 1\n"),
    ("a teleport to the finish pays", ECON, CHECK, "if os.clock() - run.startedAt < least then", "if false then"),
    ("a run paid twice", ECON, CHECK, "local run = runs[player]\n\truns[player] = nil", "local run = runs[player]"),
    ("Studio writing the live saves", ECON, CHECK,
     'local name = if RunService:IsStudio() then "PlayerData_Studio" else "PlayerData"', 'local name = "PlayerData"'),
    ("the Studio gift in the live game", ECON, CHECK, "if RunService:IsStudio() and not ready.Data.StudioGift then",
     "if not ready.Data.StudioGift then"),
    ("Robux taken on an unsaved profile", ECON, CHECK, "if not saving and not RunService:IsStudio() then", "if false then"),
    # Every device.
    ("under the notch", SHOP, CHECK, "screen.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets",
     "screen.ScreenInsets = Enum.ScreenInsets.None"),
    ("no way out on a controller", SHOP, CHECK, "Enum.KeyCode.Escape, Enum.KeyCode.ButtonB)", "Enum.KeyCode.Escape)"),
    ("frozen after closing", SHOP, CHECK, "c:Enable()", "c:Disable()"),
    ("price buttons too small for a thumb", SHOP, CHECK, "math.max(MIN_TOUCH + 5,", "math.max(20,"),
    ("a press on the panel closes the shop", SHOP, CHECK, "panel.Active = true", "panel.Active = false"),
    ("the client sends its tokens", SHOP, CHECK, "remote:InvokeServer(action, id)", "remote:InvokeServer(action, id, tokens())"),
    # The wiring.
    ("a run never paid", BOOT, CHECK,
     "pcall(EconomyService.runFinished, player, hardcore, hardcore and newBest == true, finishedId)",
     "pcall(print, player, hardcore, newBest, finishedId)"),
    ("no kiosk", HUB, CHECK, "pcall(HubService.buildKiosk, folder)", "pcall(print, folder)"),
    ("the cursor locked over the shop", VIEW, CHECK, 'playerGui:FindFirstChild("Shop")', 'playerGui:FindFirstChild("Shopp")'),
    # The code still reads.
    ("a name never declared in the layout", SHOP, PARSE, "local gap = math.floor(12 * t)", "local gap = math.floor(12 * tt)"),
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
