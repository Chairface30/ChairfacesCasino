--[[
    Chairface's Casino - DeathRollState.lua
    Death Roll game state management

    Game flow (classic WoW death roll):
    1. Host opens a challenge with a stake X and a first-roll ceiling
       (host's choice; defaults to 10x the stake)
    2. One opponent takes the seat; rolling starts immediately, host first
    3. Players alternate /roll 1-N where N is the previous roll's result
    4. Whoever rolls 1 loses and owes the other player the stake

    Rolls are real server-verified /rolls captured from chat, so no
    seeded RNG or trust in the host is required.
]]

local BJ = ChairfacesCasino
BJ.DeathRollState = {}
local DR = BJ.DeathRollState

-- Game phases
DR.PHASE = {
    IDLE = "idle",
    WAITING = "waiting",       -- Challenge open, waiting for an opponent
    ROLLING = "rolling",       -- Players alternating rolls
    SETTLEMENT = "settlement",
}

-- Reset state
function DR:Reset()
    self.phase = self.PHASE.IDLE
    self.hostName = nil
    self.opponent = nil
    self.stake = 0
    self.currentMax = 0
    self.currentRoller = nil
    self.rolls = {}
    self.winner = nil
    self.loser = nil
end

DR:Reset()

-- Host opens a challenge. startRoll is the first roll's ceiling - the host
-- dictates it (groups have different traditions); defaults to 10x the stake.
function DR:HostGame(hostName, stake, startRoll)
    self:Reset()

    startRoll = tonumber(startRoll)
    if not startRoll or startRoll < 2 then
        startRoll = stake * 10
    end

    self.phase = self.PHASE.WAITING
    self.hostName = hostName
    self.stake = stake
    self.currentMax = startRoll

    BJ:Debug("Death Roll hosted by " .. hostName .. " for " .. stake .. "g, first roll 1-" .. startRoll)
    return true
end

-- Opponent takes the seat; rolling starts immediately (host rolls first)
function DR:SetOpponent(playerName)
    if self.phase ~= self.PHASE.WAITING then
        return false, "Challenge not open"
    end

    if playerName == self.hostName then
        return false, "Host cannot take the opponent seat"
    end

    if self.opponent then
        return false, "Seat already taken"
    end

    self.opponent = playerName
    self.phase = self.PHASE.ROLLING
    self.currentRoller = self.hostName

    BJ:Debug(playerName .. " accepted the Death Roll. " .. self.hostName .. " rolls first.")
    return true
end

-- The other participant relative to a name
function DR:GetOther(playerName)
    if playerName == self.hostName then return self.opponent end
    if playerName == self.opponent then return self.hostName end
    return nil
end

-- Record a validated /roll. Every client applies this identically, either
-- from the chat event or from the host's redundant broadcast - the
-- turn/max validation makes duplicates harmless.
function DR:RecordRoll(playerName, roll, maxRoll)
    if self.phase ~= self.PHASE.ROLLING then
        return false, "Not rolling"
    end

    if playerName ~= self.currentRoller then
        return false, "Not this player's turn"
    end

    if maxRoll ~= self.currentMax then
        return false, "Wrong roll range"
    end

    table.insert(self.rolls, { player = playerName, roll = roll, max = maxRoll })

    if roll == 1 then
        -- Death! Roller loses.
        self.loser = playerName
        self.winner = self:GetOther(playerName)
        self.currentRoller = nil
        self.phase = self.PHASE.SETTLEMENT
        self:FinalizeSettlement()
        return true, "settled"
    end

    self.currentMax = roll
    self.currentRoller = self:GetOther(playerName)
    return true
end

-- Record results to leaderboard/history (host records for the group;
-- clients receive leaderboard updates via broadcast)
function DR:FinalizeSettlement()
    if BJ.Leaderboard and self.winner and self.loser then
        local myName = BJ:MyName()
        if not self.hostName or self.hostName == myName then
            BJ.Leaderboard:RecordHandResult("deathroll", self.winner, self.stake, "win")
            BJ.Leaderboard:RecordHandResult("deathroll", self.loser, -self.stake, "lose")

            -- Session debt ledger: loser owes winner the stake.
            -- Fun/real status fixed at table open: a mid-game toggle flip
            -- only affects the next hosted table
            if BJ.DebtLedger and self.stake and self.stake > 0 then
                BJ.DebtLedger:RecordDebt("deathroll", self.loser, self.winner, self.stake, self.fakePlay)
            end
        end
    end

    self:SaveToHistory()
end

-- Settlement text
function DR:GetSettlementText()
    if not self.winner or not self.loser then
        return "No result"
    end
    return string.format("|cffff4444%s|r rolled a 1!\n|cffffffff%s|r owes |cffffffff%s|r |cffffd700%dg|r",
        self.loser, self.loser, self.winner, self.stake)
end

--[[
    GAME HISTORY
]]
DR.gameHistory = {}
DR.MAX_HISTORY = 5

function DR:SaveToHistory()
    if self.phase ~= self.PHASE.SETTLEMENT then return end
    if not self.winner or not self.loser then return end

    local game = {
        timestamp = time(),
        host = self.hostName,
        opponent = self.opponent,
        stake = self.stake,
        numRolls = #self.rolls,
        winner = self.winner,
        loser = self.loser,
    }

    BJ.GameHistory:Add(self.gameHistory, game, self.MAX_HISTORY)
    self:SaveHistoryToDB()
end

function DR:SaveHistoryToDB()
    BJ.GameHistory:Save("deathrollHistory", self.gameHistory)
end

function DR:LoadHistoryFromDB()
    local history = BJ.GameHistory:Load("deathrollHistory")
    if history then
        self.gameHistory = history
        BJ:Debug("Loaded " .. #self.gameHistory .. " death roll games from history")
    end
end

function DR:GetGameLogText()
    if #self.gameHistory == 0 then
        return "No game history yet."
    end

    local lines = {}
    for gameNum, game in ipairs(self.gameHistory) do
        table.insert(lines, "|cffffd700=== Game " .. gameNum .. " ===|r")
        table.insert(lines, (game.host or "?") .. " vs " .. (game.opponent or "?") ..
            " | Stake: " .. (game.stake or 0) .. "g | " .. (game.numRolls or 0) .. " rolls")
        table.insert(lines, "  |cffff4444" .. (game.loser or "?") .. "|r owes |cff00ff00" ..
            (game.winner or "?") .. "|r " .. (game.stake or 0) .. "g")
        table.insert(lines, "")
    end
    return table.concat(lines, "\n")
end
