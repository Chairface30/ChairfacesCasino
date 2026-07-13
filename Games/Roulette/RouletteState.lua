--[[
    Chairface's Casino - RouletteState.lua
    Roulette game state management (European wheel, single zero)

    Game flow:
    1. Host opens the table and sets the chip value; host is the bank
    2. Players join and stack chips on the board (numbers + outside bets)
    3. Host spins: the result is deterministic from a broadcast seed, so
       every client computes the same number and animates the same spin
    4. Settlement: winners collect from the host, losers pay the host

    The winning pocket comes from the same style of portable LCG the
    derby engine uses - identical output on every client, no host trust.
]]

local BJ = ChairfacesCasino
BJ.RouletteState = {}
local RS = BJ.RouletteState

-- Game phases
RS.PHASE = {
    IDLE = "idle",
    BETTING = "betting",        -- Table open, chips going down
    SPINNING = "spinning",      -- No more bets - wheel is turning
    SETTLEMENT = "settlement",
}

-- European wheel pocket order (clockwise from the top)
RS.WHEEL = {
    0, 32, 15, 19, 4, 21, 2, 25, 17, 34, 6, 27, 13, 36, 11, 30, 8, 23, 10,
    5, 24, 16, 33, 1, 20, 14, 31, 9, 22, 18, 29, 7, 28, 12, 35, 3, 26,
}

RS.RED = {
    [1] = true, [3] = true, [5] = true, [7] = true, [9] = true, [12] = true,
    [14] = true, [16] = true, [18] = true, [19] = true, [21] = true, [23] = true,
    [25] = true, [27] = true, [30] = true, [32] = true, [34] = true, [36] = true,
}

-- Chip denominations the host can pick from
RS.CHIP_STEPS = { 1, 5, 10, 25, 50, 100 }

-- Seconds the wheel animation runs; settlement fires when it ends.
-- Shared by the multiplayer timer and the UI choreography.
RS.SPIN_SECONDS = 9

-- Payout (to 1) per bet key. Numbers are "n0".."n36".
-- Red/black pay 2:1 (not the real-casino 1:1): with stakes settled as a net
-- figure after the round, an even-money win read like a push, so the house
-- here is generous to keep the colours worth betting.
local OUTSIDE_PAYOUT = {
    red = 2, black = 2, odd = 1, even = 1, low = 1, high = 1,
    d1 = 2, d2 = 2, d3 = 2,
    c1 = 2, c2 = 2, c3 = 2,
}

function RS:IsValidBetKey(key)
    if OUTSIDE_PAYOUT[key] then return true end
    local n = key:match("^n(%d+)$")
    n = n and tonumber(n)
    return n ~= nil and n >= 0 and n <= 36
end

function RS:PayoutFor(key)
    if OUTSIDE_PAYOUT[key] then return OUTSIDE_PAYOUT[key] end
    return 35
end

-- Does this bet key win when `num` comes up?
function RS:IsWinningKey(key, num)
    local n = key:match("^n(%d+)$")
    if n then return tonumber(n) == num end
    if num == 0 then return false end  -- zero sinks every outside bet
    if key == "red" then return RS.RED[num] == true end
    if key == "black" then return RS.RED[num] ~= true end
    if key == "odd" then return num % 2 == 1 end
    if key == "even" then return num % 2 == 0 end
    if key == "low" then return num <= 18 end
    if key == "high" then return num >= 19 end
    if key == "d1" then return num <= 12 end
    if key == "d2" then return num >= 13 and num <= 24 end
    if key == "d3" then return num >= 25 end
    if key == "c1" then return num % 3 == 1 end
    if key == "c2" then return num % 3 == 2 end
    if key == "c3" then return num % 3 == 0 end
    return false
end

-- Human label for a bet key (settlement text, tooltips)
function RS:BetLabel(key)
    local n = key:match("^n(%d+)$")
    if n then return "#" .. n end
    local labels = {
        red = "Red", black = "Black", odd = "Odd", even = "Even",
        low = "1-18", high = "19-36",
        d1 = "1st 12", d2 = "2nd 12", d3 = "3rd 12",
        c1 = "Col 1", c2 = "Col 2", c3 = "Col 3",
    }
    return labels[key] or key
end

-- Display color code for a number
function RS:NumberColor(num)
    if num == 0 then return "|cff33cc33" end
    return RS.RED[num] and "|cffff4444" or "|cffdddddd"
end

-- Reset state
function RS:Reset()
    self.phase = self.PHASE.IDLE
    self.hostName = nil
    self.chip = 0
    self.maxBets = 5           -- chips allowed per player (host's choice)
    self.players = {}          -- players[name] = { bets = { [key] = amount } }
    self.playerOrder = {}
    self.spinSeed = nil
    self.winningNumber = nil
    self.settlements = nil     -- settlements[name] = net after a spin
    self.recentNumbers = {}    -- marquee: last 10 results at this table
    self.roundsPlayed = 0
end

RS:Reset()

-- Host opens the table (host is the bank and does not bet).
-- maxBets is the per-player chip allotment, derby-style.
function RS:HostGame(hostName, chip, maxBets)
    self:Reset()
    self.phase = self.PHASE.BETTING
    self.hostName = hostName
    self.chip = chip

    maxBets = tonumber(maxBets) or 5
    if maxBets < 1 then maxBets = 1 elseif maxBets > 15 then maxBets = 15 end
    self.maxBets = maxBets

    BJ:Debug("Roulette hosted by " .. hostName .. " at " .. chip .. "g a chip, " .. maxBets .. " chips max")
    return true
end

function RS:AddPlayer(playerName)
    if self.phase ~= self.PHASE.BETTING then
        return false, "Cannot join - no betting round open"
    end
    if playerName == self.hostName then
        return false, "The bank cannot bet"
    end
    if self.players[playerName] then
        return false, "Already joined"
    end

    self.players[playerName] = { bets = {} }
    table.insert(self.playerOrder, playerName)
    return true
end

function RS:RemovePlayer(playerName)
    if not self.players[playerName] then return false end
    self.players[playerName] = nil
    for i, name in ipairs(self.playerOrder) do
        if name == playerName then
            table.remove(self.playerOrder, i)
            break
        end
    end
    return true
end

-- Set a player's TOTAL stake on one bet key (0 clears it). Everyone
-- applies these identically from group broadcasts, derby-style.
function RS:SetBet(playerName, key, amount)
    if self.phase ~= self.PHASE.BETTING then
        return false, "Betting is closed"
    end
    local player = self.players[playerName]
    if not player then return false, "Not at the table" end
    if not self:IsValidBetKey(key) then return false, "Bad bet" end

    amount = tonumber(amount) or 0

    -- Respect the host's per-player allotment (counted in chips)
    local cur = player.bets[key] or 0
    if amount > cur and self.chip > 0 then
        local newTotal = self:TotalStaked(playerName) - cur + amount
        if newTotal > self.maxBets * self.chip then
            return false, "All " .. self.maxBets .. " of your chips are placed. Right-click a spot to take one back."
        end
    end

    player.bets[key] = (amount > 0) and amount or nil
    return true
end

-- Chips a player has on the board
function RS:ChipsUsed(playerName)
    if not self.chip or self.chip <= 0 then return 0 end
    return math.floor(self:TotalStaked(playerName) / self.chip + 0.5)
end

function RS:TotalStaked(playerName)
    local player = self.players[playerName]
    if not player then return 0 end
    local t = 0
    for _, amt in pairs(player.bets) do t = t + amt end
    return t
end

function RS:AnyBets()
    for _, name in ipairs(self.playerOrder) do
        if self:TotalStaked(name) > 0 then return true end
    end
    return false
end

-- Deterministic pocket from a seed (portable LCG, exact in doubles)
function RS:NumberFromSeed(seed)
    local state = seed % 4294967296
    if state == 0 then state = 2654435769 end
    for _ = 1, 3 do
        state = (1664525 * state + 1013904223) % 4294967296
    end
    return self.WHEEL[(state % 37) + 1]
end

-- No more bets - lock the board and compute the result
function RS:Spin(seed)
    if self.phase ~= self.PHASE.BETTING then
        return false, "Not in a betting round"
    end
    seed = tonumber(seed)
    if not seed then return false, "Bad seed" end

    self.phase = self.PHASE.SPINNING
    self.spinSeed = seed
    self.winningNumber = self:NumberFromSeed(seed)

    BJ:Debug("Roulette spin: seed " .. seed .. " -> " .. self.winningNumber)
    return true
end

-- Wheel stopped: settle every bet against the winning number
function RS:FinishSpin()
    if self.phase ~= self.PHASE.SPINNING then return false end

    local num = self.winningNumber
    self.settlements = {}
    for _, name in ipairs(self.playerOrder) do
        local net = 0
        for key, amount in pairs(self.players[name].bets) do
            if self:IsWinningKey(key, num) then
                net = net + amount * self:PayoutFor(key)
            else
                net = net - amount
            end
        end
        self.settlements[name] = net
    end

    self.phase = self.PHASE.SETTLEMENT
    self.roundsPlayed = self.roundsPlayed + 1

    -- Marquee: newest result on top, last 10 kept
    table.insert(self.recentNumbers, 1, num)
    while #self.recentNumbers > 10 do
        table.remove(self.recentNumbers)
    end

    -- Host records leaderboard results for the group
    if BJ.Leaderboard then
        local myName = UnitName("player")
        if not self.hostName or self.hostName == myName then
            for name, net in pairs(self.settlements) do
                if net > 0 then
                    BJ.Leaderboard:RecordHandResult("roulette", name, net, "win")
                elseif net < 0 then
                    BJ.Leaderboard:RecordHandResult("roulette", name, net, "lose")
                end
            end

            -- Session debt ledger: bettors settle against the host (the bank)
            if BJ.DebtLedger and self.hostName then
                local debts = {}
                for name, net in pairs(self.settlements) do
                    if name ~= self.hostName and net ~= 0 then
                        if net > 0 then
                            table.insert(debts, { debtor = self.hostName, creditor = name, amount = net })
                        else
                            table.insert(debts, { debtor = name, creditor = self.hostName, amount = -net })
                        end
                    end
                end
                -- Fun/real status fixed at table open: a mid-game toggle
                -- flip only affects the next hosted table
                BJ.DebtLedger:RecordDebts("roulette", debts, self.fakePlay)
            end
        end
    end

    self:SaveToHistory()
    return true
end

-- Clear bets and open the next betting round at the same table
function RS:NextRound()
    if self.phase ~= self.PHASE.SETTLEMENT then
        return false, "No finished round to continue from"
    end
    for _, name in ipairs(self.playerOrder) do
        self.players[name].bets = {}
    end
    self.spinSeed = nil
    self.winningNumber = nil
    self.settlements = nil
    self.phase = self.PHASE.BETTING
    return true
end

-- Settlement text for the result banner
function RS:GetSettlementText()
    if not self.winningNumber then return "No result" end
    local lines = {
        string.format("The ball lands on %s%d|r!", self:NumberColor(self.winningNumber), self.winningNumber),
    }
    local any = false
    for _, name in ipairs(self.playerOrder) do
        local net = self.settlements and self.settlements[name]
        if net and net > 0 then
            table.insert(lines, "|cff00ff00" .. name .. "|r collects |cffffd700" .. net .. "g|r from " .. (self.hostName or "the bank"))
            any = true
        elseif net and net < 0 then
            table.insert(lines, "|cffff4444" .. name .. "|r owes " .. (self.hostName or "the bank") .. " |cffffd700" .. (-net) .. "g|r")
            any = true
        end
    end
    if not any then
        table.insert(lines, "No bets settled - the house yawns.")
    end
    return table.concat(lines, "\n")
end

--[[
    GAME HISTORY
]]
RS.gameHistory = {}
RS.MAX_HISTORY = 5

function RS:SaveToHistory()
    if not self.winningNumber then return end

    local hostNet = 0
    for _, net in pairs(self.settlements or {}) do
        hostNet = hostNet - net
    end

    local game = {
        timestamp = time(),
        host = self.hostName,
        chip = self.chip,
        number = self.winningNumber,
        numPlayers = #self.playerOrder,
        hostNet = hostNet,
    }

    BJ.GameHistory:Add(self.gameHistory, game, self.MAX_HISTORY)
    self:SaveHistoryToDB()
end

function RS:SaveHistoryToDB()
    BJ.GameHistory:Save("rouletteHistory", self.gameHistory)
end

function RS:LoadHistoryFromDB()
    local history = BJ.GameHistory:Load("rouletteHistory")
    if history then
        self.gameHistory = history
        BJ:Debug("Loaded " .. #self.gameHistory .. " roulette rounds from history")
    end
end

function RS:GetGameLogText()
    if #self.gameHistory == 0 then
        return "No game history yet."
    end

    local lines = {}
    for gameNum, game in ipairs(self.gameHistory) do
        table.insert(lines, "|cffffd700=== Round " .. gameNum .. " ===|r")
        table.insert(lines, (game.host or "?") .. " spun " .. self:NumberColor(game.number or 0) ..
            (game.number or "?") .. "|r | " .. (game.numPlayers or 0) .. " players | chip " .. (game.chip or 0) .. "g")
        local net = game.hostNet or 0
        table.insert(lines, "  house " .. (net >= 0 and ("|cff00ff00+" .. net) or ("|cffff4444" .. net)) .. "g|r")
        table.insert(lines, "")
    end
    return table.concat(lines, "\n")
end
