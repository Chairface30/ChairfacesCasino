--[[
    Chairface's Casino - UI/PachinkoFrame.lua
    Gnomish Pachinko: the Peggle-style peg shooter's window. Draws the
    field BJ.Arcade.Pachinko simulates (pegs, ball, bucket, Fever bins,
    aim guide), reads the mouse for aiming, launches on click, and moves
    the fake credits: Spend on PLAY, Award on round_over.

    The engine uses y-down field pixels; every field texture is anchored
    CENTER to the field's TOPLEFT at (x, -y).
]]

local BJ = ChairfacesCasino
local UI = BJ.UI

UI.Pachinko = {}
local UIP = UI.Pachinko

local TEX = "Interface\\AddOns\\Chairfaces Casino\\Textures\\Pachinko\\"
local WHITE = "Interface\\Buttons\\WHITE8x8"

local PAD    = 16
local SIDE_W = 190
local TOP_H  = 44

local PEG_COLORS = {
    blue   = { base = { 0.30, 0.58, 1.00 }, lit = { 0.78, 0.92, 1.00 }, glow = { 0.55, 0.80, 1.00 } },
    orange = { base = { 1.00, 0.50, 0.08 }, lit = { 1.00, 0.90, 0.50 }, glow = { 1.00, 0.70, 0.25 } },
    green  = { base = { 0.22, 0.88, 0.32 }, lit = { 0.78, 1.00, 0.78 }, glow = { 0.50, 1.00, 0.55 } },
}
local BIN_COLORS = { [1] = { 0.25, 0.45, 0.85 }, [2] = { 0.95, 0.55, 0.15 }, [5] = { 1.00, 0.85, 0.20 } }

local function fmtBig(n)
    if BreakUpLargeNumbers then return BreakUpLargeNumbers(n) end
    return tostring(n)
end

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

local function styleButton(btn, enabled, r, g, b)
    if enabled then
        btn:SetBackdropColor(r, g, b, 0.9)
        btn:SetBackdropBorderColor(1, 1, 1, 0.9)
        btn:Enable()
    else
        btn:SetBackdropColor(r * 0.35, g * 0.35, b * 0.35, 0.8)
        btn:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
        btn:Disable()
    end
end

function UIP:Initialize()
    if self.frame then return end
    self:CreateFrame()
end

function UIP:CreateFrame()
    local PK = BJ.Arcade.Pachinko
    local FW, FH = PK.FIELD_W, PK.FIELD_H
    local FRAME_W = PAD + FW + PAD + SIDE_W + PAD
    local FRAME_H = TOP_H + FH + PAD

    local frame = CreateFrame("Frame", "ChairfacesCasinoPachinko", UIParent, "BackdropTemplate")
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
        bgFile = WHITE, edgeFile = WHITE, edgeSize = 2,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    frame:SetBackdropColor(0.10, 0.04, 0.18, 0.97)   -- arcade purple
    frame:SetBackdropBorderColor(0.75, 0.55, 0.95, 1)
    frame:Hide()
    self.frame = frame

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("|cffffd700Gnomish Pachinko|r")
    title:SetFont("Fonts\\FRIZQT__.TTF", 18, "OUTLINE")

    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function()
        UIP:Hide()
        if UI.Lobby then UI.Lobby:Show() end
    end)

    if UI.Lobby and UI.Lobby.AttachHowToPlayButton then
        UI.Lobby:AttachHowToPlayButton(frame, "pachinko", 8, -8)
    end
    if UI.Lobby and UI.Lobby.AttachTrixie then
        UI.Lobby:AttachTrixie(frame)
    end

    -- ===== The field =====
    local field = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    field:SetSize(FW, FH)
    field:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -TOP_H)
    field:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 2 })
    field:SetBackdropColor(0.03, 0.04, 0.14, 1)   -- night sky
    field:SetBackdropBorderColor(0.45, 0.35, 0.70, 1)
    field:EnableMouse(true)
    field:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then UIP:OnFieldClick() end
    end)
    self.field = field

    -- a few stars so the sky isn't flat
    do
        local seedRng = math.random
        for _ = 1, 48 do
            local s = field:CreateTexture(nil, "BACKGROUND", nil, 1)
            local size = 1 + seedRng() * 2
            s:SetSize(size, size)
            s:SetTexture(WHITE)
            s:SetVertexColor(0.8, 0.85, 1, 0.15 + seedRng() * 0.35)
            s:SetPoint("CENTER", field, "TOPLEFT", 6 + seedRng() * (FW - 12), -(6 + seedRng() * (FH - 12)))
        end
    end

    -- launcher: a hub at the muzzle pivot and a barrel that turns with the aim
    local barrel = field:CreateTexture(nil, "ARTWORK", nil, 2)
    barrel:SetSize(12, 30)
    barrel:SetTexture(WHITE)
    barrel:SetVertexColor(0.70, 0.72, 0.80, 1)
    self.barrel = barrel
    local hub = field:CreateTexture(nil, "ARTWORK", nil, 3)
    hub:SetSize(26, 26)
    hub:SetTexture(TEX .. "peg")
    hub:SetVertexColor(0.55, 0.58, 0.68, 1)
    hub:SetPoint("CENTER", field, "TOPLEFT", FW / 2, -PK.LAUNCHER_Y)
    self.hub = hub

    -- aim guide dots
    self.guideDots = {}
    for i = 1, 20 do
        local d = field:CreateTexture(nil, "ARTWORK", nil, 1)
        d:SetSize(6, 6)
        d:SetTexture(TEX .. "dot")
        d:SetVertexColor(1, 1, 1, 0.8)
        d:Hide()
        self.guideDots[i] = d
    end

    -- pegs are pooled: created on demand, hidden between rounds
    self.pegTex = {}

    -- balls (one plus multiball twins)
    self.ballTex = {}
    for i = 1, 6 do
        local b = field:CreateTexture(nil, "OVERLAY", nil, 2)
        b:SetSize(PK.BALL_R * 2 + 2, PK.BALL_R * 2 + 2)
        b:SetTexture(TEX .. "ball")
        b:SetVertexColor(0.92, 0.94, 1.0, 1)
        b:Hide()
        self.ballTex[i] = b
    end

    -- the free-ball bucket
    local bucket = field:CreateTexture(nil, "OVERLAY", nil, 1)
    bucket:SetSize(PK.BUCKET_W + 8, (PK.BUCKET_W + 8) / 4)
    bucket:SetTexture(TEX .. "bucket")
    self.bucket = bucket

    -- Fever bins along the bottom
    self.bins = {}
    local binW = FW / #PK.FEVER_BINS
    for i, mult in ipairs(PK.FEVER_BINS) do
        local bin = CreateFrame("Frame", nil, field, "BackdropTemplate")
        bin:SetSize(binW - 2, 28)
        bin:SetPoint("BOTTOMLEFT", field, "BOTTOMLEFT", (i - 1) * binW + 1, 2)
        bin:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
        local c = BIN_COLORS[mult] or BIN_COLORS[1]
        bin:SetBackdropColor(c[1], c[2], c[3], 0.35)
        bin:SetBackdropBorderColor(c[1], c[2], c[3], 0.9)
        bin.label = bin:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        bin.label:SetPoint("CENTER")
        bin.label:SetText("x" .. mult)
        bin:Hide()
        self.bins[i] = bin
    end

    -- centre banner (FEVER!, FREE BALL!, the result)
    local banner = field:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    banner:SetPoint("CENTER", field, "CENTER", 0, 40)
    banner:SetFont("Fonts\\FRIZQT__.TTF", 26, "OUTLINE")
    banner:SetText("")
    self.banner = banner
    local sub = field:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    sub:SetPoint("TOP", banner, "BOTTOM", 0, -6)
    sub:SetText("")
    self.bannerSub = sub

    -- floating score popups
    self.popups = {}
    for i = 1, 8 do
        local p = field:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        p:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
        p:Hide()
        self.popups[i] = p
    end

    -- ===== Side panel =====
    local side = CreateFrame("Frame", nil, frame)
    side:SetSize(SIDE_W, FH)
    side:SetPoint("TOPLEFT", field, "TOPRIGHT", PAD, 0)
    self.side = side

    local function label(text, y, template)
        local fs = side:CreateFontString(nil, "OVERLAY", template or "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", side, "TOPLEFT", 0, y)
        fs:SetText(text)
        return fs
    end
    local function value(y, template)
        local fs = side:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
        fs:SetPoint("TOPRIGHT", side, "TOPRIGHT", 0, y)
        fs:SetJustifyH("RIGHT")
        return fs
    end

    label("|cffaaaaaaCREDITS|r", 0)
    self.creditsText = value(-14, "GameFontNormalLarge")
    self.creditsText:SetFont("Fonts\\FRIZQT__.TTF", 20, "OUTLINE")
    self.creditsText:SetTextColor(1, 0.85, 0.2)

    label("|cffaaaaaaBET|r", -48)
    local function smallBtn(text, w, x, y)
        local b = CreateFrame("Button", nil, side, "BackdropTemplate")
        b:SetSize(w, 24)
        b:SetPoint("TOPLEFT", side, "TOPLEFT", x, y)
        b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        b.text:SetPoint("CENTER")
        b.text:SetText(text)
        return b
    end
    self.betDown = smallBtn("-", 28, 0, -62)
    self.betText = side:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    self.betText:SetPoint("LEFT", self.betDown, "RIGHT", 0, 0)
    self.betText:SetWidth(60)
    self.betText:SetJustifyH("CENTER")
    self.betUp = smallBtn("+", 28, 88, -62)
    self.betMax = smallBtn("MAX", 60, 130, -62)
    self.betDown:SetScript("OnClick", function() UIP:StepBet(-1) end)
    self.betUp:SetScript("OnClick", function() UIP:StepBet(1) end)
    self.betMax:SetScript("OnClick", function()
        if UIP.state and UIP.state.phase ~= BJ.Arcade.Pachinko.PHASE.OVER then return end
        UIP.bet = BJ.Arcade:MaxAffordableStep(1)
        BJ:PlaySfx("Arcade\\coin_insert.ogg")
        UIP:UpdateDisplay()
    end)

    local playBtn = CreateFrame("Button", nil, side, "BackdropTemplate")
    playBtn:SetSize(SIDE_W, 36)
    playBtn:SetPoint("TOPLEFT", side, "TOPLEFT", 0, -98)
    playBtn:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 2 })
    playBtn.text = playBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    playBtn.text:SetPoint("CENTER")
    playBtn:SetScript("OnClick", function() UIP:OnPlay() end)
    self.playBtn = playBtn

    local div = side:CreateTexture(nil, "ARTWORK")
    div:SetSize(SIDE_W, 1)
    div:SetPoint("TOPLEFT", side, "TOPLEFT", 0, -146)
    div:SetTexture(WHITE)
    div:SetVertexColor(0.5, 0.4, 0.7, 0.6)

    label("Balls", -156, "GameFontNormal")
    self.ballsText = value(-156, "GameFontHighlightLarge")
    label("Orange pegs left", -180, "GameFontNormal")
    self.orangeText = value(-180, "GameFontHighlightLarge")
    label("Score", -204, "GameFontNormal")
    self.scoreText = value(-204, "GameFontHighlight")
    label("Best score", -224)
    self.bestScoreText = value(-224, "GameFontHighlightSmall")
    label("Best win", -240)
    self.bestWinText = value(-240, "GameFontHighlightSmall")

    local div2 = side:CreateTexture(nil, "ARTWORK")
    div2:SetSize(SIDE_W, 1)
    div2:SetPoint("TOPLEFT", side, "TOPLEFT", 0, -262)
    div2:SetTexture(WHITE)
    div2:SetVertexColor(0.5, 0.4, 0.7, 0.6)

    label("|cffffd700PAYS|r  (times your bet)", -270, "GameFontNormal")
    local y = -290
    for _, row in ipairs(PK:PayTableRows()) do
        local l = label(row.label, y)
        l:SetTextColor(0.85, 0.85, 0.85)
        local v = value(y, "GameFontNormalSmall")
        v:SetText("|cffffd700" .. row.pays .. "x|r")
        y = y - 16
    end
    y = y - 8
    local tip = side:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tip:SetPoint("TOPLEFT", side, "TOPLEFT", 0, y)
    tip:SetWidth(SIDE_W)
    tip:SetJustifyH("LEFT")
    tip:SetJustifyV("TOP")
    tip:SetTextColor(0.7, 0.7, 0.8)
    tip:SetText("Point with the mouse and click the field to shoot. Light every orange peg. " ..
        "A ball into the moving bucket is a free ball. Green pegs split the ball in two. " ..
        "Clear the last orange and the ball drops into a bin that multiplies the prize.")

    self.layoutText = side:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.layoutText:SetPoint("BOTTOMLEFT", side, "BOTTOMLEFT", 0, 0)
    self.layoutText:SetTextColor(0.6, 0.55, 0.75)
    self.layoutText:SetText("")

    frame:SetScript("OnUpdate", function(_, dt) UIP:OnUpdate(dt) end)
    frame:SetScript("OnShow", function() UIP.lastHitSound = 0 end)

    if BJ.EscapeHandler then
        BJ.EscapeHandler:RegisterFrame("ChairfacesCasinoPachinko")
    end

    self.bet = self.bet or 5
    self.events = {}
    self:ShowBanner("Set your bet and press PLAY", "", 0)
    self:UpdateDisplay()
end

-- ---------------------------------------------------------------------
-- Bets and the round

function UIP:RoundRunning()
    local st = self.state
    return st ~= nil and st.phase ~= BJ.Arcade.Pachinko.PHASE.OVER
end

function UIP:StepBet(dir)
    if self:RoundRunning() then return end
    local nxt = BJ.Arcade:NextBetStep(self.bet, dir)
    if nxt ~= self.bet then
        self.bet = nxt
        BJ:PlaySfx("Arcade\\coin_insert.ogg")
        self:UpdateDisplay()
    end
end

function UIP:OnPlay()
    if self:RoundRunning() then return end
    local Arcade = BJ.Arcade
    if Arcade:GetCredits() < 1 then
        local ok, refills = Arcade:CompMe()
        if ok then
            BJ:Print("|cff00ff00The pit boss comps you " .. Arcade.COMP_AMOUNT ..
                " credits.|r (Refill #" .. refills .. " - she's keeping count.)")
            self:UpdateDisplay()
        end
        return
    end
    if not Arcade:Spend(self.bet) then
        BJ:Print("|cffff8800Not enough credits for a " .. fmtBig(self.bet) .. " credit round.|r")
        return
    end
    local seed = ((time and time() or 0) * 7919 + math.random(1, 1000000)) % 2147483647
    self.state = BJ.Arcade.Pachinko:NewRound(self.bet, seed)
    self.guideAim = nil
    self:LayoutPegs()
    for _, bin in ipairs(self.bins) do bin:Hide() end
    self.bucket:Show()
    self:ShowBanner("Click to shoot", "", 1.5)
    BJ:PlaySfx("Arcade\\slot_lever.ogg")
    if self.frame.trixieFrame and UI.Lobby and UI.Lobby.TrixieReact then
        UI.Lobby:TrixieReact(self.frame, "deal", 3)
    end
    self:UpdateDisplay()
end

function UIP:OnFieldClick()
    local st = self.state
    if not st then return end
    local PK = BJ.Arcade.Pachinko
    if not PK:CanLaunch(st) then return end
    self:AimAtCursor()
    if PK:Launch(st) then
        self:HideGuide()
        BJ:PlaySfx("Kenney\\card-place-" .. math.random(4) .. ".ogg")
        self:UpdateDisplay()
    end
end

-- ---------------------------------------------------------------------
-- Field drawing

function UIP:LayoutPegs()
    local PK = BJ.Arcade.Pachinko
    local st = self.state
    local field = self.field
    for i, p in ipairs(st.pegs) do
        local t = self.pegTex[i]
        if not t then
            t = {}
            t.ring = field:CreateTexture(nil, "ARTWORK", nil, 0)
            t.ring:SetSize(PK.PEG_R * 2 + 18, PK.PEG_R * 2 + 18)
            t.ring:SetTexture(TEX .. "ring")
            t.disc = field:CreateTexture(nil, "ARTWORK", nil, 1)
            t.disc:SetSize(PK.PEG_R * 2 + 2, PK.PEG_R * 2 + 2)
            t.disc:SetTexture(TEX .. "peg")
            self.pegTex[i] = t
        end
        t.disc:ClearAllPoints()
        t.disc:SetPoint("CENTER", field, "TOPLEFT", p.x, -p.y)
        t.ring:ClearAllPoints()
        t.ring:SetPoint("CENTER", field, "TOPLEFT", p.x, -p.y)
        local c = PEG_COLORS[p.kind].base
        t.disc:SetVertexColor(c[1], c[2], c[3], 1)
        t.disc:SetAlpha(1)
        t.disc:Show()
        t.ring:Hide()
        t.shown = "base"
    end
    for i = #st.pegs + 1, #self.pegTex do
        self.pegTex[i].disc:Hide()
        self.pegTex[i].ring:Hide()
        self.pegTex[i].shown = nil
    end
end

function UIP:HidePegs()
    for _, t in ipairs(self.pegTex) do
        t.disc:Hide()
        t.ring:Hide()
        t.shown = nil
    end
end

function UIP:HideGuide()
    for _, d in ipairs(self.guideDots) do d:Hide() end
    self.guideAim = nil
end

function UIP:DrawGuide()
    local PK = BJ.Arcade.Pachinko
    local st = self.state
    local pts = PK:Guide(st)
    for i, d in ipairs(self.guideDots) do
        local p = pts[i]
        if p then
            d:ClearAllPoints()
            d:SetPoint("CENTER", self.field, "TOPLEFT", p.x, -p.y)
            d:SetAlpha(0.85 - 0.6 * (i / #self.guideDots))
            d:Show()
        else
            d:Hide()
        end
    end
end

-- Field coordinates of the cursor (y down), or nil when the field has no
-- geometry yet.
function UIP:CursorField()
    if not GetCursorPosition then return nil end
    local field = self.field
    local scale = field:GetEffectiveScale() or 1
    local cx, cy = GetCursorPosition()
    if not cx then return nil end
    local left, top = field:GetLeft(), field:GetTop()
    if not left or not top then return nil end
    return cx / scale - left, top - cy / scale
end

function UIP:AimAtCursor()
    local st = self.state
    if not st then return end
    local PK = BJ.Arcade.Pachinko
    local fx, fy = self:CursorField()
    if not fx then return end
    -- keep aiming a little past the edges so the cursor can rest on the panel
    if fx < -120 or fx > PK.FIELD_W + 120 or fy < -60 or fy > PK.FIELD_H + 120 then return end
    PK:Aim(st, fx, fy)
end

function UIP:ShowBanner(text, subText, secs)
    self.banner:SetText(text or "")
    self.bannerSub:SetText(subText or "")
    self.bannerUntil = (secs and secs > 0) and (GetTime() + secs) or nil
end

function UIP:Popup(x, y, text, r, g, b)
    local p
    for _, cand in ipairs(self.popups) do
        if not cand:IsShown() then p = cand break end
    end
    if not p then p = self.popups[1] end
    p:ClearAllPoints()
    p:SetPoint("CENTER", self.field, "TOPLEFT", x, -y)
    p:SetText(text)
    p:SetTextColor(r or 1, g or 1, b or 1)
    p:SetAlpha(1)
    p.born = GetTime()
    p.x, p.y = x, y
    p:Show()
end

function UIP:UpdatePopups(now)
    for _, p in ipairs(self.popups) do
        if p:IsShown() then
            local age = now - (p.born or now)
            if age > 0.9 then
                p:Hide()
            else
                p:ClearAllPoints()
                p:SetPoint("CENTER", self.field, "TOPLEFT", p.x, -(p.y - age * 36))
                p:SetAlpha(1 - age / 0.9)
            end
        end
    end
end

function UIP:HandleEvents(now)
    local PK = BJ.Arcade.Pachinko
    local st = self.state
    for _, ev in ipairs(self.events) do
        local t = ev.type
        if t == "bounce" then
            if ev.speed > 60 and now - (self.lastHitSound or 0) > 0.06 then
                self.lastHitSound = now
                BJ:PlaySfx("Kenney\\chip-lay-" .. math.random(3) .. ".ogg")
            end
        elseif t == "peg" then
            if ev.peg.kind == "orange" then
                BJ:PlaySfx("Arcade\\coin_insert.ogg")
                self:Popup(ev.x, ev.y - 14, "+" .. ev.points, 1, 0.8, 0.3)
            elseif ev.peg.kind == "green" then
                self:Popup(ev.x, ev.y - 14, "+" .. ev.points, 0.6, 1, 0.6)
            end
        elseif t == "power" then
            self:ShowBanner("|cff88ff88MULTIBALL!|r", "", 1.2)
            BJ:PlaySfx("Arcade\\payout_small.ogg")
        elseif t == "fever" then
            self:ShowBanner("|cffffd700FEVER!|r", "Every orange peg is lit", 3)
            BJ:PlaySfx("fanfare.ogg")
            self.bucket:Hide()
            for _, bin in ipairs(self.bins) do bin:Show() end
            if self.frame.trixieFrame and UI.Lobby and UI.Lobby.TrixieReact then
                UI.Lobby:TrixieReact(self.frame, "love", 6)
            end
        elseif t == "bucket" then
            self:ShowBanner("|cff88ccffFREE BALL!|r", "", 1.5)
            BJ:PlaySfx("Arcade\\payout_small.ogg")
            self:Popup(ev.x, PK.BucketTop() - 16, "FREE BALL", 0.6, 0.85, 1)
        elseif t == "bin" then
            self:Popup(ev.x, PK.FIELD_H - 44, "x" .. ev.mult, 1, 0.9, 0.4)
        elseif t == "ready" then
            if st.ballsLeft > 0 then self:ShowBanner("", "", 0) end
        elseif t == "round_over" then
            self:OnRoundOver(ev.result)
        end
    end
    for i = #self.events, 1, -1 do self.events[i] = nil end
end

function UIP:OnRoundOver(result)
    local Arcade = BJ.Arcade
    local db = Arcade:GetDB()
    if result.win > 0 then Arcade:Award(result.win) end
    if result.score > (db.bestPachinkoScore or 0) then db.bestPachinkoScore = result.score end
    if result.win > (db.bestPachinkoWin or 0) then db.bestPachinkoWin = result.win end

    if result.allClear then
        self:ShowBanner("|cffffd700BOARD CLEARED!|r",
            string.format("x%d bin, %d ball%s spare: |cff00ff00WIN %s|r", result.binMult or 1,
                result.ballsLeft, result.ballsLeft == 1 and "" or "s", fmtBig(result.win)), 0)
        BJ:PlaySfx("Arcade\\jackpot.ogg")
        if self.frame.trixieFrame and UI.Lobby and UI.Lobby.TrixieReact then
            UI.Lobby:TrixieReact(self.frame, "love", 6)
        end
        if UI.Lobby and UI.Lobby.PlayTrixieVoice then UI.Lobby:PlayTrixieVoice("bigwin", { cd = 8 }) end
    elseif result.win > 0 then
        self:ShowBanner("|cff00ff00PAID|r",
            string.format("%d of %d orange pegs: |cff00ff00WIN %s|r", result.oranges,
                BJ.Arcade.Pachinko.ORANGE, fmtBig(result.win)), 0)
        BJ:PlaySfx("Arcade\\vibrant_win.ogg")
        if self.frame.trixieFrame and UI.Lobby and UI.Lobby.TrixieReact then
            UI.Lobby:TrixieReact(self.frame, "win", 4)
        end
    else
        self:ShowBanner("|cffff6060OUT OF BALLS|r",
            string.format("%d of %d orange pegs - no pay", result.oranges, BJ.Arcade.Pachinko.ORANGE), 0)
        if self.frame.trixieFrame and UI.Lobby and UI.Lobby.TrixieReact then
            UI.Lobby:TrixieReact(self.frame, "lose", 4)
        end
    end
    self:HideGuide()
    self:UpdateDisplay()
end

function UIP:OnUpdate(dt)
    local now = GetTime()
    local st = self.state
    self:UpdatePopups(now)
    if self.bannerUntil and now >= self.bannerUntil then
        self.bannerUntil = nil
        self.banner:SetText("")
        self.bannerSub:SetText("")
    end
    if not st then return end

    local PK = BJ.Arcade.Pachinko
    local aiming = st.phase == PK.PHASE.AIM
    if aiming then
        self:AimAtCursor()
        if self.guideAim ~= st.aim or self.guideDirty then
            self.guideAim = st.aim
            self.guideDirty = nil
            self:DrawGuide()
        end
    end

    PK:Step(st, dt, self.events)
    if #self.events > 0 then
        self.guideDirty = true
        self:HandleEvents(now)
        self:UpdateCounters()
    end
    self:Render(now)
end

function UIP:Render(now)
    local PK = BJ.Arcade.Pachinko
    local st = self.state
    local field = self.field

    -- launcher barrel follows the aim; it turns about its own centre, so
    -- that centre sits half a barrel down the aim line from the pivot
    local a = st.aim or 0
    local half = 15
    self.barrel:ClearAllPoints()
    self.barrel:SetPoint("CENTER", field, "TOPLEFT",
        PK.FIELD_W / 2 + math.sin(a) * half, -(PK.LAUNCHER_Y + math.cos(a) * half))
    if self.barrel.SetRotation then self.barrel:SetRotation(a) end

    -- pegs: only touch textures whose look changed
    local pulse = 0.55 + 0.35 * math.sin(now * 9)
    for i, p in ipairs(st.pegs) do
        local t = self.pegTex[i]
        if t then
            if p.gone then
                local age = st.time - (p.goneAt or st.time)
                local alpha = 1 - age / 0.35
                if alpha <= 0 then
                    if t.shown ~= "gone" then
                        t.disc:Hide()
                        t.ring:Hide()
                        t.shown = "gone"
                    end
                else
                    t.disc:SetAlpha(alpha)
                    t.ring:SetAlpha(alpha * 0.8)
                    t.shown = "fading"
                end
            elseif p.lit then
                local c = PEG_COLORS[p.kind]
                if t.shown ~= "lit" then
                    t.disc:SetVertexColor(c.lit[1], c.lit[2], c.lit[3], 1)
                    t.ring:SetVertexColor(c.glow[1], c.glow[2], c.glow[3], 1)
                    t.ring:Show()
                    t.shown = "lit"
                end
                t.ring:SetAlpha(pulse)
            end
        end
    end

    -- balls
    for i, b in ipairs(self.ballTex) do
        local ball = st.balls[i]
        if ball then
            b:ClearAllPoints()
            b:SetPoint("CENTER", field, "TOPLEFT", ball.x, -ball.y)
            b:Show()
        else
            b:Hide()
        end
    end

    -- bucket
    if st.phase ~= PK.PHASE.FEVER and st.phase ~= PK.PHASE.OVER then
        self.bucket:ClearAllPoints()
        self.bucket:SetPoint("TOP", field, "TOPLEFT", st.bucket.x, -(PK.BucketTop() - 4))
    end
end

-- ---------------------------------------------------------------------
-- Readouts

function UIP:UpdateCounters()
    local PK = BJ.Arcade.Pachinko
    local st = self.state
    if st then
        self.ballsText:SetText(tostring(st.ballsLeft + #st.balls))
        self.orangeText:SetText(st.orangeLeft .. " / " .. PK.ORANGE)
        self.scoreText:SetText(fmtBig(st.score))
        self.layoutText:SetText("Layout: " .. (st.layout or "") .. "   seed " .. tostring(st.seed))
    else
        self.ballsText:SetText("-")
        self.orangeText:SetText("-")
        self.scoreText:SetText("0")
        self.layoutText:SetText("")
    end
    self.creditsText:SetText(fmtBig(BJ.Arcade:GetCredits()))
end

function UIP:UpdateDisplay()
    local Arcade = BJ.Arcade
    local db = Arcade:GetDB()
    self:UpdateCounters()
    self.bestScoreText:SetText(fmtBig(db.bestPachinkoScore or 0))
    self.bestWinText:SetText(fmtBig(db.bestPachinkoWin or 0))
    self.betText:SetText("|cffffd700" .. fmtBet(self.bet) .. "|r")

    local running = self:RoundRunning()
    local credits = Arcade:GetCredits()
    styleButton(self.betDown, not running, 0.3, 0.3, 0.4)
    styleButton(self.betUp, not running, 0.3, 0.3, 0.4)
    styleButton(self.betMax, not running, 0.5, 0.35, 0.1)
    if running then
        self.playBtn.text:SetText("|cffaaaaaaIN PLAY|r")
        styleButton(self.playBtn, false, 0.6, 0.3, 0.8)
    else
        local canPlay = credits >= self.bet or credits < 1
        self.playBtn.text:SetText(self.state and ("PLAY AGAIN (" .. fmtBet(self.bet) .. ")")
            or ("PLAY (" .. fmtBet(self.bet) .. ")"))
        styleButton(self.playBtn, canPlay, 0.6, 0.3, 0.8)
    end
end

function UIP:Show()
    self:Initialize()
    self:UpdateDisplay()
    self.frame:Show()
end

function UIP:Hide()
    if self.frame then self.frame:Hide() end
end
