--[[
    Chairface's Casino - HoldemState.lua
    Texas Hold'em game logic with dealer button + blinds and shared community cards

    Game Flow:
    1. Rotate dealer button; small blind and big blind post forced bets
    2. Deal 2 hole cards face down to each player
    3. Street 1 (preflop) betting - action starts left of the big blind; BB has option
    4. Street 2 (flop)  - 3 shared community cards, then betting (left of button)
    5. Street 3 (turn)  - 1 shared community card, then betting
    6. Street 4 (river) - 1 shared community card, then betting
    7. Showdown - reveal hole cards, best 5 of 7 (2 hole + 5 community) wins

    Deck management, betting rounds, player actions, hand evaluation,
    showdown/settlement, and history all come from PokerEngine; this file
    holds only the Hold'em-specific rules (blinds, button, community cards,
    best-5-of-7 evaluation).
]]

local BJ = ChairfacesCasino
BJ.HoldemState = {}
local PS = BJ.HoldemState

BJ.PokerEngine:Embed(PS, {
    game = "holdem",
    debugName = "Holdem",
    displayName = "Texas Hold'em",
    historyKey = "holdemHistory",
    getMP = function() return BJ.HoldemMultiplayer end,
})

-- Initialize/reset game state
function PS:Reset()
    self.phase = self.PHASE.IDLE
    self.deck = {}
    self.cardIndex = 1
    self.seed = nil
    self.syncedCardsRemaining = nil

    -- Host info
    self.hostName = nil
    self.smallBlind = 0
    self.bigBlind = 0
    self.maxRaise = 100  -- Default max raise per betting round
    self.pot = 0

    -- Dealer button (index into playerOrder). Rotates each hand.
    self.dealerIndex = 1

    -- Shared community cards (flop/turn/river) - the same 5 for everyone
    self.communityCards = {}

    -- Player data: { [playerName] = { hand = {}, totalBet = 0, currentBet = 0, folded = false } }
    self.players = {}
    self.playerOrder = {}

    -- Betting state
    self.currentStreet = 0
    self.currentBet = 0          -- Current bet to match this round
    self.currentPlayerIndex = 0  -- Who's turn to act
    self.lastRaiser = nil        -- Who last raised
    self.actedThisRound = {}     -- Track who has acted

    -- Results
    self.winners = {}
    self.settlements = {}

    -- Tournament mode (nil = normal cash table)
    self.tourney = nil
    self.tourneyHandCap = nil
    self.tourneyApplied = nil
end

-- Initialize on load
PS:Reset()

--[[
    GAME FLOW
]]

function PS:StartRound(hostName, smallBlind, bigBlind, maxRaise, seed)
    self:Reset()

    self.hostName = hostName
    self.smallBlind = smallBlind or 0
    self.bigBlind = bigBlind or 0
    self.maxRaise = maxRaise or 100
    self.phase = self.PHASE.WAITING_FOR_PLAYERS
    self.pot = 0

    self:CreateDeck(seed)

    BJ:Debug("Holdem round started. Blinds: " .. self.smallBlind .. "/" .. self.bigBlind .. "g, Max Raise: " .. self.maxRaise .. "g")
end

--[[
    TOURNAMENT MODE
    The table is locked to a buy-in: everyone starts with the same chip
    stack, blinds are chips, and there is NO mid-entry once the first hand
    is dealt. The table persists hand after hand until seats empty by
    elimination (stack hits zero) or forfeit; the last stack standing takes
    every buy-in in gold via the debt ledger. Betting each hand is capped
    at the shortest stack (table stakes), so the engine's single-pot
    settlement is always exact - no side pots exist by construction.
    Multi-table events run one table per PARTY (5 seats each fits a party;
    a 25-player field = 5 parties), coordinated through the LFG board -
    party-scoped comms isolate the tables with no extra sync machinery.
]]
function PS:StartTourney(buyIn, startChips)
    self.tourney = {
        buyIn = math.max(1, math.floor(tonumber(buyIn) or 10)),
        startChips = math.max(2, math.floor(tonumber(startChips) or 1000)),
        chips = {},
        entrants = {},
        eliminated = {},
        out = {},
        started = false,
        champion = nil,
    }
    -- anyone already seated (the host) buys in now
    for _, name in ipairs(self.playerOrder) do
        self.tourney.chips[name] = self.tourney.startChips
        self.tourney.entrants[name] = true
    end
end

-- Continue at the same table into a fresh hand: keep every seated player (and
-- the dealer button, which StartDeal rotates one seat on the next deal), but
-- clear all per-hand state and shuffle a fresh deck. Returns to the waiting
-- phase so the host can deal again (and late arrivals can still take a seat).
function PS:PrepareNextHand(seed)
    -- Tournament: busted (or forfeited) stacks lose their seat before the
    -- next hand; everyone else plays on with their surviving chips
    if self.tourney then
        for i = #self.playerOrder, 1, -1 do
            local name = self.playerOrder[i]
            if (self.tourney.chips[name] or 0) <= 0 then
                table.remove(self.playerOrder, i)
                self.players[name] = nil
            end
        end
        self.tourneyApplied = false
    end

    self.communityCards = {}
    self.pot = 0
    self.currentStreet = 0
    self.currentBet = 0
    self.currentPlayerIndex = 0
    self.lastRaiser = nil
    self.actedThisRound = {}
    self.winners = {}
    self.settlements = {}
    self.sbIndex = nil
    self.bbIndex = nil
    self.syncedCardsRemaining = nil

    for _, name in ipairs(self.playerOrder) do
        local p = self.players[name]
        if p then
            p.hand = {}
            p.totalBet = 0
            p.currentBet = 0
            p.folded = false
            p.allIn = false
            p.handRank = nil
            p.handName = nil
        end
    end

    self.phase = self.PHASE.WAITING_FOR_PLAYERS
    self:CreateDeck(seed)
end

-- A player takes a seat. Hold'em has no ante - money enters via the blinds at deal.
function PS:PlayerJoin(playerName)
    if self.phase ~= self.PHASE.WAITING_FOR_PLAYERS then
        return false, "Cannot join - wrong phase"
    end

    if self.players[playerName] then
        return false, "Already in this hand"
    end

    local maxPlayers = self.maxPlayers or self.MAX_PLAYERS
    if #self.playerOrder >= maxPlayers then
        return false, "Table is full (" .. maxPlayers .. " players max)"
    end

    -- Tournament: the doors lock at the first deal - no mid-entry, ever
    if self.tourney and self.tourney.started then
        return false, "Tournament already underway - no mid-entry"
    end

    -- 2 hole cards each + up to 5 community; guard against running out.
    local neededCards = (#self.playerOrder + 1) * 2 + 5
    if neededCards > self.CARDS_PER_DECK then
        return false, "Not enough cards in deck"
    end

    self.players[playerName] = {
        hand = {},
        totalBet = 0,
        currentBet = 0,
        folded = false,
    }
    table.insert(self.playerOrder, playerName)

    if self.tourney then
        self.tourney.chips[playerName] = self.tourney.startChips
        self.tourney.entrants[playerName] = true
    end

    BJ:Debug(playerName .. " joined the table (seats: " .. #self.playerOrder .. ")")
    return true
end
-- Backwards-compatible alias (some call sites/sync use the old name)
PS.PlayerAnte = PS.PlayerJoin

-- Normalize the dealer button to a valid seat index
function PS:NormalizeDealer()
    local n = #self.playerOrder
    if n == 0 then self.dealerIndex = 1; return end
    self.dealerIndex = ((self.dealerIndex - 1) % n) + 1
end

-- Post small/big blinds relative to the dealer button, before the deal.
-- Heads-up: the dealer is the small blind. Returns SB/BB seat indices.
function PS:PostBlinds()
    local n = #self.playerOrder
    if n < 2 then return end
    self:NormalizeDealer()

    local sbIndex, bbIndex
    if n == 2 then
        sbIndex = self.dealerIndex
        bbIndex = (self.dealerIndex % n) + 1
    else
        sbIndex = (self.dealerIndex % n) + 1
        bbIndex = ((self.dealerIndex + 1) % n) + 1
    end

    -- Tournament: recompute the hand cap here too - clients rebuild the
    -- hand from DEAL_START (which never runs the host's StartDeal), and
    -- the cap must clamp blinds a short stack couldn't post
    if self.tourney then
        self:RecomputeTourneyCap()
    end
    local cap = self.tourney and self.tourneyHandCap or nil

    local function post(index, amount)
        if cap then amount = math.min(amount, cap) end
        local pname = self.playerOrder[index]
        local player = self.players[pname]
        if not player then return end
        player.currentBet = amount
        player.totalBet = (player.totalBet or 0) + amount
        self.pot = self.pot + amount
    end

    post(sbIndex, self.smallBlind)
    post(bbIndex, self.bigBlind)

    -- Big blind is the amount to match preflop
    self.currentBet = cap and math.min(self.bigBlind, cap) or self.bigBlind
    self.sbIndex = sbIndex
    self.bbIndex = bbIndex

    BJ:Debug("Blinds posted: SB " .. (self.playerOrder[sbIndex] or "?") ..
        " (" .. self.smallBlind .. "g), BB " .. (self.playerOrder[bbIndex] or "?") ..
        " (" .. self.bigBlind .. "g). Pot: " .. self.pot)
end

-- Deal one shared community card (flop/turn/river)
function PS:DealCommunityCard()
    local card = self:DrawCard()
    if card then
        card.faceUp = true
        table.insert(self.communityCards, card)
    end
    return card
end

-- Start a betting round
function PS:StartBettingRound(street)
    self.phase = self.PHASE.BETTING
    self.currentStreet = street
    self.lastRaiser = nil
    self.actedThisRound = {}

    if street == 1 then
        -- Preflop: the blinds were posted before the deal. Do NOT clear their
        -- currentBet / the round's currentBet (which PostBlinds set to bigBlind),
        -- otherwise the "to call" math and the BB option break.
    else
        -- Postflop: fresh round, no outstanding bet.
        self.currentBet = 0
        for _, playerName in ipairs(self.playerOrder) do
            local player = self.players[playerName]
            if player then
                player.currentBet = 0
            end
        end
    end

    local starterIndex = self:FindBettingStarter()
    self.currentPlayerIndex = starterIndex

    local starter = self.playerOrder[starterIndex]
    BJ:Debug("Betting round " .. street .. " started. First to act: " .. (starter or "?"))
    return starter
end

-- First non-folded seat at or after startIndex (wraps around the table)
function PS:FirstActiveFrom(startIndex)
    local n = #self.playerOrder
    if n == 0 then return 1 end
    for i = 0, n - 1 do
        local idx = ((startIndex - 1 + i) % n) + 1
        local p = self.players[self.playerOrder[idx]]
        if p and not p.folded then return idx end
    end
    return startIndex
end

-- Position-based first-to-act (Texas Hold'em):
--   Preflop  -> left of the big blind (heads-up: the dealer/SB acts first)
--   Postflop -> first active seat left of the dealer button (small-blind seat)
function PS:FindBettingStarter()
    local n = #self.playerOrder
    if n == 0 then return 1 end
    self:NormalizeDealer()

    local firstSeat
    if self.currentStreet == 1 then
        if n == 2 then
            firstSeat = self.dealerIndex                 -- heads-up: dealer (SB) first preflop
        elseif self.bbIndex then
            firstSeat = (self.bbIndex % n) + 1           -- seat left of the big blind
        else
            firstSeat = ((self.dealerIndex + 2) % n) + 1 -- fallback (UTG)
        end
    else
        firstSeat = (self.dealerIndex % n) + 1           -- left of the button
    end

    return self:FirstActiveFrom(firstSeat)
end

--[[
    HAND EVALUATION (best 5 of 7)
]]

-- Showdown evaluation uses the best 5-card hand from hole + community cards
function PS:GetShowdownEval(hand)
    return self:GetBestHand(hand)
end

-- Texas Hold'em: best 5-card hand from a player's hole cards + the shared
-- community cards. Enumerates every 5-card subset and keeps the strongest,
-- reusing the engine's 5-card EvaluateHand / CompareHands.
function PS:GetBestHand(holeCards)
    local pool = {}
    for _, c in ipairs(holeCards or {}) do pool[#pool + 1] = c end
    for _, c in ipairs(self.communityCards or {}) do pool[#pool + 1] = c end

    local n = #pool
    if n <= 5 then
        return self:EvaluateHand(pool)
    end

    local best = nil
    local idx = { 1, 2, 3, 4, 5 }
    local function evalCurrent()
        local combo = {}
        for _, i in ipairs(idx) do combo[#combo + 1] = pool[i] end
        local e = self:EvaluateHand(combo)
        if not best or self:CompareHands(e, best) > 0 then best = e end
    end

    evalCurrent()
    while true do
        local k = 5
        while k >= 1 and idx[k] == n - (5 - k) do k = k - 1 end
        if k < 1 then break end
        idx[k] = idx[k] + 1
        for j = k + 1, 5 do idx[j] = idx[j - 1] + 1 end
        evalCurrent()
    end
    return best
end
