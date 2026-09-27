#!/usr/bin/env python3
"""Amplify the MASS-GENERATED Trixie clips in place (they come out of
ElevenLabs quiet - mean ~ -24 dB). Applies a volume gain plus a peak limiter
so quiet clips get the full boost while the few hot clips (e.g. trix_intro was
-0.1 dB) don't clip. Targets only the generator's own line set (POOLS + the
trix_intro/poke specials) - hand-recorded orphan .ogg files are left untouched.

Re-encodes ogg -> ogg (one more Vorbis generation; negligible for barks).
Needs ffmpeg+libvorbis (FFMPEG env or --ffmpeg, else PATH). Safe/resumable:
writes a .tmp, verifies, then swaps.

  FFMPEG=/path/to/ffmpeg.exe python tools/amplify_voices.py            # +30% (x1.3)
  python tools/amplify_voices.py --gain 1.5                            # +50%
  python tools/amplify_voices.py --dry-run
"""
import argparse, math, os, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_trixie_voices as gen  # for the exact generated line set (gen.LINES)

DIR = os.path.join(os.path.dirname(HERE), "Sounds", "Trixie")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ffmpeg", default=os.environ.get("FFMPEG", "ffmpeg"))
    ap.add_argument("--gain", type=float, default=1.3, help="linear gain (1.3 = +30%%)")
    ap.add_argument("--limit", type=float, default=0.98, help="alimiter ceiling (0-1)")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    # exactly the mass-generated clips that exist on disk (skip the 19 pending
    # and any hand-recorded orphan that isn't in the generator's line set)
    targets = [n for n in gen.LINES if os.path.exists(os.path.join(DIR, n + ".ogg"))]
    db = 20 * math.log10(args.gain)
    print(f"{len(targets)} generated clips  |  gain x{args.gain} (+{db:.1f} dB)  |  "
          f"peak limit {args.limit}  |  ffmpeg {args.ffmpeg}")
    if args.dry_run:
        return

    af = f"volume={args.gain},alimiter=limit={args.limit}:level=false"
    ok = fail = 0
    for i, n in enumerate(sorted(targets), 1):
        src = os.path.join(DIR, n + ".ogg")
        tmp = src + ".amp.tmp"
        cmd = [args.ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-i", src,
               "-af", af, "-c:a", "libvorbis", "-q:a", "1", "-f", "ogg", tmp]
        r = subprocess.run(cmd)
        if r.returncode == 0 and os.path.exists(tmp) and os.path.getsize(tmp) > 0:
            os.replace(tmp, src); ok += 1
        else:
            if os.path.exists(tmp):
                os.remove(tmp)
            fail += 1
            print("  FAIL:", n)
        if i % 100 == 0:
            print(f"  ...{i}/{len(targets)}")

    print(f"\nAmplified {ok}, failed {fail}")


if __name__ == "__main__":
    main()
