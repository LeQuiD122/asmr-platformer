"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 85: the people tell it with their bodies. A gesture named and never made; too few gestures; a person's
lines and gestures out of step, or no greeting, or the same gesture twice running, or one gesture for too
many lines, or one Poses does not make; a line said without a gesture, or never started; a habit fighting it,
or an arm left mid-habit; the people never tagged; a held thing not keeping its hand out of it; the fisherman
letting go of his rod; the director's choices ignored; the old wave back; the gestures never played, started,
stepped or let go of, or played however far away; a busy hand gesturing; nobody nodding; a name never declared.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
TOWNS = S / "Server/Services/Townsfolk.lua"
STORYC = S / "Client/Services/StoryClient.lua"
POSES = S / "Shared/Poses.lua"
STORY, PARSE = "check_story.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (STORY, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ("a gesture never made", POSES, STORY, '\telseif gesture == "remember" then\n', '\telseif gesture == "recall" then\n'),
    ("too few gestures", POSES, STORY, 'Poses.GESTURES = { "greet", "explain", "point", "shrug", "worry", "remember", "warn", "lean", "sad" }',
     'Poses.GESTURES = { "greet", "explain", "point" }'),
    ("lines and gestures out of step", TOWNS, STORY, '\tRudy = { "greet", "shrug", "point", "lean", "explain" },',
     '\tRudy = { "greet", "shrug", "point", "lean" },'),
    ("no greeting", TOWNS, STORY, '\tDev = { "greet", "remember",', '\tDev = { "explain", "remember",'),
    ("the same twice running", TOWNS, STORY, '\tTobi = { "greet", "worry", "sad", "point", "explain" },',
     '\tTobi = { "greet", "worry", "worry", "point", "explain" },'),
    ("a gesture Poses does not make", TOWNS, STORY, '\tPip = { "greet", "explain", "worry", "explain", "lean", "sad" },',
     '\tPip = { "greet", "explain", "worry", "explain", "lean", "cry" },'),
    ("one gesture for too many lines", TOWNS, STORY,
     '\tFisherman = { "greet", "remember", "sad", "worry", "lean", "worry", "remember", "warn" },\n'
     '\tVenn = { "greet", "point", "shrug", "lean", "explain", "warn", "remember", "shrug" },\n'
     '\tTobi = { "greet", "worry", "sad", "point", "explain" },\n'
     '\tBarlow = { "greet", "explain", "point", "lean", "sad", "warn", "explain" },',
     '\tFisherman = { "greet", "point", "sad", "point", "lean", "point", "remember", "point" },\n'
     '\tVenn = { "greet", "point", "shrug", "point", "explain", "point", "remember", "point" },\n'
     '\tTobi = { "greet", "point", "sad", "point", "explain" },\n'
     '\tBarlow = { "greet", "point", "sad", "point", "explain", "point", "explain" },'),
    ("a line said without a gesture", TOWNS, STORY, '\t\tnpc.model:SetAttribute("Gesture", gestureFor(npc, text))\n', ""),
    ("a gesture never started", TOWNS, STORY, '\t\tnpc.model:SetAttribute("GestureAt", workspace:GetServerTimeNow())\n', ""),
    ("a habit fighting the gesture", TOWNS, STORY, "\t\tnpc.talking = os.clock() + seconds\n", ""),
    ("an arm left mid-habit", TOWNS, STORY, "\t\tfor _, jointName in ipairs(ARMS) do\n", "\t\tfor _, jointName in ipairs({}) do\n"),
    ("the people never tagged", TOWNS, STORY, '\tCollectionService:AddTag(model, "Townsperson")\n', ""),
    ("a held thing ignored", TOWNS, STORY, '\tif to == "RightHand" or to == "LeftHand" then\n', '\tif to == "Pocket" then\n'),
    ("the rod let go of", TOWNS, STORY, 'holds = "both", title = "Mr Wick"', 'title = "Mr Wick"'),
    ("the director ignored", TOWNS, STORY, "\tlocal told = TOLD[npc.name]\n", "\tlocal told = nil\n"),
    ("the old wave back", TOWNS, STORY, "\tnpc.talking = os.clock() + 2.6\n",
     '\tnpc.talking = os.clock() + 2.6\n\tturn(npc, "RightShoulder", CFrame.Angles(0.6, 0, 0.12), 0.45)\n'),
    ("never played", STORYC, STORY, "local by = Poses.tell(gesture :: string, name, t, w,", "local by = Poses.flail(gesture :: string, name, t, w,"),
    ("never started", STORYC, STORY, "\tstartTellers()\n", ""),
    ("never stepped", STORYC, STORY, "\t\tpcall(stepTellers)\n", ""),
    ("never let go of", STORYC, STORY, "\t\t\t\tPoses.drive(joint, CFrame.identity)\n", ""),
    ("played however far away", STORYC, STORY, "(root.Position - camera.CFrame.Position).Magnitude < TELL_SEEN", "true"),
    ("a busy hand gesturing", POSES, STORY, 'local mainSide = if hands == "left" then "Left" elseif hands == "none" then nil else "Right"',
     'local mainSide = "Right"'),
    ("the second hand letting go", POSES, STORY, 'local otherSide = if hands == "both" then "Left" else nil', 'local otherSide = "Left"'),
    ("nobody nodding", POSES, STORY, "local nod = 0.06 * math.sin(t * 6.3) * math.sin(t * 1.7 + 0.4)", "local nod = 0"),
    ("a name never declared", STORYC, PARSE, "\t\tlocal t = now - teller.clock\n", "\t\tlocal t = nows - teller.clock\n"),
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
