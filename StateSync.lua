--[[
    Chairface's Casino - StateSync.lua
    Versioned state synchronization with gap detection and full state dumps
    
    Architecture:
    - Each game state change increments a version number
    - All sync messages include the version number
    - Clients track the last received version
    - If a gap is detected (received version > expected), client requests full sync
    - Host can send full state dumps to individual players via whisper
    - Auto-sync on login: Player pings "Am I playing?", hosts respond if player is in their game
]]

local BJ = ChairfacesCasino
BJ.StateSync = {}
local SS = BJ.StateSync

-- Get Ace libraries
local AceSerializer = LibStub("AceSerializer-3.0")
local AceComm = LibStub("AceComm-3.0")

-- State version tracking (per game)
SS.versions = {
    blackjack = { current = 0, lastReceived = 0 },
    poker = { current = 0, lastReceived = 0 },
    hilo = { current = 0, lastReceived = 0 },
    craps = { current = 0, lastReceived = 0 },
}

-- Pending sync requests (to prevent spam)
SS.pendingSyncRequests = {
    blackjack = false,
    poker = false,
    hilo = false,
    craps = false,
}

-- Cooldown tracking for sync responses (prevent double sync)
SS.lastSyncNotification = {  -- For "Found active game" messages
    blackjack = 0,
    poker = 0,
    hilo = 0,
    craps = 0,
}
SS.lastSyncApplied = {  -- For actual state application
    blackjack = 0,
    poker = 0,
    hilo = 0,
    craps = 0,
}
SS.SYNC_COOLDOWN = 5  -- Seconds to ignore duplicate syncs

-- Message type for sync requests/responses
SS.MSG = {
    REQUEST_SYNC = "REQSYNC",      -- Client requests full state dump
    FULL_STATE = "FULLSTATE",      -- Host sends full state dump
    STATE_UPDATE = "STATEUPD",     -- Incremental state update with version
    DISCOVER_HOSTS = "DISCOVER",   -- Broadcast to find active hosts
    HOST_ANNOUNCE = "HOSTANN",     -- Host responds to discovery
    AM_I_PLAYING = "AMIPLAYING",   -- Player asks if they're in any active game
    YOU_ARE_PLAYING = "YOUREPLAYING", -- Host confirms player is in their game
}

-- Initialize state sync
function SS:Initialize()
    -- Register for discovery messages on a shared channel
    AceComm:RegisterComm("CCDiscover", function(prefix, message, distribution, sender)
        SS:OnDiscoveryMessage(prefix, message, distribution, sender)
    end)
    
    -- Register for PLAYER_ENTERING_WORLD to auto-sync on login/reload
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("GROUP_JOINED")  -- Fires when joining a group
    frame:SetScript("OnEvent", function(self, event, arg1, arg2)
        if event == "PLAYER_ENTERING_WORLD" then
            local isLogin, isReload = arg1, arg2
            -- Delay slightly to let other systems initialize
            C_Timer.After(2, function()
                SS:OnPlayerEnteringWorld(isLogin, isReload)
            end)
        elseif event == "GROUP_JOINED" then
            -- Joined a group - check for active games after a delay
            C_Timer.After(1.5, function()
                SS:OnGroupJoined()
            end)
        end
    end)
    
    BJ:Debug("StateSync initialized")
end

-- Called when player joins a group
function SS:OnGroupJoined()
    if not IsInGroup() and not IsInRaid() then
        return
    end
    
    BJ:Debug("StateSync: Joined group, checking for active casino games...")
    
    -- Use the same flow as login - ask if there are active games
    local channel = IsInRaid() and "RAID" or "PARTY"
    local myName = UnitName("player")
    AceComm:SendCommMessage("CCDiscover", SS.MSG.AM_I_PLAYING .. "|" .. myName, channel)
end

-- Called when player logs in or reloads UI
function SS:OnPlayerEnteringWorld(isLogin, isReload)
    -- Only ping if we're in a group
    if not IsInGroup() and not IsInRaid() then
        BJ:Debug("StateSync: Not in group, skipping sync check")
        return
    end
    
    BJ:Print("|cff88ff88[Casino] Checking for active games...|r")
    
    -- Broadcast "Am I playing?" to the group
    local channel = IsInRaid() and "RAID" or "PARTY"
    local myName = UnitName("player")
    AceComm:SendCommMessage("CCDiscover", SS.MSG.AM_I_PLAYING .. "|" .. myName, channel)
end

-- Handle discovery messages
function SS:OnDiscoveryMessage(prefix, message, distribution, sender)
    local myName = UnitName("player")
    local senderName = sender:match("^([^-]+)") or sender
    if senderName == myName then return end
    
    local parts = {}
    for part in message:gmatch("[^|]+") do
        table.insert(parts, part)
    end
    local msgType = parts[1]
    
    if msgType == SS.MSG.DISCOVER_HOSTS then
        -- Someone is looking for hosts - respond if we're hosting
        SS:RespondToDiscovery(senderName)
    elseif msgType == SS.MSG.HOST_ANNOUNCE then
        -- A host responded to our discovery
        local game = parts[2]
        local hostName = senderName
        SS:OnHostDiscovered(game, hostName)
    elseif msgType == SS.MSG.AM_I_PLAYING then
        -- Someone is asking if they're in any active game (after reload/login)
        local askingPlayer = parts[2]
        SS:CheckIfPlayerInGame(askingPlayer)
    elseif msgType == SS.MSG.YOU_ARE_PLAYING then
        -- A host confirmed there's an active game - they will push sync to us
        -- Check cooldown to prevent duplicate notification messages
        local game = parts[2]
        local isRecovery = parts[3] == "recovery"
        local now = GetTime()
        if SS.lastSyncNotification[game] and (now - SS.lastSyncNotification[game]) < SS.SYNC_COOLDOWN then
            BJ:Debug("StateSync: Ignoring duplicate " .. game .. " sync notification (cooldown)")
            return
        end
        SS.lastSyncNotification[game] = now
        
        local hostName = senderName
        local gameName = game == "blackjack" and "Blackjack" or (game == "poker" and "5 Card Stud" or (game == "hilo" and "High-Lo" or "Craps"))
        local gameLink = BJ:CreateGameLink(game, gameName)
        
        if isRecovery then
            -- Game is in recovery mode
            local origHost = parts[4]
            local tempHost = parts[5]
            local remaining = tonumber(parts[6]) or 120
            local myName = UnitName("player")
            
            BJ:Print("|cffff8800Found " .. gameLink .. " game - PAUSED (waiting for " .. origHost .. ")|r")
            
            -- Set recovery state for appropriate game
            if game == "blackjack" and BJ.Multiplayer then
                local MP = BJ.Multiplayer
                MP.currentHost = origHost
                MP.originalHost = origHost
                MP.temporaryHost = tempHost
                MP.hostDisconnected = true
                MP.recoveryStartTime = time() - (MP.RECOVERY_TIMEOUT - remaining)
                MP.tableOpen = true
                MP.isHost = (origHost == myName)
                
                -- If we ARE the original host, restore
                if origHost == myName then
                    BJ:Print("|cff00ff00You have reconnected as host. Restoring game...|r")
                    MP:RestoreOriginalHost()
                else
                    MP:ShowRecoveryPopup(origHost, tempHost == myName)
                    MP:UpdateRecoveryPopupTimer(remaining)
                    if BJ.UI and BJ.UI.OnHostRecoveryStart then
                        BJ.UI:OnHostRecoveryStart(origHost, tempHost)
                    end
                end
            elseif game == "poker" and BJ.PokerMultiplayer then
                local PM = BJ.PokerMultiplayer
                PM.currentHost = origHost
                PM.originalHost = origHost
                PM.temporaryHost = tempHost
                PM.hostDisconnected = true
                PM.recoveryStartTime = time() - (PM.RECOVERY_TIMEOUT - remaining)
                PM.tableOpen = true
                PM.isHost = (origHost == myName)
                
                if origHost == myName then
                    BJ:Print("|cff00ff00You have reconnected as host. Restoring game...|r")
                    PM:RestoreOriginalHost()
                elseif BJ.UI and BJ.UI.Poker and BJ.UI.Poker.OnHostRecoveryStart then
                    BJ.UI.Poker:OnHostRecoveryStart(origHost, tempHost)
                end
            elseif game == "hilo" and BJ.HiLoMultiplayer then
                -- High-Lo doesn't use recovery mode - host transfer is immediate
                -- This code path shouldn't be hit, but handle gracefully
                local HLM = BJ.HiLoMultiplayer
                HLM.currentHost = tempHost  -- New host is the temp host
                HLM.tableOpen = true
                HLM.isHost = (tempHost == myName)
                BJ.HiLoState.hostName = tempHost
                
                BJ:Print("|cff00ff00" .. tempHost .. " is the High-Lo host.|r")
                if BJ.UI and BJ.UI.HiLo then
                    BJ.UI.HiLo:UpdateDisplay()
                end
            end
        else
            -- Normal active game
            BJ:Print("|cff88ff88Found active " .. gameLink .. " game hosted by " .. hostName .. " - syncing...|r")
            
            -- Update multiplayer host tracking (but don't request sync - it's already coming)
            if game == "blackjack" and BJ.Multiplayer then
                BJ.Multiplayer.currentHost = hostName
                BJ.Multiplayer.tableOpen = true
                BJ.Multiplayer.isHost = false
            elseif game == "poker" and BJ.PokerMultiplayer then
                BJ.PokerMultiplayer.currentHost = hostName
                BJ.PokerMultiplayer.tableOpen = true
                BJ.PokerMultiplayer.isHost = false
            elseif game == "hilo" and BJ.HiLoMultiplayer then
                BJ.HiLoMultiplayer.currentHost = hostName
                BJ.HiLoMultiplayer.tableOpen = true
                BJ.HiLoMultiplayer.isHost = false
            elseif game == "craps" and BJ.CrapsMultiplayer then
                BJ.CrapsMultiplayer.currentHost = hostName
                BJ.CrapsMultiplayer.tableOpen = true
                BJ.CrapsMultiplayer.isHost = false
            end
        end
    end
end

-- Check if we're hosting any active games and send sync to requesting player (for spectators too)
function SS:CheckIfPlayerInGame(playerName)
    local MP = BJ.Multiplayer
    local PM = BJ.PokerMultiplayer
    local HLM = BJ.HiLoMultiplayer
    local myName = UnitName("player")
    
    -- Check Blackjack - send to anyone if game is active (not idle or settlement)
    -- Also check if we're temp host in recovery mode
    local bjCheck = MP and (MP.isHost or MP.temporaryHost == myName)
    
    if bjCheck then
        local GS = BJ.GameState
        local phase = GS and GS.phase
        
        -- Only sync for active games (not idle or concluded settlement)
        if GS and phase and phase ~= "idle" and phase ~= "settlement" then
            -- Check if in recovery mode
            if MP.hostDisconnected and MP.originalHost then
                -- Check if the ORIGINAL HOST is the one asking - if so, trigger restore!
                if playerName == MP.originalHost then
                    BJ:Print("|cff00ff00Original host " .. playerName .. " has reconnected! Restoring...|r")
                    MP:RestoreOriginalHost()
                else
                    -- Someone else asking - send recovery state
                    local remaining = MP.RECOVERY_TIMEOUT - (time() - (MP.recoveryStartTime or time()))
                    AceComm:SendCommMessage("CCDiscover", SS.MSG.YOU_ARE_PLAYING .. "|blackjack|recovery|" .. (MP.originalHost or "") .. "|" .. (MP.temporaryHost or "") .. "|" .. remaining, "WHISPER", playerName)
                end
            else
                -- Active game - send sync to anyone in party/raid (spectator or player)
                AceComm:SendCommMessage("CCDiscover", SS.MSG.YOU_ARE_PLAYING .. "|blackjack", "WHISPER", playerName)
                C_Timer.After(0.5, function()
                    SS:HandleSyncRequest("blackjack", playerName)
                end)
            end
        end
    end
    
    -- Check Poker - send to anyone if game is active (not idle or settlement)
    if PM and (PM.isHost or PM.temporaryHost == myName) then
        local PS = BJ.PokerState
        if PS and PS.phase and PS.phase ~= "idle" and PS.phase ~= "settlement" then
            if PM.hostDisconnected and PM.originalHost then
                if playerName == PM.originalHost then
                    BJ:Print("|cff00ff00Original host " .. playerName .. " has reconnected! Restoring...|r")
                    PM:RestoreOriginalHost()
                else
                    local remaining = PM.RECOVERY_TIMEOUT - (time() - (PM.recoveryStartTime or time()))
                    AceComm:SendCommMessage("CCDiscover", SS.MSG.YOU_ARE_PLAYING .. "|poker|recovery|" .. (PM.originalHost or "") .. "|" .. (PM.temporaryHost or "") .. "|" .. remaining, "WHISPER", playerName)
                end
            else
                AceComm:SendCommMessage("CCDiscover", SS.MSG.YOU_ARE_PLAYING .. "|poker", "WHISPER", playerName)
                C_Timer.After(0.5, function()
                    SS:HandleSyncRequest("poker", playerName)
                end)
            end
        end
    end
    
    -- Check High-Lo - send to anyone if game is active (not idle or settlement)
    -- High-Lo does immediate host transfer, no recovery mode
    if HLM and HLM.isHost then
        local HL = BJ.HiLoState
        if HL and HL.phase and HL.phase ~= "idle" and HL.phase ~= "settlement" then
            AceComm:SendCommMessage("CCDiscover", SS.MSG.YOU_ARE_PLAYING .. "|hilo", "WHISPER", playerName)
            C_Timer.After(0.5, function()
                SS:HandleSyncRequest("hilo", playerName)
            end)
        end
    end
    
    -- Check Craps
    local crapsCheck = BJ.CrapsMultiplayer and BJ.CrapsMultiplayer.isHost
    if crapsCheck then
        local CS = BJ.CrapsState
        local phase = CS and CS.phase
        
        if CS and phase and phase ~= CS.PHASE.IDLE then
            AceComm:SendCommMessage("CCDiscover", SS.MSG.YOU_ARE_PLAYING .. "|craps", "WHISPER", playerName)
            C_Timer.After(0.5, function()
                SS:HandleSyncRequest("craps", playerName)
            end)
        end
    end
end

-- Broadcast discovery request to find active hosts
function SS:BroadcastDiscovery()
    local channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY" or nil)
    if not channel then
        BJ:Print("|cff888888Not in a group.|r")
        return false
    end
    
    AceComm:SendCommMessage("CCDiscover", SS.MSG.DISCOVER_HOSTS, channel)
    BJ:Debug("StateSync: Broadcasting host discovery")
    return true
end

-- Respond to discovery if we're hosting any games
function SS:RespondToDiscovery(requesterName)
    -- Check each game
    if BJ.Multiplayer and BJ.Multiplayer.isHost then
        AceComm:SendCommMessage("CCDiscover", SS.MSG.HOST_ANNOUNCE .. "|blackjack", "WHISPER", requesterName)
    end
    if BJ.PokerMultiplayer and BJ.PokerMultiplayer.isHost then
        AceComm:SendCommMessage("CCDiscover", SS.MSG.HOST_ANNOUNCE .. "|poker", "WHISPER", requesterName)
    end
    if BJ.HiLoMultiplayer and BJ.HiLoMultiplayer.isHost then
        AceComm:SendCommMessage("CCDiscover", SS.MSG.HOST_ANNOUNCE .. "|hilo", "WHISPER", requesterName)
    end
    if BJ.CrapsMultiplayer and BJ.CrapsMultiplayer.isHost then
        AceComm:SendCommMessage("CCDiscover", SS.MSG.HOST_ANNOUNCE .. "|craps", "WHISPER", requesterName)
    end
end

-- Handle discovered host - update local state and request sync
function SS:OnHostDiscovered(game, hostName)
    BJ:Debug("StateSync: Discovered " .. game .. " host: " .. hostName)
    
    -- Update the multiplayer module with the host info
    if game == "blackjack" and BJ.Multiplayer then
        BJ.Multiplayer.currentHost = hostName
        BJ.Multiplayer.tableOpen = true
        BJ:Print("|cff88ff88Found Blackjack host: " .. hostName .. "|r")
        -- Request full sync
        SS:RequestFullSync("blackjack", hostName)
    elseif game == "poker" and BJ.PokerMultiplayer then
        BJ.PokerMultiplayer.currentHost = hostName
        BJ.PokerMultiplayer.tableOpen = true
        BJ:Print("|cff88ff88Found Poker host: " .. hostName .. "|r")
        SS:RequestFullSync("poker", hostName)
    elseif game == "hilo" and BJ.HiLoMultiplayer then
        BJ.HiLoMultiplayer.currentHost = hostName
        BJ.HiLoMultiplayer.tableOpen = true
        BJ:Print("|cff88ff88Found High-Lo host: " .. hostName .. "|r")
        SS:RequestFullSync("hilo", hostName)
    elseif game == "craps" and BJ.CrapsMultiplayer then
        BJ.CrapsMultiplayer.currentHost = hostName
        BJ.CrapsMultiplayer.tableOpen = true
        BJ:Print("|cff88ff88Found Craps host: " .. hostName .. "|r")
        SS:RequestFullSync("craps", hostName)
    end
end

-- Reset version tracking for a game (called when game ends or resets)
function SS:ResetVersion(game)
    if self.versions[game] then
        self.versions[game].current = 0
        self.versions[game].lastReceived = 0
        self.pendingSyncRequests[game] = false
    end
end

-- Increment and get new version (host only)
function SS:IncrementVersion(game)
    if self.versions[game] then
        self.versions[game].current = self.versions[game].current + 1
        return self.versions[game].current
    end
    return 0
end

-- Get current version
function SS:GetVersion(game)
    return self.versions[game] and self.versions[game].current or 0
end

-- Check if received version is valid, request sync if gap detected
-- Returns true if version is valid, false if sync needed
function SS:ValidateVersion(game, receivedVersion, hostName)
    local tracker = self.versions[game]
    if not tracker then return true end
    
    local expectedVersion = tracker.lastReceived + 1
    
    -- Version is what we expected
    if receivedVersion == expectedVersion then
        tracker.lastReceived = receivedVersion
        return true
    end
    
    -- Version 1 always valid (fresh start)
    if receivedVersion == 1 then
        tracker.lastReceived = 1
        return true
    end
    
    -- Gap detected - we missed messages
    if receivedVersion > expectedVersion then
        BJ:Debug("StateSync: Gap detected for " .. game .. 
            " - expected v" .. expectedVersion .. ", got v" .. receivedVersion)
        
        -- Request full sync if we haven't already
        if not self.pendingSyncRequests[game] then
            self:RequestFullSync(game, hostName)
        end
        return false
    end
    
    -- Old version (already processed), ignore
    if receivedVersion < expectedVersion then
        BJ:Debug("StateSync: Old version ignored for " .. game .. 
            " - expected v" .. expectedVersion .. ", got v" .. receivedVersion)
        return false
    end
    
    return true
end

-- Request full state sync from host
function SS:RequestFullSync(game, hostName)
    if not hostName then
        BJ:Debug("StateSync: Cannot request sync - no host")
        return
    end
    
    self.pendingSyncRequests[game] = true
    
    BJ:Debug("StateSync: Requesting full sync for " .. game .. " from " .. hostName)
    
    -- Send request via appropriate channel
    if game == "blackjack" and BJ.Multiplayer then
        BJ.Multiplayer:SendWhisper(hostName, SS.MSG.REQUEST_SYNC, game)
    elseif game == "poker" and BJ.PokerMultiplayer then
        BJ.PokerMultiplayer:SendWhisper(hostName, SS.MSG.REQUEST_SYNC, game)
    elseif game == "hilo" and BJ.HiLoMultiplayer then
        BJ.HiLoMultiplayer:SendWhisper(hostName, SS.MSG.REQUEST_SYNC, game)
    end
end

-- Handle sync request (host only)
function SS:HandleSyncRequest(game, requesterName)
    BJ:Debug("StateSync: Received sync request for " .. game .. " from " .. requesterName)
    
    -- Build and send full state
    local stateData = self:BuildFullState(game)
    if stateData then
        self:SendFullState(game, requesterName, stateData)
    end
end

-- Build full state dump for a game
function SS:BuildFullState(game)
    local state = {
        version = self:GetVersion(game),
        timestamp = time(),
        game = game,
    }
    
    if game == "blackjack" then
        state.data = self:BuildBlackjackState()
    elseif game == "poker" then
        state.data = self:BuildPokerState()
    elseif game == "hilo" then
        state.data = self:BuildHiLoState()
    elseif game == "craps" then
        state.data = self:BuildCrapsState()
    end
    
    return state
end

-- Build Blackjack full state
function SS:BuildBlackjackState()
    local GS = BJ.GameState
    local MP = BJ.Multiplayer
    
    -- Determine correct cards remaining
    -- If we have a real shoe with proper cardIndex, use calculation
    -- Otherwise fall back to syncedCardsRemaining (for temp hosts who don't have real shoe state)
    local cardsRemaining
    local cardIndex
    if GS.shoe and #GS.shoe > 0 and GS.cardIndex and GS.cardIndex > 1 then
        -- We have real shoe state
        cardsRemaining = #GS.shoe - GS.cardIndex + 1
        cardIndex = GS.cardIndex
    elseif GS.syncedCardsRemaining then
        -- We're a temp host or client with synced state
        cardsRemaining = GS.syncedCardsRemaining
        -- Calculate what cardIndex should be
        cardIndex = GS.shoe and (#GS.shoe - GS.syncedCardsRemaining + 1) or 1
    else
        -- Fallback
        cardsRemaining = GS:GetRemainingCards()
        cardIndex = GS.cardIndex or 1
    end
    
    BJ:Debug("[Sync] Building state: cardIndex=" .. tostring(cardIndex) .. ", remaining=" .. tostring(cardsRemaining) .. ", shoeSize=" .. tostring(GS.shoe and #GS.shoe or 0))
    
    local state = {
        -- Game phase and basic info
        phase = GS.phase,
        hostName = GS.hostName,
        ante = GS.ante,
        maxMultiplier = GS.maxMultiplier,
        seed = GS.seed,
        dealerHitsSoft17 = GS.dealerHitsSoft17,
        
        -- Dealer
        dealerHand = {},
        dealerHoleCardRevealed = GS.dealerHoleCardRevealed,
        
        -- Player order and current player
        playerOrder = GS.playerOrder,
        currentPlayerIndex = GS.currentPlayerIndex,
        
        -- All player data
        players = {},
        
        -- Shoe info
        cardsRemaining = cardsRemaining,
        cardIndex = cardIndex,
        
        -- Settlements
        settlements = GS.settlements,
        ledger = GS.ledger,
        
        -- Multiplayer state
        isHost = MP.isHost,
        countdownRemaining = MP.countdownRemaining,
    }
    
    -- Copy dealer hand
    for _, card in ipairs(GS.dealerHand or {}) do
        table.insert(state.dealerHand, { rank = card.rank, suit = card.suit })
    end
    
    -- Copy all player data
    for playerName, player in pairs(GS.players or {}) do
        local playerData = {
            hands = {},
            bets = player.bets,
            insurance = player.insurance,
            activeHandIndex = player.activeHandIndex,
            outcomes = player.outcomes,
            payouts = player.payouts,
            hasBlackjack = player.hasBlackjack,
            splitAcesHands = player.splitAcesHands,
            hasFiveCardCharlie = player.hasFiveCardCharlie,
        }
        
        -- Copy each hand
        for h, hand in ipairs(player.hands or {}) do
            local handCopy = {}
            for _, card in ipairs(hand) do
                table.insert(handCopy, { rank = card.rank, suit = card.suit })
            end
            playerData.hands[h] = handCopy
        end
        
        state.players[playerName] = playerData
    end
    
    return state
end

-- Build Poker full state
function SS:BuildPokerState()
    local PS = BJ.PokerState
    local PM = BJ.PokerMultiplayer
    
    if not PS then return nil end
    
    -- Calculate correct card values
    -- If we have a real deck with proper cardIndex, use those
    -- Otherwise, calculate from syncedCardsRemaining
    local cardIndex, cardsRemaining
    if PS.deck and #PS.deck > 0 and PS.cardIndex and PS.cardIndex > 1 then
        -- We have real deck state (we're the actual host)
        cardIndex = PS.cardIndex
        cardsRemaining = #PS.deck - PS.cardIndex + 1
    elseif PS.syncedCardsRemaining then
        -- We're temp host or client with synced state
        cardsRemaining = PS.syncedCardsRemaining
        -- Calculate what cardIndex should be for a 52-card deck
        cardIndex = 52 - PS.syncedCardsRemaining + 1
    else
        -- Fallback
        cardsRemaining = PS:GetRemainingCards()
        cardIndex = PS.cardIndex or 1
    end
    
    local state = {
        -- Game phase and basic info
        phase = PS.phase,
        hostName = PS.hostName,
        ante = PS.ante,
        pot = PS.pot,
        currentBet = PS.currentBet,
        currentStreet = PS.currentStreet,
        maxRaise = PS.maxRaise,
        seed = PS.seed,
        cardIndex = cardIndex,
        cardsRemaining = cardsRemaining,
        
        -- Player order and current player
        playerOrder = PS.playerOrder,
        currentPlayerIndex = PS.currentPlayerIndex,
        dealerIndex = PS.dealerIndex,
        
        -- All player data
        players = {},
        
        -- Betting round
        bettingRound = PS.bettingRound,
        
        -- Multiplayer state
        isHost = PM and PM.isHost or false,
    }
    
    -- Copy all player data
    for playerName, player in pairs(PS.players or {}) do
        local playerData = {
            hand = {},
            bet = player.bet,
            totalBet = player.totalBet,
            currentBet = player.currentBet or 0,  -- Include current round bet
            folded = player.folded,
            allIn = player.allIn,
            chips = player.chips,
            hasActed = player.hasActed,
        }
        
        -- Copy hand (include faceUp state)
        for _, card in ipairs(player.hand or {}) do
            table.insert(playerData.hand, { rank = card.rank, suit = card.suit, faceUp = card.faceUp })
        end
        
        state.players[playerName] = playerData
    end
    
    return state
end

-- Build High-Lo full state
function SS:BuildHiLoState()
    local HL = BJ.HiLoState
    local HLM = BJ.HiLoMultiplayer
    
    if not HL then return nil end
    
    local state = {
        -- Game phase and basic info
        phase = HL.phase,
        hostName = HL.hostName,
        maxRoll = HL.maxRoll,
        joinTimer = HL.joinTimer,
        lobbyStartTime = HL.lobbyStartTime,
        rollStartTime = HL.rollStartTime,
        
        -- Player order
        playerOrder = HL.playerOrder,
        
        -- All player data
        players = {},
        
        -- Settlement data
        highPlayer = HL.highPlayer,
        highRoll = HL.highRoll,
        lowPlayer = HL.lowPlayer,
        lowRoll = HL.lowRoll,
        winAmount = HL.winAmount,
        
        -- Tiebreaker state
        tiebreakerPlayers = HL.tiebreakerPlayers,
        tiebreakerType = HL.tiebreakerType,
        tiebreakerRolls = HL.tiebreakerRolls,
        
        -- Multiplayer state
        isHost = HLM and HLM.isHost or false,
        joinStartTime = HLM and HLM.joinStartTime,
        joinDuration = HLM and HLM.joinDuration,
    }
    
    -- Copy all player data
    for playerName, player in pairs(HL.players or {}) do
        state.players[playerName] = {
            rolled = player.rolled,
            roll = player.roll,
        }
    end
    
    return state
end

-- Build Craps full state
function SS:BuildCrapsState()
    local CS = BJ.CrapsState
    local CM = BJ.CrapsMultiplayer
    
    if not CS then return nil end
    
    local state = {
        -- Game phase and basic info
        phase = CS.phase,
        hostName = CS.hostName,
        shooterName = CS.shooterName,
        point = CS.point,
        
        -- Table settings
        minBet = CS.minBet,
        maxBet = CS.maxBet,
        maxOdds = CS.maxOdds,
        bettingTimer = CS.bettingTimer,
        tableCap = CS.tableCap,
        currentRisk = CS.currentRisk,
        
        -- Shooter order
        shooterOrder = CS.shooterOrder,
        
        -- Last roll
        lastRoll = CS.lastRoll,
        
        -- All player data
        players = {},
        
        -- Pending joins
        pendingJoins = {},
        
        -- Multiplayer state
        isHost = CM and CM.isHost or false,
    }
    
    -- Copy all player data
    for playerName, player in pairs(CS.players or {}) do
        local playerData = {
            balance = player.balance,
            startBalance = player.startBalance,
            sessionBalance = player.sessionBalance,
            lockedIn = player.lockedIn,
            isHost = player.isHost,
            isSpectator = player.isSpectator,
            bets = {},
        }
        
        -- Deep copy bets
        if player.bets then
            for k, v in pairs(player.bets) do
                if type(v) == "table" then
                    playerData.bets[k] = {}
                    for k2, v2 in pairs(v) do
                        playerData.bets[k][k2] = v2
                    end
                else
                    playerData.bets[k] = v
                end
            end
        end
        
        state.players[playerName] = playerData
    end
    
    -- Copy pending joins
    for playerName, request in pairs(CS.pendingJoins or {}) do
        state.pendingJoins[playerName] = {
            buyIn = request.buyIn,
            time = request.time,
        }
    end
    
    return state
end

-- Send full state to a specific player
function SS:SendFullState(game, targetPlayer, stateData)
    -- Serialize the state table
    local serialized = AceSerializer:Serialize(stateData)
    
    -- Compress if available
    local toSend = serialized
    if BJ.Compression and BJ.Compression.available then
        local compressed, wasCompressed = BJ.Compression:Compress(serialized)
        if wasCompressed then
            toSend = compressed
            BJ:Debug("StateSync: Compressed full state from " .. #serialized .. " to " .. #toSend .. " bytes")
        end
    end
    
    BJ:Debug("StateSync: Sending full state for " .. game .. " to " .. targetPlayer .. 
        " (v" .. stateData.version .. ", " .. #toSend .. " bytes)")
    
    -- Send via appropriate channel
    local prefix
    if game == "blackjack" then
        prefix = "CCBlackjack"
    elseif game == "poker" then
        prefix = "CCPoker"
    elseif game == "hilo" then
        prefix = "CCHiLo"
    elseif game == "craps" then
        prefix = "CCCraps"
    end
    
    if prefix then
        -- Send with FULLSTATE prefix so receiver knows to deserialize
        AceComm:SendCommMessage(prefix, SS.MSG.FULL_STATE .. "|" .. toSend, "WHISPER", targetPlayer)
    end
end

-- Broadcast full state to all group members
function SS:BroadcastFullState(game)
    local stateData = self:BuildFullState(game)
    if not stateData then return end
    
    -- Serialize the state table
    local serialized = AceSerializer:Serialize(stateData)
    
    -- Compress if available
    local toSend = serialized
    if BJ.Compression and BJ.Compression.available then
        local compressed, wasCompressed = BJ.Compression:Compress(serialized)
        if wasCompressed then
            toSend = compressed
            BJ:Debug("StateSync: Compressed broadcast state from " .. #serialized .. " to " .. #toSend .. " bytes")
        end
    end
    
    BJ:Debug("StateSync: Broadcasting full state for " .. game .. " (v" .. stateData.version .. ", " .. #toSend .. " bytes)")
    
    -- Determine channel prefix
    local prefix
    if game == "blackjack" then
        prefix = "CCBlackjack"
    elseif game == "poker" then
        prefix = "CCPoker"
    elseif game == "hilo" then
        prefix = "CCHiLo"
    end
    
    if prefix then
        -- Broadcast to group
        local channel = IsInRaid() and "RAID" or "PARTY"
        AceComm:SendCommMessage(prefix, SS.MSG.FULL_STATE .. "|" .. toSend, channel)
    end
end

-- Handle received full state
function SS:HandleFullState(game, serializedData)
    -- Check cooldown to prevent duplicate sync processing
    local now = GetTime()
    if SS.lastSyncApplied[game] and (now - SS.lastSyncApplied[game]) < SS.SYNC_COOLDOWN then
        BJ:Debug("StateSync: Ignoring duplicate " .. game .. " full state (cooldown)")
        return false
    end
    SS.lastSyncApplied[game] = now
    
    -- Get friendly game name for messages
    local gameName = game == "blackjack" and "Blackjack" or (game == "poker" and "5 Card Stud" or (game == "hilo" and "High-Lo" or "Craps"))
    
    -- Decompress if needed
    local toDeserialize = serializedData
    if BJ.Compression then
        toDeserialize = BJ.Compression:Decompress(serializedData)
    end
    
    -- Deserialize
    local success, stateData = AceSerializer:Deserialize(toDeserialize)
    if not success then
        BJ:Print("|cffff4444Sync failed:|r Could not deserialize " .. gameName .. " state.")
        BJ:Debug("StateSync: Failed to deserialize full state for " .. game)
        return false
    end
    
    BJ:Debug("StateSync: Received full state for " .. game .. " v" .. (stateData.version or "?"))
    
    -- Apply the state
    local applied = false
    if game == "blackjack" then
        applied = self:ApplyBlackjackState(stateData.data)
    elseif game == "poker" then
        applied = self:ApplyPokerState(stateData.data)
    elseif game == "hilo" then
        applied = self:ApplyHiLoState(stateData.data)
    elseif game == "craps" then
        applied = self:ApplyCrapsState(stateData.data)
    end
    
    if applied then
        -- Update version tracking
        self.versions[game].lastReceived = stateData.version
        self.pendingSyncRequests[game] = false
        
        -- Success message with clickable game link
        local gameLink = BJ:CreateGameLink(game, gameName)
        BJ:Print("|cff00ff00Sync successful:|r " .. gameLink .. " state restored.")
        
        -- Update UI
        if game == "blackjack" and BJ.UI then
            BJ.UI:UpdateDisplay()
        elseif game == "poker" and BJ.UI and BJ.UI.Poker then
            BJ.UI.Poker:UpdateDisplay()
            BJ.UI.Poker:UpdateInfoText()  -- Ensure seed is shown
            -- Delayed button update to ensure state is fully applied
            C_Timer.After(0.1, function()
                if BJ.UI and BJ.UI.Poker and BJ.UI.Poker.isInitialized then
                    local PS = BJ.PokerState
                    local myName = UnitName("player")
                    BJ:Debug("Post-sync button update: phase=" .. tostring(PS.phase) .. 
                        ", currentPlayerIdx=" .. tostring(PS.currentPlayerIndex) ..
                        ", currentPlayer=" .. tostring(PS:GetCurrentPlayer()) ..
                        ", myName=" .. myName)
                    BJ.UI.Poker:UpdateButtons()
                    BJ.UI.Poker:UpdateInfoText()  -- Update again after delay
                end
            end)
        elseif game == "hilo" and BJ.UI and BJ.UI.HiLo then
            BJ.UI.HiLo:UpdateDisplay()
        elseif game == "craps" and BJ.UI and BJ.UI.Craps then
            BJ.UI.Craps:UpdateDisplay()
        end
    else
        BJ:Print("|cffff4444Sync failed:|r Could not apply " .. gameName .. " state.")
    end
    
    return applied
end

-- Apply Blackjack state
function SS:ApplyBlackjackState(state)
    if not state then return false end
    
    local GS = BJ.GameState
    local MP = BJ.Multiplayer
    
    -- Apply basic info
    GS.phase = state.phase
    GS.hostName = state.hostName
    GS.ante = state.ante
    GS.maxMultiplier = state.maxMultiplier
    GS.seed = state.seed
    GS.dealerHitsSoft17 = state.dealerHitsSoft17
    
    -- Apply dealer
    GS.dealerHand = state.dealerHand or {}
    GS.dealerHoleCardRevealed = state.dealerHoleCardRevealed
    
    -- Apply player order and current player
    GS.playerOrder = state.playerOrder or {}
    GS.currentPlayerIndex = state.currentPlayerIndex
    
    -- Apply all player data
    GS.players = state.players or {}
    
    -- Regenerate shoe from seed if we don't have one
    -- This is important for returning hosts who have fresh state
    if not GS.shoe or #GS.shoe == 0 then
        if state.seed then
            BJ:Debug("[Sync] Regenerating shoe from seed " .. state.seed)
            GS:CreateShoe(state.seed)
            BJ:Debug("[Sync] After CreateShoe: cardIndex=" .. tostring(GS.cardIndex) .. ", shoeSize=" .. tostring(#GS.shoe))
        end
    end
    
    -- Apply shoe info
    BJ:Debug("[Sync] Received: cardIndex=" .. tostring(state.cardIndex) .. ", cardsRemaining=" .. tostring(state.cardsRemaining))
    GS.syncedCardsRemaining = state.cardsRemaining
    if state.cardIndex then
        GS.cardIndex = state.cardIndex
        BJ:Debug("[Sync] Applied cardIndex=" .. GS.cardIndex .. ", now remaining=" .. GS:GetRemainingCards())
    elseif state.cardsRemaining and GS.shoe and #GS.shoe > 0 then
        -- Calculate card index based on remaining cards (fallback)
        GS.cardIndex = #GS.shoe - state.cardsRemaining + 1
        BJ:Debug("[Sync] Calculated cardIndex=" .. GS.cardIndex .. " from remaining=" .. state.cardsRemaining)
    end
    
    -- Apply settlements
    GS.settlements = state.settlements
    GS.ledger = state.ledger
    
    -- Apply multiplayer state
    MP.countdownRemaining = state.countdownRemaining
    
    -- Update multiplayer host tracking so we stay connected
    if state.hostName then
        MP.currentHost = state.hostName
        MP.tableOpen = true
        MP.isHost = (state.hostName == UnitName("player"))
    end
    
    -- Update UI dealt cards tracking so cards display properly
    if BJ.UI then
        -- Set dealer dealt cards count
        BJ.UI.dealerDealtCards = #GS.dealerHand
        
        -- Set player dealt cards - mark all cards as "dealt" so they display
        BJ.UI.dealtCards = {}
        for _, playerName in ipairs(GS.playerOrder) do
            local player = GS.players[playerName]
            if player and player.hands then
                for h, hand in ipairs(player.hands) do
                    local cardKey = playerName .. "_" .. h
                    BJ.UI.dealtCards[cardKey] = #hand
                end
            end
        end
        
        -- Clear any animation state
        BJ.UI.isDealingAnimation = false
    end
    
    -- If we were in recovery mode, receiving a full state sync means game is resuming
    local MP = BJ.Multiplayer
    if MP.hostDisconnected then
        BJ:Print("|cff00ff00Received state sync - game resuming!|r")
        
        -- Cancel local timer
        if MP.localRecoveryTimer then
            MP.localRecoveryTimer:Cancel()
            MP.localRecoveryTimer = nil
        end
        
        -- Close recovery popup
        MP:CloseRecoveryPopup()
        
        -- Clear recovery state
        MP.hostDisconnected = false
        MP.originalHost = nil
        MP.temporaryHost = nil
        MP.recoveryStartTime = nil
        MP.restoringHost = false
        
        if BJ.UI and BJ.UI.OnHostRestored then
            BJ.UI:OnHostRestored()
        end
    end
    
    BJ:Debug("StateSync: Applied Blackjack state, phase=" .. (GS.phase or "nil") .. 
        ", dealer cards=" .. #GS.dealerHand .. ", players=" .. #GS.playerOrder ..
        ", shoe size=" .. (#GS.shoe or 0) .. ", cardIndex=" .. (GS.cardIndex or 0))
    return true
end

-- Apply Poker state
function SS:ApplyPokerState(state)
    if not state then return false end
    
    local PS = BJ.PokerState
    local PM = BJ.PokerMultiplayer
    if not PS then return false end
    
    -- Apply basic info
    PS.phase = state.phase
    PS.hostName = state.hostName
    PS.ante = state.ante
    PS.pot = state.pot
    PS.currentBet = state.currentBet
    PS.currentStreet = state.currentStreet or 0
    PS.maxRaise = state.maxRaise or 100
    PS.seed = state.seed
    
    -- Store synced cards remaining for non-host clients FIRST
    PS.syncedCardsRemaining = state.cardsRemaining
    
    -- Regenerate deck from seed if we're the returning host
    -- This is important so the deck is in the same state
    local myName = UnitName("player")
    local isReturningHost = state.hostName == myName
    
    if state.seed and isReturningHost then
        BJ:Debug("[Sync] Regenerating poker deck from seed " .. state.seed)
        PS:CreateDeck(state.seed)
        
        -- Apply card index AFTER deck regeneration (CreateDeck resets to 1)
        if state.cardIndex and state.cardIndex > 1 then
            PS.cardIndex = state.cardIndex
            BJ:Debug("[Sync] Applied poker cardIndex=" .. PS.cardIndex .. ", remaining=" .. PS:GetRemainingCards())
        elseif state.cardsRemaining then
            -- Calculate cardIndex from cardsRemaining if cardIndex wasn't provided correctly
            PS.cardIndex = 52 - state.cardsRemaining + 1
            BJ:Debug("[Sync] Calculated poker cardIndex=" .. PS.cardIndex .. " from remaining=" .. state.cardsRemaining)
        end
    end
    PS.syncedCardsRemaining = state.cardsRemaining
    
    -- Apply player order and indices
    PS.playerOrder = state.playerOrder or {}
    PS.currentPlayerIndex = state.currentPlayerIndex
    PS.dealerIndex = state.dealerIndex
    
    -- Apply all player data
    PS.players = state.players or {}
    
    -- Apply betting round
    PS.bettingRound = state.bettingRound
    
    -- Update multiplayer host tracking
    if PM and state.hostName then
        PM.currentHost = state.hostName
        PM.tableOpen = true
        PM.isHost = (state.hostName == UnitName("player"))
    end
    
    -- Initialize UI dealtCards so synced cards appear immediately
    if BJ.UI and BJ.UI.Poker then
        BJ.UI.Poker.dealtCards = {}
        for playerName, player in pairs(PS.players) do
            if player.hand then
                BJ.UI.Poker.dealtCards[playerName] = #player.hand
            end
        end
    end
    
    BJ:Debug("StateSync: Applied Poker state, phase=" .. (PS.phase or "nil") .. 
        ", players=" .. #PS.playerOrder .. ", cardIndex=" .. (PS.cardIndex or 0))
    return true
end

-- Apply High-Lo state
function SS:ApplyHiLoState(state)
    if not state then return false end
    
    local HL = BJ.HiLoState
    local HLM = BJ.HiLoMultiplayer
    if not HL then return false end
    
    -- Apply basic info
    HL.phase = state.phase
    HL.hostName = state.hostName
    HL.maxRoll = state.maxRoll
    HL.joinTimer = state.joinTimer
    HL.lobbyStartTime = state.lobbyStartTime
    HL.rollStartTime = state.rollStartTime
    
    -- Apply player order
    HL.playerOrder = state.playerOrder or {}
    
    -- Apply all player data
    HL.players = state.players or {}
    
    -- Apply settlement data
    HL.highPlayer = state.highPlayer
    HL.highRoll = state.highRoll
    HL.lowPlayer = state.lowPlayer
    HL.lowRoll = state.lowRoll
    HL.winAmount = state.winAmount
    
    -- Apply tiebreaker state
    HL.tiebreakerPlayers = state.tiebreakerPlayers
    HL.tiebreakerType = state.tiebreakerType
    HL.tiebreakerRolls = state.tiebreakerRolls
    
    -- Apply multiplayer timer state and host tracking
    if HLM then
        HLM.joinStartTime = state.joinStartTime
        HLM.joinDuration = state.joinDuration
        
        -- Update host tracking
        if state.hostName then
            HLM.currentHost = state.hostName
            HLM.tableOpen = true
            HLM.isHost = (state.hostName == UnitName("player"))
        end
    end
    
    BJ:Debug("StateSync: Applied High-Lo state, phase=" .. (HL.phase or "nil") .. 
        ", players=" .. #HL.playerOrder)
    return true
end

-- Apply Craps state
function SS:ApplyCrapsState(state)
    if not state then return false end
    
    local CS = BJ.CrapsState
    local CM = BJ.CrapsMultiplayer
    if not CS then return false end
    
    -- Apply basic info
    CS.phase = state.phase
    CS.hostName = state.hostName
    CS.shooterName = state.shooterName
    CS.point = state.point
    
    -- Apply table settings
    CS.minBet = state.minBet
    CS.maxBet = state.maxBet
    CS.maxOdds = state.maxOdds
    CS.bettingTimer = state.bettingTimer
    CS.tableCap = state.tableCap
    CS.currentRisk = state.currentRisk
    
    -- Apply shooter order
    CS.shooterOrder = state.shooterOrder or {}
    
    -- Apply last roll
    CS.lastRoll = state.lastRoll
    
    -- Apply all player data with deep copy of bets
    CS.players = {}
    for playerName, playerData in pairs(state.players or {}) do
        CS.players[playerName] = {
            balance = playerData.balance,
            startBalance = playerData.startBalance,
            sessionBalance = playerData.sessionBalance,
            lockedIn = playerData.lockedIn,
            isHost = playerData.isHost,
            isSpectator = playerData.isSpectator,
            bets = CS:CreateEmptyBets(),
        }
        
        -- Deep copy bets
        if playerData.bets then
            for k, v in pairs(playerData.bets) do
                if type(v) == "table" then
                    CS.players[playerName].bets[k] = {}
                    for k2, v2 in pairs(v) do
                        CS.players[playerName].bets[k][k2] = v2
                    end
                else
                    CS.players[playerName].bets[k] = v
                end
            end
        end
    end
    
    -- Apply pending joins
    CS.pendingJoins = {}
    for playerName, request in pairs(state.pendingJoins or {}) do
        CS.pendingJoins[playerName] = {
            buyIn = request.buyIn,
            time = request.time,
        }
    end
    
    -- Apply multiplayer state
    if CM then
        if state.hostName then
            CM.currentHost = state.hostName
            CM.tableOpen = true
            CM.isHost = (state.hostName == UnitName("player"))
        end
    end
    
    BJ:Debug("StateSync: Applied Craps state, phase=" .. (CS.phase or "nil") .. 
        ", shooter=" .. (CS.shooterName or "nil"))
    return true
end

-- Check if a message is a full state message
function SS:IsFullStateMessage(message)
    return message and message:sub(1, #SS.MSG.FULL_STATE) == SS.MSG.FULL_STATE
end

-- Check if a message is a sync request
function SS:IsSyncRequestMessage(message)
    return message and message:sub(1, #SS.MSG.REQUEST_SYNC) == SS.MSG.REQUEST_SYNC
end

-- Check if a message is a discovery request
function SS:IsDiscoveryMessage(message)
    return message and message:sub(1, 8) == "DISCOVER"
end

-- Check if a message is a host announcement
function SS:IsHostAnnounceMessage(message)
    return message and message:sub(1, 10) == "HOSTANNOUN"
end

-- Extract game from sync request
function SS:ExtractSyncRequestGame(message)
    -- Format: REQSYNC|game
    local game = message:match("REQSYNC|(%w+)")
    return game
end

-- Extract data from full state message
function SS:ExtractFullStateData(message)
    -- Format: FULLSTATE|serializedData
    local data = message:match("FULLSTATE|(.+)")
    return data
end

-- Broadcast discovery request to find active game hosts
function SS:BroadcastDiscovery()
    local AceComm = LibStub("AceComm-3.0")
    local channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY" or nil)
    
    if not channel then
        BJ:Print("|cffff8800Not in a party or raid.|r")
        return false
    end
    
    -- Send discovery request on all three game channels
    AceComm:SendCommMessage("CCBlackjack", "DISCOVER|" .. UnitName("player"), channel)
    AceComm:SendCommMessage("CCPoker", "DISCOVER|" .. UnitName("player"), channel)
    AceComm:SendCommMessage("CCHiLo", "DISCOVER|" .. UnitName("player"), channel)
    
    BJ:Debug("StateSync: Broadcast discovery request")
    return true
end

-- Handle discovery request (hosts respond with their info)
function SS:HandleDiscoveryRequest(game, requesterName)
    local isHost = false
    local hostName = UnitName("player")
    local phase = nil
    
    if game == "blackjack" then
        isHost = BJ.Multiplayer and BJ.Multiplayer.isHost
        phase = BJ.GameState and BJ.GameState.phase
    elseif game == "poker" then
        isHost = BJ.PokerMultiplayer and BJ.PokerMultiplayer.isHost
        phase = BJ.PokerState and BJ.PokerState.phase
    elseif game == "hilo" then
        isHost = BJ.HiLoMultiplayer and BJ.HiLoMultiplayer.isHost
        phase = BJ.HiLoState and BJ.HiLoState.phase
    end
    
    -- Only respond if we're hosting an active game (not idle)
    if isHost and phase and phase ~= "idle" then
        local AceComm = LibStub("AceComm-3.0")
        -- Respond directly to requester with our host info
        local msg = "HOSTANNOUN|" .. game .. "|" .. hostName .. "|" .. (phase or "unknown")
        AceComm:SendCommMessage("CC" .. (game == "blackjack" and "Blackjack" or (game == "poker" and "Poker" or "HiLo")), 
            msg, "WHISPER", requesterName)
        BJ:Debug("StateSync: Announced as host for " .. game .. " to " .. requesterName)
    end
end

-- Handle host announcement (client learns about a host)
function SS:HandleHostAnnounce(game, hostName, phase)
    BJ:Debug("StateSync: Discovered " .. game .. " host: " .. hostName .. " (phase: " .. phase .. ")")
    
    -- Update the multiplayer module with the discovered host
    if game == "blackjack" and BJ.Multiplayer then
        BJ.Multiplayer.currentHost = hostName
        BJ.Multiplayer.tableOpen = true
    elseif game == "poker" and BJ.PokerMultiplayer then
        BJ.PokerMultiplayer.currentHost = hostName
        BJ.PokerMultiplayer.tableOpen = true
    elseif game == "hilo" and BJ.HiLoMultiplayer then
        BJ.HiLoMultiplayer.currentHost = hostName
        BJ.HiLoMultiplayer.tableOpen = true
    end
    
    -- Automatically request full sync from this host
    BJ:Print("|cff88ff88Found " .. game .. " host: " .. hostName .. " - Requesting sync...|r")
    self:RequestFullSync(game, hostName)
end
