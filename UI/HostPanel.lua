--[[
    Chairface's Casino - UI/HostPanel.lua
    Host configuration panel for game settings
]]

local BJ = ChairfacesCasino
local UI = BJ.UI

UI.hostPanel = nil

-- Create the host settings panel
function UI:CreateHostPanel()
    if self.hostPanel then return end
    
    local panel = CreateFrame("Frame", "BlackjackHostPanel", UIParent, "BackdropTemplate")
    panel:SetSize(300, 490)
    panel:SetPoint("CENTER", 0, 20)
    panel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 3,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    panel:SetBackdropColor(0.08, 0.08, 0.08, 0.98)
    panel:SetBackdropBorderColor(1, 0.84, 0, 1)
    panel:SetFrameStrata("DIALOG")
    panel:SetFrameLevel(100)
    
    -- Title
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("Host Settings")
    title:SetTextColor(1, 0.84, 0, 1)
    
    local yOffset = -45
    local HS = BJ.HostSettings
    
    -- ============ ANTE INPUT ============
    local anteLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    anteLabel:SetPoint("TOPLEFT", 20, yOffset)
    anteLabel:SetText("Ante Amount (1-1000g):")
    anteLabel:SetTextColor(1, 1, 1, 1)
    
    yOffset = yOffset - 25
    
    -- Input box for ante
    local anteInputBox = CreateFrame("EditBox", "BlackjackAnteInput", panel, "BackdropTemplate")
    anteInputBox:SetSize(120, 30)
    anteInputBox:SetPoint("TOPLEFT", 20, yOffset)
    anteInputBox:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
        insets = { left = 5, right = 5, top = 5, bottom = 5 }
    })
    anteInputBox:SetBackdropColor(0.1, 0.1, 0.1, 1)
    anteInputBox:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    anteInputBox:SetFontObject("GameFontNormalLarge")
    anteInputBox:SetTextColor(1, 1, 1, 1)
    anteInputBox:SetJustifyH("CENTER")
    anteInputBox:SetAutoFocus(false)
    anteInputBox:SetNumeric(true)
    anteInputBox:SetMaxLetters(4)
    anteInputBox:SetText(tostring(HS:Get("ante")))
    
    anteInputBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    anteInputBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    anteInputBox:SetScript("OnEditFocusLost", function(self)
        local val = tonumber(self:GetText()) or 1
        val = math.max(1, math.min(1000, val))
        self:SetText(tostring(val))
        HS:Set("ante", val)
    end)
    
    -- Gold label
    local goldLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    goldLabel:SetPoint("LEFT", anteInputBox, "RIGHT", 8, 0)
    goldLabel:SetText("g")
    goldLabel:SetTextColor(1, 0.84, 0, 1)
    
    panel.anteInputBox = anteInputBox
    
    -- ============ MAX MULTIPLIER ============
    yOffset = yOffset - 50
    
    local multLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    multLabel:SetPoint("TOPLEFT", 20, yOffset)
    multLabel:SetText("Max Bet Multiple:")
    multLabel:SetTextColor(1, 1, 1, 1)
    
    local multValue = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    multValue:SetPoint("LEFT", multLabel, "RIGHT", 10, 0)
    multValue:SetTextColor(0.7, 0.7, 0.7, 1)
    panel.multValue = multValue
    
    -- Multiplier buttons
    local multButtons = {}
    local multBtnX = 20
    yOffset = yOffset - 30
    
    local multiplierOptions = { 1, 2, 5, 10 }
    for i, mult in ipairs(multiplierOptions) do
        local btn = CreateFrame("Button", nil, panel, "BackdropTemplate")
        btn:SetSize(60, 28)
        btn:SetPoint("TOPLEFT", multBtnX, yOffset)
        btn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        btn:SetBackdropColor(0.15, 0.15, 0.15, 1)
        btn:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
        
        local text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        text:SetPoint("CENTER")
        text:SetText(mult == 1 and "None" or mult .. "x")
        btn.text = text
        btn.value = mult
        
        btn:SetScript("OnClick", function(self)
            HS:Set("maxMultiplier", self.value)
            UI:UpdateHostPanel()
        end)
        
        btn:SetScript("OnEnter", function(self)
            if HS:Get("maxMultiplier") ~= self.value then
                self:SetBackdropBorderColor(1, 0.84, 0, 1)
            end
        end)
        
        btn:SetScript("OnLeave", function(self)
            if HS:Get("maxMultiplier") ~= self.value then
                self:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
            end
        end)
        
        multButtons[mult] = btn
        multBtnX = multBtnX + 65
    end
    panel.multButtons = multButtons
    
    -- ============ MAX PLAYERS ============
    yOffset = yOffset - 45
    
    local maxPLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    maxPLabel:SetPoint("TOPLEFT", 20, yOffset)
    maxPLabel:SetText("Max Players:")
    maxPLabel:SetTextColor(1, 1, 1, 1)
    
    local maxPValue = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    maxPValue:SetPoint("LEFT", maxPLabel, "RIGHT", 10, 0)
    maxPValue:SetTextColor(0.7, 0.7, 0.7, 1)
    panel.maxPValue = maxPValue
    
    -- Max players buttons
    local maxPButtons = {}
    local maxPBtnX = 20
    yOffset = yOffset - 30
    
    local maxPlayersOptions = { 2, 4, 6, 10, 15, 20 }
    for i, maxP in ipairs(maxPlayersOptions) do
        local btn = CreateFrame("Button", nil, panel, "BackdropTemplate")
        btn:SetSize(40, 26)
        btn:SetPoint("TOPLEFT", maxPBtnX, yOffset)
        btn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        btn:SetBackdropColor(0.15, 0.15, 0.15, 1)
        btn:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
        
        local text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetPoint("CENTER")
        text:SetText(tostring(maxP))
        btn.text = text
        btn.value = maxP
        
        btn:SetScript("OnClick", function(self)
            HS:Set("maxPlayers", self.value)
            UI:UpdateHostPanel()
        end)
        
        btn:SetScript("OnEnter", function(self)
            if HS:Get("maxPlayers") ~= self.value then
                self:SetBackdropBorderColor(1, 0.84, 0, 1)
            end
        end)
        
        btn:SetScript("OnLeave", function(self)
            if HS:Get("maxPlayers") ~= self.value then
                self:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
            end
        end)
        
        maxPButtons[maxP] = btn
        maxPBtnX = maxPBtnX + 44
    end
    panel.maxPButtons = maxPButtons
    
    -- ============ COUNTDOWN ============
    yOffset = yOffset - 45
    
    local cdLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cdLabel:SetPoint("TOPLEFT", 20, yOffset)
    cdLabel:SetText("Betting Countdown:")
    cdLabel:SetTextColor(1, 1, 1, 1)
    
    local cdToggle = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    cdToggle:SetPoint("LEFT", cdLabel, "RIGHT", 5, 0)
    cdToggle:SetChecked(HS:Get("countdownEnabled"))
    cdToggle:SetScript("OnClick", function(self)
        HS:Set("countdownEnabled", self:GetChecked())
        UI:UpdateHostPanel()
    end)
    panel.cdToggle = cdToggle
    
    local cdStatus = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cdStatus:SetPoint("LEFT", cdToggle, "RIGHT", 2, 0)
    cdStatus:SetTextColor(0.7, 0.7, 0.7, 1)
    panel.cdStatus = cdStatus
    
    -- Countdown seconds buttons
    local cdButtons = {}
    local cdBtnX = 20
    yOffset = yOffset - 30
    
    local countdownOptions = { 10, 15, 20, 30, 45, 60 }
    for i, secs in ipairs(countdownOptions) do
        local btn = CreateFrame("Button", nil, panel, "BackdropTemplate")
        btn:SetSize(40, 26)
        btn:SetPoint("TOPLEFT", cdBtnX, yOffset)
        btn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        btn:SetBackdropColor(0.15, 0.15, 0.15, 1)
        btn:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
        
        local text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetPoint("CENTER")
        text:SetText(secs .. "s")
        btn.text = text
        btn.value = secs
        
        btn:SetScript("OnClick", function(self)
            HS:Set("countdownSeconds", self.value)
            HS:Set("countdownEnabled", true)
            panel.cdToggle:SetChecked(true)
            UI:UpdateHostPanel()
        end)
        
        btn:SetScript("OnEnter", function(self)
            local cdEnabled = HS:Get("countdownEnabled")
            if cdEnabled and HS:Get("countdownSeconds") ~= self.value then
                self:SetBackdropBorderColor(1, 0.84, 0, 1)
            end
        end)
        
        btn:SetScript("OnLeave", function(self)
            local cdEnabled = HS:Get("countdownEnabled")
            if not cdEnabled or HS:Get("countdownSeconds") ~= self.value then
                self:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
            end
        end)
        
        cdButtons[secs] = btn
        cdBtnX = cdBtnX + 44
    end
    panel.cdButtons = cdButtons
    
    -- ============ DEALER RULE (H17/S17) ============
    yOffset = yOffset - 45
    
    local ruleLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ruleLabel:SetPoint("TOPLEFT", 20, yOffset)
    ruleLabel:SetText("Dealer Soft 17:")
    ruleLabel:SetTextColor(1, 1, 1, 1)
    
    -- H17 button
    local h17Btn = CreateFrame("Button", nil, panel, "BackdropTemplate")
    h17Btn:SetSize(70, 28)
    h17Btn:SetPoint("LEFT", ruleLabel, "RIGHT", 15, 0)
    h17Btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    h17Btn:SetBackdropColor(0.15, 0.15, 0.15, 1)
    h17Btn:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    
    local h17Text = h17Btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    h17Text:SetPoint("CENTER")
    h17Text:SetText("H17 (Hit)")
    h17Btn.text = h17Text
    
    h17Btn:SetScript("OnClick", function()
        HS:Set("dealerHitsSoft17", true)
        UI:UpdateHostPanel()
    end)
    h17Btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Dealer HITS on Soft 17", 1, 0.84, 0)
        GameTooltip:AddLine("More common rule, slightly favors house", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    h17Btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    panel.h17Btn = h17Btn
    
    -- S17 button
    local s17Btn = CreateFrame("Button", nil, panel, "BackdropTemplate")
    s17Btn:SetSize(80, 28)
    s17Btn:SetPoint("LEFT", h17Btn, "RIGHT", 8, 0)
    s17Btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    s17Btn:SetBackdropColor(0.15, 0.15, 0.15, 1)
    s17Btn:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    
    local s17Text = s17Btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    s17Text:SetPoint("CENTER")
    s17Text:SetText("S17 (Stand)")
    s17Btn.text = s17Text
    
    s17Btn:SetScript("OnClick", function()
        HS:Set("dealerHitsSoft17", false)
        UI:UpdateHostPanel()
    end)
    s17Btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Dealer STANDS on Soft 17", 1, 0.84, 0)
        GameTooltip:AddLine("Better for players", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    s17Btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    panel.s17Btn = s17Btn
    
    -- ============ START GAME BUTTON ============
    local startBtn = CreateFrame("Button", nil, panel, "BackdropTemplate")
    startBtn:SetSize(150, 40)
    startBtn:SetPoint("BOTTOM", 0, 70)
    startBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    startBtn:SetBackdropColor(0.2, 0.55, 0.2, 1)
    startBtn:SetBackdropBorderColor(0.4, 0.9, 0.4, 1)
    
    local startText = startBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    startText:SetPoint("CENTER")
    startText:SetText("START GAME")
    startText:SetTextColor(1, 1, 1, 1)
    
    startBtn:SetScript("OnClick", function()
        -- Save the ante from input box
        local anteVal = tonumber(panel.anteInputBox:GetText()) or 50
        anteVal = math.max(1, math.min(1000, anteVal))
        HS:Set("ante", anteVal)
        
        panel:Hide()
        BJ.Multiplayer:HostTable()
    end)
    
    startBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.25, 0.65, 0.25, 1)
    end)
    
    startBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.2, 0.55, 0.2, 1)
    end)
    panel.startBtn = startBtn
    
    -- ============ CANCEL BUTTON ============
    local cancelBtn = CreateFrame("Button", nil, panel, "BackdropTemplate")
    cancelBtn:SetSize(80, 28)
    cancelBtn:SetPoint("BOTTOM", 0, 20)
    cancelBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    cancelBtn:SetBackdropColor(0.4, 0.15, 0.15, 1)
    cancelBtn:SetBackdropBorderColor(0.6, 0.3, 0.3, 1)
    
    local cancelText = cancelBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cancelText:SetPoint("CENTER")
    cancelText:SetText("Cancel")
    
    cancelBtn:SetScript("OnClick", function()
        panel:Hide()
    end)
    
    cancelBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.5, 0.2, 0.2, 1)
    end)
    
    cancelBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.4, 0.15, 0.15, 1)
    end)
    
    panel:Hide()
    self.hostPanel = panel
    self:UpdateHostPanel()
end

-- Update host panel display
function UI:UpdateHostPanel()
    if not self.hostPanel then return end
    
    local HS = BJ.HostSettings
    local panel = self.hostPanel
    
    -- Update ante input
    panel.anteInputBox:SetText(tostring(HS:Get("ante")))
    
    -- Update multiplier display and buttons
    local maxMult = HS:Get("maxMultiplier")
    if maxMult == 1 then
        panel.multValue:SetText("(Ante only)")
    else
        panel.multValue:SetText("(Up to " .. maxMult .. "x)")
    end
    
    for mult, btn in pairs(panel.multButtons) do
        if mult == maxMult then
            btn:SetBackdropColor(0.2, 0.5, 0.2, 1)
            btn:SetBackdropBorderColor(0.4, 0.9, 0.4, 1)
            btn.text:SetTextColor(1, 1, 1, 1)
        else
            btn:SetBackdropColor(0.15, 0.15, 0.15, 1)
            btn:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
            btn.text:SetTextColor(0.7, 0.7, 0.7, 1)
        end
    end
    
    -- Update max players display and buttons
    local maxPlayers = HS:Get("maxPlayers") or 20
    panel.maxPValue:SetText("(" .. maxPlayers .. " max)")
    
    for maxP, btn in pairs(panel.maxPButtons) do
        if maxP == maxPlayers then
            btn:SetBackdropColor(0.2, 0.5, 0.2, 1)
            btn:SetBackdropBorderColor(0.4, 0.9, 0.4, 1)
            btn.text:SetTextColor(1, 1, 1, 1)
        else
            btn:SetBackdropColor(0.15, 0.15, 0.15, 1)
            btn:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
            btn.text:SetTextColor(0.7, 0.7, 0.7, 1)
        end
    end
    
    -- Update countdown display
    local cdEnabled = HS:Get("countdownEnabled")
    panel.cdToggle:SetChecked(cdEnabled)
    
    if cdEnabled then
        panel.cdStatus:SetText(HS:Get("countdownSeconds") .. "s")
    else
        panel.cdStatus:SetText("(Manual)")
    end
    
    for secs, btn in pairs(panel.cdButtons) do
        if cdEnabled and secs == HS:Get("countdownSeconds") then
            btn:SetBackdropColor(0.2, 0.5, 0.2, 1)
            btn:SetBackdropBorderColor(0.4, 0.9, 0.4, 1)
            btn.text:SetTextColor(1, 1, 1, 1)
        else
            btn:SetBackdropColor(0.15, 0.15, 0.15, 1)
            btn:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
            btn.text:SetTextColor(0.6, 0.6, 0.6, 1)
        end
        
        -- Dim if countdown disabled
        if cdEnabled then
            btn:SetAlpha(1)
        else
            btn:SetAlpha(0.4)
        end
    end
    
    -- Update H17/S17 buttons
    local hitsSoft17 = HS:Get("dealerHitsSoft17")
    if hitsSoft17 == nil then hitsSoft17 = true end  -- Default to H17
    
    if hitsSoft17 then
        panel.h17Btn:SetBackdropColor(0.2, 0.5, 0.2, 1)
        panel.h17Btn:SetBackdropBorderColor(0.4, 0.9, 0.4, 1)
        panel.h17Btn.text:SetTextColor(1, 1, 1, 1)
        panel.s17Btn:SetBackdropColor(0.15, 0.15, 0.15, 1)
        panel.s17Btn:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
        panel.s17Btn.text:SetTextColor(0.7, 0.7, 0.7, 1)
    else
        panel.h17Btn:SetBackdropColor(0.15, 0.15, 0.15, 1)
        panel.h17Btn:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
        panel.h17Btn.text:SetTextColor(0.7, 0.7, 0.7, 1)
        panel.s17Btn:SetBackdropColor(0.2, 0.5, 0.2, 1)
        panel.s17Btn:SetBackdropBorderColor(0.4, 0.9, 0.4, 1)
        panel.s17Btn.text:SetTextColor(1, 1, 1, 1)
    end
end

-- Show host panel
function UI:ShowHostPanel()
    if not self.hostPanel then
        self:CreateHostPanel()
    end
    
    -- Check if can host - but allow during settlement phase
    local GS = BJ.GameState
    if GS.phase ~= GS.PHASE.SETTLEMENT and GS.phase ~= GS.PHASE.IDLE then
        local canStart, reason = BJ.SessionManager:CanStartSession()
        if not canStart then
            BJ:Print("Cannot host: " .. reason)
            return
        end
    end
    
    -- Check if in group (bypass in test mode)
    local inTestMode = BJ.TestMode and BJ.TestMode.enabled
    if not IsInGroup() and not inTestMode then
        BJ:Print("You must be in a party or raid to host.")
        return
    end
    
    self:UpdateHostPanel()
    self.hostPanel:Show()
    self.hostPanel.anteInputBox:SetFocus()
end
