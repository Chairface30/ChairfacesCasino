--[[
    Chairface's Casino - DeathRollMultiplayer.lua
    Multiplayer communication for Death Roll
    Uses AceComm for reliable message delivery

    Rolls themselves are server-verified /rolls that every group member's
    client sees via CHAT_MSG_SYSTEM, so all clients update state directly
    from chat. The host additionally broadcasts each validated roll so
    players who missed the system message (e.g. just reloaded) stay synced.
]]

local BJ = ChairfacesCasino
BJ.DeathRollMultiplayer = {}
local DRM = BJ.DeathRollMultiplayer

local CHANNEL_PREFIX = "CCDeathRoll"

local MSG = {
    TABLE_OPEN = "DROPEN",      -- Host opens challenge: stake, version, startRoll
    TABLE_CLOSE = "DRCLOSE",    -- Host closes/cancels
    JOIN = "DRJOIN",            -- Player requests the opponent seat: version
    JOIN_OK = "DRJOINOK",       -- Host confirms opponent: name
    ROLL = "DRROLL",            -- Host echoes a validated roll: player, roll, max
    SETTLE = "DRSETTLE",        -- Host announces result: winner, loser, stake
    VERSION_REJECT = "DRVREJECT",
    SYNC_STATE = "DRSYNC",      -- Reserved for StateSync version injection
}

-- Shared multiplayer plumbing (send/receive) comes from GameComm.
-- Death Roll overrides the recovery flow: a 2-player roll-off is simply
-- voided if either participant leaves the group.
BJ.GameComm:Embed(DRM, {
    prefix = CHANNEL_PREFIX,
    game = "deathroll",
    displayName = "Death Roll",
    MSG = MSG,
    getState = function() return BJ.DeathRollState end,
    getUI = function() return BJ.UI and BJ.UI.DeathRoll end,
})

-- Initialize communication
function DRM:Initialize()
    self:SetupComm()

    -- Watch for /roll results
    local rollFrame = CreateFrame("Frame")
    rollFrame:RegisterEvent("CHAT_MSG_SYSTEM")
    rollFrame:SetScript("OnEvent", function(_, _, msg)
        DRM:OnSystemMessage(msg)
    end)

    BJ:Debug("Death Roll Multiplayer initialized with AceComm and roll listener")
end

-- Refresh the game window if it exists
local function updateUI()
    if BJ.UI and BJ.UI.DeathRoll and BJ.UI.DeathRoll.UpdateDisplay then
        BJ.UI.DeathRoll:UpdateDisplay()
    end
end

-- Trixie voices the local player's result (frequency-gated in Lobby)
local function playResultVoice(winner, loser)
    local Lobby = BJ.UI and BJ.UI.Lobby
    if not Lobby then return end
    local me = BJ:MyName()
    if me == winner then
        Lobby:PlayTrixieWoohooVoice()
    elseif me == loser then
        Lobby:PlayTrixieVoice("deathroll_bust")   -- rolled a 1: you're done
    end
end

--[[
    ROLL CAPTURE
]]

-- Parse "PlayerName rolls X (1-Y)" system messages
function DRM:OnSystemMessage(msg)
    local DR = BJ.DeathRollState
    if DR.phase ~= DR.PHASE.ROLLING then return end

    -- BJ:ParseRoll reads two-word Forever names and secret lines safely.
    local playerName, roll, maxRoll = BJ:ParseRoll(msg)
    if not playerName then return end

    self:ApplyRoll(playerName, roll, maxRoll, true)
end

-- Apply a roll to local state (from chat or from the host's echo).
-- RecordRoll validates turn + range, so the duplicate path is a no-op.
function DRM:ApplyRoll(playerName, roll, maxRoll, fromChat)
    local DR = BJ.DeathRollState

    local success, result = DR:RecordRoll(playerName, roll, maxRoll)
    if not success then return end

    PlaySoundFile("Interface\\AddOns\\Chairfaces Casino\\Sounds\\dice.mp3", "SFX")

    if result == "settled" then
        BJ:Print(DR.loser .. " rolled a 1! " .. DR.loser .. " owes " .. DR.winner .. " " .. DR.stake .. "g")
        PlaySoundFile("Interface\\AddOns\\Chairfaces Casino\\Sounds\\AirHorn.ogg", "Master")
        playResultVoice(DR.winner, DR.loser)
    elseif roll <= math.max(3, math.floor(maxRoll * 0.05)) then
        BJ:Print(playerName .. " rolls |cffff4444" .. roll .. "|r (1-" .. maxRoll .. ") - close one!")
        local Lobby = BJ.UI and BJ.UI.Lobby
        if Lobby then Lobby:PlayTrixieVoice("deathroll_close", { cd = 4 }) end
    end

    -- Host echoes the roll (and result) for anyone who missed the chat event
    if fromChat and DRM.isHost then
        DRM:Send(MSG.ROLL, playerName, roll, maxRoll)
        if result == "settled" then
            DRM:Send(MSG.SETTLE, DR.winner, DR.loser, DR.stake)
            if BJ.Leaderboard then
                BJ.Leaderboard:EndSession("deathroll")
            end
        end
    end

    updateUI()
end

--[[
    HOST / CLIENT ACTIONS
]]

-- Host opens a challenge. startRoll (optional) is the first roll's ceiling;
-- defaults to 10x the stake inside DeathRollState:HostGame.
function DRM:HostTable(stake, startRoll)
    local inTestMode = BJ.TestMode and BJ.TestMode.enabled
    if not IsInGroup() and not IsInRaid() and not inTestMode then
        BJ:Print("You must be in a party or raid to host a Death Roll.")
        return false
    end

    stake = tonumber(stake)
    if not stake or stake < 2 then
        BJ:Print("Stake must be at least 2g.")
        return false
    end

    -- Don't stack games in the same group
    local Lobby = BJ.UI and BJ.UI.Lobby
    if Lobby and Lobby.IsOtherGameActive then
        local isActive, activeGame = Lobby:IsOtherGameActive("deathroll")
        if isActive then
            BJ:Print("|cffff4444Cannot host - a " .. Lobby:GetGameName(activeGame) .. " game is already in progress.|r")
            return false
        end
    end

    local DR = BJ.DeathRollState
    if DR.phase ~= DR.PHASE.IDLE and DR.phase ~= DR.PHASE.SETTLEMENT then
        BJ:Print("A Death Roll is already in progress.")
        return false
    end

    local myName = BJ:MyName()
    DR:HostGame(myName, stake, startRoll)
    DRM.isHost = true
    DRM.currentHost = myName
    DRM.tableOpen = true

    -- Table terms are fixed at open so the opponent sees fun/real up front
    DR.fakePlay = BJ.GameComm.LocalFakePlay()

    if BJ.Leaderboard then
        BJ.Leaderboard:StartSession("deathroll", myName)
    end

    DRM:Send(MSG.TABLE_OPEN, stake, BJ.version, DR.currentMax, DR.fakePlay and "1" or "0")

    -- Remember the stake for the next host dialog
    if BJ.HostSettings then BJ.HostSettings:Set("deathrollStake", stake) end

    local gameLink = BJ:CreateGameLink("deathroll", "Death Roll")
    BJ:Print(gameLink .. " challenge opened for |cffffd700" .. stake .. "g|r (first roll 1-" .. DR.currentMax .. ")! Waiting for an opponent...")

    updateUI()
    return true
end

-- Client requests the opponent seat
function DRM:RequestJoin()
    if DRM.hostVersion and not BJ:VersionsCompatible(DRM.hostVersion, BJ.version) then
        BJ:Print("|cffff4444Version mismatch!|r Host has v" .. DRM.hostVersion .. ", you have v" .. BJ.version)
        BJ:Print("Please update your addon to join this challenge.")
        return false
    end

    DRM:Send(MSG.JOIN, BJ.version)
    BJ:Print("Requesting the Death Roll seat...")
    return true
end

-- Host cancels / closes the table
function DRM:CloseTable()
    local DR = BJ.DeathRollState
    if not DRM.isHost then return end

    if DR.phase == DR.PHASE.ROLLING then
        BJ:Print("|cffff8800Death Roll cancelled mid-game - no gold changes hands.|r")
    end

    DRM:Send(MSG.TABLE_CLOSE)
    if BJ.Leaderboard then
        BJ.Leaderboard:EndSession("deathroll")
    end
    DRM:ResetState()
    updateUI()
end

function DRM:ResetState()
    DRM.isHost = false
    DRM.currentHost = nil
    DRM.tableOpen = false
    BJ.DeathRollState:Reset()
end

--[[
    MESSAGE HANDLERS
]]

function DRM:RouteMessage(msgType, sender, senderName, parts)
    if msgType == MSG.TABLE_OPEN then
        self:HandleTableOpen(senderName, parts)
    elseif msgType == MSG.TABLE_CLOSE then
        self:HandleTableClose(senderName, parts)
    elseif msgType == MSG.JOIN then
        self:HandleJoin(senderName, parts)
    elseif msgType == MSG.JOIN_OK then
        self:HandleJoinOk(senderName, parts)
    elseif msgType == MSG.ROLL then
        self:HandleRoll(senderName, parts)
    elseif msgType == MSG.SETTLE then
        self:HandleSettle(senderName, parts)
    elseif msgType == MSG.VERSION_REJECT then
        self:HandleVersionReject(senderName, parts)
    end
end

function DRM:HandleTableOpen(senderName, parts)
    local stake = tonumber(parts[2]) or 0
    local hostVersion = parts[3]
    local startRoll = tonumber(parts[4])

    local DR = BJ.DeathRollState
    DR:HostGame(senderName, stake, startRoll)

    -- Table terms as opened (nil = legacy host, terms unknown)
    DR.fakePlay = BJ.GameComm.ParseFakeFlag(parts[5])

    DRM.isHost = false
    DRM.currentHost = senderName
    DRM.tableOpen = true
    DRM.hostVersion = hostVersion

    if hostVersion then
        BJ:OnPeerVersion(hostVersion, senderName)
    end

    local gameLink = BJ:CreateGameLink("deathroll", "Death Roll")
    BJ:Print(senderName .. " opened a " .. gameLink .. " challenge for |cffffd700" .. stake .. "g|r!" ..
        BJ.GameComm.FunTag(DR.fakePlay))
    PlaySoundFile("Interface\\AddOns\\Chairfaces Casino\\Sounds\\dice.mp3", "SFX")

    updateUI()
end

function DRM:HandleTableClose(senderName, parts)
    if senderName ~= DRM.currentHost then return end

    BJ:Print("Death Roll challenge closed.")
    DRM:ResetState()
    updateUI()
end

function DRM:HandleJoin(senderName, parts)
    if not DRM.isHost then return end

    local playerVersion = parts[2]
    if playerVersion then
        BJ:OnPeerVersion(playerVersion, senderName)
    end

    if playerVersion and not BJ:VersionsCompatible(playerVersion, BJ.version) then
        BJ:Print("|cffff8800" .. senderName .. " rejected - version mismatch|r (v" .. playerVersion .. " vs v" .. BJ.version .. ")")
        DRM:SendWhisper(senderName, MSG.VERSION_REJECT, BJ.version)
        return
    end

    local DR = BJ.DeathRollState
    local success, err = DR:SetOpponent(senderName)
    if success then
        DRM:Send(MSG.JOIN_OK, senderName)
        BJ:Print(senderName .. " accepted the Death Roll! You roll first: /roll " .. DR.currentMax)
        updateUI()
    else
        BJ:Debug("Death Roll join from " .. senderName .. " rejected: " .. (err or "?"))
    end
end

function DRM:HandleJoinOk(senderName, parts)
    if senderName ~= DRM.currentHost then return end

    local opponentName = parts[2]
    local DR = BJ.DeathRollState
    DR:SetOpponent(opponentName)

    local myName = BJ:MyName()
    if opponentName == myName then
        BJ:Print("|cff00ff00You're in!|r " .. DR.hostName .. " rolls first.")
    else
        BJ:Print(opponentName .. " took the Death Roll seat. " .. DR.hostName .. " rolls first.")
    end

    updateUI()
end

-- Host's echo of a validated roll (no-op if we already saw it in chat)
function DRM:HandleRoll(senderName, parts)
    if senderName ~= DRM.currentHost then return end

    local playerName = parts[2]
    local roll = tonumber(parts[3])
    local maxRoll = tonumber(parts[4])
    if not playerName or not roll or not maxRoll then return end

    self:ApplyRoll(playerName, roll, maxRoll, false)
end

function DRM:HandleSettle(senderName, parts)
    if senderName ~= DRM.currentHost then return end

    local DR = BJ.DeathRollState
    if DR.phase == DR.PHASE.SETTLEMENT then return end  -- already settled locally

    DR.winner = parts[2]
    DR.loser = parts[3]
    DR.stake = tonumber(parts[4]) or DR.stake
    DR.currentRoller = nil
    DR.phase = DR.PHASE.SETTLEMENT
    DR:SaveToHistory()

    BJ:Print(DR.loser .. " rolled a 1! " .. DR.loser .. " owes " .. DR.winner .. " " .. DR.stake .. "g")
    playResultVoice(DR.winner, DR.loser)
    updateUI()
end

function DRM:HandleVersionReject(senderName, parts)
    local hostVersion = parts[2]
    BJ:Print("|cffff4444Your addon version is outdated!|r")
    BJ:Print("Host has v" .. (hostVersion or "?") .. ", you have v" .. BJ.version)
    BJ:Print("Please update Chairface's Casino to join this challenge.")
end

--[[
    ROSTER WATCHING (overrides the GameComm card-game recovery flow)
    A 2-player roll-off has no meaningful recovery: if either participant
    leaves the group mid-game, everyone voids it locally.
]]

function DRM:OnRosterUpdate()
    local DR = BJ.DeathRollState

    -- If we left the party entirely, reset our local game state
    if not IsInGroup() and not IsInRaid() then
        if DR.phase ~= DR.PHASE.IDLE then
            BJ:Debug("Death Roll: Left party, resetting local game state")
            DRM:ResetState()
            updateUI()
        end
        return
    end

    if DR.phase == DR.PHASE.IDLE or DR.phase == DR.PHASE.SETTLEMENT then return end

    -- Void if a participant is gone from the group
    for _, name in ipairs({ DR.hostName, DR.opponent }) do
        if name and name ~= BJ:MyName()
            and not UnitInParty(name) and not UnitInRaid(name) then
            BJ:Print("|cffff4444Death Roll VOIDED: " .. name .. " left the group. No gold changes hands.|r")
            DRM:ResetState()
            updateUI()
            return
        end
    end
end

-- Initialize on load
DRM:Initialize()
