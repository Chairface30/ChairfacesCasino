#!/usr/bin/env python3
"""Re-animate the lobby's Chairface's Casino sign with AutoSprite.

The original sign (Textures/logo_frames.tga, 80 frames of 200 x 113 stacked
and Y-flipped) powers on from dark and then glows, and the whole strip
loops, so the sign blacks out every 5 seconds. The lobby now plays the
original power-on once (frames 1-POWER_ON_FRAMES) and then loops a new
glow clip made here; the original file is left untouched for the classic
setting.

The lit frame is scaled up 3x, padded to a square (so AutoSprite doesn't
stretch the lettering) and animated with animate_asset (turbo, 5 credits,
looping). The sign's band is cropped back out of each frame and packed at
the size the lobby draws it into Textures/logo_glow.tga.

Ids are kept in tools/logo_anim.json; raw sheets in tools/anim_src/.

USAGE
  python tools/gen_logo_anim.py            plan only
  python tools/gen_logo_anim.py --go       make the clip (5 credits)
  python tools/gen_logo_anim.py --repack   re-crop the downloaded sheet (free)
"""
import argparse
import json
import os
import sys
import time

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gen_trixie_anims import AutoSprite, find, download, ROOT, TOOLS, SRC_DIR  # noqa: E402

SRC = os.path.join(ROOT, "Textures", "logo_frames.tga")
OUT = os.path.join(ROOT, "Textures", "logo_glow.tga")
RECORD = os.path.join(TOOLS, "logo_anim.json")
RAW = os.path.join(SRC_DIR, "logo_glow.png")

SRC_W, SRC_H, SRC_FRAMES = 200, 113, 80
LIT_FRAME = 40            # a steady, fully lit frame of the original
UPSCALE = 3
CELL_W, CELL_H = 312, 176  # the lobby draws the sign at this size
FRAMES = 32
SHEET_SIZE = 512
PROMPT = ("Neon casino sign: the marquee bulbs around the border chase in a loop, "
          "the pink and blue neon letters glow and softly flicker. The sign itself does not move; camera still.")


def lit_frame():
    im = Image.open(SRC).convert("RGBA").transpose(Image.FLIP_TOP_BOTTOM)
    return im.crop((0, LIT_FRAME * SRC_H, SRC_W, (LIT_FRAME + 1) * SRC_H))


def square_source():
    """The lit sign scaled up and centered on a near-black square (it hangs
    over the dark lobby, and its middle is see-through); returns the image
    and the sign's box inside it as fractions of the square."""
    sign = lit_frame().resize((SRC_W * UPSCALE, SRC_H * UPSCALE), Image.LANCZOS)
    side = sign.width
    sq = Image.new("RGBA", (side, side), (12, 10, 16, 255))
    top = (side - sign.height) // 2
    sq.alpha_composite(sign, (0, top))
    return sq.convert("RGB"), (0.0, top / side, 1.0, (top + sign.height) / side)


def pack():
    raw = Image.open(RAW).convert("RGBA")
    cols_in = raw.width // SHEET_SIZE
    _, band = square_source()
    # the sign never moves, so every frame wears the original's outline:
    # crisp edges, and the see-through middle stays see-through
    mask = lit_frame().getchannel("A").resize((CELL_W, CELL_H), Image.LANCZOS)
    cols = 2048 // CELL_W
    rows = -(-FRAMES // cols)
    sheet = Image.new("RGBA", (cols * CELL_W, rows * CELL_H), (0, 0, 0, 0))
    for i in range(FRAMES):
        x, y = (i % cols_in) * SHEET_SIZE, (i // cols_in) * SHEET_SIZE
        if y + SHEET_SIZE > raw.height:
            break
        f = raw.crop((x, y, x + SHEET_SIZE, y + SHEET_SIZE))
        b = tuple(round(v * SHEET_SIZE) for v in band)
        lit = f.crop(b).resize((CELL_W, CELL_H), Image.LANCZOS)
        cell = Image.new("RGBA", lit.size, (12, 10, 16, 255))
        cell.alpha_composite(lit)
        cell.putalpha(mask)
        sheet.paste(cell, ((i % cols) * CELL_W, (i // cols) * CELL_H))
    sheet.save(OUT, format="TGA", compression="tga_rle")
    print(f"  pack logo_glow: {FRAMES} frames {cols}x{rows}, {sheet.width}x{sheet.height}, "
          f"{os.path.getsize(OUT) // 1024} KB")
    print(f"  Lobby: LOGO_GLOW = {{ frames = {FRAMES}, cols = {cols}, fw = {CELL_W}, fh = {CELL_H}, "
          f"texW = {sheet.width}, texH = {sheet.height} }}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--go", action="store_true")
    ap.add_argument("--repack", action="store_true")
    args = ap.parse_args()
    if args.repack:
        return pack()
    rec = json.load(open(RECORD, encoding="utf-8")) if os.path.exists(RECORD) else {}
    print(f"asset: {rec.get('assetId') or 'upload the lit sign (free)'}; clip: "
          f"{'collect ' + rec['jobId'] if rec.get('jobId') else '5 credits'}")
    if not args.go:
        print("plan only; add --go to spend credits")
        return
    api = AutoSprite(open(os.path.expanduser("~/.autosprite_key")).read().strip())
    if not rec.get("assetId"):
        img, _ = square_source()
        tmp = os.path.join(TOOLS, "_logo_upload.png")
        img.save(tmp)
        key = api.upload(tmp)
        os.remove(tmp)
        made = api.call("create_asset", name="Chairface's Casino sign", uploadKey=key,
                        description="Neon casino marquee sign reading Chairface's Casino")
        rec["assetId"] = find(made, "id", "assetId")
        json.dump(rec, open(RECORD, "w", encoding="utf-8"), indent=1)
        print("  asset:", rec["assetId"])
    if not rec.get("jobId"):
        res = api.call("animate_asset", assetId=rec["assetId"], animationPrompt=PROMPT[:200],
                       isLooping=True, videoTier="turbo", frameSize=SHEET_SIZE,
                       maxFrames=FRAMES, removeBg="default")
        rec["jobId"] = find(res, "jobId")
        json.dump(rec, open(RECORD, "w", encoding="utf-8"), indent=1)
        print(f"  queued {rec['jobId']} ({find(res, 'creditCost')} credits)")
    while True:
        time.sleep(35)
        st = api.call("get_asset_job_status", jobId=rec["jobId"])
        status = str(find(st, "status") or "").lower()
        print("  status:", status)
        if status == "succeeded":
            os.makedirs(SRC_DIR, exist_ok=True)
            download(find(st, "spritesheetUrl")).save(RAW)
            pack()
            return
        if status in ("failed", "error", "cancelled"):
            print(json.dumps(st)[:500])
            rec["jobId"] = None
            json.dump(rec, open(RECORD, "w", encoding="utf-8"), indent=1)
            return


if __name__ == "__main__":
    main()
