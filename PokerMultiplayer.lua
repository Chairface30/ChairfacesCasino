--[[
    Chairface's Casino - PokerMultiplayer.lua
    Network communication for 5 Card Stud poker with betting rounds
    Uses AceComm for reliable message delivery
]]

local BJ = ChairfacesCasino
BJ.PokerMultiplayer = {}
local PM = BJ.PokerMultiplayer

-- Get AceComm library
local AceComm = LibStub("AceComm-3.0")

local CHANNEL_PREFIX = "CCPoker"
local COMM_DELIMITER = "|"

local MSG = {
    TABLE_OPEN = "PTOPEN",
    TABLE_CLOSE = "PTCLOSE",
    COUNTDOWN = "PCDOWN",
    ANTE = "PANTE",
    LEAVE = "PLEAVE",
    DEAL_START = "PDEALSTART",  -- New: sync player list before dealing
    DEAL_CARD = "PCARD",
    BETTING_START = "PBETSTART",
    ACTION = "PACTION",
    BETTING_END = "PBETEND",
    SHOWDOWN = "PSHOW",
    SETTLEMENT = "PSETTLE",
    SYNC_STATE = "PSYNC",
    VERSION_REJECT = "PVREJECT",
}

PM.isHost = false
PM.currentHost = nil
PM.tableOpen = false
PM.countdownActive = false
PM.countdownRemaining = 0
PM.countdownTimer = nil

-- Turn timer state (local only - each client manages their own timer)
PM.TURN_TIME_LIMIT = 60        -- 60 seconds per turn
PM.TURN_WARNING_TIME = 10      -- Show warning at 10 seconds
PM.turnTimerActive = false
PM.turnTimerRemaining = 0
PM.turnTimer = nil

local function serialize(...)
    local parts = {...}
    for i, v in ipairs(parts) do parts[i] = tostring(v) end
    return table.concat(parts, COMM_DELIMITER)
end

local function deserialize(msg)
    local parts = {}
    for part in string.gmatch(msg, "[^" .. COMM_DELIMITER .. "]+") do
        table.insert(parts, part)
    end
    return parts
end

function PM:Initialize()
    -- Register AceComm callback for our prefix
    AceComm:RegisterComm(CHANNEL_PREFIX, function(prefix, message, distribution, sender)
        PM:OnCommReceived(prefix, message, distribution, sender)
    end)
    
    -- Register for group roster updates and connection changes
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("GROUP_ROSTER_UPDATE")
    frame:RegisterEvent("UNIT_CONNECTION")
    frame:SetScript("OnEvent", function(self, event, ...)
        if event == "GROUP_ROSTER_UPDATE" or event == "UNIT_CONNECTION" then 
            PM:OnRosterUpdate() 
        end
    end)
    
    BJ:Debug("Poker Multiplayer initialized with AceComm")
end

function PM:Send(msgType, ...)
    local args = {...}
    local msg
    
    -- For SYNC_STATE messages from host, automatically add version
    if msgType == MSG.SYNC_STATE and PM.isHost and BJ.StateSync then
        local version = BJ.StateSync:IncrementVersion("poker")
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
        end
        
        AceComm:SendCommMessage(CHANNEL_PREFIX, compressed, channel)
        BJ:Debug("Poker sent: " .. (wasCompressed and "[compressed]" or msg))
    end
end

function PM:SendWhisper(target, msgType, ...)
    local msg = serialize(msgType, ...)
    
    -- Compress if available
    local compressed, wasCompressed = msg, false
    if BJ.Compression and BJ.Compression.available then
        compressed, wasCompressed = BJ.Compression:Compress(msg)
    end
    
    AceComm:SendCommMessage(CHANNEL_PREFIX, compressed, "WHISPER", target)
    BJ:Debug("Poker whisper to " .. target .. ": " .. (wasCompressed and "[compressed]" or msg))
end

function PM:OnCommReceived(prefix, message, distribution, sender)
    if prefix ~= CHANNEL_PREFIX then return end
    local myName = UnitName("player")
    local senderName = sender:match("^([^-]+)") or sender
    if senderName == myName then return end
    
    -- Check for StateSync full state message first (before decompression)
    if BJ.StateSync and BJ.StateSync:IsFullStateMessage(message) then
        local stateData = BJ.StateSync:ExtractFullStateData(message)
        if stateData then
            BJ.StateSync:HandleFullState("poker", stateData)
        end
        return
    end
    
    -- Check for StateSync request (host only)
    if BJ.StateSync and BJ.StateSync:IsSyncRequestMessage(message) then
        if PM.isHost then
            local game = BJ.StateSync:ExtractSyncRequestGame(message)
            if game == "poker" then
                BJ.StateSync:HandleSyncRequest("poker", senderName)
            end
        end
        return
    end
    
    -- Check for discovery request (host responds)
    if BJ.StateSync and BJ.StateSync:IsDiscoveryMessage(message) then
        BJ.StateSync:HandleDiscoveryRequest("poker", senderName)
        return
    end
    
    -- Check for host announcement (client learns about host)
    if BJ.StateSync and BJ.StateSync:IsHostAnnounceMessage(message) then
        local game, hostName, phase = message:match("HOSTANNOUN|(%w+)|([^|]+)|(.+)")
        if game == "poker" then
            BJ.StateSync:HandleHostAnnounce("poker", hostName, phase)
        end
        return
    end
    
    -- Decompress if needed
    if BJ.Compression then
        local decompressed = BJ.Compression:Decompress(message)
        if decompressed then
            message = decompressed
        elseif message:sub(1, 1) == "~" then
            BJ:Debug("Cannot decompress poker message from " .. sender)
            return
        end
    end
    
    local parts = deserialize(message)
    local msgType = parts[1]
    BJ:Debug("Poker recv: " .. message)
    
    if msgType == MSG.TABLE_OPEN then self:HandleTableOpen(sender, parts)
    elseif msgType == MSG.TABLE_CLOSE then self:HandleTableClose(sender, parts)
    elseif msgType == MSG.COUNTDOWN then self:HandleCountdown(sender, parts)
    elseif msgType == MSG.ANTE then self:HandleAnte(sender, parts)
    elseif msgType == MSG.LEAVE then self:HandleLeave(sender, parts)
    elseif msgType == MSG.DEAL_START then self:HandleDealStart(sender, parts)
    elseif msgType == MSG.DEAL_CARD then self:HandleDealCard(sender, parts)
    elseif msgType == MSG.BETTING_START then self:HandleBettingStart(sender, parts)
    elseif msgType == MSG.ACTION then self:HandleAction(sender, parts)
    elseif msgType == MSG.BETTING_END then self:HandleBettingEnd(sender, parts)
    elseif msgType == MSG.SHOWDOWN then self:HandleShowdown(sender, parts)
    elseif msgType == MSG.SETTLEMENT then self:HandleSettlement(sender, parts)
    elseif msgType == MSG.SYNC_STATE then self:HandleSyncState(sender, parts)
    elseif msgType == MSG.VERSION_REJECT then self:HandleVersionReject(sender, parts)
    elseif msgType == "FULLSTATE" then
        -- Full state sync from StateSync system - route to StateSync handler
        local serializedData = table.concat(parts, "|", 2)  -- Rejoin all parts after FULLSTATE
        if BJ.StateSync then
            BJ.StateSync:HandleFullState("poker", serializedData)
        end
    elseif msgType == "REQSYNC" then
        -- Sync request from StateSync system
        if PM.isHost and BJ.StateSync then
            local requesterName = sender:match("^([^-]+)") or sender
            BJ.StateSync:HandleSyncRequest("poker", requesterName)
        end
    end
end

function PM:OnRosterUpdate()
    local myName = UnitName("player")
    
    -- If we left the party entirely, reset our local game state
    if not IsInGroup() and not IsInRaid() then
        local PS = BJ.PokerState
        if PS and PS.phase ~= PS.PHASE.IDLE then
            BJ:Debug("Poker: Left party, resetting local game state")
            PS:Reset()
            PM.isHost = false
            PM.currentHost = nil
            PM.tableOpen = false
            PM.hostDisconnected = false
            PM.originalHost = nil
            PM.temporaryHost = nil
            if BJ.UI and BJ.UI.Poker then
                BJ.UI.Poker:UpdateDisplay()
            end
        end
        return
    end
    
    -- Check if WE are the original host who just reconnected
    if PM.originalHost == myName and PM.hostDisconnected then
        BJ:Print("|cff00ff00You have reconnected as host. Restoring game...|r")
        PM:RestoreOriginalHost()
        return
    end
    
    if not PM.currentHost then return end
    if PM.isHost and not PM.hostDisconnected then return end
    
    local PS = BJ.PokerState
    if PS.phase == PS.PHASE.IDLE or PS.phase == PS.PHASE.SETTLEMENT then return end
    
    local hostInGroup = UnitInParty(PM.currentHost) or UnitInRaid(PM.currentHost)
    local hostOnline = false
    
    if hostInGroup then
        local numMembers = GetNumGroupMembers()
        for i = 1, numMembers do
            local unit = IsInRaid() and ("raid" .. i) or ("party" .. i)
            local name = UnitName(unit)
            if name == PM.currentHost then
                hostOnline = UnitIsConnected(unit)
                break
            end
        end
    end
    
    -- If host left the group entirely
    if not hostInGroup then
        BJ:Print("|cffff44445 Card Stud host (" .. PM.currentHost .. ") left the group.|r")
        PM:VoidGame("Host left the group")
        return
    end
    
    -- If host is in group but offline - start recovery
    if not hostOnline and not PM.hostDisconnected then
        PM.hostDisconnected = true
        BJ:Print("|cffff88005 Card Stud host (" .. PM.currentHost .. ") disconnected!|r")
        PM:StartHostRecovery()
    elseif hostOnline and PM.hostDisconnected then
        -- Host came back!
        PM:RestoreOriginalHost()
    end
end

--[[
    HOST RECOVERY
    When the original host disconnects, game pauses with a 2-minute grace period.
    If host returns, they resume control. If not, game is voided.
]]

PM.hostDisconnected = false
PM.originalHost = nil
PM.temporaryHost = nil
PM.recoveryTimer = nil
PM.recoveryStartTime = nil
PM.RECOVERY_TIMEOUT = 120  -- 2 minutes

-- Determine temporary host
function PM:DetermineTemporaryHost()
    local PS = BJ.PokerState
    local myName = UnitName("player")
    
    for _, playerName in ipairs(PS.playerOrder or {}) do
        if playerName ~= PM.currentHost then
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
function PM:StartHostRecovery()
    local myName = UnitName("player")
    
    PM.originalHost = PM.currentHost
    PM.recoveryStartTime = time()
    PM.hostDisconnected = true
    
    local tempHost = PM:DetermineTemporaryHost()
    
    if tempHost == myName then
        PM.temporaryHost = myName
        PM.isHost = true  -- For reset button access only
        PM:Send(MSG.SYNC_STATE, "HOST_RECOVERY_START", myName, PM.originalHost)
        
        BJ:Print("|cffff8800You are temporary host. Game PAUSED for 2 minutes.|r")
        PM:StartRecoveryCountdown()
    else
        PM.temporaryHost = tempHost
        BJ:Print("|cffff8800Waiting for " .. PM.originalHost .. " to return (2 min).|r")
        -- Start local countdown for UI updates
        PM:StartLocalRecoveryCountdown()
    end
    
    -- Show recovery popup for all players
    PM:ShowRecoveryPopup(PM.originalHost, tempHost == myName)
    
    if BJ.UI and BJ.UI.Poker and BJ.UI.Poker.OnHostRecoveryStart then
        BJ.UI.Poker:OnHostRecoveryStart(PM.originalHost, PM.temporaryHost)
    end
end

-- Start countdown
function PM:StartRecoveryCountdown()
    if PM.recoveryTimer then
        PM.recoveryTimer:Cancel()
    end
    
    PM.recoveryTimer = C_Timer.NewTicker(1, function()
        local elapsed = time() - PM.recoveryStartTime
        local remaining = PM.RECOVERY_TIMEOUT - elapsed
        
        -- Update popup timer
        PM:UpdateRecoveryPopupTimer(remaining)
        
        if BJ.UI and BJ.UI.Poker and BJ.UI.Poker.UpdateRecoveryTimer then
            BJ.UI.Poker:UpdateRecoveryTimer(remaining)
        end
        
        if remaining > 0 and remaining % 30 == 0 then
            PM:Send(MSG.SYNC_STATE, "HOST_RECOVERY_TICK", remaining)
        end
        
        if remaining <= 0 then
            PM:VoidGame("Host did not return in time")
        end
    end, PM.RECOVERY_TIMEOUT + 1)
end

-- Start local countdown for non-temp-host clients (UI updates only)
function PM:StartLocalRecoveryCountdown()
    if PM.localRecoveryTimer then
        PM.localRecoveryTimer:Cancel()
    end
    
    PM.localRecoveryTimer = C_Timer.NewTicker(1, function()
        local elapsed = time() - PM.recoveryStartTime
        local remaining = PM.RECOVERY_TIMEOUT - elapsed
        
        -- Update popup timer
        PM:UpdateRecoveryPopupTimer(remaining)
        
        if BJ.UI and BJ.UI.Poker and BJ.UI.Poker.UpdateRecoveryTimer then
            BJ.UI.Poker:UpdateRecoveryTimer(remaining)
        end
        
        if remaining <= 0 then
            if PM.localRecoveryTimer then
                PM.localRecoveryTimer:Cancel()
                PM.localRecoveryTimer = nil
            end
        end
    end, PM.RECOVERY_TIMEOUT + 1)
end

-- Restore original host after they reconnect
function PM:RestoreOriginalHost()
    -- Prevent double-restore
    if PM.restoringHost then return end
    PM.restoringHost = true
    
    local myName = UnitName("player")
    local wasOriginalHost = (PM.originalHost == myName)
    local originalHostName = PM.originalHost
    local wasTempHost = (PM.temporaryHost == myName)
    
    BJ:Print("|cff00ff00" .. originalHostName .. " has returned! Resuming game.|r")
    
    -- Cancel recovery timer
    if PM.recoveryTimer then
        PM.recoveryTimer:Cancel()
        PM.recoveryTimer = nil
    end
    
    -- Cancel local recovery timer
    if PM.localRecoveryTimer then
        PM.localRecoveryTimer:Cancel()
        PM.localRecoveryTimer = nil
    end
    
    -- Close recovery popup
    PM:CloseRecoveryPopup()
    
    -- If we were temporary host, broadcast restore and send sync to returning host
    if wasTempHost and not wasOriginalHost then
        -- Broadcast that original host is back
        PM:Send(MSG.SYNC_STATE, "HOST_RESTORED", originalHostName)
        
        -- Send full state sync to the returning host after short delay
        C_Timer.After(0.5, function()
            if BJ.StateSync then
                BJ.StateSync:BroadcastFullState("poker")
            end
            -- Now clear the restore flag
            PM.restoringHost = false
        end)
        
        -- Relinquish temp host status
        PM.isHost = false
    else
        PM.restoringHost = false
    end
    
    -- If we ARE the original host (we just reconnected), reclaim
    if wasOriginalHost then
        BJ:Print("|cff00ff00You have reconnected. Reclaiming host...|r")
        PM.isHost = true
        PM.currentHost = myName
        -- Don't broadcast sync here - temp host will send it to us
        -- Just update our UI after a delay to receive the sync
        C_Timer.After(1.5, function()
            if BJ.UI and BJ.UI.Poker then
                BJ.UI.Poker:UpdateDisplay()
            end
        end)
    end
    
    -- Reset recovery state
    PM.hostDisconnected = false
    PM.temporaryHost = nil
    PM.originalHost = nil
    PM.recoveryStartTime = nil
    
    -- Update UI
    if BJ.UI and BJ.UI.Poker and BJ.UI.Poker.OnHostRestored then
        BJ.UI.Poker:OnHostRestored()
    end
end

-- Show recovery popup
function PM:ShowRecoveryPopup(hostName, isTempHost)
    -- Close existing popup if any
    if PM.recoveryPopup then
        PM.recoveryPopup:Hide()
    end
    
    -- Create popup frame
    local popup = CreateFrame("Frame", "CasinoPokerRecoveryPopup", UIParent, "BackdropTemplate")
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
            StaticPopupDialogs["CASINO_POKER_VOID_CONFIRM"] = {
                text = "Void the current game?\n\nNo gold changes hands.",
                button1 = "Void",
                button2 = "Cancel",
                OnAccept = function()
                    PM:VoidGame("Voided by temporary host")
                end,
                timeout = 0,
                whileDead = true,
                hideOnEscape = true,
            }
            StaticPopup_Show("CASINO_POKER_VOID_CONFIRM")
        end)
        popup.voidBtn = voidBtn
    end
    
    popup:Show()
    PM.recoveryPopup = popup
end

-- Update recovery popup timer
function PM:UpdateRecoveryPopupTimer(remaining)
    if PM.recoveryPopup and PM.recoveryPopup.timerText then
        local mins = math.floor(remaining / 60)
        local secs = remaining % 60
        local color = remaining <= 30 and "ffff4444" or "ffffd700"
        PM.recoveryPopup.timerText:SetText("|c" .. color .. string.format("%d:%02d", mins, secs) .. "|r")
    end
end

-- Close recovery popup
function PM:CloseRecoveryPopup()
    if PM.recoveryPopup then
        PM.recoveryPopup:Hide()
        PM.recoveryPopup = nil
    end
end

-- Void the game
function PM:VoidGame(reason)
    BJ:Print("|cffff44445 Card Stud VOIDED: " .. reason .. "|r")
    
    if PM.recoveryTimer then
        PM.recoveryTimer:Cancel()
        PM.recoveryTimer = nil
    end
    
    if PM.localRecoveryTimer then
        PM.localRecoveryTimer:Cancel()
        PM.localRecoveryTimer = nil
    end
    
    -- Close recovery popup
    PM:CloseRecoveryPopup()
    
    if PM.temporaryHost == UnitName("player") then
        PM:Send(MSG.SYNC_STATE, "GAME_VOIDED", reason)
    end
    
    PM.hostDisconnected = false
    PM.temporaryHost = nil
    PM.originalHost = nil
    PM.recoveryStartTime = nil
    PM:ResetState()
    
    if BJ.UI and BJ.UI.Poker and BJ.UI.Poker.OnGameVoided then
        BJ.UI.Poker:OnGameVoided(reason)
    end
end

-- Check if in recovery mode
function PM:IsInRecoveryMode()
    return PM.hostDisconnected and PM.originalHost ~= nil
end

function PM:ResetState()
    PM.isHost = false
    PM.currentHost = nil
    PM.tableOpen = false
    BJ.PokerState:Reset()
end

-- Reset the current game (host only)
function PM:ResetGame()
    if not PM.isHost then
        BJ:Print("Only the host can reset the game.")
        return false
    end
    
    PM:CancelCountdown()
    BJ.PokerState:Reset()
    PM.tableOpen = false
    PM.isHost = false
    PM.currentHost = nil
    
    PM:Send(MSG.TABLE_CLOSE)
    BJ:Print("Poker game reset.")
    
    if BJ.UI and BJ.UI.Poker then
        BJ.UI.Poker:OnTableClosed()
    end
    
    return true
end

--[[
    HOST ACTIONS
]]

function PM:HostTable(settings)
    local inTestMode = BJ.TestMode and BJ.TestMode.enabled
    if not IsInGroup() and not inTestMode then
        BJ:Print("Must be in a party to host poker.")
        return false
    end
    
    BJ.PokerState:Reset()
    PM.isHost = true
    PM.currentHost = UnitName("player")
    PM.tableOpen = true
    
    -- Start leaderboard session
    if BJ.Leaderboard then
        BJ.Leaderboard:StartSession("poker", UnitName("player"))
    end
    
    -- Store maxPlayers setting
    BJ.PokerState.maxPlayers = settings.maxPlayers or 10
    
    local seed = time() + math.random(1, 100000)
    BJ.PokerState:StartRound(PM.currentHost, settings.ante, settings.maxRaise, seed)
    
    -- Host auto-antes
    local hostName = UnitName("player")
    BJ.PokerState:PlayerAnte(hostName, settings.ante)
    BJ:Print("You anted " .. settings.ante .. "g")
    
    -- Include pot and countdown in table open so clients know host has already anted
    -- Also include version for compatibility check
    local cdEnabled = settings.countdownEnabled and 1 or 0
    local cdSeconds = settings.countdownSeconds or 0
    PM:Send(MSG.TABLE_OPEN, settings.ante, settings.maxRaise, seed, BJ.PokerState.pot, settings.maxPlayers or 10, cdEnabled, cdSeconds, BJ.version)
    
    local maxPText = ""
    if settings.maxPlayers and settings.maxPlayers < 10 then
        maxPText = " | Max " .. settings.maxPlayers .. " players"
    end
    local gameLink = BJ:CreateGameLink("poker", "5 Card Stud")
    BJ:Print(gameLink .. " table opened! Ante: " .. settings.ante .. "g | Max Raise: " .. settings.maxRaise .. "g" .. maxPText)
    
    if BJ.UI and BJ.UI.Poker then
        BJ.UI.Poker:OnTableOpened(PM.currentHost, settings)
    end
    
    -- Start countdown if enabled
    if settings.countdownEnabled and settings.countdownSeconds > 0 then
        PM:StartCountdown(settings.countdownSeconds)
        BJ:Print("Betting closes in " .. settings.countdownSeconds .. " seconds!")
    end
    
    return true
end

function PM:StartCountdown(seconds)
    PM.countdownActive = true
    PM.countdownRemaining = seconds
    if PM.countdownTimer then PM.countdownTimer:Cancel() end
    
    PM.countdownTimer = C_Timer.NewTicker(1, function()
        PM.countdownRemaining = PM.countdownRemaining - 1
        PM:Send(MSG.COUNTDOWN, PM.countdownRemaining)
        if BJ.UI and BJ.UI.Poker then BJ.UI.Poker:OnCountdownTick(PM.countdownRemaining) end
        
        if PM.countdownRemaining <= 0 then
            PM.countdownActive = false
            PM.countdownTimer:Cancel()
            PM.countdownTimer = nil
            if #BJ.PokerState.playerOrder >= 2 then 
                PM:StartDeal() 
            else
                -- Not enough players - close the table
                BJ:Print("|cffff4444Countdown ended with less than 2 players. Table closed.|r")
                PM:LeaveTable()
            end
        end
    end, seconds)
    BJ:Print("Poker deal in " .. seconds .. "s!")
end

function PM:CancelCountdown()
    if PM.countdownTimer then PM.countdownTimer:Cancel() PM.countdownTimer = nil end
    PM.countdownActive = false
    PM.countdownRemaining = 0
end

--[[
    TURN TIMER SYSTEM (Local Only)
    Each client tracks their own turn timer. When it's your turn, timer starts.
    At 10 seconds, warning appears. At 0 seconds, auto-check or auto-fold is executed.
]]

-- Start turn timer (only if it's my turn)
function PM:StartTurnTimer()
    -- Cancel any existing timer
    PM:CancelTurnTimer()
    
    local PS = BJ.PokerState
    local myName = UnitName("player")
    
    -- Only during betting phase
    if PS.phase ~= PS.PHASE.BETTING then return end
    
    -- Check if it's my turn
    local currentPlayerName = PS.playerOrder[PS.currentPlayerIndex]
    if currentPlayerName ~= myName then return end
    
    -- Check if I'm still active (not folded)
    local myPlayer = PS.players[myName]
    if not myPlayer or myPlayer.folded then return end
    
    PM.turnTimerRemaining = PM.TURN_TIME_LIMIT
    PM.turnTimerActive = true
    
    -- Start ticker
    PM.turnTimer = C_Timer.NewTicker(1, function()
        PM.turnTimerRemaining = PM.turnTimerRemaining - 1
        
        -- Show warning at 10 seconds
        if PM.turnTimerRemaining == PM.TURN_WARNING_TIME then
            BJ:Print("|cffff4444WARNING: " .. PM.TURN_WARNING_TIME .. " seconds to make a move or you will auto-check/fold!|r")
            -- Play airhorn warning sound
            PlaySoundFile("Interface\\AddOns\\Chairfaces Casino\\Sounds\\AirHorn.ogg", "Master")
        end
        
        -- Update UI (show countdown at <= 10 seconds)
        if BJ.UI and BJ.UI.Poker and BJ.UI.Poker.turnTimerFrame then
            if PM.turnTimerRemaining <= PM.TURN_WARNING_TIME and PM.turnTimerRemaining > 0 then
                BJ.UI.Poker.turnTimerFrame.text:SetText(PM.turnTimerRemaining)
                BJ.UI.Poker.turnTimerFrame:Show()
            else
                BJ.UI.Poker.turnTimerFrame:Hide()
            end
        end
        
        -- Timeout - auto-check or auto-fold
        if PM.turnTimerRemaining <= 0 then
            PM:OnTurnTimeout()
        end
    end)
end

-- Cancel turn timer
function PM:CancelTurnTimer()
    if PM.turnTimer then
        PM.turnTimer:Cancel()
        PM.turnTimer = nil
    end
    PM.turnTimerActive = false
    PM.turnTimerRemaining = 0
    
    -- Hide timer UI
    if BJ.UI and BJ.UI.Poker and BJ.UI.Poker.turnTimerFrame then
        BJ.UI.Poker.turnTimerFrame:Hide()
    end
end

-- Handle turn timeout - auto-check or auto-fold
function PM:OnTurnTimeout()
    PM:CancelTurnTimer()
    
    local PS = BJ.PokerState
    local myName = UnitName("player")
    
    -- Verify it's still my turn
    local currentPlayerName = PS.playerOrder[PS.currentPlayerIndex]
    if currentPlayerName ~= myName then return end
    
    local myPlayer = PS.players[myName]
    if not myPlayer or myPlayer.folded then return end
    
    -- Check if we need to call (someone raised)
    local amountToCall = PS.currentBet - (myPlayer.currentBet or 0)
    
    if amountToCall > 0 then
        -- Must call or fold - auto-fold
        BJ:Print("|cffff8800Your turn timed out - auto-folding.|r")
        PM:PlayerAction("fold")
    else
        -- Can check - auto-check (call for 0)
        BJ:Print("|cffff8800Your turn timed out - auto-checking.|r")
        PM:PlayerAction("check")
    end
end

function PM:StartDeal()
    if not PM.isHost then return false end
    local PS = BJ.PokerState
    
    if PS.phase ~= PS.PHASE.WAITING_FOR_PLAYERS then return false end
    if #PS.playerOrder < 2 then
        BJ:Print("Need at least 2 players.")
        return false
    end
    
    PM:CancelCountdown()
    PS:StartDeal()
    
    -- Broadcast DEAL_START with full player list so clients know who's playing
    -- Format: playerName1,ante1;playerName2,ante2;...
    local playerData = {}
    for _, pname in ipairs(PS.playerOrder) do
        local player = PS.players[pname]
        local ante = player and player.totalBet or PS.ante
        table.insert(playerData, pname .. "," .. ante)
    end
    PM:Send(MSG.DEAL_START, table.concat(playerData, ";"))
    
    if BJ.UI and BJ.UI.Poker then BJ.UI.Poker:OnDealStart() end
    
    -- Deal cards with animation timing
    self:DealAllCards()
    return true
end

-- Deal all cards in proper 5-card stud order
function PM:DealAllCards()
    local PS = BJ.PokerState
    local dealDelay = 0.15  -- Fast queue, animation will pace actual display
    local cardIndex = 0
    
    -- Deal 5 rounds: hole (down), up, up, up, up
    local rounds = {
        { faceUp = false },  -- Round 1: hole card (down)
        { faceUp = true },   -- Round 2: first up card
        { faceUp = true },   -- Round 3: second up card
        { faceUp = true },   -- Round 4: third up card
        { faceUp = true },   -- Round 5: river (fourth up card)
    }
    
    local function dealNextCard()
        cardIndex = cardIndex + 1
        local roundNum = math.ceil(cardIndex / #PS.playerOrder)
        local playerIdx = ((cardIndex - 1) % #PS.playerOrder) + 1
        
        if roundNum > 5 then
            -- All cards queued, wait for animations then start betting
            -- The animation queue will call back when done
            return
        end
        
        local playerName = PS.playerOrder[playerIdx]
        local round = rounds[roundNum]
        local card = PS:DealCardToPlayer(playerName, round.faceUp)
        
        if card then
            PM:Send(MSG.DEAL_CARD, playerName, card.rank, card.suit, round.faceUp and "1" or "0", roundNum, PS:GetRemainingCards())
            
            -- Queue animation - pass callback only on last card of round 2
            local isLastCardRound2 = (roundNum == 2 and playerIdx == #PS.playerOrder)
            local callback = nil
            if isLastCardRound2 then
                callback = function()
                    -- Start betting after round 2 animations complete
                    C_Timer.After(0.3, function()
                        PM:StartBettingRound(1)
                    end)
                end
            end
            
            if BJ.UI and BJ.UI.Poker then
                BJ.UI.Poker:OnCardDealt(playerName, card, cardIndex, round.faceUp, callback)
            end
        end
        
        -- After dealing round 2, stop (betting will start via callback)
        if roundNum == 2 and playerIdx == #PS.playerOrder then
            return
        end
        
        C_Timer.After(dealDelay, dealNextCard)
    end
    
    dealNextCard()
end

-- Continue dealing after betting round
function PM:ContinueDealing(street)
    local PS = BJ.PokerState
    local dealDelay = 0.15
    local cardIndex = 0
    local totalPlayers = #PS.playerOrder
    local activeCount = 0
    
    -- Count active (non-folded) players
    for _, pname in ipairs(PS.playerOrder) do
        if PS.players[pname] and not PS.players[pname].folded then
            activeCount = activeCount + 1
        end
    end
    
    BJ:Debug("[AI] ContinueDealing street " .. street .. ", activeCount=" .. activeCount)
    
    local cardsDealt = 0
    local bettingStarted = false
    
    local function startBettingIfNeeded()
        if not bettingStarted then
            bettingStarted = true
            BJ:Debug("[AI] Starting betting round " .. street)
            C_Timer.After(0.5, function()
                PM:StartBettingRound(street)
            end)
        end
    end
    
    local function dealStreetCard()
        cardIndex = cardIndex + 1
        if cardIndex > totalPlayers then
            -- All cards queued for this street, ensure betting starts
            BJ:Debug("[AI] All " .. cardsDealt .. " cards dealt for street " .. street)
            startBettingIfNeeded()
            return
        end
        
        local playerName = PS.playerOrder[cardIndex]
        local player = PS.players[playerName]
        
        if player and not player.folded then
            local card = PS:DealCardToPlayer(playerName, true)
            if card then
                cardsDealt = cardsDealt + 1
                PM:Send(MSG.DEAL_CARD, playerName, card.rank, card.suit, "1", street + 1, PS:GetRemainingCards())
                
                -- Callback on last active player's card
                local isLast = (cardsDealt == activeCount)
                local callback = nil
                if isLast then
                    callback = function()
                        startBettingIfNeeded()
                    end
                end
                
                if BJ.UI and BJ.UI.Poker then
                    BJ.UI.Poker:OnCardDealt(playerName, card, #player.hand, true, callback)
                else
                    -- No UI, trigger callback directly
                    if callback then callback() end
                end
            end
        end
        
        C_Timer.After(dealDelay, dealStreetCard)
    end
    
    dealStreetCard()
end

function PM:StartBettingRound(street)
    local PS = BJ.PokerState
    local starter = PS:StartBettingRound(street)
    
    -- Send street and currentPlayerIndex so clients sync to same player
    PM:Send(MSG.BETTING_START, street, PS.currentPlayerIndex)
    
    if BJ.UI and BJ.UI.Poker then
        BJ.UI.Poker:OnBettingStart(street, starter)
    end
    
    -- Check if it's a test player's turn
    if BJ.TestMode and BJ.TestMode.enabled then
        self:CheckTestPlayerTurn()
    end
end

function PM:CheckTestPlayerTurn()
    local PS = BJ.PokerState
    
    BJ:Debug("[AI] CheckTestPlayerTurn called, phase=" .. tostring(PS.phase))
    
    if PS.phase ~= PS.PHASE.BETTING then
        BJ:Debug("[AI] Not in betting phase, exiting")
        return
    end
    
    local currentPlayer = PS:GetCurrentPlayer()
    BJ:Debug("[AI] Current player: " .. tostring(currentPlayer) .. ", index: " .. tostring(PS.currentPlayerIndex))
    
    if not currentPlayer then 
        BJ:Debug("[AI Error] No current player in betting phase!")
        return 
    end
    
    local myName = UnitName("player")
    if currentPlayer == myName then 
        BJ:Debug("[AI] It's the real player's turn, skipping AI")
        return 
    end
    
    -- Check if auto-play is enabled in UI
    local autoPlayEnabled = true  -- Default to true
    if BJ.UI and BJ.UI.Poker then
        autoPlayEnabled = BJ.UI.Poker.autoPlayEnabled
    end
    
    if not autoPlayEnabled then 
        BJ:Debug("[AI] Auto-play disabled")
        return 
    end
    
    -- Check if it's in our test player list
    local isTestPlayer = false
    local testPlayers = BJ.UI and BJ.UI.Poker and BJ.UI.Poker.testPlayers or {}
    
    BJ:Debug("[AI] Test players: " .. #testPlayers)
    for i, name in ipairs(testPlayers) do
        BJ:Debug("[AI]   [" .. i .. "] = " .. name)
        if name == currentPlayer then
            isTestPlayer = true
        end
    end
    
    if not isTestPlayer then
        BJ:Debug("[AI] " .. currentPlayer .. " not in test player list")
        return
    end
    
    -- Test player - auto-play after delay
    BJ:Debug("[AI] " .. currentPlayer .. " is thinking...")
    
    local playerToAct = currentPlayer  -- Capture for closure
    C_Timer.After(1.5, function()
        BJ:Debug("[AI] Timer fired for " .. playerToAct)
        BJ:Debug("[AI] Current phase: " .. tostring(PS.phase) .. ", Current player now: " .. tostring(PS:GetCurrentPlayer()))
        
        -- Re-verify conditions
        if PS.phase ~= PS.PHASE.BETTING then
            BJ:Debug("[AI] Phase changed to " .. tostring(PS.phase) .. ", cancelling")
            return
        end
        
        local stillCurrentPlayer = PS:GetCurrentPlayer()
        if stillCurrentPlayer ~= playerToAct then
            BJ:Debug("[AI] Player changed from " .. playerToAct .. " to " .. tostring(stillCurrentPlayer))
            return
        end
        
        BJ:Debug("[AI] Executing action for " .. playerToAct)
        PM:AutoPlayTestPlayer(playerToAct)
    end)
end

function PM:AutoPlayTestPlayer(playerName)
    local PS = BJ.PokerState
    local player = PS.players[playerName]
    
    BJ:Debug("[AI] AutoPlayTestPlayer for " .. playerName)
    
    if not player then
        BJ:Debug("[AI Error] Player " .. playerName .. " not found in PS.players!")
        return
    end
    
    if player.folded then
        BJ:Debug("[AI Error] Player " .. playerName .. " already folded!")
        return
    end
    
    -- Double check it's their turn
    local canAct = PS:CanPlayerAct(playerName)
    BJ:Debug("[AI] CanPlayerAct(" .. playerName .. ") = " .. tostring(canAct))
    
    if not canAct then
        BJ:Debug("[AI Error] " .. playerName .. " cannot act right now!")
        return
    end
    
    local actions = PS:GetAvailableActions(playerName)
    BJ:Debug("[AI] Available actions: " .. table.concat(actions, ", "))
    
    if not actions or #actions == 0 then
        BJ:Debug("[AI Error] No available actions for " .. playerName)
        return
    end
    
    local toCall = PS.currentBet - (player.currentBet or 0)
    BJ:Debug("[AI] currentBet=" .. PS.currentBet .. ", player.currentBet=" .. (player.currentBet or 0) .. ", toCall=" .. toCall)
    
    -- Evaluate hand strength
    local handStrength, handDesc = self:EvaluateHandStrength(playerName)
    BJ:Debug("[AI] Hand strength: " .. handStrength .. " (" .. handDesc .. ")")
    
    -- Simple decision for now - to debug the flow
    local action = "check"
    local raiseAmount = 10
    local reason = "default"
    
    -- If we need to call, either call or fold
    if toCall > 0 then
        -- 70% call, 30% fold
        if math.random(100) <= 70 then
            action = "call"
            reason = "calling"
        else
            action = "fold"
            reason = "folding"
        end
    else
        -- Can check for free - 60% check, 40% raise
        if math.random(100) <= 60 then
            action = "check"
            reason = "checking"
        else
            action = "raise"
            raiseAmount = math.min(PS.maxRaise - PS.currentBet, math.random(10, 25))
            reason = "raising"
        end
    end
    
    -- Validate action is available
    local actionValid = false
    for _, a in ipairs(actions) do
        if a == action then 
            actionValid = true 
            break 
        end
    end
    
    BJ:Debug("[AI] Chosen action: " .. action .. ", valid: " .. tostring(actionValid))
    
    if not actionValid then
        -- Fallback
        action = actions[1] or "fold"
        reason = "fallback to " .. action
        BJ:Debug("[AI] Falling back to: " .. action)
    end
    
    -- Announce decision
    local actionStr = action:upper()
    if action == "raise" then
        actionStr = actionStr .. " " .. raiseAmount .. "g"
    elseif action == "call" and toCall > 0 then
        actionStr = actionStr .. " " .. toCall .. "g"
    end
    
    BJ:Print("|cffff00ff[AI]|r " .. playerName .. ": " .. actionStr .. " (" .. handDesc .. ", " .. reason .. ")")
    
    -- Execute the action
    local success, err
    BJ:Debug("[AI] Calling PS:Player" .. action:sub(1,1):upper() .. action:sub(2) .. "...")
    
    if action == "fold" then
        success, err = PS:PlayerFold(playerName)
    elseif action == "check" then
        success, err = PS:PlayerCheck(playerName)
    elseif action == "call" then
        success, err = PS:PlayerCall(playerName)
    elseif action == "raise" then
        success, err = PS:PlayerRaise(playerName, raiseAmount)
    end
    
    BJ:Debug("[AI] Action result: success=" .. tostring(success) .. ", result=" .. tostring(err))
    
    if not success then
        BJ:Debug("[AI Error] Action " .. action .. " failed: " .. tostring(err))
        return
    end
    
    BJ:Debug("[AI] Action succeeded! Phase now: " .. tostring(PS.phase) .. ", result: " .. tostring(err))
    
    -- Broadcast and continue (include phase for client sync)
    PM:Send(MSG.SYNC_STATE, "ACTION", playerName, action, raiseAmount or 0, PS.pot, PS.currentBet, PS.currentPlayerIndex, PS.phase)
    
    if BJ.UI and BJ.UI.Poker then
        BJ.UI.Poker:OnPlayerAction(playerName, action, raiseAmount)
    end
    
    -- Check what to do next - use result value AND phase
    local result = err  -- The second return value is actually the result
    BJ:Debug("[AI] Checking next step: result=" .. tostring(result) .. ", phase=" .. tostring(PS.phase))
    
    if result == "hand_over" then
        BJ:Debug("[AI] -> Hand over (early win)")
        PM:SendSettlement()
    elseif result == "showdown" then
        BJ:Debug("[AI] -> Showdown triggered")
        PM:DoShowdown()
    elseif result == "deal_next" or PS.phase == PS.PHASE.DEALING then
        BJ:Debug("[AI] -> Dealing next street")
        PM:ContinueDealing(PS.currentStreet + 1)
    elseif PS.phase == PS.PHASE.SETTLEMENT then
        BJ:Debug("[AI] -> Settlement (phase check)")
        PM:SendSettlement()
    elseif PS.phase == PS.PHASE.BETTING then
        BJ:Debug("[AI] -> Still betting, checking next player")
        C_Timer.After(0.5, function()
            PM:CheckTestPlayerTurn()
        end)
    end
end

-- Evaluate hand strength for AI (0-5 scale) with description
function PM:EvaluateHandStrength(playerName)
    local PS = BJ.PokerState
    local player = PS.players[playerName]
    
    if not player then
        BJ:Debug("[AI Error] EvaluateHandStrength: player not found")
        return 1, "no player"
    end
    
    if not player.hand then
        BJ:Debug("[AI Error] EvaluateHandStrength: player.hand is nil")
        return 1, "no hand"
    end
    
    local allCards = player.hand
    if #allCards == 0 then 
        BJ:Debug("[AI Error] EvaluateHandStrength: hand is empty")
        return 1, "no cards" 
    end
    
    BJ:Debug("[AI] Evaluating " .. #allCards .. " cards for " .. playerName)
    
    -- Debug: print the cards
    for i, card in ipairs(allCards) do
        local rank = card.rank or "nil"
        local suit = card.suit or "nil"
        local faceUp = card.faceUp and "up" or "down"
        BJ:Debug("[AI]   Card " .. i .. ": " .. rank .. " of " .. suit .. " (" .. faceUp .. ")")
    end
    
    -- Use pcall to catch any errors in EvaluateHand
    local success, eval = pcall(function()
        return PS:EvaluateHand(allCards)
    end)
    
    if not success then
        BJ:Debug("[AI Error] EvaluateHand crashed: " .. tostring(eval))
        return 1, "eval error"
    end
    
    if not eval then 
        BJ:Debug("[AI Error] EvaluateHand returned nil")
        return 1, "eval failed" 
    end
    
    BJ:Debug("[AI] EvaluateHand returned rank: " .. tostring(eval.rank))
    
    local strength = 1
    local desc = "high card"
    
    -- Hand rank bonuses
    if eval.rank >= PS.HAND_RANK.ROYAL_FLUSH then
        strength, desc = 5, "ROYAL FLUSH!"
    elseif eval.rank >= PS.HAND_RANK.STRAIGHT_FLUSH then
        strength, desc = 5, "straight flush"
    elseif eval.rank >= PS.HAND_RANK.FOUR_OF_A_KIND then
        strength, desc = 5, "four of a kind"
    elseif eval.rank >= PS.HAND_RANK.FULL_HOUSE then
        strength, desc = 4.5, "full house"
    elseif eval.rank >= PS.HAND_RANK.FLUSH then
        strength, desc = 4, "flush"
    elseif eval.rank >= PS.HAND_RANK.STRAIGHT then
        strength, desc = 4, "straight"
    elseif eval.rank >= PS.HAND_RANK.THREE_OF_A_KIND then
        strength, desc = 3.5, "three of a kind"
    elseif eval.rank >= PS.HAND_RANK.TWO_PAIR then
        strength, desc = 3, "two pair"
    elseif eval.rank >= PS.HAND_RANK.ONE_PAIR then
        strength, desc = 2.5, "pair"
    else
        local highCard = 0
        for _, card in ipairs(allCards) do
            local val = PS.RANK_VALUES[card.rank] or 0
            if val > highCard then highCard = val end
        end
        if highCard >= 14 then
            strength, desc = 2, "ace high"
        elseif highCard >= 13 then
            strength, desc = 1.5, "king high"
        else
            strength, desc = 1, "low cards"
        end
    end
    
    return strength, desc
end

function PM:PlayerAction(action, amount)
    -- Block actions during recovery
    if PM:IsInRecoveryMode() then
        BJ:Print("|cffff8800Game is paused - waiting for host to return.|r")
        return false
    end
    
    local myName = UnitName("player")
    
    if PM.isHost then
        self:ProcessAction(myName, action, amount)
    else
        PM:Send(MSG.ACTION, action, amount or 0)
    end
end

function PM:ProcessAction(playerName, action, amount)
    local PS = BJ.PokerState
    local success, result
    
    if action == "fold" then
        success, result = PS:PlayerFold(playerName)
    elseif action == "check" then
        success, result = PS:PlayerCheck(playerName)
    elseif action == "call" then
        success, result = PS:PlayerCall(playerName)
    elseif action == "raise" then
        success, result = PS:PlayerRaise(playerName, amount or 10)
    end
    
    BJ:Debug("ProcessAction: " .. playerName .. " " .. action .. " -> success=" .. tostring(success) .. ", result=" .. tostring(result))
    
    if success then
        -- Debug: Show what we're sending
        local nextPlayer = PS.playerOrder[PS.currentPlayerIndex] or "none"
        BJ:Debug("ProcessAction: Sending sync - nextPlayerIdx=" .. tostring(PS.currentPlayerIndex) .. 
            " (" .. nextPlayer .. "), phase=" .. tostring(PS.phase))
        
        PM:Send(MSG.SYNC_STATE, "ACTION", playerName, action, amount or 0, PS.pot, PS.currentBet, PS.currentPlayerIndex, PS.phase)
        
        if BJ.UI and BJ.UI.Poker then
            BJ.UI.Poker:OnPlayerAction(playerName, action, amount)
        end
        
        -- Check result from action to determine next step
        BJ:Debug("ProcessAction: Checking next step, result=" .. tostring(result) .. ", phase=" .. tostring(PS.phase))
        
        if result == "hand_over" then
            BJ:Debug("ProcessAction: -> Hand over (early win)")
            PM:SendSettlement()
        elseif result == "showdown" then
            BJ:Debug("ProcessAction: -> Showdown triggered")
            PM:DoShowdown()
        elseif result == "deal_next" or PS.phase == PS.PHASE.DEALING then
            BJ:Debug("ProcessAction: -> Dealing next street")
            PM:ContinueDealing(PS.currentStreet + 1)
        elseif PS.phase == PS.PHASE.BETTING then
            BJ:Debug("ProcessAction: -> Still betting, checking next player")
            -- Refresh host's UI to show new current player
            if BJ.UI and BJ.UI.Poker then
                BJ.UI.Poker:UpdateDisplay()
            end
            -- Check for test player turn
            if BJ.TestMode and BJ.TestMode.enabled then
                self:CheckTestPlayerTurn()
            end
        elseif PS.phase == PS.PHASE.SETTLEMENT then
            -- Already in settlement (shouldn't normally happen but handle it)
            BJ:Debug("ProcessAction: -> Already in settlement")
            PM:SendSettlement()
        end
    else
        BJ:Print("Action failed: " .. (result or "unknown"))
    end
end

function PM:DoShowdown()
    local PS = BJ.PokerState
    
    -- Already evaluated in EndBettingRound
    PM:Send(MSG.SHOWDOWN)
    
    if BJ.UI and BJ.UI.Poker then
        BJ.UI.Poker:OnShowdown()
    end
    
    C_Timer.After(2.0, function()
        PM:SendSettlement()
    end)
end

function PM:SendSettlement()
    local PS = BJ.PokerState
    
    -- Save to game history before sending
    PS:SaveGameToHistory()
    
    local winnersStr = table.concat(PS.winners, ",")
    local settlementParts = {}
    for _, playerName in ipairs(PS.playerOrder) do
        local settlement = PS.settlements[playerName]
        local player = PS.players[playerName]
        if settlement and player then
            -- Format: name:handRank:handName:total:folded:bet
            table.insert(settlementParts, playerName .. ":" .. 
                (player.handRank or 0) .. ":" .. 
                (player.handName or "?") .. ":" ..
                settlement.total .. ":" ..
                (player.folded and "1" or "0") .. ":" ..
                (player.totalBet or 0))
        end
    end
    
    -- Include pot in message
    PM:Send(MSG.SETTLEMENT, winnersStr, table.concat(settlementParts, ";"), PS.pot)
    
    if BJ.UI and BJ.UI.Poker then
        BJ.UI.Poker:OnSettlement()
    end
end

function PM:LeaveTable()
    PM:CancelCountdown()
    if PM.isHost then
        PM:Send(MSG.TABLE_CLOSE)
        BJ:Print("5 Card Stud table closed.")
        
        -- End leaderboard session
        if BJ.Leaderboard then
            BJ.Leaderboard:EndSession("poker")
        end
    else
        PM:Send(MSG.LEAVE)
        BJ:Print("Left 5 Card Stud table.")
    end
    PM:ResetState()
    if BJ.UI and BJ.UI.Poker then BJ.UI.Poker:OnTableClosed() end
end

function PM:PlaceAnte(amount)
    local PS = BJ.PokerState
    
    if PM.isHost then
        local success, err = PS:PlayerAnte(UnitName("player"), amount)
        if success then
            BJ:Print("You anted " .. amount .. "g")
            PM:Send(MSG.SYNC_STATE, "ANTE", UnitName("player"), amount, PS.pot)
            if BJ.UI and BJ.UI.Poker then BJ.UI.Poker:OnPlayerAnted(UnitName("player"), amount) end
        else
            BJ:Print("Ante failed: " .. (err or "unknown"))
        end
        return success
    end
    
    if not PM.tableOpen then
        BJ:Print("No 5 Card Stud table open.")
        return false
    end
    
    -- Check version before joining
    if PM.hostVersion and PM.hostVersion ~= BJ.version then
        BJ:Print("|cffff4444Version mismatch!|r Host has v" .. PM.hostVersion .. ", you have v" .. BJ.version)
        BJ:Print("Please update your addon to join this table.")
        return false
    end
    
    -- Optimistically add ourselves to local state so UI updates immediately
    local myName = UnitName("player")
    if not PS.players[myName] then
        PS:PlayerAnte(myName, amount)
        BJ:Print("You anted " .. amount .. "g")
        if BJ.UI and BJ.UI.Poker then 
            BJ.UI.Poker:OnPlayerAnted(myName, amount) 
        end
    end
    
    -- Send ante with version to host for confirmation
    PM:Send(MSG.ANTE, amount, BJ.version)
    return true
end

--[[
    MESSAGE HANDLERS
]]

function PM:HandleTableOpen(sender, parts)
    local ante = tonumber(parts[2])
    local maxRaise = tonumber(parts[3])
    local seed = tonumber(parts[4])
    local pot = tonumber(parts[5]) or ante  -- Host has already anted
    local maxPlayers = tonumber(parts[6]) or 10
    local cdEnabled = tonumber(parts[7]) or 0
    local cdSeconds = tonumber(parts[8]) or 0
    local hostVersion = parts[9]  -- Host's addon version
    local senderName = sender:match("^([^-]+)") or sender
    
    PM.currentHost = senderName
    PM.tableOpen = true
    PM.isHost = false
    PM.hostVersion = hostVersion  -- Store for version check on join
    
    -- Check if host has newer version
    if hostVersion then
        BJ:OnPeerVersion(hostVersion, senderName)
    end
    
    BJ.PokerState:StartRound(senderName, ante, maxRaise, seed)
    BJ.PokerState.maxPlayers = maxPlayers
    
    -- Register host as already anted (without triggering another ante)
    BJ.PokerState:PlayerAnte(senderName, ante)
    BJ.PokerState.pot = pot  -- Sync pot from host
    
    local maxPText = ""
    if maxPlayers < 10 then
        maxPText = " | Max " .. maxPlayers .. " players"
    end
    
    local cdText = ""
    if cdEnabled == 1 and cdSeconds > 0 then
        cdText = " (Betting: " .. cdSeconds .. "s)"
    end
    
    local gameLink = BJ:CreateGameLink("poker", "5 Card Stud")
    BJ:Print(senderName .. " opened " .. gameLink .. "! Ante: " .. ante .. "g | Max Raise: " .. maxRaise .. "g" .. maxPText .. cdText)
    
    -- Play game start sound
    PlaySoundFile("Interface\\AddOns\\Chairfaces Casino\\Sounds\\chips.ogg", "SFX")
    
    if BJ.UI and BJ.UI.Poker then
        BJ.UI.Poker:OnTableOpened(senderName, { ante = ante, maxRaise = maxRaise, maxPlayers = maxPlayers })
    end
end

function PM:HandleTableClose(sender, parts)
    local senderName = sender:match("^([^-]+)") or sender
    if senderName ~= PM.currentHost then return end
    BJ:Print("5 Card Stud table closed.")
    PM:ResetState()
    if BJ.UI and BJ.UI.Poker then BJ.UI.Poker:OnTableClosed() end
end

function PM:HandleCountdown(sender, parts)
    local senderName = sender:match("^([^-]+)") or sender
    if senderName ~= PM.currentHost then return end
    local remaining = tonumber(parts[2])
    PM.countdownRemaining = remaining
    if BJ.UI and BJ.UI.Poker then BJ.UI.Poker:OnCountdownTick(remaining) end
end

function PM:HandleAnte(sender, parts)
    if not PM.isHost then return end
    local playerName = sender:match("^([^-]+)") or sender
    local amount = tonumber(parts[2])
    local playerVersion = parts[3]  -- Player's addon version
    
    -- Check if player has newer version (notify host)
    if playerVersion then
        BJ:OnPeerVersion(playerVersion, playerName)
    end
    
    -- Version check
    if playerVersion and playerVersion ~= BJ.version then
        BJ:Print("|cffff8800" .. playerName .. " rejected - version mismatch|r (v" .. playerVersion .. " vs v" .. BJ.version .. ")")
        -- Notify the player their version is outdated
        PM:SendWhisper(sender, MSG.VERSION_REJECT, BJ.version)
        return
    end
    
    -- Check max players
    local maxPlayers = BJ.PokerState.maxPlayers or 10
    if #BJ.PokerState.playerOrder >= maxPlayers then
        BJ:Debug("Table full - " .. playerName .. " cannot ante")
        return
    end
    
    local success, err = BJ.PokerState:PlayerAnte(playerName, amount)
    if success then
        BJ:Print(playerName .. " anted " .. amount .. "g")
        -- Include pot so clients stay synced
        PM:Send(MSG.SYNC_STATE, "ANTE", playerName, amount, BJ.PokerState.pot)
        -- skipSound=true: joining sound is local only (the joining player hears it on their end)
        if BJ.UI and BJ.UI.Poker then BJ.UI.Poker:OnPlayerAnted(playerName, amount, true) end
    end
end

function PM:HandleLeave(sender, parts)
    if not PM.isHost then return end
    local playerName = sender:match("^([^-]+)") or sender
    -- Handle leave logic
    BJ:Print(playerName .. " left poker.")
    if BJ.UI and BJ.UI.Poker then BJ.UI.Poker:UpdateDisplay() end
end

function PM:HandleVersionReject(sender, parts)
    local hostVersion = parts[2]
    BJ:Print("|cffff4444Your addon version is outdated!|r")
    BJ:Print("Host has v" .. (hostVersion or "?") .. ", you have v" .. BJ.version)
    BJ:Print("Please update Chairface's Casino to join this table.")
    
    -- Show popup dialog
    StaticPopupDialogs["CASINO_POKER_VERSION_MISMATCH"] = {
        text = "|cffffd700Version Mismatch|r\n\nYour addon version (v" .. BJ.version .. ") is different from the host's version (v" .. (hostVersion or "?") .. ").\n\nPlease update Chairface's Casino to join this table.",
        button1 = "OK",
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    StaticPopup_Show("CASINO_POKER_VERSION_MISMATCH")
end

function PM:HandleDealStart(sender, parts)
    local senderName = sender:match("^([^-]+)") or sender
    if senderName ~= PM.currentHost then return end
    
    local PS = BJ.PokerState
    
    -- Parse player list: playerName1,ante1;playerName2,ante2;...
    local playerDataStr = parts[2]
    if playerDataStr then
        -- Clear and rebuild player list
        PS.playerOrder = {}
        PS.players = {}
        
        for entry in playerDataStr:gmatch("[^;]+") do
            local pname, ante = entry:match("([^,]+),(%d+)")
            if pname then
                ante = tonumber(ante) or PS.ante
                table.insert(PS.playerOrder, pname)
                PS.players[pname] = {
                    hand = {},
                    folded = false,
                    currentBet = ante,
                    totalBet = ante,
                    allIn = false,
                }
            end
        end
    end
    
    PS.phase = PS.PHASE.DEALING
    BJ:Print("Dealing starting... " .. #PS.playerOrder .. " players")
    
    if BJ.UI and BJ.UI.Poker then BJ.UI.Poker:OnDealStart() end
end

function PM:HandleDealCard(sender, parts)
    local senderName = sender:match("^([^-]+)") or sender
    if senderName ~= PM.currentHost then return end
    
    local PS = BJ.PokerState
    local playerName = parts[2]
    local rank = parts[3]
    local suit = parts[4]
    local faceUp = parts[5] == "1"
    local round = tonumber(parts[6])
    local cardsRemaining = tonumber(parts[7])
    
    -- Update synced cards remaining
    if cardsRemaining then
        PS.syncedCardsRemaining = cardsRemaining
    end
    
    local player = PS.players[playerName]
    if player then
        local card = { rank = rank, suit = suit, faceUp = faceUp }
        table.insert(player.hand, card)
        
        if BJ.UI and BJ.UI.Poker then
            BJ.UI.Poker:OnCardDealt(playerName, card, #player.hand)
            BJ.UI.Poker:UpdateInfoText()  -- Update card count display
        end
    end
end

function PM:HandleBettingStart(sender, parts)
    local senderName = sender:match("^([^-]+)") or sender
    if senderName ~= PM.currentHost then return end
    
    local PS = BJ.PokerState
    local street = tonumber(parts[2])
    local starterIndex = tonumber(parts[3]) or 1
    
    -- Set phase and use the host's starter index directly
    PS.currentStreet = street
    PS.phase = PS.PHASE.BETTING
    PS.currentBet = 0
    PS.currentPlayerIndex = starterIndex
    
    -- Reset bets for new round
    for _, player in pairs(PS.players) do
        player.currentBet = 0
    end
    
    local starter = PS.playerOrder[starterIndex]
    BJ:Debug("Client: Betting round " .. street .. " started. Current player: " .. (starter or "?") .. " (index " .. starterIndex .. ")")
    
    if BJ.UI and BJ.UI.Poker then
        BJ.UI.Poker:OnBettingStart(street, starter)
    end
end

function PM:HandleAction(sender, parts)
    if not PM.isHost then return end
    local playerName = sender:match("^([^-]+)") or sender
    local action = parts[2]
    local amount = tonumber(parts[3]) or 0
    
    self:ProcessAction(playerName, action, amount)
end

function PM:HandleSyncState(sender, parts)
    local senderName = sender:match("^([^-]+)") or sender
    BJ:Debug("HandleSyncState: sender=" .. senderName .. ", currentHost=" .. tostring(PM.currentHost))
    if senderName ~= PM.currentHost then 
        BJ:Debug("HandleSyncState: REJECTED - sender is not host")
        return 
    end
    
    local PS = BJ.PokerState
    -- Message format: PSYNC|syncType|version|...data
    -- parts[1] = PSYNC (msgType)
    -- parts[2] = syncType (ANTE, ACTION, etc.)
    -- parts[3] = version number
    -- parts[4+] = actual data
    local syncType = parts[2]
    local version = tonumber(parts[3]) or 0
    
    BJ:Debug("HandleSyncState: syncType=" .. tostring(syncType) .. ", version=" .. tostring(version))
    
    if syncType == "ANTE" then
        -- parts[4] = playerName, parts[5] = amount, parts[6] = pot
        local playerName = parts[4]
        local amount = tonumber(parts[5])
        local pot = tonumber(parts[6])
        -- Validate data before calling PlayerAnte
        if not playerName or not amount then
            BJ:Debug("Invalid ANTE sync data: playerName=" .. tostring(playerName) .. ", amount=" .. tostring(amount))
            return
        end
        BJ:Debug("ANTE sync: player=" .. playerName .. ", amount=" .. amount .. ", pot=" .. tostring(pot))
        -- Only add player if not already in game (may have been optimistically added)
        local alreadyAdded = PS.players[playerName] ~= nil
        if not alreadyAdded then
            PS:PlayerAnte(playerName, amount)
        end
        -- Override pot with synced value from host
        if pot then
            PS.pot = pot
        end
        -- Skip sound: only play for our own ante, and only if we haven't already played it
        local myName = UnitName("player")
        local isMyAnte = (playerName == myName)
        local skipSound = (not isMyAnte) or alreadyAdded  -- Skip if not our ante, or if we already played it
        if BJ.UI and BJ.UI.Poker then BJ.UI.Poker:OnPlayerAnted(playerName, amount, skipSound) end
        
    elseif syncType == "ACTION" then
        -- parts[4] = playerName, parts[5] = action, parts[6] = amount, parts[7] = pot, 
        -- parts[8] = currentBet, parts[9] = currentPlayerIdx, parts[10] = phase
        local playerName = parts[4]
        local action = parts[5]
        local amount = tonumber(parts[6]) or 0
        local pot = tonumber(parts[7]) or 0
        local currentBet = tonumber(parts[8]) or 0
        local currentPlayerIdx = tonumber(parts[9]) or 1
        local phase = parts[10] or PS.phase
        
        BJ:Debug("Client received ACTION sync: player=" .. tostring(playerName) .. 
            ", action=" .. tostring(action) .. 
            ", nextPlayerIdx=" .. tostring(currentPlayerIdx) .. 
            ", phase=" .. tostring(phase))
        
        -- Update local state
        local player = PS.players[playerName]
        if player then
            if action == "fold" then
                player.folded = true
            elseif action == "check" then
                -- Check doesn't change bets
            elseif action == "call" then
                player.currentBet = currentBet
                player.totalBet = player.totalBet + (currentBet - (player.currentBet or 0))
            elseif action == "raise" then
                player.currentBet = currentBet
                player.totalBet = player.totalBet + amount
            end
        end
        PS.pot = pot
        PS.currentBet = currentBet
        PS.currentPlayerIndex = currentPlayerIdx
        PS.phase = phase
        
        local nextPlayer = PS.playerOrder[currentPlayerIdx]
        BJ:Debug("Client: Next player should be: " .. tostring(nextPlayer) .. " (index " .. currentPlayerIdx .. ")")
        
        if BJ.UI and BJ.UI.Poker then
            BJ.UI.Poker:OnPlayerAction(playerName, action, amount)
        end
        
    elseif syncType == "REQUEST_STATE" then
        -- Someone just logged in/reloaded and is requesting state
        local requesterName = parts[4]
        local myName = UnitName("player")
        
        if PM.isHost or PM.temporaryHost == myName then
            if PM:IsInRecoveryMode() then
                C_Timer.After(0.5, function()
                    PM:Send(MSG.SYNC_STATE, "RECOVERY_STATE", PM.originalHost, PM.temporaryHost, 
                        PM.RECOVERY_TIMEOUT - (time() - PM.recoveryStartTime))
                end)
            elseif BJ.PokerState.phase ~= BJ.PokerState.PHASE.IDLE then
                C_Timer.After(0.5, function()
                    if BJ.StateSync then
                        BJ.StateSync:BroadcastFullState("poker")
                    end
                end)
            end
        end
        
    elseif syncType == "RECOVERY_STATE" then
        local origHost = parts[4]
        local tempHost = parts[5]
        local remaining = tonumber(parts[6]) or 120
        local myName = UnitName("player")
        
        PM.hostDisconnected = true
        PM.originalHost = origHost
        PM.temporaryHost = tempHost
        PM.currentHost = origHost
        PM.recoveryStartTime = time() - (PM.RECOVERY_TIMEOUT - remaining)
        
        if origHost == myName then
            BJ:Print("|cff00ff00You have reconnected as host. Restoring game...|r")
            PM:RestoreOriginalHost()
        else
            BJ:Print("|cffff88005 Card Stud paused - waiting for " .. origHost .. " to return.|r")
            if BJ.UI and BJ.UI.Poker and BJ.UI.Poker.OnHostRecoveryStart then
                BJ.UI.Poker:OnHostRecoveryStart(origHost, tempHost)
            end
        end
        
    elseif syncType == "HOST_RECOVERY_START" then
        -- Host disconnected, temporary host taking over
        local tempHost = parts[4]
        local origHost = parts[5]
        local myName = UnitName("player")
        
        PM.hostDisconnected = true
        PM.originalHost = origHost
        PM.temporaryHost = tempHost
        PM.recoveryStartTime = time()
        
        BJ:Print("|cffff8800" .. origHost .. " disconnected. " .. tempHost .. " is temporary host.|r")
        BJ:Print("|cffff8800Game PAUSED. Waiting up to 2 minutes for host to return.|r")
        
        -- Non-temp-host clients start local countdown when they receive the broadcast
        if tempHost ~= myName then
            PM:StartLocalRecoveryCountdown()
            PM:ShowRecoveryPopup(origHost, false)
        end
        
        if BJ.UI and BJ.UI.Poker and BJ.UI.Poker.OnHostRecoveryStart then
            BJ.UI.Poker:OnHostRecoveryStart(origHost, tempHost)
        end
        
    elseif syncType == "HOST_RECOVERY_TICK" then
        local remaining = tonumber(parts[4])
        -- Update popup timer
        PM:UpdateRecoveryPopupTimer(remaining)
        if BJ.UI and BJ.UI.Poker and BJ.UI.Poker.UpdateRecoveryTimer then
            BJ.UI.Poker:UpdateRecoveryTimer(remaining)
        end
        
    elseif syncType == "HOST_RESTORED" then
        local origHost = parts[4]
        
        BJ:Print("|cff00ff00" .. origHost .. " has returned! Game resuming.|r")
        
        -- Cancel local recovery timer
        if PM.localRecoveryTimer then
            PM.localRecoveryTimer:Cancel()
            PM.localRecoveryTimer = nil
        end
        
        -- Close recovery popup
        PM:CloseRecoveryPopup()
        
        PM.hostDisconnected = false
        PM.originalHost = nil
        PM.temporaryHost = nil
        PM.recoveryStartTime = nil
        
        if BJ.UI and BJ.UI.Poker and BJ.UI.Poker.OnHostRestored then
            BJ.UI.Poker:OnHostRestored()
        end
        
    elseif syncType == "GAME_VOIDED" then
        local reason = parts[4] or "Unknown reason"
        
        BJ:Print("|cffff44445 Card Stud VOIDED: " .. reason .. "|r")
        
        PM.hostDisconnected = false
        PM.originalHost = nil
        PM.temporaryHost = nil
        PM.recoveryStartTime = nil
        PM:ResetState()
        
        if BJ.UI and BJ.UI.Poker and BJ.UI.Poker.OnGameVoided then
            BJ.UI.Poker:OnGameVoided(reason)
        end
    end
end

function PM:HandleShowdown(sender, parts)
    local senderName = sender:match("^([^-]+)") or sender
    if senderName ~= PM.currentHost then return end
    
    BJ.PokerState.phase = BJ.PokerState.PHASE.SHOWDOWN
    if BJ.UI and BJ.UI.Poker then BJ.UI.Poker:OnShowdown() end
end

function PM:HandleSettlement(sender, parts)
    BJ:Debug("HandleSettlement CALLED - sender=" .. tostring(sender))
    local senderName = sender:match("^([^-]+)") or sender
    BJ:Debug("HandleSettlement: senderName=" .. senderName .. ", currentHost=" .. tostring(PM.currentHost))
    if senderName ~= PM.currentHost then 
        BJ:Debug("HandleSettlement: REJECTED - sender is not host")
        return 
    end
    BJ:Debug("HandleSettlement: ACCEPTED - processing settlement")
    
    local PS = BJ.PokerState
    local winnersStr = parts[2]
    local settlementStr = parts[3]
    local pot = tonumber(parts[4]) or PS.pot
    
    BJ:Debug("HandleSettlement: winners=" .. (winnersStr or "nil") .. ", pot=" .. pot)
    BJ:Debug("HandleSettlement: settlementStr=" .. (settlementStr or "nil"))
    
    PS.pot = pot
    PS.winners = {}
    for name in winnersStr:gmatch("[^,]+") do
        table.insert(PS.winners, name)
    end
    
    PS.settlements = {}
    for entry in settlementStr:gmatch("[^;]+") do
        -- Format: name:handRank:handName:total:folded:bet
        -- Use more flexible parsing to handle handNames with special chars
        local colonParts = {}
        for part in entry:gmatch("[^:]+") do
            table.insert(colonParts, part)
        end
        
        if #colonParts >= 5 then
            local playerName = colonParts[1]
            local handRank = tonumber(colonParts[2]) or 0
            local handName = colonParts[3] or "?"
            local total = tonumber(colonParts[4]) or 0
            local folded = colonParts[5] == "1"
            local bet = tonumber(colonParts[6]) or 0
            
            BJ:Debug("  Player: " .. playerName .. ", handName=" .. handName .. ", total=" .. total)
            
            local player = PS.players[playerName]
            if player then
                player.handRank = handRank
                player.handName = handName
                player.folded = folded
                player.totalBet = bet > 0 and bet or player.totalBet or 0
            end
            
            local isWinner = false
            for _, w in ipairs(PS.winners) do
                if w == playerName then isWinner = true break end
            end
            
            PS.settlements[playerName] = {
                total = total,
                bet = bet,
                isWinner = isWinner,
                handName = handName,
                folded = folded,
            }
        end
    end
    
    PS.phase = PS.PHASE.SETTLEMENT
    
    -- Save to game history for clients too
    PS:SaveGameToHistory()
    
    -- Update client's own stats from settlement data
    if BJ.Leaderboard then
        -- Debug: show what names we're looking for
        local myName = UnitName("player")
        local myRealm = GetRealmName()
        BJ:Debug("HandleSettlement: About to call UpdateMyStatsFromSettlement")
        BJ:Debug("HandleSettlement: myName='" .. tostring(myName) .. "', myRealm='" .. tostring(myRealm) .. "'")
        BJ:Debug("HandleSettlement: Settlement keys:")
        for k, v in pairs(PS.settlements) do
            BJ:Debug("  Key: '" .. tostring(k) .. "', total=" .. tostring(v.total))
        end
        BJ.Leaderboard:UpdateMyStatsFromSettlement("poker")
    end
    
    BJ:Debug("HandleSettlement: phase set to SETTLEMENT")
    
    BJ:Print("Game over! Winner: " .. (PS.winners[1] or "?"))
    if BJ.UI and BJ.UI.Poker then 
        BJ:Debug("Calling OnSettlement")
        BJ.UI.Poker:OnSettlement() 
    end
end
