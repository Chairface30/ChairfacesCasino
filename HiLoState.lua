--[[
    Chairface's Casino - HiLoState.lua
    High-Lo game state management
    
    Game flow:
    1. Host sets max roll value and optional timer
    2. Players join
    3. Host clicks Start (or timer expires)
    4. All players /roll X
    5. When all rolls are in (or 2 min timeout), settlement
    6. Highest roller wins difference from lowest roller
]]

local BJ = ChairfacesCasino
BJ.HiLoState = {}
local HL = BJ.HiLoState

-- Game phases
HL.PHASE = {
    IDLE = "idle",
    LOBBY = "lobby",       -- Waiting for players to join
    ROLLING = "rolling",   -- Players are rolling
    TIEBREAKER = "tiebreaker", -- Resolving ties
    SETTLEMENT = "settlement",
}

-- State
HL.phase = HL.PHASE.IDLE
HL.hostName = nil
HL.maxRoll = 100           -- Default max roll value
HL.joinTimer = 0           -- Join timer (0 = manual start)
HL.players = {}            -- { name = { rolled = false, roll = nil } }
HL.playerOrder = {}        -- Order players joined
HL.rollTimeLimit = 120     -- 2 minutes to roll
HL.rollStartTime = nil     -- When rolling phase started

-- Settlement data
HL.highPlayer = nil
HL.highRoll = nil
HL.lowPlayer = nil
HL.lowRoll = nil
HL.winAmount = nil

-- Reset state
function HL:Reset()
    self.phase = self.PHASE.IDLE
    self.hostName = nil
    self.players = {}
    self.playerOrder = {}
    self.rollStartTime = nil
    self.highPlayer = nil
    self.highRoll = nil
    self.lowPlayer = nil
    self.lowRoll = nil
    self.winAmount = nil
end

-- Host starts a new game
function HL:HostGame(hostName, maxRoll, joinTimer)
    self:Reset()
    
    self.phase = self.PHASE.LOBBY
    self.hostName = hostName
    self.maxRoll = maxRoll or 100
    self.joinTimer = joinTimer or 0
    self.lobbyStartTime = time()  -- Track when lobby started for timer sync
    
    -- Host auto-joins
    self:AddPlayer(hostName)
    
    BJ:Debug("High-Lo game hosted by " .. hostName .. " with max roll " .. self.maxRoll)
    return true
end

-- Add a player to the game
function HL:AddPlayer(playerName)
    if self.phase ~= self.PHASE.LOBBY then
        return false, "Cannot join - game not in lobby phase"
    end
    
    if self.players[playerName] then
        return false, "Already joined"
    end
    
    -- Enforce 40 player limit
    if #self.playerOrder >= 40 then
        return false, "Game is full (40 players max)"
    end
    
    self.players[playerName] = {
        rolled = false,
        roll = nil,
    }
    table.insert(self.playerOrder, playerName)
    
    BJ:Debug(playerName .. " joined High-Lo")
    return true
end

-- Remove a player
function HL:RemovePlayer(playerName)
    if self.phase ~= self.PHASE.LOBBY then
        return false, "Cannot leave after game started"
    end
    
    if not self.players[playerName] then
        return false, "Not in game"
    end
    
    -- Don't allow host to leave
    if playerName == self.hostName then
        return false, "Host cannot leave"
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

-- Start the rolling phase
function HL:StartRolling()
    if self.phase ~= self.PHASE.LOBBY then
        return false, "Cannot start - not in lobby"
    end
    
    if #self.playerOrder < 2 then
        return false, "Need at least 2 players"
    end
    
    self.phase = self.PHASE.ROLLING
    self.rollStartTime = time()
    
    BJ:Debug("High-Lo rolling phase started")
    return true
end

-- Record a player's roll
function HL:RecordRoll(playerName, rollValue)
    if self.phase ~= self.PHASE.ROLLING then
        return false, "Not in rolling phase"
    end
    
    local player = self.players[playerName]
    if not player then
        return false, "Player not in game"
    end
    
    if player.rolled then
        return false, "Already rolled"
    end
    
    player.rolled = true
    player.roll = rollValue
    
    BJ:Debug(playerName .. " rolled " .. rollValue)
    
    -- Check if all players have rolled
    if self:AllPlayersRolled() then
        self:CalculateSettlement()
    end
    
    return true
end

-- Check if all players have rolled
function HL:AllPlayersRolled()
    for _, name in ipairs(self.playerOrder) do
        local player = self.players[name]
        if not player.rolled then
            return false
        end
    end
    return true
end

-- Get players sorted by roll (highest first)
function HL:GetSortedPlayers()
    local sorted = {}
    for _, name in ipairs(self.playerOrder) do
        local player = self.players[name]
        table.insert(sorted, {
            name = name,
            roll = player.roll,
            rolled = player.rolled,
        })
    end
    
    -- Sort by roll (highest first), unrolled at bottom
    table.sort(sorted, function(a, b)
        if a.rolled ~= b.rolled then
            return a.rolled  -- Rolled players first
        end
        if not a.rolled then
            return false  -- Both unrolled, maintain order
        end
        return a.roll > b.roll  -- Both rolled, highest first
    end)
    
    return sorted
end

-- Check for timeout on rolling phase
function HL:CheckTimeout()
    if self.phase ~= self.PHASE.ROLLING then
        return false
    end
    
    if not self.rollStartTime then
        return false
    end
    
    local elapsed = time() - self.rollStartTime
    if elapsed >= self.rollTimeLimit then
        -- Time's up - calculate with whoever rolled
        self:CalculateSettlement()
        return true
    end
    
    return false
end

-- Get remaining time in rolling phase
function HL:GetRemainingTime()
    if self.phase ~= self.PHASE.ROLLING or not self.rollStartTime then
        return 0
    end
    
    local elapsed = time() - self.rollStartTime
    return math.max(0, self.rollTimeLimit - elapsed)
end

-- Calculate settlement
function HL:CalculateSettlement()
    -- Find highest and lowest rolls among players who rolled
    local highRoll = -1
    local lowRoll = 999999999
    local highPlayers = {}  -- Players tied for high
    local lowPlayers = {}   -- Players tied for low
    local rolledCount = 0
    
    for _, name in ipairs(self.playerOrder) do
        local player = self.players[name]
        if player.rolled and player.roll then
            rolledCount = rolledCount + 1
            
            -- Track high rollers
            if player.roll > highRoll then
                highRoll = player.roll
                highPlayers = { name }
            elseif player.roll == highRoll then
                table.insert(highPlayers, name)
            end
            
            -- Track low rollers
            if player.roll < lowRoll then
                lowRoll = player.roll
                lowPlayers = { name }
            elseif player.roll == lowRoll then
                table.insert(lowPlayers, name)
            end
        end
    end
    
    -- Need at least 2 players who rolled
    if rolledCount < 2 then
        self.phase = self.PHASE.SETTLEMENT
        self.highPlayer = nil
        self.lowPlayer = nil
        self.winAmount = 0
        BJ:Debug("Not enough players rolled for settlement")
        return
    end
    
    -- Special case: 2 players with same roll - they need to reroll completely
    -- (a tiebreaker would be pointless since they'd just trade even)
    if rolledCount == 2 and highRoll == lowRoll then
        -- Reset rolls and go back to rolling phase
        for _, name in ipairs(self.playerOrder) do
            local player = self.players[name]
            if player then
                player.rolled = false
                player.roll = nil
            end
        end
        self.phase = self.PHASE.ROLLING
        self.rollStartTime = time()  -- Reset timer
        BJ:Print("|cffffd700TIE!|r Both players rolled " .. highRoll .. ". Everyone reroll /roll " .. self.maxRoll .. "!")
        return
    end
    
    -- Check for ties that need tiebreaker (3+ players)
    if #highPlayers > 1 or #lowPlayers > 1 then
        -- Need tiebreaker phase
        self.phase = self.PHASE.TIEBREAKER
        self.tiebreakerType = nil
        self.tiebreakerPlayers = {}
        self.tiebreakerRolls = {}
        
        if #highPlayers > 1 then
            self.tiebreakerType = "high"
            self.tiebreakerPlayers = highPlayers
            self.tiebreakerHighRoll = highRoll
            self.tiebreakerLowRoll = lowRoll
            self.tiebreakerLowPlayers = lowPlayers
            BJ:Print("|cffffd700TIE for HIGH!|r " .. table.concat(highPlayers, ", ") .. " must /roll 100 for tiebreaker!")
        else
            self.tiebreakerType = "low"
            self.tiebreakerPlayers = lowPlayers
            self.tiebreakerHighRoll = highRoll
            self.tiebreakerLowRoll = lowRoll
            self.tiebreakerHighPlayers = highPlayers
            BJ:Print("|cffffd700TIE for LOW!|r " .. table.concat(lowPlayers, ", ") .. " must /roll 100 for tiebreaker!")
        end
        
        -- Initialize tiebreaker rolls
        for _, name in ipairs(self.tiebreakerPlayers) do
            self.tiebreakerRolls[name] = nil
        end
        
        return
    end
    
    -- No ties - finalize settlement
    self:FinalizeSettlement(highPlayers[1], highRoll, lowPlayers[1], lowRoll)
end

-- Record a tiebreaker roll
function HL:RecordTiebreakerRoll(playerName, rollValue)
    if self.phase ~= self.PHASE.TIEBREAKER then
        return false, "Not in tiebreaker phase"
    end
    
    -- Check if this player is in the tiebreaker
    local inTiebreaker = false
    for _, name in ipairs(self.tiebreakerPlayers) do
        if name == playerName then
            inTiebreaker = true
            break
        end
    end
    
    if not inTiebreaker then
        return false, "Not in tiebreaker"
    end
    
    if self.tiebreakerRolls[playerName] then
        return false, "Already rolled tiebreaker"
    end
    
    self.tiebreakerRolls[playerName] = rollValue
    BJ:Debug(playerName .. " tiebreaker roll: " .. rollValue)
    
    -- Check if all tiebreaker rolls are in
    local allRolled = true
    for _, name in ipairs(self.tiebreakerPlayers) do
        if not self.tiebreakerRolls[name] then
            allRolled = false
            break
        end
    end
    
    if allRolled then
        self:ResolveTiebreaker()
    end
    
    return true
end

-- Resolve tiebreaker
function HL:ResolveTiebreaker()
    BJ:Debug("ResolveTiebreaker called. Type: " .. tostring(self.tiebreakerType))
    local winnerName = nil
    local winnerRoll = -1
    
    if self.tiebreakerType == "high" then
        -- Highest tiebreaker roll wins
        for name, roll in pairs(self.tiebreakerRolls) do
            BJ:Debug("  Tiebreaker roll: " .. name .. " = " .. tostring(roll))
            if roll > winnerRoll then
                winnerRoll = roll
                winnerName = name
            end
        end
        
        -- Check for another tie in tiebreaker
        local tiedAgain = {}
        for name, roll in pairs(self.tiebreakerRolls) do
            if roll == winnerRoll then
                table.insert(tiedAgain, name)
            end
        end
        
        BJ:Debug("  Winner: " .. tostring(winnerName) .. " with " .. winnerRoll .. ", tied count: " .. #tiedAgain)
        
        if #tiedAgain > 1 then
            -- Still tied - roll again
            self.tiebreakerPlayers = tiedAgain
            self.tiebreakerRolls = {}
            for _, name in ipairs(tiedAgain) do
                self.tiebreakerRolls[name] = nil
            end
            BJ:Print("|cffffd700Still tied!|r " .. table.concat(tiedAgain, ", ") .. " roll again!")
            return
        end
        
        -- Winner determined - get low player
        BJ:Debug("  tiebreakerLowPlayers: " .. (self.tiebreakerLowPlayers and table.concat(self.tiebreakerLowPlayers, ",") or "nil"))
        local lowPlayer = self.tiebreakerLowPlayers and self.tiebreakerLowPlayers[1]
        if self.tiebreakerLowPlayers and #self.tiebreakerLowPlayers > 1 then
            -- Need to resolve low tie too
            self.tiebreakerType = "low"
            self.tiebreakerPlayers = self.tiebreakerLowPlayers
            self.tiebreakerRolls = {}
            self.resolvedHighPlayer = winnerName
            for _, name in ipairs(self.tiebreakerLowPlayers) do
                self.tiebreakerRolls[name] = nil
            end
            BJ:Print("|cffffd700Now resolving LOW tie!|r " .. table.concat(self.tiebreakerLowPlayers, ", ") .. " must /roll 100!")
            return
        end
        
        BJ:Debug("  Finalizing: high=" .. tostring(winnerName) .. ", low=" .. tostring(lowPlayer))
        self:FinalizeSettlement(winnerName, self.tiebreakerHighRoll, lowPlayer, self.tiebreakerLowRoll)
        
    else -- low tiebreaker
        -- Lowest tiebreaker roll loses
        local loserName = nil
        local loserRoll = 999999999
        for name, roll in pairs(self.tiebreakerRolls) do
            if roll < loserRoll then
                loserRoll = roll
                loserName = name
            end
        end
        
        -- Check for another tie in tiebreaker
        local tiedAgain = {}
        for name, roll in pairs(self.tiebreakerRolls) do
            if roll == loserRoll then
                table.insert(tiedAgain, name)
            end
        end
        
        if #tiedAgain > 1 then
            -- Still tied - roll again
            self.tiebreakerPlayers = tiedAgain
            self.tiebreakerRolls = {}
            for _, name in ipairs(tiedAgain) do
                self.tiebreakerRolls[name] = nil
            end
            BJ:Print("|cffffd700Still tied!|r " .. table.concat(tiedAgain, ", ") .. " roll again!")
            return
        end
        
        -- Get high player (may have been resolved earlier)
        local highPlayer = self.resolvedHighPlayer or self.tiebreakerHighPlayers[1]
        
        self:FinalizeSettlement(highPlayer, self.tiebreakerHighRoll, loserName, self.tiebreakerLowRoll)
    end
end

-- Finalize settlement with determined winner and loser
function HL:FinalizeSettlement(highName, highRoll, lowName, lowRoll)
    self.phase = self.PHASE.SETTLEMENT
    
    self.highPlayer = highName
    self.highRoll = highRoll
    self.lowPlayer = lowName
    self.lowRoll = lowRoll
    self.winAmount = highRoll - lowRoll
    
    BJ:Debug("Settlement: " .. highName .. " (" .. highRoll .. ") wins " .. 
        self.winAmount .. "g from " .. lowName .. " (" .. lowRoll .. ")")
    
    -- Save to history
    self:SaveToHistory()
end

-- Get settlement text
function HL:GetSettlementText()
    if not self.highPlayer or not self.lowPlayer then
        return "No valid settlement (not enough rolls)"
    end
    
    return string.format("%s |cffffd700(%d)|r |cff00ff00wins|r\n%s |cffffd700(%d)|r |cffff4444loses|r",
        self.highPlayer, self.highRoll,
        self.lowPlayer, self.lowRoll)
end

-- Get detailed settlement breakdown
function HL:GetSettlementBreakdown()
    if not self.highPlayer or not self.lowPlayer then
        return "No settlement"
    end
    
    return string.format("|cffffd700%d|r - |cffffd700%d|r = |cff00ff00%dg|r\n|cff00ff88>>>|r |cffffffff%s|r pays |cffffffff%s|r |cff00ff00%dg|r |cff00ff88<<<|r",
        self.highRoll, self.lowRoll, self.winAmount,
        self.lowPlayer, self.highPlayer, self.winAmount)
end

--[[
    GAME HISTORY
]]
HL.gameHistory = {}
HL.MAX_HISTORY = 5

-- Save current game to history
function HL:SaveToHistory()
    if self.phase ~= self.PHASE.SETTLEMENT then return end
    if not self.highPlayer or not self.lowPlayer then return end
    
    local game = {
        timestamp = time(),
        host = self.hostName,
        maxRoll = self.maxRoll,
        players = {},
        winner = self.highPlayer,
        winnerRoll = self.highRoll,
        loser = self.lowPlayer,
        loserRoll = self.lowRoll,
        winAmount = self.winAmount,
    }
    
    -- Copy all player rolls
    for _, name in ipairs(self.playerOrder) do
        local player = self.players[name]
        if player and player.roll then
            table.insert(game.players, {
                name = name,
                roll = player.roll,
            })
        end
    end
    
    -- Sort by roll descending
    table.sort(game.players, function(a, b) return a.roll > b.roll end)
    
    -- Add to history
    table.insert(self.gameHistory, 1, game)
    while #self.gameHistory > self.MAX_HISTORY do
        table.remove(self.gameHistory)
    end
    
    -- Save to persistent storage
    self:SaveHistoryToDB()
end

-- Save game history to SavedVariables (encoded)
function HL:SaveHistoryToDB()
    if not ChairfacesCasinoSaved then
        ChairfacesCasinoSaved = {}
    end
    
    if BJ.Compression and BJ.Compression.EncodeForSave then
        ChairfacesCasinoSaved.hiloHistory = BJ.Compression:EncodeForSave(self.gameHistory)
    end
end

-- Load game history from SavedVariables
function HL:LoadHistoryFromDB()
    if not ChairfacesCasinoSaved or not ChairfacesCasinoSaved.hiloHistory then
        return
    end
    
    if BJ.Compression and BJ.Compression.DecodeFromSave then
        local decoded = BJ.Compression:DecodeFromSave(ChairfacesCasinoSaved.hiloHistory)
        if decoded and type(decoded) == "table" then
            self.gameHistory = decoded
            BJ:Debug("Loaded " .. #self.gameHistory .. " high-lo games from history")
        end
    end
end

-- Get formatted game log text
function HL:GetGameLogText()
    if #self.gameHistory == 0 then
        return "No game history yet."
    end
    
    local lines = {}
    
    for gameNum, game in ipairs(self.gameHistory) do
        table.insert(lines, "|cffffd700=== Game " .. gameNum .. " ===|r")
        table.insert(lines, "Host: " .. (game.host or "Unknown") .. " | Max Roll: " .. (game.maxRoll or 100))
        table.insert(lines, "")
        
        -- All rolls
        table.insert(lines, "|cff88ffffRolls:|r")
        for i, player in ipairs(game.players) do
            local color = "ffffff"
            if player.name == game.winner then
                color = "00ff00"
            elseif player.name == game.loser then
                color = "ff4444"
            end
            table.insert(lines, "  |cff" .. color .. player.name .. ": " .. player.roll .. "|r")
        end
        
        -- Result
        table.insert(lines, "")
        table.insert(lines, "|cff88ff88Result:|r")
        table.insert(lines, "  |cff00ff00" .. game.winner .. "|r rolled |cffffd700" .. game.winnerRoll .. "|r (HIGH)")
        table.insert(lines, "  |cffff4444" .. game.loser .. "|r rolled |cffffd700" .. game.loserRoll .. "|r (LOW)")
        table.insert(lines, "")
        table.insert(lines, "|cffffd700Settlement:|r")
        table.insert(lines, "  " .. game.loser .. " owes " .. game.winner .. " |cff00ff00" .. game.winAmount .. "g|r")
        table.insert(lines, "")
    end
    
    return table.concat(lines, "\n")
end
