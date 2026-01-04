--[[
    Chairface's Casino - UI/HiLoFrame.lua
    High-Lo game window with Trixie tall beside it
]]

local BJ = ChairfacesCasino
local UI = BJ.UI

UI.HiLo = {}
local HiLo = UI.HiLo

-- Frame dimensions
local FRAME_WIDTH = 280
local FRAME_WIDTH_WIDE = 520  -- Width when using 2 columns (20+ players)
local FRAME_MIN_HEIGHT = 310  -- Reduced since host/join buttons share position
local PLAYER_ROW_HEIGHT = 18  -- Reduced from 28 to fit more players
local DUAL_COLUMN_THRESHOLD = 20  -- Switch to 2 columns at this many players

-- Trixie fixed size (same as blackjack dealer images)
local TRIXIE_WIDTH = 274
local TRIXIE_HEIGHT = 350

-- Initialize
function HiLo:Initialize()
    if self.frame then return end
    self:CreateFrame()
    self:RegisterRollEvents()
end

-- Create the main frame
function HiLo:CreateFrame()
    -- Container for game frame + Trixie (Trixie on right)
    local container = CreateFrame("Frame", "ChairfacesCasinoHiLo", UIParent)
    container:SetPoint("CENTER")
    container:SetSize(FRAME_WIDTH + TRIXIE_WIDTH, FRAME_MIN_HEIGHT)
    container:SetMovable(true)
    container:EnableMouse(true)
    container:RegisterForDrag("LeftButton")
    container:SetScript("OnDragStart", container.StartMoving)
    container:SetScript("OnDragStop", container.StopMovingOrSizing)
    container:SetClampedToScreen(true)
    container:SetFrameStrata("HIGH")
    container:Hide()
    
    self.container = container
    
    -- Main game frame on the left
    local frame = CreateFrame("Frame", nil, container, "BackdropTemplate")
    frame:SetSize(FRAME_WIDTH, FRAME_MIN_HEIGHT)
    frame:SetPoint("LEFT", container, "LEFT", 0, 0)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",  -- Dark background for title area
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    frame:SetBackdropColor(0.08, 0.08, 0.12, 0.97)  -- Dark for title/status area
    frame:SetBackdropBorderColor(0.6, 0.5, 0.2, 1)
    
    -- Create felt background texture that starts below title/status area
    -- Title is at TOP -12, status is below that, so felt starts around -55 from top
    local FELT_TOP_OFFSET = 55  -- Start felt below title and status text
    local bgTexture = frame:CreateTexture(nil, "BACKGROUND", nil, 1)  -- Higher sublayer to be above backdrop
    bgTexture:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\tablefelt_bg")
    bgTexture:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -FELT_TOP_OFFSET)
    bgTexture:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
    
    local function UpdateFeltTexCoords()
        local texW, texH = 1280, 720
        local frameW = frame:GetWidth() - 4  -- Account for insets
        local frameH = frame:GetHeight() - FELT_TOP_OFFSET - 4
        local uSize = math.min(1, frameW / texW)
        local vSize = math.min(1, frameH / texH)
        local uOffset = (1 - uSize) / 2
        local vOffset = (1 - vSize) / 2
        bgTexture:SetTexCoord(uOffset, uOffset + uSize, vOffset, vOffset + vSize)
    end
    UpdateFeltTexCoords()
    frame.feltBg = bgTexture
    frame.UpdateFeltTexCoords = UpdateFeltTexCoords
    
    self.frame = frame
    
    -- Trixie on the right - fixed size (274x350), vertically centered
    local TRIXIE_WIDTH = 274
    local TRIXIE_HEIGHT = 350
    
    local trixieBtn = CreateFrame("Button", nil, container)
    trixieBtn:SetSize(TRIXIE_WIDTH, TRIXIE_HEIGHT)
    trixieBtn:SetPoint("LEFT", frame, "RIGHT", 0, 0)  -- Flush against game frame, will be repositioned in ResizeFrame
    
    -- Random wait image
    local hiloWaitIdx = math.random(1, 31)
    local trixieTexture = trixieBtn:CreateTexture(nil, "ARTWORK")
    trixieTexture:SetAllPoints()
    trixieTexture:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\dealer\\trix_wait" .. hiloWaitIdx)
    self.trixieTexture = trixieTexture
    self.trixieFrame = trixieBtn
    
    -- Easter egg click handler
    trixieBtn:SetScript("OnClick", function()
        if UI.Lobby and UI.Lobby.TryPlayPoke then
            UI.Lobby:TryPlayPoke()
        end
    end)
    
    -- Randomize pose each time HiLo is shown
    frame:HookScript("OnShow", function()
        local newIdx = math.random(1, 31)
        HiLo.trixieTexture:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\dealer\\trix_wait" .. newIdx)
    end)
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() 
        HiLo:Hide()
    end)
    
    -- Refresh button (next to close)
    local refreshBtn = CreateFrame("Button", nil, frame)
    refreshBtn:SetSize(18, 18)
    refreshBtn:SetPoint("TOPRIGHT", -28, -6)
    
    local refreshTex = refreshBtn:CreateTexture(nil, "ARTWORK")
    refreshTex:SetAllPoints()
    refreshTex:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\refresh_icon")
    refreshBtn.texture = refreshTex
    
    local refreshHighlight = refreshBtn:CreateTexture(nil, "HIGHLIGHT")
    refreshHighlight:SetAllPoints()
    refreshHighlight:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\refresh_icon")
    refreshHighlight:SetAlpha(0.5)
    refreshHighlight:SetBlendMode("ADD")
    
    refreshBtn:SetScript("OnClick", function()
        HiLo:Hide()
        C_Timer.After(0.05, function()
            HiLo:Show()
        end)
    end)
    refreshBtn:SetScript("OnEnter", function(self) 
        self.texture:SetVertexColor(0.7, 0.9, 1, 1)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Refresh Window")
        GameTooltip:Show()
    end)
    refreshBtn:SetScript("OnLeave", function(self) 
        self.texture:SetVertexColor(1, 1, 1, 1)
        GameTooltip:Hide()
    end)
    
    -- Back button to return to casino lobby (upper left corner)
    local backBtn = CreateFrame("Button", nil, frame, "BackdropTemplate")
    backBtn:SetSize(50, 18)
    backBtn:SetPoint("TOPLEFT", 8, -8)
    backBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    backBtn:SetBackdropColor(0.15, 0.35, 0.15, 1)
    backBtn:SetBackdropBorderColor(0.3, 0.6, 0.3, 1)
    
    local backText = backBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    backText:SetPoint("CENTER")
    backText:SetText("|cffffffffBack|r")
    
    backBtn:SetScript("OnClick", function()
        HiLo:Hide()
        if UI.Lobby then
            UI.Lobby:Show()
        end
    end)
    backBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.2, 0.45, 0.2, 1) end)
    backBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.15, 0.35, 0.15, 1) end)
    
    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY")
    title:SetFont("Fonts\\MORPHEUS.TTF", 22, "OUTLINE")
    title:SetPoint("TOP", 0, -12)
    title:SetText("|cffffd700High-Lo|r")
    self.title = title
    
    -- Status text (below title)
    local status = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    status:SetPoint("TOP", title, "BOTTOM", 0, -5)
    status:SetText("")
    self.statusText = status
    
    -- Settlement background frame (shown during settlement)
    local settlementBg = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    settlementBg:SetPoint("TOP", status, "BOTTOM", 0, -3)
    settlementBg:SetPoint("LEFT", 15, 0)
    settlementBg:SetPoint("RIGHT", -15, 0)
    settlementBg:SetHeight(80)  -- Will auto-resize
    settlementBg:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    settlementBg:SetBackdropColor(0, 0, 0, 1)  -- 100% opaque black
    settlementBg:SetBackdropBorderColor(0.5, 0.5, 0.3, 1)  -- Subtle gold border
    settlementBg:Hide()
    self.settlementBg = settlementBg
    
    -- Settlement text (shown during settlement) - parented to settlementBg so it's above
    local settlement = settlementBg:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    settlement:SetPoint("TOP", settlementBg, "TOP", 0, -8)
    settlement:SetWidth(FRAME_WIDTH - 40)
    settlement:SetSpacing(4)  -- 4pt gap between lines
    settlement:SetText("")
    self.settlementText = settlement
    
    -- Player list container
    local listContainer = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    listContainer:SetPoint("TOP", settlementBg, "BOTTOM", 0, -5)
    listContainer:SetPoint("LEFT", 10, 0)
    listContainer:SetPoint("RIGHT", -10, 0)
    listContainer:SetHeight(150)  -- Will be resized
    listContainer:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    listContainer:SetBackdropColor(0.05, 0.05, 0.08, 0.9)
    listContainer:SetBackdropBorderColor(0.3, 0.3, 0.4, 1)
    self.listContainer = listContainer
    
    -- Player rows (created dynamically)
    self.playerRows = {}
    
    -- Button container at bottom (smaller now that host/join share position)
    local btnContainer = CreateFrame("Frame", nil, frame)
    btnContainer:SetSize(FRAME_WIDTH - 20, 60)
    btnContainer:SetPoint("BOTTOM", 0, 10)
    self.btnContainer = btnContainer
    
    -- Create centered action button (Host/Join) - above everything
    local actionBtn = CreateFrame("Button", "HiLoActionButton", frame, "BackdropTemplate")
    actionBtn:SetSize(180, 54)  -- Triple normal size
    actionBtn:SetPoint("CENTER", frame, "CENTER", 0, 0)
    actionBtn:SetFrameLevel(frame:GetFrameLevel() + 100)  -- Above everything
    actionBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 3,
    })
    actionBtn:SetBackdropColor(0.15, 0.35, 0.15, 1)
    actionBtn:SetBackdropBorderColor(0.3, 0.7, 0.3, 1)
    
    local actionText = actionBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    actionText:SetPoint("CENTER")
    actionText:SetFont("Fonts\\FRIZQT__.TTF", 24, "OUTLINE")  -- Triple font size
    actionText:SetText("HOST")
    actionBtn.text = actionText
    
    actionBtn:SetScript("OnEnter", function(self)
        if self:IsEnabled() then
            self:SetBackdropColor(0.2, 0.5, 0.2, 1)
            self:SetBackdropBorderColor(0.4, 1, 0.4, 1)
        end
    end)
    actionBtn:SetScript("OnLeave", function(self)
        if self:IsEnabled() then
            self:SetBackdropColor(0.15, 0.35, 0.15, 1)
            self:SetBackdropBorderColor(0.3, 0.7, 0.3, 1)
        end
    end)
    actionBtn:SetScript("OnClick", function() HiLo:OnActionButtonClick() end)
    self.actionButton = actionBtn
    
    -- Start button (host only)
    local startBtn = CreateFrame("Button", nil, btnContainer, "BackdropTemplate")
    startBtn:SetSize(120, 30)
    startBtn:SetPoint("TOP", 0, 0)  -- Same position as host/join
    startBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    startBtn:SetBackdropColor(0.5, 0.4, 0.1, 1)
    startBtn:SetBackdropBorderColor(0.8, 0.6, 0.2, 1)
    local startText = startBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    startText:SetPoint("CENTER")
    startText:SetText("|cffffd700START|r")
    startBtn:SetScript("OnClick", function() HiLo:OnStartClick() end)
    startBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.6, 0.5, 0.2, 1) end)
    startBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.5, 0.4, 0.1, 1) end)
    startBtn:Hide()
    self.startBtn = startBtn
    
    -- Roll button (during rolling phase)
    local rollBtn = CreateFrame("Button", nil, btnContainer, "BackdropTemplate")
    rollBtn:SetSize(200, 35)
    rollBtn:SetPoint("TOP", 0, 0)
    rollBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
    rollBtn:SetBackdropColor(0.4, 0.2, 0.5, 1)
    rollBtn:SetBackdropBorderColor(0.6, 0.3, 0.8, 1)
    local rollText = rollBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    rollText:SetPoint("CENTER")
    rollText:SetText("|cffff88ff/roll 100|r")
    self.rollBtnText = rollText
    rollBtn:SetScript("OnClick", function() HiLo:OnRollClick() end)
    rollBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.5, 0.3, 0.6, 1) end)
    rollBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.4, 0.2, 0.5, 1) end)
    rollBtn:Hide()
    self.rollBtn = rollBtn
    
    -- Reset button (host only, shown during active game)
    local resetBtn = CreateFrame("Button", nil, btnContainer, "BackdropTemplate")
    resetBtn:SetSize(60, 22)
    resetBtn:SetPoint("BOTTOMRIGHT", btnContainer, "BOTTOMRIGHT", 0, 0)
    resetBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    resetBtn:SetBackdropColor(0.5, 0.2, 0.2, 1)
    resetBtn:SetBackdropBorderColor(0.7, 0.3, 0.3, 1)
    local resetText = resetBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    resetText:SetPoint("CENTER")
    resetText:SetText("|cffff8888Reset|r")
    resetBtn:SetScript("OnClick", function() HiLo:OnResetClick() end)
    resetBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.6, 0.3, 0.3, 1) end)
    resetBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.5, 0.2, 0.2, 1) end)
    resetBtn:Hide()
    self.resetBtn = resetBtn
    
    -- LOG button (always visible, next to reset)
    local logBtn = CreateFrame("Button", nil, btnContainer, "BackdropTemplate")
    logBtn:SetSize(45, 22)
    logBtn:SetPoint("RIGHT", resetBtn, "LEFT", -5, 0)
    logBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    logBtn:SetBackdropColor(0.2, 0.2, 0.4, 1)
    logBtn:SetBackdropBorderColor(0.4, 0.4, 0.6, 1)
    local logText = logBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    logText:SetPoint("CENTER")
    logText:SetText("|cff88aaffLOG|r")
    logBtn:SetScript("OnClick", function() HiLo:ToggleLog() end)
    logBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.3, 0.3, 0.5, 1) end)
    logBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.2, 0.2, 0.4, 1) end)
    self.logBtn = logBtn
    
    -- Timer text
    local timerText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    timerText:SetPoint("BOTTOM", btnContainer, "TOP", 0, 5)
    timerText:SetText("")
    self.timerText = timerText
    
    -- Create host settings panel (hidden by default)
    self:CreateHostPanel()
    
    -- Create test mode bar (hidden by default)
    self:CreateTestModeBar()
    
    -- Update timer
    frame:SetScript("OnUpdate", function(self, elapsed)
        HiLo:OnUpdate(elapsed)
    end)
end

-- Create test mode bar for High-Lo
function HiLo:CreateTestModeBar()
    local testBar = CreateFrame("Frame", nil, self.frame, "BackdropTemplate")
    testBar:SetSize(FRAME_WIDTH - 20, 30)  -- Single row now
    -- Position BELOW the main window (like Blackjack/Poker)
    testBar:SetPoint("TOP", self.frame, "BOTTOM", 0, -5)
    testBar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
    testBar:SetBackdropColor(0.15, 0.1, 0.2, 0.95)
    testBar:SetBackdropBorderColor(1, 0.4, 1, 1)
    
    -- Game control buttons (including trix buttons)
    local btnConfigs = {
        { text = "+TEST", cmd = "add", width = 50 },
        { text = "-TEST", cmd = "remove", width = 50 },
        { text = "ROLL", cmd = "roll", width = 45 },
        { text = "CLEAR", cmd = "clear", width = 50 },
        { text = "TRIX", cmd = "trixtoggle", width = 45, green = true },
        { text = "<Trix", cmd = "trixprev", width = 40, pink = true },
        { text = "Trix>", cmd = "trixnext", width = 40, pink = true },
    }
    
    -- Calculate total width for centering
    local totalWidth = 0
    for _, cfg in ipairs(btnConfigs) do
        totalWidth = totalWidth + cfg.width + 3
    end
    local startX = -totalWidth / 2
    
    for _, cfg in ipairs(btnConfigs) do
        local btn = CreateFrame("Button", nil, testBar, "BackdropTemplate")
        btn:SetSize(cfg.width, 22)
        btn:SetPoint("LEFT", testBar, "CENTER", startX, 0)
        btn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        if cfg.pink then
            btn:SetBackdropColor(0.4, 0.2, 0.3, 1)
            btn:SetBackdropBorderColor(0.8, 0.4, 0.6, 1)
        elseif cfg.green then
            -- Green for visibility toggle
            local isOn = self:ShouldShowTrixie()
            if isOn then
                btn:SetBackdropColor(0.2, 0.4, 0.2, 1)
                btn:SetBackdropBorderColor(0.4, 0.8, 0.4, 1)
            else
                btn:SetBackdropColor(0.3, 0.2, 0.2, 1)
                btn:SetBackdropBorderColor(0.6, 0.3, 0.3, 1)
            end
            testBar.trixToggleBtn = btn
        else
            btn:SetBackdropColor(0.3, 0.2, 0.4, 1)
            btn:SetBackdropBorderColor(0.6, 0.4, 0.8, 1)
        end
        
        local btnText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        btnText:SetPoint("CENTER")
        btnText:SetText("|cffffffff" .. cfg.text .. "|r")
        btn.text = btnText
        
        local command = cfg.cmd
        local isPink = cfg.pink
        local isGreen = cfg.green
        btn:SetScript("OnClick", function()
            if BJ.TestMode then
                if command == "add" then 
                    BJ.TestMode:AddHiLoFakePlayer()
                elseif command == "remove" then 
                    BJ.TestMode:RemoveHiLoFakePlayer()
                elseif command == "roll" then 
                    -- Roll for fake players or tiebreaker
                    local HL = BJ.HiLoState
                    if HL.phase == HL.PHASE.ROLLING then
                        BJ.TestMode:SimulateHiLoRolls()
                    elseif HL.phase == HL.PHASE.TIEBREAKER then
                        BJ.TestMode:SimulateHiLoTiebreakerRolls()
                    end
                elseif command == "clear" then 
                    BJ.TestMode:ClearHiLoFakePlayers()
                elseif command == "trixtoggle" then
                    local newState = not HiLo:ShouldShowTrixie()
                    HiLo:SetTrixieVisibility(newState)
                    -- Update button color
                    if newState then
                        btn:SetBackdropColor(0.2, 0.4, 0.2, 1)
                        btn:SetBackdropBorderColor(0.4, 0.8, 0.4, 1)
                    else
                        btn:SetBackdropColor(0.3, 0.2, 0.2, 1)
                        btn:SetBackdropBorderColor(0.6, 0.3, 0.3, 1)
                    end
                elseif command == "trixprev" then
                    BJ.TestMode:PrevTrixieImage()
                elseif command == "trixnext" then
                    BJ.TestMode:NextTrixieImage()
                end
            end
        end)
        if isPink then
            btn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.5, 0.3, 0.4, 1) end)
            btn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.4, 0.2, 0.3, 1) end)
        elseif isGreen then
            btn:SetScript("OnEnter", function(self)
                local isOn = HiLo:ShouldShowTrixie()
                if isOn then
                    self:SetBackdropColor(0.3, 0.5, 0.3, 1)
                else
                    self:SetBackdropColor(0.4, 0.3, 0.3, 1)
                end
            end)
            btn:SetScript("OnLeave", function(self)
                local isOn = HiLo:ShouldShowTrixie()
                if isOn then
                    self:SetBackdropColor(0.2, 0.4, 0.2, 1)
                else
                    self:SetBackdropColor(0.3, 0.2, 0.2, 1)
                end
            end)
        else
            btn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.4, 0.3, 0.5, 1) end)
            btn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.3, 0.2, 0.4, 1) end)
        end
        startX = startX + cfg.width + 3
    end
    
    testBar:Hide()
    self.testModeBar = testBar
end

-- Create host settings panel
function HiLo:CreateHostPanel()
    local panel = CreateFrame("Frame", nil, self.frame, "BackdropTemplate")
    panel:SetSize(FRAME_WIDTH - 20, 170)  -- Taller for proper spacing
    panel:SetPoint("CENTER", 0, 20)
    panel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    panel:SetBackdropColor(0.1, 0.1, 0.15, 0.98)
    panel:SetBackdropBorderColor(0.5, 0.4, 0.2, 1)
    panel:SetFrameLevel(self.frame:GetFrameLevel() + 10)
    panel:Hide()
    
    -- Title
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -10)
    title:SetText("|cffffd700Host Settings|r")
    
    -- Max Roll label
    local maxLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    maxLabel:SetPoint("TOPLEFT", 15, -35)
    maxLabel:SetText("Max Roll:")
    
    -- Max Roll input
    local maxInput = CreateFrame("EditBox", nil, panel, "BackdropTemplate")
    maxInput:SetSize(80, 24)
    maxInput:SetPoint("LEFT", maxLabel, "RIGHT", 10, 0)
    maxInput:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    maxInput:SetBackdropColor(0.15, 0.15, 0.2, 1)
    maxInput:SetBackdropBorderColor(0.4, 0.4, 0.5, 1)
    maxInput:SetFontObject(GameFontNormal)
    maxInput:SetTextColor(1, 1, 1)
    maxInput:SetJustifyH("CENTER")
    maxInput:SetAutoFocus(false)
    maxInput:SetNumeric(true)
    maxInput:SetMaxLetters(6)
    maxInput:SetText("100")
    maxInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    maxInput:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    self.maxRollInput = maxInput
    
    -- Join Timer label + checkbox
    local timerLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    timerLabel:SetPoint("TOPLEFT", 15, -65)
    timerLabel:SetText("Join Timer:")
    
    local timerToggle = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    timerToggle:SetSize(22, 22)
    timerToggle:SetPoint("LEFT", timerLabel, "RIGHT", 5, 0)
    timerToggle:SetChecked(false)
    self.timerToggle = timerToggle
    
    local timerStatus = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    timerStatus:SetPoint("LEFT", timerToggle, "RIGHT", 2, 0)
    timerStatus:SetTextColor(0.7, 0.7, 0.7, 1)
    timerStatus:SetText("Off")
    self.timerStatus = timerStatus
    
    -- Timer buttons row (same options as blackjack)
    local timerButtons = {}
    local timerOptions = { 10, 15, 20, 30, 45, 60 }
    local btnX = 15
    
    for i, secs in ipairs(timerOptions) do
        local btn = CreateFrame("Button", nil, panel, "BackdropTemplate")
        btn:SetSize(35, 22)
        btn:SetPoint("TOPLEFT", btnX, -90)
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
            HiLo.selectedTimer = self.value
            timerToggle:SetChecked(true)
            timerStatus:SetText(self.value .. "s")
            HiLo:UpdateTimerButtons()
        end)
        
        btn:SetScript("OnEnter", function(self)
            if HiLo.selectedTimer ~= self.value then
                self:SetBackdropBorderColor(1, 0.84, 0, 1)
            end
        end)
        
        btn:SetScript("OnLeave", function(self)
            if HiLo.selectedTimer ~= self.value then
                self:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
            end
        end)
        
        timerButtons[secs] = btn
        btnX = btnX + 39
    end
    self.timerButtons = timerButtons
    self.selectedTimer = 0
    
    timerToggle:SetScript("OnClick", function(self)
        if self:GetChecked() then
            if HiLo.selectedTimer == 0 then
                HiLo.selectedTimer = 15  -- Default to 15s
            end
            timerStatus:SetText(HiLo.selectedTimer .. "s")
        else
            timerStatus:SetText("Off")
        end
        HiLo:UpdateTimerButtons()
    end)
    
    -- Confirm button
    local confirmBtn = CreateFrame("Button", nil, panel, "BackdropTemplate")
    confirmBtn:SetSize(100, 28)
    confirmBtn:SetPoint("BOTTOM", 0, 10)
    confirmBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    confirmBtn:SetBackdropColor(0.2, 0.5, 0.2, 1)
    confirmBtn:SetBackdropBorderColor(0.3, 0.8, 0.3, 1)
    local confirmText = confirmBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    confirmText:SetPoint("CENTER")
    confirmText:SetText("|cff00ff00Open Table|r")
    confirmBtn:SetScript("OnClick", function() HiLo:OnConfirmHost() end)
    confirmBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.3, 0.6, 0.3, 1) end)
    confirmBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.2, 0.5, 0.2, 1) end)
    
    -- Cancel button
    local cancelBtn = CreateFrame("Button", nil, panel, "BackdropTemplate")
    cancelBtn:SetSize(60, 24)
    cancelBtn:SetPoint("TOPRIGHT", -5, -5)
    cancelBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    cancelBtn:SetBackdropColor(0.4, 0.2, 0.2, 1)
    cancelBtn:SetBackdropBorderColor(0.6, 0.3, 0.3, 1)
    local cancelText = cancelBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cancelText:SetPoint("CENTER")
    cancelText:SetText("|cffff8888Cancel|r")
    cancelBtn:SetScript("OnClick", function() panel:Hide() end)
    
    self.hostPanel = panel
end

-- Update timer button highlighting
function HiLo:UpdateTimerButtons()
    if not self.timerButtons then return end
    local enabled = self.timerToggle and self.timerToggle:GetChecked()
    
    for secs, btn in pairs(self.timerButtons) do
        if enabled and self.selectedTimer == secs then
            btn:SetBackdropColor(0.2, 0.4, 0.2, 1)
            btn:SetBackdropBorderColor(0.3, 0.8, 0.3, 1)
        else
            btn:SetBackdropColor(0.15, 0.15, 0.15, 1)
            btn:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
        end
    end
end

-- Update Trixie visibility based on setting
function HiLo:UpdateTrixieVisibility()
    if not self.trixieFrame then return end
    
    -- Use High-Lo specific setting
    local showTrixie = BJ.db and BJ.db.settings and BJ.db.settings.hiloShowTrixie ~= false
    
    if showTrixie then
        self.trixieFrame:Show()
    else
        self.trixieFrame:Hide()
    end
    
    self:ResizeFrame()
end

-- Check if Trixie should be shown (for test bar toggle)
function HiLo:ShouldShowTrixie()
    if BJ.db and BJ.db.settings then
        return BJ.db.settings.hiloShowTrixie ~= false
    end
    return true  -- Default to showing
end

-- Set Trixie visibility (for test bar toggle)
function HiLo:SetTrixieVisibility(show)
    if not BJ.db then BJ.db = { settings = {} } end
    if not BJ.db.settings then BJ.db.settings = {} end
    BJ.db.settings.hiloShowTrixie = show
    
    self:UpdateTrixieVisibility()
end

--[[
    TRIXIE STATE MANAGEMENT
    Trixie reacts to local player's game events
]]

-- Track last states to avoid repeats
HiLo.lastWaitState = nil
HiLo.lastWinState = nil
HiLo.lastLoseState = nil

-- Set Trixie to a random wait state
function HiLo:SetTrixieWait()
    if not self.trixieTexture then return end
    local idx
    repeat
        idx = math.random(1, 31)
    until ("wait" .. idx) ~= self.lastWaitState
    self.lastWaitState = "wait" .. idx
    self.trixieTexture:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\dealer\\trix_wait" .. idx)
    self.currentTrixieState = "wait"
end

-- Set Trixie to a random win/cheer state
function HiLo:SetTrixieCheer()
    if not self.trixieTexture then return end
    local idx
    repeat
        idx = math.random(1, 9)
    until ("win" .. idx) ~= self.lastWinState
    self.lastWinState = "win" .. idx
    self.trixieTexture:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\dealer\\trix_win" .. idx)
    self.currentTrixieState = "cheer"
end

-- Set Trixie to a random lose/sad state
function HiLo:SetTrixieLose()
    if not self.trixieTexture then return end
    local idx
    repeat
        idx = math.random(1, 12)
    until ("lose" .. idx) ~= self.lastLoseState
    self.lastLoseState = "lose" .. idx
    self.trixieTexture:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\dealer\\trix_lose" .. idx)
    self.currentTrixieState = "lose"
end

-- Set Trixie to a random love state (for big wins)
function HiLo:SetTrixieLove()
    if not self.trixieTexture then return end
    local idx = math.random(1, 10)
    self.trixieTexture:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\dealer\\trix_love" .. idx)
    self.currentTrixieState = "love"
end

-- Update Trixie based on game phase and local player status
function HiLo:UpdateTrixieForGameState()
    if not self.trixieTexture then return end
    if not self:ShouldShowTrixie() then return end
    
    local HL = BJ.HiLoState
    local UI = BJ.UI
    local myName = UnitName("player")
    local isInGame = HL.players[myName] ~= nil
    
    if HL.phase == HL.PHASE.IDLE then
        -- No game - waiting
        self:SetTrixieWait()
        self.settlementAudioPlayed = nil  -- Reset flag
        
    elseif HL.phase == HL.PHASE.LOBBY then
        -- Waiting for game to start
        self:SetTrixieWait()
        self.settlementAudioPlayed = nil  -- Reset flag
        
    elseif HL.phase == HL.PHASE.ROLLING then
        -- Rolling phase - waiting
        self:SetTrixieWait()
        
    elseif HL.phase == HL.PHASE.TIEBREAKER then
        -- Tiebreaker - waiting
        self:SetTrixieWait()
        
    elseif HL.phase == HL.PHASE.SETTLEMENT then
        -- Check if local player won or lost
        if HL.highPlayer == myName then
            -- Local player won!
            local winAmount = HL.winAmount or 0
            if winAmount >= 50 then
                self:SetTrixieLove()  -- Big win!
            else
                self:SetTrixieCheer()  -- Normal win
            end
            -- Play win audio once
            if not self.settlementAudioPlayed then
                self.settlementAudioPlayed = true
                if UI and UI.Lobby then
                    UI.Lobby:PlayWinSound()
                    UI.Lobby:PlayTrixieWoohooVoice()
                end
            end
        elseif HL.lowPlayer == myName then
            -- Local player lost
            self:SetTrixieLose()
            -- Play bad audio once
            if not self.settlementAudioPlayed then
                self.settlementAudioPlayed = true
                if UI and UI.Lobby then
                    UI.Lobby:PlayTrixieBadVoice()
                end
            end
        else
            -- Local player wasn't in the final (spectating or was eliminated in tie)
            self:SetTrixieWait()
        end
    end
end

-- Register for roll events
function HiLo:RegisterRollEvents()
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("CHAT_MSG_SYSTEM")
    eventFrame:SetScript("OnEvent", function(self, event, msg)
        HiLo:OnChatMessage(msg)
    end)
    self.eventFrame = eventFrame
end

-- Parse roll messages
function HiLo:OnChatMessage(msg)
    local HL = BJ.HiLoState
    local HLM = BJ.HiLoMultiplayer
    
    -- Parse roll message: "PlayerName rolls X (1-Y)"
    local playerName, roll, maxRoll = msg:match("(%S+) rolls (%d+) %(1%-(%d+)%)")
    
    if not playerName or not roll or not maxRoll then return end
    
    roll = tonumber(roll)
    maxRoll = tonumber(maxRoll)
    
    -- Handle main rolling phase
    if HL.phase == HL.PHASE.ROLLING then
        -- Only accept rolls with the correct max roll value
        if maxRoll ~= HL.maxRoll then
            return  -- Ignore rolls with wrong max
        end
        
        -- Check if player is in our game
        if HL.players[playerName] then
            local prevPhase = HL.phase
            
            -- Before recording, check if local player had the high roll and might get overtaken
            local myName = UnitName("player")
            local myPlayer = HL.players[myName]
            local myRoll = myPlayer and myPlayer.roll
            local wasLeading = false
            local myRollPercent = 0
            
            if myRoll and myRoll > 0 then
                myRollPercent = myRoll / (HL.maxRoll or 100)
                -- Check if we were leading before this roll
                wasLeading = true
                for name, p in pairs(HL.players) do
                    if name ~= myName and p.roll and p.roll >= myRoll then
                        wasLeading = false
                        break
                    end
                end
            end
            
            local success = HL:RecordRoll(playerName, roll)
            if success then
                -- Play dice sound
                PlaySoundFile("Interface\\AddOns\\Chairfaces Casino\\Sounds\\dice.mp3", "SFX")
                
                -- If LOCAL player just rolled, give immediate Trixie feedback
                if playerName == myName then
                    -- Quick reaction based on roll value
                    local maxRollVal = HL.maxRoll or 100
                    local rollPercent = roll / maxRollVal
                    if rollPercent >= 0.8 then
                        self:SetTrixieCheer()  -- Great roll!
                    elseif rollPercent <= 0.2 then
                        self:SetTrixieLose()  -- Bad roll...
                    else
                        self:SetTrixieWait()  -- Neutral
                    end
                elseif wasLeading and myRollPercent >= 0.90 and roll > myRoll then
                    -- Local player had a great roll (90%+) and just got overtaken!
                    self:SetTrixieLose()
                    if UI.Lobby then
                        UI.Lobby:PlayTrixieBadVoice()
                    end
                end
                
                -- Host broadcasts the roll to all clients
                if HLM and HLM.isHost then
                    HLM:BroadcastPlayerRolled(playerName, roll)
                    
                    -- Check for phase change after roll
                    if HL.phase == HL.PHASE.ROLLING and prevPhase == HL.PHASE.ROLLING then
                        -- Check if this was a 2-player tie reroll
                        -- (phase stayed ROLLING means reroll happened)
                        -- We need to check if all players rolled and got reset
                        local allUnrolled = true
                        for _, name in ipairs(HL.playerOrder) do
                            local p = HL.players[name]
                            if p and p.rolled then
                                allUnrolled = false
                                break
                            end
                        end
                        if allUnrolled and #HL.playerOrder == 2 then
                            -- 2-player tie reroll happened
                            HLM:BroadcastReroll(roll)
                        end
                    elseif HL.phase == HL.PHASE.TIEBREAKER then
                        local playersStr = table.concat(HL.tiebreakerPlayers, ",")
                        HLM:BroadcastTiebreaker(HL.tiebreakerType, playersStr)
                    elseif HL.phase == HL.PHASE.SETTLEMENT then
                        HLM:BroadcastSettlement(HL.highPlayer, HL.highRoll, HL.lowPlayer, HL.lowRoll, HL.winAmount)
                    end
                end
                
                self:UpdatePlayerList()
                self:UpdateDisplay()
                
                -- Play dice sound
                PlaySoundFile("Interface\\AddOns\\Chairfaces Casino\\Sounds\\dice.mp3", "SFX")
            end
        end
        
    -- Handle tiebreaker phase
    elseif HL.phase == HL.PHASE.TIEBREAKER then
        -- Tiebreaker is always /roll 100
        if maxRoll ~= 100 then
            return  -- Ignore non-100 rolls during tiebreaker
        end
        
        -- Check if player is in the tiebreaker
        local inTiebreaker = false
        for _, name in ipairs(HL.tiebreakerPlayers or {}) do
            if name == playerName then
                inTiebreaker = true
                break
            end
        end
        
        if inTiebreaker then
            local prevPhase = HL.phase
            local success = HL:RecordTiebreakerRoll(playerName, roll)
            if success then
                BJ:Debug("Tiebreaker roll recorded. Phase before: " .. prevPhase .. ", after: " .. HL.phase)
                
                -- Host broadcasts the tiebreaker roll
                if HLM and HLM.isHost then
                    HLM:BroadcastTiebreakerRoll(playerName, roll)
                    
                    -- Check if settlement reached after tiebreaker
                    if HL.phase == HL.PHASE.SETTLEMENT then
                        BJ:Debug("Tiebreaker resolved to settlement, broadcasting...")
                        HLM:BroadcastSettlement(HL.highPlayer, HL.highRoll, HL.lowPlayer, HL.lowRoll, HL.winAmount)
                    elseif HL.phase == HL.PHASE.TIEBREAKER then
                        -- Still in tiebreaker (maybe another tie or need low tiebreaker)
                        BJ:Debug("Still in tiebreaker phase, players: " .. table.concat(HL.tiebreakerPlayers or {}, ","))
                        local playersStr = table.concat(HL.tiebreakerPlayers, ",")
                        HLM:BroadcastTiebreaker(HL.tiebreakerType, playersStr)
                    end
                end
                
                self:UpdatePlayerList()
                self:UpdateDisplay()
                
                -- Play dice sound
                PlaySoundFile("Interface\\AddOns\\Chairfaces Casino\\Sounds\\dice.mp3", "SFX")
            end
        end
    end
end

-- Button handlers
function HiLo:OnHostClick()
    local HL = BJ.HiLoState
    if HL.phase ~= HL.PHASE.IDLE then
        BJ:Print("A game is already in progress.")
        return
    end
    
    -- Check if any other game is active
    local Lobby = BJ.UI and BJ.UI.Lobby
    if Lobby and Lobby.IsAnyGameActive then
        local isActive, activeGame = Lobby:IsAnyGameActive()
        if isActive then
            local gameName = Lobby:GetGameName(activeGame)
            BJ:Print("|cffff4444Cannot host - a " .. gameName .. " game is already in progress.|r")
            return
        end
    end
    
    -- Show host settings panel
    self.hostPanel:Show()
end

function HiLo:OnConfirmHost()
    local maxRoll = tonumber(self.maxRollInput:GetText()) or 100
    local joinTimer = 0
    
    -- Get timer from toggle/buttons instead of input
    if self.timerToggle and self.timerToggle:GetChecked() and self.selectedTimer then
        joinTimer = self.selectedTimer
    end
    
    if maxRoll < 2 then
        BJ:Print("Max roll must be at least 2.")
        return
    end
    
    self.hostPanel:Hide()
    
    local HL = BJ.HiLoState
    local myName = UnitName("player")
    
    HL:HostGame(myName, maxRoll, joinTimer)
    
    -- Broadcast to group
    if BJ.HiLoMultiplayer then
        BJ.HiLoMultiplayer:BroadcastTableOpen(maxRoll, joinTimer)
    end
    
    local gameLink = BJ:CreateGameLink("hilo", "High-Lo")
    BJ:Print(gameLink .. " table opened! Max roll: " .. maxRoll)
    
    -- Start join timer if set (handled by HiLoMultiplayer)
    if joinTimer > 0 and BJ.HiLoMultiplayer then
        BJ.HiLoMultiplayer:StartJoinTimer(joinTimer)
    end
    
    self:UpdateDisplay()
end

function HiLo:OnJoinClick()
    local HL = BJ.HiLoState
    if HL.phase ~= HL.PHASE.LOBBY then
        BJ:Print("Cannot join - no game in lobby.")
        return
    end
    
    local myName = UnitName("player")
    local HLM = BJ.HiLoMultiplayer
    
    -- If we're the host or solo, add directly
    if HLM and HLM.isHost then
        local success, err = HL:AddPlayer(myName)
        if success then
            BJ:Print("You joined the High-Lo game!")
            HLM:BroadcastPlayerJoined(myName)
            self:UpdateDisplay()
        else
            BJ:Print("Could not join: " .. (err or "unknown error"))
        end
    elseif HLM and HLM.currentHost then
        -- Send join request to host
        HLM:RequestJoin()
        BJ:Print("Join request sent...")
    else
        -- Solo mode
        local success, err = HL:AddPlayer(myName)
        if success then
            BJ:Print("You joined the High-Lo game!")
            self:UpdateDisplay()
        else
            BJ:Print("Could not join: " .. (err or "unknown error"))
        end
    end
end

function HiLo:OnStartClick()
    local HL = BJ.HiLoState
    local myName = UnitName("player")
    
    if HL.hostName ~= myName then
        BJ:Print("Only the host can start the game.")
        return
    end
    
    local success, err = HL:StartRolling()
    
    if success then
        -- Broadcast to group
        if BJ.HiLoMultiplayer then
            BJ.HiLoMultiplayer:BroadcastStartRolling()
        end
        
        BJ:Print("Rolling phase started! Everyone /roll " .. HL.maxRoll)
        self:UpdateDisplay()
    else
        BJ:Print("Could not start: " .. (err or "unknown error"))
    end
end

-- Handle action button click (context-dependent)
function HiLo:OnActionButtonClick()
    local HL = BJ.HiLoState
    local HLM = BJ.HiLoMultiplayer
    
    if HL.phase == HL.PHASE.IDLE then
        -- No game - this is a HOST action
        self:OnHostClick()
        self.actionButton:Hide()
    elseif HL.phase == HL.PHASE.LOBBY then
        -- Game in lobby - this is a JOIN action
        self:OnJoinClick()
        self.actionButton:Hide()
    end
end

-- Update action button visibility and text
function HiLo:UpdateActionButton()
    if not self.actionButton then return end
    
    local HL = BJ.HiLoState
    local HLM = BJ.HiLoMultiplayer
    local myName = UnitName("player")
    local inTestMode = BJ.TestMode and BJ.TestMode.enabled
    local inPartyOrRaid = IsInGroup() or IsInRaid()
    local canHost = inTestMode or inPartyOrRaid
    
    -- Hide during active game phases
    if HL.phase == HL.PHASE.ROLLING or 
       HL.phase == HL.PHASE.TIEBREAKER or 
       HL.phase == HL.PHASE.SETTLEMENT then
        self.actionButton:Hide()
        return
    end
    
    -- Check if player already joined
    local inGame = HL.players and HL.players[myName] ~= nil
    
    if HL.phase == HL.PHASE.IDLE then
        -- No game - show HOST button
        if canHost then
            self.actionButton.text:SetText("HOST")
            self.actionButton:Show()
            self.actionButton:Enable()
        else
            self.actionButton:Hide()
        end
    elseif HL.phase == HL.PHASE.LOBBY then
        -- Game in lobby - show JOIN button (unless already joined)
        if not inGame then
            self.actionButton.text:SetText("JOIN")
            self.actionButton:Show()
            self.actionButton:Enable()
        else
            self.actionButton:Hide()
        end
    else
        self.actionButton:Hide()
    end
end

function HiLo:OnRollClick()
    local HL = BJ.HiLoState
    local HLM = BJ.HiLoMultiplayer
    
    -- Block actions during recovery
    if HLM and HLM:IsInRecoveryMode() then
        BJ:Print("|cffff8800Game is paused - waiting for host to return.|r")
        return
    end
    
    -- Determine roll value - tiebreaker is always /roll 100
    local rollValue = HL.maxRoll
    if HL.phase == HL.PHASE.TIEBREAKER then
        rollValue = 100
    end
    
    -- Put the roll command in the chat box
    local rollCmd = "/roll " .. rollValue
    
    -- Set the chat edit box text
    if ChatFrame1EditBox then
        ChatFrame1EditBox:Show()
        ChatFrame1EditBox:SetFocus()
        ChatFrame1EditBox:SetText(rollCmd)
    end
end

function HiLo:OnResetClick()
    local HL = BJ.HiLoState
    local HLM = BJ.HiLoMultiplayer
    local myName = UnitName("player")
    
    -- Only host can reset
    if HL.hostName ~= myName then
        BJ:Print("Only the host can reset the game.")
        return
    end
    
    -- Confirm dialog
    StaticPopupDialogs["CASINO_HILO_RESET"] = {
        text = "|cffffd700Reset High-Lo Game?|r\n\nThis will cancel the current game for all players.",
        button1 = "Reset",
        button2 = "Cancel",
        OnAccept = function()
            if HLM then
                HLM:BroadcastReset()
            else
                -- No multiplayer, just reset locally
                HL:Reset()
                HiLo:UpdateDisplay()
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    StaticPopup_Show("CASINO_HILO_RESET")
end

-- Update timer
local updateElapsed = 0
function HiLo:OnUpdate(elapsed)
    updateElapsed = updateElapsed + elapsed
    if updateElapsed < 0.5 then return end
    updateElapsed = 0
    
    local HL = BJ.HiLoState
    local HLM = BJ.HiLoMultiplayer
    
    -- Join countdown - read from HiLoMultiplayer timer (which keeps running even when window closed)
    if HL.phase == HL.PHASE.LOBBY and HLM and HLM.joinStartTime and HLM.joinDuration then
        local elapsed = time() - HLM.joinStartTime
        local remaining = HLM.joinDuration - elapsed
        if remaining > 0 then
            self.timerText:SetText("|cffff8800Join closes in: " .. math.ceil(remaining) .. "s|r")
        else
            self.timerText:SetText("")
        end
    elseif HL.phase == HL.PHASE.LOBBY then
        -- No timer running
        self.timerText:SetText("")
    end
    
    -- Rolling phase timer
    if HL.phase == HL.PHASE.ROLLING then
        local remaining = HL:GetRemainingTime()
        self.timerText:SetText("|cffff8800Time remaining: " .. remaining .. "s|r")
        
        -- Check for timeout (host only)
        if HLM and HLM.isHost then
            if HL:CheckTimeout() then
                self:UpdateDisplay()
            end
        end
    end
end

-- Update display based on game state
function HiLo:UpdateDisplay()
    -- Guard: Don't update if frame isn't initialized yet
    if not self.statusText then return end
    
    local HL = BJ.HiLoState
    local inTestMode = BJ.TestMode and BJ.TestMode.enabled
    local inPartyOrRaid = IsInGroup() or IsInRaid()
    
    -- Update centered action button (Host/Join)
    self:UpdateActionButton()
    
    if HL.phase == HL.PHASE.IDLE then
        -- Show party/raid warning if not in group and not in test mode
        if not inPartyOrRaid and not inTestMode then
            self.statusText:SetText("|cffff8800Join a party or raid|r\n|cffff8800to host a game.|r")
        else
            self.statusText:SetText("|cff888888No game in progress|r")
        end
        self.settlementText:SetText("")
        if self.settlementBg then self.settlementBg:Hide() end
        self.timerText:SetText("")
        self.startBtn:Hide()
        self.rollBtn:Hide()
        self.resetBtn:Hide()
        self:ClearPlayerList()
        
    elseif HL.phase == HL.PHASE.LOBBY then
        local myName = UnitName("player")
        local isHost = HL.hostName == myName
        local inGame = HL.players[myName] ~= nil
        
        self.statusText:SetText("|cff88ccffWaiting for players...|r\nHost: " .. HL.hostName .. " | Max: " .. HL.maxRoll)
        self.settlementText:SetText("")
        if self.settlementBg then self.settlementBg:Hide() end
        
        if isHost and #HL.playerOrder >= 2 then
            self.startBtn:Show()
        else
            self.startBtn:Hide()
        end
        
        self.rollBtn:Hide()
        
        -- Show reset button for host
        if isHost then
            self.resetBtn:Show()
        else
            self.resetBtn:Hide()
        end
        
        self:UpdatePlayerList()
        
    elseif HL.phase == HL.PHASE.ROLLING then
        local myName = UnitName("player")
        local isHost = HL.hostName == myName
        local myPlayer = HL.players[myName]
        local hasRolled = myPlayer and myPlayer.rolled
        
        self.statusText:SetText("|cffff88ffRolling Phase!|r\nEveryone /roll " .. HL.maxRoll)
        self.settlementText:SetText("")
        if self.settlementBg then self.settlementBg:Hide() end
        
        self.startBtn:Hide()
        
        -- Show roll button if player hasn't rolled
        if myPlayer and not hasRolled then
            self.rollBtn:Show()
            self.rollBtnText:SetText("|cffff88ff/roll " .. HL.maxRoll .. "|r")
        else
            self.rollBtn:Hide()
        end
        
        -- Show reset button for host
        if isHost then
            self.resetBtn:Show()
        else
            self.resetBtn:Hide()
        end
        
        self:UpdatePlayerList()
    
    elseif HL.phase == HL.PHASE.TIEBREAKER then
        local myName = UnitName("player")
        local isHost = HL.hostName == myName
        local tiebreakerTypeText = HL.tiebreakerType == "high" and "HIGH" or "LOW"
        
        self.statusText:SetText("|cffffd700TIEBREAKER!|r\nResolving tie for " .. tiebreakerTypeText)
        self.settlementText:SetText("Tied players: " .. table.concat(HL.tiebreakerPlayers or {}, ", ") .. "\nMust /roll 100")
        
        self.startBtn:Hide()
        
        -- Show roll button if player needs to roll tiebreaker
        local needsToRoll = false
        for _, name in ipairs(HL.tiebreakerPlayers or {}) do
            if name == myName and not HL.tiebreakerRolls[name] then
                needsToRoll = true
                break
            end
        end
        
        if needsToRoll then
            self.rollBtn:Show()
            self.rollBtnText:SetText("|cffffd700/roll 100|r")
        else
            self.rollBtn:Hide()
        end
        
        -- Show reset button for host
        if isHost then
            self.resetBtn:Show()
        else
            self.resetBtn:Hide()
        end
        
        self:UpdatePlayerList()
        
    elseif HL.phase == HL.PHASE.SETTLEMENT then
        self.statusText:SetText("|cff00ff00Settlement|r")
        self.settlementText:SetText(HL:GetSettlementText() .. "\n" .. HL:GetSettlementBreakdown())
        self.timerText:SetText("")
        
        -- Show settlement background and size it to text
        if self.settlementBg then
            self.settlementBg:Show()
            local textHeight = self.settlementText:GetStringHeight() or 60
            self.settlementBg:SetHeight(textHeight + 16)
        end
        
        self.startBtn:Hide()
        self.rollBtn:Hide()
        self.resetBtn:Hide()
        
        self:UpdatePlayerList()
        
        -- Show action button after delay to start new game
        C_Timer.After(3, function()
            if HL.phase == HL.PHASE.SETTLEMENT then
                -- Reset game and show action button
                HL:Reset()
                self:UpdateActionButton()
            end
        end)
    end
    
    -- Update Trixie based on game state
    self:UpdateTrixieForGameState()
    
    -- Show/hide test mode bar
    if self.testModeBar then
        local inTestMode = BJ.TestMode and BJ.TestMode.enabled
        if inTestMode then
            self.testModeBar:Show()
        else
            self.testModeBar:Hide()
        end
    end
    
    self:ResizeFrame()
end

-- Update player list
function HiLo:UpdatePlayerList()
    local HL = BJ.HiLoState
    
    -- Guard against uninitialized UI
    if not self.playerRows then
        self.playerRows = {}
    end
    
    local sorted = HL:GetSortedPlayers()
    local playerCount = #sorted
    local useDualColumns = playerCount >= DUAL_COLUMN_THRESHOLD
    
    -- Determine current frame width
    local currentFrameWidth = useDualColumns and FRAME_WIDTH_WIDE or FRAME_WIDTH
    local columnWidth = useDualColumns and ((currentFrameWidth - 40) / 2) or (currentFrameWidth - 30)
    
    -- Create/update rows
    for i, playerData in ipairs(sorted) do
        local row = self.playerRows[i]
        if not row then
            row = self:CreatePlayerRow(i)
            self.playerRows[i] = row
        end
        
        row:Show()
        
        -- Resize row for current column width
        row:SetWidth(columnWidth)
        
        -- Name
        row.nameText:SetText("|cffffd700" .. playerData.name .. "|r")
        
        -- Roll value
        if playerData.rolled then
            row.rollText:SetText("|cff00ff00" .. playerData.roll .. "|r")
            row.highlight:Hide()
        else
            row.rollText:SetText("|cff666666...|r")
            row.highlight:Show()
        end
        
        -- Position row (dual column layout at 20+ players)
        if useDualColumns then
            local rowsPerColumn = math.ceil(playerCount / 2)
            local column = (i <= rowsPerColumn) and 0 or 1
            local rowInColumn = (column == 0) and (i - 1) or (i - rowsPerColumn - 1)
            local xOffset = 5 + column * (columnWidth + 10)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", self.listContainer, "TOPLEFT", xOffset, -5 - rowInColumn * PLAYER_ROW_HEIGHT)
        else
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", self.listContainer, "TOPLEFT", 5, -5 - (i-1) * PLAYER_ROW_HEIGHT)
        end
    end
    
    -- Hide extra rows
    for i = #sorted + 1, #self.playerRows do
        self.playerRows[i]:Hide()
    end
    
    -- Resize list container
    local rowsToDisplay = useDualColumns and math.ceil(playerCount / 2) or playerCount
    local listHeight = math.max(50, rowsToDisplay * PLAYER_ROW_HEIGHT + 10)
    self.listContainer:SetHeight(listHeight)
end

-- Create a player row
function HiLo:CreatePlayerRow(index)
    local row = CreateFrame("Frame", nil, self.listContainer)
    row:SetSize(FRAME_WIDTH - 30, PLAYER_ROW_HEIGHT - 2)
    
    -- Highlight background (for players who haven't rolled)
    local highlight = row:CreateTexture(nil, "BACKGROUND")
    highlight:SetAllPoints()
    highlight:SetColorTexture(0.3, 0.3, 0.1, 0.3)
    row.highlight = highlight
    
    -- Divider line in center (optional visual)
    local divider = row:CreateTexture(nil, "ARTWORK")
    divider:SetSize(1, PLAYER_ROW_HEIGHT - 4)
    divider:SetPoint("CENTER", 0, 0)
    divider:SetColorTexture(0.3, 0.3, 0.3, 0.5)
    
    -- Name text - right aligned on left half (smaller font for compact rows)
    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameText:SetPoint("RIGHT", row, "CENTER", -3, 0)  -- 3px padding from center
    nameText:SetFont("Fonts\\FRIZQT__.TTF", 10)
    nameText:SetJustifyH("RIGHT")
    row.nameText = nameText
    
    -- Roll text - left aligned on right half
    local rollText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rollText:SetPoint("LEFT", row, "CENTER", 3, 0)  -- 3px padding from center
    rollText:SetFont("Fonts\\FRIZQT__.TTF", 10)
    rollText:SetJustifyH("LEFT")
    row.rollText = rollText
    
    return row
end

-- Clear player list
function HiLo:ClearPlayerList()
    for _, row in ipairs(self.playerRows) do
        row:Hide()
    end
    self.listContainer:SetHeight(50)
end

-- Resize frame based on content
function HiLo:ResizeFrame()
    local HL = BJ.HiLoState
    local playerCount = #HL.playerOrder
    local useDualColumns = playerCount >= DUAL_COLUMN_THRESHOLD
    
    -- Check if test bar is shown
    local testBarHeight = 0
    if self.testModeBar and self.testModeBar:IsShown() then
        testBarHeight = 35  -- Bar height + spacing
    end
    
    -- Calculate rows to display (half if dual columns)
    local rowsToDisplay = useDualColumns and math.ceil(playerCount / 2) or playerCount
    local listHeight = math.max(50, rowsToDisplay * PLAYER_ROW_HEIGHT + 10)
    local totalHeight = FRAME_MIN_HEIGHT + math.max(0, listHeight - 100) + testBarHeight
    
    -- Determine frame width based on player count
    local currentFrameWidth = useDualColumns and FRAME_WIDTH_WIDE or FRAME_WIDTH
    
    -- Update game frame size
    self.frame:SetSize(currentFrameWidth, totalHeight)
    
    -- Update felt background texture coords
    if self.frame.UpdateFeltTexCoords then
        self.frame:UpdateFeltTexCoords()
    end
    
    -- Check if Trixie should be shown (use High-Lo specific setting)
    local showTrixie = BJ.db and BJ.db.settings and BJ.db.settings.hiloShowTrixie ~= false
    local TRIXIE_WIDTH = 274
    local TRIXIE_HEIGHT = 350
    local trixieWidth = 0
    
    if showTrixie and self.trixieFrame then
        -- Fixed size Trixie, centered vertically relative to game frame
        trixieWidth = TRIXIE_WIDTH
        self.trixieFrame:SetSize(TRIXIE_WIDTH, TRIXIE_HEIGHT)
        self.trixieFrame:ClearAllPoints()
        -- Center vertically: offset from center = 0
        self.trixieFrame:SetPoint("LEFT", self.frame, "RIGHT", 0, 0)
        self.trixieFrame:Show()
    elseif self.trixieFrame then
        self.trixieFrame:Hide()
    end
    
    -- Update container width (with or without Trixie)
    self.container:SetSize(currentFrameWidth + trixieWidth, totalHeight)
    
    -- Update list container width
    self.listContainer:SetWidth(currentFrameWidth - 20)
    
    -- Reposition buttons (adjust if test bar is shown)
    local btnBottom = testBarHeight > 0 and 45 or 10
    self.btnContainer:ClearAllPoints()
    self.btnContainer:SetPoint("BOTTOM", 0, btnBottom)
    
    -- Update settlement text width
    if self.settlementText then
        self.settlementText:SetWidth(currentFrameWidth - 20)
    end
end

-- Show/Hide
function HiLo:Show()
    if not self.frame then
        self:Initialize()
    end
    
    -- Hide other game windows
    local UI = BJ.UI
    if UI.mainFrame and UI.mainFrame:IsShown() then
        UI:Hide()
    end
    if UI.Poker and UI.Poker.mainFrame and UI.Poker.mainFrame:IsShown() then
        UI.Poker:Hide()
    end
    if UI.Lobby and UI.Lobby.frame and UI.Lobby.frame:IsShown() then
        UI.Lobby.frame:Hide()
    end
    
    -- Apply saved window scale
    if UI.Lobby and UI.Lobby.ApplyWindowScale then
        UI.Lobby:ApplyWindowScale()
    end
    
    -- Apply Trixie visibility setting
    self:UpdateTrixieVisibility()
    
    self:UpdateDisplay()
    self.container:Show()
    
    -- Refresh Trixie debug if active
    if BJ.TestMode and BJ.TestMode.RefreshTrixieDebug then
        BJ.TestMode:RefreshTrixieDebug()
    end
end

function HiLo:Hide()
    if self.container then
        self.container:Hide()
    end
    -- Also hide log window
    if self.logFrame then
        self.logFrame:Hide()
    end
    
    -- Don't reset game state - user should be able to close and reopen
    -- Game state persists so they can return to it (e.g., during combat)
end

function HiLo:Toggle()
    if self.container and self.container:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

-- Log window functions
function HiLo:CreateLogWindow()
    local logFrame = CreateFrame("Frame", "CasinoHiLoLogFrame", UIParent, "BackdropTemplate")
    logFrame:SetSize(320, 350)
    logFrame:SetPoint("LEFT", self.frame, "RIGHT", 10, 0)
    logFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
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
    
    -- Title bar
    local titleBar = CreateFrame("Frame", nil, logFrame, "BackdropTemplate")
    titleBar:SetSize(320, 24)
    titleBar:SetPoint("TOP", 0, 0)
    titleBar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    titleBar:SetBackdropColor(0.15, 0.12, 0.05, 1)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() logFrame:StartMoving() end)
    titleBar:SetScript("OnDragStop", function() logFrame:StopMovingOrSizing() end)
    
    local titleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("CENTER")
    titleText:SetText("|cffffd700High-Lo - Game Log|r")
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, titleBar)
    closeBtn:SetSize(18, 18)
    closeBtn:SetPoint("RIGHT", -3, 0)
    closeBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    closeBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
    closeBtn:SetScript("OnClick", function() logFrame:Hide() end)
    
    -- Scroll frame for log content
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
    logText:SetText("No game history yet.")
    
    logFrame.scrollContent = scrollContent
    logFrame.logText = logText
    
    self.logFrame = logFrame
end

function HiLo:ToggleLog()
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

function HiLo:UpdateLogWindow()
    if not self.logFrame then return end
    
    local HL = BJ.HiLoState
    local logText = HL:GetGameLogText()
    self.logFrame.logText:SetText(logText)
    
    -- Resize scroll content to fit text
    local textHeight = self.logFrame.logText:GetStringHeight()
    self.logFrame.scrollContent:SetHeight(math.max(300, textHeight + 20))
end

--[[
    HOST RECOVERY UI HANDLERS
]]

-- Host recovery started - game is paused
function HiLo:OnHostRecoveryStart(originalHost, tempHost)
    local myName = UnitName("player")
    
    -- Update status to show recovery mode
    if self.statusText then
        self.statusText:SetText("|cffff8800PAUSED|r")
    end
    if self.settlementText then
        self.settlementText:SetText("Waiting for " .. originalHost .. " to return...\nGame will void in 2 minutes if they don't reconnect.")
    end
    
    -- Trixie looks concerned
    self:SetTrixieLose()
    
    -- Hide game buttons during recovery
    if self.startBtn then self.startBtn:Hide() end
    if self.rollBtn then self.rollBtn:Hide() end
    
    -- Show reset button only for temporary host
    if tempHost == myName then
        if self.resetBtn then
            self.resetBtn:Show()
        end
    else
        if self.resetBtn then
            self.resetBtn:Hide()
        end
    end
    
    self:UpdatePlayerList()
end

-- Update recovery timer display
function HiLo:UpdateRecoveryTimer(remaining)
    if self.statusText then
        local mins = math.floor(remaining / 60)
        local secs = remaining % 60
        local timeStr = string.format("%d:%02d", mins, secs)
        local HLM = BJ.HiLoMultiplayer
        local host = HLM.originalHost or "host"
        self.statusText:SetText("|cffff8800PAUSED - " .. timeStr .. "|r")
        if self.settlementText then
            self.settlementText:SetText("Waiting for " .. host .. " to return...")
        end
    end
end

-- Host returned - game resumes
function HiLo:OnHostRestored()
    -- Trixie is happy
    self:SetTrixieCheer()
    C_Timer.After(2.0, function()
        self:SetTrixieWait()
    end)
    
    -- Update display normally
    self:UpdateDisplay()
end

-- Game was voided due to timeout or manual reset
function HiLo:OnGameVoided(reason)
    -- Show voided message
    if self.statusText then
        self.statusText:SetText("|cffff4444VOIDED|r")
    end
    if self.settlementText then
        self.settlementText:SetText(reason or "Game voided")
    end
    
    -- Trixie is sad
    self:SetTrixieLose()
    
    -- Clear display after delay
    C_Timer.After(3.0, function()
        self:UpdateDisplay()
    end)
end
