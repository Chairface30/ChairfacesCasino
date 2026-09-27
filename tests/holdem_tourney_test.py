"""Tournament-mode tests for HoldemState + PokerEngine.

Drives the state machine directly (no networking): buy-in lock, no
mid-entry, the shortest-stack hand cap, chip movement, elimination,
forfeit, champion detection and the single end-of-tournament debt record.
Run: python tests/holdem_tourney_test.py  (pip install lupa)
"""
import lupa
import os

ADDON_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

STUBS = r"""
unpack = unpack or table.unpack
function strsplit(delim, s)
  local out, from = {}, 1
  while true do
    local i = string.find(s, delim, from, true)
    if not i then out[#out+1] = string.sub(s, from) break end
    out[#out+1] = string.sub(s, from, i-1)
    from = i + #delim
  end
  return unpack(out)
end
function UnitName(u) if u == "player" then return "Host" end end
function GetRealmName() return "Realm" end
function time() return 1000 end
local function noop() end
local frameMT = { __index = function() return noop end }
function CreateFrame() return setmetatable({}, frameMT) end
C_Timer = { After = function(s, cb) end, NewTicker = function() return setmetatable({}, frameMT) end }
function GetTime() return 0 end

__nets = {}          -- captured DebtLedger:RecordNets calls
__lb = {}            -- captured leaderboard records
ChairfacesCasino = {
  Print = function() end,
  Debug = function() end,
  DebtLedger = { RecordNets = function(self, game, nets)
    local copy = {}
    for k, v in pairs(nets) do copy[k] = v end
    table.insert(__nets, { game = game, nets = copy })
  end },
  Leaderboard = { RecordHandResult = function(self, game, name, net, outcome)
    table.insert(__lb, { game = game, name = name, net = net, outcome = outcome })
  end, StartSession = function() end, EndSession = function() end },
}
"""

lua = lupa.LuaRuntime()
lua.execute(STUBS)
for f in (r"Core\CardLib.lua", r"Core\PokerEngine.lua", r"Games\Holdem\HoldemState.lua"):
    lua.execute(open(os.path.join(ADDON_DIR, f), encoding="utf-8").read())

lua.execute("PS = ChairfacesCasino.HoldemState")
ev = lua.eval
run = lua.execute

passed = 0


def check(label, cond, detail=""):
    global passed
    if cond:
        passed += 1
        print("PASS", label)
    else:
        print("FAIL", label, detail)
        raise SystemExit(1)


# betting driver: act for whoever is current until the round resolves
run(r"""
function drive(actions)
  -- actions[name] = {"fold"} or {"call"} or {"raise", n} ; default check/call
  local guard = 0
  while PS.phase == PS.PHASE.BETTING do
    guard = guard + 1
    if guard > 200 then error("betting loop stuck") end
    local name = PS:GetCurrentPlayer()
    local act = actions and actions[name]
    local ok, res
    if act and act[1] == "fold" then ok, res = PS:PlayerFold(name)
    elseif act and act[1] == "raise" then ok, res = PS:PlayerRaise(name, act[2])
      if not ok then error("raise refused: " .. tostring(res)) end
      actions[name] = nil   -- raise once, then call/check
    else
      local p = PS.players[name]
      if PS.currentBet - (p.currentBet or 0) > 0 then ok = PS:PlayerCall(name)
      else ok = PS:PlayerCheck(name) end
    end
  end
end

function playStreets(actions)
  PS:StartBettingRound(1)
  drive(actions)
  for street = 2, 4 do
    if PS.phase == PS.PHASE.DEALING then
      local n = (street == 2) and 3 or 1
      for i = 1, n do PS:DealCommunityCard() end
      PS:StartBettingRound(street)
      drive(actions)
    end
  end
end
""")

# ---- setup: 10g buy-in, 30-chip stacks, blinds 10/20, 3 players ----
run('PS:StartRound("Host", 10, 20, 1000000, 4242)')
run('PS:StartTourney(10, 30)')
run('PS:PlayerJoin("Host"); PS:PlayerJoin("Alice"); PS:PlayerJoin("Bob")')
check("buy-in seats all three stacks",
      ev('PS.tourney.chips.Host == 30 and PS.tourney.chips.Alice == 30 and PS.tourney.chips.Bob == 30'))

# ---- hand 1: everyone folds to the big blind (deterministic) ----
run('PS:StartDeal(); PS:PostBlinds()')
check("no mid-entry once the first hand is dealt",
      not ev('(PS:PlayerJoin("Latecomer"))'))
run(r"""
for i = 1, 2 do
  for _, name in ipairs(PS.playerOrder) do PS:DealCardToPlayer(name, false) end
end
""")
# dealer=Host(1), SB=Alice, BB=Bob; preflop first to act = Host
run('playStreets({ Host = {"fold"}, Alice = {"fold"} })')
check("fold-out hand settles", ev('PS.phase == PS.PHASE.SETTLEMENT'))
check("BB wins the blinds in chips",
      ev('PS.tourney.chips.Bob == 40 and PS.tourney.chips.Alice == 20 and PS.tourney.chips.Host == 30'))
check("nobody eliminated yet", ev('#PS.tourney.eliminated == 0'))
check("no per-hand debts in tournament (chips, not gold)", ev('#__nets == 0'))
check("no per-hand leaderboard records either", ev('#__lb == 0'))

# ---- hand 2: cap = shortest stack (Alice, 20); raise past it refused ----
run('PS:PrepareNextHand(777)')
check("all three seats survive", ev('#PS.playerOrder == 3'))
run('PS.dealerIndex = 2')   # rotate: dealer Alice, SB Bob, BB Host
run('PS:StartDeal(); PS:PostBlinds()')
check("hand cap is the shortest stack", ev('PS.tourneyHandCap == 20'))
check("BB clamped to the cap", ev('PS.currentBet == 20 and PS.pot == 30'))
run(r"""
for i = 1, 2 do
  for _, name in ipairs(PS.playerOrder) do PS:DealCardToPlayer(name, false) end
end
PS:StartBettingRound(1)
""")
cap_reject = ev(r"""
(function()
  local name = PS:GetCurrentPlayer()
  local ok, err = PS:PlayerRaise(name, 5)   -- total would pass the 20 cap
  return (not ok) and tostring(err) or "ACCEPTED"
end)()
""")
check("raise beyond the shortest stack refused", "table cap" in cap_reject, cap_reject)

# everyone calls to the cap -> showdown decides; all totals equal 20
run('drive(nil)')
run(r"""
for street = 2, 4 do
  if PS.phase == PS.PHASE.DEALING then
    local n = (street == 2) and 3 or 1
    for i = 1, n do PS:DealCommunityCard() end
    PS:StartBettingRound(street)
    drive(nil)
  end
end
""")
check("capped hand reaches settlement", ev('PS.phase == PS.PHASE.SETTLEMENT'))
total = ev('PS.tourney.chips.Host + PS.tourney.chips.Alice + PS.tourney.chips.Bob')
check("chips conserved across the hand (90 total)", total == 90, total)
check("Alice busted or doubled (she was all-in at the cap)",
      ev('PS.tourney.chips.Alice == 0 or PS.tourney.chips.Alice >= 40'))

# ---- play forward until a champion emerges ----
run(r"""
guard = 0
while not PS.tourney.champion do
  guard = guard + 1
  if guard > 60 then error("no champion after 60 hands") end
  PS:PrepareNextHand(1000 + guard)
  if #PS.playerOrder >= 2 then
    PS.dealerIndex = (guard % #PS.playerOrder) + 1
    PS:StartDeal()
    PS:PostBlinds()
    for i = 1, 2 do
      for _, name in ipairs(PS.playerOrder) do PS:DealCardToPlayer(name, false) end
    end
    playStreets(nil)   -- everyone calls/checks to showdown at the cap
  end
end
""")
champ = ev('PS.tourney.champion')
check("a champion is crowned", champ in ("Host", "Alice", "Bob"), champ)
check("champion holds every chip", ev('PS.tourney.chips["%s"]' % champ) == 90)
check("two eliminations recorded", ev('#PS.tourney.eliminated') == 2)

# ---- the single gold settlement: champion takes the whole pool ----
# pool = 3 x 10g = 30g -> champion nets +20, both runners-up net -10
check("exactly one debt record for the whole tournament", ev('#__nets == 1'))
check("debt game key is holdem", ev('__nets[1].game == "holdem"'))
champ_net = ev('__nets[1].nets["%s"]' % champ)
check("champion nets the whole pool minus their buy-in (+20g)", champ_net == 20, champ_net)
runner_nets = sorted(ev('__nets[1].nets["%s"]' % n) for n in ("Host", "Alice", "Bob") if n != champ)
check("runners-up just lose their buy-ins (-10g each)", runner_nets == [-10, -10], runner_nets)
zero = ev(r"""
(function()
  local s = 0
  for _, v in pairs(__nets[1].nets) do s = s + v end
  return s
end)()
""")
check("tournament nets are zero-sum", zero == 0, zero)
check("leaderboard recorded once per entrant", ev('#__lb') == 3)

# ---- forfeit path on a fresh tournament ----
run('PS:StartRound("Host", 10, 20, 1000000, 99)')
run('PS:StartTourney(25, 100)')
run('PS:PlayerJoin("Host"); PS:PlayerJoin("Alice")')
run('PS:StartDeal(); PS:PostBlinds()')
run('PS:TourneyForfeit("Alice")')
check("forfeit crowns the last stack standing", ev('PS.tourney.champion == "Host"'))
check("forfeited buy-in still pays the champion",
      ev('__nets[2] and __nets[2].nets.Host == 25 and __nets[2].nets.Alice == -25'))

print("\nAll %d checks passed." % passed)
