--[[
    Chairface's Casino - RouletteMultiplayer.lua
    Multiplayer communication for Roulette
    Uses AceComm for reliable message delivery

    Bets travel derby-style: each BET carries the sender's TOTAL on one
    board spot, so every client keeps an identical book and late/lost
    messages self-heal. The spin result is deterministic from the seed
    the host broadcasts, so the outcome never depends on host trust.
]]

local BJ = ChairfacesCasino
BJ.RouletteMultiplayer = {}
local RM = BJ.RouletteMultiplayer

local CHANNEL_PREFIX = "CCRoulette"

local MSG = {
    TABLE_OPEN = "ROPEN",       -- Host opens table: chip, version, maxBets
    TABLE_CLOSE = "RCLOSE",     -- Host closes the table
    JOIN = "RJOIN",             -- Player asks for a seat: version
    JOIN_OK = "RJOINOK",        -- Host confirms: name
    BET = "RBET",               -- Player's total on a spot: key, amount
    SPIN = "RSPIN",             -- Host locks bets and spins: seed
    NEXT = "RNEXT",             -- Host opens the next betting round
    VERSION_REJECT = "RVREJECT",
    SYNC_STATE = "RSYNC",       -- Reserved for StateSync version injection
}

-- Shared multiplayer plumbing (send/receive) comes from GameComm.
-- Roulette overrides the recovery flow: if the bank (host) leaves the
-- group, the table is voided.
BJ.GameComm:Embed(RM, {
    prefix = CHANNEL_PREFIX,
    game = "roulette",
    displayName = "Roulette",
    MSG = MSG,
    getState = function() return BJ.RouletteState end,
    getUI = function() return BJ.UI and BJ.UI.Roulette end,
})

function RM:Initialize()
    self:SetupComm()
    BJ:Debug("Roulette Multiplayer initialized with AceComm")
end

local function updateUI()
    if BJ.UI and BJ.UI.Roulette and BJ.UI.Roulette.UpdateDisplay then
        BJ.UI.Roulette:UpdateDisplay()
    end
end

--[[
    HOST ACTIONS
]]

function RM:HostTable(chip, maxBets)
    local inTestMode = BJ.TestMode and BJ.TestMode.enabled
    if not IsInGroup() and not IsInRaid() and not inTestMode then
        BJ:Print("You must be in a party or raid to host Roulette.")
        return false
    end

    chip = tonumber(chip)
    if not chip or chip < 1 then
        BJ:Print("Chip value must be at least 1g.")
        return false
    end

    -- Don't stack games in the same group
    local Lobby = BJ.UI and BJ.UI.Lobby
    if Lobby and Lobby.IsOtherGameActive then
        local isActive, activeGame = Lobby:IsOtherGameActive("roulette")
        if isActive then
            BJ:Print("|cffff4444Cannot host - a " .. Lobby:GetGameName(activeGame) .. " game is already in progress.|r")
            return false
        end
    end

    local RS = BJ.RouletteState
    if RS.phase ~= RS.PHASE.IDLE and RS.phase ~= RS.PHASE.SETTLEMENT then
        BJ:Print("A Roulette table is already open.")
        return false
    end

    local myName = UnitName("player")
    RS:HostGame(myName, chip, maxBets)
    RM.isHost = true
    RM.currentHost = myName
    RM.tableOpen = true

    -- Table terms are fixed at open so joiners see fun/real up front
    RS.fakePlay = BJ.GameComm.LocalFakePlay()

    if BJ.Leaderboard then
        BJ.Leaderboard:StartSession("roulette", myName)
    end

    RM:Send(MSG.TABLE_OPEN, chip, BJ.version, RS.maxBets, RS.fakePlay and "1" or "0")

    local gameLink = BJ:CreateGameLink("roulette", "Roulette")
    BJ:Print(gameLink .. " table is open! Chips are |cffffd700" .. chip .. "g|r, up to " ..
        RS.maxBets .. " each. Place your bets!")

    updateUI()
    return true
end

-- Host locks the board and spins the wheel
function RM:SpinWheel()
    if not RM.isHost then return false end

    local RS = BJ.RouletteState
    if RS.phase ~= RS.PHASE.BETTING then return false end
    if not RS:AnyBets() then
        BJ:Print("No bets on the board - nothing to spin for.")
        return false
    end

    local seed = (math.floor(GetTime() * 1000) % 2147483647) + math.random(1, 99999)
    local success, err = RS:Spin(seed)
    if not success then
        BJ:Print(err or "Cannot spin.")
        return false
    end

    RM:Send(MSG.SPIN, seed)
    RM:BeginSpin()
    return true
end

-- Shared by host and clients: start the animation and schedule the
-- settlement. Settlement runs off this timer, NOT the animation, so
-- the round resolves even for someone with the window closed.
function RM:BeginSpin()
    local RS = BJ.RouletteState

    BJ:Print("|cffffd700No more bets!|r The wheel is spinning...")
    local Lobby = BJ.UI and BJ.UI.Lobby
    if Lobby then Lobby:PlayTrixieVoice("roulette_nobets", { cd = 6 }) end

    if BJ.UI and BJ.UI.Roulette and BJ.UI.Roulette.StartSpin then
        BJ.UI.Roulette:StartSpin()
    end

    if RM.spinTimer then RM.spinTimer:Cancel() end
    RM.spinTimer = C_Timer.NewTimer(RS.SPIN_SECONDS, function()
        RM.spinTimer = nil
        if RS.phase == RS.PHASE.SPINNING then
            RS:FinishSpin()
            BJ:Print(RS:GetSettlementText())
            -- Trixie voices the local player's result (the bank reacts to
            -- the house's net)
            local Lobby = BJ.UI and BJ.UI.Lobby
            if Lobby and RS.settlements then
                local me = UnitName("player")
                local net = RS.settlements[me]
                if net == nil and me == RS.hostName then
                    net = 0
                    for _, n in pairs(RS.settlements) do net = net - n end
                    if net == 0 then net = nil end
                end
                if net and net > 0 then
                    Lobby:PlayTrixieWoohooVoice()
                elseif net and net < 0 then
                    Lobby:PlayTrixieBadVoice()
                end
            end
            updateUI()
        end
    end)

    updateUI()
end

-- Host opens the next round at the same table
function RM:NextRound()
    if not RM.isHost then return false end

    local RS = BJ.RouletteState
    local success, err = RS:NextRound()
    if not success then
        BJ:Print(err or "Cannot open the next round.")
        return false
    end

    RM:Send(MSG.NEXT)
    BJ:Print("Roulette: next round - place your bets!")
    updateUI()
    return true
end

-- Host closes the table
function RM:CloseTable()
    if not RM.isHost then return end

    local RS = BJ.RouletteState
    if RS.phase == RS.PHASE.SPINNING then
        BJ:Print("|cffff8800Roulette closed mid-spin - no gold changes hands.|r")
    end

    RM:Send(MSG.TABLE_CLOSE)
    if BJ.Leaderboard then
        BJ.Leaderboard:EndSession("roulette")
    end
    RM:ResetState()
    updateUI()
end

function RM:ResetState()
    if RM.spinTimer then
        RM.spinTimer:Cancel()
        RM.spinTimer = nil
    end
    if RM.hostOfflineTimer then
        RM.hostOfflineTimer:Cancel()
        RM.hostOfflineTimer = nil
    end
    RM.isHost = false
    RM.currentHost = nil
    RM.tableOpen = false
    BJ.RouletteState:Reset()
    if BJ.UI and BJ.UI.Roulette and BJ.UI.Roulette.StopSpin then
        BJ.UI.Roulette:StopSpin()
    end
end

--[[
    CLIENT ACTIONS
]]

function RM:RequestJoin()
    if RM.hostVersion and not BJ:VersionsCompatible(RM.hostVersion, BJ.version) then
        BJ:Print("|cffff4444Version mismatch!|r Host has v" .. RM.hostVersion .. ", you have v" .. BJ.version)
        BJ:Print("Please update your addon to join this table.")
        return false
    end

    RM:Send(MSG.JOIN, BJ.version)
    return true
end

-- Adjust my total on one board spot by `dir` chips and broadcast it
function RM:PlaceBet(key, dir)
    local RS = BJ.RouletteState
    local myName = UnitName("player")

    if RM.isHost then
        BJ:Print("|cffff6060The bank cannot place bets.|r")
        return false
    end
    if RS.phase ~= RS.PHASE.BETTING then return false end
    if not RS.players[myName] then
        BJ:Print("Take a seat first (JOIN).")
        return false
    end

    local cur = RS.players[myName].bets[key] or 0
    local amount = cur + dir * RS.chip
    if amount < 0 then amount = 0 end

    local success, err = RS:SetBet(myName, key, amount)
    if not success then
        if err then BJ:Print("|cffff8800" .. err .. "|r") end
        return false
    end

    RM:Send(MSG.BET, key, amount)
    if dir > 0 then
        PlaySoundFile("Interface\\AddOns\\Chairfaces Casino\\Sounds\\chips.ogg", "SFX")
    end
    updateUI()
    return true
end

--[[
    MESSAGE HANDLERS
]]

function RM:RouteMessage(msgType, sender, senderName, parts)
    if msgType == MSG.TABLE_OPEN then
        self:HandleTableOpen(senderName, parts)
    elseif msgType == MSG.TABLE_CLOSE then
        self:HandleTableClose(senderName, parts)
    elseif msgType == MSG.JOIN then
        self:HandleJoin(senderName, parts)
    elseif msgType == MSG.JOIN_OK then
        self:HandleJoinOk(senderName, parts)
    elseif msgType == MSG.BET then
        self:HandleBet(senderName, parts)
    elseif msgType == MSG.SPIN then
        self:HandleSpin(senderName, parts)
    elseif msgType == MSG.NEXT then
        self:HandleNext(senderName, parts)
    elseif msgType == MSG.VERSION_REJECT then
        self:HandleVersionReject(senderName, parts)
    end
end

function RM:HandleTableOpen(senderName, parts)
    local chip = tonumber(parts[2]) or 0
    local hostVersion = parts[3]
    local maxBets = tonumber(parts[4])

    local RS = BJ.RouletteState
    RS:HostGame(senderName, chip, maxBets)

    -- Table terms as opened (nil = legacy host, terms unknown)
    RS.fakePlay = BJ.GameComm.ParseFakeFlag(parts[5])

    RM.isHost = false
    RM.currentHost = senderName
    RM.tableOpen = true
    RM.hostVersion = hostVersion

    if hostVersion then
        BJ:OnPeerVersion(hostVersion, senderName)
    end

    local gameLink = BJ:CreateGameLink("roulette", "Roulette")
    BJ:Print(senderName .. " opened a " .. gameLink .. " table! Chips are |cffffd700" .. chip .. "g|r." ..
        BJ.GameComm.FunTag(RS.fakePlay))
    PlaySoundFile("Interface\\AddOns\\Chairfaces Casino\\Sounds\\chips.ogg", "SFX")

    updateUI()
end

function RM:HandleTableClose(senderName, parts)
    if senderName ~= RM.currentHost then return end

    BJ:Print("Roulette table closed.")
    RM:ResetState()
    updateUI()
end

function RM:HandleJoin(senderName, parts)
    if not RM.isHost then return end

    local playerVersion = parts[2]
    if playerVersion then
        BJ:OnPeerVersion(playerVersion, senderName)
    end

    if playerVersion and not BJ:VersionsCompatible(playerVersion, BJ.version) then
        BJ:Print("|cffff8800" .. senderName .. " rejected - version mismatch|r (v" .. playerVersion .. " vs v" .. BJ.version .. ")")
        RM:SendWhisper(senderName, MSG.VERSION_REJECT, BJ.version)
        return
    end

    local RS = BJ.RouletteState
    local success, err = RS:AddPlayer(senderName)
    if success then
        BJ:Print(senderName .. " sat down at the roulette table.")
        RM:Send(MSG.JOIN_OK, senderName)
        -- Push the whole current book to the new player so they see every
        -- bet already on the board, not just chips placed after they joined.
        if BJ.StateSync then
            BJ.StateSync:SendFullState("roulette", senderName, BJ.StateSync:BuildFullState("roulette"))
        end
        updateUI()
    else
        BJ:Debug("Roulette join from " .. senderName .. " rejected: " .. (err or "?"))
    end
end

function RM:HandleJoinOk(senderName, parts)
    if senderName ~= RM.currentHost then return end

    local playerName = parts[2]
    local RS = BJ.RouletteState
    if playerName and not RS.players[playerName] then
        RS:AddPlayer(playerName)
    end

    local myName = UnitName("player")
    if playerName == myName then
        BJ:Print("|cff00ff00You're in!|r Left-click a spot to stack a chip, right-click to take one back.")
    end

    updateUI()
end

-- Everyone applies everyone's bet totals directly (group broadcast)
function RM:HandleBet(senderName, parts)
    local key = parts[2]
    local amount = tonumber(parts[3])
    if not key or not amount then return end

    local RS = BJ.RouletteState
    -- Late joiners to the roster: a bet implies a seat
    if not RS.players[senderName] and RS.phase == RS.PHASE.BETTING then
        RS:AddPlayer(senderName)
    end
    if RS:SetBet(senderName, key, amount) then
        updateUI()
    end
end

function RM:HandleSpin(senderName, parts)
    if senderName ~= RM.currentHost then return end

    local seed = tonumber(parts[2])
    if not seed then return end

    local RS = BJ.RouletteState
    if RS:Spin(seed) then
        RM:BeginSpin()
    end
end

function RM:HandleNext(senderName, parts)
    if senderName ~= RM.currentHost then return end

    local RS = BJ.RouletteState
    if RS:NextRound() then
        BJ:Print("Roulette: next round - place your bets!")
        updateUI()
    end
end

function RM:HandleVersionReject(senderName, parts)
    local hostVersion = parts[2]
    BJ:Print("|cffff4444Your addon version is outdated!|r")
    BJ:Print("Host has v" .. (hostVersion or "?") .. ", you have v" .. BJ.version)
    BJ:Print("Please update Chairface's Casino to join this table.")
end

--[[
    ROSTER WATCHING (overrides the GameComm card-game recovery flow)
    If the bank (host) leaves the group, the table is voided at once. If the
    bank merely DISCONNECTS (still in the group), every client independently
    gives them the shared recovery window to come back, then voids locally -
    there is no temp-host machinery here because the bank IS the game.
    A player leaving just forfeits their unsettled bets from the roster.
]]

function RM:CancelHostOfflineTimer()
    if RM.hostOfflineTimer then
        RM.hostOfflineTimer:Cancel()
        RM.hostOfflineTimer = nil
    end
end

function RM:OnRosterUpdate()
    local RS = BJ.RouletteState

    -- If we left the party entirely, reset our local game state
    if not IsInGroup() and not IsInRaid() then
        if RS.phase ~= RS.PHASE.IDLE then
            BJ:Debug("Roulette: Left party, resetting local game state")
            RM:ResetState()
            updateUI()
        end
        return
    end

    if RS.phase == RS.PHASE.IDLE or RS.phase == RS.PHASE.SETTLEMENT then
        RM:CancelHostOfflineTimer()
        return
    end

    local host = RM.currentHost
    if not host or host == UnitName("player") then return end

    if not UnitInParty(host) and not UnitInRaid(host) then
        BJ:Print("|cffff4444Roulette VOIDED: the bank (" .. host .. ") left the group. No gold changes hands.|r")
        RM:ResetState()
        updateUI()
        return
    end

    -- Bank still in the group: check their connection
    local online = false
    local numMembers = GetNumGroupMembers()
    for i = 1, numMembers do
        local unit = IsInRaid() and ("raid" .. i) or ("party" .. i)
        if UnitName(unit) == host then
            online = UnitIsConnected(unit)
            break
        end
    end

    if not online then
        if not RM.hostOfflineTimer then
            BJ:Print("|cffff8800Roulette: the bank (" .. host .. ") disconnected - waiting " ..
                RM.RECOVERY_TIMEOUT .. "s for them to return.|r")
            RM.hostOfflineTimer = C_Timer.NewTimer(RM.RECOVERY_TIMEOUT, function()
                RM.hostOfflineTimer = nil
                local RS2 = BJ.RouletteState
                if RS2.phase == RS2.PHASE.IDLE or RS2.phase == RS2.PHASE.SETTLEMENT then return end
                -- Recheck directly - don't trust that a reconnect event
                -- fired (UnitIsConnected can flicker during loading screens)
                local stillOnline = false
                local n = GetNumGroupMembers()
                for i = 1, n do
                    local unit = IsInRaid() and ("raid" .. i) or ("party" .. i)
                    if UnitName(unit) == host then
                        stillOnline = UnitIsConnected(unit)
                        break
                    end
                end
                if stillOnline then return end
                BJ:Print("|cffff4444Roulette VOIDED: the bank (" .. host ..
                    ") did not return. No gold changes hands.|r")
                RM:ResetState()
                updateUI()
            end)
        end
    elseif RM.hostOfflineTimer then
        RM:CancelHostOfflineTimer()
        BJ:Print("|cff00ff00Roulette: the bank is back - the table resumes.|r")
    end
end

-- Initialize on load
RM:Initialize()
