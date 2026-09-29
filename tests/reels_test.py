"""Slot Floor machine tests for Games/ArcadeReels.lua.

Loads the real engine in a lupa runtime with a stub credit balance, checks
the rules of each machine (ways math, wild doubling, the Double Diamond
book, the pick-em board, tumbles), then simulates long runs to report each
machine's return-to-player. Run: python tests/reels_test.py [spins]
(pip install lupa)
"""
import lupa
import os
import sys

ADDON_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPINS = int(sys.argv[1]) if len(sys.argv) > 1 else 200000

STUBS = r"""
unpack = unpack or table.unpack
math.randomseed(12345)
__db = { credits = 0 }
ChairfacesCasino = {
  Arcade = {
    GetDB = function(self) return __db end,
    Spend = function(self, n)
      if __db.credits < n then return false end
      __db.credits = __db.credits - n
      return true
    end,
    Award = function(self, n) __db.credits = __db.credits + n end,
  },
}
"""

rt = lupa.LuaRuntime(unpack_returned_tuples=True)
rt.execute(STUBS)
rt.execute(open(os.path.join(ADDON_DIR, "Games", "ArcadeReels.lua"), encoding="utf-8").read())

failures = []
def check(label, cond, detail=""):
    if not cond:
        failures.append(label)
    print(("PASS  " if cond else "FAIL  ") + label + (f"  [{detail}]" if detail and not cond else ""))

ev = rt.eval
lua = rt.execute

# ---------- rules ----------
lua("R = ChairfacesCasino.Arcade.Reels")
check("five machines registered", ev("#R.machines") == 5)

# Kodo: 1024 ways - 2 kodos on each of the first three reels = 8 ways x 3-pay
got = ev("""(function()
  local m = R.byId.kodo
  local g = {}
  for r = 1, 5 do g[r] = { "N", "N", "N", "N" } end
  -- nines everywhere would pay; use distinct fillers
  local fill = { "A", "K", "Q", "J" }
  for r = 1, 5 do for row = 1, 4 do g[r][row] = fill[row] end end
  for r = 1, 3 do g[r][1] = "kodo"; g[r][2] = "kodo" end
  local rec = m:Evaluate(g, false)
  for _, w in ipairs(rec.wins) do if w.sym == "kodo" then return w.ways, w.units, w.count end end
end)()""")
kp = ev("R.byId.kodo.pays.kodo[3]")
check("kodo 2x2x2 = 8 ways of 3-kodo", got == (8, 8 * kp, 3), got)

# Kodo free games: a x3 wild on reel 2 in place of a kodo triples those ways
got = ev("""(function()
  local m = R.byId.kodo
  local g = {}
  local fill = { "A", "K", "Q", "J" }
  for r = 1, 5 do g[r] = {} for row = 1, 4 do g[r][row] = fill[row] end end
  g[1][1] = "kodo"; g[2][1] = "sun"; g[3][1] = "kodo"
  local rec = { }
  local wins = nil
  local cm = { ["2:1"] = 3 }
  -- call the ways evaluator through Evaluate with a fixed multiplier
  local old = math.random
  math.random = function(n) if n == 2 then return 2 end return old(n) end
  local r = m:Evaluate(g, true)
  math.random = old
  for _, w in ipairs(r.wins) do if w.sym == "kodo" then return w.ways end end
end)()""")
check("kodo free-game x3 wild triples the way", got == 3, got)

# Pharaoh: wild substitutes and doubles; five wilds pay 10000
got = ev("""(function()
  local m = R.byId.pharaoh
  local a = m:EvalLine({ "mask", "pharaoh", "mask", "A", "K" })
  local b = m:EvalLine({ "pharaoh", "pharaoh", "pharaoh", "pharaoh", "pharaoh" })
  local c = m:EvalLine({ "eye", "eye", "eye", "J", "K" })
  return a, b, c
end)()""")
check("pharaoh wild doubles (3 mask = 25 -> 50)", got[0] == 50, got)
check("pharaoh 5 wilds = 10000", got[1] == 10000, got)
check("pharaoh plain 3 eye = 20", got[2] == 20, got)

# Darkmoon: the Double Diamond book
def dm(line, coins=3):
    return ev(f"""(function() local p = R.byId.darkmoon:EvalLine({{{', '.join('"%s"' % s for s in line)}}}, {coins}) return p end)()""")
check("DD DD DD at 3 coins = 2500 total", dm(["dd", "dd", "dd"]) * 3 == 2500)
check("DD DD DD at 1 coin = 800", dm(["dd", "dd", "dd"], 1) == 800)
check("7 7 7 = 80", dm(["seven", "seven", "seven"]) == 80)
check("7 DD 7 = 160", dm(["seven", "dd", "seven"]) == 160)
check("7 DD DD = 320", dm(["seven", "dd", "dd"]) == 320)
check("mixed bars = 5", dm(["bar1", "bar3", "bar2"]) == 5)
check("bar DD bar mixed = 10", dm(["bar1", "dd", "bar2"]) == 10)
check("one cherry = 2", dm(["cherry", "blank", "blank"]) == 2)
check("lone DD = 2", dm(["blank", "dd", "blank"]) == 2)
check("nothing = 0", dm(["bar1", "seven", "blank"]) == 0)

# Jade pick board: winner appears exactly 3 times in order and last; others <= 2
ok = ev("""(function()
  local m = R.byId.jade
  for i = 1, 2000 do
    local lvl = (i % 5) + 1
    local p = m:BuildPick(lvl)
    local counts = {}
    for _, k in ipairs(p.order) do counts[k] = (counts[k] or 0) + 1 end
    if counts[p.winner] ~= 3 then return false, "winner count" end
    if p.order[#p.order] ~= p.winner then return false, "not last" end
    for k, n in pairs(counts) do if k ~= p.winner and n > 2 then return false, "decoy 3" end end
    for _, k in ipairs(p.rest) do counts[k] = (counts[k] or 0) + 1 end
    for k, n in pairs(counts) do if k ~= p.winner and n > 2 then return false, "rest 3" end end
    if #p.order + #p.rest > 12 then return false, "too many" end
    -- the winner must be unlocked at this level
    local okTier = false
    for _, j in ipairs(m:UnlockedJackpots(lvl)) do if j.key == p.winner then okTier = true end end
    if not okTier then return false, "locked tier won" end
  end
  return true
end)()""")
check("jade pick-em boards are well formed", ok == True or (isinstance(ok, tuple) and ok[0]), ok)

# Bonanza tumbles: every step with wins has an 'after' grid with no holes
ok = ev("""(function()
  local m = R.byId.bonanza
  for i = 1, 3000 do
    local rec = m:Evaluate(m:SpinOnce(i % 2 == 0), i % 2 == 0)
    for _, st in ipairs(rec.tumbles) do
      if #st.wins > 0 then
        if not st.after then return false end
        for r = 1, 6 do for row = 1, 5 do if not st.after[r][row] then return false end end end
      end
    end
    if #rec.tumbles[#rec.tumbles].wins ~= 0 then return false end
  end
  return true
end)()""")
check("bonanza tumbles settle cleanly", ok == True)

# ---------- exact RTP for the ways games ----------
# Reels are independent, so a ways game's expected pay is exact:
# E[pay n-of-a-kind] = pay[n] * prod(E[matches on reel r], r<=n) * P(reel n+1 misses),
# and free games are N/(1-R) spins (R = expected retrigger spins per spin).
R = ev("ChairfacesCasino.Arcade.Reels")

def windows(strip, rows):
    n = len(strip)
    return [[strip[(i + k) % n] for k in range(rows)] for i in range(n)]

def ways_ev(m, strips, multE, cost, scale=1.0):
    rows = m.rows
    wins = [windows([strips[r+1][i+1] for i in range(len(strips[r+1]))], rows) for r in range(m.reels)]
    total = 0
    for si in range(1, len(m.symbols)+1):
        s = m.symbols[si]
        pays = m.pays[s.id]
        if pays is None or s.wild or s.scatter: continue
        Ec, P0 = [], []
        for r in range(m.reels):
            ws = wins[r]; e = 0; z = 0
            for w in ws:
                c = sum(1 for v in w if v == s.id) + (sum(multE for v in w if v == m.wild) if r > 0 else 0)
                e += c; z += (c == 0)
            Ec.append(e/len(ws)); P0.append(z/len(ws))
        prod = 1
        for n in range(1, m.reels+1):
            prod *= Ec[n-1]
            p = pays[n]
            if p:
                total += p * prod * (P0[n] if n < m.reels else 1)
    return total * scale / cost

def scat_dist(m, strips):
    dist = {0: 1.0}
    for r in range(m.reels):
        ws = windows([strips[r+1][i+1] for i in range(len(strips[r+1]))], m.rows)
        cd = {}
        for w in ws:
            c = sum(1 for v in w if v == m.scatter); cd[c] = cd.get(c, 0) + 1/len(ws)
        nd = {}
        for a, pa in dist.items():
            for b, pb in cd.items(): nd[a+b] = nd.get(a+b, 0) + pa*pb
        dist = nd
    return dist

def machine(mid, level=1):
    m = R.byId[mid]
    cost = R.CostCoins(R, m, level)
    scale = (m.levels[level]/88) if m.levels else 1
    base = ways_ev(m, m.strips, 1, cost, scale)
    sd = scat_dist(m, m.strips)
    scat = sum(p * (m.scatterPays[min(k,5)] or 0) for k, p in sd.items())
    if mid == "jade": scat = scat  # x total bet already
    ptrig = sum(p for k, p in sd.items() if k >= 3)
    if mid == "kodo":
        N = sum(p * (m.freeSpins[min(k,5)] or 0) for k, p in sd.items()) / ptrig
        fd = scat_dist(m, m.freeStrips)
        Rr = sum(p * (m.retrigger[min(k,5)] or 0) for k, p in fd.items())
        fways = ways_ev(m, m.freeStrips, 2.5, cost, scale)
        fscat = sum(p * (m.scatterPays[min(k,5)] or 0) for k, p in fd.items())
    else:
        N = m.freeSpins
        fd = scat_dist(m, m.freeStrips)
        Rr = sum(p for k, p in fd.items() if k >= 3) * m.freeSpins
        fways = ways_ev(m, m.freeStrips, 1, cost, scale)
        fscat = sum(p * (m.scatterPays[min(k,5)] or 0) for k, p in fd.items())
    spins = N / (1 - Rr)
    free = ptrig * spins * (fways + fscat)
    pick = 0
    if mid == "jade": pick = m.jackpotShare
    return base + scat + free + pick, base, scat, free, pick, 1 / ptrig


print("\nExact RTP (ways games):")
exact = {}
for mid in ("kodo", "jade"):
    tot, base, scat, free, pick, trig = machine(mid, 1)
    exact[mid] = tot
    print(f"  {mid:9s}: RTP {tot*100:6.2f}%  (lines {base*100:.1f} + scatter {scat*100:.1f} + free {free*100:.1f} + jackpots {pick*100:.1f}; free games 1/{trig:.0f})")
    # every machine on the floor pays back ~95%, the same as Azeroth Riches
    check(f"{mid} exact RTP in 94.5-96.5%", 0.945 <= tot <= 0.965, f"{tot*100:.2f}%")

# ---------- RTP simulation ----------
lua("""
function __sim(id, level, n)
  local m = R.byId[id]
  __db.credits = 1e15
  local start = __db.credits
  local cost = R:CostCoins(m, level)
  local feats, big, freeHits, wheelHits, pickHits = 0, 0, 0, 0, 0
  local hits = 0
  for i = 1, n do
    local res = R:Play(id, 1, level)
    if res.total > 0 then hits = hits + 1 end
    if res.freeAwarded then freeHits = freeHits + 1 end
    if res.wheel then wheelHits = wheelHits + 1 end
    if res.pick then pickHits = pickHits + 1 end
    if res.total >= 50 * cost then big = big + 1 end
  end
  local wagered = n * cost
  local ret = __db.credits - start + wagered
  return ret / wagered, hits / n, freeHits, wheelHits, pickHits, big
end
""")

print(f"\nRTP over {SPINS} spins per configuration (coin = 1):")
configs = [("kodo", 1), ("pharaoh", 1), ("darkmoon", 1), ("darkmoon", 3),
           ("jade", 1), ("jade", 3), ("jade", 5), ("bonanza", 1)]
rtps = {}
for mid, lvl in configs:
    rtp, hit, fs, wh, pk, big = ev(f"__sim('{mid}', {lvl}, {SPINS})")
    rtps[(mid, lvl)] = rtp
    print(f"  {mid:9s} lvl {lvl}: RTP {rtp*100:6.2f}%  hit {hit*100:5.1f}%  "
          f"free 1/{SPINS/max(fs,1):.0f}  wheel 1/{SPINS/max(wh,1):.0f}  "
          f"pick 1/{SPINS/max(pk,1):.0f}  50x+ 1/{SPINS/max(big,1):.0f}")

if SPINS >= 100000:
    for (mid, lvl), rtp in rtps.items():
        if mid == "darkmoon" and lvl < 3:
            continue   # short-coining a wheel game is SUPPOSED to cost you
        if mid in exact:
            continue   # checked exactly above (stacked kodos swing a sim by +-10%)
        check(f"{mid} lvl {lvl} RTP in 88-100%", 0.88 <= rtp <= 1.00, f"{rtp*100:.2f}%")

print()
if failures:
    print(f"{len(failures)} FAILED: {failures}")
    sys.exit(1)
print("ALL PASS")
