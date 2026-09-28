#!/usr/bin/env python3
"""Every Trixie line again, in ElevenLabs' Eleven v4, over the clips on disk.
SPENDS CREDITS.

The lines are gen_trixie_voices.py's (LINES), unchanged in wording and file
name. What is new is how they are sent, following ElevenLabs' prompting guide
for v4:
  - an audio tag in front of each line ([excited], [teasing], [sighs]...),
    which v4 takes as direction for the delivery and does not say;
  - "sugar" is never set off by a pause (fixed in the lines themselves).

Each clip is fetched as mp3, made louder (+30% with a limiter, as
amplify_voices.py does) and written as Ogg over the old clip of the same name.
The old generator's compress step is not used here on purpose: it keeps an
existing .ogg over a new .mp3, which would throw every new clip away.
tools/voiced_v4.json remembers what is done, so a run that hits the monthly
quota picks up where it stopped. Afterwards, sync the counts:
python tools/gen_trixie_voices.py --counts-disk, into Lobby.TRIXIE_VOICE.

  set ELEVENLABS_API_KEY=sk_...              (never written to any file)
  python tools/regen_v4.py                   # dry run: every prompt, and the cost
  python tools/regen_v4.py --sample 8        # 8 clips into tools/samples_v4/ to listen to
  python tools/regen_v4.py --go              # every line not yet redone
  python tools/regen_v4.py --go --only win,lose
"""
import argparse, json, os, re, shutil, subprocess, sys, tempfile, time, urllib.error, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_trixie_voices as gen

API = "https://api.elevenlabs.io/v1"
VOICE_ID = os.environ.get("ELEVENLABS_VOICE_ID", "DODLEQrClDo8wCz460ld")
MODEL_ID = os.environ.get("ELEVENLABS_MODEL_ID", "eleven_v4")
OUTPUT_FORMAT = "mp3_44100_128"
SETTINGS = [
    {"stability": 0.45, "similarity_boost": 0.75, "style": 0.35, "use_speaker_boost": True},
    {"stability": 0.5, "similarity_boost": 0.75},
    {"stability": 0.5},
    None,
]
GAIN = 1.3
DONE = os.path.join(HERE, "voiced_v4.json")
SAMPLES = os.path.join(HERE, "samples_v4")
LCONNECT = r"C:\Program Files\Lian-Li\L-Connect 3\x64\ffmpeg.exe"

# The delivery for each situation. Each rotates through its own few, so a
# category's lines do not all come out in one tone.
TAGS = {
    "greet": ["[warm]", "[flirtatious]", "[mischievously]", "[excited]"],
    "banter": ["[mischievously]", "[teasing]", "[sarcastic]", "[laughs]", "[curious]"],
    "bye": ["[warm]", "[flirtatious]", "[teasing]"],
    "win": ["[excited]", "[laughs]", "[delighted]"],
    "lose": ["[sarcastic]", "[teasing]", "[sighs]", "[sympathetic]"],
    "bust": ["[laughs]", "[sarcastic]", "[teasing]"],
    "blackjack": ["[excited]", "[delighted]", "[shouting]"],
    "jackpot": ["[excited]", "[shouting]", "[laughs]"],
    "bigwin": ["[excited]", "[delighted]", "[laughs]"],
    "debt": ["[sarcastic]", "[teasing]", "[stern]"],
    "paid": ["[warm]", "[delighted]", "[teasing]"],
    "open_": ["[excited]", "[mischievously]", "[inviting]"],
    "deathroll_bust": ["[laughs]", "[sarcastic]", "[gasps]"],
    "crash_bail": ["[relieved]", "[excited]", "[teasing]"],
    "crash_boom": ["[gasps]", "[laughs]", "[dramatic]"],
    "deathroll_close": ["[tense]", "[whispers]", "[excited]"],
    "roulette_nobets": ["[impatient]", "[teasing]", "[sarcastic]"],
    "bingo_win": ["[excited]", "[delighted]", "[shouting]"],
    "liarsdice_challenge": ["[dramatic]", "[curious]", "[mischievously]"],
    "liarsdice_bluff": ["[laughs]", "[sarcastic]", "[teasing]"],
    "turn_nudge": ["[impatient]", "[teasing]", "[sarcastic]"],
    "bj_dealerbust": ["[laughs]", "[delighted]", "[sarcastic]"],
    "bj_push": ["[sighs]", "[teasing]", "[sarcastic]"],
    "bj_double": ["[excited]", "[mischievously]", "[teasing]"],
    "poker_showdown": ["[dramatic]", "[excited]", "[mischievously]"],
    "poker_fold": ["[sighs]", "[teasing]", "[sarcastic]"],
    "crash_takeoff": ["[excited]", "[dramatic]", "[mischievously]"],
    "crash_flyaway": ["[amazed]", "[laughs]", "[excited]"],
    "crash_high": ["[nervous]", "[excited]", "[tense]"],
    "countdown": ["[excited]", "[impatient]", "[mischievously]"],
    "tourney_champ": ["[excited]", "[shouting]", "[delighted]"],
    "tourney_bustout": ["[sympathetic]", "[sighs]", "[teasing]"],
    "intro": ["[warm]"],
    "poke": ["[laughs]", "[flirtatious]", "[teasing]", "[mischievously]"],
}
CUES = [
    (r"^(Hush|Shh)", "[whispers]"),
    (r"^(Ha!|Ha |Haha|Oof|Oops|Ouch|Whoa)", "[laughs]"),
    (r"^(Woohoo|Jackpot|Winner|Whoo|Ka-ching|Yee)", "[excited]"),
    (r"^(Oh no|Uh oh|Oh honey|Lord)", "[gasps]"),
]


def tags_for(cat):
    if cat in TAGS:
        return TAGS[cat]
    if cat.startswith("open_"):
        return TAGS["open_"]
    return [""]


def prompt(name, text):
    if text.lstrip().startswith("["):
        return text
    for pattern, tag in CUES:
        if re.search(pattern, text):
            return f"{tag} {text}"
    cat, n = gen.parse_name(name)
    tags = tags_for(cat)
    tag = tags[max(n - 1, 0) % len(tags)]
    return f"{tag} {text}".strip()


def find_ffmpeg(arg=None):
    for c in (arg, os.environ.get("FFMPEG"), shutil.which("ffmpeg"), LCONNECT):
        if c and os.path.isfile(c):
            return c
    sys.exit("ffmpeg not found: set FFMPEG or pass --ffmpeg")


def load_done():
    try:
        with open(DONE, encoding="utf-8") as f:
            return set(json.load(f))
    except (OSError, ValueError):
        return set()


def save_done(done):
    with open(DONE, "w", encoding="utf-8") as f:
        json.dump(sorted(done), f, indent=0)


class Speaker:
    def __init__(self, key):
        self.key = key
        self.settings_at = 0

    def _post(self, text, settings):
        body = {"text": text, "model_id": MODEL_ID}
        if settings is not None:
            body["voice_settings"] = settings
        req = urllib.request.Request(f"{API}/text-to-speech/{VOICE_ID}?output_format={OUTPUT_FORMAT}",
                                     data=json.dumps(body).encode("utf-8"), method="POST",
                                     headers={"xi-api-key": self.key, "Content-Type": "application/json",
                                              "Accept": "audio/mpeg"})
        with urllib.request.urlopen(req, timeout=120) as r:
            return r.read()

    def say(self, text):
        while True:
            try:
                return self._post(text, SETTINGS[self.settings_at])
            except urllib.error.HTTPError as e:
                detail = e.read().decode("utf-8", "replace")
                if e.code in (400, 422) and "setting" in detail.lower() and self.settings_at + 1 < len(SETTINGS):
                    self.settings_at += 1
                    print(f"  {MODEL_ID} refused those voice settings; now using {SETTINGS[self.settings_at]}")
                    continue
                raise urllib.error.HTTPError(e.url, e.code, detail, e.headers, None)


def to_ogg(ffmpeg, mp3, out):
    part = out + ".tmp.ogg"
    r = subprocess.run([ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-i", mp3,
                        "-af", f"volume={GAIN},alimiter=limit=0.98", "-ac", "1",
                        "-c:a", "libvorbis", "-q:a", "1", part])
    if r.returncode != 0 or not os.path.getsize(part):
        return False
    os.replace(part, out)
    return True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--go", action="store_true", help="generate (spends credits)")
    ap.add_argument("--sample", type=int, help="make N clips into tools/samples_v4/ to listen to first")
    ap.add_argument("--only", help="comma-separated categories")
    ap.add_argument("--ffmpeg")
    args = ap.parse_args()
    cats = set(args.only.split(",")) if args.only else None

    done = load_done()
    names = sorted(gen.LINES, key=gen.sort_key)
    todo = [(n, prompt(n, gen.LINES[n])) for n in names
            if n not in done and (not cats or gen.parse_name(n)[0] in cats)]
    if args.sample:
        seen, picked = set(), []
        for n, text in todo:
            cat = gen.parse_name(n)[0]
            if cat not in seen and len(picked) < args.sample:
                seen.add(cat)
                picked.append((n, text))
        todo = picked

    chars = sum(len(t) for _, t in todo)
    print(f"{len(todo)} clip(s), {chars} characters, model {MODEL_ID}, voice {VOICE_ID}.")
    if not (args.go or args.sample):
        for n, text in todo:
            print(f"  {n}: {text}")
        print("Dry run: nothing sent. --sample N to hear a few first, --go to generate.")
        return
    key = os.environ.get("ELEVENLABS_API_KEY")
    if not key:
        sys.exit("Set ELEVENLABS_API_KEY first (it starts with sk_).")
    ffmpeg = find_ffmpeg(args.ffmpeg)
    speaker = Speaker(key)
    out_dir = SAMPLES if args.sample else gen.OUT_DIR
    os.makedirs(out_dir, exist_ok=True)

    made = 0
    with tempfile.TemporaryDirectory() as tmp:
        for i, (name, text) in enumerate(todo, 1):
            try:
                audio = speaker.say(text)
            except urllib.error.HTTPError as e:
                detail = str(e.msg).lower()
                if "quota" in detail or e.code in (402, 429) or "credit" in detail:
                    print(f"[{i}/{len(todo)}] quota or rate limit reached ({e.code}). Stopping; re-run later.")
                    break
                if e.code == 401 or "api_key" in detail:
                    sys.exit(f"The API key was refused ({e.code}): {e.msg[:200]}")
                print(f"[{i}/{len(todo)}] {name}: HTTP {e.code} {e.msg[:200]}")
                continue
            mp3 = os.path.join(tmp, name + ".mp3")
            with open(mp3, "wb") as f:
                f.write(audio)
            if not to_ogg(ffmpeg, mp3, os.path.join(out_dir, name + ".ogg")):
                print(f"[{i}/{len(todo)}] {name}: conversion failed")
                continue
            if not args.sample:
                # A leftover mp3 of the same name would be a stale second copy.
                stale = os.path.join(gen.OUT_DIR, name + ".mp3")
                if os.path.exists(stale):
                    os.remove(stale)
                done.add(name)
                save_done(done)
            made += 1
            print(f"[{i}/{len(todo)}] {name}  {text}")
            time.sleep(0.3)
    if args.sample:
        print(f"\n{made} sample(s) in {SAMPLES}. Listen, then run --go.")
    else:
        print(f"\n{made} clip(s) redone in v4. Next: python tools/gen_trixie_voices.py --counts-disk, "
              "paste into Lobby.TRIXIE_VOICE, and restart the game client.")


if __name__ == "__main__":
    main()
