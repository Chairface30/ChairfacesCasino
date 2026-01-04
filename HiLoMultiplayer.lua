--[[
    Chairface's Casino - HiLoMultiplayer.lua
    Multiplayer communication for High-Lo game
    Uses AceComm for reliable message delivery
]]

local BJ = ChairfacesCasino
BJ.HiLoMultiplayer = {}
local HLM = BJ.HiLoMultiplayer

-- Get AceComm library
local AceComm = LibStub("AceComm-3.0")

-- Communication constants
local CHANNEL_PREFIX = "CCHiLo"

-- Message types
local MSG = {
    TABLE_OPEN = "OPEN",       -- Host opens table
    TABLE_CLOSE = "CLOSE",     -- Host closes table
    PLAYER_JOIN = "JOIN",      -- Player joins
    PLAYER_LEAVE = "LEAVE",    -- Player leaves
    START_ROLLING = "START",   -- Host starts rolling phase
    PLAYER_ROLLED = "ROLLED",  -- Player rolled (broadcast result)
    REROLL = "REROLL",         -- 2-player tie, need to reroll
    TIEBREAKER = "TIEBREAK",   -- Tiebreaker needed
    TIEBREAKER_ROLL = "TBROLL", -- Tiebreaker roll result
    SETTLEMENT = "SETTLE",     -- Final settlement
    RESET = "RESET",           -- Host resets the game
    VERSION_REJECT = "VREJECT", -- Host rejects player due to old version
}

-- State
HLM.isHost = false
HLM.currentHost = nil

-- Serialization helpers
local function serialize(...)
    local parts = {...}
    for i, v in ipairs(parts) do
        parts[i] = tostring(v)
    end
    return table.concat(parts, "|")
end

local function deserialize(msg)
    local parts = {}
    for part in string.gmatch(msg, "[^|]+") do
        table.insert(parts, part)
    end
    return parts
end

-- Initialize communication
function HLM:Initialize()
    -- Register AceComm callback for our prefix
    AceComm:RegisterComm(CHANNEL_PREFIX, function(prefix, message, distribution, sender)
        HLM:OnCommReceived(prefix, message, distribution, sender)
    end)
    
    -- Register for chat events to detect "1" joins and manual rolls
    local chatFrame = CreateFrame("Frame")
    chatFrame:RegisterEvent("CHAT_MSG_PARTY")
    chatFrame:RegisterEvent("CHAT_MSG_PARTY_LEADER")
    chatFrame:RegisterEvent("CHAT_MSG_RAID")
    chatFrame:RegisterEvent("CHAT_MSG_RAID_LEADER")
    chatFrame:SetScript("OnEvent", function(self, event, message, sender, ...)
        HLM:OnChatMessage(message, sender)
    end)
    
    -- Rolling phase timer state
    HLM.rollingTimerHandle = nil
    HLM.rollingTimerAnnounced = {}  -- Track which warnings we've sent
    
    BJ:Debug("High-Lo Multiplayer initialized with AceComm and chat listener")
end

-- Send a message to party/raid chat with [Casino] prefix
function HLM:SendChatMessage(message)
    local channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY" or nil)
    if channel then
        -- Prepend [Casino] to make it clear this is addon-generated
        SendChatMessage("[Casino] " .. message, channel)
    else
        -- Solo mode - just print locally
        BJ:Print("[Chat] " .. message)
    end
end

-- Handle incoming chat messages (for "1" joins)
function HLM:OnChatMessage(message, sender)
    -- Strip realm from sender name
    local senderName = sender:match("^([^-]+)") or sender
    local myName = UnitName("player")
    
    -- Don't process our own messages
    if senderName == myName then return end
    
    local HL = BJ.HiLoState
    
    -- Check for "1" to join during lobby phase
    if HL.phase == HL.PHASE.LOBBY and HLM.isHost then
        local trimmed = message:match("^%s*(.-)%s*$")  -- Trim whitespace
        if trimmed == "1" then
            -- Check if player already in game
            if not HL.players[senderName] then
                local success, err = HL:AddPlayer(senderName)
                if success then
                    BJ:Print("|cff00ff00" .. senderName .. " joined via chat!|r")
                    -- Announce in chat who joined
                    HLM:SendChatMessage(senderName .. " has joined the game!")
                    HLM:BroadcastPlayerJoined(senderName)
                    if BJ.UI and BJ.UI.HiLo then
                        BJ.UI.HiLo:UpdateDisplay()
                    end
                end
            end
        end
    end
end

-- Send message to group via AceComm (with compression)
function HLM:Send(msgType, ...)
    local args = {...}
    local msg
    
    -- For SYNC_STATE messages from host, automatically add version
    -- HiLo doesn't use SYNC_STATE the same way, but add support anyway
    if msgType == "SYNC" and HLM.isHost and BJ.StateSync then
        local version = BJ.StateSync:IncrementVersion("hilo")
        local syncType = args[1]
        table.remove(args, 1)
        msg = serialize(msgType, syncType, version, unpack(args))
    else
        msg = serialize(msgType, unpack(args))
    end
    
    local channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY" or nil)
    
    if channel then
        -- Compress if available
        local compressed, wasCompressed = msg, false
        if BJ.Compression and BJ.Compression.available then
            compressed, wasCompressed = BJ.Compression:Compress(msg)
        end
        
        AceComm:SendCommMessage(CHANNEL_PREFIX, compressed, channel)
        BJ:Debug("HiLo Sent: " .. (wasCompressed and "[compressed]" or msg))
    else
        -- Solo mode - just debug
        BJ:Debug("HiLo No group, message not sent: " .. msg)
    end
end

-- Send message to specific player via AceComm (with compression)
function HLM:SendWhisper(target, msgType, ...)
    local msg = serialize(msgType, ...)
    
    -- Compress if available
    local compressed, wasCompressed = msg, false
    if BJ.Compression and BJ.Compression.available then
        compressed, wasCompressed = BJ.Compression:Compress(msg)
    end
    
    AceComm:SendCommMessage(CHANNEL_PREFIX, compressed, "WHISPER", target)
    BJ:Debug("HiLo whisper to " .. target .. ": " .. (wasCompressed and "[compressed]" or msg))
end

-- Handle incoming AceComm messages
function HLM:OnCommReceived(prefix, message, distribution, sender)
    if prefix ~= CHANNEL_PREFIX then return end
    
    -- Handle realm name format
    local myName = UnitName("player")
    local senderName = sender:match("^([^-]+)") or sender
    if senderName == myName then return end
    
    -- Check for StateSync full state message first (before decompression)
    if BJ.StateSync and BJ.StateSync:IsFullStateMessage(message) then
        local stateData = BJ.StateSync:ExtractFullStateData(message)
        if stateData then
            BJ.StateSync:HandleFullState("hilo", stateData)
        end
        return
    end
    
    -- Check for StateSync request (host only)
    if BJ.StateSync and BJ.StateSync:IsSyncRequestMessage(message) then
        if HLM.isHost then
            local game = BJ.StateSync:ExtractSyncRequestGame(message)
            if game == "hilo" then
                BJ.StateSync:HandleSyncRequest("hilo", senderName)
            end
        end
        return
    end
    
    -- Check for discovery request (host responds)
    if BJ.StateSync and BJ.StateSync:IsDiscoveryMessage(message) then
        BJ.StateSync:HandleDiscoveryRequest("hilo", senderName)
        return
    end
    
    -- Check for host announcement (client learns about host)
    if BJ.StateSync and BJ.StateSync:IsHostAnnounceMessage(message) then
        local game, hostName, phase = message:match("HOSTANNOUN|(%w+)|([^|]+)|(.+)")
        if game == "hilo" then
            BJ.StateSync:HandleHostAnnounce("hilo", hostName, phase)
        end
        return
    end
    
    -- Decompress if needed
    if BJ.Compression then
        local decompressed = BJ.Compression:Decompress(message)
        if decompressed then
            message = decompressed
        elseif message:sub(1, 1) == "~" then
            BJ:Debug("Cannot decompress HiLo message from " .. sender)
            return
        end
    end
    
    local parts = deserialize(message)
    local msgType = parts[1]
    
    BJ:Debug("HiLo Received from " .. sender .. ": " .. message)
    
    -- Route to appropriate handler
    if msgType == MSG.TABLE_OPEN then
        self:HandleTableOpen(senderName, parts)
    elseif msgType == MSG.TABLE_CLOSE then
        self:HandleTableClose(senderName, parts)
    elseif msgType == MSG.PLAYER_JOIN then
        self:HandlePlayerJoin(senderName, parts)
    elseif msgType == MSG.PLAYER_LEAVE then
        self:HandlePlayerLeave(senderName, parts)
    elseif msgType == MSG.START_ROLLING then
        self:HandleStartRolling(senderName, parts)
    elseif msgType == MSG.PLAYER_ROLLED then
        self:HandlePlayerRolled(senderName, parts)
    elseif msgType == MSG.REROLL then
        self:HandleReroll(senderName, parts)
    elseif msgType == MSG.TIEBREAKER then
        self:HandleTiebreaker(senderName, parts)
    elseif msgType == MSG.TIEBREAKER_ROLL then
        self:HandleTiebreakerRoll(senderName, parts)
    elseif msgType == MSG.SETTLEMENT then
        self:HandleSettlement(senderName, parts)
    elseif msgType == MSG.RESET then
        self:HandleReset(senderName, parts)
    elseif msgType == MSG.VERSION_REJECT then
        self:HandleVersionReject(senderName, parts)
    elseif msgType == "REQUEST_STATE" then
        -- Someone just logged in/reloaded and is requesting state
        local requesterName = parts[2]
        local myName = UnitName("player")
        
        if HLM.isHost or HLM.temporaryHost == myName then
            if HLM:IsInRecoveryMode() then
                C_Timer.After(0.5, function()
                    HLM:Send("RECOVERY_STATE", HLM.originalHost, HLM.temporaryHost, 
                        HLM.RECOVERY_TIMEOUT - (time() - HLM.recoveryStartTime))
                end)
            elseif BJ.HiLoState.phase ~= BJ.HiLoState.PHASE.IDLE then
                C_Timer.After(0.5, function()
                    if BJ.StateSync then
                        BJ.StateSync:BroadcastFullState("hilo")
                    end
                end)
            end
        end
    elseif msgType == "RECOVERY_STATE" then
        local origHost = parts[2]
        local tempHost = parts[3]
        local remaining = tonumber(parts[4]) or 120
        local myName = UnitName("player")
        
        HLM.hostDisconnected = true
        HLM.originalHost = origHost
        HLM.temporaryHost = tempHost
        HLM.currentHost = origHost
        HLM.recoveryStartTime = time() - (HLM.RECOVERY_TIMEOUT - remaining)
        
        if origHost == myName then
            BJ:Print("|cff00ff00You have reconnected as host. Restoring game...|r")
            HLM:RestoreOriginalHost()
        else
            BJ:Print("|cffff8800High-Lo paused - waiting for " .. origHost .. " to return.|r")
            if BJ.UI and BJ.UI.HiLo and BJ.UI.HiLo.OnHostRecoveryStart then
                BJ.UI.HiLo:OnHostRecoveryStart(origHost, tempHost)
            end
        end
    elseif msgType == "HOST_TAKEOVER" then
        self:HandleHostTakeover(senderName, parts)
    elseif msgType == "HOST_TRANSFER" then
        self:HandleHostTransfer(senderName, parts)
    elseif msgType == "HOST_RECOVERY_START" then
        -- Legacy - now handled by HOST_TRANSFER
        self:HandleHostTransfer(senderName, parts)
    elseif msgType == "HOST_RECOVERY_TICK" then
        -- Legacy - no longer used
    elseif msgType == "HOST_RESTORED" then
        -- Legacy - no longer used, original host just rejoins as player
    elseif msgType == "GAME_VOIDED" then
        self:HandleGameVoided(senderName, parts)
    elseif msgType == "FULLSTATE" then
        -- Full state sync from StateSync system - route to StateSync handler
        local serializedData = table.concat(parts, "|", 2)  -- Rejoin all parts after FULLSTATE
        if BJ.StateSync then
            BJ.StateSync:HandleFullState("hilo", serializedData)
        end
    elseif msgType == "REQSYNC" then
        -- Sync request from StateSync system
        if HLM.isHost and BJ.StateSync then
            BJ.StateSync:HandleSyncRequest("hilo", senderName)
        end
    end
end

-- Handle host transfer (new permanent host)
function HLM:HandleHostTransfer(senderName, parts)
    local newHost = parts[2]
    local oldHost = parts[3]
    local myName = UnitName("player")
    
    BJ:Print("|cff00ff00" .. newHost .. " is now the High-Lo host.|r")
    
    HLM.currentHost = newHost
    HLM.hostDisconnected = false
    HLM.originalHost = nil
    HLM.temporaryHost = nil
    BJ.HiLoState.hostName = newHost
    
    if newHost == myName then
        HLM.isHost = true
    else
        HLM.isHost = false
    end
    
    if BJ.UI and BJ.UI.HiLo then
        BJ.UI.HiLo:UpdateDisplay()
    end
end

-- Handle host takeover (legacy - kept for compatibility)
function HLM:HandleHostTakeover(senderName, parts)
    local newHost = parts[2]
    local oldHost = parts[3]
    local myName = UnitName("player")
    
    BJ:Print("|cff00ff00" .. newHost .. " has taken over as High-Lo host!|r")
    
    HLM.currentHost = newHost
    HLM.hostDisconnected = false
    BJ.HiLoState.hostName = newHost
    
    if newHost == myName then
        HLM.isHost = true
    else
        HLM.isHost = false
    end
    
    if BJ.UI and BJ.UI.HiLo then
        BJ.UI.HiLo:UpdateDisplay()
    end
end

-- Handle host recovery start
-- Legacy handler - redirects to HandleHostTransfer
function HLM:HandleHostRecoveryStart(senderName, parts)
    -- Now just treated as a host transfer
    self:HandleHostTransfer(senderName, parts)
end

-- Legacy handler - no longer needed
function HLM:HandleHostRestored(senderName, parts)
    -- Original host just rejoins as a player, no special handling needed
end

-- Handle game voided
function HLM:HandleGameVoided(senderName, parts)
    local reason = parts[2] or "Unknown reason"
    
    BJ:Print("|cffff4444High-Lo VOIDED: " .. reason .. "|r")
    
    HLM.hostDisconnected = false
    HLM.originalHost = nil
    HLM.temporaryHost = nil
    HLM.recoveryStartTime = nil
    HLM.currentHost = nil
    HLM.isHost = false
    BJ.HiLoState:Reset()
    
    if BJ.UI and BJ.UI.HiLo and BJ.UI.HiLo.OnGameVoided then
        BJ.UI.HiLo:OnGameVoided(reason)
    end
end

--[[
    HOST ACTIONS
]]

-- Broadcast table open
function HLM:BroadcastTableOpen(maxRoll, joinTimer)
    HLM.isHost = true
    HLM.currentHost = UnitName("player")
    self:Send(MSG.TABLE_OPEN, maxRoll, joinTimer, BJ.version)
    
    -- Send chat announcement for players without addon
    local timerText = ""
    if joinTimer and joinTimer > 0 then
        timerText = " Joining closes in " .. joinTimer .. " seconds."
    end
    self:SendChatMessage("=== HIGH-LO GAME ===" .. timerText .. " Type 1 to join!")
end

-- Broadcast table close
function HLM:BroadcastTableClose()
    self:Send(MSG.TABLE_CLOSE)
    
    -- Send chat announcement
    self:SendChatMessage("=== HIGH-LO GAME CANCELLED ===")
    
    HLM.isHost = false
    HLM.currentHost = nil
    
    -- Cancel any timers
    self:CancelRollingTimer()
    self:CancelJoinTimer()
end

-- Broadcast reset (host only)
function HLM:BroadcastReset()
    if not HLM.isHost then return end
    self:Send(MSG.RESET)
    
    -- Send chat announcement
    self:SendChatMessage("=== HIGH-LO GAME RESET ===")
    
    -- Cancel any timers
    self:CancelRollingTimer()
    self:CancelJoinTimer()
    
    -- Reset local state
    local HL = BJ.HiLoState
    HL:Reset()
    HLM.isHost = false
    HLM.currentHost = nil
    
    BJ:Print("|cffff8800Game reset by host.|r")
    
    if BJ.UI and BJ.UI.HiLo then
        BJ.UI.HiLo:UpdateDisplay()
    end
end

-- Broadcast player joined (host confirms join)
function HLM:BroadcastPlayerJoined(playerName)
    self:Send(MSG.PLAYER_JOIN, playerName)
end

-- Broadcast start rolling
function HLM:BroadcastStartRolling()
    self:Send(MSG.START_ROLLING)
    
    local HL = BJ.HiLoState
    
    -- Send chat announcement
    self:SendChatMessage("=== ROLLING PHASE === Everyone /roll " .. HL.maxRoll .. " - You have 2 minutes!")
    
    -- Start rolling phase timer announcements
    self:StartRollingTimer()
end

-- Start rolling phase timer with announcements
function HLM:StartRollingTimer()
    -- Cancel any existing timer
    self:CancelRollingTimer()
    
    -- Reset announcement tracking
    HLM.rollingTimerAnnounced = {}
    HLM.rollingStartTime = time()
    
    local HL = BJ.HiLoState
    
    -- Create ticker that runs every second
    HLM.rollingTimerHandle = C_Timer.NewTicker(1, function()
        if HL.phase ~= HL.PHASE.ROLLING then
            HLM:CancelRollingTimer()
            return
        end
        
        local elapsed = time() - HLM.rollingStartTime
        local remaining = 120 - elapsed  -- 2 minutes = 120 seconds
        
        -- Announce at specific intervals
        if remaining <= 90 and not HLM.rollingTimerAnnounced["90"] then
            HLM.rollingTimerAnnounced["90"] = true
            HLM:SendChatMessage("1:30 remaining to /roll " .. HL.maxRoll)
        elseif remaining <= 60 and not HLM.rollingTimerAnnounced["60"] then
            HLM.rollingTimerAnnounced["60"] = true
            HLM:SendChatMessage("1 minute remaining to /roll " .. HL.maxRoll)
        elseif remaining <= 30 and not HLM.rollingTimerAnnounced["30"] then
            HLM.rollingTimerAnnounced["30"] = true
            HLM:SendChatMessage("30 seconds remaining to /roll " .. HL.maxRoll)
        elseif remaining <= 5 and remaining > 0 then
            -- 5 second countdown
            local key = tostring(remaining)
            if not HLM.rollingTimerAnnounced[key] then
                HLM.rollingTimerAnnounced[key] = true
                HLM:SendChatMessage(remaining .. "...")
            end
        elseif remaining <= 0 then
            HLM:CancelRollingTimer()
            -- Timeout handling is done in HiLoState.CheckTimeout
        end
    end, 120)  -- Max 120 ticks
end

-- Cancel rolling timer
function HLM:CancelRollingTimer()
    if HLM.rollingTimerHandle then
        HLM.rollingTimerHandle:Cancel()
        HLM.rollingTimerHandle = nil
    end
end

-- Start join timer with chat announcements
function HLM:StartJoinTimer(seconds)
    -- Cancel any existing timer
    self:CancelJoinTimer()
    
    -- Reset announcement tracking
    HLM.joinTimerAnnounced = {}
    HLM.joinStartTime = time()
    HLM.joinDuration = seconds
    
    local HL = BJ.HiLoState
    
    -- Create ticker that runs every second
    HLM.joinTimerHandle = C_Timer.NewTicker(1, function()
        if HL.phase ~= HL.PHASE.LOBBY then
            HLM:CancelJoinTimer()
            return
        end
        
        local elapsed = time() - HLM.joinStartTime
        local remaining = HLM.joinDuration - elapsed
        
        -- Announce at specific intervals
        if remaining <= 30 and not HLM.joinTimerAnnounced["30"] then
            HLM.joinTimerAnnounced["30"] = true
            HLM:SendChatMessage("30 seconds to join! Type 1 to join!")
        elseif remaining <= 5 and remaining > 0 then
            -- 5 second countdown
            local key = tostring(remaining)
            if not HLM.joinTimerAnnounced[key] then
                HLM.joinTimerAnnounced[key] = true
                HLM:SendChatMessage(remaining .. "...")
            end
        elseif remaining <= 0 then
            HLM:CancelJoinTimer()
            -- Auto-start rolling if enough players
            if #HL.playerOrder >= 2 then
                local success, err = HL:StartRolling()
                if success then
                    HLM:BroadcastStartRolling()
                    BJ:Print("Join timer expired - rolling phase started!")
                    if BJ.UI and BJ.UI.HiLo then
                        BJ.UI.HiLo:UpdateDisplay()
                    end
                end
            else
                HLM:SendChatMessage("Join timer expired but not enough players (need 2+). Game cancelled.")
                BJ:Print("Join timer expired but only " .. #HL.playerOrder .. " player(s). Game cancelled.")
                -- Cancel the game so anyone can host again
                HLM:BroadcastTableClose()
                HL:Reset()
                HLM.isHost = false
                HLM.currentHost = nil
                HLM.tableOpen = false
                -- Update UI to show HOST button
                if BJ.UI and BJ.UI.HiLo then
                    BJ.UI.HiLo:UpdateDisplay()
                end
            end
        end
    end, seconds + 5)  -- Extra buffer for safety
end

-- Cancel join timer
function HLM:CancelJoinTimer()
    if HLM.joinTimerHandle then
        HLM.joinTimerHandle:Cancel()
        HLM.joinTimerHandle = nil
    end
    HLM.joinTimerAnnounced = {}
end

-- Broadcast player rolled
function HLM:BroadcastPlayerRolled(playerName, roll)
    self:Send(MSG.PLAYER_ROLLED, playerName, roll)
end

-- Broadcast reroll (2-player tie)
function HLM:BroadcastReroll(tiedRoll)
    self:Send(MSG.REROLL, tiedRoll)
    
    -- Send chat announcement
    self:SendChatMessage("=== TIE! Both players rolled " .. tiedRoll .. " === Reroll needed! /roll 100")
end

-- Broadcast tiebreaker needed
function HLM:BroadcastTiebreaker(tiebreakerType, playersStr)
    self:Send(MSG.TIEBREAKER, tiebreakerType, playersStr)
    
    -- Send chat announcement
    local typeText = tiebreakerType == "high" and "HIGH" or "LOW"
    self:SendChatMessage("=== TIEBREAKER for " .. typeText .. " === " .. playersStr .. " must /roll 100")
end

-- Broadcast tiebreaker roll
function HLM:BroadcastTiebreakerRoll(playerName, roll)
    self:Send(MSG.TIEBREAKER_ROLL, playerName, roll)
end

-- Broadcast settlement
function HLM:BroadcastSettlement(highPlayer, highRoll, lowPlayer, lowRoll, winAmount)
    self:Send(MSG.SETTLEMENT, highPlayer, highRoll, lowPlayer, lowRoll, winAmount)
    
    -- Cancel any rolling timer
    self:CancelRollingTimer()
    
    -- Send chat settlement announcement
    self:SendChatMessage("=== GAME OVER ===")
    self:SendChatMessage(highPlayer .. " rolled " .. highRoll .. " (HIGH) - WINNER!")
    self:SendChatMessage(lowPlayer .. " rolled " .. lowRoll .. " (LOW) - LOSER")
    self:SendChatMessage(lowPlayer .. " owes " .. highPlayer .. " " .. winAmount .. "g (" .. highRoll .. " - " .. lowRoll .. " = " .. winAmount .. ")")
end

--[[
    CLIENT ACTIONS
]]

-- Request to join
function HLM:RequestJoin()
    -- Check version before joining
    if HLM.hostVersion and HLM.hostVersion ~= BJ.version then
        BJ:Print("|cffff4444Version mismatch!|r Host has v" .. HLM.hostVersion .. ", you have v" .. BJ.version)
        BJ:Print("Please update your addon to join this table.")
        return false
    end
    
    -- Send join request with version, host will confirm
    self:Send(MSG.PLAYER_JOIN, UnitName("player"), BJ.version)
    return true
end

--[[
    MESSAGE HANDLERS
]]

function HLM:HandleTableOpen(hostName, parts)
    local maxRoll = tonumber(parts[2]) or 100
    local joinTimer = tonumber(parts[3]) or 0
    local hostVersion = parts[4]  -- Host's addon version
    
    local HL = BJ.HiLoState
    
    -- Set up game state for client
    HL:Reset()
    HL.phase = HL.PHASE.LOBBY
    HL.hostName = hostName
    HL.maxRoll = maxRoll
    HL.joinTimer = joinTimer
    HL.lobbyStartTime = time()  -- Set for timer sync
    
    -- Host auto-joins
    HL:AddPlayer(hostName)
    
    HLM.isHost = false
    HLM.currentHost = hostName
    HLM.hostVersion = hostVersion  -- Store for version check on join
    
    local timerText = ""
    if joinTimer > 0 then
        timerText = " (Join timer: " .. joinTimer .. "s)"
    end
    local gameLink = BJ:CreateGameLink("hilo", "High-Lo")
    BJ:Print(hostName .. " opened a " .. gameLink .. " table! Max roll: " .. maxRoll .. timerText)
    
    -- Play game start sound (dice for High-Lo)
    PlaySoundFile("Interface\\AddOns\\Chairfaces Casino\\Sounds\\dice.mp3", "SFX")
    
    -- Update UI if open
    if BJ.UI and BJ.UI.HiLo and BJ.UI.HiLo.container and BJ.UI.HiLo.container:IsShown() then
        BJ.UI.HiLo:UpdateDisplay()
    end
end

function HLM:HandleTableClose(hostName, parts)
    local senderName = hostName:match("^([^-]+)") or hostName
    local currentHostName = HLM.currentHost and (HLM.currentHost:match("^([^-]+)") or HLM.currentHost)
    
    if senderName ~= currentHostName then return end
    
    BJ:Print("High-Lo table closed by host.")
    
    local HL = BJ.HiLoState
    HL:Reset()
    HLM.currentHost = nil
    HLM.tableOpen = false
    HLM.isHost = false
    
    -- Cancel any running join timer on clients
    HLM:CancelJoinTimer()
    
    if BJ.UI and BJ.UI.HiLo then
        BJ.UI.HiLo:UpdateDisplay()
    end
end

function HLM:HandlePlayerJoin(senderName, parts)
    local playerName = parts[2] or senderName
    local playerVersion = parts[3]  -- Player's addon version
    
    local HL = BJ.HiLoState
    
    if HLM.isHost then
        -- Version check
        if playerVersion and playerVersion ~= BJ.version then
            BJ:Print("|cffff8800" .. playerName .. " rejected - version mismatch|r (v" .. playerVersion .. " vs v" .. BJ.version .. ")")
            -- Need to get full sender name for whisper
            -- senderName is already the full name from OnCommReceived
            self:SendWhisper(senderName, MSG.VERSION_REJECT, BJ.version)
            return
        end
        
        -- Host receives join request - add player and broadcast confirmation
        local success = HL:AddPlayer(playerName)
        if success then
            BJ:Print(playerName .. " joined High-Lo!")
            -- Broadcast to all that player joined
            self:BroadcastPlayerJoined(playerName)
        end
    else
        -- Client receives confirmation - add player locally
        if not HL.players[playerName] then
            HL:AddPlayer(playerName)
        end
    end
    
    if BJ.UI and BJ.UI.HiLo then
        BJ.UI.HiLo:UpdateDisplay()
    end
end

function HLM:HandlePlayerLeave(senderName, parts)
    local playerName = parts[2] or senderName
    
    local HL = BJ.HiLoState
    HL:RemovePlayer(playerName)
    
    if BJ.UI and BJ.UI.HiLo then
        BJ.UI.HiLo:UpdateDisplay()
    end
end

function HLM:HandleVersionReject(senderName, parts)
    local hostVersion = parts[2]
    BJ:Print("|cffff4444Your addon version is outdated!|r")
    BJ:Print("Host has v" .. (hostVersion or "?") .. ", you have v" .. BJ.version)
    BJ:Print("Please update Chairface's Casino to join this table.")
    
    -- Show popup dialog
    StaticPopupDialogs["CASINO_HILO_VERSION_MISMATCH"] = {
        text = "|cffffd700Version Mismatch|r\n\nYour addon version (v" .. BJ.version .. ") is different from the host's version (v" .. (hostVersion or "?") .. ").\n\nPlease update Chairface's Casino to join this table.",
        button1 = "OK",
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    StaticPopup_Show("CASINO_HILO_VERSION_MISMATCH")
end

function HLM:HandleStartRolling(hostName, parts)
    local HL = BJ.HiLoState
    
    HL.phase = HL.PHASE.ROLLING
    HL.rollStartTime = time()
    
    BJ:Print("Rolling phase started! Everyone /roll " .. HL.maxRoll)
    
    if BJ.UI and BJ.UI.HiLo then
        BJ.UI.HiLo:UpdateDisplay()
    end
end

function HLM:HandleReroll(hostName, parts)
    local tiedRoll = tonumber(parts[2])
    
    local HL = BJ.HiLoState
    
    -- Reset all player rolls
    for _, name in ipairs(HL.playerOrder) do
        local player = HL.players[name]
        if player then
            player.rolled = false
            player.roll = nil
        end
    end
    
    HL.phase = HL.PHASE.ROLLING
    HL.rollStartTime = time()
    
    BJ:Print("|cffffd700TIE!|r Both players rolled " .. tiedRoll .. ". Everyone reroll /roll " .. HL.maxRoll .. "!")
    
    if BJ.UI and BJ.UI.HiLo then
        BJ.UI.HiLo:UpdatePlayerList()
        BJ.UI.HiLo:UpdateDisplay()
    end
end

function HLM:HandlePlayerRolled(hostName, parts)
    local playerName = parts[2]
    local roll = tonumber(parts[3])
    
    local HL = BJ.HiLoState
    local player = HL.players[playerName]
    
    if player and not player.rolled then
        player.rolled = true
        player.roll = roll
        
        if BJ.UI and BJ.UI.HiLo then
            BJ.UI.HiLo:UpdatePlayerList()
            BJ.UI.HiLo:UpdateDisplay()
            
            -- Play dice sound
            PlaySoundFile("Interface\\AddOns\\Chairfaces Casino\\Sounds\\dice.mp3", "SFX")
        end
    end
end

function HLM:HandleTiebreaker(hostName, parts)
    local tiebreakerType = parts[2]
    local playersStr = parts[3]
    
    local HL = BJ.HiLoState
    HL.phase = HL.PHASE.TIEBREAKER
    HL.tiebreakerType = tiebreakerType
    HL.tiebreakerPlayers = {}
    HL.tiebreakerRolls = {}
    
    -- Parse player list
    for name in playersStr:gmatch("[^,]+") do
        table.insert(HL.tiebreakerPlayers, name)
        HL.tiebreakerRolls[name] = nil
    end
    
    local typeText = tiebreakerType == "high" and "HIGH" or "LOW"
    BJ:Print("TIE for " .. typeText .. "! " .. playersStr .. " must /roll 100!")
    
    if BJ.UI and BJ.UI.HiLo then
        BJ.UI.HiLo:UpdateDisplay()
    end
end

function HLM:HandleTiebreakerRoll(hostName, parts)
    local playerName = parts[2]
    local roll = tonumber(parts[3])
    
    local HL = BJ.HiLoState
    
    if HL.tiebreakerRolls then
        HL.tiebreakerRolls[playerName] = roll
    end
    
    if BJ.UI and BJ.UI.HiLo then
        BJ.UI.HiLo:UpdateDisplay()
    end
end

function HLM:HandleSettlement(hostName, parts)
    local highPlayer = parts[2]
    local highRoll = tonumber(parts[3])
    local lowPlayer = parts[4]
    local lowRoll = tonumber(parts[5])
    local winAmount = tonumber(parts[6])
    
    local HL = BJ.HiLoState
    HL.phase = HL.PHASE.SETTLEMENT
    HL.highPlayer = highPlayer
    HL.highRoll = highRoll
    HL.lowPlayer = lowPlayer
    HL.lowRoll = lowRoll
    HL.winAmount = winAmount
    
    if BJ.UI and BJ.UI.HiLo then
        BJ.UI.HiLo:UpdateDisplay()
    end
end

function HLM:HandleReset(hostName, parts)
    -- Only accept from current host
    local currentHostName = HLM.currentHost and (HLM.currentHost:match("^([^-]+)") or HLM.currentHost)
    if hostName ~= currentHostName then return end
    
    BJ:Print("|cffff8800Game reset by host (" .. hostName .. ").|r")
    
    local HL = BJ.HiLoState
    HL:Reset()
    HLM.currentHost = nil
    
    if BJ.UI and BJ.UI.HiLo then
        BJ.UI.HiLo:UpdateDisplay()
    end
end

--[[
    HOST RECOVERY
    When the original host disconnects, game pauses with a 2-minute grace period.
    If host returns, they resume control. If not, game is voided.
]]

HLM.hostDisconnected = false
HLM.originalHost = nil
HLM.temporaryHost = nil
HLM.recoveryTimer = nil
HLM.recoveryStartTime = nil
HLM.RECOVERY_TIMEOUT = 120  -- 2 minutes

-- Check if host is still connected
function HLM:CheckHostConnection()
    local myName = UnitName("player")
    
    -- Check if WE are the original host who just reconnected
    if HLM.originalHost == myName and HLM.hostDisconnected then
        BJ:Print("|cff00ff00You have reconnected as host. Restoring game...|r")
        self:RestoreOriginalHost()
        return
    end
    
    if not HLM.currentHost then return end
    if HLM.isHost and not HLM.hostDisconnected then return end
    
    local HL = BJ.HiLoState
    if HL.phase == HL.PHASE.IDLE then return end
    
    local hostInGroup = UnitInParty(HLM.currentHost) or UnitInRaid(HLM.currentHost)
    local hostOnline = false
    
    if hostInGroup then
        local numMembers = GetNumGroupMembers()
        for i = 1, numMembers do
            local unit = IsInRaid() and ("raid" .. i) or ("party" .. i)
            local name = UnitName(unit)
            if name == HLM.currentHost then
                hostOnline = UnitIsConnected(unit)
                break
            end
        end
    end
    
    -- If host left the group entirely
    if not hostInGroup then
        BJ:Print("|cffff4444High-Lo host (" .. HLM.currentHost .. ") left the group.|r")
        self:VoidGame("Host left the group")
        return
    end
    
    -- If host is in group but offline - start recovery (transfer to new host)
    if not hostOnline and not HLM.hostDisconnected then
        HLM.hostDisconnected = true
        BJ:Print("|cffff8800High-Lo host (" .. HLM.currentHost .. ") disconnected!|r")
        self:StartHostRecovery()
    elseif hostOnline and HLM.hostDisconnected then
        -- Host came back - they just rejoin as player (host already transferred)
        HLM.hostDisconnected = false
    end
end

-- Determine temporary host
function HLM:DetermineTemporaryHost()
    local HL = BJ.HiLoState
    local myName = UnitName("player")
    
    for _, playerName in ipairs(HL.playerOrder or {}) do
        if playerName ~= HLM.currentHost then
            if playerName == myName then
                return myName
            end
            
            local numMembers = GetNumGroupMembers()
            for i = 1, numMembers do
                local unit = IsInRaid() and ("raid" .. i) or ("party" .. i)
                local name = UnitName(unit)
                if name == playerName and UnitIsConnected(unit) then
                    return playerName
                end
            end
        end
    end
    
    return nil
end

-- Start host recovery grace period
function HLM:StartHostRecovery()
    local myName = UnitName("player")
    
    HLM.originalHost = HLM.currentHost
    
    local newHost = self:DetermineTemporaryHost()
    
    if newHost == myName then
        -- We become the new permanent host
        HLM.currentHost = myName
        HLM.isHost = true
        BJ.HiLoState.hostName = myName
        
        self:Send("HOST_TRANSFER", myName, HLM.originalHost)
        
        BJ:Print("|cff00ff00You are now the host of High-Lo.|r")
    else
        -- Update to new host
        HLM.currentHost = newHost
        HLM.isHost = false
        BJ.HiLoState.hostName = newHost
        
        BJ:Print("|cff00ff00" .. newHost .. " is now the host of High-Lo.|r")
    end
    
    -- Clear recovery state - no waiting period needed
    HLM.hostDisconnected = false
    HLM.originalHost = nil
    
    if BJ.UI and BJ.UI.HiLo then
        BJ.UI.HiLo:UpdateDisplay()
    end
end

-- No longer needed - High-Lo does permanent host transfer instead of recovery
-- Keeping empty function for any legacy calls
function HLM:StartRecoveryCountdown()
    -- Not used - High-Lo transfers host permanently
end

-- Not used - original host just rejoins as player
function HLM:RestoreOriginalHost()
    -- Not used - High-Lo transfers host permanently
end

-- Void the game
function HLM:VoidGame(reason)
    BJ:Print("|cffff4444High-Lo VOIDED: " .. reason .. "|r")
    
    if HLM.recoveryTimer then
        HLM.recoveryTimer:Cancel()
        HLM.recoveryTimer = nil
    end
    
    if HLM.temporaryHost == UnitName("player") or HLM.isHost then
        self:Send("GAME_VOIDED", reason)
    end
    
    HLM.hostDisconnected = false
    HLM.temporaryHost = nil
    HLM.originalHost = nil
    HLM.recoveryStartTime = nil
    HLM.currentHost = nil
    HLM.isHost = false
    BJ.HiLoState:Reset()
    
    if BJ.UI and BJ.UI.HiLo and BJ.UI.HiLo.OnGameVoided then
        BJ.UI.HiLo:OnGameVoided(reason)
    end
end

-- Check if in recovery mode
function HLM:IsInRecoveryMode()
    return HLM.hostDisconnected and HLM.originalHost ~= nil
end

-- Register for roster updates and connection changes
local rosterFrame = CreateFrame("Frame")
rosterFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
rosterFrame:RegisterEvent("UNIT_CONNECTION")
rosterFrame:SetScript("OnEvent", function()
    HLM:CheckHostConnection()
end)

-- Initialize on load
HLM:Initialize()
