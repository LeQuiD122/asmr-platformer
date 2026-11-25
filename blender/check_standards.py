"""What a good Roblox game does that this one did not (the hundred-and-fifty-ninth pass onward).

Run with plain Python from the project root:  python blender/check_standards.py

What it holds:
  THE ARRIVAL (159). From the first frame you join, the game's own black and the bay's name (ReplicatedFirst/Arrival),
  over everything, Roblox's own screen taken away only once it is up; it waits for the game to load, for you, for the
  ground under you and for the first things to fetch, each for so long at the most, and is gone at the latest a few
  seconds after the game has loaded; the welcome waits for it, and so does everything that waits for the black. (Its
  faces and colours are Style's: check_style.py. The paste check looks for it: check_hub.py.)
  THE REAL PRICE (160). Every Robux price shown is the one Roblox gives you, asked once on your screen
  (ShopCatalog.robuxFor), the catalogue's only until Roblox has said; the best value reckoned from them; a pass Roblox
  has off sale not offered; the second chance the same; and the paste check asks Roblox about every id set.
  CHAT IN THE GAME'S LOOK (161). The bubbles over heads are the story's bubble (Style.BUBBLE), the chat window and the
  bar you type in the game's panel and ink in its faces, each property guarded.
  LESS MOTION WHEN ASKED (162). Roblox's Reduce Motion (Style.lessMotion): a scene's jolt, lens punch, swimming
  picture and speed lines kept small, its impacts with no flash and no black and white; the slime's launch widening a
  third; the keypad's burst a fifth.
  WHERE A RUN IS LEFT (163). Each run a funnel of its level's in five steps meaning the same on every length, each
  logged once, in order, the finish only by finishing.

Exits non-zero on any failure.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "src"
problems = []


def fail(message):
    problems.append(message)


def read(*parts):
    path = SRC.joinpath(*parts)
    return path.read_text(encoding="utf-8").replace("\r\n", "\n") if path.exists() else ""


def within(text, start, end="\nend\n"):
    """The text from `start` to the first `end` after it ("" if `start` is not there)."""
    at = text.find(start)
    if at < 0:
        return ""
    stop = text.find(end, at)
    return text[at:] if stop < 0 else text[at:stop + len(end)]


def in_order(text, *needles):
    """True if every needle is in `text`, each after the one before."""
    at = 0
    for needle in needles:
        found = text.find(needle, at)
        if found < 0:
            return False
        at = found + len(needle)
    return True


ARRIVAL = read("ReplicatedFirst", "Arrival.client.lua")
ONBOARDING = read("Client", "Services", "OnboardingService.lua")
UI = read("Client", "Services", "UIService.lua")
CATALOG = read("Shared", "ShopCatalog.lua")
SHOP = read("Client", "Services", "ShopService.lua")
DEATH = read("Client", "Services", "DeathService.lua")
BOOT = read("Server", "Bootstrap.server.lua")
STYLE = read("Shared", "Style.lua")
CINEMA = read("Client", "Services", "Cinema.lua")
CLIENT_BOOT = read("Client", "Bootstrap.client.lua")
RENDERER = read("Client", "Services", "DeformationRenderer.lua")
PASTE_LIST = (ROOT / "tools" / "paste_list.py").read_text(encoding="utf-8") if (ROOT / "tools" / "paste_list.py").exists() else ""

# ===================================================================== the arrival (159)
if not ARRIVAL:
    fail("src/ReplicatedFirst/Arrival.client.lua is missing: you join on Roblox's screen and the lobby arriving round you")
else:
    if ARRIVAL.split("\n")[1:2] != ["-- ReplicatedFirst/Arrival.client.lua"]:
        fail("Arrival: its second line does not say where it goes (ReplicatedFirst), so the paste list cannot")
    for needle, why in (
        ('me:SetAttribute("Arriving", true)', "never says it is up, so nothing waits for it"),
        ("gui.IgnoreGuiInset = true", "leaves a strip of the world showing under Roblox's bar"),
        ("gui.ResetOnSpawn = false", "is taken away by your character arriving"),
        ("\tif not game:IsLoaded() then\n\t\tgame.Loaded:Wait()\n\tend\n\treached(0.25)", "does not wait for the game to load"),
        ("if root.Parent and workspace:Raycast(root.Position, Vector3.new(0, -24, 0), below) then\n\t\t\t\tbreak",
         "does not wait for the ground under you"),
        ("while not gone and os.clock() < untilAt and ContentProvider.RequestQueueSize > 0 do",
         "does not wait for the first things to fetch (or waits for them without end)"),
        ("\tif gone then\n\t\treturn\n\tend\n\tgone = true", "can go twice"),
    ):
        if needle not in ARRIVAL:
            fail("Arrival " + why)
    taken = ARRIVAL.find("ReplicatedFirst:RemoveDefaultLoadingScreen()")
    if ARRIVAL.count("RemoveDefaultLoadingScreen") != 1 or taken < ARRIVAL.find('gui.Parent = me:WaitForChild("PlayerGui")') \
            or 'gui.Parent = me:WaitForChild("PlayerGui")' not in ARRIVAL:
        fail("Arrival: Roblox's screen is taken away before the black is up, so a half-built world shows between them")
    if not in_order(ARRIVAL, "game.Loaded:Wait()", "task.delay(ARRIVE.most, arrive)"):
        fail("Arrival: nothing sends it away in the end, or it is timed from before the game has loaded")
    gone_at = within(ARRIVAL, "local function arrive()")
    if 'me:SetAttribute("Arriving", nil)' not in gone_at or "gui:Destroy()" not in gone_at:
        fail("Arrival: it never lets go (Arriving left set, or its screen left behind)")
    most = re.search(r"most = if RunService:IsStudio\(\) then ([\d.]+) else ([\d.]+),", ARRIVAL)
    least = re.search(r"\tleast = ([\d.]+),", ARRIVAL)
    if not most or float(most.group(2)) > 15 or float(most.group(1)) > 6:
        fail("Arrival: it can be up for more than 15 seconds after the game has loaded (6 in Studio)")
    if not least or float(least.group(1)) < 0.8:
        fail("Arrival: the card can flicker past (under 0.8 seconds)")
    for name in re.findall(r':WaitForChild\("(\w+)"\)', ARRIVAL):
        if name != "PlayerGui":
            fail("Arrival waits for %s without end" % name)
    order = re.search(r"gui\.DisplayOrder = (\d+)", ARRIVAL)
    highest = max((int(n) for path in (SRC / "Client").rglob("*.lua")
                   for n in re.findall(r"DisplayOrder = (\d+)", path.read_text(encoding="utf-8"))), default=0)
    if not order or int(order.group(1)) <= highest:
        fail("Arrival: its black is not over every other screen (DisplayOrder %s, another is %d)"
             % (order.group(1) if order else "none", highest))
if "afterArrival(showWelcome)" not in ONBOARDING or "task.delay(1.5, showWelcome)" in ONBOARDING:
    fail("OnboardingService: the welcome comes up under the join card")
waits = within(ONBOARDING, "local function afterArrival(")
cap = re.search(r"local ARRIVAL_MOST = (\d+)", ONBOARDING)
if 'while me:GetAttribute("Arriving") == true and os.clock() < untilAt do' not in waits or not cap or int(cap.group(1)) > 30:
    fail("OnboardingService: the welcome waits for the join card without end, or not at all")
if 'or player:GetAttribute("Arriving") == true' not in within(UI, "function UIService.isBlack(): boolean"):
    fail("UIService: what waits for the black (a notice, the tokens a run paid) comes up under the join card")
if '("ReplicatedFirst", "First to load (ReplicatedFirst)")' not in PASTE_LIST:
    fail("tools/paste_list.py: what goes in ReplicatedFirst is listed under Other")

# ===================================================================== the real price (160)
for needle, why in (
    ("return if known and known.robux then known.robux else item.robux", "does not show the price Roblox gave"),
    ("return not (known and not known.onSale)", "calls something off sale that Roblox has not said is"),
    ("MarketplaceService:GetProductInfo(id, if isPass then Enum.InfoType.GamePass else Enum.InfoType.Product)",
     "asks Roblox about an id as the wrong kind of thing"),
    ("if item.robux and type(id) == \"number\" and id ~= 0 then", "asks Roblox about items with no id"),
    ("said[item.id] = { robux = robux, onSale = robux ~= nil and (info :: any).IsForSale ~= false }",
     "takes an answer with no price, or a pass off sale, as on sale"),
    ('if asked == "answered" then\n\t\tif answered then\n\t\t\ttask.spawn(answered)', "never answers someone who asks late"),
    ('asked = "answered"\n\t\tfor _, fn in ipairs(whenSaid) do', "never says when Roblox has answered"),
):
    if needle not in CATALOG:
        fail("ShopCatalog " + why)
asked_at = within(CATALOG, "function ShopCatalog.askPrices(")
if "pcall(function()" not in asked_at or "task.spawn(function()" not in asked_at:
    fail("ShopCatalog: asking Roblox the prices is unguarded, or holds up whoever asks")
for needle, why in (
    ("ShopCatalog.askPrices(function()\n\t\tif shop.open then\n\t\t\trender()", "never asks Roblox the prices, or never draws them"),
    ('or not ShopCatalog.onSale(item) then\n\t\t\ttoast(item.name .. " is not on sale yet.")', "offers what Roblox has off sale"),
    ('elseif not ShopCatalog.onSale(item) then\n\t\t\tfill, edge, ink, words = LOOK.soon, LOOK.soonEdge, LOOK.soonInk, "Not on sale"',
     "shows a price for what Roblox has off sale"),
):
    if needle not in SHOP:
        fail("ShopService " + why)
if SHOP.count('"R$ " .. tostring(ShopCatalog.robuxFor(item))') != 2 or "tostring(item.robux)" in SHOP:
    fail("ShopService: a price is drawn from the catalogue's number, not Roblox's")
if "local robux = ShopCatalog.robuxFor(item)" not in within(SHOP, "local function bestPack(): string?"):
    fail("ShopService: the best value is reckoned from the catalogue's prices, not Roblox's")
for needle, why in (
    ('("Second chance  R$ %d"):format(chancePrice(item))', "shows the catalogue's price"),
    ("if productId ~= 0 and chanceOnSale(item) and not chance.buying then", "is offered off sale"),
    ("elseif productId ~= 0 and item and chanceOnSale(item) then", "shows a price off sale"),
    ("return ShopCatalog.robuxFor(item) or 0", "does not show Roblox's price"),
):
    if needle not in DEATH:
        fail("DeathService: the second chance " + why)
for path in (SRC / "Client").rglob("*.lua"):
    text = path.read_text(encoding="utf-8")
    if re.search(r"tostring\(item\.robux\)|format\(item\.robux|format\([^)]*item\.robux or 0\)", text):
        fail("%s draws a Robux price from the catalogue's number" % path.name)
if not in_order(BOOT, "elseif isPass and (info :: any).IsForSale == false then", "elseif price and price ~= item.robux then") \
        or "warn((\"PASTE CHECK: Roblox does not know %s's %s %d as a %s of this game" not in BOOT:
    fail("Bootstrap: the paste check does not ask Roblox about the ids set (a wrong one found by a player pressing Buy)")

# ===================================================================== chat in the game's look (161)
bubbles = within(UI, 'local bubbles = set("BubbleChatConfiguration", {', "\n\t})")
window = within(UI, 'set("ChatWindowConfiguration", {', "\n\t})")
bar = within(UI, 'set("ChatInputBarConfiguration", {', "\n\t})")
for block, name, needles in (
    (bubbles, "the bubbles over heads", ("BackgroundColor3 = Style.BUBBLE.fill", "TextColor3 = Style.BUBBLE.ink",
                                          "FontFace = Style.BUBBLE.font")),
    (window, "the chat window", ("BackgroundColor3 = Style.COLOUR.panel", "TextColor3 = Style.COLOUR.ink",
                                 "FontFace = Style.FONT.body")),
    (bar, "the bar you type in", ("BackgroundColor3 = Style.COLOUR.panelRaised", "TextColor3 = Style.COLOUR.ink",
                                  "PlaceholderColor3 = Style.COLOUR.inkMuted", "FontFace = Style.FONT.body")),
):
    for needle in needles:
        if needle not in block:
            fail("UIService: %s are not in the game's look (%s)" % (name, needle))
if "corner.CornerRadius = Style.BUBBLE.radius" not in UI:
    fail("UIService: the chat bubbles keep Roblox's corners, not the story bubble's")
if "local config = chat:WaitForChild(name, 10)" not in UI or \
        "pcall(function()\n\t\t\t\t(config :: any)[key] = value\n\t\t\tend)" not in UI:
    fail("UIService: the chat's look is set unguarded, or waited for without end")

# ===================================================================== less motion when asked (162)
calm_reader = within(STYLE, "function Style.lessMotion(): boolean")
if 'return game:GetService("GuiService").ReducedMotionEnabled' not in calm_reader or "pcall(function()" not in calm_reader \
        or "return ok and on == true" not in calm_reader:
    fail("Style: Roblox's Reduce Motion is not read (or read unguarded)")
calm = re.search(r"local CALM = \{ shake = ([\d.]+), kick = ([\d.]+), waver = ([\d.]+), lines = ([\d.]+) \}", CINEMA)
if not calm or any(float(v) > 0.5 for v in calm.groups()):
    fail("Cinema: with less motion asked for, a scene still moves more than half as much")
for needle, why in (
    ("current.shake = math.max(current.shake, amount * (if Style.lessMotion() then CALM.shake else 1))", "the jolt"),
    ("current.waver = math.clamp(amount, 0, 1) * (if Style.lessMotion() then CALM.waver else 1)", "the picture swimming"),
    ("current.lineAmount = math.clamp(amount, 0, 1) * (if Style.lessMotion() then CALM.lines else 1)", "the speed lines"),
):
    if needle not in CINEMA:
        fail("Cinema: %s is as big with less motion asked for" % why)
impact = within(CINEMA, "function Cinema.impact(strength: number?, dark: boolean?)")
if not in_order(impact, "if Style.lessMotion() then", "current.kick = math.max(current.kick, 9 * s * CALM.kick)",
                "current.shake = math.max(current.shake, 1.2 * s * CALM.shake)", "return\n\tend",
                "current.burst = math.max(current.burst, math.min(1, 0.9 * s))",
                "current.flash.BackgroundTransparency = if dark then 0.6 else 0.55"):
    fail("Cinema: an impact still flashes, or turns black and white, with less motion asked for")
if "{ FieldOfView = base + (if calm then 3 else 9) }" not in CLIENT_BOOT \
        or 'calm = game:GetService("GuiService").ReducedMotionEnabled == true' not in CLIENT_BOOT:
    fail("Bootstrap (client): the slime's launch widens the picture as much with less motion asked for")
if 'return game:GetService("GuiService").ReducedMotionEnabled\n\t\t\tor UserSettings()' not in CLIENT_BOOT:
    fail("Bootstrap (client): a level finished celebrates as loudly with Roblox's Reduce Motion on")
for path in (SRC / "Client").rglob("*.lua"):
    text = path.read_text(encoding="utf-8")
    for m in re.finditer(r"\.CameraOffset = Vector3\.new\(math\.random\(\)", text):
        if "ReducedMotionEnabled" not in text[max(0, m.start() - 900):m.start()]:
            fail("%s shakes the camera as much with less motion asked for" % path.name)
if not re.search(r'ReducedMotionEnabled == true then\n\t+strength \*= 0\.2', RENDERER):
    fail("DeformationRenderer: the keypad's burst shakes the camera as much with less motion asked for")

# ===================================================================== where a run is left (163)
steps = re.search(r"local RUN_STEPS = \{ (.*) \}", BOOT)
named = re.findall(r'"([^"]+)"', steps.group(1)) if steps else []
if len(named) != 5 or named[0] != "Started" or named[-1] != "Finished":
    fail("Bootstrap: a run's funnel is not five steps from Started to Finished")
step_to = within(BOOT, "local function funnelTo(player: Player, step: number)")
for needle, why in (
    ("if not funnel or step <= funnel.step then\n\t\treturn\n\tend", "logs a step twice, or out of a run"),
    ("for at = funnel.step + 1, math.min(step, #RUN_STEPS) do", "skips the steps before"),
    ("AnalyticsService:LogFunnelStepEvent(player, funnel.name, funnel.session, at, RUN_STEPS[at])", "logs nothing"),
    ("funnel.step = step", "forgets how far the run has got"),
    ("pcall(function()", "can stop a run when Roblox does not answer"),
):
    if needle not in step_to:
        fail("Bootstrap: a run's funnel " + why)
if "funnelTo(player, math.min(#RUN_STEPS - 1, 1 + math.floor(4 * index / total)))" not in BOOT \
        or "\tif total > 1 then\n" not in within(BOOT, "local function runReached("):
    fail("Bootstrap: a checkpoint logs the finish, or a step that does not mean the same on every length")
started = within(BOOT, "local function progression(player: Player, status: string)")
if not in_order(started, 'if status == "start" then\n\t\tfunnelFor[player] = {',
                'session = game:GetService("HttpService"):GenerateGUID(false)', "funnelTo(player, 1)",
                'elseif status == "complete" then\n\t\tfunnelTo(player, #RUN_STEPS)\n\t\tfunnelFor[player] = nil',
                "else\n\t\tfunnelFor[player] = nil"):
    fail("Bootstrap: a run's funnel is not begun anew each run, finished by finishing, and let go of when left")
if not in_order(BOOT, "local chunkCount = #levelInstance.placedChunks\n\tfor _, entry in ipairs(levelInstance.placedChunks) do",
                "if reached and entry.index > (reached.furthest or 0) then",
                "runReached(player, entry.index, chunkCount)"):
    fail("Bootstrap: a checkpoint reached never says how far into the run it is (or reads the level as it goes)")

if problems:
    for problem in problems:
        print("FAIL: " + problem)
    sys.exit(1)
print("standards: you join on the game's own black with the bay's name, gone once the place is in (a few seconds at the "
      "most after loading), the welcome after it; every Robux price the one Roblox gives you, nothing off sale offered, "
      "every id set asked of Roblox in Studio; chat in the story bubble's look; Roblox's Reduce Motion kept by every shake, "
      "punch, flash and launch; each run a funnel of its level's in five steps, each logged once, in order.")
