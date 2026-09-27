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
    holdem = { current = 0, lastReceived = 0 },
    hilo = { current = 0, lastReceived = 0 },
}

-- Pending sync requests (to prevent spam)
SS.pendingSyncRequests = {
    blackjack = false,
    poker = false,
    holdem = false,
    hilo = false,
}

-- Cooldown tracking for sync responses (prevent double sync)
SS.lastSyncNotification = {  -- For "Found active game" messages
    blackjack = 0,
    poker = 0,
    holdem = 0,
    hilo = 0,
}
SS.lastSyncApplied = {  -- For actual state application
    blackjack = 0,
    poker = 0,
    holdem = 0,
    hilo = 0,
}
SS.SYNC_COOLDOWN = 5  -- Seconds to ignore duplicate syncs

-- Games a YOU_ARE_PLAYING just confirmed we're part of (rejoin after
-- reload/reconnect); when the full state lands we reopen that game's
-- window for the player. Keyed by game -> GetTime() of the confirmation.
SS.pendingAutoOpen = {}
SS.AUTO_OPEN_WINDOW = 30  -- seconds the confirmation stays actionable

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

--[[
    GAME REGISTRY
    Each game's Multiplayer module registers itself here (via GameComm:Embed)
    with: mp (the module), getState, getUI, prefix, displayName. StateSync's
    own per-game state serialization handlers live in SS.stateHandlers at the
    bottom of this file. Adding a game = one Embed call + one handler entry.
]]
SS.games = {}

function SS:RegisterGame(game, info)
    SS.games[game] = info

    -- Ensure tracking tables have entries for this game
    SS.versions[game] = SS.versions[game] or { current = 0, lastReceived = 0 }
    if SS.pendingSyncRequests[game] == nil then SS.pendingSyncRequests[game] = false end
    SS.lastSyncNotification[game] = SS.lastSyncNotification[game] or 0
    SS.lastSyncApplied[game] = SS.lastSyncApplied[game] or 0
end

-- User-facing game name for prints
function SS:GameName(game)
    local entry = SS.games[game]
    return entry and entry.displayName or game
end

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
    local myName = BJ:MyName()
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
    local myName = BJ:MyName()
    AceComm:SendCommMessage("CCDiscover", SS.MSG.AM_I_PLAYING .. "|" .. myName, channel)
end

-- Handle discovery messages
function SS:OnDiscoveryMessage(prefix, message, distribution, sender)
    local myName = BJ:MyName()
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
        local gameLink = BJ:CreateGameLink(game, SS:GameName(game))

        local entry = SS.games[game]
        local mp = entry and entry.mp
        if not mp then return end

        -- A host just confirmed we belong to this game: when its full state
        -- lands, reopen the window the player was sitting at
        SS.pendingAutoOpen[game] = GetTime()

        if isRecovery then
            -- Game is in recovery mode
            local origHost = parts[4]
            local tempHost = parts[5]
            local remaining = tonumber(parts[6]) or 120
            local myName = BJ:MyName()

            BJ:Print("|cffff8800Found " .. gameLink .. " game - PAUSED (waiting for " .. origHost .. ")|r")

            if game == "hilo" then
                -- High-Lo doesn't use recovery mode - host transfer is immediate
                -- This code path shouldn't be hit, but handle gracefully
                mp.currentHost = tempHost  -- New host is the temp host
                mp.tableOpen = true
                mp.isHost = (tempHost == myName)
                entry.getState().hostName = tempHost

                BJ:Print("|cff00ff00" .. tempHost .. " is the High-Lo host.|r")
                local ui = entry.getUI and entry.getUI()
                if ui and ui.UpdateDisplay then
                    ui:UpdateDisplay()
                end
            else
                -- Set recovery state (shared GameComm fields)
                mp.currentHost = origHost
                mp.originalHost = origHost
                mp.temporaryHost = tempHost
                mp.hostDisconnected = true
                mp.recoveryStartTime = time() - (mp.RECOVERY_TIMEOUT - remaining)
                mp.tableOpen = true
                mp.isHost = (origHost == myName)

                -- If we ARE the original host, restore
                if origHost == myName then
                    BJ:Print("|cff00ff00You have reconnected as host. Restoring game...|r")
                    mp:RestoreOriginalHost()
                else
                    mp:ShowRecoveryPopup(origHost, tempHost == myName)
                    mp:UpdateRecoveryPopupTimer(remaining)
                    local ui = entry.getUI and entry.getUI()
                    if ui and ui.OnHostRecoveryStart then
                        ui:OnHostRecoveryStart(origHost, tempHost)
                    end
                end
            end
        else
            -- Normal active game
            BJ:Print("|cff88ff88Found active " .. gameLink .. " game hosted by " .. hostName .. " - syncing...|r")

            -- Update multiplayer host tracking (but don't request sync - it's already coming)
            mp.currentHost = hostName
            mp.tableOpen = true
            mp.isHost = false
        end
    end
end

-- Check if we're hosting any active games and send sync to requesting player (for spectators too)
function SS:CheckIfPlayerInGame(playerName)
    local myName = BJ:MyName()

    for game, entry in pairs(SS.games) do
        local mp = entry.mp
        local state = entry.getState and entry.getState()
        local phase = state and state.phase

        -- Only respond as host (or temp host during recovery) with an active
        -- game (not idle or concluded settlement)
        if mp and (mp.isHost or mp.temporaryHost == myName)
            and phase and phase ~= "idle" and phase ~= "settlement" then

            if mp.hostDisconnected and mp.originalHost then
                -- Check if the ORIGINAL HOST is the one asking - if so, trigger restore!
                if playerName == mp.originalHost then
                    BJ:Print("|cff00ff00Original host " .. playerName .. " has reconnected! Restoring...|r")
                    mp:RestoreOriginalHost()
                else
                    -- Someone else asking - send recovery state
                    local remaining = mp.RECOVERY_TIMEOUT - (time() - (mp.recoveryStartTime or time()))
                    AceComm:SendCommMessage("CCDiscover", SS.MSG.YOU_ARE_PLAYING .. "|" .. game .. "|recovery|" ..
                        (mp.originalHost or "") .. "|" .. (mp.temporaryHost or "") .. "|" .. remaining, "WHISPER", playerName)
                end
            else
                -- Active game - send sync to anyone in party/raid (spectator or player)
                AceComm:SendCommMessage("CCDiscover", SS.MSG.YOU_ARE_PLAYING .. "|" .. game, "WHISPER", playerName)
                C_Timer.After(0.5, function()
                    SS:HandleSyncRequest(game, playerName)
                end)
            end
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
    for game, entry in pairs(SS.games) do
        if entry.mp and entry.mp.isHost then
            AceComm:SendCommMessage("CCDiscover", SS.MSG.HOST_ANNOUNCE .. "|" .. game, "WHISPER", requesterName)
        end
    end
end

-- Handle discovered host - update local state and request sync
function SS:OnHostDiscovered(game, hostName)
    BJ:Debug("StateSync: Discovered " .. game .. " host: " .. hostName)

    -- Update the multiplayer module with the host info
    local entry = SS.games[game]
    if entry and entry.mp then
        entry.mp.currentHost = hostName
        entry.mp.tableOpen = true
        BJ:Print("|cff88ff88Found " .. SS:GameName(game) .. " host: " .. hostName .. "|r")
        -- Request full sync
        SS:RequestFullSync(game, hostName)
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

    -- Send request via the game's own channel
    local entry = SS.games[game]
    if entry and entry.mp then
        entry.mp:SendWhisper(hostName, SS.MSG.REQUEST_SYNC, game)
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
    
    local handlers = SS.stateHandlers[game]
    if handlers and handlers.build then
        state.data = handlers.build(self)
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
        fakePlay = GS.fakePlay,   -- fun/real terms as opened
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
        fakePlay = PS.fakePlay,   -- fun/real terms as opened
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

-- Build Texas Hold'em full state
function SS:BuildHoldemState()
    local PS = BJ.HoldemState
    local PM = BJ.HoldemMultiplayer

    if not PS then return nil end

    local cardIndex, cardsRemaining
    if PS.deck and #PS.deck > 0 and PS.cardIndex and PS.cardIndex > 1 then
        cardIndex = PS.cardIndex
        cardsRemaining = #PS.deck - PS.cardIndex + 1
    elseif PS.syncedCardsRemaining then
        cardsRemaining = PS.syncedCardsRemaining
        cardIndex = 52 - PS.syncedCardsRemaining + 1
    else
        cardsRemaining = PS:GetRemainingCards()
        cardIndex = PS.cardIndex or 1
    end

    local state = {
        phase = PS.phase,
        hostName = PS.hostName,
        fakePlay = PS.fakePlay,   -- fun/real terms as opened
        smallBlind = PS.smallBlind,
        bigBlind = PS.bigBlind,
        pot = PS.pot,
        currentBet = PS.currentBet,
        currentStreet = PS.currentStreet,
        maxRaise = PS.maxRaise,
        seed = PS.seed,
        cardIndex = cardIndex,
        cardsRemaining = cardsRemaining,

        playerOrder = PS.playerOrder,
        currentPlayerIndex = PS.currentPlayerIndex,
        dealerIndex = PS.dealerIndex,

        -- Shared community cards
        communityCards = {},

        players = {},

        isHost = PM and PM.isHost or false,

        -- Tournament mode: the chip stacks are part of the table's truth,
        -- so a mid-tournament rejoin restores them with everything else
        tourney = PS.tourney and {
            buyIn = PS.tourney.buyIn,
            startChips = PS.tourney.startChips,
            started = PS.tourney.started,
            champion = PS.tourney.champion,
            settled = PS.tourney.settled,
            chips = PS.tourney.chips,
            entrants = PS.tourney.entrants,
            eliminated = PS.tourney.eliminated,
            out = PS.tourney.out,
        } or nil,
    }

    -- Copy community cards
    for _, card in ipairs(PS.communityCards or {}) do
        table.insert(state.communityCards, { rank = card.rank, suit = card.suit, faceUp = true })
    end

    -- Copy all player data (hole cards include faceUp state)
    for playerName, player in pairs(PS.players or {}) do
        local playerData = {
            hand = {},
            totalBet = player.totalBet,
            currentBet = player.currentBet or 0,
            folded = player.folded,
            allIn = player.allIn,
            handName = player.handName,
            handRank = player.handRank,
        }
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

        -- Table terms as opened + host-transfer epoch, so a rejoiner
        -- settles and orders transfers correctly
        opener = HL.opener,
        fakePlay = HL.fakePlay,
        hostEpoch = HLM and HLM.hostEpoch or nil,
        
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

    -- Send via the game's own channel
    local entry = SS.games[game]
    if entry and entry.prefix then
        -- Send with FULLSTATE prefix so receiver knows to deserialize
        AceComm:SendCommMessage(entry.prefix, SS.MSG.FULL_STATE .. "|" .. toSend, "WHISPER", targetPlayer)
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

    -- Broadcast to group on the game's own channel
    local entry = SS.games[game]
    if entry and entry.prefix then
        local channel = IsInRaid() and "RAID" or "PARTY"
        AceComm:SendCommMessage(entry.prefix, SS.MSG.FULL_STATE .. "|" .. toSend, channel)
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
    local gameName = SS:GameName(game)

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
    local handlers = SS.stateHandlers[game]
    if handlers and handlers.apply then
        applied = handlers.apply(self, stateData.data)
    end

    if applied then
        -- Update version tracking
        self.versions[game].lastReceived = stateData.version
        self.pendingSyncRequests[game] = false

        local entry = SS.games[game]
        local mp = entry and entry.mp

        -- If WE are this game's host after applying (e.g. the original host
        -- reclaiming after a recovery), resume the version stream from the
        -- dump: our next broadcast must be lastReceived+1 or every client
        -- silently discards it as an old version.
        if mp and mp.isHost then
            local v = self.versions[game]
            if v then v.current = math.max(v.current, v.lastReceived) end
        end

        -- Any game paused in host recovery that receives a full state is
        -- resuming (the temp host broadcasts one right after the host is
        -- restored): clear the pause generically, or the local recovery
        -- countdown voids a live game. Covers every registered game.
        if mp and mp.hostDisconnected then
            BJ:Print("|cff00ff00Received state sync - game resuming!|r")
            if mp.localRecoveryTimer then
                mp.localRecoveryTimer:Cancel()
                mp.localRecoveryTimer = nil
            end
            if mp.CloseRecoveryPopup then mp:CloseRecoveryPopup() end
            mp.hostDisconnected = false
            mp.originalHost = nil
            mp.temporaryHost = nil
            mp.recoveryStartTime = nil
            mp.restoringHost = false
            local ui = entry.getUI and entry.getUI()
            if ui and ui.OnHostRestored then ui:OnHostRestored() end
        end

        -- Success message with clickable game link
        local gameLink = BJ:CreateGameLink(game, gameName)
        BJ:Print("|cff00ff00Sync successful:|r " .. gameLink .. " state restored.")

        -- Update UI (per-game refresh choreography)
        if handlers and handlers.onSynced then
            handlers.onSynced()
        end

        -- Rejoin-on-reload: a YOU_ARE_PLAYING told us we belong to this
        -- game and its state has now landed - reopen the window the player
        -- was sitting at. Ordinary broadcast syncs never pop windows (a
        -- player may have closed theirs on purpose).
        local pending = SS.pendingAutoOpen[game]
        if pending and (GetTime() - pending) < SS.AUTO_OPEN_WINDOW then
            SS.pendingAutoOpen[game] = nil
            local myName = BJ:MyName()
            local st = entry and entry.getState and entry.getState()
            local seated = st and ((st.players and st.players[myName] ~= nil)
                or st.hostName == myName
                or st.opponent == myName)   -- Death Roll has no players table
            local active = st and st.phase and st.phase ~= "idle" and st.phase ~= "settlement"
            if seated and active and BJ.OpenGameWindow then
                if BJ.CloseAllGameWindows then BJ:CloseAllGameWindows() end
                BJ:OpenGameWindow(game)
            end
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
    GS.fakePlay = state.fakePlay
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
        MP.isHost = (state.hostName == BJ:MyName())
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
    
    -- (Recovery-pause clearing on resume is handled generically for every
    -- game in HandleFullState, which is the only caller of this apply.)

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
    PS.fakePlay = state.fakePlay
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
    local myName = BJ:MyName()
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
        PM.isHost = (state.hostName == BJ:MyName())
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

    -- (Recovery-pause clearing on resume is handled generically for every
    -- game in HandleFullState, which is the only caller of this apply.)

    BJ:Debug("StateSync: Applied Poker state, phase=" .. (PS.phase or "nil") ..
        ", players=" .. #PS.playerOrder .. ", cardIndex=" .. (PS.cardIndex or 0))
    return true
end

-- Apply Texas Hold'em state
function SS:ApplyHoldemState(state)
    if not state then return false end

    local PS = BJ.HoldemState
    local PM = BJ.HoldemMultiplayer
    if not PS then return false end

    PS.phase = state.phase
    PS.hostName = state.hostName
    PS.fakePlay = state.fakePlay
    PS.smallBlind = state.smallBlind
    PS.bigBlind = state.bigBlind
    PS.pot = state.pot
    PS.currentBet = state.currentBet
    PS.currentStreet = state.currentStreet or 0
    PS.maxRaise = state.maxRaise or 100
    PS.seed = state.seed

    -- Tournament restoration: never re-record debts from a sync (settled
    -- follows the champion), and rebuild the hand cap from the chips
    if state.tourney then
        PS.tourney = {
            buyIn = state.tourney.buyIn or 10,
            startChips = state.tourney.startChips or 1000,
            started = state.tourney.started and true or false,
            champion = state.tourney.champion,
            settled = state.tourney.settled or (state.tourney.champion ~= nil),
            chips = state.tourney.chips or {},
            entrants = state.tourney.entrants or {},
            eliminated = state.tourney.eliminated or {},
            out = state.tourney.out or {},
        }
        PS:RecomputeTourneyCap()
    else
        PS.tourney = nil
        PS.tourneyHandCap = nil
    end

    PS.syncedCardsRemaining = state.cardsRemaining

    local myName = BJ:MyName()
    local isReturningHost = state.hostName == myName
    if state.seed and isReturningHost then
        BJ:Debug("[Sync] Regenerating holdem deck from seed " .. state.seed)
        PS:CreateDeck(state.seed)
        if state.cardIndex and state.cardIndex > 1 then
            PS.cardIndex = state.cardIndex
        elseif state.cardsRemaining then
            PS.cardIndex = 52 - state.cardsRemaining + 1
        end
    end
    PS.syncedCardsRemaining = state.cardsRemaining

    PS.playerOrder = state.playerOrder or {}
    PS.currentPlayerIndex = state.currentPlayerIndex
    PS.dealerIndex = state.dealerIndex or 1
    PS.players = state.players or {}

    -- Restore the shared community cards
    PS.communityCards = state.communityCards or {}

    if PM and state.hostName then
        PM.currentHost = state.hostName
        PM.tableOpen = true
        PM.isHost = (state.hostName == BJ:MyName())
        PM.dealerIndex = PS.dealerIndex
    end

    if BJ.UI and BJ.UI.Holdem then
        BJ.UI.Holdem.dealtCards = {}
        for playerName, player in pairs(PS.players) do
            if player.hand then
                BJ.UI.Holdem.dealtCards[playerName] = #player.hand
            end
        end
    end

    -- (Recovery-pause clearing on resume is handled generically for every
    -- game in HandleFullState, which is the only caller of this apply.)

    BJ:Debug("StateSync: Applied Holdem state, phase=" .. (PS.phase or "nil") ..
        ", players=" .. #PS.playerOrder .. ", community=" .. #PS.communityCards)
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
    HL.opener = state.opener
    HL.fakePlay = state.fakePlay
    
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
            HLM.isHost = (state.hostName == BJ:MyName())
        end
        if state.hostEpoch then
            HLM.hostEpoch = math.max(tonumber(state.hostEpoch) or 1, HLM.hostEpoch or 0)
        end
    end
    
    BJ:Debug("StateSync: Applied High-Lo state, phase=" .. (HL.phase or "nil") .. 
        ", players=" .. #HL.playerOrder)
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
    local channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY" or nil)

    if not channel then
        BJ:Print("|cffff8800Not in a party or raid.|r")
        return false
    end

    -- Send discovery request on every registered game channel
    for game, entry in pairs(SS.games) do
        if entry.prefix then
            AceComm:SendCommMessage(entry.prefix, "DISCOVER|" .. BJ:MyName(), channel)
        end
    end

    BJ:Debug("StateSync: Broadcast discovery request")
    return true
end

-- Handle discovery request (hosts respond with their info)
function SS:HandleDiscoveryRequest(game, requesterName)
    local entry = SS.games[game]
    if not entry then return end

    local hostName = BJ:MyName()
    local isHost = entry.mp and entry.mp.isHost
    local state = entry.getState and entry.getState()
    local phase = state and state.phase

    -- Only respond if we're hosting an active game (not idle)
    if isHost and phase and phase ~= "idle" then
        -- Respond directly to requester with our host info
        local msg = "HOSTANNOUN|" .. game .. "|" .. hostName .. "|" .. (phase or "unknown")
        AceComm:SendCommMessage(entry.prefix, msg, "WHISPER", requesterName)
        BJ:Debug("StateSync: Announced as host for " .. game .. " to " .. requesterName)
    end
end

-- Handle host announcement (client learns about a host)
function SS:HandleHostAnnounce(game, hostName, phase)
    BJ:Debug("StateSync: Discovered " .. game .. " host: " .. hostName .. " (phase: " .. phase .. ")")

    -- Update the multiplayer module with the discovered host
    local entry = SS.games[game]
    if entry and entry.mp then
        entry.mp.currentHost = hostName
        entry.mp.tableOpen = true
    end

    -- Automatically request full sync from this host
    BJ:Print("|cff88ff88Found " .. game .. " host: " .. hostName .. " - Requesting sync...|r")
    self:RequestFullSync(game, hostName)
end

--[[
    PER-GAME STATE SERIALIZATION HANDLERS
    build/apply pack and unpack each game's full state; onSynced runs the
    game's UI refresh choreography after a successful sync. Defined at the
    end of the file so the Build*/Apply* functions above already exist.
]]
SS.stateHandlers = {
    blackjack = {
        build = SS.BuildBlackjackState,
        apply = SS.ApplyBlackjackState,
        onSynced = function()
            if BJ.UI then
                BJ.UI:UpdateDisplay()
            end
        end,
    },
    poker = {
        build = SS.BuildPokerState,
        apply = SS.ApplyPokerState,
        onSynced = function()
            if not (BJ.UI and BJ.UI.Poker) then return end
            BJ.UI.Poker:UpdateDisplay()
            BJ.UI.Poker:UpdateInfoText()  -- Ensure seed is shown
            -- Delayed button update to ensure state is fully applied
            C_Timer.After(0.1, function()
                if BJ.UI and BJ.UI.Poker and BJ.UI.Poker.isInitialized then
                    local PS = BJ.PokerState
                    local myName = BJ:MyName()
                    BJ:Debug("Post-sync button update: phase=" .. tostring(PS.phase) ..
                        ", currentPlayerIdx=" .. tostring(PS.currentPlayerIndex) ..
                        ", currentPlayer=" .. tostring(PS:GetCurrentPlayer()) ..
                        ", myName=" .. myName)
                    BJ.UI.Poker:UpdateButtons()
                    BJ.UI.Poker:UpdateInfoText()  -- Update again after delay
                end
            end)
        end,
    },
    holdem = {
        build = SS.BuildHoldemState,
        apply = SS.ApplyHoldemState,
        onSynced = function()
            if not (BJ.UI and BJ.UI.Holdem) then return end
            BJ.UI.Holdem:UpdateDisplay()
            BJ.UI.Holdem:UpdateInfoText()
            C_Timer.After(0.1, function()
                if BJ.UI and BJ.UI.Holdem and BJ.UI.Holdem.isInitialized then
                    BJ.UI.Holdem:UpdateButtons()
                    BJ.UI.Holdem:UpdateInfoText()
                end
            end)
        end,
    },
    hilo = {
        build = SS.BuildHiLoState,
        apply = SS.ApplyHiLoState,
        onSynced = function()
            if BJ.UI and BJ.UI.HiLo then
                BJ.UI.HiLo:UpdateDisplay()
            end
        end,
    },
    deathroll = {
        build = function()
            local DR = BJ.DeathRollState
            if not DR then return nil end
            return {
                phase = DR.phase,
                hostName = DR.hostName,
                fakePlay = DR.fakePlay,   -- fun/real terms as opened
                opponent = DR.opponent,
                stake = DR.stake,
                currentMax = DR.currentMax,
                currentRoller = DR.currentRoller,
                rolls = DR.rolls,
                winner = DR.winner,
                loser = DR.loser,
            }
        end,
        apply = function(_, state)
            if not state then return false end
            local DR = BJ.DeathRollState
            local DRM = BJ.DeathRollMultiplayer
            if not DR then return false end

            DR.phase = state.phase
            DR.hostName = state.hostName
            DR.fakePlay = state.fakePlay
            DR.opponent = state.opponent
            DR.stake = state.stake or 0
            DR.currentMax = state.currentMax or 0
            DR.currentRoller = state.currentRoller
            DR.rolls = state.rolls or {}
            DR.winner = state.winner
            DR.loser = state.loser

            if DRM and state.hostName then
                DRM.currentHost = state.hostName
                DRM.tableOpen = true
                DRM.isHost = (state.hostName == BJ:MyName())
            end
            return true
        end,
        onSynced = function()
            if BJ.UI and BJ.UI.DeathRoll then
                BJ.UI.DeathRoll:UpdateDisplay()
            end
        end,
    },
    bingo = {
        build = function()
            local BS = BJ.BingoState
            local BM = BJ.BingoMultiplayer
            if not BS then return nil end
            return {
                phase = BS.phase,
                hostName = BS.hostName,
                cardPrice = BS.cardPrice,
                seed = BS.seed,
                playerOrder = BS.playerOrder,
                drawn = BS.drawn,
                winners = BS.winners,
                pot = BS.pot,
                share = BS.share,
                -- Table terms as opened + caller-migration epoch, so a
                -- rejoiner settles and orders host swaps correctly
                opener = BS.opener,
                fakePlay = BS.fakePlay,
                hostEpoch = BM and BM.hostEpoch or nil,
            }
        end,
        apply = function(_, state)
            if not state then return false end
            local BS = BJ.BingoState
            local BM = BJ.BingoMultiplayer
            if not BS or not state.seed then return false end

            BS:Reset()
            BS.phase = BS.PHASE.LOBBY  -- so AddPlayer works while rebuilding
            BS.hostName = state.hostName
            BS.cardPrice = state.cardPrice or 0
            BS.seed = state.seed
            BS.opener = state.opener
            BS.fakePlay = state.fakePlay

            -- Cards are deterministic from (seed, name); rebuild them
            for _, name in ipairs(state.playerOrder or {}) do
                BS:AddPlayer(name)
            end

            BS.phase = state.phase
            for _, n in ipairs(state.drawn or {}) do
                table.insert(BS.drawn, n)
                BS.drawnSet[n] = true
            end
            BS.drawIndex = #BS.drawn
            BS.winners = state.winners or {}
            BS.pot = state.pot or 0
            BS.share = state.share or 0

            if BM and state.hostName then
                BM.currentHost = state.hostName
                BM.tableOpen = true
                BM.isHost = (state.hostName == BJ:MyName())
                if state.hostEpoch then
                    BM.hostEpoch = math.max(tonumber(state.hostEpoch) or 1, BM.hostEpoch or 0)
                end

                -- Returning host mid-draw: rebuild the deterministic pool
                -- and resume calling from where the draw left off
                if BM.isHost and BS.phase == BS.PHASE.DRAWING then
                    BS:BuildDrawPool()
                    BM:StartDrawTicker()
                end
            end
            return true
        end,
        onSynced = function()
            if BJ.UI and BJ.UI.Bingo then
                BJ.UI.Bingo:UpdateDisplay()
            end
        end,
    },
    roulette = {
        build = function()
            local RS = BJ.RouletteState
            if not RS then return nil end
            local bets = {}
            for _, name in ipairs(RS.playerOrder) do
                bets[name] = RS.players[name] and RS.players[name].bets
            end
            return {
                phase = RS.phase,
                hostName = RS.hostName,
                fakePlay = RS.fakePlay,   -- fun/real terms as opened
                chip = RS.chip,
                maxBets = RS.maxBets,
                playerOrder = RS.playerOrder,
                bets = bets,
                spinSeed = RS.spinSeed,
                winningNumber = RS.winningNumber,
                settlements = RS.settlements,
                recentNumbers = RS.recentNumbers,
            }
        end,
        apply = function(_, state)
            if not state then return false end
            local RS = BJ.RouletteState
            local RM = BJ.RouletteMultiplayer
            if not RS then return false end

            RS:Reset()
            RS.phase = RS.PHASE.BETTING  -- so AddPlayer/SetBet work while rebuilding
            RS.hostName = state.hostName
            RS.fakePlay = state.fakePlay
            RS.chip = state.chip or 0
            RS.maxBets = state.maxBets or 5
            RS.recentNumbers = state.recentNumbers or {}
            for _, name in ipairs(state.playerOrder or {}) do
                RS:AddPlayer(name)
                local bets = state.bets and state.bets[name]
                if bets then
                    for key, amt in pairs(bets) do
                        RS:SetBet(name, key, amt)
                    end
                end
            end
            RS.phase = state.phase
            RS.spinSeed = state.spinSeed
            RS.winningNumber = state.winningNumber
            RS.settlements = state.settlements

            if RM and state.hostName then
                RM.currentHost = state.hostName
                RM.tableOpen = true
                RM.isHost = (state.hostName == BJ:MyName())
            end

            -- Rejoined mid-spin: the show is unwatchable now, settle straight away
            if RS.phase == RS.PHASE.SPINNING then
                RS:FinishSpin()
            end
            return true
        end,
        onSynced = function()
            if BJ.UI and BJ.UI.Roulette then
                BJ.UI.Roulette:UpdateDisplay()
            end
        end,
    },
    crash = {
        -- The host's SECRET is deliberately absent: whispering it in a full
        -- state dump would hand the requester the crash point mid-flight.
        -- A host who reloads therefore cannot resume the round; the apply
        -- path detects that and voids it (antes returned).
        build = function()
            local CS = BJ.CrashState
            if not CS then return nil end
            local targets, cashed, refunded = {}, {}, {}
            for _, name in ipairs(CS.playerOrder) do
                local p = CS.players[name]
                if p then
                    targets[name] = p.target
                    cashed[name] = p.cashedOut
                    refunded[name] = p.refunded or nil
                end
            end
            return {
                phase = CS.phase,
                hostName = CS.hostName,
                fakePlay = CS.fakePlay,   -- fun/real terms as opened
                ante = CS.ante,
                playerOrder = CS.playerOrder,
                targets = targets,
                cashed = cashed,
                refunded = refunded,
                commit = CS.commit,
                entropyRoll = CS.entropyRoll,
                tick = (CS.phase == CS.PHASE.FLIGHT) and CS:CurrentTick() or nil,
                crashPoint = CS.crashPoint,
                settlements = CS.settlements,
                pot = CS.pot,
                winners = CS.winners,
                recentCrashes = CS.recentCrashes,
            }
        end,
        apply = function(_, state)
            if not state then return false end
            local CS = BJ.CrashState
            local CM = BJ.CrashMultiplayer
            if not CS then return false end

            CS:Reset()
            CS.phase = CS.PHASE.BOARDING  -- so AddPlayer works while rebuilding
            CS.hostName = state.hostName
            CS.fakePlay = state.fakePlay
            CS.ante = state.ante or 0
            for _, name in ipairs(state.playerOrder or {}) do
                CS:AddPlayer(name, state.targets and state.targets[name])
                local p = CS.players[name]
                if p then
                    p.cashedOut = state.cashed and state.cashed[name] or nil
                    p.refunded = (state.refunded and state.refunded[name]) or false
                end
            end
            CS.phase = state.phase
            CS.commit = state.commit
            CS.entropyRoll = state.entropyRoll
            CS.crashPoint = state.crashPoint
            CS.crashTick = state.crashPoint and CS:CrashTickFor(state.crashPoint) or nil
            CS.settlements = state.settlements
            CS.pot = state.pot
            CS.winners = state.winners
            CS.recentCrashes = state.recentCrashes or {}
            if state.phase == CS.PHASE.FLIGHT and state.tick then
                CS.flightStart = GetTime() - state.tick * CS.TICK_SECONDS
            end

            if CM and state.hostName then
                CM.currentHost = state.hostName
                CM.tableOpen = true
                CM.isHost = (state.hostName == BJ:MyName())
                if state.phase == CS.PHASE.FLIGHT then
                    if CM.isHost then
                        -- We reloaded mid-flight: the secret is gone and the
                        -- round can never finish. Void it for everyone.
                        C_Timer.After(0.5, function() CM:VoidUnfinishableRound() end)
                    else
                        CM:StartClientFlightTicker()
                    end
                end
            end
            return true
        end,
        onSynced = function()
            if BJ.UI and BJ.UI.Crash then
                BJ.UI.Crash:UpdateDisplay()
            end
        end,
    },
    liarsdice = {
        -- Only ever carries the safe shared fields (no dice faces during
        -- bidding). A reconnecting player learns their own hand by asking the
        -- host again in onSynced; the reveal (round already over) is included.
        build = function()
            local LD = BJ.LiarsDiceState
            if not LD then return nil end
            local counts, alive = {}, {}
            for _, name in ipairs(LD.playerOrder) do
                local p = LD.players[name]
                if p then
                    counts[name] = p.count
                    alive[name] = p.alive
                end
            end
            return {
                phase = LD.phase,
                hostName = LD.hostName,
                stake = LD.stake,
                onesWild = LD.onesWild,
                startDice = LD.startDice,
                playerOrder = LD.playerOrder,
                counts = counts,
                alive = alive,
                roundNum = LD.roundNum,
                firstBidder = LD.firstBidder,
                currentBid = LD.currentBid,
                currentBidderIndex = LD.currentBidderIndex,
                bidLog = LD.bidLog,
                lastLoser = LD.lastLoser,
                winner = LD.winner,
                reveal = LD.reveal,
                -- Table terms as opened + host-migration epoch, so a
                -- rejoiner settles and orders host swaps correctly
                opener = LD.opener,
                fakePlay = LD.fakePlay,
                hostEpoch = BJ.LiarsDiceMultiplayer and BJ.LiarsDiceMultiplayer.hostEpoch or nil,
            }
        end,
        apply = function(_, state)
            if not state then return false end
            local LD = BJ.LiarsDiceState
            local LDM = BJ.LiarsDiceMultiplayer
            if not LD then return false end

            LD:Reset()
            LD.phase = LD.PHASE.LOBBY  -- so AddPlayer works while rebuilding
            LD.hostName = state.hostName
            LD.stake = state.stake or 0
            LD.onesWild = state.onesWild ~= false
            LD.startDice = tonumber(state.startDice) or LD.START_DICE
            LD.opener = state.opener
            LD.fakePlay = state.fakePlay

            for _, name in ipairs(state.playerOrder or {}) do
                LD:AddPlayer(name)
                local p = LD.players[name]
                if p then
                    if state.counts and state.counts[name] ~= nil then p.count = state.counts[name] end
                    if state.alive and state.alive[name] ~= nil then p.alive = state.alive[name] end
                end
            end

            LD.roundNum = state.roundNum or 0
            LD.firstBidder = state.firstBidder
            LD.currentBid = state.currentBid
            LD.currentBidderIndex = state.currentBidderIndex or 0
            LD.bidLog = state.bidLog or {}
            LD.lastLoser = state.lastLoser
            LD.winner = state.winner
            LD.reveal = state.reveal
            LD.phase = state.phase

            if LDM and state.hostName then
                LDM.currentHost = state.hostName
                LDM.tableOpen = true
                LDM.isHost = (state.hostName == BJ:MyName())
                if state.hostEpoch then
                    LDM.hostEpoch = math.max(tonumber(state.hostEpoch) or 1, LDM.hostEpoch or 0)
                end
            end
            return true
        end,
        onSynced = function()
            local LD = BJ.LiarsDiceState
            local LDM = BJ.LiarsDiceMultiplayer
            if BJ.UI and BJ.UI.LiarsDice then
                BJ.UI.LiarsDice:UpdateDisplay()
            end
            -- If we're mid-bid and don't hold our hand, ask the host for it
            if LD and LDM and not LDM.isHost and LD.phase == LD.PHASE.BIDDING then
                local myName = BJ:MyName()
                local p = LD.players[myName]
                if p and p.alive and LD.myDiceRound ~= LD.roundNum then
                    C_Timer.After(0.5, function()
                        LDM:RequestMyDice()
                    end)
                end
            end
        end,
    },
}
