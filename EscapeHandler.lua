--[[
    Chairface's Casino - EscapeHandler.lua
    Handles Escape key to close all game windows
    
    This module registers game frames with UISpecialFrames so that
    pressing Escape will close them (standard WoW behavior).
]]

local BJ = ChairfacesCasino
BJ.EscapeHandler = {}
local EH = BJ.EscapeHandler

-- Track which frames we've registered
EH.registeredFrames = {}

-- Register a frame to close on Escape
-- Uses UISpecialFrames (the standard WoW way)
function EH:RegisterFrame(frameName)
    if not frameName or EH.registeredFrames[frameName] then
        return
    end
    
    -- Add to UISpecialFrames if not already present
    local found = false
    for _, name in ipairs(UISpecialFrames) do
        if name == frameName then
            found = true
            break
        end
    end
    
    if not found then
        tinsert(UISpecialFrames, frameName)
        EH.registeredFrames[frameName] = true
    end
end

-- Unregister a frame (rarely needed, but available)
function EH:UnregisterFrame(frameName)
    if not frameName then return end
    
    for i, name in ipairs(UISpecialFrames) do
        if name == frameName then
            tremove(UISpecialFrames, i)
            EH.registeredFrames[frameName] = nil
            break
        end
    end
end

-- Register all known casino frames
-- Called after frames are created
function EH:RegisterAllFrames()
    -- Main game frames
    EH:RegisterFrame("ChairfacesCasinoLobby")     -- Lobby
    EH:RegisterFrame("ChairfacesCasinoFrame")     -- Blackjack main window
    EH:RegisterFrame("ChairfacesCasinoPoker")     -- Poker main window
    EH:RegisterFrame("ChairfacesCasinoHiLo")      -- High-Lo main window
    
    -- Auxiliary frames
    EH:RegisterFrame("ChairfacesCasinoSettings")  -- Settings panel
    EH:RegisterFrame("ChairfacesCasinoLog")       -- Lobby log panel
    EH:RegisterFrame("ChairfacesCasinoLogPanel")  -- Blackjack log panel
    EH:RegisterFrame("CasinoPokerLogFrame")       -- Poker log
    EH:RegisterFrame("CasinoHiLoLogFrame")        -- HiLo log
    EH:RegisterFrame("BlackjackHostPanel")        -- Blackjack host settings panel
    EH:RegisterFrame("PokerHostPanel")            -- Poker host panel
    
    -- Leaderboard frames
    EH:RegisterFrame("CasinoAllTimeLeaderboard")  -- All-time leaderboard
    EH:RegisterFrame("CasinoSession_blackjack")   -- BJ party session
    EH:RegisterFrame("CasinoSession_poker")       -- Poker party session
    EH:RegisterFrame("CasinoSession_hilo")        -- HiLo party session
    
    -- Popups
    EH:RegisterFrame("BlackjackBetPopup")         -- Bet selection popup
    EH:RegisterFrame("CasinoRecoveryPopup")       -- Blackjack recovery popup
    EH:RegisterFrame("CasinoPokerRecoveryPopup")  -- Poker recovery popup
    
    -- Trixie frames
    EH:RegisterFrame("LobbyTrixieFrame")          -- Lobby Trixie
    EH:RegisterFrame("TrixieIntroContainer")      -- Intro container
    EH:RegisterFrame("TrixieIntroFrame")          -- Intro frame
    EH:RegisterFrame("HelpTrixieFrame")           -- Help Trixie
    
    -- Craps frames
    EH:RegisterFrame("ChairfacesCasinoCraps")     -- Craps main window
    EH:RegisterFrame("CrapsShooterPanel")         -- Shooter selection panel
    EH:RegisterFrame("CrapsPlayerListPanel")      -- Player list panel
    EH:RegisterFrame("CrapsRollCallPanel")        -- Roll call panel
    EH:RegisterFrame("CrapsAllBetsPanel")         -- All bets panel
    EH:RegisterFrame("CrapsBuyInPanel")           -- Buy-in panel
    EH:RegisterFrame("CrapsHostSettingsPanel")    -- Host settings panel
    EH:RegisterFrame("CrapsReceiptPopup")         -- Cash out receipt popup
    EH:RegisterFrame("CrapsPendingJoinsPanel")    -- Pending joins panel
end

-- Initialize
function EH:Initialize()
    -- Register all frames after a short delay to ensure they're created
    C_Timer.After(0.5, function()
        EH:RegisterAllFrames()
    end)
end
