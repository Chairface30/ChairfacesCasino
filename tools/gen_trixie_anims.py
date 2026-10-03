#!/usr/bin/env python3
"""Animate Trixie with AutoSprite and pack the clips for UI/Trixie.lua.

Her front-facing standing art (Textures/dealer/trixie_tall.tga) is uploaded
once as an AutoSprite asset (free), and each clip below animates that very
picture (animate_asset, turbo: 5 credits, 2 s). Animating the picture keeps
her face, painted style, thighs-up framing and her facing the player; the
character route was tried first and redrew her full-body, side-on and small.
Every clip loops, so it starts and ends on her standing pose, and any clip
can follow any other in game without a jump.

Each finished sheet is fetched, every frame is cropped to the same box her
stills use (274 x 350, lined up on the first frame against her base art),
and the frames are packed into Textures/dealer/anim/<clip>.tga. Then
UI/TrixieClips.lua is rewritten from everything that is done.

Ids and jobs are kept in tools/trixie_anims.json, so a run only does what is
missing and nothing is paid for twice. Raw sheets are kept in
tools/anim_src/ (git ignored).

USAGE
  python tools/gen_trixie_anims.py                         plan only (no calls)
  python tools/gen_trixie_anims.py --go --only idle_breathe   one clip
  python tools/gen_trixie_anims.py --go                    every missing clip
  python tools/gen_trixie_anims.py --repack [--only x]     re-crop and re-pack (free)
  python tools/gen_trixie_anims.py --go --redo x           pay for a clip again

Needs: pip install pillow
"""
import argparse
import io
import json
import os
import sys
import time
import urllib.error
import urllib.request

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOOLS = os.path.join(ROOT, "tools")
SRC_DIR = os.path.join(TOOLS, "anim_src")
OUT_DIR = os.path.join(ROOT, "Textures", "dealer", "anim")
BASE_ART = os.path.join(ROOT, "Textures", "dealer", "trixie_tall.tga")
RECORD = os.path.join(TOOLS, "trixie_anims.json")
MANIFEST = os.path.join(ROOT, "UI", "TrixieClips.lua")
MCP_URL = "https://www.autosprite.io/api/mcp"

FRAME_W, FRAME_H = 274, 350   # the size every Trixie window draws her at
SHEET_FRAMES = 32             # frames cut from each 2 s clip (7 x 5 fits a 2048 texture)
TEX_FORMAT = "blp"            # "blp" (DXT5, ~3 MB a clip) or "tga" (RLE, ~7 MB)
PLAY_FPS = 12                # played a little slower than shot: a 2.7 s loop
SHEET_SIZE = 512              # square frame size requested from AutoSprite
CREDITS_PER_CLIP = 5          # turbo tier

PROMPT_MAX = 200              # animate_asset's limit
# Every clip: she keeps facing the player and the shot holds still.
KEEP = " She keeps facing the viewer; camera still."
# Chairface asked for this on every idle: natural, not over the top.
BREATH = " Her chest rises and falls gently with each breath, subtle."

# name, mood, prompt. Moods match UI/Trixie.lua: wait, win, love, lose, deal, shuf.
CLIPS = [
    ("idle_rest", "wait", "Calm and still, only breathing; eyes open on the viewer, no blink, head still." + BREATH),
    ("idle_rest2", "wait", "(made locally: tools/make_rest_loop.py)"),
    ("idle_breathe", "wait","Relaxed idle: she blinks slowly with a soft smile, bunny ears twitch once." + BREATH),
    ("idle_hair", "wait", "She tucks a lock of hair behind her pointed ear, then lowers her hand." + BREATH),
    ("idle_glance", "wait", "She glances to one side, then looks back at the viewer and winks." + BREATH),
    ("idle_tap", "wait", "She taps her gloved fingers idly, a little bored, slight sway." + BREATH),
    ("idle_ears", "wait", "Her bunny ears droop and perk back up as she rolls her eyes playfully." + BREATH),
    ("idle_bounce", "wait", "She bounces excitedly, bunny ears flopping, beaming."),
    ("idle_stretch", "wait", "She rolls her shoulders in a light stretch, then settles." + BREATH),
    ("idle_smile", "wait", "She smiles warmly at the viewer and gives a small nod." + BREATH),
    ("idle_wink", "wait", "She gives the viewer a playful wink and a little grin." + BREATH),
    ("idle_lookleft", "wait", "She looks off to her left, curious, then back to the viewer." + BREATH),
    ("idle_lookright", "wait", "She looks off to her right with a smirk, then back to the viewer." + BREATH),
    ("idle_sway", "wait", "She sways her hips gently from side to side as if to soft music." + BREATH),
    ("idle_hum", "wait", "She hums to herself, her head bobbing slightly to a tune." + BREATH),
    ("idle_yawn", "wait", "She covers a small yawn with her gloved hand, then smiles." + BREATH),
    ("idle_bowtie", "wait", "She straightens her bow tie with both hands." + BREATH),
    ("idle_earscratch", "wait", "She scratches behind her pointed ear with her fingers, head tilting into it, then lowers her hand." + BREATH),
    ("idle_shift", "wait", "She shifts her weight from one leg to the other, relaxed." + BREATH),
    ("idle_fingertips", "wait", "She glances down at her gloved fingertips, then back up." + BREATH),
    ("idle_pursed", "wait", "She purses her lips thoughtfully, then smiles." + BREATH),
    ("idle_eyebrow", "wait", "She raises one eyebrow at the viewer, amused." + BREATH),
    ("idle_giggle", "wait", "She giggles softly at a private joke." + BREATH),
    ("idle_wave", "wait", "She gives the viewer a small friendly wave." + BREATH),
    ("idle_headtilt", "wait", "She tilts her head curiously at the viewer." + BREATH),
    ("idle_headband", "wait", "She reaches up and straightens her bunny ears headband." + BREATH),
    ("idle_content", "wait", "She lets out a contented little sigh, shoulders settling." + BREATH),
    ("idle_peek", "wait", "She leans slightly forward as if peeking at cards on the table." + BREATH),
    ("idle_chin", "wait", "She taps her chin with one finger, thinking." + BREATH),
    ("idle_shy", "wait", "She blushes and looks away shyly, then back at the viewer." + BREATH),
    ("win_clap", "win", "She claps her gloved hands and laughs, delighted for the player."),
    ("win_fist", "win", "She pumps her fist high above her head, arm fully extended, cheering excitedly, then lowers it."),
    ("win_bounce", "win", "Two small excited bunny hops in place, only a few inches high: knees bend, little jumps, hands up like bunny paws. Her head stays in view."),
    ("win_point", "win", "Arms extended, she points both index fingers at the viewer, tilts her head side to side flirtatiously and winks."),
    ("win_cheer", "win", "She throws both arms up and cheers, beaming at the viewer."),
    ("win_thumbs", "win", "She gives the viewer a thumbs up and a wink."),
    ("win_shimmy", "win", "She does a happy little shimmy of her shoulders, grinning."),
    ("win_laugh", "win", "She laughs delightedly, one hand on her chest."),
    ("win_hop", "win", "She hops on the spot, bunny ears bouncing, fists clenched in excitement."),
    ("win_applaud", "win", "She claps her gloved hands together over and over in applause, smiling."),
    ("love_kiss", "love", "She blows a kiss to the viewer and winks."),
    ("love_hug", "love", "She hugs herself happily and sways, eyes closed."),
    ("love_blush", "love", "Her cheeks flush deep pink as she blushes on her face, smiling shyly."),
    ("love_dreamy", "love", "She gazes at the viewer dreamily, chin resting on her hands."),
    ("love_twokisses", "love", "She blows two kisses to the viewer, one with each hand."),
    ("love_lashes", "love", "She flutters her eyelashes at the viewer and smiles sweetly."),
    ("love_twirl", "love", "She giggles and twirls a lock of hair around her finger, smitten."),
    ("lose_wince", "lose", "She winces sympathetically, sucking air through her teeth."),
    ("lose_headshake", "lose", "She shakes her head slowly with a sorry smile."),
    ("lose_shrug", "lose", "She gives a big exaggerated shrug, lifting both arms high, palms up, shoulders raised to her ears."),
    ("lose_console", "lose", "She reaches toward the viewer with a consoling pat in the air."),
    ("lose_arms", "lose", "She crosses her arms and pouts, then softens."),
    ("lose_slump", "lose", "She sags and keels over a little at the waist in defeat, then straightens back up."),
    ("love_heart", "love", "She brings her hands together in front of her chest to make a heart shape and holds it, smiling."),
    ("love_swoon", "love", "She clasps her hands by her cheek and sways, blushing."),
    ("talk_chat", "talk", "She talks to the viewer, her mouth moving naturally as she speaks, friendly smile."),
    ("talk_gesture", "talk", "She talks to the viewer, mouth moving, gesturing with one gloved hand."),
    ("talk_explain", "talk", "She explains something to the viewer, mouth moving, counting on her fingers."),
    ("talk_laugh", "talk", "She talks to the viewer and laughs mid-sentence, mouth moving."),
    ("talk_lean", "talk", "She leans in slightly and talks to the viewer, mouth moving, as if sharing a secret."),
    ("talk_tease", "talk", "She talks teasingly to the viewer, mouth moving, playful smirk and raised eyebrow."),
    ("talk_nod", "talk", "She talks to the viewer, mouth moving, nodding along to her own words."),
    ("talk_excited", "talk", "She talks excitedly to the viewer, mouth moving quickly, eyes bright."),
    ("talk_welcome", "talk", "She talks warmly to the viewer, mouth moving, opening one hand in welcome."),
    ("talk_hip", "talk", "She talks to the viewer, mouth moving, one hand on her hip."),
    ("lose_pout", "lose","She pouts sympathetically and gives a small shrug."),
    ("lose_facepalm", "lose", "She covers her eyes with one hand, wincing, then peeks through her fingers."),
    ("lose_sigh", "lose", "She sighs, shoulders drop, a sad little smile and a slow head shake."),
    ("lose_ears", "lose", "Her bunny ears droop sadly as she frowns, then a consoling smile."),
]


def prompt_for(name):
    p = CLIP_BY_NAME[name][2] + KEEP
    if len(p) > PROMPT_MAX:
        raise SystemExit(f"{name}: prompt is {len(p)} chars, the limit is {PROMPT_MAX}")
    return p
CLIP_BY_NAME = {c[0]: c for c in CLIPS}


# ---------------------------------------------------------------- MCP client
# (same client as GnomishPachinko/tools/gen_sprites.py)

class AutoSprite:
    def __init__(self, key):
        self.key = key
        self.sid = None
        self.rid = 0
        self._post("initialize", {"protocolVersion": "2025-03-26", "capabilities": {},
                                  "clientInfo": {"name": "chairfaces-casino", "version": "1.0"}})
        try:
            self._post("notifications/initialized", {})
        except Exception:
            pass

    def _post(self, method, params):
        self.rid += 1
        body = json.dumps({"jsonrpc": "2.0", "id": self.rid, "method": method, "params": params}).encode()
        req = urllib.request.Request(MCP_URL, data=body, method="POST")
        req.add_header("Authorization", "Bearer " + self.key)
        req.add_header("Content-Type", "application/json")
        req.add_header("Accept", "application/json, text/event-stream")
        if self.sid:
            req.add_header("Mcp-Session-Id", self.sid)
        for attempt in range(4):
            try:
                with urllib.request.urlopen(req, timeout=120) as r:
                    self.sid = r.headers.get("Mcp-Session-Id") or self.sid
                    raw = r.read().decode("utf-8", "replace")
                    if "text/event-stream" in r.headers.get("Content-Type", ""):
                        msgs = [json.loads(l[5:].strip()) for l in raw.splitlines() if l.startswith("data:")]
                        return msgs[-1] if msgs else None
                    return json.loads(raw) if raw.strip() else None
            except urllib.error.HTTPError as e:
                text = e.read().decode("utf-8", "replace")
                if e.code == 429 and attempt < 3:
                    wait = int(e.headers.get("Retry-After", "30") or 30)
                    print(f"    rate limited, waiting {wait}s")
                    time.sleep(wait)
                    continue
                raise RuntimeError(f"HTTP {e.code}: {text[:300]}")
        raise RuntimeError("gave up after retries")

    def call(self, tool, **args):
        res = self._post("tools/call", {"name": tool, "arguments": args})
        if not res:
            raise RuntimeError(f"{tool}: empty response")
        if "error" in res:
            raise RuntimeError(f"{tool}: {res['error']}")
        result = res.get("result", {})
        if result.get("isError"):
            raise RuntimeError(f"{tool}: " + " ".join(c.get("text", "") for c in result.get("content", [])))
        texts = [c.get("text", "") for c in result.get("content", []) if c.get("type") == "text"]
        for t in texts:
            t = t.strip()
            if t.startswith("{") or t.startswith("["):
                try:
                    return json.loads(t)
                except Exception:
                    pass
        return {"text": "\n".join(texts)}

    def upload(self, path):
        info = self.call("request_upload_url", fileName=os.path.basename(path), contentType="image/png")
        data = open(path, "rb").read()
        req = urllib.request.Request(info["uploadUrl"], data=data, method="PUT")
        req.add_header("Content-Type", "image/png")
        with urllib.request.urlopen(req, timeout=120) as r:
            r.read()
        return info["uploadKey"]


def download(url):
    with urllib.request.urlopen(urllib.request.Request(url), timeout=180) as r:
        return Image.open(io.BytesIO(r.read())).convert("RGBA")


def find(obj, *keys):
    """First value under any of these keys, searching nested dicts/lists."""
    if isinstance(obj, dict):
        for k in keys:
            if obj.get(k) not in (None, "", []):
                return obj[k]
        for v in obj.values():
            got = find(v, *keys)
            if got not in (None, "", []):
                return got
    elif isinstance(obj, list):
        for v in obj:
            got = find(v, *keys)
            if got not in (None, "", []):
                return got
    return None


# ---------------------------------------------------------------- record

def load_record():
    if os.path.exists(RECORD):
        return json.load(open(RECORD, encoding="utf-8"))
    return {"assetId": None, "clips": {}}


def save_record(rec):
    json.dump(rec, open(RECORD, "w", encoding="utf-8"), indent=1, sort_keys=True)


# ---------------------------------------------------------------- packing

def cut_frames(sheet, info):
    """Split an AutoSprite sheet into frames, using its frame spec when given."""
    n = int(find(info, "frameCount", "frames", "totalFrames") or SHEET_FRAMES)
    fw = int(find(info, "frameWidth", "frameSize") or SHEET_SIZE)
    fh = int(find(info, "frameHeight") or fw)
    cols = int(find(info, "columns", "cols") or max(1, sheet.width // fw))
    if sheet.width % fw or cols * fw > sheet.width:     # spec disagrees: trust the image
        cols = max(1, round(sheet.width / fw))
    out = []
    for i in range(n):
        x, y = (i % cols) * fw, (i // cols) * fh
        if y + fh > sheet.height:
            break
        out.append(sheet.crop((x, y, x + fw, y + fh)))
    return out


def crop_box(first):
    """The box in clip space that matches her 274 x 350 stills, found by
    lining her base art up with the clip's first frame (same top and same
    width of the visible figure)."""
    base = Image.open(BASE_ART).convert("RGBA")
    bl, bt, br, bb = base.getchannel("A").point(lambda a: 255 if a > 24 else 0).getbbox()
    fl, ft, fr, fb = first.getchannel("A").point(lambda a: 255 if a > 24 else 0).getbbox()
    if ft == 0 and fb == first.height and fr - fl >= first.width * 0.95:
        # animate_asset stretched her portrait to fill the square: the whole
        # frame is her whole picture, so squeezing it back to 274 x 350 undoes it
        return (0, 0, first.width, first.height), first.height / float(FRAME_H)
    s = (fr - fl) / float(br - bl)
    left = fl - bl * s
    top = ft - bt * s
    return (left, top, left + FRAME_W * s, top + FRAME_H * s), s


def save_blp(img, path):
    """BLP2, DXT5 (8-bit alpha), no mipmaps: 1 byte a pixel, about 2.4x
    smaller than our RLE TGAs. DXT works on 4 x 4 blocks, so the image is
    padded to a multiple of 4 (the texcoords use the real cell sizes, so the
    padding is never drawn)."""
    import struct
    import etcpak   # pip install etcpak
    w, h = -(-img.width // 4) * 4, -(-img.height // 4) * 4
    if (w, h) != img.size:
        padded = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        padded.paste(img, (0, 0))
        img = padded
    # see-through pixels keep stray colors from background removal, and DXT
    # blocks share colors, so they would tint the edges: fill them with the
    # nearby edge color first (alpha-weighted blur)
    import numpy as np
    from PIL import ImageFilter
    a = np.asarray(img, dtype=np.float32)
    alpha = a[..., 3:4] / 255.0
    pre = Image.fromarray(np.uint8(np.concatenate([a[..., :3] * alpha, alpha * 255], axis=2)), "RGBA")
    blur = np.asarray(pre.filter(ImageFilter.GaussianBlur(6)), dtype=np.float32)
    fill = blur[..., :3] / np.maximum(blur[..., 3:4] / 255.0, 1e-3)
    rgb = np.where(alpha > 0.04, a[..., :3], np.clip(fill, 0, 255))
    img = Image.fromarray(np.uint8(np.concatenate([rgb, a[..., 3:4]], axis=2)), "RGBA")
    data = etcpak.compress_bc3(img.tobytes(), w, h)
    header = b"BLP2" + struct.pack("<IBBBBII", 1, 2, 8, 7, 0, w, h)
    offsets = [4 + 4 + 4 + 8 + 64 + 64 + 1024] + [0] * 15
    sizes = [len(data)] + [0] * 15
    with open(path, "wb") as f:
        f.write(header + struct.pack("<16I", *offsets) + struct.pack("<16I", *sizes) + bytes(1024) + data)
    return w, h


LOOP_BLEND = 3   # last frames eased into the first, so the loop closes without a hitch


def close_loop(frames):
    """The video ends near its first frame but not on it: blend the last few
    frames toward frame 0 (25%, 50%, 75%) so the wrap is as small as any step."""
    out = list(frames)
    n = len(out)
    for k in range(1, LOOP_BLEND + 1):
        out[n - k] = Image.blend(out[n - k], out[0], (LOOP_BLEND + 1 - k) / float(LOOP_BLEND + 1))
    return out


def pack(name, frames, fps, blend=True, crop=True):
    """crop=False: the frames are already her 274 x 350 picture (the local
    tools make them that way), so they are packed as they are."""
    if blend:
        frames = close_loop(frames)
    if crop:
        box, s = crop_box(frames[0])
    else:
        box, s = (0, 0, frames[0].width, frames[0].height), 1.0
    # Cells sit on a 4-pixel grid with a clear 1-pixel border: DXT packs 4 x 4
    # blocks, and a 274-wide stride put every other frame on a different block
    # alignment, so even her still face shimmered between frames. The border
    # keeps filtering from bleeding the neighbor cell in.
    sx, sy = -(-(FRAME_W + 2) // 4) * 4, -(-(FRAME_H + 2) // 4) * 4
    cols = max(1, min(len(frames), 2048 // sx))
    rows = -(-len(frames) // cols)
    sheet = Image.new("RGBA", (cols * sx, rows * sy), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        # crop may reach past the frame edge: pad with transparency first
        pad = Image.new("RGBA", (f.width * 3, f.height * 3), (0, 0, 0, 0))
        pad.paste(f, (f.width, f.height))
        b = tuple(int(round(v + (f.width if j % 2 == 0 else f.height))) for j, v in enumerate(box))
        cell = pad.crop(b).resize((FRAME_W, FRAME_H), Image.LANCZOS)
        sheet.paste(cell, ((i % cols) * sx + 1, (i // cols) * sy + 1))
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, name + "." + TEX_FORMAT)
    for old in (".tga", ".blp"):     # never leave the other format behind
        if os.path.exists(os.path.join(OUT_DIR, name + old)):
            os.remove(os.path.join(OUT_DIR, name + old))
    if TEX_FORMAT == "blp":
        tex_w, tex_h = save_blp(sheet, path)
    else:
        sheet.save(path, format="TGA", compression="tga_rle")
        tex_w, tex_h = sheet.size
    print(f"  pack   {name}: {len(frames)} frames {cols}x{rows}, scale {s:.3f}, "
          f"{tex_w}x{tex_h} {TEX_FORMAT}, {os.path.getsize(path) // 1024} KB")
    return {"frames": len(frames), "cols": cols, "fw": FRAME_W, "fh": FRAME_H,
            "sx": sx, "sy": sy, "texW": tex_w, "texH": tex_h, "fps": fps}


def write_manifest(rec):
    lines = [
        "-- Generated by tools/gen_trixie_anims.py - do not edit by hand.",
        "-- Trixie's animated clips (AutoSprite sheets in Textures/dealer/anim/), read by UI/Trixie.lua.",
        "local BJ = ChairfacesCasino",
        "BJ.TrixieClips = {",
    ]
    for name, mood, _ in CLIPS:
        c = rec["clips"].get(name) or {}
        p = c.get("packed")
        if not p or c.get("dropped"):
            continue
        lines.append(
            '    { name = "%s", mood = "%s", file = "%s", frames = %d, cols = %d, fw = %d, fh = %d, '
            'sx = %d, sy = %d, ox = 1, oy = 1, texW = %d, texH = %d, fps = %d, loop = %s },'
            % (name, mood, name, p["frames"], p["cols"], p["fw"], p["fh"], p["sx"], p["sy"],
               p["texW"], p["texH"], p["fps"], "true" if mood == "wait" else "false"))
    lines.append("}")
    with open(MANIFEST, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    print(f"  wrote {os.path.relpath(MANIFEST, ROOT)} ({len(lines) - 5} clips)")


def repack(rec, name, fps, keep):
    c = rec["clips"][name]
    raw = os.path.join(SRC_DIR, name + ".png")
    info = c.get("sheetInfo") or {}
    frames = cut_frames(Image.open(raw).convert("RGBA"), info)
    local = c.get("jobId") == "local"         # made by a local tool (make_rest_loop.py)
    fps = c.get("fps") or fps
    if keep and keep < len(frames) and not local:   # thin the clip out evenly
        step = len(frames) / float(keep)
        frames = [frames[int(i * step)] for i in range(keep)]
        fps = max(1, round(PLAY_FPS * keep / float(SHEET_FRAMES)))   # same loop length
    c["packed"] = pack(name, frames, fps, blend=not local or c.get("blend", False), crop=not local)


def drop_rejected(rec):
    """Clips cut in the viewer live in ChairfacesCasinoDB.trixieRejected in
    every account's SavedVariables (/reload or log out first, so the file is
    written). Their textures are deleted and they leave UI/TrixieClips.lua;
    the record keeps their jobs marked dropped, so a run never pays for them
    again. Clear the list in game afterwards (or leave it: unknown names are
    ignored)."""
    import glob
    import re
    wtf = os.path.join(ROOT, "..", "..", "..", "WTF", "Account", "*", "SavedVariables", "Chairfaces Casino.lua")
    cut = set()
    for path in glob.glob(wtf):
        text = open(path, encoding="utf-8", errors="replace").read()
        m = re.search(r'\["trixieRejected"\]\s*=\s*\{(.*?)\n\s*\}', text, re.S)
        if m:
            cut |= set(re.findall(r'\["([a-z0-9_]+)"\]\s*=\s*true', m.group(1)))
    if not cut:
        print("nothing cut (mark clips with /cc trix, then /reload so the game saves the list)")
        return
    for n in sorted(cut):
        c = rec["clips"].get(n)
        if not c or c.get("dropped"):
            continue
        for ext in (".blp", ".tga"):
            f = os.path.join(OUT_DIR, n + ext)
            if os.path.exists(f):
                os.remove(f)
        c["dropped"] = True
        print("  dropped", n)
    save_record(rec)
    write_manifest(rec)


# ---------------------------------------------------------------- main

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--go", action="store_true", help="spend credits")
    ap.add_argument("--only", nargs="*", help="clip names")
    ap.add_argument("--redo", nargs="*", default=[], help="clips to pay for again")
    ap.add_argument("--repack", action="store_true", help="re-crop and re-pack downloaded sheets (free)")
    ap.add_argument("--frames", type=int, default=0, help="keep this many frames per clip (default all)")
    ap.add_argument("--drop-rejected", action="store_true",
                    help="delete the clips cut in the in-game viewer (/cc trix)")
    args = ap.parse_args()

    if args.drop_rejected:
        return drop_rejected(load_record())

    names = args.only or [c[0] for c in CLIPS]
    for n in names:
        if n not in CLIP_BY_NAME:
            sys.exit("unknown clip: " + n)
    rec = load_record()
    fps = PLAY_FPS

    if args.repack:
        for n in names:
            if os.path.exists(os.path.join(SRC_DIR, n + ".png")):
                repack(rec, n, fps, args.frames)
        save_record(rec)
        write_manifest(rec)
        return

    if rec.get("characterId"):     # the first try went through upload_character: set it aside
        rec = {"assetId": None, "clips": {}, "characterTest": rec}
    todo = [n for n in names if n in args.redo or not rec["clips"].get(n, {}).get("jobId")]
    waiting = [n for n in names if rec["clips"].get(n, {}).get("jobId") and not rec["clips"][n].get("packed")]
    print(f"asset: {rec.get('assetId') or 'upload trixie_tall (free)'}")
    print(f"new clips: {len(todo)} x {CREDITS_PER_CLIP} = {len(todo) * CREDITS_PER_CLIP} credits: {', '.join(todo) or '-'}")
    print(f"to collect: {', '.join(waiting) or '-'}")
    for n in todo:
        prompt_for(n)
    if not args.go:
        print("plan only; add --go to spend credits")
        return

    api = AutoSprite(open(os.path.expanduser("~/.autosprite_key")).read().strip())

    if not rec.get("assetId"):
        base = Image.open(BASE_ART).convert("RGBA")
        big = base.resize((base.width * 2, base.height * 2), Image.LANCZOS)
        flat = Image.new("RGBA", big.size, (255, 255, 255, 255))   # plain white for the video model
        flat.alpha_composite(big)
        tmp = os.path.join(TOOLS, "_trixie_upload.png")
        flat.convert("RGB").save(tmp)
        key = api.upload(tmp)
        os.remove(tmp)
        made = api.call("create_asset", name="Trixie standing", uploadKey=key,
                        description="Trixie, blood elf casino dealer in a red bunny suit, facing the viewer")
        rec["assetId"] = find(made, "id", "assetId")
        if not rec["assetId"]:
            sys.exit("create_asset gave no id: " + json.dumps(made)[:400])
        save_record(rec)
        print("  asset uploaded:", rec["assetId"])

    for n in todo:
        res = api.call("animate_asset", assetId=rec["assetId"], animationPrompt=prompt_for(n),
                       isLooping=True, videoTier="turbo", frameSize=SHEET_SIZE,
                       maxFrames=SHEET_FRAMES, removeBg="default")
        job = find(res, "jobId")
        if not job:
            print(f"  clip   {n}: no job id: {json.dumps(res)[:300]}")
            continue
        rec["clips"][n] = {"jobId": job, "mood": CLIP_BY_NAME[n][1]}
        save_record(rec)
        print(f"  clip   {n}: queued {job} ({find(res, 'creditCost')} credits)")
        waiting.append(n)

    pending = list(dict.fromkeys(waiting))
    first = True
    while pending:
        time.sleep(10 if first else 35)
        first = False
        for n in list(pending):
            c = rec["clips"][n]
            try:
                st = api.call("get_asset_job_status", jobId=c["jobId"])
            except Exception as e:
                print(f"  clip   {n}: {e}")
                continue
            status = str(find(st, "status") or "").lower()
            if status in ("succeeded", "completed", "done", "complete"):
                url = find(st, "spritesheetUrl", "sheetUrl", "spriteSheetUrl")
                sid = find(st, "spritesheetId")
                info = {}
                if sid:
                    info = api.call("get_asset_spritesheet", spritesheetId=sid)
                    url = url or find(info, "sheetUrl", "spritesheetUrl", "imageUrl", "url")
                # keep the job's ids, never its signed (short-lived) download links
                c["result"] = {k: v for k, v in st.items()
                               if not (isinstance(v, str) and "sig=" in v)}
                if not url:
                    print(f"  clip   {n}: no sheet url in {json.dumps(st)[:800]}")
                    save_record(rec)
                    pending.remove(n)
                    continue
                os.makedirs(SRC_DIR, exist_ok=True)
                download(url).save(os.path.join(SRC_DIR, n + ".png"))
                video = find(st, "videoUrl")
                if video:
                    with urllib.request.urlopen(video, timeout=180) as r:
                        open(os.path.join(SRC_DIR, n + ".mp4"), "wb").write(r.read())
                c["sheetInfo"] = {k: v for k, v in (find(info, "spritesheet") or info or {}).items()
                                  if not isinstance(v, str) or "sig=" not in v}
                repack(rec, n, fps, args.frames)
                save_record(rec)
                pending.remove(n)
            elif status in ("failed", "error", "cancelled"):
                print(f"  clip   {n}: failed {json.dumps(st)[:300]}")
                c["jobId"] = None
                save_record(rec)
                pending.remove(n)
            else:
                print(f"  clip   {n}: {status or json.dumps(st)[:200]}")
    write_manifest(rec)


if __name__ == "__main__":
    main()
