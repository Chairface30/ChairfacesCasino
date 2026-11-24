"""Headless smoke test for the whole addon UI.

Loads every file in `Chairfaces Casino.toc`, in order, against a mocked WoW
API, fires ADDON_LOADED + PLAYER_LOGIN, then opens and closes every casino
window (and the Settings / Debts / LFG / leaderboard windows). Any Lua error
on the way fails the test. It checks wiring, not looks: a refactor that
leaves a nil method, a missing module or a bad frame call shows up here
instead of as a red error box in game.

Run: python tests/ui_smoke_test.py  (pip install lupa)
"""
import os
import sys

import lupa

ADDON_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

MOCK = r"""
unpack = unpack or table.unpack
math.randomseed(4242)
__now = 0
__timers = {}
local function noop() end

-- ---------- widgets ----------
local frames = {}
local Obj = {}
Obj.__index = function(t, k)
  local v = rawget(Obj, k)
  if v then return v end
  if type(k) == "string" and k:match("^%u") then return noop end
end
local function new(kind, name, parent)
  local o = setmetatable({ _name = name, _kind = kind, _parent = parent, _shown = true,
                           _w = 0, _h = 0, _children = {} }, Obj)
  frames[#frames + 1] = o
  if name then _G[name] = o end
  return o
end
__frames = frames
function Obj:SetSize(w, h) self._w, self._h = w, h; local s = self._scripts; if s and s.OnSizeChanged then s.OnSizeChanged(self, w, h) end end
function Obj:SetWidth(w) self._w = w end
function Obj:SetHeight(h) self._h = h end
function Obj:GetWidth() return self._w or 0 end
function Obj:GetHeight() return self._h or 0 end
function Obj:GetSize() return self._w or 0, self._h or 0 end
function Obj:GetCenter() return 0, 0 end
function Obj:GetLeft() return 0 end
function Obj:GetRight() return 0 end
function Obj:GetTop() return 0 end
function Obj:GetBottom() return 0 end
function Obj:GetEffectiveScale() return 1 end
function Obj:GetScale() return 1 end
function Obj:GetAlpha() return 1 end
function Obj:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
function Obj:GetNumPoints() return 1 end
function Obj:SetText(t) self._text = t end
function Obj:GetText() return self._text end
function Obj:SetFormattedText(fmt, ...) self._text = string.format(fmt, ...) end
function Obj:GetStringWidth() return #(tostring(self._text or "")) * 6 end
function Obj:GetStringHeight() return 12 end
function Obj:GetUnboundedStringWidth() return self:GetStringWidth() end
function Obj:GetNumLines() return 1 end
function Obj:GetFont() return "Fonts\\FRIZQT__.TTF", 12, "" end
function Obj:GetTextColor() return 1, 1, 1, 1 end
function Obj:GetVertexColor() return 1, 1, 1, 1 end
function Obj:GetBackdropColor() return 0, 0, 0, 1 end
function Obj:GetBackdropBorderColor() return 0, 0, 0, 1 end
function Obj:GetName() return self._name end
function Obj:GetParent() return self._parent end
function Obj:SetParent(p) self._parent = p end
function Obj:GetFrameLevel() return 1 end
function Obj:GetFrameStrata() return "HIGH" end
function Obj:GetObjectType() return self._kind end
function Obj:IsObjectType(k) return self._kind == k end
function Obj:GetTexture() return self._tex end
function Obj:SetTexture(t) self._tex = t end
function Obj:GetVerticalScroll() return 0 end
function Obj:GetVerticalScrollRange() return 0 end
function Obj:GetMinMaxValues() return 0, 100 end
function Obj:GetValue() return self._value or 0 end
function Obj:SetValue(v) self._value = v; local s = self._scripts; if s and s.OnValueChanged then s.OnValueChanged(self, v) end end
function Obj:GetChecked() return self._checked or false end
function Obj:SetChecked(v) self._checked = v and true or false end
function Obj:GetNumber() return tonumber(self._text) or 0 end
function Obj:HasFocus() return false end
function Obj:IsMouseOver() return false end
function Obj:IsShown() return self._shown ~= false end
function Obj:IsVisible()
  local p = self
  while p do if p._shown == false then return false end p = p._parent end
  return true
end
function Obj:Show()
  local was = self:IsShown(); self._shown = true
  local s = self._scripts
  if not was and s and s.OnShow then s.OnShow(self) end
end
function Obj:Hide()
  local was = self:IsShown(); self._shown = false
  local s = self._scripts
  if was and s and s.OnHide then s.OnHide(self) end
end
function Obj:SetShown(v) if v then self:Show() else self:Hide() end end
function Obj:SetScript(name, fn) self._scripts = self._scripts or {}; self._scripts[name] = fn end
function Obj:GetScript(name) return self._scripts and self._scripts[name] end
function Obj:HasScript() return true end
function Obj:HookScript(name, fn)
  self._scripts = self._scripts or {}
  local old = self._scripts[name]
  self._scripts[name] = function(...) if old then old(...) end return fn(...) end
end
function Obj:IsEnabled() return self._enabled ~= false end
function Obj:SetEnabled(v)
  local was = self:IsEnabled(); self._enabled = v and true or false
  local s = self._scripts or {}
  if v and not was and s.OnEnable then s.OnEnable(self) end
  if (not v) and was and s.OnDisable then s.OnDisable(self) end
end
function Obj:Enable() self:SetEnabled(true) end
function Obj:Disable() self:SetEnabled(false) end
function Obj:Click(button) local s = self._scripts; if s and s.OnClick then s.OnClick(self, button or "LeftButton", true) end end
function Obj:RegisterEvent(e) self._events = self._events or {}; self._events[e] = true end
function Obj:CreateTexture(name) return new("Texture", name, self) end
function Obj:CreateFontString(name) return new("FontString", name, self) end
function Obj:CreateMaskTexture(name) return new("Texture", name, self) end
function Obj:CreateLine(name) return new("Line", name, self) end
function Obj:CreateAnimationGroup()
  local g = new("AnimationGroup", nil, self)
  g.CreateAnimation = function() return new("Animation", nil, g) end
  return g
end
function Obj:GetFontString() return self._fs end
function Obj:SetFontString(fs) self._fs = fs end
function Obj:GetChildren() return end
function Obj:GetRegions() return end
function CreateFrame(kind, name, parent, template)
  local f = new(kind, name, parent)
  if template and template:find("ScrollFrameTemplate") then
    f.ScrollBar = new("Slider", name and (name .. "ScrollBar"), f)
  end
  if template and template:find("SliderTemplate") then
    f.Low = new("FontString", name and (name .. "Low"), f)
    f.High = new("FontString", name and (name .. "High"), f)
    f.Text = new("FontString", name and (name .. "Text"), f)
  end
  if template and template:find("CheckButtonTemplate") then
    f.Text = new("FontString", name and (name .. "Text"), f); f.text = f.Text
  end
  return f
end
function CreateFont(name) local f = new("Font", name); _G[name] = f; return f end
UIParent = new("Frame", "UIParent")
WorldFrame = new("Frame", "WorldFrame")
Minimap = new("Frame", "Minimap")
GameTooltip = new("GameTooltip", "GameTooltip")
ItemRefTooltip = new("GameTooltip", "ItemRefTooltip")
DEFAULT_CHAT_FRAME = new("Frame", "DEFAULT_CHAT_FRAME")
DEFAULT_CHAT_FRAME.AddMessage = function(self, msg) __chat = msg end
ChatFrame1 = DEFAULT_CHAT_FRAME
TradeFrame = new("Frame", "TradeFrame")
MailFrame = new("Frame", "MailFrame")
SendMailFrame = new("Frame", "SendMailFrame")

-- ---------- api ----------
C_Timer = {
  After = function(secs, fn) table.insert(__timers, { at = __now + (secs or 0), fn = fn }) end,
  NewTicker = function(secs, fn, n) local t = { Cancel = noop, IsCancelled = function() return false end }; return t end,
  NewTimer = function(secs, fn) local t = { Cancel = noop, IsCancelled = function() return false end }; table.insert(__timers, { at = __now + secs, fn = fn }); return t end,
}
C_ChatInfo = { RegisterAddonMessagePrefix = function() return true end, SendAddonMessage = noop,
               IsAddonMessagePrefixRegistered = function() return true end }
C_AddOns = { GetAddOnMetadata = function() return "2.6.10" end, IsAddOnLoaded = function() return false end }
function GetAddOnMetadata() return "2.6.10" end
function IsAddOnLoaded() return false end
function GetTime() return __now end
function time() return 1700000000 + math.floor(__now) end
function date(fmt, t) return os.date(fmt or "%c", t) end
function GetServerTime() return time() end
function debugprofilestop() return __now * 1000 end
function UnitName(u) return "Chairface", "Chippendale" end
function UnitFullName(u) return "Chairface", "Chippendale" end
function GetRealmName() return "Forever" end
function GetNormalizedRealmName() return "Forever" end
function UnitGUID() return "Player-1-0001" end
function UnitExists(u) return u == "player" end
function UnitIsConnected() return true end
function UnitClass() return "Warrior", "WARRIOR" end
function UnitRace() return "Human", "Human" end
function UnitSex() return 2 end
function UnitLevel() return 60 end
function UnitFactionGroup() return "Alliance" end
function UnitIsGroupLeader() return false end
function UnitIsGroupAssistant() return false end
function UnitInParty() return false end
function UnitInRaid() return nil end
function IsInGroup() return false end
function IsInRaid() return false end
function IsInGuild() return false end
function GetNumGroupMembers() return 0 end
function GetNumSubgroupMembers() return 0 end
function GetMoney() return 1000000 end
function GetCursorPosition() return 0, 0 end
function GetScreenWidth() return 1920 end
function GetScreenHeight() return 1080 end
function GetLocale() return "enUS" end
function GetBuildInfo() return "1.0.0", "1", "Nov 2026", 16001 end
function GetChannelName() return 0 end
function GetChannelList() return end
function JoinChannelByName() return end
function JoinTemporaryChannel() return end
function GetCVar() return "0" end
function SetCVar() end
function PlaySound() return true end
function PlaySoundFile() return true, 1 end
function PlayMusic() end
function StopSound() end
function InCombatLockdown() return false end
function IsShiftKeyDown() return false end
function IsControlKeyDown() return false end
function IsAltKeyDown() return false end
function GetMouseFocus() return nil end
function hooksecurefunc(a, b, c) end
function issecurevariable() return true end
function securecall(f, ...) return f(...) end
function BreakUpLargeNumbers(n) return tostring(n) end
function FormatLargeNumber(n) return tostring(n) end
function strsplit(sep, s, n)
  local out = {}
  for piece in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = piece end
  return unpack(out)
end
function strjoin(sep, ...) return table.concat({ ... }, sep) end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function strsub(...) return string.sub(...) end
strlower, strupper, strlen, strfind, strmatch, strrep, format, gsub, strbyte, strchar, gmatch =
  string.lower, string.upper, string.len, string.find, string.match, string.rep, string.format, string.gsub, string.byte, string.char, string.gmatch
tinsert, tremove, wipe, tContains = table.insert, table.remove, function(t) for k in pairs(t) do t[k] = nil end return t end,
  function(t, v) for _, x in pairs(t) do if x == v then return true end end return false end
floor, ceil, abs, max, min, sqrt, random = math.floor, math.ceil, math.abs, math.max, math.min, math.sqrt, math.random
mod = math.fmod
bit = bit or { bxor = function(a, b) return a ~ b end, band = function(a, b) return a & b end,
               bor = function(a, b) return a | b end, lshift = function(a, b) return a << b end,
               rshift = function(a, b) return a >> b end }
function Mixin(o, ...) for _, m in ipairs({ ... }) do for k, v in pairs(m) do o[k] = v end end return o end
function CreateFromMixins(...) return Mixin({}, ...) end
BackdropTemplateMixin = {}
function SecondsToTime(s) return tostring(s) .. "s" end
UISpecialFrames = {}
function CreateColor(r, g, b, a)
  return { r = r, g = g, b = b, a = a, GetRGB = function(s) return s.r, s.g, s.b end,
           GetRGBA = function(s) return s.r, s.g, s.b, s.a end }
end
-- WoW's Lua 5.1 floors a float passed to %d; Lua 5.3+ raises instead
do
  local fmt = string.format
  string.format = function(f, ...)
    local ok, out = pcall(fmt, f, ...)
    if ok then return out end
    local args = { ... }
    for i = 1, select("#", ...) do
      if type(args[i]) == "number" and args[i] ~= math.floor(args[i]) then args[i] = math.floor(args[i]) end
    end
    return fmt(f, unpack(args, 1, select("#", ...)))
  end
  format = string.format
end
StaticPopupDialogs = {}
function StaticPopup_Show() end
function StaticPopup_Hide() end
SlashCmdList = {}
RAID_CLASS_COLORS = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1, colorStr = "ffffffff" } end })
NUM_CHAT_WINDOWS = 1
function ChatFrame_AddMessageEventFilter() end
function ChatFrame_RemoveMessageEventFilter() end
function UIDropDownMenu_Initialize() end
function UIDropDownMenu_SetWidth() end
function UIDropDownMenu_SetText() end
function UIDropDownMenu_CreateInfo() return {} end
function UIDropDownMenu_AddButton() end
function UIDropDownMenu_SetSelectedValue() end
function EasyMenu() end
function ToggleDropDownMenu() end
function SendChatMessage() end
function InviteUnit() end
function InitiateTrade() end
function GetPlayerTradeMoney() return 0 end
function GetTargetTradeMoney() return 0 end
function SetTradeMoney() end
function ChatEdit_InsertLink() return false end
function ChatFrame_OpenChat() end
function GetInboxNumItems() return 0, 0 end
function CheckInbox() end
function C_Timer_After(...) end
C_Map = { GetBestMapForUnit = function() return nil end }
C_CVar = { GetCVar = function() return "0" end, SetCVar = noop }
C_PartyInfo = { InviteUnit = noop }
C_FriendList = { SendWho = noop }
C_Container = {}
Enum = setmetatable({}, { __index = function() return {} end })
SOUNDKIT = setmetatable({}, { __index = function() return 1 end })
LE_PARTY_CATEGORY_HOME, LE_PARTY_CATEGORY_INSTANCE = 1, 2

-- ---------- clock ----------
function __advance(secs)
  local target = __now + secs
  while __now < target do
    __now = __now + 0.1
    for _, f in ipairs(frames) do
      local s = f._scripts
      if s and s.OnUpdate and f:IsVisible() then s.OnUpdate(f, 0.1) end
    end
    local due, keep = {}, {}
    for _, t in ipairs(__timers) do if t.at <= __now then due[#due + 1] = t else keep[#keep + 1] = t end end
    __timers = keep
    table.sort(due, function(a, b) return a.at < b.at end)
    for _, t in ipairs(due) do t.fn() end
  end
end

function __fire(event, ...)
  for _, f in ipairs(frames) do
    local s = f._scripts
    if f._events and f._events[event] and s and s.OnEvent then s.OnEvent(f, event, ...) end
  end
end
"""


def toc_files():
    out = []
    for line in open(os.path.join(ADDON_DIR, "Chairfaces Casino.toc"), encoding="utf-8"):
        line = line.strip()
        if line and not line.startswith("#"):
            out.append(line.replace("\\", os.sep))
    return out


def main():
    rt = lupa.LuaRuntime(unpack_returned_tuples=True)
    rt.execute(MOCK)
    rt.execute("__NS = {}")
    load = rt.eval("function(src, name, addon) local f, e = load(src, '@' .. name) if not f then error(e) end return f(addon, __NS) end")
    failures = []
    for rel in toc_files():
        path = os.path.join(ADDON_DIR, rel)
        try:
            load(open(path, encoding="utf-8").read(), rel, "Chairfaces Casino")
        except lupa.LuaError as e:
            failures.append(f"load {rel}: {e}")
            print("FAIL  load", rel, "\n     ", str(e).splitlines()[0])
    if failures:
        print("\n%d file(s) failed to load" % len(failures))
        sys.exit(1)
    print("PASS  every .toc file loads")

    def step(label, lua_code):
        try:
            rt.execute(lua_code)
            print("PASS ", label)
        except lupa.LuaError as e:
            failures.append(label)
            msg = str(e)
            print("FAIL ", label, "\n     ", "\n      ".join(msg.splitlines()[:6]))

    step("ADDON_LOADED + PLAYER_LOGIN", """
        __fire("ADDON_LOADED", "Chairfaces Casino")
        __fire("PLAYER_LOGIN")
        __fire("PLAYER_ENTERING_WORLD", true, false)
        __advance(3)
    """)

    windows = [
        ("Lobby", "UI.Lobby:Show()", "UI.Lobby:Hide()"),
        ("Blackjack", "UI:Show()", "UI:Hide()"),
        ("5 Card Stud", "UI.Poker:Show()", "UI.Poker:Hide()"),
        ("Texas Hold'em", "UI.Holdem:Show()", "UI.Holdem:Hide()"),
        ("High-Lo", "UI.HiLo:Show()", "UI.HiLo:Hide()"),
        ("Death Roll", "UI.DeathRoll:Show()", "UI.DeathRoll:Hide()"),
        ("Liar's Dice", "UI.LiarsDice:Show()", "UI.LiarsDice:Hide()"),
        ("Bingo", "UI.Bingo:Show()", "UI.Bingo:Hide()"),
        ("Roulette", "UI.Roulette:Show()", "UI.Roulette:Hide()"),
        ("Crash", "UI.Crash:Show()", "UI.Crash:Hide()"),
        ("Slot Floor", "UI.SlotFloor:Show()", "UI.SlotFloor:Hide()"),
        ("Slots", "UI.Slots:Show()", "UI.Slots:Hide()"),
        ("Video Poker", "UI.VideoPoker:Show()", "UI.VideoPoker:Hide()"),
        ("Debts", "UI.Debts:Show()", "UI.Debts:Hide()"),
        ("Table Finder", "UI.Finder:Show()", "UI.Finder:Hide()"),
        ("Settings", "UI.Lobby:ShowSettings()", "if UI.Lobby.settingsFrame then UI.Lobby.settingsFrame:Hide() end"),
        ("All-time leaderboard", "BJ.LeaderboardUI:ShowAllTime()", "if BJ.Leaderboard.allTimeFrame then BJ.Leaderboard.allTimeFrame:Hide() end"),
        ("Chair's Cup", "SlashCmdList.CHAIRSCUP('')", "if SigmaDerbyFrame then SigmaDerbyFrame:Hide() end"),
    ]
    for label, show, hide in windows:
        step("open + close " + label, f"""
            local BJ = ChairfacesCasino
            local UI = BJ.UI
            {show}
            __advance(1)
            {hide}
            __advance(0.5)
        """)

    # every casino window that exists must be on the shared chrome
    step("game windows share the casino chrome", """
        local names = { "ChairfacesCasinoLobby", "ChairfacesCasinoRoulette",
                        "ChairfacesCasinoPoker", "ChairfacesCasinoHoldem" }
        for _, n in ipairs(names) do
            local f = _G[n]
            assert(f, n .. " was never built")
            assert(f.titleBar and f.closeBtn, n .. " is not built by UI.Chrome")
        end
    """)

    if failures:
        print("\n%d check(s) failed" % len(failures))
        sys.exit(1)
    print("\nALL PASS")


if __name__ == "__main__":
    main()
