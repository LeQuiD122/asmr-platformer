"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 96: the sounds remade and the lobby's own. The lobby's sound deaf to the levels, or silent at joining; a
take of a sheet running into the next, the same take twice running, or a take never stopped; a slot the wrong length,
the takes miscounted, or a sheet that is not there; the generator's slots not the client's; sounds imported while
playing not picked up; the server's stand-ins (the sea, the wind, the breakers, the fountain) playing over the lobby's
own; the paste check calling the lobby's sounds required, not looking for the sheets, or for the journal's sound; the
growl not made where the halls look for it; a name never declared.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
AMB = S / "Client/Services/AmbienceService.lua"
BOOT = S / "Server/Bootstrap.server.lua"
HUBS = S / "Server/Services/HubService.lua"
LOBBYGEN = ROOT / "audio/gen_lobby_sfx.py"
STORYGEN = ROOT / "audio/gen_story_sfx.py"
AUDIOCHECK, HALLS, HUB, PARSE = "check_audio.py", "check_halls.py", "check_hub.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (AUDIOCHECK, HALLS, HUB, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('the lobby deaf to the levels', AMB, AUDIOCHECK, '\t\tlobbyOn(wanted == nil)\n', '\n'),
    ('silent at joining', AMB, AUDIOCHECK, '\tif level == nil then\n\t\tlobbyOn(true)\n\tend', '\tif false then\n\t\tlobbyOn(true)\n\tend'),
    ('a take running into the next', AMB, AUDIOCHECK, '(take :: any).PlaybackRegion = NumberRange.new(from, from + family.slot - 0.05)', '(take :: any).PlaybackRegion = NumberRange.new(from, from + 60)'),
    ('the same take twice running', AMB, AUDIOCHECK, 'while #recent > math.min(2, family.takes - 1) do', 'while #recent > 0 do'),
    ('a take never stopped', AMB, AUDIOCHECK, 'lobbyAt(take, at, lobbyRange(family.volume), pitch, near, far, family.slot / pitch)', 'lobbyAt(take, at, lobbyRange(family.volume), pitch, near, far, 60)'),
    ('a slot the wrong length', AMB, AUDIOCHECK, 'surf = { sheet = "Surf_x8", slot = 9,', 'surf = { sheet = "Surf_x8", slot = 10,'),
    ('the takes miscounted', AMB, AUDIOCHECK, 'slot = 1.5, takes = 10,', 'slot = 1.5, takes = 12,'),
    ('a sheet that is not there', AMB, AUDIOCHECK, 'gust = { sheet = "WindGust_x5",', 'gust = { sheet = "WindGusts_x5",'),
    ("the generator's slots differ", LOBBYGEN, AUDIOCHECK, 'SLOTS = {"Surf": 9.0,', 'SLOTS = {"Surf": 8.0,'),
    ('imports not picked up', AMB, AUDIOCHECK, 'if child.Name == "LobbySounds" and level == nil then', 'if child.Name == "LobbySound" and level == nil then'),
    ("the stand-ins over the lobby's own", HUBS, AUDIOCHECK, '\tif not ownSound then\n', '\tif true then\n'),
    ('the stand-in fountain too', HUBS, AUDIOCHECK, 'if water and water:IsA("BasePart") and not ownSound then', 'if water and water:IsA("BasePart") then'),
    ("the lobby's sounds required", BOOT, HUB, 'sound("LobbySounds", name, true)', 'sound("LobbySounds", name)'),
    ('the sheets not looked for', BOOT, HUB, 'for _, name in ipairs(SHEET_SOUNDS) do\n\t\tsound("MaterialSounds", name)', 'for _, name in ipairs({}) do\n\t\tsound("MaterialSounds", name)'),
    ("the journal's sound not looked for", BOOT, HUB, '"CountdownTock_x3", "JournalAdd", "DoorSlam"', '"CountdownTock_x3", "DoorSlam"'),
    ('the growl not made', STORYGEN, HALLS, '("MawGrowl", maw_growl)', '("MawGrowlx", maw_growl)'),
    ('a name never declared', AMB, PARSE, 'local take = lobbyTake(name, family)', 'local take = lobbyTakes(name, family)'),
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
