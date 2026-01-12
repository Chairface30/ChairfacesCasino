--[[
    Chairface's Casino - UI/CrapsFrame.lua
    Craps game window with table layout and betting interface
    
    Layout:
    - Main table background (user-provided texture)
    - Clickable betting areas overlaid on table
    - Info panel showing game state
    - Shooter/roll controls
    - Trixie dealer on the side
]]

local BJ = ChairfacesCasino
local UI = BJ.UI

UI.Craps = {}
local Craps = UI.Craps

-- Frame dimensions
local FRAME_WIDTH = 750
local FRAME_HEIGHT = 550
local TRIXIE_WIDTH = 274
local TRIXIE_HEIGHT = 350

-- Chip amounts for betting (dynamically generated based on min/max)
-- Valid chip denominations (must match textures in Textures/chips/)
local VALID_CHIP_VALUES = {1, 2, 5, 10, 25, 50, 100, 500, 1000}
local CHIP_AMOUNTS = {1, 5, 10, 25, 100}  -- Default, will be recalculated

-- Get chip texture path for a denomination
local function GetChipTexturePath(value)
    return "Interface\\AddOns\\Chairfaces Casino\\Textures\\chips\\" .. value .. "g"
end

-- Get current dice style folder (nil for numeric)
local function GetDiceStyleFolder()
    if BJ.db and BJ.db.settings and BJ.db.settings.diceStyle then
        local style = BJ.db.settings.diceStyle
        if style == "scrimshaw" then
            return "scrimshaw"
        end
    end
    return nil  -- numeric
end

-- Break an amount into chip denominations (for display)
-- Returns array of {value=X, count=N} sorted largest to smallest
local function BreakIntoChips(amount)
    local chips = {}
    local remaining = amount
    
    -- Go through denominations from largest to smallest
    for i = #VALID_CHIP_VALUES, 1, -1 do
        local denom = VALID_CHIP_VALUES[i]
        local count = math.floor(remaining / denom)
        if count > 0 then
            table.insert(chips, {value = denom, count = count})
            remaining = remaining - (count * denom)
        end
    end
    
    return chips
end

-- Generate chip amounts based on min and max bet
-- Only use denominations that have textures
local function GenerateChipAmounts(minBet, maxBet)
    local amounts = {}
    
    -- Filter valid chips that are within the min/max range
    for _, val in ipairs(VALID_CHIP_VALUES) do
        if val >= minBet and val <= maxBet then
            table.insert(amounts, val)
        end
    end
    
    -- If min bet is less than 1, add 1
    if minBet < 1 and #amounts == 0 then
        table.insert(amounts, 1, 1)
    end
    
    -- If no valid chips (shouldn't happen), use min bet
    if #amounts == 0 then
        table.insert(amounts, minBet)
    end
    
    -- Limit to 5 amounts for UI space (prefer larger denominations)
    while #amounts > 5 do
        -- Remove smaller values first, but keep at least one small option
        if amounts[2] then
            table.remove(amounts, 2)
        else
            table.remove(amounts, 1)
        end
    end
    
    return amounts
end

-- Player color palette for bet display
local PLAYER_COLORS = {
    {r = 0.2, g = 0.8, b = 1.0},   -- Cyan
    {r = 1.0, g = 0.6, b = 0.2},   -- Orange
    {r = 0.6, g = 1.0, b = 0.4},   -- Lime
    {r = 1.0, g = 0.4, b = 0.8},   -- Pink
    {r = 0.8, g = 0.6, b = 1.0},   -- Lavender
    {r = 1.0, g = 1.0, b = 0.4},   -- Yellow
}

-- Initialize
function Craps:Initialize()
    if self.frame then return end
    self:CreateFrame()
    
    -- Register reset confirmation popup
    StaticPopupDialogs["CRAPS_RESET_CONFIRM"] = {
        text = "Are you sure you want to reset the game? This will end the current session for all players.",
        button1 = "Yes, Reset",
        button2 = "Cancel",
        OnAccept = function()
            local CM = BJ.CrapsMultiplayer
            CM:ResetGame()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
end

-- Create the main frame
function Craps:CreateFrame()
    -- Container for game frame + Trixie
    local container = CreateFrame("Frame", "ChairfacesCasinoCraps", UIParent)
    container:SetPoint("CENTER")
    container:SetSize(FRAME_WIDTH + TRIXIE_WIDTH, FRAME_HEIGHT)
    container:SetMovable(true)
    container:EnableMouse(true)
    container:RegisterForDrag("LeftButton")
    container:SetScript("OnDragStart", container.StartMoving)
    container:SetScript("OnDragStop", container.StopMovingOrSizing)
    container:SetClampedToScreen(true)
    container:SetFrameStrata("HIGH")
    container:Hide()
    
    self.container = container
    
    -- Main game frame
    local frame = CreateFrame("Frame", nil, container, "BackdropTemplate")
    frame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    frame:SetPoint("LEFT", container, "LEFT", 0, 0)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    frame:SetBackdropColor(0.08, 0.08, 0.12, 0.97)
    frame:SetBackdropBorderColor(0.6, 0.5, 0.2, 1)
    
    self.frame = frame
    
    -- Table background (placeholder - will use user-provided texture)
    local tableBg = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    tableBg:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\tablefelt_bg")
    tableBg:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -30)
    tableBg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 60)
    self.tableBg = tableBg
    
    -- Trixie on the right
    local trixieBtn = CreateFrame("Button", nil, container)
    trixieBtn:SetSize(TRIXIE_WIDTH, TRIXIE_HEIGHT)
    trixieBtn:SetPoint("LEFT", frame, "RIGHT", 0, 0)
    
    local trixieIdx = math.random(1, 31)
    local trixieTexture = trixieBtn:CreateTexture(nil, "ARTWORK")
    trixieTexture:SetAllPoints()
    trixieTexture:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\dealer\\trix_wait" .. trixieIdx)
    self.trixieTexture = trixieTexture
    self.trixieFrame = trixieBtn
    
    trixieBtn:SetScript("OnClick", function()
        if UI.Lobby and UI.Lobby.TryPlayPoke then
            UI.Lobby:TryPlayPoke()
        end
    end)
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame)
    closeBtn:SetSize(18, 18)
    closeBtn:SetPoint("TOPRIGHT", -6, -6)
    local closeTex = closeBtn:CreateTexture(nil, "ARTWORK")
    closeTex:SetAllPoints()
    closeTex:SetTexture("Interface\\Buttons\\UI-StopButton")
    closeBtn.texture = closeTex
    closeBtn:SetScript("OnClick", function() Craps:Hide() end)
    closeBtn:SetScript("OnEnter", function(self) 
        self.texture:SetVertexColor(1, 0.3, 0.3, 1)
    end)
    closeBtn:SetScript("OnLeave", function(self) 
        self.texture:SetVertexColor(1, 1, 1, 1)
    end)
    
    -- Back button
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
        Craps:Hide()
        if UI.Lobby then UI.Lobby:Show() end
    end)
    backBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.2, 0.45, 0.2, 1) end)
    backBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.15, 0.35, 0.15, 1) end)
    
    -- Refresh button (next to back) - uses texture icon
    local refreshBtn = CreateFrame("Button", nil, frame)
    refreshBtn:SetSize(18, 18)
    refreshBtn:SetPoint("LEFT", backBtn, "RIGHT", 4, 0)
    
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
        Craps:UpdateDisplay()
        BJ:Print("|cff00ff00Craps display refreshed.|r")
    end)
    refreshBtn:SetScript("OnEnter", function(self) 
        self.texture:SetVertexColor(0.7, 0.9, 1, 1)
    end)
    refreshBtn:SetScript("OnLeave", function(self) 
        self.texture:SetVertexColor(1, 1, 1, 1)
    end)
    self.refreshButton = refreshBtn
    
    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY")
    title:SetFont("Fonts\\MORPHEUS.TTF", 22, "OUTLINE")
    title:SetPoint("TOP", 0, -6)
    title:SetText("|cffffd700Craps|r")
    self.title = title
    
    -- Info panel (right side)
    self:CreateInfoPanel()
    
    -- Betting area (center)
    self:CreateBettingArea()
    
    -- Control buttons (bottom)
    self:CreateControls()
    
    -- Chip selector
    self:CreateChipSelector()
    
    -- Point puck display
    self:CreatePointPuck()
    
    -- Dice display
    self:CreateDiceDisplay()
    
    -- Timer display (upper right)
    self:CreateTimerDisplay()
    
    -- Update timer
    frame:SetScript("OnUpdate", function(self, elapsed)
        Craps:OnUpdate(elapsed)
    end)
end

-- Create info panel (positioned in open area above table - left side)
function Craps:CreateInfoPanel()
    local panel = CreateFrame("Frame", nil, self.frame, "BackdropTemplate")
    panel:SetSize(180, 175)  -- Expanded to fit risk line
    -- Position above table on LEFT side of open area
    panel:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 10, -35)
    panel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    panel:SetBackdropColor(0, 0, 0, 0.8)
    panel:SetBackdropBorderColor(0.5, 0.4, 0.2, 1)
    
    -- Phase text
    local phaseText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    phaseText:SetPoint("TOP", 0, -10)
    phaseText:SetText("|cffffd700No Game|r")
    self.phaseText = phaseText
    
    -- Betting timer text (shows countdown)
    local bettingTimerText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    bettingTimerText:SetPoint("TOP", phaseText, "BOTTOM", 0, -2)
    bettingTimerText:SetText("")
    bettingTimerText:Hide()
    self.bettingTimerText = bettingTimerText
    
    -- Shooter text
    local shooterText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    shooterText:SetPoint("TOP", bettingTimerText, "BOTTOM", 0, -5)
    shooterText:SetText("")
    self.shooterText = shooterText
    
    -- Point display
    local pointText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    pointText:SetPoint("TOP", shooterText, "BOTTOM", 0, -10)
    pointText:SetText("")
    self.pointText = pointText
    
    -- Last roll
    local lastRollText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lastRollText:SetPoint("TOP", pointText, "BOTTOM", 0, -15)
    lastRollText:SetText("")
    self.lastRollText = lastRollText
    
    -- Player's balance
    local balanceText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    balanceText:SetPoint("TOP", lastRollText, "BOTTOM", 0, -15)
    balanceText:SetText("")
    self.balanceText = balanceText
    
    -- Player's total bets
    local betsText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    betsText:SetPoint("TOP", balanceText, "BOTTOM", 0, -5)
    betsText:SetText("")
    self.betsText = betsText
    
    -- Risk meter (host only)
    local riskText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    riskText:SetPoint("TOP", betsText, "BOTTOM", 0, -10)
    riskText:SetText("")
    self.riskText = riskText
    
    self.infoPanel = panel
end

-- Create betting area with layered texture buttons
-- Each piece is 1200x560 with transparency, they layer on top of each other
-- Layout: Control bar at bottom, craps table above it, info panels at top
function Craps:CreateBettingArea()
    local bettingFrame = CreateFrame("Frame", nil, self.frame)
    -- Original image is 1200x560, aspect ratio 2.14:1
    -- Display at 90% scale now that frame is narrower
    local tableWidth = (FRAME_WIDTH - 10) * 0.90
    local tableHeight = tableWidth / 2.14  -- Maintain aspect ratio
    bettingFrame:SetSize(tableWidth, tableHeight)
    -- Shift right so proposition bets (rightmost content) align near window edge
    -- Original image has ~183px empty on right (out of 1200), shift by ~15% of tableWidth
    local rightShift = tableWidth * 0.14
    bettingFrame:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", rightShift, 90)  -- Raised from 65 to 90 for status bar
    self.bettingFrame = bettingFrame
    
    -- Store original image dimensions for coordinate conversion
    local IMG_WIDTH = 1200
    local IMG_HEIGHT = 560
    
    -- Background removed - bet pieces are now semi-transparent without inert background
    -- (background texture creation removed for cleaner look)
    
    self.betButtons = {}
    
    -- Bet piece definitions: betType, textureName, label, hitbox bounds (from image analysis)
    -- Bounds are in original image pixels: x, y, width, height
    local betPieces = {
        -- Main bets (larger areas)
        -- Pass Line button: top below don't pass, left cropped past curve
        {betType = "passLine", texture = "pass_line", label = "PASS LINE", bounds = {285, 487, 469, 60}},
        -- Don't Pass button: contracted to bottom bar only, left cropped where it meets big 8
        {betType = "dontPass", texture = "dont_pass", label = "DON'T PASS", bounds = {343, 429, 352, 58}},
        {betType = "field", texture = "field", label = "FIELD", bounds = {285, 254, 409, 175}},
        {betType = "come", texture = "come", label = "COME", bounds = {285, 137, 410, 116}},
        {betType = "dontCome", texture = "dont_come", label = "DON'T COME", bounds = {285, 18, 116, 118}},
        
        -- Place bets (top row)
        {betType = "place4", texture = "place4", label = "PLACE 4", bounds = {401, 18, 59, 118}},
        {betType = "place5", texture = "place5", label = "PLACE 5", bounds = {461, 18, 58, 118}},
        {betType = "place6", texture = "place6", label = "PLACE 6", bounds = {519, 18, 58, 118}},
        {betType = "place8", texture = "place8", label = "PLACE 8", bounds = {578, 18, 58, 118}},
        {betType = "place9", texture = "place9", label = "PLACE 9", bounds = {636, 18, 59, 118}},
        {betType = "place10", texture = "place10", label = "PLACE 10", bounds = {695, 18, 59, 118}},
        
        -- Big 6/8
        {betType = "big6", texture = "big6", label = "BIG 6", bounds = {226, 370, 87, 73}},
        {betType = "big8", texture = "big8", label = "BIG 8", bounds = {260, 401, 83, 85}},
        
        -- Proposition bets (right column)
        {betType = "any7", texture = "any7", label = "ANY 7", bounds = {817, 83, 200, 75}},
        {betType = "hard6", texture = "hard6", label = "HARD 6", bounds = {816, 158, 102, 77}},
        {betType = "hard8", texture = "hard8", label = "HARD 8", bounds = {918, 158, 100, 77}},
        {betType = "hard4", texture = "hard4", label = "HARD 4", bounds = {816, 236, 102, 76}},
        {betType = "hard10", texture = "hard10", label = "HARD 10", bounds = {918, 236, 100, 76}},
        {betType = "craps2", texture = "snake_eyes", label = "SNAKE EYES (2)", bounds = {816, 312, 102, 73}},
        {betType = "craps12", texture = "boxcars", label = "BOXCARS (12)", bounds = {918, 312, 100, 73}},
        {betType = "craps3", texture = "craps3", label = "ACE-DEUCE (3)", bounds = {816, 386, 102, 74}},
        {betType = "yo11", texture = "yo11", label = "YO (11)", bounds = {918, 386, 100, 74}},
        {betType = "anyCraps", texture = "any_craps", label = "ANY CRAPS", bounds = {809, 461, 208, 74}},
    }
    
    -- Create each bet button with its texture
    for i, piece in ipairs(betPieces) do
        self:CreateLayeredBetButton(piece.betType, piece.texture, piece.label, piece.bounds, IMG_WIDTH, IMG_HEIGHT, i)
    end
end

-- Create a bet button with its own texture layer
function Craps:CreateLayeredBetButton(betType, textureName, label, bounds, imgWidth, imgHeight, layer)
    local parent = self.bettingFrame
    local pw, ph = parent:GetWidth(), parent:GetHeight()
    
    -- Convert image pixel coordinates to frame coordinates
    -- bounds = {x, y, width, height} in original image pixels
    -- Note: Y is flipped because we flipped the TGA
    local scaleX = pw / imgWidth
    local scaleY = ph / imgHeight
    
    local x = bounds[1] * scaleX
    local y = (imgHeight - bounds[2] - bounds[4]) * scaleY  -- Flip Y
    local w = bounds[3] * scaleX
    local h = bounds[4] * scaleY
    
    -- Create the button
    local btn = CreateFrame("Button", nil, parent)
    btn:SetFrameLevel(parent:GetFrameLevel() + layer)
    btn:SetSize(w, h)
    btn:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", x, y)
    
    -- Add the texture
    local tex = btn:CreateTexture(nil, "ARTWORK")
    tex:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\craps\\" .. textureName)
    tex:SetAlpha(0.65)  -- 65% opacity for all bet pieces
    
    -- Special handling for passLine and dontPass - show full texture, not cropped to button bounds
    if betType == "passLine" or betType == "dontPass" then
        -- Show the entire texture at full size, anchored to match the table
        tex:ClearAllPoints()
        tex:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
        tex:SetSize(pw, ph)
        tex:SetTexCoord(0, 1, 0, 1)  -- Full texture, no cropping
    else
        -- Set texture coordinates to show only this button's portion of the image
        local texLeft = bounds[1] / imgWidth
        local texRight = (bounds[1] + bounds[3]) / imgWidth
        local texTop = bounds[2] / imgHeight
        local texBottom = (bounds[2] + bounds[4]) / imgHeight
        tex:SetTexCoord(texLeft, texRight, texTop, texBottom)
        tex:SetAllPoints(btn)
    end
    btn.texture = tex
    
    -- Create highlight texture (shows on hover)
    local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.25)
    
    -- Player's own bet amount display (increased font size)
    local amountText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    amountText:SetPoint("CENTER", 0, 0)
    amountText:SetText("")
    btn.amountText = amountText
    
    -- All bet types now use numbers display
    btn.displayType = "numbers"
    
    -- Create bet marker frames for other players (all use numbers now)
    btn.betMarkers = {}
    
    -- Determine layout based on bet type
    if betType == "passLine" or betType == "passLine2" or betType == "dontPass" or betType == "come" or betType == "dontCome" or betType == "field" then
        -- Horizontal layout for large areas
        for i = 1, 8 do
            local marker = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            marker:SetPoint("LEFT", btn, "LEFT", 5 + (i-1) * 28, -10)
            marker:SetText("")
            btn.betMarkers[i] = marker
        end
    elseif betType:match("^place") then
        -- Ring layout for place bets
        local positions = {
            {x = -15, y = 8}, {x = 0, y = 12}, {x = 15, y = 8}, {x = 20, y = 0},
            {x = 15, y = -8}, {x = 0, y = -12}, {x = -15, y = -8}, {x = -20, y = 0},
        }
        for i = 1, 8 do
            local marker = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            marker:SetPoint("CENTER", btn, "CENTER", positions[i].x, positions[i].y)
            marker:SetText("")
            btn.betMarkers[i] = marker
        end
    else
        -- Compact layout for proposition bets
        for i = 1, 8 do
            local marker = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            local row = math.floor((i-1) / 4)
            local col = (i-1) % 4
            marker:SetPoint("TOPLEFT", btn, "TOPLEFT", 3 + col * 22, -3 - row * 12)
            marker:SetText("")
            btn.betMarkers[i] = marker
        end
    end
    
    btn.betType = betType
    btn.label = label
    
    -- Create chip stack container for this bet button
    btn.chipStacks = {}  -- Will hold chip stack frames for each player
    
    -- Register for both left and right clicks
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    
    btn:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            -- Right-click to remove bet (only for place bets during betting)
            Craps:OnBetButtonRightClick(betType)
        else
            -- Left-click to place bet
            Craps:OnBetButtonClick(betType)
        end
    end)
    
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(label, 1, 0.84, 0)
        Craps:ShowBetTooltip(betType)
        GameTooltip:Show()
    end)
    
    btn:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
    
    self.betButtons[betType] = btn
end

-- Create or update a chip stack display for a player's bet on a button
-- Returns a frame containing stacked chip textures
function Craps:CreateChipStack(parent, amount, playerColor, stackIndex, totalStacks, scale)
    scale = scale or 1.0
    local CHIP_SIZE = 20 * scale  -- Size of each chip texture
    local STACK_OFFSET = 3 * scale  -- Vertical offset between chips in a stack
    
    -- Create frame to hold the stack
    local stackFrame = CreateFrame("Frame", nil, parent)
    stackFrame:SetSize(CHIP_SIZE, CHIP_SIZE + 20 * scale)  -- Extra height for stacking
    
    -- Position based on index - spread horizontally across the button
    local spacing = math.min(30 * scale, parent:GetWidth() / math.max(totalStacks, 1))
    local startX = (parent:GetWidth() - (totalStacks * spacing)) / 2
    stackFrame:SetPoint("BOTTOM", parent, "BOTTOM", startX + (stackIndex - 0.5) * spacing - parent:GetWidth()/2, 5)
    stackFrame:SetFrameLevel(parent:GetFrameLevel() + 10)
    
    -- Clear existing chips
    if stackFrame.chips then
        for _, chip in ipairs(stackFrame.chips) do
            chip:Hide()
        end
    end
    stackFrame.chips = {}
    
    -- Break amount into chip denominations
    local chips = BreakIntoChips(amount)
    
    -- Create chip textures (show up to 5 chips, stacked)
    local chipCount = 0
    local maxChips = 5  -- Max chips to show per stack
    local yOffset = 0
    
    for _, chipData in ipairs(chips) do
        for i = 1, math.min(chipData.count, maxChips - chipCount) do
            local chip = stackFrame:CreateTexture(nil, "ARTWORK", nil, chipCount)
            chip:SetSize(CHIP_SIZE, CHIP_SIZE)
            chip:SetPoint("BOTTOM", stackFrame, "BOTTOM", 0, yOffset)
            chip:SetTexture(GetChipTexturePath(chipData.value))
            
            -- Apply player color tint (subtle)
            if playerColor then
                -- Mix with white so chips are still recognizable
                local tintR = 0.7 + playerColor.r * 0.3
                local tintG = 0.7 + playerColor.g * 0.3
                local tintB = 0.7 + playerColor.b * 0.3
                chip:SetVertexColor(tintR, tintG, tintB)
            end
            
            table.insert(stackFrame.chips, chip)
            chipCount = chipCount + 1
            yOffset = yOffset + STACK_OFFSET
            
            if chipCount >= maxChips then break end
        end
        if chipCount >= maxChips then break end
    end
    
    -- Add amount text below the stack
    if not stackFrame.amountText then
        local text = stackFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetPoint("TOP", stackFrame, "BOTTOM", 0, -2)
        stackFrame.amountText = text
    end
    
    local colorHex = "ffffff"
    if playerColor then
        colorHex = string.format("%02x%02x%02x", playerColor.r * 255, playerColor.g * 255, playerColor.b * 255)
    end
    stackFrame.amountText:SetText("|cff" .. colorHex .. amount .. "|r")
    
    stackFrame:Show()
    return stackFrame
end

-- Clear all chip stacks from a bet button
function Craps:ClearChipStacks(btn)
    if btn.chipStacks then
        for _, stack in pairs(btn.chipStacks) do
            if stack.chips then
                for _, chip in ipairs(stack.chips) do
                    chip:Hide()
                end
            end
            if stack.amountText then
                stack.amountText:SetText("")
            end
            stack:Hide()
        end
    end
    btn.chipStacks = {}
    
    -- Also clear old text markers
    if btn.amountText then
        btn.amountText:SetText("")
    end
    if btn.betMarkers then
        for _, marker in ipairs(btn.betMarkers) do
            marker:SetText("")
        end
    end
end

-- Update debug borders on all bet buttons (magenta when debug mode is on)
function Craps:UpdateDebugBorders()
    if not self.betButtons then return end
    
    local showDebug = BJ.debugMode
    
    for betType, btn in pairs(self.betButtons) do
        if showDebug then
            -- Show magenta debug border
            if not btn.debugBorder then
                -- Create debug border textures
                btn.debugBorder = {}
                
                -- Top border
                local top = btn:CreateTexture(nil, "OVERLAY")
                top:SetColorTexture(1, 0, 1, 1)  -- Magenta
                top:SetHeight(1)
                top:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
                top:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 0, 0)
                btn.debugBorder.top = top
                
                -- Bottom border
                local bottom = btn:CreateTexture(nil, "OVERLAY")
                bottom:SetColorTexture(1, 0, 1, 1)
                bottom:SetHeight(1)
                bottom:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
                bottom:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
                btn.debugBorder.bottom = bottom
                
                -- Left border
                local left = btn:CreateTexture(nil, "OVERLAY")
                left:SetColorTexture(1, 0, 1, 1)
                left:SetWidth(1)
                left:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
                left:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
                btn.debugBorder.left = left
                
                -- Right border
                local right = btn:CreateTexture(nil, "OVERLAY")
                right:SetColorTexture(1, 0, 1, 1)
                right:SetWidth(1)
                right:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 0, 0)
                right:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
                btn.debugBorder.right = right
            end
            
            -- Show borders
            btn.debugBorder.top:Show()
            btn.debugBorder.bottom:Show()
            btn.debugBorder.left:Show()
            btn.debugBorder.right:Show()
        else
            -- Hide debug borders if they exist
            if btn.debugBorder then
                btn.debugBorder.top:Hide()
                btn.debugBorder.bottom:Hide()
                btn.debugBorder.left:Hide()
                btn.debugBorder.right:Hide()
            end
        end
    end
end

-- Create control buttons
function Craps:CreateControls()
    local controlFrame = CreateFrame("Frame", nil, self.frame)
    controlFrame:SetSize(FRAME_WIDTH - 20, 50)
    controlFrame:SetPoint("BOTTOM", self.frame, "BOTTOM", 0, 5)
    self.controlFrame = controlFrame
    
    -- Status bar (above control frame, below betting pieces)
    local statusBar = CreateFrame("Frame", nil, self.frame, "BackdropTemplate")
    statusBar:SetSize(FRAME_WIDTH - 40, 25)
    statusBar:SetPoint("BOTTOM", controlFrame, "TOP", 0, 2)
    statusBar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    statusBar:SetBackdropColor(0, 0, 0, 0.6)
    statusBar:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)
    
    local statusText = statusBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    statusText:SetPoint("CENTER")
    statusText:SetTextColor(1, 0.84, 0, 1)
    statusText:SetText("Welcome to Craps!")
    statusBar.text = statusText
    
    self.statusBar = statusBar
    
    -- Host/Join button
    local actionBtn = CreateFrame("Button", nil, controlFrame, "BackdropTemplate")
    actionBtn:SetSize(120, 40)
    actionBtn:SetPoint("LEFT", controlFrame, "LEFT", 10, 0)
    actionBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    actionBtn:SetBackdropColor(0.15, 0.35, 0.15, 1)
    actionBtn:SetBackdropBorderColor(0.3, 0.7, 0.3, 1)
    
    local actionText = actionBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    actionText:SetPoint("CENTER")
    actionText:SetText("|cffffffff HOST |r")
    actionBtn.text = actionText
    
    actionBtn:SetScript("OnClick", function() Craps:OnActionClick() end)
    actionBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.2, 0.5, 0.2, 1)
    end)
    actionBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.15, 0.35, 0.15, 1)
    end)
    self.actionButton = actionBtn
    
    -- Lock In button (player only - during betting phase)
    local lockInBtn = CreateFrame("Button", nil, controlFrame, "BackdropTemplate")
    lockInBtn:SetSize(100, 35)
    lockInBtn:SetPoint("RIGHT", controlFrame, "RIGHT", -170, 0)  -- Left of Cash Out button
    lockInBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    lockInBtn:SetBackdropColor(0.2, 0.4, 0.6, 1)
    lockInBtn:SetBackdropBorderColor(0.3, 0.6, 0.9, 1)
    
    -- Lock icon on left side
    local lockIcon = lockInBtn:CreateTexture(nil, "ARTWORK")
    lockIcon:SetSize(20, 20)
    lockIcon:SetPoint("LEFT", lockInBtn, "LEFT", 8, 0)
    lockIcon:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\lock")
    
    local lockInText = lockInBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lockInText:SetPoint("LEFT", lockIcon, "RIGHT", 4, 0)
    lockInText:SetText("|cffffffffLock In|r")
    lockInBtn.text = lockInText
    
    lockInBtn:SetScript("OnClick", function() Craps:OnLockInClick() end)
    lockInBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.3, 0.5, 0.7, 1)
    end)
    lockInBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.2, 0.4, 0.6, 1)
    end)
    lockInBtn:Hide()
    self.lockInButton = lockInBtn
    
    -- Cash Out button (player only - leave table with receipt) - positioned left of Log
    local cashOutBtn = CreateFrame("Button", nil, controlFrame, "BackdropTemplate")
    cashOutBtn:SetSize(80, 30)
    cashOutBtn:SetPoint("RIGHT", controlFrame, "RIGHT", -80, 0)  -- Left of Log button
    cashOutBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    cashOutBtn:SetBackdropColor(0.5, 0.4, 0.1, 1)
    cashOutBtn:SetBackdropBorderColor(0.8, 0.6, 0.2, 1)
    
    local cashOutText = cashOutBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cashOutText:SetPoint("CENTER")
    cashOutText:SetText("|cffffffffCash Out|r")
    
    cashOutBtn:SetScript("OnClick", function() Craps:OnCashOutClick() end)
    cashOutBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.6, 0.5, 0.15, 1)
    end)
    cashOutBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.5, 0.4, 0.1, 1)
    end)
    cashOutBtn:Hide()
    self.cashOutButton = cashOutBtn
    
    -- Roll button (shooter only) - positioned on left side
    local rollBtn = CreateFrame("Button", nil, controlFrame, "BackdropTemplate")
    rollBtn:SetSize(150, 40)
    rollBtn:SetPoint("LEFT", controlFrame, "LEFT", 10, 0)
    rollBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    rollBtn:SetBackdropColor(0.4, 0.2, 0.5, 1)
    rollBtn:SetBackdropBorderColor(0.6, 0.3, 0.8, 1)
    
    -- Left dice icon
    local leftDice = rollBtn:CreateTexture(nil, "OVERLAY")
    leftDice:SetSize(24, 24)
    leftDice:SetPoint("LEFT", rollBtn, "LEFT", 15, 0)
    leftDice:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\dice_icon")
    
    -- Roll text in center
    local rollText = rollBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    rollText:SetPoint("CENTER")
    rollText:SetText("|cffff88ffROLL|r")
    rollBtn.text = rollText
    
    -- Right dice icon
    local rightDice = rollBtn:CreateTexture(nil, "OVERLAY")
    rightDice:SetSize(24, 24)
    rightDice:SetPoint("RIGHT", rollBtn, "RIGHT", -15, 0)
    rightDice:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\dice_icon")
    
    rollBtn:SetScript("OnClick", function() Craps:OnRollClick() end)
    rollBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.5, 0.3, 0.6, 1)
    end)
    rollBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.4, 0.2, 0.5, 1)
    end)
    rollBtn:Hide()
    self.rollButton = rollBtn
    
    -- SKIP SHOOTER button (right of roll dice button)
    local skipBtn = CreateFrame("Button", nil, controlFrame, "BackdropTemplate")
    skipBtn:SetSize(90, 35)
    skipBtn:SetPoint("LEFT", rollBtn, "RIGHT", 10, 0)
    skipBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    skipBtn:SetBackdropColor(0.4, 0.3, 0.2, 1)
    skipBtn:SetBackdropBorderColor(0.6, 0.5, 0.3, 1)
    
    local skipText = skipBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    skipText:SetPoint("CENTER")
    skipText:SetText("|cffffffffSkip|r")
    skipBtn.text = skipText
    
    skipBtn:SetScript("OnClick", function() Craps:OnSkipShooterClick() end)
    skipBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.5, 0.4, 0.25, 1)
    end)
    skipBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.4, 0.3, 0.2, 1)
    end)
    skipBtn:Hide()
    self.skipShooterButton = skipBtn
    
    -- Close Table button (host only - closes the table)
    local closeBtn = CreateFrame("Button", nil, controlFrame, "BackdropTemplate")
    closeBtn:SetSize(100, 30)
    closeBtn:SetPoint("LEFT", controlFrame, "LEFT", 10, 0)
    closeBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    closeBtn:SetBackdropColor(0.5, 0.3, 0.1, 1)
    closeBtn:SetBackdropBorderColor(0.7, 0.5, 0.2, 1)
    
    local closeText = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    closeText:SetPoint("CENTER")
    closeText:SetText("|cffffffffClose Table|r")
    
    closeBtn:SetScript("OnClick", function() Craps:OnCloseTableClick() end)
    closeBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.6, 0.4, 0.15, 1) end)
    closeBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.5, 0.3, 0.1, 1) end)
    closeBtn:Hide()
    self.closeTableButton = closeBtn
    
    -- Reset button (host only - resets all state)
    local resetBtn = CreateFrame("Button", nil, controlFrame, "BackdropTemplate")
    resetBtn:SetSize(70, 30)
    resetBtn:SetPoint("RIGHT", controlFrame, "RIGHT", -170, 0)  -- Left of Cash Out
    resetBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    resetBtn:SetBackdropColor(0.5, 0.2, 0.2, 1)
    resetBtn:SetBackdropBorderColor(0.7, 0.3, 0.3, 1)
    
    local resetText = resetBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    resetText:SetPoint("CENTER")
    resetText:SetText("|cffffffffReset|r")
    
    resetBtn:SetScript("OnClick", function() Craps:OnResetClick() end)
    resetBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.6, 0.3, 0.3, 1) end)
    resetBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.5, 0.2, 0.2, 1) end)
    resetBtn:Hide()
    self.resetButton = resetBtn
    
    -- Log button (far right - shows roll/bet history)
    local logBtn = CreateFrame("Button", nil, controlFrame, "BackdropTemplate")
    logBtn:SetSize(60, 30)
    logBtn:SetPoint("RIGHT", controlFrame, "RIGHT", -10, 0)
    logBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    logBtn:SetBackdropColor(0.2, 0.3, 0.4, 1)
    logBtn:SetBackdropBorderColor(0.4, 0.5, 0.6, 1)
    
    local logText = logBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    logText:SetPoint("CENTER")
    logText:SetText("|cffffffffLog|r")
    
    logBtn:SetScript("OnClick", function() Craps:ToggleLogPanel() end)
    logBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.3, 0.4, 0.5, 1) end)
    logBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.2, 0.3, 0.4, 1) end)
    logBtn:Show()
    self.logButton = logBtn
    
    -- Create log panel
    self:CreateLogPanel()
end

-- Create log panel for roll/bet history
function Craps:CreateLogPanel()
    local panel = CreateFrame("Frame", "CrapsLogPanel", self.frame, "BackdropTemplate")
    panel:SetSize(350, 400)
    panel:SetPoint("LEFT", self.frame, "RIGHT", 10, 0)
    panel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    panel:SetBackdropColor(0.05, 0.08, 0.12, 0.95)
    panel:SetBackdropBorderColor(0.3, 0.4, 0.5, 1)
    panel:SetFrameStrata("DIALOG")
    panel:Hide()
    
    -- Title
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", panel, "TOP", 0, -10)
    title:SetText("|cffffd700Roll History|r")
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, panel)
    closeBtn:SetSize(20, 20)
    closeBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -5, -5)
    closeBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    closeBtn:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
    closeBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
    closeBtn:SetScript("OnClick", function() panel:Hide() end)
    
    -- Scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", "CrapsLogScrollFrame", panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -35)
    scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -30, 10)
    
    -- Content frame
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(300, 1)  -- Height will grow
    scrollFrame:SetScrollChild(content)
    
    -- Log text
    local logText = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    logText:SetPoint("TOPLEFT", content, "TOPLEFT", 5, -5)
    logText:SetWidth(290)
    logText:SetJustifyH("LEFT")
    logText:SetJustifyV("TOP")
    logText:SetText("")
    
    panel.logText = logText
    panel.content = content
    self.logPanel = panel
end

-- Toggle log panel visibility
function Craps:ToggleLogPanel()
    if not self.logPanel then return end
    
    if self.logPanel:IsShown() then
        self.logPanel:Hide()
    else
        self:UpdateLogPanel()
        self.logPanel:Show()
    end
end

-- Update log panel with saved history
function Craps:UpdateLogPanel()
    if not self.logPanel then return end
    
    local log = BJ.db and BJ.db.crapsLog or {}
    local lines = {}
    
    if #log == 0 then
        table.insert(lines, "|cff888888No roll history yet.|r")
    else
        for i = #log, 1, -1 do  -- Show newest first
            local entry = log[i]
            local line = ""
            
            -- Roll info
            if entry.die1 and entry.die2 then
                local total = entry.die1 + entry.die2
                line = line .. "|cffffd700[" .. entry.die1 .. "+" .. entry.die2 .. "=" .. total .. "]|r "
            end
            
            -- Result
            if entry.result then
                local resultColor = "|cffaaaaaa"
                if entry.result == "natural" or entry.result == "point_hit" then
                    resultColor = "|cff00ff00"
                elseif entry.result == "craps" or entry.result == "seven_out" then
                    resultColor = "|cffff4444"
                elseif entry.result == "point_set" then
                    resultColor = "|cff00aaff"
                end
                line = line .. resultColor .. entry.result .. "|r"
            end
            
            -- Player breakdown
            if entry.settlements then
                for playerName, data in pairs(entry.settlements) do
                    if data.winnings ~= 0 or (data.messages and #data.messages > 0) then
                        local wColor = data.winnings >= 0 and "|cff00ff00" or "|cffff4444"
                        local wSign = data.winnings >= 0 and "+" or ""
                        line = line .. "\n  |cffcccccc" .. playerName .. ":|r " .. wColor .. wSign .. BJ:FormatGold(data.winnings) .. "|r"
                        
                        -- Show bet breakdown
                        if data.messages then
                            for _, msg in ipairs(data.messages) do
                                line = line .. "\n    |cff888888- " .. msg .. "|r"
                            end
                        end
                    end
                end
            end
            
            -- Timestamp
            if entry.timestamp then
                line = "|cff666666" .. date("%H:%M:%S", entry.timestamp) .. "|r " .. line
            end
            
            table.insert(lines, line)
            table.insert(lines, "")  -- Blank line between entries
        end
    end
    
    local text = table.concat(lines, "\n")
    self.logPanel.logText:SetText(text)
    
    -- Adjust content height
    local height = self.logPanel.logText:GetStringHeight() + 20
    self.logPanel.content:SetHeight(math.max(height, 380))
end

-- Add entry to the log (called after each roll)
function Craps:AddLogEntry(die1, die2, result, settlements)
    -- Ensure BJ.db exists
    if not BJ.db then
        BJ.db = ChairfacesCasinoDB or { settings = {} }
    end
    
    if not BJ.db.crapsLog then
        BJ.db.crapsLog = {}
    end
    
    local entry = {
        timestamp = time(),
        die1 = die1,
        die2 = die2,
        result = result,
        settlements = {}
    }
    
    -- Copy settlement data if available (host has it, clients don't initially)
    if settlements then
        for playerName, data in pairs(settlements) do
            entry.settlements[playerName] = {
                winnings = data.winnings or 0,
                messages = data.messages or {}
            }
        end
    end
    
    table.insert(BJ.db.crapsLog, entry)
    
    -- Keep only last 50 entries
    while #BJ.db.crapsLog > 50 do
        table.remove(BJ.db.crapsLog, 1)
    end
    
    -- Store reference to latest entry for clients to update with settlements
    self.pendingLogEntry = entry
    
    -- Update panel if visible
    if self.logPanel and self.logPanel:IsShown() then
        self:UpdateLogPanel()
    end
end

-- Update the most recent log entry with settlement info (for clients)
function Craps:UpdateLogEntryWithSettlement(playerName, winnings, messages)
    if not self.pendingLogEntry then return end
    
    self.pendingLogEntry.settlements[playerName] = {
        winnings = winnings,
        messages = messages or {}
    }
    
    -- Update panel if visible
    if self.logPanel and self.logPanel:IsShown() then
        self:UpdateLogPanel()
    end
end

-- Set status bar message
function Craps:SetStatus(msg, color)
    if not self.statusBar then return end
    
    if color then
        self.statusBar.text:SetTextColor(color.r or 1, color.g or 0.84, color.b or 0, 1)
    else
        self.statusBar.text:SetTextColor(1, 0.84, 0, 1)  -- Default gold
    end
    
    self.statusBar.text:SetText(msg or "")
end

-- Update status bar based on game state
function Craps:UpdateStatus()
    local CS = BJ.CrapsState
    local CM = BJ.CrapsMultiplayer
    local myName = UnitName("player")
    
    if not CM.tableOpen then
        self:SetStatus("Welcome to Craps!")
        return
    end
    
    local player = CS.players[myName]
    local isHost = player and player.isHost
    local isShooter = CS.shooterName == myName
    
    -- Check game phase
    if CS.phase == CS.PHASE.IDLE then
        if isHost then
            self:SetStatus("Waiting for players to join...")
        else
            self:SetStatus("Waiting for game to start...")
        end
    elseif CS.phase == CS.PHASE.BETTING then
        local timeLeft = CS.bettingTimeRemaining or 0
        if timeLeft > 0 then
            self:SetStatus("Place your bets! " .. timeLeft .. "s remaining", {r=0.5, g=1, b=0.5})
        else
            self:SetStatus("Place your bets!", {r=0.5, g=1, b=0.5})
        end
    elseif CS.phase == CS.PHASE.COME_OUT then
        if isShooter then
            self:SetStatus("You're the shooter! Roll for a come-out!", {r=0, g=1, b=1})
        elseif CS.shooterName then
            self:SetStatus(CS.shooterName .. " is rolling come-out...", {r=1, g=0.84, b=0})
        else
            self:SetStatus("Waiting for shooter...", {r=0.7, g=0.7, b=0.7})
        end
    elseif CS.phase == CS.PHASE.POINT then
        local pointStr = CS.point and tostring(CS.point) or "?"
        if isShooter then
            self:SetStatus("Point is " .. pointStr .. " - Roll to hit it!", {r=0, g=1, b=1})
        elseif CS.shooterName then
            self:SetStatus(CS.shooterName .. " rolling for point " .. pointStr, {r=1, g=0.84, b=0})
        else
            self:SetStatus("Point is " .. pointStr, {r=1, g=0.84, b=0})
        end
    elseif CS.phase == CS.PHASE.ROLLING then
        self:SetStatus("Rolling the dice...", {r=1, g=1, b=0.5})
    else
        self:SetStatus("")
    end
end

-- Create shooter selection panel (host only)
function Craps:CreateShooterPanel()
    local panel = CreateFrame("Frame", "CrapsShooterPanel", self.frame, "BackdropTemplate")
    panel:SetSize(180, 200)
    panel:SetPoint("BOTTOM", self.controlFrame, "TOP", 0, 5)
    panel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    panel:SetBackdropColor(0.1, 0.15, 0.2, 0.95)
    panel:SetBackdropBorderColor(0.3, 0.5, 0.7, 1)
    panel:SetFrameStrata("DIALOG")
    panel:Hide()
    
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -8)
    title:SetText("|cffffd700Select Shooter|r")
    
    -- Create player buttons
    self.shooterPanelRows = {}
    for i = 1, 8 do
        local btn = CreateFrame("Button", nil, panel, "BackdropTemplate")
        btn:SetSize(160, 22)
        btn:SetPoint("TOP", panel, "TOP", 0, -28 - (i-1) * 24)
        btn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        btn:SetBackdropColor(0.2, 0.2, 0.2, 1)
        btn:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
        
        local text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetPoint("CENTER")
        btn.text = text
        
        btn:SetScript("OnEnter", function(self)
            self:SetBackdropColor(0.3, 0.4, 0.5, 1)
        end)
        btn:SetScript("OnLeave", function(self)
            self:SetBackdropColor(0.2, 0.2, 0.2, 1)
        end)
        btn:Hide()
        
        self.shooterPanelRows[i] = btn
    end
    
    self.shooterPanel = panel
end

-- Toggle shooter selection panel
function Craps:ToggleShooterPanel()
    if not self.shooterPanel then return end
    
    if self.shooterPanel:IsShown() then
        self.shooterPanel:Hide()
    else
        self:UpdateShooterPanel()
        self.shooterPanel:Show()
    end
end

-- Update shooter panel with available players
function Craps:UpdateShooterPanel()
    local CS = BJ.CrapsState
    local CM = BJ.CrapsMultiplayer
    
    if not self.shooterPanel then return end
    
    -- Gather non-host players
    local players = {}
    for name, player in pairs(CS.players) do
        if not player.isHost and not player.isSpectator then
            local color = self.playerColors and self.playerColors[name]
            table.insert(players, {name = name, color = color})
        end
    end
    table.sort(players, function(a, b) return a.name < b.name end)
    
    -- Update buttons
    for i, btn in ipairs(self.shooterPanelRows) do
        local p = players[i]
        if p then
            local colorHex = "ffffff"
            if p.color then
                colorHex = string.format("%02x%02x%02x", p.color.r * 255, p.color.g * 255, p.color.b * 255)
            end
            btn.text:SetText("|cff" .. colorHex .. p.name .. "|r")
            btn:SetScript("OnClick", function()
                Craps:OnSelectShooter(p.name)
            end)
            btn:Show()
        else
            btn:Hide()
        end
    end
end

-- Host selects a shooter and starts the game
function Craps:OnSelectShooter(playerName)
    local CM = BJ.CrapsMultiplayer
    
    if not CM.isHost then return end
    
    -- Use AssignShooter which handles everything
    CM:AssignShooter(playerName)
    
    BJ:Print("|cffffd700" .. playerName .. " is now the shooter!|r")
    
    -- Hide panel
    self.shooterPanel:Hide()
    self:UpdateDisplay()
end

-- Create chip selector (positioned with left edge at table's left edge)
function Craps:CreateChipSelector()
    local chipFrame = CreateFrame("Frame", nil, self.frame, "BackdropTemplate")
    chipFrame:SetSize(250, 70)  -- Horizontal layout
    -- Anchor to game window's upper right corner
    chipFrame:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -10, -35)
    chipFrame:SetFrameLevel(self.bettingFrame:GetFrameLevel() + 30)  -- Layer over table
    chipFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    chipFrame:SetBackdropColor(0, 0, 0, 0.85)
    chipFrame:SetBackdropBorderColor(0.4, 0.3, 0.2, 1)
    
    local label = chipFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", 8, 0)
    label:SetText("|cffffd700Bet:|r")
    
    self.selectedChip = 1
    self.chipButtons = {}
    self.chipFrame = chipFrame
    
    -- Will be populated by UpdateChipSelector
end

-- Update chip selector based on table min/max
function Craps:UpdateChipSelector()
    local CS = BJ.CrapsState
    local minBet = CS.minBet or 1
    local maxBet = CS.maxBet or 100
    
    CHIP_AMOUNTS = GenerateChipAmounts(minBet, maxBet)
    self.selectedChip = CHIP_AMOUNTS[1]
    
    -- Clear existing buttons
    for _, btn in pairs(self.chipButtons or {}) do
        btn:Hide()
        btn:SetParent(nil)
    end
    self.chipButtons = {}
    
    -- Create new buttons with chip textures (horizontally arranged, right to left)
    local buttonSize = 40  -- Smaller button hitbox
    local textureSize = 64 -- Full size chip texture
    local spacing = 44     -- Tight spacing
    local startX = 35      -- Start after "Bet:" label
    
    for i, amount in ipairs(CHIP_AMOUNTS) do
        local btn = CreateFrame("Button", nil, self.chipFrame)
        btn:SetSize(buttonSize, buttonSize)
        -- Position horizontally from left to right
        btn:SetPoint("LEFT", self.chipFrame, "LEFT", startX + (i-1) * spacing, 0)
        
        -- Chip texture (larger than button, centered)
        local chipTex = btn:CreateTexture(nil, "ARTWORK")
        chipTex:SetSize(textureSize, textureSize)
        chipTex:SetPoint("CENTER", btn, "CENTER", 0, 0)
        chipTex:SetTexture(GetChipTexturePath(amount))
        btn.chipTex = chipTex
        
        -- Selection indicator - bold golden underline
        local underline = btn:CreateTexture(nil, "OVERLAY")
        underline:SetSize(30, 4)  -- 30px wide, thick underline
        underline:SetPoint("TOP", chipTex, "BOTTOM", 0, 8)  -- Just below chip
        underline:SetTexture("Interface\\Buttons\\WHITE8x8")
        underline:SetVertexColor(1, 0.84, 0, 1)  -- Gold color
        underline:Hide()  -- Start hidden
        btn.underline = underline
        
        local selected = (amount == self.selectedChip)
        if selected then
            btn.underline:Show()
        end
        
        btn.amount = amount
        btn:SetScript("OnClick", function()
            Craps:SelectChip(amount)
        end)
        btn:SetScript("OnEnter", function()
            GameTooltip:SetOwner(btn, "ANCHOR_TOP")
            GameTooltip:SetText(amount .. "g chip", 1, 0.84, 0)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        
        self.chipButtons[amount] = btn
    end
    
    -- Resize frame to fit chips horizontally
    self.chipFrame:SetWidth(startX + #CHIP_AMOUNTS * spacing + 20)
end

-- Select chip amount
function Craps:SelectChip(amount)
    self.selectedChip = amount
    
    for amt, btn in pairs(self.chipButtons) do
        if amt == amount then
            btn.underline:Show()
        else
            btn.underline:Hide()
        end
    end
end

-- Create point puck display (positioned on table over point numbers like real craps)
function Craps:CreatePointPuck()
    -- Puck sized to match place bet width (~59px), using square aspect ratio for the circular puck
    local puckSize = 59  -- Match place bet width
    
    local puck = CreateFrame("Frame", nil, self.bettingFrame)
    puck:SetSize(puckSize, puckSize)
    puck:SetFrameLevel(self.bettingFrame:GetFrameLevel() + 50)  -- Layer over everything
    
    -- Use the ON puck texture
    local puckTex = puck:CreateTexture(nil, "ARTWORK")
    puckTex:SetAllPoints()
    puckTex:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\craps\\on_puck")
    puck.texture = puckTex
    
    -- Start hidden (no point set)
    puck:Hide()
    
    self.puck = puck
    self.puckSize = puckSize
    
    -- Store point positions - puck centered at top edge of place bet boxes
    -- Place bets: y=18 is top edge (in image coords where 0,0 is top-left)
    -- So in WoW coords (0,0 is bottom-left), top edge is at tableHeight - 18
    -- For puck half above/half below: position center at the top edge
    -- Place bet bounds from definitions:
    -- place4: x=401, w=59 -> center at 401+29.5 = 430.5
    -- place5: x=461, w=58 -> center at 461+29 = 490
    -- place6: x=519, w=58 -> center at 519+29 = 548
    -- place8: x=578, w=58 -> center at 578+29 = 607
    -- place9: x=636, w=59 -> center at 636+29.5 = 665.5
    -- place10: x=695, w=59 -> center at 695+29.5 = 724.5
    -- Y position: top of place bets is y=18 in image coords
    self.pointPositions = {
        [4] = {x = 430, y = 18},   -- Center of place4, top edge
        [5] = {x = 490, y = 18},   -- Center of place5, top edge
        [6] = {x = 548, y = 18},   -- Center of place6, top edge
        [8] = {x = 607, y = 18},   -- Center of place8, top edge
        [9] = {x = 665, y = 18},   -- Center of place9, top edge
        [10] = {x = 724, y = 18},  -- Center of place10, top edge
    }
end

-- Create dice display (in control bar area - centered)
function Craps:CreateDiceDisplay()
    local diceFrame = CreateFrame("Frame", nil, self.controlFrame)
    diceFrame:SetSize(150, 45)
    diceFrame:SetPoint("CENTER", self.controlFrame, "CENTER", 0, 0)
    
    -- Die 1
    local die1Box = CreateFrame("Frame", nil, diceFrame, "BackdropTemplate")
    die1Box:SetSize(40, 40)
    die1Box:SetPoint("LEFT", diceFrame, "LEFT", 0, 0)
    die1Box:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    die1Box:SetBackdropColor(1, 1, 1, 1)
    die1Box:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    
    local die1Text = die1Box:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    die1Text:SetPoint("CENTER")
    die1Text:SetText("")
    self.die1Text = die1Text
    
    local die1Tex = die1Box:CreateTexture(nil, "ARTWORK")
    die1Tex:SetPoint("TOPLEFT", 2, -2)
    die1Tex:SetPoint("BOTTOMRIGHT", -2, 2)
    die1Tex:Hide()
    self.die1Texture = die1Tex
    self.die1Box = die1Box
    
    -- Die 2
    local die2Box = CreateFrame("Frame", nil, diceFrame, "BackdropTemplate")
    die2Box:SetSize(40, 40)
    die2Box:SetPoint("LEFT", die1Box, "RIGHT", 5, 0)
    die2Box:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    die2Box:SetBackdropColor(1, 1, 1, 1)
    die2Box:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    
    local die2Text = die2Box:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    die2Text:SetPoint("CENTER")
    die2Text:SetText("")
    self.die2Text = die2Text
    
    local die2Tex = die2Box:CreateTexture(nil, "ARTWORK")
    die2Tex:SetPoint("TOPLEFT", 2, -2)
    die2Tex:SetPoint("BOTTOMRIGHT", -2, 2)
    die2Tex:Hide()
    self.die2Texture = die2Tex
    self.die2Box = die2Box
    
    -- Total roll display
    local totalText = diceFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    totalText:SetPoint("LEFT", die2Box, "RIGHT", 10, 0)
    totalText:SetText("")
    self.diceTotal = totalText
    
    self.diceFrame = diceFrame
    diceFrame:Hide()
end

-- Create timer display in upper right corner
function Craps:CreateTimerDisplay()
    local timerFrame = CreateFrame("Frame", nil, self.frame, "BackdropTemplate")
    timerFrame:SetSize(120, 50)
    timerFrame:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -10, -35)
    timerFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    timerFrame:SetBackdropColor(0, 0, 0, 0.8)
    timerFrame:SetBackdropBorderColor(0.5, 0.4, 0.2, 1)
    
    -- Timer label
    local timerLabel = timerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    timerLabel:SetPoint("TOP", 0, -5)
    timerLabel:SetText("|cffffd700Timer|r")
    self.timerLabel = timerLabel
    
    -- Timer value
    local timerValue = timerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    timerValue:SetPoint("TOP", timerLabel, "BOTTOM", 0, -3)
    timerValue:SetText("")
    self.timerValue = timerValue
    
    self.timerFrame = timerFrame
    timerFrame:Hide()
end

-- Show bet tooltip with payout info
function Craps:ShowBetTooltip(betType)
    local CS = BJ.CrapsState
    
    if betType == "passLine" then
        GameTooltip:AddLine("Wins on 7/11 come-out, point hit", 1, 1, 1)
        GameTooltip:AddLine("Loses on 2/3/12 come-out, 7 out", 1, 0.5, 0.5)
        GameTooltip:AddLine("Payout: 1:1 (1.41% edge)", 0.7, 0.7, 0.7)
    elseif betType == "dontPass" then
        GameTooltip:AddLine("Wins on 2/3 come-out, 7 out", 1, 1, 1)
        GameTooltip:AddLine("Loses on 7/11 come-out, point hit", 1, 0.5, 0.5)
        GameTooltip:AddLine("12 pushes | Payout: 1:1 (1.36% edge)", 0.7, 0.7, 0.7)
    elseif betType == "come" then
        GameTooltip:AddLine("Like Pass but placed during point", 1, 1, 1)
        GameTooltip:AddLine("Payout: 1:1", 0.7, 0.7, 0.7)
    elseif betType == "dontCome" then
        GameTooltip:AddLine("Like Don't Pass but placed during point", 1, 1, 1)
        GameTooltip:AddLine("12 pushes | Payout: 1:1", 0.7, 0.7, 0.7)
    elseif betType == "field" then
        GameTooltip:AddLine("One-roll bet", 1, 1, 1)
        GameTooltip:AddLine("Wins: 2, 3, 4, 9, 10, 11, 12", 0.5, 1, 0.5)
        GameTooltip:AddLine("2 & 12 pay 2:1, others 1:1", 0.7, 0.7, 0.7)
    elseif betType == "any7" then
        GameTooltip:AddLine("One-roll: wins if 7", 1, 1, 1)
        GameTooltip:AddLine("Payout: 4:1 (16.67% edge)", 0.7, 0.7, 0.7)
    elseif betType == "anyCraps" then
        GameTooltip:AddLine("One-roll: wins on 2, 3, or 12", 1, 1, 1)
        GameTooltip:AddLine("Payout: 7:1", 0.7, 0.7, 0.7)
    elseif betType == "craps2" then
        GameTooltip:AddLine("One-roll: wins on snake eyes (2)", 1, 1, 1)
        GameTooltip:AddLine("Payout: 30:1", 0.7, 0.7, 0.7)
    elseif betType == "craps3" then
        GameTooltip:AddLine("One-roll: wins on ace-deuce (3)", 1, 1, 1)
        GameTooltip:AddLine("Payout: 15:1", 0.7, 0.7, 0.7)
    elseif betType == "craps12" then
        GameTooltip:AddLine("One-roll: wins on boxcars (12)", 1, 1, 1)
        GameTooltip:AddLine("Payout: 30:1", 0.7, 0.7, 0.7)
    elseif betType == "yo11" then
        GameTooltip:AddLine("One-roll: wins on yo-leven (11)", 1, 1, 1)
        GameTooltip:AddLine("Payout: 15:1", 0.7, 0.7, 0.7)
    elseif betType == "big6" then
        GameTooltip:AddLine("Wins when 6 rolls before 7", 1, 1, 1)
        GameTooltip:AddLine("Payout: 1:1 (9.09% edge)", 0.7, 0.7, 0.7)
    elseif betType == "big8" then
        GameTooltip:AddLine("Wins when 8 rolls before 7", 1, 1, 1)
        GameTooltip:AddLine("Payout: 1:1 (9.09% edge)", 0.7, 0.7, 0.7)
    elseif betType:match("^hard") then
        local num = betType:match("hard(%d+)")
        GameTooltip:AddLine("Hard " .. num .. " wins before easy " .. num .. " or 7", 1, 1, 1)
        if num == "4" or num == "10" then
            GameTooltip:AddLine("Payout: 7:1", 0.7, 0.7, 0.7)
        else
            GameTooltip:AddLine("Payout: 9:1", 0.7, 0.7, 0.7)
        end
    elseif betType:match("^place") then
        local num = betType:match("place(%d+)")
        GameTooltip:AddLine("Place " .. num .. " - wins when " .. num .. " rolls", 1, 1, 1)
        GameTooltip:AddLine("Loses on 7", 1, 0.5, 0.5)
        -- Show payout based on number
        if num == "4" or num == "10" then
            GameTooltip:AddLine("Payout: 9:5 (6.67% edge)", 0.7, 0.7, 0.7)
        elseif num == "5" or num == "9" then
            GameTooltip:AddLine("Payout: 7:5 (4% edge)", 0.7, 0.7, 0.7)
        else  -- 6 or 8
            GameTooltip:AddLine("Payout: 7:6 (1.52% edge)", 0.7, 0.7, 0.7)
        end
        GameTooltip:AddLine("|cff88ff88Right-click to remove bet|r", 0.5, 1, 0.5)
    end
    
    -- Show current bets on this spot
    if CS and CS.players then
        local betsOnSpot = {}
        for playerName, player in pairs(CS.players) do
            if player.bets then
                local amt = 0
                local betLabel = nil
                
                -- Check direct bet type first
                if player.bets[betType] and player.bets[betType] > 0 then
                    amt = player.bets[betType]
                end
                
                -- Handle place bets (nested structure)
                if betType:match("^place") then
                    local num = tonumber(betType:match("place(%d+)"))
                    if player.bets.place and player.bets.place[num] and player.bets.place[num] > 0 then
                        amt = amt + player.bets.place[num]
                    end
                    -- Show Come bets that moved to this point
                    if player.bets.comePoints and player.bets.comePoints[num] and player.bets.comePoints[num].base > 0 then
                        local comeAmt = player.bets.comePoints[num].base
                        table.insert(betsOnSpot, {name = playerName, amount = comeAmt, label = "Come->" .. num})
                    end
                    -- Show Don't Come bets that moved to this point
                    if player.bets.dontComePoints and player.bets.dontComePoints[num] and player.bets.dontComePoints[num].base > 0 then
                        local dcAmt = player.bets.dontComePoints[num].base
                        table.insert(betsOnSpot, {name = playerName, amount = dcAmt, label = "DC->" .. num})
                    end
                end
                
                -- Handle hardways (stored as hard4, hard6, etc.)
                if betType:match("^hard") then
                    local num = betType:match("hard(%d+)")
                    if player.bets["hard" .. num] and player.bets["hard" .. num] > 0 then
                        amt = amt + player.bets["hard" .. num]
                    end
                end
                
                if amt > 0 then
                    table.insert(betsOnSpot, {name = playerName, amount = amt})
                end
            end
        end
        
        if #betsOnSpot > 0 then
            GameTooltip:AddLine(" ")  -- Blank line separator
            GameTooltip:AddLine("Current Bets:", 1, 0.84, 0)
            for _, bet in ipairs(betsOnSpot) do
                -- Get player color from UI's playerColors table (already RGB values)
                local color = self.playerColors and self.playerColors[bet.name]
                local r, g, b = 1, 1, 1
                if color and type(color) == "table" then
                    r = color.r or 1
                    g = color.g or 1
                    b = color.b or 1
                end
                local label = bet.label and (bet.name .. " (" .. bet.label .. ")") or bet.name
                GameTooltip:AddDoubleLine(label, BJ:FormatGold(bet.amount), r, g, b, 1, 1, 1)
            end
        end
    end
end

-- Event handlers

function Craps:OnBetButtonClick(betType)
    local CM = BJ.CrapsMultiplayer
    local CS = BJ.CrapsState
    local myName = UnitName("player")
    
    -- Check if we can bet - allow during BETTING phase or when betting timer is active
    local canBet = false
    if CS.phase == CS.PHASE.BETTING then
        canBet = true
    elseif (CS.phase == CS.PHASE.COME_OUT or CS.phase == CS.PHASE.POINT) and CS.bettingTimeRemaining and CS.bettingTimeRemaining > 0 then
        canBet = true
    end
    
    if not canBet then
        BJ:Print("Cannot place bets - wait for betting phase.")
        return
    end
    
    if not CS.players[myName] then
        BJ:Print("You must join the table first.")
        return
    end
    
    -- Check if player is locked in
    local player = CS.players[myName]
    if player and player.lockedIn then
        BJ:Print("|cffff8800Bets are locked! Wait for next betting phase.|r")
        return
    end
    
    -- Extract point number if it's a place bet
    local point = nil
    if betType:match("^place(%d+)") then
        point = tonumber(betType:match("place(%d+)"))
        betType = "place"
    end
    
    CM:RequestBet(betType, self.selectedChip, point)
end

-- Right-click to remove place bets during betting phase
function Craps:OnBetButtonRightClick(betType)
    local CM = BJ.CrapsMultiplayer
    local CS = BJ.CrapsState
    local myName = UnitName("player")
    
    -- Only allow for place bets
    if not betType:match("^place(%d+)") then
        return
    end
    
    -- Check if we can modify bets - allow during BETTING phase or when betting timer is active
    local canBet = false
    if CS.phase == CS.PHASE.BETTING then
        canBet = true
    elseif (CS.phase == CS.PHASE.COME_OUT or CS.phase == CS.PHASE.POINT) and CS.bettingTimeRemaining and CS.bettingTimeRemaining > 0 then
        canBet = true
    end
    
    if not canBet then
        BJ:Print("Cannot remove bets - wait for betting phase.")
        return
    end
    
    if not CS.players[myName] then
        return
    end
    
    -- Check if player is locked in
    local player = CS.players[myName]
    if player and player.lockedIn then
        BJ:Print("|cffff8800Bets are locked! Cannot remove bets.|r")
        return
    end
    
    -- Extract point number
    local point = tonumber(betType:match("place(%d+)"))
    if not point then return end
    
    -- Check if player has a bet on this number
    local bets = player.bets
    local placeAmount = (bets.place and bets.place[point]) or 0
    
    if placeAmount <= 0 then
        BJ:Print("No place bet to remove on " .. point)
        return
    end
    
    -- Request removal through multiplayer
    CM:RequestRemoveBet("place", point)
end

function Craps:OnActionClick()
    local CM = BJ.CrapsMultiplayer
    local CS = BJ.CrapsState
    local myName = UnitName("player")
    
    if CS.phase == CS.PHASE.IDLE then
        -- Show host settings panel instead of direct host
        self:ShowHostSettings()
    elseif not CS.players[myName] then
        -- Show buy-in panel instead of direct join
        self:ShowBuyInPanel()
    end
    
    self:UpdateDisplay()
end

function Craps:OnRollClick()
    local CM = BJ.CrapsMultiplayer
    local CS = BJ.CrapsState
    
    -- Check for roll cooldown
    if CS.rollCooldown and CS.rollCooldownEnd and GetTime() < CS.rollCooldownEnd then
        local remaining = math.ceil(CS.rollCooldownEnd - GetTime())
        BJ:Print("|cffff8800Wait " .. remaining .. " seconds before rolling again.|r")
        return
    end
    
    -- Clear cooldown
    CS.rollCooldown = false
    
    CM:RequestRoll()
end

function Craps:OnSkipShooterClick()
    local CM = BJ.CrapsMultiplayer
    CM:RequestSkipShooter()
end

function Craps:OnCloseTableClick()
    local CM = BJ.CrapsMultiplayer
    CM:CloseTable()
end

function Craps:OnResetClick()
    -- Show confirmation popup
    StaticPopup_Show("CRAPS_RESET_CONFIRM")
end

function Craps:OnLockInClick()
    local CM = BJ.CrapsMultiplayer
    local CS = BJ.CrapsState
    local myName = UnitName("player")
    
    -- Can lock in during betting phase OR when betting timer is still running
    local canLockIn = false
    if CS.phase == CS.PHASE.BETTING then
        canLockIn = true
    elseif (CS.phase == CS.PHASE.COME_OUT or CS.phase == CS.PHASE.POINT) and CS.bettingTimeRemaining and CS.bettingTimeRemaining > 0 then
        canLockIn = true
    end
    
    if not canLockIn then
        BJ:Print("|cffff4444Can only lock in during betting phase.|r")
        return
    end
    
    local player = CS.players[myName]
    if not player then
        BJ:Print("|cffff4444You must join the table first.|r")
        return
    end
    
    if player.lockedIn then
        BJ:Print("|cffff8800Already locked in.|r")
        return
    end
    
    CM:LockIn()
    BJ:Print("|cff00ff00Bets locked in!|r")
    self:UpdateDisplay()
end

function Craps:OnCashOutClick()
    local CM = BJ.CrapsMultiplayer
    local CS = BJ.CrapsState
    local myName = UnitName("player")
    
    if CM.isHost then
        BJ:Print("|cffff4444Host cannot cash out. Close the table instead.|r")
        return
    end
    
    local player = CS.players[myName]
    if not player then
        BJ:Print("|cffff4444You're not at the table.|r")
        return
    end
    
    -- Check if player is the active shooter
    if CS.shooterName == myName and (CS.phase == CS.PHASE.COME_OUT or CS.phase == CS.PHASE.POINT) then
        BJ:Print("|cffff8800Cannot cash out while you are the active shooter.|r")
        return
    end
    
    -- Check if player has any active bets
    local totalBets = CS:GetPlayerTotalBets(myName)
    if totalBets > 0 then
        BJ:Print("|cffff8800Cannot cash out with bets on the table. Wait for all bets to clear.|r")
        return
    end
    
    -- Request cash out
    CM:RequestCashOut()
end

function Craps:OnRollResult(die1, die2, result, settlements)
    -- Play dice sound
    self:PlayDiceSound()
    
    -- Show dice with values
    self.diceFrame:Show()
    
    local folder = GetDiceStyleFolder()
    if folder then
        -- Use texture
        self.die1Text:Hide()
        self.die2Text:Hide()
        self.die1Texture:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\dice\\" .. folder .. "\\die_" .. die1)
        self.die2Texture:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\dice\\" .. folder .. "\\die_" .. die2)
        self.die1Texture:Show()
        self.die2Texture:Show()
        self.die1Box:SetBackdropColor(0.1, 0.1, 0.1, 1)
        self.die2Box:SetBackdropColor(0.1, 0.1, 0.1, 1)
    else
        -- Use text
        self.die1Texture:Hide()
        self.die2Texture:Hide()
        self.die1Text:SetText("|cff000000" .. die1 .. "|r")
        self.die2Text:SetText("|cff000000" .. die2 .. "|r")
        self.die1Text:Show()
        self.die2Text:Show()
        self.die1Box:SetBackdropColor(1, 1, 1, 1)
        self.die2Box:SetBackdropColor(1, 1, 1, 1)
    end
    self.diceTotal:SetText("|cffffd700= " .. (die1 + die2) .. "|r")
    
    -- Update status bar based on result
    local total = die1 + die2
    if result == "natural" then
        self:SetStatus("Natural " .. total .. "! Pass Line wins!", {r=0, g=1, b=0})
    elseif result == "craps" then
        self:SetStatus("Craps " .. total .. "! Pass Line loses!", {r=1, g=0.3, b=0.3})
    elseif result == "point_established" or result == "point_set" then
        self:SetStatus("Point is " .. total .. "!", {r=0, g=0.7, b=1})
    elseif result == "point_hit" then
        self:SetStatus("Point hit! " .. total .. "! Winner!", {r=0, g=1, b=0})
    elseif result == "seven_out" then
        self:SetStatus("Seven out! Shooter loses!", {r=1, g=0.3, b=0.3})
    elseif result == "point_roll" then
        self:SetStatus("Rolled " .. total .. " - Keep rolling!", {r=1, g=0.84, b=0})
    else
        self:SetStatus("Rolled " .. total, {r=1, g=0.84, b=0})
    end
    
    -- Update puck
    local CS = BJ.CrapsState
    self:UpdatePointPuck(CS.point)
    
    -- Add to persistent log
    self:AddLogEntry(die1, die2, result, settlements)
    
    -- Play appropriate Trixie reaction
    if result == "natural" or result == "point_hit" then
        self:SetTrixieCheer()
    elseif result == "seven_out" or result == "craps" then
        self:SetTrixieLose()
    end
    
    self:UpdateDisplay()
end

-- Sound effects
function Craps:PlayDiceSound()
    -- Check if SFX is enabled in main settings
    if UI.Lobby and not UI.Lobby.sfxEnabled then return end
    local soundFile = "Interface\\AddOns\\Chairfaces Casino\\Sounds\\dice.mp3"
    PlaySoundFile(soundFile, "SFX")
end

function Craps:PlayChipsSound()
    -- Check if SFX is enabled in main settings
    if UI.Lobby and not UI.Lobby.sfxEnabled then return end
    local soundFile = "Interface\\AddOns\\Chairfaces Casino\\Sounds\\chips.ogg"
    PlaySoundFile(soundFile, "SFX")
end

-- Update point puck display (positions on table over point number)
function Craps:UpdatePointPuck(point)
    if not self.puck then return end
    
    if point and self.pointPositions[point] then
        -- Point is set - position puck over the point number on the table
        local pos = self.pointPositions[point]
        local parent = self.bettingFrame
        local pw, ph = parent:GetWidth(), parent:GetHeight()
        
        -- Convert image coordinates to frame coordinates
        local IMG_WIDTH = 1200
        local IMG_HEIGHT = 560
        local scaleX = pw / IMG_WIDTH
        local scaleY = ph / IMG_HEIGHT
        
        -- Scale puck size to match place bet width (59px in image coords)
        local scaledPuckSize = 59 * scaleX
        self.puck:SetSize(scaledPuckSize, scaledPuckSize)
        
        local x = pos.x * scaleX
        -- pos.y is the top edge of the place bet in image coords
        -- We want puck CENTER at this line (half above, half below)
        local y = (IMG_HEIGHT - pos.y) * scaleY  -- Flip Y for WoW coords
        
        self.puck:ClearAllPoints()
        self.puck:SetPoint("CENTER", parent, "BOTTOMLEFT", x, y)
        self.puck:Show()
    else
        -- Point is off - hide the puck
        self.puck:Hide()
    end
end

-- Update dice style (called when settings change)
function Craps:UpdateDiceStyle()
    -- Refresh the current display if dice are showing
    local CS = BJ.CrapsState
    if CS and CS.lastRoll then
        local folder = GetDiceStyleFolder()
        if folder then
            self.die1Text:Hide()
            self.die2Text:Hide()
            if self.die1Texture then
                self.die1Texture:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\dice\\" .. folder .. "\\die_" .. CS.lastRoll.die1)
                self.die2Texture:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\dice\\" .. folder .. "\\die_" .. CS.lastRoll.die2)
                self.die1Texture:Show()
                self.die2Texture:Show()
            end
            self.die1Box:SetBackdropColor(0.1, 0.1, 0.1, 1)
            self.die2Box:SetBackdropColor(0.1, 0.1, 0.1, 1)
        else
            if self.die1Texture then
                self.die1Texture:Hide()
                self.die2Texture:Hide()
            end
            self.die1Text:SetText("|cff000000" .. CS.lastRoll.die1 .. "|r")
            self.die2Text:SetText("|cff000000" .. CS.lastRoll.die2 .. "|r")
            self.die1Text:Show()
            self.die2Text:Show()
            self.die1Box:SetBackdropColor(1, 1, 1, 1)
            self.die2Box:SetBackdropColor(1, 1, 1, 1)
        end
    end
    
    -- Update puck
    if CS then
        self:UpdatePointPuck(CS.point)
    end
end

-- Update betting timer display (shows in upper right corner)
function Craps:UpdateBettingTimer(timeRemaining)
    if not self.timerFrame then return end
    
    if timeRemaining and timeRemaining > 0 then
        local color = "00ff00"  -- Green
        if timeRemaining <= 10 then
            color = "ffff00"  -- Yellow
        end
        if timeRemaining <= 5 then
            color = "ff4444"  -- Red
        end
        self.timerLabel:SetText("|cffffd700Betting|r")
        self.timerValue:SetText("|cff" .. color .. timeRemaining .. "s|r")
        self.timerFrame:Show()
        
        -- Also update old info panel timer if it exists
        if self.bettingTimerText then
            self.bettingTimerText:SetText("|cff" .. color .. "Betting: " .. timeRemaining .. "s|r")
            self.bettingTimerText:Show()
        end
    else
        self.timerFrame:Hide()
        if self.bettingTimerText then
            self.bettingTimerText:Hide()
        end
    end
end

function Craps:OnGameVoided(reason)
    self.phaseText:SetText("|cffff4444VOIDED|r")
    self:SetTrixieLose()
    
    C_Timer.After(3.0, function()
        self:UpdateDisplay()
    end)
end

-- Host recovery started - game is paused
function Craps:OnHostRecoveryStart(origHost, tempHost)
    self.phaseText:SetText("|cffff8800PAUSED|r")
    self:SetStatus("Waiting for " .. origHost .. " to return...", {1, 0.5, 0})
    self:UpdateDisplay()
end

-- Host has returned - game resuming
function Craps:OnHostRestored()
    self:SetStatus("Host returned! Resuming...", {0, 1, 0})
    self:UpdateDisplay()
end

-- Update recovery timer display (optional, for UI display)
function Craps:UpdateRecoveryTimer(remaining)
    if remaining <= 30 then
        self:SetStatus("Waiting for host... " .. remaining .. "s", {1, 0.3, 0.3})
    else
        self:SetStatus("Waiting for host... " .. remaining .. "s", {1, 0.5, 0})
    end
end

-- Update display
function Craps:UpdateDisplay()
    local CS = BJ.CrapsState
    local CM = BJ.CrapsMultiplayer
    local myName = UnitName("player")
    
    -- Update debug borders if debug mode changed
    self:UpdateDebugBorders()
    
    -- Phase text
    self.phaseText:SetText("|cffffd700" .. CS:GetPhaseText() .. "|r")
    
    -- Update status bar
    self:UpdateStatus()
    
    -- Shooter
    if CS.shooterName then
        local color = CS.shooterName == myName and "00ff00" or "ffffff"
        self.shooterText:SetText("|cff" .. color .. "Shooter: " .. CS.shooterName .. "|r")
    else
        self.shooterText:SetText("")
    end
    
    -- Point
    if CS.point then
        self.pointText:SetText("|cffffd700Point: " .. CS.point .. "|r")
    else
        self.pointText:SetText("")
    end
    self:UpdatePointPuck(CS.point)
    
    -- Last roll - update dice display in control bar
    if CS.lastRoll then
        local r = CS.lastRoll
        local hardText = r.isHard and " |cffff8800(HARD)|r" or ""
        self.lastRollText:SetText("Last: " .. r.die1 .. " + " .. r.die2 .. " = |cffffd700" .. r.total .. "|r" .. hardText)
        
        -- Update dice display in control bar (respects dice style)
        if self.diceFrame then
            local folder = GetDiceStyleFolder()
            if folder then
                self.die1Text:Hide()
                self.die2Text:Hide()
                if self.die1Texture then
                    self.die1Texture:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\dice\\" .. folder .. "\\die_" .. r.die1)
                    self.die2Texture:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\dice\\" .. folder .. "\\die_" .. r.die2)
                    self.die1Texture:Show()
                    self.die2Texture:Show()
                end
                self.die1Box:SetBackdropColor(0.1, 0.1, 0.1, 1)
                self.die2Box:SetBackdropColor(0.1, 0.1, 0.1, 1)
            else
                if self.die1Texture then
                    self.die1Texture:Hide()
                    self.die2Texture:Hide()
                end
                self.die1Text:SetText("|cff000000" .. r.die1 .. "|r")
                self.die2Text:SetText("|cff000000" .. r.die2 .. "|r")
                self.die1Text:Show()
                self.die2Text:Show()
                self.die1Box:SetBackdropColor(1, 1, 1, 1)
                self.die2Box:SetBackdropColor(1, 1, 1, 1)
            end
            self.diceTotal:SetText("|cffffd700= " .. r.total .. "|r")
            self.diceFrame:Show()
        end
    else
        self.lastRollText:SetText("")
        if self.diceFrame then
            self.diceFrame:Hide()
        end
    end
    
    -- Player balance (Honor Ledger)
    local player = CS.players[myName]
    if player then
        -- Show current chip balance
        self.balanceText:SetText("Balance: " .. BJ:FormatGoldColored(player.balance))
        
        local totalBets = CS:GetPlayerTotalBets(myName)
        self.betsText:SetText("Bets: " .. BJ:FormatGoldColored(totalBets))
    else
        self.balanceText:SetText("")
        self.betsText:SetText("")
    end
    
    -- Risk meter (host only)
    if CM.isHost and CS.tableCap > 0 then
        local riskPct = CS:GetRiskPercentage()
        local riskColor = "00ff00"  -- Green
        if riskPct > 75 then
            riskColor = "ff4444"  -- Red
        elseif riskPct > 50 then
            riskColor = "ff8800"  -- Orange
        elseif riskPct > 25 then
            riskColor = "ffff00"  -- Yellow
        end
        self.riskText:SetText("Risk: |cff" .. riskColor .. CS.currentRisk .. "/" .. CS.tableCap .. "g (" .. riskPct .. "%)|r")
    else
        self.riskText:SetText("")
    end
    
    -- Update bet buttons with current amounts (player's bets in green, others in orange)
    for betType, btn in pairs(self.betButtons) do
        local myAmount = 0
        local othersAmount = 0
        
        -- Get player's own bets
        if player then
            local bets = player.bets
            
            if betType == "passLine" then myAmount = bets.passLine or 0
            elseif betType == "dontPass" then myAmount = bets.dontPass or 0
            elseif betType == "come" then myAmount = bets.come or 0
            elseif betType == "dontCome" then myAmount = bets.dontCome or 0
            elseif betType == "field" then myAmount = bets.field or 0
            elseif betType == "any7" then myAmount = bets.any7 or 0
            elseif betType == "anyCraps" then myAmount = bets.anyCraps or 0
            elseif betType == "craps2" then myAmount = bets.craps2 or 0
            elseif betType == "craps3" then myAmount = bets.craps3 or 0
            elseif betType == "craps12" then myAmount = bets.craps12 or 0
            elseif betType == "yo11" then myAmount = bets.yo11 or 0
            elseif betType == "big6" then myAmount = bets.big6 or 0
            elseif betType == "big8" then myAmount = bets.big8 or 0
            elseif betType:match("^hard") then
                local num = betType:match("hard(%d+)")
                myAmount = bets["hard" .. num] or 0
            elseif betType:match("^place") then
                local num = tonumber(betType:match("place(%d+)"))
                myAmount = (bets.place and bets.place[num]) or 0
                -- Also add Come bets that moved to this point
                if bets.comePoints and bets.comePoints[num] then
                    myAmount = myAmount + (bets.comePoints[num].base or 0)
                end
                -- Also add Don't Come bets that moved to this point
                if bets.dontComePoints and bets.dontComePoints[num] then
                    myAmount = myAmount + (bets.dontComePoints[num].base or 0)
                end
            end
        end
        
        -- Get other players' bets with colors
        local otherBets = {}  -- {playerName, color, amount}
        for pName, p in pairs(CS.players) do
            if pName ~= myName and not p.isHost then
                local bets = p.bets
                local amt = 0
                
                if betType == "passLine" then amt = bets.passLine or 0
                elseif betType == "dontPass" then amt = bets.dontPass or 0
                elseif betType == "come" then amt = bets.come or 0
                elseif betType == "dontCome" then amt = bets.dontCome or 0
                elseif betType == "field" then amt = bets.field or 0
                elseif betType == "any7" then amt = bets.any7 or 0
                elseif betType == "anyCraps" then amt = bets.anyCraps or 0
                elseif betType == "craps2" then amt = bets.craps2 or 0
                elseif betType == "craps3" then amt = bets.craps3 or 0
                elseif betType == "craps12" then amt = bets.craps12 or 0
                elseif betType == "yo11" then amt = bets.yo11 or 0
                elseif betType == "big6" then amt = bets.big6 or 0
                elseif betType == "big8" then amt = bets.big8 or 0
                elseif betType:match("^hard") then
                    local num = betType:match("hard(%d+)")
                    amt = bets["hard" .. num] or 0
                elseif betType:match("^place") then
                    local num = tonumber(betType:match("place(%d+)"))
                    amt = (bets.place and bets.place[num]) or 0
                    -- Also add Come bets that moved to this point
                    if bets.comePoints and bets.comePoints[num] then
                        amt = amt + (bets.comePoints[num].base or 0)
                    end
                    -- Also add Don't Come bets that moved to this point
                    if bets.dontComePoints and bets.dontComePoints[num] then
                        amt = amt + (bets.dontComePoints[num].base or 0)
                    end
                end
                
                if amt > 0 then
                    local color = self.playerColors and self.playerColors[pName]
                    if color then
                        table.insert(otherBets, {name = pName, color = color, amount = amt})
                    end
                end
            end
        end
        
        -- Display player's own bet in their player color
        -- Clear previous chip stacks
        self:ClearChipStacks(btn)
        
        -- Collect all bets for this button (including our own)
        local allBets = {}  -- {playerName, color, amount}
        
        if myAmount > 0 then
            local myColor = self.playerColors and self.playerColors[myName]
            if myColor then
                table.insert(allBets, {name = myName, color = myColor, amount = myAmount})
            else
                table.insert(allBets, {name = myName, color = {r=0, g=1, b=0}, amount = myAmount})
            end
        end
        
        -- Add other players' bets
        for _, bet in ipairs(otherBets) do
            table.insert(allBets, bet)
        end
        
        -- Create chip stacks for all bets
        local totalStacks = #allBets
        local chipScale = 2.0  -- 2x scale for all table chips
        for i, bet in ipairs(allBets) do
            local stack = self:CreateChipStack(btn, bet.amount, bet.color, i, totalStacks, chipScale)
            btn.chipStacks[bet.name] = stack
        end
    end
    
    -- Action button and host controls
    if CS.phase == CS.PHASE.IDLE then
        -- No game - show HOST button
        self.actionButton.text:SetText("|cffffffff HOST |r")
        self.actionButton:SetBackdropColor(0.15, 0.35, 0.15, 1)
        self.actionButton:SetBackdropBorderColor(0.3, 0.7, 0.3, 1)
        self.actionButton:Show()
        self.rollButton:Hide()
        self.resetButton:Hide()
        self.lockInButton:Hide()
        if self.skipShooterButton then self.skipShooterButton:Hide() end
        self.cashOutButton:Hide()
        if self.chipFrame then self.chipFrame:Hide() end
        if self.closeTableButton then self.closeTableButton:Hide() end
        if self.rollCallPanel then self.rollCallPanel:Hide() end
        if self.playerListPanel then self.playerListPanel:Hide() end
    elseif CM.isHost then
        -- Host with active table
        self.actionButton:Hide()
        self.lockInButton:Hide()  -- Host doesn't lock in
        self.cashOutButton:Hide()  -- Host can't cash out
        if self.skipShooterButton then self.skipShooterButton:Hide() end  -- Host can't skip
        
        -- Hide chip selector for host (they don't bet)
        if self.chipFrame then self.chipFrame:Hide() end
        
        -- Show Close Table and Reset buttons
        if self.closeTableButton then 
            self.closeTableButton:Show() 
        end
        self.resetButton:Show()
        
        -- Host doesn't roll - shooter handles that
        self.rollButton:Hide()
        
        -- Update pending join requests panel
        self:UpdatePendingJoins()
        
        -- Update player balances display for host
        self:UpdateHostPlayerList()
        
        -- Update roll call for everyone to see
        self:UpdateRollCall()
    elseif not CS.players[myName] then
        -- Not at table - check if we have a pending join request
        if CS.pendingJoins and CS.pendingJoins[myName] then
            -- Waiting for approval
            self.actionButton.text:SetText("|cffffffff WAIT |r")
            self.actionButton:SetBackdropColor(0.5, 0.4, 0.1, 1)
            self.actionButton:SetBackdropBorderColor(0.8, 0.6, 0.2, 1)
        else
            -- Can join
            self.actionButton.text:SetText("|cffffffff JOIN |r")
            self.actionButton:SetBackdropColor(0.15, 0.35, 0.15, 1)
            self.actionButton:SetBackdropBorderColor(0.3, 0.7, 0.3, 1)
        end
        self.actionButton:Show()
        self.rollButton:Hide()
        self.resetButton:Hide()
        self.lockInButton:Hide()
        if self.skipShooterButton then self.skipShooterButton:Hide() end
        self.cashOutButton:Hide()
        if self.chipFrame then self.chipFrame:Hide() end
        if self.closeTableButton then self.closeTableButton:Hide() end
        -- Show roll call for non-players too
        self:UpdateRollCall()
    else
        -- Player at table
        self.actionButton:Hide()
        self.resetButton:Hide()
        if self.closeTableButton then self.closeTableButton:Hide() end
        
        -- Show chip selector for active players during betting phase
        -- Players can place/modify bets during betting phase
        if self.chipFrame then
            -- Show chip selector during betting phase when not locked in
            -- Also show during COME_OUT and POINT if there's time remaining (betting still open)
            local canBet = false
            if player and not player.isSpectator and not player.lockedIn then
                if CS.phase == CS.PHASE.BETTING then
                    canBet = true
                elseif (CS.phase == CS.PHASE.COME_OUT or CS.phase == CS.PHASE.POINT) and CS.bettingTimeRemaining and CS.bettingTimeRemaining > 0 then
                    canBet = true
                end
            end
            
            if canBet then
                -- Ensure chip buttons are created/updated (check if any buttons exist and are shown)
                local hasButtons = false
                if self.chipButtons then
                    for _, btn in pairs(self.chipButtons) do
                        if btn and btn.GetParent then
                            hasButtons = true
                            break
                        end
                    end
                end
                if not hasButtons then
                    self:UpdateChipSelector()
                end
                self.chipFrame:Show()
            else
                self.chipFrame:Hide()
            end
        end
        
        -- Lock In button - show when betting is allowed and player not locked
        -- Use same logic as chip selector: BETTING phase OR (COME_OUT/POINT with time remaining)
        local canLockIn = false
        if player and not player.lockedIn and not player.isSpectator then
            if CS.phase == CS.PHASE.BETTING then
                canLockIn = true
            elseif (CS.phase == CS.PHASE.COME_OUT or CS.phase == CS.PHASE.POINT) and CS.bettingTimeRemaining and CS.bettingTimeRemaining > 0 then
                canLockIn = true
            end
        end
        
        if canLockIn then
            self.lockInButton:Show()
        else
            self.lockInButton:Hide()
        end
        
        -- Cash Out button - only show when player can actually cash out
        -- Cannot cash out if: host, spectator, active shooter during rolling, or has bets
        local canShowCashOut = false
        if player and not player.isHost and not player.isSpectator then
            local isShooter = CS.shooterName == myName
            local isRollingPhase = CS.phase == CS.PHASE.COME_OUT or CS.phase == CS.PHASE.POINT
            local totalBets = CS:GetPlayerTotalBets(myName)
            
            -- Can only cash out if not shooter during rolling AND no bets
            if not (isShooter and isRollingPhase) and totalBets <= 0 then
                canShowCashOut = true
            end
        end
        
        if canShowCashOut then
            self.cashOutButton:Show()
        else
            self.cashOutButton:Hide()
        end
        
        -- Roll button for shooter (host cannot be shooter)
        if CS:IsShooter(myName) and (CS.phase == CS.PHASE.COME_OUT or CS.phase == CS.PHASE.POINT) then
            self.rollButton:Show()
            -- Skip button only shows if shooter and hasn't rolled yet
            if self.skipShooterButton then
                if CS.shooterHasRolled then
                    self.skipShooterButton:Hide()  -- Already rolled, must seven-out
                else
                    self.skipShooterButton:Show()  -- Haven't rolled yet, can still skip
                end
            end
        else
            self.rollButton:Hide()
            -- Not the active shooter - hide skip button
            if self.skipShooterButton then
                self.skipShooterButton:Hide()
            end
        end
        
        -- Show roll call for players too
        self:UpdateRollCall()
    end
    
    -- Update pending reconnects panel if restoring
    self:UpdatePendingReconnectsPanel()
end

-- Update host's player list display
function Craps:UpdateHostPlayerList()
    local CS = BJ.CrapsState
    local CM = BJ.CrapsMultiplayer
    
    if not CM.isHost then return end
    
    -- Create player list panel if needed
    if not self.playerListPanel then
        self:CreatePlayerListPanel()
    end
    
    -- Initialize playerColors if needed
    self.playerColors = self.playerColors or {}
    
    -- Get sorted player names for consistent color assignment
    local sortedNames = {}
    for name, player in pairs(CS.players) do
        if not player.isHost then
            table.insert(sortedNames, name)
        end
    end
    table.sort(sortedNames)
    
    -- Assign colors based on sorted order
    local players = {}
    for i, name in ipairs(sortedNames) do
        local player = CS.players[name]
        local color = PLAYER_COLORS[i] or PLAYER_COLORS[1]
        self.playerColors[name] = color
        table.insert(players, {name = name, balance = player.balance, color = color})
    end
    
    -- Update rows
    for i, row in ipairs(self.playerListRows or {}) do
        local p = players[i]
        if p then
            local colorHex = "ffffff"
            if p.color then
                colorHex = string.format("%02x%02x%02x", p.color.r * 255, p.color.g * 255, p.color.b * 255)
            end
            row.nameText:SetText("|cff" .. colorHex .. p.name .. "|r")
            row.balanceText:SetText(BJ:FormatGoldColored(p.balance))
            row:Show()
        else
            row:Hide()
        end
    end
    
    if #players > 0 then
        -- Resize panel to fit players (title + rows)
        local panelHeight = 25 + (#players * 20)
        self.playerListPanel:SetHeight(panelHeight)
        self.playerListPanel:Show()
    else
        self.playerListPanel:Hide()
    end
end

-- Create player list panel for host (movable)
function Craps:CreatePlayerListPanel()
    if self.playerListPanel then return end
    
    local panel = CreateFrame("Frame", "CrapsPlayerListPanel", self.frame, "BackdropTemplate")
    panel:SetSize(180, 80)  -- Start small, will expand as needed
    -- Position centered below info panel
    panel:SetPoint("TOP", self.infoPanel, "BOTTOM", 0, -5)
    panel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    panel:SetBackdropColor(0, 0, 0, 0.8)
    panel:SetBackdropBorderColor(0.5, 0.4, 0.2, 1)
    panel:Hide()
    
    -- NOT movable - locked position
    panel:SetMovable(false)
    panel:EnableMouse(true)
    
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOP", 0, -5)
    title:SetText("|cffffd700Player Balances|r")
    panel.title = title
    
    self.playerListRows = {}
    for i = 1, 12 do  -- Support more players
        local row = CreateFrame("Frame", nil, panel)
        row:SetSize(170, 18)
        row:SetPoint("TOP", panel, "TOP", 0, -18 - (i-1) * 20)
        row:Hide()
        
        local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        nameText:SetPoint("LEFT", 5, 0)
        nameText:SetWidth(100)
        nameText:SetJustifyH("LEFT")
        row.nameText = nameText
        
        local balanceText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        balanceText:SetPoint("RIGHT", -5, 0)
        row.balanceText = balanceText
        
        self.playerListRows[i] = row
    end
    
    self.playerListPanel = panel
end

-- Create Roll Call panel for host (shows who's locked in)
function Craps:CreateRollCallPanel()
    if self.rollCallPanel then return end
    
    local panel = CreateFrame("Frame", "CrapsRollCallPanel", self.frame, "BackdropTemplate")
    panel:SetSize(200, 80)  -- Start small, will expand
    -- Position to the RIGHT of the info panel (player balances)
    panel:SetPoint("TOPLEFT", self.infoPanel, "TOPRIGHT", 5, 0)
    panel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    panel:SetBackdropColor(0, 0, 0, 0.9)
    panel:SetBackdropBorderColor(0.4, 0.6, 0.4, 1)
    panel:Hide()
    
    -- NOT movable - locked to parent window
    panel:SetMovable(false)
    panel:EnableMouse(true)
    
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -8)
    title:SetText("|cffffd700Roll Call|r")
    panel.title = title
    
    self.rollCallRows = {}
    for i = 1, 12 do  -- Support up to 12 players
        local row = CreateFrame("Frame", nil, panel)
        row:SetSize(190, 18)
        row:SetPoint("TOP", panel, "TOP", 0, -25 - (i-1) * 18)
        row:Hide()
        
        -- Check icon (texture instead of text)
        local checkIcon = row:CreateTexture(nil, "OVERLAY")
        checkIcon:SetSize(14, 14)
        checkIcon:SetPoint("LEFT", 5, 0)
        checkIcon:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\unchecked")
        row.checkIcon = checkIcon
        
        -- Shooter icon (dice - hidden by default)
        local shooterIcon = row:CreateTexture(nil, "OVERLAY")
        shooterIcon:SetSize(14, 14)
        shooterIcon:SetPoint("LEFT", 20, 0)
        shooterIcon:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\dice_icon")
        shooterIcon:Hide()
        row.shooterIcon = shooterIcon
        
        local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        nameText:SetPoint("LEFT", 36, 0)
        nameText:SetWidth(100)
        nameText:SetJustifyH("LEFT")
        row.nameText = nameText
        
        local statusText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        statusText:SetPoint("RIGHT", -5, 0)
        row.statusText = statusText
        
        self.rollCallRows[i] = row
    end
    
    self.rollCallPanel = panel
end

-- Update Roll Call panel
function Craps:UpdateRollCall()
    local CS = BJ.CrapsState
    local CM = BJ.CrapsMultiplayer
    
    -- Show roll call during betting for everyone (not just host)
    if CS.phase ~= CS.PHASE.BETTING and CS.phase ~= CS.PHASE.COME_OUT and CS.phase ~= CS.PHASE.POINT then
        if self.rollCallPanel then self.rollCallPanel:Hide() end
        return
    end
    
    if not self.rollCallPanel then
        self:CreateRollCallPanel()
    end
    
    -- Gather non-host players and assign consistent colors
    local players = {}
    self.playerColors = self.playerColors or {}
    
    -- Sort players by name first to get consistent order
    local sortedNames = {}
    for name, player in pairs(CS.players) do
        if not player.isHost then
            table.insert(sortedNames, name)
        end
    end
    table.sort(sortedNames)
    
    -- Assign colors based on sorted order
    for i, name in ipairs(sortedNames) do
        local player = CS.players[name]
        local color = PLAYER_COLORS[i] or PLAYER_COLORS[1]
        self.playerColors[name] = color
        
        table.insert(players, {
            name = name,
            lockedIn = player.lockedIn or false,
            totalBets = CS:GetPlayerTotalBets(name),
            balance = player.balance or 0,
            color = color,
            isShooter = (CS.shooterName == name),
        })
    end
    
    -- Update panel title based on who is viewing
    if self.rollCallPanel.title then
        if CM.isHost then
            self.rollCallPanel.title:SetText("|cffffd700Roll Call|r")
        else
            self.rollCallPanel.title:SetText("|cffffd700Players|r")
        end
    end
    
    -- Update rows
    for i, row in ipairs(self.rollCallRows) do
        local p = players[i]
        if p then
            local colorHex = string.format("%02x%02x%02x", p.color.r * 255, p.color.g * 255, p.color.b * 255)
            
            -- Show shooter icon if this player is the shooter
            if p.isShooter then
                row.shooterIcon:Show()
            else
                row.shooterIcon:Hide()
            end
            
            -- Show lock-in status to everyone
            if p.lockedIn then
                row.checkIcon:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\checked")
                row.checkIcon:SetVertexColor(0, 1, 0, 1)  -- Green tint
            else
                row.checkIcon:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\unchecked")
                row.checkIcon:SetVertexColor(0.5, 0.5, 0.5, 1)  -- Gray tint
            end
            row.checkIcon:Show()
            
            row.nameText:SetText("|cff" .. colorHex .. p.name .. "|r")
            
            if CM.isHost then
                -- Host sees total bets
                row.statusText:SetText(BJ:FormatGoldColored(p.totalBets))
            else
                -- Players see balances
                row.statusText:SetText(BJ:FormatGoldColored(p.balance))
            end
            row:Show()
        else
            row:Hide()
        end
    end
    
    -- Resize panel based on player count (title + rows)
    local panelHeight = 30 + (#players * 18)
    self.rollCallPanel:SetHeight(panelHeight)
    
    -- Show panel for both host and players whenever there are players at the table
    if #players > 0 and CS.phase ~= CS.PHASE.IDLE then
        self.rollCallPanel:Show()
    else
        self.rollCallPanel:Hide()
    end
end

-- Create All Players Bets panel (visible to all)
function Craps:CreateAllBetsPanel()
    if self.allBetsPanel then return end
    
    local panel = CreateFrame("Frame", "CrapsAllBetsPanel", self.frame, "BackdropTemplate")
    panel:SetSize(250, 200)
    panel:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 10, -35)
    panel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    panel:SetBackdropColor(0, 0, 0, 0.85)
    panel:SetBackdropBorderColor(0.4, 0.4, 0.5, 1)
    panel:Hide()
    
    -- Make movable
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    panel:SetClampedToScreen(true)
    
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -5)
    title:SetText("|cffffd700Active Bets|r")
    
    -- Scrollable content area
    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetSize(220, 170)
    scrollFrame:SetPoint("TOP", title, "BOTTOM", -10, -5)
    
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(220, 400)
    scrollFrame:SetScrollChild(content)
    
    self.allBetsContent = content
    self.allBetsPanel = panel
end

-- Update All Players Bets display
function Craps:UpdateAllBetsDisplay()
    local CS = BJ.CrapsState
    local CM = BJ.CrapsMultiplayer
    
    if CS.phase == CS.PHASE.IDLE then
        if self.allBetsPanel then self.allBetsPanel:Hide() end
        return
    end
    
    if not self.allBetsPanel then
        self:CreateAllBetsPanel()
    end
    
    -- Clear existing content
    if self.allBetsContent then
        for _, child in ipairs({self.allBetsContent:GetChildren()}) do
            child:Hide()
            child:SetParent(nil)
        end
    end
    
    -- Gather all players with bets
    local yOffset = 0
    local colorIdx = 1
    local playerColors = {}
    
    -- First pass: assign colors to players
    local sortedPlayers = {}
    for name, player in pairs(CS.players) do
        if not player.isHost then
            table.insert(sortedPlayers, name)
        end
    end
    table.sort(sortedPlayers)
    
    for _, name in ipairs(sortedPlayers) do
        playerColors[name] = PLAYER_COLORS[colorIdx] or PLAYER_COLORS[1]
        colorIdx = (colorIdx % #PLAYER_COLORS) + 1
    end
    
    -- Second pass: display bets for each player
    for _, playerName in ipairs(sortedPlayers) do
        local player = CS.players[playerName]
        local color = playerColors[playerName]
        local colorHex = string.format("%02x%02x%02x", color.r * 255, color.g * 255, color.b * 255)
        
        local totalBets = CS:GetPlayerTotalBets(playerName)
        if totalBets > 0 then
            -- Player name header
            local header = self.allBetsContent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            header:SetPoint("TOPLEFT", 5, -yOffset)
            local lockedIcon = player.lockedIn and " |cff00ff00✓|r" or ""
            header:SetText("|cff" .. colorHex .. playerName .. lockedIcon .. "|r")
            yOffset = yOffset + 14
            
            -- List their bets
            local bets = player.bets
            local betLines = {}
            
            if bets.passLine > 0 then table.insert(betLines, "Pass: " .. bets.passLine) end
            if bets.passLineOdds > 0 then table.insert(betLines, "Pass Odds: " .. bets.passLineOdds) end
            if bets.dontPass > 0 then table.insert(betLines, "Don't Pass: " .. bets.dontPass) end
            if bets.dontPassOdds > 0 then table.insert(betLines, "DP Odds: " .. bets.dontPassOdds) end
            if bets.come > 0 then table.insert(betLines, "Come: " .. bets.come) end
            if bets.dontCome > 0 then table.insert(betLines, "Don't Come: " .. bets.dontCome) end
            if bets.field > 0 then table.insert(betLines, "Field: " .. bets.field) end
            if bets.any7 > 0 then table.insert(betLines, "Any 7: " .. bets.any7) end
            if bets.anyCraps > 0 then table.insert(betLines, "Any Craps: " .. bets.anyCraps) end
            
            -- Place bets
            for point, amount in pairs(bets.place or {}) do
                if amount > 0 then table.insert(betLines, "Place " .. point .. ": " .. amount) end
            end
            
            -- Hardways
            if bets.hard4 > 0 then table.insert(betLines, "Hard 4: " .. bets.hard4) end
            if bets.hard6 > 0 then table.insert(betLines, "Hard 6: " .. bets.hard6) end
            if bets.hard8 > 0 then table.insert(betLines, "Hard 8: " .. bets.hard8) end
            if bets.hard10 > 0 then table.insert(betLines, "Hard 10: " .. bets.hard10) end
            
            for _, line in ipairs(betLines) do
                local betText = self.allBetsContent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                betText:SetPoint("TOPLEFT", 15, -yOffset)
                betText:SetText("|cff" .. colorHex .. line .. "|r")
                yOffset = yOffset + 12
            end
            
            yOffset = yOffset + 5  -- Gap between players
        end
    end
    
    if yOffset > 0 then
        self.allBetsPanel:Show()
        self.allBetsContent:SetHeight(math.max(yOffset, 170))
    else
        self.allBetsPanel:Hide()
    end
end

-- Trixie animations
function Craps:SetTrixieWait()
    local idx = math.random(1, 31)
    self.trixieTexture:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\dealer\\trix_wait" .. idx)
end

function Craps:SetTrixieCheer()
    local idx = math.random(1, 9)
    self.trixieTexture:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\dealer\\trix_win" .. idx)
    
    C_Timer.After(2.0, function()
        self:SetTrixieWait()
    end)
end

function Craps:SetTrixieLose()
    local idx = math.random(1, 12)
    self.trixieTexture:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\dealer\\trix_lose" .. idx)
    
    C_Timer.After(2.0, function()
        self:SetTrixieWait()
    end)
end

-- OnUpdate handler
function Craps:OnUpdate(elapsed)
    -- Could add betting timer display here
end

-- Show/Hide
function Craps:Show()
    if not self.frame then
        self:Initialize()
    end
    
    -- Show pending version warning if any
    if BJ.ShowPendingVersionWarning then
        BJ:ShowPendingVersionWarning()
    end
    
    -- Hide other game windows
    if UI.mainFrame and UI.mainFrame:IsShown() then
        UI:Hide()
    end
    if UI.Poker and UI.Poker.mainFrame and UI.Poker.mainFrame:IsShown() then
        UI.Poker:Hide()
    end
    if UI.HiLo and UI.HiLo.container and UI.HiLo.container:IsShown() then
        UI.HiLo:Hide()
    end
    if UI.Lobby and UI.Lobby.frame and UI.Lobby.frame:IsShown() then
        UI.Lobby.frame:Hide()
    end
    
    -- Apply saved window scale
    if UI.Lobby and UI.Lobby.ApplyWindowScale then
        UI.Lobby:ApplyWindowScale()
    end
    
    self:UpdateDisplay()
    self.container:Show()
end

function Craps:Hide()
    if self.container then
        self.container:Hide()
    end
    -- Hide all sub-windows/panels
    if self.buyInPanel then self.buyInPanel:Hide() end
    if self.hostSettingsPanel then self.hostSettingsPanel:Hide() end
    if self.pendingJoinsPanel then self.pendingJoinsPanel:Hide() end
    if self.shooterPanel then self.shooterPanel:Hide() end
    if self.playerListPanel then self.playerListPanel:Hide() end
    if self.rollCallPanel then self.rollCallPanel:Hide() end
    if self.allBetsPanel then self.allBetsPanel:Hide() end
    if self.receiptPopup then self.receiptPopup:Hide() end
end

-- Close craps when another game window or lobby opens
function Craps:OnOtherWindowOpened()
    self:Hide()
end

function Craps:Toggle()
    if self.container and self.container:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

-- Create Buy-In Panel for joining
function Craps:CreateBuyInPanel()
    if self.buyInPanel then return end
    
    local panel = CreateFrame("Frame", "CrapsBuyInPanel", UIParent, "BackdropTemplate")
    panel:SetSize(280, 160)
    panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    panel:SetFrameStrata("DIALOG")
    panel:SetFrameLevel(200)
    panel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    panel:SetBackdropColor(0.1, 0.1, 0.15, 0.98)
    panel:SetBackdropBorderColor(0.6, 0.5, 0.2, 1)
    panel:EnableMouse(true)
    panel:Hide()
    
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -15)
    title:SetText("|cffffd700Buy-In|r")
    
    local label = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOP", title, "BOTTOM", 0, -15)
    label:SetText("|cffffffffEnter chip amount (1-100,000):|r")
    
    -- Edit box for buy-in amount
    local editBox = CreateFrame("EditBox", nil, panel, "BackdropTemplate")
    editBox:SetSize(150, 30)
    editBox:SetPoint("TOP", label, "BOTTOM", 0, -10)
    editBox:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    editBox:SetBackdropColor(0.05, 0.05, 0.08, 1)
    editBox:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    editBox:SetFontObject("GameFontHighlight")
    editBox:SetJustifyH("CENTER")
    editBox:SetAutoFocus(false)
    editBox:SetNumeric(true)
    editBox:SetMaxLetters(6)
    editBox:SetText("1000")
    editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    editBox:SetScript("OnEnterPressed", function(self) 
        self:ClearFocus()
        Craps:SubmitBuyIn()
    end)
    editBox:SetScript("OnEditFocusLost", function(self)
        local val = tonumber(self:GetText()) or 1
        val = math.max(1, math.min(100000, math.floor(val)))
        self:SetText(tostring(val))
    end)
    self.buyInEditBox = editBox
    
    -- Gold label
    local goldLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    goldLabel:SetPoint("LEFT", editBox, "RIGHT", 5, 0)
    goldLabel:SetText("|cffffd700g|r")
    
    -- Button row
    local buttonY = 20
    
    -- Submit button
    local submitBtn = CreateFrame("Button", nil, panel, "BackdropTemplate")
    submitBtn:SetSize(100, 30)
    submitBtn:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 30, buttonY)
    submitBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    submitBtn:SetBackdropColor(0.15, 0.35, 0.15, 1)
    submitBtn:SetBackdropBorderColor(0.3, 0.7, 0.3, 1)
    local submitText = submitBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    submitText:SetPoint("CENTER")
    submitText:SetText("|cffffffffJoin|r")
    submitBtn:SetScript("OnClick", function() Craps:SubmitBuyIn() end)
    submitBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.2, 0.45, 0.2, 1) end)
    submitBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.15, 0.35, 0.15, 1) end)
    
    -- Cancel button
    local cancelBtn = CreateFrame("Button", nil, panel, "BackdropTemplate")
    cancelBtn:SetSize(100, 30)
    cancelBtn:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -30, buttonY)
    cancelBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    cancelBtn:SetBackdropColor(0.35, 0.15, 0.15, 1)
    cancelBtn:SetBackdropBorderColor(0.7, 0.3, 0.3, 1)
    local cancelText = cancelBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cancelText:SetPoint("CENTER")
    cancelText:SetText("|cffffffffCancel|r")
    cancelBtn:SetScript("OnClick", function() panel:Hide() end)
    cancelBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.45, 0.2, 0.2, 1) end)
    cancelBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.35, 0.15, 0.15, 1) end)
    
    self.buyInPanel = panel
end

function Craps:ShowBuyInPanel()
    if not self.buyInPanel then
        self:CreateBuyInPanel()
    end
    self.buyInEditBox:SetText("1000")
    self.buyInPanel:Show()
end

function Craps:SubmitBuyIn()
    local amount = tonumber(self.buyInEditBox:GetText()) or 0
    if amount < 1 or amount > 100000 then
        BJ:Print("|cffff4444Buy-in must be between 1 and 100,000.|r")
        return
    end
    
    self.buyInPanel:Hide()
    BJ.CrapsMultiplayer:RequestJoin(amount)
end

-- Create Host Settings Panel with entry boxes
function Craps:CreateHostSettingsPanel()
    if self.hostSettingsPanel then return end
    
    local panel = CreateFrame("Frame", "CrapsHostSettingsPanel", UIParent, "BackdropTemplate")
    panel:SetSize(300, 220)
    panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    panel:SetFrameStrata("DIALOG")
    panel:SetFrameLevel(200)
    panel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    panel:SetBackdropColor(0.1, 0.1, 0.15, 0.98)
    panel:SetBackdropBorderColor(0.6, 0.5, 0.2, 1)
    panel:EnableMouse(true)
    panel:Hide()
    
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("|cffffd700Host Craps Table|r")
    
    local yOffset = -45
    
    -- Helper function to create validated input box
    local function CreateInputRow(labelText, defaultVal, yPos)
        local label = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("TOPLEFT", 20, yPos)
        label:SetText("|cffffffff" .. labelText .. "|r")
        
        local inputBox = CreateFrame("EditBox", nil, panel, "BackdropTemplate")
        inputBox:SetSize(100, 28)
        inputBox:SetPoint("TOPLEFT", 150, yPos + 5)
        inputBox:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        inputBox:SetBackdropColor(0.05, 0.05, 0.08, 1)
        inputBox:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
        inputBox:SetFontObject("GameFontHighlight")
        inputBox:SetJustifyH("CENTER")
        inputBox:SetAutoFocus(false)
        inputBox:SetNumeric(true)
        inputBox:SetMaxLetters(6)
        inputBox:SetText(tostring(defaultVal))
        inputBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        inputBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        inputBox:SetScript("OnEditFocusLost", function(self)
            local val = tonumber(self:GetText()) or 1
            val = math.max(1, math.min(100000, math.floor(val)))
            self:SetText(tostring(val))
        end)
        
        local goldLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        goldLabel:SetPoint("LEFT", inputBox, "RIGHT", 5, 0)
        goldLabel:SetText("|cffffd700g|r")
        
        return inputBox
    end
    
    -- Table Bank (default 1000)
    self.hostCapInput = CreateInputRow("Table Bank:", 1000, yOffset)
    yOffset = yOffset - 40
    
    -- Min Bet (default 1)
    self.hostMinBetInput = CreateInputRow("Min Bet:", 1, yOffset)
    yOffset = yOffset - 40
    
    -- Max Bet (default 10)
    self.hostMaxBetInput = CreateInputRow("Max Bet:", 10, yOffset)
    
    -- Button row
    local buttonY = 20
    
    -- Host button
    local hostBtn = CreateFrame("Button", nil, panel, "BackdropTemplate")
    hostBtn:SetSize(110, 35)
    hostBtn:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 30, buttonY)
    hostBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    hostBtn:SetBackdropColor(0.15, 0.35, 0.15, 1)
    hostBtn:SetBackdropBorderColor(0.3, 0.7, 0.3, 1)
    local hostText = hostBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    hostText:SetPoint("CENTER")
    hostText:SetText("|cffffffffOpen Table|r")
    hostBtn:SetScript("OnClick", function() Craps:SubmitHostSettings() end)
    hostBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.2, 0.45, 0.2, 1) end)
    hostBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.15, 0.35, 0.15, 1) end)
    
    -- Cancel button
    local cancelBtn = CreateFrame("Button", nil, panel, "BackdropTemplate")
    cancelBtn:SetSize(110, 35)
    cancelBtn:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -30, buttonY)
    cancelBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    cancelBtn:SetBackdropColor(0.35, 0.15, 0.15, 1)
    cancelBtn:SetBackdropBorderColor(0.7, 0.3, 0.3, 1)
    local cancelText = cancelBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cancelText:SetPoint("CENTER")
    cancelText:SetText("|cffffffffCancel|r")
    cancelBtn:SetScript("OnClick", function() panel:Hide() end)
    cancelBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.45, 0.2, 0.2, 1) end)
    cancelBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.35, 0.15, 0.15, 1) end)
    
    self.hostSettingsPanel = panel
end

function Craps:ShowHostSettings()
    local CS = BJ.CrapsState
    
    -- Check for restorable session first
    if CS:HasRestorableSession() then
        self:ShowRestoreSessionPopup()
        return
    end
    
    if not self.hostSettingsPanel then
        self:CreateHostSettingsPanel()
    end
    -- Reset to defaults
    self.hostCapInput:SetText("1000")
    self.hostMinBetInput:SetText("1")
    self.hostMaxBetInput:SetText("10")
    self.hostSettingsPanel:Show()
end

-- Show popup to restore or abandon previous session
function Craps:ShowRestoreSessionPopup()
    local CS = BJ.CrapsState
    local info = CS:GetRestorableSessionInfo()
    
    if not info then return end
    
    -- Create popup if needed
    if not self.restorePopup then
        local popup = CreateFrame("Frame", "CrapsRestorePopup", UIParent, "BackdropTemplate")
        popup:SetSize(320, 200)
        popup:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
        popup:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 2,
        })
        popup:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
        popup:SetBackdropBorderColor(0.8, 0.5, 0.1, 1)
        popup:SetFrameStrata("DIALOG")
        
        -- Title
        local title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", 0, -15)
        title:SetText("|cffffd700Previous Session Found|r")
        
        -- Info text
        local infoText = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        infoText:SetPoint("TOP", 0, -45)
        infoText:SetWidth(280)
        popup.infoText = infoText
        
        -- Restore button
        local restoreBtn = CreateFrame("Button", nil, popup, "BackdropTemplate")
        restoreBtn:SetSize(120, 35)
        restoreBtn:SetPoint("BOTTOMLEFT", 30, 20)
        restoreBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        restoreBtn:SetBackdropColor(0.2, 0.5, 0.2, 1)
        restoreBtn:SetBackdropBorderColor(0.3, 0.7, 0.3, 1)
        local restoreText = restoreBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        restoreText:SetPoint("CENTER")
        restoreText:SetText("|cffffffffRestore|r")
        restoreBtn:SetScript("OnClick", function()
            popup:Hide()
            Craps:RestoreSession()
        end)
        restoreBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.3, 0.6, 0.3, 1) end)
        restoreBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.2, 0.5, 0.2, 1) end)
        
        -- New Game button
        local newBtn = CreateFrame("Button", nil, popup, "BackdropTemplate")
        newBtn:SetSize(120, 35)
        newBtn:SetPoint("BOTTOMRIGHT", -30, 20)
        newBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        newBtn:SetBackdropColor(0.5, 0.3, 0.2, 1)
        newBtn:SetBackdropBorderColor(0.7, 0.4, 0.3, 1)
        local newText = newBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        newText:SetPoint("CENTER")
        newText:SetText("|cffffffffNew Game|r")
        newBtn:SetScript("OnClick", function()
            popup:Hide()
            CS:ClearSavedSession()
            Craps:ShowHostSettingsForced()
        end)
        newBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.6, 0.4, 0.3, 1) end)
        newBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.5, 0.3, 0.2, 1) end)
        
        self.restorePopup = popup
    end
    
    -- Update info text
    local ageMin = math.floor(info.age / 60)
    local infoStr = string.format(
        "|cffffffffPlayers:|r %d\n|cffffffffTotal owed:|r %s\n|cffffffffAge:|r %d minutes ago\n|cffffffffPoint:|r %s",
        info.playerCount,
        BJ:FormatGoldColored(info.totalBalance),
        ageMin,
        info.point and tostring(info.point) or "None"
    )
    self.restorePopup.infoText:SetText(infoStr)
    
    self.restorePopup:Show()
end

-- Show host settings (forced, bypassing restore check)
function Craps:ShowHostSettingsForced()
    if not self.hostSettingsPanel then
        self:CreateHostSettingsPanel()
    end
    -- Reset to defaults
    self.hostCapInput:SetText("1000")
    self.hostMinBetInput:SetText("1")
    self.hostMaxBetInput:SetText("10")
    self.hostSettingsPanel:Show()
end

-- Restore the previous session
function Craps:RestoreSession()
    local CS = BJ.CrapsState
    local CM = BJ.CrapsMultiplayer
    
    local success, msg = CS:RestoreHostSession()
    
    if success then
        -- Set up multiplayer state
        CM.isHost = true
        CM.currentHost = UnitName("player")
        CM.tableOpen = true
        
        -- Broadcast table open with all settings
        CM:Send(CM.MSG.TABLE_OPEN, CS.minBet, CS.maxBet, CS.maxOdds, CS.bettingTimer, CS.tableCap, BJ.version)
        
        -- Notify each player they can reconnect with their saved balance
        local pending = CS:GetPendingReconnects()
        for _, p in ipairs(pending) do
            CM:Send(CM.MSG.SESSION_RECONNECT, p.name, p.balance)
        end
        
        BJ:Print("|cff00ff00Session restored!|r Waiting for players to reconnect...")
        BJ:Print("|cffffd700Players can click 'Join Table' to reconnect with their saved balance.|r")
        
        -- Show pending reconnects
        self:ShowPendingReconnectsPanel()
    else
        BJ:Print("|cffff4444Failed to restore session:|r " .. (msg or "Unknown error"))
    end
    
    self:UpdateDisplay()
end

-- Show panel listing players who need to reconnect
function Craps:ShowPendingReconnectsPanel()
    local CS = BJ.CrapsState
    local pending = CS:GetPendingReconnects()
    
    if #pending == 0 then
        BJ:Print("|cffffd700All players accounted for.|r")
        return
    end
    
    -- Create or update pending reconnects panel
    if not self.pendingReconnectsPanel then
        local panel = CreateFrame("Frame", "CrapsPendingReconnects", self.frame, "BackdropTemplate")
        panel:SetSize(250, 230)
        panel:SetPoint("RIGHT", self.frame, "LEFT", -10, 0)
        panel:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 2,
        })
        panel:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
        panel:SetBackdropBorderColor(0.7, 0.5, 0.2, 1)
        
        local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOP", 0, -10)
        title:SetText("|cffffd700Waiting for Reconnects|r")
        panel.title = title
        
        local instructText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        instructText:SetPoint("TOPLEFT", 15, -30)
        instructText:SetWidth(220)
        instructText:SetJustifyH("LEFT")
        instructText:SetText("|cff88ff88Players click 'Join Table' to reconnect|r")
        
        local listText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        listText:SetPoint("TOPLEFT", 15, -50)
        listText:SetWidth(220)
        listText:SetJustifyH("LEFT")
        panel.listText = listText
        
        -- Finalize button
        local finalizeBtn = CreateFrame("Button", nil, panel, "BackdropTemplate")
        finalizeBtn:SetSize(100, 30)
        finalizeBtn:SetPoint("BOTTOM", 0, 15)
        finalizeBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        finalizeBtn:SetBackdropColor(0.3, 0.4, 0.5, 1)
        finalizeBtn:SetBackdropBorderColor(0.4, 0.5, 0.6, 1)
        local btnText = finalizeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        btnText:SetPoint("CENTER")
        btnText:SetText("|cffffffffContinue Without|r")
        finalizeBtn:SetScript("OnClick", function()
            CS:FinalizeRestoration()
            panel:Hide()
            -- Start the betting phase
            local CM = BJ.CrapsMultiplayer
            if CS.shooterName and CM.isHost then
                CM:Send(CM.MSG.BETTING_PHASE, CS.bettingTimer or 30)
                BJ:Print("|cffffd700Betting phase started! " .. (CS.bettingTimer or 30) .. " seconds to place bets.|r")
            end
            Craps:UpdateDisplay()
            BJ:Print("|cff00ff00Session finalized.|r")
        end)
        finalizeBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.4, 0.5, 0.6, 1) end)
        finalizeBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.3, 0.4, 0.5, 1) end)
        
        self.pendingReconnectsPanel = panel
    end
    
    -- Update list
    local lines = {}
    for _, p in ipairs(pending) do
        table.insert(lines, "|cffffffff" .. p.name .. "|r - " .. BJ:FormatGoldColored(p.balance))
    end
    self.pendingReconnectsPanel.listText:SetText(table.concat(lines, "\n"))
    
    self.pendingReconnectsPanel:Show()
end

-- Update pending reconnects panel (call from UpdateDisplay)
function Craps:UpdatePendingReconnectsPanel()
    local CS = BJ.CrapsState
    
    if not CS.isRestoring or not self.pendingReconnectsPanel then
        if self.pendingReconnectsPanel then
            self.pendingReconnectsPanel:Hide()
        end
        return
    end
    
    local pending = CS:GetPendingReconnects()
    if #pending == 0 then
        self.pendingReconnectsPanel:Hide()
        return
    end
    
    local lines = {}
    for _, p in ipairs(pending) do
        table.insert(lines, "|cffffffff" .. p.name .. "|r - " .. BJ:FormatGoldColored(p.balance))
    end
    self.pendingReconnectsPanel.listText:SetText(table.concat(lines, "\n"))
    self.pendingReconnectsPanel:Show()
end

function Craps:SubmitHostSettings()
    local tableCap = tonumber(self.hostCapInput:GetText()) or 1000
    local minBet = tonumber(self.hostMinBetInput:GetText()) or 1
    local maxBet = tonumber(self.hostMaxBetInput:GetText()) or 10
    
    -- Validate
    tableCap = math.max(1, math.min(100000, math.floor(tableCap)))
    minBet = math.max(1, math.min(100000, math.floor(minBet)))
    maxBet = math.max(1, math.min(100000, math.floor(maxBet)))
    
    -- Ensure min <= max
    if minBet > maxBet then
        BJ:Print("|cffff4444Min bet cannot be greater than max bet.|r")
        return
    end
    
    -- Ensure max bet doesn't exceed table cap
    if maxBet > tableCap then
        BJ:Print("|cffff4444Max bet cannot exceed table bank.|r")
        return
    end
    
    self.hostSettingsPanel:Hide()
    
    BJ.CrapsMultiplayer:HostTable({
        minBet = minBet,
        maxBet = maxBet,
        maxOdds = 3,
        tableCap = tableCap,
        bettingTimer = 30,
    })
    
    self:UpdateDisplay()
end

-- Create Pending Joins Panel (for host)
function Craps:CreatePendingJoinsPanel()
    if self.pendingJoinsPanel then return end
    
    local panel = CreateFrame("Frame", nil, self.frame, "BackdropTemplate")
    panel:SetSize(280, 200)  -- Wider to fit ALLOW/DENY buttons
    -- Center in game window
    panel:SetPoint("CENTER", self.frame, "CENTER", 0, 0)
    panel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    panel:SetBackdropColor(0.1, 0.1, 0.12, 1)  -- 100% opaque
    panel:SetBackdropBorderColor(0.7, 0.5, 0.2, 1)
    panel:SetFrameStrata("DIALOG")  -- Above all other windows
    panel:Hide()
    
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -8)
    title:SetText("|cffffd700Pending Requests|r")
    
    -- Scrollable list of pending joins
    self.pendingJoinRows = {}
    for i = 1, 4 do
        local row = CreateFrame("Frame", nil, panel, "BackdropTemplate")
        row:SetSize(260, 35)  -- Wider to fit buttons
        row:SetPoint("TOP", panel, "TOP", 0, -25 - (i-1) * 40)
        row:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        row:SetBackdropColor(0.15, 0.15, 0.18, 1)
        row:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        row:Hide()
        
        local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        nameText:SetPoint("LEFT", 5, 5)
        nameText:SetWidth(130)
        nameText:SetJustifyH("LEFT")
        row.nameText = nameText
        
        local amountText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        amountText:SetPoint("LEFT", 5, -8)
        row.amountText = amountText
        
        -- Approve button with ALLOW label
        local approveBtn = CreateFrame("Button", nil, row, "BackdropTemplate")
        approveBtn:SetSize(55, 22)
        approveBtn:SetPoint("RIGHT", row, "RIGHT", -60, 0)
        approveBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        approveBtn:SetBackdropColor(0.15, 0.4, 0.15, 1)
        approveBtn:SetBackdropBorderColor(0.3, 0.6, 0.3, 1)
        local appText = approveBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        appText:SetPoint("CENTER")
        appText:SetText("|cff00ff00ALLOW|r")
        approveBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.2, 0.5, 0.2, 1) end)
        approveBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.15, 0.4, 0.15, 1) end)
        row.approveBtn = approveBtn
        
        -- Deny button with DENY label
        local denyBtn = CreateFrame("Button", nil, row, "BackdropTemplate")
        denyBtn:SetSize(50, 22)
        denyBtn:SetPoint("RIGHT", row, "RIGHT", -5, 0)
        denyBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        denyBtn:SetBackdropColor(0.4, 0.15, 0.15, 1)
        denyBtn:SetBackdropBorderColor(0.6, 0.3, 0.3, 1)
        local denyText = denyBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        denyText:SetPoint("CENTER")
        denyText:SetText("|cffff4444DENY|r")
        denyBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.5, 0.2, 0.2, 1) end)
        denyBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.4, 0.15, 0.15, 1) end)
        row.denyBtn = denyBtn
        
        self.pendingJoinRows[i] = row
    end
    
    self.pendingJoinsPanel = panel
end

function Craps:UpdatePendingJoins()
    local CS = BJ.CrapsState
    local CM = BJ.CrapsMultiplayer
    local myName = UnitName("player")
    
    -- Only show for host
    if not CS:IsHost(myName) then
        if self.pendingJoinsPanel then
            self.pendingJoinsPanel:Hide()
        end
        return
    end
    
    if not self.pendingJoinsPanel then
        self:CreatePendingJoinsPanel()
    end
    
    local requests = CS:GetPendingJoins()
    
    if #requests == 0 then
        self.pendingJoinsPanel:Hide()
        return
    end
    
    self.pendingJoinsPanel:Show()
    
    for i, row in ipairs(self.pendingJoinRows) do
        local req = requests[i]
        if req then
            row.nameText:SetText("|cffffffff" .. req.name .. "|r")
            row.amountText:SetText(BJ:FormatGoldColored(req.buyIn))
            row.approveBtn:SetScript("OnClick", function()
                CM:ApproveJoin(req.name)
            end)
            row.denyBtn:SetScript("OnClick", function()
                CM:DenyJoin(req.name)
            end)
            row:Show()
        else
            row:Hide()
        end
    end
end

-- Update player list (for host ready check display)
function Craps:UpdatePlayerList()
    -- This will be implemented in Phase 3 for ready check system
    self:UpdatePendingJoins()
end

-- Show receipt popup window
function Craps:ShowReceiptPopup(playerName, startBalance, endBalance, netChange)
    -- Create popup if needed
    if not self.receiptPopup then
        local popup = CreateFrame("Frame", "CrapsReceiptPopup", UIParent, "BackdropTemplate")
        popup:SetSize(250, 220)  -- Slightly taller for new line
        popup:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
        popup:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 2,
        })
        popup:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
        popup:SetBackdropBorderColor(0.8, 0.6, 0.2, 1)
        popup:SetFrameStrata("DIALOG")
        
        -- Make movable
        popup:SetMovable(true)
        popup:EnableMouse(true)
        popup:RegisterForDrag("LeftButton")
        popup:SetScript("OnDragStart", popup.StartMoving)
        popup:SetScript("OnDragStop", popup.StopMovingOrSizing)
        popup:SetClampedToScreen(true)
        
        -- Title bar
        local titleBar = CreateFrame("Frame", nil, popup, "BackdropTemplate")
        titleBar:SetSize(246, 30)
        titleBar:SetPoint("TOP", 0, -2)
        titleBar:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
        })
        titleBar:SetBackdropColor(0.6, 0.4, 0.1, 1)
        
        local title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("CENTER")
        title:SetText("|cffffd700CASINO RECEIPT|r")
        
        -- Close button
        local closeBtn = CreateFrame("Button", nil, popup, "BackdropTemplate")
        closeBtn:SetSize(24, 24)
        closeBtn:SetPoint("TOPRIGHT", -5, -5)
        closeBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        closeBtn:SetBackdropColor(0.5, 0.2, 0.2, 1)
        closeBtn:SetBackdropBorderColor(0.7, 0.3, 0.3, 1)
        local closeText = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        closeText:SetPoint("CENTER")
        closeText:SetText("|cffffffffX|r")
        closeBtn:SetScript("OnClick", function() popup:Hide() end)
        closeBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.7, 0.3, 0.3, 1) end)
        closeBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.5, 0.2, 0.2, 1) end)
        
        -- Content
        local playerText = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        playerText:SetPoint("TOPLEFT", 20, -45)
        popup.playerText = playerText
        
        local startText = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        startText:SetPoint("TOPLEFT", 20, -70)
        popup.startText = startText
        
        local endText = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        endText:SetPoint("TOPLEFT", 20, -95)
        popup.endText = endText
        
        local netText = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        netText:SetPoint("TOPLEFT", 20, -120)
        popup.netText = netText
        
        -- Decorative line
        local line = popup:CreateTexture(nil, "ARTWORK")
        line:SetSize(210, 2)
        line:SetPoint("TOP", 0, -145)
        line:SetColorTexture(0.6, 0.5, 0.2, 1)
        
        -- Casino owes line (final payout)
        local owesText = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        owesText:SetPoint("TOP", 0, -165)
        popup.owesText = owesText
        
        self.receiptPopup = popup
    end
    
    -- Update content
    local popup = self.receiptPopup
    popup.playerText:SetText("|cffffffffPlayer: |cffffd700" .. playerName .. "|r")
    popup.startText:SetText("|cffffffffBuy-in: " .. BJ:FormatGoldColored(startBalance))
    popup.endText:SetText("|cffffffffFinal Balance: " .. BJ:FormatGoldColored(endBalance))
    
    local netAbs = math.abs(netChange)
    if netChange >= 0 then
        popup.netText:SetText("|cff00ff00Net Win: +" .. BJ:FormatGold(netAbs) .. "|r")
    else
        popup.netText:SetText("|cffff4444Net Loss: -" .. BJ:FormatGold(netAbs) .. "|r")
    end
    
    -- Casino owes line - the amount to pay out
    popup.owesText:SetText("|cffffd700Casino Owes: " .. BJ:FormatGoldColored(endBalance) .. "|r")
    
    popup:Show()
end
