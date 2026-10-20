"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 89: the people's voices. The takes out of the order of the gestures; the voices never found; a gesture
said with another's voice; a voice played for a line already being said; a voice running on into the next; nobody's
voice their own, or someone without one; a name never declared.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
STORYC = S / "Client/Services/StoryClient.lua"
TOWNS = S / "Server/Services/Townsfolk.lua"
VOICEGEN = ROOT / "audio/gen_voice_sfx.py"
STORY, PARSE = "check_story.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (STORY, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('the takes out of order', VOICEGEN, STORY, 'ORDER = ("greet", "explain", "point",', 'ORDER = ("greet", "point", "explain",'),
    ('the voices never found', STORYC, STORY, 'folder:FindFirstChild("TownsfolkVoice_x9")', 'folder:FindFirstChild("TownsfolkVoice")'),
    ("another's voice", STORYC, STORY, 'local from = (index - 1) * VOICE_SLOT', 'local from = index * VOICE_SLOT'),
    ('a voice for a line already said', STORYC, STORY, 'workspace:GetServerTimeNow() - at < 0.5 then\n\t\t\t\tspeak(model, gesture)', 'workspace:GetServerTimeNow() - at < 50 then\n\t\t\t\tspeak(model, gesture)'),
    ('a voice running on', STORYC, STORY, 'PlaybackRegion = NumberRange.new(from, from + VOICE_SLOT - 0.05)', 'PlaybackRegion = NumberRange.new(from, from + 18)'),
    ("nobody's voice their own", TOWNS, STORY, 'model:SetAttribute("Voice", VOICES[name] or 1)', 'model:SetAttribute("Voice", 1)'),
    ('someone without a voice', TOWNS, STORY, 'Barlow = 0.8, Watcher = 0.7,', 'Watcher = 0.7,'),
    ('a name never declared', STORYC, PARSE, 'local from = (index - 1) * VOICE_SLOT', 'local from = (indexes - 1) * VOICE_SLOT'),
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
