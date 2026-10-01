"""Gnomish Pachinko: engine rules and a headless window smoke test.

Part 1 loads Games/Pachinko/PachinkoEngine.lua alone and plays hundreds of
seeded rounds with a scripted aim, checking the invariants: every round
ends, balls never leave the field sideways, peg counts match the rules,
Fever starts exactly when the last orange lights, the pay table is applied
as published, and the layouts are reproducible from their seed.

Part 2 loads UI/PachinkoFrame.lua against the mocked frame API shared with
reels_ui_test.py and drives whole rounds through the window - PLAY, aim,
click to launch, pump OnUpdate - checking credits move exactly as the engine
says and that nothing throws.

Run: python tests/pachinko_test.py  (pip install lupa)
"""
import math
import os
import re

import lupa

ADDON_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

failures = []


def check(label, cond, detail=""):
    if not cond:
        failures.append(label)
    print(("PASS  " if cond else "FAIL  ") + label + (f"  [{detail}]" if detail and not cond else ""))


# ---------------------------------------------------------------- engine
rt = lupa.LuaRuntime(unpack_returned_tuples=True)
rt.execute("ChairfacesCasino = { Arcade = {} }")
rt.execute(open(os.path.join(ADDON_DIR, "Games", "Pachinko", "PachinkoEngine.lua"), encoding="utf-8").read())
rt.execute("PK = ChairfacesCasino.Arcade.Pachinko")

rt.execute(r"""
-- Play one round: aim at a scripted cycle of targets, launch, step until the
-- ball drains, repeat. Returns the result plus the checks' bookkeeping.
function play_round(seed, bet, aimMode)
  local st = PK:NewRound(bet, seed)
  local info = { escaped = false, feverAt = nil, feverOrangeLeft = nil, steps = 0,
                 lostStuck = 0, buckets = 0, powers = 0, lastEvent = nil, maxBalls = 0 }
  local events = {}
  local shots = 0
  while st.phase ~= PK.PHASE.OVER and info.steps < 200000 do
    if st.phase == PK.PHASE.AIM then
      shots = shots + 1
      local tx
      if aimMode == "spread" then tx = 40 + ((shots * 97) % 460)
      elseif aimMode == "orange" then
        -- a player reading the guide: sweep the aim and take the first angle
        -- whose arc meets an unlit orange, else any unlit peg
        local pick, fallback
        for deg = -80, 80, 2 do
          st.aim = deg * math.pi / 180
          local _, peg = PK:Guide(st, 2.5)
          if peg and not peg.lit then
            if peg.kind == "orange" then pick = st.aim break end
            fallback = fallback or st.aim
          end
        end
        st.aim = pick or fallback or 0
      else tx = PK.FIELD_W / 2 end
      if aimMode ~= "orange" then PK:Aim(st, tx, 400) end
      assert(PK:Launch(st))
    end
    for i = #events, 1, -1 do events[i] = nil end
    PK:Step(st, 1 / 60, events)
    info.steps = info.steps + 1
    if #st.balls > info.maxBalls then info.maxBalls = #st.balls end
    for _, b in ipairs(st.balls) do
      if b.x < 0 or b.x > PK.FIELD_W or b.y < 0 then info.escaped = true end
    end
    for _, ev in ipairs(events) do
      info.lastEvent = ev.type
      if ev.type == "fever" then info.feverAt = st.time; info.feverOrangeLeft = st.orangeLeft end
      if ev.type == "lost" and ev.stuck then info.lostStuck = info.lostStuck + 1 end
      if ev.type == "bucket" then info.buckets = info.buckets + 1 end
      if ev.type == "power" then info.powers = info.powers + 1 end
    end
  end
  return st, info
end

function count_kinds(st)
  local c = { blue = 0, orange = 0, green = 0, total = #st.pegs }
  for _, p in ipairs(st.pegs) do c[p.kind] = c[p.kind] + 1 end
  return c
end

function min_gap(st)
  local best = 1e9
  for i = 1, #st.pegs do for j = i + 1, #st.pegs do
    local dx, dy = st.pegs[i].x - st.pegs[j].x, st.pegs[i].y - st.pegs[j].y
    local d = math.sqrt(dx * dx + dy * dy)
    if d < best then best = d end
  end end
  return best
end
""")

ev = rt.eval

# Layout rules on every layout
bad_counts, bad_gap, bad_bounds = [], [], []
for seed in range(1, 41):
    st = ev(f"PK:NewRound(1, {seed})")
    c = ev("count_kinds")(st)
    if not (c["orange"] == 25 and c["green"] == 2 and 56 <= c["total"] <= 72):
        bad_counts.append((seed, dict(c)))
    if ev("min_gap")(st) < 40 - 1e-6:
        bad_gap.append(seed)
    for p in st.pegs.values():
        if not (34 <= p.x <= 540 - 34 and 120 <= p.y <= 500):
            bad_bounds.append(seed)
            break
check("every layout has 25 orange, 2 green, 56-72 pegs", not bad_counts, str(bad_counts[:3]))
check("pegs keep the 40px gap so the ball fits between", not bad_gap, str(bad_gap[:5]))
check("pegs stay inside the peg zone", not bad_bounds, str(bad_bounds[:5]))

names = set(ev(f"PK:NewRound(1, {s}).layout") for s in range(1, 60))
check("all five layouts come up", names == {"Brickwork", "Rainbow", "Diamonds", "Rings", "Zigzag"}, str(names))

a = ev("PK:NewRound(1, 12345)")
b = ev("PK:NewRound(1, 12345)")
same = all(a.pegs[i].x == b.pegs[i].x and a.pegs[i].y == b.pegs[i].y and a.pegs[i].kind == b.pegs[i].kind
           for i in range(1, len(a.pegs) + 1))
check("a seed reproduces its layout exactly", same)

# Aim clamps
st = ev("PK:NewRound(1, 7)")
aim = ev("PK.Aim")
lim = math.radians(82)
check("aim clamps to the right limit", abs(aim(ev("PK"), st, 2000, 30) - lim) < 1e-9)
check("aim clamps to the left limit", abs(aim(ev("PK"), st, -2000, 30) + lim) < 1e-9)
check("aim above the muzzle still points to the cursor's side", aim(ev("PK"), st, 100, -50) < 0)
check("straight down is zero", abs(aim(ev("PK"), st, 270, 500)) < 1e-9)
guide = ev("function(s) local pts = PK:Guide(s) return pts end")(st)
check("the guide has dots and ends before the field bottom", len(guide) >= 3 and all(p.y < 600 for p in guide.values()))

# Rounds terminate under every aim script and obey the rules
play = ev("play_round")
all_clear = 0
partial_pays = 0
stuck_total = 0
bucket_total = 0
power_total = 0
multi = 0
rounds = 0
problems = []
for mode in ("center", "spread", "orange"):
    for seed in range(1, 61):
        st, info = play(seed, 10, mode)
        rounds += 1
        if st.phase != "OVER":
            problems.append((mode, seed, "did not end", info.steps))
            continue
        if info.escaped:
            problems.append((mode, seed, "ball escaped"))
        r = st.result
        if r.oranges != 25 - st.orangeLeft or r.oranges + st.orangeLeft != 25:
            problems.append((mode, seed, "orange count"))
        if r.allClear:
            all_clear += 1
            if info.feverOrangeLeft != 0:
                problems.append((mode, seed, "fever before last orange"))
            if r.binMult not in (1, 2, 5):
                problems.append((mode, seed, "bad bin", r.binMult))
            expect = 10 * 4 * r.binMult + 10 * r.ballsLeft
            if r.win != expect:
                problems.append((mode, seed, "all-clear pay", r.win, expect))
        else:
            if info.feverAt is not None:
                problems.append((mode, seed, "fever without clear"))
            if r.ballsLeft != 0:
                problems.append((mode, seed, "ended with balls left"))
            expect = 20 if r.oranges >= 23 else (10 if r.oranges >= 20 else 0)
            if r.win != expect:
                problems.append((mode, seed, "partial pay", r.win, expect, r.oranges))
            if r.win > 0:
                partial_pays += 1
        stuck_total += info.lostStuck
        bucket_total += info.buckets
        power_total += info.powers
        if info.maxBalls > 1:
            multi += 1
check(f"all {rounds} scripted rounds end cleanly with the published pays", not problems, str(problems[:4]))
print(f"      all-clears {all_clear}, partial pays {partial_pays}, free balls {bucket_total}, "
      f"multiballs {power_total} (in {multi} rounds), stuck balls given up {stuck_total}")
check("the aim-at-orange script clears a layout sometimes", all_clear > 0)
check("the bucket hands out free balls", bucket_total > 0)
check("green pegs split the ball", power_total > 0 and multi > 0)
check("stuck balls are rare", stuck_total <= rounds * 0.2, str(stuck_total))

# Score multiplier ladder
mult = ev("PK.ScoreMultiplier")
PK = ev("PK")
check("score multiplier ladder", [mult(PK, n) for n in (0, 9, 10, 14, 15, 19, 20, 24, 25)] == [1, 1, 2, 2, 3, 3, 5, 5, 10])

rows = ev("PK:PayTableRows()")
check("pay table rows", [r.pays for r in rows.values()] == [20, 4, 1, 2, 1], str([r.pays for r in rows.values()]))

# ---------------------------------------------------------------- window
src = open(os.path.join(ADDON_DIR, "tests", "reels_ui_test.py"), encoding="utf-8").read()
MOCK = re.search(r'MOCK = r"""(.*?)"""', src, re.S).group(1)

rt2 = lupa.LuaRuntime(unpack_returned_tuples=True)
rt2.execute(MOCK)
rt2.execute(r"""
local Obj = getmetatable(CreateFrame("Frame"))
__cursor = { x = 0, y = 0 }
function GetCursorPosition() return __cursor.x, __cursor.y end
function Obj:GetEffectiveScale() return 1 end
function Obj:GetLeft() return 0 end
function Obj:GetTop() return 600 end
function Obj:GetRight() return 540 end
function Obj:GetBottom() return 0 end
function Obj:IsMouseOver() return true end
function Obj:SetAlpha(a) rawset(self, "_alpha", a) end
function Obj:GetAlpha() return rawget(self, "_alpha") or 1 end
function Obj:SetVertexColor(r, g, b, a) rawset(self, "_vc", { r, g, b, a }) end
function Obj:SetPoint(...) rawset(self, "_point", { ... }) end
function Obj:GetPoint() local p = rawget(self, "_point") if p then return unpack(p) end end
ChairfacesCasino.Arcade.BET_STEPS = { 1, 2, 3, 4, 5, 10, 15, 25, 50, 100 }
function ChairfacesCasino.Arcade:NextBetStep(current, dir)
  local steps = self.BET_STEPS
  local idx = 1
  for i, v in ipairs(steps) do if v == current then idx = i break end end
  idx = math.max(1, math.min(#steps, idx + dir))
  return steps[idx]
end
function ChairfacesCasino.Arcade:MaxAffordableStep() return 100 end
ChairfacesCasino.UI.Lobby.AttachHowToPlayButton = function() return CreateFrame("Button") end
ChairfacesCasino.UI.Lobby.AttachTrixie = function() end
""")
for rel in (("Games", "Pachinko", "PachinkoEngine.lua"), ("UI", "PachinkoFrame.lua")):
    rt2.execute(open(os.path.join(ADDON_DIR, *rel), encoding="utf-8").read())

rt2.execute(r"""
UIP = ChairfacesCasino.UI.Pachinko
PK = ChairfacesCasino.Arcade.Pachinko

-- Play a whole round through the window: PLAY, then on every AIM phase set
-- the cursor and click the field, pumping frames in between.
function ui_round(bet)
  UIP.bet = bet
  UIP:UpdateDisplay()
  local before = __db.credits
  UIP.playBtn:Click()
  local st = UIP.state
  if not st then return nil, "no state" end
  if __db.credits ~= before - bet then return nil, "bet not taken: " .. __db.credits .. " vs " .. before end
  local shots, t = 0, 0
  while st.phase ~= PK.PHASE.OVER and t < 600 do
    if st.phase == PK.PHASE.AIM then
      shots = shots + 1
      __cursor.x = 60 + ((shots * 131) % 420)
      __cursor.y = 600 - 420     -- GetTop is 600; field y 420 -> screen 180
      __advance(1 / 30)
      UIP.field:GetScript("OnMouseDown")(UIP.field, "LeftButton")
    end
    __advance(0.5)
    t = t + 0.5
  end
  if st.phase ~= PK.PHASE.OVER then return nil, "round did not end" end
  -- the window hands the win over as the round ends
  local expect = before - bet + st.result.win
  if __db.credits ~= expect then return nil, "credits " .. __db.credits .. " expected " .. expect end
  return st.result, shots
end
""")

ok = rt2.eval("""(function()
  UIP:Show()
  return UIP.frame:IsShown() and UIP.field ~= nil and UIP.playBtn ~= nil
end)()""")
check("the window builds and opens", ok)

ui_round = rt2.eval("ui_round")
results = []
for i in range(12):
    res, info = ui_round(5)
    if res is None:
        results.append(info)
check("twelve rounds through the window settle credits exactly", not results, str(results[:3]))

# clicking the field while a ball is in flight does nothing; clicking after
# the round is over does nothing either
rt2.execute("""
UIP.playBtn:Click()
local st = UIP.state
__cursor.x, __cursor.y = 270, 180
__advance(1/30)
UIP.field:GetScript("OnMouseDown")(UIP.field, "LeftButton")
__advance(1/30)
local fired = st.ballsFired
UIP.field:GetScript("OnMouseDown")(UIP.field, "LeftButton")
__advance(1/30)
__second_click_ignored = (st.ballsFired == fired)
""")
check("a click mid-flight does not fire a second ball", rt2.eval("__second_click_ignored"))

# closing mid-round and reopening keeps the round
rt2.execute("""
UIP:Hide()
__advance(1)
UIP:Show()
__advance(1)
__kept = UIP.state ~= nil and UIP.frame:IsShown()
""")
check("closing mid-round keeps the round for when the window reopens", rt2.eval("__kept"))

# broke players get comped on PLAY
rt2.execute("""
__db.credits = 0
UIP.state = nil
UIP:Show()
UIP.bet = 5
UIP:UpdateDisplay()
UIP.playBtn:Click()
__comped = __db.credits == 100 and UIP.state == nil
""")
check("PLAY with no credits asks the pit boss for a comp instead", rt2.eval("__comped"))

print()
if failures:
    print(f"{len(failures)} FAILED: " + ", ".join(failures))
    raise SystemExit(1)
print("all pachinko checks passed")
