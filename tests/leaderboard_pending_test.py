"""Settlement-gated leaderboard tests (pending hands).

Loads the REAL Leaderboard.lua + DebtLedger.lua together in one runtime and
drives the host-side settlement flow. The rule under test: a hand only
reaches the shared all-time board once the debt it created is SETTLED -
paid by trade, or netted square by later results. Forgiven debts and FREE
PLAY rounds never count; zero-net hands commit immediately. The personal
myStats panel stays live.

Run: python tests/leaderboard_pending_test.py  (pip install lupa)
"""
import lupa
import os
import sys

ADDON_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

STUBS = r"""
unpack = unpack or table.unpack
bit = bit or { bxor = function(a, b)
  local r, p = 0, 1
  while a > 0 or b > 0 do
    local abit, bbit = a % 2, b % 2
    if abit ~= bbit then r = r + p end
    a, b, p = (a - abit) / 2, (b - bbit) / 2, p * 2
  end
  return r
end }
__now = 1000
function GetTime() return __now end
function time() return math.floor(__now) end
function UnitName(unit) if unit == "player" then return "Host" end end
function GetRealmName() return "TestRealm" end
function UnitGUID() return "Player-1-Host" end
function IsInGroup() return false end
function IsInRaid() return false end
function GetNumGroupMembers() return 0 end
function GetRaidRosterInfo() return nil end
function UnitIsConnected() return true end
function GetChannelName() return 5 end
function SendChatMessage() end
function strsplit(sep, s)
  local out = {}
  for piece in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%1")) do
    table.insert(out, piece)
  end
  return unpack(out)
end
UIParent = nil
function CreateFrame()
  local f = {}
  local function noop() end
  return setmetatable(f, { __index = function() return noop end })
end
__timers = {}
C_Timer = {
  After = function(secs, fn) table.insert(__timers, { at = __now + secs, fn = fn }) end,
  NewTicker = function(secs, fn)
    local t = { at = __now + secs, period = secs, fn = fn }
    function t:Cancel() self.cancelled = true end
    table.insert(__timers, t)
    return t
  end,
}
function __advance(seconds)
  local target = __now + seconds
  while true do
    local best
    for _, t in ipairs(__timers) do
      if not t.cancelled and t.at <= target and (not best or t.at < best.at) then best = t end
    end
    if not best then break end
    __now = best.at
    if best.period then best.at = best.at + best.period else best.cancelled = true end
    best.fn()
  end
  __now = target
end
__outbox = {}
local AceCommStub = {
  RegisterComm = function() end,
  SendCommMessage = function(self, prefix, message, channel, target)
    table.insert(__outbox, { prefix = prefix, message = message })
  end,
}
function LibStub(name, silent)
  if name == "AceComm-3.0" then return AceCommStub end
  if name == "AceSerializer-3.0" then return _G.__aceSerializer end
  if name == "CallbackHandler-1.0" then return { New = function() return {} end } end
  error("unexpected LibStub: " .. tostring(name))
end
ChairfacesCasino = { version = "2.6.1", name = "ChairfacesCasino",
  Print = function() end, Debug = function() end,
  FormatGold = function(self, g) return tostring(g) .. "g" end }
ChairfacesCasinoSaved = {}
ChairfacesCasinoDB = {}
ChairfacesCasino.MyName = function(self) return UnitName("player") end
ChairfacesCasino.UnitFullName = function(self, unit) return (UnitName(unit)) end
"""

ACE_BOOT = r"""
do
  local real = nil
  local reg = { NewLibrary = function(self, name, ver) real = {}; return real end,
                GetLibrary = function(self, name) return real end }
  local savedLibStub = LibStub
  LibStub = setmetatable({ NewLibrary = reg.NewLibrary, GetLibrary = reg.GetLibrary },
    { __call = function(self, name, silent) return reg:GetLibrary(name) end })
  %ACE_SRC%
  __aceSerializer = real
  LibStub = savedLibStub
end
"""

rt = lupa.LuaRuntime(unpack_returned_tuples=False)
rt.execute(STUBS)
ace_src = open(os.path.join(ADDON_DIR, "Libs", "AceSerializer-3.0.lua"), encoding="utf-8").read()
rt.execute(ACE_BOOT.replace("%ACE_SRC%", ace_src))
rt.execute(open(os.path.join(ADDON_DIR, "Core", "Leaderboard.lua"), encoding="utf-8").read())
rt.execute(open(os.path.join(ADDON_DIR, "Core", "DebtLedger.lua"), encoding="utf-8").read())
rt.execute("ChairfacesCasino.Leaderboard:Initialize()")
rt.execute("ChairfacesCasino.DebtLedger:Initialize()")

failures = []
def check(label, cond, detail=""):
    print(("PASS" if cond else "FAIL") + "  " + label + (f"  [{detail}]" if detail and not cond else ""))
    if not cond:
        failures.append(label)


def totals(game, player):
    rt.execute(f'__t = ChairfacesCasino.Leaderboard:GetRowTotals("{game}", "{player}-TestRealm")')
    t = rt.eval("__t")
    return None if t is None else {"net": t["net"], "games": t["games"], "wins": t["wins"], "losses": t["losses"]}


def pending_count():
    return int(rt.eval("ChairfacesCasino.Leaderboard:GetPendingCount()"))


LB = "ChairfacesCasino.Leaderboard"
DL = "ChairfacesCasino.DebtLedger"

# =====================================================================
# 1. Banked game: hands stage until the debt is PAID
#    (poker-style order: hands first, then debts)
# =====================================================================
rt.execute(f'{LB}:RecordHandResult("blackjack", "Bob", -30, "lose")')
rt.execute(f'{LB}:RecordHandResult("blackjack", "Host", 30, "win")')
rt.execute(f'{DL}:RecordDebts("blackjack", {{ {{ debtor = "Bob", creditor = "Host", amount = 30 }} }}, false)')
rt.execute("__advance(1)")
check("unsettled hand is NOT on the board", totals("blackjack", "Bob") is None, totals("blackjack", "Bob"))
check("host's hand waits on the same pair", totals("blackjack", "Host") is None)
check("both hands are pending", pending_count() == 2, pending_count())
check("myStats panel stays live",
      rt.eval("ChairfacesCasino.Leaderboard.allTimeData.myStats.blackjack.games") == 1)

rt.execute(f'{DL}:ApplyPayment("Bob-TestRealm", "Host-TestRealm", 30)')
check("payment graduates the loser's hand",
      totals("blackjack", "Bob") == {"net": -30, "games": 1, "wins": 0, "losses": 1},
      totals("blackjack", "Bob"))
check("payment graduates the winner's hand",
      totals("blackjack", "Host") == {"net": 30, "games": 1, "wins": 1, "losses": 0})
check("pending store is drained", pending_count() == 0)

# =====================================================================
# 2. Offsetting results settle without any trade
# =====================================================================
rt.execute(f'{LB}:RecordHandResult("hilo", "Bob", 20, "win")')
rt.execute(f'{LB}:RecordHandResult("hilo", "Cat", -20, "lose")')
rt.execute(f'{DL}:RecordDebt("hilo", "Cat", "Bob", 20, false)')
rt.execute("__advance(1)")
check("hilo hands pend on Cat->Bob", totals("hilo", "Bob") is None and pending_count() == 2)

# derby-style order this time: debts recorded BEFORE the hands
rt.execute(f'{DL}:RecordDebt("roulette", "Bob", "Cat", 20, false)')  # nets the pair square
rt.execute(f'{LB}:RecordHandResult("roulette", "Cat", 20, "win")')
rt.execute(f'{LB}:RecordHandResult("roulette", "Bob", -20, "lose")')
rt.execute("__advance(1)")
check("offset graduates the EARLIER round's hands",
      totals("hilo", "Bob") == {"net": 20, "games": 1, "wins": 1, "losses": 0},
      totals("hilo", "Bob"))
check("the offsetting round's own hands commit at bind (pair already square)",
      totals("roulette", "Cat") == {"net": 20, "games": 1, "wins": 1, "losses": 0},
      totals("roulette", "Cat"))
check("nothing left pending after the offset", pending_count() == 0)

# =====================================================================
# 3. Forgiveness voids pending hands - they never count
# =====================================================================
rt.execute(f'{LB}:RecordHandResult("deathroll", "Dot", -50, "lose")')
rt.execute(f'{LB}:RecordHandResult("deathroll", "Eve", 50, "win")')
rt.execute(f'{DL}:RecordDebt("deathroll", "Dot", "Eve", 50, false)')
rt.execute("__advance(1)")
check("deathroll hands pend", pending_count() == 2)
rt.execute(f'{DL}:ApplyForgive("Dot-TestRealm", "Eve-TestRealm")')
check("forgiven hands are voided, not counted", totals("deathroll", "Eve") is None)
check("voided hands leave the pending store", pending_count() == 0)
rt.execute(f'{DL}:ApplyPayment("Dot-TestRealm", "Eve-TestRealm", 50)')
check("paying after forgiveness resurrects nothing", totals("deathroll", "Eve") is None)

# =====================================================================
# 4. Zero-net hands (push / participated) commit immediately
# =====================================================================
rt.execute(f'{LB}:RecordHandResult("blackjack", "Pip", 0, "push")')
rt.execute("__advance(1)")
t = totals("blackjack", "Pip")
check("push counts without waiting", t is not None and t["games"] == 1, t)

# =====================================================================
# 5. FREE PLAY rounds never reach the board
# =====================================================================
rt.execute(f'{LB}:RecordHandResult("crash", "Fay", 40, "win")')
rt.execute(f'{LB}:RecordHandResult("crash", "Gil", -40, "lose")')
rt.execute(f'{DL}:RecordNets("crash", {{ ["Fay"] = 40, ["Gil"] = -40 }}, true)')
rt.execute("__advance(1)")
check("fake-play hands are discarded", totals("crash", "Fay") is None and totals("crash", "Gil") is None)
check("fake-play leaves nothing pending", pending_count() == 0)

# =====================================================================
# 6. Pot game, two funding pairs: winner waits for BOTH losers to pay
# =====================================================================
rt.execute(f'{LB}:RecordHandResult("poker", "Win", 100, "win")')
rt.execute(f'{LB}:RecordHandResult("poker", "LossA", -50, "lose")')
rt.execute(f'{LB}:RecordHandResult("poker", "LossB", -50, "lose")')
rt.execute(f'{DL}:RecordNets("poker", {{ ["Win"] = 100, ["LossA"] = -50, ["LossB"] = -50 }}, false)')
rt.execute("__advance(1)")
check("pot hands all pend", pending_count() == 3)

rt.execute(f'{DL}:ApplyPayment("LossA-TestRealm", "Win-TestRealm", 50)')
check("paid loser graduates",
      totals("poker", "LossA") == {"net": -50, "games": 1, "wins": 0, "losses": 1})
check("winner still waits on the other loser", totals("poker", "Win") is None)
check("winner + unpaid loser remain pending", pending_count() == 2)

rt.execute(f'{DL}:ApplyPayment("LossB-TestRealm", "Win-TestRealm", 50)')
check("second payment graduates the winner",
      totals("poker", "Win") == {"net": 100, "games": 1, "wins": 1, "losses": 0},
      totals("poker", "Win"))
check("pot round fully drained", pending_count() == 0)

# =====================================================================
# 7. Derby reports debts as "derby" but stats as "chairscup" (alias)
# =====================================================================
rt.execute(f'{DL}:RecordDebts("derby", {{ {{ debtor = "Hal", creditor = "Host", amount = 10 }} }}, false)')
rt.execute(f'{LB}:RecordHandResult("chairscup", "Hal", -10, "lose")')
rt.execute(f'{LB}:RecordHandResult("chairscup", "Host", 10, "win")')
rt.execute("__advance(1)")
check("derby hands bind through the alias (not fail-open)",
      totals("chairscup", "Hal") is None and pending_count() == 2)
rt.execute(f'{DL}:ApplyPayment("Hal-TestRealm", "Host-TestRealm", 10)')
check("derby hands graduate on payment",
      totals("chairscup", "Hal") == {"net": -10, "games": 1, "wins": 0, "losses": 1})

# =====================================================================
# 8. Pending hands persist in the plaintext DB and survive a ledger sync
#    squaring the pair (paid while the recorder was offline)
# =====================================================================
rt.execute(f'{LB}:RecordHandResult("bingo", "Ivy", -15, "lose")')
rt.execute(f'{LB}:RecordHandResult("bingo", "Jax", 15, "win")')
rt.execute(f'{DL}:RecordDebts("bingo", {{ {{ debtor = "Ivy", creditor = "Jax", amount = 15 }} }}, false)')
rt.execute("__advance(1)")
check("bingo hands pend in ChairfacesCasinoDB.lbPending",
      int(rt.eval("#ChairfacesCasinoDB.lbPending.hands")) == 2)
# a SYNC_FULL merges a NEWER zero balance for the pair (someone saw it paid)
rt.execute("__advance(10)")
rt.execute(f'{DL}:HandleSyncFull("Ivy-TestRealm,Jax-TestRealm,0," .. tostring(time() + 100))')
check("a synced tombstone graduates the hands",
      totals("bingo", "Jax") == {"net": 15, "games": 1, "wins": 1, "losses": 0},
      totals("bingo", "Jax"))

# =====================================================================
# 9. Ledger reset drops orphaned pending hands
# =====================================================================
rt.execute(f'{LB}:RecordHandResult("liarsdice", "Kai", -5, "lose")')
rt.execute(f'{LB}:RecordHandResult("liarsdice", "Lee", 5, "win")')
rt.execute(f'{DL}:RecordDebts("liarsdice", {{ {{ debtor = "Kai", creditor = "Lee", amount = 5 }} }}, false)')
rt.execute("__advance(1)")
check("liarsdice hands pend", pending_count() == 2)
rt.execute(f'{DL}:ResetLedger()')
check("ledger wipe drops pending hands", pending_count() == 0)
check("wiped hands never counted", totals("liarsdice", "Lee") is None)

print()
if failures:
    print(f"{len(failures)} FAILURES: {failures}")
    sys.exit(1)
print("ALL TESTS PASSED")
