#!/usr/bin/env python3
"""Trixie's resting loops, made locally from her standing pose.

idle_rest   only breathing: no blink, no nod. Plays most of the time.
idle_rest2  the same breathing with a slight head sway and one blink.
            Plays second most.

The video model blinks and tilts her head however it is asked, so these are
gentle warps of her standing picture (as the video clips draw her, see
video_base): over a slow breath her chest and shoulders lift a couple of
pixels and widen a touch, fading to nothing at the neck and the hips. The
loops are exact (cosines), so they repeat seamlessly. idle_rest2's head sway
is a small tilt around her neck, and its blink is her own blink from
idle_breathe: the eyes alone, lined up on her face and color matched, laid
over the resting face for a few frames.

The frames are saved as tools/anim_src/<name>.png (a 274 x 350 grid) and
packed by gen_trixie_anims.py like any other clip, so --repack keeps them.

Run: python tools/make_rest_loop.py            both loops
     python tools/make_rest_loop.py idle_rest2 one of them
"""
import math
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_trixie_anims as g  # noqa: E402

FRAMES = 35          # 7 x 5 cells: the most that fit a 2048 texture
FPS = 10             # 3.5 s a breath, an easy resting pace
LIFT = 2.2           # pixels the chest rises at the top of a breath
WIDEN = 0.010        # how much wider the chest gets (1%)
# the warp runs from the neck (no movement) through the chest (full) to the
# hips (none again), in rows of the 274 x 350 picture
NECK, CHEST, HIPS = 105, 175, 265

# idle_rest2's extras
TILT = 0.7           # degrees her head sways each way over the loop
PIVOT = (137.0, 118.0)   # where the head turns: the base of her neck
HEAD_TOP, HEAD_FADE = 95, 125   # full sway above HEAD_TOP, none below HEAD_FADE
BLINK_SRC = "idle_breathe"
BLINK_FRAMES = [9, 11, 13, 20]  # half shut, shut, shut, half open (in BLINK_SRC)
BLINK_AT = 14                   # rest2 frame where the blink starts
# one small soft oval per eye (center x, y, radii), just the eye and lashes:
# a wider patch dragged her brows and the hair strand across her forehead
# in from the blink clip, where her head is turned a little
EYES = [(122.0, 82.0, 15.0, 8.5), (150.0, 77.0, 15.0, 8.5)]
LOOPS = {
    "idle_rest": {"tilt": 0.0, "blink": False},
    "idle_rest2": {"tilt": TILT, "blink": True},
}


def weight(y):
    """0 above the neck and below the hips, 1 at the chest, smooth between."""
    w = np.zeros_like(y, dtype=np.float32)
    up = (y > NECK) & (y <= CHEST)
    down = (y > CHEST) & (y < HIPS)
    w[up] = 0.5 - 0.5 * np.cos(np.pi * (y[up] - NECK) / (CHEST - NECK))
    w[down] = 0.5 + 0.5 * np.cos(np.pi * (y[down] - CHEST) / (HIPS - CHEST))
    return w


def head_weight(y):
    """1 for the head, fading to 0 down the neck."""
    w = np.ones_like(y, dtype=np.float32)
    fade = (y > HEAD_TOP) & (y < HEAD_FADE)
    w[fade] = 0.5 + 0.5 * np.cos(np.pi * (y[fade] - HEAD_TOP) / (HEAD_FADE - HEAD_TOP))
    w[y >= HEAD_FADE] = 0
    return w


def sample(img, xs, ys):
    """Bilinear lookup of img (H x W x 4, premultiplied) at float coords."""
    h, w = img.shape[:2]
    x0 = np.clip(np.floor(xs).astype(int), 0, w - 1)
    y0 = np.clip(np.floor(ys).astype(int), 0, h - 1)
    x1, y1 = np.clip(x0 + 1, 0, w - 1), np.clip(y0 + 1, 0, h - 1)
    fx, fy = (xs - x0)[..., None], (ys - y0)[..., None]
    top = img[y0, x0] * (1 - fx) + img[y0, x1] * fx
    bot = img[y1, x0] * (1 - fx) + img[y1, x1] * fx
    return top * (1 - fy) + bot * fy


def clip_cells(name, c):
    """A clip's raw (uncompressed) frames, cropped exactly the way pack()
    crops them: the packed textures are already through DXT, which darkens
    her a little, and these loops are compressed again on top."""
    raw = os.path.join(g.SRC_DIR, name + ".png")
    frames = g.cut_frames(Image.open(raw).convert("RGBA"), c.get("sheetInfo") or {})
    (l, t, r, b), _ = g.crop_box(frames[0])
    out = []
    for f in frames:
        pad = Image.new("RGBA", (f.width * 3, f.height * 3), (0, 0, 0, 0))
        pad.paste(f, (f.width, f.height))
        out.append(pad.crop((round(l + f.width), round(t + f.height),
                             round(r + f.width), round(b + f.height))).resize((g.FRAME_W, g.FRAME_H), Image.LANCZOS))
    return out


def video_base(rec):
    """Her standing pose as the video clips draw her. The video model
    re-renders her a little darker and redder and about 3% wider than the
    original still, and every clip starts on that same picture, so the rest
    loops must use it too or they stand out. The pixel median of all the
    clips' first frames is that picture with the compression noise averaged
    away."""
    stack = []
    for name, c in rec["clips"].items():
        raw = os.path.join(g.SRC_DIR, name + ".png")
        if c.get("dropped") or c.get("jobId") == "local" or not os.path.exists(raw):
            continue
        stack.append(np.asarray(clip_cells(name, c)[0], dtype=np.float32))
    if not stack:
        sys.exit("no clips to take her standing pose from")
    st = np.stack(stack)
    med = np.median(st, axis=0)
    # the median leans a little dark: match the clips' average color exactly
    solid = med[..., 3] > 200
    want = st[:, solid, :3].mean(axis=(0, 1))
    have = med[solid, :3].mean(axis=0)
    med[..., :3] = np.clip(med[..., :3] * (want / have), 0, 255)
    print(f"  base: median of {len(stack)} clips' first frames, color matched")
    return med


def eye_mask(h, w, eye):
    """A soft oval over one eye: 1 inside, fading to 0 over a few pixels."""
    cx, cy, rx, ry = eye
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    d = np.sqrt(((xs - cx) / rx) ** 2 + ((ys - cy) / ry) ** 2)
    return np.clip((1.2 - d) / 0.4, 0, 1)[..., None]


def blink_faces(rec, base):
    """The resting face with her eyes swapped for each blink frame. Each eye
    is lined up on its own (the blink clip's head is turned slightly, so the
    two eyes shift differently) using the skin around it, and color matched
    to that skin."""
    cells = [np.asarray(f, dtype=np.float32) for f in clip_cells(BLINK_SRC, rec["clips"][BLINK_SRC])]
    h, w = base.shape[:2]
    faces = []
    for k in BLINK_FRAMES:
        a = cells[k]
        face = base.copy()
        for eye in EYES:
            cx, cy, rx, ry = eye
            mask = eye_mask(h, w, eye)
            # alignment ring: lids and skin just outside the eye
            ring_mask = eye_mask(h, w, (cx, cy, rx * 1.6, ry * 1.8))[..., 0]
            ring = (ring_mask > 0.5) & (mask[..., 0] < 0.05)
            y0, y1 = int(cy - ry * 2.2), int(cy + ry * 2.2)
            x0, x1 = int(cx - rx * 2.0), int(cx + rx * 2.0)
            best = None
            for dy in range(-6, 7):
                for dx in range(-6, 7):
                    moved = a[y0 + dy:y1 + dy, x0 + dx:x1 + dx, :3]
                    err = np.abs(moved - base[y0:y1, x0:x1, :3])[ring[y0:y1, x0:x1]].mean()
                    if best is None or err < best[0]:
                        best = (err, dx, dy)
            _, dx, dy = best
            moved = np.roll(np.roll(a, -dy, axis=0), -dx, axis=1)
            gain = base[ring, :3].mean(axis=0) / np.maximum(moved[ring, :3].mean(axis=0), 1)
            moved[..., :3] = np.clip(moved[..., :3] * gain, 0, 255)
            face[..., :3] = face[..., :3] * (1 - mask) + moved[..., :3] * mask
        faces.append(face)
    return faces


def build(name, rec, base):
    opts = LOOPS[name]
    h, w = base.shape[:2]
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    cx = w / 2.0
    wy = weight(ys)
    hy = head_weight(ys)
    blinks = blink_faces(rec, base) if opts["blink"] else []

    def premult(a):
        p = a.copy()
        p[..., :3] *= a[..., 3:4] / 255.0       # premultiply: clean edges when resampled
        return p

    pre_base = premult(base)
    pre_blinks = [premult(f) for f in blinks]
    frames = []
    for i in range(FRAMES):
        b = 0.5 - 0.5 * math.cos(2 * math.pi * i / FRAMES)    # 0 -> 1 -> 0, exact loop
        src_y = ys + LIFT * b * wy                             # chest moves up
        src_x = cx + (xs - cx) / (1 + WIDEN * b * wy)          # and a touch wider
        if opts["tilt"]:
            # her head sways side to side once a loop, turning at her neck
            ang = math.radians(opts["tilt"]) * math.sin(2 * math.pi * i / FRAMES) * hy
            px, py = PIVOT
            c, s = np.cos(-ang), np.sin(-ang)
            # added on top of the breathing, so the two meet smoothly at the neck
            src_x = src_x + (px + (xs - px) * c - (ys - py) * s) - xs
            src_y = src_y + (py + (xs - px) * s + (ys - py) * c) - ys
        img = pre_base
        if pre_blinks and BLINK_AT <= i < BLINK_AT + len(pre_blinks):
            img = pre_blinks[i - BLINK_AT]
        out = sample(img, src_x, src_y)
        alpha = out[..., 3:4]
        rgb = np.where(alpha > 0, out[..., :3] * 255.0 / np.maximum(alpha, 1e-3), 0)
        frames.append(Image.fromarray(np.uint8(np.clip(np.concatenate([rgb, alpha], 2), 0, 255)), "RGBA"))

    cols = 7
    rows = -(-FRAMES // cols)
    sheet = Image.new("RGBA", (cols * w, rows * h), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        sheet.paste(f, ((i % cols) * w, (i // cols) * h))
    os.makedirs(g.SRC_DIR, exist_ok=True)
    sheet.save(os.path.join(g.SRC_DIR, name + ".png"))

    c = rec["clips"].setdefault(name, {})
    c.update({"jobId": "local", "mood": "wait", "fps": FPS,
              "sheetInfo": {"frameCount": FRAMES, "frameWidth": w, "frameHeight": h, "columns": cols}})
    c["packed"] = g.pack(name, frames, FPS, blend=False, crop=False)   # a cosine loop is exact already


def main():
    names = sys.argv[1:] or list(LOOPS)
    rec = g.load_record()
    base = video_base(rec)
    for name in names:
        build(name, rec, base)
    g.save_record(rec)
    g.write_manifest(rec)


if __name__ == "__main__":
    main()
