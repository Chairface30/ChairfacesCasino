"""Multi-client simulation tests for TableFinder.lua.

Runs the module in several lupa (Lua) runtimes with WoW-API stubs and a
python relay standing in for guild addon traffic, then exercises listing,
sanitisation, delisting, REQ re-announce, sorting and TTL expiry.
Run: python tests/finder_test.py  (pip install lupa)
"""
import lupa
import os

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
__now = 100000
function UnitName(unit) if unit == "player" then return __playerName end end
function time() return __now end
function IsInGuild() return true end
function IsInRaid() return false end
function IsInGroup() return false end

-- no shared channel in the sim: the channel leg is silently skipped
function GetChannelName() return 0 end
__chanSends = {}
function SendChatMessage(msg, kind, lang, idx) __chanSends[#__chanSends+1] = msg end

-- C_Timer.After runs callbacks immediately (stagger delays don't matter
-- here); NewTicker never fires (heartbeats aren't under test)
C_Timer = {
  After = function(sec, cb) cb() end,
  NewTicker = function(sec, cb) return { Cancel = function() end } end,
}

__eventHandler = nil
function CreateFrame()
  local f = {}
  f.RegisterEvent = function() end
  f.SetScript = function(self, which, fn) __eventHandler = fn end
  return f
end

-- __pysend injected from python: (prefix, msg, dist, target)
C_ChatInfo = {
  RegisterAddonMessagePrefix = function() end,
  SendAddonMessage = function(prefix, msg, dist, target)
    __pysend(prefix, msg, dist, target)
  end,
}

__prints = {}
ChairfacesCasino = {
  Print = function(self, msg) __prints[#__prints+1] = tostring(msg) end,
  -- The real BJ:Readable from Core.lua: a plain string, or nil for a value
  -- the client keeps secret (here: anything whose tostring throws).
  Readable = function(self, value)
    if value == nil then return nil end
    local ok, text = pcall(function()
      local s = "" .. tostring(value)
      if s == "" then return nil end
      return s
    end)
    if ok then return text end
    return nil
  end,
}
-- As Core.lua's: a unit's name, as chat gives it (these stubs are one word).
ChairfacesCasino.MyName = function(self) return UnitName("player") end
ChairfacesCasino.UnitFullName = function(self, unit) return (UnitName(unit)) end
-- A stand-in for a secret string: reading it in any way throws.
__SECRET = setmetatable({}, { __tostring = function() error("secret string value") end })

function __fire(event, ...)
  if __eventHandler then __eventHandler(nil, event, ...) end
end
"""


class Client:
    def __init__(self, name, relay):
        self.name = name
        self.relay = relay
        self.rt = lupa.LuaRuntime(unpack_returned_tuples=False)
        self.rt.globals()["__pysend"] = self.on_send
        self.rt.execute(STUBS.replace("%PLAYER%", name))
        src = open(os.path.join(ADDON_DIR, "Core", "TableFinder.lua"), encoding="utf-8").read()
        self.rt.execute(src)
        relay.clients.append(self)
        self.rt.execute('__fire("PLAYER_LOGIN")')

    def on_send(self, prefix, msg, dist, target):
        self.relay.route(self, prefix, msg, dist, target)

    def receive(self, prefix, msg, sender):
        self.rt.globals()["__fire"]("CHAT_MSG_ADDON", prefix, msg, "GUILD", sender)

    def lua(self, code):
        return self.rt.execute(code)

    def eval(self, expr):
        return self.rt.eval(expr)

    def set_now(self, t):
        self.rt.execute(f"__now = {t}")

    def listings(self):
        n = self.eval("#ChairfacesCasino.TableFinder:GetListings()")
        out = []
        for i in range(1, int(n) + 1):
            out.append({
                k: self.eval(f'ChairfacesCasino.TableFinder:GetListings()[{i}].{k}')
                for k in ("name", "kind", "game", "stake", "note")
            })
        return out


class Relay:
    def __init__(self):
        self.clients = []

    def route(self, sender, prefix, msg, dist, target):
        if dist == "WHISPER":
            for c in self.clients:
                if c.name == target or target.startswith(c.name + "-"):
                    c.receive(prefix, msg, sender.name)
        else:
            for c in self.clients:
                if c is not sender:
                    c.receive(prefix, msg, sender.name)


passed = 0


def check(cond, label):
    global passed
    if cond:
        passed += 1
        print("PASS", label)
    else:
        print("FAIL", label)
        raise SystemExit(1)


relay = Relay()
alice = Client("Alice", relay)
bob = Client("Bob", relay)

# --- listing propagates, fields sanitized ---
alice.lua('ChairfacesCasino.TableFinder:ListMe("host", "holdem", "1g/2g blinds", "come | play~ friends")')
ls = bob.listings()
check(len(ls) == 1, "Bob sees Alice's listing")
check(ls[0]["name"] == "Alice" and ls[0]["kind"] == "host", "kind + name carried")
check(ls[0]["game"] == "holdem", "game key carried")
check("|" not in ls[0]["note"] and "~" not in ls[0]["note"], "note sanitized of | and ~")

# --- invalid game keys collapse to any ---
bob.lua('ChairfacesCasino.TableFinder:ListMe("seek", "poker;DROP", "", "")')
ls = alice.listings()
check(any(l["name"] == "Bob" and l["game"] == "any" for l in ls), "junk game key becomes any")

# --- sorting: hosts before seekers ---
ls = alice.listings()
# Alice sees only Bob (never her own listing in TF.listings); check on a third client
carol = Client("Carol", relay)
carol.lua('ChairfacesCasino.TableFinder:RequestListings()')
ls = carol.listings()
check(len(ls) == 2, "REQ re-announce fills a fresh client (%d)" % len(ls))
check(ls[0]["kind"] == "host" and ls[1]["kind"] == "seek", "hosts sort before seekers")

# --- delist removes everywhere ---
alice.lua('ChairfacesCasino.TableFinder:Delist()')
check(all(l["name"] != "Alice" for l in bob.listings()), "delist removes from Bob")
check(all(l["name"] != "Alice" for l in carol.listings()), "delist removes from Carol")

# --- TTL expiry ---
carol.set_now(100000 + 16 * 60)
check(len(carol.listings()) == 0, "listings expire after TTL")

# --- channel-leave (logout) expiry: leaving the shared channel drops the
# --- lister immediately, no TTL wait (args 2/9 = player, channel base name)
alice.lua('ChairfacesCasino.TableFinder:ListMe("host", "crash", "5g", "")')
check(any(l["name"] == "Alice" for l in bob.listings()), "Alice relisted for the logout test")
bob.lua('__fire("CHAT_MSG_CHANNEL_LEAVE", "", "Alice-Realm", "", "7. ChairfaceCasino",'
        ' "", "", 0, 7, "ChairfaceCasino")')
check(all(l["name"] != "Alice" for l in bob.listings()), "channel leave drops the lister immediately")

# --- secret strings (Forever): channel text and senders can arrive as values
# --- that throw when read. Ordinary General chat must be dropped untouched,
# --- and a secret on the casino channel skipped, never an error.
alice.lua('ChairfacesCasino.TableFinder:ListMe("host", "crash", "5g", "")')
before = len(bob.listings())
ok = True
try:
    bob.lua('__fire("CHAT_MSG_CHANNEL", __SECRET, __SECRET, "", "2. General - Ruins of Lordaeron",'
            ' __SECRET, "", 1, 2, "General - Ruins of Lordaeron")')
    bob.lua('__fire("CHAT_MSG_CHANNEL", __SECRET, __SECRET, "", "7. ChairfaceCasino",'
            ' "", "", 0, 7, "ChairfaceCasino")')
    bob.lua('__fire("CHAT_MSG_CHANNEL_LEAVE", "", __SECRET, "", "7. ChairfaceCasino",'
            ' "", "", 0, 7, "ChairfaceCasino")')
except Exception as e:
    ok = False
    print("   ", e)
check(ok, "secret channel text and senders are skipped, not an error")
check(len(bob.listings()) == before, "and change nothing")

print(f"\nAll {passed} checks passed.")
