--[[
    Chairface's Casino - UI/LiarsDiceFrame.lua
    Liar's Dice window: the roster with each player's remaining dice, the
    standing bid, your own hidden hand, the raise/call controls, and the
    all-hands reveal after a challenge.
]]

local BJ = ChairfacesCasino
local UI = BJ.UI

UI.LiarsDice = {}
local LDUI = UI.LiarsDice

local FRAME_WIDTH = 400
local FRAME_HEIGHT = 540

--[[
    DIE WIDGET
    Honors the player's dice-style setting (BJ.DiceStyles): a "texture" set
    (scrimshaw) shows the shipped die_1..die_6 images; "digit" (numeric) shows a
    numbered face; "pips" (white/red) draws pips in the set's colors. SetFace
    picks the face; SetHighlight tints the face for the counted value on a reveal.
]]
local PIP_SET = {
    [1] = { "C" },
    [2] = { "TL", "BR" },
    [3] = { "TL", "C", "BR" },
    [4] = { "TL", "TR", "BL", "BR" },
    [5] = { "TL", "TR", "C", "BL", "BR" },
    [6] = { "TL", "TR", "ML", "MR", "BL", "BR" },
}

-- The player's selected dice style descriptor (render + colors/folder).
local function diceStyle()
    local id = BJ.db and BJ.db.settings and BJ.db.settings.diceStyle or "numeric"
    return BJ:GetDiceStyle(id)
end

local function createDie(parent, size)
    local die = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    die:SetSize(size, size)
    die:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    die:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)

    -- Textured face, shown for a "texture" dice set.
    local faceTex = die:CreateTexture(nil, "ARTWORK")
    faceTex:SetPoint("TOPLEFT", 1, -1)
    faceTex:SetPoint("BOTTOMRIGHT", -1, 1)
    faceTex:Hide()
    die.faceTex = faceTex

    -- Numbered face, shown for a "digit" dice set.
    local faceNum = die:CreateFontString(nil, "OVERLAY")
    faceNum:SetPoint("CENTER", 0, 0)
    faceNum:SetFont("Fonts\\FRIZQT__.TTF", math.max(9, math.floor(size * 0.6)), "OUTLINE")
    faceNum:Hide()
    die.faceNum = faceNum

    local f = size * 0.26
    local offsets = {
        TL = { -f, f }, TR = { f, f },
        ML = { -f, 0 }, MR = { f, 0 },
        BL = { -f, -f }, BR = { f, -f },
        C  = { 0, 0 },
    }

    die.pips = {}
    for key, off in pairs(offsets) do
        local pip = die:CreateTexture(nil, "OVERLAY")
        pip:SetSize(size * 0.2, size * 0.2)
        pip:SetPoint("CENTER", die, "CENTER", off[1], off[2])
        pip:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
        pip:Hide()
        die.pips[key] = pip
    end

    function die:SetFace(face)
        self.face = face
        local style = diceStyle()
        self.faceTex:Hide()
        self.faceNum:Hide()
        for _, pip in pairs(self.pips) do pip:Hide() end

        if style.render == "texture" and style.folder then
            self.faceTex:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\dice\\" .. style.folder .. "\\die_" .. face)
            self.faceTex:SetVertexColor(1, 1, 1, 1)
            self.faceTex:Show()
            self:SetBackdropColor(0, 0, 0, 0)
            self:SetBackdropBorderColor(0, 0, 0, 0)
        elseif style.render == "digit" then
            local d, p = style.dieColor or { 0.95, 0.95, 0.92 }, style.pipColor or { 0.1, 0.1, 0.12 }
            self:SetBackdropColor(d[1], d[2], d[3], 1)
            self:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)
            self.faceNum:SetTextColor(p[1], p[2], p[3], 1)
            self.faceNum:SetText(tostring(face))
            self.faceNum:Show()
        else
            local d, p = style.dieColor or { 0.93, 0.92, 0.88 }, style.pipColor or { 0.1, 0.1, 0.12 }
            self:SetBackdropColor(d[1], d[2], d[3], 1)
            self:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)
            for _, key in ipairs(PIP_SET[face] or {}) do
                self.pips[key]:SetVertexColor(p[1], p[2], p[3], 1)
                self.pips[key]:Show()
            end
        end
    end

    function die:SetHighlight(on)
        local style = diceStyle()
        if style.render == "texture" then
            self.faceTex:SetVertexColor(on and 0.55 or 1, 1, on and 0.55 or 1, 1)
        elseif on then
            self:SetBackdropColor(0.55, 0.9, 0.55, 1)
            self:SetBackdropBorderColor(0.2, 0.6, 0.2, 1)
        else
            -- Repaint the die body in the current style's colour.
            self:SetFace(self.face or 1)
        end
    end

    return die
end

function LDUI:Initialize()
    if self.frame then return end
    self:CreateFrame()
end

function LDUI:CreateFrame()
    local frame = CreateFrame("Frame", "ChairfacesCasinoLiarsDice", UIParent, "BackdropTemplate")
    frame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
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
    frame:SetBackdropColor(0.08, 0.08, 0.1, 0.97)
    frame:SetBackdropBorderColor(0.6, 0.5, 0.2, 1)

    -- Table-felt background, same as the poker games and High-Lo. Sub-level 1
    -- keeps it above the backdrop's dark fill; the aspect-fit texcoords match
    -- how PokerFrame centers the 1280x720 felt.
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

    frame:Hide()
    self.frame = frame

    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("|cffffd700Liar's Dice|r")
    title:SetFont("Fonts\\FRIZQT__.TTF", 20, "OUTLINE")

    -- Close button (returns to the lobby)
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function()
        LDUI:Hide()
        if UI.Lobby then UI.Lobby:Show() end
    end)

    -- Debts shortcut (settle-up ledger) next to the close button
    if UI.Debts and UI.Debts.AttachDebtsIcon then
        UI.Debts:AttachDebtsIcon(frame, "RIGHT", closeBtn, "LEFT", -2, 0)
    end

    -- How to Play (top-left)
    if UI.Lobby and UI.Lobby.AttachHowToPlayButton then
        UI.Lobby:AttachHowToPlayButton(frame, "liarsdice", 8, -8)
    end

    -- Trixie deals here too
    if UI.Lobby and UI.Lobby.AttachTrixie then
        UI.Lobby:AttachTrixie(frame, "liarsdice")
    end

    -- Status line
    local status = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    status:SetPoint("TOP", title, "BOTTOM", 0, -6)
    status:SetWidth(FRAME_WIDTH - 30)
    status:SetText("")
    self.statusText = status

    -- Roster (each player + dice remaining)
    local roster = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    roster:SetPoint("TOP", status, "BOTTOM", 0, -8)
    roster:SetWidth(FRAME_WIDTH - 40)
    roster:SetJustifyH("CENTER")
    roster:SetJustifyV("TOP")
    roster:SetHeight(96)
    roster:SetText("")
    self.rosterText = roster

    -- Standing bid banner
    local bidBanner = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    bidBanner:SetPoint("TOP", roster, "BOTTOM", 0, -6)
    bidBanner:SetFont("Fonts\\FRIZQT__.TTF", 18, "OUTLINE")
    bidBanner:SetText("")
    self.bidBanner = bidBanner

    -- Reveal / all-hands container (shown during a challenge reveal)
    local revealBox = CreateFrame("Frame", nil, frame)
    revealBox:SetSize(FRAME_WIDTH - 30, 150)
    revealBox:SetPoint("TOP", bidBanner, "BOTTOM", 0, -6)
    revealBox:Hide()
    revealBox.rows = {}
    self.revealBox = revealBox

    -- "Your hand" label + dice row
    local handLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    handLabel:SetPoint("BOTTOM", frame, "BOTTOM", 0, 190)
    handLabel:SetText("|cff88ff88Your hand|r")
    self.handLabel = handLabel

    self.handDice = {}
    local dieSize = 40
    local spacing = 8
    local totalW = 5 * dieSize + 4 * spacing
    for i = 1, 5 do
        local die = createDie(frame, dieSize)
        die:SetPoint("BOTTOM", frame, "BOTTOM", -totalW / 2 + dieSize / 2 + (i - 1) * (dieSize + spacing), 148)
        die:Hide()
        self.handDice[i] = die
    end

    --[[  BID CONTROLS  ]]
    -- Count and Face steppers are stacked vertically on the left; the
    -- RAISE / CALL LIAR buttons sit vertically on the right.
    local bidControls = CreateFrame("Frame", nil, frame)
    bidControls:SetSize(FRAME_WIDTH - 30, 100)
    bidControls:SetPoint("BOTTOM", frame, "BOTTOM", 0, 44)
    self.bidControls = bidControls

    -- Quantity stepper
    local qtyLabel = bidControls:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    qtyLabel:SetPoint("TOPLEFT", 30, 0)
    qtyLabel:SetText("|cffffd700Count|r")

    local function makeStepper(parent, anchorFS, onDelta)
        local minus = CreateFrame("Button", nil, parent, "BackdropTemplate")
        minus:SetSize(24, 24)
        minus:SetPoint("TOP", anchorFS, "BOTTOM", -30, -2)
        minus:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        minus:SetBackdropColor(0.3, 0.2, 0.2, 1)
        minus:SetBackdropBorderColor(0.6, 0.4, 0.4, 1)
        minus.text = minus:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        minus.text:SetPoint("CENTER", 0, 1)
        minus.text:SetText("-")
        minus:SetScript("OnClick", function() onDelta(-1) end)

        local plus = CreateFrame("Button", nil, parent, "BackdropTemplate")
        plus:SetSize(24, 24)
        plus:SetPoint("TOP", anchorFS, "BOTTOM", 30, -2)
        plus:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        plus:SetBackdropColor(0.2, 0.3, 0.2, 1)
        plus:SetBackdropBorderColor(0.4, 0.6, 0.4, 1)
        plus.text = plus:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        plus.text:SetPoint("CENTER", 0, 1)
        plus.text:SetText("+")
        plus:SetScript("OnClick", function() onDelta(1) end)

        return minus, plus
    end

    makeStepper(bidControls, qtyLabel, function(d) LDUI:AdjustQty(d) end)
    local qtyValue = bidControls:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    qtyValue:SetPoint("TOP", qtyLabel, "BOTTOM", 0, -2)
    qtyValue:SetFont("Fonts\\FRIZQT__.TTF", 24, "OUTLINE")
    qtyValue:SetText("1")
    self.qtyValue = qtyValue

    -- Face stepper (shows a die) - stacked directly beneath the Count
    -- stepper so both bid controls sit well clear of the RAISE / CALL LIAR
    -- buttons on the right (avoids mis-clicks near the raise).
    local faceLabel = bidControls:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    faceLabel:SetPoint("TOPLEFT", bidControls, "TOPLEFT", 34, -48)
    faceLabel:SetText("|cffffd700Face|r")

    makeStepper(bidControls, faceLabel, function(d) LDUI:AdjustFace(d) end)
    local faceDie = createDie(bidControls, 34)
    faceDie:SetPoint("TOP", faceLabel, "BOTTOM", 0, -4)
    faceDie:SetFace(2)
    self.faceDie = faceDie

    -- BID + CALL LIAR buttons
    local function makeActionButton(text, xOff, r, g, b, onClick)
        local btn = CreateFrame("Button", nil, bidControls, "BackdropTemplate")
        btn:SetSize(110, 30)
        btn:SetPoint("TOPRIGHT", bidControls, "TOPRIGHT", xOff, -6)
        btn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
        btn:SetBackdropColor(r, g, b, 1)
        btn:SetBackdropBorderColor(r + 0.2, g + 0.2, b + 0.2, 1)
        btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        btn.text:SetPoint("CENTER")
        btn.text:SetText(text)
        btn:SetScript("OnClick", onClick)
        return btn
    end

    local bidBtn = makeActionButton("RAISE", -6, 0.15, 0.35, 0.15, function()
        LDUI:OnBidClick()
    end)
    bidBtn:SetPoint("TOPRIGHT", bidControls, "TOPRIGHT", -6, -18)
    self.bidBtn = bidBtn

    local liarBtn = makeActionButton("CALL LIAR!", -6, 0.4, 0.15, 0.15, function()
        LDUI:OnLiarClick()
    end)
    liarBtn:SetPoint("TOPRIGHT", bidControls, "TOPRIGHT", -6, -54)
    self.liarBtn = liarBtn

    --[[  HOST / LOBBY CONTROLS  ]]
    -- Stake input (host, lobby only)
    local stakeBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    stakeBox:SetSize(70, 24)
    stakeBox:SetPoint("BOTTOM", frame, "BOTTOM", -110, 96)
    stakeBox:SetAutoFocus(false)
    stakeBox:SetNumeric(true)
    stakeBox:SetMaxLetters(7)
    stakeBox:SetText(tostring(BJ.HostSettings and BJ.HostSettings:Get("liarsdiceStake") or 100))
    stakeBox:SetScript("OnEnterPressed", function(box) box:ClearFocus() end)
    stakeBox:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)
    self.stakeBox = stakeBox

    local stakeLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    stakeLabel:SetPoint("BOTTOM", stakeBox, "TOP", 0, 3)
    stakeLabel:SetText("|cffffd700Buy-in (g)|r")
    self.stakeLabel = stakeLabel

    -- Ones-wild toggle (host, lobby only)
    local wildBtn = CreateFrame("Button", nil, frame, "BackdropTemplate")
    wildBtn:SetSize(100, 24)
    wildBtn:SetPoint("BOTTOM", frame, "BOTTOM", 5, 96)
    wildBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    wildBtn.text = wildBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    wildBtn.text:SetPoint("CENTER")
    wildBtn:SetScript("OnClick", function()
        LDUI.onesWild = not LDUI.onesWild
        LDUI:UpdateWildButton()
    end)
    self.wildBtn = wildBtn
    self.onesWild = true

    local wildLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    wildLabel:SetPoint("BOTTOM", wildBtn, "TOP", 0, 3)
    wildLabel:SetText("|cffffd700Wild ones|r")
    self.wildLabel = wildLabel

    -- Starting-dice toggle (host, lobby only): default 3, host may choose 5
    local diceBtn = CreateFrame("Button", nil, frame, "BackdropTemplate")
    diceBtn:SetSize(100, 24)
    diceBtn:SetPoint("BOTTOM", frame, "BOTTOM", 115, 96)
    diceBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    diceBtn.text = diceBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    diceBtn.text:SetPoint("CENTER")
    diceBtn:SetScript("OnClick", function()
        LDUI.startDice = (LDUI.startDice == 5) and 3 or 5
        LDUI:UpdateDiceButton()
    end)
    self.diceBtn = diceBtn
    self.startDice = BJ.LiarsDiceState.START_DICE  -- default 3

    local diceLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    diceLabel:SetPoint("BOTTOM", diceBtn, "TOP", 0, 3)
    diceLabel:SetText("|cffffd700Start dice|r")
    self.diceLabel = diceLabel

    -- Primary context button (host START / client JOIN / host CLOSE)
    local primaryBtn = CreateFrame("Button", nil, frame, "BackdropTemplate")
    primaryBtn:SetSize(150, 34)
    primaryBtn:SetPoint("BOTTOM", frame, "BOTTOM", 0, 46)
    primaryBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
    primaryBtn.text = primaryBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    primaryBtn.text:SetPoint("CENTER")
    primaryBtn:SetScript("OnClick", function() LDUI:OnPrimaryClick() end)
    self.primaryBtn = primaryBtn

    -- Fake play (fun games record no debts) right where hosting starts
    if BJ.UI.Debts and BJ.UI.Debts.AttachFakePlayCheck then
        BJ.UI.Debts:AttachFakePlayCheck(frame, "LEFT", primaryBtn, "RIGHT", 8, 0)
    end

    -- Secondary button (host CANCEL while a match is live)
    local cancelBtn = CreateFrame("Button", nil, frame, "BackdropTemplate")
    cancelBtn:SetSize(110, 24)
    cancelBtn:SetPoint("BOTTOM", frame, "BOTTOM", 0, 16)
    cancelBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    cancelBtn:SetBackdropColor(0.3, 0.15, 0.15, 1)
    cancelBtn:SetBackdropBorderColor(0.6, 0.3, 0.3, 1)
    cancelBtn.text = cancelBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cancelBtn.text:SetPoint("CENTER")
    cancelBtn.text:SetText("Cancel Table")
    cancelBtn:SetScript("OnClick", function()
        if BJ.LiarsDiceMultiplayer then BJ.LiarsDiceMultiplayer:CloseTable() end
    end)
    self.cancelBtn = cancelBtn

    -- Forfeit button: any player may quit at any time. In the lobby this just
    -- leaves; mid-match it forfeits (drop your dice, the match plays on). A host
    -- who forfeits hands the table to another player.
    local forfeitBtn = CreateFrame("Button", nil, frame, "BackdropTemplate")
    forfeitBtn:SetSize(90, 24)
    forfeitBtn:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 12, 16)
    forfeitBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    forfeitBtn:SetBackdropColor(0.3, 0.15, 0.15, 1)
    forfeitBtn:SetBackdropBorderColor(0.6, 0.3, 0.3, 1)
    forfeitBtn.text = forfeitBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    forfeitBtn.text:SetPoint("CENTER")
    forfeitBtn.text:SetText("Forfeit")
    forfeitBtn:SetScript("OnClick", function() LDUI:OnForfeitClick() end)
    forfeitBtn:Hide()
    self.forfeitBtn = forfeitBtn

    -- Turn timer readout (GameComm shows countdown here at <=10s)
    local timerFrame = CreateFrame("Frame", nil, frame)
    timerFrame:SetSize(40, 40)
    timerFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 12)
    timerFrame.text = timerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    timerFrame.text:SetPoint("CENTER")
    timerFrame.text:SetTextColor(1, 0.3, 0.3)
    timerFrame:Hide()
    self.turnTimerFrame = timerFrame

    -- Purple test-mode bar
    self:CreateTestBar()

    if BJ.EscapeHandler then
        BJ.EscapeHandler:RegisterFrame("ChairfacesCasinoLiarsDice")
    end
end

--[[
    TEST BAR
]]
function LDUI:CreateTestBar()
    local bar = CreateFrame("Frame", nil, self.frame, "BackdropTemplate")
    bar:SetSize(240, 35)
    bar:SetPoint("TOP", self.frame, "BOTTOM", 0, -5)
    bar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
    bar:SetBackdropColor(0.15, 0.1, 0.2, 0.95)
    bar:SetBackdropBorderColor(1, 0.4, 1, 1)

    local label = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", 10, 0)
    label:SetText("|cffff00ffTEST|r")

    local addBtn = CreateFrame("Button", nil, bar, "BackdropTemplate")
    addBtn:SetSize(90, 24)
    addBtn:SetPoint("LEFT", label, "RIGHT", 8, 0)
    addBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    addBtn:SetBackdropColor(0.3, 0.2, 0.4, 1)
    addBtn:SetBackdropBorderColor(0.6, 0.4, 0.8, 1)
    addBtn.text = addBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    addBtn.text:SetPoint("CENTER")
    addBtn.text:SetText("ADD BOTS")
    addBtn:SetScript("OnClick", function()
        if BJ.TestMode and BJ.TestMode.AddLiarsDiceFakePlayers then
            BJ.TestMode:AddLiarsDiceFakePlayers(3)
        end
    end)

    local playBtn = CreateFrame("Button", nil, bar, "BackdropTemplate")
    playBtn:SetSize(110, 24)
    playBtn:SetPoint("LEFT", addBtn, "RIGHT", 8, 0)
    playBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    playBtn:SetBackdropColor(0.3, 0.2, 0.4, 1)
    playBtn:SetBackdropBorderColor(0.6, 0.4, 0.8, 1)
    playBtn.text = playBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    playBtn.text:SetPoint("CENTER")
    playBtn.text:SetText("BOTS ACT")
    playBtn:SetScript("OnClick", function()
        if BJ.TestMode and BJ.TestMode.LiarsDiceBotsAct then
            BJ.TestMode:LiarsDiceBotsAct()
        end
    end)

    bar:Hide()
    self.testBar = bar
end

function LDUI:RefreshTestBar()
    if not self.testBar then return end
    if BJ.TestMode and BJ.TestMode.enabled then
        self.testBar:Show()
    else
        self.testBar:Hide()
    end
end

--[[
    BID CONTROL STATE
]]
local function minFace()
    return BJ.LiarsDiceState.onesWild and 2 or 1
end

function LDUI:AdjustQty(d)
    local total = BJ.LiarsDiceState:TotalDice()
    self.bidQ = math.max(1, math.min(total, (self.bidQ or 1) + d))
    self:UpdateBidControls()
end

function LDUI:AdjustFace(d)
    local lo, hi = minFace(), BJ.LiarsDiceState.DICE_FACES
    self.bidFace = math.max(lo, math.min(hi, (self.bidFace or lo) + d))
    self:UpdateBidControls()
end

-- Seed the steppers with the smallest legal raise the first time it's my turn
function LDUI:ResetBidSelection()
    local LD = BJ.LiarsDiceState
    local q, face = LD:MinimalRaise()
    self.bidQ = q
    self.bidFace = face
end

function LDUI:UpdateBidControls()
    if self.qtyValue then self.qtyValue:SetText(tostring(self.bidQ or 1)) end
    if self.faceDie then self.faceDie:SetFace(self.bidFace or minFace()) end
end

function LDUI:OnBidClick()
    if BJ.LiarsDiceMultiplayer then
        BJ.LiarsDiceMultiplayer:PlaceBid(self.bidQ or 1, self.bidFace or minFace())
    end
end

function LDUI:OnLiarClick()
    if BJ.LiarsDiceMultiplayer then
        BJ.LiarsDiceMultiplayer:CallLiar()
    end
end

function LDUI:UpdateWildButton()
    if not self.wildBtn then return end
    if self.onesWild then
        self.wildBtn.text:SetText("|cff00ff00ON|r")
        self.wildBtn:SetBackdropColor(0.15, 0.3, 0.15, 1)
        self.wildBtn:SetBackdropBorderColor(0.3, 0.6, 0.3, 1)
    else
        self.wildBtn.text:SetText("|cffff8800OFF|r")
        self.wildBtn:SetBackdropColor(0.3, 0.2, 0.15, 1)
        self.wildBtn:SetBackdropBorderColor(0.6, 0.4, 0.3, 1)
    end
end

function LDUI:UpdateDiceButton()
    if not self.diceBtn then return end
    local n = (self.startDice == 5) and 5 or 3
    self.diceBtn.text:SetText("|cffffd700" .. n .. " dice|r")
    if n == 5 then
        self.diceBtn:SetBackdropColor(0.15, 0.2, 0.35, 1)
        self.diceBtn:SetBackdropBorderColor(0.3, 0.45, 0.7, 1)
    else
        self.diceBtn:SetBackdropColor(0.2, 0.2, 0.25, 1)
        self.diceBtn:SetBackdropBorderColor(0.45, 0.45, 0.55, 1)
    end
end

function LDUI:OnPrimaryClick()
    local LD = BJ.LiarsDiceState
    local LDM = BJ.LiarsDiceMultiplayer
    local myName = UnitName("player")

    if LD.phase == LD.PHASE.IDLE or LD.phase == LD.PHASE.SETTLEMENT then
        -- Host a new table
        local stake = tonumber(self.stakeBox:GetText()) or 0
        LDM:HostTable(stake, self.onesWild, self.startDice)
    elseif LD.phase == LD.PHASE.LOBBY then
        if LDM.isHost then
            LDM:StartGame()
        elseif not LD.players[myName] then
            LDM:RequestJoin()
        end
    end
    self:UpdateDisplay()
end

StaticPopupDialogs["CC_LIARSDICE_FORFEIT"] = {
    text = "Forfeit Liar's Dice?\nYou drop your dice and the match plays on without you.",
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        if BJ.LiarsDiceMultiplayer then BJ.LiarsDiceMultiplayer:RequestForfeit() end
        if BJ.UI and BJ.UI.LiarsDice then BJ.UI.LiarsDice:UpdateDisplay() end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

function LDUI:OnForfeitClick()
    local LD = BJ.LiarsDiceState
    -- In the lobby a quit is harmless (just leave) - no need to nag.
    if LD.phase == LD.PHASE.LOBBY then
        if BJ.LiarsDiceMultiplayer then BJ.LiarsDiceMultiplayer:RequestForfeit() end
        self:UpdateDisplay()
        return
    end
    -- Mid-match forfeit is destructive; confirm first.
    StaticPopup_Show("CC_LIARSDICE_FORFEIT")
end

--[[
    REVEAL DISPLAY (all hands after a challenge)
]]
function LDUI:BuildReveal()
    local LD = BJ.LiarsDiceState
    local box = self.revealBox
    local reveal = LD.reveal
    if not reveal then box:Hide() return end

    -- Hide previously built rows
    for _, row in ipairs(box.rows) do row:Hide() end

    local dieSize = 22
    local spacing = 4
    local y = 0
    local rowIndex = 0
    for _, name in ipairs(LD.playerOrder) do
        local dice = reveal.dice[name]
        if dice and #dice > 0 then
            rowIndex = rowIndex + 1
            local row = box.rows[rowIndex]
            if not row then
                row = CreateFrame("Frame", nil, box)
                row:SetSize(box:GetWidth(), dieSize + 4)
                row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                row.label:SetPoint("LEFT", row, "LEFT", 4, 0)
                row.label:SetWidth(90)
                row.label:SetJustifyH("LEFT")
                row.dice = {}
                box.rows[rowIndex] = row
            end
            row:SetPoint("TOPLEFT", box, "TOPLEFT", 0, -y)
            local color = (name == reveal.loser) and "|cffff4444" or "|cffffffff"
            row.label:SetText(color .. name .. "|r")

            for i = 1, #dice do
                local die = row.dice[i]
                if not die then
                    die = createDie(row, dieSize)
                    row.dice[i] = die
                end
                die:SetPoint("LEFT", row, "LEFT", 96 + (i - 1) * (dieSize + spacing), 0)
                die:SetFace(dice[i])
                -- Highlight dice that counted toward the bid face
                local counts = (dice[i] == reveal.bidFace)
                    or (reveal.onesWild and dice[i] == 1 and reveal.bidFace ~= 1)
                die:SetHighlight(counts)
                die:Show()
            end
            -- Hide any leftover dice widgets on this row
            for i = #dice + 1, #row.dice do row.dice[i]:Hide() end
            row:Show()
            y = y + dieSize + 6
        end
    end

    box:SetHeight(math.max(1, y))
    box:Show()
end

--[[
    MAIN REFRESH
]]
function LDUI:UpdateDisplay()
    if not self.frame then return end

    local LD = BJ.LiarsDiceState
    local LDM = BJ.LiarsDiceMultiplayer
    local myName = UnitName("player")
    local iAmPlaying = LD.players[myName] ~= nil
    local myTurn = (LD.phase == LD.PHASE.BIDDING and LD:CurrentBidder() == myName)

    -- Clear FREE PLAY badge by default; the JOIN branch below re-shows it.
    if BJ.UI and BJ.UI.Debts then
        BJ.UI.Debts:SetJoinFakeBadge(self.primaryBtn, false)
    end

    -- Roster
    local lines = {}
    for _, name in ipairs(LD.playerOrder) do
        local p = LD.players[name]
        if p then
            local marker = (LD.phase == LD.PHASE.BIDDING and name == LD:CurrentBidder()) and "|cffffd700>|r " or ""
            local nameColor = (name == myName) and "|cff88ff88" or "|cffffffff"
            local dots
            if p.alive then
                dots = "|cffffd700" .. string.rep("*", p.count) .. "|r"
            else
                dots = "|cffff4444OUT|r"
            end
            local strike = p.alive and "" or "|cff777777"
            table.insert(lines, marker .. strike .. nameColor .. name .. "|r  " .. dots)
        end
    end
    self.rosterText:SetText(table.concat(lines, "\n"))

    -- Hide everything context-dependent, then selectively show
    self.bidControls:Hide()
    self.revealBox:Hide()
    self.stakeBox:Hide(); self.stakeLabel:Hide()
    self.wildBtn:Hide(); self.wildLabel:Hide()
    self.diceBtn:Hide(); self.diceLabel:Hide()
    self.primaryBtn:Hide()
    self.cancelBtn:Hide()
    self.forfeitBtn:Hide()
    self.handLabel:Hide()
    for _, die in ipairs(self.handDice) do die:Hide() end

    local inTestMode = BJ.TestMode and BJ.TestMode.enabled
    local grouped = IsInGroup() or IsInRaid() or inTestMode

    -- A player in a live table can bail at any time. In the lobby a non-host
    -- quit is a plain leave; mid-match a still-alive player forfeits. (The host
    -- uses Cancel Table in the lobby; once live, forfeit hands the table off.)
    local myP = LD.players[myName]
    local liveMatch = (LD.phase == LD.PHASE.BIDDING or LD.phase == LD.PHASE.REVEAL)
    local showForfeit = iAmPlaying and (
        (liveMatch and myP and myP.alive)
        or (LD.phase == LD.PHASE.LOBBY and not LDM.isHost))
    self.forfeitBtn:SetShown(showForfeit)

    if LD.phase == LD.PHASE.IDLE or LD.phase == LD.PHASE.SETTLEMENT then
        if LD.phase == LD.PHASE.SETTLEMENT then
            self.statusText:SetText("|cffffd700Match over!|r")
            self.bidBanner:SetText(LD:GetSettlementText())
        else
            self.statusText:SetText(grouped and "Host a table - last player with dice wins the pot."
                or "|cffff8800Join a party or raid to play.|r")
            self.bidBanner:SetText("")
        end
        -- Host setup controls
        self.stakeBox:Show(); self.stakeLabel:Show()
        self.wildBtn:Show(); self.wildLabel:Show()
        self.diceBtn:Show(); self.diceLabel:Show()
        self:UpdateWildButton()
        self:UpdateDiceButton()
        self:SetPrimary("HOST TABLE", grouped, 0.15, 0.35, 0.15)

    elseif LD.phase == LD.PHASE.LOBBY then
        self.bidBanner:SetText("")
        local n = #LD.playerOrder
        if LDM.isHost then
            local wild = LD.onesWild and "ones wild" or "no wilds"
            self.statusText:SetText("Waiting for players... (" .. n .. " joined, need 2+) - " .. wild)
            self:SetPrimary("START MATCH", n >= 2, 0.15, 0.35, 0.15)
            self.cancelBtn:Show()
        elseif iAmPlaying then
            self.statusText:SetText("|cff00ff00You're in!|r Waiting for " .. (LD.hostName or "host") .. " to start.")
            self:SetPrimary("WAITING...", false)
        else
            self.statusText:SetText(LD.hostName .. " is hosting for " .. LD.stake .. "g. (" .. n .. " joined)")
            self:SetPrimary("JOIN (" .. LD.stake .. "g)", true, 0.15, 0.35, 0.15)
            if BJ.UI and BJ.UI.Debts then
                BJ.UI.Debts:SetJoinFakeBadge(self.primaryBtn, LD.fakePlay == true)
            end
        end

    elseif LD.phase == LD.PHASE.BIDDING then
        self.bidBanner:SetText(LD.currentBid
            and ("Bid: |cffffd700" .. LD:BidText(LD.currentBid) .. "|r by " .. LD.currentBid.by)
            or "|cff888888Opening bid...|r")

        -- Show my hand
        self:ShowMyHand()

        if LDM.isHost or iAmPlaying then
            self.cancelBtn:SetShown(LDM.isHost)
        end

        if myTurn then
            self.statusText:SetText("|cff00ff00Your turn!|r Raise the bid or call Liar.")
            -- Seed the steppers with a legal raise when the turn first lands
            if not self._hadTurn then
                self:ResetBidSelection()
            end
            self._hadTurn = true
            self.bidControls:Show()
            self:UpdateBidControls()
            -- Can't call Liar with no standing bid
            self.liarBtn:SetShown(LD.currentBid ~= nil)
            self.bidBtn.text:SetText("RAISE")
        else
            self._hadTurn = false
            local bidder = LD:CurrentBidder() or "?"
            if iAmPlaying then
                self.statusText:SetText("Waiting for " .. bidder .. " to act...")
            else
                self.statusText:SetText(bidder .. " is deciding... (spectating)")
            end
        end

    elseif LD.phase == LD.PHASE.REVEAL then
        local rv = LD.reveal
        if rv then
            self.bidBanner:SetText(rv.challenger .. " called Liar! Actual "
                .. LD:FaceName(rv.bidFace) .. "s: |cffffd700" .. rv.count .. "|r vs bid "
                .. rv.bidQ)
            self.statusText:SetText("|cffff4444" .. rv.loser .. "|r loses a die!")
        end
        self:BuildReveal()
        self.cancelBtn:SetShown(LDM.isHost)
    end

    self:RefreshTestBar()
end

-- Render this client's own hidden hand (only if it belongs to this round)
function LDUI:ShowMyHand()
    local LD = BJ.LiarsDiceState
    local myName = UnitName("player")
    local p = LD.players[myName]
    if not (p and p.alive) then return end

    self.handLabel:Show()
    if LD.myDice and LD.myDiceRound == LD.roundNum then
        self.handLabel:SetText("|cff88ff88Your hand|r")
        for i = 1, 5 do
            local die = self.handDice[i]
            if LD.myDice[i] then
                die:SetFace(LD.myDice[i])
                die:Show()
            else
                die:Hide()
            end
        end
    else
        self.handLabel:SetText("|cff888888Dealing your hand...|r")
        for _, die in ipairs(self.handDice) do die:Hide() end
    end
end

function LDUI:SetPrimary(label, enabled, r, g, b)
    local btn = self.primaryBtn
    btn:Show()
    btn.text:SetText(label)
    if enabled then
        btn:Enable()
        btn:SetBackdropColor(r or 0.15, g or 0.35, b or 0.15, 1)
        btn:SetBackdropBorderColor((r or 0.15) + 0.15, (g or 0.35) + 0.35, (b or 0.15) + 0.15, 1)
    else
        btn:Disable()
        btn:SetBackdropColor(0.15, 0.15, 0.15, 1)
        btn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    end
end

function LDUI:Show()
    self:Initialize()
    self.handLabel:SetText("|cff88ff88Your hand|r")
    self:UpdateDisplay()
    self.frame:Show()

    if BJ.ShowPendingVersionWarning then
        BJ:ShowPendingVersionWarning()
    end
end

function LDUI:Hide()
    if self.frame then
        self.frame:Hide()
    end
end

-- GameComm roster/void hooks may call these; keep them safe no-ops/refresh
function LDUI:OnGameVoided()
    self:UpdateDisplay()
end
