"""Generate Textures/mountains.tga - the Crash window's mountain range.

    python tools/make_mountains.py [--seed 7]

A horizontally TILEABLE strip (left and right edges join seamlessly) of
craggy, snowcapped peaks: two silhouette ranges (a hazier back range
peeking between the peaks of a darker front range), sharp linear ridges,
jagged snow caps above a wavering snowline. 788x200 so the strip is as
wide as the Crash sky's wrap band and the peaks stand ~3/4 of the sky's
height, clearing the tree line.

Deterministic for a given seed - rerun any time, then /reload (full
client restart if mountains.tga is brand new).
"""

import argparse
import os
import random

from PIL import Image

W, H = 788, 200

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   "Textures", "Crash", "mountains.tga")


def build_ridge(rng, lo_peak, hi_peak, lo_valley, hi_valley):
    """Height per column: sharp linear runs between alternating peak and
    valley anchors, wrapping so column W-1 meets column 0."""
    anchors = [(0, rng.randint(lo_valley, hi_valley))]
    x = 0
    peak = True
    while x < W:
        x += rng.randint(28, 78)
        if peak:
            h = rng.randint(lo_peak, hi_peak)
            # occasional split summit for extra crag
            if rng.random() < 0.35 and x + 22 < W:
                anchors.append((min(x, W), h))
                x += rng.randint(10, 22)
                h = h - rng.randint(12, 30)
        else:
            h = rng.randint(lo_valley, hi_valley)
        anchors.append((min(x, W), h))
        peak = not peak
    anchors[-1] = (W, anchors[0][1])   # tileable: wrap to the first height

    ridge = [0] * W
    for (x0, h0), (x1, h1) in zip(anchors, anchors[1:]):
        for x in range(x0, min(x1, W)):
            t = (x - x0) / max(1, x1 - x0)
            ridge[x] = h0 + (h1 - h0) * t
    return ridge


def paint_range(px, ridge, rock, snow, snowline, rng):
    """Fill columns below the ridge with rock (slightly darker toward the
    base) and cap everything above a jagged snowline with snow."""
    snow_edge = [snowline + rng.randint(-9, 9) for _ in range(W)]
    # smooth the snow edge a touch so it reads as a line, not static
    for x in range(1, W):
        snow_edge[x] = (snow_edge[x] + snow_edge[x - 1]) / 2
    for x in range(W):
        top = int(ridge[x])
        for y in range(top):
            shade = 1.0 - 0.25 * (1 - y / H)   # darker toward the ground
            c = snow if y > snow_edge[x] else rock
            px[x, H - 1 - y] = (int(c[0] * shade), int(c[1] * shade),
                                int(c[2] * shade), 255)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", type=int, default=7)
    args = ap.parse_args()
    rng = random.Random(args.seed)

    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    px = img.load()

    # hazy back range: taller, bluer, peeks out between the front peaks
    back = build_ridge(rng, 150, 198, 70, 105)
    paint_range(px, back, rock=(74, 84, 118), snow=(168, 178, 200),
                snowline=128, rng=rng)

    # front range: darker, sharper, a little lower
    front = build_ridge(rng, 110, 165, 30, 70)
    paint_range(px, front, rock=(40, 46, 70), snow=(210, 218, 234),
                snowline=98, rng=rng)

    img.save(OUT, compression="tga_rle")
    print("Wrote %s (%dx%d, seed %d)" % (OUT, W, H, args.seed))
    img.save(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                          "mountains_preview.png"))


if __name__ == "__main__":
    main()
