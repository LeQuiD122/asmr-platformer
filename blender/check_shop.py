"""The shop and its economy, checked without Studio: nothing dupable, nothing on one device only.

    python blender/check_shop.py

What it holds:
  * THE PRICE LIST (ShopCatalog): every item has a unique id, a tab that exists, exactly one way to pay
    (tokens, or Robux with a pass or product id field), and a colour; every Featured id exists.
  * NOTHING DUPABLE (EconomyService): the client can only name an action and an item; tokens are added in
    two places only (a watched run, a Robux receipt); a buy checks the price from the catalogue, the
    balance, ownership and `soon`; one request at a time per player; a receipt is granted once (its
    PurchaseId kept) and confirmed to Roblox only after a save holding it; a run pays only if the server
    saw it start and it took MIN_SECONDS; saves are session-locked (ProfileStore) and Studio has its own.
  * EVERY DEVICE (ShopService): inside the safe area; nothing pressable under 44 pixels; a controller
    can close it and change tab; Escape closes it; your character stands still while it is open; the
    columns follow the screen's width.
  * WIRED: the remotes made, the run noted and paid, the kiosk in the lobby with Roblox's own prompt,
    the shop in the pause menu, the client starting it, the cursor freed while it is open.
  * THE BACKGROUNDS AND THEIR CRATE (the hundred-and-sixth pass): one for every theme ShopLook draws beyond the
    defaults, each of a rarity; the crate's odds whole, always giving one you lack, rolled on the server, opened never
    bought, and never offered where Roblox's policy keeps paid random items out; the odds said before you pay.
  * ITS LOOK (ShopLook, the hundred-and-fifth pass): every theme whole and drawn, the defaults and the
    chosen one, a press on the background answered only off its buttons, the cookie only with a mouse
    and the system's cursor back when it closes, the tabs each their own colour and sound, the opening
    and closing each their own, and nothing of it left running once it is shut.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
problems = []


def fail(message):
    problems.append(message)


def read(*parts):
    path = SRC.joinpath(*parts)
    return path.read_text(encoding="utf-8") if path.exists() else ""


CATALOG = read("Shared", "ShopCatalog.lua")
ECONOMY = read("Server", "Services", "EconomyService.lua")
SHOP = read("Client", "Services", "ShopService.lua")
BOOT = read("Server", "Bootstrap.server.lua")
CLIENT_BOOT = read("Client", "Bootstrap.client.lua")
HUB = read("Server", "Services", "HubService.lua")
PAUSE = read("Client", "Services", "PauseMenuService.lua")
VIEW = read("Client", "Services", "ViewModeService.lua")
BEST = read("Server", "Services", "BestTimeService.lua")
ONBOARD = read("Client", "Services", "OnboardingService.lua")
STEPS = read("Client", "Services", "StepService.lua")
EMOTE_CLIENT = read("Client", "Services", "EmoteService.lua")
POSES = read("Shared", "Poses.lua")
DEATH = read("Client", "Services", "DeathService.lua")
TIMER = read("Server", "Services", "TimerService.lua")
MATERIALS = read("Shared", "MaterialConfig.lua")
SHOP_LOOK = read("Client", "Services", "ShopLook.lua")

for name, text in (("ShopCatalog", CATALOG), ("EconomyService", ECONOMY), ("ShopService", SHOP)):
    if not text:
        fail("%s.lua is missing" % name)

# ===================================================================== the price list
tabs_match = re.search(r"ShopCatalog\.TABS = \{([^}]*)\}", CATALOG)
tabs = re.findall(r'"(\w+)"', tabs_match.group(1)) if tabs_match else []
if not tabs or tabs[0] != "Featured":
    fail("ShopCatalog.TABS is missing or does not start with Featured")
items = re.findall(r"\{ id = \"(\w+)\", tab = \"(\w+)\", kind = \"(\w+)\",(.*?)\},\n", CATALOG, re.S)
if len(items) < 20:
    fail("ShopCatalog has %d items; the shop was designed with every tab filled" % len(items))
seen = set()
for item_id, tab, kind, rest in items:
    if item_id in seen:
        fail("ShopCatalog lists %s twice" % item_id)
    seen.add(item_id)
    if tab not in tabs or tab == "Featured":
        fail("%s is in a tab that is not shown (%s)" % (item_id, tab))
    price = re.search(r"\bprice = (\d+)", rest)
    robux = re.search(r"\brobux = (\d+)", rest)
    earn = re.search(r'\bearn = "(\w+)"', rest)
    if earn:
        # EARNED, NEVER SOLD: no price of either kind, and earned by something that gives it.
        if price or robux:
            fail("%s is earned and also sold" % item_id)
        # The story gives its own (finishStory); a "starter" one comes with a pass that names it (gives).
        if earn.group(1) == "starter":
            if not re.search(r'\bgives = "%s"' % item_id, CATALOG):
                fail("%s comes with the starter pack, which does not give it" % item_id)
        elif earn.group(1) == "materials":
            if 'if item.earn == "materials" and not data.Owned[item.id] then' not in ECONOMY:
                fail("%s is earned by finding every material, and finding them gives nothing" % item_id)
        elif earn.group(1) == "crate":
            if "function ShopCatalog.rollCrate(" not in CATALOG or 'if action == "crate" or item.kind == "crate" then' not in ECONOMY:
                fail("%s comes out of the background crate, and nothing opens one" % item_id)
        elif earn.group(1) != "story":
            fail("%s is earned by %s, which nothing gives" % (item_id, earn.group(1)))
    elif bool(price) == bool(robux):
        fail("%s must cost tokens or Robux, exactly one" % item_id)
    if price and int(price.group(1)) <= 0:
        fail("%s costs nothing" % item_id)
    if robux and "passId = " not in rest and "productId = " not in rest:
        fail("%s is sold for Robux with no passId or productId to put the Dashboard's id in" % item_id)
    if kind == "tokens" and not re.search(r"\btokens = \d+", rest):
        fail("token pack %s does not say how many tokens it gives" % item_id)
    if "colour = " not in rest or "accent = " not in rest:
        fail("%s has no colours for its tile" % item_id)
    if kind in ("steps", "sound", "emote") and "soon = true" in rest:
        fail("%s is built and still marked soon" % item_id)
featured = re.search(r"ShopCatalog\.FEATURED = \{([^}]*)\}", CATALOG)
for item_id in re.findall(r'"(\w+)"', featured.group(1) if featured else ""):
    if item_id not in seen:
        fail("Featured lists %s, which is not in the catalogue" % item_id)
for tab in tabs[1:]:
    if not any(t == tab for _, t, _, _ in items):
        fail("the %s tab is empty" % tab)
reward = re.search(r"BASE = \{ short = (\d+), medium = (\d+), long = (\d+) \}", CATALOG)
if not reward or not (int(reward.group(1)) < int(reward.group(2)) < int(reward.group(3))):
    fail("REWARD.BASE does not pay more for longer runs")
if not re.search(r"MIN_SECONDS = \{ short = \d+, medium = \d+, long = \d+ \}", CATALOG):
    fail("REWARD.MIN_SECONDS is missing, so a teleport to the finish would pay")

# ===================================================================== nothing dupable
for needle, why in (
    ('store:StartSessionAsync(tostring(player.UserId)', "saves are not opened as locked sessions"),
    ('if RunService:IsStudio() then "PlayerData_Studio" else "PlayerData"', "Studio tests write to the live game's saves"),
    ("p.OnSessionEnd:Connect", "a save taken by another server is not let go of"),
    ("profile:EndSession()", "a leaving player's save is never released"),
    ('if typeof(action) ~= "string" or not ACTIONS[action] then', "the shop request does not check what it is asked"),
    ("local item = ShopCatalog.get(id)", "a request's item is not looked up in the catalogue"),
    ("if item.soon then", "an item marked soon can be bought"),
    ("if owns(player, item.id) then", "an owned item can be bought again"),
    ("if profile.Data.Tokens < price then", "a buy does not check the balance"),
    ("if busy[player] or now - (lastAsk[player] or 0) < REQUEST_GAP then", "requests are not one at a time per player"),
    ("if not owns(player, item.id) then", "an item can be worn without owning it"),
    ("if not table.find(cache, purchaseId) then", "a receipt is not checked against the purchases already granted"),
    ("table.insert(cache, purchaseId)", "a granted purchase is not remembered"),
    ("return savedCache ~= nil and table.find(savedCache, purchaseId) ~= nil", "a purchase is confirmed before it is saved"),
    ("if not saving and not RunService:IsStudio() then", "Robux is taken on a profile that is not saved"),
    ("MarketplaceService.ProcessReceipt = receipt", "Robux purchases are never processed"),
    ("if os.clock() - run.startedAt < least then", "a run finished impossibly fast still pays"),
    ("local run = runs[player]\n\truns[player] = nil", "a finished run could be paid twice"),
):
    if needle not in ECONOMY:
        fail("EconomyService: " + why)
# The two places tokens go up, and only those.
adds = re.findall(r"[Dd]ata\.Tokens \+= ([\w.]+)", ECONOMY)
# (A run's "amount" twice: a run's pay in runFinished, and the story's bonus in finishStory, which only Bootstrap
# calls, after a story's last level, for someone whose own walking got there. And since the hundred-and-sixteenth pass
# the true ending's, once a save, in trueEnding, which only Bootstrap calls, for a rider who clocked in.)
if sorted(adds) != sorted(["STUDIO_TOKENS", "item.tokens", "amount", "amount", "amount", "amount", "amount", "amount", "prize",
                           "starterTokens", "codeTokens", "DEV_TOKENS"]):
    fail("EconomyService adds tokens somewhere other than a run, a token pack, the Studio gift and the Studio "
         "test panel: %s" % adds)
# THE TEST PANEL is Studio's alone: listened to only there, and checking again when it is.
dev_block = ECONOMY[ECONOMY.find("local function onDev("):ECONOMY.find("-- ===== THE SECOND CHANCE =====")]
if not dev_block.startswith("local function onDev(player: Player, action: any)\n\tif not RunService:IsStudio() then\n\t\treturn"):
    fail("the test panel's handler does not refuse outside Studio")
if "if RunService:IsStudio() then\n\t\tlocal dev = events:WaitForChild(\"DevPanel\", 10)" not in ECONOMY:
    fail("the test panel is listened to in the live game")
if 'if game:GetService("RunService"):IsStudio() then\n\tensureRemoteEvent(remoteEventsFolder, "DevPanel")' not in BOOT:
    fail("the test panel's remote is made in the live game")
DEV_CLIENT = read("Client", "Services", "DevPanelClient.lua")
if "function DevPanelClient.start()\n\tif not RunService:IsStudio() then\n\t\treturn" not in DEV_CLIENT:
    fail("the test panel is built in the live game")
if "if RunService:IsStudio() and not ready.Data.StudioGift then" not in ECONOMY:
    fail("the Studio gift of tokens is not limited to Studio")
gift_check = ECONOMY.find("ready.Data.Tokens += STUDIO_TOKENS")
if gift_check < 0 or ECONOMY.rfind("RunService:IsStudio()", 0, gift_check) < 0:
    fail("the Studio gift is not inside a Studio check")
handler = ECONOMY[ECONOMY.find("local function handle("):ECONOMY.find("local function onRequest(")]
# ONE PLACE ONLY: a code posted in the lobby's post box, found in the server's own list (ShopCatalog.CODES), while it
# lasts, once a save. Anywhere else in a request, tokens only go down.
code_branch = handler[handler.find('if action == "code" then'):handler.find("-- UNEQUIP names a kind of thing")]
if handler.replace(code_branch, "").count("Tokens +=") or code_branch.count("Tokens +=") != 1:
    fail("a shop request can add tokens")
for needle, why in (
    ("local entry = if key then ShopCatalog.code(key) else nil\n\t\tif not (key and entry) then\n\t\t\treturn answer(player, false, \"unknown\")",
     "a code not in the server's own list pays"),
    ('if not ends or os.time() >= ends then\n\t\t\treturn answer(player, false, "ended")', "a code pays after it has ended"),
    ('if data.Codes[key] then\n\t\t\treturn answer(player, false, "used")', "a code pays every time it is posted"),
    ("data.Codes[key] = true\n\t\tlocal codeTokens = entry.tokens\n\t\tdata.Tokens += codeTokens", "a code that pays is not kept as posted"),
):
    if needle not in code_branch:
        fail("EconomyService: " + why)
# The buy takes the price from the catalogue, never from the client.
if "local price = item.price" not in handler:
    fail("a buy does not take its price from the catalogue")

# ===================================================================== every device
for needle, why in (
    ("screen.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets", "the shop is not kept inside the safe area (notches)"),
    ("local MIN_TOUCH = 44", "there is no minimum size for things you press"),
    ("Enum.KeyCode.Escape, Enum.KeyCode.ButtonB", "the shop cannot be closed with Escape or a controller's B"),
    ("Enum.KeyCode.ButtonL1, Enum.KeyCode.ButtonR1", "a controller cannot change tab"),
    ("GuiService.SelectedObject = ui.firstTile", "a controller has nothing selected when the shop opens"),
    ("c:Disable()", "your character walks about while the shop is open"),
    ("c:Enable()", "your character stays frozen after the shop closes"),
    ("shop.cols = if w >= 840 then 4 elseif w >= 540 then 3 else 2", "the columns do not follow the screen"),
    ('camera:GetPropertyChangedSignal("ViewportSize")', "the shop is not laid out again when the screen changes"),
    ("tabs.ScrollingDirection = Enum.ScrollingDirection.X", "the tabs do not scroll sideways when they do not fit"),
    ("panel.Active = true", "a press on the panel falls through and closes the shop"),
    ("MarketplaceService:PromptGamePassPurchase(player, passId)", "passes are not sold through Roblox's own window"),
    ("MarketplaceService:PromptProductPurchase(player, productId)", "token packs are not sold through Roblox's own window"),
    ('remote:InvokeServer(action, id)', "the shop sends something other than an action and an item"),
):
    if needle not in SHOP:
        fail("ShopService: " + why)
# Every fixed pressable size is a thumb at least.
for match in re.finditer(r"(\w+)\.Size = UDim2\.fromOffset\(([^,]+), ([^)]+)\)", SHOP):
    name = match.group(1)
    if name in ("more", "close"):
        for value in (match.group(2), match.group(3)):
            if "MIN_TOUCH" not in value:
                fail("ShopService: the %s button is not sized from MIN_TOUCH" % name)
if "math.max(MIN_TOUCH + 5," not in SHOP or "math.max(MIN_TOUCH, math.floor(46 * t))" not in SHOP:
    fail("ShopService: price buttons or tabs can shrink below a thumb")
if re.search(r"\bInvokeServer\([^)]*(Tokens|tokens|price|amount)", SHOP):
    fail("ShopService sends tokens or a price to the server")

# ===================================================================== wired
for needle, why in (
    ('ensureRemoteFunction(remoteFunctionsFolder, "ShopRequest")', "the ShopRequest remote is never made"),
    ('ensureRemoteFunction(remoteFunctionsFolder, "ShopState")', "the ShopState remote is never made"),
    ('ensureRemoteEvent(remoteEventsFolder, "ShopUpdate")', "the ShopUpdate remote is never made"),
    ('ensureRemoteEvent(remoteEventsFolder, "TokensEarned")', "the TokensEarned remote is never made"),
    ("pcall(EconomyService.runStarted, players, HubService.getRequest().length)", "a run's start is never noted"),
    ("pcall(EconomyService.runFinished, player, hardcore, hardcore and newBest == true, finishedId)",
     "a finished run never pays (or never says which level it was)"),
    ("pcall(require, economyModule :: ModuleScript)", "a broken EconomyService could stop the whole server Bootstrap"),
    ("pcall(EconomyService.start)", "EconomyService is never started"),
):
    if needle not in BOOT:
        fail("Bootstrap: " + why)
start_list = re.search(r'for _, name in ipairs\(\{(.*?)\}\) do', CLIENT_BOOT, re.S)
started = re.findall(r'"(\w+)"', start_list.group(1)) if start_list else []
for service in ("ShopService", "OnboardingService", "StepService", "EmoteService"):
    if service not in started:
        fail("the client Bootstrap never starts %s" % service)
for needle, why in (
    ("function HubService.buildKiosk(folder: Folder)", "the lobby has no shop kiosk"),
    ('prompt.Name = "ShopPrompt"', "the kiosk has no prompt"),
    ("pcall(HubService.buildKiosk, folder)", "the kiosk is never built"),
):
    if needle not in HUB:
        fail("HubService: " + why)
if 'prompt.Name == "ShopPrompt" and who == Players.LocalPlayer' not in SHOP:
    fail("ShopService never opens from the kiosk's prompt")
if 'button("Shop", 236' not in PAUSE or "(require(module) :: any).open()" not in PAUSE:
    fail("the pause menu has no way into the shop")
if 'playerGui:FindFirstChild("Shop")' not in VIEW:
    fail("the cursor stays locked over an open shop (ViewModeService)")
if "if improved then\n\t\tremember(player, key, timeSeconds)\n\t\treturn true" not in BEST:
    fail("BestTimeService.submit does not say when a run is a new best")
# A BEST IS NEVER LOST: compared and written in one step, never read first and written after (a failed read let a
# slower time over a better one), and a stored 0 is no time.
best_submit = BEST[BEST.find("function BestTimeService.submit("):BEST.find("function BestTimeService.get(")]
if "store:UpdateAsync(key, function(existing: any): any" not in best_submit or "SetAsync" in best_submit or "GetAsync" in best_submit:
    fail("BestTimeService.submit reads and writes in two steps, so a slower time can overwrite a best")
if 'if typeof(existing) == "number" and existing > 0 and existing <= timeSeconds then' not in best_submit:
    fail("BestTimeService.submit lets a slower time over a best, or a stored 0 stand in the way of a real one")
# AN EMOTE'S STOP is passed on once, for someone with an emote playing.
emote_fn = ECONOMY[ECONOMY.find("local function onEmote("):ECONOMY.find("-- ===== STUDIO ONLY: THE TEST PANEL")]
for needle, why in (
    ('if id == "stop" then\n\t\tif not emoting[player] then\n\t\t\treturn', "a client can make the server pass on stop after stop to everyone"),
    ("emoting[player] = nil\n\t\tremote:FireAllClients(player, \"stop\"", "a stop is passed on more than once"),
    ("emoting[player] = true\n\tremote:FireAllClients(player, item.id", "an emote played is not noted, so its stop is never passed on"),
):
    if needle not in emote_fn:
        fail("EconomyService: " + why)
if "\t\temoting[player] = nil\n\tend)" not in ECONOMY:
    fail("EconomyService: a player who leaves is kept in emoting")

# ===================================================================== footprints and step sounds
if not STEPS:
    fail("StepService.lua is missing, so footprints and step sounds are sold and do nothing")
lives = re.search(r"local PRINT_LIFE: \{ \[string\]: number \} = \{([^}]*)\}", STEPS)
lives = set(re.findall(r"(\w+) = [\d.]+", lives.group(1))) if lives else set()
packs_block = STEPS[STEPS.find("local PACKS: {"):STEPS.find("type Walker")]
packs = set(re.findall(r"^\t(\w+) = \{", packs_block, re.M))
for item_id, tab, kind, rest in items:
    if kind == "steps":
        if item_id not in lives:
            fail("the footprint %s has no life in StepService, so it is never laid" % item_id)
        # drawPrint's own body only: the modelled prints (meshPrint, after it) name some steps too.
        draw_at = STEPS.find("local function drawPrint(")
        draw_block = STEPS[draw_at:STEPS.find("\nend\n", draw_at)]
        if item_id != "BubbleSole" and 'id == "%s"' % item_id not in draw_block:
            fail("the footprint %s has no shape in StepService" % item_id)
    if kind == "sound" and item_id not in packs:
        fail("the step sound %s has no pack in StepService" % item_id)
for needle, why in (
    ("local WEARABLE = { trail = true, aura = true, steps = true, sound = true, background = true }",
     "footprints, step sounds or backgrounds cannot be worn"),
    ('player:SetAttribute("Footprint", if steps and steps.kind == "steps" and owns(player, steps.id) then steps.id else nil)',
     "a footprint is shown without being owned"),
    ('player:SetAttribute("StepSound", if sound and sound.kind == "sound" and owns(player, sound.id) then sound.id else nil)',
     "a step sound is played without being owned"),
    ("if typeof(id) ~= \"string\" or not WEARABLE[id] then", "unequip accepts kinds that cannot be worn"),
):
    if needle not in ECONOMY:
        fail("EconomyService: " + why)
for needle, why in (
    ('local footprint = player:GetAttribute("Footprint")', "footprints are not read from what the server wrote"),
    ('local sound = player:GetAttribute("StepSound")', "step sounds are not read from what the server wrote"),
    ("muteRunning(root, false)", "a step sound silences Roblox's own footstep (it plays alongside it now)"),
    ("while #prints > MAX_PRINTS do", "footprints are never cleared, and pile up"),
    ("part.CanQuery = false", "footprints get in the way of rays and clicks"),
    ("if (root.Position - here).Magnitude > NEAR then", "far-off steps are drawn and played"),
    ("if speed < 2 or speed > 60 or moved > 8 or root.Anchored then", "prints are laid standing still, in a launch or in a scene"),
    ("rayParams.IgnoreWater = true", "prints are laid on the water's surface"),
):
    if needle not in STEPS:
        fail("StepService: " + why)
# THE STEP SOUNDS, AS YOU WANT THEM (2026-10-16): only off the levels (the chunks' own sounds are the game there),
# now and then rather than every step, at their own pitch (never sped up into a squeak), from the game's own takes
# (AudioService's, the same the chunks play), and never an electronic blip, not even as a stand-in.
for needle, why in (
    ('and player:GetAttribute("InLevel") == nil', "a step sound plays on a level, over the chunks"),
    ("if w.count >= w.nextSound then", "a step sound plays on every step, not now and then"),
    ("w.nextSound = math.random(EVERY_LOW, EVERY_HIGH)", "a step sound plays on every step, not now and then"),
    ("s.PlaybackSpeed = 1 - PITCH_SPREAD + math.random() * PITCH_SPREAD * 2", "a step sound is pitched away from its own"),
    ("for _, id in ipairs(audio.takesFor(event)) do", "a step sound does not use the chunks' own takes"),
):
    if needle not in STEPS:
        fail("StepService: " + why)
every = re.search(r"local EVERY_LOW, EVERY_HIGH = (\d+), (\d+)", STEPS)
if not every or int(every.group(1)) < 2 or int(every.group(2)) < int(every.group(1)):
    fail("StepService: a step sound plays too often to be now and then")
spread = re.search(r"local PITCH_SPREAD = ([\d.]+)", STEPS)
if not spread or float(spread.group(1)) > 0.1:
    fail("StepService: a step sound is pitched far from its own (a chunk sped up is a squeak)")
if "electronicping" in STEPS or "rbxasset://sounds/electronic" in STEPS:
    fail("StepService: a step sound can be an electronic blip")
for pack, events in re.findall(r"\n\t(\w+) = \{ events = \{ ([^}]*) \}, volume = ", packs_block):
    if not events.strip():
        fail("StepService: the %s pack has no takes to play" % pack)
if "function AudioService.takesFor(event: string): { string }" not in read("Client", "Services", "AudioService.lua"):
    fail("AudioService: the step sounds cannot have the chunks' own takes")
if "(require(module) :: any).preview(item)" not in SHOP:
    fail("the shop cannot preview footprints or step sounds")

# ===================================================================== emotes
emote_block = EMOTE_CLIENT[EMOTE_CLIENT.find("local EMOTES:"):EMOTE_CLIENT.find("local ORDER")]
emote_poses = dict(re.findall(r'^\t(\w+) = \{ pose = "(\w+)"', emote_block, re.M))
for item_id, tab, kind, rest in items:
    if kind != "emote":
        continue
    pose = emote_poses.get(item_id)
    if not pose:
        fail("the emote %s has nothing in EmoteService to play" % item_id)
    elif "function Poses.%s(" % pose not in POSES:
        fail("the emote %s plays Poses.%s, which does not exist" % (item_id, pose))
emote_server = ECONOMY[ECONOMY.find("local function onEmote("):ECONOMY.find("-- ===== THE SECOND CHANCE =====")]
for needle, why in (
    ('if not item or item.kind ~= "emote" or item.soon or not owns(player, item.id) then', "an emote is played without being owned"),
    ("remote:FireAllClients(player, item.id, workspace:GetServerTimeNow())", "an emote is not shown to everyone"),
    ("if now - (lastEmote[player] or 0) < EMOTE_GAP", "emotes can be spammed"),
):
    if needle not in emote_server:
        fail("EconomyService: " + why)
for needle, why in (
    ("Poses.drive(joint, turn)", "emotes are not posed through the game's joints"),
    ("Poses.drive(joint, CFrame.identity)", "an emote's pose is never let go of"),
    ("Vector3.new(v.X, 0, v.Z).Magnitude > MOVING", "moving does not end an emote"),
    ('state.remote:FireServer("stop")', "your own emote is not stopped on everyone's screen when you move"),
    ("return not (cinema and cinema.active and cinema.active())", "an emote can be played over an ending's scene"),
):
    if needle not in EMOTE_CLIENT:
        fail("EmoteService: " + why)

# ===================================================================== the second chance
chance_grant = ECONOMY[ECONOMY.find("local function receipt("):ECONOMY.find("-- ===== RUNS =====")]
if 'elseif item.id == "SecondChance" then' not in chance_grant or "profile.Data.SecondChances += 1" not in chance_grant:
    fail("a bought second chance is never kept")
if "(profile.Data.SecondChances or 0) < 1 then\n\t\treturn false" not in ECONOMY:
    fail("a second chance can be used without one")
for needle, why in (
    ("\tnoteFall(player)\n\tTimerService.resetTimer(player)", "the surge's reset forgets where the runner was before it is undone"),
    ("\t\t\t\tnoteFall(player)\n\t\t\t\tTimerService.resetTimer(player)", "a fall forgets where the runner was before it is undone"),
    ("if os.clock() - fall.at > secondChance.WINDOW", "a second chance can be used any time after a fall"),
    ("if not EconomyService.spendChance(player) then\n\t\t\t\treturn", "a second chance is given without being spent"),
    ("TimerService.resume(player, fall.elapsed)", "the clock is not put back where it was"),
    ("now.usedChance = true", "a run carried on by a second chance is not marked"),
    ("local counted = not usedChance and fairTime(player, state)", "a bought second chance can set a best"),
    ("local newBest = if counted then BestTimeService.submit(", "a bought second chance can set a best"),
    ("if counted then\n\t\t\t\tLeaderboardService.submitTime(", "a bought second chance can buy a leaderboard place"),
    ("state.checkpointChunkIndex < 2", "a second chance is offered with nowhere to go back to"),
):
    if needle not in BOOT:
        fail("Bootstrap: " + why)
if "function TimerService.resume(player: Player, elapsed: number)" not in TIMER:
    fail("TimerService cannot put a clock back")
for needle, why in (
    ("DeathService.show(offer == true)", "the death card is not told whether there is a second chance"),
    ("if chance.owned > 0 then", "the death card does not use a second chance that is owned"),
    ("MarketplaceService:PromptProductPurchase(Players.LocalPlayer, productId)", "a second chance cannot be bought from the death card"),
    ("MarketplaceService.PromptProductPurchaseFinished:Connect(", "a second chance bought on the death card is not used"),
):
    if needle not in DEATH:
        fail("DeathService: " + why)

# ===================================================================== the first five minutes
if not ONBOARD:
    fail("OnboardingService.lua is missing")
hints_block = re.search(r"local HINTS: \{ \[string\]: string \} = \{(.*?)\n\}", ONBOARD, re.S)
hints = dict(re.findall(r'^\t(\w+) = "([^"]*)",', hints_block.group(1), re.M)) if hints_block else {}
materials = re.findall(r"^\t([A-Z][A-Za-z]+) = \{", MATERIALS, re.M)
for material in materials:
    if material not in hints:
        fail("%s has no first-time hint, so a new player meets it with no idea what it does" % material)
for material, text in hints.items():
    if material not in materials:
        fail("there is a hint for %s, which is not a material" % material)
    if "--" in text or "\u2014" in text or "\u2013" in text:
        fail("the %s hint has a dash in it" % material)
    if len(text) > 90:
        fail("the %s hint is too long to read in a moment (%d characters)" % (material, len(text)))
for text in re.findall(r'(?:title|body|say) = "([^"]*)"', ONBOARD):
    if "--" in text or "\u2014" in text or "\u2013" in text:
        fail("a line in the welcome or the guide has a dash in it: %s" % text[:50])
for needle, why in (
    ("if not data.welcomed and not state.welcomeShown then", "the welcome is not limited to a first visit"),
    ('note("welcomed")', "a finished welcome is never noted, so it would come back every visit"),
    ('note("guided")', "a skipped or finished guide is never noted"),
    ('note("hinted", name)', "a hint shown is never noted, so it would come back every run"),
    ('note("shopIntro")', "the way to the shop never goes away"),
    ("pill.Active = false", "the hint line can take a press meant for the game"),
    ("if inLobby() or state.welcomeOpen then", "hints are not kept to the levels"),
    ("Enum.KeyCode.Escape, Enum.KeyCode.ButtonB", "the welcome cannot be closed with Escape or a controller's B"),
    ("GuiService.SelectedObject = ui.primary", "a controller has nothing selected on the welcome"),
    ("freeze(true)", "you walk about behind the welcome"),
    ("freeze(false)", "you stay frozen after the welcome"),
    ("local height = kit.MIN_TOUCH + 9", "the welcome's buttons are not thumb-sized"),
    ("UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled", "the welcome does not show touch controls on a phone"),
    ('return "Left stick to move', "the welcome does not show a controller's controls"),
):
    if needle not in ONBOARD:
        fail("OnboardingService: " + why)
# Skipping the welcome (or finishing it outside the lobby) is the guide declined: noted there, or the
# guide would start itself on the next visit.
finish_block = ONBOARD[ONBOARD.find("local function finishWelcome("):ONBOARD.find("local function buildWelcome(")]
if 'note("guided")' not in finish_block or 'note("welcomed")' not in finish_block:
    fail("OnboardingService: skipping the welcome does not note it, so the welcome or the guide comes back")
if ONBOARD.count("ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets") < 2:
    fail("OnboardingService: the welcome or the hint line is not kept inside the safe area")
# The guide points at things that exist.
for pad in re.findall(r'pad = "(\w+)"', ONBOARD) + ["KioskCounter"]:
    if pad.startswith("LevelPad_"):
        ok = '"LevelPad_" .. tostring(level.levelId)' in HUB
    elif pad.startswith("OptionPad_"):
        field, value = pad.split("_")[1:3]
        ok = '"OptionPad_" .. row.field .. "_" .. value' in HUB and ('"%s"' % value) in HUB
    elif pad == "StartPad":
        ok = 'startPad.Name = "StartPad"' in HUB
    else:
        ok = '"%s"' % pad in HUB
    if not ok:
        fail("the guide points at %s, which the lobby does not build" % pad)
# The server's side: flags only, a few at a time, and the funnel.
note_block = ECONOMY[ECONOMY.find("local function onNote("):ECONOMY.find("-- ===== THE EMOTES =====")]
if not note_block:
    fail("EconomyService has no onboarding notes")
if "Tokens" in note_block or "Owned" in note_block:
    fail("an onboarding note can change tokens or what is owned")
for needle, why in (
    ('if typeof(what) ~= "string" or not NOTES[what] then', "a note is not checked against the five"),
    ('not name:match("^%a+$")', "a hint's material name is not checked"),
    ("if count >= MAX_HINTS then", "hints are not capped"),
    ("if window.count > 8 then", "notes are not limited to a few at a time"),
):
    if needle not in note_block:
        fail("EconomyService: " + why)
if "local NOTES = { welcomed = true, guided = true, hinted = true, shopIntro = true, favourite = true }" \
        not in ECONOMY:
    fail("EconomyService: the notes accepted are not exactly the five")

# THE FAVOURITE, ASKED ONCE EVER: noted on the server like the rest of the first five minutes (and only
# set, never cleared, by a note), noted before Roblox's prompt is asked for so a declined or failed prompt
# is not asked again, not asked of someone whose favourite it already is, only after the way to the kiosk,
# back in the lobby from a finished run, with nothing else on screen.
for needle, why in (
    ('\telseif what == "favourite" then\n\t\tif data.AskedFavourite then\n\t\t\treturn\n\t\tend\n'
     '\t\tdata.AskedFavourite = true\n', "the favourite ask is not noted once on the server"),
):
    if needle not in note_block:
        fail("EconomyService: " + why)
if "AskedFavourite = false, -- asked once" not in ECONOMY or "askedFavourite = profile.Data.AskedFavourite" not in ECONOMY:
    fail("EconomyService: the save does not keep whether the favourite was asked, or never says so")
fav = ONBOARD[ONBOARD.find("local function stepFavourite()"):ONBOARD.find("-- ===== WHAT THE SERVER SAYS =====")]
if not fav:
    fail("OnboardingService: there is no favourite ask")
else:
    for needle, why in (
        ("data.shopIntro and not data.askedFavourite and state.finishedRun", "the favourite is asked before the way "
         "to the kiosk, without a finished run, or again"),
        ("and not state.favouriteAsked and inLobby() and not state.guiding and not state.welcomeOpen",
         "the favourite is asked during a run, the guide or the welcome"),
        ("and not state.shopPointer and not shopOpen()", "the favourite is asked over the shop or its pointer"),
        ("if now - since < FAVOURITE_SETTLE then", "the favourite is asked the moment you arrive"),
        ("AvatarEditorService:GetFavoriteAsync(game.PlaceId, Enum.AvatarItemType.Asset)",
         "the favourite is asked of someone whose favourite it already is"),
        ("if ok and already == true then\n\t\t\treturn", "the favourite is asked of someone whose favourite it already is"),
        ("pcall(function()\n\t\t\tAvatarEditorService:PromptSetFavorite(", "a favourite prompt that fails can break the step"),
    ):
        if needle not in fav:
            fail("OnboardingService: " + why)
    noted = fav.find('note("favourite")')
    if noted < 0 or noted > fav.find("PromptSetFavorite"):
        fail("OnboardingService: the favourite is asked before it is noted, so a failed prompt is asked again")
if "stepShop()\n\t\t\tstepFavourite()" not in ONBOARD:
    fail("OnboardingService: the favourite ask is never stepped")
if "if before and before.shopIntro and (data.earned or 0) > (before.earned or 0) then\n\t\tstate.finishedRun = true" \
        not in ONBOARD:
    fail("OnboardingService: a finished run is never noticed, or the favourite comes straight after the kiosk")
if "data.AskedFavourite = true\n\t\tpush(player)\n\t\tdata.AskedFavourite = false" not in ECONOMY:
    fail("EconomyService: the test panel's favourite ask again is not seen as a change, so nothing is asked")
if '{ action = "favourite", text = "Favourite ask again" }' not in DEV_CLIENT \
        or 'elseif action == "favourite" then' not in ECONOMY:
    fail("the test panel cannot bring the favourite ask back")

# AN INVITE, FROM ANYWHERE: the pause menu's third button on the shop's row, Roblox's own invite screen only
# when this account may send one, and a word from Roblox's corner when it may not.
for needle, why in (
    ('local inviteButton = button("Invite", 236', "there is no way to invite a friend (the pause menu)"),
    ("inviteButton.Size = UDim2.new(1 / 3, -23, 0, 44)", "the invite button is not a third of the row"),
    ("task.spawn(invite)", "the invite button does nothing"),
    ("return SocialService:CanSendGameInviteAsync(me)", "the invite screen is asked for without asking whether it may be"),
    ("if ok and can then\n\t\tpcall(function()\n\t\t\tSocialService:PromptGameInvite(me, inviteOptions())", "the invite screen is "
     "opened when it may not be, or unguarded"),
    ('StarterGui:SetCore("SendNotification"', "a refused invite says nothing"),
):
    if needle not in PAUSE:
        fail("PauseMenuService: " + why)

# A TIME THAT COUNTS (Bootstrap.fairTime): another go only from the start, and a best or a board place only for
# a hardcore time the server saw run, along the route, and not impossibly fast. No 0 is kept as a best.
fair = BOOT[BOOT.find("local function walkedRoute("):BOOT.find("local secondChance = {")]
if not fair:
    fail("Bootstrap: there is no rule for which times count")
else:
    for needle, why in (
        ('if not levelInstance or state.mode ~= "hardcore" then\n\t\treturn false', "a chill run (no clock) can set a best"),
        ("if elapsed <= 0 then\n\t\treturn false", "a run with no time can set a best"),
        ('def.category == "stable" and index <= count * 0.75', "a time counts without the route being walked"),
        ("if (state.checkpointChunkIndex or 0) < needed then", "a time counts without the route being walked"),
        ("if floor and elapsed < floor * 0.5 then", "an impossibly fast time counts"),
        ("if not walkedRoute(player, state) then\n\t\treturn false", "a time counts without the route being walked"),
    ):
        if needle not in fair:
            fail("Bootstrap: " + why)
# TOKENS ONLY FOR A ROUTE WALKED: waiting out MIN_SECONDS and jumping to the finish pays nothing.
for needle, why in (
    ("local walked = walkedRoute(player, state)", "tokens are paid for a run whose route was never walked"),
    ("if EconomyService and walked then", "tokens are paid for a run whose route was never walked"),
):
    if needle not in BOOT:
        fail("Bootstrap: " + why)
if "fastest = catalog.REWARD.MIN_SECONDS" not in BOOT or "runLength = HubService.getRequest().length" not in BOOT:
    fail("Bootstrap: the fastest a run can be played is not known, or not for this run's length")
retry = BOOT[BOOT.find("HardcoreRetry.OnServerEvent:Connect("):BOOT.find("LeaveLevel.OnServerEvent:Connect(")]
if "if not HubService.isInRun(player) or not PlayerStateService.canToggleMode(player) then" not in retry:
    fail("Bootstrap: another go is taken from anywhere in a run, so the clock can be started again near the end")
for needle, why in (
    ("if timeSeconds <= 0 then\n\t\treturn false", "a time of 0 is saved as a best"),
    ('typeof(value) == "number" and value > 0 then', "a best of 0 saved before shows on the lobby board as 00:00"),
):
    if needle not in BEST:
        fail("BestTimeService: " + why)
steps = sorted(int(n) for n in re.findall(r"funnel\(player, (\d+),", ECONOMY))
if steps != list(range(1, 8)):
    fail("the onboarding funnel is not steps 1 to 7, once each: %s" % steps)
if "AnalyticsService:LogOnboardingFunnelStepEvent(player, step, name)" not in ECONOMY:
    fail("the onboarding funnel is never logged")
if 'ensureRemoteEvent(remoteEventsFolder, "Onboarding")' not in BOOT:
    fail("Bootstrap never makes the Onboarding remote")
if 'playerGui:FindFirstChild("Welcome")' not in VIEW:
    fail("the cursor stays locked over the welcome (ViewModeService)")
if "ShopService.kit = {" not in SHOP:
    fail("ShopService does not share its kit, so the welcome has no look")

# A PASS PAID FOR IS A PASS HAD: an ownership check Roblox does not answer is not taken as "not owned" but asked
# again, further apart, and the pass applied (and worn) the moment one answers. And every Robux prompt's close,
# bought or not, is on the dashboard, item by item, guarded.
owns = ECONOMY[ECONOMY.find("local function ownsPass("):ECONOMY.find("local function load(")]
for needle, why in (
    ("if not ok then\n\t\treturn nil\n\tend", "a failed ownership check reads as not owning the pass"),
    ("elseif has == nil then\n\t\t\t\ttable.insert(unsure, item)", "a failed ownership check is never asked again"),
    ("\tif #unsure > 0 then\n\t\ttask.spawn(function()", "a failed ownership check is never asked again"),
    ("for _ = 1, 5 do\n\t\t\t\ttask.wait(gap)\n\t\t\t\tgap *= 2", "a failed ownership check is asked again at once, or forever"),
    ("\t\t\t\t\tpush(player)\n\t\t\t\t\tdress(player)\n", "a pass found on asking again is not applied"),
):
    if needle not in owns:
        fail("EconomyService: " + why)
for needle, why in (
    ('MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId: number, productId: number, bought: boolean)\n'
     '\t\tpromptClosed(Players:GetPlayerByUserId(userId), "ProductPrompt", ShopCatalog.byProduct(productId), bought)',
     "a product's prompt closing is not on the dashboard"),
    ('\t\tpromptClosed(player, "PassPrompt", item, bought)\n', "a pass's prompt closing is not on the dashboard"),
    ("\t\tpcall(function()\n\t\t\tAnalyticsService:LogCustomEvent(player, event,", "the dashboard's prompt events are not guarded"),
):
    if needle not in ECONOMY:
        fail("EconomyService: " + why)

# THE SELF-TEST (the test panel's, Studio only through onDev) runs the shop's own handler on the save, then puts
# the save back exactly as it was, in the same table, with any real run the player was in.
selftest = ECONOMY[ECONOMY.find("local function selfTest("):ECONOMY.find("local function onDev(")]
for needle, why in (
    ("local before = deepCopy(data)", "the self-test does not keep a copy of the save to put back"),
    ("local realRun = runs[player]", "the self-test can lose a run the player is really in"),
    ('local result = handle(player, "buy", pick.id)', "the self-test does not use the shop's own handler"),
    ("for key in pairs(data) do\n\t\tdata[key] = nil\n\tend\n\tfor key, value in pairs(before) do\n\t\tdata[key] = value",
     "the self-test does not put the save back (in the same table)"),
    ("\truns[player] = realRun\n", "the self-test can lose a run the player is really in"),
):
    if needle not in selftest:
        fail("EconomyService: " + why)
for needle, why in (
    ("local first = EconomyService.spendChance(player)\n\t\tlocal second = EconomyService.spendChance(player)",
     "the self-test does not try a second chance twice"),
    ('onNote(player, "Tokens", 999)', "the self-test does not try a note the server should ignore"),
    ("\tlastNote[player] = realNote\n", "the self-test leaves its notes counted against the player's real ones"),
    ('check("read again at once, from what was kept", againOk and took < 0.05',
     "the self-test does not show the leaderboard is kept"),
):
    if needle not in selftest:
        fail("EconomyService: " + why)
# NOTHING WAITS while the save is changed (the store reads wait on Roblox, so they come after it is put back):
# anything that happened to the save during a wait would be wiped by the putting back.
phase = selftest[selftest.find("local ran, err = pcall(function()"):selftest.find("-- THE SAVE PUT BACK")]
if "task.wait" in phase or "serviceNamed(" in phase or ":Wait()" in phase:
    fail("EconomyService: the self-test waits while it has the save changed")
if selftest.find('serviceNamed("LeaderboardService")') < selftest.find("\truns[player] = realRun\n"):
    fail("EconomyService: the self-test reads the stores before the save is put back")
if 'elseif action == "selftest" then\n\t\ttask.spawn(selfTest, player)' not in ECONOMY:
    fail("EconomyService: the test panel's Self-test does nothing")
# AND ITS CLIENT HALF: the shop, the journal and the emote picker opened and closed for real, each guarded, each
# checked as shown and as gone.
client_test = DEV_CLIENT[DEV_CLIENT.find("local function clientSelfTest("):DEV_CLIENT.find("local function build(")]
for needle, why in (
    ("local opened, err = pcall(shop.open)", "the client's self-test does not open the shop (or not guarded)"),
    ('check("the shop closes", closed and shop.isOpen() == false', "the client's self-test does not see the shop close"),
    ('local opened, err = pcall(journal.open, "keepsake")', "the client's self-test does not open the journal"),
    ('check("the journal closes", closed and journal.isOpen() == false', "the client's self-test does not see the journal close"),
    ("local opened, err = pcall(emotes.open)", "the client's self-test does not open the emote picker (or not guarded)"),
    ('check("the emote picker closes", closed and panel ~= nil', "the client's self-test does not see the emote picker close"),
    ('("SELF-TEST (client): %d of %d passed.', "the client's self-test does not say how it went"),
):
    if needle not in client_test:
        fail("DevPanelClient: " + why)
for needle, why in (
    ("close()\n\ttask.wait(0.3)\n\tlocal locked = UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter",
     "the client's self-test reads the cursor with the test panel still freeing it"),
    ('check(label .. ": the cursor free to press it", UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter)',
     "the client's self-test does not see whether the cursor is free"),
    ('cursorFree("the death card")', "the client's self-test does not check the cursor over the death card"),
    ("local opened, err = pcall(pause.setOpen, true)", "the client's self-test does not open the pause menu"),
    ('check("the pause menu closes", closed and pause.isOpen() == false', "the client's self-test does not see the pause menu close"),
    ("local shown, err = pcall(death.show, false)", "the client's self-test does not show the death card"),
    ('check("the death card goes", hidden and cardGui ~= nil', "the client's self-test does not see the death card go"),
):
    if needle not in client_test:
        fail("DevPanelClient: " + why)
# WHAT WAS BUILT, AND THE SERVER ANSWERING: the server's half counts the shelf's toys and cards against the
# keepsakes and finds this player's own statue; the client's half asks the save, the journal and the leaderboard
# through the game's own remotes, guarded, and a "not ready" is not an answer.
for needle, why in (
    ("toys == keepsakes and cards == keepsakes", "the self-test does not count the shelf against the keepsakes"),
    ('if stand:GetAttribute("Owner") == player.UserId then', "the self-test takes anyone's statue for this player's"),
):
    if needle not in selftest:
        fail("EconomyService: " + why)
for needle, why in (
    ('{ name = "JournalState", label = "the journal answers", ready = true },', "the client's self-test does not ask the journal"),
    ("local asked, answer = pcall(function()\n\t\t\t\treturn remote:InvokeServer()\n\t\t\tend)",
     "the client's self-test asks the server unguarded"),
    ("(not ask.ready or answer.ready == true)", "the client's self-test takes a save that is not ready as an answer"),
):
    if needle not in client_test:
        fail("DevPanelClient: " + why)
for needle, why in (
    ('shown ~= nil and shown:IsA("IntValue") and shown.Value == saved', "the self-test does not compare the player list's "
     "Keepsakes with the save"),
    ('player:GetAttribute("Tokens") == data.Tokens', "the self-test does not compare the tokens shown with the save"),
):
    if needle not in selftest:
        fail("EconomyService: " + why)
# Both after the save is put back, so they compare what is really there.
if selftest.find('shown.Value == saved') < selftest.find("\truns[player] = realRun\n"):
    fail("EconomyService: the self-test compares what is shown before the save is put back")
PAUSE_SRC = read("Client", "Services", "PauseMenuService.lua")
if "function PauseMenuService.setOpen(on: boolean)" not in PAUSE_SRC or "function PauseMenuService.isOpen(): boolean" not in PAUSE_SRC:
    fail("PauseMenuService cannot be opened and closed from outside, so the self-test cannot try it")
if 'if button.action == "selftest" then\n\t\t\t\ttask.spawn(clientSelfTest)' not in DEV_CLIENT:
    fail("DevPanelClient: the Self-test button does not run the client's half")
if '{ action = "selftest", text = "Self-test" }' not in DEV_CLIENT:
    fail("DevPanelClient: there is no Self-test button")

# THE VIP TAG: over a VIP player's head (the server's BillboardGui, so everyone sees it), only for VIP, taken off
# when they are not, put on with their clothes, and put away on a level; the shop says so; the test panel can turn
# VIP on and off in Studio to see it.
vip = ECONOMY[ECONOMY.find("local function vipTag("):ECONOMY.find('local KEY_TAG = "KeyTag"')]
for needle, why in (
    ("local isVip = passes[player] ~= nil and passes[player].VIP == true", "the VIP tag is given to players without VIP"),
    ("\t\tif existing then\n\t\t\texisting:Destroy()\n\t\tend\n\t\treturn", "a VIP tag stays on someone without VIP"),
    ("gui.Parent = head", "the VIP tag is not over the head"),
    ("gui.Size = UDim2.new(2.7, 0, 1.25, 0)", "the VIP tag is not sized in studs (it would stay huge far away)"),
    ("gui.MaxDistance = 80", "the VIP tag is drawn from any distance"),
    ('shown.Enabled = player:GetAttribute("InLevel") == nil', "the VIP tag shows on a level"),
):
    if needle not in vip:
        fail("EconomyService: " + why)
for needle, why in (
    ('"Cosmetic")\n\tvipTag(player)\n', "the VIP tag is not put on with the rest (dress)"),
    ('player:GetAttributeChangedSignal("InLevel"):Connect(function()\n\t\t\tvipTag(player)',
     "the VIP tag does not come off on a level and back in the lobby"),
    ('elseif action == "vip" then', "the test panel cannot turn VIP on to see the tag"),
):
    if needle not in ECONOMY:
        fail("EconomyService: " + why)
if '{ action = "vip", text = "VIP on/off" }' not in DEV_CLIENT:
    fail("DevPanelClient: there is no VIP on/off button")
if 'blurb = "A VIP tag over your head and in chat, and the gold sparkle"' not in CATALOG:
    fail("ShopCatalog: the VIP pass does not say it puts a tag over your head")

# NEAR THE END (Studio only, Bootstrap): the test panel puts you at a checkpoint about eight chunks before the
# finish of the run you are in, and that run then counts for nothing (walkedRoute refuses a skipped run: no tokens,
# no time, no level opened). Only for a run you are in and have not finished. And the client's half of the Self-test
# looks at the lobby's pads (City Shore open; locked ones boarded up and saying so) and the VIP tag over your head.
near = BOOT[BOOT.find("-- ===== STUDIO ONLY: NEAR THE END ====="):]
near = near[:near.find("\nend\n") + 5]
for needle, why in (
    ('if game:GetService("RunService"):IsStudio() then', "Near the end is not kept to Studio"),
    ('if action ~= "nearEnd" then', "Near the end answers other buttons"),
    ("HubService.isInRun(player) and state and not state.hasCompletedLevel", "Near the end moves someone not in a run (or finished)"),
    ("local last = math.max(#chunks - 8, 2)", "Near the end does not leave a last stretch to walk"),
    ('def.category == "stable"', "Near the end puts you somewhere that is not a checkpoint"),
    ("PlayerStateService.setCheckpoint(player, at, target.index, -tangent)", "a fall after Near the end sends you back to the start"),
):
    if needle not in near:
        fail("Bootstrap: " + why)
if near.find("state.skipped = true") < 0 or near.find("state.skipped = true") > near.find("root.CFrame = "):
    fail("Bootstrap: a run skipped with Near the end still counts (it is moved before it is marked)")
walked = BOOT[BOOT.find("local function walkedRoute("):BOOT.find("local function fairTime(")]
if "if state.skipped then" not in walked:
    fail("Bootstrap: a run skipped with Near the end pays, keeps a time and opens the next level")
if '{ action = "nearEnd", text = "Near the end" }' not in DEV_CLIENT:
    fail("DevPanelClient: there is no Near the end button")
client_pads = DEV_CLIENT[DEV_CLIENT.find("-- THE LOBBY'S LEVEL PADS as this screen sees them"):DEV_CLIENT.find("local failed, lines = 0, {}")]
for needle, why in (
    ('check("City Shore is open", not locked)', "the self-test does not check City Shore is open"),
    ("boards == 2 and up == wanted and says == locked", "the self-test does not check the pads' boards and signs"),
    ("(tag ~= nil) == vip and shownRight", "the self-test does not check the VIP tag"),
):
    if needle not in client_pads:
        fail("DevPanelClient: " + why)

# THE SELF-TEST OPENS AND LOCKS A LEVEL THROUGH THE LOBBY: City Shore open; finished in the save, Sky Pools opens;
# taken back, Sky Pools is as the other players here leave it; and the lobby looks again once the save is put back.
for needle, why in (
    ('check("City Shore is open", isOpen(opener.levelId) == true)', "the self-test does not check City Shore is open"),
    ("finished[key] = true\n\t\t\ttellLevels()\n\t\t\tcheck(\"City Shore finished opens Sky Pools\", isOpen(opened.levelId) == true)",
     "the self-test does not open Sky Pools through the lobby"),
    ("isOpen(opened.levelId) == others)", "the self-test does not see Sky Pools lock again"),
    ('check("the lobby reads the saves", false,', "the self-test passes with no lobby wired to the save"),
    ("\tstepGear(player)\n\ttellLevels()\n", "after the self-test the lobby keeps the levels it opened"),
):
    if needle not in selftest:
        fail("EconomyService: " + why)
if "EconomyService.setOpenReader(HubService.isOpen)" not in BOOT:
    fail("Bootstrap: the self-test cannot see the lobby's open levels")

# GETTING FURTHER KEEPS A LEVEL OPEN, so the Self-test expects Sky Pools to stay open for anyone who has finished any
# level; and a new player is told that finishing a level opens the next (the welcome, and the guide's first step).
if "local theirs = EconomyService.finishedLevels(other)\n\t\t\t\tfor _, level in ipairs(LevelDefinitions.All) do" not in selftest:
    fail("EconomyService: the self-test expects Sky Pools to lock for a player who has got further")
ONBOARD = read("Client", "Services", "OnboardingService.lua")
if "Each level is a route of materials to its end, and finishing one opens the next." not in ONBOARD:
    fail("OnboardingService: the welcome does not say that finishing a level opens the next")
if 'say = "Step on City Shore, the first level. Finishing it opens the next." }' not in ONBOARD:
    fail("OnboardingService: the guide's first step does not say that finishing City Shore opens the next")

# ADMINS OPEN EVERY LEVEL FOR THEMSELVES (/levels): only the owner (a group game's owner), ADMIN_IDS and Studio;
# anyone else is ignored; kept in the save as AdminOpen; their own progress untouched (the lobby is told they have
# finished everything, the save is not) and still recorded for real when they finish a level; said on their card.
admin = ECONOMY[ECONOMY.find("-- ===== ADMINS ====="):ECONOMY.find("-- The save's finished levels, made if an older save has none.")]
for needle, why in (
    ("if RunService:IsStudio() or ADMIN_IDS[player.UserId] == true then", "an admin is not Studio or someone listed"),
    ("return game.CreatorId ~= 0 and player.UserId == game.CreatorId", "the game's owner is not an admin (or everyone is, unpublished)"),
    ("return groupOwner[player] == true", "a group game's owner is not an admin"),
    ("if not (profile and profile:IsActive()) or not EconomyService.isAdmin(player) then\n\t\treturn",
     "anyone can open every level with /levels"),
    ("profile.Data.AdminOpen = on\n", "/levels is not kept in the save"),
    ("\ttellLevels()\n", "/levels does not open the lobby's levels at once"),
):
    if needle not in admin:
        fail("EconomyService: " + why)
if "AdminOpen = false," not in ECONOMY:
    fail("EconomyService: a new save has no AdminOpen")
if "groupOwner[player] = ok and rank == 255" not in ECONOMY:
    fail("EconomyService: a group game's owner is never found")
if "\tgroupOwner[player] = nil\n" not in ECONOMY[ECONOMY.find("local function unload("):]:
    fail("EconomyService: whether a player owns the group is kept after they leave")
finished_levels = ECONOMY[ECONOMY.find("function EconomyService.finishedLevels("):ECONOMY.find("function EconomyService.setLevelsChanged(")]
if "if profile.Data.AdminOpen == true and EconomyService.isAdmin(player) then\n\t\tlocal all: { [string]: boolean } = {}" not in finished_levels:
    fail("EconomyService: an admin's /levels does not open the levels (or writes into their save)")
if "local finished = finishedOf(profile.Data)" not in ECONOMY[ECONOMY.find("function EconomyService.runFinished("):]:
    fail("EconomyService: an admin's real progress is not recorded when they finish a level")
chat = ECONOMY[ECONOMY.find("-- /levels FOR AN ADMIN (toggleAdminOpen)"):]
for needle, why in (
    ('command.PrimaryAlias = "/levels"', "there is no /levels chat command"),
    ("local who = Players:GetPlayerByUserId(source.UserId)", "/levels is not taken as from the player who typed it"),
    ('if string.lower(message) == "/levels" then', "/levels does nothing in a place on the old chat"),
):
    if needle not in chat:
        fail("EconomyService: " + why)
if 'HubVoteState:FireClient(player, "admin", { on = on })' not in BOOT:
    fail("Bootstrap: an admin is not told what /levels did")
VOTE_CLIENT = read("Client", "Services", "HubVoteService.lua")
if 'elseif kind == "admin" then\n\t\t\tHubVoteService.onAdmin(payload)' not in VOTE_CLIENT:
    fail("HubVoteService: the vote card never says what /levels did")

# THE SELF-TEST SEES THE STORY: its place kept in the save, read back and kept in range (the server's half), and the
# Story pad in the lobby, open (the client's).
if 'check("the story\'s place kept, and kept in range", storyKept == 3 and storyCapped == #LevelDefinitions.All,' not in selftest:
    fail("EconomyService: the self-test does not check the story's place in the save")
if 'check("the Story pad, open", hub == nil or (storyPad ~= nil and storyPad:GetAttribute("Locked") ~= true),' not in DEV_CLIENT:
    fail("DevPanelClient: the self-test does not look for the Story pad")

# ROBLOX BADGES (ShopCatalog.BADGES, 0 until made): a level's for a run really played, the story's at its end (on
# foot), and a whole story in Hardcore; nothing asked for an id of 0; each asked once a session; the paste check lists
# the ones still to make.
if "ShopCatalog.BADGES = {" not in CATALOG or "level = { [1] = 0, [2] = 0, [3] = 0, [4] = 0, [5] = 0 }," not in CATALOG:
    fail("ShopCatalog: there are no badges to set (or one starts set)")
award = ECONOMY[ECONOMY.find("function EconomyService.awardBadge("):ECONOMY.find("function EconomyService.awardStoryBadges(")]
for needle, why in (
    ('if type(badgeId) ~= "number" or badgeId == 0 then\n\t\treturn', "a badge not made yet is asked for"),
    ("if asked[badgeId] then\n\t\treturn", "a badge is asked for on every finish (Roblox limits badge calls)"),
    ("BadgeService:AwardBadge(player.UserId, badgeId)", "no badge is ever awarded"),
    ("local ok, err = pcall(function()", "a badge Roblox refuses stops the finish"),
):
    if needle not in award:
        fail("EconomyService: " + why)
finish = ECONOMY[ECONOMY.find("function EconomyService.runFinished("):]
fast = finish.find("faster than it can be played")
level_badge = finish.find("EconomyService.awardBadge(player, badges.level[levelId])")
if level_badge < 0 or fast < 0 or level_badge < fast:
    fail("EconomyService: a level's badge is not awarded, or awarded for a run finished faster than it can be played")
story_badges = ECONOMY[ECONOMY.find("function EconomyService.awardStoryBadges("):]
if "EconomyService.awardBadge(player, badges.story)\n\tif wholeHardcore then\n\t\tEconomyService.awardBadge(player, badges.storyHardcore)" not in story_badges:
    fail("EconomyService: the story's badges are not awarded (or the Hardcore one for any story)")
if "\tbadgeAsked[player] = nil\n" not in ECONOMY[ECONOMY.find("local function unload("):]:
    fail("EconomyService: which badges were asked for is kept after the player leaves")
if "if walked and EconomyService and EconomyService.awardStoryBadges then\n\t\t\t\t\tpcall(EconomyService.awardStoryBadges, player, fair)" not in BOOT:
    fail("Bootstrap: the story's badges are not awarded at its end (or for a last level not walked)")
if 'print("PASTE CHECK: badges not made yet, no id in ShopCatalog.BADGES' not in BOOT:
    fail("Bootstrap: the paste check does not say which badges are still to make")

# THE STORY'S REWARD: its bonus and the green ribbon, given only by finishStory, which Bootstrap calls only after a
# story's last level, walked, for someone whose own walking reached it (not someone who joined it there late); the
# ribbon never sold, its tile saying what it takes; the bonus told above the last level's own pay.
finish_story = ECONOMY[ECONOMY.find("function EconomyService.finishStory("):ECONOMY.find("function EconomyService.isWelcomed(")]
for needle, why in (
    ("local amount = ShopCatalog.storyReward(hardcore, double)", "the story's bonus is not the catalogue's"),
    ('if item.earn == "story" and not profile.Data.Owned[item.id] then\n\t\t\tprofile.Data.Owned[item.id] = true', "finishing the story does not give the green ribbon"),
    ("earnedRemote:FireClient(player, amount, { story = true,", "the story's bonus is paid without a word"),
):
    if needle not in finish_story:
        fail("EconomyService: " + why)
if ECONOMY.count("EconomyService.finishStory(") != 2 or BOOT.count("pcall(EconomyService.finishStory, player, hardcoreStory)") != 1:
    fail("the story's reward is given somewhere other than the end of a story (and the self-test)")
if "if walked and reached >= of and EconomyService and EconomyService.finishStory then" not in BOOT:
    fail("Bootstrap: the story's reward goes to a last level not walked, or to someone who joined the story at its end")
if "local reached = 0\n\t\t\tif EconomyService and EconomyService.storyAt then" not in BOOT:
    fail("Bootstrap: where a player's own walking had got to is not read before the story's place is put back")
if 'if action == "buy" and item.earn then\n\t\treturn answer(player, false, "earned")' not in ECONOMY:
    fail("EconomyService: the green ribbon can be bought")
if "REWARD.STORY" not in CATALOG or "STORY = 150," not in CATALOG:
    fail("ShopCatalog: the story pays no bonus")
for needle, why in (
    ('if item.earn and not owned(item.id) then\n\t\ttoast("Finish the story to get " .. item.name .. ".")', "pressing the ribbon tries to buy it"),
    ('fill, edge, ink, words = LOOK.soon, LOOK.soonEdge, LOOK.soonInk, "Finish the story"', "the ribbon's tile shows no way to get it"),
    ("{ Position = UDim2.new(0.5, 0, 1, if story then -92 else -28) }", "the story's bonus lands on top of the last level's pay"),
):
    if needle not in SHOP:
        fail("ShopService: " + why)
if 'check("finishing the story pays its bonus and gives the green ribbon",' not in selftest \
        or 'check("the green ribbon is never sold", result.ok == false and result.reason == "earned",' not in selftest:
    fail("EconomyService: the self-test does not check the story's reward")

# THE DAILY CHEST: once a UTC day; the next day its streak goes on, after a day missed it starts again; the
# catalogue's rewards by day (growing, day seven's after); the player's screen told when the next opens; the pill
# says the day; a test button; the self-test opens it.
claim = ECONOMY[ECONOMY.find("function EconomyService.claimDaily("):ECONOMY.find("function EconomyService.finishStory(")]
for needle, why in (
    ("if last == now then\n\t\treturn { opened = false,", "the daily chest opens more than once a day"),
    ("local streak = if last == now - 1 then (tonumber(data.DailyStreak) or 0) + 1 else 1", "the daily streak does not go on the next day, or does not start again after a day missed"),
    ("local amount = ShopCatalog.dailyReward(streak)", "the daily chest's tokens are not the catalogue's"),
    ("data.DailyDay = now\n", "the daily chest is not kept as opened today"),
    ("dailyAttributes(player)", "the player's screen is not told the chest was opened"),
    ("earnedRemote:FireClient(player, amount, { daily = true, streak = streak })", "the daily chest pays without a word"),
):
    if needle not in claim:
        fail("EconomyService: " + why)
if "return math.floor(os.time() / DAY)" not in ECONOMY or "local DAY = 86400" not in ECONOMY:
    fail("EconomyService: the daily chest's days are not whole UTC days")
if 'player:SetAttribute("DailyNext", if day == today() then (day + 1) * DAY else 0)' not in ECONOMY:
    fail("EconomyService: the player's screen is not told when the next chest opens")
if "\tprofiles[player] = ready\n\tdailyAttributes(player)\n" not in ECONOMY:
    fail("EconomyService: joining, the chest's prompt is not told whether it opens today")
daily_rewards = re.search(r"DAILY = \{ ([\d, ]+) \}", CATALOG)
values = [int(v) for v in daily_rewards.group(1).split(", ")] if daily_rewards else []
if len(values) != 7 or values != sorted(values) or values[0] <= 0:
    fail("ShopCatalog: the daily chest's rewards are not seven days, growing")
if 'elseif action == "dailyNext" then' not in ECONOMY or '{ action = "dailyNext", text = "Daily: next day" }' not in DEV_CLIENT:
    fail("the test panel cannot try the daily streak")
if 'check("the daily chest: once a day, its streak the next day, and again from day one after a day missed",' not in selftest:
    fail("EconomyService: the self-test does not open the daily chest")
if 'table.insert(reasons, ("Daily chest, day %d"):format(tonumber(info.streak) or 1))' not in SHOP:
    fail("ShopService: the daily chest's pill does not say which day")

# THE HIDDEN CACHES' TOKENS: once a save, the catalogue's amount, told with the usual pill; the self-test finds one.
found_cache = ECONOMY[ECONOMY.find("function EconomyService.foundCache("):ECONOMY.find("function EconomyService.claimDaily(")]
for needle, why in (
    ("if data.Caches[key] then\n\t\treturn false", "a hidden cache pays every time it is found"),
    ("data.Caches[key] = true", "a hidden cache found is not kept in the save"),
    ("local amount = ShopCatalog.REWARD.CACHE", "a hidden cache's tokens are not the catalogue's"),
    ("earnedRemote:FireClient(player, amount, { cache = true })", "a hidden cache pays without a word"),
):
    if needle not in found_cache:
        fail("EconomyService: " + why)
if "Caches = {} :: { [string]: boolean }," not in ECONOMY:
    fail("EconomyService: a new save has nowhere to keep the caches found")
if "CACHE = 25," not in CATALOG:
    fail("ShopCatalog: a hidden cache pays nothing")
if 'check("a hidden cache pays once a save", cacheFirst == true and cacheAgain == false' not in selftest:
    fail("EconomyService: the self-test does not find a hidden cache")
if 'table.insert(reasons, "Hidden cache")' not in SHOP:
    fail("ShopService: a hidden cache's pill does not say what it was")

# A FRIEND IN THE RUN: a fifth more (the catalogue's FRIEND, before the 2x pass doubles it), for a Roblox friend who has
# been in the run and is still in the server, never yourself, a failed ask counting as no; asked before paying with the
# save looked at again after; a new run's crew started again, a late joiner added to it, and a player who leaves taken
# out; told once on the card as the run starts, on the pill at its end, in the invite and the first visit's pages; the
# test panel's pretend friend only in Studio; the self-test puts the real run's crew back.
friend_rate = re.search(r"\n\tFRIEND = (\d+(?:\.\d+)?), ", CATALOG)
rate = float(friend_rate.group(1)) if friend_rate else 0.0
if not 1.0 < rate <= 1.5:
    fail("ShopCatalog: a friend in the run pays no more, or far too much (FRIEND %s)" % rate)
reward_fn = CATALOG[CATALOG.find("function ShopCatalog.reward("):CATALOG.find('ShopCatalog.STAMP = "')]
friend_step = reward_fn.find("if friend then\n\t\tamount = math.floor(amount * ShopCatalog.REWARD.FRIEND + 0.5)")
if friend_step < 0:
    fail("ShopCatalog: a friend in the run adds nothing to its tokens")
elif not friend_step < reward_fn.find("if double then"):
    fail("ShopCatalog: the 2x pass does not double a friend's share")
run_finished = ECONOMY[ECONOMY.find("function EconomyService.runFinished("):ECONOMY.find("function EconomyService.finishedLevels(")]
asked = run_finished.find("local friend = EconomyService.withFriend(player)")
looked_again = run_finished.find("if not profile:IsActive() then\n\t\treturn", max(asked, 0))
paid = run_finished.find("ShopCatalog.reward(run.length, hardcore, best, double, friend)")
if asked < 0 or paid < 0:
    fail("EconomyService: a run finished with a friend pays no more")
elif not asked < looked_again < paid:
    fail("EconomyService: a run's tokens go to a save that may have closed while Roblox was asked about friends")
for needle, why in (
    ("double = double, friend = friend,", "a friend's share is paid without a word"),
    ('LogCustomEvent(player, "RunWithFriend", levelId or 0)', "runs with a friend are not on the dashboard"),
):
    if needle not in run_finished:
        fail("EconomyService: " + why)
with_friend = ECONOMY[ECONOMY.find("function EconomyService.withFriend("):ECONOMY.find("function EconomyService.friendPercent(")]
for needle, why in (
    ("if devFriend[player] and RunService:IsStudio() then", "the test panel's pretend friend pays in the live game"),
    ("if other ~= player then", "a player counts as their own friend"),
    ("other.Parent == Players and player.Parent == Players and isFriend(player, other)",
     "a friend who has left the server still counts"),
):
    if needle not in with_friend:
        fail("EconomyService: " + why)
is_friend = ECONOMY[ECONOMY.find("local function isFriend("):ECONOMY.find("function EconomyService.withFriend(")]
asked_roblox = is_friend.find("pcall(player.IsFriendsWith, player, other.UserId)")
if asked_roblox < 0:
    fail("EconomyService: whether two players are friends is asked unguarded, or not at all")
elif not asked_roblox < is_friend.find("if not ok then\n\t\treturn false\n\tend") < is_friend.find("remember(player, other.UserId"):
    fail("EconomyService: a failed ask about friends is kept, or counts as friends")
run_started = ECONOMY[ECONOMY.find("function EconomyService.runStarted("):ECONOMY.find("function EconomyService.runFinished(")]
for needle, why in (
    ("if not joining then\n\t\ttable.clear(crew)", "the last run's players count as friends in this one"),
    ("crew[player] = true", "nobody is ever in a run's crew"),
):
    if needle not in run_started:
        fail("EconomyService: " + why)
unload = ECONOMY[ECONOMY.find("local function unload("):ECONOMY.find("local function answer(")]
for name in ("crew", "friendOf", "toldFriend", "devFriend"):
    if "\t%s[player] = nil\n" % name not in unload:
        fail("EconomyService: a player who leaves is kept in %s" % name)
if "if not toldFriend[player] and crew[player] and EconomyService.withFriend(player) then\n\t\t\ttoldFriend[player] = true" not in ECONOMY:
    fail("EconomyService: a friend in the run is told every time, or never")
for needle, why in (
    ("pcall(EconomyService.runStarted, players, HubService.getRequest().length)\n\t\ttellRunFriends()",
     "nobody is told a friend is in the run as it starts"),
    ("pcall(EconomyService.runStarted, { player }, runLength, true)\n\t\ttellRunFriends()",
     "a late joiner is not told about their friend, nor their friend about them"),
    ('HubVoteState:FireClient(player, "friend", { percent = EconomyService.friendPercent() })',
     "the card is never told about a friend in the run"),
    ("task.delay(FRIEND_TELL_AFTER, function()", "a friend in the run is told before the run has even arrived"),
):
    if needle not in BOOT:
        fail("Bootstrap: " + why)
if 'elseif kind == "friend" then\n\t\t\tHubVoteService.onFriend(payload)' not in VOTE_CLIENT:
    fail("HubVoteService: the card never says a friend is in the run")
on_friend = VOTE_CLIENT[VOTE_CLIENT.find("function HubVoteService.onFriend("):VOTE_CLIENT.find("function HubVoteService.onBusy(")]
if "more tokens" not in on_friend or "%d%%" not in on_friend:
    fail("HubVoteService: the card does not say what a friend in the run pays")
if 'if info.friend then\n\t\t\ttable.insert(reasons, "With a friend")' not in SHOP:
    fail("ShopService: a friend's share is not on the pill")
for needle, why in (
    ("local realCrew = table.clone(crew)", "the self-test loses the real run's crew"),
    ("for member, on in pairs(realCrew) do\n\t\tcrew[member] = on", "the self-test loses the real run's crew"),
    ('check("alone in a run, no friend\'s bonus", EconomyService.withFriend(player) == false)',
     "the self-test does not see a run alone pay no friend's share"),
    ('check("the test panel\'s friend counts as one", EconomyService.withFriend(player) == true)',
     "the self-test does not see the test panel's friend count"),
    ('check("a friend in the run pays a fifth more", together == math.floor(plain * ShopCatalog.REWARD.FRIEND + 0.5)',
     "the self-test does not check a friend's share"),
):
    if needle not in selftest:
        fail("EconomyService: " + why)
dev_friend = ECONOMY[ECONOMY.find('elseif action == "friend" then'):ECONOMY.find('elseif action == "favourite" then')]
if "devFriend[player] = if devFriend[player] then nil else true" not in dev_friend or "toldFriend[player] = nil" not in dev_friend:
    fail("EconomyService: the test panel's friend does nothing, or is never told on the card")
if '{ action = "friend", text = "Friend in runs on/off" }' not in DEV_CLIENT:
    fail("DevPanelClient: there is no way to try a friend's share in Studio")
invite_words = re.search(r'local INVITE_WORDS = "([^"]*)"', PAUSE)
said = re.search(r"(\d+)% more tokens", invite_words.group(1)) if invite_words else None
if "made.PromptMessage = INVITE_WORDS" not in PAUSE or not said:
    fail("PauseMenuService: an invite does not say why to come")
elif int(said.group(1)) != round((rate - 1) * 100):
    fail("PauseMenuService: the invite promises %s%% and a friend pays %d%%" % (said.group(1), round((rate - 1) * 100)))
for text in [invite_words.group(1) if invite_words else ""] + re.findall(r'"([^"]*)"', on_friend):
    if "--" in text or "\u2014" in text or "\u2013" in text:
        fail("a friend's words have a dash in them: %r" % text)
if "a friend running with you" not in ONBOARD:
    fail("OnboardingService: the first visit's pages never say a friend pays more")

# DAILY CHALLENGES: a list worth chasing (enough of them, every level's, their words without a dash, each kind one a
# run can do); three a day, shuffled by the day, a level's only once it is open in the player's own save; picked the
# first time a save sees the day; a run counted and each challenge paid once that day, with the run on its pill;
# their own screen told when the save loads, when one is done, and at midnight; the self-test sees them; the test
# panel gives a new three.
challenge_block = CATALOG[CATALOG.find("ShopCatalog.CHALLENGES = {"):CATALOG.find("} :: { Challenge }")]
entries = re.findall(r'\{ id = "(\w+)", text = "([^"]*)", reward = (\d+)(?:, level = (\d+))?(?:, kind = "(\w+)")?', challenge_block)
ids = [e[0] for e in entries]
if len(entries) < 6 or len(set(ids)) != len(ids):
    fail("ShopCatalog: too few daily challenges, or two with one id: %s" % ids)
if sorted(int(e[3]) for e in entries if e[3]) != [1, 2, 3, 4]:
    fail("ShopCatalog: not one daily challenge for each level")
met = CATALOG[CATALOG.find("function ShopCatalog.challengeMet("):CATALOG.find("-- Tokens for a run: `length`")]
for challenge_id, text, reward, level, kind in entries:
    if "--" in text or "\u2014" in text or "\u2013" in text:
        fail("ShopCatalog: a daily challenge's words have a dash in them: %r" % text)
    if not 10 <= int(reward) <= 100:
        fail("ShopCatalog: daily challenge %s pays %s, out of line with a run's" % (challenge_id, reward))
    if not level and 'challenge.kind == "%s" then' % kind not in met:
        fail("ShopCatalog: daily challenge %s can never be done (no run meets %r)" % (challenge_id, kind))
for needle in ("long", "three"):
    if needle not in ids:
        fail("ShopCatalog: the self-test's daily challenge %r is gone" % needle)
if "ShopCatalog.CHALLENGES_A_DAY = 3" not in CATALOG:
    fail("ShopCatalog: not three daily challenges a day")
pick = CATALOG[CATALOG.find("function ShopCatalog.pickChallenges("):CATALOG.find("function ShopCatalog.challengeMet(")]
for needle, why in (
    ("local random = Random.new(day)", "the daily challenges are not shuffled by the day"),
    ("if #picked < ShopCatalog.CHALLENGES_A_DAY and canDo(challenge) then", "the daily challenges are picked past three, or ones a player cannot do"),
):
    if needle not in pick:
        fail("ShopCatalog: " + why)
can = ECONOMY[ECONOMY.find("local function canChallenge("):ECONOMY.find("local function challengesToday(")]
for needle, why in (
    ("if at == 1 then\n\t\treturn true", "the first level's challenge is never given"),
    ("for index = at - 1, #LevelDefinitions.All do", "a level's challenge is given before the level is open"),
):
    if needle not in can:
        fail("EconomyService: " + why)
today_block = ECONOMY[ECONOMY.find("local function challengesToday("):ECONOMY.find("local function challengeAttributes(")]
for needle, why in (
    ("state.day ~= now", "yesterday's challenges are kept today"),
    ("return canChallenge(data, challenge)", "a player is given challenges they cannot do"),
):
    if needle not in today_block:
        fail("EconomyService: " + why)
attributes = ECONOMY[ECONOMY.find("local function challengeAttributes("):ECONOMY.find("-- THE VIP TAG, over a VIP player's head")]
for name in ("Challenges", "ChallengesDone", "ChallengeRuns", "ChallengeNext"):
    if 'player:SetAttribute("%s",' % name not in attributes:
        fail("EconomyService: the player's screen is never told %s" % name)
challenge_run = ECONOMY[ECONOMY.find("function EconomyService.challengeRun("):ECONOMY.find("-- THE DAILY CHEST OPENED")]
for needle, why in (
    ("state.runs = (tonumber(state.runs) or 0) + 1", "a run is not counted among today's"),
    ("if challenge and not state.done[id] and ShopCatalog.challengeMet(challenge, run, state.runs) then\n\t\t\tstate.done[id] = true",
     "a daily challenge pays every time it is done"),
    ("data.Tokens += prize", "a daily challenge pays nothing"),
    ('logEconomy(player, true, prize, Enum.AnalyticsEconomyTransactionType.Gameplay.Name, "Challenge")',
     "a daily challenge's tokens are not on the dashboard"),
    ('LogCustomEvent(player, "ChallengeDone", challenge.reward,', "daily challenges done are not on the dashboard"),
    ("challengeAttributes(player)\n\treturn prize, done", "a daily challenge done is not told to the player's screen"),
):
    if needle not in challenge_run:
        fail("EconomyService: " + why)
for needle, why in (
    ("local prize, done = EconomyService.challengeRun(player, { levelId = levelId, hardcore = hardcore, best = best,\n\t\tfriend = friend, length = run.length })",
     "a finished run never does a daily challenge"),
    ("earnedRemote:FireClient(player, amount + prize + foundTokens, {", "a daily challenge's tokens are not on the run's pill"),
    ("friend = friend, challenges = #done,", "the run's pill does not say a challenge was done"),
):
    if needle not in run_finished:
        fail("EconomyService: " + why)
for needle, why in (
    ("\tChallenges = {} :: { [string]: any },", "a new save has nowhere to keep today's challenges"),
    ("profiles[player] = ready\n\tdailyAttributes(player)\n\tchallengeAttributes(player)", "a save loading does not show its challenges"),
    ("if today() ~= shown then", "new challenges never come at midnight"),
    ("pcall(challengeAttributes, player)", "new challenges never come at midnight"),
):
    if needle not in ECONOMY:
        fail("EconomyService: " + why)
for needle, why in (
    ('check("three challenges a day, none on a level not yet open", #picked.ids == ShopCatalog.CHALLENGES_A_DAY'
     '\n\t\t\tand #locked == 0,', "the self-test does not look at today's challenges"),
    ('check("a challenge pays once a day, and the third run counts", paidLong == long.reward and paidAgain == 0'
     '\n\t\t\tand paidThird == three.reward and data.Tokens == beforeChallenge + long.reward + three.reward,',
     "the self-test does not do a challenge"),
    ("tellLevels()\n\tdailyAttributes(player)\n\tchallengeAttributes(player)", "the self-test leaves its challenges on the player's screen"),
):
    if needle not in ECONOMY[ECONOMY.find("local function selfTest("):ECONOMY.find("local function onDev(")]:
        fail("EconomyService: " + why)
dev_new = ECONOMY[ECONOMY.find('elseif action == "challengesNew" then'):ECONOMY.find('elseif action == "friend" then')]
if "ShopCatalog.pickChallenges(today() + math.random(1, 9999)" not in dev_new or "challengeAttributes(player)" not in dev_new:
    fail("EconomyService: the test panel's new three does nothing")
if '{ action = "challengesNew", text = "Challenges: new three" }' not in DEV_CLIENT:
    fail("DevPanelClient: there is no way to see a new three in Studio")
if 'if challenges == 1 then\n\t\t\ttable.insert(reasons, "Challenge done")' not in SHOP:
    fail("ShopService: a challenge done is not on the pill")

# THE STARTER PACK: a pass (so Roblox sells it only once) with its tokens and a trail sold nowhere else, given once a
# save the moment the pass is found (on joining, a late answer, or bought), and told with the pill; first in Featured,
# off it once yours, "Once only" until then; its trail's tile and press lead to it; a pass you own shows Owned; the
# test panel buys and undoes it; the self-test sees it given once and the trail never sold.
starter_item = re.search(r'\{ id = "StarterPack", tab = "Passes", kind = "pass",(.*?)\},\n', CATALOG, re.S)
starter_body = starter_item.group(1) if starter_item else ""
starter_tokens = re.search(r"\btokens = (\d+)", starter_body)
if not starter_item or not re.search(r"\bpassId = \d+", starter_body) or not re.search(r"\brobux = \d+", starter_body):
    fail("ShopCatalog: the starter pack is not a pass sold for Robux")
if not starter_tokens or int(starter_tokens.group(1)) <= 0:
    fail("ShopCatalog: the starter pack gives no tokens")
if 'gives = "SeaGlass"' not in starter_body or "once = true" not in starter_body:
    fail("ShopCatalog: the starter pack gives no trail, or is not marked once only")
for given in re.findall(r'\bgives = "(\w+)"', CATALOG):
    given_item = re.search(r'\{ id = "%s", tab = "\w+", kind = "\w+",(.*?)\},\n' % given, CATALOG, re.S)
    if not given_item or 'earn = "starter"' not in given_item.group(1):
        fail("ShopCatalog: %s comes with the starter pack and is also sold, or is not in the catalogue" % given)
featured_ids = re.findall(r'"(\w+)"', featured.group(1) if featured else "")
if not featured_ids or featured_ids[0] != "StarterPack":
    fail("ShopCatalog: the starter pack is not first in Featured")
grant = ECONOMY[ECONOMY.find("local function grantStarter("):ECONOMY.find("local function checkPasses(")]
for needle, why in (
    ("profile:IsActive() and owned and owned.StarterPack and starter", "the starter pack is given without the pass"),
    ("if data.StarterGranted then\n\t\treturn", "the starter pack is given every time the pass is found"),
    ("data.StarterGranted = true", "the starter pack is given every time the pass is found"),
    ("data.Tokens += starterTokens", "the starter pack gives no tokens"),
    ("data.Owned[gift.id] = true", "the starter pack gives no trail"),
    ("logEconomy(player, true, starterTokens, Enum.AnalyticsEconomyTransactionType.IAP.Name, starter.id)",
     "the starter pack's tokens are not on the dashboard"),
    ("earnedRemote:FireClient(player, starterTokens, { starter = true, gift =", "the starter pack is given without a word"),
):
    if needle not in grant:
        fail("EconomyService: " + why)
check_passes = ECONOMY[ECONOMY.find("local function checkPasses("):ECONOMY.find("local function load(")]
if check_passes.count("grantStarter(player)") != 2:
    fail("EconomyService: a starter pack found on joining, or on a late answer from Roblox, gives nothing")
if '\t\t\tgrantStarter(player)\n\t\t\tpush(player)\n\t\t\tdress(player)\n\t\tend\n\tend)' not in ECONOMY:
    fail("EconomyService: buying the starter pack gives nothing until the next visit")
owns_fn = ECONOMY[ECONOMY.find("local function owns("):ECONOMY.find("local function stateFor(")]
if "if passes[player] and passes[player][id] then\n\t\treturn true" not in owns_fn:
    fail("EconomyService: a pass you own is not shown Owned in the shop")
if "\tStarterGranted = false," not in ECONOMY:
    fail("EconomyService: a new save has nowhere to keep the starter pack given")
starter_test = ECONOMY[ECONOMY.find("local function selfTest("):ECONOMY.find("local function onDev(")]
for needle, why in (
    ("grantStarter(player)\n\t\tgrantStarter(player)", "the self-test does not give the starter pack twice"),
    ('check("the starter pack gives its tokens and its trail once", pack ~= nil\n\t\t\tand data.Tokens == beforeStarter + (pack.tokens or 0)',
     "the self-test does not check the starter pack is given once"),
    ('check("a pass you own shows as owned", owns(player, "StarterPack"))', "the self-test does not see a pass shown owned"),
    ('check("the sea glass trail is never sold", glass.ok == false and glass.reason == "earned"',
     "the self-test does not try to buy the sea glass trail"),
    ("starterPasses.StarterPack = realStarter", "the self-test leaves the starter pack on"),
):
    if needle not in starter_test:
        fail("EconomyService: " + why)
dev_starter = ECONOMY[ECONOMY.find('elseif action == "starter" then'):ECONOMY.find('elseif action == "challengesNew" then')]
if "owned.StarterPack = true\n\t\t\tgrantStarter(player)" not in dev_starter or "data.StarterGranted = false" not in dev_starter:
    fail("EconomyService: the test panel's starter pack does nothing, or cannot be undone")
if '{ action = "starter", text = "Starter pack on/off" }' not in DEV_CLIENT:
    fail("DevPanelClient: there is no way to try the starter pack in Studio")
for needle, why in (
    ('if not (shop.tab == "Featured" and item.once and owned(item.id)) then', "the starter pack stays in Featured once yours"),
    ('elseif item.once then "Once only"', "the starter pack's tile does not say it is once only"),
    ('if info.starter then\n\t\t\ttable.insert(reasons, "Starter pack")', "the starter pack's pill does not say what it was"),
    ('ribbon = ("  and the %s trail"):format(string.lower(info.gift))', "the starter pack's pill does not name its trail"),
):
    if needle not in SHOP:
        fail("ShopService: " + why)
press = SHOP[SHOP.find("local function pressPrice("):SHOP.find("-- ===== ONE TILE =====")]
lead = press.find('if item.earn == "starter" and not owned(item.id) then\n\t\tlocal pack = ShopCatalog.get("StarterPack")')
if lead < 0 or 'ShopService.showTab("Passes")' not in press:
    fail("ShopService: the sea glass trail's price does not lead to the starter pack")
elif not lead < press.find('if item.earn and not owned(item.id) then\n\t\ttoast("Finish the story'):
    fail("ShopService: the sea glass trail says to finish the story")
tile_lead = SHOP.find('fill, edge, ink, words = LOOK.robux, LOOK.robuxEdge, LOOK.robuxInk, "Starter pack"')
if tile_lead < 0 or not tile_lead < SHOP.find('fill, edge, ink, words = LOOK.soon, LOOK.soonEdge, LOOK.soonInk, "Finish the story"'):
    fail("ShopService: the sea glass trail's tile does not say it is in the starter pack")

# THE MATERIALS, AS A COLLECTION: every material in MaterialConfig in the catalogue once, named without a dash; found
# only by the server seeing a runner stand on one on a level (never the squish room, never a client's word), each paid
# once a save, the last of them with the bonus, the swatch trail and the badge; told on the run's pill, by a chime,
# on the journal's own tab (a page each: what it does, what it was) and the lobby's board; kept in the save, put back
# by the self-test, and tried from the test panel.
real_materials = set(re.findall(r"^\t(\w+) = \{", MATERIALS, re.M))
catalog_materials = re.findall(r'\{ key = "(\w+)", name = "([^"]+)", colour = rgb\(', CATALOG)
keys = [key for key, _ in catalog_materials]
if set(keys) != real_materials or len(keys) != len(set(keys)):
    fail("ShopCatalog: the materials collection is not every material once: missing %s, extra %s"
         % (sorted(real_materials - set(keys)), sorted(set(keys) - real_materials)))
for key, name in catalog_materials:
    if "--" in name or "\u2014" in name or "\u2013" in name:
        fail("ShopCatalog: a material's name has a dash in it: %r" % name)
if not re.search(r"\n\tMATERIAL = [1-9]\d*,", CATALOG) or not re.search(r"\n\tMATERIALS_ALL = [1-9]\d*,", CATALOG):
    fail("ShopCatalog: finding a material, or all of them, pays nothing")
if not re.search(r"\n\tmaterials = \d+,", CATALOG):
    fail("ShopCatalog: there is no badge for finding every material")
found_fn = ECONOMY[ECONOMY.find("function EconomyService.foundMaterial("):ECONOMY.find("local function lookUnder(")]
for needle, why in (
    ("if not (profile and profile:IsActive()) or ShopCatalog.material(name) == nil then", "a material that does not exist is counted"),
    ("if data.Materials[name] then\n\t\treturn false", "a material found pays every time"),
    ("data.Materials[name] = true", "a material found is not kept"),
    ("if count == #ShopCatalog.MATERIALS then\n\t\tamount += ShopCatalog.REWARD.MATERIALS_ALL", "finding every material gives no bonus"),
    ('if item.earn == "materials" and not data.Owned[item.id] then', "finding every material gives no swatch trail"),
    ("task.spawn(EconomyService.awardBadge, player, ShopCatalog.BADGES.materials)", "finding every material gives no badge"),
    ("data.Tokens += amount", "a material found pays nothing"),
    ('logEconomy(player, true, amount, Enum.AnalyticsEconomyTransactionType.Gameplay.Name, "Material")',
     "a material's tokens are not on the dashboard"),
    ('LogCustomEvent(player, "MaterialFound", count)', "materials found are not on the dashboard"),
    ("run.tokens += amount", "a material found is not told on the run's pill"),
    ("materialsAttribute(player)\n\tpush(player)\n\treturn true", "a material found is not told to the player's screen"),
):
    if needle not in found_fn:
        fail("EconomyService: " + why)
look_fn = ECONOMY[ECONOMY.find("local function lookUnder("):ECONOMY.find("-- A FINISHED RUN AGAINST TODAY'S CHALLENGES")]
for needle, why in (
    ('if typeof(level) ~= "string" or level == "backRooms" or player:GetAttribute("InSquishRoom") then\n\t\treturn',
     "materials are found off the levels (the squish room has them all side by side)"),
    ("underParams.FilterDescendantsInstances = { character }", "the server's look under a runner hits the runner"),
    ("workspace:Raycast(root.Position, Vector3.new(0, -8, 0), underParams)", "the server does not look under a runner's feet"),
    ("EconomyService.foundMaterial(player, name)", "a material under a runner's feet is never found"),
):
    if needle not in look_fn:
        fail("EconomyService: " + why)
if "pcall(lookUnder, player)" not in ECONOMY:
    fail("EconomyService: nobody's feet are ever looked under")
if "foundMaterial" in note_block or "found = true" in note_block:
    fail("EconomyService: a client's word finds a material")
material_attributes = ECONOMY[ECONOMY.find("local function materialsAttribute("):ECONOMY.find("-- THE VIP TAG, over a VIP player's head")]
for name in ("Materials", "MaterialsFound"):
    if 'player:SetAttribute("%s",' % name not in material_attributes:
        fail("EconomyService: the player's screen is never told %s" % name)
if ECONOMY.count("challengeAttributes(player)\n\tmaterialsAttribute(player)") != 2:
    fail("EconomyService: a save loading (or the self-test putting it back) does not show its materials")
for needle, why in (
    ("local found = foundRun[player]\n\tfoundRun[player] = nil", "a run's materials are told again on the next run"),
    ("earnedRemote:FireClient(player, amount + prize + foundTokens, {", "a run's materials' tokens are not on its pill"),
    ("materials = foundCount, gift = foundGift })", "a run's pill does not say what materials it found"),
):
    if needle not in run_finished:
        fail("EconomyService: " + why)
if "\t\tfoundRun[player] = nil\n" not in run_started:
    fail("EconomyService: materials found before a run are told on its pill")
if "\tfoundRun[player] = nil\n" not in unload:
    fail("EconomyService: a player who leaves is kept in foundRun")
if "\tMaterials = {} :: { [string]: boolean }," not in ECONOMY:
    fail("EconomyService: a new save has nowhere to keep the materials found")
material_test = ECONOMY[ECONOMY.find("local function selfTest("):ECONOMY.find("local function onDev(")]
for needle, why in (
    ('check("a material found pays once, and only a real one", firstFind == true and againFind == false\n\t\t\tand madeUp == false',
     "the self-test does not find a material"),
    ('check("the last material gives the swatch trail and the bonus", data.Owned.Swatch == true',
     "the self-test does not find the last material"),
    ("foundRun[player] = realFound", "the self-test loses the real run's materials"),
):
    if needle not in material_test:
        fail("EconomyService: " + why)
dev_materials = ECONOMY[ECONOMY.find('elseif action == "materials" then'):ECONOMY.find('elseif action == "starter" then')]
if 'if material.key ~= "Soap" then' not in dev_materials or "materialsAttribute(player)" not in dev_materials:
    fail("EconomyService: the test panel's materials do nothing")
if '{ action = "materials", text = "Materials: 26 / none" }' not in DEV_CLIENT:
    fail("DevPanelClient: there is no way to try the materials in Studio")
for needle, why in (
    ('table.insert(reasons, "New material")', "a run's pill does not say it found a material"),
    ('words = LOOK.soon, LOOK.soonEdge, LOOK.soonInk, ("Find all %d"):format(#ShopCatalog.MATERIALS)',
     "the swatch trail's tile does not say what it takes"),
):
    if needle not in SHOP:
        fail("ShopService: " + why)
swatch = press.find('if item.earn == "materials" and not owned(item.id) then\n\t\ttoast(("Stand on every material')
if swatch < 0 or not swatch < press.find('if item.earn and not owned(item.id) then\n\t\ttoast("Finish the story'):
    fail("ShopService: the swatch trail says to finish the story")
JOURNAL = read("Client", "Services", "JournalService.lua")
for needle, why in (
    ('{ key = "material", name = "Materials", empty = ', "the journal has no page for the materials"),
    ("button.Size = UDim2.new(1 / #KINDS, -5, 1, 0)", "the journal's tabs do not fit four to a row"),
    ("button.TextScaled = true", "a journal tab's name is cut off on a phone"),
    ('eyebrow = ("Material %d of %d"):format(counts[kind], keepsakeTotal)', "a material's page does not say which of them it is"),
    ("table.insert(lines, hints[key])", "a material's page does not say what it does"),
    ('("Kept by the Hold: %s, from %s."):format(kept.thing, kept.from)', "a material's page does not say what it was"),
    ("quiet = true, restored = first })", "a material in the journal says a word in the corner, or lights the book on joining"),
    ('me:GetAttributeChangedSignal("Materials"):Connect(look)', "a material found never reaches the journal"),
    ("task.spawn(watchMaterials)", "the journal never looks at the materials found"),
):
    if needle not in JOURNAL:
        fail("JournalService: " + why)
for needle, why in (
    ("OnboardingService.HINTS = HINTS", "the journal cannot say what a material does"),
    ("if shownFound ~= nil and now > shownFound and kit then\n\t\t\tkit.sound(", "a material found makes no sound"),
):
    if needle not in ONBOARD:
        fail("OnboardingService: " + why)
for text in re.findall(r'"([^"]*)"', JOURNAL[JOURNAL.find("local function materialPage("):JOURNAL.find("local function watchMaterials(")]):
    if "--" in text or "\u2014" in text or "\u2013" in text:
        fail("JournalService: a material's page has a dash in it: %r" % text)

# THE JOURNAL'S MATERIALS ARE THE SAVE'S: a page for one no longer in it is taken out, and the book and its list
# told.
materials_watch = JOURNAL[JOURNAL.find("local function watchMaterials("):JOURNAL.find("function JournalService.entries(")]
for needle, why in (
    ('if entry.kind == "material" and not keep[entry.id] then\n\t\t\t\ttable.remove(entries, index)\n\t\t\t\tbyId[entry.id] = nil',
     "a material no longer in the save keeps its page in the journal"),
    ("counts.material = math.max(0, (counts.material or 0) - 1)", "a material taken out of the journal still counts"),
    ("if gone then\n\t\t\trefreshBadge()", "a material taken out of the journal still lights its badge"),
):
    if needle not in materials_watch:
        fail("JournalService: " + why)

# CODES: the list well formed (capitals and digits, each once, tokens in line with the rest, a real last day); typed
# in any case and with spaces; the server's own list, while it lasts, once a save, kept in the save; on the dashboard,
# told with the pill; tried by the self-test (its own codes taken out again) and the test panel; the post box's card
# opens with the box selected for a controller, closes on B, lets go, frees the cursor and keeps to the safe area.
import datetime
code_block = CATALOG[CATALOG.find("ShopCatalog.CODES = {"):CATALOG.find("} :: { Code }")]
code_entries = re.findall(r'\{ code = "([^"]*)", tokens = (\d+), ends = "([^"]*)" \}', code_block)
if not code_entries:
    fail("ShopCatalog: the codes list is missing, or not in its form")
seen_codes = set()
for code, tokens, ends in code_entries:
    if not re.fullmatch(r"[A-Z0-9]{3,20}", code):
        fail("ShopCatalog: the code %r is not 3 to 20 capitals and digits, so nobody can post it" % code)
    if code in seen_codes:
        fail("ShopCatalog: the code %s is listed twice" % code)
    seen_codes.add(code)
    if not 1 <= int(tokens) <= 1000:
        fail("ShopCatalog: the code %s pays %s, out of line with everything else" % (code, tokens))
    try:
        datetime.date.fromisoformat(ends)
    except ValueError:
        fail("ShopCatalog: the code %s ends on %r, which is not a day (YYYY-MM-DD)" % (code, ends))
for needle, why in (
    ('local key = string.upper((string.gsub(typed, "%s", "")))', "a code typed in small letters or with spaces is refused"),
    ('if #key < 3 or #key > 20 or not string.match(key, "^%w+$") then', "anything at all is looked for as a code"),
    ("DateTime.fromUniversalTime(tonumber(y) :: number, tonumber(m) :: number, tonumber(d) :: number).UnixTimestamp",
     "a code's last day is not read as a day"),
    ("return if ok then at + 86400 else nil", "a code ends at the start of its last day, not the end"),
):
    if needle not in CATALOG:
        fail("ShopCatalog: " + why)
for needle, why in (
    ("local ACTIONS = { buy = true, equip = true, unequip = true, code = true, crate = true }",
     "a code cannot be posted, or a crate opened"),
    ("\tCodes = {} :: { [string]: boolean },", "a new save has nowhere to keep the codes posted"),
):
    if needle not in ECONOMY:
        fail("EconomyService: " + why)
for needle, why in (
    ('logEconomy(player, true, codeTokens, Enum.AnalyticsEconomyTransactionType.Gameplay.Name, "Code")',
     "a code's tokens are not on the dashboard"),
    ('LogCustomEvent(player, "CodeRedeemed", codeTokens,', "which code was posted is not on the dashboard"),
    ("earnedRemote:FireClient(player, codeTokens, { code = key })", "a code pays without a word"),
):
    if needle not in code_branch:
        fail("EconomyService: " + why)
code_test = ECONOMY[ECONOMY.find("local function selfTest("):ECONOMY.find("local function onDev(")]
for needle, why in (
    ('check("a code pays once, and an unknown or ended one says so", codeFirst.ok == true and codeAgain.reason == "used"',
     "the self-test does not post a code"),
    ('if string.sub(ShopCatalog.CODES[index].code, 1, 8) == "SELFTEST" then\n\t\t\t\ttable.remove(ShopCatalog.CODES, index)',
     "the self-test leaves its own codes in the list"),
):
    if needle not in code_test:
        fail("EconomyService: " + why)
if 'elseif action == "codesForget" then\n\t\t-- Every code as if never posted, to post them again.\n\t\tdata.Codes = {}' not in ECONOMY:
    fail("EconomyService: the test panel cannot post a code again")
if '{ action = "codesForget", text = "Codes: post again" }' not in DEV_CLIENT:
    fail("DevPanelClient: there is no way to post a code again in Studio")
code_box = SHOP[SHOP.find("local CODE_CLOSE_ACTION"):SHOP.find("-- ===== TOKENS EARNED, said at the end of a run =====")]
for needle, why in (
    ('local result = ask("code", box.Text)', "the post box's card never asks the server"),
    ("said.Text = CODE_WORDS[tostring(result.reason)]", "the post box's card does not say why a code did not pay"),
    ("GuiService.SelectedObject = codes.box", "the post box's card opens with nothing selected for a controller"),
    ("Enum.KeyCode.ButtonB, Enum.KeyCode.Escape)", "B does not close the post box's card"),
    ("GuiService.SelectedObject = nil", "the post box's card keeps a controller's selection after it closes"),
    ("codeScreen.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets", "the post box's card is not kept inside the safe area"),
    ("codeMost.MaxSize = Vector2.new(400, 236)", "the post box's card is not capped to a phone"),
    ("hold(false)", "closing the post box's card leaves you unable to move"),
):
    if needle not in code_box:
        fail("ShopService: " + why)
for reason in ("unknown", "used", "ended"):
    if not re.search(r"\n\t%s = \"[^\"]+\"," % reason, code_box):
        fail("ShopService: the post box's card has nothing to say for a code %s" % reason)
for text in re.findall(r'"([^"]*)"', code_box):
    if "--" in text or "\u2014" in text or "\u2013" in text:
        fail("ShopService: the post box's card has a dash in its words: %r" % text)
if 'if typeof(info.code) == "string" then\n\t\t\ttable.insert(reasons, "Code " .. info.code)' not in SHOP:
    fail("ShopService: a code's pill does not say which code")
if 'or (codeBox ~= nil and codeBox:IsA("ScreenGui") and codeBox.Enabled)' not in VIEW:
    fail("ViewModeService: the post box's card does not free the cursor")

# THE SIX CHUNK SOUNDS REMADE (2026-10-16): written by audio/gen_chunk_sfx.py, four takes each, and no longer by the
# old generator (a re-run of it would put the old ones back); each take shaped noise and grains, never a plain tone.
AUDIO = ROOT / "audio"
CHUNK_GEN = (AUDIO / "gen_chunk_sfx.py").read_text(encoding="utf-8") if (AUDIO / "gen_chunk_sfx.py").exists() else ""
OLD_GEN = (AUDIO / "gen_material_sfx.py").read_text(encoding="utf-8")
REMADE = ("saltCrunch", "claySquish", "cloudHush", "leafBrush", "snowPack", "charcoalSnap")
old_events = OLD_GEN[OLD_GEN.find("MATERIAL_EVENTS = ["):OLD_GEN.find("]", OLD_GEN.find("MATERIAL_EVENTS = ["))]
chunk_families = CHUNK_GEN[CHUNK_GEN.find("FAMILIES = ["):CHUNK_GEN.find("]", CHUNK_GEN.find("FAMILIES = ["))]
for family in REMADE:
    if '("%s",' % family in old_events:
        fail("audio/gen_material_sfx.py still writes %s, so a re-run puts the old one back over the remade one" % family)
    if '("%s",' % family not in chunk_families:
        fail("audio/gen_chunk_sfx.py does not write %s" % family)
    for take in range(1, 5):
        if not (AUDIO / "materials" / ("%s_%d.wav" % (family, take))).exists():
            fail("audio/materials/%s_%d.wav is missing" % (family, take))
for maker in ("def salt_crunch(", "def clay_squish(", "def cloud_hush(", "def leaf_brush(", "def snow_pack(", "def charcoal_snap("):
    body = CHUNK_GEN[CHUNK_GEN.find(maker):]
    body = body[:body.find("\n\n\n")]
    if not body:
        fail("audio/gen_chunk_sfx.py has no %s" % maker)
    elif "np.sin(phase(" in body or "punch(" in body or "chirp(" in body:
        fail("audio/gen_chunk_sfx.py: %s has a plain tone in it (a buzz or a beep, not the stuff itself)" % maker.strip("def ("))
    elif not any(form in body for form in ("take ==", "take %", "take >=", "[take - 1]", "take in (")):
        fail("audio/gen_chunk_sfx.py: %s's four takes differ only in their seed" % maker.strip("def ("))

# THE SHOP'S WORDS (2026-10-16): the description under the name, in the shop's own rounded letters, shrinking to
# fit rather than cut off; an "i" on every tile (a thumb's press) with the whole description and what a thing of
# its kind does, for every kind and every way of earning one; put away when the grid changes or the shop closes.
tile_fn = SHOP[SHOP.find("local function makeTile("):SHOP.find("-- ===== THE GRID AND THE TABS =====")]
for needle, why in (
    ('local blurb = label(card, "Blurb", item.blurb, CHUNKY,', "a tile's description is not in the shop's own letters"),
    ("blurb.TextScaled = true", "a tile's description is cut off rather than fitted"),
    ("fit.MinTextSize = 10", "a tile's description can shrink past reading"),
    ("more.Size = UDim2.fromOffset(MIN_TOUCH, MIN_TOUCH)", "a tile's \"i\" is smaller than a thumb"),
    ("showInfo(item, more, true)", "hovering a tile's \"i\" says nothing"),
    ("showInfo(item, more, false)", "pressing a tile's \"i\" says nothing"),
    ("local nameY = top + iconD + math.floor(8 * t)", "a tile's name is not under its icon (a gap opens on a tall tile)"),
):
    if needle not in tile_fn:
        fail("ShopService: " + why)
kind_block = SHOP[SHOP.find("local KIND_WORDS"):SHOP.find("local EARN_WORDS")]
earn_block = SHOP[SHOP.find("local EARN_WORDS"):SHOP.find("local function hideInfo(")]
for _, _, kind, rest in items:
    if not re.search(r"\n\t%s = \"[^\"]+\"," % kind, kind_block):
        fail("ShopService: the \"i\" has nothing to say about a %s" % kind)
for earn in set(re.findall(r'\bearn = "(\w+)"', CATALOG)):
    if not re.search(r"\n\t%s = \"[^\"]+\"," % earn, earn_block):
        fail("ShopService: the \"i\" has nothing to say about a thing earned by %s" % earn)
for text in re.findall(r'"([^"]*)"', kind_block + earn_block):
    if "--" in text or "\u2014" in text or "\u2013" in text:
        fail("ShopService: the \"i\" has a dash in its words: %r" % text)
if "\t\treturn\n\tend\n\thideInfo()\n\tfor _, old in ipairs(grid:GetChildren()) do" not in SHOP:
    fail("ShopService: the \"i\" card stays up over a new tab")
if "\tshop.open = false\n\tcloseConfirm()\n\thideInfo()\n" not in SHOP:
    fail("ShopService: the \"i\" card stays up when the shop closes")

# THE TRAILS AND AURAS (2026-10-16): every one its own look, made of layers (a ribbon and what it leaves, or motes
# around you); the embers the fanciest of the old ones, with a real, soft light; no Neon anywhere.
looks_block = CATALOG[CATALOG.find("local LOOKS: { [string]: Look } = {"):CATALOG.find("local function sequence(")]
look_ids = set(re.findall(r"^\t(\w+) = \{$", looks_block, re.M))
for item_id, tab, kind, rest in items:
    if kind in ("trail", "aura") and item_id not in look_ids:
        fail("ShopCatalog: the %s %s has no look of its own" % (kind, item_id))
embers = looks_block[looks_block.find("\tEmbers = {"):looks_block.find("\tSparkle = {")]
if embers.count("texture = TEX.") < 3 or "glow = {" not in embers:
    fail("ShopCatalog: the embers are a single plain stream again")
for brightness in re.findall(r"brightness = ([\d.]+)", looks_block):
    if float(brightness) > 1.5:
        fail("ShopCatalog: a cosmetic's light is brighter than a soft glow (%s)" % brightness)
if "Neon" in CATALOG:
    fail("ShopCatalog: Neon in a cosmetic (lights are real lights)")
for needle, why in (
    ("light.Shadows = false", "a cosmetic's light casts shadows (every player's would)"),
    ("m.LockedToPart = not spec.trailing", "a trail's drops follow you instead of falling where they were let go"),
):
    if needle not in CATALOG:
        fail("ShopCatalog: " + why)
for new_id in ("LavaRibbon", "JellyRibbon", "Sprinkles", "Snowfall", "Fireflies", "Starlight", "SlimeStep", "EmberStep", "Velvet"):
    if new_id not in seen:
        fail("ShopCatalog: %s is gone from the shop" % new_id)

# ===== THE CHUNK SOUNDS, SECOND ROUND (2026-10-16): eleven events, each ONE UPLOAD of four takes =====
#
# From the second test: solid chocolate (and the chocolate bar) rang like glass tapped with a fingernail; slime and
# soap wanted variety; memory foam, the switches, sand, the jellyfish, ice and jelly soda wanted improving; bubble wrap's
# pops ran on behind the feet; oobleck, lego and the keyboards were liked but wanted louder and creamier.
SHEET_GEN = AUDIO / "gen_sheet_sfx.py"
AUDIO_LUA = read("Client", "Services", "AudioService.lua")
SHEET_EVENTS = ("chocolateSnap", "chocolateChunk", "slimeBoing", "jellyBounce", "soapCrumble", "foamCompress",
                "switchClack", "kineticSandImprint", "iceCrack", "jelloWobble", "bubblePop")
# THE NINETY-SIXTH PASS'S: the keypad's four short sounds (gen_keypad_sfx.py), as sheets too, with three takes or four.
# (Not the lava crust and the Needoh: liked as they are, and kept as four files each.)
SHEETS_96 = {"button_clicky": 4, "button_linear": 3, "button_tactile": 3, "button_release": 3}
if not SHEET_GEN.exists():
    fail("audio/gen_sheet_sfx.py is missing")
else:
    sheet_src = SHEET_GEN.read_text(encoding="utf-8")
    for event in SHEET_EVENTS:
        if '("%s", ' % event not in sheet_src:
            fail("gen_sheet_sfx.py does not make %s" % event)
    if "np.sin(phase(" in sheet_src.split("def chocolate_snap")[1].split("def slime_boing")[0]:
        fail("gen_sheet_sfx.py: the chocolate is a tone again (it rang like glass)")
    for event in ("lavaCrust", "needohSquish"):
        if '("%s", ' % event in sheet_src:
            fail("gen_sheet_sfx.py remakes %s, which you liked as it was" % event)
    if "[(stem, make) for stem, make, _ in KEYPAD]" not in sheet_src:
        fail("gen_sheet_sfx.py does not make the keypad's sheets")
    keypad_src = (AUDIO / "gen_keypad_sfx.py").read_text(encoding="utf-8") if (AUDIO / "gen_keypad_sfx.py").exists() else ""
    for stem in ("button_clicky", "button_linear", "button_tactile", "button_release"):
        if '("%s", ' % stem not in keypad_src[keypad_src.find("SHEETS = ["):keypad_src.find("EVENTS = [")]:
            fail("gen_keypad_sfx.py does not hand %s to the sheets" % stem)
try:
    import numpy as np
    from scipy.io import wavfile
except ImportError:
    np = None
if np is not None:
    for event, count in [(e, 4) for e in SHEET_EVENTS] + list(SHEETS_96.items()):
        path = AUDIO / "sheets" / ("%s_x%d.wav" % (event, count))
        if not path.exists():
            fail("audio/sheets/%s_x%d.wav is missing" % (event, count))
            continue
        sr, x = wavfile.read(path)
        x = x.astype(float) / 32767
        if abs(len(x) / sr - count) > 0.01:
            fail("%s_x%d.wav is %.2f s long, not %d one-second slots" % (event, count, len(x) / sr, count))
            continue
        for k in range(count):
            slot = x[int(sr * k):int(sr * (k + 1))]
            tail = slot[int(sr * 0.95):]
            take = slot[:int(sr * 0.95)]
            if np.max(np.abs(take)) < 0.05:
                fail("%s sheet: take %d is silent" % (event, k + 1))
                continue
            if np.max(np.abs(tail)) > 0.002:
                fail("%s sheet: take %d runs into the next one's slot" % (event, k + 1))
            take = take / np.max(np.abs(take))
            spectrum = np.abs(np.fft.rfft(take)) ** 2
            freqs = np.fft.rfftfreq(len(take), 1 / sr)
            centroid = (freqs * spectrum).sum() / spectrum.sum()
            if centroid < 140:
                fail("%s sheet: take %d sits at %.0f Hz, under what a phone or a laptop plays" % (event, k + 1, centroid))
            if spectrum[freqs > 6000].sum() / spectrum.sum() > 0.05:
                fail("%s sheet: take %d is harsh (too much above 6 kHz)" % (event, k + 1))
            if event in ("chocolateSnap", "chocolateChunk"):
                after = int(sr * 0.08)
                ring = np.sqrt(np.mean(take[after:after + int(sr * 0.1)] ** 2)) / (np.sqrt(np.mean(take[:after] ** 2)) + 1e-9)
                if ring > 0.2:
                    fail("%s_x4.wav: take %d rings on (%.2f after 80 ms): glass, not chocolate" % (event, k + 1, ring))
            if event == "bubblePop":
                onset = np.argmax(np.abs(take) > 10 ** (-30 / 20)) / sr
                if onset > 0.001:
                    fail("bubblePop_x4.wav: take %d starts %.1f ms late (heard behind the foot)" % (k + 1, onset * 1000))
for needle, why in (
    ('local stem, count = string.match(item.Name, "^(.-)_x(%d+)$")', "a sheet of takes is not read as its takes"),
    ('table.insert(fromFolder[event], ("%s@%g"):format(item.SoundId, k * SHEET_SLOT))', "a sheet's takes are not given their slots"),
    ("if not sheeted[event] then", "old single takes are picked from alongside a sheet of new ones"),
    ("local FOLDER_REPLACES: { [string]: boolean } = { kineticSandImprint = true, bubblePop = true }",
     "the sand's and the bubble wrap's old uploads are still picked from"),
    ("(sound :: any).PlaybackRegion = NumberRange.new(from, from + SHEET_SLOT - 0.05)", "a sheet's take plays on into the next"),
    ('local asset = string.match(id, "^(.-)@") or id', "a sheet is preloaded as nothing (its takes are not asset ids)"),
    ("	AudioService.applyTake(sound, soundId)\n", "a chunk's take is played without its slot"),
    ("	AudioService.dress(sound, event)\n", "the oobleck, the lego and the keyboards are not given their tone"),
    ("	ooblSquelch = { gain = 1.5, low = 4, mid = 1, high = -6 },", "the oobleck is not louder and creamier"),
    ("	legoClick = { gain = 1.45, low = 3, mid = 1, high = -5 },", "the lego is not louder and creamier"),
    ("	keyThock = { gain = 1.4, low = 4, mid = 0, high = -5 },", "the keyboards are not louder and creamier"),
    ("	chocolateChunk = {},", "the solid chocolate has no event of its own"),
    ("	jellyBounce = {},", "the jellyfish has no event of its own"),
):
    if needle not in AUDIO_LUA:
        fail("AudioService: " + why)
for material, event, fallback in (("ChocolateSolid", "chocolateChunk", "chocolateSnap"), ("Jellyfish", "jellyBounce", "slimeBoing")):
    body = MATERIALS[MATERIALS.find("\t%s = {" % material):]
    body = body[:body.find("\n\t},")]
    if 'sfxEvent = "%s"' % event not in body or 'sfxFallback = "%s"' % fallback not in body:
        fail("MaterialConfig: %s does not play %s (with %s until it is imported)" % (material, event, fallback))
wrap = MATERIALS[MATERIALS.find("\tBubbleWrap = {"):]
wrap = wrap[:wrap.find("\n\t},")]
gap = re.search(r"sfxMinGap = ([\d.]+)", wrap)
if not gap or float(gap.group(1)) < 0.2:
    fail("MaterialConfig: bubble wrap pops faster than a footfall again (its pops ran on behind the feet)")
if "audio.applyTake(s, library[math.random(1, #library)])" not in STEPS:
    fail("StepService: a step sound from a sheet is played from the start of the sheet")

# ===== THE LOBBY, POLISHED (2026-10-16): the embers, the VIP badge, the countdown, the keepsakes' count =====
if embers.count("texture = TEX.") < 5 or "streak = true" not in embers:
    fail("ShopCatalog: the embers are back to a few plain streams (no sparks spitting up, no heat)")
if "m.Orientation = Enum.ParticleOrientation.VelocityParallel" not in CATALOG:
    fail("ShopCatalog: a streak is drawn as a dot")
vip_fn = ECONOMY[ECONOMY.find("local function vipTag("):ECONOMY.find('local KEY_TAG = "KeyTag"')]
for needle, why in (
    ("local fill = Instance.new(\"UIGradient\")", "the VIP badge is one flat colour again"),
    ('crown.Name = "Crown"', "the VIP badge has no crown"),
    ('shine.Name = "Shine"', "the VIP badge has no shine to sweep"),
    ("word.TextStrokeTransparency = 0", "the VIP badge's letters have no outline"),
):
    if needle not in vip_fn:
        fail("EconomyService: " + why)
if vip_fn.count('point.Name = "Point"') != 1 or "for k = 0, 2 do" not in vip_fn:
    fail("EconomyService: the VIP badge's crown is not three points")
if "\tshineVipBadges()\n" not in SHOP or 'TweenService:Create(sweep, TweenInfo.new(0.75, Enum.EasingStyle.Sine), { Offset = Vector2.new(1, 0) })' not in SHOP:
    fail("ShopService: the VIP badges' shine never sweeps")
# The shine is the plaque's own rounded shape with a band of gradient slid across it: a bar inside the plaque would be
# clipped square and show past its round ends.
if 'sweep.Name = "Sweep"' not in vip_fn or "shineCorner.CornerRadius = UDim.new(0.5, 0)" not in vip_fn:
    fail("EconomyService: the VIP badge's shine is a bar again (it shows past the plaque's round ends)")
VOTE = read("Client", "Services", "HubVoteService.lua")
if "electronicpingshort" in VOTE:
    fail("HubVoteService: the countdown is the electronic ping again")
for needle, why in (
    ('local sheet = folder and folder:FindFirstChild("CountdownTock_x3")', "the countdown's own sounds are never found"),
    ("tock(if left <= 3 then 1 else 0)", "the last three seconds sound like the rest"),
    ("\t\ttock(2)\n", "nothing sounds as the countdown runs out"),
):
    if needle not in VOTE:
        fail("HubVoteService: " + why)
if not re.search(r'"CountdownTock_x3"[^}]*\}', BOOT) or not re.search(r"CountdownTock_x3 = true[^}]*\}", BOOT):
    fail("Bootstrap: the countdown's sounds are not in the list (or not marked as having a stand-in)")
try:
    import numpy as np
    from scipy.io import wavfile
    TOCK = AUDIO / "story" / "CountdownTock_x3.wav"
    if not TOCK.exists():
        fail("audio/story/CountdownTock_x3.wav is missing")
    else:
        sr, tock = wavfile.read(TOCK)
        tock = tock.astype(float) / 32767
        if abs(len(tock) / sr - 3.0) > 0.01:
            fail("CountdownTock_x3.wav is not three one-second slots")
        for k in range(3):
            slot = tock[int(sr * k):int(sr * (k + 0.95))]
            if np.max(np.abs(slot)) < 0.1:
                fail("CountdownTock_x3.wav: slot %d is silent" % k)
                continue
            spectrum = np.abs(np.fft.rfft(slot)) ** 2
            freqs = np.fft.rfftfreq(len(slot), 1 / sr)
            if (freqs * spectrum).sum() / spectrum.sum() > 1600:
                fail("CountdownTock_x3.wav: slot %d is bright and high, a ping, not a tock" % k)
except ImportError:
    pass
JOURNAL_SRC = read("Client", "Services", "JournalService.lua")
if 'if typeof(entry) == "table" and typeof(entry.thing) == "string" then' not in JOURNAL_SRC:
    fail("JournalService: the keepsakes' total counts the module's STAMP too (27 of 28 with all found)")
# SAVING, SAID PLAINLY (2026-10-17): a module named ProfileStore that is not loleris's (no ProfileStore.New) was
# reported as "attempt to call a nil value"; it is named, with where it is, before anything calls it.
store_fn = ECONOMY[ECONOMY.find("local function openStore()"):ECONOMY.find("-- ===== WHAT THE CLIENT IS TOLD =====")]
if 'if type(result) ~= "table" or type((result :: any).New) ~= "function" then' not in store_fn \
        or store_fn.find("(result :: any).New) ~= \"function\"") > store_fn.find("return (result :: any).New(name, TEMPLATE)"):
    fail("EconomyService: a module named ProfileStore that is not loleris's is called anyway (\"attempt to call a nil value\")")

# ===== THE COSMETICS AS THINGS (the ninety-seventh pass) =====
#
# Every trail, aura and set of steps has pieces (ShopCatalog.PIECES), each piece a mesh blender/gen_cosmetics.py makes
# (or a plain ball), a motion the client knows, sizes a person could wear, never Neon; the client draws them for
# everyone near, cheaply (pooled, capped, culled by distance, anchored and touching nothing), reading what is worn off
# the character as ShopCatalog.wear tags it, the shop's try-on first; and the steps are pressed in as meshes, the flat
# print kept for a place without them.
COSMETICS = read("Client", "Services", "CosmeticsClient.lua")
STEPS_SRC = read("Client", "Services", "StepService.lua")
MESHES = ROOT / "meshes" / "cosmetics"
pieces_block = CATALOG[CATALOG.find("local PIECES: { [string]: Pieces } = {"):CATALOG.find("function ShopCatalog.pieces(")]
if not pieces_block:
    fail("ShopCatalog: no PIECES (the cosmetics as modelled things)")
else:
    entries = {}
    for m in re.finditer(r"^\t(\w+) = \{ motion = \"(\w+)\"(.*?)(?=^\t\w+ = \{ motion|^\})", pieces_block, re.M | re.S):
        entries[m.group(1)] = (m.group(2), m.group(3))
    TRAIL_MOTIONS = {"toss", "drip", "splat", "bounce", "rise", "puff", "flutter"}
    AURA_MOTIONS = {"orbit", "rise", "fall", "hover", "drift"}
    for ident, _tab, kind, _body in items:
        item = {"id": ident, "kind": kind}
        if item["kind"] not in ("trail", "aura", "steps"):
            continue
        entry = entries.get(item["id"])
        if not entry:
            fail("ShopCatalog: %s (a %s) has no pieces, so it is particles only" % (item["id"], item["kind"]))
            continue
        motion, body = entry
        allowed = TRAIL_MOTIONS if item["kind"] == "trail" else AURA_MOTIONS if item["kind"] == "aura" else {"press"}
        if motion not in allowed:
            fail("ShopCatalog: %s moves as %r, which a %s does not" % (item["id"], motion, item["kind"]))
        meshes = re.findall(r'mesh = "(\w+)"', body) + re.findall(r'wings = "(\w+)"', body)
        if not meshes:
            fail("ShopCatalog: %s's pieces name no mesh" % item["id"])
        for mesh in meshes:
            if mesh != "Ball" and not (MESHES / (mesh + ".fbx")).exists():
                fail("ShopCatalog: %s is made of %s, and meshes/cosmetics/%s.fbx is not made" % (item["id"], mesh, mesh))
        for size in re.findall(r"size = ([\d.]+)", body):
            top = 2.0 if item["kind"] in ("steps", "aura") else 1.0
            if not 0.15 <= float(size) <= top:
                fail("ShopCatalog: a piece of %s is %s studs: too small to see or bigger than a person wears" % (item["id"], size))
        if "Neon" in body:
            fail("ShopCatalog: %s fakes light with Neon" % item["id"])
        every = re.search(r"every = ([\d.]+)", body)
        count = re.search(r"count = (\d+)", body)
        if item["kind"] == "trail" and (not every or float(every.group(1)) < 0.4):
            fail("ShopCatalog: %s's trail lets go a piece more often than every 0.4 studs (a flood)" % item["id"])
        if item["kind"] == "aura" and (not count or not 1 <= int(count.group(1)) <= 8):
            fail("ShopCatalog: %s's aura has %s pieces round you (1 to 8)" % (item["id"], count.group(1) if count else "no"))
    for needle, why in (
        ('top:SetAttribute("PieceTrail", trail.id)', "what trail is worn is not on the character for the pieces"),
        ('at:SetAttribute("PieceAura", aura.id)', "what aura is worn is not on the character for the pieces"),
    ):
        if needle not in CATALOG:
            fail("ShopCatalog.wear: " + why)
if not COSMETICS:
    fail("src/Client/Services/CosmeticsClient.lua is missing")
else:
    caps = {k: float(v) for k, v in re.findall(r"^local (NEAR|TRAIL_MAX|AURA_MAX|PIECES_MAX) = ([\d.]+)", COSMETICS, re.M)}
    if len(caps) < 4:
        fail("CosmeticsClient: this check can no longer read its limits")
    elif caps["NEAR"] > 160 or caps["TRAIL_MAX"] > 30 or caps["AURA_MAX"] > 10 or caps["PIECES_MAX"] > 320:
        fail("CosmeticsClient: its limits are too loose for a busy lobby: %s" % caps)
    for needle, why in (
        ('root:FindFirstChild("ShopPreviewTrailTop") or root:FindFirstChild("CosmeticTrailTop")',
         "the shop's try-on is not drawn over what is worn (or what is worn is not drawn)"),
        ('root:FindFirstChild("ShopPreviewAura") or root:FindFirstChild("CosmeticAura")', "the aura's try-on is not drawn"),
        ("(root.Position - eye).Magnitude < NEAR", "pieces are drawn for players however far off"),
        ("if #live >= PIECES_MAX then", "there is no limit on pieces in all"),
        ("count < TRAIL_MAX", "a trail's pieces are not limited"),
        ("made.CanCollide = false\n\t\tmade.CanQuery = false\n\t\tmade.CanTouch = false", "a piece can be walked into or hit"),
        ("made.Anchored = true", "a piece is left to the physics"),
        ("table.insert(pool[mesh], part)", "pieces are made and destroyed every time, not kept"),
        ('made:SetAttribute("Base", made.Size)', "a piece back from the pool keeps the squash it landed with"),
        ("ShopCatalog.pieces(w.trail)", "the trail's pieces are not the catalogue's"),
        ('elseif piece.material == "Neon" then Enum.Material.SmoothPlastic', "Neon could be used for a piece"),
    ):
        if needle not in COSMETICS:
            fail("CosmeticsClient: " + why)
# THE TRAILS AS STRANDS (the hundred-and-seventh pass: "the trail should be less wide ... more creative"): every trail
# a set of thin strands, each moved by a motion CosmeticsClient knows; the whole of one no taller than a stud and a half
# (it was two); and every aura's ring or halo within its limit and drawn.
MOTIONS = set(re.findall(r'(?:if|elseif) s\.motion == "(\w+)" then', COSMETICS)) | {"still"}
ribbon_ids = []
for m in re.finditer(r"^\t(\w+) = \{\n\t\tribbon = \{(.*?)\n\t\tmotes = \{", looks_block, re.M | re.S):
    look_id, body = m.group(1), m.group(2)
    ribbon_ids.append(look_id)
    width = re.search(r"\bwidth = ([\d.]+),\s*life", body)
    strands = re.findall(r"\{ at = Vector3\.new\((-?[\d.]+), (-?[\d.]+), (-?[\d.]+)\), motion = \"(\w+)\"(.*?)\}", body, re.S)
    if not width or not strands:
        fail("ShopCatalog: the %s trail has no strands, so it is the old wide sheet" % look_id)
        continue
    if float(width.group(1)) > 0.45:
        fail("ShopCatalog: the %s trail is %s studs wide; a strand is thin (0.45 at the most)" % (look_id, width.group(1)))
    low, high = 99.0, -99.0
    for x, y, z, motion, rest in strands:
        own = re.search(r"\bwidth = ([\d.]+)", rest)
        radius = re.search(r"\bradius = ([\d.]+)", rest)
        fade = re.search(r"\bfade = ([\d.]+)", rest)
        half = float(own.group(1) if own else width.group(1)) / 2
        reach = float(radius.group(1)) if radius and motion in ("bob", "bounce", "zigzag", "flutter") else 0
        if motion not in MOTIONS:
            fail("ShopCatalog: a strand of the %s trail moves by %s, which CosmeticsClient does not know" % (look_id, motion))
        if own and float(own.group(1)) > 0.45 and not (fade and float(fade.group(1)) >= 0.5):
            fail("ShopCatalog: a strand of the %s trail is %s studs wide and not faint" % (look_id, own.group(1)))
        low, high = min(low, float(y) - half - (reach if motion != "bounce" else 0)), max(high, float(y) + half + reach)
    if high - low > 1.5 + 1e-6 and look_id != "CloudPuff":
        fail("ShopCatalog: the %s trail stands %.2f studs tall, wider than before it was thinned" % (look_id, high - low))
for item_id, tab, kind, rest in items:
    if kind == "trail" and item_id not in ribbon_ids:
        fail("ShopCatalog: the %s trail has no ribbon of strands" % item_id)
ring_max = re.search(r"^local RING_MAX = (\d+)", COSMETICS, re.M)
pieces_block = CATALOG[CATALOG.find("local PIECES: { [string]: Pieces } = {"):CATALOG.find("function ShopCatalog.pieces(")]
starts = [(m.start(), m.group(1)) for m in re.finditer(r"^\t(\w+) = \{ motion = ", pieces_block, re.M)]
ring_counts = []
for k, (at, look_id) in enumerate(starts):
    entry = pieces_block[at:starts[k + 1][0] if k + 1 < len(starts) else len(pieces_block)]
    found_ring = re.search(r"ring = \{ count = (\d+),", entry)
    if found_ring:
        ring_counts.append((look_id, found_ring.group(1)))
if len(ring_counts) < 5:
    fail("ShopCatalog: this check finds %d auras with a ring or halo; there are five" % len(ring_counts))
for look_id, count in ring_counts:
    if not ring_max or int(count) > int(ring_max.group(1)):
        fail("ShopCatalog: the %s aura's ring has %s, more than CosmeticsClient keeps (RING_MAX)" % (look_id, count))
if not ring_max or int(ring_max.group(1)) > 16:
    fail("CosmeticsClient: an aura's ring has no limit, or too loose a one, for a busy lobby")
for needle, why in (
    ('if child:IsA("Attachment") and typeof(motion) == "string" then', "a trail's strands are never found"),
    ("s.top.Position = centre + Vector3.new(0, s.half, 0)\n\t\t\ts.bottom.Position = centre - Vector3.new(0, s.half, 0)",
     "a trail's strands are found and never moved"),
    ("moveStrands(w, root, now)", "a trail's strands are never moved"),
    ('if motion == "ring" or motion == "halo" then', "an aura's ring and halo are never placed"),
    ("local ringLook = ringOf(w.aura)", "an aura's ring is never made"),
    ("for _, one in ipairs(w.ringSet) do\n\t\t\t\t\tone.life = 0", "an old aura's ring stays when it is changed"),
    ("for _, one in ipairs(w.ringSet) do\n\t\t\t\tone.life = 0", "a ring stays round someone gone out of sight"),
    ("local at, u = auraPlace(one, look, (root :: BasePart).Position, now, (w :: Wearer).drop)",
     "a ring is not at the feet of the one wearing it"),
):
    if needle not in COSMETICS:
        fail("CosmeticsClient: " + why)
for needle, why in (
    ('top:SetAttribute("StrandMotion", strand.motion)', "a strand's motion is never told to the screens"),
    ("band.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) })",
     "a strand is not full width where it leaves you, tapering to nothing"),
    ('top:SetAttribute("PieceTrail", trail.id)', "the trail's pieces are never drawn"),
):
    if needle not in CATALOG:
        fail("ShopCatalog: " + why)
if "local function meshPrint(id: string, frame: CFrame, life: number): BasePart?" not in STEPS_SRC \
        or "local made = meshPrint(id, CFrame.fromMatrix(at, right, up) * MESH_TURN, life)" not in STEPS_SRC:
    fail("StepService: the steps are flat prints only (no pieces pressed in)")
# THE MODELLED PRINTS TURNED ROUND (the hundred-and-twenty-third pass, from your test: "the honey steps are reversed 180
# degrees"): Blender's pieces face back along the way you walk, so each is turned a half turn about the ground's up.
if "local MESH_TURN = CFrame.Angles(0, math.pi, 0)" not in STEPS_SRC:
    fail("StepService: the modelled prints are laid backwards (the paw's toes behind its pad)")
if "drawPrint(canvas, id, item.colour, item.accent)" not in STEPS_SRC:
    fail("StepService: no flat print for a place without the meshes")
started = re.search(r'for _, name in ipairs\(\{(.*?)\}\) do', read("Client", "Bootstrap.client.lua"), re.S)
if not started or '"CosmeticsClient"' not in started.group(1):
    fail("the client's Bootstrap does not start CosmeticsClient")

# ===================================================================== the backgrounds and their crate (106)
RARITY_NAMES = ("common", "rare", "epic", "legendary", "mythic")
rarity_block = CATALOG[CATALOG.find("local RARITY: "):CATALOG.find("ShopCatalog.RARITY = RARITY")]
rarities = {m[0]: m for m in re.findall(r'^\t(\w+) = \{ name = "([^"]+)", word = "([^"]+)", colour = (rgb\([^)]*\)) \},$',
                                         rarity_block, re.M)}
if tuple(rarities) != RARITY_NAMES:
    fail("ShopCatalog.RARITY is not %s, in that order (%s)" % (", ".join(RARITY_NAMES), ", ".join(rarities)))
if len({m[3] for m in rarities.values()}) < len(rarities):
    fail("ShopCatalog.RARITY: two rarities share a colour")
crate_block = CATALOG[CATALOG.find("local CRATE: "):CATALOG.find("ShopCatalog.CRATE = CRATE")]
crate_id = re.search(r'\bid = "(\w+)"', crate_block)
order_m = re.search(r"order = \{(.*?)\}", crate_block)
odds_m = re.search(r"odds = \{(.*?)\}", crate_block)
crate_order = re.findall(r'"(\w+)"', order_m.group(1)) if order_m else []
crate_odds = {k: int(v) for k, v in re.findall(r"(\w+) = (\d+)", odds_m.group(1))} if odds_m else {}
if not (crate_id and crate_order and crate_odds):
    fail("ShopCatalog.CRATE: this check can no longer read its id, order and odds")
else:
    if sum(crate_odds.values()) != 100:
        fail("ShopCatalog.CRATE: its odds add up to %d, not 100" % sum(crate_odds.values()))
    if set(crate_odds) != set(crate_order) or [r for r in RARITY_NAMES if r in crate_order] != crate_order:
        fail("ShopCatalog.CRATE: its order and its odds do not name the same rarities, rarest last")
    if "mythic" in crate_order:
        fail("ShopCatalog.CRATE: the mythic rarity is in the crate; it is sold for Robux alone")
    if any(v <= 0 for v in crate_odds.values()):
        fail("ShopCatalog.CRATE: a rarity in it never comes")
    crate_items = [(i, k, r) for i, t, k, r in items if i == crate_id.group(1)]
    if not crate_items or crate_items[0][1] != "crate" or not re.search(r"\bprice = \d+", crate_items[0][2]):
        fail("ShopCatalog.CRATE names %s, which is not a crate sold for tokens" % crate_id.group(1))
if sum(1 for _, _, k, _ in items if k == "crate") != 1:
    fail("ShopCatalog has more than one crate, or none")
look_text = read("Client", "Services", "ShopLook.lua")
look_themes_block = look_text[look_text.find("ShopLook.THEMES = {"):look_text.find("ShopLook.DEFAULTS = ")]
look_themes = dict(re.findall(r'^\t(\w+) = \{ id = "\w+", name = "[^"]*", rarity = "(\w+)"', look_themes_block, re.M))
in_crate = {}
backed = set()
for item_id, tab, kind, rest in items:
    if kind != "background":
        continue
    theme = re.search(r'\btheme = "(\w+)"', rest)
    rarity = re.search(r'\brarity = "(\w+)"', rest)
    if not (theme and rarity):
        fail("the background %s has no theme or no rarity" % item_id)
        continue
    theme, rarity = theme.group(1), rarity.group(1)
    if theme not in look_themes:
        fail("the background %s is the theme %s, which ShopLook does not draw" % (item_id, theme))
    elif look_themes[theme] == "default":
        fail("the background %s is everyone's already (%s is a default)" % (item_id, theme))
    elif look_themes[theme] != rarity:
        fail("the background %s is %s in the catalogue and %s in ShopLook" % (item_id, rarity, look_themes[theme]))
    if theme in backed:
        fail("two backgrounds are the one theme %s" % theme)
    backed.add(theme)
    if rarity not in rarities:
        fail("the background %s has a rarity, %s, that is not one" % (item_id, rarity))
    if 'earn = "crate"' in rest:
        if rarity not in crate_order:
            fail("the background %s is in the crate, and its rarity %s never comes out of it" % (item_id, rarity))
        in_crate.setdefault(rarity, []).append(item_id)
    elif not (re.search(r"\brobux = \d+", rest) and "passId = " in rest):
        fail("the background %s is neither in the crate nor a Robux pass" % item_id)
for theme, rarity in look_themes.items():
    if rarity != "default" and theme not in backed:
        fail("ShopLook draws the %s background, and nothing in the shop gives it" % theme)
for rarity in crate_order:
    if not in_crate.get(rarity):
        fail("the crate's %s rarity has no background in it" % rarity)
for needle, why in (
    ("if item.earn == \"crate\" and item.rarity == rarity and not has(item.id) then",
     "a crate can give a background you already have"),
    ("if total <= 0 then\n\t\treturn nil", "a crate gives something when you have every background in it"),
    ("local at = math.clamp(roll, 0, 0.999999) * total", "a crate's rarity is not by its share of the odds"),
    ("local list, total = lacking(has or function(_: string): boolean", "the odds said are not the ones for what you have"),
):
    if needle not in CATALOG:
        fail("ShopCatalog: " + why)
crate_branch = handler[handler.find('if action == "crate" or item.kind == "crate" then'):handler.find('if action == "buy" and item.earn then')]
if not (0 <= handler.find("if item.soon then") < handler.find('if action == "crate" or item.kind == "crate" then')
        < handler.find('if action == "buy" and item.earn then')):
    fail("EconomyService: the crate is not handled before a buy (a crate could be bought as a thing)")
for needle, why in (
    ('if action ~= "crate" or item.kind ~= "crate" or not item.price then', "a crate can be bought as a thing, or "
                                                                            "something else opened as a crate"),
    ('if randomOk[player] ~= true then\n\t\t\treturn answer(player, false, "restricted")',
     "a crate opens where Roblox's policy keeps paid random items out"),
    ("end, crateDice:NextNumber(), crateDice:NextNumber())", "a crate is not rolled with the server's own dice"),
    ("return owns(player, other)", "a crate does not know what you have already"),
    ('if not won then\n\t\t\treturn answer(player, false, "owned")', "a crate opens when there is nothing left in it"),
    ('if data.Tokens < item.price then\n\t\t\treturn answer(player, false, "short")', "a crate opens without the tokens"),
    ("data.Tokens -= item.price\n\t\tdata.Owned[won.id] = true", "a crate takes its price without giving what came out"),
):
    if needle not in crate_branch:
        fail("EconomyService: " + why)
for needle, why in (
    ('local PolicyService = game:GetService("PolicyService")', "Roblox's policy for paid random items is never asked"),
    ("return PolicyService:GetPolicyInfoForPlayerAsync(player)", "Roblox's policy for paid random items is never asked"),
    ('randomOk[player] = okPolicy and type(policy) == "table" and policy.ArePaidRandomItemsRestricted == false',
     "the crates are offered when the policy says no, or did not answer"),
    ("if RunService:IsStudio() and not randomOk[player] then\n\t\trandomOk[player] = true",
     "the crates are offered against the policy outside Studio"),
    ("randomOk[player] = nil", "a player's policy outlives them"),
    ("crates = randomOk[player] == true,", "the shop is not told whether the crates are offered"),
    ('if (item.kind == "pass" or item.kind == "background") and item.passId and item.passId ~= 0', "the mythic background is never found owned"),
    ('check("a crate gives a background you lacked"', "the Studio self-test does not open a crate"),
):
    if needle not in ECONOMY:
        fail("EconomyService: " + why)
press_fn = SHOP[SHOP.find("local function pressPrice("):SHOP.find("-- ===== ONE TILE =====")]
crate_fn = SHOP[SHOP.find("local function openCrate("):SHOP.find("-- ===== PRESSING A PRICE =====")]
for needle, why, where in (
    ("if shop.data and shop.data.crates == false then", "a crate is offered where the policy keeps them out", crate_fn),
    ("if ShopCatalog.crateDone(owned) then", "a crate is offered with nothing left in it", crate_fn),
    ('confirm(("Open a crate for %d tokens? Always one you do not have. %s."):format(price, ShopCatalog.crateOdds(owned)),',
     "a crate is paid for before its odds are said", crate_fn),
    ('return ask("crate", crate.id)', "a crate is not opened by the server", crate_fn),
    ('if item.kind == "crate" then\n\t\topenCrate(item)', "pressing the crate's price does not open one", press_fn),
    ("if item.robux and not (item.kind == \"background\" and owned(item.id)) then",
     "a Robux background, once yours, cannot be put on", press_fn),
    ("if ShopLook and ShopLook.crating() then\n\t\t\t\tShopLook.dismiss()", "Escape or B closes the shop under an open crate",
     SHOP),
    ("ShopLook.choose(if worn then worn.theme else nil)", "the shop does not open on the background you have on", SHOP),
    ("ShopLook.onRepaint(paintTitle)", "the title keeps the old background's colours", SHOP),
):
    if needle not in where:
        fail("ShopService: " + why)
if press_fn.find('if item.kind == "crate" then') > press_fn.find('if item.earn and not owned(item.id) then\n\t\ttoast("Finish the story'):
    fail("ShopService: a background in the crates says to finish the story")
if re.search(r"\b(60|25|11|4)%", SHOP):
    fail("ShopService writes the crate's odds out itself; they come from ShopCatalog.crateOdds")
for needle, why in (
    ("local level = RARITY_TAKE[won.rarity] or 1", "a crate's reveal is not the sound of its rarity"),
    ('playSound("ShopSounds/CrateReveal_x5", 0.7, level)', "a crate's reveal has no sound"),
    ('playSound("ShopSounds/CrateShake", 0.6)', "a crate shakes in silence"),
    ("Style.fit(stage, Vector2.new(340, 430))", "the crate is not fitted to the screen"),
    ("if look.crating then\n\t\t\treturn\n\t\tend", "a press on the shop under a crate is answered"),
    ("GuiService.SelectedObject = c.wear", "a controller cannot put on what came out"),
    ("while look.crating == \"shaking\" and (not answered or os.clock() - started < 1.2) and os.clock() - started < 15 do",
     "the crate shakes for ever when the server does not answer"),
    ("hideCrate(false)\n\t\t\trefused(result)", "a crate refused is not said why"),
    ("if look.crating then\n\t\thideCrate(false)\n\tend", "a crate stays over the screen once the shop is shut"),
):
    if needle not in SHOP_LOOK:
        fail("ShopLook: " + why)
takes = re.search(r"local RARITY_TAKE = \{(.*?)\}", SHOP_LOOK)
if not takes or tuple(re.findall(r"(\w+) = \d+", takes.group(1))) != RARITY_NAMES:
    fail("ShopLook: RARITY_TAKE does not give every rarity its reveal")

# ===================================================================== its look (ShopLook)
FIELDS = ("id", "name", "rarity", "top", "bottom", "edge", "title", "titleInk", "decor", "effect", "sound", "fx", "fx2")
RARITIES = ("default", "common", "rare", "epic", "legendary", "mythic")
themes_block = SHOP_LOOK[SHOP_LOOK.find("ShopLook.THEMES = {"):SHOP_LOOK.find("ShopLook.DEFAULTS = ")]
themes = {}
for m in re.finditer(r"^\t(\w+) = \{ (.*?) \},?$", themes_block, re.M | re.S):
    themes[m.group(1)] = m.group(2)
if SHOP_LOOK and not themes:
    fail("ShopLook: this check can no longer read its THEMES")
paint_fn = SHOP_LOOK[SHOP_LOOK.find("local function paint("):SHOP_LOOK.find("local function step(")]
burst_fn = SHOP_LOOK[SHOP_LOOK.find("local function burst("):SHOP_LOOK.find("-- ===== THE BACKDROP")]
for key, body in themes.items():
    fields = dict(re.findall(r"\b(\w+) = (\"[^\"]*\"|rgb\([^)]*\))", body))
    missing = [f for f in FIELDS if f not in fields]
    if missing:
        fail("ShopLook: the %s theme has no %s" % (key, ", ".join(missing)))
        continue
    if fields["id"] != '"%s"' % key:
        fail("ShopLook: the %s theme calls itself %s" % (key, fields["id"]))
    if fields["rarity"].strip('"') not in RARITIES:
        fail("ShopLook: the %s theme's rarity %s is not one of %s" % (key, fields["rarity"], ", ".join(RARITIES)))
    if 'theme.decor == %s' % fields["decor"] not in paint_fn:
        fail("ShopLook: the %s theme's %s is never drawn behind the shop" % (key, fields["decor"]))
    if 'effect == %s' % fields["effect"] not in burst_fn:
        fail("ShopLook: a press on the %s theme does nothing (%s)" % (key, fields["effect"]))
    for word in re.findall(r'"([^"]*)"', fields["name"]):
        if "--" in word or "\u2014" in word or "\u2013" in word:
            fail("ShopLook: the %s theme's name has a dash in it" % key)
defaults = re.search(r"ShopLook\.DEFAULTS = \{(.*?)\}", SHOP_LOOK)
default_ids = re.findall(r'"(\w+)"', defaults.group(1)) if defaults else []
if len(default_ids) < 3:
    fail("ShopLook: fewer than three backgrounds to open on at random")
for key in default_ids:
    if key not in themes:
        fail("ShopLook: a default background %s is not a theme" % key)
    elif 'rarity = "default"' not in themes[key]:
        fail("ShopLook: the default background %s is sold in the crates as well" % key)
for key, body in themes.items():
    if 'rarity = "default"' in body and key not in default_ids:
        fail("ShopLook: the %s background is everyone's but never opened on" % key)
colours = re.search(r"ShopLook\.TAB_COLOURS = \{(.*?)\n\}", SHOP_LOOK, re.S)
coloured = set(re.findall(r"(\w+) = rgb\(", colours.group(1))) if colours else set()
order = re.search(r"ShopLook\.TAB_ORDER = \{(.*?)\}", SHOP_LOOK, re.S)
ordered = re.findall(r'"(\w+)"', order.group(1)) if order else []
if ordered[:len(tabs)] != tabs:
    fail("ShopLook: its tabs' sounds are not in ShopCatalog.TABS's order (%s, and %s)" % (ordered, tabs))
for tab in ordered:
    if tab not in coloured:
        fail("ShopLook: the %s tab has no colour of its own" % tab)
if len(set(re.findall(r"rgb\(([^)]*)\)", colours.group(1) if colours else ""))) < len(coloured):
    fail("ShopLook: two tabs share a colour")
for needle, why in (
    ('if onPanel and not onButton then', "a press on a button also cracks, sparkles or crumbles the background"),
    ("burst(look.theme.effect, screenAt, 1)\n\t\t\tplaySound(look.theme.sound, 0.55)",
     "a press on the background is not answered with its effect and its material's sound"),
    ("local usingMouse = UserInputService.MouseEnabled and not UserInputService.TouchEnabled",
     "the cookie cursor is drawn on a touch screen, under a finger"),
    ("UserInputService.MouseIconEnabled = true", "the system's cursor is never given back"),
    ("cursorOn(false)", "the cookie stays on screen after the shop closes"),
    ("look.pressing:Disconnect()\n\t\tlook.pressing = nil", "the shop's background still answers presses once shut"),
    ("look.stepping:Disconnect()\n\t\t\t\tlook.stepping = nil", "the backdrop keeps moving every frame once shut"),
    ("id = ShopLook.DEFAULTS[math.random(1, #ShopLook.DEFAULTS)]", "the shop does not open on a background at random"),
    ('playSound("ShopSounds/ShopOpen", 0.6)', "the shop opens without its own sound"),
    ('playSound("ShopSounds/ShopClose", 0.55)', "the shop closes without its own sound"),
    ("local index = table.find(ShopLook.TAB_ORDER, name)", "a tab's sound is not its own"),
    ('if folderName == "MaterialSounds" and AudioService and AudioService.takesFor and AudioService.applyTake then',
     "a material's press is not the chunk's own sound (your soap's crumble)"),
    ("fx.DisplayOrder = (screen.DisplayOrder or 30) + 1", "the effects and the cookie are drawn under the shop"),
    ("backdrop.ZIndex = 0", "the background is drawn over the shop's tiles"),
):
    if needle not in SHOP_LOOK:
        fail("ShopLook: " + why)
puff_fn = SHOP_LOOK[SHOP_LOOK.find("function ShopLook.puff("):SHOP_LOOK.find("function ShopLook.tab(")]
if "if not look.open or look.crating then" not in puff_fn or "playSound" in puff_fn:
    fail("ShopLook: a puff of the material comes under a crate, or with a sound of its own over the press's")
if "Neon" in SHOP_LOOK or "Image" in re.sub(r"--[^\n]*", "", SHOP_LOOK):
    fail("ShopLook: its backgrounds use images or Neon; they are drawn from frames alone")
for needle, why in (
    ('local found = script.Parent and script.Parent:FindFirstChild("ShopLook")', "ShopLook is never loaded"),
    ("\tif ShopLook then\n\t\tShopLook.attach(panel, screen)\n\tend", "ShopLook is never put in the shop"),
    ("\t\tShopLook.opened()\n", "the shop opens without its look"),
    ("\t\tShopLook.closed()\n", "the shop closes without its look"),
    ("ShopLook.tab(tab)", "a tab pressed has no sound of its own"),
    ("ShopLook.tab(nextTab)", "a tab changed with a controller has no sound of its own"),
    ("local fam = family(button.Name)", "the tabs are all the one colour"),
    ("ShopLook.TAB_COLOURS[tab]", "the tabs' colours are not ShopLook's"),
    # (The hundred-and-twenty-third pass, from your test: "I wanna be able to switch tabs by using arrow keys".)
    ("Enum.KeyCode.ButtonR1, Enum.KeyCode.Left,\n\t\tEnum.KeyCode.Right)", "the arrow keys do not change tab"),
    ("local back = input.KeyCode == Enum.KeyCode.ButtonL1 or input.KeyCode == Enum.KeyCode.Left",
     "the left arrow goes the wrong way"),
    ("ui.title.BackgroundColor3 = theme.title", "the title is not in the background's colours"),
):
    if needle not in SHOP:
        fail("ShopService: " + why)
# MADE OVER (the hundred-and-twenty-second pass, from your test: "resize the UI appropriately so that the edges of the
# categories are not cut off, and work on the colours a bit more, and improve those animations ... and the layout, and
# make it fancier"). The tabs sit inside their strip with room all round, measured here against how far the widest one
# grows when chosen and its outline; the tiles likewise inside the grid. A tab's colours run through its tiles, its deep
# shades kept in its own hue, and the words on them are measured for contrast. Tiles are cards on lips over a tray,
# popping in only when a tab has just opened (an answer about tokens alone draws nothing again); the gleams turn only
# while the shop is open; your tokens are counted; the best pack is worked out from the catalogue, never written in.
layout_fn = SHOP[SHOP.find("local function layout()"):SHOP.find("-- ===== BUILDING IT =====")]
build_fn = SHOP[SHOP.find("local function build()"):SHOP.find("-- ===== OPEN AND CLOSE =====")]
open_fn = SHOP[SHOP.find("function ShopService.open("):SHOP.find("function ShopService.close()")]
close_fn = SHOP[SHOP.find("function ShopService.close()"):SHOP.find("function ShopService.isOpen()")]
tile_fn = SHOP[SHOP.find("local function makeTile("):SHOP.find("-- ===== THE GRID AND THE TABS =====")]
render_fn = SHOP[SHOP.find("render = function()"):SHOP.find("function ShopService.showTab(")]
family_fn = SHOP[SHOP.find("local function family(tab: string): Family"):SHOP.find("local function tabGlyph(")]
for needle, why, where in (
    ("ui.tabs.Size = UDim2.new(1, -(28 - 2 * TAB_ROOM), 0, tabsH + 2 * TAB_ROOM)",
     "the tabs' strip is no bigger than its tabs, so their edges are cut off", layout_fn),
    ("ui.tabs.Position = UDim2.new(0, 14 - TAB_ROOM, 0, stripTop)", "the tabs' strip is not widened out round them", layout_fn),
    ("tabRoom.PaddingLeft = UDim.new(0, TAB_ROOM)", "the first tab's left edge is cut off", build_fn),
    ("tabRoom.PaddingTop = UDim.new(0, TAB_ROOM)", "the tabs' top edges are cut off", build_fn),
    ("tabRoom.PaddingBottom = UDim.new(0, TAB_ROOM)", "the tabs' lips are cut off along the bottom", build_fn),
    ("tail.Size = UDim2.fromOffset(TAB_ROOM, 1)", "the last tab's right edge can be cut off", build_fn),
    ("gridPad.PaddingLeft = UDim.new(0, TILE_ROOM)", "a tile's outline is cut off at the grid's left", build_fn),
    ("gridPad.PaddingRight = UDim.new(0, TILE_ROOM)", "a tile's outline is cut off at the grid's right", build_fn),
    ("gridPad.PaddingTop = UDim.new(0, TILE_ROOM + 3)", "a lifted tile's outline is cut off along the grid's top", build_fn),
    ("local inner = (w - 36) - 16 - 2 * TILE_ROOM",
     "the tiles are sized without the room round them, so the last column is squeezed", layout_fn),
    ("tabGlyph(disc, tab, fam.edge)", "the tabs have no drawings of their own", build_fn),
    ("top.Size = UDim2.new(1, 0, 1, -TAB_LIP)", "the tabs stand on no lip", build_fn),
    ("TweenService:Create(top, how, { Position = to }):Play()", "a tab pressed does not sink onto its lip", build_fn),
    ("ShopLook.puff(button, 0.5)", "a tab chosen puffs none of the background's material", build_fn),
    ("ui.tray = tray", "the tiles sit straight on the moving background", build_fn),
    ("tray.ZIndex = 2", "the tray is drawn over the tiles, or under the background", build_fn),
    ("grid.ZIndex = 3", "the tiles are drawn under their tray", build_fn),
    ("modal.ZIndex = 10", "the confirm card is drawn under the tiles", build_fn),
    ("card.Size = UDim2.new(1, 0, 1, -TILE_LIP)", "a tile stands on no lip", tile_fn),
    ("TweenService:Create(card, TweenInfo.new(0.06, Enum.EasingStyle.Quad), { Position = sunk }):Play()",
     "a tile pressed does not sink onto its lip", tile_fn),
    ("light.Color = ColorSequence.new(LOOK.white, fam.pale)", "a tile is not washed in its tab's colour", tile_fn),
    ("local outline = stroke(card, fam.edge, 3)", "a tile is not outlined in its tab's colour", tile_fn),
    ("if shop.fresh then\n\t\tlift.Scale = 0", "the tiles never pop in", tile_fn),
    ("table.insert(shop.gleams, run)", "the rare tiles have no gleam", tile_fn),
    ('elseif item.kind == "tokens" and item.id == bestPack() then "Best value"', "the best pack does not say so", tile_fn),
    ("shop.fresh = false", "every redraw pops the tiles in again", render_fn),
    ("paintTabs()", "the tabs are never painted for the one chosen", render_fn),
    ('ui.progressWords.Text = ("%d of %d yours"):format(have, of)', "a tab never says how many of it are yours", render_fn),
    ("if shop.open and drawnFrom(data) ~= shop.drawn then\n\t\trender()", "every answer from the server draws the grid again",
     SHOP),
    ("showTokens(data.tokens)", "your tokens jump rather than count", SHOP),
    ("shop.fresh = true", "the tiles do not pop in when the shop opens", open_fn),
    ("ui.spin = RunService.RenderStepped:Connect(function()", "the gleams never turn", open_fn),
    ("run.Rotation = turn", "the gleams stand still", open_fn),
    ("ui.spin:Disconnect()\n\t\tui.spin = nil", "the gleams keep turning every frame once the shop is shut", close_fn),
    ("{ BackgroundTransparency = 1 }):Play()", "the dark behind the shop does not fade as it closes", close_fn),
):
    if needle not in where:
        fail("ShopService: " + why)
# THE ICON SWELLS CLEAR OF THE WORDS (the hundred-and-twenty-third pass, from your test: "when I hover over the icons
# in the shop, they get bigger which is cool but the text gets covered"): held by its middle, so it grows evenly, and
# its growth downward (half the swell past its size) stays inside the gap over the name.
if "icon.AnchorPoint = Vector2.new(0.5, 0.5)" not in tile_fn or "icon.Position = UDim2.new(0.5, 0, 0, top + iconD / 2)" not in tile_fn:
    fail("ShopService: a tile's icon swells from its top, down over its name")
swell_to = re.search(r"TweenService:Create\(swell, spring, \{ Scale = ([\d.]+) \}\)", tile_fn)
icon_d = re.search(r"local iconD = math\.floor\(math\.min\(cellW \* ([\d.]+), cellH \* ([\d.]+)\)\)", tile_fn)
gap = re.search(r"local nameY = top \+ iconD \+ math\.floor\((\d+) \* t\)", tile_fn)
if not (swell_to and icon_d and gap):
    fail("ShopService: this check can no longer read a tile's icon and its gap")
else:
    widest_icon = min(300 * float(icon_d.group(2)), 300 * float(icon_d.group(1)))  # a tall tile's icon at its largest
    if widest_icon * (float(swell_to.group(1)) - 1) / 2 >= int(gap.group(1)) * 0.8:
        fail("ShopService: a swollen icon (%.0f pixels at most, to %s) covers the name under it" % (widest_icon, swell_to.group(1)))
# LIVELIER TILES (the hundred-and-thirty-fifth pass, from your test: "improve the shop looks even more"): a sunburst
# turning behind every item, a sheen across every card now and then, a price you can pay breathing; all of them made
# afresh with every redraw (never piling up), and moved by the one frame loop that turns the gleams.
for needle, why in (
    ('rays.Name = "Rays"', "no sunburst behind the items"),
    ("table.insert(shop.rays, rays)", "the sunbursts never turn"),
    ('sheen.Name = "Sheen"', "no sheen across the cards"),
    ("sheen.grad.Offset = Vector2.new(if p < 1 then -1 + 2 * p else -2, 0)", "the sheens never sweep"),
    ("if not item.soon and tokens() >= item.price then", "a price you can pay does not say so"),
    ("table.clear(shop.rays)\n\ttable.clear(shop.sheens)\n\ttable.clear(shop.breathe)", "the old tiles' animations pile up"),
):
    if needle not in (SHOP or ""):
        fail("ShopService: " + why)
if "Best value" in CATALOG:
    fail("ShopCatalog names the best value itself; the shop works it out from the packs' tokens and Robux")
# THE ROOM, MEASURED: the widest tab chosen grows by half its lift each side, plus its outline; it must stay inside the
# strip's room and short of its neighbour's outline. Likewise a lifted tile, with the gleam's thicker outline, inside the
# grid's room.
def numbers(pattern, text, what):
    m = re.search(pattern, text)
    if not m:
        fail("ShopService: this check can no longer read %s" % what)
        return None
    return [float(g) for g in m.groups()]


room = numbers(r"local TAB_ROOM, TAB_LIP = (\d+), (\d+)", SHOP, "TAB_ROOM")
tile_room = numbers(r"local TILE_ROOM, TILE_LIP = (\d+), (\d+)", SHOP, "TILE_ROOM")
lifts = numbers(r"then (\d\.\d+) elseif part\.hovered then (\d\.\d+) else 1", SHOP, "the tabs' lifts")
tab_line = numbers(r"local edge = stroke\(top, fam\.edge, ([\d.]+)\)", build_fn, "the tabs' outline")
gap = numbers(r"tabRow\.Padding = UDim\.new\(0, (\d+)\)", build_fn, "the gap between tabs")
scale_top = numbers(r"local t = math\.clamp\(math\.min\(view\.X, view\.Y\) / 720, ([\d.]+), ([\d.]+)\)", SHOP, "the text scale")
if room and tile_room and lifts and tab_line and gap and scale_top:
    t_max = scale_top[1]
    tabs_h = max(44, int(46 * t_max))
    disc = int((tabs_h - room[1]) * 0.62)
    widest = max(len(tab) for tab in tabs) * 0.6 * int(17 * t_max) + 10 + disc + 8 + 18
    grow = (lifts[0] - 1) / 2
    if grow * widest + tab_line[0] > room[0]:
        fail("ShopService: the widest tab chosen (%d pixels) reaches %.1f pixels past its edge, beyond the strip's room of %d"
             % (widest, grow * widest + tab_line[0], room[0]))
    if grow * tabs_h + tab_line[0] > room[0]:
        fail("ShopService: a chosen tab's top is cut off along the strip")
    if grow * widest + 2 * tab_line[0] >= gap[0]:
        fail("ShopService: a chosen tab grows into its neighbour's outline")
    cell_w = ((960 - 36) - 16 - 2 * tile_room[0] - int(12 * t_max) * 3) / 4
    cell_h = min(300, cell_w * 1.2) + tile_room[1]
    if 0.015 * cell_w + 4 > tile_room[0]:
        fail("ShopService: a lifted tile's outline is cut off at the grid's sides")
    if 0.015 * cell_h + 4 + 2 > tile_room[0] + 3:
        fail("ShopService: a lifted tile's outline is cut off along the grid's top")
# THE COLOURS, MEASURED: every tab's deep shades are its own hue (from HSV, not a mix toward grey), and the words on its
# tiles and keys can be read: the name on the pale wash, the description, a key's words, the chosen key's white words.
for needle in ("edge = Color3.fromHSV(h, math.min(1, s * 1.25 + 0.15), v * 0.42)",
               "ink = Color3.fromHSV(h, math.min(1, s + 0.2), v * 0.26)", "pale = own:Lerp(LOOK.white, 0.72)",
               "ShopLook.TAB_COLOURS[tab]"):
    if needle not in family_fn:
        fail("ShopService: a tab's colours are not worked out from its own (%s)" % needle)
import colorsys


def luminance(c):
    def channel(v):
        v /= 255
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    return 0.2126 * channel(c[0]) + 0.7152 * channel(c[1]) + 0.0722 * channel(c[2])


def contrast(a, b):
    hi, lo = sorted((luminance(a), luminance(b)), reverse=True)
    return (hi + 0.05) / (lo + 0.05)


for m in re.finditer(r"(\w+) = rgb\((\d+), (\d+), (\d+)\)", colours.group(1) if colours else ""):
    tab, own = m.group(1), tuple(int(v) for v in m.group(2, 3, 4))
    h, s, v = colorsys.rgb_to_hsv(*(x / 255 for x in own))
    edge = tuple(x * 255 for x in colorsys.hsv_to_rgb(h, min(1, s * 1.25 + 0.15), v * 0.42))
    ink = tuple(x * 255 for x in colorsys.hsv_to_rgb(h, min(1, s + 0.2), v * 0.26))
    pale = tuple(x + (255 - x) * 0.72 for x in own)
    for what, a, b, least in (("name on its tiles' wash", ink, pale, 7), ("descriptions", edge, pale, 4.5),
                              ("key's words", ink, own, 4.5), ("chosen key's white words", (255, 255, 255), edge, 4.5)):
        if contrast(a, b) < least:
            fail("ShopService: the %s tab's %s are hard to read (contrast %.1f, under %s)" % (tab, what, contrast(a, b), least))

started = re.search(r"CLIENT_MODULES = \{(.*?)\}", BOOT, re.S)
if not started or '"ShopLook"' not in started.group(1):
    fail("Bootstrap: ShopLook is not among the client's modules")

if problems:
    for problem in problems:
        print("FAIL: " + problem)
    sys.exit(1)
print("shop: %d items in %d tabs, priced once, nothing dupable (locked saves, receipts granted once and "
      "saved first, runs paid once and only when watched), inside the safe area with thumb-sized buttons "
      "and a controller's way round, and wired from the kiosk and the pause menu; the first five minutes: a "
      "welcome once, a lobby guide to real pads, a hint for every one of %d materials, the way to the shop."
      % (len(items), len(tabs), len(hints)))
