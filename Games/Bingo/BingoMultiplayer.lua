--[[
    Chairface's Casino - BingoMultiplayer.lua
    Multiplayer communication for Bingo
    Uses AceComm for reliable message delivery

    The host is the caller: it draws from the seeded pool on a ticker and
    broadcasts each number. Cards are deterministic from (seed, name), so
    every client renders and daubs everyone's cards identically, and the
    host detects winners authoritatively after each draw.
]]

local BJ = ChairfacesCasino
BJ.BingoMultiplayer = {}
local BM = BJ.BingoMultiplayer

local CHANNEL_PREFIX = "CCBingo"

local MSG = {
    TABLE_OPEN = "BOPEN",       -- price, seed, version
    TABLE_CLOSE = "BCLOSE",
    JOIN = "BJOIN",             -- version
    PLAYER_JOIN = "BPJOIN",     -- host confirms: name
    LEAVE = "BLEAVE",
    START = "BSTART",           -- draw begins
    DRAW = "BDRAW",             -- number, drawIndex
    WINNER = "BWINNER",         -- namesCsv, pot, share
    HOST_SWAP = "BHSWAP",       -- newHost, epoch  (caller migration keeps the draw alive)
    VERSION_REJECT = "BVREJECT",
    SYNC_STATE = "BSYNC",       -- Reserved for StateSync version injection
}

BM.DRAW_SECONDS = 1.5  -- seconds between called numbers (tuned in testing)

-- Shared multiplayer plumbing (send/receive) comes from GameComm.
-- Bingo overrides the recovery flow: if the caller (host) leaves the
-- group mid-draw, the game is voided.
BJ.GameComm:Embed(BM, {
    prefix = CHANNEL_PREFIX,
    game = "bingo",
    displayName = "Bingo",
    MSG = MSG,
    getState = function() return BJ.BingoState end,
    getUI = function() return BJ.UI and BJ.UI.Bingo end,
})

function BM:Initialize()
    self:SetupComm()
    BJ:Debug("Bingo Multiplayer initialized with AceComm")
end

local function updateUI()
    if BJ.UI and BJ.UI.Bingo and BJ.UI.Bingo.UpdateDisplay then
        BJ.UI.Bingo:UpdateDisplay()
    end
end

--[[
    HOST ACTIONS
]]

function BM:HostTable(cardPrice)
    local inTestMode = BJ.TestMode and BJ.TestMode.enabled
    if not IsInGroup() and not IsInRaid() and not inTestMode then
        BJ:Print("You must be in a party or raid to host Bingo.")
        return false
    end

    cardPrice = tonumber(cardPrice)
    if not cardPrice or cardPrice < 1 then
        BJ:Print("Card price must be at least 1g.")
        return false
    end

    -- Don't stack games in the same group
    local Lobby = BJ.UI and BJ.UI.Lobby
    if Lobby and Lobby.IsOtherGameActive then
        local isActive, activeGame = Lobby:IsOtherGameActive("bingo")
        if isActive then
            BJ:Print("|cffff4444Cannot host - a " .. Lobby:GetGameName(activeGame) .. " game is already in progress.|r")
            return false
        end
    end

    local BS = BJ.BingoState
    if BS.phase ~= BS.PHASE.IDLE and BS.phase ~= BS.PHASE.SETTLEMENT then
        BJ:Print("A Bingo game is already in progress.")
        return false
    end

    local myName = BJ:MyName()
    local seed = (math.floor(GetTime() * 1000) % 2147483647) + math.random(1, 99999)

    BS:HostGame(myName, cardPrice, seed)
    BM.isHost = true
    BM.currentHost = myName
    BM.hostEpoch = 1
    BM.tableOpen = true

    -- The table's fun/real status is fixed when it opens, so a migrated
    -- caller settles under the ORIGINAL terms, not their own toggle
    BS.opener = myName
    BS.fakePlay = BJ.GameComm.LocalFakePlay()

    if BJ.Leaderboard then
        BJ.Leaderboard:StartSession("bingo", myName)
    end

    BM:Send(MSG.TABLE_OPEN, cardPrice, seed, BJ.version, BS.fakePlay and "1" or "0")

    -- Remember the card price for the next host dialog
    if BJ.HostSettings then BJ.HostSettings:Set("bingoPrice", cardPrice) end

    local gameLink = BJ:CreateGameLink("bingo", "Bingo")
    BJ:Print(gameLink .. " is open! Cards are |cffffd700" .. cardPrice .. "g|r each. Winner takes the pot!")

    updateUI()
    return true
end

-- Host begins the draw
function BM:StartGame()
    if not BM.isHost then return false end

    local BS = BJ.BingoState
    local success, err = BS:StartDrawing()
    if not success then
        BJ:Print(err or "Cannot start.")
        return false
    end

    BM:Send(MSG.START)
    BJ:Print("Bingo draw started! Pot: |cffffd700" .. BS.pot .. "g|r. First line wins!")
    BM:StartDrawTicker()

    updateUI()
    return true
end

-- Host draw ticker: one number every DRAW_SECONDS
function BM:StartDrawTicker()
    BM:CancelDrawTicker()

    BM.drawTicker = C_Timer.NewTicker(BM.DRAW_SECONDS, function()
        local BS = BJ.BingoState
        if BS.phase ~= BS.PHASE.DRAWING then
            BM:CancelDrawTicker()
            return
        end

        local n = BS:NextDraw()
        if not n then
            BM:CancelDrawTicker()
            return
        end

        BS:RecordDraw(n)
        BM:Send(MSG.DRAW, n, BS.drawIndex)
        BM:OnNumberCalled(n)

        -- Host authoritatively detects winners after each draw
        BM:CheckWinnersNow()
    end)
end

-- Host-only: settle if the current numbers already make a winner. Returns true
-- (and stops the draw) if it did. Shared by the draw ticker and a fresh caller
-- taking over mid-draw, in case a line completed on the number just called.
function BM:CheckWinnersNow()
    local BS = BJ.BingoState
    if BS.phase ~= BS.PHASE.DRAWING then return false end

    local winners = BS:FindWinners()
    if #winners == 0 then return false end

    BM:CancelDrawTicker()
    local pot = BS.pot
    local share = math.floor(pot / #winners)
    BS:FinalizeSettlement(winners, pot, share)
    BM:Send(MSG.WINNER, table.concat(winners, ","), pot, share)
    BM:AnnounceWinners()
    if BJ.Leaderboard then
        BJ.Leaderboard:EndSession("bingo")
    end
    updateUI()
    return true
end

function BM:CancelDrawTicker()
    if BM.drawTicker then
        BM.drawTicker:Cancel()
        BM.drawTicker = nil
    end
end

-- Local reaction to a called number (both host and clients).
-- Deliberately silent - a sound every 1.5s got old fast.
function BM:OnNumberCalled(n)
    local BS = BJ.BingoState

    if BJ.UI and BJ.UI.Bingo and BJ.UI.Bingo.OnDraw then
        BJ.UI.Bingo:OnDraw(n)
    else
        updateUI()
    end
end

function BM:AnnounceWinners()
    local BS = BJ.BingoState
    BJ:Print("|cff00ff00BINGO!|r " .. table.concat(BS.winners, ", ") ..
        " wins |cffffd700" .. BS.share .. "g|r after " .. #BS.drawn .. " numbers!")
    -- Only celebrate out loud for people actually watching the game
    local bui = BJ.UI and BJ.UI.Bingo
    if bui and bui.frame and bui.frame:IsShown() then
        PlaySoundFile("Interface\\AddOns\\Chairfaces Casino\\Sounds\\Bingo.ogg", "Master")
    end
    -- Trixie voices the local player's result
    local Lobby = BJ.UI and BJ.UI.Lobby
    if Lobby then
        local me = BJ:MyName()
        local iWon = false
        for _, name in ipairs(BS.winners or {}) do
            if name == me then iWon = true break end
        end
        if iWon then
            Lobby:PlayTrixieVoice("bingo_win")   -- "BINGO, sugar!"
        elseif BS.players and BS.players[me] then
            Lobby:PlayTrixieBadVoice()
        end
    end
end

-- Host cancels / closes the table
function BM:CloseTable()
    if not BM.isHost then return end

    local BS = BJ.BingoState
    if BS.phase == BS.PHASE.DRAWING then
        BJ:Print("|cffff8800Bingo cancelled mid-draw - no gold changes hands.|r")
    end

    BM:CancelDrawTicker()
    BM:Send(MSG.TABLE_CLOSE)
    if BJ.Leaderboard then
        BJ.Leaderboard:EndSession("bingo")
    end
    BM:ResetState()
    updateUI()
end

function BM:ResetState()
    BM:CancelDrawTicker()
    BM.isHost = false
    BM.currentHost = nil
    BM.hostEpoch = 0
    BM.tableOpen = false
    BJ.BingoState:Reset()
end

--[[
    CLIENT ACTIONS
]]

function BM:RequestJoin()
    if BM.hostVersion and not BJ:VersionsCompatible(BM.hostVersion, BJ.version) then
        BJ:Print("|cffff4444Version mismatch!|r Host has v" .. BM.hostVersion .. ", you have v" .. BJ.version)
        BJ:Print("Please update your addon to join this game.")
        return false
    end

    BM:Send(MSG.JOIN, BJ.version)
    return true
end

--[[
    MESSAGE HANDLERS
]]

-- Caller-authoritative broadcast types. If we are the current caller and hear
-- one of these from someone else, a stale ex-caller has surfaced (e.g. it
-- reconnected after a migration). We re-assert our epoch so it stands down.
local HOST_AUTHORITATIVE = {
    [MSG.TABLE_OPEN] = true,
    [MSG.START] = true,
    [MSG.DRAW] = true,
    [MSG.WINNER] = true,
}

function BM:RouteMessage(msgType, sender, senderName, parts)
    -- Re-assert only while OUR game is live: a settled/idle ex-caller (whose
    -- isHost persists until reset) must not shout down the next table someone
    -- else opens (same phase guard as High-Lo's transfer machinery).
    local BS = BJ.BingoState
    if BM.isHost and HOST_AUTHORITATIVE[msgType] and senderName ~= BJ:MyName()
        and BS.phase ~= BS.PHASE.IDLE and BS.phase ~= BS.PHASE.SETTLEMENT then
        BM:Send(MSG.HOST_SWAP, BJ:MyName(), BM.hostEpoch or 1)
        return
    end

    if msgType == MSG.TABLE_OPEN then
        self:HandleTableOpen(senderName, parts)
    elseif msgType == MSG.TABLE_CLOSE then
        self:HandleTableClose(senderName, parts)
    elseif msgType == MSG.JOIN then
        self:HandleJoin(senderName, parts)
    elseif msgType == MSG.PLAYER_JOIN then
        self:HandlePlayerJoin(senderName, parts)
    elseif msgType == MSG.LEAVE then
        self:HandleLeave(senderName, parts)
    elseif msgType == MSG.START then
        self:HandleStart(senderName, parts)
    elseif msgType == MSG.DRAW then
        self:HandleDraw(senderName, parts)
    elseif msgType == MSG.WINNER then
        self:HandleWinner(senderName, parts)
    elseif msgType == MSG.HOST_SWAP then
        self:HandleHostSwap(senderName, parts)
    elseif msgType == MSG.VERSION_REJECT then
        self:HandleVersionReject(senderName, parts)
    end
end

function BM:HandleTableOpen(senderName, parts)
    local cardPrice = tonumber(parts[2]) or 0
    local seed = tonumber(parts[3])
    local hostVersion = parts[4]
    local fakeFlag = parts[5]  -- "1"/"0"; nil from pre-2.5.1 hosts
    if not seed then return end

    local BS = BJ.BingoState
    BS:HostGame(senderName, cardPrice, seed)

    -- Table terms as opened (nil fakePlay = unknown/legacy host: a migrated
    -- caller then falls back to their own live setting, the old behavior)
    BS.opener = senderName
    BS.fakePlay = BJ.GameComm.ParseFakeFlag(fakeFlag)

    BM.isHost = false
    BM.currentHost = senderName
    BM.hostEpoch = 1
    BM.tableOpen = true
    BM.hostVersion = hostVersion

    if hostVersion then
        BJ:OnPeerVersion(hostVersion, senderName)
    end

    local gameLink = BJ:CreateGameLink("bingo", "Bingo")
    BJ:Print(senderName .. " opened " .. gameLink .. "! Cards are |cffffd700" .. cardPrice .. "g|r each." ..
        BJ.GameComm.FunTag(BS.fakePlay))
    PlaySoundFile("Interface\\AddOns\\Chairfaces Casino\\Sounds\\chips.ogg", "SFX")

    updateUI()
end

function BM:HandleTableClose(senderName, parts)
    if senderName ~= BM.currentHost then return end

    BJ:Print("Bingo table closed.")
    BM:ResetState()
    updateUI()
end

function BM:HandleJoin(senderName, parts)
    if not BM.isHost then return end

    local playerVersion = parts[2]
    if playerVersion then
        BJ:OnPeerVersion(playerVersion, senderName)
    end

    if playerVersion and not BJ:VersionsCompatible(playerVersion, BJ.version) then
        BJ:Print("|cffff8800" .. senderName .. " rejected - version mismatch|r (v" .. playerVersion .. " vs v" .. BJ.version .. ")")
        BM:SendWhisper(senderName, MSG.VERSION_REJECT, BJ.version)
        return
    end

    local BS = BJ.BingoState
    local success, err = BS:AddPlayer(senderName)
    if success then
        BJ:Print(senderName .. " bought a bingo card (" .. #BS.playerOrder .. " players)")
        BM:Send(MSG.PLAYER_JOIN, senderName)
        updateUI()
    else
        BJ:Debug("Bingo join from " .. senderName .. " rejected: " .. (err or "?"))
    end
end

function BM:HandlePlayerJoin(senderName, parts)
    if senderName ~= BM.currentHost then return end

    local playerName = parts[2]
    local BS = BJ.BingoState
    if playerName and not BS.players[playerName] then
        BS:AddPlayer(playerName)
    end

    local myName = BJ:MyName()
    if playerName == myName then
        BJ:Print("|cff00ff00You're in!|r Your card is ready - waiting for the draw to start.")
    end

    updateUI()
end

function BM:HandleLeave(senderName, parts)
    if not BM.isHost then return end

    local BS = BJ.BingoState
    if BS:RemovePlayer(senderName) then
        BJ:Print(senderName .. " left the bingo game.")
        updateUI()
    end
end

function BM:HandleStart(senderName, parts)
    if senderName ~= BM.currentHost then return end

    local BS = BJ.BingoState
    if BS.phase == BS.PHASE.LOBBY then
        -- Clients flip phase directly; the pot derives from price x players
        BS.pot = BS.cardPrice * #BS.playerOrder
        BS.phase = BS.PHASE.DRAWING
    end

    BJ:Print("Bingo draw started! Pot: |cffffd700" .. BS.pot .. "g|r. First line wins!")
    updateUI()
end

function BM:HandleDraw(senderName, parts)
    if senderName ~= BM.currentHost then return end

    local n = tonumber(parts[2])
    if not n then return end

    local BS = BJ.BingoState
    if BS:RecordDraw(n) then
        BM:OnNumberCalled(n)
    end
end

function BM:HandleWinner(senderName, parts)
    if senderName ~= BM.currentHost then return end

    local BS = BJ.BingoState
    if BS.phase == BS.PHASE.SETTLEMENT then return end

    local winners = {}
    for name in (parts[2] or ""):gmatch("[^,]+") do
        table.insert(winners, name)
    end
    local pot = tonumber(parts[3])
    local share = tonumber(parts[4])

    BS:FinalizeSettlement(winners, pot, share)
    BM:AnnounceWinners()
    updateUI()
end

function BM:HandleVersionReject(senderName, parts)
    local hostVersion = parts[2]
    BJ:Print("|cffff4444Your addon version is outdated!|r")
    BJ:Print("Host has v" .. (hostVersion or "?") .. ", you have v" .. BJ.version)
    BJ:Print("Please update Chairface's Casino to join this game.")
end

--[[
    ROSTER WATCHING (overrides the GameComm card-game recovery flow)
    Bingo is fully deterministic from the shared seed, so it does not depend on
    any single caller: if the caller leaves or drops, any remaining player can
    rebuild the draw pool and continue. We migrate the caller role instead of
    voiding, and only void if literally no one is left to take over.
]]

function BM:OnRosterUpdate()
    local BS = BJ.BingoState

    -- If we left the party entirely, reset our local game state
    if not IsInGroup() and not IsInRaid() then
        if BS.phase ~= BS.PHASE.IDLE then
            BJ:Debug("Bingo: Left party, resetting local game state")
            BM:ResetState()
            updateUI()
        end
        return
    end

    if BS.phase == BS.PHASE.IDLE or BS.phase == BS.PHASE.SETTLEMENT then return end
    if not BM.currentHost then return end
    if BM.isHost then return end

    local host = BM.currentHost
    local hostInGroup = UnitInParty(host) or UnitInRaid(host)
    local hostOnline = false
    if hostInGroup then
        local n = GetNumGroupMembers()
        for i = 1, n do
            local unit = IsInRaid() and ("raid" .. i) or ("party" .. i)
            if BJ:UnitFullName(unit) == host then
                hostOnline = UnitIsConnected(unit)
                break
            end
        end
    end

    -- Caller gone (left the group or disconnected): elect a replacement and keep
    -- the draw going. Void only if nobody is left to take over.
    if not hostInGroup or not hostOnline then
        if not BM:MigrateHost(host) then
            BJ:Print("|cffff4444Bingo VOIDED: caller (" .. host .. ") left and no one can take over. No gold changes hands.|r")
            BM:ResetState()
            updateUI()
        end
    end
end

--[[
    CALLER MIGRATION (host swap)

    Deterministic pick: the first still-present, still-connected player in the
    shared card order, excluding the departed caller. Everyone computes the same
    answer, so only the elected player promotes itself; the rest adopt it via the
    HOST_SWAP it broadcasts.
]]

function BM:ElectNewHost(excludeHost)
    local BS = BJ.BingoState
    local myName = BJ:MyName()
    for _, name in ipairs(BS.playerOrder) do
        if name ~= excludeHost then
            local present, online = false, false
            if name == myName then
                present, online = true, true
            else
                local n = GetNumGroupMembers()
                for i = 1, n do
                    local unit = IsInRaid() and ("raid" .. i) or ("party" .. i)
                    if BJ:UnitFullName(unit) == name then
                        present = true
                        online = UnitIsConnected(unit)
                        break
                    end
                end
            end
            if present and online then return name end
        end
    end
    return nil
end

-- Caller is gone. Returns true if the game survives (we took over, or someone
-- else will), false if it must void.
function BM:MigrateHost(oldHost)
    local BS = BJ.BingoState
    if BS.phase == BS.PHASE.IDLE or BS.phase == BS.PHASE.SETTLEMENT then return false end

    local newHost = BM:ElectNewHost(oldHost)
    if not newHost then return false end

    BM:CancelDrawTicker()
    if newHost == BJ:MyName() then
        BM:BecomeMigratedHost()
    else
        BJ:Print("|cffffd700Bingo:|r caller is gone - " .. newHost .. " is taking over the draw...")
    end
    return true
end

-- We are the elected replacement caller: bump the epoch, announce it, rebuild
-- the seeded draw pool (we were a client and never built it) and resume drawing
-- from exactly where the last caller left off.
function BM:BecomeMigratedHost()
    local BS = BJ.BingoState
    local myName = BJ:MyName()

    BM.hostEpoch = (BM.hostEpoch or 0) + 1
    BM.isHost = true
    BM.currentHost = myName
    BM.tableOpen = true
    BS.hostName = myName

    if BJ.Leaderboard then BJ.Leaderboard:StartSession("bingo", myName) end

    BM:Send(MSG.HOST_SWAP, myName, BM.hostEpoch)
    BJ:Print("|cff00ff00You are now calling Bingo.|r Resuming the draw where it left off.")

    -- Same seed => same shuffle order; drawIndex is already synced from the calls
    -- we've been recording, so NextDraw continues at the right spot.
    if not BS.drawPool then BS:BuildDrawPool() end

    -- A line may already be complete on the last number called - settle it before
    -- drawing any more.
    if BM:CheckWinnersNow() then return end

    if BS.phase == BS.PHASE.DRAWING then
        BM:StartDrawTicker()
    end
    updateUI()
end

function BM:HandleHostSwap(senderName, parts)
    local newHost = parts[2]
    local epoch = tonumber(parts[3]) or 0
    if not newHost then return end
    if epoch < (BM.hostEpoch or 0) then return end  -- stale, ignore
    -- A same-epoch clash shouldn't happen (deterministic pick); if it does, the
    -- lexicographically lower name wins so everyone converges the same way.
    if epoch == (BM.hostEpoch or 0) and BM.currentHost and newHost ~= BM.currentHost
        and BM.currentHost < newHost then
        return
    end

    local myName = BJ:MyName()
    local wasHost = BM.isHost

    BM.hostEpoch = epoch
    BM.currentHost = newHost
    BM.isHost = (newHost == myName)
    BJ.BingoState.hostName = newHost

    if wasHost and newHost ~= myName then
        BM:CancelDrawTicker()
        if BJ.Leaderboard then BJ.Leaderboard:EndSession("bingo") end
        BJ:Print("|cffff8800" .. newHost .. " has taken over calling Bingo.|r")
    elseif not wasHost and newHost ~= myName then
        BJ:Print("|cffffd700Bingo caller is now " .. newHost .. ".|r")
    end

    updateUI()
end

-- Initialize on load
BM:Initialize()
