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

-- Realm-wide sync rides the SAME shared hidden channel the table finder uses
-- (TableFinder joins "ChairfaceCasino" at login); our traffic is marked
-- CCLB7 so it never collides with the finder's CCLFG7. Declared up here so
-- the CHAT_MSG_CHANNEL handler in Initialize can see them (they used to be
-- locals defined below Initialize, which made the handler read a nil global).
local REALM_CHANNEL = "ChairfaceCasino"
local LB_MARK = "CCLB7"

-- Message types
-- The legacy types (STATS_*, SESS_UPD, AT_UPD) are still EMITTED so
-- pre-2.5.4 clients keep seeing updates, but they are no longer ingested:
-- they carry blended accumulator totals that cannot be deduplicated (see
-- the bucket notes below). All ingest goes through the bucket messages.
local MSG = {
    STATS_REQUEST = "STATS_REQ",      -- Legacy: request stats from group (still answered)
    STATS_RESPONSE = "STATS_RESP",    -- Legacy: response with player stats (emit only)
    STATS_BROADCAST = "STATS_BC",     -- Legacy: broadcast own stats (emit only)
    SESSION_UPDATE = "SESS_UPD",      -- Legacy: session update (emit only)
    SESSION_REQUEST = "SESS_REQ",     -- Request current session data (answered with both formats)
    ALLTIME_UPDATE = "AT_UPD",        -- Legacy: all-time update (emit only)
    CLEAR_DB = "CLEAR_DB",            -- Command to clear all leaderboard data (debug)
    BUCKETS = "B3",                   -- Bucket payload: the SENDER'S OWN recorder buckets
    BUCKETS_ANY = "R3",               -- Bucket payload: any recorders (digest reply, whispered)
    DIGEST = "D3",                    -- Anti-entropy digest: bucket versions I hold
    SESSION_BUCKET = "S3",            -- Session update: the sender's own session bucket
    -- SEASON-TAGGED all-time bucket sync (2.5.4+). Same payloads as B3/R3/D3
    -- but prefixed with the sender's season; a receiver drops any payload
    -- whose season != its own so a season reset can't be undone by a peer
    -- (old client, or one that hasn't reset yet) pushing pre-season buckets.
    -- B3/R3 stay EMITTED for pre-2.5.4 peers but are no longer INGESTED.
    BUCKETS_S = "B4",                 -- season | own-recorder buckets
    BUCKETS_ANY_S = "R4",             -- season | any-recorder buckets (digest reply)
    DIGEST_S = "D4",                  -- season | digest
    HELLO = "H4",                     -- realm-channel presence ping: just the season
}

-- Encryption key (different from Compression.lua for extra security)
-- Using player-specific salt makes data non-transferable between accounts
local ENCRYPT_KEY = { 0x4C, 0x42, 0x5F, 0x43, 0x41, 0x53, 0x49, 0x4E, 0x4F } -- "LB_CASINO"

-- HMAC-like checksum to detect tampering
local CHECKSUM_SALT = "ChairfaceCasinoLeaderboard2024"

--[[
    DATA STRUCTURES — PER-RECORDER BUCKETS

    Every hand is recorded by exactly ONE machine: the host of that game
    (all RecordHandResult call sites are host-gated). The sync layer keeps
    that property instead of blending it away: a player's leaderboard row
    is a set of BUCKETS keyed by the recorder that witnessed those hands.

        allTimeData[gameType]["Player-Realm"] = {
            buckets = {
                ["Recorder-Realm"] = { net, games, wins, losses, pushes },
                ["LEGACY:Player-Realm"] = { ... },  -- frozen pre-bucket data
            },
            lastSync = timestamp,
        }

    Rules that make sync duplication-proof:
    - A machine only ever ADDS HANDS to its own bucket (recorder = itself).
      Everyone else's copy of that bucket is a replica, replaced wholesale.
    - A bucket's games count therefore only grows at its single writer, so
      "more games" is an exact version number, not a heuristic. Equal-games
      ties break deterministically (net, then wins) so all clients converge.
    - Applying any bucket twice is a no-op. Replays, rebroadcasts and
      out-of-order digests can never double-count a hand.
    - A row's displayed total is the SUM of its buckets; each hand lives in
      exactly one bucket (its host's), so the sum counts it exactly once.

    The one-time migration wraps each old blended row into a synthetic
    "LEGACY:<owner>" bucket (same id on every machine, then frozen), so old
    totals survive and converge instead of stacking.

    myStats (personal detail: pushes/bestWin/worstLoss panel) is unchanged:
    local-only accumulation, never merged from the network.

    Session data uses the same shape with { net, hands, start } buckets.
    start is the RECORDER'S session startTime: when a party re-forms the
    recorder's fresh bucket (newer start, fewer hands) must supersede its
    stale one on every receiver, so a session bucket's version is the pair
    (start, hands) — still single-writer, still monotonic at the writer.
        partySession.players["Player-Realm"] = {
            buckets = { ["Recorder-Realm"] = { net, hands, start } },
            lastUpdate = time(),
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
    holdem = true,
    hilo = true,
    deathroll = true,
    bingo = true,
    roulette = true,
    liarsdice = true,
    crash = true,
    chairscup = true,
}

-- Legacy compatibility - maps to partySession
LB.sessionData = {
    blackjack = { players = {}, startTime = 0, host = nil },
    poker = { players = {}, startTime = 0, host = nil },
    holdem = { players = {}, startTime = 0, host = nil },
    hilo = { players = {}, startTime = 0, host = nil },
    deathroll = { players = {}, startTime = 0, host = nil },
    bingo = { players = {}, startTime = 0, host = nil },
    roulette = { players = {}, startTime = 0, host = nil },
}

-- All-time data (loaded from encrypted SavedVariables)
LB.allTimeData = nil

-- UI references
LB.sessionFrames = {}  -- { blackjack = frame, poker = frame, hilo = frame }
LB.allTimeFrame = nil

-- Track party membership for session management
LB.lastPartyMembers = {}
LB.partyCheckTimer = nil

-- Pending sync work, flushed in one batch shortly after a settlement
LB.dirtyRows = {}          -- dirtyRows[gameType][fullName] = true
LB.sessionDirty = false
LB.flushQueued = false
LB.lastDigestReply = {}    -- per-sender cooldown for digest responses
LB.digestSentTo = {}       -- whisper-digest targets (R4 solicitation record)
LB.lastDigestBroadcast = 0 -- when we last broadcast a digest to the group
LB.saveQueued = false      -- debounced SaveToStorage pending

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

-- Debounced save for the hot paths. A full save is a serialize + XOR +
-- base64 pass over the ENTIRE board (which now grows with the whole
-- server), and a blackjack settlement used to trigger it twice per seat in
-- one frame. SavedVariables only persist on logout/reload anyway, so
-- batching to one save per 10s loses nothing - the logout handler flushes
-- whatever is still pending.
function LB:QueueSave()
    if self.saveQueued then return end
    self.saveQueued = true
    C_Timer.After(10, function()
        LB.saveQueued = false
        LB:SaveToStorage()
    end)
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
        -- Checksum mismatch - could be corrupted data, different character, or actual tampering
        -- Just silently reset rather than alarming the user
        BJ:Debug("Leaderboard: Checksum mismatch, starting fresh")
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
    self:MigrateToBuckets()
    self:ApplySeasonReset()
end

-- Every game the leaderboard tracks
LB.GAME_TYPES = { "blackjack", "poker", "holdem", "hilo", "deathroll", "bingo", "roulette", "liarsdice", "crash", "chairscup" }

-- Data format version (3 = per-recorder buckets)
LB.DATA_FMT = 3

-- All-time leaderboard SEASON. Bumping this retires every existing all-time
-- board row on next load (see ApplySeasonReset) for a clean server-wide
-- start, and tags all bucket sync so pre-reset/old-season data can't flow
-- back in. Personal myStats is NOT reset. Bump only with the user's OK.
-- Season 2 (2.6.2): fresh start for settlement gating - season 1 boards
-- were fed at game settlement, season 2 rows only ever contain SETTLED
-- hands, so the two must not mix.
LB.SEASON = 2

-- Initialize empty data structure
function LB:InitializeEmptyData()
    self.allTimeData = { myStats = {}, fmt = LB.DATA_FMT, season = LB.SEASON }
    for _, gameType in ipairs(LB.GAME_TYPES) do
        self.allTimeData[gameType] = {}
        self.allTimeData.myStats[gameType] = { net = 0, games = 0, wins = 0, losses = 0, pushes = 0, bestWin = 0, worstLoss = 0 }
    end
end

-- Season epoch: if the stored board predates the current season, retire every
-- all-time row (keep personal myStats) so the whole server restarts clean.
-- One-time per season bump; the notice prints after login.
function LB:ApplySeasonReset()
    local data = self.allTimeData
    if not data then return end
    if data.season == LB.SEASON then return end
    for k, v in pairs(data) do
        if k ~= "myStats" and k ~= "fmt" and k ~= "season" and type(v) == "table" then
            data[k] = {}
        end
    end
    data.season = LB.SEASON
    self.seasonWasReset = true
    self:SaveToStorage()
end

--[[
    ============================================
    BUCKET CORE
    ============================================
]]

local function myFullName()
    return BJ:MyName() .. "-" .. GetRealmName()
end

--[[
    INGEST GUARDS

    Realm-wide sync means ANY player on the server can whisper us a bucket
    payload, so nothing off the wire is trusted: a string or table where a
    number belongs would error in bucketBeats/GetRowTotals (breaking ingest
    or the board UI), and games = math.huge would mint a bucket no real
    counter could ever beat - poisoning the whole realm until a season bump.
    Every incoming bucket is normalized through sanitizeBucket, unknown game
    keys are dropped (they'd otherwise bloat everyone's SavedVariables), and
    name keys are length-capped.
]]

local VALID_GAMES = {}
for _, g in ipairs(LB.GAME_TYPES) do VALID_GAMES[g] = true end

local MAX_BUCKET_GAMES = 1000000     -- one hand every ~30s, nonstop, for a year
local MAX_BUCKET_NET = 100000000     -- +/- 100M gold net
local MAX_NAME_LEN = 64              -- "Name-Realm" (LEGACY: prefix adds 7)

-- Non-negative integer within cap; nil field counts as 0 (old buckets).
local function saneCount(v)
    if v == nil then return 0 end
    v = tonumber(v)
    if not v or v ~= v or v < 0 or v > MAX_BUCKET_GAMES then return nil end
    return math.floor(v)
end

local function saneNet(v)
    if v == nil then return 0 end
    v = tonumber(v)
    if not v or v ~= v or v < -MAX_BUCKET_NET or v > MAX_BUCKET_NET then return nil end
    return v
end

-- Validate + normalize one incoming bucket. Returns a clean copy, or nil
-- if any field is the wrong type, non-finite, or out of bounds.
local function sanitizeBucket(b)
    if type(b) ~= "table" then return nil end
    local net = saneNet(b.net)
    local games = saneCount(b.games)
    local wins = saneCount(b.wins)
    local losses = saneCount(b.losses)
    local pushes = saneCount(b.pushes)
    if not (net and games and wins and losses and pushes) then return nil end
    return { net = net, games = games, wins = wins, losses = losses, pushes = pushes }
end

-- Exact version compare between two copies of the SAME bucket. games only
-- grows at the bucket's single writer, so more games = strictly newer.
-- Equal games ties (only possible for the one-shot LEGACY migration
-- buckets, written once per machine) break deterministically so every
-- client keeps the same copy. Equal on all keys = same data = no-op.
local function bucketBeats(inc, cur)
    if not cur then return true end
    if (inc.games or 0) ~= (cur.games or 0) then return (inc.games or 0) > (cur.games or 0) end
    if (inc.net or 0) ~= (cur.net or 0) then return (inc.net or 0) > (cur.net or 0) end
    if (inc.wins or 0) ~= (cur.wins or 0) then return (inc.wins or 0) > (cur.wins or 0) end
    return false
end

-- Find-or-create a row (bucket container) for a player in a game
function LB:GetRow(gameType, rowName)
    if not self.allTimeData then self:InitializeEmptyData() end
    if not self.allTimeData[gameType] then self.allTimeData[gameType] = {} end
    local row = self.allTimeData[gameType][rowName]
    if not row then
        row = { buckets = {}, lastSync = 0 }
        self.allTimeData[gameType][rowName] = row
    end
    return row
end

-- Replace-if-newer replica merge. Never accumulates: replaying the same
-- bucket any number of times cannot change the result.
function LB:MergeBucket(gameType, rowName, recorder, incoming)
    if not gameType or not rowName or not recorder or not incoming then return false end
    local row = self:GetRow(gameType, rowName)
    local cur = row.buckets[recorder]
    if not bucketBeats(incoming, cur) then return false end
    row.buckets[recorder] = {
        net = incoming.net or 0,
        games = incoming.games or 0,
        wins = incoming.wins or 0,
        losses = incoming.losses or 0,
        pushes = incoming.pushes or 0,
    }
    row.lastSync = time()
    return true
end

-- Displayed totals for a row: the sum of its buckets. Each hand lives in
-- exactly one bucket, so the sum counts it exactly once.
function LB:GetRowTotals(gameType, rowName)
    local row = self.allTimeData and self.allTimeData[gameType]
        and self.allTimeData[gameType][rowName]
    if not row or not row.buckets then return nil end
    local t = { net = 0, games = 0, wins = 0, losses = 0, pushes = 0, lastSync = row.lastSync or 0 }
    for _, b in pairs(row.buckets) do
        t.net = t.net + (b.net or 0)
        t.games = t.games + (b.games or 0)
        t.wins = t.wins + (b.wins or 0)
        t.losses = t.losses + (b.losses or 0)
        t.pushes = t.pushes + (b.pushes or 0)
    end
    return t
end

-- One-time upgrade of pre-bucket (blended-accumulator) rows: each becomes
-- a single synthetic "LEGACY:<owner>" bucket. The id is the same on every
-- machine and the bucket is written exactly once (then frozen), so when
-- two clients migrate different blends of the same player, the
-- deterministic compare converges them to one copy instead of stacking.
function LB:MigrateToBuckets()
    local data = self.allTimeData
    if not data or data.fmt == LB.DATA_FMT then return end
    for gameType, rows in pairs(data) do
        if gameType ~= "myStats" and gameType ~= "fmt" and type(rows) == "table" then
            for rowName, entry in pairs(rows) do
                if type(entry) == "table" and not entry.buckets then
                    rows[rowName] = {
                        buckets = {
                            ["LEGACY:" .. rowName] = {
                                net = entry.net or 0,
                                games = entry.games or 0,
                                wins = entry.wins or 0,
                                losses = entry.losses or 0,
                                pushes = entry.pushes or 0,
                            },
                        },
                        lastSync = entry.lastSync or 0,
                    }
                end
            end
        end
    end
    data.fmt = LB.DATA_FMT
    self:SaveToStorage()
    BJ:Debug("Leaderboard: migrated legacy rows to per-recorder buckets")
end

--[[
    ============================================
    INITIALIZATION
    ============================================
]]

function LB:Initialize()
    -- Load persistent data
    self:LoadFromStorage()

    -- Attach the pending-hand store (hands waiting on debt settlement
    -- survive relogs; a debt paid days later still graduates them)
    self:EnsurePendingStore()

    -- Register communication channel
    AceComm:RegisterComm(CHANNEL_PREFIX, function(prefix, message, distribution, sender)
        LB:OnCommReceived(prefix, message, distribution, sender)
    end)
    
    -- Register for party/raid events to manage party session, plus the shared
    -- realm channel for realm-wide leaderboard discovery (HELLO pings).
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    eventFrame:RegisterEvent("PARTY_LEADER_CHANGED")
    eventFrame:RegisterEvent("GROUP_LEFT")
    eventFrame:RegisterEvent("CHAT_MSG_CHANNEL")
    eventFrame:RegisterEvent("PLAYER_LOGOUT")
    eventFrame:SetScript("OnEvent", function(self, event, ...)
        if event == "PLAYER_LOGOUT" then
            -- Flush a pending debounced save (pure local writes, no network)
            if LB.saveQueued then
                LB.saveQueued = false
                LB:SaveToStorage()
            end
            return
        end
        if event == "CHAT_MSG_CHANNEL" then
            -- Channel first, then the text, each through BJ:Readable: on
            -- Forever channel text can be a secret string (see Core.lua).
            local text, sender, _, _, _, _, _, _, chanName = ...
            chanName = BJ:Readable(chanName)
            if not (chanName and chanName:lower():find(REALM_CHANNEL:lower(), 1, true)) then return end
            text, sender = BJ:Readable(text), BJ:Readable(sender)
            if text and sender and text:sub(1, #LB_MARK) == LB_MARK then
                local body = text:sub(#LB_MARK + 1):gsub("~", "|")
                local mt, season = body:match("^([^|]+)|(.*)$")
                if mt == MSG.HELLO then
                    LB:OnRealmHello(sender, season)
                end
            end
            return
        end
        LB:OnPartyEvent(event)
    end)

    -- Queue a realm HELLO for the first UI click to flush (announces our
    -- season so ungrouped realm peers can pull our board and vice versa).
    C_Timer.After(15, function() LB:QueueRealmHello(true) end)
    -- Keep a fresh HELLO queued for the next hardware flush (throttled inside).
    C_Timer.NewTicker(600, function() LB:QueueRealmHello() end)

    -- Initialize party session if already in a group
    if IsInGroup() or IsInRaid() then
        self:StartPartySession()
    end

    -- Announce a season reset once the player is in-world
    if self.seasonWasReset then
        self.seasonWasReset = nil
        C_Timer.After(5, function()
            BJ:Print("|cffffd700New leaderboard season!|r The all-time board has been reset for a fresh start - your personal stats are kept.")
        end)
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
                            LB:BroadcastDigest()
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
    local myName = BJ:MyName()
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
            local name = BJ:UnitFullName("party" .. i)
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
                LB:BroadcastDigest()
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
        BJ.LeaderboardUI:HideSession("holdem")
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

-- Record one hand result. Only the game's HOST reaches this (every call
-- site is host-gated), so this machine is the single writer of the hand:
-- it lands in OUR OWN bucket under the player's row, exactly once, and
-- replicates from there. Nobody else ever adds it anywhere.
-- SETTLEMENT GATING: the hand does NOT hit the shared all-time board here.
-- It stages and only graduates into the bucket once the debt it created is
-- settled (see the PENDING HANDS section). The session board and the
-- personal myStats panel stay live.
function LB:RecordHandResult(gameType, playerName, netGold, outcome)
    if not gameType or not playerName then return end

    -- Normalize player name (add realm if missing)
    local fullName = playerName
    if not fullName:find("-") then
        fullName = playerName .. "-" .. GetRealmName()
    end
    local recorder = myFullName()

    -- Party session: bump my own session bucket for this player
    if self.partySession.startTime and self.partySession.startTime > 0 then
        local row = self.partySession.players[fullName]
        if not row then
            row = { buckets = {}, lastUpdate = 0 }
            self.partySession.players[fullName] = row
        end
        local b = row.buckets[recorder]
        if not b then
            b = { net = 0, hands = 0, start = self.partySession.startTime }
            row.buckets[recorder] = b
        end
        b.net = b.net + netGold
        b.hands = b.hands + 1
        b.start = self.partySession.startTime
        row.lastUpdate = time()
        self.sessionDirty = true
    end

    -- All-time: STAGE the hand. It graduates into my bucket only when the
    -- debt it creates SETTLES - paid by trade, or netted square by later
    -- results. Forgiven debts and FREE PLAY rounds never count; zero-net
    -- hands (push / participated) have nothing owed and commit at the next
    -- flush. See the PENDING HANDS section.
    self:StageHand(gameType, fullName, netGold, outcome)

    -- Personal detail panel (pushes/bestWin/worstLoss) for the local player
    -- stays LIVE - it is local-only, so there is nothing to game.
    if fullName == recorder then
        self:UpdateMyAllTimeStats(gameType, netGold, outcome)
    end

    self:QueueFlush()

    -- Update UI
    self:UpdateSessionUI(gameType)
    self:UpdateAllTimeUI()
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

    -- NOTE: myStats no longer mirrors into the leaderboard row. The row is
    -- the sum of recorder buckets; mirroring a second accumulator onto it
    -- was one of the old duplication paths.

    self:QueueSave()
end

-- Update myStats from local settlement data (called by clients after receiving settlement sync)
-- This allows clients to track their own detailed stats without needing broadcasts from host
function LB:UpdateMyStatsFromSettlement(gameType)
    local myName = BJ:MyName()
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
    elseif gameType == "holdem" then
        if not BJ.HoldemState or not BJ.HoldemState.settlements then
            BJ:Debug("UpdateMyStatsFromSettlement: No holdem settlements table")
            return
        end
        mySettlement = BJ.HoldemState.settlements[myName] or BJ.HoldemState.settlements[myFullName]
        settlementSource = "holdem"
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
    elseif settlementSource == "poker" or settlementSource == "holdem" then
        -- Poker / Hold'em use the isWinner flag
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
    
    -- NOTE: deliberately NOT written into the leaderboard row. The hand is
    -- already in the recording host's bucket (which replicates to us);
    -- writing it here as well would count it twice.

    -- Save and update UI
    self:QueueSave()
    self:UpdateAllTimeUI()

    BJ:Debug("Leaderboard: Updated myStats from local settlement for " .. gameType)
end

--[[
    ============================================
    PENDING HANDS (settlement-gated board entry)

    A hand the host records does NOT hit the shared all-time board at game
    settlement - a board fed at settlement counts debts that later get
    forgiven, and free wins between friends who never intend to pay. The
    hand stages here, gets bound to the debt-ledger pair(s) its gold flows
    through, and graduates into the recorder's bucket only when every one
    of those pairs' balances clears:

      - a detected trade payment squares the pair  -> hands graduate
      - later results net the pair back to zero    -> hands graduate
        (the books are square; nobody owes anything)
      - the creditor FORGIVES the pair             -> hands still watching
        it are VOIDED - forgiven gold never counts
      - FREE PLAY round (fake play host)           -> discarded outright
      - zero-net hand (push / participated)        -> commits immediately;
        nothing was owed

    Pending hands persist in ChairfacesCasinoDB.lbPending (plaintext,
    beside the debt ledger they mirror), so a debt paid days later still
    graduates the hands it funded. Everything runs on the RECORDER's
    machine and graduation rides the normal bucket flush - no wire changes,
    older clients just see the updates later. If the recorder wasn't around
    when a pair was paid, the ledger's own sync (PAY broadcast, SYNC_FULL
    tombstones) squares its copy eventually and the hands graduate then.
    Known soft spot: a remote forgiveness the recorder only learns about
    through a SYNC_FULL zero tombstone is indistinguishable from a payment
    and graduates; the live FORGIVE broadcast voids correctly.

    The SESSION board and the personal myStats panel deliberately stay
    LIVE: the session pane is the night's running scoreboard (it mirrors
    the tab, not the settled history), and myStats is local-only.
    ============================================
]]

-- DebtLedger reports some games under its own keys
local DEBT_GAME_ALIAS = { derby = "chairscup" }

-- Staged hands are married to the debt entries from the SAME settlement:
-- games call RecordHandResult and RecordDebts in either order, both
-- synchronously, and FinalizeStagedHands runs ~0.5s later at flush time.
LB.stagedHands = {}     -- [game] = { { player, net, outcome }, ... }
LB.recentDebtInfo = {}  -- [game] = { entries, fakePlay, at } from DebtLedger

local PENDING_CAP = 1000
local DEBT_INFO_WINDOW = 5  -- seconds a RecordDebts report stays bindable

-- Same never-trust-BJ.db-in-Initialize dance as DebtLedger (the
-- ADDON_LOADED name-mismatch gotcha).
function LB:EnsurePendingStore()
    if self.pendingStore then return self.pendingStore end
    if not BJ.db then
        ChairfacesCasinoDB = ChairfacesCasinoDB or {}
        BJ.db = ChairfacesCasinoDB
    end
    BJ.db.lbPending = BJ.db.lbPending or { hands = {} }
    BJ.db.lbPending.hands = BJ.db.lbPending.hands or {}
    self.pendingStore = BJ.db.lbPending
    return self.pendingStore
end

function LB:StageHand(game, player, net, outcome)
    self.stagedHands[game] = self.stagedHands[game] or {}
    table.insert(self.stagedHands[game], { player = player, net = net, outcome = outcome })
end

-- DebtLedger calls this from RecordDebts with the round's normalized debt
-- entries - or entries = {} and fakePlay = true for an off-the-books round.
function LB:OnDebtsRecorded(game, entries, fakePlay)
    game = DEBT_GAME_ALIAS[game] or game
    self.recentDebtInfo[game] = {
        entries = entries or {},
        fakePlay = fakePlay and true or false,
        at = GetTime(),
    }
end

-- The actual bucket write (the pre-gating body of RecordHandResult).
-- Only graduated hands reach this.
function LB:CommitHand(gameType, fullName, netGold, outcome)
    local recorder = myFullName()
    local row = self:GetRow(gameType, fullName)
    local b = row.buckets[recorder]
    if not b then
        b = { net = 0, games = 0, wins = 0, losses = 0, pushes = 0 }
        row.buckets[recorder] = b
    end
    b.net = b.net + netGold
    b.games = b.games + 1
    if outcome == "win" or outcome == "blackjack" then
        b.wins = b.wins + 1
    elseif outcome == "lose" or outcome == "bust" then
        b.losses = b.losses + 1
    elseif outcome == "push" then
        b.pushes = (b.pushes or 0) + 1
    end
    row.lastSync = time()

    self.dirtyRows[gameType] = self.dirtyRows[gameType] or {}
    self.dirtyRows[gameType][fullName] = true
    self:QueueSave()
end

-- Bind this settlement's staged hands to their debt pairs, or commit /
-- discard them. Runs at the top of FlushSync. If the ledger reported
-- nothing for the round (ledger disabled, odd state), fail OPEN and count
-- the hand like the pre-gating addon did - gating must never silently eat
-- honest results because of a plumbing hiccup.
function LB:FinalizeStagedHands()
    if not next(self.stagedHands) then return end
    local staged = self.stagedHands
    self.stagedHands = {}

    local DLedger = BJ.DebtLedger
    local ledgerUp = DLedger and DLedger.data and DLedger.PairKeyFor and DLedger.IsSquare
    local committed = false

    for game, hands in pairs(staged) do
        local info = self.recentDebtInfo[game]
        self.recentDebtInfo[game] = nil
        if info and (GetTime() - info.at) > DEBT_INFO_WINDOW then info = nil end

        for _, h in ipairs(hands) do
            if info and info.fakePlay then
                -- FREE PLAY: never reaches the shared board
            elseif math.abs(h.net) < 0.01 then
                self:CommitHand(game, h.player, h.net, h.outcome)
                committed = true
            elseif not info or not ledgerUp then
                self:CommitHand(game, h.player, h.net, h.outcome)
                committed = true
            else
                -- every pair from this settlement the player's gold touches
                local watch = {}
                local bound = false
                for _, d in ipairs(info.entries) do
                    if d.debtor == h.player or d.creditor == h.player then
                        bound = true
                        local key = DLedger:PairKeyFor(d.debtor, d.creditor)
                        -- a pair this settlement itself netted square is
                        -- already satisfied (offsets count as settled)
                        if not DLedger:IsSquare(key) then
                            local dup = false
                            for _, k in ipairs(watch) do
                                if k == key then dup = true break end
                            end
                            if not dup then watch[#watch + 1] = key end
                        end
                    end
                end
                if not bound or #watch == 0 then
                    self:CommitHand(game, h.player, h.net, h.outcome)
                    committed = true
                else
                    local store = self:EnsurePendingStore()
                    table.insert(store.hands, {
                        g = game, p = h.player, n = h.net, o = h.outcome,
                        k = watch, t = time(),
                    })
                    while #store.hands > PENDING_CAP do
                        table.remove(store.hands, 1)
                    end
                end
            end
        end
    end

    if committed then
        self:UpdateAllTimeUI()
    end
end

local function handWatchIndex(h, key)
    for i, k in ipairs(h.k or {}) do
        if k == key then return i end
    end
    return nil
end

-- A pair's balance cleared (payment, or offsetting results): pending hands
-- watching it drop that key, and hands with nothing left to wait on
-- graduate into the recorder's bucket.
function LB:OnPairSquare(pairKey)
    local store = self:EnsurePendingStore()
    if #store.hands == 0 then return end
    local i, committed = 1, false
    while i <= #store.hands do
        local h = store.hands[i]
        local idx = handWatchIndex(h, pairKey)
        if idx then table.remove(h.k, idx) end
        if idx and #h.k == 0 then
            table.remove(store.hands, i)
            self:CommitHand(h.g, h.p, h.n, h.o)
            committed = true
        else
            i = i + 1
        end
    end
    if committed then
        self:QueueFlush()
        self:UpdateAllTimeUI()
    end
end

-- The creditor forgave the pair: hands still waiting on it are voided.
-- Hands that already had this pair satisfied earlier keep their progress.
function LB:OnPairForgiven(pairKey)
    local store = self:EnsurePendingStore()
    if #store.hands == 0 then return end
    local i, dropped = 1, 0
    while i <= #store.hands do
        if handWatchIndex(store.hands[i], pairKey) then
            table.remove(store.hands, i)
            dropped = dropped + 1
        else
            i = i + 1
        end
    end
    if dropped > 0 then
        BJ:Debug("Leaderboard: " .. dropped .. " pending hand(s) voided by forgiveness")
    end
end

-- The local debt ledger was wiped: pending hands can never graduate.
function LB:OnLedgerReset()
    local store = self:EnsurePendingStore()
    if #store.hands > 0 then
        BJ:Print("|cff888888" .. #store.hands .. " unsettled leaderboard hand(s) dropped with the ledger.|r")
        store.hands = {}
    end
end

-- How many hands are waiting on settlement (for UI/debug)
function LB:GetPendingCount()
    local store = self:EnsurePendingStore()
    return #store.hands
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

-- Handle incoming messages.
-- Legacy stat payloads (STATS_RESP/STATS_BC/AT_UPD/SESS_UPD) are dropped:
-- they carry blended accumulator totals that overlap the bucket streams,
-- so ingesting them would re-introduce double counting. Old clients still
-- get answered in their own format; their hands enter the boards when the
-- recording host runs a bucket-aware version.
function LB:OnCommReceived(prefix, message, distribution, sender)
    if prefix ~= CHANNEL_PREFIX then return end

    local myName = BJ:MyName()
    local senderName = sender:match("^([^-]+)") or sender
    if senderName == myName then return end

    -- Serialized payloads first: everything after the first | is a blob
    -- (AceSerializer output must not go through strsplit)
    local msgType, payload = message:match("^([^|]+)|(.*)$")
    msgType = msgType or message

    -- Season-tagged all-time sync (2.5.4+). Payload is "<season>|<blob>".
    -- Drop anything from a different season so a reset stays reset.
    if msgType == MSG.BUCKETS_S or msgType == MSG.BUCKETS_ANY_S
        or msgType == MSG.DIGEST_S then
        local season, blob
        if payload then season, blob = payload:match("^(%d+)|(.*)$") end
        if tonumber(season) ~= LB.SEASON then return end
        if msgType == MSG.BUCKETS_S then
            self:HandleBuckets(senderName, blob, true)
        elseif msgType == MSG.BUCKETS_ANY_S then
            -- A digest REPLY relays any recorder's buckets, so only ingest
            -- it if we actually asked: we whispered this peer our digest
            -- (realm reconcile) or broadcast one to the group recently.
            -- Unsolicited R4s from realm strangers are dropped.
            if self:DigestPending(senderName) then
                self:HandleBuckets(senderName, blob, false)
            end
        else
            self:HandleDigestSeasoned(sender, senderName, blob)
        end
        return
    end

    -- Legacy unseasoned all-time buckets (B3/R3) are EMITTED for pre-2.5.4
    -- peers but no longer INGESTED: absorbing them would let an old client's
    -- pre-season board flow back in and undo the season reset. A pre-2.5.4
    -- peer's DIGEST (D3) is still ANSWERED (feeds them our data; we merge
    -- nothing from the reply).
    if msgType == MSG.BUCKETS or msgType == MSG.BUCKETS_ANY then
        return
    elseif msgType == MSG.DIGEST then
        self:HandleDigest(sender, senderName, payload)
        return
    end

    local parts = { strsplit("|", message) }

    if msgType == MSG.SESSION_BUCKET then
        self:HandleSessionBucket(senderName, parts)
    elseif msgType == MSG.STATS_REQUEST then
        -- Legacy peer requesting stats: answer in their format
        self:HandleStatsRequest(senderName)
    elseif msgType == MSG.SESSION_REQUEST then
        -- Someone is requesting party session data (answered in both formats)
        self:HandlePartySessionRequest(senderName)
    elseif msgType == MSG.CLEAR_DB then
        -- Someone is requesting we clear our DB (debug command)
        self:HandleClearDbCommand(sender)
    end
end

--[[
    ============================================
    BUCKET SYNC (flush, digest anti-entropy)
    ============================================
]]

-- Raw send helpers for serialized payloads
function LB:SendRaw(msg)
    local channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY" or nil)
    if channel then
        AceComm:SendCommMessage(CHANNEL_PREFIX, msg, channel)
    end
end

function LB:SendRawWhisper(target, msg)
    AceComm:SendCommMessage(CHANNEL_PREFIX, msg, "WHISPER", target)
end

-- Batch broadcast shortly after a settlement (a blackjack hand records
-- every seat back-to-back; one message carries them all)
function LB:QueueFlush()
    if self.flushQueued then return end
    self.flushQueued = true
    C_Timer.After(0.5, function()
        LB.flushQueued = false
        LB:FlushSync()
    end)
end

function LB:FlushSync()
    -- Marry this settlement's staged hands to their debt pairs first: any
    -- hand that commits here (zero-net, already-square, fail-open) lands in
    -- dirtyRows and rides THIS flush.
    self:FinalizeStagedHands()

    local dirty = self.dirtyRows
    local sessionDirty = self.sessionDirty
    self.dirtyRows = {}
    self.sessionDirty = false

    if not IsInGroup() and not IsInRaid() then return end
    local recorder = myFullName()

    -- My freshly-bumped buckets, one blob
    local mine = {}
    local any = false
    for gameType, rows in pairs(dirty) do
        for rowName in pairs(rows) do
            local row = self.allTimeData[gameType] and self.allTimeData[gameType][rowName]
            local b = row and row.buckets and row.buckets[recorder]
            if b then
                mine[gameType] = mine[gameType] or {}
                mine[gameType][rowName] = { [recorder] = b }
                any = true
            end
        end
    end
    if any then
        local blob = AceSerializer:Serialize(mine)
        self:SendRaw(MSG.BUCKETS .. "|" .. blob)                       -- pre-2.5.4 peers
        self:SendRaw(MSG.BUCKETS_S .. "|" .. LB.SEASON .. "|" .. blob) -- season-tagged
    end

    -- Legacy row totals so pre-bucket clients keep seeing updates
    for gameType, rows in pairs(dirty) do
        for rowName in pairs(rows) do
            local t = self:GetRowTotals(gameType, rowName)
            if t then
                self:Send(MSG.ALLTIME_UPDATE, gameType, rowName,
                    t.net, t.games, t.wins, t.losses)
            end
        end
    end

    if sessionDirty then
        self:BroadcastPartySessionUpdate()
    end
end

-- Merge a serialized bucket payload: { [game] = { [row] = { [recorder] = bucket } } }.
-- requireOwn: every recorder must be the sender (B3 — you may only push
-- buckets you author). Digest replies (R3) relay any recorder's buckets.
function LB:HandleBuckets(senderName, payload, requireOwn)
    if not payload or payload == "" then return end
    local ok, data = AceSerializer:Deserialize(payload)
    if not ok or type(data) ~= "table" then return end

    local changed = false
    for gameType, rows in pairs(data) do
        if VALID_GAMES[gameType] and type(rows) == "table" then
            for rowName, buckets in pairs(rows) do
                if type(rowName) == "string" and #rowName <= MAX_NAME_LEN
                    and type(buckets) == "table" then
                    for recorder, b in pairs(buckets) do
                        if type(recorder) == "string" and #recorder <= MAX_NAME_LEN + 7 then
                            local recShort = recorder:match("^([^-]+)") or recorder
                            local clean = sanitizeBucket(b)
                            if clean and (not requireOwn or recShort == senderName) then
                                if self:MergeBucket(gameType, rowName, recorder, clean) then
                                    changed = true
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    if changed then
        self:QueueSave()
        self:UpdateAllTimeUI()
        BJ:Debug("Leaderboard: merged buckets from " .. senderName)
    end
end

-- My digest: every bucket I hold keyed by version (games count).
function LB:BuildDigest()
    local dig = {}
    if not self.allTimeData then return dig end
    for gameType, rows in pairs(self.allTimeData) do
        if gameType ~= "myStats" and gameType ~= "fmt" and gameType ~= "season"
            and type(rows) == "table" then
            for rowName, row in pairs(rows) do
                if type(row) == "table" and row.buckets then
                    for recorder, b in pairs(row.buckets) do
                        dig[gameType] = dig[gameType] or {}
                        dig[gameType][rowName] = dig[gameType][rowName] or {}
                        dig[gameType][rowName][recorder] = b.games or 0
                    end
                end
            end
        end
    end
    return dig
end

-- Anti-entropy digest: every bucket I hold, by version (games count).
-- Broadcast on roster changes / manual sync; peers whisper back only the
-- buckets where their copy is strictly newer or mine is missing.
function LB:BroadcastDigest()
    if not IsInGroup() and not IsInRaid() then return end
    if not self.allTimeData then return end
    self.lastDigestBroadcast = GetTime()
    local blob = AceSerializer:Serialize(self:BuildDigest())
    self:SendRaw(MSG.DIGEST .. "|" .. blob)                       -- pre-2.5.4 peers
    self:SendRaw(MSG.DIGEST_S .. "|" .. LB.SEASON .. "|" .. blob) -- season-tagged
end

-- Did we recently ASK for buckets from this peer? True while a digest we
-- whispered them (realm reconcile) or broadcast to the group is fresh.
-- Gates R4 ingestion so strangers can't push us unsolicited board data.
local DIGEST_REPLY_WINDOW = 600
function LB:DigestPending(senderName)
    local now = GetTime()
    local whispered = self.digestSentTo[senderName]
    if whispered and (now - whispered) < DIGEST_REPLY_WINDOW then return true end
    return (now - (self.lastDigestBroadcast or 0)) < DIGEST_REPLY_WINDOW
        and (self.lastDigestBroadcast or 0) > 0
end

-- Build the "buckets you're missing or behind on" reply from a peer's digest.
local function digestReply(self, dig)
    local reply, any = {}, false
    for gameType, rows in pairs(self.allTimeData) do
        if gameType ~= "myStats" and gameType ~= "fmt" and gameType ~= "season"
            and type(rows) == "table" then
            for rowName, row in pairs(rows) do
                if type(row) == "table" and row.buckets then
                    for recorder, b in pairs(row.buckets) do
                        local theirs = dig[gameType] and dig[gameType][rowName]
                            and dig[gameType][rowName][recorder]
                        if not theirs or (b.games or 0) > theirs then
                            reply[gameType] = reply[gameType] or {}
                            reply[gameType][rowName] = reply[gameType][rowName] or {}
                            reply[gameType][rowName][recorder] = b
                            any = true
                        end
                    end
                end
            end
        end
    end
    return any and reply or nil
end

-- Season-tagged digest (D4): only same-season peers reach here. Reply with a
-- season-tagged bucket blob (R4) over whisper. Also used realm-wide: the
-- reconcile that Part-C's channel HELLO triggers rides this same path.
function LB:HandleDigestSeasoned(sender, senderName, payload)
    -- Separate cooldown from the legacy D3 handler: the two share a peer and
    -- both fire for one BroadcastDigest, so a shared map would let the (ignored)
    -- D3 reply throttle the D4 reply the peer actually ingests.
    self.lastSeasonedDigestReply = self.lastSeasonedDigestReply or {}
    local now = GetTime()
    if self.lastSeasonedDigestReply[senderName]
        and (now - self.lastSeasonedDigestReply[senderName]) < 30 then
        return
    end
    local ok, dig = AceSerializer:Deserialize(payload or "")
    if not ok or type(dig) ~= "table" then return end
    if not self.allTimeData then return end
    local reply = digestReply(self, dig)
    if reply then
        self.lastSeasonedDigestReply[senderName] = now
        self:SendRawWhisper(sender, MSG.BUCKETS_ANY_S .. "|" .. LB.SEASON .. "|"
            .. AceSerializer:Serialize(reply))
        BJ:Debug("Leaderboard: sent seasoned digest reply to " .. senderName)
    end
end

function LB:HandleDigest(sender, senderName, payload)
    -- Per-sender cooldown so roster churn can't turn digests into storms
    local now = GetTime()
    if self.lastDigestReply[senderName] and (now - self.lastDigestReply[senderName]) < 30 then
        return
    end

    local ok, dig = AceSerializer:Deserialize(payload or "")
    if not ok or type(dig) ~= "table" then return end
    if not self.allTimeData then return end

    local reply = {}
    local any = false
    for gameType, rows in pairs(self.allTimeData) do
        if gameType ~= "myStats" and gameType ~= "fmt" and type(rows) == "table" then
            for rowName, row in pairs(rows) do
                if type(row) == "table" and row.buckets then
                    for recorder, b in pairs(row.buckets) do
                        local theirs = dig[gameType] and dig[gameType][rowName]
                            and dig[gameType][rowName][recorder]
                        if not theirs or (b.games or 0) > theirs then
                            reply[gameType] = reply[gameType] or {}
                            reply[gameType][rowName] = reply[gameType][rowName] or {}
                            reply[gameType][rowName][recorder] = b
                            any = true
                        end
                    end
                end
            end
        end
    end

    if any then
        self.lastDigestReply[senderName] = now
        self:SendRawWhisper(sender, MSG.BUCKETS_ANY .. "|" .. AceSerializer:Serialize(reply))
        BJ:Debug("Leaderboard: sent digest reply to " .. senderName)
    end
end

-- Session totals for a player: sum of that row's recorder buckets
function LB:GetSessionTotals(rowName)
    local row = self.partySession.players[rowName]
    if not row or not row.buckets then return nil end
    local t = { net = 0, hands = 0 }
    for _, b in pairs(row.buckets) do
        t.net = t.net + (b.net or 0)
        t.hands = t.hands + (b.hands or 0)
    end
    return t
end

-- Broadcast my session recording. The bucket message (S3) carries only MY
-- OWN recorder bucket — the one thing this machine is authoritative for —
-- so receivers can replace it wholesale without double counting. The
-- legacy blended SESS_UPD follows for pre-bucket clients (they ignore S3).
function LB:BroadcastPartySessionUpdate()
    if not self.partySession.startTime or self.partySession.startTime == 0 then return end
    if not IsInGroup() and not IsInRaid() then return end

    local recorder = myFullName()
    local mineParts = {}
    local legacyParts = {}
    for name, row in pairs(self.partySession.players) do
        local b = row.buckets and row.buckets[recorder]
        if b and b.hands > 0 then
            table.insert(mineParts, name .. "," .. b.net .. "," .. b.hands)
        end
        local t = self:GetSessionTotals(name)
        if t and t.hands > 0 then
            table.insert(legacyParts, name .. "," .. t.net .. "," .. t.hands)
        end
    end

    if #mineParts > 0 then
        self:Send(MSG.SESSION_BUCKET, self.partySession.startTime, recorder,
            table.concat(mineParts, ";"))
    end
    if #legacyParts > 0 then
        self:Send(MSG.SESSION_UPDATE, "party", self.partySession.startTime,
            table.concat(legacyParts, ";"))
    end
end

-- Merge another recorder's session bucket. The bucket's version is the
-- pair (recorder's session start, hands): a fresh session supersedes a
-- stale one outright, and within one session hands only grows at its
-- single writer. Replays are no-ops either way.
function LB:HandleSessionBucket(senderName, parts)
    -- parts: MSG, startTime, recorder, playerStr
    local startTime = tonumber(parts[2]) or 0
    local recorder = parts[3]
    local playerStr = parts[4] or ""
    if not recorder or recorder == "" then return end

    -- Only the recorder may push its own session bucket
    local recShort = recorder:match("^([^-]+)") or recorder
    if recShort ~= senderName then return end

    if not IsInGroup() and not IsInRaid() then return end
    if not self.partySession.startTime or self.partySession.startTime == 0 then
        self:StartPartySession()
    end

    local changed = false
    for entry in playerStr:gmatch("[^;]+") do
        local name, net, hands = entry:match("([^,]+),([^,]+),([^,]+)")
        if name then
            local newNet = tonumber(net) or 0
            local newHands = tonumber(hands) or 0
            local row = self.partySession.players[name]
            if not row then
                row = { buckets = {}, lastUpdate = 0 }
                self.partySession.players[name] = row
            end
            local cur = row.buckets[recorder]
            if not cur or startTime > (cur.start or 0)
                or (startTime == (cur.start or 0) and newHands > cur.hands) then
                row.buckets[recorder] = { net = newNet, hands = newHands, start = startTime }
                row.lastUpdate = time()
                changed = true
            end
        end
    end

    if changed then
        BJ:Debug("Leaderboard: merged session bucket from " .. senderName)
        self:UpdateSessionUI("blackjack")
        self:UpdateSessionUI("poker")
        self:UpdateSessionUI("holdem")
        self:UpdateSessionUI("hilo")
    end
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

-- Clear all leaderboard data (debug function)
function LB:ClearAllData(broadcast)
    -- Clear all-time data (every tracked game)
    self:InitializeEmptyData()

    -- Clear party session
    self.partySession = {
        players = {},
        startTime = 0,
        partyId = nil,
    }

    -- Clear per-game session data
    for _, gameType in ipairs(LB.GAME_TYPES) do
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
    for _, gameType in ipairs(LB.GAME_TYPES) do
        self:UpdateSessionUI(gameType)
    end
    
    BJ:Debug("Leaderboard: Cleared all local data")
    print("|cffff9944[Casino]|r All leaderboard data cleared!")
    
    -- Broadcast to group if requested
    if broadcast and (IsInGroup() or IsInRaid()) then
        self:Send(MSG.CLEAR_DB)
        print("|cffff9944[Casino]|r Clear command sent to group members")
    end
end

-- Handle clear DB command from another player. Remote wipe is a debug
-- tool: honor it ONLY from allowlisted characters (same gate as /cc db).
-- Ungated, any group member could broadcast CLEAR_DB and destroy everyone's
-- myStats - which is local-only and never comes back from peers.
function LB:HandleClearDbCommand(sender)
    local short = sender:match("^([^-]+)") or sender
    if not (BJ.TestMode and BJ.TestMode.IsAuthorizedName
        and BJ.TestMode:IsAuthorizedName(short)) then
        BJ:Debug("Leaderboard: ignored CLEAR_DB from unauthorized " .. tostring(sender))
        return
    end
    BJ:Debug("Leaderboard: Received clear DB command from " .. sender)
    print("|cffff9944[Casino]|r Received clear command from " .. sender .. " - clearing local data...")

    -- Clear without re-broadcasting
    self:ClearAllData(false)
end

-- Handle stats request - send our stats
function LB:HandleStatsRequest(requester)
    if not self.allTimeData or not self.allTimeData.myStats then return end
    
    local myName = BJ:MyName()
    local myRealm = GetRealmName()
    local myFullName = myName .. "-" .. myRealm
    
    -- Send stats for each game type
    for _, gameType in ipairs(LB.GAME_TYPES) do
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

-- Request a full sync from the group: the digest makes peers whisper back
-- exactly the buckets we're missing or behind on (and our digest arriving
-- at THEIR machines via the same roster flow covers the other direction).
-- The legacy request keeps pre-bucket peers answered in their own format.
-- Runs from the "Sync Now" button (a hardware event), so the realm channel
-- HELLO can flush here. Works even when ungrouped: it announces to the realm.
function LB:RequestGroupSync()
    local grouped = IsInGroup() or IsInRaid()
    if grouped then
        self:Send(MSG.STATS_REQUEST)
        self:BroadcastDigest()
        C_Timer.After(0.5, function()
            LB:BroadcastMyStats()
        end)
    end

    -- Realm-wide: announce our season on the shared channel so ungrouped
    -- peers reconcile with us over whisper (15s floor guards against spam).
    self:QueueRealmHello(true)
    self:FlushRealmQueue()

    if grouped then
        BJ:Print("|cff88ff88Requesting leaderboard sync from your group and the realm...|r")
    else
        BJ:Print("|cff88ff88Announcing to the realm for a leaderboard sync...|r")
    end
end

-- Broadcast our stats to the group
function LB:BroadcastMyStats()
    if not self.allTimeData or not self.allTimeData.myStats then return end
    
    local myName = BJ:MyName()
    local myRealm = GetRealmName()
    local myFullName = myName .. "-" .. myRealm
    
    for _, gameType in ipairs(LB.GAME_TYPES) do
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
    REALM-WIDE ANTI-ENTROPY (Part C)

    Party/raid sync above only reaches your group. To sync the board across
    the whole server, we use the shared hidden "ChairfaceCasino" chat channel
    (TableFinder joins it at login) purely for DISCOVERY: a tiny season-tagged
    HELLO announces "a casino player is here on season N". Everything heavy
    then goes over addon WHISPER, which reaches any player on the realm and is
    NOT hardware-gated - so the actual bucket transfer reuses the same
    season-tagged digest/reply/merge as party sync.

    Channel sends ARE hardware-gated, so a HELLO is queued and flushed on a
    casino UI click (Sync Now / opening the board). Receiving a peer's HELLO
    schedules a throttled whisper of our digest to them (once per peer per
    15 min, staggered), and their reply merges only if the season matches.
]]

-- REALM_CHANNEL / LB_MARK are declared at the top of the file (Initialize
-- needs them too).
local realmQueue = {}
local lastHello = 0
local lastReconcile = {}                   -- per-peer whisper cooldown

local function realmChannelIndex()
    local idx = GetChannelName(REALM_CHANNEL)
    return (idx and idx > 0) and idx or nil
end

-- Queue a HELLO; flushed on the next casino UI hardware event. Automatic
-- callers throttle to 1 / 5 min; an explicit user action (force) still can't
-- announce more than once per 15s, so a Sync Now masher can't spam the channel.
function LB:QueueRealmHello(force)
    local now = GetTime()
    local floor = force and 15 or 300
    if (now - lastHello) < floor then return end
    lastHello = now
    -- The HELLO is idempotent - keep at most ONE queued. The ticker used to
    -- append a copy every tick, so hours of idling followed by one casino
    -- click dumped dozens of identical SendChatMessages onto the channel in
    -- a single frame (spam, and enough to trip the server chat throttle).
    realmQueue = { MSG.HELLO .. "|" .. LB.SEASON }
end

-- Flush queued channel sends. MUST be called from a hardware-event context
-- (a button OnClick) or the channel SendChatMessage is silently dropped.
function LB:FlushRealmQueue()
    local idx = realmChannelIndex()
    if not idx or #realmQueue == 0 then return end
    local q = realmQueue
    realmQueue = {}
    for _, m in ipairs(q) do
        -- '|' is a chat escape-code introducer (SendChatMessage errors on a
        -- bare pipe). Swap to '~' on the wire like TableFinder does over this
        -- same channel; the receiver swaps it back.
        SendChatMessage(LB_MARK .. m:gsub("%|", "~"), "CHANNEL", nil, idx)
    end
end

-- A peer announced on the channel. If we share a season, whisper them our
-- digest (throttled per peer, staggered) so they reply with what we lack.
function LB:OnRealmHello(sender, season)
    if tonumber(season) ~= LB.SEASON then return end
    local short = sender:match("^([^-]+)") or sender
    if short == BJ:MyName() then return end
    local now = GetTime()
    if lastReconcile[short] and (now - lastReconcile[short]) < 900 then return end
    lastReconcile[short] = now
    local target = sender
    C_Timer.After(math.random() * 8, function()
        LB:WhisperDigest(target)
    end)
end

-- Send our season-tagged digest to one player over whisper (realm-wide).
function LB:WhisperDigest(target)
    if not self.allTimeData then return end
    local short = tostring(target):match("^([^-]+)") or tostring(target)
    self.digestSentTo[short] = GetTime()
    local blob = AceSerializer:Serialize(self:BuildDigest())
    self:SendRawWhisper(target, MSG.DIGEST_S .. "|" .. LB.SEASON .. "|" .. blob)
    BJ:Debug("Leaderboard: whispered realm digest to " .. tostring(target))
end

--[[
    ============================================
    DATA ACCESS HELPERS
    ============================================
]]

-- Get sorted session leaderboard (rows summed from recorder buckets)
function LB:GetSessionLeaderboard(gameType)
    -- Use party session data (cumulative across all games)
    if not self.partySession or not self.partySession.players then
        return {}
    end

    local sorted = {}
    for name in pairs(self.partySession.players) do
        local t = self:GetSessionTotals(name)
        if t and t.hands > 0 then
            table.insert(sorted, {
                name = name,
                net = t.net,
                hands = t.hands,
            })
        end
    end

    table.sort(sorted, function(a, b) return a.net > b.net end)
    return sorted
end

-- Get sorted all-time leaderboard for a game type (rows summed from buckets)
function LB:GetAllTimeLeaderboard(gameType)
    if not self.allTimeData or not self.allTimeData[gameType] then
        return {}
    end

    local sorted = {}
    for name in pairs(self.allTimeData[gameType]) do
        local t = self:GetRowTotals(gameType, name)
        if t and t.games > 0 then
            table.insert(sorted, {
                name = name,
                net = t.net,
                games = t.games,
                wins = t.wins,
                losses = t.losses,
                pushes = t.pushes,
                lastSync = t.lastSync,
            })
        end
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
    for _, gameType in ipairs(LB.GAME_TYPES) do
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

-- Reset MY personal stats (the myStats detail panel) for one game, or all
-- games when gameType is nil. Deliberately does NOT touch the shared board
-- rows: every realm peer holds replicas of the recorder buckets, so a local
-- row delete just resurrects on the next digest exchange (no tombstones).
-- Only a season bump truly clears the shared board.
function LB:ResetMyData(gameType)
    if not self.allTimeData then return end

    local function fresh()
        return { net = 0, games = 0, wins = 0, losses = 0, pushes = 0, bestWin = 0, worstLoss = 0 }
    end
    if gameType then
        self.allTimeData.myStats[gameType] = fresh()
    else
        for _, g in ipairs(LB.GAME_TYPES) do
            self.allTimeData.myStats[g] = fresh()
        end
    end

    self:SaveToStorage()
    self:UpdateAllTimeUI()
    BJ:Print("|cffffd700Your personal stats were reset.|r The shared leaderboard rows are unaffected.")
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
