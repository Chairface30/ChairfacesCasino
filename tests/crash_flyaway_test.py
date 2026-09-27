"""Fly-away arming tests for CrashMultiplayer.lua.

Loads the real GameComm + CrashState + CrashMultiplayer in a lupa runtime
with WoW stubs and drives the host's flight ticker through whole flights:
the fly-away must NEVER end a round while anyone is still aboard, must fire
only after the ship stays empty for the full escape run, and must lose to
a crash tick that lands during the run (the close call).
Run: python tests/crash_flyaway_test.py  (pip install lupa)
"""
import lupa
import os
import sys

ADDON_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

STUBS = r"""
unpack = unpack or table.unpack
__now = 1000
function GetTime() return __now end
function time() return math.floor(__now) end
function UnitName(unit) if unit == "player" then return "Host" end end
function GetRealmName() return "TestRealm" end
function IsInGroup() return true end
function IsInRaid() return false end
function GetNumGroupMembers() return 4 end
function UnitIsConnected() return true end
function UnitInParty() return true end
function UnitInRaid() return false end
function PlaySoundFile() end
function PlaySound() end
UIParent = nil
function CreateFrame()
  local f = {}
  local function noop() end
  return setmetatable(f, { __index = function() return noop end })
end

-- Manual clock: tickers/timers fire when __advance() walks time forward
__timers = {}
C_Timer = {
  After = function(secs, fn)
    table.insert(__timers, { at = __now + secs, fn = fn, once = true })
  end,
  NewTicker = function(secs, fn)
    local t = { period = secs, at = __now + secs, fn = fn }
    function t:Cancel() self.cancelled = true end
    table.insert(__timers, t)
    return t
  end,
}
function __advance(seconds)
  local target = __now + seconds
  while true do
    -- earliest due timer, if any, inside the window
    local best
    for _, t in ipairs(__timers) do
      if not t.cancelled and t.at <= target and (not best or t.at < best.at) then
        best = t
      end
    end
    if not best then break end
    __now = best.at
    if best.once then best.cancelled = true else best.at = best.at + best.period end
    best.fn()
  end
  __now = target
end

local acecomm = {
  Embed = function(self, t)
    t.RegisterComm = function() end
    t.SendCommMessage = function() end
  end,
  RegisterComm = function() end,
  SendCommMessage = function() end,
}
function LibStub(name, silent) return acecomm end

ChairfacesCasino = {
  version = "2.5.2",
  name = "ChairfacesCasino",
  Print = function() end,
  Debug = function() end,
  FormatGold = function(self, n) return tostring(n) .. "g" end,
  CreateGameLink = function(self, game, text) return text end,
  OnPeerVersion = function() end,
  VersionsCompatible = function() return true end,
  GameHistory = {
    Add = function(self, list, game, max) table.insert(list, 1, game) end,
    Save = function() end,
    Load = function() return nil end,
  },
  Leaderboard = { RecordHandResult = function() end, StartSession = function() end, EndSession = function() end },
  DebtLedger = { RecordNets = function() end, IsFakePlay = function() return false end },
  TestMode = { enabled = true },
  HostSettings = { Set = function() end, Get = function() return nil end },
  db = { settings = {} },
}
"""

rt = lupa.LuaRuntime(unpack_returned_tuples=False)
rt.execute(STUBS)
for rel in [("Core", "GameComm.lua"), ("Games", "Crash", "CrashState.lua"),
            ("Games", "Crash", "CrashMultiplayer.lua")]:
    rt.execute(open(os.path.join(ADDON_DIR, *rel), encoding="utf-8").read())

failures = []
def check(label, cond, detail=""):
    status = "PASS" if cond else "FAIL"
    if not cond:
        failures.append(label)
    print(f"{status}  {label}" + (f"  [{detail}]" if detail and not cond else ""))

lua = rt.execute
ev = rt.eval

# A secret whose crash tick leaves plenty of room for mid-flight jumps
secret = ev("""
(function()
  local CS = ChairfacesCasino.CrashState
  for i = 1, 20000 do
    local s = "secret-" .. i
    local _, _, tick = CS:ComputeCrash(s, 0)
    if tick >= 60 and tick < 140 then return s end
  end
end)()
""")
check("found a long test flight secret", secret is not None)

def start_flight(riders):
    """Host a table, board riders over the wire, launch with our secret."""
    joins = "\n".join(
        f'CM:HandleJoin("{name}", {{ "ZJOIN", "2.5.2", "{target}" }})'
        for name, target in riders)
    lua(f"""
    local BJ = ChairfacesCasino
    local CM = BJ.CrashMultiplayer
    local CS = BJ.CrashState
    __timers = {{}}
    CM:ResetState()
    CM:HostTable(10)
    {joins}
    CM.secret = "{secret}"
    CS:BeginLaunch(CS:HashString(CM.secret))
    local _, point, tick = CS:ComputeCrash(CM.secret, 0)
    CM.crashPointSecret = point
    CM.crashTickSecret = tick
    CS:StartFlight(0)
    CM:StartFlightTicker()
    """)

def phase():
    return ev("ChairfacesCasino.CrashState.phase")

def aboard():
    return int(ev("ChairfacesCasino.CrashMultiplayer:CountAboard()"))

crash_tick = int(ev(f'select(3, ChairfacesCasino.CrashState:ComputeCrash("{secret}", 0))'))
TICK_SECS = float(ev("ChairfacesCasino.CrashState.TICK_SECONDS"))
EXIT_SECS = float(ev("ChairfacesCasino.CrashMultiplayer.FLYAWAY_EXIT_SECS"))

# --- 1. First jump of three must NOT start a fly-away, ever
start_flight([("A", ""), ("B", ""), ("C", "")])
lua("__advance(5 * ChairfacesCasino.CrashState.TICK_SECONDS)")
lua('ChairfacesCasino.CrashMultiplayer:HandleCashout("A", { "ZCASH" })')
lua(f"__advance({EXIT_SECS + 2})")  # well past a full escape run
check("first jump: still flying", phase() == "flight", phase())
check("first jump: two still aboard", aboard() == 2, aboard())
check("first jump: no fly-away flag", ev("ChairfacesCasino.CrashState.flyAway") is None)

# --- 2. All three out -> escape run -> fly-away ends the round
lua('ChairfacesCasino.CrashMultiplayer:HandleCashout("B", { "ZCASH" })')
lua('ChairfacesCasino.CrashMultiplayer:HandleCashout("C", { "ZCASH" })')
lua("__advance(%f)" % (EXIT_SECS - 0.5))
check("escape run: still flying just before exit", phase() == "flight", phase())
lua("__advance(1.0)")
check("empty ship: round ends as fly-away", phase() == "settlement", phase())
check("fly-away flag set", ev("ChairfacesCasino.CrashState.flyAway") == True)
# B and C jumped on the same tick: they tie and split; early jumper A pays
check("last jumpers (tick tie) still win the pot",
      ev("#ChairfacesCasino.CrashState.winners") == 2 and
      ev('ChairfacesCasino.CrashState.settlements["A"]') == -10)

# --- 3. Crash tick lands during the escape run: the close call wins
start_flight([("A", ""), ("B", "")])
# jump both just before the crash tick so the run overlaps the explosion
jump_at = crash_tick - 2
lua(f"__advance({jump_at} * {TICK_SECS})")
lua('ChairfacesCasino.CrashMultiplayer:HandleCashout("A", { "ZCASH" })')
lua('ChairfacesCasino.CrashMultiplayer:HandleCashout("B", { "ZCASH" })')
lua(f"__advance({EXIT_SECS + 2})")
check("close call: round settled", phase() == "settlement", phase())
check("close call: explosion, not fly-away", ev("ChairfacesCasino.CrashState.flyAway") is None)

# --- 4. Riders with pending auto targets count as aboard: no fly-away
start_flight([("A", ""), ("B", "3.0"), ("C", "3.5")])
lua("__advance(5 * ChairfacesCasino.CrashState.TICK_SECONDS)")
lua('ChairfacesCasino.CrashMultiplayer:HandleCashout("A", { "ZCASH" })')
lua(f"__advance({EXIT_SECS + 1})")
check("pending autos: still flying after a manual jump", phase() == "flight", phase())

# --- 5. DoCrash(true) forced with riders aboard downgrades to an explosion
start_flight([("A", ""), ("B", "")])
lua("__advance(5 * ChairfacesCasino.CrashState.TICK_SECONDS)")
lua("ChairfacesCasino.CrashMultiplayer:DoCrash(true)")
check("forced fly-away with riders aboard: explodes instead",
      phase() == "settlement" and ev("ChairfacesCasino.CrashState.flyAway") is None,
      f"{phase()} flyAway={ev('ChairfacesCasino.CrashState.flyAway')}")

print()
if failures:
    print(f"{len(failures)} FAILURES: {failures}")
    sys.exit(1)
print("ALL TESTS PASSED")
