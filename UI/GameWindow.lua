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
