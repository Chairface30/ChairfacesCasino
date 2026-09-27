--[[
    Chairface's Casino - UI/RouletteFrame.lua
    Roulette window: a fully animated wheel and ball on the left, the
    betting board (numbers grid plus outside bets) on the right.

    The wheel is drawn from 37 pocket frames positioned by angle around
    a circle, so "spinning" is just advancing one rotation angle each
    frame. The ball orbits the opposite way on an easing curve that is
    choreographed backward from the winning pocket - every client runs
    the identical show and the ball always lands on the broadcast result.
]]

local BJ = ChairfacesCasino
local UI = BJ.UI

UI.Roulette = {}
local RUI = UI.Roulette

local FRAME_W = 960
local FRAME_H = 600

-- Wheel geometry
local WHEEL_CX, WHEEL_CY = 190, 330   -- center, offsets from frame TOPLEFT
local RIM_SIZE = 344                  -- outer rim circle
local POCKET_R = 134                  -- pocket ring radius (wedge band center)
local HUB_SIZE = 178                  -- inner hub circle
local BALL_R_OUT = 156                -- ball orbit radius at full speed
local BALL_R_IN = POCKET_R            -- ball radius once it drops in
local TWO_PI = math.pi * 2

-- Tapered wedge with transparent surround: rotating the CONTENT of a
-- texture is only visible when the shape doesn't fill the quad, which
-- is why pockets can't just be rotated WHITE8x8 squares.
local WEDGE_TEX = "Interface\\AddOns\\Chairfaces Casino\\Textures\\Widgets\\wedge"

-- Board geometry (the marquee column sits between wheel and board)
local MARQUEE_X = 374
local BOARD_X, BOARD_Y = 426, 104     -- top-left of the zero cell area
local CELL_W, CELL_H, CELL_GAP = 34, 26, 2

local CIRCLE_TEX = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

function RUI:Initialize()
    if self.frame then return end
    self:CreateFrame()
end

-- Screen position for polar coordinates around the wheel center
-- (angle 0 = straight up, increasing clockwise)
local function polar(r, angle)
    return WHEEL_CX + r * math.sin(angle), -(WHEEL_CY - r * math.cos(angle))
end

function RUI:CreateFrame()
    local frame = CreateFrame("Frame", "ChairfacesCasinoRoulette", UIParent, "BackdropTemplate")
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
    frame:SetBackdropColor(0.05, 0.04, 0.06, 0.97)   -- dark fallback if art missing
    frame:SetBackdropBorderColor(0.6, 0.5, 0.2, 1)

    -- Table-felt background, same as the poker games and High-Lo. Sub-level 1
    -- keeps it above the backdrop's fill; aspect-fit texcoords match PokerFrame.
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
    title:SetText("|cffffd700Roulette|r")
    title:SetFont("Fonts\\FRIZQT__.TTF", 20, "OUTLINE")

    -- Close button (returns to the lobby)
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function()
        RUI:Hide()
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
        UI.Lobby:AttachHowToPlayButton(frame, "roulette", 8, -8)
    end

    -- Trixie deals here too - on the wheel's side of the table
    if UI.Lobby and UI.Lobby.AttachTrixie then
        local trixie = UI.Lobby:AttachTrixie(frame, "roulette")
        trixie:ClearAllPoints()
        trixie:SetPoint("RIGHT", frame, "LEFT", 0, 0)
    end

    -- Status line
    local status = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    status:SetPoint("TOP", title, "BOTTOM", 0, -6)
    status:SetWidth(FRAME_W - 40)
    status:SetText("")
    self.statusText = status

    self:CreateWheel()
    self:CreateMarquee()
    self:CreateBoard()
    self:CreateControls()
    self:CreateTestBar()

    -- Register Escape-key close
    if BJ.EscapeHandler then
        BJ.EscapeHandler:RegisterFrame("ChairfacesCasinoRoulette")
    end

    self:RenderWheel(0)
end

--[[
    THE WHEEL
]]

function RUI:CreateWheel()
    local frame = self.frame
    local RS = BJ.RouletteState

    -- Outer rim
    local rim = frame:CreateTexture(nil, "ARTWORK", nil, 0)
    rim:SetSize(RIM_SIZE, RIM_SIZE)
    rim:SetPoint("CENTER", frame, "TOPLEFT", WHEEL_CX, -WHEEL_CY)
    rim:SetTexture(CIRCLE_TEX)
    rim:SetVertexColor(0.35, 0.22, 0.08, 1)      -- polished wood

    local rimInner = frame:CreateTexture(nil, "ARTWORK", nil, 1)
    rimInner:SetSize(RIM_SIZE - 26, RIM_SIZE - 26)
    rimInner:SetPoint("CENTER", rim, "CENTER")
    rimInner:SetTexture(CIRCLE_TEX)
    rimInner:SetVertexColor(0.12, 0.1, 0.06, 1)  -- ball track shadow

    -- Pocket ring: one tapered wedge per pocket, repositioned AND
    -- re-rotated every render so each wedge always points at the hub
    self.pockets = {}
    for i = 1, 37 do
        local num = RS.WHEEL[i]
        local pocket = CreateFrame("Frame", nil, frame)
        pocket:SetSize(40, 40)   -- quad is bigger than the wedge so rotation never clips
        pocket:SetFrameLevel(frame:GetFrameLevel() + 2)

        local bg = pocket:CreateTexture(nil, "ARTWORK", nil, 2)
        bg:SetAllPoints()
        bg:SetTexture(WEDGE_TEX)
        if num == 0 then
            bg:SetVertexColor(0.05, 0.5, 0.1, 1)
        elseif RS.RED[num] then
            bg:SetVertexColor(0.62, 0.08, 0.08, 1)
        else
            bg:SetVertexColor(0.07, 0.07, 0.09, 1)
        end
        pocket.bg = bg

        local text = pocket:CreateFontString(nil, "OVERLAY")
        text:SetPoint("CENTER")
        text:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
        text:SetText(num)
        pocket.text = text

        self.pockets[i] = pocket
    end

    -- Hub
    local hub = frame:CreateTexture(nil, "ARTWORK", nil, 4)
    hub:SetSize(HUB_SIZE, HUB_SIZE)
    hub:SetPoint("CENTER", rim, "CENTER")
    hub:SetTexture(CIRCLE_TEX)
    hub:SetVertexColor(0.45, 0.32, 0.1, 1)

    local hubInner = frame:CreateTexture(nil, "ARTWORK", nil, 5)
    hubInner:SetSize(HUB_SIZE - 30, HUB_SIZE - 30)
    hubInner:SetPoint("CENTER", rim, "CENTER")
    hubInner:SetTexture(CIRCLE_TEX)
    hubInner:SetVertexColor(0.1, 0.14, 0.1, 1)

    -- Gold turret embellishment: four tapered spokes and four studs
    -- that rotate with the wheel, under a fixed gold center cap
    self.spokes = {}
    for k = 1, 4 do
        local spoke = frame:CreateTexture(nil, "ARTWORK", nil, 6)
        spoke:SetSize(44, 44)
        spoke:SetTexture(WEDGE_TEX)
        spoke:SetVertexColor(0.88, 0.7, 0.24, 1)
        self.spokes[k] = spoke
    end
    self.studs = {}
    for k = 1, 4 do
        local stud = frame:CreateTexture(nil, "ARTWORK", nil, 6)
        stud:SetSize(9, 9)
        stud:SetTexture(CIRCLE_TEX)
        stud:SetVertexColor(0.88, 0.7, 0.24, 1)
        self.studs[k] = stud
    end

    local cap = frame:CreateTexture(nil, "ARTWORK", nil, 7)
    cap:SetSize(46, 46)
    cap:SetPoint("CENTER", rim, "CENTER")
    cap:SetTexture(CIRCLE_TEX)
    cap:SetVertexColor(0.88, 0.7, 0.24, 1)

    local capInner = frame:CreateTexture(nil, "OVERLAY", nil, 0)
    capInner:SetSize(30, 30)
    capInner:SetPoint("CENTER", rim, "CENTER")
    capInner:SetTexture(CIRCLE_TEX)
    capInner:SetVertexColor(0.08, 0.12, 0.08, 1)

    -- The winning number, big and clear ABOVE the wheel once the ball
    -- drops (on the wheel itself it fought the turret for legibility)
    local hubNumber = frame:CreateFontString(nil, "OVERLAY")
    hubNumber:SetPoint("CENTER", frame, "TOPLEFT", WHEEL_CX, -(WHEEL_CY - RIM_SIZE / 2 - 22))
    hubNumber:SetFont("Fonts\\FRIZQT__.TTF", 30, "OUTLINE")
    hubNumber:SetText("")
    self.hubNumber = hubNumber

    -- The ball
    local ballFrame = CreateFrame("Frame", nil, frame)
    ballFrame:SetSize(12, 12)
    ballFrame:SetFrameLevel(frame:GetFrameLevel() + 6)
    local ball = ballFrame:CreateTexture(nil, "OVERLAY")
    ball:SetAllPoints()
    ball:SetTexture(CIRCLE_TEX)
    ball:SetVertexColor(1, 1, 1, 1)
    ballFrame:Hide()
    self.ballFrame = ballFrame

    -- Animation driver
    self.spinDriver = CreateFrame("Frame")
    self.spinDriver:Hide()

    self.wheelTheta = 0
end

-- Place every pocket, the turret, and optionally the ball for a wheel
-- angle. Each wedge is also rotated so it always points at the hub.
function RUI:RenderWheel(theta, ballAngle, ballRadius)
    local step = TWO_PI / 37
    local frame = self.frame
    for i = 1, 37 do
        local a = theta + (i - 1) * step
        local x, y = polar(POCKET_R, a)
        local pocket = self.pockets[i]
        pocket:ClearAllPoints()
        pocket:SetPoint("CENTER", frame, "TOPLEFT", x, y)
        if pocket.bg.SetRotation then
            pocket.bg:SetRotation(-a)
        end
    end

    -- Turret spokes and studs turn with the wheel
    for k = 1, 4 do
        local a = theta + (k - 1) * (TWO_PI / 4)
        local x, y = polar(46, a)
        local spoke = self.spokes[k]
        spoke:ClearAllPoints()
        spoke:SetPoint("CENTER", frame, "TOPLEFT", x, y)
        if spoke.SetRotation then
            spoke:SetRotation(-a)
        end

        local sa = a + TWO_PI / 8
        local sx, sy = polar(64, sa)
        self.studs[k]:ClearAllPoints()
        self.studs[k]:SetPoint("CENTER", frame, "TOPLEFT", sx, sy)
    end

    if ballAngle then
        local x, y = polar(ballRadius or BALL_R_IN, ballAngle)
        self.ballFrame:ClearAllPoints()
        self.ballFrame:SetPoint("CENTER", frame, "TOPLEFT", x, y)
        self.ballFrame:Show()
    end
end

-- Index (1..37) of a number on the wheel
local function pocketIndexOf(num)
    local RS = BJ.RouletteState
    for i = 1, 37 do
        if RS.WHEEL[i] == num then return i end
    end
    return 1
end

-- Start the spin show. Choreographed backward from the winning number:
-- both easings end at t=D with the ball exactly over the winning pocket.
function RUI:StartSpin()
    self:Initialize()
    local RS = BJ.RouletteState
    if not RS.winningNumber then return end

    local D = RS.SPIN_SECONDS
    local startTheta = self.wheelTheta or 0
    local wheelDelta = 3 * TWO_PI                      -- 3 lazy revolutions
    local thetaEnd = startTheta + wheelDelta

    local step = TWO_PI / 37
    local pocketAngle = (pocketIndexOf(RS.winningNumber) - 1) * step
    local ballTarget = thetaEnd + pocketAngle          -- pocket's final world angle
    local ballDelta = 6 * TWO_PI                       -- 6 revolutions, opposite way
    local ballStart = ballTarget + ballDelta

    local elapsed = 0
    self.hubNumber:SetText("")
    self.spinDriver:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        local p = elapsed / D
        if p >= 1 then
            self.spinDriver:SetScript("OnUpdate", nil)
            self.spinDriver:Hide()
            self.wheelTheta = thetaEnd % TWO_PI
            self:RenderWheel(self.wheelTheta, (self.wheelTheta + pocketAngle), BALL_R_IN)
            self.hubNumber:SetText(RS:NumberColor(RS.winningNumber) .. RS.winningNumber .. "|r")
            return
        end

        -- Wheel: cubic ease-out. Ball: quadratic ease-out, so it keeps
        -- pace longer, then falls inward over the last stretch.
        local easeW = 1 - (1 - p) ^ 3
        local easeB = 1 - (1 - p) ^ 2
        local theta = startTheta + wheelDelta * easeW
        local ballAngle = ballStart - ballDelta * easeB

        local drop = (p - 0.62) / 0.38
        if drop < 0 then drop = 0 end
        local ballRadius = BALL_R_OUT - (BALL_R_OUT - BALL_R_IN) * (drop * drop)

        self:RenderWheel(theta, ballAngle, ballRadius)
    end)
    self.spinDriver:Show()
end

function RUI:StopSpin()
    if self.spinDriver then
        self.spinDriver:SetScript("OnUpdate", nil)
        self.spinDriver:Hide()
    end
    if self.ballFrame then self.ballFrame:Hide() end
    if self.hubNumber then self.hubNumber:SetText("") end
end

--[[
    MARQUEE - the last 10 results, newest on top, between wheel and board
]]

function RUI:CreateMarquee()
    local frame = self.frame

    local header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", MARQUEE_X - 2, -(BOARD_Y - 16))
    header:SetText("|cffccaa66LAST 10|r")

    self.marqueeCells = {}
    for i = 1, 10 do
        local cell = CreateFrame("Frame", nil, frame)
        cell:SetSize(38, 20)
        cell:SetPoint("TOPLEFT", frame, "TOPLEFT", MARQUEE_X, -(BOARD_Y + (i - 1) * 22))

        local bg = cell:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.1, 0.1, 0.12, 0.6)
        cell.bg = bg

        local text = cell:CreateFontString(nil, "OVERLAY")
        text:SetPoint("CENTER")
        text:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
        text:SetText("")
        cell.text = text

        self.marqueeCells[i] = cell
    end
end

function RUI:RefreshMarquee()
    local RS = BJ.RouletteState
    for i = 1, 10 do
        local cell = self.marqueeCells[i]
        local n = RS.recentNumbers and RS.recentNumbers[i]
        if n then
            cell.text:SetText(n)
            cell.text:SetTextColor(1, 1, 1)
            if n == 0 then
                cell.bg:SetColorTexture(0.05, 0.45, 0.1, i == 1 and 1 or 0.75)
            elseif RS.RED[n] then
                cell.bg:SetColorTexture(0.55, 0.08, 0.08, i == 1 and 1 or 0.75)
            else
                cell.bg:SetColorTexture(0.08, 0.08, 0.1, i == 1 and 1 or 0.75)
            end
        else
            cell.text:SetText("")
            cell.bg:SetColorTexture(0.1, 0.1, 0.12, 0.35)
        end
    end
end

--[[
    THE BOARD
]]

local function cellColorFor(key)
    local RS = BJ.RouletteState
    local n = key:match("^n(%d+)$")
    if n then
        n = tonumber(n)
        if n == 0 then return 0.05, 0.45, 0.1 end
        if RS.RED[n] then return 0.55, 0.08, 0.08 end
        return 0.08, 0.08, 0.1
    end
    if key == "red" then return 0.55, 0.08, 0.08 end
    if key == "black" then return 0.08, 0.08, 0.1 end
    return 0.1, 0.22, 0.12  -- felt green for the other outside bets
end

function RUI:CreateBetCell(key, label, x, y, w, h)
    local frame = self.frame
    local RS = BJ.RouletteState

    local btn = CreateFrame("Button", nil, frame)
    btn:SetSize(w, h)
    btn:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -y)

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(cellColorFor(key))

    local border = btn:CreateTexture(nil, "BORDER")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(0.75, 0.65, 0.35, 0.5)
    border:SetDrawLayer("BACKGROUND", -1)

    btn:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")

    local text = btn:CreateFontString(nil, "OVERLAY")
    text:SetPoint("CENTER", 0, 3)
    text:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    text:SetText(label)

    -- Your chips on this spot
    local myBet = btn:CreateFontString(nil, "OVERLAY")
    myBet:SetPoint("BOTTOM", 0, 1)
    myBet:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
    myBet:SetTextColor(1, 0.84, 0)
    myBet:SetText("")
    btn.myBet = myBet

    -- Winning-spot glow at settlement
    local glow = btn:CreateTexture(nil, "OVERLAY", nil, 7)
    glow:SetAllPoints()
    glow:SetColorTexture(1, 0.84, 0, 0.35)
    glow:Hide()
    btn.glow = glow

    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:SetScript("OnClick", function(_, mouse)
        if BJ.RouletteMultiplayer then
            BJ.RouletteMultiplayer:PlaceBet(key, mouse == "RightButton" and -1 or 1)
        end
    end)

    btn:SetScript("OnEnter", function(self)
        local anyBets = false
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(RS:BetLabel(key) .. "  pays " .. RS:PayoutFor(key) .. ":1", 1, 0.82, 0)
        for _, name in ipairs(RS.playerOrder) do
            local amt = RS.players[name] and RS.players[name].bets[key]
            if amt and amt > 0 then
                GameTooltip:AddDoubleLine(name, amt .. "g", 1, 1, 1, 0.4, 1, 0.4)
                anyBets = true
            end
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    self.betCells[key] = btn
    return btn
end

function RUI:CreateBoard()
    self.betCells = {}

    local gridX = BOARD_X + 26   -- number grid starts right of the zero
    local pitchX = CELL_W + CELL_GAP
    local pitchY = CELL_H + CELL_GAP

    -- Zero (spans the three number rows)
    self:CreateBetCell("n0", "0", BOARD_X, BOARD_Y, 24, 3 * pitchY - CELL_GAP)

    -- 1-36: twelve columns, three rows (top row 3,6,...,36)
    for c = 1, 12 do
        for r = 0, 2 do
            local n = 3 * c - r
            self:CreateBetCell("n" .. n, tostring(n),
                gridX + (c - 1) * pitchX, BOARD_Y + r * pitchY, CELL_W, CELL_H)
        end
    end

    -- Column bets (right of the grid, aligned with their rows)
    local colX = gridX + 12 * pitchX
    self:CreateBetCell("c3", "2:1", colX, BOARD_Y, 30, CELL_H)
    self:CreateBetCell("c2", "2:1", colX, BOARD_Y + pitchY, 30, CELL_H)
    self:CreateBetCell("c1", "2:1", colX, BOARD_Y + 2 * pitchY, 30, CELL_H)

    -- Dozens
    local dozenY = BOARD_Y + 3 * pitchY + 2
    local dozenW = 4 * pitchX - CELL_GAP
    self:CreateBetCell("d1", "1st 12", gridX, dozenY, dozenW, CELL_H)
    self:CreateBetCell("d2", "2nd 12", gridX + 4 * pitchX, dozenY, dozenW, CELL_H)
    self:CreateBetCell("d3", "3rd 12", gridX + 8 * pitchX, dozenY, dozenW, CELL_H)

    -- Outside bets
    local outY = dozenY + pitchY + 2
    local outW = 2 * pitchX - CELL_GAP
    self:CreateBetCell("low", "1-18", gridX, outY, outW, CELL_H)
    self:CreateBetCell("even", "EVEN", gridX + 2 * pitchX, outY, outW, CELL_H)
    self:CreateBetCell("red", "RED", gridX + 4 * pitchX, outY, outW, CELL_H)
    self:CreateBetCell("black", "BLACK", gridX + 6 * pitchX, outY, outW, CELL_H)
    self:CreateBetCell("odd", "ODD", gridX + 8 * pitchX, outY, outW, CELL_H)
    self:CreateBetCell("high", "19-36", gridX + 10 * pitchX, outY, outW, CELL_H)

    -- Players + bets readout under the board
    local playersText = self.frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    playersText:SetPoint("TOPLEFT", self.frame, "TOPLEFT", BOARD_X, -(outY + CELL_H + 14))
    playersText:SetWidth(FRAME_W - BOARD_X - 30)
    playersText:SetJustifyH("LEFT")
    playersText:SetJustifyV("TOP")
    playersText:SetText("")
    self.playersText = playersText

    -- Result banner
    local resultText = self.frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    resultText:SetPoint("TOPLEFT", playersText, "BOTTOMLEFT", 0, -10)
    resultText:SetWidth(FRAME_W - BOARD_X - 30)
    resultText:SetJustifyH("LEFT")
    resultText:SetJustifyV("TOP")
    resultText:SetText("")
    self.resultText = resultText
end

-- Refresh chip labels and winning glows on every cell. Derby-style view:
-- everyone sees every bet on a spot. Your own stake stays green; the pooled
-- stake from the other players shows as a separate blue number so you can
-- always pick your own chips out at a glance. Hover lists everyone. (The bank
-- never bets, so for the host the whole spot is "others".)
function RUI:RefreshBoard()
    local RS = BJ.RouletteState
    local myName = UnitName("player")
    local me = RS.players[myName]
    local showGlow = (RS.phase == RS.PHASE.SETTLEMENT) and RS.winningNumber

    for key, cell in pairs(self.betCells) do
        local mine = (me and me.bets[key]) or 0
        local others = 0
        for _, name in ipairs(RS.playerOrder) do
            if name ~= myName then
                local b = RS.players[name] and RS.players[name].bets[key]
                others = others + (b or 0)
            end
        end
        local parts = {}
        if mine > 0 then parts[#parts + 1] = "|cff66ff66" .. mine .. "|r" end
        if others > 0 then parts[#parts + 1] = "|cff40b0ff" .. others .. "|r" end
        cell.myBet:SetText(table.concat(parts, "+"))
        if showGlow and RS:IsWinningKey(key, RS.winningNumber) then
            cell.glow:Show()
        else
            cell.glow:Hide()
        end
    end
end

--[[
    CONTROLS (bottom-left, under the wheel)
]]

function RUI:CreateControls()
    local frame = self.frame

    -- Chip stepper (host, table closed only)
    local chipLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    chipLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 60, -(WHEEL_CY + RIM_SIZE / 2 + 14))
    chipLabel:SetText("Chip:")
    self.chipLabel = chipLabel

    local chipDown = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    chipDown:SetSize(22, 22); chipDown:SetText("-")
    chipDown:SetPoint("LEFT", chipLabel, "RIGHT", 8, 0)
    self.chipDown = chipDown

    local chipVal = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    chipVal:SetWidth(48); chipVal:SetJustifyH("CENTER")
    chipVal:SetPoint("LEFT", chipDown, "RIGHT", 4, 0)
    self.chipVal = chipVal

    local chipUp = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    chipUp:SetSize(22, 22); chipUp:SetText("+")
    chipUp:SetPoint("LEFT", chipVal, "RIGHT", 4, 0)
    self.chipUp = chipUp

    -- Bets-per-player stepper (host, table closed only) - derby-style
    local betsLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    betsLabel:SetPoint("LEFT", chipUp, "RIGHT", 18, 0)
    betsLabel:SetText("Bets:")
    self.betsLabel = betsLabel

    local betsDown = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    betsDown:SetSize(22, 22); betsDown:SetText("-")
    betsDown:SetPoint("LEFT", betsLabel, "RIGHT", 8, 0)
    self.betsDown = betsDown

    local betsVal = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    betsVal:SetWidth(28); betsVal:SetJustifyH("CENTER")
    betsVal:SetPoint("LEFT", betsDown, "RIGHT", 4, 0)
    self.betsVal = betsVal

    local betsUp = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    betsUp:SetSize(22, 22); betsUp:SetText("+")
    betsUp:SetPoint("LEFT", betsVal, "RIGHT", 4, 0)
    self.betsUp = betsUp

    -- Fake play (fun games record no debts) rides the host-settings row
    if BJ.UI.Debts and BJ.UI.Debts.AttachFakePlayCheck then
        BJ.UI.Debts:AttachFakePlayCheck(frame, "LEFT", betsUp, "RIGHT", 12, 0)
    end

    local RS = BJ.RouletteState
    -- Last-hosted chip/bets, clamped in case CHIP_STEPS ever shrinks
    local savedIdx = BJ.HostSettings and tonumber(BJ.HostSettings:Get("rouletteChipIdx")) or 2
    self.chipIdx = math.max(1, math.min(#RS.CHIP_STEPS, savedIdx))
    self.betsCount = math.max(1, math.min(15,
        (BJ.HostSettings and tonumber(BJ.HostSettings:Get("rouletteBets")) or 5)))
    local function refreshChip()
        local RS2 = BJ.RouletteState
        local idle = (RS2.phase == RS2.PHASE.IDLE)
        local chip = idle and RS2.CHIP_STEPS[self.chipIdx] or RS2.chip
        self.chipVal:SetText((chip or 0) .. "g")
        self.betsVal:SetText(tostring(idle and self.betsCount or (RS2.maxBets or 5)))
    end
    self.RefreshChip = refreshChip

    chipDown:SetScript("OnClick", function()
        if self.chipIdx > 1 then self.chipIdx = self.chipIdx - 1; refreshChip() end
    end)
    chipUp:SetScript("OnClick", function()
        if self.chipIdx < #RS.CHIP_STEPS then self.chipIdx = self.chipIdx + 1; refreshChip() end
    end)
    betsDown:SetScript("OnClick", function()
        if self.betsCount > 1 then self.betsCount = self.betsCount - 1; refreshChip() end
    end)
    betsUp:SetScript("OnClick", function()
        if self.betsCount < 15 then self.betsCount = self.betsCount + 1; refreshChip() end
    end)

    -- Main + secondary action buttons
    local function makeButton(xOff)
        local btn = CreateFrame("Button", nil, frame, "BackdropTemplate")
        btn:SetSize(140, 32)
        btn:SetPoint("TOPLEFT", frame, "TOPLEFT", xOff, -(WHEEL_CY + RIM_SIZE / 2 + 44))
        btn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
        local text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        text:SetPoint("CENTER")
        btn.text = text
        return btn
    end

    local actionBtn = makeButton(40)
    actionBtn:SetScript("OnClick", function() RUI:OnActionClick() end)
    self.actionBtn = actionBtn

    local cancelBtn = makeButton(190)
    cancelBtn:SetScript("OnClick", function()
        if BJ.RouletteMultiplayer and BJ.RouletteMultiplayer.isHost then
            BJ.RouletteMultiplayer:CloseTable()
        end
        RUI:UpdateDisplay()
    end)
    self.cancelBtn = cancelBtn

    refreshChip()
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

function RUI:OnActionClick()
    local RS = BJ.RouletteState
    local RM = BJ.RouletteMultiplayer
    local myName = UnitName("player")

    if RS.phase == RS.PHASE.IDLE then
        if RM:HostTable(RS.CHIP_STEPS[self.chipIdx], self.betsCount) and BJ.HostSettings then
            -- Remember the chip/bets picks for the next table
            BJ.HostSettings:Set("rouletteChipIdx", self.chipIdx)
            BJ.HostSettings:Set("rouletteBets", self.betsCount)
        end
    elseif RS.phase == RS.PHASE.BETTING then
        if RM.isHost then
            RM:SpinWheel()
        elseif not RS.players[myName] then
            RM:RequestJoin()
        end
    elseif RS.phase == RS.PHASE.SETTLEMENT then
        if RM.isHost then
            RM:NextRound()
        end
    end

    self:UpdateDisplay()
end

--[[
    TEST BAR (visible only while /cc db test mode is on)
]]

function RUI:CreateTestBar()
    local bar = CreateFrame("Frame", nil, self.frame, "BackdropTemplate")
    bar:SetSize(260, 35)
    bar:SetPoint("TOP", self.frame, "BOTTOM", 0, -5)
    bar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
    bar:SetBackdropColor(0.15, 0.1, 0.2, 0.95)
    bar:SetBackdropBorderColor(1, 0.4, 1, 1)

    local label = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", 10, 0)
    label:SetText("|cffff00ffTEST|r")

    local addBtn = CreateFrame("Button", nil, bar, "BackdropTemplate")
    addBtn:SetSize(130, 24)
    addBtn:SetPoint("LEFT", label, "RIGHT", 8, 0)
    addBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    addBtn:SetBackdropColor(0.3, 0.2, 0.4, 1)
    addBtn:SetBackdropBorderColor(0.6, 0.4, 0.8, 1)
    addBtn.text = addBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    addBtn.text:SetPoint("CENTER")
    addBtn.text:SetText("+FAKE BETTOR")
    addBtn:SetScript("OnClick", function()
        if BJ.TestMode then BJ.TestMode:AddRouletteFakePlayers(1) end
    end)
    addBtn:SetScript("OnEnter", function(s) s:SetBackdropColor(0.4, 0.3, 0.5, 1) end)
    addBtn:SetScript("OnLeave", function(s) s:SetBackdropColor(0.3, 0.2, 0.4, 1) end)

    bar:Hide()
    self.testBar = bar
end

function RUI:RefreshTestBar()
    if not self.testBar then return end
    if BJ.TestMode and BJ.TestMode.enabled then
        self.testBar:Show()
    else
        self.testBar:Hide()
    end
end

--[[
    DISPLAY
]]

function RUI:UpdateDisplay()
    if not self.frame then return end

    local RS = BJ.RouletteState
    local RM = BJ.RouletteMultiplayer
    local myName = UnitName("player")
    local me = RS.players[myName]

    -- Clear FREE PLAY badge by default; the JOIN TABLE branch re-shows it.
    if BJ.UI and BJ.UI.Debts then
        BJ.UI.Debts:SetJoinFakeBadge(self.actionBtn, false)
    end

    self:RefreshBoard()
    self:RefreshMarquee()
    self.RefreshChip()

    -- Players readout
    if RS.phase ~= RS.PHASE.IDLE then
        local parts = {}
        for _, name in ipairs(RS.playerOrder) do
            local staked = RS:TotalStaked(name)
            local shown = name == myName and ("|cff88ff88" .. name .. "|r") or name
            table.insert(parts, shown .. " (" .. staked .. "g)")
        end
        local bank = RS.hostName and (" |cffccaa66Bank:|r " .. RS.hostName) or ""
        self.playersText:SetText("|cffccaa66PLAYERS (" .. #RS.playerOrder .. ")|r" .. bank ..
            (#parts > 0 and ("\n" .. table.concat(parts, ", ")) or "\n|cff888888(no seats taken yet)|r"))
    else
        self.playersText:SetText("")
    end

    -- Result banner
    if RS.phase == RS.PHASE.SETTLEMENT then
        self.resultText:SetText(RS:GetSettlementText())
    else
        self.resultText:SetText("")
    end

    -- Resting wheel shows the last result in its pocket
    if RS.phase ~= RS.PHASE.SPINNING then
        if RS.winningNumber then
            local step = TWO_PI / 37
            local idx = 1
            for i = 1, 37 do
                if RS.WHEEL[i] == RS.winningNumber then idx = i break end
            end
            self:RenderWheel(self.wheelTheta or 0, (self.wheelTheta or 0) + (idx - 1) * step, BALL_R_IN)
            self.hubNumber:SetText(RS:NumberColor(RS.winningNumber) .. RS.winningNumber .. "|r")
        else
            self:RenderWheel(self.wheelTheta or 0)
            self.ballFrame:Hide()
            self.hubNumber:SetText("")
        end
    end

    -- Phase chrome
    local inTestMode = BJ.TestMode and BJ.TestMode.enabled
    local grouped = IsInGroup() or IsInRaid() or inTestMode

    local chipAdjustable = (RS.phase == RS.PHASE.IDLE)
    self.chipDown:SetEnabled(chipAdjustable)
    self.chipUp:SetEnabled(chipAdjustable)
    self.betsDown:SetEnabled(chipAdjustable)
    self.betsUp:SetEnabled(chipAdjustable)
    self.cancelBtn:Hide()

    if RS.phase == RS.PHASE.IDLE then
        self.statusText:SetText(grouped and "Open a table - you deal, players bet against you."
            or "|cffff8800Join a party or raid to play.|r")
        styleButton(self.actionBtn, "OPEN TABLE", grouped, 0.15, 0.35, 0.15)

    elseif RS.phase == RS.PHASE.BETTING then
        if RM.isHost then
            self.statusText:SetText("Betting is open. Spin when the board is set.")
            styleButton(self.actionBtn, "SPIN", RS:AnyBets(), 0.35, 0.28, 0.1)
            self.cancelBtn:Show()
            styleButton(self.cancelBtn, "CLOSE TABLE", true, 0.35, 0.15, 0.15)
        elseif me then
            self.statusText:SetText("|cff00ff00Place your bets!|r Left-click adds a " ..
                RS.chip .. "g chip, right-click takes one back. (" ..
                RS:ChipsUsed(myName) .. "/" .. RS.maxBets .. " chips)")
            styleButton(self.actionBtn, "STAKED: " .. RS:TotalStaked(myName) .. "g", false)
        else
            self.statusText:SetText(BJ:SeatName(RS.hostName) .. " runs the table at " .. RS.chip .. "g a chip.")
            styleButton(self.actionBtn, "JOIN TABLE", true, 0.15, 0.35, 0.15)
            if BJ.UI and BJ.UI.Debts then
                BJ.UI.Debts:SetJoinFakeBadge(self.actionBtn, RS.fakePlay == true)
            end
        end

    elseif RS.phase == RS.PHASE.SPINNING then
        self.statusText:SetText("|cffffd700No more bets!|r")
        styleButton(self.actionBtn, "SPINNING...", false)

    elseif RS.phase == RS.PHASE.SETTLEMENT then
        self.statusText:SetText("|cffffd700" .. RS:NumberColor(RS.winningNumber or 0) ..
            (RS.winningNumber or "?") .. "|r|cffffd700 pays out!|r")
        if RM.isHost then
            styleButton(self.actionBtn, "NEXT ROUND", true, 0.15, 0.35, 0.15)
            self.cancelBtn:Show()
            styleButton(self.cancelBtn, "CLOSE TABLE", true, 0.35, 0.15, 0.15)
        else
            styleButton(self.actionBtn, "WAITING...", false)
        end
    end

    self:RefreshTestBar()
end

function RUI:Show()
    self:Initialize()
    self:UpdateDisplay()
    self.frame:Show()

    -- Show any deferred version warning now that a casino window is open
    if BJ.ShowPendingVersionWarning then
        BJ:ShowPendingVersionWarning()
    end
end

function RUI:Hide()
    if self.frame then
        self.frame:Hide()
    end
end
