"""Pot-based chicken tests for CrashState.lua.

Loads the real module in a lupa runtime with WoW stubs and drives whole
rounds: last-jumper-takes-pot, tick ties splitting, crash-tick rollbacks,
nobody-jumped pushes, voided riders, auto-jump targets, and the geometric
explosion distribution. Run: python tests/crash_test.py  (pip install lupa)
"""
import lupa
import os
import sys

ADDON_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

STUBS = r"""
unpack = unpack or table.unpack
__now = 1000
function GetTime() return __now end
function time() __now = __now + 1; return __now end
function UnitName(unit) if unit == "player" then return "Host" end end
function GetRealmName() return "TestRealm" end

__handResults = {}
__recordedNets = nil
ChairfacesCasino = {
  Print = function() end,
  Debug = function() end,
  GameHistory = {
    Add = function(self, list, game, max) table.insert(list, 1, game) end,
    Save = function() end,
    Load = function() return nil end,
  },
  Leaderboard = {
    RecordHandResult = function(self, game, name, net, outcome)
      table.insert(__handResults, { game = game, name = name, net = net, outcome = outcome })
    end,
  },
  DebtLedger = {
    RecordNets = function(self, game, nets)
      local copy = {}
      for k, v in pairs(nets) do copy[k] = v end
      __recordedNets = { game = game, nets = copy }
    end,
  },
  TestMode = { enabled = false },
}
-- As Core.lua's: a unit's name, as chat gives it (these stubs are one word).
ChairfacesCasino.MyName = function(self) return UnitName("player") end
ChairfacesCasino.UnitFullName = function(self, unit) return (UnitName(unit)) end
"""

rt = lupa.LuaRuntime(unpack_returned_tuples=False)
rt.execute(STUBS)
rt.execute(open(os.path.join(ADDON_DIR, "Games", "Crash", "CrashState.lua"), encoding="utf-8").read())

failures = []
def check(label, cond, detail=""):
    status = "PASS" if cond else "FAIL"
    if not cond:
        failures.append(label)
    print(f"{status}  {label}" + (f"  [{detail}]" if detail and not cond else ""))

def lua(code):
    return rt.execute(code)

def ev(expr):
    return rt.eval(expr)

# Find a secret whose crash tick leaves room for pre-crash jumps
secret = ev("""
(function()
  local CS = ChairfacesCasino.CrashState
  for i = 1, 10000 do
    local s = "secret-" .. i
    local _, _, tick = CS:ComputeCrash(s, 0)
    if tick >= 30 and tick < 140 then return s end
  end
end)()
""")
check("found a mid-flight test secret", secret is not None)

def start_round(riders, secret_):
    lua(f"""
    local CS = ChairfacesCasino.CrashState
    CS:Reset()
    CS:HostGame("Host", 10)
    for _, r in ipairs({{ {', '.join(repr(r) for r in riders)} }}) do
      CS:AddPlayer(r)
    end
    CS:BeginLaunch(CS:HashString("{secret_}"))
    CS:StartFlight(0)
    """)

def crash_tick():
    return int(ev(f'select(3, ChairfacesCasino.CrashState:ComputeCrash("{secret}", 0))'))

T = crash_tick()

# --- 1. Last jumper takes the pot; earlier jumper and rider both lose ante
start_round(["A", "B", "C"], secret)
lua(f"""
local CS = ChairfacesCasino.CrashState
CS:CashOut("A", CS:MultiplierAt({T-5}), {T-5})
CS:CashOut("B", CS:MultiplierAt({T-2}), {T-2})
__recordedNets = nil
CS:Crash("{secret}", 0)
""")
check("verify passes on honest reveal", ev("ChairfacesCasino.CrashState.verifyFailed") == False)
check("pot is every ante", ev("ChairfacesCasino.CrashState.pot") == 30, ev("ChairfacesCasino.CrashState.pot"))
check("last jumper B wins alone",
      ev("#ChairfacesCasino.CrashState.winners") == 1 and ev("ChairfacesCasino.CrashState.winners[1]") == "B")
check("winner nets pot minus own ante", ev('ChairfacesCasino.CrashState.settlements["B"]') == 20)
check("early jumper loses ante", ev('ChairfacesCasino.CrashState.settlements["A"]') == -10)
check("rider goes down, loses ante", ev('ChairfacesCasino.CrashState.settlements["C"]') == -10)
check("debt ledger got zero-sum crash nets",
      ev('__recordedNets and __recordedNets.game') == "crash" and
      ev('__recordedNets.nets["A"] + __recordedNets.nets["B"] + __recordedNets.nets["C"]') == 0)

# --- 2. Jump at/after the crash tick rolls back: exploded with hand on the ripcord
start_round(["A", "B"], secret)
lua(f"""
local CS = ChairfacesCasino.CrashState
CS:CashOut("A", CS:MultiplierAt({T-3}), {T-3})
CS:CashOut("B", CS:MultiplierAt({T}), {T})
CS:Crash("{secret}", 0)
""")
check("tick tie with the crash loses", ev('ChairfacesCasino.CrashState.settlements["B"]') == -10)
check("surviving jumper takes the pot", ev('ChairfacesCasino.CrashState.settlements["A"]') == 10)

# --- 3. Same-tick jumpers split the pot (odd gold to the earliest seat)
start_round(["A", "B", "C"], secret)
lua(f"""
local CS = ChairfacesCasino.CrashState
CS:CashOut("A", CS:MultiplierAt({T-4}), {T-4})
CS:CashOut("B", CS:MultiplierAt({T-4}), {T-4})
CS:Crash("{secret}", 0)
""")
check("tie: two winners", ev("#ChairfacesCasino.CrashState.winners") == 2)
check("tie: pot split evenly", ev('ChairfacesCasino.CrashState.settlements["A"]') == 5
      and ev('ChairfacesCasino.CrashState.settlements["B"]') == 5)
check("tie: the one who rode down pays", ev('ChairfacesCasino.CrashState.settlements["C"]') == -10)

# --- 4. Nobody jumps: antes push
start_round(["A", "B"], secret)
lua(f'ChairfacesCasino.CrashState:Crash("{secret}", 0)')
check("no jumpers: no winners", ev("#ChairfacesCasino.CrashState.winners") == 0)
check("no jumpers: everyone pushes", ev('ChairfacesCasino.CrashState.settlements["A"]') == 0
      and ev('ChairfacesCasino.CrashState.settlements["B"]') == 0)

# --- 5. A voided rider is out of the pot entirely
start_round(["A", "B", "C"], secret)
lua(f"""
local CS = ChairfacesCasino.CrashState
CS:Refund("C")
CS:CashOut("A", CS:MultiplierAt({T-2}), {T-2})
CS:Crash("{secret}", 0)
""")
check("voided rider shrinks the pot", ev("ChairfacesCasino.CrashState.pot") == 20)
check("voided rider nets zero", ev('ChairfacesCasino.CrashState.settlements["C"]') == 0)
check("winner takes the smaller pot", ev('ChairfacesCasino.CrashState.settlements["A"]') == 10)

# --- 6. Auto-jump target applies at settlement even if never fired live
start_round(["A", "B"], secret)
lua(f"""
local CS = ChairfacesCasino.CrashState
CS.players["A"].target = CS:MultiplierAt({T-6})
CS:Crash("{secret}", 0)
""")
check("late-applied auto target still wins the pot",
      ev("#ChairfacesCasino.CrashState.winners") == 1 and ev("ChairfacesCasino.CrashState.winners[1]") == "A")

# --- 7. Distribution (rising hazard): always explodes, past the climb-out,
#        erratic low-mid deaths, 600m+ rare, the cap a fraction of a percent
stats = ev("""
(function()
  local CS = ChairfacesCasino.CrashState
  local n, caps, below1, past600, meters = 20000, 0, 0, 0, {}
  for i = 1, n do
    local p = CS:CrashPointFromSeed(i * 7919)
    if p < 1.0 then below1 = below1 + 1 end
    if p >= CS.MAX_MULT then caps = caps + 1 end
    local m = CS:MetersFor(p)
    if m > 600 then past600 = past600 + 1 end
    meters[#meters + 1] = m
  end
  table.sort(meters)
  return below1 .. "," .. caps .. "," .. meters[math.floor(n / 2)] .. "," .. past600
end)()
""")
below1, caps, median_m, past600 = [int(x) for x in stats.split(",")]
check("no explosion before the climb-out ends", below1 == 0, below1)
check("cap explosions are a rare spectacle (<0.5%, still happen)", 0 < caps < 0.005 * 20000, caps)
check("median flight ~310m (erratic low-mid deaths)", 260 <= median_m <= 370, median_m)
check("600m+ flights are rare (~7%)", 0.03 * 20000 <= past600 <= 0.12 * 20000, past600)

# --- 8. Meters <-> multiplier round trip (auto-jump input path)
rt_err = ev("""
(function()
  local CS = ChairfacesCasino.CrashState
  local worst = 0
  for _, m in ipairs({ 50, 100, 250, 450, 700, 1000 }) do
    local back = CS:MetersFor(CS:MultForMeters(m))
    local err = math.abs(back - m)
    if err > worst then worst = err end
  end
  return worst
end)()
""")
check("MultForMeters inverts MetersFor within 1m", rt_err <= 1, rt_err)

# --- 9. The crash tick never outruns the watchdog
max_tick = ev("""
(function()
  local CS = ChairfacesCasino.CrashState
  return CS:CrashTickFor(CS.MAX_MULT)
end)()
""")
check("cap tick stays inside the watchdog window", max_tick < ev("ChairfacesCasino.CrashState.WATCHDOG_TICKS"),
      f"{max_tick} vs watchdog")

print()
if failures:
    print(f"{len(failures)} FAILURES: {failures}")
    sys.exit(1)
print("ALL TESTS PASSED")
