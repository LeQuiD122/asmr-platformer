"""The true ending (you chose it on 2026-10-20: clocking in, and the Watcher given his face back), checked without Studio.

    python blender/check_trueending.py

What it holds (the hundred-and-fourteenth pass, clocking in):
  * THE TIME CLOCK stands beside Mr Barlow on the gangway, on its own pillar on the deck, clear of the far rail and of
    the way along the deck; its card rack with one card, NOT CLOCKED IN.
  * IT IS EARNED: "Clock in" works only once you know what it cost the one before you (the clue "price"); before that
    Mr Barlow tells you where to go, and what he says has no dash in it.
  * CLOCKED IN: you are marked for this level (ClockedIn), and every level starts with nobody clocked in; you are stood
    at it, your card is punched on your screen (FloodedHallsClient's "clockin", its prompt gone after), a note goes in
    your journal (Conversations.NOTES.clocked, by Townsfolk.write), and Mr Barlow says his piece.
  * ITS SOUND: ClockPunch made, listed and given a stand-in.

And (the hundred-and-fifteenth pass, the ending itself):
  * HIM: Edwin Marsh stood along Outfall 3, past its gate and short of the grille at its daylight end, facing the room;
    in the Watcher's dark clothes with his own face (Townsfolk.LOOKS), the green ribbon at his neck, saying nothing.
  * ONLY FOR THE ONE WHO CLOCKED IN: the server gives a clocked in rider's gates GATES.TRUE more, and waits for them;
    the client hides him on every screen from the start, and plays the true ending only for a rider who clocked in and
    was given the time; its beats fit inside the time given, in order.
  * THE ENDING: he walks up out of the light, stops at the gate (outside the room), waves, and goes back into the light
    and out of sight; you wave back; its words say 15 August; the chord carried home (MorningChord, made and listed,
    EndChord standing in), and the scene ends.

And (the hundred-and-sixteenth pass, what it gives):
  * ONCE A SAVE, ONLY FOR THE ONE WHO CLOCKED IN: Bootstrap gives it for a rider who clocked in, before the run's own;
    its tokens (ShopCatalog.REWARD.TRUE) are paid once a save, its badge given, the save marked (TrueEnding).
  * THE KEY HOLDER'S PLAQUE over your head for everyone to see, only once it is yours: sized in studs, not drawn from
    any distance, put away on a level, over the VIP tag when there is one; put on with your clothes and when you come
    back from a level.
  * HIS LEDGE EMPTY on your screen once you have seen it (StoryClient hides the Watcher for you alone); the shop says
    what the tokens were for; the test panel can give you the whole story and the true ending, to see them.
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


STORY = read("Server", "Services", "StoryService.lua")
TOWNS = read("Server", "Services", "Townsfolk.lua")
TALK = read("Shared", "Conversations.lua")
HALLS = read("Server", "Services", "FloodedHallsService.lua")
HALLS_CLIENT = read("Client", "Services", "FloodedHallsClient.lua")
BOOT = read("Server", "Bootstrap.server.lua")


def number(text, pattern, what):
    found = re.search(pattern, text, re.M)
    if not found:
        fail("this check can no longer read %s" % what)
        return None
    return [float(g) for g in found.groups()]


# ===================================================================== the time clock, on the deck
for needle, why in (
    ("local function timeClock(parent: Instance, spot: CFrame, npc: any)", "there is no time clock"),
    ("\ttimeClock(parent, spot, npc)\nend", "Mr Barlow is stood up without his time clock beside him"),
    ('prop(model, "ClockPillar"', "the clock has nothing under it"),
    ('local card = prop(model, "ClockCard"', "there is no card in its rack"),
    ('words.Text = "KEY HOLDER\\n14 AUG\\nNOT CLOCKED IN"', "your card does not say you are not clocked in"),
    ('prompt.ActionText = "Clock in"', "the clock does not say what it does"),
):
    if needle not in STORY:
        fail("StoryService: " + why)
# CLEAR OF THE RAIL AND OF THE WAY ALONG: the gangway's numbers (FloodedHallsService) and where the clock is from him.
along = number(HALLS, r"^local MOUTH_ALONG = ([\d.]+)", "the gangway's width")
engineer = number(HALLS, r"local engineerAt = \(endFrame \* CFrame\.new\(deckTo - ([\d.]+), -1\.0, deckWide - ([\d.]+)\)\)",
                  "where Mr Barlow stands")
offset = number(STORY, r"local at = spot \* CFrame\.new\((-?[\d.]+), 0, (-?[\d.]+)\)", "where the clock is from Mr Barlow")
if along and engineer and offset:
    deck_wide = along[0] * 2
    barlow_z = deck_wide - engineer[1]
    # He faces back along the deck, so his left is toward the far rail: the clock's middle, and its card rack's far
    # face 1.1 past it on that side.
    clock_z = barlow_z - offset[0]
    rail_z = deck_wide - 0.3
    if clock_z + 1.1 > rail_z - 0.35 - 0.1:
        fail("the time clock's card rack is in the far rail (%.2f, the rail's near face at %.2f)" % (clock_z + 1.1, rail_z - 0.35))
    if clock_z - 0.8 < along[0] + 4:
        fail("the time clock stands in the way along the deck to the flume (its near side at %.1f, the way at %.1f)"
             % (clock_z - 0.8, along[0]))
    if offset[1] > -1:
        fail("the time clock is not in front of Mr Barlow, where you see it as you come along")

# ===================================================================== earned
for needle, why in (
    ('if not Townsfolk.knows(player, "clue:price") then', "you can clock in before you know what it cost him"),
    ('Townsfolk.say(npc, if Townsfolk.knows(player, "clue:father") then NOT_YET.father else NOT_YET.first)',
     "Mr Barlow says nothing when it is too soon"),
):
    if needle not in STORY:
        fail("StoryService: " + why)
lines = re.search(r"local NOT_YET = \{\n(.*?)\n\}\nlocal CLOCKED = (\"[^\"\n]*\")", STORY, re.S)
if not lines:
    fail("this check can no longer read what Mr Barlow says at the clock")
else:
    said = re.findall(r'"([^"\n]*)"', lines.group(1)) + [lines.group(2).strip('"')]
    if len(said) < 3:
        fail("Mr Barlow is missing a line at the clock")
    for text in said:
        if re.search(r"--|—|–", text):
            fail("a dash in what Mr Barlow says at the clock: %r" % text)
    if "Wick" not in said[0]:
        fail("too soon, Mr Barlow does not say who to ask (Mr Wick knew him)")
if '{ id = "barlow_marsh", say = "Tell me about my father.", needs = "father", clue = "price"' not in TALK:
    fail("Conversations: nothing gives the clue price any more, so nobody can ever clock in")
for needle, why in (
    ("function Townsfolk.knows(player: Player, key: string): boolean", "the story cannot ask what you know"),
    ("function Townsfolk.write(player: Player, key: string)", "the story cannot write in your journal"),
):
    if needle not in TOWNS:
        fail("Townsfolk: " + why)

# ===================================================================== clocked in
for needle, why in (
    ('player:SetAttribute("ClockedIn", true)', "clocking in marks nothing"),
    ("\t\tplayer:SetAttribute(\"ClockedIn\", nil)\n", "a clocking in carries on into the next level"),
    ("root.CFrame = stand", "you are not stood at the clock for the scene"),
    ('halls:FireClient(player, "clockin", model)', "your card is never punched on your screen"),
    ('pcall(Townsfolk.write, player, "clocked")', "clocking in puts nothing in your journal"),
    ("Townsfolk.say(npc, CLOCKED)", "Mr Barlow says nothing when you clock in"),
):
    if needle not in STORY:
        fail("StoryService: " + why)
if not re.search(r'^\tclocked = \{ title = "Clocked in",', TALK, re.M):
    fail("Conversations: the journal has no note for clocking in")
for needle, why in (
    ('if kind == "clockin" and typeof(player) == "Instance" and player:IsA("Model") then', "never hears it"),
    ("prompt.Enabled = false", "leaves the prompt up once you have clocked in"),
    ("words.Text = stamped", "never punches the card"),
    ('sound("ClockPunch", CLICK,', "makes no sound as the card is punched (or has no stand-in)"),
    ("Cinema.begin({ hush = false })", "plays it as an ending, and the level's sound goes"),
    ("Cinema.finish()", "never gives the camera back"),
):
    if needle not in HALLS_CLIENT:
        fail("FloodedHallsClient, clocking in: " + why)
if not (ROOT / "audio" / "endings" / "ClockPunch.wav").exists():
    fail("audio/endings/ClockPunch.wav is not made (python audio/gen_hall_sfx.py)")
# THE SOUNDS, read from Bootstrap's lists (the story's sounds, and which of them have a stand-in).
story_list = re.search(r"local STORY_SOUNDS = \{(.*?)\}", BOOT, re.S)
optional_list = re.search(r"local OPTIONAL = \{(.*?)\}", BOOT, re.S)
listed = set(re.findall(r'"(\w+)"', story_list.group(1))) if story_list else set()
optional = set(re.findall(r"(\w+) = true", optional_list.group(1))) if optional_list else set()
for name in ("ClockPunch", "MorningChord"):
    if name not in listed or name not in optional:
        fail("Bootstrap does not list %s as an optional story sound" % name)
    if not (ROOT / "audio" / "endings" / (name + ".wav")).exists():
        fail("audio/endings/%s.wav is not made (python audio/gen_hall_sfx.py)" % name)

# ===================================================================== him, in the light behind the gate
TOWNS_LOOKS = TOWNS[TOWNS.find("local LOOKS: {"):TOWNS.find("local function quiet(")]
TOWNS_LINES = TOWNS[TOWNS.find("local LINES: {"):TOWNS.find("-- HOW EACH LINE IS TOLD")]
if not re.search(r"^\tMarsh = \{ skin = [^\n]*hairStyle = \"short\",\n\t\ttop = Color3\.fromRGB\(40, 40, 44\)", TOWNS_LOOKS, re.M):
    fail("Townsfolk: Edwin Marsh has no look, or not the Watcher's dark clothes with his own face")
if re.search(r"^\tMarsh = \{", TOWNS_LINES, re.M):
    fail("Townsfolk: Edwin Marsh has lines; he says nothing (he waves)")
for needle, why in (
    ('local npc = Townsfolk.spawn(chamber, "Marsh", spot, "stand",', "Edwin Marsh is never stood in the gate chamber"),
    ('Townsfolk.wear(npc, "Ribbon",', "Edwin Marsh has no green ribbon"),
    ("\t\t\tpcall(barlow, folder)\n\t\t\tpcall(marsh)\n", "Edwin Marsh is not stood up with the baths' people"),
):
    if needle not in STORY:
        fail("StoryService: " + why)
gates = number(HALLS, r"^\tHALF_L = ([\d.]+),\n\tHIGH = [\d.]+,\n\tWALL = ([\d.]+),", "the gate chamber's length and walls")
marsh_at = number(HALLS, r"^\tMARSH_AT = (-?[\d.]+),", "where Edwin Marsh waits")
culvert = number(HALLS, r"^\tculvert\(0, ([\d.]+), ([\d.]+), ([\d.]+), true\)", "Outfall 3's size")
if gates and marsh_at and culvert:
    gate_z = -gates[0] - gates[1]
    grille_z = gate_z - culvert[2] + 1.5
    if not (grille_z + 2 < marsh_at[0] < gate_z - 4):
        fail("Edwin Marsh waits at %.1f, not inside Outfall 3 between its gate (%.1f) and its grille (%.1f)"
             % (marsh_at[0], gate_z, grille_z))
if 'model:SetAttribute("MarshSpot", frame * CFrame.new(0, 0, g.MARSH_AT) * CFrame.Angles(0, math.pi, 0))' not in HALLS:
    fail("FloodedHallsService: nobody is told where Edwin Marsh waits, or he faces away from the room")

# ===================================================================== only for the one who clocked in
for needle, why in (
    ('local gates = GATES.SECONDS + (if player:GetAttribute("ClockedIn") == true then GATES.TRUE else 0)',
     "a clocked in rider's gates are given no more time"),
    ("if chamber then gates else 0, if chamber then GATES.MAW else 0)", "the rider's screen is not told the time it has"),
    ("\t\t\t\ttask.wait(gates)\n", "the run ends before the true ending has been played"),
):
    if needle not in HALLS:
        fail("FloodedHallsService: " + why)
beats = number(HALLS_CLIENT, r"^local TRUE = \{ light = ([\d.]+), face = ([\d.]+), wave = ([\d.]+), morning = ([\d.]+), done = ([\d.]+) \}",
               "the true ending's beats")
more = number(HALLS, r"^\tSECONDS = ([\d.]+),\n\tKEY_AT = [\d.]+,\n(?:\t--[^\n]*\n)*\tTRUE = ([\d.]+),", "the gates' time")
last = number(HALLS_CLIENT, r"^\tlast = ([\d.]+),", "the chamber's last beat")
if beats and more and last:
    if beats != sorted(beats) or len(set(beats)) != len(beats):
        fail("the true ending's beats are out of order")
    if beats[0] != last[0]:
        fail("the true ending does not start where the chamber's last line would (%.1f, not %.1f)" % (beats[0], last[0]))
    if beats[-1] + 0.8 > more[0] + more[1]:
        fail("the true ending runs to %.1f s and the server gives the gates %.1f" % (beats[-1] + 0.8, more[0] + more[1]))
for needle, why in (
    ("item.LocalTransparencyModifier = 1\n\t\t\t\ttable.insert(opening.marshParts, item)", "shows Edwin Marsh on every screen"),
    ('opening.trueEnd = opening.marsh ~= nil and opening.chamber ~= nil and Players.LocalPlayer:GetAttribute("ClockedIn") == true\n\t\tand gates >= TRUE.done',
     "plays the true ending for a rider who did not clock in, or was not given the time"),
    ("\telseif current.trueEnd then\n\t\ttrueStep(current, b)\n\telseif b < current.gates + 0.8 then",
     "never plays the true ending in place of the last line"),
):
    if needle not in HALLS_CLIENT:
        fail("FloodedHallsClient: " + why)

# ===================================================================== the ending
walk = number(HALLS_CLIENT, r"^local MARSH = \{ stop = (-?[\d.]+), walk = ([\d.]+), back = (-?[\d.]+) \}", "where he walks")
if walk and gates and marsh_at and culvert:
    gate_z = -gates[0] - gates[1]
    if not (walk[0] < gate_z - 1):
        fail("Edwin Marsh walks into the room (he stops at %.1f; the gate's line is at %.1f)" % (walk[0], gate_z))
    if not (walk[2] < walk[0] and walk[2] > gate_z - culvert[2] + 1.5):
        fail("Edwin Marsh does not go back up the outfall into the light, or goes through its grille")
    if beats and (walk[0] - marsh_at[0]) / walk[1] + 0.6 > beats[1] - beats[0]:
        fail("Edwin Marsh does not reach the gate before his face is shown")
for needle, why in (
    ('Cinema.caption("Harrow Bay", "15 August. The tide went out, and the day ended.", 6)', "the day does not end (15 August)"),
    ('holdMine("wave")', "you do not wave back"),
    ("by = Poses.wave(name, b - TRUE.wave, raised, r6)", "he does not wave"),
    ('sound("MorningChord", nil, 0.7, 1, false) or sound("EndChord", nil, 0.7, 1, false)', "the chord is not carried home"),
    ("seen = 1 - math.clamp((b - (TRUE.done - 2.6)) / 2.2, 0, 1)", "he does not go out of sight into the light"),
    ("\telse\n\t\tendScene()\n\tend\nend\n\n-- THE GATE CHAMBER", "the true ending never ends"),
):
    if needle not in HALLS_CLIENT:
        fail("FloodedHallsClient, the true ending: " + why)

# ===================================================================== what it gives (the hundred-and-sixteenth pass)
ECONOMY = read("Server", "Services", "EconomyService.lua")
CATALOG = read("Shared", "ShopCatalog.lua")
STORY_CLIENT = read("Client", "Services", "StoryClient.lua")
SHOP_CLIENT = read("Client", "Services", "ShopService.lua")
DEV = read("Client", "Services", "DevPanelClient.lua")
reward = number(CATALOG, r"^\tTRUE = (\d+), --", "what the true ending pays")
if reward and not 100 <= reward[0] <= 1000:
    fail("ShopCatalog: the true ending pays %d tokens; it is the end of the story, and pays like it (100 to 1000)" % reward[0])
if not re.search(r"^\ttrueEnding = 0, --", CATALOG, re.M) and not re.search(r"^\ttrueEnding = \d+, --", CATALOG, re.M):
    fail("ShopCatalog: the true ending has no badge")
template = ECONOMY[ECONOMY.find("local TEMPLATE = {"):ECONOMY.find("type Profile = {")]
if "\tTrueEnding = false,\n" not in template:
    fail("EconomyService: the save does not keep the true ending")
give = ECONOMY[ECONOMY.find("function EconomyService.trueEnding(player: Player)"):ECONOMY.find("function EconomyService.isWelcomed(")]
for needle, why in (
    ("if not (profile and profile:IsActive()) or profile.Data.TrueEnding == true then\n\t\treturn", "is given more than once a save"),
    ("profile.Data.TrueEnding = true", "is never kept in the save"),
    ("local amount = ShopCatalog.REWARD.TRUE * (if double then 2 else 1)", "does not pay what the catalogue says"),
    ('player:SetAttribute("TrueEnding", true)', "is never told to the player's screen"),
    ("keyTag(player)", "puts no plaque over their head"),
    ("EconomyService.awardBadge, player, ShopCatalog.BADGES.trueEnding", "gives no badge"),
    ("earnedRemote:FireClient(player, amount, { trueEnding = true, double = double })", "never says what the tokens were for"),
):
    if needle not in give:
        fail("EconomyService.trueEnding " + why)
call = re.search(r'if player:GetAttribute\("ClockedIn"\) == true and EconomyService and EconomyService\.trueEnding then\n'
                 r'\t+pcall\(EconomyService\.trueEnding, player\)\n\t+end\n\t+if finishRunFor then', BOOT)
if not call:
    fail("Bootstrap: the true ending's reward is not given to a rider who clocked in as they come through the gates")
if BOOT.count("EconomyService.trueEnding, player") != 1:
    fail("Bootstrap: the true ending's reward is given somewhere else too")
plaque = ECONOMY[ECONOMY.find("local function keyTag(player: Player)"):ECONOMY.find("local function dress(player: Player)")]
for needle, why in (
    ("if not (profile and profile.Data.TrueEnding == true) then\n\t\tif existing then\n\t\t\texisting:Destroy()",
     "is over the head of someone who has not seen the true ending"),
    ("gui.Size = UDim2.new(3.6, 0, 0.95, 0)", "is not sized in studs (it would stay huge far away)"),
    ("gui.MaxDistance = 80", "is drawn from any distance"),
    ('shown.Enabled = player:GetAttribute("InLevel") == nil', "shows on a level"),
    ("if head:FindFirstChild(VIP_TAG) then 4.75 else 3.35", "sits on top of the VIP tag"),
    ('word.Text = "KEY HOLDER"', "does not say what it is"),
):
    if needle not in plaque:
        fail("EconomyService, the key holder's plaque, " + why)
for needle, why in (
    ("\tvipTag(player)\n\tkeyTag(player)\nend", "the key holder's plaque is not put on with the rest (dress)"),
    ("\t\t\tvipTag(player)\n\t\t\tkeyTag(player)\n\t\tend)", "the key holder's plaque is not put away on a level"),
    ('player:SetAttribute("TrueEnding", ready.Data.TrueEnding == true)', "a save that has seen the true ending is not told to its screen"),
    ('elseif action == "trueEnding" then', "the test panel cannot show the true ending's plaque"),
    ('elseif action == "storyKnown" then', "the test panel cannot give the whole story"),
):
    if needle not in ECONOMY:
        fail("EconomyService: " + why)
for needle, why in (
    ('{ action = "storyKnown", text = "Know the whole story" }', "has no button for the whole story"),
    ('{ action = "trueEnding", text = "True ending on/off" }', "has no button for the true ending"),
):
    if needle not in DEV:
        fail("DevPanelClient " + why)
for needle, why in (
    ('if model.Name ~= "Watcher" then', "hides someone other than the Watcher"),
    ('Players.LocalPlayer:GetAttribute("TrueEnding") == true then\n\t\t\titem.LocalTransparencyModifier = 1',
     "never empties his ledge for someone who has seen the true ending"),
    ("model.DescendantAdded:Connect(hide)", "misses what of him arrives later"),
    ("\t\t\tstoppedWaiting(model)\n", "never looks for him"),
):
    if needle not in STORY_CLIENT:
        fail("StoryClient, the Watcher gone: " + why)
if 'table.insert(reasons, "The true ending")' not in SHOP_CLIENT:
    fail("ShopService: the tokens for the true ending come with no word of what they were for")

if problems:
    for problem in problems:
        print("FAIL: " + problem)
    sys.exit(1)
print("true ending: the time clock beside Mr Barlow, on the deck, clear of the rail and the way; earned (what it cost "
      "him, first), and pointed to before; clocked in for this level only, stood at it, the card punched on your "
      "screen, a note in your journal, its own sound; and for that rider only, given the time for it, Edwin Marsh with "
      "his face walking up out of the light to the gate, the wave, and back into the morning: 15 August; paid once a "
      "save, the key holder's plaque over your head, his ledge empty on your screen.")
