--[[
    Chairface's Casino - UI/Lobby.lua
    Main casino lobby - game selection screen with animated elements
]]

local BJ = ChairfacesCasino
local UI = BJ.UI

UI.Lobby = {}
local Lobby = UI.Lobby

local LOBBY_WIDTH = 720
local LOBBY_HEIGHT = 420  -- condensed: 3 rows x 4 games, flush grid
local HELP_HEIGHT = 730   -- the How-to-Play panel keeps its full height (tall game-button column)
local HELP_WIDTH = 720  -- widened for the tavern background; content area fills the extra width

-- ===========================================================================
-- Shared "tavern" background (the rowdy-casino lobby art) for the utility
-- windows: Settings, How to Play, Leaderboard, Debts, LFG. Same layering trick
-- the lobby uses (art at BACKGROUND sub-level 1 so it draws over the frame's
-- backdrop fill, dark scrim at sub-level 2 for readability), but with COVER
-- tex-coords so the landscape art fills any window shape without distortion,
-- recomputed on resize. Call once per frame; safe to call again (no-op).
-- ===========================================================================
local TAVERN_TEX = "Interface\\AddOns\\Chairfaces Casino\\Textures\\lobby_bg"
local TAVERN_ASPECT = 720 / 490   -- native aspect of lobby_bg.tga

local function tavernCover(tex, frame)
    local w, h = frame:GetWidth(), frame:GetHeight()
    if not w or not h or w <= 0 or h <= 0 then return end
    local frameAspect = w / h
    if frameAspect > TAVERN_ASPECT then
        -- frame is wider than the art: fill width, crop top/bottom
        local vis = TAVERN_ASPECT / frameAspect
        local crop = (1 - vis) / 2
        tex:SetTexCoord(0, 1, crop, 1 - crop)
    else
        -- frame is taller/narrower: fill height, crop left/right
        local vis = frameAspect / TAVERN_ASPECT
        local crop = (1 - vis) / 2
        tex:SetTexCoord(crop, 1 - crop, 0, 1)
    end
end

function Lobby:ApplyTavernBackground(frame, opts)
    if not frame or frame.__tavernBg then return frame and frame.__tavernBg end
    opts = opts or {}
    if frame.SetBackdropColor then
        -- dark fallback that only shows if the art texture fails to load
        frame:SetBackdropColor(0.06, 0.05, 0.07, 0.97)
    end
    local art = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    art:SetPoint("TOPLEFT", 3, -3)
    art:SetPoint("BOTTOMRIGHT", -3, 3)
    art:SetTexture(TAVERN_TEX)
    local scrim = frame:CreateTexture(nil, "BACKGROUND", nil, 2)
    scrim:SetAllPoints(art)
    -- these windows are text-heavy, so a slightly heavier scrim than the lobby's
    scrim:SetColorTexture(0.03, 0.02, 0.05, opts.scrim or 0.62)
    frame.__tavernBg = art
    frame.__tavernScrim = scrim
    local function refresh() tavernCover(art, frame) end
    refresh()
    frame:HookScript("OnSizeChanged", refresh)
    frame:HookScript("OnShow", refresh)
    return art
end

-- Easter egg: Trixie poke sounds (default 1 in 500 chance on click)
local DEFAULT_POKE_CHANCE = 500

-- Voice frequency multipliers (how often Trixie speaks during game events)
-- Lower = more frequent, Higher = less frequent
local VOICE_FREQ_OPTIONS = {
    { name = "Always", value = 1 },      -- Always plays
    { name = "Frequent", value = 2 },    -- 50% chance
    { name = "Normal", value = 3 },      -- 33% chance (default)
    { name = "Occasional", value = 5 },  -- 20% chance
    { name = "Rare", value = 10 },       -- 10% chance
}

function Lobby:GetPokeChance()
    -- Try to load from encrypted storage first
    if ChairfacesCasinoSaved and ChairfacesCasinoSaved.pokeChanceEnc then
        if BJ.Compression and BJ.Compression.DecodeFromSave then
            local decoded = BJ.Compression:DecodeFromSave(ChairfacesCasinoSaved.pokeChanceEnc)
            if decoded and type(decoded) == "number" then
                return decoded
            end
        end
    end
    -- Fallback to old unencrypted location (migration)
    if BJ.db and BJ.db.settings and BJ.db.settings.pokeChance then
        local value = BJ.db.settings.pokeChance
        -- Migrate to encrypted storage
        self:SetPokeChance(value)
        BJ.db.settings.pokeChance = nil  -- Clear old storage
        return value
    end
    return DEFAULT_POKE_CHANCE
end

function Lobby:SetPokeChance(value)
    if not ChairfacesCasinoSaved then
        ChairfacesCasinoSaved = {}
    end
    if BJ.Compression and BJ.Compression.EncodeForSave then
        ChairfacesCasinoSaved.pokeChanceEnc = BJ.Compression:EncodeForSave(value)
    end
end

function Lobby:GetVoiceFrequency()
    if BJ.db and BJ.db.settings and BJ.db.settings.voiceFrequency then
        return BJ.db.settings.voiceFrequency
    end
    return 3  -- Default to "Normal"
end

function Lobby:SetVoiceFrequency(value)
    if BJ.db and BJ.db.settings then
        BJ.db.settings.voiceFrequency = value
    end
end

-- Check if voice should play based on frequency setting
function Lobby:ShouldPlayVoice()
    local freq = self:GetVoiceFrequency()
    return math.random(1, freq) == 1
end

function Lobby:TryPlayPokeSound()
    return self:TryPlayPoke()
end

function Lobby:Initialize()
    if self.frame then return end
    self:CreateLobbyFrame()
end

function Lobby:CreateLobbyFrame()
    local frame = CreateFrame("Frame", "ChairfacesCasinoLobby", UIParent, "BackdropTemplate")
    frame:SetSize(LOBBY_WIDTH, LOBBY_HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    frame:SetFrameStrata("HIGH")
    
    -- Background
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    frame:SetBackdropColor(0.05, 0.04, 0.06, 0.97)  -- dark fallback if art missing
    frame:SetBackdropBorderColor(0.6, 0.5, 0.2, 1)

    -- Rowdy Azerothian casino backdrop art. On this client a plain BACKGROUND
    -- texture draws BEHIND the frame's backdrop fill and is hidden, so - like
    -- High-Lo's felt - the art sits at BACKGROUND sub-level 1 (above the
    -- backdrop) and a dark scrim at sub-level 2 keeps the game grid readable.
    -- Sub-levels must stay within -8..7.
    local bgArt = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    bgArt:SetPoint("TOPLEFT", 3, -3)
    bgArt:SetPoint("BOTTOMRIGHT", -3, 3)
    bgArt:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\lobby_bg")
    local bgScrim = frame:CreateTexture(nil, "BACKGROUND", nil, 2)
    bgScrim:SetAllPoints(bgArt)
    bgScrim:SetColorTexture(0.03, 0.02, 0.05, 0.5)

    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -5, -5)
    closeBtn:SetScript("OnClick", function()
        Lobby:PlayTrixieVoice("bye", { cd = 30 })
        frame:Hide()
    end)

    -- Animated logo centered above game selection
    -- Logo is 200x113 base, scaled to 312x176 (25% wider than 250px buttons)
    local logoWidth = 312
    local logoHeight = 176
    local logoFrame = CreateFrame("Frame", nil, frame)
    logoFrame:SetSize(logoWidth, logoHeight)
    logoFrame:SetPoint("TOP", frame, "TOP", 0, -2)
    
    local logoTexture = logoFrame:CreateTexture(nil, "ARTWORK")
    logoTexture:SetAllPoints()
    logoTexture:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\logo_frames")
    logoTexture:SetTexCoord(0, 1, 1/80, 0)  -- Vertical: first frame, Y-flipped
    
    -- Animate logo continuously
    local logoElapsed = 0
    local logoNumFrames = 80
    local logoFrameTime = 0.065  -- ~15fps (30% slower than 0.05)
    local logoCurrentFrame = 0
    local logoAnimDuration = logoNumFrames * logoFrameTime
    
    logoFrame:SetScript("OnUpdate", function(self, dt)
        logoElapsed = logoElapsed + dt
        
        -- Loop the animation
        if logoElapsed >= logoAnimDuration then
            logoElapsed = logoElapsed - logoAnimDuration
            logoCurrentFrame = 0
        end
        
        local newFrame = math.floor(logoElapsed / logoFrameTime)
        if newFrame ~= logoCurrentFrame and newFrame < logoNumFrames then
            logoCurrentFrame = newFrame
            -- Vertical sprite sheet: adjust top/bottom coords
            local top = logoCurrentFrame / logoNumFrames
            local bottom = (logoCurrentFrame + 1) / logoNumFrames
            logoTexture:SetTexCoord(0, 1, bottom, top)  -- Y-flipped
        end
    end)
    
    -- Game selection panel (centered below logo)
    local gamePanel = CreateFrame("Frame", nil, frame)
    gamePanel:SetSize(690, LOBBY_HEIGHT - logoHeight - 60)
    gamePanel:SetPoint("TOP", logoFrame, "BOTTOM", 0, -2)
    
    -- Invisible anchor row where the "Select a Game" label used to sit;
    -- every game button hangs off this, so it stays as a pure anchor
    local gamesLabel = gamePanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    gamesLabel:SetPoint("TOP", gamePanel, "TOP", 0, -4)
    gamesLabel:SetText("")
    
    -- ===================== GAME GRID =====================
    -- Condensed 3-row x 4-column grid; buttons sit flush (no gaps) with a
    -- single icon to the left of each name. Each game group is a COLUMN:
    --   Col 1 (dice)  Col 2 (cards)   Col 3           Col 4
    --   High-Lo       Texas Hold'em   Chair's Cup     Bingo
    --   Death Roll    5 Card Stud     Roulette        Slots
    --   Liar's Dice   Blackjack       Crash           Video Poker
    local BUTTON_WIDTH  = 170
    local BUTTON_HEIGHT = 50
    local GRID_TOP      = -2          -- first row sits right under the logo
    local TEX  = "Interface\\AddOns\\Chairfaces Casino\\Textures\\"
    local CARDS = TEX .. "cards\\"
    local DICE  = TEX .. "icon"
    local WID   = TEX .. "Widgets\\"
    local ARC   = TEX .. "Arcade\\"
    local ICON_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

    -- 4 columns centred: 1,2,3,4 -> -1.5W, -0.5W, +0.5W, +1.5W
    local function colX(col) return (col - 2.5) * BUTTON_WIDTH end
    local function rowY(row) return GRID_TOP - (row - 1) * BUTTON_HEIGHT end

    local function gameHoverIn(self)
        local r, g, b = self:GetBackdropColor()
        self:SetBackdropColor(r + 0.05, g + 0.15, b + 0.05, 0.5)
        local br, bg, bb = self:GetBackdropBorderColor()
        self:SetBackdropBorderColor(br + 0.1, bg + 0.3, bb + 0.1, 1)
    end

    -- Factory for the common "hide the lobby and open a UI module" click
    local function opener(mod, method)
        return function()
            frame:Hide()
            Lobby:HideHelp(true)
            local m = UI[mod]
            if m and m[method] then m[method](m) end
        end
    end

    -- Blackjack is the root UI module (UI:Show), not a sub-module
    local function openBlackjack()
        frame:Hide()
        Lobby:HideHelp(true)
        if UI.Show then UI:Show() end
    end

    -- Opens the standalone Chair's Cup / Sigma Derby addon via its slash handler
    local function openDerby()
        frame:Hide()
        Lobby:HideHelp(true)
        local handler = SlashCmdList and SlashCmdList["CHAIRSCUP"]
        if handler then
            local sd = _G.SigmaDerbyFrame
            if not (sd and sd:IsShown()) then
                handler("")
                sd = _G.SigmaDerbyFrame
            end
            if sd then
                Lobby.derbyOpenedFromLobby = true
                if not Lobby.derbyHideHooked then
                    Lobby.derbyHideHooked = true
                    sd:HookScript("OnHide", function()
                        if Lobby.derbyOpenedFromLobby then
                            Lobby.derbyOpenedFromLobby = false
                            Lobby:Show()
                        end
                    end)
                end
            end
        else
            BJ:Print("|cffff4444Chair's Cup (Derby) isn't available - reload your UI and try again.|r")
        end
    end

    -- Build one grid button. spec: row, col, key (frame.<key>), name, nameSize,
    -- icon (texture), iw/ih (icon size), texCoord/mask (optional), open (onclick),
    -- arcade (bool -> purple styling, fake-credit subtext, no live-table gating).
    local function makeGameButton(spec)
        local btn = CreateFrame("Button", nil, gamePanel, "BackdropTemplate")
        btn:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
        btn:SetPoint("TOP", gamesLabel, "BOTTOM", colX(spec.col), rowY(spec.row))
        btn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
        if spec.arcade then
            btn:SetBackdropColor(0.22, 0.12, 0.3, 0.5)
            btn:SetBackdropBorderColor(0.55, 0.35, 0.7, 1)
        else
            btn:SetBackdropColor(0.15, 0.35, 0.15, 0.5)
            btn:SetBackdropBorderColor(0.3, 0.7, 0.3, 1)
        end

        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetSize(spec.iw or 32, spec.ih or 32)
        icon:SetPoint("LEFT", btn, "LEFT", 8, 0)
        icon:SetTexture(spec.icon)
        if spec.mask and icon.SetMask then icon:SetMask(ICON_MASK)
        elseif spec.texCoord then icon:SetTexCoord(unpack(spec.texCoord)) end
        btn.icons = { icon }

        local name = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        name:SetPoint("LEFT", icon, "RIGHT", 7, 6)
        name:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
        name:SetJustifyH("LEFT")
        name:SetFont("Fonts\\FRIZQT__.TTF", spec.nameSize or 13, "OUTLINE")
        name:SetText((spec.arcade and "|cffcc88ff" or "|cff00ff00") .. spec.name .. "|r")

        local sub = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        sub:SetPoint("LEFT", icon, "RIGHT", 7, -9)
        sub:SetText(spec.arcade and "|cffaa77ddFake Credits|r" or "|cff88ff88Play Now!|r")
        btn.subtext = sub

        if spec.arcade then
            btn:SetScript("OnEnter", function(self)
                self:SetBackdropColor(0.3, 0.18, 0.4, 0.5)
                self:SetBackdropBorderColor(0.7, 0.5, 0.9, 1)
            end)
            btn:SetScript("OnLeave", function(self)
                self:SetBackdropColor(0.22, 0.12, 0.3, 0.5)
                self:SetBackdropBorderColor(0.55, 0.35, 0.7, 1)
            end)
        else
            btn:SetScript("OnEnter", gameHoverIn)
            btn:SetScript("OnLeave", function() Lobby:UpdateGameButtons() end)
        end
        btn:SetScript("OnClick", spec.open)
        frame[spec.key] = btn
        return btn, icon
    end

    -- Column 1: dice games
    makeGameButton({ row = 1, col = 1, key = "hiloButton",      name = "High-Lo",     icon = DICE, iw = 34, ih = 34, open = opener("HiLo", "Show") })
    makeGameButton({ row = 2, col = 1, key = "deathrollButton", name = "Death Roll",  icon = DICE, iw = 34, ih = 34, open = opener("DeathRoll", "Show") })
    makeGameButton({ row = 3, col = 1, key = "liarsdiceButton", name = "Liar's Dice", icon = DICE, iw = 34, ih = 34, open = opener("LiarsDice", "Show") })

    -- Column 2: card games
    makeGameButton({ row = 1, col = 2, key = "holdemButton", name = "Texas Hold'em", nameSize = 12, icon = CARDS .. "K_spades", iw = 26, ih = 36, open = opener("Holdem", "Show") })
    makeGameButton({ row = 2, col = 2, key = "fcsButton",    name = "5 Card Stud",   icon = CARDS .. "5_spades", iw = 26, ih = 36, open = opener("Poker", "Show") })
    makeGameButton({ row = 3, col = 2, key = "bjButton",     name = "Blackjack",     icon = CARDS .. "A_spades", iw = 26, ih = 36, open = openBlackjack })

    -- Column 3: Chair's Cup / Roulette / Crash
    makeGameButton({ row = 1, col = 3, key = "derbyButton",    name = "Chair's Cup", nameSize = 12, icon = WID .. "chairscup_icon", iw = 34, ih = 34, open = openDerby })
    makeGameButton({ row = 2, col = 3, key = "rouletteButton", name = "Roulette",    icon = WID .. "roulette_icon", iw = 34, ih = 34, open = opener("Roulette", "Show") })
    local crashBtn, crashZep = makeGameButton({ row = 3, col = 3, key = "crashButton", name = "Crash", icon = TEX .. "Crash\\zeppelin", iw = 52, ih = 26, texCoord = { 0, 1, 0, 0.1 }, open = opener("Crash", "Show") })

    -- Column 4: Bingo + solo arcade (Slots, Video Poker)
    makeGameButton({ row = 1, col = 4, key = "bingoButton",      name = "Bingo",                 icon = WID .. "bingo_icon", iw = 34, ih = 34, open = opener("Bingo", "Show") })
    makeGameButton({ row = 2, col = 4, key = "slotsButton",      name = "Slots: Azeroth Riches", nameSize = 10, arcade = true, icon = ARC .. "emerald",  iw = 30, ih = 30, open = opener("Slots", "Show") })
    makeGameButton({ row = 3, col = 4, key = "videoPokerButton", name = "Video Poker",           arcade = true, icon = ARC .. "sapphire", iw = 30, ih = 30, open = opener("VideoPoker", "Show") })

    -- Animate the crash zeppelin icon in place (10-frame vertical sprite sheet)
    do
        local ZFRAMES, ZFPS = 10, 18
        local zepElapsed, zepFrame = 0, -1
        crashBtn:SetScript("OnUpdate", function(_, dt)
            zepElapsed = zepElapsed + dt
            if zepElapsed > 3600 then zepElapsed = zepElapsed % (ZFRAMES / ZFPS) end
            local f = math.floor(zepElapsed * ZFPS) % ZFRAMES
            if f ~= zepFrame then
                zepFrame = f
                crashZep:SetTexCoord(0, 1, f / ZFRAMES, (f + 1) / ZFRAMES)
            end
        end)
    end

    -- Utility buttons hang just below the last grid row
    local GAMES_BOTTOM_Y = rowY(3) - BUTTON_HEIGHT
    
    -- Settings, Help, Leaderboard, Debts, LFG in one row (centered)
    local UTIL_BUTTON_WIDTH = 80
    local UTIL_ROW_WIDTH = UTIL_BUTTON_WIDTH * 5 + 32  -- 5 buttons + 4 gaps of 8
    
    local buttonRow1 = CreateFrame("Frame", nil, gamePanel)
    buttonRow1:SetSize(UTIL_ROW_WIDTH, 35)
    buttonRow1:SetPoint("TOP", gamesLabel, "BOTTOM", 0, GAMES_BOTTOM_Y - 20)
    
    -- Settings button (row 1, left)
    local settingsBtn = CreateFrame("Button", nil, buttonRow1, "BackdropTemplate")
    settingsBtn:SetSize(UTIL_BUTTON_WIDTH, 35)
    settingsBtn:SetPoint("LEFT", buttonRow1, "LEFT", 0, 0)
    settingsBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    settingsBtn:SetBackdropColor(0.25, 0.2, 0.15, 0.5)
    settingsBtn:SetBackdropBorderColor(0.5, 0.4, 0.2, 1)

    local settingsText = settingsBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    settingsText:SetPoint("CENTER")
    settingsText:SetText("|cffffd700Settings|r")

    settingsBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.35, 0.3, 0.2, 0.5)
        self:SetBackdropBorderColor(0.7, 0.6, 0.3, 1)
    end)
    settingsBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.25, 0.2, 0.15, 0.5)
        self:SetBackdropBorderColor(0.5, 0.4, 0.2, 1)
    end)
    settingsBtn:SetScript("OnClick", function()
        Lobby:OpenFromLobby(function() Lobby:ShowSettings() end,
            function() return Lobby.settingsFrame end)
    end)
    
    -- Help button (row 1, second from left)
    local helpBtn = CreateFrame("Button", nil, buttonRow1, "BackdropTemplate")
    helpBtn:SetSize(UTIL_BUTTON_WIDTH, 35)
    helpBtn:SetPoint("LEFT", settingsBtn, "RIGHT", 8, 0)
    helpBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    helpBtn:SetBackdropColor(0.15, 0.25, 0.35, 0.5)
    helpBtn:SetBackdropBorderColor(0.3, 0.5, 0.7, 1)
    
    local helpText = helpBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    helpText:SetPoint("CENTER")
    helpText:SetText("|cff88ccffHow to Play|r")
    
    helpBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.2, 0.35, 0.5, 0.5)
        self:SetBackdropBorderColor(0.4, 0.7, 1, 1)
    end)
    helpBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.15, 0.25, 0.35, 0.5)
        self:SetBackdropBorderColor(0.3, 0.5, 0.7, 1)
    end)
    helpBtn:SetScript("OnClick", function()
        Lobby:ShowHelp()
    end)
    
    -- Leaderboard button (row 1, third from left)
    local lbBtn = CreateFrame("Button", nil, buttonRow1, "BackdropTemplate")
    lbBtn:SetSize(UTIL_BUTTON_WIDTH, 35)
    lbBtn:SetPoint("LEFT", helpBtn, "RIGHT", 8, 0)
    lbBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    lbBtn:SetBackdropColor(0.35, 0.28, 0.1, 0.5)
    lbBtn:SetBackdropBorderColor(0.8, 0.65, 0.2, 1)
    
    local lbText = lbBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbText:SetPoint("CENTER")
    lbText:SetText("|cffffd700Leaderboard|r")
    
    lbBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.45, 0.38, 0.15, 0.5)
        self:SetBackdropBorderColor(1, 0.85, 0.3, 1)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("All-Time Leaderboard", 1, 0.84, 0)
        GameTooltip:AddLine("View win/loss standings across all games", 1, 1, 1)
        GameTooltip:AddLine("Track your stats and compare with others", 1, 1, 1)
        GameTooltip:Show()
    end)
    lbBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.35, 0.28, 0.1, 0.5)
        self:SetBackdropBorderColor(0.8, 0.65, 0.2, 1)
        GameTooltip:Hide()
    end)
    lbBtn:SetScript("OnClick", function()
        if BJ.LeaderboardUI then
            Lobby:OpenFromLobby(function() BJ.LeaderboardUI:ShowAllTime() end,
                function() return BJ.Leaderboard and BJ.Leaderboard.allTimeFrame end)
        end
    end)
    self.leaderboardBtn = lbBtn

    -- Debts / settle-up ledger button (row 1, fourth)
    local debtBtn = CreateFrame("Button", nil, buttonRow1, "BackdropTemplate")
    debtBtn:SetSize(UTIL_BUTTON_WIDTH, 35)
    debtBtn:SetPoint("LEFT", lbBtn, "RIGHT", 8, 0)
    debtBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    debtBtn:SetBackdropColor(0.3, 0.14, 0.1, 0.5)
    debtBtn:SetBackdropBorderColor(0.7, 0.35, 0.25, 1)

    local debtText = debtBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    debtText:SetPoint("CENTER")
    debtText:SetText("|cffff9977Debts|r")

    debtBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.42, 0.2, 0.14, 0.5)
        self:SetBackdropBorderColor(1, 0.5, 0.35, 1)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Settle-Up Ledger", 1, 0.6, 0.45)
        GameTooltip:AddLine("Who owes who, netted across every game", 1, 1, 1)
        GameTooltip:AddLine("Trading gold to a player settles your tab automatically", 1, 1, 1)
        GameTooltip:Show()
    end)
    debtBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.3, 0.14, 0.1, 0.5)
        self:SetBackdropBorderColor(0.7, 0.35, 0.25, 1)
        GameTooltip:Hide()
    end)
    debtBtn:SetScript("OnClick", function()
        if BJ.UI and BJ.UI.Debts then
            Lobby:OpenFromLobby(function() BJ.UI.Debts:Show() end,
                function() return BJ.UI.Debts.frame end)
        end
    end)

    -- Table Finder / LFG button (row 1, fifth)
    local finderBtn = CreateFrame("Button", nil, buttonRow1, "BackdropTemplate")
    finderBtn:SetSize(UTIL_BUTTON_WIDTH, 35)
    finderBtn:SetPoint("LEFT", debtBtn, "RIGHT", 8, 0)
    finderBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    finderBtn:SetBackdropColor(0.1, 0.18, 0.3, 0.5)
    finderBtn:SetBackdropBorderColor(0.3, 0.45, 0.75, 1)

    local finderText = finderBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    finderText:SetPoint("CENTER")
    finderText:SetText("|cff88bbffLFG|r")

    finderBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.15, 0.26, 0.42, 0.5)
        self:SetBackdropBorderColor(0.45, 0.65, 1, 1)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Table Finder", 0.55, 0.75, 1)
        GameTooltip:AddLine("An LFG board for gambling: list yourself as", 1, 1, 1)
        GameTooltip:AddLine("hosting or looking to play, and find others", 1, 1, 1)
        GameTooltip:Show()
    end)
    finderBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.1, 0.18, 0.3, 0.5)
        self:SetBackdropBorderColor(0.3, 0.45, 0.75, 1)
        GameTooltip:Hide()
    end)
    finderBtn:SetScript("OnClick", function()
        frame:Hide()
        Lobby:HideHelp(true)
        if BJ.UI and BJ.UI.Finder then BJ.UI.Finder:Show() end
    end)

    -- Copyright text at bottom center
    local copyrightText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    copyrightText:SetPoint("BOTTOM", frame, "BOTTOM", 0, 8)
    copyrightText:SetText("|cff666666© 2026 Chairface / Ionlydps|r")
    
    -- Version text at bottom right
    local versionText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    versionText:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 8)
    versionText:SetText("|cff888888Chairface's Casino v" .. BJ.version .. "|r")
    
    -- Trixie on the right side of lobby (same size as games: 274x350)
    local TRIXIE_WIDTH = 274
    local TRIXIE_HEIGHT = 350
    
    -- Parent to UIParent but position relative to lobby frame
    local trixieFrame = CreateFrame("Button", "LobbyTrixieFrame", UIParent)
    trixieFrame:SetSize(TRIXIE_WIDTH, TRIXIE_HEIGHT)
    trixieFrame:SetPoint("LEFT", frame, "RIGHT", 0, 0)
    trixieFrame:SetFrameStrata("HIGH")  -- Same as lobby
    
    -- Random wait image (1-31, includes trixie_tall as wait31)
    local randomWaitIdx = math.random(1, 31)
    local trixieTexture = trixieFrame:CreateTexture(nil, "ARTWORK")
    trixieTexture:SetAllPoints()
    trixieTexture:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\dealer\\trix_wait" .. randomWaitIdx)
    trixieFrame.texture = trixieTexture
    
    -- Easter egg click handler
    trixieFrame:SetScript("OnClick", function()
        Lobby:TryPlayPoke()
    end)
    
    -- Hide when lobby hides
    frame:HookScript("OnHide", function()
        trixieFrame:Hide()
    end)
    frame:HookScript("OnShow", function()
        -- Randomize Trixie pose each time lobby opens
        local newIdx = math.random(1, 31)
        trixieFrame.texture:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\dealer\\trix_wait" .. newIdx)
        Lobby:UpdateLobbyTrixieVisibility()
    end)
    
    self.lobbyTrixie = trixieFrame

    frame:HookScript("OnHide", function() Lobby:StopBanterTicker() end)

    frame:Hide()
    self.frame = frame
end

-- Every casino game window, by global name. Opening the lobby closes all
-- of these first so windows never stack and z-fight.
local GAME_WINDOWS = {
    "ChairfacesCasinoFrame",      -- Blackjack
    "ChairfacesCasinoPoker",      -- 5 Card Stud
    "ChairfacesCasinoHoldem",     -- Texas Hold'em
    "ChairfacesCasinoHiLo",       -- High-Lo
    "ChairfacesCasinoDeathRoll",  -- Death Roll
    "ChairfacesCasinoBingo",      -- Bingo
    "ChairfacesCasinoRoulette",   -- Roulette
    "ChairfacesCasinoLiarsDice",  -- Liar's Dice
    "SigmaDerbyFrame",            -- Chair's Cup derby
    "ChairfacesCasinoSlots",      -- Solo slots
    "ChairfacesCasinoVideoPoker", -- Solo video poker
}

function Lobby:CloseGameWindows()
    for _, name in ipairs(GAME_WINDOWS) do
        local f = _G[name]
        if f and f.Hide and f:IsShown() then
            f:Hide()
        end
    end
end

function Lobby:Show()
    if not self.frame then
        self:Initialize()
    end

    -- one casino window at a time: the lobby replaces whatever game
    -- window is open instead of layering over it
    self:CloseGameWindows()

    -- Initialize audio on first show
    if not self.audioInitialized then
        self:InitializeAudio()
        self.audioInitialized = true
    end
    
    -- Apply saved window scale
    self:ApplyWindowScale()
    
    -- Update Lobby Trixie visibility
    self:UpdateLobbyTrixieVisibility()
    
    -- Update game button states based on active games
    self:UpdateGameButtons()
    
    -- Start lobby refresh ticker
    self:StartLobbyRefreshTicker()
    
    self.frame:Show()
    
    -- Check for first run intro
    if not ChairfacesCasinoSaved then
        ChairfacesCasinoSaved = {}
    end
    
    -- Force intro to show again for the 2.3.3 release (reset if they
    -- haven't seen the 2.3.3 intro yet)
    if not ChairfacesCasinoSaved.introVersion or ChairfacesCasinoSaved.introVersion < "2.3.3" then
        ChairfacesCasinoSaved.trixieIntroShown = nil
    end

    if not ChairfacesCasinoSaved.trixieIntroShown then
        C_Timer.After(0.5, function()
            self:ShowTrixieIntro()
        end)
        ChairfacesCasinoSaved.trixieIntroShown = true
        ChairfacesCasinoSaved.introVersion = "2.3.3"  -- Track which version they saw intro for
    else
        -- Trixie greets you (not on the very first run - the intro covers that)
        C_Timer.After(1.2, function()
            if self.frame and self.frame:IsShown() then self:TrixieGreeting() end
        end)
    end

    -- kick off her idle banter while the lobby is up
    self:StartBanterTicker()
end

-- Update Lobby Trixie visibility based on setting
function Lobby:UpdateLobbyTrixieVisibility()
    if not self.lobbyTrixie then return end
    
    local showTrixie = true
    if BJ.db and BJ.db.settings then
        showTrixie = BJ.db.settings.showLobbyTrixie ~= false
    end
    
    -- Only show Trixie if setting is enabled AND lobby is visible
    if showTrixie and self.frame and self.frame:IsShown() then
        self.lobbyTrixie:Show()
    else
        self.lobbyTrixie:Hide()
    end
end

-- Apply saved window scale to all casino windows
function Lobby:ApplyWindowScale()
    local scale = 1.0
    if BJ.db and BJ.db.settings and BJ.db.settings.windowScale then
        scale = BJ.db.settings.windowScale
    end
    
    -- Apply to lobby
    if self.frame then
        self.frame:SetScale(scale)
    end
    
    -- Apply to blackjack (uses mainFrame)
    if BJ.UI and BJ.UI.mainFrame then
        BJ.UI.mainFrame:SetScale(scale)
    end
    
    -- Apply to poker
    if BJ.UI and BJ.UI.Poker and BJ.UI.Poker.mainFrame then
        BJ.UI.Poker.mainFrame:SetScale(scale)
    end
    
    -- Apply to high-lo (uses container as outer frame)
    if BJ.UI and BJ.UI.HiLo and BJ.UI.HiLo.container then
        BJ.UI.HiLo.container:SetScale(scale)
    end
    
    -- Apply to settings
    if self.settingsFrame then
        self.settingsFrame:SetScale(scale)
    end
    
    -- Apply to lobby Trixie (since it's parented to UIParent)
    if self.lobbyTrixie then
        self.lobbyTrixie:SetScale(scale)
    end
    
    -- Apply to help Trixie (since it's parented to UIParent)
    if self.helpTrixie then
        self.helpTrixie:SetScale(scale)
    end
end

-- Show Trixie introduction on first run
function Lobby:ShowTrixieIntro()
    -- Hide the lobby while intro is showing
    if self.frame then
        self.frame:Hide()
    end
    
    -- Play fanfare and intro voice
    self:PlayWinSound()
    self:PlayTrixieIntroVoice()
    
    -- Create intro overlay container
    local container = CreateFrame("Frame", "TrixieIntroContainer", UIParent)
    container:SetPoint("CENTER")
    container:SetSize(700, 500)
    container:SetFrameStrata("FULLSCREEN_DIALOG")
    
    -- Go straight to tall Trixie with dialog
    self:ShowIntroPhase2(container)
end

-- Phase 2: Show tall Trixie with dialog
function Lobby:ShowIntroPhase2(container)
    -- Trixie tall image (left side, standing next to dialog)
    -- Original image is 896x1152, display at proper aspect ratio
    -- Use a button frame so it's clickable
    local trixieBtn = CreateFrame("Button", nil, container)
    trixieBtn:SetSize(280, 360)
    trixieBtn:SetPoint("LEFT", container, "LEFT", -20, 0)
    
    -- Random wait image for intro
    local introWaitIdx = math.random(1, 31)
    local trixieTall = trixieBtn:CreateTexture(nil, "ARTWORK")
    trixieTall:SetAllPoints()
    trixieTall:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\dealer\\trix_wait" .. introWaitIdx)
    
    -- Easter egg click handler
    trixieBtn:SetScript("OnClick", function()
        Lobby:TryPlayPoke()
    end)
    
    -- Create intro dialog box (right of Trixie)
    local intro = CreateFrame("Frame", "TrixieIntroFrame", container, "BackdropTemplate")
    intro:SetSize(450, 380)
    intro:SetPoint("LEFT", trixieBtn, "RIGHT", 20, 0)
    intro:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 3,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    intro:SetBackdropColor(0.05, 0.05, 0.08, 0.98)
    intro:SetBackdropBorderColor(0.8, 0.6, 0.2, 1)
    
    -- Sparkle border effect
    local glow = intro:CreateTexture(nil, "BACKGROUND")
    glow:SetPoint("TOPLEFT", -10, 10)
    glow:SetPoint("BOTTOMRIGHT", 10, -10)
    glow:SetColorTexture(1, 0.8, 0.3, 0.15)
    glow:SetBlendMode("ADD")
    
    -- Welcome header
    local headerText = intro:CreateFontString(nil, "OVERLAY")
    headerText:SetFont("Fonts\\MORPHEUS.TTF", 24, "OUTLINE")
    headerText:SetPoint("TOP", intro, "TOP", 0, -25)
    headerText:SetText("|cffffd700~ Welcome to the Casino! ~|r")
    
    -- Speech bubble area
    local speechBg = CreateFrame("Frame", nil, intro, "BackdropTemplate")
    speechBg:SetSize(400, 250)
    speechBg:SetPoint("TOP", headerText, "BOTTOM", 0, -20)
    speechBg:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    speechBg:SetBackdropColor(0.15, 0.12, 0.18, 0.9)
    speechBg:SetBackdropBorderColor(0.5, 0.4, 0.6, 0.8)
    
    -- Trixie's dialogue - she introduces herself with her title
    local dialogText = speechBg:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dialogText:SetPoint("CENTER", 0, 0)
    dialogText:SetWidth(380)
    dialogText:SetJustifyH("CENTER")
    dialogText:SetSpacing(3)
   dialogText:SetText(
    "|cffffd700Bal'a dash, darlings!|r |cffffffffWhether you're a fresh face in Silvermoon or a returning high-roller, welcome to the absolute finest casino in Azeroth!|r\n\n" ..
    "|cffffffffI'm|r |cffff99ccTrixie, Grand High Dealer of the Sin'dorei...|r\n" ..
    "|cffffffff...and I am so thrilled to be your personal dealer tonight.\n\n" ..
    "Oh, you would not believe the upgrades we've made! We still have your favorite classic tables, of course... but now?...Oh, sugar, we've gone all out.\n" ..
    "We are now rolling out |cffffd700Texas Hold'em|r, |cffffd700Roulette|r, and |cffffd700Video Poker|r!\n\n" ..
    "We've got |cffffd700Bingo|r, |cffffd700Liar's Dice|r, and |cffffd700Slots|r spinning faster than a gnome in a washing machine!"
)

    -- Continue button
    local continueBtn = CreateFrame("Button", nil, intro, "BackdropTemplate")
    continueBtn:SetSize(120, 35)
    continueBtn:SetPoint("BOTTOM", intro, "BOTTOM", 0, 14)
    continueBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    continueBtn:SetBackdropColor(0.2, 0.5, 0.3, 1)
    continueBtn:SetBackdropBorderColor(0.4, 0.8, 0.5, 1)
    
    local btnText = continueBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btnText:SetPoint("CENTER")
    btnText:SetText("|cffffffffLet's Play!|r")
    
    continueBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.3, 0.6, 0.4, 1)
    end)
    continueBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.2, 0.5, 0.3, 1)
    end)
    continueBtn:SetScript("OnClick", function()
        -- Stop the intro voice
        Lobby:StopTrixieIntroVoice()
        container:Hide()
        container:SetParent(nil)
        -- Show the lobby again
        if Lobby.frame then
            Lobby.frame:Show()
        end
    end)
end

-- Request full state sync for all games
function Lobby:RequestFullSync()
    local SS = BJ.StateSync
    if not SS then
        BJ:Print("|cffff4444StateSync not available.|r")
        return
    end
    
    local syncCount = 0
    local knownHosts = false
    
    -- Check and sync Blackjack
    local bjHost = BJ.Multiplayer and BJ.Multiplayer.currentHost
    if bjHost and bjHost ~= BJ:MyName() then
        SS:RequestFullSync("blackjack", bjHost)
        syncCount = syncCount + 1
        knownHosts = true
        BJ:Print("|cff88ff88Requesting Blackjack sync from " .. bjHost .. "|r")
    end
    
    -- Check and sync Poker
    local pokerHost = BJ.PokerMultiplayer and BJ.PokerMultiplayer.currentHost
    if pokerHost and pokerHost ~= BJ:MyName() then
        SS:RequestFullSync("poker", pokerHost)
        syncCount = syncCount + 1
        knownHosts = true
        BJ:Print("|cff88ff88Requesting Poker sync from " .. pokerHost .. "|r")
    end

    -- Check and sync Texas Hold'em
    local holdemHost = BJ.HoldemMultiplayer and BJ.HoldemMultiplayer.currentHost
    if holdemHost and holdemHost ~= BJ:MyName() then
        SS:RequestFullSync("holdem", holdemHost)
        syncCount = syncCount + 1
        knownHosts = true
        BJ:Print("|cff88ff88Requesting Texas Hold'em sync from " .. holdemHost .. "|r")
    end

    -- Check and sync High-Lo
    local hiloHost = BJ.HiLoMultiplayer and BJ.HiLoMultiplayer.currentHost
    if hiloHost and hiloHost ~= BJ:MyName() then
        SS:RequestFullSync("hilo", hiloHost)
        syncCount = syncCount + 1
        knownHosts = true
        BJ:Print("|cff88ff88Requesting High-Lo sync from " .. hiloHost .. "|r")
    end
    
    if not knownHosts then
        -- No known hosts - try to discover them
        BJ:Print("|cff88ccffSearching for active game hosts...|r")
        local sent = SS:BroadcastDiscovery()
        if sent then
            BJ:Print("|cff888888Hosts will respond if found. Click Sync again in a moment.|r")
        end
    elseif syncCount > 0 then
        BJ:Print("|cff00ff00Sync requested for " .. syncCount .. " game(s).|r")
    end
end

function Lobby:Hide()
    if self.frame then
        self.frame:Hide()
    end
    -- Stop the refresh ticker when lobby is hidden
    self:StopLobbyRefreshTicker()
end

function Lobby:Toggle()
    if self.frame and self.frame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

-- Hook into UI
function UI:ShowLobby()
    -- Don't open lobby if blackjack game window is already open
    if UI.mainFrame and UI.mainFrame:IsShown() then
        return
    end
    
    -- Hide other game windows
    if UI.HiLo and UI.HiLo.container and UI.HiLo.container:IsShown() then
        UI.HiLo:Hide()
    end
    if UI.Poker and UI.Poker.frame and UI.Poker.frame:IsShown() then
        UI.Poker:Hide()
    end
    
    if not UI.Lobby.frame then
        UI.Lobby:Initialize()
    end
    UI.Lobby:Show()
    
    -- Show any pending version warning now that user has opened the casino
    BJ:ShowPendingVersionWarning()
end

-- Settings Panel
function Lobby:CreateSettingsPanel()
    if self.settingsFrame then return end
    
    local frame = CreateFrame("Frame", "ChairfacesCasinoSettings", UIParent, "BackdropTemplate")
    frame:SetSize(560, 580)  -- widened for the tavern background (tallest page is Visuals & Sound)
    frame:SetPoint("CENTER", 200, 0)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    frame:SetFrameStrata("DIALOG")
    
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    frame:SetBackdropColor(0.1, 0.1, 0.12, 0.97)
    frame:SetBackdropBorderColor(0.5, 0.4, 0.2, 1)
    Lobby:ApplyTavernBackground(frame)

    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("|cffffd700Settings|r")
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)

    -- ===== tabs =====
    -- Three pages; every control below lives on exactly one, so a tab
    -- switch is just page Show/Hide. Each page's anchor offset lifts its
    -- content block up under the tab row - the controls keep the anchor
    -- coordinates they had in the old single-page layout.
    local pageVis = CreateFrame("Frame", nil, frame)
    pageVis:SetPoint("TOPLEFT", 0, -44)
    pageVis:SetPoint("BOTTOMRIGHT", 0, -44)
    local pageTrix = CreateFrame("Frame", nil, frame)
    pageTrix:SetPoint("TOPLEFT", -180, 228)
    pageTrix:SetPoint("BOTTOMRIGHT", -180, 228)
    local pageAuto = CreateFrame("Frame", nil, frame)
    pageAuto:SetPoint("TOPLEFT", 0, 498)
    pageAuto:SetPoint("BOTTOMRIGHT", 0, 498)
    frame.settingsPages = { pageVis, pageTrix, pageAuto }

    local tabBtns = {}
    local function selectTab(idx)
        for i, page in ipairs(frame.settingsPages) do
            page:SetShown(i == idx)
            local b = tabBtns[i]
            if i == idx then
                b:SetBackdropColor(0.32, 0.26, 0.12, 1)
                b:SetBackdropBorderColor(0.8, 0.65, 0.3, 1)
            else
                b:SetBackdropColor(0.16, 0.16, 0.2, 1)
                b:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
            end
        end
        frame.currentSettingsTab = idx
    end
    for i, name in ipairs({ "Visuals & Sound", "Trixie", "Auto-Open" }) do
        local b = CreateFrame("Button", nil, frame, "BackdropTemplate")
        b:SetSize(132, 22)
        b:SetPoint("TOPLEFT", 10 + (i - 1) * 140, -34)
        b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        local t = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        t:SetPoint("CENTER")
        t:SetText(name)
        b:SetScript("OnClick", function() selectTab(i) end)
        tabBtns[i] = b
    end
    frame.SelectSettingsTab = selectTab
    
    -- ========== LEFT COLUMN (Card Deck, Card Back, Dice) ==========
    local leftCol = 115  -- Center of left column
    
    -- Card Deck/Face section
    local faceLabel = pageVis:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    faceLabel:SetPoint("TOP", pageVis, "TOPLEFT", leftCol, -20)
    faceLabel:SetText("Card Deck")
    
    local cardDecks = {
        { id = "classic", name = "Classic", texture = "A_spades", path = "cards" },
        { id = "dark", name = "Dark", texture = "A_spades", path = "cards_dark" },
        { id = "warcraft", name = "Warcraft", texture = "A_spades", path = "cards_alt" },
    }
    frame.cardDecks = cardDecks
    
    local savedDeck = "classic"
    if BJ.db and BJ.db.settings and BJ.db.settings.cardDeck then
        savedDeck = BJ.db.settings.cardDeck
    end
    frame.currentDeckIndex = 1
    for i, deck in ipairs(cardDecks) do
        if deck.id == savedDeck then
            frame.currentDeckIndex = i
            break
        end
    end
    
    local facePreview = CreateFrame("Frame", nil, pageVis, "BackdropTemplate")
    facePreview:SetSize(60, 84)
    facePreview:SetPoint("TOP", faceLabel, "BOTTOM", 0, -5)
    facePreview:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    facePreview:SetBackdropColor(0.15, 0.15, 0.15, 1)
    facePreview:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    
    local faceTex = facePreview:CreateTexture(nil, "ARTWORK")
    faceTex:SetPoint("TOPLEFT", 2, -2)
    faceTex:SetPoint("BOTTOMRIGHT", -2, 2)
    frame.cardDeckTexture = faceTex
    frame.cardDeckPreview = facePreview
    
    -- Animation state for preview
    frame.deckAnimElapsed = 0
    frame.deckAnimFrame = 0
    frame.deckAnimInfo = nil
    
    facePreview:SetScript("OnUpdate", function(self, dt)
        if not frame.deckAnimInfo then return end
        
        frame.deckAnimElapsed = frame.deckAnimElapsed + dt
        local animInfo = frame.deckAnimInfo
        local newFrame = math.floor(frame.deckAnimElapsed / animInfo.frameTime) % animInfo.numFrames
        
        if newFrame ~= frame.deckAnimFrame then
            frame.deckAnimFrame = newFrame
            -- Vertical sprite sheet with Y-flip
            local top = (newFrame + 1) / animInfo.numFrames
            local bottom = newFrame / animInfo.numFrames
            frame.cardDeckTexture:SetTexCoord(0, 1, top, bottom)
        end
    end)
    
    -- Arrow texture for navigation
    local ARROW_TEXTURE = "Interface\\AddOns\\Chairfaces Casino\\Textures\\Widgets\\arrow_right"
    
    -- Nav buttons for card deck
    local deckPrevBtn = CreateFrame("Button", nil, pageVis, "BackdropTemplate")
    deckPrevBtn:SetSize(24, 24)
    deckPrevBtn:SetPoint("RIGHT", facePreview, "LEFT", -8, 0)
    deckPrevBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    deckPrevBtn:SetBackdropColor(0.3, 0.3, 0.3, 1)
    deckPrevBtn:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    local deckPrevTex = deckPrevBtn:CreateTexture(nil, "ARTWORK")
    deckPrevTex:SetSize(14, 14)
    deckPrevTex:SetPoint("CENTER")
    deckPrevTex:SetTexture(ARROW_TEXTURE)
    deckPrevTex:SetTexCoord(1, 0, 0, 1)  -- Flip horizontally for left arrow
    deckPrevBtn.texture = deckPrevTex
    deckPrevBtn:SetScript("OnClick", function()
        frame.currentDeckIndex = frame.currentDeckIndex - 1
        if frame.currentDeckIndex < 1 then frame.currentDeckIndex = #cardDecks end
        Lobby:UpdateCardDeckPreview()
    end)
    deckPrevBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.4, 0.4, 0.4, 1) end)
    deckPrevBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.3, 0.3, 0.3, 1) end)
    
    local deckNextBtn = CreateFrame("Button", nil, pageVis, "BackdropTemplate")
    deckNextBtn:SetSize(24, 24)
    deckNextBtn:SetPoint("LEFT", facePreview, "RIGHT", 8, 0)
    deckNextBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    deckNextBtn:SetBackdropColor(0.3, 0.3, 0.3, 1)
    deckNextBtn:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    local deckNextTex = deckNextBtn:CreateTexture(nil, "ARTWORK")
    deckNextTex:SetSize(14, 14)
    deckNextTex:SetPoint("CENTER")
    deckNextTex:SetTexture(ARROW_TEXTURE)
    deckNextBtn.texture = deckNextTex
    deckNextBtn:SetScript("OnClick", function()
        frame.currentDeckIndex = frame.currentDeckIndex + 1
        if frame.currentDeckIndex > #cardDecks then frame.currentDeckIndex = 1 end
        Lobby:UpdateCardDeckPreview()
    end)
    deckNextBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.4, 0.4, 0.4, 1) end)
    deckNextBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.3, 0.3, 0.3, 1) end)
    
    local deckName = pageVis:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    deckName:SetPoint("TOP", facePreview, "BOTTOM", 0, -3)
    frame.cardDeckName = deckName
    
    local deckSelectBtn = CreateFrame("Button", nil, pageVis, "BackdropTemplate")
    deckSelectBtn:SetSize(70, 22)
    deckSelectBtn:SetPoint("TOP", deckName, "BOTTOM", 0, -3)
    deckSelectBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    deckSelectBtn:SetBackdropColor(0.2, 0.4, 0.2, 1)
    deckSelectBtn:SetBackdropBorderColor(0.3, 0.6, 0.3, 1)
    local deckSelectText = deckSelectBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    deckSelectText:SetPoint("CENTER")
    deckSelectText:SetText("|cff00ff00Select|r")
    deckSelectBtn:SetScript("OnClick", function()
        local deck = cardDecks[frame.currentDeckIndex]
        Lobby:SelectCardDeck(deck.id)
    end)
    deckSelectBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.3, 0.5, 0.3, 1) end)
    deckSelectBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.2, 0.4, 0.2, 1) end)
    
    -- Card Back section
    local backLabel = pageVis:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    backLabel:SetPoint("TOP", deckSelectBtn, "BOTTOM", 0, -12)
    backLabel:SetText("Card Back")
    
    local cardBacks = {
        { id = "blue", name = "Blue", texture = "back_blue" },
        { id = "red", name = "Red", texture = "back_red" },
        { id = "mtg", name = "MTG", texture = "back_mtg" },
        { id = "hs", name = "Hearthstone", texture = "back_hs" },
        { id = "warcraft", name = "Warcraft", texture = "back_warcraft" },
    }
    frame.cardBacks = cardBacks
    
    local savedBack = "blue"
    if BJ.db and BJ.db.settings and BJ.db.settings.cardBack then
        savedBack = BJ.db.settings.cardBack
    end
    frame.currentBackIndex = 1
    for i, back in ipairs(cardBacks) do
        if back.id == savedBack then
            frame.currentBackIndex = i
            break
        end
    end
    
    local cardPreview = CreateFrame("Frame", nil, pageVis, "BackdropTemplate")
    cardPreview:SetSize(60, 84)
    cardPreview:SetPoint("TOP", backLabel, "BOTTOM", 0, -5)
    cardPreview:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
    cardPreview:SetBackdropColor(0.15, 0.15, 0.15, 1)
    cardPreview:SetBackdropBorderColor(0, 0.8, 0, 1)
    
    local cardTex = cardPreview:CreateTexture(nil, "ARTWORK")
    cardTex:SetPoint("TOPLEFT", 2, -2)
    cardTex:SetPoint("BOTTOMRIGHT", -2, 2)
    frame.cardBackTexture = cardTex
    
    -- Nav buttons for card back (using arrow texture)
    local prevBtn = CreateFrame("Button", nil, pageVis, "BackdropTemplate")
    prevBtn:SetSize(24, 24)
    prevBtn:SetPoint("RIGHT", cardPreview, "LEFT", -8, 0)
    prevBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    prevBtn:SetBackdropColor(0.3, 0.3, 0.3, 1)
    prevBtn:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    local prevTex = prevBtn:CreateTexture(nil, "ARTWORK")
    prevTex:SetSize(14, 14)
    prevTex:SetPoint("CENTER")
    prevTex:SetTexture(ARROW_TEXTURE)
    prevTex:SetTexCoord(1, 0, 0, 1)  -- Flip horizontally for left arrow
    prevBtn.texture = prevTex
    prevBtn:SetScript("OnClick", function()
        frame.currentBackIndex = frame.currentBackIndex - 1
        if frame.currentBackIndex < 1 then frame.currentBackIndex = #cardBacks end
        Lobby:UpdateCardBackPreview()
    end)
    prevBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.4, 0.4, 0.4, 1) end)
    prevBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.3, 0.3, 0.3, 1) end)
    
    local nextBtn = CreateFrame("Button", nil, pageVis, "BackdropTemplate")
    nextBtn:SetSize(24, 24)
    nextBtn:SetPoint("LEFT", cardPreview, "RIGHT", 8, 0)
    nextBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    nextBtn:SetBackdropColor(0.3, 0.3, 0.3, 1)
    nextBtn:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    local nextTex = nextBtn:CreateTexture(nil, "ARTWORK")
    nextTex:SetSize(14, 14)
    nextTex:SetPoint("CENTER")
    nextTex:SetTexture(ARROW_TEXTURE)
    nextBtn.texture = nextTex
    nextBtn:SetScript("OnClick", function()
        frame.currentBackIndex = frame.currentBackIndex + 1
        if frame.currentBackIndex > #cardBacks then frame.currentBackIndex = 1 end
        Lobby:UpdateCardBackPreview()
    end)
    nextBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.4, 0.4, 0.4, 1) end)
    nextBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.3, 0.3, 0.3, 1) end)
    
    local cardName = pageVis:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cardName:SetPoint("TOP", cardPreview, "BOTTOM", 0, -3)
    frame.cardBackName = cardName
    
    local selectBtn = CreateFrame("Button", nil, pageVis, "BackdropTemplate")
    selectBtn:SetSize(70, 22)
    selectBtn:SetPoint("TOP", cardName, "BOTTOM", 0, -3)
    selectBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    selectBtn:SetBackdropColor(0.2, 0.4, 0.2, 1)
    selectBtn:SetBackdropBorderColor(0.3, 0.6, 0.3, 1)
    local selectText = selectBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    selectText:SetPoint("CENTER")
    selectText:SetText("|cff00ff00Select|r")
    selectBtn:SetScript("OnClick", function()
        local back = cardBacks[frame.currentBackIndex]
        Lobby:SelectCardBack(back.id)
    end)
    selectBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.3, 0.5, 0.3, 1) end)
    selectBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.2, 0.4, 0.2, 1) end)
    
    -- Dice section
    local diceLabel = pageVis:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    diceLabel:SetPoint("TOP", selectBtn, "BOTTOM", 0, -12)
    diceLabel:SetText("Dice Style")
    
    -- Shared registry (numeric, white pips, red pips, scrimshaw texture)
    local diceStyles = BJ.DiceStyles
    frame.diceStyles = diceStyles
    
    local savedDice = "numeric"
    if BJ.db and BJ.db.settings and BJ.db.settings.diceStyle then
        savedDice = BJ.db.settings.diceStyle
    end
    frame.currentDiceIndex = 1
    for i, dice in ipairs(diceStyles) do
        if dice.id == savedDice then
            frame.currentDiceIndex = i
            break
        end
    end
    
    local dicePreview = CreateFrame("Frame", nil, pageVis, "BackdropTemplate")
    dicePreview:SetSize(48, 48)
    dicePreview:SetPoint("TOP", diceLabel, "BOTTOM", 0, -5)
    dicePreview:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    dicePreview:SetBackdropColor(0.15, 0.15, 0.15, 1)
    dicePreview:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    frame.dicePreview = dicePreview
    
    local diceTex = dicePreview:CreateTexture(nil, "ARTWORK")
    diceTex:SetPoint("TOPLEFT", 4, -4)
    diceTex:SetPoint("BOTTOMRIGHT", -4, 4)
    frame.diceTexture = diceTex
    
    -- Digit for the "numeric" style
    local diceText = dicePreview:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    diceText:SetPoint("CENTER")
    diceText:SetText("|cff0000001|r")  -- Show 1 for preview
    frame.dicePreviewText = diceText

    -- Pip overlay for the "pips" styles - a sample face 5 (TL/TR/C/BL/BR)
    local pf = 12
    local pipOffsets = {
        TL = { -pf, pf }, TR = { pf, pf }, C = { 0, 0 },
        BL = { -pf, -pf }, BR = { pf, -pf },
    }
    frame.dicePips = {}
    for _, key in ipairs({ "TL", "TR", "C", "BL", "BR" }) do
        local pip = dicePreview:CreateTexture(nil, "OVERLAY")
        pip:SetSize(9, 9)
        pip:SetPoint("CENTER", dicePreview, "CENTER", pipOffsets[key][1], pipOffsets[key][2])
        pip:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
        pip:Hide()
        frame.dicePips[key] = pip
    end
    
    -- Nav buttons for dice (using arrow texture like leaderboard)
    local ARROW_TEXTURE = "Interface\\AddOns\\Chairfaces Casino\\Textures\\Widgets\\arrow_right"
    
    local dicePrevBtn = CreateFrame("Button", nil, pageVis, "BackdropTemplate")
    dicePrevBtn:SetSize(24, 24)
    dicePrevBtn:SetPoint("RIGHT", dicePreview, "LEFT", -8, 0)
    dicePrevBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    dicePrevBtn:SetBackdropColor(0.3, 0.3, 0.3, 1)
    dicePrevBtn:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    local dicePrevTex = dicePrevBtn:CreateTexture(nil, "ARTWORK")
    dicePrevTex:SetSize(14, 14)
    dicePrevTex:SetPoint("CENTER")
    dicePrevTex:SetTexture(ARROW_TEXTURE)
    dicePrevTex:SetTexCoord(1, 0, 0, 1)  -- Flip horizontally for left arrow
    dicePrevBtn.texture = dicePrevTex
    dicePrevBtn:SetScript("OnClick", function()
        frame.currentDiceIndex = frame.currentDiceIndex - 1
        if frame.currentDiceIndex < 1 then frame.currentDiceIndex = #diceStyles end
        Lobby:UpdateDicePreview()
    end)
    dicePrevBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.4, 0.4, 0.4, 1) end)
    dicePrevBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.3, 0.3, 0.3, 1) end)
    
    local diceNextBtn = CreateFrame("Button", nil, pageVis, "BackdropTemplate")
    diceNextBtn:SetSize(24, 24)
    diceNextBtn:SetPoint("LEFT", dicePreview, "RIGHT", 8, 0)
    diceNextBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    diceNextBtn:SetBackdropColor(0.3, 0.3, 0.3, 1)
    diceNextBtn:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    local diceNextTex = diceNextBtn:CreateTexture(nil, "ARTWORK")
    diceNextTex:SetSize(14, 14)
    diceNextTex:SetPoint("CENTER")
    diceNextTex:SetTexture(ARROW_TEXTURE)
    diceNextBtn.texture = diceNextTex
    diceNextBtn:SetScript("OnClick", function()
        frame.currentDiceIndex = frame.currentDiceIndex + 1
        if frame.currentDiceIndex > #diceStyles then frame.currentDiceIndex = 1 end
        Lobby:UpdateDicePreview()
    end)
    diceNextBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.4, 0.4, 0.4, 1) end)
    diceNextBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.3, 0.3, 0.3, 1) end)
    
    local diceName = pageVis:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    diceName:SetPoint("TOP", dicePreview, "BOTTOM", 0, -3)
    frame.diceName = diceName
    
    local diceSelectBtn = CreateFrame("Button", nil, pageVis, "BackdropTemplate")
    diceSelectBtn:SetSize(70, 22)
    diceSelectBtn:SetPoint("TOP", diceName, "BOTTOM", 0, -3)
    diceSelectBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    diceSelectBtn:SetBackdropColor(0.2, 0.4, 0.2, 1)
    diceSelectBtn:SetBackdropBorderColor(0.3, 0.6, 0.3, 1)
    local diceSelectText = diceSelectBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    diceSelectText:SetPoint("CENTER")
    diceSelectText:SetText("|cff00ff00Select|r")
    diceSelectBtn:SetScript("OnClick", function()
        local dice = diceStyles[frame.currentDiceIndex]
        Lobby:SelectDiceStyle(dice.id)
    end)
    diceSelectBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.3, 0.5, 0.3, 1) end)
    diceSelectBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.2, 0.4, 0.2, 1) end)
    
    -- ========== RIGHT COLUMN (Audio, Interface, Trixie) ==========
    local rightCol = 325  -- Center of right column
    local rightLeft = 230  -- Left edge of right column

    -- Audio section
    local audioLabel = pageVis:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    audioLabel:SetPoint("TOP", pageVis, "TOPLEFT", rightCol, -20)
    audioLabel:SetText("Audio")

    local sfxBtn = CreateFrame("Button", nil, pageVis, "BackdropTemplate")
    sfxBtn:SetSize(85, 26)
    sfxBtn:SetPoint("TOPLEFT", rightLeft, -38)
    sfxBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    sfxBtn:SetBackdropColor(0.2, 0.2, 0.2, 1)
    sfxBtn:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    local sfxIcon = sfxBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sfxIcon:SetPoint("CENTER")
    sfxIcon:SetText("|cff00ff00SFX ON|r")
    frame.sfxIcon = sfxIcon
    frame.sfxBtn = sfxBtn
    sfxBtn:SetScript("OnClick", function() Lobby:ToggleSFX() end)
    sfxBtn:SetScript("OnEnter", function(self)
        if Lobby.sfxEnabled then
            self:SetBackdropColor(0.2, 0.45, 0.2, 1)  -- Brighter green hover
        else
            self:SetBackdropColor(0.3, 0.3, 0.3, 1)  -- Gray hover
        end
    end)
    sfxBtn:SetScript("OnLeave", function(self)
        if Lobby.sfxEnabled then
            self:SetBackdropColor(0.15, 0.35, 0.15, 1)  -- Green normal
        else
            self:SetBackdropColor(0.2, 0.2, 0.2, 1)  -- Gray normal
        end
    end)
    
    local voiceBtn = CreateFrame("Button", nil, pageVis, "BackdropTemplate")
    voiceBtn:SetSize(85, 26)
    voiceBtn:SetPoint("LEFT", sfxBtn, "RIGHT", 10, 0)
    voiceBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    voiceBtn:SetBackdropColor(0.2, 0.2, 0.2, 1)
    voiceBtn:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    local voiceIcon = voiceBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    voiceIcon:SetPoint("CENTER")
    voiceIcon:SetText("|cff00ff00VOICE ON|r")
    frame.voiceIcon = voiceIcon
    frame.voiceBtn = voiceBtn
    voiceBtn:SetScript("OnClick", function() Lobby:ToggleVoice() end)
    voiceBtn:SetScript("OnEnter", function(self)
        if Lobby.voiceEnabled then
            self:SetBackdropColor(0.2, 0.45, 0.2, 1)  -- Brighter green hover
        else
            self:SetBackdropColor(0.3, 0.3, 0.3, 1)  -- Gray hover
        end
    end)
    voiceBtn:SetScript("OnLeave", function(self)
        if Lobby.voiceEnabled then
            self:SetBackdropColor(0.15, 0.35, 0.15, 1)  -- Green normal
        else
            self:SetBackdropColor(0.2, 0.2, 0.2, 1)  -- Gray normal
        end
    end)
    
    -- Voice Frequency
    local voiceFreqLabel = pageVis:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    voiceFreqLabel:SetPoint("TOPLEFT", rightLeft, -72)
    voiceFreqLabel:SetText("Voice Frequency:")

    local voiceFreqValue = pageVis:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    voiceFreqValue:SetPoint("TOPRIGHT", -20, -72)
    voiceFreqValue:SetText("|cff88ff88Normal|r")
    frame.voiceFreqValue = voiceFreqValue

    local voiceFreqSlider = CreateFrame("Slider", nil, pageVis, "OptionsSliderTemplate")
    voiceFreqSlider:SetSize(180, 14)
    voiceFreqSlider:SetPoint("TOPLEFT", rightLeft, -87)
    voiceFreqSlider:SetMinMaxValues(1, 5)
    voiceFreqSlider:SetValueStep(1)
    voiceFreqSlider:SetObeyStepOnDrag(true)
    voiceFreqSlider.Low:SetText("")
    voiceFreqSlider.High:SetText("")
    voiceFreqSlider.Text:SetText("")
    frame.voiceFreqSlider = voiceFreqSlider
    
    local function UpdateVoiceFreqDisplay()
        local sliderVal = voiceFreqSlider:GetValue()
        local freqNames = { "Always", "Frequent", "Normal", "Occasional", "Rare" }
        local freqValues = { 1, 2, 3, 5, 10 }
        local freqColors = { "00ff00", "88ff88", "ffffff", "ffaa66", "ff6666" }
        voiceFreqValue:SetText("|cff" .. freqColors[sliderVal] .. freqNames[sliderVal] .. "|r")
        Lobby:SetVoiceFrequency(freqValues[sliderVal])
    end
    voiceFreqSlider:SetScript("OnValueChanged", UpdateVoiceFreqDisplay)
    
    local initFreq = Lobby:GetVoiceFrequency()
    local initSlider = initFreq == 1 and 1 or initFreq == 2 and 2 or initFreq == 3 and 3 or initFreq == 5 and 4 or 5
    voiceFreqSlider:SetValue(initSlider)
    UpdateVoiceFreqDisplay()
    
    -- Interface section
    local interfaceLabel = pageVis:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    interfaceLabel:SetPoint("TOP", pageVis, "TOPLEFT", rightCol, -124)
    interfaceLabel:SetText("Interface")

    -- Minimap slider
    local minimapLabel = pageVis:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    minimapLabel:SetPoint("TOPLEFT", rightLeft, -142)
    minimapLabel:SetText("Minimap Icon:")

    local minimapValue = pageVis:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    minimapValue:SetPoint("TOPRIGHT", -20, -142)
    minimapValue:SetText("|cff88ff881.5x|r")
    frame.minimapValue = minimapValue

    local minimapSlider = CreateFrame("Slider", nil, pageVis, "OptionsSliderTemplate")
    minimapSlider:SetSize(180, 14)
    minimapSlider:SetPoint("TOPLEFT", rightLeft, -157)
    minimapSlider:SetMinMaxValues(1.5, 5.0)
    minimapSlider:SetValueStep(0.5)
    minimapSlider:SetObeyStepOnDrag(true)
    minimapSlider.Low:SetText("1.5x")
    minimapSlider.High:SetText("5x")
    minimapSlider.Text:SetText("")
    frame.minimapSlider = minimapSlider
    
    local savedMinimapScale = 1.5
    if BJ.db and BJ.db.settings and BJ.db.settings.minimapScale then
        savedMinimapScale = BJ.db.settings.minimapScale
    end
    minimapSlider:SetValue(savedMinimapScale)
    
    local function UpdateMinimapDisplay()
        local val = minimapSlider:GetValue()
        minimapValue:SetText(string.format("|cff88ff88%.1fx|r", val))
        Lobby:SetMinimapScale(val)
    end
    minimapSlider:SetScript("OnValueChanged", UpdateMinimapDisplay)
    UpdateMinimapDisplay()
    
    -- Hide minimap checkbox
    local hideMinimapCheck = CreateFrame("CheckButton", nil, pageVis, "UICheckButtonTemplate")
    hideMinimapCheck:SetSize(22, 22)
    hideMinimapCheck:SetPoint("TOPLEFT", rightLeft, -184)
    hideMinimapCheck:SetScript("OnClick", function(self)
        local hide = self:GetChecked()
        if BJ.MinimapButton then
            if hide then BJ.MinimapButton:Hide() else BJ.MinimapButton:Show() end
        end
        if ChairfacesCasinoDB then ChairfacesCasinoDB.minimapHidden = hide end
    end)
    frame.hideMinimapCheck = hideMinimapCheck
    if ChairfacesCasinoDB and ChairfacesCasinoDB.minimapHidden then
        hideMinimapCheck:SetChecked(true)
    end

    local hideMinimapLabel = pageVis:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hideMinimapLabel:SetPoint("LEFT", hideMinimapCheck, "RIGHT", 2, 0)
    hideMinimapLabel:SetText("Hide minimap icon")

    -- Mailbox helper checkbox (the "Buy Casino Credits" button on the mail window)
    local mailHelperCheck = CreateFrame("CheckButton", nil, pageVis, "UICheckButtonTemplate")
    mailHelperCheck:SetSize(22, 22)
    mailHelperCheck:SetPoint("TOPLEFT", rightLeft, -206)
    mailHelperCheck:SetScript("OnClick", function(self)
        local show = self:GetChecked()
        if BJ.db and BJ.db.settings then BJ.db.settings.showMailHelper = show end
        if BJ.Arcade and BJ.Arcade.UpdateMailHelperVisibility then BJ.Arcade:UpdateMailHelperVisibility() end
    end)
    mailHelperCheck:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Show the 'Buy Casino Credits' button on the mail window")
        GameTooltip:Show()
    end)
    mailHelperCheck:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.mailHelperCheck = mailHelperCheck
    local mailHelperChecked = true
    if BJ.db and BJ.db.settings then mailHelperChecked = BJ.db.settings.showMailHelper ~= false end
    mailHelperCheck:SetChecked(mailHelperChecked)

    local mailHelperLabel = pageVis:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    mailHelperLabel:SetPoint("LEFT", mailHelperCheck, "RIGHT", 2, 0)
    mailHelperLabel:SetText("Mailbox credits helper")

    -- Window Scale slider
    local windowLabel = pageVis:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    windowLabel:SetPoint("TOPLEFT", rightLeft, -234)
    windowLabel:SetText("Window Scale:")

    local windowValue = pageVis:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    windowValue:SetPoint("TOPRIGHT", -20, -234)
    windowValue:SetText("|cff88ff88100%|r")
    frame.windowValue = windowValue

    local windowSlider = CreateFrame("Slider", nil, pageVis, "OptionsSliderTemplate")
    windowSlider:SetSize(180, 14)
    windowSlider:SetPoint("TOPLEFT", rightLeft, -249)
    windowSlider:SetMinMaxValues(0.6, 1.2)
    windowSlider:SetValueStep(0.05)
    windowSlider:SetObeyStepOnDrag(true)
    windowSlider.Low:SetText("60%")
    windowSlider.High:SetText("120%")
    windowSlider.Text:SetText("")
    frame.windowSlider = windowSlider

    local savedWindowScale = 1.0
    if BJ.db and BJ.db.settings and BJ.db.settings.windowScale then
        savedWindowScale = BJ.db.settings.windowScale
    end
    windowSlider:SetValue(savedWindowScale)

    local function UpdateWindowDisplayText()
        local val = windowSlider:GetValue()
        windowValue:SetText(string.format("|cff88ff88%d%%|r", math.floor(val * 100 + 0.5)))
    end
    local function ApplyWindowScale()
        local val = windowSlider:GetValue()
        Lobby:SetWindowScale(val)
    end
    windowSlider:SetScript("OnValueChanged", UpdateWindowDisplayText)
    windowSlider:SetScript("OnMouseUp", ApplyWindowScale)
    UpdateWindowDisplayText()

    -- Show Trixie section label
    local trixieLabel = pageTrix:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    trixieLabel:SetPoint("TOPLEFT", rightLeft, -292)
    trixieLabel:SetText("Show Trixie")

    -- Per-game Trixie toggles, laid out in two columns of five. Lobby keeps
    -- its legacy "showLobbyTrixie" key; every other game uses "<key>ShowTrixie".
    -- Games that mount Trixie through AttachTrixie (Hold'em, Death Roll, Bingo,
    -- Roulette, Liar's Dice, Chair's Cup) refresh live via RefreshGameTrixie;
    -- the bespoke Blackjack / Poker / High-Lo frames refresh themselves.
    local trixieGames = {
        { label = "Lobby",         key = "showLobbyTrixie", apply = function()
            Lobby:UpdateLobbyTrixieVisibility(); Lobby:UpdateHelpTrixieVisibility() end },
        { label = "Blackjack",     key = "blackjackShowTrixie", apply = function(show)
            if BJ.UI and BJ.UI.SetTrixieVisibility then BJ.UI:SetTrixieVisibility(show) end end },
        { label = "5 Card Stud",   key = "pokerShowTrixie", apply = function(show)
            if BJ.UI and BJ.UI.Poker and BJ.UI.Poker.SetTrixieVisibility then BJ.UI.Poker:SetTrixieVisibility(show) end end },
        { label = "Texas Hold'em", key = "holdemShowTrixie", apply = function(show)
            if BJ.UI and BJ.UI.Holdem and BJ.UI.Holdem.SetTrixieVisibility then BJ.UI.Holdem:SetTrixieVisibility(show) end end },
        { label = "High-Lo",       key = "hiloShowTrixie", apply = function()
            if BJ.UI and BJ.UI.HiLo and BJ.UI.HiLo.UpdateTrixieVisibility then BJ.UI.HiLo:UpdateTrixieVisibility() end end },
        { label = "Death Roll",    key = "deathrollShowTrixie", apply = function() Lobby:RefreshGameTrixie("deathroll") end },
        { label = "Bingo",         key = "bingoShowTrixie", apply = function() Lobby:RefreshGameTrixie("bingo") end },
        { label = "Roulette",      key = "rouletteShowTrixie", apply = function() Lobby:RefreshGameTrixie("roulette") end },
        { label = "Liar's Dice",   key = "liarsdiceShowTrixie", apply = function() Lobby:RefreshGameTrixie("liarsdice") end },
        { label = "Crash", key = "crashShowTrixie", apply = function() Lobby:RefreshGameTrixie("crash") end },
        { label = "Chair's Cup",   key = "derbyShowTrixie", apply = function() Lobby:RefreshGameTrixie("derby") end },
    }
    frame.trixieChecks = {}
    local TRIXIE_COL2_X = rightLeft + 112
    local trixieHalf = math.ceil(#trixieGames / 2)
    for i, g in ipairs(trixieGames) do
        local col = (i <= trixieHalf) and 0 or 1
        local row = (i <= trixieHalf) and (i - 1) or (i - trixieHalf - 1)
        local x = (col == 0) and rightLeft or TRIXIE_COL2_X
        local y = -310 - row * 22
        local cb = CreateFrame("CheckButton", nil, pageTrix, "UICheckButtonTemplate")
        cb:SetSize(22, 22)
        cb:SetPoint("TOPLEFT", x, y)
        cb:SetScript("OnClick", function(self)
            local show = self:GetChecked()
            if BJ.db and BJ.db.settings then BJ.db.settings[g.key] = show end
            if g.apply then g.apply(show) end
        end)
        local checked = true
        if BJ.db and BJ.db.settings then checked = BJ.db.settings[g.key] ~= false end
        cb:SetChecked(checked)
        local lbl = pageTrix:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        lbl:SetText(g.label)
        frame.trixieChecks[g.key] = cb
    end

    -- Select / unselect all: if everything is currently on, turn it all off,
    -- otherwise turn it all on. Updates the checkboxes and applies live.
    local trixieAllBtn = CreateFrame("Button", nil, pageTrix, "UIPanelButtonTemplate")
    trixieAllBtn:SetSize(84, 18)
    trixieAllBtn:SetPoint("TOPLEFT", rightLeft + 114, -288)
    trixieAllBtn:SetText("All On/Off")
    trixieAllBtn:SetScript("OnClick", function()
        local allOn = true
        for _, g in ipairs(trixieGames) do
            if BJ.db and BJ.db.settings and BJ.db.settings[g.key] == false then
                allOn = false
                break
            end
        end
        local newVal = not allOn
        for _, g in ipairs(trixieGames) do
            if BJ.db and BJ.db.settings then BJ.db.settings[g.key] = newVal end
            if frame.trixieChecks[g.key] then frame.trixieChecks[g.key]:SetChecked(newVal) end
            if g.apply then g.apply(newVal) end
        end
    end)

    -- Replay Intro button (was "Meet Trixie!")
    local replayIntroBtn = CreateFrame("Button", nil, pageTrix, "BackdropTemplate")
    replayIntroBtn:SetSize(180, 28)
    replayIntroBtn:SetPoint("TOPLEFT", rightLeft, -450)
    replayIntroBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    replayIntroBtn:SetBackdropColor(0.4, 0.2, 0.3, 1)
    replayIntroBtn:SetBackdropBorderColor(0.6, 0.3, 0.4, 1)
    local replayIntroText = replayIntroBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    replayIntroText:SetPoint("CENTER")
    replayIntroText:SetText("|cffff99ccReplay Intro|r")
    replayIntroBtn:SetScript("OnClick", function()
        frame:Hide()
        if Lobby.frame then Lobby.frame:Hide() end
        Lobby:ShowTrixieIntro()
    end)
    replayIntroBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.5, 0.3, 0.4, 1) end)
    replayIntroBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.4, 0.2, 0.3, 1) end)

    -- Trixie chatter: her table calls, lobby greeting, and idle banter
    local chatterCb = CreateFrame("CheckButton", nil, pageTrix, "UICheckButtonTemplate")
    chatterCb:SetSize(22, 22)
    chatterCb:SetPoint("TOPLEFT", rightLeft + 192, -452)
    chatterCb:SetScript("OnClick", function(self)
        if BJ.db and BJ.db.settings then BJ.db.settings.trixieChatter = self:GetChecked() end
    end)
    do
        local on = true
        if BJ.db and BJ.db.settings then on = BJ.db.settings.trixieChatter ~= false end
        chatterCb:SetChecked(on)
    end
    local chatterLbl = pageTrix:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    chatterLbl:SetPoint("LEFT", chatterCb, "RIGHT", 2, 0)
    chatterLbl:SetText("Trixie table calls & banter")

    -- Announce open tables in the host's party/raid chat (reaches non-addon
    -- group members); never leaves the group.
    local yellCb = CreateFrame("CheckButton", nil, pageTrix, "UICheckButtonTemplate")
    yellCb:SetSize(22, 22)
    yellCb:SetPoint("TOPLEFT", rightLeft + 192, -474)
    yellCb:SetScript("OnClick", function(self)
        if BJ.db and BJ.db.settings then
            BJ.db.settings.trixiePublicChannel = self:GetChecked() and "GROUP" or "OFF"
        end
    end)
    do
        local on = true
        if BJ.db and BJ.db.settings then
            on = (BJ.db.settings.trixiePublicChannel or "GROUP") ~= "OFF"
        end
        yellCb:SetChecked(on)
    end
    local yellLbl = pageTrix:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    yellLbl:SetPoint("LEFT", yellCb, "RIGHT", 2, 0)
    yellLbl:SetText("Announce open tables in party/raid chat")

    -- Debug section (hidden unless debug mode) - positioned below Replay Intro button
    local pokeSection = CreateFrame("Frame", nil, pageTrix)
    pokeSection:SetSize(180, 40)
    pokeSection:SetPoint("TOPLEFT", rightLeft, -488)
    frame.pokeSection = pokeSection
    
    local pokeLabel = pokeSection:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pokeLabel:SetPoint("TOPLEFT", 0, 0)
    pokeLabel:SetText("|cffff00ffDebug:|r Poke (1 in X):")
    
    local pokeInput = CreateFrame("EditBox", nil, pokeSection, "BackdropTemplate")
    pokeInput:SetSize(50, 18)
    pokeInput:SetPoint("TOPLEFT", 0, -15)
    pokeInput:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    pokeInput:SetBackdropColor(0.15, 0.15, 0.2, 1)
    pokeInput:SetBackdropBorderColor(0.5, 0.3, 0.5, 1)
    pokeInput:SetFontObject(GameFontNormalSmall)
    pokeInput:SetTextColor(1, 1, 1)
    pokeInput:SetJustifyH("CENTER")
    pokeInput:SetAutoFocus(false)
    pokeInput:SetNumeric(true)
    pokeInput:SetMaxLetters(5)
    pokeInput:SetText(tostring(Lobby:GetPokeChance()))
    pokeInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    pokeInput:SetScript("OnEnterPressed", function(self)
        local val = tonumber(self:GetText()) or 500
        if val < 1 then val = 1 end
        Lobby:SetPokeChance(val)
        self:SetText(tostring(val))
        self:ClearFocus()
    end)
    frame.pokeInput = pokeInput
    
    if not (BJ.TestMode and BJ.TestMode.enabled) then
        pokeSection:Hide()
    end
    
    -- Debug: Clear DB button (only visible in debug mode)
    local clearDbBtn = CreateFrame("Button", nil, frame, "BackdropTemplate")
    clearDbBtn:SetSize(120, 28)
    clearDbBtn:SetPoint("BOTTOM", frame, "BOTTOM", 0, 15)
    clearDbBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    clearDbBtn:SetBackdropColor(0.5, 0.2, 0.1, 1)
    clearDbBtn:SetBackdropBorderColor(0.9, 0.4, 0.2, 1)
    
    local clearDbText = clearDbBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    clearDbText:SetPoint("CENTER")
    clearDbText:SetText("|cffff9944Clear Leaderboard DB|r")
    
    clearDbBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.7, 0.3, 0.15, 1)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Clear All Leaderboard Data", 1, 0.6, 0.3)
        GameTooltip:AddLine("DEBUG: Wipes local DB and broadcasts", 1, 1, 1)
        GameTooltip:AddLine("clear command to all group members", 1, 1, 1)
        GameTooltip:Show()
    end)
    clearDbBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.5, 0.2, 0.1, 1)
        GameTooltip:Hide()
    end)
    clearDbBtn:SetScript("OnClick", function()
        StaticPopupDialogs["CASINO_CLEAR_ALL_DB"] = {
            text = "|cffff6666WARNING:|r Clear ALL leaderboard data?\n\nThis will wipe your local database AND send a clear command to all party members!\n\n|cffff9944This cannot be undone!|r",
            button1 = "Clear All",
            button2 = "Cancel",
            OnAccept = function()
                if BJ.Leaderboard then
                    BJ.Leaderboard:ClearAllData(true)
                end
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
        }
        StaticPopup_Show("CASINO_CLEAR_ALL_DB")
    end)
    
    frame.clearDbBtn = clearDbBtn
    if not (BJ.TestMode and BJ.TestMode.enabled) then
        clearDbBtn:Hide()
    end
    
    -- ===== Auto-open hosted games (the aggregate list) =====
    -- One checkbox per game: when someone hosts THAT game, its window
    -- pops open for you - only the games you tick here, no others.
    -- (GameComm:MaybeAutoOpen drives it; the derby keeps its own
    -- SigmaDerbyDB.autoOpen storage, mirrored by its in-window checkbox.)
    local aoLabel = pageAuto:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    aoLabel:SetPoint("TOPLEFT", 20, -562)
    aoLabel:SetText("|cffffd700Auto-open when someone hosts:|r")

    local function autoOpenGet(key)
        if key == "derby" then
            return (SigmaDerbyDB and SigmaDerbyDB.autoOpen) and true or false
        end
        local a = BJ.db and BJ.db.settings and BJ.db.settings.autoOpen
        return (a and a[key]) and true or false
    end
    local function autoOpenSet(key, val)
        if key == "derby" then
            SigmaDerbyDB = SigmaDerbyDB or {}
            SigmaDerbyDB.autoOpen = val
            return
        end
        BJ.db = BJ.db or ChairfacesCasinoDB or {}
        BJ.db.settings = BJ.db.settings or {}
        BJ.db.settings.autoOpen = BJ.db.settings.autoOpen or {}
        BJ.db.settings.autoOpen[key] = val or nil
    end

    frame.autoOpenChecks = {}
    for i, entry in ipairs(Lobby.gameList) do
        local col = (i % 2 == 1) and 0 or 1
        local row = math.floor((i - 1) / 2)
        local cb = CreateFrame("CheckButton", nil, pageAuto, "UICheckButtonTemplate")
        cb:SetSize(22, 22)
        cb:SetPoint("TOPLEFT", 24 + col * 210, -582 - row * 22)
        cb:SetChecked(autoOpenGet(entry.key))
        cb:SetScript("OnClick", function(self)
            autoOpenSet(entry.key, self:GetChecked() and true or false)
        end)
        local lbl = pageAuto:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        lbl:SetText(entry.name)
        frame.autoOpenChecks[entry.key] = cb
    end

    -- minimap behavior: on (default) = left-click jumps to the hosted
    -- game; off = the original always-open-the-lobby behavior
    local mmCB = CreateFrame("CheckButton", nil, pageAuto, "UICheckButtonTemplate")
    mmCB:SetSize(22, 22)
    mmCB:SetPoint("TOPLEFT", 24, -700)
    mmCB:SetChecked(not (BJ.db and BJ.db.settings and
        BJ.db.settings.minimapOpensGame == false))
    mmCB:SetScript("OnClick", function(self)
        BJ.db = BJ.db or ChairfacesCasinoDB or {}
        BJ.db.settings = BJ.db.settings or {}
        BJ.db.settings.minimapOpensGame = self:GetChecked() and true or false
    end)
    local mmLbl = pageAuto:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    mmLbl:SetPoint("LEFT", mmCB, "RIGHT", 2, 0)
    mmLbl:SetText("Minimap click opens the hosted game (off = always the lobby)")
    frame.minimapOpensGameCheck = mmCB

    -- the derby's own checkbox can change autoOpen behind our back:
    -- re-read everything whenever the panel comes up
    frame:HookScript("OnShow", function()
        for key, cb in pairs(frame.autoOpenChecks) do
            cb:SetChecked(autoOpenGet(key))
        end
        mmCB:SetChecked(not (BJ.db and BJ.db.settings and
            BJ.db.settings.minimapOpensGame == false))
    end)

    selectTab(1)
    frame:Hide()
    self.settingsFrame = frame

    -- Initialize previews
    self:UpdateCardBackPreview()
    self:UpdateCardDeckPreview()
    self:UpdateDicePreview()
end

function Lobby:UpdateCardBackPreview()
    if not self.settingsFrame then return end
    
    local frame = self.settingsFrame
    local back = frame.cardBacks[frame.currentBackIndex]
    
    frame.cardBackTexture:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\cards\\" .. back.texture)
    frame.cardBackName:SetText("|cffffffff" .. back.name .. "|r")
end

function Lobby:SelectCardBack(backId)
    -- Ensure db is initialized
    if not BJ.db then
        BJ.db = ChairfacesCasinoDB or { settings = { cardBack = "blue" } }
    end
    if not BJ.db.settings then
        BJ.db.settings = { cardBack = "blue" }
    end
    
    BJ.db.settings.cardBack = backId
    
    -- Update cards in game
    if BJ.UI and BJ.UI.Cards then
        BJ.UI.Cards:SetCardBack(backId)
    end
    
    -- Find index and update preview to show selected
    if self.settingsFrame then
        for i, back in ipairs(self.settingsFrame.cardBacks) do
            if back.id == backId then
                self.settingsFrame.currentBackIndex = i
                break
            end
        end
        self:UpdateCardBackPreview()
    end
    
    BJ:Print("Card back set to: " .. backId)
end

function Lobby:UpdateDicePreview()
    if not self.settingsFrame then return end

    local frame = self.settingsFrame
    local dice = frame.diceStyles[frame.currentDiceIndex]

    -- Reset every preview element, then show the one this style uses.
    frame.diceTexture:Hide()
    frame.dicePreviewText:Hide()
    for _, pip in pairs(frame.dicePips or {}) do pip:Hide() end

    if dice.render == "texture" and dice.folder then
        frame.diceTexture:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\dice\\" .. dice.folder .. "\\die_1")
        frame.diceTexture:Show()
        frame.dicePreview:SetBackdropColor(0.1, 0.1, 0.1, 1)
    elseif dice.render == "pips" then
        local d, p = dice.dieColor, dice.pipColor
        frame.dicePreview:SetBackdropColor(d[1], d[2], d[3], 1)
        for _, key in ipairs({ "TL", "TR", "C", "BL", "BR" }) do
            local pip = frame.dicePips[key]
            pip:SetVertexColor(p[1], p[2], p[3], 1)
            pip:Show()
        end
    else
        -- Numeric: a digit tinted with the pip color on the die-body color.
        local d = dice.dieColor or { 1, 1, 1 }
        local p = dice.pipColor or { 0, 0, 0 }
        frame.dicePreview:SetBackdropColor(d[1], d[2], d[3], 1)
        frame.dicePreviewText:SetText(string.format("|cff%02x%02x%02x", math.floor(p[1] * 255),
            math.floor(p[2] * 255), math.floor(p[3] * 255)) .. "1|r")
        frame.dicePreviewText:Show()
    end

    frame.diceName:SetText("|cffffffff" .. dice.name .. "|r")
end

function Lobby:SelectDiceStyle(styleId)
    -- Ensure db is initialized
    if not BJ.db then
        BJ.db = ChairfacesCasinoDB or { settings = {} }
    end
    if not BJ.db.settings then
        BJ.db.settings = {}
    end
    
    BJ.db.settings.diceStyle = styleId

    -- Find index and update preview to show selected
    if self.settingsFrame then
        for i, dice in ipairs(self.settingsFrame.diceStyles) do
            if dice.id == styleId then
                self.settingsFrame.currentDiceIndex = i
                break
            end
        end
        self:UpdateDicePreview()
    end
    
    BJ:Print("Dice style set to: " .. styleId)
end

function Lobby:UpdateCardDeckPreview()
    if not self.settingsFrame then return end
    
    local frame = self.settingsFrame
    local deck = frame.cardDecks[frame.currentDeckIndex]
    
    -- Check if this deck has animated cards (show Ace of Spades as preview)
    local animInfo = nil
    if deck.id == "warcraft" and BJ.UI and BJ.UI.Cards then
        animInfo = BJ.UI.Cards.animatedCards["A_spades"]
    end
    
    if animInfo then
        -- Use animated sprite sheet
        frame.cardDeckTexture:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\" .. deck.path .. "\\" .. animInfo.spriteFile)
        frame.deckAnimInfo = animInfo
        frame.deckAnimElapsed = 0
        frame.deckAnimFrame = 0
        -- Set initial frame (Y-flipped)
        local top = 1 / animInfo.numFrames
        local bottom = 0
        frame.cardDeckTexture:SetTexCoord(0, 1, top, bottom)
    else
        -- Static texture
        frame.cardDeckTexture:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\" .. deck.path .. "\\" .. deck.texture)
        frame.cardDeckTexture:SetTexCoord(0, 1, 0, 1)
        frame.deckAnimInfo = nil
    end
    
    frame.cardDeckName:SetText("|cffffffff" .. deck.name .. "|r")
end

function Lobby:SelectCardDeck(deckId)
    -- Ensure db is initialized
    if not BJ.db then
        BJ.db = ChairfacesCasinoDB or { settings = { cardDeck = "classic" } }
    end
    if not BJ.db.settings then
        BJ.db.settings = { cardDeck = "classic" }
    end
    
    BJ.db.settings.cardDeck = deckId
    
    -- Update cards system
    if BJ.UI and BJ.UI.Cards then
        BJ.UI.Cards:SetCardDeck(deckId)
    end
    
    -- Find index and update preview to show selected
    if self.settingsFrame then
        for i, deck in ipairs(self.settingsFrame.cardDecks) do
            if deck.id == deckId then
                self.settingsFrame.currentDeckIndex = i
                break
            end
        end
        self:UpdateCardDeckPreview()
    end
    
    BJ:Print("Card deck set to: " .. deckId)
end

function Lobby:SetMinimapScale(scale)
    -- Ensure db is initialized
    if not BJ.db then
        BJ.db = ChairfacesCasinoDB or { settings = {} }
    end
    if not BJ.db.settings then
        BJ.db.settings = {}
    end
    
    BJ.db.settings.minimapScale = scale
    
    -- Apply to minimap button
    if BJ.MinimapButton and BJ.MinimapButton.button then
        local baseSize = 32
        local newSize = baseSize * scale
        BJ.MinimapButton.button:SetSize(newSize, newSize)
        BJ.MinimapButton.currentScale = scale  -- Store for hover sizing
        
        -- Scale the overlay and background textures
        if BJ.MinimapButton.button.overlay then
            local overlaySize = 53 * scale
            BJ.MinimapButton.button.overlay:SetSize(overlaySize, overlaySize)
        end
        if BJ.MinimapButton.button.background then
            local bgSize = 20 * scale
            BJ.MinimapButton.button.background:SetSize(bgSize, bgSize)
        end
    end
end

function Lobby:SetWindowScale(scale)
    -- Ensure db is initialized
    if not BJ.db then
        BJ.db = ChairfacesCasinoDB or { settings = {} }
    end
    if not BJ.db.settings then
        BJ.db.settings = {}
    end
    
    BJ.db.settings.windowScale = scale
    
    -- Apply to all casino windows
    local windows = {}
    
    -- Lobby
    if self.frame then
        table.insert(windows, self.frame)
    end
    
    -- Blackjack (uses mainFrame)
    if BJ.UI and BJ.UI.mainFrame then
        table.insert(windows, BJ.UI.mainFrame)
    end
    
    -- Poker
    if BJ.UI and BJ.UI.Poker and BJ.UI.Poker.mainFrame then
        table.insert(windows, BJ.UI.Poker.mainFrame)
    end
    
    -- High-Lo (uses container as outer frame)
    if BJ.UI and BJ.UI.HiLo and BJ.UI.HiLo.container then
        table.insert(windows, BJ.UI.HiLo.container)
    end
    
    -- Settings panel
    if self.settingsFrame then
        table.insert(windows, self.settingsFrame)
    end
    
    -- Lobby Trixie
    if self.lobbyTrixie then
        table.insert(windows, self.lobbyTrixie)
    end
    
    for _, window in ipairs(windows) do
        if window and window.SetScale then
            window:SetScale(scale)
        end
    end
    
end

-- Open an auxiliary window (Settings/Leaderboard/Debts) FROM the lobby: hide
-- the lobby, show the window, and hook it (once) so closing it reopens the
-- lobby. The per-frame flag means closing that window from a game or a slash
-- command (where it wasn't opened from the lobby) won't pop the lobby.
function Lobby:OpenFromLobby(show, getFrame)
    if self.frame then self.frame:Hide() end
    self:HideHelp(true)
    show()
    local f = getFrame()
    if f then
        if not f.__lobbyReturnHooked then
            f.__lobbyReturnHooked = true
            f:HookScript("OnHide", function()
                if f.__returnToLobby then
                    f.__returnToLobby = false
                    Lobby:Show()
                end
            end)
        end
        f.__returnToLobby = true
    end
end

function Lobby:ToggleSettings()
    if not self.settingsFrame then
        self:CreateSettingsPanel()
    end
    
    if self.settingsFrame:IsShown() then
        self.settingsFrame:Hide()
    else
        self:ShowSettings()
    end
end

function Lobby:ShowSettings()
    if not self.settingsFrame then
        self:CreateSettingsPanel()
    end
    
    -- Set current index to match saved setting
    local currentBack = "blue"
    if BJ.db and BJ.db.settings and BJ.db.settings.cardBack then
        currentBack = BJ.db.settings.cardBack
    end
    for i, back in ipairs(self.settingsFrame.cardBacks) do
        if back.id == currentBack then
            self.settingsFrame.currentBackIndex = i
            break
        end
    end
    
    -- Update deck selection to match current setting
    local currentDeck = "classic"
    if BJ.db and BJ.db.settings and BJ.db.settings.cardDeck then
        currentDeck = BJ.db.settings.cardDeck
    end
    for i, deck in ipairs(self.settingsFrame.cardDecks) do
        if deck.id == currentDeck then
            self.settingsFrame.currentDeckIndex = i
            break
        end
    end
    
    self:UpdateCardBackPreview()
    self:UpdateCardDeckPreview()
    self:UpdateAudioControls()
    
    -- Update debug section visibility
    if self.settingsFrame.pokeSection then
        if BJ.TestMode and BJ.TestMode.enabled then
            self.settingsFrame.pokeSection:Show()
            -- Update the poke input value
            if self.settingsFrame.pokeInput then
                self.settingsFrame.pokeInput:SetText(tostring(self:GetPokeChance()))
            end
        else
            self.settingsFrame.pokeSection:Hide()
        end
    end
    
    self.settingsFrame:Show()
end

-- ========== AUDIO SYSTEM ==========
Lobby.sfxEnabled = true
Lobby.voiceEnabled = true

function Lobby:InitializeAudio()
    -- Ensure db is initialized
    if not BJ.db then
        BJ.db = ChairfacesCasinoDB or { settings = {} }
    end
    if not BJ.db.settings then
        BJ.db.settings = {}
    end
    
    -- Load saved settings
    if BJ.db.settings.sfxEnabled ~= nil then
        self.sfxEnabled = BJ.db.settings.sfxEnabled
    else
        self.sfxEnabled = true  -- Default SFX on
    end
    
    if BJ.db.settings.voiceEnabled ~= nil then
        self.voiceEnabled = BJ.db.settings.voiceEnabled
    else
        self.voiceEnabled = true  -- Default Voice on
    end
end

function Lobby:ToggleSFX()
    self.sfxEnabled = not self.sfxEnabled
    self:SaveAudioSettings()
    self:UpdateAudioControls()
end

function Lobby:ToggleVoice()
    self.voiceEnabled = not self.voiceEnabled
    self:SaveAudioSettings()
    self:UpdateAudioControls()
end

function Lobby:SaveAudioSettings()
    if not BJ.db then
        BJ.db = ChairfacesCasinoDB or { settings = {} }
    end
    if not BJ.db.settings then
        BJ.db.settings = {}
    end
    
    BJ.db.settings.sfxEnabled = self.sfxEnabled
    BJ.db.settings.voiceEnabled = self.voiceEnabled
end

function Lobby:UpdateAudioControls()
    if not self.settingsFrame then return end
    
    local frame = self.settingsFrame
    
    -- Update SFX button - green background when ON
    if frame.sfxBtn then
        if self.sfxEnabled then
            frame.sfxIcon:SetText("|cffffffff SFX ON|r")
            frame.sfxBtn:SetBackdropColor(0.15, 0.35, 0.15, 1)
            frame.sfxBtn:SetBackdropBorderColor(0.3, 0.7, 0.3, 1)
        else
            frame.sfxIcon:SetText("|cffaaaaaa SFX OFF|r")
            frame.sfxBtn:SetBackdropColor(0.2, 0.2, 0.2, 1)
            frame.sfxBtn:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
        end
    end
    
    -- Update Voice button
    if frame.voiceBtn then
        if self.voiceEnabled then
            frame.voiceIcon:SetText("|cffffffff VOICE ON|r")
            frame.voiceBtn:SetBackdropColor(0.15, 0.35, 0.15, 1)
            frame.voiceBtn:SetBackdropBorderColor(0.3, 0.7, 0.3, 1)
        else
            frame.voiceIcon:SetText("|cffaaaaaa VOICE OFF|r")
            frame.voiceBtn:SetBackdropColor(0.2, 0.2, 0.2, 1)
            frame.voiceBtn:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
        end
    end
end

-- Play sound effects (called from game code)
function Lobby:PlayBustSound()
    if not self.sfxEnabled then return end
    if not self:IsAnyCasinoWindowOpen() then return end
    PlaySound(8959, "SFX")
end

function Lobby:PlayWinSound()
    if not self.sfxEnabled then return end
    -- Only play sounds if a casino window is actually open
    if not self:IsAnyCasinoWindowOpen() then return end
    local soundFile = "Interface\\AddOns\\Chairfaces Casino\\Sounds\\fanfare.ogg"
    PlaySoundFile(soundFile, "SFX")
end

-- Check if any casino window is open
function Lobby:IsAnyCasinoWindowOpen()
    local UI = BJ.UI
    if not UI then return false end
    
    -- Check lobby
    if self.frame and self.frame:IsShown() then return true end
    
    -- Check blackjack
    if UI.mainFrame and UI.mainFrame:IsShown() then return true end
    
    -- Check poker
    if UI.Poker and UI.Poker.mainFrame and UI.Poker.mainFrame:IsShown() then return true end

    -- Check hold'em
    if UI.Holdem and UI.Holdem.mainFrame and UI.Holdem.mainFrame:IsShown() then return true end

    -- Check hi-lo
    if UI.HiLo and UI.HiLo.frame and UI.HiLo.frame:IsShown() then return true end

    -- Every other game window uses module.frame — a window missing here is a
    -- muted game (all Lobby:Play*Sound calls gate on this function).
    for _, mod in ipairs({ UI.DeathRoll, UI.Bingo, UI.Roulette, UI.LiarsDice,
                           UI.Crash, UI.Slots, UI.VideoPoker, UI.Debts }) do
        if mod and mod.frame and mod.frame:IsShown() then return true end
    end

    -- Derby lives in its own global frame
    if SigmaDerbyFrame and SigmaDerbyFrame:IsShown() then return true end

    return false
end

function Lobby:PlayShuffleSound()
    if not self.sfxEnabled then return end
    if not self:IsAnyCasinoWindowOpen() then return end
    local soundFile = "Interface\\AddOns\\Chairfaces Casino\\Sounds\\shuffle.ogg"
    PlaySoundFile(soundFile, "SFX")
end

function Lobby:PlayCardSound()
    if not self.sfxEnabled then return end
    if not self:IsAnyCasinoWindowOpen() then return end
    local soundFile = "Interface\\AddOns\\Chairfaces Casino\\Sounds\\flycard.ogg"
    PlaySoundFile(soundFile, "SFX")
end

-- Trixie voice lines (play at ~25% chance)
function Lobby:PlayTrixieIntroVoice()
    if not self.voiceEnabled then return end
    local soundFile = "Interface\\AddOns\\Chairfaces Casino\\Sounds\\Trixie\\trix_intro.ogg"
    local willPlay, soundHandle = PlaySoundFile(soundFile, "SFX")
    if willPlay then
        self.introSoundHandle = soundHandle
    end
end

function Lobby:StopTrixieIntroVoice()
    if self.introSoundHandle then
        StopSound(self.introSoundHandle)
        self.introSoundHandle = nil
    end
end

--[[
    CENTRAL TRIXIE VOICE POOLS
    Every situation maps to a list of .ogg basenames in Sounds\Trixie\. Record
    any subset you like - a missing file just no-ops in PlaySoundFile, so pools
    can grow as you add clips. Add a new basename here and it plays as soon as
    the file exists. Existing recorded clips (trix_woohoo/cheer*/bad*/bust*/
    blackjack) are kept in their pools for backward compatibility.
]]
-- category = how many clips exist (trix_<cat>1 .. trix_<cat>N in Sounds\Trixie).
-- Bump the number here AND add the matching lines to tools/gen_trixie_voices.py,
-- then re-run it, to give her more variety. A too-high count is harmless
-- (missing files just no-op). Filenames are trix_<category><index>.ogg/.mp3.
Lobby.TRIXIE_VOICE = {
    -- Counts are synced to the clips ACTUALLY on disk via
    -- `gen_trixie_voices.py --counts-disk` (batches 1-3 of the ~10x expansion;
    -- batch 3 hit the monthly budget, so poker_fold/crash_high/tourney_* still
    -- have 19 clips queued for the next quota reset).
    -- lobby / ambient
    greet = 40, banter = 52, bye = 32,
    -- generic outcomes, shared by every game
    win = 52, lose = 52, bust = 36, blackjack = 32,
    -- big moments
    jackpot = 32, bigwin = 32,
    -- money changing hands
    debt = 32, paid = 26,
    -- per-game "table just opened" announcements (keyed open_<gameKey>)
    open_blackjack = 24, open_poker = 24, open_holdem = 24, open_hilo = 24,
    open_deathroll = 24, open_liarsdice = 24, open_bingo = 24,
    open_roulette = 24, open_crash = 24,
    -- game-specific dramatic moments
    deathroll_bust = 26, crash_bail = 26, crash_boom = 26,
    deathroll_close = 24, roulette_nobets = 24, bingo_win = 24,
    liarsdice_challenge = 24, liarsdice_bluff = 24,
    -- card-game moments
    bj_dealerbust = 24, bj_push = 24, bj_double = 24, poker_showdown = 24,
    poker_fold = 23,
    -- crash moments
    crash_takeoff = 24, crash_flyaway = 24, crash_high = 18,
    -- Hold'em tournament
    tourney_champ = 18, tourney_bustout = 18,
    -- table flow
    turn_nudge = 24, countdown = 24,
}

-- Play a random clip from a category. MUTE (voiceEnabled) is ALWAYS honored.
-- FREQUENCY (voiceFrequency -> ShouldPlayVoice) gates every line EXCEPT when
-- opts.noFreq is set (used for the game-open call, which must reach the group
-- reliably). opts.cd = per-category cooldown (seconds). A GLOBAL cooldown keeps
-- Trixie to one line at a time, so chained events (pay a debt, then close the
-- window) can't stack two or three overlapping voices. Returns true only if a
-- clip actually started playing.
Lobby.lastVoiceAt = {}
Lobby.GLOBAL_VOICE_CD = 4  -- min seconds between ANY two spoken lines (~clip length)
function Lobby:PlayTrixieVoice(cat, opts)
    if not self.voiceEnabled then return false end          -- mute (always)
    opts = opts or {}
    if not opts.noFreq and not self:ShouldPlayVoice() then return false end  -- frequency
    local n = self.TRIXIE_VOICE[cat]
    if not n or n < 1 then return false end
    local now = GetTime()
    -- one line at a time (never overlap/stack)
    if self.lastVoiceGlobal and (now - self.lastVoiceGlobal) < self.GLOBAL_VOICE_CD then
        return false
    end
    -- per-category cooldown
    if opts.cd and self.lastVoiceAt[cat] and (now - self.lastVoiceAt[cat]) < opts.cd then
        return false
    end
    local base = "Interface\\AddOns\\Chairfaces Casino\\Sounds\\Trixie\\trix_" ..
        cat .. math.random(1, n)
    -- .ogg first (hand-recorded), then .mp3 (auto-generated from ElevenLabs).
    -- PlaySoundFile returns willPlay=false for a missing file without erroring.
    local willPlay = PlaySoundFile(base .. ".ogg", "SFX")
    if not willPlay then willPlay = PlaySoundFile(base .. ".mp3", "SFX") end
    if willPlay then
        self.lastVoiceGlobal = now
        self.lastVoiceAt[cat] = now
        return true
    end
    return false
end

-- Back-compat wrappers: the games call these by name all over the codebase.
function Lobby:PlayTrixieBlackjackVoice() self:PlayTrixieVoice("blackjack") end
function Lobby:PlayTrixieBadVoice()       self:PlayTrixieVoice("lose") end
function Lobby:PlayTrixieBustVoice()      self:PlayTrixieVoice("bust") end
function Lobby:PlayTrixieWoohooVoice()    self:PlayTrixieVoice("win") end

function Lobby:PlayGameStartSound()
    local soundFile = "Interface\\AddOns\\Chairfaces Casino\\Sounds\\chips.ogg"
    PlaySoundFile(soundFile, "SFX")
end

--[[
    TRIXIE THE HOST - SCRIPTED CHATTER
    Trixie barks out every table that opens on the addon network (by name and
    host), drops a greeting when you open the lobby, and tosses the odd bit of
    idle banter while you loiter. All gated by db.settings.trixieChatter
    (default on) and throttled so she's flavor, never spam.
]]

-- Coloured chat line in Trixie's voice. Routes to chat + the casino log.
function Lobby:TrixieSay(text)
    BJ:Print("|cffff77ccTrixie:|r |cffffe6f5" .. text .. "|r")
end

function Lobby:TrixieChatterOn()
    if BJ.db and BJ.db.settings and BJ.db.settings.trixieChatter == false then return false end
    return true
end

-- Called from GameComm when any game's TABLE_OPEN arrives (never for your own
-- broadcast - the comm preamble self-filters). displayName is the game's
-- user-facing name; hostName is the opener.
Lobby.lastTableCall = {}
Lobby.TABLE_CALL_LINES = {
    "Heads up, sugar - <host> just threw open a <game> table! Grab a seat before it fills up.",
    "Ding ding ding! <host> is hostin' <game>. Bring your gold and your nerve.",
    "Ooooh, <host> opened up <game>! You feelin' lucky tonight, hon?",
    "<host>'s <game> table is LIVE. Don't make me come find you.",
    "Fresh <game> table, courtesy of <host> - the chips are waitin', darlin'.",
    "Word on the floor: <host> is runnin' <game>. Get in there!",
    "<game>, hosted by <host>, now takin' all comers. The house says hi.",
    "Step right up! <host> just racked 'em for a round of <game>.",
}
-- Returns true if Trixie SPOKE a table-open line (so the caller can skip the
-- fallback chime). The chat line is gated by the chatter toggle; the spoken
-- game-specific announcement is gated by voice mute + frequency.
function Lobby:TrixieAnnounceTable(displayName, hostName, gameKey)
    if not displayName then return false end
    local key = gameKey or displayName
    local now = GetTime()
    local last = self.lastTableCall[key]
    if last and (now - last) < 60 then return false end   -- one call per game per minute
    self.lastTableCall[key] = now
    if self:TrixieChatterOn() then
        local host = hostName and (hostName:match("^([^-]+)") or hostName) or "Somebody"
        local line = self.TABLE_CALL_LINES[math.random(1, #self.TABLE_CALL_LINES)]
        line = line:gsub("<host>", host):gsub("<game>", displayName)
        self:TrixieSay(line)
    end
    -- "Blackjack's open!" - a game-specific spoken call so other addon holders
    -- in the group/raid hear a table went live. NOT gated by the frequency
    -- slider (still respects mute) so the alert is reliable.
    return self:PlayTrixieVoice("open_" .. (gameKey or ""), { noFreq = true })
end

-- A one-liner when you open the lobby, throttled so re-opening isn't chatty.
Lobby.GREETING_LINES = {
    "Well look who's back! Pull up a chair, the felt's still warm.",
    "Welcome to Chairface's, hon. Tables are hot tonight - go make some bad decisions.",
    "There's my favorite high roller. What are we losin' - I mean WINNIN' - today?",
    "Doors are open, drinks are flowin'. Pick your poison off the board.",
    "Evenin', sugar. The house always wins... but tonight it could be your house.",
    "You hear that? That's the sound of gold changin' hands. Let's add yours.",
}
function Lobby:TrixieGreeting()
    if not self:TrixieChatterOn() then return end
    local now = GetTime()
    if self.lastGreeting and (now - self.lastGreeting) < 600 then return end
    self.lastGreeting = now
    self:TrixieSay(self.GREETING_LINES[math.random(1, #self.GREETING_LINES)])
    self:PlayTrixieVoice("greet")
end

-- Idle banter: while the lobby is up, she occasionally pipes up. Started on
-- Show, self-cancels when the lobby hides.
Lobby.BANTER_LINES = {
    "Still browsin'? The chips don't stack themselves, darlin'.",
    "Psst - Death Roll's quick if you're feelin' brave. Or foolish. Same thing.",
    "I once saw a gnome win the mega on a two-copper bet. Could be you.",
    "House rule number one: it's only gamblin' if you stop while you're ahead.",
    "That zeppelin in Crash? She always blows. Question is when you jump.",
    "Fancy a spin on Azeroth Riches? The pots are lookin' plump tonight.",
    "No rush, hon. The tables'll still be riggeddd- I mean, RUNNING, when you're ready.",
}
function Lobby:StartBanterTicker()
    if self.banterTicker then return end
    self.banterTicker = C_Timer.NewTicker(75, function()
        if not (self.frame and self.frame:IsShown()) then
            if self.banterTicker then self.banterTicker:Cancel(); self.banterTicker = nil end
            return
        end
        if not self:TrixieChatterOn() then return end
        if math.random(1, 100) > 40 then return end   -- ~40% of ticks
        self:TrixieSay(self.BANTER_LINES[math.random(1, #self.BANTER_LINES)])
        self:PlayTrixieVoice("banter")
    end)
end
function Lobby:StopBanterTicker()
    if self.banterTicker then self.banterTicker:Cancel(); self.banterTicker = nil end
end

-- ========== LOG WINDOW ==========
function Lobby:CreateLogWindow()
    if self.logFrame then return end
    
    local frame = CreateFrame("Frame", "ChairfacesCasinoLog", UIParent, "BackdropTemplate")
    frame:SetSize(350, 200)
    frame:SetPoint("BOTTOMLEFT", 20, 200)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    frame:SetFrameStrata("MEDIUM")
    frame:SetResizable(true)
    frame:SetResizeBounds(200, 100, 600, 400)
    
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    frame:SetBackdropColor(0.05, 0.05, 0.08, 0.9)
    frame:SetBackdropBorderColor(0.4, 0.35, 0.2, 1)
    
    -- Title bar
    local titleBar = CreateFrame("Frame", nil, frame)
    titleBar:SetHeight(20)
    titleBar:SetPoint("TOPLEFT", 2, -2)
    titleBar:SetPoint("TOPRIGHT", -2, -2)
    
    local titleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    titleText:SetPoint("LEFT", 8, 0)
    titleText:SetText("|cffffd700Casino Log|r")
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetSize(20, 20)
    closeBtn:SetPoint("TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)
    
    -- Clear button
    local clearBtn = CreateFrame("Button", nil, frame, "BackdropTemplate")
    clearBtn:SetSize(50, 16)
    clearBtn:SetPoint("TOPRIGHT", closeBtn, "TOPLEFT", -5, -2)
    clearBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    clearBtn:SetBackdropColor(0.3, 0.3, 0.3, 1)
    clearBtn:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    
    local clearText = clearBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    clearText:SetPoint("CENTER")
    clearText:SetText("Clear")
    
    clearBtn:SetScript("OnClick", function()
        Lobby:ClearLog()
    end)
    
    -- ScrollingMessageFrame supports |H...|h hyperlinks (FontString does not)
    local messageFrame = CreateFrame("ScrollingMessageFrame", nil, frame)
    messageFrame:SetPoint("TOPLEFT", 8, -24)
    messageFrame:SetPoint("BOTTOMRIGHT", -8, 8)
    messageFrame:SetFontObject("GameFontNormalSmall")
    messageFrame:SetJustifyH("LEFT")
    messageFrame:SetMaxLines(100)
    messageFrame:SetFading(false)
    messageFrame:SetHyperlinksEnabled(true)
    messageFrame:EnableMouseWheel(true)
    messageFrame:SetScript("OnMouseWheel", function(self, delta)
        if delta > 0 then
            if IsShiftKeyDown() then self:ScrollToTop() else self:ScrollUp() end
        else
            if IsShiftKeyDown() then self:ScrollToBottom() else self:ScrollDown() end
        end
    end)
    messageFrame:SetScript("OnHyperlinkClick", function(self, link, text, button)
        local linkType, game = strsplit(":", link)
        if linkType == "casinolink" then
            if game == "hilo" and BJ.UI and BJ.UI.HiLo then BJ.UI.HiLo:Show()
            elseif game == "blackjack" and BJ.UI and BJ.UI.Show then BJ.UI:Show()
            elseif game == "poker" and BJ.UI and BJ.UI.Poker then BJ.UI.Poker:Show()
            end
        else
            SetItemRef(link, text, button, self)
        end
    end)

    frame.messageFrame = messageFrame

    -- Resize handle
    local resizeBtn = CreateFrame("Button", nil, frame)
    resizeBtn:SetSize(16, 16)
    resizeBtn:SetPoint("BOTTOMRIGHT", -2, 2)
    resizeBtn:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeBtn:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeBtn:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")

    resizeBtn:SetScript("OnMouseDown", function()
        frame:StartSizing("BOTTOMRIGHT")
    end)
    resizeBtn:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
    end)

    frame:Hide()
    self.logFrame = frame
end

function Lobby:AddLogMessage(msg)
    if not self.logFrame then
        self:CreateLogWindow()
    end
    self.logFrame.messageFrame:AddMessage(tostring(msg))
    self.logFrame.messageFrame:ScrollToBottom()
end

function Lobby:ClearLog()
    if not self.logFrame then return end
    self.logFrame.messageFrame:Clear()
end

function Lobby:ShowLog()
    if not self.logFrame then
        self:CreateLogWindow()
    end
    self.logFrame:Show()
end

function Lobby:HideLog()
    if self.logFrame then
        self.logFrame:Hide()
    end
end

function Lobby:ToggleLog()
    if not self.logFrame then
        self:CreateLogWindow()
    end
    if self.logFrame:IsShown() then
        self.logFrame:Hide()
    else
        self.logFrame:Show()
    end
end

--[[
    HELP PANEL
    Shows Trixie explaining game rules with scrollable content
]]

-- Help text content
Lobby.helpContent = {
    blackjack = {
        title = "Blackjack",
        text = [[|cffffd700Welcome to Blackjack!|r

|cff88ffffObjective:|r
Beat the dealer by getting a hand value closer to 21 without going over.

|cff88ffffCard Values:|r
- Number cards (2-10): Face value
- Face cards (J, Q, K): 10 points
- Aces: 1 or 11 points (whichever is better)

|cff88ffffHow to Play:|r
1. The host opens a table and sets the ante
2. Players join by clicking ANTE
3. Everyone gets 2 cards; dealer shows one card face-up
4. On your turn, choose:
   - |cff00ff00HIT|r: Take another card
   - |cff00ff00STAND|r: Keep your current hand
   - |cff00ff00DOUBLE|r: Double your bet, take one card, then stand
   - |cff00ff00SPLIT|r: If you have a pair, split into two hands

|cff88ffffWinning:|r
- Get closer to 21 than the dealer without busting
- |cffffd700Blackjack|r (Ace + 10-value card) pays 3:2
- Regular wins pay 1:1
- Tie (Push) returns your bet

|cff88ffffDealer Rules (H17 vs S17):|r
The host chooses one of two dealer rules:
- |cff00ff00H17|r: Dealer HITS on Soft 17 (Ace counted as 11)
- |cff00ff00S17|r: Dealer STANDS on Soft 17
Both rules: Dealer always stands on hard 17+ and hits on 16 or less.
S17 is slightly better for players.

|cff88ffffSpecial Rules:|r
- |cffffd7005-Card Charlie|r: 5 cards without busting is an automatic win!
- Split Aces only get one card each and pay 1:1

|cffff8888Remember:|r This is for fun! Trade gold honorably with other players to settle bets.]]
    },
    poker = {
        title = "5 Card Stud",
        text = [[|cffffd700Welcome to 5 Card Stud Poker!|r

|cff88ffffObjective:|r
Make the best 5-card poker hand and win the pot through betting or showdown.

|cff88ffffHand Rankings (Best to Worst):|r
1. |cffffd700Royal Flush|r - A, K, Q, J, 10 of same suit
2. |cffffd700Straight Flush|r - 5 consecutive cards, same suit
3. |cffffd700Four of a Kind|r - 4 cards of same rank
4. |cffffd700Full House|r - 3 of a kind + a pair
5. |cffffd700Flush|r - 5 cards of same suit
6. |cffffd700Straight|r - 5 consecutive cards
7. |cffffd700Three of a Kind|r - 3 cards of same rank
8. |cffffd700Two Pair|r - 2 different pairs
9. |cffffd700One Pair|r - 2 cards of same rank
10. |cffffd700High Card|r - Highest card wins

|cff88ffffHow to Play:|r
1. Host opens table, sets ante and max raise
2. Players join by clicking JOIN
3. Everyone antes and gets one card face-down
4. Four betting rounds, each with a new face-up card
5. After all cards are dealt, showdown determines winner

|cff88ffffBetting Options:|r
- |cff00ff00CHECK|r: Pass (if no bet to call)
- |cff00ff00CALL|r: Match the current bet
- |cff00ff00RAISE|r: Increase the bet
- |cffff4444FOLD|r: Give up your hand and bets

|cff88ffffTips:|r
- Watch opponents' face-up cards for clues
- Fold weak hands early to save gold
- Bluffing can work, but be careful!

|cffff8888Remember:|r This is for fun! Trade gold honorably with other players to settle bets.]]
    },
    hilo = {
        title = "High-Lo",
        text = [[|cffffd700Welcome to High-Lo!|r

|cff88ffffObjective:|r
Roll the highest number to win gold from the player with the lowest roll!

|cff88ffffHow to Play:|r
1. One player hosts and sets the max roll value
2. Other players click JOIN to enter the game
3. When ready, host clicks START
4. Everyone types /roll X (or click the Roll button)
5. Highest roller wins the difference from lowest roller

|cff88ffffExample:|r
- Max roll is set to 100
- Alice rolls 82, Bob rolls 45, Carol rolls 67
- Alice |cff00ff00wins|r and Bob |cffff4444loses|r
- |cffffd70082 - 45 = 37g|r
- Bob pays Alice 37 gold!

|cff88ffffSettings:|r
- |cffffd700Max Roll|r: The maximum number for /roll (default 100)
- |cffffd700Join Timer|r: Optional countdown for join phase (0 = manual start)

|cff88ffffRules:|r
- All players have 2 minutes to roll
- Players who don't roll in time are skipped
- If only one person rolls, no settlement occurs
- Ties for high or low trigger a /roll 100 tiebreaker

|cffff8888Remember:|r This is for fun! Trade gold honorably with other players to settle bets.]]
    },
    holdem = {
        title = "Texas Hold'em",
        text = [[|cffffd700Welcome to Texas Hold'em!|r

|cff88ffffObjective:|r
Make the best 5-card hand from your 2 hole cards and the 5 community cards.

|cff88ffffHow to Play:|r
1. Host opens the table and sets the blinds
2. Players join; the dealer button rotates each hand
3. Everyone gets 2 face-down hole cards
4. Betting rounds: pre-flop, flop (3 cards), turn, river
5. Showdown - best 5 of your 7 cards wins the pot

|cff88ffffBetting Options:|r
- |cff00ff00CHECK|r: Pass (if no bet to call)
- |cff00ff00CALL|r: Match the current bet
- |cff00ff00RAISE|r: Increase the bet
- |cffff4444FOLD|r: Give up your hand and bets

|cff88ffffHand Rankings (Best to Worst):|r
1. |cffffd700Royal Flush|r - A, K, Q, J, 10 of same suit
2. |cffffd700Straight Flush|r - 5 consecutive cards, same suit
3. |cffffd700Four of a Kind|r - 4 cards of same rank
4. |cffffd700Full House|r - 3 of a kind + a pair
5. |cffffd700Flush|r - 5 cards of same suit
6. |cffffd700Straight|r - 5 consecutive cards
7. |cffffd700Three of a Kind|r - 3 cards of same rank
8. |cffffd700Two Pair|r - 2 different pairs
9. |cffffd700One Pair|r - 2 cards of same rank
10. |cffffd700High Card|r - Highest card wins

|cff88ffffTips:|r
- Position matters: acting last is an advantage
- Suited connectors and pairs play well multiway
- Don't chase draws when the price is wrong!

|cffff8888Remember:|r This is for fun! Trade gold honorably with other players to settle bets.]]
    },
    deathroll = {
        title = "Death Roll",
        text = [[|cffffd700Welcome to Death Roll!|r

|cff88ffffObjective:|r
Don't roll the 1. Whoever rolls it pays the other player the stake.

|cff88ffffHow to Play:|r
1. The host sets the stake and the first roll ceiling
   (defaults to 10x the stake - groups have their own traditions)
2. One opponent clicks ACCEPT to take the seat
3. The host rolls first: /roll <ceiling> (or click ROLL)
4. Each roll sets the next player's maximum
5. Rolling a |cffff44441|r loses - pay the winner the stake!

|cff88ffffExample:|r
- Stake 100g, first roll 1-1000
- Host rolls 412, opponent rolls 1-412 and gets 87
- Host rolls 1-87... down and down until someone hits 1

|cff88ffffFair Play:|r
Rolls are real server-verified /rolls that everyone in the
group can see in chat - no addon trust required.

|cffff8888Remember:|r This is for fun! Trade gold honorably with other players to settle bets.]]
    },
    bingo = {
        title = "Bingo",
        text = [[|cffffd700Welcome to Bingo!|r

|cff88ffffObjective:|r
Be the first to complete a line - across, down, or diagonal.

|cff88ffffHow to Play:|r
1. The host opens the game and sets the card price
2. Players buy a card (everyone can see everyone's card)
3. The host starts the draw - numbers are called automatically
4. Your card daubs itself as numbers come up
5. First completed line wins the whole pot!

|cff88ffffThe Card:|r
- 5x5 grid: B (1-15), I (16-30), N (31-45), G (46-60), O (61-75)
- The center square is FREE
- Ties split the pot evenly

|cff88ffffFair Play:|r
Cards and the draw order come from a shared seed, so every
player's addon shows identical cards and calls.

|cffff8888Remember:|r This is for fun! Trade gold honorably with other players to settle bets.]]
    },
    roulette = {
        title = "Roulette",
        text = [[|cffffd700Welcome to Roulette!|r

|cff88ffffObjective:|r
Bet on where the ball lands. The host is the bank; winners collect
from the host, losers pay the host.

|cff88ffffHow to Play:|r
1. The host opens the table, setting the chip value and how
   many chips each player may place
2. Players JOIN, then left-click board spots to stack chips
   (right-click takes a chip back)
3. The host calls the spin - no more bets!
4. The wheel and ball run the same animation on every screen,
   and the ball lands on the same number for everyone
5. Winners are paid by the odds; the host can spin again or close

|cff88ffffBets and Payouts:|r
- Straight number (including 0): |cffffd70035:1|r
- Red/Black, Dozens and columns: |cffffd7002:1|r
- Odd/Even, 1-18/19-36: |cffffd7001:1|r
- Zero wins only straight bets on 0 - every outside bet loses

|cff88ffffFair Play:|r
This is a European wheel (single zero). The winning number is
computed from a seed the host broadcasts, with the same math on
every client - the host cannot pick the result.

|cffff8888Remember:|r This is for fun! Trade gold honorably with other players to settle bets.]]
    },
    liarsdice = {
        title = "Liar's Dice",
        text = [[|cffffd700Welcome to Liar's Dice!|r

|cff88ffffObjective:|r
Be the last player holding dice. Everyone rolls in secret and bluffs
about how many of each face are hidden across ALL the cups on the table.

|cff88ffffHow to Play:|r
1. The host opens a table (buy-in) and players JOIN. Everyone starts
   with 3 dice (the host can bump the table up to 5).
2. Each round every player is dealt a hidden hand - you can see only
   your own dice.
3. On your turn you must either RAISE the bid or CALL LIAR:
   - A bid is a claim about the whole table, e.g. "three 5s" means at
     least three 5s exist among everyone's dice.
   - A raise must beat the standing bid: a higher count of any face, or
     the same count of a higher face.
4. Instead of raising you can CALL LIAR on the previous bid. All cups
   lift and the bid face is counted:
   - If there are at least as many as bid, the bid holds and the
     |cffff4444caller|r loses a die.
   - If there are fewer, the |cffff4444bidder|r loses a die.
5. Lose all your dice and you're out. Last player standing wins the pot.

|cff88ffffOnes Are Wild:|r
When the host enables it (default), every |cffffd7001|r counts as the
face in the current bid - so totals run higher than you'd expect. You
cannot bid ones while they're wild.

|cff88ffffFair Play:|r
The host deals from a seed that is revealed the moment a challenge is
called, so every player can verify the hand they were dealt was honest
and nobody could peek at your cup.

|cffff8888Remember:|r This is for fun! Trade gold honorably with other players to settle bets.]]
    },
    crash = {
        title = "Crash",
        text = [[|cffffd700Welcome to Crash!|r

|cff88ffffObjective:|r
A GAME OF CHICKEN. Everyone antes into a pot and boards a goblin
zeppelin that is 100% guaranteed to explode - the only question is
when. Parachute out before the blast, but AFTER everyone else: the
last rider to jump takes the whole pot.

|cff88ffffHow to Play:|r
1. The host opens the table and sets the ante; the host is the
   pilot - they know the fate, so they do not ride.
2. Board by anteing into the pot. You can set an |cff00ff00auto-jump
   distance|r (e.g. 450m) - it fires with zero lag the instant the
   odometer reaches it, exactly like clicking that tick yourself.
3. The host LAUNCHES: boarding locks and the zeppelin leaves the tower.
4. The odometer climbs - 100m in the first 5 seconds, then the sky
   is the limit. Smash |cffff4444JUMP!|r any time. Jumping realizes
   nothing by itself: it just stakes your claim as the latest one out.
5. When she blows, everyone still aboard loses their ante to the pot.
   Among the jumpers, the LAST tick out wins it all (a tie on the
   same tick splits it). If nobody jumped, the antes push back.
6. After the crash, ANYONE can claim the next flight - whoever
   clicks becomes the new pilot and presses LAUNCH. The sitting
   pilot keeps the chair by clicking it themselves.

|cff88ffffThe Nerve:|r
Past the climb-out the explosion odds are the same every tick - the
flight so far tells you NOTHING about the flight left. The average
flight runs long (most blow past 400m; about one in eight runs the
full 1000m and explodes at the cap), so the pot is pure nerve:
outwait the table, don't outwait the zeppelin. Disconnecting won't
save your ante - a vanished rider goes down with the ship.

|cff88ffffProvably Fair:|r
At launch the host broadcasts a fingerprint (hash) of a secret that
decides the crash point. Nobody can predict it mid-flight (the
secret stays hidden), and the host cannot change it once the flight
is up (the fingerprint is already on record). After the crash the
secret is revealed and your client verifies it automatically -
a tampered reveal is called out in red.

|cff88ffffDisconnects:|r
A rider who disconnects mid-flight gets their ante voided. If the
pilot (host) vanishes mid-flight, the whole round is voided - no
gold changes hands.

|cffff8888Remember:|r This is for fun! Trade gold honorably with other players to settle bets.]]
    },
    slots = {
        title = "Slots (Solo)",
        text = [[|cffffd700Welcome to Azeroth Riches - 5-Reel Slots!|r

|cff88ffffThe Arcade:|r
A solo machine played on |cffcc88fffake credits|r, like the old
handheld Vegas games. No gold, no group, no trades - your credit
balance is saved on this character and follows you around.

|cff88ffffHow to Play:|r
1. Pick how many |cffffd700lines|r are active (1-9) and your
   |cffffd700bet per line|r (1-5). Total bet = lines x bet.
2. Five reels spin, five symbols tall (a 5x5 grid).
3. Wins pay on active lines for 3+ matching symbols from the
   leftmost reel.

|cff88ffffThe nine lines|r (activation order): Middle, Row 2, Row 4,
Top, Bottom, Slash /, Backslash \, Top V, Bottom ^.
The markers around the reels show the bet riding each line
(0 = line off). Click any marker to play up to that line.

|cff88ffffPays (per line, per credit - 3 / 4 / 5):|r
WILD |cffffd70060/300/1500|r - Skull |cffffd70050/200/1000|r - Gold |cffffd70020/60/250|r
Ruby |cffffd70010/30/100|r - Emerald |cffffd7006/18/60|r - Sapphire |cffffd7004/12/40|r
Die |cffffd7005/15/50|r - Shroom/Melon/Apple and Silver/Copper fill the low end

|cff88ffffCOINS - the WoW Token:|r
Every Token that lands is a |cffffd700coin|r with a credit value on it
(scaled by your total bet). Exactly |cffffd7003 coins|r in view triggers
a random side bonus: Loot Chest, Bonus Wheel, or Free Spins.

|cffff9933HOLD & SPIN:|r Land |cffffd7004+ coins|r and they LOCK in place
with 3 respins - every new coin resets the respins to 3, and all
|cffffd70025|r positions are in play. When they run out you collect every
locked coin. Special coins pay the |cff55ff55MINI|r / |cff55aaffMINOR|r / |cffcc66ffMAJOR|r
jackpots, and locking |cffffd70020+|r of the 25 positions wins the
progressive |cffff3333GRAND JACKPOT|r. Every jackpot is a live pot -
they grow with every wager (yours and the rest of the realm's)
until somebody hits them. You need a total bet of |cffffd7005+|r to be
riding for the pots (smaller bets win the old fixed multiples),
and the million-seeded |cffff4455MEGA|r pot needs a total bet of |cffffd700100+|r.

|cffff77ffGEM RUSH:|r 1 in 20 pulls strips everything below the gems
off the reels - only high symbols, pure line pay.

|cff88ffffBroke?|r
When you hit zero the pit boss will comp you back in. She keeps
count of your refills, though. Forever.]]
    },
    videopoker = {
        title = "Video Poker & Blackjack (Solo)",
        text = [[|cffffd700Welcome to the video card cabinet!|r

|cff88ffffThe Arcade:|r
A solo machine played on |cffcc88fffake credits|r, like the old
handheld Vegas games. No gold, no group, no trades - your credit
balance is saved on this character and follows you around.

|cff88ffffThree games, one cabinet:|r Use the tabs up top to switch
between |cffffd700Video Poker|r, |cffffd700Video Blackjack|r and |cffffd700Video Keno|r.

|cff88ffffVideo Keno:|r Pick 1-10 numbers on the 80-number board,
set your bet and DRAW - 20 numbers are called and matches pay
by how many you picked. The pay ladder updates live.

|cff88ffffVideo Poker:|r
1. Set your bet (1-5) and DEAL. Click cards to HOLD.
2. DRAW replaces the rest and the table pays you.
3. Click the game name to switch variation:
   |cffffd700Jacks or Better|r, |cffffd700Bonus Poker|r,
   |cffffd700Double Double Bonus|r, or |cffffd700Deuces Wild|r.
Bet 5 for the |cffffd700800x|r royal jackpot.

|cff88ffffVideo Blackjack:|r
1. Set your bet and DEAL - you get two cards, dealer shows one.
2. HIT for another card, STAND to hold, DOUBLE (one card, double
   the wager), or SPLIT a pair into two hands - resplit up to
   four hands if another pair shows up.
3. Dealer draws to 17. Blackjack pays |cffffd7003:2|r; a win pays even.

|cff88ffffShow Off / Send:|r Brag your credit total to chat with
|cffffd700Show Off|r, or gift credits to a friend (one-way) with
|cffffd700Send Credits|r.

|cff88ffffBroke?|r
When you hit zero the pit boss will comp you back in. She keeps
count of your refills, though. Forever.]]
    },
    derby = {
        title = "Chair's Cup (Derby)",
        text = [[|cffffd700Welcome to Chair's Cup!|r

|cff88ffffObjective:|r
Bet on which TWO horses finish first and second (a quinella) -
order doesn't matter.

|cff88ffffHow to Play:|r
1. Whoever presses NEW RACE becomes the bank for that race
2. The host sets the stake size and bets allowed per player
3. Left-click a combo line to bet, right-click to take one back
4. The host presses RUN RACE: 10s last call, 3s countdown, go!
5. After the race, everyone sees one net figure to collect or pay

|cff88ffffOdds:|r
Each line shows its payout odds up front - longshots pay more.

|cff88ffffFair Play:|r
The race is built from a shared seed, so every player watches
the identical race and sees identical payouts. The addon never
touches gold - settle up by trade afterwards.

|cff88ffffMore:|r
The full rules are also on the |cff00ff00How to Play|r button
inside the Derby window itself.]]
    },
    debug = {
        title = "Debug / Test Commands",
        text = [[|cffff00ffDEBUG MODE|r - visible only to authorized characters.
Enable with |cff88ff88/cc db|r first; all commands below need it on.

|cff88ffffTable games (Blackjack / Poker bots):|r
|cff88ff88/cc test add [name]|r - add a fake player
|cff88ff88/cc test remove <name>|r - remove a fake player
|cff88ff88/cc test list|r / |cff88ff88clear|r - list / remove all bots
|cff88ff88/cc test auto|r - toggle bot auto-play
|cff88ff88/cc test deal|r - force the deal
|cff88ff88/cc test dealer|r - make the dealer act
|cff88ff88/cc test hit/stand/double/split [name]|r - force a bot action

|cff88ffffOther multiplayer games:|r
|cff88ff88/cc test drjoin [name]|r - bot accepts the open Death Roll
|cff88ff88/cc test bingo <n>|r - add N fake bingo card buyers
|cff88ff88/cc test bingospeed <sec>|r - adjust bingo call speed live
|cff88ff88/cc test roulette <n>|r - add N fake roulette bettors
|cff88ff88/cc test ld <n>|r - add N fake Liar's Dice players
|cff88ff88/cc test ldact|r - nudge the Liar's Dice bot on turn

|cff88ffffArcade (solo games):|r
|cff88ff88/cc test arcade reset|r - credits back to 1,000
|cff88ff88/cc test arcade credits <n>|r - set the balance outright
|cff88ff88/cc test arcade refills|r - zero refill counters (incl. lifetime)

|cff88ffffSlots rigging (next spin only, one-shot):|r
|cff88ff88/cc test slots bonus|r - exactly 3 coins (side bonus)
|cff88ff88/cc test slots fireshot|r - 5 coins (HOLD & SPIN)
|cff88ff88/cc test slots <sym> <count> [line]|r - force a line win
|cff88ff88/cc test bj pair|r - next video blackjack deal is a pair
Symbols: skull gold ruby emerald sapphire die shroom
melon apple silver copper wild (count 3-5, line 1-9)]]
    }
}

function Lobby:ShowHelp()
    -- Hide the lobby while help is showing
    if self.frame then
        self.frame:Hide()
    end
    
    if self.helpPanel then
        self.helpPanel:Show()
        self:UpdateHelpTrixieVisibility()
        return
    end
    
    self:CreateHelpPanel()
    self.helpPanel:Show()
    self:UpdateHelpTrixieVisibility()
end

function Lobby:HideHelp(dontShowLobby)
    if self.helpPanel then
        self.helpPanel:Hide()
    end
    -- Hide help Trixie
    if self.helpTrixie then
        self.helpTrixie:Hide()
    end
    -- Opened from a game window's How to Play button: closing help should
    -- reopen that game window, not pop the lobby over it
    if self.helpFromGame then
        self.helpFromGame = false
        local mod = self.helpReturnModule
        self.helpReturnModule = nil
        if mod and mod.Show then mod:Show() end
        return
    end
    -- Show the lobby again (unless told not to)
    if not dontShowLobby and self.frame then
        self.frame:Show()
    end
end

-- Update Help Trixie visibility based on setting
function Lobby:UpdateHelpTrixieVisibility()
    if not self.helpTrixie then return end
    
    local showTrixie = true
    if BJ.db and BJ.db.settings then
        showTrixie = BJ.db.settings.showLobbyTrixie ~= false
    end
    
    -- Only show Trixie if setting is enabled AND help panel is visible
    if showTrixie and self.helpPanel and self.helpPanel:IsShown() then
        self.helpTrixie:Show()
    else
        self.helpTrixie:Hide()
    end
end

function Lobby:CreateHelpPanel()
    -- Parent to UIParent so it shows when lobby is hidden
    local panel = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    panel:SetSize(HELP_WIDTH, HELP_HEIGHT)
    panel:SetPoint("CENTER")
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    panel:SetClampedToScreen(true)
    panel:SetFrameStrata("HIGH")
    panel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    panel:SetBackdropColor(0.05, 0.08, 0.12, 0.98)
    panel:SetBackdropBorderColor(0.3, 0.5, 0.7, 1)
    panel:SetFrameLevel(self.frame:GetFrameLevel() + 10)
    Lobby:ApplyTavernBackground(panel)
    
    -- Title
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -10)
    title:SetText("|cff88ccffHow to Play|r")
    
    -- Back button (top right)
    local closeBtn = CreateFrame("Button", nil, panel, "BackdropTemplate")
    closeBtn:SetSize(60, 22)
    closeBtn:SetPoint("TOPRIGHT", -8, -8)
    closeBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    closeBtn:SetBackdropColor(0.3, 0.3, 0.4, 1)
    closeBtn:SetBackdropBorderColor(0.5, 0.5, 0.6, 1)
    local closeBtnText = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    closeBtnText:SetPoint("CENTER")
    closeBtnText:SetText("Back")
    closeBtn:SetScript("OnClick", function() Lobby:HideHelp() end)
    closeBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.4, 0.4, 0.5, 1) end)
    closeBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.3, 0.3, 0.4, 1) end)
    
    -- Game selection buttons (left side) - every game gets a listing
    local btnFrame = CreateFrame("Frame", nil, panel)
    btnFrame:SetSize(120, 400)
    btnFrame:SetPoint("TOPLEFT", 15, -45)

    local helpGameList = {
        { key = "blackjack", label = "Blackjack" },
        { key = "poker",     label = "5 Card Stud" },
        { key = "holdem",    label = "Texas Hold'em" },
        { key = "hilo",      label = "High-Lo" },
        { key = "deathroll", label = "Death Roll" },
        { key = "bingo",     label = "Bingo" },
        { key = "roulette",  label = "Roulette" },
        { key = "liarsdice", label = "Liar's Dice" },
        { key = "crash",     label = "Crash" },
        { key = "derby",     label = "Chair's Cup" },
        { key = "slots",     label = "Slots (solo)" },
        { key = "videopoker", label = "Video Poker" },
    }

    -- Debug command reference: only characters on the debug allow-list see it
    if BJ.TestMode and BJ.TestMode.CanUseDebugMode and BJ.TestMode:CanUseDebugMode() then
        table.insert(helpGameList, { key = "debug", label = "Debug Cmds" })
    end

    local prevBtn
    for _, entry in ipairs(helpGameList) do
        local gameBtn = CreateFrame("Button", nil, btnFrame, "BackdropTemplate")
        gameBtn:SetSize(110, 30)
        if prevBtn then
            gameBtn:SetPoint("TOP", prevBtn, "BOTTOM", 0, -10)
        else
            gameBtn:SetPoint("TOP", 0, 0)
        end
        gameBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        gameBtn:SetBackdropColor(0.15, 0.35, 0.15, 1)
        gameBtn:SetBackdropBorderColor(0.3, 0.7, 0.3, 1)
        local gameBtnText = gameBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        gameBtnText:SetPoint("CENTER")
        gameBtnText:SetText("|cff00ff00" .. entry.label .. "|r")
        local key = entry.key
        gameBtn:SetScript("OnClick", function() Lobby:ShowHelpContent(key) end)
        gameBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.2, 0.5, 0.2, 1) end)
        gameBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.15, 0.35, 0.15, 1) end)
        prevBtn = gameBtn
    end

    -- Back button (hidden by default, shown when viewing game help)
    local backBtn = CreateFrame("Button", nil, btnFrame, "BackdropTemplate")
    backBtn:SetSize(110, 26)
    backBtn:SetPoint("TOP", prevBtn, "BOTTOM", 0, -15)
    backBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    backBtn:SetBackdropColor(0.3, 0.25, 0.15, 1)
    backBtn:SetBackdropBorderColor(0.5, 0.4, 0.2, 1)
    local backText = backBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    backText:SetPoint("CENTER")
    backText:SetText("|cffffcc00< Back|r")
    backBtn:SetScript("OnClick", function() Lobby:ShowMainHelp() end)
    backBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.4, 0.35, 0.2, 1) end)
    backBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.3, 0.25, 0.15, 1) end)
    backBtn:Hide()
    panel.backBtn = backBtn
    
    -- Content area (middle with scroll)
    local contentFrame = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    contentFrame:SetSize(560, HELP_HEIGHT - 60)  -- fills the widened panel
    contentFrame:SetPoint("TOPLEFT", btnFrame, "TOPRIGHT", 10, 5)
    contentFrame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    contentFrame:SetBackdropColor(0.02, 0.02, 0.05, 0.9)
    contentFrame:SetBackdropBorderColor(0.2, 0.2, 0.3, 1)
    
    -- Scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", nil, contentFrame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 8, -8)
    scrollFrame:SetPoint("BOTTOMRIGHT", -28, 8)
    
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(500, 1)
    scrollFrame:SetScrollChild(scrollChild)

    local contentText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    contentText:SetPoint("TOPLEFT", 0, 0)
    contentText:SetWidth(500)
    contentText:SetJustifyH("LEFT")
    contentText:SetJustifyV("TOP")
    contentText:SetSpacing(2)
    
    -- Default content with commands and tips
    local defaultHelp = "|cffffd700=== Slash Commands ===|r\n\n"
    defaultHelp = defaultHelp .. "|cff88ff88/cc|r or |cff88ff88/casino|r - Open lobby\n"
    defaultHelp = defaultHelp .. "|cff88ff88/cc help|r - Show commands in chat\n"
    defaultHelp = defaultHelp .. "|cff88ff88/cc default|r - Reset settings\n"
    defaultHelp = defaultHelp .. "|cff88ff88/cc intro|r - Replay Trixie intro\n"
    defaultHelp = defaultHelp .. "|cff88ff88/hilo <max> [timer]|r - Quick start High-Lo\n"
    defaultHelp = defaultHelp .. "   max = max roll, timer = 20-120 sec (default 60)\n"
    defaultHelp = defaultHelp .. "   Example: /hilo 1000 30\n"
    defaultHelp = defaultHelp .. "|cff88ff88/cup|r, |cff88ff88/derby|r or |cff88ff88/chairscup|r - Open the Chair's Cup derby\n\n"
    defaultHelp = defaultHelp .. "|cffffd700=== Tips ===|r\n\n"
    defaultHelp = defaultHelp .. "|cffcccccc\226\128\162|r Click |cff00ff00[game names]|r in chat to open that game directly\n\n"
    defaultHelp = defaultHelp .. "|cffcccccc\226\128\162|r Games require a party or raid - invite friends!\n\n"
    defaultHelp = defaultHelp .. "|cffcccccc\226\128\162|r One person hosts, others join. The host is the 'house'.\n\n"
    defaultHelp = defaultHelp .. "|cffcccccc\226\128\162|r Settle debts with in-game gold trades after games.\n\n"
    defaultHelp = defaultHelp .. "|cff888888Select a game on the left to see its rules.|r"
    
    contentText:SetText(defaultHelp)
    
    -- Store default help text for back button
    panel.defaultHelpText = defaultHelp
    
    panel.contentText = contentText
    panel.scrollChild = scrollChild
    panel.scrollFrame = scrollFrame
    
    -- Set initial scroll height after a frame delay (text needs to render)
    C_Timer.After(0.01, function()
        if panel.contentText then
            local textHeight = panel.contentText:GetStringHeight()
            panel.scrollChild:SetHeight(math.max(340, textHeight + 20))
        end
    end)
    
    self.helpPanel = panel
    
    -- Tall Trixie on the right side (same dimensions as lobby Trixie)
    local TRIXIE_WIDTH = 274
    local TRIXIE_HEIGHT = 350
    
    local helpTrixieFrame = CreateFrame("Button", "HelpTrixieFrame", UIParent)
    helpTrixieFrame:SetSize(TRIXIE_WIDTH, TRIXIE_HEIGHT)
    helpTrixieFrame:SetPoint("LEFT", panel, "RIGHT", 0, 0)
    helpTrixieFrame:SetFrameStrata("HIGH")
    
    -- Random wait image for help window
    local helpWaitIdx = math.random(1, 31)
    local helpTrixieTexture = helpTrixieFrame:CreateTexture(nil, "ARTWORK")
    helpTrixieTexture:SetAllPoints()
    helpTrixieTexture:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\dealer\\trix_wait" .. helpWaitIdx)
    helpTrixieFrame.texture = helpTrixieTexture
    
    -- Click for easter egg poke
    helpTrixieFrame:SetScript("OnClick", function()
        Lobby:TryPlayPoke()
    end)
    
    -- Randomize pose each time help is shown
    panel:HookScript("OnShow", function()
        local newIdx = math.random(1, 31)
        helpTrixieFrame.texture:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\dealer\\trix_wait" .. newIdx)
    end)
    
    helpTrixieFrame:Hide()
    self.helpTrixie = helpTrixieFrame
end

-- Show main help page (called by back button)
function Lobby:ShowMainHelp()
    if not self.helpPanel then return end
    
    -- Reset content to default
    self.helpPanel.contentText:SetText(self.helpPanel.defaultHelpText)
    
    -- Resize scroll child
    local textHeight = self.helpPanel.contentText:GetStringHeight()
    self.helpPanel.scrollChild:SetHeight(math.max(340, textHeight + 20))
    
    -- Scroll to top
    self.helpPanel.scrollFrame:SetVerticalScroll(0)
    
    -- Hide back button
    self.helpPanel.backBtn:Hide()
end

-- Which UI module owns a game's window (blackjack lives on UI itself)
local function gameUIModule(game)
    if game == "blackjack" then return UI end
    if game == "poker" then return UI.Poker end
    if game == "holdem" then return UI.Holdem end
    if game == "hilo" then return UI.HiLo end
    if game == "deathroll" then return UI.DeathRoll end
    if game == "bingo" then return UI.Bingo end
    if game == "roulette" then return UI.Roulette end
    if game == "liarsdice" then return UI.LiarsDice end
    if game == "crash" then return UI.Crash end
    if game == "slots" then return UI.Slots end
    if game == "videopoker" then return UI.VideoPoker end
end

-- Open the help panel directly on one game's rules (used by the
-- "How to Play" button each game window carries). The game window is
-- hidden while help is up and restored when it closes.
function Lobby:ShowHowToPlay(game)
    local mod = gameUIModule(game)
    if mod and mod.Hide then mod:Hide() end
    self:ShowHelp()
    self:ShowHelpContent(game)
    self.helpFromGame = true
    self.helpReturnModule = mod
end

-- Attach the Trixie dealer to the right side of a game window. Rolls a
-- fresh pose each time the window opens, respects the show-Trixie
-- setting, and keeps the poke easter egg.
-- gameKey (optional): drives the "<gameKey>ShowTrixie" setting so each game's
-- Trixie can be toggled independently in the settings panel. Callers that pass
-- no key (the solo arcade machines) fall back to the shared lobby toggle.
function Lobby:AttachTrixie(parentFrame, gameKey)
    local tf = CreateFrame("Button", nil, parentFrame)
    tf:SetSize(274, 350)
    tf:SetPoint("LEFT", parentFrame, "RIGHT", 0, 0)

    local tex = tf:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tf.texture = tex

    tf:SetScript("OnClick", function()
        Lobby:TryPlayPoke()
    end)

    local settingKey = gameKey and (gameKey .. "ShowTrixie") or "showLobbyTrixie"
    local function refresh()
        local show = true
        if BJ.db and BJ.db.settings then
            show = BJ.db.settings[settingKey] ~= false
        end
        if show then
            tf.texture:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\dealer\\trix_wait" .. math.random(1, 31))
            tf:Show()
        else
            tf:Hide()
        end
    end
    parentFrame:HookScript("OnShow", refresh)
    if parentFrame:IsShown() then refresh() end

    -- Register the refresh so the settings panel can toggle this game's Trixie
    -- live (each game frame is built once, so one refresh per key).
    Lobby.gameTrixies = Lobby.gameTrixies or {}
    local regKey = gameKey or "lobby"
    Lobby.gameTrixies[regKey] = Lobby.gameTrixies[regKey] or {}
    table.insert(Lobby.gameTrixies[regKey], refresh)

    parentFrame.trixieFrame = tf   -- so games can make her react
    return tf
end

-- How much art each Trixie pose set ships with (dealer/trix_<set><n>.tga).
local TRIXIE_SETS = { wait = 31, win = 9, lose = 12, love = 10, deal = 8, shuf = 12 }

-- Swap Trixie to a reaction pose for a few seconds, then back to waiting.
-- Safe to call on any frame that mounted her via AttachTrixie; overlapping
-- reactions just replace each other (the newest one wins the reset).
function Lobby:TrixieReact(parentFrame, mood, holdSecs)
    local tf = parentFrame and parentFrame.trixieFrame
    local n = TRIXIE_SETS[mood]
    if not tf or not n or not tf:IsShown() then return end
    tf.texture:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\dealer\\trix_" ..
        mood .. math.random(1, n))
    tf.reactToken = (tf.reactToken or 0) + 1
    local token = tf.reactToken
    C_Timer.After(holdSecs or 4, function()
        if tf.reactToken == token and tf:IsShown() then
            tf.texture:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\dealer\\trix_wait" ..
                math.random(1, TRIXIE_SETS.wait))
        end
    end)
end

-- Re-run the visibility refresh for a game that mounts Trixie via AttachTrixie.
function Lobby:RefreshGameTrixie(gameKey)
    if not self.gameTrixies then return end
    local list = self.gameTrixies[gameKey]
    if not list then return end
    for _, fn in ipairs(list) do fn() end
end

-- Attach a small "How to Play" button to a game window (same style as
-- the Derby's). Returns the button so callers can reposition it.
function Lobby:AttachHowToPlayButton(parent, gameKey, x, y)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(92, 20)
    btn:SetText("How to Play")
    btn:SetPoint("TOPLEFT", x or 10, y or -10)
    btn:SetFrameLevel(parent:GetFrameLevel() + 20)
    btn:SetScript("OnClick", function()
        Lobby:ShowHowToPlay(gameKey)
    end)
    return btn
end

function Lobby:ShowHelpContent(game)
    if not self.helpPanel then return end
    
    local content = self.helpContent[game]
    if not content then return end
    
    -- Update content
    self.helpPanel.contentText:SetText(content.text)
    
    -- Resize scroll child to fit content
    local textHeight = self.helpPanel.contentText:GetStringHeight()
    self.helpPanel.scrollChild:SetHeight(math.max(340, textHeight + 20))
    
    -- Scroll to top
    self.helpPanel.scrollFrame:SetVerticalScroll(0)
    
    -- Show back button
    self.helpPanel.backBtn:Show()
end

--[[
    EASTER EGG - Trixie Poke Sound
    Very rare chance to play when clicking on Trixie (configurable in debug mode)
]]
function Lobby:TryPlayPoke()
    local pokeChance = self:GetPokeChance()
    if math.random(1, pokeChance) == 1 then
        local pokeNum = math.random(1, 4)
        local soundFile = "Interface\\AddOns\\Chairfaces Casino\\Sounds\\Trixie\\trix_poke" .. pokeNum .. ".ogg"
        PlaySoundFile(soundFile, "SFX")
        return true
    end
    return false
end

--[[
    GAME ACTIVE CHECK
    Returns true if any game is currently in an active (non-idle, non-settlement) phase
]]
--[[
    GAME SESSION GATING
    One registry drives every "is a game running?" check and the lobby
    button states. Adding a game = one entry here plus its lobby button.
]]
Lobby.gameList = {
    { key = "blackjack", name = "Blackjack",     state = function() return BJ.GameState end,      button = "bjButton" },
    { key = "poker",     name = "5 Card Stud",   state = function() return BJ.PokerState end,     button = "fcsButton" },
    { key = "holdem",    name = "Texas Hold'em", state = function() return BJ.HoldemState end,    button = "holdemButton" },
    { key = "hilo",      name = "High-Lo",       state = function() return BJ.HiLoState end,      button = "hiloButton" },
    { key = "deathroll", name = "Death Roll",    state = function() return BJ.DeathRollState end, button = "deathrollButton" },
    { key = "bingo",     name = "Bingo",         state = function() return BJ.BingoState end,     button = "bingoButton" },
    { key = "roulette",  name = "Roulette",      state = function() return BJ.RouletteState end,  button = "rouletteButton" },
    { key = "liarsdice", name = "Liar's Dice",   state = function() return BJ.LiarsDiceState end,  button = "liarsdiceButton" },
    { key = "crash",     name = "Crash", state = function() return BJ.CrashState end,     button = "crashButton" },
    -- Chair's Cup exposes a phase adapter (BJ.DerbyState, set up at the
    -- bottom of SigmaDerbyUI.lua) so the derby participates in the same
    -- one-game-at-a-time gating as everything else.
    { key = "derby",     name = "Chair's Cup",   state = function() return BJ.DerbyState end,     button = "derbyButton" },
}

-- Check if a specific game is in an active session (not idle, not settlement)
function Lobby:IsGameInSession(gameType)
    for _, entry in ipairs(Lobby.gameList) do
        if entry.key == gameType then
            local state = entry.state()
            if state and state.phase and state.phase ~= "idle" and state.phase ~= "settlement" then
                return true
            end
            return false
        end
    end
    return false
end

function Lobby:IsAnyGameActive()
    for _, entry in ipairs(Lobby.gameList) do
        if self:IsGameInSession(entry.key) then
            return true, entry.key
        end
    end
    return false, nil
end

-- Check if any OTHER game (not the specified one) is active
function Lobby:IsOtherGameActive(excludeGame)
    for _, entry in ipairs(Lobby.gameList) do
        if entry.key ~= excludeGame and self:IsGameInSession(entry.key) then
            return true, entry.key
        end
    end
    return false, nil
end

-- Get friendly name for game
function Lobby:GetGameName(gameType)
    for _, entry in ipairs(Lobby.gameList) do
        if entry.key == gameType then return entry.name end
    end
    return gameType
end

-- Start the lobby refresh ticker (checks for game state changes)
function Lobby:StartLobbyRefreshTicker()
    -- Store current state to detect changes
    self.lastActiveStates = {}
    for _, entry in ipairs(Lobby.gameList) do
        self.lastActiveStates[entry.key] = self:IsGameInSession(entry.key)
    end

    -- Cancel any existing ticker
    self:StopLobbyRefreshTicker()

    -- Create a ticker that checks every 0.5 seconds
    self.lobbyRefreshTicker = C_Timer.NewTicker(0.5, function()
        if not self.frame or not self.frame:IsShown() then
            self:StopLobbyRefreshTicker()
            return
        end

        local changed = false
        for _, entry in ipairs(Lobby.gameList) do
            local active = self:IsGameInSession(entry.key)
            if active ~= self.lastActiveStates[entry.key] then
                changed = true
                self.lastActiveStates[entry.key] = active
            end
        end

        if changed then
            self:UpdateGameButtons()
        end
    end)
end

-- Stop the lobby refresh ticker
function Lobby:StopLobbyRefreshTicker()
    if self.lobbyRefreshTicker then
        self.lobbyRefreshTicker:Cancel()
        self.lobbyRefreshTicker = nil
    end
end

-- Update game buttons based on active game sessions
function Lobby:UpdateGameButtons()
    if not self.frame then return end

    local anyActive = self:IsAnyGameActive()

    for _, entry in ipairs(Lobby.gameList) do
        local btn = self.frame[entry.button]
        if btn then
            local inSession = self:IsGameInSession(entry.key)
            if inSession then
                -- This game is active - show "Join Now!" in green
                btn:SetBackdropColor(0.15, 0.35, 0.15, 0.5)
                btn:SetBackdropBorderColor(0.3, 0.7, 0.3, 1)
                btn.subtext:SetText("|cff88ff88Join Now!|r")
            elseif anyActive then
                -- Another game is active - desaturated gray button
                btn:SetBackdropColor(0.22, 0.22, 0.22, 0.5)
                btn:SetBackdropBorderColor(0.42, 0.42, 0.42, 1)
                btn.subtext:SetText("|cffffff00Table is Busy|r")
            else
                -- No games active - show "Play Now!" in green
                btn:SetBackdropColor(0.15, 0.35, 0.15, 0.5)
                btn:SetBackdropBorderColor(0.3, 0.7, 0.3, 1)
                btn.subtext:SetText("|cff88ff88Play Now!|r")
            end

            -- While a game is running, wash out every other game's icons
            local desat = (anyActive and not inSession) and 0.8 or 0
            if btn.icons then
                for _, tex in ipairs(btn.icons) do
                    if tex.SetDesaturation then
                        tex:SetDesaturation(desat)
                    elseif tex.SetDesaturated then
                        tex:SetDesaturated(desat > 0)
                    end
                end
            end
            if btn.iconTexts then
                for _, fs in ipairs(btn.iconTexts) do
                    fs:SetAlpha(desat > 0 and 0.35 or 1)
                end
            end
        end
    end
end
