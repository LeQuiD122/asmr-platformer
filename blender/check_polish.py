"""The polish passes (the hundred-and-thirty-seventh onward): how the game feels between the big moments.

Run with plain Python from the project root:  python blender/check_polish.py

What it holds:
  IN AND OUT OF A RUN UNDER A DIP (137). Every move into a level and out of one fades to black first, the place is
  streamed in round where you are going while it is black, the level's name is on the black, and the picture fades
  back up; a fall caught in Chill is a cut to black that fades back; the kill plane catches a fall once, not on every
  frame the character is still under it; the fade covers the whole screen.
  A CHECKPOINT REACHED, FELT (138). The furthest checkpoint of the run marked on the player (new ground only: back to
  nothing as a run starts or starts again); RunFeel's ring over the slab, kept on it, a real light, gone after; the
  chime's takes as its generator writes them, never the same twice running, never over a scene.
  THE SCREEN PUT RIGHT (139). The best times cleared, as many as their panel holds, names found first, one refresh at a
  time; the folded clock off a phone's thumb, the panels stacked as tall as the readout is; the run's panels on a level
  only; the pause card where you are; the vote card in a person's words, no dashes; the death card coming up; a run's
  tokens told after its scene.
  A SCENE ALWAYS LETS GO (140). A time no scene runs past, longer than the longest ending and the longest moment; a new
  character ends one; Reset held back in one; what is open put away before the controls are taken; the lens marks, the
  hints and the run's panels off its picture, and back after.
  THE SMALL THINGS (141). Every sound folder the game plays from fetched ahead; a Reset in a run a fall (Chill: your
  checkpoint under a dip; Hardcore: the fall's card); back on your feet in a moment and a half.
  ONE NOTICE AT A TIME (142). The vote card's notices queued, a few at most, each read before the next, none under a
  scene or the black; the answers to what you just did said at once.
  PUT AWAY FOR THE BLACK (143). Every black and every dip the server sends puts away what is open first (the list a
  scene puts away, the post box's card on it); and nothing in the game's own screens is drawn over the black but the
  squish room's own cover and the Studio test panel.
  ONE SOFT SOUND FOR EVERY PRESS (144). AudioService.press plays one slot of the menus' sheet (a tap never twice
  running), a soft click where it is not imported and never the engine's ping; the shop's own sounds go through it;
  the pause card opening and going, the death card's choices, the journal's tabs, pages and closing and the words you
  choose each make it; a refusal in the shop says no.
  A LONG SERVER STAYS QUICK (145). The server lets go of a level's platforms when it is taken down (its frame loop
  walked every cell of every level ever built); the client's tables of what each tile is doing are weak-keyed or swept
  of parts no longer in the world, every one of them.
  THE LEVELS' OWN SOUNDS (146). The harbour's rain and its bell, Outfall 3's key and the chamber's two splashes are
  sounds of the game's own (the engine's only where those are not imported, and the rain never played fast); and no
  sound anywhere in the game is played pitched up (a PlaybackSpeed over 1.25).
  THE WORDS (147). A key named on the screen is named only to a keyboard (a controller and a phone told their own: the
  secret's card, the journal's foot, first person's Ctrl); the emotes' hint names the menu; nothing tells a mouse to
  tap; the lobby's signs in the vote card's dots; no level described as it was in the first weeks.
  THE STORY'S DAYS AND THE MATERIALS' NAMES (148). Every date the game shows is one of the Hold's days (the eleventh
  to the fourteenth of August, and the fifteenth it ends on), and Wick's year on the key holders' list is the one he
  tells (forty years back, thirty since Marsh); the squish room's signs call each material what the lobby's board and
  the journal do.
  THE RUN SCREEN'S PRESSES (149). The clock folding down and opening and the best times put away and brought back make
  the press too, as a card going and coming.

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


BOOT = read("Server", "Bootstrap.server.lua")
CLIENT_BOOT = read("Client", "Bootstrap.client.lua")
UI = read("Client", "Services", "UIService.lua")
for name, text in (("the server Bootstrap", BOOT), ("the client Bootstrap", CLIENT_BOOT), ("UIService", UI)):
    if not text:
        fail("missing " + name)

# ===================================================================== in and out of a run (137)

dip = re.search(r"^local DIP = \{ out = ([\d.]+), back = ([\d.]+), stream = ([\d.]+), fall = ([\d.]+) \}", BOOT, re.M)
if not dip:
    fail("Bootstrap: no DIP (how long a move's fade takes each way, and how long the place is waited for)")
else:
    out, back, stream, fall = (float(v) for v in dip.groups())
    if out > 0.6:
        fail("Bootstrap: the fade to black before a move takes %.2f s: it feels like the game has stopped" % out)
    if not 0.5 <= back <= 1.5:
        fail("Bootstrap: the fade back up after a move takes %.2f s (between half a second and a second and a half)" % back)
    if not 2 <= stream <= 6:
        fail("Bootstrap: the place is waited for %.1f s at most (two to six: long enough to arrive, never a hang)" % stream)
    if fall > 0.8:
        fail("Bootstrap: a fall caught in Chill takes %.2f s to fade back: you lose sight of where you are" % fall)

stream_fn = within(BOOT, "local function streamFor(")
if "player:RequestStreamAroundAsync(at, DIP.stream)" not in stream_fn:
    fail("Bootstrap: nothing streams the place in before you are put there")
if "task.spawn(function()" not in stream_fn:
    fail("Bootstrap: the place is streamed in to one player after another, not to everyone at once")

chosen = within(BOOT, "local function startChosenLevel(")
if not in_order(chosen, "streamFor(players, levelInstance.startPosition)", "hrp.CFrame = CFrame.new(levelInstance.startPosition)"):
    fail("Bootstrap: you are put on a level's start before your screen has it (stream it in first)")
if "ScreenFade:FireClient(player, { card = card })" not in chosen:
    fail("Bootstrap: nothing says which level it is on the black")

lobby = within(BOOT, "local function startFromLobby(")
if not in_order(lobby, "ScreenFade:FireClient(player, { black = true, time = DIP.out })", "task.wait(DIP.out)",
                "local ok, result = pcall(function()", "ScreenFade:FireClient(player, { black = false, time = DIP.back })",
                "error(result, 0)"):
    fail("Bootstrap: a run from the lobby starts with a cut, or a failed start leaves everyone in the dark")
if "startChosenLevel(level, players, origin, cardFor(level))" not in lobby:
    fail("Bootstrap: a level from the lobby has no name on the black")
if "cardFor(level, run))" not in within(BOOT, "local function storyLevel("):
    fail("Bootstrap: a story's level has no name on the black")

home = within(BOOT, "local function goHome(")
if not in_order(home, "if homeGoing[player] or player.Parent ~= Players then", "homeGoing[player] = true",
                "ScreenFade:FireClient(player, { black = true, time = DIP.out })", "held.Anchored = true",
                "task.wait(DIP.out)", "streamFor({ player }, HubService.spawnPosition())", "held.Anchored = false",
                "HubService.returnToHub(player)", "ScreenFade:FireClient(player, { black = false, time = DIP.back })"):
    fail("Bootstrap: going home is not black, streamed in, set down and faded back up, in that order")
if "pcall(after)" not in home:
    fail("Bootstrap: something going wrong once home leaves the screen black")
complete = within(BOOT, "local function completeRun(")
if "\t\t\tgoHome(player)\n" not in complete:
    fail("Bootstrap: a finished run goes home with a cut")
leave = within(BOOT, "LeaveLevel.OnServerEvent:Connect(function(player: Player)", "\nend)\n")
if "goHome(player, function()\n\t\t\tstoryLeave(player)\n\t\tend)" not in leave:
    fail("Bootstrap: leaving from the menu goes home with a cut (or not out of the story once home)")
if "task.spawn(goHome, player)" not in within(BOOT, "local function storyNext("):
    fail("Bootstrap: the end of a story goes home with a cut")
for where, needle in (("storyTimeUp", "local function storyTimeUp("), ("storyStep", "local function storyStep(")):
    if not in_order(within(BOOT, needle), "ScreenFade:FireClient(player, { dip = true, time = DIP.back })",
                    "HubService.returnToHub(player)"):
        fail("Bootstrap: %s takes a story player to the lobby with a jump cut" % where)

plane = within(BOOT, 'game:GetService("RunService").Heartbeat:Connect(function()', "\nend)\n")
if "if homeGoing[player] then\n\t\t\tcontinue\n\t\tend" not in plane:
    fail("Bootstrap: someone held still going home is taken for a fall")
if not in_order(plane, "local last = caughtAt[player]", "if last and os.clock() - last < CATCH_GAP then",
                "caughtAt[player] = os.clock()", "state.falls = (state.falls or 0) + 1"):
    fail("Bootstrap: one fall is counted on every frame the character is still under the plane")
gap = re.search(r"^local CATCH_GAP = ([\d.]+)$", BOOT, re.M)
if not gap or not 0.5 <= float(gap.group(1)) <= 2:
    fail("Bootstrap: CATCH_GAP is not between half a second and two (a fall caught once)")
if not in_order(plane, "hrp.CFrame = CFrame.new(groundedRecovery(behind, state.checkpointPosition))",
                "ScreenFade:FireClient(player, { dip = true, time = DIP.fall })"):
    fail("Bootstrap: a fall caught in Chill is a jump cut")
removing = within(BOOT, "Players.PlayerRemoving:Connect(function(player: Player)\n\t-- LEFT THE SERVER", "\nend)\n")
for needle in ("homeGoing[player] = nil", "caughtAt[player] = nil"):
    if needle not in removing:
        fail("Bootstrap: a player who leaves is kept in %s" % needle.split("[")[0])

if "fadeGui.IgnoreGuiInset = true" not in UI or "blackout.Parent = fadeGui" not in UI:
    fail("UIService: the fade stops short of the top of the screen (a strip of the world over every move)")
if not in_order(within(UI, "function UIService.dip("), "blackout.BackgroundTransparency = 0", "UIService.fadeFromBlack("):
    fail("UIService: a dip never goes black")
for needle, why in (
    ("function UIService.fadeCard(card: any)", "the level's name cannot be put on the black"),
    ("function UIService.isBlack(): boolean", "nothing can tell that the screen is black"),
    ("showCard(false, math.min(0.3, over * 0.4))", "the level's name stays up after the black has gone"),
):
    if needle not in UI:
        fail("UIService: " + why)
for needle, why in (
    ("UIService.fadeToBlack(payload.time, payload.card)", "the level's name never reaches the black"),
    ("elseif payload.card then\n\t\t\tUIService.fadeCard(payload.card)", "the level's name never reaches the black"),
):
    if needle not in CLIENT_BOOT:
        fail("the client Bootstrap: " + why)

if not in_order(CLIENT_BOOT, "if payload.dip then", "UIService.dip(payload.time)"):
    fail("the client Bootstrap: a dip is never seen")

# ===================================================================== a checkpoint reached (138)

RUN_FEEL = read("Client", "Services", "RunFeel.lua")
if not RUN_FEEL:
    fail("there is no RunFeel: reaching a checkpoint says nothing")
if '"RunFeel", "StalkerClient" }) do' not in CLIENT_BOOT:
    fail("the client Bootstrap never starts RunFeel")
wired = within(BOOT, "function wireCheckpointing(")
if not in_order(wired, "PlayerStateService.setCheckpoint(player, checkpointPos, entry.index, backward)",
                "if reached and entry.index > (reached.furthest or 0) then", "reached.furthest = entry.index",
                'player:SetAttribute("Checkpoint", entry.index)'):
    fail("Bootstrap: a checkpoint further on than any before is never said (or every touch of one is)")
if not in_order(chosen, "PlayerStateService.beginRun(player, request.mode :: any)", 'player:SetAttribute("Checkpoint", 0)'):
    fail("Bootstrap: a new run's checkpoints are not new ground (the last run's furthest is kept)")
if not in_order(within(BOOT, "local function joinRunLate("), "PlayerStateService.beginRun(", 'player:SetAttribute("Checkpoint", 0)'):
    fail("Bootstrap: someone joining a run late starts with the last run's checkpoints")
if not in_order(within(BOOT, "local function restartRunFor("), "PlayerStateService.restartRun(",
                'player:SetAttribute("Checkpoint", 0)'):
    fail("Bootstrap: after a Hardcore fall the checkpoints are not new ground again")
if not in_order(BOOT, "now.furthest = fall.chunk", 'player:SetAttribute("Checkpoint", fall.chunk)'):
    fail("Bootstrap: a second chance puts you back at your checkpoint without saying so")
for needle, why in (
    ('me:GetAttributeChangedSignal("Checkpoint"):Connect(function()', "nothing listens for a checkpoint reached"),
    ("local further = now > furthest and now > 1", "the slab you start on, or one already reached, is said again"),
    ('if level == nil or level == "backRooms" or inScene() then', "a checkpoint is said over a scene, in the back rooms or the lobby"),
    ('local folder = SoundService:FindFirstChild("StorySounds")\n\tlocal sheet = folder and folder:FindFirstChild("CheckpointChime_x3")',
     "the chime is not looked for in StorySounds"),
    ("(s :: any).PlaybackRegion = NumberRange.new(from, from + CHIME.slot - 0.05)", "a take plays on into the next"),
    ("if take == lastTake then", "the same take of the chime can come twice running"),
    ('local glow = Instance.new("PointLight")', "the glow is not a real light"),
    ("plate.CanCollide = false", "the ring's plate is in your way"),
    ("plate.CanQuery = false", "the ring's plate is in your way"),
    ("game:GetService(\"Debris\"):AddItem(plate, RING.seconds + RING.second + 0.6)", "the ring is left lying on the slab"),
):
    if needle not in RUN_FEEL:
        fail("RunFeel: " + why)
if "Material.Neon" in RUN_FEEL:
    fail("RunFeel: a lit block faking light (Neon); light comes from a light")
ring = re.search(r"local RING = \{ reach = ([\d.]+), seconds = ([\d.]+),", RUN_FEEL)
if not ring:
    fail("RunFeel: this check can no longer read the ring")
else:
    if not 0.5 <= float(ring.group(1)) <= 0.95:
        fail("RunFeel: the ring spreads to %s of the slab: past its edge, into the air (or hardly at all)" % ring.group(1))
    if not 0.6 <= float(ring.group(2)) <= 1.6:
        fail("RunFeel: the ring takes %s s: a flash, or a crawl" % ring.group(2))
chime_spec = re.search(r"local CHIME = \{ takes = (\d+), slot = ([\d.]+), volume = ([\d.]+) \}", RUN_FEEL)
gen = (ROOT / "audio" / "gen_checkpoint_sfx.py")
gen_text = gen.read_text(encoding="utf-8") if gen.exists() else ""
gen_slot = re.search(r"^SLOT = ([\d.]+)$", gen_text, re.M)
dyads = re.search(r"^DYADS = \((.*)\)$", gen_text, re.M)
gen_takes = len(re.findall(r"\(\d+\.\d+, \d+\.\d+\)", dyads.group(1))) if dyads else 0
wav = ROOT / "audio" / "story" / "CheckpointChime_x3.wav"
if not (chime_spec and gen_slot and wav.exists()):
    fail("the checkpoint chime: its generator, its file or RunFeel's CHIME is missing or unreadable")
else:
    takes, slot, volume = int(chime_spec.group(1)), float(chime_spec.group(2)), float(chime_spec.group(3))
    if abs(slot - float(gen_slot.group(1))) > 1e-6 or takes != gen_takes or takes != 3:
        fail("RunFeel plays the chime as %d takes of %.2f s, and gen_checkpoint_sfx.py writes %d of %s" % (
            takes, slot, gen_takes, gen_slot.group(1)))
    import wave
    with wave.open(str(wav)) as w:
        length = w.getnframes() / w.getframerate()
    if abs(length - slot * takes) > 0.02:
        fail("CheckpointChime_x3.wav is %.2f s, not %d slots of %.2f s" % (length, takes, slot))
    if volume > 0.6:
        fail("RunFeel: the chime at %.2f is louder than the chunks it sounds over" % volume)

# ===================================================================== the screen put right (139)

clear_rows = within(UI, "local function clearRows()")
if "for _, child in ipairs(leaderboardContent:GetChildren()) do" not in clear_rows:
    fail("UIService: the best times' rows are never cleared (they are in Content, not the panel): every refresh stacks another board")
refresh = within(UI, "function UIService.refreshLeaderboard(")
top_rows = re.search(r"^local TOP_ROWS = (\d+)$", UI, re.M)
open_height = re.search(r"^local OPEN_HEIGHT = (\d+)$", UI, re.M)
if not (top_rows and open_height):
    fail("UIService: this check can no longer read how many rows the board shows, or how tall it is")
else:
    # Inside the panel: its padding (16 a side), the title (18) and the spacer (8) with the list's gaps (4), then rows of
    # 28 with a gap of 4 each.
    room = int(open_height.group(1)) - 32 - 34
    if int(top_rows.group(1)) * 32 > room + 4:
        fail("UIService: %s rows of best times do not fit a %s-pixel board: they spill out of it" % (
            top_rows.group(1), open_height.group(1)))
if not in_order(refresh, "refreshTicket += 1", "names[index] = nameFor(entry.userId)", "if refreshTicket ~= ticket then",
                "clearRows()"):
    fail("UIService: two refreshes of the board close together draw into each other (names not found first)")
if "nameFor(" in refresh[refresh.find("for i, entry in ipairs(shown) do"):]:
    fail("UIService: a name is looked up on the web for each row as it is drawn")
if "shown[TOP_ROWS] = { rank = i, userId = data[i].userId, time = data[i].time }" not in refresh:
    fail("UIService: someone on the board below the rows shown never sees their own place")
touch = within(UI, "if input.TouchEnabled and not input.KeyboardEnabled then", "\n\tend\n")
if not in_order(touch, "timerPanel.Position = UDim2.new(1, -SPACE.xl, 0, top + MODE_TALL + SPACE.sm)",
                "timerPill.AnchorPoint = Vector2.new(1, 0)", "timerPill.Position = timerPanel.Position"):
    fail("UIService: on a phone the folded clock stays down under the jump button")
if "modeButton.Size = UDim2.new(0, 96, 0, MODE_TALL)" not in UI \
        or "timerPanel.Position = UDim2.new(1, -SPACE.xl, 1, -(SPACE.xl + MODE_TALL + SPACE.sm))" not in UI \
        or "tooltip.Position = UDim2.new(1, -SPACE.xl, 1, -(SPACE.xl + MODE_TALL + SPACE.sm + 46 + SPACE.sm))" not in UI:
    fail("UIService: the clock and the tooltip are not stacked on the mode readout as tall as it is")
for needle, why in (
    ("timerPanel.Visible = timerShown and not timerFolded and onLevel()", "the hardcore clock stays up in the lobby"),
    ("timerPill.Visible = timerShown and timerFolded and onLevel()", "the folded clock stays up in the lobby"),
    ('return visible and (currentMode == "hardcore" or chillBoardEnabled) and onLevel()', "the best times stay up in the lobby"),
    ("modeButton.Visible = onLevel()", "the mode readout stays up in the lobby"),
    ('player:GetAttributeChangedSignal("InLevel"):Connect(showForPlace)', "the run's panels never follow you on and off a level"),
):
    if needle not in UI:
        fail("UIService: " + why)

PAUSE = read("Client", "Services", "PauseMenuService.lua")
face_fn = within(PAUSE, "local function showFace()")
for needle, why in (
    ('face.heading.Text = if rooms then "The back rooms" elseif running then "This run" else "In the lobby"',
     "the pause card says This run in the lobby"),
    ("face.leave.Visible = level ~= nil", "the pause card offers a way out of the lobby, where there is none"),
    ('face.resume.Text = if level ~= nil then "Keep running" else "Back"', "the pause card says Keep running in the lobby"),
    ("card.Size = UDim2.new(0.92, 0, 0, rowY + 44 + 24)", "the pause card keeps the run's height round fewer buttons"),
):
    if needle not in face_fn:
        fail("PauseMenuService: " + why)
if "\t\tshowFace()\n\t\tframe.Visible = true" not in PAUSE:
    fail("PauseMenuService: the card opens without saying where you are")
if 'Players.LocalPlayer:GetAttributeChangedSignal("InLevel"):Connect(showFace)' not in PAUSE:
    fail("PauseMenuService: the card does not follow you on and off a level")
if "face.runName = levelName" not in within(PAUSE, "function PauseMenuService.setRun("):
    fail("PauseMenuService: the vote's level is written over the lobby's card")

VOTE = read("Client", "Services", "HubVoteService.lua")
for needle, why in (
    ('("%s  ·  %s run  ·  %d %s voted"):format(\n\t\t\tcap(result.mode), cap(result.length),', "the result card reads as the server's words"),
    ("cap(leading.mode), votes.mode or 0,\n\t\tcap(leading.length), votes.length or 0)", "the tally reads as the server's words"),
):
    if needle not in VOTE:
        fail("HubVoteService: " + why)
VOTE_CODE = "\n".join(line for line in VOTE.split("\n") if not line.strip().startswith("--"))
for literal in re.findall(r'"((?:[^"\\\n]|\\.)*)"', VOTE_CODE):
    if " - " in literal or "--" in literal:
        fail("HubVoteService: a dash on the vote card: %r" % literal)

DEATH = read("Client", "Services", "DeathService.lua")
arrive = re.search(r"^local ARRIVE = ([\d.]+)$", DEATH, re.M)
if not arrive or not 0.15 <= float(arrive.group(1)) <= 0.6:
    fail("DeathService: the death card does not come up over a moment (ARRIVE)")
if not in_order(DEATH, "title.TextTransparency, sub.TextTransparency, tint.BackgroundTransparency = 1, 1, 1",
                "gui.Enabled = true", "local come = math.clamp(since / ARRIVE, 0, 1)",
                "title.TextTransparency = 1 - (0.85 - breath * 0.45) * come"):
    fail("DeathService: the death card is switched on, half-way through a breath")

SHOP = read("Client", "Services", "ShopService.lua")
held = within(SHOP, "local function heldBack(): boolean")
if "cinema.active()" not in held or "ui.isBlack()" not in held:
    fail("ShopService: a run's tokens are told under the scene's bars or the black of the move home")
wait = re.search(r"while heldBack\(\) and os\.clock\(\) - began < (\d+) do", within(SHOP, "local function earned("))
if not wait or int(wait.group(1)) > 90:
    fail("ShopService: a run's tokens wait for nothing, or for ever")
if "showEarned(amount, info)" not in within(SHOP, "local function earned("):
    fail("ShopService: a run's tokens are never told")

# ===================================================================== a scene always lets go (140)

CINEMA = read("Client", "Services", "Cinema.lua")
most = re.search(r"^local MOST = \{ ending = (\d+), moment = (\d+) \}", CINEMA, re.M)
HALLS_SV = read("Server", "Services", "FloodedHallsService.lua")
HALLS_CL = read("Client", "Services", "FloodedHallsClient.lua")
STORY_CL = read("Client", "Services", "StoryClient.lua")
slide = re.search(r"^local SLIDE_SECONDS = ([\d.]+)", HALLS_SV, re.M)
gates = {k: float(v) for k, v in re.findall(r"^\t(SECONDS|TRUE|MAW) = ([\d.]+),", within(HALLS_SV, "local GATES = {", "\n}\n"), re.M)}
moment = re.search(r"^local MOMENT = \{ ponder = ([\d.]+), close = ([\d.]+) \}", STORY_CL, re.M)
caught = re.search(r"^local CAUGHT = \{ loom = [\d.]+, face = [\d.]+, black = ([\d.]+) \}", STORY_CL, re.M)
clock = re.search(r"^local CLOCK = \{ card = ([\d.]+), shift = ([\d.]+),", HALLS_CL, re.M)
if not (most and slide and len(gates) == 3 and moment and caught and clock):
    fail("this check can no longer read a scene's time limit (Cinema's MOST) or how long the longest scenes are")
else:
    ending, short = int(most.group(1)), int(most.group(2))
    # The longest ending: the halls' flume, the mouth, the gates and the true ending after them, and its captions read.
    longest = float(slide.group(1)) + gates["MAW"] + gates["SECONDS"] + gates["TRUE"] + 15
    if ending < longest or ending > 300:
        fail("Cinema: an ending may run %d s, and the halls' true ending takes about %.0f (a limit between it and five "
             "minutes)" % (ending, longest))
    # The longest moment: a secret found (pondered, closed on, its caption read), his catch, the clock.
    moment_longest = max(float(moment.group(1)) + float(moment.group(2)) + 10, float(caught.group(1)),
                         float(clock.group(1)) + float(clock.group(2)))
    if short < moment_longest + 10 or short > 90:
        fail("Cinema: a moment may run %d s: under its longest (%.0f s and its reading) or long enough to strand you" % (
            short, moment_longest))
for needle, why in (
    ("RunService:BindToRenderStep(SHOW, Enum.RenderPriority.Camera.Value + 2, sceneStep)", "a scene's time is never kept"),
    ("if current and not current.overdue and os.clock() - current.began > current.most then", "a scene can run for ever"),
    ("task.defer(left)", "a scene past its time is never put away"),
    ("began = os.clock(),\n\t\tmost = if ending then MOST.ending else MOST.moment, overdue = false }", "a scene's time is not set as it begins"),
    ("me.CharacterAdded:Connect(function()\n\t\tif live then\n\t\t\tleft()", "a new character is left in the old one's scene"),
    ('game:GetService("StarterGui"):SetCore("ResetButtonCallback", on)', "Roblox's Reset is never held back in a scene"),
):
    if needle not in CINEMA:
        fail("Cinema: " + why)
begin_fn = within(CINEMA, "function Cinema.begin(")
finish_fn = within(CINEMA, "function Cinema.finish(")
if not in_order(begin_fn, "closeOverlays()", "found:Disable()", "allowReset(false)", "quietScreens(true)"):
    fail("Cinema: a scene starts with Reset, the open menus or the lens marks and the run's panels left as they were")
if not in_order(finish_fn, "holdStill(false)", "allowReset(true)", "quietScreens(false)"):
    fail("Cinema: a scene ends without Reset, the lens marks, the hints or the run's panels back")
overlays = within(CINEMA, "local function closeOverlays()")
PAUSE_SRC = read("Client", "Services", "PauseMenuService.lua")
JOURNAL = read("Client", "Services", "JournalService.lua")
EMOTES = read("Client", "Services", "EmoteService.lua")
TALK = read("Client", "Services", "TalkClient.lua")
SCREEN_FX = read("Client", "Services", "ScreenEffects.lua")
WELCOME = read("Client", "Services", "OnboardingService.lua")
for module, calls, source, has in (
    ("PauseMenuService", ("m.isOpen()", "m.setOpen(false)"), PAUSE_SRC,
     ("function PauseMenuService.isOpen(): boolean", "function PauseMenuService.setOpen(on: boolean)")),
    ("JournalService", ("m.isOpen()", "m.toggle()"), JOURNAL, ("function JournalService.isOpen(): boolean", "function JournalService.toggle()")),
    ("ShopService", ("m.close()",), SHOP, ("function ShopService.close()",)),
    ("EmoteService", ("m.close()",), EMOTES, ("function EmoteService.close()",)),
    ("TalkClient", ("m.dismiss()",), TALK, ("function TalkClient.dismiss()\n\thide()",)),
):
    block = within(overlays, 'besideDo("%s", function(m)' % module, "\n\tend)\n")
    if not all(call in block for call in calls):
        fail("Cinema: %s is left open over a scene" % module)
    if not all(needle in source for needle in has):
        fail("%s cannot be put away from outside (Cinema asks it to, as a scene starts)" % module)
quiet = within(CINEMA, "local function quietScreens(on: boolean)")
if '{ "MaterialLensMarks", "Hints" }' not in quiet:
    fail("Cinema: the lens marks or the hints stay over a scene's picture")
if 'gui.Name = "MaterialLensMarks"' not in SCREEN_FX or 'gui.Name = "Hints"' not in WELCOME:
    fail("Cinema puts away screens by names that ScreenEffects or OnboardingService no longer use")
if "m.sceneOn(on)" not in quiet or "sceneHeld = on\n\tshowForPlace()" not in within(UI, "function UIService.sceneOn("):
    fail("UIService: the run's panels stay over a scene's picture")
if 'return player:GetAttribute("InLevel") ~= nil and not sceneHeld' not in UI:
    fail("UIService: the run's panels are shown under a scene")

# ===================================================================== the small things (141)

AUDIO = read("Client", "Services", "AudioService.lua")
folders = re.search(r"^local PRELOAD_FOLDERS = \{ ([^}]*) \}", AUDIO, re.M)
listed = set(re.findall(r'"(\w+)"', folders.group(1))) if folders else set()
played = set()
for path in SRC.rglob("*.lua"):
    played |= set(re.findall(r'FindFirstChild\("(\w+Sounds)"\)', path.read_text(encoding="utf-8")))
for name in sorted(played - {"MaterialSounds"} - listed):
    fail("AudioService: the game plays sounds from SoundService.%s and never fetches them ahead (late on a first play)" % name)
preload = within(AUDIO, "local PRELOAD_FOLDERS = {", "\nend)\n")
if not in_order(preload, "ContentProvider:PreloadAsync(fetch)", "for _, probe in ipairs(probes) do\n\t\tprobe:Destroy()"):
    fail("AudioService: only the materials' sounds are fetched ahead")
if re.search(r"for _, \w+ in ipairs\(fetch\) do\s*\w+:Destroy\(\)", preload):
    fail("AudioService: the game's own sounds are destroyed after they are fetched")
respawn = re.search(r"^Players\.RespawnTime = ([\d.]+)$", BOOT, re.M)
if not respawn or float(respawn.group(1)) > 2.5:
    fail("Bootstrap: a Reset waits Roblox's five seconds (Players.RespawnTime) to put you back")
character = within(BOOT, "local function onCharacter(character: Model)", "\n\tend\n")
if not in_order(character, "if inRunNow and state and not state.hasCompletedLevel then", 'if state.mode == "hardcore" then',
                "sendBackToStart(player)", "local at = recoverAtCheckpoint(player)", "hrp.CFrame = CFrame.new(at)",
                "ScreenFade:FireClient(player, { dip = true, time = DIP.fall })"):
    fail("Bootstrap: a Reset in a run is not a fall (Chill back at the start, Hardcore's clock running on)")
if not in_order(BOOT, "local function groundedRecovery(", "recoverAtCheckpoint = function(player: Player): Vector3?",
                "return groundedRecovery(state.checkpointPosition + back * CHILL_SETBACK_STUDS, state.checkpointPosition)"):
    fail("Bootstrap: a Reset in Chill is not put where a fall would be")

# ===================================================================== one notice at a time (142)

queue = within(VOTE, "local function nextNotice()")
kept = re.search(r"^local NOTICES_KEPT = (\d+)$", VOTE, re.M)
if not kept or not 2 <= int(kept.group(1)) <= 6:
    fail("HubVoteService: the notices are not kept to a few (NOTICES_KEPT): they pile up, or one is all")
hold = re.search(r"while heldBack\(\) and os\.clock\(\) - began < (\d+) do", queue)
if not hold or int(hold.group(1)) > 120:
    fail("HubVoteService: a notice comes up under a scene or the black, or waits for ever")
if not in_order(queue, "HubVoteService.say(notice.badge, notice.title, notice.body)", "task.wait(OPENED_FOR)",
                "noticing = false", "nextNotice()"):
    fail("HubVoteService: a second notice comes up over the first before it is read")
vote_held = within(VOTE, "local function heldBack(): boolean")
if "cinema.active()" not in vote_held or "ui.isBlack()" not in vote_held:
    fail("HubVoteService: a notice does not wait for the scene or the black")
for needle, why in (
    ('HubVoteService.tell("NEW", title, body, true)', "a level opened is said over the ending"),
    ('HubVoteService.tell("+" .. reward, title,', "a challenge done is said over the ending"),
    ('HubVoteService.tell("STORY", "Waiting for the others",', "the story's wait is said over the black"),
    ('HubVoteService.tell("STORY", "The story went on without you",', "the story's going on is said over the black"),
    ('HubVoteService.tell("+" .. percent .. "%", "Running with a friend",', "a friend in the run is said over the black"),
    ('HubVoteService.say("WAIT", "A run is still on",', "stepping on Start while a run is on is answered late"),
    ('HubVoteService.say("DAILY", "Opened today",', "the chest is answered late"),
):
    if needle not in VOTE:
        fail("HubVoteService: " + why)

# ===================================================================== put away for the black (143)

CINEMA_SRC = read("Client", "Services", "Cinema.lua")
SHOP_SRC = read("Client", "Services", "ShopService.lua")
fade_handler = within(CLIENT_BOOT, "ScreenFade.OnClientEvent:Connect(function(payload)", "\n\tend)\n")
if not in_order(fade_handler, "if payload.dip then", "putAway()", "UIService.dip(payload.time)"):
    fail("the client Bootstrap: a dip leaves what is open (the shop, the journal) over the move")
if not in_order(fade_handler, "elseif payload.black == true then", "putAway()", "UIService.fadeToBlack(payload.time, payload.card)"):
    fail("the client Bootstrap: a move under the black carries the shop or the journal onto the level")
put_away = within(CLIENT_BOOT, "local function putAway()")
if 'Services:FindFirstChild("Cinema")' not in put_away or "pcall(module.closeOverlays)" not in put_away:
    fail("the client Bootstrap: what is put away for the black is not the list a scene puts away (Cinema.closeOverlays)")
if "Cinema.closeOverlays = closeOverlays" not in CINEMA_SRC:
    fail("Cinema: the list of what is open cannot be used from outside it")
overlay_list = within(CINEMA_SRC, "local function closeOverlays()")
for module in ("PauseMenuService", "JournalService", "ShopService", "EmoteService", "TalkClient"):
    if 'besideDo("%s"' % module not in overlay_list:
        fail("Cinema: %s is not put away for a scene or a move" % module)
if "m.closeCodes()" not in overlay_list:
    fail("Cinema: the post box's card is left up over a scene or a move (it holds your controls)")
if "function ShopService.closeCodes()\n\tcloseCodes()\nend" not in SHOP_SRC:
    fail("ShopService: the post box's card cannot be put away from outside")

fade_order = re.search(r"fadeGui\.DisplayOrder = (\d+)", UI)
fade_order = int(fade_order.group(1)) if fade_order else 0
OVER_THE_BLACK = {"SquishRoomClient.lua": "the squish room's own cover", "DevPanelClient.lua": "the Studio test panel"}
for path in sorted((SRC / "Client" / "Services").glob("*.lua")):
    orders = [int(v) for v in re.findall(r"DisplayOrder = (\d+)", path.read_text(encoding="utf-8"))]
    if path.name == "UIService.lua":
        orders = [v for v in orders if v != fade_order]
    if not orders:
        continue
    if path.name in OVER_THE_BLACK:
        if fade_order >= max(orders):
            fail("UIService: the black (%d) is over %s (%d)" % (fade_order, OVER_THE_BLACK[path.name], max(orders)))
    elif fade_order <= max(orders):
        fail("UIService: the black (%d) is under %s's screen (%d): it is left floating on every move"
             % (fade_order, path.stem, max(orders)))
look = read("Client", "Services", "ShopLook.lua")
if "fx.DisplayOrder = (screen.DisplayOrder or 30) + 1" in look and fade_order <= 31:
    fail("UIService: the black is under the shop's effects (the shop's own order and one)")

# ===================================================================== one soft sound for every press (144)

AUDIO_SRC = read("Client", "Services", "AudioService.lua")
press = within(AUDIO_SRC, "function AudioService.press(kind: string?, volume: number?)")
if not press:
    fail("AudioService: no press for the menus (AudioService.press)")
else:
    if not in_order(press, 'local folder = SoundService:FindFirstChild("ShopSounds")',
                    'local sheet = folder and folder:FindFirstChild("UiTaps_x8")',
                    "(take :: any).PlaybackRegion = NumberRange.new(from, from + PRESS_SLOT - 0.05)"):
        fail("AudioService: a press does not play one slot of ShopSounds.UiTaps_x8 (it plays on into the next)")
    if "if pick == lastTap then" not in press or "lastTap = pick" not in press:
        fail("AudioService: the same tap can come twice running")
    if "if not regioned then" not in press:
        fail("AudioService: where a region cannot be set, a press plays on through the rest of the sheet")
    if 's.SoundId = "rbxasset://sounds/clickfast.wav"' not in press:
        fail("AudioService: with the sheet not imported, a press is silent or something louder than a soft click")
for name in ("AudioService.lua", "ShopService.lua", "PauseMenuService.lua", "DeathService.lua", "JournalService.lua",
             "TalkClient.lua", "OnboardingService.lua", "EmoteService.lua"):
    if "electronicpingshort" in read("Client", "Services", name):
        fail("%s: the engine's electronic ping is still a menu's sound (the one sound the game was never to make)"
             % name.replace(".lua", ""))
ui_sound = within(SHOP_SRC, "local function uiSound(event: string, volume: number)")
if not in_order(ui_sound, 'local kind = if event == "bubblePop" then "good" elseif event == "buttonClick" then "tap" else event',
                'script.Parent:FindFirstChild("AudioService")', "audio.press(kind, volume)"):
    fail("ShopService: the shop's own presses (and the welcome's and the emotes', through its kit) are not the press")
if 'FindFirstChild("MaterialSounds")' in ui_sound:
    fail("ShopService: a press is looked for in MaterialSounds again (by names nothing there has)")
for needle, why in (
    ('uiSound("no", 0.45)\n\ttoast(CRATE_WORDS[result.reason]', "a crate refused says nothing"),
    ('uiSound("no", 0.45)\n\t\t\ttoast("Not enough tokens.")', "a purchase refused says nothing"),
):
    if needle not in SHOP_SRC:
        fail("ShopService: " + why)
HELPER_NEEDLES = ('local function pressSound(kind: string)', 'script.Parent:FindFirstChild("AudioService")',
                  'audio.press(kind)')
for name, uses in (
    ("PauseMenuService.lua", [('local function slide()', 'pressSound(if open then "open" else "close")',
                               "the pause card opens and goes in silence")]),
    ("DeathService.lua", [('second.Activated:Connect(function()', 'pressSound("tap")', "the second chance is pressed in silence"),
                          ('again.Activated:Connect(function()', 'pressSound("tap")', "Try again is pressed in silence"),
                          ('out.Activated:Connect(function()', 'pressSound("tap")', "leaving is pressed in silence")]),
    ("JournalService.lua", [("\telse\n\t\tpressSound(\"close\")\n\t\tContextActionService:UnbindAction(\"JournalClose\")",
                             None, "the journal shuts in silence"),
                            ("row.Activated:Connect(function()\n\t\t\t\tpressSound(\"tap\")", None,
                             "a page is turned to in silence"),
                            ("button.Activated:Connect(function()\n\t\t\tpressSound(\"tap\")\n\t\t\tpickKind(kind.key)",
                             None, "a tab is pressed in silence")]),
    ("TalkClient.lua", [("button.Activated:Connect(function()\n\t\tpressSound(\"tap\")\n\t\tchoose(index)", None,
                         "the words you choose are pressed in silence")]),
):
    text = read("Client", "Services", name)
    module = name.replace(".lua", "")
    if not in_order(text, *HELPER_NEEDLES):
        fail("%s: no way to the press (pressSound, AudioService.press)" % module)
    declared = text.find("local function pressSound(kind: string)")
    for first, second, why in uses:
        at = text.find(first)
        if at < 0 or (second is not None and second not in within(text, first, "\n\tend)\n" if "Activated" in first else "\nend\n")):
            fail("%s: %s" % (module, why))
        elif declared < 0 or at < declared:
            fail("%s: pressSound is used before it is declared (a nil global there)" % module)

# ===================================================================== a long server stays quick (145)

DEFORM = read("Server", "Services", "DeformationService.lua")
decay = within(DEFORM, "RunService.Heartbeat:Connect(function(dt: number)", "\nend)\n")
if "for platform, state in pairs(platformStates) do\n\t\t-- A LEVEL'S PLATFORMS GO WITH IT" not in decay or not in_order(
        decay, "for platform, state in pairs(platformStates) do", "if platform.Parent == nil then",
        "platformStates[platform] = nil", "continue", "local creepDef = state.material and Materials[state.material]"):
    fail("DeformationService: a level's platforms are kept after it is taken down, and walked every frame for ever")
RENDER = read("Client", "Services", "DeformationRenderer.lua")
sweep = within(RENDER, "local kept: { { [any]: any } } = {", "\nend)\n")
if not in_order(sweep, "while true do", "task.wait(15)", "for item in pairs(list) do",
                'if typeof(item) == "Instance" and item.Parent == nil then', "list[item] = nil"):
    fail("DeformationRenderer: nothing lets go of a tile when its level is taken down")
listed = sweep[sweep.find("} } = {") + len("} } = {"):] if sweep else ""
kept_names = set(re.findall(r"\b(\w+)\b", listed[:listed.find("}")])) if listed else set()
for name, kind in re.findall(r"^local (\w+): \{ \[(BasePart|Bone|Instance|MeshPart|Model|Part)\][^\n]*= \{\}$", RENDER, re.M):
    if name not in kept_names:
        fail("DeformationRenderer: %s keeps every %s it is given (neither weak-keyed nor swept)" % (name, kind))
if not re.search(r"^local reachCache: \{ \[any\]: number \} = setmetatable\(\{\}, \{ __mode = \"k\" \}\)", RENDER, re.M):
    fail("DeformationRenderer: reachCache keeps every sheet's bones it has measured")

# ===================================================================== the levels' own sounds (146)

SUNK = read("Client", "Services", "SunkenCityClient.lua")
bell_step = within(SUNK, "local function stepBell(t: number)")
if not in_order(bell_step, 'local own = folder and folder:FindFirstChild("HarbourBell")', "if own and own:IsA(\"Sound\") then",
                "rung.RollOffMaxDistance = 900", "rung.Parent = part", "rung:Play()", "else",
                "longSound(part, PING_SOUND, 0.26, 1.1, 900)"):
    fail("SunkenCityClient: the bell tolls with the engine's ping (StorySounds.HarbourBell not played from the bell)")
rain_step = within(SUNK, "local function stepRain(t: number, dt: number, clock: number, at: Vector3?)")
if not in_order(rain_step, 'local own = folder and folder:FindFirstChild("HarbourRain")', "hiss = own:Clone()",
                'hiss:SetAttribute("Gain", 0.4)', "hiss.SoundId = RAIN_SOUND", "hiss.Looped = true"):
    fail("SunkenCityClient: the rain is the engine's falling wind (StorySounds.HarbourRain not played)")
if '(tonumber(rainSound:GetAttribute("Gain")) or 0.22) * rain' not in rain_step:
    fail("SunkenCityClient: the rain's own sound is played as loud as the stand-in")
HALLS_C = read("Client", "Services", "FloodedHallsClient.lua")
water_fn = within(HALLS_C, "local function waterSound(kind: string, volume: number, speed: number): Sound")
if not in_order(water_fn, 'shared:FindFirstChild("WaterSounds")', "water.dress(made, kind)", "made.SoundId = SPLASH"):
    fail("FloodedHallsClient: the chamber's splashes are not the water's own (WaterSounds)")
for needle, why in (
    ('keep(current, waterSound("splash", 0.8, 0.7))', "the splash up out of the sump is the engine's"),
    ('keep(current, waterSound("splash", 1, 0.55))', "the splash out of its throat is the engine's"),
    ('keep(current, sound("KeyTurn", CLICK, 0.9, 0.55, false))', "the key turns with a light switch's click"),
):
    if needle not in HALLS_C:
        fail("FloodedHallsClient: " + why)
if "sound(nil, SPLASH" in HALLS_C or "sound(nil, CLICK" in HALLS_C:
    fail("FloodedHallsClient: a scene's sound is still the engine's alone, with no name to have its own")
for path in sorted(SRC.rglob("*.lua")):
    text = path.read_text(encoding="utf-8")
    for m in re.finditer(r"^[^\n-]*\bPlaybackSpeed = (\d+(?:\.\d+)?)\s*$", text, re.M):
        if float(m.group(1)) > 1.25:
            fail("%s:%d: a sound played pitched up (PlaybackSpeed %s; the sound taste: never pitched up)" % (
                path.name, text.count("\n", 0, m.start()) + 1, m.group(1)))

# ===================================================================== the words (147)

STORY_C = read("Client", "Services", "StoryClient.lua")
JOURNAL_C = read("Client", "Services", "JournalService.lua")
VIEW_C = read("Client", "Services", "ViewModeService.lua")
read_hint = within(STORY_C, "local function readHint(): string")
if not in_order(read_hint, '== "Gamepad" then', "Press D-pad up to read it.", "elseif input.TouchEnabled and not input.KeyboardEnabled then",
                "Tap the book to read it.", "Press J to read it."):
    fail("StoryClient: a secret's card tells a controller or a phone to press J")
if "{ readHint(), 14," not in within(STORY_C, "local function card(title: string, found: number, total: number)"):
    fail("StoryClient: a secret's card does not say how to read it on the device in hand")
close_words = within(JOURNAL_C, "local function closeWords(): string")
if not in_order(close_words, '== "Gamepad" then', 'return "B to close"', "elseif UserInputService.TouchEnabled",
                'return ""', 'return "J or Esc to close"'):
    fail("JournalService: the page's foot tells a controller or a phone J or Esc")
if "ui.foot = foot" not in JOURNAL_C or not in_order(within(JOURNAL_C, "local function setOpen(on: boolean)"),
                                                      "if on then", "ui.foot.Text = closeWords()"):
    fail("JournalService: the page's foot is not said for the device in hand as the journal opens")
if not in_order(within(VIEW_C, "function ViewModeService.setView(view: string)"),
                'last.Name:sub(1, 7) ~= "Gamepad" and last ~= Enum.UserInputType.Touch',
                '(if keys then "First person. Ctrl frees the cursor." else "First person.")'):
    fail("ViewModeService: first person tells a controller or a phone about Ctrl")
for path in sorted((SRC / "Client" / "Services").glob("*.lua")):
    text = path.read_text(encoding="utf-8")
    for m in re.finditer(r'"(Press J|J or Esc)', text):
        around = text[max(0, m.start() - 500):m.end() + 500]
        if "Gamepad" not in around:
            fail("%s:%d: a key named to everyone (%s...), on a controller and a phone too" % (
                path.name, text.count("\n", 0, m.start()) + 1, m.group(1)))
if "or Emotes in the menu), and anyone near you sees it." not in SHOP_SRC:
    fail("ShopService: the emotes' hint leaves out the way to them on a phone (Emotes in the menu)")
if "Tap it to try it." in SHOP_SRC:
    fail("ShopService: a background tells a mouse to tap it")
HUB_SRC = read("Server", "Services", "HubService.lua")
if '("%spar %d:%02d  ·  %s"):format(' not in HUB_SRC or '  |  ' in HUB_SRC:
    fail("HubService: the level pads' signs are set apart with bars, not the vote card's dots")
if "exists so far" in read("Shared", "LevelDefinitions.lua"):
    fail("LevelDefinitions: a level is still described as it was in the first weeks")

# ===================================================================== the story's days, the materials' names (148)

DATED = re.compile(r"\b(?:(?:MONDAY|TUESDAY|WEDNESDAY|THURSDAY|FRIDAY|SATURDAY|SUNDAY|Monday|Tuesday|Wednesday|Thursday|"
                   r"Friday|Saturday|Sunday) (\d{1,2})\b|(\d{1,2}) (?:AUG|AUGUST|August)\b|(?:AUGUST|August) (\d{1,2})\b)")
for path in sorted(SRC.rglob("*.lua")):
    text = path.read_text(encoding="utf-8")
    for literal in re.finditer(r'"(?:[^"\\\n]|\\.)*"', text):
        for m in DATED.finditer(literal.group(0)):
            day = int(next(g for g in m.groups() if g))
            if not 11 <= day <= 15:
                fail("%s:%d: a date the Hold never reaches (%s): its days are the 11th to the 14th of August, and the "
                     "15th it ends on" % (path.name, text.count("\n", 0, literal.start()) + 1, m.group(0)))
STORY_SV = read("Server", "Services", "StoryService.lua")
wick = re.search(r"A\. Wick, (\d{4})\.", STORY_SV)
said = "forty years back" in read("Server", "Services", "Townsfolk.lua") and "Forty years back." in read("Shared", "Conversations.lua")
if not wick or (said and int(wick.group(1)) != 1979 + 30 - 40):
    fail("StoryService: the key holders' list dates Wick %s, and he says forty years back (thirty years since Marsh, 1979)"
         % (wick.group(1) if wick else "nowhere"))
SQUISH_SV = read("Server", "Services", "SquishRoomService.lua")
if re.search(r"^local NAMES\b", SQUISH_SV, re.M):
    fail("SquishRoomService: the signs have names of their own for the materials again")
named = within(SQUISH_SV, "local function spaced(name: string): string")
if not in_order(named, 'Shared:FindFirstChild("ShopCatalog")', "for _, material in ipairs(catalog.MATERIALS) do",
                "if material.key == name then", "return material.name"):
    fail("SquishRoomService: a sign's name is not the collection's (ShopCatalog.MATERIALS), as the board and the journal say it")

# ===================================================================== the run screen's presses (149)

if not in_order(UI, 'local function pressSound(kind: string)', 'script.Parent:FindFirstChild("AudioService")', "audio.press(kind)",
                "local function showTimer()"):
    fail("UIService: the run screen has no way to the press (pressSound, AudioService.press)")
for needle, why in (
    ('timerFold.Activated:Connect(function()\n\tpressSound("close")\n\ttimerFolded = true', "the clock folds in silence"),
    ('timerPill.Activated:Connect(function()\n\tpressSound("open")\n\ttimerFolded = false', "the clock opens in silence"),
    ('leaderboardOpen = not leaderboardOpen\n\tpressSound(if leaderboardOpen then "open" else "close")',
     "the best times are put away and brought back in silence"),
):
    if needle not in UI:
        fail("UIService: " + why)

if problems:
    for problem in problems:
        print("FAIL: " + problem)
    sys.exit(1)
print("polish: into and out of every run under a dip, streamed in on the black with the level's name on it, a Chill "
      "fall a cut, a fall caught once; a checkpoint further on said with a ring over the slab and two low notes; the "
      "best times drawn once and inside their panel, the run's panels on a level only, the pause card where you are, "
      "the vote card in a person's words, the death card coming up, a run's tokens told after its scene; every scene "
      "let go of in time, on a new character, with Reset held back and nothing left over its picture; every sound "
      "fetched ahead, a Reset a fall, back in a moment and a half; the notices one at a time, never under a scene; "
      "what is open put away for every move, and nothing over the black; one soft sound for every press; a level's "
      "platforms let go of when it is taken down; the levels' last stand-ins given sounds of their own, and nothing "
      "pitched up; the keys named only to a keyboard, and the lobby's signs in dots; every date one of the Hold's days, "
      "and one name for each material; the run screen's presses heard.")
