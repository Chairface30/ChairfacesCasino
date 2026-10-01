"""Generate Textures/Pachinko/*.tga for Gnomish Pachinko.

peg.tga / ball.tga are white shaded discs the window tints with
SetVertexColor (blue/orange/green pegs, a silver ball), ring.tga is the
soft glow a lit peg wears, dot.tga is one aim-guide dot, bucket.tga is the
free-ball cup, icon.tga is the lobby button's icon. All power-of-two,
32-bit uncompressed TGA.

Run: python tools/make_pachinko_textures.py   (pip install pillow)
"""
import math
import os

from PIL import Image, ImageDraw

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Textures", "Pachinko")
os.makedirs(OUT, exist_ok=True)

SS = 4  # supersample factor for clean edges


def shaded_disc(size, highlight=(0.35, 0.35), edge_dark=0.55, spec=0.0):
    """White disc, lit from the top-left, alpha-antialiased edge."""
    big = size * SS
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    px = img.load()
    c = big / 2
    r = big / 2 - SS
    hx, hy = big * highlight[0], big * highlight[1]
    for y in range(big):
        for x in range(big):
            d = math.hypot(x + 0.5 - c, y + 0.5 - c)
            if d > r + 1:
                continue
            a = max(0.0, min(1.0, r + 1 - d))
            # radial shade: bright toward the highlight, darker at the far edge
            hd = math.hypot(x + 0.5 - hx, y + 0.5 - hy) / (big * 0.9)
            v = 1.0 - (1.0 - edge_dark) * min(1.0, hd ** 1.1)
            if spec > 0:
                s = max(0.0, 1.0 - math.hypot(x + 0.5 - hx, y + 0.5 - hy) / (big * 0.16))
                v = min(1.0, v + spec * s * s)
            g = int(round(255 * v))
            px[x, y] = (g, g, g, int(round(255 * a)))
    return img.resize((size, size), Image.LANCZOS)


def glow_ring(size, radius=0.70, width=0.16):
    big = size * SS
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    px = img.load()
    c = big / 2
    for y in range(big):
        for x in range(big):
            d = math.hypot(x + 0.5 - c, y + 0.5 - c) / (big / 2)
            a = math.exp(-((d - radius) ** 2) / (2 * width * width))
            # fade the inside a touch less than the outside so it reads as a halo
            if d > 0.98:
                a *= max(0.0, (1.0 - d) / 0.02)
            px[x, y] = (255, 255, 255, int(round(255 * min(1.0, a))))
    return img.resize((size, size), Image.LANCZOS)


def soft_dot(size):
    big = size * SS
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    px = img.load()
    c = big / 2
    for y in range(big):
        for x in range(big):
            d = math.hypot(x + 0.5 - c, y + 0.5 - c) / (big / 2)
            a = 1.0 if d < 0.55 else max(0.0, 1.0 - (d - 0.55) / 0.35)
            px[x, y] = (255, 255, 255, int(round(255 * a)))
    return img.resize((size, size), Image.LANCZOS)


def bucket(w, h):
    """An open cup: dark steel body, lighter rims, transparent above."""
    big_w, big_h = w * SS, h * SS
    img = Image.new("RGBA", (big_w, big_h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    top = int(big_h * 0.18)
    inset = int(big_w * 0.06)
    body = (70, 86, 110, 255)
    inner = (38, 46, 60, 255)
    rim = (190, 205, 230, 255)
    # body trapezoid
    d.polygon([(0, top), (big_w - 1, top), (big_w - 1 - inset, big_h - 1), (inset, big_h - 1)], fill=body)
    # hollow
    hol = int(big_w * 0.07)
    d.polygon([(hol, top), (big_w - 1 - hol, top), (big_w - 1 - inset - hol // 2, big_h - 1 - SS * 3),
               (inset + hol // 2, big_h - 1 - SS * 3)], fill=inner)
    # rims (lips) on both sides
    lip_w = int(big_w * 0.08)
    d.rectangle([0, 0, lip_w, top + SS * 2], fill=rim)
    d.rectangle([big_w - 1 - lip_w, 0, big_w - 1, top + SS * 2], fill=rim)
    d.rectangle([0, top, big_w - 1, top + SS], fill=rim)
    return img.resize((w, h), Image.LANCZOS)


def tint(img, rgb):
    r, g, b = rgb
    out = img.copy()
    px = out.load()
    for y in range(out.height):
        for x in range(out.width):
            v, _, _, a = px[x, y]
            px[x, y] = (int(v * r), int(v * g), int(v * b), a)
    return out


def icon():
    """Lobby icon: an orange peg, a blue peg and the silver ball."""
    img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    peg = shaded_disc(34, spec=0.25)
    img.alpha_composite(tint(peg, (1.0, 0.55, 0.12)), (26, 26))
    img.alpha_composite(tint(peg, (0.3, 0.6, 1.0)), (2, 30))
    ball = shaded_disc(24, spec=0.6)
    img.alpha_composite(tint(ball, (0.9, 0.92, 0.98)), (14, 2))
    return img


def save(img, name):
    path = os.path.join(OUT, name)
    img.save(path, format="TGA")
    print("wrote", path, img.size)


if __name__ == "__main__":
    save(shaded_disc(64, spec=0.3), "peg.tga")
    save(shaded_disc(64, highlight=(0.32, 0.30), edge_dark=0.45, spec=0.75), "ball.tga")
    save(glow_ring(64), "ring.tga")
    save(soft_dot(32), "dot.tga")
    save(bucket(128, 32), "bucket.tga")
    save(icon(), "icon.tga")
