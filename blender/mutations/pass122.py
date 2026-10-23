"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 122, from your test: the shop made over. The tabs' strip no bigger than its tabs, or not widened round them;
no room on its left, along its top or under the lips; the last tab's edge; too little room for the chosen tab, the
chosen tab lifted too far, the tabs crowding; a tile cut at the grid's left or along its top; too little room round the
tiles; the last column squeezed; the tabs without drawings, on no lip, not sinking, puffing nothing; no tray; the tray
over the tiles, the tiles under it, the confirm card under them; a tile on no lip, not sinking, not washed or outlined
in its tab's colours; tiles never popping in; no gleam; the best value written into the catalogue, or unsaid; every
redraw popping in; the tabs never painted; how many are yours unsaid; every answer redrawing; tokens jumping; no pop
on opening; the gleams standing still, or turning after it shuts; the dark not fading; the deep shades greyed; a
tab's words unreadable; the puff under a crate, or with its own sound; a name never declared.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
CAT = S / "Shared/ShopCatalog.lua"
LOOK = S / "Client/Services/ShopLook.lua"
SHOPC = S / "Client/Services/ShopService.lua"
SHOP, PARSE = "check_shop.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (SHOP, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('the strip no bigger than its tabs', SHOPC, SHOP, 'ui.tabs.Size = UDim2.new(1, -(28 - 2 * TAB_ROOM), 0, tabsH + 2 * TAB_ROOM)', 'ui.tabs.Size = UDim2.new(1, -28, 0, tabsH + 6)'),
    ('the strip not widened round them', SHOPC, SHOP, 'ui.tabs.Position = UDim2.new(0, 14 - TAB_ROOM, 0, stripTop)', 'ui.tabs.Position = UDim2.new(0, 14, 0, stripTop)'),
    ('no room on its left', SHOPC, SHOP, 'tabRoom.PaddingLeft = UDim.new(0, TAB_ROOM)', 'tabRoom.PaddingLeft = UDim.new(0, 0)'),
    ('no room along its top', SHOPC, SHOP, 'tabRoom.PaddingTop = UDim.new(0, TAB_ROOM)', 'tabRoom.PaddingTop = UDim.new(0, 0)'),
    ('no room under the lips', SHOPC, SHOP, 'tabRoom.PaddingBottom = UDim.new(0, TAB_ROOM)', 'tabRoom.PaddingBottom = UDim.new(0, 0)'),
    ("the last tab's edge", SHOPC, SHOP, 'tail.Size = UDim2.fromOffset(TAB_ROOM, 1)', 'tail.Size = UDim2.fromOffset(0, 1)'),
    ('too little room for the chosen tab', SHOPC, SHOP, 'local TAB_ROOM, TAB_LIP = 10, 5', 'local TAB_ROOM, TAB_LIP = 4, 5'),
    ('the chosen tab lifted too far', SHOPC, SHOP, 'then 1.06 elseif part.hovered then 1.03 else 1', 'then 1.15 elseif part.hovered then 1.03 else 1'),
    ('the tabs crowding', SHOPC, SHOP, 'tabRow.Padding = UDim.new(0, 12)', 'tabRow.Padding = UDim.new(0, 6)'),
    ("a tile cut at the grid's left", SHOPC, SHOP, 'gridPad.PaddingLeft = UDim.new(0, TILE_ROOM)', 'gridPad.PaddingLeft = UDim.new(0, 2)'),
    ('a tile cut along its top', SHOPC, SHOP, 'gridPad.PaddingTop = UDim.new(0, TILE_ROOM + 3)', 'gridPad.PaddingTop = UDim.new(0, 4)'),
    ('too little room round the tiles', SHOPC, SHOP, 'local TILE_ROOM, TILE_LIP = 9, 6', 'local TILE_ROOM, TILE_LIP = 3, 6'),
    ('the last column squeezed', SHOPC, SHOP, 'local inner = (w - 36) - 16 - 2 * TILE_ROOM', 'local inner = (w - 36) - 16'),
    ('the tabs without drawings', SHOPC, SHOP, 'tabGlyph(disc, tab, fam.edge)', 'local _ = tabGlyph'),
    ('the tabs on no lip', SHOPC, SHOP, 'top.Size = UDim2.new(1, 0, 1, -TAB_LIP)', 'top.Size = UDim2.new(1, 0, 1, 0)'),
    ('a tab not sinking', SHOPC, SHOP, 'TweenService:Create(top, how, { Position = to }):Play()', 'local _ = how'),
    ('a tab puffing nothing', SHOPC, SHOP, 'ShopLook.puff(button, 0.5)', 'local _ = button'),
    ('no tray', SHOPC, SHOP, '\tui.tray = tray\n', '\tui.trays = tray\n'),
    ('the tray over the tiles', SHOPC, SHOP, 'tray.ZIndex = 2', 'tray.ZIndex = 5'),
    ('the tiles under it', SHOPC, SHOP, 'grid.ZIndex = 3', 'grid.ZIndex = 1'),
    ('the confirm card under them', SHOPC, SHOP, 'modal.ZIndex = 10', 'modal.ZIndex = 1'),
    ('a tile on no lip', SHOPC, SHOP, 'card.Size = UDim2.new(1, 0, 1, -TILE_LIP)', 'card.Size = UDim2.new(1, 0, 1, 0)'),
    ('a tile not sinking', SHOPC, SHOP, '{ Position = sunk }):Play()', '{ Position = rest }):Play()'),
    ("a tile not washed in its tab's colour", SHOPC, SHOP, 'light.Color = ColorSequence.new(LOOK.white, fam.pale)', 'light.Color = ColorSequence.new(LOOK.white, LOOK.tile)'),
    ('a tile outlined in the old teal', SHOPC, SHOP, 'local outline = stroke(card, fam.edge, 3)', 'local outline = stroke(card, LOOK.edge, 3)'),
    ('tiles never popping in', SHOPC, SHOP, 'if shop.fresh then\n\t\tlift.Scale = 0', 'if false then\n\t\tlift.Scale = 0'),
    ('no gleam', SHOPC, SHOP, 'table.insert(shop.gleams, run)', 'local _ = run'),
    ('the best value written into the catalogue', CAT, SHOP, 'blurb = "The whole till"', 'blurb = "The whole till, Best value"'),
    ('the best value unsaid', SHOPC, SHOP, 'elseif item.kind == "tokens" and item.id == bestPack() then "Best value"', 'elseif false then "Best value"'),
    ('every redraw popping in', SHOPC, SHOP, '\tui.firstTile = first\n\tshop.fresh = false\n', '\tui.firstTile = first\n'),
    ('the tabs never painted', SHOPC, SHOP, '\tpaintTabs()\n', '\tlocal _ = paintTabs\n'),
    ('how many are yours unsaid', SHOPC, SHOP, 'ui.progressWords.Text = ("%d of %d yours"):format(have, of)', 'ui.progressWords.Text = ""'),
    ('every answer redrawing', SHOPC, SHOP, 'if shop.open and drawnFrom(data) ~= shop.drawn then', 'if shop.open then'),
    ('tokens jumping', SHOPC, SHOP, 'showTokens(data.tokens)', 'ui.tokenWords.Text = tostring(data.tokens)'),
    ('no pop on opening', SHOPC, SHOP, '\tshop.fresh = true\n', '\n'),
    ('the gleams standing still', SHOPC, SHOP, 'run.Rotation = turn', 'run.Rotation = 0'),
    ('the gleams turning after it shuts', SHOPC, SHOP, '\t\tui.spin:Disconnect()\n\t\tui.spin = nil\n', '\t\tui.spin = nil\n'),
    ('the dark not fading', SHOPC, SHOP, 'TweenService:Create(ui.dim, TweenInfo.new(0.22, Enum.EasingStyle.Quad), { BackgroundTransparency = 1 }):Play()', 'local _ = ui.dim'),
    ('the deep shades greyed', SHOPC, SHOP, 'edge = Color3.fromHSV(h, math.min(1, s * 1.25 + 0.15), v * 0.42)', 'edge = own:Lerp(Color3.new(0.2, 0.2, 0.2), 0.6)'),
    ("a tab's words unreadable", LOOK, SHOP, 'Steps = rgb(176, 222, 160)', 'Steps = rgb(60, 70, 50)'),
    ('the puff under a crate', LOOK, SHOP, 'if not look.open or look.crating then\n\t\treturn\n\tend\n\tif look.theme.effect == "flicker"', 'if not look.open then\n\t\treturn\n\tend\n\tif look.theme.effect == "flicker"'),
    ('the puff with its own sound', LOOK, SHOP, '\tburst(look.theme.effect, centre, strength)\nend', '\tburst(look.theme.effect, centre, strength)\n\tplaySound(look.theme.sound, 0.4)\nend'),
    ('a name never declared', SHOPC, PARSE, 'local discD = math.floor((tabsH - TAB_LIP) * 0.62)', 'local discD = math.floor((tabsH - TAB_LIPS) * 0.62)'),
]

paths = {m[1] for m in MUTATIONS}
originals = {path: path.read_bytes() for path in paths}
missed = []
try:
    for label, path, checker, old, new in MUTATIONS:
        text = originals[path].decode("utf-8").replace("\r\n", "\n")
        assert text.count(old) == 1, "%s: anchor found %d times" % (label, text.count(old))
        path.write_bytes(text.replace(old, new).encode("utf-8"))
        result = run(checker)
        path.write_bytes(originals[path])
        caught = result.returncode != 0
        why = [line.strip() for line in (result.stdout + result.stderr).splitlines()
               if line.startswith("  ") or line.startswith("FAIL")][:2]
        print("%-8s %s  %s" % ("caught" if caught else "MISSED", label, "; ".join(why)[:170]))
        if not caught:
            missed.append(label)
finally:
    for path, data in originals.items():
        path.write_bytes(data)
print("\n%d of %d caught" % (len(MUTATIONS) - len(missed), len(MUTATIONS)))
sys.exit(1 if missed else 0)
