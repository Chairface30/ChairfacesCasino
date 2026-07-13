--[[
    Chairface's Casino - BingoState.lua
    75-ball Bingo game state management

    Game flow:
    1. Host opens a game with a card price; a shared seed is broadcast
    2. Players buy in; every card is generated deterministically from
       (seed, playerName), so any client can verify any card
    3. Host starts the draw: numbers come from a seeded shuffle of 1-75,
       one every few seconds
    4. Cards auto-daub. After each draw the host checks every card;
       first completed line (row, column, or diagonal - center is FREE)
       wins the pot. Simultaneous winners split it.
]]

local BJ = ChairfacesCasino
BJ.BingoState = {}
local BS = BJ.BingoState

-- Constants
BS.MAX_PLAYERS = 40
BS.NUMBERS = 75
BS.COLUMN_LETTERS = { "B", "I", "N", "G", "O" }

-- Game phases
BS.PHASE = {
    IDLE = "idle",
    LOBBY = "lobby",           -- Waiting for players to buy cards
    DRAWING = "drawing",       -- Numbers being called
    SETTLEMENT = "settlement",
}

-- Reset state
function BS:Reset()
    self.phase = self.PHASE.IDLE
    self.hostName = nil
    self.cardPrice = 0
    self.seed = nil
    self.players = {}          -- { name = { card = card } }
    self.playerOrder = {}
    self.drawn = {}            -- ordered list of called numbers
    self.drawnSet = {}         -- [number] = true
    self.drawPool = nil        -- host's seeded shuffle of 1..75
    self.drawIndex = 0
    self.winners = {}
    self.pot = 0
    self.share = 0
end

BS:Reset()

-- Deterministic per-player card: 5x5, column c drawing from
-- (c-1)*15+1 .. c*15, center square free. Every client generates
-- identical cards from the shared seed, so cards are verifiable.
function BS:GenerateCard(seed, playerName)
    local nameHash = 0
    for i = 1, #playerName do
        nameHash = (nameHash * 31 + string.byte(playerName, i)) % 2147483647
    end
    local rng = BJ.CardLib.SeededRandom((seed + nameHash) % 2147483647 + 1)

    local card = {}
    for row = 1, 5 do card[row] = {} end

    for col = 1, 5 do
        -- Partial Fisher-Yates over this column's 15 numbers
        local nums = {}
        for n = 1, 15 do nums[n] = (col - 1) * 15 + n end
        for i = 15, 2, -1 do
            local j = math.floor(rng() * i) + 1
            nums[i], nums[j] = nums[j], nums[i]
        end
        for row = 1, 5 do
            card[row][col] = nums[row]
        end
    end

    card[3][3] = 0  -- FREE center
    return card
end

-- Host opens a game
function BS:HostGame(hostName, cardPrice, seed)
    self:Reset()

    self.phase = self.PHASE.LOBBY
    self.hostName = hostName
    self.cardPrice = cardPrice
    self.seed = seed

    -- Host plays too
    self:AddPlayer(hostName)

    BJ:Debug("Bingo hosted by " .. hostName .. " at " .. cardPrice .. "g a card (seed " .. seed .. ")")
    return true
end

-- A player buys a card
function BS:AddPlayer(playerName)
    if self.phase ~= self.PHASE.LOBBY then
        return false, "Cannot join - game not in lobby phase"
    end

    if self.players[playerName] then
        return false, "Already joined"
    end

    if #self.playerOrder >= self.MAX_PLAYERS then
        return false, "Game is full (" .. self.MAX_PLAYERS .. " players max)"
    end

    self.players[playerName] = {
        card = self:GenerateCard(self.seed, playerName),
    }
    table.insert(self.playerOrder, playerName)

    BJ:Debug(playerName .. " bought a bingo card")
    return true
end

-- Remove a player (lobby phase only)
function BS:RemovePlayer(playerName)
    if self.phase ~= self.PHASE.LOBBY then
        return false, "Cannot leave after the draw starts"
    end
    if playerName == self.hostName then
        return false, "Host cannot leave"
    end
    if not self.players[playerName] then
        return false, "Not in game"
    end

    self.players[playerName] = nil
    for i, name in ipairs(self.playerOrder) do
        if name == playerName then
            table.remove(self.playerOrder, i)
            break
        end
    end
    return true
end

-- Seeded shuffle of 1..75 (offset so cards and pool use different streams).
-- Deterministic from the game seed, so a returning host resumes exactly
-- where the draw left off.
function BS:BuildDrawPool()
    local rng = BJ.CardLib.SeededRandom(self.seed + 0x5EED)
    self.drawPool = {}
    for n = 1, self.NUMBERS do self.drawPool[n] = n end
    for i = self.NUMBERS, 2, -1 do
        local j = math.floor(rng() * i) + 1
        self.drawPool[i], self.drawPool[j] = self.drawPool[j], self.drawPool[i]
    end
end

-- Start the draw (host)
function BS:StartDrawing()
    if self.phase ~= self.PHASE.LOBBY then
        return false, "Not in lobby"
    end
    if #self.playerOrder < 2 then
        return false, "Need at least 2 players"
    end

    self:BuildDrawPool()
    self.pot = self.cardPrice * #self.playerOrder
    self.phase = self.PHASE.DRAWING
    BJ:Debug("Bingo draw started. Pot: " .. self.pot .. "g")
    return true
end

-- Host: pull the next number from the pool (nil when exhausted)
function BS:NextDraw()
    if not self.drawPool then return nil end
    if self.drawIndex >= self.NUMBERS then return nil end
    return self.drawPool[self.drawIndex + 1]
end

-- Record a called number (host and clients alike)
function BS:RecordDraw(number)
    if self.phase ~= self.PHASE.DRAWING then return false end
    if self.drawnSet[number] then return false end

    table.insert(self.drawn, number)
    self.drawnSet[number] = true
    self.drawIndex = #self.drawn
    return true
end

-- Column letter for a number ("B" for 1-15 ... "O" for 61-75)
function BS:GetLetterFor(number)
    return self.COLUMN_LETTERS[math.ceil(number / 15)] or "?"
end

-- Does this card have a completed line? (center is always marked)
function BS:CardHasBingo(card)
    local function marked(row, col)
        local n = card[row][col]
        return n == 0 or self.drawnSet[n]
    end

    for i = 1, 5 do
        local rowDone, colDone = true, true
        for j = 1, 5 do
            if not marked(i, j) then rowDone = false end
            if not marked(j, i) then colDone = false end
        end
        if rowDone or colDone then return true end
    end

    local diag1, diag2 = true, true
    for i = 1, 5 do
        if not marked(i, i) then diag1 = false end
        if not marked(i, 6 - i) then diag2 = false end
    end
    return diag1 or diag2
end

-- The first completed line on a card as a list of {row, col} pairs,
-- or nil if the card has no bingo (used to star the winning line)
function BS:GetWinningLine(card)
    local function marked(row, col)
        local n = card[row][col]
        return n == 0 or self.drawnSet[n]
    end

    for i = 1, 5 do
        local rowDone, colDone = true, true
        for j = 1, 5 do
            if not marked(i, j) then rowDone = false end
            if not marked(j, i) then colDone = false end
        end
        if rowDone then
            local line = {}
            for j = 1, 5 do line[j] = { i, j } end
            return line
        end
        if colDone then
            local line = {}
            for j = 1, 5 do line[j] = { j, i } end
            return line
        end
    end

    local diag1, diag2 = true, true
    for i = 1, 5 do
        if not marked(i, i) then diag1 = false end
        if not marked(i, 6 - i) then diag2 = false end
    end
    if diag1 then
        local line = {}
        for i = 1, 5 do line[i] = { i, i } end
        return line
    end
    if diag2 then
        local line = {}
        for i = 1, 5 do line[i] = { i, 6 - i } end
        return line
    end
    return nil
end

-- How close a card is to bingo: returns the fewest undaubed cells on
-- any line, and how many lines sit at that minimum (for sorting)
function BS:GetCardCloseness(card)
    local best, count = 6, 0
    local function consider(miss)
        if miss < best then
            best, count = miss, 1
        elseif miss == best then
            count = count + 1
        end
    end

    for i = 1, 5 do
        local rowMiss, colMiss = 0, 0
        for j = 1, 5 do
            local rn = card[i][j]
            if not (rn == 0 or self.drawnSet[rn]) then rowMiss = rowMiss + 1 end
            local cn = card[j][i]
            if not (cn == 0 or self.drawnSet[cn]) then colMiss = colMiss + 1 end
        end
        consider(rowMiss)
        consider(colMiss)
    end

    local d1, d2 = 0, 0
    for i = 1, 5 do
        local a = card[i][i]
        if not (a == 0 or self.drawnSet[a]) then d1 = d1 + 1 end
        local b = card[i][6 - i]
        if not (b == 0 or self.drawnSet[b]) then d2 = d2 + 1 end
    end
    consider(d1)
    consider(d2)

    return best, count
end

-- All players whose card is complete right now
function BS:FindWinners()
    local winners = {}
    for _, name in ipairs(self.playerOrder) do
        local player = self.players[name]
        if player and self:CardHasBingo(player.card) then
            table.insert(winners, name)
        end
    end
    return winners
end

-- Lock in winners and record results. Host records leaderboard for the
-- group; clients receive leaderboard updates via broadcast.
function BS:FinalizeSettlement(winners, pot, share)
    self.winners = winners
    self.pot = pot or (self.cardPrice * #self.playerOrder)
    self.share = share or math.floor(self.pot / math.max(1, #winners))
    self.phase = self.PHASE.SETTLEMENT

    if BJ.Leaderboard and #winners > 0 then
        local myName = UnitName("player")
        if not self.hostName or self.hostName == myName then
            local isWinner = {}
            for _, w in ipairs(winners) do isWinner[w] = true end
            for _, name in ipairs(self.playerOrder) do
                if isWinner[name] then
                    BJ.Leaderboard:RecordHandResult("bingo", name, self.share - self.cardPrice, "win")
                else
                    BJ.Leaderboard:RecordHandResult("bingo", name, -self.cardPrice, "lose")
                end
            end

            -- Session debt ledger: losers' card money goes to the winners.
            -- Settles under the fun/real status the table OPENED with, not
            -- the recorder's live toggle - a mid-game flip (opener's or a
            -- migrated caller's) only affects the next hosted table; nil
            -- (legacy host) falls back to the recorder's live setting.
            if BJ.DebtLedger then
                local nets = {}
                for _, name in ipairs(self.playerOrder) do
                    nets[name] = isWinner[name] and (self.share - self.cardPrice) or -self.cardPrice
                end
                BJ.DebtLedger:RecordNets("bingo", nets, self.fakePlay)
            end
        end
    end

    self:SaveToHistory()
end

-- Settlement text
function BS:GetSettlementText()
    if #self.winners == 0 then return "No winner" end
    local names = table.concat(self.winners, ", ")
    return string.format("|cff00ff00BINGO!|r |cffffffff%s|r\nwins |cffffd700%dg|r after %d numbers",
        names, self.share, #self.drawn)
end

--[[
    GAME HISTORY
]]
BS.gameHistory = {}
BS.MAX_HISTORY = 5

function BS:SaveToHistory()
    if self.phase ~= self.PHASE.SETTLEMENT then return end
    if #self.winners == 0 then return end

    local game = {
        timestamp = time(),
        host = self.hostName,
        cardPrice = self.cardPrice,
        numPlayers = #self.playerOrder,
        numDraws = #self.drawn,
        winners = { unpack(self.winners) },
        pot = self.pot,
        share = self.share,
    }

    BJ.GameHistory:Add(self.gameHistory, game, self.MAX_HISTORY)
    self:SaveHistoryToDB()
end

function BS:SaveHistoryToDB()
    BJ.GameHistory:Save("bingoHistory", self.gameHistory)
end

function BS:LoadHistoryFromDB()
    local history = BJ.GameHistory:Load("bingoHistory")
    if history then
        self.gameHistory = history
        BJ:Debug("Loaded " .. #self.gameHistory .. " bingo games from history")
    end
end

function BS:GetGameLogText()
    if #self.gameHistory == 0 then
        return "No game history yet."
    end

    local lines = {}
    for gameNum, game in ipairs(self.gameHistory) do
        table.insert(lines, "|cffffd700=== Game " .. gameNum .. " ===|r")
        table.insert(lines, "Host: " .. (game.host or "?") .. " | " .. (game.numPlayers or 0) ..
            " players at " .. (game.cardPrice or 0) .. "g | Pot: " .. (game.pot or 0) .. "g")
        table.insert(lines, "  |cff00ff00" .. table.concat(game.winners or {}, ", ") ..
            "|r won " .. (game.share or 0) .. "g after " .. (game.numDraws or 0) .. " numbers")
        table.insert(lines, "")
    end
    return table.concat(lines, "\n")
end
