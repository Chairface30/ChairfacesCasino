--[[
    Chairface's Casino - UI/DeathRollFrame.lua
    Death Roll game window: stake, the two duelists, the shrinking roll
    ceiling, roll history, and one context-sensitive action button.
]]

local BJ = ChairfacesCasino
local UI = BJ.UI

UI.DeathRoll = {}
local DRUI = UI.DeathRoll

local FRAME_WIDTH = 340
local FRAME_HEIGHT = 440

function DRUI:Initialize()
    if self.frame then return end
    self:CreateFrame()
end

function DRUI:CreateFrame()
    local frame = CreateFrame("Frame", "ChairfacesCasinoDeathRoll", UIParent, "BackdropTemplate")
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
    title:SetText("|cffffd700Death Roll|r")
    title:SetFont("Fonts\\FRIZQT__.TTF", 20, "OUTLINE")

    -- Close button (returns to the lobby)
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function()
        DRUI:Hide()
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
        UI.Lobby:AttachHowToPlayButton(frame, "deathroll", 8, -8)
    end

    -- Trixie deals here too
    if UI.Lobby and UI.Lobby.AttachTrixie then
        UI.Lobby:AttachTrixie(frame, "deathroll")
    end

    -- Status line
    local status = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    status:SetPoint("TOP", title, "BOTTOM", 0, -6)
    status:SetWidth(FRAME_WIDTH - 30)
    status:SetText("")
    self.statusText = status

    -- Stake line
    local stake = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    stake:SetPoint("TOP", status, "BOTTOM", 0, -6)
    stake:SetText("")
    self.stakeText = stake

    -- The two duelists
    local vsFrame = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    vsFrame:SetSize(FRAME_WIDTH - 30, 46)
    vsFrame:SetPoint("TOP", stake, "BOTTOM", 0, -8)
    vsFrame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    vsFrame:SetBackdropColor(0.05, 0.05, 0.06, 0.9)
    vsFrame:SetBackdropBorderColor(0.35, 0.3, 0.15, 1)

    local hostText = vsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hostText:SetPoint("LEFT", 12, 0)
    hostText:SetWidth((FRAME_WIDTH - 30) / 2 - 24)
    hostText:SetJustifyH("LEFT")
    self.hostText = hostText

    local vsText = vsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    vsText:SetPoint("CENTER")
    vsText:SetText("|cff888888vs|r")

    local oppText = vsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    oppText:SetPoint("RIGHT", -12, 0)
    oppText:SetWidth((FRAME_WIDTH - 30) / 2 - 24)
    oppText:SetJustifyH("RIGHT")
    self.oppText = oppText

    -- The shrinking ceiling
    local bigNumber = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    bigNumber:SetPoint("TOP", vsFrame, "BOTTOM", 0, -14)
    bigNumber:SetFont("Fonts\\FRIZQT__.TTF", 44, "OUTLINE")
    bigNumber:SetText("")
    self.bigNumber = bigNumber

    local bigLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bigLabel:SetPoint("TOP", bigNumber, "BOTTOM", 0, -2)
    bigLabel:SetText("")
    self.bigLabel = bigLabel

    -- Roll history
    local history = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    history:SetPoint("TOP", bigLabel, "BOTTOM", 0, -10)
    history:SetPoint("LEFT", frame, "LEFT", 18, 0)
    history:SetPoint("RIGHT", frame, "RIGHT", -18, 0)
    history:SetHeight(110)
    history:SetJustifyH("CENTER")
    history:SetJustifyV("TOP")
    history:SetText("")
    self.historyText = history

    -- Stake input (host, idle only)
    local stakeBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    stakeBox:SetSize(70, 24)
    stakeBox:SetPoint("BOTTOM", frame, "BOTTOM", -110, 52)
    stakeBox:SetAutoFocus(false)
    stakeBox:SetNumeric(true)
    stakeBox:SetMaxLetters(7)
    stakeBox:SetText(tostring(BJ.HostSettings and BJ.HostSettings:Get("deathrollStake") or 100))
    stakeBox:SetScript("OnEnterPressed", function(box) box:ClearFocus() end)
    stakeBox:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)
    stakeBox:SetScript("OnTextChanged", function()
        DRUI:SyncStartDefault()
    end)
    self.stakeBox = stakeBox

    local stakeLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    stakeLabel:SetPoint("BOTTOM", stakeBox, "TOP", -3, 3)
    stakeLabel:SetText("|cffffd700Stake (g)|r")
    self.stakeLabel = stakeLabel

    -- First-roll ceiling input (host, idle only). Groups have different
    -- traditions for the opening roll, so the host dictates it; defaults
    -- to 10x the stake until the host types their own number.
    local startBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    startBox:SetSize(70, 24)
    startBox:SetPoint("BOTTOM", frame, "BOTTOM", -30, 52)
    startBox:SetAutoFocus(false)
    startBox:SetNumeric(true)
    startBox:SetMaxLetters(7)
    startBox:SetText(tostring((BJ.HostSettings and BJ.HostSettings:Get("deathrollStake") or 100) * 10))
    startBox:SetScript("OnEnterPressed", function(box) box:ClearFocus() end)
    startBox:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)
    startBox:SetScript("OnTextChanged", function(box, userInput)
        if userInput then
            -- Clearing the box hands control back to the 10x default
            DRUI.startEdited = (box:GetText() ~= "")
            if not DRUI.startEdited then
                DRUI:SyncStartDefault()
            end
        end
    end)
    self.startBox = startBox

    local startLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    startLabel:SetPoint("BOTTOM", startBox, "TOP", -3, 3)
    startLabel:SetText("|cffffd700First roll|r")
    self.startLabel = startLabel

    -- Main action button (context-sensitive)
    local actionBtn = CreateFrame("Button", nil, frame, "BackdropTemplate")
    actionBtn:SetSize(140, 36)
    actionBtn:SetPoint("BOTTOM", frame, "BOTTOM", 90, 46)
    actionBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
    local actionText = actionBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    actionText:SetPoint("CENTER")
    actionBtn.text = actionText
    actionBtn:SetScript("OnClick", function() DRUI:OnActionClick() end)
    self.actionBtn = actionBtn

    -- Fake play (fun games record no debts) right where hosting starts
    if BJ.UI.Debts and BJ.UI.Debts.AttachFakePlayCheck then
        BJ.UI.Debts:AttachFakePlayCheck(frame, "BOTTOM", actionBtn, "TOP", -30, 2)
    end

    -- Result banner
    local resultText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    resultText:SetPoint("BOTTOM", frame, "BOTTOM", 0, 14)
    resultText:SetWidth(FRAME_WIDTH - 24)
    resultText:SetText("")
    self.resultText = resultText

    -- Purple test-mode bar (debug tools, GUI counterpart to /cc test ...)
    self:CreateTestBar()

    -- Register Escape-key close
    if BJ.EscapeHandler then
        BJ.EscapeHandler:RegisterFrame("ChairfacesCasinoDeathRoll")
    end
end

--[[
    TEST BAR (visible only while /cc db test mode is on)
]]
function DRUI:CreateTestBar()
    local bar = CreateFrame("Frame", nil, self.frame, "BackdropTemplate")
    bar:SetSize(220, 35)
    bar:SetPoint("TOP", self.frame, "BOTTOM", 0, -5)
    bar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
    bar:SetBackdropColor(0.15, 0.1, 0.2, 0.95)
    bar:SetBackdropBorderColor(1, 0.4, 1, 1)

    local label = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", 10, 0)
    label:SetText("|cffff00ffTEST|r")

    local acceptBtn = CreateFrame("Button", nil, bar, "BackdropTemplate")
    acceptBtn:SetSize(110, 24)
    acceptBtn:SetPoint("LEFT", label, "RIGHT", 8, 0)
    acceptBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    acceptBtn:SetBackdropColor(0.3, 0.2, 0.4, 1)
    acceptBtn:SetBackdropBorderColor(0.6, 0.4, 0.8, 1)
    acceptBtn.text = acceptBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    acceptBtn.text:SetPoint("CENTER")
    acceptBtn.text:SetText("FAKE ACCEPT")
    acceptBtn:SetScript("OnClick", function()
        if BJ.TestMode then
            BJ.TestMode:DeathRollFakeAccept()
        end
    end)
    acceptBtn:SetScript("OnEnter", function(s) s:SetBackdropColor(0.4, 0.3, 0.5, 1) end)
    acceptBtn:SetScript("OnLeave", function(s) s:SetBackdropColor(0.3, 0.2, 0.4, 1) end)

    bar:Hide()
    self.testBar = bar
end

function DRUI:RefreshTestBar()
    if not self.testBar then return end
    if BJ.TestMode and BJ.TestMode.enabled then
        self.testBar:Show()
    else
        self.testBar:Hide()
    end
end

-- Keep the first-roll box at 10x the stake until the host edits it
function DRUI:SyncStartDefault()
    if not self.startBox or self.startEdited then return end
    local stake = tonumber(self.stakeBox and self.stakeBox:GetText()) or 0
    self.startBox:SetText(tostring(stake * 10))
end

-- Enable/disable + color the action button
local function setAction(self, label, enabled, r, g, b)
    local btn = self.actionBtn
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

function DRUI:OnActionClick()
    local DR = BJ.DeathRollState
    local DRM = BJ.DeathRollMultiplayer
    local myName = UnitName("player")

    if DR.phase == DR.PHASE.IDLE or DR.phase == DR.PHASE.SETTLEMENT then
        -- Host a new challenge
        local stake = tonumber(self.stakeBox:GetText()) or 0
        local startRoll = tonumber(self.startBox:GetText())
        DRM:HostTable(stake, startRoll)
    elseif DR.phase == DR.PHASE.WAITING then
        if DRM.isHost then
            DRM:CloseTable()
        else
            DRM:RequestJoin()
        end
    elseif DR.phase == DR.PHASE.ROLLING then
        if DR.currentRoller == myName then
            RandomRoll(1, DR.currentMax)
        end
    end

    self:UpdateDisplay()
end

function DRUI:UpdateDisplay()
    if not self.frame then return end

    local DR = BJ.DeathRollState
    local DRM = BJ.DeathRollMultiplayer
    local myName = UnitName("player")
    local iAmPlayer = (myName == DR.hostName or myName == DR.opponent)

    -- Clear FREE PLAY badge by default; the ACCEPT branch re-shows it.
    if BJ.UI and BJ.UI.Debts then
        BJ.UI.Debts:SetJoinFakeBadge(self.actionBtn, false)
    end

    -- Duelists
    local function nameLine(name)
        if not name then return "|cff666666(open seat)|r" end
        local marker = (DR.phase == DR.PHASE.ROLLING and name == DR.currentRoller) and "|cffffd700> |r" or ""
        local color = (name == myName) and "|cff88ff88" or "|cffffffff"
        return marker .. color .. name .. "|r"
    end
    self.hostText:SetText(nameLine(DR.hostName))
    self.oppText:SetText(nameLine(DR.opponent))

    -- Stake
    if DR.stake and DR.stake > 0 then
        self.stakeText:SetText("Stake: |cffffd700" .. DR.stake .. "g|r")
    else
        self.stakeText:SetText("")
    end

    -- Roll history (latest 8)
    local lines = {}
    local firstShown = math.max(1, #DR.rolls - 7)
    for i = firstShown, #DR.rolls do
        local r = DR.rolls[i]
        local color = r.roll == 1 and "ff4444" or "ffffff"
        table.insert(lines, r.player .. " rolled |cff" .. color .. r.roll .. "|r (1-" .. r.max .. ")")
    end
    self.historyText:SetText(table.concat(lines, "\n"))

    -- Phase-specific chrome
    local inTestMode = BJ.TestMode and BJ.TestMode.enabled
    local grouped = IsInGroup() or IsInRaid() or inTestMode

    self.stakeBox:Hide()
    self.stakeLabel:Hide()
    self.startBox:Hide()
    self.startLabel:Hide()
    self.resultText:SetText("")

    if DR.phase == DR.PHASE.IDLE or DR.phase == DR.PHASE.SETTLEMENT then
        if DR.phase == DR.PHASE.SETTLEMENT then
            self.statusText:SetText("|cffffd700Game over!|r")
            self.resultText:SetText(DR:GetSettlementText())
            self.bigNumber:SetText("|cffff44441|r")
            self.bigLabel:SetText("|cffff4444DEATH|r")
        else
            self.statusText:SetText(grouped and "Open a challenge - loser owes the stake."
                or "|cffff8800Join a party or raid to play.|r")
            self.bigNumber:SetText("")
            self.bigLabel:SetText("")
        end
        self.stakeBox:Show()
        self.stakeLabel:Show()
        self.startBox:Show()
        self.startLabel:Show()
        setAction(self, "HOST CHALLENGE", grouped, 0.15, 0.35, 0.15)

    elseif DR.phase == DR.PHASE.WAITING then
        self.bigNumber:SetText("|cffffd700" .. DR.currentMax .. "|r")
        self.bigLabel:SetText("first roll: /roll " .. DR.currentMax)
        if DRM.isHost then
            self.statusText:SetText("Waiting for someone to accept...")
            setAction(self, "CANCEL", true, 0.35, 0.15, 0.15)
        else
            self.statusText:SetText(DR.hostName .. " challenges anyone for " .. DR.stake .. "g!")
            setAction(self, "ACCEPT (" .. DR.stake .. "g)", true, 0.15, 0.35, 0.15)
            -- lift the badge above the fake-play checkbox pinned over this button
            if BJ.UI and BJ.UI.Debts then
                BJ.UI.Debts:SetJoinFakeBadge(self.actionBtn, DR.fakePlay == true, 26)
            end
        end

    elseif DR.phase == DR.PHASE.ROLLING then
        self.bigNumber:SetText("|cffffd700" .. DR.currentMax .. "|r")
        self.bigLabel:SetText("/roll " .. DR.currentMax .. " - a 1 loses!")
        if DR.currentRoller == myName then
            self.statusText:SetText("|cff00ff00Your roll!|r")
            setAction(self, "ROLL 1-" .. DR.currentMax, true, 0.35, 0.28, 0.1)
        elseif iAmPlayer then
            self.statusText:SetText("Waiting for " .. (DR.currentRoller or "?") .. " to roll...")
            setAction(self, "WAITING...", false)
        else
            self.statusText:SetText((DR.currentRoller or "?") .. " is rolling... (spectating)")
            setAction(self, "SPECTATING", false)
        end
    end

    self:RefreshTestBar()
end

function DRUI:Show()
    self:Initialize()
    self:UpdateDisplay()
    self.frame:Show()

    -- Show any deferred version warning now that a casino window is open
    if BJ.ShowPendingVersionWarning then
        BJ:ShowPendingVersionWarning()
    end
end

function DRUI:Hide()
    if self.frame then
        self.frame:Hide()
    end
end
