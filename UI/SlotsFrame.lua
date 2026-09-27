--[[
    Chairface's Casino - UI/SlotsFrame.lua
    "Azeroth Riches": a five-reel slot, five symbols tall (a 5x5 grid), with
    five paylines (top / middle / bottom / both diagonals). The player picks how
    many lines are active and a per-line bet. Three mini WoW Tokens on active
    lines trigger a randomly chosen bonus mini-game (loot chest / wheel / free
    spins). Persistent FAKE credit balance (BJ.Arcade) - no gold, no group.
]]

local BJ = ChairfacesCasino
local UI = BJ.UI

UI.Slots = {}
local SUI = UI.Slots

local FRAME_W = 600
local FRAME_H = 700

local REELS, ROWS = 5, 5
local ICON = 54
local CELL_H = 60
local REEL_W = 74
local REEL_GAP = 8
local REEL_H = ROWS * CELL_H + 6

local function reelAreaW() return REELS * REEL_W + (REELS - 1) * REEL_GAP end

-- ===== round cabinet buttons (SPIN / AUTO) =====
-- A generated bulb-lit casino button texture; the vertex tint tracks
-- state (it multiplies the lit dome, so state colours run bright), flips
-- gold under the mouse, and Blizzard's action-button glow burns around it
-- while the button is "live".
local function applyCircleColor(btn)
    local base = btn.base
    if not base then return end
    if base.enabled and btn.hovered then
        btn.circle:SetVertexColor(1, 0.85, 0.2, 1)
        btn.text:SetTextColor(0, 0, 0)
    elseif base.enabled then
        btn.circle:SetVertexColor(base.r, base.g, base.b, 1)
        btn.text:SetTextColor(1, 1, 1)
    else
        btn.circle:SetVertexColor(0.3, 0.3, 0.32, 1)
        btn.text:SetTextColor(0.55, 0.55, 0.55)
    end
end

local function styleCircle(btn, enabled, r, g, b)
    btn.base = { enabled = enabled, r = r, g = g, b = b }
    if enabled then btn:Enable() else btn:Disable() end
    applyCircleColor(btn)
end

-- The in-game glow: the action-button proc burst where the client has it,
-- the pet autocast shine as the fallback. Guarded so repaints don't
-- re-kick a glow that's already running.
local function setGlow(btn, on)
    if on and not btn.glowOn then
        btn.glowOn = true
        if ActionButton_ShowOverlayGlow then
            ActionButton_ShowOverlayGlow(btn)
        elseif btn.shine and AutoCastShine_AutoCastStart then
            AutoCastShine_AutoCastStart(btn.shine)
        end
    elseif not on and btn.glowOn then
        btn.glowOn = false
        if ActionButton_HideOverlayGlow then
            ActionButton_HideOverlayGlow(btn)
        elseif btn.shine and AutoCastShine_AutoCastStop then
            AutoCastShine_AutoCastStop(btn.shine)
        end
    end
end

-- Big bets in small boxes: 10000 -> "10k", 2500000 -> "2.5m".
local function fmtBet(n)
    if n >= 1000000 then
        local m = n / 1000000
        if m == math.floor(m) then return m .. "m" end
        return string.format("%.1fm", m)
    end
    if n >= 1000 then
        local k = n / 1000
        if k == math.floor(k) then return k .. "k" end
        return string.format("%.1fk", k)
    end
    return tostring(n)
end

-- Full number with thousands separators for the roomy readouts.
local function fmtBig(n)
    if BreakUpLargeNumbers then return BreakUpLargeNumbers(n) end
    return tostring(n)
end

-- Line colours (for markers and win highlights), one per payline, in the
-- engine's activation order: middle, row2, row4, top, bottom, /, \, V, ^.
local LINE_COLORS = {
    { 0.35, 0.7, 1.0 },   -- 1 Middle (row 3)
    { 0.5, 0.9, 0.4 },    -- 2 Row 2
    { 0.95, 0.65, 0.3 },  -- 3 Row 4
    { 0.95, 0.3, 0.3 },   -- 4 Top (row 1)
    { 0.8, 0.5, 1.0 },    -- 5 Bottom (row 5)
    { 1.0, 0.85, 0.25 },  -- 6 Slash /
    { 0.3, 0.9, 0.85 },   -- 7 Backslash \
    { 1.0, 0.5, 0.7 },    -- 8 Top V
    { 0.65, 0.85, 0.3 },  -- 9 Bottom ^
}

function SUI:Initialize()
    if self.frame then return end
    self:CreateFrame()
end

function SUI:CreateFrame()
    local frame = CreateFrame("Frame", "ChairfacesCasinoSlots", UIParent, "BackdropTemplate")
    frame:SetSize(FRAME_W, FRAME_H)
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
    frame:SetBackdropColor(0.1, 0.06, 0.12, 0.97)
    frame:SetBackdropBorderColor(0.7, 0.55, 0.2, 1)
    frame:Hide()
    self.frame = frame

    -- Painted cabinet art covers the whole frame (logo is baked into the
    -- art; the backdrop colour underneath is the fallback until the client
    -- has registered the texture).
    local bg = frame:CreateTexture(nil, "BACKGROUND", nil, 7)
    bg:SetAllPoints()
    bg:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\Arcade\\slotsbackground")

    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function()
        SUI:Hide()
        if UI.Lobby then UI.Lobby:Show() end
    end)

    if UI.Lobby and UI.Lobby.AttachHowToPlayButton then
        UI.Lobby:AttachHowToPlayButton(frame, "slots", 8, -8)
    end
    if UI.Lobby and UI.Lobby.AttachTrixie then
        UI.Lobby:AttachTrixie(frame)
    end

    -- Every progressive pot gets its own shaded window; a pot dims when
    -- the current total bet isn't riding for it (5+ for the classics,
    -- 100+ for MEGA). MINI/MINOR/MAJOR flank the logo on the left,
    -- GRAND/MEGA on the right, both columns centred on the logo's midline.
    local JACKPOT_TIERS = {
        { key = "mini",  label = "MINI",  color = { 0.33, 1.00, 0.33 }, side = "LEFT",  slot = 1, of = 3 },
        { key = "minor", label = "MINOR", color = { 0.33, 0.67, 1.00 }, side = "LEFT",  slot = 2, of = 3 },
        { key = "major", label = "MAJOR", color = { 0.80, 0.40, 1.00 }, side = "LEFT",  slot = 3, of = 3 },
        { key = "grand", label = "GRAND", color = { 1.00, 0.60, 0.20 }, side = "RIGHT", slot = 1, of = 2 },
        { key = "mega",  label = "MEGA",  color = { 1.00, 0.27, 0.33 }, side = "RIGHT", slot = 2, of = 2 },
    }
    self.jackpotBoxes = {}
    local BOXW, BOXH, BOXGAP = 104, 36, 5
    local LOGO_MID_Y = -95   -- vertical centre of the baked-in logo art
    for _, t in ipairs(JACKPOT_TIERS) do
        local box = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        box:SetSize(BOXW, BOXH)
        local colH = t.of * BOXH + (t.of - 1) * BOXGAP
        local y = LOGO_MID_Y + colH / 2 - (t.slot - 1) * (BOXH + BOXGAP)
        if t.side == "LEFT" then
            box:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, y)
        else
            box:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, y)
        end
        box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        box:SetBackdropColor(0, 0, 0, 0.72)
        box:SetBackdropBorderColor(t.color[1], t.color[2], t.color[3], 0.9)
        local label = box:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("TOP", 0, -3)
        label:SetTextColor(t.color[1], t.color[2], t.color[3])
        label:SetText(t.label)
        local value = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        value:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
        value:SetPoint("BOTTOM", 0, 4)
        box.value = value
        self.jackpotBoxes[t.key] = box
    end

    -- Reel area (5 reels x 5 rows). Dropped a touch so the corner line
    -- markers above it clear the credits readout.
    local reelArea = CreateFrame("Frame", nil, frame)
    reelArea:SetSize(reelAreaW(), REEL_H)
    reelArea:SetPoint("TOP", -50, -240)   -- clears the button stack + top markers
    self.reelArea = reelArea

    self.reels = {}
    for r = 1, REELS do
        local reel = CreateFrame("Frame", nil, reelArea, "BackdropTemplate")
        reel:SetSize(REEL_W, REEL_H)
        reel:SetPoint("LEFT", (r - 1) * (REEL_W + REEL_GAP), 0)
        reel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
        reel:SetBackdropColor(0.04, 0.04, 0.06, 1)
        reel:SetBackdropBorderColor(0.55, 0.45, 0.2, 1)

        -- anticipation dressing: an additive gold ring that pulses while the
        -- reel sweats, plus Blizzard's autocast shine + proc glow where the
        -- client still ships them (API-guarded: they come and go per client)
        local sweatGlow = reel:CreateTexture(nil, "OVERLAY")
        sweatGlow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
        sweatGlow:SetBlendMode("ADD")
        sweatGlow:SetVertexColor(1, 0.85, 0.2, 0.9)
        sweatGlow:SetPoint("TOPLEFT", -14, 14)
        sweatGlow:SetPoint("BOTTOMRIGHT", 14, -14)
        sweatGlow:Hide()
        reel.sweatGlow = sweatGlow
        if AutoCastShine_AutoCastStart then
            reel.shine = CreateFrame("Frame", nil, reel, "AutoCastShineTemplate")
            reel.shine:SetPoint("TOPLEFT", 2, -2)
            reel.shine:SetPoint("BOTTOMRIGHT", -2, 2)
        end

        reel.icons, reel.hl, reel.coinFS = {}, {}, {}
        for row = 1, ROWS do
            local hl = reel:CreateTexture(nil, "BACKGROUND")
            hl:SetColorTexture(1, 0.85, 0.2, 0.35)
            hl:SetSize(REEL_W - 6, CELL_H - 4)
            hl:SetPoint("CENTER", reel, "TOP", 0, -(row - 0.5) * CELL_H)
            hl:Hide()
            reel.hl[row] = hl

            local tex = reel:CreateTexture(nil, "ARTWORK")
            tex:SetSize(ICON, ICON)
            tex:SetPoint("CENTER", reel, "TOP", 0, -(row - 0.5) * CELL_H)
            tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            reel.icons[row] = tex

            -- coin value stamped over a landed WoW Token
            local fs = reel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            fs:SetPoint("CENTER", tex, "CENTER", 0, -6)
            fs:SetFont("Fonts\\FRIZQT__.TTF", 13, "THICKOUTLINE")
            fs:Hide()
            reel.coinFS[row] = fs
        end
        self.reels[r] = reel
    end

    -- Payline markers. Each shows 0 until its line is live, then the bet
    -- riding on it (1-5). Horizontal rows get one marker to the LEFT of their
    -- row; each diagonal gets a marker at both of its corners; the V / ^
    -- zig-zags sit just inside the diagonal corner markers. Clicking any
    -- marker plays up to and including that line.
    self.lineMarkers = {}
    local Slots = BJ.Arcade.Slots

    local function rowY(row)
        return REEL_H / 2 - (row - 0.5) * CELL_H
    end

    local function makeMarker(lineIdx)
        local m = CreateFrame("Button", nil, frame, "BackdropTemplate")
        m:SetSize(24, 24)
        m:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        m.text = m:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        m.text:SetPoint("CENTER")
        m:SetScript("OnClick", function() SUI:SetLines(lineIdx) end)
        m:SetScript("OnEnter", function(self)
            local ln = Slots.LINES[lineIdx]
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:AddLine("Line " .. lineIdx .. " - " .. ln.name)
            GameTooltip:AddLine("Click to play " .. lineIdx .. " line" .. (lineIdx > 1 and "s" or ""), 0.8, 0.8, 0.8)
            GameTooltip:Show()
            SUI:ShowLineOverlay(lineIdx)   -- trace the line across the reels
        end)
        m:SetScript("OnLeave", function()
            GameTooltip:Hide()
            SUI:HideLineOverlay()
        end)
        self.lineMarkers[lineIdx] = self.lineMarkers[lineIdx] or {}
        table.insert(self.lineMarkers[lineIdx], m)
        return m
    end

    -- 1-5: the horizontal rows (activation order middle, 2, 4, top, bottom)
    for lineIdx = 1, 5 do
        local row = Slots.LINES[lineIdx].cells[1].row
        local m = makeMarker(lineIdx)
        m:SetPoint("RIGHT", reelArea, "LEFT", -6, rowY(row))
    end

    -- 6: slash / (bottom-left up to top-right) - a marker on both corners
    makeMarker(6):SetPoint("TOPRIGHT", reelArea, "BOTTOMLEFT", -2, -2)
    makeMarker(6):SetPoint("BOTTOMLEFT", reelArea, "TOPRIGHT", 2, 2)

    -- 7: backslash \ (top-left down to bottom-right)
    makeMarker(7):SetPoint("BOTTOMRIGHT", reelArea, "TOPLEFT", -2, 2)
    makeMarker(7):SetPoint("TOPLEFT", reelArea, "BOTTOMRIGHT", 2, -2)

    -- 8: top V - starts/ends on the top row, so its markers ride the top edge
    -- just inside the diagonal corner markers
    makeMarker(8):SetPoint("BOTTOM", reelArea, "TOPLEFT", 40, 2)
    makeMarker(8):SetPoint("BOTTOM", reelArea, "TOPRIGHT", -40, 2)

    -- 9: bottom ^ - same idea along the bottom edge
    makeMarker(9):SetPoint("TOP", reelArea, "BOTTOMLEFT", 40, -2)
    makeMarker(9):SetPoint("TOP", reelArea, "BOTTOMRIGHT", -40, -2)

    -- Win banner (below the bottom-edge line markers)
    -- the banner rides on a credit-bar-styled plate that only shows while
    -- there's something to say (see SetWinText)
    local winPlate = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    winPlate:SetPoint("TOP", reelArea, "BOTTOM", 0, -26)
    winPlate:SetSize(10, 30)
    winPlate:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    winPlate:SetBackdropColor(0, 0, 0, 0.85)
    winPlate:SetBackdropBorderColor(0.95, 0.8, 0.1, 1)
    winPlate:Hide()
    self.winPlate = winPlate

    local winText = winPlate:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    winText:SetPoint("CENTER")
    winText:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE")
    winText:SetText("")
    self.winText = winText

    -- SPIN and AUTO are big round cabinet buttons (alpha-mask circles) in
    -- the control column right of the reels, with Blizzard's autocast
    -- sparkle running around them: on SPIN whenever it's ready to fire,
    -- on AUTO while a batch is running.
    local function makeCircleButton(size, fontSize)
        local b = CreateFrame("Button", nil, frame)
        b:SetSize(size, size)
        b.circle = b:CreateTexture(nil, "BACKGROUND")
        b.circle:SetAllPoints()
        b.circle:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\Arcade\\bulb_button")
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        b.text:SetPoint("CENTER")
        b.text:SetFont("Fonts\\FRIZQT__.TTF", fontSize, "OUTLINE")
        b.text:SetJustifyH("CENTER")
        if AutoCastShine_AutoCastStart then
            b.shine = CreateFrame("Frame", nil, b, "AutoCastShineTemplate")
            b.shine:SetPoint("TOPLEFT", 8, -8)
            b.shine:SetPoint("BOTTOMRIGHT", -8, 8)
        end
        b:SetScript("OnEnter", function(self)
            self.hovered = true
            applyCircleColor(self)
        end)
        b:SetScript("OnLeave", function(self)
            self.hovered = false
            applyCircleColor(self)
        end)
        return b
    end

    local spinBtn = makeCircleButton(100, 18)
    spinBtn:SetPoint("TOP", reelArea, "TOPRIGHT", 70, -34)
    spinBtn:SetScript("OnClick", function() SUI:OnSpin() end)
    self.spinBtn = spinBtn

    local maxBtn = CreateFrame("Button", nil, frame, "BackdropTemplate")
    maxBtn:SetSize(100, 36)
    maxBtn:SetPoint("TOP", spinBtn, "BOTTOM", 0, -15)
    maxBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
    maxBtn.text = maxBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    maxBtn.text:SetPoint("CENTER")
    maxBtn.text:SetText("MAX BET")
    maxBtn:SetScript("OnClick", function()
        if SUI.spinning or SUI.bonusActive then return end
        SUI.betPerLine = BJ.Arcade:MaxAffordableStep(SUI.lines)
        BJ:PlaySfx("Arcade\\coin_insert.ogg")
        SUI:UpdateDisplay()
    end)
    self.maxBtn = maxBtn

    -- MAX LINES: light every payline (MAX BET above only maxes the wager
    -- per line, so the two knobs are independent)
    local maxLinesBtn = CreateFrame("Button", nil, frame, "BackdropTemplate")
    maxLinesBtn:SetSize(100, 36)
    maxLinesBtn:SetPoint("TOP", maxBtn, "BOTTOM", 0, -15)
    maxLinesBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
    maxLinesBtn.text = maxLinesBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    maxLinesBtn.text:SetPoint("CENTER")
    maxLinesBtn.text:SetText("MAX LINES")
    maxLinesBtn:SetScript("OnClick", function()
        if SUI.spinning or SUI.bonusActive then return end
        SUI:SetLines(BJ.Arcade.Slots.MAX_LINES)
    end)
    self.maxLinesBtn = maxLinesBtn

    -- AUTO: run a fixed batch of spins at the current bet - click cycles
    -- OFF -> 10 -> 25 -> 50 -> OFF. Never indefinite; it counts down and
    -- stops on its own (or when credits run dry; a bonus pauses and then
    -- resumes the remaining count).
    local AUTO_STEPS = { 10, 25, 50 }
    local autoBtn = makeCircleButton(78, 15)
    autoBtn:SetPoint("TOP", maxLinesBtn, "BOTTOM", 0, -15)
    autoBtn.text:SetText("AUTO")
    autoBtn:SetScript("OnClick", function()
        local idx = ((SUI.autoIdx or 0) + 1) % (#AUTO_STEPS + 1)
        SUI.autoIdx = idx
        if idx == 0 then
            SUI.autoSpin = false
            SUI.autoLeft = 0
        else
            SUI.autoSpin = true
            SUI.autoLeft = AUTO_STEPS[idx]
            if not (SUI.spinning or SUI.bonusActive) then
                SUI:QueueAutoSpin(0.2)
            end
        end
        SUI:UpdateDisplay()
    end)
    self.autoBtn = autoBtn

    -- The credit bar: the betting controls live ON it now. LINES and
    -- BET/LINE stacked on the left, CREDIT front and centre, BET (total)
    -- with WIN beneath it on the right, best/refills small at the bottom.
    local meter = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    meter:SetSize(FRAME_W - 60, 52)
    meter:SetPoint("BOTTOM", frame, "BOTTOM", 0, 42)
    meter:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    meter:SetBackdropColor(0, 0, 0, 0.85)
    meter:SetBackdropBorderColor(0.95, 0.8, 0.1, 1)

    local function miniStepper(yOfs, label, onDown, onUp)
        local lab = meter:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lab:SetPoint("LEFT", meter, "LEFT", 10, yOfs)
        lab:SetText(label)
        local down = CreateFrame("Button", nil, meter, "UIPanelButtonTemplate")
        down:SetSize(18, 18); down:SetText("-")
        down:SetPoint("LEFT", meter, "LEFT", 66, yOfs)
        local val = meter:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        val:SetWidth(46); val:SetJustifyH("CENTER")
        val:SetPoint("LEFT", down, "RIGHT", 1, 0)
        local up = CreateFrame("Button", nil, meter, "UIPanelButtonTemplate")
        up:SetSize(18, 18); up:SetText("+")
        up:SetPoint("LEFT", val, "RIGHT", 1, 0)
        down:SetScript("OnClick", onDown)
        up:SetScript("OnClick", onUp)
        return down, val, up
    end
    self.linesDown, self.linesVal, self.linesUp = miniStepper(13, "LINES",
        function() SUI:SetLines(SUI.lines - 1) end,
        function() SUI:SetLines(SUI.lines + 1) end)
    self.betDown, self.betVal, self.betUp = miniStepper(-9, "BET/LINE",
        function()
            local nxt = BJ.Arcade:NextBetStep(SUI.betPerLine, -1)
            if nxt ~= SUI.betPerLine then SUI.betPerLine = nxt; SUI:UpdateDisplay() end
        end,
        function()
            local nxt = BJ.Arcade:NextBetStep(SUI.betPerLine, 1)
            if nxt ~= SUI.betPerLine then
                SUI.betPerLine = nxt
                BJ:PlaySfx("Arcade\\coin_insert.ogg")
                SUI:UpdateDisplay()
            end
        end)

    local creditFS = meter:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    creditFS:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE")
    creditFS:SetPoint("CENTER", meter, "CENTER", 0, 10)
    self.meterCreditFS = creditFS

    local betFS = meter:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    betFS:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    betFS:SetPoint("RIGHT", meter, "RIGHT", -14, 13)
    self.meterBetFS = betFS

    local winFS = meter:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    winFS:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    winFS:SetPoint("RIGHT", meter, "RIGHT", -14, -9)
    self.meterWinFS = winFS

    -- bragging rights, small along the bottom centre
    local sub = meter:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sub:SetPoint("BOTTOM", 0, 3)
    self.meterSubFS = sub
    self.winShown = 0

    -- Bottom rail: SHOW OFF / SEND / BUY / PAYS, all in the same style.
    -- (The paytable lives on the PAYS popup, drawn with the reel symbols.)
    local function railButton(label, onClick, tip)
        local b = CreateFrame("Button", nil, frame, "BackdropTemplate")
        b:SetSize(120, 26)
        b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        b:SetBackdropColor(0.2, 0.2, 0.28, 1)
        b:SetBackdropBorderColor(0.55, 0.45, 0.2, 1)
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        b.text:SetPoint("CENTER")
        b.text:SetText("|cffffd700" .. label .. "|r")
        b:SetScript("OnClick", onClick)
        if tip then
            b:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:AddLine(tip)
                GameTooltip:Show()
            end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
        return b
    end
    local rail = {
        railButton("SHOW OFF", function() if BJ.ShareCredits then BJ:ShareCredits() end end,
            "Brag your credit total to chat"),
        railButton("SEND CREDITS", function() BJ:ShowSendCreditsDialog() end,
            "Gift arcade credits to another player (one-way)"),
        railButton("BUY CREDITS", function() BJ:ShowBuyCreditsDialog() end,
            "Buy credits: mail money to the casino"),
        railButton("PAYS", function() SUI:TogglePays() end),
    }
    local railW = #rail * 120 + (#rail - 1) * 8
    for i, b in ipairs(rail) do
        b:SetPoint("BOTTOMLEFT", frame, "BOTTOM", -railW / 2 + (i - 1) * 128, 10)
    end
    self.paysBtn = rail[#rail]

    -- Debug-only GRANT button: comp any character any number of credits.
    -- Built only for allow-listed characters (the /cc db gate) and shown only
    -- while debug mode is on. It hangs below the cabinet, outside the frame,
    -- so it never covers the machine.
    if BJ.Arcade and BJ.Arcade:CanGrantCredits() then
        local g = railButton("GRANT", function()
            if BJ.ShowGrantCreditsDialog then BJ:ShowGrantCreditsDialog() end
        end, "Debug: grant credits to any character")
        g:SetBackdropColor(0.28, 0.12, 0.32, 1)
        g:SetBackdropBorderColor(0.8, 0.3, 1.0, 1)
        g.text:SetText("|cffff00ffGRANT|r")
        g:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", -14, -4)
        self.grantBtn = g
    end
    self:UpdateGrantButton()

    self.spinDriver = CreateFrame("Frame")
    self.spinDriver:Hide()

    -- the jackpot marquee ticks up live while the cabinet is open (the
    -- community-pot simulation lives in Slots:AccrueJackpots)
    frame:HookScript("OnShow", function()
        SUI:UpdateGrantButton()
        SUI.grandTicker = SUI.grandTicker or C_Timer.NewTicker(1, function()
            if frame:IsShown() then SUI:UpdateJackpotMarquee() end
        end)
        -- an auto-spin batch paused by closing the window picks back up
        if SUI.autoSpin and (SUI.autoLeft or 0) > 0
            and not (SUI.spinning or SUI.bonusActive) then
            SUI:QueueAutoSpin(0.8)
        end
    end)
    frame:HookScript("OnHide", function()
        if SUI.grandTicker then
            SUI.grandTicker:Cancel()
            SUI.grandTicker = nil
        end
    end)

    if BJ.EscapeHandler then
        BJ.EscapeHandler:RegisterFrame("ChairfacesCasinoSlots")
    end

    self.lines = 5
    self.betPerLine = 1
    self.grid = BJ.Arcade.Slots:GridFromStops(BJ.Arcade.Slots:RollStops())
    self:RenderGrid(self.grid)
end

-- The PAYS popup: every paying symbol rendered with its own icon and its
-- 3 / 4 / 5-of-a-kind pays, read straight from the engine tables so it can
-- never drift from the real odds. Coin/bonus rules ride along at the bottom.
local SYMBOL_NAME = {
    wild = "WILD", skull = "Skull", gold = "Gold", ruby = "Ruby",
    emerald = "Emerald", sapphire = "Sapphire", die = "Die", shroom = "Shroom",
    melon = "Melon", apple = "Apple", silver = "Silver", copper = "Copper",
}

function SUI:TogglePays()
    if self.paysFrame and self.paysFrame:IsShown() then
        self.paysFrame:Hide()
        return
    end
    self:EnsurePaysFrame()
    self.paysFrame:Show()
end

function SUI:EnsurePaysFrame()
    if self.paysFrame then return end
    local Slots = BJ.Arcade.Slots

    local order = {}
    for _, sym in ipairs(Slots.SYMBOLS) do
        if sym.id ~= "token" then order[#order + 1] = sym end
    end

    local ROWH, TOP, FOOTER = 26, 64, 96
    local p = CreateFrame("Frame", nil, self.frame, "BackdropTemplate")
    p:SetFrameStrata("DIALOG")
    p:SetSize(430, TOP + #order * ROWH + FOOTER)
    p:SetPoint("CENTER")
    p:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
    p:SetBackdropColor(0.05, 0.03, 0.1, 0.98)
    p:SetBackdropBorderColor(0.8, 0.65, 0.2, 1)
    p:EnableMouse(true)
    p:Hide()
    self.paysFrame = p

    local title = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("|cffffd700PAYS|r  |cffccaa66per line, per credit|r")

    local closeBtn = CreateFrame("Button", nil, p, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() p:Hide() end)

    -- column headers over the pay columns
    local COLX = { 220, 290, 360 }
    local heads = { "3x", "4x", "5x" }
    for c = 1, 3 do
        local h = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        h:SetPoint("TOPLEFT", COLX[c], -40)
        h:SetWidth(56)
        h:SetJustifyH("RIGHT")
        h:SetText("|cffccaa66" .. heads[c] .. "|r")
    end

    for i, sym in ipairs(order) do
        local y = -(TOP + (i - 1) * ROWH)

        local icon = p:CreateTexture(nil, "ARTWORK")
        icon:SetSize(22, 22)
        icon:SetPoint("TOPLEFT", 24, y)
        icon:SetTexture(sym.icon)
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

        local name = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        name:SetPoint("TOPLEFT", 56, y - 4)
        if sym.id == "wild" then
            name:SetText("|cffff77ffWILD|r  |cff888888(matches anything)|r")
        else
            name:SetText(SYMBOL_NAME[sym.id] or sym.id)
        end

        local pays = Slots.LINE_PAY[sym.id] or {}
        for c = 1, 3 do
            local fs = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            fs:SetPoint("TOPLEFT", COLX[c], y - 4)
            fs:SetWidth(56)
            fs:SetJustifyH("RIGHT")
            fs:SetText("|cffffd700" .. (pays[c + 2] or 0) .. "|r")
        end
    end

    local footer = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    footer:SetPoint("BOTTOM", 0, 14)
    footer:SetWidth(390)
    footer:SetJustifyH("CENTER")
    footer:SetSpacing(3)
    footer:SetText(
        "|cff88ccffWoW Tokens are COINS carrying credit values.|r\n" ..
        "|cff88ccff3 coins in view: a random side bonus (chest / wheel / free spins).|r\n" ..
        "|cffff99334+ coins: HOLD & SPIN on all 25 cells - 3 respins,\n" ..
        "lock 20 of 25 for the progressive GRAND!|r\n" ..
        "|cffff77ff1 in 20 pulls is a GEM RUSH - only gems and better on the reels.|r")
end

-- ===== payline overlay: window-frame paylines =====
-- Frames can't rotate, so instead of stretched line textures: a straight
-- row gets one long thin bordered window laid across the reels, and an
-- angled run gets a chain of small bordered windows beaded along the
-- slope. Its own element, floated well above the reels.

-- cell centre in reelArea coordinates, origin bottom-left
local function cellXY(cell)
    local x = (cell.reel - 1) * (REEL_W + REEL_GAP) + REEL_W / 2
    local y = REEL_H - (cell.row - 0.5) * CELL_H
    return x, y
end

function SUI:ShowLineOverlay(lineIdx)
    if not self.lineOverlay then
        local ov = CreateFrame("Frame", nil, self.frame)
        ov:SetAllPoints(self.reelArea)
        ov:SetFrameLevel(self.frame:GetFrameLevel() + 30)
        ov.wins = {}
        self.lineOverlay = ov
    end
    local ov = self.lineOverlay
    local used = 0
    -- two window styles: "bar" is a thin bordered strip (horizontals),
    -- "dot" is a small white-filled square (diagonal beads)
    local function nextWin(kind)
        used = used + 1
        local w = ov.wins[used]
        if not w then
            w = CreateFrame("Frame", nil, ov, "BackdropTemplate")
            ov.wins[used] = w
        end
        if w.kind ~= kind then
            w.kind = kind
            if kind == "bar" then
                w:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
                w:SetBackdropBorderColor(1, 1, 1, 0.9)
            else
                w:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
                w:SetBackdropColor(1, 1, 1, 0.9)
            end
        end
        w:ClearAllPoints()
        w:Show()
        return w
    end

    local cells = BJ.Arcade.Slots.LINES[lineIdx].cells
    -- collapse to bend points: straights/diagonals are one run, V/^ two
    local verts = { cells[1] }
    for i = 2, #cells - 1 do
        if (cells[i].row - cells[i - 1].row) ~= (cells[i + 1].row - cells[i].row) then
            verts[#verts + 1] = cells[i]
        end
    end
    verts[#verts + 1] = cells[#cells]

    for i = 1, #verts - 1 do
        local x1, y1 = cellXY(verts[i])
        local x2, y2 = cellXY(verts[i + 1])
        if y1 == y2 then
            -- horizontal run: one thin solid strip across the reels (the
            -- 4px height closes the border onto itself - no hollow gap)
            local w = nextWin("bar")
            w:SetSize(math.abs(x2 - x1) + REEL_W - 12, 4)
            w:SetPoint("CENTER", ov, "BOTTOMLEFT", (x1 + x2) / 2, y1)
        else
            -- angled run: small filled squares packed tight enough to read
            -- as one solid line
            local len = math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
            local n = math.max(3, math.floor(len / 3))
            local s0 = (i == 1) and 0 or 1   -- don't double up on the bend
            for s = s0, n do
                local w = nextWin("dot")
                w:SetSize(4, 4)
                w:SetPoint("CENTER", ov, "BOTTOMLEFT",
                    x1 + (x2 - x1) * s / n, y1 + (y2 - y1) * s / n)
            end
        end
    end
    for i = used + 1, #ov.wins do ov.wins[i]:Hide() end
    ov:Show()
end

function SUI:HideLineOverlay()
    if self.lineOverlay then self.lineOverlay:Hide() end
    -- if the win parade owns a line right now, put its trace back
    if self.paradeLine then self:ShowLineOverlay(self.paradeLine) end
end

-- Set the win banner; the plate behind it sizes to the text and hides
-- entirely when there's nothing to say.
function SUI:SetWinText(str)
    self.winText:SetText(str or "")
    if str and str ~= "" then
        self.winPlate:SetSize(self.winText:GetStringWidth() + 28,
            self.winText:GetStringHeight() + 14)
        self.winPlate:Show()
    else
        self.winPlate:Hide()
    end
end

-- Draw the whole grid from a grid[reel][row] table
function SUI:RenderGrid(grid)
    local Slots = BJ.Arcade.Slots
    for r = 1, REELS do
        for row = 1, ROWS do
            local id = grid and grid[r] and grid[r][row]
            self.reels[r].icons[row]:SetTexture(id and Slots:IconFor(id) or nil)
        end
    end
end

-- Randomise one reel's visible symbols (spin flicker). Pass a strip to
-- flicker something other than the base game's (e.g. a GEM RUSH pull).
function SUI:FlickerReel(r, strip)
    local Slots = BJ.Arcade.Slots
    strip = strip or Slots.STRIP
    local n = #strip
    for row = 1, ROWS do
        self.reels[r].icons[row]:SetTexture(Slots:IconFor(strip[math.random(n)]))
    end
end

function SUI:ClearHighlights()
    for r = 1, REELS do
        for row = 1, ROWS do self.reels[r].hl[row]:Hide() end
    end
end

-- Coin value stamps ("+25", "MINI", ...) over landed WoW Tokens
local JACKPOT_LABEL = {
    mini  = "|cff55ff55MINI|r",
    minor = "|cff55aaffMINOR|r",
    major = "|cffcc66ffMAJOR|r",
    mega  = "|cffff4455MEGA|r",
}
local function coinLabel(coin)
    if coin.jackpot then return JACKPOT_LABEL[coin.jackpot] or "?" end
    return "|cffffd700" .. fmtBet(coin.value) .. "|r"
end

function SUI:ShowCoinValues(coins)
    for key, coin in pairs(coins or {}) do
        local reel, row = key:match("^(%d+):(%d+)$")
        reel, row = tonumber(reel), tonumber(row)
        if reel and row then
            local fs = self.reels[reel].coinFS[row]
            fs:SetText(coinLabel(coin))
            fs:Show()
        end
    end
end

function SUI:ClearCoinValues()
    for r = 1, REELS do
        for row = 1, ROWS do self.reels[r].coinFS[row]:Hide() end
    end
end

-- Dim (or restore) every symbol; used by hold & spin so locked coins pop.
function SUI:SetReelsDimmed(dim)
    for r = 1, REELS do
        for row = 1, ROWS do
            if dim then
                self.reels[r].icons[row]:SetVertexColor(0.3, 0.3, 0.35)
            else
                self.reels[r].icons[row]:SetVertexColor(1, 1, 1)
            end
        end
    end
end

function SUI:HighlightWins(wins)
    self:ClearHighlights()
    for _, w in ipairs(wins) do
        local col = LINE_COLORS[w.line]
        for i = 1, w.count do
            local cell = w.cells[i]
            local hl = self.reels[cell.reel].hl[cell.row]
            hl:SetColorTexture(col[1], col[2], col[3], 0.45)
            hl:Show()
        end
    end
end

function SUI:HighlightTokens(cells)
    for _, cell in ipairs(cells) do
        local hl = self.reels[cell.reel].hl[cell.row]
        hl:SetColorTexture(0.4, 0.8, 1, 0.5)
        hl:Show()
    end
end

function SUI:SetLines(n)
    if self.spinning or self.bonusActive then return end
    n = math.max(1, math.min(BJ.Arcade.Slots.MAX_LINES, n))
    if n > self.lines then
        BJ:PlaySfx("Arcade\\coin_insert.ogg")
    end
    self.lines = n
    self:UpdateDisplay()
end

-- Every marker on a line shows the bet riding it (or 0 when the line is off).
function SUI:UpdateLineMarkers()
    for lineIdx, markers in pairs(self.lineMarkers) do
        local active = (lineIdx <= self.lines)
        local c = LINE_COLORS[lineIdx]
        for _, m in ipairs(markers) do
            if active then
                m:SetBackdropColor(c[1] * 0.5, c[2] * 0.5, c[3] * 0.5, 1)
                m:SetBackdropBorderColor(c[1], c[2], c[3], 1)
                m.text:SetText(fmtBet(self.betPerLine))
                m.text:SetTextColor(1, 1, 1)
            else
                m:SetBackdropColor(0.12, 0.12, 0.14, 1)
                m:SetBackdropBorderColor(0.3, 0.3, 0.32, 1)
                m.text:SetText("0")
                m.text:SetTextColor(0.5, 0.5, 0.5)
            end
        end
    end
end

-- Schedule the next automatic spin. Silently drops out if auto was toggled
-- off, the machine is busy, the window closed, or the credits can't cover
-- it - and stops for good when the spin batch is used up.
function SUI:QueueAutoSpin(delay)
    C_Timer.After(delay or 1.4, function()
        if not self.autoSpin then return end
        if (self.autoLeft or 0) <= 0 then
            self.autoSpin = false
            self.autoIdx = 0
            BJ:Print("|cff88ccffAuto-spin batch finished.|r")
            self:UpdateDisplay()
            return
        end
        if self.spinning or self.bonusActive then return end
        if not (self.frame and self.frame:IsShown()) then return end
        if BJ.Arcade:GetCredits() < self.lines * self.betPerLine then
            self.autoSpin = false
            self.autoIdx = 0
            BJ:Print("|cffff8800Auto-spin stopped - not enough credits.|r")
            self:UpdateDisplay()
            return
        end
        self.autoLeft = self.autoLeft - 1
        self:OnSpin()
    end)
end

function SUI:OnSpin()
    if self.spinning or self.bonusActive then return end
    local Arcade = BJ.Arcade
    local Slots = Arcade.Slots

    if Arcade:GetCredits() < 1 then
        local ok, refills = Arcade:CompMe()
        if ok then
            BJ:Print("|cff00ff00The pit boss comps you " .. Arcade.COMP_AMOUNT ..
                " credits.|r (Refill #" .. refills .. " - she's keeping count.)")
            self:UpdateDisplay()
        end
        return
    end

    local result, err = Slots:Spin(self.betPerLine, self.lines)
    if not result then
        BJ:Print("|cffff8800" .. (err or "Cannot spin.") .. "|r")
        return
    end

    if self.rollupDriver then self.rollupDriver:SetScript("OnUpdate", nil) end
    self.winShown = 0
    self:SetWinText("")
    self:StopWinFlash()
    self:ClearHighlights()
    self:ClearCoinValues()
    self:SetReelsDimmed(false)
    self.spinning = true
    self.grid = result.grid
    self:UpdateDisplay()

    if result.rich then
        -- GEM RUSH: Trixie explains the strip while a giant token spins
        -- over the machine; the reels hold until she's done. The intro is
        -- pcall'd so a theatre error can never eat the rush (or strand
        -- the machine with spinning=true) - worst case the reels just run.
        local n = BJ.Arcade:GetDB().rushCount or 0
        self:SetWinText(("|cffff77ffGEM RUSH #%d! Only gems and better on the reels!|r"):format(n))
        local ok = pcall(self.PlayGemRushIntro, self,
            function() self:RunReelTheatre(result) end)
        if not ok then
            self:RunReelTheatre(result)
        end
    else
        self:RunReelTheatre(result)
    end
end

-- GEM RUSH intro: voice line + a ZG temple blinder (cut from the cabinet
-- art, GEM RUSH! stamped in gold) covering the reels. When the clip ends
-- the blinder swells and poofs, and onDone fires (on a real timer, so a
-- hidden window can't strand the spin).
local GEMRUSH_INTRO_SECS = 5.5   -- length of trixie_reelhelp.ogg plus a beat
function SUI:PlayGemRushIntro(onDone)
    -- Trixie is a voice line, so she obeys the VOICE toggle (not SFX)
    local lobby = BJ.UI and BJ.UI.Lobby
    if not lobby or lobby.voiceEnabled ~= false then
        pcall(PlaySoundFile,
            "Interface\\AddOns\\Chairfaces Casino\\Sounds\\Trixie\\trixie_reelhelp.ogg", "Master")
    end
    pcall(function() UI.Lobby:TrixieReact(self.frame, "deal", GEMRUSH_INTRO_SECS) end)

    if not self.rushToken then
        local f = CreateFrame("Frame", nil, self.frame)
        f:SetFrameStrata("DIALOG")
        f:SetPoint("CENTER", self.reelArea, "CENTER")
        f.tex = f:CreateTexture(nil, "OVERLAY")
        f.tex:SetAllPoints()
        f.tex:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\Arcade\\gemrush_blinder")
        f:Hide()
        self.rushToken = f
    end

    -- the blinder blankets every reel icon, sitting still while she talks
    local f = self.rushToken
    local BASE_W, BASE_H = reelAreaW() + 10, REEL_H + 10
    f:SetScript("OnUpdate", nil)
    f:SetSize(BASE_W, BASE_H)
    f:SetAlpha(1)
    f:Show()

    C_Timer.After(GEMRUSH_INTRO_SECS, function()
        BJ:PlaySfx("Kenney\\card-fan-1.ogg")   -- the poof
        local t = 0
        f:SetScript("OnUpdate", function(_, dt)
            t = t + dt
            local p = math.min(t / 0.35, 1)
            f:SetSize(BASE_W * (1 + 0.5 * p), BASE_H * (1 + 0.5 * p))
            f:SetAlpha(1 - p)
            if p >= 1 then
                f:SetScript("OnUpdate", nil)
                f:Hide()
            end
        end)
        if onDone then onDone() end
    end)
end

-- Reels flicker, then lock left to right on the real grid. The stop
-- sounds are scheduled with a small lead so the audio hit lands exactly
-- as each reel visually locks (the file has a touch of attack).
--
-- ANTICIPATION: the grid is predetermined, so once two coins have
-- already locked in view the remaining reels sweat - each holds for a
-- full play of the anticipation track (two plays when reel 5 is landing
-- the fifth coin), glowing gold until it lands.
function SUI:RunReelTheatre(result)
    BJ:PlaySfx("Arcade\\slot_lever.ogg")
    C_Timer.After(0.2, function()
        if self.spinning then
            BJ:PlaySfx("Arcade\\reel_spin.ogg")
        end
    end)

    local SOUND_LEAD = 0.08
    local ANTICIPATION_SECS = 2.2   -- length of anticipation3.ogg
    local elapsed, tick = 0, 0
    local stopAt, stopped, anticipate = {}, {}, {}
    local epicFifth = false   -- reel 5 is about to land the FIFTH coin
    do
        -- pass 1: which reels sweat? (two coins already in view)
        local cum = 0
        for r = 1, REELS do
            if cum >= 2 then anticipate[r] = true end
            if r == REELS and cum >= 4 then
                -- four coins showing and the last reel carries another:
                -- the fireshot is launching with a fifth coin on deck
                for row = 1, ROWS do
                    if result.grid[r][row] == "token" then epicFifth = true break end
                end
            end
            for row = 1, ROWS do
                if result.grid[r][row] == "token" then cum = cum + 1 end
            end
        end
        -- pass 2: stop times - every sweating reel holds for one full
        -- anticipation track; the epic fifth-coin moment gets two plays
        local t = 0.5
        for r = 1, REELS do
            local gap = 0.28
            if anticipate[r] then
                gap = (r == REELS and epicFifth) and ANTICIPATION_SECS * 2 or ANTICIPATION_SECS
            end
            t = t + gap
            stopAt[r] = t
            stopped[r] = false
        end
    end
    -- Every sweating reel gets its own full play of the anticipation track
    -- (its stop is timed to the track length, so nothing gets cut); the 5th
    -- reel holds twice as long and plays the track back to back.
    local sweating = {}
    local antSound = {}
    for r = 1, REELS do
        C_Timer.After(math.max(0, stopAt[r] - SOUND_LEAD), function()
            if self.spinning then
                BJ:PlaySfx("Arcade\\reel_stop" .. ((r - 1) % 3 + 1) .. ".ogg")
            end
        end)
        if anticipate[r] then
            C_Timer.After(stopAt[r - 1] or 0, function()
                if self.spinning and not stopped[r] then
                    -- the sweat: anticipation track, pulsing gold ring,
                    -- autocast shine + proc glow where the client has them,
                    -- symbols blown up and the flicker doubled (driver below)
                    local reel = self.reels[r]
                    local _, h = BJ:PlaySfx("Arcade\\anticipation3.ogg")
                    antSound[r] = h
                    if r == REELS and epicFifth then
                        -- double-length hold: second play chained on
                        C_Timer.After(ANTICIPATION_SECS, function()
                            if self.spinning and not stopped[r] then
                                local _, h2 = BJ:PlaySfx("Arcade\\anticipation3.ogg")
                                antSound[r] = h2
                            end
                        end)
                    end
                    sweating[r] = true
                    reel:SetBackdropBorderColor(1, 0.85, 0.2, 1)
                    reel.sweatGlow:Show()
                    if reel.shine and AutoCastShine_AutoCastStart then
                        AutoCastShine_AutoCastStart(reel.shine)
                    end
                    if ActionButton_ShowOverlayGlow then
                        ActionButton_ShowOverlayGlow(reel)
                    end
                    for row = 1, ROWS do
                        reel.icons[row]:SetSize(ICON + 18, ICON + 18)
                    end
                end
            end)
        end
    end
    local fastTick = 0
    self.spinDriver:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        tick = tick + dt
        fastTick = fastTick + dt
        local flickerStrip = result.rich and BJ.Arcade.Slots.RICH_STRIP or nil
        if tick >= 0.06 then
            tick = 0
            for r = 1, REELS do
                if not stopped[r] and not sweating[r] then self:FlickerReel(r, flickerStrip) end
            end
        end
        if fastTick >= 0.03 then
            fastTick = 0
            for r = 1, REELS do
                if not stopped[r] and sweating[r] then
                    self:FlickerReel(r, flickerStrip)
                    self.reels[r].sweatGlow:SetAlpha(0.5 + 0.5 * math.abs(math.sin(elapsed * 6)))
                end
            end
        end
        for r = 1, REELS do
            if not stopped[r] and elapsed >= stopAt[r] then
                stopped[r] = true
                local reel = self.reels[r]
                reel:SetBackdropBorderColor(0.55, 0.45, 0.2, 1)
                if sweating[r] then
                    sweating[r] = nil
                    reel.sweatGlow:Hide()
                    if reel.shine and AutoCastShine_AutoCastStop then
                        AutoCastShine_AutoCastStop(reel.shine)
                    end
                    if ActionButton_HideOverlayGlow then
                        ActionButton_HideOverlayGlow(reel)
                    end
                    for row = 1, ROWS do
                        reel.icons[row]:SetSize(ICON, ICON)
                    end
                end
                if antSound[r] and StopSound then
                    StopSound(antSound[r])   -- safety: windows match the track, so usually a no-op
                    antSound[r] = nil
                end
                for row = 1, ROWS do
                    self.reels[r].icons[row]:SetTexture(BJ.Arcade.Slots:IconFor(result.grid[r][row]))
                end
            end
        end
        if stopped[REELS] then
            self.spinDriver:SetScript("OnUpdate", nil)
            self.spinDriver:Hide()
            self.spinning = false
            BJ.Arcade.Slots:SettleSpin(result)   -- the win pays out only now
            self:ShowResult(result)
        end
    end)
    self.spinDriver:Show()
end

-- Seconds each step of the win parade holds the stage (shared by the
-- parade itself and the auto-spin wait that must sit through one cycle)
local PARADE_STEP_SECONDS = 1.4

function SUI:ShowResult(result)
    self:UpdateDisplay()

    -- landed coins always show their face value
    self:ShowCoinValues(result.coins)

    if result.fireshot then
        self.bonusActive = true          -- lock the machine through the fanfare
        self:HighlightTokens(result.tokenCells)
        self:SetWinText("|cffff9933FIRESHOT! " .. result.coinCount ..
            " coins - HOLD & SPIN!|r")
        BJ:PlaySfx("Arcade\\jackpot.ogg", "Master")
        UI.Lobby:TrixieReact(self.frame, "love", 6)
        UI.Lobby:PlayTrixieVoice("jackpot", { cd = 8 })
        C_Timer.After(1.2, function() SUI:StartFireshot(result) end)
        return
    end

    if result.bonus then
        self.bonusActive = true          -- lock the machine through the fanfare
        self:HighlightTokens(result.tokenCells)
        self:SetWinText("|cff88ccffBONUS! Three WoW Tokens!|r")
        BJ:PlaySfx("Arcade\\vibrant_win.ogg", "Master")
        UI.Lobby:TrixieReact(self.frame, "love", 5)
        C_Timer.After(0.8, function() SUI:StartBonus(result.totalBet) end)
        return
    end

    if result.payout > 0 then
        local best = result.wins[1]
        local label = best and (best.count .. "x " .. best.sym) or "Winner"
        local big = result.payout >= 20 * result.totalBet
        local moderate = not big and result.payout >= 5 * result.totalBet
        if big then
            BJ:PlaySfx("Arcade\\jackpot.ogg", "Master")
            BJ:PlaySfx("Arcade\\coin_shower.ogg")
            UI.Lobby:TrixieReact(self.frame, "love", 5)
            UI.Lobby:PlayTrixieVoice("bigwin", { cd = 8 })
        elseif moderate then
            BJ:PlaySfx("Arcade\\vibrant_win.ogg")
            UI.Lobby:TrixieReact(self.frame, "win", 4)
        else
            BJ:PlaySfx("Arcade\\payout_small.ogg")
            UI.Lobby:TrixieReact(self.frame, "win", 4)
        end
        -- roll the win up; the flash parade and any queued auto-spin wait
        -- until the meter lands. Auto-spin then waits for ONE FULL parade
        -- cycle - every winning line gets its moment (plus the TOTAL step)
        -- before the next spin wipes the stage.
        self:RollUpWin(result.payout, label, function()
            self:StartWinFlash(result.wins, big)
            if self.autoSpin then
                local steps = #result.wins + (#result.wins > 1 and 1 or 0)
                self:QueueAutoSpin(steps * PARADE_STEP_SECONDS + 0.2)
            end
        end)
    else
        self:SetWinText("|cff888888No luck - spin again!|r")
        if math.random(6) == 1 then   -- she only mocks you sometimes
            UI.Lobby:TrixieReact(self.frame, "lose", 3)
        end
        if self.autoSpin then self:QueueAutoSpin(1.4) end
    end
end

-- Count the win banner up from 0 to the payout with coin ticks - bigger
-- wins roll longer.
function SUI:RollUpWin(amount, label, onDone)
    self.rollupDriver = self.rollupDriver or CreateFrame("Frame")
    local drv = self.rollupDriver
    local dur = (amount <= 10 and 0.6) or (amount <= 100 and 1.2)
        or (amount <= 1000 and 1.8) or 2.4
    local t, lastTick = 0, 0
    drv:SetScript("OnUpdate", function(_, dt)
        t = t + dt
        local p = math.min(t / dur, 1)
        self.winShown = math.floor(amount * p)
        self:SetWinText("|cff00ff00" .. label .. "!  +" ..
            fmtBig(self.winShown) .. " credits|r")
        if self.meterWinFS then
            self.meterWinFS:SetText("|cffffe100WIN|r " .. fmtBig(self.winShown))
        end
        if t - lastTick >= 0.11 and p < 1 then
            lastTick = t
            BJ:PlaySfx("coin.ogg")
        end
        if p >= 1 then
            drv:SetScript("OnUpdate", nil)
            if onDone then onDone() end
        end
    end)
end

-- Vegas mode: parade each winning line one at a time - its cells strobe
-- between gold and the line colour, the winning symbols pulse, the win banner
-- shows THAT line's pay, and the cabinet border runs a marquee. With several
-- wins (or a multi-win total) the parade cycles through them and never stops
-- until the next spin clears it.
function SUI:StartWinFlash(wins, big)
    self:StopWinFlash()
    if not wins or #wins == 0 then return end
    if not self.flashDriver then
        self.flashDriver = CreateFrame("Frame")
        self.flashDriver:Hide()
    end

    -- Build the parade: one step per winning line, plus a TOTAL step when
    -- there's more than one thing to celebrate.
    local steps = {}
    local total = 0
    for _, w in ipairs(wins) do
        steps[#steps + 1] = w
        total = total + w.pay
    end
    if #wins > 1 then
        steps[#steps + 1] = { totalStep = true, pay = total }
    end

    local STEP_SECONDS = PARADE_STEP_SECONDS
    local speed = big and 12 or 9
    local idx, t = 1, 0

    local function showStep(step)
        self:ClearHighlights()
        for r = 1, REELS do
            for row = 1, ROWS do self.reels[r].icons[row]:SetSize(ICON, ICON) end
        end
        for _, markers in pairs(self.lineMarkers) do
            for _, m in ipairs(markers) do m:SetSize(24, 24) end
        end
        self:UpdateLineMarkers()
        if step.totalStep then
            self.paradeLine = nil
            if self.lineOverlay then self.lineOverlay:Hide() end
            self:SetWinText("|cffffd700TOTAL|r  |cff00ff00+" .. fmtBig(step.pay) .. " credits|r")
        else
            self.paradeLine = step.line
            self:ShowLineOverlay(step.line)   -- white trace across the paying line
            self:SetWinText(string.format("|cffffd700Line %d|r  |cff00ff00%dx %s  +%s credits|r",
                step.line, step.count, step.sym, fmtBig(step.pay)))
        end
    end
    showStep(steps[1])

    self.flashDriver:SetScript("OnUpdate", function(_, dt)
        t = t + dt
        if t >= STEP_SECONDS then
            t = t - STEP_SECONDS
            idx = (idx % #steps) + 1
            showStep(steps[idx])
        end

        local step = steps[idx]
        local phase = math.sin(t * speed)
        local a = 0.4 + 0.45 * math.abs(phase)
        local flashWins = step.totalStep and wins or { step }
        for _, w in ipairs(flashWins) do
            local col = LINE_COLORS[w.line] or { 1, 0.85, 0.2 }
            for i = 1, w.count do
                local cell = w.cells[i]
                local reel = self.reels[cell.reel]
                local hl = reel.hl[cell.row]
                if phase > 0 then
                    hl:SetColorTexture(1, 0.9, 0.15, a)            -- gold beat
                else
                    hl:SetColorTexture(col[1], col[2], col[3], a)  -- line colour beat
                end
                hl:Show()
                local size = ICON + 6 * math.abs(phase)
                reel.icons[cell.row]:SetSize(size, size)
            end
            -- the line's markers beat right along with the icons
            for _, m in ipairs(self.lineMarkers[w.line] or {}) do
                local ms = 24 + 5 * math.abs(phase)
                m:SetSize(ms, ms)
                if phase > 0 then
                    m:SetBackdropBorderColor(1, 0.9, 0.15, 1)
                else
                    m:SetBackdropBorderColor(col[1], col[2], col[3], 1)
                end
            end
        end

        -- cabinet border marquee
        local b = 0.5 + 0.5 * math.abs(math.sin(t * speed * 0.7))
        self.frame:SetBackdropBorderColor(1 * b, 0.8 * b, 0.15, 1)
    end)
    self.flashDriver:Show()
end

function SUI:StopWinFlash()
    if self.flashDriver then
        self.flashDriver:SetScript("OnUpdate", nil)
        self.flashDriver:Hide()
    end
    if self.frame then
        self.frame:SetBackdropBorderColor(0.7, 0.55, 0.2, 1)
    end
    for r = 1, REELS do
        for row = 1, ROWS do
            self.reels[r].icons[row]:SetSize(ICON, ICON)
        end
    end
    self.paradeLine = nil
    if self.lineOverlay then self.lineOverlay:Hide() end
    if self.lineMarkers then
        for _, markers in pairs(self.lineMarkers) do
            for _, m in ipairs(markers) do m:SetSize(24, 24) end
        end
        self:UpdateLineMarkers()
    end
end

local function styleButton(btn, enabled, r, g, b)
    if enabled then
        btn:Enable()
        btn:SetBackdropColor(r, g, b, 1)
        btn:SetBackdropBorderColor(r + 0.15, g + 0.3, b + 0.15, 1)
    else
        btn:Disable()
        btn:SetBackdropColor(0.15, 0.15, 0.15, 1)
        btn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    end
end

-- The five progressive pots, full numbers, ticking up live in their own
-- shaded windows (the 1s ticker calls this so the accumulation is visible
-- in real time). Ineligible pots dim to show the bet isn't riding for them.
function SUI:UpdateJackpotMarquee()
    if not self.jackpotBoxes then return end
    local Slots = BJ.Arcade.Slots
    local totalBet = (self.lines or 5) * (self.betPerLine or 1)
    for tier, box in pairs(self.jackpotBoxes) do
        box.value:SetText(fmtBig(Slots:GetJackpot(tier)))
        local minBet = (Slots.JACKPOT_MIN_BET and Slots.JACKPOT_MIN_BET[tier]) or 0
        box:SetAlpha(totalBet >= minBet and 1 or 0.35)
    end
end

function SUI:UpdateDisplay()
    if not self.frame then return end
    local Arcade = BJ.Arcade
    local Slots = Arcade.Slots
    local credits = Arcade:GetCredits()
    local db = Arcade:GetDB()

    self.linesVal:SetText(tostring(self.lines))
    self.betVal:SetText(fmtBet(self.betPerLine))
    local totalBet = self.lines * self.betPerLine
    self:UpdateJackpotMarquee()
    if self.meterWinFS then
        self.meterWinFS:SetText("|cffffe100WIN|r " .. fmtBig(self.winShown or 0))
        self.meterCreditFS:SetText("|cffffe100CREDIT|r " .. fmtBig(credits))
        self.meterBetFS:SetText("|cffffe100BET|r " .. fmtBet(totalBet))
        self.meterSubFS:SetText("|cff888888best win: " .. fmtBig(db.bestSlotsWin or 0) .. "|r   " ..
            "|cffcc8866refills: " .. Arcade:GetLifetimeComps() .. "|r")
    end
    self:UpdateLineMarkers()

    local busy = self.spinning or self.bonusActive
    self.linesDown:SetEnabled(not busy)
    self.linesUp:SetEnabled(not busy)
    self.betDown:SetEnabled(not busy)
    self.betUp:SetEnabled(not busy)

    if credits < 1 then
        self.spinBtn.text:SetText("COMP\nME")
        styleCircle(self.spinBtn, not busy, 0.95, 0.65, 0.25)
        setGlow(self.spinBtn, false)
        styleButton(self.maxBtn, false, 0, 0, 0)
    else
        local canSpin = not busy and credits >= totalBet
        self.spinBtn.text:SetText("SPIN\n|cffffd700" .. fmtBet(totalBet) .. "|r")
        styleCircle(self.spinBtn, canSpin, 0.35, 0.95, 0.35)
        setGlow(self.spinBtn, canSpin)
        styleButton(self.maxBtn, not busy, 0.35, 0.28, 0.1)
    end
    if self.maxLinesBtn then
        styleButton(self.maxLinesBtn, not busy and self.lines < Slots.MAX_LINES, 0.22, 0.3, 0.42)
    end

    if self.autoBtn then
        if self.autoSpin then
            self.autoBtn.text:SetText("AUTO\n|cff00ff00" .. (self.autoLeft or 0) .. "|r")
            styleCircle(self.autoBtn, true, 0.35, 0.95, 0.35)
            setGlow(self.autoBtn, true)
        else
            self.autoBtn.text:SetText("AUTO")
            styleCircle(self.autoBtn, credits >= 1, 0.62, 0.62, 0.72)
            setGlow(self.autoBtn, false)
        end
    end
end

--[[
    BONUS MINI-GAMES
    One of three is chosen at random when 3+ tokens land on active lines.
]]

function SUI:EnsureBonusFrame()
    if self.bonus then return self.bonus end
    local b = CreateFrame("Frame", nil, self.frame, "BackdropTemplate")
    b:SetFrameStrata("DIALOG")
    b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 3 })
    b:SetBackdropColor(0.06, 0.03, 0.12, 0.98)
    b:SetBackdropBorderColor(0.8, 0.65, 0.2, 1)
    b:EnableMouse(true)
    b:Hide()

    -- Two layouts: "full" covers the reels (chest / wheel), "banner" is a
    -- slim strip UNDER the reels so free spins can play out on the real
    -- machine in plain view.
    function b.SetLayout(_, mode)
        b:ClearAllPoints()
        if mode == "banner" then
            b:SetPoint("TOPLEFT", SUI.reelArea, "BOTTOMLEFT", -30, -28)
            b:SetPoint("TOPRIGHT", SUI.reelArea, "BOTTOMRIGHT", 30, -28)
            b:SetHeight(124)
            b:SetBackdropColor(0.06, 0.03, 0.12, 0.9)
        else
            b:SetPoint("TOPLEFT", SUI.reelArea, "TOPLEFT", -30, 28)
            b:SetPoint("BOTTOMRIGHT", SUI.reelArea, "BOTTOMRIGHT", 30, -28)
            b:SetBackdropColor(0.06, 0.03, 0.12, 0.98)
        end
    end

    b.title = b:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    b.title:SetPoint("TOP", 0, -12)
    b.title:SetFont("Fonts\\FRIZQT__.TTF", 22, "THICKOUTLINE")

    b.sub = b:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    b.sub:SetPoint("TOP", b.title, "BOTTOM", 0, -6)
    b.sub:SetWidth(reelAreaW() + 30)   -- wrap inside the box instead of spilling
    b.sub:SetJustifyH("CENTER")
    b.sub:SetSpacing(2)

    b.area = CreateFrame("Frame", nil, b)
    b.area:SetPoint("TOPLEFT", 0, -78)
    b.area:SetPoint("BOTTOMRIGHT", 0, 52)

    b.collect = CreateFrame("Button", nil, b, "BackdropTemplate")
    b.collect:SetSize(160, 32)
    b.collect:SetPoint("BOTTOM", 0, 10)
    b.collect:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
    b.collect.text = b.collect:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.collect.text:SetPoint("CENTER")
    b.collect:SetScript("OnClick", function() SUI:EndBonus() end)
    b.collect:Hide()

    self.bonus = b
    return b
end

function SUI:StartBonus(stake)
    local Bonus = BJ.Arcade.Bonus
    self.bonusActive = true
    self.bonusWon = 0
    self:StopWinFlash()
    self:UpdateDisplay()
    local b = self:EnsureBonusFrame()
    -- clear any previous widgets in the play area
    if b.widgets then for _, w in ipairs(b.widgets) do w:Hide() end end
    b.widgets = {}
    b.collect:Hide()
    b:SetLayout("full")
    b:Show()

    local kind = Bonus:RandomType()
    if kind == "chest" then
        self:BonusChest(b, stake)
    elseif kind == "wheel" then
        self:BonusWheel(b, stake)
    else
        self:BonusFreeSpins(b, stake)
    end
end

function SUI:EndBonus()
    if self.bonus then self.bonus:Hide() end
    self.bonusActive = false
    self:SetReelsDimmed(false)     -- hold & spin dims the board; restore it
    if self.bonusWon and self.bonusWon > 0 then
        self:SetWinText("|cff00ff00BONUS win: +" .. self.bonusWon .. " credits!|r")
        self.winShown = self.bonusWon   -- the meter shows the bonus haul too
    end
    self:UpdateDisplay()
    if self.autoSpin then self:QueueAutoSpin(1.6) end   -- resume auto play
end

-- Loot Chest: pick one of three hidden prizes. Chests are icon art in clearly
-- visible clickable slots - the picked one swaps to the OPEN chest with a gold
-- burst and a little lid-pop bounce. (An earlier build embedded the raw world
-- chest .m2 in a PlayerModel; loading arbitrary doodad models can hard-crash
-- the client, so the 3D chest is gone for good.)
function SUI:BonusChest(b, stake)
    b.title:SetText("|cffffd700LOOT CHEST BONUS|r")
    b.sub:SetText("Pick a chest to loot!")
    local prizes = BJ.Arcade.Bonus:MakeChests(stake)
    local picked = false
    local n = #prizes
    local gap = 28
    local cw = 120
    local totalW = n * cw + (n - 1) * gap

    for i = 1, n do
        local chest = CreateFrame("Button", nil, b.area, "BackdropTemplate")
        chest:SetSize(cw, cw)
        chest:SetPoint("CENTER", b.area, "CENTER", -totalW / 2 + (i - 0.5) * (cw + gap) - gap / 2, 6)
        chest:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
        chest:SetBackdropColor(0.1, 0.07, 0.03, 1)
        chest:SetBackdropBorderColor(0.75, 0.6, 0.2, 1)
        chest:SetScript("OnEnter", function(s)
            if not picked then s:SetBackdropBorderColor(1, 0.9, 0.3, 1) end
        end)
        chest:SetScript("OnLeave", function(s)
            s:SetBackdropBorderColor(0.75, 0.6, 0.2, 1)
        end)

        -- gold burst behind the icon, revealed on open
        local burst = chest:CreateTexture(nil, "BORDER")
        burst:SetPoint("CENTER")
        burst:SetSize(cw * 1.15, cw * 1.15)
        burst:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
        burst:SetVertexColor(1, 0.85, 0.2, 0)
        chest.burst = burst

        -- lockbox closed, gold pile when opened (both icons ship with every
        -- client - the TreasureChest01c/d art doesn't exist on classic ones)
        local icon = chest:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("TOPLEFT", 10, -10)
        icon:SetPoint("BOTTOMRIGHT", -10, 10)
        icon:SetTexture("Interface\\Icons\\INV_Box_01")   -- closed
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        chest.icon = icon

        local prizeFS = chest:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        prizeFS:SetPoint("TOP", chest, "BOTTOM", 0, -4)
        prizeFS:SetText("|cffffd700?|r")
        chest.prizeFS = prizeFS

        chest:SetScript("OnClick", function()
            if picked then return end
            picked = true
            BJ.Arcade:Award(prizes[i])
            self.bonusWon = prizes[i]

            -- reveal: the pick spills its gold, ghosts on the rest
            for j, c2 in ipairs(b.widgets) do
                c2.icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_02")  -- opened: gold!
                if j ~= i then
                    c2.icon:SetVertexColor(0.35, 0.35, 0.35)
                    c2:SetBackdropBorderColor(0.35, 0.3, 0.2, 1)
                end
                c2.prizeFS:SetText((j == i and "|cff00ff00" or "|cff888888") .. "+" .. fmtBet(prizes[j]) .. "|r")
            end

            -- lid-pop: quick bounce + gold burst fading out on the picked chest
            local t = 0
            local driver = CreateFrame("Frame")
            driver:SetScript("OnUpdate", function(_, dt)
                t = t + dt
                local p = math.min(t / 0.6, 1)
                local bounce = math.sin(p * math.pi) * 10
                chest.icon:ClearAllPoints()
                chest.icon:SetPoint("TOPLEFT", 10 - bounce * 0.4, -10 + bounce)
                chest.icon:SetPoint("BOTTOMRIGHT", -10 + bounce * 0.4, 10 + bounce * 0.4)
                chest.burst:SetVertexColor(1, 0.85, 0.2, 0.7 * (1 - p))
                if p >= 1 then driver:SetScript("OnUpdate", nil) end
            end)

            local big = prizes[i] >= 20 * math.max(1, stake)
            BJ:PlaySfx(big and "Arcade\\jackpot.ogg" or "chips.ogg", big and "Master" or "SFX")
            b.sub:SetText("You looted |cff00ff00" .. prizes[i] .. "|r credits!")
            b.collect.text:SetText("COLLECT " .. prizes[i])
            styleButton(b.collect, true, 0.15, 0.35, 0.15)
            b.collect:Show()
        end)
        b.widgets[i] = chest
    end
end

-- Bonus Wheel: a proper wheel like the roulette table - prize pockets ride a
-- spinning disc, a fixed pointer at the top, and the wheel decelerates until
-- one pocket lands under the pointer.
function SUI:BonusWheel(b, stake)
    b.title:SetText("|cffffd700BONUS WHEEL|r")
    b.sub:SetText("Round and round she goes...")
    local prizes = BJ.Arcade.Bonus:MakeWheel(stake)
    local n = #prizes

    local DISC_R = 118        -- disc radius (px)
    local POCKET_R = 84       -- pocket ring radius

    -- the disc
    local disc = CreateFrame("Frame", nil, b.area)
    disc:SetSize(DISC_R * 2, DISC_R * 2)
    disc:SetPoint("CENTER", b.area, "CENTER", 0, -4)
    local discTex = disc:CreateTexture(nil, "BACKGROUND")
    discTex:SetAllPoints()
    discTex:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
    discTex:SetVertexColor(0.1, 0.06, 0.14, 0.95)
    local rim = disc:CreateTexture(nil, "BORDER")
    rim:SetPoint("TOPLEFT", -6, 6)
    rim:SetPoint("BOTTOMRIGHT", 6, -6)
    rim:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
    rim:SetVertexColor(0.75, 0.6, 0.2, 0.5)
    local hub = disc:CreateTexture(nil, "ARTWORK")
    hub:SetSize(30, 30)
    hub:SetPoint("CENTER")
    hub:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
    hub:SetVertexColor(0.75, 0.6, 0.2, 1)
    b.widgets[#b.widgets + 1] = disc

    -- the fixed pointer at 12 o'clock
    local pointer = b.area:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    pointer:SetPoint("BOTTOM", disc, "TOP", 0, -12)
    pointer:SetFont("Fonts\\FRIZQT__.TTF", 26, "THICKOUTLINE")
    pointer:SetText("|cffffd700V|r")
    b.widgets[#b.widgets + 1] = pointer

    -- prize pockets around the ring, roulette-style alternating colours
    local pockets = {}
    for i = 1, n do
        local p = CreateFrame("Frame", nil, disc)
        p:SetSize(52, 52)
        p.bg = p:CreateTexture(nil, "BACKGROUND")
        p.bg:SetAllPoints()
        p.bg:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
        if i % 2 == 1 then p.bg:SetVertexColor(0.6, 0.12, 0.12, 1)
        else p.bg:SetVertexColor(0.1, 0.1, 0.12, 1) end
        p.text = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        p.text:SetPoint("CENTER")
        p.text:SetText("|cffffd700" .. fmtBet(prizes[i]) .. "|r")
        pockets[i] = p
    end

    local TWO_PI = 2 * math.pi
    local slice = TWO_PI / n
    local function layout(rot)
        for i = 1, n do
            local theta = (i - 1) * slice + rot
            pockets[i]:ClearAllPoints()
            pockets[i]:SetPoint("CENTER", disc, "CENTER",
                POCKET_R * math.sin(theta), POCKET_R * math.cos(theta))
        end
    end
    layout(0)

    -- spin: several laps, ease out, land the target pocket under the pointer
    local target = math.random(n)
    local rotFinal = 4 * TWO_PI - (target - 1) * slice
    local DURATION = 4.5
    local t = 0
    local lastTop = nil
    local driver = CreateFrame("Frame")
    driver:SetScript("OnUpdate", function(_, dt)
        t = math.min(t + dt, DURATION)
        local p = t / DURATION
        local rot = rotFinal * (1 - (1 - p) ^ 3)
        layout(rot)

        -- click as each pocket passes the pointer
        local top = math.floor(((-rot) % TWO_PI) / slice + 0.5) % n + 1
        if top ~= lastTop then
            lastTop = top
            BJ:PlaySfx("flycard.ogg")
        end

        if t >= DURATION then
            driver:SetScript("OnUpdate", nil)
            local prize = prizes[target]
            BJ.Arcade:Award(prize)
            self.bonusWon = prize
            pockets[target].bg:SetVertexColor(0.15, 0.7, 0.2, 1)
            b.sub:SetText("You win |cff00ff00" .. prize .. "|r credits!")
            b.collect.text:SetText("COLLECT " .. prize)
            styleButton(b.collect, true, 0.15, 0.35, 0.15)
            b.collect:Show()
            BJ:PlaySfx("Arcade\\jackpot.ogg", "Master")
        end
    end)
end

-- Free Spins: N automatic spins at the triggering bet with a global win
-- multiplier, played out ON THE REAL REELS - the bonus frame drops to a slim
-- banner under the machine so every spin, lock and win is visible.
function SUI:BonusFreeSpins(b, stake)
    local Slots = BJ.Arcade.Slots
    local count, mult = BJ.Arcade.Bonus:MakeFreeSpins()
    b:SetLayout("banner")
    b.title:SetText("|cffffd700FREE SPINS|r  |cff88ccffx" .. mult .. "|r")
    b.sub:SetText(string.format("Spins left: |cffffd700%d|r     Total won: |cff00ff00%d|r", count, 0))

    local left, won = count, 0
    local betPerLine = math.max(1, math.floor(stake / math.max(1, self.lines)))
    self.fsDriver = self.fsDriver or CreateFrame("Frame")

    local function finish()
        self.fsDriver:SetScript("OnUpdate", nil)
        self.bonusWon = won
        b.sub:SetText("Free spins done - |cff00ff00+" .. won .. "|r credits!")
        b.collect.text:SetText("COLLECT " .. won)
        styleButton(b.collect, true, 0.15, 0.35, 0.15)
        b.collect:Show()
    end

    local function oneSpin()
        if left <= 0 then finish() return end
        left = left - 1

        -- roll the outcome on the BONUS strip - richer symbols, and WoW
        -- Tokens are far more common; 4+ tokens in view adds extra spins
        local grid = Slots:GridFromStops(Slots:RollStops(Slots.BONUS_STRIP), Slots.BONUS_STRIP)
        local wins, pay = Slots:EvaluateGrid(grid, betPerLine, self.lines)
        pay = pay * mult
        local tokensInView = 0
        for r = 1, REELS do
            for row = 1, ROWS do
                if grid[r][row] == "token" then tokensInView = tokensInView + 1 end
            end
        end
        local retrigger = (tokensInView >= Slots.FREESPIN_RETRIGGER)
        if retrigger then left = left + Slots.FREESPIN_EXTRA end
        self.grid = grid
        self:ClearHighlights()
        -- free spins run themselves: no lever, just the reel whir
        BJ:PlaySfx("Arcade\\reel_spin.ogg")

        local SOUND_LEAD = 0.08
        local elapsed, tick = 0, 0
        local stopAt, stopped = {}, {}
        for r = 1, REELS do stopAt[r] = 0.25 + r * 0.16; stopped[r] = false end
        for r = 1, REELS do
            C_Timer.After(math.max(0, stopAt[r] - SOUND_LEAD), function()
                if self.bonusActive then
                    BJ:PlaySfx("Arcade\\reel_stop" .. ((r - 1) % 3 + 1) .. ".ogg")
                end
            end)
        end

        self.fsDriver:SetScript("OnUpdate", function(_, dt)
            elapsed = elapsed + dt
            tick = tick + dt
            if tick >= 0.06 then
                tick = 0
                for r = 1, REELS do if not stopped[r] then self:FlickerReel(r) end end
            end
            for r = 1, REELS do
                if not stopped[r] and elapsed >= stopAt[r] then
                    stopped[r] = true
                    for row = 1, ROWS do
                        self.reels[r].icons[row]:SetTexture(Slots:IconFor(grid[r][row]))
                    end
                end
            end
            if stopped[REELS] then
                self.fsDriver:SetScript("OnUpdate", nil)
                if pay > 0 then
                    BJ.Arcade:Award(pay)
                    won = won + pay
                    self:HighlightWins(wins)
                    BJ:PlaySfx("Arcade\\payout_small.ogg")
                end
                local extra = ""
                if pay > 0 then extra = "   |cff00ff00+" .. pay .. "!|r" end
                if retrigger then
                    extra = extra .. "   |cff88ccff" .. tokensInView .. " Tokens: +" ..
                        Slots.FREESPIN_EXTRA .. " spins!|r"
                    BJ:PlaySfx("Arcade\\coin_shower.ogg")
                end
                b.sub:SetText(string.format("Spins left: |cffffd700%d|r     Total won: |cff00ff00%d|r%s",
                    left, won, extra))
                C_Timer.After((pay > 0 or retrigger) and 1.0 or 0.5, oneSpin)
            end
        end)
        self.fsDriver:Show()
    end

    C_Timer.After(0.8, oneSpin)
end

--[[
    HOLD & SPIN (Fireshot-style, modelled on Stampede Fury)
    Plays on the real reels with the banner frame keeping score: the
    triggering coins lock in place, everything else dims, and each respin
    flickers only the empty cells. Any new coin locks with its value shown
    and resets the respins to 3. When the respins run out you collect every
    coin - and locking GRAND_FILL (20) or more of the 25 positions hits the
    progressive GRAND jackpot.
]]
function SUI:StartFireshot(result)
    local Slots = BJ.Arcade.Slots
    self.bonusActive = true
    self.bonusWon = 0
    self:StopWinFlash()
    self:UpdateDisplay()

    local b = self:EnsureBonusFrame()
    if b.widgets then for _, w in ipairs(b.widgets) do w:Hide() end end
    b.widgets = {}
    b.collect:Hide()
    b:SetLayout("banner")
    b:Show()
    b.title:SetText("|cffff9933HOLD & SPIN|r")

    local state = Slots:FireshotStart(result.coins, result.totalBet)

    -- board: dim everything, then pop the locked coins back to full colour
    self:ClearHighlights()
    self:SetReelsDimmed(true)
    local function lockCell(key, coin)
        local reel, row = key:match("^(%d+):(%d+)$")
        reel, row = tonumber(reel), tonumber(row)
        if not reel then return end
        local R = self.reels[reel]
        R.icons[row]:SetTexture(Slots:IconFor("token"))
        R.icons[row]:SetVertexColor(1, 1, 1)
        R.coinFS[row]:SetText(coinLabel(coin))
        R.coinFS[row]:Show()
        local hl = R.hl[row]
        hl:SetColorTexture(1, 0.6, 0.1, 0.35)
        hl:Show()
    end
    self:ClearCoinValues()
    for key, coin in pairs(state.locked) do lockCell(key, coin) end

    local function coinsTotal()
        local t = 0
        for _, c in pairs(state.locked) do t = t + (c.value or 0) end
        return t
    end
    local function updateBanner(extra)
        b.sub:SetText(string.format(
            "Respins: |cffffd700%d|r   Coins: |cffffd700%d|r/%d   Value: |cff00ff00%s|r%s",
            state.respins, state.count, Slots.GRAND_FILL, fmtBig(coinsTotal()), extra or ""))
    end
    updateBanner()

    self.fsDriver = self.fsDriver or CreateFrame("Frame")

    local function finish()
        local total, grand, jackpots = Slots:FireshotSettle(state)
        self.bonusWon = total

        -- name every jackpot that hit
        local names = {}
        if (jackpots.mini or 0) > 0 then
            names[#names + 1] = "|cff55ff55MINI" .. (jackpots.mini > 1 and " x" .. jackpots.mini or "") .. "|r"
        end
        if (jackpots.minor or 0) > 0 then
            names[#names + 1] = "|cff55aaffMINOR" .. (jackpots.minor > 1 and " x" .. jackpots.minor or "") .. "|r"
        end
        if (jackpots.major or 0) > 0 then
            names[#names + 1] = "|cffcc66ffMAJOR" .. (jackpots.major > 1 and " x" .. jackpots.major or "") .. "|r"
        end
        if (jackpots.mega or 0) > 0 then
            names[#names + 1] = "|cffff4455MEGA" .. (jackpots.mega > 1 and " x" .. jackpots.mega or "") .. "|r"
        end
        if grand then names[#names + 1] = "|cffff3333GRAND|r" end
        local jackpotLine = (#names > 0)
            and (table.concat(names, " + ") .. " JACKPOT" .. (#names > 1 and "S" or "") .. "!  ")
            or ""

        UI.Lobby:TrixieReact(self.frame, "love", 8)
        if grand then
            b.title:SetText("|cffff3333GRAND JACKPOT!|r")
            b.sub:SetText(string.format("%s|cffff9933GRAND pays %d|r - total |cff00ff00%d credits!|r",
                jackpotLine, grand, total))
            BJ:Print("|cffff3333GRAND JACKPOT!|r Hold & Spin pays |cff00ff00" .. total .. "|r credits!")
            BJ:PlaySfx("Arcade\\jackpot.ogg", "Master")
            BJ:PlaySfx("Arcade\\vibrant_win.ogg", "Master")
        else
            b.sub:SetText(jackpotLine .. "The coins pay |cff00ff00" .. total .. "|r credits!")
            if #names > 0 then
                BJ:Print("Hold & Spin: " .. jackpotLine .. "|cff00ff00+" .. total .. " credits|r")
            end
            BJ:PlaySfx("Arcade\\jackpot.ogg", "Master")
        end
        b.collect.text:SetText("COLLECT " .. total)
        styleButton(b.collect, true, 0.15, 0.35, 0.15)
        b.collect:Show()
    end

    local oneRespin
    oneRespin = function()
        if state.done then finish() return end
        BJ:PlaySfx("Arcade\\reel_spin.ogg")

        -- flicker only the unlocked cells for a moment, then resolve
        local elapsed, tick = 0, 0
        local n = #Slots.STRIP
        self.fsDriver:SetScript("OnUpdate", function(_, dt)
            elapsed = elapsed + dt
            tick = tick + dt
            if tick >= 0.07 then
                tick = 0
                -- only the empty ARENA cells spin; the outer rows sit dim
                for _, key in ipairs(state.arenaKeys) do
                    if not state.locked[key] then
                        local r, row = key:match("^(%d+):(%d+)$")
                        local icon = self.reels[tonumber(r)].icons[tonumber(row)]
                        icon:SetTexture(Slots:IconFor(Slots.STRIP[math.random(n)]))
                        icon:SetVertexColor(0.3, 0.3, 0.35)
                    end
                end
            end
            if elapsed >= 0.8 then
                self.fsDriver:SetScript("OnUpdate", nil)
                BJ:PlaySfx("Arcade\\reel_stop2.ogg")

                local newCoins = Slots:FireshotRespin(state)
                -- empty arena cells settle on dim junk; new coins lock in
                for _, key in ipairs(state.arenaKeys) do
                    if not state.locked[key] then
                        local r, row = key:match("^(%d+):(%d+)$")
                        local icon = self.reels[tonumber(r)].icons[tonumber(row)]
                        icon:SetTexture(Slots:IconFor(Slots.STRIP[math.random(n)]))
                        icon:SetVertexColor(0.3, 0.3, 0.35)
                    end
                end
                local gotNew, gotJackpot = false, nil
                for key, coin in pairs(newCoins) do
                    gotNew = true
                    if coin.jackpot then gotJackpot = coin.jackpot end
                    lockCell(key, coin)
                end
                if gotNew then
                    BJ:PlaySfx("Arcade\\vibrant_win.ogg")   -- another coin stacks!
                    if gotJackpot then
                        updateBanner("   " .. (JACKPOT_LABEL[gotJackpot] or "") ..
                            " |cff00ff00coin locked!|r")
                    else
                        updateBanner("   |cff00ff00coin locked - respins reset!|r")
                    end
                else
                    updateBanner()
                end
                C_Timer.After(0.7, oneRespin)
            end
        end)
        self.fsDriver:Show()
    end

    C_Timer.After(0.6, oneRespin)
end

function SUI:UpdateGrantButton()
    if not self.grantBtn then return end
    self.grantBtn:SetShown(BJ.Arcade and BJ.Arcade:GrantVisible() or false)
end

function SUI:Show()
    self:Initialize()
    self:UpdateDisplay()
    self.frame:Show()
    -- opening the machine is a hardware event: pull a one-time shared jackpot
    -- baseline and flush any queued reset broadcasts to the realm channel
    if BJ.Arcade and BJ.Arcade.SyncJackpotsOnLook then BJ.Arcade:SyncJackpotsOnLook() end
end

function SUI:Hide()
    if self.frame then self.frame:Hide() end
end
