--[[
    Chairface's Casino - GameState.lua
    Deck management, hand logic, scoring, and Vegas rules engine
]]

local BJ = ChairfacesCasino
BJ.GameState = {}
local GS = BJ.GameState

-- Constants
GS.SHOE_DECKS = 1  -- Default to single deck, expands based on player count
GS.CARDS_PER_DECK = 52
GS.TOTAL_CARDS = GS.SHOE_DECKS * GS.CARDS_PER_DECK
GS.RESHUFFLE_THRESHOLD = 0.75  -- Reshuffle at 75% penetration

-- Card suits and ranks
GS.SUITS = { "hearts", "diamonds", "clubs", "spades" }
-- Using text symbols for suits
-- Using colored letters for maximum compatibility
GS.SUIT_SYMBOLS = { 
    hearts = "|cffff0000H|r",      -- Red H for hearts
    diamonds = "|cffff6600D|r",    -- Orange D for diamonds
    clubs = "|cff00ff00C|r",       -- Green C for clubs
    spades = "|cffffffffS|r"       -- White S for spades
}
GS.RANKS = { "A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K" }
GS.RANK_VALUES = {
    ["A"] = 11,  -- Aces are 11 by default, reduced to 1 if bust
    ["2"] = 2, ["3"] = 3, ["4"] = 4, ["5"] = 5, ["6"] = 6,
    ["7"] = 7, ["8"] = 8, ["9"] = 9, ["10"] = 10,
    ["J"] = 10, ["Q"] = 10, ["K"] = 10
}

-- Game phases
GS.PHASE = {
    IDLE = "idle",              -- No active game
    WAITING_FOR_PLAYERS = "waiting",  -- Host opened, waiting for antes
    DEALING = "dealing",        -- Cards being dealt
    PLAYER_TURN = "player_turn", -- Players making decisions
    DEALER_TURN = "dealer_turn", -- Dealer playing out
    SETTLEMENT = "settlement",   -- Showing results/payouts
}

-- Hand outcomes
GS.OUTCOME = {
    PENDING = "pending",
    BLACKJACK = "blackjack",    -- 3:2 payout
    WIN = "win",                -- 1:1 payout
    LOSE = "lose",              -- Lose bet
    PUSH = "push",              -- Tie, bet returned
    BUST = "bust",              -- Over 21, lose
    SURRENDER = "surrender",    -- Not implemented per rules
}

-- Initialize/reset game state
function GS:Reset()
    self.phase = self.PHASE.IDLE
    self.shoe = {}
    self.cardIndex = 1
    self.seed = nil
    
    -- Host info
    self.hostName = nil
    self.ante = 0
    
    -- Dealer hand
    self.dealerHand = {}
    self.dealerHoleCardRevealed = false
    
    -- Player hands: { [playerName] = { hands = {}, bets = {}, insurance = 0, activeHandIndex = 1 } }
    self.players = {}
    self.playerOrder = {}  -- Order of play
    self.currentPlayerIndex = 0
    
    -- Settlement ledger
    self.settlements = {}
    
    -- Voided game flag
    self.gameVoided = false
end

-- Reset for new hand but preserve shoe (for same host continuing)
function GS:ResetForNewHand()
    self.phase = self.PHASE.IDLE
    -- Preserve shoe, cardIndex, seed - don't reset them
    
    -- Host info preserved too (hostName stays)
    -- ante will be set by StartRound
    
    -- Clear dealer hand
    self.dealerHand = {}
    self.dealerHoleCardRevealed = false
    
    -- Clear player hands
    self.players = {}
    self.playerOrder = {}
    self.currentPlayerIndex = 0
    
    -- Clear settlement ledger
    self.settlements = {}
    
    -- Clear voided flag
    self.gameVoided = false
end

-- Last hand data (preserved between games)
GS.lastHand = nil

-- Save current hand results before starting new game
function GS:SaveLastHand()
    if self.phase ~= self.PHASE.SETTLEMENT then return end
    if #self.playerOrder == 0 then return end
    
    self.lastHand = {
        timestamp = time(),
        hostName = self.hostName,
        ante = self.ante,
        dealerHand = {},
        dealerScore = 0,
        players = {},
        settlements = {},
    }
    
    -- Copy dealer hand
    for _, card in ipairs(self.dealerHand) do
        table.insert(self.lastHand.dealerHand, { rank = card.rank, suit = card.suit })
    end
    self.lastHand.dealerScore = self:ScoreHand(self.dealerHand).total
    
    -- Copy player data
    for _, playerName in ipairs(self.playerOrder) do
        local player = self.players[playerName]
        if player then
            local playerData = {
                name = playerName,
                hands = {},
                bets = {},
                outcomes = player.outcomes or {},
                payouts = player.payouts or {},
            }
            for h, hand in ipairs(player.hands) do
                local handCopy = {}
                for _, card in ipairs(hand) do
                    table.insert(handCopy, { rank = card.rank, suit = card.suit })
                end
                table.insert(playerData.hands, handCopy)
                table.insert(playerData.bets, player.bets[h] or 0)
            end
            table.insert(self.lastHand.players, playerData)
        end
    end
    
    -- Copy settlements
    for playerName, settlement in pairs(self.settlements) do
        self.lastHand.settlements[playerName] = {
            total = settlement.total,
            details = settlement.details,
        }
    end
    
    BJ:Debug("Last hand saved")
end

-- Get formatted last hand results
function GS:GetLastHandText()
    if not self.lastHand then
        return "No previous hand recorded."
    end
    
    local lh = self.lastHand
    local lines = {}
    
    -- Header
    local timeAgo = time() - lh.timestamp
    local timeStr = timeAgo < 60 and (timeAgo .. "s ago") or (math.floor(timeAgo / 60) .. "m ago")
    table.insert(lines, "=== Last Hand (" .. timeStr .. ") ===")
    table.insert(lines, "Host: " .. lh.hostName .. " | Ante: " .. lh.ante .. "g")
    
    -- Dealer
    local dealerCards = ""
    for _, card in ipairs(lh.dealerHand) do
        dealerCards = dealerCards .. card.rank .. " "
    end
    table.insert(lines, "Dealer: " .. dealerCards .. "(" .. lh.dealerScore .. ")")
    
    -- Players
    for _, player in ipairs(lh.players) do
        for h, hand in ipairs(player.hands) do
            local handCards = ""
            for _, card in ipairs(hand) do
                handCards = handCards .. card.rank .. " "
            end
            local score = self:ScoreHand(hand).total
            local outcome = player.outcomes[h] or "?"
            local payout = player.payouts[h] or 0
            
            local resultStr = ""
            if outcome == "win" or outcome == "blackjack" then
                resultStr = "|cff00ff00WIN +" .. payout .. "g|r"
            elseif outcome == "lose" or outcome == "bust" then
                resultStr = "|cffff4444LOSE " .. payout .. "g|r"
            elseif outcome == "push" then
                resultStr = "|cffffff00PUSH|r"
            end
            
            local label = player.name
            if #player.hands > 1 then
                label = label .. " (Hand " .. h .. ")"
            end
            table.insert(lines, label .. ": " .. handCards .. "(" .. score .. ") - " .. resultStr)
        end
    end
    
    -- Settlement summary
    table.insert(lines, "--- Settlement ---")
    for playerName, settlement in pairs(lh.settlements) do
        local total = settlement.total
        if total > 0 then
            table.insert(lines, lh.hostName .. " owes " .. playerName .. " " .. total .. "g")
        elseif total < 0 then
            table.insert(lines, playerName .. " owes " .. lh.hostName .. " " .. math.abs(total) .. "g")
        else
            table.insert(lines, playerName .. ": even")
        end
    end
    
    return table.concat(lines, "\n")
end

-- Format gold amount with silver/copper (e.g., 1.5 = "1g 50s")
function GS:FormatGold(amount)
    if amount == 0 then return "0g" end
    
    local sign = amount < 0 and "-" or "+"
    amount = math.abs(amount)
    
    local gold = math.floor(amount)
    local silver = math.floor((amount - gold) * 100)
    local copper = math.floor(((amount - gold) * 100 - silver) * 100)
    
    local parts = {}
    if gold > 0 then table.insert(parts, gold .. "g") end
    if silver > 0 then table.insert(parts, silver .. "s") end
    if copper > 0 then table.insert(parts, copper .. "c") end
    
    if #parts == 0 then return "0g" end
    return sign .. table.concat(parts, " ")
end

-- Initialize on load
GS:Reset()

--[[
    SHOE MANAGEMENT
    Using seeded random for deterministic shuffling across all clients
]]

-- Simple seeded PRNG (Linear Congruential Generator)
local function seededRandom(seed)
    local state = seed
    return function()
        state = (state * 1103515245 + 12345) % 2147483648
        return state / 2147483648
    end
end

-- Create and shuffle a new shoe
function GS:CreateShoe(seed, numDecks)
    self.seed = seed or time()
    self.SHOE_DECKS = numDecks or 1  -- Default to 1 deck
    self.TOTAL_CARDS = self.SHOE_DECKS * self.CARDS_PER_DECK
    self.shoe = {}
    self.cardIndex = 1
    
    -- Create deck(s)
    for deck = 1, self.SHOE_DECKS do
        for _, suit in ipairs(self.SUITS) do
            for _, rank in ipairs(self.RANKS) do
                table.insert(self.shoe, {
                    rank = rank,
                    suit = suit,
                    id = #self.shoe + 1
                })
            end
        end
    end
    
    -- Fisher-Yates shuffle with seeded random
    local rng = seededRandom(self.seed)
    for i = #self.shoe, 2, -1 do
        local j = math.floor(rng() * i) + 1
        self.shoe[i], self.shoe[j] = self.shoe[j], self.shoe[i]
    end
    
    BJ:Debug("Shoe created with seed: " .. self.seed .. ", " .. #self.shoe .. " cards (" .. self.SHOE_DECKS .. " decks)")
end

-- Calculate decks needed based on player count
-- 1 deck for 1-5 players, 2 decks for 6-15, 3 decks for 16-20
function GS:CalculateDecksNeeded(numPlayers)
    if numPlayers <= 5 then
        return 1
    elseif numPlayers <= 15 then
        return 2
    else
        return 3
    end
end

-- Ensure shoe has correct deck count for current players
function GS:EnsureShoeCapacity(numPlayers)
    local decksNeeded = self:CalculateDecksNeeded(numPlayers)
    if decksNeeded ~= self.SHOE_DECKS then
        local action = decksNeeded > self.SHOE_DECKS and "Expanding" or "Adjusting"
        BJ:Print(action .. " shoe to " .. decksNeeded .. " deck" .. (decksNeeded > 1 and "s" or "") .. " for " .. numPlayers .. " players")
        self:CreateShoe(self.seed, decksNeeded)
        -- Update UI to show new card count
        if BJ.UI and BJ.UI.UpdateDisplay then
            BJ.UI:UpdateDisplay()
        end
    end
end

-- Check if shoe needs reshuffling
function GS:NeedsReshuffle()
    return self.cardIndex > (self.TOTAL_CARDS * self.RESHUFFLE_THRESHOLD)
end

-- Draw next card from shoe
function GS:DrawCard()
    if self.cardIndex > #self.shoe then
        BJ:Print("Error: Shoe exhausted!")
        return nil
    end
    
    local card = self.shoe[self.cardIndex]
    self.cardIndex = self.cardIndex + 1
    return card
end

-- Get remaining cards in shoe
function GS:GetRemainingCards()
    -- Use synced value if available (for non-host clients)
    if self.syncedCardsRemaining and not BJ.Multiplayer.isHost then
        return self.syncedCardsRemaining
    end
    return #self.shoe - self.cardIndex + 1
end

--[[
    HAND SCORING
]]

-- Calculate hand value, returns { total, isSoft, isBust, isBlackjack }
function GS:ScoreHand(hand)
    local total = 0
    local aces = 0
    
    for _, card in ipairs(hand) do
        local value = self.RANK_VALUES[card.rank]
        total = total + value
        if card.rank == "A" then
            aces = aces + 1
        end
    end
    
    -- Reduce aces from 11 to 1 if busting
    while total > 21 and aces > 0 do
        total = total - 10
        aces = aces - 1
    end
    
    local isSoft = aces > 0 and total <= 21  -- Has an ace counted as 11
    local isBust = total > 21
    local isBlackjack = #hand == 2 and total == 21
    local isFiveCardCharlie = #hand >= 5 and total <= 21  -- 5+ cards without busting
    
    return {
        total = total,
        isSoft = isSoft,
        isBust = isBust,
        isBlackjack = isBlackjack,
        isFiveCardCharlie = isFiveCardCharlie
    }
end

-- Format hand for display
function GS:FormatHand(hand, hideHoleCard)
    local parts = {}
    for i, card in ipairs(hand) do
        if hideHoleCard and i == 2 then
            table.insert(parts, "[??]")
        else
            table.insert(parts, card.rank)
        end
    end
    return table.concat(parts, " ")
end

-- Get card display string
function GS:CardToString(card)
    return card.rank
end

-- Get numeric value of a single card
function GS:CardValue(card)
    return self.RANK_VALUES[card.rank]
end

--[[
    GAME ACTIONS
]]

-- Start a new round as host
function GS:StartRound(hostName, ante, seed, preserveShoe, dealerHitsSoft17)
    -- Check if same host is continuing (preserve shoe)
    local sameHost = self.hostName == hostName and #self.shoe > 0
    
    if sameHost or preserveShoe then
        -- Same host continuing - preserve the shoe
        self:ResetForNewHand()
    else
        -- New host or first game - full reset
        self:Reset()
    end
    
    self.hostName = hostName
    self.ante = ante
    self.dealerHitsSoft17 = dealerHitsSoft17 ~= false  -- Default to H17 (true) if not specified
    self.phase = self.PHASE.WAITING_FOR_PLAYERS
    
    -- Always store the seed for display, even if we don't reshuffle
    if seed then
        self.seed = seed
    end
    
    -- Track if we reshuffled this round
    self.reshuffledThisRound = false
    
    -- Create shoe if needed or if it needs reshuffling
    if #self.shoe == 0 or self:NeedsReshuffle() then
        self:CreateShoe(seed)
        self.reshuffledThisRound = true
        if sameHost then
            BJ:Print("|cff88ffffShuffling deck...|r")
        end
    else
        BJ:Debug("Continuing with existing shoe. " .. self:GetRemainingCards() .. " cards remaining.")
    end
    
    BJ:Debug("Round started. Host: " .. hostName .. ", Ante: " .. ante .. ", Rule: " .. (self.dealerHitsSoft17 and "H17" or "S17"))
end

-- Player joins with a bet
function GS:PlayerAnte(playerName, betAmount)
    if self.phase ~= self.PHASE.WAITING_FOR_PLAYERS then
        return false, "Cannot join - wrong phase"
    end
    
    if self.players[playerName] then
        return false, "Already in this hand"
    end
    
    -- Check player limit (uses host setting, defaults to 20)
    local maxPlayers = self.maxPlayers or 20
    if #self.playerOrder >= maxPlayers then
        return false, "Table is full (" .. maxPlayers .. " players max)"
    end
    
    self.players[playerName] = {
        hands = { {} },  -- Start with one empty hand
        bets = { betAmount },
        insurance = 0,
        activeHandIndex = 1,
        outcomes = { self.OUTCOME.PENDING },
        payouts = { 0 },
    }
    table.insert(self.playerOrder, playerName)
    
    -- Check if we need more decks for the new player count
    self:EnsureShoeCapacity(#self.playerOrder)
    
    BJ:Debug(playerName .. " anted " .. betAmount)
    return true
end

-- Add to existing bet (for multiplier betting)
function GS:AddToBet(playerName, additionalAmount)
    if self.phase ~= self.PHASE.WAITING_FOR_PLAYERS then
        return false, "Cannot add bet - wrong phase"
    end
    
    local player = self.players[playerName]
    if not player then
        return false, "Player not in hand"
    end
    
    local newBet = player.bets[1] + additionalAmount
    local maxBet = self.ante * (self.maxMultiplier or 1)
    
    if newBet > maxBet then
        return false, "Exceeds maximum bet (" .. maxBet .. "g)"
    end
    
    player.bets[1] = newBet
    BJ:Debug(playerName .. " increased bet to " .. newBet)
    return true, newBet
end

-- Deal initial cards
function GS:DealInitialCards()
    if self.phase ~= self.PHASE.WAITING_FOR_PLAYERS then
        return false, "Cannot deal - wrong phase"
    end
    
    if #self.playerOrder == 0 then
        return false, "No players at table"
    end
    
    -- Start game log
    self:StartGameLog()
    
    -- Ensure shoe has enough cards for all players
    self:EnsureShoeCapacity(#self.playerOrder)
    
    self.phase = self.PHASE.DEALING
    self.dealerHand = {}
    
    -- Deal 2 cards to each player, then 2 to dealer
    -- First card to each player
    for _, playerName in ipairs(self.playerOrder) do
        local card = self:DrawCard()
        table.insert(self.players[playerName].hands[1], card)
    end
    
    -- First card to dealer (face up)
    table.insert(self.dealerHand, self:DrawCard())
    
    -- Second card to each player
    for _, playerName in ipairs(self.playerOrder) do
        local card = self:DrawCard()
        table.insert(self.players[playerName].hands[1], card)
    end
    
    -- Second card to dealer (hole card, face down)
    table.insert(self.dealerHand, self:DrawCard())
    self.dealerHoleCardRevealed = false
    
    -- Check for insurance opportunity (dealer shows Ace)
    self.insuranceOffered = (self.dealerHand[1].rank == "A")
    
    -- Move to player turn
    self.phase = self.PHASE.PLAYER_TURN
    self.currentPlayerIndex = 1
    
    -- Check for player blackjacks and auto-stand them
    self:CheckAndAutoStandBlackjacks()
    
    BJ:Debug("Initial deal complete. Dealer shows: " .. self:CardToString(self.dealerHand[1]))
    
    return true
end

-- Check all players for blackjack and auto-stand them
function GS:CheckAndAutoStandBlackjacks()
    local blackjackPlayers = {}
    
    for _, playerName in ipairs(self.playerOrder) do
        local player = self.players[playerName]
        local score = self:ScoreHand(player.hands[1])
        
        if score.isBlackjack then
            player.hasBlackjack = true
            player.outcomes[1] = self.OUTCOME.BLACKJACK  -- Mark as resolved
            table.insert(blackjackPlayers, playerName)
            self:LogAction(playerName, "BLACKJACK", "Natural 21!")
        end
    end
    
    -- Skip blackjack players in turn order
    self:SkipToNextNonBlackjackPlayer()
    
    return blackjackPlayers
end

-- Skip to next player who doesn't have blackjack
function GS:SkipToNextNonBlackjackPlayer()
    while self.currentPlayerIndex <= #self.playerOrder do
        local playerName = self.playerOrder[self.currentPlayerIndex]
        local player = self.players[playerName]
        
        if not player.hasBlackjack then
            return  -- Found a player who needs to act
        end
        
        self.currentPlayerIndex = self.currentPlayerIndex + 1
    end
    
    -- All players had blackjack or are done
    -- Don't automatically start dealer - let the caller handle timing
    -- This allows for proper animation delays
end

-- Check if all players are done and dealer should play
function GS:ShouldDealerPlay()
    return self.currentPlayerIndex > #self.playerOrder and self.phase == self.PHASE.PLAYER_TURN
end

-- Manually trigger dealer turn (called after animations complete)
function GS:StartDealerTurn()
    if self:ShouldDealerPlay() then
        self:PlayDealerHand()
    end
end

-- Check if player can perform action
function GS:CanPlayerAct(playerName)
    if self.phase ~= self.PHASE.PLAYER_TURN then
        return false
    end
    
    local currentPlayer = self.playerOrder[self.currentPlayerIndex]
    return playerName == currentPlayer
end

-- Get current active player
function GS:GetCurrentPlayer()
    if self.phase ~= self.PHASE.PLAYER_TURN then
        return nil
    end
    return self.playerOrder[self.currentPlayerIndex]
end

-- Player hits
function GS:PlayerHit(playerName)
    if not self:CanPlayerAct(playerName) then
        return false, "Not your turn"
    end
    
    local player = self.players[playerName]
    local handIndex = player.activeHandIndex
    local hand = player.hands[handIndex]
    
    -- Cannot hit on split aces (only get one card each)
    if player.splitAcesHands and player.splitAcesHands[handIndex] then
        return false, "Cannot hit on split aces"
    end
    
    local card = self:DrawCard()
    table.insert(hand, card)
    
    local score = self:ScoreHand(hand)
    BJ:Debug(playerName .. " hits: " .. self:CardToString(card) .. " (Total: " .. score.total .. ")")
    
    -- Log the action
    self:LogAction(playerName, "HIT", self:CardToString(card) .. " -> " .. score.total .. (score.isBust and " BUST" or (score.isFiveCardCharlie and " 5-CARD CHARLIE!" or "")))
    
    if score.isBust then
        player.outcomes[handIndex] = self.OUTCOME.BUST
        self:AdvanceToNextHand(playerName)
    elseif score.isFiveCardCharlie then
        -- 5 card charlie is an automatic win - mark and advance
        player.hasFiveCardCharlie = player.hasFiveCardCharlie or {}
        player.hasFiveCardCharlie[handIndex] = true
        player.outcomes[handIndex] = self.OUTCOME.WIN  -- Mark as resolved (auto win)
        BJ:Print(playerName .. " has a 5-Card Charlie!")
        self:AdvanceToNextHand(playerName)
    elseif score.total == 21 then
        -- Auto-stand on 21
        BJ:Debug(playerName .. " auto-stands on 21")
        self:LogAction(playerName, "STAND", "auto-stand at 21")
        self:AdvanceToNextHand(playerName)
    end
    
    return true, card
end

-- Player stands
function GS:PlayerStand(playerName)
    if not self:CanPlayerAct(playerName) then
        return false, "Not your turn"
    end
    
    local player = self.players[playerName]
    local hand = player.hands[player.activeHandIndex]
    local score = self:ScoreHand(hand)
    
    BJ:Debug(playerName .. " stands")
    self:LogAction(playerName, "STAND", "at " .. score.total)
    self:AdvanceToNextHand(playerName)
    return true
end

-- Player doubles down
function GS:PlayerDouble(playerName)
    if not self:CanPlayerAct(playerName) then
        return false, "Not your turn"
    end
    
    local player = self.players[playerName]
    local handIndex = player.activeHandIndex
    local hand = player.hands[handIndex]
    
    -- Can only double on first two cards
    if #hand ~= 2 then
        return false, "Can only double on first two cards"
    end
    
    -- Double the bet
    player.bets[handIndex] = player.bets[handIndex] * 2
    
    -- Draw exactly one card
    local card = self:DrawCard()
    table.insert(hand, card)
    
    local score = self:ScoreHand(hand)
    BJ:Debug(playerName .. " doubles: " .. self:CardToString(card) .. " (Total: " .. score.total .. ")")
    
    -- Log the action
    self:LogAction(playerName, "DOUBLE", self:CardToString(card) .. " -> " .. score.total .. (score.isBust and " BUST" or ""))
    
    if score.isBust then
        player.outcomes[handIndex] = self.OUTCOME.BUST
    end
    
    -- Automatically stand after double
    self:AdvanceToNextHand(playerName)
    return true, card
end

-- Player splits
function GS:PlayerSplit(playerName)
    if not self:CanPlayerAct(playerName) then
        return false, "Not your turn"
    end
    
    local player = self.players[playerName]
    local handIndex = player.activeHandIndex
    local hand = player.hands[handIndex]
    
    -- Can only split on first two cards of same rank
    if #hand ~= 2 then
        return false, "Can only split with two cards"
    end
    
    if hand[1].rank ~= hand[2].rank then
        return false, "Can only split pairs"
    end
    
    -- Check max splits (4 hands total)
    if #player.hands >= 4 then
        return false, "Maximum splits reached"
    end
    
    -- Check if splitting aces
    local isSplittingAces = hand[1].rank == "A"
    
    -- Save the second card before removing it
    local secondCard = hand[2]
    
    -- Create new hand with second card
    local newHand = { secondCard }
    
    -- Remove second card from original hand properly (resize array)
    table.remove(hand, 2)
    
    -- Insert new hand after current
    table.insert(player.hands, handIndex + 1, newHand)
    table.insert(player.bets, handIndex + 1, player.bets[handIndex])  -- Same bet
    table.insert(player.outcomes, handIndex + 1, self.OUTCOME.PENDING)
    table.insert(player.payouts, handIndex + 1, 0)
    
    -- Track split aces (player must stand after one card each, no blackjack, 1:1 payout)
    player.splitAcesHands = player.splitAcesHands or {}
    if isSplittingAces then
        player.splitAcesHands[handIndex] = true
        player.splitAcesHands[handIndex + 1] = true
    end
    
    -- Draw a card for each hand
    local card1 = self:DrawCard()
    local card2 = self:DrawCard()
    table.insert(hand, card1)
    table.insert(newHand, card2)
    
    -- Log the action
    self:LogAction(playerName, "SPLIT", self:FormatHand(hand) .. " | " .. self:FormatHand(newHand))
    
    BJ:Debug(playerName .. " splits. Hand 1: " .. self:FormatHand(hand) .. ", Hand 2: " .. self:FormatHand(newHand))
    
    -- For split aces, return that player must stand
    if isSplittingAces then
        return true, card1, card2, true  -- 4th return = isSplitAces
    end
    
    return true, card1, card2, false
end

-- Player takes insurance
function GS:PlayerInsurance(playerName, amount)
    if self.phase ~= self.PHASE.PLAYER_TURN then
        return false, "Wrong phase for insurance"
    end
    
    if not self.insuranceOffered then
        return false, "Insurance not available"
    end
    
    local player = self.players[playerName]
    if not player then
        return false, "Player not in hand"
    end
    
    -- Insurance is typically up to half the original bet
    local maxInsurance = math.floor(player.bets[1] / 2)
    if amount > maxInsurance then
        amount = maxInsurance
    end
    
    player.insurance = amount
    BJ:Debug(playerName .. " takes insurance: " .. amount)
    return true
end

-- Advance to next hand or next player
function GS:AdvanceToNextHand(playerName)
    local player = self.players[playerName]
    
    -- Check if player has more hands to play
    if player.activeHandIndex < #player.hands then
        player.activeHandIndex = player.activeHandIndex + 1
        BJ:Debug(playerName .. " moves to hand " .. player.activeHandIndex)
        return
    end
    
    -- Move to next player
    self.currentPlayerIndex = self.currentPlayerIndex + 1
    
    -- Skip players with blackjack
    self:SkipToNextNonBlackjackPlayer()
end

-- Dealer plays out their hand
function GS:PlayDealerHand()
    self.phase = self.PHASE.DEALER_TURN
    self.dealerHoleCardRevealed = true
    
    BJ:Debug("Dealer reveals: " .. self:FormatHand(self.dealerHand))
    self:LogDealerAction("REVEAL", self:FormatHand(self.dealerHand))
    
    -- Check if any player hands need dealer to play
    -- Dealer doesn't need to play if all hands are already resolved (bust, blackjack, 5-card charlie)
    local anyNeedDealer = false
    for _, playerName in ipairs(self.playerOrder) do
        local player = self.players[playerName]
        for i, outcome in ipairs(player.outcomes) do
            -- PENDING means this hand needs dealer to play to determine outcome
            if outcome == self.OUTCOME.PENDING then
                anyNeedDealer = true
                break
            end
        end
        if anyNeedDealer then break end
    end
    
    -- If all player hands are already resolved, dealer doesn't need to play
    if not anyNeedDealer then
        BJ:Debug("All player hands resolved, dealer stands")
        self:LogDealerAction("STAND", "All hands resolved")
        self:SettleHands()
        return
    end
    
    -- Check if dealer should auto-stand based on H17/S17 rule
    local score = self:ScoreHand(self.dealerHand)
    local shouldStand = self:DealerShouldStand(score)
    
    if shouldStand then
        BJ:Debug("Dealer stands at " .. score.total .. (score.isSoft and " (soft)" or "") .. (score.isBust and " (BUST)" or ""))
        self:LogDealerAction("STAND", score.total .. (score.isSoft and " soft" or "") .. (score.isBust and " BUST" or ""))
        self:SettleHands()
        return
    end
    
    -- Dealer needs to act - wait for host to control
    -- Host will call DealerHit or DealerStand
    BJ:Debug("Dealer has " .. score.total .. (score.isSoft and " (soft)" or "") .. ", must hit")
end

-- Check if dealer should stand based on H17/S17 rule
function GS:DealerShouldStand(score)
    if score.isBust then
        return true  -- Busted, stop
    end
    
    if score.total > 17 then
        return true  -- Always stand on 18+
    end
    
    if score.total < 17 then
        return false  -- Always hit below 17
    end
    
    -- score.total == 17
    if score.isSoft then
        -- Soft 17: depends on rule
        -- H17 = dealer hits soft 17, S17 = dealer stands on soft 17
        return not self.dealerHitsSoft17
    else
        -- Hard 17: always stand
        return true
    end
end

-- Dealer hits (called by host)
function GS:DealerHit()
    if self.phase ~= self.PHASE.DEALER_TURN then
        return false, "Not dealer's turn"
    end
    
    local card = self:DrawCard()
    table.insert(self.dealerHand, card)
    local score = self:ScoreHand(self.dealerHand)
    
    BJ:Debug("Dealer draws: " .. self:CardToString(card) .. " (Total: " .. score.total .. (score.isSoft and " soft" or "") .. ")")
    self:LogDealerAction("HIT", self:CardToString(card) .. " -> " .. score.total .. (score.isSoft and " soft" or ""))
    
    -- Check if bust or should auto-stand based on H17/S17 rule
    if score.isBust then
        BJ:Debug("Dealer busts at " .. score.total)
        self:LogDealerAction("BUST", score.total)
        self:SettleHands()
        return true, card, true  -- true = settled
    end
    
    if self:DealerShouldStand(score) then
        BJ:Debug("Dealer stands at " .. score.total .. (score.isSoft and " (soft)" or ""))
        self:LogDealerAction("STAND", score.total .. (score.isSoft and " soft" or ""))
        self:SettleHands()
        return true, card, true  -- true = settled
    end
    
    return true, card, false  -- false = need more action
end

-- Dealer stands (called by host) - shouldn't normally be called since auto-stand at 17
function GS:DealerStand()
    if self.phase ~= self.PHASE.DEALER_TURN then
        return false, "Not dealer's turn"
    end
    
    local score = self:ScoreHand(self.dealerHand)
    BJ:Debug("Dealer stands at " .. score.total)
    self:LogDealerAction("STAND", score.total)
    self:SettleHands()
    return true
end

-- Check if dealer needs to act (for UI)
function GS:DealerNeedsAction()
    if self.phase ~= self.PHASE.DEALER_TURN then
        return false
    end
    local score = self:ScoreHand(self.dealerHand)
    return not self:DealerShouldStand(score)
end

-- Settle all hands and calculate payouts
function GS:SettleHands()
    self.phase = self.PHASE.SETTLEMENT
    self.settlements = {}
    
    local dealerScore = self:ScoreHand(self.dealerHand)
    local dealerBlackjack = dealerScore.isBlackjack
    
    -- Process insurance first
    if self.insuranceOffered and dealerBlackjack then
        for _, playerName in ipairs(self.playerOrder) do
            local player = self.players[playerName]
            if player.insurance > 0 then
                -- Insurance pays 2:1
                local insurancePayout = player.insurance * 2
                self.settlements[playerName] = self.settlements[playerName] or { total = 0, details = {} }
                self.settlements[playerName].total = self.settlements[playerName].total + insurancePayout
                table.insert(self.settlements[playerName].details, {
                    type = "insurance",
                    result = "win",
                    amount = insurancePayout
                })
            end
        end
    else
        -- Insurance lost
        for _, playerName in ipairs(self.playerOrder) do
            local player = self.players[playerName]
            if player.insurance > 0 then
                self.settlements[playerName] = self.settlements[playerName] or { total = 0, details = {} }
                self.settlements[playerName].total = self.settlements[playerName].total - player.insurance
                table.insert(self.settlements[playerName].details, {
                    type = "insurance",
                    result = "lose",
                    amount = -player.insurance
                })
            end
        end
    end
    
    -- Process each player's hands
    for _, playerName in ipairs(self.playerOrder) do
        local player = self.players[playerName]
        self.settlements[playerName] = self.settlements[playerName] or { total = 0, details = {} }
        
        for i, hand in ipairs(player.hands) do
            local bet = player.bets[i]
            local handScore = self:ScoreHand(hand)
            local outcome = player.outcomes[i]
            local payout = 0
            local hasFiveCardCharlie = player.hasFiveCardCharlie and player.hasFiveCardCharlie[i]
            
            -- Already determined (bust)
            if outcome == self.OUTCOME.BUST then
                payout = -bet
            
            -- 5 Card Charlie beats everything except dealer blackjack when player has 2 cards
            -- Since 5 card charlie requires 5 cards, dealer blackjack is irrelevant
            elseif hasFiveCardCharlie then
                outcome = self.OUTCOME.WIN
                payout = bet  -- Pays 1:1 like a regular win
                
            -- Player blackjack
            elseif handScore.isBlackjack then
                -- Split aces don't count as blackjack - pay 1:1 only
                if player.splitAcesHands and player.splitAcesHands[i] then
                    if dealerBlackjack then
                        outcome = self.OUTCOME.PUSH
                        payout = 0
                    elseif dealerScore.isBust then
                        outcome = self.OUTCOME.WIN
                        payout = bet  -- 1:1 for split aces
                    elseif handScore.total > dealerScore.total then
                        outcome = self.OUTCOME.WIN
                        payout = bet  -- 1:1 for split aces
                    elseif handScore.total < dealerScore.total then
                        outcome = self.OUTCOME.LOSE
                        payout = -bet
                    else
                        outcome = self.OUTCOME.PUSH
                        payout = 0
                    end
                elseif dealerBlackjack then
                    outcome = self.OUTCOME.PUSH
                    payout = 0
                else
                    outcome = self.OUTCOME.BLACKJACK
                    -- 3:2 payout: 1g bet wins 1g 50s (stored as 1.5 gold)
                    -- We store payouts as decimal gold for proper 3:2
                    payout = bet * 1.5
                end
                
            -- Dealer blackjack (player loses unless also blackjack, handled above)
            elseif dealerBlackjack then
                outcome = self.OUTCOME.LOSE
                payout = -bet
                
            -- Dealer busts
            elseif dealerScore.isBust then
                outcome = self.OUTCOME.WIN
                payout = bet
                
            -- Compare scores
            elseif handScore.total > dealerScore.total then
                outcome = self.OUTCOME.WIN
                payout = bet
            elseif handScore.total < dealerScore.total then
                outcome = self.OUTCOME.LOSE
                payout = -bet
            else
                outcome = self.OUTCOME.PUSH
                payout = 0
            end
            
            player.outcomes[i] = outcome
            player.payouts[i] = payout
            self.settlements[playerName].total = self.settlements[playerName].total + payout
            
            table.insert(self.settlements[playerName].details, {
                type = "hand",
                handIndex = i,
                hand = self:FormatHand(hand),
                score = handScore.total,
                bet = bet,
                result = outcome,
                amount = payout
            })
        end
    end
    
    -- Build final ledger showing who owes who
    self:BuildSettlementLedger()
    
    -- Save to game history
    self:SaveGameToHistory()
end

-- Build human-readable settlement ledger
function GS:BuildSettlementLedger()
    self.ledger = {
        hostProfit = 0,
        entries = {}
    }
    
    for _, playerName in ipairs(self.playerOrder) do
        local settlement = self.settlements[playerName]
        if settlement then
            local netAmount = settlement.total
            self.ledger.hostProfit = self.ledger.hostProfit - netAmount  -- House wins what players lose
            
            local entry = {
                player = playerName,
                net = netAmount,
                details = settlement.details
            }
            table.insert(self.ledger.entries, entry)
        end
    end
    
    BJ:Debug("Settlement complete. Host profit: " .. self.ledger.hostProfit)
end

-- Build settlements and ledger from synced outcomes/payouts (for clients)
function GS:BuildSettlementFromSync()
    self.settlements = {}
    self.ledger = {
        hostProfit = 0,
        entries = {}
    }
    
    local dealerScore = self:ScoreHand(self.dealerHand)
    
    for _, playerName in ipairs(self.playerOrder) do
        local player = self.players[playerName]
        if player then
            local settlement = { total = 0, details = {} }
            
            for i, hand in ipairs(player.hands) do
                local bet = player.bets[i] or 0
                local outcome = player.outcomes[i] or self.OUTCOME.PENDING
                local payout = player.payouts[i] or 0
                local handScore = self:ScoreHand(hand)
                
                settlement.total = settlement.total + payout
                
                -- Build result string
                local resultStr = "unknown"
                if outcome == self.OUTCOME.WIN then
                    resultStr = "WIN"
                elseif outcome == self.OUTCOME.LOSE then
                    resultStr = "LOSE"
                elseif outcome == self.OUTCOME.PUSH then
                    resultStr = "PUSH"
                elseif outcome == self.OUTCOME.BLACKJACK then
                    resultStr = "BLACKJACK"
                elseif outcome == self.OUTCOME.BUST then
                    resultStr = "BUST"
                end
                
                table.insert(settlement.details, {
                    type = "hand",
                    handIndex = i,
                    hand = self:FormatHand(hand),
                    score = handScore.total,
                    bet = bet,
                    result = resultStr,
                    amount = payout
                })
            end
            
            self.settlements[playerName] = settlement
            self.ledger.hostProfit = self.ledger.hostProfit - settlement.total
            
            table.insert(self.ledger.entries, {
                player = playerName,
                net = settlement.total,
                details = settlement.details
            })
        end
    end
end

-- Get settlement summary text
function GS:GetSettlementSummary()
    if not self.ledger then
        return "No settlement data"
    end
    
    local lines = {}
    table.insert(lines, "=== Settlement ===")
    table.insert(lines, "Dealer: " .. self:FormatHand(self.dealerHand) .. " (" .. self:ScoreHand(self.dealerHand).total .. ")")
    table.insert(lines, "")
    
    for _, entry in ipairs(self.ledger.entries) do
        local status
        if entry.net > 0 then
            status = "|cff00ff00" .. self:FormatGold(entry.net) .. "|r"
        elseif entry.net < 0 then
            status = "|cffff0000" .. self:FormatGold(entry.net) .. "|r"
        else
            status = "|cffffff00Push|r"
        end
        table.insert(lines, entry.player .. ": " .. status)
        
        for _, detail in ipairs(entry.details) do
            if detail.type == "hand" then
                table.insert(lines, "  Hand " .. detail.handIndex .. ": " .. detail.hand .. 
                    " (" .. detail.score .. ") - " .. detail.result)
            elseif detail.type == "insurance" then
                table.insert(lines, "  Insurance: " .. detail.result)
            end
        end
    end
    
    table.insert(lines, "")
    table.insert(lines, "--- Who Owes Who ---")
    
    for _, entry in ipairs(self.ledger.entries) do
        if entry.net > 0 then
            table.insert(lines, self.hostName .. " owes " .. entry.player .. " " .. self:FormatGold(entry.net))
        elseif entry.net < 0 then
            table.insert(lines, entry.player .. " owes " .. self.hostName .. " " .. self:FormatGold(math.abs(entry.net)))
        end
    end
    
    if self.ledger.hostProfit > 0 then
        table.insert(lines, "")
        table.insert(lines, "House profit: |cff00ff00" .. self:FormatGold(self.ledger.hostProfit) .. "|r")
    elseif self.ledger.hostProfit < 0 then
        table.insert(lines, "")
        table.insert(lines, "House loss: |cffff0000" .. self:FormatGold(self.ledger.hostProfit) .. "|r")
    end
    
    return table.concat(lines, "\n")
end

-- Check if can split current hand
function GS:CanSplit(playerName)
    local player = self.players[playerName]
    if not player then return false end
    
    local hand = player.hands[player.activeHandIndex]
    if #hand ~= 2 then return false end
    if hand[1].rank ~= hand[2].rank then return false end
    if #player.hands >= 4 then return false end
    
    return true
end

-- Check if can double current hand
function GS:CanDouble(playerName)
    local player = self.players[playerName]
    if not player then return false end
    
    local hand = player.hands[player.activeHandIndex]
    return #hand == 2
end

-- Check if insurance is available
function GS:CanInsurance(playerName)
    if not self.insuranceOffered then return false end
    if self.phase ~= self.PHASE.PLAYER_TURN then return false end
    
    local player = self.players[playerName]
    if not player then return false end
    if player.insurance > 0 then return false end  -- Already took insurance
    
    return true
end

--[[
    GAME HISTORY LOG (Last 5 games)
]]
GS.gameHistory = {}
GS.MAX_HISTORY = 5
GS.currentGameLog = nil

-- Start logging a new game
function GS:StartGameLog()
    self.currentGameLog = {
        timestamp = time(),
        host = self.hostName,
        ante = self.ante,
        players = {},
        actions = {},
        dealerActions = {},
        results = {},
    }
end

-- Log a player action
function GS:LogAction(playerName, action, details)
    if not self.currentGameLog then return end
    table.insert(self.currentGameLog.actions, {
        time = time(),
        player = playerName,
        action = action,
        details = details or ""
    })
end

-- Log dealer action
function GS:LogDealerAction(action, details)
    if not self.currentGameLog then return end
    table.insert(self.currentGameLog.dealerActions, {
        time = time(),
        action = action,
        details = details or ""
    })
end

-- Save game to history
function GS:SaveGameToHistory()
    if not self.currentGameLog then return end
    
    -- Record final hands and results
    self.currentGameLog.dealerHand = self:FormatHand(self.dealerHand)
    self.currentGameLog.dealerScore = self:ScoreHand(self.dealerHand).total
    
    for _, playerName in ipairs(self.playerOrder) do
        local player = self.players[playerName]
        local playerResult = {
            name = playerName,
            hands = {},
            totalNet = 0
        }
        
        for i, hand in ipairs(player.hands) do
            table.insert(playerResult.hands, {
                cards = self:FormatHand(hand),
                score = self:ScoreHand(hand).total,
                bet = player.bets[i],
                outcome = player.outcomes[i],
                payout = player.payouts[i]
            })
            playerResult.totalNet = playerResult.totalNet + (player.payouts[i] or 0)
        end
        
        table.insert(self.currentGameLog.results, playerResult)
    end
    
    -- Add to history, keeping only last 5
    table.insert(self.gameHistory, 1, self.currentGameLog)
    while #self.gameHistory > self.MAX_HISTORY do
        table.remove(self.gameHistory)
    end
    
    self.currentGameLog = nil
    
    -- Save to persistent storage
    self:SaveHistoryToDB()
end

-- Save game history to SavedVariables (encoded)
function GS:SaveHistoryToDB()
    if not ChairfacesCasinoSaved then
        ChairfacesCasinoSaved = {}
    end
    
    if BJ.Compression and BJ.Compression.EncodeForSave then
        ChairfacesCasinoSaved.blackjackHistory = BJ.Compression:EncodeForSave(self.gameHistory)
    end
end

-- Load game history from SavedVariables
function GS:LoadHistoryFromDB()
    if not ChairfacesCasinoSaved or not ChairfacesCasinoSaved.blackjackHistory then
        return
    end
    
    if BJ.Compression and BJ.Compression.DecodeFromSave then
        local decoded = BJ.Compression:DecodeFromSave(ChairfacesCasinoSaved.blackjackHistory)
        if decoded and type(decoded) == "table" then
            self.gameHistory = decoded
            BJ:Debug("Loaded " .. #self.gameHistory .. " blackjack games from history")
        end
    end
end

-- Get formatted game history text
function GS:GetGameLogText()
    if #self.gameHistory == 0 then
        return "No game history yet."
    end
    
    local lines = {}
    
    for gameNum, game in ipairs(self.gameHistory) do
        table.insert(lines, "")
        table.insert(lines, "|cffffffff=============== GAME " .. gameNum .. " ===============|r")
        table.insert(lines, "")
        table.insert(lines, "Host: " .. (game.host or "Unknown") .. " | Ante: " .. (game.ante or 0) .. "g")
        table.insert(lines, "")
        
        -- Player actions
        table.insert(lines, "|cff88ffffPlayer Actions:|r")
        for _, action in ipairs(game.actions or {}) do
            table.insert(lines, "  " .. action.player .. ": " .. action.action .. (action.details ~= "" and (" - " .. action.details) or ""))
        end
        
        -- Dealer actions
        if game.dealerActions and #game.dealerActions > 0 then
            table.insert(lines, "")
            table.insert(lines, "|cffff8888Dealer:|r " .. (game.dealerHand or "?") .. " = " .. (game.dealerScore or "?"))
            for _, action in ipairs(game.dealerActions) do
                table.insert(lines, "  " .. action.action .. (action.details ~= "" and (" - " .. action.details) or ""))
            end
        end
        
        -- Results
        table.insert(lines, "")
        table.insert(lines, "|cff88ff88Results:|r")
        for _, result in ipairs(game.results or {}) do
            for i, hand in ipairs(result.hands) do
                -- Convert outcome to string if it's a number/enum
                local outcomeStr = hand.outcome
                if type(outcomeStr) ~= "string" then
                    outcomeStr = tostring(outcomeStr) or "?"
                end
                local outcomeColor = outcomeStr == "win" and "00ff00" or (outcomeStr == "blackjack" and "ffd700" or (outcomeStr == "push" and "ffff00" or "ff4444"))
                local netStr = self:FormatGold(hand.payout or 0)
                table.insert(lines, "  " .. result.name .. (#result.hands > 1 and (" H" .. i) or "") .. ": " .. hand.cards .. " = " .. hand.score .. " |cff" .. outcomeColor .. "[" .. outcomeStr:upper() .. "]|r " .. netStr)
            end
        end
        
        table.insert(lines, "")
    end
    
    return table.concat(lines, "\n")
end
