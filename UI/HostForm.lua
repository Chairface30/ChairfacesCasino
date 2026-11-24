--[[
    Chairface's Casino - UI/HostForm.lua
    ============================================
    The "host a table" settings popup every game uses. A game describes
    its settings as a list of fields; the form lays them out top to bottom
    in the casino style, loads them from / saves them to BJ.HostSettings,
    and ends with Start / Cancel and the fake-play checkbox.

        local form = UI.HostForm:Create({
            name = "PokerHostPanel", title = "5 Card Stud - Host",
            onStart = function(form) ... form:Get("pokerAnte") ... end,
        })
        form:Number("pokerAnte", "Ante (1-1000g):", { default = 10, min = 1, max = 1000, unit = "g" })
        form:Choice("pokerMaxPlayers", "Max Players:", { 2, 3, 4, 5, 6, 7, 8, 9, 10 }, { default = 10 })
        form:Countdown("pokerCountdownEnabled", "pokerCountdownSeconds", "Time to Join / Deal:")
        form:Check("holdemTournament", "Tournament", { tooltip = { ... } })
        form:Finish()
        form:Show()        -- reloads every field from HostSettings first

    Field kinds
      Number   edit box (+ unit), clamped on read, saved when Start is pressed
      Choice   a row of option buttons; saved the moment one is picked
      Countdown  on/off + seconds buttons; picking seconds switches it on
      Check    checkbox; saved on click
]]

local BJ = ChairfacesCasino
local UI = BJ.UI
local T = BJ.Theme

local HostForm = {}
UI.HostForm = HostForm

local PAD = 16
local Form = {}
Form.__index = Form

local function HS() return BJ.HostSettings end
local function load(key, default)
    local v = HS() and HS():Get(key)
    if v == nil then v = default end
    return v
end
local function save(key, v)
    if HS() then HS():Set(key, v) end
end

function HostForm:Create(opts)
    local W = opts.width or 300
    local frame = UI.Chrome:CreateDialog({
        name = opts.name,
        title = opts.title or "Host Settings",
        width = W, height = 200,
    })
    frame.titleText:SetFontObject("CCFontMedium")
    frame:SetFrameLevel(100)
    local form = setmetatable({
        frame = frame, opts = opts, W = W,
        y = frame.BODY_TOP - 12,
        fields = {}, order = {},
    }, Form)
    frame.form = form
    if BJ.EscapeHandler and opts.name then BJ.EscapeHandler:RegisterFrame(opts.name) end
    return form
end

-- a field label (white), optional tooltip, optional right-hand status text
function Form:Label(text, tooltip)
    local fs = self.frame:CreateFontString(nil, "OVERLAY", "CCFontHighlight")
    fs:SetPoint("TOPLEFT", PAD, self.y)
    fs:SetText(text)
    if tooltip then
        local hit = CreateFrame("Button", nil, self.frame)
        hit:SetAllPoints(fs)
        T:Tooltip(hit, unpack(tooltip))
    end
    local status = self.frame:CreateFontString(nil, "OVERLAY", "CCFontDimSmall")
    status:SetPoint("LEFT", fs, "RIGHT", 8, 0)
    self.y = self.y - 20
    return fs, status
end

function Form:Space(dy) self.y = self.y - (dy or 8) end

function Form:add(key, field)
    field.key = key
    self.fields[key] = field
    self.order[#self.order + 1] = field
    return field
end

-- ---------- Number ----------
function Form:Number(key, label, o)
    o = o or {}
    self:Label(label, o.tooltip)
    local box = T:EditBox(self.frame, o.width or 100, 26)
    box:SetPoint("TOPLEFT", PAD, self.y)
    box:SetNumeric(true)
    box:SetMaxLetters(o.letters or 4)
    box:SetJustifyH("CENTER")
    box:SetScript("OnEnterPressed", function(b) b:ClearFocus() end)
    if o.unit then
        local u = self.frame:CreateFontString(nil, "OVERLAY", "CCFontLarge")
        u:SetPoint("LEFT", box, "RIGHT", 8, 0)
        u:SetText(o.unit)
    end
    self.y = self.y - 36
    local field = self:add(key, {
        box = box,
        load = function() box:SetText(tostring(load(key, o.default or 0))) end,
        get = function()
            local v = tonumber(box:GetText()) or o.default or 0
            if o.min then v = math.max(o.min, v) end
            if o.max then v = math.min(o.max, v) end
            return v
        end,
    })
    field.save = function() save(key, field.get()) end
    return field
end

-- ---------- option rows ----------
local function optionRow(self, values, o, onPick)
    local btnW = o.buttonWidth or 34
    local x, buttons = PAD, {}
    for _, v in ipairs(values) do
        if x + btnW > self.W - PAD then          -- wrap long rows
            x = PAD
            self.y = self.y - 26
        end
        local b = T:Button(self.frame, o.text and o.text(v) or tostring(v), btnW, 22, "secondary")
        b:SetPoint("TOPLEFT", x, self.y)
        b:SetScript("OnClick", function() onPick(v) end)
        b.value = v
        buttons[#buttons + 1] = b
        x = x + btnW + 4
    end
    self.y = self.y - 32
    return buttons
end

local function paintRow(buttons, selected, dim)
    for _, b in ipairs(buttons) do
        T:SetButtonVariant(b, (b.value == selected and not dim) and "primary" or "secondary")
        b:SetAlpha(dim and 0.45 or 1)
    end
end

function Form:Choice(key, label, values, o)
    o = o or {}
    local _, status = self:Label(label, o.tooltip)
    local field
    local buttons = optionRow(self, values, o, function(v)
        save(key, v)
        field.load()
        if o.onPick then o.onPick(v) end
    end)
    field = self:add(key, {
        buttons = buttons,
        load = function()
            local v = load(key, o.default)
            paintRow(buttons, v, false)
            status:SetText(o.status and o.status(v) or "")
        end,
        get = function() return load(key, o.default) end,
    })
    return field
end

function Form:Countdown(enabledKey, secondsKey, label, o)
    o = o or {}
    local values = o.values or { 10, 15, 20, 30, 45, 60 }
    local _, status = self:Label(label, o.tooltip)
    local toggle = T:Check(self.frame, "", 18)
    toggle:SetPoint("TOPLEFT", PAD + 150, self.y + 22)
    status:ClearAllPoints()
    status:SetPoint("LEFT", toggle, "RIGHT", 4, 0)
    local field
    local buttons = optionRow(self, values, { buttonWidth = 40, text = function(v) return v .. "s" end },
        function(v)
            save(secondsKey, v)
            save(enabledKey, true)
            field.load()
        end)
    toggle:SetScript("OnClick", function(cb)
        save(enabledKey, cb:GetChecked() and true or false)
        field.load()
    end)
    field = self:add(secondsKey, {
        toggle = toggle, buttons = buttons,
        load = function()
            local on = load(enabledKey, false) and true or false
            local secs = load(secondsKey, o.default or 15)
            toggle:SetChecked(on)
            paintRow(buttons, secs, not on)
            status:SetText(on and (secs .. "s") or (o.offText or "Off"))
        end,
        get = function()
            return load(enabledKey, false) and true or false, load(secondsKey, o.default or 15)
        end,
    })
    return field
end

function Form:Check(key, label, o)
    o = o or {}
    local cb = T:Check(self.frame, label, 18)
    cb:SetPoint("TOPLEFT", PAD - 2, self.y)
    cb.text:SetFontObject("CCFontNormal")
    cb:SetLabel(label)
    if o.tooltip then T:Tooltip(cb, unpack(o.tooltip)) end
    cb:SetScript("OnClick", function(b)
        save(key, b:GetChecked() and true or false)
        if o.onChange then o.onChange(b:GetChecked()) end
    end)
    self.y = self.y - 28
    return self:add(key, {
        check = cb,
        load = function() cb:SetChecked(load(key, o.default or false) and true or false) end,
        get = function() return cb:GetChecked() and true or false end,
    })
end

-- ---------- finishing ----------
function Form:Get(key)
    local f = self.fields[key]
    if f then return f.get() end
end

function Form:Field(key) return self.fields[key] end

function Form:Refresh()
    for _, f in ipairs(self.order) do f.load() end
end

-- Save the typed fields (numbers); choices/checks save as they change.
function Form:Commit()
    for _, f in ipairs(self.order) do
        if f.save then f.save() end
    end
end

function Form:Finish()
    self.y = self.y - 6
    local start = T:Button(self.frame, self.opts.startText or "Start Game", 120, 30, "primary")
    start:SetPoint("TOPLEFT", PAD, self.y)
    start:SetScript("OnClick", function()
        self:Commit()
        if self.opts.onStart then self.opts.onStart(self) end
    end)
    local cancel = T:Button(self.frame, "Cancel", 90, 30, "secondary")
    cancel:SetPoint("LEFT", start, "RIGHT", 10, 0)
    cancel:SetScript("OnClick", function() self.frame:Hide() end)
    self.startBtn, self.cancelBtn = start, cancel
    self.y = self.y - 36
    -- fake play (fun games record no debts) right where hosting starts
    if UI.Debts and UI.Debts.AttachFakePlayCheck then
        UI.Debts:AttachFakePlayCheck(self.frame, "TOPLEFT", start, "BOTTOMLEFT", 0, -8)
        self.y = self.y - 26
    end
    self.frame:SetHeight(-self.y + 12)
    return self
end

function Form:Show()
    self:Refresh()
    self.frame:Show()
    if self.order[1] and self.order[1].box then self.order[1].box:SetFocus() end
end

function Form:Hide() self.frame:Hide() end
function Form:IsShown() return self.frame:IsShown() end
