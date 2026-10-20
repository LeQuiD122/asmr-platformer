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
# (A story player goes on through storyStep instead, after the same hold: its next level, or the lobby to wait.)
linger = re.search(r"sceneState\[player\] = nil\s*task\.wait\(([\d.]+)\)\s*(?:--[^\n]*\n\s*)*local going = storyRun\s*"
                   r"if going and going\.players\[player\] and player\.Parent then\s*storyStep\(player\)\s*return\s*end\s*"
                   r"if player\.Parent then\s*HubService\.returnToHub\(player\)", BOOT)
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
if "Style.FONT.shout" not in cry or "Style.FONT.murmur" not in cry:
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
    ('npc.model:SetAttribute("Gesture", gestureFor(npc, text))', "nobody talks with their hands"),
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
    if not ((AUDIO_DIR / "materials" / ("%s_1.wav" % stem)).exists() or (AUDIO_DIR / "buttons" / ("%s_1.wav" % stem)).exists()
            or any((AUDIO_DIR / "sheets").glob("%s_x[0-9]*.wav" % stem))):
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
# The sixth is found by falling, not on a level: Bootstrap reveals it in the back rooms.
if 'pcall(Interactables.reveal, player, "backRooms", eye, focus, anchor)' in BOOT:
    used_ids.add("backRooms")
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
for scene_fn, label in (("pry", "the bar at work"), ("moment", "a secret found"), ("peek", "the look under the boards"),
                        ("caught", "being caught in the back rooms")):
    body = STORY_CLIENT[STORY_CLIENT.find("local function %s(" % scene_fn):]
    body = body[:body.find("\nend\n")]
    if "Cinema.begin({ hush = false })" not in body:
        fail("a secret's scene (%s) would silence the level like an ending" % label)
# THE HIDDEN CACHES: one for each of the four levels, their words without a dash; each a thing standing on its floor,
# glinting, taken once a save for its tokens (EconomyService.foundCache) with a line in the journal, and off your
# screen from then on (marked like a letter); put in a nook of its own two thirds along, or beside the route.
caches_block = table_block(INTERACT, "local CACHES: { [number]: Cache } = {") or ""
cache_levels = sorted(int(v) for v in re.findall(r"^\t\[(\d+)\] = \{ title = ", caches_block, re.M))
if cache_levels != [1, 2, 3, 4]:
    fail("the hidden caches are not one for each of the four levels: %s" % cache_levels)
for text in strings(caches_block):
    if "--" in text or "\u2014" in text or "\u2013" in text:
        fail("a hidden cache's words have a dash in them: %r" % text)
cache_fn = INTERACT[INTERACT.find("function Interactables.cache("):INTERACT.find("-- A LITTLE GLINT on something worth walking over to")]
for needle, why in (
    ("cf * CFrame.new(0, spec.size.Y / 2, 0)", "a hidden cache does not stand on its floor"),
    ("Interactables.glint(box,", "a hidden cache has nothing to catch the eye"),
    ('Interactables.mark(box, "note:" .. spec.title)', "a hidden cache already taken shows again next time"),
    ("pcall(save.foundCache, player, levelId)", "a hidden cache pays nothing"),
    ('Interactables.take(player, { title = spec.title, body = spec.body }, box, "note")', "a hidden cache leaves no line in the journal"),
):
    if needle not in cache_fn:
        fail(why)
for needle, why in (
    ("local hidden = nookNear(0.66)", "no hidden cache is put in a nook"),
    ("pcall(nookCache, folder, hidden, level.levelId)", "the hidden cache's nook is left empty"),
    ("pcall(Interactables.cache, folder, besideRoute(cap, -1, 1.2), level.levelId)", "a level with no room for a nook has no hidden cache"),
):
    if needle not in STORY:
        fail(why)

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
    # Four takes, as single files or (since the ninety-sixth pass) as one sheet of four.
    singles = all((AUDIO_DIR / "materials" / ("%s_%d.wav" % (event, take))).exists() for take in range(1, 5))
    if not singles and not (AUDIO_DIR / "sheets" / ("%s_x4.wav" % event)).exists():
        fail("audio has neither %s_1 to _4 nor a sheet %s_x4" % (event, event))

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

# ONE CHORD FOR ALL FOUR: each ending's last chord falls back on EndChord at its own pitch, so one upload
# brings all four back (the four would not all upload).
if not (AUDIO_DIR / "endings" / "EndChord.wav").exists():
    fail("audio/endings/EndChord.wav is missing (python audio/gen_ending_sfx.py EndChord)")
if "local alt = options and options.alt and folder and folder:FindFirstChild(options.alt)" not in (CINEMA or ""):
    fail("Cinema has no stand-in from another story sound, so a missing chord is silence")
for level, text, name in (("City Shore", SHORE or "", "ShoreChord"), ("the Sky Pools", SKY_CLIENT, "PoolsChord"),
                          ("the Sunken City", SUNKEN_CLIENT, "SunkenChord")):
    if not re.search(r'Cinema\.sound\("%s", [^\n]*alt = "EndChord", altPitch = [\d.]+' % name, text):
        fail("the ending of %s has no EndChord to fall back on" % level)
if 'sound("HallsChord", nil, 0.7, 1, false) or sound("EndChord", nil, 0.7, 1, false)' not in HALLS_CLIENT:
    fail("the ending of the Flooded Halls has no EndChord to fall back on")

# ===================================================================== the journal, kept between sessions
#
# What you pick up is saved (EconomyService.keepEntry, called by Interactables.take on the server, as the story
# wrote it), capped and never twice; read back once the save is ready (JournalState), with the reader's name
# put in; added on the client quietly and already read; and anything out in the world that is already in the
# journal shows as taken.
ECONOMY_SRC = read("Server", "Services", "EconomyService.lua") or ""
keep = ECONOMY_SRC[ECONOMY_SRC.find("function EconomyService.keepEntry("):ECONOMY_SRC.find("-- ===== THE EMOTES =====")]
if not keep:
    fail("EconomyService does not keep the journal between sessions")
for needle, why in (
    ("Journal = {} :: { any }", "the save has no journal"),
    ("if #journal >= JOURNAL_MOST then\n\t\treturn", "the journal in the save is not capped"),
    ("if kept.id == id then\n\t\t\treturn", "the same thing can be kept twice"),
    ('if typeof(id) ~= "string" or #id > 160 then', "a journal id is not checked"),
    ("kept[field] = string.sub(value, 1, 4000)", "a journal entry's words are not capped"),
    ("if last and now - last < 0.5 then\n\t\treturn { ready = false }", "the journal can be asked for without end"),
    ('entry.body = (entry.body:gsub("%%s", name))', "the reader's name is not put back into the letters"),
    ("journalState.OnServerInvoke = onJournal", "nothing answers JournalState"),
):
    if needle not in ECONOMY_SRC:
        fail("EconomyService: " + why)
if 'ensureRemoteFunction(remoteFunctionsFolder, "JournalState")' not in BOOT:
    fail("Bootstrap never makes the JournalState remote, so the journal is never read back")
take = INTERACT_EARLY[INTERACT_EARLY.find("function Interactables.take("):INTERACT_EARLY.find("Players.PlayerRemoving")]
for needle, why in (
    ("pcall(save.keepEntry, player, { id = id, kind = sort, title = entry.title, body = entry.body,",
     "what is taken is not kept between sessions, or kept with the first reader's name in it"),
):
    if needle not in take:
        fail("Interactables: " + why)
for needle, why in (
    ('Interactables.mark(sheet, "note:" .. entry.title)', "a letter on the ground is not marked with its journal id"),
    ('Interactables.mark(model, "keepsake:" .. entry.thing)', "a keepsake is not marked with its journal id"),
    ('CollectionService:AddTag(object, "JournalThing")', "nothing is tagged for the client to show as taken"),
    ('count = math.max(count, before + (if kept["secret:" .. noteTitle] then 0 else 1))',
     "a secret's card counts only this session's secrets"),
):
    if needle not in INTERACT_EARLY:
        fail("Interactables: " + why)
# THE TEST PANEL CAN FILL THE SHELF AND EMPTY THE JOURNAL (Studio only, through onDev): every keepsake taken as
# if picked up, quietly, with its words and where it came from; and the saved journal emptied.
DEV_PANEL = read("Client", "Services", "DevPanelClient.lua") or ""
for needle, why in (
    ('{ action = "keepsakes", text = "All keepsakes" }', "the test panel cannot fill the keepsake shelf"),
    ('{ action = "journal", text = "Clear journal (rejoin)" }', "the test panel cannot empty the journal"),
):
    if needle not in DEV_PANEL:
        fail("DevPanelClient: " + why)
for needle, why in (
    ('elseif action == "keepsakes" then\n\t\ttask.spawn(giveAllKeepsakes, player)', "All keepsakes does nothing"),
    ('elseif action == "journal" then', "Clear journal does nothing"),
    ("\t\tdata.Journal = {}\n", "Clear journal does nothing"),
    ("{ material = item.material, from = item.from }, true)", "All keepsakes fills the corner with 27 lines"),
):
    if needle not in ECONOMY_SRC:
        fail("EconomyService: " + why)
if "line = entry.line, from = entry.from" not in INTERACT_EARLY:
    fail("Interactables: the keepsake list leaves out each one's words, so the test panel's keepsakes are empty")

# THE COLLECTION, SHOWN TO EVERYONE: a Keepsakes column in Roblox's own player list (leaderstats), counted from
# the saved journal's keepsakes only, set on joining, raised the moment one is picked up, and right again after
# the test panel empties the journal or the self-test puts the save back.
show = ECONOMY_SRC[ECONOMY_SRC.find("local function showCollection("):]
show = show[:show.find("\nend\n")]
for needle, why in (
    ('stats.Name = "leaderstats"', "the collection is not in Roblox's player list (leaderstats, exactly)"),
    ('value.Name = "Keepsakes"', "the player list's column is not Keepsakes"),
    ('if kept.kind == "keepsake" then\n\t\t\tcount += 1', "the player list counts more than the keepsakes"),
):
    if needle not in show:
        fail("EconomyService: " + why)
for needle, why in (
    ("\tshowCollection(player)\n\tif not ready.Data.Welcomed then", "the collection is not shown on joining"),
    ('\tif kept.kind == "keepsake" then\n\t\tshowCollection(player)\n\tend\n', "a keepsake picked up does not raise the count"),
    ("\t\tdata.Journal = {}\n\t\tshowCollection(player)\n", "the count stays up after the journal is emptied"),
    ("\tlastNote[player] = realNote\n\tshowCollection(player)\n", "the count can be wrong after the self-test"),
):
    if needle not in ECONOMY_SRC:
        fail("EconomyService: " + why)

if 'Interactables.mark(paper, "note:" .. entry.title)' not in STORY:
    fail("StoryService: a notice board's note is not marked with its journal id")
for needle, why in (
    ("read = data.restored == true", "a journal read back from last time lights the badge up again"),
    ("data.quiet = true\n\t\t\t\t\tdata.restored = true", "a journal read back from last time is announced again"),
    ('functions:WaitForChild("JournalState", 20)', "the journal is never asked for"),
    ('CollectionService:GetInstanceAddedSignal("JournalThing"):Connect(hideIfKept)',
     "things already in the journal are not shown as taken when they come into view"),
    ("task.spawn(readBack)", "the journal is never read back"),
):
    if needle not in JOURNAL:
        fail("JournalService: " + why)

# IMPACT FRAMES, SPEED LINES AND THOUGHTS (Cinema, 2026-10-16): an impact frame is two frames in black and white,
# a soft flash (never full white: a beat, not a strobe), speed lines and a punch in; speed lines are drawn every frame
# the camera is; a thought is written out over a head. Cleared away with the scene.
impact_fn = CINEMA[CINEMA.find("function Cinema.impact("):CINEMA.find("function Cinema.think(")]
for needle, why in (
    ("effect.Saturation = -1", "an impact frame is not black and white"),
    ("current.kick = math.max(current.kick, 9 * s)", "an impact frame does not punch in"),
    ("current.burst = math.max(current.burst, math.min(1, 0.9 * s))", "an impact frame has no speed lines"),
):
    if needle not in impact_fn:
        fail("Cinema: " + why)
flash = re.search(r"current\.flash\.BackgroundTransparency = ([\d.]+)", impact_fn)
if not flash or float(flash.group(1)) < 0.4:
    fail("Cinema: an impact frame's flash is too near full white (a strobe, not a beat)")
for needle, why in (
    ("\tdrawLines(current, dt)\n", "the speed lines are never drawn"),
    ("camera.FieldOfView = math.max(8, fov - kick)", "an impact frame's punch in is never seen"),
    ("\tif current.impactFx then\n\t\tcurrent.impactFx:Destroy()", "an impact frame's colour is left on after the scene"),
    ("TweenService:Create(words, TweenInfo.new(length / 30, Enum.EasingStyle.Linear), { MaxVisibleGraphemes = length }):Play()",
     "a thought is not written out as it is thought"),
):
    if needle not in CINEMA:
        fail("Cinema: " + why)

# A BODY THAT ACTS (Poses): the dive pushes off and is buffeted; prying, pondering, startled, peering.
for pose in ("pry", "ponder", "startle", "peer"):
    if "function Poses.%s(name: string, t: number, w: number, r6: boolean): CFrame?" % pose not in POSES:
        fail("Poses: there is no %s for a secret's scene" % pose)
dive_fn = POSES[POSES.find("function Poses.dive("):POSES.find("function Poses.sled(")]
for needle, why in (
    ("local push = 1 - math.clamp(t / 0.32, 0, 1)", "the dive does not push off the board"),
    ("local buffet = close * math.clamp((t - 1.8) / 0.6, 0, 1)", "the dive is a statue in the wind"),
):
    if needle not in dive_fn:
        fail("Poses: " + why)

# CITY SHORE'S DIVE, HIT LIKE AN ACTION GAME: an impact frame leaving the board, through the gulls and into the
# water; speed lines down the drop; wind streaks and air trails; the body rolled and yawed by the wind.
for needle, why in (
    ("\t\t\t\tCinema.impact(1)\n", "leaving the board is not hit"),
    ("\t\t\t\tCinema.impact(0.8)\n", "bursting through the gulls is not hit"),
    ("\t\tCinema.impact(1.4)\n", "hitting the water is not hit"),
    ("Cinema.speedLines(0.75)", "the drop has no speed lines"),
    ('trail.Name = "DiveAirTrail"', "no air trails off the hands and feet"),
    ("streaks.Rate = if not splash and t > 1.5 then 90 else 0", "no wind streaking past in the fall"),
    ("CFrame.Angles(-math.pi * 0.95 * over, yaw, roll)", "the diver is not buffeted by the wind"),
    ("\t\t\tfor _, made in ipairs({ a0, a1, trail }) do\n\t\t\t\ttable.insert(current.held, made)",
     "the air trails are left on the character after the dive"),
    # THE DIVER ACTS, AND THE DROP SHOWS WHERE IT IS GOING (the ninety-second pass): what they think off the board,
    # turning over and with the water coming; the drop looks down past them at the sea, not up at the sky; and their
    # face, close, on the way down.
    ('think("brave", "Okay. Don\'t look down.", 1.8)', "the diver thinks nothing as they leave the board"),
    ('think("looked", "I looked down.", 1.6)', "the diver thinks nothing as they turn over and see the drop"),
    ('think("arms", "Arms together. Arms together!", 2)', "the diver thinks nothing with the water coming"),
    ("Cinema.point(CFrame.lookAt(eye, here - Vector3.new(0, 22, 0), current.facing)",
     "the drop looks up at the sky, away from where they are going"),
    ('shot("face")', "the diver's face is never seen on the way down"),
):
    if needle not in SHORE:
        fail("CityShoreClient: " + why)
if "here + Vector3.new(0, -16, 0) + current.facing * 5 + side * 2" in SHORE:
    fail("CityShoreClient: the drop is shot from under the diver looking up at the sky again")
for words in re.findall(r'think\("\w+", "([^"]+)"', SHORE):
    if "--" in words or "—" in words or "–" in words:
        fail("CityShoreClient: a thought has a dash in it: %r" % words)

# THE BAR SEEN AT WORK, AND YOU IN A SECRET'S SCENE: every secret has what you think before and after (no dashes);
# the bar's first opening is shown worked (the server opens it only on the last tug, the same length on both
# sides); the scenes pose you (prying, startled, pondering, peering), put the bar in your hands and back.
secrets_block = INTERACT[INTERACT.find("Interactables.SECRETS = {"):INTERACT.find("local TOTAL = ")]
secret_starts = [(m.group(1), m.start()) for m in re.finditer(r"^\t(\w+) = \{ order = \d+,", secrets_block, re.M)]
for index, (secret_id, start) in enumerate(secret_starts):
    entry = secrets_block[start:secret_starts[index + 1][1] if index + 1 < len(secret_starts) else len(secrets_block)]
    think = re.search(r'think = \{ "([^"]+)", "([^"]+)" \}', entry)
    if not think:
        fail("Interactables: the secret %s has nothing for you to think" % secret_id)
    else:
        for text in think.groups():
            if "--" in text or "\u2014" in text or "\u2013" in text:
                fail("Interactables: a thought has a dash in it: %r" % text)
open_fn = INTERACT[INTERACT.find("local function openable("):INTERACT.find("function Interactables.locker(")]
for needle, why in (
    ('remote:FireClient(player, "pry", { at = host.Position, object = object,', "the bar is never seen at work"),
    ("wait = PRY_SECONDS", "the thing flies open before the bar has touched it"),
    ("task.delay(wait, function()\n\t\t\t\ton.open(player)", "the thing flies open before the bar has touched it"),
):
    if needle not in open_fn:
        fail("Interactables: " + why)
if INTERACT.count("\t\tsecret = ") < 4:
    fail("Interactables: a thing the bar opens does not say what is in it")
if "think = if secret.think then secret.think[2] else nil" not in INTERACT:
    fail("Interactables: what you make of a secret is never sent")
server_pry = re.search(r"local PRY_SECONDS = ([\d.]+)", INTERACT)
client_pry = re.search(r"local PRY_SECONDS = ([\d.]+)", STORY_CLIENT)
if not (server_pry and client_pry) or server_pry.group(1) != client_pry.group(1):
    fail("StoryClient: the bar's scene and the server disagree on how long the prying takes")
for needle, why in (
    ('elseif kind == "pry" and typeof(data) == "table" then\n\t\t\t\tpry(data)', "the bar's scene is never played"),
    ('\tact("pry")\n', "you do not work the bar"),
    ('\t\t\tCinema.impact(0.9)\n\t\t\tact("startle")\n', "you do not jump back when it gives (or it giving is not hit)"),
    ('if not again and not (acting.now and acting.now.pose == "ponder") then\n\t\tact("ponder")', "you do not stop to work out what you have found"),
    ("Cinema.think(character, data.think, 3.4)", "what you make of a secret is not over your head"),
    ('\tact("peer")\n', "you do not lean over the gap"),
    ("\tact(nil)\n\tbarInHands(false)\n", "the bar and your pose are not given back when a scene ends"),
):
    if needle not in STORY_CLIENT:
        fail("StoryClient: " + why)

# THE PEOPLE TELL IT WITH THEIR BODIES (2026-10-16): every line comes with a gesture, chosen line by line (TOLD),
# played by every client on their joints (StoryClient, Poses.tell) with whichever hand is not holding something.
# It used to be one hand out and back, and only for the people with nothing in their hands: most of them stood still.
gestures_lua = re.search(r"^Poses\.GESTURES = \{ (.*?) \}", POSES, re.M)
known = re.findall(r'"(\w+)"', gestures_lua.group(1)) if gestures_lua else []
if len(known) < 8:
    fail("Poses: there are %d gestures to tell a story with" % len(known))
gesture_fn = POSES[POSES.find("local function gestureAt("):POSES.find("function Poses.tell(")]
for g in known:
    if g != "explain" and 'gesture == "%s"' % g not in gesture_fn:
        fail("Poses: the gesture %s is named and never made" % g)
lines_block = TOWNS[TOWNS.find("local LINES: {"):TOWNS.find("-- HOW EACH LINE IS TOLD")]
told_block = TOWNS[TOWNS.find("local TOLD: {"):TOWNS.find("-- HOW LONG anything said")]
told = {name: re.findall(r'"(\w+)"', body) for name, body in re.findall(r"^\t(\w+) = \{ (.*?) \},", told_block, re.M)}
said_by = {name: re.findall(r'^\t\t"(?:[^"\\]|\\.)*",', body, re.M)
           for name, body in re.findall(r"^\t(\w+) = \{\n(.*?)\n\t\},", lines_block, re.M | re.S)}
if not said_by or not told:
    fail("this check can no longer read the townsfolk's lines or how each is told")
tally = {}
for name, lines in said_by.items():
    how = told.get(name)
    if how is None:
        fail("Townsfolk: nothing says how %s tells their lines" % name)
        continue
    if len(how) != len(lines):
        fail("Townsfolk: %s has %d lines and %d gestures for them" % (name, len(lines), len(how)))
    if how and how[0] != "greet":
        fail("Townsfolk: %s does not greet you with their first line" % name)
    for g in how:
        tally[g] = tally.get(g, 0) + 1
        if g not in known:
            fail("Townsfolk: %s tells a line with %r, which Poses does not make" % (name, g))
    for a, b in zip(how, how[1:]):
        if a == b:
            fail("Townsfolk: %s tells two lines running the same way (%s)" % (name, a))
total = sum(tally.values()) or 1
if len(tally) < 8:
    fail("Townsfolk: the lines are told with only %d of the gestures" % len(tally))
for g, n in tally.items():
    if g not in ("greet", "explain") and n > 0.25 * total:
        fail("Townsfolk: %d of %d lines are told with %s" % (n, total, g))
for needle, why in (
    ('npc.model:SetAttribute("Gesture", gestureFor(npc, text))', "a line is said without a gesture"),
    ('npc.model:SetAttribute("GestureAt", workspace:GetServerTimeNow())', "a gesture is never started"),
    ("npc.talking = os.clock() + seconds", "a habit fights the gesture of someone talking"),
    ("for _, jointName in ipairs(ARMS) do", "a habit's arm is left where it was when a gesture starts"),
    ('CollectionService:AddTag(model, "Townsperson")', "the clients never find the people to play their gestures"),
    ('if to == "RightHand" or to == "LeftHand" then', "something held in a hand does not keep that hand out of the gesture"),
    ('holds = "both", title = "Mr Wick"', "the fisherman lets go of his rod to gesture"),
    ("local told = TOLD[npc.name]", "the lines are not told the way TOLD says"),
):
    if needle not in TOWNS:
        fail("Townsfolk: " + why)
if 'turn(npc, "RightShoulder", CFrame.Angles(0.6, 0, 0.12), 0.45)' in TOWNS:
    fail("Townsfolk: the old one-handed wave is back alongside the gestures")
for needle, why in (
    ("local by = Poses.tell(gesture :: string, name, t, w,", "the people's gestures are never played"),
    ("\tstartTellers()\n", "the people's gestures are never started"),
    ("\t\tpcall(stepTellers)\n", "the people's gestures are never stepped"),
    ("\t\t\t\tPoses.drive(joint, CFrame.identity)\n", "a gesture is never let go of"),
    ("(root.Position - camera.CFrame.Position).Magnitude < TELL_SEEN", "everyone's gestures are played however far away"),
):
    if needle not in STORY_CLIENT:
        fail("StoryClient: " + why)
for needle, why in (
    ('local mainSide = if hands == "left" then "Left" elseif hands == "none" then nil else "Right"',
     "a gesture is made with a hand that is holding something"),
    ('local otherSide = if hands == "both" then "Left" else nil', "a gesture's second hand lets go of what it holds"),
    ("local nod = 0.06 * math.sin(t * 6.3) * math.sin(t * 1.7 + 0.4)", "nobody nods as they talk"),
):
    if needle not in POSES:
        fail("Poses: " + why)

# THE LOCKERS AND THE SECRETS' SCENES, from the second test (2026-10-16): a locker was a solid block whose door swung
# back INTO it, so opened it showed a blank face (read as a locker turned the wrong way round), and the scene looked
# over your shoulder (your back, or your head when the wall behind pulled the camera in) and then at that blank face.
locker_fn = INTERACT[INTERACT.find("function Interactables.locker("):INTERACT.find("function Interactables.lockbox(")]
holds_fn = INTERACT[INTERACT.find("local function lockerHolds("):INTERACT.find("function Interactables.locker(")]
swing_angle = re.search(r"swing\(door, hinge, (-?)math\.rad\((\d+)\)", locker_fn)
if not swing_angle or swing_angle.group(1) == "-":
    fail("Interactables: a locker's door swings back into the locker instead of out toward you")
for needle, why in (
    ('piece(parent, "LockerSide"', "a locker is a solid block again, with nothing inside to see"),
    ('piece(parent, "LockerLid"', "a locker has no lid over its inside"),
    ("lockerHolds(parent, base, door, opts.secret)", "a locker holds nothing"),
    ("TweenService:Create(lamp, TweenInfo.new(0.5), { Brightness = 0.9 }):Play()", "a locker's lamp never comes on"),
):
    if needle not in locker_fn:
        fail("Interactables: " + why)
if "Enum.Material.Neon" in locker_fn or "Enum.Material.Neon" in holds_fn:
    fail("Interactables: a locker fakes its light with Neon")
for needle, why in (
    ('if what == "locker" then', "Locker 3 does not have your coat in it"),
    ('"KeyHolderCard"', "your card is not in Locker 3"),
    ('elseif what == "marsh" then', "Marsh's locker is empty"),
    ('"WireHanger"', "an empty locker is not even a hanger"),
):
    if needle not in holds_fn:
        fail("Interactables: " + why)
reveal_fn = INTERACT[INTERACT.find("function Interactables.reveal("):INTERACT.find("local function openable(")]
for needle, why in (
    ("local again = mine[id] == true", "a secret looked at again plays its whole scene and card over again"),
    ("again = again or kept[", "a secret found in an earlier session plays its whole scene again"),
    ("again = again,", "the client is never told a look is a second look"),
):
    if needle not in reveal_fn:
        fail("Interactables: " + why)
if "local function overShoulder(" in STORY_CLIENT or "overShoulder(" in STORY_CLIENT:
    fail("StoryClient: a secret's scene is shot over your shoulder again (your back, or your head, fills it)")
two_fn = STORY_CLIENT[STORY_CLIENT.find("local function twoShot("):STORY_CLIENT.find("-- THE BAR IN YOUR HANDS")]
for needle, why in (
    ("mid + right * side * reach", "the two-shot is not taken from the side"),
    ("twoShotSide = if math.max(rightRoom, leftRoom) < 3.2 then 0", "the two-shot does not choose the side with room"),
    ("if not twoShotSide then", "the two-shot swaps sides in the middle of a scene"),
):
    if needle not in two_fn:
        fail("StoryClient: " + why)
if STORY_CLIENT.count("twoShotSide = nil") < 4:
    fail("StoryClient: a scene keeps the last scene's side for its two-shot")
moment_fn = STORY_CLIENT[STORY_CLIENT.find("local function moment("):STORY_CLIENT.find("local function peek(")]
for needle, why in (
    ("local reach = math.clamp((eye.Position - focus).Magnitude * 0.5, 1.9, 3.4)", "the close look is not close"),
    ("local want = focus + out * (reach - 0.7 * u)", "the close look is not in front of what was found"),
    ("local closing = if again then 3 else MOMENT.close", "a second look is as long as the first"),
    ("if not again then\n\t\tsound(\"SecretSting\"", "a second look stings again"),
    ("if not again then\n\t\t\t\tcard(", "a second look puts its card up again"),
):
    if needle not in moment_fn:
        fail("StoryClient: " + why)
if "Cinema.spline(path, u)" in moment_fn:
    fail("StoryClient: the secret's scene drifts along its old curve to the outside of the thing again")

# THE PEOPLE'S VOICES (2026-10-16): no words, the sound of somebody talking, one for each gesture, in one upload, at
# each speaker's own pitch, as each line starts.
VOICE_GEN = SRC.parent / "audio" / "gen_voice_sfx.py"
VOICE_WAV = SRC.parent / "audio" / "story" / "TownsfolkVoice_x9.wav"
voice_order = re.search(r'^ORDER = \((.*?)\)', VOICE_GEN.read_text(encoding="utf-8"), re.M) if VOICE_GEN.exists() else None
if not voice_order or re.findall(r'"(\w+)"', voice_order.group(1)) != known:
    fail("gen_voice_sfx.py's takes are not in the order of Poses.GESTURES, so a gesture would be said with another's voice")
if not VOICE_WAV.exists():
    fail("audio/story/TownsfolkVoice_x9.wav is missing")
else:
    try:
        import numpy as np
        from scipy.io import wavfile
        sr, wav = wavfile.read(VOICE_WAV)
        wav = wav.astype(float) / 32767
        if abs(len(wav) / sr - 2.0 * len(known)) > 0.01:
            fail("TownsfolkVoice_x9.wav is not %d two-second slots" % len(known))
        else:
            for k, g in enumerate(known):
                slot = wav[int(sr * 2 * k):int(sr * 2 * (k + 1))]
                if np.max(np.abs(slot[:int(sr * 1.95)])) < 0.1:
                    fail("TownsfolkVoice_x9.wav: the %s voice is silent" % g)
                if np.max(np.abs(slot[int(sr * 1.95):])) > 0.002:
                    fail("TownsfolkVoice_x9.wav: the %s voice runs into the next slot" % g)
    except ImportError:
        pass
voices = dict(re.findall(r"(\w+) = ([\d.]+)", TOWNS[TOWNS.find("local VOICES: {"):TOWNS.find("-- HOW LONG anything said")]))
for name in said_by:
    if name not in voices:
        fail("Townsfolk: %s has no voice of their own" % name)
for needle, why in (
    ('model:SetAttribute("Voice", VOICES[name] or 1)', "nobody's voice is their own"),
):
    if needle not in TOWNS:
        fail("Townsfolk: " + why)
for needle, why in (
    ('local sheet = folder and folder:FindFirstChild("TownsfolkVoice_x9")', "the voices are never found"),
    ("local from = (index - 1) * VOICE_SLOT", "a gesture is said with the wrong voice"),
    ("if typeof(gesture) == \"string\" and workspace:GetServerTimeNow() - at < 0.5 then\n\t\t\t\tspeak(model, gesture)",
     "a voice is played for a line already being said, or never"),
    ("(voice :: any).PlaybackRegion = NumberRange.new(from, from + VOICE_SLOT - 0.05)", "a voice runs on into the next one"),
):
    if needle not in STORY_CLIENT:
        fail("StoryClient: " + why)

# ONE TEXT FOR THE STORY ON SCREEN (2026-10-16): the captions were Gotham and the thoughts, whispers and the secret's
# card Garamond, so a level told with captions (the Sunken City) and one told with thoughts (the Flooded Halls) read as
# two games. Every line of the story on the screen is in the game's one family now (Style, the ninety-ninth pass: it was
# Gotham, the menus Nunito); signs and notices in the world keep their own print (check_style.py).
CINEMA_SRC = read("Client", "Services", "Cinema.lua") or ""
for label, text in (("Cinema", CINEMA_SRC), ("StoryClient", STORY_CLIENT)):
    if "Garamond" in text or "Style.FONT.paper" in text or "Style.WORLD.letter" in text:
        fail("%s: a line of the story on the screen is in another typeface (the paper's Garamond) again" % label)

# THE BUTTER STICKS GIVE ONLY WHERE YOU STEP, AND THEIR WRAPPER GOES WITH THEM (from the test, 2026-10-17): the dent
# shallower than a stick is tall (gen_butter_sticks.py RISE), no travelling wave across the chunk after a step, and
# the wax shell over the sticks driven with the butter's own dent, held and given back.
import re as _re
_butter = RENDERER[RENDERER.find("local BUTTER_STICK = {}"):RENDERER.find("local function softBedEffect(")]
_press = _re.search(r"BUTTER_STICK\.PRESS = ([\d.]+)", _butter)
_rise = _re.search(r"^RISE = ([\d.]+)", (SRC.parent / "blender" / "gen_butter_sticks.py").read_text(encoding="utf-8"), _re.M)
if not _press or not _rise or float(_press.group(1)) >= float(_rise.group(1)):
    fail("DeformationRenderer: a step sinks a butter stick deeper than it stands over its grooves (it caves in below them)")
if "BUTTER_STICK.RIPPLE = nil" not in _butter:
    fail("DeformationRenderer: a step on the butter sticks sends dips across the whole chunk again (they read as other steps)")
if "BUTTER_STICK.SHELL = true" not in _butter:
    fail("DeformationRenderer: the butter sticks' wrapper is not driven, so it stays up as a flat lid over every dent")
_soft = RENDERER[RENDERER.find("local function softBedEffect("):RENDERER.find("-- MOLTEN KEYS")]
for _needle, _why in (
    ("driveShell(tile, down, -profile.PRESS, false)", "the wrapper does not go down with the butter"),
    ("driveShell(tile, keep, -profile.PRESS * profile.RESIDUAL_FRACTION, false)", "the wrapper does not hold the butter's dent"),
    ("driveShell(tile, back, 0, false)", "the wrapper never comes back up with the butter"),
    ("if bone and onSlab and profile.RIPPLE then", "a bed with no wave still sends one"),
):
    if _needle not in _soft:
        fail("DeformationRenderer: " + _why)
# THE BUBBLE WRAP'S POPS, SEEN (the hundred-and-first pass): a puff you can see from behind, the film's flecks thrown out,
# a glint at the instant; and the pocket swelling before it goes.
_pop = RENDERER[RENDERER.find("local function popPuff("):RENDERER.find("local function burstPocket(")]
for _needle, _why in (
    ("burst:Emit(8)", "a pop's puff is too small to see"),
    ("flecks:Emit(7)", "a pop throws no flecks of film"),
    ("glint:Emit(1)", "a pop has no glint"),
):
    if _needle not in _pop:
        fail("DeformationRenderer: " + _why)
_swell = re.search(r"^POCKET\.SWELL = ([\d.]+)", RENDERER, re.M)
if not _swell or float(_swell.group(1)) < 0.35:
    fail("DeformationRenderer: a bubble wrap pocket barely swells before it pops (the half of the pop that shows)")

# ===================================================================== what you say to them (the hundred-and-fourth pass)
# Shared/Conversations.lua: every person in it is one of the people (Townsfolk.LINES); every topic has your line and
# their answer, no dashes in either; every `after` is a topic that exists, every `needs` a clue something gives, every
# clue given has a note for your journal; and the thread you chose, you are Marsh's child, can be followed from the
# start (every clue can be learned, each from things you can already ask).
CONVERSATIONS = read("Shared", "Conversations.lua") or ""
if not CONVERSATIONS:
    fail("Shared/Conversations.lua is missing: you cannot say anything to anyone")
else:
    topics_block = CONVERSATIONS[CONVERSATIONS.find("Conversations.TOPICS = {"):CONVERSATIONS.find("Conversations.NOTES = {")]
    people = {}
    for person, body in re.findall(r"^\t(\w+) = \{\n(.*?)^\t\},", topics_block, re.M | re.S):
        people[person] = re.findall(r'\{ id = "(\w+)", say = "([^"]*)",(.*?)reply = \{\n(.*?)\n\t\t\} \},', body, re.S)
        if len(people[person]) != len(re.findall(r'\bid = "', body)):
            fail("Conversations: this check can no longer read every topic of %s's" % person)
    notes = dict(re.findall(r'^\t(\w+) = \{ title = "([^"]+)"', CONVERSATIONS, re.M))
    ids, gives, needs, afters = set(), {}, [], []
    for person, rows in people.items():
        if person not in LINES:
            fail("Conversations: %s is no one the town has (Townsfolk.LINES)" % person)
        if not rows:
            fail("Conversations: %s has nothing you can ask" % person)
        for tid, say, extra, reply in rows:
            if tid in ids:
                fail("Conversations: two topics are called %s" % tid)
            ids.add(tid)
            lines = re.findall(r'"([^"]*)"', reply)
            if not lines:
                fail("Conversations: %s has no answer" % tid)
            for text in [say] + lines:
                if re.search(r"--|—|–", text):
                    fail("Conversations: a dash in %s: %r" % (tid, text))
            found_after = re.search(r'after = "(\w+)"', extra)
            found_needs = re.search(r'needs = "(\w+)"', extra)
            found_clue = re.search(r'clue = "(\w+)"', extra)
            if found_after:
                afters.append((tid, found_after.group(1)))
            if found_needs:
                needs.append((tid, found_needs.group(1)))
            if found_clue:
                gives.setdefault(found_clue.group(1), []).append(tid)
    for tid, other in afters:
        if other not in ids:
            fail("Conversations: %s comes after %s, which nobody can be asked" % (tid, other))
    for tid, clue in needs:
        if clue not in gives:
            fail("Conversations: %s needs the clue %s, which nothing gives" % (tid, clue))
    for clue in gives:
        if clue not in notes:
            fail("Conversations: the clue %s puts nothing in your journal (NOTES)" % clue)
    # FOLLOWABLE FROM THE START: learn what can be learned, over and over, until nothing new is; every clue learned.
    known, changed = set(), True
    all_rows = {tid: (extra,) for rows in people.values() for tid, _, extra, _ in rows}
    while changed:
        changed = False
        for tid, (extra,) in all_rows.items():
            if tid in known:
                continue
            a = re.search(r'after = "(\w+)"', extra)
            n = re.search(r'needs = "(\w+)"', extra)
            if (not a or a.group(1) in known) and (not n or "clue:" + n.group(1) in known):
                known.add(tid)
                c = re.search(r'clue = "(\w+)"', extra)
                if c:
                    known.add("clue:" + c.group(1))
                changed = True
    for tid in all_rows:
        if tid not in known:
            fail("Conversations: %s can never be asked (what it waits for never comes)" % tid)
    for clue in ("face", "marsh", "father", "price"):
        if "clue:" + clue not in known:
            fail("Conversations: the story's thread breaks: %s can never be learned" % clue)
    for needle, why in (
        ("function Townsfolk.offer(player: Player, npc: Person)", "your choices are never offered"),
        ("function Townsfolk.answer(player: Player, name: string, id: string)", "a choice is never answered"),
        ("for _, offered in ipairs(Conversations.offered(name, knownBy(player))) do", "a choice not offered can be said"),
        ("> Conversations.REACH + 6 then", "you can talk to someone from across the level"),
        ("Townsfolk.speakAs(player, said)", "you never say your line"),
        ('pcall(book.take, player, { title = note.title, body = note.body }, nil, "note", { from = note.from })',
         "what you learn is not written in your journal"),
        ('pcall(save.markHeard, player, key)', "what you said is forgotten between sessions"),
    ):
        if needle not in TOWNS:
            fail("Townsfolk: " + why)
    TALK_CLIENT = read("Client", "Services", "TalkClient.lua") or ""
    for needle, why in (
        ("(root.Position - head.Position).Magnitude > reach then\n\t\t\thide()", "walking away does not put the choices away"),
        ('remote:FireServer("say", offer.person, option.id)', "a choice is never said"),
        ("GuiService.SelectedObject = ui.buttons[1]", "a controller cannot choose"),
    ):
        if needle not in TALK_CLIENT:
            fail("TalkClient: " + why)
    if 'ensureRemoteEvent(remoteEventsFolder, "Talk")' not in BOOT:
        fail("Bootstrap never makes the Talk remote")

if problems:
    for problem in problems:
        print("FAIL: " + problem)
    sys.exit(1)
print("story: %d people with lines (%s), four numbered openings on one day, things to read on every level, the "
      "time card in the player's name, clean words, every ending wired as a scene at half speed, everyone dressed, "
      "every material with a sound, six seconds on LEVEL COMPLETE."
      % (len(LINES), ", ".join(sorted(LINES))))
