--[[
    Chairface's Casino - CrapsState.lua
    Craps game state management - Vegas Perfect Rules
    
    Game Flow:
    1. Host opens table, becomes first shooter
    2. Players join and place bets during betting phase
    3. Shooter rolls (come-out or point phase)
    4. Bets are settled based on roll
    5. Shooter changes on seven-out
    6. Host plays the bank (house edge on bets)
]]

local BJ = ChairfacesCasino
BJ.CrapsState = {}
local CS = BJ.CrapsState

-- Game phases
CS.PHASE = {
    IDLE = "idle",
    BETTING = "betting",       -- Players placing bets, waiting to start
    COME_OUT = "come_out",     -- Come-out roll phase
    POINT = "point",           -- Point established, shooting for it
    ROLLING = "rolling",       -- Waiting for shooter to roll
    SETTLEMENT = "settlement", -- Showing results
}

-- Initialize state
CS.phase = CS.PHASE.IDLE
CS.hostName = nil
CS.shooterName = nil
CS.shooterIndex = 1
CS.point = nil
CS.lastRoll = nil              -- {die1, die2, total, isHard}
CS.rollHistory = {}            -- Recent rolls for display

CS.players = {}                -- {name = {bets = {}, balance = 0, startBalance = 0, lockedIn = false}}
CS.shooterOrder = {}           -- Player rotation order

-- Honor Ledger System
CS.tableCap = 100000           -- Max total payout the bank can sustain
CS.currentRisk = 0             -- Current potential payout exposure
CS.pendingJoins = {}           -- {playerName = {buyIn = amount, timestamp = time}}

-- Betting limits (set by host)
CS.minBet = 100
CS.maxBet = 10000
CS.maxOdds = 3                 -- 3x-4x-5x odds multiplier (varies by point)

-- Timer settings
CS.bettingTimer = 30           -- Seconds for betting phase
CS.rollTimer = 60              -- Max time for shooter to roll
CS.bettingStartTime = nil
CS.rollStartTime = nil

-- Payout tables (multipliers including original bet back)
-- These represent what you GET BACK, so 2 means 1:1 payout + original
CS.PAYOUTS = {
    -- Line bets (1:1)
    passLine = 2,
    dontPass = 2,
    come = 2,
    dontCome = 2,
    
    -- Odds by point (true odds)
    passLineOdds = {
        [4] = 3,     -- 2:1
        [5] = 2.5,   -- 3:2
        [6] = 2.2,   -- 6:5
        [8] = 2.2,   -- 6:5
        [9] = 2.5,   -- 3:2
        [10] = 3,    -- 2:1
    },
    dontPassOdds = {
        [4] = 1.5,   -- 1:2
        [5] = 1.67,  -- 2:3
        [6] = 1.83,  -- 5:6
        [8] = 1.83,  -- 5:6
        [9] = 1.67,  -- 2:3
        [10] = 1.5,  -- 1:2
    },
    
    -- Place bets
    place = {
        [4] = 2.8,   -- 9:5
        [5] = 2.4,   -- 7:5
        [6] = 2.17,  -- 7:6
        [8] = 2.17,  -- 7:6
        [9] = 2.4,   -- 7:5
        [10] = 2.8,  -- 9:5
    },
    
    -- Field bet
    field = {
        [2] = 3,     -- 2:1
        [3] = 2,     -- 1:1
        [4] = 2,     -- 1:1
        [9] = 2,     -- 1:1
        [10] = 2,    -- 1:1
        [11] = 2,    -- 1:1
        [12] = 3,    -- 2:1
    },
    
    -- Proposition bets
    any7 = 5,         -- 4:1
    anyCraps = 8,     -- 7:1
    craps2 = 31,      -- 30:1
    craps3 = 16,      -- 15:1
    craps12 = 31,     -- 30:1
    yo11 = 16,        -- 15:1
    
    -- Hardways
    hard4 = 9,        -- 8:1 (pays 8 for 1, so 9 total return)
    hard6 = 11,       -- 10:1 (pays 10 for 1, so 11 total return)
    hard8 = 11,       -- 10:1 (pays 10 for 1, so 11 total return)
    hard10 = 9,       -- 8:1 (pays 8 for 1, so 9 total return)
    
    -- Big 6/8
    big6 = 2,         -- 1:1
    big8 = 2,         -- 1:1
}

-- Create empty bet structure for a player
function CS:CreateEmptyBets()
    return {
        -- Line bets
        passLine = 0,
        passLineOdds = 0,
        dontPass = 0,
        dontPassOdds = 0,
        
        -- Come bets (indexed by their "point" once established)
        come = 0,              -- Flat come bet (before it moves)
        comePoints = {},       -- {[point] = {base = 0, odds = 0}}
        dontCome = 0,          -- Flat don't come
        dontComePoints = {},   -- {[point] = {base = 0, odds = 0}}
        
        -- Place bets
        place = {[4] = 0, [5] = 0, [6] = 0, [8] = 0, [9] = 0, [10] = 0},
        
        -- Field (one-roll)
        field = 0,
        
        -- Proposition bets (one-roll)
        any7 = 0,
        anyCraps = 0,
        craps2 = 0,
        craps3 = 0,
        craps12 = 0,
        yo11 = 0,
        
        -- Hardways (stay until win or lose)
        hard4 = 0,
        hard6 = 0,
        hard8 = 0,
        hard10 = 0,
        
        -- Big 6/8
        big6 = 0,
        big8 = 0,
    }
end

-- Reset state
function CS:Reset()
    self.phase = self.PHASE.IDLE
    self.hostName = nil
    self.shooterName = nil
    self.shooterIndex = 1
    self.shooterHasRolled = false  -- Track if current shooter has rolled dice
    self.point = nil
    self.lastRoll = nil
    self.rollHistory = {}
    self.players = {}
    self.shooterOrder = {}
    self.bettingStartTime = nil
    self.rollStartTime = nil
    -- Honor Ledger reset
    self.tableCap = 100000
    self.currentRisk = 0
    self.pendingJoins = {}
end

-- Host opens a craps table
function CS:HostTable(hostName, settings)
    self:Reset()
    
    self.phase = self.PHASE.BETTING
    self.hostName = hostName
    
    -- Apply settings
    if settings then
        self.minBet = settings.minBet or 100
        self.maxBet = settings.maxBet or 10000
        self.maxOdds = settings.maxOdds or 3
        self.bettingTimer = settings.bettingTimer or 30
        self.tableCap = settings.tableCap or 100000
    end
    
    -- Host joins as the bank (not a player/shooter)
    self:AddPlayer(hostName, self.tableCap, true)
    self.shooterName = nil  -- No shooter until first player joins
    self.shooterIndex = 0
    
    BJ:Debug("Craps table hosted by " .. hostName .. " with cap " .. self.tableCap)
    return true
end

-- Add player to the game (with buy-in balance)
function CS:AddPlayer(playerName, buyIn, isHost)
    if self.phase == self.PHASE.IDLE then
        return false, "No active table"
    end
    
    if self.players[playerName] then
        return false, "Already at table"
    end
    
    -- Limit to 8 players (standard craps table)
    if #self.shooterOrder >= 8 then
        return false, "Table is full (8 players max)"
    end
    
    -- Validate buy-in
    local balance = tonumber(buyIn) or 0
    if not isHost and balance <= 0 then
        return false, "Invalid buy-in amount"
    end
    
    self.players[playerName] = {
        bets = self:CreateEmptyBets(),
        balance = balance,           -- Current chip balance
        startBalance = balance,      -- Starting balance for receipt
        sessionBalance = 0,          -- Track win/loss this session (legacy)
        lockedIn = false,            -- Ready check status
        isHost = isHost or false,
    }
    
    -- Add to shooter rotation (host is NOT a shooter - they're the bank)
    if not isHost then
        table.insert(self.shooterOrder, playerName)
        
        -- First non-host player automatically becomes the shooter
        if not self.shooterName then
            self.shooterName = playerName
            self.shooterIndex = 1
        end
        
        -- Log balance
        self:LogBalance(playerName, balance, "Joined")
    end
    
    BJ:Debug(playerName .. " joined craps table with " .. balance .. " chips")
    return true
end

-- Request to join (creates pending join request)
function CS:RequestJoin(playerName, buyIn)
    if self.phase == self.PHASE.IDLE then
        return false, "No active table"
    end
    
    if self.players[playerName] then
        return false, "Already at table"
    end
    
    if self.pendingJoins[playerName] then
        return false, "Join request already pending"
    end
    
    local amount = tonumber(buyIn)
    if not amount or amount < 1 or amount > 100000 then
        return false, "Buy-in must be between 1 and 100,000"
    end
    
    self.pendingJoins[playerName] = {
        buyIn = amount,
        timestamp = time(),
    }
    
    BJ:Debug(playerName .. " requests to join with " .. amount .. " chips")
    return true
end

-- Approve a pending join request (host only)
function CS:ApproveJoin(playerName)
    local request = self.pendingJoins[playerName]
    if not request then
        return false, "No pending request from " .. playerName
    end
    
    local success, err = self:AddPlayer(playerName, request.buyIn, false)
    if success then
        self.pendingJoins[playerName] = nil
    end
    return success, err
end

-- Deny a pending join request (host only)
function CS:DenyJoin(playerName)
    if not self.pendingJoins[playerName] then
        return false, "No pending request from " .. playerName
    end
    
    self.pendingJoins[playerName] = nil
    BJ:Debug("Join request from " .. playerName .. " denied")
    return true
end

-- Get pending join requests
function CS:GetPendingJoins()
    local requests = {}
    for name, data in pairs(self.pendingJoins) do
        table.insert(requests, {
            name = name,
            buyIn = data.buyIn,
            timestamp = data.timestamp,
        })
    end
    -- Sort by timestamp
    table.sort(requests, function(a, b) return a.timestamp < b.timestamp end)
    return requests
end

-- Get player balance
function CS:GetPlayerBalance(playerName)
    local player = self.players[playerName]
    if not player then return 0 end
    return player.balance
end

-- Deduct from player balance (for placing bets)
function CS:DeductBalance(playerName, amount)
    local player = self.players[playerName]
    if not player then return false, "Not at table" end
    if player.balance < amount then return false, "Insufficient balance" end
    
    player.balance = player.balance - amount
    return true
end

-- Add to player balance (for winnings)
function CS:AddBalance(playerName, amount)
    local player = self.players[playerName]
    if not player then return false end
    
    player.balance = player.balance + amount
    return true
end

-- Check if player can afford a bet
function CS:CanAffordBet(playerName, amount)
    local player = self.players[playerName]
    if not player then return false end
    return player.balance >= amount
end

-- Remove player from the game
function CS:RemovePlayer(playerName)
    local player = self.players[playerName]
    if not player then
        return false, "Not at table"
    end
    
    -- Don't allow host to leave if others are playing
    if playerName == self.hostName and #self.shooterOrder > 1 then
        return false, "Host cannot leave while players are at the table"
    end
    
    -- Log balance before removing
    if not player.isHost then
        self:LogBalance(playerName, player.balance, "Cashed out")
    end
    
    -- If they're the shooter, pass the dice
    if playerName == self.shooterName then
        self:PassDice()
    end
    
    -- Remove from shooter order
    for i, name in ipairs(self.shooterOrder) do
        if name == playerName then
            table.remove(self.shooterOrder, i)
            break
        end
    end
    
    -- Forfeit all bets
    self.players[playerName] = nil
    
    BJ:Debug(playerName .. " left craps table")
    return true
end

-- Get next shooter in rotation
function CS:GetNextShooter()
    if #self.shooterOrder == 0 then return nil end
    
    self.shooterIndex = self.shooterIndex + 1
    if self.shooterIndex > #self.shooterOrder then
        self.shooterIndex = 1
    end
    
    return self.shooterOrder[self.shooterIndex]
end

-- Pass the dice to next shooter
function CS:PassDice()
    local nextShooter = self:GetNextShooter()
    if nextShooter then
        self.shooterName = nextShooter
        BJ:Debug("Dice passed to " .. nextShooter)
    end
    return nextShooter
end

-- Place a bet
function CS:PlaceBet(playerName, betType, amount, point)
    local player = self.players[playerName]
    if not player then
        return false, "Not at table"
    end
    
    -- Host (banker) cannot place bets
    if player.isHost then
        return false, "Banker cannot place bets"
    end
    
    if amount < self.minBet then
        return false, "Minimum bet is " .. self.minBet
    end
    
    if amount > self.maxBet then
        return false, "Maximum bet is " .. self.maxBet
    end
    
    -- Check player balance
    if not self:CanAffordBet(playerName, amount) then
        return false, "Insufficient balance (" .. player.balance .. "g)"
    end
    
    -- Check table cap (risk)
    local potentialPayout = self:CalculatePotentialPayout(betType, amount, point or self.point)
    if self:WouldExceedCap(betType, amount, point or self.point) then
        return false, "Would exceed table bank limit"
    end
    
    local bets = player.bets
    
    -- Validate bet based on game phase
    if not self:CanPlaceBet(betType, point) then
        return false, "Cannot place this bet now"
    end
    
    -- Handle different bet types
    if betType == "passLine" then
        bets.passLine = bets.passLine + amount
    elseif betType == "passLineOdds" then
        -- Must have pass line bet first
        if bets.passLine == 0 then
            return false, "Must have Pass Line bet first"
        end
        -- Max odds based on point
        local maxOdds = self:GetMaxOdds(self.point) * bets.passLine
        if bets.passLineOdds + amount > maxOdds then
            return false, "Max odds exceeded"
        end
        bets.passLineOdds = bets.passLineOdds + amount
    elseif betType == "dontPass" then
        bets.dontPass = bets.dontPass + amount
    elseif betType == "dontPassOdds" then
        if bets.dontPass == 0 then
            return false, "Must have Don't Pass bet first"
        end
        -- Max odds for don't pass (usually allows more since payout is lower)
        local maxOdds = self:GetMaxOdds(self.point) * bets.dontPass * 2
        if bets.dontPassOdds + amount > maxOdds then
            return false, "Max odds exceeded"
        end
        bets.dontPassOdds = bets.dontPassOdds + amount
    elseif betType == "come" then
        bets.come = bets.come + amount
    elseif betType == "comeOdds" and point then
        -- Must have come bet on that point
        local comePoint = bets.comePoints[point]
        if not comePoint or comePoint.base == 0 then
            return false, "Must have Come bet on " .. point .. " first"
        end
        local maxOdds = self:GetMaxOdds(point) * comePoint.base
        if comePoint.odds + amount > maxOdds then
            return false, "Max odds exceeded"
        end
        comePoint.odds = comePoint.odds + amount
    elseif betType == "dontCome" then
        bets.dontCome = bets.dontCome + amount
    elseif betType == "place" and point then
        bets.place[point] = bets.place[point] + amount
    elseif betType == "field" then
        bets.field = bets.field + amount
    elseif betType == "any7" then
        bets.any7 = bets.any7 + amount
    elseif betType == "anyCraps" then
        bets.anyCraps = bets.anyCraps + amount
    elseif betType == "craps2" then
        bets.craps2 = bets.craps2 + amount
    elseif betType == "craps3" then
        bets.craps3 = bets.craps3 + amount
    elseif betType == "craps12" then
        bets.craps12 = bets.craps12 + amount
    elseif betType == "yo11" then
        bets.yo11 = bets.yo11 + amount
    elseif betType == "hard4" then
        bets.hard4 = bets.hard4 + amount
    elseif betType == "hard6" then
        bets.hard6 = bets.hard6 + amount
    elseif betType == "hard8" then
        bets.hard8 = bets.hard8 + amount
    elseif betType == "hard10" then
        bets.hard10 = bets.hard10 + amount
    elseif betType == "big6" then
        bets.big6 = bets.big6 + amount
    elseif betType == "big8" then
        bets.big8 = bets.big8 + amount
    else
        return false, "Invalid bet type"
    end
    
    -- Deduct from player balance
    self:DeductBalance(playerName, amount)
    
    -- Update table risk
    self.currentRisk = self.currentRisk + potentialPayout
    
    BJ:Debug(playerName .. " placed " .. amount .. " on " .. betType .. (point and (" " .. point) or "") .. " | Balance: " .. player.balance .. " | Risk: " .. self.currentRisk)
    return true
end

-- Check if a bet can be placed in current phase
function CS:CanPlaceBet(betType, point)
    -- Come out phase (no point established): Pass/Don't Pass, one-roll bets
    local comeOutPhase = (self.phase == self.PHASE.COME_OUT or self.phase == self.PHASE.BETTING) and self.point == nil
    
    -- Point phase (point established): includes BETTING phase when point exists
    local pointPhase = self.phase == self.PHASE.POINT or self.phase == self.PHASE.ROLLING or 
                       (self.phase == self.PHASE.BETTING and self.point ~= nil)
    
    if comeOutPhase then
        if betType == "passLine" or betType == "dontPass" then
            return true
        end
        -- One-roll bets always allowed
        if betType == "field" or betType == "any7" or betType == "anyCraps" or
           betType == "craps2" or betType == "craps3" or betType == "craps12" or
           betType == "yo11" then
            return true
        end
        -- Hardways allowed anytime
        if betType == "hard4" or betType == "hard6" or betType == "hard8" or betType == "hard10" then
            return true
        end
        -- Big 6/8 allowed anytime
        if betType == "big6" or betType == "big8" then
            return true
        end
    end
    
    -- Point phase: Odds, Come/Don't Come, Place bets
    if pointPhase then
        if betType == "passLineOdds" or betType == "dontPassOdds" then
            return self.point ~= nil
        end
        if betType == "come" or betType == "dontCome" or betType == "comeOdds" then
            return true
        end
        if betType == "place" and point then
            return true
        end
        -- One-roll bets always allowed
        if betType == "field" or betType == "any7" or betType == "anyCraps" or
           betType == "craps2" or betType == "craps3" or betType == "craps12" or
           betType == "yo11" then
            return true
        end
        -- Hardways allowed anytime
        if betType == "hard4" or betType == "hard6" or betType == "hard8" or betType == "hard10" then
            return true
        end
        -- Big 6/8 allowed anytime
        if betType == "big6" or betType == "big8" then
            return true
        end
    end
    
    return false
end

-- Remove a place bet (returns money to player)
function CS:RemoveBet(playerName, betType, point)
    local player = self.players[playerName]
    if not player then
        return false, "Not at table"
    end
    
    -- Only allow during betting phase
    local canBet = false
    if self.phase == self.PHASE.BETTING then
        canBet = true
    elseif (self.phase == self.PHASE.COME_OUT or self.phase == self.PHASE.POINT) and self.bettingTimeRemaining and self.bettingTimeRemaining > 0 then
        canBet = true
    end
    
    if not canBet then
        return false, "Cannot remove bets now"
    end
    
    -- Check if locked in
    if player.lockedIn then
        return false, "Bets are locked"
    end
    
    local bets = player.bets
    
    -- Only allow removing place bets for now
    if betType == "place" and point then
        local amount = bets.place[point] or 0
        if amount <= 0 then
            return false, "No bet to remove"
        end
        
        -- Return bet to player balance
        player.balance = player.balance + amount
        bets.place[point] = 0
        
        -- Update table risk
        self:UpdateTableRisk()
        
        BJ:Debug(playerName .. " removed place " .. point .. " bet of " .. amount)
        return true
    end
    
    return false, "Cannot remove this bet type"
end

-- Get max odds multiplier for a point
function CS:GetMaxOdds(point)
    -- 3-4-5 odds: 3x on 4/10, 4x on 5/9, 5x on 6/8
    if self.maxOdds == 345 then
        if point == 4 or point == 10 then return 3 end
        if point == 5 or point == 9 then return 4 end
        if point == 6 or point == 8 then return 5 end
    end
    return self.maxOdds
end

-- Start the come-out roll phase
function CS:StartComeOut()
    if self.phase ~= self.PHASE.BETTING then
        return false, "Not in betting phase"
    end
    
    if #self.shooterOrder < 1 then
        return false, "Need at least 1 player"
    end
    
    self.phase = self.PHASE.COME_OUT
    self.point = nil
    self.rollStartTime = time()
    
    BJ:Debug("Come-out roll phase started, shooter: " .. self.shooterName)
    return true
end

-- Process a dice roll
function CS:ProcessRoll(die1, die2)
    local total = die1 + die2
    local isHard = (die1 == die2)
    
    self.lastRoll = {
        die1 = die1,
        die2 = die2,
        total = total,
        isHard = isHard,
        timestamp = time()
    }
    
    -- Add to history (keep last 20 rolls)
    table.insert(self.rollHistory, 1, self.lastRoll)
    while #self.rollHistory > 20 do
        table.remove(self.rollHistory)
    end
    
    BJ:Debug("Roll: " .. die1 .. " + " .. die2 .. " = " .. total .. (isHard and " (HARD)" or ""))
    
    local result
    if self.phase == self.PHASE.COME_OUT then
        result = self:ProcessComeOutRoll(total)
    elseif self.phase == self.PHASE.POINT or self.phase == self.PHASE.ROLLING then
        result = self:ProcessPointRoll(total, isHard)
    else
        return nil, "Invalid phase for rolling"
    end
    
    -- Settle bets based on roll
    local settlements = self:SettleRoll(result, total, die1, die2)
    
    return result, settlements
end

-- Process roll locally (for clients) - clears bets that were lost without balance changes
-- Balance changes come from SETTLEMENT messages from host
function CS:ProcessRollLocal(result, total, isHard)
    for playerName, player in pairs(self.players) do
        if not player.isHost then
            local bets = player.bets
            
            -- Clear one-roll bets (Field, Any 7, Any Craps, Craps 2/3/12, Yo 11)
            bets.field = 0
            bets.any7 = 0
            bets.anyCraps = 0
            bets.craps2 = 0
            bets.craps3 = 0
            bets.craps12 = 0
            bets.yo11 = 0
            
            -- Clear Pass Line bets on natural/craps/point_hit/seven_out
            if result == "natural" or result == "craps" or result == "point_hit" or result == "seven_out" then
                bets.passLine = 0
                bets.passLineOdds = 0
            end
            
            -- Clear Don't Pass on natural/craps (not 12)/point_hit/seven_out
            if result == "natural" or result == "point_hit" then
                bets.dontPass = 0
                bets.dontPassOdds = 0
            elseif result == "craps" and total ~= 12 then
                -- Don't pass wins on 2,3 but pushes on 12
            elseif result == "seven_out" then
                -- Don't pass wins
            end
            
            -- Clear hardways on 7 or if hit easy
            if total == 7 then
                bets.hard4 = 0
                bets.hard6 = 0
                bets.hard8 = 0
                bets.hard10 = 0
            elseif not isHard then
                if total == 4 then bets.hard4 = 0 end
                if total == 6 then bets.hard6 = 0 end
                if total == 8 then bets.hard8 = 0 end
                if total == 10 then bets.hard10 = 0 end
            end
            
            -- Clear place bets on 7 (lose), point_hit (returned), or when number is hit (win)
            if total == 7 or result == "point_hit" then
                for point, _ in pairs(bets.place) do
                    bets.place[point] = 0
                end
            else
                -- Clear the specific place bet that was hit (it won)
                if bets.place[total] and bets.place[total] > 0 then
                    bets.place[total] = 0
                end
            end
            
            -- Clear Big 6/8 on 7
            if total == 7 then
                bets.big6 = 0
                bets.big8 = 0
            end
            
            -- Clear Come bet on 7/11 (win) or 2/3/12 (lose), or moves to point
            local comeMoved = false
            if bets.come > 0 then
                if total == 7 or total == 11 or total == 2 or total == 3 or total == 12 then
                    bets.come = 0
                elseif total >= 4 and total <= 10 and total ~= 7 then
                    -- Moves to point - move bet to comePoints
                    if not bets.comePoints[total] then
                        bets.comePoints[total] = {base = 0, odds = 0}
                    end
                    bets.comePoints[total].base = bets.comePoints[total].base + bets.come
                    bets.come = 0
                    comeMoved = true  -- Mark that we just moved a bet here
                end
            end
            
            -- Clear Come point bets when hit (win), on 7 (lose), or point_hit (returned)
            -- BUT don't clear if we just moved a bet there on this roll
            if total == 7 or result == "point_hit" then
                for point, _ in pairs(bets.comePoints) do
                    bets.comePoints[point] = nil
                end
            elseif bets.comePoints[total] and not comeMoved then
                bets.comePoints[total] = nil
            end
            
            -- Clear Don't Come bet on 7/11 (lose) or 2/3 (win, 12 push), or moves to point
            local dontComeMoved = false
            if bets.dontCome > 0 then
                if total == 7 or total == 11 or total == 2 or total == 3 then
                    bets.dontCome = 0
                elseif total >= 4 and total <= 10 and total ~= 7 then
                    -- Moves to point - move bet to dontComePoints
                    if not bets.dontComePoints[total] then
                        bets.dontComePoints[total] = {base = 0, odds = 0}
                    end
                    bets.dontComePoints[total].base = bets.dontComePoints[total].base + bets.dontCome
                    bets.dontCome = 0
                    dontComeMoved = true  -- Mark that we just moved a bet here
                end
                -- Note: 12 is a push, bet stays but we clear it since it resolves
                if total == 12 then
                    bets.dontCome = 0
                end
            end
            
            -- Clear Don't Come point bets when hit (lose), on 7 (win), or point_hit (returned)
            -- BUT don't clear if we just moved a bet there on this roll
            if total == 7 or result == "point_hit" then
                for point, _ in pairs(bets.dontComePoints) do
                    bets.dontComePoints[point] = nil
                end
            elseif bets.dontComePoints[total] and not dontComeMoved then
                bets.dontComePoints[total] = nil
            end
        end
    end
end

-- Process come-out roll
function CS:ProcessComeOutRoll(total)
    if total == 7 or total == 11 then
        -- Natural - Pass Line wins, Don't Pass loses
        BJ:Debug("Natural " .. total .. "!")
        return "natural"
    elseif total == 2 or total == 3 or total == 12 then
        -- Craps - Pass Line loses
        BJ:Debug("Craps " .. total .. "!")
        return "craps"
    else
        -- Point established
        self.point = total
        self.phase = self.PHASE.POINT
        BJ:Debug("Point is " .. total)
        return "point_established"
    end
end

-- Process point phase roll
function CS:ProcessPointRoll(total, isHard)
    if total == 7 then
        -- Seven-out - Pass Line loses, dice pass
        BJ:Debug("Seven out!")
        local result = "seven_out"
        self.point = nil
        self:PassDice()
        self.phase = self.PHASE.COME_OUT
        return result
    elseif total == self.point then
        -- Point hit - Pass Line wins
        BJ:Debug("Point hit! " .. total)
        self.point = nil
        self.phase = self.PHASE.COME_OUT
        return "point_hit"
    else
        -- Regular roll, continue
        return "roll"
    end
end

-- Settle all bets based on roll result
function CS:SettleRoll(result, total, die1, die2)
    local settlements = {}
    local isHard = (die1 == die2)
    
    -- First pass: calculate total payouts to check for haircut
    local totalPayouts = 0
    local payoutsByPlayer = {}
    
    for playerName, player in pairs(self.players) do
        if not player.isHost then
            local bets = player.bets
            local winnings = self:CalculateSettlement(player, result, total, die1, die2)
            if winnings > 0 then
                totalPayouts = totalPayouts + winnings
                payoutsByPlayer[playerName] = winnings
            end
        end
    end
    
    -- Check if bank can cover all payouts (haircut rule)
    local host = nil
    for name, p in pairs(self.players) do
        if p.isHost then host = p break end
    end
    
    local haircutFactor = 1.0
    if host and totalPayouts > self.tableCap then
        -- Apply haircut - everyone gets scaled payout
        haircutFactor = self.tableCap / totalPayouts
        BJ:Print("|cffff8800Bank shortage! Payouts scaled to " .. string.format("%.1f%%", haircutFactor * 100) .. "|r")
    end
    
    -- Second pass: apply settlements
    for playerName, player in pairs(self.players) do
        if player.isHost then
            -- Skip host/banker
            settlements[playerName] = { winnings = 0, messages = {} }
        else
            local bets = player.bets
            local winnings = 0
            local messages = {}
            
            -- === PASS LINE ===
            if result == "natural" then
                -- Pass wins on 7 or 11
                if bets.passLine > 0 then
                    local betAmount = bets.passLine
                    local profit = betAmount  -- 1:1 payout
                    winnings = winnings + betAmount + profit  -- Return bet + profit
                    bets.passLine = 0  -- Clear the bet
                    table.insert(messages, "Pass Line wins " .. profit)
                end
                if bets.dontPass > 0 then
                    winnings = winnings - bets.dontPass
                    bets.dontPass = 0
                    table.insert(messages, "Don't Pass loses")
                end
            elseif result == "craps" then
                -- Pass loses on 2, 3, 12
                if bets.passLine > 0 then
                    winnings = winnings - bets.passLine
                    bets.passLine = 0
                    table.insert(messages, "Pass Line loses")
                end
                if bets.dontPass > 0 then
                    if total == 12 then
                        -- 12 is a push for Don't Pass - return original bet
                        winnings = winnings + bets.dontPass
                        bets.dontPass = 0
                        table.insert(messages, "Don't Pass pushes on 12")
                    else
                        -- 2 or 3 wins for Don't Pass
                        local betAmount = bets.dontPass
                        local profit = betAmount  -- 1:1 payout
                        winnings = winnings + betAmount + profit  -- Return bet + profit
                        bets.dontPass = 0
                        table.insert(messages, "Don't Pass wins " .. profit)
                    end
                end
            elseif result == "point_hit" then
                -- Pass Line wins
                if bets.passLine > 0 then
                    local betAmount = bets.passLine
                    local profit = betAmount  -- 1:1 payout
                    winnings = winnings + betAmount + profit  -- Return bet + profit
                    bets.passLine = 0
                    table.insert(messages, "Pass Line wins " .. profit)
                end
                -- Pass Line Odds win (true odds)
                if bets.passLineOdds > 0 then
                    local betAmount = bets.passLineOdds
                    local payout = self.PAYOUTS.passLineOdds[total] or 1
                    local profit = betAmount * (payout - 1)
                    winnings = winnings + betAmount + profit  -- Return bet + profit
                    bets.passLineOdds = 0
                    table.insert(messages, "Pass Odds wins " .. string.format("%.0f", profit))
                end
                -- Don't Pass loses
                if bets.dontPass > 0 then
                    winnings = winnings - bets.dontPass
                    bets.dontPass = 0
                    bets.dontPassOdds = 0
                    table.insert(messages, "Don't Pass loses")
                end
        elseif result == "seven_out" then
            -- Pass Line loses
            if bets.passLine > 0 then
                winnings = winnings - bets.passLine
                bets.passLine = 0
                bets.passLineOdds = 0
                table.insert(messages, "Pass Line loses")
            end
            -- Pass Line Odds lose
            if bets.passLineOdds > 0 then
                winnings = winnings - bets.passLineOdds
                bets.passLineOdds = 0
                table.insert(messages, "Pass Odds loses")
            end
            -- Don't Pass wins
            if bets.dontPass > 0 then
                local betAmount = bets.dontPass
                local profit = betAmount  -- 1:1 payout
                winnings = winnings + betAmount + profit  -- Return bet + profit
                bets.dontPass = 0
                table.insert(messages, "Don't Pass wins " .. profit)
            end
            -- Don't Pass Odds win
            if bets.dontPassOdds > 0 then
                local betAmount = bets.dontPassOdds
                local payout = self.PAYOUTS.dontPassOdds[self.point] or 1
                local profit = betAmount * (payout - 1)
                winnings = winnings + betAmount + profit  -- Return bet + profit
                bets.dontPassOdds = 0
                table.insert(messages, "Don't Odds wins " .. string.format("%.0f", profit))
            end
        end
        
        -- === COME BETS ===
        -- Flat come bet moves to point or resolves
        local newComePoint = nil  -- Track if we just moved a come bet
        if bets.come > 0 then
            if total == 7 or total == 11 then
                local betAmount = bets.come
                local profit = betAmount  -- 1:1 payout
                winnings = winnings + betAmount + profit  -- Return bet + profit
                bets.come = 0
                table.insert(messages, "Come wins " .. profit)
            elseif total == 2 or total == 3 or total == 12 then
                winnings = winnings - bets.come
                bets.come = 0
                table.insert(messages, "Come loses")
            else
                -- Move to the point (but don't evaluate it this roll)
                newComePoint = total
                if not bets.comePoints[total] then
                    bets.comePoints[total] = {base = 0, odds = 0}
                end
                bets.comePoints[total].base = bets.comePoints[total].base + bets.come
                bets.come = 0
                table.insert(messages, "Come bet moves to " .. total)
            end
        end
        
        -- Come bets on points (skip the one that just moved this roll)
        for point, comeBet in pairs(bets.comePoints) do
            if comeBet.base > 0 and point ~= newComePoint then
                if result == "point_hit" then
                    -- Point hit - return all come point bets (no profit, just returned)
                    local betAmount = comeBet.base
                    winnings = winnings + betAmount  -- Return bet only
                    if comeBet.odds > 0 then
                        winnings = winnings + comeBet.odds  -- Return odds bet too
                        table.insert(messages, "Come " .. point .. " returned + odds")
                    else
                        table.insert(messages, "Come " .. point .. " returned")
                    end
                    bets.comePoints[point] = nil
                elseif total == point then
                    -- Come bet wins (number hit)
                    local betAmount = comeBet.base
                    local profit = betAmount  -- 1:1 payout
                    winnings = winnings + betAmount + profit  -- Return bet + profit
                    -- Come odds win too
                    if comeBet.odds > 0 then
                        local oddsBet = comeBet.odds
                        local oddsPayout = self.PAYOUTS.passLineOdds[point] or 1
                        local oddsProfit = oddsBet * (oddsPayout - 1)
                        winnings = winnings + oddsBet + oddsProfit  -- Return odds bet + profit
                        table.insert(messages, "Come " .. point .. " wins " .. profit .. " + odds " .. string.format("%.0f", oddsProfit))
                    else
                        table.insert(messages, "Come " .. point .. " wins " .. profit)
                    end
                    bets.comePoints[point] = nil
                elseif total == 7 then
                    -- Come bet loses on 7
                    winnings = winnings - comeBet.base - comeBet.odds
                    table.insert(messages, "Come " .. point .. " loses")
                    bets.comePoints[point] = nil
                end
            end
        end
        
        -- === DON'T COME BETS ===
        -- Flat don't come bet moves to point or resolves
        local newDontComePoint = nil  -- Track if we just moved a don't come bet
        if bets.dontCome > 0 then
            if total == 2 or total == 3 then
                -- Don't Come wins on 2, 3
                local betAmount = bets.dontCome
                local profit = betAmount  -- 1:1 payout
                winnings = winnings + betAmount + profit  -- Return bet + profit
                bets.dontCome = 0
                table.insert(messages, "Don't Come wins " .. profit)
            elseif total == 12 then
                -- Push on 12 (bar 12)
                winnings = winnings  -- No change, bet returned
                bets.dontCome = 0
                table.insert(messages, "Don't Come pushes (bar 12)")
            elseif total == 7 or total == 11 then
                -- Don't Come loses on 7, 11
                winnings = winnings - bets.dontCome
                bets.dontCome = 0
                table.insert(messages, "Don't Come loses")
            else
                -- Move to the point (but don't evaluate it this roll)
                newDontComePoint = total
                if not bets.dontComePoints[total] then
                    bets.dontComePoints[total] = {base = 0, odds = 0}
                end
                bets.dontComePoints[total].base = bets.dontComePoints[total].base + bets.dontCome
                bets.dontCome = 0
                table.insert(messages, "Don't Come moves to " .. total)
            end
        end
        
        -- Don't Come bets on points (skip the one that just moved this roll)
        for point, dcBet in pairs(bets.dontComePoints) do
            if dcBet.base > 0 and point ~= newDontComePoint then
                if result == "point_hit" then
                    -- Point hit - return all don't come point bets (no profit, just returned)
                    local betAmount = dcBet.base
                    winnings = winnings + betAmount  -- Return bet only
                    if dcBet.odds > 0 then
                        winnings = winnings + dcBet.odds  -- Return odds bet too
                        table.insert(messages, "Don't Come " .. point .. " returned + odds")
                    else
                        table.insert(messages, "Don't Come " .. point .. " returned")
                    end
                    bets.dontComePoints[point] = nil
                elseif total == 7 then
                    -- Don't Come wins when 7 rolls
                    local betAmount = dcBet.base
                    local profit = betAmount  -- 1:1 payout
                    winnings = winnings + betAmount + profit  -- Return bet + profit
                    -- Don't Come Odds win too (if any)
                    if dcBet.odds > 0 then
                        local oddsBet = dcBet.odds
                        local oddsPayout = self.PAYOUTS.dontPassOdds[point] or 1
                        local oddsProfit = oddsBet * (oddsPayout - 1)
                        winnings = winnings + oddsBet + oddsProfit
                        table.insert(messages, "Don't Come " .. point .. " wins " .. profit .. " + odds " .. string.format("%.0f", oddsProfit))
                    else
                        table.insert(messages, "Don't Come " .. point .. " wins " .. profit)
                    end
                    bets.dontComePoints[point] = nil
                elseif total == point then
                    -- Don't Come loses when point rolls
                    winnings = winnings - dcBet.base - dcBet.odds
                    table.insert(messages, "Don't Come " .. point .. " loses")
                    bets.dontComePoints[point] = nil
                end
            end
        end
        
        -- === PLACE BETS ===
        if result == "point_hit" then
            -- Point hit - return all place bets (no profit, just returned)
            for point, amount in pairs(bets.place) do
                if amount > 0 then
                    winnings = winnings + amount  -- Return bet only
                    bets.place[point] = 0
                    table.insert(messages, "Place " .. point .. " returned")
                end
            end
        elseif result ~= "seven_out" then
            for point, amount in pairs(bets.place) do
                if amount > 0 and total == point then
                    local payout = self.PAYOUTS.place[point] or 2
                    local profit = amount * (payout - 1)
                    winnings = winnings + amount + profit  -- Return bet + profit
                    bets.place[point] = 0  -- Clear the bet
                    table.insert(messages, "Place " .. point .. " wins " .. string.format("%.0f", profit))
                end
            end
        else
            -- Seven out - lose all place bets
            for point, amount in pairs(bets.place) do
                if amount > 0 then
                    winnings = winnings - amount
                    bets.place[point] = 0
                    table.insert(messages, "Place " .. point .. " loses")
                end
            end
        end
        
        -- === FIELD BET (one roll) ===
        if bets.field > 0 then
            local betAmount = bets.field
            local fieldPayout = self.PAYOUTS.field[total]
            if fieldPayout then
                local profit = betAmount * (fieldPayout - 1)
                winnings = winnings + betAmount + profit  -- Return bet + profit
                table.insert(messages, "Field wins " .. string.format("%.0f", profit))
            else
                -- 5, 6, 7, 8 lose
                winnings = winnings - betAmount
                table.insert(messages, "Field loses")
            end
            bets.field = 0  -- One-roll bet
        end
        
        -- === PROPOSITION BETS (one roll) ===
        -- Any 7
        if bets.any7 > 0 then
            local betAmount = bets.any7
            if total == 7 then
                local profit = betAmount * (self.PAYOUTS.any7 - 1)
                winnings = winnings + betAmount + profit  -- Return bet + profit
                table.insert(messages, "Any 7 wins " .. string.format("%.0f", profit))
            else
                winnings = winnings - betAmount
            end
            bets.any7 = 0
        end
        
        -- Any Craps
        if bets.anyCraps > 0 then
            local betAmount = bets.anyCraps
            if total == 2 or total == 3 or total == 12 then
                local profit = betAmount * (self.PAYOUTS.anyCraps - 1)
                winnings = winnings + betAmount + profit  -- Return bet + profit
                table.insert(messages, "Any Craps wins " .. string.format("%.0f", profit))
            else
                winnings = winnings - betAmount
            end
            bets.anyCraps = 0
        end
        
        -- Specific craps
        if bets.craps2 > 0 then
            local betAmount = bets.craps2
            if total == 2 then
                local profit = betAmount * (self.PAYOUTS.craps2 - 1)
                winnings = winnings + betAmount + profit  -- Return bet + profit
                table.insert(messages, "Snake Eyes wins " .. string.format("%.0f", profit))
            else
                winnings = winnings - betAmount
            end
            bets.craps2 = 0
        end
        
        if bets.craps3 > 0 then
            local betAmount = bets.craps3
            if total == 3 then
                local profit = betAmount * (self.PAYOUTS.craps3 - 1)
                winnings = winnings + betAmount + profit  -- Return bet + profit
                table.insert(messages, "Ace Deuce wins " .. string.format("%.0f", profit))
            else
                winnings = winnings - betAmount
            end
            bets.craps3 = 0
        end
        
        if bets.craps12 > 0 then
            local betAmount = bets.craps12
            if total == 12 then
                local profit = betAmount * (self.PAYOUTS.craps12 - 1)
                winnings = winnings + betAmount + profit  -- Return bet + profit
                table.insert(messages, "Boxcars wins " .. string.format("%.0f", profit))
            else
                winnings = winnings - betAmount
            end
            bets.craps12 = 0
        end
        
        -- Yo-leven
        if bets.yo11 > 0 then
            local betAmount = bets.yo11
            if total == 11 then
                local profit = betAmount * (self.PAYOUTS.yo11 - 1)
                winnings = winnings + betAmount + profit  -- Return bet + profit
                table.insert(messages, "Yo wins " .. string.format("%.0f", profit))
            else
                winnings = winnings - betAmount
            end
            bets.yo11 = 0
        end
        
        -- === HARDWAYS ===
        -- Hard 4 (2+2)
        if bets.hard4 > 0 then
            local betAmount = bets.hard4
            if total == 4 and isHard then
                local profit = betAmount * (self.PAYOUTS.hard4 - 1)
                winnings = winnings + betAmount + profit  -- Return bet + profit
                bets.hard4 = 0
                table.insert(messages, "Hard 4 wins " .. string.format("%.0f", profit))
            elseif total == 4 or total == 7 then
                -- Easy 4 or 7 loses hardway
                winnings = winnings - betAmount
                bets.hard4 = 0
                table.insert(messages, "Hard 4 loses")
            end
        end
        
        -- Hard 6 (3+3)
        if bets.hard6 > 0 then
            local betAmount = bets.hard6
            if total == 6 and isHard then
                local profit = betAmount * (self.PAYOUTS.hard6 - 1)
                winnings = winnings + betAmount + profit  -- Return bet + profit
                bets.hard6 = 0
                table.insert(messages, "Hard 6 wins " .. string.format("%.0f", profit))
            elseif total == 6 or total == 7 then
                winnings = winnings - betAmount
                bets.hard6 = 0
                table.insert(messages, "Hard 6 loses")
            end
        end
        
        -- Hard 8 (4+4)
        if bets.hard8 > 0 then
            local betAmount = bets.hard8
            if total == 8 and isHard then
                local profit = betAmount * (self.PAYOUTS.hard8 - 1)
                winnings = winnings + betAmount + profit  -- Return bet + profit
                bets.hard8 = 0
                table.insert(messages, "Hard 8 wins " .. string.format("%.0f", profit))
            elseif total == 8 or total == 7 then
                winnings = winnings - betAmount
                bets.hard8 = 0
                table.insert(messages, "Hard 8 loses")
            end
        end
        
        -- Hard 10 (5+5)
        if bets.hard10 > 0 then
            local betAmount = bets.hard10
            if total == 10 and isHard then
                local profit = betAmount * (self.PAYOUTS.hard10 - 1)
                winnings = winnings + betAmount + profit  -- Return bet + profit
                bets.hard10 = 0
                table.insert(messages, "Hard 10 wins " .. string.format("%.0f", profit))
            elseif total == 10 or total == 7 then
                winnings = winnings - betAmount
                bets.hard10 = 0
                table.insert(messages, "Hard 10 loses")
            end
        end
        
        -- === BIG 6/8 ===
        if bets.big6 > 0 then
            local betAmount = bets.big6
            if total == 6 then
                local profit = betAmount * (self.PAYOUTS.big6 - 1)
                winnings = winnings + betAmount + profit  -- Return bet + profit
                bets.big6 = 0
                table.insert(messages, "Big 6 wins " .. string.format("%.0f", profit))
            elseif total == 7 then
                winnings = winnings - betAmount
                bets.big6 = 0
                table.insert(messages, "Big 6 loses")
            end
        end
        
        if bets.big8 > 0 then
            local betAmount = bets.big8
            if total == 8 then
                local profit = betAmount * (self.PAYOUTS.big8 - 1)
                winnings = winnings + betAmount + profit  -- Return bet + profit
                bets.big8 = 0
                table.insert(messages, "Big 8 wins " .. string.format("%.0f", profit))
            elseif total == 7 then
                winnings = winnings - betAmount
                bets.big8 = 0
                table.insert(messages, "Big 8 loses")
            end
        end
        
        -- Store settlement for this player
        player.sessionBalance = (player.sessionBalance or 0) + winnings
        
        -- Honor Ledger: Add/subtract from balance
        -- Winnings includes net change (positive = won, negative = lost)
        -- When bets were placed, amount was deducted from balance
        -- So winnings here is net profit/loss after bet
        if winnings > 0 then
            -- Player won - add winnings to balance (bet amount already in play)
            self:AddBalance(playerName, winnings)
        elseif winnings < 0 then
            -- Player lost - no action needed, bet was already deducted
            -- But we need to add back any winning bet amounts that weren't lost
        end
        
        -- Apply haircut to winnings if needed
        if winnings > 0 and haircutFactor < 1.0 then
            local originalWinnings = winnings
            winnings = math.floor(winnings * haircutFactor)
            table.insert(messages, "(Haircut applied: " .. originalWinnings .. " -> " .. winnings .. ")")
        end
        
        -- Add back any bet amounts that were won (original stake + profit)
        -- Calculate return of winning bets
        local returnAmount = self:CalculateWinningBetReturns(player, result, total, isHard)
        if returnAmount > 0 then
            self:AddBalance(playerName, returnAmount)
        end
        
        -- Clear resolved bets (one-roll bets always clear, others clear on resolution)
        self:ClearResolvedBets(player, result, total, isHard)
        
        -- Check for bankruptcy (balance <= 0 with no active bets)
        if player.balance <= 0 then
            local hasBets = false
            for betType, amount in pairs(player.bets) do
                if type(amount) == "number" and amount > 0 then
                    hasBets = true
                    break
                elseif type(amount) == "table" then
                    for _, v in pairs(amount) do
                        if v > 0 then hasBets = true break end
                    end
                end
            end
            
            if not hasBets then
                player.isSpectator = true
                table.insert(messages, "BANKRUPT - moved to spectator mode")
            end
        end
        
        settlements[playerName] = {
            winnings = winnings,
            messages = messages,
        }
        
        -- Log balance after settlement
        if winnings ~= 0 then
            self:LogBalance(playerName, player.balance, "Roll " .. (self.lastRoll and self.lastRoll.total or "?"))
        end
        end  -- End of else (not host)
    end
    
    -- Reset table risk after roll (recalculate based on remaining bets)
    self:RecalculateRisk()
    
    return settlements
end

-- Calculate the return of winning bet stakes (original bet amount returned)
function CS:CalculateWinningBetReturns(player, result, total, isHard)
    local bets = player.bets
    local returned = 0
    
    -- Pass Line bets - returned on win
    if result == "natural" or result == "point_hit" then
        returned = returned + bets.passLine
        returned = returned + bets.passLineOdds
    end
    
    -- Don't Pass - returned on craps (except 12) or seven_out
    if result == "craps" and total ~= 12 then
        returned = returned + bets.dontPass
    elseif result == "seven_out" then
        returned = returned + bets.dontPass
        returned = returned + bets.dontPassOdds
    end
    
    -- Field bets - one roll, returned on win
    if bets.field > 0 and (total == 2 or total == 3 or total == 4 or total == 9 or total == 10 or total == 11 or total == 12) then
        returned = returned + bets.field
    end
    
    -- Proposition bets - one roll, returned on win
    if total == 7 and bets.any7 > 0 then
        returned = returned + bets.any7
    end
    if (total == 2 or total == 3 or total == 12) and bets.anyCraps > 0 then
        returned = returned + bets.anyCraps
    end
    if total == 2 and bets.craps2 > 0 then
        returned = returned + bets.craps2
    end
    if total == 3 and bets.craps3 > 0 then
        returned = returned + bets.craps3
    end
    if total == 12 and bets.craps12 > 0 then
        returned = returned + bets.craps12
    end
    if total == 11 and bets.yo11 > 0 then
        returned = returned + bets.yo11
    end
    
    -- Hardways - returned on hard win
    if isHard then
        if total == 4 and bets.hard4 > 0 then returned = returned + bets.hard4 end
        if total == 6 and bets.hard6 > 0 then returned = returned + bets.hard6 end
        if total == 8 and bets.hard8 > 0 then returned = returned + bets.hard8 end
        if total == 10 and bets.hard10 > 0 then returned = returned + bets.hard10 end
    end
    
    -- Place bets - returned on win (stay active)
    if bets.place[total] and bets.place[total] > 0 and total ~= 7 then
        returned = returned + bets.place[total]
    end
    
    -- Big 6/8 - returned on win (stay active)
    if total == 6 and bets.big6 > 0 then returned = returned + bets.big6 end
    if total == 8 and bets.big8 > 0 then returned = returned + bets.big8 end
    
    return returned
end

-- Calculate settlement for haircut check (winnings only, no balance changes)
function CS:CalculateSettlement(player, result, total, die1, die2)
    local bets = player.bets
    local winnings = 0
    local isHard = (die1 == die2)
    
    -- Pass Line
    if result == "natural" and bets.passLine > 0 then
        winnings = winnings + bets.passLine * (self.PAYOUTS.passLine - 1)
    elseif result == "point_hit" then
        if bets.passLine > 0 then winnings = winnings + bets.passLine * (self.PAYOUTS.passLine - 1) end
        if bets.passLineOdds > 0 then
            local payout = self.PAYOUTS.passLineOdds[total] or 1
            winnings = winnings + bets.passLineOdds * (payout - 1)
        end
    end
    
    -- Don't Pass
    if result == "craps" and total ~= 12 and bets.dontPass > 0 then
        winnings = winnings + bets.dontPass * (self.PAYOUTS.dontPass - 1)
    elseif result == "seven_out" then
        if bets.dontPass > 0 then winnings = winnings + bets.dontPass * (self.PAYOUTS.dontPass - 1) end
        if bets.dontPassOdds > 0 then
            local payout = self.PAYOUTS.dontPassOdds[self.point] or 1
            winnings = winnings + bets.dontPassOdds * (payout - 1)
        end
    end
    
    -- Field
    if bets.field > 0 then
        local fieldPayout = self.PAYOUTS.field[total]
        if fieldPayout then
            winnings = winnings + bets.field * (fieldPayout - 1)
        end
    end
    
    -- Props
    if total == 7 and bets.any7 > 0 then winnings = winnings + bets.any7 * (self.PAYOUTS.any7 - 1) end
    if (total == 2 or total == 3 or total == 12) and bets.anyCraps > 0 then
        winnings = winnings + bets.anyCraps * (self.PAYOUTS.anyCraps - 1)
    end
    if total == 2 and bets.craps2 > 0 then winnings = winnings + bets.craps2 * (self.PAYOUTS.craps2 - 1) end
    if total == 3 and bets.craps3 > 0 then winnings = winnings + bets.craps3 * (self.PAYOUTS.craps3 - 1) end
    if total == 12 and bets.craps12 > 0 then winnings = winnings + bets.craps12 * (self.PAYOUTS.craps12 - 1) end
    if total == 11 and bets.yo11 > 0 then winnings = winnings + bets.yo11 * (self.PAYOUTS.yo11 - 1) end
    
    -- Hardways
    if total == 4 and isHard and bets.hard4 > 0 then winnings = winnings + bets.hard4 * (self.PAYOUTS.hard4 - 1) end
    if total == 6 and isHard and bets.hard6 > 0 then winnings = winnings + bets.hard6 * (self.PAYOUTS.hard6 - 1) end
    if total == 8 and isHard and bets.hard8 > 0 then winnings = winnings + bets.hard8 * (self.PAYOUTS.hard8 - 1) end
    if total == 10 and isHard and bets.hard10 > 0 then winnings = winnings + bets.hard10 * (self.PAYOUTS.hard10 - 1) end
    
    -- Place bets
    if total ~= 7 then
        local amount = bets.place[total] or 0
        if amount > 0 then
            local payout = self.PAYOUTS.place[total] or 1
            winnings = winnings + amount * (payout - 1)
        end
    end
    
    -- Big 6/8
    if total == 6 and bets.big6 > 0 then winnings = winnings + bets.big6 * (self.PAYOUTS.big6 - 1) end
    if total == 8 and bets.big8 > 0 then winnings = winnings + bets.big8 * (self.PAYOUTS.big8 - 1) end
    
    return winnings
end

-- Clear bets that have resolved (either won or lost)
function CS:ClearResolvedBets(player, result, total, isHard)
    local bets = player.bets
    
    -- One-roll bets ALWAYS clear
    bets.field = 0
    bets.any7 = 0
    bets.anyCraps = 0
    bets.craps2 = 0
    bets.craps3 = 0
    bets.craps12 = 0
    bets.yo11 = 0
    
    -- Pass Line - clears on natural, craps, point_hit, or seven_out
    if result == "natural" or result == "craps" or result == "point_hit" or result == "seven_out" then
        bets.passLine = 0
        bets.passLineOdds = 0
    end
    
    -- Don't Pass - clears on natural (loses), point_hit (loses), seven_out (wins), or craps (wins/push)
    if result == "natural" or result == "point_hit" or result == "seven_out" or result == "craps" then
        bets.dontPass = 0
        bets.dontPassOdds = 0
    end
    
    -- Hardways - clear on 7 or if the number hits easy
    if total == 7 then
        bets.hard4 = 0
        bets.hard6 = 0
        bets.hard8 = 0
        bets.hard10 = 0
    else
        if total == 4 then bets.hard4 = 0 end
        if total == 6 then bets.hard6 = 0 end
        if total == 8 then bets.hard8 = 0 end
        if total == 10 then bets.hard10 = 0 end
    end
    
    -- Place bets - clear on 7 (lose)
    if total == 7 then
        for point, _ in pairs(bets.place) do
            bets.place[point] = 0
        end
    end
    
    -- Big 6/8 - clear on 7 (lose)
    if total == 7 then
        bets.big6 = 0
        bets.big8 = 0
    end
end

-- Recalculate current risk based on all active bets
function CS:RecalculateRisk()
    local totalRisk = 0
    
    for playerName, player in pairs(self.players) do
        if not player.isHost then
            local bets = player.bets
            
            -- Calculate potential payout for each active bet
            totalRisk = totalRisk + self:CalculatePotentialPayout("passLine", bets.passLine, self.point)
            totalRisk = totalRisk + self:CalculatePotentialPayout("passLineOdds", bets.passLineOdds, self.point)
            totalRisk = totalRisk + self:CalculatePotentialPayout("dontPass", bets.dontPass, self.point)
            totalRisk = totalRisk + self:CalculatePotentialPayout("dontPassOdds", bets.dontPassOdds, self.point)
            totalRisk = totalRisk + self:CalculatePotentialPayout("come", bets.come, nil)
            totalRisk = totalRisk + self:CalculatePotentialPayout("dontCome", bets.dontCome, nil)
            totalRisk = totalRisk + self:CalculatePotentialPayout("field", bets.field, nil)
            totalRisk = totalRisk + self:CalculatePotentialPayout("any7", bets.any7, nil)
            totalRisk = totalRisk + self:CalculatePotentialPayout("anyCraps", bets.anyCraps, nil)
            totalRisk = totalRisk + self:CalculatePotentialPayout("craps2", bets.craps2, nil)
            totalRisk = totalRisk + self:CalculatePotentialPayout("craps3", bets.craps3, nil)
            totalRisk = totalRisk + self:CalculatePotentialPayout("craps12", bets.craps12, nil)
            totalRisk = totalRisk + self:CalculatePotentialPayout("yo11", bets.yo11, nil)
            totalRisk = totalRisk + self:CalculatePotentialPayout("hard4", bets.hard4, nil)
            totalRisk = totalRisk + self:CalculatePotentialPayout("hard6", bets.hard6, nil)
            totalRisk = totalRisk + self:CalculatePotentialPayout("hard8", bets.hard8, nil)
            totalRisk = totalRisk + self:CalculatePotentialPayout("hard10", bets.hard10, nil)
            totalRisk = totalRisk + self:CalculatePotentialPayout("big6", bets.big6, nil)
            totalRisk = totalRisk + self:CalculatePotentialPayout("big8", bets.big8, nil)
            
            -- Place bets
            for point, amount in pairs(bets.place) do
                totalRisk = totalRisk + self:CalculatePotentialPayout("place", amount, point)
            end
            
            -- Come point bets
            for point, comeBet in pairs(bets.comePoints) do
                totalRisk = totalRisk + self:CalculatePotentialPayout("come", comeBet.base, point)
                totalRisk = totalRisk + self:CalculatePotentialPayout("comeOdds", comeBet.odds, point)
            end
            
            -- Don't Come point bets
            for point, dcBet in pairs(bets.dontComePoints) do
                totalRisk = totalRisk + self:CalculatePotentialPayout("dontCome", dcBet.base, point)
                totalRisk = totalRisk + self:CalculatePotentialPayout("dontComeOdds", dcBet.odds, point)
            end
        end
    end
    
    self.currentRisk = totalRisk
    BJ:Debug("Recalculated risk: " .. totalRisk)
end

-- Get total bet amount for a player
function CS:GetPlayerTotalBets(playerName)
    local player = self.players[playerName]
    if not player then return 0 end
    
    local bets = player.bets
    local total = 0
    
    total = total + bets.passLine + bets.passLineOdds
    total = total + bets.dontPass + bets.dontPassOdds
    total = total + bets.come + bets.dontCome
    
    for _, comeBet in pairs(bets.comePoints) do
        total = total + comeBet.base + comeBet.odds
    end
    for _, dcBet in pairs(bets.dontComePoints) do
        total = total + dcBet.base + dcBet.odds
    end
    
    for _, amount in pairs(bets.place) do
        total = total + amount
    end
    
    total = total + bets.field
    total = total + bets.any7 + bets.anyCraps
    total = total + bets.craps2 + bets.craps3 + bets.craps12 + bets.yo11
    total = total + bets.hard4 + bets.hard6 + bets.hard8 + bets.hard10
    total = total + bets.big6 + bets.big8
    
    return total
end

-- Get player count
function CS:GetPlayerCount()
    return #self.shooterOrder
end

-- Check if player is the shooter
function CS:IsShooter(playerName)
    return self.shooterName == playerName
end

-- Check if player is the host
function CS:IsHost(playerName)
    return self.hostName == playerName
end

-- Get roll result text
function CS:GetRollText()
    if not self.lastRoll then return "" end
    
    local r = self.lastRoll
    local text = r.die1 .. " + " .. r.die2 .. " = " .. r.total
    if r.isHard then
        text = text .. " (HARD)"
    end
    return text
end

-- Get phase display text
function CS:GetPhaseText()
    if self.phase == self.PHASE.IDLE then
        return "No game"
    elseif self.phase == self.PHASE.BETTING then
        return "Place your bets"
    elseif self.phase == self.PHASE.COME_OUT then
        if self.shooterName then
            return self.shooterName .. "'s come-out roll"
        end
        return "Come-out roll"
    elseif self.phase == self.PHASE.POINT then
        return "Point is " .. (self.point or "?")
    elseif self.phase == self.PHASE.ROLLING then
        return "Waiting for roll"
    elseif self.phase == self.PHASE.SETTLEMENT then
        return "Settlement"
    end
    return ""
end

-- Game history
CS.gameHistory = {}
CS.MAX_HISTORY = 10

-- Balance log for record keeping (simple balance snapshots)
CS.balanceLog = {}
CS.MAX_BALANCE_LOG = 100

-- Log a balance snapshot
function CS:LogBalance(playerName, balance, note)
    local entry = {
        time = date("%H:%M:%S"),
        player = playerName,
        balance = balance,
        note = note or "",
    }
    
    table.insert(self.balanceLog, entry)
    while #self.balanceLog > self.MAX_BALANCE_LOG do
        table.remove(self.balanceLog, 1)
    end
    
    -- Auto-save
    self:SaveBalanceLog()
end

-- Save balance log to SavedVariables
function CS:SaveBalanceLog()
    if not ChairfacesCasinoSaved then
        ChairfacesCasinoSaved = {}
    end
    ChairfacesCasinoSaved.crapsBalanceLog = self.balanceLog
end

-- Load balance log from SavedVariables
function CS:LoadBalanceLog()
    if ChairfacesCasinoSaved and ChairfacesCasinoSaved.crapsBalanceLog then
        self.balanceLog = ChairfacesCasinoSaved.crapsBalanceLog
    end
end

-- Save current session to history
function CS:SaveToHistory()
    local game = {
        timestamp = time(),
        host = self.hostName,
        rolls = {},
        players = {},
    }
    
    -- Copy roll history
    for i, roll in ipairs(self.rollHistory) do
        table.insert(game.rolls, {
            die1 = roll.die1,
            die2 = roll.die2,
            total = roll.total,
            isHard = roll.isHard,
        })
        if i >= 20 then break end  -- Limit
    end
    
    -- Copy player balances
    for name, player in pairs(self.players) do
        table.insert(game.players, {
            name = name,
            balance = player.sessionBalance or 0,
        })
    end
    
    table.insert(self.gameHistory, 1, game)
    while #self.gameHistory > self.MAX_HISTORY do
        table.remove(self.gameHistory)
    end
    
    self:SaveHistoryToDB()
end

-- Save history to SavedVariables
function CS:SaveHistoryToDB()
    if not ChairfacesCasinoSaved then
        ChairfacesCasinoSaved = {}
    end
    
    if BJ.Compression and BJ.Compression.EncodeForSave then
        ChairfacesCasinoSaved.crapsHistory = BJ.Compression:EncodeForSave(self.gameHistory)
    end
end

-- Load history from SavedVariables
function CS:LoadHistoryFromDB()
    if not ChairfacesCasinoSaved or not ChairfacesCasinoSaved.crapsHistory then
        return
    end
    
    if BJ.Compression and BJ.Compression.DecodeFromSave then
        local decoded = BJ.Compression:DecodeFromSave(ChairfacesCasinoSaved.crapsHistory)
        if decoded and type(decoded) == "table" then
            self.gameHistory = decoded
            BJ:Debug("Loaded " .. #self.gameHistory .. " craps games from history")
        end
    end
end

-- Generate cash out receipt for a player
function CS:GenerateCashOutReceipt(playerName)
    local player = self.players[playerName]
    if not player then return nil end
    
    local netChange = player.balance - player.startBalance
    local netText = netChange >= 0 and ("+" .. netChange) or tostring(netChange)
    
    local receipt = {
        player = playerName,
        startBalance = player.startBalance,
        endBalance = player.balance,
        netChange = netChange,
        netText = netText,
        timestamp = time(),
    }
    
    return receipt
end

-- Format receipt as chat-friendly text
function CS:FormatReceiptText(receipt)
    if not receipt then return "" end
    
    local lines = {
        "--- CASINO RECEIPT ---",
        "Player: " .. receipt.player,
        "Start Balance: " .. receipt.startBalance,
        "End Balance: " .. receipt.endBalance,
        "Net " .. (receipt.netChange >= 0 and "Win" or "Loss") .. ": " .. receipt.netText,
        "----------------------",
    }
    
    return table.concat(lines, "\n")
end

-- Calculate potential payout for a bet (for risk tracking)
function CS:CalculatePotentialPayout(betType, amount, point)
    local payout = 0
    
    if betType == "passLine" or betType == "dontPass" or betType == "come" or betType == "dontCome" then
        payout = amount  -- 1:1 payout
    elseif betType == "passLineOdds" and point and self.PAYOUTS.passLineOdds[point] then
        payout = amount * (self.PAYOUTS.passLineOdds[point] - 1)
    elseif betType == "dontPassOdds" and point and self.PAYOUTS.dontPassOdds[point] then
        payout = amount * (self.PAYOUTS.dontPassOdds[point] - 1)
    elseif betType == "place" and point and self.PAYOUTS.place[point] then
        payout = amount * (self.PAYOUTS.place[point] - 1)
    elseif betType == "field" then
        payout = amount * 2  -- Best case 2:1
    elseif betType == "any7" then
        payout = amount * (self.PAYOUTS.any7 - 1)
    elseif betType == "anyCraps" then
        payout = amount * (self.PAYOUTS.anyCraps - 1)
    elseif betType == "craps2" or betType == "craps12" then
        payout = amount * (self.PAYOUTS.craps2 - 1)
    elseif betType == "craps3" or betType == "yo11" then
        payout = amount * (self.PAYOUTS.craps3 - 1)
    elseif betType == "hard4" or betType == "hard10" then
        payout = amount * (self.PAYOUTS.hard4 - 1)
    elseif betType == "hard6" or betType == "hard8" then
        payout = amount * (self.PAYOUTS.hard6 - 1)
    elseif betType == "big6" or betType == "big8" then
        payout = amount  -- 1:1
    end
    
    return payout
end

-- Check if a bet would exceed the table cap
function CS:WouldExceedCap(betType, amount, point)
    local potentialPayout = self:CalculatePotentialPayout(betType, amount, point)
    return (self.currentRisk + potentialPayout) > self.tableCap
end

-- Get current risk as percentage of cap
function CS:GetRiskPercentage()
    if self.tableCap <= 0 then return 100 end
    return math.floor((self.currentRisk / self.tableCap) * 100)
end

-- Get available cap (remaining room for bets)
function CS:GetAvailableCap()
    return math.max(0, self.tableCap - self.currentRisk)
end

-- ============================================
-- HOST SESSION RESTORATION SYSTEM
-- ============================================

-- Save current session state for crash recovery
function CS:SaveHostSession()
    if not ChairfacesCasinoSaved then
        ChairfacesCasinoSaved = {}
    end
    
    local session = {
        timestamp = time(),
        hostName = self.hostName,
        phase = self.phase,
        point = self.point,
        shooterName = self.shooterName,
        shooterIndex = self.shooterIndex,
        shooterHasRolled = self.shooterHasRolled,
        shooterOrder = {},
        players = {},
        lastRoll = self.lastRoll,
        -- Settings
        minBet = self.minBet,
        maxBet = self.maxBet,
        maxOdds = self.maxOdds,
        tableCap = self.tableCap,
        bettingTimer = self.bettingTimer,
    }
    
    -- Copy shooter order
    for i, name in ipairs(self.shooterOrder) do
        session.shooterOrder[i] = name
    end
    
    -- Copy players with all their data
    for name, player in pairs(self.players) do
        if not player.isHost then
            session.players[name] = {
                balance = player.balance,
                startBalance = player.startBalance,
                isSpectator = player.isSpectator,
                lockedIn = player.lockedIn,
                bets = self:CopyBets(player.bets),
            }
        end
    end
    
    ChairfacesCasinoSaved.crapsHostSession = session
end

-- Helper to deep copy bets structure
function CS:CopyBets(bets)
    if not bets then return self:CreateEmptyBets() end
    
    local copy = {
        passLine = bets.passLine or 0,
        passLineOdds = bets.passLineOdds or 0,
        dontPass = bets.dontPass or 0,
        dontPassOdds = bets.dontPassOdds or 0,
        come = bets.come or 0,
        dontCome = bets.dontCome or 0,
        comePoints = {},
        dontComePoints = {},
        place = {},
        field = bets.field or 0,
        any7 = bets.any7 or 0,
        anyCraps = bets.anyCraps or 0,
        craps2 = bets.craps2 or 0,
        craps3 = bets.craps3 or 0,
        craps12 = bets.craps12 or 0,
        yo11 = bets.yo11 or 0,
        hard4 = bets.hard4 or 0,
        hard6 = bets.hard6 or 0,
        hard8 = bets.hard8 or 0,
        hard10 = bets.hard10 or 0,
        big6 = bets.big6 or 0,
        big8 = bets.big8 or 0,
    }
    
    -- Copy come points
    if bets.comePoints then
        for point, data in pairs(bets.comePoints) do
            copy.comePoints[point] = {base = data.base or 0, odds = data.odds or 0}
        end
    end
    
    -- Copy don't come points
    if bets.dontComePoints then
        for point, data in pairs(bets.dontComePoints) do
            copy.dontComePoints[point] = {base = data.base or 0, odds = data.odds or 0}
        end
    end
    
    -- Copy place bets
    if bets.place then
        for point, amount in pairs(bets.place) do
            copy.place[point] = amount
        end
    end
    
    return copy
end

-- Check if there's a restorable session
function CS:HasRestorableSession()
    if not ChairfacesCasinoSaved or not ChairfacesCasinoSaved.crapsHostSession then
        return false
    end
    
    local session = ChairfacesCasinoSaved.crapsHostSession
    local myName = UnitName("player")
    
    -- Must be the same host
    if session.hostName ~= myName then
        return false
    end
    
    -- Session must be recent (within 30 minutes)
    local age = time() - (session.timestamp or 0)
    if age > 1800 then
        return false
    end
    
    -- Must have players with balances
    local hasPlayers = false
    for name, player in pairs(session.players or {}) do
        if player.balance and player.balance > 0 then
            hasPlayers = true
            break
        end
    end
    
    return hasPlayers
end

-- Get session info for display
function CS:GetRestorableSessionInfo()
    if not ChairfacesCasinoSaved or not ChairfacesCasinoSaved.crapsHostSession then
        return nil
    end
    
    local session = ChairfacesCasinoSaved.crapsHostSession
    local info = {
        timestamp = session.timestamp,
        age = time() - (session.timestamp or 0),
        playerCount = 0,
        totalBalance = 0,
        point = session.point,
        phase = session.phase,
    }
    
    for name, player in pairs(session.players or {}) do
        info.playerCount = info.playerCount + 1
        info.totalBalance = info.totalBalance + (player.balance or 0)
    end
    
    return info
end

-- Restore host session
function CS:RestoreHostSession()
    if not ChairfacesCasinoSaved or not ChairfacesCasinoSaved.crapsHostSession then
        return false, "No session to restore"
    end
    
    local session = ChairfacesCasinoSaved.crapsHostSession
    local myName = UnitName("player")
    
    if session.hostName ~= myName then
        return false, "Session belongs to different host"
    end
    
    -- Reset first
    self:Reset()
    
    -- Restore basic state
    self.hostName = session.hostName
    self.point = session.point
    self.shooterIndex = session.shooterIndex or 1
    self.shooterHasRolled = session.shooterHasRolled or false
    self.lastRoll = session.lastRoll
    
    -- Restore settings
    self.minBet = session.minBet or 100
    self.maxBet = session.maxBet or 10000
    self.maxOdds = session.maxOdds or 3
    self.tableCap = session.tableCap or 100000
    self.bettingTimer = session.bettingTimer or 60
    
    -- Clear game state - start fresh (no point, no bets)
    self.point = nil
    self.lastRoll = nil
    self.currentRisk = 0
    
    -- Add host as bank
    self.players[myName] = {
        balance = 0,
        startBalance = 0,
        sessionBalance = 0,
        bets = self:CreateEmptyBets(),
        isHost = true,
        isSpectator = false,
        lockedIn = true,
    }
    
    -- Restore shooter order
    self.shooterOrder = {}
    for i, name in ipairs(session.shooterOrder or {}) do
        self.shooterOrder[i] = name
    end
    
    -- Restore players (they need to reconnect, but we track their balances)
    -- Bets are cleared - only balances are preserved
    self.restoredPlayers = {}  -- Track who needs to reconnect
    for name, playerData in pairs(session.players or {}) do
        self.restoredPlayers[name] = {
            balance = playerData.balance,
            startBalance = playerData.startBalance,
            sessionBalance = playerData.sessionBalance or 0,
            bets = self:CreateEmptyBets(),  -- Clear bets - start fresh
            isSpectator = playerData.isSpectator,
            lockedIn = false,  -- Not locked in - new round
        }
    end
    
    -- Set phase - go to BETTING to let players reconnect
    -- Once they reconnect, host can resume
    self.phase = self.PHASE.BETTING
    self.isRestoring = true
    
    -- Restore shooter if they were in the session
    if session.shooterName and self.restoredPlayers[session.shooterName] then
        self.pendingShooter = session.shooterName
    end
    
    return true, "Session restored - waiting for players to reconnect"
end

-- Handle player reconnecting to restored session
function CS:HandlePlayerReconnect(playerName)
    if not self.restoredPlayers or not self.restoredPlayers[playerName] then
        return false
    end
    
    local restored = self.restoredPlayers[playerName]
    
    -- Add player with their restored balance but empty bets (fresh start)
    self.players[playerName] = {
        balance = restored.balance,
        startBalance = restored.startBalance,
        sessionBalance = restored.sessionBalance or 0,
        bets = self:CreateEmptyBets(),  -- Fresh bets for new round
        isHost = false,
        isSpectator = restored.isSpectator or false,
        lockedIn = false,  -- Not locked in - new round starting
    }
    
    -- Add to shooter order if not already there and not spectator
    if not restored.isSpectator then
        local inOrder = false
        for _, name in ipairs(self.shooterOrder) do
            if name == playerName then
                inOrder = true
                break
            end
        end
        if not inOrder then
            table.insert(self.shooterOrder, playerName)
        end
    end
    
    -- If this was the pending shooter, restore them
    if self.pendingShooter == playerName then
        self.shooterName = playerName
        self.pendingShooter = nil
    end
    
    -- Remove from pending reconnects
    self.restoredPlayers[playerName] = nil
    
    -- Check if all players have reconnected
    local pendingCount = 0
    for _ in pairs(self.restoredPlayers) do
        pendingCount = pendingCount + 1
    end
    
    return true, pendingCount
end

-- Get list of players still needing to reconnect
function CS:GetPendingReconnects()
    if not self.restoredPlayers then return {} end
    
    local pending = {}
    for name, data in pairs(self.restoredPlayers) do
        table.insert(pending, {
            name = name,
            balance = data.balance,
        })
    end
    return pending
end

-- Clear the saved session (call after successful close or when abandoning)
function CS:ClearSavedSession()
    if ChairfacesCasinoSaved then
        ChairfacesCasinoSaved.crapsHostSession = nil
    end
    self.restoredPlayers = nil
    self.isRestoring = nil
    self.pendingShooter = nil
end

-- Finalize restoration (host confirms all needed players are back)
function CS:FinalizeRestoration()
    if not self.isRestoring then return false end
    
    -- Any players who didn't reconnect - their balances are still owed
    -- Log them for record keeping
    if self.restoredPlayers then
        for name, data in pairs(self.restoredPlayers) do
            if data.balance > 0 then
                self:LogBalance(name, data.balance, "Unreconnected (owed)")
            end
        end
    end
    
    self.restoredPlayers = nil
    self.isRestoring = nil
    self.pendingShooter = nil
    
    -- Start fresh betting phase if we have players
    if self.shooterName then
        -- Always start with betting phase after restoration
        self.phase = self.PHASE.BETTING
    end
    
    return true
end
