"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 81: City Shore's dive hit like an action game, and the bar seen at work in a secret's scene. An impact frame in
colour, without its punch or its lines, a full white flash; speed lines never drawn; the punch never seen; the
impact's colour left on; a thought not written out; a pose missing; the dive not pushing off or not buffeted; the
leap, the gulls or the water not hit; no speed lines down the drop; no air trails or left on after; no wind
streaks; the diver not buffeted; a secret with nothing to think or a dash in a thought; the bar never seen at work,
the thing opening before it is touched, a thing not saying what is in it, what you make of it never sent; the two
sides disagreeing on the prying's length; the bar's scene never played, no prying, no jump back, no hit, no
pondering, no thought, no peering, the bar and your pose not given back.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
CINEMA = S / "Client/Services/Cinema.lua"
POSES = S / "Shared/Poses.lua"
SHORE = S / "Client/Services/CityShoreClient.lua"
INTER = S / "Server/Services/Interactables.lua"
STORYC = S / "Client/Services/StoryClient.lua"
STORY, PARSE = "check_story.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (STORY, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ("an impact frame in colour", CINEMA, STORY, "\teffect.Saturation = -1\n", ""),
    ("no punch in", CINEMA, STORY, "current.kick = math.max(current.kick, 9 * s)", "current.kick = current.kick"),
    ("no lines in an impact", CINEMA, STORY, "current.burst = math.max(current.burst, math.min(1, 0.9 * s))", "current.burst = current.burst"),
    ("a full white flash", CINEMA, STORY, "current.flash.BackgroundTransparency = 0.55", "current.flash.BackgroundTransparency = 0"),
    ("speed lines never drawn", CINEMA, STORY, "\tdrawLines(current, dt)\n", ""),
    ("the punch never seen", CINEMA, STORY, "camera.FieldOfView = math.max(8, fov - kick)", "camera.FieldOfView = fov"),
    ("the impact's colour left on", CINEMA, STORY, "\tif current.impactFx then\n\t\tcurrent.impactFx:Destroy()\n\tend\n", ""),
    ("a thought all at once", CINEMA, STORY, "TweenService:Create(words, TweenInfo.new(length / 30, Enum.EasingStyle.Linear), { MaxVisibleGraphemes = length }):Play()",
     "words.MaxVisibleGraphemes = -1"),
    ("no pondering pose", POSES, STORY, "function Poses.ponder(name: string, t: number, w: number, r6: boolean): CFrame?",
     "function Poses.think(name: string, t: number, w: number, r6: boolean): CFrame?"),
    ("the dive not pushing off", POSES, STORY, "local push = 1 - math.clamp(t / 0.32, 0, 1)", "local push = 0"),
    ("the dive a statue in the wind", POSES, STORY, "local buffet = close * math.clamp((t - 1.8) / 0.6, 0, 1)", "local buffet = 0"),
    ("the leap not hit", SHORE, STORY, "\t\t\t\tCinema.impact(1)\n", ""),
    ("the gulls not hit", SHORE, STORY, "\t\t\t\tCinema.impact(0.8)\n", ""),
    ("the water not hit", SHORE, STORY, "\t\tCinema.impact(1.4)\n", ""),
    ("no speed lines down the drop", SHORE, STORY, "Cinema.speedLines(0.75)", "Cinema.speedLines(0)"),
    ("no air trails", SHORE, STORY, 'trail.Name = "DiveAirTrail"', 'trail.Name = "DiveTrail"'),
    ("air trails left on", SHORE, STORY, "\t\t\tfor _, made in ipairs({ a0, a1, trail }) do\n\t\t\t\ttable.insert(current.held, made)",
     "\t\t\tfor _, made in ipairs({}) do\n\t\t\t\ttable.insert(current.held, made)"),
    ("no wind streaks", SHORE, STORY, "streaks.Rate = if not splash and t > 1.5 then 90 else 0", "streaks.Rate = 0"),
    ("the diver not buffeted", SHORE, STORY, "CFrame.Angles(-math.pi * 0.95 * over, yaw, roll)", "CFrame.Angles(-math.pi * 0.95 * over, 0, 0)"),
    ("a secret with nothing to think", INTER, STORY,
     '\t\tthink = { "Rusted shut. Something rattles inside.", "A photograph... who would keep this down here?" }, note = {',
     '\t\tnote = {'),
    ("a dash in a thought", INTER, STORY, '"Locker 3. Why do I know that number?"', '"Locker 3 -- why do I know that number?"'),
    ("the bar never seen at work", INTER, STORY, 'remote:FireClient(player, "pry", { at = host.Position, object = object,',
     'remote:FireClient(player, "whisper", { at = host.Position, object = object,'),
    ("opening before it is touched", INTER, STORY, "\t\t\t\twait = PRY_SECONDS\n", ""),
    ("a thing not saying what is in it", INTER, STORY, "\t\tsecret = opts.secret,\n", ""),
    ("what you make of it never sent", INTER, STORY, "think = if secret.think then secret.think[2] else nil", "think = nil"),
    ("the two sides disagreeing", STORYC, STORY, "local PRY_SECONDS = 1.75", "local PRY_SECONDS = 1"),
    ("the bar's scene never played", STORYC, STORY, '\t\t\telseif kind == "pry" and typeof(data) == "table" then\n\t\t\t\tpry(data)\n', ""),
    ("no prying", STORYC, STORY, '\tact("pry")\n', ""),
    ("no jump back", STORYC, STORY, '\t\t\tact("startle")\n\t\t\tbarInHands(false)\n', "\t\t\tbarInHands(false)\n"),
    ("it giving not hit", STORYC, STORY, "\t\t\tCinema.impact(0.9)\n", ""),
    ("no pondering", STORYC, STORY, '\tif not again and not (acting.now and acting.now.pose == "ponder") then\n\t\tact("ponder")\n\tend\n', ""),
    ("no thought", STORYC, STORY, "Cinema.think(character, data.think, 3.4)", "Cinema.caption(data.think, nil, 3.4)"),
    ("no peering", STORYC, STORY, '\tact("peer")\n', ""),
    ("the bar not given back", STORYC, STORY, "\tact(nil)\n\tbarInHands(false)\n", "\tact(nil)\n"),
    ("a name never declared", STORYC, PARSE, "\t\tlocal from = poseOf(acting.before, name, r6, now)\n", "\t\tlocal from = poseOf(acting.befor, name, r6, nows)\n"),
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
