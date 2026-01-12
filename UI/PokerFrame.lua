--[[
    Chairface's Casino - UI/PokerFrame.lua
    5 Card Stud poker UI with host settings panel and flying card animations
]]

local BJ = ChairfacesCasino
local UI = BJ.UI

UI.Poker = {}
local Poker = UI.Poker

-- Trixie dimensions - all images are 274x350 (912x1165 scaled proportionally)
local TRIXIE_HEIGHT = 350
local TRIXIE_WIDTH = 274
local TRIXIE_LEFT_PADDING = 10  -- Space from window edge to Trixie left
local TRIXIE_RIGHT_PADDING = 10 -- Space from Trixie right to play area

-- Play area configuration
local PLAY_AREA_WIDTH = 920
local TRIXIE_AREA_WIDTH = TRIXIE_LEFT_PADDING + TRIXIE_WIDTH + TRIXIE_RIGHT_PADDING  -- 294px

-- Frame dimensions (will be adjusted based on Trixie visibility)
local FRAME_WIDTH_WITH_TRIXIE = TRIXIE_AREA_WIDTH + PLAY_AREA_WIDTH  -- 1214px
local FRAME_WIDTH_NO_TRIXIE = PLAY_AREA_WIDTH + 20  -- 940px (just play area + padding)
local FRAME_HEIGHT = 520

-- Current offset for play area elements (changes based on Trixie visibility)
local PLAY_AREA_OFFSET = TRIXIE_AREA_WIDTH  -- Default with Trixie
local FRAME_WIDTH = FRAME_WIDTH_WITH_TRIXIE

local BORDER_COLOR = { 0.4, 0.25, 0.1, 1 }

-- Check if Trixie should be shown
function Poker:ShouldShowTrixie()
    if ChairfacesCasinoDB and ChairfacesCasinoDB.settings then
        return ChairfacesCasinoDB.settings.pokerShowTrixie ~= false
    end
    return true
end

-- Update frame dimensions based on Trixie visibility
function Poker:UpdateFrameDimensions()
    local showTrixie = self:ShouldShowTrixie()
    if showTrixie then
        PLAY_AREA_OFFSET = TRIXIE_AREA_WIDTH
        FRAME_WIDTH = FRAME_WIDTH_WITH_TRIXIE
    else
        PLAY_AREA_OFFSET = 10  -- Small left padding
        FRAME_WIDTH = FRAME_WIDTH_NO_TRIXIE
    end
end

-- Get current play area offset based on Trixie visibility
function Poker:GetPlayAreaOffset()
    if self:ShouldShowTrixie() then
        return TRIXIE_AREA_WIDTH
    else
        return 10  -- Small padding when no Trixie
    end
end

-- Player grid: 5 cols x 2 rows visible
local PLAYER_COLS = 5
local PLAYER_CELL_WIDTH = 185  -- More horizontal separation (+10)
local PLAYER_CELL_HEIGHT = 130  -- More space between rows

-- Test player names
Poker.testPlayerNames = {
    "Thrallmar", "Sylvanas", "Arthas", "Jaina", "Tyrande",
    "Malfurion", "Illidan", "Vashj", "Kelthuzad", "Uther",
}
Poker.testPlayers = {}
Poker.dealtCards = {}
Poker.autoPlayEnabled = true
Poker.isInitialized = false
Poker.isDealingAnimation = false

-- Animation settings (matching blackjack)
Poker.DEAL_DURATION = 0.4
Poker.DEAL_DELAY = 0.35
Poker.DEAL_START_X = 45
Poker.DEAL_START_Y = -190

function Poker:Initialize()
    -- Created on first Show()
end

function Poker:CreateMainFrame()
    local frame = CreateFrame("Frame", "ChairfacesCasinoPoker", UIParent, "BackdropTemplate")
    frame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    frame:SetFrameStrata("HIGH")
    
    -- Border only backdrop
    frame:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 8,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropBorderColor(unpack(BORDER_COLOR))
    
    -- Create centered felt background texture
    local bgTexture = frame:CreateTexture(nil, "BACKGROUND")
    bgTexture:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\tablefelt_bg")
    bgTexture:SetAllPoints()
    local function UpdateFeltTexCoords()
        local texW, texH = 1280, 720
        local frameW, frameH = frame:GetWidth(), frame:GetHeight()
        local uSize = math.min(1, frameW / texW)
        local vSize = math.min(1, frameH / texH)
        local uOffset = (1 - uSize) / 2
        local vOffset = (1 - vSize) / 2
        bgTexture:SetTexCoord(uOffset, uOffset + uSize, vOffset, vOffset + vSize)
    end
    UpdateFeltTexCoords()
    frame.feltBg = bgTexture
    frame.UpdateFeltTexCoords = UpdateFeltTexCoords
    
    -- Title bar
    local titleBar = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    titleBar:SetSize(FRAME_WIDTH - 16, 28)
    titleBar:SetPoint("TOP", 0, -8)
    titleBar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
    titleBar:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
    titleBar:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    self.titleBar = titleBar  -- Store reference for resizing
    
    local titleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("CENTER")
    titleText:SetText("Chairface's Casino - 5 Card Stud")
    titleText:SetTextColor(1, 0.84, 0, 1)
    self.titleText = titleText
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, titleBar)
    closeBtn:SetSize(20, 20)
    closeBtn:SetPoint("RIGHT", -5, 0)
    closeBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    closeBtn:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
    closeBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
    closeBtn:SetScript("OnClick", function() Poker:Hide() end)
    
    -- Refresh button
    local refreshBtn = CreateFrame("Button", nil, titleBar)
    refreshBtn:SetSize(18, 18)
    refreshBtn:SetPoint("RIGHT", closeBtn, "LEFT", -3, 0)
    
    local refreshTex = refreshBtn:CreateTexture(nil, "ARTWORK")
    refreshTex:SetAllPoints()
    refreshTex:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\refresh_icon")
    refreshBtn.texture = refreshTex
    
    local refreshHighlight = refreshBtn:CreateTexture(nil, "HIGHLIGHT")
    refreshHighlight:SetAllPoints()
    refreshHighlight:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\refresh_icon")
    refreshHighlight:SetAlpha(0.5)
    refreshHighlight:SetBlendMode("ADD")
    
    refreshBtn:SetScript("OnClick", function()
        Poker:Hide()
        C_Timer.After(0.05, function()
            Poker:Show()
        end)
    end)
    refreshBtn:SetScript("OnEnter", function(self) 
        self.texture:SetVertexColor(0.7, 0.9, 1, 1)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Refresh Window")
        GameTooltip:Show()
    end)
    refreshBtn:SetScript("OnLeave", function(self) 
        self.texture:SetVertexColor(1, 1, 1, 1)
        GameTooltip:Hide()
    end)
    
    -- Back button
    local backBtn = CreateFrame("Button", nil, titleBar, "BackdropTemplate")
    backBtn:SetSize(50, 18)
    backBtn:SetPoint("RIGHT", refreshBtn, "LEFT", -5, 0)
    backBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    backBtn:SetBackdropColor(0.15, 0.35, 0.15, 1)
    backBtn:SetBackdropBorderColor(0.3, 0.6, 0.3, 1)
    local backText = backBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    backText:SetPoint("CENTER")
    backText:SetText("|cffffffffBack|r")
    backBtn:SetScript("OnClick", function()
        Poker:Hide()
        if UI.Lobby then UI.Lobby:Show() end
    end)
    backBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.2, 0.45, 0.2, 1) end)
    backBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.15, 0.35, 0.15, 1) end)
    
    -- Session Leaderboard button
    local sessionBtn = CreateFrame("Button", nil, titleBar)
    sessionBtn:SetSize(20, 20)
    sessionBtn:SetPoint("RIGHT", backBtn, "LEFT", -5, 0)
    
    local sessionTex = sessionBtn:CreateTexture(nil, "ARTWORK")
    sessionTex:SetAllPoints()
    sessionTex:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\leaderboard_session")
    sessionBtn.texture = sessionTex
    
    local sessionHighlight = sessionBtn:CreateTexture(nil, "HIGHLIGHT")
    sessionHighlight:SetAllPoints()
    sessionHighlight:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\leaderboard_session")
    sessionHighlight:SetAlpha(0.5)
    sessionHighlight:SetBlendMode("ADD")
    
    sessionBtn:SetScript("OnClick", function()
        if BJ.LeaderboardUI then
            BJ.LeaderboardUI:ToggleSession("poker")
        end
    end)
    sessionBtn:SetScript("OnEnter", function(self)
        self.texture:SetVertexColor(1, 0.9, 0.5, 1)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Session Leaderboard", 1, 0.84, 0)
        GameTooltip:AddLine("View current session standings", 1, 1, 1)
        GameTooltip:Show()
    end)
    sessionBtn:SetScript("OnLeave", function(self)
        self.texture:SetVertexColor(1, 1, 1, 1)
        GameTooltip:Hide()
    end)
    self.sessionBtn = sessionBtn
    
    -- All-time leaderboard button (trophy icon)
    local allTimeBtn = CreateFrame("Button", nil, titleBar)
    allTimeBtn:SetSize(20, 20)
    allTimeBtn:SetPoint("RIGHT", sessionBtn, "LEFT", -5, 0)
    
    local allTimeTex = allTimeBtn:CreateTexture(nil, "ARTWORK")
    allTimeTex:SetAllPoints()
    allTimeTex:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\leaderboard_alltime")
    allTimeTex:SetTexCoord(0, 1, 1, 0)  -- Flip vertically
    allTimeBtn.texture = allTimeTex
    
    local allTimeHighlight = allTimeBtn:CreateTexture(nil, "HIGHLIGHT")
    allTimeHighlight:SetAllPoints()
    allTimeHighlight:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\leaderboard_alltime")
    allTimeHighlight:SetTexCoord(0, 1, 1, 0)  -- Flip vertically
    allTimeHighlight:SetAlpha(0.5)
    allTimeHighlight:SetBlendMode("ADD")
    
    allTimeBtn:SetScript("OnClick", function()
        if BJ.LeaderboardUI then
            BJ.LeaderboardUI:ToggleAllTime("poker")
        end
    end)
    allTimeBtn:SetScript("OnEnter", function(self)
        self.texture:SetVertexColor(1, 0.9, 0.5, 1)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("All-Time Leaderboard", 1, 0.84, 0)
        GameTooltip:AddLine("View all-time rankings", 1, 1, 1)
        GameTooltip:Show()
    end)
    allTimeBtn:SetScript("OnLeave", function(self)
        self.texture:SetVertexColor(1, 1, 1, 1)
        GameTooltip:Hide()
    end)
    self.allTimeBtn = allTimeBtn
    
    -- Info text (centered below title bar)
    local infoText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    infoText:SetPoint("TOP", titleBar, "BOTTOM", 0, -5)
    infoText:SetTextColor(0.8, 0.8, 0.8, 1)
    frame.infoText = infoText
    self.infoText = infoText
    
    self.mainFrame = frame
    
    -- Create components
    self:CreateDealerArea()
    self:CreateActionButtons()
    self:CreateStatusBar()
    self:RepositionTrixie()  -- Position Trixie after status bar exists
    self:CreatePlayerArea()
    self:CreateTestModeBar()
    self:CreateHostPanel()
    self:CreateFlyingCard()
    
    frame:Hide()
    self.isInitialized = true
end

function Poker:CreateDealerArea()
    local dealerArea = CreateFrame("Frame", nil, self.mainFrame)
    dealerArea:SetSize(PLAY_AREA_WIDTH - 40, 120)
    dealerArea:SetPoint("TOP", self.mainFrame, "TOP", PLAY_AREA_OFFSET / 2, -45)
    
    -- Trixie dealer on left side - will be positioned after status bar is created
    local trixieFrame = CreateFrame("Button", nil, self.mainFrame)
    trixieFrame:SetSize(TRIXIE_WIDTH, TRIXIE_HEIGHT)
    -- Temporary position, will be updated in RepositionTrixie after statusBar exists
    trixieFrame:SetPoint("BOTTOMLEFT", self.mainFrame, "BOTTOMLEFT", TRIXIE_LEFT_PADDING, 100)
    
    -- Randomize initial wait image
    local initialWaitIdx = math.random(1, 31)
    local trixieTexture = trixieFrame:CreateTexture(nil, "ARTWORK")
    trixieTexture:SetAllPoints()
    trixieTexture:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\dealer\\trix_wait" .. initialWaitIdx)
    trixieFrame.texture = trixieTexture
    trixieFrame.currentState = "wait" .. initialWaitIdx
    trixieFrame.isWaiting = true
    trixieFrame.lastDealState = nil
    trixieFrame.lastShufState = nil
    
    self.trixieTexture = trixieTexture
    self.trixieFrame = trixieFrame
    
    -- Random state functions (matching Blackjack)
    trixieFrame.SetRandomWait = function(self)
        local idx = math.random(1, 31)
        self.texture:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\dealer\\trix_wait" .. idx)
        self.currentState = "wait" .. idx
        self.isWaiting = true
    end
    
    trixieFrame.SetRandomDeal = function(self)
        local idx = math.random(1, 8)
        while idx == self.lastDealState and math.random() > 0.3 do
            idx = math.random(1, 8)
        end
        self.lastDealState = idx
        self.texture:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\dealer\\trix_deal" .. idx)
        self.currentState = "deal" .. idx
        self.isWaiting = false
    end
    
    trixieFrame.SetRandomShuffle = function(self)
        local idx = math.random(1, 12)
        while idx == self.lastShufState and math.random() > 0.3 do
            idx = math.random(1, 12)
        end
        self.lastShufState = idx
        self.texture:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\dealer\\trix_shuf" .. idx)
        self.currentState = "shuf" .. idx
        self.isWaiting = false
    end
    
    trixieFrame.SetRandomLose = function(self)
        local idx = math.random(1, 12)
        self.texture:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\dealer\\trix_lose" .. idx)
        self.currentState = "lose" .. idx
        self.isWaiting = false
    end
    
    trixieFrame.SetRandomCheer = function(self)
        local idx = math.random(1, 9)
        self.texture:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\dealer\\trix_win" .. idx)
        self.currentState = "win" .. idx
        self.isWaiting = false
    end
    
    trixieFrame.SetRandomLove = function(self)
        local idx = math.random(1, 10)
        self.texture:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\dealer\\trix_love" .. idx)
        self.currentState = "love" .. idx
        self.isWaiting = false
    end
    
    trixieFrame.SetRandomWinOrLove = function(self)
        if math.random() < 0.1 then
            self:SetRandomLove()
        else
            self:SetRandomCheer()
        end
    end
    
    -- Easter egg click handler
    trixieFrame:SetScript("OnClick", function()
        if UI.Lobby and UI.Lobby.TryPlayPoke then
            UI.Lobby:TryPlayPoke()
        end
    end)
    
    -- Pot display (center of play area)
    local potFrame = CreateFrame("Frame", nil, dealerArea, "BackdropTemplate")
    potFrame:SetSize(120, 50)
    potFrame:SetPoint("CENTER", dealerArea, "CENTER", 0, 0)
    potFrame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
    potFrame:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
    potFrame:SetBackdropBorderColor(0.6, 0.5, 0.2, 1)
    
    local potLabel = potFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    potLabel:SetPoint("TOP", 0, -8)
    potLabel:SetText("|cffffd700POT|r")
    
    local potAmount = potFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    potAmount:SetPoint("BOTTOM", 0, 8)
    potAmount:SetFont("Fonts\\FRIZQT__.TTF", 20, "OUTLINE")
    potAmount:SetText("|cffffffff0g|r")
    self.potAmount = potAmount
    self.potFrame = potFrame
    potFrame:Hide()
    
    -- Settlement list (top-right corner, shown during settlement)
    -- Left edge should not extend past host button's right edge
    -- Host button: centered at PLAY_AREA_OFFSET/2 (147px from center), 180px wide = right edge at center+237
    -- Frame is 1214px wide, center at 607, so host button right edge at ~844px from left
    -- Settlement at TOPRIGHT -10 means right edge at 1204, so max width = 1204 - 844 = 360px
    local settlementFrame = CreateFrame("Frame", nil, self.mainFrame, "BackdropTemplate")
    settlementFrame:SetSize(360, 315)  -- Width constrained to not overlap host button
    settlementFrame:SetPoint("TOPRIGHT", self.mainFrame, "TOPRIGHT", -10, -40)  -- Below header bar
    settlementFrame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
    settlementFrame:SetBackdropColor(0.05, 0.05, 0.05, 1)  -- Fully opaque
    settlementFrame:SetBackdropBorderColor(1, 0.84, 0, 1)  -- Gold border like blackjack
    settlementFrame:SetFrameLevel(self.mainFrame:GetFrameLevel() + 10)
    
    local settlementTitle = settlementFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    settlementTitle:SetPoint("TOP", 0, -11)
    settlementTitle:SetText("Settlement")
    settlementTitle:SetTextColor(1, 0.84, 0, 1)
    settlementTitle:SetFont("Fonts\\FRIZQT__.TTF", 20)  -- 14*1.4
    
    local settlementText = settlementFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    settlementText:SetPoint("TOPLEFT", 17, -42)  -- 12*1.4, 30*1.4
    settlementText:SetPoint("TOPRIGHT", -17, -42)
    settlementText:SetJustifyH("LEFT")
    settlementText:SetJustifyV("TOP")
    settlementText:SetFont("Fonts\\FRIZQT__.TTF", 17, "OUTLINE")  -- 12*1.4
    settlementText:SetText("")
    self.settlementText = settlementText
    self.settlementFrame = settlementFrame
    settlementFrame:Hide()
    
    -- Action announcement text (large text under pot that fades)
    local actionText = dealerArea:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    actionText:SetPoint("TOP", potFrame, "BOTTOM", 0, -10)
    actionText:SetFont("Fonts\\FRIZQT__.TTF", 18, "OUTLINE")
    actionText:SetTextColor(1, 0.84, 0, 1)
    actionText:SetText("")
    self.actionText = actionText
    self.actionTextFadeStart = 0
    
    self.dealerArea = dealerArea
end

function Poker:CreateActionButtons()
    local buttonArea = CreateFrame("Frame", nil, self.mainFrame)
    buttonArea:SetSize(PLAY_AREA_WIDTH - 20, 50)
    -- Center in play area (aligned with pot)
    buttonArea:SetPoint("BOTTOM", self.mainFrame, "BOTTOM", PLAY_AREA_OFFSET / 2, 15)
    
    self.buttons = {}
    self.buttonArea = buttonArea
    
    local function createButton(parent, name, text, width, color)
        local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
        btn:SetSize(width, 32)
        btn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
        local r, g, b = 0.15, 0.35, 0.15
        if color then r, g, b = unpack(color) end
        btn:SetBackdropColor(r, g, b, 1)
        btn:SetBackdropBorderColor(r + 0.15, g + 0.35, b + 0.15, 1)
        btn.baseColor = {r, g, b}
        local btnText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        btnText:SetPoint("CENTER")
        btnText:SetText(text)
        btn.text = btnText
        btn:SetScript("OnEnter", function(self)
            if self:IsEnabled() then 
                local bc = self.baseColor
                self:SetBackdropColor(bc[1] + 0.1, bc[2] + 0.1, bc[3] + 0.1, 1) 
            end
        end)
        btn:SetScript("OnLeave", function(self)
            local bc = self.baseColor
            self:SetBackdropColor(bc[1], bc[2], bc[3], 1)
        end)
        btn:SetScript("OnDisable", function(self)
            self:SetBackdropColor(0.2, 0.2, 0.2, 0.7)
            self.text:SetTextColor(0.5, 0.5, 0.5)
        end)
        btn:SetScript("OnEnable", function(self)
            local bc = self.baseColor
            self:SetBackdropColor(bc[1], bc[2], bc[3], 1)
            self.text:SetTextColor(1, 1, 1)
        end)
        self.buttons[name] = btn
        return btn
    end
    
    -- Main button bar: FOLD, CHECK/CALL, [input], RAISE (X), MAX RAISE (Y), LOG
    local btnConfigs = {
        { name = "fold", text = "FOLD", width = 60, color = {0.4, 0.15, 0.15} },
        { name = "checkCall", text = "CHECK", width = 70 },
    }
    
    local totalWidth = 0
    for _, cfg in ipairs(btnConfigs) do
        totalWidth = totalWidth + cfg.width + 5
    end
    -- Add space for: input(50) + raise(80) + maxRaise(90) + log(45) + gaps
    totalWidth = totalWidth + 50 + 5 + 80 + 5 + 90 + 5 + 45
    
    local startX = -totalWidth / 2
    
    for _, cfg in ipairs(btnConfigs) do
        local btn = createButton(buttonArea, cfg.name, cfg.text, cfg.width, cfg.color)
        btn:SetPoint("LEFT", buttonArea, "CENTER", startX, 0)
        startX = startX + cfg.width + 5
    end
    
    -- Raise input box
    local raiseInput = CreateFrame("EditBox", nil, buttonArea, "BackdropTemplate")
    raiseInput:SetSize(50, 28)
    raiseInput:SetPoint("LEFT", buttonArea, "CENTER", startX, 0)
    raiseInput:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    raiseInput:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
    raiseInput:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    raiseInput:SetFontObject("GameFontNormal")
    raiseInput:SetJustifyH("CENTER")
    raiseInput:SetAutoFocus(false)
    raiseInput:SetNumeric(true)
    raiseInput:SetMaxLetters(6)
    raiseInput:SetText("1")
    raiseInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    raiseInput:SetScript("OnEnterPressed", function(self) self:ClearFocus() Poker:OnRaiseClick() end)
    raiseInput:SetScript("OnTextChanged", function(self)
        -- Only update label, don't validate while typing (allow blank)
        Poker:UpdateRaiseButtonLabel()
    end)
    raiseInput:SetScript("OnEditFocusLost", function(self)
        -- Validate only when focus is lost
        Poker:ValidateRaiseInput()
        Poker:UpdateRaiseButtonLabel()
    end)
    self.raiseInput = raiseInput
    startX = startX + 55
    
    -- RAISE button with dynamic label
    local raiseBtn = createButton(buttonArea, "raise", "RAISE (1)", 80)
    raiseBtn:SetPoint("LEFT", buttonArea, "CENTER", startX, 0)
    startX = startX + 85
    
    -- MAX RAISE button
    local maxRaiseBtn = createButton(buttonArea, "maxRaise", "RAISE (MAX)", 90)
    maxRaiseBtn:SetPoint("LEFT", buttonArea, "CENTER", startX, 0)
    startX = startX + 95
    
    -- LOG button at the end
    local logBtn = createButton(buttonArea, "log", "LOG", 45, {0.2, 0.2, 0.4})
    logBtn:SetPoint("LEFT", buttonArea, "CENTER", startX, 0)
    
    -- DEAL button (hidden by default, shown only when host and active)
    local dealBtn = createButton(buttonArea, "deal", "DEAL", 60)
    dealBtn:SetPoint("RIGHT", self.buttons.fold, "LEFT", -10, 0)
    dealBtn:Hide()
    
    -- RESET button in bottom right corner (inside brown border)
    local resetBtn = createButton(self.mainFrame, "reset", "RESET", 60, {0.4, 0.3, 0.1})
    resetBtn:SetPoint("BOTTOMRIGHT", self.mainFrame, "BOTTOMRIGHT", -15, 15)
    
    self.buttons.deal:SetScript("OnClick", function() self:OnDealClick() end)
    self.buttons.reset:SetScript("OnClick", function() self:OnResetClick() end)
    self.buttons.log:SetScript("OnClick", function() self:ToggleLog() end)
    self.buttons.fold:SetScript("OnClick", function() self:OnFoldClick() end)
    self.buttons.checkCall:SetScript("OnClick", function() self:OnCheckCallClick() end)
    self.buttons.raise:SetScript("OnClick", function() self:OnRaiseClick() end)
    self.buttons.maxRaise:SetScript("OnClick", function() self:OnMaxRaiseClick() end)
    
    -- Create centered action button (Host/Join)
    self:CreatePokerActionButton()
end

-- Create the centered Host/Join action button for Poker
function Poker:CreatePokerActionButton()
    local btn = CreateFrame("Button", "PokerActionButton", self.mainFrame, "BackdropTemplate")
    btn:SetSize(180, 54)  -- Triple normal size
    -- Center in play area (aligned with pot)
    btn:SetPoint("CENTER", self.mainFrame, "CENTER", PLAY_AREA_OFFSET / 2, 0)
    btn:SetFrameLevel(self.mainFrame:GetFrameLevel() + 100)  -- Above everything
    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 3,
    })
    btn:SetBackdropColor(0.15, 0.35, 0.15, 1)
    btn:SetBackdropBorderColor(0.3, 0.7, 0.3, 1)
    btn:EnableMouse(true)
    btn:RegisterForClicks("AnyUp")
    
    local btnText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    btnText:SetPoint("CENTER")
    btnText:SetFont("Fonts\\FRIZQT__.TTF", 24, "OUTLINE")  -- Triple font size
    btnText:SetText("HOST")
    btn.text = btnText
    
    -- Custom enable/disable with visual feedback
    btn.isEnabled = true
    btn.Enable = function(self)
        self.isEnabled = true
        self:EnableMouse(true)
        self:SetBackdropColor(0.15, 0.35, 0.15, 1)
        self:SetBackdropBorderColor(0.3, 0.7, 0.3, 1)
        self.text:SetTextColor(1, 1, 1, 1)
    end
    btn.Disable = function(self)
        self.isEnabled = false
        self:EnableMouse(false)
        self:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
        self:SetBackdropBorderColor(0.2, 0.2, 0.2, 0.5)
        self.text:SetTextColor(0.5, 0.5, 0.5, 1)
    end
    btn.IsEnabled = function(self)
        return self.isEnabled
    end
    
    btn:SetScript("OnEnter", function(self)
        if self.isEnabled then
            self:SetBackdropColor(0.2, 0.5, 0.2, 1)
            self:SetBackdropBorderColor(0.4, 1, 0.4, 1)
        end
    end)
    
    btn:SetScript("OnLeave", function(self)
        if self.isEnabled then
            self:SetBackdropColor(0.15, 0.35, 0.15, 1)
            self:SetBackdropBorderColor(0.3, 0.7, 0.3, 1)
        end
    end)
    
    btn:SetScript("OnClick", function()
        if btn.isEnabled then
            Poker:OnPokerActionButtonClick()
        end
    end)
    
    self.actionButton = btn
end

-- Handle action button click (context-dependent)
function Poker:OnPokerActionButtonClick()
    local PS = BJ.PokerState
    local PM = BJ.PokerMultiplayer
    
    -- During settlement, treat as HOST action (start new game)
    if PS.phase == PS.PHASE.SETTLEMENT then
        self:ShowHostPanel()
        self.actionButton:Hide()
    elseif not PM.tableOpen and not PM.isHost then
        -- No table open - this is a HOST action
        self:ShowHostPanel()
        self.actionButton:Hide()
    elseif PM.tableOpen and PS.phase == PS.PHASE.WAITING_FOR_PLAYERS then
        -- Table open, waiting for players - this is a JOIN/ANTE action
        self:OnJoinClick()
        self.actionButton:Hide()
    end
end

-- Update action button visibility and text
function Poker:UpdatePokerActionButton()
    if not self.actionButton then return end
    
    local PS = BJ.PokerState
    local PM = BJ.PokerMultiplayer
    local myName = UnitName("player")
    local inTestMode = BJ.TestMode and BJ.TestMode.enabled
    local inPartyOrRaid = IsInGroup() or IsInRaid()
    local canHost = inTestMode or inPartyOrRaid
    
    -- Check if ANY game is in session (not idle, not settlement)
    local Lobby = BJ.Lobby
    local anyGameInSession = false
    if Lobby and Lobby.IsGameInSession then
        anyGameInSession = Lobby:IsGameInSession("blackjack") or 
                          Lobby:IsGameInSession("poker") or 
                          Lobby:IsGameInSession("hilo")
    end
    
    -- Check if player already joined
    local inGame = PS.players and PS.players[myName] ~= nil
    
    -- During WAITING_FOR_PLAYERS for THIS game, show JOIN button for players not yet in game
    if PS.phase == PS.PHASE.WAITING_FOR_PLAYERS then
        if PM.tableOpen and not inGame then
            self.actionButton.text:SetText("JOIN")
            self.actionButton:Show()
            self.actionButton:Enable()
        else
            self.actionButton:Hide()
        end
        return
    end
    
    -- Hide HOST button if any game is in session
    if anyGameInSession then
        self.actionButton:Hide()
        return
    end
    
    -- Hide during active game phases (betting, showdown, etc)
    local gameActive = PS.phase ~= PS.PHASE.IDLE and PS.phase ~= PS.PHASE.SETTLEMENT
    if gameActive then
        self.actionButton:Hide()
        return
    end
    
    -- During settlement, anyone who can host should see HOST button
    if PS.phase == PS.PHASE.SETTLEMENT then
        if canHost then
            self.actionButton.text:SetText("HOST")
            self.actionButton:Show()
            self.actionButton:Enable()
        else
            self.actionButton:Hide()
        end
        return
    end
    
    -- IDLE phase - show HOST button if no table open
    if not PM.tableOpen and not PM.isHost then
        if canHost then
            self.actionButton.text:SetText("HOST")
            self.actionButton:Show()
            self.actionButton:Enable()
        else
            self.actionButton:Hide()
        end
    else
        self.actionButton:Hide()
    end
end

-- Start action button refresh ticker (checks for game state changes)
function Poker:StartActionButtonRefreshTicker()
    -- Store current state to detect changes
    local Lobby = BJ.Lobby
    if Lobby and Lobby.IsGameInSession then
        self.lastBjInSession = Lobby:IsGameInSession("blackjack")
        self.lastPokerInSession = Lobby:IsGameInSession("poker")
        self.lastHiloInSession = Lobby:IsGameInSession("hilo")
    end
    
    -- Cancel any existing ticker
    self:StopActionButtonRefreshTicker()
    
    -- Create a ticker that checks every 0.5 seconds
    self.actionButtonRefreshTicker = C_Timer.NewTicker(0.5, function()
        if not self.mainFrame or not self.mainFrame:IsShown() then
            self:StopActionButtonRefreshTicker()
            return
        end
        
        -- Check if any game states have changed
        if Lobby and Lobby.IsGameInSession then
            local bjInSession = Lobby:IsGameInSession("blackjack")
            local pokerInSession = Lobby:IsGameInSession("poker")
            local hiloInSession = Lobby:IsGameInSession("hilo")
            
            if bjInSession ~= self.lastBjInSession or 
               pokerInSession ~= self.lastPokerInSession or 
               hiloInSession ~= self.lastHiloInSession then
                -- State changed, update action button
                self:UpdatePokerActionButton()
                self.lastBjInSession = bjInSession
                self.lastPokerInSession = pokerInSession
                self.lastHiloInSession = hiloInSession
            end
        end
    end)
end

-- Stop action button refresh ticker
function Poker:StopActionButtonRefreshTicker()
    if self.actionButtonRefreshTicker then
        self.actionButtonRefreshTicker:Cancel()
        self.actionButtonRefreshTicker = nil
    end
end

function Poker:CreateStatusBar()
    local statusBar = CreateFrame("Frame", nil, self.mainFrame, "BackdropTemplate")
    statusBar:SetSize(PLAY_AREA_WIDTH - 100, 25)
    -- Anchored just above buttons, closer to them
    statusBar:SetPoint("BOTTOM", self.buttonArea, "TOP", 0, 2)
    statusBar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    statusBar:SetBackdropColor(0, 0, 0, 0.6)
    statusBar:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)
    
    local text = statusBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("CENTER")
    text:SetTextColor(1, 0.84, 0, 1)
    text:SetText("Welcome to 5 Card Stud!")
    statusBar.text = text
    
    self.statusBar = statusBar
    
    -- Turn timer frame (for turn timeout)
    local turnTimer = CreateFrame("Frame", nil, self.mainFrame, "BackdropTemplate")
    turnTimer:SetSize(200, 70)
    turnTimer:SetPoint("TOP", self.mainFrame, "TOP", 0, -60)
    turnTimer:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
    turnTimer:SetBackdropColor(0.6, 0.1, 0.1, 0.95)
    turnTimer:SetBackdropBorderColor(1, 0.2, 0.2, 1)
    turnTimer:SetFrameLevel(self.mainFrame:GetFrameLevel() + 15)
    
    local turnTimerLabel = turnTimer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    turnTimerLabel:SetPoint("TOP", 0, -5)
    turnTimerLabel:SetText("|cffff4444TIME LEFT|r")
    turnTimerLabel:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    
    turnTimer.text = turnTimer:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    turnTimer.text:SetPoint("CENTER", 0, 0)
    turnTimer.text:SetFont("Fonts\\FRIZQT__.TTF", 24, "OUTLINE")
    turnTimer.text:SetTextColor(1, 0.3, 0.3, 1)
    
    turnTimer.warning = turnTimer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    turnTimer.warning:SetPoint("BOTTOM", 0, 5)
    turnTimer.warning:SetText("|cffff8800Auto-check/fold soon!|r")
    turnTimer.warning:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    turnTimer:Hide()
    
    self.turnTimerFrame = turnTimer
end

function Poker:CreateLogWindow()
    -- Create log window (similar to blackjack log)
    local logFrame = CreateFrame("Frame", "CasinoPokerLogFrame", UIParent, "BackdropTemplate")
    logFrame:SetSize(320, 350)
    logFrame:SetPoint("LEFT", self.mainFrame, "RIGHT", 10, 0)
    logFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    logFrame:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
    logFrame:SetBackdropBorderColor(0.4, 0.3, 0.1, 1)
    logFrame:SetMovable(true)
    logFrame:EnableMouse(true)
    logFrame:RegisterForDrag("LeftButton")
    logFrame:SetClampedToScreen(true)
    logFrame:SetScript("OnDragStart", logFrame.StartMoving)
    logFrame:SetScript("OnDragStop", logFrame.StopMovingOrSizing)
    logFrame:SetFrameStrata("DIALOG")
    logFrame:Hide()
    
    -- Title bar
    local titleBar = CreateFrame("Frame", nil, logFrame, "BackdropTemplate")
    titleBar:SetSize(320, 24)
    titleBar:SetPoint("TOP", 0, 0)
    titleBar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    titleBar:SetBackdropColor(0.15, 0.12, 0.05, 1)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() logFrame:StartMoving() end)
    titleBar:SetScript("OnDragStop", function() logFrame:StopMovingOrSizing() end)
    
    local titleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("CENTER")
    titleText:SetText("|cffffd7005 Card Stud - Game Log|r")
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, titleBar)
    closeBtn:SetSize(18, 18)
    closeBtn:SetPoint("RIGHT", -3, 0)
    closeBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    closeBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
    closeBtn:SetScript("OnClick", function() logFrame:Hide() end)
    
    -- Scroll frame for log content
    local scrollFrame = CreateFrame("ScrollFrame", nil, logFrame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetSize(285, 310)
    scrollFrame:SetPoint("TOP", titleBar, "BOTTOM", -10, -5)
    
    local scrollContent = CreateFrame("Frame", nil, scrollFrame)
    scrollContent:SetSize(285, 800)
    scrollFrame:SetScrollChild(scrollContent)
    
    local logText = scrollContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    logText:SetPoint("TOPLEFT", 5, -5)
    logText:SetPoint("TOPRIGHT", -5, -5)
    logText:SetJustifyH("LEFT")
    logText:SetJustifyV("TOP")
    logText:SetFont("Fonts\\FRIZQT__.TTF", 11)
    logText:SetSpacing(2)
    logText:SetText("No game history yet.")
    
    logFrame.scrollContent = scrollContent
    logFrame.logText = logText
    
    self.logFrame = logFrame
end

function Poker:ToggleLog()
    if not self.logFrame then
        self:CreateLogWindow()
    end
    
    if self.logFrame:IsShown() then
        self.logFrame:Hide()
    else
        self:UpdateLogWindow()
        self.logFrame:Show()
    end
end

function Poker:UpdateLogWindow()
    if not self.logFrame then return end
    
    local PS = BJ.PokerState
    local logText = PS:GetGameLogText()
    self.logFrame.logText:SetText(logText)
    
    -- Resize scroll content to fit text
    local textHeight = self.logFrame.logText:GetStringHeight()
    self.logFrame.scrollContent:SetHeight(math.max(300, textHeight + 20))
end

function Poker:CreatePlayerArea()
    local ROW_HEIGHT = PLAYER_CELL_HEIGHT
    local visibleHeight = ROW_HEIGHT * 2 + 20  -- Two rows with padding
    
    -- Player area anchored to RIGHT edge of window, expanding left
    local clipFrame = CreateFrame("Frame", nil, self.mainFrame)
    clipFrame:SetSize(PLAY_AREA_WIDTH - 30, visibleHeight)
    -- Anchor to RIGHT side of window, 15px from edge, above buttons
    clipFrame:SetPoint("BOTTOMRIGHT", self.mainFrame, "BOTTOMRIGHT", -15, 77)
    clipFrame:SetClipsChildren(true)
    
    local content = CreateFrame("Frame", nil, clipFrame)
    content:SetSize(PLAY_AREA_WIDTH - 40, ROW_HEIGHT * 2)
    content:SetPoint("BOTTOM", clipFrame, "BOTTOM", 0, 0)  -- Anchor from bottom
    
    local rowIndicatorFrame = CreateFrame("Frame", nil, self.mainFrame, "BackdropTemplate")
    rowIndicatorFrame:SetSize(45, 24)
    rowIndicatorFrame:SetPoint("RIGHT", self.mainFrame, "RIGHT", -8, 0)
    rowIndicatorFrame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    rowIndicatorFrame:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
    rowIndicatorFrame:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    
    local rowIndicator = rowIndicatorFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    rowIndicator:SetPoint("CENTER")
    rowIndicator:SetText("1/1")
    
    local playerArea = {}
    playerArea.clipFrame = clipFrame
    playerArea.content = content
    playerArea.rowContainer = content
    playerArea.currentRow = 1
    playerArea.totalRows = 1
    playerArea.rowIndicator = rowIndicator
    playerArea.rowIndicatorFrame = rowIndicatorFrame
    playerArea.hands = {}
    playerArea.ROW_HEIGHT = ROW_HEIGHT
    
    local function scrollToRow(targetRow)
        targetRow = math.max(1, math.min(targetRow, playerArea.totalRows))
        -- Scroll by moving content down (showing higher rows)
        local yOffset = -((targetRow - 1) * ROW_HEIGHT)
        content:ClearAllPoints()
        content:SetPoint("BOTTOM", clipFrame, "BOTTOM", 0, yOffset)
        playerArea.currentRow = targetRow
        rowIndicator:SetText(targetRow .. "/" .. math.max(1, playerArea.totalRows))
    end
    
    local function updateRowDisplay()
        rowIndicator:SetText(playerArea.currentRow .. "/" .. math.max(1, playerArea.totalRows))
        if playerArea.totalRows > 1 then
            rowIndicatorFrame:Show()
        else
            rowIndicatorFrame:Hide()
        end
        scrollToRow(playerArea.currentRow)
    end
    
    clipFrame:EnableMouseWheel(true)
    clipFrame:SetScript("OnMouseWheel", function(self, delta)
        if delta > 0 and playerArea.currentRow > 1 then
            playerArea.currentRow = playerArea.currentRow - 1
            scrollToRow(playerArea.currentRow)
        elseif delta < 0 and playerArea.currentRow < playerArea.totalRows then
            playerArea.currentRow = playerArea.currentRow + 1
            scrollToRow(playerArea.currentRow)
        end
    end)
    
    playerArea.updateRowDisplay = updateRowDisplay
    playerArea.scrollToRow = scrollToRow
    rowIndicatorFrame:Hide()
    
    self.playerArea = playerArea
end

function Poker:CreateTestModeBar()
    local testBar = CreateFrame("Frame", nil, self.mainFrame, "BackdropTemplate")
    testBar:SetSize(FRAME_WIDTH - 20, 30)  -- Single row
    testBar:SetPoint("TOP", self.mainFrame, "BOTTOM", 0, -5)
    testBar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
    testBar:SetBackdropColor(0.15, 0.1, 0.2, 0.95)
    testBar:SetBackdropBorderColor(1, 0.4, 1, 1)
    
    local testLabel = testBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    testLabel:SetPoint("LEFT", 10, 0)
    testLabel:SetText("|cffff00ffTEST MODE|r")
    
    local function createTestBtn(text, width, color)
        local btn = CreateFrame("Button", nil, testBar, "BackdropTemplate")
        btn:SetSize(width, 20)
        btn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        local r, g, b = unpack(color or {0.3, 0.2, 0.4})
        btn:SetBackdropColor(r, g, b, 1)
        btn:SetBackdropBorderColor(r + 0.3, g + 0.2, b + 0.4, 1)
        local btnText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        btnText:SetPoint("CENTER")
        btnText:SetText(text)
        btn.text = btnText
        btn.baseColor = {r, g, b}
        btn:SetScript("OnEnter", function(self) self:SetBackdropColor(r + 0.1, g + 0.1, b + 0.1, 1) end)
        btn:SetScript("OnLeave", function(self) 
            local bc = self.baseColor
            self:SetBackdropColor(bc[1], bc[2], bc[3], 1) 
        end)
        return btn
    end
    
    -- Game controls
    local addBtn = createTestBtn("+PLAYER", 60)
    addBtn:SetPoint("LEFT", testLabel, "RIGHT", 10, 0)
    addBtn:SetScript("OnClick", function() self:AddTestPlayer() end)
    
    local remBtn = createTestBtn("-PLAYER", 60)
    remBtn:SetPoint("LEFT", addBtn, "RIGHT", 5, 0)
    remBtn:SetScript("OnClick", function() self:RemoveTestPlayer() end)
    
    local clearBtn = createTestBtn("CLEAR", 50)
    clearBtn:SetPoint("LEFT", remBtn, "RIGHT", 5, 0)
    clearBtn:SetScript("OnClick", function() self:ClearTestPlayers() end)
    
    local dealBtn = createTestBtn("DEAL", 50)
    dealBtn:SetPoint("LEFT", clearBtn, "RIGHT", 10, 0)
    dealBtn:SetScript("OnClick", function()
        if BJ.PokerMultiplayer and BJ.PokerMultiplayer.isHost then
            BJ.PokerMultiplayer:StartDeal()
        end
    end)
    
    local autoBtn = createTestBtn("AUTO*", 55, {0.2, 0.4, 0.2})
    autoBtn:SetPoint("LEFT", dealBtn, "RIGHT", 10, 0)
    autoBtn:SetScript("OnClick", function()
        self.autoPlayEnabled = not self.autoPlayEnabled
        self:UpdateAutoPlayButton()
        self:UpdateDisplay()
    end)
    self.autoPlayBtn = autoBtn
    
    -- Trixie visibility toggle (green)
    local trixToggleBtn = createTestBtn("TRIX", 45, {0.2, 0.4, 0.2})
    trixToggleBtn:SetPoint("LEFT", autoBtn, "RIGHT", 10, 0)
    trixToggleBtn:SetScript("OnClick", function()
        local newState = not self:ShouldShowTrixie()
        self:SetTrixieVisibility(newState)
        -- Update button color
        if newState then
            trixToggleBtn:SetBackdropColor(0.2, 0.4, 0.2, 1)
            trixToggleBtn.baseColor = {0.2, 0.4, 0.2}
        else
            trixToggleBtn:SetBackdropColor(0.3, 0.2, 0.2, 1)
            trixToggleBtn.baseColor = {0.3, 0.2, 0.2}
        end
    end)
    -- Set initial color based on visibility state
    if not self:ShouldShowTrixie() then
        trixToggleBtn:SetBackdropColor(0.3, 0.2, 0.2, 1)
        trixToggleBtn.baseColor = {0.3, 0.2, 0.2}
    end
    self.trixToggleBtn = trixToggleBtn
    
    -- Trixie debug buttons (pink)
    local trixPrevBtn = createTestBtn("<Trix", 40, {0.4, 0.2, 0.3})
    trixPrevBtn:SetPoint("LEFT", trixToggleBtn, "RIGHT", 5, 0)
    trixPrevBtn:SetScript("OnClick", function()
        if BJ.TestMode then BJ.TestMode:PrevTrixieImage() end
    end)
    
    local trixNextBtn = createTestBtn("Trix>", 40, {0.4, 0.2, 0.3})
    trixNextBtn:SetPoint("LEFT", trixPrevBtn, "RIGHT", 5, 0)
    trixNextBtn:SetScript("OnClick", function()
        if BJ.TestMode then BJ.TestMode:NextTrixieImage() end
    end)
    
    -- Clear DB button (orange)
    local clearDbBtn = createTestBtn("CLR DB", 55, {0.5, 0.2, 0.1})
    clearDbBtn:SetPoint("LEFT", trixNextBtn, "RIGHT", 10, 0)
    clearDbBtn:SetScript("OnClick", function()
        StaticPopupDialogs["CASINO_CLEAR_ALL_DB"] = {
            text = "|cffff6666WARNING:|r Clear ALL leaderboard data?\n\nThis will wipe your local database AND send a clear command to all party members!\n\n|cffff9944This cannot be undone!|r",
            button1 = "Clear All",
            button2 = "Cancel",
            OnAccept = function()
                if BJ.Leaderboard then
                    BJ.Leaderboard:ClearAllData(true)
                end
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
        }
        StaticPopup_Show("CASINO_CLEAR_ALL_DB")
    end)
    
    local countText = testBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    countText:SetPoint("RIGHT", -10, 0)
    countText:SetText("Players: 0/10")
    self.testPlayerCount = countText
    
    self.testModeBar = testBar
    testBar:Hide()
end

function Poker:CreateHostPanel()
    local panel = CreateFrame("Frame", "PokerHostPanel", UIParent, "BackdropTemplate")
    panel:SetSize(280, 370)  -- Taller to fit countdown
    panel:SetPoint("CENTER", 0, 20)
    panel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 3,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    panel:SetBackdropColor(0.08, 0.08, 0.08, 0.98)
    panel:SetBackdropBorderColor(1, 0.84, 0, 1)
    panel:SetFrameStrata("DIALOG")
    panel:SetFrameLevel(100)
    
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("5 Card Stud - Host Settings")
    title:SetTextColor(1, 0.84, 0, 1)
    
    local yOffset = -45
    
    -- Ante input
    local anteLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    anteLabel:SetPoint("TOPLEFT", 20, yOffset)
    anteLabel:SetText("Ante (1-1000g):")
    anteLabel:SetTextColor(1, 1, 1, 1)
    
    yOffset = yOffset - 25
    
    local anteInput = CreateFrame("EditBox", nil, panel, "BackdropTemplate")
    anteInput:SetSize(100, 28)
    anteInput:SetPoint("TOPLEFT", 20, yOffset)
    anteInput:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
    anteInput:SetBackdropColor(0.1, 0.1, 0.1, 1)
    anteInput:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    anteInput:SetFontObject("GameFontNormalLarge")
    anteInput:SetJustifyH("CENTER")
    anteInput:SetAutoFocus(false)
    anteInput:SetNumeric(true)
    anteInput:SetMaxLetters(4)
    anteInput:SetText(tostring(BJ.HostSettings:Get("pokerAnte") or 10))
    anteInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    anteInput:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    
    local goldLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    goldLabel:SetPoint("LEFT", anteInput, "RIGHT", 8, 0)
    goldLabel:SetText("g")
    goldLabel:SetTextColor(1, 0.84, 0, 1)
    
    panel.anteInput = anteInput
    
    -- Max raise input (The Cap)
    yOffset = yOffset - 40
    
    local raiseLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    raiseLabel:SetPoint("TOPLEFT", 20, yOffset)
    raiseLabel:SetText("The Cap (1-1000g):")
    raiseLabel:SetTextColor(1, 1, 1, 1)
    
    -- Create invisible button over label for tooltip
    local raiseLabelBtn = CreateFrame("Button", nil, panel)
    raiseLabelBtn:SetAllPoints(raiseLabel)
    raiseLabelBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("The Cap", 1, 0.84, 0)
        GameTooltip:AddLine("The maximum total amount that can be", 1, 1, 1, true)
        GameTooltip:AddLine("bet across all players each round.", 1, 1, 1, true)
        GameTooltip:AddLine("Once the cap is reached, no further", 1, 1, 1, true)
        GameTooltip:AddLine("raises are allowed - players can", 1, 1, 1, true)
        GameTooltip:AddLine("only call or fold.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    raiseLabelBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    
    yOffset = yOffset - 25
    
    local raiseInput = CreateFrame("EditBox", nil, panel, "BackdropTemplate")
    raiseInput:SetSize(100, 28)
    raiseInput:SetPoint("TOPLEFT", 20, yOffset)
    raiseInput:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
    raiseInput:SetBackdropColor(0.1, 0.1, 0.1, 1)
    raiseInput:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    raiseInput:SetFontObject("GameFontNormalLarge")
    raiseInput:SetJustifyH("CENTER")
    raiseInput:SetAutoFocus(false)
    raiseInput:SetNumeric(true)
    raiseInput:SetMaxLetters(4)
    raiseInput:SetText(tostring(BJ.HostSettings:Get("pokerMaxRaise") or 100))
    raiseInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    raiseInput:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    
    local goldLabel2 = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    goldLabel2:SetPoint("LEFT", raiseInput, "RIGHT", 8, 0)
    goldLabel2:SetText("g")
    goldLabel2:SetTextColor(1, 0.84, 0, 1)
    
    panel.raiseInput = raiseInput
    
    -- Max Players
    yOffset = yOffset - 40
    
    local maxPLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    maxPLabel:SetPoint("TOPLEFT", 20, yOffset)
    maxPLabel:SetText("Max Players:")
    maxPLabel:SetTextColor(1, 1, 1, 1)
    
    local maxPValue = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    maxPValue:SetPoint("LEFT", maxPLabel, "RIGHT", 8, 0)
    maxPValue:SetText("(" .. (BJ.HostSettings:Get("pokerMaxPlayers") or 10) .. " max)")
    maxPValue:SetTextColor(0.7, 0.7, 0.7, 1)
    panel.maxPValue = maxPValue
    
    yOffset = yOffset - 28
    
    -- Max players buttons (2-10)
    local maxPButtons = {}
    local btnX = 20
    local currentMaxP = BJ.HostSettings:Get("pokerMaxPlayers") or 10
    for _, num in ipairs({2, 3, 4, 5, 6, 7, 8, 9, 10}) do
        local btn = CreateFrame("Button", nil, panel, "BackdropTemplate")
        btn:SetSize(24, 22)
        btn:SetPoint("TOPLEFT", btnX, yOffset)
        btn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        if num == currentMaxP then
            btn:SetBackdropColor(0.2, 0.5, 0.2, 1)
        else
            btn:SetBackdropColor(0.15, 0.15, 0.15, 1)
        end
        btn:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
        local txt = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        txt:SetPoint("CENTER")
        txt:SetText(tostring(num))
        btn:SetScript("OnClick", function()
            BJ.HostSettings:Set("pokerMaxPlayers", num)
            panel.maxPValue:SetText("(" .. num .. " max)")
            -- Update button colors
            for n, b in pairs(maxPButtons) do
                if n == num then
                    b:SetBackdropColor(0.2, 0.5, 0.2, 1)
                else
                    b:SetBackdropColor(0.15, 0.15, 0.15, 1)
                end
            end
        end)
        btn:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(0.6, 0.6, 0.6, 1) end)
        btn:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(0.4, 0.4, 0.4, 1) end)
        maxPButtons[num] = btn
        btnX = btnX + 26
    end
    panel.maxPButtons = maxPButtons
    
    -- Betting Countdown
    yOffset = yOffset - 35
    
    local cdLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cdLabel:SetPoint("TOPLEFT", 20, yOffset)
    cdLabel:SetText("Time to Join / Deal:")
    cdLabel:SetTextColor(1, 1, 1, 1)
    
    local cdToggle = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    cdToggle:SetSize(22, 22)
    cdToggle:SetPoint("LEFT", cdLabel, "RIGHT", 5, 0)
    cdToggle:SetChecked(BJ.HostSettings:Get("pokerCountdownEnabled") or false)
    panel.cdToggle = cdToggle
    
    local cdStatus = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cdStatus:SetPoint("LEFT", cdToggle, "RIGHT", 2, 0)
    cdStatus:SetTextColor(0.7, 0.7, 0.7, 1)
    panel.cdStatus = cdStatus
    
    -- Countdown seconds buttons
    yOffset = yOffset - 28
    local cdButtons = {}
    local cdBtnX = 20
    local countdownOptions = { 10, 15, 20, 30, 45, 60 }
    local currentCd = BJ.HostSettings:Get("pokerCountdownSeconds") or 15
    
    for i, secs in ipairs(countdownOptions) do
        local btn = CreateFrame("Button", nil, panel, "BackdropTemplate")
        btn:SetSize(35, 22)
        btn:SetPoint("TOPLEFT", cdBtnX, yOffset)
        btn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        btn:SetBackdropColor(0.15, 0.15, 0.15, 1)
        btn:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
        
        local text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetPoint("CENTER")
        text:SetText(secs .. "s")
        btn.text = text
        btn.value = secs
        
        btn:SetScript("OnClick", function(self)
            BJ.HostSettings:Set("pokerCountdownSeconds", self.value)
            BJ.HostSettings:Set("pokerCountdownEnabled", true)
            panel.cdToggle:SetChecked(true)
            Poker:UpdatePokerCountdownButtons()
        end)
        
        btn:SetScript("OnEnter", function(self)
            local cdEnabled = panel.cdToggle:GetChecked()
            if cdEnabled and BJ.HostSettings:Get("pokerCountdownSeconds") ~= self.value then
                self:SetBackdropBorderColor(1, 0.84, 0, 1)
            end
        end)
        
        btn:SetScript("OnLeave", function(self)
            local cdEnabled = panel.cdToggle:GetChecked()
            if not cdEnabled or BJ.HostSettings:Get("pokerCountdownSeconds") ~= self.value then
                self:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
            end
        end)
        
        cdButtons[secs] = btn
        cdBtnX = cdBtnX + 39
    end
    panel.cdButtons = cdButtons
    
    cdToggle:SetScript("OnClick", function(self)
        BJ.HostSettings:Set("pokerCountdownEnabled", self:GetChecked())
        Poker:UpdatePokerCountdownButtons()
    end)
    
    -- Buttons
    yOffset = yOffset - 45
    
    local startBtn = CreateFrame("Button", nil, panel, "BackdropTemplate")
    startBtn:SetSize(100, 30)
    startBtn:SetPoint("TOPLEFT", 20, yOffset)
    startBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
    startBtn:SetBackdropColor(0.15, 0.4, 0.15, 1)
    startBtn:SetBackdropBorderColor(0.3, 0.7, 0.3, 1)
    local startText = startBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    startText:SetPoint("CENTER")
    startText:SetText("Start Game")
    startBtn:SetScript("OnClick", function()
        local ante = tonumber(panel.anteInput:GetText()) or 10
        ante = math.max(1, math.min(1000, ante))
        local maxRaise = tonumber(panel.raiseInput:GetText()) or 100
        maxRaise = math.max(1, math.min(1000, maxRaise))
        local maxPlayers = BJ.HostSettings:Get("pokerMaxPlayers") or 10
        local countdownEnabled = panel.cdToggle:GetChecked()
        local countdownSeconds = BJ.HostSettings:Get("pokerCountdownSeconds") or 15
        
        BJ.HostSettings:Set("pokerAnte", ante)
        BJ.HostSettings:Set("pokerMaxRaise", maxRaise)
        
        panel:Hide()
        Poker:OnHostClick(ante, maxRaise, maxPlayers, countdownEnabled, countdownSeconds)
    end)
    startBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.2, 0.5, 0.2, 1) end)
    startBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.15, 0.4, 0.15, 1) end)
    
    local cancelBtn = CreateFrame("Button", nil, panel, "BackdropTemplate")
    cancelBtn:SetSize(100, 30)
    cancelBtn:SetPoint("LEFT", startBtn, "RIGHT", 20, 0)
    cancelBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
    cancelBtn:SetBackdropColor(0.4, 0.15, 0.15, 1)
    cancelBtn:SetBackdropBorderColor(0.7, 0.3, 0.3, 1)
    local cancelText = cancelBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cancelText:SetPoint("CENTER")
    cancelText:SetText("Cancel")
    cancelBtn:SetScript("OnClick", function() panel:Hide() end)
    cancelBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.5, 0.2, 0.2, 1) end)
    cancelBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.4, 0.15, 0.15, 1) end)
    
    panel:Hide()
    self.hostPanel = panel
end

function Poker:UpdatePokerCountdownButtons()
    if not self.hostPanel or not self.hostPanel.cdButtons then return end
    
    local cdEnabled = self.hostPanel.cdToggle:GetChecked()
    local currentSecs = BJ.HostSettings:Get("pokerCountdownSeconds") or 15
    
    -- Update status text
    if cdEnabled then
        self.hostPanel.cdStatus:SetText(currentSecs .. "s")
    else
        self.hostPanel.cdStatus:SetText("Off")
    end
    
    -- Update button highlighting
    for secs, btn in pairs(self.hostPanel.cdButtons) do
        if cdEnabled and secs == currentSecs then
            btn:SetBackdropColor(0.2, 0.4, 0.2, 1)
            btn:SetBackdropBorderColor(0.3, 0.8, 0.3, 1)
        else
            btn:SetBackdropColor(0.15, 0.15, 0.15, 1)
            btn:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
        end
    end
end

function Poker:CreateFlyingCard()
    local card = CreateFrame("Frame", nil, self.mainFrame)
    card:SetSize(UI.Cards.CARD_WIDTH, UI.Cards.CARD_HEIGHT)
    card:SetFrameStrata("TOOLTIP")
    card:SetFrameLevel(100)
    
    card.backTexture = card:CreateTexture(nil, "ARTWORK")
    card.backTexture:SetAllPoints()
    card.backTexture:SetTexture(UI.Cards:GetCardBackTexture())
    
    card.spinGroup = card:CreateAnimationGroup()
    card.spinAnim = card.spinGroup:CreateAnimation("Rotation")
    card.spinAnim:SetOrder(1)
    card.spinAnim:SetDuration(0.25)
    card.spinAnim:SetDegrees(-360)
    card.spinAnim:SetOrigin("CENTER", 0, 0)
    card.spinGroup:SetLooping("NONE")
    
    card:Hide()
    self.flyingCard = card
end

function Poker:ShowHostPanel()
    if not self.hostPanel then return end
    self.hostPanel.anteInput:SetText(tostring(BJ.HostSettings:Get("pokerAnte") or 10))
    self.hostPanel.raiseInput:SetText(tostring(BJ.HostSettings:Get("pokerMaxRaise") or 100))
    self.hostPanel.cdToggle:SetChecked(BJ.HostSettings:Get("pokerCountdownEnabled") or false)
    self:UpdatePokerCountdownButtons()
    self.hostPanel:Show()
end

function Poker:Show()
    if not self.mainFrame then self:CreateMainFrame() end
    
    -- Hide other game windows
    if UI.HiLo and UI.HiLo.container and UI.HiLo.container:IsShown() then
        UI.HiLo:Hide()
    end
    if UI.mainFrame and UI.mainFrame:IsShown() then
        UI:Hide()
    end
    if UI.Lobby and UI.Lobby.frame and UI.Lobby.frame:IsShown() then
        UI.Lobby.frame:Hide()
    end
    if UI.Craps then
        UI.Craps:OnOtherWindowOpened()
    end
    
    -- Apply saved window scale
    if UI.Lobby and UI.Lobby.ApplyWindowScale then
        UI.Lobby:ApplyWindowScale()
    end
    
    self.mainFrame:Show()
    self:UpdateTestModeLayout()
    self:UpdateDisplay()
    
    -- Start action button refresh ticker
    self:StartActionButtonRefreshTicker()
    
    -- Refresh Trixie debug if active
    if BJ.TestMode and BJ.TestMode.RefreshTrixieDebug then
        BJ.TestMode:RefreshTrixieDebug()
    end
end

function Poker:Hide()
    if self.mainFrame then self.mainFrame:Hide() end
    if self.hostPanel then self.hostPanel:Hide() end
    if self.logFrame then self.logFrame:Hide() end
    -- Stop the refresh ticker
    self:StopActionButtonRefreshTicker()
    -- Hide session leaderboard when game window closes
    if BJ.LeaderboardUI then
        BJ.LeaderboardUI:HideSession("poker")
    end
end

function Poker:UpdateTestModeLayout()
    if not self.testModeBar then return end
    if BJ.TestMode and BJ.TestMode.enabled then
        self.testModeBar:Show()
    else
        self.testModeBar:Hide()
    end
end

function Poker:UpdateAutoPlayButton()
    if not self.autoPlayBtn then return end
    if self.autoPlayEnabled then
        self.autoPlayBtn.text:SetText("AUTO*")
        self.autoPlayBtn:SetBackdropColor(0.2, 0.4, 0.2, 1)
        self.autoPlayBtn.baseColor = {0.2, 0.4, 0.2}
    else
        self.autoPlayBtn.text:SetText("AUTO")
        self.autoPlayBtn:SetBackdropColor(0.4, 0.2, 0.2, 1)
        self.autoPlayBtn.baseColor = {0.4, 0.2, 0.2}
    end
end

-- Button handlers
function Poker:OnHostClick(ante, maxRaise, maxPlayers, countdownEnabled, countdownSeconds)
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
    
    ante = ante or BJ.HostSettings:Get("pokerAnte") or 10
    maxRaise = maxRaise or BJ.HostSettings:Get("pokerMaxRaise") or 100
    maxPlayers = maxPlayers or BJ.HostSettings:Get("pokerMaxPlayers") or 10
    countdownEnabled = countdownEnabled or false
    countdownSeconds = countdownSeconds or BJ.HostSettings:Get("pokerCountdownSeconds") or 15
    local settings = { 
        ante = ante, 
        maxRaise = maxRaise, 
        maxPlayers = maxPlayers,
        countdownEnabled = countdownEnabled,
        countdownSeconds = countdownSeconds
    }
    if BJ.PokerMultiplayer then BJ.PokerMultiplayer:HostTable(settings) end
end

function Poker:OnDealClick()
    if BJ.PokerMultiplayer and BJ.PokerMultiplayer.isHost then
        BJ.PokerMultiplayer:StartDeal()
    end
end

function Poker:OnResetClick()
    -- Confirm dialog before reset
    StaticPopupDialogs["CASINO_POKER_RESET"] = {
        text = "|cffffd700Reset 5 Card Stud Game?|r\n\nThis will cancel the current game for all players.",
        button1 = "Reset",
        button2 = "Cancel",
        OnAccept = function()
            if BJ.PokerMultiplayer then BJ.PokerMultiplayer:ResetGame() end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    StaticPopup_Show("CASINO_POKER_RESET")
end

function Poker:OnJoinClick()
    local PS = BJ.PokerState
    if BJ.PokerMultiplayer then BJ.PokerMultiplayer:PlaceAnte(PS.ante) end
end

function Poker:OnFoldClick()
    if BJ.PokerMultiplayer then BJ.PokerMultiplayer:PlayerAction("fold") end
end

-- Combined Check/Call button - determines action based on current state
function Poker:OnCheckCallClick()
    local PS = BJ.PokerState
    local myName = UnitName("player")
    local myPlayer = PS.players[myName]
    
    if not myPlayer then return end
    
    local playerBet = myPlayer.currentBet or 0
    local toCall = (PS.currentBet or 0) - playerBet
    
    if toCall <= 0 then
        -- Can check
        if BJ.PokerMultiplayer then BJ.PokerMultiplayer:PlayerAction("check") end
    else
        -- Must call
        if BJ.PokerMultiplayer then BJ.PokerMultiplayer:PlayerAction("call") end
    end
end

function Poker:OnRaiseClick()
    local amount = tonumber(self.raiseInput:GetText()) or 10
    if BJ.PokerMultiplayer then BJ.PokerMultiplayer:PlayerAction("raise", amount) end
end

-- Test mode functions
function Poker:AddTestPlayer()
    local PS = BJ.PokerState
    if #self.testPlayers >= 9 then
        BJ:Print("Max test players (9 + you = 10)")
        return
    end
    for _, name in ipairs(self.testPlayerNames) do
        local exists = false
        for _, p in ipairs(self.testPlayers) do if p == name then exists = true break end end
        if not exists and not PS.players[name] then
            table.insert(self.testPlayers, name)
            BJ:Print("Added: " .. name)
            if PS.phase == PS.PHASE.WAITING_FOR_PLAYERS then
                PS:PlayerAnte(name, PS.ante)
                self:OnPlayerAnted(name, PS.ante)
            end
            break
        end
    end
    self:UpdateTestPlayerCount()
    self:UpdateDisplay()
end

function Poker:RemoveTestPlayer()
    if #self.testPlayers > 0 then
        local name = table.remove(self.testPlayers)
        BJ:Print("Removed: " .. name)
        self:UpdateTestPlayerCount()
        self:UpdateDisplay()
    end
end

function Poker:ClearTestPlayers()
    self.testPlayers = {}
    BJ:Print("All test players cleared.")
    self:UpdateTestPlayerCount()
    self:UpdateDisplay()
end

function Poker:AnteTestPlayers()
    local PS = BJ.PokerState
    if PS.phase ~= PS.PHASE.WAITING_FOR_PLAYERS then return end
    for _, name in ipairs(self.testPlayers) do
        if not PS.players[name] then
            PS:PlayerAnte(name, PS.ante)
            self:OnPlayerAnted(name, PS.ante)
        end
    end
end

function Poker:UpdateTestPlayerCount()
    if not self.testPlayerCount then return end
    local PS = BJ.PokerState
    self.testPlayerCount:SetText("Players: " .. #PS.playerOrder .. "/10")
end

-- Display functions
function Poker:UpdateDisplay()
    -- Guard against uninitialized UI
    if not self.isInitialized then
        return
    end
    
    self:UpdateInfoText()
    self:UpdatePlayerHands()
    self:UpdatePot()
    self:UpdateStatus()
    self:UpdateButtons()
    self:UpdateTestPlayerCount()
end

function Poker:UpdateInfoText()
    local PS = BJ.PokerState
    local PM = BJ.PokerMultiplayer
    
    if not self.infoText then return end
    
    if PM and PM.tableOpen then
        local hostName = PM.currentHost or "?"
        local ante = PS.ante or 0
        local maxRaise = PS.maxRaise or 0
        local remaining = PS:GetRemainingCards()
        local seedText = PS.seed and (" | Seed: " .. PS.seed) or ""
        self.infoText:SetText(string.format("Host: %s | Ante: %dg | Cap: %dg | Remaining Cards: %d%s", 
            hostName, ante, maxRaise, remaining, seedText))
    else
        self.infoText:SetText("")
    end
end

function Poker:UpdatePlayerHands()
    -- Guard against uninitialized UI
    if not self.isInitialized or not self.playerArea then
        return
    end
    
    local PS = BJ.PokerState
    local myName = UnitName("player")
    local container = self.playerArea.content
    local isShowdown = PS.phase == PS.PHASE.SHOWDOWN or PS.phase == PS.PHASE.SETTLEMENT
    
    for _, hand in pairs(self.playerArea.hands) do
        hand:Hide()
    end
    
    if #PS.playerOrder == 0 then
        self.playerArea.totalRows = 1
        self.playerArea.updateRowDisplay()
        return
    end
    
    local handDisplayIndex = 0
    
    for playerIdx, playerName in ipairs(PS.playerOrder) do
        local player = PS.players[playerName]
        if player then
            handDisplayIndex = handDisplayIndex + 1
            
            while #self.playerArea.hands < handDisplayIndex do
                local newHand = self:CreateCompactHandDisplay(container, "PokerHand" .. (#self.playerArea.hands + 1))
                table.insert(self.playerArea.hands, newHand)
            end
            
            local handDisplay = self.playerArea.hands[handDisplayIndex]
            
            local rowNum = math.ceil(handDisplayIndex / PLAYER_COLS)
            local posInRow = ((handDisplayIndex - 1) % PLAYER_COLS)
            local xOffset = (posInRow - 2) * PLAYER_CELL_WIDTH
            -- Position from bottom: row 1 at bottom, row 2 above it
            local yOffset = (rowNum - 1) * PLAYER_CELL_HEIGHT + PLAYER_CELL_HEIGHT / 2 + 5
            
            handDisplay:ClearAllPoints()
            handDisplay:SetPoint("CENTER", container, "BOTTOM", xOffset, yOffset)
            
            -- Determine cards to show based on dealt animation
            -- During animation, only show cards that have been "dealt" (animated to player)
            -- Default to 0 if animation is in progress, or full hand if not animating
            local dealtCount
            if self.isDealingAnimation then
                dealtCount = self.dealtCards[playerName] or 0
            else
                dealtCount = self.dealtCards[playerName] or #player.hand
            end
            
            local cardsToShow = {}
            for i = 1, math.min(dealtCount, #player.hand) do
                local card = player.hand[i]
                local showFace = card.faceUp or (playerName == myName) or isShowdown
                table.insert(cardsToShow, {
                    rank = card.rank,
                    suit = card.suit,
                    faceUp = showFace
                })
            end
            
            self:UpdateCompactHandDisplay(handDisplay, playerName, cardsToShow, player, isShowdown)
            
            handDisplay.playerName = playerName
            handDisplay.playerIndex = playerIdx
            handDisplay:Show()
        end
    end
    
    local totalPlayers = handDisplayIndex
    self.playerArea.totalRows = math.max(1, math.ceil(totalPlayers / PLAYER_COLS) - 1)
    self.playerArea.updateRowDisplay()
end

function Poker:CreateCompactHandDisplay(parent, name)
    local hand = CreateFrame("Frame", name, parent)
    hand:SetSize(150, PLAYER_CELL_HEIGHT)
    
    hand.label = hand:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hand.label:SetPoint("TOP", 0, 0)
    hand.label:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    
    hand.cardContainer = CreateFrame("Frame", nil, hand)
    hand.cardContainer:SetSize(150, UI.Cards.CARD_HEIGHT)
    hand.cardContainer:SetPoint("TOP", hand.label, "BOTTOM", 0, -8)  -- More space between name and cards
    
    hand.cards = {}
    
    -- Hand rank text (shows during settlement) - use higher draw layer to display above cards
    hand.handRank = hand:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hand.handRank:SetPoint("TOP", hand.cardContainer, "BOTTOM", 0, -9)  -- Lowered 5pts
    hand.handRank:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    hand.handRank:SetDrawLayer("OVERLAY", 7)  -- Higher sublayer to appear above cards
    hand.handRank:Hide()
    
    return hand
end

function Poker:UpdateCompactHandDisplay(handDisplay, playerName, cardsToShow, player, isShowdown)
    local PS = BJ.PokerState
    
    local isCurrentPlayer = (PS.phase == PS.PHASE.BETTING and PS:GetCurrentPlayer() == playerName)
    local label = playerName
    if isCurrentPlayer then
        label = "|cff00ff00>> " .. playerName .. " <<|r"
    elseif player.folded then
        label = "|cff666666" .. playerName .. " (FOLD)|r"
    end
    handDisplay.label:SetText(label)
    
    -- Create or update active player highlight background
    if not handDisplay.activeBg then
        handDisplay.activeBg = handDisplay:CreateTexture(nil, "BACKGROUND", nil, -1)
        handDisplay.activeBg:SetTexture("Interface\\Buttons\\WHITE8x8")
        handDisplay.activeBg:SetPoint("TOPLEFT", -5, 5)
        handDisplay.activeBg:SetPoint("BOTTOMRIGHT", 5, -5)
    end
    
    if isCurrentPlayer then
        handDisplay.activeBg:SetVertexColor(0, 0.5, 0, 0.4)  -- Green glow
        handDisplay.activeBg:Show()
    else
        handDisplay.activeBg:Hide()
    end
    
    for _, card in ipairs(handDisplay.cards) do
        UI.Cards:ReleaseCard(card)
    end
    handDisplay.cards = {}
    
    local cardWidth = UI.Cards.CARD_WIDTH
    local cardSpacing = UI.Cards.CARD_SPACING
    local totalWidth = #cardsToShow > 0 and (cardWidth + (cardSpacing * (#cardsToShow - 1))) or 0
    local startX = -totalWidth / 2 + cardWidth / 2
    
    -- Generate consistent seed for this player
    local seed = 0
    for c = 1, #playerName do seed = seed + string.byte(playerName, c) end
    
    local baseLevel = handDisplay.cardContainer:GetFrameLevel() + 1
    
    for i, cardData in ipairs(cardsToShow) do
        local card = UI.Cards:GetCard(handDisplay.cardContainer, false)
        UI.Cards:SetCard(card, cardData, cardData.faceUp)
        
        card:SetFrameLevel(baseLevel + (i * 2))
        if card.back then
            card.back:SetFrameLevel(baseLevel + (i * 2) + 1)
        end
        
        -- Calculate random but consistent rotation and offset (like blackjack)
        local cardSeed = seed + i + (cardData.rank and string.byte(cardData.rank, 1) or 0) + (cardData.suit and string.byte(cardData.suit, 1) or 0)
        local rotationVariance = ((cardSeed % 30) - 15) * 0.01
        local xVariance = ((cardSeed * 7) % 11) - 5
        local yVariance = (((cardSeed * 13) % 11) - 5)
        
        card:ClearAllPoints()
        card:SetPoint("CENTER", handDisplay.cardContainer, "CENTER", startX + (i - 1) * cardSpacing + xVariance, yVariance)
        
        if card.faceTexture then
            card.faceTexture:SetRotation(rotationVariance)
        end
        if card.back and card.back.texture then
            card.back.texture:SetRotation(rotationVariance)
        end
        
        card:Show()
        table.insert(handDisplay.cards, card)
    end
    
    if isShowdown and player.handName and not player.folded then
        handDisplay.handRank:SetText("|cffffd700" .. player.handName .. "|r")
        handDisplay.handRank:Show()
    else
        handDisplay.handRank:Hide()
    end
end

function Poker:UpdatePot()
    local PS = BJ.PokerState
    if PS.pot > 0 then
        self.potAmount:SetText("|cffffffff" .. PS.pot .. "g|r")
        self.potFrame:Show()
    else
        self.potFrame:Hide()
    end
    
    -- Show settlement list during settlement phase
    -- Check that settlements table exists and has entries
    local hasSettlements = PS.settlements and next(PS.settlements) ~= nil
    BJ:Debug("UpdatePot: phase=" .. (PS.phase or "nil") .. ", hasSettlements=" .. tostring(hasSettlements))
    
    if PS.phase == PS.PHASE.SETTLEMENT and hasSettlements then
        BJ:Debug("UpdatePot: showing settlement frame")
        self:UpdateSettlementList()
        self.settlementFrame:Show()
    else
        if self.settlementFrame then
            self.settlementFrame:Hide()
        end
    end
end

function Poker:UpdateSettlementList()
    local PS = BJ.PokerState
    if not PS.settlements then 
        BJ:Debug("UpdateSettlementList: no settlements table")
        return 
    end
    
    -- Count settlements
    local settlementCount = 0
    for _ in pairs(PS.settlements) do
        settlementCount = settlementCount + 1
    end
    BJ:Debug("UpdateSettlementList: settlementCount=" .. settlementCount)
    
    if settlementCount == 0 then
        BJ:Debug("UpdateSettlementList: settlements table is empty")
        return
    end
    
    if not PS.winners or #PS.winners == 0 then 
        BJ:Debug("UpdateSettlementList: no winners")
        return 
    end
    
    BJ:Debug("UpdateSettlementList: winner=" .. PS.winners[1])
    
    local winner = PS.winners[1]  -- Primary winner
    local winnerHand = ""
    if PS.settlements[winner] then
        winnerHand = PS.settlements[winner].handName or ""
        BJ:Debug("UpdateSettlementList: winnerHand=" .. winnerHand)
    end
    
    -- Build list of what each player owes/wins
    local playerList = {}
    for playerName, data in pairs(PS.settlements) do
        local bet = data.bet or 0
        -- Also check player object for totalBet
        local player = PS.players[playerName]
        if player and player.totalBet and player.totalBet > 0 then
            bet = player.totalBet
        end
        
        table.insert(playerList, {
            name = playerName,
            bet = bet,
            folded = data.folded,
            isWinner = data.isWinner,
            handName = data.handName,
            total = data.total or 0,  -- Net win/loss
        })
    end
    
    -- Sort by bet amount (most to least) for losers
    table.sort(playerList, function(a, b)
        if a.isWinner ~= b.isWinner then
            return a.isWinner  -- Winners first
        end
        return a.bet > b.bet  -- Then by bet amount
    end)
    
    -- Build display text
    local lines = {}
    
    -- Show winner with hand
    if #PS.winners == 1 then
        local winMessage = winner .. " wins"
        if winnerHand and winnerHand ~= "" and winnerHand ~= "?" then
            winMessage = winMessage .. " with " .. winnerHand .. "!"
        else
            winMessage = winMessage .. "!"
        end
        table.insert(lines, "|cff00ff00" .. winMessage .. "|r")
        table.insert(lines, "")
        
        -- Show ledger: who owes winner how much (sorted from most to least)
        table.insert(lines, "|cffffffffLedger:|r")
        local losers = {}
        for _, entry in ipairs(playerList) do
            if not entry.isWinner and entry.bet > 0 then
                table.insert(losers, entry)
            end
        end
        -- Sort losers by amount owed (most first)
        table.sort(losers, function(a, b) return a.bet > b.bet end)
        
        for _, entry in ipairs(losers) do
            local foldText = entry.folded and " (fold)" or ""
            table.insert(lines, "  " .. entry.name .. foldText .. " owes |cffffd700" .. entry.bet .. "g|r")
        end
    else
        -- Split pot
        table.insert(lines, "|cffffd700Split pot!|r")
        local winShare = math.floor(PS.pot / #PS.winners)
        for _, w in ipairs(PS.winners) do
            local wData = PS.settlements[w]
            local wHand = wData and wData.handName or ""
            table.insert(lines, "|cff00ff00" .. w .. ": +" .. winShare .. "g|r")
            if wHand and wHand ~= "" and wHand ~= "?" then
                table.insert(lines, "  |cff88ff88" .. wHand .. "|r")
            end
        end
        table.insert(lines, "")
        table.insert(lines, "|cffffffffLedger:|r")
        for _, entry in ipairs(playerList) do
            if not entry.isWinner and entry.bet > 0 then
                local foldText = entry.folded and " (fold)" or ""
                table.insert(lines, "  " .. entry.name .. foldText .. " owes |cffffd700" .. entry.bet .. "g|r")
            end
        end
    end
    
    local text = table.concat(lines, "\n")
    self.settlementText:SetText(text)
    
    -- Resize frame to fit content
    local numLines = #lines
    local frameHeight = math.max(84, numLines * 17 + 48)  -- 60*1.4, 12*1.4, 28+6 padding
    self.settlementFrame:SetSize(360, frameHeight)  -- Width constrained to not overlap host button
    
    BJ:Debug("UpdateSettlementList: displayed " .. numLines .. " lines")
end

function Poker:UpdateStatus()
    local PS = BJ.PokerState
    local msg = ""
    local inTestMode = BJ.TestMode and BJ.TestMode.enabled
    local inPartyOrRaid = IsInGroup() or IsInRaid()
    
    if PS.phase == PS.PHASE.IDLE then
        -- Show party/raid warning if not in group and not in test mode
        if not inPartyOrRaid and not inTestMode then
            msg = "|cffff8800Join a party or raid to host a game.|r"
        else
            msg = "Click HOST to start a game."
        end
    elseif PS.phase == PS.PHASE.WAITING_FOR_PLAYERS then
        msg = "Waiting for players... (" .. #PS.playerOrder .. "/10)"
    elseif PS.phase == PS.PHASE.DEALING then
        msg = "Dealing cards..."
    elseif PS.phase == PS.PHASE.BETTING then
        local currentPlayer = PS:GetCurrentPlayer()
        local streetNames = { "Street 1 (Bring-in)", "Street 2", "Street 3", "River" }
        local streetName = streetNames[PS.currentStreet] or "Betting"
        if currentPlayer == UnitName("player") then
            local myBet = PS.players[currentPlayer] and PS.players[currentPlayer].currentBet or 0
            local toCall = PS.currentBet - myBet
            if toCall > 0 then
                msg = "|cff00ff00YOUR TURN|r - " .. streetName .. " - Call " .. toCall .. "g or Raise"
            else
                msg = "|cff00ff00YOUR TURN|r - " .. streetName .. " - Check or Raise"
            end
        else
            msg = streetName .. " - Waiting for " .. (currentPlayer or "?") .. "..."
        end
    elseif PS.phase == PS.PHASE.SHOWDOWN then
        msg = "SHOWDOWN!"
    elseif PS.phase == PS.PHASE.SETTLEMENT then
        if PS.winners and #PS.winners > 0 then
            if #PS.winners == 1 then
                local w = PS.winners[1]
                -- Get detailed hand name from settlements
                local handName = "Unknown"
                if PS.settlements and PS.settlements[w] then
                    handName = PS.settlements[w].handName or "Unknown"
                elseif PS.players[w] then
                    handName = PS.players[w].handName or "Unknown"
                end
                msg = "|cff00ff00" .. w .. " wins with " .. handName .. "!|r"
            else
                -- Multiple winners - show hands
                local winnerParts = {}
                for _, w in ipairs(PS.winners) do
                    local handName = "Unknown"
                    if PS.settlements and PS.settlements[w] then
                        handName = PS.settlements[w].handName or "Unknown"
                    end
                    table.insert(winnerParts, w .. " (" .. handName .. ")")
                end
                msg = "|cff00ff00Split pot: " .. table.concat(winnerParts, ", ") .. "|r"
            end
        end
    end
    
    self.statusBar.text:SetText(msg)
end

function Poker:UpdateButtons()
    local PS = BJ.PokerState
    local PM = BJ.PokerMultiplayer
    local myName = UnitName("player")
    local isHost = PM and PM.isHost
    local tableOpen = PM and PM.tableOpen
    local inGame = PS.players[myName] ~= nil
    local isMyTurn = PS:CanPlayerAct(myName)
    local inTestMode = BJ.TestMode and BJ.TestMode.enabled
    local inParty = IsInGroup() or IsInRaid()
    
    -- Turn timer management
    if PM then
        if isMyTurn and not PM.turnTimerActive then
            -- Start timer when it becomes my turn
            PM:StartTurnTimer()
        elseif not isMyTurn and PM.turnTimerActive then
            -- Cancel timer when it's no longer my turn
            PM:CancelTurnTimer()
        end
    end
    
    for _, btn in pairs(self.buttons) do btn:SetEnabled(false) end
    
    -- LOG button is always enabled
    self.buttons.log:SetEnabled(true)
    
    -- Update centered action button (Host/Join)
    self:UpdatePokerActionButton()
    
    -- DEAL button - only show for host when deal is available
    if isHost and PS.phase == PS.PHASE.WAITING_FOR_PLAYERS and #PS.playerOrder >= 2 then
        self.buttons.deal:SetEnabled(true)
        self.buttons.deal:Show()
    else
        self.buttons.deal:SetEnabled(false)
        self.buttons.deal:Hide()
    end
    
    -- RESET button - always enabled for host when not idle
    if isHost and PS.phase ~= PS.PHASE.IDLE then
        self.buttons.reset:SetEnabled(true)
    end
    
    local myPlayer = PS.players[myName]
    local canFold = inGame and myPlayer and not myPlayer.folded and PS.phase == PS.PHASE.BETTING
    self.buttons.fold:SetEnabled(canFold)
    
    -- Calculate max remaining raise for this round
    local maxRaise = PS.maxRaise or 100
    local currentBet = PS.currentBet or 0
    local remainingRaise = maxRaise - currentBet
    if remainingRaise < 0 then remainingRaise = 0 end
    self.maxRemainingRaise = remainingRaise
    
    -- Update MAX RAISE button label
    if self.buttons.maxRaise then
        self.buttons.maxRaise.text:SetText("RAISE (" .. remainingRaise .. ")")
    end
    
    -- Update RAISE button label based on input
    self:UpdateRaiseButtonLabel()
    
    -- Update combined Check/Call button label and state
    if isMyTurn then
        local playerBet = myPlayer and myPlayer.currentBet or 0
        local toCall = (PS.currentBet or 0) - playerBet
        
        if toCall <= 0 then
            -- Can check
            self.buttons.checkCall.text:SetText("CHECK")
            self.buttons.checkCall:SetEnabled(true)
        else
            -- Must call
            self.buttons.checkCall.text:SetText("CALL " .. toCall)
            self.buttons.checkCall:SetEnabled(true)
        end
        
        -- Enable raise buttons if allowed
        local actions = PS:GetAvailableActions(myName)
        for _, action in ipairs(actions) do
            if action == PS.ACTION.RAISE then 
                self.buttons.raise:SetEnabled(true)
                if remainingRaise > 0 then
                    self.buttons.maxRaise:SetEnabled(true)
                end
            end
        end
    else
        -- Not my turn - show CHECK as default label
        self.buttons.checkCall.text:SetText("CHECK")
    end
end

-- Validate raise input to be between 1 and max remaining raise
function Poker:ValidateRaiseInput()
    if not self.raiseInput then return end
    
    local inputVal = tonumber(self.raiseInput:GetText())
    local maxRemaining = self.maxRemainingRaise or 1
    
    -- Ensure minimum of 1
    if not inputVal or inputVal < 1 then
        self.raiseInput:SetText("1")
        return
    end
    
    -- Ensure maximum of remaining raise
    if inputVal > maxRemaining then
        self.raiseInput:SetText(tostring(maxRemaining))
        return
    end
end

-- Update raise button label based on input value
function Poker:UpdateRaiseButtonLabel()
    if self.raiseInput and self.buttons.raise then
        local text = self.raiseInput:GetText()
        local inputVal = tonumber(text)
        local maxRemaining = self.maxRemainingRaise or 1
        
        -- Handle blank or invalid input - show "RAISE (?)" while typing
        if not inputVal or text == "" then
            self.buttons.raise.text:SetText("RAISE (?)")
            return
        end
        
        if inputVal < 1 then inputVal = 1 end
        if inputVal > maxRemaining then inputVal = maxRemaining end
        self.buttons.raise.text:SetText("RAISE (" .. inputVal .. ")")
    end
end

-- Handle max raise click
function Poker:OnMaxRaiseClick()
    local PS = BJ.PokerState
    local maxRaise = self.maxRemainingRaise or 0
    if maxRaise > 0 then
        -- Set the input to max and call raise
        if self.raiseInput then
            self.raiseInput:SetText(tostring(maxRaise))
        end
        self:OnRaiseClick()
    end
end

-- Trixie state functions (matching Blackjack pattern)
function Poker:SetTrixieState(state)
    if not self.trixieFrame then return end
    self.trixieFrame.texture:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\dealer\\trix_" .. state)
end

function Poker:SetTrixieWait()
    if not self.trixieFrame then return end
    self.trixieFrame:SetRandomWait()
end

function Poker:SetTrixieDeal()
    if not self.trixieFrame then return end
    self.trixieFrame:SetRandomDeal()
end

function Poker:SetTrixieShuffle()
    if not self.trixieFrame then return end
    self.trixieFrame:SetRandomShuffle()
end

function Poker:SetTrixieCheer()
    if not self.trixieFrame then return end
    self.trixieFrame:SetRandomCheer()
end

function Poker:SetTrixieLose()
    if not self.trixieFrame then return end
    self.trixieFrame:SetRandomLose()
end

function Poker:SetTrixieLove()
    if not self.trixieFrame then return end
    self.trixieFrame:SetRandomLove()
end

-- Toggle Trixie visibility and resize window
function Poker:SetTrixieVisibility(show)
    if not ChairfacesCasinoDB then ChairfacesCasinoDB = { settings = {} } end
    if not ChairfacesCasinoDB.settings then ChairfacesCasinoDB.settings = {} end
    ChairfacesCasinoDB.settings.pokerShowTrixie = show
    
    -- Update dimensions
    self:UpdateFrameDimensions()
    
    -- Resize main frame
    if self.mainFrame then
        self.mainFrame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
        -- Update felt background texture coords
        if self.mainFrame.UpdateFeltTexCoords then
            self.mainFrame:UpdateFeltTexCoords()
        end
    end
    
    -- Reposition all play area elements (including Trixie and status bar)
    self:RepositionPlayAreaElements()
end

-- Reposition Trixie relative to status bar
function Poker:RepositionTrixie()
    if not self.trixieFrame then return end
    
    local showTrixie = self:ShouldShowTrixie()
    self.trixieFrame:ClearAllPoints()
    
    if showTrixie then
        -- Button area is at BOTTOM +15, buttons are 32px tall
        -- Status bar is 5px above buttons, 25px tall
        -- Status bar top is at: 15 + 32 + 5 + 25 = 77px from bottom
        -- Add half status bar height (13px) to align Trixie bottom with status bar top
        local TRIXIE_BOTTOM_OFFSET = 95
        self.trixieFrame:SetPoint("BOTTOMLEFT", self.mainFrame, "BOTTOMLEFT", TRIXIE_LEFT_PADDING, TRIXIE_BOTTOM_OFFSET)
        self.trixieFrame:Show()
    else
        self.trixieFrame:Hide()
    end
end

-- Reposition all elements that depend on PLAY_AREA_OFFSET
function Poker:RepositionPlayAreaElements()
    -- Dealer area - centered in play area
    if self.dealerArea then
        self.dealerArea:ClearAllPoints()
        self.dealerArea:SetPoint("TOP", self.mainFrame, "TOP", PLAY_AREA_OFFSET / 2, -45)
    end
    
    -- Title bar
    if self.titleBar then
        self.titleBar:SetWidth(FRAME_WIDTH - 16)
    end
    
    -- Button area - centered in play area (aligned with pot)
    if self.buttonArea then
        self.buttonArea:ClearAllPoints()
        self.buttonArea:SetPoint("BOTTOM", self.mainFrame, "BOTTOM", PLAY_AREA_OFFSET / 2, 15)
    end
    
    -- Status bar width - uses play area width, position follows buttons
    if self.statusBar then
        self.statusBar:SetWidth(PLAY_AREA_WIDTH - 100)
    end
    
    -- HOST/JOIN action button - centered in play area (aligned with pot)
    if self.actionButton then
        self.actionButton:ClearAllPoints()
        self.actionButton:SetPoint("CENTER", self.mainFrame, "CENTER", PLAY_AREA_OFFSET / 2, 0)
    end
    
    -- Player area clip frame - align to RIGHT edge of window (15px from border)
    if self.playerArea and self.playerArea.clipFrame then
        self.playerArea.clipFrame:ClearAllPoints()
        -- Anchor to RIGHT side of window, 15px from edge
        self.playerArea.clipFrame:SetPoint("BOTTOMRIGHT", self.mainFrame, "BOTTOMRIGHT", -15, 77)
    end
    
    -- Test bar - resize to match current window width
    if self.testModeBar then
        self.testModeBar:SetSize(FRAME_WIDTH - 20, 30)
    end
    
    -- Reposition Trixie
    self:RepositionTrixie()
    
    -- Update display
    self:UpdateDisplay()
end

function Poker:GetHandDisplayForPlayer(playerName)
    local PS = BJ.PokerState
    for i, name in ipairs(PS.playerOrder) do
        if name == playerName then
            return self.playerArea.hands[i]
        end
    end
    return nil
end

-- Flying card animation
function Poker:AnimateCardToPlayer(playerName, cardData, faceUp, onComplete)
    local handDisplay = self:GetHandDisplayForPlayer(playerName)
    if not handDisplay or not self.flyingCard then
        if onComplete then onComplete() end
        return
    end
    
    if UI.Lobby then UI.Lobby:PlayCardSound() end
    
    self.flyingCard.backTexture:SetTexture(UI.Cards:GetCardBackTexture())
    
    local startX = self.DEAL_START_X
    local startY = self.DEAL_START_Y
    
    local cardContainer = handDisplay.cardContainer
    if not cardContainer or not cardContainer:GetLeft() then
        if onComplete then onComplete() end
        return
    end
    
    -- Target the center of the card container, offset by card position
    local numCards = self.dealtCards[playerName] or 0
    local cardSpacing = UI.Cards.CARD_SPACING
    local cardWidth = UI.Cards.CARD_WIDTH or 50
    
    -- Calculate center of the card container
    local containerCenterX = (cardContainer:GetLeft() + cardContainer:GetRight()) / 2
    local containerCenterY = (cardContainer:GetTop() + cardContainer:GetBottom()) / 2
    
    -- Offset for which card slot we're dealing to (cards fan out from center)
    local totalCardWidth = (numCards + 1) * cardSpacing
    local cardOffset = (numCards * cardSpacing) - (totalCardWidth / 2) + (cardSpacing / 2)
    
    local endX = containerCenterX - self.mainFrame:GetLeft() + cardOffset - (cardWidth / 2)
    local endY = containerCenterY - self.mainFrame:GetTop()
    
    self.flyingCard:ClearAllPoints()
    self.flyingCard:SetPoint("TOPLEFT", self.mainFrame, "TOPLEFT", startX, startY)
    self.flyingCard:Show()
    
    if self.flyingCard.spinGroup then
        self.flyingCard.spinGroup:Stop()
        self.flyingCard.spinGroup:Play()
    end
    
    local elapsed = 0
    local duration = self.DEAL_DURATION
    
    self.flyingCard:SetScript("OnUpdate", function(frame, dt)
        elapsed = elapsed + dt
        local progress = math.min(elapsed / duration, 1)
        local eased = 1 - math.pow(1 - progress, 3)
        
        local currentX = startX + (endX - startX) * eased
        local currentY = startY + (endY - startY) * eased
        
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", self.mainFrame, "TOPLEFT", currentX, currentY)
        
        if progress >= 1 then
            frame:SetScript("OnUpdate", nil)
            if frame.spinGroup then frame.spinGroup:Stop() end
            frame:Hide()
            
            if onComplete then onComplete() end
        end
    end)
end

Poker.animQueue = {}
Poker.isAnimating = false

function Poker:QueueCardAnimation(playerName, cardData, faceUp, onComplete)
    table.insert(self.animQueue, {
        playerName = playerName,
        cardData = cardData,
        faceUp = faceUp,
        onComplete = onComplete,
    })
    
    if not self.isAnimating then
        self:ProcessAnimQueue()
    end
end

function Poker:ProcessAnimQueue()
    if #self.animQueue == 0 then
        self.isAnimating = false
        self.isDealingAnimation = false
        self:SetTrixieWait()
        return
    end
    
    self.isAnimating = true
    local anim = table.remove(self.animQueue, 1)
    
    self:SetTrixieDeal()
    
    self:AnimateCardToPlayer(anim.playerName, anim.cardData, anim.faceUp, function()
        -- Increment dealt cards count so the card shows
        self.dealtCards[anim.playerName] = (self.dealtCards[anim.playerName] or 0) + 1
        self:UpdatePlayerHands()
        self:UpdateInfoText()
        
        -- Call the external callback (to trigger next card deal from multiplayer)
        if anim.onComplete then 
            anim.onComplete() 
        end
        
        -- Always continue processing queue after a short delay
        C_Timer.After(0.1, function()
            self:ProcessAnimQueue()
        end)
    end)
end

function Poker:ClearAnimQueue()
    self.animQueue = {}
    self.isAnimating = false
    if self.flyingCard then
        self.flyingCard:SetScript("OnUpdate", nil)
        self.flyingCard:Hide()
    end
end

-- Event handlers
function Poker:OnTableOpened(hostName, settings)
    -- Ensure UI is initialized before updating
    if not self.isInitialized then
        return
    end
    self:SetTrixieWait()
    self.dealtCards = {}
    self:ClearAnimQueue()
    self:UpdateDisplay()
    if BJ.TestMode and BJ.TestMode.enabled then
        C_Timer.After(0.3, function() self:AnteTestPlayers() end)
    end
end

function Poker:OnTableClosed()
    -- Ensure UI is initialized before updating
    if not self.isInitialized then
        return
    end
    self:SetTrixieWait()
    self.testPlayers = {}
    self.dealtCards = {}
    self.isDealingAnimation = false
    self:ClearAnimQueue()
    self:UpdateDisplay()
end

function Poker:OnPlayerAnted(playerName, amount, skipSound)
    -- Ensure UI is initialized before updating
    if not self.isInitialized then
        return
    end
    -- Play ante sound (unless skipSound is true - used when we already played it locally)
    if not skipSound and BJ.UI and BJ.UI.Animation and BJ.UI.Animation.PlayAnteSound then
        BJ.UI.Animation:PlayAnteSound()
    end
    self:UpdateDisplay()
end

function Poker:OnDealStart()
    if not self.isInitialized then return end
    self:SetTrixieDeal()
    
    -- Initialize dealtCards to 0 for ALL players BEFORE any cards appear
    local PS = BJ.PokerState
    self.dealtCards = {}
    for _, playerName in ipairs(PS.playerOrder) do
        self.dealtCards[playerName] = 0
    end
    
    self.isDealingAnimation = true
    self:UpdateDisplay()
end

function Poker:OnCardDealt(playerName, card, cardIndex, faceUp, onComplete)
    if not self.isInitialized then 
        if onComplete then onComplete() end
        return 
    end
    self:QueueCardAnimation(playerName, card, faceUp, onComplete)
end

function Poker:OnDealComplete()
end

function Poker:OnBettingStart(street, firstPlayer)
    if not self.isInitialized then return end
    self.isDealingAnimation = false
    self:SetTrixieWait()
    self:UpdateDisplay()
end

function Poker:OnPlayerAction(playerName, action, amount)
    if not self.isInitialized then return end
    
    -- Full display update to ensure turn indicator and all state is current
    self:UpdateDisplay()
    
    -- Additional button refresh after a short delay to catch any timing issues
    C_Timer.After(0.1, function()
        if self.isInitialized then
            self:UpdateStatus()
            self:UpdateButtons()
        end
    end)
    
    -- Show large action text
    local actionStr = ""
    if action == "fold" then
        actionStr = playerName .. " FOLDS"
        self:SetTrixieCheer()
        C_Timer.After(1.5, function() self:SetTrixieWait() end)
    elseif action == "check" then
        actionStr = playerName .. " CHECKS"
    elseif action == "call" then
        actionStr = playerName .. " CALLS"
        if amount and amount > 0 then
            actionStr = actionStr .. " " .. amount .. "g"
        end
    elseif action == "raise" then
        actionStr = playerName .. " RAISES"
        if amount and amount > 0 then
            actionStr = actionStr .. " " .. amount .. "g"
        end
        self:SetTrixieDeal()
        C_Timer.After(1.0, function() self:SetTrixieWait() end)
    end
    
    if actionStr ~= "" then
        self:ShowActionText(actionStr)
    end
end

function Poker:ShowActionText(text)
    if not self.actionText then return end
    
    self.actionText:SetText(text)
    self.actionText:SetAlpha(1)
    self.actionTextFadeStart = GetTime()
    
    -- Hide settlement during action display
    if self.settlementFrame then
        self.settlementFrame:Hide()
    end
    
    -- Start fade timer if not already running
    if not self.actionFadeTimer then
        self.actionFadeTimer = C_Timer.NewTicker(0.05, function()
            local elapsed = GetTime() - self.actionTextFadeStart
            
            if elapsed < 4.0 then
                -- Stay fully visible for 4 seconds (doubled from 2)
                self.actionText:SetAlpha(1)
            elseif elapsed < 5.0 then
                -- Fade out over 1 second
                local fadeProgress = (elapsed - 4.0) / 1.0
                self.actionText:SetAlpha(1 - fadeProgress)
            else
                -- Fully faded
                self.actionText:SetAlpha(0)
                self.actionText:SetText("")
                if self.actionFadeTimer then
                    self.actionFadeTimer:Cancel()
                    self.actionFadeTimer = nil
                end
            end
        end)
    end
end

function Poker:OnShowdown()
    if not self.isInitialized then return end
    self:SetTrixieDeal()  -- Neutral during showdown
    local PS = BJ.PokerState
    for playerName, player in pairs(PS.players) do
        self.dealtCards[playerName] = #player.hand
    end
    self:UpdateDisplay()
end

function Poker:OnSettlement()
    if not self.isInitialized then return end
    local PS = BJ.PokerState
    local myName = UnitName("player")
    
    -- Check if local player won
    local iWon = false
    if PS.winners then
        for _, winner in ipairs(PS.winners) do
            if winner == myName then
                iWon = true
                break
            end
        end
    end
    
    if iWon then
        -- Local player won! Trixie cheers
        self:SetTrixieCheer()
        if UI.Lobby then 
            UI.Lobby:PlayWinSound()
            UI.Lobby:PlayTrixieWoohooVoice()
        end
    else
        -- Local player lost - Trixie is sad
        self:SetTrixieLose()
        if UI.Lobby then
            UI.Lobby:PlayTrixieBadVoice()
        end
    end
    
    self:UpdateDisplay()
end

function Poker:OnCountdownTick(remaining)
    if not self.isInitialized then return end
    if remaining > 0 then
        self.statusBar.text:SetText("Deal in " .. remaining .. "s... (" .. #BJ.PokerState.playerOrder .. " players)")
    end
end

--[[
    HOST RECOVERY UI HANDLERS
]]

-- Host recovery started - game is paused
function Poker:OnHostRecoveryStart(originalHost, tempHost)
    if not self.isInitialized then return end
    local myName = UnitName("player")
    
    -- Update status to show recovery mode
    if self.statusBar then
        self.statusBar.text:SetText("|cffff8800PAUSED - Waiting for " .. originalHost .. "|r")
    end
    
    -- Trixie looks concerned
    self:SetTrixieLose()
    
    -- Hide game buttons during recovery
    if self.foldBtn then self.foldBtn:Hide() end
    if self.checkBtn then self.checkBtn:Hide() end
    if self.callBtn then self.callBtn:Hide() end
    if self.raiseBtn then self.raiseBtn:Hide() end
    
    -- Show reset button only for temporary host
    if tempHost == myName then
        if self.resetBtn then
            self.resetBtn:Show()
        end
    else
        if self.resetBtn then
            self.resetBtn:Hide()
        end
    end
    
    self:UpdateDisplay()
end

-- Update recovery timer display
function Poker:UpdateRecoveryTimer(remaining)
    if not self.isInitialized then return end
    if self.statusBar then
        local mins = math.floor(remaining / 60)
        local secs = remaining % 60
        local timeStr = string.format("%d:%02d", mins, secs)
        local PM = BJ.PokerMultiplayer
        local host = PM.originalHost or "host"
        self.statusBar.text:SetText("|cffff8800PAUSED - " .. host .. " has " .. timeStr .. " to return|r")
    end
end

-- Host returned - game resumes
function Poker:OnHostRestored()
    if not self.isInitialized then return end
    
    -- Trixie is happy
    self:SetTrixieCheer()
    C_Timer.After(2.0, function()
        self:SetTrixieWait()
    end)
    
    -- Update display normally
    self:UpdateDisplay()
    self:UpdateButtons()
end

-- Game was voided due to timeout or manual reset
function Poker:OnGameVoided(reason)
    if not self.isInitialized then return end
    
    -- Show voided message
    if self.statusBar then
        self.statusBar.text:SetText("|cffff4444VOIDED: " .. (reason or "Game cancelled") .. "|r")
    end
    
    -- Trixie is sad
    self:SetTrixieLose()
    
    -- Clear display after delay
    C_Timer.After(3.0, function()
        self:UpdateDisplay()
        self:UpdateButtons()
    end)
end
