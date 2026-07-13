--[[ SigmaDerbyEngine.lua --------------------------------------------------
  Trust-independent CORE for Chair's Cup (a quinella horse-race betting game).

  Design goals:
    * BIT-IDENTICAL across every client. Given the same seed, every player's
      addon computes the exact same odds, the exact same finishing order, and
      the exact same race animation timeline. This is what makes the game
      provably fair: nobody has to trust the host's RNG.
    * NO WoW API dependency. This file runs in plain Lua 5.1 (WoW) AND in
      standalone Lua so you can unit-test the math outside the game.
        Standalone:  lua SigmaDerbyEngine.lua   -> runs a self-test
        In WoW:      the self-test auto-skips (it detects GetTime()).

  Deliberately avoids:
    * math.random  (algorithm/seeding not guaranteed identical across clients)
    * bitwise ops  (not portable between WoW's Lua 5.1 and standalone 5.3)
  Uses an LCG whose arithmetic stays < 2^53, so it's exact in IEEE doubles
  everywhere.
---------------------------------------------------------------------------]]

-- In WoW, every addon file receives (addonName, sharedTable) as vararg.
-- In standalone Lua these are nil, so the publish at the bottom no-ops and the
-- self-test still runs. This is how SigmaDerbyUI.lua gets at the engine.
local _ADDON_NAME, _NS = ...

local Engine = {}
Engine.HORSES = 5

-- The 10 quinella combos (top-2 in either order), in a fixed canonical order.
-- All clients MUST index combos identically, so this table is authoritative.
Engine.COMBOS = {
  {1,2},{1,3},{1,4},{1,5},
  {2,3},{2,4},{2,5},
  {3,4},{3,5},
  {4,5},
}

-- Win bets (back one horse to finish FIRST) share the combo bet-index
-- space: index WIN_BASE + h is a win bet on horse h. This keeps the whole
-- bet pipeline (books, network messages, settlement) index-driven.
Engine.WIN_BASE = #Engine.COMBOS

-- Odds ladder Sigma-Derby-style: raw fair odds get rounded DOWN to the nearest
-- rung (house-friendly). Min 2:1, capped at 33:1.
local LADDER = {2,3,4,5,6,8,10,12,15,20,25,33}

-- House edge applied to displayed odds (0.12 = 12% hold). Tune to taste.
Engine.HOUSE_EDGE = 0.15

-- ===================== Deterministic PRNG (portable LCG) =====================
-- Numerical Recipes constants. 1664525 * (2^32-1) ~= 7.15e15 < 2^53, so every
-- intermediate is an exact double. Identical output on WoW Lua and standalone.
local function newRNG(seed)
  local state = seed % 4294967296
  if state == 0 then state = 2654435769 end  -- avoid the zero fixed point
  local function nextU32()
    state = (1664525 * state + 1013904223) % 4294967296
    return state
  end
  return {
    u32    = nextU32,
    random = function() return nextU32() / 4294967296 end,        -- [0,1)
    int    = function(n) return (nextU32() % n) + 1 end,           -- [1,n]
  }
end
Engine.newRNG = newRNG

-- ===================== Per-race horse strengths =====================
-- Multiplicative spread so a race actually has favorites (~2:1) and longshots
-- (~99:1), not five identical horses. exp() gives the spread; k controls it.
local function rollStrengths(rng, k)
  k = k or 1.25
  local s = {}
  for i = 1, Engine.HORSES do
    s[i] = math.exp((rng.random() * 2 - 1) * k)   -- in roughly [e^-k, e^k]
  end
  return s
end

-- ===================== Closed-form combo probabilities =====================
-- Plackett-Luce: P(i first)        = s_i / S
--                P(i first,j 2nd)  = (s_i/S) * (s_j/(S - s_i))
-- P(combo {i,j} finishes top-2 either order) =
--    s_i*s_j/S * ( 1/(S-s_i) + 1/(S-s_j) )
local function comboProbabilities(strengths)
  local S = 0
  for i = 1, Engine.HORSES do S = S + strengths[i] end
  local probs = {}
  for idx, c in ipairs(Engine.COMBOS) do
    local i, j = c[1], c[2]
    local si, sj = strengths[i], strengths[j]
    probs[idx] = (si * sj / S) * (1/(S - si) + 1/(S - sj))
  end
  return probs
end

local function ladderRound(x)
  local best = LADDER[1]
  for _, rung in ipairs(LADDER) do
    if rung <= x then best = rung else break end
  end
  return best
end

-- Displayed odds "X:1" for each combo: fair (1/p), shaved by house edge,
-- snapped to the ladder. Payout to a winner = stake * (oddsToOne + 1)
-- (your stake back plus winnings), since the stake was escrowed with the host.
local function comboOdds(strengths)
  local probs = comboProbabilities(strengths)
  local odds = {}
  for idx, p in ipairs(probs) do
    local fair = 1 / p
    odds[idx] = ladderRound(fair * (1 - Engine.HOUSE_EDGE))
  end
  return odds, probs
end

-- Win odds per horse. P(h first) = s_h / S (Plackett-Luce). Heavy
-- favorites can price below the ladder's 2:1 floor, so win bets get an
-- extra even-money rung instead of overpaying the chalk.
local function winLadderRound(x)
  if x < 2 then return 1 end
  return ladderRound(x)
end

local function winOddsFor(strengths)
  local S = 0
  for i = 1, Engine.HORSES do S = S + strengths[i] end
  local odds, probs = {}, {}
  for i = 1, Engine.HORSES do
    probs[i] = strengths[i] / S
    odds[i] = winLadderRound((1 / probs[i]) * (1 - Engine.HOUSE_EDGE))
  end
  return odds, probs
end

-- ===================== Actual finishing order =====================
-- Plackett-Luce sampling WITHOUT replacement, proportional to strength,
-- driven by the shared seed -> identical result on every client.
local function sampleOrder(rng, strengths)
  local pool = {}
  for i = 1, Engine.HORSES do pool[i] = i end
  local order = {}
  while #pool > 0 do
    local total = 0
    for _, h in ipairs(pool) do total = total + strengths[h] end
    local roll = rng.random() * total
    local acc, chosen = 0, #pool
    for k, h in ipairs(pool) do
      acc = acc + strengths[h]
      if roll <= acc then chosen = k break end
    end
    order[#order+1] = pool[chosen]
    table.remove(pool, chosen)
  end
  return order  -- order[1]=winner, order[2]=place, ...
end

-- ===================== Public: build a full race from a seed =====================
-- Everything the clients need, derived from one shared seed. Separate RNG
-- streams (offset seeds) keep strength-rolling and order-sampling independent.
function Engine.buildRace(seed)
  local strengths = rollStrengths(newRNG(seed))
  local odds, probs = comboOdds(strengths)
  local wOdds, wProbs = winOddsFor(strengths)
  local order = sampleOrder(newRNG(seed + 0x5BD1E995), strengths)

  -- winning combo index (top 2, normalized to canonical low,high order)
  local a, b = order[1], order[2]
  if a > b then a, b = b, a end
  local winningCombo
  for idx, c in ipairs(Engine.COMBOS) do
    if c[1] == a and c[2] == b then winningCombo = idx break end
  end

  return {
    seed         = seed,
    strengths    = strengths,
    odds         = odds,          -- odds[comboIdx] = X (means X:1)
    probs        = probs,         -- true probability per combo (for verification)
    winOdds      = wOdds,         -- winOdds[horse] = X (means X:1, horse to WIN)
    winProbs     = wProbs,        -- true win probability per horse
    finishOrder  = order,         -- horse ids, 1st..5th
    winner       = order[1],      -- horse id that finishes first
    winningCombo = winningCombo,  -- index into Engine.COMBOS
  }
end

-- ===================== Payouts =====================
-- bets: { {player="Name", comboIdx=4, stake=50}, ... }   (stake in whatever unit)
-- comboIdx <= WIN_BASE is a quinella bet; comboIdx = WIN_BASE + h is a win
-- bet on horse h. Returns per-player total to RETURN (stake+winnings for
-- hits, 0 for misses) plus the house's net. Every client can run this and
-- check the host.
function Engine.settle(race, bets)
  local payouts, houseNet = {}, 0
  for _, bet in ipairs(bets) do
    houseNet = houseNet + bet.stake
    local ret = 0
    if bet.comboIdx > Engine.WIN_BASE then
      local horse = bet.comboIdx - Engine.WIN_BASE
      if horse == race.finishOrder[1] then
        ret = bet.stake * (race.winOdds[horse] + 1)
      end
    elseif bet.comboIdx == race.winningCombo then
      ret = bet.stake * (race.odds[bet.comboIdx] + 1)
    end
    payouts[bet.player] = (payouts[bet.player] or 0) + ret
    houseNet = houseNet - ret
  end
  return payouts, houseNet
end

-- ===================== Deterministic animation timeline (optional layer) =====
-- Produces stuttery, jostling motion that uses ~the whole race and crosses the
-- line in race.finishOrder. Returns positions[horse][tick] in [0,1].
--
-- Model: each horse has a finish tick. The WINNER crosses first, at FIRST_FRAC
-- of the race; the 5th crosses at the very end. Base progress is linear to that
-- finish tick (so it takes most of the race -- no teleporting). Overlaid noise
-- creates mid-race lead changes but is forced to zero at both the start and the
-- finish, so it can never reorder the field at the line.
function Engine.buildTimeline(race, ticks)
  ticks = ticks or 240
  local rng = newRNG(race.seed + 0x27D4EB2F)
  local N = Engine.HORSES
  local FIRST_FRAC = 0.90   -- winner crosses at 90% of the race
  local LAST_FRAC  = 1.00   -- last place crosses at the very end

  -- finish tick per horse, strictly ordered by finishing place (no jitter, so
  -- the animated order always matches the real result)
  local horseFinish = {}
  for place, horse in ipairs(race.finishOrder) do
    local frac = (N == 1) and 0 or (place - 1) / (N - 1)
    horseFinish[horse] = (FIRST_FRAC + frac * (LAST_FRAC - FIRST_FRAC)) * ticks
  end

  -- Smooth, always-forward SPEED per horse: a baseline of 1 plus a couple of
  -- slow sine components. Because speed never drops to <=0, the motion is
  -- naturally monotonic (never reverses) AND smooth (no hard stalls) -- the
  -- gentle surges and fades of a real race. We integrate speed into position,
  -- then normalise each horse to reach the line at its OWN finish tick, which
  -- keeps the outcome and finish order exactly as race.finishOrder.
  local comps = {}
  for h = 1, N do
    comps[h] = {
      { a = 0.30 + rng.random() * 0.16, c = 1.4 + rng.random() * 1.6, p = rng.random() * 6.2831853 },
      { a = 0.15 + rng.random() * 0.10, c = 4.0 + rng.random() * 3.0, p = rng.random() * 6.2831853 },
    }
  end
  local function speed(h, t)
    local s, frac = 1.0, t / ticks
    for _, cmp in ipairs(comps[h]) do
      s = s + cmp.a * math.sin(cmp.c * 6.2831853 * frac + cmp.p)
    end
    if s < 0.05 then s = 0.05 end            -- keep strictly forward
    return s
  end

  -- integrate speed -> raw cumulative distance per horse
  local raw, acc = {}, {}
  for h = 1, N do raw[h] = {}; acc[h] = 0 end
  for t = 1, ticks do
    for h = 1, N do
      acc[h] = acc[h] + speed(h, t)
      raw[h][t] = acc[h]
    end
  end

  -- normalise so each horse hits 1.0 exactly at its finish tick, then holds
  local positions = {}
  for h = 1, N do
    positions[h] = {}
    local hf = math.floor(horseFinish[h] + 0.5)
    if hf < 1 then hf = 1 elseif hf > ticks then hf = ticks end
    local denom = raw[h][hf]
    for t = 1, ticks do
      local p = raw[h][t] / denom
      if p > 1 then p = 1 end
      positions[h][t] = p
    end
  end
  return positions
end

-- ===================== Standalone self-test (auto-skips inside WoW) =========
if type(_G) == "table" and not _G.GetTime then  -- GetTime exists only in WoW
  print("== Chair's Cup engine self-test ==")
  local seed = 1234567
  local race = Engine.buildRace(seed)
  io.write("strengths: ")
  for i=1,Engine.HORSES do io.write(string.format("%.2f ", race.strengths[i])) end
  print()
  print("odds (combo -> X:1):")
  for idx, c in ipairs(Engine.COMBOS) do
    print(string.format("  %d-%d : %3d:1   (true p=%.4f)",
      c[1], c[2], race.odds[idx], race.probs[idx]))
  end
  io.write("finish order: ")
  for _,h in ipairs(race.finishOrder) do io.write(h.." ") end
  print()
  local wc = Engine.COMBOS[race.winningCombo]
  print(string.format("winning combo: %d-%d (#%d)", wc[1], wc[2], race.winningCombo))

  -- determinism check: same seed must reproduce identical winner
  local race2 = Engine.buildRace(seed)
  assert(race2.winningCombo == race.winningCombo, "NON-DETERMINISTIC!")
  print("determinism check: PASS")

  -- pacing: the winner must NOT reach the line early (teleport regression guard)
  local tl = Engine.buildTimeline(race, 240)
  local winner = race.finishOrder[1]
  local crossTick = 240
  for t = 1, 240 do if tl[winner][t] >= 0.999 then crossTick = t; break end end
  print(string.format("winner crosses at tick %d/240 (%.0f%% of race)",
    crossTick, crossTick / 240 * 100))
  assert(crossTick >= 240 * 0.8, "TELEPORT: winner finished too early")
  print("pacing check: PASS")

  -- payout demo
  local bets = {
    {player="Alice", comboIdx=race.winningCombo, stake=50},
    {player="Bob",   comboIdx=(race.winningCombo % 10)+1, stake=50},
  }
  local payouts, houseNet = Engine.settle(race, bets)
  print(string.format("Alice gets back: %d", payouts["Alice"] or 0))
  print(string.format("Bob gets back:   %d", payouts["Bob"] or 0))
  print(string.format("house net:       %d", houseNet))

  -- win bets
  print("win odds (horse -> X:1):")
  for h = 1, Engine.HORSES do
    print(string.format("  %d : %3d:1   (true p=%.4f)", h, race.winOdds[h], race.winProbs[h]))
  end
  local winnerHorse = race.finishOrder[1]
  local wbets = {
    {player="Cara", comboIdx=Engine.WIN_BASE + winnerHorse,        stake=10},
    {player="Dan",  comboIdx=Engine.WIN_BASE + race.finishOrder[2], stake=10},
  }
  local wp = Engine.settle(race, wbets)
  assert((wp["Cara"] or 0) == 10 * (race.winOdds[winnerHorse] + 1), "WIN BET PAYOUT WRONG")
  assert((wp["Dan"] or 0) == 0, "LOSING WIN BET PAID OUT")
  print("win bet check: PASS")
end

if type(_NS) == "table" then _NS.Engine = Engine end  -- WoW: hand off to UI file
return Engine
