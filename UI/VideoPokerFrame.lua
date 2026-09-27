--[[
    Chairface's Casino - UI/VideoPokerFrame.lua
    Solo Jacks-or-Better video poker on the persistent FAKE credit
    balance (BJ.Arcade) - the handheld Vegas classic. Bet, deal five,
    click cards to hold, draw, get paid by the table.
]]

local BJ = ChairfacesCasino
local UI = BJ.UI

UI.VideoPoker = {}
local VP = UI.VideoPoker

local FRAME_W = 620
local FRAME_H = 700

-- Game King paytable grid layout: hand names on the left, one pay column
-- per coin bet (1-5), the active column lit up in red like the real cabinet.
local PT_ROWH   = 15
local PT_TOPPAD = 22
local PT_NAME_W = 178
local PT_LPAD   = 10
local PT_W      = FRAME_W - 60
local PT_COLW   = (PT_W - PT_NAME_W - PT_LPAD - 8) / 5

local CARD_W, CARD_H = 92, 128
local CARD_GAP = 14

-- Multi-hand extras: each additional hand renders as a small overlapped fan
-- (rank corners stay readable, same trick as the blackjack rows) in a strip
-- between the paytable and the main cards.
local MH_CARD_W, MH_CARD_H = 44, 62
local MH_OVERLAP = 22
local MH_FAN_W = MH_CARD_W + 4 * MH_OVERLAP
local MH_GAP = 10
local MH_STRIP_H = MH_CARD_H + 20

-- Smaller cards for the video blackjack hands (more cards per row)
local BJ_CARD_W, BJ_CARD_H = 60, 84
local BJ_CARD_GAP = 6
local BJ_MAX_CARDS = 8

local CARD_PATH = "Interface\\AddOns\\Chairfaces Casino\\Textures\\cards\\"
-- Card flips rotate through the Kenney card-place variants so a five-card
-- deal doesn't machine-gun the same sample.
local function playCardSound()
    BJ:PlaySfx("Kenney\\card-place-" .. math.random(4) .. ".ogg")
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

local function cardBackTexture()
    local back = BJ.db and BJ.db.settings and BJ.db.settings.cardBack
    if back and back ~= "" and back ~= "classic" then
        return CARD_PATH .. "back_" .. back
    end
    return CARD_PATH .. "back"
end

-- A blinking "GAME OVER" stamp. Lives on its own high frame level so it
-- draws over card/board children; mouse-transparent so clicks pass through.
local function makeGameOverOverlay(parent, yOfs, height)
    local f = CreateFrame("Frame", nil, parent)
    f:SetPoint("LEFT", parent, "LEFT", 0, yOfs or 0)
    f:SetPoint("RIGHT", parent, "RIGHT", 0, yOfs or 0)
    f:SetHeight(height or 58)
    f:SetFrameLevel(parent:GetFrameLevel() + 20)

    local strip = f:CreateTexture(nil, "BACKGROUND")
    strip:SetAllPoints()
    strip:SetColorTexture(0, 0, 0, 0.55)

    local text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    text:SetPoint("CENTER")
    text:SetFont("Fonts\\FRIZQT__.TTF", 44, "THICKOUTLINE")
    text:SetTextColor(1, 0.1, 0.1)
    text:SetText("GAME OVER")

    local pulse = 0
    f:SetScript("OnUpdate", function(_, dt)
        pulse = pulse + dt * 3.2
        text:SetAlpha(0.45 + 0.55 * math.abs(math.sin(pulse)))
    end)
    f:Hide()
    return f
end

function VP:Initialize()
    if self.frame then return end
    self:CreateFrame()
end

function VP:CreateFrame()
    local frame = CreateFrame("Frame", "ChairfacesCasinoVideoPoker", UIParent, "BackdropTemplate")
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
    frame:SetBackdropColor(0.01, 0.03, 0.30, 0.97)   -- Game King blue
    frame:SetBackdropBorderColor(0.95, 0.8, 0.1, 1)
    frame:Hide()
    self.frame = frame

    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("|cffffd700Video Poker|r")
    title:SetFont("Fonts\\FRIZQT__.TTF", 18, "OUTLINE")
    self.title = title

    -- Close button (returns to the lobby)
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function()
        VP:Hide()
        if UI.Lobby then
            UI.Lobby:Show()
        end
    end)

    -- How to Play
    if UI.Lobby and UI.Lobby.AttachHowToPlayButton then
        UI.Lobby:AttachHowToPlayButton(frame, "videopoker", 8, -8)
    end

    -- Trixie deals this one personally
    if UI.Lobby and UI.Lobby.AttachTrixie then
        UI.Lobby:AttachTrixie(frame)
    end

    -- Game-mode tabs: Video Poker | Video Blackjack | Video Keno
    local function makeTab(label, mode, anchor, xoff)
        local b = CreateFrame("Button", nil, frame, "BackdropTemplate")
        b:SetSize(118, 22)
        if anchor then b:SetPoint("LEFT", anchor, "RIGHT", xoff or 6, 0)
        else b:SetPoint("TOP", title, "BOTTOM", -124, -4) end
        b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        b.text:SetPoint("CENTER")
        b.text:SetText(label)
        b.mode = mode
        b:SetScript("OnClick", function() VP:SetGameMode(mode) end)
        return b
    end
    self.pokerTab = makeTab("Video Poker", "poker")
    self.bjTab = makeTab("Video Blackjack", "blackjack", self.pokerTab)
    self.kenoTab = makeTab("Video Keno", "keno", self.bjTab)

    -- "Show Off" brag button (posts your credit total to chat)
    local bragBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    bragBtn:SetSize(96, 20)
    bragBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -34)
    bragBtn:SetText("Show Off")
    bragBtn:SetScript("OnClick", function() if BJ.ShareCredits then BJ:ShareCredits() end end)
    bragBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Brag your credit total to chat")
        GameTooltip:Show()
    end)
    bragBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- "Send" gift button (one-way credit transfer to another player)
    local sendBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    sendBtn:SetSize(96, 20)
    sendBtn:SetPoint("TOP", bragBtn, "BOTTOM", 0, -2)
    sendBtn:SetText("Send Credits")
    sendBtn:SetScript("OnClick", function() BJ:ShowSendCreditsDialog() end)
    sendBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Gift arcade credits to another player (one-way)")
        GameTooltip:Show()
    end)
    sendBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- "Buy Credits" helper (mail gold to the casino banker)
    local buyBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    buyBtn:SetSize(96, 20)
    buyBtn:SetPoint("TOP", sendBtn, "BOTTOM", 0, -2)
    buyBtn:SetText("Buy Credits")
    buyBtn:SetScript("OnClick", function() BJ:ShowBuyCreditsDialog() end)
    buyBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Buy credits: mail gold to the casino")
        GameTooltip:AddLine("10g = " .. (BJ.Arcade.CREDITS_PER_10G or 10000) .. " credits", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    buyBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Debug-only "Grant" button: comp any character any number of credits.
    -- Only built for allow-listed characters (the same gate as /cc db).
    if BJ.Arcade and BJ.Arcade:CanGrantCredits() then
        local grantBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        grantBtn:SetSize(96, 20)
        grantBtn:SetPoint("TOP", buyBtn, "BOTTOM", 0, -2)
        grantBtn:SetText("|cffff00ffGrant|r")
        grantBtn:SetScript("OnClick", function()
            if BJ.ShowGrantCreditsDialog then BJ:ShowGrantCreditsDialog() end
        end)
        grantBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Debug: grant credits to any character")
            GameTooltip:AddLine("Costs you nothing - house money.", 0.8, 0.8, 0.8)
            GameTooltip:Show()
        end)
        grantBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        self.grantBtn = grantBtn
    end

    -- Credits readout (centred under the middle tab)
    local credits = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    credits:SetPoint("TOP", self.bjTab, "BOTTOM", 0, -6)
    credits:SetFont("Fonts\\FRIZQT__.TTF", 15, "OUTLINE")
    credits:SetText("")
    self.creditsText = credits

    -- Variation selector: click to cycle Jacks or Better / Bonus Poker /
    -- Double Double Bonus / Deuces Wild.
    local varBtn = CreateFrame("Button", nil, frame, "BackdropTemplate")
    varBtn:SetSize(260, 22)
    varBtn:SetPoint("TOP", credits, "BOTTOM", 0, -6)
    varBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    varBtn:SetBackdropColor(0.1, 0.16, 0.24, 1)
    varBtn:SetBackdropBorderColor(0.4, 0.55, 0.7, 1)
    varBtn.text = varBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    varBtn.text:SetPoint("CENTER")
    varBtn:SetScript("OnClick", function() VP:CycleVariation() end)
    varBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Click to change video-poker game")
        GameTooltip:Show()
    end)
    varBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.varBtn = varBtn

    -- Hand-count selector: cycles 1 / 3 / 5 hands (Triple / Five Play).
    local handsBtn = CreateFrame("Button", nil, frame, "BackdropTemplate")
    handsBtn:SetSize(110, 22)
    handsBtn:SetPoint("LEFT", varBtn, "RIGHT", 8, 0)
    handsBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    handsBtn:SetBackdropColor(0.1, 0.16, 0.24, 1)
    handsBtn:SetBackdropBorderColor(0.4, 0.55, 0.7, 1)
    handsBtn.text = handsBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    handsBtn.text:SetPoint("CENTER")
    handsBtn:SetScript("OnClick", function() VP:CycleHands() end)
    handsBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Play 1, 3 or 5 hands at once")
        GameTooltip:AddLine("Held cards apply to every hand; each hand", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("draws from its own deck. Bet is per hand.", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    handsBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.handsBtn = handsBtn

    -- Paytable (two columns of rows; winning row lights up). Rows are built
    -- from the current variation and rebuilt when it changes.
    local payFrame = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    payFrame:SetSize(FRAME_W - 60, 96)
    payFrame:SetPoint("TOP", varBtn, "BOTTOM", 0, -8)
    payFrame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    payFrame:SetBackdropColor(0, 0.01, 0.42, 0.95)
    payFrame:SetBackdropBorderColor(0.95, 0.8, 0.1, 1)
    self.payFrame = payFrame
    self.payRows = {}
    self:BuildPaytable()

    -- The five cards (flow below the paytable, which varies in height).
    -- The area leaves a band under the cards for the HELD tags so they
    -- never collide with the result banner.
    local cardArea = CreateFrame("Frame", nil, frame)
    cardArea:SetSize(5 * CARD_W + 4 * CARD_GAP, CARD_H + 26)
    cardArea:SetPoint("TOP", payFrame, "BOTTOM", 0, -16)

    self.cards = {}
    for i = 1, 5 do
        local btn = CreateFrame("Button", nil, cardArea)
        btn:SetSize(CARD_W, CARD_H)
        btn:SetPoint("TOPLEFT", (i - 1) * (CARD_W + CARD_GAP), 0)

        local tex = btn:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        tex:SetTexture(cardBackTexture())
        btn.tex = tex

        local held = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        held:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
        held:SetPoint("TOP", btn, "BOTTOM", 0, -3)
        held:SetText("|cffffe100HELD|r")
        held:Hide()
        btn.heldText = held

        btn:SetScript("OnClick", function() VP:ToggleHold(i) end)
        self.cards[i] = btn
    end
    self.cardArea = cardArea

    -- Multi-hand strip: up to four extra-hand fans, sitting between the
    -- paytable and the main cards (cardArea is re-anchored below it when
    -- more than one hand is in play - see ApplyHandLayout).
    local multiArea = CreateFrame("Frame", nil, frame)
    multiArea:SetSize(4 * MH_FAN_W + 3 * MH_GAP, MH_STRIP_H)
    multiArea:SetPoint("TOP", payFrame, "BOTTOM", 0, -8)
    multiArea:Hide()
    self.multiArea = multiArea

    self.extraFans = {}
    for f = 1, 4 do
        local holder = CreateFrame("Frame", nil, multiArea)
        holder:SetSize(MH_FAN_W, MH_CARD_H)
        local texs = {}
        for c = 1, 5 do
            local tex = holder:CreateTexture(nil, "ARTWORK", nil, c)
            tex:SetSize(MH_CARD_W, MH_CARD_H)
            tex:SetPoint("LEFT", holder, "LEFT", (c - 1) * MH_OVERLAP, 0)
            texs[c] = tex
        end
        local label = holder:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("TOP", holder, "BOTTOM", 0, -2)
        label:SetWidth(MH_FAN_W + MH_GAP)
        self.extraFans[f] = { holder = holder, texs = texs, label = label }
    end

    -- "GAME OVER" stamped across the cards between hands (blinks until the
    -- next deal). Blackjack and keno get their own stamps on their panels.
    self.gameOverFrame = makeGameOverOverlay(cardArea, -5, 58)

    -- Result banner
    local result = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    result:SetPoint("TOP", cardArea, "BOTTOM", 0, -10)
    result:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE")
    result:SetText("")
    self.resultText = result

    -- Game King meter bar: WIN / CREDIT / BET across the bottom of the play
    -- field. The WIN meter rolls up rather than snapping to the payout.
    local meter = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    meter:SetSize(PT_W, 46)
    meter:SetPoint("TOP", result, "BOTTOM", 0, -8)
    meter:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    meter:SetBackdropColor(0, 0, 0, 0.85)
    meter:SetBackdropBorderColor(0.95, 0.8, 0.1, 1)
    local function meterFS(point, x)
        local fs = meter:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        fs:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE")
        fs:SetPoint(point, x or 0, 7)
        return fs
    end
    self.meterWinFS = meterFS("LEFT", 14)
    self.meterCreditFS = meterFS("CENTER")
    self.meterBetFS = meterFS("RIGHT", -14)
    -- second row: best win + refills, per game mode
    local meterSub = meter:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    meterSub:SetPoint("BOTTOM", 0, 4)
    self.meterSubFS = meterSub
    self.meterFrame = meter
    self.winShown = 0

    -- Bet controls + deal/draw
    local betLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    betLabel:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 40, 30)
    betLabel:SetText("Bet:")

    local betDown = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    betDown:SetSize(22, 22); betDown:SetText("-")
    betDown:SetPoint("LEFT", betLabel, "RIGHT", 8, 0)
    self.betDown = betDown

    local betVal = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    betVal:SetWidth(62); betVal:SetJustifyH("CENTER")
    betVal:SetPoint("LEFT", betDown, "RIGHT", 4, 0)
    self.betVal = betVal

    local betUp = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    betUp:SetSize(22, 22); betUp:SetText("+")
    betUp:SetPoint("LEFT", betVal, "RIGHT", 4, 0)
    self.betUp = betUp

    local maxBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    maxBtn:SetSize(78, 22); maxBtn:SetText("Max Bet")
    maxBtn:SetPoint("LEFT", betUp, "RIGHT", 12, 0)
    maxBtn:SetScript("OnClick", function() VP:OnMaxBet() end)
    self.maxBtn = maxBtn

    self.bet = 1
    -- the steppers walk the shared high-roller ladder (1..5, 10, 15, 25 ...
    -- all the way to 100,000)
    betDown:SetScript("OnClick", function()
        local nxt = BJ.Arcade:NextBetStep(self.bet, -1)
        if nxt ~= self.bet then self.bet = nxt; self:UpdateDisplay() end
    end)
    betUp:SetScript("OnClick", function()
        local nxt = BJ.Arcade:NextBetStep(self.bet, 1)
        if nxt ~= self.bet then
            self.bet = nxt
            BJ:PlaySfx("Arcade\\coin_insert.ogg")
            self:UpdateDisplay()
        end
    end)

    local dealBtn = CreateFrame("Button", nil, frame, "BackdropTemplate")
    dealBtn:SetSize(150, 34)
    dealBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -40, 24)
    dealBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
    dealBtn.text = dealBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dealBtn.text:SetPoint("CENTER")
    dealBtn:SetScript("OnClick", function()
        if VP.mode == "blackjack" then VP:OnBJDeal()
        elseif VP.mode == "keno" then VP:OnKenoDraw()
        else VP:OnDealDraw() end
    end)
    self.dealBtn = dealBtn

    -- Poker-only widgets (hidden in the other modes). The meter bar is NOT
    -- here - WIN/CREDIT/BET stays up in all three games; one machine.
    -- multiArea is deliberately absent: it only shows when hands > 1
    -- (ApplyHandLayout owns it).
    self.pokerWidgets = { self.varBtn, self.handsBtn, self.payFrame, cardArea, result }

    -- ===== Video Blackjack panel (hidden in other modes) =====
    self:CreateBlackjackPanel()

    -- ===== Video Keno panel (hidden in other modes) =====
    self:CreateKenoPanel()

    if BJ.EscapeHandler then
        BJ.EscapeHandler:RegisterFrame("ChairfacesCasinoVideoPoker")
    end

    self.game = nil     -- poker hand in progress
    self.bjGame = nil   -- blackjack hand in progress
    self.mode = "poker"
    self.holds = {}
    self:ApplyHandLayout()
end

-- Re-flow the poker column for the current hand count: with more than one
-- hand the paytable compacts (BuildPaytable reads the count) and the main
-- cards drop below the extras strip.
function VP:ApplyHandLayout()
    local hands = BJ.Arcade.Poker:GetHandCount()
    local multi = hands > 1

    self:BuildPaytable()

    self.cardArea:ClearAllPoints()
    if multi then
        self.cardArea:SetPoint("TOP", self.multiArea, "BOTTOM", 0, -8)
    else
        self.cardArea:SetPoint("TOP", self.payFrame, "BOTTOM", 0, -16)
    end
    self.multiArea:SetShown(multi and self.mode == "poker")

    -- lay out hands-1 fans, centred in the strip
    local n = hands - 1
    for f = 1, 4 do
        local fan = self.extraFans[f]
        if f <= n then
            local width = n * MH_FAN_W + (n - 1) * MH_GAP
            local x = -width / 2 + (f - 1) * (MH_FAN_W + MH_GAP) + MH_FAN_W / 2
            fan.holder:ClearAllPoints()
            fan.holder:SetPoint("TOP", self.multiArea, "TOP", x, 0)
            fan.holder:Show()
        else
            fan.holder:Hide()
        end
    end

    if self.handsBtn then
        self.handsBtn.text:SetText("|cffffffff< |r|cff88ccff" ..
            (multi and (hands .. " HANDS") or "1 HAND") .. "|r|cffffffff >|r")
    end

    self:RenderExtraHands(self.lastExtras)
end

-- Paint the extra-hand fans: faces + result labels once drawn; while a
-- hand is LIVE, cards you hold show face-up in every fan immediately
-- (they're shared by all hands) and the rest stay face-down.
function VP:RenderExtraHands(extras)
    local hands = BJ.Arcade.Poker:GetHandCount()
    local backTex = cardBackTexture()
    local live = self.game   -- mid-hand: mirror the holds into the fans
    for f = 1, hands - 1 do
        local fan = self.extraFans[f]
        local res = extras and extras[f]
        for c = 1, 5 do
            if res then
                local card = res.hand[c]
                fan.texs[c]:SetTexture(CARD_PATH .. card.rank .. "_" .. card.suit)
            elseif live and self.holds[c] and live.dealt and live.dealt[c] then
                local card = live.dealt[c]
                fan.texs[c]:SetTexture(CARD_PATH .. card.rank .. "_" .. card.suit)
            else
                fan.texs[c]:SetTexture(backTex)
            end
        end
        if res then
            if res.payout > 0 then
                fan.label:SetText("|cff00ff00" .. res.name .. " +" .. fmtBet(res.payout) .. "|r")
            else
                fan.label:SetText("|cff666666No pay|r")
            end
        else
            fan.label:SetText("")
        end
    end
end

-- Cycle 1 -> 3 -> 5 hands (only between hands).
function VP:CycleHands()
    if self.mode ~= "poker" or self.game or self.cardAnim then return end
    BJ.Arcade.Poker:CycleHandCount()
    self.lastExtras = nil
    BJ:PlaySfx("Arcade\\coin_insert.ogg")
    self:ApplyHandLayout()
    self:UpdateDisplay()
end

-- The keno board: 80 numbers in an 8x10 grid, click to pick up to 10.
function VP:CreateKenoPanel()
    local frame = self.frame
    local Keno = BJ.Arcade.Keno

    local panel = CreateFrame("Frame", nil, frame)
    panel:SetPoint("TOP", self.creditsText, "BOTTOM", 0, -10)
    panel:SetPoint("LEFT", frame, "LEFT", 20, 0)
    panel:SetPoint("RIGHT", frame, "RIGHT", -20, 0)
    panel:SetHeight(390)
    panel:Hide()
    self.kenoPanel = panel

    local COLS, CW, GAP = 10, 38, 4
    local gridW = COLS * CW + (COLS - 1) * GAP
    local gridFrame = CreateFrame("Frame", nil, panel)
    gridFrame:SetSize(gridW, 8 * (30 + GAP))
    gridFrame:SetPoint("TOP", 0, -26)

    self.kenoPicks = {}
    self.kenoCells = {}
    for n = 1, Keno.NUMBERS do
        local col = (n - 1) % COLS
        local row = math.floor((n - 1) / COLS)
        local cell = CreateFrame("Button", nil, gridFrame, "BackdropTemplate")
        cell:SetSize(CW, 30)
        cell:SetPoint("TOPLEFT", col * (CW + GAP), -row * (30 + GAP))
        cell:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        cell.text = cell:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        cell.text:SetPoint("CENTER")
        cell.text:SetText(tostring(n))
        cell.num = n
        cell:SetScript("OnClick", function() VP:KenoTogglePick(n) end)
        self.kenoCells[n] = cell
    end

    -- blinking GAME OVER between draws (mouse-transparent: picking numbers
    -- underneath still works)
    self.kenoGameOver = makeGameOverOverlay(panel, 20, 58)

    -- picks readout + clear button above the grid
    local picksFS = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    picksFS:SetPoint("BOTTOMLEFT", gridFrame, "TOPLEFT", 0, 6)
    self.kenoPicksText = picksFS

    local clearBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    clearBtn:SetSize(70, 20)
    clearBtn:SetPoint("BOTTOMRIGHT", gridFrame, "TOPRIGHT", 0, 4)
    clearBtn:SetText("Clear")
    clearBtn:SetScript("OnClick", function() VP:KenoClearPicks() end)
    self.kenoClearBtn = clearBtn

    -- result banner + pay ladder for the current pick count
    local kenoResult = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    kenoResult:SetPoint("TOP", gridFrame, "BOTTOM", 0, -8)
    kenoResult:SetFont("Fonts\\FRIZQT__.TTF", 15, "OUTLINE")
    self.kenoResultText = kenoResult

    local ladder = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ladder:SetPoint("TOP", kenoResult, "BOTTOM", 0, -6)
    ladder:SetWidth(gridW)
    self.kenoLadderText = ladder
end

-- Build the blackjack table (dealer row centred up top, up to four player
-- hands centred beneath - splits and resplits fan out side by side). Lives in
-- the same cabinet; SetGameMode shows/hides it against the poker widgets.
local BJ_OVERLAP = 22      -- px each additional card peeks out from the stack
local BJ_HAND_GAP = 18     -- px between split hands

function VP:CreateBlackjackPanel()
    local frame = self.frame

    local panel = CreateFrame("Frame", nil, frame)
    panel:SetPoint("TOP", self.creditsText, "BOTTOM", 0, -14)
    panel:SetPoint("LEFT", frame, "LEFT", 20, 0)
    panel:SetPoint("RIGHT", frame, "RIGHT", -20, 0)
    panel:SetHeight(320)
    panel:Hide()
    self.bjPanel = panel

    -- Dealer: label centred over a pooled, centred card row.
    local dealerLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    dealerLabel:SetPoint("TOP", panel, "TOP", 0, -2)
    self.bjDealerLabel = dealerLabel

    local dealerRow = CreateFrame("Frame", nil, panel)
    dealerRow:SetPoint("TOP", dealerLabel, "BOTTOM", 0, -4)
    dealerRow:SetSize(1, BJ_CARD_H)
    self.bjDealerRow = dealerRow
    self.bjDealerCards = {}
    for i = 1, BJ_MAX_CARDS do
        local tex = dealerRow:CreateTexture(nil, "ARTWORK", nil, i - 8)  -- sublayer range is -8..7
        tex:SetSize(BJ_CARD_W, BJ_CARD_H)
        tex:Hide()
        self.bjDealerCards[i] = tex
    end

    -- Player: a centred strip of up to four hand blocks. Each block owns a
    -- card pool, a value label above and a result label below; the active
    -- hand gets a gold underline.
    local handStrip = CreateFrame("Frame", nil, panel)
    handStrip:SetPoint("TOP", dealerRow, "BOTTOM", 0, -40)
    handStrip:SetSize(1, BJ_CARD_H + 40)
    self.bjHandStrip = handStrip

    self.bjHands = {}
    local Blackjack = BJ.Arcade and BJ.Arcade.Blackjack
    local maxHands = (Blackjack and Blackjack.MAX_HANDS) or 4
    for h = 1, maxHands do
        local block = CreateFrame("Frame", nil, handStrip)
        block:SetSize(BJ_CARD_W, BJ_CARD_H)
        block.label = block:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        block.label:SetPoint("BOTTOM", block, "TOP", 0, 4)
        block.result = block:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        block.result:SetPoint("TOP", block, "BOTTOM", 0, -4)
        block.marker = block:CreateTexture(nil, "OVERLAY")
        block.marker:SetColorTexture(1, 0.85, 0.2, 0.9)
        block.marker:SetPoint("TOPLEFT", block, "BOTTOMLEFT", 0, -1)
        block.marker:SetPoint("TOPRIGHT", block, "BOTTOMRIGHT", 0, -1)
        block.marker:SetHeight(3)
        block.cards = {}
        for i = 1, BJ_MAX_CARDS do
            local tex = block:CreateTexture(nil, "ARTWORK", nil, i - 8)  -- sublayer range is -8..7
            tex:SetSize(BJ_CARD_W, BJ_CARD_H)
            tex:Hide()
            block.cards[i] = tex
        end
        block:Hide()
        self.bjHands[h] = block
    end

    -- blinking GAME OVER between rounds
    self.bjGameOver = makeGameOverOverlay(panel, -40, 58)

    -- Result banner
    local bjResult = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    bjResult:SetPoint("BOTTOM", panel, "BOTTOM", 0, 2)
    bjResult:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE")
    bjResult:SetText("")
    self.bjResultText = bjResult

    -- Action buttons in the bottom-right corner (where DEAL sits between
    -- hands), well clear of the bet controls on the bottom-left.
    local function actionBtn(label, onClick)
        local b = CreateFrame("Button", nil, frame, "BackdropTemplate")
        b:SetSize(72, 30)
        b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        b.text:SetPoint("CENTER")
        b.text:SetText(label)
        b:SetScript("OnClick", onClick)
        b:Hide()
        return b
    end
    self.bjSplitBtn  = actionBtn("SPLIT",  function() VP:OnBJSplit() end)
    self.bjDoubleBtn = actionBtn("DOUBLE", function() VP:OnBJDouble() end)
    self.bjStandBtn  = actionBtn("STAND",  function() VP:OnBJStand() end)
    self.bjHitBtn    = actionBtn("HIT",    function() VP:OnBJHit() end)
    self.bjSplitBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 24)
    self.bjDoubleBtn:SetPoint("RIGHT", self.bjSplitBtn, "LEFT", -8, 0)
    self.bjStandBtn:SetPoint("RIGHT", self.bjDoubleBtn, "LEFT", -8, 0)
    self.bjHitBtn:SetPoint("RIGHT", self.bjStandBtn, "LEFT", -8, 0)
end

-- Lay a pooled card row out centred in its holder: first card full, the rest
-- peeking out by BJ_OVERLAP.
local function layoutCardRow(holder, pool, cards, hidden, backTex)
    local n = #cards
    local width = (n > 0) and (BJ_CARD_W + (n - 1) * BJ_OVERLAP) or 1
    holder:SetWidth(width)
    for i = 1, #pool do
        local tex = pool[i]
        local card = cards[i]
        if card then
            tex:ClearAllPoints()
            tex:SetPoint("LEFT", holder, "LEFT", (i - 1) * BJ_OVERLAP, 0)
            if hidden and hidden[i] then
                tex:SetTexture(backTex)
            else
                tex:SetTexture(CARD_PATH .. card.rank .. "_" .. card.suit)
            end
            tex:Show()
        else
            tex:Hide()
        end
    end
    return width
end

function VP:ToggleHold(i)
    if not self.game or self.cardAnim then return end   -- holds only mid-hand
    self.holds[i] = not self.holds[i]
    self.cards[i].heldText:SetShown(self.holds[i])
    self:RenderExtraHands(nil)   -- held cards show in every fan right away
    BJ:PlaySfx("Kenney\\chip-lay-" .. math.random(3) .. ".ogg")
end

-- Flip the given card slots over one at a time (deal cadence) and run onDone
-- when the last card lands. The hand is already decided - this is theatre.
function VP:AnimateCards(indices, onDone)
    if #indices == 0 then
        if onDone then onDone() end
        return
    end
    self.cardAnim = true
    local hand = (self.game and self.game.hand) or self.lastHand
    for _, i in ipairs(indices) do
        self.cards[i].tex:SetTexture(cardBackTexture())
    end
    local step = 0
    local function flip()
        step = step + 1
        local idx = indices[step]
        if not idx then
            self.cardAnim = false
            if onDone then onDone() end
            return
        end
        local card = hand and hand[idx]
        if card then
            self.cards[idx].tex:SetTexture(CARD_PATH .. card.rank .. "_" .. card.suit)
        end
        playCardSound()
        C_Timer.After(0.16, flip)
    end
    C_Timer.After(0.05, flip)
end

function VP:OnDealDraw()
    local Arcade = BJ.Arcade
    local Poker = Arcade.Poker
    if self.cardAnim then return end

    if self.game then
        -- DRAW: finish the hand; only the replaced cards flip at a cadence
        local replaced = {}
        for i = 1, 5 do
            if not self.holds[i] then replaced[#replaced + 1] = i end
        end
        local numHands = self.game.numHands or 1
        local result = Poker:Draw(self.game, self.holds)
        self.lastHand = self.game.hand
        self.game = nil
        self:RenderCards()   -- shows held cards; AnimateCards flips the rest

        self:AnimateCards(replaced, function()
            self.lastResultKey = result.key
            self.currentKey = nil
            self.lastExtras = result.extras
            self:RenderExtraHands(result.extras)
            if result.payout > 0 then
                if numHands > 1 then
                    local winners = (result.key and 1 or 0)
                    for _, r in ipairs(result.extras or {}) do
                        if r.payout > 0 then winners = winners + 1 end
                    end
                    self.resultText:SetText(string.format(
                        "|cff00ff00%d of %d hands pay: +%s|r", winners, numHands, fmtBig(result.payout)))
                else
                    self.resultText:SetText("|cff00ff00" .. result.name .. "|r")
                end
                self.winSounds = {}
                if result.payout >= 20 * (self.bet or 1) * numHands then
                    local _, h1 = BJ:PlaySfx("Arcade\\jackpot.ogg", "Master")
                    local _, h2 = BJ:PlaySfx("Arcade\\coin_shower.ogg")
                    self.winSounds[#self.winSounds + 1] = h1
                    self.winSounds[#self.winSounds + 1] = h2
                    UI.Lobby:TrixieReact(self.frame, "love", 5)
                else
                    UI.Lobby:TrixieReact(self.frame, "win", 4)
                end
                -- no one-shot payout sample: the coin.ogg roll-up loop IS
                -- the payout sound
                self:RollUpWin(result.payout)
            else
                self.resultText:SetText("|cffff2020No pay - deal again!|r")
            end
            -- Every finished hand - win or lose - ends with GAME OVER
            -- blinking over the cards until the next deal.
            self:UpdateDisplay()
        end)
    else
        -- DEAL: start a hand (or beg for credits)
        if Arcade:GetCredits() < 1 then
            local ok, refills = Arcade:CompMe()
            if ok then
                BJ:Print("|cff00ff00The pit boss comps you " .. Arcade.COMP_AMOUNT ..
                    " credits.|r (Refill #" .. refills .. " - she's keeping count.)")
                self:UpdateDisplay()
            end
            return
        end

        local game, err = Poker:Deal(self.bet)
        if not game then
            BJ:Print("|cffff8800" .. (err or "Cannot deal.") .. "|r")
            return
        end

        self.game = game
        self.holds = {}
        self.lastResultKey = nil
        self.currentKey = nil
        self.lastExtras = nil
        self:RenderExtraHands(nil)   -- extras face-down while you pick holds
        self:FinishRollupNow()
        self.resultText:SetText("|cff88ccffClick cards to HOLD, then draw.|r")
        self:RenderCards()
        self:AnimateCards({ 1, 2, 3, 4, 5 }, function()
            -- light up the paytable row this deal already makes
            if self.game then
                local key, name = Poker:Evaluate(self.game.hand)
                self.currentKey = key
                if key then
                    self.resultText:SetText("|cffffe100You have: " .. name .. "|r")
                end
            end
            self:UpdateDisplay()
        end)
    end

    self:UpdateDisplay()
end

-- One place decides which game's GAME OVER stamp should blink: the active
-- mode's, whenever that machine has no live round (fresh launch included).
function VP:UpdateGameOver()
    if self.gameOverFrame then
        self.gameOverFrame:SetShown(self.mode == "poker" and not self.game and not self.cardAnim)
    end
    if self.bjGameOver then
        self.bjGameOver:SetShown(self.mode == "blackjack" and not self.bjGame and not self.bjAnim)
    end
    if self.kenoGameOver then
        self.kenoGameOver:SetShown(self.mode == "keno" and not self.kenoDrawing
            and not self.kenoCard)
    end
end

function VP:RenderCards()
    local hand = self.game and self.game.hand or self.lastHand
    if self.game then self.lastHand = self.game.hand end

    for i = 1, 5 do
        local btn = self.cards[i]
        local card = hand and hand[i]
        if card then
            btn.tex:SetTexture(CARD_PATH .. card.rank .. "_" .. card.suit)
        else
            btn.tex:SetTexture(cardBackTexture())
        end
        btn.heldText:SetShown(self.game ~= nil and self.holds[i] == true)
    end
end

-- (Re)build the paytable grid for the current variation, Game King style:
-- hand names down the left, one pay column per coin (1-5), yellow on blue,
-- vertical separators, a red band on the active bet column and a gold band
-- on the hand you currently have / just made. Rows are pooled so switching
-- games doesn't leak font strings.
function VP:BuildPaytable()
    local Poker = BJ.Arcade.Poker
    local rows = Poker:CurrentVariation().paytable
    local payFrame = self.payFrame
    if not payFrame then return end

    -- multi-hand compacts the rows to buy space for the extras strip
    local n = #rows
    local rowH = (Poker:GetHandCount() > 1) and 12 or PT_ROWH
    local topPad = (Poker:GetHandCount() > 1) and 16 or PT_TOPPAD
    payFrame:SetHeight(topPad + n * rowH + 8)

    -- one-time chrome
    if not payFrame.colHl then
        payFrame.colHl = payFrame:CreateTexture(nil, "BACKGROUND", nil, 1)
        payFrame.colHl:SetColorTexture(0.72, 0.05, 0.05, 0.9)

        payFrame.rowHl = payFrame:CreateTexture(nil, "BACKGROUND", nil, 2)
        payFrame.rowHl:SetColorTexture(1, 0.85, 0.15, 0.3)
        payFrame.rowHl:Hide()

        payFrame.headers = {}
        for c = 1, 5 do
            local h = payFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            h:SetPoint("TOPLEFT", PT_LPAD + PT_NAME_W + (c - 1) * PT_COLW, -5)
            h:SetWidth(PT_COLW - 6)
            h:SetJustifyH("RIGHT")
            h:SetTextColor(1, 0.88, 0.25)
            payFrame.headers[c] = h
        end

        payFrame.seps = {}
        for c = 0, 4 do
            local t = payFrame:CreateTexture(nil, "ARTWORK")
            t:SetColorTexture(0.95, 0.8, 0.1, 0.5)
            t:SetWidth(1)
            local x = PT_LPAD + PT_NAME_W + c * PT_COLW - 3
            t:SetPoint("TOP", payFrame, "TOPLEFT", x, -3)
            t:SetPoint("BOTTOM", payFrame, "BOTTOMLEFT", x, 3)
            payFrame.seps[#payFrame.seps + 1] = t
        end
    end

    self.payPool = self.payPool or {}
    self.payRows = {}
    local total = math.max(n, #self.payPool)
    for i = 1, total do
        local row = rows[i]
        local rec = self.payPool[i]
        if not rec and row then
            rec = { cells = {} }
            rec.name = payFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            rec.name:SetJustifyH("LEFT")
            rec.name:SetTextColor(1, 0.88, 0.25)
            for c = 1, 5 do
                local fs = payFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                fs:SetJustifyH("RIGHT")
                fs:SetTextColor(1, 0.88, 0.25)
                rec.cells[c] = fs
            end
            self.payPool[i] = rec
        end
        if rec then
            if row then
                local y = -topPad - (i - 1) * rowH
                rec.y = y
                rec.name:ClearAllPoints()
                rec.name:SetPoint("TOPLEFT", PT_LPAD, y)
                rec.name:SetWidth(PT_NAME_W - 8)
                rec.name:Show()
                for c = 1, 5 do
                    rec.cells[c]:ClearAllPoints()
                    rec.cells[c]:SetPoint("TOPLEFT", PT_LPAD + PT_NAME_W + (c - 1) * PT_COLW, y)
                    rec.cells[c]:SetWidth(PT_COLW - 6)
                    rec.cells[c]:Show()
                end
                self.payRows[row.key] = rec
            else
                rec.name:Hide()
                for c = 1, 5 do rec.cells[c]:Hide() end
            end
        end
    end
    payFrame.rowHl:SetHeight(rowH)
    payFrame.rowHl:Hide()
end

-- Advance to the next variation (only between hands).
function VP:CycleVariation()
    if self.mode ~= "poker" or self.game then return end
    BJ.Arcade.Poker:CycleVariation()
    self.lastResultKey = nil
    self.lastExtras = nil
    self.resultText:SetText("")
    self:ApplyHandLayout()
    self:UpdateVariationLabel()
    self:UpdateDisplay()
end

function VP:UpdateVariationLabel()
    local v = BJ.Arcade.Poker:CurrentVariation()
    if self.varBtn then
        self.varBtn.text:SetText("|cffffffff< |r|cff88ccff" .. v.name .. "|r|cffffffff >|r")
    end
    if self.title then
        self.title:SetText("|cffffd700Video Poker|r  |cff88ccff" .. v.name .. "|r")
    end
end

-- "Max Bet" commits the biggest ladder step the balance can cover, in
-- whichever game is on screen.
function VP:OnMaxBet()
    if self.mode == "blackjack" and self.bjGame then return end
    if self.mode == "keno" and (self.kenoDrawing or self.kenoCard) then return end
    if self.mode == "poker" and (self.game or self.cardAnim) then return end
    local units = (self.mode == "poker") and BJ.Arcade.Poker:GetHandCount() or 1
    self.bet = BJ.Arcade:MaxAffordableStep(units)
    BJ:PlaySfx("Arcade\\coin_insert.ogg")
    self:UpdateDisplay()
end

function VP:RefreshPaytable()
    local Poker = BJ.Arcade.Poker
    local v = Poker:CurrentVariation()
    local payFrame = self.payFrame
    if not payFrame or not payFrame.headers then return end

    local bet = self.bet or 1
    local overMax = bet > 5
    local activeCol = overMax and 5 or math.max(1, math.min(bet, 5))

    -- column headers: coins 1-5; past the classic ladder the 5th column
    -- becomes the actual bet
    for c = 1, 5 do
        if c == 5 and overMax then
            payFrame.headers[c]:SetText("BET " .. fmtBet(bet))
        else
            payFrame.headers[c]:SetText(tostring(c))
        end
    end

    -- the red active-column band
    local x = PT_LPAD + PT_NAME_W + (activeCol - 1) * PT_COLW - 3
    payFrame.colHl:ClearAllPoints()
    payFrame.colHl:SetPoint("TOPLEFT", payFrame, "TOPLEFT", x, -2)
    payFrame.colHl:SetPoint("BOTTOMRIGHT", payFrame, "BOTTOMLEFT", x + PT_COLW, 2)
    payFrame.colHl:Show()

    local royalMin = Poker.ROYAL_MIN_BET or 5
    for _, row in ipairs(v.paytable) do
        local rec = self.payRows[row.key]
        if rec then
            rec.name:SetText(row.name)
            for c = 1, 5 do
                local pay
                if c == 5 and overMax then
                    pay = Poker:PayFor(row.key, bet) * bet
                else
                    local per = row.pay
                    if row.key == v.royalKey and c >= royalMin then
                        per = v.royalMaxPay or Poker.ROYAL_MAX_PAY
                    end
                    pay = per * c
                end
                rec.cells[c]:SetText(fmtBet(pay))
            end
        end
    end

    -- gold band on the hand you currently have (mid-hand) or just made
    local hlKey = self.game and self.currentKey or self.lastResultKey
    local rec = hlKey and self.payRows[hlKey]
    if rec then
        payFrame.rowHl:ClearAllPoints()
        payFrame.rowHl:SetPoint("TOPLEFT", 2, rec.y + 2)
        payFrame.rowHl:SetPoint("TOPRIGHT", -2, rec.y + 2)
        payFrame.rowHl:Show()
    else
        payFrame.rowHl:Hide()
    end
end

-- Roll the WIN meter up from 0 to `amount`, looping coin ticks until it
-- lands. The rate is a fixed 5 bet-multiples of coins per second, so a
-- full house (10x) rolls ~2s and a monster quad rolls for ages - exactly
-- like feeding a hopper. Capped so a royal doesn't take a lunch break.
local ROLLUP_MULT_PER_SEC = 5
function VP:RollUpWin(amount, onDone)
    self.rollupDriver = self.rollupDriver or CreateFrame("Frame")
    local drv = self.rollupDriver
    local mult = amount / math.max(1, self.bet or 1)
    local dur = math.min(10, math.max(0.5, mult / ROLLUP_MULT_PER_SEC))
    local t, lastTick = 0, 0
    self.winShown = 0
    drv:SetScript("OnUpdate", function(_, dt)
        t = t + dt
        local p = math.min(t / dur, 1)
        self.winShown = math.floor(amount * p)
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

-- Kill a running roll-up and every lingering win sound - called the moment
-- a new hand starts so the last celebration never bleeds into it.
function VP:FinishRollupNow()
    if self.rollupDriver then self.rollupDriver:SetScript("OnUpdate", nil) end
    if self.winSounds and StopSound then
        for _, h in ipairs(self.winSounds) do StopSound(h) end
    end
    self.winSounds = nil
    self.winShown = 0
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

function VP:UpdateDisplay()
    if not self.frame then return end
    self:UpdateGameOver()
    local Arcade = BJ.Arcade
    local credits = Arcade:GetCredits()
    local db = Arcade:GetDB()
    self.betVal:SetText(fmtBet(self.bet))

    local comps = "|cffcc8866refills: " .. Arcade:GetLifetimeComps() .. "|r"

    -- the Game King meter bar carries everything now: WIN/CREDIT/BET up
    -- top, best win + refills on the small row beneath
    if self.meterWinFS then
        self.meterWinFS:SetText("|cffffe100WIN|r " .. fmtBig(self.winShown or 0))
        self.meterCreditFS:SetText("|cffffe100CREDIT|r " .. fmtBig(credits))
        self.meterBetFS:SetText("|cffffe100BET|r " .. fmtBet(self.bet))
        local best
        if self.mode == "blackjack" then
            best = "|cff888888best BJ win: " .. fmtBig(db.bestBlackjackWin or 0) .. "|r"
        elseif self.mode == "keno" then
            best = "|cff888888best keno win: " .. fmtBig(db.bestKenoWin or 0) .. "|r"
        else
            best = "|cff888888best win: " .. fmtBig(db.bestPokerWin or 0) .. "|r"
        end
        self.meterSubFS:SetText(best .. "   " .. comps)
    end
    self.creditsText:SetText("")

    if self.mode == "blackjack" then
        self:UpdateBlackjackDisplay(credits)
        return
    end

    if self.mode == "keno" then
        self:UpdateKenoDisplay(credits)
        return
    end

    self:RefreshPaytable()

    local midHand = self.game ~= nil
    self.betDown:SetEnabled(not midHand)
    self.betUp:SetEnabled(not midHand)
    if self.maxBtn then self.maxBtn:SetEnabled(not midHand) end
    if self.varBtn then self.varBtn:SetEnabled(not midHand) end
    if self.handsBtn then self.handsBtn:SetEnabled(not midHand) end

    -- the deal costs bet x hands; BET meter shows the multiplier too
    local hands = BJ.Arcade.Poker:GetHandCount()
    local cost = self.bet * hands
    if self.meterBetFS and hands > 1 then
        self.meterBetFS:SetText("|cffffe100BET|r " .. fmtBet(self.bet) .. "|cff88ccff x" .. hands .. "|r")
    end

    -- chunky Game King yellow button, black text
    self.dealBtn:Show()
    if midHand then
        self.dealBtn.text:SetText("DRAW")
        styleButton(self.dealBtn, true, 0.9, 0.72, 0.05)
        self.dealBtn.text:SetTextColor(0, 0, 0)
    elseif credits < 1 then
        self.dealBtn.text:SetText("COMP ME")
        styleButton(self.dealBtn, true, 0.35, 0.25, 0.1)
        self.dealBtn.text:SetTextColor(1, 0.82, 0)
    else
        self.dealBtn.text:SetText("DEAL (" .. fmtBet(cost) .. ")")
        styleButton(self.dealBtn, credits >= cost, 0.9, 0.72, 0.05)
        if credits >= cost then
            self.dealBtn.text:SetTextColor(0, 0, 0)
        else
            self.dealBtn.text:SetTextColor(0.6, 0.6, 0.6)
        end
    end
end

-- ===== Video Blackjack =====

function VP:SetGameMode(mode)
    if mode ~= "poker" and mode ~= "blackjack" and mode ~= "keno" then mode = "poker" end
    -- Never switch mid-hand (or mid-animation).
    if self.cardAnim or self.bjAnim or self.kenoDrawing then return end
    if self.game and mode ~= "poker" then return end
    if self.bjGame and mode ~= "blackjack" then return end
    self.mode = mode
    local poker = (mode == "poker")

    for _, w in ipairs(self.pokerWidgets or {}) do w:SetShown(poker) end
    if self.multiArea and not poker then self.multiArea:Hide() end
    if self.bjPanel then self.bjPanel:SetShown(mode == "blackjack") end
    if self.kenoPanel then self.kenoPanel:SetShown(mode == "keno") end
    if mode ~= "blackjack" then
        self.bjHitBtn:Hide(); self.bjStandBtn:Hide(); self.bjDoubleBtn:Hide()
        if self.bjSplitBtn then self.bjSplitBtn:Hide() end
    end
    self:UpdateTabHighlight()

    if poker then
        self.title:SetText("|cffffd700Video Poker|r  |cff88ccff" ..
            BJ.Arcade.Poker:CurrentVariation().name .. "|r")
        self:ApplyHandLayout()
        self:UpdateVariationLabel()
        self:RenderCards()
    elseif mode == "blackjack" then
        self.title:SetText("|cffffd700Video Blackjack|r")
        self:RenderBlackjack()
    else
        self.title:SetText("|cffffd700Video Keno|r")
        self:KenoUpdateBoard()
    end
    self:UpdateDisplay()
end

function VP:UpdateTabHighlight()
    local function style(tab, active)
        if not tab then return end
        if active then
            tab:SetBackdropColor(0.18, 0.38, 0.22, 1)
            tab:SetBackdropBorderColor(0.4, 0.85, 0.5, 1)
            tab.text:SetTextColor(1, 1, 1)
        else
            tab:SetBackdropColor(0.1, 0.11, 0.14, 1)
            tab:SetBackdropBorderColor(0.35, 0.38, 0.45, 1)
            tab.text:SetTextColor(0.7, 0.7, 0.7)
        end
    end
    style(self.pokerTab, self.mode == "poker")
    style(self.bjTab, self.mode == "blackjack")
    style(self.kenoTab, self.mode == "keno")
end

-- first k entries of a card list (deal-cadence view)
local function sliceCards(cards, k)
    if not k or k >= #cards then return cards end
    local t = {}
    for i = 1, k do t[i] = cards[i] end
    return t
end

function VP:RenderBlackjack()
    local Blackjack = BJ.Arcade.Blackjack
    local g = self.bjGame or self.bjLastGame

    -- during the deal animation only part of each row is on the table yet
    local dealerView, playerView
    if g and self.bjAnim and g == self.bjGame then
        dealerView = sliceCards(g.dealer, self.bjAnim.d)
        playerView = sliceCards(g.hands[1].cards, self.bjAnim.p)
    end

    -- Dealer row (hole card face-down until the reveal)
    if g then
        local hidden = (not g.revealDealer) and { [2] = true } or nil
        layoutCardRow(self.bjDealerRow, self.bjDealerCards, dealerView or g.dealer, hidden, cardBackTexture())
        if dealerView and #dealerView < 1 then
            self.bjDealerLabel:SetText("Dealer")
        elseif g.revealDealer then
            self.bjDealerLabel:SetText("Dealer: |cffffd700" .. (Blackjack:HandValue(g.dealer)) .. "|r")
        else
            self.bjDealerLabel:SetText("Dealer: |cffffd700" .. Blackjack:CardValue(g.dealer[1].rank) .. "|r + ?")
        end
    else
        for _, tex in ipairs(self.bjDealerCards) do tex:Hide() end
        self.bjDealerRow:SetWidth(1)
        self.bjDealerLabel:SetText("Dealer")
    end

    -- Player hands, centred as one strip
    local blocks = self.bjHands
    local nHands = g and #g.hands or 0
    local widths, total = {}, 0
    for h = 1, #blocks do
        local block = blocks[h]
        local hand = g and g.hands[h]
        if hand then
            local view = (h == 1 and playerView) or hand.cards
            widths[h] = layoutCardRow(block, block.cards, view, nil, nil)
            total = total + widths[h] + (h > 1 and BJ_HAND_GAP or 0)

            local v = Blackjack:HandValue(#view > 0 and view or hand.cards)
            local vc = (v > 21) and "|cffff4040" or "|cffffd700"
            local tag = (nHands > 1) and ("Hand " .. h .. ": ") or "You: "
            if #view == 0 then
                block.label:SetText(tag .. "|cff888888-|r")
            else
                block.label:SetText(tag .. vc .. v .. "|r  |cff888888(" .. fmtBet(hand.bet) .. ")|r")
            end

            if hand.result then
                local rc = (hand.resultKey == "win" or hand.resultKey == "blackjack") and "|cff00ff00"
                    or (hand.resultKey == "push") and "|cffffd700" or "|cffff4040"
                block.result:SetText(rc .. hand.result .. "|r")
            else
                block.result:SetText("")
            end
            block.marker:SetShown(g and not g.over and g.active == h and not hand.done)
            block:Show()
        else
            block:Hide()
        end
    end
    -- centre the strip: place blocks left to right from -total/2
    local x = -total / 2
    for h = 1, nHands do
        local block = blocks[h]
        block:ClearAllPoints()
        block:SetPoint("LEFT", self.bjHandStrip, "CENTER", x, 0)
        x = x + widths[h] + BJ_HAND_GAP
    end
end

function VP:UpdateBlackjackDisplay(credits)
    local Blackjack = BJ.Arcade.Blackjack
    local mid = self.bjGame ~= nil
    self.betDown:SetEnabled(not mid)
    self.betUp:SetEnabled(not mid)
    if self.maxBtn then self.maxBtn:SetEnabled(not mid) end

    if mid then
        local dealt = not self.bjAnim   -- buttons wake up after the deal lands
        self.dealBtn:Hide()
        self.bjHitBtn:Show(); self.bjStandBtn:Show()
        self.bjDoubleBtn:Show(); self.bjSplitBtn:Show()
        styleButton(self.bjHitBtn, dealt, 0.15, 0.3, 0.42)
        styleButton(self.bjStandBtn, dealt, 0.4, 0.3, 0.12)
        styleButton(self.bjDoubleBtn, dealt and Blackjack:CanDouble(self.bjGame), 0.32, 0.2, 0.36)
        styleButton(self.bjSplitBtn, dealt and Blackjack:CanSplit(self.bjGame), 0.15, 0.38, 0.3)
    else
        self.bjHitBtn:Hide(); self.bjStandBtn:Hide()
        self.bjDoubleBtn:Hide(); self.bjSplitBtn:Hide()
        self.dealBtn:Show()
        if credits < 1 then
            self.dealBtn.text:SetText("COMP ME")
            styleButton(self.dealBtn, true, 0.35, 0.25, 0.1)
            self.dealBtn.text:SetTextColor(1, 0.82, 0)
        else
            self.dealBtn.text:SetText("DEAL (" .. fmtBet(self.bet) .. ")")
            styleButton(self.dealBtn, credits >= self.bet, 0.9, 0.72, 0.05)
            if credits >= self.bet then
                self.dealBtn.text:SetTextColor(0, 0, 0)
            else
                self.dealBtn.text:SetTextColor(0.6, 0.6, 0.6)
            end
        end
    end
end

function VP:BJShowResult(g)
    local color = "|cff888888"
    if g.resultKey == "win" or g.resultKey == "blackjack" then color = "|cff00ff00"
    elseif g.resultKey == "push" then color = "|cffffd700"
    elseif g.resultKey == "lose" or g.resultKey == "bust" then color = "|cffff2020" end

    local net = (g.payout or 0) - (g.totalBet or 0)
    local suffix = ""
    if net > 0 then suffix = "  +" .. net .. " credits"
    elseif net < 0 then suffix = "  -" .. (-net) .. " credits" end
    self.bjResultText:SetText(color .. g.result .. suffix .. "|r")

    if g.resultKey == "blackjack" then
        self.winSounds = {}
        local _, h = BJ:PlaySfx("Arcade\\jackpot.ogg", "Master")
        self.winSounds[#self.winSounds + 1] = h
        UI.Lobby:TrixieReact(self.frame, "love", 5)
    elseif net > 0 then
        BJ:PlaySfx("chips.ogg")
        UI.Lobby:TrixieReact(self.frame, "win", 4)
    end
    -- anything returned (wins AND pushes) rolls up on the WIN meter
    if (g.payout or 0) > 0 then
        self:RollUpWin(g.payout)
    end
end

-- One place to advance the UI after any blackjack action: repaint, and if the
-- round just ended, show the result and free the machine for the next deal.
function VP:BJAfterAction()
    local g = self.bjGame
    self:RenderBlackjack()
    if g and g.over then
        self:BJShowResult(g)
        self.bjLastGame = g       -- keep the table visible between rounds
        self.bjGame = nil
    end
    self:UpdateDisplay()
end

function VP:OnBJDeal()
    local Arcade = BJ.Arcade
    local Blackjack = Arcade.Blackjack
    if self.bjGame then return end

    if Arcade:GetCredits() < 1 then
        local ok, refills = Arcade:CompMe()
        if ok then
            BJ:Print("|cff00ff00The pit boss comps you " .. Arcade.COMP_AMOUNT ..
                " credits.|r (Refill #" .. refills .. " - she's keeping count.)")
            self:UpdateDisplay()
        end
        return
    end

    local game, err = Blackjack:Deal(self.bet)
    if not game then
        BJ:Print("|cffff8800" .. (err or "Cannot deal.") .. "|r")
        return
    end
    self.bjGame = game
    self.bjLastGame = nil
    self:FinishRollupNow()
    self.bjResultText:SetText("")

    -- deal cadence: player, dealer, player, dealer - one card at a time
    self.bjAnim = { p = 0, d = 0 }
    local steps = {
        function() self.bjAnim.p = 1 end,
        function() self.bjAnim.d = 1 end,
        function() self.bjAnim.p = 2 end,
        function() self.bjAnim.d = 2 end,
    }
    local i = 0
    local function nextCard()
        i = i + 1
        if steps[i] then
            steps[i]()
            playCardSound()
            self:RenderBlackjack()
            C_Timer.After(0.3, nextCard)
        else
            self.bjAnim = nil
            if not game.over then
                local hints = { "Hit", "Stand" }
                if Blackjack:CanDouble(game) then hints[#hints + 1] = "Double" end
                if Blackjack:CanSplit(game) then hints[#hints + 1] = "Split" end
                self.bjResultText:SetText("|cff88ccff" .. table.concat(hints, ", ") .. ".|r")
            end
            self:BJAfterAction()
        end
    end
    self:RenderBlackjack()
    self:UpdateDisplay()
    C_Timer.After(0.2, nextCard)
end

function VP:OnBJHit()
    if self.bjAnim then return end
    local g = self.bjGame
    if not g or g.over then return end
    BJ.Arcade.Blackjack:Hit(g)
    playCardSound()
    self:BJAfterAction()
end

function VP:OnBJStand()
    if self.bjAnim then return end
    local g = self.bjGame
    if not g or g.over then return end
    BJ.Arcade.Blackjack:Stand(g)
    self:BJAfterAction()
end

function VP:OnBJDouble()
    if self.bjAnim then return end
    local g = self.bjGame
    if not g or not BJ.Arcade.Blackjack:CanDouble(g) then return end
    BJ.Arcade.Blackjack:Double(g)
    playCardSound()
    self:BJAfterAction()
end

function VP:OnBJSplit()
    if self.bjAnim then return end
    local g = self.bjGame
    if not g or not BJ.Arcade.Blackjack:CanSplit(g) then return end
    BJ.Arcade.Blackjack:Split(g)
    playCardSound()
    self:BJAfterAction()
end

-- ===== Video Keno =====

local KENO_IDLE   = { 0.08, 0.1, 0.14 }
local KENO_PICK   = { 0.15, 0.3, 0.5 }
local KENO_MISS   = { 0.3, 0.3, 0.32 }
local KENO_HIT    = { 0.12, 0.45, 0.18 }

local function kenoPaint(cell, bg, border, textColor)
    cell:SetBackdropColor(bg[1], bg[2], bg[3], 1)
    cell:SetBackdropBorderColor(border[1], border[2], border[3], 1)
    cell.text:SetTextColor(textColor[1], textColor[2], textColor[3])
end

function VP:KenoTogglePick(n)
    if self.kenoDrawing then return end
    local Keno = BJ.Arcade.Keno
    if self.kenoPicks[n] then
        self.kenoPicks[n] = nil
    else
        local count = 0
        for _ in pairs(self.kenoPicks) do count = count + 1 end
        if count >= Keno.MAX_PICKS then
            BJ:Print("|cffff8800You can pick at most " .. Keno.MAX_PICKS .. " numbers.|r")
            return
        end
        self.kenoPicks[n] = true
        BJ:PlaySfx("coin.ogg")
    end
    self:KenoUpdateBoard()
    self:UpdateDisplay()
end

function VP:KenoClearPicks()
    if self.kenoDrawing then return end
    wipe(self.kenoPicks)
    self.kenoResultText:SetText("")
    self:KenoUpdateBoard()
    self:UpdateDisplay()
end

-- Repaint the whole board to its idle state (picks blue, rest dark).
function VP:KenoUpdateBoard()
    for n, cell in ipairs(self.kenoCells or {}) do
        if self.kenoPicks[n] then
            kenoPaint(cell, KENO_PICK, { 0.4, 0.7, 1 }, { 1, 1, 1 })
        else
            kenoPaint(cell, KENO_IDLE, { 0.3, 0.32, 0.38 }, { 0.75, 0.75, 0.75 })
        end
    end
end

function VP:KenoPickCount()
    local count = 0
    for _ in pairs(self.kenoPicks) do count = count + 1 end
    return count
end

function VP:OnKenoDraw()
    local Arcade = BJ.Arcade
    local Keno = Arcade.Keno
    if self.kenoDrawing then return end

    -- Stage 1: PLAY buys the card up front, clears GAME OVER, and hands the
    -- board over for spot picking.
    if not self.kenoCard then
        if Arcade:GetCredits() < 1 then
            local ok, refills = Arcade:CompMe()
            if ok then
                BJ:Print("|cff00ff00The pit boss comps you " .. Arcade.COMP_AMOUNT ..
                    " credits.|r (Refill #" .. refills .. " - she's keeping count.)")
                self:UpdateDisplay()
            end
            return
        end
        local paid, err = Keno:BuyCard(self.bet)
        if not paid then
            BJ:Print("|cffff8800" .. (err or "Cannot buy a card.") .. "|r")
            return
        end
        self.kenoCard = { bet = paid }
        self:FinishRollupNow()
        BJ:PlaySfx("coin.ogg")
        self.kenoResultText:SetText("|cff88ccffCard bought - pick your spots, then DRAW.|r")
        self:UpdateDisplay()
        return
    end

    -- Stage 2: run the draw for the paid card.
    local picks = {}
    for n in pairs(self.kenoPicks) do picks[#picks + 1] = n end
    local result, err = Keno:Play(picks, self.kenoCard.bet)
    if not result then
        BJ:Print("|cffff8800" .. (err or "Cannot play.") .. "|r")
        return
    end

    self.kenoCard = nil
    self.kenoDrawing = true
    self:KenoUpdateBoard()
    self.kenoResultText:SetText("|cff88ccffDrawing...|r")
    self:UpdateDisplay()

    -- reveal the 20 draws one at a time
    local i = 0
    local hits = 0
    local function reveal()
        i = i + 1
        local n = result.drawn[i]
        if not n then
            self.kenoDrawing = false
            if result.payout > 0 then
                self.kenoResultText:SetText(string.format(
                    "|cff00ff00%d of %d hit  -  +%s credits!|r", result.matches, result.picks, fmtBig(result.payout)))
                self.winSounds = {}
                if result.payout >= 20 * result.bet then
                    local _, h = BJ:PlaySfx("Arcade\\jackpot.ogg", "Master")
                    self.winSounds[#self.winSounds + 1] = h
                    UI.Lobby:TrixieReact(self.frame, "love", 5)
                else
                    BJ:PlaySfx("chips.ogg")
                    UI.Lobby:TrixieReact(self.frame, "win", 4)
                end
                self:RollUpWin(result.payout)
            else
                self.kenoResultText:SetText(string.format(
                    "|cff888888%d of %d hit - no pay. Try again!|r", result.matches, result.picks))
            end
            self:UpdateDisplay()
            return
        end
        local cell = self.kenoCells[n]
        if self.kenoPicks[n] then
            hits = hits + 1
            kenoPaint(cell, KENO_HIT, { 0.3, 1, 0.4 }, { 1, 1, 1 })
            BJ:PlaySfx("coin.ogg")
        else
            kenoPaint(cell, KENO_MISS, { 0.5, 0.5, 0.52 }, { 0.2, 0.2, 0.2 })
            playCardSound()
        end
        self.kenoResultText:SetText(string.format(
            "|cff88ccffDrawing... %d/20|r   hits: |cff00ff00%d|r", i, hits))
        C_Timer.After(0.145, reveal)   -- ~20% slower than the original pace
    end
    C_Timer.After(0.3, reveal)
end
function VP:UpdateKenoDisplay(credits)
    local Keno = BJ.Arcade.Keno
    local picks = self:KenoPickCount()
    self.kenoPicksText:SetText("Picks: |cffffd700" .. picks .. "|r/" .. Keno.MAX_PICKS)

    -- live pay ladder for the current pick count
    local ladder = Keno.PAY[picks]
    if ladder then
        local parts = {}
        local keys = {}
        for m in pairs(ladder) do keys[#keys + 1] = m end
        table.sort(keys)
        for _, m in ipairs(keys) do
            parts[#parts + 1] = m .. " hits: |cffffd700" .. fmtBet(ladder[m] * self.bet) .. "|r"
        end
        self.kenoLadderText:SetText("|cffccaa66PAYS:|r  " .. table.concat(parts, "   "))
    else
        self.kenoLadderText:SetText("|cff888888Pick 1-" .. Keno.MAX_PICKS .. " numbers, then DRAW.|r")
    end

    local busy = self.kenoDrawing
    local carded = self.kenoCard ~= nil
    -- the bet is locked once a card is bought
    self.betDown:SetEnabled(not busy and not carded)
    self.betUp:SetEnabled(not busy and not carded)
    if self.maxBtn then self.maxBtn:SetEnabled(not busy and not carded) end
    if self.kenoClearBtn then self.kenoClearBtn:SetEnabled(not busy and picks > 0) end

    self.dealBtn:Show()
    if carded then
        local canDraw = not busy and picks > 0
        self.dealBtn.text:SetText("DRAW")
        styleButton(self.dealBtn, canDraw, 0.9, 0.72, 0.05)
        self.dealBtn.text:SetTextColor(canDraw and 0 or 0.6, canDraw and 0 or 0.6, canDraw and 0 or 0.6)
    elseif credits < 1 then
        self.dealBtn.text:SetText("COMP ME")
        styleButton(self.dealBtn, not busy, 0.35, 0.25, 0.1)
        self.dealBtn.text:SetTextColor(1, 0.82, 0)
    else
        local canPlay = not busy and credits >= self.bet
        self.dealBtn.text:SetText("PLAY (" .. fmtBet(self.bet) .. ")")
        styleButton(self.dealBtn, canPlay, 0.9, 0.72, 0.05)
        self.dealBtn.text:SetTextColor(canPlay and 0 or 0.6, canPlay and 0 or 0.6, canPlay and 0 or 0.6)
    end
end

function VP:Show()
    self:Initialize()
    self:SetGameMode(self.mode or "poker")
    self.frame:Show()
end

function VP:Hide()
    if self.frame then
        self.frame:Hide()
    end
end
