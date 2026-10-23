"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 108: the slide's arches. Not tagged, not saying where their middle is, their hoops outside their model;
never found or lit for a ride, never glowing up ahead; passing under one doing nothing, not sparkling, silent, not
shaking; their lights left on when a ride is cut short or done; a light casting shadows, or too bright; the sound not
checked for; a name never declared.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
BOOT = S / "Server/Bootstrap.server.lua"
SKY = S / "Client/Services/SkyPoolsClient.lua"
SKYS = S / "Server/Services/SkyPoolsService.lua"
HUB, SKYCHECK, PARSE = "check_hub.py", "check_skypools.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (HUB, SKYCHECK, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('not tagged', SKYS, SKYCHECK, 'CollectionService:AddTag(arch, "SlideArch")', 'arch:SetAttribute("Tag", "SlideArch")'),
    ('not saying where its middle is', SKYS, SKYCHECK, 'arch:SetAttribute("Centre", (frame * CFrame.new(0, 2.4, 0)).Position)', 'arch:SetAttribute("Centre", frame.Position)'),
    ('hoops outside their model', SKYS, SKYCHECK, 'block(arch, "SlideHoop"', 'block(folder, "SlideHoop"'),
    ('never found', SKY, SKYCHECK, 'for _, model in ipairs(CollectionService:GetTagged("SlideArch")) do', 'for _, model in ipairs(CollectionService:GetTagged("SlideArches")) do'),
    ('never lit for a ride', SKY, SKYCHECK, '\tpcall(archesOn)\n', '\tlocal _ = archesOn\n'),
    ('never glowing up ahead', SKY, SKYCHECK, '\tmoveArches(current.seat.Position)\n', '\tlocal _ = moveArches\n'),
    ('passing under doing nothing', SKY, SKYCHECK, 'if d < ARCH_PASS then\n\t\t\t\tarchPassed(a)', 'if d < 0 then\n\t\t\t\tarchPassed(a)'),
    ('not sparkling', SKY, SKYCHECK, 'emitter:Emit(4)', 'emitter:Emit(0)'),
    ('silent', SKY, SKYCHECK, 'Cinema.sound("ArchPass", 0.45, { pitch = 0.97 + math.random() * 0.06, keep = true })', 'local _ = 0.45'),
    ('not shaking', SKY, SKYCHECK, 'Cinema.shake(0.2)', 'local _ = 0.2'),
    ('lights on when cut short', SKY, SKYCHECK, '\t\tride = nil\n\t\tarchesOff()\n', '\t\tride = nil\n'),
    ('lights on when done', SKY, SKYCHECK, '\t\tsplashFlash()\n\t\tarchesFade()\n', '\t\tsplashFlash()\n'),
    ('a light casting shadows', SKY, SKYCHECK, '\t\t\t\tlight.Name = "ArchGlow"\n\t\t\t\tlight.Brightness = 0\n\t\t\t\tlight.Range = 12\n\t\t\t\tlight.Color = colours[1]:Lerp(Color3.new(1, 1, 1), 0.45)\n\t\t\t\tlight.Shadows = false', '\t\t\t\tlight.Name = "ArchGlow"\n\t\t\t\tlight.Brightness = 0\n\t\t\t\tlight.Range = 12\n\t\t\t\tlight.Color = colours[1]:Lerp(Color3.new(1, 1, 1), 0.45)\n\t\t\t\tlight.Shadows = true'),
    ('too bright', SKY, SKYCHECK, 'local ARCH_FLARE = 1.6 ', 'local ARCH_FLARE = 3 '),
    ('the sound not checked for', BOOT, HUB, '"ScreamerStab", "ArchPass", "KeyLift",', '"ScreamerStab", "KeyLift",'),
    ('a name never declared', SKY, PARSE, 'local d = (a.centre - at).Magnitude', 'local d = (a.centre - att).Magnitude'),
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
