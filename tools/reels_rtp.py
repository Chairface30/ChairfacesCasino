#!/usr/bin/env python3
"""Long-run return to player for one Slot Floor machine (Games/ArcadeReels.lua).

tests/reels_test.py checks every machine in 200,000 spins, which is too few
for the ones with big free-spin runs (a sim swings several points). This runs
one machine for as long as you like, so they can be set to the same payback:

  python tools/reels_rtp.py pharaoh 1 2000000
  python tools/reels_rtp.py darkmoon 3 2000000 --seed 5
  python tools/reels_rtp.py bonanza 1 2000000 --patch try.lua   # new numbers, file untouched
"""
import argparse, os
import lupa

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load(seed, patch=None):
    rt = lupa.LuaRuntime(unpack_returned_tuples=True)
    rt.execute(f"""
        unpack = unpack or table.unpack
        math.randomseed({seed})
        __db = {{ credits = 0 }}
        ChairfacesCasino = {{ Arcade = {{
            GetDB = function(self) return __db end,
            Spend = function(self, n) __db.credits = __db.credits - n return true end,
            Award = function(self, n) __db.credits = __db.credits + n end,
        }} }}
    """)
    rt.execute(open(os.path.join(ROOT, "Games", "ArcadeReels.lua"), encoding="utf-8").read())
    rt.execute("R = ChairfacesCasino.Arcade.Reels")
    if patch:
        rt.execute(patch)
    rt.execute("""
        function __sim(id, level, n)
            local m = R.byId[id]
            __db.credits = 0
            local cost = R:CostCoins(m, level)
            local hits = 0
            for _ = 1, n do
                local res = R:Play(id, 1, level)
                if res.total > 0 then hits = hits + 1 end
            end
            local wagered = n * cost
            return (__db.credits + wagered) / wagered, hits / n
        end
    """)
    return rt


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("machine")
    ap.add_argument("level", type=int)
    ap.add_argument("spins", type=int)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--patch")
    args = ap.parse_args()
    patch = open(args.patch, encoding="utf-8").read() if args.patch else None
    rtp, hit = load(args.seed, patch).eval(f"__sim('{args.machine}', {args.level}, {args.spins})")
    print(f"{args.machine} lvl {args.level}: RTP {rtp * 100:.2f}%  hit {hit * 100:.1f}%  ({args.spins} spins, seed {args.seed})")


if __name__ == "__main__":
    main()
