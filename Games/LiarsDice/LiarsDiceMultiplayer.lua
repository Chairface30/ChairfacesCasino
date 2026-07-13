--[[
    Chairface's Casino - LiarsDiceMultiplayer.lua
    Multiplayer communication for Liar's Dice.

    The host is the dealer and the referee. Each round it derives every
    player's dice from a private seed and whispers each player only their own
    hand, so the shared/broadcast state never carries dice faces and nobody
    can see anyone else's cup. Bidding is host-authoritative: players send
    BID/CHALLENGE intents, the host validates and broadcasts the resulting
    move that everyone applies, so no two clients can diverge.

    On a challenge the host reveals the seed and every hand at once; clients
    re-derive and verify, then the loser drops a die. A host that merely drops
    connection triggers the shared 2-minute recovery pause (resume on return,
    void on timeout); a host that fully LEAVES the group voids the match, since
    the hidden host-authoritative hands can't be rehosted by a temp host.
]]

local BJ = ChairfacesCasino
BJ.LiarsDiceMultiplayer = {}
local LDM = BJ.LiarsDiceMultiplayer

local CHANNEL_PREFIX = "CCLiarsDice"

local MSG = {
    TABLE_OPEN = "LDOPEN",       -- stake, version, onesWild(1/0), startDice
    TABLE_CLOSE = "LDCLOSE",
    JOIN = "LDJOIN",             -- version
    PLAYER_JOIN = "LDPJOIN",     -- name
    LEAVE = "LDLEAVE",
    ROUND = "LDROUND",           -- roundNum, firstBidder
    DICE = "LDDICE",             -- (whisper) roundNum, "d,d,d"  -> your own hand
    DICE_REQ = "LDDICEREQ",      -- (whisper to host) roundNum
    BID_INTENT = "LDBIDI",       -- q, face   (client -> host)
    BID_MADE = "LDBID",          -- player, q, face   (host -> group, authoritative)
    CHAL_INTENT = "LDCHALI",     -- (client -> host)
    REVEAL = "LDREVEAL",         -- roundNum, seed, diceStr, bidQ, bidFace,
                                 -- bidder, challenger, loser, count, onesWild(1/0)
    GAME_OVER = "LDOVER",        -- winner
    FORFEIT = "LDFF",            -- (client->host) I quit; (host->group) name forfeited
    HOST_SWAP = "LDHSWAP",       -- newHost  (host migration to keep the match alive)
    VERSION_REJECT = "LDVREJECT",
    SYNC_STATE = "LDSYNC",       -- Reserved for StateSync version injection
}

LDM.REVEAL_SECONDS = 4  -- how long the resolved challenge stays up before the next round

-- Shared multiplayer plumbing comes from GameComm. Liar's Dice overrides the
-- recovery flow: hidden host-authoritative hands can't be resumed by a temp
-- host, so the match is simply voided if the host leaves.
BJ.GameComm:Embed(LDM, {
    prefix = CHANNEL_PREFIX,
    game = "liarsdice",
    displayName = "Liar's Dice",
    MSG = MSG,
    getState = function() return BJ.LiarsDiceState end,
    getUI = function() return BJ.UI and BJ.UI.LiarsDice end,
    turnTimeoutWarning = "auto-raise",
})

function LDM:Initialize()
    self:SetupComm()
    BJ:Debug("Liar's Dice Multiplayer initialized with AceComm")
end

local function updateUI()
    if BJ.UI and BJ.UI.LiarsDice and BJ.UI.LiarsDice.UpdateDisplay then
        BJ.UI.LiarsDice:UpdateDisplay()
    end
end

--[[
    SERIALIZATION HELPERS
    Dice never travel over the "|" AceComm delimiter: a hand is "d,d,d" and a
    full reveal is "name=d,d,d;name=d,d,d". WoW character names are letters
    only, so ";", ",", "=" are safe field separators.
]]
local function diceToCsv(dice)
    return table.concat(dice or {}, ",")
end

local function csvToDice(s)
    local t = {}
    for n in tostring(s):gmatch("[^,]+") do
        t[#t + 1] = tonumber(n)
    end
    return t
end

local function serializeAllDice(diceByName, order)
    local segs = {}
    for _, name in ipairs(order) do
        local d = diceByName[name]
        if d then
            segs[#segs + 1] = name .. "=" .. diceToCsv(d)
        end
    end
    return table.concat(segs, ";")
end

local function deserializeAllDice(str)
    local byName = {}
    for seg in tostring(str):gmatch("[^;]+") do
        local name, dstr = seg:match("([^=]+)=(.+)")
        if name and dstr then
            byName[name] = csvToDice(dstr)
        end
    end
    return byName
end

--[[
    HOST ACTIONS
]]

function LDM:HostTable(stake, onesWild, startDice)
    local inTestMode = BJ.TestMode and BJ.TestMode.enabled
    if not IsInGroup() and not IsInRaid() and not inTestMode then
        BJ:Print("You must be in a party or raid to host Liar's Dice.")
        return false
    end

    stake = tonumber(stake)
    if not stake or stake < 1 then
        BJ:Print("Stake must be at least 1g.")
        return false
    end

    -- Don't stack games in the same group
    local Lobby = BJ.UI and BJ.UI.Lobby
    if Lobby and Lobby.IsOtherGameActive then
        local isActive, activeGame = Lobby:IsOtherGameActive("liarsdice")
        if isActive then
            BJ:Print("|cffff4444Cannot host - a " .. Lobby:GetGameName(activeGame) .. " game is already in progress.|r")
            return false
        end
    end

    local LD = BJ.LiarsDiceState
    if LD.phase ~= LD.PHASE.IDLE and LD.phase ~= LD.PHASE.SETTLEMENT then
        BJ:Print("A Liar's Dice match is already in progress.")
        return false
    end

    local myName = UnitName("player")
    LD:HostGame(myName, stake, onesWild, startDice)
    LDM.isHost = true
    LDM.currentHost = myName
    LDM.hostEpoch = 1
    LDM.tableOpen = true

    -- The table's fun/real status is fixed when it opens, so a migrated
    -- host settles under the ORIGINAL terms, not their own toggle
    LD.opener = myName
    LD.fakePlay = BJ.GameComm.LocalFakePlay()

    if BJ.Leaderboard then
        BJ.Leaderboard:StartSession("liarsdice", myName)
    end

    LDM:Send(MSG.TABLE_OPEN, stake, BJ.version, LD.onesWild and 1 or 0, LD.startDice,
        LD.fakePlay and "1" or "0")

    -- Remember the stake for the next host dialog
    if BJ.HostSettings then BJ.HostSettings:Set("liarsdiceStake", stake) end

    local gameLink = BJ:CreateGameLink("liarsdice", "Liar's Dice")
    BJ:Print(gameLink .. " table is open! Buy-in is |cffffd700" .. stake .. "g|r. Last player standing wins the pot!")

    updateUI()
    return true
end

-- Host begins the match (locks the lobby, deals round 1)
function LDM:StartGame()
    if not LDM.isHost then return false end

    local LD = BJ.LiarsDiceState
    local success, err = LD:StartMatch()
    if not success then
        BJ:Print(err or "Cannot start.")
        return false
    end

    BJ:Print("Liar's Dice match starting with " .. #LD.playerOrder .. " players!")
    LDM:BeginNewRound(1)
    return true
end

-- Host: deal a fresh round. Derives every hand from a private seed, whispers
-- each player their own dice, and announces the round to everyone.
function LDM:BeginNewRound(roundNum)
    local LD = BJ.LiarsDiceState
    if LD.phase == LD.PHASE.SETTLEMENT then return end

    local seed = (math.floor(GetTime() * 1000) % 2147483647) + math.random(1, 99999) + roundNum
    LD:BeginRound(roundNum, seed)

    local myName = UnitName("player")
    for _, name in ipairs(LD.playerOrder) do
        local p = LD.players[name]
        if p and p.alive and p.count > 0 and name ~= myName then
            LDM:SendWhisper(name, MSG.DICE, roundNum, diceToCsv(LD.allDice[name]))
        end
    end

    LDM:Send(MSG.ROUND, roundNum, LD.firstBidder)

    BJ:Print("|cffffd700Round " .. roundNum .. "|r - " .. LD:TotalDice() ..
        " dice in play. " .. (LD.firstBidder or "?") .. " opens the bidding.")

    updateUI()
    LDM:StartTurnTimer()
end

-- Host cancels / closes the table
function LDM:CloseTable()
    if not LDM.isHost then return end

    local LD = BJ.LiarsDiceState
    if LD.phase == LD.PHASE.BIDDING or LD.phase == LD.PHASE.REVEAL then
        BJ:Print("|cffff8800Liar's Dice cancelled mid-match - no gold changes hands.|r")
    end

    LDM:CancelTurnTimer()
    LDM:Send(MSG.TABLE_CLOSE)
    if BJ.Leaderboard then
        BJ.Leaderboard:EndSession("liarsdice")
    end
    LDM:ResetState()
    updateUI()
end

function LDM:ResetState()
    LDM:CancelTurnTimer()
    LDM.isHost = false
    LDM.currentHost = nil
    LDM.hostEpoch = 0
    LDM.tableOpen = false
    -- Clear any host-disconnect recovery bookkeeping too
    LDM.hostDisconnected = false
    LDM.originalHost = nil
    LDM.temporaryHost = nil
    LDM.recoveryStartTime = nil
    BJ.LiarsDiceState:Reset()
end

--[[
    CLIENT ACTIONS
]]

function LDM:RequestJoin()
    if LDM.hostVersion and not BJ:VersionsCompatible(LDM.hostVersion, BJ.version) then
        BJ:Print("|cffff4444Version mismatch!|r Host has v" .. LDM.hostVersion .. ", you have v" .. BJ.version)
        BJ:Print("Please update your addon to join this match.")
        return false
    end

    LDM:Send(MSG.JOIN, BJ.version)
    return true
end

-- Place a bid on my turn (host applies directly; clients send an intent)
function LDM:PlaceBid(q, face)
    local LD = BJ.LiarsDiceState
    local myName = UnitName("player")

    if LD.phase ~= LD.PHASE.BIDDING then return false end
    if LD:CurrentBidder() ~= myName then
        BJ:Print("|cffff8800It's not your turn.|r")
        return false
    end

    local ok, err = LD:IsBidLegal(q, face)
    if not ok then
        BJ:Print("|cffff8800" .. (err or "Illegal bid") .. "|r")
        return false
    end

    if LDM.isHost then
        LDM:ApplyBidAuthoritative(myName, q, face)
    else
        -- Stop our local turn timer while we wait for the host to confirm,
        -- so it can't fire a second auto-raise in the meantime
        LDM:CancelTurnTimer()
        LDM:Send(MSG.BID_INTENT, q, face)
    end
    return true
end

-- Call "Liar!" on my turn against the standing bid
function LDM:CallLiar()
    local LD = BJ.LiarsDiceState
    local myName = UnitName("player")

    if LD.phase ~= LD.PHASE.BIDDING or not LD.currentBid then return false end
    if LD:CurrentBidder() ~= myName then
        BJ:Print("|cffff8800It's not your turn.|r")
        return false
    end

    if LDM.isHost then
        LDM:ResolveChallengeAuthoritative(myName)
    else
        LDM:CancelTurnTimer()
        LDM:Send(MSG.CHAL_INTENT)
    end
    return true
end

-- Ask the host to (re-)send my hand (used after a reload/sync)
function LDM:RequestMyDice()
    local LD = BJ.LiarsDiceState
    if LDM.isHost or not LDM.currentHost then return end
    LDM:SendWhisper(LDM.currentHost, MSG.DICE_REQ, LD.roundNum)
end

--[[
    HOST-AUTHORITATIVE APPLICATION
]]

function LDM:ApplyBidAuthoritative(name, q, face)
    local LD = BJ.LiarsDiceState
    LD:ApplyBid(name, q, face)
    LDM:Send(MSG.BID_MADE, name, q, face)
    LDM:AnnounceBid(name, q, face)
    LDM:CancelTurnTimer()
    updateUI()
    LDM:StartTurnTimer()
end

function LDM:ResolveChallengeAuthoritative(challenger)
    local LD = BJ.LiarsDiceState
    local reveal = LD:ResolveChallenge(challenger)
    if not reveal then return end

    LDM:CancelTurnTimer()

    -- Tell everyone the full outcome (seed + all hands)
    LDM:Send(MSG.REVEAL, reveal.seed,
        serializeAllDice(reveal.dice, LD.playerOrder),
        reveal.bidQ, reveal.bidFace, reveal.bidder, reveal.challenger,
        reveal.loser, reveal.count, reveal.onesWild and 1 or 0, LD.roundNum)

    LD:ApplyReveal(reveal)
    LDM:AnnounceReveal(reveal)
    updateUI()

    local winner = LD:CheckMatchOver()
    if winner then
        LD:FinalizeSettlement(winner)
        LDM:Send(MSG.GAME_OVER, winner)
        LDM:AnnounceWinner(winner)
        if BJ.Leaderboard then
            BJ.Leaderboard:EndSession("liarsdice")
        end
        updateUI()
    else
        local nextRound = LD.roundNum + 1
        C_Timer.After(LDM.REVEAL_SECONDS, function()
            local S = BJ.LiarsDiceState
            if LDM.isHost and S.phase == S.PHASE.REVEAL then
                LDM:BeginNewRound(nextRound)
            end
        end)
    end
end

--[[
    ANNOUNCEMENTS
]]

function LDM:AnnounceBid(name, q, face)
    local LD = BJ.LiarsDiceState
    BJ:Debug(name .. " bids " .. LD:BidText({ q = q, face = face }))
end

function LDM:AnnounceReveal(reveal)
    local LD = BJ.LiarsDiceState
    local wildNote = reveal.onesWild and " (ones wild)" or ""
    BJ:Print(reveal.challenger .. " called Liar on " ..
        reveal.bidder .. "'s " .. LD:BidText({ q = reveal.bidQ, face = reveal.bidFace }) ..
        " - there were |cffffd700" .. reveal.count .. "|r" .. wildNote ..
        ". |cffff4444" .. reveal.loser .. "|r loses a die!")
    local lui = BJ.UI and BJ.UI.LiarsDice
    if lui and lui.frame and lui.frame:IsShown() then
        PlaySoundFile("Interface\\AddOns\\Chairfaces Casino\\Sounds\\dice.mp3", "SFX")
    end
    -- Trixie reacts to the challenge: a wince if it's YOUR die, otherwise the
    -- table-wide "somebody called LIAR!" drama.
    local Lobby = BJ.UI and BJ.UI.Lobby
    if Lobby then
        if reveal.loser == UnitName("player") then
            Lobby:PlayTrixieVoice("liarsdice_bluff")
        else
            Lobby:PlayTrixieVoice("liarsdice_challenge", { cd = 4 })
        end
    end
end

function LDM:AnnounceWinner(winner)
    BJ:Print("|cff00ff00" .. winner .. " wins Liar's Dice|r - last player with dice takes the pot!")
    local lui = BJ.UI and BJ.UI.LiarsDice
    if lui and lui.frame and lui.frame:IsShown() then
        PlaySoundFile("Interface\\AddOns\\Chairfaces Casino\\Sounds\\AirHorn.ogg", "Master")
    end
    -- Trixie voices the local player's result
    local Lobby = BJ.UI and BJ.UI.Lobby
    if Lobby then
        local me = UnitName("player")
        local LD = BJ.LiarsDiceState
        if winner == me then
            Lobby:PlayTrixieWoohooVoice()
        elseif LD.players and LD.players[me] then
            Lobby:PlayTrixieBadVoice()
        end
    end
end

--[[
    MESSAGE HANDLERS
]]

-- Host-authoritative broadcast types. If we are the current host and hear one of
-- these from someone else, a stale ex-host has surfaced (e.g. reconnected after a
-- migration). We re-assert our epoch so they stand down instead of both hosting.
local HOST_AUTHORITATIVE = {
    [MSG.TABLE_OPEN] = true,
    [MSG.ROUND] = true,
    [MSG.BID_MADE] = true,
    [MSG.REVEAL] = true,
    [MSG.GAME_OVER] = true,
}

function LDM:RouteMessage(msgType, sender, senderName, parts)
    -- A rival host is broadcasting. Re-assert our (higher-or-equal) epoch and
    -- ignore their message; the stale host adopts us via HandleHostSwap.
    -- Re-assert only while OUR match is live: a settled/idle ex-host (whose
    -- isHost persists until reset) must not shout down the next table someone
    -- else opens (same phase guard as High-Lo's transfer machinery).
    local LD = BJ.LiarsDiceState
    if LDM.isHost and HOST_AUTHORITATIVE[msgType] and senderName ~= UnitName("player")
        and LD.phase ~= LD.PHASE.IDLE and LD.phase ~= LD.PHASE.SETTLEMENT then
        LDM:Send(MSG.HOST_SWAP, UnitName("player"), LDM.hostEpoch or 1)
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
    elseif msgType == MSG.ROUND then
        self:HandleRound(senderName, parts)
    elseif msgType == MSG.DICE then
        self:HandleDice(senderName, parts)
    elseif msgType == MSG.DICE_REQ then
        self:HandleDiceReq(senderName, parts)
    elseif msgType == MSG.BID_INTENT then
        self:HandleBidIntent(senderName, parts)
    elseif msgType == MSG.BID_MADE then
        self:HandleBidMade(senderName, parts)
    elseif msgType == MSG.CHAL_INTENT then
        self:HandleChalIntent(senderName, parts)
    elseif msgType == MSG.REVEAL then
        self:HandleReveal(senderName, parts)
    elseif msgType == MSG.GAME_OVER then
        self:HandleGameOver(senderName, parts)
    elseif msgType == MSG.FORFEIT then
        self:HandleForfeit(senderName, parts)
    elseif msgType == MSG.HOST_SWAP then
        self:HandleHostSwap(senderName, parts)
    elseif msgType == MSG.VERSION_REJECT then
        self:HandleVersionReject(senderName, parts)
    end
end

function LDM:HandleTableOpen(senderName, parts)
    local stake = tonumber(parts[2]) or 0
    local hostVersion = parts[3]
    local onesWild = parts[4] ~= "0"
    local startDice = tonumber(parts[5])  -- nil from older hosts -> defaults to 3
    local fakeFlag = parts[6]             -- "1"/"0"; nil from pre-2.5.2 hosts

    local LD = BJ.LiarsDiceState
    LD:HostGame(senderName, stake, onesWild, startDice)

    -- Table terms as opened (nil fakePlay = unknown/legacy host: a migrated
    -- host then falls back to their own live setting, the old behavior)
    LD.opener = senderName
    LD.fakePlay = BJ.GameComm.ParseFakeFlag(fakeFlag)

    LDM.isHost = false
    LDM.currentHost = senderName
    LDM.hostEpoch = 1
    LDM.tableOpen = true
    LDM.hostVersion = hostVersion

    if hostVersion then
        BJ:OnPeerVersion(hostVersion, senderName)
    end

    local gameLink = BJ:CreateGameLink("liarsdice", "Liar's Dice")
    BJ:Print(senderName .. " opened " .. gameLink .. "! Buy-in is |cffffd700" .. stake .. "g|r." ..
        BJ.GameComm.FunTag(LD.fakePlay))
    PlaySoundFile("Interface\\AddOns\\Chairfaces Casino\\Sounds\\dice.mp3", "SFX")

    updateUI()
end

function LDM:HandleTableClose(senderName, parts)
    if senderName ~= LDM.currentHost then return end

    BJ:Print("Liar's Dice table closed.")
    LDM:ResetState()
    updateUI()
end

function LDM:HandleJoin(senderName, parts)
    if not LDM.isHost then return end

    local playerVersion = parts[2]
    if playerVersion then
        BJ:OnPeerVersion(playerVersion, senderName)
    end

    if playerVersion and not BJ:VersionsCompatible(playerVersion, BJ.version) then
        BJ:Print("|cffff8800" .. senderName .. " rejected - version mismatch|r (v" .. playerVersion .. " vs v" .. BJ.version .. ")")
        LDM:SendWhisper(senderName, MSG.VERSION_REJECT, BJ.version)
        return
    end

    local LD = BJ.LiarsDiceState
    local success, err = LD:AddPlayer(senderName)
    if success then
        BJ:Print(senderName .. " joined Liar's Dice (" .. #LD.playerOrder .. " players)")
        LDM:Send(MSG.PLAYER_JOIN, senderName)
        updateUI()
    else
        BJ:Debug("Liar's Dice join from " .. senderName .. " rejected: " .. (err or "?"))
    end
end

function LDM:HandlePlayerJoin(senderName, parts)
    if senderName ~= LDM.currentHost then return end

    local playerName = parts[2]
    local LD = BJ.LiarsDiceState
    if playerName and playerName ~= "" and not LD.players[playerName] then
        LD:AddPlayer(playerName)
    end

    local myName = UnitName("player")
    if playerName == myName then
        BJ:Print("|cff00ff00You're in!|r Waiting for the host to start the match.")
    end

    updateUI()
end

function LDM:HandleLeave(senderName, parts)
    if not LDM.isHost then return end

    local LD = BJ.LiarsDiceState
    if LD:RemovePlayer(senderName) then
        BJ:Print(senderName .. " left the Liar's Dice table.")
        updateUI()
    end
end

--[[
    QUIT / FORFEIT
    Any player may bail out at any time. In the lobby that's a plain leave; once
    the match is live it's a forfeit (the quitter drops their dice and the match
    plays on with whoever is left). The host is authoritative: clients ask, the
    host applies and echoes the result to everyone.
]]

-- Local player clicked Quit.
function LDM:RequestForfeit()
    local LD = BJ.LiarsDiceState
    local myName = UnitName("player")
    if not LD.players[myName] then return end

    if LDM.isHost then
        -- The host bailing: hand the table to another player so the match can
        -- continue; only cancel outright if nobody is left to take over.
        if LD.phase == LD.PHASE.LOBBY then
            LDM:CloseTable()
            return
        end
        if not LDM:AppointSuccessorAndLeave() then
            LDM:CloseTable()
        end
        return
    end

    if LD.phase == LD.PHASE.LOBBY then
        LDM:Send(MSG.LEAVE)
        LDM:ResetState()
        updateUI()
        return
    end

    -- Mid-match: ask the host to forfeit us.
    LDM:Send(MSG.FORFEIT, myName)
    BJ:Print("|cffff8800You forfeit the match.|r")
end

-- Host resolves a forfeit and tells everyone.
function LDM:ApplyForfeitAuthoritative(name)
    local LD = BJ.LiarsDiceState
    local result = LD:ForfeitPlayer(name)
    if not result then return end

    LDM:CancelTurnTimer()
    LDM:Send(MSG.FORFEIT, name)   -- authoritative echo; clients replicate
    BJ:Print("|cffff8800" .. name .. " forfeits Liar's Dice.|r")

    if result == "removed" then
        updateUI()
        return
    end

    if result == "gameover" then
        local winner = LD:CheckMatchOver()
        if winner then
            LD:FinalizeSettlement(winner)
            LDM:Send(MSG.GAME_OVER, winner)
            LDM:AnnounceWinner(winner)
            if BJ.Leaderboard then BJ.Leaderboard:EndSession("liarsdice") end
        end
        updateUI()
        return
    end

    -- Match continues (possibly with a new player on turn).
    updateUI()
    LDM:StartTurnTimer()
end

function LDM:HandleForfeit(senderName, parts)
    local LD = BJ.LiarsDiceState

    if LDM.isHost then
        -- A client asked to forfeit themselves (ignore our own echo).
        if senderName == UnitName("player") then return end
        LDM:ApplyForfeitAuthoritative(senderName)
        return
    end

    -- Non-host: only the host's authoritative echo is applied.
    if senderName ~= LDM.currentHost then return end
    local name = parts[2]
    if not name then return end

    LD:ForfeitPlayer(name)
    BJ:Print("|cffff8800" .. name .. " forfeits Liar's Dice.|r")
    LDM:CancelTurnTimer()
    updateUI()
    if LD.phase ~= LD.PHASE.SETTLEMENT and LD:AliveCount() > 1 then
        LDM:StartTurnTimer()
    end
end

function LDM:HandleRound(senderName, parts)
    if senderName ~= LDM.currentHost then return end

    local roundNum = tonumber(parts[2])
    local firstBidder = parts[3]
    if not roundNum then return end

    local LD = BJ.LiarsDiceState
    LD.firstBidder = firstBidder
    LD:BeginRound(roundNum, nil)  -- client: reset bidding, keep my own dice

    -- If our own hand didn't arrive (lost whisper), ask for it shortly
    local myName = UnitName("player")
    local p = LD.players[myName]
    if p and p.alive then
        C_Timer.After(1.0, function()
            local S = BJ.LiarsDiceState
            if S.phase == S.PHASE.BIDDING and S.roundNum == roundNum and S.myDiceRound ~= roundNum then
                LDM:RequestMyDice()
            end
        end)
    end

    updateUI()
    LDM:StartTurnTimer()
end

function LDM:HandleDice(senderName, parts)
    if senderName ~= LDM.currentHost then return end

    local roundNum = tonumber(parts[2])
    local dice = csvToDice(parts[3])
    if not roundNum then return end

    local LD = BJ.LiarsDiceState
    LD:SetMyDice(roundNum, dice)
    updateUI()
end

function LDM:HandleDiceReq(senderName, parts)
    if not LDM.isHost then return end

    local roundNum = tonumber(parts[2])
    local LD = BJ.LiarsDiceState
    if roundNum == LD.roundNum and LD.allDice and LD.allDice[senderName] then
        LDM:SendWhisper(senderName, MSG.DICE, roundNum, diceToCsv(LD.allDice[senderName]))
    end
end

function LDM:HandleBidIntent(senderName, parts)
    if not LDM.isHost then return end

    local LD = BJ.LiarsDiceState
    if LD.phase ~= LD.PHASE.BIDDING then return end
    if LD:CurrentBidder() ~= senderName then return end

    local q = tonumber(parts[2])
    local face = tonumber(parts[3])
    local ok = LD:IsBidLegal(q, face)
    if ok then
        LDM:ApplyBidAuthoritative(senderName, q, face)
    else
        BJ:Debug("Liar's Dice illegal bid intent from " .. senderName)
    end
end

function LDM:HandleBidMade(senderName, parts)
    if senderName ~= LDM.currentHost then return end

    local LD = BJ.LiarsDiceState
    if LD.phase ~= LD.PHASE.BIDDING then return end

    local name = parts[2]
    local q = tonumber(parts[3])
    local face = tonumber(parts[4])
    if not name or not q or not face then return end

    LD:ApplyBid(name, q, face)
    LDM:AnnounceBid(name, q, face)
    LDM:CancelTurnTimer()
    updateUI()
    LDM:StartTurnTimer()
end

function LDM:HandleChalIntent(senderName, parts)
    if not LDM.isHost then return end

    local LD = BJ.LiarsDiceState
    if LD.phase ~= LD.PHASE.BIDDING or not LD.currentBid then return end
    if LD:CurrentBidder() ~= senderName then return end

    LDM:ResolveChallengeAuthoritative(senderName)
end

function LDM:HandleReveal(senderName, parts)
    if senderName ~= LDM.currentHost then return end

    local LD = BJ.LiarsDiceState
    if LD.phase == LD.PHASE.REVEAL then return end  -- already applied

    local reveal = {
        seed = tonumber(parts[2]),
        dice = deserializeAllDice(parts[3]),
        bidQ = tonumber(parts[4]),
        bidFace = tonumber(parts[5]),
        bidder = parts[6],
        challenger = parts[7],
        loser = parts[8],
        count = tonumber(parts[9]),
        onesWild = parts[10] ~= "0",
    }

    LD:ApplyReveal(reveal)
    LDM:CancelTurnTimer()
    LDM:AnnounceReveal(reveal)
    updateUI()
end

function LDM:HandleGameOver(senderName, parts)
    if senderName ~= LDM.currentHost then return end

    local LD = BJ.LiarsDiceState
    if LD.phase == LD.PHASE.SETTLEMENT then return end

    local winner = parts[2]
    LD:FinalizeSettlement(winner)
    LDM:AnnounceWinner(winner)
    updateUI()
end

function LDM:HandleVersionReject(senderName, parts)
    local hostVersion = parts[2]
    BJ:Print("|cffff4444Your addon version is outdated!|r")
    BJ:Print("Host has v" .. (hostVersion or "?") .. ", you have v" .. BJ.version)
    BJ:Print("Please update Chairface's Casino to join this match.")
end

--[[
    TURN TIMER HOOKS (GameComm)
]]

function LDM:ShouldRunTurnTimer()
    local LD = BJ.LiarsDiceState
    local myName = UnitName("player")
    if LD.phase ~= LD.PHASE.BIDDING then return false end
    if LD:CurrentBidder() ~= myName then return false end
    local p = LD.players[myName]
    return p and p.alive
end

-- On timeout, make the smallest legal raise so an idle player never instantly
-- forfeits a die; if no raise is possible, call Liar.
function LDM:OnTurnTimeout()
    LDM:CancelTurnTimer()
    local LD = BJ.LiarsDiceState
    local myName = UnitName("player")
    if LD.phase ~= LD.PHASE.BIDDING or LD:CurrentBidder() ~= myName then return end

    local q, face = LD:MinimalRaise()
    if LD:IsBidLegal(q, face) then
        BJ:Print("|cffff8800Auto-raise:|r " .. LD:BidText({ q = q, face = face }))
        LDM:PlaceBid(q, face)
    elseif LD.currentBid then
        BJ:Print("|cffff8800Time's up - calling Liar!|r")
        LDM:CallLiar()
    end
end

--[[
    HOST-SIDE ACTOR WATCHDOG HOOKS (shared ticker lives in GameComm)
    The turn timer above only runs on the acting player's own client, so a
    hard-disconnected bidder would stall the match forever. The host shadows
    the turn and applies the same default the bidder's own timeout would
    have: the smallest legal raise, or Liar if no raise is possible.
]]

function LDM:GetCurrentActor()
    local LD = BJ.LiarsDiceState
    if LD.phase ~= LD.PHASE.BIDDING then return nil end
    local name = LD:CurrentBidder()
    local p = name and LD.players[name]
    if not p or not p.alive then return nil end
    return name
end

function LDM:OnActorTimeout(playerName)
    local LD = BJ.LiarsDiceState
    if LD.phase ~= LD.PHASE.BIDDING or LD:CurrentBidder() ~= playerName then return end

    local q, face = LD:MinimalRaise()
    if LD:IsBidLegal(q, face) then
        LDM:ApplyBidAuthoritative(playerName, q, face)
    elseif LD.currentBid then
        LDM:ResolveChallengeAuthoritative(playerName)
    end
end

--[[
    ROSTER WATCHING + HOST MIGRATION
    Liar's Dice does not depend on one specific host: every player's die count is
    public and a fresh host can re-deal the current round, so we HOST-SWAP rather
    than void when the host drops. A host that LEAVES the group is replaced at
    once; a host that merely disconnects gets the shared 2-minute recovery pause,
    and if they don't return we elect a replacement. A monotonically increasing
    epoch settles any split-brain if a stale ex-host reconnects (higher wins).
]]

function LDM:OnRosterUpdate()
    local LD = BJ.LiarsDiceState

    -- If we left the party entirely, reset our local game state
    if not IsInGroup() and not IsInRaid() then
        if LD.phase ~= LD.PHASE.IDLE then
            BJ:Debug("Liar's Dice: Left party, resetting local game state")
            LDM:ResetState()
            updateUI()
        end
        return
    end

    if not LDM.currentHost then return end
    if LDM.isHost and not LDM.hostDisconnected then return end
    if LD.phase == LD.PHASE.IDLE or LD.phase == LD.PHASE.SETTLEMENT then return end

    local host = LDM.currentHost
    local hostInGroup = UnitInParty(host) or UnitInRaid(host)
    local hostOnline = false
    if hostInGroup then
        local n = GetNumGroupMembers()
        for i = 1, n do
            local unit = IsInRaid() and ("raid" .. i) or ("party" .. i)
            if UnitName(unit) == host then
                hostOnline = UnitIsConnected(unit)
                break
            end
        end
    end

    -- Host left the group entirely: elect a replacement (void only if nobody is
    -- left to take over).
    if not hostInGroup then
        LDM:CancelTurnTimer()
        if not LDM:MigrateHost(host) then
            BJ:Print("|cffff4444Liar's Dice VOIDED: host (" .. host .. ") left and no one can take over. No gold changes hands.|r")
            LDM:VoidGame("Host left the group")
        end
        return
    end

    -- Host is in the group but offline: pause with the shared recovery popup.
    if not hostOnline and not LDM.hostDisconnected then
        LDM.hostDisconnected = true
        LDM.originalHost = host
        LDM.recoveryStartTime = time()
        LDM:CancelTurnTimer()
        BJ:Print("|cffff8800Liar's Dice host (" .. host .. ") disconnected!|r Match paused - 2 minutes for them to return before a new host takes over.")
        LDM:ShowRecoveryPopup(host, false)
        LDM:StartLocalRecoveryCountdown()
    elseif hostOnline and LDM.hostDisconnected then
        -- Host is back online and still authoritative: clear the pause locally.
        LDM:EndHostRecovery()
    end
end

-- Recovery grace ran out with the host still gone: swap to a new host instead
-- of voiding (GameComm calls this in place of VoidGame when it exists).
function LDM:OnRecoveryTimeout()
    local host = LDM.originalHost or LDM.currentHost
    LDM:EndHostRecoveryQuiet()
    if not LDM:MigrateHost(host) then
        BJ:Print("|cffff4444Liar's Dice voided - the host did not return and no one can take over.|r")
        LDM:VoidGame("Host did not return in time")
    end
end

-- Host came back within the grace period: close the pause and resume play.
function LDM:EndHostRecovery()
    if not LDM.hostDisconnected then return end
    BJ:Print("|cff00ff00" .. (LDM.originalHost or "The host") .. " reconnected. Resuming the match.|r")
    LDM:EndHostRecoveryQuiet()
    updateUI()
end

-- Clear the recovery pause without the "reconnected" chatter (used when a
-- migration supersedes the pause).
function LDM:EndHostRecoveryQuiet()
    if LDM.recoveryTimer then LDM.recoveryTimer:Cancel(); LDM.recoveryTimer = nil end
    if LDM.localRecoveryTimer then LDM.localRecoveryTimer:Cancel(); LDM.localRecoveryTimer = nil end
    LDM:CloseRecoveryPopup()
    LDM.hostDisconnected = false
    LDM.originalHost = nil
    LDM.temporaryHost = nil
    LDM.recoveryStartTime = nil
end

--[[
    HOST MIGRATION (host swap)
]]

-- Deterministic new-host pick: the first still-present, still-connected, alive
-- player in the shared player order, excluding the departed host. Everyone
-- computes the same answer, so only the elected player promotes itself.
function LDM:ElectNewHost(excludeHost)
    local LD = BJ.LiarsDiceState
    local myName = UnitName("player")
    for _, name in ipairs(LD.playerOrder) do
        local p = LD.players[name]
        if p and p.alive and name ~= excludeHost then
            local present, online = false, false
            if name == myName then
                present, online = true, true
            else
                local n = GetNumGroupMembers()
                for i = 1, n do
                    local unit = IsInRaid() and ("raid" .. i) or ("party" .. i)
                    if UnitName(unit) == name then
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

-- Current host is gone. Returns true if the match survives (we took over, or
-- someone else will), false if it must void.
function LDM:MigrateHost(oldHost)
    local LD = BJ.LiarsDiceState
    if LD.phase == LD.PHASE.IDLE or LD.phase == LD.PHASE.SETTLEMENT then return false end

    local newHost = LDM:ElectNewHost(oldHost)
    if not newHost then return false end

    if newHost == UnitName("player") then
        LDM:BecomeMigratedHost()
    else
        LDM:CancelTurnTimer()
        BJ:Print("|cffffd700Liar's Dice:|r host is gone - " .. newHost .. " is taking over the table...")
    end
    return true
end

-- We are the elected replacement: bump the epoch, announce it, and re-deal the
-- current round (fresh seed) so we legitimately hold every hidden hand.
function LDM:BecomeMigratedHost()
    local LD = BJ.LiarsDiceState
    local myName = UnitName("player")

    LDM.hostEpoch = (LDM.hostEpoch or 0) + 1
    LDM.isHost = true
    LDM.currentHost = myName
    LDM.tableOpen = true
    LD.hostName = myName

    if BJ.Leaderboard then BJ.Leaderboard:StartSession("liarsdice", myName) end

    LDM:Send(MSG.HOST_SWAP, myName, LDM.hostEpoch)
    BJ:Print("|cff00ff00You are now hosting Liar's Dice.|r Re-dealing the round for the players still in.")

    local roundNum = math.max(1, LD.roundNum or 1)
    LDM:BeginNewRound(roundNum)
end

-- Voluntary host quit while still in the group: nobody else sees a roster change,
-- so we must actively appoint a successor. We drop our own dice, forfeit to the
-- table, and directly name the next host (who re-deals on receipt). Returns false
-- if there is no one left to take over (caller closes the table instead).
function LDM:AppointSuccessorAndLeave()
    local LD = BJ.LiarsDiceState
    local myName = UnitName("player")

    -- Drop ourselves from the match first (we are still authoritative here).
    local result = LD:ForfeitPlayer(myName)
    if not result then return false end
    LDM:Send(MSG.FORFEIT, myName)
    LDM:CancelTurnTimer()

    -- If our leaving leaves only one player, the match is over - settle it right
    -- here (as the still-authoritative host) instead of handing off to a lone
    -- "winner" who would otherwise sit in a one-player table forever.
    if result == "gameover" then
        local winner = LD:CheckMatchOver()
        if winner then
            LD:FinalizeSettlement(winner)
            LDM:Send(MSG.GAME_OVER, winner)
            LDM:AnnounceWinner(winner)
            if BJ.Leaderboard then BJ.Leaderboard:EndSession("liarsdice") end
        end
        updateUI()
        return true
    end

    -- Match continues: appoint a successor to keep refereeing.
    local newHost = LDM:ElectNewHost(myName)
    if not newHost then
        -- Shouldn't happen (result was "eliminated", so 2+ remain), but if we
        -- somehow can't find anyone, don't strand the table.
        return false
    end

    -- Appoint the successor. Bump the epoch so this supersedes our own hosting.
    LDM.hostEpoch = (LDM.hostEpoch or 0) + 1
    LDM:Send(MSG.HOST_SWAP, newHost, LDM.hostEpoch)
    if BJ.Leaderboard then BJ.Leaderboard:EndSession("liarsdice") end

    -- Step down locally to a departed spectator.
    LDM.isHost = false
    LDM.currentHost = newHost
    LD.hostName = newHost
    BJ:Print("|cffff8800You forfeit and hand Liar's Dice hosting to " .. newHost .. ".|r")
    updateUI()
    return true
end

function LDM:HandleHostSwap(senderName, parts)
    local newHost = parts[2]
    local epoch = tonumber(parts[3]) or 0
    if not newHost then return end
    if epoch < (LDM.hostEpoch or 0) then return end  -- stale, ignore
    -- A same-epoch clash shouldn't happen (deterministic pick); if it does, the
    -- lexicographically lower name wins so everyone converges the same way.
    if epoch == (LDM.hostEpoch or 0) and LDM.currentHost and newHost ~= LDM.currentHost
        and LDM.currentHost < newHost then
        return
    end

    local myName = UnitName("player")
    local wasHost = LDM.isHost

    LDM.hostEpoch = epoch
    LDM.currentHost = newHost
    LDM.isHost = (newHost == myName)
    BJ.LiarsDiceState.hostName = newHost

    if newHost == myName and not wasHost then
        -- We were appointed host (a departing host named us). Take over the
        -- table and re-deal the current round so we hold every hidden hand.
        if BJ.Leaderboard then BJ.Leaderboard:StartSession("liarsdice", myName) end
        BJ:Print("|cff00ff00You are now hosting Liar's Dice.|r Re-dealing the round for the players still in.")
        LDM.tableOpen = true
        local LD = BJ.LiarsDiceState
        if LDM.hostDisconnected then LDM:EndHostRecoveryQuiet() end
        local roundNum = math.max(1, LD.roundNum or 1)
        LDM:BeginNewRound(roundNum)
        updateUI()
        return
    elseif wasHost and newHost ~= myName then
        LDM:CancelTurnTimer()
        if BJ.Leaderboard then BJ.Leaderboard:EndSession("liarsdice") end
        BJ:Print("|cffff8800" .. newHost .. " has taken over hosting Liar's Dice.|r")
    elseif not wasHost and newHost ~= myName then
        BJ:Print("|cffffd700Liar's Dice host is now " .. newHost .. ".|r")
    end

    if LDM.hostDisconnected then LDM:EndHostRecoveryQuiet() end
    updateUI()
end

-- Initialize on load
LDM:Initialize()
