--[[
    Chairface's Casino - LeaderboardUI.lua
    UI for session leaderboards and all-time leaderboard window
]]

local BJ = ChairfacesCasino
BJ.LeaderboardUI = {}
local LBUI = BJ.LeaderboardUI
local LB = BJ.Leaderboard

-- UI Constants
local SESSION_WIDTH = 220
local SESSION_HEIGHT = 280
local ALLTIME_WIDTH = 620
local ALLTIME_HEIGHT = 500

-- Colors
local COLORS = {
    gold = { 1, 0.84, 0 },
    green = { 0.3, 1, 0.3 },
    red = { 1, 0.4, 0.4 },
    white = { 1, 1, 1 },
    gray = { 0.6, 0.6, 0.6 },
    darkGray = { 0.3, 0.3, 0.3 },
    headerBg = { 0.15, 0.12, 0.08 },
    headerBorder = { 0.8, 0.65, 0.2 },
    panelBg = { 0.08, 0.08, 0.1, 0.95 },
    panelBorder = { 0.5, 0.4, 0.2 },
    rowHighlight = { 0.3, 0.25, 0.1, 0.5 },
    selfRow = { 0.4, 0.35, 0.1, 0.7 },
}

-- Game type display info (now with texture paths for icons)
local GAME_INFO = {
    blackjack = { 
        name = "Blackjack", 
        iconTexture = "Interface\\AddOns\\Chairfaces Casino\\Textures\\cards\\A_spades",
        color = { 0.2, 0.8, 0.3 } 
    },
    poker = { 
        name = "5 Card Stud", 
        iconTexture = "Interface\\AddOns\\Chairfaces Casino\\Textures\\cards\\A_diamonds",
        color = { 0.9, 0.3, 0.3 } 
    },
    hilo = { 
        name = "High-Lo", 
        iconTexture = "Interface\\AddOns\\Chairfaces Casino\\Textures\\icon",  -- Minimap dice icon
        color = { 0.3, 0.6, 0.9 } 
    },
}

-- Arrow texture for self-highlight
local ARROW_TEXTURE = "Interface\\AddOns\\Chairfaces Casino\\Textures\\arrow_right"

--[[
    ============================================
    UTILITY FUNCTIONS
    ============================================
]]

-- Format gold with color
local function formatGold(amount)
    if amount > 0 then
        return "|cff00ff88+" .. amount .. "g|r"
    elseif amount < 0 then
        return "|cffff6666" .. amount .. "g|r"
    else
        return "|cffaaaaaa0g|r"
    end
end

-- Format time ago
local function formatTimeAgo(timestamp)
    if not timestamp or timestamp == 0 then
        return "Never"
    end
    
    local diff = time() - timestamp
    if diff < 60 then
        return "Just now"
    elseif diff < 3600 then
        return math.floor(diff / 60) .. "m ago"
    elseif diff < 86400 then
        return math.floor(diff / 3600) .. "h ago"
    elseif diff < 604800 then
        return math.floor(diff / 86400) .. "d ago"
    else
        return math.floor(diff / 604800) .. "w ago"
    end
end

-- Get short name (remove realm)
local function shortName(fullName)
    return fullName:match("^([^-]+)") or fullName
end

-- Check if name is self
local function isSelf(fullName)
    local myName = UnitName("player")
    local myRealm = GetRealmName()
    local myFullName = myName .. "-" .. myRealm
    return fullName == myFullName or fullName == myName
end

--[[
    ============================================
    SESSION LEADERBOARD WINDOW
    ============================================
]]

function LBUI:CreateSessionFrame(gameType)
    local info = GAME_INFO[gameType]
    if not info then return nil end
    
    local frame = CreateFrame("Frame", "CasinoSession_" .. gameType, UIParent, "BackdropTemplate")
    frame:SetSize(SESSION_WIDTH, SESSION_HEIGHT)
    frame:SetPoint("RIGHT", UIParent, "RIGHT", -20, 0)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- Save position
        local point, _, relPoint, x, y = self:GetPoint()
        if not ChairfacesCasinoSaved then ChairfacesCasinoSaved = {} end
        ChairfacesCasinoSaved["sessionPos_" .. gameType] = { point, relPoint, x, y }
    end)
    frame:SetClampedToScreen(true)
    frame:SetFrameStrata("DIALOG")  -- Higher than HIGH so it's above game windows
    frame:SetFrameLevel(100)  -- Extra high level within strata
    frame.gameType = gameType
    
    -- Load saved position
    if ChairfacesCasinoSaved and ChairfacesCasinoSaved["sessionPos_" .. gameType] then
        local pos = ChairfacesCasinoSaved["sessionPos_" .. gameType]
        frame:ClearAllPoints()
        frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    end
    
    -- Main backdrop
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    frame:SetBackdropColor(unpack(COLORS.panelBg))
    frame:SetBackdropBorderColor(unpack(COLORS.panelBorder))
    
    -- Header with gradient look
    local header = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    header:SetSize(SESSION_WIDTH - 4, 32)
    header:SetPoint("TOP", 0, -2)
    header:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    header:SetBackdropColor(unpack(COLORS.headerBg))
    header:SetBackdropBorderColor(unpack(COLORS.headerBorder))
    
    -- Header gradient overlay
    local headerGlow = header:CreateTexture(nil, "ARTWORK")
    headerGlow:SetTexture("Interface\\Buttons\\WHITE8x8")
    headerGlow:SetPoint("TOPLEFT", 1, -1)
    headerGlow:SetPoint("TOPRIGHT", -1, -1)
    headerGlow:SetHeight(16)
    headerGlow:SetGradient("VERTICAL", CreateColor(0.4, 0.3, 0.1, 0.3), CreateColor(0.4, 0.3, 0.1, 0))
    
    -- Title with texture icon
    local titleIcon = header:CreateTexture(nil, "ARTWORK")
    titleIcon:SetSize(18, 18)
    titleIcon:SetPoint("LEFT", 8, 0)
    titleIcon:SetTexture(info.iconTexture)
    
    local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", titleIcon, "RIGHT", 5, 0)
    title:SetText("|cffffd700PARTY SESSION|r")
    title:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, header)
    closeBtn:SetSize(18, 18)
    closeBtn:SetPoint("RIGHT", -4, 0)
    closeBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    closeBtn:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
    closeBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
    closeBtn:SetScript("OnClick", function() frame:Hide() end)
    
    -- Column headers
    local colHeader = CreateFrame("Frame", nil, frame)
    colHeader:SetSize(SESSION_WIDTH - 20, 18)
    colHeader:SetPoint("TOP", header, "BOTTOM", 0, -5)
    
    local rankCol = colHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rankCol:SetPoint("LEFT", 5, 0)
    rankCol:SetText("|cffaaaaaa#|r")
    
    local nameCol = colHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameCol:SetPoint("LEFT", 25, 0)
    nameCol:SetText("|cffaaaaaaPlayer|r")
    
    local netCol = colHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    netCol:SetPoint("RIGHT", -5, 0)
    netCol:SetText("|cffaaaaaaNet|r")
    
    -- Divider line
    local divider = frame:CreateTexture(nil, "ARTWORK")
    divider:SetTexture("Interface\\Buttons\\WHITE8x8")
    divider:SetSize(SESSION_WIDTH - 20, 1)
    divider:SetPoint("TOP", colHeader, "BOTTOM", 0, -2)
    divider:SetColorTexture(0.4, 0.35, 0.2, 0.8)
    
    -- Scroll frame for entries
    local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetSize(SESSION_WIDTH - 30, SESSION_HEIGHT - 100)
    scrollFrame:SetPoint("TOP", divider, "BOTTOM", -5, -5)
    
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(SESSION_WIDTH - 30, 1)  -- Height will expand
    scrollFrame:SetScrollChild(scrollChild)
    
    frame.scrollChild = scrollChild
    frame.rows = {}
    
    -- Footer with session stats
    local footer = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    footer:SetSize(SESSION_WIDTH - 4, 32)
    footer:SetPoint("BOTTOM", 0, 2)
    footer:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
    })
    footer:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
    
    local footerText = footer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    footerText:SetPoint("CENTER")
    footerText:SetText("|cff888888Hands: 0  |  Total: 0g|r")
    frame.footerText = footerText
    
    frame:Hide()
    return frame
end

function LBUI:UpdateSessionFrame(gameType)
    local frame = LB.sessionFrames[gameType]
    if not frame then return end
    
    local leaderboard = LB:GetSessionLeaderboard(gameType)
    local scrollChild = frame.scrollChild
    
    -- Clear existing rows
    for _, row in ipairs(frame.rows) do
        row:Hide()
    end
    
    -- Create/update rows
    local yOffset = 0
    local totalHands = 0
    local totalNet = 0
    
    for i, entry in ipairs(leaderboard) do
        local row = frame.rows[i]
        if not row then
            row = CreateFrame("Frame", nil, scrollChild, "BackdropTemplate")
            row:SetSize(SESSION_WIDTH - 35, 22)
            row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
            
            -- Arrow icon for self-highlight (hidden by default)
            row.arrow = row:CreateTexture(nil, "ARTWORK")
            row.arrow:SetSize(12, 12)
            row.arrow:SetPoint("LEFT", 2, 0)
            row.arrow:SetTexture(ARROW_TEXTURE)
            row.arrow:Hide()
            
            row.rank = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.rank:SetPoint("LEFT", 16, 0)
            
            row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.name:SetPoint("LEFT", 30, 0)
            row.name:SetWidth(100)
            row.name:SetJustifyH("LEFT")
            
            row.net = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.net:SetPoint("RIGHT", -5, 0)
            
            frame.rows[i] = row
        end
        
        row:SetPoint("TOPLEFT", 0, -yOffset)
        
        -- Highlight self
        if isSelf(entry.name) then
            row:SetBackdropColor(unpack(COLORS.selfRow))
            row.rank:SetText("|cffffd700" .. i .. "|r")
            row.arrow:Show()
        else
            row:SetBackdropColor(0, 0, 0, 0)
            row.rank:SetText("|cffaaaaaa" .. i .. "|r")
            row.arrow:Hide()
        end
        
        row.name:SetText(shortName(entry.name))
        row.net:SetText(formatGold(entry.net))
        
        row:Show()
        
        yOffset = yOffset + 24
        totalHands = totalHands + entry.hands
        totalNet = totalNet + math.abs(entry.net)
    end
    
    scrollChild:SetHeight(math.max(yOffset, 1))
    
    -- Update footer
    frame.footerText:SetText("|cff888888Hands: " .. totalHands .. "  |  Pot: " .. totalNet .. "g|r")
end

--[[
    ============================================
    ALL-TIME LEADERBOARD WINDOW
    ============================================
]]

function LBUI:CreateAllTimeFrame()
    local frame = CreateFrame("Frame", "CasinoAllTimeLeaderboard", UIParent, "BackdropTemplate")
    frame:SetSize(ALLTIME_WIDTH, ALLTIME_HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        if not ChairfacesCasinoSaved then ChairfacesCasinoSaved = {} end
        ChairfacesCasinoSaved.allTimePos = { point, relPoint, x, y }
    end)
    frame:SetClampedToScreen(true)
    frame:SetFrameStrata("DIALOG")
    
    -- Load saved position
    if ChairfacesCasinoSaved and ChairfacesCasinoSaved.allTimePos then
        local pos = ChairfacesCasinoSaved.allTimePos
        frame:ClearAllPoints()
        frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    end
    
    -- Dark backdrop
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 3,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    frame:SetBackdropColor(0.05, 0.05, 0.08, 0.98)
    frame:SetBackdropBorderColor(0.7, 0.55, 0.2, 1)
    
    -- Ornate header
    local header = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    header:SetSize(ALLTIME_WIDTH - 6, 45)
    header:SetPoint("TOP", 0, -3)
    header:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    header:SetBackdropColor(0.12, 0.1, 0.05, 1)
    header:SetBackdropBorderColor(0.8, 0.65, 0.2, 1)
    
    -- Header gradient glow
    local headerGlow = header:CreateTexture(nil, "ARTWORK")
    headerGlow:SetTexture("Interface\\Buttons\\WHITE8x8")
    headerGlow:SetPoint("TOPLEFT", 2, -2)
    headerGlow:SetPoint("TOPRIGHT", -2, -2)
    headerGlow:SetHeight(22)
    headerGlow:SetGradient("VERTICAL", CreateColor(0.6, 0.45, 0.1, 0.4), CreateColor(0.6, 0.45, 0.1, 0))
    
    -- Trophy icon and title
    local trophyFrame = CreateFrame("Frame", nil, header)
    trophyFrame:SetSize(32, 32)
    trophyFrame:SetPoint("LEFT", 10, 0)
    
    local trophyTex = trophyFrame:CreateTexture(nil, "ARTWORK")
    trophyTex:SetAllPoints()
    trophyTex:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\leaderboard_alltime")
    trophyTex:SetTexCoord(0, 1, 1, 0)  -- Flip vertically
    
    local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", trophyFrame, "RIGHT", 8, 2)
    title:SetText("|cffffd700CHAIRFACE'S CASINO|r")
    title:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE")
    
    local subtitle = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subtitle:SetPoint("LEFT", trophyFrame, "RIGHT", 8, -12)
    subtitle:SetText("|cffccaa66ALL-TIME LEADERBOARD|r")
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, header, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", 0, 0)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)
    
    -- Tab bar
    local tabBar = CreateFrame("Frame", nil, frame)
    tabBar:SetSize(ALLTIME_WIDTH - 20, 30)
    tabBar:SetPoint("TOP", header, "BOTTOM", 0, -5)
    frame.tabBar = tabBar
    frame.tabs = {}
    
    local tabWidth = (ALLTIME_WIDTH - 30) / 3
    for i, gameType in ipairs({ "blackjack", "poker", "hilo" }) do
        local info = GAME_INFO[gameType]
        local tab = CreateFrame("Button", nil, tabBar, "BackdropTemplate")
        tab:SetSize(tabWidth, 28)
        tab:SetPoint("LEFT", (i - 1) * (tabWidth + 5), 0)
        tab:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 2,
        })
        tab.gameType = gameType
        
        -- Create icon texture
        local tabIcon = tab:CreateTexture(nil, "ARTWORK")
        tabIcon:SetSize(20, 20)
        tabIcon:SetPoint("LEFT", 8, 0)
        tabIcon:SetTexture(info.iconTexture)
        tab.icon = tabIcon
        
        local tabText = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        tabText:SetPoint("LEFT", tabIcon, "RIGHT", 4, 0)
        tabText:SetText(info.name:upper())
        tab.text = tabText
        
        tab:SetScript("OnClick", function()
            LBUI:SelectTab(gameType)
        end)
        
        tab:SetScript("OnEnter", function(self)
            if frame.selectedTab ~= gameType then
                self:SetBackdropColor(0.25, 0.2, 0.1, 1)
            end
        end)
        
        tab:SetScript("OnLeave", function(self)
            if frame.selectedTab ~= gameType then
                self:SetBackdropColor(0.15, 0.12, 0.08, 1)
            end
        end)
        
        frame.tabs[gameType] = tab
    end
    
    -- Column headers - positions must match row content positions
    local colHeader = CreateFrame("Frame", nil, frame)
    colHeader:SetSize(ALLTIME_WIDTH - 30, 20)
    colHeader:SetPoint("TOP", tabBar, "BOTTOM", 0, -10)
    
    -- Header positions match row positions exactly
    -- Reduced gap before Net, doubled gaps after Net and W/L
    local headers = {
        { text = "#", xPos = 18, width = 20, align = "CENTER" },
        { text = "Player", xPos = 40, width = 120, align = "LEFT" },
        { text = "Net", xPos = 155, width = 75, align = "RIGHT" },
        { text = "W/L", xPos = 245, width = 55, align = "CENTER", key = "wlHeader" },
        { text = "Games", xPos = 315, width = 45, align = "CENTER" },
        { text = "Last Sync", xPos = 365, width = 85, align = "RIGHT" },
    }
    
    for _, h in ipairs(headers) do
        local col = colHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        col:SetPoint("LEFT", h.xPos, 0)
        col:SetWidth(h.width)
        col:SetJustifyH(h.align)
        col:SetText("|cffccaa66" .. h.text .. "|r")
        if h.key then
            frame[h.key] = col
        end
    end
    
    -- Divider
    local divider = frame:CreateTexture(nil, "ARTWORK")
    divider:SetTexture("Interface\\Buttons\\WHITE8x8")
    divider:SetSize(ALLTIME_WIDTH - 30, 1)
    divider:SetPoint("TOP", colHeader, "BOTTOM", 0, -3)
    divider:SetColorTexture(0.5, 0.4, 0.2, 0.8)
    
    -- Scroll frame for entries
    local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetSize(ALLTIME_WIDTH - 40, 200)
    scrollFrame:SetPoint("TOP", divider, "BOTTOM", -5, -5)
    
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(ALLTIME_WIDTH - 40, 1)
    scrollFrame:SetScrollChild(scrollChild)
    
    frame.scrollChild = scrollChild
    frame.rows = {}
    
    -- My stats panel
    local myStatsPanel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    myStatsPanel:SetSize(ALLTIME_WIDTH - 20, 80)
    myStatsPanel:SetPoint("BOTTOM", 0, 55)
    myStatsPanel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    myStatsPanel:SetBackdropColor(0.1, 0.1, 0.12, 0.9)
    myStatsPanel:SetBackdropBorderColor(0.4, 0.35, 0.2, 1)
    
    local myStatsTitle = myStatsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    myStatsTitle:SetPoint("TOPLEFT", 10, -8)
    myStatsTitle:SetText("|cffffd700YOUR STATS|r")
    frame.myStatsTitle = myStatsTitle
    
    local myStatsLine1 = myStatsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    myStatsLine1:SetPoint("TOPLEFT", 10, -28)
    frame.myStatsLine1 = myStatsLine1
    
    local myStatsLine2 = myStatsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    myStatsLine2:SetPoint("TOPLEFT", 10, -45)
    frame.myStatsLine2 = myStatsLine2
    
    -- Footer buttons
    local footerBar = CreateFrame("Frame", nil, frame)
    footerBar:SetSize(ALLTIME_WIDTH - 20, 35)
    footerBar:SetPoint("BOTTOM", 0, 10)
    
    -- Sync button
    local syncBtn = CreateFrame("Button", nil, footerBar, "BackdropTemplate")
    syncBtn:SetSize(100, 28)
    syncBtn:SetPoint("LEFT", 0, 0)
    syncBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    syncBtn:SetBackdropColor(0.2, 0.35, 0.2, 1)
    syncBtn:SetBackdropBorderColor(0.4, 0.7, 0.4, 1)
    
    local syncText = syncBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    syncText:SetPoint("CENTER")
    syncText:SetText("|cff88ff88Sync Now|r")
    
    syncBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.3, 0.5, 0.3, 1)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Sync Leaderboard", 0.5, 1, 0.5)
        GameTooltip:AddLine("Request stats from group members", 1, 1, 1)
        GameTooltip:Show()
    end)
    syncBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.2, 0.35, 0.2, 1)
        GameTooltip:Hide()
    end)
    syncBtn:SetScript("OnClick", function()
        LB:RequestGroupSync()
    end)
    
    -- Player count
    local playerCount = footerBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    playerCount:SetPoint("CENTER", 0, 0)
    playerCount:SetText("|cff888888Players: 0|r")
    frame.playerCount = playerCount
    
    -- Reset button
    local resetBtn = CreateFrame("Button", nil, footerBar, "BackdropTemplate")
    resetBtn:SetSize(100, 28)
    resetBtn:SetPoint("RIGHT", 0, 0)
    resetBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    resetBtn:SetBackdropColor(0.35, 0.15, 0.15, 1)
    resetBtn:SetBackdropBorderColor(0.7, 0.3, 0.3, 1)
    
    local resetText = resetBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    resetText:SetPoint("CENTER")
    resetText:SetText("|cffff8888Reset My Data|r")
    
    resetBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.5, 0.2, 0.2, 1)
    end)
    resetBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.35, 0.15, 0.15, 1)
    end)
    resetBtn:SetScript("OnClick", function()
        StaticPopupDialogs["CASINO_RESET_LEADERBOARD"] = {
            text = "Reset your leaderboard data for |cffffd700" .. GAME_INFO[frame.selectedTab].name .. "|r?\n\nThis cannot be undone!",
            button1 = "Reset",
            button2 = "Cancel",
            OnAccept = function()
                LB:ResetMyData(frame.selectedTab)
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
        }
        StaticPopup_Show("CASINO_RESET_LEADERBOARD")
    end)
    
    frame:Hide()
    frame.selectedTab = "blackjack"
    return frame
end

function LBUI:SelectTab(gameType)
    local frame = LB.allTimeFrame
    if not frame then return end
    
    frame.selectedTab = gameType
    
    -- Update tab appearance
    for gt, tab in pairs(frame.tabs) do
        if gt == gameType then
            tab:SetBackdropColor(0.35, 0.28, 0.1, 1)
            tab:SetBackdropBorderColor(1, 0.8, 0.3, 1)
            tab.text:SetText("|cffffffff" .. GAME_INFO[gt].name:upper() .. "|r")
            if tab.icon then tab.icon:SetVertexColor(1, 1, 1, 1) end
        else
            tab:SetBackdropColor(0.15, 0.12, 0.08, 1)
            tab:SetBackdropBorderColor(0.4, 0.35, 0.2, 1)
            tab.text:SetText("|cffaaaaaa" .. GAME_INFO[gt].name:upper() .. "|r")
            if tab.icon then tab.icon:SetVertexColor(0.6, 0.6, 0.6, 1) end
        end
    end
    
    -- Update content
    self:UpdateAllTimeFrame()
end

function LBUI:UpdateAllTimeFrame()
    local frame = LB.allTimeFrame
    if not frame then return end
    
    local gameType = frame.selectedTab or "blackjack"
    local leaderboard = LB:GetAllTimeLeaderboard(gameType)
    local scrollChild = frame.scrollChild
    
    -- Update W/L header based on game type
    if frame.wlHeader then
        if gameType == "blackjack" then
            frame.wlHeader:SetText("|cffccaa66W/L/P|r")
        else
            frame.wlHeader:SetText("|cffccaa66W/L|r")
        end
    end
    
    -- Clear existing rows
    for _, row in ipairs(frame.rows) do
        row:Hide()
    end
    
    -- Create/update rows
    local yOffset = 0
    for i, entry in ipairs(leaderboard) do
        local row = frame.rows[i]
        if not row then
            row = CreateFrame("Frame", nil, scrollChild, "BackdropTemplate")
            row:SetSize(ALLTIME_WIDTH - 50, 24)
            row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
            
            -- Arrow icon for self-highlight (hidden by default)
            row.arrow = row:CreateTexture(nil, "ARTWORK")
            row.arrow:SetSize(14, 14)
            row.arrow:SetPoint("LEFT", 2, 0)
            row.arrow:SetTexture(ARROW_TEXTURE)
            row.arrow:Hide()
            
            row.rank = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.rank:SetPoint("LEFT", 18, 0)
            row.rank:SetWidth(20)
            row.rank:SetJustifyH("CENTER")
            
            row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.name:SetPoint("LEFT", 40, 0)
            row.name:SetWidth(120)
            row.name:SetJustifyH("LEFT")
            
            row.net = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.net:SetPoint("LEFT", 155, 0)
            row.net:SetWidth(75)
            row.net:SetJustifyH("RIGHT")
            
            row.wl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.wl:SetPoint("LEFT", 245, 0)
            row.wl:SetWidth(55)
            row.wl:SetJustifyH("CENTER")
            
            row.games = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.games:SetPoint("LEFT", 315, 0)
            row.games:SetWidth(45)
            row.games:SetJustifyH("CENTER")
            
            row.sync = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.sync:SetPoint("LEFT", 365, 0)
            row.sync:SetWidth(85)
            row.sync:SetJustifyH("RIGHT")
            
            frame.rows[i] = row
        end
        
        row:SetPoint("TOPLEFT", 0, -yOffset)
        
        -- Highlight self
        if isSelf(entry.name) then
            row:SetBackdropColor(unpack(COLORS.selfRow))
            row.rank:SetText("|cffffd700" .. i .. "|r")
            row.arrow:Show()
        else
            if i % 2 == 0 then
                row:SetBackdropColor(0.1, 0.1, 0.1, 0.3)
            else
                row:SetBackdropColor(0, 0, 0, 0)
            end
            row.rank:SetText("|cffaaaaaa" .. i .. "|r")
            row.arrow:Hide()
        end
        
        row.name:SetText(shortName(entry.name))
        row.net:SetText(formatGold(entry.net))
        
        -- W/L display based on game type
        if gameType == "blackjack" then
            -- Show W/L/P for blackjack
            local pushes = entry.pushes or 0
            if entry.wins > 0 or entry.losses > 0 or pushes > 0 then
                row.wl:SetText("|cff88ff88" .. entry.wins .. "|r/|cffff8888" .. entry.losses .. "|r/|cffffcc88" .. pushes .. "|r")
            else
                row.wl:SetText("|cff666666-|r")
            end
        else
            -- Show W/L for poker/hilo
            if entry.wins > 0 or entry.losses > 0 then
                row.wl:SetText("|cff88ff88" .. entry.wins .. "|r/|cffff8888" .. entry.losses .. "|r")
            else
                row.wl:SetText("|cff666666-|r")
            end
        end
        
        row.games:SetText("|cffcccccc" .. entry.games .. "|r")
        row.sync:SetText("|cff888888" .. formatTimeAgo(entry.lastSync) .. "|r")
        
        row:Show()
        yOffset = yOffset + 26
    end
    
    scrollChild:SetHeight(math.max(yOffset, 1))
    
    -- Update my stats - different display per game type
    local myStats = LB:GetMyStats(gameType)
    if myStats then
        frame.myStatsTitle:SetText("|cffffd700YOUR " .. GAME_INFO[gameType].name:upper() .. " STATS|r")
        
        if gameType == "blackjack" then
            -- Blackjack shows Push
            frame.myStatsLine1:SetText("|cffccccccGames:|r " .. myStats.games .. 
                "  |cffccccccWon:|r |cff88ff88" .. myStats.wins .. "|r" ..
                "  |cffccccccLost:|r |cffff8888" .. myStats.losses .. "|r" ..
                "  |cffccccccPush:|r |cffffcc88" .. myStats.pushes .. "|r")
        else
            -- Poker and HiLo don't show Push
            frame.myStatsLine1:SetText("|cffccccccGames:|r " .. myStats.games .. 
                "  |cffccccccWon:|r |cff88ff88" .. myStats.wins .. "|r" ..
                "  |cffccccccLost:|r |cffff8888" .. myStats.losses .. "|r")
        end
        
        frame.myStatsLine2:SetText("|cffccccccNet:|r " .. formatGold(myStats.net) ..
            "  |cffccccccBest Win:|r |cff88ff88+" .. myStats.bestWin .. "g|r" ..
            "  |cffccccccWorst Loss:|r |cffff8888" .. myStats.worstLoss .. "g|r")
    else
        frame.myStatsTitle:SetText("|cffffd700YOUR " .. GAME_INFO[gameType].name:upper() .. " STATS|r")
        frame.myStatsLine1:SetText("|cff888888No games played yet.|r")
        frame.myStatsLine2:SetText("")
    end
    
    -- Update player count
    frame.playerCount:SetText("|cff888888Players in DB: " .. LB:GetTotalPlayers() .. "|r")
end

--[[
    ============================================
    PUBLIC API
    ============================================
]]

-- Show session leaderboard for a game type
function LBUI:ShowSession(gameType)
    if not LB.sessionFrames[gameType] then
        LB.sessionFrames[gameType] = self:CreateSessionFrame(gameType)
    end
    
    local frame = LB.sessionFrames[gameType]
    if frame then
        self:UpdateSessionFrame(gameType)
        frame:Show()
        -- Request party session data from other party members
        LB:RequestPartySessionData()
    end
end

-- Hide session leaderboard
function LBUI:HideSession(gameType)
    if LB.sessionFrames[gameType] then
        LB.sessionFrames[gameType]:Hide()
    end
end

-- Toggle session leaderboard
function LBUI:ToggleSession(gameType)
    if not LB.sessionFrames[gameType] then
        LB.sessionFrames[gameType] = self:CreateSessionFrame(gameType)
    end
    
    local frame = LB.sessionFrames[gameType]
    if frame:IsShown() then
        frame:Hide()
    else
        self:UpdateSessionFrame(gameType)
        frame:Show()
        -- Request party session data from other party members
        LB:RequestPartySessionData()
    end
end

-- Show all-time leaderboard
function LBUI:ShowAllTime()
    if not LB.allTimeFrame then
        LB.allTimeFrame = self:CreateAllTimeFrame()
    end
    
    self:SelectTab(LB.allTimeFrame.selectedTab or "blackjack")
    LB.allTimeFrame:Show()
end

-- Hide all-time leaderboard
function LBUI:HideAllTime()
    if LB.allTimeFrame then
        LB.allTimeFrame:Hide()
    end
end

-- Toggle all-time leaderboard
function LBUI:ToggleAllTime(gameType)
    if not LB.allTimeFrame then
        LB.allTimeFrame = self:CreateAllTimeFrame()
    end
    
    if LB.allTimeFrame:IsShown() then
        LB.allTimeFrame:Hide()
    else
        -- Use provided gameType, or fall back to selected/default
        local tabToShow = gameType or LB.allTimeFrame.selectedTab or "blackjack"
        self:SelectTab(tabToShow)
        LB.allTimeFrame:Show()
    end
end

-- Check if session window is shown
function LBUI:IsSessionShown(gameType)
    return LB.sessionFrames[gameType] and LB.sessionFrames[gameType]:IsShown()
end

-- Check if all-time window is shown
function LBUI:IsAllTimeShown()
    return LB.allTimeFrame and LB.allTimeFrame:IsShown()
end
