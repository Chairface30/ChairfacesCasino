--[[
    Chairface's Casino - GameComm.lua
    Shared multiplayer plumbing embedded into each game's Multiplayer module:

      - "|"-delimited serialization (wire format unchanged from the original
        per-game implementations)
      - AceComm send/whisper with optional compression and automatic
        StateSync version injection on SYNC_STATE broadcasts
      - Incoming-message preamble: self-filter, StateSync routing
        (full state / sync request / discovery / host announce), decompression,
        then dispatch to the game's RouteMessage
      - Group roster watching with host-disconnect recovery (2-minute pause,
        temporary host, recovery popup, void on timeout)
      - Pre-deal betting countdown and per-turn timer

    Usage:  BJ.GameComm:Embed(module, config) right after the module's MSG
    table is defined. Config fields:
        prefix              AceComm prefix (e.g. "CCPoker")
        game                StateSync game key (e.g. "poker")
        displayName         User-facing game name for prints
        MSG                 The module's message-type table (SYNC_STATE and
                            COUNTDOWN are used by the shared code)
        getState            function -> the game's state module
        getUI               function -> the game's UI module (resolved lazily)
        turnTimeoutWarning  Text for the 10-second warning (e.g. "auto-stand")

    Games provide these hooks (after Embed, so they override the defaults):
        RouteMessage(msgType, sender, senderName, parts)  -- required
        OnCountdownComplete()      -- required if StartCountdown is used
        ShouldRunTurnTimer()       -- required if StartTurnTimer is used
        OnTurnTimeout()            -- required if StartTurnTimer is used
        ResetState()               -- required (used by VoidGame)
        OnVoidCleanup()            -- optional extra cleanup after VoidGame
    A game may also override any shared method wholesale (High-Lo replaces
    the recovery flow with a permanent host transfer).
]]

local BJ = ChairfacesCasino
BJ.GameComm = {}
local GC = BJ.GameComm

local AceComm = LibStub("AceComm-3.0")
local COMM_DELIMITER = "|"

--[[
    SERIALIZATION
]]

function GC.Serialize(...)
    local parts = {...}
    for i, v in ipairs(parts) do
        parts[i] = tostring(v)
    end
    return table.concat(parts, COMM_DELIMITER)
end

-- Split on "|" preserving empty fields, so positional arguments never shift
function GC.Deserialize(msg)
    local parts = {}
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

--[[
    FAKE-PLAY TABLE TERMS (shared helpers)
    A table's fun/real status is fixed when it opens and rides TABLE_OPEN
    as an appended "1"/"0" field, so joiners see what they're sitting down
    to and a migrated host settles under the original terms.
]]

-- The local fake-play toggle at this moment (captured at table open)
function GC.LocalFakePlay()
    return (BJ.DebtLedger and BJ.DebtLedger:IsFakePlay()) and true or false
end

-- Wire flag ("1"/"0") -> true/false; anything else (legacy sender) -> nil.
-- Explicit if/elseif on purpose: `(x and false) or nil` folds an explicit
-- "0" (REAL table) into nil.
function GC.ParseFakeFlag(flag)
    if flag == "1" then
        return true
    elseif flag == "0" then
        return false
    end
    return nil
end

-- Announcement suffix so joiners know the table's terms up front
function GC.FunTag(fakePlay)
    return fakePlay and " |cff888888(fun game - no debts)|r" or ""
end

--[[
    SHARED METHODS (copied onto each game module by Embed)
]]

local M = {}

-- Resolve the game's UI module (may not exist yet at load time)
function M:UI()
    return self.GetUI and self.GetUI() or nil
end

-- Register AceComm prefix and roster/connection events
function M:SetupComm()
    AceComm:RegisterComm(self.commPrefix, function(prefix, message, distribution, sender)
        self:OnCommReceived(prefix, message, distribution, sender)
    end)

    local frame = CreateFrame("Frame")
    frame:RegisterEvent("GROUP_ROSTER_UPDATE")
    frame:RegisterEvent("UNIT_CONNECTION")
    frame:SetScript("OnEvent", function()
        self:OnRosterUpdate()
    end)

    -- Host-side stall protection; no-ops unless this game defines the
    -- GetCurrentActor/OnActorTimeout hooks and we are hosting
    self:StartActorWatch()
end

-- Send message to group (with compression). SYNC_STATE broadcasts from the
-- host automatically get a StateSync version inserted after the sync type.
function M:Send(msgType, ...)
    local args = {...}
    local msg

    if self.MSG and msgType == self.MSG.SYNC_STATE and self.isHost and BJ.StateSync then
        local version = BJ.StateSync:IncrementVersion(self.gameKey)
        local syncType = args[1]
        table.remove(args, 1)
        msg = GC.Serialize(msgType, syncType, version, unpack(args))
    else
        msg = GC.Serialize(msgType, unpack(args))
    end

    -- When WE open a table, shout it to a human-readable channel so players
    -- WITHOUT the addon nearby know a game is live (throttled; opt-out setting).
    if self.MSG and msgType == self.MSG.TABLE_OPEN and self.isHost then
        GC:PublicAnnounceOpen(self.gameKey, self.displayName)
    end

    local channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY" or nil)
    if channel then
        local compressed, wasCompressed = msg, false
        if BJ.Compression and BJ.Compression.available then
            compressed, wasCompressed = BJ.Compression:Compress(msg)
        end

        AceComm:SendCommMessage(self.commPrefix, compressed, channel)
        BJ:Debug(self.displayName .. " sent: " .. (wasCompressed and "[compressed]" or msg))
    else
        BJ:Debug(self.displayName .. " no group, message not sent: " .. msg)
    end
end

-- Announce an open table in the host's own PARTY/RAID chat, so the host's
-- group members - INCLUDING any who don't run the addon - see a game is live.
-- It never leaves the group (no yell/say/realm reach). Host-side, throttled
-- per game so Blackjack's between-hand TABLE_OPEN re-broadcasts don't spam.
-- A solo host has no group to tell, so it stays silent; "OFF" disables it.
GC.lastPublicAnnounce = {}
GC.PUBLIC_LINES = {
    "Table's up, everyone - %s at Chairface's Casino. Who's in?",
    "Now hosting %s right here - grab a seat, the house is open!",
    "%s is live at my table. Ante up, folks!",
    "Come one, come all - %s running now. Let's play!",
}
function GC:PublicAnnounceOpen(gameKey, displayName)
    local db = BJ.db or ChairfacesCasinoDB
    if db and db.settings and db.settings.trixiePublicChannel == "OFF" then return end
    -- only the host's own party/raid hears it
    local chan = IsInRaid() and "RAID" or (IsInGroup() and "PARTY" or nil)
    if not chan then return end                      -- solo host: nobody to tell
    local now = GetTime()
    local last = self.lastPublicAnnounce[gameKey or ""]
    if last and (now - last) < 300 then return end   -- once per 5 min per game
    self.lastPublicAnnounce[gameKey or ""] = now
    local line = string.format(self.PUBLIC_LINES[math.random(1, #self.PUBLIC_LINES)], displayName or "A casino")
    SendChatMessage(line, chan)
end

-- Send message to a specific player (with compression)
function M:SendWhisper(target, msgType, ...)
    local msg = GC.Serialize(msgType, ...)

    local compressed, wasCompressed = msg, false
    if BJ.Compression and BJ.Compression.available then
        compressed, wasCompressed = BJ.Compression:Compress(msg)
    end

    AceComm:SendCommMessage(self.commPrefix, compressed, "WHISPER", target)
    BJ:Debug(self.displayName .. " whisper to " .. target .. ": " .. (wasCompressed and "[compressed]" or msg))
end

-- Incoming message preamble shared by every game, then per-game dispatch
function M:OnCommReceived(prefix, message, distribution, sender)
    if prefix ~= self.commPrefix then return end

    local myName = BJ:MyName()
    local senderName = sender:match("^([^-]+)") or sender
    if senderName == myName then return end

    -- StateSync full state message (checked before decompression)
    if BJ.StateSync and BJ.StateSync:IsFullStateMessage(message) then
        local stateData = BJ.StateSync:ExtractFullStateData(message)
        if stateData then
            BJ.StateSync:HandleFullState(self.gameKey, stateData)
        end
        return
    end

    -- StateSync request (host only)
    if BJ.StateSync and BJ.StateSync:IsSyncRequestMessage(message) then
        if self.isHost then
            local game = BJ.StateSync:ExtractSyncRequestGame(message)
            if game == self.gameKey then
                BJ.StateSync:HandleSyncRequest(self.gameKey, senderName)
            end
        end
        return
    end

    -- Discovery request (host responds)
    if BJ.StateSync and BJ.StateSync:IsDiscoveryMessage(message) then
        BJ.StateSync:HandleDiscoveryRequest(self.gameKey, senderName)
        return
    end

    -- Host announcement (client learns about host)
    if BJ.StateSync and BJ.StateSync:IsHostAnnounceMessage(message) then
        local game, hostName, phase = message:match("HOSTANNOUN|(%w+)|([^|]+)|(.+)")
        if game == self.gameKey then
            BJ.StateSync:HandleHostAnnounce(self.gameKey, hostName, phase)
        end
        return
    end

    -- Decompress if needed
    if BJ.Compression then
        local decompressed = BJ.Compression:Decompress(message)
        if decompressed then
            message = decompressed
        elseif message:sub(1, 1) == "~" then
            BJ:Debug("Cannot decompress " .. self.displayName .. " message from " .. sender)
            return
        end
    end

    local parts = GC.Deserialize(message)
    local msgType = parts[1]

    BJ:Debug(self.displayName .. " recv from " .. sender .. ": " .. message)

    if msgType == "WDFORCE" then
        -- The host's actor watchdog forced someone's default action
        -- (see ActorWatchTick); handled centrally for every game
        local hostName = self.currentHost and (self.currentHost:match("^([^-]+)") or self.currentHost)
        if senderName == hostName then
            local who, why = parts[2], parts[3]
            BJ:Print("|cffff8800" .. self.displayName .. ": " .. tostring(who) ..
                (why == "left" and " left the group" or " is not responding") ..
                " - the host played their default action.|r")
        end
        return
    end

    if msgType == "FULLSTATE" then
        -- Full state sync from StateSync system
        local serializedData = table.concat(parts, "|", 2)
        if BJ.StateSync then
            BJ.StateSync:HandleFullState(self.gameKey, serializedData)
        end
    elseif msgType == "REQSYNC" then
        -- Sync request from StateSync system
        if self.isHost and BJ.StateSync then
            BJ.StateSync:HandleSyncRequest(self.gameKey, senderName)
        end
    else
        if self.MSG and self.MSG.TABLE_OPEN and msgType == self.MSG.TABLE_OPEN then
            -- Trixie announces the new table by name ("Blackjack's open!") so
            -- other addon holders in the group know to join. If she stays quiet
            -- (muted, frequency roll, or no clip), fall back to the coin chime.
            local spoke = false
            local lobby = BJ.UI and BJ.UI.Lobby
            if lobby and lobby.TrixieAnnounceTable then
                spoke = lobby:TrixieAnnounceTable(self.displayName, senderName, self.gameKey)
            end
            if not spoke then GC:PlayTableOpenChime(self.gameKey, self) end
            GC:MaybeAutoOpen(self.gameKey, self)
        end
        self:RouteMessage(msgType, sender, senderName, parts)
    end
end

-- Subtle "a table just opened" chime so idle addon users notice someone is
-- hosting. Fires centrally for every game's TABLE_OPEN broadcast (own
-- messages never reach here — the preamble self-filters). Deliberately NOT
-- gated on IsAnyCasinoWindowOpen: the point is to reach players with no
-- casino window up. Throttled per game because some hosts re-broadcast
-- TABLE_OPEN every round (Blackjack re-opens the table between hands).
GC.lastOpenChime = {}
function GC:PlayTableOpenChime(gameKey, module)
    -- someone already sitting at that table doesn't need the doorbell
    if module then
        local ui = module.UI and module:UI()
        local f = ui and (ui.mainFrame or ui.frame)
        if f and f.IsShown and f:IsShown() then return end
    end
    local now = GetTime()
    local last = self.lastOpenChime[gameKey or ""]
    if last and (now - last) < 60 then return end
    self.lastOpenChime[gameKey or ""] = now
    BJ:PlaySfx("coin_drop.ogg")
end

-- Per-game auto-open: pop the game's own window when its TABLE_OPEN
-- arrives, for games the user opted into in the settings panel
-- (db.settings.autoOpen[gameKey]; the derby has its own equivalent).
-- Throttled like the chime because some hosts re-broadcast TABLE_OPEN
-- every round - a window the player just closed must not re-pop.
GC.lastAutoOpen = {}
function GC:MaybeAutoOpen(gameKey, module)
    local db = BJ.db or ChairfacesCasinoDB
    local auto = db and db.settings and db.settings.autoOpen
    if not (auto and auto[gameKey]) then return end
    -- already at that table, or busy in a different game? stay put
    local ui = module and module.UI and module:UI()
    local f = ui and (ui.mainFrame or ui.frame)
    if f and f.IsShown and f:IsShown() then return end
    local lobby = BJ.UI and BJ.UI.Lobby
    if lobby and lobby.IsOtherGameActive and lobby:IsOtherGameActive(gameKey) then
        return
    end
    -- a re-broadcast for a session we already know about (Blackjack
    -- re-opens the table between hands) must not re-pop a window the
    -- player closed on purpose - only a FRESH table auto-opens
    if lobby and lobby.IsGameInSession and lobby:IsGameInSession(gameKey) then
        return
    end
    local now = GetTime()
    local last = self.lastAutoOpen[gameKey]
    if last and (now - last) < 60 then return end
    self.lastAutoOpen[gameKey] = now
    -- jump straight to the hosted game: clear every other casino window
    -- first (same behavior as clicking a casinolink)
    if BJ.CloseAllGameWindows then BJ:CloseAllGameWindows() end
    if BJ.OpenGameWindow then BJ:OpenGameWindow(gameKey) end
end

--[[
    ROSTER WATCHING
]]

function M:OnRosterUpdate()
    local myName = BJ:MyName()
    local state = self.GetState()

    -- If we left the party entirely, reset our local game state
    if not IsInGroup() and not IsInRaid() then
        if state and state.phase ~= state.PHASE.IDLE then
            BJ:Debug(self.displayName .. ": Left party, resetting local game state")
            state:Reset()
            self.isHost = false
            self.currentHost = nil
            self.tableOpen = false
            self.hostDisconnected = false
            self.originalHost = nil
            self.temporaryHost = nil
            local ui = self:UI()
            if ui and ui.UpdateDisplay then ui:UpdateDisplay() end
        end
        return
    end

    -- Check if WE are the original host who just reconnected
    if self.originalHost == myName and self.hostDisconnected then
        BJ:Print("|cff00ff00You have reconnected as host. Restoring game...|r")
        self:RestoreOriginalHost()
        return
    end

    if not self.currentHost then return end
    if self.isHost and not self.hostDisconnected then return end

    if state.phase == state.PHASE.IDLE or state.phase == state.PHASE.SETTLEMENT then return end

    local hostInGroup = UnitInParty(self.currentHost) or UnitInRaid(self.currentHost)
    local hostOnline = false

    if hostInGroup then
        local numMembers = GetNumGroupMembers()
        for i = 1, numMembers do
            local unit = IsInRaid() and ("raid" .. i) or ("party" .. i)
            if BJ:UnitFullName(unit) == self.currentHost then
                hostOnline = UnitIsConnected(unit)
                break
            end
        end
    end

    -- If host left the group entirely, void the game
    if not hostInGroup then
        BJ:Print("|cffff4444" .. self.displayName .. " host (" .. self.currentHost .. ") left the group.|r")
        self:VoidGame("Host left the group")
        return
    end

    -- If host is in group but offline - start recovery
    if not hostOnline and not self.hostDisconnected then
        self.hostDisconnected = true
        BJ:Print("|cffff8800" .. self.displayName .. " host (" .. self.currentHost .. ") disconnected!|r")
        self:StartHostRecovery()
    elseif hostOnline and self.hostDisconnected then
        -- Host came back online. Only the temp host triggers the restore;
        -- other clients wait for the HOST_RESTORED broadcast.
        if self.temporaryHost == myName then
            self:CheckHostReturn()
        end
    end
end

--[[
    HOST RECOVERY
    When the original host disconnects, the game pauses with a 2-minute grace
    period. If the host returns they resume control; otherwise the game is
    voided by the temporary host.
]]

local function UpdateRecoveryUI(self, remaining)
    self:UpdateRecoveryPopupTimer(remaining)
    local ui = self:UI()
    if ui and ui.UpdateRecoveryTimer then
        ui:UpdateRecoveryTimer(remaining)
    end
end

-- First connected non-host player in seating order becomes temporary host
function M:DetermineTemporaryHost()
    local state = self.GetState()
    local myName = BJ:MyName()

    for _, playerName in ipairs(state.playerOrder or {}) do
        if playerName ~= self.currentHost then
            if playerName == myName then
                return myName
            end

            local numMembers = GetNumGroupMembers()
            for i = 1, numMembers do
                local unit = IsInRaid() and ("raid" .. i) or ("party" .. i)
                local name = BJ:UnitFullName(unit)
                if name == playerName and UnitIsConnected(unit) then
                    return playerName
                end
            end
        end
    end

    return nil
end

function M:StartHostRecovery()
    local myName = BJ:MyName()

    self.originalHost = self.currentHost
    self.recoveryStartTime = time()
    self.hostDisconnected = true

    local tempHost = self:DetermineTemporaryHost()

    if tempHost == myName then
        self.temporaryHost = myName
        self.isHost = true  -- For reset button access only
        self:Send(self.MSG.SYNC_STATE, "HOST_RECOVERY_START", myName, self.originalHost)

        BJ:Print("|cffff8800You are temporary host while waiting for " .. self.originalHost .. " to return.|r")
        BJ:Print("|cffff8800Game is PAUSED. Host has 2 minutes to reconnect or the game is voided.|r")
        self:StartRecoveryCountdown()
    else
        self.temporaryHost = tempHost
        BJ:Print("|cffff8800Waiting for " .. self.originalHost .. " to return (2 min timeout).|r")
        self:StartLocalRecoveryCountdown()
    end

    -- Show recovery popup for all players
    self:ShowRecoveryPopup(self.originalHost, tempHost == myName)

    local ui = self:UI()
    if ui and ui.OnHostRecoveryStart then
        ui:OnHostRecoveryStart(self.originalHost, self.temporaryHost)
    end
end

-- Authoritative countdown (temp host only) - broadcasts ticks and voids on timeout
function M:StartRecoveryCountdown()
    if self.recoveryTimer then
        self.recoveryTimer:Cancel()
    end

    self.recoveryTimer = C_Timer.NewTicker(1, function()
        local elapsed = time() - self.recoveryStartTime
        local remaining = self.RECOVERY_TIMEOUT - elapsed

        UpdateRecoveryUI(self, remaining)

        -- Broadcast remaining time so other clients stay in sync
        if remaining > 0 and remaining % 5 == 0 then
            self:Send(self.MSG.SYNC_STATE, "HOST_RECOVERY_TICK", remaining)
        end

        if remaining <= 0 then
            self:VoidGame("Host did not return in time")
        end
    end, self.RECOVERY_TIMEOUT + 1)
end

-- Local countdown for non-temp-host clients (UI updates only)
function M:StartLocalRecoveryCountdown()
    if self.localRecoveryTimer then
        self.localRecoveryTimer:Cancel()
    end

    self.localRecoveryTimer = C_Timer.NewTicker(1, function()
        if not self.hostDisconnected then
            -- Recovery ended
            if self.localRecoveryTimer then
                self.localRecoveryTimer:Cancel()
                self.localRecoveryTimer = nil
            end
            return
        end

        local elapsed = time() - self.recoveryStartTime
        local remaining = self.RECOVERY_TIMEOUT - elapsed

        UpdateRecoveryUI(self, remaining)

        if remaining <= 0 then
            if self.localRecoveryTimer then
                self.localRecoveryTimer:Cancel()
                self.localRecoveryTimer = nil
            end
            -- Timer ran out. Games that support host migration (Liar's Dice,
            -- Bingo) elect a new host instead of voiding; everyone else cleans
            -- up locally. VoidGame only broadcasts if we're the temp host, so
            -- for a plain client that is a purely local dismiss + reset.
            if self.OnRecoveryTimeout then
                self:OnRecoveryTimeout()
            else
                self:VoidGame("Host did not return in time")
            end
        end
    end, self.RECOVERY_TIMEOUT + 1)
end

-- Check if the original host is back online, and restore them if so
function M:CheckHostReturn()
    if not self.originalHost or not self.hostDisconnected then return end

    local hostOnline = false
    local numMembers = GetNumGroupMembers()
    for i = 1, numMembers do
        local unit = IsInRaid() and ("raid" .. i) or ("party" .. i)
        if BJ:UnitFullName(unit) == self.originalHost then
            hostOnline = UnitIsConnected(unit)
            break
        end
    end

    if hostOnline then
        self:RestoreOriginalHost()
    end
end

-- Restore original host after they reconnect
function M:RestoreOriginalHost()
    -- Prevent double-restore
    if self.restoringHost then return end
    self.restoringHost = true

    local myName = BJ:MyName()
    local wasOriginalHost = (self.originalHost == myName)
    local originalHostName = self.originalHost
    local wasTempHost = (self.temporaryHost == myName)

    BJ:Print("|cff00ff00" .. originalHostName .. " has returned! Resuming game.|r")

    if self.recoveryTimer then
        self.recoveryTimer:Cancel()
        self.recoveryTimer = nil
    end

    if self.localRecoveryTimer then
        self.localRecoveryTimer:Cancel()
        self.localRecoveryTimer = nil
    end

    self:CloseRecoveryPopup()

    -- If we were temporary host, broadcast restore and send sync to returning host
    if wasTempHost and not wasOriginalHost then
        self:Send(self.MSG.SYNC_STATE, "HOST_RESTORED", originalHostName)

        C_Timer.After(0.5, function()
            if BJ.StateSync then
                BJ.StateSync:BroadcastFullState(self.gameKey)
            end
            self.restoringHost = false
        end)

        -- Relinquish temp host status
        self.isHost = false
    else
        self.restoringHost = false
    end

    -- If we ARE the original host (we just reconnected), reclaim
    if wasOriginalHost then
        BJ:Print("|cff00ff00You have reconnected. Reclaiming host...|r")
        self.isHost = true
        self.currentHost = myName
        -- Resume the StateSync version stream from wherever it is NOW. The
        -- temp host's recovery messages and full-state dump advanced every
        -- client's tracking past our own counter, so continuing from our
        -- stale value would make clients discard our next broadcasts as
        -- "old versions" (or force a needless gap resync).
        if BJ.StateSync then
            local v = BJ.StateSync.versions[self.gameKey]
            if v then v.current = math.max(v.current, v.lastReceived) end
        end
        -- Don't broadcast sync here - temp host will send it to us.
        -- Just update our UI after a delay to receive the sync.
        C_Timer.After(1.5, function()
            local ui = self:UI()
            if ui then
                if ui.UpdateDisplay then ui:UpdateDisplay() end
                if ui.UpdateButtons then ui:UpdateButtons() end
                if ui.UpdateStatus then ui:UpdateStatus() end
            end
        end)
    end

    -- Reset recovery state
    self.hostDisconnected = false
    self.temporaryHost = nil
    self.originalHost = nil
    self.recoveryStartTime = nil

    local ui = self:UI()
    if ui and ui.OnHostRestored then
        ui:OnHostRestored()
    end
end

function M:ShowRecoveryPopup(hostName, isTempHost)
    if self.recoveryPopup then
        self.recoveryPopup:Hide()
    end

    local popup = CreateFrame("Frame", "CasinoRecoveryPopup_" .. self.gameKey, UIParent, "BackdropTemplate")
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

    -- Manual dismiss: any client can hide the pause window even while the
    -- grace timer is still running (or if it never resolves). Hiding is purely
    -- local and does not void the game for anyone else.
    local closeBtn = CreateFrame("Button", nil, popup, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", 2, 2)
    closeBtn:SetScript("OnClick", function() self:CloseRecoveryPopup() end)

    local title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -15)
    title:SetText("|cffff8800HOST DISCONNECTED|r")

    local hostText = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hostText:SetPoint("TOP", title, "BOTTOM", 0, -10)
    hostText:SetText("|cffffffff" .. hostName .. "|r has disconnected")

    local timerText = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    timerText:SetPoint("TOP", hostText, "BOTTOM", 0, -10)
    timerText:SetText("|cffffd7002:00|r")
    popup.timerText = timerText

    local statusText = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusText:SetPoint("TOP", timerText, "BOTTOM", 0, -5)
    statusText:SetText("Game paused - waiting for host to return")
    popup.statusText = statusText

    -- Void button (only for temp host)
    if isTempHost then
        local dialogKey = "CASINO_VOID_CONFIRM_" .. self.gameKey:upper()
        local voidBtn = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
        voidBtn:SetSize(100, 25)
        voidBtn:SetPoint("BOTTOM", 0, 15)
        voidBtn:SetText("Void Game")
        voidBtn:SetScript("OnClick", function()
            StaticPopupDialogs[dialogKey] = {
                text = "Void the current game?\n\nNo gold changes hands.",
                button1 = "Void",
                button2 = "Cancel",
                OnAccept = function()
                    self:VoidGame("Voided by temporary host")
                end,
                timeout = 0,
                whileDead = true,
                hideOnEscape = true,
            }
            StaticPopup_Show(dialogKey)
        end)
        popup.voidBtn = voidBtn
    end

    popup:Show()
    self.recoveryPopup = popup
end

function M:UpdateRecoveryPopupTimer(remaining)
    if self.recoveryPopup and self.recoveryPopup.timerText then
        local mins = math.floor(remaining / 60)
        local secs = remaining % 60
        local color = remaining <= 30 and "ffff4444" or "ffffd700"
        self.recoveryPopup.timerText:SetText("|c" .. color .. string.format("%d:%02d", mins, secs) .. "|r")
    end
end

function M:CloseRecoveryPopup()
    if self.recoveryPopup then
        self.recoveryPopup:Hide()
        self.recoveryPopup = nil
    end
end

-- Void the game (host left, recovery timeout, or manual)
function M:VoidGame(reason)
    BJ:Print("|cffff4444" .. self.displayName .. " VOIDED: " .. reason .. "|r")

    if self.recoveryTimer then
        self.recoveryTimer:Cancel()
        self.recoveryTimer = nil
    end

    if self.localRecoveryTimer then
        self.localRecoveryTimer:Cancel()
        self.localRecoveryTimer = nil
    end

    self:CloseRecoveryPopup()

    if self.temporaryHost == BJ:MyName() then
        self:Send(self.MSG.SYNC_STATE, "GAME_VOIDED", reason)
    end

    self.hostDisconnected = false
    self.temporaryHost = nil
    self.originalHost = nil
    self.recoveryStartTime = nil
    self:ResetState()

    if self.OnVoidCleanup then
        self:OnVoidCleanup()
    end

    local ui = self:UI()
    if ui and ui.OnGameVoided then
        ui:OnGameVoided(reason)
    end
end

-- Check if game is in recovery mode (paused)
function M:IsInRecoveryMode()
    return self.hostDisconnected and self.originalHost ~= nil
end

--[[
    PRE-DEAL COUNTDOWN (host only)
]]

function M:StartCountdown(seconds)
    self.countdownActive = true
    self.countdownRemaining = seconds

    -- "Here we go - findin' your seats!" as the pre-deal countdown kicks off.
    local lobby = BJ.UI and BJ.UI.Lobby
    if lobby and lobby.PlayTrixieVoice then lobby:PlayTrixieVoice("countdown", { cd = 20 }) end
    if self.countdownTimer then
        self.countdownTimer:Cancel()
    end

    self.countdownTimer = C_Timer.NewTicker(1, function()
        self.countdownRemaining = self.countdownRemaining - 1
        self:Send(self.MSG.COUNTDOWN, self.countdownRemaining)

        local ui = self:UI()
        if ui and ui.OnCountdownTick then
            ui:OnCountdownTick(self.countdownRemaining)
        end

        if self.countdownRemaining <= 0 then
            self.countdownActive = false
            self.countdownTimer:Cancel()
            self.countdownTimer = nil
            self:OnCountdownComplete()
        end
    end, seconds)
end

function M:CancelCountdown()
    if self.countdownTimer then
        self.countdownTimer:Cancel()
        self.countdownTimer = nil
    end
    self.countdownActive = false
    self.countdownRemaining = 0
end

--[[
    TURN TIMER (local only)
    Each client tracks their own turn timer. At 10 seconds a warning appears;
    at 0 the game's OnTurnTimeout executes the default action.
]]

function M:StartTurnTimer()
    self:CancelTurnTimer()

    -- Game-specific check: right phase, my turn, still active
    if not self:ShouldRunTurnTimer() then return end

    self.turnTimerRemaining = self.TURN_TIME_LIMIT
    self.turnTimerActive = true

    -- "Your move, sugar." Fires when it becomes the local player's turn in any
    -- turn-based game (frequency-gated; cooldown so multi-street games don't nag).
    local lobby = BJ.UI and BJ.UI.Lobby
    if lobby and lobby.PlayTrixieVoice then lobby:PlayTrixieVoice("turn_nudge", { cd = 25, lineUp = true }) end

    self.turnTimer = C_Timer.NewTicker(1, function()
        self.turnTimerRemaining = self.turnTimerRemaining - 1

        if self.turnTimerRemaining == self.TURN_WARNING_TIME then
            BJ:Print("|cffff4444WARNING: " .. self.TURN_WARNING_TIME ..
                " seconds to make a move or you will " .. (self.turnTimeoutWarning or "auto-play") .. "!|r")
            PlaySoundFile("Interface\\AddOns\\Chairfaces Casino\\Sounds\\AirHorn.ogg", "Master")
        end

        -- Show countdown in UI at <= 10 seconds
        local ui = self:UI()
        if ui and ui.turnTimerFrame then
            if self.turnTimerRemaining <= self.TURN_WARNING_TIME and self.turnTimerRemaining > 0 then
                ui.turnTimerFrame.text:SetText(self.turnTimerRemaining)
                ui.turnTimerFrame:Show()
            else
                ui.turnTimerFrame:Hide()
            end
        end

        if self.turnTimerRemaining <= 0 then
            self:OnTurnTimeout()
        end
    end)
end

function M:CancelTurnTimer()
    if self.turnTimer then
        self.turnTimer:Cancel()
        self.turnTimer = nil
    end
    self.turnTimerActive = false
    self.turnTimerRemaining = 0

    local ui = self:UI()
    if ui and ui.turnTimerFrame then
        ui.turnTimerFrame:Hide()
    end
end

--[[
    HOST-SIDE ACTOR WATCHDOG
    The turn timer above runs ONLY on the acting player's own client, so a
    hard disconnect (client gone, not just AFK) means nobody ever fires the
    timeout and the hand stalls forever. The HOST shadows every turn with its
    own clock: once the same actor has been on the clock past the turn limit
    plus a grace, the host forces the game's default action through the same
    authoritative path a real action message would take. An actor who LEFT
    THE GROUP can never act again, so they are forced out after a short
    settle delay (long enough for an in-flight action message to land).

    Games opt in by defining both hooks (turn-based games only):
        GetCurrentActor()          -> name of the player who must act, or nil
        OnActorTimeout(playerName) -> host-side force of their default action
]]

local ACTOR_LEAVE_SETTLE = 10     -- seconds GONE FROM THE GROUP before a
                                  -- departed actor is forced out (measured
                                  -- from their disappearance, not turn start)
local ACTOR_FORCED_FOLLOWUP = 15  -- window for an actor we already force-
                                  -- acted this turn cycle (multi-hand turns,
                                  -- e.g. Blackjack splits) instead of a
                                  -- fresh full clock

function M:StartActorWatch()
    if self.actorWatchTicker then return end
    -- Only turn-based games define the watchdog hooks; the rest never need
    -- the ticker at all (hooks are defined before Initialize/SetupComm runs)
    if not (self.GetCurrentActor and self.OnActorTimeout) then return end
    self.actorWatchTicker = C_Timer.NewTicker(5, function()
        self:ActorWatchTick()
    end)
end

function M:ActorWatchTick()
    if not (self.GetCurrentActor and self.OnActorTimeout) then return end
    if not self.isHost then
        self.actorWatchName, self.actorWatchSince, self.actorGoneSince = nil, nil, nil
        return
    end
    -- Paused during host recovery; in test mode the fake players are driven
    -- by TestMode (they aren't in the group, so the leave check would
    -- instantly force them out from under the test harness)
    if self.hostDisconnected then return end
    if BJ.TestMode and BJ.TestMode.enabled then return end
    if not IsInGroup() and not IsInRaid() then return end

    local actor = self:GetCurrentActor()
    if not actor or actor == BJ:MyName() then
        self.actorWatchName, self.actorWatchSince, self.actorGoneSince = nil, nil, nil
        self.actorForcedName = nil
        return
    end

    local now = GetTime()
    if actor ~= self.actorWatchName then
        self.actorWatchName = actor
        self.actorWatchSince = now
        self.actorGoneSince = nil
        if actor == self.actorForcedName then
            -- Same player we already force-acted (their turn continued into
            -- another hand): backdate the clock so only a short follow-up
            -- window remains, not another full turn limit
            self.actorWatchSince = now - (self.TURN_TIME_LIMIT + self.ACTOR_GRACE - ACTOR_FORCED_FOLLOWUP)
        else
            self.actorForcedName = nil
        end
        return
    end

    -- The leave-settle window measures from when the actor disappeared
    -- from the group, so even a player who deliberated a while before
    -- dropping gets the full in-flight grace
    local leftGroup = not UnitInParty(actor) and not UnitInRaid(actor)
    if leftGroup then
        self.actorGoneSince = self.actorGoneSince or now
    else
        self.actorGoneSince = nil
    end

    local held = now - (self.actorWatchSince or now)
    local goneFor = self.actorGoneSince and (now - self.actorGoneSince) or 0

    if (leftGroup and goneFor >= ACTOR_LEAVE_SETTLE)
        or held >= (self.TURN_TIME_LIMIT + self.ACTOR_GRACE) then
        self.actorWatchName, self.actorWatchSince, self.actorGoneSince = nil, nil, nil
        self.actorForcedName = actor
        BJ:Print("|cffff8800" .. self.displayName .. ": " .. actor ..
            (leftGroup and " left the group" or " is not responding") ..
            " - forcing their default action.|r")
        -- Tell the table WHY an action is about to appear out of nowhere.
        -- Top-level type (not SYNC_STATE) so no StateSync version is
        -- consumed; old clients' routers ignore unknown types silently.
        self:Send("WDFORCE", actor, leftGroup and "left" or "dc")
        self:OnActorTimeout(actor)
    end
end

function M:CancelActorWatch()
    if self.actorWatchTicker then
        self.actorWatchTicker:Cancel()
        self.actorWatchTicker = nil
    end
    self.actorWatchName, self.actorWatchSince, self.actorGoneSince = nil, nil, nil
    self.actorForcedName = nil
end

--[[
    SYNC_STATE SENDER GATE
    Shared by the card games' HandleSyncState. Ordinary state sync is
    host-authoritative; the recovery/control subtypes below legitimately
    come from the TEMP host (or, for REQUEST_STATE, from any client), so
    the host-only filter must not eat them. HOST_RECOVERY_START and
    RECOVERY_STATE arrive before the receiver knows who the temp host is,
    so they are validated against their own claims instead.
]]

local CONTROL_SYNC = {
    REQUEST_STATE = true,
    RECOVERY_STATE = true,
    HOST_RECOVERY_START = true,
    HOST_RECOVERY_TICK = true,
    HOST_RESTORED = true,
    GAME_VOIDED = true,
}
GC.CONTROL_SYNC = CONTROL_SYNC

-- Returns accepted, isControl. isControl tells the caller to keep control
-- messages out of StateSync version gap detection (they ride the temp
-- host's own counter, or none at all).
function M:AcceptSyncSender(senderName, parts)
    local syncType = parts[2]
    local hostName = self.currentHost and (self.currentHost:match("^([^-]+)") or self.currentHost)

    if CONTROL_SYNC[syncType] then
        if syncType == "HOST_RECOVERY_START" then
            -- Sender must be the temp host it announces, replacing the host we know
            local claimedTemp, claimedOrig = parts[4], parts[5]
            if senderName ~= claimedTemp then return false, true end
            if hostName and claimedOrig ~= hostName then return false, true end
        elseif syncType == "RECOVERY_STATE" then
            -- Whispered to a fresh reloader who may not know the host yet;
            -- trust it only from a claimed participant of the recovery
            local claimedOrig, claimedTemp = parts[4], parts[5]
            if senderName ~= claimedTemp and senderName ~= claimedOrig then return false, true end
        elseif syncType == "REQUEST_STATE" then
            -- Any player may ask; the handler gates on host/temp host
        else
            local tempName = self.temporaryHost and (self.temporaryHost:match("^([^-]+)") or self.temporaryHost)
            if senderName ~= hostName and senderName ~= tempName then return false, true end
        end
        return true, true
    end

    return senderName == hostName, false
end

--[[
    EMBED
]]

function GC:Embed(target, config)
    target.commPrefix = config.prefix
    target.gameKey = config.game
    target.displayName = config.displayName
    target.MSG = config.MSG
    target.GetState = config.getState
    target.GetUI = config.getUI
    target.turnTimeoutWarning = config.turnTimeoutWarning

    -- Shared state defaults
    target.isHost = false
    target.currentHost = nil
    target.tableOpen = false

    target.countdownActive = false
    target.countdownRemaining = 0
    target.countdownTimer = nil

    target.TURN_TIME_LIMIT = 120       -- Seconds per turn; long enough for a
                                       -- disconnected client to reconnect and
                                       -- rejoin before being auto-folded
    target.TURN_WARNING_TIME = 10      -- Show warning at 10 seconds
    target.turnTimerActive = false
    target.turnTimerRemaining = 0
    target.turnTimer = nil

    target.ACTOR_GRACE = 30            -- Host-side watchdog slack past
                                       -- TURN_TIME_LIMIT before force-acting
    target.actorWatchTicker = nil
    target.actorWatchName = nil
    target.actorWatchSince = nil
    target.actorGoneSince = nil
    target.actorForcedName = nil

    target.hostDisconnected = false
    target.originalHost = nil
    target.temporaryHost = nil
    target.recoveryTimer = nil
    target.recoveryStartTime = nil
    target.RECOVERY_TIMEOUT = 120  -- 2 minutes

    for name, fn in pairs(M) do
        target[name] = fn
    end

    -- Register with StateSync so its per-game dispatch can find this module
    if BJ.StateSync and BJ.StateSync.RegisterGame then
        BJ.StateSync:RegisterGame(config.game, {
            mp = target,
            getState = config.getState,
            getUI = config.getUI,
            prefix = config.prefix,
            displayName = config.displayName,
        })
    end

    return target
end
