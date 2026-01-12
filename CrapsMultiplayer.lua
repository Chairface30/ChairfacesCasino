--[[
    Chairface's Casino - CrapsMultiplayer.lua
    Multiplayer communication for Craps game
    Uses AceComm for reliable message delivery
    
    The host manages all game state and validates actions.
    Clients send bet requests and roll requests to host.
    Host broadcasts state changes to all players.
]]

local BJ = ChairfacesCasino
BJ.CrapsMultiplayer = {}
local CM = BJ.CrapsMultiplayer

-- Get AceComm library
local AceComm = LibStub("AceComm-3.0")

-- Communication channel prefix
local CHANNEL_PREFIX = "CCCraps"

-- Message types
local MSG = {
    TABLE_OPEN = "OPEN",
    TABLE_CLOSE = "CLOSE",
    PLAYER_JOIN = "JOIN",
    PLAYER_LEAVE = "LEAVE",
    BET_REQUEST = "BETREQ",
    BET_CONFIRM = "BETOK",
    BET_REJECT = "BETNO",
    BET_SYNC = "BETSYNC",        -- Sync bet changes to all players
    BET_REMOVE_REQ = "BETRMREQ", -- Request to remove a bet
    BET_REMOVE_OK = "BETRMOK",   -- Bet removal confirmed
    BETTING_OPEN = "BETOPEN",
    BETTING_CLOSE = "BETCLOSE",
    BETTING_PHASE = "BETPHASE",  -- New betting phase started with timer
    ROLL_RESULT = "ROLL",
    POINT_SET = "POINT",
    SHOOTER_CHANGE = "SHOOTER",
    SKIP_SHOOTER = "SKIPSHOOT",  -- Player skips their turn as shooter
    SETTLEMENT = "SETTLE",
    STATE_SYNC = "SYNC",
    HOST_TRANSFER = "HTRANS",
    GAME_VOIDED = "VOID",
    RESET = "RESET",             -- Host resets game state
    -- Honor Ledger messages
    JOIN_REQUEST = "JOINREQ",    -- Player requests to join with buy-in
    JOIN_APPROVE = "JOINOK",     -- Host approves join
    JOIN_DENY = "JOINNO",        -- Host denies join
    BALANCE_UPDATE = "BALANCE",  -- Balance changed
    CASH_OUT = "CASHOUT",        -- Player cashing out
    CASH_OUT_RECEIPT = "RECEIPT", -- Receipt sent to player
    LOCK_IN = "LOCKIN",          -- Player locked in their bets
    -- Host recovery messages
    HOST_RECOVERY_START = "HRECOV",
    HOST_RECOVERY_TICK = "HRECTICK",
    HOST_RECOVERY_STATE = "HRECSTATE",
    HOST_RESTORED = "HREST",
    -- Session restore messages
    SESSION_RECONNECT = "SESSRECON", -- Notify player they can reconnect with saved balance
}

-- Expose MSG for external use
CM.MSG = MSG

-- State
CM.isHost = false
CM.currentHost = nil
CM.tableOpen = false
CM.chatFrame = nil

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
function CM:Initialize()
    AceComm:RegisterComm(CHANNEL_PREFIX, function(prefix, message, distribution, sender)
        CM:OnCommReceived(prefix, message, distribution, sender)
    end)
    
    if not self.chatFrame then
        self.chatFrame = CreateFrame("Frame")
        self.chatFrame:RegisterEvent("CHAT_MSG_SYSTEM")
        self.chatFrame:RegisterEvent("CHAT_MSG_PARTY")
        self.chatFrame:RegisterEvent("CHAT_MSG_PARTY_LEADER")
        self.chatFrame:RegisterEvent("CHAT_MSG_RAID")
        self.chatFrame:RegisterEvent("CHAT_MSG_RAID_LEADER")
        self.chatFrame:SetScript("OnEvent", function(frame, event, message, sender, ...)
            if event == "CHAT_MSG_SYSTEM" then
                CM:OnSystemMessage(message)
            else
                CM:OnChatMessage(message, sender)
            end
        end)
    end
    
    BJ:Debug("Craps Multiplayer initialized")
end

-- Send message to group via AceComm
function CM:Send(msgType, ...)
    local msg = serialize(msgType, ...)
    local channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY" or nil)
    
    if channel then
        local compressed, wasCompressed = msg, false
        if BJ.Compression and BJ.Compression.available then
            compressed, wasCompressed = BJ.Compression:Compress(msg)
        end
        AceComm:SendCommMessage(CHANNEL_PREFIX, compressed, channel)
        BJ:Debug("Craps Sent: " .. (wasCompressed and "[compressed]" or msg))
    end
end

-- Send message to specific player
function CM:SendWhisper(target, msgType, ...)
    local msg = serialize(msgType, ...)
    local compressed = msg
    if BJ.Compression and BJ.Compression.available then
        compressed = BJ.Compression:Compress(msg) or msg
    end
    AceComm:SendCommMessage(CHANNEL_PREFIX, compressed, "WHISPER", target)
end

-- Handle incoming messages
function CM:OnCommReceived(prefix, message, distribution, sender)
    if prefix ~= CHANNEL_PREFIX then return end
    
    local myName = UnitName("player")
    local senderName = sender:match("^([^-]+)") or sender
    if senderName == myName then return end
    
    -- Check for StateSync full state message first (before decompression)
    if BJ.StateSync and BJ.StateSync:IsFullStateMessage(message) then
        local stateData = BJ.StateSync:ExtractFullStateData(message)
        if stateData then
            BJ.StateSync:HandleFullState("craps", stateData)
        end
        return
    end
    
    -- Check for StateSync request (host only)
    if BJ.StateSync and BJ.StateSync:IsSyncRequestMessage(message) then
        if CM.isHost then
            local game = BJ.StateSync:ExtractSyncRequestGame(message)
            if game == "craps" then
                BJ.StateSync:HandleSyncRequest("craps", senderName)
            end
        end
        return
    end
    
    -- Check for discovery request (host responds)
    if BJ.StateSync and BJ.StateSync:IsDiscoveryMessage(message) then
        BJ.StateSync:HandleDiscoveryRequest("craps", senderName)
        return
    end
    
    -- Check for host announcement (client learns about host)
    if BJ.StateSync and BJ.StateSync:IsHostAnnounceMessage(message) then
        local game, hostName, phase = message:match("HOSTANNOUN|(%w+)|([^|]+)|(.+)")
        if game == "craps" then
            BJ.StateSync:HandleHostAnnounce("craps", hostName, phase)
        end
        return
    end
    
    if BJ.Compression then
        local decompressed = BJ.Compression:Decompress(message)
        if decompressed then
            message = decompressed
        elseif message:sub(1, 1) == "~" then
            return
        end
    end
    
    local parts = deserialize(message)
    local msgType = parts[1]
    
    BJ:Debug("Craps Received from " .. sender .. ": " .. msgType)
    
    if msgType == MSG.TABLE_OPEN then
        self:HandleTableOpen(senderName, parts)
    elseif msgType == MSG.TABLE_CLOSE then
        self:HandleTableClose(senderName, parts)
    elseif msgType == MSG.PLAYER_JOIN then
        self:HandlePlayerJoin(senderName, parts)
    elseif msgType == MSG.PLAYER_LEAVE then
        self:HandlePlayerLeave(senderName, parts)
    elseif msgType == MSG.BET_REQUEST then
        self:HandleBetRequest(senderName, parts)
    elseif msgType == MSG.BET_CONFIRM then
        self:HandleBetConfirm(senderName, parts)
    elseif msgType == MSG.BET_REJECT then
        self:HandleBetReject(senderName, parts)
    elseif msgType == MSG.BET_SYNC then
        self:HandleBetSync(senderName, parts)
    elseif msgType == MSG.BET_REMOVE_REQ then
        self:HandleBetRemoveRequest(senderName, parts)
    elseif msgType == MSG.BET_REMOVE_OK then
        self:HandleBetRemoveConfirm(senderName, parts)
    elseif msgType == MSG.BETTING_OPEN then
        self:HandleBettingOpen(senderName, parts)
    elseif msgType == MSG.BETTING_CLOSE then
        self:HandleBettingClose(senderName, parts)
    elseif msgType == MSG.BETTING_PHASE then
        self:HandleBettingPhase(senderName, parts)
    elseif msgType == MSG.ROLL_RESULT then
        self:HandleRollResult(senderName, parts)
    elseif msgType == MSG.POINT_SET then
        self:HandlePointSet(senderName, parts)
    elseif msgType == MSG.SHOOTER_CHANGE then
        self:HandleShooterChange(senderName, parts)
    elseif msgType == MSG.SKIP_SHOOTER then
        self:HandleSkipShooter(senderName, parts)
    elseif msgType == MSG.SETTLEMENT then
        self:HandleSettlement(senderName, parts)
    elseif msgType == MSG.STATE_SYNC then
        self:HandleStateSync(senderName, parts)
    elseif msgType == MSG.HOST_TRANSFER then
        self:HandleHostTransfer(senderName, parts)
    elseif msgType == MSG.GAME_VOIDED then
        self:HandleGameVoided(senderName, parts)
    elseif msgType == MSG.RESET then
        self:HandleReset(senderName, parts)
    -- Honor Ledger handlers
    elseif msgType == MSG.JOIN_REQUEST then
        self:HandleJoinRequest(senderName, parts)
    elseif msgType == MSG.JOIN_APPROVE then
        self:HandleJoinApprove(senderName, parts)
    elseif msgType == MSG.JOIN_DENY then
        self:HandleJoinDeny(senderName, parts)
    elseif msgType == MSG.BALANCE_UPDATE then
        self:HandleBalanceUpdate(senderName, parts)
    elseif msgType == MSG.CASH_OUT then
        self:HandleCashOut(senderName, parts)
    elseif msgType == MSG.CASH_OUT_RECEIPT then
        self:HandleCashOutReceipt(senderName, parts)
    elseif msgType == MSG.LOCK_IN then
        self:HandleLockIn(senderName, parts)
    -- Host recovery handlers
    elseif msgType == MSG.HOST_RECOVERY_START then
        self:HandleHostRecoveryStart(senderName, parts)
    elseif msgType == MSG.HOST_RECOVERY_TICK then
        self:HandleHostRecoveryTick(senderName, parts)
    elseif msgType == MSG.HOST_RECOVERY_STATE then
        self:HandleHostRecoveryState(senderName, parts)
    elseif msgType == MSG.HOST_RESTORED then
        self:HandleHostRestored(senderName, parts)
    elseif msgType == MSG.SESSION_RECONNECT then
        self:HandleSessionReconnect(senderName, parts)
    end
end

-- Handle notification that we can reconnect to restored session
function CM:HandleSessionReconnect(hostName, parts)
    local playerName = parts[2]
    local balance = tonumber(parts[3]) or 0
    local myName = UnitName("player")
    
    -- Only care if this is for us
    if playerName ~= myName then return end
    
    -- Store that we have a pending reconnect opportunity
    CM.pendingReconnect = {
        host = hostName,
        balance = balance,
        time = time()
    }
    
    -- Show notification
    BJ:Print("|cff00ff00" .. hostName .. " has restored the previous session!|r")
    BJ:Print("|cffffd700Your balance of " .. BJ:FormatGoldColored(balance) .. " is waiting.|r")
    BJ:Print("|cffffd700Click 'Join Table' to reconnect.|r")
    
    -- Update UI to show reconnect option
    if BJ.UI and BJ.UI.Craps then
        BJ.UI.Craps:UpdateDisplay()
    end
end

-- Handle host recovery start
function CM:HandleHostRecoveryStart(senderName, parts)
    local tempHost = parts[2]
    local origHost = parts[3]
    local myName = UnitName("player")
    
    CM.hostDisconnected = true
    CM.originalHost = origHost
    CM.temporaryHost = tempHost
    CM.recoveryStartTime = time()
    
    BJ:Print("|cffff8800" .. origHost .. " disconnected. " .. tempHost .. " is temporary host.|r")
    BJ:Print("|cffff8800Game PAUSED. Waiting up to 2 minutes for host to return.|r")
    
    -- Show popup for non-temp-host players
    if tempHost ~= myName then
        CM:ShowRecoveryPopup(origHost, false)
        CM:StartLocalRecoveryCountdown()
    end
    
    if BJ.UI and BJ.UI.Craps then
        BJ.UI.Craps:OnHostRecoveryStart(origHost, tempHost)
    end
end

-- Handle recovery timer tick
function CM:HandleHostRecoveryTick(senderName, parts)
    local remaining = tonumber(parts[2])
    
    -- Sync our local time
    CM.recoveryStartTime = time() - (CM.RECOVERY_TIMEOUT - remaining)
    CM:UpdateRecoveryPopupTimer(remaining)
    
    if BJ.UI and BJ.UI.Craps and BJ.UI.Craps.UpdateRecoveryTimer then
        BJ.UI.Craps:UpdateRecoveryTimer(remaining)
    end
end

-- Handle host restored
function CM:HandleHostRestored(senderName, parts)
    local origHost = parts[2]
    
    BJ:Print("|cff00ff00" .. origHost .. " has returned! Game resuming.|r")
    
    -- Cancel local timer
    if CM.localRecoveryTimer then
        CM.localRecoveryTimer:Cancel()
        CM.localRecoveryTimer = nil
    end
    
    -- Close popup
    CM:CloseRecoveryPopup()
    
    CM.hostDisconnected = false
    CM.originalHost = nil
    CM.temporaryHost = nil
    CM.recoveryStartTime = nil
    CM.currentHost = origHost
    
    local CS = BJ.CrapsState
    CS.hostName = origHost
    
    if BJ.UI and BJ.UI.Craps then
        BJ.UI.Craps:OnHostRestored()
    end
end

-- Handle recovery state sent to reconnecting host
function CM:HandleHostRecoveryState(senderName, parts)
    local origHost = parts[2]
    local tempHost = parts[3]
    local remaining = tonumber(parts[4]) or 120
    local myName = UnitName("player")
    
    -- Only the original host should process this
    if origHost ~= myName then return end
    
    -- Set up recovery state so RestoreOriginalHost can be called
    CM.hostDisconnected = true
    CM.originalHost = origHost
    CM.temporaryHost = tempHost
    CM.recoveryStartTime = time() - (CM.RECOVERY_TIMEOUT - remaining)
    
    -- Now restore ourselves as host
    CM:RestoreOriginalHost()
end

-- Handle reset from host
function CM:HandleReset(senderName, parts)
    local CS = BJ.CrapsState
    CS:Reset()
    
    CM.isHost = false
    CM.currentHost = nil
    CM.tableOpen = false
    
    BJ:Print("|cffff8800Craps game reset by host.|r")
    
    if BJ.UI and BJ.UI.Craps then
        BJ.UI.Craps:UpdateDisplay()
    end
end

-- HOST ACTIONS --

function CM:HostTable(settings)
    local myName = UnitName("player")
    local inTestMode = BJ.TestMode and BJ.TestMode.enabled
    
    if not IsInGroup() and not IsInRaid() and not inTestMode then
        BJ:Print("You must be in a party or raid to host Craps.")
        return false
    end
    
    local CS = BJ.CrapsState
    local Lobby = BJ.UI and BJ.UI.Lobby
    if Lobby and Lobby.IsAnyGameActive then
        local isActive, activeGame = Lobby:IsAnyGameActive()
        if isActive then
            local gameName = Lobby:GetGameName(activeGame)
            BJ:Print("|cffff4444Cannot host - a " .. gameName .. " game is in progress.|r")
            return false
        end
    end
    
    local success = CS:HostTable(myName, settings)
    if not success then return false end
    
    -- Host cannot be the shooter - set shooter to nil until a player joins
    CS.shooterName = nil
    
    CM.isHost = true
    CM.currentHost = myName
    CM.tableOpen = true
    
    -- Include table cap and version in broadcast
    self:Send(MSG.TABLE_OPEN, CS.minBet, CS.maxBet, CS.maxOdds, CS.bettingTimer, CS.tableCap, BJ.version)
    
    -- Use in-app messaging with game link like blackjack
    local gameLink = BJ:CreateGameLink("craps", "Craps")
    BJ:Print(gameLink .. " table opened! Min: " .. BJ:FormatGoldColored(CS.minBet) .. " | Max: " .. BJ:FormatGoldColored(CS.maxBet) .. " | Bank: " .. BJ:FormatGoldColored(CS.tableCap))
    
    -- Update chip selector for host
    if BJ.UI and BJ.UI.Craps then
        BJ.UI.Craps:UpdateChipSelector()
    end
    
    return true
end

function CM:CloseTable()
    if not CM.isHost then return false end
    
    local CS = BJ.CrapsState
    if #CS.rollHistory > 0 then
        CS:SaveToHistory()
    end
    
    -- Send receipts to all non-host players with remaining balance
    for playerName, player in pairs(CS.players) do
        if not player.isHost and player.balance > 0 then
            local startBalance = player.startBalance or player.balance
            local netChange = player.balance - startBalance
            
            -- Send receipt to this player (with "closed" flag)
            self:SendWhisper(playerName, MSG.CASH_OUT_RECEIPT, playerName, startBalance, player.balance, netChange, "closed")
            
            -- Log balance
            CS:LogBalance(playerName, player.balance, "Table closed")
            
            -- Print to host chat
            BJ:Print("|cffffd700" .. playerName .. " returned:|r " .. BJ:FormatGoldColored(player.balance))
        end
    end
    
    self:Send(MSG.TABLE_CLOSE)
    BJ:Print("|cff888888Craps table closed.|r")
    
    -- Clear saved session (successful close)
    CS:ClearSavedSession()
    
    CS:Reset()
    CM.isHost = false
    CM.currentHost = nil
    CM.tableOpen = false
    
    if BJ.UI and BJ.UI.Craps then
        BJ.UI.Craps:UpdateDisplay()
    end
    return true
end

-- Reset all game state (host only)
function CM:ResetGame()
    if not CM.isHost then return false end
    
    local CS = BJ.CrapsState
    CS:Reset()
    
    self:Send(MSG.RESET)
    BJ:Print("|cffff8800Craps game reset.|r")
    
    CM.isHost = false
    CM.currentHost = nil
    CM.tableOpen = false
    
    if BJ.UI and BJ.UI.Craps then
        BJ.UI.Craps:UpdateDisplay()
    end
    return true
end

function CM:OpenBetting()
    if not CM.isHost then return false end
    local CS = BJ.CrapsState
    CS.phase = CS.PHASE.BETTING
    CS.bettingStartTime = time()
    self:Send(MSG.BETTING_OPEN, CS.bettingTimer)
    return true
end

function CM:CloseBetting()
    if not CM.isHost then return false end
    local CS = BJ.CrapsState
    if CS.point then
        CS.phase = CS.PHASE.POINT
    else
        CS.phase = CS.PHASE.COME_OUT
    end
    CS.rollStartTime = time()
    CS.shooterWarned = false  -- Reset warning flag
    self:Send(MSG.BETTING_CLOSE)
    
    -- Start shooter timer
    self:StartShooterTimer()
    
    return true
end

-- Host assigns a shooter and starts the game
function CM:AssignShooter(playerName)
    if not CM.isHost then return false end
    local CS = BJ.CrapsState
    
    -- Set the shooter
    CS.shooterName = playerName
    
    -- Rebuild shooter order starting with selected player
    CS.shooterOrder = {}
    local sortedNames = {}
    for name, player in pairs(CS.players) do
        if not player.isHost and not player.isSpectator then
            table.insert(sortedNames, name)
        end
    end
    table.sort(sortedNames)
    
    -- Rotate so selected player is first
    local startIdx = 1
    for i, name in ipairs(sortedNames) do
        if name == playerName then
            startIdx = i
            break
        end
    end
    for i = startIdx, #sortedNames do
        table.insert(CS.shooterOrder, sortedNames[i])
    end
    for i = 1, startIdx - 1 do
        table.insert(CS.shooterOrder, sortedNames[i])
    end
    
    -- Close betting and start
    self:CloseBetting()
    self:Send(MSG.SHOOTER_CHANGE, playerName)
    
    return true
end

-- Player requests to skip their turn as shooter
function CM:RequestSkipShooter()
    local CS = BJ.CrapsState
    local myName = UnitName("player")
    
    -- Can skip as long as they haven't rolled the dice yet
    if CS.shooterName == myName and CS.shooterHasRolled then
        BJ:Print("|cffff4444Cannot skip after rolling the dice. Seven-out to pass.|r")
        return false
    end
    
    -- Send skip request to host
    self:SendWhisper(self.currentHost, MSG.SKIP_SHOOTER, myName)
    return true
end

-- Host handles skip shooter request
function CM:HandleSkipShooter(senderName, parts)
    if not CM.isHost then return end
    
    local playerName = parts[2] or senderName
    local CS = BJ.CrapsState
    
    -- Can't skip if they've already rolled
    if CS.shooterName == playerName and CS.shooterHasRolled then
        return  -- Can't skip after rolling
    end
    
    -- Remove from shooter order and add to end
    local newOrder = {}
    local skippedPlayer = nil
    for i, name in ipairs(CS.shooterOrder) do
        if name == playerName then
            skippedPlayer = name
        else
            table.insert(newOrder, name)
        end
    end
    if skippedPlayer then
        table.insert(newOrder, skippedPlayer)
    end
    CS.shooterOrder = newOrder
    
    -- If this player was next shooter, advance to next
    if CS.shooterName == playerName or not CS.shooterName then
        if #newOrder > 0 then
            CS.shooterName = newOrder[1]
            CS.shooterIndex = 1
            CS.shooterHasRolled = false  -- Reset for new shooter
            self:Send(MSG.SHOOTER_CHANGE, CS.shooterName)
            BJ:Print("|cffffd700" .. playerName .. " skipped. " .. CS.shooterName .. " is now the shooter.|r")
        end
    else
        BJ:Print("|cffffd700" .. playerName .. " will skip their next turn as shooter.|r")
    end
    
    if BJ.UI and BJ.UI.Craps then
        BJ.UI.Craps:UpdateDisplay()
    end
end

-- Shooter timer - 60 seconds to roll
CM.shooterTimerHandle = nil

function CM:StartShooterTimer()
    -- Cancel any existing timer
    if CM.shooterTimerHandle then
        CM.shooterTimerHandle:Cancel()
    end
    
    local CS = BJ.CrapsState
    
    -- Check every second
    CM.shooterTimerHandle = C_Timer.NewTicker(1, function()
        if not CM.isHost then
            CM.shooterTimerHandle:Cancel()
            return
        end
        
        -- Check if still in rolling phase
        if CS.phase ~= CS.PHASE.COME_OUT and CS.phase ~= CS.PHASE.POINT then
            CM.shooterTimerHandle:Cancel()
            return
        end
        
        local elapsed = time() - (CS.rollStartTime or time())
        local remaining = 60 - elapsed
        
        -- 10 second warning
        if remaining <= 10 and remaining > 9 and not CS.shooterWarned then
            CS.shooterWarned = true
            BJ:Print("|cffff4444" .. (CS.shooterName or "Shooter") .. " has 10 seconds to roll!|r")
            self:Send(MSG.BALANCE_UPDATE, "TIMER_WARNING", "10")
            
            -- Play airhorn sound
            if BJ.UI and BJ.UI.Lobby and BJ.UI.Lobby.PlaySound then
                BJ.UI.Lobby:PlaySound("airhorn")
            end
        end
        
        -- Time's up - force the roll using chat system
        if remaining <= 0 then
            CM.shooterTimerHandle:Cancel()
            BJ:Print("|cffff4444Time's up! Forcing roll for " .. (CS.shooterName or "shooter") .. ".|r")
            
            -- Use chat /roll 6 system - host forces roll on behalf of shooter
            CM.forceRollPending = true
            CM.forceRollDie1 = nil
            CM.forceRollDie2 = nil
            RandomRoll(1, 6)
        end
    end)
end

function CM:StopShooterTimer()
    if CM.shooterTimerHandle then
        CM.shooterTimerHandle:Cancel()
        CM.shooterTimerHandle = nil
    end
end

-- Handle system messages for host force rolls
function CM:OnForceRollMessage(rollNum)
    if not CM.forceRollPending then return false end
    
    if not CM.forceRollDie1 then
        CM.forceRollDie1 = rollNum
        -- Roll second die
        RandomRoll(1, 6)
        return true
    elseif not CM.forceRollDie2 then
        CM.forceRollDie2 = rollNum
        
        local die1 = CM.forceRollDie1
        local die2 = CM.forceRollDie2
        CM.forceRollPending = false
        CM.forceRollDie1 = nil
        CM.forceRollDie2 = nil
        
        CM:ProcessRoll(die1, die2)
        
        if BJ.UI and BJ.UI.Lobby and BJ.UI.Lobby.PlaySound then
            BJ.UI.Lobby:PlaySound("dice")
        end
        return true
    end
    return false
end

function CM:ProcessRoll(die1, die2)
    if not CM.isHost then return false end
    
    -- Stop the shooter timer
    self:StopShooterTimer()
    
    local CS = BJ.CrapsState
    
    -- Mark that shooter has rolled (can no longer skip)
    CS.shooterHasRolled = true
    
    -- Start roll cooldown (5 seconds between rolls for betting)
    CS.rollCooldown = true
    CS.rollCooldownEnd = GetTime() + 5
    
    local result, settlements = CS:ProcessRoll(die1, die2)
    if not result then return false end
    
    self:Send(MSG.ROLL_RESULT, die1, die2, result)
    
    -- Send settlements and print win/loss messages for host
    for playerName, settlement in pairs(settlements) do
        if settlement.winnings ~= 0 or #settlement.messages > 0 then
            local msgStr = table.concat(settlement.messages, ";")
            local player = CS.players[playerName]
            local newBalance = player and player.balance or 0
            self:Send(MSG.SETTLEMENT, playerName, settlement.winnings, newBalance, msgStr)
            
            -- Print win/loss message for host
            if settlement.winnings > 0 then
                BJ:Print("|cffffffff" .. playerName .. "|r |cff00ff00+" .. settlement.winnings .. "g|r (Balance: " .. newBalance .. "g)")
            elseif settlement.winnings < 0 then
                BJ:Print("|cffffffff" .. playerName .. "|r |cffff4444" .. settlement.winnings .. "g|r (Balance: " .. newBalance .. "g)")
            end
        end
    end
    
    -- Reset lock-in status for next betting round
    for name, player in pairs(CS.players) do
        if not player.isHost then
            player.lockedIn = false
        end
    end
    
    -- Return to betting phase after roll completes (with timer)
    -- Except on seven_out which clears everything
    if result ~= "seven_out" then
        CS.phase = CS.PHASE.BETTING
        self:StartBettingTimer()
    end
    
    if result == "point_established" then
        self:Send(MSG.POINT_SET, CS.point)
        BJ:Print("|cffffd700Point is " .. CS.point .. "!|r")
    elseif result == "point_hit" then
        BJ:Print("|cff00ff00Point hit! " .. CS.lastRoll.total .. "!|r")
    elseif result == "seven_out" then
        -- Clear all bets for all players on seven out (shooter change)
        for name, player in pairs(CS.players) do
            if not player.isHost then
                player.bets = CS:CreateEmptyBets()
            end
        end
        -- Reset shooterHasRolled for new shooter
        CS.shooterHasRolled = false
        -- Broadcast bet clear to all players
        self:Send(MSG.SHOOTER_CHANGE, CS.shooterName, "CLEAR")
        BJ:Print("|cffff4444Seven out!|r " .. (CS.shooterName or "Next player") .. " is the new shooter. All bets cleared.")
        -- Now start betting phase for new shooter
        CS.phase = CS.PHASE.BETTING
        self:StartBettingTimer()
    elseif result == "natural" then
        BJ:Print("|cff00ff00Natural " .. CS.lastRoll.total .. "!|r Pass Line wins!")
    elseif result == "craps" then
        BJ:Print("|cffff4444Craps " .. CS.lastRoll.total .. "!|r Pass Line loses!")
    end
    
    if BJ.Leaderboard then
        for playerName, settlement in pairs(settlements) do
            if settlement.winnings ~= 0 then
                local outcome = settlement.winnings > 0 and "win" or "lose"
                BJ.Leaderboard:RecordHandResult("craps", playerName, settlement.winnings, outcome)
            end
        end
    end
    
    -- Save session for crash recovery
    CS:SaveHostSession()
    
    if BJ.UI and BJ.UI.Craps then
        BJ.UI.Craps:OnRollResult(die1, die2, result, settlements)
    end
    
    return true, result
end

-- Start the betting timer (60 seconds max)
function CM:StartBettingTimer()
    local CS = BJ.CrapsState
    
    -- Cancel any existing timer
    if self.bettingTimerHandle then
        self.bettingTimerHandle:Cancel()
        self.bettingTimerHandle = nil
    end
    
    -- Reset lockedIn status for all players
    for name, player in pairs(CS.players) do
        player.lockedIn = false
    end
    
    CS.bettingTimeRemaining = 60
    self:Send(MSG.BETTING_PHASE, CS.bettingTimeRemaining)
    
    -- Update UI every second
    local function tickTimer()
        CS.bettingTimeRemaining = CS.bettingTimeRemaining - 1
        
        if BJ.UI and BJ.UI.Craps then
            BJ.UI.Craps:UpdateBettingTimer(CS.bettingTimeRemaining)
        end
        
        if CS.bettingTimeRemaining <= 0 then
            -- Timer expired, force close betting
            self:CloseBetting()
            self.bettingTimerHandle = nil
        else
            self.bettingTimerHandle = C_Timer.NewTimer(1, tickTimer)
        end
    end
    
    self.bettingTimerHandle = C_Timer.NewTimer(1, tickTimer)
    
    if BJ.UI and BJ.UI.Craps then
        BJ.UI.Craps:UpdateBettingTimer(CS.bettingTimeRemaining)
        BJ.UI.Craps:UpdateDisplay()
    end
end

-- Check if all players are locked in
function CM:AllPlayersLockedIn()
    local CS = BJ.CrapsState
    local playerCount = 0
    
    for name, player in pairs(CS.players) do
        if not player.isHost then
            playerCount = playerCount + 1
            if not player.lockedIn then
                return false
            end
        end
    end
    
    return playerCount > 0
end

-- PLAYER ACTIONS --

function CM:JoinTable()
    local myName = UnitName("player")
    local CS = BJ.CrapsState
    
    if not CM.tableOpen then
        BJ:Print("No craps table is open.")
        return false
    end
    
    if CS.players[myName] then
        BJ:Print("You're already at the table.")
        return false
    end
    
    if CM.isHost then
        local success, err = CS:AddPlayer(myName)
        if success then
            self:Send(MSG.PLAYER_JOIN, myName)
            BJ:Print("|cff00ff00You joined the craps table!|r")
        else
            BJ:Print("|cffff4444" .. err .. "|r")
            return false
        end
    else
        self:Send(MSG.PLAYER_JOIN, myName)
    end
    return true
end

function CM:LeaveTable()
    local myName = UnitName("player")
    local CS = BJ.CrapsState
    
    if not CS.players[myName] then return false end
    
    if CM.isHost then
        local success, err = CS:RemovePlayer(myName)
        if success then
            self:Send(MSG.PLAYER_LEAVE, myName)
        else
            BJ:Print("|cffff4444" .. err .. "|r")
            return false
        end
    else
        self:Send(MSG.PLAYER_LEAVE, myName)
    end
    return true
end

function CM:RequestBet(betType, amount, point)
    local myName = UnitName("player")
    local CS = BJ.CrapsState
    
    -- Block bets during host recovery
    if CM.hostDisconnected then
        BJ:Print("|cffff8800Game is paused - waiting for host to return.|r")
        return false
    end
    
    if CM.isHost then
        local success, err = CS:PlaceBet(myName, betType, amount, point)
        if success then
            self:Send(MSG.BET_CONFIRM, myName, betType, amount, point or "")
            if BJ.UI and BJ.UI.Craps then
                BJ.UI.Craps:UpdateDisplay()
            end
            return true
        else
            BJ:Print("|cffff4444" .. err .. "|r")
            return false
        end
    else
        self:Send(MSG.BET_REQUEST, betType, amount, point or "")
        return true
    end
end

-- Request to remove a place bet
function CM:RequestRemoveBet(betType, point)
    local myName = UnitName("player")
    local CS = BJ.CrapsState
    
    -- Block during host recovery
    if CM.hostDisconnected then
        BJ:Print("|cffff8800Game is paused - waiting for host to return.|r")
        return false
    end
    
    if CM.isHost then
        -- Host processes locally
        local success, err = CS:RemoveBet(myName, betType, point)
        if success then
            self:Send(MSG.BET_REMOVE_OK, myName, betType, point or "")
            if BJ.UI and BJ.UI.Craps then
                BJ.UI.Craps:UpdateDisplay()
            end
            return true
        else
            BJ:Print("|cffff4444" .. err .. "|r")
            return false
        end
    else
        self:Send(MSG.BET_REMOVE_REQ, betType, point or "")
        return true
    end
end

function CM:RequestRoll()
    local myName = UnitName("player")
    local CS = BJ.CrapsState
    
    -- Block rolls during host recovery
    if CM.hostDisconnected then
        BJ:Print("|cffff8800Game is paused - waiting for host to return.|r")
        return false
    end
    
    if not CS:IsShooter(myName) then
        BJ:Print("You're not the shooter.")
        return false
    end
    
    if CS.phase ~= CS.PHASE.COME_OUT and CS.phase ~= CS.PHASE.POINT and CS.phase ~= CS.PHASE.ROLLING then
        BJ:Print("Can't roll right now.")
        return false
    end
    
    CM.pendingRoll = true
    CM.rollDie1 = nil
    CM.rollDie2 = nil
    RandomRoll(1, 6)
    return true
end

-- MESSAGE HANDLERS --

function CM:HandleTableOpen(hostName, parts)
    local minBet = tonumber(parts[2]) or 100
    local maxBet = tonumber(parts[3]) or 10000
    local maxOdds = tonumber(parts[4]) or 3
    local bettingTimer = tonumber(parts[5]) or 30
    local tableCap = tonumber(parts[6]) or 100000
    local hostVersion = parts[7] or "unknown"
    
    -- Check version compatibility
    local myVersion = BJ.version or "0.0.0"
    if hostVersion ~= "unknown" and hostVersion ~= myVersion then
        -- Compare versions (simple string compare works for semantic versioning)
        if hostVersion > myVersion then
            BJ:Print("|cffff4444WARNING: Host is running Chairfaces Casino v" .. hostVersion .. " but you have v" .. myVersion .. ". Please update to join this table!|r")
        end
    end
    
    local CS = BJ.CrapsState
    CS:Reset()
    CS.phase = CS.PHASE.BETTING
    CS.hostName = hostName
    CS.hostVersion = hostVersion  -- Store host version for join check
    CS.shooterName = nil  -- Host cannot be shooter
    CS.minBet = minBet
    CS.maxBet = maxBet
    CS.maxOdds = maxOdds
    CS.bettingTimer = bettingTimer
    CS.tableCap = tableCap
    CS:AddPlayer(hostName, tableCap, true)  -- Host is the bank
    
    CM.isHost = false
    CM.currentHost = hostName
    CM.tableOpen = true
    
    local gameLink = BJ:CreateGameLink("craps", "Craps")
    BJ:Print("|cffffd700" .. hostName .. "|r opened a " .. gameLink .. " table! Min: " .. BJ:FormatGoldColored(minBet) .. " | Max: " .. BJ:FormatGoldColored(maxBet) .. " | Bank: " .. BJ:FormatGoldColored(tableCap))
    
    if BJ.UI and BJ.UI.Craps then
        BJ.UI.Craps:UpdateChipSelector()
        BJ.UI.Craps:UpdateDisplay()
    end
end

function CM:HandleTableClose(hostName, parts)
    if hostName ~= CM.currentHost then return end
    
    local CS = BJ.CrapsState
    CS:Reset()
    CM.isHost = false
    CM.currentHost = nil
    CM.tableOpen = false
    
    BJ:Print("|cff888888Craps table closed.|r")
    
    if BJ.UI and BJ.UI.Craps then
        BJ.UI.Craps:UpdateDisplay()
    end
end

function CM:HandlePlayerJoin(senderName, parts)
    local playerName = parts[2] or senderName
    local buyIn = tonumber(parts[3]) or 0
    local CS = BJ.CrapsState
    
    if CM.isHost then
        -- Check if this is a reconnecting player from restored session
        if CS.isRestoring and CS.restoredPlayers and CS.restoredPlayers[playerName] then
            local success, pendingCount = CS:HandlePlayerReconnect(playerName)
            if success then
                -- Broadcast their restored state
                local player = CS.players[playerName]
                self:Send(MSG.PLAYER_JOIN, playerName, player.balance)
                BJ:Print("|cff00ff00" .. playerName .. "|r reconnected with " .. BJ:FormatGoldColored(player.balance))
                
                -- Sync their bets
                self:SyncPlayerBets(playerName)
                
                if pendingCount == 0 then
                    BJ:Print("|cffffd700All players reconnected!|r")
                end
            end
        else
            local hadShooter = CS.shooterName ~= nil
            local success, err = CS:AddPlayer(playerName, buyIn, false)
            if success then
                self:Send(MSG.PLAYER_JOIN, playerName, buyIn)
                BJ:Print("|cff00ff00" .. playerName .. "|r joined with " .. BJ:FormatGoldColored(buyIn))
                
                -- If this was first player, they become shooter - broadcast it
                if not hadShooter and CS.shooterName then
                    self:Send(MSG.SHOOTER_CHANGE, CS.shooterName)
                    BJ:Print("|cffffd700" .. CS.shooterName .. " is the shooter.|r")
                end
            else
                self:SendWhisper(playerName, MSG.BET_REJECT, err)
            end
        end
        
        -- Save session for crash recovery
        CS:SaveHostSession()
    else
        CS:AddPlayer(playerName, buyIn, false)
    end
    
    if BJ.UI and BJ.UI.Craps then
        BJ.UI.Craps:UpdateDisplay()
    end
end

function CM:HandlePlayerLeave(senderName, parts)
    local playerName = parts[2] or senderName
    local CS = BJ.CrapsState
    CS:RemovePlayer(playerName)
    
    -- Save session for crash recovery (host only)
    if CM.isHost then
        CS:SaveHostSession()
    end
    
    if BJ.UI and BJ.UI.Craps then
        BJ.UI.Craps:UpdateDisplay()
    end
end

function CM:HandleBetRequest(senderName, parts)
    if not CM.isHost then return end
    
    local betType = parts[2]
    local amount = tonumber(parts[3]) or 0
    local point = parts[4] ~= "" and tonumber(parts[4]) or nil
    
    local CS = BJ.CrapsState
    local success, err = CS:PlaceBet(senderName, betType, amount, point)
    
    if success then
        -- Only confirm to the betting player - don't broadcast bets yet
        -- Bets will be synced when player locks in or host forces roll
        self:SendWhisper(senderName, MSG.BET_CONFIRM, betType, amount, point or "")
        
        -- Save session for crash recovery
        CS:SaveHostSession()
    else
        self:SendWhisper(senderName, MSG.BET_REJECT, err)
    end
end

-- Host handles bet remove request
function CM:HandleBetRemoveRequest(senderName, parts)
    if not CM.isHost then return end
    
    local betType = parts[2]
    local point = parts[3] ~= "" and tonumber(parts[3]) or nil
    
    local CS = BJ.CrapsState
    local success, err = CS:RemoveBet(senderName, betType, point)
    
    if success then
        self:SendWhisper(senderName, MSG.BET_REMOVE_OK, betType, point or "")
        -- Save session for crash recovery
        CS:SaveHostSession()
    else
        self:SendWhisper(senderName, MSG.BET_REJECT, err)
    end
end

-- Player receives bet remove confirmation
function CM:HandleBetRemoveConfirm(hostName, parts)
    if hostName ~= CM.currentHost then return end
    
    local betType = parts[2]
    local point = parts[3] ~= "" and tonumber(parts[3]) or nil
    
    local CS = BJ.CrapsState
    local myName = UnitName("player")
    
    -- Apply removal locally
    CS:RemoveBet(myName, betType, point)
    
    BJ:Print("|cff00ff00Bet removed: " .. betType .. (point and (" " .. point) or "") .. "|r")
    
    if BJ.UI and BJ.UI.Craps then
        BJ.UI.Craps:UpdateDisplay()
    end
end

function CM:HandleBetConfirm(hostName, parts)
    if hostName ~= CM.currentHost then return end
    
    local betType = parts[2]
    local amount = tonumber(parts[3]) or 0
    local point = parts[4] ~= "" and tonumber(parts[4]) or nil
    
    local CS = BJ.CrapsState
    local myName = UnitName("player")
    
    -- This is our own bet confirmation
    if not CS.players[myName] then
        CS:AddPlayer(myName)
    end
    CS:PlaceBet(myName, betType, amount, point)
    
    -- Mark that we added bets this round
    if CS.players[myName] then
        CS.players[myName].betsAddedThisRound = true
    end
    
    BJ:Print("|cff00ff00Bet placed: " .. amount .. "g on " .. betType .. "|r")
    
    if BJ.UI and BJ.UI.Craps then
        BJ.UI.Craps:UpdateDisplay()
    end
end

-- Handle bet sync broadcast (updates other players' view of bets)
-- New format: BET_SYNC, playerName, balance, "betType:amount,betType:amount,..."
function CM:HandleBetSync(hostName, parts)
    if hostName ~= CM.currentHost then return end
    
    local playerName = parts[2]
    local newBalance = tonumber(parts[3]) or 0
    local betStr = parts[4] or ""
    
    local CS = BJ.CrapsState
    local myName = UnitName("player")
    
    -- Don't re-process our own bets
    if playerName == myName then return end
    
    -- Ensure player exists
    if not CS.players[playerName] then
        return
    end
    
    local player = CS.players[playerName]
    
    -- Reset all bets for this player first
    player.bets = CS:CreateEmptyBets()
    player.balance = newBalance
    
    -- Parse and apply all bets
    if betStr ~= "" then
        for betPair in betStr:gmatch("[^,]+") do
            local betType, amount = betPair:match("([^:]+):(%d+)")
            if betType and amount then
                amount = tonumber(amount)
                
                -- Handle place bets
                local placeNum = betType:match("^place(%d+)$")
                if placeNum then
                    player.bets.place[tonumber(placeNum)] = amount
                -- Handle come point bets (moved from Come)
                elseif betType:match("^comePointOdds(%d+)$") then
                    local point = tonumber(betType:match("^comePointOdds(%d+)$"))
                    if not player.bets.comePoints[point] then
                        player.bets.comePoints[point] = {base = 0, odds = 0}
                    end
                    player.bets.comePoints[point].odds = amount
                elseif betType:match("^comePoint(%d+)$") then
                    local point = tonumber(betType:match("^comePoint(%d+)$"))
                    if not player.bets.comePoints[point] then
                        player.bets.comePoints[point] = {base = 0, odds = 0}
                    end
                    player.bets.comePoints[point].base = amount
                -- Handle don't come point bets (moved from Don't Come)
                elseif betType:match("^dontComePointOdds(%d+)$") then
                    local point = tonumber(betType:match("^dontComePointOdds(%d+)$"))
                    if not player.bets.dontComePoints[point] then
                        player.bets.dontComePoints[point] = {base = 0, odds = 0}
                    end
                    player.bets.dontComePoints[point].odds = amount
                elseif betType:match("^dontComePoint(%d+)$") then
                    local point = tonumber(betType:match("^dontComePoint(%d+)$"))
                    if not player.bets.dontComePoints[point] then
                        player.bets.dontComePoints[point] = {base = 0, odds = 0}
                    end
                    player.bets.dontComePoints[point].base = amount
                elseif player.bets[betType] ~= nil then
                    player.bets[betType] = amount
                end
            end
        end
    end
    
    BJ:Debug("Synced bets for " .. playerName .. ": " .. betStr)
    
    if BJ.UI and BJ.UI.Craps then
        BJ.UI.Craps:UpdateDisplay()
    end
end

function CM:HandleBetReject(hostName, parts)
    BJ:Print("|cffff4444" .. (parts[2] or "Bet rejected") .. "|r")
end

function CM:HandleBettingOpen(hostName, parts)
    if hostName ~= CM.currentHost then return end
    local CS = BJ.CrapsState
    CS.phase = CS.PHASE.BETTING
    CS.bettingTimer = tonumber(parts[2]) or 30
    CS.bettingStartTime = time()
    
    -- Reset lock-in and betsAddedThisRound for local player
    local myName = UnitName("player")
    if CS.players[myName] then
        CS.players[myName].lockedIn = false
        CS.players[myName].betsAddedThisRound = false
    end
    
    if BJ.UI and BJ.UI.Craps then
        BJ.UI.Craps:UpdateDisplay()
    end
end

function CM:HandleBettingClose(hostName, parts)
    if hostName ~= CM.currentHost then return end
    local CS = BJ.CrapsState
    if CS.point then
        CS.phase = CS.PHASE.POINT
    else
        CS.phase = CS.PHASE.COME_OUT
    end
    CS.rollStartTime = time()
    
    if BJ.UI and BJ.UI.Craps then
        BJ.UI.Craps:UpdateDisplay()
    end
end

-- Client receives betting phase notification
function CM:HandleBettingPhase(hostName, parts)
    if hostName ~= CM.currentHost then return end
    
    local CS = BJ.CrapsState
    local timeRemaining = tonumber(parts[2]) or 60
    
    CS.phase = CS.PHASE.BETTING
    CS.bettingTimeRemaining = timeRemaining
    
    -- Reset lock-in and betsAddedThisRound for ALL players (so checkmarks clear)
    for name, player in pairs(CS.players) do
        player.lockedIn = false
        player.betsAddedThisRound = false
    end
    
    -- Start client-side timer countdown
    if self.clientTimerHandle then
        self.clientTimerHandle:Cancel()
        self.clientTimerHandle = nil
    end
    
    local function tickClientTimer()
        CS.bettingTimeRemaining = CS.bettingTimeRemaining - 1
        
        if BJ.UI and BJ.UI.Craps then
            BJ.UI.Craps:UpdateBettingTimer(CS.bettingTimeRemaining)
        end
        
        if CS.bettingTimeRemaining <= 0 then
            self.clientTimerHandle = nil
            -- Timer expired, hide timer display
            if BJ.UI and BJ.UI.Craps then
                BJ.UI.Craps:UpdateBettingTimer(0)
            end
        else
            self.clientTimerHandle = C_Timer.NewTimer(1, tickClientTimer)
        end
    end
    
    self.clientTimerHandle = C_Timer.NewTimer(1, tickClientTimer)
    
    if BJ.UI and BJ.UI.Craps then
        BJ.UI.Craps:UpdateBettingTimer(timeRemaining)
        BJ.UI.Craps:UpdateDisplay()
    end
end

function CM:HandleRollResult(hostName, parts)
    if hostName ~= CM.currentHost then return end
    
    local die1 = tonumber(parts[2]) or 0
    local die2 = tonumber(parts[3]) or 0
    local result = parts[4]
    
    local CS = BJ.CrapsState
    local total = die1 + die2
    local isHard = (die1 == die2)
    
    CS.lastRoll = {
        die1 = die1,
        die2 = die2,
        total = total,
        isHard = isHard,
        timestamp = time()
    }
    
    table.insert(CS.rollHistory, 1, CS.lastRoll)
    while #CS.rollHistory > 20 do
        table.remove(CS.rollHistory)
    end
    
    -- Process game state changes based on result
    if result == "point_established" then
        CS.point = total
        CS.phase = CS.PHASE.POINT
        BJ:Print("|cffffd700Point is " .. total .. "!|r")
    elseif result == "seven_out" then
        CS.point = nil
        CS.phase = CS.PHASE.COME_OUT
        BJ:Print("|cffff4444Seven out!|r")
    elseif result == "point_hit" then
        BJ:Print("|cff00ff00Point hit! " .. total .. "!|r")
        CS.point = nil
        CS.phase = CS.PHASE.COME_OUT
    elseif result == "natural" then
        BJ:Print("|cff00ff00Natural " .. total .. "!|r Pass Line wins!")
        CS.phase = CS.PHASE.COME_OUT
    elseif result == "craps" then
        BJ:Print("|cffff4444Craps " .. total .. "!|r Pass Line loses!")
        CS.phase = CS.PHASE.COME_OUT
    end
    
    -- Process bets locally to clear losing bets and keep state in sync
    -- The actual balance changes come from SETTLEMENT messages
    CS:ProcessRollLocal(result, total, isHard)
    
    if BJ.UI and BJ.UI.Craps then
        BJ.UI.Craps:OnRollResult(die1, die2, result, nil)
    end
end

function CM:HandlePointSet(hostName, parts)
    if hostName ~= CM.currentHost then return end
    local CS = BJ.CrapsState
    CS.point = tonumber(parts[2])
    CS.phase = CS.PHASE.POINT
    
    if BJ.UI and BJ.UI.Craps then
        BJ.UI.Craps:UpdateDisplay()
    end
end

function CM:HandleShooterChange(hostName, parts)
    if hostName ~= CM.currentHost then return end
    local CS = BJ.CrapsState
    CS.shooterName = parts[2]
    local clearBets = parts[3] == "CLEAR"
    
    local myName = UnitName("player")
    if CS.shooterName == myName then
        BJ:Print("|cffffd700You are now the shooter!|r")
    end
    
    -- Clear all bets for all players on shooter change
    if clearBets then
        for name, player in pairs(CS.players) do
            if not player.isHost then
                player.bets = CS:CreateEmptyBets()
            end
        end
        BJ:Print("|cffff8800All bets cleared for new shooter.|r")
    end
    
    if BJ.UI and BJ.UI.Craps then
        BJ.UI.Craps:UpdateDisplay()
    end
end

function CM:HandleSettlement(hostName, parts)
    if hostName ~= CM.currentHost then return end
    
    local playerName = parts[2]
    local winnings = tonumber(parts[3]) or 0
    local newBalance = tonumber(parts[4])  -- Host now sends new balance
    local msgStr = parts[5] or ""  -- Bet breakdown messages
    
    local CS = BJ.CrapsState
    local player = CS.players[playerName]
    if player then
        player.sessionBalance = player.sessionBalance + winnings
        -- Update actual balance if provided
        if newBalance then
            player.balance = newBalance
        end
        -- Reset locked in status for next round
        player.lockedIn = false
    end
    
    -- Parse breakdown messages
    local messages = {}
    if msgStr and msgStr ~= "" then
        for msg in string.gmatch(msgStr, "[^;]+") do
            table.insert(messages, msg)
        end
    end
    
    -- Update log entry with this settlement
    if BJ.UI and BJ.UI.Craps then
        BJ.UI.Craps:UpdateLogEntryWithSettlement(playerName, winnings, messages)
    end
    
    local myName = UnitName("player")
    if playerName == myName then
        -- My own settlement - show breakdown
        if #messages > 0 then
            for _, msg in ipairs(messages) do
                BJ:Print("  |cffaaaaaa" .. msg .. "|r")
            end
        end
        
        if winnings > 0 then
            BJ:Print("|cff00ff00Total: +" .. BJ:FormatGold(winnings) .. "|r")
            -- Show floating combat text
            self:ShowFloatingWinnings(winnings, true)
        elseif winnings < 0 then
            BJ:Print("|cffff4444Total: -" .. BJ:FormatGold(math.abs(winnings)) .. "|r")
            -- Show floating combat text
            self:ShowFloatingWinnings(winnings, false)
        end
        if BJ.Leaderboard then
            BJ.Leaderboard:UpdateMyStatsFromSettlement("craps")
        end
    else
        -- Other player's settlement - show with their name and breakdown
        if #messages > 0 then
            BJ:Print("|cffffffff" .. playerName .. ":|r")
            for _, msg in ipairs(messages) do
                BJ:Print("  |cffaaaaaa" .. msg .. "|r")
            end
        end
        
        if winnings > 0 then
            BJ:Print("|cffffffff" .. playerName .. "|r |cff00ff00+" .. BJ:FormatGold(winnings) .. "|r")
        elseif winnings < 0 then
            BJ:Print("|cffffffff" .. playerName .. "|r |cffff4444-" .. BJ:FormatGold(math.abs(winnings)) .. "|r")
        end
    end
    
    if BJ.UI and BJ.UI.Craps then
        BJ.UI.Craps:UpdateDisplay()
    end
end

-- Show floating combat text for winnings/losses
function CM:ShowFloatingWinnings(amount, isWin)
    local text, r, g, b
    if isWin then
        text = "+" .. BJ:FormatGold(amount)
        r, g, b = 0, 1, 0  -- Green
    else
        text = "-" .. BJ:FormatGold(math.abs(amount))
        r, g, b = 1, 0.3, 0.3  -- Red
    end
    
    -- Try to use combat floating text
    if CombatText_AddMessage then
        -- Retail WoW
        CombatText_AddMessage(text, COMBAT_TEXT_SCROLL_FUNCTION, r, g, b, "crit", nil)
    elseif SHOW_COMBAT_TEXT == "1" then
        -- Try default combat text
        CombatTextSetActiveUnit("player")
        -- Fall back to error frame if nothing else works
        if UIErrorsFrame then
            UIErrorsFrame:AddMessage(text, r, g, b)
        end
    else
        -- Fallback - show in UIErrorsFrame
        if UIErrorsFrame then
            UIErrorsFrame:AddMessage(text, r, g, b)
        end
    end
end

function CM:HandleStateSync(hostName, parts)
    if hostName ~= CM.currentHost then return end
    local CS = BJ.CrapsState
    CS.phase = parts[2] or CS.PHASE.IDLE
    CS.point = parts[3] ~= "" and tonumber(parts[3]) or nil
    -- Don't default to hostName - shooter must be explicitly assigned
    CS.shooterName = (parts[4] and parts[4] ~= "") and parts[4] or nil
    
    if BJ.UI and BJ.UI.Craps then
        BJ.UI.Craps:UpdateDisplay()
    end
end

function CM:HandleHostTransfer(senderName, parts)
    local newHost = parts[2]
    local CS = BJ.CrapsState
    local myName = UnitName("player")
    
    CS.hostName = newHost
    CM.currentHost = newHost
    
    if newHost == myName then
        CM.isHost = true
        BJ:Print("|cff00ff00You are now the craps host.|r")
    else
        CM.isHost = false
        BJ:Print("|cffffd700" .. newHost .. " is now the craps host.|r")
    end
    
    if BJ.UI and BJ.UI.Craps then
        BJ.UI.Craps:UpdateDisplay()
    end
end

function CM:HandleGameVoided(hostName, parts)
    BJ:Print("|cffff4444Craps voided: " .. (parts[2] or "Game voided") .. "|r")
    
    -- Cancel local timer
    if CM.localRecoveryTimer then
        CM.localRecoveryTimer:Cancel()
        CM.localRecoveryTimer = nil
    end
    
    -- Close recovery popup
    self:CloseRecoveryPopup()
    
    local CS = BJ.CrapsState
    CS:Reset()
    CM.isHost = false
    CM.currentHost = nil
    CM.tableOpen = false
    CM.hostDisconnected = false
    CM.originalHost = nil
    CM.temporaryHost = nil
    CM.recoveryStartTime = nil
    
    if BJ.UI and BJ.UI.Craps then
        BJ.UI.Craps:OnGameVoided(parts[2])
    end
end

-- HONOR LEDGER HANDLERS --

-- Player sends join request with buy-in amount
function CM:RequestJoin(buyIn)
    local myName = UnitName("player")
    local CS = BJ.CrapsState
    
    if CS.players[myName] then
        BJ:Print("|cffff4444You are already at the table.|r")
        return false
    end
    
    local amount = tonumber(buyIn)
    if not amount or amount < 1 or amount > 100000 then
        BJ:Print("|cffff4444Buy-in must be between 1 and 100,000.|r")
        return false
    end
    
    -- Track our own pending request locally
    local CS = BJ.CrapsState
    local myName = UnitName("player")
    CS.pendingJoins = CS.pendingJoins or {}
    CS.pendingJoins[myName] = { buyIn = amount, time = time() }
    
    -- Check version before sending
    local myVersion = BJ.version or "0.0.0"
    local hostVersion = CS.hostVersion or "unknown"
    if hostVersion ~= "unknown" and hostVersion > myVersion then
        BJ:Print("|cffff4444Cannot join: Host is running v" .. hostVersion .. " but you have v" .. myVersion .. ". Please update your addon!|r")
        return false
    end
    
    self:Send(MSG.JOIN_REQUEST, amount, BJ.version)
    BJ:Print("|cffffd700Requesting to join with " .. amount .. " chips...|r")
    
    -- Update UI to show WAIT
    if BJ.UI and BJ.UI.Craps then
        BJ.UI.Craps:UpdateDisplay()
    end
    
    return true
end

-- Host receives join request
function CM:HandleJoinRequest(senderName, parts)
    if not CM.isHost then return end
    
    local buyIn = tonumber(parts[2]) or 0
    local playerVersion = parts[3] or "unknown"
    local CS = BJ.CrapsState
    
    -- Check version compatibility
    local myVersion = BJ.version or "0.0.0"
    if playerVersion == "unknown" or playerVersion < myVersion then
        -- Player has older or unknown version
        local reason = "Version mismatch: You have v" .. (playerVersion == "unknown" and "old" or playerVersion) .. ", host requires v" .. myVersion .. ". Please update!"
        self:SendWhisper(senderName, MSG.JOIN_DENY, reason)
        BJ:Print("|cffff4444" .. senderName .. " denied: outdated version (" .. playerVersion .. ")|r")
        return
    end
    
    -- Check if this is a reconnecting player from restored session
    if CS.isRestoring and CS.restoredPlayers and CS.restoredPlayers[senderName] then
        local success, pendingCount = CS:HandlePlayerReconnect(senderName)
        if success then
            local player = CS.players[senderName]
            -- Notify the player they've been approved with their RESTORED balance
            self:SendWhisper(senderName, MSG.JOIN_APPROVE, player.balance)
            -- Broadcast to all that player joined with restored balance
            self:Send(MSG.PLAYER_JOIN, senderName, player.balance)
            BJ:Print("|cff00ff00" .. senderName .. "|r reconnected with " .. BJ:FormatGoldColored(player.balance))
            
            -- First non-host player becomes the shooter
            if not CS.shooterName then
                CS.shooterName = senderName
                self:Send(MSG.SHOOTER_CHANGE, senderName)
            end
            
            -- Save session
            CS:SaveHostSession()
            
            if pendingCount == 0 then
                BJ:Print("|cffffd700All players reconnected!|r")
                CS:FinalizeRestoration()
                -- Explicitly hide the panel
                if BJ.UI and BJ.UI.Craps and BJ.UI.Craps.pendingReconnectsPanel then
                    BJ.UI.Craps.pendingReconnectsPanel:Hide()
                end
                -- Start the betting phase
                if CS.shooterName then
                    self:Send(MSG.BETTING_PHASE, CS.bettingTimer or 30)
                    BJ:Print("|cffffd700Betting phase started! " .. (CS.bettingTimer or 30) .. " seconds to place bets.|r")
                end
            end
            
            -- Update UI
            if BJ.UI and BJ.UI.Craps then
                BJ.UI.Craps:UpdatePendingReconnectsPanel()
                BJ.UI.Craps:UpdateDisplay()
            end
        end
        return
    end
    
    local success, err = CS:RequestJoin(senderName, buyIn)
    if success then
        BJ:Print("|cffffd700" .. senderName .. " wants to join with " .. buyIn .. " chips.|r")
        -- Update UI to show pending request
        if BJ.UI and BJ.UI.Craps then
            BJ.UI.Craps:UpdatePendingJoins()
        end
    else
        -- Auto-deny if request failed
        self:SendWhisper(senderName, MSG.JOIN_DENY, err or "Request failed")
    end
end

-- Host approves a join request
function CM:ApproveJoin(playerName)
    if not CM.isHost then return false end
    
    local CS = BJ.CrapsState
    local request = CS.pendingJoins[playerName]
    if not request then
        BJ:Print("|cffff4444No pending request from " .. playerName .. "|r")
        return false
    end
    
    local success, err = CS:ApproveJoin(playerName)
    if success then
        -- First non-host player becomes the shooter
        if not CS.shooterName then
            CS.shooterName = playerName
            self:Send(MSG.SHOOTER_CHANGE, playerName)
        end
        
        -- Notify the player they've been approved
        self:SendWhisper(playerName, MSG.JOIN_APPROVE, request.buyIn)
        -- Broadcast to all that player joined
        self:Send(MSG.PLAYER_JOIN, playerName, request.buyIn)
        BJ:Print("|cff00ff00" .. playerName .. "|r joined with " .. BJ:FormatGoldColored(request.buyIn))
        
        if BJ.UI and BJ.UI.Craps then
            BJ.UI.Craps:UpdateDisplay()
        end
        return true
    else
        BJ:Print("|cffff4444Failed to approve: " .. (err or "Unknown error") .. "|r")
        return false
    end
end

-- Host denies a join request
function CM:DenyJoin(playerName)
    if not CM.isHost then return false end
    
    local CS = BJ.CrapsState
    local success = CS:DenyJoin(playerName)
    if success then
        self:SendWhisper(playerName, MSG.JOIN_DENY, "Request denied by host")
        BJ:Print("|cffff8800Denied join request from " .. playerName .. "|r")
        
        if BJ.UI and BJ.UI.Craps then
            BJ.UI.Craps:UpdatePendingJoins()
        end
        return true
    end
    return false
end

-- Player receives approval
function CM:HandleJoinApprove(hostName, parts)
    if hostName ~= CM.currentHost then return end
    
    local buyIn = tonumber(parts[2]) or 0
    local myName = UnitName("player")
    local CS = BJ.CrapsState
    
    -- Clear pending request
    if CS.pendingJoins then
        CS.pendingJoins[myName] = nil
    end
    
    -- Add self to local state
    CS:AddPlayer(myName, buyIn, false)
    
    BJ:Print("|cff00ff00Joined the table with " .. buyIn .. " chips!|r")
    
    if BJ.UI and BJ.UI.Craps then
        BJ.UI.Craps:UpdateDisplay()
    end
end

-- Player receives denial
function CM:HandleJoinDeny(hostName, parts)
    if hostName ~= CM.currentHost then return end
    
    local myName = UnitName("player")
    local CS = BJ.CrapsState
    
    -- Clear pending request
    if CS.pendingJoins then
        CS.pendingJoins[myName] = nil
    end
    
    local reason = parts[2] or "Request denied"
    BJ:Print("|cffff4444Join denied: " .. reason .. "|r")
    
    if BJ.UI and BJ.UI.Craps then
        BJ.UI.Craps:UpdateDisplay()
    end
end

-- Handle player join broadcast (updates everyone's state)
function CM:HandlePlayerJoinWithBuyIn(senderName, parts)
    if senderName ~= CM.currentHost then return end
    
    local playerName = parts[2]
    local buyIn = tonumber(parts[3]) or 0
    local myName = UnitName("player")
    
    -- Don't re-add ourselves
    if playerName == myName then return end
    
    local CS = BJ.CrapsState
    if not CS.players[playerName] then
        CS:AddPlayer(playerName, buyIn, false)
    end
    
    if BJ.UI and BJ.UI.Craps then
        BJ.UI.Craps:UpdateDisplay()
    end
end

-- Balance update broadcast
function CM:HandleBalanceUpdate(hostName, parts)
    if hostName ~= CM.currentHost then return end
    
    local playerName = parts[2]
    local newBalance = parts[3]
    
    -- Handle timer warning specially
    if playerName == "TIMER_WARNING" then
        local seconds = tonumber(newBalance) or 10
        local CS = BJ.CrapsState
        BJ:Print("|cffff4444" .. (CS.shooterName or "Shooter") .. " has " .. seconds .. " seconds to roll!|r")
        
        -- Play airhorn sound on all clients
        if BJ.UI and BJ.UI.Lobby and BJ.UI.Lobby.PlaySound then
            BJ.UI.Lobby:PlaySound("airhorn")
        end
        return
    end
    
    local CS = BJ.CrapsState
    local player = CS.players[playerName]
    if player then
        player.balance = tonumber(newBalance) or 0
    end
    
    local myName = UnitName("player")
    if playerName == myName and BJ.UI and BJ.UI.Craps then
        BJ.UI.Craps:UpdateDisplay()
    end
end

-- Player requests to cash out
function CM:RequestCashOut()
    local myName = UnitName("player")
    local CS = BJ.CrapsState
    
    if not CS.players[myName] then
        BJ:Print("|cffff4444You are not at the table.|r")
        return false
    end
    
    -- Check if player has active bets
    local totalBets = CS:GetPlayerTotalBets(myName)
    if totalBets > 0 then
        BJ:Print("|cffff4444Cannot cash out with active bets.|r")
        return false
    end
    
    self:Send(MSG.CASH_OUT)
    BJ:Print("|cffffd700Requesting cash out...|r")
    return true
end

-- Host handles cash out request
function CM:HandleCashOut(senderName, parts)
    if not CM.isHost then return end
    
    local CS = BJ.CrapsState
    local player = CS.players[senderName]
    if not player then return end
    
    -- Check for active bets
    local totalBets = CS:GetPlayerTotalBets(senderName)
    if totalBets > 0 then
        self:SendWhisper(senderName, MSG.CASH_OUT_RECEIPT, "DENIED", "Active bets")
        return
    end
    
    -- If this player is the shooter, pass to next player first
    if CS.shooterName == senderName then
        CS:PassDice()
        if CS.shooterName and CS.shooterName ~= senderName then
            self:Send(MSG.SHOOTER_CHANGE, CS.shooterName)
            BJ:Print("|cffffd700Dice passed to " .. CS.shooterName .. "|r")
        end
    end
    
    -- Generate receipt
    local receipt = CS:GenerateCashOutReceipt(senderName)
    if receipt then
        -- Send receipt to player
        self:SendWhisper(senderName, MSG.CASH_OUT_RECEIPT, "OK", 
            receipt.startBalance, receipt.endBalance, receipt.netChange)
        
        -- Remove player from table
        CS:RemovePlayer(senderName)
        
        -- Broadcast player left
        self:Send(MSG.PLAYER_LEAVE, senderName, receipt.endBalance)
        local netColor = receipt.netChange >= 0 and "00ff00" or "ff4444"
        BJ:Print("|cffffffff" .. senderName .. "|r cashed out with |cffffd700" .. receipt.endBalance .. "g|r (|cff" .. netColor .. receipt.netText .. "|r)")
        
        if BJ.UI and BJ.UI.Craps then
            BJ.UI.Craps:UpdateDisplay()
        end
    end
end

-- Player receives cash out receipt
function CM:HandleCashOutReceipt(hostName, parts)
    if hostName ~= CM.currentHost then return end
    
    local status = parts[2]
    if status == "DENIED" then
        BJ:Print("|cffff4444Cash out denied: " .. (parts[3] or "Unknown reason") .. "|r")
        return
    end
    
    local startBalance = tonumber(parts[3]) or 0
    local endBalance = tonumber(parts[4]) or 0
    local netChange = tonumber(parts[5]) or 0
    
    -- Show receipt popup window
    if BJ.UI and BJ.UI.Craps then
        BJ.UI.Craps:ShowReceiptPopup(startBalance, endBalance, netChange)
    end
    
    -- Remove self from local state
    local myName = UnitName("player")
    local CS = BJ.CrapsState
    CS.players[myName] = nil
    
    -- Remove from shooter order
    for i, name in ipairs(CS.shooterOrder) do
        if name == myName then
            table.remove(CS.shooterOrder, i)
            break
        end
    end
    
    if BJ.UI and BJ.UI.Craps then
        BJ.UI.Craps:UpdateDisplay()
    end
end

-- Player locks in their bets
function CM:LockIn()
    local myName = UnitName("player")
    local CS = BJ.CrapsState
    
    if not CS.players[myName] then
        return false
    end
    
    -- Mark locally as locked in
    CS.players[myName].lockedIn = true
    
    self:Send(MSG.LOCK_IN)
    return true
end

-- Host handles lock in
function CM:HandleLockIn(senderName, parts)
    local CS = BJ.CrapsState
    local myName = UnitName("player")
    
    -- Determine which player locked in
    -- If parts[2] exists, this is a broadcast from host about another player's lock-in
    -- Otherwise, it's a direct lock-in from the sender
    local playerName = parts[2] or senderName
    
    -- Only lock the specific player, not others
    local player = CS.players[playerName]
    if player then
        player.lockedIn = true
        BJ:Debug(playerName .. " locked in")
        
        -- Play chips sound only if player added bets this round
        if player.betsAddedThisRound and BJ.UI and BJ.UI.Craps and BJ.UI.Craps.PlayChipsSound then
            BJ.UI.Craps:PlayChipsSound()
        end
        
        -- If we're the host processing the original lock-in (not a broadcast), handle it
        if CM.isHost and not parts[2] then
            -- Broadcast this player's full bet state to all players
            self:BroadcastPlayerBets(senderName)
            
            -- Broadcast lock-in status to other players
            self:Send(MSG.LOCK_IN, senderName)
            
            -- Check if all non-host players are now locked in
            if self:AllPlayersLockedIn() then
                -- Cancel the betting timer
                if self.bettingTimerHandle then
                    self.bettingTimerHandle:Cancel()
                    self.bettingTimerHandle = nil
                end
                
                if CS.shooterName then
                    BJ:Print("|cff00ff00All players locked in! Roll is now available.|r")
                    -- Close betting immediately
                    self:CloseBetting()
                else
                    BJ:Print("|cffffd700All players locked in! Waiting for shooter assignment.|r")
                end
            end
        end
        
        if BJ.UI and BJ.UI.Craps then
            BJ.UI.Craps:UpdateDisplay()
        end
    end
end

-- Broadcast a player's full bet state to all players
function CM:BroadcastPlayerBets(playerName)
    local CS = BJ.CrapsState
    local player = CS.players[playerName]
    if not player then return end
    
    local bets = player.bets
    
    -- Serialize all non-zero bets
    local betData = {}
    if bets.passLine > 0 then betData.passLine = bets.passLine end
    if bets.passLineOdds > 0 then betData.passLineOdds = bets.passLineOdds end
    if bets.dontPass > 0 then betData.dontPass = bets.dontPass end
    if bets.dontPassOdds > 0 then betData.dontPassOdds = bets.dontPassOdds end
    if bets.come > 0 then betData.come = bets.come end
    if bets.dontCome > 0 then betData.dontCome = bets.dontCome end
    if bets.field > 0 then betData.field = bets.field end
    if bets.any7 > 0 then betData.any7 = bets.any7 end
    if bets.anyCraps > 0 then betData.anyCraps = bets.anyCraps end
    if bets.craps2 > 0 then betData.craps2 = bets.craps2 end
    if bets.craps3 > 0 then betData.craps3 = bets.craps3 end
    if bets.craps12 > 0 then betData.craps12 = bets.craps12 end
    if bets.yo11 > 0 then betData.yo11 = bets.yo11 end
    if bets.hard4 > 0 then betData.hard4 = bets.hard4 end
    if bets.hard6 > 0 then betData.hard6 = bets.hard6 end
    if bets.hard8 > 0 then betData.hard8 = bets.hard8 end
    if bets.hard10 > 0 then betData.hard10 = bets.hard10 end
    if bets.big6 > 0 then betData.big6 = bets.big6 end
    if bets.big8 > 0 then betData.big8 = bets.big8 end
    
    -- Place bets
    for point, amount in pairs(bets.place or {}) do
        if amount > 0 then
            betData["place" .. point] = amount
        end
    end
    
    -- Come point bets (bets that moved from Come to a point number)
    for point, comeBet in pairs(bets.comePoints or {}) do
        if comeBet.base > 0 then
            betData["comePoint" .. point] = comeBet.base
        end
        if comeBet.odds > 0 then
            betData["comePointOdds" .. point] = comeBet.odds
        end
    end
    
    -- Don't Come point bets (bets that moved from Don't Come to a point number)
    for point, dcBet in pairs(bets.dontComePoints or {}) do
        if dcBet.base > 0 then
            betData["dontComePoint" .. point] = dcBet.base
        end
        if dcBet.odds > 0 then
            betData["dontComePointOdds" .. point] = dcBet.odds
        end
    end
    
    -- Serialize to string
    local betStr = ""
    for betType, amount in pairs(betData) do
        if betStr ~= "" then betStr = betStr .. "," end
        betStr = betStr .. betType .. ":" .. amount
    end
    
    if betStr ~= "" then
        self:Send(MSG.BET_SYNC, playerName, player.balance, betStr)
    end
end

-- Host forces roll - locks all players and closes betting
function CM:ForceRollNow()
    if not CM.isHost then return false end
    
    local CS = BJ.CrapsState
    
    if CS.phase ~= CS.PHASE.BETTING then
        BJ:Print("|cffff4444Can only force roll during betting phase.|r")
        return false
    end
    
    -- Lock all players who aren't already locked and broadcast their bets
    local lockedCount = 0
    for name, player in pairs(CS.players) do
        if not player.isHost then
            if not player.lockedIn then
                player.lockedIn = true
                lockedCount = lockedCount + 1
            end
            -- Broadcast all players' bets (even if they were already locked)
            self:BroadcastPlayerBets(name)
        end
    end
    
    if lockedCount > 0 then
        BJ:Print("|cffff8800Forced lock on " .. lockedCount .. " player(s).|r")
    end
    
    -- Broadcast the force roll
    self:Send(MSG.BETTING_CLOSE, "FORCED")
    
    -- Close betting
    self:CloseBetting()
    
    BJ:Print("|cff00ff00Betting closed. Ready to roll!|r")
    
    return true
end

-- CASH OUT SYSTEM --

-- Player requests to cash out
function CM:RequestCashOut()
    local myName = UnitName("player")
    local CS = BJ.CrapsState
    
    if CM.isHost then
        return false
    end
    
    local player = CS.players[myName]
    if not player then
        return false
    end
    
    self:Send(MSG.CASH_OUT, myName)
    return true
end

-- Host handles cash out request
function CM:HandleCashOut(senderName, parts)
    if not CM.isHost then return end
    
    local playerName = parts[2] or senderName
    local CS = BJ.CrapsState
    local player = CS.players[playerName]
    
    if not player then return end
    
    -- Calculate net win/loss
    local startBalance = player.startBalance or 0
    local endBalance = player.balance or 0
    local netWinLoss = endBalance - startBalance
    
    -- Send receipt to player
    self:Send(MSG.CASH_OUT_RECEIPT, playerName, startBalance, endBalance, netWinLoss)
    
    -- Show receipt popup for host
    if BJ.UI and BJ.UI.Craps then
        BJ.UI.Craps:ShowReceiptPopup(playerName, startBalance, endBalance, netWinLoss)
    end
    
    -- Also print to chat log
    BJ:Print("|cffffd700" .. playerName .. " cashed out:|r " .. BJ:FormatGoldColored(endBalance))
    
    -- Remove player from table
    CS:RemovePlayer(playerName)
    
    -- Broadcast player leave
    self:Send(MSG.PLAYER_LEAVE, playerName)
    
    if BJ.UI and BJ.UI.Craps then
        BJ.UI.Craps:UpdateDisplay()
    end
end

-- Player receives cash out receipt
function CM:HandleCashOutReceipt(hostName, parts)
    if hostName ~= CM.currentHost then return end
    
    local playerName = parts[2]
    local startBalance = tonumber(parts[3]) or 0
    local endBalance = tonumber(parts[4]) or 0
    local netWinLoss = tonumber(parts[5]) or 0
    local isTableClose = parts[6] == "closed"
    
    local myName = UnitName("player")
    if playerName ~= myName then return end
    
    -- Show receipt popup for player
    if BJ.UI and BJ.UI.Craps then
        BJ.UI.Craps:ShowReceiptPopup(playerName, startBalance, endBalance, netWinLoss)
    end
    
    -- Print to chat (different message if table closed vs voluntary cash out)
    if isTableClose then
        BJ:Print("|cffffd700Table closed - your balance:|r " .. BJ:FormatGoldColored(endBalance))
    else
        BJ:Print("|cffffd700You cashed out:|r " .. BJ:FormatGoldColored(endBalance))
        
        -- Only remove self from local state if not table close (table close will reset everything)
        local CS = BJ.CrapsState
        CS:RemovePlayer(myName)
    end
    
    if BJ.UI and BJ.UI.Craps then
        BJ.UI.Craps:UpdateDisplay()
    end
end

-- ROLL DETECTION --

CM.pendingRoll = false
CM.rollDie1 = nil
CM.rollDie2 = nil

-- Host watches for shooter's rolls
CM.hostWatchingRoll = false
CM.hostRollDie1 = nil
CM.hostRollDie2 = nil

function CM:OnSystemMessage(message)
    local CS = BJ.CrapsState
    local myName = UnitName("player")
    
    -- Parse the roll message
    local roller, roll = message:match("(%S+) rolls (%d+) %(1%-6%)")
    if not roller or not roll then return end
    
    local rollNum = tonumber(roll)
    if not rollNum then return end
    
    -- Check for host force roll first (host rolling on behalf of timed-out shooter)
    if CM.isHost and roller == myName and CM.forceRollPending then
        if CM:OnForceRollMessage(rollNum) then
            return
        end
    end
    
    -- If I'm the shooter and I initiated a roll
    if CM.pendingRoll and CS:IsShooter(myName) and roller == myName then
        -- Only process if we're in a rolling phase
        if CS.phase ~= CS.PHASE.COME_OUT and CS.phase ~= CS.PHASE.POINT and CS.phase ~= CS.PHASE.ROLLING then
            CM.pendingRoll = false
            CM.rollDie1 = nil
            CM.rollDie2 = nil
            return
        end
        
        if not CM.rollDie1 then
            CM.rollDie1 = rollNum
            RandomRoll(1, 6)
        elseif not CM.rollDie2 then
            CM.rollDie2 = rollNum
            
            local die1 = CM.rollDie1
            local die2 = CM.rollDie2
            CM.pendingRoll = false
            CM.rollDie1 = nil
            CM.rollDie2 = nil
            
            if CM.isHost then
                CM:ProcessRoll(die1, die2)
            end
            -- Non-host shooter doesn't need to send - host watches chat
            
            if BJ.UI and BJ.UI.Lobby and BJ.UI.Lobby.PlaySound then
                BJ.UI.Lobby:PlaySound("dice")
            end
        end
        return
    end
    
    -- If I'm the host, watch for the shooter's rolls
    if CM.isHost and CS.shooterName and roller == CS.shooterName then
        -- Only process if we're in a rolling phase
        if CS.phase ~= CS.PHASE.COME_OUT and CS.phase ~= CS.PHASE.POINT and CS.phase ~= CS.PHASE.ROLLING then
            -- Clear any partial roll state if someone rolls outside valid phase
            CM.hostRollDie1 = nil
            CM.hostRollDie2 = nil
            return
        end
        
        if not CM.hostRollDie1 then
            CM.hostRollDie1 = rollNum
            BJ:Debug("Host detected shooter die 1: " .. rollNum)
        elseif not CM.hostRollDie2 then
            CM.hostRollDie2 = rollNum
            BJ:Debug("Host detected shooter die 2: " .. rollNum)
            
            local die1 = CM.hostRollDie1
            local die2 = CM.hostRollDie2
            CM.hostRollDie1 = nil
            CM.hostRollDie2 = nil
            
            CM:ProcessRoll(die1, die2)
            
            if BJ.UI and BJ.UI.Lobby and BJ.UI.Lobby.PlaySound then
                BJ.UI.Lobby:PlaySound("dice")
            end
        end
    end
end

function CM:OnChatMessage(message, sender)
    local senderName = sender:match("^([^-]+)") or sender
    local myName = UnitName("player")
    if senderName == myName then return end
    
    local CS = BJ.CrapsState
    
    -- Chat join is disabled for Honor Ledger system - players must use buy-in
    -- This prevents accidental joins without a buy-in amount
end

-- HOST RECOVERY --

CM.hostDisconnected = false
CM.originalHost = nil

function CM:CheckHostConnection()
    local myName = UnitName("player")
    if not CM.currentHost then return end
    
    local CS = BJ.CrapsState
    if CS.phase == CS.PHASE.IDLE then return end
    
    -- If we're the host and not disconnected, nothing to check
    if CM.isHost and not CM.hostDisconnected then return end
    
    -- Check if we ARE the original host who just reconnected
    -- We need to check if we were the host before (hostName matches us)
    if CS.hostName == myName and CM.hostDisconnected then
        CM:RestoreOriginalHost()
        return
    end
    
    -- Also check if our name matches originalHost (in case state was synced)
    if CM.originalHost == myName and CM.hostDisconnected then
        CM:RestoreOriginalHost()
        return
    end
    
    local hostToCheck = CM.originalHost or CM.currentHost
    local hostInGroup = UnitInParty(hostToCheck) or UnitInRaid(hostToCheck)
    local hostOnline = false
    
    if hostInGroup then
        local numMembers = GetNumGroupMembers()
        for i = 1, numMembers do
            local unit = IsInRaid() and ("raid" .. i) or ("party" .. i)
            local name = UnitName(unit)
            if name == hostToCheck then
                hostOnline = UnitIsConnected(unit)
                break
            end
        end
    end
    
    -- Host left group entirely
    if not hostInGroup then
        BJ:Print("|cffff4444Craps host left the group.|r")
        self:VoidGame("Host left")
        return
    end
    
    -- Host disconnected - start recovery
    if not hostOnline and not CM.hostDisconnected then
        self:StartHostRecovery()
    -- Host reconnected during recovery - temp host detects and triggers restore
    elseif hostOnline and CM.hostDisconnected and CM.originalHost then
        -- If we are the temp host, send recovery state to the returning host
        if CM.temporaryHost == myName then
            self:Send(MSG.HOST_RECOVERY_STATE, CM.originalHost, myName, CM.RECOVERY_TIMEOUT - (time() - (CM.recoveryStartTime or time())))
        end
    end
end

--[[
    HOST RECOVERY SYSTEM
    When the original host disconnects, game pauses with a 2-minute grace period.
    If host returns, they resume control. If not, game is voided.
]]

CM.hostDisconnected = false
CM.originalHost = nil
CM.temporaryHost = nil
CM.recoveryTimer = nil
CM.recoveryStartTime = nil
CM.RECOVERY_TIMEOUT = 120  -- 2 minutes

-- Determine who should become the temporary host
function CM:DetermineTemporaryHost()
    local CS = BJ.CrapsState
    local myName = UnitName("player")
    
    -- First online player in shooterOrder becomes temporary host
    for _, playerName in ipairs(CS.shooterOrder) do
        if playerName ~= CM.currentHost then
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
function CM:StartHostRecovery()
    local myName = UnitName("player")
    local CS = BJ.CrapsState
    
    -- Store original host
    CM.originalHost = CM.currentHost
    CM.hostDisconnected = true
    CM.recoveryStartTime = time()
    
    -- Save session state for crash recovery
    CS:SaveHostSession()
    
    -- Determine temporary host
    local tempHost = self:DetermineTemporaryHost()
    
    if tempHost == myName then
        -- We become temporary host
        CM.temporaryHost = myName
        CM.isHost = true  -- For certain permissions
        self:Send(MSG.HOST_RECOVERY_START, myName, CM.originalHost)
        
        BJ:Print("|cffff8800You are temporary host while waiting for " .. CM.originalHost .. " to return.|r")
        BJ:Print("|cffff8800Game is PAUSED. Host has 2 minutes to reconnect or game is voided.|r")
        
        -- Start countdown timer (authoritative)
        self:StartRecoveryCountdown()
    else
        CM.temporaryHost = tempHost
        BJ:Print("|cffff8800" .. CM.originalHost .. " disconnected. Waiting for return (2 min timeout).|r")
        
        -- Start local countdown timer for UI updates
        self:StartLocalRecoveryCountdown()
    end
    
    -- Show recovery popup for all players
    self:ShowRecoveryPopup(CM.originalHost, tempHost == myName)
    
    -- Update UI to show paused state
    if BJ.UI and BJ.UI.Craps then
        BJ.UI.Craps:OnHostRecoveryStart(CM.originalHost, CM.temporaryHost)
    end
end

-- Start authoritative countdown (temp host only)
function CM:StartRecoveryCountdown()
    if CM.recoveryTimer then
        CM.recoveryTimer:Cancel()
    end
    
    local remaining = CM.RECOVERY_TIMEOUT
    
    CM.recoveryTimer = C_Timer.NewTicker(1, function()
        remaining = remaining - 1
        
        -- Broadcast tick every 10 seconds
        if remaining % 10 == 0 or remaining <= 10 then
            CM:Send(MSG.HOST_RECOVERY_TICK, remaining)
        end
        
        -- Update local popup
        CM:UpdateRecoveryPopupTimer(remaining)
        
        if remaining <= 0 then
            CM.recoveryTimer:Cancel()
            CM.recoveryTimer = nil
            CM:VoidGame("Host did not return in time")
        end
    end, CM.RECOVERY_TIMEOUT)
end

-- Start local countdown for non-temp-host players
function CM:StartLocalRecoveryCountdown()
    if CM.localRecoveryTimer then
        CM.localRecoveryTimer:Cancel()
    end
    
    CM.localRecoveryTimer = C_Timer.NewTicker(1, function()
        local elapsed = time() - (CM.recoveryStartTime or time())
        local remaining = CM.RECOVERY_TIMEOUT - elapsed
        
        CM:UpdateRecoveryPopupTimer(remaining)
        
        if remaining <= 0 then
            CM.localRecoveryTimer:Cancel()
            CM.localRecoveryTimer = nil
        end
    end, CM.RECOVERY_TIMEOUT + 5)  -- Extra buffer
end

-- Original host has returned
function CM:RestoreOriginalHost()
    local myName = UnitName("player")
    
    -- Cancel timers
    if CM.recoveryTimer then
        CM.recoveryTimer:Cancel()
        CM.recoveryTimer = nil
    end
    if CM.localRecoveryTimer then
        CM.localRecoveryTimer:Cancel()
        CM.localRecoveryTimer = nil
    end
    
    -- Close popup
    self:CloseRecoveryPopup()
    
    -- Restore host status
    CM.isHost = true
    CM.currentHost = myName
    CM.hostDisconnected = false
    CM.originalHost = nil
    CM.temporaryHost = nil
    CM.recoveryStartTime = nil
    
    local CS = BJ.CrapsState
    CS.hostName = myName
    
    -- Broadcast restoration
    self:Send(MSG.HOST_RESTORED, myName)
    
    BJ:Print("|cff00ff00You have reconnected as host. Game resuming!|r")
    
    -- Resume betting timer if we were in betting phase
    if CS.phase == CS.PHASE.BETTING and CS.bettingTimeRemaining and CS.bettingTimeRemaining > 0 then
        self:StartBettingTimer()
    end
    
    if BJ.UI and BJ.UI.Craps then
        BJ.UI.Craps:OnHostRestored()
        BJ.UI.Craps:UpdateDisplay()
    end
end

-- Show recovery popup window
function CM:ShowRecoveryPopup(hostName, isTempHost)
    if CM.recoveryPopup then
        CM.recoveryPopup:Hide()
    end
    
    local popup = CreateFrame("Frame", "CrapsRecoveryPopup", UIParent, "BackdropTemplate")
    popup:SetSize(320, 140)
    popup:SetPoint("CENTER", 0, 150)
    popup:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    popup:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
    popup:SetBackdropBorderColor(0.8, 0.5, 0.1, 1)
    popup:SetFrameStrata("DIALOG")
    
    local title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -15)
    title:SetText("|cffff8800GAME PAUSED|r")
    
    local statusText = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    statusText:SetPoint("TOP", 0, -45)
    statusText:SetText("Waiting for " .. hostName .. " to return...")
    popup.statusText = statusText
    
    local timerText = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    timerText:SetPoint("TOP", 0, -70)
    timerText:SetText("|cffffd700" .. CM.RECOVERY_TIMEOUT .. "s|r")
    popup.timerText = timerText
    
    local infoText = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    infoText:SetPoint("TOP", 0, -100)
    infoText:SetText("|cff888888Game will void if host doesn't return|r")
    
    -- Void button (temp host only)
    if isTempHost then
        local voidBtn = CreateFrame("Button", nil, popup, "BackdropTemplate")
        voidBtn:SetSize(80, 25)
        voidBtn:SetPoint("BOTTOM", 0, 10)
        voidBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        voidBtn:SetBackdropColor(0.5, 0.2, 0.2, 1)
        voidBtn:SetBackdropBorderColor(0.7, 0.3, 0.3, 1)
        local btnText = voidBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        btnText:SetPoint("CENTER")
        btnText:SetText("|cffffffffVoid Now|r")
        voidBtn:SetScript("OnClick", function()
            CM:VoidGame("Voided by temporary host")
        end)
        voidBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.6, 0.3, 0.3, 1) end)
        voidBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.5, 0.2, 0.2, 1) end)
    end
    
    popup:Show()
    CM.recoveryPopup = popup
end

-- Update popup timer display
function CM:UpdateRecoveryPopupTimer(remaining)
    if CM.recoveryPopup and CM.recoveryPopup.timerText then
        local color = remaining <= 30 and "|cffff4444" or "|cffffd700"
        CM.recoveryPopup.timerText:SetText(color .. remaining .. "s|r")
    end
end

-- Close recovery popup
function CM:CloseRecoveryPopup()
    if CM.recoveryPopup then
        CM.recoveryPopup:Hide()
        CM.recoveryPopup = nil
    end
end

function CM:VoidGame(reason)
    BJ:Print("|cffff4444Craps VOIDED: " .. reason .. "|r")
    
    -- Cancel timers
    if CM.recoveryTimer then
        CM.recoveryTimer:Cancel()
        CM.recoveryTimer = nil
    end
    if CM.localRecoveryTimer then
        CM.localRecoveryTimer:Cancel()
        CM.localRecoveryTimer = nil
    end
    
    -- Close popup
    self:CloseRecoveryPopup()
    
    if CM.isHost or CM.temporaryHost == UnitName("player") then
        self:Send(MSG.GAME_VOIDED, reason)
    end
    
    local CS = BJ.CrapsState
    
    -- Clear saved session since game is voided
    CS:ClearSavedSession()
    
    CS:Reset()
    CM.isHost = false
    CM.currentHost = nil
    CM.tableOpen = false
    CM.hostDisconnected = false
    CM.originalHost = nil
    CM.temporaryHost = nil
    CM.recoveryStartTime = nil
    
    if BJ.UI and BJ.UI.Craps then
        BJ.UI.Craps:OnGameVoided(reason)
    end
end

-- Roster event handling
local rosterFrame = CreateFrame("Frame")
rosterFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
rosterFrame:RegisterEvent("UNIT_CONNECTION")
rosterFrame:SetScript("OnEvent", function()
    if not IsInGroup() and not IsInRaid() then
        local CS = BJ.CrapsState
        if CS and CS.phase ~= CS.PHASE.IDLE then
            CS:Reset()
            CM.isHost = false
            CM.currentHost = nil
            CM.tableOpen = false
            if BJ.UI and BJ.UI.Craps then
                BJ.UI.Craps:UpdateDisplay()
            end
        end
        return
    end
    CM:CheckHostConnection()
end)
