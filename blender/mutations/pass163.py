"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 163: where a run is left. A step logged twice; the steps before skipped; a checkpoint logging the finish;
one session for every run; finishing never logged; a run left kept on; a checkpoint saying nothing; the level read as the
run goes; the log unguarded.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
BOOT = S / "Server/Bootstrap.server.lua"
STANDARDS = "check_standards.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (STANDARDS,):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('a step logged twice', BOOT, STANDARDS, 'if not funnel or step <= funnel.step then', 'if not funnel then'),
    ('the steps before skipped', BOOT, STANDARDS, 'for at = funnel.step + 1, math.min(step, #RUN_STEPS) do', 'for at = step, math.min(step, #RUN_STEPS) do'),
    ('a checkpoint logging the finish', BOOT, STANDARDS, 'funnelTo(player, math.min(#RUN_STEPS - 1, 1 + math.floor(4 * index / total)))', 'funnelTo(player, 1 + math.floor(4 * index / total))'),
    ('one session for every run', BOOT, STANDARDS, 'session = game:GetService("HttpService"):GenerateGUID(false)', 'session = "run"'),
    ('finishing never logged', BOOT, STANDARDS, '\t\tfunnelTo(player, #RUN_STEPS)\n\t\tfunnelFor[player] = nil', '\t\tfunnelFor[player] = nil'),
    ('a run left kept on', BOOT, STANDARDS, '\telse\n\t\tfunnelFor[player] = nil\n\tend\nend', '\telse\n\t\tlocal _ = funnelFor[player]\n\tend\nend'),
    ('a checkpoint saying nothing', BOOT, STANDARDS, '\t\t\t\t\trunReached(player, entry.index, chunkCount)\n', ''),
    ('the level read as the run goes', BOOT, STANDARDS, '\tlocal chunkCount = #levelInstance.placedChunks\n', '\tlocal chunkCount = 0\n'),
    ('the log unguarded', BOOT, STANDARDS, '\t\tpcall(function()\n\t\t\tAnalyticsService:LogFunnelStepEvent(player, funnel.name, funnel.session, at, RUN_STEPS[at])\n\t\tend)', '\t\tAnalyticsService:LogFunnelStepEvent(player, funnel.name, funnel.session, at, RUN_STEPS[at])'),
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
