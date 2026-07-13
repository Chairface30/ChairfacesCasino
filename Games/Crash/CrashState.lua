--[[
    Chairface's Casino - CrashState.lua
    Crash game state (pure logic, no networking)

    THE GAME OF CHICKEN. Every rider antes into a POT. The zeppelin WILL
    explode - the only question is when. Jump too early and someone
    braver outlasts you; ride too long and you go down with the ship.
    The last rider to parachute out before the explosion takes the pot.

    Game flow:
    1. Host opens the table and sets the ante; the host is the pilot and
       does not ride (they know the fate; except in test mode)
    2. Players board by anteing into the pot, optionally with an
       auto-jump target
    3. Host launches: a COMMIT (hash of a secret only the host holds)
       goes out and the flight starts. crashPoint = f(secret), so the
       host cannot change it mid-flight (the hash is on record) and the
       riders cannot predict it (the secret stays hidden until the
       reveal, when every client verifies it).
    4. The distance climbs on a fixed curve of 0.5s ticks. Riders jump
       manually (host-receipt-time authoritative) or their auto target
       fires deterministically on every client at the same tick.
    5. The zeppelin explodes at the crash point - guaranteed, at the
       1000m cap at the latest. Everyone still aboard loses their ante.
       Among the jumpers, the LAST tick out wins the whole pot (ties on
       the tick split it). If nobody jumped, the antes push back.

    The math: after the climb-out the explosion odds are a constant
    HAZARD per tick (memoryless - the elapsed flight tells you nothing),
    so the average flight runs far longer than the old banked game and
    every extra tick aboard is the same pure nerve.
]]

local BJ = ChairfacesCasino
BJ.CrashState = {}
local CS = BJ.CrashState

CS.PHASE = {
    IDLE = "idle",
    BOARDING = "boarding",      -- Table open, riders anteing
    LAUNCHING = "launching",    -- Boarding closed; commit out, waiting on the entropy /roll
    FLIGHT = "flight",          -- Multiplier climbing
    SETTLEMENT = "settlement",  -- Crashed and revealed
}

CS.HAZARD = 0.012               -- base explosion odds per tick past the climb-out
CS.HAZARD_RAMP = 0.0006         -- extra odds per tick of altitude: the higher she
                                -- flies the twitchier she gets, so flights die
                                -- erratically low-mid, ~8% reach 600m, and the
                                -- 1000m cap is a ~0.1% jackpot spectacle
CS.MAX_MULT = 100               -- the 1000m cap: she explodes HERE at the latest
CS.TICK_SECONDS = 0.5           -- coarse ticks so message latency rarely matters
CS.GROWTH = 1.035               -- distance curve per tick past the climb-out
CS.RAMP_TICKS = 10              -- the climb-out: 0m -> 100m over these ticks (5s)

-- First tick past the max multiplier plus grace: a client still in FLIGHT
-- beyond this many ticks never got the CRASH message - void locally.
-- (the cap tick is RAMP_TICKS + 134 = 144; ~23 ticks of grace on top)
CS.WATCHDOG_TICKS = 167

--[[
    PROVABLY-FAIR MATH
    All arithmetic stays under 2^53 so every client computes identical
    values in Lua doubles (same requirement as CardLib's PRNG).
]]

-- Deterministic 32-bit string hash (multiplier 31 keeps products exact)
function CS:HashString(s)
    local h = 5381
    for i = 1, #s do
        h = (h * 31 + s:byte(i)) % 4294967296
    end
    return h
end

-- Combined round seed from the host's secret and the public /roll
function CS:SeedFrom(secret, roll)
    return self:HashString(secret .. ":" .. tostring(roll))
end

-- Crash point from a seed. The explosion never lands during the climb-out;
-- past it, tick t survives with probability (1 - HAZARD - HAZARD_RAMP*t):
-- a RISING hazard, so most flights die erratically in the low-mid range,
-- ~8% clear 600m and the 1000m cap is a once-in-a-thousand spectacle
-- (median ~310m). Deterministic walk of the survival product, so every
-- up-to-date client reconstructs the identical crash point - changing
-- these numbers breaks crash-table consistency with older sub-versions.
-- There is no fly-away and no house: the pot game needs no edge.
function CS:CrashPointFromSeed(seed)
    local state = seed % 4294967296
    if state == 0 then state = 2654435769 end
    for _ = 1, 3 do
        state = (1664525 * state + 1013904223) % 4294967296
    end
    local u = (state + 1) / 4294967296          -- uniform in (0, 1]
    local lnU = math.log(u)
    local lnSurvive = 0
    local survived = 0
    while survived < 400 do
        local h = self.HAZARD + self.HAZARD_RAMP * survived
        if h > 0.5 then h = 0.5 end
        lnSurvive = lnSurvive + math.log(1 - h)
        if lnSurvive < lnU then break end
        survived = survived + 1
    end
    local point = self:MultiplierAt(self.RAMP_TICKS + survived)
    if point > self.MAX_MULT then point = self.MAX_MULT end
    return point
end

-- Multiplier shown at a given tick (2 decimals, monotonic): a linear
-- climb-out from x0.00 to x1.00 over RAMP_TICKS, then the growth curve.
function CS:MultiplierAt(tick)
    if tick < 0 then tick = 0 end
    local m
    if tick < self.RAMP_TICKS then
        m = tick / self.RAMP_TICKS
    else
        m = self.GROWTH ^ (tick - self.RAMP_TICKS)
    end
    m = math.floor(100 * m) / 100
    if m > self.MAX_MULT then m = self.MAX_MULT end
    return m
end

-- First tick whose multiplier reaches the crash point - the explosion tick.
-- A bail-out only pays if it lands on an earlier tick.
function CS:CrashTickFor(crashPoint)
    for t = 0, 200 do
        if self:MultiplierAt(t) >= crashPoint then return t end
    end
    return 200
end

-- First tick that reaches an auto-bail target (nil if never)
function CS:TargetTickFor(target)
    for t = 0, 200 do
        if self:MultiplierAt(t) >= target then return t end
    end
    return nil
end

--[[
    STATE
]]

function CS:Reset()
    self.phase = self.PHASE.IDLE
    self.hostName = nil
    self.ante = 0
    self.players = {}          -- players[name] = { target=n|nil, cashedOut={mult,tick}|nil, refunded=bool }
    self.playerOrder = {}
    self.commit = nil          -- host's hash commitment (everyone)
    self.secret = nil          -- host only, until the reveal
    self.entropyRoll = nil     -- the public /roll result
    self.seed = nil
    self.crashPoint = nil      -- known to host at launch; to everyone at reveal
    self.crashTick = nil
    self.flightStart = nil     -- local GetTime() when the flight began
    self.settlements = nil     -- settlements[name] = net gold after the round
    self.pot = nil             -- total antes staked this flight
    self.winners = nil         -- last tick out: the pot takers (ties split)
    self.verifyFailed = false
    self.recentCrashes = self.recentCrashes or {}   -- marquee survives rounds
    self.roundsPlayed = self.roundsPlayed or 0
end

CS:Reset()
CS.recentCrashes = {}
CS.roundsPlayed = 0

-- Host opens the table. Host is the bank and does not ride.
function CS:HostGame(hostName, ante)
    self:Reset()
    self.phase = self.PHASE.BOARDING
    self.hostName = hostName
    self.ante = tonumber(ante) or 0
    BJ:Debug("Crash hosted by " .. hostName .. " at " .. self.ante .. "g a seat")
    return true
end

-- A rider boards (antes). target is an optional auto-bail multiplier.
function CS:AddPlayer(playerName, target)
    if self.phase ~= self.PHASE.BOARDING then
        return false, "Boarding is closed"
    end
    -- The pilot rides too (the fate exists on their machine either way;
    -- the addon never shows it - a trust convention, like fake play).
    if self.players[playerName] then
        return false, "Already aboard"
    end

    self.players[playerName] = { target = self:CleanTarget(target) }
    table.insert(self.playerOrder, playerName)
    return true
end

function CS:RemovePlayer(playerName)
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

-- Normalize an auto-bail target: 1.01 .. MAX_MULT, 2 decimals, nil = manual
function CS:CleanTarget(target)
    target = tonumber(target)
    if not target or target <= 1 then return nil end
    if target > self.MAX_MULT then target = self.MAX_MULT end
    return math.floor(target * 100) / 100
end

function CS:SetTarget(playerName, target)
    if self.phase ~= self.PHASE.BOARDING then
        return false, "Targets lock at launch"
    end
    local p = self.players[playerName]
    if not p then return false, "Not aboard" end
    p.target = self:CleanTarget(target)
    return true
end

function CS:RiderCount()
    return #self.playerOrder
end

--[[
    ROUND FLOW
]]

-- Boarding closes; the host's commitment is on record. Waiting on the roll.
function CS:BeginLaunch(commit)
    if self.phase ~= self.PHASE.BOARDING then
        return false, "Not boarding"
    end
    self.phase = self.PHASE.LAUNCHING
    self.commit = tonumber(commit)
    return true
end

-- The entropy /roll landed; the flight begins NOW (local clock).
function CS:StartFlight(roll)
    if self.phase ~= self.PHASE.LAUNCHING then
        return false, "Not launching"
    end
    self.entropyRoll = tonumber(roll)
    self.phase = self.PHASE.FLIGHT
    self.flightStart = GetTime()
    return true
end

-- Host only, at flight start: compute where this flight ends.
function CS:ComputeCrash(secret, roll)
    local seed = self:SeedFrom(secret, roll)
    local point = self:CrashPointFromSeed(seed)
    return seed, point, self:CrashTickFor(point)
end

function CS:CurrentTick()
    if not self.flightStart then return 0 end
    return math.floor((GetTime() - self.flightStart) / self.TICK_SECONDS)
end

function CS:CurrentMultiplier()
    return self:MultiplierAt(self:CurrentTick())
end

-- Record a bail-out (host-confirmed manual, or deterministic auto).
-- If the player's auto target already fired by `tick`, the auto result
-- wins - so a manual click racing its own auto target converges to the
-- same numbers on every client.
function CS:CashOut(playerName, mult, tick)
    local p = self.players[playerName]
    if not p or p.cashedOut or p.refunded then return false end
    if p.target then
        local tt = self:TargetTickFor(p.target)
        if tt and tt <= tick then
            -- auto pays the multiplier at the tick it fires (not the bare
            -- target) - the same as a manual bail that instant. With coarse
            -- ticks this is what keeps every strategy's EV at (1-edge).
            mult, tick = self:MultiplierAt(tt), tt
        end
    end
    p.cashedOut = { mult = mult, tick = tick }
    return true
end

-- Void a rider's ante (round-void flows only). NEVER used for a mid-flight
-- disconnect anymore: in the pot game a refund (0) beats losing the ante,
-- so pulling the cable would be a free escape hatch. A vanished rider
-- stays aboard and rides her into the ground like anyone else who
-- doesn't jump (their auto-jump target still fires and can still win).
function CS:Refund(playerName)
    local p = self.players[playerName]
    if not p or p.cashedOut or p.refunded then return false end
    p.refunded = true
    return true
end

-- Deterministic auto-bails: every client applies the same targets at the
-- same ticks, no messages needed. Called each render tick during FLIGHT.
function CS:ApplyAutoCashouts(currentTick)
    local fired = {}
    for _, name in ipairs(self.playerOrder) do
        local p = self.players[name]
        if p and p.target and not p.cashedOut and not p.refunded then
            local tt = self:TargetTickFor(p.target)
            if tt and tt <= currentTick then
                -- pays the tick's multiplier (CashOut corrects to it)
                if self:CashOut(name, self:MultiplierAt(tt), tt) then
                    fired[#fired + 1] = name
                end
            end
        end
    end
    return fired
end

-- The explosion. Verifies the reveal (clients), rolls back any bail-out
-- the crash actually beat, and settles every seat. Also accepted from
-- BOARDING so a client that missed both LAUNCH and START still settles
-- (verification is skipped without a commit; auto targets still apply).
function CS:Crash(secret, roll)
    if self.phase ~= self.PHASE.FLIGHT and self.phase ~= self.PHASE.LAUNCHING
        and self.phase ~= self.PHASE.BOARDING then
        return false, "No flight to crash"
    end

    roll = tonumber(roll) or self.entropyRoll
    self.secret = secret
    self.verifyFailed = false
    if self.commit and self:HashString(secret) ~= self.commit then
        self.verifyFailed = true
    end

    local seed, point, tick = self:ComputeCrash(secret, roll or 0)
    self.seed = seed
    self.crashPoint = point
    self.crashTick = tick

    -- Auto targets the crash beat (target tick >= crash tick) never fired;
    -- a jump recorded at-or-past the crash tick is undone. Ties lose:
    -- the zeppelin explodes with your hand on the ripcord.
    for _, name in ipairs(self.playerOrder) do
        local p = self.players[name]
        if p.cashedOut and p.cashedOut.tick >= tick then
            p.cashedOut = nil
        end
    end

    -- ... and auto targets the crash did NOT beat are applied here, so a
    -- client that missed the START message still settles identically.
    for _, name in ipairs(self.playerOrder) do
        local p = self.players[name]
        if p.target and not p.cashedOut and not p.refunded then
            local tt = self:TargetTickFor(p.target)
            if tt and tt < tick then
                p.cashedOut = { mult = self:MultiplierAt(tt), tick = tt }
            end
        end
    end

    -- THE CHICKEN SETTLEMENT: every live ante is in the pot, and the last
    -- tick out of the ship takes it all (ties on the tick split it, odd
    -- gold to the earliest seat). Everyone else - early jumpers and the
    -- riders who went down - loses their ante. If NOBODY jumped, there is
    -- no one to pay: the antes push back.
    self.pot = 0
    local lastTick = nil
    for _, name in ipairs(self.playerOrder) do
        local p = self.players[name]
        if not p.refunded then
            self.pot = self.pot + self.ante
            if p.cashedOut and (not lastTick or p.cashedOut.tick > lastTick) then
                lastTick = p.cashedOut.tick
            end
        end
    end

    self.winners = {}
    if lastTick then
        for _, name in ipairs(self.playerOrder) do
            local p = self.players[name]
            if not p.refunded and p.cashedOut and p.cashedOut.tick == lastTick then
                table.insert(self.winners, name)
            end
        end
    end

    self.settlements = {}
    local isWinner = {}
    for _, w in ipairs(self.winners) do isWinner[w] = true end
    local numWinners = #self.winners
    local share = numWinners > 0 and math.floor(self.pot / numWinners) or 0
    local remainder = numWinners > 0 and (self.pot - share * numWinners) or 0
    for _, name in ipairs(self.playerOrder) do
        local p = self.players[name]
        local net
        if p.refunded then
            net = 0
        elseif numWinners == 0 then
            net = 0                     -- nobody jumped: push
        elseif isWinner[name] then
            net = share - self.ante
            if remainder > 0 then
                net = net + remainder
                remainder = 0
            end
        else
            net = -self.ante
        end
        self.settlements[name] = net
    end

    self.phase = self.PHASE.SETTLEMENT
    self.roundsPlayed = self.roundsPlayed + 1

    table.insert(self.recentCrashes, 1, point)
    while #self.recentCrashes > 10 do
        table.remove(self.recentCrashes)
    end

    -- Host records leaderboard results for the group
    if BJ.Leaderboard then
        local myName = UnitName("player")
        if not self.hostName or self.hostName == myName then
            for name, net in pairs(self.settlements) do
                if net > 0 then
                    BJ.Leaderboard:RecordHandResult("crash", name, net, "win")
                elseif net < 0 then
                    BJ.Leaderboard:RecordHandResult("crash", name, net, "lose")
                end
            end

            -- Session debt ledger: the pot is zero-sum among the riders,
            -- so losers pay the winner(s) directly - the pilot banks nothing.
            -- Fun/real status fixed at table open: a mid-game toggle flip
            -- only affects the next hosted table
            if BJ.DebtLedger then
                BJ.DebtLedger:RecordNets("crash", self.settlements, self.fakePlay)
            end
        end
    end

    self:SaveToHistory()
    return true
end

-- Same table, next flight
function CS:NextRound()
    if self.phase ~= self.PHASE.SETTLEMENT then
        return false, "No finished round to continue from"
    end
    self.players = {}
    self.playerOrder = {}
    self.commit = nil
    self.secret = nil
    self.entropyRoll = nil
    self.seed = nil
    self.crashPoint = nil
    self.crashTick = nil
    self.flightStart = nil
    self.settlements = nil
    self.pot = nil
    self.winners = nil
    self.verifyFailed = false
    self.phase = self.PHASE.BOARDING
    return true
end

-- The round cannot finish (host lost the secret to a reload, or vanished):
-- all antes void, back to boarding if the table survives.
function CS:VoidRound(backToBoarding)
    self.players = {}
    self.playerOrder = {}
    self.commit = nil
    self.secret = nil
    self.entropyRoll = nil
    self.seed = nil
    self.crashPoint = nil
    self.crashTick = nil
    self.flightStart = nil
    self.settlements = nil
    self.pot = nil
    self.winners = nil
    self.verifyFailed = false
    self.phase = backToBoarding and self.PHASE.BOARDING or self.PHASE.IDLE
    return true
end

--[[
    DISPLAY HELPERS
]]

-- The flight reads as distance: the climb-out is the first 100m, the
-- log-scale run to the cap lands exactly at 1000m (where she blows for sure).
function CS:MetersFor(mult)
    if not mult or mult <= 0 then return 0 end
    local m
    if mult <= 1 then
        m = 100 * mult
    else
        m = 100 + 900 * (math.log(mult) / math.log(self.MAX_MULT))
    end
    if m > 1000 then m = 1000 end
    return math.floor(m + 0.5)
end

-- Inverse of MetersFor: the multiplier whose odometer reads `m` meters
-- (UI convenience so auto-jump targets can be typed as a distance)
function CS:MultForMeters(m)
    m = tonumber(m)
    if not m or m <= 0 then return nil end
    if m > 1000 then m = 1000 end
    if m <= 100 then
        return m / 100
    end
    return self.MAX_MULT ^ ((m - 100) / 900)
end

function CS:CrashColor(point)
    if not point then return "|cffdddddd" end
    if point < 2 then return "|cffff4444" end
    if point < 6 then return "|cffffd700" end
    return "|cff00ff00"
end

function CS:GetSettlementText()
    if not self.crashPoint then return "No result" end
    local lines = {}
    if self.flyAway then
        -- everyone jumped: she sails off - nobody sees where she comes down
        table.insert(lines, "Everyone jumped! She sails off into the night - nobody sees where she comes down.")
    else
        table.insert(lines, string.format("The zeppelin explodes at %s%dm|r!",
            self:CrashColor(self.crashPoint), self:MetersFor(self.crashPoint)))
    end
    if self.verifyFailed then
        table.insert(lines, "|cffff4444WARNING: the host's reveal FAILED verification! Do not settle this round.|r")
    end

    if #self.playerOrder == 0 then
        table.insert(lines, "Nobody was aboard - the fireworks were free.")
        return table.concat(lines, "\n")
    end

    local numWinners = self.winners and #self.winners or 0
    if numWinners == 0 then
        table.insert(lines, "|cffffff00Nobody jumped - the whole table rode her into the ground. Antes push.|r")
        return table.concat(lines, "\n")
    end

    local isWinner = {}
    for _, w in ipairs(self.winners) do isWinner[w] = true end
    for _, name in ipairs(self.playerOrder) do
        local p = self.players[name]
        local net = self.settlements and self.settlements[name]
        if p and p.refunded then
            table.insert(lines, "|cff888888" .. name .. "|r - ante voided, owes nothing")
        elseif isWinner[name] then
            local takes = numWinners > 1 and "splits the pot" or "takes the pot"
            table.insert(lines, "|cff00ff00" .. name .. "|r " .. takes .. ": |cffffd700+" ..
                (net or 0) .. "g|r (last out at " .. self:MetersFor(p.cashedOut.mult) .. "m)")
        elseif p and p.cashedOut then
            table.insert(lines, "|cffff4444" .. name .. "|r loses the ante |cffff4444" ..
                (net and -net or self.ante) .. "g|r (jumped too early at " ..
                self:MetersFor(p.cashedOut.mult) .. "m)")
        else
            table.insert(lines, "|cffff4444" .. name .. "|r loses the ante |cffff4444" ..
                (net and -net or self.ante) .. "g|r (went down with the ship)")
        end
    end
    table.insert(lines, "|cff888888Losers pay the winner by hand - the tab is on /cc debts.|r")
    return table.concat(lines, "\n")
end

--[[
    GAME HISTORY
]]
CS.gameHistory = {}
CS.MAX_HISTORY = 5

function CS:SaveToHistory()
    if not self.crashPoint then return end

    local riders = {}
    for _, name in ipairs(self.playerOrder) do
        local p = self.players[name]
        riders[#riders + 1] = {
            name = name,
            net = self.settlements and self.settlements[name] or 0,
            bailedAt = p and p.cashedOut and p.cashedOut.mult or nil,
            refunded = p and p.refunded or nil,
        }
    end

    local game = {
        timestamp = time(),
        host = self.hostName,
        ante = self.ante,
        crashPoint = self.crashPoint,
        numPlayers = #self.playerOrder,
        pot = self.pot,
        winners = self.winners,
        riders = riders,
    }

    BJ.GameHistory:Add(self.gameHistory, game, self.MAX_HISTORY)
    self:SaveHistoryToDB()
end

function CS:SaveHistoryToDB()
    BJ.GameHistory:Save("crashHistory", self.gameHistory)
end

function CS:LoadHistoryFromDB()
    local history = BJ.GameHistory:Load("crashHistory")
    if history then
        self.gameHistory = history
        BJ:Debug("Loaded " .. #self.gameHistory .. " crash rounds from history")
    end
end

function CS:GetGameLogText()
    if #self.gameHistory == 0 then
        return "No flight history yet."
    end

    local lines = {}
    for gameNum, game in ipairs(self.gameHistory) do
        table.insert(lines, "|cffffd700=== Flight " .. gameNum .. " ===|r")
        table.insert(lines, (game.host or "?") .. " piloted to " .. self:CrashColor(game.crashPoint) ..
            self:MetersFor(game.crashPoint) .. "m|r | " .. (game.numPlayers or 0) ..
            " riders | pot " .. (game.pot or ((game.ante or 0) * (game.numPlayers or 0))) .. "g")
        for _, r in ipairs(game.riders or {}) do
            local netStr = (r.net or 0) >= 0 and ("|cff00ff00+" .. (r.net or 0)) or ("|cffff4444" .. r.net)
            if r.refunded then
                table.insert(lines, "  |cff888888" .. r.name .. " - voided|r")
            elseif r.bailedAt then
                table.insert(lines, "  " .. r.name .. " jumped at " .. self:MetersFor(r.bailedAt) ..
                    "m " .. netStr .. "g|r")
            else
                table.insert(lines, "  " .. r.name .. " went down " .. netStr .. "g|r")
            end
        end
        -- pre-pot-rework entries carried the old bank's net; show it so
        -- saved history still reads right after the update
        if game.hostNet and not game.pot then
            local net = game.hostNet
            table.insert(lines, "  house " .. (net >= 0 and ("|cff00ff00+" .. net) or ("|cffff4444" .. net)) .. "g|r")
        end
        table.insert(lines, "")
    end
    return table.concat(lines, "\n")
end
