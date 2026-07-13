--[[
    Chairface's Casino - PokerEngine.lua
    Shared poker logic for the stud (5 Card Stud) and community-card
    (Texas Hold'em) games: constants, deck management, betting rounds,
    player actions, hand evaluation, showdown/settlement, and history.

    Usage: BJ.PokerEngine:Embed(stateModule, config) right after the module
    table is created. Config fields:
        game            Leaderboard/StateSync game key ("poker", "holdem")
        debugName       Short name for debug messages ("Poker", "Holdem")
        displayName     User-facing name ("5 Card Stud", "Texas Hold'em")
        historyKey      ChairfacesCasinoSaved key for game history
        getMP           function -> the game's Multiplayer module

    Games define after Embed (later definitions override the defaults):
        Reset, StartRound, seating/ante handling, StartBettingRound,
        FindBettingStarter, and (Hold'em) GetShowdownEval/GetBestHand
        for best-5-of-7 evaluation over the community cards.
]]

local BJ = ChairfacesCasino
BJ.PokerEngine = {}
local PE = BJ.PokerEngine

--[[
    SHARED CONSTANTS (one table instance shared by both games - treat as read-only)
]]

-- Hand rankings (higher = better)
PE.HAND_RANK = {
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

PE.HAND_NAMES = {
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
PE.PHASE = {
    IDLE = "idle",
    WAITING_FOR_PLAYERS = "waiting",      -- Waiting for antes/seats
    DEALING = "dealing",                   -- Cards being dealt (animation)
    BETTING = "betting",                   -- Betting round in progress
    SHOWDOWN = "showdown",                 -- Revealing hole cards
    SETTLEMENT = "settlement",             -- Results
}

-- Betting streets (how many betting rounds have opened)
PE.STREET = {
    ANTE = 0,      -- Pre-deal
    FIRST = 1,
    SECOND = 2,
    THIRD = 3,
    FOURTH = 4,    -- Final street (river)
}

-- Player actions
PE.ACTION = {
    FOLD = "fold",
    CHECK = "check",
    CALL = "call",
    RAISE = "raise",
}

--[[
    SHARED METHODS (copied onto each game's state module by Embed)
]]

local M = {}

--[[
    DECK MANAGEMENT
]]

-- Create and shuffle a fresh deck (1 deck per hand)
function M:CreateDeck(seed)
    self.seed = seed or time()
    self.deck = BJ.CardLib:CreateShuffledDeck(self.seed, 1, self.RANKS, self.SUITS)
    self.cardIndex = 1

    BJ:Debug(self.debugName .. " deck shuffled: " .. #self.deck .. " cards")
end

function M:DrawCard()
    if self.cardIndex > #self.deck then
        BJ:Print("Error: Deck exhausted!")
        return nil
    end
    local card = self.deck[self.cardIndex]
    self.cardIndex = self.cardIndex + 1
    return card
end

function M:GetRemainingCards()
    -- Use synced value for non-host clients
    local mp = self.GetMP and self.GetMP()
    if self.syncedCardsRemaining and mp and not mp.isHost then
        return self.syncedCardsRemaining
    end
    return #self.deck - self.cardIndex + 1
end

--[[
    GAME FLOW
]]

-- Start the deal (called by host)
function M:StartDeal()
    if self.phase ~= self.PHASE.WAITING_FOR_PLAYERS then
        return false, "Cannot deal - wrong phase"
    end

    if #self.playerOrder < 2 then
        return false, "Need at least 2 players"
    end

    -- Tournament: lock the doors on the first deal (no mid-entry) and cap
    -- this hand's total commitment at the shortest stack, so every bet is
    -- always callable and the single-pot settlement needs no side pots.
    if self.tourney then
        self.tourney.started = true
        self:RecomputeTourneyCap()
        self.tourneyApplied = false
    end

    self.phase = self.PHASE.DEALING
    self.currentStreet = 0
    return true
end

-- The tournament hand cap: min chips among the seated stacks. Deterministic
-- from synced chip counts, so hosts and clients agree without a message.
function M:RecomputeTourneyCap()
    if not self.tourney then self.tourneyHandCap = nil return end
    local cap
    for _, name in ipairs(self.playerOrder) do
        local c = self.tourney.chips[name] or 0
        if not cap or c < cap then cap = c end
    end
    self.tourneyHandCap = cap or 0
end

-- Deal one card to a player (called during animation)
function M:DealCardToPlayer(playerName, faceUp)
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

function M:GetVisibleCards(playerName)
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

function M:GetCurrentPlayer()
    if self.phase ~= self.PHASE.BETTING then return nil end
    return self.playerOrder[self.currentPlayerIndex]
end

function M:CanPlayerAct(playerName)
    if self.phase ~= self.PHASE.BETTING then return false end
    return playerName == self:GetCurrentPlayer()
end

function M:GetActivePlayers()
    local count = 0
    for _, playerName in ipairs(self.playerOrder) do
        local player = self.players[playerName]
        if player and not player.folded then
            count = count + 1
        end
    end
    return count
end

function M:GetAvailableActions(playerName)
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
        local canRaise = true
        -- tournament: a raise must fit under the hand cap (shortest stack)
        if self.tourney and self.tourneyHandCap then
            canRaise = (player.totalBet or 0) + math.max(0, toCall) + 1
                <= self.tourneyHandCap
        end
        if canRaise then
            table.insert(actions, self.ACTION.RAISE)
        end
    end

    return actions
end

--[[
    PLAYER ACTIONS
]]

function M:PlayerFold(playerName)
    if self.phase ~= self.PHASE.BETTING then
        return false, "Cannot fold outside of betting phase"
    end

    -- Folding is only allowed on your own turn, like every other action.
    if not self:CanPlayerAct(playerName) then
        return false, "Not your turn"
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

    -- personal teasing line only when YOU fold (long cd so it stays a treat)
    if playerName == UnitName("player") and BJ.UI and BJ.UI.Lobby then
        BJ.UI.Lobby:PlayTrixieVoice("poker_fold", { cd = 45 })
    end

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

function M:PlayerCheck(playerName)
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

function M:PlayerCall(playerName)
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

function M:PlayerRaise(playerName, raiseAmount)
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

    -- Tournament: total commitment this hand is capped at the shortest
    -- stack at the deal, so every raise stays callable by everyone (the
    -- table-stakes rule that makes side pots unnecessary)
    if self.tourney and self.tourneyHandCap then
        if (player.totalBet or 0) + totalCost > self.tourneyHandCap then
            return false, "Raise exceeds the table cap of "
                .. self.tourneyHandCap .. " chips (the shortest stack)"
        end
    end

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

function M:AdvanceToNextPlayer()
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

function M:IsBettingRoundComplete(nextPlayer)
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

function M:EndBettingRound()
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

function M:EndHandEarly()
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

--[[
    SHOWDOWN AND SETTLEMENT
]]

-- Evaluate a player's full holding at showdown. Stud evaluates the 5-card
-- hand directly; Hold'em overrides this to pick the best 5 of 7.
function M:GetShowdownEval(hand)
    return self:EvaluateHand(hand)
end

function M:StartShowdown()
    self.phase = self.PHASE.SHOWDOWN

    local evaluations = {}
    for _, playerName in ipairs(self.playerOrder) do
        local player = self.players[playerName]
        if player and not player.folded then
            local eval = self:GetShowdownEval(player.hand)
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

function M:CalculateSettlements()
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
            local eval = self:GetShowdownEval(player.hand)
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

        -- Record to leaderboard (host only - clients get updates via
        -- broadcast). Tournament hands move CHIPS, not gold: nothing is
        -- recorded per hand - the buy-ins settle once at tournament end.
        if BJ.Leaderboard and not self.tourney then
            local myName = UnitName("player")
            if not self.hostName or self.hostName == myName then
                local outcome = isWinner and "win" or "lose"
                if player.folded then outcome = "lose" end
                BJ.Leaderboard:RecordHandResult(self.gameKey, playerName, payout, outcome)
            end
        end
    end

    -- Session debt ledger: losers pay winners (host records for the group,
    -- same gate as the leaderboard above; suppressed in tournaments).
    -- Fun/real status fixed at table open: a mid-game toggle flip only
    -- affects the next hosted table
    if BJ.DebtLedger and not self.tourney then
        local myName = UnitName("player")
        if not self.hostName or self.hostName == myName then
            local nets = {}
            for name, s in pairs(self.settlements) do
                nets[name] = s.total
            end
            BJ.DebtLedger:RecordNets(self.gameKey, nets, self.fakePlay)
        end
    end

    -- Tournament: move the chips, flag busts, crown the champion
    if self.tourney then
        self:ApplyTourneyResult()
    end

    BJ:Debug("CalculateSettlements complete. Total settlements: " .. (next(self.settlements) and "yes" or "no"))
end

--[[
    TOURNAMENT BOOKKEEPING (shared; a game opts in by setting self.tourney
    via its StartTourney - currently Hold'em only)

    Settlements move CHIPS between stacks, never gold. A stack at zero is
    eliminated (seat removed at the next hand). When one stack holds
    everything the tournament ends and THAT is when gold moves: every
    entrant owes the champion one buy-in, recorded through the debt ledger
    (host-gated and fake-play aware like every other game). Deterministic
    from the synced settlements, so clients run the same math the host does.
]]
function M:ApplyTourneyResult()
    local t = self.tourney
    if not t or self.tourneyApplied then return end
    self.tourneyApplied = true

    for name, s in pairs(self.settlements or {}) do
        if t.chips[name] ~= nil then
            t.chips[name] = math.max(0, t.chips[name] + (s.total or 0))
        end
    end

    local alive = {}
    local newlyOut = false
    for _, name in ipairs(self.playerOrder) do
        if (t.chips[name] or 0) <= 0 then
            if not t.out[name] then
                t.out[name] = true
                newlyOut = true
                table.insert(t.eliminated, name)
                BJ:Print("|cffff8800" .. name .. " is out of chips - eliminated!|r")
            end
        else
            table.insert(alive, name)
        end
    end

    if #alive == 1 and not t.champion then
        t.champion = alive[1]
        self:FinishTourney()  -- plays the champion line; skip bustout below
    elseif newlyOut and BJ.UI and BJ.UI.Lobby then
        BJ.UI.Lobby:PlayTrixieVoice("tourney_bustout", { cd = 8 })
    end
end

-- A player abandons the tournament (left the table / disconnected past
-- recovery): their stack is forfeit but their buy-in still pays the champion.
function M:TourneyForfeit(playerName)
    local t = self.tourney
    if not t or not t.entrants[playerName] then return end
    t.chips[playerName] = 0
    if not t.out[playerName] then
        t.out[playerName] = true
        table.insert(t.eliminated, playerName)
        BJ:Print("|cffff8800" .. playerName .. " forfeits the tournament (buy-in stays in the prize).|r")
    end
    -- forfeit can end the tournament too
    local alive = {}
    for _, name in ipairs(self.playerOrder) do
        if (t.chips[name] or 0) > 0 then table.insert(alive, name) end
    end
    if #alive == 1 and not t.champion then
        t.champion = alive[1]
        self:FinishTourney()
    end
end

function M:FinishTourney()
    local t = self.tourney
    if not t or not t.champion or t.settled then return end
    t.settled = true

    -- The prize pool is every buy-in and the champion takes it all
    -- (forfeits count - a walkout's buy-in stays in the pool). A 50/30/20
    -- top-three split was sized for multi-table fields; with a single
    -- table it's winner-take-all - revisit if multi-table ever returns.
    local entrants = 0
    for _ in pairs(t.entrants) do entrants = entrants + 1 end
    local pool = t.buyIn * entrants

    local nets = {}
    for name in pairs(t.entrants) do nets[name] = -t.buyIn end
    nets[t.champion] = pool - t.buyIn

    BJ:Print("|cffffd700" .. t.champion .. " wins the tournament and the whole pool: "
        .. pool .. "g!|r")
    if BJ.UI and BJ.UI.Lobby then
        BJ.UI.Lobby:PlayTrixieVoice("tourney_champ", { noFreq = true })
    end

    local myName = UnitName("player")
    local isRecorder = (not self.hostName or self.hostName == myName)
    if isRecorder and entrants > 1 then
        if BJ.DebtLedger then
            -- Terms fixed when the tournament table opened, like cash games
            BJ.DebtLedger:RecordNets(self.gameKey, nets, self.fakePlay)
        end
        if BJ.Leaderboard then
            for name, net in pairs(nets) do
                BJ.Leaderboard:RecordHandResult(self.gameKey, name, net,
                    net > 0 and "win" or "lose")
            end
        end
    end
end

--[[
    HAND NAMING
]]

-- Convert rank value (2-14) to display name
function M:RankValueToName(val)
    local names = {
        [2] = "2's", [3] = "3's", [4] = "4's", [5] = "5's", [6] = "6's",
        [7] = "7's", [8] = "8's", [9] = "9's", [10] = "10's",
        [11] = "Jacks", [12] = "Queens", [13] = "Kings", [14] = "Aces"
    }
    return names[val] or tostring(val)
end

-- Convert rank value to single card name (for kickers)
function M:RankValueToCard(val)
    local names = {
        [2] = "2", [3] = "3", [4] = "4", [5] = "5", [6] = "6",
        [7] = "7", [8] = "8", [9] = "9", [10] = "10",
        [11] = "J", [12] = "Q", [13] = "K", [14] = "A"
    }
    return names[val] or tostring(val)
end

-- Get detailed hand description with optional kickers (only show kicker if it was a tiebreaker)
function M:GetDetailedHandName(eval, showKicker)
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

function M:EvaluateHand(hand)
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

function M:IsStraight(rankValues)
    if #rankValues < 5 then return false end
    local sorted = { unpack(rankValues) }
    table.sort(sorted, function(a, b) return a > b end)
    for i = 1, 4 do
        if sorted[i] - sorted[i + 1] ~= 1 then return false end
    end
    return true
end

function M:CompareHands(evalA, evalB)
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

function M:FormatHand(hand)
    local parts = {}
    for _, card in ipairs(hand) do
        table.insert(parts, card.rank)
    end
    return table.concat(parts, " ")
end

function M:CardToString(card)
    return card.rank
end

function M:GetPlayerCount()
    return #self.playerOrder
end

function M:CanJoin()
    if self.phase ~= self.PHASE.WAITING_FOR_PLAYERS then
        return false, "Game not accepting players"
    end
    local maxPlayers = self.maxPlayers or self.MAX_PLAYERS
    if #self.playerOrder >= maxPlayers then
        return false, "Table full"
    end
    return true
end

function M:GetSettlementSummary()
    if not self.settlements then return "No settlement data" end

    local lines = {}
    table.insert(lines, "=== " .. self.displayName .. " Results ===")
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

-- Save game to history (called after settlement)
function M:SaveGameToHistory()
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
    BJ.GameHistory:Add(self.gameHistory, game, self.MAX_HISTORY)

    BJ:Debug(self.debugName .. " game saved to history. Total games: " .. #self.gameHistory)

    -- Save to persistent storage
    self:SaveHistoryToDB()
end

-- Save game history to SavedVariables (encoded)
function M:SaveHistoryToDB()
    BJ.GameHistory:Save(self.historyKey, self.gameHistory)
end

-- Load game history from SavedVariables
function M:LoadHistoryFromDB()
    local history = BJ.GameHistory:Load(self.historyKey)
    if history then
        self.gameHistory = history
        BJ:Debug("Loaded " .. #self.gameHistory .. " " .. self.gameKey .. " games from history")
    end
end

-- Get formatted game history text for log window
function M:GetGameLogText()
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

--[[
    EMBED
]]

function PE:Embed(target, config)
    target.gameKey = config.game
    target.debugName = config.debugName
    target.displayName = config.displayName
    target.historyKey = config.historyKey
    target.GetMP = config.getMP

    -- Constants
    target.MAX_PLAYERS = 10
    target.CARDS_PER_HAND = 5
    target.CARDS_PER_DECK = 52
    target.SUITS = BJ.CardLib.SUITS
    target.RANKS = BJ.CardLib.POKER_RANKS
    target.RANK_VALUES = BJ.CardLib.POKER_RANK_VALUES
    target.HAND_RANK = PE.HAND_RANK
    target.HAND_NAMES = PE.HAND_NAMES
    target.PHASE = PE.PHASE
    target.STREET = PE.STREET
    target.ACTION = PE.ACTION

    -- Game history
    target.gameHistory = {}
    target.MAX_HISTORY = 5

    for name, fn in pairs(M) do
        target[name] = fn
    end

    return target
end
