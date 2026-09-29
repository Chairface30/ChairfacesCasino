--[[
    Chairface's Casino - UI/ReelsFrame.lua
    The Slot Floor: a picker window behind the lobby's Slots button, and one
    themed cabinet window per video reel machine in Games/ArcadeReels.lua.

    A machine window is built from its engine definition (reel count, rows,
    symbols, theme colours), so the five machines share this code but each
    looks and plays like its floor original:
      * stepper-style scrolling reels that land with a bounce (Kodo,
        Pharaoh, Darkmoon, Jade), or Sweet Bonanza's drop-in columns with
        tumbling wins (Tel'Abim Bonanza)
      * free games played out spin by spin, the Darkmoon prize wheel, and
        the Jade Fortunes Fu Bat pick-em
    The engine has already charged and paid the whole outcome when a spin
    starts; `pending` hides the not-yet-revealed part of the balance until
    the animation gets there.
]]

local BJ = ChairfacesCasino
local UI = BJ.UI

UI.Reels = {}
local RUI = UI.Reels
UI.SlotFloor = {}
local Floor = UI.SlotFloor

local WHITE = "Interface\\Buttons\\WHITE8x8"
local FONT = "Fonts\\FRIZQT__.TTF"
local TEX = "Interface\\AddOns\\Chairfaces Casino\\Textures\\"

local function Engine() return BJ.Arcade.Reels end

local function fmtBig(n)
    n = math.floor(n or 0)
    if BreakUpLargeNumbers then return BreakUpLargeNumbers(n) end
    return tostring(n)
end

local function fmtShort(n)
    if n >= 1000000 then
        local v = n / 1000000
        return (v == math.floor(v)) and (v .. "m") or string.format("%.1fm", v)
    elseif n >= 10000 then
        local v = n / 1000
        return (v == math.floor(v)) and (v .. "k") or string.format("%.1fk", v)
    end
    return tostring(n)
end

-- Some clients lack a given icon; a symbol whose icon isn't in this
-- client's file list is drawn with its text glyph instead. The probe is
-- only trusted if it recognises an icon every client has.
local iconOK = {}
local probeWorks
local function hasIcon(path)
    if not path then return false end
    if probeWorks == nil then
        probeWorks = (GetFileIDFromPath ~= nil)
            and (GetFileIDFromPath("Interface\\Icons\\INV_Misc_Coin_02") ~= nil)
    end
    if not probeWorks then return true end
    if iconOK[path] == nil then iconOK[path] = (GetFileIDFromPath(path) ~= nil) end
    return iconOK[path]
end

local function plate(parent, bg, border, edge)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = edge or 1 })
    f:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
    f:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
    return f
end

local function text(parent, size, flags, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    fs:SetFont(FONT, size, flags or "OUTLINE")
    return fs
end

local function shade(c, k) return { c[1] * k, c[2] * k, c[3] * k } end

-- A flat cabinet button: plate + label, lit in the machine's colours.
local function makeButton(parent, w, h, label, theme, size)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(w, h)
    b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 2 })
    b.label = text(b, size or 12, "OUTLINE")
    b.label:SetPoint("CENTER")
    b.label:SetText(label)
    b.theme = theme
    b.paint = function(self)
        local t = self.theme
        if not self:IsEnabled() then
            self:SetBackdropColor(0.12, 0.12, 0.12, 1)
            self:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
            self.label:SetTextColor(0.5, 0.5, 0.5)
        elseif self.hot then
            self:SetBackdropColor(t.border[1], t.border[2], t.border[3], 1)
            self:SetBackdropBorderColor(1, 1, 1, 1)
            self.label:SetTextColor(0, 0, 0)
        else
            local c = self.fill or shade(t.bg2, 0.9)
            self:SetBackdropColor(c[1], c[2], c[3], 1)
            self:SetBackdropBorderColor(t.border[1], t.border[2], t.border[3], 1)
            self.label:SetTextColor(1, 1, 1)
        end
    end
    b:SetScript("OnEnter", function(self) self.hot = true; self:paint() end)
    b:SetScript("OnLeave", function(self) self.hot = false; self:paint(); GameTooltip:Hide() end)
    b:HookScript("OnEnable", function(self) self:paint() end)
    b:HookScript("OnDisable", function(self) self:paint() end)
    b:paint()
    return b
end

--[[ =================== the machine window =================== ]]

RUI.frames = {}
RUI.frame = nil      -- the machine window currently open (lobby sound gating)

local CAPTIONS = {
    kodo = { sun = "WILD", coin = "BONUS" },
    pharaoh = { pharaoh = "WILD x2", sphinx = "SCATTER" },
    darkmoon = { dd = "WILD x2" },
    jade = { gong = "BONUS" },
    bonanza = { idol = "SCATTER" },
}

-- Feature summary shown on each machine's marquee plate.
local MARQUEE = {
    kodo = "3 / 4 / 5 COINS  =  8 / 15 / 20 FREE GAMES  -  SUNSET WILDS x2 / x3 THAT MULTIPLY",
    pharaoh = "3+ SPHINX  =  15 FREE SPINS  -  ALL FREE SPIN WINS TRIPLED  -  RETRIGGERS",
    bonanza = "8+ ANYWHERE PAYS  -  WINS TUMBLE  -  4+ IDOLS = 10 FREE SPINS WITH BOMBS UP TO x100",
}

-- Rules text for the PAYS panel.
local RULES = {
    kodo = {
        "1024 ways: 3+ of a kind on adjacent reels from the left, any row.",
        "Sunset WILD lands on reels 2-4 and substitutes for all but the coin.",
        "Coins pay anywhere: 3 = 2x, 4 = 10x, 5 = 20x total bet.",
        "3 / 4 / 5 coins award 8 / 15 / 20 free games.",
        "Free games: every WILD is x2 or x3, and wilds on one way multiply (up to x27).",
        "In free games, 2+ coins add 5 / 8 / 15 / 20 more.",
    },
    pharaoh = {
        "20 fixed lines, left to right.",
        "The Pharaoh is WILD and DOUBLES any win she substitutes in.",
        "Sphinx scatters pay anywhere: 2 = 2x, 3 = 5x, 4 = 20x, 5 = 100x total bet.",
        "3+ sphinxes award 15 free spins; every free spin win pays x3.",
        "Free spins retrigger (up to 180).",
    },
    darkmoon = {
        "One payline, 1 to 3 coins. Pays are per coin played.",
        "Double Diamond is WILD: one in a win pays x2, two pay x4.",
        "Three Double Diamonds: 800 / 1600 / 2500 for 1 / 2 / 3 coins.",
        "Any cherry pays; any mix of BARs pays 5.",
        "SPIN on reel 3's payline turns the Darkmoon Wheel (25 - 1000 per coin),",
        "but ONLY when 3 coins are played.",
    },
    jade = {
        "243 ways: 3+ of a kind on adjacent reels from the left.",
        "Buy gold levels (8 / 18 / 38 / 68 / 88 coins) to unlock the jackpots:",
        "1 gold = MINI, 2 = +MINOR, 3 = +MAJOR, 4+ = GRAND. More gold, more Fu Bats.",
        "The Fu Bat can fly after any spin: pick coins until three match.",
        "FU is WILD on reels 2-5. 3+ gongs = 10 free games (retriggers).",
        "Line pays scale with the gold level (table shows your current bet).",
    },
    bonanza = {
        "Pay anywhere: 8+ of one symbol anywhere on the screen pays.",
        "Winning symbols burst, the rest tumble down, new ones drop in - repeat.",
        "4 / 5 / 6 idols pay 3x / 5x / 100x and award 10 free spins.",
        "Free spins: multiplier bombs (x2 - x100) land; when a tumble",
        "sequence ends, the bombs on screen add up and multiply its win.",
        "3+ idols in free spins = +5 spins. Max win 21,100x bet.",
    },
}

function RUI:Get(id)
    return self.frames[id]
end

-- Cell geometry for a machine.
local function geometry(m)
    if m.id == "darkmoon" then return 150, 96 end
    local cw = math.min(math.floor(600 / m.reels), 116)
    local ch = math.min(math.floor(372 / m.rows), 104)
    return cw, ch
end

local function newCell(parent, m, cw, ch)
    local c = CreateFrame("Frame", nil, parent)
    c:SetSize(cw - 8, ch)
    c.hl = c:CreateTexture(nil, "BACKGROUND")
    c.hl:SetPoint("TOPLEFT", 2, -2)
    c.hl:SetPoint("BOTTOMRIGHT", -2, 2)
    c.hl:SetColorTexture(1, 1, 1, 0)
    local isz = math.min(cw, ch) - 18
    c.iconSize = isz
    c.icon = c:CreateTexture(nil, "ARTWORK")
    c.icon:SetSize(isz, isz)
    c.icon:SetPoint("CENTER")
    c.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    c.glyph = c:CreateFontString(nil, "ARTWORK")
    c.glyph:SetPoint("CENTER")
    c.glyph:SetFont(FONT, 20, "THICKOUTLINE")
    c.cap = text(c, 10, "OUTLINE")
    c.cap:SetPoint("BOTTOM", c.icon, "BOTTOM", 0, 2)
    c.badge = text(c, 14, "THICKOUTLINE")
    c.badge:SetPoint("TOPRIGHT", c.icon, "TOPRIGHT", 4, 4)
    c.badge:SetTextColor(1, 0.9, 0.2)
    return c
end

function RUI:SetCell(f, cell, symId)
    local m = f.m
    cell.sym = symId
    cell.badge:Hide()
    local s = m.symbolById[symId]
    if not s or s.blank then
        cell.icon:Hide(); cell.cap:Hide(); cell.glyph:SetText("")
        return
    end
    local light = m.theme.lightReels
    if s.icon and hasIcon(s.icon) then
        cell.icon:SetTexture(s.icon)
        cell.icon:Show()
        cell.glyph:SetText("")
    else
        cell.icon:Hide()
        local g = s.glyph or "?"
        local ch = f.cellH
        local lines = select(2, g:gsub("\n", "")) + 1
        local size
        if lines > 1 then size = ch * 0.2
        elseif #g == 1 then size = ch * (s.big and 0.62 or 0.5)
        elseif #g == 2 then size = ch * 0.42
        else size = ch * 0.26 end
        cell.glyph:SetFont(FONT, math.floor(size), light and "" or "THICKOUTLINE")
        cell.glyph:SetText(g)
        cell.glyph:SetTextColor(s.color[1], s.color[2], s.color[3])
    end
    local cap = CAPTIONS[m.id] and CAPTIONS[m.id][symId]
    if cap then
        cell.cap:SetText(cap)
        cell.cap:SetTextColor(1, 0.85, 0.2)
        cell.cap:Show()
    else
        cell.cap:Hide()
    end
end

function RUI:Build(m)
    local Reels = Engine()
    local t = m.theme
    local cw, ch = geometry(m)
    local areaW = m.reels * cw
    local areaH = m.rows * ch
    local W = math.max(areaW + 80, 660)
    local H = 96 + 40 + areaH + 24 + 44 + 90

    local f = CreateFrame("Frame", "ChairfacesCasinoReels_" .. m.id, UIParent, "BackdropTemplate")
    f.m, f.cellW, f.cellH = m, cw, ch
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
    f:SetBackdropColor(t.bg[1], t.bg[2], t.bg[3], 0.98)
    f:SetBackdropBorderColor(t.border[1], t.border[2], t.border[3], 1)
    f:Hide()

    f.state = { coin = 1, level = Reels:MaxLevel(m), token = 0, pending = 0,
                shownWin = 0, autoLeft = 0 }
    if m.id == "jade" then f.state.level = 1 end

    -- ===== header: title band =====
    local band = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    band:SetPoint("TOPLEFT", 3, -3)
    band:SetPoint("TOPRIGHT", -3, -3)
    band:SetHeight(86)
    band:SetColorTexture(t.bg2[1], t.bg2[2], t.bg2[3], 0.85)
    local stripe = f:CreateTexture(nil, "BACKGROUND", nil, 2)
    stripe:SetPoint("TOPLEFT", band, "BOTTOMLEFT")
    stripe:SetPoint("TOPRIGHT", band, "BOTTOMRIGHT")
    stripe:SetHeight(3)
    stripe:SetColorTexture(t.border[1], t.border[2], t.border[3], 1)

    -- marquee bulbs along the band's bottom edge (they chase on wins)
    f.bulbs = {}
    local nb = math.floor((W - 20) / 22)
    for i = 1, nb do
        local b = f:CreateTexture(nil, "ARTWORK")
        b:SetSize(6, 6)
        b:SetPoint("CENTER", stripe, "LEFT", 10 + (i - 1) * 22, 0)
        b:SetColorTexture(1, 0.95, 0.6, 1)
        f.bulbs[i] = b
    end

    local title = text(f, 30, "THICKOUTLINE")
    title:SetPoint("TOP", 0, -12)
    title:SetText(m.title:upper())
    title:SetTextColor(t.title[1], t.title[2], t.title[3])
    f.titleFS = title
    local tag = text(f, 11, "OUTLINE")
    tag:SetPoint("TOP", title, "BOTTOM", 0, -4)
    tag:SetText(m.tagline)
    tag:SetTextColor(t.accent[1], t.accent[2], t.accent[3])

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() f:Hide(); Floor:Show() end)

    local back = makeButton(f, 70, 22, "< FLOOR", t, 10)
    back:SetPoint("TOPLEFT", 10, -10)
    back:SetScript("OnClick", function() f:Hide(); Floor:Show() end)

    -- ===== marquee plate (jackpots / feature summary) =====
    local mq = plate(f, { 0, 0, 0, 0.6 }, { t.border[1], t.border[2], t.border[3], 0.7 })
    mq:SetPoint("TOP", 0, -96)
    mq:SetSize(W - 40, 32)
    f.marquee = mq
    if m.id == "jade" then
        f.jpPlates = {}
        local n = #m.jackpots
        local pw = (W - 60) / n
        for i, j in ipairs(m.jackpots) do
            local p = plate(mq, { 0.05, 0.02, 0.02, 1 }, { j.color[1], j.color[2], j.color[3], 1 })
            p:SetSize(pw - 8, 26)
            p:SetPoint("LEFT", mq, "LEFT", 6 + (i - 1) * pw, 0)
            p.label = text(p, 11, "OUTLINE")
            p.label:SetPoint("LEFT", 6, 0)
            p.label:SetText(j.label)
            p.label:SetTextColor(j.color[1], j.color[2], j.color[3])
            p.value = text(p, 13, "OUTLINE")
            p.value:SetPoint("RIGHT", -6, 0)
            p.pips = text(p, 12, "OUTLINE")
            p.pips:SetPoint("CENTER", 0, 0)
            p.pips:SetTextColor(1, 1, 1)
            p.j = j
            f.jpPlates[j.key] = p
        end
    elseif m.id == "darkmoon" then
        local fs = text(mq, 11, "OUTLINE")
        fs:SetPoint("CENTER")
        fs:SetTextColor(1, 0.85, 0.3)
        f.mqText = fs
    else
        local fs = text(mq, 10, "OUTLINE")
        fs:SetPoint("CENTER")
        fs:SetText(MARQUEE[m.id] or "")
        fs:SetTextColor(t.title[1], t.title[2], t.title[3])
        f.mqText = fs
    end

    -- ===== the reels =====
    local area = plate(f, { 0, 0, 0, 1 }, { t.border[1], t.border[2], t.border[3], 1 }, 3)
    area:SetSize(areaW + 12, areaH + 12)
    area:SetPoint("TOP", mq, "BOTTOM", 0, -8)
    f.area = area

    f.cols = {}
    for r = 1, m.reels do
        local col = CreateFrame("Frame", nil, area, "BackdropTemplate")
        col:SetSize(cw - 4, areaH)
        col:SetPoint("TOPLEFT", 6 + (r - 1) * cw + 2, -6)
        col:SetBackdrop({ bgFile = WHITE })
        local rc = t.reel
        col:SetBackdropColor(rc[1], rc[2], rc[3], 1)
        if col.SetClipsChildren then col:SetClipsChildren(true) end
        -- reels shaded towards their top and bottom edges, like a drum
        if not t.lightReels then
            local top = col:CreateTexture(nil, "OVERLAY", nil, 7)
            top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(10)
            top:SetColorTexture(0, 0, 0, 0.45)
            local bot = col:CreateTexture(nil, "OVERLAY", nil, 7)
            bot:SetPoint("BOTTOMLEFT"); bot:SetPoint("BOTTOMRIGHT"); bot:SetHeight(10)
            bot:SetColorTexture(0, 0, 0, 0.45)
        end
        col.glow = col:CreateTexture(nil, "BACKGROUND", nil, 1)
        col.glow:SetAllPoints()
        col.glow:SetColorTexture(t.accent[1], t.accent[2], t.accent[3], 0)
        col.cells = {}
        for k = 0, m.rows do
            local c = newCell(col, m, cw, ch)
            col.cells[k] = c   -- index = slot (0 = parked above the window)
        end
        col.offset = 0
        f.cols[r] = col
    end
    self:LayoutCols(f)

    if m.payRow then
        -- the stepper's payline: a red rule across the middle
        for _, side in ipairs({ -1, 1 }) do
            local ln = area:CreateTexture(nil, "OVERLAY", nil, 6)
            ln:SetColorTexture(0.9, 0.1, 0.1, 0.85)
            ln:SetHeight(2)
            ln:SetPoint("LEFT", area, "TOPLEFT", 4, -(6 + (m.payRow - 0.5) * ch) + side * (ch / 2 - 2))
            ln:SetPoint("RIGHT", area, "TOPRIGHT", -4, -(6 + (m.payRow - 0.5) * ch) + side * (ch / 2 - 2))
        end
        local arrowL = text(area, 22, "THICKOUTLINE")
        arrowL:SetPoint("RIGHT", area, "TOPLEFT", -2, -(6 + (m.payRow - 0.5) * ch))
        arrowL:SetText(">")
        arrowL:SetTextColor(1, 0.2, 0.2)
        local arrowR = text(area, 22, "THICKOUTLINE")
        arrowR:SetPoint("LEFT", area, "TOPRIGHT", 2, -(6 + (m.payRow - 0.5) * ch))
        arrowR:SetText("<")
        arrowR:SetTextColor(1, 0.2, 0.2)
    end

    -- free-games badge rides on the reel frame's top edge
    local fg = plate(area, { t.bg2[1], t.bg2[2], t.bg2[3], 1 }, { 1, 0.9, 0.3, 1 }, 2)
    fg:SetSize(260, 26)
    fg:SetPoint("BOTTOM", area, "TOP", 0, -2)
    fg:SetFrameLevel(area:GetFrameLevel() + 20)
    fg.fs = text(fg, 13, "OUTLINE")
    fg.fs:SetPoint("CENTER")
    fg:Hide()
    f.freeBadge = fg

    -- a full-width banner over the reels for the big moments
    local banner = plate(area, { 0, 0, 0, 0.82 }, { t.border[1], t.border[2], t.border[3], 1 }, 2)
    banner:SetPoint("LEFT", 20, 0)
    banner:SetPoint("RIGHT", -20, 0)
    banner:SetHeight(96)
    banner:SetFrameLevel(area:GetFrameLevel() + 30)
    banner.big = text(banner, 30, "THICKOUTLINE")
    banner.big:SetPoint("CENTER", 0, 14)
    banner.small = text(banner, 16, "OUTLINE")
    banner.small:SetPoint("CENTER", 0, -22)
    banner:Hide()
    f.banner = banner

    -- ===== status line under the reels =====
    local status = text(f, 16, "OUTLINE")
    status:SetPoint("TOP", area, "BOTTOM", 0, -6)
    status:SetText("")
    f.status = status

    -- ===== controls =====
    local ctl = plate(f, { 0, 0, 0, 0.55 }, { t.border[1], t.border[2], t.border[3], 0.6 })
    ctl:SetPoint("BOTTOMLEFT", 12, 42)
    ctl:SetPoint("BOTTOMRIGHT", -12, 42)
    ctl:SetHeight(70)
    f.ctl = ctl

    local function stepper(label, x, onDown, onUp)
        local lab = text(ctl, 10, "OUTLINE")
        lab:SetPoint("TOPLEFT", x, -8)
        lab:SetText(label)
        lab:SetTextColor(t.title[1], t.title[2], t.title[3])
        local down = makeButton(ctl, 26, 26, "-", t, 16)
        down:SetPoint("TOPLEFT", x, -24)
        local val = text(ctl, 15, "OUTLINE")
        val:SetWidth(64)
        val:SetJustifyH("CENTER")
        val:SetPoint("LEFT", down, "RIGHT", 2, 0)
        local up = makeButton(ctl, 26, 26, "+", t, 16)
        up:SetPoint("LEFT", val, "RIGHT", 2, 0)
        local sub = text(ctl, 9, "")
        sub:SetPoint("TOP", val, "BOTTOM", 0, -8)
        sub:SetTextColor(0.75, 0.75, 0.75)
        down:SetScript("OnClick", onDown)
        up:SetScript("OnClick", onUp)
        return down, val, up, sub
    end

    f.coinDown, f.coinVal, f.coinUp, f.coinSub = stepper("COIN VALUE", 12,
        function() RUI:StepCoin(f, -1) end, function() RUI:StepCoin(f, 1) end)
    if Reels:MaxLevel(m) > 1 then
        local lbl = (m.id == "jade") and "GOLD LEVEL" or "COINS PLAYED"
        f.lvlDown, f.lvlVal, f.lvlUp, f.lvlSub = stepper(lbl, 150,
            function() RUI:StepLevel(f, -1) end, function() RUI:StepLevel(f, 1) end)
    end

    local spin = makeButton(ctl, 120, 54, "SPIN", t, 20)
    spin:SetPoint("RIGHT", ctl, "RIGHT", -10, 0)
    spin.fill = { 0.1, 0.55, 0.15 }
    spin:SetScript("OnClick", function() RUI:OnSpin(f) end)
    spin:paint()
    f.spinBtn = spin

    local maxb = makeButton(ctl, 84, 25, (m.id == "darkmoon") and "BET MAX" or "MAX BET", t, 11)
    maxb:SetPoint("TOPRIGHT", spin, "TOPLEFT", -8, 0)
    maxb:SetScript("OnClick", function() RUI:MaxBet(f) end)
    f.maxBtn = maxb

    local auto = makeButton(ctl, 84, 25, "AUTO", t, 11)
    auto:SetPoint("BOTTOMRIGHT", spin, "BOTTOMLEFT", -8, 0)
    auto:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    auto:SetScript("OnClick", function(_, button) RUI:CycleAuto(f, button) end)
    auto:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Auto-spin")
        GameTooltip:AddLine("Left-click: start / stop a batch", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Right-click: batch size", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    f.autoBtn = auto

    local pays = makeButton(ctl, 64, 25, "PAYS", t, 11)
    pays:SetPoint("TOPRIGHT", maxb, "TOPLEFT", -8, 0)
    pays:SetScript("OnClick", function() RUI:TogglePays(f) end)
    f.paysBtn = pays

    -- ===== credit meter =====
    local meter = plate(f, { 0, 0, 0, 0.85 }, { t.border[1], t.border[2], t.border[3], 1 })
    meter:SetPoint("BOTTOMLEFT", 12, 10)
    meter:SetPoint("BOTTOMRIGHT", -12, 10)
    meter:SetHeight(28)
    f.creditFS = text(meter, 15, "OUTLINE")
    f.creditFS:SetPoint("LEFT", 12, 0)
    f.betFS = text(meter, 15, "OUTLINE")
    f.betFS:SetPoint("CENTER", 0, 0)
    f.winFS = text(meter, 15, "OUTLINE")
    f.winFS:SetPoint("RIGHT", -12, 0)

    -- one driver frame for every per-frame animation
    f.driver = CreateFrame("Frame", nil, f)
    f.anims = {}
    f.driver:SetScript("OnUpdate", function(_, dt) RUI:Tick(f, dt) end)

    f:SetScript("OnShow", function()
        RUI.frame = f
        RUI:UpdateDisplay(f)
    end)
    f:SetScript("OnHide", function()
        if RUI.frame == f then RUI.frame = nil end
        RUI:Abort(f)
        if f.pays then f.pays:Hide() end
    end)

    if BJ.EscapeHandler then BJ.EscapeHandler:RegisterFrame(f:GetName()) end

    -- first look: a random resting screen
    local grid = m:SpinOnce(false)
    self:ShowGrid(f, grid)
    self.frames[m.id] = f
    return f
end

--[[ ----- reel geometry & rendering ----- ]]

function RUI:LayoutCols(f)
    local ch = f.cellH
    for _, col in ipairs(f.cols) do
        for k = 0, f.m.rows do
            local c = col.cells[k]
            c:ClearAllPoints()
            c:SetPoint("TOP", col, "TOP", 0, -(k - 1) * ch + col.offset)
        end
    end
end

function RUI:ShowGrid(f, grid, bombs)
    for r, col in ipairs(f.cols) do
        col.offset = 0
        for k = 1, f.m.rows do
            self:SetCell(f, col.cells[k], grid[r][k])
            col.cells[k]:SetAlpha(1)
        end
        self:SetCell(f, col.cells[0], self:Filler(f.m, r))
    end
    self:LayoutCols(f)
    self:ClearHighlights(f)
    if bombs then self:ShowBombs(f, bombs) end
end

function RUI:Filler(m, r)
    if m.strips and m.strips[r] then
        local s = m.strips[r]
        return s[math.random(#s)]
    end
    if m.weightList then
        local l = m.weightList
        return l[math.random(#l)][1]
    end
    return m.symbols[math.random(#m.symbols)].id
end

function RUI:ClearHighlights(f)
    f.pulse = nil
    for _, col in ipairs(f.cols) do
        col.glow:SetColorTexture(0, 0, 0, 0)
        for k = 0, f.m.rows do
            local c = col.cells[k]
            c.hl:SetColorTexture(1, 1, 1, 0)
            c:SetAlpha(1)
            c.icon:SetSize(c.iconSize, c.iconSize)
        end
    end
end

-- Light a set of cells (pulsing in the machine's accent), dim the rest.
function RUI:Highlight(f, cells, dimOthers)
    self:ClearHighlights(f)
    local lit = {}
    for _, c in ipairs(cells or {}) do lit[c.reel .. ":" .. c.row] = true end
    for r, col in ipairs(f.cols) do
        for k = 1, f.m.rows do
            local cell = col.cells[k]
            if lit[r .. ":" .. k] then
                cell:SetAlpha(1)
            elseif dimOthers then
                cell:SetAlpha(0.35)
            end
        end
    end
    f.pulse = { lit = lit, t = 0 }
end

function RUI:ShowBombs(f, bombs)
    for key, v in pairs(bombs or {}) do
        local r, row = key:match("^(%d+):(%d+)$")
        local col = f.cols[tonumber(r)]
        local cell = col and col.cells[tonumber(row)]
        if cell then
            cell.badge:SetText("x" .. v)
            cell.badge:Show()
        end
    end
end

function RUI:ShowMultipliers(f, cellMult)
    for key, v in pairs(cellMult or {}) do
        local r, row = key:match("^(%d+):(%d+)$")
        local cell = f.cols[tonumber(r)].cells[tonumber(row)]
        cell.badge:SetText("x" .. v)
        cell.badge:Show()
    end
end

--[[ ----- the animation clock ----- ]]

function RUI:Tick(f, dt)
    -- reel scrolling
    if f.spin then self:TickSpin(f, dt) end
    -- tumbling cells
    if f.drops then self:TickDrops(f, dt) end
    -- wheel
    if f.wheelAnim then self:TickWheel(f, dt) end
    -- win pulse
    if f.pulse then
        local p = f.pulse
        p.t = p.t + dt
        local a = 0.25 + 0.35 * math.abs(math.sin(p.t * 5))
        local acc = f.m.theme.accent
        local grow = 1 + 0.1 * math.abs(math.sin(p.t * 5))
        for key in pairs(p.lit) do
            local r, row = key:match("^(%d+):(%d+)$")
            local cell = f.cols[tonumber(r)].cells[tonumber(row)]
            cell.hl:SetColorTexture(acc[1], acc[2], acc[3], a)
            cell.icon:SetSize(cell.iconSize * grow, cell.iconSize * grow)
        end
    end
    -- chasing marquee bulbs while a win shows
    f.bulbT = (f.bulbT or 0) + dt
    local chase = f.celebrate and math.floor(f.bulbT * 12) or math.floor(f.bulbT * 2)
    for i, b in ipairs(f.bulbs) do
        local on = ((i + chase) % 3 == 0)
        if f.celebrate then
            b:SetColorTexture(1, 0.95, 0.4, on and 1 or 0.25)
        else
            b:SetColorTexture(1, 0.95, 0.6, on and 0.9 or 0.5)
        end
    end
    -- win meter roll-up
    if f.roll then
        local ro = f.roll
        ro.t = ro.t + dt
        local p = math.min(ro.t / ro.dur, 1)
        f.state.shownWin = math.floor(ro.from + (ro.to - ro.from) * p)
        f.winFS:SetText("|cffffe100WIN|r " .. fmtBig(f.state.shownWin))
        f.creditFS:SetText("|cffffe100CREDIT|r " .. fmtBig(self:ShownCredits(f)))
        ro.tick = (ro.tick or 0) + dt
        if ro.tick > 0.1 and p < 1 then ro.tick = 0; BJ:PlaySfx("coin.ogg") end
        if p >= 1 then
            f.roll = nil
            if ro.done then ro.done() end
        end
    end
end

--[[ ----- stepper reels: scroll, then land with a bounce ----- ]]

local SPIN_SPEED = 1500   -- px/s

-- Scroll every reel and land them left to right on `grid`. `anticipate`
-- is the set of reels that hold (glowing) because a feature is one symbol
-- away.
function RUI:SpinTo(f, grid, anticipate, fast, done)
    local m = f.m
    local s = { t = 0, reels = {}, done = done }
    local base = fast and 0.45 or 0.7
    local gap = fast and 0.18 or 0.26
    local at = base
    for r = 1, m.reels do
        if anticipate and anticipate[r] then at = at + 1.3 end
        s.reels[r] = { stopAt = at, state = "spin", feed = nil }
        at = at + gap
    end
    f.spin = s
    f.lastGrid = grid
    BJ:PlaySfx("Arcade\\reel_spin.ogg")
end

function RUI:TickSpin(f, dt)
    local s = f.spin
    local m = f.m
    local ch = f.cellH
    s.t = s.t + dt
    local allDone = true
    for r, col in ipairs(f.cols) do
        local rs = s.reels[r]
        if rs.state ~= "done" then allDone = false end
        if rs.state == "spin" or rs.state == "feed" then
            if rs.state == "spin" and s.t >= rs.stopAt then
                -- start feeding the landing symbols, bottom row first
                rs.state = "feed"
                rs.feed = {}
                for k = m.rows, 1, -1 do rs.feed[#rs.feed + 1] = f.lastGrid[r][k] end
                rs.shiftsLeft = m.rows + 1
                col.glow:SetColorTexture(0, 0, 0, 0)
            end
            if s.anticipate and s.anticipate[r] and rs.state == "spin" and s.t >= (rs.stopAt - 1.3) then
                local a = 0.15 + 0.2 * math.abs(math.sin(s.t * 8))
                local acc = m.theme.accent
                col.glow:SetColorTexture(acc[1], acc[2], acc[3], a)
                if not rs.sweat then
                    rs.sweat = true
                    BJ:PlaySfx("Arcade\\anticipation3.ogg")
                end
            end
            col.offset = col.offset - SPIN_SPEED * dt
            while col.offset <= -ch do
                col.offset = col.offset + ch
                -- every cell steps down a slot; the bottom one wraps to the top
                local cells = col.cells
                local bottom = cells[m.rows]
                for k = m.rows, 1, -1 do cells[k] = cells[k - 1] end
                cells[0] = bottom
                local nextSym
                if rs.state == "feed" and #rs.feed > 0 then
                    nextSym = table.remove(rs.feed, 1)
                else
                    nextSym = self:Filler(m, r)
                end
                self:SetCell(f, cells[0], nextSym)
                if rs.state == "feed" then
                    rs.shiftsLeft = rs.shiftsLeft - 1
                    if rs.shiftsLeft <= 0 then
                        rs.state = "bounce"
                        rs.bt = 0
                        col.offset = 0
                        BJ:PlaySfx("Arcade\\reel_stop" .. ((r - 1) % 3 + 1) .. ".ogg")
                        break
                    end
                end
            end
        elseif rs.state == "bounce" then
            rs.bt = rs.bt + dt
            local p = math.min(rs.bt / 0.16, 1)
            col.offset = -10 * math.sin(p * math.pi) -- dips past the line, springs back
            if p >= 1 then
                col.offset = 0
                rs.state = "done"
            end
        end
        -- position: offset <= 0 means the reel has moved DOWN by -offset
        for k = 0, m.rows do
            local c = col.cells[k]
            c:ClearAllPoints()
            c:SetPoint("TOP", col, "TOP", 0, -(k - 1) * ch + col.offset)
        end
    end
    if allDone then
        f.spin = nil
        if s.done then s.done() end
    end
end

-- Which reels should sweat: once (need - 1) feature symbols are showing,
-- every later reel that could still complete it holds its stop.
function RUI:Anticipation(f, grid, sym, need)
    if not sym then return nil end
    local ant, count = {}, 0
    local any = false
    local m = f.m
    for r = 1, m.reels do
        local canLand = true
        if m.strips and m.strips[r] then
            canLand = false
            for _, v in ipairs(m.strips[r]) do
                if v == sym then canLand = true break end
            end
        end
        if count >= need - 1 and canLand then ant[r] = true; any = true end
        for _, v in ipairs(grid[r]) do if v == sym then count = count + 1 end end
    end
    return any and ant or nil
end

--[[ ----- tumbling columns (Bonanza) ----- ]]

local GRAVITY = 55   -- rows / s^2

function RUI:TickDrops(f, dt)
    local d = f.drops
    d.t = d.t + dt
    local ch = f.cellH
    local moving = false
    for r, col in ipairs(f.cols) do
        for k = 1, f.m.rows do
            local c = col.cells[k]
            if c.delay and c.delay > 0 then
                c.delay = c.delay - dt
                moving = true
            elseif c.pos and c.pos < c.tpos then
                c.vel = (c.vel or 0) + GRAVITY * dt
                c.pos = c.pos + c.vel * dt
                if c.pos >= c.tpos then
                    c.pos = c.tpos
                    c.vel = 0
                    if not d.silent then d.landed = (d.landed or 0) + 1 end
                else
                    moving = true
                end
            end
            if c.pos then
                c:ClearAllPoints()
                c:SetPoint("TOP", col, "TOP", 0, -(c.pos - 1) * ch)
            end
        end
    end
    if d.clack and (d.landed or 0) > 0 and d.t - (d.lastClack or 0) > 0.09 then
        d.lastClack = d.t
        d.landed = 0
        BJ:PlaySfx("Arcade\\reel_stop" .. math.random(3) .. ".ogg")
    end
    if not moving and d.t > 0.05 then
        f.drops = nil
        if d.done then d.done() end
    end
end

-- A whole new screen drops in from above, column by column.
function RUI:DropIn(f, grid, bombs, fast, done)
    local rows = f.m.rows
    for r, col in ipairs(f.cols) do
        col.cells[0]:Hide()
        for k = 1, rows do
            local c = col.cells[k]
            self:SetCell(f, c, grid[r][k])
            c:SetAlpha(1)
            c.icon:SetSize(c.iconSize, c.iconSize)
            c.hl:SetColorTexture(1, 1, 1, 0)
            c.pos = k - rows - 0.4
            c.tpos = k
            c.vel = 0
            c.delay = (r - 1) * (fast and 0.05 or 0.08) + (rows - k) * 0.025
        end
    end
    f.pulse = nil
    f.drops = { t = 0, clack = true, done = function()
        if bombs then self:ShowBombs(f, bombs) end
        if done then done() end
    end }
end

-- One tumble: the winning cells burst, the survivors fall, new symbols
-- fill from the top (all read from the engine's recorded step).
function RUI:Tumble(f, step, nextBombs, done)
    local rows = f.m.rows
    local burst = {}
    for _, w in ipairs(step.wins) do
        for _, c in ipairs(w.cells) do burst[c.reel .. ":" .. c.row] = true end
    end
    -- burst: flare then vanish
    for r, col in ipairs(f.cols) do
        for k = 1, rows do
            if burst[r .. ":" .. k] then
                local c = col.cells[k]
                c.icon:SetSize(c.iconSize * 1.3, c.iconSize * 1.3)
            end
        end
    end
    BJ:PlaySfx("Arcade\\payout_small.ogg")
    self:After(f, 0.3, function()
        for r, col in ipairs(f.cols) do
            local keep, gone = {}, {}
            for k = 1, rows do
                local c = col.cells[k]
                if burst[r .. ":" .. k] then gone[#gone + 1] = c else keep[#keep + 1] = c end
            end
            local missing = #gone
            local newCells = {}
            -- new ones come in from above (reusing the burst frames)
            for i, c in ipairs(gone) do
                self:SetCell(f, c, step.after[r][i])
                c:SetAlpha(1)
                c.icon:SetSize(c.iconSize, c.iconSize)
                c.hl:SetColorTexture(1, 1, 1, 0)
                c.pos = i - missing - 0.3
                c.tpos = i
                c.vel = 0
                c.delay = (r - 1) * 0.03
                newCells[i] = c
            end
            for i, c in ipairs(keep) do
                c.badge:Hide()
                c.pos = c.pos or i
                c.tpos = missing + i
                c.vel = 0
                c.delay = 0
                newCells[missing + i] = c
            end
            for k = 1, rows do col.cells[k] = newCells[k] end
        end
        f.pulse = nil
        f.drops = { t = 0, clack = false, done = function()
            self:ShowBombs(f, nextBombs)
            if done then done() end
        end }
    end)
end

-- Scroll-reel layout expects every cell's pos cleared again.
function RUI:ResetDropState(f)
    for _, col in ipairs(f.cols) do
        for k = 0, f.m.rows do
            local c = col.cells[k]
            c.pos, c.tpos, c.vel, c.delay = nil, nil, nil, nil
        end
    end
end

--[[ ----- timers that die with the spin ----- ]]

function RUI:After(f, secs, fn)
    local token = f.state.token
    C_Timer.After(secs, function()
        if f.state.token ~= token or not f:IsShown() then return end
        fn()
    end)
end

function RUI:Abort(f)
    local st = f.state
    st.token = st.token + 1
    st.pending = 0
    st.busy = false
    st.autoLeft = 0
    f.spin, f.drops, f.wheelAnim, f.roll = nil, nil, nil, nil
    f.celebrate = false
    f.banner:Hide()
    f.freeBadge:Hide()
    if f.wheel then f.wheel:Hide() end
    if f.pick then f.pick:Hide() end
    self:ResetDropState(f)
    -- settle on the last screen the spin would have ended on
    local res = st.result
    local rec = res and (res.free[#res.free] or res.base)
    local grid = rec and (rec.final or rec.grid) or f.lastGrid
    if grid then self:ShowGrid(f, grid) end
end

--[[ ----- bets ----- ]]

function RUI:Cost(f)
    local R = Engine()
    return R:CostCoins(f.m, f.state.level) * f.state.coin
end

function RUI:StepCoin(f, dir)
    if f.state.busy then return end
    local nxt = Engine():NextCoin(f.state.coin, dir)
    if nxt ~= f.state.coin then
        f.state.coin = nxt
        if dir > 0 then BJ:PlaySfx("Arcade\\coin_insert.ogg") end
        self:UpdateDisplay(f)
    end
end

function RUI:StepLevel(f, dir)
    if f.state.busy then return end
    local maxL = Engine():MaxLevel(f.m)
    local nxt = math.max(1, math.min(maxL, f.state.level + dir))
    if nxt ~= f.state.level then
        f.state.level = nxt
        if dir > 0 then BJ:PlaySfx("Arcade\\coin_insert.ogg") end
        self:UpdateDisplay(f)
    end
end

-- MAX BET: top level at the biggest coin the balance covers, then spin.
function RUI:MaxBet(f)
    local st = f.state
    if st.busy then return end
    local R = Engine()
    st.level = R:MaxLevel(f.m)
    local credits = BJ.Arcade:GetCredits()
    local unit = R:CostCoins(f.m, st.level)
    while st.coin > 1 and st.coin * unit > credits do
        st.coin = R:NextCoin(st.coin, -1)
    end
    BJ:PlaySfx("Arcade\\coin_insert.ogg")
    self:UpdateDisplay(f)
    self:OnSpin(f)
end

-- AUTO: left-click starts a batch (or stops a running one); right-click
-- picks the batch size.
local AUTO_STEPS = { 10, 25, 50, 100 }
function RUI:CycleAuto(f, button)
    local st = f.state
    st.autoSize = st.autoSize or AUTO_STEPS[1]
    if button == "RightButton" then
        local idx = 1
        for i, v in ipairs(AUTO_STEPS) do if v == st.autoSize then idx = i end end
        st.autoSize = AUTO_STEPS[idx % #AUTO_STEPS + 1]
    elseif (st.autoLeft or 0) > 0 then
        st.autoLeft = 0
    else
        st.autoLeft = st.autoSize
        if not st.busy then self:OnSpin(f) end
    end
    self:UpdateDisplay(f)
end

--[[ ----- the spin ----- ]]

function RUI:OnSpin(f)
    local st = f.state
    if st.busy then return end
    local Arcade = BJ.Arcade
    if Arcade:GetCredits() < 1 then
        local ok, refills = Arcade:CompMe()
        if ok then
            BJ:Print("|cff00ff00The pit boss comps you " .. Arcade.COMP_AMOUNT ..
                " credits.|r (Refill #" .. refills .. ")")
        end
        self:UpdateDisplay(f)
        return
    end
    local result, err = Engine():Play(f.m.id, st.coin, st.level)
    if not result then
        BJ:Print("|cffff8800" .. (err or "Cannot spin.") .. "|r")
        st.autoLeft = 0
        self:UpdateDisplay(f)
        return
    end
    if st.autoLeft and st.autoLeft > 0 then st.autoLeft = st.autoLeft - 1 end

    st.token = st.token + 1
    st.busy = true
    st.pending = result.total
    st.result = result
    st.shownWin = 0
    f.roll = nil
    f.celebrate = false
    f.banner:Hide()
    f.status:SetText("")
    self:ClearHighlights(f)
    BJ:PlaySfx("Arcade\\slot_lever.ogg")
    self:UpdateDisplay(f)

    self:PlayRecord(f, result.base, false, function()
        self:AfterBase(f, result)
    end)
end

-- Spin one record onto the reels and pay it out on screen.
function RUI:PlayRecord(f, rec, free, done)
    local m = f.m
    if m.id == "bonanza" then
        self:DropIn(f, rec.grid, rec.firstBombs, free, function()
            self:PlayTumbles(f, rec, 1, 0, done)
        end)
        return
    end
    local need = (m.id == "darkmoon") and nil or 3
    local ant = need and self:Anticipation(f, rec.grid, m.scatter, need)
    if m.id == "kodo" and free then ant = nil end
    self:SpinTo(f, rec.grid, ant, free, function()
        if rec.cellMult then self:ShowMultipliers(f, rec.cellMult) end
        self:RevealWins(f, rec, done)
    end)
    f.spin.anticipate = ant
end

-- Bonanza: evaluate/burst/fall through each recorded tumble step.
function RUI:PlayTumbles(f, rec, i, runUnits, done)
    local step = rec.tumbles[i]
    if not step or #step.wins == 0 then
        -- sequence over: bombs, scatters
        local credits = rec.credits
        local function finish()
            self:RevealWins(f, rec, done, true)
        end
        if rec.bombApplied then
            local cells = {}
            for key in pairs(rec.finalBombs or {}) do
                local r, row = key:match("^(%d+):(%d+)$")
                cells[#cells + 1] = { reel = tonumber(r), row = tonumber(row) }
            end
            self:Highlight(f, cells, true)
            f.status:SetText(("|cffffd700BOMBS! x%d|r  |cff00ff00%s x %d|r"):format(
                rec.bombSum, fmtBig(math.floor(rec.tumbleUnits / rec.bombSum * self:Coin(f) + 0.5)), rec.bombSum))
            BJ:PlaySfx("Arcade\\vibrant_win.ogg")
            self:After(f, 1.4, finish)
        else
            finish()
        end
        return
    end
    -- show this step's wins
    local cells, units = {}, 0
    local names = {}
    for _, w in ipairs(step.wins) do
        for _, c in ipairs(w.cells) do cells[#cells + 1] = c end
        units = units + w.units
        names[#names + 1] = w.count .. " " .. f.m.symbolById[w.sym].name
    end
    runUnits = runUnits + units
    self:Highlight(f, cells, true)
    f.status:SetText("|cff00ff00" .. table.concat(names, "  +  ") .. "|r   |cffffd700" ..
        fmtBig(math.floor(runUnits * self:Coin(f) + 0.5)) .. "|r")
    self:After(f, 0.9, function()
        local nextStep = rec.tumbles[i + 1]
        local nb = nextStep and nextStep.bombs or rec.finalBombs
        self:Tumble(f, step, nb, function()
            self:PlayTumbles(f, rec, i + 1, runUnits, done)
        end)
    end)
end

function RUI:Coin(f)
    return (f.state.result and f.state.result.coin) or f.state.coin
end

-- Light the record's wins, roll its credits onto the WIN meter.
function RUI:RevealWins(f, rec, done, quick)
    local m = f.m
    local st = f.state
    local credits = rec.credits or 0
    local cells = {}
    -- (tumble wins point at screens that have since fallen away; the
    -- tumbles lit their own)
    if m.id ~= "bonanza" then
        for _, w in ipairs(rec.wins or {}) do
            for _, c in ipairs(w.cells) do cells[#cells + 1] = c end
        end
    end
    if rec.scatterUnits and rec.scatterCells then
        for _, c in ipairs(rec.scatterCells) do cells[#cells + 1] = c end
    end
    if rec.freeAdded and rec.freeAdded > 0 and rec.scatterCells then
        for _, c in ipairs(rec.scatterCells) do cells[#cells + 1] = c end
    end
    if #cells > 0 then self:Highlight(f, cells, true) end

    if credits <= 0 then
        if not quick then f.status:SetText("") end
        self:After(f, 0.15, done)
        return
    end

    st.pending = math.max(0, st.pending - credits)
    local line = self:DescribeWins(f, rec)
    f.status:SetText(line)
    local cost = st.result.cost
    if credits >= 5 * cost then
        BJ:PlaySfx("Arcade\\vibrant_win.ogg")
    else
        BJ:PlaySfx("Arcade\\payout_small.ogg")
    end
    local dur = (credits < 2 * cost) and 0.5 or ((credits < 10 * cost) and 1.0 or 1.6)
    f.roll = { t = 0, dur = dur, from = st.shownWin, to = st.shownWin + credits, done = function()
        self:UpdateDisplay(f)
        self:After(f, 0.35, done)
    end }
    self:UpdateDisplay(f)
end

function RUI:DescribeWins(f, rec)
    local m = f.m
    local coin = self:Coin(f)
    local best, bestUnits = nil, 0
    for _, w in ipairs(rec.wins or {}) do
        if w.units > bestUnits then best, bestUnits = w, w.units end
    end
    local parts = {}
    if best then
        local name = best.label or (best.sym and m.symbolById[best.sym] and m.symbolById[best.sym].name) or "Win"
        if best.ways then
            parts[#parts + 1] = ("%d x %s  (%d ways)"):format(best.count, name, best.ways)
        elseif best.line and m.lines then
            parts[#parts + 1] = ("Line %d: %d x %s%s"):format(best.line, best.count, name,
                best.doubled and " (WILD x2)" or "")
        elseif best.count then
            parts[#parts + 1] = ("%d x %s"):format(best.count, name)
        else
            parts[#parts + 1] = name
        end
        if #rec.wins > 1 then parts[#parts + 1] = ("+%d more"):format(#rec.wins - 1) end
    end
    if rec.scatterUnits then
        parts[#parts + 1] = ("%d %s"):format(#rec.scatterCells,
            m.symbolById[m.scatter].name .. "s")
    end
    if rec.mult and rec.mult > 1 then parts[#parts + 1] = "x" .. rec.mult end
    return "|cff00ff00" .. table.concat(parts, "  ") .. "|r   |cffffd700+" ..
        fmtBig(rec.credits) .. "|r"
end

--[[ ----- after the base spin: features, then settle ----- ]]

function RUI:AfterBase(f, result)
    local m = f.m
    if result.freeAwarded then
        self:FreeGames(f, result, function() self:AfterFree(f, result) end)
    else
        self:AfterFree(f, result)
    end
end

function RUI:AfterFree(f, result)
    if result.wheel then
        self:Wheel(f, result, function() self:Finish(f, result) end)
    elseif result.pick then
        self:Pick(f, result, function() self:Finish(f, result) end)
    else
        if result.wheelMissed then
            f.status:SetText("|cffcc66ffSPIN landed - play 3 coins to turn the wheel!|r")
        end
        self:Finish(f, result)
    end
end

function RUI:Banner(f, big, small, color, secs, done)
    local b = f.banner
    b.big:SetText(big)
    b.big:SetTextColor(color[1], color[2], color[3])
    b.small:SetText(small or "")
    b:Show()
    b:SetAlpha(1)
    self:After(f, secs or 2, function()
        b:Hide()
        if done then done() end
    end)
end

function RUI:FreeGames(f, result, done)
    local m = f.m
    local t = m.theme
    local total = result.freeAwarded
    local label = (m.id == "bonanza" or m.id == "pharaoh") and "FREE SPINS" or "FREE GAMES"
    BJ:PlaySfx("Arcade\\jackpot.ogg", "Master")
    pcall(function() UI.Lobby:TrixieReact(f, "love", 5) end)
    local sub = ({
        kodo = "Sunset wilds are x2 and x3!",
        pharaoh = "All wins pay TRIPLE!",
        jade = "Fu wilds run hot!",
        bonanza = "Multiplier bombs are live!",
    })[m.id] or ""
    f.celebrate = true
    self:Banner(f, total .. " " .. label .. "!", sub, t.title, 2.6, function()
        f.celebrate = false
        local i = 0
        local awarded = total
        local function nextSpin()
            i = i + 1
            local rec = result.free[i]
            if not rec then
                f.freeBadge:Hide()
                self:ResetDropState(f)
                f.celebrate = true
                BJ:PlaySfx("Arcade\\coin_shower.ogg")
                self:Banner(f, label .. " WIN", fmtBig(result.freeTotal or 0) .. " credits",
                    { 0.4, 1, 0.4 }, 2.8, function()
                        f.celebrate = false
                        done()
                    end)
                return
            end
            f.freeBadge.fs:SetText(("%s  %d / %d%s"):format(label, i, awarded,
                (m.id == "pharaoh") and "   ALL WINS x3" or ""))
            f.freeBadge.fs:SetTextColor(1, 0.95, 0.5)
            f.freeBadge:Show()
            self:PlayRecord(f, rec, true, function()
                if rec.freeAdded and rec.freeAdded > 0 then
                    awarded = awarded + rec.freeAdded
                    BJ:PlaySfx("Arcade\\vibrant_win.ogg")
                    self:Banner(f, "+" .. rec.freeAdded .. " " .. label .. "!", "Retriggered!",
                        t.title, 1.6, nextSpin)
                else
                    self:After(f, 0.45, nextSpin)
                end
            end)
        end
        nextSpin()
    end)
end

-- The spin is fully revealed: celebrate size, clear pending, go again.
function RUI:Finish(f, result)
    local st = f.state
    st.pending = 0
    local cost = result.cost
    local total = result.total
    local function wrapUp()
        st.busy = false
        self:UpdateDisplay(f)
        if total > 0 then
            -- cycle each win in turn while the machine idles
            self:StartWinCycle(f, result)
        end
        if (st.autoLeft or 0) > 0 then
            if BJ.Arcade:GetCredits() < self:Cost(f) then
                st.autoLeft = 0
                BJ:Print("|cffff8800Auto-spin stopped - not enough credits.|r")
                self:UpdateDisplay(f)
            else
                self:After(f, total > 0 and 1.2 or 0.5, function() self:OnSpin(f) end)
            end
        end
    end
    if total >= 15 * cost then
        local word = (total >= 100 * cost and "EPIC WIN") or (total >= 40 * cost and "MEGA WIN") or "BIG WIN"
        f.celebrate = true
        BJ:PlaySfx("Arcade\\jackpot.ogg", "Master")
        BJ:PlaySfx("Arcade\\coin_shower.ogg")
        pcall(function() UI.Lobby:TrixieReact(f, "love", 5) end)
        pcall(function() UI.Lobby:PlayTrixieVoice("bigwin", { cd = 8 }) end)
        self:Banner(f, word .. "!", fmtBig(total) .. " credits" ..
            (result.capped and "  (max win)" or ""), { 1, 0.85, 0.2 }, 3, function()
            f.celebrate = false
            wrapUp()
        end)
    else
        if total == 0 and math.random(8) == 1 then
            pcall(function() UI.Lobby:TrixieReact(f, "lose", 3) end)
        end
        wrapUp()
    end
end

function RUI:StartWinCycle(f, result)
    local wins = {}
    local rec = result.base
    if not rec or #(rec.wins or {}) < 2 or f.m.id == "bonanza" or result.freeAwarded then return end
    for _, w in ipairs(rec.wins) do wins[#wins + 1] = w end
    local token = f.state.token
    local i = 0
    local function step()
        if f.state.token ~= token or f.state.busy or not f:IsShown() then return end
        i = i % #wins + 1
        local w = wins[i]
        self:Highlight(f, w.cells, true)
        local name = w.label or f.m.symbolById[w.sym].name
        local credits = math.floor(w.units * result.coin + 0.5)
        if w.ways then
            f.status:SetText(("|cff00ff00%d x %s - %d ways|r  |cffffd700%s|r"):format(w.count, name, w.ways, fmtBig(credits)))
        elseif w.line then
            f.status:SetText(("|cff00ff00Line %d: %d x %s|r  |cffffd700%s|r"):format(w.line, w.count, name, fmtBig(credits)))
        end
        C_Timer.After(1.3, step)
    end
    C_Timer.After(1.3, step)
end

--[[ ----- Darkmoon: the prize wheel ----- ]]

-- 24 painted slots; the smaller prizes repeat, like a real wheel.
local WHEEL_SLOTS = { 25, 150, 40, 300, 30, 75, 45, 1000, 25, 100, 35, 200,
                      30, 120, 50, 750, 40, 80, 60, 400, 35, 250, 45, 500 }

function RUI:EnsureWheel(f)
    if f.wheel then return f.wheel end
    local R = 150
    local w = CreateFrame("Frame", nil, f.area, "BackdropTemplate")
    w:SetSize(2 * R + 70, 2 * R + 70)
    w:SetPoint("CENTER", f, "CENTER", 0, 20)
    w:SetFrameStrata("DIALOG")
    w:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 3 })
    w:SetBackdropColor(0.08, 0.02, 0.12, 0.97)
    w:SetBackdropBorderColor(1, 0.8, 0.2, 1)
    w.R = R
    w.slots = {}
    local cols = { { 0.8, 0.1, 0.2 }, { 0.1, 0.35, 0.85 }, { 0.95, 0.75, 0.1 }, { 0.15, 0.6, 0.25 },
                   { 0.6, 0.15, 0.7 }, { 0.95, 0.45, 0.1 } }
    for i, v in ipairs(WHEEL_SLOTS) do
        local s = plate(w, cols[(i - 1) % #cols + 1], { 1, 1, 1, 0.8 })
        s:SetSize(44, 22)
        s.fs = text(s, 12, "OUTLINE")
        s.fs:SetPoint("CENTER")
        s.fs:SetText(v)
        s.value = v
        w.slots[i] = s
    end
    local hub = text(w, 16, "THICKOUTLINE")
    hub:SetPoint("CENTER")
    hub:SetText("DARKMOON\nWHEEL")
    hub:SetTextColor(1, 0.85, 0.3)
    w.hub = hub
    local ptr = text(w, 26, "THICKOUTLINE")
    ptr:SetPoint("TOP", w, "TOP", 0, -2)
    ptr:SetText("V")
    ptr:SetTextColor(1, 0.2, 0.2)
    w.result = text(w, 18, "THICKOUTLINE")
    w.result:SetPoint("BOTTOM", w, "BOTTOM", 0, 8)
    w:Hide()
    f.wheel = w
    return w
end

function RUI:PlaceWheel(w, angle)
    local n = #w.slots
    local lit = nil
    local bestCos = -2
    for i, s in ipairs(w.slots) do
        local a = angle + (i - 1) * (2 * math.pi / n)
        local x, y = math.sin(a) * w.R, math.cos(a) * w.R
        s:ClearAllPoints()
        s:SetPoint("CENTER", w, "CENTER", x, y)
        local c = math.cos(a)
        if c > bestCos then bestCos, lit = c, i end
    end
    for i, s in ipairs(w.slots) do
        s:SetBackdropBorderColor(1, 1, 1, i == lit and 1 or 0.5)
        -- (sized, not scaled: a scaled frame's anchor offsets scale too)
        if i == lit then s:SetSize(56, 28) else s:SetSize(44, 22) end
    end
    return lit
end

function RUI:Wheel(f, result, done)
    local w = self:EnsureWheel(f)
    local n = #WHEEL_SLOTS
    local target = {}
    for i, v in ipairs(WHEEL_SLOTS) do
        if v == result.wheel.coins then target[#target + 1] = i end
    end
    local slot = target[math.random(#target)]
    -- slot i sits at the top when angle = -(i-1)*step (mod 2pi)
    local stepA = 2 * math.pi / n
    local final = -(slot - 1) * stepA - (4 + math.random(2)) * 2 * math.pi
    w.result:SetText("")
    w:Show()
    self:PlaceWheel(w, 0)
    BJ:PlaySfx("Arcade\\jackpot.ogg", "Master")
    f.status:SetText("|cffcc66ffSPIN THE WHEEL!|r")
    self:After(f, 1.2, function()
        f.wheelAnim = { t = 0, dur = 5.5, from = 0, to = final, last = nil, done = function()
            local credits = result.wheel.credits
            w.result:SetText("|cff00ff00" .. result.wheel.coins .. " x " .. result.coin ..
                " = " .. fmtBig(credits) .. "|r")
            f.state.pending = math.max(0, f.state.pending - credits)
            BJ:PlaySfx("Arcade\\coin_shower.ogg")
            f.celebrate = true
            f.roll = { t = 0, dur = 1.6, from = f.state.shownWin, to = f.state.shownWin + credits }
            self:UpdateDisplay(f)
            self:After(f, 2.6, function()
                f.celebrate = false
                w:Hide()
                done()
            end)
        end }
    end)
end

function RUI:TickWheel(f, dt)
    local a = f.wheelAnim
    a.t = a.t + dt
    local p = math.min(a.t / a.dur, 1)
    local e = 1 - (1 - p) ^ 3          -- ease out: fast, then crawling to a stop
    local ang = a.from + (a.to - a.from) * e
    local lit = self:PlaceWheel(f.wheel, ang)
    if lit ~= a.last then
        a.last = lit
        BJ:PlaySfx("coin.ogg")
    end
    if p >= 1 then
        f.wheelAnim = nil
        if a.done then a.done() end
    end
end

--[[ ----- Jade Fortunes: the Fu Bat pick-em ----- ]]

function RUI:EnsurePick(f)
    if f.pick then return f.pick end
    local m = f.m
    local p = CreateFrame("Frame", nil, f.area, "BackdropTemplate")
    p:SetPoint("TOPLEFT", f.area, "TOPLEFT", 0, 0)
    p:SetPoint("BOTTOMRIGHT", f.area, "BOTTOMRIGHT", 0, 0)
    p:SetFrameStrata("DIALOG")
    p:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 3 })
    p:SetBackdropColor(0.25, 0.02, 0.02, 0.97)
    p:SetBackdropBorderColor(1, 0.8, 0.2, 1)
    p.head = text(p, 18, "THICKOUTLINE")
    p.head:SetPoint("TOP", 0, -8)
    p.head:SetTextColor(1, 0.85, 0.3)
    p.coins = {}
    local cols, rows = 4, 3
    local bw, bh = 110, 70
    local gx = (f.area:GetWidth() - cols * bw) / (cols + 1)
    for i = 1, m.pickCoins do
        local b = CreateFrame("Button", nil, p, "BackdropTemplate")
        b:SetSize(bw, bh)
        local cx = (i - 1) % cols
        local cy = math.floor((i - 1) / cols)
        b:SetPoint("TOPLEFT", gx + cx * (bw + gx), -40 - cy * (bh + 10))
        b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 2 })
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetSize(44, 44)
        b.icon:SetPoint("CENTER", 0, 6)
        b.icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_02")
        b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        b.fs = text(b, 14, "THICKOUTLINE")
        b.fs:SetPoint("BOTTOM", 0, 5)
        b:SetScript("OnClick", function() RUI:PickCoin(f, i) end)
        p.coins[i] = b
    end
    p.auto = makeButton(p, 110, 22, "PICK FOR ME", m.theme, 10)
    p.auto:SetPoint("BOTTOM", 0, 8)
    p.auto:SetScript("OnClick", function() RUI:AutoPick(f) end)
    p:Hide()
    f.pick = p
    return p
end

function RUI:Pick(f, result, done)
    local p = self:EnsurePick(f)
    local pk = result.pick
    p.state = { pk = pk, revealed = 0, counts = {}, done = done, over = false }
    p.head:SetText("THE FU BAT FLIES!  Pick coins - match 3 to win a jackpot")
    for _, b in ipairs(p.coins) do
        b.taken = nil
        b:SetBackdropColor(0.55, 0.08, 0.05, 1)
        b:SetBackdropBorderColor(1, 0.8, 0.2, 1)
        b.icon:SetDesaturated(false)
        b.icon:Show()
        b.fs:SetText("")
        b:SetAlpha(1)
        b:Enable()
    end
    for _, pl in pairs(f.jpPlates or {}) do pl.pips:SetText("") end
    p:Show()
    BJ:PlaySfx("Arcade\\jackpot.ogg", "Master")
    f.status:SetText("|cffffd700FU BAT JACKPOT BONUS|r")
    if (f.state.autoLeft or 0) > 0 then
        self:After(f, 1.2, function() self:AutoPick(f) end)
    end
end

local function jackpotByKey(m, key)
    for _, j in ipairs(m.jackpots) do if j.key == key then return j end end
end

function RUI:PickCoin(f, i)
    local p = f.pick
    local ps = p and p.state
    if not ps or ps.over then return end
    local b = p.coins[i]
    if b.taken then return end
    ps.revealed = ps.revealed + 1
    local key = ps.pk.order[ps.revealed]
    if not key then return end
    b.taken = key
    local j = jackpotByKey(f.m, key)
    b:SetBackdropColor(j.color[1] * 0.35, j.color[2] * 0.35, j.color[3] * 0.35, 1)
    b:SetBackdropBorderColor(j.color[1], j.color[2], j.color[3], 1)
    b.fs:SetText(j.label)
    b.fs:SetTextColor(j.color[1], j.color[2], j.color[3])
    b:Disable()
    ps.counts[key] = (ps.counts[key] or 0) + 1
    local pl = f.jpPlates and f.jpPlates[key]
    if pl then pl.pips:SetText(string.rep("o ", ps.counts[key])) end
    BJ:PlaySfx("coin.ogg")
    if ps.revealed >= #ps.pk.order then
        ps.over = true
        -- turn over the rest, dimmed
        local ri = 0
        for _, bb in ipairs(p.coins) do
            if not bb.taken then
                ri = ri + 1
                local rk = ps.pk.rest[ri]
                local rj = rk and jackpotByKey(f.m, rk)
                if rj then
                    bb.fs:SetText(rj.label)
                    bb.fs:SetTextColor(rj.color[1], rj.color[2], rj.color[3])
                end
                bb:SetAlpha(0.4)
                bb:Disable()
            end
        end
        -- flash the winners
        for _, bb in ipairs(p.coins) do
            if bb.taken == key then bb:SetBackdropBorderColor(1, 1, 1, 1) end
        end
        local credits = ps.pk.credits
        p.head:SetText("|cff00ff00" .. j.label .. " JACKPOT!  " .. fmtBig(credits) .. "|r")
        f.state.pending = math.max(0, f.state.pending - credits)
        BJ:PlaySfx("Arcade\\jackpot.ogg", "Master")
        BJ:PlaySfx("Arcade\\coin_shower.ogg")
        pcall(function() UI.Lobby:PlayTrixieVoice("jackpot", { cd = 8 }) end)
        f.celebrate = true
        f.roll = { t = 0, dur = 2, from = f.state.shownWin, to = f.state.shownWin + credits }
        self:UpdateDisplay(f)
        self:After(f, 3.2, function()
            f.celebrate = false
            p:Hide()
            for _, pl2 in pairs(f.jpPlates or {}) do pl2.pips:SetText("") end
            ps.done()
        end)
    end
end

function RUI:AutoPick(f)
    local p = f.pick
    if not (p and p.state) or p.state.over then return end
    for i, b in ipairs(p.coins) do
        if not b.taken then
            self:PickCoin(f, i)
            break
        end
    end
    if not p.state.over then self:After(f, 0.45, function() self:AutoPick(f) end) end
end

--[[ ----- the PAYS panel ----- ]]

function RUI:TogglePays(f)
    if f.pays and f.pays:IsShown() then f.pays:Hide() return end
    self:BuildPays(f)
    f.pays:Show()
end

function RUI:BuildPays(f)
    local m = f.m
    local t = m.theme
    local st = f.state
    local p = f.pays
    if not p then
        p = plate(f, { t.bg[1] * 0.8, t.bg[2] * 0.8, t.bg[3] * 0.8, 0.98 }, t.border, 2)
        p:SetPoint("TOPLEFT", f, "TOPRIGHT", 4, 0)
        p:SetSize(330, f:GetHeight())
        p.rows = {}
        p.head = text(p, 16, "OUTLINE")
        p.head:SetPoint("TOP", 0, -10)
        p.head:SetTextColor(t.title[1], t.title[2], t.title[3])
        p.note = text(p, 10, "")
        p.note:SetPoint("TOP", p.head, "BOTTOM", 0, -4)
        p.note:SetTextColor(0.8, 0.8, 0.8)
        p.rules = text(p, 10, "")
        p.rules:SetWidth(310)
        p.rules:SetJustifyH("LEFT")
        p.rules:SetTextColor(0.9, 0.9, 0.9)
        f.pays = p
    end
    for _, r in ipairs(p.rows) do r:Hide() end

    local coin = st.coin
    local R = Engine()
    local cost = R:CostCoins(m, st.level) * coin
    p.head:SetText("PAYS")
    p.note:SetText(("at your bet: %s credits a spin (coin %s)"):format(fmtBig(cost), fmtBig(coin)))

    local entries = {}
    local function credits(units) return fmtShort(math.floor(units + 0.5)) end
    if m.id == "darkmoon" then
        local c = st.level
        local P = m.pays
        local function per(v) return credits(v * c * coin) end
        entries = {
            { "dd", "3 x DD = " .. credits(P.ddThree[c] * coin) },
            { "seven", "3 x 7 = " .. per(P.seven) },
            { "bar3", "3 x triple BAR = " .. per(P.bar3) },
            { "bar2", "3 x double BAR = " .. per(P.bar2) },
            { "bar1", "3 x BAR = " .. per(P.bar1) .. "   any BARs = " .. per(P.anybar) },
            { "cherry", "3 = " .. per(P.cherry[3]) .. "  2 = " .. per(P.cherry[2]) .. "  1 = " .. per(P.cherry[1]) },
            { "dd", "two DD = " .. per(P.ddTwo) .. "   one DD = " .. per(P.ddOne) },
            { "spin", c == 3 and "SPIN: wheel pays 25 - 1000 x coin" or "SPIN: needs 3 coins!" },
        }
    elseif m.id == "bonanza" then
        for _, s in ipairs(m.symbols) do
            local pt = m.pays[s.id]
            if pt then
                entries[#entries + 1] = { s.id, ("12+ %s   10+ %s   8+ %s"):format(
                    credits(pt[3] * cost), credits(pt[2] * cost), credits(pt[1] * cost)) }
            end
        end
        entries[#entries + 1] = { "idol", ("6 %s  5 %s  4 %s"):format(credits(100 * cost), credits(5 * cost), credits(3 * cost)) }
        entries[#entries + 1] = { "bomb", "free spins: x2 - x100, added up" }
    else
        local scale = m.levels and (m.levels[st.level] / 88) or 1
        for _, s in ipairs(m.symbols) do
            local pt = m.pays[s.id]
            if pt then
                local bits = {}
                for n = 5, 2, -1 do
                    if pt[n] then bits[#bits + 1] = n .. ": " .. credits(pt[n] * coin * scale) end
                end
                entries[#entries + 1] = { s.id, table.concat(bits, "   ") }
            end
        end
        if m.scatterPays then
            local bits = {}
            for n = 5, 2, -1 do
                if m.scatterPays[n] then bits[#bits + 1] = n .. ": " .. credits(m.scatterPays[n] * cost) end
            end
            entries[#entries + 1] = { m.scatter, table.concat(bits, "   ") }
        end
        if m.id == "jade" then
            for _, j in ipairs(m.jackpots) do
                entries[#entries + 1] = { false, ("|cff%02x%02x%02x%s|r  %s%s"):format(
                    math.floor(j.color[1] * 255), math.floor(j.color[2] * 255),
                    math.floor(j.color[3] * 255), j.label,
                    fmtShort(j.coins * coin), st.level >= j.level and "" or "  (locked)") }
            end
        end
    end

    local y = -44
    local rowH = (m.id == "bonanza") and 26 or 28
    for i, e in ipairs(entries) do
        local row = p.rows[i]
        if not row then
            row = CreateFrame("Frame", nil, p)
            row:SetSize(310, rowH)
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(rowH - 4, rowH - 4)
            row.icon:SetPoint("LEFT", 0, 0)
            row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            row.glyph = text(row, 12, "THICKOUTLINE")
            row.glyph:SetPoint("CENTER", row.icon, "CENTER")
            row.fs = text(row, 11, "")
            row.fs:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
            p.rows[i] = row
        end
        row:SetPoint("TOPLEFT", 10, y)
        local s = e[1] and m.symbolById[e[1]]
        if s and s.icon and hasIcon(s.icon) then
            row.icon:SetTexture(s.icon); row.icon:Show(); row.glyph:SetText("")
        else
            row.icon:Hide()
            local g = s and (s.glyph or ""):gsub("\n", " ") or ""
            row.glyph:SetText(g)
            if s then row.glyph:SetTextColor(s.color[1], s.color[2], s.color[3]) end
            if m.theme.lightReels and s then row.glyph:SetTextColor(1, 1, 1) end
            if s and s.id == "seven" then row.glyph:SetTextColor(1, 0.2, 0.2) end
        end
        row.fs:SetText(e[2])
        row:Show()
        y = y - rowH
    end
    p.rules:ClearAllPoints()
    p.rules:SetPoint("TOPLEFT", 10, y - 8)
    p.rules:SetText("- " .. table.concat(RULES[m.id] or {}, "\n- "))
end

--[[ ----- display ----- ]]

-- The balance as the cabinet shows it: the engine has already paid the
-- whole spin, so hold back what the reels haven't revealed yet, and let a
-- rolling win count up into CREDIT alongside the WIN meter.
function RUI:ShownCredits(f)
    local st = f.state
    local held = st.pending or 0
    if f.roll then held = held + math.max(0, f.roll.to - (st.shownWin or 0)) end
    return BJ.Arcade:GetCredits() - held
end

function RUI:UpdateDisplay(f)
    f = f or self.frame
    if not f then
        return
    end
    local m = f.m
    local st = f.state
    local R = Engine()
    local cost = self:Cost(f)
    f.creditFS:SetText("|cffffe100CREDIT|r " .. fmtBig(self:ShownCredits(f)))
    f.betFS:SetText("|cffffe100BET|r " .. fmtBig(cost))
    if not f.roll then
        f.winFS:SetText("|cffffe100WIN|r " .. fmtBig(st.shownWin or 0))
    end
    f.coinVal:SetText(fmtShort(st.coin))
    f.coinSub:SetText(("%d coins a spin"):format(R:CostCoins(m, st.level)))
    if f.lvlVal then
        if m.id == "jade" then
            f.lvlVal:SetText(string.rep("|cffffd700o|r", st.level) .. string.rep("|cff555555o|r", 5 - st.level))
            f.lvlSub:SetText(("%d-coin bet"):format(m.levels[st.level]))
        else
            f.lvlVal:SetText(st.level .. " / " .. m.maxCoins)
            f.lvlSub:SetText(st.level == m.maxCoins and "|cff66ff66wheel is live|r" or "|cffff6666no wheel|r")
        end
    end
    if f.mqText and m.id == "darkmoon" then
        f.mqText:SetText(st.level == m.maxCoins
            and "DOUBLE DIAMOND WILDS x2 / x4  -  WHEEL LIVE: 25 TO 1000 x COIN"
            or "DOUBLE DIAMOND WILDS x2 / x4  -  |cffff6666PLAY 3 COINS TO LIGHT THE WHEEL|r")
    end
    if f.jpPlates then
        for _, pl in pairs(f.jpPlates) do
            local on = st.level >= pl.j.level
            pl.value:SetText(fmtShort(pl.j.coins * st.coin))
            pl:SetAlpha(on and 1 or 0.35)
        end
    end

    local busy = st.busy
    for _, k in ipairs({ "coinDown", "coinUp", "lvlDown", "lvlUp", "maxBtn" }) do
        if f[k] then f[k]:SetEnabled(not busy) end
    end
    if BJ.Arcade:GetCredits() < 1 and not busy then
        f.spinBtn.label:SetText("COMP ME")
        f.spinBtn:SetEnabled(true)
    else
        f.spinBtn.label:SetText("SPIN")
        f.spinBtn:SetEnabled(not busy and BJ.Arcade:GetCredits() >= cost)
    end
    if (st.autoLeft or 0) > 0 then
        f.autoBtn.label:SetText("STOP " .. st.autoLeft)
        f.autoBtn.fill = { 0.1, 0.5, 0.15 }
    else
        f.autoBtn.label:SetText("AUTO x" .. (st.autoSize or 10))
        f.autoBtn.fill = nil
    end
    f.autoBtn:paint()
    if f.pays and f.pays:IsShown() then self:BuildPays(f) end
end

function RUI:ShowMachine(id)
    local m = Engine().byId[id]
    if not m then return end
    local f = self.frames[id] or self:Build(m)
    Floor:Hide()
    for _, other in pairs(self.frames) do
        if other ~= f then other:Hide() end
    end
    f:Show()
end

--[[ =================== the Slot Floor =================== ]]

-- The house machine (Azeroth Riches) keeps its own window; the rest are
-- engine machines.
local HOUSE = {
    id = "azeroth", title = "Azeroth Riches", tagline = "THE HOUSE MACHINE - PROGRESSIVE JACKPOTS",
    icon = TEX .. "Arcade\\emerald",
    theme = { bg = { 0.12, 0.05, 0.16 }, bg2 = { 0.35, 0.12, 0.45 }, border = { 0.95, 0.75, 0.25 },
              title = { 1, 0.85, 0.3 }, accent = { 0.4, 1, 0.5 } },
}

function Floor:Build()
    local W, H = 760, 470
    local f = CreateFrame("Frame", "ChairfacesCasinoSlotFloor", UIParent, "BackdropTemplate")
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
    f:SetBackdropColor(0.04, 0.03, 0.06, 0.98)
    f:SetBackdropBorderColor(0.95, 0.8, 0.3, 1)
    f:Hide()
    self.frame = f

    -- carpet: a subtle diagonal check
    for i = 0, 18 do
        local tx = f:CreateTexture(nil, "BACKGROUND", nil, 1)
        tx:SetSize(40, H - 6)
        tx:SetPoint("TOPLEFT", 3 + i * 42, -3)
        tx:SetColorTexture(0.35, 0.05, 0.1, (i % 2 == 0) and 0.12 or 0.05)
    end

    local title = text(f, 28, "THICKOUTLINE")
    title:SetPoint("TOP", 0, -14)
    title:SetText("THE SLOT FLOOR")
    title:SetTextColor(1, 0.85, 0.3)
    local sub = text(f, 11, "")
    sub:SetPoint("TOP", title, "BOTTOM", 0, -4)
    sub:SetText("Six machines, one bankroll. Pick a cabinet and pull.")
    sub:SetTextColor(0.8, 0.8, 0.8)

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function()
        f:Hide()
        if UI.Lobby then UI.Lobby:Show() end
    end)

    local credit = plate(f, { 0, 0, 0, 0.85 }, { 0.95, 0.8, 0.3, 1 })
    credit:SetSize(260, 28)
    credit:SetPoint("BOTTOM", 0, 12)
    self.creditFS = text(credit, 15, "OUTLINE")
    self.creditFS:SetPoint("CENTER")

    local list = { HOUSE }
    for _, m in ipairs(Engine().machines) do list[#list + 1] = m end
    self.tiles = {}
    local TW, TH = 234, 170
    local gx = (W - 3 * TW) / 4
    for i, m in ipairs(list) do
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

        -- the cabinet's headline symbol
        local iconPath = m.icon
        if not iconPath then
            for _, s in ipairs(m.symbols) do
                if s.icon and hasIcon(s.icon) then iconPath = s.icon break end
            end
        end
        local ic = tile:CreateTexture(nil, "ARTWORK")
        ic:SetSize(48, 48)
        ic:SetPoint("TOPLEFT", 8, -7)
        ic:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        if iconPath then ic:SetTexture(iconPath) end

        local name = text(tile, 16, "OUTLINE")
        name:SetPoint("TOPLEFT", ic, "TOPRIGHT", 8, -4)
        name:SetPoint("RIGHT", tile, "RIGHT", -6, 0)
        name:SetJustifyH("LEFT")
        name:SetText(m.title)
        name:SetTextColor(t.title[1], t.title[2], t.title[3])

        local tag = text(tile, 10, "OUTLINE")
        tag:SetPoint("TOP", tile, "TOP", 0, -68)
        tag:SetWidth(TW - 16)
        tag:SetText(m.tagline)
        tag:SetTextColor(t.accent[1], t.accent[2], t.accent[3])

        local info = text(tile, 10, "")
        info:SetPoint("BOTTOMLEFT", 10, 30)
        info:SetJustifyH("LEFT")
        info:SetTextColor(0.85, 0.85, 0.85)
        tile.info = info

        local play = makeButton(tile, TW - 20, 22, "PLAY", t, 12)
        play:SetPoint("BOTTOM", 0, 6)
        play:EnableMouse(false)   -- the whole tile is the button

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
            if m.id == "azeroth" then
                f:Hide()
                if UI.Slots then UI.Slots:Show() end
            else
                RUI:ShowMachine(m.id)
            end
        end)
        self.tiles[i] = tile
    end

    if BJ.EscapeHandler then BJ.EscapeHandler:RegisterFrame("ChairfacesCasinoSlotFloor") end
    f:SetScript("OnShow", function() Floor:UpdateDisplay() end)
end

function Floor:UpdateDisplay()
    if not self.frame then return end
    self.creditFS:SetText("|cffffe100CREDITS|r " .. fmtBig(BJ.Arcade:GetCredits()))
    local R = Engine()
    for _, tile in ipairs(self.tiles) do
        local m = tile.m
        if m.id == "azeroth" then
            local db = BJ.Arcade:GetDB()
            tile.info:SetText("9 lines, hold & spin, 5 jackpots\nbest win: " .. fmtBig(db.bestSlotsWin or 0))
        else
            local st = R:GetStats(m.id)
            local minCost = R:CostCoins(m, 1)
            local fmtLine = ({
                kodo = "5x4  1024 ways",
                pharaoh = "5x3  20 lines",
                darkmoon = "3 reels  1 line",
                jade = "5x3  243 ways",
                bonanza = "6x5  pay anywhere",
            })[m.id] or ""
            tile.info:SetText(("%s   from %d a spin\nbest win: %s"):format(
                fmtLine, minCost, fmtBig(st.best or 0)))
        end
    end
end

function Floor:Show()
    if not self.frame then self:Build() end
    for _, mf in pairs(RUI.frames) do mf:Hide() end
    self.frame:Show()
end

function Floor:Hide()
    if self.frame then self.frame:Hide() end
end

-- Credit changes from outside (gifts, grants, comps) refresh whatever's open.
function RUI:RefreshAll()
    if Floor.frame and Floor.frame:IsShown() then Floor:UpdateDisplay() end
    if self.frame and self.frame:IsShown() then self:UpdateDisplay(self.frame) end
end
