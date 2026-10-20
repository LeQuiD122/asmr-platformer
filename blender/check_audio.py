"""Every sound file the game ships, checked by ear's proxies without Studio (the ninety-sixth pass).

    python blender/check_audio.py
    python blender/check_audio.py --selftest     only the self-test (bad sounds made on purpose, each must fail)

What it holds, for every WAV in audio/ (buttons, materials, sheets, story, endings, ambience, lobby, water):
  * THE FORMAT ROBLOX PLAYS IN 3D: mono, 44.1 kHz, 16 bit.
  * NO CLIPPING, NO DC: no peak over -0.9 dBFS, no offset that thumps when the sound starts and stops.
  * CLEAN ENDS: a one-shot starts from silence and dies to it (no click as it starts or is cut off), but for the
    few made to hit on their first sample (the bubble wrap's pop).
  * SEAMLESS LOOPS: a bed's last sample runs on into its first with no step bigger than its own steps either side,
    and it is as loud at its end as at its start (no swell at the join).
  * LEVEL: each family within its loudness band (BS.1770), so a sound neither vanishes nor jumps out of the mix.
  * SOFT (the sound taste: soft, low, ASMR): each family under its spectral-centroid ceiling.
  * NO BARE TONES: a long sound that is not music is not a few steady sine waves (the old drone, the old zaps).
  * TAKES THAT DIFFER: no two takes of one sound (numbered files, or slots of a sheet) are the same sound.
  * SHEETS: every slot of a `_xN` sheet holds a take, and each take is over before the next slot starts.
  * NAMED AS THE GAME ASKS: every sound name the Luau asks a folder for (StorySounds, AmbienceSounds, LobbySounds,
    WaterSounds) is a file in the folder it comes from, so a typo on either side is caught here, not in play.
"""
import pathlib
import re
import sys

import numpy as np
from scipy import signal
from scipy.io import wavfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
AUDIO = ROOT / "audio"
SRC = ROOT / "src"
SR = 44100
problems = []


def fail(message):
    problems.append(message)


# ------------------------------------------------------------------------------------------------ measures
def k_weighted(x):
    def biquad(kind, fc, q, gain_db):
        a_lin = 10 ** (gain_db / 40)
        w0 = 2 * np.pi * fc / SR
        alpha = np.sin(w0) / (2 * q)
        c = np.cos(w0)
        if kind == "highshelf":
            s = 2 * np.sqrt(a_lin) * alpha
            b = [a_lin * ((a_lin + 1) + (a_lin - 1) * c + s), -2 * a_lin * ((a_lin - 1) + (a_lin + 1) * c),
                 a_lin * ((a_lin + 1) + (a_lin - 1) * c - s)]
            a = [(a_lin + 1) - (a_lin - 1) * c + s, 2 * ((a_lin - 1) - (a_lin + 1) * c), (a_lin + 1) - (a_lin - 1) * c - s]
        else:
            b = [(1 + c) / 2, -(1 + c), (1 + c) / 2]
            a = [1 + alpha, -2 * c, 1 - alpha]
        return np.array(b) / a[0], np.array(a) / a[0]
    b1, a1 = biquad("highshelf", 1500.0, 1 / np.sqrt(2), 4.0)
    b2, a2 = biquad("highpass", 38.0, 0.5, 0.0)
    return signal.lfilter(b2, a2, signal.lfilter(b1, a1, x))


def lufs(x):
    if not len(x) or not np.any(x):
        return -120.0
    y = k_weighted(x)
    block, hop = int(0.4 * SR), int(0.1 * SR)
    if len(y) < block:
        active = np.abs(x) > np.max(np.abs(x)) * 0.01
        return -0.691 + 10 * np.log10(np.mean(y[active] ** 2) + 1e-15)
    powers = np.array([np.mean(y[i:i + block] ** 2) for i in range(0, len(y) - block + 1, hop)])
    loud = -0.691 + 10 * np.log10(powers + 1e-15)
    gated = powers[loud > -70]
    if not len(gated):
        return -120.0
    rel = -0.691 + 10 * np.log10(np.mean(gated)) - 10
    return -0.691 + 10 * np.log10(np.mean(powers[(loud > -70) & (loud > rel)]) + 1e-15)


def centroid(x):
    f, p = signal.welch(x, SR, nperseg=min(len(x), 4096))
    return float((f * p).sum() / (p.sum() + 1e-15))


def tonality(x):
    """The share of energy in the 8 strongest 2-Hz bins of the long-term spectrum (60 Hz to 6 kHz): a held sine is
    near 1; water, wind and voices are near 0; a struck or bowed thing in between."""
    f, p = signal.welch(x[:SR * 8], SR, nperseg=min(len(x), 22050))
    p = p[(f > 60) & (f < 6000)]
    return float(np.sort(p)[-8:].sum() / (p.sum() + 1e-15)) if p.sum() > 0 else 0.0


def seam(x):
    near = np.abs(np.diff(np.concatenate([x[-2000:], x[:2000]])))
    near = np.delete(near, 1999)
    return abs(x[-1] - x[0]) / (np.percentile(near, 95) + 1e-9)


def rms_db(x):
    return 20 * np.log10(np.sqrt(np.mean(x ** 2)) + 1e-12)


def fingerprint(x):
    """A take's shape over its whole length: where its energy sits (a profile over 64 bands, 60 Hz to 12 kHz) and how
    it goes (its envelope, 32 points from its start to its end), each normalised. Two takes are alike as the product
    of the two: a drip at another pitch differs in the first, a gust that peaks later in the second."""
    x = np.asarray(x, dtype=float)
    if not np.any(x):
        return np.zeros(64), np.zeros(32)
    loud = np.abs(x) > 0.01 * np.max(np.abs(x))
    first, last = int(np.argmax(loud)), len(x) - int(np.argmax(loud[::-1]))
    seg = x[first:last]
    if len(seg) < 2048:
        seg = np.concatenate([seg, np.zeros(2048 - len(seg))])
    f, _, z = signal.stft(seg, SR, nperseg=2048, noverlap=1536)
    power = np.abs(z) ** 2
    edges = np.geomspace(60, 12000, 65)
    profile = np.array([power[(f >= lo) & (f < hi)].sum() for lo, hi in zip(edges[:-1], edges[1:])])
    profile = np.sqrt(profile)
    envelope = np.sqrt(power.sum(axis=0))
    envelope = np.interp(np.linspace(0, len(envelope) - 1, 32), np.arange(len(envelope)), envelope)
    return profile / (np.linalg.norm(profile) + 1e-12), envelope / (np.linalg.norm(envelope) + 1e-12)


def alike(a, b):
    return float(np.dot(a[0], b[0]) * np.dot(a[1], b[1]))


# ------------------------------------------------------------------------------------------------ the families
# loudness band (LUFS), centroid ceiling (Hz), and which of their files are beds (loops) or music.
FAMILIES = {
    "buttons": dict(lufs=(-19, -12), centroid=2400),
    "materials": dict(lufs=(-32, -11), centroid=4500),
    "sheets": dict(lufs=(-30, -11), centroid=4000),
    "story": dict(lufs=(-25, -10), centroid=2000),
    "endings": dict(lufs=(-27, -12), centroid=2000),
    "ambience": dict(lufs=(-27, -16), centroid=1600),
    "lobby": dict(lufs=(-29, -17), centroid=2000),
    "water": dict(lufs=(-30, -12), centroid=2600),
    "shop": dict(lufs=(-28, -13), centroid=3000),
}
LOOPS = re.compile(r"^(UnderwaterHum|SlideRush|WhirlRoar|CulvertWash|FlumeRush|ShoreSea|RoofWind|PartyFar|HarbourNight|"
                   r"BathsHum|HoldDrone|SeaBed_\d|FountainBed|Heartbeat|Lap|Pour|Stream|\w+Loop)$")
MUSIC = re.compile(r"(Chord|SecretSting|Chime_\d|BuoyBell_(x)?\d|button_(combo|circuit)_\d|button_linear_(x)?\d|HoldDrone|"
                   r"PartyFar|Siren|CountdownTock_x\d|TownsfolkVoice_x\d|HarbourNight|ShopTab_x\d|CrateReveal_x\d|ShopOpen)$")
ATTACK_FIRST = {"bubblePop_x4"}  # heard the moment the foot lands: loud from its first sample, by design
SHEET = re.compile(r"^(\w+)_x(\d+)$")
# Files kept only so their old ids still play: superseded by a sheet of the same event (checked for format alone).
SUPERSEDED_BY_SHEET = re.compile(r"^(iceCrack|jelloWobble|foamCompress|switchClack|chocolateSnap)_\d$")


def check_file(folder, path, spec, takes):
    name = path.stem
    rate, data = wavfile.read(str(path))
    where = "%s/%s" % (folder, path.name)
    if data.ndim != 1:
        fail("%s: stereo; Roblox plays a 3D sound from a mono file only" % where)
        data = data.mean(axis=1)
    if rate != SR:
        fail("%s: %d Hz, not 44100" % (where, rate))
    if data.dtype != np.int16:
        fail("%s: %s, not 16-bit" % (where, data.dtype))
    x = data.astype(float) / 32768.0
    if not len(x) or not np.any(x):
        fail("%s: silent" % where)
        return
    top = 20 * np.log10(np.max(np.abs(x)))
    if top > -0.9:
        fail("%s: peaks at %.1f dBFS (clipping on some devices; keep under -0.9)" % (where, top))
    if abs(np.mean(x)) > 0.005:
        fail("%s: a DC offset of %.3f (it thumps as it starts and stops)" % (where, np.mean(x)))
    if folder == "materials" and SUPERSEDED_BY_SHEET.match(name):
        return
    sheet = SHEET.match(name)
    loop = bool(LOOPS.match(name))
    if loop and name != "Heartbeat":
        s = seam(x)
        if s > 2.0:
            fail("%s: the loop's join steps %.1f times its neighbours (a click every time round)" % (where, s))
        head, tail = rms_db(x[:SR * 2]), rms_db(x[-SR * 2:])  # two seconds: a sparse bed (laps) evens out
        if abs(head - tail) > 6:
            fail("%s: %.1f dB louder at one end than the other (a swell or a dip at the join)" % (where, abs(head - tail)))
    else:
        if abs(x[0]) > 0.05 and name not in ATTACK_FIRST:
            fail("%s: starts at %.2f, not from silence (a click as it starts)" % (where, abs(x[0])))
        if np.sqrt(np.mean(x[-220:] ** 2)) > 0.01:
            fail("%s: still sounding at its last sample (cut off: a click as it ends)" % where)
    if sheet:
        count = int(sheet.group(2))
        slot = len(x) // count
        for k in range(count):
            part = x[k * slot:(k + 1) * slot]
            if not np.any(np.abs(part) > 0.01):
                fail("%s: slot %d holds nothing" % (where, k + 1))
            if np.max(np.abs(part[-int(0.04 * SR):])) > 0.01:
                fail("%s: take %d is still sounding as slot %d starts" % (where, k + 1, k + 2))
            if abs(part[0]) > 0.05 and name not in ATTACK_FIRST:
                fail("%s: take %d starts with a click (not from silence)" % (where, k + 1))
        parts = [x[k * slot:(k + 1) * slot] for k in range(count)]
        level = max(lufs(p) for p in parts if np.any(p))
        takes.setdefault((folder, sheet.group(1)), []).extend((("%s[%d]" % (name, k + 1)), p) for k, p in enumerate(parts))
    else:
        level = lufs(x)
        m = re.match(r"^(.*?)_(\d+)$", name)
        if m:
            takes.setdefault((folder, m.group(1)), []).append((name, x))
    lo, hi = spec["lufs"]
    if not lo <= level <= hi:
        fail("%s: %.1f LUFS, outside its family's %d to %d" % (where, level, lo, hi))
    c = centroid(x)
    if c > spec["centroid"]:
        fail("%s: bright for the game's taste (centroid %.0f Hz, its family's ceiling %d)" % (where, c, spec["centroid"]))
    if len(x) >= SR and not MUSIC.search(name):
        tone = tonality(x)
        if tone > 0.9:
            fail("%s: %.0f%% of it is a few steady tones (a bare tone; not music, so it should not be)" % (where, 100 * tone))


def check_takes(takes):
    for (folder, stem), items in takes.items():
        if len(items) < 2:
            continue
        prints = [(n, fingerprint(x)) for n, x in items]
        for i in range(len(prints)):
            for j in range(i + 1, len(prints)):
                same = alike(prints[i][1], prints[j][1])
                if same > 0.997:
                    fail("%s: %s and %s are the same sound (%.3f alike); a take should differ in what happens" % (
                        folder, prints[i][0], prints[j][0], same))


# ------------------------------------------------------------------------------------------------ named as the game asks
def asked_for():
    """Every name the Luau looks up in a sound folder, however it does it: Cinema.sound("Name"); a variable holding the
    folder (`local folder = SoundService:FindFirstChild("StorySounds")`) and then `folder:FindFirstChild("Name")`; and a
    file's own `sound("Name", ...)` helper where that helper looks in StorySounds."""
    asked = {}
    folders = {"StorySounds": "story", "AmbienceSounds": "ambience", "LobbySounds": "lobby"}
    for path in SRC.rglob("*.lua"):
        text = path.read_text(encoding="utf-8", errors="replace")
        for m in re.finditer(r'Cinema\.sound\("(\w+)"', text):
            asked.setdefault(("story", m.group(1)), path.name)
        for key, folder in folders.items():
            # Only within the function that took the folder (to the next `end` at the margin): the same variable
            # name holds other folders in other functions.
            for found in re.finditer(r'local (\w+) = [^\n]*FindFirstChild\("%s"\)' % key, text):
                close = text.find("\nend", found.end())
                window = text[found.end():close if close > 0 else len(text)]
                for m in re.finditer(r'\b%s:FindFirstChild\("(\w+)"\)' % found.group(1), window):
                    asked.setdefault((folder, m.group(1)), path.name)
        helper = re.search(r'local function sound\(name: string\??,[^\n]*\n(?:[^\n]*\n){0,2}[^\n]*"StorySounds"', text)
        if helper:
            for m in re.finditer(r'\bsound\("(\w+)",', text):
                asked.setdefault(("story", m.group(1)), path.name)
    return asked


def check_names():
    present = {}
    for folder in FAMILIES:
        d = AUDIO / folder
        present[folder] = {p.stem for p in d.glob("*.wav")} if d.exists() else set()
    story_like = present["story"] | present["endings"]
    for (folder, name), where in sorted(asked_for().items()):
        have = story_like if folder == "story" else present[folder]
        if name not in have:
            fail("%s asks for the sound %s, and there is no audio/%s/%s.wav" % (where, name,
                                                                            "story or endings" if folder == "story" else folder,
                                                                            name))


def check_lobby():
    """THE LOBBY'S SHEETS AS THE CLIENT PLAYS THEM: every family in AmbienceService's LOBBY and PRESSES, and in
    HubLeverService's LEVER, names a sheet that is there, with as many takes as it says and slots as long as it says
    (a slot too long plays the next take's start; too short, cuts a wave off), and the same slots as its generator
    writes (gen_lobby_sfx.py, gen_press_sfx.py); and the beds it plays by name are there."""
    amb = (SRC / "Client" / "Services" / "AmbienceService.lua")
    text = amb.read_text(encoding="utf-8") if amb.exists() else ""
    lever_file = SRC / "Client" / "Services" / "HubLeverService.lua"
    lever = lever_file.read_text(encoding="utf-8") if lever_file.exists() else ""
    pattern = r'^\t(\w+) = \{ sheet = "(\w+)", slot = ([\d.]+), takes = (\d+),'
    rows = re.findall(pattern, text, re.M) + re.findall(pattern, lever, re.M)
    if "LobbySounds" in text and not rows:
        fail("AmbienceService: this check can no longer read the lobby's families (LOBBY)")
    slots = {}
    for name in ("gen_lobby_sfx.py", "gen_press_sfx.py"):
        gen = AUDIO / name
        made = gen.read_text(encoding="utf-8") if gen.exists() else ""
        found = re.search(r"SLOTS = \{(.*?)\}", made, re.S)
        if found:
            slots.update(dict(re.findall(r'"(\w+)": ([\d.]+)', found.group(1))))
    for family, sheet, slot, count in rows:
        path = AUDIO / "lobby" / ("%s.wav" % sheet)
        m = SHEET.match(sheet)
        if not path.exists():
            fail("AmbienceService plays the lobby's %s from %s, and there is no audio/lobby/%s.wav" % (family, sheet, sheet))
            continue
        if not m or int(m.group(2)) != int(count):
            fail("AmbienceService: the lobby's %s says %s takes, and %s holds %s" % (family, count, sheet,
                                                                                  m.group(2) if m else "a single take"))
            continue
        rate, data = wavfile.read(str(path))
        if abs(len(data) / rate / int(count) - float(slot)) > 0.01:
            fail("AmbienceService: the lobby's %s plays %s s slots, and %s has %.2f s ones" % (
                family, slot, sheet, len(data) / rate / int(count)))
        made = slots.get(m.group(1))
        if made is None or abs(float(made) - float(slot)) > 1e-6:
            fail("its generator writes %s with %s s slots, and the game plays %s" % (sheet, made, slot))
    if rows:
        for name in ("SeaBed_1", "SeaBed_2", "FountainBed"):
            if not (AUDIO / "lobby" / ("%s.wav" % name)).exists():
                fail("AmbienceService plays the lobby's %s, and there is no audio/lobby/%s.wav" % (name, name))
        # WIRED: in the lobby only (on at joining, on and off with the level), one slot of a sheet a time and never
        # one of the last two again, each take gone at its slot's end; and the server's stand-ins only without them.
        for needle, why in (
            ("\t\tlobbyOn(wanted == nil)\n", "the lobby's sound does not follow you in and out of the levels"),
            ("\tif level == nil then\n\t\tlobbyOn(true)\n\tend", "the lobby is silent when you join until you have been on a level"),
            ("(take :: any).PlaybackRegion = NumberRange.new(from, from + family.slot - 0.05)",
             "a take of a sheet plays on into the next take"),
            ("while #recent > math.min(2, family.takes - 1) do", "the same take can come twice running"),
            ("lobbyAt(take, at, lobbyRange(family.volume), pitch, near, far, family.slot / pitch)",
             "a take is not stopped at its slot's end where a region cannot be set"),
            ('if child.Name == "LobbySounds" and level == nil then', "the sounds imported while playing are not picked up"),
        ):
            if needle not in text:
                fail("AmbienceService: " + why)
        hub = (SRC / "Server" / "Services" / "HubService.lua")
        hub_text = hub.read_text(encoding="utf-8") if hub.exists() else ""
        stand = hub_text[hub_text.find("local ownSound = "):hub_text.find("-- Gulls, if an id has been pasted in.")]
        if 'local ownSound = game:GetService("SoundService"):FindFirstChild("LobbySounds") ~= nil' not in hub_text \
                or "\tif not ownSound then\n" not in stand \
                or stand.count('SoundId = "rbxasset://sounds/impact_water.mp3"') != 3:
            fail("HubService: its stand-in sea, wind and breakers play over the lobby's own sounds")
        if 'if water and water:IsA("BasePart") and not ownSound then' not in hub_text:
            fail("HubService: its stand-in fountain plays over the lobby's own")
        # HEARD WHERE THEY ARE (the hundred-and-first pass): the fountain fading to nothing within a short walk, the
        # presses at the pad on every screen near it, the lever at the lever; nothing of the room's played from its
        # folder (a Sound in a Folder is heard everywhere at once).
        for needle, why in (
            ("lobbyAt(s, fountain, 0.55, 1, 6, 55, 1e6)", "the fountain is heard from across the promenade"),
            ("lobbyAt(take, part.Position + Vector3.new(0, 1, 0), spec.volume, pitch, 6, 60, spec.slot / pitch)",
             "a press is not heard from the pad pressed"),
            ("if standing and standing ~= before then", "a press sounds again and again while you stand on the pad"),
            ('return if part:GetAttribute("Locked") then "locked" else "pad"', "a locked pad sounds like an open one"),
            ("local ok, err = pcall(scanPresses)", "the presses are never listened for"),
        ):
            if needle not in text:
                fail("AmbienceService: " + why)
        for needle, why in (
            ("s.Parent = at", "the lever's sound is not at the lever"),
            ("s.RollOffMode = Enum.RollOffMode.InverseTapered", "the lever's sound does not fade with distance"),
            ("local yours = os.clock() - pulledAt < 4", "the lever sounds when nobody pulled it"),
            ("pulledAt = os.clock()", "the lever sounds when nobody pulled it"),
        ):
            if needle not in lever:
                fail("HubLeverService: " + why)
        if re.search(r"playAt\((folder|hubFolder), VOTE", hub_text):
            fail("HubService: a vote's sound is played from the lobby's folder, everywhere at once")
        if "splash.RollOffMode = Enum.RollOffMode.InverseTapered" not in hub_text:
            fail("HubService: the stand-in fountain is heard from across the promenade")


def check_shop():
    """THE SHOP'S OWN SOUNDS AS THE CLIENT PLAYS THEM (the hundred-and-fifth pass): every sheet in audio/shop has the
    slots its generator writes (gen_shop_sfx.py) and ShopLook plays; every sound ShopLook asks for is there; the tabs'
    sheet holds one take for each tab ShopLook knows; and Bootstrap checks for every one of them in ShopSounds."""
    look_file = SRC / "Client" / "Services" / "ShopLook.lua"
    if not look_file.exists():
        return
    look = look_file.read_text(encoding="utf-8")
    gen = AUDIO / "gen_shop_sfx.py"
    made = gen.read_text(encoding="utf-8") if gen.exists() else ""
    found = re.search(r"SLOTS = \{(.*?)\}", made, re.S)
    slots = dict(re.findall(r'"(\w+)": ([\d.]+)', found.group(1))) if found else {}
    if not slots:
        fail("gen_shop_sfx.py: this check can no longer read its SLOTS")
    found = re.search(r"^local SLOT = \{(.*?)\}", look, re.M)
    played = dict(re.findall(r"(\w+) = ([\d.]+)", found.group(1))) if found else {}
    if not played:
        fail("ShopLook: this check can no longer read its SLOT")
    have = {q.stem for q in (AUDIO / "shop").glob("*.wav")}
    for name in sorted(have):
        m = SHEET.match(name)
        if not m:
            continue
        slot = slots.get(m.group(1))
        if slot is None:
            fail("gen_shop_sfx.py writes %s with no slot of its own in SLOTS" % name)
            continue
        rate, data = wavfile.read(str(AUDIO / "shop" / ("%s.wav" % name)))
        if abs(len(data) / rate / int(m.group(2)) - float(slot)) > 0.01:
            fail("audio/shop/%s.wav has %.2f s slots, and its generator says %s" % (
                name, len(data) / rate / int(m.group(2)), slot))
        if m.group(1) in played and abs(float(played[m.group(1)]) - float(slot)) > 1e-6:
            fail("ShopLook plays %s in %s s slots, and its generator writes %s" % (name, played[m.group(1)], slot))
    for name in sorted(set(re.findall(r'"ShopSounds/(\w+)"', look))):
        if name not in have:
            fail("ShopLook asks for ShopSounds/%s, and there is no audio/shop/%s.wav" % (name, name))
    order = re.search(r"^ShopLook\.TAB_ORDER = \{(.*?)\}", look, re.M | re.S)
    tabs = re.findall(r'"(\w+)"', order.group(1)) if order else []
    sheet = next((n for n in have if n.startswith("ShopTab_x")), None)
    if not tabs:
        fail("ShopLook: this check can no longer read its TAB_ORDER")
    elif sheet is None or int(SHEET.match(sheet).group(2)) != len(tabs):
        fail("ShopLook has %d tabs, and the tabs' sheet holds %s takes" % (len(tabs), SHEET.match(sheet).group(2)
                                                                           if sheet else "no"))
    # EVERY THEME'S PRESS from somewhere real: a material's uploaded takes or its files, the story's or the water's.
    audio_text = (SRC / "Client" / "Services" / "AudioService.lua")
    audio_text = audio_text.read_text(encoding="utf-8") if audio_text.exists() else ""
    water = SRC / "Shared" / "WaterSounds.lua"
    water = water.read_text(encoding="utf-8") if water.exists() else ""
    for folder_name, name in sorted(set(re.findall(r'sound = "(\w+)/(\w+)"', look))):
        if folder_name == "MaterialSounds":
            files = list((AUDIO / "materials").glob("%s_*.wav" % name)) + list((AUDIO / "sheets").glob("%s_*.wav" % name))
            if not files and not re.search(r"\n\t%s = \{\n\t\t\"rbxassetid://" % name, audio_text):
                fail("ShopLook presses with the material sound %s, and it has no ids and no files" % name)
        elif folder_name == "StorySounds":
            if not ((AUDIO / "story" / ("%s.wav" % name)).exists() or (AUDIO / "endings" / ("%s.wav" % name)).exists()):
                fail("ShopLook presses with StorySounds/%s, and there is no such file" % name)
        elif folder_name == "WaterSounds":
            m = SHEET.match(name)
            row = re.search(r'sheet = "%s", slot = ([\d.]+)' % name, water)
            if not (AUDIO / "water" / ("%s.wav" % name)).exists() or not row:
                fail("ShopLook presses with WaterSounds/%s, and WaterSounds has no such sheet" % name)
            elif not m or m.group(1) not in played or abs(float(played[m.group(1)]) - float(row.group(1))) > 1e-6:
                fail("ShopLook plays WaterSounds/%s in slots of its own, not WaterSounds's %s s" % (name, row.group(1)))
        elif folder_name != "ShopSounds":
            fail("ShopLook presses with %s/%s, a folder this check does not know" % (folder_name, name))
    # A CRATE'S REVEAL, a take for each rarity (the hundred-and-sixth pass).
    found = re.search(r"local RARITY_TAKE = \{(.*?)\}", look)
    reveal = next((n for n in have if n.startswith("CrateReveal_x")), None)
    if found and reveal:
        levels = sorted(int(v) for v in re.findall(r"= (\d+)", found.group(1)))
        if levels != list(range(1, int(SHEET.match(reveal).group(2)) + 1)):
            fail("ShopLook plays the crate's reveal by rarity as takes %s, and %s holds %s" % (
                levels, reveal, SHEET.match(reveal).group(2)))
    boot = SRC / "Server" / "Bootstrap.server.lua"
    text = boot.read_text(encoding="utf-8") if boot.exists() else ""
    found = re.search(r"local SHOP_SOUNDS = \{(.*?)\}", text, re.S)
    listed = set(re.findall(r'"(\w+)"', found.group(1))) if found else set()
    if listed != have:
        fail("Bootstrap checks ShopSounds for %s, and audio/shop holds %s" % (sorted(listed), sorted(have)))


def check_own():
    """YOUR OWN RECORDING, ALONE (the hundred-and-first pass): the soap's crumble you uploaded is the only one played,
    never the generated takes between yours."""
    audio = SRC / "Client" / "Services" / "AudioService.lua"
    text = audio.read_text(encoding="utf-8") if audio.exists() else ""
    if "local OWN_ONLY: { [string]: boolean } = { soapCrumble = true }" not in text:
        fail("AudioService: the soap's own recording is not kept alone")
    if "if OWN_ONLY[event] and #list > 0 then\n\t\t\t\tcontinue" not in text:
        fail("AudioService: the folder's takes are mixed in with your own recording")


def check_water():
    """THE LEVELS' WATER AS THE GAME PLAYS IT: every family WaterSounds.lua names is a file in audio/water with as many
    takes and as long slots as it says (and as gen_water_sfx.py writes); and every level's water goes through it."""
    module = SRC / "Shared" / "WaterSounds.lua"
    if not module.exists():
        return
    text = module.read_text(encoding="utf-8")
    sheets = re.findall(r'^\t(\w+) = \{ sheet = "(\w+)", slot = ([\d.]+), takes = (\d+) \}', text, re.M)
    beds = re.findall(r'^\t(\w+) = \{ bed = "(\w+)" \}', text, re.M)
    if not sheets or not beds:
        fail("WaterSounds: this check can no longer read its families")
    gen = AUDIO / "gen_water_sfx.py"
    src = gen.read_text(encoding="utf-8") if gen.exists() else ""
    found = re.search(r"SLOTS = \{(.*?)\}", src)
    slots = dict(re.findall(r'"(\w+)": ([\d.]+)', found.group(1))) if found else {}
    for kind, sheet, slot, count in sheets:
        path = AUDIO / "water" / ("%s.wav" % sheet)
        m = SHEET.match(sheet)
        if not path.exists():
            fail("WaterSounds plays %s from %s, and there is no audio/water/%s.wav" % (kind, sheet, sheet))
            continue
        if not m or int(m.group(2)) != int(count):
            fail("WaterSounds: %s says %s takes, and %s holds %s" % (kind, count, sheet, m.group(2) if m else "one"))
            continue
        rate, data = wavfile.read(str(path))
        if abs(len(data) / rate / int(count) - float(slot)) > 0.01:
            fail("WaterSounds: %s plays %s s slots, and %s has %.2f s ones" % (kind, slot, sheet, len(data) / rate / int(count)))
        made = slots.get(m.group(1))
        if made is None or abs(float(made) - float(slot)) > 1e-6:
            fail("gen_water_sfx.py writes %s with %s s slots, and WaterSounds plays %s" % (sheet, made, slot))
    for kind, bed in beds:
        if not (AUDIO / "water" / ("%s.wav" % bed)).exists():
            fail("WaterSounds plays %s from %s, and there is no audio/water/%s.wav" % (kind, bed, bed))
    for rel, needles in (
        (("Client", "Services", "SkyPoolsClient.lua"), ('if not WaterSounds.dress(s, kind) then', 'play("dip", ', 'play("splash", ')),
        (("Server", "Services", "SkyPoolsService.lua"), ("if not (kind and WaterSounds.dress(s, kind)) then",
                                                       'if not WaterSounds.dress(s, "splash") then')),
        (("Server", "Services", "SunkenCityService.lua"), ("if not (kind and WaterSounds.dress(s, kind)) then",
                                                         ('if not WaterSounds.dress(drip, "drip") then', 2))),
        (("Server", "Services", "FloodedHallsService.lua"), ('if not WaterSounds.dress(drip, "drip") then',)),
        (("Server", "Services", "DiveFinaleService.lua"), ('if WaterSounds.dress(sound, "splash") then',)),
    ):
        path = SRC.joinpath(*rel)
        body = path.read_text(encoding="utf-8") if path.exists() else ""
        for needle in needles:
            needle, times = needle if isinstance(needle, tuple) else (needle, 1)
            if body.count(needle) < times:
                fail("%s: its water is still the engine's one splash (%s)" % (rel[-1], needle))
    if "if pick == last[kind] then" not in text:
        fail("WaterSounds: the same take can come twice running")
    if "(sound :: any).PlaybackRegion = NumberRange.new(from, from + slot - 0.05)" not in text:
        fail("WaterSounds: a take of a sheet plays on into the next")


# ------------------------------------------------------------------------------------------------ the self-test
def selftest():
    """Each rule shown a sound made to break it, and each must say so (and a good one must pass): a check that never
    fails proves nothing."""
    global problems
    import tempfile
    t = np.arange(SR) / SR
    # A good sound: a soft burst of low-mid noise, rising from silence and dying to it, at an ordinary level.
    good = signal.lfilter(*signal.butter(2, [200, 1200], btype="band", fs=SR), np.random.default_rng(1).standard_normal(SR))
    good *= np.clip(t / 0.004, 0, 1) * np.exp(-t / 0.15)
    good = good / np.max(np.abs(good)) * 0.5
    good *= 10 ** ((-22 - lufs(good)) / 20)
    cases = {
        "clipping": np.clip(good * 3, -1, 0.99999),
        "dc": good + 0.02,
        "click_start": np.concatenate([[0.5] * 10, good[10:]]),
        "cut_off": good * 0 + 0.2 * np.sin(2 * np.pi * 200 * t),
        "bare_tone": 0.3 * np.sin(2 * np.pi * 220 * np.arange(3 * SR) / SR) * np.clip(np.arange(3 * SR) / 2000, 0, 1)
        * np.clip((3 * SR - np.arange(3 * SR)) / 2000, 0, 1),
        "too_quiet": good * 0.001,
        "too_bright": np.random.default_rng(2).standard_normal(SR) * np.hanning(SR) * 0.3,
    }
    expect = {"clipping": "peaks at", "dc": "DC offset", "click_start": "not from silence", "cut_off": "cut off",
              "bare_tone": "steady tones", "too_quiet": "outside its family", "too_bright": "bright for"}
    with tempfile.TemporaryDirectory() as tmp:
        tmp = pathlib.Path(tmp)
        missed = []
        for name, x in list(cases.items()) + [("fine", good)]:
            p = tmp / ("%s.wav" % name)
            wavfile.write(p, SR, np.clip(np.round(x * 32767), -32768, 32767).astype(np.int16))
            problems = []
            check_file("story", p, FAMILIES["story"], {})
            said = " ".join(problems)
            if name == "fine":
                if problems:
                    missed.append("a good sound failed: " + said)
            elif expect[name] not in said:
                missed.append("%s was not caught (%s)" % (name, said or "nothing said"))
        # A loop with a step at its join, and two identical takes.
        loop = np.random.default_rng(3).standard_normal(SR * 2) * 0.1
        loop = signal.lfilter([1], [1, -0.99], loop) * 0.05
        loop[-1] = loop[0] + 0.5
        p = tmp / "SeaBed_9.wav"
        wavfile.write(p, SR, np.clip(np.round(loop * 32767), -32768, 32767).astype(np.int16))
        problems = []
        check_file("lobby", p, FAMILIES["lobby"], {})
        if "join steps" not in " ".join(problems):
            missed.append("a loop with a step at its join was not caught")
        problems = []
        check_takes({("materials", "x"): [("x_1", good), ("x_2", good.copy())]})
        if "same sound" not in " ".join(problems):
            missed.append("two identical takes were not caught")
        problems = []
        check_takes({("materials", "x"): [("x_1", good), ("x_2", np.roll(cases["too_bright"], 0) * 0.5)]})
        if problems:
            missed.append("two different takes were called the same")
    problems = []
    return missed


if __name__ == "__main__":
    missed = selftest()
    for m in missed:
        print("FAIL: self-test: " + m)
    if missed:
        sys.exit(1)
    if "--selftest" in sys.argv:
        print("audio self-test: every rule caught its bad sound, and a good one passed")
        sys.exit(0)
    count = 0
    takes = {}
    for folder, spec in FAMILIES.items():
        d = AUDIO / folder
        if not d.exists():
            continue
        for path in sorted(d.glob("*.wav")):
            check_file(folder, path, spec, takes)
            count += 1
    check_takes(takes)
    check_names()
    check_lobby()
    check_water()
    check_shop()
    check_own()
    if problems:
        for problem in problems:
            print("FAIL: " + problem)
        sys.exit(1)
    print("audio: %d files, mono 16-bit 44.1 kHz, none clipping, clean ends, seamless loops, each family at its level "
          "and soft enough, no bare tones outside the music, every take its own, and every name the game asks for "
          "there (self-test: every rule caught its bad sound)" % count)
