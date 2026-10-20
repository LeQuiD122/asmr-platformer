"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 32: the keepsake shelf in the squish room. A shelf too small, into the lift or the wall, off the floor
or through the ceiling; toys scaled about anywhere or left in the air, cards floating; nothing tagged for
each player's own collection; a toy that is no keepsake; no prompt; Interactables unable to make a toy; and a
client that shows everyone's shelf the same, never counts, never fills it, misses it streaming in, or opens
nothing.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
ROOM = S / "Server/Services/SquishRoomService.lua"
INTER = S / "Server/Services/Interactables.lua"
JOURNAL = S / "Client/Services/JournalService.lua"
SQUISH, PARSE = "check_squishroom.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (SQUISH, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    # The shelf's place and size.
    ("too few cubbies", ROOM, SQUISH, "local SHELF_COLUMNS, SHELF_ROWS = 9, 3", "local SHELF_COLUMNS, SHELF_ROWS = 8, 3"),
    ("into the lift", ROOM, SQUISH, "local SHELF_LEFT = 26", "local SHELF_LEFT = 14"),
    ("into the side wall", ROOM, SQUISH, "local SHELF_LEFT = 26", "local SHELF_LEFT = 52"),
    ("through the ceiling", ROOM, SQUISH, "local CUBBY = Vector3.new(3.2, 3, 2.2)", "local CUBBY = Vector3.new(3.2, 7, 2.2)"),
    ("off the wall", ROOM, SQUISH, "pcall(buildShelf, folder, cx - SHELF_LEFT, zA + 0.3, y)",
     "pcall(buildShelf, folder, cx - SHELF_LEFT, zA + 6, y)"),
    ("off the floor", ROOM, SQUISH, "CFrame.new(middleX, y + SHELF_PLINTH / 2, zMid)", "CFrame.new(middleX, y + SHELF_PLINTH, zMid)"),
    # The toys and cards.
    ("scaled about anywhere", ROOM, SQUISH, "\ttoy.WorldPivot = box\n", ""),
    ("a toy in the air", ROOM, SQUISH, "floorY + size.Y / 2 - box.Position.Y", "floorY + size.Y - box.Position.Y"),
    ("a card floating", ROOM, SQUISH, "CFrame.new(x, floorY + 0.7, wallZ + SHELF_BOARD + 0.14)",
     "CFrame.new(x, floorY + 1.7, wallZ + SHELF_BOARD + 0.14)"),
    ("toys for everyone", ROOM, SQUISH, 'CollectionService:AddTag(toy, "ShelfToy")', 'CollectionService:AddTag(toy, "Toy")'),
    ("cards for everyone", ROOM, SQUISH, 'CollectionService:AddTag(card, "ShelfEmpty")', 'CollectionService:AddTag(card, "Card")'),
    ("a board that never counts", ROOM, SQUISH, 'CollectionService:AddTag(sign, "ShelfCount")', 'CollectionService:AddTag(sign, "Sign")'),
    ("a toy that is no keepsake", ROOM, SQUISH, 'toy:SetAttribute("JournalId", id)', 'toy:SetAttribute("Keepsake", id)'),
    ("no prompt", ROOM, SQUISH, 'prompt.Name = "KeepsakeShelfPrompt"', 'prompt.Name = "ShelfPrompt"'),
    ("no toy on its own", INTER, SQUISH, "function Interactables.toy(", "function Interactables.makeToy("),
    ("the keepsake made another way", INTER, SQUISH, "local model, first = Interactables.toy(parent, cf, material)",
     "local model, first = nil, nil"),
    # The client.
    ("everyone's shelf the same", JOURNAL, SQUISH, 'if CollectionService:HasTag(item, "ShelfToy") then have else not have',
     "true"),
    ("never counted", JOURNAL, SQUISH, 'label.Text = ("KEEPSAKES  %d of %d"):format(counts.keepsake or 0, keepsakeTotal)',
     'label.Text = "KEEPSAKES"'),
    ("a keepsake not on the shelf", JOURNAL, SQUISH, 'if kind == "keepsake" then\n\t\trefreshShelf()', 'if false then\n\t\trefreshShelf()'),
    ("never filled from the save", JOURNAL, SQUISH, "refreshShelf()\n\t\t\treturn", "return"),
    ("missed as it streams in", JOURNAL, SQUISH, '\tCollectionService:GetInstanceAddedSignal("ShelfToy"):Connect(shelfItem)\n', ""),
    ("a prompt that opens nothing", JOURNAL, SQUISH, '\t\t\tJournalService.open("keepsake")\n', ""),
    # The code still reads.
    ("a name never declared", ROOM, PARSE, "local width = SHELF_COLUMNS * CUBBY.X + (SHELF_COLUMNS + 1) * SHELF_BOARD",
     "local width = SHELF_COLUMNS * CUBY.X + (SHELF_COLUMNS + 1) * SHELF_BOARD"),
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
