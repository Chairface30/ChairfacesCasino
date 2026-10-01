--[[
    Chairface's Casino - UI/PachinkoParlor.lua
    The Pachinko Parlor: a floor of six machines (UI.PachinkoParlor) and
    one window per machine (UI.Pachinko). Draws the board that
    BJ.Arcade.Pachinko simulates - pins, rails, the display with its three
    reels, the start pocket's tulip, the attacker, balls in flight - and
    moves the fake credits through the wallet it hands the engine: RATE
    credits a ball out, RATE credits a ball back.

    Board pixels are y-down; every board texture anchors CENTER to the
    board's TOPLEFT at (x, -y).
]]

local BJ = ChairfacesCasino
local UI = BJ.UI

UI.PachinkoParlor = {}
UI.Pachinko = { frames = {} }
local Parlor = UI.PachinkoParlor
local PKUI = UI.Pachinko

local TEX = "Interface\\AddOns\\Chairfaces Casino\\Textures\\Pachinko\\"
local WHITE = "Interface\\Buttons\\WHITE8x8"

local function Engine() return BJ.Arcade.Pachinko end

local function fmtBig(n)
    if BreakUpLargeNumbers then return BreakUpLargeNumbers(n) end
    return tostring(n)
end

local function text(parent, size, flags, template)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontNormal")
    fs:SetFont("Fonts\\FRIZQT__.TTF", size, flags or "")
    return fs
end

local function plate(parent, bg, border)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    f:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
    f:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
    return f
end

local function makeButton(parent, w, h, label, theme, size)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(w, h)
    b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    b.text = text(b, size or 12, "OUTLINE")
    b.text:SetPoint("CENTER")
    b.text:SetText(label)
    local t = theme or { accent = { 0.9, 0.8, 0.3 }, border = { 0.9, 0.8, 0.3 } }
    function b:paint()
        if not self:IsEnabled() then
            self:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
            self:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)
            self.text:SetTextColor(0.5, 0.5, 0.5)
        elseif self.hot or self.lit then
            self:SetBackdropColor(t.accent[1] * 0.5, t.accent[2] * 0.5, t.accent[3] * 0.5, 1)
            self:SetBackdropBorderColor(1, 1, 1, 1)
            self.text:SetTextColor(1, 1, 1)
        else
            self:SetBackdropColor(t.accent[1] * 0.25, t.accent[2] * 0.25, t.accent[3] * 0.25, 1)
            self:SetBackdropBorderColor(t.border[1], t.border[2], t.border[3], 1)
            self.text:SetTextColor(t.accent[1], t.accent[2], t.accent[3])
        end
    end
    b:SetScript("OnEnter", function(self) self.hot = true; self:paint() end)
    b:SetScript("OnLeave", function(self) self.hot = false; self:paint() end)
    b:paint()
    return b
end

-- Per-machine saved stats live beside the arcade credits.
local function statsFor(id)
    local db = BJ.Arcade:GetDB()
    db.pachinko = db.pachinko or {}
    db.pachinko[id] = db.pachinko[id] or { spins = 0, jackpots = 0, best = 0, ballsIn = 0, ballsOut = 0 }
    return db.pachinko[id]
end

-- =====================================================================
-- The floor

function Parlor:Build()
    local W, H = 760, 470
    local f = CreateFrame("Frame", "ChairfacesCasinoPachinkoParlor", UIParent, "BackdropTemplate")
    f:SetSize(W, H)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:SetFrameStrata("HIGH")
    f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 3 })
    f:SetBackdropColor(0.05, 0.03, 0.08, 0.98)
    f:SetBackdropBorderColor(0.8, 0.5, 0.95, 1)
    f:Hide()
    self.frame = f

    for i = 0, 18 do
        local tx = f:CreateTexture(nil, "BACKGROUND", nil, 1)
        tx:SetSize(40, H - 6)
        tx:SetPoint("TOPLEFT", 3 + i * 42, -3)
        tx:SetColorTexture(0.2, 0.05, 0.3, (i % 2 == 0) and 0.14 or 0.06)
    end

    local title = text(f, 28, "THICKOUTLINE")
    title:SetPoint("TOP", 0, -14)
    title:SetText("THE PACHINKO PARLOR")
    title:SetTextColor(0.9, 0.7, 1)
    local sub = text(f, 11, "")
    sub:SetPoint("TOP", title, "BOTTOM", 0, -4)
    sub:SetText("Six machines, one bankroll. Buy balls, find the sweet spot on the handle, wait for three of a kind.")
    sub:SetTextColor(0.8, 0.8, 0.8)

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function()
        f:Hide()
        if UI.Lobby then UI.Lobby:Show() end
    end)

    if UI.Lobby and UI.Lobby.AttachHowToPlayButton then
        UI.Lobby:AttachHowToPlayButton(f, "pachinko", 8, -8)
    end

    local credit = plate(f, { 0, 0, 0, 0.85 }, { 0.8, 0.5, 0.95, 1 })
    credit:SetSize(260, 28)
    credit:SetPoint("BOTTOM", 0, 12)
    self.creditFS = text(credit, 15, "OUTLINE")
    self.creditFS:SetPoint("CENTER")

    self.tiles = {}
    local TW, TH = 234, 170
    local gx = (W - 3 * TW) / 4
    for i, m in ipairs(Engine().MACHINES) do
        local t = m.theme
        local tile = CreateFrame("Button", nil, f, "BackdropTemplate")
        tile:SetSize(TW, TH)
        local cx, cy = (i - 1) % 3, math.floor((i - 1) / 3)
        tile:SetPoint("TOPLEFT", gx + cx * (TW + gx), -66 - cy * (TH + 14))
        tile:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 2 })
        tile:SetBackdropColor(t.bg[1], t.bg[2], t.bg[3], 1)
        tile:SetBackdropBorderColor(t.border[1], t.border[2], t.border[3], 0.8)

        local topBand = tile:CreateTexture(nil, "BACKGROUND", nil, 2)
        topBand:SetPoint("TOPLEFT", 2, -2)
        topBand:SetPoint("TOPRIGHT", -2, -2)
        topBand:SetHeight(58)
        topBand:SetColorTexture(t.bg2[1], t.bg2[2], t.bg2[3], 0.8)

        local ic = tile:CreateTexture(nil, "ARTWORK")
        ic:SetSize(44, 44)
        ic:SetPoint("TOPLEFT", 10, -8)
        ic:SetTexture(TEX .. "icon")

        local name = text(tile, 15, "OUTLINE")
        name:SetPoint("TOPLEFT", ic, "TOPRIGHT", 8, -4)
        name:SetPoint("RIGHT", tile, "RIGHT", -6, 0)
        name:SetJustifyH("LEFT")
        name:SetText(m.title)
        name:SetTextColor(t.title[1], t.title[2], t.title[3])

        local tag = text(tile, 9, "OUTLINE")
        tag:SetPoint("TOP", tile, "TOP", 0, -66)
        tag:SetWidth(TW - 16)
        tag:SetText(m.tagline)
        tag:SetTextColor(t.accent[1], t.accent[2], t.accent[3])

        local info = text(tile, 10, "")
        info:SetPoint("BOTTOMLEFT", 10, 30)
        info:SetJustifyH("LEFT")
        info:SetTextColor(0.85, 0.85, 0.85)
        tile.info = info

        local play = makeButton(tile, TW - 20, 22, "SIT DOWN", t, 12)
        play:SetPoint("BOTTOM", 0, 6)
        play:EnableMouse(false)

        tile.m = m
        tile.play = play
        tile:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(1, 1, 1, 1)
            play.hot = true; play:paint()
        end)
        tile:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(t.border[1], t.border[2], t.border[3], 0.8)
            play.hot = false; play:paint()
        end)
        tile:SetScript("OnClick", function()
            BJ:PlaySfx("Arcade\\coin_insert.ogg")
            PKUI:ShowMachine(m.id)
        end)
        self.tiles[i] = tile
    end

    if BJ.EscapeHandler then BJ.EscapeHandler:RegisterFrame("ChairfacesCasinoPachinkoParlor") end
    f:SetScript("OnShow", function() Parlor:UpdateDisplay() end)
end

function Parlor:UpdateDisplay()
    if not self.frame then return end
    self.creditFS:SetText("|cffffe100CREDITS|r " .. fmtBig(BJ.Arcade:GetCredits()))
    local PK = Engine()
    for _, tile in ipairs(self.tiles) do
        local m = tile.m
        local s = statsFor(m.id)
        local big = 0
        for _, r in ipairs(m.rounds) do if r[1] > big then big = r[1] end end
        tile.info:SetText(("1 in %d   up to %dR (%s balls)\njackpots: %d   best: %s balls"):format(
            m.odds, big, fmtBig(PK:JackpotBalls(m, big)), s.jackpots or 0, fmtBig(s.best or 0)))
    end
end

function Parlor:Show()
    if not self.frame then self:Build() end
    for _, mf in pairs(PKUI.frames) do mf:Hide() end
    self.frame:Show()
end

function Parlor:Hide()
    if self.frame then self.frame:Hide() end
end

-- =====================================================================
-- A machine window

local BOARD_W, BOARD_H = 440, 600
local SIDE_W = 210
local PAD = 14
local TOP_H = 40

function PKUI:ShowMachine(id)
    local w = self.frames[id]
    if not w then
        w = self:Build(id)
        self.frames[id] = w
    end
    if Parlor.frame then Parlor.frame:Hide() end
    w:Show()
    self:UpdateDisplay(w)
end

function PKUI:Build(id)
    local PK = Engine()
    local m = PK:GetMachine(id)
    local t = m.theme
    local FRAME_W = PAD + BOARD_W + PAD + SIDE_W + PAD
    local FRAME_H = TOP_H + BOARD_H + PAD

    local w = CreateFrame("Frame", "ChairfacesCasinoPachinko_" .. id, UIParent, "BackdropTemplate")
    w:SetSize(FRAME_W, FRAME_H)
    w:SetPoint("CENTER")
    w:SetMovable(true)
    w:EnableMouse(true)
    w:RegisterForDrag("LeftButton")
    w:SetScript("OnDragStart", w.StartMoving)
    w:SetScript("OnDragStop", w.StopMovingOrSizing)
    w:SetClampedToScreen(true)
    w:SetFrameStrata("HIGH")
    w:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 2, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    w:SetBackdropColor(t.bg[1], t.bg[2], t.bg[3], 0.98)
    w:SetBackdropBorderColor(t.border[1], t.border[2], t.border[3], 1)
    w:Hide()
    w.m = m
    w.id = id
    w.state = PK:NewMachineState(m, (time and time() or 0) + math.random(1, 100000))
    w.events = {}
    w.rate = w.rate or 5

    local title = text(w, 18, "OUTLINE")
    title:SetPoint("TOP", 0, -10)
    title:SetText(m.title)
    title:SetTextColor(t.title[1], t.title[2], t.title[3])

    local closeBtn = CreateFrame("Button", nil, w, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function()
        PK:SetFiring(w.state, false)
        w:Hide()
        Parlor:Show()
    end)
    w.closeBtn = closeBtn

    if UI.Lobby and UI.Lobby.AttachHowToPlayButton then
        UI.Lobby:AttachHowToPlayButton(w, "pachinko", 8, -8)
    end
    if UI.Lobby and UI.Lobby.AttachTrixie then
        UI.Lobby:AttachTrixie(w)
    end

    -- ===== the board =====
    local board = CreateFrame("Frame", nil, w, "BackdropTemplate")
    board:SetSize(BOARD_W, BOARD_H)
    board:SetPoint("TOPLEFT", w, "TOPLEFT", PAD, -TOP_H)
    board:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 2 })
    board:SetBackdropColor(t.bg2[1] * 0.5, t.bg2[2] * 0.5, t.bg2[3] * 0.5, 1)
    board:SetBackdropBorderColor(t.border[1], t.border[2], t.border[3], 1)
    w.board = board

    -- the display box with its three reels
    local box = PK.BOX
    local disp = CreateFrame("Frame", nil, board, "BackdropTemplate")
    disp:SetSize(box.r - box.l, box.b - box.t)
    disp:SetPoint("TOPLEFT", board, "TOPLEFT", box.l, -box.t)
    disp:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 2 })
    disp:SetBackdropColor(0.02, 0.02, 0.05, 1)
    disp:SetBackdropBorderColor(t.accent[1], t.accent[2], t.accent[3], 1)
    w.display = disp
    w.reels = {}
    for i = 1, 3 do
        local r = plate(disp, { 0.08, 0.08, 0.12, 1 }, { 0.4, 0.4, 0.5, 1 })
        r:SetSize(48, 64)
        r:SetPoint("CENTER", disp, "CENTER", (i - 2) * 54, 10)
        r.digit = text(r, 40, "OUTLINE")
        r.digit:SetPoint("CENTER")
        r.digit:SetText("7")
        r.digit:SetTextColor(t.title[1], t.title[2], t.title[3])
        w.reels[i] = r
    end
    w.modeText = text(disp, 12, "OUTLINE")
    w.modeText:SetPoint("TOP", disp, "TOP", 0, -8)
    w.modeText:SetText("NORMAL")
    w.holdDots = {}
    for i = 1, PK.HOLD_MAX do
        local d = disp:CreateTexture(nil, "OVERLAY")
        d:SetSize(10, 10)
        d:SetTexture(TEX .. "peg")
        d:SetPoint("BOTTOM", disp, "BOTTOM", (i - 2.5) * 16, 24)
        d:SetVertexColor(0.3, 0.3, 0.35, 1)
        w.holdDots[i] = d
    end
    w.dispText = text(disp, 11, "OUTLINE")
    w.dispText:SetPoint("BOTTOM", disp, "BOTTOM", 0, 8)
    w.dispText:SetText("")

    -- pins and rails (rails drawn as rows of pins)
    local st = w.state
    w.pinTex = {}
    for _, p in ipairs(st.board.pins) do
        local tx = board:CreateTexture(nil, "ARTWORK", nil, 1)
        if p.wind then
            tx:SetSize(PK.WIND_R * 2 + 2, PK.WIND_R * 2 + 2)
            tx:SetVertexColor(1, 0.45, 0.35, 1)
        else
            tx:SetSize(6, 6)
            tx:SetVertexColor(0.95, 0.85, 0.55, 1)
        end
        tx:SetTexture(TEX .. "peg")
        tx:SetPoint("CENTER", board, "TOPLEFT", p.x, -p.y)
        w.pinTex[#w.pinTex + 1] = tx
    end
    for _, r in ipairs(st.board.rails) do
        local len = math.sqrt((r.x1 - r.x0) ^ 2 + (r.y1 - r.y0) ^ 2)
        local n = math.max(1, math.floor(len / 9))
        for k = 0, n do
            local f = k / n
            local tx = board:CreateTexture(nil, "ARTWORK", nil, 1)
            tx:SetSize(5, 5)
            tx:SetTexture(TEX .. "peg")
            tx:SetVertexColor(0.8, 0.85, 1, 1)
            tx:SetPoint("CENTER", board, "TOPLEFT", r.x0 + (r.x1 - r.x0) * f, -(r.y0 + (r.y1 - r.y0) * f))
        end
    end

    -- pockets: start (with its tulip petals), sides, attacker
    local sp = st.board.start
    local startTex = plate(board, { 0.1, 0.5, 0.2, 1 }, { 0.5, 1, 0.6, 1 })
    startTex:SetSize(sp.w + 4, 12)
    startTex:SetPoint("TOP", board, "TOPLEFT", sp.x, -(sp.y - 2))
    w.startTex = startTex
    w.petals = {}
    for i, dir in ipairs({ -1, 1 }) do
        local pt = board:CreateTexture(nil, "ARTWORK", nil, 2)
        pt:SetSize(4, 14)
        pt:SetTexture(WHITE)
        pt:SetVertexColor(0.6, 1, 0.7, 1)
        pt:SetPoint("BOTTOM", board, "TOPLEFT", sp.x + dir * (sp.w / 2 + 3), -(sp.y + 2))
        pt.dir = dir
        w.petals[i] = pt
    end
    for _, s in ipairs(st.board.sides) do
        local tx = plate(board, { 0.1, 0.3, 0.5, 1 }, { 0.5, 0.8, 1, 1 })
        tx:SetSize(s.w + 4, 10)
        tx:SetPoint("TOP", board, "TOPLEFT", s.x, -(s.y - 2))
    end
    local at = st.board.attacker
    local attacker = plate(board, { 0.3, 0.2, 0.05, 1 }, { 0.6, 0.5, 0.3, 1 })
    attacker:SetSize(at.w + 4, 16)
    attacker:SetPoint("TOP", board, "TOPLEFT", at.x, -(at.y - 3))
    attacker.label = text(attacker, 9, "OUTLINE")
    attacker.label:SetPoint("CENTER")
    attacker.label:SetText("ATTACKER")
    attacker.label:SetTextColor(0.7, 0.6, 0.4)
    w.attacker = attacker

    -- balls
    w.ballTex = {}
    for i = 1, 40 do
        local b = board:CreateTexture(nil, "OVERLAY", nil, 2)
        b:SetSize(PK.BALL_R * 2 + 1, PK.BALL_R * 2 + 1)
        b:SetTexture(TEX .. "ball")
        b:SetVertexColor(0.92, 0.94, 1, 1)
        b:Hide()
        w.ballTex[i] = b
    end

    -- banner over the display for jackpots
    w.banner = text(board, 24, "THICKOUTLINE")
    w.banner:SetPoint("CENTER", board, "CENTER", 0, 150)
    w.banner:SetText("")
    w.bannerSub = text(board, 13, "OUTLINE")
    w.bannerSub:SetPoint("TOP", w.banner, "BOTTOM", 0, -4)
    w.bannerSub:SetText("")

    -- pay popups
    w.popups = {}
    for i = 1, 10 do
        local p = text(board, 12, "OUTLINE")
        p:Hide()
        w.popups[i] = p
    end

    -- ===== side panel =====
    local side = CreateFrame("Frame", nil, w)
    side:SetSize(SIDE_W, BOARD_H)
    side:SetPoint("TOPLEFT", board, "TOPRIGHT", PAD, 0)
    w.side = side

    local function label(txt, y, size)
        local fs = text(side, size or 10, "")
        fs:SetPoint("TOPLEFT", side, "TOPLEFT", 0, y)
        fs:SetText(txt)
        fs:SetTextColor(0.7, 0.7, 0.75)
        return fs
    end
    local function value(y, size)
        local fs = text(side, size or 12, "OUTLINE")
        fs:SetPoint("TOPRIGHT", side, "TOPRIGHT", 0, y)
        fs:SetJustifyH("RIGHT")
        return fs
    end

    label("CREDITS", 0)
    w.creditsText = value(-12, 20)
    w.creditsText:SetTextColor(1, 0.85, 0.2)
    label("BALLS YOU CAN BUY", -40)
    w.ballsText = value(-40, 12)

    label("CREDITS A BALL", -62)
    w.rateBtns = {}
    for i, r in ipairs(PK.RATES) do
        local b = makeButton(side, 38, 20, tostring(r), t, 11)
        b:SetPoint("TOPLEFT", side, "TOPLEFT", (i - 1) * 43, -76)
        b:SetScript("OnClick", function() PKUI:SetRate(w, r) end)
        b.rate = r
        w.rateBtns[i] = b
    end

    label("HANDLE", -106)
    w.handleText = value(-106, 11)
    local handle = CreateFrame("Slider", nil, side, "BackdropTemplate")
    handle:SetSize(SIDE_W, 18)
    handle:SetPoint("TOPLEFT", side, "TOPLEFT", 0, -120)
    handle:SetOrientation("HORIZONTAL")
    handle:SetMinMaxValues(0, 100)
    handle:SetValueStep(1)
    handle:SetValue(w.state.handle * 100)
    handle:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    handle:SetBackdropColor(0.1, 0.1, 0.12, 1)
    handle:SetBackdropBorderColor(t.border[1], t.border[2], t.border[3], 1)
    local thumb = handle:CreateTexture(nil, "ARTWORK")
    thumb:SetSize(12, 18)
    thumb:SetTexture(WHITE)
    thumb:SetVertexColor(t.accent[1], t.accent[2], t.accent[3], 1)
    if handle.SetThumbTexture then handle:SetThumbTexture(thumb) end
    handle:SetScript("OnValueChanged", function(self, v)
        PK:SetHandle(w.state, (v or 0) / 100)
        PKUI:UpdateHandleText(w)
    end)
    w.handle = handle
    local nudgeL = makeButton(side, 60, 18, "< softer", t, 10)
    nudgeL:SetPoint("TOPLEFT", side, "TOPLEFT", 0, -142)
    nudgeL:SetScript("OnClick", function() PKUI:NudgeHandle(w, -2) end)
    local nudgeR = makeButton(side, 60, 18, "harder >", t, 10)
    nudgeR:SetPoint("TOPRIGHT", side, "TOPRIGHT", 0, -142)
    nudgeR:SetScript("OnClick", function() PKUI:NudgeHandle(w, 2) end)

    local fireBtn = makeButton(side, SIDE_W, 36, "FIRE", t, 16)
    fireBtn:SetPoint("TOPLEFT", side, "TOPLEFT", 0, -170)
    fireBtn:SetScript("OnClick", function() PKUI:ToggleFire(w) end)
    w.fireBtn = fireBtn

    local div = side:CreateTexture(nil, "ARTWORK")
    div:SetSize(SIDE_W, 1)
    div:SetPoint("TOPLEFT", side, "TOPLEFT", 0, -216)
    div:SetTexture(WHITE)
    div:SetVertexColor(t.border[1], t.border[2], t.border[3], 0.6)

    label("THIS SESSION", -224, 11)
    label("Balls fired", -240)
    w.firedText = value(-240, 11)
    label("Balls paid", -254)
    w.paidText = value(-254, 11)
    label("Spins", -268)
    w.spinsText = value(-268, 11)
    label("Jackpots", -282)
    w.jackpotsText = value(-282, 11)
    label("Best jackpot", -296)
    w.bestText = value(-296, 11)

    label("ALL TIME", -320, 11)
    label("Jackpots", -336)
    w.allJackpotsText = value(-336, 11)
    label("Best jackpot", -350)
    w.allBestText = value(-350, 11)
    label("Balls in / out", -364)
    w.allBallsText = value(-364, 11)

    local div2 = side:CreateTexture(nil, "ARTWORK")
    div2:SetSize(SIDE_W, 1)
    div2:SetPoint("TOPLEFT", side, "TOPLEFT", 0, -386)
    div2:SetTexture(WHITE)
    div2:SetVertexColor(t.border[1], t.border[2], t.border[3], 0.6)

    local spec = text(side, 10, "")
    spec:SetPoint("TOPLEFT", side, "TOPLEFT", 0, -394)
    spec:SetWidth(SIDE_W)
    spec:SetJustifyH("LEFT")
    spec:SetJustifyV("TOP")
    spec:SetTextColor(0.75, 0.75, 0.8)
    local roundsTxt = {}
    for _, r in ipairs(m.rounds) do
        roundsTxt[#roundsTxt + 1] = ("%dR (%s balls) %d%%"):format(r[1], fmtBig(PK:JackpotBalls(m, r[1])), math.floor(r[2] * 100 + 0.5))
    end
    local kakTxt = m.st and (m.st .. " spins of kakuhen (ST)") or "kakuhen until the next jackpot"
    spec:SetText(("|cffffd700%s|r\n%s\n\nJackpot 1 in %d, in kakuhen 1 in %d.\n%d%% of jackpots are kakuhen: %s.%s\nStart pocket pays %d, attacker pays %d a ball, %d balls a round.\nRounds: %s"):format(
        m.tagline, m.blurb, m.odds, m.kakuhenOdds, math.floor(m.kakuhenRate * 100 + 0.5), kakTxt,
        (m.jitan or 0) > 0 and (" Even jackpots give " .. m.jitan .. " spins of jitan.") or "",
        m.startPay, m.attackerPay, m.count, table.concat(roundsTxt, ", ")))

    w:SetScript("OnUpdate", function(_, dt) PKUI:OnUpdate(w, dt) end)
    w:SetScript("OnHide", function() PK:SetFiring(w.state, false); PKUI:UpdateDisplay(w) end)

    if BJ.EscapeHandler then BJ.EscapeHandler:RegisterFrame("ChairfacesCasinoPachinko_" .. id) end

    self:SetRate(w, w.rate)
    self:UpdateHandleText(w)
    return w
end

-- ---------------------------------------------------------------------
-- Controls

function PKUI:SetRate(w, rate)
    if w.state.firing then return end
    w.rate = rate
    for _, b in ipairs(w.rateBtns) do
        b.lit = (b.rate == rate)
        b:paint()
    end
    self:UpdateDisplay(w)
end

function PKUI:UpdateHandleText(w)
    w.handleText:SetText(("%d%%"):format(math.floor(w.state.handle * 100 + 0.5)))
end

function PKUI:NudgeHandle(w, delta)
    local v = math.floor(w.state.handle * 100 + 0.5) + delta
    if v < 0 then v = 0 elseif v > 100 then v = 100 end
    w.handle:SetValue(v)
    Engine():SetHandle(w.state, v / 100)
    self:UpdateHandleText(w)
end

function PKUI:Wallet(w)
    if not w.wallet then
        local rate = function() return w.rate or 1 end
        w.wallet = {
            spend = function(balls)
                local ok = BJ.Arcade:Spend(balls * rate())
                if ok then
                    local s = statsFor(w.id)
                    s.ballsIn = (s.ballsIn or 0) + balls
                end
                return ok
            end,
            award = function(balls)
                BJ.Arcade:Award(balls * rate())
                local s = statsFor(w.id)
                s.ballsOut = (s.ballsOut or 0) + balls
            end,
        }
    end
    return w.wallet
end

function PKUI:ToggleFire(w)
    local PK = Engine()
    local st = w.state
    if st.firing then
        PK:SetFiring(st, false)
    else
        if BJ.Arcade:GetCredits() < (w.rate or 1) then
            if BJ.Arcade:GetCredits() < 1 then
                local ok, refills = BJ.Arcade:CompMe()
                if ok then
                    BJ:Print("|cff00ff00The pit boss comps you " .. BJ.Arcade.COMP_AMOUNT ..
                        " credits.|r (Refill #" .. refills .. " - she's keeping count.)")
                end
            else
                BJ:Print("|cffff8800Not enough credits for a " .. w.rate .. " credit ball. Pick a cheaper rate.|r")
            end
            self:UpdateDisplay(w)
            return
        end
        PK:SetFiring(st, true)
        BJ:PlaySfx("Arcade\\slot_lever.ogg")
    end
    self:UpdateDisplay(w)
end

-- ---------------------------------------------------------------------
-- Frame loop

function PKUI:Popup(w, x, y, txt, r, g, b)
    local p
    for _, cand in ipairs(w.popups) do
        if not cand:IsShown() then p = cand break end
    end
    if not p then p = w.popups[1] end
    p:ClearAllPoints()
    p:SetPoint("CENTER", w.board, "TOPLEFT", x, -y)
    p:SetText(txt)
    p:SetTextColor(r or 1, g or 1, b or 1)
    p:SetAlpha(1)
    p.born = GetTime()
    p.x, p.y = x, y
    p:Show()
end

function PKUI:ShowBanner(w, txt, sub, secs)
    w.banner:SetText(txt or "")
    w.bannerSub:SetText(sub or "")
    w.bannerUntil = (secs and secs > 0) and (GetTime() + secs) or nil
end

local MODE_TEXT = { normal = "NORMAL", kakuhen = "|cffff66ffKAKUHEN|r", jitan = "|cff66ccffJITAN|r" }

function PKUI:HandleEvents(w, now)
    local PK = Engine()
    local st = w.state
    local m = w.m
    for _, ev in ipairs(w.events) do
        local ty = ev.type
        if ty == "pin" then
            if now - (w.lastPinSound or 0) > 0.09 then
                w.lastPinSound = now
                BJ:PlaySfx("Kenney\\chip-lay-" .. math.random(3) .. ".ogg")
            end
        elseif ty == "start" then
            BJ:PlaySfx("Arcade\\coin_insert.ogg")
            self:Popup(w, st.board.start.x, st.board.start.y - 18, "+" .. ev.pay, 0.6, 1, 0.7)
        elseif ty == "side" then
            self:Popup(w, ev.x, ev.y - 16, "+" .. ev.pay, 0.6, 0.85, 1)
        elseif ty == "attacker" then
            if now - (w.lastPaySound or 0) > 0.25 then
                w.lastPaySound = now
                BJ:PlaySfx("Arcade\\payout_small.ogg")
            end
            self:Popup(w, st.board.attacker.x + (math.random() - 0.5) * 60, st.board.attacker.y - 20, "+" .. ev.pay, 1, 0.9, 0.4)
            w.bannerSub:SetText(("Round %d of %d   %d / %d"):format(ev.round, ev.rounds, ev.count, m.count))
        elseif ty == "spin_start" then
            w.spinning = true
            w.reelStopped = { false, false, false }
            if ev.reach then w.reachPending = true end
        elseif ty == "reel_stop" then
            if w.reelStopped then w.reelStopped[ev.reel] = true end
            BJ:PlaySfx("Arcade\\reel_stop" .. math.min(3, ev.reel) .. ".ogg")
            if ev.reach then
                w.dispText:SetText("|cffff8800REACH!|r")
                BJ:PlaySfx("Arcade\\anticipation3.ogg")
            end
        elseif ty == "spin_end" then
            w.spinning = false
            w.dispText:SetText("")
            for i = 1, 3 do w.reels[i].digit:SetText(tostring(ev.reels[i])) end
            if ev.hit then
                for i = 1, 3 do w.reels[i].digit:SetTextColor(1, 0.9, 0.3) end
            else
                for i = 1, 3 do w.reels[i].digit:SetTextColor(m.theme.title[1], m.theme.title[2], m.theme.title[3]) end
            end
        elseif ty == "jackpot_start" then
            self:ShowBanner(w, "|cffffd700JACKPOT!|r", ("%d rounds - %s"):format(ev.rounds, ev.kind == "kakuhen" and "|cffff66ffKAKUHEN|r" or "normal"), 0)
            BJ:PlaySfx("Arcade\\jackpot.ogg")
            w.attacker:SetBackdropColor(0.9, 0.6, 0.1, 1)
            w.attacker.label:SetText("OPEN")
            w.attacker.label:SetTextColor(1, 1, 0.8)
            if w.trixieFrame and UI.Lobby and UI.Lobby.TrixieReact then UI.Lobby:TrixieReact(w, "love", 6) end
            if UI.Lobby and UI.Lobby.PlayTrixieVoice then UI.Lobby:PlayTrixieVoice("jackpot", { cd = 8 }) end
        elseif ty == "round_end" then
            w.attacker:SetBackdropColor(0.5, 0.35, 0.1, 1)
            w.attacker.label:SetText("ROUND " .. ev.round .. " DONE")
        elseif ty == "round_start" then
            w.attacker:SetBackdropColor(0.9, 0.6, 0.1, 1)
            w.attacker.label:SetText("OPEN")
        elseif ty == "jackpot_end" then
            local s = statsFor(w.id)
            s.jackpots = (s.jackpots or 0) + 1
            if ev.paid > (s.best or 0) then s.best = ev.paid end
            s.spins = st.spins
            self:ShowBanner(w, "|cff00ff00+" .. fmtBig(ev.paid) .. " balls|r",
                ev.mode == "kakuhen" and "Kakuhen: the next one comes quick" or
                (ev.mode == "jitan" and "Jitan: the tulip stays open for " .. ev.spins .. " spins" or ""), 5)
            w.attacker:SetBackdropColor(0.3, 0.2, 0.05, 1)
            w.attacker.label:SetText("ATTACKER")
            w.attacker.label:SetTextColor(0.7, 0.6, 0.4)
            BJ:PlaySfx("Arcade\\vibrant_win.ogg")
        elseif ty == "mode" then
            w.modeText:SetText(MODE_TEXT[ev.mode] or ev.mode)
            if ev.mode == "kakuhen" then BJ:PlaySfx("fanfare.ogg") end
        elseif ty == "broke" then
            BJ:Print("|cffff8800Out of credits. The pit boss comps you if you hit zero.|r")
        end
    end
    for i = #w.events, 1, -1 do w.events[i] = nil end
end

function PKUI:OnUpdate(w, dt)
    local PK = Engine()
    local st = w.state
    local now = GetTime()

    PK:Step(st, dt, w.events, self:Wallet(w))
    if #w.events > 0 then
        self:HandleEvents(w, now)
        self:UpdateCounters(w)
    end

    -- balls
    for i, b in ipairs(w.ballTex) do
        local ball = st.balls[i]
        if ball then
            b:ClearAllPoints()
            b:SetPoint("CENTER", w.board, "TOPLEFT", ball.x, -ball.y)
            b:Show()
        else
            b:Hide()
        end
    end

    -- reels roll while a spin runs
    if w.spinning and st.spin then
        local sp = st.spin
        for i = 1, 3 do
            local stopped = w.reelStopped and w.reelStopped[i]
            if not stopped then
                w.reels[i].digit:SetText(tostring(1 + math.floor((now * (9 + i * 3)) % 9)))
            elseif sp.result then
                w.reels[i].digit:SetText(tostring(sp.result.reels[i]))
            end
        end
    end

    -- tulip petals open while the start pocket is widened
    local open = st.mode ~= "normal"
    for _, pt in ipairs(w.petals) do
        pt:ClearAllPoints()
        local sp = st.board.start
        local off = open and (sp.wOpen / 2 + 2) or (sp.w / 2 + 3)
        pt:SetPoint("BOTTOM", w.board, "TOPLEFT", sp.x + pt.dir * off, -(sp.y + 2))
        pt:SetVertexColor(open and 1 or 0.6, 1, open and 0.5 or 0.7, 1)
    end

    -- holds
    for i, d in ipairs(w.holdDots) do
        if i <= #st.holds then d:SetVertexColor(1, 0.85, 0.3, 1) else d:SetVertexColor(0.3, 0.3, 0.35, 1) end
    end

    -- popups and banner
    for _, p in ipairs(w.popups) do
        if p:IsShown() then
            local age = now - (p.born or now)
            if age > 0.9 then
                p:Hide()
            else
                p:ClearAllPoints()
                p:SetPoint("CENTER", w.board, "TOPLEFT", p.x, -(p.y - age * 30))
                p:SetAlpha(1 - age / 0.9)
            end
        end
    end
    if w.bannerUntil and now >= w.bannerUntil then
        w.bannerUntil = nil
        w.banner:SetText("")
        w.bannerSub:SetText("")
    end
end

-- ---------------------------------------------------------------------
-- Readouts

function PKUI:UpdateCounters(w)
    local st = w.state
    local credits = BJ.Arcade:GetCredits()
    w.creditsText:SetText(fmtBig(credits))
    w.ballsText:SetText(fmtBig(math.floor(credits / (w.rate or 1))))
    w.firedText:SetText(fmtBig(st.launched))
    w.paidText:SetText(fmtBig(st.paidBalls))
    w.spinsText:SetText(fmtBig(st.spins))
    w.jackpotsText:SetText(fmtBig(st.jackpots))
    w.bestText:SetText(fmtBig(st.bestJackpot))
    local s = statsFor(w.id)
    w.allJackpotsText:SetText(fmtBig(s.jackpots or 0))
    w.allBestText:SetText(fmtBig(s.best or 0))
    w.allBallsText:SetText(fmtBig(s.ballsIn or 0) .. " / " .. fmtBig(s.ballsOut or 0))
    w.modeText:SetText((MODE_TEXT[st.mode] or st.mode) ..
        ((st.mode ~= "normal" and st.modeSpins > 0) and ("  " .. st.modeSpins) or ""))
end

function PKUI:UpdateDisplay(w)
    self:UpdateCounters(w)
    local st = w.state
    w.fireBtn.text:SetText(st.firing and "STOP" or ("FIRE (" .. (w.rate or 1) .. " a ball)"))
    w.fireBtn.lit = st.firing
    w.fireBtn:paint()
    for _, b in ipairs(w.rateBtns) do
        if st.firing then b:Disable() else b:Enable() end
        b:paint()
    end
end

-- Credit changes from outside (gifts, grants, comps) refresh whatever's open.
function PKUI:RefreshAll()
    for _, w in pairs(self.frames) do
        if w:IsShown() then self:UpdateDisplay(w) end
    end
    if Parlor.frame and Parlor.frame:IsShown() then Parlor:UpdateDisplay() end
end

function PKUI:Show()
    Parlor:Show()
end

function PKUI:Hide()
    for _, w in pairs(self.frames) do w:Hide() end
    Parlor:Hide()
end
