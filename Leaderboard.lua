--[[
    Chairface's Casino - Leaderboard.lua
    Persistent win/loss tracking with encrypted storage
    Session leaderboards and all-time cross-player sync
]]

local BJ = ChairfacesCasino
BJ.Leaderboard = {}
local LB = BJ.Leaderboard

-- Communication prefix for leaderboard sync
local CHANNEL_PREFIX = "CCLeaderboard"
local AceComm = LibStub("AceComm-3.0")
local AceSerializer = LibStub("AceSerializer-3.0")

-- Message types
local MSG = {
    STATS_REQUEST = "STATS_REQ",      -- Request stats from group
    STATS_RESPONSE = "STATS_RESP",    -- Response with player stats
    STATS_BROADCAST = "STATS_BC",     -- Broadcast own stats to group
    SESSION_UPDATE = "SESS_UPD",      -- Broadcast session leaderboard update
    SESSION_REQUEST = "SESS_REQ",     -- Request current session data from host
    ALLTIME_UPDATE = "AT_UPD",        -- Broadcast all-time leaderboard update for a player
    CLEAR_DB = "CLEAR_DB",            -- Command to clear all leaderboard data (debug)
}

-- Encryption key (different from Compression.lua for extra security)
-- Using player-specific salt makes data non-transferable between accounts
local ENCRYPT_KEY = { 0x4C, 0x42, 0x5F, 0x43, 0x41, 0x53, 0x49, 0x4E, 0x4F } -- "LB_CASINO"

-- HMAC-like checksum to detect tampering
local CHECKSUM_SALT = "ChairfaceCasinoLeaderboard2024"

--[[
    DATA STRUCTURES
    
    Session data (reset each session):
    sessionData[gameType] = {
        players = {
            ["PlayerName-Realm"] = { net = 1234, hands = 5, lastUpdate = time() }
        },
        startTime = time(),
        host = "HostName"
    }
    
    All-time data (persistent, encrypted):
    allTimeData = {
        blackjack = {
            ["PlayerName-Realm"] = { net = 45200, games = 127, lastSync = timestamp }
        },
        poker = { ... },
        hilo = { ... },
        myStats = {
            blackjack = { net = -8200, games = 62, wins = 28, losses = 31, pushes = 3, bestWin = 4200, worstLoss = -2800 },
            poker = { ... },
            hilo = { ... }
        }
    }
]]

-- Session data - now party-wide and cumulative across all games
-- Persists while in a party/raid, tracks total wins/losses per player
LB.partySession = {
    players = {},      -- { playerName = { net = 0, hands = 0, lastUpdate = 0 } }
    startTime = 0,     -- When session started (party formed)
    partyId = nil,     -- Unique ID for this party session
}

-- Per-game session for UI filtering (but data comes from partySession)
LB.gameFilters = {
    blackjack = true,
    poker = true,
    hilo = true,
    craps = true,
}

-- Legacy compatibility - maps to partySession
LB.sessionData = {
    blackjack = { players = {}, startTime = 0, host = nil },
    poker = { players = {}, startTime = 0, host = nil },
    hilo = { players = {}, startTime = 0, host = nil },
    craps = { players = {}, startTime = 0, host = nil },
}

-- All-time data (loaded from encrypted SavedVariables)
LB.allTimeData = nil

-- UI references
LB.sessionFrames = {}  -- { blackjack = frame, poker = frame, hilo = frame }
LB.allTimeFrame = nil

-- Track party membership for session management
LB.lastPartyMembers = {}
LB.partyCheckTimer = nil

--[[
    ============================================
    ENCRYPTION / CHECKSUM FUNCTIONS
    ============================================
]]

-- Generate a checksum for data integrity verification
local function generateChecksum(data)
    local str = CHECKSUM_SALT .. data
    local hash = 0
    for i = 1, #str do
        hash = (hash * 31 + string.byte(str, i)) % 2147483647
    end
    return string.format("%08X", hash)
end

-- XOR encryption with key stretching
local function encryptData(data, playerGUID)
    -- Combine static key with player GUID for account-specific encryption
    local fullKey = {}
    local guidBytes = playerGUID or "DEFAULT"
    for i = 1, #ENCRYPT_KEY do
        table.insert(fullKey, ENCRYPT_KEY[i])
    end
    for i = 1, #guidBytes do
        table.insert(fullKey, string.byte(guidBytes, i))
    end
    
    local result = {}
    for i = 1, #data do
        local keyByte = fullKey[((i - 1) % #fullKey) + 1]
        local dataByte = string.byte(data, i)
        -- Double XOR with position for extra scrambling
        local encrypted = bit.bxor(dataByte, keyByte)
        encrypted = bit.bxor(encrypted, (i * 7) % 256)
        table.insert(result, string.char(encrypted))
    end
    return table.concat(result)
end

-- Decrypt data (symmetric operation)
local function decryptData(data, playerGUID)
    -- Decryption is the reverse of encryption
    local fullKey = {}
    local guidBytes = playerGUID or "DEFAULT"
    for i = 1, #ENCRYPT_KEY do
        table.insert(fullKey, ENCRYPT_KEY[i])
    end
    for i = 1, #guidBytes do
        table.insert(fullKey, string.byte(guidBytes, i))
    end
    
    local result = {}
    for i = 1, #data do
        local keyByte = fullKey[((i - 1) % #fullKey) + 1]
        local dataByte = string.byte(data, i)
        -- Reverse the double XOR
        local decrypted = bit.bxor(dataByte, (i * 7) % 256)
        decrypted = bit.bxor(decrypted, keyByte)
        table.insert(result, string.char(decrypted))
    end
    return table.concat(result)
end

-- Base64 encoding table
local b64chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'

local function base64Encode(data)
    return ((data:gsub('.', function(x) 
        local r, b = '', x:byte()
        for i = 8, 1, -1 do r = r .. (b % 2^i - b % 2^(i-1) > 0 and '1' or '0') end
        return r
    end) .. '0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
        if #x < 6 then return '' end
        local c = 0
        for i = 1, 6 do c = c + (x:sub(i, i) == '1' and 2^(6-i) or 0) end
        return b64chars:sub(c+1, c+1)
    end) .. ({ '', '==', '=' })[#data % 3 + 1])
end

local function base64Decode(data)
    data = string.gsub(data, '[^'..b64chars..'=]', '')
    return (data:gsub('.', function(x)
        if x == '=' then return '' end
        local r, f = '', (b64chars:find(x) - 1)
        for i = 6, 1, -1 do r = r .. (f % 2^i - f % 2^(i-1) > 0 and '1' or '0') end
        return r
    end):gsub('%d%d%d?%d?%d?%d?%d?%d?', function(x)
        if #x ~= 8 then return '' end
        local c = 0
        for i = 1, 8 do c = c + (x:sub(i, i) == '1' and 2^(8-i) or 0) end
        return string.char(c)
    end))
end

-- Save encrypted leaderboard data
function LB:SaveToStorage()
    if not self.allTimeData then return end
    if not ChairfacesCasinoSaved then
        ChairfacesCasinoSaved = {}
    end
    
    -- Serialize
    local serialized = AceSerializer:Serialize(self.allTimeData)
    if not serialized then
        BJ:Debug("Leaderboard: Failed to serialize data")
        return
    end
    
    -- Generate checksum before encryption
    local checksum = generateChecksum(serialized)
    local dataWithChecksum = checksum .. "|" .. serialized
    
    -- Encrypt with player-specific key
    local playerGUID = UnitGUID("player") or "UNKNOWN"
    local encrypted = encryptData(dataWithChecksum, playerGUID)
    
    -- Base64 encode for safe storage
    local encoded = base64Encode(encrypted)
    
    -- Store with version marker
    ChairfacesCasinoSaved.leaderboardData = "LBv2:" .. encoded
    
    BJ:Debug("Leaderboard: Saved encrypted data")
end

-- Load and decrypt leaderboard data
function LB:LoadFromStorage()
    if not ChairfacesCasinoSaved or not ChairfacesCasinoSaved.leaderboardData then
        self:InitializeEmptyData()
        return
    end
    
    local stored = ChairfacesCasinoSaved.leaderboardData
    
    -- Check version marker
    if not stored:match("^LBv2:") then
        BJ:Debug("Leaderboard: Invalid or old format, starting fresh")
        self:InitializeEmptyData()
        return
    end
    
    -- Remove version marker
    local encoded = stored:sub(6)
    
    -- Base64 decode
    local encrypted = base64Decode(encoded)
    if not encrypted or encrypted == "" then
        BJ:Debug("Leaderboard: Failed to decode base64")
        self:InitializeEmptyData()
        return
    end
    
    -- Decrypt
    local playerGUID = UnitGUID("player") or "UNKNOWN"
    local decrypted = decryptData(encrypted, playerGUID)
    
    -- Extract checksum and data
    local checksum, serialized = decrypted:match("^(%x+)|(.+)$")
    if not checksum or not serialized then
        BJ:Debug("Leaderboard: Invalid data format (checksum)")
        self:InitializeEmptyData()
        return
    end
    
    -- Verify checksum
    local expectedChecksum = generateChecksum(serialized)
    if checksum ~= expectedChecksum then
        BJ:Print("|cffff4444Leaderboard data integrity check failed!|r Data may have been tampered with.")
        self:InitializeEmptyData()
        return
    end
    
    -- Deserialize
    local success, data = AceSerializer:Deserialize(serialized)
    if not success or type(data) ~= "table" then
        BJ:Debug("Leaderboard: Failed to deserialize")
        self:InitializeEmptyData()
        return
    end
    
    self.allTimeData = data
    BJ:Debug("Leaderboard: Loaded encrypted data successfully")
end

-- Initialize empty data structure
function LB:InitializeEmptyData()
    self.allTimeData = {
        blackjack = {},
        poker = {},
        hilo = {},
        craps = {},
        myStats = {
            blackjack = { net = 0, games = 0, wins = 0, losses = 0, pushes = 0, bestWin = 0, worstLoss = 0 },
            poker = { net = 0, games = 0, wins = 0, losses = 0, pushes = 0, bestWin = 0, worstLoss = 0 },
            hilo = { net = 0, games = 0, wins = 0, losses = 0, pushes = 0, bestWin = 0, worstLoss = 0 },
            craps = { net = 0, games = 0, wins = 0, losses = 0, pushes = 0, bestWin = 0, worstLoss = 0 },
        }
    }
end

--[[
    ============================================
    INITIALIZATION
    ============================================
]]

function LB:Initialize()
    -- Load persistent data
    self:LoadFromStorage()
    
    -- Register communication channel
    AceComm:RegisterComm(CHANNEL_PREFIX, function(prefix, message, distribution, sender)
        LB:OnCommReceived(prefix, message, distribution, sender)
    end)
    
    -- Register for party/raid events to manage party session
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    eventFrame:RegisterEvent("PARTY_LEADER_CHANGED")
    eventFrame:RegisterEvent("GROUP_LEFT")
    eventFrame:SetScript("OnEvent", function(self, event)
        LB:OnPartyEvent(event)
    end)
    
    -- Initialize party session if already in a group
    if IsInGroup() or IsInRaid() then
        self:StartPartySession()
    end
    
    BJ:Debug("Leaderboard system initialized")
end

-- Handle party events
function LB:OnPartyEvent(event)
    if event == "GROUP_LEFT" then
        -- Party disbanded - end session
        self:EndPartySession()
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PARTY_LEADER_CHANGED" then
        -- Check if we just joined a group
        if IsInGroup() or IsInRaid() then
            if not self.partySession.startTime or self.partySession.startTime == 0 then
                self:StartPartySession()
            else
                -- Already in a session - check if new members joined and broadcast our stats
                -- Use a cooldown to avoid spamming on rapid roster changes
                local now = GetTime()
                if not self.lastRosterSyncTime or (now - self.lastRosterSyncTime) > 5 then
                    self.lastRosterSyncTime = now
                    C_Timer.After(1, function()
                        if IsInGroup() or IsInRaid() then
                            BJ:Debug("Leaderboard: Roster changed, broadcasting stats")
                            LB:BroadcastMyStats()
                        end
                    end)
                end
            end
        else
            -- No longer in a group
            self:EndPartySession()
        end
    end
end

-- Start a new party-wide session
function LB:StartPartySession()
    -- Generate unique party ID based on members
    local members = {}
    
    -- Always add self first
    local myName = UnitName("player")
    if myName and myName ~= "" then
        table.insert(members, myName)
    end
    
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local name = GetRaidRosterInfo(i)
            if name and type(name) == "string" and name ~= "" then
                -- Avoid duplicates
                local found = false
                for _, m in ipairs(members) do
                    if m == name then found = true break end
                end
                if not found then
                    table.insert(members, name)
                end
            end
        end
    elseif IsInGroup() then
        for i = 1, GetNumGroupMembers() - 1 do
            local name = UnitName("party" .. i)
            if name and type(name) == "string" and name ~= "" then
                table.insert(members, name)
            end
        end
    end
    
    -- Need at least one member (self) for a valid session
    if #members == 0 then
        BJ:Debug("Leaderboard: No members found, skipping party session start")
        return
    end
    
    table.sort(members)
    local partyId = table.concat(members, ",") .. ":" .. time()
    
    -- Only reset if this is a new party
    if self.partySession.partyId ~= partyId or self.partySession.startTime == 0 then
        self.partySession = {
            players = {},
            startTime = time(),
            partyId = partyId,
        }
        BJ:Debug("Leaderboard: Started new party session")
        
        -- Auto-sync all-time stats with party members after a short delay
        -- This allows time for everyone to be fully connected
        C_Timer.After(2, function()
            if IsInGroup() or IsInRaid() then
                BJ:Debug("Leaderboard: Auto-syncing all-time stats with party")
                LB:BroadcastMyStats()
            end
        end)
    end
end

-- End party session
function LB:EndPartySession()
    -- Clear session data
    self.partySession = {
        players = {},
        startTime = 0,
        partyId = nil,
    }
    
    -- Hide all session UIs
    if BJ.LeaderboardUI then
        BJ.LeaderboardUI:HideSession("blackjack")
        BJ.LeaderboardUI:HideSession("poker")
        BJ.LeaderboardUI:HideSession("hilo")
    end
    
    BJ:Debug("Leaderboard: Ended party session")
end

--[[
    ============================================
    GAME SESSION MANAGEMENT (per-game tracking within party session)
    ============================================
]]

-- Start a new session for a game type (just tracks which game is active, data goes to party session)
function LB:StartSession(gameType, hostName)
    -- Ensure party session is active if in a group
    if (IsInGroup() or IsInRaid()) and (not self.partySession.startTime or self.partySession.startTime == 0) then
        self:StartPartySession()
    end
    
    -- Update per-game tracking
    self.sessionData[gameType] = {
        players = {},  -- This is now just a reference, actual data in partySession
        startTime = time(),
        host = hostName,
    }
    BJ:Debug("Leaderboard: Started " .. gameType .. " game, host: " .. hostName)
    self:UpdateSessionUI(gameType)
end

-- End a session for a specific game type (party session continues)
function LB:EndSession(gameType)
    local session = self.sessionData[gameType]
    if not session or not session.startTime or session.startTime == 0 then
        return
    end
    
    -- Just clear the per-game tracking, party session data persists
    self.sessionData[gameType] = {
        players = {},
        startTime = 0,
        host = nil,
    }
    
    BJ:Debug("Leaderboard: Ended " .. gameType .. " game (party session continues)")
    -- Note: Don't hide the session UI - it shows party-wide data across all games
end

-- Update session data for a player after a hand (now updates party session)
function LB:RecordHandResult(gameType, playerName, netGold, outcome)
    if not gameType or not playerName then return end
    
    -- Normalize player name (add realm if missing)
    local fullName = playerName
    if not fullName:find("-") then
        local realm = GetRealmName()
        fullName = playerName .. "-" .. realm
    end
    
    -- Update party session data (cumulative across all games)
    if self.partySession.startTime and self.partySession.startTime > 0 then
        if not self.partySession.players[fullName] then
            self.partySession.players[fullName] = { net = 0, hands = 0, lastUpdate = 0 }
        end
        self.partySession.players[fullName].net = self.partySession.players[fullName].net + netGold
        self.partySession.players[fullName].hands = self.partySession.players[fullName].hands + 1
        self.partySession.players[fullName].lastUpdate = time()
        
        -- Broadcast party session update to group
        self:BroadcastPartySessionUpdate()
    end
    
    -- Update all-time data for ALL players (not just self)
    self:UpdateAllTimeStats(gameType, fullName, netGold, outcome)
    
    -- Update UI
    self:UpdateSessionUI(gameType)
    self:UpdateAllTimeUI()
end

-- Update all-time stats for any player (includes wins/losses for local player)
function LB:UpdateAllTimeStats(gameType, fullName, netGold, outcome)
    if not self.allTimeData then
        self:InitializeEmptyData()
    end
    
    -- Initialize game type table if needed
    if not self.allTimeData[gameType] then
        self.allTimeData[gameType] = {}
    end
    
    -- Initialize player entry if needed
    if not self.allTimeData[gameType][fullName] then
        self.allTimeData[gameType][fullName] = {
            net = 0, games = 0, wins = 0, losses = 0, lastSync = 0
        }
    end
    
    local entry = self.allTimeData[gameType][fullName]
    entry.net = entry.net + netGold
    entry.games = entry.games + 1
    
    -- Track wins/losses
    if outcome == "win" or outcome == "blackjack" then
        entry.wins = (entry.wins or 0) + 1
    elseif outcome == "lose" or outcome == "bust" then
        entry.losses = (entry.losses or 0) + 1
    end
    
    entry.lastSync = time()
    
    -- Broadcast this update to the group so everyone has the same data
    self:BroadcastAllTimeUpdate(gameType, fullName, entry)
    
    -- Also update myStats if this is the local player
    local myName = UnitName("player")
    local myRealm = GetRealmName()
    local myFullName = myName .. "-" .. myRealm
    
    if fullName == myFullName then
        self:UpdateMyAllTimeStats(gameType, netGold, outcome)
    else
        -- For other players, just save (they will update their own myStats locally from settlement)
        self:SaveToStorage()
    end
end

-- Update personal all-time stats
function LB:UpdateMyAllTimeStats(gameType, netGold, outcome)
    if not self.allTimeData then
        self:InitializeEmptyData()
    end
    
    local stats = self.allTimeData.myStats[gameType]
    if not stats then
        stats = { net = 0, games = 0, wins = 0, losses = 0, pushes = 0, bestWin = 0, worstLoss = 0 }
        self.allTimeData.myStats[gameType] = stats
    end
    
    stats.net = stats.net + netGold
    stats.games = stats.games + 1
    
    if outcome == "win" or outcome == "blackjack" then
        stats.wins = stats.wins + 1
    elseif outcome == "lose" or outcome == "bust" then
        stats.losses = stats.losses + 1
    elseif outcome == "push" then
        stats.pushes = stats.pushes + 1
    end
    
    if netGold > stats.bestWin then
        stats.bestWin = netGold
    end
    if netGold < stats.worstLoss then
        stats.worstLoss = netGold
    end
    
    -- Also add self to the game-specific leaderboard
    local myName = UnitName("player")
    local myRealm = GetRealmName()
    local myFullName = myName .. "-" .. myRealm
    
    if not self.allTimeData[gameType][myFullName] then
        self.allTimeData[gameType][myFullName] = {
            net = 0, games = 0, wins = 0, losses = 0, pushes = 0, lastSync = 0
        }
    end
    
    local myEntry = self.allTimeData[gameType][myFullName]
    myEntry.net = stats.net
    myEntry.games = stats.games
    myEntry.wins = stats.wins
    myEntry.losses = stats.losses
    myEntry.pushes = stats.pushes
    myEntry.lastSync = time()
    
    -- Save to storage
    self:SaveToStorage()
end

-- Update myStats from local settlement data (called by clients after receiving settlement sync)
-- This allows clients to track their own detailed stats without needing broadcasts from host
function LB:UpdateMyStatsFromSettlement(gameType)
    local myName = UnitName("player")
    local myRealm = GetRealmName()
    local myFullName = myName .. "-" .. myRealm
    
    BJ:Debug("UpdateMyStatsFromSettlement: gameType=" .. gameType .. ", myName=" .. myName)
    
    -- Find settlement data based on game type
    local mySettlement = nil
    local settlementSource = nil
    
    if gameType == "blackjack" then
        if not BJ.GameState or not BJ.GameState.settlements then 
            BJ:Debug("UpdateMyStatsFromSettlement: No BJ settlements table")
            return 
        end
        mySettlement = BJ.GameState.settlements[myName] or BJ.GameState.settlements[myFullName]
        settlementSource = "blackjack"
    elseif gameType == "poker" then
        if not BJ.PokerState or not BJ.PokerState.settlements then 
            BJ:Debug("UpdateMyStatsFromSettlement: No poker settlements table")
            return 
        end
        -- Debug: list all keys in settlements
        BJ:Debug("UpdateMyStatsFromSettlement: Poker settlement keys:")
        for k, v in pairs(BJ.PokerState.settlements) do
            BJ:Debug("  Key: '" .. tostring(k) .. "'")
        end
        mySettlement = BJ.PokerState.settlements[myName] or BJ.PokerState.settlements[myFullName]
        settlementSource = "poker"
    elseif gameType == "hilo" then
        if not BJ.HiLoState then return end
        local HL = BJ.HiLoState
        -- HiLo doesn't have settlements table, we build it from state
        local myShortName = myName  -- HiLo typically uses short names
        
        -- Check if player participated in this game
        local participated = HL.players and HL.players[myShortName]
        if not participated then
            return  -- Player wasn't in this game at all
        end
        
        -- Build settlement based on outcome
        if HL.highPlayer == myShortName then
            mySettlement = { total = HL.winAmount or 0, isWinner = true, participated = true }
        elseif HL.lowPlayer == myShortName then
            mySettlement = { total = -(HL.winAmount or 0), isWinner = false, isLoser = true, participated = true }
        else
            -- Player participated but wasn't winner or loser (eliminated in middle)
            mySettlement = { total = 0, isWinner = false, isLoser = false, participated = true }
        end
        settlementSource = "hilo"
    end
    
    if not mySettlement then 
        BJ:Debug("UpdateMyStatsFromSettlement: mySettlement not found for '" .. myName .. "' or '" .. myFullName .. "'")
        return 
    end
    
    BJ:Debug("UpdateMyStatsFromSettlement: Found settlement, total=" .. (mySettlement.total or 0))
    
    -- Initialize data if needed
    if not self.allTimeData then
        self:InitializeEmptyData()
    end
    
    local stats = self.allTimeData.myStats[gameType]
    if not stats then
        stats = { net = 0, games = 0, wins = 0, losses = 0, pushes = 0, bestWin = 0, worstLoss = 0 }
        self.allTimeData.myStats[gameType] = stats
    end
    
    -- Calculate totals from settlement
    local totalNet = mySettlement.total or 0
    local wins = 0
    local losses = 0
    local pushes = 0
    
    if settlementSource == "blackjack" then
        -- Blackjack uses details array
        if mySettlement.details then
            for i, detail in ipairs(mySettlement.details) do
                if detail.type == "hand" then
                    local result = detail.result
                    if result == "WIN" or result == "BLACKJACK" or result == "win" or result == "blackjack" then
                        wins = wins + 1
                    elseif result == "LOSE" or result == "BUST" or result == "lose" or result == "bust" then
                        losses = losses + 1
                    elseif result == "PUSH" or result == "push" then
                        pushes = pushes + 1
                    end
                end
            end
        end
    elseif settlementSource == "poker" then
        -- Poker uses isWinner flag
        if mySettlement.isWinner then
            wins = 1
        elseif mySettlement.folded then
            losses = 1  -- Folding counts as a loss
        else
            losses = 1  -- Lost at showdown
        end
    elseif settlementSource == "hilo" then
        -- Hi-Lo: only winner/loser get W/L, others just get game counted
        if mySettlement.isWinner then
            wins = 1
        elseif mySettlement.isLoser then
            losses = 1
        end
        -- Players who participated but weren't winner/loser get no W/L but game still counts
    end
    
    -- Update myStats
    stats.net = stats.net + totalNet
    stats.games = stats.games + 1
    stats.wins = stats.wins + wins
    stats.losses = stats.losses + losses
    stats.pushes = stats.pushes + pushes
    
    if totalNet > stats.bestWin then
        stats.bestWin = totalNet
    end
    if totalNet < stats.worstLoss then
        stats.worstLoss = totalNet
    end
    
    -- Also update the all-time leaderboard entry for ourselves
    if not self.allTimeData[gameType] then
        self.allTimeData[gameType] = {}
    end
    if not self.allTimeData[gameType][myFullName] then
        self.allTimeData[gameType][myFullName] = {
            net = 0, games = 0, wins = 0, losses = 0, pushes = 0, lastSync = 0
        }
    end
    
    local myEntry = self.allTimeData[gameType][myFullName]
    myEntry.net = stats.net
    myEntry.games = stats.games
    myEntry.wins = stats.wins
    myEntry.losses = stats.losses
    myEntry.pushes = stats.pushes
    myEntry.lastSync = time()
    
    -- Save and update UI
    self:SaveToStorage()
    self:UpdateAllTimeUI()
    
    BJ:Debug("Leaderboard: Updated myStats from local settlement for " .. gameType)
end

--[[
    ============================================
    MULTIPLAYER SYNC
    ============================================
]]

-- Send message to group
function LB:Send(msgType, ...)
    local parts = { msgType, ... }
    for i, v in ipairs(parts) do
        parts[i] = tostring(v)
    end
    local msg = table.concat(parts, "|")
    
    local channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY" or nil)
    if channel then
        AceComm:SendCommMessage(CHANNEL_PREFIX, msg, channel)
    end
end

-- Send message to specific player
function LB:SendWhisper(target, msgType, ...)
    local parts = { msgType, ... }
    for i, v in ipairs(parts) do
        parts[i] = tostring(v)
    end
    local msg = table.concat(parts, "|")
    AceComm:SendCommMessage(CHANNEL_PREFIX, msg, "WHISPER", target)
end

-- Handle incoming messages
function LB:OnCommReceived(prefix, message, distribution, sender)
    if prefix ~= CHANNEL_PREFIX then return end
    
    local myName = UnitName("player")
    local senderName = sender:match("^([^-]+)") or sender
    if senderName == myName then return end
    
    local parts = { strsplit("|", message) }
    local msgType = parts[1]
    
    if msgType == MSG.STATS_REQUEST then
        -- Someone is requesting our stats
        self:HandleStatsRequest(senderName)
    elseif msgType == MSG.STATS_RESPONSE then
        -- Received stats from another player
        self:HandleStatsResponse(senderName, parts)
    elseif msgType == MSG.STATS_BROADCAST then
        -- Player is broadcasting their stats
        self:HandleStatsBroadcast(senderName, parts)
    elseif msgType == MSG.SESSION_UPDATE then
        -- Someone is broadcasting party session update
        self:HandlePartySessionUpdate(sender, parts)
    elseif msgType == MSG.SESSION_REQUEST then
        -- Someone is requesting party session data
        self:HandlePartySessionRequest(senderName)
    elseif msgType == MSG.ALLTIME_UPDATE then
        -- Someone is broadcasting all-time leaderboard update
        self:HandleAllTimeUpdate(sender, parts)
    elseif msgType == MSG.CLEAR_DB then
        -- Someone is requesting we clear our DB (debug command)
        self:HandleClearDbCommand(sender)
    end
end

-- Broadcast party session update to group (any player can do this)
function LB:BroadcastPartySessionUpdate()
    if not self.partySession.startTime or self.partySession.startTime == 0 then return end
    if not IsInGroup() and not IsInRaid() then return end
    
    -- Build player data string: name1,net1,hands1;name2,net2,hands2;...
    local playerParts = {}
    for name, data in pairs(self.partySession.players) do
        table.insert(playerParts, name .. "," .. data.net .. "," .. data.hands)
    end
    local playerStr = table.concat(playerParts, ";")
    
    self:Send(MSG.SESSION_UPDATE, "party", self.partySession.startTime, playerStr)
end

-- Handle party session update from another player
function LB:HandlePartySessionUpdate(sender, parts)
    -- parts: MSG, "party", startTime, playerStr
    local startTime = tonumber(parts[3]) or 0
    local playerStr = parts[4] or ""
    
    if not IsInGroup() and not IsInRaid() then return end
    
    -- Ensure we have a party session
    if not self.partySession.startTime or self.partySession.startTime == 0 then
        self:StartPartySession()
    end
    
    -- Merge player data (take the higher values to handle sync)
    if playerStr ~= "" then
        for entry in playerStr:gmatch("[^;]+") do
            local name, net, hands = entry:match("([^,]+),([^,]+),([^,]+)")
            if name then
                local newNet = tonumber(net) or 0
                local newHands = tonumber(hands) or 0
                
                local existing = self.partySession.players[name]
                if not existing then
                    self.partySession.players[name] = {
                        net = newNet,
                        hands = newHands,
                        lastUpdate = time()
                    }
                else
                    -- Take higher hand count (more recent data)
                    if newHands > existing.hands then
                        existing.net = newNet
                        existing.hands = newHands
                        existing.lastUpdate = time()
                    end
                end
            end
        end
    end
    
    BJ:Debug("Leaderboard: Received party session update from " .. sender)
    self:UpdateSessionUI("blackjack")
    self:UpdateSessionUI("poker")
    self:UpdateSessionUI("hilo")
end

-- Handle party session request
function LB:HandlePartySessionRequest(requester)
    -- Anyone can respond with their session data
    self:BroadcastPartySessionUpdate()
end

-- Request party session data
function LB:RequestPartySessionData()
    if not IsInGroup() and not IsInRaid() then return end
    self:Send(MSG.SESSION_REQUEST, "party")
end

-- Broadcast all-time update for a specific player/game
-- Format: ALLTIME_UPDATE|gameType|playerName|net|games|wins|losses
function LB:BroadcastAllTimeUpdate(gameType, playerName, data)
    if not IsInGroup() and not IsInRaid() then return end
    if not data then return end
    
    self:Send(MSG.ALLTIME_UPDATE, gameType, playerName, 
        data.net or 0, 
        data.games or 0,
        data.wins or 0,
        data.losses or 0)
end

-- Handle all-time update from another player
function LB:HandleAllTimeUpdate(sender, parts)
    -- parts: MSG, gameType, playerName, net, games, wins, losses
    local gameType = parts[2]
    local playerName = parts[3]
    local net = tonumber(parts[4]) or 0
    local games = tonumber(parts[5]) or 0
    local wins = tonumber(parts[6]) or 0
    local losses = tonumber(parts[7]) or 0
    
    if not gameType or not playerName then return end
    
    -- Initialize data structures if needed
    if not self.allTimeData then
        self:InitializeEmptyData()
    end
    if not self.allTimeData[gameType] then
        self.allTimeData[gameType] = {}
    end
    
    -- Get or create player entry
    local existing = self.allTimeData[gameType][playerName]
    
    -- Only update if the incoming data has more games (is more recent)
    if not existing or games > (existing.games or 0) then
        self.allTimeData[gameType][playerName] = {
            net = net,
            games = games,
            wins = wins,
            losses = losses,
            lastSync = time()
        }
        
        -- Save and update UI
        self:SaveToStorage()
        self:UpdateAllTimeUI()
        
        BJ:Debug("Leaderboard: Updated all-time data for " .. playerName .. " in " .. gameType)
    end
end

-- Clear all leaderboard data (debug function)
function LB:ClearAllData(broadcast)
    -- Clear all-time data
    self.allTimeData = {
        blackjack = {},
        poker = {},
        hilo = {},
        myStats = {
            blackjack = { net = 0, games = 0, wins = 0, losses = 0, pushes = 0, bestWin = 0, worstLoss = 0 },
            poker = { net = 0, games = 0, wins = 0, losses = 0, pushes = 0, bestWin = 0, worstLoss = 0 },
            hilo = { net = 0, games = 0, wins = 0, losses = 0, pushes = 0, bestWin = 0, worstLoss = 0 },
        }
    }
    
    -- Clear party session
    self.partySession = {
        players = {},
        startTime = 0,
        partyId = nil,
    }
    
    -- Clear per-game session data
    for _, gameType in ipairs({ "blackjack", "poker", "hilo" }) do
        self.sessionData[gameType] = {
            players = {},
            startTime = 0,
            host = nil,
        }
    end
    
    -- Save cleared data
    self:SaveToStorage()
    
    -- Update UI
    self:UpdateAllTimeUI()
    self:UpdateSessionUI("blackjack")
    self:UpdateSessionUI("poker")
    self:UpdateSessionUI("hilo")
    
    BJ:Debug("Leaderboard: Cleared all local data")
    print("|cffff9944[Casino]|r All leaderboard data cleared!")
    
    -- Broadcast to group if requested
    if broadcast and (IsInGroup() or IsInRaid()) then
        self:Send(MSG.CLEAR_DB)
        print("|cffff9944[Casino]|r Clear command sent to group members")
    end
end

-- Handle clear DB command from another player
function LB:HandleClearDbCommand(sender)
    BJ:Debug("Leaderboard: Received clear DB command from " .. sender)
    print("|cffff9944[Casino]|r Received clear command from " .. sender .. " - clearing local data...")
    
    -- Clear without re-broadcasting
    self:ClearAllData(false)
end

-- Handle stats request - send our stats
function LB:HandleStatsRequest(requester)
    if not self.allTimeData or not self.allTimeData.myStats then return end
    
    local myName = UnitName("player")
    local myRealm = GetRealmName()
    local myFullName = myName .. "-" .. myRealm
    
    -- Send stats for each game type
    for _, gameType in ipairs({ "blackjack", "poker", "hilo" }) do
        local stats = self.allTimeData.myStats[gameType]
        if stats and stats.games > 0 then
            self:SendWhisper(requester, MSG.STATS_RESPONSE,
                gameType,
                myFullName,
                stats.net,
                stats.games,
                stats.wins,
                stats.losses,
                stats.pushes
            )
        end
    end
end

-- Handle stats response - merge into our all-time data
function LB:HandleStatsResponse(sender, parts)
    -- parts: MSG, gameType, fullName, net, games, wins, losses, pushes
    local gameType = parts[2]
    local fullName = parts[3]
    local net = tonumber(parts[4]) or 0
    local games = tonumber(parts[5]) or 0
    local wins = tonumber(parts[6]) or 0
    local losses = tonumber(parts[7]) or 0
    local pushes = tonumber(parts[8]) or 0
    
    if not gameType or not fullName then return end
    if not self.allTimeData then self:InitializeEmptyData() end
    if not self.allTimeData[gameType] then self.allTimeData[gameType] = {} end
    
    -- Merge: only update if their data is newer/different
    local existing = self.allTimeData[gameType][fullName]
    if not existing or existing.games < games then
        self.allTimeData[gameType][fullName] = {
            net = net,
            games = games,
            wins = wins,
            losses = losses,
            pushes = pushes,
            lastSync = time()
        }
        BJ:Debug("Leaderboard: Updated " .. fullName .. " " .. gameType .. " stats")
        self:SaveToStorage()
        self:UpdateAllTimeUI()
    end
end

-- Handle stats broadcast (same as response)
function LB:HandleStatsBroadcast(sender, parts)
    self:HandleStatsResponse(sender, parts)
end

-- Request stats from all group members
function LB:RequestGroupSync()
    if not IsInGroup() and not IsInRaid() then
        BJ:Print("Join a group to sync leaderboard data with other players.")
        return
    end
    
    self:Send(MSG.STATS_REQUEST)
    BJ:Print("|cff88ff88Requesting leaderboard sync from group...|r")
    
    -- Also broadcast our own stats
    C_Timer.After(0.5, function()
        LB:BroadcastMyStats()
    end)
end

-- Broadcast our stats to the group
function LB:BroadcastMyStats()
    if not self.allTimeData or not self.allTimeData.myStats then return end
    
    local myName = UnitName("player")
    local myRealm = GetRealmName()
    local myFullName = myName .. "-" .. myRealm
    
    for _, gameType in ipairs({ "blackjack", "poker", "hilo" }) do
        local stats = self.allTimeData.myStats[gameType]
        if stats and stats.games > 0 then
            self:Send(MSG.STATS_BROADCAST,
                gameType,
                myFullName,
                stats.net,
                stats.games,
                stats.wins,
                stats.losses,
                stats.pushes
            )
        end
    end
end

--[[
    ============================================
    DATA ACCESS HELPERS
    ============================================
]]

-- Get sorted session leaderboard
function LB:GetSessionLeaderboard(gameType)
    -- Use party session data (cumulative across all games)
    if not self.partySession or not self.partySession.players then
        return {}
    end
    
    local sorted = {}
    for name, data in pairs(self.partySession.players) do
        table.insert(sorted, {
            name = name,
            net = data.net,
            hands = data.hands,
        })
    end
    
    table.sort(sorted, function(a, b) return a.net > b.net end)
    return sorted
end

-- Get sorted all-time leaderboard for a game type
function LB:GetAllTimeLeaderboard(gameType)
    if not self.allTimeData or not self.allTimeData[gameType] then
        return {}
    end
    
    local sorted = {}
    for name, data in pairs(self.allTimeData[gameType]) do
        table.insert(sorted, {
            name = name,
            net = data.net or 0,
            games = data.games or 0,
            wins = data.wins or 0,
            losses = data.losses or 0,
            pushes = data.pushes or 0,
            lastSync = data.lastSync or 0,
        })
    end
    
    -- Sort: players with W/L first (by net), then players with only games (by games desc)
    table.sort(sorted, function(a, b)
        local aHasWL = (a.wins > 0 or a.losses > 0)
        local bHasWL = (b.wins > 0 or b.losses > 0)
        
        if aHasWL and not bHasWL then
            return true  -- a comes first (has W/L)
        elseif not aHasWL and bHasWL then
            return false  -- b comes first (has W/L)
        elseif aHasWL and bHasWL then
            -- Both have W/L, sort by net
            return a.net > b.net
        else
            -- Neither has W/L, sort by games played
            return a.games > b.games
        end
    end)
    return sorted
end

-- Get my stats for a game type
function LB:GetMyStats(gameType)
    if not self.allTimeData or not self.allTimeData.myStats then
        return nil
    end
    return self.allTimeData.myStats[gameType]
end

-- Get total players in leaderboard
function LB:GetTotalPlayers()
    if not self.allTimeData then return 0 end
    
    local seen = {}
    for _, gameType in ipairs({ "blackjack", "poker", "hilo" }) do
        if self.allTimeData[gameType] then
            for name, _ in pairs(self.allTimeData[gameType]) do
                seen[name] = true
            end
        end
    end
    
    local count = 0
    for _ in pairs(seen) do
        count = count + 1
    end
    return count
end

-- Check if session is active
function LB:IsSessionActive(gameType)
    local session = self.sessionData[gameType]
    return session and session.startTime and session.startTime > 0
end

-- Get session info
function LB:GetSessionInfo(gameType)
    local session = self.sessionData[gameType]
    if not session then return nil end
    return {
        host = session.host,
        startTime = session.startTime,
        playerCount = 0,  -- Will count below
        totalHands = 0,
        totalPot = 0,
    }
end

-- Reset my data (with confirmation)
function LB:ResetMyData(gameType)
    if not self.allTimeData then return end
    
    if gameType then
        -- Reset specific game
        self.allTimeData.myStats[gameType] = {
            net = 0, games = 0, wins = 0, losses = 0, pushes = 0, bestWin = 0, worstLoss = 0
        }
        -- Remove self from that leaderboard
        local myName = UnitName("player")
        local myRealm = GetRealmName()
        local myFullName = myName .. "-" .. myRealm
        self.allTimeData[gameType][myFullName] = nil
    else
        -- Reset all
        self:InitializeEmptyData()
    end
    
    self:SaveToStorage()
    self:UpdateAllTimeUI()
    BJ:Print("|cffffd700Leaderboard data reset.|r")
end

--[[
    ============================================
    UI UPDATE STUBS (implemented in LeaderboardUI.lua)
    ============================================
]]

function LB:UpdateSessionUI(gameType)
    if self.sessionFrames[gameType] and self.sessionFrames[gameType]:IsShown() then
        if BJ.LeaderboardUI and BJ.LeaderboardUI.UpdateSessionFrame then
            BJ.LeaderboardUI:UpdateSessionFrame(gameType)
        end
    end
end

function LB:UpdateAllTimeUI()
    if self.allTimeFrame and self.allTimeFrame:IsShown() then
        if BJ.LeaderboardUI and BJ.LeaderboardUI.UpdateAllTimeFrame then
            BJ.LeaderboardUI:UpdateAllTimeFrame()
        end
    end
end
