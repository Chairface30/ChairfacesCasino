--[[
    Chairface's Casino - UI/CrashFrame.lua
    Crash: a goblin zeppelin sputters across the sky and WILL explode.
    Everyone antes into the pot; the last rider to parachute out before
    the blast takes it all. A game of chicken at cruising altitude.

    The zeppelin, parachutes and explosion are drawn from stock textures
    (circle mask + flat rects) so they render on every client version.
]]

local BJ = ChairfacesCasino
local UI = BJ.UI

UI.Crash = {}
local CF = UI.Crash

local FRAME_W = 620
local FRAME_H = 560

local SKY_H = 270
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local FLAT = "Interface\\Buttons\\WHITE8x8"

-- The flying ship renders from Textures\zeppelin.tga, a pre-rendered
-- sprite sheet of the real transport zeppelin m2 (which can't be shown
-- in a Model frame - it hard-crashes the client - nor shipped as an m2).
-- Set false to fall back to the old hand-drawn stock-texture ship, or
-- audition a new sheet live with /cc zep skin <frames> <fps>.
local ZEP_SKIN_ENABLED = true

-- Sheet geometry (same pattern as the lobby logo): frames stacked
-- vertically in one tall TGA, frame 0 at the top, built by
-- tools\build_zep_sheet.py from Blender renders (tools\zep_render.py).
-- 10 frames = one full propeller revolution; 18 fps matches the m2
-- animation's true prop speed. FRAMES = 1 would mean a static image.
local ZEP_SKIN_FRAMES = 10
local ZEP_SKIN_FPS = 18

-- Same idea for the mooring tower: Textures\tower.tga (pre-rendered
-- retail zeppelin tower, trimmed to content) replaces the hand-drawn
-- mast. Static image, sky-height tall. Toggle preview: /cc zep tower.
local TOWER_SKIN_ENABLED = true
local TOWER_SKIN_ASPECT = 160 / 413   -- trimmed tower.tga width/height

-- Blizzard's own effect models replace the hand-drawn circle FX: the
-- exhaust burns with the classic looping immolation flame and the crash
-- pops the vanilla goblin-bomb blast. Spell-effect m2s are safe in Model
-- frames (it was the transport WMO doodad that hard-crashed the client,
-- never these - the derby's creature models are equally fine), and both
-- IDs are vanilla-era so every supported client has them. Set an ID to 0
-- to fall back to the stock-texture circles.
-- 0: the m2 effects composite poorly against the painted sky, so fire
-- and smoke are drawn with upgraded stock-texture effects instead (a
-- flickering star-burst flame cluster and a long transparent puff
-- trail). Audition model alternatives with /cc zep fire|smoke <fileID>.
local FIRE_MODEL_FILEID = 0
local SMOKE_MODEL_FILEID = 0

-- 0: the m2 blasts read as pasted-on squares against the night sky (no
-- clean transparency), so the crash keeps the original hand-drawn burst.
-- Audition candidates anytime with /cc zep boom <fileID>.
local BOOM_MODEL_FILEID = 0

-- The doomed-flight staging: she flies clean off the tower, CATCHES FIRE
-- at this many meters out, and the smoke billows in just behind.
local FIRE_AT_METERS = 50
local SMOKE_AT_METERS = 70

-- The bail-out: a real goblin under a real parachute. The jumper loads
-- by DISPLAY id: SetDisplayInfo is pure client data, so he arrives with
-- his skin. (SetCreature needs the server's creature cache - an empty
-- model when that NPC was never seen this session, which is why NPC ids
-- like 641/3391 showed nothing - and a raw m2 load has no skin at all:
-- that was the white mannequin.) 1140 = classic goblin male, straight
-- from the era build's CreatureDisplayInfo (1233/1302/1412 also work).
local GOBLIN_DISPLAY_ID = 1140
local GOBLIN_MODEL_FILEID = 124224 -- creature/goblin/goblin.m2 (bare fallback)
local CHUTE_MODEL_FILEID = 166633  -- spells/parachute.m2

-- Load an effect m2 into a model frame; returns ok, reason. Tries the
-- modern fileID API first, then legacy SetModel (which also accepts
-- fileIDs on some builds). /cc zep fx reports every load result, and
-- /cc zep fire|smoke|boom <fileID> auditions alternatives live.
local function applyEffectModel(frame, fileID)
    if not fileID or fileID <= 0 then return false, "disabled (id 0)" end
    if frame.ClearModel then pcall(frame.ClearModel, frame) end
    if frame.SetModelByFileID then
        local ok, err = pcall(frame.SetModelByFileID, frame, fileID)
        if ok then return true end
        if frame.SetModel and pcall(frame.SetModel, frame, fileID) then
            return true
        end
        return false, "rejected: " .. tostring(err)
    end
    if frame.SetModel then
        local ok, err = pcall(frame.SetModel, frame, fileID)
        if ok then return true end
        return false, "rejected: " .. tostring(err)
    end
    return false, "no fileID model API on this client"
end

-- The Tirisfal forest: pre-rendered trees (Textures\tree1..tree7.tga
-- plus the leafy tree.tga, all trimmed to content; aspect = trimmed
-- width/height so they keep their proportions at any planted height).
local TREES = {
    { file = "tree1", aspect = 228 / 177 },   -- old logged stump
    { file = "tree2", aspect = 157 / 362 },   -- needle pine
    { file = "tree3", aspect = 156 / 360 },   -- needle pine, fuller
    { file = "tree4", aspect = 198 / 372 },   -- broad pine
    { file = "tree5", aspect = 199 / 364 },   -- broad pine, darker
    { file = "tree6", aspect = 160 / 358 },   -- thin pine
    { file = "tree7", aspect = 115 / 362 },   -- dead spindle
    { file = "tree",  aspect = 152 / 239 },   -- lone leafy oak
}

-- One authored track, laid out once - no wrapping, no randomness: every
-- flight passes the same forest. { trackX, TREES index, height, mirror };
-- trackX is world pixels from the tower (WORLD_LEN 4800 = the x100 cap,
-- plus a screen's width of runoff). The forest runs behind the tower at
-- the dock (the tower frame layers above it), then: forest edge ->
-- dense heart -> logged clearing (stumps) -> second stand -> thinning ->
-- dead spindles on the approach to the cap.
local FOREST = {
    -- around the tower and the dock
    { -30, 3,  92 }, { 30, 2, 104, true }, { 95, 5,  88 }, { 150, 6, 96 },
    { 215, 4,  84, true }, { 270, 2, 100 }, { 320, 7, 78 },
    -- the forest edge
    { 380, 7,  74 }, { 430, 2,  88, true }, { 455, 8,  56 }, { 505, 1, 22 },
    { 545, 3,  96 },
    -- deepening
    { 620, 6,  84 }, { 665, 2, 102, true }, { 700, 1,  20 }, { 738, 4, 78 },
    { 800, 5,  90 }, { 860, 7,  70, true }, { 915, 3, 108 }, { 960, 2, 86 },
    -- the dense heart
    { 1050, 4,  96 }, { 1085, 2, 110, true }, { 1120, 6,  88 },
    { 1170, 3, 104 }, { 1205, 7,  78, true }, { 1240, 5,  98 },
    { 1300, 2, 116 }, { 1335, 1,  24 },       { 1360, 6,  92, true },
    { 1410, 3,  88 }, { 1455, 4, 106 },       { 1500, 2,  94, true },
    { 1540, 7,  82 }, { 1580, 5, 112 },       { 1640, 6,  86 },
    { 1685, 3,  98, true }, { 1730, 2, 90 },  { 1780, 4,  84 },
    { 1830, 7, 104, true }, { 1870, 1, 18 },  { 1895, 5,  88 },
    -- a logged clearing: mostly stumps
    { 2010, 1, 26 }, { 2130, 1, 20, true }, { 2260, 7, 64 }, { 2320, 1, 24 },
    -- second stand
    { 2410, 2,  98 }, { 2450, 3,  86, true }, { 2520, 5, 104 },
    { 2590, 6,  78 }, { 2640, 8,  60 },       { 2700, 2, 112, true },
    { 2760, 4,  92 }, { 2830, 7,  86 },       { 2900, 3, 100, true },
    { 2950, 1,  22 }, { 2990, 5,  84 },       { 3060, 2, 106 },
    { 3130, 6,  94, true }, { 3200, 4, 80 },  { 3260, 7,  72 },
    -- thinning out
    { 3420, 3, 90 }, { 3540, 1, 20 }, { 3650, 7, 76, true },
    { 3790, 2, 88 }, { 3920, 6, 70 }, { 4080, 7, 60, true }, { 4180, 1, 18 },
    -- dead spindles on the run to the cap
    { 4350, 7, 84 }, { 4600, 7, 68, true }, { 4850, 7, 92 },
    { 5100, 7, 74, true }, { 5230, 1, 22 },
}

-- The zeppelin docks at a mooring tower and flies a level course from it:
-- altitude never changes, only distance (plus the nervous sputter).
-- THE knobs for micro-adjusting the docked ship: her bottom-left corner
-- in pixels from the sky's bottom-left. DOCK_X -65 centers the 220px
-- ship on the tower's centerline (~x45, tail clipped by the sky edge);
-- DOCK_Y is the cruising altitude the whole flight holds.
local DOCK_X = -40
local DOCK_Y = 96

-- The odometer: the flight reads as distance, not a multiplier
-- (0m at the tower, 1000m = the cap where she blows without fail)
local function metersFor(mult)
    return BJ.CrashState:MetersFor(mult)
end

function CF:Initialize()
    if self.frame then return end
    self:CreateFrame()
end

function CF:Show()
    self:Initialize()
    self.frame:Show()
    self:UpdateDisplay()
end

function CF:Hide()
    if self.frame then self.frame:Hide() end
end

function CF:CreateFrame()
    local frame = CreateFrame("Frame", "ChairfacesCasinoCrash", UIParent, "BackdropTemplate")
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
        bgFile = FLAT,
        edgeFile = FLAT,
        edgeSize = 2,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    frame:SetBackdropColor(0.07, 0.08, 0.12, 0.97)
    frame:SetBackdropBorderColor(0.6, 0.45, 0.2, 1)
    frame:Hide()
    frame:SetScript("OnHide", function() CF:StopEngine() end)
    self.frame = frame

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("|cffffd700Crash|r")
    title:SetFont("Fonts\\FRIZQT__.TTF", 18, "OUTLINE")

    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function()
        CF:Hide()
        if UI.Lobby then UI.Lobby:Show() end
    end)

    -- Debts shortcut (settle-up ledger) next to the close button
    if UI.Debts and UI.Debts.AttachDebtsIcon then
        UI.Debts:AttachDebtsIcon(frame, "RIGHT", closeBtn, "LEFT", -2, 0)
    end

    if UI.Lobby and UI.Lobby.AttachHowToPlayButton then
        UI.Lobby:AttachHowToPlayButton(frame, "crash", 8, -8)
    end

    -- Flight log (last five flights, riders and all)
    local logBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    logBtn:SetSize(80, 20)
    logBtn:SetPoint("TOPLEFT", 102, -8)
    logBtn:SetText("Flight Log")
    logBtn:SetFrameLevel(frame:GetFrameLevel() + 20)
    logBtn:SetScript("OnClick", function() CF:ToggleLog() end)
    if UI.Lobby and UI.Lobby.AttachTrixie then
        UI.Lobby:AttachTrixie(frame, "crash")
    end

    -- Recent crash points marquee
    local marquee = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    marquee:SetPoint("TOP", title, "BOTTOM", 0, -4)
    marquee:SetText("")
    self.marquee = marquee

    -- ==================== THE SKY ====================
    local sky = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    sky:SetSize(FRAME_W - 32, SKY_H)
    sky:SetPoint("TOP", 0, -56)
    sky:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
    sky:SetBackdropColor(0.05, 0.09, 0.20, 1)
    sky:SetBackdropBorderColor(0.35, 0.35, 0.5, 1)
    sky:SetClipsChildren(true)
    self.sky = sky

    -- a few stars
    for i = 1, 14 do
        local star = sky:CreateTexture(nil, "BACKGROUND", nil, 1)
        star:SetSize(2, 2)
        star:SetTexture(FLAT)
        star:SetVertexColor(1, 1, 1, 0.25 + (i % 4) * 0.1)
        star:SetPoint("BOTTOMLEFT", (i * 83) % (FRAME_W - 40), 30 + (i * 47) % (SKY_H - 50))
    end

    -- the ground / dirt strip rides its own frame ABOVE the mountain layer,
    -- so the sunken mountain circles disappear behind the horizon
    local groundFrame = CreateFrame("Frame", nil, sky)
    groundFrame:SetAllPoints()
    groundFrame:SetFrameLevel(sky:GetFrameLevel() + 2)
    local ground = groundFrame:CreateTexture(nil, "BACKGROUND", nil, 2)
    ground:SetPoint("BOTTOMLEFT", 0, 0)
    ground:SetPoint("BOTTOMRIGHT", 0, 0)
    ground:SetHeight(14)
    ground:SetTexture(FLAT)
    ground:SetVertexColor(0.18, 0.14, 0.08, 1)

    -- The world scrolls sidescroller-style once the ship reaches centre
    -- screen, so every piece of scenery is movable. The mooring tower is
    -- unique (it scrolls away and never comes back); hills and trees wrap
    -- around on parallax layers to sell the distance.

    -- the mooring tower the zeppelin departs from: a mast up from the
    -- ground with crossbeams and a docking arm at the top
    local tower = CreateFrame("Frame", nil, sky)
    tower:SetSize(44, DOCK_Y + 50)
    tower:SetPoint("BOTTOMLEFT", 0, 0)
    self.tower = tower

    tower.art = {}   -- hand-drawn parts, for the tower-skin hide/restore
    local mast = tower:CreateTexture(nil, "BACKGROUND", nil, 3)
    mast:SetSize(7, DOCK_Y + 26)
    mast:SetPoint("BOTTOMLEFT", 18, 14)
    mast:SetTexture(FLAT)
    mast:SetVertexColor(0.35, 0.28, 0.16, 1)
    table.insert(tower.art, mast)
    for i = 1, 4 do
        local beam = tower:CreateTexture(nil, "BACKGROUND", nil, 3)
        beam:SetSize(21, 3)
        beam:SetPoint("BOTTOMLEFT", 11, 14 + i * 24)
        beam:SetTexture(FLAT)
        beam:SetVertexColor(0.30, 0.24, 0.13, 1)
        table.insert(tower.art, beam)
    end
    local dockArm = tower:CreateTexture(nil, "BACKGROUND", nil, 3)
    dockArm:SetSize(20, 4)
    dockArm:SetPoint("BOTTOMLEFT", 22, DOCK_Y + 34)
    dockArm:SetTexture(FLAT)
    dockArm:SetVertexColor(0.42, 0.34, 0.2, 1)
    table.insert(tower.art, dockArm)
    local beacon = tower:CreateTexture(nil, "BACKGROUND", nil, 4)
    beacon:SetSize(5, 5)
    beacon:SetPoint("BOTTOMLEFT", 19, DOCK_Y + 40)
    beacon:SetTexture(CIRCLE)
    beacon:SetVertexColor(1, 0.3, 0.2, 0.9)
    table.insert(tower.art, beacon)

    -- Pre-rendered tower skin (see the zeppelin skin below): the full
    -- height of the sky at the render's own aspect, feet on the ground.
    -- Anchored to the frame's LEFT edge so nothing pokes past the sky's
    -- left border at the dock (the sky clips children).
    local towerSkin = tower:CreateTexture(nil, "BACKGROUND", nil, 3)
    local towerH = SKY_H - 16
    towerSkin:SetSize(towerH * TOWER_SKIN_ASPECT, towerH)
    towerSkin:SetPoint("BOTTOMLEFT", tower, "BOTTOMLEFT", 0, 8)
    towerSkin:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\Crash\\tower")
    towerSkin:Hide()
    tower.skin = towerSkin
    if TOWER_SKIN_ENABLED then
        towerSkin:Show()
        for _, tex in ipairs(tower.art) do tex:Hide() end
    end

    -- parallax scenery: far rounded mountains (slow) and near trees (full
    -- speed), spread over a wrap strip a bit wider than the sky
    self.scenery = {}
    local stripLen = (FRAME_W - 32) + 200
    -- craggy snowcapped mountain range: a pre-generated tileable strip
    -- (Textures\mountains.tga, from tools\make_mountains.py) standing
    -- ~3/4 of the sky so the peaks clear the tree line. Two copies
    -- leapfrog by tile-width so the range never shows a break.
    local MTN_W, MTN_H = 788, 200
    for i = 0, 1 do
        local mtn = CreateFrame("Frame", nil, sky)
        mtn:SetSize(MTN_W, MTN_H)
        mtn:SetFrameLevel(sky:GetFrameLevel() + 1)   -- behind everything
        local tex = mtn:CreateTexture(nil, "BACKGROUND", nil, 2)
        tex:SetAllPoints()
        tex:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\Crash\\mountains")
        table.insert(self.scenery, {
            holder = mtn, speed = 0.35, tile = MTN_W,
            baseX = i * MTN_W, y = 8,
        })
    end
    -- the deep-forest wall: an extremely dense parallax band between the
    -- mountains and the front trees. Bigger than the front trees, heavily
    -- overlapped so there is never a gap, dimmed for distance haze, and
    -- wrapping so it runs unbroken across the entire flight
    local WALL_TYPES = { 2, 3, 4, 5, 6 }   -- the tall pines
    for i = 1, math.ceil(stripLen / 36) do
        local kind = TREES[WALL_TYPES[(i % #WALL_TYPES) + 1]]
        local th = 120 + (i * 37) % 50
        local tree = CreateFrame("Frame", nil, sky)
        tree:SetSize(th * kind.aspect, th)
        tree:SetFrameLevel(sky:GetFrameLevel() + 3)   -- behind the forest
        local tex = tree:CreateTexture(nil, "BACKGROUND", nil, 4)
        tex:SetAllPoints()
        tex:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\Crash\\" .. kind.file)
        if i % 2 == 0 then
            tex:SetTexCoord(1, 0, 0, 1)
        end
        tex:SetVertexColor(0.45, 0.50, 0.55, 1)   -- hazed with distance
        table.insert(self.scenery, {
            holder = tree, speed = 0.6, wrap = true,
            baseX = (i - 1) * 36, y = 14,
        })
    end

    -- the Tirisfal forest: fixed authored positions, scrolls past once
    -- (LayoutWorld places these absolutely; the hills and the deep wall wrap)
    for _, def in ipairs(FOREST) do
        local kind = TREES[def[2]]
        local th = def[3]
        local tw = th * kind.aspect
        local tree = CreateFrame("Frame", nil, sky)
        tree:SetSize(tw, th)
        tree:SetFrameLevel(sky:GetFrameLevel() + 4)   -- standing on the dirt,
                                                      -- behind the tower
        local tex = tree:CreateTexture(nil, "BACKGROUND", nil, 5)
        tex:SetAllPoints()
        tex:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\Crash\\" .. kind.file)
        if def[4] then
            tex:SetTexCoord(1, 0, 0, 1)   -- mirrored for variety
        end
        table.insert(self.scenery, {
            holder = tree, speed = 1.0, baseX = def[1], y = 12, w = tw,
        })
    end

    -- HUD holder: the sky's text lives on its own high frame level so it
    -- always renders in front of the forest, the tower and the zeppelin
    -- (FontStrings on the sky itself would draw at the sky's own level,
    -- i.e. behind every child frame)
    local hud = CreateFrame("Frame", nil, sky)
    hud:SetAllPoints()
    hud:SetFrameLevel(sky:GetFrameLevel() + 10)
    self.hud = hud

    -- Big multiplier readout
    local mult = hud:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    mult:SetPoint("TOP", sky, "TOP", 0, -14)
    mult:SetFont("Fonts\\FRIZQT__.TTF", 40, "THICKOUTLINE")
    mult:SetText("")
    self.multText = mult

    -- live pot / riders-still-aboard readout under the odometer
    local bailNow = hud:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    bailNow:SetPoint("TOP", mult, "BOTTOM", 0, -2)
    bailNow:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE")
    bailNow:SetText("")
    self.bailNowText = bailNow

    -- Sky status line (boarding / rolling / crashed)
    local skyStatus = hud:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    skyStatus:SetPoint("CENTER", sky, "CENTER", 0, 10)
    skyStatus:SetFont("Fonts\\FRIZQT__.TTF", 17, "OUTLINE")
    skyStatus:SetText("")
    self.skyStatus = skyStatus

    -- ==================== THE ZEPPELIN ====================
    -- Hand-drawn from stock textures inside a holder so the whole ship
    -- moves as one. Deliberately NOT a Model frame: pointing one at the
    -- transport zeppelin m2 (a world doodad) hard-crashes the client with
    -- an access violation - do not reintroduce it.
    local zep = CreateFrame("Frame", nil, sky)
    zep:SetSize(220, 128)   -- 200% since the pre-rendered skin shipped;
                            -- the hand-drawn art below still lays out for
                            -- 110x64 and is debug-fallback only now
    zep:SetPoint("BOTTOMLEFT", DOCK_X, DOCK_Y)
    zep:SetFrameLevel(sky:GetFrameLevel() + 6)   -- above tower and scenery
    tower:SetFrameLevel(sky:GetFrameLevel() + 5) -- above the forest: trees
                                                 -- pass behind the tower
    self.zep = zep

    local balloon = zep:CreateTexture(nil, "ARTWORK", nil, 2)
    balloon:SetSize(96, 44)
    balloon:SetPoint("TOP", 0, -2)
    balloon:SetTexture(CIRCLE)
    balloon:SetVertexColor(0.45, 0.60, 0.35, 1)   -- goblin green

    local balloonShine = zep:CreateTexture(nil, "ARTWORK", nil, 3)
    balloonShine:SetSize(44, 14)
    balloonShine:SetPoint("TOP", -12, -8)
    balloonShine:SetTexture(CIRCLE)
    balloonShine:SetVertexColor(0.75, 0.85, 0.65, 0.5)

    local fin = zep:CreateTexture(nil, "ARTWORK", nil, 1)
    fin:SetSize(16, 22)
    fin:SetPoint("RIGHT", balloon, "LEFT", 14, 8)
    fin:SetTexture(FLAT)
    fin:SetVertexColor(0.65, 0.30, 0.15, 1)

    local strut1 = zep:CreateTexture(nil, "ARTWORK", nil, 1)
    strut1:SetSize(3, 10)
    strut1:SetPoint("TOP", balloon, "BOTTOM", -14, 3)
    strut1:SetTexture(FLAT)
    strut1:SetVertexColor(0.3, 0.25, 0.15, 1)

    local strut2 = zep:CreateTexture(nil, "ARTWORK", nil, 1)
    strut2:SetSize(3, 10)
    strut2:SetPoint("TOP", balloon, "BOTTOM", 14, 3)
    strut2:SetTexture(FLAT)
    strut2:SetVertexColor(0.3, 0.25, 0.15, 1)

    local gondola = zep:CreateTexture(nil, "ARTWORK", nil, 2)
    gondola:SetSize(38, 12)
    gondola:SetPoint("TOP", balloon, "BOTTOM", 0, -5)
    gondola:SetTexture(FLAT)
    gondola:SetVertexColor(0.5, 0.35, 0.18, 1)

    -- hand-drawn parts, so the /cc zep debug overlay can hide/restore them
    zep.art = { balloon, balloonShine, fin, strut1, strut2, gondola }

    -- Optional pre-rendered skin: a real m2 can't be shipped in an addon
    -- (models only load from the game archives), so the retail zeppelin is
    -- delivered as a pre-rendered RGBA image instead. Drop it in as
    -- Textures\zeppelin.tga (transparent background, nose pointing RIGHT —
    -- she flies left-to-right with the exhaust flame at her rear/left;
    -- non-power-of-two is fine, logo_frames.tga is 200x9040). Preview it
    -- live with /cc zep skin, then flip ZEP_SKIN_ENABLED at the top of
    -- this file to ship it. Missing file + enabled flag would render a
    -- solid box, so the flag stays false until the texture is actually in
    -- the folder. Multi-frame sheets animate via AnimateSkin below.
    local skin = zep:CreateTexture(nil, "ARTWORK", nil, 2)
    skin:SetAllPoints(zep)
    skin:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\Crash\\zeppelin")
    skin:Hide()
    zep.skin = skin
    self:SetSkinSheet(ZEP_SKIN_FRAMES, ZEP_SKIN_FPS)
    if ZEP_SKIN_ENABLED then
        skin:Show()
        for _, tex in ipairs(zep.art) do tex:Hide() end
    end

    -- The fire at the rear: a flickering cluster of star-burst tongues
    -- over a soft glow (shapes, not plain circles). Hidden at the dock;
    -- the flight driver lights it at FIRE_AT_METERS.
    local STAR = "Interface\\Cooldown\\star4"
    self.flameParts = {}
    local flameDefs = {
        { tex = CIRCLE, size = 30, x = 34, y = 14, r = 1.0, g = 0.30, b = 0.05, a = 0.30 }, -- glow
        { tex = STAR,   size = 34, x = 32, y = 14, r = 1.0, g = 0.45, b = 0.05, a = 0.90 }, -- orange tongue
        { tex = STAR,   size = 22, x = 40, y = 20, r = 1.0, g = 0.80, b = 0.25, a = 0.90 }, -- yellow heart
        { tex = STAR,   size = 13, x = 28, y = 10, r = 1.0, g = 0.95, b = 0.60, a = 0.95 }, -- white core
    }
    for _, d in ipairs(flameDefs) do
        local p = zep:CreateTexture(nil, "ARTWORK", nil, 4)
        p:SetTexture(d.tex)
        -- star4 has no alpha channel (white star on black, made for
        -- additive blending) - ADD folds the black away into glow
        p:SetBlendMode("ADD")
        p:SetSize(d.size, d.size)
        p:SetPoint("CENTER", zep, "LEFT", d.x, d.y)
        p:SetVertexColor(d.r, d.g, d.b, d.a)
        p:Hide()
        p.base = d
        table.insert(self.flameParts, p)
    end

    -- Blizzard's own looping flame at the exhaust plus a smoke billow
    -- right behind it, when the client can load fileID models. The
    -- circle flame / puff trail below stay as automatic fallbacks.
    self.fxStatus = {}
    local fireFrame = CreateFrame("PlayerModel", nil, zep)
    fireFrame:SetSize(64, 64)
    fireFrame:SetPoint("CENTER", zep, "LEFT", 30, 10)
    fireFrame:SetFrameLevel(zep:GetFrameLevel() + 1)
    fireFrame:Hide()
    self.fxFire = fireFrame
    local fok, fwhy = applyEffectModel(fireFrame, FIRE_MODEL_FILEID)
    self.fxStatus.fire = fok and ("ok (" .. FIRE_MODEL_FILEID .. ")") or fwhy
    self.zepFireModel = fok and fireFrame or nil

    local smokeFrame = CreateFrame("PlayerModel", nil, zep)
    smokeFrame:SetSize(90, 90)
    smokeFrame:SetPoint("CENTER", zep, "LEFT", 10, 34)
    smokeFrame:SetFrameLevel(zep:GetFrameLevel() + 1)
    smokeFrame:Hide()
    self.fxSmoke = smokeFrame
    local sok, swhy = applyEffectModel(smokeFrame, SMOKE_MODEL_FILEID)
    self.fxStatus.smoke = sok and ("ok (" .. SMOKE_MODEL_FILEID .. ")") or swhy
    self.zepSmokeModel = sok and smokeFrame or nil

    -- ==================== SMOKE TRAIL ====================
    -- Translucent grey puffs spawn thick at the tail while she burns,
    -- drifting a long way back as they swell and thin. They live on
    -- their own layer so the trail passes in FRONT of the forest but
    -- behind the ship.
    local smokeLayer = CreateFrame("Frame", nil, sky)
    smokeLayer:SetAllPoints()
    smokeLayer:SetFrameLevel(sky:GetFrameLevel() + 5)
    self.smokeLayer = smokeLayer
    self.smoke = {}
    self.smokePool = {}
    self.smokeClock = 0

    -- ==================== EXPLOSION ====================
    -- Two depth layers sell the blast in 3D: half the pieces burst
    -- BEHIND the ship (but over the forest - the old pieces lived on the
    -- sky itself, which drew them behind the trees), half in FRONT of
    -- her, faster and brighter because they're closer to the camera.
    local boomBack = CreateFrame("Frame", nil, sky)
    boomBack:SetAllPoints()
    boomBack:SetFrameLevel(sky:GetFrameLevel() + 5)   -- over trees, behind the ship
    local boomFront = CreateFrame("Frame", nil, sky)
    boomFront:SetAllPoints()
    boomFront:SetFrameLevel(sky:GetFrameLevel() + 8)  -- in front of the ship
    self.boomPieces = {}
    for i = 1, 36 do
        local front = (i % 2 == 0)
        local b = (front and boomFront or boomBack):CreateTexture(nil, "OVERLAY", nil, 5)
        b:SetTexture(CIRCLE)
        b:Hide()
        b.front = front
        self.boomPieces[i] = b
    end

    -- Blizzard's own goblin-bomb blast plays the crash when the client
    -- supports fileID models; the circle shrapnel above is the fallback
    local boomFrame = CreateFrame("PlayerModel", nil, sky)
    boomFrame:SetSize(320, 320)   -- roomy: a tight rect clips the blast
    boomFrame:SetFrameLevel(sky:GetFrameLevel() + 8)   -- over ship and tower
    boomFrame:Hide()
    self.fxBoom = boomFrame
    local bok, bwhy = applyEffectModel(boomFrame, BOOM_MODEL_FILEID)
    self.fxStatus = self.fxStatus or {}
    self.fxStatus.boom = bok and ("ok (" .. BOOM_MODEL_FILEID .. ")") or bwhy
    self.boomModel = bok and boomFrame or nil

    local crashedText = self.hud:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    crashedText:SetPoint("CENTER", sky, "CENTER", 0, 24)
    crashedText:SetFont("Fonts\\FRIZQT__.TTF", 34, "THICKOUTLINE")
    crashedText:SetTextColor(1, 0.15, 0.1)
    crashedText:SetText("")
    self.crashedText = crashedText

    -- ==================== PARACHUTES (bail-outs) ====================
    self.chutes = {}

    -- ==================== FLIGHT DRIVER ====================
    sky:SetScript("OnUpdate", function(_, dt) CF:OnSkyUpdate(dt) end)

    -- ==================== RIDERS PANEL ====================
    local riders = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    riders:SetSize(280, 168)
    riders:SetPoint("TOPLEFT", 16, -56 - SKY_H - 8)
    riders:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
    riders:SetBackdropColor(0.1, 0.1, 0.14, 1)
    riders:SetBackdropBorderColor(0.35, 0.35, 0.5, 1)

    local ridersTitle = riders:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ridersTitle:SetPoint("TOPLEFT", 8, -6)
    ridersTitle:SetText("|cffffd700Riders|r")
    self.ridersTitle = ridersTitle

    self.riderRows = {}
    for i = 1, 10 do
        local row = riders:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row:SetPoint("TOPLEFT", 8, -22 - (i - 1) * 14)
        row:SetPoint("RIGHT", riders, "RIGHT", -8, 0)
        row:SetJustifyH("LEFT")
        row:SetWordWrap(false)   -- long ledger lines truncate, never overlap
        row:SetText("")
        self.riderRows[i] = row
    end

    -- ==================== CONTROLS (right column) ====================
    local ctrl = CreateFrame("Frame", nil, frame)
    ctrl:SetSize(280, 196)   -- tall enough for status + board + LAUNCH + close
    ctrl:SetPoint("TOPRIGHT", -16, -56 - SKY_H - 8)
    self.ctrl = ctrl

    local status = ctrl:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    status:SetPoint("TOP", 0, 0)
    status:SetWidth(276)
    status:SetText("")
    self.statusText = status

    local function makeButton(w, h)
        local b = CreateFrame("Button", nil, ctrl, "BackdropTemplate")
        b:SetSize(w, h)
        b:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 2 })
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        b.text:SetPoint("CENTER")
        b:Hide()
        return b
    end
    local function styleButton(b, r, g, bl, textColor)
        b:SetBackdropColor(r, g, bl, 1)
        b:SetBackdropBorderColor(r + 0.2, g + 0.2, bl + 0.2, 1)
        b.text:SetTextColor(unpack(textColor or { 1, 1, 1 }))
    end

    local function makeEditBox(w)
        local e = CreateFrame("EditBox", nil, ctrl, "BackdropTemplate")
        e:SetSize(w, 22)
        e:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
        e:SetBackdropColor(0.15, 0.15, 0.2, 1)
        e:SetBackdropBorderColor(0.5, 0.5, 0.6, 1)
        e:SetFontObject(GameFontNormal)
        e:SetTextColor(1, 1, 1)
        e:SetJustifyH("CENTER")
        e:SetAutoFocus(false)
        e:SetMaxLetters(8)
        e:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
        e:SetScript("OnEnterPressed", function(s) s:ClearFocus() end)
        e:Hide()
        return e
    end

    -- Host: ante input + open table
    local anteLabel = ctrl:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    anteLabel:SetPoint("TOP", 0, -40)   -- clear of a two-line status text
    anteLabel:SetText("Ante per seat (gold):")
    self.anteLabel = anteLabel

    local anteBox = makeEditBox(90)
    anteBox:SetPoint("TOP", anteLabel, "BOTTOM", 0, -4)
    anteBox:SetNumeric(true)
    anteBox:SetText(tostring(BJ.HostSettings and BJ.HostSettings:Get("crashAnte") or 10))
    self.anteBox = anteBox

    local openBtn = makeButton(180, 30)
    openBtn:SetPoint("TOP", anteBox, "BOTTOM", 0, -8)
    styleButton(openBtn, 0.15, 0.35, 0.15)
    openBtn.text:SetText("|cff00ff00Open Table|r")
    openBtn:SetScript("OnClick", function()
        BJ.CrashMultiplayer:HostTable(self.anteBox:GetText())
    end)
    self.openBtn = openBtn

    -- Fake play (fun games record no debts) right where hosting starts;
    -- parented to the button so it shows and hides with it
    if BJ.UI.Debts and BJ.UI.Debts.AttachFakePlayCheck then
        BJ.UI.Debts:AttachFakePlayCheck(openBtn, "TOP", openBtn, "BOTTOM", -32, -4)
    end

    -- Rider: auto-jump distance + board. Typed in METERS; the wire still
    -- carries a multiplier, so convert at this edge only.
    local targetLabel = ctrl:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    targetLabel:SetPoint("TOP", 0, -40)   -- clear of a two-line status text
    targetLabel:SetText("Auto-jump at meters (optional, e.g. 450):")
    self.targetLabel = targetLabel

    local targetBox = makeEditBox(90)
    targetBox:SetPoint("TOP", targetLabel, "BOTTOM", 0, -4)
    targetBox:SetText("")
    self.targetBox = targetBox

    local function targetMult()
        local text = self.targetBox:GetText()
        if not text or text == "" then return nil end
        return BJ.CrashState:MultForMeters(text)
    end

    local boardBtn = makeButton(180, 30)
    boardBtn:SetPoint("TOP", targetBox, "BOTTOM", 0, -8)
    styleButton(boardBtn, 0.15, 0.35, 0.15)
    boardBtn:SetScript("OnClick", function()
        BJ.CrashMultiplayer:RequestJoin(targetMult())
    end)
    self.boardBtn = boardBtn

    local targetBtn = makeButton(180, 24)
    targetBtn:SetPoint("TOP", targetBox, "BOTTOM", 0, -8)
    styleButton(targetBtn, 0.2, 0.25, 0.4)
    targetBtn.text:SetText("Set Auto-Jump")
    targetBtn:SetScript("OnClick", function()
        BJ.CrashMultiplayer:SetTarget(targetMult())
    end)
    self.targetBtn = targetBtn

    -- Host: launch
    local launchBtn = makeButton(200, 40)
    launchBtn:SetPoint("TOP", 0, -34)
    styleButton(launchBtn, 0.55, 0.4, 0.05)
    launchBtn.text:SetText("|cffffffffLAUNCH!|r")
    launchBtn.text:SetFont("Fonts\\FRIZQT__.TTF", 18, "OUTLINE")
    launchBtn:SetScript("OnClick", function()
        BJ.CrashMultiplayer:Launch()
    end)
    self.launchBtn = launchBtn

    -- THE BUTTON
    local bailBtn = makeButton(230, 56)
    bailBtn:SetPoint("TOP", 0, -30)
    styleButton(bailBtn, 0.6, 0.1, 0.05)
    bailBtn.text:SetText("|cffffffffJUMP!|r")
    bailBtn.text:SetFont("Fonts\\FRIZQT__.TTF", 24, "THICKOUTLINE")
    bailBtn:SetScript("OnClick", function()
        BJ.CrashMultiplayer:CashOut()
    end)
    bailBtn:SetScript("OnEnter", function(b) b:SetBackdropColor(0.75, 0.15, 0.08, 1) end)
    bailBtn:SetScript("OnLeave", function(b) b:SetBackdropColor(0.6, 0.1, 0.05, 1) end)
    self.bailBtn = bailBtn

    -- Host: next round / close table
    local nextBtn = makeButton(180, 30)
    nextBtn:SetPoint("TOP", 0, -34)
    styleButton(nextBtn, 0.15, 0.35, 0.15)
    nextBtn.text:SetText("|cff00ff00Next Flight|r")
    nextBtn:SetScript("OnClick", function()
        BJ.CrashMultiplayer:NextRound()
    end)
    self.nextBtn = nextBtn

    local closeTableBtn = makeButton(180, 24)
    closeTableBtn:SetPoint("BOTTOM", 0, 4)
    styleButton(closeTableBtn, 0.35, 0.15, 0.15)
    closeTableBtn.text:SetText("|cffff8866Close Table|r")
    closeTableBtn:SetScript("OnClick", function()
        BJ.CrashMultiplayer:CloseTable()
    end)
    self.closeTableBtn = closeTableBtn

    -- Fairness note
    local fairness = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fairness:SetPoint("BOTTOM", 0, 10)
    fairness:SetText("|cff888888Provably fair: hash committed before a public /roll picks the fate; verified at the reveal.|r")

    if BJ.EscapeHandler then
        BJ.EscapeHandler:RegisterFrame("ChairfacesCasinoCrash")
    end

    self.chuteTimers = {}
end

--[[
    FLIGHT ANIMATION
]]

-- Distance flown (in world pixels) for a given multiplier: linear during
-- the x0->x1 climb-out, then log-scale so the pace stays steady as the
-- numbers run away. The camera pins the ship at centre screen and scrolls
-- the world past it, sidescroller style.
-- WORLD_LEN is sized against the log base below: base MAX_MULT (x100)
-- with 4800px runs the world at the same px/sec as the old base-10
-- normalization did - but the scroll now lasts all the way to the cap
-- instead of pinning the scenery still at x10.
local WORLD_LEN = 4800   -- world pixels from x0 to the x100 cap
local function flightDistance(mult)
    if not mult or mult <= 0 then return 0 end
    local p
    if mult <= 1 then
        p = 0.10 * mult
    else
        p = math.log(mult) / math.log(BJ.CrashState.MAX_MULT)
        if p > 1 then p = 1 end
        p = 0.10 + 0.90 * p
    end
    return p * WORLD_LEN
end

-- Slide the tower and the wrap scenery for a given scroll distance
function CF:LayoutWorld(scroll)
    self.curScroll = scroll   -- parachutes anchor to the world with this
    if self.tower then
        local tx = -scroll
        self.tower:ClearAllPoints()
        self.tower:SetPoint("BOTTOMLEFT", tx, 0)
        self.tower:SetShown(tx > -100)   -- the skin is ~90px wide
    end
    if not self.scenery then return end
    local skyW = self.sky:GetWidth()
    local stripLen = skyW + 200
    for _, s in ipairs(self.scenery) do
        local sx
        if s.tile then
            -- seamless tiled strip (mountains): two copies leapfrog by
            -- tile-width, so together they always cover the window
            sx = s.baseX - (scroll * s.speed) % s.tile
        elseif s.wrap then
            -- the deep-forest wall recycles around a wrap strip
            sx = (s.baseX - scroll * s.speed) % stripLen - 100
        else
            -- the forest is absolute: each tree scrolls past exactly once
            sx = s.baseX - scroll * s.speed
        end
        s.holder:ClearAllPoints()
        s.holder:SetPoint("BOTTOMLEFT", sx, s.y)
        if not (s.wrap or s.tile) then
            -- cull only the one-shot forest trees; tiled strips MUST stay
            -- shown while hanging far off the left edge - a tile piece at
            -- sx -400 still covers most of the window
            s.holder:SetShown(sx > -(s.w or 40) and sx < skyW)
        end
    end
end

function CF:OnSkyUpdate(dt)
    local CS = BJ.CrashState
    local CM = BJ.CrashMultiplayer

    -- explosion pieces, parachutes, lingering smoke and the fly-away
    -- animate in every phase; the skin's propellers only turn in flight
    -- (AnimateFlyAway spins them itself on the way out)
    self:AnimateBoom(dt)
    self:AnimateChutes(dt)
    self:AnimateSmoke(dt)
    self:AnimateFlyAway(dt)

    if CS.phase ~= CS.PHASE.FLIGHT then return end
    self:AnimateSkin(dt)

    -- snappier auto-bail + watchdog handling while the window is open
    if CM then
        CM:ApplyDueAutoCashouts()
        CM:CheckFlightWatchdog()
    end
    if CS.phase ~= CS.PHASE.FLIGHT then return end   -- watchdog may have voided

    local mult = CS:CurrentMultiplier()
    local meters = metersFor(mult)
    self.multText:SetText("|cffffd700" .. meters .. "m|r")

    -- climbing-high tension line: once per round when she crosses into the
    -- rarefied ~500m+ air where the hazard is steep (noFreq so it lands).
    if not self.crashHighSaid and meters >= 500 then
        self.crashHighSaid = true
        if BJ.UI and BJ.UI.Lobby then
            BJ.UI.Lobby:PlayTrixieVoice("crash_high", { noFreq = true })
        end
    end

    -- sidescroller camera: the ship flies from the tower to centre screen,
    -- then stays pinned there while the world scrolls past. There is no
    -- fly-away anymore: at the 1000m cap the host's CRASH lands within a
    -- tick and she blows right there on centre screen.
    -- The tick multiplier steps, so for MOTION we sample the same curve
    -- at the fractional tick instead: past the climb-out the growth
    -- exponent cancels against the log distance mapping, which makes the
    -- scroll speed exactly constant - uniform, perfectly smooth motion.
    -- (Payouts, the odometer and the crash still land on whole ticks.)
    local dist
    if CS.flightStart then
        local tick = (GetTime() - CS.flightStart) / CS.TICK_SECONDS
        if tick < 0 then tick = 0 end
        local m
        if tick < CS.RAMP_TICKS then
            m = tick / CS.RAMP_TICKS
        else
            m = CS.GROWTH ^ (tick - CS.RAMP_TICKS)
        end
        if m > CS.MAX_MULT then m = CS.MAX_MULT end
        dist = flightDistance(m)
    else
        dist = flightDistance(mult)
    end

    local centerX = (self.sky:GetWidth() - self.zep:GetWidth()) / 2
    local travel = centerX - DOCK_X
    local zepX
    if dist < travel then
        zepX = DOCK_X + dist
        self:LayoutWorld(0)
    else
        zepX = centerX
        self:LayoutWorld(dist - travel)
    end

    -- everyone's out: she breaks from the center pin and makes an
    -- accelerating run for the edge. The hidden crash can still catch
    -- her on screen - that's the close call everyone wants to see; the
    -- explosion FX land wherever she's reached when it fires.
    if CM and CM.CountAboard and #CS.playerOrder > 0
        and CM:CountAboard() == 0 then
        self.escapeT = (self.escapeT or 0) + dt
        zepX = zepX + 70 * self.escapeT * self.escapeT
    else
        self.escapeT = nil
    end

    -- the nervous sputter is vertical only: a little +/- Y bob
    local t = GetTime()
    local sputterY = math.sin(t * 7.7) * 3 + math.sin(t * 23.3) * 1.5
    self.zep:ClearAllPoints()
    self.zep:SetPoint("BOTTOMLEFT", zepX, DOCK_Y + sputterY)

    -- the doomed-flight staging: she lifts off clean, catches fire at
    -- FIRE_AT_METERS, and the smoke billows in just behind
    local burning = dist >= FIRE_AT_METERS * (WORLD_LEN / 1000)
    local smoking = dist >= SMOKE_AT_METERS * (WORLD_LEN / 1000)

    -- the fire: an audition model if one is set, plus the flickering
    -- star-burst cluster - every tongue jitters its own size, alpha and
    -- spin so the flame licks instead of pulsing
    if self.zepFireModel then
        self.zepFireModel:SetShown(burning)
    end
    if self.flameParts then
        for i, p in ipairs(self.flameParts) do
            p:SetShown(burning)
            if burning then
                local d = p.base
                local jit = 0.7 + 0.4 * math.abs(math.sin(t * (9 + i * 2.7) + i * 1.3))
                if math.random(70) == 1 then jit = 0.3 end   -- ...gutter
                p:SetSize(d.size * jit, d.size * jit)
                p:SetAlpha(d.a * (0.7 + 0.3 * jit))
                if p.SetRotation then
                    p:SetRotation(math.sin(t * (4 + i)) * 0.6 + i)
                end
            end
        end
    end

    -- smoke off the back: an audition model if set, else the puff trail
    if self.zepSmokeModel then
        self.zepSmokeModel:SetShown(smoking)
    elseif smoking then
        self.smokeClock = (self.smokeClock or 0) + dt
        if self.smokeClock >= 0.05 then   -- thick: ~20 puffs a second
            self.smokeClock = 0
            self:SpawnSmoke()
        end
    end

    -- keep the riders ledger's unrealized gains ticking (once a second)
    self.riderRefresh = (self.riderRefresh or 0) + dt
    if self.riderRefresh >= 1 then
        self.riderRefresh = 0
        self:UpdateDisplay()
    end

    -- pot and nerve readout beneath the odometer: how much is up for
    -- grabs and how many are still white-knuckling it
    local CMod = BJ.CrashMultiplayer
    local aboard = CMod and CMod:CountAboard() or 0
    local pot = CS.ante * #CS.playerOrder
    self.bailNowText:SetText("|cffffd700pot " .. pot .. "g|r  -  |cffff8866" ..
        aboard .. " still aboard|r")

    self:UpdateBailButton(mult)
end

-- One grey puff at the tail of the ship
function CF:SpawnSmoke()
    if not (self.zep and self.zep:GetLeft() and self.sky:GetLeft()) then return end
    local puff = table.remove(self.smokePool)
    if not puff then
        puff = (self.smokeLayer or self.sky):CreateTexture(nil, "ARTWORK", nil, 0)
        puff:SetTexture(CIRCLE)
    end
    puff.x = (self.zep:GetLeft() - self.sky:GetLeft()) + 32 + math.random(-4, 4)
    puff.y = (self.zep:GetBottom() - self.sky:GetBottom()) + 72 + math.random(-6, 6)
    puff.age = 0
    puff.seed = math.random() * 6
    puff.drift = 48 + math.random(24)     -- px/sec backward on top of the
    puff.rise = 8 + math.random(10)       -- world sliding past
    puff.scroll0 = self.curScroll or 0    -- anchored to the WORLD
    local g = 0.4 + math.random() * 0.25
    puff:SetVertexColor(g, g, g, 1)
    puff:Show()
    table.insert(self.smoke, puff)
end

-- Puffs ride the world backward, swelling and thinning as they go. They
-- never die on screen (a visible pop reads as flashing) - each lives
-- until it has fully cleared the sky's left edge, where the clip window
-- has already swallowed it.
function CF:AnimateSmoke(dt)
    if not self.smoke then return end
    for i = #self.smoke, 1, -1 do
        local s = self.smoke[i]
        s.age = s.age + dt
        local size = 6 + 18 * s.age
        local cx = s.x - ((self.curScroll or 0) - (s.scroll0 or 0))
            - s.drift * s.age
        if cx + size / 2 < 0 or s.age > 30 then
            s:Hide()
            table.remove(self.smoke, i)
            table.insert(self.smokePool, s)
        else
            s:SetSize(size, size)
            s:ClearAllPoints()
            s:SetPoint("CENTER", self.sky, "BOTTOMLEFT",
                cx, s.y + s.rise * s.age + math.sin(s.age * 5 + s.seed) * 3)
            -- translucent from birth, thinning with age but never gone:
            -- exiting the screen is what ends a puff
            s:SetAlpha(0.35 / (1 + s.age * 0.35))
        end
    end
end

function CF:UpdateBailButton(mult)
    local CS = BJ.CrashState
    local CM = BJ.CrashMultiplayer
    local myName = UnitName("player")
    local p = CS.players[myName]

    if CS.phase == CS.PHASE.FLIGHT and p and not p.cashedOut and not p.refunded then
        self.bailBtn:Show()
        if CM and CM.pendingCashout then
            self.bailBtn.text:SetText("|cffffff88JUMPING...|r")
        else
            self.bailBtn.text:SetText("|cffffffffJUMP!|r  |cffffd700" ..
                metersFor(mult or CS:CurrentMultiplier()) .. "m|r")
        end
    else
        self.bailBtn:Hide()
    end
end

-- Blizzard's own booms, by fileDataID (vanilla-era files every classic
-- client ships): the cannon blast layered with a New Year firework boom.
-- willPlay is checked so a client missing them falls back to the air horn.
local BOOM_FDIDS = { 566101, 566373 }   -- cannon01_blasta, g_fireworkboomgeneral1
local function playCrashBoom()
    local played = false
    for _, id in ipairs(BOOM_FDIDS) do
        local ok, willPlay = pcall(PlaySoundFile, id, "SFX")
        if ok and willPlay then played = true end
    end
    if not played then
        PlaySoundFile("Interface\\AddOns\\Chairfaces Casino\\Sounds\\AirHorn.ogg", "SFX")
    end
end

-- Kick the explosion FX off at the zeppelin's last position. She always
-- blows - at the 1000m cap if nowhere sooner.
function CF:OnCrash()
    local CS = BJ.CrashState
    self.crashedText:SetTextColor(1, 0.15, 0.1)
    self.crashedText:SetText("KABOOM  " .. metersFor(CS.crashPoint) .. "m")
    playCrashBoom()

    -- explode where the ship actually is on screen
    local x, y = DOCK_X + 60, DOCK_Y + 40
    if self.zep and self.zep:GetLeft() and self.sky:GetLeft() then
        x = (self.zep:GetLeft() - self.sky:GetLeft()) + 72
    end
    -- a settled flight lands in the log right away if it's open
    if self.logFrame and self.logFrame:IsShown() then
        self:UpdateLogWindow()
    end

    self.boomAge = 0
    if self.boomModel then
        -- re-applying the fileID rewinds the one-shot blast animation
        local bm = self.boomModel
        bm:ClearAllPoints()
        bm:SetPoint("CENTER", self.sky, "BOTTOMLEFT", x, y)
        applyEffectModel(bm, BOOM_MODEL_FILEID)
        bm:Show()
    else
        for i, b in ipairs(self.boomPieces) do
            local ang = math.random() * 2 * math.pi
            local spd = 30 + math.random(90)
            if b.front then spd = spd * 1.35 end   -- closer = faster: depth
            b.ox = x + math.random(-14, 14)
            b.oy = y + math.random(-12, 12)
            b.dx = math.cos(ang) * spd
            b.dy = math.sin(ang) * spd * 0.8 + 18   -- a little updraft
            b.size0 = 6 + math.random(16)
            b.grow = 14 + math.random(30)
            -- the fire palette: white core -> yellow -> orange -> red,
            -- with dark smoke chunks tumbling through
            local roll = math.random()
            if roll < 0.15 then b:SetVertexColor(1, 0.97, 0.80, 1)
            elseif roll < 0.40 then b:SetVertexColor(1, 0.80, 0.15, 1)
            elseif roll < 0.70 then b:SetVertexColor(1, 0.45, 0.05, 1)
            elseif roll < 0.88 then b:SetVertexColor(0.90, 0.15, 0.05, 1)
            else b:SetVertexColor(0.25, 0.22, 0.20, 1) end
            if not b.front then
                -- the far half of the blast sits dimmer, deeper in
                local r, g, bl = b:GetVertexColor()
                b:SetVertexColor(r * 0.65, g * 0.65, bl * 0.65, 1)
            end
            b:Show()
        end
    end
    if self.zep then self.zep:Hide() end
    self:UpdateDisplay()
end

function CF:AnimateBoom(dt)
    if not self.boomAge then return end
    self.boomAge = self.boomAge + dt
    local age = self.boomAge
    local life = self.boomModel and 1.6 or 1.3
    if age > life then
        self.boomAge = nil
        if self.boomModel then self.boomModel:Hide() end
        for _, b in ipairs(self.boomPieces) do b:Hide() end
        return
    end
    if self.boomModel then return end   -- the m2 animates itself
    for _, b in ipairs(self.boomPieces) do
        local grow = b.size0 + b.grow * age
        b:SetSize(grow, grow)
        b:ClearAllPoints()
        -- radial burst with a touch of gravity on the arcs
        b:SetPoint("CENTER", self.sky, "BOTTOMLEFT",
            b.ox + b.dx * age,
            b.oy + b.dy * age - 20 * age * age)
        b:SetAlpha(1 - age / life)
    end
end

-- Comical goblin panic on the way out the door: the three lines verified
-- to play on the anniversary client (/cc zep sound walked the candidates)
-- - two zany goblin farewells and the classic goblin death scream.
local BAIL_VOICE_FDIDS = {
    { 550807, 550814, 550517 },
}
local lastBailVoice = 0
local function playBailVoice()
    local now = GetTime()
    if now - lastBailVoice < 0.5 then return end   -- a choir of jumpers is noise
    lastBailVoice = now
    for _, tier in ipairs(BAIL_VOICE_FDIDS) do
        -- rotate through the tier starting from a random line, so one
        -- missing file can't mute a tier that has working ones
        local n = #tier
        local start = math.random(n)
        for i = 0, n - 1 do
            local id = tier[((start - 1 + i) % n) + 1]
            local ok, willPlay = pcall(PlaySoundFile, id, "Master")
            if ok and willPlay then return end
        end
    end
    -- every game-file id failed on this client: fall back to a SHIPPED
    -- sound so a jump is never silent (Trixie cheers the jumper out the
    -- door until working goblin ids are pinned via /cc zep sound)
    BJ:PlaySfx("trix_woohoo.ogg")
end

-- A little parachute pops where the ship is when someone bails
function CF:OnBailOut(playerName, mult)
    if not self.sky or not self.sky:IsShown() then return end
    playBailVoice()
    -- the goblin jumps from wherever the ship is on screen
    local x, y = DOCK_X + 60, DOCK_Y
    if self.zep and self.zep:GetLeft() and self.sky:GetLeft() then
        x = (self.zep:GetLeft() - self.sky:GetLeft()) + 72
    end

    local chute = self.chutePool and table.remove(self.chutePool)
    if not chute then
        chute = CreateFrame("Frame", nil, self.sky)
        chute:SetSize(36, 54)
        chute:SetFrameLevel(self.sky:GetFrameLevel() + 7)   -- in front of everything

        -- the real deal when models load: spells/parachute.m2 stitched
        -- above creature/goblin/goblin.m2 - the goblin who just jumped
        local canopyModel = CreateFrame("PlayerModel", nil, chute)
        canopyModel:SetSize(36, 30)
        canopyModel:SetPoint("TOP", 0, 0)
        local jumper = CreateFrame("PlayerModel", nil, chute)
        jumper:SetSize(28, 32)
        jumper:SetPoint("TOP", 0, -20)
        local okC = applyEffectModel(canopyModel, CHUTE_MODEL_FILEID)
        -- by display id so the goblin arrives textured; bare m2 fallback
        local okG = jumper.SetDisplayInfo
            and pcall(jumper.SetDisplayInfo, jumper, GOBLIN_DISPLAY_ID)
        if not okG then
            okG = applyEffectModel(jumper, GOBLIN_MODEL_FILEID)
        end
        if okC and okG then
            chute.models = { canopyModel, jumper }
        else
            canopyModel:Hide()
            jumper:Hide()
        end

        -- hand-drawn fallback for clients that can't load fileID models
        local canopy = chute:CreateTexture(nil, "OVERLAY", nil, 3)
        canopy:SetSize(24, 14)
        canopy:SetPoint("TOP", 0, 0)
        canopy:SetTexture(CIRCLE)
        canopy:SetVertexColor(0.9, 0.75, 0.3, 1)
        local body = chute:CreateTexture(nil, "OVERLAY", nil, 3)
        body:SetSize(6, 8)
        body:SetPoint("TOP", 0, -16)
        body:SetTexture(FLAT)
        body:SetVertexColor(0.4, 0.6, 0.35, 1)
        if chute.models then
            canopy:Hide()
            body:Hide()
        end

        local label = chute:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("TOP", chute, "BOTTOM", 0, -1)
        chute.label = label
    end
    chute.label:SetText("|cff00ff00" .. (playerName or "") .. "|r")
    chute.x, chute.y, chute.age = x, y, 0
    chute.scroll0 = self.curScroll or 0   -- anchor him to the WORLD: the
    -- ship keeps flying while the world (and the goblin) slides back
    chute:ClearAllPoints()
    chute:SetPoint("BOTTOMLEFT", x, y)
    chute:Show()
    table.insert(self.chutes, chute)
end

function CF:AnimateChutes(dt)
    if not self.chutes then return end
    for i = #self.chutes, 1, -1 do
        local c = self.chutes[i]
        c.age = c.age + dt
        local drift = (self.curScroll or 0) - (c.scroll0 or 0)
        local cx = c.x - drift + math.sin(c.age * 3) * 6
        if c.age > 2.4 or c.y - 30 * c.age < 6 or cx < -60 then
            c:Hide()
            table.remove(self.chutes, i)
            self.chutePool = self.chutePool or {}
            table.insert(self.chutePool, c)
        else
            c:ClearAllPoints()
            c:SetPoint("BOTTOMLEFT", cx, c.y - 30 * c.age)
            c:SetAlpha(c.age > 1.8 and (1 - (c.age - 1.8) / 0.6) or 1)
        end
    end
end

--[[
    ENGINE SOUND
    Blizzard's own zeppelin propeller loop, by fileDataID with fallbacks
    (willPlay-checked, so a client missing the newer files just tries the
    next). PlaySoundFile doesn't loop, so a ticker restarts the clip; the
    tiny hiccup at each restart suits a goblin engine fine. Runs only
    while the window is visible and a flight is up.
]]

-- All VANILLA-era files (verified in the 1.12 sound listing), so the
-- anniversary/classic clients are guaranteed to ship them - the newer
-- cata/mop propeller loops tried first turned out not to exist there.
local ENGINE_FDIDS = {
    567190,   -- sound/doodad/doodadcompression/zeppelinengineloop.ogg (the real thing)
    566733,   -- sound/doodad/goblinmachineryloop.ogg
    566604,   -- sound/doodad/zeppelinheliuma.ogg
}
local ENGINE_RETRIGGER_SECS = 4

function CF:StartEngine()
    if self.engineTicker then return end
    local lobby = UI.Lobby
    if lobby and lobby.sfxEnabled == false then return end

    local function rev()
        if self.engineHandle then
            StopSound(self.engineHandle)
            self.engineHandle = nil
        end
        -- muting SFX mid-flight silences the engine at the next rev
        if lobby and lobby.sfxEnabled == false then return end
        -- remember which candidate this client has so we only probe once
        if self.engineFdid then
            local _, handle = PlaySoundFile(self.engineFdid, "SFX")
            self.engineHandle = handle
            return
        end
        for _, id in ipairs(ENGINE_FDIDS) do
            local ok, willPlay, handle = pcall(PlaySoundFile, id, "SFX")
            if ok and willPlay then
                self.engineFdid = id
                self.engineHandle = handle
                return
            end
        end
        self.engineFdid = false   -- nothing available; stay quiet
    end

    rev()
    if self.engineFdid == false then return end
    self.engineTicker = C_Timer.NewTicker(ENGINE_RETRIGGER_SECS, rev)
end

function CF:StopEngine()
    if self.engineTicker then
        self.engineTicker:Cancel()
        self.engineTicker = nil
    end
    if self.engineHandle then
        StopSound(self.engineHandle)
        self.engineHandle = nil
    end
end

--[[
    FLIGHT LOG (same floating window pattern as the other games)
]]

function CF:CreateLogWindow()
    local logFrame = CreateFrame("Frame", "CasinoCrashLogFrame", UIParent, "BackdropTemplate")
    logFrame:SetSize(320, 350)
    logFrame:SetPoint("LEFT", self.frame, "RIGHT", 10, 0)
    logFrame:SetBackdrop({
        bgFile = FLAT,
        edgeFile = FLAT,
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

    local titleBar = CreateFrame("Frame", nil, logFrame, "BackdropTemplate")
    titleBar:SetSize(320, 24)
    titleBar:SetPoint("TOP", 0, 0)
    titleBar:SetBackdrop({ bgFile = FLAT })
    titleBar:SetBackdropColor(0.15, 0.12, 0.05, 1)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() logFrame:StartMoving() end)
    titleBar:SetScript("OnDragStop", function() logFrame:StopMovingOrSizing() end)

    local titleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("CENTER")
    titleText:SetText("|cffffd700Crash - Flight Log|r")

    local closeBtn = CreateFrame("Button", nil, titleBar)
    closeBtn:SetSize(18, 18)
    closeBtn:SetPoint("RIGHT", -3, 0)
    closeBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    closeBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
    closeBtn:SetScript("OnClick", function() logFrame:Hide() end)

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
    logText:SetText("No flight history yet.")

    logFrame.scrollContent = scrollContent
    logFrame.logText = logText

    self.logFrame = logFrame
end

function CF:ToggleLog()
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

function CF:UpdateLogWindow()
    if not self.logFrame then return end

    self.logFrame.logText:SetText(BJ.CrashState:GetGameLogText())

    local textHeight = self.logFrame.logText:GetStringHeight()
    self.logFrame.scrollContent:SetHeight(math.max(300, textHeight + 20))
end

-- Park the ship back at the mooring tower and rewind the world
-- (between rounds / fresh table)
-- Configure the skin's sprite-sheet geometry (frames stacked vertically,
-- frame 0 at the top) and rewind to frame 0. frames=1 restores plain
-- whole-texture display. Called at creation with the baked constants and
-- from /cc zep skin <frames> <fps> to audition a sheet live.
function CF:SetSkinSheet(frames, fps)
    self.skinFrames = math.max(1, math.floor(frames or 1))
    self.skinFPS = (fps and fps > 0) and fps or 15
    self.skinElapsed = 0
    self.skinFrame = 0
    local skin = self.zep and self.zep.skin
    if not skin then return end
    if self.skinFrames > 1 then
        skin:SetTexCoord(0, 1, 0, 1 / self.skinFrames)
    else
        skin:SetTexCoord(0, 1, 0, 1)
    end
end

-- Step the sprite-sheet skin (lobby-logo pattern: accumulate time, move
-- the texcoord window one frame strip at a time). Runs in every phase so
-- the propellers idle at the mooring tower too; no-op for static skins.
function CF:AnimateSkin(dt)
    local skin = self.zep and self.zep.skin
    if not (skin and skin:IsShown()) then return end
    local frames = self.skinFrames or 1
    if frames <= 1 then return end
    local frameTime = 1 / (self.skinFPS or 15)
    self.skinElapsed = (self.skinElapsed or 0) + dt
    local duration = frames * frameTime
    if self.skinElapsed >= duration then
        self.skinElapsed = self.skinElapsed % duration
    end
    local newFrame = math.floor(self.skinElapsed / frameTime)
    if newFrame >= frames then newFrame = frames - 1 end
    if newFrame ~= self.skinFrame then
        self.skinFrame = newFrame
        skin:SetTexCoord(0, 1, newFrame / frames, (newFrame + 1) / frames)
    end
end

-- Everyone jumped: she flies off the right edge instead of exploding.
-- The round is already settled under the hood; the banner waits until
-- she has actually left the screen ("the game ends when she's gone").
function CF:OnFlyAway()
    self.flyAnim = { t = 0, v = 60 }
    self.crashedText:SetText("")
    if BJ.UI and BJ.UI.Lobby then BJ.UI.Lobby:PlayTrixieVoice("crash_flyaway") end
    if self.logFrame and self.logFrame:IsShown() then
        self:UpdateLogWindow()
    end
    self:UpdateDisplay()
end

function CF:AnimateFlyAway(dt)
    local fa = self.flyAnim
    if not fa or not self.zep then return end
    fa.t = fa.t + dt
    fa.v = fa.v + 220 * dt   -- full throttle out of town
    local left = self.zep:GetLeft()
    local skyLeft = self.sky and self.sky:GetLeft()
    if not left or not skyLeft then self.flyAnim = nil return end
    local x = (left - skyLeft) + fa.v * dt
    self.zep:ClearAllPoints()
    self.zep:SetPoint("BOTTOMLEFT", x, DOCK_Y + math.sin(fa.t * 7.7) * 3)
    self:AnimateSkin(dt)     -- props keep spinning on the way out
    if x > self.sky:GetWidth() + 20 then
        self.flyAnim = nil
        self.zep:Hide()
        self.crashedText:SetTextColor(0.55, 0.8, 1)
        self.crashedText:SetText("...AND SHE'S GONE")
        self:UpdateDisplay()
    end
end

function CF:DockZeppelin()
    if not self.zep then return end
    self.flyAnim = nil
    self.escapeT = nil
    self.zep:ClearAllPoints()
    self.zep:SetPoint("BOTTOMLEFT", DOCK_X, DOCK_Y)
    self.zep:Show()
    -- engine off at the mooring tower: no flame, no smoke, props still
    if self.fxFire then self.fxFire:Hide() end
    if self.fxSmoke then self.fxSmoke:Hide() end
    for _, p in ipairs(self.flameParts or {}) do p:Hide() end
    self:LayoutWorld(0)
end

function CF:OnFlightStart()
    self.crashedText:SetText("")
    self.crashHighSaid = false   -- re-arm the climbing-high line for this round
    self:DockZeppelin()
    self:UpdateDisplay()
    if BJ.UI and BJ.UI.Lobby then BJ.UI.Lobby:PlayTrixieVoice("crash_takeoff", { cd = 5 }) end
end

function CF:StopFlight()
    self:StopEngine()
    self:DockZeppelin()
    if self.crashedText then self.crashedText:SetText("") end
end

--[[
    DISPLAY
]]

local function riderLine(CS, name)
    local p = CS.players[name]
    if not p then return name end
    local bits = "|cffffffff" .. name .. "|r"
    local ante = CS.ante or 0

    -- After the flight the panel is the pot ledger: who took it, who fed it
    if CS.phase == CS.PHASE.SETTLEMENT then
        local net = CS.settlements and CS.settlements[name]
        local isWinner = false
        for _, w in ipairs(CS.winners or {}) do
            if w == name then isWinner = true break end
        end
        if p.refunded then
            return bits .. " |cff888888- ante voided, owes nothing|r"
        elseif isWinner then
            local takes = (#(CS.winners or {}) > 1) and "splits the pot" or "TAKES THE POT"
            return "|cff00ff00" .. name .. "|r " .. takes .. " |cffffd700+" .. (net or 0) ..
                "g|r |cff888888(last out, " .. metersFor(p.cashedOut and p.cashedOut.mult) .. "m)|r"
        elseif net and net < 0 then
            if p.cashedOut then
                return bits .. " |cffff4444-" .. (-net) .. "g|r |cff888888(jumped too early, " ..
                    metersFor(p.cashedOut.mult) .. "m)|r"
            end
            return bits .. " |cffff4444-" .. (-net) .. "g|r |cff888888(went down with the ship)|r"
        elseif p.cashedOut then
            return bits .. " |cffffff00- push (nobody won)|r"
        else
            return bits .. " |cffffff00- push, antes back|r"
        end
    end

    if p.refunded then
        return bits .. " |cff888888(voided)|r"
    end
    if p.cashedOut then
        return bits .. " |cff00ff00jumped at " .. metersFor(p.cashedOut.mult) .. "m|r"
    end
    if CS.phase == CS.PHASE.FLIGHT then
        local tag = p.target and (" |cff88ccffauto " .. metersFor(p.target) .. "m|r") or ""
        return bits .. " |cffff8866STILL ABOARD|r |cff888888(ante " .. ante .. "g)|r" .. tag
    end
    local tag = p.target and (" |cff88ccffauto " .. metersFor(p.target) .. "m|r") or ""
    return bits .. " |cffffd700ante " .. ante .. "g|r" .. tag
end

function CF:UpdateDisplay()
    if not self.frame or not self.frame:IsShown() then return end

    local CS = BJ.CrashState
    local CM = BJ.CrashMultiplayer
    local myName = UnitName("player")
    local phase = CS.phase
    local isHost = CM and CM.isHost
    local aboard = CS.players[myName] ~= nil

    -- marquee (distances: where the last few flights blew up)
    if #CS.recentCrashes > 0 then
        local bits = {}
        for _, pt in ipairs(CS.recentCrashes) do
            bits[#bits + 1] = CS:CrashColor(pt) .. metersFor(pt) .. "m|r"
        end
        self.marquee:SetText("Last explosions:  " .. table.concat(bits, "  "))
    else
        self.marquee:SetText("|cff888888No flights yet at this table.|r")
    end

    -- engine drones exactly while a flight is up and the window is open
    -- (UpdateDisplay runs on every phase change and once a second in
    -- flight; OnHide kills it if the window closes mid-flight)
    if phase == CS.PHASE.FLIGHT then
        self:StartEngine()
    else
        self:StopEngine()
    end

    -- sky text (and the ship parks at the tower whenever it isn't flying)
    if phase ~= CS.PHASE.FLIGHT and phase ~= CS.PHASE.SETTLEMENT then
        self:DockZeppelin()
    end
    if phase ~= CS.PHASE.FLIGHT and self.bailNowText then
        self.bailNowText:SetText("")
    end
    -- the red CRASHED stamp only lives through the settlement screen;
    -- the moment the next boarding is called it comes down
    if phase ~= CS.PHASE.SETTLEMENT and self.crashedText then
        self.crashedText:SetText("")
    end
    if phase == CS.PHASE.IDLE then
        self.multText:SetText("")
        self.skyStatus:SetText("|cff888888No table open.|r")
    elseif phase == CS.PHASE.BOARDING then
        self.multText:SetText("")
        local pot = CS.ante * #CS.playerOrder
        self.skyStatus:SetText("|cffffd700BOARDING|r  -  |cffffd700" .. CS.ante ..
            "g|r a seat, pot |cffffd700" .. pot .. "g|r")
    elseif phase == CS.PHASE.LAUNCHING then
        self.multText:SetText("")
        self.skyStatus:SetText("|cffffd700LIFTOFF...|r")
    elseif phase == CS.PHASE.FLIGHT then
        self.skyStatus:SetText("")
    elseif phase == CS.PHASE.SETTLEMENT then
        self.multText:SetText(CS:CrashColor(CS.crashPoint) .. metersFor(CS.crashPoint) .. "m|r")
        if CS.verifyFailed then
            self.skyStatus:SetText("|cffff4444REVEAL FAILED VERIFICATION|r")
        elseif CS.winners and #CS.winners > 0 then
            self.skyStatus:SetText("|cff00ff00" .. table.concat(CS.winners, " + ") ..
                " take" .. (#CS.winners == 1 and "s" or "") .. " the pot!|r")
        elseif #CS.playerOrder > 0 then
            self.skyStatus:SetText("|cffffff00Nobody jumped - antes push.|r")
        else
            self.skyStatus:SetText("")
        end
    end

    -- riders (a debt ledger once the flight has settled)
    if phase == CS.PHASE.SETTLEMENT then
        self.ridersTitle:SetText("|cffffd700Settle Up|r  |cff888888(" .. #CS.playerOrder .. " riders)|r")
    else
        self.ridersTitle:SetText("|cffffd700Riders|r  |cff888888(" .. #CS.playerOrder .. ")|r")
    end
    for i, row in ipairs(self.riderRows) do
        local name = CS.playerOrder[i]
        if name then
            if i == #self.riderRows and #CS.playerOrder > #self.riderRows then
                row:SetText("|cff888888... and " .. (#CS.playerOrder - #self.riderRows + 1) .. " more|r")
            else
                row:SetText(riderLine(CS, name))
            end
        else
            row:SetText("")
        end
    end

    -- controls: hide everything, then show what this phase + role needs
    self.anteLabel:Hide(); self.anteBox:Hide(); self.openBtn:Hide()
    self.targetLabel:Hide(); self.targetBox:Hide(); self.boardBtn:Hide(); self.targetBtn:Hide()
    self.launchBtn:Hide(); self.nextBtn:Hide(); self.closeTableBtn:Hide()
    self:UpdateBailButton()

    if phase == CS.PHASE.IDLE then
        self.statusText:SetText("|cff88ccffHost a zeppelin: set the ante and open the table.|r")
        self.anteLabel:Show(); self.anteBox:Show(); self.openBtn:Show()

    elseif phase == CS.PHASE.BOARDING then
        if isHost then
            -- the pilot can ride too: same board/target controls as any
            -- rider, with LAUNCH re-anchored beneath them
            self.closeTableBtn:Show()
            self.launchBtn:ClearAllPoints()
            if aboard then
                self.statusText:SetText("|cff00ff00Aboard your own ship.|r LAUNCH when ready.")
                self.targetLabel:Show(); self.targetBox:Show(); self.targetBtn:Show()
                self.launchBtn:SetPoint("TOP", self.targetBtn, "BOTTOM", 0, -6)
            else
                self.statusText:SetText("|cff88ccffBoarding: ride along, or just pilot her.|r")
                self.targetLabel:Show(); self.targetBox:Show(); self.boardBtn:Show()
                self.boardBtn.text:SetText("|cff00ff00Ante In (" .. CS.ante .. "g)|r")
                if BJ.UI and BJ.UI.Debts then
                    BJ.UI.Debts:SetJoinFakeBadge(self.boardBtn, CS.fakePlay == true)
                end
                self.launchBtn:SetPoint("TOP", self.boardBtn, "BOTTOM", 0, -6)
            end
            self.launchBtn:Show()
        elseif aboard then
            self.statusText:SetText("|cff00ff00You're aboard.|r Adjust your auto-jump until launch.")
            self.targetLabel:Show(); self.targetBox:Show(); self.targetBtn:Show()
        else
            self.statusText:SetText("|cff88ccffAnte |cffffd700" .. CS.ante ..
                "g|r into the pot. Last one to jump takes it all.|r")
            self.targetLabel:Show(); self.targetBox:Show(); self.boardBtn:Show()
            self.boardBtn.text:SetText("|cff00ff00Ante In (" .. CS.ante .. "g)|r")
            if BJ.UI and BJ.UI.Debts then
                BJ.UI.Debts:SetJoinFakeBadge(self.boardBtn, CS.fakePlay == true)
            end
        end

    elseif phase == CS.PHASE.LAUNCHING then
        self.statusText:SetText("|cffffd700Boarding closed - fate is sealed...|r")

    elseif phase == CS.PHASE.FLIGHT then
        local p = CS.players[myName]
        if p and p.cashedOut then
            self.statusText:SetText("|cff00ff00Jumped at " .. metersFor(p.cashedOut.mult) ..
                "m!|r Now pray everyone still up there rides her into the ground.")
        elseif aboard then
            self.statusText:SetText("")
        else
            self.statusText:SetText("|cff888888Spectating. The brave are up there.|r")
        end

    elseif phase == CS.PHASE.SETTLEMENT then
        self.statusText:SetText("|cffffd700Losers pay the winner by hand - then the next flight boards.|r")
        -- anyone can take the next flight; whoever clicks becomes the
        -- pilot and bank
        self.nextBtn:Show()
        if isHost then
            self.nextBtn.text:SetText("|cff00ff00Next Flight|r")
            self.closeTableBtn:Show()
        else
            self.nextBtn.text:SetText("|cff00ff00Pilot Next Flight|r")
        end
    end
end

-- ==================== DEBUG: LIVE MODEL AUDITION ====================
-- /cc zep ... (TestMode-name-gated in Core.lua). Overlays a PlayerModel
-- frame on the hand-drawn zeppelin so candidate models can be auditioned
-- live while she flies. The transport zeppelin m2 world doodad hard-crashed
-- the client with an access violation (that's why the ship is hand-drawn),
-- and pcall cannot catch a client crash — it only catches Lua errors from
-- invalid IDs. Whatever ID you typed last before a crash-to-desktop is the
-- culprit; note it down and never use it. The overlay never activates
-- outside this command, so normal play stays on the safe hand-drawn art.
function CF:DebugZep(arg)
    if not self.zep then
        BJ:Print("Zep debug: open the Crash window first so the zeppelin exists.")
        return
    end

    if not self.zepModel then
        local m = CreateFrame("PlayerModel", nil, self.zep)
        m:SetAllPoints(self.zep)
        m:SetFrameLevel(self.zep:GetFrameLevel() + 1)
        m:Hide()
        self.zepModel = m
    end

    local m = self.zepModel
    local cmd, rest = strsplit(" ", arg or "", 2)
    cmd = strlower(cmd or "")

    local function setArtShown(shown)
        for _, tex in ipairs(self.zep.art or {}) do
            tex:SetShown(shown)
        end
    end

    -- mode: "display" (creature displayID), "file" (m2 fileDataID), or
    -- "npc" (creature/NPC ID - the number in a Wowhead URL; the client
    -- resolves the model itself, so no displayID hunting needed)
    local function apply(id, mode)
        BJ:Print("Zep debug: trying " .. mode .. " |cffffd700" .. id ..
            "|r — if the client hard-crashes now, that ID is the culprit.")
        m:ClearModel()
        local fn = (mode == "file" and m.SetModelByFileID)
            or (mode == "npc" and m.SetCreature)
            or m.SetDisplayInfo
        if not fn then
            BJ:Print("Zep debug: that lookup isn't available on this client.")
            return
        end
        local ok = pcall(fn, m, id)
        if not ok then
            BJ:Print("Zep debug: that ID was rejected (invalid, no harm done).")
            return
        end
        self.zepModelId, self.zepModelMode = id, mode
        m:Show()
        setArtShown(false)
    end

    if cmd == "off" then
        m:ClearModel()
        m:Hide()
        if self.zep.skin then self.zep.skin:Hide() end
        if self.fxFire then self.fxFire:Hide() end
        if self.fxSmoke then self.fxSmoke:Hide() end
        if self.fxBoom then self.fxBoom:Hide() end
        setArtShown(true)
        self.zepModelId = nil
        BJ:Print("Zep debug: model off, hand-drawn zeppelin restored.")
    elseif cmd == "skin" then
        -- preview Textures\zeppelin.tga in place of the hand-drawn parts
        -- (a missing file shows as a solid box - that means the tga isn't
        -- in the folder, or the client hasn't been fully restarted since
        -- the file was added: /reload does NOT pick up new texture files).
        -- Optional args audition an animated sheet: /cc zep skin 10 20
        -- shows a 10-frame sheet at 20 fps; bare /cc zep skin toggles.
        local skin = self.zep.skin
        if not skin then return end
        local frames, fps
        if rest then frames, fps = strsplit(" ", rest, 2) end
        frames, fps = tonumber(frames), tonumber(fps)
        if skin:IsShown() and not frames then
            skin:Hide()
            setArtShown(true)
            BJ:Print("Zep debug: skin off, hand-drawn zeppelin restored.")
        else
            self:SetSkinSheet(frames or ZEP_SKIN_FRAMES, fps or ZEP_SKIN_FPS)
            skin:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\Crash\\zeppelin")
            skin:Show()
            m:Hide()
            setArtShown(false)
            if self.skinFrames > 1 then
                BJ:Print(("Zep debug: showing Textures\\Crash\\zeppelin.tga as a %d-frame sheet at %g fps."):format(
                    self.skinFrames, self.skinFPS))
            else
                BJ:Print("Zep debug: showing Textures\\Crash\\zeppelin.tga (solid box = file missing/bad format).")
            end
        end
    elseif cmd == "sound" then
        -- audition game-file sound ids: /cc zep sound <fileID> plays one;
        -- bare /cc zep sound walks the whole bail-voice list (staggered)
        -- and reports which ids this client can actually play
        local id = tonumber(rest)
        if id then
            local ok, willPlay = pcall(PlaySoundFile, id, "Master")
            BJ:Print(("Zep debug: sound %d -> %s"):format(id,
                (ok and willPlay) and "|cff00ff00PLAYS|r"
                or (ok and "|cffff8800exists but won't play|r" or "|cffff4444rejected|r")))
        else
            local all = {}
            for _, tier in ipairs(BAIL_VOICE_FDIDS) do
                for _, tid in ipairs(tier) do table.insert(all, tid) end
            end
            BJ:Print("Zep debug: testing " .. #all .. " bail-voice ids, one per second...")
            for i, tid in ipairs(all) do
                C_Timer.After(i - 1, function()
                    local ok, willPlay = pcall(PlaySoundFile, tid, "Master")
                    BJ:Print(("  %d -> %s"):format(tid,
                        (ok and willPlay) and "|cff00ff00PLAYS|r"
                        or (ok and "|cffff8800no|r" or "|cffff4444rejected|r")))
                end)
            end
        end
    elseif cmd == "fx" then
        local s = self.fxStatus or {}
        BJ:Print(("Crash FX: fire = %s | smoke = %s | boom = %s"):format(
            s.fire or "not created", s.smoke or "not created", s.boom or "not created"))
    elseif cmd == "fire" or cmd == "smoke" or cmd == "boom" then
        -- audition an effect m2 live: /cc zep fire 166111 etc.
        local id = tonumber(rest)
        if not id then
            BJ:Print("Usage: /cc zep " .. cmd .. " <fileID>   (0 = circle fallback; /cc zep fx = status)")
            return
        end
        local frame = (cmd == "fire" and self.fxFire)
            or (cmd == "smoke" and self.fxSmoke) or self.fxBoom
        if not frame then return end
        local ok, why = applyEffectModel(frame, id)
        self.fxStatus = self.fxStatus or {}
        self.fxStatus[cmd] = ok and ("ok (" .. id .. ")") or why
        local active = ok and frame or nil
        if cmd == "fire" then
            FIRE_MODEL_FILEID, self.zepFireModel = id, active
        elseif cmd == "smoke" then
            SMOKE_MODEL_FILEID, self.zepSmokeModel = id, active
        else
            BOOM_MODEL_FILEID, self.boomModel = id, active
        end
        if not ok then
            frame:Hide()
            BJ:Print("Zep debug: " .. cmd .. " model " .. id .. " failed - " .. tostring(why))
            return
        end
        if cmd == "boom" then
            -- preview the blast right on the ship
            local x = 200
            if self.zep:GetLeft() and self.sky:GetLeft() then
                x = (self.zep:GetLeft() - self.sky:GetLeft()) + 72
            end
            frame:ClearAllPoints()
            frame:SetPoint("CENTER", self.sky, "BOTTOMLEFT", x, DOCK_Y + 40)
            frame:Show()
            self.boomAge = 0
        else
            frame:Show()   -- burns at the exhaust until the next dock
        end
        BJ:Print("Zep debug: " .. cmd .. " model set to " .. id .. ".")
    elseif cmd == "tower" then
        -- preview Textures\tower.tga in place of the hand-drawn mast
        local ts = self.tower and self.tower.skin
        if not ts then return end
        if ts:IsShown() then
            ts:Hide()
            for _, tex in ipairs(self.tower.art or {}) do tex:Show() end
            BJ:Print("Zep debug: tower skin off, hand-drawn tower restored.")
        else
            ts:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\Crash\\tower")
            ts:Show()
            for _, tex in ipairs(self.tower.art or {}) do tex:Hide() end
            BJ:Print("Zep debug: showing Textures\\Crash\\tower.tga (solid box = file missing/bad format).")
        end
    elseif cmd == "next" or cmd == "prev" then
        if not self.zepModelId then
            BJ:Print("Zep debug: set a starting ID first, e.g. /cc zep 1207")
            return
        end
        apply(self.zepModelId + (cmd == "next" and 1 or -1), self.zepModelMode)
    elseif cmd == "face" then
        local deg = tonumber(rest)
        if deg then m:SetFacing(math.rad(deg)) else BJ:Print("Usage: /cc zep face <degrees>") end
    elseif cmd == "scale" then
        local s = tonumber(rest)
        if s and m.SetCamDistanceScale then m:SetCamDistanceScale(s)
        else BJ:Print("Usage: /cc zep scale <n>  (camera distance, e.g. 1.5)") end
    elseif cmd == "file" then
        local id = tonumber(rest)
        if id then apply(id, "file") else BJ:Print("Usage: /cc zep file <fileID>") end
    elseif cmd == "npc" then
        local id = tonumber(rest)
        if id then apply(id, "npc") else BJ:Print("Usage: /cc zep npc <npcID>  (the number in a Wowhead URL)") end
    elseif cmd == "info" then
        if self.zepModelId then
            BJ:Print("Zep debug: showing " .. (self.zepModelMode or "display") .. " " .. self.zepModelId)
        else
            BJ:Print("Zep debug: no model active (hand-drawn zeppelin).")
        end
    elseif tonumber(cmd) then
        apply(tonumber(cmd), "display")
    else
        BJ:Print("Zep debug: /cc zep <displayID> | npc <npcID> | file <fileID> | skin [frames fps] | tower | fx | fire <id> | smoke <id> | boom <id> | sound [id] | next | prev | face <deg> | scale <n> | info | off")
    end
end
