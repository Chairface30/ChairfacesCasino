#!/usr/bin/env python3
"""Re-encode Trixie voice clips from .mp3 to smaller Ogg Vorbis, in place.

The generator writes ElevenLabs .mp3 at 128 kbps / 44.1 kHz mono - overkill
for short voice barks. This transcodes each to Ogg Vorbis (WoW plays .ogg, and
the addon prefers .ogg over .mp3), then deletes the redundant .mp3. Safe and
resumable: converts to a .tmp, verifies non-empty, then swaps and deletes the
mp3 only on success. If a hand-recorded .ogg already exists for a clip, the mp3
is just dropped (the existing .ogg wins).

Needs ffmpeg (with libvorbis). Point at it via FFMPEG env or --ffmpeg, else PATH.

  FFMPEG=/path/to/ffmpeg.exe python tools/compress_voices.py            # ~64 kbps (-q:a 1)
  python tools/compress_voices.py --quality 0                            # ~48 kbps, smaller
  python tools/compress_voices.py --quality 1 --rate 22050               # + downsample
  python tools/compress_voices.py --dir ../Sounds/Arcade                 # a different folder
  python tools/compress_voices.py --dry-run
"""
import argparse, glob, os, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_DIR = os.path.join(os.path.dirname(HERE), "Sounds", "Trixie")


def sizes(d):
    mp3 = glob.glob(os.path.join(d, "*.mp3"))
    ogg = glob.glob(os.path.join(d, "*.ogg"))
    tot = sum(os.path.getsize(f) for f in mp3 + ogg)
    return len(mp3), len(ogg), tot


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ffmpeg", default=os.environ.get("FFMPEG", "ffmpeg"))
    ap.add_argument("--dir", default=DEFAULT_DIR)
    ap.add_argument("--quality", type=float, default=1.0,
                    help="Vorbis -q:a (0~=48kbps, 1~=64kbps, 2~=80kbps). Default 1.")
    ap.add_argument("--rate", type=int, default=0, help="downsample Hz (0 = keep source)")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    d = os.path.abspath(args.dir)
    mp3s = sorted(glob.glob(os.path.join(d, "*.mp3")))
    m0, o0, b0 = sizes(d)
    print(f"Dir: {d}")
    print(f"Before: {m0} mp3 + {o0} ogg = {b0/1e6:.1f} MB")
    print(f"ffmpeg: {args.ffmpeg}  |  vorbis -q:a {args.quality}"
          + (f"  -ar {args.rate}" if args.rate else "  (keep sample rate)"))
    if args.dry_run:
        print(f"{len(mp3s)} mp3 would be transcoded to .ogg (dry run)")
        return

    conv = skip = fail = 0
    for i, mp3 in enumerate(mp3s, 1):
        ogg = mp3[:-4] + ".ogg"
        if os.path.exists(ogg):          # keep an existing (hand-recorded) ogg
            os.remove(mp3); skip += 1; continue
        tmp = ogg + ".tmp"
        cmd = [args.ffmpeg, "-hide_banner", "-loglevel", "error", "-y",
               "-i", mp3, "-vn", "-ac", "1", "-c:a", "libvorbis",
               "-q:a", str(args.quality)]
        if args.rate:
            cmd += ["-ar", str(args.rate)]
        # tmp has a .tmp extension, so force the container (ffmpeg otherwise
        # infers format from the extension and fails on '.ogg.tmp').
        cmd += ["-f", "ogg", tmp]
        r = subprocess.run(cmd)
        if r.returncode == 0 and os.path.exists(tmp) and os.path.getsize(tmp) > 0:
            os.replace(tmp, ogg); os.remove(mp3); conv += 1
        else:
            if os.path.exists(tmp):
                os.remove(tmp)
            fail += 1
            print("  FAIL:", os.path.basename(mp3))
        if i % 100 == 0:
            print(f"  ...{i}/{len(mp3s)}")

    m1, o1, b1 = sizes(d)
    print(f"\nConverted {conv}, dropped-redundant {skip}, failed {fail}")
    print(f"After: {m1} mp3 + {o1} ogg = {b1/1e6:.1f} MB")
    print(f"Saved: {(b0-b1)/1e6:.1f} MB ({100*(b0-b1)/max(1,b0):.0f}% smaller)")


if __name__ == "__main__":
    main()
