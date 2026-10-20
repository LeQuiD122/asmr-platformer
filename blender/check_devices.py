"""Every screen on every device, checked without Studio: PC, phone, tablet and controller.

    python blender/check_devices.py

What it holds, for every screen the client draws:
  * A CONTROLLER CAN DO EVERYTHING. Every menu opens from a controller (the journal on D-pad up, the
    pause menu on D-pad down, the shop from a prompt or the pause menu), starts with something selected,
    closes on B, and lets go of the selection when it closes. Nothing always-on is bound to a button
    the prompts use (X for things, Y for Talk), which is how Talk used to open the journal.
  * A THUMB CAN PRESS EVERYTHING. Every button with a fixed size is at least 44 pixels each way, but
    for the few listed below with the reason they are exempt.
  * NOTHING IS WIDER THAN A PHONE. No fixed width over 360 pixels without a scale and a cap.
  * NOTHING SITS UNDER A NOTCH OR A THUMB. The menus with buttons at the screen's edge keep to the
    device's safe area; on a touch screen the run's corner panels move off the thumbstick and the jump
    button.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
CLIENT = ROOT / "src" / "Client"
problems = []


def fail(message):
    problems.append(message)


def read(name):
    path = CLIENT / "Services" / name
    return path.read_text(encoding="utf-8") if path.exists() else ""


PAUSE = read("PauseMenuService.lua")
JOURNAL = read("JournalService.lua")
DEATH = read("DeathService.lua")
UI = read("UIService.lua")
VOTE = read("HubVoteService.lua")
SHOP = read("ShopService.lua")
WELCOME = read("OnboardingService.lua")
EMOTES = read("EmoteService.lua")
TOWNSFOLK = (ROOT / "src" / "Server" / "Services" / "Townsfolk.lua").read_text(encoding="utf-8")

# Buttons allowed under a thumb's size, and why.
EXEMPT = {
    ("SunkenCityClient.lua", "shut"): "the Studio-only debug panel (F7)",
    ("UIService.lua", "modeButton"): "a readout that takes no presses (Active false)",
    ("UIService.lua", "collapse"): "a glyph; the whole panel under it is the button",
    ("UIService.lua", "leaveButton"): "in the old settings menu, which nothing opens any more",
    ("UIService.lua", "boardToggle"): "in the old settings menu, which nothing opens any more",
    ("ViewModeService.lua", "modal"): "an invisible one-pixel button that frees the cursor",
}
WIDE_EXEMPT = {("SunkenCityClient.lua", "label")}  # the Studio-only debug panel

# ===================================================================== a controller
for needle, text, why in (
    ("Enum.KeyCode.M, Enum.KeyCode.Escape, Enum.KeyCode.DPadDown", PAUSE, "the pause menu cannot be opened with a controller"),
    ("input.KeyCode == Enum.KeyCode.J or input.KeyCode == Enum.KeyCode.DPadUp", JOURNAL, "the journal cannot be opened with a controller"),
    ("GuiService.SelectedObject = firstButton", PAUSE, "the pause menu opens with nothing selected for a controller"),
    ('BindActionAtPriority("PauseMenuBack"', PAUSE, "B does not close the pause menu"),
    ("Enum.ContextActionPriority.High.Value + 5, Enum.KeyCode.ButtonB)", PAUSE, "B does not close the pause menu"),
    ("SelectedObject = ui.tabs[shownKind]", JOURNAL, "the journal opens with nothing selected for a controller"),
    ("Enum.KeyCode.Escape, Enum.KeyCode.ButtonB", JOURNAL, "B does not close the journal"),
    ("SelectedObject = firstChoice", DEATH, "the death card's choice has nothing selected for a controller"),
    ("GuiService.SelectedObject = ui.firstTile", SHOP, "the shop opens with nothing selected for a controller"),
    ("GuiService.SelectedObject = ui.primary", WELCOME, "the welcome opens with nothing selected for a controller"),
    ("D-pad up opens your journal, D-pad down the menu", WELCOME, "the welcome tells a controller player the wrong buttons"),
    ('"Press D-pad up to read it."', JOURNAL, "the journal's note tells a controller player the wrong button"),
    ("Enum.KeyCode.G, Enum.KeyCode.DPadRight)", EMOTES, "the emotes cannot be opened with a keyboard or a controller"),
    ("GuiService.SelectedObject = ui.first", EMOTES, "the emotes open with nothing selected for a controller"),
    ("Enum.KeyCode.Escape, Enum.KeyCode.ButtonB)", EMOTES, "B does not close the emotes"),
    ('local emotesButton = button("Emotes", 236', PAUSE, "a phone has no way to the emotes (the pause menu)"),
    ("gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets", EMOTES, "the emotes are not kept inside the safe area"),
    ("cells.CellSize = UDim2.fromOffset(132, kit.MIN_TOUCH + 9)", EMOTES, "the emote buttons are under a thumb's size"),
):
    if needle not in text:
        fail(why)
# THE CURSOR IS FREE WHEREVER THERE IS SOMETHING TO PRESS: in third person it is locked to the middle of the
# screen, so every screen with buttons on it must free it while it is up (ViewModeService.menuOpen). The
# death card's choices ("Try again", the second chance) were missing, so a mouse could press neither.
VIEW_MODE = read("ViewModeService.lua")
for needle, why in (
    ('local death = playerGui:FindFirstChild("DeathCard")', "the death card does not free the cursor"),
    ('local choices = death and death:FindFirstChild("Choices", true)', "the death card does not free the cursor"),
    ("and death.Enabled and choices ~= nil and choices:IsA(\"GuiObject\")\n\t\t\tand choices.Visible)",
     "the death card does not free the cursor while its choices are up"),
    ('or (devPanel ~= nil and devPanel:IsA("GuiObject") and devPanel.Visible)', "the Studio test panel does not free "
     "the cursor"),
):
    if needle not in VIEW_MODE:
        fail(why + " (ViewModeService.menuOpen)")
if 'gui.Name = "DeathCard"' not in DEATH or 'row.Name = "Choices"' not in DEATH:
    fail("the death card or its row of choices is not named what ViewModeService looks for")

# AN ERROR ONCE, NOT EVERY FRAME: a step that runs every frame (or several times a second) says a given failure
# once, so a lasting error cannot bury the rest of Output (the paste check included).
for module, call in (
    ("EmoteService.lua", 'warnOnce("EmoteService: " .. tostring(err))'),
    ("OnboardingService.lua", 'warnOnce("OnboardingService: " .. tostring(err))'),
    ("StepService.lua", 'warnOnce("StepService: " .. tostring(err))'),
    ("ViewModeService.lua", 'warnOnce("ViewModeService: " .. tostring(err))'),
    ("DeformationRenderer.lua", 'warnOnce("DeformationRenderer: the lava\'s life failed: " .. tostring(err))'),
):
    text = read(module)
    if call not in text or "if not warnedOnce[text] then\n\t\twarnedOnce[text] = true" not in text:
        fail("%s says the same error every frame" % module)

# Selection let go of when a menu closes, so a controller is not left steering an invisible button.
for name, text in (("the pause menu", PAUSE), ("the journal", JOURNAL), ("the death card", DEATH), ("the shop", SHOP),
                   ("the emotes", EMOTES)):
    if "SelectedObject = nil" not in text:
        fail("%s keeps a controller's selection after it closes" % name)
# Y is Talk (Townsfolk's prompt) and X is every other prompt: nothing always-on may use them.
if "prompt.GamepadKeyCode = Enum.KeyCode.ButtonY" not in TOWNSFOLK:
    fail("Talk is not on a controller's Y any more; recheck what else uses Y")
for path in sorted((CLIENT).rglob("*.lua")):
    text = path.read_text(encoding="utf-8")
    for key in ("ButtonY", "ButtonX", "ButtonA"):
        for match in re.finditer(r"Enum\.KeyCode\.%s\b" % key, text):
            line = text[:match.start()].count("\n") + 1
            fail("%s:%d binds a controller's %s, which the prompts and jumping use" % (path.name, line, key[-1]))

# ===================================================================== a thumb
for path in sorted(CLIENT.rglob("*.lua")):
    text = path.read_text(encoding="utf-8")
    for made in re.finditer(r'local (\w+) = Instance\.new\("(?:TextButton|ImageButton)"\)', text):
        name = made.group(1)
        size = re.search(r"\b%s\.Size = UDim2\.(?:fromOffset\(([^,]+), ([^)]+)\)|new\(([^,]+), ([^,]+), ([^,]+), ([^)]+)\))"
                         % re.escape(name), text[made.end():])
        if not size or (path.name, name) in EXEMPT:
            continue
        if size.group(1) is not None:
            sides = [size.group(1).strip(), size.group(2).strip()]
        else:
            xs, xo, ys, yo = (v.strip() for v in size.group(3, 4, 5, 6))
            sides = [xo if xs == "0" else None, yo if ys == "0" else None]
        for side in sides:
            if side is None:
                continue
            if re.fullmatch(r"-?\d+", side) and 0 <= int(side) < 44:
                line = text[:made.start()].count("\n") + 1
                fail("%s:%d %s is %s pixels, under a thumb's 44" % (path.name, line, name, side))

# ===================================================================== a phone held upright
for path in sorted(CLIENT.rglob("*.lua")):
    text = path.read_text(encoding="utf-8")
    for match in re.finditer(r"(\w+)\.Size = UDim2\.(?:new\(0, (\d+), [\d.]+, -?\d+\)|fromOffset\((\d+), )", text):
        width = int(match.group(2) or match.group(3))
        if width > 360 and (path.name, match.group(1)) not in WIDE_EXEMPT:
            line = text[:match.start()].count("\n") + 1
            fail("%s:%d %s is %d pixels wide, wider than a phone held upright" % (path.name, line, match.group(1), width))
for needle, text, why in (
    ("cardMost.MaxSize = Vector2.new(380, 304)", PAUSE, "the pause menu is not capped and scaled to the screen"),
    ("rowMost.MaxSize = Vector2.new(600, 48)", DEATH, "the death card's choices are not capped and scaled"),
    ("most.MaxSize = Vector2.new(440, 116)", VOTE, "the vote card is not capped and scaled"),
    ("completionMost.MaxSize = Vector2.new(520, 172)", UI, "the LEVEL COMPLETE banner is not capped and scaled"),
):
    if needle not in text:
        fail(why)

# ===================================================================== a notch, a thumbstick, a jump button
for name, text in (("the pause menu", PAUSE), ("the journal", JOURNAL), ("the shop", SHOP)):
    if "ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets" not in text:
        fail("%s is not kept inside the device's safe area" % name)
if "screenGui.IgnoreGuiInset = true" in UI:
    fail("the run's screen ignores the safe area")
touch = UI[UI.find("-- ===================================================================== phones and tablets"):]
for needle, why in (
    ("if input.TouchEnabled and not input.KeyboardEnabled then", "the run's screen does not change for a touch screen"),
    ("leaderboard.Position = UDim2.new(0, SPACE.xl, 0, SPACE.xl)", "the best times stay over the thumbstick on a phone"),
    ("timerPanel.Position = UDim2.new(1, -SPACE.xl, 0, top", "the hardcore clock stays over the jump button on a phone"),
    ("modeButton.Position = UDim2.new(1, -SPACE.xl, 0, top)", "the mode stays over the jump button on a phone"),
):
    if needle not in touch:
        fail(why)
if "tabsRow.Size = UDim2.new(1, 0, 0, 44)" not in JOURNAL:
    fail("the journal's tabs are under a thumb's height")

# ===================================================================== fitted to every screen (the hundred-and-second pass)
# The panels drawn at a fixed size follow the screen (Style.fit: never larger than it, not tiny on a phone, larger on a
# big one), and the Self-test measures every screen on the device it runs on: off an edge, words not fitting, a
# button under a thumb.
STYLE = (ROOT / "src" / "Shared" / "Style.lua").read_text(encoding="utf-8")
DEV = read("DevPanelClient.lua")
for needle, why in (
    ("function Style.fit(panel: GuiObject, design: Vector2): UIScale", "Style has no way to fit a panel to the screen"),
    ("local fits = math.min(room.X / design.X, room.Y / design.Y)", "a fitted panel can be larger than the screen"),
    ('camera:GetPropertyChangedSignal("ViewportSize"):Connect(update)', "a fitted panel does not follow the screen turning"),
):
    if needle not in STYLE:
        fail(why)
for needle, text, why in (
    ("Style.fit(card, Vector2.new(380, 304))", PAUSE, "the pause menu is not fitted to the screen"),
    ("Style.fit(completion, Vector2.new(520, 172))", UI, "LEVEL COMPLETE is not fitted to the screen"),
    ("Style.fit(settingsFrame, Vector2.new(300, 320))", UI, "the run's settings are not fitted to the screen"),
    ("Style.fit(leaderboard, Vector2.new(218, 208))", UI, "the best times are not fitted to the screen"),
):
    if needle not in text:
        fail(why)
for label in ("the screen as it is", "the shop", "the journal", "the emote picker", "the pause menu", "the death card"):
    if 'onScreen("%s")' % label not in DEV:
        fail("the Self-test does not measure %s on this device" % label)
for needle, why in (
    ("not item.TextFits then", "the Self-test does not look for words that do not fit"),
    ("if at.X < -2 or at.Y < -2 or right > view.X + 2 or bottom > view.Y + 2 then", "the Self-test does not look for "
                                                                                   "things off an edge"),
    ("local stick = at.X < 280 and bottom > view.Y - 230", "the Self-test does not look for buttons under a thumb"),
):
    if needle not in DEV:
        fail(why)

if problems:
    for problem in problems:
        print("FAIL: " + problem)
    sys.exit(1)
print("devices: every menu opens, selects, closes and lets go on a controller, with nothing always-on on X, Y "
      "or A; every button a thumb's size (%d exempt, each for a reason); nothing wider than a phone; the "
      "menus inside the safe area and the run's corners clear of the thumbstick and jump." % len(EXEMPT))
