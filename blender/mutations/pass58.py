"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 58: an admin's /levels. Anyone an admin; the owner not one, or everyone on an unpublished place; a group's
owner never found or kept after leaving; anyone allowed to use it; not kept in the save; the lobby not told; the
save written to; an admin's real progress not recorded; no chat command, or one that takes anyone's word, or none
on the old chat; the admin not told.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
ECON = S / "Server/Services/EconomyService.lua"
BOOT = S / "Server/Bootstrap.server.lua"
BANNER = S / "Client/Services/HubVoteService.lua"
SHOP, PARSE = "check_shop.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (SHOP, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ("anyone an admin", ECON, SHOP, "if RunService:IsStudio() or ADMIN_IDS[player.UserId] == true then",
     "if true then"),
    ("everyone on an unpublished place", ECON, SHOP, "return game.CreatorId ~= 0 and player.UserId == game.CreatorId",
     "return player.UserId == game.CreatorId or game.CreatorId == 0"),
    ("a group's owner never found", ECON, SHOP, "groupOwner[player] = ok and rank == 255", "groupOwner[player] = false"),
    ("a group's owner kept", ECON, SHOP, "\tgroupOwner[player] = nil\n", ""),
    ("anyone may use it", ECON, SHOP,
     "if not (profile and profile:IsActive()) or not EconomyService.isAdmin(player) then\n\t\treturn",
     "if not (profile and profile:IsActive()) then\n\t\treturn"),
    ("not kept in the save", ECON, SHOP, "\tprofile.Data.AdminOpen = on\n", ""),
    ("the lobby not told", ECON, SHOP,
     "\t\tif on then \"open for them\" else \"back to their own progress\"))\n\ttellLevels()\n",
     "\t\tif on then \"open for them\" else \"back to their own progress\"))\n"),
    ("the save written to", ECON, SHOP,
     "\t\tlocal all: { [string]: boolean } = {}\n\t\tfor _, level in ipairs(LevelDefinitions.All) do\n\t\t\tall[tostring(level.levelId)] = true\n",
     "\t\tlocal all: { [string]: boolean } = finishedOf(profile.Data)\n\t\tfor _, level in ipairs(LevelDefinitions.All) do\n\t\t\tall[tostring(level.levelId)] = true\n"),
    ("no chat command", ECON, SHOP, 'command.PrimaryAlias = "/levels"', 'command.PrimaryAlias = "/lvls"'),
    ("anyone's word", ECON, SHOP, "local who = Players:GetPlayerByUserId(source.UserId)",
     "local who = Players:GetPlayers()[1]"),
    ("none on the old chat", ECON, SHOP, 'if string.lower(message) == "/levels" then', 'if message == "/never" then'),
    ("the admin not told (server)", BOOT, SHOP, 'HubVoteState:FireClient(player, "admin", { on = on })',
     'HubVoteState:FireClient(player, "admin")'),
    ("the admin not told (card)", BANNER, SHOP, '\t\telseif kind == "admin" then\n\t\t\tHubVoteService.onAdmin(payload)\n', ""),
    ("a name never declared", ECON, PARSE, "local on = profile.Data.AdminOpen ~= true", "local on = profle.Data.AdminOpen ~= true"),
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
