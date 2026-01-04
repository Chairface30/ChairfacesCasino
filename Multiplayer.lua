--[[
    Chairface's Casino - Multiplayer.lua
    Hidden addon channel communication and game state synchronization
    Uses AceComm for reliable message delivery
]]

local BJ = ChairfacesCasino
BJ.Multiplayer = {}
local MP = BJ.Multiplayer

-- Get AceComm library
local AceComm = LibStub("AceComm-3.0")
local AceSerializer = LibStub("AceSerializer-3.0")

-- Communication constants
local CHANNEL_PREFIX = "CCBlackjack"
local COMM_DELIMITER = "|"

-- Message types
local MSG = {
    -- Session messages
    SESSION_START = "SESS_START",   -- Host starts session with settings
    SESSION_END = "SESS_END",       -- Host ends session
    SESSION_RESET = "SESS_RESET",   -- Force reset stuck session
    
    -- Host messages
    TABLE_OPEN = "TOPEN",       -- Host opens table: ante
    TABLE_CLOSE = "TCLOSE",     -- Host closes table
    DEAL_START = "DEAL",        -- Host deals: seed
    COUNTDOWN = "CDOWN",        -- Countdown tick
    ACTION_ACK = "ACK",         -- Host acknowledges action
    SYNC_STATE = "SYNC",        -- Full state sync
    RESET = "RESET",            -- Host resets game
    VERSION_REJECT = "VREJECT", -- Host rejects player due to old version
    
    -- Player messages
    ANTE = "ANTE",              -- Player antes: amount (includes version)
    LEAVE = "LEAVE",            -- Player leaves
    HIT = "HIT",                -- Player hits: handIndex
    STAND = "STAND",            -- Player stands: handIndex
    DOUBLE = "DOUBLE",          -- Player doubles: handIndex
    SPLIT = "SPLIT",            -- Player splits: handIndex
}

-- State
MP.isHost = false
MP.currentHost = nil
MP.tableOpen = false
MP.pendingAnte = nil  -- Ante amount for pending table

-- Countdown state
MP.countdownActive = false
MP.countdownRemaining = 0
MP.countdownTimer = nil

-- Turn timer state (local only - each client manages their own timer)
MP.TURN_TIME_LIMIT = 60        -- 60 seconds per turn
MP.TURN_WARNING_TIME = 10      -- Show warning at 10 seconds
MP.turnTimerActive = false
MP.turnTimerRemaining = 0
MP.turnTimer = nil

-- Serialization helpers
local function serialize(...)
    local parts = {...}
    for i, v in ipairs(parts) do
        parts[i] = tostring(v)
    end
    return table.concat(parts, COMM_DELIMITER)
end

local function deserialize(msg)
    local parts = {}
    -- Use split that preserves empty fields
    local pos = 1
    while true do
        local delimPos = string.find(msg, COMM_DELIMITER, pos, true)
        if delimPos then
            table.insert(parts, string.sub(msg, pos, delimPos - 1))
            pos = delimPos + 1
        else
            table.insert(parts, string.sub(msg, pos))
            break
        end
    end
    return parts
end

-- Initialize communication
function MP:Initialize()
    -- Register AceComm callback for our prefix
    AceComm:RegisterComm(CHANNEL_PREFIX, function(prefix, message, distribution, sender)
        MP:OnCommReceived(prefix, message, distribution, sender)
    end)
    
    -- Register for group roster updates and connection changes
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("GROUP_ROSTER_UPDATE")
    frame:RegisterEvent("UNIT_CONNECTION")  -- Fires when player connects/disconnects
    frame:SetScript("OnEvent", function(self, event, ...)
        if event == "GROUP_ROSTER_UPDATE" or event == "UNIT_CONNECTION" then
            MP:OnRosterUpdate()
        end
    end)
    
    BJ:Debug("Multiplayer initialized with AceComm, prefix: " .. CHANNEL_PREFIX)
    
    -- Initialize compression
    if BJ.Compression and BJ.Compression.Initialize then
        BJ.Compression:Initialize()
    end
end

-- Send message to group via AceComm (with compression)
function MP:Send(msgType, ...)
    local args = {...}
    local msg
    
    -- For SYNC_STATE messages from host, automatically add version
    if msgType == MSG.SYNC_STATE and MP.isHost and BJ.StateSync then
        local version = BJ.StateSync:IncrementVersion("blackjack")
        -- Insert version after sync type (which is args[1])
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
            if wasCompressed then
                BJ:Debug("Compressed: " .. BJ.Compression:GetStats(msg, compressed))
            end
        end
        
        AceComm:SendCommMessage(CHANNEL_PREFIX, compressed, channel)
        BJ:Debug("Sent: " .. (wasCompressed and "[compressed]" or msg))
    else
        -- Solo mode for testing
        BJ:Debug("No group, message not sent: " .. msg)
    end
end

-- Send message to specific player via AceComm (with compression)
function MP:SendWhisper(target, msgType, ...)
    local msg = serialize(msgType, ...)
    
    -- Compress if available
    local compressed, wasCompressed = msg, false
    if BJ.Compression and BJ.Compression.available then
        compressed, wasCompressed = BJ.Compression:Compress(msg)
    end
    
    AceComm:SendCommMessage(CHANNEL_PREFIX, compressed, "WHISPER", target)
    BJ:Debug("Whisper to " .. target .. ": " .. (wasCompressed and "[compressed]" or msg))
end

-- Handle incoming AceComm messages
function MP:OnCommReceived(prefix, message, distribution, sender)
    if prefix ~= CHANNEL_PREFIX then return end
    
    -- Don't process our own messages (unless testing)
    local myName = UnitName("player")
    local senderName = sender:match("^([^-]+)") or sender
    if senderName == myName then return end
    
    -- Check for StateSync full state message first (before decompression)
    if BJ.StateSync and BJ.StateSync:IsFullStateMessage(message) then
        local stateData = BJ.StateSync:ExtractFullStateData(message)
        if stateData then
            BJ.StateSync:HandleFullState("blackjack", stateData)
        end
        return
    end
    
    -- Check for StateSync request (host only)
    if BJ.StateSync and BJ.StateSync:IsSyncRequestMessage(message) then
        if MP.isHost then
            local game = BJ.StateSync:ExtractSyncRequestGame(message)
            if game == "blackjack" then
                BJ.StateSync:HandleSyncRequest("blackjack", senderName)
            end
        end
        return
    end
    
    -- Check for discovery request (host responds)
    if BJ.StateSync and BJ.StateSync:IsDiscoveryMessage(message) then
        BJ.StateSync:HandleDiscoveryRequest("blackjack", senderName)
        return
    end
    
    -- Check for host announcement (client learns about host)
    if BJ.StateSync and BJ.StateSync:IsHostAnnounceMessage(message) then
        local game, hostName, phase = message:match("HOSTANNOUN|(%w+)|([^|]+)|(.+)")
        if game == "blackjack" then
            BJ.StateSync:HandleHostAnnounce("blackjack", hostName, phase)
        end
        return
    end
    
    -- Decompress if needed
    if BJ.Compression then
        local decompressed = BJ.Compression:Decompress(message)
        if decompressed then
            message = decompressed
        elseif message:sub(1, 1) == "~" then
            -- Compressed but can't decompress - skip message
            BJ:Debug("Cannot decompress message from " .. sender)
            return
        end
    end
    
    local parts = deserialize(message)
    local msgType = parts[1]
    
    BJ:Debug("Received from " .. sender .. ": " .. message)
    
    -- Route to appropriate handler
    if msgType == MSG.SESSION_START then
        self:HandleSessionStart(sender, parts)
    elseif msgType == MSG.SESSION_END then
        self:HandleSessionEnd(sender, parts)
    elseif msgType == MSG.SESSION_RESET then
        self:HandleSessionReset(sender, parts)
    elseif msgType == MSG.TABLE_OPEN then
        self:HandleTableOpen(sender, parts)
    elseif msgType == MSG.TABLE_CLOSE then
        self:HandleTableClose(sender, parts)
    elseif msgType == MSG.COUNTDOWN then
        self:HandleCountdown(sender, parts)
    elseif msgType == MSG.ANTE then
        self:HandleAnte(sender, parts)
    elseif msgType == MSG.LEAVE then
        self:HandleLeave(sender, parts)
    elseif msgType == MSG.DEAL_START then
        self:HandleDealStart(sender, parts)
    elseif msgType == MSG.HIT then
        self:HandleHit(sender, parts)
    elseif msgType == MSG.STAND then
        self:HandleStand(sender, parts)
    elseif msgType == MSG.DOUBLE then
        self:HandleDouble(sender, parts)
    elseif msgType == MSG.SPLIT then
        self:HandleSplit(sender, parts)
    elseif msgType == MSG.RESET then
        self:HandleReset(sender, parts)
    elseif msgType == MSG.SYNC_STATE then
        self:HandleSyncState(sender, parts)
    elseif msgType == MSG.VERSION_REJECT then
        self:HandleVersionReject(sender, parts)
    elseif msgType == "FULLSTATE" then
        -- Full state sync from StateSync system - route to StateSync handler
        local serializedData = table.concat(parts, "|", 2)  -- Rejoin all parts after FULLSTATE
        if BJ.StateSync then
            BJ.StateSync:HandleFullState("blackjack", serializedData)
        end
    elseif msgType == "REQSYNC" then
        -- Sync request from StateSync system
        if MP.isHost and BJ.StateSync then
            local requesterName = sender:match("^([^-]+)") or sender
            BJ.StateSync:HandleSyncRequest("blackjack", requesterName)
        end
    end
end

-- Handle roster changes
function MP:OnRosterUpdate()
    local GS = BJ.GameState
    local myName = UnitName("player")
    
    -- Check if WE are the original host who just reconnected
    if MP.originalHost == myName and MP.hostDisconnected then
        BJ:Print("|cff00ff00You have reconnected as host. Restoring game...|r")
        MP:RestoreOriginalHost()
        return
    end
    
    -- Skip if no current host set
    if not MP.currentHost then return end
    
    -- Skip if we are the active host (not in recovery)
    if MP.currentHost == myName and not MP.hostDisconnected then return end
    
    -- Skip if no active game (idle or already settled)
    if GS.phase == GS.PHASE.IDLE or GS.phase == GS.PHASE.SETTLEMENT then return end
    
    -- Check if host is still in group and online
    local hostInGroup = UnitInParty(MP.currentHost) or UnitInRaid(MP.currentHost)
    local hostOnline = false
    
    if hostInGroup then
        -- Check if host is online (not disconnected)
        local numMembers = GetNumGroupMembers()
        for i = 1, numMembers do
            local unit = IsInRaid() and ("raid" .. i) or ("party" .. i)
            local name = UnitName(unit)
            if name == MP.currentHost then
                hostOnline = UnitIsConnected(unit)
                break
            end
        end
    end
    
    -- If host left the group entirely, void the game
    if not hostInGroup then
        BJ:Print("|cffff4444Host (" .. MP.currentHost .. ") left the group.|r")
        MP:VoidGame("Host left the group")
        return
    end
    
    -- If host is in group but offline/disconnected during active game
    if not hostOnline and not MP.hostDisconnected then
        MP.hostDisconnected = true
        BJ:Print("|cffff8800Host (" .. MP.currentHost .. ") disconnected!|r")
        MP:StartHostRecovery()
    elseif hostOnline and MP.hostDisconnected then
        -- Host came back online - only temp host should trigger restore
        -- Other clients will receive HOST_RESTORED broadcast
        if MP.temporaryHost == myName then
            MP:CheckHostReturn()
        end
    end
end

-- Check if anyone can reset (host disconnected)
function MP:CanForceReset()
    return MP.hostDisconnected or not MP.currentHost
end

-- Reset multiplayer state
function MP:ResetState()
    MP.isHost = false
    MP.currentHost = nil
    MP.tableOpen = false
    MP.pendingAnte = nil
    BJ.GameState:Reset()
end

--[[
    HOST ACTIONS
]]

-- Broadcast session start
function MP:BroadcastSessionStart(settings)
    local settingsStr = BJ.HostSettings:Serialize()
    MP:Send(MSG.SESSION_START, settingsStr)
end

-- Broadcast session end
function MP:BroadcastSessionEnd()
    MP:Send(MSG.SESSION_END)
end

-- Broadcast session reset
function MP:BroadcastSessionReset()
    MP:Send(MSG.SESSION_RESET)
end

-- Host a new table using current settings
function MP:HostTable(settings)
    local inTestMode = BJ.TestMode and BJ.TestMode.enabled
    
    if not IsInGroup() and not inTestMode then
        BJ:Print("You must be in a party or raid to host a table.")
        return false
    end
    
    -- Save last hand results before clearing
    if BJ.GameState.phase == BJ.GameState.PHASE.SETTLEMENT then
        BJ.GameState:SaveLastHand()
    end
    
    -- Clear all animations from previous game
    if BJ.UI and BJ.UI.Animation and BJ.UI.Animation.ClearAllEffects then
        BJ.UI.Animation:ClearAllEffects()
    end
    
    -- Force clear session - we're the host starting a new hand
    BJ.SessionManager:ClearSession()
    
    -- Use provided settings or current host settings
    settings = settings or {
        ante = BJ.HostSettings:Get("ante"),
        maxMultiplier = BJ.HostSettings:Get("maxMultiplier"),
        countdownEnabled = BJ.HostSettings:Get("countdownEnabled"),
        countdownSeconds = BJ.HostSettings:Get("countdownSeconds"),
        maxPlayers = BJ.HostSettings:Get("maxPlayers") or 20,
        dealerHitsSoft17 = BJ.HostSettings:Get("dealerHitsSoft17"),
    }
    -- Ensure dealerHitsSoft17 has a default
    if settings.dealerHitsSoft17 == nil then
        settings.dealerHitsSoft17 = true  -- Default to H17
    end
    
    -- Validate settings
    local valid, errors = BJ.HostSettings:Validate()
    if not valid then
        for _, err in ipairs(errors) do
            BJ:Print("Error: " .. err)
        end
        return false
    end
    
    -- Start session
    local success, err = BJ.SessionManager:StartSession(UnitName("player"), settings)
    if not success then
        BJ:Print("Failed to start session: " .. (err or "unknown error"))
        return false
    end
    
    MP.isHost = true
    MP.currentHost = UnitName("player")
    MP.tableOpen = true
    
    -- Initialize game state (preserves shoe if same host continuing)
    local seed = time() + math.random(1, 100000)
    BJ.GameState:StartRound(MP.currentHost, settings.ante, seed, nil, settings.dealerHitsSoft17)
    BJ.GameState.maxMultiplier = settings.maxMultiplier
    BJ.GameState.maxPlayers = settings.maxPlayers
    
    -- Get cards remaining and reshuffle status after potential reshuffle
    local cardsRemaining = BJ.GameState:GetRemainingCards()
    local reshuffled = BJ.GameState.reshuffledThisRound and "1" or "0"
    
    -- Broadcast table open with settings, version, cards remaining, and reshuffle status
    local settingsStr = BJ.HostSettings:Serialize()
    MP:Send(MSG.TABLE_OPEN, settings.ante, seed, settingsStr, BJ.version, cardsRemaining, reshuffled)
    
    local maxPText = settings.maxPlayers < 20 and " | Max " .. settings.maxPlayers .. " players" or ""
    local ruleText = settings.dealerHitsSoft17 and "H17" or "S17"
    local gameLink = BJ:CreateGameLink("blackjack", "Blackjack")
    BJ:Print(gameLink .. " table opened! Ante: " .. settings.ante .. "g" ..
        (settings.maxMultiplier > 1 and " (up to " .. settings.maxMultiplier .. "x)" or "") ..
        " | " .. ruleText ..
        maxPText .. ". Waiting for players...")
    
    -- Auto-ante any existing fake players in test mode
    if BJ.TestMode and BJ.TestMode.enabled then
        BJ.TestMode:AnteAllFakePlayers()
    end
    
    -- Update UI
    if BJ.UI then
        BJ.UI:OnHostTable(settings)
    end
    
    -- Start countdown if enabled
    if settings.countdownEnabled then
        MP:StartCountdown(settings.countdownSeconds)
    end
    
    return true
end

-- Start betting countdown
function MP:StartCountdown(seconds)
    MP.countdownActive = true
    MP.countdownRemaining = seconds
    
    -- Cancel existing timer
    if MP.countdownTimer then
        MP.countdownTimer:Cancel()
    end
    
    -- Create countdown ticker
    MP.countdownTimer = C_Timer.NewTicker(1, function()
        MP.countdownRemaining = MP.countdownRemaining - 1
        
        -- Broadcast countdown to all clients
        MP:Send(MSG.COUNTDOWN, MP.countdownRemaining)
        
        if BJ.UI then
            BJ.UI:OnCountdownTick(MP.countdownRemaining)
        end
        
        if MP.countdownRemaining <= 0 then
            MP.countdownActive = false
            MP.countdownTimer:Cancel()
            MP.countdownTimer = nil
            
            -- Check if we have players
            if #BJ.GameState.playerOrder > 0 then
                -- Auto-deal if players are ready
                MP:Deal()
            else
                -- No players - close the table
                BJ:Print("|cffff4444Countdown ended with no players. Table closed.|r")
                MP:LeaveTable()
            end
        end
    end, seconds)
    
    BJ:Print("Betting closes in " .. seconds .. " seconds!")
end

-- Cancel countdown
function MP:CancelCountdown()
    if MP.countdownTimer then
        MP.countdownTimer:Cancel()
        MP.countdownTimer = nil
    end
    MP.countdownActive = false
    MP.countdownRemaining = 0
end

--[[
    TURN TIMER SYSTEM (Local Only)
    Each client tracks their own turn timer. When it's your turn, timer starts.
    At 10 seconds, warning appears. At 0 seconds, auto-stand is executed.
]]

-- Start turn timer (only if it's my turn)
function MP:StartTurnTimer()
    -- Cancel any existing timer
    MP:CancelTurnTimer()
    
    local GS = BJ.GameState
    local myName = UnitName("player")
    
    -- Only during player turns phase
    if GS.phase ~= GS.PHASE.PLAYER_TURNS and GS.phase ~= GS.PHASE.PLAYER_TURN then return end
    
    -- Check if it's my turn
    local currentPlayerName = GS.playerOrder[GS.currentPlayerIndex]
    if currentPlayerName ~= myName then return end
    
    MP.turnTimerRemaining = MP.TURN_TIME_LIMIT
    MP.turnTimerActive = true
    
    -- Start ticker
    MP.turnTimer = C_Timer.NewTicker(1, function()
        MP.turnTimerRemaining = MP.turnTimerRemaining - 1
        
        -- Show warning at 10 seconds
        if MP.turnTimerRemaining == MP.TURN_WARNING_TIME then
            BJ:Print("|cffff4444WARNING: " .. MP.TURN_WARNING_TIME .. " seconds to make a move or you will auto-stand!|r")
        end
        
        -- Update UI (show countdown at <= 10 seconds)
        if BJ.UI and BJ.UI.turnTimerFrame then
            if MP.turnTimerRemaining <= MP.TURN_WARNING_TIME and MP.turnTimerRemaining > 0 then
                BJ.UI.turnTimerFrame.text:SetText(MP.turnTimerRemaining)
                BJ.UI.turnTimerFrame:Show()
            else
                BJ.UI.turnTimerFrame:Hide()
            end
        end
        
        -- Timeout - auto-stand
        if MP.turnTimerRemaining <= 0 then
            MP:OnTurnTimeout()
        end
    end)
end

-- Cancel turn timer
function MP:CancelTurnTimer()
    if MP.turnTimer then
        MP.turnTimer:Cancel()
        MP.turnTimer = nil
    end
    MP.turnTimerActive = false
    MP.turnTimerRemaining = 0
    
    -- Hide timer UI
    if BJ.UI and BJ.UI.turnTimerFrame then
        BJ.UI.turnTimerFrame:Hide()
    end
end

-- Handle turn timeout - force stand
function MP:OnTurnTimeout()
    MP:CancelTurnTimer()
    
    local GS = BJ.GameState
    local myName = UnitName("player")
    
    -- Verify it's still my turn
    local currentPlayerName = GS.playerOrder[GS.currentPlayerIndex]
    if currentPlayerName ~= myName then return end
    
    BJ:Print("|cffff8800Your turn timed out - auto-standing.|r")
    
    -- Execute stand action using the correct method
    MP:Stand()
end

-- Close table / deal cards
function MP:Deal()
    if not MP.isHost then
        BJ:Print("Only the host can deal.")
        return false
    end
    
    if BJ.GameState.phase ~= BJ.GameState.PHASE.WAITING_FOR_PLAYERS then
        BJ:Print("Cannot deal right now.")
        return false
    end
    
    if #BJ.GameState.playerOrder == 0 then
        BJ:Print("No players have anted. Wait for players to join.")
        return false
    end
    
    -- Cancel any active countdown
    MP:CancelCountdown()
    
    -- Set flag to block test player actions until animation completes
    -- This must be set BEFORE DealInitialCards because that triggers hooks
    if BJ.UI then
        BJ.UI.isDealingAnimation = true
    end
    
    -- Deal cards
    local success, err = BJ.GameState:DealInitialCards()
    if not success then
        BJ:Print("Deal failed: " .. (err or "unknown error"))
        if BJ.UI then
            BJ.UI.isDealingAnimation = false
        end
        return false
    end
    
    -- Build full game state to sync
    -- Format: DEAL|seed|playerOrder|cardsRemaining|dealerCards~playerCards
    -- Where dealerCards = card1,card2 and playerCards = player1Cards;player2Cards;...
    -- Each card is rank:suit (e.g., "A:hearts")
    local GS = BJ.GameState
    local parts = { GS.seed }
    
    -- Player order (comma separated)
    table.insert(parts, table.concat(GS.playerOrder, ","))
    
    -- Cards remaining in shoe
    table.insert(parts, GS:GetRemainingCards())
    
    -- Dealer cards (comma separated)
    local dealerCards = {}
    for _, card in ipairs(GS.dealerHand) do
        table.insert(dealerCards, card.rank .. ":" .. card.suit)
    end
    table.insert(parts, table.concat(dealerCards, ","))
    
    -- Each player's cards (semicolon between players, comma between cards)
    local allPlayerCards = {}
    for _, playerName in ipairs(GS.playerOrder) do
        local player = GS.players[playerName]
        local hand = player.hands[1]
        local playerCards = {}
        for _, card in ipairs(hand) do
            table.insert(playerCards, card.rank .. ":" .. card.suit)
        end
        table.insert(allPlayerCards, table.concat(playerCards, ","))
    end
    table.insert(parts, table.concat(allPlayerCards, ";"))
    
    -- Add current player index (after blackjack skips)
    table.insert(parts, GS.currentPlayerIndex)
    
    -- Add player bets (comma separated, same order as playerOrder)
    local allBets = {}
    for _, playerName in ipairs(GS.playerOrder) do
        local player = GS.players[playerName]
        table.insert(allBets, player.bets[1] or GS.ante)
    end
    table.insert(parts, table.concat(allBets, ","))
    
    -- Add reshuffle flag so clients know to play shuffle animation
    table.insert(parts, GS.reshuffledThisRound and "1" or "0")
    
    -- Broadcast deal with full state
    MP:Send(MSG.DEAL_START, unpack(parts))
    
    BJ:Print("Cards dealt!")
    
    -- Update UI
    if BJ.UI then
        BJ.UI:OnCardsDealt()
    end
    
    return true
end

-- Leave table / close if host
function MP:LeaveTable()
    -- Cancel any countdown
    MP:CancelCountdown()
    
    if MP.isHost then
        MP:Send(MSG.TABLE_CLOSE)
        BJ:Print("Table closed.")
        
        -- End session
        BJ.SessionManager:EndSession()
    else
        MP:Send(MSG.LEAVE)
        BJ:Print("Left the table.")
    end
    
    MP:ResetState()
    
    if BJ.UI and BJ.UI.OnTableClosed then
        BJ.UI:OnTableClosed()
    end
end

--[[
    PLAYER ACTIONS
]]

-- Place ante
function MP:PlaceAnte(amount)
    if MP.isHost then
        -- Host is also a player
        local success, err = BJ.GameState:PlayerAnte(UnitName("player"), amount)
        if success then
            BJ:Print("You anted " .. amount .. "g")
            if BJ.UI then
                BJ.UI:OnAnteAccepted(amount)
            end
        else
            BJ:Print("Ante failed: " .. (err or "unknown"))
        end
        return success
    end
    
    if not MP.tableOpen then
        BJ:Print("No table is open.")
        return false
    end
    
    -- Check version before joining
    if MP.hostVersion and MP.hostVersion ~= BJ.version then
        BJ:Print("|cffff4444Version mismatch!|r Host has v" .. MP.hostVersion .. ", you have v" .. BJ.version)
        BJ:Print("Please update your addon to join this table.")
        return false
    end
    
    -- Send ante to host with version (use empty string for anteType, not nil)
    MP:Send(MSG.ANTE, amount, "", BJ.version)
    BJ:Print("Ante placed: " .. amount .. "g (waiting for confirmation)")
    return true
end

-- Add to existing bet
function MP:AddToBet(amount)
    local myName = UnitName("player")
    
    if MP.isHost then
        -- Host processes locally
        local success, newBet = BJ.GameState:AddToBet(myName, amount)
        if success then
            BJ:Print("Bet increased to " .. newBet .. "g")
            if BJ.UI then
                BJ.UI:UpdateDisplay()
            end
        else
            BJ:Print("Cannot add to bet: " .. (newBet or "unknown"))
        end
        return success
    end
    
    if not MP.tableOpen then
        BJ:Print("No table is open.")
        return false
    end
    
    -- Send add bet request to host
    MP:Send(MSG.ANTE, amount, "ADD")
    BJ:Print("Adding " .. amount .. "g to bet (waiting for confirmation)")
    return true
end

-- Player actions
function MP:Hit()
    -- Block actions during recovery
    if MP:IsInRecoveryMode() then
        BJ:Print("|cffff8800Game is paused - waiting for host to return.|r")
        return false
    end
    
    local GS = BJ.GameState
    local myName = UnitName("player")
    
    -- Check if this is a dealer hit (host during dealer turn)
    if MP.isHost and GS.phase == GS.PHASE.DEALER_TURN and GS:DealerNeedsAction() then
        local success, card, settled = GS:DealerHit()
        if success then
            MP:Send(MSG.SYNC_STATE, "DEALER_HIT", card.rank, card.suit)
            if BJ.UI then 
                BJ.UI:OnDealerHit(card)
                -- Wait for animation then check if settled or need more action
                C_Timer.After(1.0, function()
                    if settled or GS.phase == GS.PHASE.SETTLEMENT then
                        MP:SendSettlement()
                        if BJ.UI then BJ.UI:OnSettlement() end
                    else
                        BJ.UI:UpdateButtons()
                        BJ.UI:UpdateStatus()
                    end
                end)
            end
        end
        return success
    end
    
    -- Normal player hit
    if MP.isHost then
        -- Process locally
        local player = GS.players[myName]
        local handIndexBefore = player and player.activeHandIndex or 1
        
        local success, card = GS:PlayerHit(myName)
        if success then
            -- Check if busted
            local busted = player and player.outcomes[handIndexBefore] == GS.OUTCOME.BUST
            local newActiveHand = player and player.activeHandIndex or 1
            
            -- Broadcast with full sync info
            MP:Send(MSG.SYNC_STATE, "HIT", myName, card.rank, card.suit,
                handIndexBefore, busted and "BUST" or "", newActiveHand, GS.currentPlayerIndex)
            if BJ.UI then BJ.UI:OnPlayerHit(myName, card, handIndexBefore) end
            MP:CheckPhaseChange()
        end
        return success
    else
        MP:Send(MSG.HIT)
    end
    return true
end

-- Auto-dealer hit (called from UI:AutoPlayDealer)
function MP:AutoDealerHit()
    local GS = BJ.GameState
    
    if not MP.isHost then return false end
    if GS.phase ~= GS.PHASE.DEALER_TURN then return false end
    if not GS:DealerNeedsAction() then return false end
    
    local success, card, settled = GS:DealerHit()
    if success then
        MP:Send(MSG.SYNC_STATE, "DEALER_HIT", card.rank, card.suit)
        return true, card, settled
    end
    return false
end

function MP:Stand()
    -- Block actions during recovery
    if MP:IsInRecoveryMode() then
        BJ:Print("|cffff8800Game is paused - waiting for host to return.|r")
        return false
    end
    
    local GS = BJ.GameState
    local myName = UnitName("player")
    
    -- Check if this is dealer stand (host during dealer turn)
    if MP.isHost and GS.phase == GS.PHASE.DEALER_TURN then
        local success = GS:DealerStand()
        if success then
            MP:Send(MSG.SYNC_STATE, "DEALER_STAND")
            -- Dealer stood, should be in settlement now
            if GS.phase == GS.PHASE.SETTLEMENT then
                MP:SendSettlement()
                if BJ.UI then BJ.UI:OnSettlement() end
            end
        end
        return success
    end
    
    -- Normal player stand
    if MP.isHost then
        local success = GS:PlayerStand(myName)
        if success then
            MP:Send(MSG.SYNC_STATE, "STAND", myName, GS.currentPlayerIndex)
            if BJ.UI then BJ.UI:OnPlayerStand(myName) end
            MP:CheckPhaseChange()
        end
        return success
    else
        MP:Send(MSG.STAND)
    end
    return true
end

function MP:Double()
    -- Block actions during recovery
    if MP:IsInRecoveryMode() then
        BJ:Print("|cffff8800Game is paused - waiting for host to return.|r")
        return false
    end
    
    local myName = UnitName("player")
    if MP.isHost then
        local success, card = BJ.GameState:PlayerDouble(myName)
        if success then
            MP:Send(MSG.SYNC_STATE, "DOUBLE", myName, card.rank, card.suit, BJ.GameState.currentPlayerIndex)
            if BJ.UI then BJ.UI:OnPlayerDouble(myName, card) end
            MP:CheckPhaseChange()
        end
        return success
    else
        MP:Send(MSG.DOUBLE)
    end
    return true
end

function MP:Split(confirmed)
    -- Block actions during recovery
    if MP:IsInRecoveryMode() then
        BJ:Print("|cffff8800Game is paused - waiting for host to return.|r")
        return false
    end
    
    local myName = UnitName("player")
    local player = BJ.GameState.players[myName]
    
    -- Check if splitting aces - show warning if not confirmed
    if player and player.hands and player.hands[player.activeHandIndex] then
        local hand = player.hands[player.activeHandIndex]
        if #hand >= 2 and hand[1].rank == "A" and not confirmed then
            -- Show confirmation dialog for split aces
            StaticPopupDialogs["CASINO_SPLIT_ACES"] = {
                text = "|cffffd700Split Aces Warning|r\n\nWhen splitting Aces:\n• You receive only ONE card per hand\n• You cannot hit or double\n• 21 does NOT count as Blackjack\n• Wins pay 1:1 only\n\nProceed with split?",
                button1 = "Split",
                button2 = "Cancel",
                OnAccept = function()
                    MP:Split(true)  -- Call with confirmed=true
                end,
                timeout = 0,
                whileDead = true,
                hideOnEscape = true,
                preferredIndex = 3,
            }
            StaticPopup_Show("CASINO_SPLIT_ACES")
            return true
        end
    end
    
    if MP.isHost then
        local splitCard = nil
        if player and player.hands and player.hands[player.activeHandIndex] then
            local hand = player.hands[player.activeHandIndex]
            if #hand >= 2 then
                splitCard = hand[2]
            end
        end
        
        local success, card1, card2, isSplitAces = BJ.GameState:PlayerSplit(myName)
        if success then
            MP:Send(MSG.SYNC_STATE, "SPLIT", myName,
                splitCard.rank, splitCard.suit,
                card1.rank, card1.suit,
                card2.rank, card2.suit,
                isSplitAces and "1" or "0")
            if BJ.UI then BJ.UI:OnPlayerSplit(myName, card1, card2, isSplitAces) end
            
            -- For split aces, automatically stand on both hands after animation
            if isSplitAces then
                C_Timer.After(1.5, function()
                    -- Stand on first hand
                    if BJ.GameState.phase == BJ.GameState.PHASE.PLAYER_TURN then
                        MP:Stand()
                        -- Stand on second hand after first
                        C_Timer.After(0.5, function()
                            if BJ.GameState.phase == BJ.GameState.PHASE.PLAYER_TURN then
                                MP:Stand()
                            end
                        end)
                    end
                end)
            end
        end
        return success
    else
        MP:Send(MSG.SPLIT)
    end
    return true
end

function MP:Insurance(amount)
    local myName = UnitName("player")
    amount = amount or math.floor(BJ.GameState.players[myName].bets[1] / 2)
    
    if MP.isHost then
        local success = BJ.GameState:PlayerInsurance(myName, amount)
        if success then
            MP:Send(MSG.INSURANCE, myName, amount)
        end
        return success
    else
        MP:Send(MSG.INSURANCE, amount)
    end
    return true
end

--[[
    MESSAGE HANDLERS (Non-host clients)
]]

-- Session handlers
function MP:HandleSessionStart(sender, parts)
    local settingsStr = parts[2]
    local settings = BJ.HostSettings:Deserialize(settingsStr)
    BJ.SessionManager:OnRemoteSessionStart(sender, settings)
end

function MP:HandleSessionEnd(sender, parts)
    BJ.SessionManager:OnRemoteSessionEnd(sender)
end

function MP:HandleSessionReset(sender, parts)
    BJ:Print(sender .. " reset the session.")
    BJ.SessionManager:ClearSession()
    MP:ResetState()
    if BJ.UI and BJ.UI.OnTableClosed then
        BJ.UI:OnTableClosed()
    end
end

function MP:HandleCountdown(sender, parts)
    if sender ~= MP.currentHost then return end
    
    local remaining = tonumber(parts[2])
    MP.countdownRemaining = remaining
    
    if BJ.UI then
        BJ.UI:OnCountdownTick(remaining)
    end
end

function MP:HandleTableOpen(sender, parts)
    local ante = tonumber(parts[2])
    local seed = tonumber(parts[3])
    local settingsStr = parts[4]
    local hostVersion = parts[5]  -- Host's addon version
    local cardsRemaining = tonumber(parts[6])  -- Cards remaining in shoe
    local reshuffled = parts[7] == "1"  -- Whether host reshuffled
    
    -- Parse settings if provided
    local settings = {
        ante = ante,
        maxMultiplier = 1,
        countdownEnabled = false,
        countdownSeconds = 0,
    }
    
    if settingsStr then
        settings = BJ.HostSettings:Deserialize(settingsStr)
    end
    
    -- Update session manager
    BJ.SessionManager:OnRemoteSessionStart(sender, settings)
    
    -- Normalize sender name (strip server)
    local senderName = sender:match("^([^-]+)") or sender
    
    -- Check if same host continuing (preserve shoe state knowledge)
    local sameHost = MP.currentHost == senderName
    
    MP.currentHost = senderName
    MP.tableOpen = true
    MP.isHost = false
    MP.hostVersion = hostVersion  -- Store for version check on join
    
    -- Start round - clients don't have the actual shoe, just track remaining count
    BJ.GameState:StartRound(senderName, ante, seed, sameHost, settings.dealerHitsSoft17)
    BJ.GameState.maxMultiplier = settings.maxMultiplier
    BJ.GameState.maxPlayers = settings.maxPlayers or 20
    
    -- Sync reshuffle status from host (override client's local determination)
    BJ.GameState.reshuffledThisRound = reshuffled
    
    -- Store synced cards remaining from host
    if cardsRemaining then
        BJ.GameState.syncedCardsRemaining = cardsRemaining
    end
    
    local multText = ""
    if settings.maxMultiplier > 1 then
        multText = " (bet up to " .. settings.maxMultiplier .. "x)"
    end
    
    local maxPText = ""
    if settings.maxPlayers and settings.maxPlayers < 20 then
        maxPText = " | Max " .. settings.maxPlayers .. " players"
    end
    
    local ruleText = settings.dealerHitsSoft17 and "H17" or "S17"
    
    local gameLink = BJ:CreateGameLink("blackjack", "Blackjack")
    BJ:Print(senderName .. " opened a " .. gameLink .. " table! Ante: " .. ante .. "g" .. multText .. " | " .. ruleText .. maxPText)
    
    -- Play game start sound
    PlaySoundFile("Interface\\AddOns\\Chairfaces Casino\\Sounds\\chips.ogg", "SFX")
    
    if BJ.UI then
        BJ.UI:OnTableOpened(senderName, settings)
    end
end

function MP:HandleTableClose(sender, parts)
    if sender ~= MP.currentHost then return end
    
    BJ:Print("Table closed by host.")
    BJ.SessionManager:OnRemoteSessionEnd(sender)
    MP:ResetState()
    
    if BJ.UI and BJ.UI.OnTableClosed then
        BJ.UI:OnTableClosed()
    end
end

function MP:HandleAnte(sender, parts)
    if not MP.isHost then return end
    
    -- Normalize sender name (strip realm if present)
    local playerName = sender:match("^([^-]+)") or sender
    
    local amount = tonumber(parts[2])
    local anteType = parts[3]  -- nil for new ante, "ADD" for adding to bet
    local playerVersion = parts[4]  -- Player's addon version
    
    -- Version check for new antes (not for ADD)
    if anteType ~= "ADD" and playerVersion and playerVersion ~= BJ.version then
        BJ:Print("|cffff8800" .. playerName .. " rejected - version mismatch|r (v" .. playerVersion .. " vs v" .. BJ.version .. ")")
        -- Notify the player their version is outdated
        MP:SendWhisper(sender, MSG.VERSION_REJECT, BJ.version)
        return
    end
    
    if anteType == "ADD" then
        -- Adding to existing bet
        local success, newBet = BJ.GameState:AddToBet(playerName, amount)
        if success then
            BJ:Print(playerName .. " increased bet to " .. newBet .. "g")
            -- Broadcast the new total bet
            MP:Send(MSG.SYNC_STATE, "BET_UPDATE", playerName, newBet)
            if BJ.UI then BJ.UI:UpdateDisplay() end
        else
            BJ:Debug("Add bet from " .. playerName .. " rejected: " .. (newBet or "unknown"))
        end
    else
        -- New ante
        local success, err = BJ.GameState:PlayerAnte(playerName, amount)
        if success then
            BJ:Print(playerName .. " anted " .. amount .. "g")
            -- Broadcast confirmation to all
            MP:Send(MSG.SYNC_STATE, "ANTE", playerName, amount)
            if BJ.UI then BJ.UI:OnPlayerAnted(playerName, amount) end
        else
            BJ:Debug("Ante from " .. playerName .. " rejected: " .. (err or "unknown"))
        end
    end
end

function MP:HandleLeave(sender, parts)
    if not MP.isHost then return end
    
    -- Normalize sender name
    local playerName = sender:match("^([^-]+)") or sender
    
    -- Remove player from game (if not already dealt)
    if BJ.GameState.phase == BJ.GameState.PHASE.WAITING_FOR_PLAYERS then
        BJ.GameState.players[playerName] = nil
        for i, name in ipairs(BJ.GameState.playerOrder) do
            if name == playerName then
                table.remove(BJ.GameState.playerOrder, i)
                break
            end
        end
    end
    
    BJ:Print(playerName .. " left the table.")
    if BJ.UI then BJ.UI:OnPlayerLeft(playerName) end
end

function MP:HandleVersionReject(sender, parts)
    local hostVersion = parts[2]
    BJ:Print("|cffff4444Your addon version is outdated!|r")
    BJ:Print("Host has v" .. (hostVersion or "?") .. ", you have v" .. BJ.version)
    BJ:Print("Please update Chairface's Casino to join this table.")
    
    -- Show popup dialog
    StaticPopupDialogs["CASINO_VERSION_MISMATCH"] = {
        text = "|cffffd700Version Mismatch|r\n\nYour addon version (v" .. BJ.version .. ") is different from the host's version (v" .. (hostVersion or "?") .. ").\n\nPlease update Chairface's Casino to join this table.",
        button1 = "OK",
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    StaticPopup_Show("CASINO_VERSION_MISMATCH")
end

function MP:HandleDealStart(sender, parts)
    -- Normalize sender for comparison
    local senderName = sender:match("^([^-]+)") or sender
    local hostName = MP.currentHost and (MP.currentHost:match("^([^-]+)") or MP.currentHost)
    if senderName ~= hostName then return end
    
    local GS = BJ.GameState
    
    -- Parse the full game state
    -- Format: DEAL|seed|playerOrder|cardsRemaining|dealerCards|playerCards|currentPlayerIndex|playerBets|reshuffled
    local seed = tonumber(parts[2])
    local playerOrderStr = parts[3]
    local cardsRemaining = tonumber(parts[4])
    local dealerCardsStr = parts[5]
    local playerCardsStr = parts[6]
    local currentPlayerIdx = tonumber(parts[7]) or 1
    local playerBetsStr = parts[8]
    local reshuffledFlag = parts[9]
    
    -- Set reshuffle flag for animation
    GS.reshuffledThisRound = (reshuffledFlag == "1")
    
    -- Parse player bets into array first (before creating players)
    local playerBets = {}
    if playerBetsStr then
        for betStr in playerBetsStr:gmatch("[^,]+") do
            table.insert(playerBets, tonumber(betStr) or GS.ante)
        end
    end
    
    -- Store cards remaining
    GS.syncedCardsRemaining = cardsRemaining
    
    -- Parse player order and create players with correct bets
    GS.playerOrder = {}
    GS.players = {}
    local playerIdx = 1
    for name in playerOrderStr:gmatch("[^,]+") do
        table.insert(GS.playerOrder, name)
        local bet = playerBets[playerIdx] or GS.ante
        GS.players[name] = {
            hands = { {} },
            bets = { bet },
            insurance = 0,
            activeHandIndex = 1,
            outcomes = { GS.OUTCOME.PENDING },
            payouts = { 0 },
        }
        playerIdx = playerIdx + 1
    end
    
    -- Parse dealer cards
    GS.dealerHand = {}
    if dealerCardsStr then
        for cardStr in dealerCardsStr:gmatch("[^,]+") do
            local rank, suit = cardStr:match("([^:]+):(.+)")
            if rank and suit then
                table.insert(GS.dealerHand, { rank = rank, suit = suit })
            end
        end
    end
    
    -- Parse player cards
    if playerCardsStr then
        playerIdx = 1
        for playerHandStr in playerCardsStr:gmatch("[^;]+") do
            if playerIdx <= #GS.playerOrder then
                local playerName = GS.playerOrder[playerIdx]
                local hand = {}
                for cardStr in playerHandStr:gmatch("[^,]+") do
                    local rank, suit = cardStr:match("([^:]+):(.+)")
                    if rank and suit then
                        table.insert(hand, { rank = rank, suit = suit })
                    end
                end
                GS.players[playerName].hands[1] = hand
                
                -- Check for blackjack and mark outcome
                local score = GS:ScoreHand(hand)
                if score.isBlackjack then
                    GS.players[playerName].hasBlackjack = true
                    GS.players[playerName].outcomes[1] = GS.OUTCOME.BLACKJACK
                end
            end
            playerIdx = playerIdx + 1
        end
    end
    
    -- Set game phase - use host's currentPlayerIndex directly
    GS.seed = seed
    GS.phase = GS.PHASE.PLAYER_TURN
    GS.currentPlayerIndex = currentPlayerIdx
    GS.dealerHoleCardRevealed = false
    
    -- Start game log for client
    GS:StartGameLog()
    
    -- Debug output
    local currentPlayer = GS.playerOrder[currentPlayerIdx] or "?"
    BJ:Debug("Client received deal. Players: " .. #GS.playerOrder .. ", Current turn: " .. currentPlayer .. " (index " .. currentPlayerIdx .. "), Reshuffled: " .. tostring(GS.reshuffledThisRound))
    
    BJ:Print("Cards dealt! " .. currentPlayer .. "'s turn.")
    if BJ.UI then BJ.UI:OnCardsDealt() end
end

function MP:HandleHit(sender, parts)
    if MP.isHost then
        -- Normalize sender name first
        local playerName = sender:match("^([^-]+)") or sender
        local GS = BJ.GameState
        local player = GS.players[playerName]
        local handIndexBefore = player and player.activeHandIndex or 1
        local currentIdxBefore = GS.currentPlayerIndex
        
        -- Process action
        local success, card = GS:PlayerHit(playerName)
        if success then
            -- Check if busted (outcome changed)
            local busted = player and player.outcomes[handIndexBefore] == GS.OUTCOME.BUST
            local newActiveHand = player and player.activeHandIndex or 1
            
            -- Check if turn advanced (auto-stand on 21, bust, or 5-card charlie)
            local turnAdvanced = GS.currentPlayerIndex ~= currentIdxBefore
            
            -- Check if hit resulted in exactly 21 (auto-stand)
            local hand = player and player.hands[handIndexBefore]
            local score = hand and GS:ScoreHand(hand)
            local hitTo21 = score and score.total == 21 and not score.isBust
            
            -- Broadcast result with bust info, new hand index, and current player index
            -- Also include turnAdvanced flag so clients know to check for phase change
            MP:Send(MSG.SYNC_STATE, "HIT", playerName, card.rank, card.suit, 
                handIndexBefore, busted and "BUST" or (hitTo21 and "21" or ""), newActiveHand, GS.currentPlayerIndex)
            -- Pass handIndexBefore so animation goes to correct hand
            if BJ.UI then BJ.UI:OnPlayerHit(playerName, card, handIndexBefore) end
            
            -- Check for phase change
            MP:CheckPhaseChange()
        end
    else
        -- Non-host receives broadcast via SYNC_STATE
    end
end

function MP:HandleStand(sender, parts)
    if MP.isHost then
        local playerName = sender:match("^([^-]+)") or sender
        local success = BJ.GameState:PlayerStand(playerName)
        if success then
            -- Include current player index for sync
            MP:Send(MSG.SYNC_STATE, "STAND", playerName, BJ.GameState.currentPlayerIndex)
            if BJ.UI then BJ.UI:OnPlayerStand(playerName) end
            MP:CheckPhaseChange()
        end
    end
end

function MP:HandleDouble(sender, parts)
    if MP.isHost then
        local playerName = sender:match("^([^-]+)") or sender
        local success, card = BJ.GameState:PlayerDouble(playerName)
        if success then
            -- Include current player index for sync
            MP:Send(MSG.SYNC_STATE, "DOUBLE", playerName, card.rank, card.suit, BJ.GameState.currentPlayerIndex)
            if BJ.UI then BJ.UI:OnPlayerDouble(playerName, card) end
            MP:CheckPhaseChange()
        end
    end
end

function MP:HandleSplit(sender, parts)
    if MP.isHost then
        local playerName = sender:match("^([^-]+)") or sender
        local player = BJ.GameState.players[playerName]
        
        -- Get the split card before splitting (for sync)
        local splitCard = nil
        if player and player.hands and player.hands[player.activeHandIndex] then
            local hand = player.hands[player.activeHandIndex]
            if #hand >= 2 then
                splitCard = hand[2]  -- The card that will be split off
            end
        end
        
        local success, card1, card2 = BJ.GameState:PlayerSplit(playerName)
        if success then
            -- Send: playerName, splitCard (the card that was split), card1 (new card for hand1), card2 (new card for hand2)
            MP:Send(MSG.SYNC_STATE, "SPLIT", playerName, 
                splitCard.rank, splitCard.suit,
                card1.rank, card1.suit, 
                card2.rank, card2.suit)
            if BJ.UI then BJ.UI:OnPlayerSplit(playerName, card1, card2) end
        end
    end
end

-- Broadcast reset to all clients
function MP:BroadcastReset()
    if not MP.isHost then return end
    MP:Send(MSG.RESET)
end

-- Handle reset from host
function MP:HandleReset(sender, parts)
    -- Only accept from host
    local senderName = sender:match("^([^-]+)") or sender
    local hostName = MP.currentHost and (MP.currentHost:match("^([^-]+)") or MP.currentHost)
    if senderName ~= hostName then return end
    
    BJ:Print("Game reset by host.")
    BJ.SessionManager:EndSession()
    MP:ResetState()
    BJ.GameState:Reset()
    if BJ.UI then
        -- Cancel any ongoing animations
        if BJ.UI.Animation and BJ.UI.Animation.ClearQueue then
            BJ.UI.Animation:ClearQueue()
        end
        BJ.UI.isDealingAnimation = false
        
        BJ.UI.dealtCards = {}
        BJ.UI.dealerDealtCards = 0
        -- Hide countdown frame
        if BJ.UI.countdownFrame then
            BJ.UI.countdownFrame:Hide()
        end
        -- Hide settlement panel
        if BJ.UI.settlementPanel then
            BJ.UI.settlementPanel:Hide()
        end
        BJ.UI:UpdateDisplay()
    end
end

function MP:HandleSyncState(sender, parts)
    -- Normalize sender for comparison
    local senderName = sender:match("^([^-]+)") or sender
    local hostName = MP.currentHost and (MP.currentHost:match("^([^-]+)") or MP.currentHost)
    if senderName ~= hostName then return end
    
    local syncType = parts[2]
    local version = tonumber(parts[3]) or 0
    
    -- Validate version (if StateSync is available)
    if BJ.StateSync and version > 0 then
        local valid = BJ.StateSync:ValidateVersion("blackjack", version, hostName)
        if not valid then
            -- Gap detected, sync request sent, ignore this message
            BJ:Debug("Blackjack: Ignoring sync v" .. version .. " due to gap")
            return
        end
    end
    
    -- Parts shift by 1 because version is now at index 3
    -- Old: SYNC|type|data...
    -- New: SYNC|type|version|data...
    
    if syncType == "ANTE" then
        local playerName = parts[4]
        local amount = tonumber(parts[5])
        BJ.GameState:PlayerAnte(playerName, amount)
        if BJ.UI then BJ.UI:OnPlayerAnted(playerName, amount) end
        
    elseif syncType == "BET_UPDATE" then
        local playerName = parts[4]
        local newBet = tonumber(parts[5])
        local player = BJ.GameState.players[playerName]
        if player then
            player.bets[1] = newBet
            if BJ.UI then BJ.UI:UpdateDisplay() end
        end
        
    elseif syncType == "HIT" then
        local playerName = parts[4]
        local card = { rank = parts[5], suit = parts[6] }
        local handIndex = tonumber(parts[7]) or 1
        local hitStatus = parts[8]  -- "BUST", "21", or ""
        local newActiveHand = tonumber(parts[9]) or 1
        local newCurrentPlayerIdx = tonumber(parts[10])
        
        -- Sync the hit
        local player = BJ.GameState.players[playerName]
        if player then
            -- Make sure we're adding to the correct hand
            if player.hands[handIndex] then
                table.insert(player.hands[handIndex], card)
            end
            
            -- If busted, mark the outcome
            if hitStatus == "BUST" then
                player.outcomes[handIndex] = BJ.GameState.OUTCOME.BUST
            end
            
            -- Update active hand index
            player.activeHandIndex = newActiveHand
            
            -- Log action for history
            BJ.GameState:LogAction(playerName, "HIT", BJ.GameState:CardToString(card))
            
            -- If hit to 21, also log the auto-stand
            if hitStatus == "21" then
                BJ.GameState:LogAction(playerName, "STAND", "auto-stand at 21")
            end
            
            -- Pass handIndex so animation goes to correct hand
            if BJ.UI then BJ.UI:OnPlayerHit(playerName, card, handIndex) end
        end
        
        -- Update current player index (for turn changes after bust or auto-stand)
        if newCurrentPlayerIdx then
            BJ.GameState.currentPlayerIndex = newCurrentPlayerIdx
            if BJ.UI then
                BJ.UI:UpdateButtons()
                BJ.UI:UpdateStatus()
            end
        end
        
    elseif syncType == "STAND" then
        local playerName = parts[4]
        local nextPlayerIdx = tonumber(parts[5])
        -- Log action for history
        BJ.GameState:LogAction(playerName, "STAND", "")
        -- Advance to next player
        if nextPlayerIdx then
            BJ.GameState.currentPlayerIndex = nextPlayerIdx
        end
        if BJ.UI then 
            BJ.UI:OnPlayerStand(playerName)
            BJ.UI:UpdateDisplay()
        end
        
    elseif syncType == "DOUBLE" then
        local playerName = parts[4]
        local card = { rank = parts[5], suit = parts[6] }
        local nextPlayerIdx = tonumber(parts[7])
        local player = BJ.GameState.players[playerName]
        if player then
            player.bets[player.activeHandIndex] = player.bets[player.activeHandIndex] * 2
            table.insert(player.hands[player.activeHandIndex], card)
            -- Log action for history
            BJ.GameState:LogAction(playerName, "DOUBLE", BJ.GameState:CardToString(card))
            if nextPlayerIdx then
                BJ.GameState.currentPlayerIndex = nextPlayerIdx
            end
            if BJ.UI then BJ.UI:OnPlayerDouble(playerName, card) end
        end
        
    elseif syncType == "SPLIT" then
        local playerName = parts[4]
        local splitCard = { rank = parts[5], suit = parts[6] }
        local card1 = { rank = parts[7], suit = parts[8] }
        local card2 = { rank = parts[9], suit = parts[10] }
        local isSplitAces = parts[11] == "1"
        -- Update player state for split
        local player = BJ.GameState.players[playerName]
        if player then
            local handIndex = player.activeHandIndex
            local hand = player.hands[handIndex]
            if hand and #hand >= 2 then
                -- Remove the split card from first hand
                table.remove(hand, 2)
                -- Create new hand with the split card
                local newHand = { splitCard }
                table.insert(player.hands, handIndex + 1, newHand)
                table.insert(player.bets, handIndex + 1, player.bets[handIndex])
                table.insert(player.outcomes, handIndex + 1, BJ.GameState.OUTCOME.PENDING)
                table.insert(player.payouts, handIndex + 1, 0)
                -- Add new cards to each hand
                table.insert(hand, card1)
                table.insert(newHand, card2)
                -- Track split aces
                if isSplitAces then
                    player.splitAcesHands = player.splitAcesHands or {}
                    player.splitAcesHands[handIndex] = true
                    player.splitAcesHands[handIndex + 1] = true
                end
            end
            -- Log action for history
            BJ.GameState:LogAction(playerName, "SPLIT", "")
        end
        if BJ.UI then BJ.UI:OnPlayerSplit(playerName, card1, card2, isSplitAces) end
        
    elseif syncType == "DEALER_TURN" then
        -- Cancel turn timer - player turns are over
        MP:CancelTurnTimer()
        BJ.GameState.phase = BJ.GameState.PHASE.DEALER_TURN
        BJ.GameState.dealerHoleCardRevealed = true
        -- Log dealer reveal
        BJ.GameState:LogDealerAction("REVEAL", BJ.GameState:FormatHand(BJ.GameState.dealerHand))
        if BJ.UI then BJ.UI:OnDealerTurn() end
        
    elseif syncType == "DEALER_HIT" then
        local card = { rank = parts[4], suit = parts[5] }
        table.insert(BJ.GameState.dealerHand, card)
        -- Log dealer hit
        BJ.GameState:LogDealerAction("HIT", BJ.GameState:CardToString(card))
        if BJ.UI then BJ.UI:OnDealerHit(card) end
        
    elseif syncType == "SETTLEMENT" then
        -- Parse settlement data
        -- Format: player1:outcome1,outcome2:payout1,payout2;player2:...
        local settlementStr = parts[4]
        if settlementStr then
            for playerData in settlementStr:gmatch("[^;]+") do
                local playerName, outcomesStr, payoutsStr = playerData:match("([^:]+):([^:]+):(.+)")
                if playerName then
                    local player = BJ.GameState.players[playerName]
                    if player then
                        -- Parse outcomes
                        local i = 1
                        for outcome in outcomesStr:gmatch("[^,]+") do
                            player.outcomes[i] = tonumber(outcome) or 0
                            i = i + 1
                        end
                        -- Parse payouts
                        i = 1
                        for payout in payoutsStr:gmatch("[^,]+") do
                            player.payouts[i] = tonumber(payout) or 0
                            i = i + 1
                        end
                    end
                end
            end
        end
        -- Build settlements and ledger for display
        BJ.GameState:BuildSettlementFromSync()
        BJ.GameState.phase = BJ.GameState.PHASE.SETTLEMENT
        -- Save to game history for client
        BJ.GameState:SaveGameToHistory()
        if BJ.UI then 
            BJ.UI:OnSettlement()
        end
        
    elseif syncType == "REQUEST_STATE" then
        -- Someone just logged in/reloaded and is requesting state
        local requesterName = parts[3]
        local myName = UnitName("player")
        
        -- Only the host (or temp host) responds with full state
        if MP.isHost or MP.temporaryHost == myName then
            -- Check if we're in recovery mode
            if MP:IsInRecoveryMode() then
                -- Send recovery state
                C_Timer.After(0.5, function()
                    MP:Send(MSG.SYNC_STATE, "RECOVERY_STATE", MP.originalHost, MP.temporaryHost, 
                        MP.RECOVERY_TIMEOUT - (time() - MP.recoveryStartTime))
                end)
            elseif BJ.GameState.phase ~= BJ.GameState.PHASE.IDLE then
                -- Send full game state
                C_Timer.After(0.5, function()
                    if BJ.StateSync then
                        BJ.StateSync:BroadcastFullState("blackjack")
                    end
                end)
            end
        end
        
    elseif syncType == "RECOVERY_STATE" then
        -- Received recovery state after login/reload
        local origHost = parts[3]
        local tempHost = parts[4]
        local remaining = tonumber(parts[5]) or 120
        local myName = UnitName("player")
        
        MP.hostDisconnected = true
        MP.originalHost = origHost
        MP.temporaryHost = tempHost
        MP.currentHost = origHost
        MP.recoveryStartTime = time() - (MP.RECOVERY_TIMEOUT - remaining)
        
        -- Check if we ARE the original host who just reconnected
        if origHost == myName then
            BJ:Print("|cff00ff00You have reconnected as host. Restoring game...|r")
            MP:RestoreOriginalHost()
        else
            BJ:Print("|cffff8800Game is paused - waiting for " .. origHost .. " to return.|r")
            MP:ShowRecoveryPopup(origHost, tempHost == myName)
            MP:UpdateRecoveryPopupTimer(remaining)
            
            if BJ.UI and BJ.UI.OnHostRecoveryStart then
                BJ.UI:OnHostRecoveryStart(origHost, tempHost)
            end
        end
        
    elseif syncType == "HOST_RECOVERY_START" then
        -- Host disconnected, temporary host taking over
        local tempHost = parts[3]
        local origHost = parts[4]
        local myName = UnitName("player")
        
        MP.hostDisconnected = true
        MP.originalHost = origHost
        MP.temporaryHost = tempHost
        MP.recoveryStartTime = time()
        
        BJ:Print("|cffff8800" .. origHost .. " disconnected. " .. tempHost .. " is temporary host.|r")
        BJ:Print("|cffff8800Game PAUSED. Waiting up to 2 minutes for host to return.|r")
        
        -- Show popup for all players (temp host already has it from StartHostRecovery)
        if tempHost ~= myName then
            MP:ShowRecoveryPopup(origHost, false)
            -- Start local countdown timer for smooth UI updates
            MP:StartLocalRecoveryCountdown()
        end
        
        if BJ.UI and BJ.UI.OnHostRecoveryStart then
            BJ.UI:OnHostRecoveryStart(origHost, tempHost)
        end
        
    elseif syncType == "HOST_RECOVERY_TICK" then
        local remaining = tonumber(parts[3])
        -- Sync our local time with the authoritative tick
        MP.recoveryStartTime = time() - (MP.RECOVERY_TIMEOUT - remaining)
        -- Update popup timer for non-temp-host players
        MP:UpdateRecoveryPopupTimer(remaining)
        if BJ.UI and BJ.UI.UpdateRecoveryTimer then
            BJ.UI:UpdateRecoveryTimer(remaining)
        end
        
    elseif syncType == "HOST_RESTORED" then
        local origHost = parts[3]
        
        BJ:Print("|cff00ff00" .. origHost .. " has returned! Game resuming.|r")
        
        -- Cancel local timer
        if MP.localRecoveryTimer then
            MP.localRecoveryTimer:Cancel()
            MP.localRecoveryTimer = nil
        end
        
        -- Close popup
        MP:CloseRecoveryPopup()
        
        MP.hostDisconnected = false
        MP.originalHost = nil
        MP.temporaryHost = nil
        MP.recoveryStartTime = nil
        
        if BJ.UI and BJ.UI.OnHostRestored then
            BJ.UI:OnHostRestored()
        end
        
    elseif syncType == "GAME_VOIDED" then
        local reason = parts[3] or "Unknown reason"
        
        BJ:Print("|cffff4444Game VOIDED: " .. reason .. "|r")
        
        -- Cancel local timer
        if MP.localRecoveryTimer then
            MP.localRecoveryTimer:Cancel()
            MP.localRecoveryTimer = nil
        end
        
        -- Close popup
        MP:CloseRecoveryPopup()
        
        -- Reset everything locally
        MP.hostDisconnected = false
        MP.originalHost = nil
        MP.temporaryHost = nil
        MP.recoveryStartTime = nil
        MP:ResetState()
        BJ.GameState:Reset()
        
        if BJ.SessionManager then
            BJ.SessionManager:ClearSession()
        end
        
        if BJ.UI and BJ.UI.OnGameVoided then
            BJ.UI:OnGameVoided(reason)
        end
    end
end

-- Check if phase changed after action
function MP:CheckPhaseChange()
    local GS = BJ.GameState
    
    -- Check if all players are done and dealer should play
    if GS:ShouldDealerPlay() then
        -- Add delay before dealer starts
        C_Timer.After(1.5, function()
            GS:StartDealerTurn()
            -- After StartDealerTurn, check if we need host action or already settled
            C_Timer.After(0.5, function()
                MP:Send(MSG.SYNC_STATE, "DEALER_TURN")
                if BJ.UI then 
                    BJ.UI:OnDealerTurn()
                    BJ.UI:UpdateButtons()
                    BJ.UI:UpdateStatus()
                end
                
                -- Check if already settled (17+ or all busted)
                if GS.phase == GS.PHASE.SETTLEMENT then
                    C_Timer.After(0.5, function()
                        MP:SendSettlement()
                        if BJ.UI then BJ.UI:OnSettlement() end
                    end)
                end
                -- If dealer needs action, buttons are already updated
            end)
        end)
        return
    end
    
    -- Direct dealer turn check (for cases when already in dealer turn)
    if GS.phase == GS.PHASE.DEALER_TURN then
        if BJ.UI then 
            BJ.UI:UpdateButtons()
            BJ.UI:UpdateStatus()
        end
        return
    end
    
    if GS.phase == GS.PHASE.SETTLEMENT then
        MP:SendSettlement()
        if BJ.UI then BJ.UI:OnSettlement() end
    end
end

-- Helper to send settlement with full data
function MP:SendSettlement()
    local GS = BJ.GameState
    -- Build settlement data string
    -- Format: player1:outcome1,outcome2:payout1,payout2;player2:...
    local settlementParts = {}
    for _, playerName in ipairs(GS.playerOrder) do
        local player = GS.players[playerName]
        if player then
            local outcomes = {}
            local payouts = {}
            for i, outcome in ipairs(player.outcomes) do
                table.insert(outcomes, tostring(outcome))
                table.insert(payouts, tostring(player.payouts[i] or 0))
            end
            table.insert(settlementParts, playerName .. ":" .. table.concat(outcomes, ",") .. ":" .. table.concat(payouts, ","))
        end
    end
    local settlementStr = table.concat(settlementParts, ";")
    
    MP:Send(MSG.SYNC_STATE, "SETTLEMENT", settlementStr)
end

--[[
    HOST RECOVERY
    When the original host disconnects, game pauses with a 2-minute grace period.
    If host returns, they resume control. If not, game is voided.
]]

MP.hostDisconnected = false
MP.originalHost = nil
MP.temporaryHost = nil
MP.recoveryTimer = nil
MP.recoveryStartTime = nil
MP.RECOVERY_TIMEOUT = 120  -- 2 minutes

-- Determine who should become the temporary host (just to hold state)
function MP:DetermineTemporaryHost()
    local GS = BJ.GameState
    local myName = UnitName("player")
    
    -- First online player in playerOrder becomes temporary host
    for _, playerName in ipairs(GS.playerOrder) do
        if playerName ~= MP.currentHost then
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
function MP:StartHostRecovery()
    local myName = UnitName("player")
    
    -- Store original host
    MP.originalHost = MP.currentHost
    MP.recoveryStartTime = time()
    
    -- Determine temporary host
    local tempHost = MP:DetermineTemporaryHost()
    
    if tempHost == myName then
        -- We become temporary host
        MP.temporaryHost = myName
        MP.isHost = true  -- Only for reset button access
        MP:Send(MSG.SYNC_STATE, "HOST_RECOVERY_START", myName, MP.originalHost)
        
        BJ:Print("|cffff8800You are temporary host while waiting for " .. MP.originalHost .. " to return.|r")
        BJ:Print("|cffff8800Game is PAUSED. Host has 2 minutes to reconnect or game is voided.|r")
        
        -- Start countdown timer (authoritative)
        MP:StartRecoveryCountdown()
    else
        MP.temporaryHost = tempHost
        BJ:Print("|cffff8800Waiting for " .. MP.originalHost .. " to return (2 min timeout).|r")
        
        -- Start local countdown timer for UI updates
        MP:StartLocalRecoveryCountdown()
    end
    
    -- Show recovery popup for all players
    MP:ShowRecoveryPopup(MP.originalHost, tempHost == myName)
    
    -- Update UI to show paused state
    if BJ.UI and BJ.UI.OnHostRecoveryStart then
        BJ.UI:OnHostRecoveryStart(MP.originalHost, MP.temporaryHost)
    end
end

-- Create and show the recovery popup window
function MP:ShowRecoveryPopup(hostName, isTempHost)
    -- Close existing popup if any
    if MP.recoveryPopup then
        MP.recoveryPopup:Hide()
    end
    
    -- Create popup frame
    local popup = CreateFrame("Frame", "CasinoRecoveryPopup", UIParent, "BackdropTemplate")
    popup:SetSize(320, 140)
    popup:SetPoint("CENTER", 0, 150)
    popup:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 }
    })
    popup:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
    popup:SetFrameStrata("DIALOG")
    popup:SetMovable(true)
    popup:EnableMouse(true)
    popup:RegisterForDrag("LeftButton")
    popup:SetScript("OnDragStart", popup.StartMoving)
    popup:SetScript("OnDragStop", popup.StopMovingOrSizing)
    
    -- Title
    local title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -15)
    title:SetText("|cffff8800HOST DISCONNECTED|r")
    
    -- Host name
    local hostText = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hostText:SetPoint("TOP", title, "BOTTOM", 0, -10)
    hostText:SetText("|cffffffff" .. hostName .. "|r has disconnected")
    
    -- Timer text
    local timerText = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    timerText:SetPoint("TOP", hostText, "BOTTOM", 0, -10)
    timerText:SetText("|cffffd7002:00|r")
    popup.timerText = timerText
    
    -- Status text
    local statusText = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusText:SetPoint("TOP", timerText, "BOTTOM", 0, -5)
    statusText:SetText("Game paused - waiting for host to return")
    popup.statusText = statusText
    
    -- Void button (only for temp host)
    if isTempHost then
        local voidBtn = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
        voidBtn:SetSize(100, 25)
        voidBtn:SetPoint("BOTTOM", 0, 15)
        voidBtn:SetText("Void Game")
        voidBtn:SetScript("OnClick", function()
            StaticPopupDialogs["CASINO_VOID_GAME_CONFIRM"] = {
                text = "Void the current game?\n\nNo gold changes hands.",
                button1 = "Void",
                button2 = "Cancel",
                OnAccept = function()
                    MP:VoidGame("Voided by temporary host")
                end,
                timeout = 0,
                whileDead = true,
                hideOnEscape = true,
            }
            StaticPopup_Show("CASINO_VOID_GAME_CONFIRM")
        end)
        popup.voidBtn = voidBtn
    end
    
    popup:Show()
    MP.recoveryPopup = popup
end

-- Update the recovery popup timer
function MP:UpdateRecoveryPopupTimer(remaining)
    if MP.recoveryPopup and MP.recoveryPopup.timerText then
        local mins = math.floor(remaining / 60)
        local secs = remaining % 60
        local color = remaining <= 30 and "ffff4444" or "ffffd700"
        MP.recoveryPopup.timerText:SetText("|c" .. color .. string.format("%d:%02d", mins, secs) .. "|r")
    end
end

-- Close the recovery popup
function MP:CloseRecoveryPopup()
    if MP.recoveryPopup then
        MP.recoveryPopup:Hide()
        MP.recoveryPopup = nil
    end
end

-- Start the 2-minute recovery countdown (temp host only - authoritative)
function MP:StartRecoveryCountdown()
    if MP.recoveryTimer then
        MP.recoveryTimer:Cancel()
    end
    
    MP.recoveryTimer = C_Timer.NewTicker(1, function()
        local elapsed = time() - MP.recoveryStartTime
        local remaining = MP.RECOVERY_TIMEOUT - elapsed
        
        -- Update local popup timer
        MP:UpdateRecoveryPopupTimer(remaining)
        
        -- Update local UI with remaining time
        if BJ.UI and BJ.UI.UpdateRecoveryTimer then
            BJ.UI:UpdateRecoveryTimer(remaining)
        end
        
        -- Broadcast remaining time every 5 seconds so other clients can update
        if remaining > 0 and remaining % 5 == 0 then
            MP:Send(MSG.SYNC_STATE, "HOST_RECOVERY_TICK", remaining)
        end
        
        if remaining <= 0 then
            -- Timeout - void the game
            MP:VoidGame("Host did not return in time")
        end
    end, MP.RECOVERY_TIMEOUT + 1)
end

-- Start local countdown for non-temp-host clients (just for UI updates)
function MP:StartLocalRecoveryCountdown()
    if MP.localRecoveryTimer then
        MP.localRecoveryTimer:Cancel()
    end
    
    MP.localRecoveryTimer = C_Timer.NewTicker(1, function()
        if not MP.hostDisconnected then
            -- Recovery ended
            if MP.localRecoveryTimer then
                MP.localRecoveryTimer:Cancel()
                MP.localRecoveryTimer = nil
            end
            return
        end
        
        local elapsed = time() - MP.recoveryStartTime
        local remaining = MP.RECOVERY_TIMEOUT - elapsed
        
        -- Update local popup timer
        MP:UpdateRecoveryPopupTimer(remaining)
        
        -- Update local UI
        if BJ.UI and BJ.UI.UpdateRecoveryTimer then
            BJ.UI:UpdateRecoveryTimer(remaining)
        end
    end, MP.RECOVERY_TIMEOUT + 1)
end

-- Check if original host has returned
function MP:CheckHostReturn()
    if not MP.originalHost or not MP.hostDisconnected then return end
    
    local hostOnline = false
    local numMembers = GetNumGroupMembers()
    for i = 1, numMembers do
        local unit = IsInRaid() and ("raid" .. i) or ("party" .. i)
        local name = UnitName(unit)
        if name == MP.originalHost then
            hostOnline = UnitIsConnected(unit)
            break
        end
    end
    
    if hostOnline then
        -- Host is back! Restore them
        MP:RestoreOriginalHost()
    end
end

-- Restore original host after they reconnect
function MP:RestoreOriginalHost()
    -- Prevent double-restore
    if MP.restoringHost then return end
    MP.restoringHost = true
    
    local myName = UnitName("player")
    local wasOriginalHost = (MP.originalHost == myName)
    local originalHostName = MP.originalHost
    local wasTempHost = (MP.temporaryHost == myName)
    
    BJ:Print("|cff00ff00" .. originalHostName .. " has returned! Resuming game.|r")
    
    -- Cancel recovery timer
    if MP.recoveryTimer then
        MP.recoveryTimer:Cancel()
        MP.recoveryTimer = nil
    end
    
    -- Cancel local recovery timer
    if MP.localRecoveryTimer then
        MP.localRecoveryTimer:Cancel()
        MP.localRecoveryTimer = nil
    end
    
    -- Close recovery popup
    MP:CloseRecoveryPopup()
    
    -- If we were temporary host, broadcast restore and send sync to returning host
    if wasTempHost and not wasOriginalHost then
        -- Broadcast that original host is back
        MP:Send(MSG.SYNC_STATE, "HOST_RESTORED", originalHostName)
        
        -- Send full state sync to the returning host after short delay
        C_Timer.After(0.5, function()
            if BJ.StateSync then
                BJ.StateSync:BroadcastFullState("blackjack")
            end
            -- Now clear the restore flag
            MP.restoringHost = false
        end)
        
        -- Relinquish temp host status
        MP.isHost = false
    else
        MP.restoringHost = false
    end
    
    -- If we ARE the original host (we just reconnected), reclaim
    if wasOriginalHost then
        BJ:Print("|cff00ff00You have reconnected. Reclaiming host...|r")
        MP.isHost = true
        MP.currentHost = myName
        -- Don't broadcast sync here - temp host will send it to us
        -- Just update our UI after a delay to receive the sync
        C_Timer.After(1.5, function()
            if BJ.UI then
                BJ.UI:UpdateDisplay()
                BJ.UI:UpdateButtons()
                BJ.UI:UpdateStatus()
            end
        end)
    end
    
    -- Reset recovery state
    MP.hostDisconnected = false
    MP.temporaryHost = nil
    MP.originalHost = nil
    MP.recoveryStartTime = nil
    
    -- Update UI
    if BJ.UI and BJ.UI.OnHostRestored then
        BJ.UI:OnHostRestored()
    end
end

-- Void the game (timeout or manual reset)
function MP:VoidGame(reason)
    BJ:Print("|cffff4444Game VOIDED: " .. reason .. "|r")
    
    -- Cancel recovery timer
    if MP.recoveryTimer then
        MP.recoveryTimer:Cancel()
        MP.recoveryTimer = nil
    end
    
    -- Close recovery popup
    MP:CloseRecoveryPopup()
    
    -- Broadcast void to all
    if MP.temporaryHost == UnitName("player") then
        MP:Send(MSG.SYNC_STATE, "GAME_VOIDED", reason)
    end
    
    -- Reset everything
    MP.hostDisconnected = false
    MP.temporaryHost = nil
    MP.originalHost = nil
    MP.recoveryStartTime = nil
    MP:ResetState()
    BJ.GameState:Reset()
    
    if BJ.SessionManager then
        BJ.SessionManager:ClearSession()
    end
    
    -- Update UI
    if BJ.UI then
        BJ.UI:OnGameVoided(reason)
    end
end

-- Check if game is in recovery mode (paused)
function MP:IsInRecoveryMode()
    return MP.hostDisconnected and MP.originalHost ~= nil
end

-- Check if current player can take actions (blocked during recovery)
function MP:CanTakeAction()
    if MP:IsInRecoveryMode() then
        BJ:Print("|cffff8800Game is paused - waiting for host to return.|r")
        return false
    end
    return true
end
