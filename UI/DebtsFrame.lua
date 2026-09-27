--[[
    Chairface's Casino - UI/DebtsFrame.lua
    The session tab window for DebtLedger.lua: "My Tab" shows what you owe
    and what you're owed (with Forgive buttons on your credits), "All Debts"
    shows every outstanding balance the ledger knows about. Hovering a row
    shows the recent activity (game debts, trade payments, forgiveness)
    behind that balance.
]]

local BJ = ChairfacesCasino
local UI = BJ.UI

UI.Debts = {}
local DF = UI.Debts

local FRAME_W, FRAME_H = 660, 450  -- landscape, to host the tavern background
local ROW_H = 26
local HEADER_ROW_H = 24

-- Confirm before forgiving a debt owed to you
StaticPopupDialogs["CHAIRFACES_DEBT_FORGIVE"] = {
    text = "Forgive %s's debt of %s?\n\nThis clears it for the whole group.",
    button1 = "Forgive",
    button2 = "Cancel",
    OnAccept = function(self, data)
        if BJ.DebtLedger then
            BJ.DebtLedger:Forgive(data)
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- Confirm before wiping the local ledger
StaticPopupDialogs["CHAIRFACES_DEBT_RESET"] = {
    text = "|cffff6666Clear your entire debt ledger?|r\n\nOnly your copy is wiped - other players keep theirs.\n\nThis cannot be undone!",
    button1 = "Clear",
    button2 = "Cancel",
    OnAccept = function()
        if BJ.DebtLedger then
            BJ.DebtLedger:ResetLedger()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

--[[
    ============================================
    FAKE PLAY CHECKBOXES
    ============================================
    One global toggle ("games I host record no debts"), surfaced as a
    checkbox next to every game's host button so nobody has to open this
    window to find it. Every copy registers here and they all stay in
    sync: DebtLedger:SetFakePlay -> NotifyChanged -> UpdateFakePlayChecks.
]]

DF.fakeChecks = {}

function DF:AttachFakePlayCheck(parent, point, relTo, relPoint, x, y)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(20, 20)
    cb:SetPoint(point, relTo, relPoint, x, y)
    cb:SetFrameLevel(parent:GetFrameLevel() + 5)

    local label = cb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", cb, "RIGHT", 0, 0)
    cb.labelText = label

    -- Loud when ON so a host can't miss that the next table they open records
    -- no debts (the accidental-on-nobody-noticed case); quiet gray when off.
    local function styleLabel(on)
        label:SetText(on and "|cffff4040FREE PLAY ON|r" or "|cffaaaaaaFake play|r")
    end
    cb.styleLabel = styleLabel
    styleLabel(BJ.DebtLedger and BJ.DebtLedger:IsFakePlay() or false)

    cb:SetChecked(BJ.DebtLedger and BJ.DebtLedger:IsFakePlay() or false)
    cb:SetScript("OnClick", function(self)
        if BJ.DebtLedger then
            BJ.DebtLedger:SetFakePlay(self:GetChecked() and true or false)
        end
        styleLabel(self:GetChecked())
    end)
    cb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Fake Play", 1, 1, 0.4)
        GameTooltip:AddLine("Games YOU host record no debts -", 1, 1, 1)
        GameTooltip:AddLine("for friends who just want to play, not pay.", 1, 1, 1)
        GameTooltip:AddLine("One switch for every game; the table sees a notice.", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("Locked in when a table opens - flipping it mid-game", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("only changes tables you host from then on.", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    cb:SetScript("OnLeave", function() GameTooltip:Hide() end)

    table.insert(DF.fakeChecks, cb)
    return cb
end

function DF:UpdateFakePlayChecks()
    local on = BJ.DebtLedger and BJ.DebtLedger:IsFakePlay() or false
    for _, cb in ipairs(self.fakeChecks) do
        cb:SetChecked(on)
        if cb.styleLabel then cb.styleLabel(on) end
    end
end

--[[
    FREE-PLAY JOIN BADGE
    ============================================
    A table's fun/real status is fixed at open (see GameComm) and rides
    TABLE_OPEN. A fun table records no debts, so a player sitting down needs
    to KNOW that before they play for pretend stakes. The gray "(fun game)"
    tag in chat was too easy to miss - this is the loud version: a red
    pulsing banner pinned above the JOIN button of any table that opened on
    fake play. Games call SetJoinFakeBadge(joinButton, XS.fakePlay == true)
    from wherever they show/refresh their join button.
]]

local function pulseBadge(badge)
    -- gentle red pulse so it reads as a live warning, not decoration
    badge.pulse = (badge.pulse or 0) + (badge.dir or 0.02)
    if badge.pulse >= 1 then badge.pulse = 1; badge.dir = -0.03
    elseif badge.pulse <= 0 then badge.pulse = 0; badge.dir = 0.03 end
    local a = 0.55 + 0.45 * badge.pulse
    badge.bg:SetVertexColor(0.7, 0.05, 0.05, 0.92)
    badge.label:SetAlpha(a)
end

-- Show/hide the loud FREE PLAY warning above a join button.
-- isFake must be a definite boolean: only a table that DEFINITELY opened on
-- fake play (flag == true) gets the badge; nil/unknown legacy hosts don't.
-- yOffset (optional) lifts the badge to clear other chrome pinned above the
-- button (e.g. Death Roll's fake-play checkbox); defaults to 4.
function DF:SetJoinFakeBadge(button, isFake, yOffset)
    if not button then return end
    local badge = button._ccFakeBadge
    if not isFake then
        if badge then badge:Hide() end
        return
    end
    if not badge then
        badge = CreateFrame("Frame", nil, button, "BackdropTemplate")
        badge:SetPoint("BOTTOM", button, "TOP", 0, yOffset or 4)
        badge:SetFrameLevel(button:GetFrameLevel() + 3)

        local bg = badge:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetTexture("Interface\\Buttons\\WHITE8x8")
        bg:SetVertexColor(0.7, 0.05, 0.05, 0.92)
        badge.bg = bg

        badge:SetBackdrop({
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 2,
        })
        badge:SetBackdropBorderColor(1, 0.85, 0.2, 1)

        local label = badge:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        label:SetPoint("CENTER")
        label:SetText("|cffffffff\226\154\160 FREE PLAY \226\128\148 NO DEBTS \226\154\160|r")
        label:SetTextColor(1, 1, 1, 1)
        badge.label = label

        badge:SetSize(label:GetStringWidth() + 22, 24)
        badge.dir = 0.03
        badge:SetScript("OnUpdate", function(self, elapsed)
            self.acc = (self.acc or 0) + elapsed
            if self.acc < 0.04 then return end
            self.acc = 0
            pulseBadge(self)
        end)
        button._ccFakeBadge = badge
    end
    badge:Show()
end

-- The debts shortcut icon that rides every game window (it replaced the
-- old per-game session-leaderboard icon - the tab IS the session view now)
function DF:AttachDebtsIcon(parent, point, relTo, relPoint, x, y)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(20, 20)
    btn:SetPoint(point, relTo, relPoint, x, y)

    local tex = btn:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\Widgets\\leaderboard_session")
    btn.texture = tex

    local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\Widgets\\leaderboard_session")
    highlight:SetAlpha(0.5)
    highlight:SetBlendMode("ADD")

    btn:SetScript("OnClick", function()
        DF:Toggle()
    end)
    btn:SetScript("OnEnter", function(self)
        self.texture:SetVertexColor(1, 0.9, 0.5, 1)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Debts - Settle-Up Ledger", 1, 0.6, 0.45)
        GameTooltip:AddLine("Who owes who, netted across every game", 1, 1, 1)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function(self)
        self.texture:SetVertexColor(1, 1, 1, 1)
        GameTooltip:Hide()
    end)
    return btn
end

function DF:CreateFrame()
    local frame = CreateFrame("Frame", "ChairfacesCasinoDebts", UIParent, "BackdropTemplate")
    frame:SetSize(FRAME_W, FRAME_H)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        if not ChairfacesCasinoSaved then ChairfacesCasinoSaved = {} end
        ChairfacesCasinoSaved.debtsPos = { point, relPoint, x, y }
    end)
    frame:SetClampedToScreen(true)
    frame:SetFrameStrata("DIALOG")
    frame:Hide()

    if ChairfacesCasinoSaved and ChairfacesCasinoSaved.debtsPos then
        local pos = ChairfacesCasinoSaved.debtsPos
        frame:ClearAllPoints()
        frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    end

    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 3,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    frame:SetBackdropColor(0.05, 0.05, 0.08, 0.98)
    frame:SetBackdropBorderColor(0.7, 0.55, 0.2, 1)
    if UI.Lobby and UI.Lobby.ApplyTavernBackground then UI.Lobby:ApplyTavernBackground(frame) end

    -- Header
    local header = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    header:SetSize(FRAME_W - 6, 45)
    header:SetPoint("TOP", 0, -3)
    header:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    header:SetBackdropColor(0.12, 0.1, 0.05, 1)
    header:SetBackdropBorderColor(0.8, 0.65, 0.2, 1)

    local headerGlow = header:CreateTexture(nil, "ARTWORK")
    headerGlow:SetTexture("Interface\\Buttons\\WHITE8x8")
    headerGlow:SetPoint("TOPLEFT", 2, -2)
    headerGlow:SetPoint("TOPRIGHT", -2, -2)
    headerGlow:SetHeight(22)
    if headerGlow.SetGradient and CreateColor then
        headerGlow:SetGradient("VERTICAL", CreateColor(0.6, 0.45, 0.1, 0.4), CreateColor(0.6, 0.45, 0.1, 0))
    else
        headerGlow:SetVertexColor(0.6, 0.45, 0.1, 0.25)
    end

    local iconFrame = CreateFrame("Frame", nil, header)
    iconFrame:SetSize(32, 32)
    iconFrame:SetPoint("LEFT", 10, 0)
    local iconTex = iconFrame:CreateTexture(nil, "ARTWORK")
    iconTex:SetAllPoints()
    iconTex:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\icon")

    local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", iconFrame, "RIGHT", 8, 2)
    title:SetText("|cffffd700CHAIRFACE'S CASINO|r")
    title:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE")

    local subtitle = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subtitle:SetPoint("LEFT", iconFrame, "RIGHT", 8, -12)
    subtitle:SetText("|cffccaa66SETTLE-UP LEDGER|r")

    local closeBtn = CreateFrame("Button", nil, header, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", 0, 0)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)

    -- Tab bar: My Tab | All Debts
    local tabBar = CreateFrame("Frame", nil, frame)
    tabBar:SetSize(FRAME_W - 20, 30)
    tabBar:SetPoint("TOP", header, "BOTTOM", 0, -6)
    frame.tabs = {}

    local tabDefs = {
        { id = "mine", label = "MY TAB" },
        { id = "all", label = "ALL DEBTS" },
    }
    local tabWidth = (FRAME_W - 30) / 2
    for i, def in ipairs(tabDefs) do
        local tab = CreateFrame("Button", nil, tabBar, "BackdropTemplate")
        tab:SetSize(tabWidth, 28)
        tab:SetPoint("TOPLEFT", (i - 1) * (tabWidth + 10), 0)
        tab:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 2,
        })
        tab.label = def.label

        local tabText = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        tabText:SetPoint("CENTER")
        tabText:SetText(def.label)
        tab.text = tabText

        tab:SetScript("OnClick", function()
            DF:SelectTab(def.id)
        end)
        tab:SetScript("OnEnter", function(self)
            if frame.selectedTab ~= def.id then
                self:SetBackdropColor(0.25, 0.2, 0.12, 1)
            end
        end)
        tab:SetScript("OnLeave", function(self)
            if frame.selectedTab ~= def.id then
                self:SetBackdropColor(0.15, 0.12, 0.08, 1)
            end
        end)
        frame.tabs[def.id] = tab
    end

    -- Summary line (totals for you)
    local summary = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    summary:SetPoint("TOP", tabBar, "BOTTOM", 0, -8)
    frame.summary = summary

    -- Scrolling debt list
    local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 12, -125)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 46)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(FRAME_W - 42, 100)
    scrollFrame:SetScrollChild(content)
    frame.content = content
    frame.scrollFrame = scrollFrame

    -- Footer buttons
    local function footerButton(labelText, anchorPoint, x, r, g, b)
        local btn = CreateFrame("Button", nil, frame, "BackdropTemplate")
        btn:SetSize(120, 26)
        btn:SetPoint(anchorPoint, frame, anchorPoint, x, 12)
        btn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 2,
        })
        btn:SetBackdropColor(r, g, b, 1)
        btn:SetBackdropBorderColor(r * 2, g * 2, b * 2, 1)
        local text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        text:SetPoint("CENTER")
        text:SetText(labelText)
        btn:SetScript("OnEnter", function(self)
            self:SetBackdropColor(r * 1.5, g * 1.5, b * 1.5, 1)
        end)
        btn:SetScript("OnLeave", function(self)
            self:SetBackdropColor(r, g, b, 1)
        end)
        return btn
    end

    local postBtn = footerButton("|cffffd700Post to Chat|r", "BOTTOMLEFT", 12, 0.25, 0.2, 0.1)
    postBtn:SetScript("OnClick", function() DF:PostToChat() end)

    local resetBtn = footerButton("|cffff8866Clear Ledger|r", "BOTTOMRIGHT", -12, 0.25, 0.1, 0.08)
    resetBtn:SetScript("OnClick", function()
        StaticPopup_Show("CHAIRFACES_DEBT_RESET")
    end)

    -- Fake play: games I host record no debts (same toggle that rides
    -- next to every host button)
    frame.funCheck = self:AttachFakePlayCheck(frame, "BOTTOM", frame, "BOTTOM", -34, 13)

    frame.rows = {}
    frame.selectedTab = "mine"
    self.frame = frame

    if BJ.EscapeHandler then
        BJ.EscapeHandler:RegisterFrame("ChairfacesCasinoDebts")
    end

    return frame
end

--[[
    ============================================
    ROWS
    ============================================
]]

function DF:GetRow(i)
    local frame = self.frame
    local row = frame.rows[i]
    if row then return row end

    row = CreateFrame("Frame", nil, frame.content, "BackdropTemplate")
    row:SetSize(FRAME_W - 42, ROW_H)
    row:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })

    local left = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    left:SetPoint("LEFT", 8, 0)
    left:SetJustifyH("LEFT")
    row.left = left

    local right = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    right:SetPoint("RIGHT", -78, 0)
    right:SetJustifyH("RIGHT")
    row.right = right

    -- one action button per row, restyled per use (Settle / Forgive)
    local btn = CreateFrame("Button", nil, row, "BackdropTemplate")
    btn:SetSize(62, 18)
    btn:SetPoint("RIGHT", -8, 0)
    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btn.label:SetPoint("CENTER")
    btn.Style = function(self, text, r, g, b)
        self.baseColor = { r, g, b }
        self.label:SetText(text)
        self:SetBackdropColor(r, g, b, 1)
        self:SetBackdropBorderColor(r * 2, g * 2, b * 2, 1)
    end
    btn:SetScript("OnEnter", function(self)
        local c = self.baseColor or { 0.2, 0.2, 0.2 }
        self:SetBackdropColor(c[1] * 1.5, c[2] * 1.5, c[3] * 1.5, 1)
    end)
    btn:SetScript("OnLeave", function(self)
        local c = self.baseColor or { 0.2, 0.2, 0.2 }
        self:SetBackdropColor(c[1], c[2], c[3], 1)
    end)
    row.actionBtn = btn

    -- History tooltip for the pair behind this row
    row:SetScript("OnEnter", function(self)
        local entry = self.entryRef
        if not entry or not entry.history or #entry.history == 0 then return end
        local DL = BJ.DebtLedger
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Recent activity", 1, 0.84, 0)
        for j = 1, math.min(#entry.history, 8) do
            local h = entry.history[j]
            local stamp = date("%m/%d %H:%M", h.t or 0)
            local line
            if h.kind == "pay" then
                line = stamp .. "  Paid: " .. DL:ShortName(h.from) .. " > " .. DL:ShortName(h.to) .. "  " .. BJ:FormatGold(h.amt)
            elseif h.kind == "forgive" then
                line = stamp .. "  Forgiven: " .. BJ:FormatGold(h.amt)
            else
                local label = DL.GAME_LABELS[h.game] or h.game or "?"
                line = stamp .. "  " .. label .. ": " .. DL:ShortName(h.from) .. " > " .. DL:ShortName(h.to) .. "  " .. BJ:FormatGold(h.amt)
            end
            GameTooltip:AddLine(line, 0.9, 0.9, 0.9)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    frame.rows[i] = row
    return row
end

-- Reset a row to a neutral state before styling it for its list item
local function PrepareRow(row, y, height)
    row:SetHeight(height)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", 0, y)
    row:SetBackdropColor(0.1, 0.1, 0.12, 0.8)
    row:SetBackdropBorderColor(0.25, 0.22, 0.15, 1)
    row.left:SetText("")
    row.right:SetText("")
    row.right:ClearAllPoints()
    row.right:SetPoint("RIGHT", -8, 0)
    row.actionBtn:Hide()
    row.entryRef = nil
    row:Show()
end

--[[
    ============================================
    REFRESH
    ============================================
]]

function DF:Refresh()
    local frame = self.frame
    if not frame or not frame:IsShown() then return end
    local DL = BJ.DebtLedger
    if not DL then return end

    -- Summary totals
    local iOweTotal, owedToMeTotal = DL:GetMyTotals()
    frame.summary:SetText(
        "You owe |cffff4444" .. BJ:FormatGold(iOweTotal) .. "|r   |cff666666-|r   Owed to you |cff00ff00" .. BJ:FormatGold(owedToMeTotal) .. "|r"
    )

    if frame.funCheck then
        frame.funCheck:SetChecked(DL:IsFakePlay())
    end

    -- Tab styling
    for id, tab in pairs(frame.tabs) do
        if id == frame.selectedTab then
            tab:SetBackdropColor(0.35, 0.28, 0.1, 1)
            tab:SetBackdropBorderColor(1, 0.8, 0.3, 1)
            tab.text:SetText("|cffffffff" .. tab.label .. "|r")
        else
            tab:SetBackdropColor(0.15, 0.12, 0.08, 1)
            tab:SetBackdropBorderColor(0.4, 0.35, 0.2, 1)
            tab.text:SetText("|cffaaaaaa" .. tab.label .. "|r")
        end
    end

    -- Build the display list for the selected tab
    local items = {}
    if frame.selectedTab == "mine" then
        local iOwe, owedToMe = DL:GetMyDebts()

        table.insert(items, { type = "header", text = "|cffff6644YOU OWE|r" })
        if #iOwe == 0 then
            table.insert(items, { type = "empty", text = "Nothing - you're all square!" })
        end
        for _, d in ipairs(iOwe) do
            table.insert(items, { type = "owe", name = d.name, amount = d.amount, entry = d.entry })
        end

        table.insert(items, { type = "header", text = "|cff44ff66OWED TO YOU|r" })
        if #owedToMe == 0 then
            table.insert(items, { type = "empty", text = "Nobody owes you... yet." })
        end
        for _, d in ipairs(owedToMe) do
            table.insert(items, { type = "owed", name = d.name, amount = d.amount, entry = d.entry })
        end
    else
        local debts = DL:GetAllDebts()
        if #debts == 0 then
            table.insert(items, { type = "empty", text = "No outstanding debts anywhere. A clean casino!" })
        end
        for _, d in ipairs(debts) do
            table.insert(items, { type = "pair", debtor = d.debtor, creditor = d.creditor, amount = d.amount, entry = d.entry })
        end
    end

    -- Render rows
    local me = BJ:MyName()
    local y = 0
    for i, item in ipairs(items) do
        local height = (item.type == "header") and HEADER_ROW_H or ROW_H
        local row = self:GetRow(i)
        PrepareRow(row, y, height)
        row.entryRef = item.entry

        if item.type == "header" then
            row:SetBackdropColor(0.16, 0.13, 0.07, 1)
            row:SetBackdropBorderColor(0.5, 0.4, 0.2, 1)
            row.left:SetText(item.text)
        elseif item.type == "empty" then
            row:SetBackdropColor(0.08, 0.08, 0.1, 0.6)
            row.left:SetText("|cff888888" .. item.text .. "|r")
        elseif item.type == "owe" then
            row.left:SetText("|cffff8866" .. DL:ShortName(item.name) .. "|r")
            row.right:ClearAllPoints()
            row.right:SetPoint("RIGHT", -78, 0)
            row.right:SetText("|cffff4444" .. BJ:FormatGold(item.amount) .. "|r")
            row.actionBtn:Show()
            row.actionBtn:Style("|cffffd700Settle|r", 0.3, 0.24, 0.08)
            local creditorName = item.name
            row.actionBtn:SetScript("OnClick", function()
                DL:SettleWithTrade(creditorName)
            end)
        elseif item.type == "owed" then
            row.left:SetText("|cff88ff99" .. DL:ShortName(item.name) .. "|r")
            row.right:ClearAllPoints()
            row.right:SetPoint("RIGHT", -78, 0)
            row.right:SetText("|cff00ff00" .. BJ:FormatGold(item.amount) .. "|r")
            row.actionBtn:Show()
            row.actionBtn:Style("|cff88ff88Forgive|r", 0.15, 0.25, 0.15)
            local debtorName = item.name
            local amountStr = BJ:FormatGold(item.amount)
            row.actionBtn:SetScript("OnClick", function()
                StaticPopup_Show("CHAIRFACES_DEBT_FORGIVE", DL:ShortName(debtorName), amountStr, debtorName)
            end)
        elseif item.type == "pair" then
            local involvesMe = DL:ShortName(item.debtor) == me or DL:ShortName(item.creditor) == me
            if involvesMe then
                row:SetBackdropBorderColor(0.7, 0.55, 0.2, 1)
            end
            row.left:SetText("|cffff8866" .. DL:ShortName(item.debtor) .. "|r |cffaaaaaa owes|r |cff88ff99" .. DL:ShortName(item.creditor) .. "|r")
            row.right:SetText("|cffffd700" .. BJ:FormatGold(item.amount) .. "|r")
        end

        y = y - height - 2
    end

    -- Hide leftover pooled rows
    for i = #items + 1, #frame.rows do
        frame.rows[i]:Hide()
    end

    frame.content:SetHeight(math.max(100, -y + 10))
end

--[[
    ============================================
    CHAT / SHOW-HIDE
    ============================================
]]

function DF:PostToChat()
    local DL = BJ.DebtLedger
    if not DL then return end
    local debts = DL:GetAllDebts()
    if #debts == 0 then
        BJ:Print("No outstanding debts to post.")
        return
    end
    local channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY" or nil)
    if not channel then
        BJ:Print("Not in a group - nothing posted.")
        return
    end
    SendChatMessage("=== Casino Tab (who owes who) ===", channel)
    for i, d in ipairs(debts) do
        if i > 10 then
            SendChatMessage("...and " .. (#debts - 10) .. " more. See /cc debts.", channel)
            break
        end
        SendChatMessage(DL:ShortName(d.debtor) .. " owes " .. DL:ShortName(d.creditor) .. " " .. BJ:FormatGold(d.amount), channel)
    end
end

function DF:SelectTab(id)
    if not self.frame then return end
    self.frame.selectedTab = id
    self:Refresh()
end

function DF:Show()
    if not self.frame then
        self:CreateFrame()
    end
    self.frame:Show()
    if BJ.ShowPendingVersionWarning then
        BJ:ShowPendingVersionWarning()
    end
    self:Refresh()
end

function DF:Hide()
    if self.frame then
        self.frame:Hide()
    end
end

function DF:Toggle()
    if self.frame and self.frame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end
