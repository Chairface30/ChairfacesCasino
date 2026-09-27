"""Season-epoch + realm-wide sync tests for Leaderboard.lua (2.5.4).

Exercises the pieces added on top of the per-recorder bucket system:
  1. ApplySeasonReset wipes the all-time board (keeps myStats) when the
     stored season predates the current one.
  2. Season isolation on the wire: a season-tagged payload from a different
     season is dropped, and legacy unseasoned B3/R3 buckets are no longer
     ingested (so an un-reset / old peer can't resurrect the old board).
  3. Realm-wide anti-entropy: a never-before-seen, ungrouped peer that hears
     our HELLO reconciles the whole board over whisper (D4 -> R4 -> merge).

Run: python tests/leaderboard_season_test.py  (pip install lupa)
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
function UnitName(unit) if unit == "player" then return "%NAME%" end end
function GetRealmName() return "TestRealm" end
function UnitGUID() return "Player-1-%NAME%" end
-- realm-wide peers are NOT grouped: prove the whisper path needs no group
function IsInGroup() return false end
function IsInRaid() return false end
function GetNumGroupMembers() return 0 end
function GetRaidRosterInfo() return nil end
function UnitIsConnected() return true end
function GetChannelName() return 5 end
function SendChatMessage(msg, chan, _, idx) table.insert(__chatout, msg) end
__chatout = {}
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
  RegisterComm = function(self, prefix, fn) __commHandler = fn end,
  SendCommMessage = function(self, prefix, message, channel, target)
    table.insert(__outbox, { prefix = prefix, message = message,
      channel = channel, target = target or "" })
  end,
}
function LibStub(name, silent)
  if name == "AceComm-3.0" then return AceCommStub end
  if name == "AceSerializer-3.0" then return _G.__aceSerializer end
  if name == "CallbackHandler-1.0" then return { New = function() return {} end } end
  error("unexpected LibStub: " .. tostring(name))
end
ChairfacesCasino = { version = "2.5.4", name = "ChairfacesCasino",
  Print = function() end, Debug = function() end }
ChairfacesCasinoSaved = {}
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


def make_runtime(name, init=True):
    rt = lupa.LuaRuntime(unpack_returned_tuples=False)
    rt.execute(STUBS.replace("%NAME%", name))
    ace_src = open(os.path.join(ADDON_DIR, "Libs", "AceSerializer-3.0.lua"), encoding="utf-8").read()
    rt.execute(ACE_BOOT.replace("%ACE_SRC%", ace_src))
    rt.execute(open(os.path.join(ADDON_DIR, "Core", "Leaderboard.lua"), encoding="utf-8").read())
    # pin to season 1: the wire fixtures below hardcode season tags; the
    # epoch MECHANISM is what's under test, not the shipped season number
    rt.execute("ChairfacesCasino.Leaderboard.SEASON = 1")
    if init:
        rt.execute("ChairfacesCasino.Leaderboard:Initialize()")
    return rt


failures = []
def check(label, cond, detail=""):
    print(("PASS" if cond else "FAIL") + "  " + label + (f"  [{detail}]" if detail and not cond else ""))
    if not cond:
        failures.append(label)


def totals(rt, game, player):
    rt.execute(f'__t = ChairfacesCasino.Leaderboard:GetRowTotals("{game}", "{player}-TestRealm")')
    t = rt.eval("__t")
    return None if t is None else {"net": t["net"], "games": t["games"], "wins": t["wins"], "losses": t["losses"]}


def deliver(dst, dst_name, msg, sender):
    dst.globals()["__incoming"] = msg
    dst.execute(
        'ChairfacesCasino.Leaderboard:OnCommReceived("CCLeaderboard", __incoming, "WHISPER", "%s-TestRealm")'
        % sender)


def relay(src, src_name, dsts):
    """Move src's outbox to the named runtimes (respecting WHISPER targets)."""
    n = int(src.eval("#__outbox"))
    msgs = []
    for i in range(1, n + 1):
        m = src.eval(f"__outbox[{i}]")
        msgs.append({"message": m["message"], "channel": m["channel"], "target": m["target"]})
    src.execute("__outbox = {}")
    for m in msgs:
        for dname, drt in dsts.items():
            if m["channel"] == "WHISPER" and not m["target"].startswith(dname):
                continue
            deliver(drt, dname, m["message"], src_name)


# =====================================================================
# 1. Season reset wipes the board, keeps myStats
# =====================================================================
r = make_runtime("Ann", init=False)
r.execute(r"""
local LB = ChairfacesCasino.Leaderboard
LB.allTimeData = {
    myStats = { blackjack = { net = 777, games = 9, wins = 5, losses = 4, pushes = 0, bestWin = 100, worstLoss = -50 } },
    fmt = 3, season = 0,   -- an OLD season
    blackjack = { ["Ann-TestRealm"] = { buckets = { ["Ann-TestRealm"] = { net = 500, games = 50, wins = 30, losses = 20, pushes = 0 } } } },
}
LB.SEASON = 1
LB:ApplySeasonReset()
""")
check("season reset clears the all-time board",
      totals(r, "blackjack", "Ann") is None, totals(r, "blackjack", "Ann"))
check("season reset keeps personal myStats",
      r.eval("ChairfacesCasino.Leaderboard.allTimeData.myStats.blackjack.net") == 777)
check("season reset stamps the new season",
      r.eval("ChairfacesCasino.Leaderboard.allTimeData.season") == 1)
check("season reset flagged a notice", r.eval("ChairfacesCasino.Leaderboard.seasonWasReset") == True)

# same-season load does NOT wipe
r.execute(r"""
local LB = ChairfacesCasino.Leaderboard
LB.allTimeData.blackjack["Ann-TestRealm"] = { buckets = { ["Ann-TestRealm"] = { net = 5, games = 1, wins = 1, losses = 0, pushes = 0 } } }
LB.seasonWasReset = nil
LB:ApplySeasonReset()
""")
check("re-applying the same season is a no-op",
      totals(r, "blackjack", "Ann") == {"net": 5, "games": 1, "wins": 1, "losses": 0})

# =====================================================================
# 2. Season isolation on the wire
# =====================================================================
ann = make_runtime("Ann")
# a season-2 B4 must be dropped (we're season 1)
blob = ann.eval('__aceSerializer:Serialize({ blackjack = { ["Bob-TestRealm"] = { ["Bob-TestRealm"] = { net = 9, games = 3, wins = 3, losses = 0, pushes = 0 } } } })')
deliver(ann, "Ann", "B4|2|" + blob, "Bob")
check("a foreign-season B4 is dropped", totals(ann, "blackjack", "Bob") is None,
      totals(ann, "blackjack", "Bob"))
# the SAME buckets tagged with our season DO merge
deliver(ann, "Ann", "B4|1|" + blob, "Bob")
check("a same-season B4 merges", totals(ann, "blackjack", "Bob") == {"net": 9, "games": 3, "wins": 3, "losses": 0})
# a legacy unseasoned B3 is no longer ingested (old peer can't resurrect data)
blob2 = ann.eval('__aceSerializer:Serialize({ hilo = { ["Bob-TestRealm"] = { ["Bob-TestRealm"] = { net = 40, games = 8, wins = 8, losses = 0, pushes = 0 } } } })')
deliver(ann, "Ann", "B3|" + blob2, "Bob")
check("legacy B3 buckets are no longer ingested", totals(ann, "hilo", "Bob") is None,
      totals(ann, "hilo", "Bob"))

# =====================================================================
# 3. Realm-wide whisper reconcile with a never-seen, ungrouped peer
# =====================================================================
host = make_runtime("Host")
zed = make_runtime("Zed")   # brand new, never in Host's group
# Host has recorded some hands (as the game host)
host.execute(r"""
local LB = ChairfacesCasino.Leaderboard
LB:RecordHandResult("roulette", "Host", 60, "win")
LB:RecordHandResult("roulette", "Cat", -60, "lose")
""")
host.execute("__advance(1)")     # flush timers
host.execute("__outbox = {}")    # ignore the party flush (nobody grouped anyway)

# Host announces on the realm channel; Zed hears the HELLO and reconciles.
# We feed Zed the HELLO body directly (channel transport is stubbed).
check("Zed starts with no roulette board", totals(zed, "roulette", "Host") is None)
zed.execute('ChairfacesCasino.Leaderboard:OnRealmHello("Host-TestRealm", "1")')
zed.execute("__advance(10)")     # fire the staggered WhisperDigest
relay(zed, "Zed", {"Host": host})    # Zed's D4 digest reaches Host
relay(host, "Host", {"Zed": zed})    # Host's R4 reply reaches Zed
check("never-seen peer pulls the whole board over whisper",
      totals(zed, "roulette", "Host") == {"net": 60, "games": 1, "wins": 1, "losses": 0},
      totals(zed, "roulette", "Host"))
check("realm reconcile also carried the other seat",
      totals(zed, "roulette", "Cat") == {"net": -60, "games": 1, "wins": 0, "losses": 1})

# a foreign-season HELLO is ignored (no whisper scheduled)
zed2 = make_runtime("Zed2")
zed2.execute('ChairfacesCasino.Leaderboard:OnRealmHello("Host-TestRealm", "7")')
zed2.execute("__advance(10)")
check("a foreign-season HELLO triggers no reconcile", int(zed2.eval("#__outbox")) == 0)

# =====================================================================
# 4. Idle HELLOs collapse to ONE channel send (no flush-click spam)
# =====================================================================
q = make_runtime("Que")
q.execute("__advance(20)")     # login QueueRealmHello(true) fires at +15s
q.execute("__advance(1300)")   # two 600s ticker firings queue more HELLOs
q.execute("ChairfacesCasino.Leaderboard:FlushRealmQueue()")
check("hours of queued HELLOs flush as a single message",
      int(q.eval("#__chatout")) == 1, q.eval("#__chatout"))
check("HELLO rides the channel with the pipe swapped",
      q.eval("__chatout[1]") == "CCLB7H4~1", q.eval("__chatout[1]"))
q.execute("ChairfacesCasino.Leaderboard:FlushRealmQueue()")
check("a second flush sends nothing (queue drained)", int(q.eval("#__chatout")) == 1)

# =====================================================================
# 5. Reset My Stats: personal panel only, shared rows untouched
# =====================================================================
res = make_runtime("Res")
res.execute(r"""
local LB = ChairfacesCasino.Leaderboard
LB:RecordHandResult("roulette", "Res", 25, "win")
LB:RecordHandResult("roulette", "Bob", -25, "lose")
""")
res.execute("__advance(1)")
check("recorder has a shared row before reset",
      totals(res, "roulette", "Res") == {"net": 25, "games": 1, "wins": 1, "losses": 0})
res.execute('ChairfacesCasino.Leaderboard:ResetMyData("roulette")')
check("reset zeroes the personal myStats panel",
      res.eval('ChairfacesCasino.Leaderboard.allTimeData.myStats.roulette.games') == 0)
check("reset leaves my shared row alone",
      totals(res, "roulette", "Res") == {"net": 25, "games": 1, "wins": 1, "losses": 0},
      totals(res, "roulette", "Res"))
check("reset leaves other players' rows alone",
      totals(res, "roulette", "Bob") == {"net": -25, "games": 1, "wins": 0, "losses": 1})

print()
if failures:
    print(f"{len(failures)} FAILURES: {failures}")
    sys.exit(1)
print("ALL TESTS PASSED")
