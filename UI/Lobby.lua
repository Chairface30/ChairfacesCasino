--[[
    Chairface's Casino - UI/Lobby.lua
    Main casino lobby - game selection screen with animated elements
]]

local BJ = ChairfacesCasino
local UI = BJ.UI

UI.Lobby = {}
local Lobby = UI.Lobby

local LOBBY_WIDTH = 352
local LOBBY_HEIGHT = 580
local HELP_WIDTH = 525  -- Wide enough for button frame (15+120) + gap (10) + content (360) + padding (20)

-- Easter egg: Trixie poke sounds (default 1 in 500 chance on click)
local DEFAULT_POKE_CHANCE = 500

-- Voice frequency multipliers (how often Trixie speaks during game events)
-- Lower = more frequent, Higher = less frequent
local VOICE_FREQ_OPTIONS = {
    { name = "Always", value = 1 },      -- Always plays
    { name = "Frequent", value = 2 },    -- 50% chance
    { name = "Normal", value = 3 },      -- 33% chance (default)
    { name = "Occasional", value = 5 },  -- 20% chance
    { name = "Rare", value = 10 },       -- 10% chance
}

function Lobby:GetPokeChance()
    -- Try to load from encrypted storage first
    if ChairfacesCasinoSaved and ChairfacesCasinoSaved.pokeChanceEnc then
        if BJ.Compression and BJ.Compression.DecodeFromSave then
            local decoded = BJ.Compression:DecodeFromSave(ChairfacesCasinoSaved.pokeChanceEnc)
            if decoded and type(decoded) == "number" then
                return decoded
            end
        end
    end
    -- Fallback to old unencrypted location (migration)
    if BJ.db and BJ.db.settings and BJ.db.settings.pokeChance then
        local value = BJ.db.settings.pokeChance
        -- Migrate to encrypted storage
        self:SetPokeChance(value)
        BJ.db.settings.pokeChance = nil  -- Clear old storage
        return value
    end
    return DEFAULT_POKE_CHANCE
end

function Lobby:SetPokeChance(value)
    if not ChairfacesCasinoSaved then
        ChairfacesCasinoSaved = {}
    end
    if BJ.Compression and BJ.Compression.EncodeForSave then
        ChairfacesCasinoSaved.pokeChanceEnc = BJ.Compression:EncodeForSave(value)
    end
end

function Lobby:GetVoiceFrequency()
    if BJ.db and BJ.db.settings and BJ.db.settings.voiceFrequency then
        return BJ.db.settings.voiceFrequency
    end
    return 3  -- Default to "Normal"
end

function Lobby:SetVoiceFrequency(value)
    if BJ.db and BJ.db.settings then
        BJ.db.settings.voiceFrequency = value
    end
end

-- Check if voice should play based on frequency setting
function Lobby:ShouldPlayVoice()
    local freq = self:GetVoiceFrequency()
    return math.random(1, freq) == 1
end

function Lobby:TryPlayPokeSound()
    return self:TryPlayPoke()
end

function Lobby:Initialize()
    if self.frame then return end
    self:CreateLobbyFrame()
end

function Lobby:CreateLobbyFrame()
    local frame = CreateFrame("Frame", "ChairfacesCasinoLobby", UIParent, "BackdropTemplate")
    frame:SetSize(LOBBY_WIDTH, LOBBY_HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    frame:SetFrameStrata("HIGH")
    
    -- Background
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    frame:SetBackdropColor(0.08, 0.08, 0.1, 0.97)
    frame:SetBackdropBorderColor(0.6, 0.5, 0.2, 1)
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -5, -5)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)
    
    -- Animated logo centered above game selection
    -- Logo is 200x113 base, scaled to 312x176 (25% wider than 250px buttons)
    local logoWidth = 312
    local logoHeight = 176
    local logoFrame = CreateFrame("Frame", nil, frame)
    logoFrame:SetSize(logoWidth, logoHeight)
    logoFrame:SetPoint("TOP", frame, "TOP", 0, -2)
    
    local logoTexture = logoFrame:CreateTexture(nil, "ARTWORK")
    logoTexture:SetAllPoints()
    logoTexture:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\logo_frames")
    logoTexture:SetTexCoord(0, 1, 1/80, 0)  -- Vertical: first frame, Y-flipped
    
    -- Animate logo continuously
    local logoElapsed = 0
    local logoNumFrames = 80
    local logoFrameTime = 0.065  -- ~15fps (30% slower than 0.05)
    local logoCurrentFrame = 0
    local logoAnimDuration = logoNumFrames * logoFrameTime
    
    logoFrame:SetScript("OnUpdate", function(self, dt)
        logoElapsed = logoElapsed + dt
        
        -- Loop the animation
        if logoElapsed >= logoAnimDuration then
            logoElapsed = logoElapsed - logoAnimDuration
            logoCurrentFrame = 0
        end
        
        local newFrame = math.floor(logoElapsed / logoFrameTime)
        if newFrame ~= logoCurrentFrame and newFrame < logoNumFrames then
            logoCurrentFrame = newFrame
            -- Vertical sprite sheet: adjust top/bottom coords
            local top = logoCurrentFrame / logoNumFrames
            local bottom = (logoCurrentFrame + 1) / logoNumFrames
            logoTexture:SetTexCoord(0, 1, bottom, top)  -- Y-flipped
        end
    end)
    
    -- Game selection panel (centered below logo)
    local gamePanel = CreateFrame("Frame", nil, frame)
    gamePanel:SetSize(300, LOBBY_HEIGHT - logoHeight - 60)
    gamePanel:SetPoint("TOP", logoFrame, "BOTTOM", 0, -15)
    
    -- Games label
    local gamesLabel = gamePanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    gamesLabel:SetPoint("TOP", gamePanel, "TOP", 0, -10)
    gamesLabel:SetText("|cffffd700Select a Game|r")
    
    -- Blackjack button (available) with card icons
    local bjButton = CreateFrame("Button", nil, gamePanel, "BackdropTemplate")
    bjButton:SetSize(250, 60)
    bjButton:SetPoint("TOP", gamesLabel, "BOTTOM", 0, -20)
    bjButton:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    bjButton:SetBackdropColor(0.15, 0.35, 0.15, 1)
    bjButton:SetBackdropBorderColor(0.3, 0.7, 0.3, 1)
    
    -- Left icon: Ace of Spades
    local leftIcon = bjButton:CreateTexture(nil, "ARTWORK")
    leftIcon:SetSize(40, 56)
    leftIcon:SetPoint("LEFT", bjButton, "LEFT", 10, 0)
    leftIcon:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\cards\\A_spades")
    
    -- Right icon: Queen of Hearts
    local rightIcon = bjButton:CreateTexture(nil, "ARTWORK")
    rightIcon:SetSize(40, 56)
    rightIcon:SetPoint("RIGHT", bjButton, "RIGHT", -10, 0)
    rightIcon:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\cards\\Q_hearts")
    
    local bjText = bjButton:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    bjText:SetPoint("CENTER", 0, 5)
    bjText:SetText("|cff00ff00Blackjack|r")
    bjText:SetFont("Fonts\\FRIZQT__.TTF", 18, "OUTLINE")
    
    local bjSubtext = bjButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bjSubtext:SetPoint("CENTER", 0, -12)
    bjSubtext:SetText("|cff88ff88Play Now!|r")
    
    bjButton:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.2, 0.5, 0.2, 1)
        self:SetBackdropBorderColor(0.4, 1, 0.4, 1)
    end)
    bjButton:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.15, 0.35, 0.15, 1)
        self:SetBackdropBorderColor(0.3, 0.7, 0.3, 1)
    end)
    bjButton:SetScript("OnClick", function()
        frame:Hide()
        Lobby:HideHelp(true)  -- Hide help without showing lobby
        if UI.Show then
            UI:Show()
        end
    end)
    
    -- 5 Card Stud button (now available!)
    local fcsButton = CreateFrame("Button", nil, gamePanel, "BackdropTemplate")
    fcsButton:SetSize(250, 60)
    fcsButton:SetPoint("TOP", bjButton, "BOTTOM", 0, -15)
    fcsButton:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    fcsButton:SetBackdropColor(0.15, 0.35, 0.15, 1)
    fcsButton:SetBackdropBorderColor(0.3, 0.7, 0.3, 1)
    
    -- Left icon: 5 of Spades
    local fcsLeftIcon = fcsButton:CreateTexture(nil, "ARTWORK")
    fcsLeftIcon:SetSize(40, 56)
    fcsLeftIcon:SetPoint("LEFT", fcsButton, "LEFT", 10, 0)
    fcsLeftIcon:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\cards\\5_spades")
    
    -- Right icon: Ace of Hearts
    local fcsRightIcon = fcsButton:CreateTexture(nil, "ARTWORK")
    fcsRightIcon:SetSize(40, 56)
    fcsRightIcon:SetPoint("RIGHT", fcsButton, "RIGHT", -10, 0)
    fcsRightIcon:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\cards\\A_hearts")
    
    local fcsText = fcsButton:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    fcsText:SetPoint("CENTER", 0, 5)
    fcsText:SetText("|cff00ff005 Card Stud|r")
    fcsText:SetFont("Fonts\\FRIZQT__.TTF", 18, "OUTLINE")
    
    local fcsSubtext = fcsButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fcsSubtext:SetPoint("CENTER", 0, -12)
    fcsSubtext:SetText("|cff88ff88Play Now!|r")
    
    fcsButton:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.2, 0.5, 0.2, 1)
        self:SetBackdropBorderColor(0.4, 1, 0.4, 1)
    end)
    fcsButton:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.15, 0.35, 0.15, 1)
        self:SetBackdropBorderColor(0.3, 0.7, 0.3, 1)
    end)
    fcsButton:SetScript("OnClick", function()
        frame:Hide()
        Lobby:HideHelp(true)  -- Hide help without showing lobby
        if UI.Poker and UI.Poker.Show then
            UI.Poker:Show()
        end
    end)
    
    -- High-Lo button (now available!)
    local hiloButton = CreateFrame("Button", nil, gamePanel, "BackdropTemplate")
    hiloButton:SetSize(250, 50)
    hiloButton:SetPoint("TOP", fcsButton, "BOTTOM", 0, -15)
    hiloButton:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    hiloButton:SetBackdropColor(0.15, 0.35, 0.15, 1)
    hiloButton:SetBackdropBorderColor(0.3, 0.7, 0.3, 1)
    
    -- Dice icon on left
    local hiloDiceLeft = hiloButton:CreateTexture(nil, "ARTWORK")
    hiloDiceLeft:SetSize(42, 42)
    hiloDiceLeft:SetPoint("LEFT", 10, 0)
    hiloDiceLeft:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\icon")
    
    -- Dice icon on right
    local hiloDiceRight = hiloButton:CreateTexture(nil, "ARTWORK")
    hiloDiceRight:SetSize(42, 42)
    hiloDiceRight:SetPoint("RIGHT", -10, 0)
    hiloDiceRight:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\icon")
    
    local hiloText = hiloButton:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    hiloText:SetPoint("CENTER", 0, 5)
    hiloText:SetText("|cff00ff00High-Lo|r")
    hiloText:SetFont("Fonts\\FRIZQT__.TTF", 18, "OUTLINE")
    
    local hiloSubtext = hiloButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hiloSubtext:SetPoint("CENTER", 0, -12)
    hiloSubtext:SetText("|cff88ff88Play Now!|r")
    
    hiloButton:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.2, 0.5, 0.2, 1)
        self:SetBackdropBorderColor(0.4, 1, 0.4, 1)
    end)
    hiloButton:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.15, 0.35, 0.15, 1)
        self:SetBackdropBorderColor(0.3, 0.7, 0.3, 1)
    end)
    hiloButton:SetScript("OnClick", function()
        frame:Hide()
        Lobby:HideHelp(true)  -- Hide help without showing lobby
        if UI.HiLo and UI.HiLo.Show then
            UI.HiLo:Show()
        end
    end)
    
    -- Coming Soon games (grayed out)
    local comingSoonGames = {
        { name = "Texas Hold'em" },
    }
    
    local prevBtn = hiloButton
    local lastBtn
    for _, game in ipairs(comingSoonGames) do
        local btn = CreateFrame("Button", nil, gamePanel, "BackdropTemplate")
        btn:SetSize(250, 45)
        btn:SetPoint("TOP", prevBtn, "BOTTOM", 0, -15)
        btn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 2,
        })
        btn:SetBackdropColor(0.15, 0.15, 0.15, 0.7)
        btn:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.7)
        btn:Disable()
        
        local btnText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        btnText:SetPoint("CENTER", 0, 3)
        btnText:SetText("|cff555555" .. game.name .. "|r")
        
        local soonText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        soonText:SetPoint("CENTER", 0, -10)
        soonText:SetText("|cff666666Coming Soon|r")
        
        prevBtn = btn
        lastBtn = btn
    end
    
    -- Settings, Help, and Sync buttons in a row
    local buttonRow = CreateFrame("Frame", nil, gamePanel)
    buttonRow:SetSize(250, 35)
    buttonRow:SetPoint("TOP", lastBtn, "BOTTOM", 0, -15)
    
    -- Settings button (left)
    local settingsBtn = CreateFrame("Button", nil, buttonRow, "BackdropTemplate")
    settingsBtn:SetSize(78, 35)
    settingsBtn:SetPoint("LEFT", buttonRow, "LEFT", 0, 0)
    settingsBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    settingsBtn:SetBackdropColor(0.25, 0.2, 0.15, 1)
    settingsBtn:SetBackdropBorderColor(0.5, 0.4, 0.2, 1)
    
    local settingsText = settingsBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    settingsText:SetPoint("CENTER")
    settingsText:SetText("|cffffd700Settings|r")
    
    settingsBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.35, 0.3, 0.2, 1)
        self:SetBackdropBorderColor(0.7, 0.6, 0.3, 1)
    end)
    settingsBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.25, 0.2, 0.15, 1)
        self:SetBackdropBorderColor(0.5, 0.4, 0.2, 1)
    end)
    settingsBtn:SetScript("OnClick", function()
        Lobby:ToggleSettings()
    end)
    
    -- Help button (center)
    local helpBtn = CreateFrame("Button", nil, buttonRow, "BackdropTemplate")
    helpBtn:SetSize(78, 35)
    helpBtn:SetPoint("CENTER", buttonRow, "CENTER", 0, 0)
    helpBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    helpBtn:SetBackdropColor(0.15, 0.25, 0.35, 1)
    helpBtn:SetBackdropBorderColor(0.3, 0.5, 0.7, 1)
    
    local helpText = helpBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    helpText:SetPoint("CENTER")
    helpText:SetText("|cff88ccffHelp|r")
    
    helpBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.2, 0.35, 0.5, 1)
        self:SetBackdropBorderColor(0.4, 0.7, 1, 1)
    end)
    helpBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.15, 0.25, 0.35, 1)
        self:SetBackdropBorderColor(0.3, 0.5, 0.7, 1)
    end)
    helpBtn:SetScript("OnClick", function()
        Lobby:ShowHelp()
    end)
    
    -- Sync button (right)
    local syncBtn = CreateFrame("Button", nil, buttonRow, "BackdropTemplate")
    syncBtn:SetSize(78, 35)
    syncBtn:SetPoint("RIGHT", buttonRow, "RIGHT", 0, 0)
    syncBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    syncBtn:SetBackdropColor(0.2, 0.3, 0.2, 1)
    syncBtn:SetBackdropBorderColor(0.4, 0.6, 0.4, 1)
    
    local syncText = syncBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    syncText:SetPoint("CENTER")
    syncText:SetText("|cff88ff88Sync|r")
    syncBtn.text = syncText
    
    -- Sync button cooldown tracking
    syncBtn.lastClick = 0
    syncBtn.cooldown = 5  -- 5 second cooldown
    
    syncBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.3, 0.4, 0.3, 1)
        self:SetBackdropBorderColor(0.5, 0.8, 0.5, 1)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Sync Game State", 0.5, 1, 0.5)
        GameTooltip:AddLine("Request full state sync from hosts", 1, 1, 1)
        GameTooltip:AddLine("for all active games.", 1, 1, 1)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("5 second cooldown between clicks", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    syncBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.2, 0.3, 0.2, 1)
        self:SetBackdropBorderColor(0.4, 0.6, 0.4, 1)
        GameTooltip:Hide()
    end)
    syncBtn:SetScript("OnClick", function(self)
        local now = GetTime()
        local remaining = self.cooldown - (now - self.lastClick)
        
        if remaining > 0 then
            BJ:Print("|cffff8800Sync on cooldown.|r Wait " .. string.format("%.1f", remaining) .. " seconds.")
            return
        end
        
        self.lastClick = now
        Lobby:RequestFullSync()
    end)
    self.syncBtn = syncBtn
    
    -- Under construction note (below button row with same spacing as game buttons)
    local noteText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    noteText:SetPoint("TOP", buttonRow, "BOTTOM", 0, -15)
    noteText:SetText("|cffff9900~ More games coming soon! ~|r")
    
    -- Version text at bottom right
    local versionText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    versionText:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 8)
    versionText:SetText("|cff888888v" .. BJ.version .. "|r")
    
    -- Trixie on the right side of lobby (same size as games: 274x350)
    local TRIXIE_WIDTH = 274
    local TRIXIE_HEIGHT = 350
    
    -- Parent to UIParent but position relative to lobby frame
    local trixieFrame = CreateFrame("Button", "LobbyTrixieFrame", UIParent)
    trixieFrame:SetSize(TRIXIE_WIDTH, TRIXIE_HEIGHT)
    trixieFrame:SetPoint("LEFT", frame, "RIGHT", 0, 0)
    trixieFrame:SetFrameStrata("HIGH")  -- Same as lobby
    
    -- Random wait image (1-31, includes trixie_tall as wait31)
    local randomWaitIdx = math.random(1, 31)
    local trixieTexture = trixieFrame:CreateTexture(nil, "ARTWORK")
    trixieTexture:SetAllPoints()
    trixieTexture:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\dealer\\trix_wait" .. randomWaitIdx)
    trixieFrame.texture = trixieTexture
    
    -- Easter egg click handler
    trixieFrame:SetScript("OnClick", function()
        Lobby:TryPlayPoke()
    end)
    
    -- Hide when lobby hides
    frame:HookScript("OnHide", function()
        trixieFrame:Hide()
    end)
    frame:HookScript("OnShow", function()
        -- Randomize Trixie pose each time lobby opens
        local newIdx = math.random(1, 31)
        trixieFrame.texture:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\dealer\\trix_wait" .. newIdx)
        Lobby:UpdateLobbyTrixieVisibility()
    end)
    
    self.lobbyTrixie = trixieFrame
    
    frame:Hide()
    self.frame = frame
end

function Lobby:Show()
    if not self.frame then
        self:Initialize()
    end
    
    -- Initialize audio on first show
    if not self.audioInitialized then
        self:InitializeAudio()
        self.audioInitialized = true
    end
    
    -- Apply saved window scale
    self:ApplyWindowScale()
    
    -- Update Lobby Trixie visibility
    self:UpdateLobbyTrixieVisibility()
    
    self.frame:Show()
    
    -- Check for first run intro
    if not ChairfacesCasinoSaved then
        ChairfacesCasinoSaved = {}
    end
    
    -- Force intro to show again for 1.3 release (reset if they haven't seen 1.3 intro)
    if not ChairfacesCasinoSaved.introVersion or ChairfacesCasinoSaved.introVersion < "1.3" then
        ChairfacesCasinoSaved.trixieIntroShown = nil
    end
    
    if not ChairfacesCasinoSaved.trixieIntroShown then
        C_Timer.After(0.5, function()
            self:ShowTrixieIntro()
        end)
        ChairfacesCasinoSaved.trixieIntroShown = true
        ChairfacesCasinoSaved.introVersion = "1.3"  -- Track which version they saw intro for
    end
end

-- Update Lobby Trixie visibility based on setting
function Lobby:UpdateLobbyTrixieVisibility()
    if not self.lobbyTrixie then return end
    
    local showTrixie = true
    if BJ.db and BJ.db.settings then
        showTrixie = BJ.db.settings.showLobbyTrixie ~= false
    end
    
    -- Only show Trixie if setting is enabled AND lobby is visible
    if showTrixie and self.frame and self.frame:IsShown() then
        self.lobbyTrixie:Show()
    else
        self.lobbyTrixie:Hide()
    end
end

-- Apply saved window scale to all casino windows
function Lobby:ApplyWindowScale()
    local scale = 1.0
    if BJ.db and BJ.db.settings and BJ.db.settings.windowScale then
        scale = BJ.db.settings.windowScale
    end
    
    -- Apply to lobby
    if self.frame then
        self.frame:SetScale(scale)
    end
    
    -- Apply to blackjack (uses mainFrame)
    if BJ.UI and BJ.UI.mainFrame then
        BJ.UI.mainFrame:SetScale(scale)
    end
    
    -- Apply to poker
    if BJ.UI and BJ.UI.Poker and BJ.UI.Poker.mainFrame then
        BJ.UI.Poker.mainFrame:SetScale(scale)
    end
    
    -- Apply to high-lo (uses container as outer frame)
    if BJ.UI and BJ.UI.HiLo and BJ.UI.HiLo.container then
        BJ.UI.HiLo.container:SetScale(scale)
    end
    
    -- Apply to settings
    if self.settingsFrame then
        self.settingsFrame:SetScale(scale)
    end
    
    -- Apply to lobby Trixie (since it's parented to UIParent)
    if self.lobbyTrixie then
        self.lobbyTrixie:SetScale(scale)
    end
    
    -- Apply to help Trixie (since it's parented to UIParent)
    if self.helpTrixie then
        self.helpTrixie:SetScale(scale)
    end
end

-- Show Trixie introduction on first run
function Lobby:ShowTrixieIntro()
    -- Hide the lobby while intro is showing
    if self.frame then
        self.frame:Hide()
    end
    
    -- Play fanfare and intro voice
    self:PlayWinSound()
    self:PlayTrixieIntroVoice()
    
    -- Create intro overlay container
    local container = CreateFrame("Frame", "TrixieIntroContainer", UIParent)
    container:SetPoint("CENTER")
    container:SetSize(700, 500)
    container:SetFrameStrata("FULLSCREEN_DIALOG")
    
    -- Go straight to tall Trixie with dialog
    self:ShowIntroPhase2(container)
end

-- Phase 2: Show tall Trixie with dialog
function Lobby:ShowIntroPhase2(container)
    -- Trixie tall image (left side, standing next to dialog)
    -- Original image is 896x1152, display at proper aspect ratio
    -- Use a button frame so it's clickable
    local trixieBtn = CreateFrame("Button", nil, container)
    trixieBtn:SetSize(280, 360)
    trixieBtn:SetPoint("LEFT", container, "LEFT", -20, 0)
    
    -- Random wait image for intro
    local introWaitIdx = math.random(1, 31)
    local trixieTall = trixieBtn:CreateTexture(nil, "ARTWORK")
    trixieTall:SetAllPoints()
    trixieTall:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\dealer\\trix_wait" .. introWaitIdx)
    
    -- Easter egg click handler
    trixieBtn:SetScript("OnClick", function()
        Lobby:TryPlayPoke()
    end)
    
    -- Create intro dialog box (right of Trixie)
    local intro = CreateFrame("Frame", "TrixieIntroFrame", container, "BackdropTemplate")
    intro:SetSize(450, 380)
    intro:SetPoint("LEFT", trixieBtn, "RIGHT", 20, 0)
    intro:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 3,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    intro:SetBackdropColor(0.05, 0.05, 0.08, 0.98)
    intro:SetBackdropBorderColor(0.8, 0.6, 0.2, 1)
    
    -- Sparkle border effect
    local glow = intro:CreateTexture(nil, "BACKGROUND")
    glow:SetPoint("TOPLEFT", -10, 10)
    glow:SetPoint("BOTTOMRIGHT", 10, -10)
    glow:SetColorTexture(1, 0.8, 0.3, 0.15)
    glow:SetBlendMode("ADD")
    
    -- Welcome header
    local headerText = intro:CreateFontString(nil, "OVERLAY")
    headerText:SetFont("Fonts\\MORPHEUS.TTF", 24, "OUTLINE")
    headerText:SetPoint("TOP", intro, "TOP", 0, -25)
    headerText:SetText("|cffffd700~ Welcome to the Casino! ~|r")
    
    -- Speech bubble area
    local speechBg = CreateFrame("Frame", nil, intro, "BackdropTemplate")
    speechBg:SetSize(400, 200)
    speechBg:SetPoint("TOP", headerText, "BOTTOM", 0, -20)
    speechBg:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    speechBg:SetBackdropColor(0.15, 0.12, 0.18, 0.9)
    speechBg:SetBackdropBorderColor(0.5, 0.4, 0.6, 0.8)
    
    -- Trixie's dialogue - she introduces herself with her title
    local dialogText = speechBg:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dialogText:SetPoint("CENTER", 0, 0)
    dialogText:SetWidth(380)
    dialogText:SetJustifyH("CENTER")
    dialogText:SetSpacing(3)
    dialogText:SetText("|cffffd700Bal'a dash!|r |cffffffffWelcome to the finest tables in Azeroth!|r\n\nI'm |cffff99ccTrixie|r, |cff999999Grand High Dealer of the Sin'dorei|r\n...and I'll be your personal dealer tonight.\n\nWe've got |cffffd700Blackjack|r, |cffffd700High-Lo|r, and |cffffd7005 Card Stud|r\non the finest velvet this side of Stormwind.\n|cff888888Guaranteed free of goblin explosives, I promise.|r\n\n|cff88ff88Keep your eyes open, darling...\nwe have even more games coming soon!|r")
    
    -- Continue button
    local continueBtn = CreateFrame("Button", nil, intro, "BackdropTemplate")
    continueBtn:SetSize(120, 35)
    continueBtn:SetPoint("BOTTOM", intro, "BOTTOM", 0, 25)
    continueBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    continueBtn:SetBackdropColor(0.2, 0.5, 0.3, 1)
    continueBtn:SetBackdropBorderColor(0.4, 0.8, 0.5, 1)
    
    local btnText = continueBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btnText:SetPoint("CENTER")
    btnText:SetText("|cffffffffLet's Play!|r")
    
    continueBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.3, 0.6, 0.4, 1)
    end)
    continueBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.2, 0.5, 0.3, 1)
    end)
    continueBtn:SetScript("OnClick", function()
        -- Stop the intro voice
        Lobby:StopTrixieIntroVoice()
        container:Hide()
        container:SetParent(nil)
        -- Show the lobby again
        if Lobby.frame then
            Lobby.frame:Show()
        end
    end)
end

-- Request full state sync for all games
function Lobby:RequestFullSync()
    local SS = BJ.StateSync
    if not SS then
        BJ:Print("|cffff4444StateSync not available.|r")
        return
    end
    
    local syncCount = 0
    local knownHosts = false
    
    -- Check and sync Blackjack
    local bjHost = BJ.Multiplayer and BJ.Multiplayer.currentHost
    if bjHost and bjHost ~= UnitName("player") then
        SS:RequestFullSync("blackjack", bjHost)
        syncCount = syncCount + 1
        knownHosts = true
        BJ:Print("|cff88ff88Requesting Blackjack sync from " .. bjHost .. "|r")
    end
    
    -- Check and sync Poker
    local pokerHost = BJ.PokerMultiplayer and BJ.PokerMultiplayer.currentHost
    if pokerHost and pokerHost ~= UnitName("player") then
        SS:RequestFullSync("poker", pokerHost)
        syncCount = syncCount + 1
        knownHosts = true
        BJ:Print("|cff88ff88Requesting Poker sync from " .. pokerHost .. "|r")
    end
    
    -- Check and sync High-Lo
    local hiloHost = BJ.HiLoMultiplayer and BJ.HiLoMultiplayer.currentHost
    if hiloHost and hiloHost ~= UnitName("player") then
        SS:RequestFullSync("hilo", hiloHost)
        syncCount = syncCount + 1
        knownHosts = true
        BJ:Print("|cff88ff88Requesting High-Lo sync from " .. hiloHost .. "|r")
    end
    
    if not knownHosts then
        -- No known hosts - try to discover them
        BJ:Print("|cff88ccffSearching for active game hosts...|r")
        local sent = SS:BroadcastDiscovery()
        if sent then
            BJ:Print("|cff888888Hosts will respond if found. Click Sync again in a moment.|r")
        end
    elseif syncCount > 0 then
        BJ:Print("|cff00ff00Sync requested for " .. syncCount .. " game(s).|r")
    end
end

function Lobby:Hide()
    if self.frame then
        self.frame:Hide()
    end
end

function Lobby:Toggle()
    if self.frame and self.frame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

-- Hook into UI
function UI:ShowLobby()
    -- Don't open lobby if blackjack game window is already open
    if UI.mainFrame and UI.mainFrame:IsShown() then
        return
    end
    
    -- Hide other game windows
    if UI.HiLo and UI.HiLo.container and UI.HiLo.container:IsShown() then
        UI.HiLo:Hide()
    end
    if UI.Poker and UI.Poker.frame and UI.Poker.frame:IsShown() then
        UI.Poker:Hide()
    end
    
    if not UI.Lobby.frame then
        UI.Lobby:Initialize()
    end
    UI.Lobby:Show()
end

-- Settings Panel
function Lobby:CreateSettingsPanel()
    if self.settingsFrame then return end
    
    local frame = CreateFrame("Frame", "ChairfacesCasinoSettings", UIParent, "BackdropTemplate")
    frame:SetSize(440, 545)  -- Taller for 4 Trixie checkboxes
    frame:SetPoint("CENTER", 200, 0)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    frame:SetFrameStrata("DIALOG")
    
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    frame:SetBackdropColor(0.1, 0.1, 0.12, 0.97)
    frame:SetBackdropBorderColor(0.5, 0.4, 0.2, 1)
    
    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("|cffffd700Settings|r")
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)
    
    -- ========== LEFT COLUMN (Card Deck, Card Back, Dice) ==========
    local leftCol = 115  -- Center of left column
    
    -- Card Deck/Face section
    local faceLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    faceLabel:SetPoint("TOP", frame, "TOPLEFT", leftCol, -20)
    faceLabel:SetText("Card Deck")
    
    local cardDecks = {
        { id = "classic", name = "Classic", texture = "A_spades", path = "cards" },
        { id = "dark", name = "Dark", texture = "A_spades", path = "cards_dark" },
        { id = "warcraft", name = "Warcraft", texture = "A_spades", path = "cards_alt" },
    }
    frame.cardDecks = cardDecks
    
    local savedDeck = "classic"
    if BJ.db and BJ.db.settings and BJ.db.settings.cardDeck then
        savedDeck = BJ.db.settings.cardDeck
    end
    frame.currentDeckIndex = 1
    for i, deck in ipairs(cardDecks) do
        if deck.id == savedDeck then
            frame.currentDeckIndex = i
            break
        end
    end
    
    local facePreview = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    facePreview:SetSize(60, 84)
    facePreview:SetPoint("TOP", faceLabel, "BOTTOM", 0, -5)
    facePreview:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    facePreview:SetBackdropColor(0.15, 0.15, 0.15, 1)
    facePreview:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    
    local faceTex = facePreview:CreateTexture(nil, "ARTWORK")
    faceTex:SetPoint("TOPLEFT", 2, -2)
    faceTex:SetPoint("BOTTOMRIGHT", -2, 2)
    frame.cardDeckTexture = faceTex
    frame.cardDeckPreview = facePreview
    
    -- Animation state for preview
    frame.deckAnimElapsed = 0
    frame.deckAnimFrame = 0
    frame.deckAnimInfo = nil
    
    facePreview:SetScript("OnUpdate", function(self, dt)
        if not frame.deckAnimInfo then return end
        
        frame.deckAnimElapsed = frame.deckAnimElapsed + dt
        local animInfo = frame.deckAnimInfo
        local newFrame = math.floor(frame.deckAnimElapsed / animInfo.frameTime) % animInfo.numFrames
        
        if newFrame ~= frame.deckAnimFrame then
            frame.deckAnimFrame = newFrame
            -- Vertical sprite sheet with Y-flip
            local top = (newFrame + 1) / animInfo.numFrames
            local bottom = newFrame / animInfo.numFrames
            frame.cardDeckTexture:SetTexCoord(0, 1, top, bottom)
        end
    end)
    
    -- Nav buttons for card deck
    local deckPrevBtn = CreateFrame("Button", nil, frame, "BackdropTemplate")
    deckPrevBtn:SetSize(24, 24)
    deckPrevBtn:SetPoint("RIGHT", facePreview, "LEFT", -8, 0)
    deckPrevBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    deckPrevBtn:SetBackdropColor(0.3, 0.3, 0.3, 1)
    deckPrevBtn:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    local deckPrevText = deckPrevBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    deckPrevText:SetPoint("CENTER")
    deckPrevText:SetText("<")
    deckPrevBtn:SetScript("OnClick", function()
        frame.currentDeckIndex = frame.currentDeckIndex - 1
        if frame.currentDeckIndex < 1 then frame.currentDeckIndex = #cardDecks end
        Lobby:UpdateCardDeckPreview()
    end)
    deckPrevBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.4, 0.4, 0.4, 1) end)
    deckPrevBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.3, 0.3, 0.3, 1) end)
    
    local deckNextBtn = CreateFrame("Button", nil, frame, "BackdropTemplate")
    deckNextBtn:SetSize(24, 24)
    deckNextBtn:SetPoint("LEFT", facePreview, "RIGHT", 8, 0)
    deckNextBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    deckNextBtn:SetBackdropColor(0.3, 0.3, 0.3, 1)
    deckNextBtn:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    local deckNextText = deckNextBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    deckNextText:SetPoint("CENTER")
    deckNextText:SetText(">")
    deckNextBtn:SetScript("OnClick", function()
        frame.currentDeckIndex = frame.currentDeckIndex + 1
        if frame.currentDeckIndex > #cardDecks then frame.currentDeckIndex = 1 end
        Lobby:UpdateCardDeckPreview()
    end)
    deckNextBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.4, 0.4, 0.4, 1) end)
    deckNextBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.3, 0.3, 0.3, 1) end)
    
    local deckName = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    deckName:SetPoint("TOP", facePreview, "BOTTOM", 0, -3)
    frame.cardDeckName = deckName
    
    local deckSelectBtn = CreateFrame("Button", nil, frame, "BackdropTemplate")
    deckSelectBtn:SetSize(70, 22)
    deckSelectBtn:SetPoint("TOP", deckName, "BOTTOM", 0, -3)
    deckSelectBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    deckSelectBtn:SetBackdropColor(0.2, 0.4, 0.2, 1)
    deckSelectBtn:SetBackdropBorderColor(0.3, 0.6, 0.3, 1)
    local deckSelectText = deckSelectBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    deckSelectText:SetPoint("CENTER")
    deckSelectText:SetText("|cff00ff00Select|r")
    deckSelectBtn:SetScript("OnClick", function()
        local deck = cardDecks[frame.currentDeckIndex]
        Lobby:SelectCardDeck(deck.id)
    end)
    deckSelectBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.3, 0.5, 0.3, 1) end)
    deckSelectBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.2, 0.4, 0.2, 1) end)
    
    -- Card Back section
    local backLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    backLabel:SetPoint("TOP", deckSelectBtn, "BOTTOM", 0, -12)
    backLabel:SetText("Card Back")
    
    local cardBacks = {
        { id = "blue", name = "Blue", texture = "back_blue" },
        { id = "red", name = "Red", texture = "back_red" },
        { id = "mtg", name = "MTG", texture = "back_mtg" },
        { id = "hs", name = "Hearthstone", texture = "back_hs" },
    }
    frame.cardBacks = cardBacks
    
    local savedBack = "blue"
    if BJ.db and BJ.db.settings and BJ.db.settings.cardBack then
        savedBack = BJ.db.settings.cardBack
    end
    frame.currentBackIndex = 1
    for i, back in ipairs(cardBacks) do
        if back.id == savedBack then
            frame.currentBackIndex = i
            break
        end
    end
    
    local cardPreview = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    cardPreview:SetSize(60, 84)
    cardPreview:SetPoint("TOP", backLabel, "BOTTOM", 0, -5)
    cardPreview:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
    cardPreview:SetBackdropColor(0.15, 0.15, 0.15, 1)
    cardPreview:SetBackdropBorderColor(0, 0.8, 0, 1)
    
    local cardTex = cardPreview:CreateTexture(nil, "ARTWORK")
    cardTex:SetPoint("TOPLEFT", 2, -2)
    cardTex:SetPoint("BOTTOMRIGHT", -2, 2)
    frame.cardBackTexture = cardTex
    
    -- Nav buttons for card back
    local prevBtn = CreateFrame("Button", nil, frame, "BackdropTemplate")
    prevBtn:SetSize(24, 24)
    prevBtn:SetPoint("RIGHT", cardPreview, "LEFT", -8, 0)
    prevBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    prevBtn:SetBackdropColor(0.3, 0.3, 0.3, 1)
    prevBtn:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    local prevText = prevBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    prevText:SetPoint("CENTER")
    prevText:SetText("<")
    prevBtn:SetScript("OnClick", function()
        frame.currentBackIndex = frame.currentBackIndex - 1
        if frame.currentBackIndex < 1 then frame.currentBackIndex = #cardBacks end
        Lobby:UpdateCardBackPreview()
    end)
    prevBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.4, 0.4, 0.4, 1) end)
    prevBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.3, 0.3, 0.3, 1) end)
    
    local nextBtn = CreateFrame("Button", nil, frame, "BackdropTemplate")
    nextBtn:SetSize(24, 24)
    nextBtn:SetPoint("LEFT", cardPreview, "RIGHT", 8, 0)
    nextBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    nextBtn:SetBackdropColor(0.3, 0.3, 0.3, 1)
    nextBtn:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    local nextText = nextBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nextText:SetPoint("CENTER")
    nextText:SetText(">")
    nextBtn:SetScript("OnClick", function()
        frame.currentBackIndex = frame.currentBackIndex + 1
        if frame.currentBackIndex > #cardBacks then frame.currentBackIndex = 1 end
        Lobby:UpdateCardBackPreview()
    end)
    nextBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.4, 0.4, 0.4, 1) end)
    nextBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.3, 0.3, 0.3, 1) end)
    
    local cardName = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cardName:SetPoint("TOP", cardPreview, "BOTTOM", 0, -3)
    frame.cardBackName = cardName
    
    local selectBtn = CreateFrame("Button", nil, frame, "BackdropTemplate")
    selectBtn:SetSize(70, 22)
    selectBtn:SetPoint("TOP", cardName, "BOTTOM", 0, -3)
    selectBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    selectBtn:SetBackdropColor(0.2, 0.4, 0.2, 1)
    selectBtn:SetBackdropBorderColor(0.3, 0.6, 0.3, 1)
    local selectText = selectBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    selectText:SetPoint("CENTER")
    selectText:SetText("|cff00ff00Select|r")
    selectBtn:SetScript("OnClick", function()
        local back = cardBacks[frame.currentBackIndex]
        Lobby:SelectCardBack(back.id)
    end)
    selectBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.3, 0.5, 0.3, 1) end)
    selectBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.2, 0.4, 0.2, 1) end)
    
    -- Dice section
    local diceLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    diceLabel:SetPoint("TOP", selectBtn, "BOTTOM", 0, -12)
    diceLabel:SetText("Dice")
    
    local dicePreview = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    dicePreview:SetSize(40, 40)
    dicePreview:SetPoint("TOP", diceLabel, "BOTTOM", 0, -5)
    dicePreview:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    dicePreview:SetBackdropColor(0.15, 0.15, 0.15, 1)
    dicePreview:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    
    local diceTex = dicePreview:CreateTexture(nil, "ARTWORK")
    diceTex:SetPoint("TOPLEFT", 4, -4)
    diceTex:SetPoint("BOTTOMRIGHT", -4, 4)
    diceTex:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\dice\\d6")
    
    local diceNote = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    diceNote:SetPoint("TOP", dicePreview, "BOTTOM", 0, -3)
    diceNote:SetText("|cff666666(coming soon)|r")
    
    -- ========== RIGHT COLUMN (Audio, Sliders, Trixie) ==========
    local rightCol = 325  -- Center of right column
    local rightLeft = 230  -- Left edge of right column
    
    -- Audio section
    local audioLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    audioLabel:SetPoint("TOP", frame, "TOPLEFT", rightCol, -40)
    audioLabel:SetText("Audio")
    
    local sfxBtn = CreateFrame("Button", nil, frame, "BackdropTemplate")
    sfxBtn:SetSize(85, 26)
    sfxBtn:SetPoint("TOPLEFT", rightLeft, -58)
    sfxBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    sfxBtn:SetBackdropColor(0.2, 0.2, 0.2, 1)
    sfxBtn:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    local sfxIcon = sfxBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sfxIcon:SetPoint("CENTER")
    sfxIcon:SetText("|cff00ff00SFX ON|r")
    frame.sfxIcon = sfxIcon
    frame.sfxBtn = sfxBtn
    sfxBtn:SetScript("OnClick", function() Lobby:ToggleSFX() end)
    sfxBtn:SetScript("OnEnter", function(self)
        if Lobby.sfxEnabled then
            self:SetBackdropColor(0.2, 0.45, 0.2, 1)  -- Brighter green hover
        else
            self:SetBackdropColor(0.3, 0.3, 0.3, 1)  -- Gray hover
        end
    end)
    sfxBtn:SetScript("OnLeave", function(self)
        if Lobby.sfxEnabled then
            self:SetBackdropColor(0.15, 0.35, 0.15, 1)  -- Green normal
        else
            self:SetBackdropColor(0.2, 0.2, 0.2, 1)  -- Gray normal
        end
    end)
    
    local voiceBtn = CreateFrame("Button", nil, frame, "BackdropTemplate")
    voiceBtn:SetSize(85, 26)
    voiceBtn:SetPoint("LEFT", sfxBtn, "RIGHT", 10, 0)
    voiceBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    voiceBtn:SetBackdropColor(0.2, 0.2, 0.2, 1)
    voiceBtn:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    local voiceIcon = voiceBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    voiceIcon:SetPoint("CENTER")
    voiceIcon:SetText("|cff00ff00VOICE ON|r")
    frame.voiceIcon = voiceIcon
    frame.voiceBtn = voiceBtn
    voiceBtn:SetScript("OnClick", function() Lobby:ToggleVoice() end)
    voiceBtn:SetScript("OnEnter", function(self)
        if Lobby.voiceEnabled then
            self:SetBackdropColor(0.2, 0.45, 0.2, 1)  -- Brighter green hover
        else
            self:SetBackdropColor(0.3, 0.3, 0.3, 1)  -- Gray hover
        end
    end)
    voiceBtn:SetScript("OnLeave", function(self)
        if Lobby.voiceEnabled then
            self:SetBackdropColor(0.15, 0.35, 0.15, 1)  -- Green normal
        else
            self:SetBackdropColor(0.2, 0.2, 0.2, 1)  -- Gray normal
        end
    end)
    
    -- Voice Frequency
    local voiceFreqLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    voiceFreqLabel:SetPoint("TOPLEFT", rightLeft, -120)
    voiceFreqLabel:SetText("Voice Frequency:")
    
    local voiceFreqValue = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    voiceFreqValue:SetPoint("TOPRIGHT", -20, -120)
    voiceFreqValue:SetText("|cff88ff88Normal|r")
    frame.voiceFreqValue = voiceFreqValue
    
    local voiceFreqSlider = CreateFrame("Slider", nil, frame, "OptionsSliderTemplate")
    voiceFreqSlider:SetSize(180, 14)
    voiceFreqSlider:SetPoint("TOPLEFT", rightLeft, -135)
    voiceFreqSlider:SetMinMaxValues(1, 5)
    voiceFreqSlider:SetValueStep(1)
    voiceFreqSlider:SetObeyStepOnDrag(true)
    voiceFreqSlider.Low:SetText("")
    voiceFreqSlider.High:SetText("")
    voiceFreqSlider.Text:SetText("")
    frame.voiceFreqSlider = voiceFreqSlider
    
    local function UpdateVoiceFreqDisplay()
        local sliderVal = voiceFreqSlider:GetValue()
        local freqNames = { "Always", "Frequent", "Normal", "Occasional", "Rare" }
        local freqValues = { 1, 2, 3, 5, 10 }
        local freqColors = { "00ff00", "88ff88", "ffffff", "ffaa66", "ff6666" }
        voiceFreqValue:SetText("|cff" .. freqColors[sliderVal] .. freqNames[sliderVal] .. "|r")
        Lobby:SetVoiceFrequency(freqValues[sliderVal])
    end
    voiceFreqSlider:SetScript("OnValueChanged", UpdateVoiceFreqDisplay)
    
    local initFreq = Lobby:GetVoiceFrequency()
    local initSlider = initFreq == 1 and 1 or initFreq == 2 and 2 or initFreq == 3 and 3 or initFreq == 5 and 4 or 5
    voiceFreqSlider:SetValue(initSlider)
    UpdateVoiceFreqDisplay()
    
    -- Minimap slider
    local minimapLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    minimapLabel:SetPoint("TOPLEFT", rightLeft, -165)
    minimapLabel:SetText("Minimap Icon:")
    
    local minimapValue = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    minimapValue:SetPoint("TOPRIGHT", -20, -165)
    minimapValue:SetText("|cff88ff881.5x|r")
    frame.minimapValue = minimapValue
    
    local minimapSlider = CreateFrame("Slider", nil, frame, "OptionsSliderTemplate")
    minimapSlider:SetSize(180, 14)
    minimapSlider:SetPoint("TOPLEFT", rightLeft, -180)
    minimapSlider:SetMinMaxValues(1.5, 5.0)
    minimapSlider:SetValueStep(0.5)
    minimapSlider:SetObeyStepOnDrag(true)
    minimapSlider.Low:SetText("1.5x")
    minimapSlider.High:SetText("5x")
    minimapSlider.Text:SetText("")
    frame.minimapSlider = minimapSlider
    
    local savedMinimapScale = 1.5
    if BJ.db and BJ.db.settings and BJ.db.settings.minimapScale then
        savedMinimapScale = BJ.db.settings.minimapScale
    end
    minimapSlider:SetValue(savedMinimapScale)
    
    local function UpdateMinimapDisplay()
        local val = minimapSlider:GetValue()
        minimapValue:SetText(string.format("|cff88ff88%.1fx|r", val))
        Lobby:SetMinimapScale(val)
    end
    minimapSlider:SetScript("OnValueChanged", UpdateMinimapDisplay)
    UpdateMinimapDisplay()
    
    -- Hide minimap checkbox
    local hideMinimapCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    hideMinimapCheck:SetSize(22, 22)
    hideMinimapCheck:SetPoint("TOPLEFT", rightLeft, -200)
    hideMinimapCheck:SetScript("OnClick", function(self)
        local hide = self:GetChecked()
        if BJ.MinimapButton then
            if hide then BJ.MinimapButton:Hide() else BJ.MinimapButton:Show() end
        end
        if ChairfacesCasinoDB then ChairfacesCasinoDB.minimapHidden = hide end
    end)
    frame.hideMinimapCheck = hideMinimapCheck
    if ChairfacesCasinoDB and ChairfacesCasinoDB.minimapHidden then
        hideMinimapCheck:SetChecked(true)
    end
    
    local hideMinimapLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hideMinimapLabel:SetPoint("LEFT", hideMinimapCheck, "RIGHT", 2, 0)
    hideMinimapLabel:SetText("Hide minimap icon")
    
    -- Show Trixie section label
    local trixieLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    trixieLabel:SetPoint("TOPLEFT", rightLeft, -220)
    trixieLabel:SetText("Show Trixie")
    
    -- Lobby Trixie checkbox
    local showLobbyTrixieCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    showLobbyTrixieCheck:SetSize(22, 22)
    showLobbyTrixieCheck:SetPoint("TOPLEFT", rightLeft, -238)
    showLobbyTrixieCheck:SetScript("OnClick", function(self)
        local show = self:GetChecked()
        if BJ.db and BJ.db.settings then
            BJ.db.settings.showLobbyTrixie = show
        end
        Lobby:UpdateLobbyTrixieVisibility()
        Lobby:UpdateHelpTrixieVisibility()
    end)
    frame.showLobbyTrixieCheck = showLobbyTrixieCheck
    local showLobbyTrixie = true
    if BJ.db and BJ.db.settings then
        showLobbyTrixie = BJ.db.settings.showLobbyTrixie ~= false
    end
    showLobbyTrixieCheck:SetChecked(showLobbyTrixie)
    
    local showLobbyTrixieLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    showLobbyTrixieLabel:SetPoint("LEFT", showLobbyTrixieCheck, "RIGHT", 2, 0)
    showLobbyTrixieLabel:SetText("Lobby")
    
    -- High-Lo Trixie checkbox
    local showHiLoTrixieCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    showHiLoTrixieCheck:SetSize(22, 22)
    showHiLoTrixieCheck:SetPoint("TOPLEFT", rightLeft, -260)
    showHiLoTrixieCheck:SetScript("OnClick", function(self)
        local show = self:GetChecked()
        if BJ.db and BJ.db.settings then
            BJ.db.settings.hiloShowTrixie = show
        end
        if BJ.UI and BJ.UI.HiLo and BJ.UI.HiLo.UpdateTrixieVisibility then
            BJ.UI.HiLo:UpdateTrixieVisibility()
        end
    end)
    frame.showHiLoTrixieCheck = showHiLoTrixieCheck
    local showHiLoTrixie = true
    if BJ.db and BJ.db.settings then
        showHiLoTrixie = BJ.db.settings.hiloShowTrixie ~= false
    end
    showHiLoTrixieCheck:SetChecked(showHiLoTrixie)
    
    local showHiLoTrixieLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    showHiLoTrixieLabel:SetPoint("LEFT", showHiLoTrixieCheck, "RIGHT", 2, 0)
    showHiLoTrixieLabel:SetText("High-Lo")
    
    -- Blackjack Trixie checkbox
    local showBJTrixieCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    showBJTrixieCheck:SetSize(22, 22)
    showBJTrixieCheck:SetPoint("TOPLEFT", rightLeft, -282)
    showBJTrixieCheck:SetScript("OnClick", function(self)
        local show = self:GetChecked()
        if BJ.db and BJ.db.settings then
            BJ.db.settings.blackjackShowTrixie = show
        end
        if BJ.UI and BJ.UI.SetTrixieVisibility then
            BJ.UI:SetTrixieVisibility(show)
        end
    end)
    frame.showBJTrixieCheck = showBJTrixieCheck
    local showBJTrixie = true
    if BJ.db and BJ.db.settings then
        showBJTrixie = BJ.db.settings.blackjackShowTrixie ~= false
    end
    showBJTrixieCheck:SetChecked(showBJTrixie)
    
    local showBJTrixieLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    showBJTrixieLabel:SetPoint("LEFT", showBJTrixieCheck, "RIGHT", 2, 0)
    showBJTrixieLabel:SetText("Blackjack")
    
    -- Poker Trixie checkbox
    local showPokerTrixieCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    showPokerTrixieCheck:SetSize(22, 22)
    showPokerTrixieCheck:SetPoint("TOPLEFT", rightLeft, -304)
    showPokerTrixieCheck:SetScript("OnClick", function(self)
        local show = self:GetChecked()
        if BJ.db and BJ.db.settings then
            BJ.db.settings.pokerShowTrixie = show
        end
        if BJ.UI and BJ.UI.Poker and BJ.UI.Poker.SetTrixieVisibility then
            BJ.UI.Poker:SetTrixieVisibility(show)
        end
    end)
    frame.showPokerTrixieCheck = showPokerTrixieCheck
    local showPokerTrixie = true
    if BJ.db and BJ.db.settings then
        showPokerTrixie = BJ.db.settings.pokerShowTrixie ~= false
    end
    showPokerTrixieCheck:SetChecked(showPokerTrixie)
    
    local showPokerTrixieLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    showPokerTrixieLabel:SetPoint("LEFT", showPokerTrixieCheck, "RIGHT", 2, 0)
    showPokerTrixieLabel:SetText("5 Card Stud")
    
    -- Window Scale slider
    local windowLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    windowLabel:SetPoint("TOPLEFT", rightLeft, -332)
    windowLabel:SetText("Window Scale:")
    
    local windowValue = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    windowValue:SetPoint("TOPRIGHT", -20, -332)
    windowValue:SetText("|cff88ff88100%|r")
    frame.windowValue = windowValue
    
    local windowSlider = CreateFrame("Slider", nil, frame, "OptionsSliderTemplate")
    windowSlider:SetSize(180, 14)
    windowSlider:SetPoint("TOPLEFT", rightLeft, -347)
    windowSlider:SetMinMaxValues(0.6, 1.2)
    windowSlider:SetValueStep(0.05)
    windowSlider:SetObeyStepOnDrag(true)
    windowSlider.Low:SetText("60%")
    windowSlider.High:SetText("120%")
    windowSlider.Text:SetText("")
    frame.windowSlider = windowSlider
    
    local savedWindowScale = 1.0
    if BJ.db and BJ.db.settings and BJ.db.settings.windowScale then
        savedWindowScale = BJ.db.settings.windowScale
    end
    windowSlider:SetValue(savedWindowScale)
    
    local function UpdateWindowDisplayText()
        local val = windowSlider:GetValue()
        windowValue:SetText(string.format("|cff88ff88%d%%|r", math.floor(val * 100 + 0.5)))
    end
    local function ApplyWindowScale()
        local val = windowSlider:GetValue()
        Lobby:SetWindowScale(val)
    end
    windowSlider:SetScript("OnValueChanged", UpdateWindowDisplayText)
    windowSlider:SetScript("OnMouseUp", ApplyWindowScale)
    UpdateWindowDisplayText()
    
    -- Replay Intro button (was "Meet Trixie!")
    local replayIntroBtn = CreateFrame("Button", nil, frame, "BackdropTemplate")
    replayIntroBtn:SetSize(180, 28)
    replayIntroBtn:SetPoint("TOPLEFT", rightLeft, -382)
    replayIntroBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    replayIntroBtn:SetBackdropColor(0.4, 0.2, 0.3, 1)
    replayIntroBtn:SetBackdropBorderColor(0.6, 0.3, 0.4, 1)
    local replayIntroText = replayIntroBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    replayIntroText:SetPoint("CENTER")
    replayIntroText:SetText("|cffff99ccReplay Intro|r")
    replayIntroBtn:SetScript("OnClick", function()
        frame:Hide()
        if Lobby.frame then Lobby.frame:Hide() end
        Lobby:ShowTrixieIntro()
    end)
    replayIntroBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.5, 0.3, 0.4, 1) end)
    replayIntroBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.4, 0.2, 0.3, 1) end)
    
    -- Debug section (hidden unless debug mode) - positioned below Replay Intro button
    local pokeSection = CreateFrame("Frame", nil, frame)
    pokeSection:SetSize(180, 40)
    pokeSection:SetPoint("TOPLEFT", rightLeft, -420)  -- Below Replay Intro button
    frame.pokeSection = pokeSection
    
    local pokeLabel = pokeSection:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pokeLabel:SetPoint("TOPLEFT", 0, 0)
    pokeLabel:SetText("|cffff00ffDebug:|r Poke (1 in X):")
    
    local pokeInput = CreateFrame("EditBox", nil, pokeSection, "BackdropTemplate")
    pokeInput:SetSize(50, 18)
    pokeInput:SetPoint("TOPLEFT", 0, -15)
    pokeInput:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    pokeInput:SetBackdropColor(0.15, 0.15, 0.2, 1)
    pokeInput:SetBackdropBorderColor(0.5, 0.3, 0.5, 1)
    pokeInput:SetFontObject(GameFontNormalSmall)
    pokeInput:SetTextColor(1, 1, 1)
    pokeInput:SetJustifyH("CENTER")
    pokeInput:SetAutoFocus(false)
    pokeInput:SetNumeric(true)
    pokeInput:SetMaxLetters(5)
    pokeInput:SetText(tostring(Lobby:GetPokeChance()))
    pokeInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    pokeInput:SetScript("OnEnterPressed", function(self)
        local val = tonumber(self:GetText()) or 500
        if val < 1 then val = 1 end
        Lobby:SetPokeChance(val)
        self:SetText(tostring(val))
        self:ClearFocus()
    end)
    frame.pokeInput = pokeInput
    
    if not (BJ.TestMode and BJ.TestMode.enabled) then
        pokeSection:Hide()
    end
    
    frame:Hide()
    self.settingsFrame = frame
    
    -- Initialize previews
    self:UpdateCardBackPreview()
    self:UpdateCardDeckPreview()
end

function Lobby:UpdateCardBackPreview()
    if not self.settingsFrame then return end
    
    local frame = self.settingsFrame
    local back = frame.cardBacks[frame.currentBackIndex]
    
    frame.cardBackTexture:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\cards\\" .. back.texture)
    frame.cardBackName:SetText("|cffffffff" .. back.name .. "|r")
end

function Lobby:SelectCardBack(backId)
    -- Ensure db is initialized
    if not BJ.db then
        BJ.db = ChairfacesCasinoDB or { settings = { cardBack = "blue" } }
    end
    if not BJ.db.settings then
        BJ.db.settings = { cardBack = "blue" }
    end
    
    BJ.db.settings.cardBack = backId
    
    -- Update cards in game
    if BJ.UI and BJ.UI.Cards then
        BJ.UI.Cards:SetCardBack(backId)
    end
    
    -- Find index and update preview to show selected
    if self.settingsFrame then
        for i, back in ipairs(self.settingsFrame.cardBacks) do
            if back.id == backId then
                self.settingsFrame.currentBackIndex = i
                break
            end
        end
        self:UpdateCardBackPreview()
    end
    
    BJ:Print("Card back set to: " .. backId)
end

function Lobby:UpdateCardDeckPreview()
    if not self.settingsFrame then return end
    
    local frame = self.settingsFrame
    local deck = frame.cardDecks[frame.currentDeckIndex]
    
    -- Check if this deck has animated cards (show Ace of Spades as preview)
    local animInfo = nil
    if deck.id == "warcraft" and BJ.UI and BJ.UI.Cards then
        animInfo = BJ.UI.Cards.animatedCards["A_spades"]
    end
    
    if animInfo then
        -- Use animated sprite sheet
        frame.cardDeckTexture:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\" .. deck.path .. "\\" .. animInfo.spriteFile)
        frame.deckAnimInfo = animInfo
        frame.deckAnimElapsed = 0
        frame.deckAnimFrame = 0
        -- Set initial frame (Y-flipped)
        local top = 1 / animInfo.numFrames
        local bottom = 0
        frame.cardDeckTexture:SetTexCoord(0, 1, top, bottom)
    else
        -- Static texture
        frame.cardDeckTexture:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\" .. deck.path .. "\\" .. deck.texture)
        frame.cardDeckTexture:SetTexCoord(0, 1, 0, 1)
        frame.deckAnimInfo = nil
    end
    
    frame.cardDeckName:SetText("|cffffffff" .. deck.name .. "|r")
end

function Lobby:SelectCardDeck(deckId)
    -- Ensure db is initialized
    if not BJ.db then
        BJ.db = ChairfacesCasinoDB or { settings = { cardDeck = "classic" } }
    end
    if not BJ.db.settings then
        BJ.db.settings = { cardDeck = "classic" }
    end
    
    BJ.db.settings.cardDeck = deckId
    
    -- Update cards system
    if BJ.UI and BJ.UI.Cards then
        BJ.UI.Cards:SetCardDeck(deckId)
    end
    
    -- Find index and update preview to show selected
    if self.settingsFrame then
        for i, deck in ipairs(self.settingsFrame.cardDecks) do
            if deck.id == deckId then
                self.settingsFrame.currentDeckIndex = i
                break
            end
        end
        self:UpdateCardDeckPreview()
    end
    
    BJ:Print("Card deck set to: " .. deckId)
end

function Lobby:SetMinimapScale(scale)
    -- Ensure db is initialized
    if not BJ.db then
        BJ.db = ChairfacesCasinoDB or { settings = {} }
    end
    if not BJ.db.settings then
        BJ.db.settings = {}
    end
    
    BJ.db.settings.minimapScale = scale
    
    -- Apply to minimap button
    if BJ.MinimapButton and BJ.MinimapButton.button then
        local baseSize = 32
        local newSize = baseSize * scale
        BJ.MinimapButton.button:SetSize(newSize, newSize)
        BJ.MinimapButton.currentScale = scale  -- Store for hover sizing
        
        -- Scale the overlay and background textures
        if BJ.MinimapButton.button.overlay then
            local overlaySize = 53 * scale
            BJ.MinimapButton.button.overlay:SetSize(overlaySize, overlaySize)
        end
        if BJ.MinimapButton.button.background then
            local bgSize = 20 * scale
            BJ.MinimapButton.button.background:SetSize(bgSize, bgSize)
        end
    end
end

function Lobby:SetWindowScale(scale)
    -- Ensure db is initialized
    if not BJ.db then
        BJ.db = ChairfacesCasinoDB or { settings = {} }
    end
    if not BJ.db.settings then
        BJ.db.settings = {}
    end
    
    BJ.db.settings.windowScale = scale
    
    -- Apply to all casino windows
    local windows = {}
    
    -- Lobby
    if self.frame then
        table.insert(windows, self.frame)
    end
    
    -- Blackjack (uses mainFrame)
    if BJ.UI and BJ.UI.mainFrame then
        table.insert(windows, BJ.UI.mainFrame)
    end
    
    -- Poker
    if BJ.UI and BJ.UI.Poker and BJ.UI.Poker.mainFrame then
        table.insert(windows, BJ.UI.Poker.mainFrame)
    end
    
    -- High-Lo (uses container as outer frame)
    if BJ.UI and BJ.UI.HiLo and BJ.UI.HiLo.container then
        table.insert(windows, BJ.UI.HiLo.container)
    end
    
    -- Settings panel
    if self.settingsFrame then
        table.insert(windows, self.settingsFrame)
    end
    
    -- Lobby Trixie
    if self.lobbyTrixie then
        table.insert(windows, self.lobbyTrixie)
    end
    
    for _, window in ipairs(windows) do
        if window and window.SetScale then
            window:SetScale(scale)
        end
    end
end

function Lobby:ToggleSettings()
    if not self.settingsFrame then
        self:CreateSettingsPanel()
    end
    
    if self.settingsFrame:IsShown() then
        self.settingsFrame:Hide()
    else
        self:ShowSettings()
    end
end

function Lobby:ShowSettings()
    if not self.settingsFrame then
        self:CreateSettingsPanel()
    end
    
    -- Set current index to match saved setting
    local currentBack = "blue"
    if BJ.db and BJ.db.settings and BJ.db.settings.cardBack then
        currentBack = BJ.db.settings.cardBack
    end
    for i, back in ipairs(self.settingsFrame.cardBacks) do
        if back.id == currentBack then
            self.settingsFrame.currentBackIndex = i
            break
        end
    end
    
    -- Update deck selection to match current setting
    local currentDeck = "classic"
    if BJ.db and BJ.db.settings and BJ.db.settings.cardDeck then
        currentDeck = BJ.db.settings.cardDeck
    end
    for i, deck in ipairs(self.settingsFrame.cardDecks) do
        if deck.id == currentDeck then
            self.settingsFrame.currentDeckIndex = i
            break
        end
    end
    
    self:UpdateCardBackPreview()
    self:UpdateCardDeckPreview()
    self:UpdateAudioControls()
    
    -- Update debug section visibility
    if self.settingsFrame.pokeSection then
        if BJ.TestMode and BJ.TestMode.enabled then
            self.settingsFrame.pokeSection:Show()
            -- Update the poke input value
            if self.settingsFrame.pokeInput then
                self.settingsFrame.pokeInput:SetText(tostring(self:GetPokeChance()))
            end
        else
            self.settingsFrame.pokeSection:Hide()
        end
    end
    
    self.settingsFrame:Show()
end

-- ========== AUDIO SYSTEM ==========
Lobby.sfxEnabled = true
Lobby.voiceEnabled = true

function Lobby:InitializeAudio()
    -- Ensure db is initialized
    if not BJ.db then
        BJ.db = ChairfacesCasinoDB or { settings = {} }
    end
    if not BJ.db.settings then
        BJ.db.settings = {}
    end
    
    -- Load saved settings
    if BJ.db.settings.sfxEnabled ~= nil then
        self.sfxEnabled = BJ.db.settings.sfxEnabled
    else
        self.sfxEnabled = true  -- Default SFX on
    end
    
    if BJ.db.settings.voiceEnabled ~= nil then
        self.voiceEnabled = BJ.db.settings.voiceEnabled
    else
        self.voiceEnabled = true  -- Default Voice on
    end
end

function Lobby:ToggleSFX()
    self.sfxEnabled = not self.sfxEnabled
    self:SaveAudioSettings()
    self:UpdateAudioControls()
end

function Lobby:ToggleVoice()
    self.voiceEnabled = not self.voiceEnabled
    self:SaveAudioSettings()
    self:UpdateAudioControls()
end

function Lobby:SaveAudioSettings()
    if not BJ.db then
        BJ.db = ChairfacesCasinoDB or { settings = {} }
    end
    if not BJ.db.settings then
        BJ.db.settings = {}
    end
    
    BJ.db.settings.sfxEnabled = self.sfxEnabled
    BJ.db.settings.voiceEnabled = self.voiceEnabled
end

function Lobby:UpdateAudioControls()
    if not self.settingsFrame then return end
    
    local frame = self.settingsFrame
    
    -- Update SFX button - green background when ON
    if frame.sfxBtn then
        if self.sfxEnabled then
            frame.sfxIcon:SetText("|cffffffff SFX ON|r")
            frame.sfxBtn:SetBackdropColor(0.15, 0.35, 0.15, 1)
            frame.sfxBtn:SetBackdropBorderColor(0.3, 0.7, 0.3, 1)
        else
            frame.sfxIcon:SetText("|cffaaaaaa SFX OFF|r")
            frame.sfxBtn:SetBackdropColor(0.2, 0.2, 0.2, 1)
            frame.sfxBtn:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
        end
    end
    
    -- Update Voice button
    if frame.voiceBtn then
        if self.voiceEnabled then
            frame.voiceIcon:SetText("|cffffffff VOICE ON|r")
            frame.voiceBtn:SetBackdropColor(0.15, 0.35, 0.15, 1)
            frame.voiceBtn:SetBackdropBorderColor(0.3, 0.7, 0.3, 1)
        else
            frame.voiceIcon:SetText("|cffaaaaaa VOICE OFF|r")
            frame.voiceBtn:SetBackdropColor(0.2, 0.2, 0.2, 1)
            frame.voiceBtn:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
        end
    end
end

-- Play sound effects (called from game code)
function Lobby:PlayBustSound()
    if not self.sfxEnabled then return end
    PlaySound(8959, "SFX")
end

function Lobby:PlayWinSound()
    if not self.sfxEnabled then return end
    local soundFile = "Interface\\AddOns\\Chairfaces Casino\\Sounds\\fanfare.ogg"
    PlaySoundFile(soundFile, "SFX")
end

function Lobby:PlayShuffleSound()
    if not self.sfxEnabled then return end
    local soundFile = "Interface\\AddOns\\Chairfaces Casino\\Sounds\\shuffle.ogg"
    PlaySoundFile(soundFile, "SFX")
end

function Lobby:PlayCardSound()
    if not self.sfxEnabled then return end
    local soundFile = "Interface\\AddOns\\Chairfaces Casino\\Sounds\\flycard.ogg"
    PlaySoundFile(soundFile, "SFX")
end

-- Trixie voice lines (play at ~25% chance)
function Lobby:PlayTrixieIntroVoice()
    if not self.voiceEnabled then return end
    local soundFile = "Interface\\AddOns\\Chairfaces Casino\\Sounds\\trix_intro.ogg"
    local willPlay, soundHandle = PlaySoundFile(soundFile, "SFX")
    if willPlay then
        self.introSoundHandle = soundHandle
    end
end

function Lobby:StopTrixieIntroVoice()
    if self.introSoundHandle then
        StopSound(self.introSoundHandle)
        self.introSoundHandle = nil
    end
end

function Lobby:PlayTrixieBlackjackVoice()
    if not self.voiceEnabled then return end
    if not self:ShouldPlayVoice() then return end
    local soundFile = "Interface\\AddOns\\Chairfaces Casino\\Sounds\\trix_blackjack.ogg"
    PlaySoundFile(soundFile, "SFX")
end

-- Generic bad reaction voice (for any loss/bad event)
function Lobby:PlayTrixieBadVoice()
    if not self.voiceEnabled then return end
    if not self:ShouldPlayVoice() then return end
    local sounds = {
        "Interface\\AddOns\\Chairfaces Casino\\Sounds\\trix_bad1.ogg",
        "Interface\\AddOns\\Chairfaces Casino\\Sounds\\trix_bad2.ogg",
        "Interface\\AddOns\\Chairfaces Casino\\Sounds\\trix_bad3.ogg",
    }
    local soundFile = sounds[math.random(1, #sounds)]
    PlaySoundFile(soundFile, "SFX")
end

-- Blackjack-specific bust voice (includes context-specific bust clips)
function Lobby:PlayTrixieBustVoice()
    if not self.voiceEnabled then return end
    if not self:ShouldPlayVoice() then return end
    local sounds = {
        "Interface\\AddOns\\Chairfaces Casino\\Sounds\\trix_bust.ogg",
        "Interface\\AddOns\\Chairfaces Casino\\Sounds\\trix_bust2.ogg",
        "Interface\\AddOns\\Chairfaces Casino\\Sounds\\trix_bad1.ogg",
        "Interface\\AddOns\\Chairfaces Casino\\Sounds\\trix_bad2.ogg",
        "Interface\\AddOns\\Chairfaces Casino\\Sounds\\trix_bad3.ogg",
    }
    local soundFile = sounds[math.random(1, #sounds)]
    PlaySoundFile(soundFile, "SFX")
end

function Lobby:PlayTrixieWoohooVoice()
    if not self.voiceEnabled then return end
    if not self:ShouldPlayVoice() then return end
    local sounds = {
        "Interface\\AddOns\\Chairfaces Casino\\Sounds\\trix_woohoo.ogg",
        "Interface\\AddOns\\Chairfaces Casino\\Sounds\\trix_cheer1.ogg",
        "Interface\\AddOns\\Chairfaces Casino\\Sounds\\trix_cheer2.ogg",
        "Interface\\AddOns\\Chairfaces Casino\\Sounds\\trix_cheer3.ogg",
        "Interface\\AddOns\\Chairfaces Casino\\Sounds\\trix_cheer4.ogg",
        "Interface\\AddOns\\Chairfaces Casino\\Sounds\\trix_cheer5.ogg",
        "Interface\\AddOns\\Chairfaces Casino\\Sounds\\trix_cheer6.ogg",
    }
    local soundFile = sounds[math.random(1, #sounds)]
    PlaySoundFile(soundFile, "SFX")
end

function Lobby:PlayGameStartSound()
    local soundFile = "Interface\\AddOns\\Chairfaces Casino\\Sounds\\chips.ogg"
    PlaySoundFile(soundFile, "SFX")
end

-- ========== LOG WINDOW ==========
function Lobby:CreateLogWindow()
    if self.logFrame then return end
    
    local frame = CreateFrame("Frame", "ChairfacesCasinoLog", UIParent, "BackdropTemplate")
    frame:SetSize(350, 200)
    frame:SetPoint("BOTTOMLEFT", 20, 200)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    frame:SetFrameStrata("MEDIUM")
    frame:SetResizable(true)
    frame:SetResizeBounds(200, 100, 600, 400)
    
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    frame:SetBackdropColor(0.05, 0.05, 0.08, 0.9)
    frame:SetBackdropBorderColor(0.4, 0.35, 0.2, 1)
    
    -- Title bar
    local titleBar = CreateFrame("Frame", nil, frame)
    titleBar:SetHeight(20)
    titleBar:SetPoint("TOPLEFT", 2, -2)
    titleBar:SetPoint("TOPRIGHT", -2, -2)
    
    local titleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    titleText:SetPoint("LEFT", 8, 0)
    titleText:SetText("|cffffd700Casino Log|r")
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetSize(20, 20)
    closeBtn:SetPoint("TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)
    
    -- Clear button
    local clearBtn = CreateFrame("Button", nil, frame, "BackdropTemplate")
    clearBtn:SetSize(50, 16)
    clearBtn:SetPoint("TOPRIGHT", closeBtn, "TOPLEFT", -5, -2)
    clearBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    clearBtn:SetBackdropColor(0.3, 0.3, 0.3, 1)
    clearBtn:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    
    local clearText = clearBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    clearText:SetPoint("CENTER")
    clearText:SetText("Clear")
    
    clearBtn:SetScript("OnClick", function()
        Lobby:ClearLog()
    end)
    
    -- Scroll frame for messages
    local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 8, -24)
    scrollFrame:SetPoint("BOTTOMRIGHT", -28, 8)
    
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(1, 1)  -- Will be updated dynamically
    scrollFrame:SetScrollChild(scrollChild)
    
    -- Message container
    local messageFrame = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    messageFrame:SetPoint("TOPLEFT", 0, 0)
    messageFrame:SetWidth(300)
    messageFrame:SetJustifyH("LEFT")
    messageFrame:SetJustifyV("TOP")
    messageFrame:SetText("")
    
    frame.scrollFrame = scrollFrame
    frame.scrollChild = scrollChild
    frame.messageFrame = messageFrame
    frame.messages = {}
    
    -- Resize handle
    local resizeBtn = CreateFrame("Button", nil, frame)
    resizeBtn:SetSize(16, 16)
    resizeBtn:SetPoint("BOTTOMRIGHT", -2, 2)
    resizeBtn:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeBtn:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeBtn:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    
    resizeBtn:SetScript("OnMouseDown", function()
        frame:StartSizing("BOTTOMRIGHT")
    end)
    resizeBtn:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        messageFrame:SetWidth(scrollFrame:GetWidth() - 10)
    end)
    
    frame:Hide()
    self.logFrame = frame
end

function Lobby:AddLogMessage(msg)
    if not self.logFrame then
        self:CreateLogWindow()
    end
    
    local frame = self.logFrame
    table.insert(frame.messages, msg)
    
    -- Keep only last 100 messages
    while #frame.messages > 100 do
        table.remove(frame.messages, 1)
    end
    
    -- Update display
    local text = table.concat(frame.messages, "\n")
    frame.messageFrame:SetText(text)
    
    -- Update scroll child height
    local textHeight = frame.messageFrame:GetStringHeight()
    frame.scrollChild:SetHeight(textHeight + 10)
    
    -- Auto-scroll to bottom
    C_Timer.After(0.01, function()
        if frame.scrollFrame then
            frame.scrollFrame:SetVerticalScroll(frame.scrollFrame:GetVerticalScrollRange())
        end
    end)
end

function Lobby:ClearLog()
    if not self.logFrame then return end
    self.logFrame.messages = {}
    self.logFrame.messageFrame:SetText("")
    self.logFrame.scrollChild:SetHeight(1)
end

function Lobby:ShowLog()
    if not self.logFrame then
        self:CreateLogWindow()
    end
    self.logFrame:Show()
end

function Lobby:HideLog()
    if self.logFrame then
        self.logFrame:Hide()
    end
end

function Lobby:ToggleLog()
    if not self.logFrame then
        self:CreateLogWindow()
    end
    if self.logFrame:IsShown() then
        self.logFrame:Hide()
    else
        self.logFrame:Show()
    end
end

--[[
    HELP PANEL
    Shows Trixie explaining game rules with scrollable content
]]

-- Help text content
Lobby.helpContent = {
    blackjack = {
        title = "Blackjack",
        text = [[|cffffd700Welcome to Blackjack!|r

|cff88ffffObjective:|r
Beat the dealer by getting a hand value closer to 21 without going over.

|cff88ffffCard Values:|r
- Number cards (2-10): Face value
- Face cards (J, Q, K): 10 points
- Aces: 1 or 11 points (whichever is better)

|cff88ffffHow to Play:|r
1. The host opens a table and sets the ante
2. Players join by clicking ANTE
3. Everyone gets 2 cards; dealer shows one card face-up
4. On your turn, choose:
   - |cff00ff00HIT|r: Take another card
   - |cff00ff00STAND|r: Keep your current hand
   - |cff00ff00DOUBLE|r: Double your bet, take one card, then stand
   - |cff00ff00SPLIT|r: If you have a pair, split into two hands

|cff88ffffWinning:|r
- Get closer to 21 than the dealer without busting
- |cffffd700Blackjack|r (Ace + 10-value card) pays 3:2
- Regular wins pay 1:1
- Tie (Push) returns your bet

|cff88ffffDealer Rules (H17 vs S17):|r
The host chooses one of two dealer rules:
- |cff00ff00H17|r: Dealer HITS on Soft 17 (Ace counted as 11)
- |cff00ff00S17|r: Dealer STANDS on Soft 17
Both rules: Dealer always stands on hard 17+ and hits on 16 or less.
S17 is slightly better for players.

|cff88ffffSpecial Rules:|r
- |cffffd7005-Card Charlie|r: 5 cards without busting is an automatic win!
- Split Aces only get one card each and pay 1:1

|cffff8888Remember:|r This is for fun! Trade gold honorably with other players to settle bets.]]
    },
    poker = {
        title = "5 Card Stud",
        text = [[|cffffd700Welcome to 5 Card Stud Poker!|r

|cff88ffffObjective:|r
Make the best 5-card poker hand and win the pot through betting or showdown.

|cff88ffffHand Rankings (Best to Worst):|r
1. |cffffd700Royal Flush|r - A, K, Q, J, 10 of same suit
2. |cffffd700Straight Flush|r - 5 consecutive cards, same suit
3. |cffffd700Four of a Kind|r - 4 cards of same rank
4. |cffffd700Full House|r - 3 of a kind + a pair
5. |cffffd700Flush|r - 5 cards of same suit
6. |cffffd700Straight|r - 5 consecutive cards
7. |cffffd700Three of a Kind|r - 3 cards of same rank
8. |cffffd700Two Pair|r - 2 different pairs
9. |cffffd700One Pair|r - 2 cards of same rank
10. |cffffd700High Card|r - Highest card wins

|cff88ffffHow to Play:|r
1. Host opens table, sets ante and max raise
2. Players join by clicking JOIN
3. Everyone antes and gets one card face-down
4. Four betting rounds, each with a new face-up card
5. After all cards are dealt, showdown determines winner

|cff88ffffBetting Options:|r
- |cff00ff00CHECK|r: Pass (if no bet to call)
- |cff00ff00CALL|r: Match the current bet
- |cff00ff00RAISE|r: Increase the bet
- |cffff4444FOLD|r: Give up your hand and bets

|cff88ffffTips:|r
- Watch opponents' face-up cards for clues
- Fold weak hands early to save gold
- Bluffing can work, but be careful!

|cffff8888Remember:|r This is for fun! Trade gold honorably with other players to settle bets.]]
    },
    hilo = {
        title = "High-Lo",
        text = [[|cffffd700Welcome to High-Lo!|r

|cff88ffffObjective:|r
Roll the highest number to win gold from the player with the lowest roll!

|cff88ffffHow to Play:|r
1. One player hosts and sets the max roll value
2. Other players click JOIN to enter the game
3. When ready, host clicks START
4. Everyone types /roll X (or click the Roll button)
5. Highest roller wins the difference from lowest roller

|cff88ffffExample:|r
- Max roll is set to 100
- Alice rolls 82, Bob rolls 45, Carol rolls 67
- Alice |cff00ff00wins|r and Bob |cffff4444loses|r
- |cffffd70082 - 45 = 37g|r
- Bob pays Alice 37 gold!

|cff88ffffSettings:|r
- |cffffd700Max Roll|r: The maximum number for /roll (default 100)
- |cffffd700Join Timer|r: Optional countdown for join phase (0 = manual start)

|cff88ffffRules:|r
- All players have 2 minutes to roll
- Players who don't roll in time are skipped
- If only one person rolls, no settlement occurs
- Ties for high or low trigger a /roll 100 tiebreaker

|cffff8888Remember:|r This is for fun! Trade gold honorably with other players to settle bets.]]
    }
}

function Lobby:ShowHelp()
    -- Hide the lobby while help is showing
    if self.frame then
        self.frame:Hide()
    end
    
    if self.helpPanel then
        self.helpPanel:Show()
        self:UpdateHelpTrixieVisibility()
        return
    end
    
    self:CreateHelpPanel()
    self.helpPanel:Show()
    self:UpdateHelpTrixieVisibility()
end

function Lobby:HideHelp(dontShowLobby)
    if self.helpPanel then
        self.helpPanel:Hide()
    end
    -- Hide help Trixie
    if self.helpTrixie then
        self.helpTrixie:Hide()
    end
    -- Show the lobby again (unless told not to)
    if not dontShowLobby and self.frame then
        self.frame:Show()
    end
end

-- Update Help Trixie visibility based on setting
function Lobby:UpdateHelpTrixieVisibility()
    if not self.helpTrixie then return end
    
    local showTrixie = true
    if BJ.db and BJ.db.settings then
        showTrixie = BJ.db.settings.showLobbyTrixie ~= false
    end
    
    -- Only show Trixie if setting is enabled AND help panel is visible
    if showTrixie and self.helpPanel and self.helpPanel:IsShown() then
        self.helpTrixie:Show()
    else
        self.helpTrixie:Hide()
    end
end

function Lobby:CreateHelpPanel()
    -- Parent to UIParent so it shows when lobby is hidden
    local panel = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    panel:SetSize(HELP_WIDTH, LOBBY_HEIGHT)
    panel:SetPoint("CENTER")
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    panel:SetClampedToScreen(true)
    panel:SetFrameStrata("HIGH")
    panel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    panel:SetBackdropColor(0.05, 0.08, 0.12, 0.98)
    panel:SetBackdropBorderColor(0.3, 0.5, 0.7, 1)
    panel:SetFrameLevel(self.frame:GetFrameLevel() + 10)
    
    -- Title
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -10)
    title:SetText("|cff88ccffHelp & Rules|r")
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, panel)
    closeBtn:SetSize(24, 24)
    closeBtn:SetPoint("TOPRIGHT", -5, -5)
    closeBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    closeBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
    closeBtn:SetScript("OnClick", function() Lobby:HideHelp() end)
    
    -- Game selection buttons (left side)
    local btnFrame = CreateFrame("Frame", nil, panel)
    btnFrame:SetSize(120, 200)
    btnFrame:SetPoint("TOPLEFT", 15, -45)
    
    local bjHelpBtn = CreateFrame("Button", nil, btnFrame, "BackdropTemplate")
    bjHelpBtn:SetSize(110, 30)
    bjHelpBtn:SetPoint("TOP", 0, 0)
    bjHelpBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    bjHelpBtn:SetBackdropColor(0.15, 0.35, 0.15, 1)
    bjHelpBtn:SetBackdropBorderColor(0.3, 0.7, 0.3, 1)
    local bjHelpText = bjHelpBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    bjHelpText:SetPoint("CENTER")
    bjHelpText:SetText("|cff00ff00Blackjack|r")
    bjHelpBtn:SetScript("OnClick", function() Lobby:ShowHelpContent("blackjack") end)
    bjHelpBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.2, 0.5, 0.2, 1) end)
    bjHelpBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.15, 0.35, 0.15, 1) end)
    
    local pokerHelpBtn = CreateFrame("Button", nil, btnFrame, "BackdropTemplate")
    pokerHelpBtn:SetSize(110, 30)
    pokerHelpBtn:SetPoint("TOP", bjHelpBtn, "BOTTOM", 0, -10)
    pokerHelpBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    pokerHelpBtn:SetBackdropColor(0.15, 0.35, 0.15, 1)
    pokerHelpBtn:SetBackdropBorderColor(0.3, 0.7, 0.3, 1)
    local pokerHelpText = pokerHelpBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    pokerHelpText:SetPoint("CENTER")
    pokerHelpText:SetText("|cff00ff005 Card Stud|r")
    pokerHelpBtn:SetScript("OnClick", function() Lobby:ShowHelpContent("poker") end)
    pokerHelpBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.2, 0.5, 0.2, 1) end)
    pokerHelpBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.15, 0.35, 0.15, 1) end)
    
    local hiloHelpBtn = CreateFrame("Button", nil, btnFrame, "BackdropTemplate")
    hiloHelpBtn:SetSize(110, 30)
    hiloHelpBtn:SetPoint("TOP", pokerHelpBtn, "BOTTOM", 0, -10)
    hiloHelpBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    hiloHelpBtn:SetBackdropColor(0.15, 0.35, 0.15, 1)
    hiloHelpBtn:SetBackdropBorderColor(0.3, 0.7, 0.3, 1)
    local hiloHelpText = hiloHelpBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hiloHelpText:SetPoint("CENTER")
    hiloHelpText:SetText("|cff00ff00High-Lo|r")
    hiloHelpBtn:SetScript("OnClick", function() Lobby:ShowHelpContent("hilo") end)
    hiloHelpBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.2, 0.5, 0.2, 1) end)
    hiloHelpBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.15, 0.35, 0.15, 1) end)
    
    -- Back button (hidden by default, shown when viewing game help)
    local backBtn = CreateFrame("Button", nil, btnFrame, "BackdropTemplate")
    backBtn:SetSize(110, 26)
    backBtn:SetPoint("TOP", hiloHelpBtn, "BOTTOM", 0, -15)
    backBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    backBtn:SetBackdropColor(0.3, 0.25, 0.15, 1)
    backBtn:SetBackdropBorderColor(0.5, 0.4, 0.2, 1)
    local backText = backBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    backText:SetPoint("CENTER")
    backText:SetText("|cffffcc00< Back|r")
    backBtn:SetScript("OnClick", function() Lobby:ShowMainHelp() end)
    backBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.4, 0.35, 0.2, 1) end)
    backBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.3, 0.25, 0.15, 1) end)
    backBtn:Hide()
    panel.backBtn = backBtn
    
    -- Content area (middle with scroll)
    local contentFrame = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    contentFrame:SetSize(360, LOBBY_HEIGHT - 60)
    contentFrame:SetPoint("TOPLEFT", btnFrame, "TOPRIGHT", 10, 5)
    contentFrame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    contentFrame:SetBackdropColor(0.02, 0.02, 0.05, 0.9)
    contentFrame:SetBackdropBorderColor(0.2, 0.2, 0.3, 1)
    
    -- Scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", nil, contentFrame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 8, -8)
    scrollFrame:SetPoint("BOTTOMRIGHT", -28, 8)
    
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(320, 1)
    scrollFrame:SetScrollChild(scrollChild)
    
    local contentText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    contentText:SetPoint("TOPLEFT", 0, 0)
    contentText:SetWidth(320)
    contentText:SetJustifyH("LEFT")
    contentText:SetJustifyV("TOP")
    contentText:SetSpacing(2)
    
    -- Default content with commands and tips
    local defaultHelp = "|cffffd700=== Slash Commands ===|r\n\n"
    defaultHelp = defaultHelp .. "|cff88ff88/cc|r or |cff88ff88/casino|r - Open lobby\n"
    defaultHelp = defaultHelp .. "|cff88ff88/cc help|r - Show commands in chat\n"
    defaultHelp = defaultHelp .. "|cff88ff88/cc default|r - Reset settings\n"
    defaultHelp = defaultHelp .. "|cff88ff88/cc intro|r - Replay Trixie intro\n"
    defaultHelp = defaultHelp .. "|cff88ff88/hilo <max> [timer]|r - Quick start High-Lo\n"
    defaultHelp = defaultHelp .. "   max = max roll, timer = 20-120 sec (default 60)\n"
    defaultHelp = defaultHelp .. "   Example: /hilo 1000 30\n\n"
    defaultHelp = defaultHelp .. "|cffffd700=== Tips ===|r\n\n"
    defaultHelp = defaultHelp .. "|cffcccccc\226\128\162|r Click |cff00ff00[game names]|r in chat to open that game directly\n\n"
    defaultHelp = defaultHelp .. "|cffcccccc\226\128\162|r Games require a party or raid - invite friends!\n\n"
    defaultHelp = defaultHelp .. "|cffcccccc\226\128\162|r One person hosts, others join. The host is the 'house'.\n\n"
    defaultHelp = defaultHelp .. "|cffcccccc\226\128\162|r Settle debts with in-game gold trades after games.\n\n"
    defaultHelp = defaultHelp .. "|cff888888Select a game on the left to see its rules.|r"
    
    contentText:SetText(defaultHelp)
    
    -- Store default help text for back button
    panel.defaultHelpText = defaultHelp
    
    panel.contentText = contentText
    panel.scrollChild = scrollChild
    panel.scrollFrame = scrollFrame
    
    -- Set initial scroll height after a frame delay (text needs to render)
    C_Timer.After(0.01, function()
        if panel.contentText then
            local textHeight = panel.contentText:GetStringHeight()
            panel.scrollChild:SetHeight(math.max(340, textHeight + 20))
        end
    end)
    
    self.helpPanel = panel
    
    -- Tall Trixie on the right side (same as lobby)
    local TRIXIE_ASPECT = 274 / 350  -- Width:Height ratio from wait images
    local trixieHeight = LOBBY_HEIGHT
    local trixieWidth = trixieHeight * TRIXIE_ASPECT
    
    local helpTrixieFrame = CreateFrame("Button", "HelpTrixieFrame", UIParent)
    helpTrixieFrame:SetSize(trixieWidth, trixieHeight)
    helpTrixieFrame:SetPoint("LEFT", panel, "RIGHT", 0, 0)
    helpTrixieFrame:SetFrameStrata("HIGH")
    
    -- Random wait image for help window
    local helpWaitIdx = math.random(1, 31)
    local helpTrixieTexture = helpTrixieFrame:CreateTexture(nil, "ARTWORK")
    helpTrixieTexture:SetAllPoints()
    helpTrixieTexture:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\dealer\\trix_wait" .. helpWaitIdx)
    helpTrixieFrame.texture = helpTrixieTexture
    
    -- Click for easter egg poke
    helpTrixieFrame:SetScript("OnClick", function()
        Lobby:TryPlayPoke()
    end)
    
    -- Randomize pose each time help is shown
    panel:HookScript("OnShow", function()
        local newIdx = math.random(1, 31)
        helpTrixieFrame.texture:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\dealer\\trix_wait" .. newIdx)
    end)
    
    helpTrixieFrame:Hide()
    self.helpTrixie = helpTrixieFrame
end

-- Show main help page (called by back button)
function Lobby:ShowMainHelp()
    if not self.helpPanel then return end
    
    -- Reset content to default
    self.helpPanel.contentText:SetText(self.helpPanel.defaultHelpText)
    
    -- Resize scroll child
    local textHeight = self.helpPanel.contentText:GetStringHeight()
    self.helpPanel.scrollChild:SetHeight(math.max(340, textHeight + 20))
    
    -- Scroll to top
    self.helpPanel.scrollFrame:SetVerticalScroll(0)
    
    -- Hide back button
    self.helpPanel.backBtn:Hide()
end

function Lobby:ShowHelpContent(game)
    if not self.helpPanel then return end
    
    local content = self.helpContent[game]
    if not content then return end
    
    -- Update content
    self.helpPanel.contentText:SetText(content.text)
    
    -- Resize scroll child to fit content
    local textHeight = self.helpPanel.contentText:GetStringHeight()
    self.helpPanel.scrollChild:SetHeight(math.max(340, textHeight + 20))
    
    -- Scroll to top
    self.helpPanel.scrollFrame:SetVerticalScroll(0)
    
    -- Show back button
    self.helpPanel.backBtn:Show()
end

--[[
    EASTER EGG - Trixie Poke Sound
    Very rare chance to play when clicking on Trixie (configurable in debug mode)
]]
function Lobby:TryPlayPoke()
    local pokeChance = self:GetPokeChance()
    if math.random(1, pokeChance) == 1 then
        local pokeNum = math.random(1, 4)
        local soundFile = "Interface\\AddOns\\Chairfaces Casino\\Sounds\\trix_poke" .. pokeNum .. ".ogg"
        PlaySoundFile(soundFile, "SFX")
        return true
    end
    return false
end

--[[
    GAME ACTIVE CHECK
    Returns true if any game is currently in an active (non-idle, non-settlement) phase
]]
function Lobby:IsAnyGameActive()
    -- Check Blackjack
    local GS = BJ.GameState
    if GS and GS.phase and GS.phase ~= "idle" and GS.phase ~= "settlement" then
        return true, "blackjack"
    end
    
    -- Check Poker
    local PS = BJ.PokerState
    if PS and PS.phase and PS.phase ~= "idle" and PS.phase ~= "settlement" then
        return true, "poker"
    end
    
    -- Check High-Lo
    local HL = BJ.HiLoState
    if HL and HL.phase and HL.phase ~= HL.PHASE.IDLE and HL.phase ~= HL.PHASE.SETTLEMENT then
        return true, "hilo"
    end
    
    return false, nil
end

-- Get friendly name for game
function Lobby:GetGameName(gameType)
    if gameType == "blackjack" then return "Blackjack"
    elseif gameType == "poker" then return "5 Card Stud"
    elseif gameType == "hilo" then return "High-Lo"
    else return gameType end
end
