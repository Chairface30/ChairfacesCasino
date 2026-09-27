--[[
    Chairface's Casino - UI/TableFinderFrame.lua
    The Table Finder window: an LFG-style board over TableFinder.lua.
    List yourself as hosting a table or looking to play, browse everyone
    else's listings, and whisper/invite straight from the rows.
]]

local BJ = ChairfacesCasino
local UI = BJ.UI

UI.Finder = {}
local FD = UI.Finder

local FRAME_W, FRAME_H = 720, 490  -- landscape, to host the tavern background
local ROW_H = 46

function FD:Initialize()
    if self.frame then return end
    self:CreateFrame()
end

function FD:CreateFrame()
    local frame = CreateFrame("Frame", "ChairfacesCasinoFinder", UIParent, "BackdropTemplate")
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
    frame:SetBackdropColor(0.05, 0.07, 0.09, 0.97)
    frame:SetBackdropBorderColor(0.7, 0.55, 0.2, 1)
    if UI.Lobby and UI.Lobby.ApplyTavernBackground then UI.Lobby:ApplyTavernBackground(frame) end
    frame:Hide()
    self.frame = frame

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("|cffffd700Table Finder|r")
    title:SetFont("Fonts\\FRIZQT__.TTF", 18, "OUTLINE")

    local sub = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sub:SetPoint("TOP", title, "BOTTOM", 0, -2)
    sub:SetText("|cff888888Find players and tables - reaches every addon user on the realm|r")

    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function()
        FD:Hide()
        if UI.Lobby then UI.Lobby:Show() end
    end)

    -- ============================ listing form =============================
    local form = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    form:SetPoint("TOPLEFT", 14, -52)
    form:SetPoint("TOPRIGHT", -14, -52)
    form:SetHeight(104)
    form:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    form:SetBackdropColor(0.03, 0.045, 0.06, 0.9)
    form:SetBackdropBorderColor(0.3, 0.4, 0.5, 1)

    -- ---- host / seek toggle (two exclusive buttons) ----
    self.selKind = "seek"
    local function makeKindBtn(text, x)
        local b = CreateFrame("Button", nil, form, "BackdropTemplate")
        b:SetSize(122, 22)
        b:SetPoint("TOPLEFT", x, -10)
        b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        b.text:SetPoint("CENTER")
        b.text:SetText(text)
        return b
    end
    local seekBtn = makeKindBtn("I want to play", 10)
    local hostBtn = makeKindBtn("I'm hosting a table", 138)

    local function paintKind()
        local on  = { 0.15, 0.35, 0.2, 1 }
        local off = { 0.1, 0.1, 0.12, 1 }
        local pick = (FD.selKind == "seek") and seekBtn or hostBtn
        local other = (pick == seekBtn) and hostBtn or seekBtn
        pick:SetBackdropColor(unpack(on))
        pick:SetBackdropBorderColor(0.4, 0.9, 0.5, 1)
        other:SetBackdropColor(unpack(off))
        other:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
    end
    seekBtn:SetScript("OnClick", function() FD.selKind = "seek"; paintKind() end)
    hostBtn:SetScript("OnClick", function() FD.selKind = "host"; paintKind() end)
    paintKind()

    -- ---- game dropdown ----
    local gameLabel = form:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    gameLabel:SetPoint("TOPLEFT", 10, -44)
    gameLabel:SetText("Game:")

    self.selGame = "any"
    local gameDrop = CreateFrame("Frame", "CCFinderGameDrop", form, "UIDropDownMenuTemplate")
    gameDrop:SetPoint("TOPLEFT", 40, -36)
    UIDropDownMenu_SetWidth(gameDrop, 110)
    UIDropDownMenu_SetText(gameDrop, "Anything")
    UIDropDownMenu_Initialize(gameDrop, function(_, level)
        for _, g in ipairs(BJ.TableFinder.GAMES) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = g.name
            info.checked = (FD.selGame == g.key)
            info.func = function()
                FD.selGame = g.key
                UIDropDownMenu_SetText(gameDrop, g.name)
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    -- ---- stakes box ----
    local stakeLabel = form:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    stakeLabel:SetPoint("TOPLEFT", 200, -44)
    stakeLabel:SetText("Stakes:")
    local stakeBox = CreateFrame("EditBox", nil, form, "InputBoxTemplate")
    stakeBox:SetSize(90, 18)
    stakeBox:SetPoint("TOPLEFT", 248, -41)
    stakeBox:SetAutoFocus(false)
    stakeBox:SetMaxLetters(24)
    self.stakeBox = stakeBox

    -- ---- note box ----
    local noteLabel = form:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    noteLabel:SetPoint("TOPLEFT", 10, -76)
    noteLabel:SetText("Note:")
    local noteBox = CreateFrame("EditBox", nil, form, "InputBoxTemplate")
    noteBox:SetSize(300, 18)
    noteBox:SetPoint("TOPLEFT", 48, -73)
    noteBox:SetAutoFocus(false)
    noteBox:SetMaxLetters(70)
    self.noteBox = noteBox

    -- ---- list / delist ----
    local listBtn = CreateFrame("Button", nil, form, "UIPanelButtonTemplate")
    listBtn:SetSize(100, 22)
    listBtn:SetPoint("TOPRIGHT", -10, -38)
    listBtn:SetText("List Me")
    listBtn:SetScript("OnClick", function()
        BJ.TableFinder:ListMe(FD.selKind, FD.selGame, stakeBox:GetText(), noteBox:GetText())
        BJ.TableFinder:FlushChannelQueue()   -- click = hardware event
        stakeBox:ClearFocus()
        noteBox:ClearFocus()
        FD:Refresh()
    end)

    local delistBtn = CreateFrame("Button", nil, form, "UIPanelButtonTemplate")
    delistBtn:SetSize(100, 22)
    delistBtn:SetPoint("TOPRIGHT", -10, -66)
    delistBtn:SetText("Delist")
    delistBtn:SetScript("OnClick", function()
        BJ.TableFinder:Delist()
        BJ.TableFinder:FlushChannelQueue()
        FD:Refresh()
    end)
    self.delistBtn = delistBtn

    -- ============================ browse list ==============================
    local listHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    listHeader:SetPoint("TOPLEFT", 16, -166)
    listHeader:SetText("|cffffd700Open tables & players|r")
    self.listHeader = listHeader

    local refreshBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    refreshBtn:SetSize(80, 20)
    refreshBtn:SetPoint("TOPRIGHT", -34, -162)
    refreshBtn:SetText("Refresh")
    refreshBtn:SetScript("OnClick", function()
        BJ.TableFinder:RequestListings()
        BJ.TableFinder:FlushChannelQueue()
        FD:Refresh()
    end)

    local scroll = CreateFrame("ScrollFrame", "ChairfacesCasinoFinderScroll", frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 14, -186)
    scroll:SetPoint("BOTTOMRIGHT", -34, 16)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(FRAME_W - 60, 10)
    scroll:SetScrollChild(content)
    self.listContent = content
    self.rows = {}

    -- keep ages/expiry fresh while the window is up
    frame:SetScript("OnShow", function()
        if not FD.ticker then
            FD.ticker = C_Timer.NewTicker(30, function() FD:Refresh() end)
        end
    end)
    frame:SetScript("OnHide", function()
        if FD.ticker then
            FD.ticker:Cancel()
            FD.ticker = nil
        end
    end)

    if BJ.EscapeHandler then
        BJ.EscapeHandler:RegisterFrame("ChairfacesCasinoFinder")
    end
end

local function ageText(seen)
    local s = time() - (seen or 0)
    if s < 60 then return "just now" end
    return math.floor(s / 60) .. "m ago"
end

-- Rebuild the list from TableFinder (rows are pooled).
function FD:Refresh()
    if not self.frame or not self.frame:IsShown() then return end
    local TF = BJ.TableFinder
    local listings = TF:GetListings()
    local content = self.listContent

    self.delistBtn:SetShown(TF.myListing ~= nil)

    for _, row in ipairs(self.rows) do row:Hide() end

    local y = 0
    for i, l in ipairs(listings) do
        local row = self.rows[i]
        if not row then
            row = CreateFrame("Frame", nil, content, "BackdropTemplate")
            row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
            row:SetHeight(ROW_H)

            row.line1 = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            row.line1:SetPoint("TOPLEFT", 8, -7)
            row.line1:SetPoint("RIGHT", -150, 0)
            row.line1:SetJustifyH("LEFT")
            row.line1:SetWordWrap(false)

            -- clickable name line: click to whisper
            row.byline = CreateFrame("Button", nil, row)
            row.byline:SetPoint("TOPLEFT", 8, -25)
            row.byline:SetSize(280, 14)
            row.byline.text = row.byline:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.byline.text:SetPoint("LEFT")
            row.byline.text:SetJustifyH("LEFT")
            row.byline:SetScript("OnEnter", function(b)
                GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
                GameTooltip:AddLine("Click to whisper " .. (b.player or ""), 0.6, 0.8, 1)
                GameTooltip:Show()
            end)
            row.byline:SetScript("OnLeave", function() GameTooltip:Hide() end)
            row.byline:SetScript("OnClick", function(b)
                if b.player and b.player ~= "" and ChatFrame_SendTell then
                    ChatFrame_SendTell(b.player)
                end
            end)

            row.inviteBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            row.inviteBtn:SetSize(60, 20)
            row.inviteBtn:SetPoint("RIGHT", -8, 0)
            row.inviteBtn:SetText("Invite")

            row.whisperBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            row.whisperBtn:SetSize(66, 20)
            row.whisperBtn:SetPoint("RIGHT", row.inviteBtn, "LEFT", -4, 0)
            row.whisperBtn:SetText("Whisper")

            self.rows[i] = row
        end

        local tag = (l.kind == "host")
            and "|cff44dd66[HOSTING]|r"
            or  "|cff66aaff[LF GAME]|r"
        local stakeText = (l.stake and l.stake ~= "") and ("  |cffffd700" .. l.stake .. "|r") or ""
        row.line1:SetText(tag .. " |cffffffff" .. TF:GameName(l.game) .. "|r" .. stakeText)

        row.byline.player = l.name
        local noteText = (l.note and l.note ~= "") and ("  |cffaaaaaa" .. l.note .. "|r") or ""
        row.byline.text:SetText("|cff88bbff" .. l.name .. "|r  |cff666666" .. ageText(l.seen) .. "|r" .. noteText)

        local mine = (l.name == BJ:MyName())
        row.inviteBtn:SetShown(not mine)
        row.whisperBtn:SetShown(not mine)
        row.inviteBtn:SetScript("OnClick", function()
            local invite = C_PartyInfo and C_PartyInfo.InviteUnit or InviteUnit
            if invite then invite(l.name) end
        end)
        row.whisperBtn:SetScript("OnClick", function()
            if ChatFrame_SendTell then ChatFrame_SendTell(l.name) end
        end)

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -y)
        row:SetPoint("TOPRIGHT", 0, -y)
        if l.kind == "host" then
            row:SetBackdropColor(0.05, 0.1, 0.06, 0.85)
            row:SetBackdropBorderColor(0.25, 0.45, 0.28, 0.9)
        else
            row:SetBackdropColor(0.05, 0.07, 0.1, 0.85)
            row:SetBackdropBorderColor(0.25, 0.32, 0.45, 0.9)
        end
        row:Show()
        y = y + ROW_H + 4
    end

    if #listings == 0 then
        if not self.emptyText then
            self.emptyText = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            self.emptyText:SetPoint("TOP", content, "TOP", 0, -20)
        end
        self.emptyText:SetText("|cff888888Nobody is listed right now.\nList yourself above and get a game going!|r")
        self.emptyText:Show()
    elseif self.emptyText then
        self.emptyText:Hide()
    end

    content:SetHeight(math.max(y, 10))
end

function FD:Show()
    self:Initialize()
    -- one window at a time: opening the finder puts the lobby away
    if UI.Lobby and UI.Lobby.frame and UI.Lobby.frame:IsShown() then
        UI.Lobby.frame:Hide()
    end
    -- opening is a click (hardware event): flush queued realm-channel
    -- traffic (login REQ, heartbeats) and ask the board to re-announce
    BJ.TableFinder:RequestListings()
    BJ.TableFinder:FlushChannelQueue()
    self.frame:Show()
    self:Refresh()
end

function FD:Hide()
    if self.frame then self.frame:Hide() end
end

function FD:Toggle()
    self:Initialize()
    if self.frame:IsShown() then self:Hide() else self:Show() end
end
