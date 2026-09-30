"""The story (Harrow Bay, 14 August) and the scenes the first two levels end on.

Run with plain Python from the project root:  python blender/check_story.py

The story is told by people standing on three levels, built by four services, and the endings are
drawn by three clients that share one camera library. None of that can be seen without Studio, so
this holds the parts that are easy to lose when one file is pasted and another is not:

  EVERYONE WHO IS STOOD UP HAS SOMETHING TO SAY. Every Townsfolk.spawn names someone in LINES
  (except the Watcher, who has no face and says nothing), and the story's thread (the key holder,
  the gates, the day) runs through each level's people.
  THE WORDS ARE CLEAN. No double hyphen or dash in anything a player reads: the lines, the shouts,
  the reactions, the openings, the captions, the signs and the time card.
  EACH LEVEL OPENS ON THE SAME DAY, later each time, and the last room says who never came.
  THE ENDINGS ARE WIRED. City Shore's dive (DiveCinema, both ends), the Sky Pools' slide (the pose for
  everyone, the scene for the rider, the camera always given back), and Bootstrap: the remote made,
  the story staged, the new client started, and six seconds on LEVEL COMPLETE before the lobby.
  THE PEOPLE STAND ON THINGS. A sitter's feet are the top of what they sit on, and Okafor's are the
  lounger cushion's.

Exits non-zero on any failure.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "src"


def read(*parts):
    path = SRC.joinpath(*parts)
    return path.read_text(encoding="utf-8") if path.exists() else None


TOWNS = read("Server", "Services", "Townsfolk.lua")
STORY = read("Server", "Services", "StoryService.lua")
POSES = read("Shared", "Poses.lua")
CINEMA = read("Client", "Services", "Cinema.lua")
SHORE = read("Client", "Services", "CityShoreClient.lua")
DIVE = read("Server", "Services", "DiveFinaleService.lua")
SKY = read("Server", "Services", "SkyPoolsService.lua")
SKY_CLIENT = read("Client", "Services", "SkyPoolsClient.lua")
SUNKEN = read("Server", "Services", "SunkenCityService.lua")
SUNKEN_CLIENT = read("Client", "Services", "SunkenCityClient.lua")
BOOT = read("Server", "Bootstrap.server.lua")
CLIENT_BOOT = read("Client", "Bootstrap.client.lua")

problems = []


def fail(message):
    problems.append(message)


missing = [name for name, text in (
    ("ServerScriptService/Services/Townsfolk", TOWNS), ("ServerScriptService/Services/StoryService", STORY),
    ("ReplicatedStorage/Shared/Poses", POSES), ("StarterPlayerScripts/Services/Cinema", CINEMA),
    ("StarterPlayerScripts/Services/CityShoreClient", SHORE), ("DiveFinaleService", DIVE),
    ("SkyPoolsService", SKY), ("SkyPoolsClient", SKY_CLIENT), ("SunkenCityService", SUNKEN),
    ("SunkenCityClient", SUNKEN_CLIENT), ("the server Bootstrap", BOOT), ("the client Bootstrap", CLIENT_BOOT),
) if text is None]
if missing:
    print("FAIL: missing " + ", ".join(missing))
    sys.exit(1)


def table_block(source, header):
    """The body of a `local NAME ... = {` table, up to its closing brace at the left margin."""
    start = source.find(header)
    if start < 0:
        return None
    body = source[start:]
    end = body.find("\n}")
    return body[:end] if end > 0 else None


def strings(text):
    return re.findall(r'"((?:[^"\\\n]|\\.)*)"', text)


def by_person(block):
    """{ name: [lines] } from a LINES or SHOUTS table: `\tName = {` opens a person, `\t},` closes one."""
    people = {}
    current = None
    for line in block.splitlines():
        head = re.match(r"^\t([A-Z][A-Za-z]*) = \{(.*)$", line)
        if head:
            current = head.group(1)
            people[current] = strings(head.group(2))
            if head.group(2).rstrip().endswith("},"):
                current = None
            continue
        if current and line.strip().startswith("},"):
            current = None
            continue
        if current:
            people[current].extend(strings(line))
    return people


# ===================================================================== who is there, and what they say

lines_block = table_block(TOWNS, "local LINES:")
shouts_block = table_block(TOWNS, "local SHOUTS:")
reactions_block = table_block(TOWNS, "local REACTIONS:")
openings_block = table_block(STORY, "local OPENINGS:")
if not (lines_block and shouts_block and reactions_block and openings_block):
    print("FAIL: this check can no longer read Townsfolk's LINES, SHOUTS or REACTIONS, or StoryService's OPENINGS")
    sys.exit(1)
LINES = by_person(lines_block)
SHOUTS = by_person(shouts_block)

SILENT = {"Watcher"}  # faceless, far off, and says nothing: that is the point of him
spawned = {}
for label, text in (("DiveFinaleService", DIVE), ("SkyPoolsService", SKY), ("StoryService", STORY),
                    ("SunkenCityService", SUNKEN)):
    for name in re.findall(r'Townsfolk\.spawn\([^,]+, "([A-Za-z]+)"', text):
        spawned.setdefault(name, label)
for name, where in sorted(spawned.items()):
    if name in SILENT:
        continue
    if name not in LINES:
        fail("%s stands %s up, and Townsfolk has nothing for them to say" % (where, name))
    elif len(LINES[name]) < 3:
        fail("%s has %d line(s); a person you can talk to needs at least three" % (name, len(LINES[name])))
for name in ("Sal", "Pip", "Maren", "Dev", "Okafor", "Rudy", "Attendant", "Fisherman", "Venn", "Tobi", "Barlow"):
    if name not in spawned:
        fail("nobody stands %s up any more, and the story has a hole where they were" % name)
for name in ("Maren", "Rudy"):
    if len(SHOUTS.get(name, [])) < 2:
        fail("%s has nothing to shout when someone goes" % name)
    if 'Townsfolk.shout("%s")' % name not in (DIVE if name == "Maren" else SKY):
        fail("%s's shout is never called when someone goes" % name)

# THE THREAD: at least two people on every level know about the key holder, so it is heard whoever
# you happen to talk to.
for level, names in (("City Shore", ("Sal", "Pip", "Maren")), ("the Sky Pools", ("Dev", "Okafor", "Rudy")),
                     ("the Sunken City", ("Attendant", "Fisherman")), ("the Corporation Baths", ("Venn", "Tobi", "Barlow"))):
    knowing = [name for name in names
               if re.search(r"\bkeys?\b|pump man|key holder", " ".join(LINES.get(name, [])).lower())]
    if len(knowing) < 2:
        fail("only %s on %s mention(s) the key holder; the story needs at least two people on each level"
             % (", ".join(knowing) or "nobody", level))

# ===================================================================== the words are clean

readable = []
notes_block = table_block(STORY, "local NOTES:")
if not notes_block:
    fail("this check can no longer read StoryService's NOTES, the things left lying about to read")
    notes_block = ""
for block in (lines_block, shouts_block, reactions_block, openings_block, notes_block):
    readable.extend(strings(block))
# And what is written on the walls: signs, notes, the culvert's writing.
for text in (SUNKEN, SKY, DIVE):
    for call in re.findall(r'label\([^,\n]+, Enum\.NormalId\.\w+, ("[^"\n]*")', text):
        readable.extend(strings(call))
HALLS_CLIENT = read("Client", "Services", "FloodedHallsClient.lua") or ""
for text in (SHORE, SKY_CLIENT, SUNKEN_CLIENT, HALLS_CLIENT):
    for call in re.findall(r"Cinema\.caption\(([^)]*)\)", text):
        readable.extend(strings(call))

# THE KEEPSAKES: every material is something somebody in Harrow Bay was holding when the water came.
# One for every material, with a thing, a place and a line. Since the eighteenth pass they are THINGS
# lying in the nooks off the route, picked up into the journal, not cards that come up on every step.
KEEPSAKES = read("Shared", "Keepsakes.lua") or ""
JOURNAL = read("Client", "Services", "JournalService.lua") or ""
INTERACT_EARLY = read("Server", "Services", "Interactables.lua") or ""
SCREEN = read("Client", "Services", "ScreenEffects.lua") or ""
MATERIAL_CONFIG = read("Shared", "MaterialConfig.lua") or ""
materials_block = table_block(MATERIAL_CONFIG, "local Materials:")
materials = set(re.findall(r"^\t([A-Z][A-Za-z]*) = \{$", materials_block or "", re.M))
kept = dict((name, body) for name, body in re.findall(r"^\t([A-Z][A-Za-z]*) = \{\n(.*?)\n\t\},", KEEPSAKES, re.M | re.S))
if not materials:
    fail("this check can no longer read the materials in MaterialConfig")
for name in sorted(materials):
    body = kept.get(name)
    if body is None:
        fail("%s is a material with no keepsake: nobody in Harrow Bay was holding it" % name)
        continue
    for field in ("thing", "from", "line"):
        if not re.search(r"\b%s = \"[^\"]+\"" % field, body):
            fail("%s's keepsake has no %s" % (name, field))
    readable.extend(strings(body))
for name in sorted(set(kept) - materials):
    fail("the keepsake %s is for a material that does not exist" % name)
if "service.touched(materialName)" in SCREEN or (SRC / "Client" / "Services" / "KeepsakeService.lua").exists():
    fail("a keepsake's card comes up when you step on a material again: they are picked up now (JournalService)")
for needle, why in (
    ("function Interactables.keepsake(", "no keepsake is ever a thing you can pick up"),
    ('Interactables.take(player, { title = entry.thing, body = entry.line }, model, "keepsake"',
     "picking a keepsake up never puts it in the journal"),
    ("function Interactables.take(", "nothing you pick up goes into the journal"),
):
    if needle not in INTERACT_EARLY:
        fail(why)
if "function Interactables.read(" in INTERACT_EARLY or "gui.Name = \"StoryNote\"" in INTERACT_EARLY:
    fail("a note is put on the screen over the level again: it goes into the journal, to be read when chosen")
for needle, why in (
    ('kind == "journal"', "the journal never hears what was taken"),
    ('kind == "hide"', "what you take stays on your screen"),
    ("dim.Modal = true", "the journal does not free the mouse, so it cannot be used in first person"),
    ("while (Cinema and Cinema.active()) or isOpen do", "the corner line comes up in the middle of a scene"),
    ("Enum.KeyCode.J", "nothing opens the journal from the keyboard"),
    ("hide(if typeof(data.object)", "what you pick up is not taken off your screen"),
):
    if needle not in JOURNAL:
        fail("JournalService: " + why)
card = re.search(r'\("(KEY HOLDER[^"]*)"\):format\(', SUNKEN)
if not card:
    fail("the time card in the pumping station no longer says KEY HOLDER")
else:
    readable.append(card.group(1))
    if "NOT CLOCKED IN" not in card.group(1) or "14 AUG" not in card.group(1):
        fail("the time card no longer says the day, or that the key holder never clocked in")
    if "player.DisplayName" not in SUNKEN[card.end():card.end() + 80]:
        fail("the time card is not made out in the player's name, which is the reveal")
for text in readable:
    if "--" in text or "—" in text or "–" in text:
        fail("a line a player reads has a dash in it: %r" % text)

# ===================================================================== the same day, later each time

openings = dict((int(k), strings(v)) for k, v in re.findall(r"\[(\d)\] = \{([^}]*)\}", openings_block))
for level in (1, 2, 3, 4):
    if level not in openings or len(openings[level]) != 2:
        fail("level %d has no opening words (a place and a line)" % level)
for level in (1, 2, 3):
    if level in openings and "14 August" not in openings[level][1]:
        fail("level %d's opening is not on 14 August, the day the whole story is" % level)
if "pcall(StoryService.opening, player, level.levelId)" not in STORY:
    fail("StoryService.stage never shows the opening words")
for needle, why in (
    ("local function sal(", "StoryService no longer builds Sal and her cart"),
    ("local function pip(", "StoryService no longer builds Pip and her sandcastle"),
    ("pcall(sal, folder, first)", "Sal is never stood on City Shore"),
    ("pcall(pip, folder, mid)", "Pip is never stood on City Shore"),
    ('folder.Parent = levels', "City Shore's people are not put in Workspace.Levels, so they outlive the run"),
):
    if needle not in STORY:
        fail(why)

# ===================================================================== the endings are wired

for needle, why in (
    ("function Cinema.begin", "Cinema has no begin"), ("function Cinema.finish", "Cinema has no finish"),
    ("function Cinema.point", "Cinema has no point"), ("function Cinema.clear", "Cinema has no clear"),
    ("function Cinema.caption", "Cinema has no caption"), ("function Cinema.active", "Cinema has no active"),
):
    if needle not in CINEMA:
        fail(why)
for needle in ("function Poses.joints", "function Poses.drive", "function Poses.turn", "function Poses.isR6",
               "function Poses.weight", "function Poses.dive", "function Poses.sled", "function Poses.flail"):
    if needle not in POSES:
        fail("ReplicatedStorage/Shared/Poses has no %s" % needle.split(".")[-1])

# City Shore: the server tells, the client draws.
for needle, why in (
    ('remote:FireAllClients("dive", player, workspace:GetServerTimeNow(), finale.circle.Y, tip)',
     "DiveFinaleService never says someone has gone off the board"),
    ('remote:FireAllClients("splash", player,', "DiveFinaleService never says where the diver went in"),
    ("CFrame = CFrame.new(surface) * turn", "the last of the fall stands the diver back up, so they go in feet first"),
    ("CFrame = CFrame.new(rest) * turn", "the sink under the water stands the diver back up"),
    ('Townsfolk.spawn(model, "Maren"', "Maren is not on the dive deck"),
):
    if needle not in DIVE:
        fail(why)
for needle, why in (
    ('kind == "dive"', "CityShoreClient never hears the dive"),
    ('kind == "splash"', "CityShoreClient never hears the splash"),
    ("Poses.dive(", "nobody is posed for the dive"),
    ("Cinema.begin()", "the dive is never played as a scene"),
    ("Cinema.finish(now)", "the dive's scene never gives the camera back"),
    ("humanoid.PlatformStand = false", "the diver is left lying down after the scene"),
    ("pcall(endScene, true)", "a failure in the dive's scene keeps the camera"),
    ("Cinema.done()", "the dive never says its story is told, so the lobby waits the full minute"),
    ("root.CFrame = CFrame.new(Vector3.new(from.X, y, from.Z)) * (root.CFrame - root.CFrame.Position)",
     "the last of the fall arrives in the server's steps instead of smoothly"),
):
    if needle not in SHORE:
        fail(why)

# The Sky Pools: the pose for everyone, the scene for the rider.
for needle, why in (
    ('remote:FireAllClients("pose", player, startedAt, seconds + SkyPath.SKIM_SECONDS)', "nobody else sees the rider's arms up"),
    ("pcall(people, model, mouth)", "nobody is stood up on the Sky Pools"),
    ("table.clear(STAGE.walks)", "the places people stand are kept from the last build"),
):
    if needle not in SKY:
        fail(why)
for needle, why in (
    ('if first == "pose" then', "SkyPoolsClient takes the pose message for a sled"),
    ('typeof(sled) == "Instance"', "SkyPoolsClient calls IsA on whatever it is sent"),
    ("Poses.sled(", "nobody is posed on the slide"),
    ("Cinema.begin()", "the slide is never played as a scene"),
    ("pcall(scene.shoot, current, u)", "the slide's scene never moves the camera"),
):
    if needle not in SKY_CLIENT:
        fail(why)
if SKY_CLIENT.count("Cinema.finish()") < 2:
    fail("the slide's scene does not give the camera back both after the landing and if the sled goes")

# Okafor sits on the cushion: a sitter's feet are the top of what they sit on.
cushion = re.search(r'seat\(parent, "LoungerCushion", Vector3\.new\([\d.]+, ([\d.]+), [\d.]+\),\s*'
                    r'at \* CFrame\.new\(0, ([\d.]+),', SKY)
sits = re.search(r"local seatAt = bed \* CFrame\.new\([-\d.]+, ([\d.]+),", SKY)
if not cushion or not sits:
    fail("this check can no longer read the lounger's cushion or where Okafor sits on it")
else:
    top = float(cushion.group(2)) + float(cushion.group(1)) / 2
    if abs(float(sits.group(1)) - top) > 0.15:
        fail("Okafor sits %.2f over the deck and the cushion's top is %.2f: she is in the lounger or over it"
             % (float(sits.group(1)), top))

# Bootstrap: the remote, the story, the client, and the time on LEVEL COMPLETE.
for needle, why in (
    ('ensureRemoteEvent(remoteEventsFolder, "DiveCinema")', "Bootstrap never makes the DiveCinema remote"),
    ('Services:WaitForChild("StoryService", 5)', "Bootstrap never looks for StoryService (or waits forever for it)"),
    ("pcall(StoryService.stage, level, built, players)", "Bootstrap never stages the story"),
):
    if needle not in BOOT:
        fail(why)
linger = re.search(r"sceneState\[player\] = nil\s*task\.wait\(([\d.]+)\)\s*if player\.Parent then\s*HubService\.returnToHub\(player\)", BOOT)
if not linger:
    fail("this check can no longer find the return to the lobby after a run")
elif float(linger.group(1)) < 6:
    fail("the lobby comes back %s seconds after LEVEL COMPLETE; the last room is held for six" % linger.group(1))
# AND NOT BEFORE THE ENDING HAS BEEN WATCHED: the return waits for the scene's "done" (Cinema), and the
# banner waits for it too.
for needle, why in (
    ('ensureRemoteEvent(remoteEventsFolder, "SceneState")', "Bootstrap never makes the SceneState remote"),
    ('while sceneState[player] == "began" and waited < SCENE_WAIT', "the lobby takes you in the middle of an ending"),
):
    if needle not in BOOT:
        fail(why)
if "while Cinema and not Cinema.told() and waited < BANNER_WAIT do" not in CLIENT_BOOT:
    fail("the banner comes up over an ending's last caption")
# CAPTIONS ARE READ (eighteenth pass): each stays up as long as its words take to read twice, none
# replaces one not yet read once, a scene holds its last shot for one still up, and the camera comes back
# over your shoulder.
for needle, why in (
    ("local hold = math.max(seconds or CAPTION_SECONDS, READ_BASE + READ_WORD * count)",
     "a caption comes down before its words can be read"),
    ("local start = math.max(now, current.freeAt)", "a caption replaces one that has not been read yet"),
    ("if not now and os.clock() < current.readUntil then", "a scene gives the camera back with a caption still up"),
    ("camera.CFrame = CFrame.lookAt(at - flat * 11 + Vector3.new(0, 3.5, 0), at)",
     "the camera comes back from an ending looking wherever the last shot looked"),
    ('tell("done")', "an ending never tells the server it has been watched"),
):
    if needle not in CINEMA:
        fail(why)
# THE VIEW, chosen in the lobby and held for the run; and the journal and the view started on the client.
VIEW = read("Client", "Services", "ViewModeService.lua") or ""
for needle, why in (
    ("player.CameraMode = Enum.CameraMode.LockFirstPerson", "first person is never locked for a run"),
    ("player.CameraMinZoomDistance = THIRD_DISTANCE", "third person is not held at one distance for a run"),
    ('player:GetAttributeChangedSignal("InLevel"):Connect(apply)', "the view is not locked when a run starts"),
):
    if needle not in VIEW:
        fail("ViewModeService: " + why)
if '"JournalService", "ViewModeService"' not in CLIENT_BOOT:
    fail("the client Bootstrap never starts the journal and the view")
# THIRD PERSON, FIRST ONLY THROUGH THE LOBBY'S VIEWER, AND CTRL FOR THE CURSOR (nineteenth pass). Nothing
# on the screen for the view: the one button in ViewModeService is the invisible one that frees the
# cursor in first person.
for needle, why in (
    ('prompt.Name == "ViewScopePrompt"', "the lobby's viewer does not change the view"),
    ("Enum.KeyCode.LeftControl", "Ctrl does not toggle the cursor"),
    ("UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter", "a locked cursor is never held in the middle"),
    ("modal.Modal = true", "Ctrl cannot free the cursor in first person"),
    ("local menu = menuOpen()", "the cursor stays locked over an open journal or pause menu"),
    ("not humanoid.Sit and not humanoid.PlatformStand and not root.Anchored", "a locked cursor turns you while you ride"),
):
    if needle not in VIEW:
        fail("ViewModeService: " + why)
if VIEW.count('Instance.new("TextButton")') != 1 or "Third person\" }" in VIEW or "VIEW FOR THE RUN" in VIEW:
    fail("ViewModeService puts a view switch on the screen again; it belongs to the lobby's viewer")
HUB_SRC = read("Server", "Services", "HubService.lua") or ""
for needle, why in (
    ('scope.Name = "ViewScope"', "the lobby has no seaside viewer, so first person cannot be chosen"),
    ('prompt.Name = "ViewScopePrompt"', "the lobby's viewer has no prompt"),
):
    if needle not in HUB_SRC:
        fail(why)
# THE PROMPTS ARE ROBLOX'S OWN (twentieth pass). A restyled card was tried: it was not wanted, and while
# the cursor was over it, it swallowed the right mouse button's release, so the camera went on dragging
# and the cursor stayed pinned near every NPC.
for path in sorted(SRC.rglob("*.lua")):
    text = path.read_text(encoding="utf-8")
    if "ProximityPromptStyle.Custom" in text:
        fail("%s draws its own prompts again; they are Roblox's own" % path.relative_to(SRC.parent).as_posix())
if (SRC / "Client" / "Services" / "PromptStyleService.lua").exists() or '"PromptStyleService"' in CLIENT_BOOT:
    fail("PromptStyleService is back; the prompts are Roblox's own")
# BACK FROM FIRST PERSON INTO A PROPER THIRD PERSON VIEW, and no slipping into first person in the lobby.
for needle, why in (
    ('if view == "third" and was == "first" then\n\t\tsettleThird()', "coming back from first person leaves the camera "
                                                                     "inside your head until you scroll out"),
    ("player.CameraMinZoomDistance = LOBBY_NEAR", "a scroll in the lobby slips you into first person"),
):
    if needle not in VIEW:
        fail("ViewModeService: " + why)
# THE SKY POOLS' PEOPLE EACH HAVE A HABIT (twentieth pass), and it leaves their hands alone while they talk.
for name in ("Dev", "Okafor", "Rudy"):
    if "function HABITS.%s(" % name not in TOWNS:
        fail("%s has no habit: they stand like a statue between lines" % name)
if "if habit and now > npc.talking then" not in TOWNS or "npc.talking = os.clock() + 2.6" not in TOWNS:
    fail("a habit fights the hands of someone talking")
# WHAT YOUR CHARACTER CRIES OUT ON THE WAY DOWN THE DRAIN: lettered like a voice, and slow enough to read.
cry = SUNKEN[SUNKEN.find('gui.Name = "DrainCry"'):]
cry = cry[:cry.find("-- THE RIDE IS SEEN")]
if "Enum.Font.PermanentMarker" not in cry or "Enum.Font.Kalam" not in cry:
    fail("the drain's cries are no longer lettered like a voice")
waits = [float(w) for w in re.findall(r"task\.wait\(if quiet then ([\d.]+) else ([\d.]+)\)", cry)[0]] \
    if re.search(r"task\.wait\(if quiet then ([\d.]+) else ([\d.]+)\)", cry) else []
if not waits or min(waits) < 1.5:
    fail("the drain's cries change too fast to read")
# THE SLIME'S KICK, from one resting width, and only with the ordinary camera.
if "launchKick.base = launchKick.base or camera.FieldOfView" not in CLIENT_BOOT \
        or "camera.CameraType == Enum.CameraType.Custom" not in CLIENT_BOOT:
    fail("the slime launch's camera kick is gone, or it would fight a scene's camera")
# BUBBLE WRAP IS HEARD UNDER YOUR FOOT, not a round trip later; and SOAP CRUMBLES WITHOUT CRACKS.
RENDERER = read("Client", "Services", "DeformationRenderer.lua") or ""
if 'AudioService.playSfx("BubbleWrap", part, true)' not in RENDERER or "if not heard then" not in RENDERER:
    fail("your own bubble wrap pops wait for the server again (or are heard twice)")
soap = RENDERER[RENDERER.find("Effects.Soap = function"):]
soap = soap[:soap.find("\nend\n")]
crumble = RENDERER[RENDERER.find("local interval = total > 0 and"):]
crumble = crumble[:crumble.find("crumbling[tile] = nil")]
if not soap or "Fissure.grow" in soap or "Fissure.extend" in soap or "Fissure.extend" in crumble:
    fail("soap draws black cracks again; it only crumbles")
loop = re.search(r'for _, name in ipairs\(\{([^}]*)\}\) do\s*task\.spawn', CLIENT_BOOT)
if not loop or '"CityShoreClient"' not in loop.group(1):
    fail("the client Bootstrap never starts CityShoreClient, so the dive is not a scene")

# SunkenNPCs became Townsfolk: nothing may still ask for it.
if (SRC / "Server" / "Services" / "SunkenNPCs.lua").exists():
    fail("src/Server/Services/SunkenNPCs.lua is back; Townsfolk replaced it")
# (ServerStorage.SunkenNPCs, the folder of hand-made characters, is still honoured by Townsfolk; only the
# module is gone.)
for path in SRC.rglob("*.lua"):
    for line in path.read_text(encoding="utf-8").splitlines():
        if 'SunkenNPCs"' in line and ("require" in line or "script.Parent" in line or "Services" in line):
            fail("%s still looks for the SunkenNPCs module: %s" % (path.relative_to(ROOT), line.strip()))

# ===================================================================== the fifteenth pass

# SLOW ENOUGH TO READ: what people say stays up twice as long, captions seven seconds, openings twelve.
if not re.search(r"^local READ = 2$", TOWNS, re.M) or "task.delay((seconds or 4.5) * READ," not in TOWNS:
    fail("what people say no longer stays up twice as long (Townsfolk.READ)")
caption_s = re.search(r"^local CAPTION_SECONDS = ([\d.]+)", CINEMA, re.M)
if not caption_s or float(caption_s.group(1)) < 7:
    fail("a caption comes down before it can be read twice (Cinema.CAPTION_SECONDS under seven)")
if "task.wait(12)" not in STORY or '("Level %d"):format(levelId)' not in STORY:
    fail("the words that open a level are not held for twelve seconds, or no longer say which level it is")
# YOU ARE ALWAYS IN SHOT, however close your own camera was.
for needle, why in (
    ("item.LocalTransparencyModifier = 0", "a zoomed-in player is invisible in their own scene"),
    ("RunService:BindToRenderStep(SHOW,", "nothing keeps the player drawn while a scene is on"),
    ("function Cinema.dip(", "a scene cannot dip to black to go somewhere else"),
):
    if needle not in CINEMA:
        fail(why)
# Unbound on the way in (a scene begun twice) and on the way out.
if CINEMA.count("RunService:UnbindFromRenderStep(SHOW)") < 2:
    fail("the player is kept drawn after the scene, even in first person")
# The poses the new scenes ask for by name: a missing one does nothing, silently.
for pose in ("flume", "key", "wheel", "climb"):
    if "function Poses.%s(" % pose not in POSES:
        fail("ReplicatedStorage/Shared/Poses has no %s, which the Flooded Halls' scene asks for" % pose)
# EVERYONE IS DRESSED: a look for everyone stood up, and hair, clothes and faces are built from it.
looks_block = table_block(TOWNS, "local LOOKS:")
looked = set(re.findall(r"^\t([A-Z][A-Za-z]*) = \{", looks_block or "", re.M))
for name in sorted(spawned):
    if name not in looked:
        fail("%s has no look in Townsfolk.LOOKS, so they stand there in plain colours" % name)
for needle, why in (
    ("pcall(dress, model, look)", "nobody is dressed"),
    ('feature(model, head, "Hair"', "nobody has hair"),
    ("desc.HeightScale = scale[1]", "everyone is built to the same proportions"),
    ('turn(npc, "RightShoulder", CFrame.Angles(0.6, 0, 0.12), 0.45)', "nobody talks with their hands"),
):
    if needle not in TOWNS:
        fail(why)
# THINGS TO READ on every level, and one with the reader's own name on it.
note_levels = dict((int(k), v) for k, v in re.findall(r"\[(\d)\] = \{(.*?)\n\t\},", notes_block, re.S))
for level in (1, 2, 3, 4):
    # Four since the sixteenth pass: one of them the Hold's own (LORE.md).
    if len(re.findall(r"title = ", note_levels.get(level, ""))) < 4:
        fail("level %d has fewer than four things to read" % level)
if "%s" not in note_levels.get(4, ""):
    fail("nothing in the baths has the reader's own name on it (a %s in a level 4 note)")
for needle, why in (
    ("pcall(nookNote, folder, nook, entry)", "the notes are not put in the nooks off the route"),
    ("pcall(note, folder, cap, entry)", "a note with no nook to go in is never put out"),
    ('Interactables.take(player, entry, paper, "note")', "a notice is never taken into the journal"),
    ("pcall(nookKeepsake, folder, nook, material)", "no keepsake is ever left in a nook"),
    ("pcall(venn, folder, first)", "Mrs Venn is never stood at the baths"),
    ("pcall(tobi, folder, mid)", "Tobi is never stood at the baths"),
    ("pcall(barlow, folder)", "Mr Barlow is never stood at the flume"),
):
    if needle not in STORY:
        fail(why)
HALLS = read("Server", "Services", "FloodedHallsService.lua") or ""
if 'halls:SetAttribute("EngineerSpot"' not in HALLS:
    fail("the halls never say where the night engineer stands")
# THE LEVELS ARE NUMBERED in the order they happen, where a player reads their names.
LEVELDEFS = read("Shared", "LevelDefinitions.lua") or ""
HUB = read("Server", "Services", "HubService.lua") or ""
if "function LevelDefinitions.titleOf(" not in LEVELDEFS or "makeSign(pad, LevelDefinitions.titleOf(level)," not in HUB:
    fail("the lobby's pads do not say Level 1, Level 2...")
for level, when in ((1, "9:14 AM"), (2, "3:00 PM"), (3, "11:52 PM"), (4, "11:56 PM")):
    if 'storyTime = "%s"' % when not in LEVELDEFS:
        fail("level %d is no longer set at %s on 14 August" % (level, when))
# SLOWER: every ending at about half its old speed.
SKYPATH = read("Shared", "SkyPath.lua") or ""
PATH = read("Shared", "SunkenPath.lua") or ""
for label, pattern, text, limit, below in (
    ("the slide's speed", r"SkyPath\.SPEED = ([\d.]+)", SKYPATH, 40, True),
    ("the drain's length", r"SunkenPath\.DRAIN_SECONDS = ([\d.]+)", PATH, 12, False),
    ("the dive's last carry", r"local CARRY_SPEED = ([\d.]+)", DIVE, 150, True),
    ("the diver's fall", r"local FALL_SPEED = ([\d.]+)", SHORE, 130, True),
):
    found = re.search(pattern, text)
    if not found:
        fail("this check can no longer read %s" % label)
    elif (float(found.group(1)) > limit) if below else (float(found.group(1)) < limit):
        fail("%s is back to full speed (%s)" % (label, found.group(1)))
# LINE 2 OF EVERY FILE SAYS WHERE IT GOES IN STUDIO (HANDOFF, "Where things are"): it is how a pasted
# file is put in the right place, and tools/paste_list.py reads it. Two files had lost it.
for path in sorted(SRC.rglob("*.lua")):
    head = path.read_text(encoding="utf-8").splitlines()[:3]
    if not any(line.strip().startswith("--") and ".lua" in line and "/" in line for line in head):
        fail("%s does not say where it goes in Studio in its first lines" % path.relative_to(SRC.parent).as_posix())
# F7 HIDES THE STUDIO PANEL, which it did not.
if "local panel = { on = false }" not in SUNKEN_CLIENT or "input:GetFocusedTextBox()" not in SUNKEN_CLIENT \
        or "shut.Activated:Connect(toggle)" not in SUNKEN_CLIENT:
    fail("the Sunken City's Studio panel starts shown, or F7 and its x cannot hide it")
# EVERY MATERIAL HAS A SOUND: each event with no ids has takes generated for it, and the game picks up
# whatever is put in SoundService.MaterialSounds.
AUDIO = read("Client", "Services", "AudioService.lua") or ""
AUDIO_DIR = SRC.parent / "audio"
empty = re.findall(r"^\t([a-zA-Z]+) = \{\},", AUDIO, re.M)
ALIASES = {"buttonClick": "button_clicky", "buttonLinear": "button_linear", "buttonTactile": "button_tactile",
           "buttonRelease": "button_release", "buttonCombo": "button_combo", "buttonCircuit": "button_circuit"}
for event in empty:
    stem = ALIASES.get(event, event)
    if not ((AUDIO_DIR / "materials" / ("%s_1.wav" % stem)).exists() or (AUDIO_DIR / "buttons" / ("%s_1.wav" % stem)).exists()):
        fail("%s has no sound: no ids, and no generated takes in audio/" % event)
if 'SoundService:FindFirstChild("MaterialSounds")' not in AUDIO:
    fail("AudioService never looks in SoundService.MaterialSounds, so the generated takes have to be pasted as ids")
for name in ("GateGroan", "WaterRush", "Siren", "MawRumble", "JawsShut", "Heartbeat", "SecretSting"):
    if not (AUDIO_DIR / "story" / ("%s.wav" % name)).exists():
        fail("audio/story/%s.wav is missing" % name)

# ===================================================================== the seventeenth pass

# AN ENDING SILENCES THE LEVEL: every ambient sound tagged, faded by the camera when an ending starts,
# and kept at nothing by what writes ambience every frame; and every level has a bed of its own.
AMBIENCE = read("Client", "Services", "AmbienceService.lua") or ""
SKY_SERVER = SKY
HALLS_SERVER = read("Server", "Services", "FloodedHallsService.lua") or ""
HUB_SERVER = read("Server", "Services", "HubService.lua") or ""
for label, text, needle in (
    ("Cinema", CINEMA, 'Players.LocalPlayer:SetAttribute("Hushed", true)'),
    ("Cinema", CINEMA, 'CollectionService:GetTagged("Ambience")'),
    ("Cinema", CINEMA, "local ending = not (options and options.hush == false)"),
    ("the Sunken City's mood", SUNKEN_CLIENT, 'local hush = if Players.LocalPlayer:GetAttribute("Hushed") then 0 else 1'),
    ("the Sunken City's mood", SUNKEN_CLIENT, "(1 - 0.6 * inside) * hush"),
    ("the Sunken City's rumble", SUNKEN_CLIENT, "0.55 * nearness * hush"),
    ("the Sky Pools' water", SKY_SERVER, 'CollectionService:AddTag(s, "Ambience")'),
    ("the Sunken City's water", SUNKEN, 'CollectionService:AddTag(s, "Ambience")'),
    ("the baths' drips", HALLS_SERVER, 'AddTag(drip, "Ambience")'),
    ("AmbienceService", AMBIENCE, 'player:GetAttributeChangedSignal("Hushed")'),
    ("Bootstrap", BOOT, 'player:SetAttribute("InLevel", level.backdrop)'),
    ("HubService", HUB_SERVER, 'player:SetAttribute("InLevel", nil)'),
):
    if needle not in text:
        fail("%s no longer does its part in silencing a level for its ending (%s)" % (label, needle))
beds = re.findall(r'\{ name = "(\w+)", volume', AMBIENCE)
for backdrop in ("cityShore", "skyPools", "sunkenCity", "floodedHalls"):
    if "\t%s = {" % backdrop not in AMBIENCE:
        fail("the %s level has no ambience of its own" % backdrop)
for name in set(beds):
    if not (AUDIO_DIR / "ambience" / ("%s.wav" % name)).exists():
        fail("audio/ambience/%s.wav is missing, and AmbienceService plays it" % name)
if '"AmbienceService", "StoryClient"' not in CLIENT_BOOT:
    fail("the client Bootstrap never starts AmbienceService and StoryClient")

# THE SECRETS: five, each with a place to be found, a way to open it, a scene and something to read.
INTERACT = read("Server", "Services", "Interactables.lua") or ""
STORY_CLIENT = read("Client", "Services", "StoryClient.lua") or ""
secrets_block = table_block(INTERACT, "Interactables.SECRETS = {") or ""
secret_ids = re.findall(r"^\t(\w+) = \{ order = (\d+)", secrets_block, re.M)
total = re.search(r"^local TOTAL = (\d+)$", INTERACT, re.M)
if not total or int(total.group(1)) != len(secret_ids):
    fail("Interactables.TOTAL is not the number of secrets, so the card counts wrong")
readable_secrets = strings(secrets_block)
for text in readable_secrets:
    if "--" in text or "—" in text or "–" in text:
        fail("a secret's words have a dash in them: %r" % text)
used_ids = set(re.findall(r'"(siren|photograph|marsh|locker|boards)"', STORY))
for sid, _ in secret_ids:
    if sid not in used_ids:
        fail("the secret %s is never put anywhere, so nobody can find it" % sid)
for kind, where in (("PoolBox", SKY_SERVER), ("AquariumLocker", SUNKEN), ("StaffLockers", HALLS_SERVER),
                    ("LoosePlank", HALLS_SERVER)):
    if '"%s"' % kind not in where:
        fail("nothing marks where the %s goes any more" % kind)
    if 'kind == "%s"' % kind not in STORY:
        fail("StoryService never builds the %s" % kind)
for needle, why in (
    ("pcall(Interactables.pryBar, folder, first.frame", "the pry bar is not in the first nook"),
    ("pcall(Interactables.pryBar, folder, besideRoute(cap, -1, 2.6))", "no level has the pry bar on it where there is no nook"),
    ("pcall(sirenTower, folder, instance, chunks, used, reserved)", "City Shore has no Siren Tower"),
    ("guard.CanCollide = true", "you can fall off the Siren Tower's bridge"),
    ("rail.CanCollide = true", "the Siren Tower bridge's rail is drawn and not there"),
    ("Interactables.looseBricks(parent, face, \"siren\"", "the Siren Room's loose bricks are gone"),
    ("spots()", "nothing is built on the levels' story spots"),
    ("if entry.lying and Interactables then", "no letter ever lies on the ground"),
):
    if needle not in STORY:
        fail(why)
for level in (1, 2, 3, 4):
    if "lying = true" not in note_levels.get(level, ""):
        fail("level %d has no letter lying on the ground" % level)
for needle, why in (
    ('kind == "moment"', "StoryClient never plays a secret's scene"),
    ('kind == "peek"', "StoryClient never looks under the boards"),
    ('kind == "whisper"', "StoryClient never whispers"),
):
    if needle not in STORY_CLIENT:
        fail(why)
if STORY_CLIENT.count("Cinema.begin({ hush = false })") < 2:
    fail("a secret's scene (or the look under the boards) would silence the level like an ending")
if 'ensureRemoteEvent(remoteEventsFolder, "StoryMoment")' not in BOOT:
    fail("Bootstrap never makes the StoryMoment remote")

# THE MOUTH: the meshes the client expects are the meshes Blender builds.
MAW = read("Client", "Services", "Maw.lua") or ""
extents_path = SRC.parent / "blender" / "maw_extents.json"
if not extents_path.exists():
    fail("blender/maw_extents.json is missing: run blender/gen_maw.py")
else:
    import json
    built = json.loads(extents_path.read_text(encoding="utf-8"))
    for name, entry in built.items():
        want = re.search(r"%s = Vector3\.new\(([\d.]+), ([\d.]+), ([\d.]+)\)" % name, MAW)
        if not want:
            fail("Maw.SIZE has no %s" % name)
        elif any(abs(float(want.group(i + 1)) - entry["size"][i]) > 0.05 for i in range(3)):
            fail("Maw.SIZE's %s is not what gen_maw.py builds (%s): the client would refuse the import" % (name, entry["size"]))
        if not (SRC.parent / "meshes" / ("%s.fbx" % name)).exists():
            fail("meshes/%s.fbx is missing" % name)
gates_maw = re.search(r"\n\tMAW = ([\d.]+),", HALLS_SERVER)
if not gates_maw or float(gates_maw.group(1)) < 4:
    fail("the mouth at the bottom of the fall has less than four seconds, or none")
if "task.wait(GATES.MAW)" not in HALLS_SERVER:
    fail("the server moves the rider into the chamber before the mouth has shut")

# ===================================================================== the twenty-first pass

# THE NEEDOH HAS ITS OWN SOUND: it borrowed clay's files and sounded exactly like the clay chunk.
needoh_at = MATERIAL_CONFIG.find("\tNeedoh = {")
needoh_block = MATERIAL_CONFIG[needoh_at:MATERIAL_CONFIG.find("\n\t},", needoh_at)] if needoh_at >= 0 else ""
if 'sfxEvent = "needohSquish"' not in needoh_block:
    fail("the Needoh has no sound event of its own, so it sounds like whatever it borrows")
if 'sfxEvent = "claySquish"' in needoh_block:
    fail("the Needoh plays clay's sound again, so the two chunks sound the same")
fallback_pitch = re.search(r"sfxFallbackPitch = ([\d.]+)", needoh_block)
if 'sfxFallback = "claySquish"' in needoh_block and not (fallback_pitch and float(fallback_pitch.group(1)) <= 0.85):
    fail("the Needoh falls back to clay's takes at clay's pitch: the same sound until its own are imported")
if "pitch = pitch or matDef.sfxFallbackPitch" not in AUDIO:
    fail("AudioService plays a borrowed sound at the lender's pitch (sfxFallbackPitch is ignored)")
for event in ("needohSquish", "lavaCrust"):
    for take in range(1, 5):
        if not (AUDIO_DIR / "materials" / ("%s_%d.wav" % (event, take))).exists():
            fail("audio/materials/%s_%d.wav is missing" % (event, take))

# THE LAVA IS ABOUT TO GO: a glow that breathes, embers and heat haze off it, bubbles that swell and
# spit, spurts where you stand, and a fountain when it gives way.
for needle, why in (
    ('embers.Name = "Embers"', "the lava throws off no embers"),
    ('smoke.Name = "HeatSmoke"', "no heat rises off the lava"),
    ("lavaLife.bubble(platform, at)", "the lava never bubbles"),
    ("lavaLife.flare(tile, 1)", "the lava does not flare when it bursts"),
    ("lavaLife.flare(tile, 0.35)", "the lava does not flare where it is stood on"),
    ("fountain:Emit(36)", "the lava bursts without a fountain"),
):
    if needle not in RENDERER:
        fail(why)
if not re.search(r"^lavaLife\.start\(\)$", RENDERER, re.M):
    fail("nothing ever starts the lava's life (glow, embers, bubbles)")

# THE ENDINGS ARE SCORED: each scene plays sounds of its own, every one of them is in audio/endings,
# and whatever a scene plays is faded out when it hands the camera back.
for needle, why in (
    ("function Cinema.sound(name: string, volume: number, options: SoundOptions?): Sound?", "Cinema has no way to play a scene's sound"),
    ("function Cinema.fade(s: Sound?, seconds: number?)", "Cinema has no way to fade a scene's sound out"),
    ('game:GetService("SoundService"):FindFirstChild("StorySounds")', "Cinema never looks in SoundService.StorySounds"),
    ("for _, s in ipairs(current.sounds) do\n\t\tCinema.fade(s, 2.5)", "a scene's sounds go on playing after it hands the camera back"),
):
    if needle not in (CINEMA or ""):
        fail(why)
SKY_CLIENT = read("Client", "Services", "SkyPoolsClient.lua") or ""
scored = {
    "City Shore": (SHORE or "", ("DiveBoard", "DiveWind", "DiveSplash", "UnderwaterHum", "ShoreChord")),
    "the Sky Pools": (SKY_CLIENT, ("SlideRush", "CloudWhoosh", "SkimSlap", "PoolPlunge", "PoolsChord")),
    "the Sunken City": (SUNKEN_CLIENT, ("WhirlRoar", "DrainFall", "CulvertWash", "SunkenChord")),
    "the Flooded Halls": (HALLS_CLIENT, ("FlumeRush", "PlungeWind", "HallsChord")),
}
for level, (text, names) in scored.items():
    for name in names:
        if not re.search(r'(Cinema\.sound|\bsound)\("%s"' % name, text):
            fail("the ending of %s never plays %s" % (level, name))
        if not (AUDIO_DIR / "endings" / ("%s.wav" % name)).exists():
            fail("audio/endings/%s.wav is missing, and the ending of %s plays it" % (name, level))
if "Cinema.fade(current.wind, 0.3)" not in (SHORE or ""):
    fail("the wind of the dive goes on after the water has closed over them")
if "Cinema.fade(current.roar, 2.5)" not in SUNKEN_CLIENT:
    fail("the whirlpool roars on all the way down the culvert")

# THE HIGH DIVE, SHOT PROPERLY: a cut back up to Maren, gulls to fall through, the air rushing past,
# the sun flaring as you go and put back after, and light and fish under the water.
for needle, why in (
    ('shot("maren")', "the dive never cuts back up to Maren watching you go"),
    ('deck:FindFirstChild("Maren", true)', "the dive never finds Maren on the deck"),
    ("pcall(moveGulls, current, here, now)", "the gulls never move, or never scatter"),
    ("here.Y - gull.home.Y < 24", "the gulls never scatter as you drop through them"),
    ('rush.Name = "DiveRush"', "nothing rushes past you on the way down"),
    ('"LightShaft"', "no light comes down through the water"),
    ('"Fish"', "nothing swims under the harbour"),
    ("rays.Intensity = current.sunWas", "the sun stays flared after the dive"),
):
    if needle not in (SHORE or ""):
        fail(why)

if problems:
    for problem in problems:
        print("FAIL: " + problem)
    sys.exit(1)
print("story: %d people with lines (%s), four numbered openings on one day, things to read on every level, the "
      "time card in the player's name, clean words, every ending wired as a scene at half speed, everyone dressed, "
      "every material with a sound, six seconds on LEVEL COMPLETE."
      % (len(LINES), ", ".join(sorted(LINES))))
