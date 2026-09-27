"""Multi-client simulation tests for DebtLedger.lua.

Runs the module in several lupa (Lua) runtimes with WoW-API stubs and a
python comm relay standing in for AceComm party traffic, then exercises
game debts, netting, trade payments, forgiveness, forged messages, and
late-joiner sync. Run: python tests/debt_test.py  (pip install lupa)
"""
import lupa
import os
import sys

ADDON_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

STUBS = r"""
unpack = unpack or table.unpack

function strsplit(delim, s)
  local out = {}
  local from = 1
  while true do
    local i = string.find(s, delim, from, true)
    if not i then out[#out+1] = string.sub(s, from) break end
    out[#out+1] = string.sub(s, from, i-1)
    from = i + #delim
  end
  return unpack(out)
end

__playerName = "%PLAYER%"
__npcName = nil
__tradePlayerMoney = 0
__tradeTargetMoney = 0
__now = 1000

function UnitName(unit)
  if unit == "player" then return __playerName end
  if unit == "NPC" then return __npcName end
  return nil
end
function GetRealmName() return "TestRealm" end
function IsInGroup() return true end
function IsInRaid() return false end
function GetTime() return __now end
function time() __now = __now + 1; return __now end
function date(fmt, t) return os.date(fmt, t) end
function GetPlayerTradeMoney() return __tradePlayerMoney end
function GetTargetTradeMoney() return __tradeTargetMoney end
ERR_TRADE_COMPLETE = "Trade complete."
ERR_TRADE_CANCELLED = "Trade cancelled."

-- group + settle-by-trade stubs
__groupMembers = {}          -- { "Name", ... } -> party1, party2, ...
__initiatedTrade = nil       -- unit token passed to InitiateTrade
__setTradeMoney = nil        -- copper placed by the auto-fill
__interactNear = true
function GetNumGroupMembers() return #__groupMembers end
function UnitExists(unit)
  local i = tonumber(string.match(unit or "", "^party(%d+)$"))
  return i ~= nil and __groupMembers[i] ~= nil
end
local realUnitName = UnitName
function UnitName(unit)
  local i = tonumber(string.match(unit or "", "^party(%d+)$"))
  if i then return __groupMembers[i] end
  return realUnitName(unit)
end
function CheckInteractDistance(unit, index) return __interactNear end
function InitiateTrade(unit) __initiatedTrade = unit end

-- Staging money is readable back through GetPlayerTradeMoney on a real
-- client; __tradeGateBlocked simulates the modern hardware-event gate
-- silently refusing the call (no error, nothing staged)
__tradeGateBlocked = false
function SetTradeMoney(copper)
  if __tradeGateBlocked then return end
  __setTradeMoney = copper
  __tradePlayerMoney = copper
end

-- Optional trade money-input frame with gold/silver parentKey boxes, the
-- way the addon reaches them. SetText mimics Blizzard's OnTextChanged
-- path pushing the combined value into the trade. (SetTradeMoney itself
-- is called first and is the authoritative fill; boxes are cosmetics.)
__goldBoxText, __silverBoxText = nil, nil
function __enableTradeBoxes()
  local function push()
    local g = tonumber(__goldBoxText) or 0
    local s = tonumber(__silverBoxText) or 0
    SetTradeMoney(g * 10000 + s * 100)
  end
  TradePlayerInputMoneyFrame = {
    gold = {
      SetText = function(self, t) __goldBoxText = t; push() end,
      ClearFocus = function() end,
    },
    silver = {
      SetText = function(self, t) __silverBoxText = t; push() end,
      ClearFocus = function() end,
    },
  }
end

C_Timer = { After = function(sec, cb) end }  -- timers not exercised in tests

__eventHandler = nil
function CreateFrame()
  local f = {}
  f.RegisterEvent = function() end
  f.SetScript = function(self, which, fn) __eventHandler = fn end
  return f
end

__commHandler = nil
-- __pysend is injected from python: (prefix, msg, dist, target)
local AceCommStub = {
  RegisterComm = function(self, prefix, fn) __commHandler = fn end,
  SendCommMessage = function(self, prefix, msg, dist, target)
    __pysend(prefix, msg, dist, target)
  end,
}
function LibStub(name)
  if name == "AceComm-3.0" then return AceCommStub end
  return {}
end

__prints = {}
ChairfacesCasino = {
  db = {},
  Print = function(self, msg) __prints[#__prints+1] = tostring(msg) end,
  Debug = function(self, msg) end,
  FormatGold = function(self, amount)
    amount = math.floor((amount or 0) * 100 + 0.5) / 100
    local gold = math.floor(amount)
    local silver = math.floor((amount - gold) * 100 + 0.5)
    if silver > 0 then return gold .. "g " .. silver .. "s" end
    return gold .. "g"
  end,
  TestMode = { enabled = true },
}

-- Fire an event through the registered frame handler
function __fire(event, a1, a2)
  if __eventHandler then __eventHandler(nil, event, a1, a2) end
end

-- Deliver an incoming comm message
function __receive(prefix, msg, dist, sender)
  if __commHandler then __commHandler(prefix, msg, dist, sender) end
end
"""

class Client:
    def __init__(self, name, relay):
        self.name = name
        self.relay = relay
        self.rt = lupa.LuaRuntime(unpack_returned_tuples=False)
        self.rt.globals()["__pysend"] = self.on_send
        self.rt.execute(STUBS.replace("%PLAYER%", name))
        src = open(ADDON_DIR + r"\Core\DebtLedger.lua", encoding="utf-8").read()
        self.rt.execute(src)
        self.rt.execute("ChairfacesCasino.DebtLedger:Initialize()")
        self.outbox = []

    def on_send(self, prefix, msg, dist, target):
        self.outbox.append((prefix, msg, dist, target))
        self.relay.route(self, prefix, msg, dist, target)

    def receive(self, prefix, msg, dist, sender):
        self.rt.globals()["__receive"](prefix, msg, dist, sender)

    def lua(self, code):
        return self.rt.execute(code)

    def eval(self, expr):
        return self.rt.eval(expr)

    def owed(self, debtor, creditor):
        return self.eval(
            f'ChairfacesCasino.DebtLedger:GetOwed("{debtor}-TestRealm", "{creditor}-TestRealm")')

    def prints(self):
        p = self.rt.globals()["__prints"]
        return [p[i + 1] for i in range(len(p))]


class Relay:
    def __init__(self):
        self.clients = []
        self.paused = False

    def route(self, sender, prefix, msg, dist, target):
        if self.paused:
            return
        if dist == "WHISPER":
            for c in self.clients:
                # AceComm whisper target may be short or full name
                if c.name == target or c.name + "-TestRealm" == target:
                    c.receive(prefix, msg, dist, sender.name)
        else:
            # group broadcast: everyone receives, including the sender (echo)
            for c in self.clients:
                c.receive(prefix, msg, dist, sender.name)


failures = []
def check(label, cond, detail=""):
    status = "PASS" if cond else "FAIL"
    if not cond:
        failures.append(label)
    print(f"{status}  {label}" + (f"  [{detail}]" if detail and not cond else ""))


relay = Relay()
host = Client("Host", relay)
peer = Client("Peer", relay)
relay.clients = [host, peer]

# --- 1. Host records a blackjack round: Alice loses 50 to Host, Host loses 30 to Bob
host.lua("""
ChairfacesCasino.DebtLedger:RecordDebts("blackjack", {
  { debtor = "Alice", creditor = "Host", amount = 50 },
  { debtor = "Host", creditor = "Bob", amount = 30 },
})
""")
check("host ledger: Alice owes Host 50", host.owed("Alice", "Host") == 50, host.owed("Alice", "Host"))
check("host ledger: Host owes Bob 30", host.owed("Host", "Bob") == 30)
check("host self-echo not double-applied", host.owed("Alice", "Host") == 50)
check("peer got broadcast: Alice owes Host 50", peer.owed("Alice", "Host") == 50, peer.owed("Alice", "Host"))
check("peer got broadcast: Host owes Bob 30", peer.owed("Host", "Bob") == 30)

# --- 2. RecordNets greedy decomposition (hold'em pot: Peer wins 50 off Alice 40 + Bob 10)
host.lua("""
ChairfacesCasino.DebtLedger:RecordNets("holdem", { Alice = -40, Bob = -10, Peer = 50 })
""")
check("nets: Alice owes Peer 40", host.owed("Alice", "Peer") == 40, host.owed("Alice", "Peer"))
check("nets: Bob owes Peer 10", host.owed("Bob", "Peer") == 10)
check("peer mirror: Alice owes Peer 40", peer.owed("Alice", "Peer") == 40)
check("peer announced its own credit", any("owes you" in p for p in peer.prints()), peer.prints())

# --- 3. Cross-game netting: Host loses 20 to Alice at hilo -> Alice's 50 debt nets to 30
host.lua('ChairfacesCasino.DebtLedger:RecordDebt("hilo", "Host", "Alice", 20)')
check("netting: Alice now owes Host 30", host.owed("Alice", "Host") == 30, host.owed("Alice", "Host"))
check("netting mirrored on peer", peer.owed("Alice", "Host") == 30)

# --- 4. Trade payment: Peer owes Host 100; Peer hands Host 60g in a trade
host.lua('ChairfacesCasino.DebtLedger:RecordDebt("deathroll", "Peer", "Host", 100)')
check("setup: Peer owes Host 100", peer.owed("Peer", "Host") == 100)

# Peer side of the trade window (Peer gives 60g)
peer.lua('__npcName = "Host"; __fire("TRADE_SHOW")')
check("peer reminded of debt on trade open", any("You owe Host" in p for p in peer.prints()), peer.prints())
peer.lua('__tradePlayerMoney = 600000; __tradeTargetMoney = 0; __fire("TRADE_MONEY_CHANGED")')
# Host side of the same trade (receives 60g)
host.lua('__npcName = "Peer"; __fire("TRADE_SHOW")')
host.lua('__tradePlayerMoney = 0; __tradeTargetMoney = 600000; __fire("TRADE_MONEY_CHANGED")')
peer.lua('__fire("TRADE_CLOSED"); __fire("UI_INFO_MESSAGE", 1, ERR_TRADE_COMPLETE)')
host.lua('__fire("TRADE_CLOSED"); __fire("UI_INFO_MESSAGE", 1, ERR_TRADE_COMPLETE)')
check("peer after paying: owes 40", peer.owed("Peer", "Host") == 40, peer.owed("Peer", "Host"))
check("host after receiving: owed 40 (PAY echo skipped)", host.owed("Peer", "Host") == 40, host.owed("Peer", "Host"))
check("payer announced payment", any("Debt paid" in p for p in peer.prints()))
check("payee announced receipt", any("payment received" in p for p in host.prints()))

# --- 5. Overpay is capped: Peer trades 500g against the 40 owed
peer.lua('__npcName = "Host"; __fire("TRADE_SHOW")')
peer.lua('__tradePlayerMoney = 5000000; __tradeTargetMoney = 0; __fire("TRADE_MONEY_CHANGED")')
host.lua('__npcName = "Peer"; __fire("TRADE_SHOW")')
host.lua('__tradePlayerMoney = 0; __tradeTargetMoney = 5000000; __fire("TRADE_MONEY_CHANGED")')
peer.lua('__fire("TRADE_CLOSED"); __fire("UI_INFO_MESSAGE", 1, ERR_TRADE_COMPLETE)')
host.lua('__fire("TRADE_CLOSED"); __fire("UI_INFO_MESSAGE", 1, ERR_TRADE_COMPLETE)')
check("overpay capped: debt fully cleared, no negative", peer.owed("Peer", "Host") == 0 and peer.owed("Host", "Peer") == 0)
check("host agrees debt cleared", host.owed("Peer", "Host") == 0)

# --- 6. Cancelled trade applies nothing
host.lua('ChairfacesCasino.DebtLedger:RecordDebt("roulette", "Peer", "Host", 25)')
peer.lua('__npcName = "Host"; __fire("TRADE_SHOW")')
peer.lua('__tradePlayerMoney = 250000; __tradeTargetMoney = 0; __fire("TRADE_MONEY_CHANGED")')
peer.lua('__fire("TRADE_CLOSED"); __fire("UI_INFO_MESSAGE", 1, ERR_TRADE_CANCELLED)')
check("cancelled trade: debt unchanged", peer.owed("Peer", "Host") == 25, peer.owed("Peer", "Host"))

# --- 7. Forgive: Host forgives Peer's 25g; peer honors it (sender == creditor)
host.lua('ChairfacesCasino.DebtLedger:Forgive("Peer")')
check("host forgave: 0 owed", host.owed("Peer", "Host") == 0)
check("peer honored forgive", peer.owed("Peer", "Host") == 0)
check("peer notified of forgiveness", any("forgave your" in p for p in peer.prints()), peer.prints())

# --- 8. Forged FORGIVE from a non-creditor is rejected
host.lua('ChairfacesCasino.DebtLedger:RecordDebt("bingo", "Alice", "Bob", 15)')
peer.receive("CCDebtLedger", "FORGIVE|Alice-TestRealm|Bob-TestRealm", "PARTY", "Mallory")
check("forged forgive rejected", peer.owed("Alice", "Bob") == 15, peer.owed("Alice", "Bob"))

# --- 9. Forged PAY (sender != payer) rejected
peer.receive("CCDebtLedger", "PAY|Alice-TestRealm|Bob-TestRealm|15", "PARTY", "Mallory")
check("forged pay rejected", peer.owed("Alice", "Bob") == 15)

# --- 10. Late joiner sync: fresh client asks, host answers, ledgers converge
late = Client("Late", relay)
relay.clients = [host, peer, late]
# Give Late a stale nonzero copy of a debt Host has since seen paid (tombstone test)
late.lua("""
local DL = ChairfacesCasino.DebtLedger
local e = DL:GetEntry("Host-TestRealm", "Peer-TestRealm", true)
e.balance = 100
e.updated = 1  -- ancient
""")
late.lua('ChairfacesCasino.DebtLedger:RequestSync()')
check("sync: late joiner learned Alice owes Host 30", late.owed("Alice", "Host") == 30, late.owed("Alice", "Host"))
check("sync: late joiner learned Alice owes Peer 40", late.owed("Alice", "Peer") == 40)
check("sync: stale Peer-Host debt overwritten by newer tombstone", late.owed("Peer", "Host") == 0, late.owed("Peer", "Host"))

# --- 11. Silver amounts survive the wire (60.51g style payments)
host.lua('ChairfacesCasino.DebtLedger:RecordDebt("manual", "Carl", "Dana", 12.34)')
check("fractional debt on wire", abs(peer.owed("Carl", "Dana") - 12.34) < 0.001, peer.owed("Carl", "Dana"))

# --- 12. Fake play: a host with the toggle on records nothing, table gets a notice
host.lua('ChairfacesCasino.DebtLedger:SetFakePlay(true)')
host.lua("""
ChairfacesCasino.DebtLedger:RecordDebts("roulette", {
  { debtor = "Peer", creditor = "Host", amount = 500 },
})
""")
check("fake play: host recorded nothing", host.owed("Peer", "Host") == 0, host.owed("Peer", "Host"))
check("fake play: peer recorded nothing", peer.owed("Peer", "Host") == 0)
check("fake play: peer saw the fun-game notice", any("fake play" in p for p in peer.prints()), peer.prints()[-3:])
host.lua('ChairfacesCasino.DebtLedger:SetFakePlay(false)')
check("fake play toggle reads back off", host.eval("ChairfacesCasino.DebtLedger:IsFakePlay()") == False)

# --- 13. Settle by trade: button opens trade with a nearby creditor and fills the gold
host.lua('ChairfacesCasino.DebtLedger:RecordDebt("hilo", "Peer", "Host", 30)')
check("settle setup: Peer owes Host 30", peer.owed("Peer", "Host") == 30)

peer.lua('__groupMembers = { "Host" }; __interactNear = true')
peer.lua('ChairfacesCasino.DebtLedger:SettleWithTrade("Host")')
check("settle: trade initiated with the right unit", peer.eval("__initiatedTrade") == "party1", peer.eval("__initiatedTrade"))
peer.lua('__npcName = "Host"; __fire("TRADE_SHOW")')
check("settle: exact gold owed placed in trade", peer.eval("__setTradeMoney") == 300000, peer.eval("__setTradeMoney"))
check("settle: player told to confirm", any("confirm to settle" in p for p in peer.prints()))

# the queued trade then completes normally and clears the debt on both sides
peer.lua('__tradePlayerMoney = 300000; __tradeTargetMoney = 0; __fire("TRADE_MONEY_CHANGED")')
host.lua('__npcName = "Peer"; __fire("TRADE_SHOW")')
host.lua('__tradePlayerMoney = 0; __tradeTargetMoney = 300000; __fire("TRADE_MONEY_CHANGED")')
peer.lua('__fire("TRADE_CLOSED"); __fire("UI_INFO_MESSAGE", 1, ERR_TRADE_COMPLETE)')
host.lua('__fire("TRADE_CLOSED"); __fire("UI_INFO_MESSAGE", 1, ERR_TRADE_COMPLETE)')
check("settle: debt cleared on payer", peer.owed("Peer", "Host") == 0)
check("settle: debt cleared on payee", host.owed("Peer", "Host") == 0)

# guard rails: not in group / too far / nothing owed
host.lua('ChairfacesCasino.DebtLedger:RecordDebt("holdem", "Peer", "Host", 8)')
peer.lua('__initiatedTrade = nil; __groupMembers = {}')
peer.lua('ChairfacesCasino.DebtLedger:SettleWithTrade("Host")')
check("settle: refuses when creditor not in group", peer.eval("__initiatedTrade") == None)
check("settle: explains the group requirement", any("must be in your group" in p for p in peer.prints()))
peer.lua('__groupMembers = { "Host" }; __interactNear = false')
host.lua('ChairfacesCasino.DebtLedger:RecordDebt("bingo", "Peer", "Host", 5)')
peer.lua('ChairfacesCasino.DebtLedger:SettleWithTrade("Host")')
check("settle: refuses when too far away", peer.eval("__initiatedTrade") == None)
check("settle: explains the range problem", any("too far away" in p for p in peer.prints()))
peer.lua('__interactNear = true')
peer.lua('ChairfacesCasino.DebtLedger:SettleWithTrade("Alice")')
check("settle: refuses when nothing is owed", any("don't owe" in p for p in peer.prints()))

# with the real money-input boxes present, the fill types into gold/silver
# directly (the MoneyInputFrame_SetCopper path errors on Classic clients)
host.lua('ChairfacesCasino.DebtLedger:RecordDebt("manual", "Peer", "Host", 12.34)')
peer.lua('__enableTradeBoxes(); __setTradeMoney = nil')
peer.lua('ChairfacesCasino.DebtLedger:SettleWithTrade("Host")')
peer.lua('__npcName = "Host"; __fire("TRADE_SHOW")')
# Peer owed 13 from the guard-rail tests plus 12.34 = 25.34g -> 25g 34s
check("settle: gold box typed directly", peer.eval("__goldBoxText") == "25", peer.eval("__goldBoxText"))
check("settle: silver box typed directly", peer.eval("__silverBoxText") == "34", peer.eval("__silverBoxText"))
check("settle: boxes pushed the value into the trade", peer.eval("__setTradeMoney") == 253400, peer.eval("__setTradeMoney"))
# pay it off so the final tallies below stay unchanged
peer.lua('__tradePlayerMoney = 253400; __tradeTargetMoney = 0; __fire("TRADE_MONEY_CHANGED")')
host.lua('__npcName = "Peer"; __fire("TRADE_SHOW")')
host.lua('__tradePlayerMoney = 0; __tradeTargetMoney = 253400; __fire("TRADE_MONEY_CHANGED")')
peer.lua('__fire("TRADE_CLOSED"); __fire("UI_INFO_MESSAGE", 1, ERR_TRADE_COMPLETE)')
host.lua('__fire("TRADE_CLOSED"); __fire("UI_INFO_MESSAGE", 1, ERR_TRADE_COMPLETE)')
check("settle: box-filled trade cleared the debt on both sides",
      peer.owed("Peer", "Host") == 0 and host.owed("Peer", "Host") == 0,
      (peer.owed("Peer", "Host"), host.owed("Peer", "Host")))

# a settled pair starts its history over: nothing left after the payoff,
# exactly one entry once the next debt lands
def pair_history_len(client):
    return client.eval(
        '(function() local e = ChairfacesCasino.DebtLedger:GetEntry("Host-TestRealm", "Peer-TestRealm", false); '
        'return e and #(e.history or {}) or -1 end)()')
check("history wiped once settled", pair_history_len(peer) == 0, pair_history_len(peer))

# game debts that merely NET to zero keep their history - the back and
# forth is what explains the balance; only settling/forgiving clears it
host.lua('ChairfacesCasino.DebtLedger:RecordDebt("blackjack", "Xena", "Yara", 10)')
host.lua('ChairfacesCasino.DebtLedger:RecordDebt("hilo", "Yara", "Xena", 10)')
xy_hist = host.eval(
    '(function() local e = ChairfacesCasino.DebtLedger:GetEntry("Xena-TestRealm", "Yara-TestRealm", false); '
    'return e and #(e.history or {}) or -1 end)()')
check("netting to zero keeps the back-and-forth", xy_hist == 2, xy_hist)
host.lua('ChairfacesCasino.DebtLedger:RecordDebt("crash", "Xena", "Yara", 5)')
xy_hist = host.eval(
    '(function() local e = ChairfacesCasino.DebtLedger:GetEntry("Xena-TestRealm", "Yara-TestRealm", false); '
    'return e and #(e.history or {}) or -1 end)()')
check("next game debt continues that history", xy_hist == 3, xy_hist)

# taint-gated client: SetTradeMoney is silently ignored (AllowedWhenUntainted).
# The fill must NOT claim success; the player is told the amount to type.
host.lua('ChairfacesCasino.DebtLedger:RecordDebt("hilo", "Peer", "Host", 7)')
check("new debt starts a fresh one-entry history", pair_history_len(peer) == 1, pair_history_len(peer))
peer.lua('TradePlayerInputMoneyFrame = nil')
peer.lua('__tradeGateBlocked = true; __setTradeMoney = nil; __tradePlayerMoney = 0')
n_before = len(peer.prints())
peer.lua('ChairfacesCasino.DebtLedger:SettleWithTrade("Host")')
peer.lua('__npcName = "Host"; __fire("TRADE_SHOW")')
new_prints = peer.prints()[n_before:]
check("gated: no false 'placed' claim", not any("placed in the trade" in p for p in new_prints), new_prints)
check("gated: told the amount to type",
      any("7g" in p and "into the trade" in p for p in new_prints), new_prints)
peer.lua('__fire("TRADE_CLOSED"); __fire("UI_INFO_MESSAGE", 1, ERR_TRADE_CANCELLED)')
peer.lua('__tradeGateBlocked = false')
host.lua('ChairfacesCasino.DebtLedger:Forgive("Peer")')  # keep final tallies stable
check("forgiveness also wipes the history", pair_history_len(peer) == 0, pair_history_len(peer))

# --- 14. UI query shape
iowe_count = host.eval("""
(function()
  local iOwe, owedToMe = ChairfacesCasino.DebtLedger:GetMyDebts()
  return #iOwe .. "," .. #owedToMe
end)()
""")
check("host GetMyDebts shape (owes Bob; owed by Alice)", iowe_count == "1,1", iowe_count)

all_debts = host.eval("#ChairfacesCasino.DebtLedger:GetAllDebts()")
# Open pairs: Alice>Host, Host>Bob, Alice>Peer, Bob>Peer, Alice>Bob,
# Carl>Dana, Xena>Yara (Peer>Host was settled by the box-filled trade)
check("GetAllDebts lists every open pair", all_debts == 7, all_debts)

# --- 15. Regression: Initialize with BJ.db unset must attach to the saved-vars
# global instead of silently bailing (the 2.3.6 "no debts recorded" bug: the
# ADDON_LOADED name never matched, so BJ.db was nil at PLAYER_LOGIN)
cold = Client("Cold", relay)
cold.lua("""
ChairfacesCasino.db = nil
ChairfacesCasinoDB = nil
ChairfacesCasino.DebtLedger.data = nil
ChairfacesCasino.DebtLedger:Initialize()
""")
check("cold init: BJ.db attached to the SV global",
      cold.eval("ChairfacesCasino.db ~= nil and ChairfacesCasino.db == ChairfacesCasinoDB"))
check("cold init: ledger storage created",
      cold.eval("ChairfacesCasino.db.debtLedger ~= nil and ChairfacesCasino.db.debtLedger.pairs ~= nil"))
cold.lua('ChairfacesCasino.DebtLedger:RecordDebt("blackjack", "Alice", "Cold", 42)')
check("cold init: recording works after fallback", cold.owed("Alice", "Cold") == 42, cold.owed("Alice", "Cold"))
check("cold init: debt landed in the persisted table",
      cold.eval("(function() for _ in pairs(ChairfacesCasinoDB.debtLedger.pairs) do return true end return false end)()"))

print()
if failures:
    print(f"{len(failures)} FAILURES: {failures}")
    sys.exit(1)
print("ALL TESTS PASSED")
