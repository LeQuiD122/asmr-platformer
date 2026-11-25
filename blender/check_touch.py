"""What the game's surfaces do to the touch (the hundred-and-sixty-fourth pass onward).

Run with plain Python from the project root:  python blender/check_touch.py

What it holds:
  FELT IN YOUR HANDS (164). Every material has a shape it is felt in (Haptics.UNDERFOOT), every shape starts at once,
  runs forward, stays between nothing and full and ends at nothing within half a second (nothing left buzzing); every
  call to Roblox's haptics guarded, nothing on a server, a controller's motors let go after; your own steps felt only
  once their sound is certain and never anyone else's, one a footfall, a phone's lighter; a scene's impacts and jolts,
  a checkpoint, the slime's fling and every menu press felt; a hard landing felt and an ordinary jump not; each of
  them asked of Haptics beside its caller, never waited for.
  THE TELEPRINTER (165). Every creamy keyboard carries Y, E and S (so YES can be typed on any of them); the key typed is
  the one under your middle with your weight on it (an R6 body's too), once a press, only on a creamy keyboard; well
  into a key before it counts, so the line between two keys types neither, and yet the middle of every key longer than
  a walk across the board covers between two looks, so a row walked types every key of it; YES answers it, paid from
  the save (once: check_shop.py) and said on your strip and on the tokens' pill; its message the keepsake's own, printed
  until you have answered it; nothing waited for without end; the test panel can make it unanswered again.
  AN R6 BODY STANDS ON ITS LEGS (165). HipHeight is 0 on R6, so every reading of it says on the same line what an R6
  body's legs are (2 studs): the teleprinter, the footing and the trails' feet (the townsfolk, made R15, excepted).

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


HAPTICS = read("Client", "Services", "Haptics.lua")
AUDIO = read("Client", "Services", "AudioService.lua")
CINEMA = read("Client", "Services", "Cinema.lua")
RUN_FEEL = read("Client", "Services", "RunFeel.lua")
CLIENT_BOOT = read("Client", "Bootstrap.client.lua")
MATERIALS = read("Shared", "MaterialConfig.lua")
BUILDER = read("Server", "ChunkBuilder.server.lua")
CHUNKS = read("Shared", "ChunkDefinitions.lua")
GRID = read("Shared", "SubRegionGrid.lua")
DEFORM = read("Server", "Services", "DeformationService.lua")
BOOT = read("Server", "Bootstrap.server.lua")
ECONOMY = read("Server", "Services", "EconomyService.lua")
CATALOG = read("Shared", "ShopCatalog.lua")
KEEPSAKES = read("Shared", "Keepsakes.lua")
TELE = read("Client", "Services", "Teleprinter.lua")
SHOP = read("Client", "Services", "ShopService.lua")
DEV_PANEL = read("Client", "Services", "DevPanelClient.lua")
COSMETICS = read("Client", "Services", "CosmeticsClient.lua")

material_block = within(MATERIALS, "local Materials: { [string]: MaterialDef } = {", "\n}\n")
material_names = set(re.findall(r"^\t([A-Z]\w+) = \{$", material_block, re.M))
if len(material_names) < 20:
    fail("MaterialConfig: its materials could not be read (%d found)" % len(material_names))

# ===================================================================== felt in your hands (164)
if not HAPTICS:
    fail("src/Client/Services/Haptics.lua is missing: nothing in the game is felt")
else:
    if HAPTICS.split("\n")[1:2] != ["-- StarterPlayerScripts/Services/Haptics.lua"]:
        fail("Haptics: its second line does not say where it goes")
    shapes = {}
    for name, keys, heavy in re.findall(r"^\t(\w+) = \{ keys = \{ (.*) \}, heavy = (true|false) \},$", HAPTICS, re.M):
        shapes[name] = [(float(t), float(v)) for t, v in re.findall(r"\{ ([\d.]+), ([\d.]+) \}", keys)]
    if len(shapes) < 12:
        fail("Haptics: its shapes could not be read (%d found)" % len(shapes))
    for name, keys in sorted(shapes.items()):
        times = [t for t, _ in keys]
        values = [v for _, v in keys]
        if len(keys) < 2 or times[0] != 0 or any(b <= a for a, b in zip(times, times[1:])):
            fail("Haptics: %s does not start at once and run forward" % name)
        elif any(v < 0 or v > 1 for v in values) or values[-1] != 0 or times[-1] > 500 or max(values) <= 0:
            fail("Haptics: %s is felt at nothing, over full, for over half a second, or does not end at nothing" % name)
    underfoot = dict(re.findall(r'(\w+) = "(\w+)"', within(HAPTICS, "local UNDERFOOT: { [string]: string } = {", "\n}\n")))
    for material in sorted(material_names):
        if material not in underfoot:
            fail("Haptics: %s is not felt in a shape of its own (UNDERFOOT)" % material)
    for material, shape in sorted(underfoot.items()):
        if shape not in shapes:
            fail("Haptics: %s is felt as %s, which is not a shape" % (material, shape))
        if material_names and material not in material_names:
            fail("Haptics: UNDERFOOT names %s, which is not a material" % material)
    played = within(HAPTICS, "local function play(name: string, scale: number?)")
    if "if not RunService:IsClient() then\n\t\treturn\n\tend" not in played:
        fail("Haptics: it plays on a server")
    for needle, why in (
        ('local ok, made = pcall(function()\n\t\t\tlocal new = (Instance.new :: any)("HapticEffect")',
         "a HapticEffect is made unguarded (a client without them stops)"),
        ("new.Type = Enum.HapticEffectType.Custom", "its own shapes are not Custom waveforms"),
        ("local ok = pcall(function()\n\t\t\t(effect :: any):SetWaveformKeys(keysFor(shape, scale))",
         "a shape's waveform is written unguarded"),
        ("pcall(function()\n\t\t\t(effect :: any):Play()\n\t\tend)", "an effect is played unguarded"),
        ("if motorTurn[motor] == turn then\n\t\t\tpcall(function()\n\t\t\t\tHapticService:SetMotor(PAD, motor, 0)",
         "a controller's motor is never let go"),
        ("if not HapticService:IsVibrationSupported(PAD) then", "a controller with no motors is asked to buzz"),
        ('if soon("underfoot") then\n\t\treturn\n\tend', "two materials under you at once are felt twice"),
        ("if onPhone() then\n\t\tscale *= PHONE.underfoot", "a phone feels its steps as hard as a controller"),
        ('if amount < JOLT_LEAST or soon("jolt") then', "every small jolt of a scene is felt"),
        ("elseif now == Enum.HumanoidStateType.Landed then\n\t\t\tstopFalling()", "the fall is watched after a landing"),
        ("humanoid.Destroying:Once(stopFalling)", "the fall is watched after the character has gone"),
        ("if fastest >= LANDING.from then", "every landing is felt as a hard one"),
        ('new.Type = Enum.HapticEffectType.UIClick', "a press is not Roblox's own click"),
    ):
        if needle not in HAPTICS:
            fail("Haptics: " + why)
    gap = re.search(r"local GAP = \{ underfoot = ([\d.]+), press = ([\d.]+), jolt = ([\d.]+) \}", HAPTICS)
    if not gap or float(gap.group(1)) < 0.05:
        fail("Haptics: your steps can be felt more than twenty times a second")
    phone = re.search(r"local PHONE = \{ underfoot = ([\d.]+) \}", HAPTICS)
    if not phone or float(phone.group(1)) >= 1:
        fail("Haptics: a phone feels its steps as hard as a controller")
    landing = re.search(r"local LANDING = \{ from = ([\d.]+), full = ([\d.]+) \}", HAPTICS)
    if not landing or float(landing.group(1)) <= 55 or float(landing.group(2)) <= float(landing.group(1)):
        fail("Haptics: an ordinary jump's landing (about 53 studs a second) is felt as a hard one")

playing = within(AUDIO, "function AudioService.playSfx(")
if not in_order(playing, "local soundId = pickSoundId(event)\n\tif not soundId then\n\t\treturn\n\tend",
                "\tif mine then\n\t\tlocal hands = felt()\n\t\tif hands then\n\t\t\tpcall(hands.step, material, asked, gain)",
                "local playing = activeSounds[material]"):
    fail("AudioService: a step is felt before its sound is certain, or someone else's is felt")
if "pcall(hands.press, kind)" not in within(AUDIO, "function AudioService.press("):
    fail("AudioService: a press in a menu is not felt")
asking = within(AUDIO, "local function felt(): any")
if 'script.Parent:FindFirstChild("Haptics")' not in asking or "haptics = false" not in asking:
    fail("AudioService: Haptics is waited for, or looked for on every sound")
impact = within(CINEMA, "function Cinema.impact(strength: number?, dark: boolean?)")
if not in_order(impact, "if not current then\n\t\treturn\n\tend", "inHands(function(haptics)\n\t\thaptics.impact(s)",
                "if Style.lessMotion() then"):
    fail("Cinema: a scene's impact is not felt (or felt with less motion asked for only, or out of a scene)")
if "\t\tinHands(function(haptics)\n\t\t\thaptics.jolt(amount)" not in within(CINEMA, "function Cinema.shake(amount: number)"):
    fail("Cinema: a scene's jolt is not felt")
if 'local found = script.Parent and script.Parent:FindFirstChild("Haptics")' not in within(CINEMA, "local function inHands("):
    fail("Cinema: Haptics is waited for")
if not in_order(within(RUN_FEEL, "local function reached()"), "chime()", 'local haptics = beside("Haptics")',
                "pcall(haptics.checkpoint)"):
    fail("RunFeel: a checkpoint reached is not felt")
if "(require(haptics) :: any).launch(launchVelocity)" not in within(CLIENT_BOOT, "SlimeLaunch.OnClientEvent:Connect(", "\nend)\n"):
    fail("Bootstrap (client): the slime's fling is not felt")
if '"Haptics", "Teleprinter", "RunFeel", "StalkerClient" }) do' not in CLIENT_BOOT:
    fail("Bootstrap (client): Haptics or the Teleprinter is never started")

# ===================================================================== the teleprinter (165)
answer = re.search(r'\tanswer = "([A-Z]+)",', DEFORM)
answer = answer.group(1) if answer else ""
if not answer:
    fail("DeformationService: the teleprinter has no answer")
rows = re.search(r"local KEY_ROWS = \{ (.*) \}", BUILDER)
key_from = re.search(r"local KEY_FROM = (\d+)", BUILDER)
cell = re.search(r"local CELL_SIZE_TARGET = ([\d.]+)", GRID)
clamp = re.search(r"local MIN_CELLS, MAX_CELLS = (\d+), (\d+)", GRID)
sizes = set()
if "local at = ((col - 2 + KEY_FROM) % #line) + 1" not in BUILDER \
        or "local line = KEY_ROWS[((row - 1) % #KEY_ROWS) + 1]" not in BUILDER or not (rows and key_from and cell and clamp):
    fail("ChunkBuilder: a key's letter is not read from its row as this check reads it")
else:
    lines = re.findall(r'"([^"]+)"', rows.group(1))
    for block in re.split(r"\nChunkDefinitions\.", CHUNKS):
        if "materials = { CreamyKeyboard = true }" in block:
            size = re.search(r"sizeX = (\d+), sizeZ = (\d+)", block)
            if size:
                sizes.add((int(size.group(1)), int(size.group(2))))
    if not sizes:
        fail("ChunkDefinitions: no creamy keyboard's size could be read")
    for size_x, size_z in sorted(sizes):
        cols = min(max(int(size_x / float(cell.group(1)) + 0.5), int(clamp.group(1))), int(clamp.group(2)))
        count_rows = min(max(int(size_z / float(cell.group(1)) + 0.5), int(clamp.group(1))), int(clamp.group(2)))
        letters = set()
        for row in range(1, count_rows + 1):
            line = lines[(row - 1) % len(lines)]
            for col in range(1, cols + 1):
                letters.add(line[(col - 2 + int(key_from.group(1))) % len(line)])
        missing = [c for c in answer if c not in letters]
        if missing:
            fail("ChunkBuilder: a %dx%d creamy keyboard has no %s on it, so its teleprinter can never be answered %s"
                 % (size_x, size_z, ", ".join(missing), answer))
typing = within(DEFORM, "local function typeUnder(platform: BasePart, state, player: Player, now: number)")
for needle, why in (
    ("local col, row = SubRegionGrid.getActiveRegion(root.Position, platform.CFrame, state.grid)",
     "types a key you are not standing in the middle of"),
    ("if root.Position.Y - top > legs + root.Size.Y / 2 + TYPING.above then\n\t\tmine.key = nil\n\t\treturn",
     "types a key you are in the air over (or never types a key pressed again)"),
    ("local legs = if humanoid.RigType == Enum.HumanoidRigType.R6 then TYPING.legsR6 else humanoid.HipHeight",
     "never types for an R6 body, whose HipHeight is 0"),
    ("if key == mine.key then\n\t\treturn\n\tend", "types a key over and over while you stand on it"),
    ("if math.abs(into.X) > half.X - TYPING.inside or math.abs(into.Z) > half.Z - TYPING.inside then\n\t\treturn\n\tend"
     "\n\tmine.key = key", "types the two keys you stand between in turn"),
    ("if string.sub(mine.line, -#TYPING.answer) == TYPING.answer then", "never hears the answer"),
    ("local ok, amount = pcall(answeredBy :: any, player)", "lets a failed save stop the typing"),
    ('teleprinterSay(player, "answered", paid)\n\t\t-- A new line after the answer', "never says it is answered"),
    ('mine.line = ""\n\tend\nend', "hears one YES as many"),
    ('teleprinterSay(player, "typed", letter, fresh)', "never tells your screen what you typed"),
):
    if needle not in typing:
        fail("DeformationService: the teleprinter " + why)
if not in_order(typing, "mine.at = now\n", "if root.Position.Y - top"):
    fail("DeformationService: the teleprinter forgets the line of someone standing still on a key")
if typing.count("mine.key = key") != 1 or not in_order(typing, "if root.Position.Y - top", "if key == mine.key then",
                                                     "local into = cell.part.CFrame:PointToObjectSpace(root.Position)",
                                                     "mine.key = key"):
    fail("DeformationService: the teleprinter takes a key as yours before you are well into it")
legs_r6 = re.search(r"\tlegsR6 = ([\d.]+),", DEFORM)
if not legs_r6 or float(legs_r6.group(1)) != 2:
    fail("DeformationService: the teleprinter stands an R6 body on legs that are not its own 2 studs")
# WELL INTO A KEY, AND YET NO KEY WALKED PAST. The band at each edge has to be wider than a standing body's jitter, and
# what is left in the middle of the smallest key longer than a walk across the board (its own pace) covers between two
# looks, or a row walked at an ordinary pace skips keys.
inside = re.search(r"\tinside = ([\d.]+),", DEFORM)
every = re.search(r"\tevery = ([\d.]+),", DEFORM)
gap = re.search(r"local TILE_GAP = ([\d.]+)", GRID)
walk = re.search(r"DEFAULT_WALKSPEED = (\d+)", MATERIALS)
pace = re.search(r"speedMultiplier = ([\d.]+)", within(material_block, "\tCreamyKeyboard = {", "\n\t},"))
if not (inside and every and gap and walk and pace and cell and clamp):
    fail("DeformationService: how far into a key it counts, or how often it looks, cannot be read")
else:
    if float(inside.group(1)) < 0.25:
        fail("DeformationService: the teleprinter counts a key the moment you touch its edge, so standing on the line "
             "between two keys types them in turn")
    stride = int(walk.group(1)) * float(pace.group(1)) * float(every.group(1))
    for size_x, size_z in sorted(sizes):
        cols = min(max(int(size_x / float(cell.group(1)) + 0.5), int(clamp.group(1))), int(clamp.group(2)))
        count_rows = min(max(int(size_z / float(cell.group(1)) + 0.5), int(clamp.group(1))), int(clamp.group(2)))
        width = min(size_x / cols, size_z / count_rows) - float(gap.group(1))
        if width - 2 * float(inside.group(1)) <= stride:
            fail("DeformationService: on a %dx%d creamy keyboard the middle of a key (%.2f studs) is no longer than a "
                 "walk covers between two looks (%.2f), so a row walked skips keys"
                 % (size_x, size_z, width - 2 * float(inside.group(1)), stride))
if 'if state.material == "CreamyKeyboard" and platform.Parent then' not in DEFORM:
    fail("DeformationService: the teleprinter types on something that is not a creamy keyboard")
if 'local remote = RemoteEvents:FindFirstChild("Teleprinter")' not in within(DEFORM, "local function teleprinterSay("):
    fail("DeformationService: the teleprinter's remote is waited for")
if "Players.PlayerRemoving:Connect(function(player: Player)\n\ttyping[player] = nil" not in DEFORM:
    fail("DeformationService: the teleprinter keeps the line of someone who has left")
forget = re.search(r"\tforget = (\d+),", DEFORM)
keep = re.search(r"\tkeep = (\d+),", DEFORM)
if not forget or int(forget.group(1)) < 5 or not keep or int(keep.group(1)) < len(answer):
    fail("DeformationService: the teleprinter forgets a line too soon, or keeps too little of it to hear the answer")
if 'ensureRemoteEvent(remoteEventsFolder, "Teleprinter")' not in BOOT:
    fail("Bootstrap: the teleprinter has no remote")
if "DeformationService.setAnswered(EconomyService.answeredTeleprinter)" not in BOOT:
    fail("Bootstrap: the teleprinter's answer is never paid")
for needle, why in (
    ("\tTeleprinter = false,\n}", "a save has no place to keep the teleprinter answered"),
    ('player:SetAttribute("Teleprinter", ready.Data.Teleprinter == true)', "a save loaded does not say it is answered"),
    ('player:SetAttribute("Teleprinter", true)', "the answer does not say it is answered"),
    ("earnedRemote:FireClient(player, amount, { teleprinter = true })", "the answer's tokens are not said"),
    ('elseif action == "teleprinter" then', "the test panel cannot make the teleprinter unanswered again"),
):
    if needle not in ECONOMY:
        fail("EconomyService: " + why)
reward = re.search(r"\tTELEPRINTER = (\d+),", CATALOG)
if not reward or not 0 < int(reward.group(1)) <= 150:
    fail("ShopCatalog: the teleprinter pays nothing, or more than a secret should (150)")
asked = re.search(r'local SAYS = \{ asked = "([A-Z ]+)", answered = "([A-Z ]+)" \}', TELE)
keepsake = within(KEEPSAKES, "\tCreamyKeyboard = {", "\n\t},")
if not asked or asked.group(1) not in keepsake:
    fail("Teleprinter: what it prints is not what the keepsake says it last typed")
if not TELE:
    fail("src/Client/Services/Teleprinter.lua is missing: the keyboards type nothing")
else:
    if TELE.split("\n")[1:2] != ["-- StarterPlayerScripts/Services/Teleprinter.lua"]:
        fail("Teleprinter: its second line does not say where it goes")
    for needle, why in (
        ('if me:GetAttribute("Teleprinter") ~= true then\n\t\t\ttable.insert(queue, { text = SAYS.asked, tap = true })',
         "prints its message for someone who has answered it"),
        ('if fresh == true then\n\t\t-- A new line: a fresh tape, and its message first, until you have answered it.\n\t\ttape = ""',
         "runs one line into the next"),
        ('local remotes = ReplicatedStorage:WaitForChild("RemoteEvents", 30)', "waits for the remotes without end"),
        ('local remote = remotes and remotes:WaitForChild("Teleprinter", 30)', "waits for its remote without end"),
        ("hideAfter(if confirmed then PRINT.answeredStays else PRINT.stays)", "never goes"),
        ('quietAnswer = not (type(paid) == "number" and paid > 0)', "sounds its answer twice with the tokens' pill"),
    ):
        if needle not in TELE:
            fail("Teleprinter: " + why)
keyboard_hint = re.search(r'^\tCreamyKeyboard = "([^"]*)"', read("Client", "Services", "OnboardingService.lua"), re.M)
if not keyboard_hint or "types its letter" not in keyboard_hint.group(1):
    fail("OnboardingService: the keyboard's first hint does not say a key types its letter")
if 'if info.teleprinter then\n\t\t\ttable.insert(reasons, "The teleprinter answered")' not in SHOP:
    fail("ShopService: the tokens' pill does not say the teleprinter paid them")
if '{ action = "teleprinter", text = "Teleprinter answered on/off" },' not in DEV_PANEL:
    fail("DevPanelClient: the test panel has no button for the teleprinter")

# ===================================================================== an R6 body stands on its legs (165)
# HipHeight is 0 on an R6 body; its 2-stud legs are what stand it up. Read alone, it puts an R6 body's feet a stud and
# more short of the ground: the teleprinter never typed for one, the footing never found the ground under one, and a
# trail hung a stud above its feet. So every reading says on its own line what an R6 body's legs are. The townsfolk are
# made R15 only, as long as they are.
R15_ONLY = {"Townsfolk.lua": "Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)"}
for path in sorted(SRC.rglob("*.lua")):
    text = path.read_text(encoding="utf-8").replace("\r\n", "\n")
    for number, line in enumerate(text.split("\n"), 1):
        code = line.split("--", 1)[0]
        if not re.search(r"\.HipHeight\b(?!\s*=[^=])", code):
            continue
        if path.name in R15_ONLY:
            if R15_ONLY[path.name] not in text:
                fail("%s:%d reads HipHeight, and its bodies are no longer made R15 only, so an R6 one stands on 0"
                     % (path.name, number))
        elif "Enum.HumanoidRigType.R6" not in code:
            fail("%s:%d reads HipHeight with no R6 body's legs beside it (HipHeight is 0 on R6)" % (path.name, number))
if ("local legs = if humanoid.RigType == Enum.HumanoidRigType.R6 then 2 else humanoid.HipHeight\n"
        "\tif root.Position.Y - hit.Position.Y > legs + root.Size.Y / 2 + 0.7 then") \
        not in within(RUN_FEEL, "local function groundUnder("):
    fail("RunFeel: the footing finds no ground under an R6 body (its HipHeight is 0, its legs 2 studs)")
if "local hip = if humanoid and humanoid.RigType ~= Enum.HumanoidRigType.R6 then humanoid.HipHeight else 2" \
        not in within(COSMETICS, "local function feetDrop("):
    fail("CosmeticsClient: a trail hangs a stud above an R6 body's feet")

# ===================================================================== the tape is a slip (203, 205, 208)
# Three notes, three shapes. 2026-11-06: the text "is hidden behind a beige overlay in the middle of the square with
# rounded edges instead of going to the very end and disappearing afterwards" (a box whose letters stopped dead at its
# left edge). 2026-11-07: "the line is too big" (a band across the whole screen). 2026-11-12: "too wide and takes a whole
# line of space on the screen which is not good and not aesthetic" (a thin line across the whole screen). So: a short
# slip in the middle, as wide as its print and no wider than a share of the screen; its letters, once it is full, running
# out through its left end and FADING on the way, never cut off dead; thin, small print, a little see-through.
tape_build = within(TELE, "local function build()")
for needle, why in (
    ("strip.Size = UDim2.new(0, STRIP.pad * 2, 0, STRIP.height)", "its tape is a line across the screen again, not a slip"),
    ("strip.ClipsDescendants = true", "its letters are drawn past the slip's end"),
    ("words.Size = UDim2.new(1, -STRIP.pad * 2, 1, 0)", "its letters do not run between the slip's margins"),
    ("words.TextXAlignment = Enum.TextXAlignment.Right", "its newest letter is not at the slip's right end"),
    ("NumberSequenceKeypoint.new(STRIP.fade, 0)", "its letters do not fade out as they reach the slip's end"),
):
    if needle not in tape_build:
        fail("Teleprinter: " + why)
tape_render = within(TELE, "local function render()")
for needle, why in (
    ("local most = math.min(STRIP.wide, (if camera then camera.ViewportSize.X else 800) * STRIP.share)",
     "the slip is not kept to a share of the screen"),
    ("strip.Size = UDim2.new(0, math.clamp(need, STRIP.pad * 2 + STRIP.type, most), 0, STRIP.height)",
     "the slip is not as wide as its print"),
    ("fading.Enabled = need > most", "a slip with room for every letter fades them anyway, or a full one cuts them off dead"),
):
    if needle not in tape_render:
        fail("Teleprinter: " + why)
shown = re.search(r"local PRINT = \{ pace = [\d.]+, shown = (\d+),", TELE)
strip = re.search(r"local STRIP = \{ height = (\d+), lift = \d+, wide = (\d+), share = ([\d.]+), pad = \d+, fade = ([\d.]+), "
                  r"type = (\d+), paper = ([\d.]+), round = \d+ \}", TELE)
if not shown or int(shown.group(1)) < 100:
    fail("Teleprinter: the tape keeps fewer letters than a slip shows, so they stop short of its end")
if not strip:
    fail("Teleprinter: this check can no longer read the slip's measurements")
else:
    if int(strip.group(2)) > 420 or float(strip.group(3)) > 0.7:
        fail("Teleprinter: the slip is a line across the screen again (wider than 420, or over seven tenths of a screen)")
    if int(strip.group(2)) < 280:
        fail("Teleprinter: the slip is too short for its own message (KEY HOLDER PLEASE CONFIRM needs about 270)")
    if not 0.1 <= float(strip.group(4)) <= 0.6:
        fail("Teleprinter: the fade at the slip's end is out of place")
    # A THIN TAPE (205): a narrow paper ribbon with small print, a little see-through.
    if int(strip.group(1)) > 28 or int(strip.group(5)) > 18 or not 0 < float(strip.group(6)) <= 0.5:
        fail("Teleprinter: the tape is a band across the game again (taller than 28, print over 18, or solid paper)")
for needle, why in (
    ("words.TextSize = STRIP.type", "the tape's print is not its own small size"),
    ("strip.BackgroundTransparency = STRIP.paper", "the tape's paper is solid again"),
):
    if needle not in TELE:
        fail("Teleprinter: " + why)

if problems:
    for problem in problems:
        print("FAIL: " + problem)
    sys.exit(1)
print("touch: every material felt underfoot in a shape of its own (%d shapes, each ending at nothing within half a "
      "second), your own steps only and once their sound is certain, a phone's lighter; a scene's impacts and jolts, a "
      "checkpoint, the slime's fling, a hard landing and every press felt; every creamy keyboard carries %s, the key under "
      "your middle typed once a press (an R6 body's too, never the line between two keys, no key of a row walked "
      "past), %s answering the teleprinter, paid once a save; every HipHeight read with an R6 body's legs beside it."
      % (len(shapes) if HAPTICS else 0, ", ".join(answer), answer))
