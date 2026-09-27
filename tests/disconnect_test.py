"""Disconnect-hardening tests for GameComm/StateSync and the games (v2.5.x).

Loads the real modules in lupa runtimes with WoW-API stubs, then exercises:
  - the host-side actor watchdog (stalled actor forced, group-leaver forced
    fast, paused during recovery, inert in test mode / as client)
  - the SYNC_STATE sender filter now admitting temp-host recovery messages
    (with claim validation) while still rejecting forgeries
  - the corrected recovery-message field offsets (version at parts[3])
  - StateSync version adoption when the original host reclaims
  - ApplyPokerState clearing recovery state on a full-state sync
  - High-Lo host-transfer epochs (stale ex-host demotion, forged/stale
    transfers ignored, re-assertion against rival hosts)
  - fake-play table terms surviving Bingo caller migration / High-Lo host
    transfer, and DebtLedger honoring the explicit override

Run: python tests/disconnect_test.py   (pip install lupa)
"""
import lupa
import os

ADDON_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

STUBS = r"""
unpack = unpack or table.unpack

__playerName = "%PLAYER%"
__now = 1000
__groupMembers = {}     -- name -> true (present in group)
__connected = {}        -- name -> false marks a disconnected member
__sent = {}             -- outbound AceComm messages

function UnitName(unit)
  if unit == "player" then return __playerName end
  -- partyN tokens resolve in insertion order for UnitIsConnected loops
  local i = tonumber(string.match(unit or "", "^party(%d+)$"))
  if i then
    local n = 0
    for name in pairs(__groupMembers) do
      n = n + 1
      if n == i then return name end
    end
  end
  return nil
end
function GetTime() return __now end
function time() return __now end
function IsInGroup() return true end
function IsInRaid() return false end
function GetNumGroupMembers()
  local n = 0
  for _ in pairs(__groupMembers) do n = n + 1 end
  return n
end
function UnitInParty(name) return __groupMembers[name] == true end
function UnitInRaid(name) return false end
function UnitIsConnected(unit)
  local name = UnitName(unit)
  if name and __connected[name] == false then return false end
  return true
end
function PlaySoundFile() end
function SendChatMessage() end
function GetRealmName() return "TestRealm" end
function date(fmt, t) return os.date(fmt, t) end
StaticPopupDialogs = {}
function StaticPopup_Show() end

-- Frames: a universal mock whose every missing method exists and whose
-- factory methods (CreateFontString etc.) return another mock
local function mockobj()
  local t = {}
  setmetatable(t, { __index = function(_, k)
    return function(...) return mockobj() end
  end })
  return t
end
function CreateFrame() return mockobj() end

__afterQueue = {}
C_Timer = {
  After = function(sec, cb) table.insert(__afterQueue, cb) end,
  NewTicker = function(interval, cb, iters) return { Cancel = function() end } end,
  NewTimer = function(sec, cb) return { Cancel = function() end } end,
}

local AceCommStub = {
  RegisterComm = function() end,
  SendCommMessage = function(self, prefix, msg, dist, target)
    table.insert(__sent, { prefix = prefix, msg = msg, dist = dist, target = target })
  end,
}
-- Functional round-trip: Serialize hands back a registry key, Deserialize
-- resolves it, so HandleFullState can be driven end-to-end in tests
__serialized = {}
__serialCount = 0
local AceSerializerStub = {
  Serialize = function(self, t)
    __serialCount = __serialCount + 1
    local key = "SER" .. __serialCount
    __serialized[key] = t
    return key
  end,
  Deserialize = function(self, s)
    if __serialized[s] ~= nil then return true, __serialized[s] end
    return false
  end,
}
function LibStub(name)
  if name == "AceComm-3.0" then return AceCommStub end
  if name == "AceSerializer-3.0" then return AceSerializerStub end
  return {}
end

ChairfacesCasino = {}
local BJ = ChairfacesCasino
__prints = {}
function BJ:Print(msg) table.insert(__prints, tostring(msg)) end
function BJ:Debug(msg) end
function BJ:CreateGameLink(game, text) return text end
function BJ:OnPeerVersion() end
function BJ:VersionsCompatible() return true end
BJ.version = "2.5.2"

BJ.Leaderboard = {
    StartSession = function() end,
    EndSession = function() end,
    RecordHandResult = function() end,
}
BJ.GameHistory = setmetatable({}, { __index = function()
    return function() end
end })

-- Fake Blackjack game state: just enough surface for the multiplayer
-- module's stand/ante/reset paths
BJ.GameState = {
  PHASE = {
    IDLE = "idle", WAITING_FOR_PLAYERS = "waiting", DEALING = "dealing",
    PLAYER_TURN = "player_turn", DEALER_TURN = "dealer_turn",
    SETTLEMENT = "settlement",
  },
  phase = "idle",
  playerOrder = {},
  currentPlayerIndex = 1,
  players = {},
  stood = {},
  anted = {},
}
function BJ.GameState:PlayerStand(name)
  table.insert(self.stood, name)
  self.phase = self.PHASE.SETTLEMENT
  return true
end
function BJ.GameState:PlayerAnte(name, amount)
  table.insert(self.anted, name)
  return true
end
function BJ.GameState:ShouldDealerPlay() return false end
function BJ.GameState:Reset()
  self.phase = self.PHASE.IDLE
  self.playerOrder = {}
  self.players = {}
end
function BJ.GameState:LogAction() end
"""


BLACKJACK_FILES = (r"Core\StateSync.lua", r"Core\GameComm.lua",
                   r"Games\Blackjack\Multiplayer.lua")
HILO_FILES = (r"Core\StateSync.lua", r"Core\GameComm.lua",
              r"Games\HiLo\HiLoState.lua", r"Games\HiLo\HiLoMultiplayer.lua")
BINGO_FILES = (r"Core\StateSync.lua", r"Core\GameComm.lua", r"Core\CardLib.lua",
               r"Games\Bingo\BingoState.lua", r"Games\Bingo\BingoMultiplayer.lua")
LD_FILES = (r"Core\StateSync.lua", r"Core\GameComm.lua", r"Core\CardLib.lua",
            r"Games\LiarsDice\LiarsDiceState.lua",
            r"Games\LiarsDice\LiarsDiceMultiplayer.lua")


def make_runtime(player, group=(), offline=(), files=BLACKJACK_FILES):
    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(STUBS.replace("%PLAYER%", player))
    for name in group:
        lua.execute('__groupMembers["%s"] = true' % name)
    for name in offline:
        lua.execute('__connected["%s"] = false' % name)
    for f in files:
        src = open(os.path.join(ADDON_DIR, f), encoding="utf-8").read()
        lua.execute(src)
    return lua


passed = failed = 0


def check(desc, ok):
    global passed, failed
    if ok:
        passed += 1
        print("PASS  " + desc)
    else:
        failed += 1
        print("FAIL  " + desc)


# ---------------------------------------------------------------- watchdog
lua = make_runtime("Host", group=("Dave",))
lua.execute("""
local BJ = ChairfacesCasino
MP = BJ.Multiplayer
MP.isHost = true
MP.currentHost = "Host"
local GS = BJ.GameState
GS.phase = GS.PHASE.PLAYER_TURN
GS.playerOrder = { "Dave", "Host" }
GS.currentPlayerIndex = 1
GS.players = { Dave = { hands = {{}}, activeHandIndex = 1, outcomes = {}, bets = {}, payouts = {} } }
""")

lua.execute("__now = 1000; MP:ActorWatchTick()")
check("watchdog tracks the actor without forcing",
      lua.eval('MP.actorWatchName == "Dave"')
      and lua.eval("#ChairfacesCasino.GameState.stood == 0"))

lua.execute("__now = 1100; MP:ActorWatchTick()")
check("watchdog quiet before turn limit + grace",
      lua.eval("#ChairfacesCasino.GameState.stood == 0"))

lua.execute("__now = 1151; MP:ActorWatchTick()")
check("stalled connected actor is force-stood after limit+grace",
      lua.eval('ChairfacesCasino.GameState.stood[1] == "Dave"')
      and lua.eval("MP.actorWatchName == nil"))
lua.execute("""
__forcedNotice = false
for _, m in ipairs(__sent) do
    if m.msg:find("WDFORCE|Dave", 1, true) then __forcedNotice = true end
end
""")
check("a WDFORCE notice is broadcast so the table knows why",
      lua.eval("__forcedNotice == true"))

# the notice prints on receiving clients (central GameComm intercept)
lua.execute("""
MP.currentHost = "Alice"
__prints = {}
MP:OnCommReceived("CCBlackjack", "WDFORCE|Dave|left", "PARTY", "Alice-SomeRealm")
__noticePrinted = false
for _, p in ipairs(__prints) do
    if p:find("Dave", 1, true) and p:find("left the group", 1, true) then
        __noticePrinted = true
    end
end
__prints = {}
MP:OnCommReceived("CCBlackjack", "WDFORCE|Dave|left", "PARTY", "Mallory-SomeRealm")
__forgedPrinted = #__prints > 0
MP.currentHost = "Host"
""")
check("WDFORCE from the host prints the reason on clients",
      lua.eval("__noticePrinted == true"))
check("WDFORCE from a non-host is ignored",
      lua.eval("__forgedPrinted == false"))

# leaver fast path: the settle window measures from DEPARTURE, not turn start
lua.execute("""
local GS = ChairfacesCasino.GameState
GS.stood = {}
GS.phase = GS.PHASE.PLAYER_TURN
MP.actorForcedName = nil
__groupMembers["Dave"] = nil    -- Dave left the group
__now = 2000; MP:ActorWatchTick()   -- tracks Dave
__now = 2006; MP:ActorWatchTick()   -- first tick seeing him gone
""")
check("group-leaver not forced the tick they are first seen gone",
      lua.eval("#ChairfacesCasino.GameState.stood == 0"))
lua.execute("__now = 2011; MP:ActorWatchTick()")
check("group-leaver not forced before the settle delay elapses from departure",
      lua.eval("#ChairfacesCasino.GameState.stood == 0"))
lua.execute("__now = 2016; MP:ActorWatchTick()")
check("group-leaver force-stood once the settle delay has passed since departure",
      lua.eval('ChairfacesCasino.GameState.stood[1] == "Dave"'))

# multi-hand follow-up: a player already force-acted gets a short window,
# not another full 150s clock
lua.execute("""
local GS = ChairfacesCasino.GameState
GS.stood = {}
GS.phase = GS.PHASE.PLAYER_TURN
__groupMembers["Dave"] = true   -- in group, just disconnected (150s path)
MP.actorForcedName = nil
MP.actorWatchName = nil
__now = 5000; MP:ActorWatchTick()   -- track
__now = 5151; MP:ActorWatchTick()   -- first force (held past 150)
GS.phase = GS.PHASE.PLAYER_TURN     -- same player's next split hand
__now = 5156; MP:ActorWatchTick()   -- re-tracks with backdated clock
__now = 5161; MP:ActorWatchTick()
""")
check("first force fired and follow-up not instant",
      lua.eval("#ChairfacesCasino.GameState.stood == 1"))
lua.execute("__now = 5176; MP:ActorWatchTick()")
check("same player's next hand forced within the short follow-up window",
      lua.eval("#ChairfacesCasino.GameState.stood == 2"))

# paused / inert cases
lua.execute("""
local GS = ChairfacesCasino.GameState
GS.stood = {}
GS.phase = GS.PHASE.PLAYER_TURN
__groupMembers["Dave"] = true
MP.hostDisconnected = true
__now = 3000; MP:ActorWatchTick()
__now = 3500; MP:ActorWatchTick()
""")
check("watchdog paused during host recovery",
      lua.eval("#ChairfacesCasino.GameState.stood == 0"))
lua.execute("""
MP.hostDisconnected = false
ChairfacesCasino.TestMode = { enabled = true }
__now = 4000; MP:ActorWatchTick()
__now = 4500; MP:ActorWatchTick()
""")
check("watchdog inert in test mode",
      lua.eval("#ChairfacesCasino.GameState.stood == 0"))
lua.execute("""
ChairfacesCasino.TestMode = nil
MP.isHost = false
__now = 5000; MP:ActorWatchTick()
__now = 5500; MP:ActorWatchTick()
""")
check("watchdog inert on non-host clients",
      lua.eval("#ChairfacesCasino.GameState.stood == 0"))

# ------------------------------------------------- sender filter (client)
lua = make_runtime("Me", group=("Alice", "Bob"), offline=("Alice",))
lua.execute("""
local BJ = ChairfacesCasino
MP = BJ.Multiplayer
MP.isHost = false
MP.currentHost = "Alice"
local GS = BJ.GameState
GS.phase = GS.PHASE.PLAYER_TURN
GS.playerOrder = { "Me", "Bob" }
""")

# forged takeover: sender doesn't match its own claim
lua.execute('MP:HandleSyncState("Mallory", {"BJSYNC","HOST_RECOVERY_START","5","Bob","Alice"})')
check("forged HOST_RECOVERY_START (sender != claimed temp) rejected",
      lua.eval("MP.hostDisconnected ~= true"))

# legit takeover from the temp host
lua.execute('MP:HandleSyncState("Bob", {"BJSYNC","HOST_RECOVERY_START","5","Bob","Alice"})')
check("temp host's HOST_RECOVERY_START accepted with correct offsets",
      lua.eval("MP.hostDisconnected == true")
      and lua.eval('MP.temporaryHost == "Bob"')
      and lua.eval('MP.originalHost == "Alice"'))

# tick from the temp host updates the countdown baseline
lua.execute("MP.recoveryStartTime = nil")
lua.execute('MP:HandleSyncState("Bob", {"BJSYNC","HOST_RECOVERY_TICK","6","95"})')
check("temp host's HOST_RECOVERY_TICK accepted",
      lua.eval("MP.recoveryStartTime ~= nil"))

# void from a bystander is ignored; from the temp host it lands
lua.execute('MP:HandleSyncState("Mallory", {"BJSYNC","GAME_VOIDED","7","forged"})')
check("GAME_VOIDED from a bystander rejected",
      lua.eval("MP.hostDisconnected == true"))
lua.execute('MP:HandleSyncState("Bob", {"BJSYNC","GAME_VOIDED","7","Host did not return"})')
check("GAME_VOIDED from the temp host resets the table",
      lua.eval("MP.hostDisconnected ~= true")
      and lua.eval('ChairfacesCasino.GameState.phase == "idle"'))

# ordinary state traffic still host-only
lua.execute("""
local GS = ChairfacesCasino.GameState
GS.phase = GS.PHASE.WAITING_FOR_PLAYERS
GS.anted = {}
MP.currentHost = "Alice"
""")
lua.execute('MP:HandleSyncState("Mallory", {"BJSYNC","ANTE","1","Zed","10"})')
check("state sync from a non-host still rejected",
      lua.eval("#ChairfacesCasino.GameState.anted == 0"))
lua.execute('MP:HandleSyncState("Alice", {"BJSYNC","ANTE","1","Zed","10"})')
check("state sync from the host still accepted",
      lua.eval('ChairfacesCasino.GameState.anted[1] == "Zed"'))

# HOST_RESTORED from the temp host clears the pause
lua.execute("""
MP.hostDisconnected = true
MP.temporaryHost = "Bob"
MP.originalHost = "Alice"
""")
lua.execute('MP:HandleSyncState("Bob", {"BJSYNC","HOST_RESTORED","8","Alice"})')
check("HOST_RESTORED from the temp host clears recovery",
      lua.eval("MP.hostDisconnected == false"))

# ------------------------------------- version adoption on host reclaim
lua = make_runtime("Me", group=("Bob",))
lua.execute("""
local BJ = ChairfacesCasino
MP = BJ.Multiplayer
MP.hostDisconnected = true
MP.originalHost = "Me"
MP.temporaryHost = "Bob"
BJ.StateSync.versions.blackjack = { current = 3, lastReceived = 20 }
MP:RestoreOriginalHost()
""")
check("reclaiming host adopts the advanced version stream",
      lua.eval("ChairfacesCasino.StateSync.versions.blackjack.current == 20")
      and lua.eval("MP.isHost == true"))

# ---------------- HandleFullState: generic recovery clear + version resume
lua = make_runtime("Me", group=("Alice", "Bob"))
lua.execute("""
local BJ = ChairfacesCasino
-- A GameComm-embedded stand-in for PokerMultiplayer (real methods, fake game)
BJ.PokerMultiplayer = {}
BJ.GameComm:Embed(BJ.PokerMultiplayer, {
  prefix = "CCPoker", game = "poker", displayName = "5 Card Stud",
  MSG = { SYNC_STATE = "PSYNC" },
  getState = function() return BJ.PokerState end,
  getUI = function() return nil end,
})
BJ.PokerState = { phase = "betting", players = {}, playerOrder = {} }

local SS = BJ.StateSync
local Ser = LibStub("AceSerializer-3.0")
local PM = BJ.PokerMultiplayer

-- (1) Non-host client paused in recovery receives the temp host's dump:
-- the pause must clear generically in HandleFullState
PM.hostDisconnected = true
PM.originalHost = "Alice"
PM.temporaryHost = "Bob"
PM.currentHost = "Alice"
SS.versions.poker = { current = 3, lastReceived = 0 }
__applied1 = SS:HandleFullState("poker", Ser:Serialize({
  version = 20, game = "poker",
  data = { phase = "betting", hostName = "Alice",
           players = {}, playerOrder = {}, cardsRemaining = 40 },
}))
__currentAfterClient = SS.versions.poker.current
""")
check("HandleFullState applies the dump on a paused client",
      lua.eval("__applied1 == true"))
check("HandleFullState clears recovery generically so the timer cannot void",
      lua.eval("ChairfacesCasino.PokerMultiplayer.hostDisconnected == false")
      and lua.eval("ChairfacesCasino.PokerMultiplayer.temporaryHost == nil"))
check("a non-host applier does not touch its own version counter",
      lua.eval("__currentAfterClient == 3"))

lua.execute("""
local BJ = ChairfacesCasino
local SS = BJ.StateSync
local Ser = LibStub("AceSerializer-3.0")
local PM = BJ.PokerMultiplayer

-- (2) The RECLAIMING HOST receives the dump (hostName == me): the version
-- stream must resume from the dump so its next broadcast isn't discarded.
-- A YOU_ARE_PLAYING confirmation is also pending, so the game window the
-- player was seated at must reopen (rejoin auto-open).
__now = __now + 10   -- past the sync cooldown
PM.hostDisconnected = true
PM.temporaryHost = "Bob"
__opened = nil
BJ.CloseAllGameWindows = function() end
BJ.OpenGameWindow = function(self, game) __opened = game end
SS.pendingAutoOpen.poker = GetTime()
__applied2 = SS:HandleFullState("poker", Ser:Serialize({
  version = 21, game = "poker",
  data = { phase = "betting", hostName = "Me",
           players = {}, playerOrder = {}, cardsRemaining = 40 },
}))
""")
check("reclaiming host resumes the version stream from the dump",
      lua.eval("__applied2 == true")
      and lua.eval("ChairfacesCasino.PokerMultiplayer.isHost == true")
      and lua.eval("ChairfacesCasino.StateSync.versions.poker.current == 21"))
check("rejoin auto-open pops the window the player was seated at",
      lua.eval('__opened == "poker"')
      and lua.eval("ChairfacesCasino.StateSync.pendingAutoOpen.poker == nil"))

# a plain broadcast sync (no pending confirmation) must NOT pop windows
lua.execute("""
local BJ = ChairfacesCasino
local Ser = LibStub("AceSerializer-3.0")
__now = __now + 10
__opened = nil
__applied3 = BJ.StateSync:HandleFullState("poker", Ser:Serialize({
  version = 22, game = "poker",
  data = { phase = "betting", hostName = "Me",
           players = {}, playerOrder = {}, cardsRemaining = 39 },
}))
""")
check("ordinary broadcast syncs never pop windows",
      lua.eval("__applied3 == true") and lua.eval("__opened == nil"))

# shared fake-flag parser: the "0" case must be false, never nil
lua.execute("""
local GC = ChairfacesCasino.GameComm
__pf1 = GC.ParseFakeFlag("1")
__pf0 = GC.ParseFakeFlag("0")
__pfn = GC.ParseFakeFlag(nil)
""")
check("ParseFakeFlag: '1'=true, '0'=false (not nil), missing=nil",
      lua.eval("__pf1 == true")
      and lua.eval("__pf0 == false")
      and lua.eval("__pfn == nil"))

# ------------------------------------------- High-Lo host-transfer epochs
lua = make_runtime("Cara", group=("Alice", "Bob"), offline=("Alice",),
                   files=HILO_FILES)
lua.execute("""
local BJ = ChairfacesCasino
HLM = BJ.HiLoMultiplayer
HL = BJ.HiLoState
HL.phase = HL.PHASE.ROLLING
HL.playerOrder = { "Alice", "Bob", "Cara" }
HL.hostName = "Alice"
HLM.isHost = false
HLM.currentHost = "Alice"
HLM.hostEpoch = 1
HLM:StartHostRecovery()
""")
check("hilo: transfer elects the first connected player and bumps the epoch",
      lua.eval('HLM.currentHost == "Bob"')
      and lua.eval("HLM.hostEpoch == 2")
      and lua.eval('HL.hostName == "Bob"'))

lua.execute('HLM:HandleHostTransfer("Alice", {"HOST_TRANSFER","Alice","Bob","1"})')
check("hilo: stale-epoch transfer from the old host is ignored",
      lua.eval('HLM.currentHost == "Bob"') and lua.eval("HLM.hostEpoch == 2"))

lua.execute('HLM:HandleHostTransfer("Zed", {"HOST_TRANSFER","Zed","Bob","2"})')
check("hilo: same-epoch clash keeps the lexicographically lower host",
      lua.eval('HLM.currentHost == "Bob"'))

lua.execute('HLM:HandleHostTransfer("Dan", {"HOST_TRANSFER","Dan","Bob"})')
check("hilo: legacy (no-epoch) transfer still accepted as one more transfer",
      lua.eval('HLM.currentHost == "Dan"') and lua.eval("HLM.hostEpoch == 3"))

# stale ex-host demotion
lua = make_runtime("Old", group=("New",), files=HILO_FILES)
lua.execute("""
local BJ = ChairfacesCasino
HLM = BJ.HiLoMultiplayer
HL = BJ.HiLoState
HL.phase = HL.PHASE.ROLLING
HL.hostName = "Old"
HLM.isHost = true
HLM.currentHost = "Old"
HLM.hostEpoch = 1
HLM.rollingTimerHandle = { Cancel = function() end }
HLM:HandleHostTransfer("New", {"HOST_TRANSFER","New","Old","2"})
""")
check("hilo: stale ex-host stands down on a higher-epoch transfer",
      lua.eval("HLM.isHost == false")
      and lua.eval('HLM.currentHost == "New"')
      and lua.eval("HLM.hostEpoch == 2")
      and lua.eval("HLM.rollingTimerHandle == nil"))

# active host re-asserts against a rival's authoritative broadcast
lua = make_runtime("New", group=("Old",), files=HILO_FILES)
lua.execute("""
local BJ = ChairfacesCasino
HLM = BJ.HiLoMultiplayer
HL = BJ.HiLoState
HL.phase = HL.PHASE.ROLLING
HL.hostName = "New"
HLM.isHost = true
HLM.currentHost = "New"
HLM.hostEpoch = 2
__sent = {}
HLM:RouteMessage("SETTLE", "Old", "Old", {"SETTLE","A","90","B","10","80"})
__reasserted = false
for _, m in ipairs(__sent) do
    if m.msg:find("HOST_TRANSFER|New", 1, true) then __reasserted = true end
end
""")
check("hilo: active host re-asserts its epoch against a rival broadcast",
      lua.eval("__reasserted == true"))
check("hilo: the rival's settlement was not applied",
      lua.eval("HL.phase == HL.PHASE.ROLLING"))

# --------------------------- fake-play terms survive a High-Lo transfer
lua = make_runtime("Bob", group=("Alice", "Cara"), files=HILO_FILES)
lua.execute("""
local BJ = ChairfacesCasino
HL = BJ.HiLoState
BJ.DebtLedger = {
    IsFakePlay = function() return false end,
    RecordDebt = function(self, game, debtor, creditor, amount, fakePlay)
        __lastFP = fakePlay
        __recorded = true
    end,
}
HL.hostName = "Bob"      -- we are the TRANSFERRED host
HL.players = {}
HL.opener = "Alice"      -- Alice opened the table with fake play ON
HL.fakePlay = true
__lastFP = "unset"
HL:FinalizeSettlement("Alice", 95, "Cara", 10)
""")
check("hilo: transferred host records under the table's opening terms",
      lua.eval("__lastFP == true"))
lua.execute("""
HL.opener = "Bob"        -- we opened it ourselves: the terms captured at
                         -- open still rule - a mid-game toggle is ignored
__lastFP = "unset"
HL:FinalizeSettlement("Alice", 95, "Cara", 10)
""")
check("hilo: the opener records under the terms it opened with, not its live toggle",
      lua.eval("__lastFP == true"))
lua.execute("""
HL.opener = "Alice"
HL.fakePlay = nil        -- legacy (pre-2.5.2) opener: terms unknown
__lastFP = "unset"
HL:FinalizeSettlement("Alice", 95, "Cara", 10)
""")
check("hilo: unknown legacy terms fall back to the recorder's live setting",
      lua.eval("__lastFP == nil"))
lua.execute("""
local HLM = ChairfacesCasino.HiLoMultiplayer
HLM:HandleTableOpen("Alice", {"OPEN","100","0","2.5.2","0"})
""")
check("hilo: an explicitly REAL table ('0') parses to false, not nil",
      lua.eval("ChairfacesCasino.HiLoState.fakePlay == false"))
lua.execute("""
HL = ChairfacesCasino.HiLoState
HL.hostName = "Bob"      -- transferred to us
__lastFP = "unset"
HL:FinalizeSettlement("Alice", 95, "Cara", 10)
""")
check("hilo: migrated host passes explicit REAL terms through to the ledger",
      lua.eval("__lastFP == false"))

# --------------------------- fake-play terms survive Bingo caller migration
lua = make_runtime("Cara", group=("Alice", "Bob"), files=BINGO_FILES)
lua.execute("""
local BJ = ChairfacesCasino
BM = BJ.BingoMultiplayer
BS = BJ.BingoState
BJ.DebtLedger = {
    IsFakePlay = function() return false end,
    RecordNets = function(self, game, nets, fakePlay)
        __lastFP = fakePlay
    end,
}
BM:HandleTableOpen("Alice", {"BOPEN","5","12345","2.5.2","1"})
""")
check("bingo: TABLE_OPEN carries the opener's fake-play terms",
      lua.eval("BS.fakePlay == true")
      and lua.eval('BS.opener == "Alice"')
      and lua.eval("BM.hostEpoch == 1"))
lua.execute("""
BS:AddPlayer("Bob")
BS:AddPlayer("Cara")
BS.hostName = "Cara"     -- caller migrated to us
__lastFP = "unset"
BS:FinalizeSettlement({"Bob"}, 15, 15)
""")
check("bingo: migrated caller records under the table's opening terms",
      lua.eval("__lastFP == true"))
lua.execute("""
BS.phase = BS.PHASE.DRAWING   -- re-arm settlement
BS.opener = "Cara"            -- we opened it ourselves: terms captured at
                              -- open still rule - a mid-game toggle is ignored
__lastFP = "unset"
BS:FinalizeSettlement({"Bob"}, 15, 15)
""")
check("bingo: the opener records under the terms it opened with, not its live toggle",
      lua.eval("__lastFP == true"))
lua.execute('BM:HandleTableOpen("Alice", {"BOPEN","5","777","2.5.2","0"})')
check("bingo: an explicitly REAL table ('0') parses to false, not nil",
      lua.eval("BS.fakePlay == false"))
lua.execute("""
BS:AddPlayer("Cara")
BS.hostName = "Cara"     -- caller migrated to us
__lastFP = "unset"
BS:FinalizeSettlement({"Alice"}, 10, 10)
""")
check("bingo: migrated caller passes explicit REAL terms through to the ledger",
      lua.eval("__lastFP == false"))

# ------------------- fake-play terms survive a Liar's Dice host migration
lua = make_runtime("Cara", group=("Alice", "Bob"), files=LD_FILES)
lua.execute("""
local BJ = ChairfacesCasino
LDM = BJ.LiarsDiceMultiplayer
LD = BJ.LiarsDiceState
BJ.DebtLedger = {
    IsFakePlay = function() return false end,
    RecordDebts = function(self, game, debts, fakePlay)
        __lastFP = fakePlay
        __debtCount = #debts
    end,
}
LDM:HandleTableOpen("Alice", {"LDOPEN","25","2.5.2","1","3","1"})
""")
check("liarsdice: TABLE_OPEN carries the opener's fake-play terms",
      lua.eval("LD.fakePlay == true")
      and lua.eval('LD.opener == "Alice"')
      and lua.eval("LDM.hostEpoch == 1"))
lua.execute("""
LD:AddPlayer("Bob")
LD:AddPlayer("Cara")
LD.hostName = "Cara"     -- host migrated to us
__lastFP = "unset"
LD:FinalizeSettlement("Bob")
""")
check("liarsdice: migrated host records under the table's opening terms",
      lua.eval("__lastFP == true") and lua.eval("__debtCount == 2"))
lua.execute("""
LD.phase = LD.PHASE.BIDDING   -- re-arm settlement
LD.opener = "Cara"            -- we opened it ourselves: terms captured at
                              -- open still rule - a mid-game toggle is ignored
__lastFP = "unset"
LD:FinalizeSettlement("Bob")
""")
check("liarsdice: the opener records under the terms it opened with, not its live toggle",
      lua.eval("__lastFP == true"))
lua.execute('LDM:HandleTableOpen("Alice", {"LDOPEN","25","2.5.2","1","3","0"})')
check("liarsdice: an explicitly REAL table ('0') parses to false, not nil",
      lua.eval("LD.fakePlay == false"))
lua.execute("""
LD:AddPlayer("Bob")
LD:AddPlayer("Cara")
LD.hostName = "Cara"     -- host migrated to us
__lastFP = "unset"
LD:FinalizeSettlement("Bob")
""")
check("liarsdice: migrated host passes explicit REAL terms through to the ledger",
      lua.eval("__lastFP == false"))

# --------------------------- real DebtLedger honors the explicit override
lua = make_runtime("Alice", group=("Bob", "Cara"),
                   files=(r"Core\GameComm.lua", r"Core\DebtLedger.lua"))
lua.execute("""
local BJ = ChairfacesCasino
ChairfacesCasinoDB = {}
BJ.DebtLedger:Initialize()
BJ.db.settings = BJ.db.settings or {}
BJ.db.settings.fakePlay = true   -- OUR toggle is fun...

-- ...but the table's terms say real: the debt must land
BJ.DebtLedger:RecordDebts("bingo",
    { { debtor = "Bob", creditor = "Cara", amount = 10 } }, false)
__pairsAfterReal = 0
for _ in pairs(ChairfacesCasinoDB.debtLedger.pairs) do
    __pairsAfterReal = __pairsAfterReal + 1
end

-- nil override = live setting (fun): nothing new recorded
BJ.DebtLedger:RecordDebts("hilo",
    { { debtor = "Bob", creditor = "Alice", amount = 5 } })
__pairsAfterFun = 0
for _ in pairs(ChairfacesCasinoDB.debtLedger.pairs) do
    __pairsAfterFun = __pairsAfterFun + 1
end
""")
check("debtledger: explicit real-terms override beats the local fun toggle",
      lua.eval("__pairsAfterReal == 1"))
check("debtledger: nil override still honors the local fun toggle",
      lua.eval("__pairsAfterFun == 1"))

print()
if failed:
    print("%d FAILED, %d passed" % (failed, passed))
    raise SystemExit(1)
print("All %d checks passed." % passed)
