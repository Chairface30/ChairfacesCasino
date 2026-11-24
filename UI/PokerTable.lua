--[[
    Chairface's Casino - UI/PokerTable.lua
    ============================================
    The poker table window, shared by 5 Card Stud (UI/PokerFrame.lua) and
    Texas Hold'em (UI/HoldemFrame.lua) - the UI twin of Core/PokerEngine.lua.

        UI.PokerTable:Embed(module, cfg)

    builds every table method on `module`. Each game file then defines only
    its rule differences through the hooks below (a later
    `function Module:X()` replaces the embedded default, same as the engine).

    cfg:
      key          game key: settings/host-setting prefix, lobby + how-to key
      name         display name ("5 Card Stud")
      state, net   BJ field names of the game's State / Multiplayer modules
      prefix       global-name prefix for the action button, host panel, hands
      frameName    main window global name
      logFrameName log window global name
      resetPopup   StaticPopup key for "reset game?"

    Hooks (defaults are no-ops / the 5 Card Stud behaviour):
      Poker:CreateDealerExtras(dealerArea)       extra table furniture
      Poker:CreateExtraButtons(buttonArea, createButton)
      Poker:UpdateExtraButtons(PS, isHost)
      Poker:BlocksNewTable(PS)                    true = hide HOST at settlement
      Poker:StakesText(PS)                        info-bar stakes ("Ante: 10g")
      Poker:AnteForJoin(PS)                       gold sent with a join
      Poker:ExtendHostPanel(form)                 extra UI.HostForm fields
      Poker:ReadHostPanelExtras(form)             -> extra table settings
      Poker:BuildTableSettings(ante, maxRaise, maxPlayers, cdOn, cdSecs, panel)
      Poker:DecorateHand(hand)                    per-seat extras at creation
      Poker:DecorateHandLabel(hand, name, player, label) -> label
      Poker:PotUnit(PS)                           "g" or " chips"
      Poker:ExtendSettlement(PS, lines)
      Poker:CapRaise(PS, myPlayer, currentBet, remainingRaise) -> remainingRaise
]]

local BJ = ChairfacesCasino
local UI = BJ.UI

local PokerTable = {}
UI.PokerTable = PokerTable

function PokerTable:Embed(Poker, cfg)
    local KEY, NAME = cfg.key, cfg.name
    local STATE, NET = cfg.state, cfg.net

    -- Trixie beside the table, moods and the show/hide setting
    UI.GameWindow:EmbedTrixie(Poker, KEY)

    -- host-away pause / void messages (UI/GameWindow.lua)
    UI.GameWindow:EmbedRecovery(Poker, { net = function() return BJ[NET] end })
    function Poker:OnRecoveryPause(originalHost, tempHost, iAmTempHost)
        -- only the temporary host may reset the paused table
        if self.buttons and self.buttons.reset then self.buttons.reset:SetShown(iAmTempHost) end
    end

    -- the shared "last games" log window (UI/GameLog.lua)
    UI.GameLog:Embed(Poker, {
        name = cfg.logFrameName, title = NAME,
        state = function() return BJ[STATE] end,
        anchor = function() return Poker.mainFrame end,
    })

    -- ===== Hooks: defaults are 5 Card Stud's rules; Hold'em overrides =====
    function Poker:CreateDealerExtras(dealerArea) end
    function Poker:UpdateTableExtras() end
    function Poker:CreateExtraButtons(buttonArea, createButton) end
    function Poker:UpdateExtraButtons(PS, isHost) end
    function Poker:BlocksNewTable(PS) return false end
    function Poker:StakesText(PS) return string.format("Ante: %dg", PS.ante or 0) end
    function Poker:AnteForJoin(PS) return PS.ante end
    function Poker:ExtendHostPanel(form) end
    function Poker:ReadHostPanelExtras(form) return nil end
    function Poker:BuildTableSettings(ante, maxRaise, maxPlayers, cdOn, cdSecs, extra)
        return {
            ante = ante,
            maxRaise = maxRaise,
            maxPlayers = maxPlayers,
            countdownEnabled = cdOn,
            countdownSeconds = cdSecs,
        }
    end
    function Poker:DecorateHand(hand) end
    function Poker:DecorateHandLabel(hand, name, player, label) return label end
    function Poker:PotUnit(PS) return "g" end
    function Poker:ExtendSettlement(PS, lines) end
    function Poker:CapRaise(PS, myPlayer, currentBet, remainingRaise) return remainingRaise end

    -- Play area: one fixed layout. Trixie stands beside the window
    -- (UI.GameWindow:EmbedTrixie), so nothing inside makes room for her.
    local PLAY_AREA_WIDTH = 920
    local PLAY_AREA_OFFSET = 10
    local FRAME_WIDTH = PLAY_AREA_WIDTH + 20   -- 940px
    local FRAME_HEIGHT = 520

    function Poker:GetPlayAreaOffset() return PLAY_AREA_OFFSET end

    -- Player grid: 5 cols x 2 rows visible
    local PLAYER_COLS = 5
    local PLAYER_CELL_WIDTH = 185  -- More horizontal separation (+10)
    local PLAYER_CELL_HEIGHT = 130  -- More space between rows

    -- Test player names
    Poker.testPlayerNames = {
        "Thrall Frostwolf", "Sylvanas Windrunner", "Arthas Menethil", "Jaina Proudmoore", "Tyrande Whisperwind",
        "Malfurion Stormrage", "Illidan Stormrage", "Vashj Tidebinder", "Kelthuzad Lich", "Uther Lightbringer",
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
        -- Shared casino window (UI/Chrome.lua): felt table, How to Play on
        -- the left of the title band; leaderboard, debts, refresh and X on
        -- the right. The X goes back to the lobby.
        local frame = UI.Chrome:CreateWindow({
            name = cfg.frameName,
            title = NAME,
            width = FRAME_WIDTH, height = FRAME_HEIGHT,
            art = "felt", artW = 1280, artH = 714,
            howTo = KEY,
            debts = true,
            onLog = function() Poker:ToggleLog() end,
            leaderboard = KEY,
            onRefresh = function()
                Poker:Hide()
                C_Timer.After(0.05, function() Poker:Show() end)
            end,
            onClose = function()
                Poker:Hide()
                if UI.Lobby then UI.Lobby:Show() end
            end,
        })
        local titleBar = frame.titleBar
        self.titleBar = titleBar
        self.titleText = frame.titleText
        self.sessionBtn = frame.debtsBtn
        self.allTimeBtn = frame.leaderboardBtn

        -- Info text (centered below title bar)
        local infoText = frame:CreateFontString(nil, "OVERLAY", "CCFontSmall")
        infoText:SetPoint("TOP", titleBar, "BOTTOM", 0, -5)
        infoText:SetTextColor(0.8, 0.8, 0.8, 1)
        frame.infoText = infoText
        self.infoText = infoText

        self.mainFrame = frame

        -- Create components
        self:CreateDealerArea()
        self:CreateActionButtons()
        self:CreateStatusBar()
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

        -- Trixie deals from beside the table
        self:MountTrixie(self.mainFrame)

        -- Pot display (center of play area)
        local potFrame = CreateFrame("Frame", nil, dealerArea, "BackdropTemplate")
        potFrame:SetSize(120, 50)
        if cfg.potLeft then
            potFrame:SetPoint("LEFT", dealerArea, "LEFT", 30, 0)   -- leaves the middle to the board
        else
            potFrame:SetPoint("CENTER", dealerArea, "CENTER", 0, 0)
        end
        potFrame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
        potFrame:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
        potFrame:SetBackdropBorderColor(0.6, 0.5, 0.2, 1)

        local potLabel = potFrame:CreateFontString(nil, "OVERLAY", "CCFontNormal")
        potLabel:SetPoint("TOP", 0, -8)
        potLabel:SetText("|cffffd700POT|r")

        local potAmount = potFrame:CreateFontString(nil, "OVERLAY", "CCFontLarge")
        potAmount:SetPoint("BOTTOM", 0, 8)
        potAmount:SetFont("Fonts\\FRIZQT__.TTF", 20, "OUTLINE")
        potAmount:SetText("|cffffffff0g|r")
        self.potAmount = potAmount
        self.potFrame = potFrame

        -- the visual pot: denomination chip stacks to the RIGHT of the pot
        -- box (above collides with the header)
        if UI.ChipPot then
            local chips = UI.ChipPot:Attach(potFrame)
            chips:SetPoint("BOTTOMLEFT", potFrame, "BOTTOMRIGHT", 8, 4)
            self.potChips = chips
        end

        potFrame:Hide()

        -- Settlement list (top-right corner, shown during settlement)
        -- Left edge should not extend past host button's right edge
        -- Host button: centered at PLAY_AREA_OFFSET/2 (147px from center), 180px wide = right edge at center+237
        -- Frame is 1214px wide, center at 607, so host button right edge at ~844px from left
        -- Settlement at TOPRIGHT -10 means right edge at 1204, so max width = 1204 - 844 = 360px
        local settlementFrame = CreateFrame("Frame", nil, self.mainFrame, "BackdropTemplate")
        -- Width constrained to not overlap the host button; cfg.settlementTop
        -- drops it below table furniture (Hold'em's community cards)
        settlementFrame:SetSize(360, cfg.settlementMaxH or 315)
        settlementFrame:SetPoint("TOPRIGHT", self.mainFrame, "TOPRIGHT", -10, cfg.settlementTop or -40)
        settlementFrame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
        settlementFrame:SetBackdropColor(0.05, 0.05, 0.05, 1)  -- Fully opaque
        settlementFrame:SetBackdropBorderColor(1, 0.84, 0, 1)  -- Gold border like blackjack
        settlementFrame:SetFrameLevel(self.mainFrame:GetFrameLevel() + 10)

        local settlementTitle = settlementFrame:CreateFontString(nil, "OVERLAY", "CCFontLarge")
        settlementTitle:SetPoint("TOP", 0, -11)
        settlementTitle:SetText("Settlement")
        settlementTitle:SetTextColor(1, 0.84, 0, 1)
        settlementTitle:SetFont("Fonts\\FRIZQT__.TTF", 20)  -- 14*1.4

        -- Scrollable body so a long ledger scrolls instead of spilling out of
        -- the frame and overlapping the table below (same pattern as Hold'em)
        local settlementScroll = CreateFrame("ScrollFrame", nil, settlementFrame, "UIPanelScrollFrameTemplate")
        settlementScroll:SetPoint("TOPLEFT", settlementFrame, "TOPLEFT", 17, -42)  -- below title
        settlementScroll:SetPoint("BOTTOMRIGHT", settlementFrame, "BOTTOMRIGHT", -34, 12)  -- room for scrollbar

        local settlementContent = CreateFrame("Frame", nil, settlementScroll)
        settlementContent:SetSize(309, 1)  -- 360 - 17 left pad - 34 right pad
        settlementScroll:SetScrollChild(settlementContent)

        local settlementText = settlementContent:CreateFontString(nil, "OVERLAY", "CCFontNormal")
        settlementText:SetPoint("TOPLEFT", 0, 0)
        settlementText:SetWidth(309)
        settlementText:SetJustifyH("LEFT")
        settlementText:SetJustifyV("TOP")
        settlementText:SetFont("Fonts\\FRIZQT__.TTF", 17, "OUTLINE")  -- 12*1.4
        settlementText:SetText("")
        if settlementScroll.ScrollBar then
            settlementScroll.ScrollBar:Hide()  -- only shown when content overflows
        end
        self.settlementText = settlementText
        self.settlementScroll = settlementScroll
        self.settlementContent = settlementContent
        self.settlementFrame = settlementFrame
        settlementFrame:Hide()

        -- Action announcement text (large text under pot that fades)
        local actionText = dealerArea:CreateFontString(nil, "OVERLAY", "CCFontLarge")
        actionText:SetPoint("TOP", potFrame, "BOTTOM", 0, -10)
        actionText:SetFont("Fonts\\FRIZQT__.TTF", 18, "OUTLINE")
        actionText:SetTextColor(1, 0.84, 0, 1)
        actionText:SetText("")
        self.actionText = actionText
        self.actionTextFadeStart = 0

        self.dealerArea = dealerArea
        self:CreateDealerExtras(dealerArea)
    end

    function Poker:CreateActionButtons()
        local buttonArea = CreateFrame("Frame", nil, self.mainFrame)
        buttonArea:SetSize(PLAY_AREA_WIDTH - 20, 50)
        -- Center in play area (aligned with pot)
        buttonArea:SetPoint("BOTTOM", self.mainFrame, "BOTTOM", PLAY_AREA_OFFSET / 2, 15)

        self.buttons = {}
        self.buttonArea = buttonArea

        -- Theme button; `color` is the old rgb hint, mapped to a role
        -- (green = go, red = danger, gold = primary, blue/grey = secondary)
        local function createButton(parent, name, text, width, color)
            local variant = color and BJ.Theme:VariantFromRGB(unpack(color)) or "go"
            local btn = BJ.Theme:Button(parent, text, width, 32, variant)
            self.buttons[name] = btn
            return btn
        end

        -- Main button bar: FOLD, CHECK/CALL, [input], RAISE (X), MAX RAISE (Y)
        local btnConfigs = {
            { name = "fold", text = "FOLD", width = 60, color = {0.4, 0.15, 0.15} },
            { name = "checkCall", text = "CHECK", width = 70 },
        }

        local totalWidth = 0
        for _, bc in ipairs(btnConfigs) do
            totalWidth = totalWidth + bc.width + 5
        end
        -- Add space for: input(50) + raise(80) + maxRaise(90) + gaps
        totalWidth = totalWidth + 50 + 5 + 80 + 5 + 90

        local startX = -totalWidth / 2

        for _, bc in ipairs(btnConfigs) do
            local btn = createButton(buttonArea, bc.name, bc.text, bc.width, bc.color)
            btn:SetPoint("LEFT", buttonArea, "CENTER", startX, 0)
            startX = startX + bc.width + 5
        end

        -- Raise input box
        local raiseInput = CreateFrame("EditBox", nil, buttonArea, "BackdropTemplate")
        raiseInput:SetSize(50, 28)
        raiseInput:SetPoint("LEFT", buttonArea, "CENTER", startX, 0)
        raiseInput:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        raiseInput:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
        raiseInput:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
        raiseInput:SetFontObject("CCFontNormal")
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



        -- DEAL button (hidden by default, shown only when host and active)
        local dealBtn = createButton(buttonArea, "deal", "DEAL", 60)
        dealBtn:SetPoint("RIGHT", self.buttons.fold, "LEFT", -10, 0)
        dealBtn:Hide()

        -- RESET button in bottom right corner (inside brown border)
        local resetBtn = createButton(self.mainFrame, "reset", "RESET", 60, {0.4, 0.3, 0.1})
        resetBtn:SetPoint("BOTTOMRIGHT", self.mainFrame, "BOTTOMRIGHT", -15, 15)

        self:CreateExtraButtons(buttonArea, createButton)

        self.buttons.deal:SetScript("OnClick", function() self:OnDealClick() end)
        self.buttons.reset:SetScript("OnClick", function() self:OnResetClick() end)
        self.buttons.fold:SetScript("OnClick", function() self:OnFoldClick() end)
        self.buttons.checkCall:SetScript("OnClick", function() self:OnCheckCallClick() end)
        self.buttons.raise:SetScript("OnClick", function() self:OnRaiseClick() end)
        self.buttons.maxRaise:SetScript("OnClick", function() self:OnMaxRaiseClick() end)

        -- Create centered action button (Host/Join)
        self:CreateTableActionButton()
    end

    -- Create the centered Host/Join action button for Poker
    function Poker:CreateTableActionButton()
        -- centred in the play area (aligned with the pot)
        local btn = UI.GameWindow:CallToAction(self.mainFrame, cfg.prefix .. "ActionButton",
            function() Poker:OnTableActionButtonClick() end)
        btn:SetPoint("CENTER", self.mainFrame, "CENTER", PLAY_AREA_OFFSET / 2, 0)
        self.actionButton = btn
    end

    function Poker:OnTableActionButtonClick()
        local PS = BJ[STATE]
        local PM = BJ[NET]

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
    function Poker:UpdateTableActionButton()
        if not self.actionButton then return end

        -- Clear FREE PLAY badge by default; only the JOIN branch re-shows it.
        if BJ.UI and BJ.UI.Debts then
            BJ.UI.Debts:SetJoinFakeBadge(self.actionButton, false)
        end

        local PS = BJ[STATE]
        local PM = BJ[NET]
        local myName = BJ:MyName()
        local inTestMode = BJ.TestMode and BJ.TestMode.enabled
        local inPartyOrRaid = IsInGroup() or IsInRaid()
        local canHost = inTestMode or inPartyOrRaid

        -- Check if ANY game is in session (not idle, not settlement)
        local Lobby = BJ.Lobby
        local anyGameInSession = false
        if Lobby and Lobby.IsGameInSession then
            anyGameInSession = Lobby:IsGameInSession("blackjack") or 
                              Lobby:IsGameInSession(KEY) or 
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
                if BJ.UI and BJ.UI.Debts then
                    BJ.UI.Debts:SetJoinFakeBadge(self.actionButton, PS.fakePlay == true)
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

        -- Hide during active game phases (betting, showdown, etc)
        local gameActive = PS.phase ~= PS.PHASE.IDLE and PS.phase ~= PS.PHASE.SETTLEMENT
        if gameActive then
            self.actionButton:Hide()
            return
        end

        -- During settlement, anyone who can host should see HOST button -
        -- unless the game holds the table (a tournament between hands)
        if PS.phase == PS.PHASE.SETTLEMENT and self:BlocksNewTable(PS) then
            self.actionButton:Hide()
            return
        end
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
            self.lastInSession = Lobby:IsGameInSession(KEY)
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
                local inSession = Lobby:IsGameInSession(KEY)
                local hiloInSession = Lobby:IsGameInSession("hilo")

                if bjInSession ~= self.lastBjInSession or 
                   inSession ~= self.lastInSession or 
                   hiloInSession ~= self.lastHiloInSession then
                    -- State changed, update action button
                    self:UpdateTableActionButton()
                    self.lastBjInSession = bjInSession
                    self.lastInSession = inSession
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

        local text = statusBar:CreateFontString(nil, "OVERLAY", "CCFontNormal")
        text:SetPoint("CENTER")
        text:SetTextColor(1, 0.84, 0, 1)
        text:SetText("Welcome to " .. NAME .. "!")
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
        turnTimer.warning:SetText("|cffff8800Auto-check/fold soon!|r")
        turnTimer.warning:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
        turnTimer:Hide()

        self.turnTimerFrame = turnTimer
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

        local rowIndicator = rowIndicatorFrame:CreateFontString(nil, "OVERLAY", "CCFontNormal")
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
        local GW = UI.GameWindow
        local bar = GW:TestBar(self, self.mainFrame, GW:Specs({
            { text = "+PLAYER", width = 60, onClick = function() self:AddTestPlayer() end },
            { text = "-PLAYER", width = 60, onClick = function() self:RemoveTestPlayer() end },
            { text = "CLEAR", width = 50, onClick = function() self:ClearTestPlayers() end },
            { text = "DEAL", width = 50, onClick = function()
                if BJ[NET] and BJ[NET].isHost then BJ[NET]:StartDeal() end
            end },
            { key = "auto", text = "AUTO*", width = 55, variant = "go", onClick = function()
                self.autoPlayEnabled = not self.autoPlayEnabled
                self:UpdateAutoPlayButton()
                self:UpdateDisplay()
            end },
        }, GW:CommonTestTools(self)))
        self.testModeBar = bar
        self.autoPlayBtn = bar.buttons.auto
        self.trixToggleBtn = bar.buttons.trix
        self.testPlayerCount = bar:AddText("countText", 90)
        self.testPlayerCount:SetText("Players: 0/10")
    end

    function Poker:CreateHostPanel()
        -- the shared host settings popup (UI/HostForm.lua)
        local form = UI.HostForm:Create({
            name = cfg.prefix .. "HostPanel",
            title = NAME .. " - Host",
            onStart = function(f)
                local cdOn, cdSecs = f:Get(KEY .. "CountdownSeconds")
                local extra = Poker:ReadHostPanelExtras(f)
                f:Hide()
                Poker:OnHostClick(f:Get(KEY .. "Ante"), f:Get(KEY .. "MaxRaise"),
                    f:Get(KEY .. "MaxPlayers"), cdOn, cdSecs, extra)
            end,
        })
        form:Number(KEY .. "Ante", cfg.anteLabel or "Ante (1-1000g):",
            { default = 10, min = cfg.anteMin or 1, max = 1000, unit = "g" })
        form:Number(KEY .. "MaxRaise", "The Cap (1-1000g):", {
            default = 100, min = 1, max = 1000, unit = "g",
            tooltip = { "The Cap", "The maximum total amount that can be bet across all players each round.",
                "Once the cap is reached, no further raises are allowed - players can only call or fold." },
        })
        form:Choice(KEY .. "MaxPlayers", "Max Players:", { 2, 3, 4, 5, 6, 7, 8, 9, 10 }, {
            default = 10, buttonWidth = 26, status = function(v) return "(" .. v .. " max)" end,
        })
        form:Countdown(KEY .. "CountdownEnabled", KEY .. "CountdownSeconds", "Time to Join / Deal:")
        self:ExtendHostPanel(form)
        form:Finish()
        self.hostForm = form
        self.hostPanel = form.frame
    end

    function Poker:UpdateCountdownButtons()
        if self.hostForm then self.hostForm:Refresh() end
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
        if self.hostForm then self.hostForm:Show() end
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

        -- Surface a deferred "newer version in your group" warning if one is pending
        if BJ.ShowPendingVersionWarning then
            BJ:ShowPendingVersionWarning()
        end
    end

    function Poker:Hide()
        if self.mainFrame then self.mainFrame:Hide() end
        if self.hostPanel then self.hostPanel:Hide() end
        if self.logFrame then self.logFrame:Hide() end
        -- Stop the refresh ticker
        self:StopActionButtonRefreshTicker()
    end

    function Poker:UpdateTestModeLayout()
        self:RefreshTestBar()
    end

    function Poker:UpdateAutoPlayButton()
        if not self.autoPlayBtn then return end
        BJ.Theme:SetButton(self.autoPlayBtn, self.autoPlayEnabled and "AUTO*" or "AUTO", true,
            self.autoPlayEnabled and "go" or "danger")
    end

    function Poker:OnHostClick(ante, maxRaise, maxPlayers, countdownEnabled, countdownSeconds, extra)
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

        ante = ante or BJ.HostSettings:Get(KEY .. "Ante") or 10
        maxRaise = maxRaise or BJ.HostSettings:Get(KEY .. "MaxRaise") or 100
        maxPlayers = maxPlayers or BJ.HostSettings:Get(KEY .. "MaxPlayers") or 10
        countdownEnabled = countdownEnabled or false
        countdownSeconds = countdownSeconds or BJ.HostSettings:Get(KEY .. "CountdownSeconds") or 15
        local settings = self:BuildTableSettings(ante, maxRaise, maxPlayers,
            countdownEnabled, countdownSeconds, extra)
        if BJ[NET] then BJ[NET]:HostTable(settings) end
    end

    function Poker:OnDealClick()
        if BJ[NET] and BJ[NET].isHost then
            BJ[NET]:StartDeal()
        end
    end

    function Poker:OnResetClick()
        -- Confirm dialog before reset
        StaticPopupDialogs[cfg.resetPopup] = {
            text = "|cffffd700Reset " .. NAME .. " Game?|r\n\nThis will cancel the current game for all players.",
            button1 = "Reset",
            button2 = "Cancel",
            OnAccept = function()
                if BJ[NET] then BJ[NET]:ResetGame() end
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
        StaticPopup_Show(cfg.resetPopup)
    end

    function Poker:OnJoinClick()
        local PS = BJ[STATE]
        if BJ[NET] then BJ[NET]:PlaceAnte(self:AnteForJoin(PS)) end
    end

    function Poker:OnFoldClick()
        if BJ[NET] then BJ[NET]:PlayerAction("fold") end
    end

    -- Combined Check/Call button - determines action based on current state
    function Poker:OnCheckCallClick()
        local PS = BJ[STATE]
        local myName = BJ:MyName()
        local myPlayer = PS.players[myName]

        if not myPlayer then return end

        local playerBet = myPlayer.currentBet or 0
        local toCall = (PS.currentBet or 0) - playerBet

        if toCall <= 0 then
            -- Can check
            if BJ[NET] then BJ[NET]:PlayerAction("check") end
        else
            -- Must call
            if BJ[NET] then BJ[NET]:PlayerAction("call") end
        end
    end

    function Poker:OnRaiseClick()
        local amount = tonumber(self.raiseInput:GetText()) or 10
        if BJ[NET] then BJ[NET]:PlayerAction("raise", amount) end
    end

    -- Test mode functions
    function Poker:AddTestPlayer()
        local PS = BJ[STATE]
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
                    PS:PlayerAnte(name, self:AnteForJoin(PS))
                    self:OnPlayerAnted(name, self:AnteForJoin(PS))
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
        local PS = BJ[STATE]
        if PS.phase ~= PS.PHASE.WAITING_FOR_PLAYERS then return end
        for _, name in ipairs(self.testPlayers) do
            if not PS.players[name] then
                PS:PlayerAnte(name, self:AnteForJoin(PS))
                self:OnPlayerAnted(name, self:AnteForJoin(PS))
            end
        end
    end

    function Poker:UpdateTestPlayerCount()
        if not self.testPlayerCount then return end
        local PS = BJ[STATE]
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
        self:UpdateTableExtras()
        self:UpdatePot()
        self:UpdateStatus()
        self:UpdateButtons()
        self:UpdateTestPlayerCount()
    end

    function Poker:UpdateInfoText()
        local PS = BJ[STATE]
        local PM = BJ[NET]

        if not self.infoText then return end

        if PM and PM.tableOpen then
            local hostName = PM.currentHost or "?"
            local maxRaise = PS.maxRaise or 0
            local remaining = PS:GetRemainingCards()
            local seedText = PS.seed and (" | Seed: " .. PS.seed) or ""
            self.infoText:SetText(string.format("Host: %s | %s | Cap: %dg | Remaining Cards: %d%s",
                BJ:SeatName(hostName), self:StakesText(PS), maxRaise, remaining, seedText))
        else
            self.infoText:SetText("")
        end
    end

    function Poker:UpdatePlayerHands()
        -- Guard against uninitialized UI
        if not self.isInitialized or not self.playerArea then
            return
        end

        local PS = BJ[STATE]
        local myName = BJ:MyName()
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
                    local newHand = self:CreateCompactHandDisplay(container, cfg.prefix .. "Hand" .. (#self.playerArea.hands + 1))
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

        hand.label = hand:CreateFontString(nil, "OVERLAY", "CCFontNormal")
        hand.label:SetPoint("TOP", 0, 0)
        hand.label:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")

        hand.cardContainer = CreateFrame("Frame", nil, hand)
        hand.cardContainer:SetSize(150, UI.Cards.CARD_HEIGHT)
        hand.cardContainer:SetPoint("TOP", hand.label, "BOTTOM", 0, -8)  -- More space between name and cards

        hand.cards = {}

        -- Hand rank text (shows during settlement) - use higher draw layer to display above cards
        hand.handRank = hand:CreateFontString(nil, "OVERLAY", "CCFontSmall")
        hand.handRank:SetPoint("TOP", hand.cardContainer, "BOTTOM", 0, -9)  -- Lowered 5pts
        hand.handRank:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
        hand.handRank:SetDrawLayer("OVERLAY", 7)  -- Higher sublayer to appear above cards
        hand.handRank:Hide()

        self:DecorateHand(hand)
        return hand
    end

    function Poker:UpdateCompactHandDisplay(handDisplay, playerName, cardsToShow, player, isShowdown)
        local PS = BJ[STATE]

        local isCurrentPlayer = (PS.phase == PS.PHASE.BETTING and PS:GetCurrentPlayer() == playerName)
        -- Two-word Forever names can run to 25 characters: short form on a seat.
        local seatName, wholeName = BJ:SeatName(playerName, PS.playerOrder)
        local label = seatName
        if isCurrentPlayer then
            label = "|cff00ff00>> " .. seatName .. " <<|r"
        elseif player.folded then
            label = "|cff666666" .. seatName .. " (FOLD)|r"
        end
        label = self:DecorateHandLabel(handDisplay, playerName, player, label)
        handDisplay.label:SetText(label)
        BJ:FitNameFont(handDisplay.label, wholeName)

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
        local cardSpacing = UI.Cards:GetFanSpacing(#cardsToShow, handDisplay.cardContainer:GetWidth() or 150)
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
        local PS = BJ[STATE]
        if PS.pot > 0 then
            self.potAmount:SetText("|cffffffff" .. PS.pot .. self:PotUnit(PS) .. "|r")
            self.potFrame:Show()
        else
            self.potFrame:Hide()
        end
        if self.potChips then self.potChips:SetAmount(PS.pot or 0) end

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
        local PS = BJ[STATE]
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

        self:ExtendSettlement(PS, lines)

        local text = table.concat(lines, "\n")
        self.settlementText:SetText(text)

        -- Size the frame to the rendered text (wrapped lines included), capped
        -- at the original 315px footprint - past the cap the body scrolls.
        local MAX_FRAME_HEIGHT = cfg.settlementMaxH or 315
        local textHeight = math.ceil(self.settlementText:GetStringHeight() or 0)
        self.settlementContent:SetHeight(math.max(1, textHeight))

        local desired = textHeight + 42 + 17
        local frameHeight = math.max(84, math.min(MAX_FRAME_HEIGHT, desired))
        self.settlementFrame:SetSize(360, frameHeight)

        local scrollBar = self.settlementScroll.ScrollBar
        if desired > MAX_FRAME_HEIGHT then
            if scrollBar then scrollBar:Show() end
        else
            self.settlementScroll:SetVerticalScroll(0)
            if scrollBar then scrollBar:Hide() end
        end

        BJ:Debug("UpdateSettlementList: displayed " .. #lines .. " lines, textHeight=" .. textHeight)
    end

    function Poker:UpdateStatus()
        local PS = BJ[STATE]
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
            if currentPlayer == BJ:MyName() then
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
        local PS = BJ[STATE]
        local PM = BJ[NET]
        local myName = BJ:MyName()
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


        -- Update centered action button (Host/Join)
        self:UpdateTableActionButton()

        -- DEAL button - only show for host when deal is available
        if isHost and PS.phase == PS.PHASE.WAITING_FOR_PLAYERS and #PS.playerOrder >= 2 then
            self.buttons.deal:SetEnabled(true)
            self.buttons.deal:Show()
        else
            self.buttons.deal:SetEnabled(false)
            self.buttons.deal:Hide()
        end

        self:UpdateExtraButtons(PS, isHost)

        -- RESET button - always enabled for host when not idle
        if isHost and PS.phase ~= PS.PHASE.IDLE then
            self.buttons.reset:SetEnabled(true)
        end

        local myPlayer = PS.players[myName]
        -- Folding is only allowed on your own turn (engine enforces this too)
        local canFold = isMyTurn and inGame and myPlayer and not myPlayer.folded and PS.phase == PS.PHASE.BETTING
        self.buttons.fold:SetEnabled(canFold)

        -- Calculate max remaining raise for this round
        local maxRaise = PS.maxRaise or 100
        local currentBet = PS.currentBet or 0
        local remainingRaise = maxRaise - currentBet
        if remainingRaise < 0 then remainingRaise = 0 end
        remainingRaise = self:CapRaise(PS, myPlayer, currentBet, remainingRaise)
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
        local PS = BJ[STATE]
        local maxRaise = self.maxRemainingRaise or 0
        if maxRaise > 0 then
            -- Set the input to max and call raise
            if self.raiseInput then
                self.raiseInput:SetText(tostring(maxRaise))
            end
            self:OnRaiseClick()
        end
    end

    function Poker:GetHandDisplayForPlayer(playerName)
        local PS = BJ[STATE]
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
        -- (same squeezed spacing the final render uses, so the card lands in place)
        local numCards = self.dealtCards[playerName] or 0
        local cardSpacing = UI.Cards:GetFanSpacing(numCards + 1, cardContainer:GetWidth() or 150)
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
        local PS = BJ[STATE]
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
        if UI.Lobby then UI.Lobby:PlayTrixieVoice("poker_showdown", { cd = 5 }) end
        local PS = BJ[STATE]
        for playerName, player in pairs(PS.players) do
            self.dealtCards[playerName] = #player.hand
        end
        self:UpdateDisplay()
    end

    function Poker:OnSettlement()
        if not self.isInitialized then return end
        local PS = BJ[STATE]
        local myName = BJ:MyName()

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
            self.statusBar.text:SetText("Deal in " .. remaining .. "s... (" .. #BJ[STATE].playerOrder .. " players)")
        end
    end

    --[[
        HOST RECOVERY UI HANDLERS
    ]]

    return Poker
end
