"""The chunks and the bodies (the hundred-and-fiftieth pass onward): how the materials and the characters feel.

Run with plain Python from the project root:  python blender/check_feel.py

What it holds:
  WHAT YOUR OUTPUT SAID, AND NO TRADE MARKS (150). Cinema loads anywhere: the server loads SunkenCityClient in Studio to
  see that it loads, and that loads Cinema, so nothing either does as it loads may reach for a LocalPlayer (there is
  none on the server). And nothing a player reads names another company's product: the bricks, the stress ball, the
  sculpting sand and the jelly are called that on the board, in the journal, on the signs, in the hints, in the shop
  and in the story's papers.

Exits non-zero on any failure.
"""
import math
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


def strings(text):
    """Every double-quoted string in Luau source, comments left out."""
    found = []
    for line in text.split("\n"):
        code = line
        # A comment starts at "--" outside a string.
        out, quoted, k = [], False, 0
        while k < len(code):
            ch = code[k]
            if ch == '"' and (k == 0 or code[k - 1] != "\\"):
                quoted = not quoted
            if not quoted and code.startswith("--", k):
                break
            out.append(ch)
            k += 1
        found.extend(re.findall(r'"((?:[^"\\]|\\.)*)"', "".join(out)))
    return found


CINEMA = read("Client", "Services", "Cinema.lua")
SUNKEN_CLIENT = read("Client", "Services", "SunkenCityClient.lua")
CATALOG = read("Shared", "ShopCatalog.lua")
ONBOARDING = read("Client", "Services", "OnboardingService.lua")
for name, text in (("Cinema", CINEMA), ("SunkenCityClient", SUNKEN_CLIENT), ("ShopCatalog", CATALOG),
                   ("OnboardingService", ONBOARDING)):
    if not text:
        fail("missing " + name)

# ===================================================================== what your Output said (150)

# The server's Studio check (SunkenCityService.studio.check) requires SunkenCityClient, which requires Cinema as it
# loads. Anything at the top of either that reaches for the LocalPlayer fails there.
for name, text in (("Cinema", CINEMA), ("SunkenCityClient", SUNKEN_CLIENT)):
    for number, line in enumerate(text.split("\n"), 1):
        if line[:1].strip() and not line.startswith("--") and re.search(r"LocalPlayer\s*[:.]", line):
            fail("%s:%d reaches for the LocalPlayer as it loads, and the server loads it too (in Studio, to check the "
                 "level's client): %s" % (name, number, line.strip()[:80]))
if not re.search(r"^local me = Players\.LocalPlayer\nif me then\n\tlocal wasIn = me:GetAttribute\(\"InLevel\"\)", CINEMA, re.M):
    fail("Cinema: the watch on InLevel (leaving a level ends a scene) is not kept to a client (if me then)")
if not in_order(CINEMA, "if me then\n\tme.CharacterAdded:Connect(function()", "if live then", "left()"):
    fail("Cinema: a new character no longer ends a scene, or it is not kept to a client")

# ===================================================================== no trade marks (150)

PLAIN = {"KineticSand": "Sculpting sand", "Lego": "Toy bricks", "JelloSoda": "Jelly", "Needoh": "Stress ball"}
for key, name in PLAIN.items():
    if not re.search(r'\{ key = "%s", name = "%s",' % (key, re.escape(name)), CATALOG):
        fail("ShopCatalog.MATERIALS: %s is not called %s" % (key, name))
MARKS = re.compile(r"(?i)\b(lego|needoh|nee ?doh|kinetic sand|jell-?o)\b")
# Every file a player reads words from. A string with a space in it, or one ending a sentence, is words; one without is
# a key, an id or a mesh name, which no player sees and a save depends on.
READ = (("Shared", "ShopCatalog.lua"), ("Shared", "Keepsakes.lua"), ("Shared", "Conversations.lua"),
        ("Shared", "LevelDefinitions.lua"), ("Client", "Services", "OnboardingService.lua"),
        ("Client", "Services", "ShopLook.lua"), ("Client", "Services", "ShopService.lua"),
        ("Client", "Services", "JournalService.lua"), ("Client", "Services", "StoryClient.lua"),
        ("Client", "Services", "UIService.lua"), ("Client", "Services", "DeathService.lua"),
        ("Client", "Services", "PauseMenuService.lua"), ("Client", "Services", "TalkClient.lua"),
        ("Server", "Services", "StoryService.lua"), ("Server", "Services", "Townsfolk.lua"),
        ("Server", "Services", "SquishRoomService.lua"), ("Server", "Services", "HubService.lua"),
        ("Server", "Services", "EconomyService.lua"))
for parts in READ:
    text = read(*parts)
    if not text:
        fail("missing " + "/".join(parts))
        continue
    for said in strings(text):
        if (" " in said or said.endswith((".", "!", "?"))) and MARKS.search(said):
            fail("%s: a player reads a trade mark: \"%s\"" % (parts[-1], said[:70]))
for key, words in (("KineticSand", "Sculpting sand"), ("Lego", "Toy bricks"), ("JelloSoda", "Jelly"),
                   ("Needoh", "A stress ball")):
    if not re.search(r'^\t%s = "%s' % (key, re.escape(words)), ONBOARDING, re.M):
        fail("OnboardingService: the hint for %s does not call it %s" % (key, words.lower()))

# ===================================================================== the floor going behind you (151)

CONFIG = read("Shared", "MaterialConfig.lua")
DEFORM = read("Server", "Services", "DeformationService.lua")
RENDER = read("Client", "Services", "DeformationRenderer.lua")


def materials(text):
    """{name: body} for every entry of MaterialConfig's Materials table."""
    found = {}
    for match in re.finditer(r"^\t(\w+) = \{\n(.*?)^\t\},", text, re.M | re.S):
        found[match.group(1)] = match.group(2)
    return found


def number(body, field):
    match = re.search(r"^\t\t%s = ([\d.]+),?$" % field, body, re.M)
    return float(match.group(1)) if match else None


MATS = materials(CONFIG)
if len(MATS) < 25:
    fail("MaterialConfig: only %d materials read (the table's shape has changed under this check)" % len(MATS))
CRUMBLING = ("KineticSand", "Soap", "Cookie", "Lego", "ChocolateSolid", "Ice", "Lava", "Cloud",
             # (205) bubble wrap gives way too, from your note of 2026-11-07: "drop me just how other chunks do"
             "BubbleWrap")
# (246) SNOW, MEMORY FOAM AND WARM CHOCOLATE KEEP THEIR FLOOR under a walking foot, from your "continue" of 2026-11-22: snow
# packs into a faster trail, foam is soft and never drops you, chocolate holds your feet where it has melted. Each must
# have its own reason to cross it, and none may crumble behind you again.
for name, needle in (("Snow", "packedSpeed"), ("Foam", "jumpScale"), ("Chocolate", "softSpeed")):
    body = MATS.get(name, "")
    if number(body, "crumbleAfter") is not None:
        fail("MaterialConfig: %s crumbles behind you again (246: it keeps its floor)" % name)
    if needle not in body:
        fail("MaterialConfig: %s has lost what it does instead of breaking (%s)" % (name, needle))
for name in CRUMBLING:
    body = MATS.get(name, "")
    crumble, regrow = number(body, "crumbleAfter"), number(body, "regrowAfter")
    if crumble is None:
        fail("MaterialConfig: %s does not crumble behind you (no crumbleAfter): walked across, it never breaks" % name)
        continue
    if not 0.8 <= crumble <= 2.0:
        fail("MaterialConfig: %s gives way %.2f s after a foot (0.8 to 2: never under a walker, soon behind one)"
             % (name, crumble))
    if regrow is None or regrow > 8:
        fail("MaterialConfig: %s's holes take %s s to fill (eight at most, or whoever follows has no way across)"
             % (name, regrow))
    dissolve = number(body, "dissolveTime")
    if dissolve is not None and dissolve > crumble + 0.05:
        fail("MaterialConfig: %s's standing clock (%.2f) is slower than its crumble (%.2f), so it says nothing"
             % (name, dissolve, crumble))
coal = MATS.get("Charcoal", "")
ignite, burn = number(coal, "igniteAfter"), number(coal, "burnFor")
if ignite is None or burn is None or ignite + burn > 2.2:
    fail("MaterialConfig: a coal stepped on takes %s s to go to ash (2.2 at most)" % (
        "?" if ignite is None or burn is None else "%.1f" % (ignite + burn)))
entered = within(DEFORM, "local function onPlayerEnterCell(")
if not in_order(entered, "local crumble = matDef and matDef.crumbleAfter",
                'if crumble and cell.state ~= "exhausted" and not cell.crumbleAt then',
                "cell.crumbleAt = os.clock() + crumble", "cell.warned = nil"):
    fail("DeformationService: a foot on a crumbling cell does not start it going (once, from the first foot)")
beat = DEFORM[DEFORM.find("RunService.Heartbeat:Connect(function(dt: number)"):]
if not in_order(beat, "local crumbleAt = cell.crumbleAt", 'if crumbleAt and cell.state ~= "exhausted" then',
                "if now >= crumbleAt then", "cell.crumbleAt = nil", "collapseCell(platform, cell, nil)",
                "elseif not cell.warned and now >= crumbleAt - CRUMBLE_WARN then", "cell.warned = true",
                'replicate(platform, cell, nil, "warn")'):
    fail("DeformationService: a crumble never comes due in the heartbeat, or is not shaken first")
if re.search(r"if now >= crumbleAt then[^\n]*\n[^\n]*cell\.count", beat):
    fail("DeformationService: a crumble only takes a cell somebody is still on (the walker behind would never see it)")
warn_at = re.search(r"^local CRUMBLE_WARN = ([\d.]+)$", DEFORM, re.M)
if not warn_at or not 0.25 <= float(warn_at.group(1)) <= 0.7:
    fail("DeformationService: a crumbling cell is shaken %s s before it goes (a quarter to seven tenths of a second)"
         % (warn_at.group(1) if warn_at else "never"))
restore = within(DEFORM, "local function restoreCell(")
if "cell.crumbleAt = nil" not in restore or "cell.warned = nil" not in restore:
    fail("DeformationService: a hole filled back in keeps the crumble that opened it (it would give way again unasked)")
update = within(RENDER, "function DeformationRenderer.onDeformationUpdate(payload)")
if not in_order(update, "remember(tile)", 'if payload.cause == "warn" then', "DeformationRenderer.tremble(tile, material)",
                "return", "local isRepeat = lastState[tile] == state"):
    fail("DeformationRenderer: a cell about to give way is not shaken (or is taken for a footstep, sound and all)")
tremble = within(RENDER, "DeformationRenderer.tremble = (function()", "\nend)()\n")
if not in_order(tremble, "puff(tile, colour", "local bone = boneFor(tile)", "boneOffset(bone, info, base + by)",
                "play(tile, tile, info, { CFrame = from * CFrame.new(0, by, 0) })", 'lastState[tile] ~= "exhausted"'):
    fail("DeformationRenderer: the shake does not judder the cell (its bone, or the tile) and settle it back")
for key, needle in (("KineticSand", "a moment after you step on it"), ("Lego", "a moment after you step on it"),
                    ("ChocolateSolid", "a moment after you step on it")):
    hint = re.search(r'^\t%s = "([^"]*)"' % key, ONBOARDING, re.M)
    if not hint or needle not in hint.group(1):
        fail("OnboardingService: the hint for %s does not say it goes behind you" % key)
# (246) The three that keep their floor say what they do instead.
for key, needle in (("Snow", "trail"), ("Foam", "never drops you"), ("Chocolate", "stand still")):
    hint = re.search(r'^	%s = "([^"]*)"' % key, ONBOARDING, re.M)
    if not hint or needle not in hint.group(1):
        fail("OnboardingService: the hint for %s does not say what it does now (%s)" % (key, needle))

# ===================================================================== your footing (152)

FEEL = read("Client", "Services", "RunFeel.lua")
if not FEEL:
    fail("missing RunFeel")
grip = re.search(r"grip = \{ Ice = ([\d.]+), Soap = ([\d.]+), ButterWax = ([\d.]+), Chocolate = ([\d.]+) \}", FEEL)
if not grip:
    fail("RunFeel: no grip for the slippery things (ice, soap, waxed butter, warm chocolate)")
else:
    ice, soap, wax, choc = (float(v) for v in grip.groups())
    if not (1 <= ice < soap < wax < choc <= 6):
        fail("RunFeel: the slippery things are not ice, then soap, then waxed butter, then chocolate, between 1 and 6 a second")
for material, residue in (("Cloud", "wet"), ("Jellyfish", "wet"), ("ButterStick", "greasy"), ("ButterWax", "greasy"),
                          ("Honey", "sticky"), ("KineticSand", "gritty"), ("Salt", "gritty"), ("Cookie", "gritty")):
    if not re.search(r'\b%s = "%s"' % (material, residue), FEEL):
        fail("RunFeel: %s does not leave your soles %s" % (material, residue))
if "wipes = { LambsEar = true }" not in FEEL:
    fail("RunFeel: lamb's ear does not wipe your soles")
for kind, needles in (("wet", ("seconds = 5", "grip = 7")), ("greasy", ("seconds = 5", "grip = 4.5")),
                      ("sticky", ("seconds = 4", "speed = 0.82", "holds = true")), ("gritty", ("seconds = 4", "boost = 2"))):
    body = re.search(r"\b%s = \{([^}]*)\}" % kind, FEEL)
    if not body or not all(n in body.group(1) for n in needles):
        fail("RunFeel: what %s soles do has changed under this check (%s)" % (kind, ", ".join(needles)))
slide_fn = within(FEEL, "local function slideStep(dt: number)")
for needle, why in (
    ("or inScene() then", "you slide in a scene, where you are held still"),
    ("state == Enum.HumanoidStateType.Swimming", "you slide in the water"),
    ("humanoid.Sit", "you slide in a seat"),
    ("controls:GetMoveVector()", "the slide reads your character's own walk back (it would feed on itself), not your keys"),
    ("slide.carried += (wanted - slide.carried) * (1 - math.exp(-rate * dt))", "the slide is not eased at the ground's grip"),
    ("humanoid:Move(slide.carried * speed, false)", "the slide is never given to your character's walk"),
):
    if needle not in slide_fn:
        fail("RunFeel: " + why)
if re.search(r"if rate == nil then\n\t\tslide\.carried = wanted\n\t\tif speed < 1 then\n\t\t\thumanoid:Move\(wanted \* speed, false\)\n\t\tend\n\t\treturn", slide_fn) is None:
    fail("RunFeel: on ordinary ground your walk is taken over (it must be left to Roblox unless your soles slow you)")
if 'BindToRenderStep("RunFeelFooting", Enum.RenderPriority.Input.Value + 1,' not in FEEL:
    fail("RunFeel: the slide does not come just after Roblox reads your keys (Input + 1)")
grip_fn = within(FEEL, "local function gripFor(f: Feet?): (number?, number)")
if not in_order(grip_fn, "local onSource", "if residue.holds then", "return nil,"):
    fail("RunFeel: sticky soles slide (they hold, even on ice), or slow you on the honey itself")
if not in_order(within(FEEL, "local function groundUnder("), 'item:GetAttribute("Material")', "item = item.Parent"):
    fail("RunFeel: what you stand on is not found from its platform's Material")
if not re.search(r"while #slide\.prints > FOOTING\.kept do", FEEL):
    fail("RunFeel: the sole prints are never thinned out")
for key, needle in (("Cloud", "wets your shoes"), ("Honey", "sticks to your shoes"), ("LambsEar", "wipes your shoes"),
                    ("Ice", "slippery"), ("Soap", "slippery"), ("ButterWax", "slippery")):
    hint = re.search(r'^\t%s = "([^"]*)"' % key, ONBOARDING, re.M)
    if not hint or needle not in hint.group(1):
        fail("OnboardingService: the hint for %s does not say it %s" % (key, needle))

# ===================================================================== the butter sticks, waxed (153, then 243)
# 153 took the wrapper off because the sticks stood 0.3 ABOVE the walkable plane under it, so the shell was inside the
# butter. 243 put it back, with the sticks a shell's thickness BELOW the plane, so the shell's crests are the floor.

BUILDER = read("Server", "ChunkBuilder.server.lua")
PROPS = read("Server", "ChunkProps.server.lua")
SHELL_T = 0.3
shells = within(BUILDER, "local WAX_SHELLS: { [string]: { WaxSpec } } = {", "\n}\n")
shells = "\n".join(line.split("--")[0] for line in shells.split("\n"))
if not shells.strip():
    fail("ChunkBuilder: no WAX_SHELLS (the table's shape has changed under this check)")
elif "Wax_Shell_Sticks_16x12_A" not in shells or "Wax_Shell_Sticks_16x12_B" not in shells:
    fail("ChunkBuilder: the butter sticks have no draped wax shell (243: a crackable wax shell)")
if not re.search(r"^\tButterStick = \{ whiten", BUILDER, re.M):
    fail("ChunkBuilder: the butter sticks' wax has no finish of its own")
sticks = re.search(r"ButterStick = \{\n(?:\t\t--[^\n]*\n)*\t\t\{ sizeX = 16, sizeZ = 12, meshHeight = ([\d.]+), surfaceOffset = ([\d.]+),", BUILDER)
if not sticks:
    fail("ChunkBuilder: the butter sticks' rig is gone")
elif abs(float(sticks.group(2)) - (float(sticks.group(1)) / 2 + SHELL_T)) > 0.05:
    fail("ChunkBuilder: the butter sticks are not a shell's thickness under where you walk (offset %s, want %.2f): "
         "higher and the shell is inside them (153), lower and it floats" % (sticks.group(2), float(sticks.group(1)) / 2 + SHELL_T))
butter = RENDER[RENDER.find("local BUTTER_STICK = {}"):RENDER.find("local function softBedEffect(")]
if "BUTTER_STICK.SHELL = true" not in butter or "BUTTER_STICK.CRACK = true" not in butter:
    fail("DeformationRenderer: the butter sticks' wax does not go down with the dent and crack (243)")
# Opaque: see-through, bare butter reads as a glass block with butter's colour (the water through its edges).
look = re.search(r"^\tButterStick = \{\n(.*?)\n\t\},", read("Shared", "MaterialAppearance.lua"), re.S | re.M)
see = re.search(r"^\t\ttransparency = ([\d.]+),", look.group(1), re.M) if look else None
if not look:
    fail("MaterialAppearance: the butter sticks have no look of their own")
elif see and float(see.group(1)) > 0.02:
    fail("MaterialAppearance: the butter sticks are see-through (%s), a glass block the colour of butter" % see.group(1))
curls = re.search(r"BUTTER_STICK\.CURLS = (\d+)", butter)
if not curls or not 1 <= int(curls.group(1)) <= 4:
    fail("DeformationRenderer: a step on the butter turns up no curl of it (one to four)")
if not re.search(r"^\tButterCurl = \{ colour = ", RENDER, re.M):
    fail("DeformationRenderer: there is no butter curl to turn up")
if "flingDebris(tile, \"ButterCurl\", profile.CURLS)" not in RENDER:
    fail("DeformationRenderer: the soft bed never turns up its curls")
if "textureFrom" in within(PROPS, "P25_ButterStick = {", "},") or not re.search(r"^\tP25_ButterStick = \{\},", PROPS, re.M):
    fail("ChunkProps: the bare butter sticks take a wrapper's print again")
stick_def = MATS.get("ButterStick", "")
if 'category = "pace"' not in stick_def or "crumbleAfter" in stick_def or "stepsToCollapse" in stick_def:
    fail("MaterialConfig: the butter sticks drop you (they are soft, and a pace material)")
hint = re.search(r'^\tButterStick = "([^"]*)"', ONBOARDING, re.M)
if not hint or "greasy" not in hint.group(1) or "stick of butter" in hint.group(1):
    fail("OnboardingService: the butter's hint does not say it greases your shoes")

# ===================================================================== bubble wrap pops (154)

wrap = MATS.get("BubbleWrap", "")
if "microBounceHeight" in wrap or "launchVelocity" in wrap:
    fail("MaterialConfig: bubble wrap throws you up on every touch again (a trampoline, the popping lost under it)")
if number(wrap, "popCount") != 2:
    fail("MaterialConfig: a bubble wrap cell takes %s pops to give way (two)" % number(wrap, "popCount"))
land = re.search(r"^local POP_LAND = ([\d.]+)$", DEFORM, re.M)
rebound = re.search(r"^local POP_REBOUND = ([\d.]+)$", DEFORM, re.M)
if not land or not 20 <= float(land.group(1)) <= 45:
    fail("DeformationService: a landing that pops a ring is a fall of %s studs a second (20 to 45: a jump, not a step down)"
         % (land.group(1) if land else "nothing"))
if not rebound or not 1 <= float(rebound.group(1)) <= 3.5:
    fail("DeformationService: fresh wrap gives %s studs of a landing back (one to three and a half: a give, not a throw)"
         % (rebound.group(1) if rebound else "nothing"))
ring = within(DEFORM, "local function ringPop(")
if not in_order(ring, "for dc = -1, 1 do", "for dr = -1, 1 do", "cellAt(state, landed.col + dc, landed.row + dr)",
                "if other.count == 0 then", 'other.state = "decaying"', "other.origin = Vector2.new(landed.col, landed.row)",
                'popBubbles(platform, state, other, player, "ring", false)', "other.origin = nil"):
    fail("DeformationService: a landing does not pop the eight cells round it (or leaves them never coming back)")
entered = within(DEFORM, "local function onPlayerEnterCell(")
if not in_order(entered, 'if state.material == "BubbleWrap" and cell.state ~= "exhausted" then',
                "local fresh = cell.popCount == 0", "popBubbles(platform, state, cell, player, nil, announced)",
                "local fall = lowestFall[player]", "fall.speed < -POP_LAND", "os.clock() - fall.at <= FALL_MEMORY",
                "fall.speed = 0", "ringPop(platform, state, cell, player)", "if fresh and cell.state ~= \"exhausted\" then",
                "SlimeLaunch:FireClient(player, bounceVelocity(POP_REBOUND))"):
    fail("DeformationService: a step on bubble wrap does not pop it, or a landing does not pop a ring, once")
wrap_fx = within(RENDER, "Effects.BubbleWrap = function(ctx: Ctx)")
if not in_order(wrap_fx, 'if ctx.cause == "ring" then', 'ctx.cause = "rung"', "task.delay(",
                'AudioService.playSfx("BubbleWrap", tile, ctx.mine, { force = true', "Effects.BubbleWrap(ctx)", "return"):
    fail("DeformationRenderer: a landing's ring goes off all at once, or silently")
hint = re.search(r'^\tBubbleWrap = "([^"]*)"', ONBOARDING, re.M)
if not hint or "ring" not in hint.group(1):
    fail("OnboardingService: the bubble wrap's hint does not say a jump pops a ring")

# ===================================================================== the keyboards, key by key (155)

APPEAR = read("Shared", "MaterialAppearance.lua")
CHUNKS = read("Server", "Services", "ChunkService.lua")
if not re.search(r'^local KEYED: \{ \[string\]: boolean \} = \{ CreamyKeyboard = true, LavaKeys = true \}', BUILDER, re.M):
    fail("ChunkBuilder: the keyboards are not built key by key (KEYED)")
if 'mesh = "Keyboard_Field' in BUILDER:
    fail("ChunkBuilder: a keyboard is the rigged field again (one colour for every key, the letters in one texture)")
keycap = within(BUILDER, "local function attachKeycap(")
for needle, why in (
    ("local template = keycapTemplate()", "the sculpted cap is not looked for"),
    ('warn("ChunkBuilder: no Keycap_Sculpted', "a board without the imported cap says nothing"),
    ("cap.Size = tile.Size\n", "a key does not fill its cell (the gaps between keys come back)"),
    ("cap.CFrame = tile.CFrame * CFrame.Angles(0, math.pi, 0)", "a key's letter reads upside down to whoever walks the board"),
    ("cap.CanCollide = false", "a key collides (the tile is the floor; a moving collider re-fires its own touches)"),
    ('cap:SetAttribute("Role", role)', "a key has no part in its colourway"),
    ('gui.Face = Enum.NormalId.Top', "a key's letter is not on its top"),
    ("label.FontFace = Style.WORLD.", "a key's letter is not in the game's one face"),
    ("cap.Parent = tile", "a key is not on its cell"),
):
    if needle not in keycap:
        fail("ChunkBuilder: " + why)
regions = within(BUILDER, "local function buildSubRegions(")
for needle, why in (
    ("if BRICKED[materialName] or KEYED[materialName] or ROCKED[materialName] or CHUNKED[materialName] then\n\t\t\t\ttile.Transparency = 1",
     "a keyboard's tiles show over its keys"),
    ("attachKeycap(tile, materialName, col, row, grid.cols, grid.rows)", "a keyboard's cells get no keys"),
    ("and not BRICKED[materialName] and not KEYED[materialName]\n\t\t\t\tand not ROCKED[materialName] then",
     "a keyboard's cells ask for tile meshes it has no use for"),
    ("attachKeyboardBody(slab, materialName)\n\t\tMaterialAppearance.paintKeys(slab, nil)", "a keyboard is never coloured"),
):
    if needle not in regions:
        fail("ChunkBuilder: " + why)
cell = 16 / max(2, min(6, int(16 / 3.2 + 0.5)))
seam = 0.15
CAPGEN = (ROOT / "blender" / "gen_keycap.py").read_text(encoding="utf-8") if (ROOT / "blender" / "gen_keycap.py").exists() else ""
base = re.search(r"^BASE = ([\d.]+)", CAPGEN, re.M)
height = re.search(r"^HEIGHT = ([\d.]+)", CAPGEN, re.M)
tile_thick = re.search(r"^local TILE_THICKNESS = ([\d.]+)", BUILDER, re.M)
if not (base and height and tile_thick):
    fail("gen_keycap.py: the cap's size is not where this check reads it")
else:
    if abs(float(base.group(1)) - (cell - seam)) > 0.01:
        fail("gen_keycap.py: the cap is %s across, and a 16-stud board's key is %.2f (its cell less the seam)"
             % (base.group(1), cell - seam))
    if abs(float(height.group(1)) - float(tile_thick.group(1))) > 0.01:
        fail("gen_keycap.py: the cap is %s tall, and the tile it stands for is %s" % (height.group(1), tile_thick.group(1)))
if not (ROOT / "meshes" / "Keycap_Sculpted.fbx").exists():
    fail("meshes/Keycap_Sculpted.fbx is not there to import (run blender/gen_keycap.py)")
ways = re.search(r"MaterialAppearance\.CREAMY_WAYS = \{([^}]*)\}", APPEAR)
names = re.findall(r'"(\w+)"', ways.group(1)) if ways else []
if len(names) < 8:
    fail("MaterialAppearance: %d colourways for the creamy keyboards (eight at least)" % len(names))
KEYCAPS = within(APPEAR, "local KEYCAPS: { [string]: Colourway } = {", "\n}\n")
for name in names + ["Lava"]:
    way = re.search(r"^\t%s = \{(.*?)\},$" % name, KEYCAPS, re.M | re.S)
    if not way or not all(f + " = rgb(" in way.group(1) for f in ("alpha", "alphaInk", "mod", "modInk", "accent", "accentInk", "case")):
        fail("MaterialAppearance: the %s colourway is missing a colour (letters, number row, accents, each ink, the case)" % name)
paint = within(APPEAR, "function MaterialAppearance.paintKeys(")
for needle, why in (
    ('if material == "LavaKeys" then "Lava" else way or ways[math.random(1, #ways)]', "the keys over lava are painted a creamy colourway"),
    ('if material == "CreamyKeyboard" then\n\t\t\tslab.Color = colours.case', "a creamy board's case keeps another board's colour"),
    ('cap:SetAttribute("KeyColour", colour)', "a key does not keep its colour (heat cannot give it back)"),
    ("letter.TextColor3 = ink", "a key's letter is not inked"),
):
    if needle not in paint:
        fail("MaterialAppearance: " + why)
spawn = within(CHUNKS, "function ChunkService.spawnChunk(")
if not in_order(spawn, "MaterialAppearance.paintKeys(clone, nil)", "clone.Parent = ensureLevelsFolder()"):
    fail("ChunkService: a keyboard placed in a level keeps its template's colours (every board alike)")
if re.search(r"^\tP2[123]_Keyboard\w+ = \{ (tint|texture)", PROPS, re.M) or "13076266447" in PROPS:
    fail("ChunkProps: a keyboard is tinted or textured whole again, over its keys' colours")
keys = within(RENDER, "-- ===== THE KEYBOARDS, KEY BY KEY", "\n\tsection()\nend\n")
for needle, why in (
    ("Keys.move(cap, Keys.DOWN, -Keys.DEPTH)", "a key does not go down under a foot"),
    ("UP = TweenInfo.new(0.26, Enum.EasingStyle.Back", "a key does not spring back"),
    ('cap:SetAttribute("KeyHeld", true)', "a key being moved is not marked, so the lava's bob fights it"),
    ("for _, other in ipairs(Keys.around(tile)) do", "the keys round a pressed one do not take the weight"),
    ('if done == Enum.PlaybackState.Completed and cap.Parent then', "a key back at rest is never let go"),
):
    if needle not in keys:
        fail("DeformationRenderer: " + why)
creamy = within(keys, "Effects.CreamyKeyboard = function(ctx: Ctx)", "\n\t\tend\n\n")
if 'if ctx.state == "deformed" then' not in creamy or "task.delay(0.11" in creamy or "Keys.UP, 0)" not in creamy:
    fail("DeformationRenderer: a key does not stay down while the foot is on it and come up when it leaves")
if re.search(r'Name:sub\(1, 4\) == "Key_"', RENDER):
    fail("DeformationRenderer: the keys are still looked for as bones of the rigged field")
hint = re.search(r'^\tCreamyKeyboard = "([^"]*)"', ONBOARDING, re.M)
if not hint or "springs back" not in hint.group(1):
    fail("OnboardingService: the keyboard's hint does not say a key springs back")

# ===================================================================== the keys over lava (156)

lava_keys = MATS.get("LavaKeys", "")
clock = number(lava_keys, "dissolveTime")
if 'category = "risk"' not in lava_keys or clock is None or not 1.0 <= clock <= 1.8:
    fail("MaterialConfig: a key over lava does not sink under someone standing on it (a risk, 1 to 1.8 s)")
if not 2 <= (number(lava_keys, "wearSteps") or 0) <= 6:
    fail("MaterialConfig: a key over lava does not wear out under feet (249: wearSteps 2 to 6)")
if (number(lava_keys, "regrowAfter") or 99) > 8:
    fail("MaterialConfig: a key gone under the lava is too long coming back (eight seconds at most)")
if "microBounceHeight" in lava_keys:
    fail("MaterialConfig: the keys over lava throw you up")
float_at = re.search(r"^local LAVA_FLOAT = ([\d.]+)$", BUILDER, re.M)
if not float_at or not 0.3 <= float(float_at.group(1)) <= 0.7:
    fail("ChunkBuilder: the lava under the keys is not where their feet are in it (LAVA_FLOAT 0.3 to 0.7 under the plane)")
body = within(BUILDER, "local function attachKeyboardBody(")
for needle, why in (
    ('if materialName ~= "LavaKeys" then', "the creamy boards get a pool of lava"),
    ("slab.Transparency = 1", "the slab still shows where the lava should be"),
    ('pool.Name = "LavaPool"', "there is no lava under the keys"),
    ("pool.CanCollide = false", "the lava is a floor (a key gone under would drop you onto it)"),
    ('skin.Name = "LavaSkin"', "the lava has no skin of its own"),
):
    if needle not in body:
        fail("ChunkBuilder: " + why)
cont = re.search(r"^local CONTINUOUS: [^\n]*", BUILDER, re.M)
if not cont or "LavaKeys" in cont.group(0):
    fail("ChunkBuilder: the keys over lava are edge-matched tiles (no seams between keys)")
look = re.search(r"^\tLavaKeys = \{\n(.*?)^\t\},", APPEAR, re.M | re.S)
if not look or "Neon" in look.group(1):
    fail("MaterialAppearance: the keys over lava are Neon (nothing glows by being Neon)")
lava_fx = within(keys, "Effects.LavaKeys = function(ctx: Ctx)", "\n\t\tend\n\tend\n")
for needle, why in (
    ("local clock = (own and own.dissolveTime) or 1.3", "a key does not sink over the material's own clock"),
    ("Keys.move(cap, TweenInfo.new(clock, Enum.EasingStyle.Quad, Enum.EasingDirection.In), -Keys.SINK)", "a key does not sink as you stand on it"),
    ("{ Color = Keys.HOT }", "a sinking key does not heat"),
    ('elseif ctx.state == "exhausted" then', "a key gone under is not seen going"),
    ("lavaLife.bubble(slab,", "a key going under makes no splash"),
    ("Keys.move(cap, if fromUnder then Keys.BACK else Keys.RISE, 0)", "a key let go does not come back up"),
    ("{ Color = if fromUnder then colour else Keys.wornColour(colour, wear) }", "a key let go does not cool (to its wear, 249)"),
    ("Keys.wearLook(cap, wear)", "a key does not show its wear (249)"),
):
    if needle not in lava_fx:
        fail("DeformationRenderer: " + why)
life_fx = RENDER[RENDER.find("local lavaLife = {"):RENDER.find("Effects.Lava = function(ctx: Ctx)")]
for needle, why in (
    ('local pool = platform:FindFirstChild("LavaPool")', "the lava's life does not know the keys' pool"),
    ("pool.CFrame * CFrame.new(0, pool.Size.Y / 2 + 0.05, 0)", "the embers and bubbles do not come off the pool's surface"),
    ("skinTexture.OffsetStudsU = (now * 0.35) % 7", "the pool does not flow"),
    ('if cap.Parent and not cap:GetAttribute("KeyHeld") then', "the floating keys' bob fights a key being pressed"),
    ('if material ~= "Lava" and material ~= "LavaKeys" then', "the keys over lava are not lava to the lava's life"),
):
    if needle not in life_fx:
        fail("DeformationRenderer: " + why)
hint = re.search(r'^\tLavaKeys = "([^"]*)"', ONBOARDING, re.M)
if not hint or "sinks while you stand on it" not in hint.group(1):
    fail("OnboardingService: the keys over lava's hint does not say a key sinks under you")

# ===================================================================== the idles and the emotes, keyed (157, 158)

sys.path.insert(0, str(ROOT / "blender"))
import pose_keys  # noqa: E402

POSES_TEXT = read("Shared", "Poses.lua")
KEYED = pose_keys.read_keyed(POSES_TEXT)
EMOTES_TEXT = read("Client", "Services", "EmoteService.lua")
LIFE = read("Client", "Services", "PlayerLife.lua")
IDLES = ("idleLook", "idleShift", "idlePonder", "idleYawn", "idleHand", "idleTap", "idleAuraCrossed", "idleAuraBreeze",
         "idleAuraPockets", "idleAuraBrush")
EMOTE_POSES = ("emoteWave", "emoteCheer", "emoteBow", "emoteShrug", "emoteFlex", "emoteStretch", "emoteSpin", "emoteGroove",
               "emoteSitSquish", "emoteAura")
for name in IDLES + EMOTE_POSES:
    if name not in KEYED:
        fail("Poses: no keyed pose %s (blender/gen_poses.py writes them)" % name)
    elif "function Poses.%s(name: string, t: number, w: number, r6: boolean): CFrame?" % name not in POSES_TEXT:
        fail("Poses: %s has no function to play it" % name)
GEN = (ROOT / "blender" / "gen_poses.py")
if GEN.exists():
    import subprocess
    stale = subprocess.run([sys.executable, str(GEN), "--check"], capture_output=True, text=True, cwd=str(ROOT))
    if stale.returncode != 0:
        fail("Poses.lua's keyed poses are not what blender/gen_poses.py writes: run it")
else:
    fail("blender/gen_poses.py is missing")
for needle, why in (
    ("local function curve(track: { { number } }, t: number, k: number): number", "no curve through a pose's keys"),
    ("if (here - before) * (after - here) <= 0 then\n\t\t\treturn 0", "a joint overshoots a key where it turns back"),
    ("return loop[1] + (t - loop[2]) % (loop[2] - loop[1])", "a pose's loop is not played round"),
    ("local function r6Turn(", "an R6 body is left out of every keyed pose"),
    ("return CFrame.new(curve(track, t, 5), curve(track, t, 6), curve(track, t, 7)) * angles", "the root never moves (a sit, a hop)"),
):
    if needle not in POSES_TEXT:
        fail("Poses: " + why)
for name, pose in KEYED.items():
    first_bad, last_bad = [], []
    for joint, track in pose["keys"].items():
        if any(abs(v) > 1e-6 for v in track[0][1:]):
            first_bad.append(joint)
        end = list(track[-1][1:])
        if joint == "Root" and abs(end[1] - 2 * math.pi) < 1e-3:
            end[1] = 0.0
        if any(abs(v) > 1e-6 for v in end):
            last_bad.append(joint)
    if first_bad or last_bad:
        fail("Poses.%s does not start and end at rest (%s)" % (name, ", ".join(sorted(set(first_bad + last_bad)))))
    loop = pose["loop"]
    if loop:
        last = max(track[-1][0] for track in pose["keys"].values())
        spare = pose["seconds"] - (last - loop[1]) - loop[1]
        span = loop[1] - loop[0]
        if spare < -1e-6 or abs(spare / span - round(spare / span)) > 1e-3:
            fail("Poses.%s: its loop does not end on its own start when the way out begins (a jump)" % name)
    hits = []
    t = 0.0
    while t <= pose["seconds"]:
        hits += pose_keys.collisions(pose_keys.turns(pose, t))
        t += 0.1
    if hits:
        fail("Poses.%s passes through itself: %s" % (name, ", ".join(sorted(set(hits)))))
    fastest, at, joint = pose_keys.speeds(pose)
    if fastest > 16:
        fail("Poses.%s whips %s at %.1f radians a second (sixteen at most)" % (name, joint, fastest))
    lowest = 99.0
    t = 0.0
    while t <= pose["seconds"]:
        points, _, _ = pose_keys.body(pose_keys.turns(pose, t))
        lowest = min(lowest, points["RightToe"][1], points["LeftToe"][1], points["RightAnkle"][1], points["LeftAnkle"][1])
        t += 0.1
    if lowest < pose_keys.GROUND - 0.35:
        fail("Poses.%s puts a foot %.2f studs into the floor" % (name, pose_keys.GROUND - lowest))
lengths = dict(re.findall(r"^\t(\w+) = ([\d.]+),$", within(POSES_TEXT, "Poses.LENGTH = {", "\n}\n"), re.M))
emote_rows = re.findall(r'^\t(\w+) = \{ pose = "(\w+)", seconds = ([\d.]+)([^\n]*)\},$', EMOTES_TEXT, re.M)
if len(emote_rows) < 10:
    fail("EmoteService: %d emotes (ten)" % len(emote_rows))
for emote, pose, seconds, rest in emote_rows:
    if pose not in lengths or abs(float(lengths[pose]) - float(seconds)) > 1e-6:
        fail("EmoteService: %s lasts %s, and its pose %s %s" % (emote, seconds, pose,
             "is " + lengths[pose] if pose in lengths else "does not exist"))
order = re.search(r"^local ORDER = \{([^}]*)\}", EMOTES_TEXT, re.M)
listed = set(re.findall(r'"(\w+)"', order.group(1))) if order else set()
if listed != {row[0] for row in emote_rows}:
    fail("EmoteService: the picker's ORDER and the emotes it plays are not the same ten")
for emote in {row[0] for row in emote_rows}:
    if not re.search(r'\{ id = "%s", tab = "Emotes", kind = "emote"' % emote, CATALOG):
        fail("ShopCatalog: the emote %s cannot be bought" % emote)
if not re.search(r'Aura = \{ pose = "emoteAura", seconds = [\d.]+, aura = true \}', EMOTES_TEXT):
    fail("EmoteService: the Aura comes without its glow")
for needle, why in (
    ("local function auraOn(entry: Playing, root: BasePart)", "there is no glow for the Aura"),
    ("if emote.aura then\n\t\t\tauraOn(entry, root :: BasePart)", "the Aura's glow is never put on"),
    ("local glow = entry.glow\n\tif glow then", "the Aura's glow is left on after it"),
):
    if needle not in EMOTES_TEXT:
        fail("EmoteService: " + why)
if "Neon" in within(EMOTES_TEXT, "local function auraOn("):
    fail("EmoteService: the Aura glows by being Neon")
fidgets = re.findall(r'\{ pose = "(\w+)", seconds = ([\d.]+), often = ([\d.]+) \}', LIFE)
if len(fidgets) < 10 or sum(1 for f in fidgets if f[0].startswith("idleAura")) < 4:
    fail("PlayerLife: %d idles, %d with aura (ten, four)" % (len(fidgets), sum(1 for f in fidgets if f[0].startswith("idleAura"))))
for pose, seconds, _ in fidgets:
    if pose not in lengths or abs(float(lengths[pose]) - float(seconds)) > 1e-6:
        fail("PlayerLife: the idle %s lasts %s, and its pose %s" % (pose, seconds,
             "is " + lengths[pose] if pose in lengths else "does not exist"))
pick = within(LIFE, "local function nextFidget(")
# Both passes over the list: the one weighing what is left, and the one picking from it.
if pick.count("if fidget ~= last then") != 2 or "local fidget = nextFidget(life.rng, life.last)" not in LIFE:
    fail("PlayerLife: an idle can come twice running")

# SODA FIZZES (205), from your note of 2026-11-07: on a soda chunk "I have green waves coming out of my feet as though
# I'm on slime chunk". Soda shares slime's step, so it must say what is its own: its rings its own foam, no slime goo
# under it, and a burst of bubbles (a film with a glint, a texture of its own) where you step.
slime_step = within(RENDER, "Effects.Slime = function(ctx: Ctx)")
for needle, why in (
    ('elseif ctx.material == "JelloSoda" then MaterialAppearance.Appearances.JelloSoda.color:Lerp(Color3.new(1, 1, 1), 0.55)',
     "soda's rings are slime's green"),
    ("SLIME.fizz(tile, feet[1] and feet[1].position or tile.Position)", "a step on soda lets go no fizz"),
    ('if ctx.material ~= "JelloSoda" and (not marks[tile] or #marks[tile] < 3) then', "slime's green goo hangs under soda"),
):
    if needle not in slime_step:
        fail("DeformationRenderer: " + why)
fizz = within(RENDER, "function SLIME.fizz(tile: BasePart, at: Vector3)")
if not re.search(r'^SLIME\.SODA_BUBBLE = "rbxassetid://\d+"', RENDER, re.M) or "bubbles.Texture = SLIME.SODA_BUBBLE" not in fizz:
    fail("DeformationRenderer: soda's bubbles are not its own film with a glint")
if "bubbles:Emit(SLIME.SODA_BURST)" not in fizz or "Debris:AddItem(host, 2)" not in fizz:
    fail("DeformationRenderer: soda's fizz is not a burst that clears itself away")
foam_fx = within(RENDER, "Effects.Foam = function(ctx: Ctx)")
if not in_order(foam_fx, 'if ctx.state == "exhausted" then', "setResidual(tile, bone, give, -NEW_MATS.Foam.drop)",
                "moveTile(tile, give, -NEW_MATS.Foam.drop, 1, 1)", "return", 'if ctx.state == "deformed" then'):
    fail("DeformationRenderer: foam that gives way stays where it was, with no floor under it")
foam_drop = re.search(r"Foam = \{ press = [\d.]+, dwell = [\d.]+, rate = [\d.]+, rebound = [\d.]+, tick = [\d.]+, drop = ([\d.]+),", RENDER)
if not foam_drop or not 2 <= float(foam_drop.group(1)) < 3:
    fail("DeformationRenderer: foam that gives way does not drop out of sight, or turns its bed inside out (drop 2 to 3)")
# THE LIGHT SWITCHES ARE SOLID (205), from your note of 2026-11-07: "I should physically be able to turn them on or off in
# a better fashion, as though they should be more 'solid'". No skinned plate to bend like rubber: every switch its own
# rigid plate and rocker paddle on a pivot, the paddle and its pilot light tipped together.
#
# AND WORKED BY THE FOOT (208), from your note of 2026-11-10: "work further on ... the light switches". The paddle was a
# picture of a rocker, thrown once as you came onto its cell by where your foot happened to be. Now it collides, stands
# proud at its raised end and flush at the other, and is thrown by a sole coming down on its raised half (every foot
# near you, every frame), never by the cell; the cell is sensed by a taller part, since a foot on a raised half is clear
# of the tile; and its clack is the throw's, not the cell's.
if re.search(r"^\tLightSwitch = \{\n\t\t\{ sizeX", BUILDER, re.M):
    fail("ChunkBuilder: the light switches are a skinned plate again, and bend like rubber under a foot")
rocker = within(BUILDER, "local function attachRocker(tile: BasePart, materialName: string)")
for needle, why in (
    ('paddle:SetAttribute("Pivot", tile.CFrame:ToObjectSpace(pivot))',
     "a rocker says where it turns in the world's space, which is wrong the moment its chunk is stood in a level"),
    ("pivot * CFrame.Angles(-ROCKER.TILT, 0, 0) * CFrame.new(0, ROCKER.THICK / 2 - ROCKER.SINK, 0))",
     "a rocker does not rest tipped off, on its pivot"),
    ('pilot:SetAttribute("Offset", onPaddle)', "a rocker's pilot light is left behind when it tips"),
    ("paddle.CanCollide = true", "a rocker is not under your foot: you walk through it"),
    ('CollectionService:AddTag(paddle, "SwitchRocker")', "a rocker cannot be found by the screens that work it"),
    ('fixed("SwitchWell",', "a rocker has no well round it, and its edge is lost in its plate"),
    ('fixed("SwitchScrew",', "a switch plate has no screws"),
):
    if needle not in rocker:
        fail("ChunkBuilder: " + why)
if "\t\t\tif ROCKED[materialName] then\n\t\t\t\tattachRocker(tile, materialName)" not in BUILDER:
    fail("ChunkBuilder: the light switches are never given their rockers")
spec = {}
for key in ("SEAM", "WIDE", "LONG", "THICK", "SINK"):
    found = re.search(r"^\t%s = ([\d.]+)," % key, within(BUILDER, "local ROCKER = {", "\n}\n"), re.M)
    spec[key] = float(found.group(1)) if found else None
tilt = re.search(r"^\tTILT = math\.rad\(([\d.]+)\),", within(BUILDER, "local ROCKER = {", "\n}\n"), re.M)
if None in spec.values() or not tilt:
    fail("ChunkBuilder: this check can no longer read the rocker's measurements")
else:
    import math
    # On the shallowest cell a switch has (2.85 studs deep): how far the rocker's two ends stand over the plate.
    half = 2.85 * spec["LONG"] / 2
    swing = half * math.sin(math.radians(float(tilt.group(1))))
    middle = spec["THICK"] - spec["SINK"]
    raised, low = middle + swing, middle - swing
    if raised < 0.3:
        fail("ChunkBuilder: a rocker's raised end stands %.2f over its plate: under 0.3 it is not felt, nor seen to be raised" % raised)
    if raised > 0.6:
        fail("ChunkBuilder: a rocker's raised end stands %.2f over its plate: over 0.6 is a kerb, not a switch" % raised)
    if not -0.06 <= low <= 0.08:
        fail("ChunkBuilder: a rocker's low end is %.2f over its plate: it should come out flush" % low)
if "proud = true," not in MATS.get("LightSwitch", ""):
    fail("MaterialConfig: the light switches are not marked proud, so a foot on a raised rocker is not sensed")
if "reachDef.proud == true" not in DEFORM:
    fail("DeformationService: a proud material's cells are sensed by the thin tile, which a foot on a rocker is clear of")
rockers = within(RENDER, "local ROCKERS = {", "\nEffects.LightSwitch = function(ctx: Ctx)")
for needle, why in (
    ("local goal = (pivot :: CFrame) * CFrame.Angles(if on then tilt else -tilt, 0, 0) * CFrame.new(0, rise, 0)",
     "a rocker does not tip whole about its pivot"),
    ("TweenService:Create(pilot, snap, { CFrame = goal * offset,", "a rocker's pilot light stays put as it tips"),
    ("TweenService:Create(rocker, snap, { CFrame = goal }):Play()",
     "a rocker's throw is one of its tile's tweens, which the cell's next word from the server cancels before it has moved"),
    ("table.insert(feet, { at = part.Position - part.CFrame.UpVector * (part.Size.Y / 2), mine = player == me })",
     "the rockers are not worked by soles"),
    ("for _, player in ipairs(Players:GetPlayers()) do", "only your own feet work the rockers, so nobody else's switches move"),
    ("local pivot = tile.CFrame * (hinge :: CFrame)", "a rocker is tipped about where its template stood, not where it is"),
    ("local pivot = (tile :: BasePart).CFrame * (hinge :: CFrame)", "feet are measured against where a rocker's template stood"),
    ("and at.Y >= -0.4 and at.Y <= ROCKERS.OVER then", "a foot passing over a rocker in a jump throws it"),
    ("if near ~= far and (switchOn[tile] == true) ~= far then", "a rocker is thrown by a foot on the half already down, or chatters under two feet"),
    ('AudioService.playSfx("LightSwitch", tile, mine, { force = true })', "a rocker goes over without its clack"),
    ('tags:GetInstanceAddedSignal("SwitchRocker"):Connect(', "a switch streamed in later is never worked"),
):
    if needle not in rockers:
        fail("DeformationRenderer: " + why)
if "\nROCKERS.start()\n" not in RENDER:
    fail("DeformationRenderer: the rockers are never watched")
switch_fx = within(RENDER, "Effects.LightSwitch = function(ctx: Ctx)")
if not in_order(switch_fx, 'typeof(rocker:GetAttribute("Pivot")) == "CFrame" then', 'if ctx.state == "pristine" and switchOn[tile] then',
                "ROCKERS.show(tile, false)", "return"):
    fail("DeformationRenderer: a rocker is still thrown by the cell, or is never put back to off")
if 'heard = heard or (material == "LightSwitch" and state == "deformed" and tile:FindFirstChild("Rocker") ~= nil)' not in RENDER:
    fail("DeformationRenderer: a switch clacks as you come onto its cell, before its rocker has moved")
base = re.search(r"LightSwitch = \{.*?baseColor = Color3\.fromRGB\((\d+), (\d+), (\d+)\)", APPEAR, re.S)
if not base or max(int(base.group(1)), int(base.group(2)), int(base.group(3))) > 140:
    fail("MaterialAppearance: the board behind the switch plates is as pale as they are, and twenty switches read as one sheet")
# SOLID CHOCOLATE CRUMBLES (210), from the note of 2026-11-13: "I don't like that solid chocolate deforms like a mesh".
if re.search(r"^\tChocolateSolid = \{\n\t\t\{ sizeX", BUILDER, re.M):
    fail("ChunkBuilder: solid chocolate is a skinned plate again, and bends like rubber under a foot")
if "\t\t\tif CHUNKED[materialName] then\n\t\t\t\tattachChocSquare(tile, slab, materialName)" not in BUILDER:
    fail("ChunkBuilder: solid chocolate's cells are never given their squares")
choc_fx = within(RENDER, "Effects.ChocolateSolid = function(ctx: Ctx)")
for needle, why in (("CHOCBAR.breakUp(tile, square)", "a square that gives way is not broken into lumps"),
                    ("CHOCBAR.crack(square)", "a square stood on shows no crack"),
                    ("CHOCBAR.hide(square, false)", "a square never comes back when its cell does")):
    if needle not in choc_fx:
        fail("DeformationRenderer: " + why)
if "Effects.JelloSoda = Effects.Slime" not in RENDER:
    fail("DeformationRenderer: soda no longer wobbles like jelly (Effects.JelloSoda)")

# ===== SAND FILLS ITS HOLES, AND BUTTER IS SLOW WHERE ITS WAX IS BROKEN (the two-hundred-and-seventh pass) =====
#
# From the notes of 2026-11-06 ("improve butterwax and sand models of the chunks, and potentially work on its mechanics")
# and a capture of a sand chunk on the Sky Pools: a platform of long flat triangles. The server has filled a poured-away
# cell back in six seconds later since the hundred-and-fifty-first pass; the screen never did, so the skin stayed
# stretched down to the point the collapse had pinched it to, over a floor that was back.
collapse = within(RENDER, "local function collapseSand(tile: BasePart)", "\nend\n\n")
refill = within(RENDER, "SAND.refill = function(tile: BasePart)", "\nend\n\n")
sand_fx = within(RENDER, "Effects.KineticSand = function(ctx: Ctx)")
for where, needle, why in (
    (collapse, "SAND.holes[tile] = true", "a sand cell that pours away is not remembered as a hole, so it is never filled"),
    (collapse, "if stamp.tile == tile then", "a footprint is left hanging in the air over the hole it was pressed into"),
    (refill, "SAND.holes[tile] = nil", "a filled hole is still counted as one"),
    (refill, "sandOffset[bone] = nil", "a filled hole's sand is still held down where the collapse left it"),
    (refill, "{ Transform = CFrame.identity }", "a filled hole's sand never comes back up"),
    (refill, "for other in pairs(SAND.holes) do", "filling one hole lifts the sand of the hole beside it"),
    (sand_fx, "if SAND.holes[tile] then\n\t\t\tSAND.refill(tile)\n\t\tend",
     "the sand is never filled back in when the server gives a cell its floor back"),
):
    if needle not in where:
        fail("DeformationRenderer: " + why)
if "SAND.holes = (setmetatable({}, { __mode = \"k\" }) :: any)" not in RENDER:
    fail("DeformationRenderer: the sand's holes are kept after their chunk has gone (not weak)")
wax = MATS.get("ButterWax", "")
soft = number(wax, "softSpeed")
if soft is None:
    fail("MaterialConfig: waxed butter has no softSpeed, so broken wax is as fast as whole")
elif not 0.5 <= soft <= 0.9:
    fail("MaterialConfig: waxed butter's softSpeed is %.2f: under half speed it is honey, over nine tenths nobody feels it" % soft)
enter = within(DEFORM, "local function onPlayerEnterCell(platform: BasePart, state, cell, player: Player)")
if not in_order(enter, 'cell.broken = cell.state == "decaying" or cell.state == "deformed"', 'cell.state = "deformed"\n\t\tcell.decayTimer = 0\n\t\treplicate(platform, cell, player)',
                "applyMaterialEffectOnEnter(player, state.material, cell)"):
    fail("DeformationService: whether a butter cell's wax was already broken is not asked before the foot marks it")
for needle, why in (
    ("humanoid.WalkSpeed = Constants.DEFAULT_WALKSPEED * (if cell and cell.broken then matDef.softSpeed else 1)",
     "broken wax does not slow you, or whole wax does not give the speed back"),
    ("\tcell.broken = nil\n", "a cell put back as built is still counted as broken wax"),
):
    if needle not in DEFORM:
        fail("DeformationService: " + why)
if 'tile:SetAttribute("Soft", if ctx.state == "pristine" then nil else true)' not in within(RENDER, "Effects.ButterWax = function(ctx: Ctx)"):
    fail("DeformationRenderer: a butter cell with its wax broken is not marked soft (or stays soft once it is whole again)")
for needle, why in (
    ("local rate = if f and f.on and not f.soft then FOOTING.grip[f.on] else nil", "you still slide on butter whose wax is broken"),
    ('if under:GetAttribute("Soft") == true then', "RunFeel never looks for ground that has given"),
):
    if needle not in FEEL:
        fail("RunFeel: " + why)

# THE ENDINGS' SCORE (the two-hundred-and-eleventh pass): a bed that grows under each ending and the hit on its turn,
# both the scene's, and every level calling them.
for needle, why in (("function Cinema.score(name: string)", "has no score"),
                    ("function Cinema.climax(pitch: number?)", "has no climax"),
                    ('Cinema.sound("ScoreHit", 0.85, { keep = true, pitch = pitch or 1 })', "does not land the hit"),
                    ("\tscoring.bed = nil\n\tscoring.token += 1\n\tif current.ending", "leaves the score's bed playing after its scene")):
    if needle not in CINEMA:
        fail("Cinema " + why)
for client, beds in (("CityShoreClient", ['Cinema.score("Shore")']), ("SkyPoolsClient", []),
                     ("SunkenCityClient", ['Cinema.score("Sunken")']), ("HillHouseClient", ['Cinema.score("Hill")']),
                     ("FloodedHallsClient", ['Cinema.score("Halls")'])):
    text = read("Client", "Services", client + ".lua")
    if "climax(" not in text:
        fail("%s: its ending has no climax (the score's hit)" % client)
    for bed in beds:
        if bed not in text:
            fail("%s: its ending has no score under it" % client)
# (And the chunked chocolate builds quietly: its squares are its look, so no tile mesh is looked for.)
if "if MESHLESS[materialName] or CHUNKED[materialName] then" not in BUILDER:
    fail("ChunkBuilder: a chunked material looks for a tile mesh it never has, and warns about it every server")

if problems:
    for problem in problems:
        print("FAIL: " + problem)
    sys.exit(1)
print("feel: Cinema loads on the server's check without a LocalPlayer; no trade mark anywhere a player reads; every "
      "breaking material gives way a moment after the first foot, shaken first, its hole filled in a few seconds; "
      "slippery ground slides you, and your soles carry what you walked on (wet, greasy, sticky, gritty) until lamb's "
      "ear wipes them; the butter is bare, level with where you walk, turning up curls; bubble wrap pops under a step "
      "and in a ring under a landing, and never throws you; every keyboard a key to a cell, sculpted, close, in a "
      "colourway of its own, pressed and held and sprung; the keys over lava floating on lava, sinking under you; ten "
      "idles and ten emotes in keys, from rest to rest, never through the body, never whipping, the Aura glowing.")
