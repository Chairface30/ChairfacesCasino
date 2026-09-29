"""Headless smoke test for UI/ReelsFrame.lua (the Slot Floor windows).

Loads the real engine + UI against a mocked WoW frame API, then drives
whole spins on every machine - base games, free games, the Darkmoon wheel,
the Jade pick-em, Bonanza tumbles, auto-spin, closing mid-spin - by pumping
OnUpdate and C_Timer on a fake clock. Catches Lua errors and checks the
money: the meter never shows unrevealed credits, and everything a spin won
is revealed by the time the machine idles.
Run: python tests/reels_ui_test.py  (pip install lupa)
"""
import lupa
import os
import sys

ADDON_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

MOCK = r"""
unpack = unpack or table.unpack
math.randomseed(777)
__now = 0
__timers = {}
C_Timer = {
  After = function(secs, fn) table.insert(__timers, { at = __now + secs, fn = fn }) end,
  NewTicker = function() return { Cancel = function() end } end,
}
function GetTime() return __now end
function time() return 1000000 + math.floor(__now) end
UIParent = nil
GameTooltip = setmetatable({}, { __index = function() return function() end end })
function BreakUpLargeNumbers(n) return tostring(n) end
function strsplit(sep, s)
  local out = {}
  for piece in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = piece end
  return unpack(out)
end
strlower = string.lower
UISpecialFrames = {}
tinsert = table.insert

local frames = {}
local Obj = {}
Obj.__index = function(t, k)
  local v = rawget(Obj, k)
  if v then return v end
  -- every other widget METHOD (CapitalCase, like WoW's) is a no-op;
  -- lowercase keys are the addon's own fields and stay nil
  if type(k) == "string" and k:match("^%u") then return function() end end
end
function Obj:SetSize(w, h) rawset(self, "_w", w); rawset(self, "_h", h) end
function Obj:SetWidth(w) rawset(self, "_w", w) end
function Obj:SetHeight(h) rawset(self, "_h", h) end
function Obj:GetWidth() return rawget(self, "_w") or 0 end
function Obj:GetHeight() return rawget(self, "_h") or 0 end
function Obj:SetText(t) rawset(self, "_text", t) end
function Obj:GetText() return rawget(self, "_text") end
function Obj:GetName() return rawget(self, "_name") end
function Obj:GetFrameLevel() return 1 end
function Obj:IsShown() return rawget(self, "_shown") ~= false end
function Obj:IsVisible() return self:IsShown() end
function Obj:Show()
  local was = self:IsShown()
  rawset(self, "_shown", true)
  if not was and rawget(self, "_scripts") and rawget(self, "_scripts").OnShow then self._scripts.OnShow(self) end
end
function Obj:Hide()
  local was = self:IsShown()
  rawset(self, "_shown", false)
  if was and rawget(self, "_scripts") and rawget(self, "_scripts").OnHide then self._scripts.OnHide(self) end
end
function Obj:SetShown(v) if v then self:Show() else self:Hide() end end
function Obj:SetScript(name, fn)
  rawset(self, "_scripts", rawget(self, "_scripts") or {})
  rawget(self, "_scripts")[name] = fn
end
function Obj:GetScript(name) local s = rawget(self, "_scripts") return s and s[name] end
function Obj:HookScript(name, fn)
  rawset(self, "_scripts", rawget(self, "_scripts") or {})
  local old = rawget(self, "_scripts")[name]
  rawget(self, "_scripts")[name] = function(...) if old then old(...) end fn(...) end
end
function Obj:IsEnabled() return rawget(self, "_enabled") ~= false end
function Obj:SetEnabled(v)
  local was = self:IsEnabled()
  rawset(self, "_enabled", v and true or false)
  local s = rawget(self, "_scripts") or {}
  if v and not was and s.OnEnable then s.OnEnable(self) end
  if (not v) and was and s.OnDisable then s.OnDisable(self) end
end
function Obj:Enable() self:SetEnabled(true) end
function Obj:Disable() self:SetEnabled(false) end
function Obj:Click(button) if rawget(self, "_scripts") and rawget(self, "_scripts").OnClick then self._scripts.OnClick(self, button or "LeftButton") end end
local function new(name)
  local o = setmetatable({ _name = name }, Obj)
  frames[#frames + 1] = o
  if name then _G[name] = o end
  return o
end
function Obj:CreateTexture() return new() end
function Obj:CreateFontString() return new() end
function CreateFrame(kind, name, parent, template)
  local f = new(name)
  rawset(f, "_parent", parent)
  if template == "UIPanelCloseButton" then rawset(f, "_close", true) end
  return f
end
function __pumpUpdates(dt)
  for _, f in ipairs(frames) do
    local s = rawget(f, "_scripts")
    if s and s.OnUpdate then
      -- only while its window is shown
      local p, vis = f, true
      while p do if rawget(p, "_shown") == false then vis = false break end p = rawget(p, "_parent") end
      if vis then s.OnUpdate(f, dt) end
    end
  end
end
function __advance(secs)
  local stepDt = 1 / 30
  local target = __now + secs
  while __now < target do
    __now = __now + stepDt
    __pumpUpdates(stepDt)
    local due = {}
    local keep = {}
    for _, t in ipairs(__timers) do
      if t.at <= __now then due[#due + 1] = t else keep[#keep + 1] = t end
    end
    __timers = keep
    table.sort(due, function(a, b) return a.at < b.at end)
    for _, t in ipairs(due) do t.fn() end
  end
end

__sfx = 0
__db = { credits = 5000000 }
ChairfacesCasino = {
  UI = { Lobby = { Show = function() end, TrixieReact = function() end, PlayTrixieVoice = function() end } },
  Print = function(self, msg) __lastPrint = msg end,
  PlaySfx = function() __sfx = __sfx + 1 end,
  EscapeHandler = { RegisterFrame = function() end },
  Arcade = {
    COMP_AMOUNT = 100,
    GetDB = function() return __db end,
    GetCredits = function() return __db.credits end,
    Spend = function(self, n) if __db.credits < n then return false end __db.credits = __db.credits - n return true end,
    Award = function(self, n) __db.credits = __db.credits + n end,
    CompMe = function() __db.credits = 100 return true, 1 end,
  },
}
"""

rt = lupa.LuaRuntime(unpack_returned_tuples=True)
rt.execute(MOCK)
for rel in (("Games", "ArcadeReels.lua"), ("UI", "ReelsFrame.lua")):
    rt.execute(open(os.path.join(ADDON_DIR, *rel), encoding="utf-8").read())

failures = []
def check(label, cond, detail=""):
    if not cond:
        failures.append(label)
    print(("PASS  " if cond else "FAIL  ") + label + (f"  [{detail}]" if detail and not cond else ""))

ev, lua = rt.eval, rt.execute

lua("""
UIR = ChairfacesCasino.UI.Reels
Floor = ChairfacesCasino.UI.SlotFloor
R = ChairfacesCasino.Arcade.Reels
""")

# the floor builds and opens each machine
ok = ev("""(function()
  Floor:Show()
  if not Floor.frame:IsShown() then return false end
  if #Floor.tiles ~= 6 then return false end
  Floor.tiles[2]:Click()        -- Kodo Stampede
  return UIR.frames.kodo ~= nil and UIR.frames.kodo:IsShown() and not Floor.frame:IsShown()
end)()""")
check("slot floor opens a machine", ok)

lua("""
function __spinAndWait(id, maxSecs)
  local f = UIR.frames[id]
  local startCredits = __db.credits
  f.spinBtn:Click()
  local res = f.state.result
  local shownMax = 0
  local t = 0
  local leaked = false
  while f.state.busy and t < (maxSecs or 600) do
    __advance(0.5)
    t = t + 0.5
    -- the meter may never show credits that haven't been revealed yet
    local shown = UIR:ShownCredits(f)
    if shown > startCredits - res.cost + (f.state.shownWin or 0) + 1 then leaked = true end
    -- the pick-em waits for clicks: take the next coin whenever it's up
    if f.pick and f.pick:IsShown() then
      for i, b in ipairs(f.pick.coins) do
        if not b.taken and b:IsEnabled() then b:Click() break end
      end
    end
  end
  return res, f.state.busy, f.state.pending, leaked, f.state.shownWin
end
""")

def run(id, label, force=None, level=None, spins=1, maxSecs=900):
    if level is not None:
        lua(f"UIR.frames.{id} = UIR.frames.{id} or UIR:Build(R.byId.{id}); UIR.frames.{id}.state.level = {level}")
    lua(f"UIR:ShowMachine('{id}')")
    for i in range(spins):
        if force:
            lua(f"R.forceNext = {{ id = '{id}', kind = '{force}' }}")
        res, busy, pending, leaked, shown = ev(f"__spinAndWait('{id}', {maxSecs})")
        if res is None:
            check(f"{label}: spin started", False, ev("__lastPrint"))
            return None
        total = res.total
        check(f"{label} #{i+1}: finishes and idles", not busy)
        check(f"{label} #{i+1}: nothing left pending", pending == 0, pending)
        check(f"{label} #{i+1}: meter never ran ahead of the reveal", not leaked)
        check(f"{label} #{i+1}: WIN meter shows the whole win", shown == total, f"{shown} vs {total}")
    return res

for mid in ("kodo", "pharaoh", "darkmoon", "jade", "bonanza"):
    run(mid, f"{mid} base", spins=12)

res = run("kodo", "kodo free games", force="free")
check("kodo free games were played", res is not None and len(res.free) >= 8)
res = run("pharaoh", "pharaoh free spins", force="free")
check("pharaoh free spins were played", res is not None and len(res.free) >= 15)
res = run("jade", "jade free games", force="free")
check("jade free games were played", res is not None and len(res.free) >= 10)
res = run("bonanza", "bonanza free spins", force="free")
check("bonanza free spins were played", res is not None and len(res.free) >= 10)
res = run("darkmoon", "darkmoon wheel", force="wheel", level=3)
check("darkmoon wheel turned", res is not None and res.wheel is not None)
res = run("darkmoon", "darkmoon short-coined SPIN", force="wheel", level=1)
check("darkmoon wheel stays dark at 1 coin", res is not None and res.wheel is None and res.wheelMissed)
res = run("jade", "jade pick-em", force="pick", level=5)
check("jade pick-em paid a jackpot", res is not None and res.pick is not None)

# auto-spin runs a batch down to zero
ok = ev("""(function()
  UIR:ShowMachine('pharaoh')
  local f = UIR.frames.pharaoh
  f.autoBtn:Click("LeftButton")
  local t = 0
  while (f.state.autoLeft > 0 or f.state.busy) and t < 2000 do __advance(1); t = t + 1 end
  return f.state.autoLeft == 0 and not f.state.busy
end)()""")
check("auto-spin runs its batch out", ok)

# closing mid-spin settles cleanly (the engine already paid)
ok = ev("""(function()
  UIR:ShowMachine('bonanza')
  local f = UIR.frames.bonanza
  R.forceNext = { id = 'bonanza', kind = 'free' }
  f.spinBtn:Click()
  __advance(3)
  f:Hide()
  __advance(30)
  return (not f.state.busy) and f.state.pending == 0
end)()""")
check("closing mid-feature settles and unlocks", ok)

# PAYS panel builds for every machine at every level
ok = ev("""(function()
  for _, m in ipairs(R.machines) do
    UIR:ShowMachine(m.id)
    local f = UIR.frames[m.id]
    for lvl = 1, R:MaxLevel(m) do
      f.state.level = lvl
      UIR:TogglePays(f); UIR:TogglePays(f)
    end
  end
  return true
end)()""")
check("PAYS panels build", ok)

print()
if failures:
    print(f"{len(failures)} FAILED: {failures}")
    sys.exit(1)
print("ALL PASS")
