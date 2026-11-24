--[[
    Chairface's Casino - UI/Buttons.lua
    Button creation and bet selector popup
]]

local BJ = ChairfacesCasino
BJ.UI = BJ.UI or {}
local UI = BJ.UI

UI.Buttons = {}
local Buttons = UI.Buttons

-- Create a styled game button. Delegates to the shared theme (UI/Theme.lua):
-- a "go" (green) action button that turns gold via SetButtonHighlight when
-- it's the player's move, and grey when disabled.
function Buttons:CreateGameButton(parent, name, text, width)
    return BJ.Theme:Button(parent, text, width or 70, 35, "go", "BlackjackBtn" .. name)
end

-- Set button highlight state (gold for action needed)
function Buttons:SetButtonHighlight(btn, highlighted)
    BJ.Theme:SetButtonHighlight(btn, highlighted)
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
    
    local title = popup:CreateFontString(nil, "OVERLAY", "CCFontLarge")
    title:SetPoint("TOP", 0, -10)
    title:SetText("Place Your Bet")
    title:SetTextColor(1, 0.84, 0, 1)
    
    -- Bet amount display
    local betDisplay = popup:CreateFontString(nil, "OVERLAY", "CCFontLarge")
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
    local confirmBtn = BJ.Theme:Button(popup, "", 80, 30, "go", nil)
    confirmBtn:SetPoint("BOTTOM", 0, 10)
    
    local confirmText = confirmBtn.text
    confirmText:SetText("BET")
    
    confirmBtn:SetScript("OnClick", function()
        local amount = BJ.GameState.ante * popup.currentMultiplier
        BJ.Multiplayer:PlaceAnte(amount)
        popup:Hide()
    end)
    
    confirmBtn:SetScript("OnEnter", function(self)

    end)
    
    confirmBtn:SetScript("OnLeave", function(self)
        BJ.Theme:StyleButton(self)

    end)
    
    -- Cancel button
    local cancelBtn = BJ.Theme:Button(popup, "", 60, 25, "danger", nil)
    cancelBtn:SetPoint("TOPRIGHT", -5, -5)
    
    local cancelText = cancelBtn.text
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
        
        local text = btn:CreateFontString(nil, "OVERLAY", "CCFontNormal")
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
