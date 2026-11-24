--[[
    Chairface's Casino - UI/Chrome.lua
    ============================================
    Every casino window is built here, so they all share one frame:

      +================ gold 2px edge =================+
      | [How to Play] [Log] ...   TITLE   ... [$] [X]   |  <- title bar
      |-------------------------------------------------|  <- gold rule
      |                                                 |
      |              body (art / felt / dark)           |
      |                                                 |
      +=================================================+

    UI.Chrome:CreateWindow(opts) -> frame
      opts.name      global frame name (keeps EscapeHandler / tests working)
      opts.title     title text
      opts.width/height
      opts.art       nil (plain dark) | "felt" | "tavern" | texture path
      opts.body      {r,g,b[,a]} body colour instead of the standard dark
      opts.artW/artH source pixel size of opts.art (default 1280x720)
      opts.scrim     0..1 darkening over the art (default 0 for felt, 0.45 for other art)
      opts.onClose   close handler (default: hide, then show the lobby)
      opts.noLobby   true = closing does NOT reopen the lobby (popups/tools)
      opts.howTo     game key -> adds the How to Play button (left)
      opts.debts     true -> adds the Debts icon (right, beside the X)
      opts.leaderboard  game key -> adds the all-time leaderboard trophy (right)
      opts.onRefresh function(frame) -> adds the refresh icon (right)
      opts.onLog     function(frame) -> adds the "Log" button (left, after How to Play)
      opts.strata    default "HIGH"
      opts.noDrag    true = not movable
      opts.titleBar  false = no band (art windows that paint their own title)
      opts.parent    default UIParent

    The returned frame carries:
      frame.titleBar, frame.titleText, frame.closeBtn, frame.howToBtn,
      frame.debtsBtn, frame.feltBg + frame.UpdateFeltTexCoords (art windows),
      frame.BODY_TOP (negative y offset where content starts),
      frame:SetTitle(text), frame:AddHeaderLeft(widget[, gap]),
      frame:AddHeaderRight(widget[, gap]).
]]

local BJ = ChairfacesCasino
BJ.UI = BJ.UI or {}
local UI = BJ.UI
local T = BJ.Theme

local Chrome = {}
UI.Chrome = Chrome

Chrome.TITLE_H = 30      -- title band height
Chrome.EDGE = 2          -- window border width
Chrome.PAD = 10          -- standard inner padding
Chrome.HEADER_BTN_H = 20 -- header button height

-- Default close: hide, then go back to the lobby.
local function defaultClose(frame)
    frame:Hide()
    if UI.Lobby and UI.Lobby.Show then UI.Lobby:Show() end
end

function Chrome:CreateWindow(opts)
    opts = opts or {}
    local frame = CreateFrame("Frame", opts.name, opts.parent or UIParent, "BackdropTemplate")
    frame:SetSize(opts.width or 600, opts.height or 400)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata(opts.strata or "HIGH")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    if frame.SetToplevel then frame:SetToplevel(true) end
    if not opts.noDrag then
        frame:SetMovable(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", frame.StartMoving)
        frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    end
    T:Backdrop(frame, "window")
    if opts.body then   -- a machine's own body colour (arcade cabinets)
        local b = opts.body
        frame:SetBackdropColor(b[1], b[2], b[3], b[4] or 0.97)
    end

    -- table art
    if opts.art then
        local scrim = opts.scrim
        if scrim == nil then scrim = (opts.art == "felt") and 0 or 0.45 end
        local tex, fit = T:ApplyArt(frame, opts.art, opts.artW, opts.artH, scrim, Chrome.EDGE)
        frame.feltBg = tex
        frame.artBg = tex
        frame.UpdateFeltTexCoords = fit
    end

    -- title band
    local hasBar = opts.titleBar ~= false
    local bar = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    bar:SetPoint("TOPLEFT", Chrome.EDGE, -Chrome.EDGE)
    bar:SetPoint("TOPRIGHT", -Chrome.EDGE, -Chrome.EDGE)
    bar:SetHeight(Chrome.TITLE_H)
    bar:SetFrameLevel(frame:GetFrameLevel() + 10)
    if hasBar then
        T:Backdrop(bar, "title")
        local rule = T:Divider(bar)
        rule:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
        rule:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
        bar.rule = rule
    end
    frame.titleBar = bar

    local title = bar:CreateFontString(nil, "OVERLAY", "CCFontTitle")
    title:SetPoint("CENTER", bar, "CENTER", 0, 0)
    title:SetText(opts.title or "")
    frame.titleText = title
    function frame:SetTitle(text)
        self.titleText:SetText(text or "")
        self:LayoutTitle()
    end
    function frame:LayoutTitle() Chrome.LayoutTitleFor(self) end

    -- header clusters: left grows rightward, right grows leftward
    frame._hdrLeft, frame._hdrRight = {}, {}
    function frame:AddHeaderLeft(w, gap)
        local list = self._hdrLeft
        w:SetParent(self.titleBar)
        w:ClearAllPoints()
        if #list == 0 then
            w:SetPoint("LEFT", self.titleBar, "LEFT", Chrome.PAD - 2, 0)
        else
            w:SetPoint("LEFT", list[#list], "RIGHT", gap or 6, 0)
        end
        w:SetFrameLevel(self.titleBar:GetFrameLevel() + 2)
        list[#list + 1] = w
        return w
    end
    function frame:AddHeaderRight(w, gap)
        local list = self._hdrRight
        w:SetParent(self.titleBar)
        w:ClearAllPoints()
        if #list == 0 then
            w:SetPoint("RIGHT", self.titleBar, "RIGHT", -(Chrome.PAD - 6), 0)
        else
            w:SetPoint("RIGHT", list[#list], "LEFT", -(gap or 4), 0)
        end
        w:SetFrameLevel(self.titleBar:GetFrameLevel() + 2)
        list[#list + 1] = w
        return w
    end

    -- close X
    local onClose = opts.onClose
    local close = T:CloseButton(bar, function()
        if onClose then onClose(frame)
        elseif opts.noLobby then frame:Hide()
        else defaultClose(frame) end
    end)
    frame:AddHeaderRight(close)
    frame.closeBtn = close

    -- standard header tools, right to left: X, refresh, debts, leaderboard
    if opts.onRefresh then
        frame.refreshBtn = T:IconButton(bar, T.TEX .. "Widgets\\refresh_icon", 16,
            { "Refresh Window" }, function() opts.onRefresh(frame) end)
        frame:AddHeaderRight(frame.refreshBtn)
    end
    if opts.debts and UI.Debts and UI.Debts.AttachDebtsIcon then
        frame.debtsBtn = UI.Debts:AttachDebtsIcon(frame)
        frame:AddHeaderRight(frame.debtsBtn)
    end
    if opts.leaderboard then
        local key = opts.leaderboard
        local lb = T:IconButton(bar, T.TEX .. "Widgets\\leaderboard_alltime", 18,
            { "All-Time Leaderboard", "View all-time rankings" }, function()
                if BJ.LeaderboardUI then BJ.LeaderboardUI:ToggleAllTime(key) end
            end)
        lb.icon:SetTexCoord(0, 1, 1, 0)   -- the trophy art is stored upside down
        lb.hl:SetTexCoord(0, 1, 1, 0)
        frame.leaderboardBtn = lb
        frame:AddHeaderRight(lb)
    end
    if opts.howTo then
        frame.howToBtn = Chrome:HowToPlayButton(frame, opts.howTo)
        frame:AddHeaderLeft(frame.howToBtn)
    end
    if opts.onLog then
        frame.logBtn = Chrome:HeaderButton(frame, "Log", 44, function() opts.onLog(frame) end)
        BJ.Theme:Tooltip(frame.logBtn, "Game Log", "The last games at this table")
        frame:AddHeaderLeft(frame.logBtn)
    end

    frame.BODY_TOP = -(Chrome.EDGE + Chrome.TITLE_H)
    frame:LayoutTitle()
    -- re-fit whenever the window changes width (Bingo / High-Lo grow) and
    -- on show (string widths are only exact once the font has loaded)
    frame:HookScript("OnSizeChanged", function(self) self:LayoutTitle() end)
    frame:HookScript("OnShow", function(self) self:LayoutTitle() end)
    frame:Hide()
    return frame
end

-- Width a header cluster takes from its window edge (0 when empty).
local function clusterWidth(list, inset, gap)
    if #list == 0 then return 0 end
    local w = inset
    for i, b in ipairs(list) do
        w = w + (b:GetWidth() or 0) + (i > 1 and gap or 0)
    end
    return w
end

--[[
    Fit the title between the header tools so they never collide:
      1. centred on the window, when both clusters leave room;
      2. otherwise How to Play folds down to a "?" button and we retry;
      3. then the title centres in the gap between the clusters,
         stepping its font down (to 10pt) until it fits.
]]
function Chrome.LayoutTitleFor(frame)
    local t = frame.titleText
    if not t then return end
    local text = t:GetText()
    local W = frame:GetWidth() or 0
    if not text or text == "" or W <= 0 then return end

    -- the size this title is styled at (its font object; SetFont on the
    -- string while shrinking doesn't touch the object, so this stays true)
    local fo = t.GetFontObject and t:GetFontObject()
    local base = (type(fo) == "table" and fo.GetFont and select(2, fo:GetFont())) or T.SIZE.title
    local flags = (base >= T.SIZE.title) and "OUTLINE" or ""

    local SPACE = 8   -- breathing room either side of the title
    local function fits()
        local lw = clusterWidth(frame._hdrLeft, Chrome.PAD - 2, 6)
        local rw = clusterWidth(frame._hdrRight, Chrome.PAD - 6, 4)
        local tw = t:GetStringWidth() or 0
        t:ClearAllPoints()
        if math.max(lw, rw) * 2 + tw + SPACE * 2 <= W - 2 * Chrome.EDGE then
            t:SetPoint("CENTER", frame.titleBar, "CENTER", 0, 0)
            return true
        end
        if lw + rw + tw + SPACE * 2 <= W - 2 * Chrome.EDGE then
            -- off-centre: centred in the free gap between the clusters
            local gapMid = lw + (W - 2 * Chrome.EDGE - lw - rw) / 2
            t:ClearAllPoints()
            t:SetPoint("CENTER", frame.titleBar, "LEFT", gapMid, 0)
            return true
        end
        return false
    end

    t:SetFont(T.FONT, base, flags)
    local h = frame.howToBtn
    if h and h._ccCompact then          -- room again (window grew): restore it
        h._ccCompact = nil
        h:SetText("How to Play")
        h:SetWidth(86)
    end
    if fits() then return end
    if h and not h._ccCompact then
        h._ccCompact = true
        h:SetText("?")
        h:SetWidth(Chrome.HEADER_BTN_H + 2)
        if fits() then return end
    end
    for size = base - 2, 10, -2 do
        t:SetFont(T.FONT, size, flags)
        if fits() then return end
    end
    -- last resort: clip to the gap
    local lw = clusterWidth(frame._hdrLeft, Chrome.PAD - 2, 6)
    local rw = clusterWidth(frame._hdrRight, Chrome.PAD - 6, 4)
    t:ClearAllPoints()
    t:SetPoint("LEFT", frame.titleBar, "LEFT", lw + 4, 0)
    t:SetPoint("RIGHT", frame.titleBar, "RIGHT", -(rw + 4), 0)
    t:SetWordWrap(false)
end

-- A small header button (Log, History, Settings...).
function Chrome:HeaderButton(frame, text, width, onClick, variant)
    local b = T:Button(frame.titleBar or frame, text, width or 70, Chrome.HEADER_BTN_H, variant or "secondary")
    if onClick then b:SetScript("OnClick", onClick) end
    return b
end

function Chrome:HowToPlayButton(frame, gameKey)
    local b = T:Button(frame.titleBar or frame, "How to Play", 86, Chrome.HEADER_BTN_H, "secondary")
    b:SetScript("OnClick", function()
        if UI.Lobby and UI.Lobby.ShowHowToPlay then UI.Lobby:ShowHowToPlay(gameKey) end
    end)
    -- narrow windows fold this to "?" (Chrome.LayoutTitleFor); the tooltip
    -- keeps the meaning
    BJ.Theme:Tooltip(b, "How to Play", "The rules of this game")
    return b
end

-- A titled section inside a window body: a panel with a small gold
-- caption on its top edge. Returns panel, caption.
function Chrome:Section(parent, caption, w, h, kind)
    local p = T:Panel(parent, kind or "panel", w, h)
    local cap
    if caption then
        cap = p:CreateFontString(nil, "OVERLAY", "CCFontSmall")
        cap:SetPoint("BOTTOMLEFT", p, "TOPLEFT", 4, 2)
        cap:SetText(string.upper(caption))
        p.caption = cap
    end
    return p, cap
end

-- A popup/dialog that floats over a window (bet pickers, confirmations,
-- host panels). Same chrome, no lobby on close, DIALOG strata.
function Chrome:CreateDialog(opts)
    opts = opts or {}
    opts.noLobby = true
    opts.strata = opts.strata or "DIALOG"
    return self:CreateWindow(opts)
end
