"""Per-recorder bucket sync tests for Leaderboard.lua.

Three real Lua runtimes (Host, Bob, Cat) run the actual module and exchange
the actual wire messages through a relay. Every scenario checks the core
invariant: a hand recorded once can never appear twice, no matter how many
times messages are replayed, reordered, or re-requested — and all clients
converge to identical boards.
Run: python tests/leaderboard_sync_test.py  (pip install lupa)
"""
import lupa
import os
import sys

ADDON_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

STUBS_TEMPLATE = r"""
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
function IsInGroup() return true end
function IsInRaid() return false end
function GetNumGroupMembers() return 3 end
function GetRaidRosterInfo() return nil end
function UnitIsConnected() return true end
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

-- timers fire when __advance() walks the clock
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

-- outbox: python relays these to the other runtimes
__outbox = {}
local AceCommStub = {
  RegisterComm = function(self, prefix, fn) __commHandler = fn end,
  SendCommMessage = function(self, prefix, message, channel, target)
    table.insert(__outbox, { prefix = prefix, message = message,
      channel = channel, target = target or "" })
  end,
}
local AceSerializerReal = nil
function LibStub(name, silent)
  if name == "AceComm-3.0" then return AceCommStub end
  if name == "AceSerializer-3.0" then return AceSerializerReal or _G.__aceSerializer end
  if name == "CallbackHandler-1.0" then return { New = function() return {} end } end
  error("unexpected LibStub: " .. tostring(name))
end

ChairfacesCasino = {
  version = "2.5.3",
  name = "ChairfacesCasino",
  Print = function() end,
  Debug = function() end,
  LeaderboardUI = nil,
}
-- As Core.lua's: a unit's name, as chat gives it (these stubs are one word).
ChairfacesCasino.MyName = function(self) return UnitName("player") end
ChairfacesCasino.UnitFullName = function(self, unit) return (UnitName(unit)) end
ChairfacesCasinoSaved = {}
"""

# AceSerializer needs LibStub with the registration API; give it a minimal one
ACE_SERIALIZER_BOOT = r"""
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


def make_runtime(name):
    rt = lupa.LuaRuntime(unpack_returned_tuples=False)
    rt.execute(STUBS_TEMPLATE.replace("%NAME%", name))
    ace_src = open(os.path.join(ADDON_DIR, "Libs", "AceSerializer-3.0.lua"), encoding="utf-8").read()
    rt.execute(ACE_SERIALIZER_BOOT.replace("%ACE_SRC%", ace_src))
    rt.execute(open(os.path.join(ADDON_DIR, "Core", "Leaderboard.lua"), encoding="utf-8").read())
    # pin to season 1: the wire fixtures below hardcode season tags, and the
    # bucket logic under test is season-agnostic
    rt.execute("ChairfacesCasino.Leaderboard.SEASON = 1")
    rt.execute("ChairfacesCasino.Leaderboard:Initialize()")
    return rt


RUNTIMES = {}
for n in ("Host", "Bob", "Cat"):
    RUNTIMES[n] = make_runtime(n)

failures = []
def check(label, cond, detail=""):
    status = "PASS" if cond else "FAIL"
    if not cond:
        failures.append(label)
    print(f"{status}  {label}" + (f"  [{detail}]" if detail and not cond else ""))


def drain(sender_name, duplicate=False, drop_for=()):
    """Relay sender's outbox to the other runtimes (optionally duplicated).
    Returns the drained messages for replay tests."""
    rt = RUNTIMES[sender_name]
    msgs = []
    n = rt.eval("#__outbox")
    for i in range(1, int(n) + 1):
        m = rt.eval(f"__outbox[{i}]")
        msgs.append({ "prefix": m["prefix"], "message": m["message"],
                      "channel": m["channel"], "target": m["target"] })
    rt.execute("__outbox = {}")
    for m in msgs:
        for other_name, other in RUNTIMES.items():
            if other_name == sender_name or other_name in drop_for:
                continue
            if m["channel"] == "WHISPER" and not m["target"].startswith(other_name):
                continue
            deliveries = 2 if duplicate else 1
            for _ in range(deliveries):
                other.globals()["__incoming"] = m["message"]
                other.execute(
                    'ChairfacesCasino.Leaderboard:OnCommReceived("CCLeaderboard", __incoming, "PARTY", "%s-TestRealm")'
                    % sender_name)
    return msgs


def settle_and_flush(recorder, results, duplicate=False, drop_for=()):
    """Record hands on the recorder and relay its flush broadcast."""
    rt = RUNTIMES[recorder]
    for (game, player, net, outcome) in results:
        rt.execute(
            f'ChairfacesCasino.Leaderboard:RecordHandResult("{game}", "{player}", {net}, "{outcome}")')
    rt.execute("__advance(1)")   # fires the 0.5s flush
    return drain(recorder, duplicate=duplicate, drop_for=drop_for)


def totals(runtime_name, game, player):
    rt = RUNTIMES[runtime_name]
    rt.execute(
        f'__t = ChairfacesCasino.Leaderboard:GetRowTotals("{game}", "{player}-TestRealm")')
    t = rt.eval("__t")
    if t is None:
        return None
    return { "net": t["net"], "games": t["games"], "wins": t["wins"], "losses": t["losses"] }


def boards_equal(game, player):
    vals = [totals(n, game, player) for n in RUNTIMES]
    return all(v == vals[0] for v in vals), vals


# --- 1. Host records a blackjack round for all three; everyone converges
settle_and_flush("Host", [
    ("blackjack", "Host", -30, "lose"),
    ("blackjack", "Bob", 20, "win"),
    ("blackjack", "Cat", 10, "win"),
])
same, vals = boards_equal("blackjack", "Bob")
check("all boards agree after one round", same, vals)
check("Bob's totals are exact", totals("Bob", "blackjack", "Bob") == { "net": 20, "games": 1, "wins": 1, "losses": 0 })

# --- 2. Duplicated delivery of the same flush cannot double-count
settle_and_flush("Host", [("blackjack", "Bob", 15, "win")], duplicate=True)
check("duplicate delivery is a no-op",
      totals("Bob", "blackjack", "Bob") == { "net": 35, "games": 2, "wins": 2, "losses": 0 },
      totals("Bob", "blackjack", "Bob"))
same, vals = boards_equal("blackjack", "Bob")
check("boards still agree after duplicates", same, vals)

# --- 3. A second recorder (Bob hosts next): buckets stack, hands don't
settle_and_flush("Bob", [
    ("blackjack", "Bob", -10, "lose"),
    ("blackjack", "Cat", 10, "win"),
])
check("two recorders sum correctly",
      totals("Cat", "blackjack", "Bob") == { "net": 25, "games": 3, "wins": 2, "losses": 1 },
      totals("Cat", "blackjack", "Bob"))
same, vals = boards_equal("blackjack", "Cat")
check("boards agree across recorders", same, vals)

# --- 4. Cat misses a round entirely, then heals via digest anti-entropy
settle_and_flush("Host", [("roulette", "Bob", 50, "win")], drop_for=("Cat",))
check("Cat is behind after the missed round", totals("Cat", "roulette", "Bob") is None)
# Cat broadcasts its digest; Host whispers back what Cat lacks
RUNTIMES["Cat"].execute("ChairfacesCasino.Leaderboard:BroadcastDigest()")
drain("Cat")
drain("Host")   # digest replies
drain("Bob")
check("digest heals the missed round",
      totals("Cat", "roulette", "Bob") == { "net": 50, "games": 1, "wins": 1, "losses": 0 },
      totals("Cat", "roulette", "Bob"))
# replaying the digest exchange changes nothing
RUNTIMES["Cat"].execute("ChairfacesCasino.Leaderboard:BroadcastDigest()")
drain("Cat"); drain("Host"); drain("Bob")
check("repeated digest exchange is a no-op",
      totals("Cat", "roulette", "Bob") == { "net": 50, "games": 1, "wins": 1, "losses": 0 })

# --- 5. Legacy blended messages are ignored (the old duplication vector)
RUNTIMES["Bob"].globals()["__incoming"] = "AT_UPD|blackjack|Bob-TestRealm|9999|500|400|100"
RUNTIMES["Bob"].execute(
    'ChairfacesCasino.Leaderboard:OnCommReceived("CCLeaderboard", __incoming, "PARTY", "Host-TestRealm")')
check("legacy AT_UPD blend is dropped",
      totals("Bob", "blackjack", "Bob") == { "net": 25, "games": 3, "wins": 2, "losses": 1 },
      totals("Bob", "blackjack", "Bob"))

# --- 6. Spoof guard: a bucket push (B4) may only carry the sender's own buckets
spoof = RUNTIMES["Host"].eval(
    '__aceSerializer:Serialize({ blackjack = { ["Bob-TestRealm"] = { ["Cat-TestRealm"] = { net = 100000, games = 99, wins = 99, losses = 0, pushes = 0 } } } })')
RUNTIMES["Bob"].globals()["__incoming"] = "B4|1|" + spoof
RUNTIMES["Bob"].execute(
    'ChairfacesCasino.Leaderboard:OnCommReceived("CCLeaderboard", __incoming, "PARTY", "Host-TestRealm")')
check("B4 cannot push someone else's bucket",
      totals("Bob", "blackjack", "Bob") == { "net": 25, "games": 3, "wins": 2, "losses": 1 })

# --- 6b. Hostile payloads: wrong types, absurd numbers, and junk game keys
#         are dropped without erroring (realm-wide sync = untrusted senders)
for label, lua_bucket in [
    ("string counters", '{ net = "garbage", games = "lots", wins = 0, losses = 0, pushes = 0 }'),
    ("table where number belongs", '{ net = {}, games = 1, wins = 1, losses = 0, pushes = 0 }'),
    ("absurd games count can't mint an unbeatable bucket", '{ net = 5, games = 1e15, wins = 1, losses = 0, pushes = 0 }'),
    ("negative games", '{ net = 5, games = -3, wins = 1, losses = 0, pushes = 0 }'),
]:
    bad = RUNTIMES["Host"].eval(
        '__aceSerializer:Serialize({ blackjack = { ["Bob-TestRealm"] = { ["Host-TestRealm"] = %s } } })' % lua_bucket)
    RUNTIMES["Bob"].globals()["__incoming"] = "B4|1|" + bad
    RUNTIMES["Bob"].execute(
        'ChairfacesCasino.Leaderboard:OnCommReceived("CCLeaderboard", __incoming, "PARTY", "Host-TestRealm")')
    check("hostile payload dropped: " + label,
          totals("Bob", "blackjack", "Bob") == { "net": 25, "games": 3, "wins": 2, "losses": 1 },
          totals("Bob", "blackjack", "Bob"))
junk = RUNTIMES["Host"].eval(
    '__aceSerializer:Serialize({ notagame = { ["Bob-TestRealm"] = { ["Host-TestRealm"] = { net = 1, games = 1, wins = 1, losses = 0, pushes = 0 } } } })')
RUNTIMES["Bob"].globals()["__incoming"] = "B4|1|" + junk
RUNTIMES["Bob"].execute(
    'ChairfacesCasino.Leaderboard:OnCommReceived("CCLeaderboard", __incoming, "PARTY", "Host-TestRealm")')
check("unknown game keys can't bloat the board",
      RUNTIMES["Bob"].eval('ChairfacesCasino.Leaderboard.allTimeData.notagame') is None)

# --- 6c. R4 digest replies are only ingested when solicited
dot = make_runtime("Dot")
r4blob = RUNTIMES["Host"].eval(
    '__aceSerializer:Serialize({ roulette = { ["Cat-TestRealm"] = { ["Host-TestRealm"] = { net = 7, games = 1, wins = 1, losses = 0, pushes = 0 } } } })')
dot.globals()["__incoming"] = "R4|1|" + r4blob
dot.execute(
    'ChairfacesCasino.Leaderboard:OnCommReceived("CCLeaderboard", __incoming, "WHISPER", "Host-TestRealm")')
dot.execute('__t = ChairfacesCasino.Leaderboard:GetRowTotals("roulette", "Cat-TestRealm")')
check("unsolicited R4 from a stranger is dropped", dot.eval("__t") is None)
# after we ask (digest goes out), the same reply merges
dot.execute("ChairfacesCasino.Leaderboard:BroadcastDigest()")
dot.execute("__outbox = {}")
dot.execute(
    'ChairfacesCasino.Leaderboard:OnCommReceived("CCLeaderboard", __incoming, "WHISPER", "Host-TestRealm")')
dot.execute('__t = ChairfacesCasino.Leaderboard:GetRowTotals("roulette", "Cat-TestRealm")')
check("solicited R4 merges after our digest", dot.eval("__t.games") == 1)
# a whispered digest (realm reconcile) also opens the window, per target
dot2 = make_runtime("Dot2")
dot2.execute('ChairfacesCasino.Leaderboard:WhisperDigest("Host-TestRealm")')
dot2.execute("__outbox = {}")
dot2.globals()["__incoming"] = "R4|1|" + r4blob
dot2.execute(
    'ChairfacesCasino.Leaderboard:OnCommReceived("CCLeaderboard", __incoming, "WHISPER", "Host-TestRealm")')
dot2.execute('__t = ChairfacesCasino.Leaderboard:GetRowTotals("roulette", "Cat-TestRealm")')
check("R4 merges after a whispered realm digest", dot2.eval("__t.games") == 1)

# --- 6d. CLEAR_DB only honored from allowlisted senders
dot.globals()["__incoming"] = "CLEAR_DB"
dot.execute(
    'ChairfacesCasino.Leaderboard:OnCommReceived("CCLeaderboard", __incoming, "PARTY", "Host-TestRealm")')
dot.execute('__t = ChairfacesCasino.Leaderboard:GetRowTotals("roulette", "Cat-TestRealm")')
check("CLEAR_DB from unauthorized sender is ignored", dot.eval("__t.games") == 1)
dot.execute(
    'ChairfacesCasino.TestMode = { IsAuthorizedName = function(self, n) return n == "Host" end }')
dot.execute(
    'ChairfacesCasino.Leaderboard:OnCommReceived("CCLeaderboard", __incoming, "PARTY", "Host-TestRealm")')
dot.execute('__t = ChairfacesCasino.Leaderboard:GetRowTotals("roulette", "Cat-TestRealm")')
check("CLEAR_DB from allowlisted sender clears", dot.eval("__t") is None)

# --- 7. Session board: two recorders, replays, exact sums
for name in RUNTIMES:
    RUNTIMES[name].execute("ChairfacesCasino.Leaderboard:StartPartySession()")
settle_and_flush("Host", [("holdem", "Bob", 40, "win"), ("holdem", "Host", -40, "lose")], duplicate=True)
settle_and_flush("Bob", [("holdem", "Bob", -5, "lose"), ("holdem", "Cat", 5, "win")])
def session(runtime_name, player):
    rt = RUNTIMES[runtime_name]
    rt.execute(f'__s = ChairfacesCasino.Leaderboard:GetSessionTotals("{player}-TestRealm")')
    s = rt.eval("__s")
    return s and { "net": s["net"], "hands": s["hands"] }
check("session sums across recorders", session("Cat", "Bob") == { "net": 35, "hands": 2 },
      session("Cat", "Bob"))
check("session agrees everywhere",
      session("Host", "Bob") == session("Bob", "Bob") == session("Cat", "Bob"))

# --- 8. Migration: an old blended row becomes a frozen LEGACY bucket, and
#        two machines migrating different blends converge instead of stacking
mig = make_runtime("Mig")
mig.execute(r"""
local LB = ChairfacesCasino.Leaderboard
-- simulate a pre-bucket saved payload: old-shape rows, no fmt marker
LB.allTimeData = {
    myStats = {},
    blackjack = {
        ["Mig-TestRealm"] = { net = 120, games = 12, wins = 7, losses = 5, lastSync = 1 },
        ["Bob-TestRealm"] = { net = -50, games = 5, wins = 2, losses = 3, lastSync = 1 },
    },
}
LB:MigrateToBuckets()
""")
mig.execute('__t = ChairfacesCasino.Leaderboard:GetRowTotals("blackjack", "Mig-TestRealm")')
t = mig.eval("__t")
check("migration preserves old totals", t["net"] == 120 and t["games"] == 12)
mig.execute('__b = ChairfacesCasino.Leaderboard.allTimeData.blackjack["Bob-TestRealm"].buckets["LEGACY:Bob-TestRealm"]')
check("old third-party rows become LEGACY buckets", mig.eval("__b.games") == 5)
# converging two different blends of the same row: bigger blend wins on both
mig.execute(r"""
local LB = ChairfacesCasino.Leaderboard
LB:MergeBucket("blackjack", "Bob-TestRealm", "LEGACY:Bob-TestRealm",
    { net = -60, games = 6, wins = 2, losses = 4, pushes = 0 })
""")
mig.execute('__t2 = ChairfacesCasino.Leaderboard:GetRowTotals("blackjack", "Bob-TestRealm")')
check("legacy blends converge to the larger, not the sum", mig.eval("__t2.games") == 6, mig.eval("__t2.games"))

print()
if failures:
    print(f"{len(failures)} FAILURES: {failures}")
    sys.exit(1)
print("ALL TESTS PASSED")
