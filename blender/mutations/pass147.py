"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 147: the words. A secret's card saying Press J to everyone, or its controller's words gone; the
journal's foot not said as it opens, or J said to a controller; Ctrl told to a phone; the emotes' way on a phone left
out; a mouse told to tap; the pads' bars back; City Shore described as it was; a new key named to everyone.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
HUBS = S / "Server/Services/HubService.lua"
JOURNAL = S / "Client/Services/JournalService.lua"
LEVELS = S / "Shared/LevelDefinitions.lua"
PAUSE = S / "Client/Services/PauseMenuService.lua"
SHOPC = S / "Client/Services/ShopService.lua"
STORYC = S / "Client/Services/StoryClient.lua"
VIEWC = S / "Client/Services/ViewModeService.lua"
POLISH = "check_polish.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (POLISH,):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ("a secret's card says Press J to all", STORYC, POLISH, '{ readHint(), 14,', '{ "Kept in your journal. Press J to read it.", 14,'),
    ("the secret's card's controller words gone", STORYC, POLISH, 'return "Kept in your journal. Press D-pad up to read it."', 'return "Kept in your journal. Press J to read it."'),
    ("the journal's foot not said as it opens", JOURNAL, POLISH, '\t\tif ui.foot then\n\t\t\tui.foot.Text = closeWords()\n\t\tend\n', ''),
    ("the journal's foot says J to a controller", JOURNAL, POLISH, 'return "B to close"', 'return "J or Esc to close"'),
    ('Ctrl told to a phone', VIEWC, POLISH, '(if keys then "First person. Ctrl frees the cursor." else "First person.")', '"First person. Ctrl frees the cursor."'),
    ("the emotes' way on a phone left out", SHOPC, POLISH, '(G, right on the D-pad, or Emotes in the menu)', '(G, or right on the D-pad)'),
    ('a mouse told to tap', SHOPC, POLISH, 'Only you see it. Press it to try it.', 'Only you see it. Tap it to try it.'),
    ("the pads' bars back", HUBS, POLISH, '("%spar %d:%02d  ·  %s"):format(', '("%spar %d:%02d  |  %s"):format('),
    ('City Shore as it was', LEVELS, POLISH, '"The spiral over the city, the beach and the waterpark, and the high dive at its end."', '"The spiral over the city. The only backdrop that exists so far."'),
    ('a new key named to everyone', PAUSE, POLISH, 'heading.Text = "This run"\n\theading.Parent = card', 'heading.Text = "Press J for your journal"\n\theading.Parent = card'),
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
