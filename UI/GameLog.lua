--[[
    Chairface's Casino - UI/GameLog.lua
    ============================================
    The "last games" log window every game shares. Each game's State module
    already renders its history as text (`State:GetGameLogText()`, built on
    Core/GameHistory.lua); this is the one window that shows it.

        UI.GameLog:Embed(module, {
            name  = "CasinoPokerLogFrame",          -- global frame name
            title = "5 Card Stud",                   -- window says "<title> - Game Log"
            state = function() return BJ.PokerState end,
            anchor = function() return module.mainFrame end,  -- opens beside this
        })

    gives the module:
        module:CreateLogWindow()   build (lazy; ToggleLog calls it)
        module:ToggleLog()         show/hide, refreshed on show
        module:UpdateLogWindow()   re-read the history (no-op while closed)
        module.logFrame            the window (nil until first opened)
]]

local BJ = ChairfacesCasino
local UI = BJ.UI
local T = BJ.Theme

local GameLog = {}
UI.GameLog = GameLog

GameLog.WIDTH, GameLog.HEIGHT = 340, 380

function GameLog:Create(opts)
    local W, H = self.WIDTH, self.HEIGHT
    local f = UI.Chrome:CreateDialog({
        name = opts.name,
        title = (opts.title or "Game") .. " - Game Log",
        width = W, height = H,
        strata = "DIALOG",
    })
    f.titleText:SetFontObject("CCFontMedium")

    local well = T:Panel(f, "inset")
    well:SetPoint("TOPLEFT", 8, f.BODY_TOP - 8)
    well:SetPoint("BOTTOMRIGHT", -8, 8)

    local scroll = CreateFrame("ScrollFrame", nil, well, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -26, 6)
    T:StyleScrollBar(scroll)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(W - 50, 300)
    scroll:SetScrollChild(content)

    local text = content:CreateFontString(nil, "OVERLAY", "CCFontHighlightSmall")
    text:SetPoint("TOPLEFT", 4, -4)
    text:SetPoint("TOPRIGHT", -4, -4)
    text:SetJustifyH("LEFT")
    text:SetJustifyV("TOP")
    text:SetFont(T.FONT, 11)
    text:SetSpacing(2)
    text:SetText("No game history yet.")

    f.scrollFrame = scroll
    f.scrollContent = content
    f.logText = text
    f.text = text            -- Blackjack's old field name

    if BJ.EscapeHandler and opts.name then BJ.EscapeHandler:RegisterFrame(opts.name) end
    return f
end

function GameLog:Fill(f, state)
    if not f then return end
    local txt = state and state.GetGameLogText and state:GetGameLogText() or "No game history yet."
    f.logText:SetText(txt ~= "" and txt or "No game history yet.")
    local h = f.logText:GetStringHeight() or 0
    f.scrollContent:SetHeight(math.max(300, h + 20))
end

function GameLog:Embed(module, opts)
    function module:CreateLogWindow()
        if self.logFrame then return self.logFrame end
        self.logFrame = GameLog:Create(opts)
        return self.logFrame
    end

    function module:UpdateLogWindow()
        if not self.logFrame then return end
        GameLog:Fill(self.logFrame, opts.state())
    end

    function module:ToggleLog()
        local f = self:CreateLogWindow()
        if f:IsShown() then
            f:Hide()
            return
        end
        local anchor = opts.anchor and opts.anchor()
        f:ClearAllPoints()
        if anchor and anchor.IsShown and anchor:IsShown() then
            f:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 8, 0)
        else
            f:SetPoint("CENTER")
        end
        self:UpdateLogWindow()
        f:Show()
    end
    return module
end
