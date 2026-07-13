--[[
    Chairface's Casino - LiarsDiceState.lua
    Liar's Dice (Common Hand / Perudo-style) game state.

    Game flow:
    1. Host opens a table with a stake and the "ones wild" option; players
       join the lobby (each starts with 5 dice).
    2. Host starts the match. Every round the host generates a private
       roundSeed and derives each player's dice deterministically from
       (roundSeed, playerName, roundNum). Only the owner is told their dice
       (whispered by the multiplayer layer), so nobody can see anyone else's.
    3. Players take turns raising the bid ("three 5s") or calling "Liar!".
       A raise must beat the standing bid: more dice, or the same count of a
       higher face.
    4. On a challenge the host reveals the roundSeed and everyone's dice, so
       all clients re-derive and verify. The actual count of the bid face
       (plus every 1 when ones are wild) is compared to the bid: if the bid
       holds the challenger loses a die, otherwise the bidder does.
    5. A player at 0 dice is eliminated. Last player standing wins the pooled
       stake from everyone else.

    The host is the dealer (it knows every hand), exactly like the seeded
    card games. Revealing the roundSeed at showdown lets each player verify
    the dice they were dealt were honest.
]]

local BJ = ChairfacesCasino
BJ.LiarsDiceState = {}
local LD = BJ.LiarsDiceState

-- Constants
LD.MAX_PLAYERS = 8
LD.START_DICE = 3        -- default dice each player starts with
LD.MAX_START_DICE = 5    -- host can bump the table up to this many
LD.DICE_FACES = 6

-- Game phases
LD.PHASE = {
    IDLE = "idle",
    LOBBY = "lobby",           -- Waiting for players to join
    BIDDING = "bidding",       -- Players raising / calling
    REVEAL = "reveal",         -- Showing a resolved challenge
    SETTLEMENT = "settlement", -- Match over, someone won
}

-- Reset state
function LD:Reset()
    self.phase = self.PHASE.IDLE
    self.hostName = nil
    self.stake = 0
    self.onesWild = true
    self.startDice = self.START_DICE  -- dice each player starts with this match
    self.players = {}          -- [name] = { count, alive, dice }
    self.playerOrder = {}      -- fixed join order (indices stay stable)
    self.roundNum = 0
    self.roundSeed = nil       -- host-only during a round
    self.allDice = nil         -- host-only: [name] = { d, d, ... }
    self.myDice = nil          -- this client's own dice for the round
    self.myDiceRound = 0       -- which round self.myDice belongs to
    self.currentBid = nil      -- { q, face, by } or nil (no bid yet)
    self.currentBidderIndex = 0
    self.firstBidder = nil     -- who opens the current round's bidding
    self.bidLog = {}           -- this round's bids, for display
    self.lastLoser = nil       -- who lost the previous challenge
    self.reveal = nil          -- { dice, face, count, wild, bidQ, bidFace,
                               --   loser, bidder, challenger, onesWild }
    self.winner = nil
end

LD:Reset()

--[[
    HIDDEN DICE DERIVATION
    Deterministic from (seed, playerName, roundNum). The host derives every
    player's dice; the seed is revealed at showdown so anyone can re-derive
    and verify. Must stay byte-identical across versions/clients.
]]
function LD:DeriveDice(seed, playerName, roundNum, count)
    local nameHash = 0
    for i = 1, #playerName do
        nameHash = (nameHash * 31 + string.byte(playerName, i)) % 2147483647
    end
    -- Keep every intermediate product well under 2^53 so the result is
    -- byte-identical across clients (WoW Lua uses doubles everywhere).
    local mixed = (seed + nameHash * 131 + roundNum * 977) % 2147483647 + 1
    local rng = BJ.CardLib.SeededRandom(mixed)
    local dice = {}
    for i = 1, count do
        dice[i] = math.floor(rng() * self.DICE_FACES) + 1  -- 1..6
    end
    table.sort(dice)
    return dice
end

--[[
    LOBBY
]]

function LD:HostGame(hostName, stake, onesWild, startDice)
    self:Reset()

    self.phase = self.PHASE.LOBBY
    self.hostName = hostName
    self.stake = stake
    self.onesWild = onesWild ~= false  -- default true
    -- Starting dice: default 3, host may choose up to MAX_START_DICE (5)
    startDice = tonumber(startDice) or self.START_DICE
    if startDice < 1 then startDice = self.START_DICE end
    if startDice > self.MAX_START_DICE then startDice = self.MAX_START_DICE end
    self.startDice = startDice

    -- Host plays too
    self:AddPlayer(hostName)

    BJ:Debug("Liar's Dice hosted by " .. hostName .. " for " .. stake .. "g (ones wild: " ..
        tostring(self.onesWild) .. ", start dice: " .. self.startDice .. ")")
    return true
end

function LD:AddPlayer(playerName)
    if self.phase ~= self.PHASE.LOBBY then
        return false, "Cannot join - the match has already started"
    end
    if self.players[playerName] then
        return false, "Already joined"
    end
    if #self.playerOrder >= self.MAX_PLAYERS then
        return false, "Table is full (" .. self.MAX_PLAYERS .. " players max)"
    end

    self.players[playerName] = { count = self.startDice or self.START_DICE, alive = true, dice = nil }
    table.insert(self.playerOrder, playerName)

    BJ:Debug(playerName .. " joined Liar's Dice")
    return true
end

function LD:RemovePlayer(playerName)
    if self.phase ~= self.PHASE.LOBBY then
        return false, "Cannot leave after the match starts"
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

-- A player quits mid-match and forfeits. Returns one of:
--   "removed"    - dropped during the lobby (no match under way)
--   "eliminated" - taken out mid-match, the match continues
--   "gameover"   - taken out mid-match, only one player remains
--   nil          - could not forfeit (unknown player / already out)
function LD:ForfeitPlayer(name)
    local p = self.players[name]
    if not p then return nil end
    if self.phase == self.PHASE.LOBBY then
        return self:RemovePlayer(name) and "removed" or nil
    end
    if self.phase == self.PHASE.SETTLEMENT then return nil end
    if not p.alive then return nil end

    local wasCurrent = (self:CurrentBidder() == name)
    local idx = self:IndexOf(name) or 1
    p.alive = false
    p.count = 0
    self.lastLoser = name

    if self:AliveCount() <= 1 then
        return "gameover"
    end

    -- If they were on turn, or the standing bid was theirs, pass the action to
    -- the next alive player so the round keeps flowing.
    if self.currentBid and self.currentBid.by == name then
        self.currentBid = nil
        self.currentBidderIndex = self:NextAliveIndex(idx)
    elseif wasCurrent then
        self.currentBidderIndex = self:NextAliveIndex(idx)
    end
    return "eliminated"
end

-- Count of players still holding dice
function LD:AliveCount()
    local n = 0
    for _, name in ipairs(self.playerOrder) do
        local p = self.players[name]
        if p and p.alive then n = n + 1 end
    end
    return n
end

-- Total dice on the table right now
function LD:TotalDice()
    local n = 0
    for _, name in ipairs(self.playerOrder) do
        local p = self.players[name]
        if p and p.alive then n = n + (p.count or 0) end
    end
    return n
end

-- Index (in playerOrder) of a player name, or nil
function LD:IndexOf(playerName)
    for i, name in ipairs(self.playerOrder) do
        if name == playerName then return i end
    end
    return nil
end

-- The next alive player's index after a given index (wraps around)
function LD:NextAliveIndex(fromIndex)
    local n = #self.playerOrder
    if n == 0 then return 0 end
    for step = 1, n do
        local idx = ((fromIndex - 1 + step) % n) + 1
        local p = self.players[self.playerOrder[idx]]
        if p and p.alive then return idx end
    end
    return fromIndex
end

--[[
    MATCH / ROUND FLOW
]]

-- Host validates the lobby and locks it in. First round's bidding opens
-- with the host.
function LD:StartMatch()
    if self.phase ~= self.PHASE.LOBBY then
        return false, "Not in lobby"
    end
    if #self.playerOrder < 2 then
        return false, "Need at least 2 players"
    end
    self.roundNum = 0
    self.lastLoser = nil
    self.firstBidder = self.hostName
    return true
end

-- Begin a round. On the host, seed is the private roundSeed used to derive
-- every alive player's dice. Clients call BeginRound(roundNum, nil) to reset
-- the per-round bidding state and learn their own dice via a whisper.
function LD:BeginRound(roundNum, seed)
    self.roundNum = roundNum
    self.phase = self.PHASE.BIDDING
    self.currentBid = nil
    self.bidLog = {}
    self.reveal = nil

    -- Whoever opens the bidding this round
    local firstIdx = self:IndexOf(self.firstBidder or self.hostName) or 1
    -- Make sure the opener is still alive (loser may have been eliminated)
    if not (self.players[self.playerOrder[firstIdx]]
            and self.players[self.playerOrder[firstIdx]].alive) then
        firstIdx = self:NextAliveIndex(firstIdx)
    end
    self.currentBidderIndex = firstIdx
    self.firstBidder = self.playerOrder[firstIdx]

    if seed then
        -- Host: derive everyone's dice for this round
        self.roundSeed = seed
        self.allDice = {}
        for _, name in ipairs(self.playerOrder) do
            local p = self.players[name]
            if p and p.alive and p.count > 0 then
                self.allDice[name] = self:DeriveDice(seed, name, roundNum, p.count)
            end
        end
        -- Host also knows its own hand immediately
        self.myDice = self.allDice[self.hostName]
        self.myDiceRound = roundNum
    end
end

-- Store this client's own dice (received by whisper from the host)
function LD:SetMyDice(roundNum, dice)
    self.myDice = dice
    self.myDiceRound = roundNum
end

-- Who is on turn to bid
function LD:CurrentBidder()
    return self.playerOrder[self.currentBidderIndex]
end

-- Is a bid legal given the standing bid? Returns true, or false + reason.
function LD:IsBidLegal(q, face)
    q = tonumber(q); face = tonumber(face)
    if not q or not face then return false, "Invalid bid" end
    if q < 1 then return false, "Quantity must be at least 1" end

    local minFace = self.onesWild and 2 or 1
    if face < minFace or face > self.DICE_FACES then
        if self.onesWild and face == 1 then
            return false, "Ones are wild - you cannot bid ones"
        end
        return false, "Face must be " .. minFace .. "-" .. self.DICE_FACES
    end

    if q > self:TotalDice() then
        return false, "Only " .. self:TotalDice() .. " dice are on the table"
    end

    local cur = self.currentBid
    if not cur then return true end  -- opening bid: any legal bid

    -- Must strictly exceed: more dice, or same count of a higher face
    if q > cur.q then return true end
    if q == cur.q and face > cur.face then return true end
    return false, "Bid must raise the count or the face"
end

-- Apply a validated bid (host-authoritative; everyone applies the echo)
function LD:ApplyBid(playerName, q, face)
    q = tonumber(q); face = tonumber(face)
    self.currentBid = { q = q, face = face, by = playerName }
    table.insert(self.bidLog, { by = playerName, q = q, face = face })

    -- Advance the turn to the next alive player
    local idx = self:IndexOf(playerName) or self.currentBidderIndex
    self.currentBidderIndex = self:NextAliveIndex(idx)
    return true
end

-- The smallest legal raise over the standing bid (used for auto-play on
-- turn timeout, so an idle player never instantly forfeits a die).
function LD:MinimalRaise()
    local minFace = self.onesWild and 2 or 1
    local cur = self.currentBid
    if not cur then
        return 1, minFace
    end
    -- Bump the face if we can, otherwise bump the count and reset the face
    if cur.face < self.DICE_FACES then
        return cur.q, cur.face + 1
    end
    return cur.q + 1, minFace
end

--[[
    CHALLENGE RESOLUTION (host-authoritative)
]]

-- Count how many dice show `face` across all alive hands, counting 1s as
-- wild when enabled. Operates on a diceByName table ([name] = {d,...}).
function LD:CountFace(diceByName, face, onesWild)
    local total = 0
    for _, name in ipairs(self.playerOrder) do
        local dice = diceByName[name]
        if dice then
            for _, d in ipairs(dice) do
                if d == face or (onesWild and d == 1 and face ~= 1) then
                    total = total + 1
                end
            end
        end
    end
    return total
end

-- Host resolves a challenge against the standing bid. Returns a reveal
-- table describing the outcome (does not yet mutate dice counts - call
-- ApplyReveal with the result on every client, host included).
function LD:ResolveChallenge(challenger)
    local cur = self.currentBid
    if not cur or not self.allDice then return nil end

    local count = self:CountFace(self.allDice, cur.face, self.onesWild)
    local bidHolds = count >= cur.q
    local loser = bidHolds and challenger or cur.by

    -- Flatten dice into a serializable, name-keyed snapshot
    local diceSnapshot = {}
    for _, name in ipairs(self.playerOrder) do
        if self.allDice[name] then
            diceSnapshot[name] = { unpack(self.allDice[name]) }
        end
    end

    return {
        dice = diceSnapshot,
        seed = self.roundSeed,
        face = cur.face,
        count = count,
        bidQ = cur.q,
        bidFace = cur.face,
        bidder = cur.by,
        challenger = challenger,
        loser = loser,
        onesWild = self.onesWild,
    }
end

-- Apply a resolved challenge everywhere: record the reveal, dock the loser a
-- die, handle elimination, and set who opens the next round.
function LD:ApplyReveal(reveal)
    self.reveal = reveal
    self.phase = self.PHASE.REVEAL

    local loser = reveal.loser
    local p = self.players[loser]
    if p then
        p.count = math.max(0, (p.count or 0) - 1)
        if p.count == 0 then
            p.alive = false
        end
    end
    self.lastLoser = loser

    -- The loser opens the next round; if eliminated, the next alive player does
    local loserIdx = self:IndexOf(loser) or 1
    if p and p.alive then
        self.firstBidder = loser
    else
        self.firstBidder = self.playerOrder[self:NextAliveIndex(loserIdx)]
    end

    self.currentBid = nil
end

-- After a reveal, is the match over? Returns winner name or nil.
function LD:CheckMatchOver()
    if self:AliveCount() <= 1 then
        for _, name in ipairs(self.playerOrder) do
            local p = self.players[name]
            if p and p.alive then return name end
        end
    end
    return nil
end

-- Lock in the winner and record results. Host records for the group.
function LD:FinalizeSettlement(winner)
    self.winner = winner
    self.phase = self.PHASE.SETTLEMENT

    if BJ.Leaderboard and winner then
        local myName = UnitName("player")
        if not self.hostName or self.hostName == myName then
            local losers = #self.playerOrder - 1
            BJ.Leaderboard:RecordHandResult("liarsdice", winner, self.stake * losers, "win")
            for _, name in ipairs(self.playerOrder) do
                if name ~= winner then
                    BJ.Leaderboard:RecordHandResult("liarsdice", name, -self.stake, "lose")
                end
            end

            -- Session debt ledger: every loser owes the winner the stake.
            -- Settles under the fun/real status the table OPENED with, not
            -- the recorder's live toggle - a mid-game flip (opener's or a
            -- migrated host's) only affects the next hosted table; nil
            -- (legacy opener) falls back to the recorder's live setting.
            if BJ.DebtLedger and self.stake and self.stake > 0 then
                local debts = {}
                for _, name in ipairs(self.playerOrder) do
                    if name ~= winner then
                        table.insert(debts, { debtor = name, creditor = winner, amount = self.stake })
                    end
                end
                BJ.DebtLedger:RecordDebts("liarsdice", debts, self.fakePlay)
            end
        end
    end

    self:SaveToHistory()
end

--[[
    DISPLAY HELPERS
]]

-- English name for a die face
function LD:FaceName(face, plural)
    local names = { "1", "2", "3", "4", "5", "6" }
    local s = names[face] or tostring(face)
    return s .. (plural and "s" or "")
end

-- "three 5s" style bid text
function LD:BidText(bid)
    if not bid then return "no bid yet" end
    return bid.q .. " x " .. self:FaceName(bid.face, bid.q ~= 1)
end

function LD:GetSettlementText()
    if not self.winner then return "No winner" end
    local losers = #self.playerOrder - 1
    return string.format("|cff00ff00%s|r wins the pot!\n|cffffd700%dg|r from %d player%s",
        self.winner, self.stake * losers, losers, losers == 1 and "" or "s")
end

--[[
    GAME HISTORY
]]
LD.gameHistory = {}
LD.MAX_HISTORY = 5

function LD:SaveToHistory()
    if self.phase ~= self.PHASE.SETTLEMENT then return end
    if not self.winner then return end

    local game = {
        timestamp = time(),
        host = self.hostName,
        stake = self.stake,
        numPlayers = #self.playerOrder,
        rounds = self.roundNum,
        winner = self.winner,
    }

    BJ.GameHistory:Add(self.gameHistory, game, self.MAX_HISTORY)
    self:SaveHistoryToDB()
end

function LD:SaveHistoryToDB()
    BJ.GameHistory:Save("liarsdiceHistory", self.gameHistory)
end

function LD:LoadHistoryFromDB()
    local history = BJ.GameHistory:Load("liarsdiceHistory")
    if history then
        self.gameHistory = history
        BJ:Debug("Loaded " .. #self.gameHistory .. " Liar's Dice games from history")
    end
end

function LD:GetGameLogText()
    if #self.gameHistory == 0 then
        return "No game history yet."
    end

    local lines = {}
    for gameNum, game in ipairs(self.gameHistory) do
        table.insert(lines, "|cffffd700=== Game " .. gameNum .. " ===|r")
        table.insert(lines, "Host: " .. (game.host or "?") .. " | " .. (game.numPlayers or 0) ..
            " players at " .. (game.stake or 0) .. "g | " .. (game.rounds or 0) .. " rounds")
        table.insert(lines, "  |cff00ff00" .. (game.winner or "?") .. "|r took the pot")
        table.insert(lines, "")
    end
    return table.concat(lines, "\n")
end
