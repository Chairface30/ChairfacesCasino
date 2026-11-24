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

-- Play area: one fixed layout. Trixie stands beside the window
-- (UI.GameWindow:EmbedTrixie), so nothing inside makes room for her.
local PLAY_AREA_WIDTH = 920
local PLAY_AREA_OFFSET = 10
local FRAME_WIDTH = PLAY_AREA_WIDTH + 20   -- 940px
local FRAME_HEIGHT = 540

local FELT_COLOR = { 0.05, 0.3, 0.15, 0.95 }

local PLAYER_COLS = 5
local PLAYER_CELL_WIDTH = 165
local PLAYER_CELL_HEIGHT = 120

function UI:Initialize()
    if self.isInitialized then return end
    
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
    self:CreateTestModeBar()
    self:CreateSettlementPanel()
    self.isInitialized = true
end

function UI:CreateMainFrame()
    -- Shared casino window (UI/Chrome.lua), same header as every table
    local frame = UI.Chrome:CreateWindow({
        name = "ChairfacesCasinoFrame",
        title = "Blackjack",
        width = FRAME_WIDTH, height = FRAME_HEIGHT,
        art = "felt", artW = 1280, artH = 714,
        howTo = "blackjack",
        debts = true,
        onLog = function() UI:ToggleLog() end,
        leaderboard = "blackjack",
        onRefresh = function()
            UI:Hide()
            C_Timer.After(0.05, function() UI:Show() end)
        end,
        onClose = function()
            UI:Hide()
            if UI.Lobby then UI.Lobby:Show() end
        end,
    })
    local titleBar = frame.titleBar
    self.titleBar = titleBar
    self.titleText = frame.titleText
    self.sessionBtn = frame.debtsBtn
    self.allTimeBtn = frame.leaderboardBtn

    local infoText = frame:CreateFontString(nil, "OVERLAY", "CCFontSmall")
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
    
    local label = dealerArea:CreateFontString(nil, "OVERLAY", "CCFontSmall")
    label:SetPoint("TOP", 0, 0)
    label:SetText("DEALER")
    label:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")  -- Same font/style as players, smaller size
    dealerArea.label = label

    -- the visual pot: every gold piece wagered this hand, stacked as
    -- denomination chips beside the dealer
    if UI.ChipPot then
        local chips = UI.ChipPot:Attach(dealerArea)
        chips:SetPoint("RIGHT", dealerArea, "LEFT", -12, -10)
        self.tableChips = chips
    end

    local hand = UI.Cards:CreateHandDisplay(dealerArea, "DealerHandDisplay", true)
    hand:SetPoint("TOP", label, "BOTTOM", 0, -5)
    dealerArea.hand = hand
    
    -- Trixie deals from beside the table
    self:MountTrixie(self.mainFrame)

    -- Settlement scoreboard (right side, same Y as Trixie)
    local scoreboard = CreateFrame("Frame", nil, self.mainFrame, "BackdropTemplate")
    scoreboard:SetSize(210, 168)  -- 150*1.4, 120*1.4 - Will resize dynamically
    scoreboard:SetPoint("TOPRIGHT", self.mainFrame, "TOPRIGHT", -15, -60)
    scoreboard:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
    scoreboard:SetBackdropColor(0, 0, 0, 1)  -- Fully opaque
    scoreboard:SetBackdropBorderColor(0.5, 0.4, 0.2, 1)
    scoreboard:Hide()
    
    local scoreTitle = scoreboard:CreateFontString(nil, "OVERLAY", "CCFontNormal")
    scoreTitle:SetPoint("TOP", 0, -7)
    scoreTitle:SetText("|cffffd700Ledger|r")
    scoreTitle:SetFont("Fonts\\FRIZQT__.TTF", 17)  -- 12*1.4
    scoreboard.title = scoreTitle
    
    -- Divider line
    local divider = scoreboard:CreateTexture(nil, "ARTWORK")
    divider:SetSize(2, 112)  -- 80*1.4
    divider:SetPoint("TOP", scoreTitle, "BOTTOM", 0, -7)
    divider:SetColorTexture(0.4, 0.4, 0.4, 0.6)
    scoreboard.divider = divider
    
    -- Left column: Players owe dealer (losses)
    local oweDealerLabel = scoreboard:CreateFontString(nil, "OVERLAY", "CCFontNormal")
    oweDealerLabel:SetPoint("TOPLEFT", 11, -31)  -- 8*1.4, 22*1.4
    oweDealerLabel:SetText("|cffff6666Owe Host|r")
    oweDealerLabel:SetJustifyH("LEFT")
    oweDealerLabel:SetFont("Fonts\\FRIZQT__.TTF", 14)  -- 10*1.4
    scoreboard.oweDealerLabel = oweDealerLabel
    
    local oweDealerContent = scoreboard:CreateFontString(nil, "OVERLAY", "CCFontNormal")
    oweDealerContent:SetPoint("TOPLEFT", 11, -50)  -- 8*1.4, 36*1.4
    oweDealerContent:SetWidth(91)  -- 65*1.4
    oweDealerContent:SetJustifyH("LEFT")
    oweDealerContent:SetJustifyV("TOP")
    oweDealerContent:SetFont("Fonts\\FRIZQT__.TTF", 14)  -- 10*1.4
    scoreboard.oweDealer = oweDealerContent
    
    -- Right column: Dealer owes players (wins)
    local dealerOwesLabel = scoreboard:CreateFontString(nil, "OVERLAY", "CCFontNormal")
    dealerOwesLabel:SetPoint("TOPRIGHT", -11, -31)
    dealerOwesLabel:SetText("|cff66ff66Host Owes|r")
    dealerOwesLabel:SetJustifyH("RIGHT")
    dealerOwesLabel:SetFont("Fonts\\FRIZQT__.TTF", 14)  -- 10*1.4
    scoreboard.dealerOwesLabel = dealerOwesLabel
    
    local dealerOwesContent = scoreboard:CreateFontString(nil, "OVERLAY", "CCFontNormal")
    dealerOwesContent:SetPoint("TOPRIGHT", -11, -50)
    dealerOwesContent:SetWidth(91)  -- 65*1.4
    dealerOwesContent:SetJustifyH("RIGHT")
    dealerOwesContent:SetJustifyV("TOP")
    dealerOwesContent:SetFont("Fonts\\FRIZQT__.TTF", 14)  -- 10*1.4
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
    
    local text = statusBar:CreateFontString(nil, "OVERLAY", "CCFontNormal")
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
    countdown.text = countdown:CreateFontString(nil, "OVERLAY", "CCFontLarge")
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
    
    local turnTimerLabel = turnTimer:CreateFontString(nil, "OVERLAY", "CCFontSmall")
    turnTimerLabel:SetPoint("TOP", 0, -5)
    turnTimerLabel:SetText("|cffff4444TIME LEFT|r")
    turnTimerLabel:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    
    turnTimer.text = turnTimer:CreateFontString(nil, "OVERLAY", "CCFontLarge")
    turnTimer.text:SetPoint("CENTER", 0, 0)
    turnTimer.text:SetFont("Fonts\\FRIZQT__.TTF", 24, "OUTLINE")
    turnTimer.text:SetTextColor(1, 0.3, 0.3, 1)
    
    turnTimer.warning = turnTimer:CreateFontString(nil, "OVERLAY", "CCFontSmall")
    turnTimer.warning:SetPoint("BOTTOM", 0, 5)
    turnTimer.warning:SetText("|cffff8800Auto-stand soon!|r")
    turnTimer.warning:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    turnTimer:Hide()
    
    self.statusBar = statusBar
    self.countdownFrame = countdown
    self.turnTimerFrame = turnTimer
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
    
    local rowIndicator = rowIndicatorFrame:CreateFontString(nil, "OVERLAY", "CCFontNormal")
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
    local GW = UI.GameWindow
    local function tm(fn)
        return function()
            if BJ.TestMode then fn(BJ.TestMode) end
            UI:UpdateDisplay()
        end
    end
    local bar = GW:TestBar(self, self.mainFrame, GW:Specs({
        { text = "+PLAYER", width = 65, onClick = tm(function(T) T:AddFakePlayer() end) },
        { text = "-PLAYER", width = 65, onClick = tm(function(T) T:RemoveLastFakePlayer() end) },
        { text = "DEAL", width = 50, onClick = tm(function(T) T:ForceDeal() end) },
        { text = "CLEAR", width = 55, onClick = tm(function(T) T:ClearFakePlayers() end) },
        { text = "HIT", width = 40, onClick = tm(function(T) T:ManualAction("hit") end) },
        { text = "STAND", width = 55, onClick = tm(function(T) T:ManualAction("stand") end) },
        { text = "DBL", width = 40, onClick = tm(function(T) T:ManualAction("double") end) },
        { text = "SPLIT", width = 50, onClick = tm(function(T) T:ManualAction("split") end) },
        { key = "auto", text = "AUTO", width = 50, onClick = tm(function(T)
            T:ToggleAutoPlay()
            UI.testBar.buttons.auto:SetText(T.autoPlay and "AUTO*" or "AUTO")
        end) },
    }, GW:CommonTestTools(self)))
    self.testModeBar = bar
    bar.trixToggleBtn = bar.buttons.trix
end

function UI:CreateActionButtons()
    local buttonArea = CreateFrame("Frame", nil, self.mainFrame)
    buttonArea:SetSize(PLAY_AREA_WIDTH - 20, 50)
    -- Center in play area (offset by half of PLAY_AREA_OFFSET to the right)
    buttonArea:SetPoint("BOTTOM", PLAY_AREA_OFFSET / 2, 15)
    
    local buttons = {}
    local configs = {
        { name = "hit", text = "HIT", width = 50 },
        { name = "stand", text = "STAND", width = 60 },
        { name = "double", text = "DBL", width = 45 },
        { name = "split", text = "SPLIT", width = 55 },
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
    
    -- Create DEAL button (hidden by default, shown only when host and active)
    local dealBtn = UI.Buttons:CreateGameButton(buttonArea, "deal", "DEAL", 60)
    dealBtn:SetPoint("RIGHT", buttons.hit, "LEFT", -10, 0)
    dealBtn:Hide()
    buttons.deal = dealBtn
    
    -- Create AUTO button (hidden by default, shown only for host)
    local autoBtn = UI.Buttons:CreateGameButton(buttonArea, "auto", "AUTO", 50)
    autoBtn:SetPoint("LEFT", buttons.split, "RIGHT", 10, 0)
    autoBtn:Hide()
    buttons.auto = autoBtn
    
    -- Create RESET button in bottom right corner (inside brown border)
    local resetBtn = UI.Buttons:CreateGameButton(self.mainFrame, "reset", "RESET", 55)
    resetBtn:SetPoint("BOTTOMRIGHT", self.mainFrame, "BOTTOMRIGHT", -15, 15)
    buttons.reset = resetBtn
    
    buttons.deal:SetScript("OnClick", function() BJ.Multiplayer:Deal() end)
    buttons.hit:SetScript("OnClick", function() BJ.Multiplayer:Hit() end)
    buttons.stand:SetScript("OnClick", function() BJ.Multiplayer:Stand() end)
    buttons.double:SetScript("OnClick", function() BJ.Multiplayer:Double() end)
    buttons.split:SetScript("OnClick", function() BJ.Multiplayer:Split() end)
    buttons.auto:SetScript("OnClick", function() UI:ToggleAutoDealer() end)
    buttons.reset:SetScript("OnClick", function() UI:OnResetClick() end)
    
    self.buttons = buttons
    self.buttonArea = buttonArea
    
    -- Create centered action button (Host/Join)
    self:CreateActionButton()
end

-- Create the centered Host/Join action button
function UI:CreateActionButton()
    -- centred in the dealer area (dealer area is at TOP, 0, -53 and is 110 tall)
    local btn = UI.GameWindow:CallToAction(self.mainFrame, "BlackjackActionButton",
        function() UI:OnActionButtonClick() end)
    btn:SetPoint("CENTER", self.dealerArea, "CENTER", 0, -15)
    self.actionButton = btn
end

function UI:OnActionButtonClick()
    local GS = BJ.GameState
    local MP = BJ.Multiplayer
    local myName = BJ:MyName()
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

    -- Clear the FREE PLAY badge by default; only the JOIN branch below
    -- re-shows it (badge is a child of the button, so a hidden button
    -- hides it automatically - this covers the HOST/RESET branches).
    if BJ.UI and BJ.UI.Debts then
        BJ.UI.Debts:SetJoinFakeBadge(self.actionButton, false)
    end

    local GS = BJ.GameState
    local MP = BJ.Multiplayer
    local myName = BJ:MyName()
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
    
    -- If host disconnected, show RESET for everyone
    if MP.hostDisconnected then
        self.actionButton.text:SetText("RESET")
        self.actionButton:Show()
        self.actionButton:Enable()
        return
    end
    
    -- Check if player already anted
    local alreadyAnted = GS.players and GS.players[myName] ~= nil
    local isCurrentHost = MP.currentHost == myName
    
    -- During WAITING_FOR_PLAYERS for THIS game, show JOIN button for non-host non-anted players
    if GS.phase == GS.PHASE.WAITING_FOR_PLAYERS then
        if MP.tableOpen and not isCurrentHost and not alreadyAnted then
            self.actionButton.text:SetText("JOIN")
            self.actionButton:Show()
            self.actionButton:Enable()
            if BJ.UI and BJ.UI.Debts then
                BJ.UI.Debts:SetJoinFakeBadge(self.actionButton, GS.fakePlay == true)
            end
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
    
    -- Hide during active game (dealing, player turn, dealer turn)
    if GS.phase == GS.PHASE.DEALING or 
       GS.phase == GS.PHASE.PLAYER_TURN or 
       GS.phase == GS.PHASE.DEALER_TURN then
        self.actionButton:Hide()
        return
    end
    
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
    else
        self.actionButton:Hide()
    end
end

-- Start action button refresh ticker (checks for game state changes)
function UI:StartActionButtonRefreshTicker()
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
                self:UpdateActionButton()
                self.lastBjInSession = bjInSession
                self.lastPokerInSession = pokerInSession
                self.lastHiloInSession = hiloInSession
            end
        end
    end)
end

-- Stop action button refresh ticker
function UI:StopActionButtonRefreshTicker()
    if self.actionButtonRefreshTicker then
        self.actionButtonRefreshTicker:Cancel()
        self.actionButtonRefreshTicker = nil
    end
end

function UI:CreateSettlementPanel()
    local panel = CreateFrame("Frame", nil, self.mainFrame, "BackdropTemplate")
    panel:SetSize(700, 450)  -- Reasonable size that fits in window
    panel:SetPoint("TOPRIGHT", self.mainFrame, "TOPRIGHT", -10, -10)  -- Top-right with padding
    panel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 3, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    panel:SetBackdropColor(0.1, 0.1, 0.1, 1)  -- Fully opaque
    panel:SetBackdropBorderColor(1, 0.84, 0, 1)
    panel:SetFrameLevel(self.mainFrame:GetFrameLevel() + 10)
    
    local title = panel:CreateFontString(nil, "OVERLAY", "CCFontLarge")
    title:SetPoint("TOP", 0, -15)
    title:SetText("Settlement")
    title:SetTextColor(1, 0.84, 0, 1)
    title:SetFont("Fonts\\FRIZQT__.TTF", 24)
    
    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetSize(620, 320)
    scrollFrame:SetPoint("TOP", title, "BOTTOM", -10, -15)
    
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(600, 800)
    scrollFrame:SetScrollChild(content)
    panel.content = content
    
    local text = content:CreateFontString(nil, "OVERLAY", "CCFontNormal")
    text:SetPoint("TOPLEFT", 10, -10)
    text:SetWidth(580)
    text:SetJustifyH("LEFT")
    text:SetSpacing(4)
    text:SetFont("Fonts\\FRIZQT__.TTF", 18)
    panel.text = text
    
    local closeBtn = BJ.Theme:Button(panel, "", 180, 50, "go", nil)
    closeBtn:SetPoint("BOTTOM", 0, 15)
    closeBtn.text = closeBtn.text
    closeBtn.text:SetText("CLOSE")
    closeBtn:SetScript("OnClick", function() panel:Hide() end)
    
    panel:Hide()
    self.settlementPanel = panel
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
    
    -- Start action button refresh ticker
    self:StartActionButtonRefreshTicker()
    
    -- Refresh Trixie debug if active
    if BJ.TestMode and BJ.TestMode.RefreshTrixieDebug then
        BJ.TestMode:RefreshTrixieDebug()
    end

    -- Surface a deferred "newer version in your group" warning if one is pending
    if BJ.ShowPendingVersionWarning then
        BJ:ShowPendingVersionWarning()
    end
end

function UI:Hide()
    if self.mainFrame then
        self.mainFrame:Hide()
    end
    -- Stop the refresh ticker
    self:StopActionButtonRefreshTicker()
    -- Also hide log panel
    if self.logFrame then
        self.logFrame:Hide()
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

    -- visual pot: the table's total action this hand as chip stacks
    if self.tableChips then
        local total = 0
        if GS.phase ~= GS.PHASE.IDLE then
            for _, player in pairs(GS.players or {}) do
                for _, bet in ipairs(player.bets or {}) do
                    total = total + (bet or 0)
                end
            end
        end
        self.tableChips:SetAmount(total)
    end
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

-- Get random Trixie state from a list
function UI:SetTrixieRandomState(states)
    if not states or #states == 0 then return end
    local idx = math.random(1, #states)
    self:SetTrixieState(states[idx])
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
    -- First name, as the games show everyone (a byte cut could split a letter).
    local shortHostName = BJ:SeatName(hostName, BJ.GameState and BJ.GameState.playerOrder)
    
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
    
    -- Calculate width: ~10 pixels per character (7*1.4) + padding
    -- Each column needs: name + space + amount
    local charWidth = 10  -- 7*1.4 rounded
    local columnWidth = (maxNameLen + 1 + maxAmountLen) * charWidth + 14  -- +14 padding (10*1.4)
    if columnWidth < 98 then columnWidth = 98 end  -- Minimum column width (70*1.4)
    
    local totalWidth = (columnWidth * 2) + 28  -- Two columns + divider + padding (20*1.4)
    if totalWidth < 224 then totalWidth = 224 end  -- Minimum total width (160*1.4)
    
    -- Calculate max width so left edge doesn't pass action button's right edge
    -- Scoreboard is at TOPRIGHT -15, action button is 180 wide centered in dealer area
    -- Action button right edge is approximately at mainFrame center + 90
    -- Scoreboard left edge = mainFrame right - 15 - totalWidth
    -- Constraint: mainFrame right - 15 - totalWidth >= mainFrame center + 90
    -- So: totalWidth <= mainFrame width / 2 - 90 - 15 = mainFrame width / 2 - 105
    if self.mainFrame then
        local frameWidth = self.mainFrame:GetWidth()
        local maxWidth = (frameWidth / 2) - 105  -- Leave space for action button
        if maxWidth < 224 then maxWidth = 224 end  -- Don't go below minimum
        if totalWidth > maxWidth then
            totalWidth = maxWidth
            columnWidth = (totalWidth - 28) / 2  -- Recalculate column width
        end
    end
    
    -- Update column widths
    self.settlementScoreboard.oweDealer:SetWidth(columnWidth)
    self.settlementScoreboard.dealerOwes:SetWidth(columnWidth)
    
    -- Dynamically resize based on content
    local maxEntries = math.max(oweDealerCount, dealerOwesCount)
    local lineHeight = 17  -- 12*1.4
    local baseHeight = 63  -- 45*1.4 - Title + labels
    local contentHeight = maxEntries * lineHeight
    local totalHeight = baseHeight + contentHeight + 14  -- padding (10*1.4)
    
    if totalHeight < 98 then totalHeight = 98 end  -- 70*1.4
    
    self.settlementScoreboard:SetSize(totalWidth, totalHeight)
    self.settlementScoreboard.divider:SetHeight(contentHeight + 21)  -- 15*1.4
    
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
    self:RefreshTestBar()
end

function UI:UpdateTestModeLayout()
    -- the bar hangs under the window, so nothing inside moves
    self:RefreshTestBar()
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
        if cp == BJ:MyName() then
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
        local myName = BJ:MyName()
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
    
    local myName = BJ:MyName()
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
    local myName = BJ:MyName()
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
    
    -- DEAL button - only show for host when deal is available
    if isHost and GS.phase == GS.PHASE.WAITING_FOR_PLAYERS and #GS.playerOrder > 0 then
        self.buttons.deal:SetEnabled(true)
        self.buttons.deal:Show()
    else
        self.buttons.deal:SetEnabled(false)
        self.buttons.deal:Hide()
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
    
    -- AUTO button - only show for host
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
            -- Hide for non-hosts
            self.buttons.auto:SetEnabled(false)
            self.buttons.auto:Hide()
        end
    end
    
    
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
        local myName = BJ:MyName()
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
    -- No sound - joining sound is local only (played in OnAnteAccepted)
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
        
        -- Set label: the short form, since Forever names run long
        local lbl, wholeName = BJ:SeatName(playerName, GS.playerOrder)
        if playerName == BJ:MyName() then
            lbl = "|cff00ff00" .. lbl .. "|r"
        end
        handDisplay.label:SetText(lbl)
        BJ:FitNameFont(handDisplay.label, wholeName)
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
            local myName = BJ:MyName()
            local myPlayer = GS.players[myName]
            if myPlayer and myPlayer.hasBlackjack then
                -- Local player got blackjack!
                self:SetTrixieCheer()
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
                        local myName = BJ:MyName()
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
                        local myName = BJ:MyName()
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
    if playerName == BJ:MyName() and UI.Lobby then
        UI.Lobby:PlayTrixieVoice("bj_double")   -- you doubled down
    end
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
    -- After split, each hand gets a new card dealt to it.
    -- The split always happens on the player's ACTIVE hand; the new hand is
    -- inserted immediately after it (see GameState:PlayerSplit). Splitting a
    -- later hand (e.g. hand 2 -> hands 2 & 3) shifts every subsequent hand's
    -- index up by one, so we can never assume the split touched hands 1 & 2.
    local GS = BJ.GameState
    local player = GS.players[playerName]

    if not player then
        self:UpdateDisplay()
        return
    end

    local splitIndex = player.activeHandIndex or 1
    local newIndex = splitIndex + 1

    -- Rebuild dealt-card counts from the authoritative hand list. Every hand
    -- already on the table keeps showing all of its cards; only the two hands
    -- involved in the split hold a single (original) card until the new card
    -- animates in. Keying off the current hand list corrects the index shift.
    for h = 1, #player.hands do
        local cardKey = playerName .. "_" .. h
        if h == splitIndex or h == newIndex then
            self.dealtCards[cardKey] = 1  -- Original card only; new card animates in
        else
            self.dealtCards[cardKey] = #player.hands[h]
        end
    end

    -- Find hand displays for the two split hands
    local hand1Display = self:FindPlayerHandDisplay(playerName, splitIndex)
    local cardKey1 = playerName .. "_" .. splitIndex
    local cardKey2 = playerName .. "_" .. newIndex

    -- Update display to show split hands
    self:UpdatePlayerHands()

    -- Animate dealing card1 to the split hand
    if hand1Display and card1 and UI.Animation then
        UI.Animation:DealSingleCard(hand1Display, card1, true, function()
            self.dealtCards[cardKey1] = 2
            self:UpdatePlayerHands()

            -- Then animate dealing card2 to the new hand
            -- Re-find in case the display changed
            local h2Display = self:FindPlayerHandDisplay(playerName, newIndex)
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
    local myName = BJ:MyName()
    
    -- Check local player's settlement result
    local mySettlement = GS.settlements and GS.settlements[myName]
    local myTotal = mySettlement and mySettlement.total or 0
    
    -- Check if dealer busted
    local dealerScore = GS:ScoreHand(GS.dealerHand)
    
    if myTotal > 0 then
        -- Local player won! Trixie cheers for them
        self:SetTrixieCheer()
        if UI.Lobby then
            if dealerScore and dealerScore > 21 then
                UI.Lobby:PlayTrixieVoice("bj_dealerbust")   -- dealer busted, you win
            else
                UI.Lobby:PlayTrixieWoohooVoice()
            end
        end
    elseif myTotal < 0 then
        -- Local player lost - Trixie is sad
        self:SetTrixieLose()
        if UI.Lobby then
            UI.Lobby:PlayTrixieBadVoice()
        end
    else
        -- Push (if you were dealt in) or simply not in this hand
        self:SetTrixieWait()
        if mySettlement and UI.Lobby then
            UI.Lobby:PlayTrixieVoice("bj_push")   -- a tie
        end
    end
    
    -- Update settlement scoreboard
    if GS.settlements then
        self:UpdateSettlementScoreboard(GS.settlements)
    end
    
    -- Update the display to show settlement state
    self:UpdateDisplay()
end

function UI:OnHostDisconnected()
    -- Legacy function - now handled by OnHostRecoveryStart
    self:OnHostRecoveryStart(BJ.Multiplayer.currentHost, nil)
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
    -- Grow the scroll child to the rendered text so long ledgers scroll
    -- instead of clipping at the fixed default height
    if self.settlementPanel.content then
        local h = math.ceil(self.settlementPanel.text:GetStringHeight() or 0)
        self.settlementPanel.content:SetHeight(math.max(320, h + 40))
    end
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

-- the shared "last games" log window (UI/GameLog.lua)
UI.GameLog:Embed(UI, {
    name = "ChairfacesCasinoLogPanel", title = "Blackjack",
    state = function() return BJ.GameState end,
    anchor = function() return UI.mainFrame end,
})

-- Trixie beside the table, moods and the show/hide setting (UI/GameWindow.lua)
UI.GameWindow:EmbedTrixie(UI, "blackjack")

-- host-away pause / void messages (UI/GameWindow.lua)
UI.GameWindow:EmbedRecovery(UI, { net = function() return BJ.Multiplayer end })

function UI:OnRecoveryPause(originalHost, tempHost, iAmTempHost)
    -- the temporary host gets VOID GAME on the big button; everyone else waits
    if self.actionButton then
        if iAmTempHost then
            self.actionButton:SetText("VOID GAME")
            self.actionButton:Show()
            self.actionButton:Enable()
        else
            self.actionButton:Hide()
        end
    end
end

-- the last 30 seconds also count down in the big countdown box
function UI:OnRecoveryTick(remaining)
    if self.countdownFrame and remaining <= 30 then
        self.countdownFrame.text:SetText(remaining)
        self.countdownFrame:Show()
        local w = BJ.Theme.C.warn
        self.countdownFrame:SetBackdropColor(w[1] * 0.8, w[2] * 0.5, w[3] * 0.5, 0.9)
    end
end

function UI:OnRecoveryResume()
    if self.countdownFrame then self.countdownFrame:Hide() end
end

function UI:OnRecoveryVoid()
    if self.countdownFrame then self.countdownFrame:Hide() end
    if self.settlementPanel then self.settlementPanel:Hide() end
end
