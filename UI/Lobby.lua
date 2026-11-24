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

function Lobby:Initialize()
    if self.frame then return end
    self:CreateLobbyFrame()
end

function Lobby:CreateLobbyFrame()
    -- Shared casino window (UI/Chrome.lua). The animated sign is the
    -- lobby's title, so the band is transparent and only carries the X.
    -- The rowdy Azerothian backdrop art is cropped to fit, under a dark
    -- scrim that keeps the game grid readable.
    local frame = UI.Chrome:CreateWindow({
        name = "ChairfacesCasinoLobby",
        width = LOBBY_WIDTH, height = LOBBY_HEIGHT,
        art = "Interface\\AddOns\\Chairfaces Casino\\Textures\\lobby_bg",
        artW = 720, artH = 490, scrim = 0.5,
        titleBar = false,
        -- her goodbye comes from the casino watch
        onClose = function(f) f:Hide() end,
    })
    local closeBtn = frame.closeBtn

    -- Animated logo centered above game selection
    -- Logo is 200x113 base, scaled to 312x176 (25% wider than 250px buttons)
    local logoWidth = 312
    local logoHeight = 176
    local logoFrame = CreateFrame("Frame", nil, frame)
    logoFrame:SetSize(logoWidth, logoHeight)
    logoFrame:SetPoint("TOP", frame, "TOP", 0, -2)
    
    local logoTexture = logoFrame:CreateTexture(nil, "ARTWORK")
    logoTexture:SetAllPoints()
    -- The sign. Classic: the original 80-frame strip (vertical, Y-flipped)
    -- looping whole, power-on included. New (default): that power-on plays
    -- once each time the lobby opens, then the AutoSprite glow loop
    -- (tools/gen_logo_anim.py) runs, which starts and ends on the lit sign.
    local CLASSIC = "Interface\\AddOns\\Chairfaces Casino\\Textures\\logo_frames"
    local GLOW = "Interface\\AddOns\\Chairfaces Casino\\Textures\\logo_glow"
    local logoNumFrames = 80
    local logoFrameTime = 0.065  -- ~15fps (30% slower than 0.05)
    local logoAnimDuration = logoNumFrames * logoFrameTime
    local POWER_ON_FRAMES = 23   -- strip frames until the sign is fully lit
    local LOGO_GLOW = { frames = 32, cols = 6, fw = 312, fh = 176, texW = 1872, texH = 1056, fps = 12 }
    local logoElapsed, logoCurrentFrame, logoTex = 0, -1, nil

    local function showStrip(f)
        if logoTex ~= CLASSIC then logoTex = CLASSIC; logoTexture:SetTexture(CLASSIC) end
        logoTexture:SetTexCoord(0, 1, (f + 1) / logoNumFrames, f / logoNumFrames)  -- Y-flipped
    end
    local function showGlow(f)
        if logoTex ~= GLOW then logoTex = GLOW; logoTexture:SetTexture(GLOW) end
        local g = LOGO_GLOW
        local c, r = f % g.cols, math.floor(f / g.cols)
        logoTexture:SetTexCoord(c * g.fw / g.texW, (c + 1) * g.fw / g.texW,
                                r * g.fh / g.texH, (r + 1) * g.fh / g.texH)
    end

    function Lobby:RestartLogo()
        logoElapsed, logoCurrentFrame = 0, -1
        showStrip(0)
    end
    Lobby:RestartLogo()
    frame:HookScript("OnShow", function() Lobby:RestartLogo() end)

    logoFrame:SetScript("OnUpdate", function(self, dt)
        logoElapsed = logoElapsed + dt
        local classic = BJ.db and BJ.db.settings and BJ.db.settings.classicLogo
        if classic then
            if logoElapsed >= logoAnimDuration then logoElapsed = logoElapsed % logoAnimDuration end
            local f = math.floor(logoElapsed / logoFrameTime)
            if f ~= logoCurrentFrame then logoCurrentFrame = f; showStrip(f) end
            return
        end
        local powerOn = POWER_ON_FRAMES * logoFrameTime
        if logoElapsed < powerOn then
            local f = math.floor(logoElapsed / logoFrameTime)
            if f ~= logoCurrentFrame then logoCurrentFrame = f; showStrip(f) end
        else
            local f = POWER_ON_FRAMES + math.floor((logoElapsed - powerOn) * LOGO_GLOW.fps) % LOGO_GLOW.frames
            if f ~= logoCurrentFrame then logoCurrentFrame = f; showGlow(f - POWER_ON_FRAMES) end
        end
    end)
    
    -- Game selection panel (centered below logo)
    local gamePanel = CreateFrame("Frame", nil, frame)
    gamePanel:SetSize(690, LOBBY_HEIGHT - logoHeight - 60)
    gamePanel:SetPoint("TOP", logoFrame, "BOTTOM", 0, -2)
    
    -- Invisible anchor row where the "Select a Game" label used to sit;
    -- every game button hangs off this, so it stays as a pure anchor
    local gamesLabel = gamePanel:CreateFontString(nil, "OVERLAY", "CCFontLarge")
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

    -- Tiles are painted by Lobby:PaintGameTile (normal / join / busy /
    -- arcade); hover brightens the edge to full gold.
    local function gameHoverIn(self)
        local c = BJ.Theme.C.border
        self:SetBackdropBorderColor(c[1], c[2], c[3], 1)
        self.hoverGlow:Show()
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

    -- Chair's Cup opens like any game; when it closes, the lobby comes back
    local function openDerby()
        frame:Hide()
        Lobby:HideHelp(true)
        local Derby = UI.Derby
        if not Derby then
            BJ:Print("|cffff4444Chair's Cup (Derby) isn't available - reload your UI and try again.|r")
            return
        end
        Derby:Show()
        Lobby.derbyOpenedFromLobby = true
        if not Lobby.derbyHideHooked then
            Lobby.derbyHideHooked = true
            Derby.frame:HookScript("OnHide", function()
                if Lobby.derbyOpenedFromLobby then
                    Lobby.derbyOpenedFromLobby = false
                    Lobby:Show()
                end
            end)
        end
    end

    -- Build one grid button. spec: row, col, key (frame.<key>), name, nameSize,
    -- icon (texture), iw/ih (icon size), texCoord/mask (optional), open (onclick),
    -- arcade (bool -> purple styling, fake-credit subtext, no live-table gating).
    local function makeGameButton(spec)
        local btn = CreateFrame("Button", nil, gamePanel, "BackdropTemplate")
        btn:SetSize(BUTTON_WIDTH - 4, BUTTON_HEIGHT - 4)
        btn:SetPoint("TOP", gamesLabel, "BOTTOM", colX(spec.col), rowY(spec.row) - 2)
        btn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 } })
        btn.arcade = spec.arcade

        local glow = btn:CreateTexture(nil, "BACKGROUND", nil, 1)
        glow:SetPoint("TOPLEFT", 1, -1)
        glow:SetPoint("BOTTOMRIGHT", -1, 1)
        glow:SetColorTexture(1, 0.85, 0.4, 0.10)
        glow:Hide()
        btn.hoverGlow = glow

        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetSize(spec.iw or 32, spec.ih or 32)
        icon:SetPoint("LEFT", btn, "LEFT", 8, 0)
        icon:SetTexture(spec.icon)
        if spec.mask and icon.SetMask then icon:SetMask(ICON_MASK)
        elseif spec.texCoord then icon:SetTexCoord(unpack(spec.texCoord)) end
        btn.icons = { icon }

        local name = btn:CreateFontString(nil, "OVERLAY", "CCFontMedium")
        name:SetPoint("LEFT", icon, "RIGHT", 7, 6)
        name:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
        name:SetJustifyH("LEFT")
        name:SetFont(BJ.Theme.FONT, spec.nameSize or 13, "OUTLINE")
        name:SetText(spec.name)
        btn.nameText = name

        local sub = btn:CreateFontString(nil, "OVERLAY", "CCFontSmall")
        sub:SetPoint("LEFT", icon, "RIGHT", 7, -9)
        btn.subtext = sub
        Lobby:PaintGameTile(btn, spec.arcade and "arcade" or "normal")

        btn:SetScript("OnEnter", gameHoverIn)
        btn:SetScript("OnLeave", function(self)
            self.hoverGlow:Hide()
            if self.arcade then Lobby:PaintGameTile(self, "arcade")
            else Lobby:UpdateGameButtons() end
        end)
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
    makeGameButton({ row = 2, col = 4, key = "slotsButton",      name = "Slots",                 arcade = true, icon = ARC .. "emerald",  iw = 30, ih = 30, open = opener("SlotFloor", "Show") })
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
    
    -- Settings, Help, Leaderboard, Debts, LFG in one row (centered),
    -- standard theme buttons
    local T = BJ.Theme
    local UTIL_BUTTON_WIDTH = 96
    local UTIL_GAP = 8
    local UTIL_ROW_WIDTH = UTIL_BUTTON_WIDTH * 5 + UTIL_GAP * 4

    local buttonRow1 = CreateFrame("Frame", nil, gamePanel)
    buttonRow1:SetSize(UTIL_ROW_WIDTH, 28)
    buttonRow1:SetPoint("TOP", gamesLabel, "BOTTOM", 0, GAMES_BOTTOM_Y - 20)

    local utilSpecs = {
        { text = "Settings", click = function()
            Lobby:OpenFromLobby(function() Lobby:ShowSettings() end,
                function() return Lobby.settingsFrame end)
        end },
        { text = "How to Play", click = function() Lobby:ShowHelp() end },
        { text = "Leaderboard", variant = "primary",
          tip = { "All-Time Leaderboard", "View win/loss standings across all games",
                  "Track your stats and compare with others" },
          click = function()
            if BJ.LeaderboardUI then
                Lobby:OpenFromLobby(function() BJ.LeaderboardUI:ShowAllTime() end,
                    function() return BJ.Leaderboard and BJ.Leaderboard.allTimeFrame end)
            end
        end },
        { text = "Debts",
          tip = { "Settle-Up Ledger", "Who owes who, netted across every game",
                  "Trading gold to a player settles your tab automatically" },
          click = function()
            if BJ.UI and BJ.UI.Debts then
                Lobby:OpenFromLobby(function() BJ.UI.Debts:Show() end,
                    function() return BJ.UI.Debts.frame end)
            end
        end },
        { text = "LFG",
          tip = { "Table Finder", "An LFG board for gambling: list yourself as",
                  "hosting or looking to play, and find others" },
          click = function()
            frame:Hide()
            Lobby:HideHelp(true)
            if BJ.UI and BJ.UI.Finder then BJ.UI.Finder:Show() end
        end },
    }
    local prev
    for _, spec in ipairs(utilSpecs) do
        local b = T:Button(buttonRow1, spec.text, UTIL_BUTTON_WIDTH, 28, spec.variant or "secondary")
        if prev then b:SetPoint("LEFT", prev, "RIGHT", UTIL_GAP, 0)
        else b:SetPoint("LEFT", buttonRow1, "LEFT", 0, 0) end
        b:SetScript("OnClick", spec.click)
        if spec.tip then T:Tooltip(b, unpack(spec.tip)) end
        if spec.text == "Leaderboard" then self.leaderboardBtn = b end
        prev = b
    end

    -- Copyright text at bottom center
    local copyrightText = frame:CreateFontString(nil, "OVERLAY", "CCFontDisableSmall")
    copyrightText:SetPoint("BOTTOM", frame, "BOTTOM", 0, 8)
    copyrightText:SetText("© 2026 Chairface Chippendale")
    
    -- Version text at bottom right
    local versionText = frame:CreateFontString(nil, "OVERLAY", "CCFontDisableSmall")
    versionText:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 8)
    versionText:SetText("Chairface's Casino v" .. BJ.version)
    
    -- Trixie on the right side of lobby (same size as games: 274x350)
    local TRIXIE_WIDTH = 274
    local TRIXIE_HEIGHT = 350
    
    -- Parent to UIParent but position relative to lobby frame
    local trixieFrame = CreateFrame("Button", "LobbyTrixieFrame", UIParent)
    trixieFrame:SetSize(TRIXIE_WIDTH, TRIXIE_HEIGHT)
    trixieFrame:SetPoint("LEFT", frame, "RIGHT", 0, 0)
    trixieFrame:SetFrameStrata("HIGH")  -- Same as lobby
    
    local trixieTexture = trixieFrame:CreateTexture(nil, "ARTWORK")
    trixieTexture:SetAllPoints()
    BJ.Trixie:Attach(trixieFrame, trixieTexture)
    
    -- Easter egg click handler
    trixieFrame:SetScript("OnClick", function()
        Lobby:TryPlayPoke()
    end)
    
    -- Hide when lobby hides
    frame:HookScript("OnHide", function()
        trixieFrame:Hide()
    end)
    frame:HookScript("OnShow", function()
        -- Fresh Trixie pose each time lobby opens
        trixieFrame:Idle(true)
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
        self.introPendingUntil = GetTime() + 1.5   -- no greeting before it
        C_Timer.After(0.5, function()
            self:ShowTrixieIntro()
        end)
        ChairfacesCasinoSaved.trixieIntroShown = true
        ChairfacesCasinoSaved.introVersion = "2.3.3"  -- Track which version they saw intro for
    end
    -- her greeting comes from the casino watch (CheckCasinoOpen)

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
    
    self:PlayWinSound()

    -- Create intro overlay container
    local container = CreateFrame("Frame", "TrixieIntroContainer", UIParent)
    container:SetPoint("CENTER")
    container:SetSize(700, 500)
    container:SetFrameStrata("FULLSCREEN_DIALOG")
    self.introContainer = container

    -- Go straight to tall Trixie with dialog
    self:ShowIntroPhase2(container)
    -- her voice after her picture exists, so she talks along with it
    self:PlayTrixieIntroVoice()
end

-- Phase 2: Show tall Trixie with dialog
function Lobby:ShowIntroPhase2(container)
    -- Trixie tall image (left side, standing next to dialog)
    -- Original image is 896x1152, display at proper aspect ratio
    -- Use a button frame so it's clickable
    local trixieBtn = CreateFrame("Button", nil, container)
    trixieBtn:SetSize(280, 360)
    trixieBtn:SetPoint("LEFT", container, "LEFT", -20, 0)
    
    local trixieTall = trixieBtn:CreateTexture(nil, "ARTWORK")
    trixieTall:SetAllPoints()
    BJ.Trixie:Attach(trixieBtn, trixieTall)
    
    -- Easter egg click handler
    trixieBtn:SetScript("OnClick", function()
        Lobby:TryPlayPoke()
    end)
    
    -- Create intro dialog box (right of Trixie)
    local intro = CreateFrame("Frame", "TrixieIntroFrame", container, "BackdropTemplate")
    intro:SetSize(450, 380)
    intro:SetPoint("LEFT", trixieBtn, "RIGHT", 20, 0)
    BJ.Theme:Backdrop(intro, "panel")
    
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
    local dialogText = speechBg:CreateFontString(nil, "OVERLAY", "CCFontNormal")
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
    local continueBtn = BJ.Theme:Button(intro, "", 120, 35, "go", nil)
    continueBtn:SetPoint("BOTTOM", intro, "BOTTOM", 0, 14)
    
    local btnText = continueBtn.text
    btnText:SetText("Let's Play!")
    
    continueBtn:SetScript("OnEnter", function(self)

    end)
    continueBtn:SetScript("OnLeave", function(self)
        BJ.Theme:StyleButton(self)

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

--[[
    EASTER EGG - Trixie Poke Sound
    Very rare chance to play when clicking on Trixie (configurable in debug mode)
]]
function Lobby:TryPlayPoke()
    local pokeChance = self:GetPokeChance()
    -- A poke while she is speaking is dropped, like any other line.
    if not self:TrixieSpeaking() and math.random(1, pokeChance) == 1 then
        return self:PlayTrixieClip("trix_poke" .. math.random(1, 4)) and true or false
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
    -- bottom of UI/DerbyFrame.lua) so the derby participates in the same
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
-- One painter for every lobby game tile, so the grid reads as one set.
--   normal: gold name, "Play Now!"     join: green edge, "Join Now!"
--   busy:   greyed, "Table is Busy"    arcade: purple, "Fake Credits"
local TILE_STYLES = {
    normal = { bg = { 0.08, 0.065, 0.05, 0.78 }, edge = "borderDim", name = "gold",       sub = "good",    subText = "Play Now!" },
    join   = { bg = { 0.06, 0.16, 0.07, 0.85 },  edge = "good",      name = "goldBright", sub = "good",    subText = "Join Now!" },
    busy   = { bg = { 0.06, 0.06, 0.06, 0.80 },  edge = "textMuted", name = "textMuted",  sub = "warn",    subText = "Table is Busy" },
    arcade = { bg = { 0.12, 0.06, 0.16, 0.80 },  edge = "arcade",    name = "arcade",     sub = "textDim", subText = "Fake Credits" },
}
function Lobby:PaintGameTile(btn, state)
    local C = BJ.Theme.C
    local st = TILE_STYLES[state] or TILE_STYLES.normal
    btn:SetBackdropColor(st.bg[1], st.bg[2], st.bg[3], st.bg[4])
    local e = C[st.edge]
    btn:SetBackdropBorderColor(e[1], e[2], e[3], state == "arcade" and 0.7 or 1)
    if btn.nameText then BJ.Theme:SetTextRole(btn.nameText, st.name) end
    BJ.Theme:SetTextRole(btn.subtext, st.sub)
    btn.subtext:SetText(st.subText)
end

function Lobby:UpdateGameButtons()
    if not self.frame then return end

    local anyActive = self:IsAnyGameActive()

    for _, entry in ipairs(Lobby.gameList) do
        local btn = self.frame[entry.button]
        if btn then
            local inSession = self:IsGameInSession(entry.key)
            if inSession then
                Lobby:PaintGameTile(btn, "join")      -- this game is running
            elseif anyActive then
                Lobby:PaintGameTile(btn, "busy")      -- another game is running
            else
                Lobby:PaintGameTile(btn, "normal")
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
