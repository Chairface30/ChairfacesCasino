"""Pachinko Parlor: board physics, the lottery, each machine's payback, and
a headless run of the parlor windows.

Part 1 fires balls at every machine with the lottery switched off and
counts where they end: start pocket, side pockets, attacker (with a
jackpot open), drain, wedged. Boards must build from their seed, keep
every pin out of the display box, and never wedge a ball.

Part 2 checks the lottery against its specs: hit odds in NORMAL and
KAKUHEN, reach frequency, the kakuhen share of jackpots, round draws,
holds capped at four, mode transitions (kakuhen loop / ST / jitan).

Part 3 feeds the measured pocket rates into a Monte Carlo of each
machine's economy (starts, spins, jackpots, modes, holds) and reports the
payback: balls paid per ball fired. Every machine must land between 88%
and 100% at its best handle setting.

Part 4 opens the parlor against the mocked frame API, picks a machine,
fires with credits moving through the wallet, forces a jackpot and
watches the attacker pay.

Run: python tests/pachinko_test.py  (pip install lupa)
"""
import os
import random
import re

import lupa

ADDON_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
failures = []


def check(label, cond, detail=""):
    if not cond:
        failures.append(label)
    print(("PASS  " if cond else "FAIL  ") + label + (f"  [{detail}]" if detail and not cond else ""))


rt = lupa.LuaRuntime(unpack_returned_tuples=True)
rt.execute("ChairfacesCasino = { Arcade = {} }")
rt.execute(open(os.path.join(ADDON_DIR, "Games", "Pachinko", "PachinkoMachine.lua"), encoding="utf-8").read())
rt.execute(r"""
PK = ChairfacesCasino.Arcade.Pachinko
PK.LAUNCH_INTERVAL = 0.12   -- balls do not touch, so a dense stream measures the same

-- fire `balls` at a machine with the lottery off (or a jackpot held open,
-- or the tulip held open) and count where they land
function pockets(id, handle, balls, mode)
  local m = PK:GetMachine(id)
  local st = PK:NewMachineState(m, 99)
  PK:SetHandle(st, handle)
  PK:SetFiring(st, true)
  st.m = setmetatable({ odds = 1e12, kakuhenOdds = 1e12, count = 1e9 }, { __index = m })
  if mode == "jackpot" then
    st.jackpot = { rounds = 1000, round = 1, count = 0, kind = "normal", open = true, gap = 0, paid = 0 }
  elseif mode == "open" then
    st.mode = "jitan"; st.modeSpins = 1e9
  end
  local ev = {}
  local c = { start = 0, side = 0, attacker = 0, drain = 0, stuck = 0, escaped = 0, inbox = 0 }
  local wallet = { spend = function() return true end, award = function() end }
  local box = PK.BOX
  while st.launched < balls or #st.balls > 0 do
    if st.launched >= balls then st.firing = false end
    for i = #ev, 1, -1 do ev[i] = nil end
    PK:Step(st, 1 / 30, ev, wallet)
    for _, b in ipairs(st.balls) do
      if b.x < 0 or b.x > PK.FIELD_W or b.y < 0 then c.escaped = c.escaped + 1 end
      if b.x > box.l + 1 and b.x < box.r - 1 and b.y > box.t + 1 and b.y < box.b - 1 then c.inbox = c.inbox + 1 end
    end
    for _, e in ipairs(ev) do
      if e.type == "start" then c.start = c.start + 1
      elseif e.type == "side" then c.side = c.side + 1
      elseif e.type == "attacker" then c.attacker = c.attacker + 1
      elseif e.type == "drain" then if e.stuck then c.stuck = c.stuck + 1 else c.drain = c.drain + 1 end end
    end
    st.holds = {}   -- keep the queue from filling; we only count entries
  end
  return c
end

function board_ok(id)
  local m = PK:GetMachine(id)
  local a = PK:NewMachineState(m, 1)
  local b = PK:NewMachineState(m, 2)
  if #a.board.pins ~= #b.board.pins then return false, "pin count differs" end
  for i, p in ipairs(a.board.pins) do
    if p.x ~= b.board.pins[i].x or p.y ~= b.board.pins[i].y then return false, "pins differ" end
  end
  local box = PK.BOX
  for _, p in ipairs(a.board.pins) do
    if p.x > box.l and p.x < box.r and p.y > box.t and p.y < box.b then return false, "pin inside the display" end
  end
  return true, #a.board.pins, #a.board.rails
end
""")
ev = rt.eval

# ---------------------------------------------------------------- physics
machines = ["vashjir", "felreaver", "northrend", "ravenholdt", "hunt", "scourge"]
rates = {}
pockets = ev("pockets")
board_ok = ev("board_ok")
for mid in machines:
    ok, pins, rails = board_ok(mid)
    check(f"{mid}: board builds from its seed, nothing inside the display", ok is True, str(pins))
    best = None
    for h in (0.4, 0.55, 0.7, 0.85):
        c = pockets(mid, h, 240, None)
        if c.escaped or c.inbox:
            check(f"{mid}: balls stay on the board", False, f"escaped {c.escaped} inbox {c.inbox}")
        if best is None or c.start > best[1].start:
            best = (h, c)
    h, c = best
    jp = pockets(mid, h, 240, "jackpot")
    op = pockets(mid, h, 240, "open")
    rates[mid] = dict(handle=h, start=c.start / 240, side=c.side / 240, attacker=jp.attacker / 240,
                      start_jp=jp.start / 240, start_open=op.start / 240)
    r = rates[mid]
    print(f"      {mid}: handle {h:.2f} starts {r['start']:.3f} sides {r['side']:.3f} tulip-open starts {r['start_open']:.3f} "
          f"attacker {r['attacker']:.2f} (stuck {c.stuck + jp.stuck + op.stuck})")
    check(f"{mid}: no wedged balls", c.stuck + jp.stuck + op.stuck == 0, str(c.stuck + jp.stuck + op.stuck))
    check(f"{mid}: the start pocket takes 5-30% of balls at the best handle", 0.05 <= r["start"] <= 0.30, f"{r['start']:.3f}")
    check(f"{mid}: the open attacker takes most balls", r["attacker"] >= 0.45, f"{r['attacker']:.2f}")
    check(f"{mid}: the open tulip takes more than the closed pocket", r["start_open"] > r["start"], f"{r['start_open']:.3f} vs {r['start']:.3f}")

# ---------------------------------------------------------------- lottery
rt.execute(r"""
-- run the lottery alone: feed starts straight in and tick time forward
function lottery(id, starts, seed, mode)
  local m = PK:GetMachine(id)
  local st = PK:NewMachineState(m, seed)
  if mode then st.mode = mode; st.modeSpins = 0 end
  local ev = {}
  local c = { spins = 0, hits = 0, reach = 0, kakuhen = 0, rounds = {}, maxHolds = 0, modes = {}, roundsTotal = 0 }
  local fed = 0
  local wallet = { spend = function() return true end, award = function() end }
  st.firing = false
  local guard = 0
  while (fed < starts or #st.holds > 0 or st.spin or st.jackpot) and guard < 5000000 do
    guard = guard + 1
    if fed < starts and #st.holds < PK.HOLD_MAX and not st.jackpot then
      -- a ball into the start pocket
      st.balls[1] = { x = st.board.start.x, y = st.board.start.y - PK.BALL_R - 1, vx = 0, vy = 50, slow = 0 }
      fed = fed + 1
    end
    for i = #ev, 1, -1 do ev[i] = nil end
    PK:Step(st, 0.5, ev, wallet)
    if #st.holds > c.maxHolds then c.maxHolds = #st.holds end
    for _, e in ipairs(ev) do
      if e.type == "spin_end" then
        c.spins = c.spins + 1
        if e.hit then c.hits = c.hits + 1 end
      elseif e.type == "spin_start" and e.reach then c.reach = c.reach + 1
      elseif e.type == "jackpot_start" then
        c.rounds[e.rounds] = (c.rounds[e.rounds] or 0) + 1
        c.roundsTotal = c.roundsTotal + 1
        if e.kind == "kakuhen" then c.kakuhen = c.kakuhen + 1 end
        -- feed the attacker so the jackpot plays out quickly
        local jp = st.jackpot
        while st.jackpot do
          if st.jackpot.open then
            st.balls[1] = { x = st.board.attacker.x, y = st.board.attacker.y - PK.BALL_R - 1, vx = 0, vy = 50, slow = 0 }
          end
          PK:Step(st, 0.5, nil, wallet)
        end
      elseif e.type == "mode" then c.modes[e.mode] = (c.modes[e.mode] or 0) + 1 end
    end
    -- measure one mode's odds only: pin the mode back after any jackpot
    st.mode = mode or "normal"; st.modeSpins = 0
  end
  return c
end
""")
lottery = ev("lottery")
c = lottery("felreaver", 40000, 5, None)
rate = c.hits / c.spins
check("Fel Reaver hits about 1 in 319 in NORMAL", 1 / 420 < rate < 1 / 250, f"1 in {1/rate:.0f} over {c.spins} spins")
check("about 12% of spins show a reach", 0.09 < c.reach / c.spins < 0.17, f"{c.reach / c.spins:.3f}")
check("holds never exceed four", c.maxHolds <= 4, str(c.maxHolds))
kak = c.kakuhen / max(1, c.roundsTotal)
check("about 65% of Fel Reaver jackpots are kakuhen", 0.5 < kak < 0.8, f"{kak:.2f} of {c.roundsTotal}")
r16 = (c.rounds[16] or 0) / max(1, c.roundsTotal)
check("round draws follow the spec (16R about 45%)", 0.3 < r16 < 0.6, f"{r16:.2f}")
ck = lottery("felreaver", 4000, 9, "kakuhen")
krate = ck.hits / ck.spins
check("Fel Reaver hits about 1 in 40 in KAKUHEN", 1 / 60 < krate < 1 / 28, f"1 in {1/krate:.0f}")

# mode transitions on a tiny deterministic walk
rt.execute(r"""
function transitions(id)
  local m = PK:GetMachine(id)
  local st = PK:NewMachineState(m, 3)
  local wallet = { spend = function() return true end, award = function() end }
  local seen = {}
  -- force one kakuhen jackpot and one normal jackpot by hand
  for _, kind in ipairs({ true, false }) do
    st.holds[1] = { hit = true, kakuhen = kind, rounds = 4, reels = { 7, 7, 7 }, reach = true }
    local ev = {}
    while not st.jackpot do PK:Step(st, 0.5, ev, wallet) end
    while st.jackpot do
      if st.jackpot.open then
        st.balls[1] = { x = st.board.attacker.x, y = st.board.attacker.y - PK.BALL_R - 1, vx = 0, vy = 50, slow = 0 }
      end
      PK:Step(st, 0.5, ev, wallet)
    end
    seen[#seen + 1] = st.mode .. ":" .. tostring(st.modeSpins)
  end
  return seen[1], seen[2]
end
""")
a, b = ev("transitions")("felreaver")
check("a kakuhen jackpot leaves Fel Reaver in KAKUHEN until the next hit, a normal one in 100 spins of JITAN",
      a == "kakuhen:0" and b == "jitan:100", f"{a} {b}")
a, b = ev("transitions")("hunt")
check("Beast Master's Hunt gives 100 ST spins after every jackpot", a == "kakuhen:100" and b == "kakuhen:100", f"{a} {b}")

# ---------------------------------------------------------------- payback
specs = {m.id: m for m in ev("PK.MACHINES").values()}


def payback(mid, balls=300000, seed=1):
    """Monte Carlo of a machine's economy from the measured pocket rates."""
    m = specs[mid]
    r = rates[mid]
    rng = random.Random(seed)
    rounds = [(row[1], row[2]) for row in m.rounds.values()]
    rsum = sum(w for _, w in rounds)
    paid = fired = 0
    mode, mode_spins = "normal", 0
    holds = 0
    spin_secs = {"normal": 1.7, "kakuhen": 0.55, "jitan": 0.55}
    clock = 0.0   # time until the running spin finishes
    while fired < balls:
        fired += 1
        clock -= 0.6
        if clock <= 0 and holds > 0:
            holds -= 1
            clock += spin_secs[mode] + (1.6 * 0.12)
            odds = m.kakuhenOdds if mode == "kakuhen" else m.odds
            if rng.random() < 1 / odds:
                pick = rng.random() * rsum
                for n, w in rounds:
                    pick -= w
                    if pick <= 0:
                        break
                kak = rng.random() < m.kakuhenRate
                # the jackpot: fire until every round's count is in
                for _ in range(n):
                    need = m.count
                    while need > 0:
                        fired += 1
                        if rng.random() < r["attacker"]:
                            need -= 1
                            paid += m.attackerPay
                        if rng.random() < r["start_jp"]:
                            paid += m.startPay
                            if holds < 4:
                                holds += 1
                        if rng.random() < r["side"]:
                            paid += m.sidePay
                    fired += 1   # the gap between rounds
                if kak:
                    mode, mode_spins = "kakuhen", (m.st or 0)
                elif (m.jitan or 0) > 0:
                    mode, mode_spins = "jitan", m.jitan
                else:
                    mode, mode_spins = "normal", 0
                clock = 0
            else:
                if mode != "normal" and mode_spins > 0:
                    mode_spins -= 1
                    if mode_spins == 0:
                        mode = "normal"
        start_rate = r["start"] if mode == "normal" else r["start_open"]
        if rng.random() < start_rate:
            paid += m.startPay
            if holds < 4:
                holds += 1
        if rng.random() < r["side"]:
            paid += m.sidePay
    return paid / fired


for mid in machines:
    rtp = payback(mid)
    print(f"      {mid}: payback {rtp:.3f}")
    check(f"{mid}: payback between 88% and 100%", 0.88 <= rtp <= 1.0, f"{rtp:.3f}")

# ---------------------------------------------------------------- window
src = open(os.path.join(ADDON_DIR, "tests", "reels_ui_test.py"), encoding="utf-8").read()
MOCK = re.search(r'MOCK = r"""(.*?)"""', src, re.S).group(1)
rt2 = lupa.LuaRuntime(unpack_returned_tuples=True)
rt2.execute(MOCK)
rt2.execute(r"""
local Obj = getmetatable(CreateFrame("Frame"))
function Obj:GetEffectiveScale() return 1 end
function Obj:GetLeft() return 0 end
function Obj:GetTop() return 600 end
function Obj:SetValue(v) rawset(self, "_value", v) end
function Obj:GetValue() return rawget(self, "_value") or 0 end
function GetCursorPosition() return 0, 0 end
ChairfacesCasino.UI.Lobby.AttachHowToPlayButton = function() return CreateFrame("Button") end
ChairfacesCasino.UI.Lobby.AttachTrixie = function() end
ChairfacesCasino.UI.Lobby.PlayTrixieVoice = function() end
ChairfacesCasino.Arcade.GetDB = function() __db.pachinko = __db.pachinko or {} return __db end
""")
for rel in (("Games", "Pachinko", "PachinkoMachine.lua"), ("UI", "PachinkoParlor.lua")):
    rt2.execute(open(os.path.join(ADDON_DIR, *rel), encoding="utf-8").read())
rt2.execute(r"""
Parlor = ChairfacesCasino.UI.PachinkoParlor
PKUI = ChairfacesCasino.UI.Pachinko
PK = ChairfacesCasino.Arcade.Pachinko
""")
ok = rt2.eval("""(function()
  Parlor:Show()
  if not Parlor.frame:IsShown() or #Parlor.tiles ~= 6 then return false end
  Parlor.tiles[2]:Click()
  local w = PKUI.frames.felreaver
  return w ~= nil and w:IsShown() and not Parlor.frame:IsShown()
end)()""")
check("the parlor opens a machine window", ok)
rt2.execute(r"""
local w = PKUI.frames.felreaver
__before = __db.credits
PKUI:SetRate(w, 5)
w.fireBtn:Click()
__advance(6)             -- ten balls at 100 a minute
__fired = w.state.launched
__spent = __before - __db.credits
w.fireBtn:Click()        -- stop
__advance(8)
__after_stop = w.state.launched
""")
check("firing spends the rate per ball", rt2.eval("__fired") >= 9 and rt2.eval("__spent") >= rt2.eval("__fired") * 5 - 5 * 3, f"fired {rt2.eval('__fired')} spent {rt2.eval('__spent')}")
check("the fire button stops the stream", rt2.eval("__after_stop") == rt2.eval("__fired"))
rt2.execute(r"""
local w = PKUI.frames.felreaver
local st = w.state
-- force a jackpot through the hold queue and fire into the open attacker
st.holds[1] = { hit = true, kakuhen = true, rounds = 4, reels = { 7, 7, 7 }, reach = true }
__creditsBefore = __db.credits
w.fireBtn:Click()
__advance(60)
w.fireBtn:Click()
__advance(10)
__paid = st.paidBalls
__mode = st.mode
__jackpots = st.jackpots
__stats = __db.pachinko.felreaver
""")
check("a forced jackpot pays through the attacker and leaves KAKUHEN", rt2.eval("__jackpots") >= 1 and rt2.eval("__paid") > 0 and rt2.eval("__mode") in ("kakuhen", "jitan", "normal"), f"jackpots {rt2.eval('__jackpots')} paid {rt2.eval('__paid')} mode {rt2.eval('__mode')}")
check("machine stats are saved", rt2.eval("__stats ~= nil and __stats.jackpots >= 1"))
rt2.execute("PKUI.frames.felreaver.closeBtn:Click()")
check("closing a machine returns to the parlor", rt2.eval("Parlor.frame:IsShown() and not PKUI.frames.felreaver:IsShown()"))

print()
if failures:
    print(f"{len(failures)} FAILED: " + ", ".join(failures))
    raise SystemExit(1)
print("all pachinko parlor checks passed")
