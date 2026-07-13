--[[
    Chairface's Casino - PokerState.lua
    5 Card Stud poker game logic with proper betting rounds

    Game Flow:
    1. Ante - everyone puts in initial bet
    2. Street 1 - 1 card face down (hole card), 1 card face up
    3. First betting round - lowest upcard starts (bring-in)
    4. Street 2 - 1 card face up
    5. Second betting round - highest visible hand starts
    6. Street 3 - 1 card face up
    7. Third betting round - highest visible hand starts
    8. Street 4 - 1 card face up (river)
    9. Final betting round - highest visible hand starts
    10. Showdown - reveal hole cards, best hand wins

    Deck management, betting rounds, player actions, hand evaluation,
    showdown/settlement, and history all come from PokerEngine; this file
    holds only the stud-specific rules.
]]

local BJ = ChairfacesCasino
BJ.PokerState = {}
local PS = BJ.PokerState

BJ.PokerEngine:Embed(PS, {
    game = "poker",
    debugName = "Poker",
    displayName = "5 Card Stud",
    historyKey = "pokerHistory",
    getMP = function() return BJ.PokerMultiplayer end,
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
    self.ante = 0
    self.maxRaise = 100  -- Default max raise per betting round
    self.pot = 0

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
end

-- Initialize on load
PS:Reset()

--[[
    GAME FLOW
]]

function PS:StartRound(hostName, ante, maxRaise, seed)
    self:Reset()

    self.hostName = hostName
    self.ante = ante
    self.maxRaise = maxRaise or 100
    self.phase = self.PHASE.WAITING_FOR_PLAYERS
    self.pot = 0

    self:CreateDeck(seed)

    BJ:Debug("Poker round started. Ante: " .. ante .. "g, Max Raise: " .. self.maxRaise .. "g")
end

function PS:PlayerAnte(playerName, betAmount)
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

    local neededCards = (#self.playerOrder + 1) * self.CARDS_PER_HAND
    if neededCards > self.CARDS_PER_DECK then
        return false, "Not enough cards in deck"
    end

    self.players[playerName] = {
        hand = {},
        totalBet = betAmount,
        currentBet = 0,
        folded = false,
    }
    table.insert(self.playerOrder, playerName)
    self.pot = self.pot + betAmount

    BJ:Debug(playerName .. " anted " .. betAmount .. " (pot: " .. self.pot .. ")")
    return true
end

-- Start a betting round
function PS:StartBettingRound(street)
    self.phase = self.PHASE.BETTING
    self.currentStreet = street
    self.currentBet = 0
    self.lastRaiser = nil
    self.actedThisRound = {}

    -- Reset current bets for this round
    for _, playerName in ipairs(self.playerOrder) do
        local player = self.players[playerName]
        if player then
            player.currentBet = 0
        end
    end

    local starterIndex = self:FindBettingStarter()
    self.currentPlayerIndex = starterIndex

    local starter = self.playerOrder[starterIndex]
    BJ:Debug("Betting round " .. street .. " started. First to act: " .. (starter or "?"))
    return starter
end

-- Stud first-to-act: lowest upcard opens the first street (bring-in),
-- highest visible hand opens later streets.
function PS:FindBettingStarter()
    if self.currentStreet == 1 then
        return self:FindLowestUpcardPlayer()
    else
        return self:FindHighestVisibleHandPlayer()
    end
end

function PS:FindLowestUpcardPlayer()
    local lowestValue = 999
    local lowestIndex = 1

    for i, playerName in ipairs(self.playerOrder) do
        local player = self.players[playerName]
        if player and not player.folded then
            for _, card in ipairs(player.hand) do
                if card.faceUp then
                    local value = self.RANK_VALUES[card.rank] or 0
                    if value < lowestValue then
                        lowestValue = value
                        lowestIndex = i
                    end
                    break
                end
            end
        end
    end

    return lowestIndex
end

function PS:FindHighestVisibleHandPlayer()
    local bestEval = nil
    local bestIndex = 1

    for i, playerName in ipairs(self.playerOrder) do
        local player = self.players[playerName]
        if player and not player.folded then
            local visibleCards = self:GetVisibleCards(playerName)
            local eval = self:EvaluateHand(visibleCards)

            if not bestEval or self:CompareHands(eval, bestEval) > 0 then
                bestEval = eval
                bestIndex = i
            end
        end
    end

    return bestIndex
end
