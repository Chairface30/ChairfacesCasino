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
local ALLTIME_WIDTH = 820  -- widened to landscape to host the tavern background
local ALLTIME_HEIGHT = 606  -- grows with the game-tab rows (see TAB_LIST)

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
        iconTexture = "Interface\\AddOns\\Chairfaces Casino\\Textures\\cards\\5_spades",
        color = { 0.9, 0.3, 0.3 }
    },
    holdem = {
        name = "Texas Hold'em",
        iconTexture = "Interface\\AddOns\\Chairfaces Casino\\Textures\\cards\\K_spades",
        color = { 0.85, 0.65, 0.2 }
    },
    hilo = {
        name = "High-Lo",
        iconTexture = "Interface\\AddOns\\Chairfaces Casino\\Textures\\icon",  -- Minimap dice icon
        color = { 0.3, 0.6, 0.9 }
    },
    deathroll = {
        name = "Death Roll",
        iconTexture = "Interface\\AddOns\\Chairfaces Casino\\Textures\\icon",
        color = { 0.9, 0.4, 0.3 }
    },
    bingo = {
        name = "Bingo",
        iconTexture = "Interface\\AddOns\\Chairfaces Casino\\Textures\\Widgets\\bingo_icon",
        color = { 0.7, 0.4, 0.9 }
    },
    roulette = {
        name = "Roulette",
        iconTexture = "Interface\\AddOns\\Chairfaces Casino\\Textures\\Widgets\\roulette_icon",
        color = { 0.85, 0.25, 0.35 }
    },
    liarsdice = {
        name = "Liar's Dice",
        iconTexture = "Interface\\AddOns\\Chairfaces Casino\\Textures\\icon",
        color = { 0.6, 0.8, 0.4 }
    },
    crash = {
        name = "Crash",
        -- same hand-drawn zeppelin sprite the lobby button uses (transparent).
        -- It's a 10-frame vertical sheet, so show just frame 0 (top tenth).
        iconTexture = "Interface\\AddOns\\Chairfaces Casino\\Textures\\Crash\\zeppelin",
        texCoord = { 0, 1, 0, 0.1 },
        color = { 0.95, 0.5, 0.2 }
    },
    chairscup = {
        name = "Chair's Cup",
        -- custom transparent icon, same as the lobby's Chair's Cup button
        iconTexture = "Interface\\AddOns\\Chairfaces Casino\\Textures\\Widgets\\chairscup_icon",
        color = { 0.8, 0.7, 0.3 }
    },
}

-- Style a tab/title icon from its GAME_INFO entry: a `mask = true` entry
-- (Chair's Cup) gets a circular alpha mask so its black square corners read
-- transparent; a `texCoord` entry (Crash's zeppelin sprite sheet) picks one
-- frame. SetMask is guarded so clients without it just keep the plain icon.
local ICON_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local function maskIcon(tex, info)
    if not (tex and info) then return end
    if info.mask and tex.SetMask then
        tex:SetMask(ICON_MASK)
    elseif info.texCoord then
        tex:SetTexCoord(unpack(info.texCoord))
    end
end

-- Arrow texture for self-highlight
local ARROW_TEXTURE = "Interface\\AddOns\\Chairfaces Casino\\Textures\\Widgets\\arrow_right"

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
    local myName = BJ:MyName()
    local myRealm = GetRealmName()
    local myFullName = myName .. "-" .. myRealm
    return fullName == myFullName or fullName == myName
end

--[[
    ============================================
    SESSION LEADERBOARD WINDOW
    ============================================
]]

--[[
    ============================================
    ALL-TIME LEADERBOARD WINDOW
    ============================================
]]

function LBUI:CreateAllTimeFrame()
    -- Shared casino window (UI/Chrome.lua) on the tavern art; pops over
    -- whatever is open, so closing never reopens the lobby
    local frame = BJ.UI.Chrome:CreateWindow({
        name = "CasinoAllTimeLeaderboard",
        title = "All-Time Leaderboard",
        width = ALLTIME_WIDTH, height = ALLTIME_HEIGHT,
        strata = "DIALOG",
        art = "tavern", scrim = 0.62,
        noLobby = true,
    })
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        if not ChairfacesCasinoSaved then ChairfacesCasinoSaved = {} end
        ChairfacesCasinoSaved.allTimePos = { point, relPoint, x, y }
    end)
    if ChairfacesCasinoSaved and ChairfacesCasinoSaved.allTimePos then
        local pos = ChairfacesCasinoSaved.allTimePos
        frame:ClearAllPoints()
        frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    end
    local header = frame.titleBar

    -- Tab bar: one tab per tracked game, three across, as many rows as needed
    local TAB_LIST = { "blackjack", "poker", "holdem", "hilo", "deathroll",
                       "bingo", "roulette", "liarsdice", "crash", "chairscup" }
    local TABS_PER_ROW = 3
    local numTabRows = math.ceil(#TAB_LIST / TABS_PER_ROW)

    local tabBar = CreateFrame("Frame", nil, frame)
    tabBar:SetSize(ALLTIME_WIDTH - 20, numTabRows * 33)
    tabBar:SetPoint("TOP", header, "BOTTOM", 0, -5)
    frame.tabBar = tabBar
    frame.tabs = {}

    local tabWidth = (ALLTIME_WIDTH - 40) / TABS_PER_ROW
    for i, gameType in ipairs(TAB_LIST) do
        local info = GAME_INFO[gameType]
        local row = math.ceil(i / TABS_PER_ROW)
        local col = (i - 1) % TABS_PER_ROW
        local tab = CreateFrame("Button", nil, tabBar, "BackdropTemplate")
        tab:SetSize(tabWidth, 28)
        tab:SetPoint("TOPLEFT", col * (tabWidth + 5), -(row - 1) * 33)
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
        maskIcon(tabIcon, info)
        tab.icon = tabIcon
        
        local tabText = tab:CreateFontString(nil, "OVERLAY", "CCFontNormal")
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
        local col = colHeader:CreateFontString(nil, "OVERLAY", "CCFontSmall")
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
    
    local myStatsTitle = myStatsPanel:CreateFontString(nil, "OVERLAY", "CCFontNormal")
    myStatsTitle:SetPoint("TOPLEFT", 10, -8)
    myStatsTitle:SetText("|cffffd700YOUR STATS|r")
    frame.myStatsTitle = myStatsTitle
    
    local myStatsLine1 = myStatsPanel:CreateFontString(nil, "OVERLAY", "CCFontSmall")
    myStatsLine1:SetPoint("TOPLEFT", 10, -28)
    frame.myStatsLine1 = myStatsLine1
    
    local myStatsLine2 = myStatsPanel:CreateFontString(nil, "OVERLAY", "CCFontSmall")
    myStatsLine2:SetPoint("TOPLEFT", 10, -45)
    frame.myStatsLine2 = myStatsLine2
    
    -- Footer buttons
    local footerBar = CreateFrame("Frame", nil, frame)
    footerBar:SetSize(ALLTIME_WIDTH - 20, 35)
    footerBar:SetPoint("BOTTOM", 0, 10)
    
    -- Sync button
    local syncBtn = BJ.Theme:Button(footerBar, "", 100, 28, "go", nil)
    syncBtn:SetPoint("LEFT", 0, 0)
    
    local syncText = syncBtn.text
    syncText:SetText("Sync Now")
    
    syncBtn:SetScript("OnEnter", function(self)

        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Sync Leaderboard", 0.5, 1, 0.5)
        GameTooltip:AddLine("Request stats from group members", 1, 1, 1)
        GameTooltip:Show()
    end)
    syncBtn:SetScript("OnLeave", function(self)
        BJ.Theme:StyleButton(self)
        GameTooltip:Hide()
    end)
    syncBtn:SetScript("OnClick", function()
        LB:RequestGroupSync()
    end)
    
    -- Player count
    local playerCount = footerBar:CreateFontString(nil, "OVERLAY", "CCFontSmall")
    playerCount:SetPoint("CENTER", 0, 0)
    playerCount:SetText("|cff888888Players: 0|r")
    frame.playerCount = playerCount
    
    -- Reset button
    local resetBtn = BJ.Theme:Button(footerBar, "", 100, 28, "danger", nil)
    resetBtn:SetPoint("RIGHT", 0, 0)
    
    local resetText = resetBtn.text
    resetText:SetText("Reset My Stats")

    resetBtn:SetScript("OnEnter", function(self)

        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Reset My Stats", 1, 0.55, 0.55)
        GameTooltip:AddLine("Clears YOUR personal stats panel for this game. Shared leaderboard rows live on every player's client and are not touched.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    resetBtn:SetScript("OnLeave", function(self)
        BJ.Theme:StyleButton(self)
        GameTooltip:Hide()
    end)
    resetBtn:SetScript("OnClick", function()
        StaticPopupDialogs["CASINO_RESET_LEADERBOARD"] = {
            text = "Reset your personal stats for |cffffd700" .. GAME_INFO[frame.selectedTab].name .. "|r?\n\nThe shared leaderboard is not affected.\nThis cannot be undone!",
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

    -- Full wipe (test mode only): clears ALL games, ALL players, and tells
    -- the group to do the same - keeps test games from poisoning real stats
    local clearAllBtn = BJ.Theme:Button(footerBar, "", 110, 28, "danger", nil)
    clearAllBtn:SetPoint("RIGHT", resetBtn, "LEFT", -8, 0)

    local clearAllText = clearAllBtn.text
    clearAllText:SetText("Wipe ALL")

    clearAllBtn:SetScript("OnEnter", function(self)

        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Wipe ALL Stats (Test Mode)", 1, 0.6, 0.25)
        GameTooltip:AddLine("Clears every game and every player, locally AND for the group.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    clearAllBtn:SetScript("OnLeave", function(self)
        BJ.Theme:StyleButton(self)
        GameTooltip:Hide()
    end)
    clearAllBtn:SetScript("OnClick", function()
        StaticPopupDialogs["CASINO_CLEAR_ALL_DB"] = {
            text = "|cffff6666WARNING:|r Clear ALL leaderboard data?\n\nThis will wipe your local database AND send a clear command to all party members!\n\n|cffff9944This cannot be undone!|r",
            button1 = "Clear All",
            button2 = "Cancel",
            OnAccept = function()
                LB:ClearAllData(true)
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
        }
        StaticPopup_Show("CASINO_CLEAR_ALL_DB")
    end)
    clearAllBtn:Hide()
    frame.clearAllBtn = clearAllBtn

    -- Only surface the full wipe while test mode is on
    frame:HookScript("OnShow", function()
        if BJ.TestMode and BJ.TestMode.enabled then
            clearAllBtn:Show()
        else
            clearAllBtn:Hide()
        end
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
    -- Everyone on the board, so a shared first name shows whole.
    local boardNames = {}
    for _, e in ipairs(leaderboard) do boardNames[#boardNames + 1] = e.name end
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
            
            row.rank = row:CreateFontString(nil, "OVERLAY", "CCFontSmall")
            row.rank:SetPoint("LEFT", 18, 0)
            row.rank:SetWidth(20)
            row.rank:SetJustifyH("CENTER")
            
            row.name = row:CreateFontString(nil, "OVERLAY", "CCFontSmall")
            row.name:SetPoint("LEFT", 40, 0)
            row.name:SetWidth(120)
            row.name:SetJustifyH("LEFT")
            -- One line: a long two-word Forever name is cut with "..."
            -- rather than wrapping into the row below.
            pcall(row.name.SetWordWrap, row.name, false)
            
            row.net = row:CreateFontString(nil, "OVERLAY", "CCFontSmall")
            row.net:SetPoint("LEFT", 155, 0)
            row.net:SetWidth(75)
            row.net:SetJustifyH("RIGHT")
            
            row.wl = row:CreateFontString(nil, "OVERLAY", "CCFontSmall")
            row.wl:SetPoint("LEFT", 245, 0)
            row.wl:SetWidth(55)
            row.wl:SetJustifyH("CENTER")
            
            row.games = row:CreateFontString(nil, "OVERLAY", "CCFontSmall")
            row.games:SetPoint("LEFT", 315, 0)
            row.games:SetWidth(45)
            row.games:SetJustifyH("CENTER")
            
            row.sync = row:CreateFontString(nil, "OVERLAY", "CCFontSmall")
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
        
        local shown, wholeName = BJ:SeatName(entry.name, boardNames)
        row.name:SetText(shown)
        BJ:FitNameFont(row.name, wholeName)
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

-- Show all-time leaderboard
function LBUI:ShowAllTime()
    if not LB.allTimeFrame then
        LB.allTimeFrame = self:CreateAllTimeFrame()
    end

    self:SelectTab(LB.allTimeFrame.selectedTab or "blackjack")
    LB.allTimeFrame:Show()
    -- opening the board is a hardware event: announce to the realm so peers
    -- reconcile their boards with ours
    if LB.QueueRealmHello then LB:QueueRealmHello(); LB:FlushRealmQueue() end
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
        if LB.QueueRealmHello then LB:QueueRealmHello(); LB:FlushRealmQueue() end
    end
end

-- Check if all-time window is shown
function LBUI:IsAllTimeShown()
    return LB.allTimeFrame and LB.allTimeFrame:IsShown()
end
