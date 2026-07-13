--[[
    Chairface's Casino - CrashMultiplayer.lua
    Multiplayer communication for Crash

    Trust model: the host commits to a secret (hash broadcast at launch)
    and reveals it at the crash, so the crash point is fixed before the
    flight, hidden from every rider during it, and verifiable by every
    client at the reveal. Manual bail-outs are host-receipt-time
    authoritative (broadcast, so the whole table sees them); auto-bail
    targets resolve deterministically on every client with no messages.

    Host disconnect mid-flight cannot be recovered - only the host holds
    the secret - so the round voids immediately instead of using the
    2-minute GameComm recovery pause.

    A RIDER who disconnects mid-flight stays aboard: in the pot game a
    refund would beat losing, so pulling the cable can't be an escape
    hatch. Their auto-jump target still fires and can still win them
    the pot; without one they ride her into the ground.
]]

local BJ = ChairfacesCasino
BJ.CrashMultiplayer = {}
local CM = BJ.CrashMultiplayer

local CHANNEL_PREFIX = "CCCrash"

local MSG = {
    TABLE_OPEN = "ZOPEN",       -- Host opens table: ante, version
    TABLE_CLOSE = "ZCLOSE",     -- Host closes the table
    JOIN = "ZJOIN",             -- Rider antes in: version, target ("" = manual)
    JOIN_OK = "ZJOINOK",        -- Host confirms: name, target
    TARGET = "ZTARGET",         -- Rider updates auto-bail target pre-launch
    LAUNCH = "ZLAUNCH",         -- Host locks boarding: commit hash
    START = "ZSTART",           -- Flight begins: entropy roll
    CASHOUT = "ZCASH",          -- Rider pulls the ripcord (host arbitrates)
    CASHOUT_OK = "ZCASHOK",     -- Host confirms: name, mult, tick
    CRASH = "ZCRASH",           -- The explosion: secret (reveal), roll echo
    REFUND = "ZREFUND",         -- Host voids an offline rider's ante: name
    VOID_ROUND = "ZVOIDR",      -- Round unfinishable: antes void, back to boarding
    NEXT = "ZNEXT",             -- Host opens the next boarding round
    NEXT_HOST = "ZNEXTHOST",    -- A player claims the next flight as its new pilot/bank
    VERSION_REJECT = "ZVREJECT",
    SYNC_STATE = "ZSYNC",       -- Reserved for StateSync version injection
}

BJ.GameComm:Embed(CM, {
    prefix = CHANNEL_PREFIX,
    game = "crash",
    displayName = "Crash",
    MSG = MSG,
    getState = function() return BJ.CrashState end,
    getUI = function() return BJ.UI and BJ.UI.Crash end,
})

function CM:Initialize()
    self:SetupComm()
    BJ:Debug("Crash Multiplayer initialized with AceComm")
end

local function updateUI()
    if BJ.UI and BJ.UI.Crash and BJ.UI.Crash.UpdateDisplay then
        BJ.UI.Crash:UpdateDisplay()
    end
end

--[[
    HOST ACTIONS
]]

-- How long the everyone-jumped escape run lasts before the host calls it
-- a fly-away. Slightly longer than the client-side run animation needs to
-- clear the screen, so a surviving ship is visually gone when the round
-- ends - and the hidden crash tick gets every chance to catch her first.
CM.FLYAWAY_EXIT_SECS = 3.0

-- Seconds a pilot may read as offline (still in the group) before clients
-- void the round. UnitIsConnected flickers false during loading screens, so
-- voiding instantly would split the table on a mere blip.
CM.HOST_LOSS_GRACE = 15

function CM:HostTable(ante)
    local inTestMode = BJ.TestMode and BJ.TestMode.enabled
    if not IsInGroup() and not IsInRaid() and not inTestMode then
        BJ:Print("You must be in a party or raid to host Crash.")
        return false
    end

    ante = tonumber(ante)
    if not ante or ante < 1 then
        BJ:Print("Ante must be at least 1g.")
        return false
    end

    local Lobby = BJ.UI and BJ.UI.Lobby
    if Lobby and Lobby.IsOtherGameActive then
        local isActive, activeGame = Lobby:IsOtherGameActive("crash")
        if isActive then
            BJ:Print("|cffff4444Cannot host - a " .. Lobby:GetGameName(activeGame) .. " game is already in progress.|r")
            return false
        end
    end

    local CS = BJ.CrashState
    if CS.phase ~= CS.PHASE.IDLE and CS.phase ~= CS.PHASE.SETTLEMENT then
        BJ:Print("A Crash table is already open.")
        return false
    end

    local myName = UnitName("player")
    CS:HostGame(myName, ante)
    CM.isHost = true
    CM.currentHost = myName
    CM.tableOpen = true

    -- Table terms are fixed at open so riders see fun/real up front
    CS.fakePlay = BJ.GameComm.LocalFakePlay()

    if BJ.Leaderboard then
        BJ.Leaderboard:StartSession("crash", myName)
    end

    CM:Send(MSG.TABLE_OPEN, ante, BJ.version, CS.fakePlay and "1" or "0")

    -- Remember the ante for the next host dialog
    if BJ.HostSettings then BJ.HostSettings:Set("crashAnte", ante) end

    local gameLink = BJ:CreateGameLink("crash", "Crash")
    BJ:Print(gameLink .. " is boarding! |cffffd700" .. ante ..
        "g|r a seat into the pot - the last one to jump takes it all.")

    updateUI()
    return true
end

-- Host closes boarding and launches: commit the secret's hash, then take
-- off immediately. The fate is sealed at this moment and revealed (and
-- verified by every client) at the crash.
function CM:Launch()
    if not CM.isHost then return false end

    local CS = BJ.CrashState
    if CS.phase ~= CS.PHASE.BOARDING then return false end
    if CS:RiderCount() == 0 then
        BJ:Print("Nobody is aboard - nothing to fly for.")
        return false
    end

    -- The secret only this client ever holds (until the reveal)
    CM.secret = tostring(math.random(1, 2147483646)) .. "-" ..
        tostring(math.floor(GetTime() * 1000) % 2147483647) .. "-" ..
        tostring(math.random(1, 2147483646))
    local commit = CS:HashString(CM.secret)

    CS:BeginLaunch(commit)
    CM:Send(MSG.LAUNCH, commit)
    CM:BeginFlight()

    updateUI()
    return true
end

-- Host: fate sealed - take off. The wire format keeps the entropy field
-- from the old /roll flow (always 0 now) so START stays stable.
function CM:BeginFlight()
    local CS = BJ.CrashState
    if CS.phase ~= CS.PHASE.LAUNCHING or not CM.isHost then return end

    local _, point, tick = CS:ComputeCrash(CM.secret, 0)
    CM.crashPointSecret = point   -- host-side knowledge only
    CM.crashTickSecret = tick

    CS:StartFlight(0)
    CS.flyAway = nil
    CM:Send(MSG.START, 0)
    BJ:Print("|cff00ff00LIFTOFF!|r She WILL blow - last one out wins the pot!")

    CM:StartFlightTicker()
    if BJ.UI and BJ.UI.Crash and BJ.UI.Crash.OnFlightStart then
        BJ.UI.Crash:OnFlightStart()
    end
    updateUI()
end

-- Host ticker: applies deterministic auto-bails as they come due and
-- fires the explosion at the crash tick. Runs regardless of UI state.
-- Also owns the FLY-AWAY call: once NOBODY is left aboard (and someone
-- actually rode this flight), she makes her escape run - but only if the
-- ship stays verifiably empty for the WHOLE run does the round end as a
-- fly-away. The crash tick is checked first every pass, so the hidden
-- explosion gets every chance to catch her on screen (the close call).
function CM:StartFlightTicker()
    if CM.flightTicker then CM.flightTicker:Cancel() end
    CM.escapeRunStart = nil
    CM.flightTicker = C_Timer.NewTicker(0.1, function()
        local CS = BJ.CrashState
        if CS.phase ~= CS.PHASE.FLIGHT or not CM.isHost then
            if CM.flightTicker then CM.flightTicker:Cancel() CM.flightTicker = nil end
            return
        end
        CM:ApplyDueAutoCashouts()
        if CS:CurrentTick() >= (CM.crashTickSecret or 0) then
            CM.flightTicker:Cancel()
            CM.flightTicker = nil
            CM:DoCrash()
            return
        end
        if CS:RiderCount() > 0 and CM:CountAboard() == 0 then
            CM.escapeRunStart = CM.escapeRunStart or GetTime()
            if GetTime() - CM.escapeRunStart >= CM.FLYAWAY_EXIT_SECS then
                CM.flightTicker:Cancel()
                CM.flightTicker = nil
                CM:DoCrash(true)
            end
        else
            CM.escapeRunStart = nil
        end
    end)
end

-- Clients run a slow ticker for the same duties (auto-bail feedback and
-- the no-crash-signal watchdog) so neither depends on the window being open.
function CM:StartClientFlightTicker()
    if CM.clientTicker then CM.clientTicker:Cancel() end
    CM.clientTicker = C_Timer.NewTicker(1, function()
        local CS = BJ.CrashState
        if CS.phase ~= CS.PHASE.FLIGHT then
            if CM.clientTicker then CM.clientTicker:Cancel() CM.clientTicker = nil end
            return
        end
        CM:ApplyDueAutoCashouts()
        CM:CheckFlightWatchdog()
    end)
end

-- Fire any auto targets the current tick has reached (idempotent; safe to
-- call from tickers and the UI's OnUpdate alike).
function CM:ApplyDueAutoCashouts()
    local CS = BJ.CrashState
    if CS.phase ~= CS.PHASE.FLIGHT then return end
    -- never fire an auto AT/past the crash tick the host already knows about
    local tick = CS:CurrentTick()
    if CM.isHost and CM.crashTickSecret and tick >= CM.crashTickSecret then return end
    local fired = CS:ApplyAutoCashouts(tick)
    for _, name in ipairs(fired) do
        local p = CS.players[name]
        if p and p.cashedOut then
            CM:ApplyCashoutFX(name, p.cashedOut.mult)
        end
    end
    if #fired > 0 then updateUI() end
end

-- Trixie voices the local player's result (the pilot has no stake)
function CM:PlayResultVoice()
    local Lobby = BJ.UI and BJ.UI.Lobby
    local CS = BJ.CrashState
    if not Lobby or not CS.settlements then return end
    local me = UnitName("player")
    local net = CS.settlements[me]
    if net and net > 0 then
        Lobby:PlayTrixieVoice("crash_bail")    -- bailed in time / took the pot
    elseif net and net < 0 then
        Lobby:PlayTrixieVoice("crash_boom")    -- rode her into the ground
    end
end

function CM:DoCrash(flyaway)
    local CS = BJ.CrashState
    if not CM.isHost or not CM.secret then return end

    -- A fly-away ending is only legal with an EMPTY ship: if anyone is
    -- still aboard, whatever asked for it was wrong - she explodes on
    -- schedule instead, no matter who asked.
    if flyaway and CM:CountAboard() > 0 then flyaway = nil end

    local secret = CM.secret
    CM.secret = nil
    CM.crashPointSecret = nil
    CM.crashTickSecret = nil

    -- field 4: fly-away flag (everyone jumped; she leaves the screen
    -- instead of exploding - the reveal still rides the wire for verify)
    CS.flyAway = flyaway and true or nil
    CM:Send(MSG.CRASH, secret, CS.entropyRoll or 0, flyaway and 1 or 0)
    if CS:Crash(secret, CS.entropyRoll) then
        BJ:Print(CS:GetSettlementText())
        CM:PlayResultVoice()
        local ui = BJ.UI and BJ.UI.Crash
        if ui then
            if CS.flyAway and ui.OnFlyAway then ui:OnFlyAway()
            elseif ui.OnCrash then ui:OnCrash() end
        end
        updateUI()
    end
end

-- Open the next flight at the same table. Anyone can pull this lever -
-- and whoever pulls it becomes the next flight's pilot: they run the
-- commit/reveal and press LAUNCH (the pot settles rider-to-rider; the
-- pilot banks nothing). The current host
-- keeps the chair if they click it themselves. Claims are ARBITRATED by
-- the sitting host (first claim received wins, confirmed in the NEXT
-- broadcast), so two players smashing the button never split the table.
function CM:NextRound()
    local CS = BJ.CrashState

    if not CM.isHost then
        if CS.phase ~= CS.PHASE.SETTLEMENT then return false end
        CM:Send(MSG.NEXT_HOST)
        BJ:Print("Claiming the pilot's chair for the next flight...")
        return true
    end

    local success, err = CS:NextRound()
    if not success then
        BJ:Print(err or "Cannot open the next round.")
        return false
    end

    CM:Send(MSG.NEXT, "")
    BJ:Print("Crash: next flight is boarding!")
    updateUI()
    return true
end

-- Everyone (claimer included) runs the same takeover: fresh boarding
-- round with the claimer in the pilot's chair.
function CM:ApplyHostTakeover(newHost)
    local CS = BJ.CrashState
    if CS.phase ~= CS.PHASE.SETTLEMENT then return false end
    if not CS:NextRound() then return false end

    local myName = UnitName("player")
    CS.hostName = newHost
    CM.currentHost = newHost
    CM.isHost = (newHost == myName)
    CM.pendingCashout = false

    if CM.isHost then
        if BJ.Leaderboard then
            BJ.Leaderboard:StartSession("crash", myName)
        end
        BJ:Print("|cff00ff00You have the con!|r Next flight is boarding - you're the pilot. LAUNCH when ready.")
    else
        BJ:Print("Crash: " .. newHost .. " takes the con - next flight is boarding, " ..
            newHost .. " is the pilot!")
    end
    updateUI()
    return true
end

function CM:CloseTable()
    if not CM.isHost then return end

    local CS = BJ.CrashState
    if CS.phase == CS.PHASE.FLIGHT or CS.phase == CS.PHASE.LAUNCHING then
        BJ:Print("|cffff8800Crash closed mid-flight - no gold changes hands.|r")
    end

    CM:Send(MSG.TABLE_CLOSE)
    if BJ.Leaderboard then
        BJ.Leaderboard:EndSession("crash")
    end
    CM:ResetState()
    updateUI()
end

function CM:ResetState()
    if CM.flightTicker then
        CM.flightTicker:Cancel()
        CM.flightTicker = nil
    end
    if CM.clientTicker then
        CM.clientTicker:Cancel()
        CM.clientTicker = nil
    end
    if CM.hostLossTimer then
        CM.hostLossTimer:Cancel()
        CM.hostLossTimer = nil
    end
    CM.secret = nil
    CM.crashPointSecret = nil
    CM.crashTickSecret = nil
    CM.escapeRunStart = nil
    CM.pendingCashout = false
    CM.isHost = false
    CM.currentHost = nil
    CM.tableOpen = false
    BJ.CrashState:Reset()
    if BJ.UI and BJ.UI.Crash and BJ.UI.Crash.StopFlight then
        BJ.UI.Crash:StopFlight()
    end
end

--[[
    CLIENT ACTIONS
]]

-- Ante in, with an optional auto-bail target
function CM:RequestJoin(target)
    -- The pilot rides too: the host joins locally and broadcasts the same
    -- JOIN_OK every other rider gets. (The fate lives on the host's
    -- machine either way; the addon never displays it to them.)
    if CM.isHost then
        local CS = BJ.CrashState
        local myName = UnitName("player")
        target = CS:CleanTarget(target)
        local success, err = CS:AddPlayer(myName, target)
        if success then
            local p = CS.players[myName]
            BJ:Print("|cff00ff00You're aboard your own zeppelin!|r Outlast the table - she WILL blow.")
            CM:Send(MSG.JOIN_OK, myName, p.target or "")
            updateUI()
            return true
        end
        if err then BJ:Print("|cffff8800" .. err .. "|r") end
        return false
    end

    if CM.hostVersion and not BJ:VersionsCompatible(CM.hostVersion, BJ.version) then
        BJ:Print("|cffff4444Version mismatch!|r Host has v" .. CM.hostVersion .. ", you have v" .. BJ.version)
        BJ:Print("Please update your addon to join this table.")
        return false
    end

    local CS = BJ.CrashState
    target = CS:CleanTarget(target)
    CM:Send(MSG.JOIN, BJ.version, target or "")
    return true
end

-- Change my auto-bail target (boarding only); broadcast so every book matches
function CM:SetTarget(target)
    local CS = BJ.CrashState
    local myName = UnitName("player")
    local success, err = CS:SetTarget(myName, target)
    if not success then
        if err then BJ:Print("|cffff8800" .. err .. "|r") end
        return false
    end
    local p = CS.players[myName]
    CM:Send(MSG.TARGET, p.target or "")
    updateUI()
    return true
end

-- THE BUTTON. Manual bail-out: the host's receipt time decides the payout.
function CM:CashOut()
    local CS = BJ.CrashState
    local myName = UnitName("player")

    if CS.phase ~= CS.PHASE.FLIGHT then return false end
    local p = CS.players[myName]
    if not p or p.cashedOut or p.refunded then return false end
    if CM.pendingCashout then return false end

    if CM.isHost then
        -- Test-mode host riding their own zeppelin arbitrates locally
        CM:HostArbitrateCashout(myName)
        return true
    end

    CM.pendingCashout = true
    CM:Send(MSG.CASHOUT)
    updateUI()
    return true
end

-- Host applies a manual bail at ITS current tick (receipt time)
function CM:HostArbitrateCashout(playerName)
    local CS = BJ.CrashState
    if not CM.isHost or CS.phase ~= CS.PHASE.FLIGHT then return end

    local t = CS:CurrentTick()
    if t >= (CM.crashTickSecret or 0) then return end   -- crash beat the message

    local mult = CS:MultiplierAt(t)
    if CS:CashOut(playerName, mult, t) then
        CM:Send(MSG.CASHOUT_OK, playerName, mult, t)
        CM:ApplyCashoutFX(playerName, mult)
        updateUI()
    end
end

-- Shared jump feedback (chat line + UI hook). No gold is realized at the
-- jump - it only stakes your claim; the pot settles at the explosion.
function CM:ApplyCashoutFX(playerName, mult)
    local CS = BJ.CrashState
    BJ:Print("|cff00ff00" .. playerName .. " parachutes out at " .. CS:MetersFor(mult) ..
        "m!|r Still aboard: " .. CM:CountAboard())
    if BJ.UI and BJ.UI.Crash and BJ.UI.Crash.OnBailOut then
        BJ.UI.Crash:OnBailOut(playerName, mult)
    end

    -- When this was the LAST rider out, the escape run + fly-away are
    -- handled by the host's flight ticker (StartFlightTicker): it
    -- re-verifies the ship is empty on every pass for the whole run, so
    -- a fly-away can never end a round while anyone is still aboard.
end

-- Riders still on the ship (not jumped, not voided)
function CM:CountAboard()
    local CS = BJ.CrashState
    local n = 0
    for _, name in ipairs(CS.playerOrder) do
        local p = CS.players[name]
        if p and not p.cashedOut and not p.refunded then n = n + 1 end
    end
    return n
end

--[[
    MESSAGE HANDLERS
]]

function CM:RouteMessage(msgType, sender, senderName, parts)
    if msgType == MSG.TABLE_OPEN then
        self:HandleTableOpen(senderName, parts)
    elseif msgType == MSG.TABLE_CLOSE then
        self:HandleTableClose(senderName, parts)
    elseif msgType == MSG.JOIN then
        self:HandleJoin(senderName, parts)
    elseif msgType == MSG.JOIN_OK then
        self:HandleJoinOk(senderName, parts)
    elseif msgType == MSG.TARGET then
        self:HandleTarget(senderName, parts)
    elseif msgType == MSG.LAUNCH then
        self:HandleLaunch(senderName, parts)
    elseif msgType == MSG.START then
        self:HandleStart(senderName, parts)
    elseif msgType == MSG.CASHOUT then
        self:HandleCashout(senderName, parts)
    elseif msgType == MSG.CASHOUT_OK then
        self:HandleCashoutOk(senderName, parts)
    elseif msgType == MSG.CRASH then
        self:HandleCrash(senderName, parts)
    elseif msgType == MSG.REFUND then
        self:HandleRefund(senderName, parts)
    elseif msgType == MSG.VOID_ROUND then
        self:HandleVoidRound(senderName, parts)
    elseif msgType == MSG.NEXT then
        self:HandleNext(senderName, parts)
    elseif msgType == MSG.NEXT_HOST then
        self:HandleNextHost(senderName, parts)
    elseif msgType == MSG.VERSION_REJECT then
        self:HandleVersionReject(senderName, parts)
    end
end

function CM:HandleTableOpen(senderName, parts)
    local ante = tonumber(parts[2]) or 0
    local hostVersion = parts[3]

    local CS = BJ.CrashState
    CS:HostGame(senderName, ante)

    -- Table terms as opened (nil = legacy host, terms unknown)
    CS.fakePlay = BJ.GameComm.ParseFakeFlag(parts[4])

    CM.isHost = false
    CM.currentHost = senderName
    CM.tableOpen = true
    CM.hostVersion = hostVersion
    CM.pendingCashout = false

    if hostVersion then
        BJ:OnPeerVersion(hostVersion, senderName)
    end

    local gameLink = BJ:CreateGameLink("crash", "Crash")
    BJ:Print(senderName .. "'s " .. gameLink .. " is boarding! Ante is |cffffd700" .. ante .. "g|r a seat." ..
        BJ.GameComm.FunTag(CS.fakePlay))
    PlaySoundFile("Interface\\AddOns\\Chairfaces Casino\\Sounds\\chips.ogg", "SFX")

    updateUI()
end

function CM:HandleTableClose(senderName, parts)
    if senderName ~= CM.currentHost then return end

    BJ:Print("Crash table closed.")
    CM:ResetState()
    updateUI()
end

function CM:HandleJoin(senderName, parts)
    if not CM.isHost then return end

    local playerVersion = parts[2]
    local target = parts[3]
    if playerVersion then
        BJ:OnPeerVersion(playerVersion, senderName)
    end

    if playerVersion and not BJ:VersionsCompatible(playerVersion, BJ.version) then
        BJ:Print("|cffff8800" .. senderName .. " rejected - version mismatch|r (v" .. playerVersion .. " vs v" .. BJ.version .. ")")
        CM:SendWhisper(senderName, MSG.VERSION_REJECT, BJ.version)
        return
    end

    local CS = BJ.CrashState
    local success, err = CS:AddPlayer(senderName, target)
    if success then
        local p = CS.players[senderName]
        BJ:Print(senderName .. " boarded the zeppelin" ..
            (p.target and (" (auto-jump " .. CS:MetersFor(p.target) .. "m)") or "") .. ".")
        CM:Send(MSG.JOIN_OK, senderName, p.target or "")
        if BJ.StateSync then
            BJ.StateSync:SendFullState("crash", senderName, BJ.StateSync:BuildFullState("crash"))
        end
        updateUI()
    else
        BJ:Debug("Crash join from " .. senderName .. " rejected: " .. (err or "?"))
    end
end

function CM:HandleJoinOk(senderName, parts)
    if senderName ~= CM.currentHost then return end

    local playerName = parts[2]
    local target = parts[3]
    local CS = BJ.CrashState
    if playerName and not CS.players[playerName] then
        CS:AddPlayer(playerName, target)
    end

    local myName = UnitName("player")
    if playerName == myName then
        BJ:Print("|cff00ff00You're aboard!|r Outlast the table: jump AFTER everyone else but BEFORE she blows.")
        PlaySoundFile("Interface\\AddOns\\Chairfaces Casino\\Sounds\\chips.ogg", "SFX")
    end

    updateUI()
end

function CM:HandleTarget(senderName, parts)
    local CS = BJ.CrashState
    if not CS.players[senderName] then return end
    CS:SetTarget(senderName, parts[2])
    updateUI()
end

function CM:HandleLaunch(senderName, parts)
    if senderName ~= CM.currentHost then return end

    local CS = BJ.CrashState
    if CS:BeginLaunch(parts[2]) then
        BJ:Print("|cffffd700Boarding closed!|r Fate is sealed - liftoff imminent.")
        -- If neither START nor the host's fizzle-reopen ever arrives,
        -- don't sit in LAUNCHING forever
        C_Timer.After(30, function()
            local S = BJ.CrashState
            if S.phase == S.PHASE.LAUNCHING and not CM.isHost then
                S.phase = S.PHASE.BOARDING
                S.commit = nil
                BJ:Print("|cffff8800Crash: the launch never happened - boarding reopened.|r")
                updateUI()
            end
        end)
        updateUI()
    end
end

function CM:HandleStart(senderName, parts)
    if senderName ~= CM.currentHost then return end

    local CS = BJ.CrashState
    -- Missed the LAUNCH broadcast: catch up (no commit means the reveal
    -- cannot be verified on this client, but the round still resolves)
    if CS.phase == CS.PHASE.BOARDING then
        CS:BeginLaunch(nil)
    end
    if CS:StartFlight(parts[2]) then
        CS.flyAway = nil
        BJ:Print("|cff00ff00LIFTOFF!|r She WILL blow - last one out wins the pot!")
        CM:StartClientFlightTicker()
        if BJ.UI and BJ.UI.Crash and BJ.UI.Crash.OnFlightStart then
            BJ.UI.Crash:OnFlightStart()
        end
        updateUI()
    end
end

function CM:HandleCashout(senderName, parts)
    if not CM.isHost then return end
    CM:HostArbitrateCashout(senderName)
end

function CM:HandleCashoutOk(senderName, parts)
    if senderName ~= CM.currentHost then return end

    local playerName = parts[2]
    local mult = tonumber(parts[3])
    local tick = tonumber(parts[4])
    if not playerName or not mult or not tick then return end

    local CS = BJ.CrashState
    if CS:CashOut(playerName, mult, tick) then
        if playerName == UnitName("player") then
            CM.pendingCashout = false
        end
        CM:ApplyCashoutFX(playerName, mult)
        updateUI()
    end
end

function CM:HandleCrash(senderName, parts)
    if senderName ~= CM.currentHost then return end

    local CS = BJ.CrashState
    local secret = parts[2]
    local roll = parts[3]
    CS.flyAway = (tonumber(parts[4]) == 1) or nil
    CM.pendingCashout = false

    if CS:Crash(secret, roll) then
        BJ:Print(CS:GetSettlementText())
        CM:PlayResultVoice()
        if CS.verifyFailed then
            PlaySoundFile("Interface\\AddOns\\Chairfaces Casino\\Sounds\\AirHorn.ogg", "Master")
        end
        local ui = BJ.UI and BJ.UI.Crash
        if ui then
            if CS.flyAway and ui.OnFlyAway then ui:OnFlyAway()
            elseif ui.OnCrash then ui:OnCrash() end
        end
        updateUI()
    end
end

function CM:HandleRefund(senderName, parts)
    if senderName ~= CM.currentHost then return end

    local playerName = parts[2]
    local CS = BJ.CrashState
    if playerName and CS:Refund(playerName) then
        BJ:Print("|cff888888" .. playerName .. " disconnected - their ante is voided.|r")
        updateUI()
    end
end

function CM:HandleVoidRound(senderName, parts)
    if senderName ~= CM.currentHost then return end

    local CS = BJ.CrashState
    local keepPlayers = parts[2] == "1"
    CM.pendingCashout = false
    if keepPlayers then
        -- Launch fizzled: back to boarding with the same riders
        if CS.phase == CS.PHASE.LAUNCHING then
            CS.phase = CS.PHASE.BOARDING
            CS.commit = nil
            BJ:Print("|cffff8800Crash: the launch never happened - boarding reopened.|r")
        end
    else
        CS:VoidRound(true)
        BJ:Print("|cffff8800Crash: round VOIDED - all antes returned. Boarding reopened.|r")
    end
    updateUI()
end

-- NEXT from the sitting host: either they keep the chair (empty field)
-- or they're confirming a claimed takeover (field = the new pilot).
function CM:HandleNext(senderName, parts)
    if senderName ~= CM.currentHost then return end

    local CS = BJ.CrashState
    local newHost = parts[2]
    if newHost and newHost ~= "" then
        CM:ApplyHostTakeover(newHost)
    elseif CS:NextRound() then
        BJ:Print("Crash: next flight is boarding!")
        updateUI()
    end
end

-- A claim for the pilot's chair. Only the sitting host arbitrates: the
-- first claim received wins; the phase flip to boarding makes every
-- later claim fall through the SETTLEMENT check.
function CM:HandleNextHost(senderName, parts)
    if not CM.isHost then return end
    local CS = BJ.CrashState
    if CS.phase ~= CS.PHASE.SETTLEMENT then return end
    CM:Send(MSG.NEXT, senderName)
    CM:ApplyHostTakeover(senderName)
end

function CM:HandleVersionReject(senderName, parts)
    local hostVersion = parts[2]
    BJ:Print("|cffff4444Your addon version is outdated!|r")
    BJ:Print("Host has v" .. (hostVersion or "?") .. ", you have v" .. BJ.version)
    BJ:Print("Please update Chairface's Casino to join this table.")
end

--[[
    ROSTER WATCHING (overrides the GameComm card-game recovery flow)

    Only the host holds the secret, so a lost host mid-round can never be
    recovered - the round voids immediately, no 2-minute pause. A RIDER
    lost mid-flight stays aboard (see the header note: refunding them
    would make disconnecting a free escape from a losing pot).
]]

function CM:OnRosterUpdate()
    local CS = BJ.CrashState
    local myName = UnitName("player")

    -- If we left the party entirely, reset our local game state
    if not IsInGroup() and not IsInRaid() then
        if CS.phase ~= CS.PHASE.IDLE then
            BJ:Debug("Crash: Left party, resetting local game state")
            CM:ResetState()
            updateUI()
        end
        return
    end

    if CS.phase == CS.PHASE.IDLE or CS.phase == CS.PHASE.SETTLEMENT then return end

    -- Host watch (clients only). Leaving the group is final and voids at
    -- once; a mere OFFLINE reading gets a short debounce first, because
    -- UnitIsConnected can flicker false during the pilot's loading screens -
    -- voiding on a blip would split the table (clients void, pilot flies on
    -- and settles alone). A real disconnect mid-flight can never finish
    -- anyway (the pilot's reload loses the secret and voids on rejoin).
    local host = CM.currentHost
    if host and host ~= myName then
        local inGroup = UnitInParty(host) or UnitInRaid(host)
        local online = false
        if inGroup then
            local numMembers = GetNumGroupMembers()
            for i = 1, numMembers do
                local unit = IsInRaid() and ("raid" .. i) or ("party" .. i)
                if UnitName(unit) == host then
                    online = UnitIsConnected(unit)
                    break
                end
            end
        end
        if not inGroup then
            BJ:Print("|cffff4444Crash VOIDED: the pilot (" .. host ..
                ") is gone. No gold changes hands.|r")
            CM:ResetState()
            updateUI()
            return
        end
        if not online then
            if not CM.hostLossTimer then
                CM.hostLossTimer = C_Timer.NewTimer(CM.HOST_LOSS_GRACE, function()
                    CM.hostLossTimer = nil
                    local CS2 = BJ.CrashState
                    if CS2.phase == CS2.PHASE.IDLE or CS2.phase == CS2.PHASE.SETTLEMENT then return end
                    -- Recheck: still in the group and still offline?
                    local stillOnline = false
                    local n = GetNumGroupMembers()
                    for i = 1, n do
                        local unit = IsInRaid() and ("raid" .. i) or ("party" .. i)
                        if UnitName(unit) == host then
                            stillOnline = UnitIsConnected(unit)
                            break
                        end
                    end
                    if not stillOnline then
                        BJ:Print("|cffff4444Crash VOIDED: the pilot (" .. host ..
                            ") is gone. No gold changes hands.|r")
                        CM:ResetState()
                        updateUI()
                    end
                end)
            end
        elseif CM.hostLossTimer then
            CM.hostLossTimer:Cancel()
            CM.hostLossTimer = nil
        end
    end

    -- Rider watch (host only, mid-flight): a vanished rider STAYS aboard.
    -- Refunding them would make yanking the cable a free escape hatch in
    -- the pot game, so their ante rides on: an auto-jump target still
    -- fires for them, otherwise they go down with the ship.
    if CM.isHost and (CS.phase == CS.PHASE.FLIGHT or CS.phase == CS.PHASE.LAUNCHING) then
        for _, name in ipairs(CS.playerOrder) do
            local p = CS.players[name]
            if p and not p.cashedOut and not p.refunded and name ~= myName and not p.dcAnnounced then
                local inGroup = UnitInParty(name) or UnitInRaid(name)
                local online = false
                if inGroup then
                    local numMembers = GetNumGroupMembers()
                    for i = 1, numMembers do
                        local unit = IsInRaid() and ("raid" .. i) or ("party" .. i)
                        if UnitName(unit) == name then
                            online = UnitIsConnected(unit)
                            break
                        end
                    end
                end
                if not inGroup or not online then
                    p.dcAnnounced = true
                    BJ:Print("|cff888888" .. name .. " disconnected - their ante rides on. " ..
                        (p.target and "Their auto-jump can still win." or "No auto-jump set: she'll take them down.") .. "|r")
                end
            end
        end
        updateUI()
    end
end

-- The host that /reloaded mid-flight comes back without the secret: the
-- round can never finish. Void it for everyone (called from StateSync
-- apply, see the crash stateHandlers entry).
function CM:VoidUnfinishableRound()
    local CS = BJ.CrashState
    if not CM.isHost then return end
    if CS.phase ~= CS.PHASE.FLIGHT and CS.phase ~= CS.PHASE.LAUNCHING then return end
    if CM.secret then return end   -- we still hold it; nothing is wrong

    CS:VoidRound(true)
    CM:Send(MSG.VOID_ROUND, "0")
    BJ:Print("|cffff8800Crash: the flight could not be resumed after your reload - round VOIDED, antes returned.|r")
    updateUI()
end

-- Client-side watchdog, driven by the UI's OnUpdate: if the flight has run
-- far past any possible crash tick, the CRASH message is never coming.
function CM:CheckFlightWatchdog()
    local CS = BJ.CrashState
    if CS.phase ~= CS.PHASE.FLIGHT then return end
    if CS:CurrentTick() <= CS.WATCHDOG_TICKS then return end

    if CM.isHost then
        CM:VoidUnfinishableRound()
    else
        BJ:Print("|cffff8800Crash: no crash signal from the host - round voided locally. No gold changes hands.|r")
        CS:VoidRound(true)
        updateUI()
    end
end

-- Initialize on load
CM:Initialize()
