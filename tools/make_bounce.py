#!/usr/bin/env python3
"""Trixie's win_bounce: an animated bunny hop with a physics-driven bounce.

The hop itself is AutoSprite video (tools/anim_src/win_bounce_src.png, a
copy of the win_bounce clip gen_trixie_anims.py made): her knees bend, her
hands come up like bunny paws, she grins. The video model keeps her low (a
real jump sent her head out of the frame), so on top of it she gets a real
jump arc: right where the video comes up out of its crouch she launches,
flies and lands.

Her chest rides a damped spring on each side, driven by her total motion
(the video's own bob plus the jump): it lags downward as she launches,
floats up at the top and as she falls, heaves down when she lands, then
jiggles to rest. The spring follows her chest wherever the video moves it.
Her picture is cut off at the thighs, so while she is up that edge fades
instead of showing as a hard line.

Run: python tools/make_bounce.py
     (a new hop video: gen_trixie_anims.py --go --only win_bounce --redo
     win_bounce, copy tools/anim_src/win_bounce.png to win_bounce_src.png,
     then run this)
"""
import math
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_trixie_anims as g  # noqa: E402
import make_rest_loop as rest  # noqa: E402

NAME = "win_bounce"
SRC = "win_bounce_src"   # the AutoSprite hop video's raw sheet (32 frames of 512)
FPS = 16                 # the video's 32 frames over its 2 seconds
HOP_HEIGHT = 16.0        # pixels the jump adds at its top
AIR_FRAMES = 8           # frames in the air (half a second)
TRIM = 8                 # the video's first frames are her just standing: skip them
TOTAL = 35               # 7 x 5 cells: after the video, she holds still while the jiggle settles
FADE = 26                # pixels of the cut edge at her thighs faded out while she is up
TORSO = (95, 100, 180, 150)   # collar and bow tie: what the tracker follows
# chest: centers, radii (pixels in her standing picture) and spring per side
CHEST = [
    {"cx": 117.0, "cy": 197.0, "rx": 30.0, "ry": 28.0, "hz": 3.4, "damp": 0.16},
    {"cx": 170.0, "cy": 197.0, "rx": 30.0, "ry": 28.0, "hz": 3.7, "damp": 0.17},
]
CHEST_AMP = 10.0         # pixels of the biggest chest swing (the spring is scaled to it)
SIM_DT = 1.0 / 1200


def track(frames):
    """How far her torso has moved in each frame from the first (dx, dy;
    +dy is down), by matching her collar and bow tie."""
    a0 = np.asarray(frames[0], dtype=np.float32)
    x0, y0, x1, y1 = TORSO
    ref = a0[y0:y1, x0:x1, :3]
    out = []
    for f in frames:
        a = np.asarray(f, dtype=np.float32)
        best = min((np.abs(a[y0 + dy:y1 + dy, x0 + dx:x1 + dx, :3] - ref).mean(), dx, dy)
                   for dy in range(-30, 21) for dx in range(-12, 13)
                   if y0 + dy >= 0 and y1 + dy <= a.shape[0])
        out.append((best[1], best[2]))
    dx = np.array([o[0] for o in out], dtype=np.float64)
    dy = np.array([o[1] for o in out], dtype=np.float64)
    k = np.array([1, 2, 3, 2, 1], dtype=np.float64)
    k /= k.sum()

    def smooth(v):
        return np.convolve(np.pad(v, 2, mode="edge"), k, mode="valid")
    return smooth(dx), smooth(dy)


def jump(dy):
    """The added jump, per frame (pixels up): it launches where the video is
    lowest in its crouch."""
    n = len(dy)
    start = int(np.argmax(dy[: n - AIR_FRAMES - 1]))
    lift = np.zeros(n)
    for i in range(start, min(n, start + AIR_FRAMES + 1)):
        u = (i - start) / float(AIR_FRAMES)
        lift[i] = HOP_HEIGHT * 4 * u * (1 - u)
    return lift


def springs(height):
    """Each chest side's offset per frame (pixels, up is +) from the body's
    height per frame (up is +)."""
    n = len(height)
    t = np.arange(n) / float(FPS)
    ts = np.arange(0, t[-1], SIM_DT)
    yb = np.interp(ts, t, height)
    k = np.exp(-0.5 * (np.arange(-30, 31) / 12.0) ** 2)
    yb = np.convolve(np.pad(yb, 30, mode="edge"), k / k.sum(), mode="valid")
    acc = np.gradient(np.gradient(yb, SIM_DT), SIM_DT)
    sides = []
    for side in CHEST:
        w0 = 2 * math.pi * side["hz"]
        u, v = 0.0, 0.0
        us = np.zeros(len(ts))
        for i in range(len(ts)):
            a = -w0 * w0 * u - 2 * side["damp"] * w0 * v - acc[i]
            v += a * SIM_DT
            u += v * SIM_DT
            us[i] = u
        sides.append(us)
    peak = max(np.abs(u).max() for u in sides)
    tail = np.clip((ts[-1] - ts) / 0.3, 0, 1)      # land exactly on rest at the end
    return [np.interp(t, ts, u * CHEST_AMP / peak * tail) for u in sides]


def main():
    rec = g.load_record()
    video = rest.clip_cells(SRC, {"sheetInfo": {}})      # the video's own 512 layout
    frames = video[TRIM:]
    frames = frames + [frames[-1]] * (TOTAL - len(frames))   # land, then settle
    dx, dy = track(frames)
    lift = jump(dy)
    height = -dy + lift                      # her total height, up is +
    chest = springs(height)
    out_frames = []
    for i, f in enumerate(frames):
        a = np.asarray(f, dtype=np.float32)
        h, w = a.shape[:2]
        pre = a.copy()
        pre[..., :3] *= a[..., 3:4] / 255.0
        ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
        video_y = ys + lift[i]               # the jump: each screen row shows the video row below
        src_y = video_y.copy()
        for side, u in zip(CHEST, chest):
            blob = np.exp(-0.5 * (((xs - side["cx"] - dx[i]) / side["rx"]) ** 2
                                  + ((video_y - side["cy"] - dy[i]) / side["ry"]) ** 2))
            src_y = src_y + u[i] * blob
        out = rest.sample(pre, xs, src_y)
        out[(src_y < 0) | (src_y > h - 1)] = 0
        if lift[i] > 0:
            edge = np.clip((h - 1 - src_y) / FADE, 0, 1)
            out *= (1 - min(1.0, lift[i] / 4.0) * (1 - edge))[..., None]
        alpha = out[..., 3:4]
        rgb = np.where(alpha > 0, out[..., :3] * 255.0 / np.maximum(alpha, 1e-3), 0)
        out_frames.append(Image.fromarray(np.uint8(np.clip(np.concatenate([rgb, alpha], 2), 0, 255)), "RGBA"))
    print("  video bob (down +):", " ".join("%.0f" % v for v in dy))
    print("  added jump (up +): ", " ".join("%.0f" % v for v in lift))
    print("  chest (up +):      ", " ".join("%.0f" % v for v in chest[0]))

    cols = 7
    w, h = out_frames[0].size
    rows = -(-len(out_frames) // cols)
    sheet = Image.new("RGBA", (cols * w, rows * h), (0, 0, 0, 0))
    for i, f in enumerate(out_frames):
        sheet.paste(f, ((i % cols) * w, (i // cols) * h))
    sheet.save(os.path.join(g.SRC_DIR, NAME + ".png"))   # what --repack packs
    c = rec["clips"].setdefault(NAME, {})
    c.update({"jobId": "local", "mood": "win", "fps": FPS, "blend": True,
              "sheetInfo": {"frameCount": len(out_frames), "frameWidth": w, "frameHeight": h, "columns": cols}})
    c["packed"] = g.pack(NAME, out_frames, FPS, blend=True, crop=False)
    g.save_record(rec)
    g.write_manifest(rec)


if __name__ == "__main__":
    main()
