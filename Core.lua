--[[
    Chairface's Casino - Core.lua
    Addon initialization, slash commands, and global namespace
]]

-- Global addon namespace
ChairfacesCasino = ChairfacesCasino or {}
local BJ = ChairfacesCasino

-- Addon info
BJ.name = "ChairfacesCasino"
BJ.version = "1.3.4"

-- Default saved variables
local defaults = {
    settings = {
        soundEnabled = true,
        showTutorialTips = true,
        cardBack = "blue",  -- red, blue, or mtg
        hiloShowTrixie = true,      -- Show Trixie on High-Lo window
        blackjackShowTrixie = true, -- Show Trixie on Blackjack window
        pokerShowTrixie = true,     -- Show Trixie on 5 Card Stud window
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
    if event == "ADDON_LOADED" and arg1 == BJ.name then
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
        ChairfacesCasinoDB = CopyTable(defaults)
    end
    self.db = ChairfacesCasinoDB
    
    -- Merge any missing defaults (for addon updates)
    for k, v in pairs(defaults) do
        if self.db[k] == nil then
            self.db[k] = CopyTable(v)
        end
    end
    
    self:Print("v" .. self.version .. " loaded. Type /cc or /casino to open.")
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
    
    -- Initialize multiplayer communication (Blackjack)
    if self.Multiplayer and self.Multiplayer.Initialize then
        self.Multiplayer:Initialize()
    end
    
    -- Initialize poker multiplayer communication
    if self.PokerMultiplayer and self.PokerMultiplayer.Initialize then
        self.PokerMultiplayer:Initialize()
    end
    
    -- Initialize UI
    if self.UI and self.UI.Initialize then
        self.UI:Initialize()
    end
    
    -- Initialize Poker UI
    if self.UI and self.UI.Poker and self.UI.Poker.Initialize then
        self.UI.Poker:Initialize()
    end
    
    -- Initialize minimap button
    if self.MinimapButton and self.MinimapButton.Initialize then
        self.MinimapButton:Initialize()
    end
    
    -- Load persistent game history for all games
    if self.GameState and self.GameState.LoadHistoryFromDB then
        self.GameState:LoadHistoryFromDB()
    end
    if self.PokerState and self.PokerState.LoadHistoryFromDB then
        self.PokerState:LoadHistoryFromDB()
    end
    if self.HiLoState and self.HiLoState.LoadHistoryFromDB then
        self.HiLoState:LoadHistoryFromDB()
    end
end

function BJ:OnPlayerLogout()
    -- Leave any active table
    if self.Multiplayer and self.Multiplayer.LeaveTable then
        self.Multiplayer:LeaveTable()
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
        BJ:Print("|cff88ff88/cc help|r - Show this help")
        BJ:Print("|cff88ff88/hilo <max> [timer]|r - Quick start High-Lo")
        BJ:Print("   max = max roll, timer = 20-120 sec (default 60)")
        BJ:Print("   Example: /hilo 1000 30")
    elseif cmd == "default" or cmd == "defaults" or cmd == "reset" then
        -- Reset all settings to defaults
        BJ:ResetToDefaults()
    elseif cmd == "intro" then
        -- Show Trixie intro again
        if ChairfacesCasinoSaved then
            ChairfacesCasinoSaved.trixieIntroShown = nil
        end
        BJ:Print("Trixie intro reset! Open the casino to see it again.")
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
        end
    else
        -- Default: open lobby
        if BJ.UI and BJ.UI.ShowLobby then
            BJ.UI:ShowLobby()
        end
    end
end

-- Utility: Deep copy a table
function CopyTable(t)
    if type(t) ~= "table" then return t end
    local copy = {}
    for k, v in pairs(t) do
        copy[k] = CopyTable(v)
    end
    return copy
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
    
    local myName = UnitName("player")
    
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
    -- Format: |Hgarrmission:casino:gamename|h[DisplayText]|h
    -- We use garrmission as the link type since it's handled by SetHyperlink
    return "|cff00ff00|Hgarrmission:casino:" .. gameName .. "|h[" .. (displayText or gameName) .. "]|h|r"
end

-- Hook into chat frame to handle our custom links
local function OnHyperlinkClick(self, link, text, button)
    local linkType, addon, game = strsplit(":", link)
    if linkType == "garrmission" and addon == "casino" then
        if game == "hilo" then
            if BJ.UI and BJ.UI.HiLo then
                BJ.UI.HiLo:Show()
            end
        elseif game == "blackjack" then
            if BJ.UI and BJ.UI.Show then
                BJ.UI:Show()
            end
        elseif game == "poker" then
            if BJ.UI and BJ.UI.Poker then
                BJ.UI.Poker:Show()
            end
        end
        return
    end
end

-- Hook into chat frames
local function HookChatFrame(frame)
    if frame.casinoHooked then return end
    frame:HookScript("OnHyperlinkClick", OnHyperlinkClick)
    frame.casinoHooked = true
end

-- Hook all chat frames
for i = 1, NUM_CHAT_WINDOWS do
    local frame = _G["ChatFrame" .. i]
    if frame then
        HookChatFrame(frame)
    end
end

-- Also hook any new chat frames that get created
hooksecurefunc("FCF_OpenTemporaryWindow", function()
    for i = 1, NUM_CHAT_WINDOWS do
        local frame = _G["ChatFrame" .. i]
        if frame then
            HookChatFrame(frame)
        end
    end
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
    end
    
    -- Update card back
    if BJ.UI and BJ.UI.Cards then
        BJ.UI.Cards:SetCardBack("blue")
    end
    
    BJ:Print("Settings reset to defaults.")
end
