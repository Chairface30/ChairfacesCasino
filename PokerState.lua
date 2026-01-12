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
]]

local BJ = ChairfacesCasino
BJ.PokerState = {}
local PS = BJ.PokerState

-- Constants
PS.MAX_PLAYERS = 10
PS.CARDS_PER_HAND = 5
PS.CARDS_PER_DECK = 52

-- Use shared card data
PS.SUITS = { "hearts", "diamonds", "clubs", "spades" }
PS.RANKS = { "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A" }

-- Rank values for comparison (Ace high)
PS.RANK_VALUES = {
    ["2"] = 2, ["3"] = 3, ["4"] = 4, ["5"] = 5, ["6"] = 6,
    ["7"] = 7, ["8"] = 8, ["9"] = 9, ["10"] = 10,
    ["J"] = 11, ["Q"] = 12, ["K"] = 13, ["A"] = 14
}

-- Hand rankings (higher = better)
PS.HAND_RANK = {
    HIGH_CARD = 1,
    ONE_PAIR = 2,
    TWO_PAIR = 3,
    THREE_OF_A_KIND = 4,
    STRAIGHT = 5,
    FLUSH = 6,
    FULL_HOUSE = 7,
    FOUR_OF_A_KIND = 8,
    STRAIGHT_FLUSH = 9,
    ROYAL_FLUSH = 10,
}

PS.HAND_NAMES = {
    [1] = "High Card",
    [2] = "One Pair",
    [3] = "Two Pair",
    [4] = "Three of a Kind",
    [5] = "Straight",
    [6] = "Flush",
    [7] = "Full House",
    [8] = "Four of a Kind",
    [9] = "Straight Flush",
    [10] = "Royal Flush",
}

-- Game phases
PS.PHASE = {
    IDLE = "idle",
    WAITING_FOR_PLAYERS = "waiting",      -- Waiting for antes
    DEALING = "dealing",                   -- Cards being dealt (animation)
    BETTING = "betting",                   -- Betting round in progress
    SHOWDOWN = "showdown",                 -- Revealing hole cards
    SETTLEMENT = "settlement",             -- Results
}

-- Betting streets (how many up cards dealt)
PS.STREET = {
    ANTE = 0,      -- Initial ante phase
    FIRST = 1,     -- After 2 cards (1 down, 1 up) - bring-in
    SECOND = 2,    -- After 3 cards (1 down, 2 up)
    THIRD = 3,     -- After 4 cards (1 down, 3 up)
    FOURTH = 4,    -- After 5 cards (1 down, 4 up) - river
}

-- Player actions
PS.ACTION = {
    FOLD = "fold",
    CHECK = "check",
    CALL = "call",
    RAISE = "raise",
}

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
    DECK MANAGEMENT
]]

local function seededRandom(seed)
    local state = seed
    return function()
        state = (state * 1103515245 + 12345) % 2147483648
        return state / 2147483648
    end
end

-- Create and shuffle a fresh deck (1 deck per hand)
function PS:CreateDeck(seed)
    self.seed = seed or time()
    self.deck = {}
    self.cardIndex = 1
    
    for _, suit in ipairs(self.SUITS) do
        for _, rank in ipairs(self.RANKS) do
            table.insert(self.deck, {
                rank = rank,
                suit = suit,
                id = #self.deck + 1
            })
        end
    end
    
    local rng = seededRandom(self.seed)
    for i = #self.deck, 2, -1 do
        local j = math.floor(rng() * i) + 1
        self.deck[i], self.deck[j] = self.deck[j], self.deck[i]
    end
    
    BJ:Debug("Poker deck shuffled: " .. #self.deck .. " cards")
end

function PS:DrawCard()
    if self.cardIndex > #self.deck then
        BJ:Print("Error: Deck exhausted!")
        return nil
    end
    local card = self.deck[self.cardIndex]
    self.cardIndex = self.cardIndex + 1
    return card
end

function PS:GetRemainingCards()
    -- Use synced value for non-host clients
    if self.syncedCardsRemaining and BJ.PokerMultiplayer and not BJ.PokerMultiplayer.isHost then
        return self.syncedCardsRemaining
    end
    return #self.deck - self.cardIndex + 1
end

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

-- Start the deal (called by host)
function PS:StartDeal()
    if self.phase ~= self.PHASE.WAITING_FOR_PLAYERS then
        return false, "Cannot deal - wrong phase"
    end
    
    if #self.playerOrder < 2 then
        return false, "Need at least 2 players"
    end
    
    self.phase = self.PHASE.DEALING
    self.currentStreet = 0
    return true
end

-- Deal one card to a player (called during animation)
function PS:DealCardToPlayer(playerName, faceUp)
    local player = self.players[playerName]
    if not player then return nil end
    if player.folded then return nil end
    
    local card = self:DrawCard()
    if card then
        card.faceUp = faceUp
        table.insert(player.hand, card)
    end
    return card
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

function PS:GetVisibleCards(playerName)
    local player = self.players[playerName]
    if not player then return {} end
    
    local visible = {}
    for _, card in ipairs(player.hand) do
        if card.faceUp then
            table.insert(visible, card)
        end
    end
    return visible
end

function PS:GetCurrentPlayer()
    if self.phase ~= self.PHASE.BETTING then return nil end
    return self.playerOrder[self.currentPlayerIndex]
end

function PS:CanPlayerAct(playerName)
    if self.phase ~= self.PHASE.BETTING then return false end
    return playerName == self:GetCurrentPlayer()
end

function PS:GetActivePlayers()
    local count = 0
    for _, playerName in ipairs(self.playerOrder) do
        local player = self.players[playerName]
        if player and not player.folded then
            count = count + 1
        end
    end
    return count
end

function PS:GetAvailableActions(playerName)
    local player = self.players[playerName]
    if not player or player.folded then return {} end
    
    local actions = {}
    local playerBet = player.currentBet or 0
    local toCall = self.currentBet - playerBet
    
    table.insert(actions, self.ACTION.FOLD)
    
    if toCall <= 0 then
        table.insert(actions, self.ACTION.CHECK)
    else
        table.insert(actions, self.ACTION.CALL)
    end
    
    if self.currentBet < self.maxRaise then
        table.insert(actions, self.ACTION.RAISE)
    end
    
    return actions
end

-- Player actions
function PS:PlayerFold(playerName)
    -- Can fold anytime during betting, not just on turn
    if self.phase ~= self.PHASE.BETTING then
        return false, "Cannot fold outside of betting phase"
    end
    
    local player = self.players[playerName]
    if not player then
        return false, "Player not in game"
    end
    
    if player.folded then
        return false, "Already folded"
    end
    
    player.folded = true
    
    BJ:Debug(playerName .. " folds")
    
    -- If this player was current, advance turn
    local wasCurrentPlayer = (self:GetCurrentPlayer() == playerName)
    
    if self:GetActivePlayers() == 1 then
        self:EndHandEarly()
        return true, "hand_over"
    end
    
    -- If it was their turn, advance to next player
    if wasCurrentPlayer then
        self:AdvanceToNextPlayer()
    end
    
    return true
end

function PS:PlayerCheck(playerName)
    if not self:CanPlayerAct(playerName) then
        return false, "Not your turn"
    end
    
    local player = self.players[playerName]
    local toCall = self.currentBet - player.currentBet
    
    if toCall > 0 then
        return false, "Cannot check - must call " .. toCall .. "g"
    end
    
    BJ:Debug(playerName .. " checks")
    self.actedThisRound[playerName] = true
    
    self:AdvanceToNextPlayer()
    return true
end

function PS:PlayerCall(playerName)
    if not self:CanPlayerAct(playerName) then
        return false, "Not your turn"
    end
    
    local player = self.players[playerName]
    local toCall = self.currentBet - player.currentBet
    
    if toCall <= 0 then
        return self:PlayerCheck(playerName)
    end
    
    player.currentBet = self.currentBet
    player.totalBet = player.totalBet + toCall
    self.pot = self.pot + toCall
    
    BJ:Debug(playerName .. " calls " .. toCall .. "g (pot: " .. self.pot .. ")")
    self.actedThisRound[playerName] = true
    
    self:AdvanceToNextPlayer()
    return true, toCall
end

function PS:PlayerRaise(playerName, raiseAmount)
    if not self:CanPlayerAct(playerName) then
        return false, "Not your turn"
    end
    
    local player = self.players[playerName]
    
    if raiseAmount <= 0 then
        return false, "Invalid raise amount"
    end
    
    local newBet = self.currentBet + raiseAmount
    if newBet > self.maxRaise then
        return false, "Exceeds max raise (" .. self.maxRaise .. "g)"
    end
    
    local toCall = self.currentBet - player.currentBet
    local totalCost = toCall + raiseAmount
    
    player.currentBet = newBet
    player.totalBet = player.totalBet + totalCost
    self.pot = self.pot + totalCost
    self.currentBet = newBet
    self.lastRaiser = playerName
    
    self.actedThisRound = {}
    self.actedThisRound[playerName] = true
    
    BJ:Debug(playerName .. " raises to " .. newBet .. "g (pot: " .. self.pot .. ")")
    
    self:AdvanceToNextPlayer()
    return true, totalCost
end

function PS:AdvanceToNextPlayer()
    local startIndex = self.currentPlayerIndex
    local numPlayers = #self.playerOrder
    
    for i = 1, numPlayers do
        local nextIndex = ((startIndex - 1 + i) % numPlayers) + 1
        local nextPlayer = self.playerOrder[nextIndex]
        local player = self.players[nextPlayer]
        
        if player and not player.folded then
            if self:IsBettingRoundComplete(nextPlayer) then
                self:EndBettingRound()
                return "round_complete"
            end
            
            self.currentPlayerIndex = nextIndex
            BJ:Debug("Next to act: " .. nextPlayer)
            return nextPlayer
        end
    end
    
    self:EndBettingRound()
    return "round_complete"
end

function PS:IsBettingRoundComplete(nextPlayer)
    if self.lastRaiser and nextPlayer == self.lastRaiser then
        return true
    end
    
    for _, playerName in ipairs(self.playerOrder) do
        local player = self.players[playerName]
        if player and not player.folded then
            if not self.actedThisRound[playerName] then
                return false
            end
            if player.currentBet < self.currentBet then
                return false
            end
        end
    end
    
    return true
end

function PS:EndBettingRound()
    BJ:Debug("Betting round " .. self.currentStreet .. " complete. Pot: " .. self.pot)
    
    -- Reset for next round
    for _, playerName in ipairs(self.playerOrder) do
        local player = self.players[playerName]
        if player then
            player.currentBet = 0
        end
    end
    self.currentBet = 0
    
    if self:GetActivePlayers() == 1 then
        self:EndHandEarly()
        return "hand_over"
    elseif self.currentStreet >= 4 then
        self:StartShowdown()
        return "showdown"
    else
        self.phase = self.PHASE.DEALING
        return "deal_next"
    end
end

function PS:EndHandEarly()
    for _, playerName in ipairs(self.playerOrder) do
        local player = self.players[playerName]
        if player and not player.folded then
            self.winners = { playerName }
            break
        end
    end
    
    self:CalculateSettlements()
    self.phase = self.PHASE.SETTLEMENT
    BJ:Debug("Hand ended early. Winner: " .. (self.winners[1] or "?"))
end

function PS:StartShowdown()
    self.phase = self.PHASE.SHOWDOWN
    
    local evaluations = {}
    for _, playerName in ipairs(self.playerOrder) do
        local player = self.players[playerName]
        if player and not player.folded then
            local eval = self:EvaluateHand(player.hand)
            eval.playerName = playerName
            table.insert(evaluations, eval)
            
            player.handRank = eval.rank
            player.handName = self.HAND_NAMES[eval.rank]
        end
    end
    
    table.sort(evaluations, function(a, b)
        return self:CompareHands(a, b) > 0
    end)
    
    self.winners = { evaluations[1].playerName }
    for i = 2, #evaluations do
        if self:CompareHands(evaluations[1], evaluations[i]) == 0 then
            table.insert(self.winners, evaluations[i].playerName)
        else
            break
        end
    end
    
    self:CalculateSettlements()
    self.phase = self.PHASE.SETTLEMENT
    
    BJ:Debug("Showdown. Winner(s): " .. table.concat(self.winners, ", "))
end

function PS:CalculateSettlements()
    self.settlements = {}
    
    local numWinners = #self.winners
    local winShare = math.floor(self.pot / numWinners)
    local remainder = self.pot - (winShare * numWinners)
    
    BJ:Debug("CalculateSettlements: numWinners=" .. numWinners .. ", pot=" .. self.pot .. ", winShare=" .. winShare)
    
    -- Evaluate all hands and count how many players have each hand rank
    local allPlayerEvals = {}
    local rankCounts = {}  -- How many non-folded players have each rank
    
    for _, playerName in ipairs(self.playerOrder) do
        local player = self.players[playerName]
        if player and not player.folded and player.hand then
            local eval = self:EvaluateHand(player.hand)
            allPlayerEvals[playerName] = eval
            rankCounts[eval.rank] = (rankCounts[eval.rank] or 0) + 1
        end
    end
    
    for _, playerName in ipairs(self.playerOrder) do
        local player = self.players[playerName]
        local bet = player.totalBet or 0
        local isWinner = false
        local payout = 0
        
        for i, winner in ipairs(self.winners) do
            if winner == playerName then
                isWinner = true
                payout = winShare - bet
                if i == 1 then payout = payout + remainder end
                break
            end
        end
        
        if not isWinner then
            payout = -bet
        end
        
        -- Get detailed hand name
        -- Only show kicker if another player has the same hand rank (kicker matters)
        local detailedHandName = player.handName or "Unknown"
        if player.hand and not player.folded then
            local eval = allPlayerEvals[playerName]
            local showKicker = eval and rankCounts[eval.rank] and rankCounts[eval.rank] > 1
            detailedHandName = self:GetDetailedHandName(eval, showKicker)
        end
        
        -- Update player.handName with the detailed name (for sync)
        player.handName = detailedHandName
        
        self.settlements[playerName] = {
            total = payout,
            bet = bet,
            isWinner = isWinner,
            handName = detailedHandName,
            folded = player.folded,
        }
        BJ:Debug("  Settlement for " .. playerName .. ": handName=" .. detailedHandName .. ", bet=" .. bet .. ", isWinner=" .. tostring(isWinner))
        
        -- Record to leaderboard (host only - clients get updates via broadcast)
        if BJ.Leaderboard then
            local myName = UnitName("player")
            if not self.hostName or self.hostName == myName then
                local outcome = isWinner and "win" or "lose"
                if player.folded then outcome = "lose" end
                BJ.Leaderboard:RecordHandResult("poker", playerName, payout, outcome)
            end
        end
    end
    
    BJ:Debug("CalculateSettlements complete. Total settlements: " .. (next(self.settlements) and "yes" or "no"))
end

-- Convert rank value (2-14) to display name
function PS:RankValueToName(val)
    local names = {
        [2] = "2's", [3] = "3's", [4] = "4's", [5] = "5's", [6] = "6's",
        [7] = "7's", [8] = "8's", [9] = "9's", [10] = "10's",
        [11] = "Jacks", [12] = "Queens", [13] = "Kings", [14] = "Aces"
    }
    return names[val] or tostring(val)
end

-- Convert rank value to single card name (for kickers)
function PS:RankValueToCard(val)
    local names = {
        [2] = "2", [3] = "3", [4] = "4", [5] = "5", [6] = "6",
        [7] = "7", [8] = "8", [9] = "9", [10] = "10",
        [11] = "J", [12] = "Q", [13] = "K", [14] = "A"
    }
    return names[val] or tostring(val)
end

-- Get detailed hand description with optional kickers (only show kicker if it was a tiebreaker)
function PS:GetDetailedHandName(eval, showKicker)
    if not eval or not eval.rank then return "Unknown" end
    
    local rank = eval.rank
    local kickers = eval.kickers or {}
    
    if rank == self.HAND_RANK.ROYAL_FLUSH then
        return "Royal Flush!"
    elseif rank == self.HAND_RANK.STRAIGHT_FLUSH then
        return "Straight Flush, " .. self:RankValueToCard(kickers[1]) .. " High"
    elseif rank == self.HAND_RANK.FOUR_OF_A_KIND then
        return "Four " .. self:RankValueToName(kickers[1])
    elseif rank == self.HAND_RANK.FULL_HOUSE then
        return "Full House, " .. self:RankValueToName(kickers[1]) .. " over " .. self:RankValueToName(kickers[2])
    elseif rank == self.HAND_RANK.FLUSH then
        return "Flush, " .. self:RankValueToCard(kickers[1]) .. " High"
    elseif rank == self.HAND_RANK.STRAIGHT then
        return "Straight, " .. self:RankValueToCard(kickers[1]) .. " High"
    elseif rank == self.HAND_RANK.THREE_OF_A_KIND then
        return "Three " .. self:RankValueToName(kickers[1])
    elseif rank == self.HAND_RANK.TWO_PAIR then
        return "Two Pair, " .. self:RankValueToName(kickers[1]) .. " and " .. self:RankValueToName(kickers[2])
    elseif rank == self.HAND_RANK.ONE_PAIR then
        local kickerStr = ""
        if showKicker and kickers[2] and kickers[2] > 0 then
            kickerStr = ", " .. self:RankValueToCard(kickers[2]) .. " Kicker"
        end
        return "Pair of " .. self:RankValueToName(kickers[1]) .. kickerStr
    else
        -- High card
        if kickers[1] then
            local secondKicker = ""
            if showKicker and kickers[2] and kickers[2] > 0 then
                secondKicker = ", " .. self:RankValueToCard(kickers[2]) .. " Kicker"
            end
            return self:RankValueToCard(kickers[1]) .. " High" .. secondKicker
        end
        return "High Card"
    end
end

--[[
    HAND EVALUATION
]]

function PS:EvaluateHand(hand)
    if #hand == 0 then
        return { rank = 0, kickers = {} }
    end
    
    local rankCounts = {}
    local suitCounts = {}
    local rankValues = {}
    
    for _, card in ipairs(hand) do
        local rv = self.RANK_VALUES[card.rank]
        rankCounts[rv] = (rankCounts[rv] or 0) + 1
        suitCounts[card.suit] = (suitCounts[card.suit] or 0) + 1
        table.insert(rankValues, rv)
    end
    
    table.sort(rankValues, function(a, b) return a > b end)
    
    local isFlush = false
    if #hand >= 5 then
        for _, count in pairs(suitCounts) do
            if count >= 5 then isFlush = true break end
        end
    end
    
    local isStraight = #hand >= 5 and self:IsStraight(rankValues)
    
    -- Check wheel
    local isWheel = false
    if not isStraight and #hand >= 5 then
        local sorted = { unpack(rankValues) }
        table.sort(sorted, function(a, b) return a > b end)
        if sorted[1] == 14 and sorted[2] == 5 and sorted[3] == 4 and 
           sorted[4] == 3 and sorted[5] == 2 then
            isStraight = true
            isWheel = true
            rankValues = {5, 4, 3, 2, 1}
        end
    end
    
    local pairList, trips, quads, singles = {}, {}, {}, {}
    for rv, count in pairs(rankCounts) do
        if count == 4 then table.insert(quads, rv)
        elseif count == 3 then table.insert(trips, rv)
        elseif count == 2 then table.insert(pairList, rv)
        else table.insert(singles, rv)
        end
    end
    
    table.sort(pairList, function(a, b) return a > b end)
    table.sort(trips, function(a, b) return a > b end)
    table.sort(quads, function(a, b) return a > b end)
    table.sort(singles, function(a, b) return a > b end)
    
    local result = { rank = self.HAND_RANK.HIGH_CARD, kickers = rankValues }
    
    if isStraight and isFlush then
        result.rank = (rankValues[1] == 14 and not isWheel) and self.HAND_RANK.ROYAL_FLUSH or self.HAND_RANK.STRAIGHT_FLUSH
        result.kickers = { rankValues[1] }
    elseif #quads > 0 then
        result.rank = self.HAND_RANK.FOUR_OF_A_KIND
        result.kickers = { quads[1], singles[1] or 0 }
    elseif #trips > 0 and #pairList > 0 then
        result.rank = self.HAND_RANK.FULL_HOUSE
        result.kickers = { trips[1], pairList[1] }
    elseif isFlush then
        result.rank = self.HAND_RANK.FLUSH
        result.kickers = rankValues
    elseif isStraight then
        result.rank = self.HAND_RANK.STRAIGHT
        result.kickers = { rankValues[1] }
    elseif #trips > 0 then
        result.rank = self.HAND_RANK.THREE_OF_A_KIND
        result.kickers = { trips[1], singles[1] or 0, singles[2] or 0 }
    elseif #pairList >= 2 then
        result.rank = self.HAND_RANK.TWO_PAIR
        result.kickers = { pairList[1], pairList[2], singles[1] or 0 }
    elseif #pairList == 1 then
        result.rank = self.HAND_RANK.ONE_PAIR
        result.kickers = { pairList[1], singles[1] or 0, singles[2] or 0, singles[3] or 0 }
    end
    
    return result
end

function PS:IsStraight(rankValues)
    if #rankValues < 5 then return false end
    local sorted = { unpack(rankValues) }
    table.sort(sorted, function(a, b) return a > b end)
    for i = 1, 4 do
        if sorted[i] - sorted[i + 1] ~= 1 then return false end
    end
    return true
end

function PS:CompareHands(evalA, evalB)
    if evalA.rank > evalB.rank then return 1
    elseif evalA.rank < evalB.rank then return -1 end
    
    for i = 1, math.max(#evalA.kickers, #evalB.kickers) do
        local kA, kB = evalA.kickers[i] or 0, evalB.kickers[i] or 0
        if kA > kB then return 1 elseif kA < kB then return -1 end
    end
    return 0
end

--[[
    UTILITY
]]

function PS:FormatHand(hand)
    local parts = {}
    for _, card in ipairs(hand) do
        table.insert(parts, card.rank)
    end
    return table.concat(parts, " ")
end

function PS:CardToString(card)
    return card.rank
end

function PS:GetPlayerCount()
    return #self.playerOrder
end

function PS:CanJoin()
    if self.phase ~= self.PHASE.WAITING_FOR_PLAYERS then
        return false, "Game not accepting players"
    end
    if #self.playerOrder >= self.MAX_PLAYERS then
        return false, "Table full"
    end
    return true
end

function PS:GetSettlementSummary()
    if not self.settlements then return "No settlement data" end
    
    local lines = {}
    table.insert(lines, "=== 5 Card Stud Results ===")
    table.insert(lines, "Pot: " .. self.pot .. "g")
    table.insert(lines, "")
    
    table.insert(lines, "|cff00ff00Winner(s):|r")
    for _, winner in ipairs(self.winners) do
        local player = self.players[winner]
        local settlement = self.settlements[winner]
        table.insert(lines, "  " .. winner .. " - " .. (player.handName or "Winner") .. " (+" .. settlement.total .. "g)")
    end
    
    table.insert(lines, "")
    table.insert(lines, "All Players:")
    for _, playerName in ipairs(self.playerOrder) do
        local player = self.players[playerName]
        local settlement = self.settlements[playerName]
        local status = player.folded and "|cff888888FOLDED|r" or (self:FormatHand(player.hand) .. " (" .. (player.handName or "?") .. ")")
        local netStr = settlement.total >= 0 and ("+" .. settlement.total) or tostring(settlement.total)
        local color = settlement.isWinner and "00ff00" or "ff4444"
        table.insert(lines, "  " .. playerName .. ": " .. status .. " |cff" .. color .. netStr .. "g|r")
    end
    
    return table.concat(lines, "\n")
end

--[[
    GAME HISTORY LOG (Last 5 games)
]]
PS.gameHistory = {}
PS.MAX_HISTORY = 5

-- Save game to history (called after settlement)
function PS:SaveGameToHistory()
    if not self.settlements or not self.winners or #self.winners == 0 then
        return
    end
    
    local game = {
        timestamp = time(),
        pot = self.pot,
        winners = {},
        players = {},
    }
    
    -- Copy winners
    for _, w in ipairs(self.winners) do
        table.insert(game.winners, w)
    end
    
    -- Copy player data
    for _, playerName in ipairs(self.playerOrder) do
        local player = self.players[playerName]
        local settlement = self.settlements[playerName]
        if player and settlement then
            table.insert(game.players, {
                name = playerName,
                folded = player.folded,
                handName = player.handName or "?",
                totalBet = player.totalBet or 0,
                net = settlement.total or 0,
                isWinner = settlement.isWinner,
            })
        end
    end
    
    -- Add to history, keeping only last 5
    table.insert(self.gameHistory, 1, game)
    while #self.gameHistory > self.MAX_HISTORY do
        table.remove(self.gameHistory)
    end
    
    BJ:Debug("Poker game saved to history. Total games: " .. #self.gameHistory)
    
    -- Save to persistent storage
    self:SaveHistoryToDB()
end

-- Save game history to SavedVariables (encoded)
function PS:SaveHistoryToDB()
    if not ChairfacesCasinoSaved then
        ChairfacesCasinoSaved = {}
    end
    
    if BJ.Compression and BJ.Compression.EncodeForSave then
        ChairfacesCasinoSaved.pokerHistory = BJ.Compression:EncodeForSave(self.gameHistory)
    end
end

-- Load game history from SavedVariables
function PS:LoadHistoryFromDB()
    if not ChairfacesCasinoSaved or not ChairfacesCasinoSaved.pokerHistory then
        return
    end
    
    if BJ.Compression and BJ.Compression.DecodeFromSave then
        local decoded = BJ.Compression:DecodeFromSave(ChairfacesCasinoSaved.pokerHistory)
        if decoded and type(decoded) == "table" then
            self.gameHistory = decoded
            BJ:Debug("Loaded " .. #self.gameHistory .. " poker games from history")
        end
    end
end

-- Get formatted game history text for log window
function PS:GetGameLogText()
    if #self.gameHistory == 0 then
        return "No game history yet."
    end
    
    local lines = {}
    
    for gameNum, game in ipairs(self.gameHistory) do
        -- Header
        local timeAgo = time() - game.timestamp
        local timeStr
        if timeAgo < 60 then
            timeStr = timeAgo .. "s ago"
        elseif timeAgo < 3600 then
            timeStr = math.floor(timeAgo / 60) .. "m ago"
        else
            timeStr = math.floor(timeAgo / 3600) .. "h ago"
        end
        
        table.insert(lines, "|cffffd700=== Game " .. gameNum .. " (" .. timeStr .. ") ===|r")
        table.insert(lines, "Pot: " .. (game.pot or 0) .. "g")
        
        -- Winner
        if game.winners and #game.winners > 0 then
            local winnerStr = table.concat(game.winners, ", ")
            table.insert(lines, "|cff00ff00Winner: " .. winnerStr .. "|r")
        end
        
        table.insert(lines, "")
        table.insert(lines, "|cff88ffffLedger:|r")
        
        -- Sort players by amount owed (most first)
        local sortedPlayers = {}
        for _, p in ipairs(game.players) do
            table.insert(sortedPlayers, p)
        end
        table.sort(sortedPlayers, function(a, b)
            if a.isWinner ~= b.isWinner then return a.isWinner end
            return a.totalBet > b.totalBet
        end)
        
        -- Show each player
        for _, p in ipairs(sortedPlayers) do
            local status = ""
            if p.isWinner then
                status = "|cff00ff00WON +" .. math.abs(p.net) .. "g|r"
            elseif p.folded then
                status = "|cff888888FOLDED -" .. p.totalBet .. "g|r"
            else
                status = "|cffff4444LOST -" .. p.totalBet .. "g|r"
            end
            
            local handStr = ""
            if not p.folded and p.handName and p.handName ~= "?" then
                handStr = " (" .. p.handName .. ")"
            end
            
            table.insert(lines, "  " .. p.name .. handStr .. ": " .. status)
        end
        
        table.insert(lines, "")
    end
    
    return table.concat(lines, "\n")
end
