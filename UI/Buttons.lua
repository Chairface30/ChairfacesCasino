--[[
    Chairface's Casino - UI/Buttons.lua
    Button creation and bet selector popup
]]

local BJ = ChairfacesCasino
BJ.UI = BJ.UI or {}
local UI = BJ.UI

UI.Buttons = {}
local Buttons = UI.Buttons

-- Create a styled game button
function Buttons:CreateGameButton(parent, name, text, width)
    local btn = CreateFrame("Button", "BlackjackBtn" .. name, parent, "BackdropTemplate")
    btn:SetSize(width or 70, 35)
    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    -- Disabled state by default (gray)
    btn:SetBackdropColor(0.1, 0.1, 0.1, 0.7)
    btn:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.7)
    
    local btnText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btnText:SetPoint("CENTER")
    btnText:SetText(text)
    btn.text = btnText
    
    btn:SetScript("OnEnter", function(self)
        if self:IsEnabled() then
            -- Hover: brighter green (like blackjack button hover)
            self:SetBackdropColor(0.2, 0.5, 0.2, 1)
            self:SetBackdropBorderColor(0.4, 1, 0.4, 1)
        end
    end)
    
    btn:SetScript("OnLeave", function(self)
        if self:IsEnabled() then
            if self.highlighted then
                -- Highlighted state (gold)
                self:SetBackdropColor(0.3, 0.25, 0.1, 1)
                self:SetBackdropBorderColor(0.6, 0.5, 0.2, 1)
            else
                -- Normal enabled state (green like blackjack button)
                self:SetBackdropColor(0.15, 0.35, 0.15, 1)
                self:SetBackdropBorderColor(0.3, 0.7, 0.3, 1)
            end
        end
    end)
    
    btn:SetScript("OnDisable", function(self)
        self:SetBackdropColor(0.1, 0.1, 0.1, 0.7)
        self:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.7)
        self.text:SetTextColor(0.5, 0.5, 0.5, 1)
    end)
    
    btn:SetScript("OnEnable", function(self)
        -- Enabled: green like blackjack button
        self:SetBackdropColor(0.15, 0.35, 0.15, 1)
        self:SetBackdropBorderColor(0.3, 0.7, 0.3, 1)
        self.text:SetTextColor(1, 1, 1, 1)
    end)
    
    return btn
end

-- Set button highlight state (gold for action needed)
function Buttons:SetButtonHighlight(btn, highlighted)
    btn.highlighted = highlighted
    if highlighted then
        -- Gold highlight for action needed
        btn:SetBackdropColor(0.3, 0.25, 0.1, 1)
        btn:SetBackdropBorderColor(0.6, 0.5, 0.2, 1)
    else
        if btn:IsEnabled() then
            -- Green enabled state
            btn:SetBackdropColor(0.15, 0.35, 0.15, 1)
            btn:SetBackdropBorderColor(0.3, 0.7, 0.3, 1)
        else
            -- Gray disabled state
            btn:SetBackdropColor(0.1, 0.1, 0.1, 0.7)
            btn:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.7)
        end
    end
end

-- Bet selector popup
UI.betPopup = nil

function UI:CreateBetSelector()
    if self.betPopup then return end
    
    local popup = CreateFrame("Frame", "BlackjackBetPopup", self.mainFrame, "BackdropTemplate")
    popup:SetSize(220, 160)
    popup:SetPoint("CENTER")
    popup:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    popup:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
    popup:SetBackdropBorderColor(1, 0.84, 0, 1)
    popup:SetFrameLevel(self.mainFrame:GetFrameLevel() + 20)
    
    local title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -10)
    title:SetText("Place Your Bet")
    title:SetTextColor(1, 0.84, 0, 1)
    
    -- Bet amount display
    local betDisplay = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    betDisplay:SetPoint("TOP", title, "BOTTOM", 0, -15)
    betDisplay:SetFont("Fonts\\FRIZQT__.TTF", 24, "OUTLINE")
    betDisplay:SetTextColor(1, 1, 1, 1)
    popup.betDisplay = betDisplay
    
    -- Bet multiplier buttons container
    local btnContainer = CreateFrame("Frame", nil, popup)
    btnContainer:SetSize(200, 35)
    btnContainer:SetPoint("TOP", betDisplay, "BOTTOM", 0, -10)
    popup.btnContainer = btnContainer
    
    popup.currentMultiplier = 1
    popup.multiplierButtons = {}
    
    -- Confirm button
    local confirmBtn = CreateFrame("Button", nil, popup, "BackdropTemplate")
    confirmBtn:SetSize(80, 30)
    confirmBtn:SetPoint("BOTTOM", 0, 10)
    confirmBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    confirmBtn:SetBackdropColor(0.2, 0.5, 0.2, 1)
    confirmBtn:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    
    local confirmText = confirmBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    confirmText:SetPoint("CENTER")
    confirmText:SetText("BET")
    
    confirmBtn:SetScript("OnClick", function()
        local amount = BJ.GameState.ante * popup.currentMultiplier
        BJ.Multiplayer:PlaceAnte(amount)
        popup:Hide()
    end)
    
    confirmBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.3, 0.6, 0.3, 1)
    end)
    
    confirmBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.2, 0.5, 0.2, 1)
    end)
    
    -- Cancel button
    local cancelBtn = CreateFrame("Button", nil, popup, "BackdropTemplate")
    cancelBtn:SetSize(60, 25)
    cancelBtn:SetPoint("TOPRIGHT", -5, -5)
    cancelBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    cancelBtn:SetBackdropColor(0.5, 0.2, 0.2, 1)
    cancelBtn:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    
    local cancelText = cancelBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cancelText:SetPoint("CENTER")
    cancelText:SetText("Cancel")
    
    cancelBtn:SetScript("OnClick", function()
        popup:Hide()
    end)
    
    popup:Hide()
    self.betPopup = popup
end

function UI:UpdateBetPopup()
    if not self.betPopup then return end
    
    local popup = self.betPopup
    local ante = BJ.GameState.ante
    local maxMult = BJ.GameState.maxMultiplier or 1
    local total = ante * popup.currentMultiplier
    
    popup.betDisplay:SetText(total .. "g")
    
    -- Clear old buttons
    for _, btn in pairs(popup.multiplierButtons) do
        btn:Hide()
        btn:SetParent(nil)
    end
    popup.multiplierButtons = {}
    
    -- Create buttons for allowed multipliers
    local allowedMults = { 1 }
    if maxMult >= 2 then table.insert(allowedMults, 2) end
    if maxMult >= 5 then table.insert(allowedMults, 5) end
    if maxMult >= 10 then table.insert(allowedMults, 10) end
    
    local btnWidth = 45
    local totalBtnWidth = #allowedMults * btnWidth + (#allowedMults - 1) * 5
    local startX = -totalBtnWidth / 2 + btnWidth / 2
    
    for i, mult in ipairs(allowedMults) do
        local btn = CreateFrame("Button", nil, popup.btnContainer, "BackdropTemplate")
        btn:SetSize(btnWidth, 30)
        btn:SetPoint("CENTER", popup.btnContainer, "CENTER", startX + (i - 1) * (btnWidth + 5), 0)
        btn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        
        local text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        text:SetPoint("CENTER")
        text:SetText(mult .. "x")
        btn.text = text
        btn.multiplier = mult
        
        btn:SetScript("OnClick", function(self)
            popup.currentMultiplier = self.multiplier
            UI:UpdateBetPopup()
        end)
        
        btn:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(1, 0.84, 0, 1)
        end)
        
        btn:SetScript("OnLeave", function(self)
            if popup.currentMultiplier ~= self.multiplier then
                self:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
            end
        end)
        
        -- Highlight selected
        if mult == popup.currentMultiplier then
            btn:SetBackdropColor(0.3, 0.5, 0.3, 1)
            btn:SetBackdropBorderColor(1, 0.84, 0, 1)
        else
            btn:SetBackdropColor(0.2, 0.2, 0.2, 1)
            btn:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
        end
        
        popup.multiplierButtons[mult] = btn
    end
end

function UI:ShowBetPopup()
    if not self.betPopup then
        self:CreateBetSelector()
    end
    
    -- Reset to 1x
    self.betPopup.currentMultiplier = 1
    self:UpdateBetPopup()
    self.betPopup:Show()
end

-- Override ante click to show popup or bet directly
function UI:OnAnteClick()
    local maxMult = BJ.GameState.maxMultiplier or 1
    
    if maxMult == 1 then
        -- No multiples allowed, just bet the ante directly
        BJ.Multiplayer:PlaceAnte(BJ.GameState.ante)
    else
        -- Show bet selector
        self:ShowBetPopup()
    end
end
