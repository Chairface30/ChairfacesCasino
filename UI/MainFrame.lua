--[[
    Chairface's Casino - UI/MainFrame.lua
    Main game window
]]

local BJ = ChairfacesCasino
BJ.UI = BJ.UI or {}
local UI = BJ.UI

UI.mainFrame = nil
UI.isInitialized = false
UI.dealtCards = {}  -- Track which cards have been animated/dealt
UI.dealerDealtCards = 0  -- Track how many dealer cards have been dealt
UI.isDealingAnimation = false  -- Track if initial deal animation is in progress

-- Trixie dimensions - all images are 274x350 (912x1165 scaled proportionally)
local TRIXIE_HEIGHT = 350
local TRIXIE_WIDTH = 274
local TRIXIE_LEFT_PADDING = 10  -- Space from window edge to Trixie left
local TRIXIE_RIGHT_PADDING = 10 -- Space from Trixie right to play area start

-- Play area configuration
local PLAY_AREA_WIDTH = 920
local TRIXIE_AREA_WIDTH = TRIXIE_LEFT_PADDING + TRIXIE_WIDTH + TRIXIE_RIGHT_PADDING  -- 294px

-- Frame dimensions (will be adjusted based on Trixie visibility)
local FRAME_WIDTH_WITH_TRIXIE = TRIXIE_AREA_WIDTH + PLAY_AREA_WIDTH  -- 1214px
local FRAME_WIDTH_NO_TRIXIE = PLAY_AREA_WIDTH + 20  -- 940px (just play area + padding)
local FRAME_HEIGHT = 540  -- Increased for divider line spacing

-- Current offset for play area elements (changes based on Trixie visibility)
local PLAY_AREA_OFFSET = TRIXIE_AREA_WIDTH  -- Default with Trixie
local FRAME_WIDTH = FRAME_WIDTH_WITH_TRIXIE

local FELT_COLOR = { 0.05, 0.3, 0.15, 0.95 }
local BORDER_COLOR = { 0.4, 0.25, 0.1, 1 }

local PLAYER_COLS = 5
local PLAYER_CELL_WIDTH = 165
local PLAYER_CELL_HEIGHT = 120

-- Check if Trixie should be shown
function UI:ShouldShowTrixie()
    if ChairfacesCasinoDB and ChairfacesCasinoDB.settings then
        return ChairfacesCasinoDB.settings.blackjackShowTrixie ~= false
    end
    return true  -- Default to showing
end

-- Update frame dimensions based on Trixie visibility
function UI:UpdateFrameDimensions()
    local showTrixie = self:ShouldShowTrixie()
    if showTrixie then
        PLAY_AREA_OFFSET = TRIXIE_AREA_WIDTH
        FRAME_WIDTH = FRAME_WIDTH_WITH_TRIXIE
    else
        PLAY_AREA_OFFSET = 10  -- Small left padding
        FRAME_WIDTH = FRAME_WIDTH_NO_TRIXIE
    end
end

function UI:Initialize()
    if self.isInitialized then return end
    
    -- Set frame dimensions based on Trixie visibility setting
    self:UpdateFrameDimensions()
    
    -- Initialize card back and deck from saved settings
    if UI.Cards and UI.Cards.InitializeCardBack then
        UI.Cards:InitializeCardBack()
    end
    if UI.Cards and UI.Cards.InitializeCardDeck then
        UI.Cards:InitializeCardDeck()
    end
    self:CreateMainFrame()
    self:CreateDealerArea()
    self:CreateActionButtons()  -- Create buttons BEFORE status bar (status bar anchors to buttons)
    self:CreateStatusBar()
    self:CreatePlayerArea()
    self:RepositionTrixie()  -- Position Trixie after player area exists
    self:CreateTestModeBar()
    self:CreateSettlementPanel()
    self:CreateLogPanel()
    self.isInitialized = true
end

function UI:CreateMainFrame()
    local frame = CreateFrame("Frame", "ChairfacesCasinoFrame", UIParent, "BackdropTemplate")
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
    -- Set texture coordinates to crop from center
    -- Texture is 1280x720, we show center portion based on frame size
    -- If window is larger than texture, we show full texture (stretched)
    local function UpdateFeltTexCoords()
        local texW, texH = 1280, 720
        local frameW, frameH = frame:GetWidth(), frame:GetHeight()
        -- Calculate what portion of texture to show (centered)
        -- If frame is larger than texture, show full texture
        local uSize = math.min(1, frameW / texW)
        local vSize = math.min(1, frameH / texH)
        local uOffset = (1 - uSize) / 2
        local vOffset = (1 - vSize) / 2
        bgTexture:SetTexCoord(uOffset, uOffset + uSize, vOffset, vOffset + vSize)
    end
    UpdateFeltTexCoords()
    frame.feltBg = bgTexture
    frame.UpdateFeltTexCoords = UpdateFeltTexCoords
    
    local titleBar = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    titleBar:SetSize(FRAME_WIDTH - 16, 28)
    titleBar:SetPoint("TOP", 0, -8)
    titleBar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
    titleBar:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
    titleBar:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    self.titleBar = titleBar  -- Store reference for resizing
    
    local titleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("CENTER")
    titleText:SetText("Chairface's Casino - Blackjack")
    titleText:SetTextColor(1, 0.84, 0, 1)
    self.titleText = titleText
    
    local closeBtn = CreateFrame("Button", nil, titleBar)
    closeBtn:SetSize(20, 20)
    closeBtn:SetPoint("RIGHT", -5, 0)
    closeBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    closeBtn:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
    closeBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
    closeBtn:SetScript("OnClick", function() UI:Hide() end)
    
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
        UI:Hide()
        C_Timer.After(0.05, function()
            UI:Show()
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
    
    -- Back button to return to casino lobby
    local backBtn = CreateFrame("Button", nil, titleBar, "BackdropTemplate")
    backBtn:SetSize(50, 18)
    backBtn:SetPoint("RIGHT", refreshBtn, "LEFT", -5, 0)
    backBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    backBtn:SetBackdropColor(0.15, 0.35, 0.15, 1)
    backBtn:SetBackdropBorderColor(0.3, 0.6, 0.3, 1)
    
    local backText = backBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    backText:SetPoint("CENTER")
    backText:SetText("|cffffffffBack|r")
    
    backBtn:SetScript("OnClick", function()
        UI:Hide()
        if UI.Lobby then
            UI.Lobby:Show()
        end
    end)
    backBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.2, 0.45, 0.2, 1) end)
    backBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.15, 0.35, 0.15, 1) end)
    
    local infoText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    infoText:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 10, -5)
    infoText:SetTextColor(0.8, 0.8, 0.8, 1)
    frame.infoText = infoText
    
    frame:Hide()
    self.mainFrame = frame
end

function UI:CreateDealerArea()
    local dealerArea = CreateFrame("Frame", nil, self.mainFrame)
    dealerArea:SetSize(300, 110)
    -- Center in the play area (right of Trixie)
    dealerArea:SetPoint("TOP", PLAY_AREA_OFFSET / 2, -53)
    
    local label = dealerArea:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOP", 0, 0)
    label:SetText("DEALER")
    label:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")  -- Same font/style as players, smaller size
    dealerArea.label = label
    
    local hand = UI.Cards:CreateHandDisplay(dealerArea, "DealerHandDisplay", true)
    hand:SetPoint("TOP", label, "BOTTOM", 0, -5)
    dealerArea.hand = hand
    
    -- Trixie dealer image - positioned on left side of window
    -- Use Button frame for click handling
    local trixieFrame = CreateFrame("Button", nil, self.mainFrame)
    trixieFrame:SetSize(TRIXIE_WIDTH, TRIXIE_HEIGHT)
    -- Position on left side, centered vertically
    -- Vertical center: (FRAME_HEIGHT - TRIXIE_HEIGHT) / 2 from top
    local verticalOffset = (FRAME_HEIGHT - TRIXIE_HEIGHT) / 2
    trixieFrame:SetPoint("TOPLEFT", self.mainFrame, "TOPLEFT", TRIXIE_LEFT_PADDING, -verticalOffset)
    
    -- Randomize initial wait image
    local initialWaitIdx = math.random(1, 31)
    local trixieTexture = trixieFrame:CreateTexture(nil, "ARTWORK")
    trixieTexture:SetAllPoints()
    trixieTexture:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\dealer\\trix_wait" .. initialWaitIdx)
    trixieFrame.texture = trixieTexture
    trixieFrame.currentState = "wait" .. initialWaitIdx
    trixieFrame.isWaiting = true  -- Track if in wait state cycle
    trixieFrame.lastDealState = nil  -- Track last deal image to avoid repeats
    trixieFrame.lastShufState = nil  -- Track last shuffle image to avoid repeats
    
    -- Easter egg click handler
    trixieFrame:SetScript("OnClick", function()
        if UI.Lobby and UI.Lobby.TryPlayPoke then
            UI.Lobby:TryPlayPoke()
        end
    end)
    
    -- Trixie state management
    trixieFrame.SetState = function(self, state)
        local imageName = "trix_" .. state
        local texturePath = "Interface\\AddOns\\Chairfaces Casino\\Textures\\dealer\\" .. imageName
        self.texture:SetTexture(texturePath)
        self.currentState = state
        self.currentImageName = imageName  -- Track actual image name
        -- Track if this is a wait state
        self.isWaiting = string.match(state, "^wait") ~= nil
        
        -- Update debug label if debug mode is active
        if BJ.TestMode and BJ.TestMode.enabled and BJ.TestMode.trixieDebugActive and self.debugLabel then
            self.debugLabel:SetText(imageName)
            self.debugLabel:Show()
        end
    end
    
    -- Random wait state for idle cycling (31 wait images, no repeats)
    trixieFrame.SetRandomWait = function(self)
        local idx
        repeat
            idx = math.random(1, 31)
        until ("wait" .. idx) ~= self.lastWaitState
        self.lastWaitState = "wait" .. idx
        self:SetState("wait" .. idx)
    end
    
    -- Random deal state (8 deal images, no repeats)
    trixieFrame.SetRandomDeal = function(self)
        local idx
        repeat
            idx = math.random(1, 8)
        until ("deal" .. idx) ~= self.lastDealState
        self.lastDealState = "deal" .. idx
        self:SetState("deal" .. idx)
    end
    
    -- Random shuffle state (12 shuffle images, no repeats)
    trixieFrame.SetRandomShuffle = function(self)
        local idx
        repeat
            idx = math.random(1, 12)
        until ("shuf" .. idx) ~= self.lastShufState
        self.lastShufState = "shuf" .. idx
        self:SetState("shuf" .. idx)
    end
    
    -- Random lose state (12 lose images, no repeats)
    trixieFrame.SetRandomLose = function(self)
        local idx
        repeat
            idx = math.random(1, 12)
        until ("lose" .. idx) ~= self.lastLoseState
        self.lastLoseState = "lose" .. idx
        self:SetState("lose" .. idx)
    end
    
    -- Random cheer/win state (9 win images, no repeats)
    trixieFrame.SetRandomCheer = function(self)
        local idx
        repeat
            idx = math.random(1, 9)
        until ("win" .. idx) ~= self.lastWinState
        self.lastWinState = "win" .. idx
        self:SetState("win" .. idx)
    end
    
    -- Random love state (10 love images, no repeats)
    trixieFrame.SetRandomLove = function(self)
        local idx
        repeat
            idx = math.random(1, 10)
        until ("love" .. idx) ~= self.lastLoveState
        self.lastLoveState = "love" .. idx
        self:SetState("love" .. idx)
    end
    
    -- Special: Chance to show love instead of win (10% chance on big wins)
    trixieFrame.SetRandomWinOrLove = function(self)
        if math.random(1, 10) == 1 then
            self:SetRandomLove()
        else
            self:SetRandomCheer()
        end
    end
    
    self.trixieFrame = trixieFrame
    
    -- Settlement scoreboard (right side, same Y as Trixie)
    local scoreboard = CreateFrame("Frame", nil, self.mainFrame, "BackdropTemplate")
    scoreboard:SetSize(150, 120)  -- Will resize dynamically
    scoreboard:SetPoint("TOPRIGHT", self.mainFrame, "TOPRIGHT", -15, -60)
    scoreboard:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    scoreboard:SetBackdropColor(0, 0, 0, 1)  -- Fully opaque
    scoreboard:SetBackdropBorderColor(0.5, 0.4, 0.2, 1)
    scoreboard:Hide()
    
    local scoreTitle = scoreboard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    scoreTitle:SetPoint("TOP", 0, -5)
    scoreTitle:SetText("|cffffd700Ledger|r")
    scoreboard.title = scoreTitle
    
    -- Divider line
    local divider = scoreboard:CreateTexture(nil, "ARTWORK")
    divider:SetSize(1, 80)
    divider:SetPoint("TOP", scoreTitle, "BOTTOM", 0, -5)
    divider:SetColorTexture(0.4, 0.4, 0.4, 0.6)
    scoreboard.divider = divider
    
    -- Left column: Players owe dealer (losses)
    local oweDealerLabel = scoreboard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    oweDealerLabel:SetPoint("TOPLEFT", 8, -22)
    oweDealerLabel:SetText("|cffff6666Owe Host|r")
    oweDealerLabel:SetJustifyH("LEFT")
    scoreboard.oweDealerLabel = oweDealerLabel
    
    local oweDealerContent = scoreboard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    oweDealerContent:SetPoint("TOPLEFT", 8, -36)
    oweDealerContent:SetWidth(65)
    oweDealerContent:SetJustifyH("LEFT")
    oweDealerContent:SetJustifyV("TOP")
    scoreboard.oweDealer = oweDealerContent
    
    -- Right column: Dealer owes players (wins)
    local dealerOwesLabel = scoreboard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dealerOwesLabel:SetPoint("TOPRIGHT", -8, -22)
    dealerOwesLabel:SetText("|cff66ff66Host Owes|r")
    dealerOwesLabel:SetJustifyH("RIGHT")
    scoreboard.dealerOwesLabel = dealerOwesLabel
    
    local dealerOwesContent = scoreboard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dealerOwesContent:SetPoint("TOPRIGHT", -8, -36)
    dealerOwesContent:SetWidth(65)
    dealerOwesContent:SetJustifyH("RIGHT")
    dealerOwesContent:SetJustifyV("TOP")
    scoreboard.dealerOwes = dealerOwesContent
    
    self.settlementScoreboard = scoreboard
    
    self.dealerArea = dealerArea
end

function UI:CreateStatusBar()
    local statusBar = CreateFrame("Frame", nil, self.mainFrame, "BackdropTemplate")
    statusBar:SetSize(PLAY_AREA_WIDTH - 100, 25)
    -- Position above button area, centered in play area
    statusBar:SetPoint("BOTTOM", self.buttonArea, "TOP", 0, 5)
    statusBar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    statusBar:SetBackdropColor(0, 0, 0, 0.6)
    statusBar:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)
    
    local text = statusBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("CENTER")
    text:SetTextColor(1, 0.84, 0, 1)
    statusBar.text = text
    
    -- Countdown timer - positioned in dealer area (for betting countdown)
    local countdown = CreateFrame("Frame", nil, self.mainFrame, "BackdropTemplate")
    countdown:SetSize(120, 40)
    countdown:SetPoint("CENTER", self.dealerArea, "CENTER", 0, -15)  -- Center in dealer area
    countdown:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
    countdown:SetBackdropColor(0.6, 0.2, 0.2, 0.9)
    countdown:SetBackdropBorderColor(1, 0.3, 0.3, 1)
    countdown:SetFrameLevel(self.mainFrame:GetFrameLevel() + 10)  -- Above cards
    countdown.text = countdown:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    countdown.text:SetPoint("CENTER")
    countdown.text:SetFont("Fonts\\FRIZQT__.TTF", 20, "OUTLINE")
    countdown:Hide()
    
    -- Turn timer frame - positioned in player area (for turn timeout)
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
    turnTimer.warning:SetText("|cffff8800Auto-stand soon!|r")
    turnTimer.warning:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    turnTimer:Hide()
    
    self.statusBar = statusBar
    self.countdownFrame = countdown
    self.turnTimerFrame = turnTimer
end

function UI:RepositionTrixie()
    -- Trixie is positioned on the left side of the window, bottom-anchored like Poker
    if self.trixieFrame and self.mainFrame then
        local showTrixie = self:ShouldShowTrixie()
        self.trixieFrame:ClearAllPoints()
        if showTrixie then
            -- Match Poker positioning: bottom-anchored above status bar
            -- Button area is at BOTTOM +15, buttons are 32px tall
            -- Status bar is 5px above buttons, 25px tall
            -- Trixie bottom offset = 15 + 32 + 5 + 25 + 13 = 90px, rounded to 95
            local TRIXIE_BOTTOM_OFFSET = 95
            self.trixieFrame:SetPoint("BOTTOMLEFT", self.mainFrame, "BOTTOMLEFT", TRIXIE_LEFT_PADDING, TRIXIE_BOTTOM_OFFSET)
            self.trixieFrame:Show()
        else
            self.trixieFrame:Hide()
        end
    end
end

-- Toggle Trixie visibility and resize window
function UI:SetTrixieVisibility(show)
    if not ChairfacesCasinoDB then ChairfacesCasinoDB = { settings = {} } end
    if not ChairfacesCasinoDB.settings then ChairfacesCasinoDB.settings = {} end
    ChairfacesCasinoDB.settings.blackjackShowTrixie = show
    
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
    
    -- Reposition Trixie
    self:RepositionTrixie()
    
    -- Reposition all play area elements
    self:RepositionPlayAreaElements()
end

-- Reposition all elements that depend on PLAY_AREA_OFFSET
function UI:RepositionPlayAreaElements()
    -- Dealer area - center in play area
    if self.dealerArea then
        self.dealerArea:ClearAllPoints()
        self.dealerArea:SetPoint("TOP", self.mainFrame, "TOP", PLAY_AREA_OFFSET / 2, -53)
    end
    
    -- Status bar width and position - center in play area
    if self.statusBar then
        self.statusBar:SetWidth(PLAY_AREA_WIDTH - 100)
        self.statusBar:ClearAllPoints()
        self.statusBar:SetPoint("BOTTOM", self.buttonArea, "TOP", 0, 5)
    end
    
    -- Player area clip frame
    if self.playerArea and self.playerArea.clipFrame then
        self.playerArea.clipFrame:ClearAllPoints()
        self.playerArea.clipFrame:SetPoint("BOTTOM", self.statusBar, "TOP", 0, 8)
    end
    
    -- Button area - center in play area (no test mode offset needed, test bar is outside window)
    if self.buttonArea then
        self.buttonArea:ClearAllPoints()
        self.buttonArea:SetPoint("BOTTOM", self.mainFrame, "BOTTOM", PLAY_AREA_OFFSET / 2, 15)
    end
    
    -- Test bar - resize to match current window width
    if self.testModeBar then
        self.testModeBar:SetSize(FRAME_WIDTH - 20, 35)
    end
    
    -- Reposition Trixie
    self:RepositionTrixie()
    
    -- Resize title bar to match frame width
    if self.titleBar then
        self.titleBar:SetWidth(FRAME_WIDTH - 16)
    end
    
    -- Update display
    self:UpdateDisplay()
end

function UI:CreatePlayerArea()
    -- Row height includes space for name above and score/bet/result below
    -- Add extra padding for cleaner row separation
    local ROW_HEIGHT = PLAYER_CELL_HEIGHT + 100
    local visibleHeight = ROW_HEIGHT + 15  -- Extra height to avoid cropping settlement text
    
    -- Create a clipping frame that masks content outside its bounds
    local clipFrame = CreateFrame("Frame", nil, self.mainFrame)
    clipFrame:SetSize(PLAY_AREA_WIDTH - 50, visibleHeight)
    -- Anchor to bottom, above status bar (like Poker)
    clipFrame:SetPoint("BOTTOM", self.statusBar, "TOP", 0, 8)
    clipFrame:SetClipsChildren(true)  -- This is the key - clips anything outside bounds
    
    -- Content frame that holds all players (will be taller than clip frame)
    local content = CreateFrame("Frame", nil, clipFrame)
    content:SetSize(PLAY_AREA_WIDTH - 60, ROW_HEIGHT)
    content:SetPoint("TOP", clipFrame, "TOP", 0, 0)  -- Starts at top, we'll move it for scrolling
    
    -- Simple row indicator on the right (no buttons, just display)
    local rowIndicatorFrame = CreateFrame("Frame", nil, self.mainFrame, "BackdropTemplate")
    rowIndicatorFrame:SetSize(45, 24)
    rowIndicatorFrame:SetPoint("RIGHT", self.mainFrame, "RIGHT", -8, -30)
    rowIndicatorFrame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    rowIndicatorFrame:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
    rowIndicatorFrame:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    
    local rowIndicator = rowIndicatorFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    rowIndicator:SetPoint("CENTER", rowIndicatorFrame, "CENTER", 0, 0)
    rowIndicator:SetText("1/1")
    
    -- Create playerArea table to hold all state
    local playerArea = {}
    playerArea.clipFrame = clipFrame
    playerArea.content = content
    playerArea.rowContainer = content  -- For compatibility
    playerArea.currentRow = 1
    playerArea.totalRows = 1
    playerArea.rowIndicator = rowIndicator
    playerArea.rowIndicatorFrame = rowIndicatorFrame
    playerArea.hands = {}
    playerArea.ROW_HEIGHT = ROW_HEIGHT
    
    -- Scroll function - moves content frame up/down within clip frame
    local function scrollToRow(targetRow)
        targetRow = math.max(1, math.min(targetRow, playerArea.totalRows))
        local yOffset = (targetRow - 1) * ROW_HEIGHT
        content:ClearAllPoints()
        content:SetPoint("TOP", clipFrame, "TOP", 0, yOffset)
        playerArea.currentRow = targetRow
        rowIndicator:SetText(targetRow .. "/" .. math.max(1, playerArea.totalRows))
    end
    
    local function updateRowDisplay()
        rowIndicator:SetText(playerArea.currentRow .. "/" .. math.max(1, playerArea.totalRows))
        -- Show indicator if more than 1 row
        if playerArea.totalRows > 1 then
            rowIndicatorFrame:Show()
        else
            rowIndicatorFrame:Hide()
        end
        scrollToRow(playerArea.currentRow)
    end
    
    -- Mouse wheel scrolling on clip frame
    clipFrame:EnableMouseWheel(true)
    clipFrame:SetScript("OnMouseWheel", function(self, delta)
        if delta > 0 then
            if playerArea.currentRow > 1 then
                playerArea.currentRow = playerArea.currentRow - 1
                scrollToRow(playerArea.currentRow)
            end
        else
            if playerArea.currentRow < playerArea.totalRows then
                playerArea.currentRow = playerArea.currentRow + 1
                scrollToRow(playerArea.currentRow)
            end
        end
    end)
    
    playerArea.updateRowDisplay = updateRowDisplay
    playerArea.scrollToRow = scrollToRow
    
    -- Initially hide indicator (shown when multiple rows)
    rowIndicatorFrame:Hide()
    
    self.playerArea = playerArea
end

function UI:CreateTestModeBar()
    local testBar = CreateFrame("Frame", nil, self.mainFrame, "BackdropTemplate")
    testBar:SetSize(FRAME_WIDTH - 20, 35)  -- Single row
    -- Position BELOW the main window (like Poker)
    testBar:SetPoint("TOP", self.mainFrame, "BOTTOM", 0, -5)
    testBar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
    testBar:SetBackdropColor(0.15, 0.1, 0.2, 0.95)
    testBar:SetBackdropBorderColor(1, 0.4, 1, 1)
    
    local btnConfigs = {
        { text = "+PLAYER", cmd = "add", width = 65 },
        { text = "-PLAYER", cmd = "remove", width = 65 },
        { text = "DEAL", cmd = "deal", width = 50 },
        { text = "CLEAR", cmd = "clear", width = 55 },
        { text = "HIT", cmd = "hit", width = 40 },
        { text = "STAND", cmd = "stand", width = 55 },
        { text = "DBL", cmd = "double", width = 40 },
        { text = "SPLIT", cmd = "split", width = 50 },
        { text = "AUTO", cmd = "auto", width = 50 },
        { text = "TRIX", cmd = "trixtoggle", width = 45, green = true },
        { text = "<Trix", cmd = "trixprev", width = 40, pink = true },
        { text = "Trix>", cmd = "trixnext", width = 40, pink = true },
    }
    
    -- Calculate total width for centering
    local totalWidth = 0
    for _, cfg in ipairs(btnConfigs) do
        totalWidth = totalWidth + cfg.width + 5
    end
    local startX = -totalWidth / 2
    
    for _, cfg in ipairs(btnConfigs) do
        local btn = UI.Buttons:CreateGameButton(testBar, "Test" .. cfg.cmd, cfg.text, cfg.width)
        btn:SetPoint("LEFT", testBar, "CENTER", startX, 0)
        -- Override colors for test mode purple theme (pink for trix buttons, green for toggle)
        if cfg.pink then
            btn:SetBackdropColor(0.4, 0.2, 0.3, 1)
            btn:SetBackdropBorderColor(0.8, 0.4, 0.6, 1)
        elseif cfg.green then
            -- Green for visibility toggle
            local isOn = UI:ShouldShowTrixie()
            if isOn then
                btn:SetBackdropColor(0.2, 0.4, 0.2, 1)
                btn:SetBackdropBorderColor(0.4, 0.8, 0.4, 1)
            else
                btn:SetBackdropColor(0.3, 0.2, 0.2, 1)
                btn:SetBackdropBorderColor(0.6, 0.3, 0.3, 1)
            end
            testBar.trixToggleBtn = btn
        else
            btn:SetBackdropColor(0.3, 0.2, 0.4, 1)
            btn:SetBackdropBorderColor(0.6, 0.4, 0.8, 1)
        end
        
        local command = cfg.cmd
        local isPink = cfg.pink
        local isGreen = cfg.green
        btn:SetScript("OnClick", function()
            if BJ.TestMode then
                if command == "add" then BJ.TestMode:AddFakePlayer()
                elseif command == "remove" then BJ.TestMode:RemoveLastFakePlayer()
                elseif command == "deal" then BJ.TestMode:ForceDeal()
                elseif command == "clear" then BJ.TestMode:ClearFakePlayers()
                elseif command == "hit" then BJ.TestMode:ManualAction("hit")
                elseif command == "stand" then BJ.TestMode:ManualAction("stand")
                elseif command == "double" then BJ.TestMode:ManualAction("double")
                elseif command == "split" then BJ.TestMode:ManualAction("split")
                elseif command == "auto" then
                    BJ.TestMode:ToggleAutoPlay()
                    btn.text:SetText(BJ.TestMode.autoPlay and "AUTO*" or "AUTO")
                elseif command == "trixtoggle" then
                    local newState = not UI:ShouldShowTrixie()
                    UI:SetTrixieVisibility(newState)
                    -- Update button color
                    if newState then
                        btn:SetBackdropColor(0.2, 0.4, 0.2, 1)
                        btn:SetBackdropBorderColor(0.4, 0.8, 0.4, 1)
                    else
                        btn:SetBackdropColor(0.3, 0.2, 0.2, 1)
                        btn:SetBackdropBorderColor(0.6, 0.3, 0.3, 1)
                    end
                elseif command == "trixprev" then BJ.TestMode:PrevTrixieImage()
                elseif command == "trixnext" then BJ.TestMode:NextTrixieImage()
                end
                UI:UpdateDisplay()
            end
        end)
        if isPink then
            btn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.5, 0.3, 0.4, 1) end)
            btn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.4, 0.2, 0.3, 1) end)
        elseif isGreen then
            btn:SetScript("OnEnter", function(self)
                local isOn = UI:ShouldShowTrixie()
                if isOn then
                    self:SetBackdropColor(0.3, 0.5, 0.3, 1)
                else
                    self:SetBackdropColor(0.4, 0.3, 0.3, 1)
                end
            end)
            btn:SetScript("OnLeave", function(self)
                local isOn = UI:ShouldShowTrixie()
                if isOn then
                    self:SetBackdropColor(0.2, 0.4, 0.2, 1)
                else
                    self:SetBackdropColor(0.3, 0.2, 0.2, 1)
                end
            end)
        else
            btn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.4, 0.3, 0.5, 1) end)
            btn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.3, 0.2, 0.4, 1) end)
        end
        startX = startX + cfg.width + 5
    end
    
    testBar:Hide()
    self.testModeBar = testBar
end

function UI:CreateActionButtons()
    local buttonArea = CreateFrame("Frame", nil, self.mainFrame)
    buttonArea:SetSize(PLAY_AREA_WIDTH - 20, 50)
    -- Center in play area (offset by half of PLAY_AREA_OFFSET to the right)
    buttonArea:SetPoint("BOTTOM", PLAY_AREA_OFFSET / 2, 15)
    
    local buttons = {}
    local configs = {
        { name = "deal", text = "DEAL", width = 60 },
        { name = "hit", text = "HIT", width = 50 },
        { name = "stand", text = "STAND", width = 60 },
        { name = "double", text = "DBL", width = 45 },
        { name = "split", text = "SPLIT", width = 55 },
        { name = "auto", text = "AUTO", width = 50 },
        { name = "log", text = "LOG", width = 45 },
        { name = "reset", text = "RESET", width = 55 },
    }
    
    local totalWidth = 0
    for _, cfg in ipairs(configs) do
        totalWidth = totalWidth + cfg.width + 5
    end
    local startX = -totalWidth / 2
    
    for _, cfg in ipairs(configs) do
        local btn = UI.Buttons:CreateGameButton(buttonArea, cfg.name, cfg.text, cfg.width)
        btn:SetPoint("LEFT", buttonArea, "CENTER", startX, 0)
        buttons[cfg.name] = btn
        startX = startX + cfg.width + 5
    end
    
    buttons.deal:SetScript("OnClick", function() BJ.Multiplayer:Deal() end)
    buttons.hit:SetScript("OnClick", function() BJ.Multiplayer:Hit() end)
    buttons.stand:SetScript("OnClick", function() BJ.Multiplayer:Stand() end)
    buttons.double:SetScript("OnClick", function() BJ.Multiplayer:Double() end)
    buttons.split:SetScript("OnClick", function() BJ.Multiplayer:Split() end)
    buttons.auto:SetScript("OnClick", function() UI:ToggleAutoDealer() end)
    buttons.log:SetScript("OnClick", function() UI:ToggleLogPanel() end)
    buttons.reset:SetScript("OnClick", function() UI:OnResetClick() end)
    
    self.buttons = buttons
    self.buttonArea = buttonArea
    
    -- Create centered action button (Host/Join)
    self:CreateActionButton()
end

-- Create the centered Host/Join action button
function UI:CreateActionButton()
    local btn = CreateFrame("Button", "BlackjackActionButton", self.mainFrame, "BackdropTemplate")
    btn:SetSize(180, 54)  -- Triple normal size
    -- Center in dealer area (dealer area is at TOP, 0, -53 and is 110 tall)
    btn:SetPoint("CENTER", self.dealerArea, "CENTER", 0, -15)
    btn:SetFrameLevel(self.mainFrame:GetFrameLevel() + 100)  -- Above everything
    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 3,
    })
    btn:SetBackdropColor(0.15, 0.35, 0.15, 1)
    btn:SetBackdropBorderColor(0.3, 0.7, 0.3, 1)
    
    local btnText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    btnText:SetPoint("CENTER")
    btnText:SetFont("Fonts\\FRIZQT__.TTF", 24, "OUTLINE")  -- Triple font size
    btnText:SetText("HOST")
    btn.text = btnText
    
    btn:SetScript("OnEnter", function(self)
        if self:IsEnabled() then
            self:SetBackdropColor(0.2, 0.5, 0.2, 1)
            self:SetBackdropBorderColor(0.4, 1, 0.4, 1)
        end
    end)
    
    btn:SetScript("OnLeave", function(self)
        if self:IsEnabled() then
            self:SetBackdropColor(0.15, 0.35, 0.15, 1)
            self:SetBackdropBorderColor(0.3, 0.7, 0.3, 1)
        end
    end)
    
    btn:SetScript("OnClick", function()
        UI:OnActionButtonClick()
    end)
    
    self.actionButton = btn
end

-- Handle action button click (context-dependent)
function UI:OnActionButtonClick()
    local GS = BJ.GameState
    local MP = BJ.Multiplayer
    local myName = UnitName("player")
    local isCurrentHost = MP.currentHost == myName
    local inTestMode = BJ.TestMode and BJ.TestMode.enabled
    local inPartyOrRaid = IsInGroup() or IsInRaid()
    local canHost = inTestMode or inPartyOrRaid
    
    -- Check if in recovery mode - temporary host can void the game
    if MP:IsInRecoveryMode() and MP.temporaryHost == myName then
        -- Confirm void
        StaticPopupDialogs["CASINO_VOID_GAME"] = {
            text = "Void the current game?\n\nThis will reset the game for all players.\nNo gold changes hands.",
            button1 = "Void Game",
            button2 = "Wait",
            OnAccept = function()
                MP:VoidGame("Voided by temporary host")
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
        StaticPopup_Show("CASINO_VOID_GAME")
        return
    end
    
    -- Legacy: Anyone can reset when host disconnected (old behavior fallback)
    if MP.hostDisconnected and not MP:IsInRecoveryMode() then
        BJ.SessionManager:ForceReset()
        MP:ResetState()
        if BJ.UI.OnTableClosed then
            BJ.UI:OnTableClosed()
        end
        return
    end
    
    -- Settlement phase - anyone can host a new game
    if GS.phase == GS.PHASE.SETTLEMENT and canHost then
        self:OnHostClick()
        self.actionButton:Hide()
        return
    end
    
    -- Idle phase - host or anyone if no table open
    if GS.phase == GS.PHASE.IDLE then
        if (isCurrentHost or MP.isHost) or (not MP.tableOpen and canHost) then
            self:OnHostClick()
            self.actionButton:Hide()
            return
        end
    end
    
    if not MP.tableOpen and not MP.isHost then
        -- No table open - this is a HOST action
        self:OnHostClick()
        self.actionButton:Hide()
    elseif MP.tableOpen and GS.phase == GS.PHASE.WAITING_FOR_PLAYERS then
        -- Table open, waiting for players - this is a JOIN/ANTE action
        self:OnAnteClick()
        self.actionButton:Hide()
    end
end

-- Update action button visibility and text
function UI:UpdateActionButton()
    if not self.actionButton then return end
    
    local GS = BJ.GameState
    local MP = BJ.Multiplayer
    local myName = UnitName("player")
    local inTestMode = BJ.TestMode and BJ.TestMode.enabled
    local inPartyOrRaid = IsInGroup() or IsInRaid()
    local canHost = inTestMode or inPartyOrRaid
    
    -- If host disconnected, show RESET for everyone
    if MP.hostDisconnected then
        self.actionButton.text:SetText("RESET")
        self.actionButton:Show()
        self.actionButton:Enable()
        return
    end
    
    -- Hide during active game (dealing, player turn, dealer turn)
    if GS.phase == GS.PHASE.DEALING or 
       GS.phase == GS.PHASE.PLAYER_TURN or 
       GS.phase == GS.PHASE.DEALER_TURN then
        self.actionButton:Hide()
        return
    end
    
    -- Check if player already anted
    local alreadyAnted = GS.players and GS.players[myName] ~= nil
    local isCurrentHost = MP.currentHost == myName
    
    -- During settlement, anyone can host a new game
    if GS.phase == GS.PHASE.SETTLEMENT then
        if canHost then
            self.actionButton.text:SetText("HOST")
            self.actionButton:Show()
            self.actionButton:Enable()
            return
        else
            self.actionButton:Hide()
            return
        end
    end
    
    -- During idle, check if table is open or not
    if GS.phase == GS.PHASE.IDLE then
        if isCurrentHost or MP.isHost then
            -- Host can start new hand
            self.actionButton.text:SetText("HOST")
            self.actionButton:Show()
            self.actionButton:Enable()
            return
        elseif not MP.tableOpen and canHost then
            -- No table open - anyone can host
            self.actionButton.text:SetText("HOST")
            self.actionButton:Show()
            self.actionButton:Enable()
            return
        else
            self.actionButton:Hide()
            return
        end
    end
    
    if not MP.tableOpen and not MP.isHost then
        -- No table open - show HOST button
        if canHost then
            self.actionButton.text:SetText("HOST")
            self.actionButton:Show()
            self.actionButton:Enable()
        else
            self.actionButton:Hide()
        end
    elseif MP.tableOpen and GS.phase == GS.PHASE.WAITING_FOR_PLAYERS then
        -- Table open - show JOIN button (unless already joined or is host)
        if not isCurrentHost and not alreadyAnted then
            self.actionButton.text:SetText("JOIN")
            self.actionButton:Show()
            self.actionButton:Enable()
        else
            self.actionButton:Hide()
        end
    else
        self.actionButton:Hide()
    end
end

function UI:CreateSettlementPanel()
    local panel = CreateFrame("Frame", nil, self.mainFrame, "BackdropTemplate")
    panel:SetSize(525, 375)  -- 350*1.5, 250*1.5
    panel:SetPoint("TOPRIGHT", self.mainFrame, "TOPRIGHT", -10, -10)  -- Top-right with padding
    panel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 3, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    panel:SetBackdropColor(0.1, 0.1, 0.1, 1)  -- Fully opaque
    panel:SetBackdropBorderColor(1, 0.84, 0, 1)
    panel:SetFrameLevel(self.mainFrame:GetFrameLevel() + 10)
    
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -15)
    title:SetText("Settlement")
    title:SetTextColor(1, 0.84, 0, 1)
    title:SetFont("Fonts\\FRIZQT__.TTF", 18)
    
    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetSize(465, 270)  -- 310*1.5, 180*1.5
    scrollFrame:SetPoint("TOP", title, "BOTTOM", -10, -15)
    
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(450, 600)
    scrollFrame:SetScrollChild(content)
    
    local text = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("TOPLEFT", 8, -8)  -- 5*1.5 ≈ 8
    text:SetWidth(435)
    text:SetJustifyH("LEFT")
    text:SetSpacing(4)  -- 2-3 * 1.5 ≈ 4
    text:SetFont("Fonts\\FRIZQT__.TTF", 14)  -- ~9*1.5 ≈ 14
    panel.text = text
    
    local closeBtn = CreateFrame("Button", nil, panel, "BackdropTemplate")
    closeBtn:SetSize(150, 45)  -- 100*1.5, 30*1.5
    closeBtn:SetPoint("BOTTOM", 0, 15)
    closeBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
    closeBtn:SetBackdropColor(0.2, 0.5, 0.2, 1)
    closeBtn.text = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    closeBtn.text:SetPoint("CENTER")
    closeBtn.text:SetText("CLOSE")
    closeBtn.text:SetFont("Fonts\\FRIZQT__.TTF", 15)  -- ~10*1.5
    closeBtn:SetScript("OnClick", function() panel:Hide() end)
    
    panel:Hide()
    self.settlementPanel = panel
end

function UI:CreateLogPanel()
    local panel = CreateFrame("Frame", "ChairfacesCasinoLogPanel", UIParent, "BackdropTemplate")
    panel:SetSize(320, 350)
    panel:SetPoint("LEFT", self.mainFrame, "RIGHT", 10, 0)
    panel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    panel:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
    panel:SetBackdropBorderColor(0.4, 0.3, 0.1, 1)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetClampedToScreen(true)
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    panel:SetFrameStrata("DIALOG")
    panel:Hide()
    
    -- Title bar
    local titleBar = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    titleBar:SetSize(320, 24)
    titleBar:SetPoint("TOP", 0, 0)
    titleBar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    titleBar:SetBackdropColor(0.15, 0.12, 0.05, 1)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() panel:StartMoving() end)
    titleBar:SetScript("OnDragStop", function() panel:StopMovingOrSizing() end)
    
    local titleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("CENTER")
    titleText:SetText("|cffffd700Blackjack - Game Log|r")
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, titleBar)
    closeBtn:SetSize(18, 18)
    closeBtn:SetPoint("RIGHT", -3, 0)
    closeBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    closeBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
    closeBtn:SetScript("OnClick", function() panel:Hide() end)
    
    -- Scroll frame for log content
    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
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
    
    panel.scrollContent = scrollContent
    panel.text = logText
    
    self.logPanel = panel
end

function UI:ToggleLogPanel()
    if self.logPanel:IsShown() then
        self.logPanel:Hide()
    else
        self:UpdateLogPanel()
        self.logPanel:Show()
    end
end

function UI:UpdateLogPanel()
    local GS = BJ.GameState
    local logText = "No game history yet."
    if GS.GetGameLogText then
        logText = GS:GetGameLogText()
    end
    self.logPanel.text:SetText(logText)
    
    -- Resize scroll content to fit text
    local textHeight = self.logPanel.text:GetStringHeight()
    self.logPanel.scrollContent:SetHeight(math.max(300, textHeight + 20))
end

function UI:Show()
    if not self.isInitialized then
        self:Initialize()
    end
    
    -- Hide other game windows
    if UI.HiLo and UI.HiLo.container and UI.HiLo.container:IsShown() then
        UI.HiLo:Hide()
    end
    if UI.Poker and UI.Poker.mainFrame and UI.Poker.mainFrame:IsShown() then
        UI.Poker:Hide()
    end
    if UI.Lobby and UI.Lobby.frame and UI.Lobby.frame:IsShown() then
        UI.Lobby.frame:Hide()
    end
    
    -- Initialize audio system if not already done
    local Lobby = UI.Lobby
    if Lobby and not Lobby.audioInitialized then
        Lobby:InitializeAudio()
        Lobby.audioInitialized = true
    end
    
    -- Apply saved window scale
    if Lobby and Lobby.ApplyWindowScale then
        Lobby:ApplyWindowScale()
    end
    
    self.mainFrame:Show()
    self:UpdateDisplay()
    
    -- Refresh Trixie debug if active
    if BJ.TestMode and BJ.TestMode.RefreshTrixieDebug then
        BJ.TestMode:RefreshTrixieDebug()
    end
end

function UI:Hide()
    if self.mainFrame then
        self.mainFrame:Hide()
    end
    -- Also hide log panel
    if self.logPanel then
        self.logPanel:Hide()
    end
end

function UI:Toggle()
    if self.mainFrame and self.mainFrame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

-- Helper to build info text consistently (with seed)
function UI:BuildInfoText(shufflingText)
    local GS = BJ.GameState
    local infoText = ""
    if GS.hostName then
        local multiplier = GS.maxMultiplier or 1
        local ruleText = GS.dealerHitsSoft17 and "H17" or "S17"
        infoText = "Host: " .. GS.hostName .. " | Ante: " .. GS.ante .. "g with " .. multiplier .. "x multiplier | " .. ruleText
        
        -- Show shuffling text or card count
        if shufflingText then
            infoText = infoText .. " | " .. shufflingText
        elseif self.displayedCardCount and self.displayedCardCount > 0 then
            infoText = infoText .. " | Remaining Cards: " .. self.displayedCardCount
        elseif #GS.shoe > 0 then
            infoText = infoText .. " | Remaining Cards: " .. GS:GetRemainingCards()
        elseif GS.syncedCardsRemaining then
            infoText = infoText .. " | Remaining Cards: " .. GS.syncedCardsRemaining
        end
        
        -- Always add seed for transparency
        if GS.seed then
            infoText = infoText .. " | Seed: " .. GS.seed
        end
    end
    return infoText
end

function UI:UpdateDisplay()
    local GS = BJ.GameState
    self:UpdateTitleBar()
    self:UpdateTestModeBar()
    
    self.mainFrame.infoText:SetText(self:BuildInfoText())
    
    self:UpdateStatus()
    self:UpdateDealerDisplay()
    self:UpdatePlayerHands()
    self:UpdateButtons()
end

function UI:UpdateDealerDisplay()
    local GS = BJ.GameState
    
    -- Only show cards that have been dealt (animated)
    local numDealt = self.dealerDealtCards or 0
    local dealtDealerCards = {}
    for i = 1, math.min(numDealt, #GS.dealerHand) do
        table.insert(dealtDealerCards, GS.dealerHand[i])
    end
    
    if #dealtDealerCards > 0 then
        -- Host sees hole card face up, players see it face down until revealed
        local isHost = BJ.Multiplayer.isHost
        local hideHole = not isHost and not GS.dealerHoleCardRevealed and #dealtDealerCards >= 2
        UI.Cards:UpdateHandDisplay(self.dealerArea.hand, dealtDealerCards, hideHole)
        
        local scoreText
        -- Host always sees full score, players only see it when revealed
        if (isHost or GS.dealerHoleCardRevealed) and #dealtDealerCards >= 2 then
            local score = GS:ScoreHand(dealtDealerCards)
            if score.isBust then
                scoreText = score.total .. " BUST"
            else
                scoreText = tostring(score.total)
            end
        elseif #dealtDealerCards >= 1 then
            local upCard = dealtDealerCards[1]
            local upValue = GS:CardValue(upCard)
            if upCard.rank == "A" then
                -- Ace showing - potential blackjack!
                scoreText = "|cffffd700!? Blackjack ?!|r"
            else
                scoreText = upValue .. " + ?"
            end
        else
            scoreText = ""
        end
        self.dealerArea.hand.scoreLabel:SetText(scoreText)
        self.dealerArea.hand.scoreLabel:Show()
    else
        UI.Cards:UpdateHandDisplay(self.dealerArea.hand, {})
        self.dealerArea.hand.scoreLabel:Hide()
    end
end

-- Trixie dealer image state management
function UI:SetTrixieState(state)
    if not self.trixieFrame then return end
    self.trixieFrame:SetState(state)
end

-- Get random Trixie state from a list
function UI:SetTrixieRandomState(states)
    if not states or #states == 0 then return end
    local idx = math.random(1, #states)
    self:SetTrixieState(states[idx])
end

-- Set Trixie to a random wait pose
function UI:SetTrixieWait()
    if not self.trixieFrame then return end
    self.trixieFrame:SetRandomWait()
end

-- Set Trixie to a random deal pose (no repeats)
function UI:SetTrixieDeal()
    if not self.trixieFrame then return end
    self.trixieFrame:SetRandomDeal()
end

-- Set Trixie to a random shuffle pose (no repeats)
function UI:SetTrixieShuffle()
    if not self.trixieFrame then return end
    self.trixieFrame:SetRandomShuffle()
end

-- Set Trixie to a random cheer pose
function UI:SetTrixieCheer()
    if not self.trixieFrame then return end
    self.trixieFrame:SetRandomCheer()
end

-- Set Trixie to a random lose pose (dealer wins)
function UI:SetTrixieLose()
    if not self.trixieFrame then return end
    self.trixieFrame:SetRandomLose()
end

-- Set Trixie to a random love pose (rare special)
function UI:SetTrixieLove()
    if not self.trixieFrame then return end
    self.trixieFrame:SetRandomLove()
end

-- Update settlement scoreboard
function UI:UpdateSettlementScoreboard(settlements)
    if not self.settlementScoreboard then return end
    
    if not settlements then
        self.settlementScoreboard:Hide()
        return
    end
    
    local oweDealerList = {}   -- Players who lost (owe dealer)
    local dealerOwesList = {}  -- Players who won (dealer owes them)
    local maxNameLen = 0
    local maxAmountLen = 0
    
    -- First pass: collect entries and calculate max lengths
    for playerName, data in pairs(settlements) do
        local total = data.total or 0
        if total ~= 0 then
            local nameLen = string.len(playerName)
            if nameLen > 12 then nameLen = 12 end  -- Cap at 12 chars
            if nameLen > maxNameLen then maxNameLen = nameLen end
            
            local amountStr = tostring(math.abs(total)) .. "g"
            if string.len(amountStr) > maxAmountLen then maxAmountLen = string.len(amountStr) end
            
            if total < 0 then
                table.insert(oweDealerList, { name = playerName, amount = math.abs(total) })
            else
                table.insert(dealerOwesList, { name = playerName, amount = total })
            end
        end
    end
    
    -- Sort both lists by amount descending (most gold at top)
    table.sort(oweDealerList, function(a, b) return a.amount > b.amount end)
    table.sort(dealerOwesList, function(a, b) return a.amount > b.amount end)
    
    -- Build text from sorted lists
    local oweDealerText = ""
    for _, entry in ipairs(oweDealerList) do
        local shortName = string.sub(entry.name, 1, 12)
        oweDealerText = oweDealerText .. shortName .. " " .. entry.amount .. "g\n"
    end
    
    local dealerOwesText = ""
    for _, entry in ipairs(dealerOwesList) do
        local shortName = string.sub(entry.name, 1, 12)
        dealerOwesText = dealerOwesText .. shortName .. " " .. entry.amount .. "g\n"
    end
    
    local oweDealerCount = #oweDealerList
    local dealerOwesCount = #dealerOwesList
    
    if oweDealerCount == 0 and dealerOwesCount == 0 then
        self.settlementScoreboard:Hide()
        return
    end
    
    -- Update column headers with host name
    local GS = BJ.GameState
    local hostName = GS.hostName or "Host"
    local shortHostName = string.sub(hostName, 1, 10)
    
    -- Determine if local player is the host (flip colors if so)
    local isHost = BJ.Multiplayer and BJ.Multiplayer.isHost
    
    if isHost then
        -- Host perspective: players owing = good (green), host owing = bad (red)
        self.settlementScoreboard.oweDealerLabel:SetText("|cff66ff66Owe " .. shortHostName .. "|r")
        self.settlementScoreboard.dealerOwesLabel:SetText("|cffff6666" .. shortHostName .. " Owes|r")
    else
        -- Player perspective: players owing = bad (red), host owing = good (green)
        self.settlementScoreboard.oweDealerLabel:SetText("|cffff6666Owe " .. shortHostName .. "|r")
        self.settlementScoreboard.dealerOwesLabel:SetText("|cff66ff66" .. shortHostName .. " Owes|r")
    end
    
    self.settlementScoreboard.oweDealer:SetText(oweDealerText)
    self.settlementScoreboard.dealerOwes:SetText(dealerOwesText)
    
    -- Calculate width: ~7 pixels per character + padding
    -- Each column needs: name + space + amount
    local charWidth = 7
    local columnWidth = (maxNameLen + 1 + maxAmountLen) * charWidth + 10  -- +10 padding
    if columnWidth < 70 then columnWidth = 70 end  -- Minimum column width
    
    local totalWidth = (columnWidth * 2) + 20  -- Two columns + divider + padding
    if totalWidth < 160 then totalWidth = 160 end  -- Minimum total width
    
    -- Update column widths
    self.settlementScoreboard.oweDealer:SetWidth(columnWidth)
    self.settlementScoreboard.dealerOwes:SetWidth(columnWidth)
    
    -- Dynamically resize based on content
    local maxEntries = math.max(oweDealerCount, dealerOwesCount)
    local lineHeight = 12
    local baseHeight = 45  -- Title + labels
    local contentHeight = maxEntries * lineHeight
    local totalHeight = baseHeight + contentHeight + 10  -- padding
    
    if totalHeight < 70 then totalHeight = 70 end
    
    self.settlementScoreboard:SetSize(totalWidth, totalHeight)
    self.settlementScoreboard.divider:SetHeight(contentHeight + 15)
    
    self.settlementScoreboard:Show()
end

function UI:UpdateTitleBar()
    if not self.titleText then return end
    local inTestMode = BJ.TestMode and BJ.TestMode.enabled
    local gameName = "Blackjack"  -- Current game
    
    if inTestMode then
        self.titleText:SetText("Chairface's Casino - " .. gameName .. " |cffff00ff[DEBUG]|r")
    else
        self.titleText:SetText("Chairface's Casino - " .. gameName)
    end
end

function UI:UpdateTestModeBar()
    if not self.testModeBar then return end
    local inTestMode = BJ.TestMode and BJ.TestMode.enabled
    if inTestMode then
        self.testModeBar:Show()
    else
        self.testModeBar:Hide()
    end
    -- Update layout based on test mode
    self:UpdateTestModeLayout()
end

-- Show/hide test bar when test mode is toggled (bar is outside window, no resize needed)
function UI:UpdateTestModeLayout()
    if not self.mainFrame then return end
    
    local inTestMode = BJ.TestMode and BJ.TestMode.enabled
    
    -- Window size does NOT change - test bar is outside/below
    self.mainFrame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    
    -- Button area stays at fixed position (centered in play area)
    if self.buttonArea then
        self.buttonArea:ClearAllPoints()
        self.buttonArea:SetPoint("BOTTOM", self.mainFrame, "BOTTOM", PLAY_AREA_OFFSET / 2, 15)
    end
    
    -- Test bar is positioned below the window - resize to match current window width
    if self.testModeBar then
        self.testModeBar:SetSize(FRAME_WIDTH - 20, 35)
        self.testModeBar:ClearAllPoints()
        self.testModeBar:SetPoint("TOP", self.mainFrame, "BOTTOM", 0, -5)
        
        if inTestMode then
            self.testModeBar:Show()
        else
            self.testModeBar:Hide()
        end
    end
    
    -- Player area clip frame position
    if self.playerArea and self.playerArea.clipFrame then
        self.playerArea.clipFrame:ClearAllPoints()
        self.playerArea.clipFrame:SetPoint("BOTTOM", self.statusBar, "TOP", 0, 8)
    end
    
    -- Update title to show game name
    if self.titleText then
        self.titleText:SetText("Chairface's Casino - Blackjack")
    end
end

function UI:UpdateStatus()
    local GS = BJ.GameState
    local status = ""
    local inTestMode = BJ.TestMode and BJ.TestMode.enabled
    local inPartyOrRaid = IsInGroup() or IsInRaid()
    
    -- Check for voided game first
    if GS.gameVoided then
        status = "|cffff4444GAME VOIDED|r - Player disconnected. Host can RESET."
    elseif GS.phase == GS.PHASE.IDLE then
        -- Show party/raid warning if not in group and not in test mode
        if not inPartyOrRaid and not inTestMode then
            status = "|cffff8800Join a party or raid to host a game.|r"
        else
            status = "No active table. Click HOST to start a game."
        end
    elseif GS.phase == GS.PHASE.WAITING_FOR_PLAYERS then
        status = "Waiting for players... (" .. #GS.playerOrder .. " anted)"
    elseif GS.phase == GS.PHASE.PLAYER_TURN then
        local cp = GS:GetCurrentPlayer()
        if cp == UnitName("player") then
            status = "Your turn! Choose an action."
        elseif cp then
            status = "Waiting for " .. cp .. "..."
        else
            -- No current player means all players done, waiting for dealer
            status = "Dealer's turn..."
        end
    elseif GS.phase == GS.PHASE.DEALER_TURN then
        local score = GS:ScoreHand(GS.dealerHand)
        local ruleText = GS.dealerHitsSoft17 and "H17" or "S17"
        if GS:DealerNeedsAction() then
            if BJ.autoDealer then
                status = "Dealer has " .. score.total .. (score.isSoft and " (soft)" or "") .. " - drawing... (" .. ruleText .. ")"
            else
                status = "Dealer has " .. score.total .. (score.isSoft and " (soft)" or "") .. " - click HIT (" .. ruleText .. ")"
            end
        else
            status = "Dealer stands at " .. score.total .. " (" .. ruleText .. ")"
        end
    elseif GS.phase == GS.PHASE.SETTLEMENT then
        status = "Hand complete! Click HOST to start a new game."
    elseif GS.phase == GS.PHASE.DEALING then
        status = "Dealing cards..."
    end
    self.statusBar.text:SetText(status)
    
    -- Update dealer name with color coding
    if self.dealerArea and self.dealerArea.label then
        local hostName = BJ.Multiplayer.currentHost
        local myName = UnitName("player")
        local isHost = BJ.Multiplayer.isHost
        
        if hostName then
            -- Apply color coding like player names
            local labelText
            if isHost then
                -- I'm the host - gold color
                labelText = "|cffffd700" .. hostName .. "|r"
            elseif hostName == myName then
                -- I'm the host (shouldn't happen but safety)
                labelText = "|cffffd700" .. hostName .. "|r"
            else
                -- Someone else is host - white
                labelText = hostName
            end
            self.dealerArea.label:SetText(labelText)
            self.dealerArea.label:Show()
        else
            -- No host, hide the label
            self.dealerArea.label:SetText("")
            self.dealerArea.label:Hide()
        end
    end
end

function UI:FormatScoreText(scoreInfo, showFinalOnly)
    if not scoreInfo then return "" end
    if scoreInfo.isBust then
        return "|cffff4444" .. scoreInfo.total .. " BUST|r"
    end
    if scoreInfo.isBlackjack then
        return "|cffffd700BLACKJACK!|r"
    end
    if scoreInfo.isFiveCardCharlie then
        return "|cff00ff00" .. scoreInfo.total .. " 5-CARD!|r"
    end
    -- For soft hands (ace counted as 11), show both options unless:
    -- 1. Player has stood/finished (showFinalOnly)
    -- 2. The soft value would bust (this is already handled - isSoft is only true if total <= 21)
    -- Only show "hard/soft" format when there's a meaningful choice (soft value <= 21)
    if scoreInfo.isSoft and not showFinalOnly then
        local hardValue = scoreInfo.total - 10  -- Ace as 1
        local softValue = scoreInfo.total        -- Ace as 11
        -- Only show both if soft value is valid (<=21) - this is guaranteed by isSoft
        return "|cffffff00" .. hardValue .. "/" .. softValue .. "|r"
    end
    return tostring(scoreInfo.total)
end

function UI:UpdatePlayerHands()
    local GS = BJ.GameState
    local container = self.playerArea.content
    
    -- Hide all existing hand displays
    for _, hand in ipairs(self.playerArea.hands) do
        UI.Cards:UpdateHandDisplay(hand, {})
        hand:Hide()
    end
    
    local myName = UnitName("player")
    local isSettlement = (GS.phase == GS.PHASE.SETTLEMENT)
    
    -- Count total hand displays needed
    local totalHands = 0
    for _, playerName in ipairs(GS.playerOrder) do
        local playerData = GS.players[playerName]
        if playerData then
            totalHands = totalHands + #playerData.hands
        end
    end
    
    if totalHands == 0 then 
        self.playerArea.totalRows = 1
        self.playerArea.currentRow = 1
        self.playerArea.rowIndicator:SetText("0/0")
        if self.playerArea.rowIndicatorFrame then
            self.playerArea.rowIndicatorFrame:Hide()
        end
        container:SetHeight(self.playerArea.ROW_HEIGHT or 180)
        return 
    end
    
    local totalRows = math.ceil(totalHands / PLAYER_COLS)
    self.playerArea.totalRows = totalRows
    
    -- Set content frame height to fit all rows
    local ROW_HEIGHT = self.playerArea.ROW_HEIGHT or 180
    local contentHeight = totalRows * ROW_HEIGHT
    container:SetHeight(contentHeight)
    
    -- Clamp current row
    if self.playerArea.currentRow < 1 then
        self.playerArea.currentRow = 1
    elseif self.playerArea.currentRow > totalRows then
        self.playerArea.currentRow = totalRows
    end
    
    -- Update row indicator and nav visibility
    self.playerArea.rowIndicator:SetText(self.playerArea.currentRow .. "/" .. totalRows)
    if self.playerArea.rowIndicatorFrame then
        if totalRows > 2 then
            self.playerArea.rowIndicatorFrame:Show()
        else
            self.playerArea.rowIndicatorFrame:Hide()
        end
    end
    
    -- Render ALL hands at once
    local handDisplayIndex = 0
    local cp = GS:GetCurrentPlayer()
    
    for i, playerName in ipairs(GS.playerOrder) do
        local playerData = GS.players[playerName]
        if playerData then
            for h, handCards in ipairs(playerData.hands) do
                handDisplayIndex = handDisplayIndex + 1
                
                -- Create hand display if needed
                while #self.playerArea.hands < handDisplayIndex do
                    local newHand = UI.Cards:CreateHandDisplay(container, "PlayerHand" .. (#self.playerArea.hands + 1), false)
                    table.insert(self.playerArea.hands, newHand)
                end
                
                local handDisplay = self.playerArea.hands[handDisplayIndex]
                
                -- Calculate row and position within row
                local rowNum = math.ceil(handDisplayIndex / PLAYER_COLS)
                local posInRow = ((handDisplayIndex - 1) % PLAYER_COLS)
                
                -- Calculate how many items in this row (for centering)
                local firstInRow = (rowNum - 1) * PLAYER_COLS + 1
                local lastInRow = math.min(rowNum * PLAYER_COLS, totalHands)
                local itemsInRow = lastInRow - firstInRow + 1
                local rowWidth = itemsInRow * PLAYER_CELL_WIDTH
                local halfRowWidth = rowWidth / 2
                
                -- X position: center the row
                local xOffset = -halfRowWidth + (posInRow * PLAYER_CELL_WIDTH) + (PLAYER_CELL_WIDTH / 2)
                -- Y position: from top of content, going down
                local yOffset = -((rowNum - 1) * ROW_HEIGHT) - (ROW_HEIGHT / 2)
                
                -- Build label
                local label = playerName
                if #playerData.hands > 1 then
                    label = label .. " (" .. h .. ")"
                end
                -- Don't show turn indicator during initial deal animation
                local isAnimating = UI.Animation and UI.Animation.isInitialDeal
                local isCurrentPlayer = playerName == cp and GS.phase == GS.PHASE.PLAYER_TURN and h == playerData.activeHandIndex and not isAnimating
                local isHost = playerName == GS.hostName
                if isCurrentPlayer then
                    -- Active player: bright green like button hover
                    label = "|cff66ff66>" .. label .. "<|r"
                elseif isHost then
                    -- Host: gold
                    label = "|cffffd700" .. label .. "|r"
                elseif playerName == myName then
                    -- Self (non-host): slightly dimmer green
                    label = "|cff00dd00" .. label .. "|r"
                end
                
                -- Determine results
                local result, payout = nil, nil
                if isSettlement then
                    if playerData.outcomes and playerData.payouts then
                        result = playerData.outcomes[h]
                        payout = playerData.payouts[h]
                    end
                else
                    if playerData.outcomes and playerData.outcomes[h] then
                        local outcome = playerData.outcomes[h]
                        if outcome == GS.OUTCOME.BLACKJACK or outcome == GS.OUTCOME.BUST then
                            result = outcome
                        end
                    end
                end
                
                -- Only show cards that have been dealt (animated)
                local dealtCardsForHand = {}
                local cardKey = playerName .. "_" .. h
                local numDealt = self.dealtCards[cardKey] or 0
                for c = 1, math.min(numDealt, #handCards) do
                    table.insert(dealtCardsForHand, handCards[c])
                end
                
                -- Calculate display score
                local displayScore = ""
                if #dealtCardsForHand > 0 then
                    local dealtScoreInfo = GS:ScoreHand(dealtCardsForHand)
                    local handIsDone = isSettlement or 
                                      GS.phase == GS.PHASE.DEALER_TURN or
                                      playerName ~= cp or 
                                      h ~= playerData.activeHandIndex or
                                      (playerData.outcomes and playerData.outcomes[h])
                    displayScore = self:FormatScoreText(dealtScoreInfo, handIsDone)
                end
                
                -- Update hand display
                local bet = playerData.bets[h]
                UI.Cards:UpdateHandDisplay(handDisplay, dealtCardsForHand, false, nil, bet, label, result, payout)
                handDisplay.scoreLabel:SetText(displayScore)
                if #dealtCardsForHand > 0 then
                    handDisplay.scoreLabel:Show()
                else
                    handDisplay.scoreLabel:Hide()
                end
                
                -- Set background highlight for current player
                if handDisplay.labelBg then
                    if isCurrentPlayer then
                        handDisplay.labelBg:SetVertexColor(0.3, 0.25, 0.1, 0.8)
                        handDisplay.labelBg:SetWidth(handDisplay.label:GetStringWidth() + 20)
                        handDisplay.labelBg:Show()
                    else
                        handDisplay.labelBg:Hide()
                    end
                end
                
                -- Store player info on handDisplay for effect positioning
                handDisplay.playerName = playerName
                handDisplay.handIndex = h
                
                -- Position in content frame
                handDisplay:ClearAllPoints()
                handDisplay:SetPoint("CENTER", container, "TOP", xOffset, yOffset)
                handDisplay:Show()
            end
        end
    end
end

-- Scroll to the row containing the active player
function UI:ScrollToActivePlayer()
    local GS = BJ.GameState
    local currentPlayer = GS:GetCurrentPlayer()
    if not currentPlayer then return end
    
    -- Find which hand index the current player is at
    local handIndex = 0
    for i, playerName in ipairs(GS.playerOrder) do
        local playerData = GS.players[playerName]
        if playerData then
            for h = 1, #playerData.hands do
                handIndex = handIndex + 1
                if playerName == currentPlayer and h == playerData.activeHandIndex then
                    -- Found the active hand, calculate its row
                    local targetRow = math.ceil(handIndex / PLAYER_COLS)
                    if targetRow ~= self.playerArea.currentRow then
                        self.playerArea.currentRow = targetRow
                        if self.playerArea.scrollToRow then
                            self.playerArea.scrollToRow(targetRow)
                        end
                    end
                    return
                end
            end
        end
    end
end

function UI:UpdateButtons()
    local GS = BJ.GameState
    local SM = BJ.SessionManager
    local myName = UnitName("player")
    local isMyTurn = GS:CanPlayerAct(myName)
    local isHost = BJ.Multiplayer.isHost
    local sessionActive = SM.isLocked
    local inTestMode = BJ.TestMode and BJ.TestMode.enabled
    local inPartyOrRaid = IsInGroup() or IsInRaid()
    
    -- Cancel turn timer if it's not my turn anymore
    if not isMyTurn and BJ.Multiplayer and BJ.Multiplayer.turnTimerActive then
        BJ.Multiplayer:CancelTurnTimer()
    end
    
    -- Check if auto button exists, if not recreate button area
    if not self.buttons.auto and self.buttonArea then
        self.buttonArea:Hide()
        self.buttonArea = nil
        self:CreateActionButtons()
    end
    
    for _, btn in pairs(self.buttons) do
        btn:SetEnabled(false)
        UI.Buttons:SetButtonHighlight(btn, false)
    end
    
    -- Update centered action button (Host/Join)
    self:UpdateActionButton()
    
    -- DEAL button
    if isHost and GS.phase == GS.PHASE.WAITING_FOR_PLAYERS and #GS.playerOrder > 0 then
        self.buttons.deal:SetEnabled(true)
    end
    
    -- Action buttons (HIT, STAND, DOUBLE, SPLIT)
    -- Only enabled if it's player's turn AND NO initial deal animation is playing
    -- Regular card animations (hits) should NOT block action buttons
    local initialDealPlaying = self.isDealingAnimation
    if isMyTurn and not initialDealPlaying then
        -- Start turn timer if not already running
        if BJ.Multiplayer and not BJ.Multiplayer.turnTimerActive then
            BJ.Multiplayer:StartTurnTimer()
        end
        
        local player = GS.players[myName]
        if player then
            local hand = player.hands[player.activeHandIndex]
            local handIndex = player.activeHandIndex
            local isSplitAcesHand = player.splitAcesHands and player.splitAcesHands[handIndex]
            
            if hand then
                -- Cannot hit on split aces
                if not isSplitAcesHand then
                    self.buttons.hit:SetEnabled(true)
                end
                self.buttons.stand:SetEnabled(true)
                -- Cannot double on split aces
                if #hand == 2 and not isSplitAcesHand then
                    self.buttons.double:SetEnabled(true)
                end
                if GS:CanSplit(myName) then
                    self.buttons.split:SetEnabled(true)
                end
            end
        end
    end
    
    -- Dealer turn is automatic by rules, but host can control pacing manually
    -- When AUTO is off, host clicks HIT to draw each card
    if isHost and GS.phase == GS.PHASE.DEALER_TURN then
        if GS:DealerNeedsAction() then
            -- Dealer must hit per rules - enable HIT button for manual pacing
            self.buttons.hit:SetEnabled(true)
            UI.Buttons:SetButtonHighlight(self.buttons.hit, true)
        end
        -- No STAND button - dealer cannot choose to stand early (rules dictate)
    end
    
    -- AUTO button - controls automatic dealer play pacing
    if self.buttons.auto then
        if isHost then
            self.buttons.auto:SetEnabled(true)
            self.buttons.auto:Show()
            if BJ.autoDealer then
                self.buttons.auto.text:SetText("|cff00ff00AUTO|r")
                UI.Buttons:SetButtonHighlight(self.buttons.auto, true)
            else
                self.buttons.auto.text:SetText("AUTO")
                UI.Buttons:SetButtonHighlight(self.buttons.auto, false)
            end
        else
            -- Show but disabled for non-hosts
            self.buttons.auto:SetEnabled(false)
            self.buttons.auto:Show()
            self.buttons.auto.text:SetText("AUTO")
        end
    end
    
    -- LOG always enabled
    self.buttons.log:SetEnabled(true)
    
    -- RESET button - only available for host
    if isHost then
        self.buttons.reset:SetEnabled(true)
    end
end

function UI:ToggleAutoDealer()
    BJ.autoDealer = not BJ.autoDealer
    if BJ.autoDealer then
        BJ:Print("Auto-dealer enabled - dealer will play automatically")
        -- If we're currently in dealer turn, start auto play
        local GS = BJ.GameState
        if GS.phase == GS.PHASE.DEALER_TURN and GS:DealerNeedsAction() then
            self:AutoPlayDealer()
        end
    else
        BJ:Print("Auto-dealer disabled - click HIT to draw dealer cards")
    end
    self:UpdateButtons()
end

function UI:OnHostClick()
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
    self:ShowHostPanel()
end

function UI:OnAnteClick()
    local GS = BJ.GameState
    if GS.phase == GS.PHASE.WAITING_FOR_PLAYERS then
        local myName = UnitName("player")
        if GS.players[myName] then
            -- Already in, try to add more
            BJ.Multiplayer:AddToBet(GS.ante)
        else
            -- First ante
            BJ.Multiplayer:PlaceAnte(GS.ante)
        end
    end
end

function UI:OnResetClick()
    -- Show confirmation dialog
    StaticPopupDialogs["BLACKJACK_RESET_CONFIRM"] = {
        text = "Are you sure you want to reset the game? This will end the current session for all players.",
        button1 = "Yes, Reset",
        button2 = "Cancel",
        OnAccept = function()
            -- Cancel any ongoing animations
            if UI.Animation and UI.Animation.ClearQueue then
                UI.Animation:ClearQueue()
            end
            UI.isDealingAnimation = false
            
            -- Cancel countdown timer
            if BJ.Multiplayer and BJ.Multiplayer.CancelCountdown then
                BJ.Multiplayer:CancelCountdown()
            end
            
            -- Broadcast reset to all clients
            if BJ.Multiplayer.isHost then
                BJ.Multiplayer:BroadcastReset()
            end
            BJ.SessionManager:EndSession()
            BJ.Multiplayer:ResetState()
            BJ.GameState:Reset()
            UI.dealtCards = {}  -- Clear dealt cards tracking
            UI.dealerDealtCards = 0  -- Clear dealer dealt cards
            -- Hide countdown frame
            if UI.countdownFrame then
                UI.countdownFrame:Hide()
            end
            -- Hide settlement panel
            if UI.settlementPanel then
                UI.settlementPanel:Hide()
            end
            UI:UpdateDisplay()
            BJ:Print("Game reset.")
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    StaticPopup_Show("BLACKJACK_RESET_CONFIRM")
end

function UI:OnHostTable()
    self.dealtCards = {}  -- Clear dealt cards tracking for new game
    self.dealerDealtCards = 0  -- Clear dealer dealt cards
    -- Clear any persistent effects from previous round
    if UI.Animation and UI.Animation.ClearPersistentEffects then
        UI.Animation:ClearPersistentEffects()
    end
    -- Set Trixie to waiting state for new game
    self:SetTrixieWait()
    self:Show()
    self:UpdateDisplay()
end

-- Called when another player hosts a table (non-host clients)
function UI:OnTableOpened(hostName, settings)
    self.dealtCards = {}  -- Clear dealt cards tracking
    self.dealerDealtCards = 0  -- Clear dealer dealt cards
    -- Clear any persistent effects from previous round
    if UI.Animation and UI.Animation.ClearPersistentEffects then
        UI.Animation:ClearPersistentEffects()
    end
    -- Set Trixie to waiting state for new game
    self:SetTrixieWait()
    -- Don't auto-open window for non-host clients - just update if already open
    if self.mainFrame and self.mainFrame:IsShown() then
        self:UpdateDisplay()
    end
end

function UI:OnTableClosed()
    self.settlementPanel:Hide()
    if self.countdownFrame then
        self.countdownFrame:Hide()
    end
    self:UpdateDisplay()
end

function UI:OnPlayerAnted(playerName, amount)
    -- Play ante sound
    if UI.Animation and UI.Animation.PlayAnteSound then
        UI.Animation:PlayAnteSound()
    end
    self:UpdateDisplay()
end

function UI:OnAnteAccepted(amount)
    -- Play ante sound for our own ante
    if UI.Animation and UI.Animation.PlayAnteSound then
        UI.Animation:PlayAnteSound()
    end
    self:UpdateDisplay()
end

function UI:OnPlayerLeft()
    self:UpdateDisplay()
end

function UI:OnCardsDealt()
    if self.countdownFrame then
        self.countdownFrame:Hide()
    end
    
    -- Set dealing animation flag immediately to disable buttons
    self.isDealingAnimation = true
    self:UpdateButtons()
    
    -- Clear dealt cards tracking for new hand
    self.dealtCards = {}
    self.dealerDealtCards = 0
    
    -- Clear any persistent effects from previous round
    if UI.Animation and UI.Animation.ClearPersistentEffects then
        UI.Animation:ClearPersistentEffects()
    end
    
    -- Hide settlement scoreboard for new round
    if self.settlementScoreboard then
        self.settlementScoreboard:Hide()
    end
    
    -- Clear existing displays
    UI.Cards:UpdateHandDisplay(self.dealerArea.hand, {})
    for _, hand in ipairs(self.playerArea.hands) do
        UI.Cards:UpdateHandDisplay(hand, {})
        hand:Hide()
    end
    
    -- Check if we need to play shuffle animation (reshuffle happened)
    local GS = BJ.GameState
    local needsShuffle = GS.reshuffledThisRound
    
    -- If shuffling, freeze the displayed card count until shuffle completes
    if needsShuffle then
        -- Store "old" card count (full deck) to show during shuffle
        -- After shuffle, we'll update to actual remaining
        self.isShuffling = true
        self.displayedCardCount = nil  -- Hide count during shuffle, or show "Shuffling..."
    end
    
    -- Play shuffle sound 3 times with delays, then start dealing
    local function playShuffleSequence(callback)
        -- Update status to show shuffling
        self.statusBar.text:SetText("Shuffling deck...")
        
        -- Update info text to show shuffling state
        self.mainFrame.infoText:SetText(self:BuildInfoText("|cff88ffffShuffling...|r"))
        
        -- Set Trixie to shuffling
        self:SetTrixieShuffle()
        
        -- First shuffle
        if UI.Lobby then
            UI.Lobby:PlayShuffleSound()
        end
        C_Timer.After(1.0, function()
            -- Alternate shuffle pose
            self:SetTrixieShuffle()
            -- Second shuffle
            if UI.Lobby then
                UI.Lobby:PlayShuffleSound()
            end
            C_Timer.After(1.0, function()
                -- Third shuffle pose
                self:SetTrixieShuffle()
                -- Third shuffle
                if UI.Lobby then
                    UI.Lobby:PlayShuffleSound()
                end
                C_Timer.After(1.5, function()
                    -- Shuffle complete - now update card count
                    self.isShuffling = false
                    self.displayedCardCount = GS:GetRemainingCards()
                    
                    -- Update info text with new card count (helper includes seed)
                    self.mainFrame.infoText:SetText(self:BuildInfoText())
                    
                    -- Set Trixie to dealing
                    self:SetTrixieDeal()
                    -- Now start dealing
                    if callback then callback() end
                end)
            end)
        end)
    end
    
    -- Function to start dealing cards
    local function startDealing()
        -- Update status to show dealing
        self.statusBar.text:SetText("Starting hand...")
    
    local GS = BJ.GameState
    local totalPlayers = #GS.playerOrder
    local totalRows = math.ceil(totalPlayers / PLAYER_COLS)
    local ROW_HEIGHT = self.playerArea.ROW_HEIGHT
    
    -- Set row info and start on row 1
    self.playerArea.totalRows = totalRows
    self.playerArea.currentRow = 1
    
    -- Set content height to fit all rows
    local contentHeight = totalRows * ROW_HEIGHT
    self.playerArea.content:SetHeight(contentHeight)
    
    -- Scroll to row 1
    if self.playerArea.scrollToRow then
        self.playerArea.scrollToRow(1)
    end
    
    -- Show nav if multiple rows
    if self.playerArea.rowIndicatorFrame then
        if totalRows > 1 then
            self.playerArea.rowIndicatorFrame:Show()
        else
            self.playerArea.rowIndicatorFrame:Hide()
        end
    end
    self.playerArea.rowIndicator:SetText("1/" .. totalRows)
    
    -- Create hand displays for ALL players
    local container = self.playerArea.content
    local playerHands = {}
    
    -- Create displays for all players, positioned in rows
    for i = 1, totalPlayers do
        while #self.playerArea.hands < i do
            local newHand = UI.Cards:CreateHandDisplay(container, "PlayerHand" .. (#self.playerArea.hands + 1), false)
            table.insert(self.playerArea.hands, newHand)
        end
        
        local handDisplay = self.playerArea.hands[i]
        local playerName = GS.playerOrder[i]
        
        -- Position based on which row this player is in
        local row = math.ceil(i / PLAYER_COLS)
        local colInRow = (i - 1) % PLAYER_COLS
        
        -- Calculate items in this player's row
        local firstInRow = (row - 1) * PLAYER_COLS + 1
        local lastInRow = math.min(row * PLAYER_COLS, totalPlayers)
        local itemsInRow = lastInRow - firstInRow + 1
        local rowWidth = itemsInRow * PLAYER_CELL_WIDTH
        local halfRowWidth = rowWidth / 2
        
        -- X offset from center
        local xOffset = -halfRowWidth + (colInRow * PLAYER_CELL_WIDTH) + (PLAYER_CELL_WIDTH / 2)
        -- Y offset: from top, each row lower
        local yOffset = -((row - 1) * ROW_HEIGHT) - (ROW_HEIGHT / 2)
        
        handDisplay:ClearAllPoints()
        handDisplay:SetPoint("CENTER", container, "TOP", xOffset, yOffset)
        
        -- Set label
        local lbl = playerName
        if playerName == UnitName("player") then
            lbl = "|cff00ff00" .. playerName .. "|r"
        end
        handDisplay.label:SetText(lbl)
        handDisplay.label:Show()
        handDisplay.betLabel:SetText(GS.players[playerName].bets[1] .. "g")
        handDisplay.betLabel:Show()
        handDisplay:Show()
        
        -- Store player info for effect positioning
        handDisplay.playerName = playerName
        handDisplay.handIndex = 1
        
        playerHands[i] = handDisplay
    end
    
    if UI.Animation then
        self.isDealingAnimation = true  -- Block actions during deal
        
        UI.Animation:DealInitialCards(self.dealerArea.hand, playerHands, function()
            self.isDealingAnimation = false  -- Deal complete, allow actions
            
            -- Scroll to row 1 after dealing completes
            self.playerArea.currentRow = 1
            if self.playerArea.scrollToRow then
                self.playerArea.scrollToRow(1)
            end
            
            -- Update info text with seed (persists through all phases)
            self.mainFrame.infoText:SetText(self:BuildInfoText())
            
            self:UpdateButtons()
            self:UpdateStatus()
            self:UpdateDealerDisplay()
            self:UpdatePlayerHands()  -- Ensure player hands are correctly displayed
            
            -- Check if local player got blackjack and play voice/effects
            local myName = UnitName("player")
            local myPlayer = GS.players[myName]
            if myPlayer and myPlayer.hasBlackjack then
                -- Local player got blackjack!
                self:SetTrixieCheer()
                -- Force texture refresh
                if self.trixieFrame and self.trixieFrame.texture then
                    self.trixieFrame.texture:SetTexture(self.trixieFrame.texture:GetTexture())
                end
                if UI.Lobby then
                    UI.Lobby:PlayWinSound()
                    UI.Lobby:PlayTrixieBlackjackVoice()
                end
                -- Hold cheer for 3 seconds then return to wait
                C_Timer.After(3.0, function()
                    self:SetTrixieWait()
                end)
            else
                -- Local player didn't get blackjack - show waiting animation
                self:SetTrixieWait()
                -- Force texture refresh
                if self.trixieFrame and self.trixieFrame.texture then
                    self.trixieFrame.texture:SetTexture(self.trixieFrame.texture:GetTexture())
                end
            end
            
            -- Wait a moment for players to see the dealt hands before starting turns
            if BJ.Multiplayer.isHost then
                C_Timer.After(2.0, function()
                    BJ.Multiplayer:CheckPhaseChange()
                    -- Also check for test player turns
                    if BJ.TestMode and BJ.TestMode.enabled and BJ.TestMode.CheckNextPlayer then
                        BJ.TestMode:CheckNextPlayer()
                    end
                end)
            end
        end)
        
        -- Fallback for non-host: force animation complete after timeout
        -- This ensures buttons are enabled even if animation callback fails
        if not BJ.Multiplayer.isHost then
            C_Timer.After(5.0, function()
                if self.isDealingAnimation then
                    BJ:Debug("Fallback: clearing isDealingAnimation for non-host")
                    self.isDealingAnimation = false
                    self:UpdateButtons()
                    self:UpdateStatus()
                end
            end)
        end
    else
        -- Fallback: just show cards immediately without animation
        self.dealerDealtCards = #BJ.GameState.dealerHand
        for playerName, _ in pairs(BJ.GameState.players) do
            local player = BJ.GameState.players[playerName]
            for handIdx, hand in ipairs(player.hands) do
                local cardKey = playerName .. "_" .. handIdx
                self.dealtCards[cardKey] = #hand
            end
        end
        self:UpdateDisplay()
        
        -- Clear the animation flag since we're done
        self.isDealingAnimation = false
        
        -- Trigger next phase
        if BJ.Multiplayer.isHost then
            C_Timer.After(1.0, function()
                BJ.Multiplayer:CheckPhaseChange()
                if BJ.TestMode and BJ.TestMode.enabled and BJ.TestMode.CheckNextPlayer then
                    BJ.TestMode:CheckNextPlayer()
                end
            end)
        end
    end  -- End of if UI.Animation
    end  -- End of startDealing function
    
    -- Either play shuffle sequence then deal, or deal immediately
    if needsShuffle then
        playShuffleSequence(startDealing)
    else
        -- No shuffle needed - just set Trixie to dealing and start
        -- Set displayed card count (no shuffle, so just use current)
        self.displayedCardCount = GS:GetRemainingCards()
        self:SetTrixieDeal()
        self.statusBar.text:SetText("Dealing...")
        startDealing()
    end
end

function UI:OnPlayerHit(playerName, card, handIndex)
    local GS = BJ.GameState
    local player = GS.players[playerName]
    -- Use provided handIndex or fall back to activeHandIndex
    local targetHandIndex = handIndex or (player and player.activeHandIndex or 1)
    
    -- Find the correct hand display for this player
    local handDisplay = self:FindPlayerHandDisplay(playerName, targetHandIndex)
    
    if handDisplay and UI.Animation then
        -- Store reference to handDisplay for use in closure
        local targetHand = handDisplay
        UI.Animation:DealSingleCard(targetHand, card, true, function()
            -- Track that this card has been dealt
            local cardKey = playerName .. "_" .. targetHandIndex
            self.dealtCards[cardKey] = (self.dealtCards[cardKey] or 0) + 1
            
            -- Update display to show the new card
            self:UpdatePlayerHands()
            self:UpdateButtons()
            self:UpdateStatus()
            
            -- Check for special outcomes and play effects after a brief delay
            -- This ensures the card has visually landed before the effect appears
            -- Re-find the hand display in case it moved during animation
            local effectHand = self:FindPlayerHandDisplay(playerName, targetHandIndex)
            if effectHand and player and player.hands[targetHandIndex] then
                local score = GS:ScoreHand(player.hands[targetHandIndex])
                if score.isBust then
                    C_Timer.After(0.3, function()
                        UI.Animation:PlayBustEffect(effectHand, playerName, targetHandIndex)
                        -- Play bust sound and voice
                        if UI.Lobby then
                            UI.Lobby:PlayBustSound()
                        end
                        -- Trixie reacts based on who busted
                        local myName = UnitName("player")
                        local isHost = BJ.Multiplayer and BJ.Multiplayer.isHost
                        if playerName == myName then
                            -- Local player busted - Trixie is sad for them
                            self:SetTrixieLose()
                            if UI.Lobby then
                                UI.Lobby:PlayTrixieBustVoice()
                            end
                        elseif isHost then
                            -- Host/dealer cheers when other players bust
                            self:SetTrixieCheer()
                            if UI.Lobby then
                                UI.Lobby:PlayTrixieWoohooVoice()
                            end
                        else
                            -- Non-host players stay neutral when others bust
                            self:SetTrixieWait()
                        end
                        -- Return to waiting after a moment
                        C_Timer.After(2.0, function()
                            self:SetTrixieWait()
                        end)
                    end)
                elseif score.isFiveCardCharlie then
                    C_Timer.After(0.3, function()
                        -- Trixie reacts based on who got 5-card charlie
                        local myName = UnitName("player")
                        local isHost = BJ.Multiplayer and BJ.Multiplayer.isHost
                        if playerName == myName then
                            -- Local player got charlie - play win sound and Trixie cheers!
                            if UI.Lobby then
                                UI.Lobby:PlayWinSound()
                                UI.Lobby:PlayTrixieWoohooVoice()
                            end
                            self:SetTrixieCheer()
                        elseif isHost then
                            -- Host/dealer is sad when players win with charlie
                            self:SetTrixieLose()
                            if UI.Lobby then
                                UI.Lobby:PlayTrixieBadVoice()
                            end
                        else
                            -- Non-host players stay neutral when others get charlie
                            self:SetTrixieWait()
                        end
                        C_Timer.After(2.0, function()
                            self:SetTrixieWait()
                        end)
                    end)
                end
            end
            
            -- If a test player was waiting for this animation, continue their turn
            local TM = BJ.TestMode
            if TM and TM.waitingForAnimation == playerName then
                TM.waitingForAnimation = nil
                
                -- Wait for any effects (bust/charlie) to finish playing
                local function continueAfterEffects()
                    if UI.Animation and UI.Animation:IsPlayingEffects() then
                        C_Timer.After(0.3, continueAfterEffects)
                        return
                    end
                    
                    C_Timer.After(0.3, function()
                        -- Check if still this player's turn (didn't bust)
                        if GS:GetCurrentPlayer() == playerName and GS.phase == GS.PHASE.PLAYER_TURN then
                            TM:AutoPlayHand(playerName)
                        else
                            -- Busted or moved to next player
                            if BJ.Multiplayer.isHost then
                                BJ.Multiplayer:CheckPhaseChange()
                            end
                            TM:CheckNextPlayer()
                        end
                    end)
                end
                
                C_Timer.After(0.5, continueAfterEffects)
            end
        end, false)
    else
        -- No animation - still track dealt card
        local cardKey = playerName .. "_" .. targetHandIndex
        self.dealtCards[cardKey] = (self.dealtCards[cardKey] or 0) + 1
        self:UpdateDisplay()
    end
end

-- Find the correct visual hand display for a player
function UI:FindPlayerHandDisplay(playerName, handIndex)
    local GS = BJ.GameState
    
    -- Calculate which global hand index this player's hand is
    local globalHandIndex = 0
    for i, pName in ipairs(GS.playerOrder) do
        local playerData = GS.players[pName]
        if playerData then
            for h = 1, #playerData.hands do
                globalHandIndex = globalHandIndex + 1
                if pName == playerName and h == handIndex then
                    -- All hands are now rendered, so just return the hand at this index
                    return self.playerArea.hands[globalHandIndex]
                end
            end
        end
    end
    
    return nil
end

function UI:OnPlayerStand()
    self:UpdateDisplay()
end

function UI:OnPlayerDouble(playerName, card)
    local GS = BJ.GameState
    local player = GS.players[playerName]
    local activeHandIndex = player and player.activeHandIndex or 1
    
    local handDisplay = self:FindPlayerHandDisplay(playerName, activeHandIndex)
    
    if handDisplay and UI.Animation then
        UI.Animation:DealSingleCard(handDisplay, card, true, function()
            -- Track that this card has been dealt
            local cardKey = playerName .. "_" .. activeHandIndex
            self.dealtCards[cardKey] = (self.dealtCards[cardKey] or 0) + 1
            
            -- Update display to show the new card
            self:UpdatePlayerHands()
            self:UpdateButtons()
            self:UpdateStatus()
            
            -- If a test player was waiting for this animation (double), move to next
            local TM = BJ.TestMode
            if TM and TM.waitingForAnimation == playerName and TM.waitingForDouble then
                TM.waitingForAnimation = nil
                TM.waitingForDouble = nil
                C_Timer.After(0.5, function()
                    if BJ.Multiplayer.isHost then
                        BJ.Multiplayer:CheckPhaseChange()
                    end
                    TM:CheckNextPlayer()
                end)
            end
        end, false)
    else
        -- No animation - still track dealt card
        local cardKey = playerName .. "_" .. activeHandIndex
        self.dealtCards[cardKey] = (self.dealtCards[cardKey] or 0) + 1
        self:UpdateDisplay()
    end
end

function UI:OnPlayerSplit(playerName, card1, card2)
    -- After split, each hand gets a new card dealt to it
    -- card1 goes to first hand, card2 goes to second hand
    local GS = BJ.GameState
    local player = GS.players[playerName]
    
    if not player then
        self:UpdateDisplay()
        return
    end
    
    -- Find hand displays for both hands
    local hand1Display = self:FindPlayerHandDisplay(playerName, 1)
    local hand2Display = self:FindPlayerHandDisplay(playerName, 2)
    
    -- Initialize dealt cards to show original cards (before new cards)
    -- Each hand starts with 1 card after split, will have 2 after new cards
    local cardKey1 = playerName .. "_1"
    local cardKey2 = playerName .. "_2"
    self.dealtCards[cardKey1] = 1  -- Original card
    self.dealtCards[cardKey2] = 1  -- Original card
    
    -- Update display to show split hands
    self:UpdatePlayerHands()
    
    -- Animate dealing card1 to first hand
    if hand1Display and card1 and UI.Animation then
        UI.Animation:DealSingleCard(hand1Display, card1, true, function()
            self.dealtCards[cardKey1] = 2
            self:UpdatePlayerHands()
            
            -- Then animate dealing card2 to second hand
            -- Re-find hand2 in case display changed
            local h2Display = self:FindPlayerHandDisplay(playerName, 2)
            if h2Display and card2 then
                UI.Animation:DealSingleCard(h2Display, card2, true, function()
                    self.dealtCards[cardKey2] = 2
                    self:UpdatePlayerHands()
                    self:UpdateButtons()
                    self:UpdateStatus()
                    
                    -- Handle test player split completion
                    local TM = BJ.TestMode
                    if TM and TM.waitingForAnimation == playerName and TM.waitingForSplit then
                        TM.waitingForAnimation = nil
                        TM.waitingForSplit = nil
                        -- Continue playing first hand after split
                        C_Timer.After(0.5, function()
                            if GS:GetCurrentPlayer() == playerName then
                                TM:AutoPlayHand(playerName)
                            end
                        end)
                    end
                end, false)
            else
                self.dealtCards[cardKey2] = 2
                self:UpdateDisplay()
            end
        end, false)
    else
        -- No animation - mark all as dealt
        if player then
            for h = 1, #player.hands do
                local cardKey = playerName .. "_" .. h
                self.dealtCards[cardKey] = #player.hands[h]
            end
        end
        self:UpdateDisplay()
    end
end

function UI:OnDealerTurn()
    UI.Cards:FlipHoleCard(self.dealerArea.hand)
    self:UpdateDisplay()
    
    -- If auto-dealer enabled, play automatically; otherwise host clicks HIT manually
    if BJ.autoDealer and BJ.Multiplayer.isHost then
        self:AutoPlayDealer()
    end
end

-- Auto-play the dealer's turn
function UI:AutoPlayDealer()
    local GS = BJ.GameState
    
    if GS.phase ~= GS.PHASE.DEALER_TURN then return end
    if not GS:DealerNeedsAction() then 
        -- Dealer is done, check for settlement
        if BJ.Multiplayer.isHost then
            C_Timer.After(0.5, function()
                BJ.Multiplayer:CheckPhaseChange()
            end)
        end
        return 
    end
    
    -- Delay between dealer hits
    C_Timer.After(1.0, function()
        if GS.phase ~= GS.PHASE.DEALER_TURN then return end
        if not GS:DealerNeedsAction() then 
            -- Dealer is done
            if BJ.Multiplayer.isHost then
                BJ.Multiplayer:CheckPhaseChange()
            end
            return 
        end
        
        -- Dealer hits using Multiplayer function (which has access to MSG)
        local success, card, settled = BJ.Multiplayer:AutoDealerHit()
        if success and card then
            self:OnDealerHit(card)
            
            -- Check if dealer needs more cards after animation
            C_Timer.After(1.0, function()
                if settled or GS.phase == GS.PHASE.SETTLEMENT then
                    -- Dealer is done
                    if BJ.Multiplayer.isHost then
                        BJ.Multiplayer:SendSettlement()
                        self:OnSettlement()
                    end
                elseif GS:DealerNeedsAction() then
                    self:AutoPlayDealer()
                else
                    -- Dealer is done, check for settlement
                    if BJ.Multiplayer.isHost then
                        BJ.Multiplayer:CheckPhaseChange()
                    end
                end
            end)
        end
    end)
end

function UI:OnDealerHit(card)
    if UI.Animation then
        UI.Animation:DealSingleCard(self.dealerArea.hand, card, true, function()
            -- Track dealer dealt card
            self.dealerDealtCards = (self.dealerDealtCards or 0) + 1
            -- Update display to show the new card
            self:UpdateDealerDisplay()
        end, true)
    else
        -- No animation - still track dealt card
        self.dealerDealtCards = (self.dealerDealtCards or 0) + 1
        self:UpdateDisplay()
    end
end

function UI:OnSettlement()
    -- Release the session lock so host can start a new hand
    if BJ.SessionManager.isLocked then
        BJ.SessionManager:EndSession()
    end
    
    local GS = BJ.GameState
    local myName = UnitName("player")
    
    -- Check local player's settlement result
    local mySettlement = GS.settlements and GS.settlements[myName]
    local myTotal = mySettlement and mySettlement.total or 0
    
    -- Check if dealer busted
    local dealerScore = GS:ScoreHand(GS.dealerHand)
    
    if myTotal > 0 then
        -- Local player won! Trixie cheers for them
        self:SetTrixieCheer()
        if UI.Lobby then
            UI.Lobby:PlayTrixieWoohooVoice()
        end
    elseif myTotal < 0 then
        -- Local player lost - Trixie is sad
        self:SetTrixieLose()
        if UI.Lobby then
            UI.Lobby:PlayTrixieBadVoice()
        end
    else
        -- Push or not in game - neutral reaction
        self:SetTrixieWait()
    end
    
    -- Update settlement scoreboard
    if GS.settlements then
        self:UpdateSettlementScoreboard(GS.settlements)
    end
    
    -- Update the display to show settlement state
    self:UpdateDisplay()
end

-- Handle game voided due to player disconnect
function UI:OnGameVoided(disconnectedPlayer)
    -- Update status to show voided game
    if self.statusBar then
        self.statusBar.text:SetText("|cffff4444GAME VOIDED|r - " .. disconnectedPlayer .. " disconnected")
    end
    
    -- Trixie looks sad/confused
    self:SetTrixieLose()
    
    -- Hide settlement panel if showing
    if self.settlementPanel then
        self.settlementPanel:Hide()
    end
    
    -- Update buttons - only RESET should be available for host
    self:UpdateButtons()
    self:UpdateDisplay()
end

function UI:OnHostDisconnected()
    -- Legacy function - now handled by OnHostRecoveryStart
    self:OnHostRecoveryStart(BJ.Multiplayer.currentHost, nil)
end

-- Host recovery started - game is paused
function UI:OnHostRecoveryStart(originalHost, tempHost)
    local myName = UnitName("player")
    
    -- Update status to show recovery mode
    if self.statusBar then
        self.statusBar.text:SetText("|cffff8800PAUSED - Waiting for " .. originalHost .. "|r")
    end
    
    -- Trixie looks concerned
    self:SetTrixieLose()
    
    -- Show reset button only for temporary host
    if tempHost == myName then
        if self.actionButton then
            self.actionButton.text:SetText("VOID GAME")
            self.actionButton:Show()
            self.actionButton:Enable()
        end
    else
        if self.actionButton then
            self.actionButton:Hide()
        end
    end
    
    -- Hide other buttons during recovery
    if self.hitButton then self.hitButton:Hide() end
    if self.standButton then self.standButton:Hide() end
    if self.doubleButton then self.doubleButton:Hide() end
    if self.splitButton then self.splitButton:Hide() end
    
    self:UpdateDisplay()
end

-- Update recovery timer display
function UI:UpdateRecoveryTimer(remaining)
    if self.statusBar then
        local mins = math.floor(remaining / 60)
        local secs = remaining % 60
        local timeStr = string.format("%d:%02d", mins, secs)
        local host = BJ.Multiplayer.originalHost or "host"
        self.statusBar.text:SetText("|cffff8800PAUSED - " .. host .. " has " .. timeStr .. " to return|r")
    end
    
    -- Show in countdown frame too
    if self.countdownFrame and remaining <= 30 then
        self.countdownFrame.text:SetText(remaining)
        self.countdownFrame:Show()
        self.countdownFrame:SetBackdropColor(0.8, 0.3, 0.1, 0.9)
    end
end

-- Host returned - game resumes
function UI:OnHostRestored()
    -- Hide countdown
    if self.countdownFrame then
        self.countdownFrame:Hide()
    end
    
    -- Trixie is happy
    self:SetTrixieCheer()
    C_Timer.After(2.0, function()
        self:SetTrixieWait()
    end)
    
    -- Update display normally
    self:UpdateDisplay()
    self:UpdateButtons()
    self:UpdateStatus()
end

-- Game was voided due to timeout or manual reset
function UI:OnGameVoided(reason)
    -- Hide countdown
    if self.countdownFrame then
        self.countdownFrame:Hide()
    end
    
    -- Show voided message
    if self.statusBar then
        self.statusBar.text:SetText("|cffff4444GAME VOIDED: " .. reason .. "|r")
    end
    
    -- Trixie is sad
    self:SetTrixieLose()
    
    -- Clear display after delay
    C_Timer.After(3.0, function()
        self:UpdateDisplay()
        self:UpdateButtons()
    end)
end

function UI:OnCountdownTick(remaining)
    if not self.countdownFrame then return end
    if remaining > 0 then
        self.countdownFrame.text:SetText(remaining)
        self.countdownFrame:Show()
        local r, g, b = 0.2, 0.5, 0.2
        if remaining <= 5 then
            r, g, b = 0.8, 0.1, 0.1
        elseif remaining <= 10 then
            r, g, b = 0.7, 0.4, 0.1
        end
        self.countdownFrame:SetBackdropColor(r, g, b, 0.9)
    else
        self.countdownFrame:Hide()
    end
end

-- Turn timer tick (30 second limit per turn, only show last 10 seconds)
function UI:OnTurnTimerTick(remaining)
    if not self.countdownFrame then return end
    
    -- Only show timer for last 10 seconds
    if remaining > 0 and remaining <= 10 then
        self.countdownFrame.text:SetText(remaining)
        self.countdownFrame:Show()
        
        -- Color based on urgency
        local r, g, b = 0.8, 0.5, 0.1  -- Orange for warning
        if remaining <= 5 then
            r, g, b = 0.8, 0.1, 0.1  -- Red when critical
        end
        self.countdownFrame:SetBackdropColor(r, g, b, 0.9)
        
        -- Update status bar with warning
        if self.statusBar then
            self.statusBar.text:SetText("|cffff4444MAKE A MOVE or auto-stand in " .. remaining .. "s!|r")
        end
    else
        self.countdownFrame:Hide()
    end
end

function UI:ShowSettlement()
    self.settlementPanel.text:SetText(BJ.GameState:GetSettlementSummary())
    self.settlementPanel:Show()
end

function UI:ResetForNewHand()
    UI.Cards:ReleaseAllCards()
    local GS = BJ.GameState
    if BJ.Multiplayer.isHost then
        if GS:NeedsReshuffle() then
            GS:CreateShoe(time() + math.random(1, 100000))
            BJ:Print("Shoe reshuffled!")
        end
        GS.phase = GS.PHASE.WAITING_FOR_PLAYERS
        GS.dealerHand = {}
        GS.dealerHoleCardRevealed = false
        GS.players = {}
        GS.playerOrder = {}
        GS.currentPlayerIndex = 0
        GS.settlements = {}
        GS.ledger = nil
        GS.insuranceOffered = false
        BJ:Print("Ready for next hand!")
    end
    self:UpdateDisplay()
end
