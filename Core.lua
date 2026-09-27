--[[
    Chairface's Casino - Core.lua
    Addon initialization, slash commands, and global namespace
]]

-- The addon name exactly as WoW reports it (the folder name, with the
-- space). ADDON_LOADED must be matched against THIS - the space-free
-- BJ.name never matched, so OnAddonLoaded silently never ran and BJ.db
-- stayed nil until some module's fallback happened to touch it.
local ADDON_NAME = ...

-- Global addon namespace
ChairfacesCasino = ChairfacesCasino or {}
local BJ = ChairfacesCasino

-- Addon info
BJ.name = "ChairfacesCasino"
BJ.version = "2.6.4"

-- Dice appearance sets, shared by the settings picker and Liar's Dice.
--   render "digit"   = a numbered die face (dieColor body, pipColor text)
--   render "pips"    = a drawn pip face using dieColor + pipColor
--   render "texture" = an image set under Textures\dice\<folder>\die_1..6
BJ.DiceStyles = {
    { id = "numeric",   name = "Numeric",      render = "digit",   dieColor = { 0.95, 0.95, 0.92 }, pipColor = { 0.08, 0.08, 0.1 } },
    { id = "whitepips", name = "White (pips)", render = "pips",    dieColor = { 0.95, 0.95, 0.92 }, pipColor = { 0.08, 0.08, 0.1 } },
    { id = "redpips",   name = "Red (pips)",   render = "pips",    dieColor = { 0.72, 0.11, 0.11 }, pipColor = { 0.97, 0.97, 0.95 } },
    { id = "scrimshaw", name = "Scrimshaw",    render = "texture", folder = "scrimshaw" },
}

function BJ:GetDiceStyle(id)
    for _, s in ipairs(BJ.DiceStyles) do
        if s.id == id then return s end
    end
    return BJ.DiceStyles[1]
end

-- Local utility: Deep copy a table (don't override global CopyTable)
local function DeepCopy(t)
    if type(t) ~= "table" then return t end
    local copy = {}
    for k, v in pairs(t) do
        copy[k] = DeepCopy(v)
    end
    return copy
end

-- Format gold amount with silver (1g = 100s)
-- Input is in gold (can have decimals), output shows gold and silver separately
function BJ:FormatGold(amount)
    if not amount then return "0g" end
    
    -- Round to nearest silver (0.01g)
    amount = math.floor(amount * 100 + 0.5) / 100
    
    local gold = math.floor(amount)
    local silver = math.floor((amount - gold) * 100 + 0.5)
    
    if silver > 0 then
        if gold > 0 then
            return gold .. "g " .. silver .. "s"
        else
            return silver .. "s"
        end
    else
        return gold .. "g"
    end
end

-- Format a net gold amount with an explicit +/- sign (e.g. "+1g 50s", "-2g")
function BJ:FormatGoldSigned(amount)
    if not amount or amount == 0 then return "0g" end
    local sign = amount < 0 and "-" or "+"
    return sign .. self:FormatGold(math.abs(amount))
end

-- Format gold for display (colored)
function BJ:FormatGoldColored(amount)
    if not amount then return "|cffffd7000g|r" end
    
    -- Round to nearest silver (0.01g)
    amount = math.floor(amount * 100 + 0.5) / 100
    
    local gold = math.floor(amount)
    local silver = math.floor((amount - gold) * 100 + 0.5)
    
    if silver > 0 then
        if gold > 0 then
            return "|cffffd700" .. gold .. "g|r |cffc0c0c0" .. silver .. "s|r"
        else
            return "|cffc0c0c0" .. silver .. "s|r"
        end
    else
        return "|cffffd700" .. gold .. "g|r"
    end
end

-- Version check state (only show warning once per session)
BJ.versionWarningShown = false
BJ.highestSeenVersion = BJ.version  -- Track highest version seen from peers

-- Compare version strings (returns true if v1 < v2)
function BJ:IsVersionOlder(v1, v2)
    local function parseVersion(v)
        local parts = {}
        for num in string.gmatch(v, "(%d+)") do
            table.insert(parts, tonumber(num))
        end
        return parts
    end
    
    local p1 = parseVersion(v1)
    local p2 = parseVersion(v2)
    
    for i = 1, math.max(#p1, #p2) do
        local n1 = p1[i] or 0
        local n2 = p2[i] or 0
        if n1 < n2 then return true end
        if n1 > n2 then return false end
    end
    return false
end

-- Two versions are network-compatible when their major.minor match. Patch /
-- sub-versions (e.g. 2.3.1 vs 2.3.4) are wire-compatible and must NOT trip the
-- mismatch warnings or join rejections - only a major.minor change (2.3 -> 2.4)
-- signals an incompatible protocol.
function BJ:VersionsCompatible(a, b)
    if not a or a == "" or not b or b == "" then return true end
    local function majorMinor(v)
        local major, minor = tostring(v):match("^(%d+)%.(%d+)")
        return (major or "0") .. "." .. (minor or "0")
    end
    return majorMinor(a) == majorMinor(b)
end

-- Called when we receive a version from another player
function BJ:OnPeerVersion(peerVersion, peerName)
    if not peerVersion or peerVersion == "" then return end

    -- Update highest seen version
    if BJ:IsVersionOlder(BJ.highestSeenVersion, peerVersion) then
        BJ.highestSeenVersion = peerVersion
    end

    -- Warn only on an incompatible (major.minor) newer version. Sub-version
    -- bumps are compatible, so they never defer a warning.
    if not BJ.versionWarningShown and not BJ:VersionsCompatible(BJ.version, peerVersion)
        and BJ:IsVersionOlder(BJ.version, peerVersion) then
        -- Store pending warning info instead of showing immediately
        BJ.pendingVersionWarning = {
            peerVersion = peerVersion,
            peerName = peerName or "unknown"
        }
        BJ:Debug("Version mismatch detected: peer " .. (peerName or "unknown") .. " has v" .. peerVersion .. " (we have v" .. BJ.version .. ") - deferring warning")
    end
end

-- Show pending version warning (called when user opens a casino window)
function BJ:ShowPendingVersionWarning()
    if not BJ.pendingVersionWarning or BJ.versionWarningShown then return end
    
    local info = BJ.pendingVersionWarning
    BJ.versionWarningShown = true
    BJ.pendingVersionWarning = nil
    
    -- Create warning popup
    StaticPopupDialogs["CHAIRFACES_CASINO_VERSION_WARNING"] = {
        text = "|cffff8800Chairface's Casino|r\n\nA player in your group (" .. info.peerName .. ") has a newer version (|cff44ff44" .. info.peerVersion .. "|r).\n\nYour version: |cffff4444" .. BJ.version .. "|r\n\nPlease update from CurseForge for the latest features and bug fixes!",
        button1 = "OK",
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    StaticPopup_Show("CHAIRFACES_CASINO_VERSION_WARNING")
end

-- Default saved variables
local defaults = {
    settings = {
        soundEnabled = true,
        showTutorialTips = true,
        cardBack = "blue",  -- red, blue, or mtg
        diceStyle = "numeric",  -- numeric or scrimshaw
        hiloShowTrixie = true,      -- Show Trixie on High-Lo window
        blackjackShowTrixie = true, -- Show Trixie on Blackjack window
        pokerShowTrixie = true,     -- Show Trixie on 5 Card Stud window
        holdemShowTrixie = true,    -- Show Trixie on Texas Hold'em window
        minimapOpensGame = true,    -- left-click jumps to the hosted game
        autoOpen = {},              -- per-game "open when hosted" opt-ins
        trixieChatter = true,       -- Trixie's table calls, greeting & banter
        trixiePublicChannel = "GROUP", -- announce open tables in the host's party/raid ("OFF" disables)
    },
    stats = {
        handsPlayed = 0,
        handsWon = 0,
        handsLost = 0,
        handsPushed = 0,
        blackjacks = 0,
        totalWagered = 0,
        netProfit = 0,
    }
}

-- Initialization
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LOGOUT")

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and (arg1 == ADDON_NAME or arg1 == BJ.name) then
        BJ:OnAddonLoaded()
    elseif event == "PLAYER_LOGIN" then
        BJ:OnPlayerLogin()
    elseif event == "PLAYER_LOGOUT" then
        BJ:OnPlayerLogout()
    end
end)

function BJ:OnAddonLoaded()
    -- Initialize saved variables
    if not ChairfacesCasinoDB then
        ChairfacesCasinoDB = DeepCopy(defaults)
    end
    self.db = ChairfacesCasinoDB
    
    -- Merge any missing defaults (for addon updates)
    for k, v in pairs(defaults) do
        if self.db[k] == nil then
            self.db[k] = DeepCopy(v)
        end
    end
    
    self:Print("Chairface's Casino v" .. self.version .. " loaded. Type /cc or /casino to open.")
end

function BJ:OnPlayerLogin()
    -- Initialize host settings
    if self.HostSettings and self.HostSettings.Initialize then
        self.HostSettings:Initialize()
    end
    
    -- Initialize session manager
    if self.SessionManager and self.SessionManager.Initialize then
        self.SessionManager:Initialize()
    end
    
    -- Initialize state sync system
    if self.StateSync and self.StateSync.Initialize then
        self.StateSync:Initialize()
    end
    
    -- Initialize leaderboard system
    if self.Leaderboard and self.Leaderboard.Initialize then
        self.Leaderboard:Initialize()
    end

    -- Initialize the cross-game session debt ledger (settle-up tracking)
    if self.DebtLedger and self.DebtLedger.Initialize then
        self.DebtLedger:Initialize()
    end
    
    -- Initialize multiplayer communication (Blackjack)
    if self.Multiplayer and self.Multiplayer.Initialize then
        self.Multiplayer:Initialize()
    end
    
    -- Initialize poker multiplayer communication
    if self.PokerMultiplayer and self.PokerMultiplayer.Initialize then
        self.PokerMultiplayer:Initialize()
    end

    -- Initialize Texas Hold'em multiplayer communication
    if self.HoldemMultiplayer and self.HoldemMultiplayer.Initialize then
        self.HoldemMultiplayer:Initialize()
    end

    -- Initialize UI
    if self.UI and self.UI.Initialize then
        self.UI:Initialize()
    end

    -- Initialize Poker UI
    if self.UI and self.UI.Poker and self.UI.Poker.Initialize then
        self.UI.Poker:Initialize()
    end

    -- Initialize Texas Hold'em UI
    if self.UI and self.UI.Holdem and self.UI.Holdem.Initialize then
        self.UI.Holdem:Initialize()
    end
    
    -- Initialize minimap button
    if self.MinimapButton and self.MinimapButton.Initialize then
        self.MinimapButton:Initialize()
    end
    
    -- Initialize escape key handler (closes windows on Escape)
    if self.EscapeHandler and self.EscapeHandler.Initialize then
        self.EscapeHandler:Initialize()
    end
    
    -- Load persistent game history for all games
    if self.GameState and self.GameState.LoadHistoryFromDB then
        self.GameState:LoadHistoryFromDB()
    end
    if self.PokerState and self.PokerState.LoadHistoryFromDB then
        self.PokerState:LoadHistoryFromDB()
    end
    if self.HoldemState and self.HoldemState.LoadHistoryFromDB then
        self.HoldemState:LoadHistoryFromDB()
    end
    if self.HiLoState and self.HiLoState.LoadHistoryFromDB then
        self.HiLoState:LoadHistoryFromDB()
    end
    if self.DeathRollState and self.DeathRollState.LoadHistoryFromDB then
        self.DeathRollState:LoadHistoryFromDB()
    end
    if self.BingoState and self.BingoState.LoadHistoryFromDB then
        self.BingoState:LoadHistoryFromDB()
    end
    if self.RouletteState and self.RouletteState.LoadHistoryFromDB then
        self.RouletteState:LoadHistoryFromDB()
    end
    if self.LiarsDiceState and self.LiarsDiceState.LoadHistoryFromDB then
        self.LiarsDiceState:LoadHistoryFromDB()
    end
    if self.CrashState and self.CrashState.LoadHistoryFromDB then
        self.CrashState:LoadHistoryFromDB()
    end
end

function BJ:OnPlayerLogout()
    -- Clean up all game states without sending network messages
    -- (Network calls during logout cause protected function errors)
    -- Other players will detect our absence via GROUP_ROSTER_UPDATE
    
    -- Blackjack cleanup
    if self.Multiplayer then
        -- Cancel any active timers
        if self.Multiplayer.CancelCountdown then
            self.Multiplayer:CancelCountdown()
        end
        if self.Multiplayer.CancelTurnTimer then
            self.Multiplayer:CancelTurnTimer()
        end
        -- Reset state (no network calls)
        if self.Multiplayer.ResetState then
            self.Multiplayer:ResetState()
        end
    end
    
    -- Poker cleanup
    if self.PokerMultiplayer then
        if self.PokerMultiplayer.CancelCountdown then
            self.PokerMultiplayer:CancelCountdown()
        end
        if self.PokerMultiplayer.ResetState then
            self.PokerMultiplayer:ResetState()
        end
    end

    -- Texas Hold'em cleanup
    if self.HoldemMultiplayer then
        if self.HoldemMultiplayer.CancelCountdown then
            self.HoldemMultiplayer:CancelCountdown()
        end
        if self.HoldemMultiplayer.ResetState then
            self.HoldemMultiplayer:ResetState()
        end
    end
    
    -- HiLo cleanup
    if self.HiLoState then
        if self.HiLoState.Reset then
            self.HiLoState:Reset()
        end
    end

    -- Death Roll cleanup
    if self.DeathRollState and self.DeathRollState.Reset then
        self.DeathRollState:Reset()
    end

    -- Bingo cleanup (cancel draw ticker, no network calls)
    if self.BingoMultiplayer and self.BingoMultiplayer.CancelDrawTicker then
        self.BingoMultiplayer:CancelDrawTicker()
    end
    if self.BingoState and self.BingoState.Reset then
        self.BingoState:Reset()
    end

    -- Roulette cleanup (cancel spin timer, no network calls)
    if self.RouletteMultiplayer and self.RouletteMultiplayer.spinTimer then
        self.RouletteMultiplayer.spinTimer:Cancel()
        self.RouletteMultiplayer.spinTimer = nil
    end

    -- Crash cleanup (ResetState cancels every crash timer and
    -- sends nothing)
    if self.CrashMultiplayer and self.CrashMultiplayer.ResetState then
        self.CrashMultiplayer:ResetState()
    end
    if self.RouletteState and self.RouletteState.Reset then
        self.RouletteState:Reset()
    end

    -- Liar's Dice cleanup (cancel turn timer, no network calls)
    if self.LiarsDiceMultiplayer and self.LiarsDiceMultiplayer.CancelTurnTimer then
        self.LiarsDiceMultiplayer:CancelTurnTimer()
    end
    if self.LiarsDiceState and self.LiarsDiceState.Reset then
        self.LiarsDiceState:Reset()
    end

end

-- Utility: Print to chat and log window
function BJ:Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[Casino]|r " .. tostring(msg))
    -- Also add to log window if it exists
    if BJ.UI and BJ.UI.Lobby and BJ.UI.Lobby.AddLogMessage then
        BJ.UI.Lobby:AddLogMessage(msg)
    end
end

-- Utility: a chat or event value as a plain string, or nil when the client
-- keeps it secret. On the Forever client a secret string still answers
-- type() == "string", then throws the moment it is indexed, compared or
-- matched ("attempt to index local 'text' (a secret string value)"). So the
-- concat AND the comparison both sit inside the pcall: a secret survives the
-- concat and only throws on the first compare. Every chat handler reads its
-- message and sender through here before touching them.
function BJ:Readable(value)
    if value == nil then return nil end
    local ok, text = pcall(function()
        local s = "" .. tostring(value)
        if s == "" then return nil end
        return s
    end)
    if ok then return text end
    return nil
end

-- Utility: a player's name as the casino shows it: the first name alone,
-- unless someone else in `others` (the table, the riders, the board, the
-- ledger) has the same first name -- then the whole name, "First Surname",
-- for both of them. Returns the text and whether it is the whole name, so
-- the caller can shrink the font to fit (BJ:FitNameFont). Two with the same
-- first name AND surname (another realm) get the realm as well. WoW Forever
-- names are "First Surname"; the realm is otherwise never shown.
function BJ:SeatName(name, others)
    name = BJ:Readable(name)
    if not name then return "?", false end
    local short, realm = name:match("^([^-]+)%-?(.*)$")
    short = short or name
    local first = short:match("^(%S+) %S")
    if not first then return short, false end

    local shared, twin = false, false
    for _, other in ipairs(others or {}) do
        local full = BJ:Readable(other)
        -- Only this very entry is "me"; the same name on another realm is not.
        if full and full ~= name then
            local o = full:match("^([^-]+)") or full
            local oFirst = o:match("^(%S+) %S") or o
            if oFirst:lower() == first:lower() then
                shared = true
                if o:lower() == short:lower() then twin = true end
            end
        end
    end
    if not shared then return first, false end
    if twin and realm ~= "" then return short .. "-" .. realm, true end
    return short, true
end

-- Utility: a name label's font, smaller while it shows a whole name (so
-- "Chairface Chippendale" fits where "Chairface" did), back to its own size
-- when it shows a first name again. The label's own font is remembered the
-- first time, so its size, face and outline are kept.
function BJ:FitNameFont(fontString, wholeName)
    if type(fontString) ~= "table" or type(fontString.GetFont) ~= "function" then return end
    if not fontString.casinoBaseFont then
        local ok, face, size, flags = pcall(fontString.GetFont, fontString)
        if not (ok and face and tonumber(size)) then return end
        fontString.casinoBaseFont = { face, tonumber(size), flags }
    end
    local base = fontString.casinoBaseFont
    local size = wholeName and math.max(8, math.floor(base[2] * 0.85 + 0.5)) or base[2]
    pcall(fontString.SetFont, fontString, base[1], size, base[3])
end

-- Utility: the next player name at the start of typed text, and the rest.
-- Every WoW Forever name is two words ("Chairface Chippendale", perhaps with
-- "-Realm" on the second), so a command can take names with spaces in them
-- and still tell where one ends: "Sewer Urchin Chairface Chippendale 25".
function BJ:TakeName(text)
    local first, second, rest = tostring(text or ""):match("^%s*(%S+)%s+(%S+)%s*(.-)%s*$")
    if not first or tonumber(first) or tonumber(second) then return nil, text end
    return first .. " " .. second, rest
end

-- WoW Forever (interface 16xxx) gives every character a surname, and
-- UnitName returns it as its SECOND value -- the slot other clients use for
-- a realm: BJ:MyName() -> "Highley", "Regarded". Chat and addon
-- messages name the same player "Highley Regarded". So a name is always
-- read through BJ:UnitFullName / BJ:MyName, never BJ:UnitFullName(...)'s first
-- value alone, or "is this me?" fails everywhere.
BJ.isForever = (function()
    local ok, _, _, _, toc = pcall(GetBuildInfo)
    return ok and type(toc) == "number" and toc >= 16000 and toc < 17000
end)()

-- A unit's name as chat gives it: "First Last" on Forever; the plain name,
-- as UnitName's first value, on other clients.
function BJ:UnitFullName(unit)
    local ok, first, second = pcall(UnitName, unit)
    if not ok then return nil end
    first = BJ:Readable(first)
    if not first then return nil end
    second = BJ:Readable(second)
    if BJ.isForever and second then return first .. " " .. second end
    return first
end

-- This character's name, the same way.
function BJ:MyName()
    return BJ:UnitFullName("player") or UnitName("player")
end

-- Utility: a server /roll system line -> name, roll, max (numbers), or nil.
-- Forever names are a first name and a surname with a space between
-- ("Chairface Chippendale rolls 42 (1-100)"), so the name is everything
-- before " rolls", not one word. A realm after the last hyphen is dropped:
-- players are keyed by the bare name, as BJ:MyName() gives it.
function BJ:ParseRoll(msg)
    msg = BJ:Readable(msg)
    if not msg then return nil end
    local name, roll, maxRoll = msg:match("^(.+) rolls (%d+) %(1%-(%d+)%)$")
    if not name then return nil end
    name = name:match("^(.-)%-[^%-%s]+$") or name
    return name, tonumber(roll), tonumber(maxRoll)
end

-- Utility: play an addon sound effect, honoring the lobby's SFX toggle.
-- `file` is relative to the Sounds folder (subfolders OK: "Kenney\\card-place-1.ogg").
-- Passes through PlaySoundFile's returns so callers can StopSound(handle).
function BJ:PlaySfx(file, channel)
    if self.UI and self.UI.Lobby and self.UI.Lobby.sfxEnabled == false then return end
    return PlaySoundFile("Interface\\AddOns\\Chairfaces Casino\\Sounds\\" .. file, channel or "SFX")
end

-- Utility: Debug print
function BJ:Debug(msg)
    if self.db and self.db.settings and self.db.settings.debug then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff9900[BJ Debug]|r " .. tostring(msg))
        if BJ.UI and BJ.UI.Lobby and BJ.UI.Lobby.AddLogMessage then
            BJ.UI.Lobby:AddLogMessage("|cffff9900[Debug]|r " .. msg)
        end
    end
end

-- Slash command handler
SLASH_CHAIRFACESCASINO1 = "/casino"
SLASH_CHAIRFACESCASINO2 = "/cc"

SlashCmdList["CHAIRFACESCASINO"] = function(msg)
    local cmd, arg = strsplit(" ", msg, 2)
    cmd = strlower(cmd or "")
    
    if cmd == "" or cmd == "show" or cmd == "open" then
        -- Open the casino lobby
        if BJ.UI and BJ.UI.ShowLobby then
            BJ.UI:ShowLobby()
        else
            BJ:Print("Casino lobby not yet initialized.")
        end
    elseif cmd == "help" or cmd == "?" then
        -- Show all commands
        BJ:Print("|cffffd700=== Chairface's Casino Commands ===|r")
        BJ:Print("|cff88ff88/cc|r or |cff88ff88/casino|r - Open casino lobby")
        BJ:Print("|cff88ff88/cc default|r - Reset all settings to defaults")
        BJ:Print("|cff88ff88/cc intro|r - Replay Trixie's introduction")
        BJ:Print("|cff88ff88/cc events|r - Community gambling-events calendar")
        BJ:Print("|cff88ff88/cc debts|r - The tab: who owes who across all games")
        BJ:Print("|cff88ff88/cc lfg|r - Table Finder: list yourself or find a game")
        BJ:Print("|cff88ff88/cc fakeplay|r - Toggle fake play (games you host record no debts)")
        BJ:Print("|cff88ff88/cc help|r - Show this help")
        BJ:Print("|cff88ff88/hilo <max> [timer]|r - Quick start High-Lo")
        BJ:Print("   max = max roll, timer = 20-120 sec (default 60)")
        BJ:Print("   Example: /hilo 1000 30")
        BJ:Print("|cff88ff88/cup|r, |cff88ff88/derby|r or |cff88ff88/chairscup|r - Open the Chair's Cup derby")
    elseif cmd == "default" or cmd == "defaults" or cmd == "reset" then
        -- Reset all settings to defaults
        BJ:ResetToDefaults()
    elseif cmd == "intro" then
        -- Show Trixie intro again
        if ChairfacesCasinoSaved then
            ChairfacesCasinoSaved.trixieIntroShown = nil
        end
        BJ:Print("Trixie intro reset! Open the casino to see it again.")
    elseif cmd == "chipscale" then
        -- Debug/test-mode knob: live-resize every chip pile (pot + player
        -- stacks) to find the size worth baking into UI/ChipPot.lua
        if not (BJ.TestMode and BJ.TestMode.enabled) then
            BJ:Print("chipscale is a test-mode knob - enable /cc db first.")
        elseif BJ.UI and BJ.UI.ChipPot then
            BJ.UI.ChipPot:SetScale(tonumber(arg))
        end
    elseif cmd == "debts" or cmd == "debt" or cmd == "ledger" or cmd == "tab" then
        -- Session debt ledger window
        if BJ.UI and BJ.UI.Debts then
            BJ.UI.Debts:Toggle()
        end
    elseif cmd == "lfg" or cmd == "finder" or cmd == "find" or cmd == "lft" then
        -- LFG-style table finder board
        if BJ.UI and BJ.UI.Finder then
            BJ.UI.Finder:Toggle()
        end
    elseif cmd == "fakeplay" or cmd == "fun" then
        -- Fun nights: games this client hosts record no debts
        if BJ.DebtLedger then
            BJ.DebtLedger:SetFakePlay(not BJ.DebtLedger:IsFakePlay())
        end
    elseif cmd == "zep" then
        -- Hidden: audition zeppelin models live in the Crash window
        -- (same name gate as /cc db; see Crash:DebugZep for the crash caveat)
        if BJ.TestMode and BJ.TestMode:CanUseDebugMode() and BJ.UI and BJ.UI.Crash then
            BJ.UI.Crash:DebugZep(arg)
        end
    elseif cmd == "db" or cmd == "debug" or cmd == "testmode" then
        -- Hidden: Toggle test/debug mode for all games
        if BJ.TestMode then
            BJ.TestMode:Toggle()
            if BJ.UI and BJ.UI.UpdateTestModeLayout then
                BJ.UI:UpdateTestModeLayout()
            end
        end
    elseif cmd == "test" then
        -- Hidden test mode commands
        if not BJ.TestMode or not BJ.TestMode.enabled then
            return
        end
        
        local subcmd, subarg = strsplit(" ", arg or "", 2)
        subcmd = strlower(subcmd or "")
        
        if subcmd == "add" then
            BJ.TestMode:AddFakePlayer(subarg)
        elseif subcmd == "remove" then
            BJ.TestMode:RemoveFakePlayer(subarg)
        elseif subcmd == "list" then
            BJ.TestMode:ListFakePlayers()
        elseif subcmd == "clear" then
            BJ.TestMode:ClearFakePlayers()
        elseif subcmd == "auto" then
            BJ.TestMode:ToggleAutoPlay()
        elseif subcmd == "deal" then
            BJ.TestMode:ForceDeal()
        elseif subcmd == "dealer" then
            BJ.TestMode:DealerAction()
        elseif subcmd == "hit" then
            BJ.TestMode:ManualAction("hit", subarg)
        elseif subcmd == "stand" then
            BJ.TestMode:ManualAction("stand", subarg)
        elseif subcmd == "double" then
            BJ.TestMode:ManualAction("double", subarg)
        elseif subcmd == "split" then
            BJ.TestMode:ManualAction("split", subarg)
        elseif subcmd == "drjoin" then
            -- Fake opponent accepts the open Death Roll and auto-rolls
            BJ.TestMode:DeathRollFakeAccept(subarg)
        elseif subcmd == "bingo" then
            -- Add N fake card buyers to the open bingo lobby
            BJ.TestMode:AddBingoFakePlayers(subarg)
        elseif subcmd == "bingospeed" then
            -- Live-adjust seconds between bingo calls (find the sweet spot)
            BJ.TestMode:SetBingoDrawSpeed(subarg)
        elseif subcmd == "roulette" then
            -- Add N fake bettors to the open roulette table
            BJ.TestMode:AddRouletteFakePlayers(subarg)
        elseif subcmd == "liarsdice" or subcmd == "ld" then
            -- Add N fake players to the open Liar's Dice lobby
            BJ.TestMode:AddLiarsDiceFakePlayers(subarg)
        elseif subcmd == "ldact" then
            -- Nudge whichever bot is on turn to act
            BJ.TestMode:LiarsDiceBotsAct()
        elseif subcmd == "arcade" then
            -- Solo-game debugging: credit reset / refill reset / set balance
            BJ.TestMode:ArcadeCommand(subarg)
        elseif subcmd == "slots" then
            -- Rig the next slots spin to test lines and the bonus games
            BJ.TestMode:SlotsForce(subarg)
        elseif subcmd == "bj" then
            -- Rig the video blackjack machine (e.g. "pair" for split testing)
            BJ.TestMode:VideoBJForce(subarg)
        elseif subcmd == "debt" then
            -- Debt ledger harness: add/pay/list/wipe with fake players
            if BJ.DebtLedger then
                BJ.DebtLedger:TestCommand(subarg)
            end
        end
    else
        -- Default: open lobby
        if BJ.UI and BJ.UI.ShowLobby then
            BJ.UI:ShowLobby()
        end
    end
end

-- High-Lo quick start command
SLASH_HILOQUICK1 = "/hilo"

SlashCmdList["HILOQUICK"] = function(msg)
    local arg1, arg2 = strsplit(" ", msg, 2)
    local maxRoll = tonumber(arg1) or 100
    local joinTimer = tonumber(arg2) or 60
    
    -- Validate max roll
    if maxRoll < 2 then
        BJ:Print("Max roll must be at least 2.")
        return
    end
    
    -- Validate join timer (20-120 seconds)
    if joinTimer < 20 then
        joinTimer = 20
    elseif joinTimer > 120 then
        joinTimer = 120
    end
    
    local inTestMode = BJ.TestMode and BJ.TestMode.enabled
    local inPartyOrRaid = IsInGroup() or IsInRaid()
    
    if not inPartyOrRaid and not inTestMode then
        BJ:Print("You must be in a party or raid to host High-Lo.")
        return
    end
    
    local HL = BJ.HiLoState
    local HLM = BJ.HiLoMultiplayer
    
    -- Check if a game is already in progress
    if HL.phase ~= HL.PHASE.IDLE then
        BJ:Print("A High-Lo game is already in progress.")
        return
    end
    
    -- Check if any other game is active
    local Lobby = BJ.UI and BJ.UI.Lobby
    if Lobby and Lobby.IsAnyGameActive then
        local isActive, activeGame = Lobby:IsAnyGameActive()
        if isActive then
            local gameName = Lobby:GetGameName(activeGame)
            BJ:Print("|cffff4444Cannot host - a " .. gameName .. " game is already in progress.|r")
            return
        end
    end
    
    local myName = BJ:MyName()
    
    -- Host the game
    HL:HostGame(myName, maxRoll, joinTimer)
    
    -- Broadcast to group
    if HLM then
        HLM:BroadcastTableOpen(maxRoll, joinTimer)
        -- Start join timer with chat announcements
        HLM:StartJoinTimer(joinTimer)
    end
    
    local gameLink = BJ:CreateGameLink("hilo", "High-Lo")
    BJ:Print(gameLink .. " table opened! Max roll: " .. maxRoll .. " | " .. joinTimer .. " second join window")
    
    -- Update UI if open (but don't force open)
    if BJ.UI and BJ.UI.HiLo and BJ.UI.HiLo.frame then
        BJ.UI.HiLo:UpdateDisplay()
    end
end

--[[
    Clickable Chat Links
    Creates clickable game links in chat messages
]]

-- Create a clickable link for a game
function BJ:CreateGameLink(gameName, displayText)
    -- Format: |Haddon:casinolink:gamename|h[DisplayText]|h
    -- The "addon" hyperlink type exists specifically for addons:
    -- Blizzard's SetItemRef deliberately ignores it, so a plain
    -- post-hook is enough. Never override the SetItemRef global -
    -- that taints Blizzard's whole hyperlink path (clicking a player
    -- name then opens a tainted menu whose protected Copy Character
    -- Name action throws ADDON_ACTION_FORBIDDEN on CopyToClipboard).
    return "|cff00ff00|Haddon:casinolink:" .. gameName .. "|h[" .. (displayText or gameName) .. "]|h|r"
end

-- Brag your solo arcade credit total to chat. Arcade credits are local, so the
-- number is embedded as plain text (that's what other players actually see);
-- WoW strips custom clickable links from outgoing player chat, so we only make
-- the "Play the Arcade" link clickable in your own frame.
function BJ:ShareCredits()
    local credits = (BJ.Arcade and BJ.Arcade:GetCredits()) or 0
    local pretty = BreakUpLargeNumbers and BreakUpLargeNumbers(credits) or tostring(credits)

    local channel = "SAY"
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then channel = "INSTANCE_CHAT"
    elseif IsInRaid() then channel = "RAID"
    elseif IsInGroup() then channel = "PARTY" end

    local msg = "Chairface's Casino \226\128\148 I'm holding " .. pretty ..
        " arcade credits! Think you can beat that? Type /cc to play."
    SendChatMessage(msg, channel)

    -- Local, clickable version for yourself.
    local link = BJ:CreateGameLink("arcade", "Play the Arcade")
    BJ:Print("You bragged " .. pretty .. " credits to " .. channel:lower():gsub("_", " ") ..
        ". " .. link)
end

-- Gift dialog for the arcade machines: separate boxes for the player's name
-- and the amount (amount defaults to 1 each time it opens).
function BJ:ShowSendCreditsDialog()
    if not BJ.sendCreditsFrame then
        local f = CreateFrame("Frame", "ChairfacesCasinoSendCredits", UIParent, "BackdropTemplate")
        f:SetSize(280, 150)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
        f:SetBackdropColor(0.05, 0.07, 0.1, 0.98)
        f:SetBackdropBorderColor(0.7, 0.55, 0.2, 1)
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)

        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", 0, -10)
        title:SetText("|cffffd700Send Arcade Credits|r")

        local nameLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameLabel:SetPoint("TOPLEFT", 16, -42)
        nameLabel:SetText("To:")
        local nameBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
        nameBox:SetSize(160, 20)
        nameBox:SetPoint("LEFT", nameLabel, "RIGHT", 44, 0)
        nameBox:SetAutoFocus(false)
        nameBox:SetMaxLetters(24)
        f.nameBox = nameBox

        local amtLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        amtLabel:SetPoint("TOPLEFT", 16, -74)
        amtLabel:SetText("Amount:")
        local amtBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
        amtBox:SetSize(80, 20)
        amtBox:SetPoint("LEFT", amtLabel, "RIGHT", 12, 0)
        amtBox:SetAutoFocus(false)
        amtBox:SetNumeric(true)
        amtBox:SetMaxLetters(9)
        f.amtBox = amtBox

        local function doSend()
            local target = f.nameBox:GetText() or ""
            local amount = tonumber(f.amtBox:GetText()) or 0
            local ok, err = BJ.Arcade:SendCredits(target, amount)
            if ok then
                f:Hide()
            else
                BJ:Print("|cffff8800" .. (err or "Could not send.") .. "|r")
            end
        end

        local sendBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        sendBtn:SetSize(100, 24)
        sendBtn:SetPoint("BOTTOMLEFT", 20, 14)
        sendBtn:SetText("Send")
        sendBtn:SetScript("OnClick", doSend)

        local cancelBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        cancelBtn:SetSize(100, 24)
        cancelBtn:SetPoint("BOTTOMRIGHT", -20, 14)
        cancelBtn:SetText("Cancel")
        cancelBtn:SetScript("OnClick", function() f:Hide() end)

        nameBox:SetScript("OnEnterPressed", function() f.amtBox:SetFocus() end)
        amtBox:SetScript("OnEnterPressed", doSend)
        nameBox:SetScript("OnEscapePressed", function() f:Hide() end)
        amtBox:SetScript("OnEscapePressed", function() f:Hide() end)

        BJ.sendCreditsFrame = f
    end

    local f = BJ.sendCreditsFrame
    f.nameBox:SetText("")
    f.amtBox:SetText("1")      -- default quantity
    f:Show()
    f.nameBox:SetFocus()
end

-- Debug grant dialog: type a character name and a quantity, and the credits
-- are conjured onto that character (nothing leaves your own balance). Hidden
-- behind the same character-name allow-list as /cc db - the button that opens
-- it is only built for those characters, and this refuses to open for anyone
-- else even if the function is called directly.
function BJ:ShowGrantCreditsDialog()
    if not (BJ.Arcade and BJ.Arcade:CanGrantCredits()) then return end

    if not BJ.grantCreditsFrame then
        local f = CreateFrame("Frame", "ChairfacesCasinoGrantCredits", UIParent, "BackdropTemplate")
        f:SetSize(300, 170)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
        f:SetBackdropColor(0.08, 0.04, 0.10, 0.98)
        f:SetBackdropBorderColor(0.8, 0.3, 1.0, 1)
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)

        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", 0, -10)
        title:SetText("|cffff00ffGrant Arcade Credits|r")

        local nameLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameLabel:SetPoint("TOPLEFT", 16, -42)
        nameLabel:SetText("Character:")
        local nameBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
        nameBox:SetSize(150, 20)
        nameBox:SetPoint("LEFT", nameLabel, "RIGHT", 12, 0)
        nameBox:SetAutoFocus(false)
        nameBox:SetMaxLetters(24)
        f.nameBox = nameBox

        local amtLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        amtLabel:SetPoint("TOPLEFT", 16, -74)
        amtLabel:SetText("Credits:")
        local amtBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
        amtBox:SetSize(100, 20)
        amtBox:SetPoint("LEFT", amtLabel, "RIGHT", 12, 0)
        amtBox:SetAutoFocus(false)
        amtBox:SetNumeric(true)
        amtBox:SetMaxLetters(9)
        f.amtBox = amtBox

        local note = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        note:SetPoint("TOPLEFT", 16, -100)
        note:SetPoint("RIGHT", -16, 0)
        note:SetJustifyH("LEFT")
        note:SetText("|cff888888House money - your own balance is untouched. They must be online with the addon loaded.|r")

        local function doGrant()
            local ok, err = BJ.Arcade:GrantCredits(f.nameBox:GetText() or "",
                tonumber(f.amtBox:GetText()) or 0)
            if ok then
                f:Hide()
            else
                BJ:Print("|cffff8800" .. (err or "Could not grant.") .. "|r")
            end
        end

        local grantBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        grantBtn:SetSize(110, 24)
        grantBtn:SetPoint("BOTTOMLEFT", 20, 14)
        grantBtn:SetText("Grant")
        grantBtn:SetScript("OnClick", doGrant)

        local cancelBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        cancelBtn:SetSize(100, 24)
        cancelBtn:SetPoint("BOTTOMRIGHT", -20, 14)
        cancelBtn:SetText("Cancel")
        cancelBtn:SetScript("OnClick", function() f:Hide() end)

        nameBox:SetScript("OnEnterPressed", function() f.amtBox:SetFocus() end)
        amtBox:SetScript("OnEnterPressed", doGrant)
        nameBox:SetScript("OnEscapePressed", function() f:Hide() end)
        amtBox:SetScript("OnEscapePressed", function() f:Hide() end)

        BJ.grantCreditsFrame = f
    end

    local f = BJ.grantCreditsFrame
    f.nameBox:SetText("")
    f.amtBox:SetText("1000")
    f:Show()
    f.nameBox:SetFocus()
end

-- Buy-credits helper: pick how many lots to buy and the addon fills out
-- the Send Mail form at a mailbox - subject, body, money and recipient - so
-- the player only has to press Send.
function BJ:ShowBuyCreditsDialog()
    if not BJ.buyCreditsFrame then
        local f = CreateFrame("Frame", "ChairfacesCasinoBuyCredits", UIParent, "BackdropTemplate")
        f:SetSize(320, 190)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
        f:SetBackdropColor(0.05, 0.08, 0.05, 0.98)
        f:SetBackdropBorderColor(0.7, 0.55, 0.2, 1)
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)

        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", 0, -10)
        title:SetText("|cffffd700Buy Arcade Credits|r")

        local goldLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        goldLabel:SetPoint("TOPLEFT", 16, -42)
        goldLabel:SetText("Lots of " .. BJ.Arcade:PriceText(1) .. ":")
        local goldBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
        goldBox:SetSize(80, 20)
        goldBox:SetPoint("LEFT", goldLabel, "RIGHT", 12, 0)
        goldBox:SetAutoFocus(false)
        goldBox:SetNumeric(true)
        goldBox:SetMaxLetters(6)
        f.goldBox = goldBox

        local rateInfo = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        rateInfo:SetPoint("TOPLEFT", 16, -72)
        f.rateInfo = rateInfo

        local note = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        note:SetPoint("TOPLEFT", 16, -96)
        note:SetPoint("RIGHT", -16, 0)
        note:SetJustifyH("LEFT")
        note:SetSpacing(2)
        note:SetText("|cff888888Stand at a mailbox, then press Fill Mail - the Send Mail form is completed for you (open its Send Mail tab if it asks). Press WoW's Send button to pay and the credits arrive instantly.|r")

        local function refreshRate()
            local lots = math.floor(tonumber(f.goldBox:GetText()) or 0)
            local credits = lots * BJ.Arcade.CREDITS_PER_LOT
            f.rateInfo:SetText(string.format("= |cffffd700%d|r credits for |cffffd700%s|r", credits, BJ.Arcade:PriceText(lots)))
        end
        goldBox:SetScript("OnTextChanged", refreshRate)
        f.refreshRate = refreshRate

        local fillBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        fillBtn:SetSize(110, 24)
        fillBtn:SetPoint("BOTTOMLEFT", 20, 14)
        fillBtn:SetText("Fill Mail")
        fillBtn:SetScript("OnClick", function()
            local ok, err = BJ.Arcade:FillPurchaseMail(f.goldBox:GetText())
            if ok then
                f:Hide()
            else
                BJ:Print("|cffff8800" .. (err or "Could not fill the mail.") .. "|r")
            end
        end)

        local cancelBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        cancelBtn:SetSize(100, 24)
        cancelBtn:SetPoint("BOTTOMRIGHT", -20, 14)
        cancelBtn:SetText("Cancel")
        cancelBtn:SetScript("OnClick", function() f:Hide() end)

        goldBox:SetScript("OnEscapePressed", function() f:Hide() end)
        goldBox:SetScript("OnEnterPressed", function() fillBtn:Click() end)

        BJ.buyCreditsFrame = f
    end

    local f = BJ.buyCreditsFrame
    f.goldBox:SetText("1")
    f.refreshRate()
    f:Show()
    f.goldBox:SetFocus()
end

-- Close every casino/game window. Used when a chat link jumps you straight
-- into a game so you never end up with two tables stacked on top of each other.
function BJ:CloseAllGameWindows()
    local names = {
        "ChairfacesCasinoLobby",
        "ChairfacesCasinoFrame",       -- Blackjack
        "ChairfacesCasinoPoker",
        "ChairfacesCasinoHoldem",
        "ChairfacesCasinoHiLo",
        "ChairfacesCasinoDeathRoll",
        "ChairfacesCasinoBingo",
        "ChairfacesCasinoRoulette",
        "ChairfacesCasinoLiarsDice",
        "ChairfacesCasinoSlots",
        "ChairfacesCasinoVideoPoker",
        "SigmaDerbyFrame",             -- Chair's Cup
    }
    -- Opening a game from a link is not "returning from the derby to the
    -- lobby", so hiding the derby here must not bounce the lobby back up.
    if BJ.UI and BJ.UI.Lobby then BJ.UI.Lobby.derbyOpenedFromLobby = false end
    for _, n in ipairs(names) do
        local frame = _G[n]
        if frame and frame.IsShown and frame:IsShown() then frame:Hide() end
    end
end

-- One table that knows every game's UI module, shared by casinolinks,
-- the per-game auto-open (GameComm) and the minimap button. Keys match
-- both the GameComm gameKeys and the Lobby.gameList keys; "derby" and
-- "chairscup" are the same window.
local GAME_UI = {
    hilo      = function() return BJ.UI and BJ.UI.HiLo end,
    blackjack = function() return BJ.UI end,
    poker     = function() return BJ.UI and BJ.UI.Poker end,
    holdem    = function() return BJ.UI and BJ.UI.Holdem end,
    deathroll = function() return BJ.UI and BJ.UI.DeathRoll end,
    bingo     = function() return BJ.UI and BJ.UI.Bingo end,
    roulette  = function() return BJ.UI and BJ.UI.Roulette end,
    liarsdice = function() return BJ.UI and BJ.UI.LiarsDice end,
    crash     = function() return BJ.UI and BJ.UI.Crash end,
    arcade    = function() return BJ.UI and BJ.UI.Slots end,
    finder    = function() return BJ.UI and BJ.UI.Finder end,
}

-- Open one game's window by key (casinolink key or gameList key).
function BJ:OpenGameWindow(game)
    if game == "chairscup" or game == "derby" then
        -- Chair's Cup is decoupled; drive it through its own slash handler.
        local handler = SlashCmdList and SlashCmdList["CHAIRSCUP"]
        local sd = _G.SigmaDerbyFrame
        if handler and not (sd and sd:IsShown()) then handler("") end
        return
    end
    local getUI = GAME_UI[game]
    local ui = getUI and getUI()
    if ui and ui.Show then ui:Show() end
end

-- The game's window frame (nil if never created), for shown checks.
function BJ:GetGameWindow(game)
    if game == "chairscup" or game == "derby" then return _G.SigmaDerbyFrame end
    local getUI = GAME_UI[game]
    local ui = getUI and getUI()
    return ui and (ui.mainFrame or ui.frame)
end

hooksecurefunc("SetItemRef", function(link, text, button, chatFrame)
    local linkType, namespace, game = strsplit(":", link)
    if linkType ~= "addon" or namespace ~= "casinolink" then return end

    -- A link jumps straight into one game: clear any other open casino
    -- windows first so the player isn't left with stacked tables.
    BJ:CloseAllGameWindows()
    BJ:OpenGameWindow(game)
end)

-- Reset all settings to defaults
function BJ:ResetToDefaults()
    -- Reset settings
    if not self.db then
        self.db = ChairfacesCasinoDB or {}
    end
    
    self.db.settings = {
        soundEnabled = true,
        voiceEnabled = true,
        voiceFrequency = 3,
        showTutorialTips = true,
        cardBack = "blue",
        minimapScale = 1.5,
        windowScale = 1.0,
        debug = false,
    }
    
    -- Apply minimap scale
    if BJ.MinimapButton and BJ.MinimapButton.button then
        local baseSize = 32
        BJ.MinimapButton.button:SetSize(baseSize, baseSize)
        if BJ.MinimapButton.button.overlay then
            BJ.MinimapButton.button.overlay:SetSize(53, 53)
        end
        if BJ.MinimapButton.button.background then
            BJ.MinimapButton.button.background:SetSize(20, 20)
        end
    end
    
    -- Apply window scale (reset to 1.0)
    if BJ.UI and BJ.UI.Lobby then
        BJ.UI.Lobby:ApplyWindowScale()
    end
    
    -- Update settings panel if open
    if BJ.UI and BJ.UI.Lobby and BJ.UI.Lobby.settingsFrame then
        local sf = BJ.UI.Lobby.settingsFrame
        if sf.minimapSlider then sf.minimapSlider:SetValue(1.0) end
        if sf.windowSlider then sf.windowSlider:SetValue(1.0) end
        if sf.voiceFreqSlider then sf.voiceFreqSlider:SetValue(3) end
        if sf.sfxIcon then sf.sfxIcon:SetText("|cff00ff00SFX ON|r") end
        if sf.voiceIcon then sf.voiceIcon:SetText("|cff00ff00VOICE ON|r") end
        if sf.mailHelperCheck then sf.mailHelperCheck:SetChecked(true) end
    end

    -- Re-show the mailbox credits helper (default is on)
    if BJ.Arcade and BJ.Arcade.UpdateMailHelperVisibility then
        BJ.Arcade:UpdateMailHelperVisibility()
    end
    
    -- Update card back
    if BJ.UI and BJ.UI.Cards then
        BJ.UI.Cards:SetCardBack("blue")
    end
    
    BJ:Print("Settings reset to defaults.")
end
