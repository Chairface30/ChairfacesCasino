--[[
    Chairface's Casino - UI/GameWindow.lua
    ============================================
    Behaviour every multiplayer game window shares, embedded the same way
    GameComm / PokerEngine are: `UI.GameWindow:EmbedX(module, ...)` defines
    methods on the module; a later `function Module:X()` still overrides.

    Trixie (EmbedTrixie)
      Every game mounts her the same way: standing beside the window
      (Lobby:AttachTrixie), shown/hidden by the one "<key>ShowTrixie"
      setting, refreshed live from the settings panel. Games call the mood
      methods; none of them know how she is drawn.

        UI.GameWindow:EmbedTrixie(module, "poker")
        module:MountTrixie(frame)          -- once, when the window is built
        module:SetTrixieWait() / SetTrixieDeal() / SetTrixieShuffle()
        module:SetTrixieCheer() / SetTrixieLose() / SetTrixieLove()
        module:SetTrixieState(state)
        module:ShouldShowTrixie() / SetTrixieVisibility(show)
]]

local BJ = ChairfacesCasino
local UI = BJ.UI

local GW = {}
UI.GameWindow = GW

local function settings()
    local db = BJ.db or ChairfacesCasinoDB
    if not db then
        ChairfacesCasinoDB = { settings = {} }
        db = ChairfacesCasinoDB
    end
    db.settings = db.settings or {}
    return db.settings
end

-- mood method -> Trixie widget method (UI/Trixie.lua)
local MOODS = {
    SetTrixieWait    = "SetRandomWait",
    SetTrixieDeal    = "SetRandomDeal",
    SetTrixieShuffle = "SetRandomShuffle",
    SetTrixieCheer   = "SetRandomCheer",
    SetTrixieLose    = "SetRandomLose",
    SetTrixieLove    = "SetRandomLove",
}

-- The plain mood methods, by name, so a game that wraps them (High-Lo
-- plays each reaction once per state) can still call the shared one.
GW.MOOD = {}
for method, widgetMethod in pairs(MOODS) do
    GW.MOOD[method] = function(self)
        local tf = self.trixieFrame
        if tf and tf:IsShown() and tf[widgetMethod] then tf[widgetMethod](tf) end
    end
end

--[[
    The big centred call-to-action every table shows between hands
    (HOST / JOIN / RESET / VOID GAME). A theme "primary" button at
    180x54 with a 24pt label; window code sets its text and enables it.
]]
function GW:CallToAction(parent, name, onClick)
    local T = BJ.Theme
    local btn = T:Button(parent, "HOST", 180, 54, "primary", name)
    btn._ccFixedFont = true
    btn.text:SetFont(T.FONT, 24, "OUTLINE")
    btn:SetFrameLevel(parent:GetFrameLevel() + 100)   -- above the table
    btn:RegisterForClicks("AnyUp")
    if onClick then btn:SetScript("OnClick", onClick) end
    return btn
end

--[[
    The test-mode bar (only shown while `/cc db` test mode is on): one
    purple strip hung under the window with a TEST tag and a row of
    buttons. Every game builds it here, so they all look and behave alike.

        local bar = UI.GameWindow:TestBar(module, frame, {
            { key = "add",  text = "+FAKE", width = 60, onClick = fn },
            { key = "slow", text = "SLOWER", width = 62, onClick = fn },
        })
        bar.buttons.add              -- each button by key
        bar:AddText(key)             -- a status label after the buttons
        module:RefreshTestBar()      -- shows/hides it with test mode; the
                                     -- module may define OnRefreshTestBar(bar)
]]
GW.testWindows = {}

-- Test mode flipped: every built game window shows/hides its bar and redraws.
function GW:RefreshTestMode()
    for module in pairs(self.testWindows) do
        if module.RefreshTestBar then module:RefreshTestBar() end
        if module.UpdateDisplay then module:UpdateDisplay() end
    end
end

-- "Clear ALL leaderboard data?" - the one confirm every wipe button uses
function GW:ConfirmClearDB()
    StaticPopupDialogs["CASINO_CLEAR_ALL_DB"] = {
        text = "|cffff6666WARNING:|r Clear ALL leaderboard data?\n\nThis will wipe your local database AND send a clear command to all party members!\n\n|cffff9944This cannot be undone!|r",
        button1 = "Clear All",
        button2 = "Cancel",
        OnAccept = function()
            if BJ.Leaderboard then BJ.Leaderboard:ClearAllData(true) end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
    StaticPopup_Show("CASINO_CLEAR_ALL_DB")
end

-- The tools every test bar ends with: Trixie on/off (green on, red off),
-- step through her poses, wipe the leaderboard. Append to a TestBar spec.
function GW:CommonTestTools(module)
    local T = BJ.Theme
    return {
        { key = "trix", text = "TRIX", width = 45,
          variant = (not module.ShouldShowTrixie or module:ShouldShowTrixie()) and "go" or "danger",
          onClick = function()
              local on = not module:ShouldShowTrixie()
              module:SetTrixieVisibility(on)
              T:SetButtonVariant(module.testBar.buttons.trix, on and "go" or "danger")
          end },
        { text = "<Trix", width = 40, onClick = function()
            if BJ.TestMode then BJ.TestMode:PrevTrixieImage() end
        end },
        { text = "Trix>", width = 40, onClick = function()
            if BJ.TestMode then BJ.TestMode:NextTrixieImage() end
        end },
        { text = "CLR DB", width = 55, variant = "danger", onClick = function() GW:ConfirmClearDB() end },
    }
end

-- concatenate spec lists
function GW:Specs(...)
    local out = {}
    for _, list in ipairs({ ... }) do
        for _, s in ipairs(list) do out[#out + 1] = s end
    end
    return out
end

function GW:TestBar(module, frame, specs)
    local T = BJ.Theme
    local bar = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    bar:SetPoint("TOP", frame, "BOTTOM", 0, -5)
    bar:SetBackdrop({ bgFile = T.FLAT, edgeFile = T.FLAT, edgeSize = 2,
        insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    local a = T.C.arcade
    bar:SetBackdropColor(0.10, 0.06, 0.14, 0.95)
    bar:SetBackdropBorderColor(a[1], a[2], a[3], 1)

    local tag = bar:CreateFontString(nil, "OVERLAY", "CCFontSmall")
    tag:SetPoint("LEFT", 10, 0)
    tag:SetText(T:Paint("arcade", "TEST"))
    bar.tag = tag

    bar.buttons = {}
    local prev, width = tag, 10 + 30
    for _, s in ipairs(specs or {}) do
        local b = T:Button(bar, s.text, s.width or 70, 24, s.variant or "arcade")
        b:SetPoint("LEFT", prev, "RIGHT", 6, 0)
        if s.onClick then b:SetScript("OnClick", s.onClick) end
        if s.key then bar.buttons[s.key] = b end
        prev = b
        width = width + (s.width or 70) + 6
    end
    bar:SetSize(width + 12, 35)

    function bar:AddText(key, w)
        local fs = self:CreateFontString(nil, "OVERLAY", "CCFontSmall")
        fs:SetPoint("LEFT", prev, "RIGHT", 8, 0)
        self[key] = fs
        self:SetWidth(self:GetWidth() + (w or 80))
        prev = fs
        return fs
    end

    bar:Hide()
    module.testBar = bar
    GW.testWindows[module] = true

    function module:RefreshTestBar()
        local b = self.testBar
        if not b then return end
        if BJ.TestMode and BJ.TestMode.enabled then
            if self.OnRefreshTestBar then self:OnRefreshTestBar(b) end
            b:Show()
        else
            b:Hide()
        end
    end
    return bar
end

--[[
    Host recovery (EmbedRecovery). GameComm/StateSync call the same four
    methods on every game's window while a host is away; every game now
    answers them the same way:

        PAUSED - Waiting for <host>     (Trixie worried)
        PAUSED - <host> has 1:23 to return
        (host back: Trixie cheers, the table redraws)
        GAME VOIDED: <reason>           (Trixie sad, table redraws after 3s)

    Optional per-game hooks for its own buttons:
        module:OnRecoveryPause(originalHost, tempHost, iAmTempHost)
        module:OnRecoveryTick(remaining)
        module:OnRecoveryResume()
        module:OnRecoveryVoid(reason)
    opts.net = function() return BJ.<Game>Multiplayer end
]]
local function setStatus(self, text)
    local bar = self.statusBar
    if bar and bar.text then
        bar.text:SetText(text)
    elseif self.statusText then
        self.statusText:SetText(text)
    end
end

function GW:EmbedRecovery(module, opts)
    local T = BJ.Theme
    local function built(self) return self.frame or self.mainFrame end
    local function seat(name) return name and BJ:SeatName(name) or "the host" end

    function module:OnHostRecoveryStart(originalHost, tempHost)
        if not built(self) then return end
        setStatus(self, T:Paint("warn", "PAUSED - Waiting for " .. seat(originalHost)))
        if self.SetTrixieLose then self:SetTrixieLose() end
        if self.OnRecoveryPause then
            self:OnRecoveryPause(originalHost, tempHost, tempHost == BJ:MyName())
        end
        if self.UpdateDisplay then self:UpdateDisplay() end
    end

    function module:UpdateRecoveryTimer(remaining)
        if not built(self) then return end
        remaining = math.max(0, math.floor(remaining or 0))
        local net = opts.net and opts.net()
        local host = net and net.originalHost
        setStatus(self, T:Paint("warn", string.format("PAUSED - %s has %d:%02d to return",
            seat(host), math.floor(remaining / 60), remaining % 60)))
        if self.OnRecoveryTick then self:OnRecoveryTick(remaining) end
    end

    function module:OnHostRestored()
        if not built(self) then return end
        if self.OnRecoveryResume then self:OnRecoveryResume() end
        if self.SetTrixieCheer then
            self:SetTrixieCheer()
            C_Timer.After(2.0, function() self:SetTrixieWait() end)
        end
        if self.UpdateDisplay then self:UpdateDisplay() end
        if self.UpdateButtons then self:UpdateButtons() end
    end

    function module:OnGameVoided(reason)
        if not built(self) then return end
        setStatus(self, T:Paint("bad", "GAME VOIDED: " .. tostring(reason or "game cancelled")))
        if self.OnRecoveryVoid then self:OnRecoveryVoid(reason) end
        if self.SetTrixieLose then self:SetTrixieLose() end
        C_Timer.After(3.0, function()
            if self.UpdateDisplay then self:UpdateDisplay() end
            if self.UpdateButtons then self:UpdateButtons() end
        end)
    end
    return module
end

function GW:EmbedTrixie(module, key)
    local settingKey = key .. "ShowTrixie"

    function module:MountTrixie(frame)
        if not (UI.Lobby and UI.Lobby.AttachTrixie) then return end
        local tf = UI.Lobby:AttachTrixie(frame, key)
        self.trixieFrame = tf
        self.trixieTexture = tf.texture
        return tf
    end

    function module:ShouldShowTrixie()
        return settings()[settingKey] ~= false
    end

    function module:SetTrixieVisibility(show)
        settings()[settingKey] = show and true or false
        if UI.Lobby and UI.Lobby.RefreshGameTrixie then UI.Lobby:RefreshGameTrixie(key) end
    end

    -- she stands outside the window, so nothing in it moves for her
    function module:RepositionTrixie() end

    for method, fn in pairs(GW.MOOD) do module[method] = fn end

    function module:SetTrixieState(state)
        local tf = self.trixieFrame
        if tf and tf:IsShown() and tf.SetState then tf:SetState(state) end
    end

    return module
end
