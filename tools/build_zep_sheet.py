"""Stack rendered zeppelin frames into the Textures/zeppelin.tga sprite sheet.

    python tools/build_zep_sheet.py <frames_dir> [--fps 20] [--flip-x]

Takes the PNGs rendered by tools/zep_render.py (any alphabetically-ordered
set of RGBA images works), crops them to their common content box, scales
into WIDTHxHEIGHT sprite frames, stacks them vertically (frame 0 at the
top -- the order CrashFrame.lua's AnimateSkin steps through), and writes a
32-bit RLE TGA.

The client only picks up NEW texture files on a full restart -- /reload is
not enough the first time zeppelin.tga appears.

Preview in-game:   /cc zep skin <frames> <fps>
Ship it:           ZEP_SKIN_ENABLED/FRAMES/FPS at the top of UI/CrashFrame.lua
"""

import argparse
import os
import sys

try:
    from PIL import Image
except ImportError:
    sys.exit(
        "Pillow not available in this Python (%s).\n"
        "This script runs in a NORMAL terminal, not inside Blender -- only "
        "zep_render.py runs in Blender.\nIn PowerShell:  python \"%s\" ...\n"
        "If Pillow is genuinely missing there:  python -m pip install pillow"
        % (sys.executable, os.path.abspath(__file__)))

ADDON_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def parse_args():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("frames_dir", nargs="?",
                   default=os.path.join(ADDON_DIR, "tools", "zep_frames"),
                   help="directory of rendered PNG frames (sorted by name)")
    p.add_argument("--out",
                   default=os.path.join(ADDON_DIR, "Textures", "Crash", "zeppelin.tga"))
    p.add_argument("--width", type=int, default=256,
                   help="sprite frame width (ship frame is 110x64; 256x128 = 2x+)")
    p.add_argument("--height", type=int, default=128)
    p.add_argument("--fps", type=float, default=15,
                   help="playback fps to print (zep_render.py prints the "
                        "value that matches the animation's real prop speed)")
    p.add_argument("--flip-x", action="store_true",
                   help="mirror horizontally (use when the render came out "
                        "nose-left; she must fly nose-RIGHT)")
    p.add_argument("--flip-y", action="store_true",
                   help="mirror vertically (only if the in-game preview is "
                        "upside down)")
    p.add_argument("--no-trim", action="store_true",
                   help="skip cropping to the union content box")
    return p.parse_args()


def load_frames(frames_dir):
    names = sorted(f for f in os.listdir(frames_dir)
                   if f.lower().endswith((".png", ".tga")))
    if not names:
        sys.exit("No .png frames in %s" % frames_dir)
    frames = [Image.open(os.path.join(frames_dir, n)).convert("RGBA")
              for n in names]
    sizes = {im.size for im in frames}
    if len(sizes) > 1:
        sys.exit("Frames have mixed sizes: %s" % sizes)
    print("Loaded %d frames (%dx%d) from %s"
          % (len(frames), frames[0].width, frames[0].height, frames_dir))
    return frames


def union_bbox(frames):
    """Smallest box containing every frame's non-transparent pixels, so the
    whole prop sweep stays in frame and nothing wobbles between frames."""
    box = None
    for im in frames:
        b = im.getchannel("A").getbbox()
        if b is None:
            continue
        box = b if box is None else (min(box[0], b[0]), min(box[1], b[1]),
                                     max(box[2], b[2]), max(box[3], b[3]))
    return box


def fit_frame(im, w, h):
    """Scale to fit inside w x h keeping aspect, centered on transparency."""
    scale = min(w / im.width, h / im.height)
    nw, nh = max(1, round(im.width * scale)), max(1, round(im.height * scale))
    im = im.resize((nw, nh), Image.LANCZOS)
    canvas = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    canvas.paste(im, ((w - nw) // 2, (h - nh) // 2))
    return canvas


def main():
    args = parse_args()
    frames = load_frames(args.frames_dir)

    if not args.no_trim:
        box = union_bbox(frames)
        if box:
            frames = [im.crop(box) for im in frames]
            print("Trimmed to union content box %s -> %dx%d"
                  % (box, frames[0].width, frames[0].height))

    if args.flip_x:
        frames = [im.transpose(Image.FLIP_LEFT_RIGHT) for im in frames]
        print("Mirrored horizontally (nose now on the other side)")
    if args.flip_y:
        frames = [im.transpose(Image.FLIP_TOP_BOTTOM) for im in frames]

    frames = [fit_frame(im, args.width, args.height) for im in frames]

    n = len(frames)
    sheet = Image.new("RGBA", (args.width, args.height * n), (0, 0, 0, 0))
    for i, im in enumerate(frames):
        sheet.paste(im, (0, i * args.height))

    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    sheet.save(args.out, compression="tga_rle")
    kb = os.path.getsize(args.out) / 1024
    print("\nWrote %s  (%dx%d, %d frames, %.0f KB RLE)"
          % (args.out, sheet.width, sheet.height, n, kb))
    print("Restart the client fully if zeppelin.tga is new, then preview:")
    print("    /cc zep skin %d %g" % (n, args.fps))
    print("Ship it in UI/CrashFrame.lua:")
    print("    ZEP_SKIN_ENABLED = true, ZEP_SKIN_FRAMES = %d, ZEP_SKIN_FPS = %g"
          % (n, args.fps))


if __name__ == "__main__":
    main()
