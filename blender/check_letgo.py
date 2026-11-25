"""What your test of 2026-11-04 found, held fixed (the hundred-and-seventy-eighth to eighty-second passes).

Run with plain Python from the project root:  python blender/check_letgo.py

What it holds:
  LEAVING LETS GO (178). An ending's "they have arrived" comes long after it began, and it once came after you had left:
  the flume's ride put you in the gate chamber where the halls had been (the fall through the sky) and forty seconds on
  finished your next run, the Sunken City, at its fourth checkpoint; the drain's outfall finished a run whose level was
  gone ("attempt to index nil with 'levelId'"). So every ending is handed finishFrom(levelInstance), which finishes
  nothing for a level that is gone; completeRun finishes nothing with no level or for someone the lobby has back; the
  flume, the slide and the drain move you, give you the key and say you arrived only while you are still on their level
  (stillHere), and leave no "just arrived" behind them if you are not; a ride left behind owns no fall on the next
  level (ownsFall asks InLevel first); and the scene's words go at once when the lobby takes you.
  HE IS NOT THERE (179). The Watcher ahead of you stands on a safe chunk and fades as you come; nothing of him collides,
  touches or stops the camera, whatever he is dressed in after, and once faded nothing of him is solid on your screen.
  UNDER THE SEA IS A FALL (180). The Sunken City's sea is parts: four studs under it, outside the shelters (the aquarium,
  the flat) and the water you swim in under the flat, and not in the drain, the kill plane catches you as any fall.
  NO WHITE COLUMNS (181). A trail's ribbon is never longer than 16 studs, and starts again from where you are after any
  jump no running makes (a teleport); the searchlight's haze is its first 55 studs only, thin and faint.
  THE LOBBY'S LIGHTS AND ARROWS (182). The start pad is not a slab of Neon: a green pad with a faint inlay and a low lamp;
  the chosen key's ring is half see-through and its lamps low; the walk's arrows lie on its planks, and (199) none on the
  plaza, where they lay under the spawn's camera either side of you, the wings again in brass.
  OVER AND UNDER ITSELF (197). The Sunken City's serpent goes up the street at its depth and back down it DIVE deeper,
  turning over and under itself at each end and leaning a stud to one side as it goes round: it used to turn back on
  the line it came up, and lay folded in itself, its tail out past its nose, for two thirds of its patrol. Walked in
  full on a short street and a long one, no two parts of it ever meet; a surfacing from the deeper way back reaches as
  much further along it.
  THE ARROWS LET INTO THE FLOOR (196). The lobby's arrows are solid brass in the stone, not Neon: from behind you at the
  spawn the first of them glowed out either side of you like a pair of pale wings.
  STILL, NOTHING DRAWN (195). A trail's strands sway only as far as you are travelling across the ground (none standing,
  all of it at a walk; a teleport is not travel), so standing still they draw no bars either side of you; the shop's
  try-on keeps the whole sway.

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


def code(text):
    """The text with every comment taken out, so a rule is never met by a sentence about it."""
    return "\n".join(line.split("--", 1)[0] for line in text.splitlines())


def between(text, start, end):
    at = text.find(start)
    if at < 0:
        return ""
    stop = text.find(end, at + len(start))
    return text[at:stop if stop >= 0 else len(text)]


BOOT = read("Server", "Bootstrap.server.lua")
HALLS = read("Server", "Services", "FloodedHallsService.lua")
SKY = read("Server", "Services", "SkyPoolsService.lua")
CITY = read("Server", "Services", "SunkenCityService.lua")
DIVE = read("Server", "Services", "DiveFinaleService.lua")
STORY = read("Server", "Services", "StoryService.lua")
HUB = read("Server", "Services", "HubService.lua")
CINEMA = read("Client", "Services", "Cinema.lua")
STORYC = read("Client", "Services", "StoryClient.lua")
COSMETIC = read("Client", "Services", "CosmeticsClient.lua")
SEARCH = read("Client", "Services", "SearchlightClient.lua")
SHOP = read("Shared", "ShopCatalog.lua")

# ===== 178: LEAVING LETS GO =====
finish_from = between(BOOT, "local function finishFrom(run: any, before: ((Player) -> ())?): (Player) -> ()", "\nend\n")
if not finish_from:
    fail("Bootstrap has no finishFrom, so an ending's late arrival finishes whatever run its rider is on by then")
else:
    body = code(finish_from)
    if "if run == nil or levelInstance ~= run or not finishRunFor then" not in body:
        fail("finishFrom does not refuse a level that is gone (levelInstance ~= run), so leaving in the Maw finishes "
             "the next run")
    if "before(player)" not in body or "finish(player)" not in body:
        fail("finishFrom does not do what the ending does first and then finish the run")
    if body.find("before(player)") > body.find("finish(player)"):
        fail("finishFrom finishes the run before what that ending does first (the true ending's reward)")
boot_code = code(BOOT)
if boot_code.count("finishFrom(levelInstance)") + boot_code.count("finishFrom(levelInstance,") < 5:
    fail("not every ending (the dive, the house, the slide, the drain, the flume) is handed finishFrom(levelInstance)")
if "finishRunFor(player)" in boot_code:
    fail("an ending calls finishRunFor straight, so a late arrival from a level that is gone finishes the next run")
complete = between(BOOT, "local function completeRun(player: Player)", "local state = PlayerStateService.getState(player)")
if "if not levelInstance or not HubService.isInRun(player) then" not in code(complete):
    fail("completeRun finishes with no level (the drain's outfall: 'attempt to index nil with levelId') or for someone "
         "the lobby already has back")

for name, text, level, model_alive in (
    ("FloodedHallsService", HALLS, "floodedHalls", "halls.Parent ~= nil"),
    ("SkyPoolsService", SKY, "skyPools", "model.Parent ~= nil"),
    ("SunkenCityService", CITY, "sunkenCity", None),
):
    still = between(text, "local function stillHere(): boolean", "\n\t\tend\n" if name != "SunkenCityService" else "\n\tend\n")
    if not still:
        fail("%s's ride has no stillHere, so it moves you and finishes a run after you have left" % name)
        continue
    if 'player:GetAttribute("InLevel") == "%s"' % level not in still:
        fail("%s's stillHere does not ask whether you are still on the level (InLevel)" % name)
    if model_alive and model_alive not in still:
        fail("%s's stillHere does not ask whether the level is still there" % name)
    owns = between(text, "function %s.ownsFall(player: Player): boolean" % name, "\nend\n")
    if 'if player:GetAttribute("InLevel") ~= "%s" then\n\t\treturn false' % level not in owns:
        fail("%s.ownsFall does not ask InLevel first, so a ride left behind keeps the next level's falls uncaught" % name)
dive_owns = between(DIVE, "function DiveFinaleService.ownsFall(player: Player): boolean", "\nend\n")
if 'if level == nil or level == "backRooms" then\n\t\treturn false' not in dive_owns:
    fail("DiveFinaleService.ownsFall owns falls off any level, so a dive left behind keeps the next level's falls uncaught")

ride = between(HALLS, "local connection = prompt.Triggered:Connect(function(player: Player)", "return function()")
for needle, why in (
    ("if f >= 1 or not root.Parent or not stillHere() then", "the flume's ride runs on after you have left"),
    ("if root.Parent and stillHere() and typeof(arrive) == \"CFrame\" then", "the flume waits out the Maw for someone gone"),
    ("task.wait(GATES.MAW)\n\t\t\t\t-- INTO THE GATE CHAMBER", "the Maw's wait has moved"),
    ("if stillHere() then\n\t\t\t\t\troot.AssemblyLinearVelocity = Vector3.zero\n\t\t\t\t\troot.CFrame = arrive",
     "the flume puts you in the gate chamber after you have left (the fall through the sky)"),
    ("if stillHere() then\n\t\t\t\t\t\t\tgiveKey(character)", "the gate key is given to someone who has left"),
    ("if stillHere() then\n\t\t\t\tarrivedAt[player] = os.clock()\n\t\t\t\tif onArrive then\n\t\t\t\t\tonArrive(player)",
     "the flume says you arrived (and so finishes a run) after you have left"),
    ("else\n\t\t\t\tarrivedAt[player] = nil", "a flume left behind leaves 'just arrived' on you"),
):
    if needle not in ride:
        fail(why)
slide = between(SKY, "local connection = prompt.Triggered:Connect(function(player: Player)", "return function()")
for needle, why in (
    ("not seat.Parent or not root.Parent or not stillHere() then", "the slide runs on after you have left"),
    ("local here = stillHere()\n\t\t\tif root.Parent and here then", "the slide sets you down in its pool after you left"),
    ("if here and stillHere() then\n\t\t\t\tarrivedAt[player] = os.clock()\n\t\t\t\tif onArrive then",
     "the slide says you arrived (and so finishes a run) after you have left"),
):
    if needle not in slide:
        fail(why)
drain = between(CITY, "local function ride(player: Player, root: BasePart, humanoid: Humanoid", "\nend\n")
for needle, why in (
    ("while root.Parent and stillHere() do", "the drain's ride runs on after you have left"),
    ("if root.Parent and stillHere() then\n\t\t-- Set down", "the drain sets you down at the outfall after you have left"),
    ("if not stillHere() then\n\t\tarrivedAt[player] = nil\n\t\treturn", "a drain left behind leaves 'just arrived' on you"),
    ("if onArrive and stillHere() then\n\t\tonArrive(player)", "the drain finishes a run after you left from the reveal"),
):
    if needle not in drain:
        fail(why)
cinema_finish = between(CINEMA, "function Cinema.finish(now: boolean?)", "Cinema.STAMP")
words = between(cinema_finish, "if now and current.words then", "local open = TweenInfo.new(0.8")
if not words or "TextTransparency = 1" not in words or "BackgroundTransparency = 1" not in words:
    fail("Cinema.finish does not take the scene's words away at once when the lobby has you ('The Hold' over the lobby)")
elif "TweenInfo.new(0.25)" not in words:
    fail("the scene's words take their time going when the lobby has you")

# ===== 179: HE IS NOT THERE =====
ahead = between(STORY, "local function watcherAhead(parent: Instance, cap: BasePart, before: any)", "\nend\n")
nothing = between(ahead, "local function nothing(item: Instance)", "\n\t\tend\n")
for needle in ("item.CanCollide = false", "item.CanTouch = false", "item.CanQuery = false"):
    if needle not in nothing:
        fail("the Watcher ahead of you is still solid where he stood (%s missing): the invisible wall on the safe chunk" % needle)
# HIS HUMANOID PUTS CanCollide BACK every step (tested: still 14 of 16 solid with it turned off), so what makes him
# nothing is a collision group that meets nothing.
if "local group = apparitions()" not in ahead or "if group then\n\t\t\t\t\titem.CollisionGroup = group" not in nothing:
    fail("the Watcher is not put in the group that meets nothing, and his Humanoid makes him solid again every step")
groups = between(STORY, "local function apparitions(): string?", "\nend\n")
for needle, why in (
    ('local name = "Apparitions"', "the apparitions' group is not the one the client puts him in"),
    ("physics:RegisterCollisionGroup(name)", "the apparitions' group is never made"),
    ('physics:CollisionGroupSetCollidable(name, "Default", false)', "the apparitions' group still meets everything else"),
    ("physics:CollisionGroupSetCollidable(name, name, false)", "the apparitions' group meets itself"),
):
    if needle not in groups:
        fail(why)
if STORY.find("local function apparitions(): string?") > STORY.find("local function watcherAhead("):
    fail("apparitions is written below the Watcher that uses it")
if "for _, item in ipairs(npc.model:GetDescendants()) do\n\t\t\tnothing(item)" not in ahead:
    fail("the Watcher's own parts are never made nothing")
if "npc.model.DescendantAdded:Connect(nothing)" not in ahead:
    fail("what the Watcher is dressed in after he is made is still solid")
gone = between(STORYC, "local function aheadGone(model: Instance)", "\nend\n")
if not re.search(r"if k >= 1 or not model\.Parent then\n\t+fade:Disconnect\(\)\n(?:\t+--[^\n]*\n)*\t+for _, item in ipairs\("
                 r"model:GetDescendants\(\)\) do\n\t+if item:IsA\(\"BasePart\"\) then\n\t+item\.CanQuery = false\n"
                 r"\t+pcall\(function\(\)\n\t+item\.CollisionGroup = \"Apparitions\"", gone):
    fail("once the Watcher has faded on your screen he is still solid on it, or still catches the camera")

# ===== 180: UNDER THE SEA IS A FALL =====
under = between(CITY, "function SunkenCityService.underSea(player: Player): boolean", "\nend\n")
if not under:
    fail("SunkenCityService has no underSea, so a fall into the sea goes on down into the drowned streets")
else:
    depth = re.search(r"local catch = ([0-9.]+)\n", under)
    if not depth or float(depth.group(1)) != 4:
        fail("the sea catches at a depth other than four studs under it")
    room = re.search(r"local margin = ([0-9.]+)\n", under)
    if not room or float(room.group(1)) < 6:
        fail("the shelters have too little margin round them: the aquarium's doorway, in the tower's wall, is open sea again")
    for needle, why in (
        ('player:GetAttribute("InLevel") ~= "sunkenCity" or riding[player] or arrivedAt[player]',
         "the sea catches the drain's rider, or someone not on the level"),
        ("if p.Y > watch.water - catch then", "the sea catches you above its own surface"),
        ("for _, box in ipairs(watch.shelters) do", "the sea catches you in the aquarium or the flat"),
        ("local half = box.Size / 2 + Vector3.new(margin, margin, margin)",
         "the sea catches you in the aquarium's doorway, between the tower and the tunnel (190)"),
        ("for _, fill in ipairs(swimWater.fills) do", "the sea catches you swimming in the flooded floor under the flat"),
    ):
        if needle not in under:
            fail(why)
if "swimWater.watch = { shelters = shelters, water = waterLevel }" not in CITY:
    fail("the drain's attach never tells underSea where the shelters and the water are")
if "SunkenCityService.clearWater()\n\t\tswimWater.watch = nil" not in CITY:
    fail("the level's undo leaves underSea watching a sea that is gone")
if not re.search(r"local fell = hrp\.Position\.Y < killY\n\t+or \(SunkenCityService ~= nil and SunkenCityService\.underSea ~= nil "
                 r"and SunkenCityService\.underSea\(player\)\)\n\t+if fell\n", BOOT):
    fail("the kill plane never asks underSea, so a fall into the Sunken City's sea is never caught")

# ===== 181: NO WHITE COLUMNS =====
if "band.MaxLength = 16" not in code(SHOP):
    fail("a trail's ribbon has no greatest length, so a fall draws a white pillar a hundred studs up")
jump = between(COSMETIC, "local lastAt = w.last", "\n\t\t\tend\n\t\t\tend\n")
if "local JUMPED = 12" not in COSMETIC:
    fail("CosmeticsClient has no JUMPED, the move no running makes")
if not ("(root.Position - lastAt).Magnitude > JUMPED" in jump and "child:Clear()" in jump and 'child:IsA("Trail")' in jump):
    fail("a teleport still draws a ribbon from where you were to where you are (the white bar across the level)")
if "local HAZE_LONGEST = 55" not in SEARCH:
    fail("the searchlight's haze is not cut to its first 55 studs")
search_code = code(SEARCH)
if "beam.Attachment1 = haze" not in search_code or "beam.Attachment1 = far" in search_code:
    fail("the searchlight's haze runs the whole way to the water again (the white column across the harbour)")
if "hazeEnd.Position = Vector3.new(0, 0, -math.min(long, HAZE_LONGEST))" not in search_code:
    fail("the haze's end is never kept short of the water as the lamp turns")
fade = between(SEARCH, "local function fade(rain: number): NumberSequence", "\nend\n")
near = re.search(r"local near = ([0-9.]+)", fade)
if not near or float(near.group(1)) < 0.85:
    fail("the searchlight's haze is near-opaque at the lamp again")

# ===== 182: THE LOBBY'S LIGHTS AND ARROWS =====
hub_code = code(HUB)
start = between(HUB, 'startPad.Name = "StartPad"', 'makeSign(startPad, "START", "step on to begin")')
if "startPad.Material = Enum.Material.Neon" in code(start) or "startPad.Material = Enum.Material.SmoothPlastic" not in start:
    fail("the start pad is a slab of Neon again, the brightest thing in the lobby")
inlay = re.search(r"startInlay\.Transparency = ([0-9.]+)", start)
if not inlay or float(inlay.group(1)) < 0.5:
    fail("the start pad's inlay is near-solid light")
glow = re.search(r"startLamp\.Brightness = ([0-9.]+)", start)
if not glow or float(glow.group(1)) > 0.8:
    fail("the start pad's lamp is too bright")
halo = between(HUB, "local function setHighlight(pad: BasePart, on: boolean)", "\nend\n")
ring = re.search(r"part\.Transparency = if on then ([0-9.]+) else 1", halo)
if not ring or float(ring.group(1)) < 0.5:
    fail("the chosen key's ring is a white-hot disc again")
lamp = re.search(r"glow\.Brightness = ([0-9.]+)", halo)
if not lamp or float(lamp.group(1)) > 0.9:
    fail("the chosen key's lamp is too bright")
beam = re.search(r"beam\.Brightness = ([0-9.]+)", halo)
if not beam or float(beam.group(1)) > 0.6:
    fail("the chosen key's upward light is too bright")
arrows = between(HUB, "local SPREAD, DEPTH = 3.4, 2.4", "-- MOTES.")
for needle, why in (
    ("{ z = gatesWalk.Z + 8, y = 1.09, count = 5 }", "the walk's arrows are not on its planks"),
    ("for index = 1, run.count do", "each run of arrows is not its own length"),
):
    if needle not in arrows:
        fail(why)
# 199: none on the plaza. Its three lay 7.6 to 12.4 studs ahead of the spawn, where the camera behind you puts your hips,
# and stuck out either side of you, eight and a half studs wide: the wings again, in brass.
runs = re.search(r"for _, run in ipairs\(\{ (.*) \}\) do", arrows)
if not runs:
    fail("the lobby's arrows are not laid in runs")
else:
    if runs.group(1).count("{ z = ") != 1 or "plaza" in runs.group(1) or "AT.spawn" in runs.group(1):
        fail("arrows on the plaza again, under the spawn's camera either side of you")
    elif "plazaFirst" in code(arrows) or "AT.spawn.Z -" in code(arrows):
        fail("an arrow is laid off the spawn again, under the camera either side of you")

# ===== 191: THE CHOCOLATE AND THE KEYS OVER LAVA (your note of 2026-11-05) =====
CONFIG = read("Shared", "MaterialConfig.lua")
RENDER = read("Client", "Services", "DeformationRenderer.lua")


def config_of(name):
    return between(CONFIG, "\t%s = {" % name, "\n\t},")


# (246: warm chocolate keeps its floor while you walk and melts through only under a foot that stands.)
for name, longest in (("ChocolateSolid", 0.8),):
    crumble = re.search(r"crumbleAfter = ([0-9.]+)", config_of(name))
    if not crumble or float(crumble.group(1)) > longest:
        fail("%s takes too long to break again (more than %.1f s after a foot)" % (name, longest))
melt = re.search(r"dissolveTime = ([0-9.]+)", config_of("Chocolate"))
if not melt or float(melt.group(1)) > 1.0:
    fail("the warm chocolate melts away slower than it breaks")
bob = re.search(r"local t = now \* ([0-9.]+) \+ key\.phase\n\t+cap\.CFrame = \(rest :: CFrame\) \* CFrame\.new\(0, ([0-9.]+) \* math\.sin\(t\), 0\)",
                RENDER)
if not bob or float(bob.group(1)) < 2 or float(bob.group(2)) < 0.15:
    fail("the keys over lava hardly move on the lava again (they ride it a fifth of a stud, twice as fast)")
for tween, longest in (("RISE", 0.4), ("BACK", 0.55)):
    found = re.search(r"%s = TweenInfo\.new\(([0-9.]+)," % tween, RENDER)
    if not found or float(found.group(1)) > longest:
        fail("a key over lava comes back up slowly again (%s)" % tween)

# ===== 193: THE NEEDOH, MET (your note of 2026-11-05: "what does needoh chunk do other than displace") =====
needoh = config_of("Needoh")
for key, test, why in (
    ("chargeAfter", lambda v: v <= 0.15, "the Needoh waits too long to start giving, so a walker never meets its squeeze"),
    ("chargeTime", lambda v: v <= 0.8, "the Needoh takes too long to fill"),
    ("chargeJump", lambda v: 2.4 <= v <= 3.0, "the Needoh's spring is too small to notice, or throws you off the route"),
):
    found = re.search(r"%s = ([0-9.]+)," % key, needoh)
    if not found or not test(float(found.group(1))):
        fail(why)

# ===== 195: STILL, NOTHING DRAWN (the pale bars either side of you standing in the lobby) =====
strands = re.search(r"local STRANDS = \{ still = ([0-9.]+), moving = ([0-9.]+), ease = ([0-9.]+), jump = ([0-9.]+) \}", COSMETIC)
if not strands:
    fail("CosmeticsClient has no STRANDS, how far a trail's strands sway at each pace")
else:
    still, moving, ease, leap = (float(strands.group(n)) for n in (1, 2, 3, 4))
    if still < 0.5 or moving <= still or moving > 16:
        fail("a trail's strands sway from %s to %s studs a second, so they sway standing still or never fully running"
             % (still, moving))
    if ease < 2:
        fail("a trail's sway follows your pace %s times a second, so it goes on long after you stop" % ease)
    if leap < 30:
        fail("a trail's strands count a run at %s studs a second as a teleport" % leap)
mover = between(COSMETIC, "local function moveStrands(w: Wearer, root: BasePart, now: number)", "\nend\n")
for needle, why in (
    ('local trying = root:FindFirstChild("ShopPreviewTrailTop") ~= nil', "the shop's try-on is swayed by your pace, so a trail cannot be seen there"),
    ("local sway = if trying then 1 else math.clamp((w.pace - STRANDS.still) / (STRANDS.moving - STRANDS.still), 0, 1)",
     "a trail's strands sway as far standing still as running (the pale bars either side of you)"),
    ("local centre = s.at:Lerp(strandPlace(s, now), sway)", "a trail's strands are moved their whole way whatever your pace"),
):
    if needle not in mover:
        fail(why)
pacing = between(COSMETIC, "local lastAt = w.last", "moveStrands(w, root, now)")
if not re.search(r"local pace = if lastAt and dt > 0 then Vector3\.new\(root\.Position\.X - lastAt\.X, 0, "
                 r"root\.Position\.Z - lastAt\.Z\)\.Magnitude / dt else 0", pacing):
    fail("a wearer's pace is not their travel across the ground this frame")
if "if pace > STRANDS.jump then 0 else math.min(pace, STRANDS.moving)" not in pacing:
    fail("a teleport counts as running, so the strands sway for a moment wherever you are set down")

# ===== 197: OVER AND UNDER ITSELF (the serpent folded flat on itself for two thirds of its patrol) =====
PATH = read("Shared", "SunkenPath.lua")
path_numbers = {name: float(value) for name, value in re.findall(r"^SunkenPath\.([A-Z_]+) = ([\d.]+)", PATH, re.M)}
dive, lean_most = path_numbers.get("DIVE"), path_numbers.get("TURN_SIDE")
if dive is None or lean_most is None:
    fail("SunkenPath has no DIVE or TURN_SIDE, so the serpent turns back on the line it came up")
else:
    if dive < 18:
        fail("the serpent comes back only %s deeper, less than its own height, so its halves still pass through "
             "each other at each end" % dive)
    if not 0 < lean_most <= 1.2:
        fail("the serpent leans %s to one side through a turn: none flips it over at the bottom, more puts it into "
             "the dry flat (two studs of room)" % lean_most)
    # 199, seen in play: a turn no wider round than the body is thick pinches the inside of the bend to nothing, and
    # the skin pulls into a flat web across the loop. Its widest radius (MONSTER_GIRTH), with the fins on it (two
    # fifths more), and ten studs inside that.
    girth = re.search(r"local MONSTER_GIRTH = ([0-9.]+)", read("Server", "Services", "SunkenCityService.lua"))
    if not girth:
        fail("SunkenCityService gives the serpent no girth, so nothing says how wide its turns must be")
    elif dive / 2 < float(girth.group(1)) * 1.4 + 10:
        fail("the serpent turns %.0f studs round, no wider than it is thick with its fins (%.0f): its skin pulls into a "
             "web across the loop" % (dive / 2, float(girth.group(1)) * 1.4))
    along = between(PATH, "function SunkenPath.along(b: Brief, t: number, behind: number): (number, number, number)", "\nend\n")
    for needle, why in (
        ("local r = SunkenPath.DIVE / 2", "the serpent's turns are not half circles DIVE across"),
        ("return r + within, 0, 0", "the way up the street is not at the serpent's own depth"),
        ("return span - r - (within - run - turn), 2 * r, 0", "the way back down the street is not DIVE deeper"),
        ("return span - r + r * math.sin(a), r - r * math.cos(a), SunkenPath.TURN_SIDE * math.sin(a)",
         "the far turn is not over and under, leaning"),
        ("return r - r * math.sin(a), r + r * math.cos(a), SunkenPath.TURN_SIDE * math.sin(a)",
         "the near turn is not under and over, leaning"),
    ):
        if needle not in along:
            fail(why)
    placing = between(PATH, "local function placed(b: Brief, t: number, behind: number, into: number?, spot: Vector3?): Vector3", "\nend\n")
    for needle, why in (
        ("local s, drop, lean = SunkenPath.along(b, t, behind)", "the body is not laid where the patrol says, deeper and leaning"),
        ("local y = b.waterY - b.depth - drop + ", "the way back is drawn at the same depth as the way up"),
        ("local here = at + side * (wander + sway + lean)", "the serpent does not lean through its turns"),
        ("local deeper = 1 + drop / math.max(1, b.depth - SunkenPath.CREST)", "a surfacing from the deeper way back rises "
         "as steeply as one from its depth, a spike out of the dark"),
        ("local reach = math.max(0, 1 - near / (SunkenPath.CREST_REACH * deeper))", "the heave's reach is not as much "
         "further as it has to come"),
    ):
        if needle not in placing:
            fail(why)

    # The patrol, walked: nowhere along it do two parts of the body (three joints or more apart) come within its
    # thickness of each other, on the shortest street a run lays (about 496 studs, so a 296-stud patrol once the
    # harbour's 200 is kept clear) and on a long one; and it never jumps. (SunkenPath's floor of 60 is for a street
    # too short to be a run, where a loop shorter than the serpent has to cross itself.)
    def walk_along(span, travelled):
        r = dive / 2
        run, turn = span - 2 * r, math.pi * r
        within = travelled % (2 * run + 2 * turn)
        if within < run:
            return r + within, 0.0
        if within < run + turn:
            a = (within - run) / r
            return span - r + r * math.sin(a), r - r * math.cos(a)
        if within < 2 * run + turn:
            return span - r - (within - run - turn), 2 * r
        a = (within - 2 * run - turn) / r
        return r - r * math.sin(a), r + r * math.cos(a)

    for span in (296.0, 450.0, 640.0):
        loop = 2 * (span - dive) + 2 * math.pi * dive / 2
        worst = None
        step = 0.0
        while step < loop:
            joints = [walk_along(span, step - behind) for behind in range(0, 199, 11)]
            for i in range(len(joints)):
                for j in range(i + 3, len(joints)):
                    (si, di), (sj, dj) = joints[i], joints[j]
                    if abs(si - sj) < 16 and abs(di - dj) < 16:
                        worst = worst or (step, i, j)
            here, ahead = walk_along(span, step), walk_along(span, step + 1)
            if math.hypot(ahead[0] - here[0], ahead[1] - here[1]) > 1.05:
                fail("the serpent's patrol jumps at %.0f studs along it (a %.0f street)" % (step, span))
                break
            step += 1.0
        if worst:
            fail("on a %.0f-stud patrol the serpent's joints %d and %d pass through each other %.0f studs along it"
                 % (span, worst[1] + 1, worst[2] + 1, worst[0]))

    # ===== 202: ROLLED THROUGH ITS TURNS (seen in play: a flat striped web across the loop) =====
    # Each bone was turned keeping up up, heading first; where the body points straight down, halfway round a turn, one
    # bone's heading and the next were half a turn apart, and the skin drawn from both collapsed flat. SeaRig.follow now
    # takes SunkenPath.across, the street's side at each joint in a turn, and rolls the back toward it as far as the
    # bone points up or down.
    RIG = read("Shared", "SeaRig.lua")
    CITY_CLIENT = read("Client", "Services", "SunkenCityClient.lua")
    rolled_body = between(RIG, "local function rolled(a: Vector3, b: Vector3, across: Vector3): CFrame", "\nend\n")
    across_body = between(PATH, "function SunkenPath.across(", "\nend\n")
    for needle, why, where in (
        ("local up = Vector3.yAxis - b * b.Y + across * math.abs(b.Y)", "the serpent's bones do not roll through a turn",
         rolled_body),
        ("return frameAlong(b, up) * frameAlong(a, Vector3.yAxis):Inverse()", "a bone is not laid along its joints with "
         "its back where the roll puts it", rolled_body),
        ("turn = rolled(from.Unit, to.Unit, across[index] or Vector3.zero)", "a chain given an across is not rolled", RIG),
        ("local s, _, lean = SunkenPath.along(b, t, first + (index - 1) * spacing)", "across is not worked out at each "
         "joint", across_body),
        ("if lean ~= 0 then", "across is given on the straights too, so the body banks wherever it climbs", across_body),
        ("out[index] = Vector3.new(-dir.Z, 0, dir.X)", "across is not the street's own side", across_body),
        ("SeaRig.follow(mesh.chain, mesh.rig.rest, joints, true, mesh.posed, mesh.across)", "the serpent is posed "
         "without its across, so it flips half over at the bottom of each turn", CITY_CLIENT),
        ("mesh.across[index] = frame:VectorToObjectSpace(acrossWorld[index])", "the serpent's across is not in its "
         "part's own space", CITY_CLIENT),
    ):
        if needle not in where:
            fail(why)

    def cross(a, b):
        return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])

    def unit(a):
        m = math.sqrt(sum(x * x for x in a))
        return tuple(x / m for x in a)

    def frame_along(d, up):
        right = cross(d, up)
        if math.sqrt(sum(x * x for x in right)) < 1e-4:
            right = cross(d, (1.0, 0.0, 0.0) if abs(d[0]) < 0.9 else (0.0, 0.0, 1.0))
        right = unit(right)
        return right, cross(right, d), d

    # The patrol walked again, every bone laid as SeaRig lays it: no bone turned more than 60 degrees from the next
    # (the flip was 180), on the streets above. Along the street is x, up y, the street's across z.
    worst_turn = 0.0
    for span in (296.0, 450.0):
        loop = 2 * (span - dive) + 2 * math.pi * dive / 2
        step = 0.0
        while step < loop:
            joints = [walk_along(span, step - behind) for behind in range(0, 199, 11)]
            frames = []
            for i in range(len(joints) - 1):
                (s0, d0), (s1, d1) = joints[i], joints[i + 1]
                d = unit((s1 - s0, -(d1 - d0), 0.0))
                turning = 1e-6 < d0 < dive - 1e-6
                up = (-d[0] * d[1], 1.0 - d[1] * d[1], (abs(d[1]) if turning else 0.0) - d[2] * d[1])
                frames.append(frame_along(d, up))
            for a, b in zip(frames, frames[1:]):
                trace = sum(a[k][0] * b[k][0] + a[k][1] * b[k][1] + a[k][2] * b[k][2] for k in range(3))
                worst_turn = max(worst_turn, math.degrees(math.acos(max(-1.0, min(1.0, (trace - 1) / 2)))))
            step += 4.0
    if worst_turn > 60:
        fail("one of the serpent's bones turns %.0f degrees from the next in its turn over and under itself, "
             "so the skin between them collapses into a web" % worst_turn)

# ===== 196: THE ARROWS LET INTO THE FLOOR (the pale wings either side of you at the spawn) =====
arrows = between(HUB, 'local chevron = propAt("Hub_Chevron", tip, folder, math.pi)', "\n\t\tend\n\tend\n")
if not arrows:
    fail("the lobby's arrows are not laid from Hub_Chevron")
elif "Enum.Material.Neon" in code(arrows):
    fail("the lobby's arrows glow again, the pale wings either side of you at the spawn")
else:
    for needle, why in (
        ("chevron.Material = Enum.Material.Metal", "the lobby's arrows are not brass let into the stone"),
        ("chevron.Transparency = 0\n", "the lobby's arrows are see-through"),
        ("chevron.Color = PALETTE.brass", "the lobby's arrows are not brass-coloured"),
        ("bar.Material = Enum.Material.Metal", "a place without the arrow mesh has glowing bars for arrows"),
    ):
        if needle not in arrows:
            fail(why)
if "\tbrass = Color3.fromRGB(184, 146, 82),\n" not in HUB:
    fail("the lobby's palette has no brass for its arrows")

if problems:
    print("LET GO PROBLEMS (%d):" % len(problems))
    for problem in problems:
        print("  " + problem)
    sys.exit(1)
print("let go: an ending finishes only the level it came from, and no ride, slide or drain moves you or finishes a run "
      "once you have left; the Watcher is nothing to walk into; under the Sunken City's sea is a fall; no ribbon over 16 "
      "studs or drawn across a teleport, the searchlight's haze 55 studs and faint; the start pad and the chosen ring soft, "
      "the walk's arrows on its planks and none under you on the plaza, brass let into the stone; a trail's strands still when you are; the serpent "
      "over and under itself at each end, never folded in itself.")
