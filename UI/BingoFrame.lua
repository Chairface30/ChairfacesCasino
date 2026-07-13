--[[
    Chairface's Casino - UI/BingoFrame.lua
    Bingo game window: EVERY player's auto-daubing 5x5 card in a scrolling
    grid on the left (grows up to 3 cards wide, then 2 tall, then scrolls),
    with the caller panel (current ball, recent calls, pot, players) on
    the right. Each card carries its owner's name above it.
]]

local BJ = ChairfacesCasino
local UI = BJ.UI

UI.Bingo = {}
local BUI = UI.Bingo

-- Card geometry: cells are ~33% smaller than the original single-card view
local CELL_SIZE = 35
local CELL_GAP = 3
local CARD_W = 5 * CELL_SIZE + 4 * CELL_GAP   -- 187
local NAME_H = 16
local CARD_H = CARD_W + NAME_H                -- owner name row + square grid
local CARD_GAP = 10
local MAX_COLS = 3         -- expand up to 3 cards wide...
local MAX_VIS_ROWS = 2     -- ...then 2 tall, then scroll

local GRID_LEFT = 18
local GRID_TOP = -70
local PANEL_W = 250
local SCROLLBAR_W = 28
local MIN_WIDTH = 520
local MIN_HEIGHT = 470

function BUI:Initialize()
    if self.frame then return end
    self:CreateFrame()
end

function BUI:CreateFrame()
    local frame = CreateFrame("Frame", "ChairfacesCasinoBingo", UIParent, "BackdropTemplate")
    frame:SetSize(MIN_WIDTH, MIN_HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    frame:SetFrameStrata("HIGH")
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    frame:SetBackdropColor(0.05, 0.04, 0.06, 0.97)   -- dark fallback if art missing
    frame:SetBackdropBorderColor(0.6, 0.5, 0.2, 1)

    -- Table-felt background, same as the poker games and High-Lo. Sub-level 1
    -- keeps it above the backdrop's fill; aspect-fit texcoords match PokerFrame.
    -- Bingo resizes its frame dynamically, so refresh the texcoords on resize.
    local bgTexture = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    bgTexture:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\tablefelt_bg")
    bgTexture:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -2)
    bgTexture:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
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
    frame:HookScript("OnSizeChanged", UpdateFeltTexCoords)

    frame:Hide()
    self.frame = frame

    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("|cffffd700Bingo|r")
    title:SetFont("Fonts\\FRIZQT__.TTF", 20, "OUTLINE")

    -- Close button (returns to the lobby)
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function()
        BUI:Hide()
        if UI.Lobby then
            UI.Lobby:Show()
        end
    end)

    -- Debts shortcut (settle-up ledger) next to the close button
    if UI.Debts and UI.Debts.AttachDebtsIcon then
        UI.Debts:AttachDebtsIcon(frame, "RIGHT", closeBtn, "LEFT", -2, 0)
    end

    -- How to Play (top-left, like the Derby window)
    if UI.Lobby and UI.Lobby.AttachHowToPlayButton then
        UI.Lobby:AttachHowToPlayButton(frame, "bingo", 8, -8)
    end

    -- Trixie deals here too
    if UI.Lobby and UI.Lobby.AttachTrixie then
        UI.Lobby:AttachTrixie(frame, "bingo")
    end

    -- Status line
    local status = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    status:SetPoint("TOP", title, "BOTTOM", 0, -6)
    status:SetWidth(MIN_WIDTH - 30)
    status:SetText("")
    self.statusText = status

    -- Scrolling card area (left) - all players' cards live in here
    local cardScroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    cardScroll:SetPoint("TOPLEFT", frame, "TOPLEFT", GRID_LEFT, GRID_TOP)
    cardScroll:SetSize(CARD_W, CARD_H)

    local cardContent = CreateFrame("Frame", nil, cardScroll)
    cardContent:SetSize(CARD_W, CARD_H)
    cardScroll:SetScrollChild(cardContent)

    -- Keep the hint's hidden-card counts in step with the scroll position
    cardScroll:HookScript("OnVerticalScroll", function()
        BUI:UpdateScrollHint()
    end)

    self.cardScroll = cardScroll
    self.cardContent = cardContent
    self.cardFrames = {}

    -- Big, obvious cue that more cards are hiding below the fold
    local scrollHint = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    scrollHint:SetPoint("TOP", cardScroll, "BOTTOM", 0, -4)
    scrollHint:SetText("")
    self.scrollHint = scrollHint

    -- Right-hand caller panel: fixed width, pinned to the right edge so the
    -- card area can grow independently as players join
    local panel = CreateFrame("Frame", nil, frame)
    panel:SetWidth(PANEL_W)
    panel:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -14, GRID_TOP + 18)
    panel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 14)
    self.callerPanel = panel

    local ballLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ballLabel:SetPoint("TOPLEFT", 8, 0)
    ballLabel:SetText("|cffccaa66LAST CALL|r")

    local ball = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    ball:SetPoint("TOPLEFT", ballLabel, "BOTTOMLEFT", 0, -4)
    ball:SetFont("Fonts\\FRIZQT__.TTF", 36, "OUTLINE")
    ball:SetText("--")
    self.ballText = ball

    local drawCount = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    drawCount:SetPoint("TOPLEFT", ball, "BOTTOMLEFT", 0, -4)
    drawCount:SetText("")
    self.drawCountText = drawCount

    local recent = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    recent:SetPoint("TOPLEFT", drawCount, "BOTTOMLEFT", 0, -8)
    recent:SetWidth(PANEL_W - 16)
    recent:SetJustifyH("LEFT")
    recent:SetText("")
    self.recentText = recent

    local potText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    potText:SetPoint("TOPLEFT", recent, "BOTTOMLEFT", 0, -12)
    potText:SetText("")
    self.potText = potText

    local playersText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    playersText:SetPoint("TOPLEFT", potText, "BOTTOMLEFT", 0, -8)
    playersText:SetWidth(PANEL_W - 16)
    playersText:SetJustifyH("LEFT")
    playersText:SetJustifyV("TOP")
    playersText:SetHeight(90)
    playersText:SetText("")
    self.playersText = playersText

    -- Card price input (host, idle only)
    local priceBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    priceBox:SetSize(70, 24)
    priceBox:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 16, 96)
    priceBox:SetAutoFocus(false)
    priceBox:SetNumeric(true)
    priceBox:SetMaxLetters(6)
    priceBox:SetText(tostring(BJ.HostSettings and BJ.HostSettings:Get("bingoPrice") or 10))
    priceBox:SetScript("OnEnterPressed", function(box) box:ClearFocus() end)
    priceBox:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)
    self.priceBox = priceBox

    local priceLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    priceLabel:SetPoint("BOTTOM", priceBox, "TOP", -3, 3)
    priceLabel:SetText("|cffffd700Card price (g)|r")
    self.priceLabel = priceLabel

    -- Fake play (fun games record no debts) right where hosting starts
    if BJ.UI.Debts and BJ.UI.Debts.AttachFakePlayCheck then
        BJ.UI.Debts:AttachFakePlayCheck(panel, "LEFT", priceBox, "RIGHT", 8, 0)
    end

    -- Primary + secondary action buttons (context-sensitive)
    local function makeButton(yOffset)
        local btn = CreateFrame("Button", nil, panel, "BackdropTemplate")
        btn:SetSize(170, 32)
        btn:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 8, yOffset)
        btn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
        local text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        text:SetPoint("CENTER")
        btn.text = text
        return btn
    end

    local actionBtn = makeButton(54)
    actionBtn:SetScript("OnClick", function() BUI:OnActionClick() end)
    self.actionBtn = actionBtn

    local cancelBtn = makeButton(16)
    cancelBtn:SetScript("OnClick", function() BUI:OnCancelClick() end)
    self.cancelBtn = cancelBtn

    -- Result banner (bottom-left, under the cards)
    local resultText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    resultText:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", GRID_LEFT, 14)
    resultText:SetWidth(CARD_W)
    resultText:SetJustifyH("LEFT")
    resultText:SetText("")
    self.resultText = resultText

    -- Purple test-mode bar (debug tools, GUI counterpart to /cc test ...)
    self:CreateTestBar()

    -- Register Escape-key close
    if BJ.EscapeHandler then
        BJ.EscapeHandler:RegisterFrame("ChairfacesCasinoBingo")
    end
end

--[[
    TEST BAR (visible only while /cc db test mode is on)
]]
function BUI:CreateTestBar()
    local bar = CreateFrame("Frame", nil, self.frame, "BackdropTemplate")
    bar:SetSize(340, 35)
    bar:SetPoint("TOP", self.frame, "BOTTOM", 0, -5)
    bar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
    bar:SetBackdropColor(0.15, 0.1, 0.2, 0.95)
    bar:SetBackdropBorderColor(1, 0.4, 1, 1)

    local label = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", 10, 0)
    label:SetText("|cffff00ffTEST|r")

    local function makeBtn(text, width, anchorTo, onClick)
        local btn = CreateFrame("Button", nil, bar, "BackdropTemplate")
        btn:SetSize(width, 24)
        btn:SetPoint("LEFT", anchorTo, "RIGHT", 6, 0)
        btn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        btn:SetBackdropColor(0.3, 0.2, 0.4, 1)
        btn:SetBackdropBorderColor(0.6, 0.4, 0.8, 1)
        btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        btn.text:SetPoint("CENTER")
        btn.text:SetText(text)
        btn:SetScript("OnClick", onClick)
        btn:SetScript("OnEnter", function(s) s:SetBackdropColor(0.4, 0.3, 0.5, 1) end)
        btn:SetScript("OnLeave", function(s) s:SetBackdropColor(0.3, 0.2, 0.4, 1) end)
        return btn
    end

    local addBtn = makeBtn("+FAKE", 60, label, function()
        if BJ.TestMode then BJ.TestMode:AddBingoFakePlayers(1) end
    end)
    local slowBtn = makeBtn("SLOWER", 62, addBtn, function()
        if BJ.TestMode and BJ.BingoMultiplayer then
            BJ.TestMode:SetBingoDrawSpeed(BJ.BingoMultiplayer.DRAW_SECONDS + 0.5)
        end
        BUI:RefreshTestBar()
    end)
    local fastBtn = makeBtn("FASTER", 62, slowBtn, function()
        if BJ.TestMode and BJ.BingoMultiplayer then
            BJ.TestMode:SetBingoDrawSpeed(BJ.BingoMultiplayer.DRAW_SECONDS - 0.5)
        end
        BUI:RefreshTestBar()
    end)

    local speedText = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    speedText:SetPoint("LEFT", fastBtn, "RIGHT", 8, 0)
    speedText:SetText("")
    bar.speedText = speedText

    bar:Hide()
    self.testBar = bar
end

function BUI:RefreshTestBar()
    if not self.testBar then return end
    if BJ.TestMode and BJ.TestMode.enabled then
        local secs = BJ.BingoMultiplayer and BJ.BingoMultiplayer.DRAW_SECONDS or 4
        self.testBar.speedText:SetText("|cffff00ff" .. secs .. "s / call|r")
        self.testBar:Show()
    else
        self.testBar:Hide()
    end
end

local function styleButton(btn, label, enabled, r, g, b)
    btn.text:SetText(label)
    if enabled then
        btn:Enable()
        btn:Show()
        btn:SetBackdropColor(r or 0.15, g or 0.35, b or 0.15, 1)
        btn:SetBackdropBorderColor((r or 0.15) + 0.15, (g or 0.35) + 0.35, (b or 0.15) + 0.15, 1)
    else
        btn:Disable()
        btn:SetBackdropColor(0.15, 0.15, 0.15, 1)
        btn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    end
end

function BUI:OnActionClick()
    local BS = BJ.BingoState
    local BM = BJ.BingoMultiplayer
    local myName = UnitName("player")

    if BS.phase == BS.PHASE.IDLE or BS.phase == BS.PHASE.SETTLEMENT then
        BM:HostTable(tonumber(self.priceBox:GetText()) or 0)
    elseif BS.phase == BS.PHASE.LOBBY then
        if BM.isHost then
            BM:StartGame()
        elseif not BS.players[myName] then
            BM:RequestJoin()
        end
    end

    self:UpdateDisplay()
end

function BUI:OnCancelClick()
    local BM = BJ.BingoMultiplayer
    if BM.isHost then
        BM:CloseTable()
    end
    self:UpdateDisplay()
end

--[[
    CARD GRID
    One pooled frame per card: owner name on top, 5x5 cells below.
]]

function BUI:GetCardFrame(i)
    local cf = self.cardFrames[i]
    if cf then return cf end

    cf = CreateFrame("Frame", nil, self.cardContent)
    cf:SetSize(CARD_W, CARD_H)

    local nameText = cf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameText:SetPoint("TOPLEFT", 0, 0)
    nameText:SetPoint("TOPRIGHT", 0, 0)
    nameText:SetHeight(NAME_H - 2)
    nameText:SetJustifyH("CENTER")
    cf.nameText = nameText

    cf.cells = {}
    for row = 1, 5 do
        cf.cells[row] = {}
        for col = 1, 5 do
            local cell = CreateFrame("Frame", nil, cf, "BackdropTemplate")
            cell:SetSize(CELL_SIZE, CELL_SIZE)
            cell:SetPoint("TOPLEFT",
                (col - 1) * (CELL_SIZE + CELL_GAP),
                -NAME_H - (row - 1) * (CELL_SIZE + CELL_GAP))
            cell:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
            cell:SetBackdropColor(0.12, 0.12, 0.15, 1)
            cell:SetBackdropBorderColor(0.4, 0.35, 0.2, 1)

            local text = cell:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            text:SetPoint("CENTER")
            text:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
            cell.text = text

            cf.cells[row][col] = cell
        end
    end

    self.cardFrames[i] = cf
    return cf
end

-- Paint one player's card into a pooled card frame
function BUI:RenderCardInto(cf, ownerName, card)
    local BS = BJ.BingoState
    local myName = UnitName("player")

    cf.isWinner = false
    if not ownerName then
        cf.nameText:SetText("|cff666666(no cards yet)|r")
    else
        local isWinner = false
        for _, w in ipairs(BS.winners or {}) do
            if w == ownerName then isWinner = true break end
        end
        cf.isWinner = isWinner
        if isWinner then
            cf.nameText:SetText("|cffffd700" .. ownerName .. " - BINGO!|r")
        elseif ownerName == myName then
            cf.nameText:SetText("|cff88ff88" .. ownerName .. " (you)|r")
        else
            cf.nameText:SetText("|cffffffff" .. ownerName .. "|r")
        end
    end

    for row = 1, 5 do
        for col = 1, 5 do
            local cell = cf.cells[row][col]
            if cell.star then cell.star:Hide() end
            local n = card and card[row][col]
            if not n and n ~= 0 then
                cell.text:SetText("")
                cell:SetBackdropColor(0.12, 0.12, 0.15, 1)
                cell:SetBackdropBorderColor(0.4, 0.35, 0.2, 1)
            elseif n == 0 then
                cell.text:SetText("|cffffd700FREE|r")
                cell.text:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
                cell:SetBackdropColor(0.25, 0.2, 0.05, 1)
                cell:SetBackdropBorderColor(0.8, 0.65, 0.2, 1)
            else
                cell.text:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
                if BS.drawnSet[n] then
                    cell.text:SetText("|cffffffff" .. n .. "|r")
                    cell:SetBackdropColor(0.1, 0.4, 0.12, 1)
                    cell:SetBackdropBorderColor(0.3, 0.9, 0.35, 1)
                else
                    cell.text:SetText("|cffbbbbbb" .. n .. "|r")
                    cell:SetBackdropColor(0.12, 0.12, 0.15, 1)
                    cell:SetBackdropBorderColor(0.4, 0.35, 0.2, 1)
                end
            end
        end
    end

    -- Star every square of the winning line on a winning card (gold raid
    -- target star replaces the number)
    if card and cf.isWinner and BS.GetWinningLine then
        local line = BS:GetWinningLine(card)
        if line then
            for _, rc in ipairs(line) do
                local cell = cf.cells[rc[1]][rc[2]]
                if not cell.star then
                    local star = cell:CreateTexture(nil, "OVERLAY")
                    star:SetPoint("CENTER")
                    star:SetSize(CELL_SIZE - 6, CELL_SIZE - 6)
                    star:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
                    star:SetTexCoord(0, 0.25, 0, 0.25)  -- gold star
                    cell.star = star
                end
                cell.text:SetText("")
                cell.star:Show()
                cell:SetBackdropColor(0.25, 0.2, 0.05, 1)
                cell:SetBackdropBorderColor(1, 0.84, 0, 1)
            end
        end
    end
end

-- Lay out every player's card - yours first, the rest sorted by how
-- close they are to a bingo (fewest balls missing on any line, then
-- most lines at that count, then name) - growing the window up to
-- 3 wide x 2 tall and scrolling with a loud hint past that
function BUI:RenderAllCards()
    local BS = BJ.BingoState
    local myName = UnitName("player")

    local others = {}
    for _, n in ipairs(BS.playerOrder) do
        if n ~= myName then
            local card = BS.players[n] and BS.players[n].card
            local best, count = 6, 0
            if card and BS.GetCardCloseness then
                best, count = BS:GetCardCloseness(card)
            end
            table.insert(others, { name = n, best = best, count = count })
        end
    end
    table.sort(others, function(a, b)
        if a.best ~= b.best then return a.best < b.best end
        if a.count ~= b.count then return a.count > b.count end
        return a.name < b.name
    end)

    local names = {}
    if BS.players[myName] then
        table.insert(names, myName)
    end
    for _, entry in ipairs(others) do
        table.insert(names, entry.name)
    end

    local n = #names
    local shown = math.max(n, 1)  -- keep one blank card as a placeholder
    local cols = math.min(shown, MAX_COLS)
    local totalRows = math.ceil(shown / cols)
    local visRows = math.min(totalRows, MAX_VIS_ROWS)

    for i = 1, shown do
        local cf = self:GetCardFrame(i)
        local col = (i - 1) % cols + 1
        local row = math.floor((i - 1) / cols) + 1
        cf:ClearAllPoints()
        cf:SetPoint("TOPLEFT",
            (col - 1) * (CARD_W + CARD_GAP),
            -(row - 1) * (CARD_H + CARD_GAP))
        cf:Show()

        local owner = names[i]
        local card = owner and BS.players[owner] and BS.players[owner].card or nil
        self:RenderCardInto(cf, owner, card)
    end
    for i = shown + 1, #self.cardFrames do
        self.cardFrames[i]:Hide()
    end

    -- Resize the scroll viewport and the window around it
    local contentW = cols * CARD_W + (cols - 1) * CARD_GAP
    local contentH = totalRows * CARD_H + (totalRows - 1) * CARD_GAP
    local viewH = visRows * CARD_H + (visRows - 1) * CARD_GAP

    self.cardContent:SetSize(contentW, contentH)
    self.cardScroll:SetSize(contentW, viewH)
    self.resultText:SetWidth(contentW)

    -- Remember the grid so the scroll hint can count hidden cards live
    self.gridCols = cols
    self.gridCardCount = shown

    if totalRows > visRows then
        if self.cardScroll.ScrollBar then
            self.cardScroll.ScrollBar:Show()
        end
    else
        self.cardScroll:SetVerticalScroll(0)
        if self.cardScroll.ScrollBar then
            self.cardScroll.ScrollBar:Hide()
        end
    end
    self:UpdateScrollHint()

    local w = GRID_LEFT + contentW + SCROLLBAR_W + PANEL_W + 14
    local h = -GRID_TOP + viewH + 22 + 44   -- top chrome + hint row + result row
    self.frame:SetSize(math.max(w, MIN_WIDTH), math.max(h, MIN_HEIGHT))
    self.statusText:SetWidth(math.max(w, MIN_WIDTH) - 30)
end

-- Count cards fully hidden above/below the viewport and update the hint
-- (re-runs on every scroll, so the numbers track the scroll position)
function BUI:UpdateScrollHint()
    if not self.scrollHint then return end

    local total = self.gridCardCount or 0
    local cols = self.gridCols or 1
    local sf = self.cardScroll
    if total == 0 or sf:GetVerticalScrollRange() <= 1 then
        self.scrollHint:SetText("")
        return
    end

    local offset = sf:GetVerticalScroll()
    local viewBottom = offset + sf:GetHeight()
    local rowH = CARD_H + CARD_GAP

    local above, below = 0, 0
    for i = 1, total do
        local row = math.ceil(i / cols)
        local top = (row - 1) * rowH
        local bottom = top + CARD_H
        if bottom <= offset + 2 then
            above = above + 1
        elseif top >= viewBottom - 2 then
            below = below + 1
        end
    end

    if below > 0 then
        self.scrollHint:SetText("|cffffd700\226\150\188\226\150\188  SCROLL DOWN: " .. below ..
            " more card" .. (below == 1 and "" or "s") .. " below  \226\150\188\226\150\188|r")
    elseif above > 0 then
        self.scrollHint:SetText("|cffffd700\226\150\178\226\150\178  SCROLL UP: " .. above ..
            " card" .. (above == 1 and "" or "s") .. " above  \226\150\178\226\150\178|r")
    else
        self.scrollHint:SetText("")
    end
end

-- Called for each number as it's drawn
function BUI:OnDraw(n)
    self:UpdateDisplay()
end

function BUI:UpdateDisplay()
    if not self.frame then return end

    local BS = BJ.BingoState
    local BM = BJ.BingoMultiplayer
    local myName = UnitName("player")
    local me = BS.players[myName]

    -- Clear FREE PLAY badge by default; the BUY CARD branch re-shows it.
    -- (actionBtn is persistent, so we can't rely on a hidden parent.)
    if BJ.UI and BJ.UI.Debts then
        BJ.UI.Debts:SetJoinFakeBadge(self.actionBtn, false)
    end

    -- Everyone's cards (a single blank card when nobody has joined)
    self:RenderAllCards()

    -- Caller panel
    if #BS.drawn > 0 then
        local last = BS.drawn[#BS.drawn]
        self.ballText:SetText("|cffffd700" .. BS:GetLetterFor(last) .. "-" .. last .. "|r")
        self.drawCountText:SetText(#BS.drawn .. " / " .. BS.NUMBERS .. " called")

        local recent = {}
        for i = math.max(1, #BS.drawn - 5), #BS.drawn - 1 do
            local n = BS.drawn[i]
            table.insert(recent, 1, BS:GetLetterFor(n) .. "-" .. n)
        end
        self.recentText:SetText(#recent > 0 and ("|cff888888Recent: " .. table.concat(recent, "  ") .. "|r") or "")
    else
        self.ballText:SetText("|cff666666--|r")
        self.drawCountText:SetText("")
        self.recentText:SetText("")
    end

    -- Pot and players
    if BS.phase ~= BS.PHASE.IDLE then
        local pot = (BS.phase == BS.PHASE.LOBBY) and (BS.cardPrice * #BS.playerOrder) or BS.pot
        self.potText:SetText("Pot: |cffffd700" .. pot .. "g|r  (" .. BS.cardPrice .. "g a card)")

        local names = {}
        for i, name in ipairs(BS.playerOrder) do
            if i > 8 then
                table.insert(names, "|cff888888+" .. (#BS.playerOrder - 8) .. " more|r")
                break
            end
            table.insert(names, name == myName and ("|cff88ff88" .. name .. "|r") or name)
        end
        self.playersText:SetText("|cffccaa66PLAYERS (" .. #BS.playerOrder .. ")|r\n" .. table.concat(names, ", "))
    else
        self.potText:SetText("")
        self.playersText:SetText("")
    end

    -- Phase-specific chrome
    local inTestMode = BJ.TestMode and BJ.TestMode.enabled
    local grouped = IsInGroup() or IsInRaid() or inTestMode

    self.priceBox:Hide()
    self.priceLabel:Hide()
    self.cancelBtn:Hide()
    self.resultText:SetText("")

    if BS.phase == BS.PHASE.IDLE or BS.phase == BS.PHASE.SETTLEMENT then
        if BS.phase == BS.PHASE.SETTLEMENT then
            self.statusText:SetText("|cffffd700Game over!|r")
            self.resultText:SetText(BS:GetSettlementText())
        else
            self.statusText:SetText(grouped and "Host a game - winner takes the pot!"
                or "|cffff8800Join a party or raid to play.|r")
        end
        self.priceBox:Show()
        self.priceLabel:Show()
        styleButton(self.actionBtn, "HOST BINGO", grouped, 0.15, 0.35, 0.15)

    elseif BS.phase == BS.PHASE.LOBBY then
        if BM.isHost then
            self.statusText:SetText("Waiting for players... start when ready.")
            styleButton(self.actionBtn, "START DRAW", #BS.playerOrder >= 2, 0.15, 0.35, 0.15)
            self.cancelBtn:Show()
            styleButton(self.cancelBtn, "CANCEL", true, 0.35, 0.15, 0.15)
        elseif me then
            self.statusText:SetText("Card bought! Waiting for " .. (BS.hostName or "?") .. " to start...")
            styleButton(self.actionBtn, "WAITING...", false)
        else
            self.statusText:SetText((BS.hostName or "?") .. " is selling cards for " .. BS.cardPrice .. "g!")
            styleButton(self.actionBtn, "BUY CARD (" .. BS.cardPrice .. "g)", true, 0.15, 0.35, 0.15)
            if BJ.UI and BJ.UI.Debts then
                BJ.UI.Debts:SetJoinFakeBadge(self.actionBtn, BS.fakePlay == true)
            end
        end

    elseif BS.phase == BS.PHASE.DRAWING then
        if me then
            self.statusText:SetText("|cff00ff00Numbers are being called - good luck!|r")
        else
            self.statusText:SetText("Draw in progress (spectating)")
        end
        if BM.isHost then
            styleButton(self.actionBtn, "DRAWING...", false)
            self.cancelBtn:Show()
            styleButton(self.cancelBtn, "CANCEL", true, 0.35, 0.15, 0.15)
        else
            styleButton(self.actionBtn, me and "GOOD LUCK!" or "SPECTATING", false)
        end
    end

    self:RefreshTestBar()
end

function BUI:Show()
    self:Initialize()
    self:UpdateDisplay()
    self.frame:Show()

    -- Show any deferred version warning now that a casino window is open
    if BJ.ShowPendingVersionWarning then
        BJ:ShowPendingVersionWarning()
    end
end

function BUI:Hide()
    if self.frame then
        self.frame:Hide()
    end
end
