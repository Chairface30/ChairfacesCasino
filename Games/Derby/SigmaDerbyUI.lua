--[[ SigmaDerbyUI.lua --------------------------------------------------------
  Chair's Cup - in-game quinella horse-race betting parlor (UI layer).

  Money model: the addon never touches gold. The host sets ONE stake amount
  and a per-player bet allotment; players place bets; after the race each
  player is shown a single net figure to collect or pay, settled by hand.

  Multiplayer: party/raid addon messaging. Whoever presses New Race becomes
  the bank for that race and broadcasts the seed; every client builds the
  identical race from it, so odds and result match on every screen.
---------------------------------------------------------------------------]]

local ADDON, ns = ...
local Engine = ns.Engine

local TITLE = "Chair's Cup"

-- ------- tunables -------
local HORSE_SIZE   = 26          -- doubled token size
local RACE_SECONDS = 45

-- stadium track geometry (two straights + semicircular ends). Footprint matches
-- the old oval (width 2*L + 2*R, height 2*R) so surrounding layout is unchanged.
local FRAME_W, FRAME_H = 1000, 700
local OVAL_CX, OVAL_CY = 500, 235     -- track centre (FINISH clears the title)
local TRACK_R = 172                   -- end-cap radius = half the track height
local TRACK_L = 288                   -- half-length of each straight
local LANE_GAP = 26                   -- radial spacing between the 5 lanes
local RAIL_DOTS = 220

local HORSE_COLORS = {
  {0.85,0.20,0.20}, {0.25,0.55,0.95}, {0.30,0.75,0.35},
  {0.90,0.80,0.20}, {0.70,0.45,0.85},
}

-- ------- runtime state -------
local race            -- current race from Engine.buildRace
local timeline        -- positions[h][tick]
local localStakes = {}-- localStakes[comboIdx] = gold you have staked this race
local raceRunning = false
local phase = "idle"  -- idle -> betting -> countdown -> running -> done
local countdownBetsOpen = false  -- true during the post-Run-Race last-call window

-- host-controlled settings (the ONLY stake anyone bets with, and the allotment)
local STAKE_STEPS = {1, 3, 5, 7, 10, 15, 25, 50, 100}
local stakeIdx = 3    -- default 5g; host can change
local hostMaxBets = 3 -- bets allowed per player

local resultFS        -- settlement readout (assigned in controls)
local seedText        -- seed + bank indicator (assigned in scaffolding)

-- multiplayer state
local PREFIX = "SigmaDerby"   -- internal id; unchanged so saved data/comms match
local PROTO  = 4              -- protocol version; bumped when message formats change
                              -- (v4: win-bet indices WIN_BASE+1..+5 in the books)
local isHost = false
local hostName = nil
local raceFakePlay = nil      -- fun/real status captured when WE host a race;
                              -- a mid-race fake-play toggle flip only affects
                              -- the next race we host (nil = live setting)
local remoteFakePlay = nil    -- fun/real status of the race we're BETTING in,
                              -- learned from the host's NEW/STATE (nil = unknown)
local remoteBook = {}         -- remoteBook[player][comboIdx] = stake
local settleBook = nil        -- host-authoritative final book for the current race
local versionWarned = false   -- so the mismatch warning prints only once
local pendingBets = {}        -- coalesced outgoing bet updates (throttled)
local flushScheduled = false
local driver = CreateFrame("Frame")  -- always-shown; runs the race clock even
                                     -- when the main window is closed

-- forward declarations (assigned later, called only at runtime)
local stakeDown, stakeUp, betsDown, betsUp, newBtn, runBtn, relinquishBtn
local refreshStake, refreshMaxBets, syncSettingsUI
local applyRace, hostStartRace, runRace, onUpdate, showPayouts
local updateSeedText, updateLocks, updateFakeBanner
local clearHighlight, highlightWinner, refreshCell
local applyTheme
local stopRocketSound   -- assigned with the speedway race audio below

-- ------- bet accounting (a "bet" is one host-stake unit on any line) -------
local function currentStake() return STAKE_STEPS[stakeIdx] end
local function totalStaked()
  local t = 0
  for _, s in pairs(localStakes) do t = t + (s or 0) end
  return t
end
local function betsUsed()
  local st = currentStake()
  return st > 0 and math.floor(totalStaked() / st + 0.5) or 0
end
local function remoteHasBets()
  for _, book in pairs(remoteBook) do
    for _, s in pairs(book) do if s and s > 0 then return true end end
  end
  return false
end
local function hasAnyBets() return betsUsed() > 0 or remoteHasBets() end

-- ------- comms -------
local function netChannel()
  if IsInRaid() then return "RAID" elseif IsInGroup() then return "PARTY" end
  return nil
end
local function netSend(msg)
  local ch = netChannel()
  if ch and C_ChatInfo and C_ChatInfo.SendAddonMessage then
    C_ChatInfo.SendAddonMessage(PREFIX, msg, ch)
  end
end

-- Throttled bet sender: coalesce per-combo (BET carries the current TOTAL on a
-- combo, so only the latest value matters) and drip out ~1 per 0.15s, staying
-- well under WoW's addon-message rate cap so nothing gets dropped or throttled.
local function flushBets()
  flushScheduled = false
  for idx, stake in pairs(pendingBets) do
    netSend("BET," .. idx .. "," .. stake)
    pendingBets[idx] = nil
    break                                   -- one per tick, spread the load
  end
  if next(pendingBets) then
    flushScheduled = true
    C_Timer.After(0.15, flushBets)
  end
end
local function queueBet(idx, stake)
  pendingBets[idx] = stake
  if not flushScheduled then
    flushScheduled = true
    C_Timer.After(0.15, flushBets)
  end
end
local function isSelf(sender)
  if not sender then return false end
  local short = Ambiguate and Ambiguate(sender, "short") or sender:gsub("%-.*$", "")
  return short == ChairfacesCasino:MyName()
end
-- First names, as every game shows them.
local function shortName(name)
  local CC = ChairfacesCasino
  if CC and CC.SeatName then return CC:SeatName(name) end
  return name and (Ambiguate and Ambiguate(name, "short") or name) or "?"
end

-- =====================================================================
--  Frame scaffolding
-- =====================================================================
local f = CreateFrame("Frame", "SigmaDerbyFrame", UIParent, "BackdropTemplate")
f:SetSize(FRAME_W, FRAME_H)
f:SetPoint("CENTER")
f:SetBackdrop({
  bgFile   = "Interface\\Buttons\\WHITE8X8",
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  tile = false, edgeSize = 16,
  insets = { left = 4, right = 4, top = 4, bottom = 4 },
})
f:SetBackdropColor(0.04, 0.04, 0.05, 0.95)
f:SetBackdropBorderColor(0.55, 0.45, 0.18, 1)
f:SetFrameStrata("HIGH")        -- sit above default world/UI frames
f:SetToplevel(true)             -- raise to front when clicked
f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
f:SetScript("OnDragStart", f.StartMoving)
f:SetScript("OnDragStop", function(self)
  self:StopMovingOrSizing()
  local point, _, relPoint, x, y = self:GetPoint()
  SigmaDerbyDB = SigmaDerbyDB or {}
  SigmaDerbyDB.win = { point = point, relPoint = relPoint, x = x, y = y }
end)
f:Hide()

local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOP", 0, -14)
title:SetText(TITLE)

local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", -4, -4)

-- Debts shortcut (settle-up ledger) next to the close button; guarded
-- because the derby stays loadable stand-alone
do
  local Debts = ChairfacesCasino and ChairfacesCasino.UI and ChairfacesCasino.UI.Debts
  if Debts and Debts.AttachDebtsIcon then
    Debts:AttachDebtsIcon(f, "RIGHT", close, "LEFT", -2, 0)
  end
end

local helpBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
helpBtn:SetSize(92, 20); helpBtn:SetText("How to Play")
helpBtn:SetPoint("TOPLEFT", 12, -12)

local histBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
histBtn:SetSize(70, 20); histBtn:SetText("History")
histBtn:SetPoint("LEFT", helpBtn, "RIGHT", 6, 0)

seedText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
seedText:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 12)
seedText:SetText("Seed: -")
local autoOpenCB = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
autoOpenCB:SetSize(26, 26)
autoOpenCB:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -150, 10)
local autoOpenLabel = autoOpenCB:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
autoOpenLabel:SetPoint("LEFT", autoOpenCB, "RIGHT", 2, 0)
autoOpenLabel:SetText("Auto-open on new race")

autoOpenCB:SetScript("OnClick", function(self)
  SigmaDerbyDB = SigmaDerbyDB or {}
  SigmaDerbyDB.autoOpen = self:GetChecked()
end)

-- cosmetic theme toggle: goblin rocket cars on asphalt instead of horses
-- on dirt. Per-client only - the race math is identical for every viewer.
local rocketCB = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
rocketCB:SetSize(26, 26)
rocketCB:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -330, 10)
local rocketLabel = rocketCB:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
rocketLabel:SetPoint("LEFT", rocketCB, "RIGHT", 2, 0)
rocketLabel:SetText("Rocket cars")
rocketCB:SetScript("OnClick", function(self)
  SigmaDerbyDB = SigmaDerbyDB or {}
  SigmaDerbyDB.theme = self:GetChecked() and "speedway" or "turf"
  if applyTheme then applyTheme() end
end)

-- the casino lobby's settings panel can flip autoOpen too: re-read the
-- saved value every time the derby window comes up
f:HookScript("OnShow", function()
  autoOpenCB:SetChecked(SigmaDerbyDB and SigmaDerbyDB.autoOpen and true or false)
end)
-- =====================================================================
--  Oval track + horses
-- =====================================================================
local function anchorCenter(region, x, y)
  region:ClearAllPoints()
  region:SetPoint("CENTER", f, "TOPLEFT", x, -y)
end

-- A point at arc-length fraction p in [0,1) around a stadium of end-cap radius R
-- (centred at OVAL_CX,OVAL_CY, straight half-length TRACK_L). p=0 is top centre;
-- the field runs counter-clockwise (left along the top first), like a real
-- track. Returns pixel coords in the frame's top-left / y-down space.
local function trackPoint(R, p)
  local arc = math.pi * R
  local per = 4 * TRACK_L + 2 * arc
  local d = (p - math.floor(p)) * per

  if d <= TRACK_L then
    -- Top straight: moving left. Facing = math.pi (180 degrees)
    return OVAL_CX - d, OVAL_CY - R, math.pi
  end
  
  d = d - TRACK_L
  if d <= arc then
    -- Left semicircle: top to bottom.
    local th = -math.pi / 2 - d / R
    -- The tangent movement vector is perpendicular to the radial angle
    local facing = th - math.pi / 2
    return (OVAL_CX - TRACK_L) + R * math.cos(th), OVAL_CY + R * math.sin(th), facing
  end
  
  d = d - arc
  if d <= 2 * TRACK_L then
    -- Bottom straight: moving right. Facing = 0 (0 degrees)
    return (OVAL_CX - TRACK_L) + d, OVAL_CY + R, 0
  end
  
  d = d - 2 * TRACK_L
  if d <= arc then
    -- Right semicircle: bottom to top.
    local th = -3 * math.pi / 2 - d / R
    local facing = th - math.pi / 2
    return (OVAL_CX + TRACK_L) + R * math.cos(th), OVAL_CY + R * math.sin(th), facing
  end
  
  d = d - arc
  -- Catch-all top straight remainder: moving left
  return (OVAL_CX + TRACK_L) - d, OVAL_CY - R, math.pi
end
-- per-horse lane radii (lane 1 outermost), all sharing the same straight length
local laneR = {}
for h = 1, Engine.HORSES do laneR[h] = TRACK_R - 18 - (h - 1) * LANE_GAP end
local innerR = laneR[Engine.HORSES] - LANE_GAP

-- fill a stadium with horizontal strips. At vertical offset dy the half-width is
-- TRACK_L + sqrt(R^2 - dy^2): flat straights top & bottom, rounded left/right.
local function fillStadium(R, r, g, b, a, sublevel)
  local rowH = 3
  local n = math.floor(R / rowH)
  local strips = {}
  for i = -n, n do
    local dy = i * rowH
    local hw = TRACK_L + math.sqrt(math.max(0, R * R - dy * dy))
    local strip = f:CreateTexture(nil, "BORDER", nil, sublevel)
    strip:SetColorTexture(r, g, b, a)
    strip:SetSize(hw * 2, rowH + 1)
    anchorCenter(strip, OVAL_CX, OVAL_CY + dy)
    strips[#strips + 1] = strip
  end
  return strips
end

-- green felt field (shows around the track), brown track band, green infield
local FELT = {0.07, 0.34, 0.17}
local DIRT = {0.46, 0.31, 0.17}
local ASPHALT = {0.16, 0.16, 0.19}   -- the speedway theme's track surface
local felt = f:CreateTexture(nil, "BORDER", nil, -8)
felt:SetColorTexture(FELT[1], FELT[2], FELT[3], 1)
felt:SetPoint("TOPLEFT",     f, "TOPLEFT", 10, -36)
felt:SetPoint("BOTTOMRIGHT", f, "TOPLEFT", FRAME_W - 10, -(OVAL_CY + TRACK_R + 16))
-- the band is kept so the theme can repaint dirt <-> asphalt at runtime
local trackStrips = fillStadium(TRACK_R, DIRT[1], DIRT[2], DIRT[3], 1, -7)
fillStadium(innerR, FELT[1], FELT[2], FELT[3], 1, -6)    -- green infield

-- Continuous railing (not dots): a smooth polyline that follows the straights
-- and turns, with periodic cross-posts on the outer rail.
local function railSeg(x1, y1, x2, y2, thick, r, g, b, a, layer)
  local ln = f:CreateLine(nil, layer or "ARTWORK")
  ln:SetThickness(thick)
  ln:SetColorTexture(r, g, b, a or 1)
  ln:SetStartPoint("TOPLEFT", f, x1, -y1)
  ln:SetEndPoint("TOPLEFT", f, x2, -y2)
  return ln
end

local function drawRail(R, thick, withPosts)
  local N = 180
  local px, py = trackPoint(R, 0)
  for i = 1, N do
    local x, y = trackPoint(R, i / N)
    railSeg(px, py, x, y, thick, 0.95, 0.95, 0.95, 1)      -- white rail
    px, py = x, y
  end
  if withPosts then
    local posts = 28
    for i = 0, posts - 1 do
      local x, y = trackPoint(R, i / posts)
      local nx, ny = x - OVAL_CX, y - OVAL_CY               -- outward normal
      local len = math.sqrt(nx * nx + ny * ny); if len < 1 then len = 1 end
      nx, ny = nx / len, ny / len
      local hl = 6                                          -- half post length
      local red = (i % 2 == 0)
      local cr = red and 0.85 or 0.95
      local cg = red and 0.15 or 0.95
      local cb = red and 0.15 or 0.95
      railSeg(x - nx * hl, y - ny * hl, x + nx * hl, y + ny * hl, 3, cr, cg, cb, 1, "OVERLAY")
    end
  end
end

drawRail(TRACK_R, 4, true)     -- outer running rail with red/white posts
drawRail(innerR, 3, true)      -- inner rail with matching posts

-- finish line: a solid gold line at top centre, inner rail up to outer rail
railSeg(OVAL_CX, OVAL_CY - innerR, OVAL_CX, OVAL_CY - TRACK_R, 4, 1, 0.9, 0.25, 1, "OVERLAY")
local finLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
finLabel:SetText("FINISH")
anchorCenter(finLabel, OVAL_CX, OVAL_CY - TRACK_R - 12)

-- ------- mounts -------
-- Faction-appropriate mount MODELS. The display IDs below are best-effort; if a
-- lane shows the wrong model (or none), correct it in-game with
--   /cup setmodel <lane 1-5> <displayID>      (saved per character)
-- and list the current ones with  /cup models .
local MODEL_SIZE   = 90      -- the model scales with its frame (was 75)
-- How far above its lane's centre line a racer's frame sits, so the body (not
-- the frame) is over the lane. Fixed, not a share of MODEL_SIZE, so a bigger
-- model does not ride higher.
local MODEL_LIFT   = 6
-- The field starts this far behind the finish line, measured ALONG each lane
-- (it used to be a flat +16px on screen, which on the bends and straights
-- pushed lane 1 over the outer rail and lane 5 into the infield).
local START_BEHIND = 16
local MOUNT_FACING = 5.2     -- radians; rough side-on view. Tweak to taste.
local MOUNT_CAM    = 2.8     -- larger = zoomed out
local ROCKET_CAM   = 5.0     -- the rocket car is a much fatter model than a
                             -- horse: zoom its camera out further so it fits
                             -- the frame instead of clipping at the edges
local IDLE_ANIM = 0          -- stand
local RUN_ANIM  = 5         -- run/gallop loop (tweak if it looks wrong)
local MOUNT_DEFAULTS = {
  Alliance = { 2410, 2404, 2402, 2405, 2404 },
  Horde    = { 2410, 2404, 2402, 2405, 2404 },
}
-- Speedway theme: every lane drives the goblin rocket car. 10318 is the
-- only display for creature/goblinrocketcar in the era build's
-- CreatureDisplayInfo - the lanes stay told apart by their colored
-- number tags. /cup setmodel overrides save under the "Speedway" key
-- while the theme is on, so custom cars don't clobber the horse picks.
local ROCKET_DISPLAY = 10318
local function currentTheme()
  return (SigmaDerbyDB and SigmaDerbyDB.theme) or "turf"
end
local function modelKey()
  if currentTheme() == "speedway" then return "Speedway" end
  return UnitFactionGroup("player") or "Alliance"
end
local function mountDisplayID(lane)
  local key = modelKey()
  local ov = SigmaDerbyDB and SigmaDerbyDB.models
             and SigmaDerbyDB.models[key] and SigmaDerbyDB.models[key][lane]
  if ov then return ov end
  if key == "Speedway" then return ROCKET_DISPLAY end
  local set = MOUNT_DEFAULTS[key] or MOUNT_DEFAULTS.Alliance
  return set[lane]
end

local horses = {}
for h = 1, Engine.HORSES do
  local m = CreateFrame("PlayerModel", nil, f)
  m:SetSize(MODEL_SIZE, MODEL_SIZE)
  local lbl = m:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  lbl:SetPoint("BOTTOM", m, "BOTTOM", 0, math.floor(MODEL_SIZE * 0.4))
  lbl:SetText(h)
  local cr = HORSE_COLORS[h]; lbl:SetTextColor(cr[1], cr[2], cr[3])
  horses[h] = { frame = m, model = m, label = lbl }
end

local function applyMount(h)
  local m = horses[h].model
  local id = mountDisplayID(h)
  if id and id > 0 then m:SetDisplayInfo(id) end
  m:SetFacing(MOUNT_FACING)
  if m.SetCamDistanceScale then
    m:SetCamDistanceScale(currentTheme() == "speedway" and ROCKET_CAM or MOUNT_CAM)
  end
  m:SetAnimation(IDLE_ANIM)
end
local function applyAllMounts() for h = 1, Engine.HORSES do applyMount(h) end end
local function setHorsesAnimation(anim)
  for h = 1, Engine.HORSES do horses[h].model:SetAnimation(anim) end
end

-- Change this value if your models run sideways (e.g., math.pi / 2 or 0)
local MODEL_DIRECTION_OFFSET = 90

local function placeHorse(h, p, bob)
  -- Behind the line by the same distance in every lane: a share of that
  -- lane's own length, so the racer stays on its lane all the way round.
  local R = laneR[h]
  local perimeter = 4 * TRACK_L + 2 * math.pi * R
  local x, y, facingAngle = trackPoint(R, p - START_BEHIND / perimeter)

  local m = horses[h].model
  anchorCenter(horses[h].frame, x, y - MODEL_LIFT + (bob or 0))
  
  -- Apply dynamic track rotation + model adjustments on the fly
  m:SetFacing(-facingAngle + MODEL_DIRECTION_OFFSET)
end
local function resetHorses()
  for h = 1, Engine.HORSES do
    placeHorse(h, 0, 0)
  end
  setHorsesAnimation(IDLE_ANIM)
end

-- Repaint the whole cosmetic theme: track surface color + racer models.
-- (forward-declared up top; the checkbox and /cup theme call this)
applyTheme = function()
  local c = (currentTheme() == "speedway") and ASPHALT or DIRT
  for _, strip in ipairs(trackStrips) do
    strip:SetColorTexture(c[1], c[2], c[3], 1)
  end
  applyAllMounts()
end

-- =====================================================================
--  Betting board: 10 combos in two centred columns
-- =====================================================================
local BOARD_TOP = OVAL_CY + TRACK_R + 24
local cells = {}
local DEFAULT_BG = {1, 1, 1, 0.05}

-- Label for a bet line: combo lines below WIN_BASE, win lines above it
local function cellLabel(idx)
  if idx > Engine.WIN_BASE then
    local h = idx - Engine.WIN_BASE
    local col = HORSE_COLORS[h]
    local odds = race and race.winOdds and race.winOdds[h] or 0
    if race and odds <= 1 then
      -- Even-money favourites take no bets - show the line as closed.
      return string.format("|cff%02x%02x%02x#%d|r WIN   |cff777777closed|r",
        col[1] * 255, col[2] * 255, col[3] * 255, h)
    end
    return string.format("|cff%02x%02x%02x#%d|r WIN   %d:1",
      col[1] * 255, col[2] * 255, col[3] * 255, h, odds)
  end
  local c = Engine.COMBOS[idx]
  local odds = race and race.odds[idx] or 0
  return string.format("%d-%d   %d:1", c[1], c[2], odds)
end

refreshCell = function(idx)
  local cell = cells[idx]
  if not cell then return end
  cell.oddsFS:SetText(cellLabel(idx))

  -- Everyone sees every bet on a line. Your own stake stays green; the pooled
  -- stake from the other players shows as its own number in a distinct colour
  -- so you can always pick your own bet out at a glance. (The host never bets,
  -- so for the host the whole line is "others".)
  local mine = isHost and 0 or (localStakes[idx] or 0)
  local others = 0
  for _, book in pairs(remoteBook) do
    others = others + (book[idx] or 0)
  end

  local parts = {}
  if mine > 0 then parts[#parts + 1] = "|cff66ff66" .. mine .. "g|r" end
  if others > 0 then parts[#parts + 1] = "|cff40b0ff" .. others .. "g|r" end
  cell.stakeFS:SetText(table.concat(parts, " "))
end

clearHighlight = function()
  for i = 1, #cells do
    cells[i].bg:SetColorTexture(DEFAULT_BG[1], DEFAULT_BG[2], DEFAULT_BG[3], DEFAULT_BG[4])
    cells[i].oddsFS:SetTextColor(1, 1, 1)
  end
end
highlightWinner = function(idx)
  cells[idx].bg:SetColorTexture(1, 0.84, 0, 0.32)   -- gold, stays until next race
  cells[idx].oddsFS:SetTextColor(1, 0.9, 0.2)
end

local function placeBet(idx, dir)
  if isHost then
    resultFS:SetText("|cffff6060The Bank (Host) cannot place bets.|r")
    return
  end
  -- No markers until someone has actually opened a race (solo odds previews
  -- and the pre-race lull don't take bets).
  if not hostName then
    resultFS:SetText("|cffff6060No race is open - wait for someone to press New Race.|r")
    return
  end
  if raceRunning or not race then return end
  if phase ~= "betting" and not (phase == "countdown" and countdownBetsOpen) then return end
  -- Even-money lines are closed: a 1:1 win only hands your stake back, so
  -- heavy favourites can't be used as a free push.
  if dir > 0 then
    local o
    if idx > Engine.WIN_BASE then
      o = race.winOdds and race.winOdds[idx - Engine.WIN_BASE]
    else
      o = race.odds and race.odds[idx]
    end
    if (o or 0) <= 1 then
      resultFS:SetText("|cffff6060That line is 1:1 - even-money bets are closed.|r")
      return
    end
  end
  local st  = currentStake()
  local cur = localStakes[idx] or 0
  if dir > 0 then
    if betsUsed() >= hostMaxBets then
      resultFS:SetText(string.format(
        "|cffff6060All %d of your bets are placed.|r Right-click a line to take one back.",
        hostMaxBets))
      return
    end
    localStakes[idx] = cur + st               -- stack another stake on this line
  else
    local v = cur - st
    localStakes[idx] = (v > 0) and v or nil    -- take one stake back
  end
  refreshCell(idx)
  queueBet(idx, localStakes[idx] or 0)   -- throttled/coalesced send
  SigmaDerby_UpdateTotals()
  updateLocks()
end


for idx = 1, #Engine.COMBOS do
  local col = (idx <= 5) and 0 or 1
  local row = (idx <= 5) and (idx - 1) or (idx - 6)
  local bx = 200 + col * 320
  local by = BOARD_TOP + row * 28

  local btn = CreateFrame("Button", nil, f)
  btn:SetSize(280, 26)
  btn:SetPoint("TOPLEFT", f, "TOPLEFT", bx, -by)

  local bg = btn:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(); bg:SetColorTexture(unpack(DEFAULT_BG))
  btn:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")

  local oddsFS = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  oddsFS:SetPoint("LEFT", 8, 0)
  local stakeFS = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  stakeFS:SetPoint("RIGHT", -8, 0)

  cells[idx] = { btn = btn, bg = bg, oddsFS = oddsFS, stakeFS = stakeFS }

  btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  btn:SetScript("OnClick", function(_, mouse)
    if mouse == "RightButton" then placeBet(idx, -1) else placeBet(idx, 1) end
  end)

  -- MOVED: This must be INSIDE the loop so 'btn' and 'idx' are valid!
  btn:SetScript("OnEnter", function(self)
    local hasBets = false
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Bets for " .. Engine.COMBOS[idx][1] .. "-" .. Engine.COMBOS[idx][2], 1, 0.82, 0)

    local mine = (not isHost) and (localStakes[idx] or 0) or 0
    if mine > 0 then
      GameTooltip:AddDoubleLine("You", mine .. "g", 0.4, 1, 0.4, 0.4, 1, 0.4)
      hasBets = true
    end
    for player, book in pairs(remoteBook) do
      if book[idx] and book[idx] > 0 then
        GameTooltip:AddDoubleLine(shortName(player), book[idx] .. "g", 1, 1, 1, 0.25, 0.7, 1)
        hasBets = true
      end
    end
    if hasBets then GameTooltip:Show() else GameTooltip:Hide() end
  end)
  btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
  
end -- <--- The loop officially ends HERE now.

-- =====================================================================
--  Win bets: back a single horse to finish FIRST, own odds (left column).
--  Not part of the quinella - these lines live at index WIN_BASE + horse
--  in the same books/messages, so every downstream system just works.
-- =====================================================================
local winHeader = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
winHeader:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -(BOARD_TOP - 16))
winHeader:SetText("|cffffd100WIN|r |cff888888- first past the post|r")

for h = 1, Engine.HORSES do
  local idx = Engine.WIN_BASE + h
  local by = BOARD_TOP + (h - 1) * 28

  local btn = CreateFrame("Button", nil, f)
  btn:SetSize(176, 26)
  btn:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -by)

  local bg = btn:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(); bg:SetColorTexture(unpack(DEFAULT_BG))
  btn:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")

  local oddsFS = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  oddsFS:SetPoint("LEFT", 8, 0)
  local stakeFS = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  stakeFS:SetPoint("RIGHT", -8, 0)

  cells[idx] = { btn = btn, bg = bg, oddsFS = oddsFS, stakeFS = stakeFS }

  btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  btn:SetScript("OnClick", function(_, mouse)
    if mouse == "RightButton" then placeBet(idx, -1) else placeBet(idx, 1) end
  end)

  btn:SetScript("OnEnter", function(self)
    local hasBets = false
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Win bets on Horse " .. h, 1, 0.82, 0)
    local mine = (not isHost) and (localStakes[idx] or 0) or 0
    if mine > 0 then
      GameTooltip:AddDoubleLine("You", mine .. "g", 0.4, 1, 0.4, 0.4, 1, 0.4)
      hasBets = true
    end
    for player, book in pairs(remoteBook) do
      if book[idx] and book[idx] > 0 then
        GameTooltip:AddDoubleLine(shortName(player), book[idx] .. "g", 1, 1, 1, 0.25, 0.7, 1)
        hasBets = true
      end
    end
    if hasBets then GameTooltip:Show() else GameTooltip:Hide() end
  end)
  btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- =====================================================================
--  Controls + readout
-- =====================================================================
local CTRL_Y = BOARD_TOP + 5 * 28 + 16
local CTRL_X = 200

local stakeLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
stakeLabel:SetPoint("TOPLEFT", f, "TOPLEFT", CTRL_X, -CTRL_Y)
stakeLabel:SetText("Stake:")

stakeDown = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
stakeDown:SetSize(22, 22); stakeDown:SetText("-")
stakeDown:SetPoint("LEFT", stakeLabel, "RIGHT", 8, 0)

local stakeVal = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
stakeVal:SetWidth(52); stakeVal:SetJustifyH("CENTER")
stakeVal:SetPoint("LEFT", stakeDown, "RIGHT", 4, 0)

stakeUp = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
stakeUp:SetSize(22, 22); stakeUp:SetText("+")
stakeUp:SetPoint("LEFT", stakeVal, "RIGHT", 4, 0)

local betsLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
betsLabel:SetPoint("LEFT", stakeUp, "RIGHT", 18, 0)
betsLabel:SetText("Bets:")

betsDown = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
betsDown:SetSize(22, 22); betsDown:SetText("-")
betsDown:SetPoint("LEFT", betsLabel, "RIGHT", 8, 0)

local betsValFS = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
betsValFS:SetWidth(28); betsValFS:SetJustifyH("CENTER")
betsValFS:SetPoint("LEFT", betsDown, "RIGHT", 4, 0)

betsUp = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
betsUp:SetSize(22, 22); betsUp:SetText("+")
betsUp:SetPoint("LEFT", betsValFS, "RIGHT", 4, 0)

newBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
newBtn:SetSize(110, 22); newBtn:SetText("New Race")
newBtn:SetPoint("LEFT", betsUp, "RIGHT", 18, 0)

runBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
runBtn:SetSize(110, 22); runBtn:SetText("Run Race")
runBtn:SetPoint("LEFT", newBtn, "RIGHT", 8, 0)

-- relinquish the bank so anyone in the group may host the next race
relinquishBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
relinquishBtn:SetSize(120, 22); relinquishBtn:SetText("Open Hosting")
relinquishBtn:SetPoint("LEFT", runBtn, "RIGHT", 8, 0)
relinquishBtn:SetScript("OnClick", function()
  isHost = false
  hostName = nil
  netSend("OPEN")                    -- tell everyone the bank is open
  resultFS:SetText("Hosting is open. Anyone can press New Race.")
  updateSeedText()
  updateLocks()
end)

-- Fake play (fun games record no debts): the casino-wide toggle, surfaced
-- next to the hosting controls like every other game. The Debts window
-- code owns it; guard because the derby stays loadable stand-alone.
do
  local Debts = ChairfacesCasino and ChairfacesCasino.UI and ChairfacesCasino.UI.Debts
  if Debts and Debts.AttachFakePlayCheck then
    Debts:AttachFakePlayCheck(f, "LEFT", relinquishBtn, "RIGHT", 12, 0)
  end
end

refreshStake    = function() stakeVal:SetText(STAKE_STEPS[stakeIdx] .. "g") end
refreshMaxBets  = function() betsValFS:SetText(tostring(hostMaxBets)) end

local function broadcastSettings()
  if isHost then netSend("SET," .. currentStake() .. "," .. hostMaxBets) end
end

stakeDown:SetScript("OnClick", function()
  if stakeIdx > 1 then stakeIdx = stakeIdx - 1; refreshStake()
    broadcastSettings(); SigmaDerby_UpdateTotals(); updateLocks() end
end)
stakeUp:SetScript("OnClick", function()
  if stakeIdx < #STAKE_STEPS then stakeIdx = stakeIdx + 1; refreshStake()
    broadcastSettings(); SigmaDerby_UpdateTotals(); updateLocks() end
end)
betsDown:SetScript("OnClick", function()
  if hostMaxBets > 1 then hostMaxBets = hostMaxBets - 1; refreshMaxBets()
    broadcastSettings(); SigmaDerby_UpdateTotals(); updateLocks() end
end)
betsUp:SetScript("OnClick", function()
  if hostMaxBets < #Engine.COMBOS then hostMaxBets = hostMaxBets + 1; refreshMaxBets()
    broadcastSettings(); SigmaDerby_UpdateTotals(); updateLocks() end
end)
refreshStake(); refreshMaxBets()

-- apply host-broadcast settings on a client
syncSettingsUI = function(stakeAmount, maxBets)
  if stakeAmount then
    for i, v in ipairs(STAKE_STEPS) do if v == stakeAmount then stakeIdx = i; break end end
  end
  if maxBets then hostMaxBets = maxBets end
  refreshStake(); refreshMaxBets(); SigmaDerby_UpdateTotals(); updateLocks()
end

local totalFS = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
totalFS:SetPoint("TOPLEFT", f, "TOPLEFT", CTRL_X, -(CTRL_Y + 30))

resultFS = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
resultFS:SetPoint("TOPLEFT", f, "TOPLEFT", CTRL_X, -(CTRL_Y + 54))
resultFS:SetWidth(FRAME_W - CTRL_X - 30); resultFS:SetJustifyH("LEFT")

-- Loud FREE PLAY banner: the derby has no single "join" button, so a fun
-- race (host opened with fake play on - no debts recorded) is called out
-- with an unmissable red bar across the top of the window. Toggled by
-- updateFakeBanner() from updateLocks; pulses so it reads as a live warning.
local raceFakeBanner = CreateFrame("Frame", nil, f, "BackdropTemplate")
raceFakeBanner:SetPoint("TOP", f, "TOP", 0, -6)
raceFakeBanner:SetSize(FRAME_W - 24, 26)
raceFakeBanner:SetFrameStrata("HIGH")
do
  local bg = raceFakeBanner:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetTexture("Interface\\Buttons\\WHITE8x8")
  bg:SetVertexColor(0.7, 0.05, 0.05, 0.92)
  raceFakeBanner.bg = bg
  raceFakeBanner:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
  raceFakeBanner:SetBackdropBorderColor(1, 0.85, 0.2, 1)
  local label = raceFakeBanner:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  label:SetPoint("CENTER")
  label:SetText("|cffffffff\226\154\160 FREE PLAY \226\128\148 NO DEBTS THIS RACE \226\154\160|r")
  raceFakeBanner.label = label
  raceFakeBanner:SetScript("OnUpdate", function(self, e)
    self.acc = (self.acc or 0) + e
    if self.acc < 0.04 then return end
    self.acc = 0
    self.pulse = (self.pulse or 0) + (self.dir or 0.03)
    if self.pulse >= 1 then self.pulse = 1; self.dir = -0.03
    elseif self.pulse <= 0 then self.pulse = 0; self.dir = 0.03 end
    self.label:SetAlpha(0.55 + 0.45 * self.pulse)
  end)
  raceFakeBanner:Hide()
end

-- Show the banner when the active race opened on fake play. Host uses its own
-- captured term; a bettor uses what the host announced over the wire.
updateFakeBanner = function()
  local fun
  if isHost then fun = (raceFakePlay == true) else fun = (remoteFakePlay == true) end
  -- only while a race is actually open/settling, not on an empty idle table
  if fun and phase ~= "idle" then raceFakeBanner:Show() else raceFakeBanner:Hide() end
end

function SigmaDerby_UpdateTotals()
  if isHost then
    local totalPool, totalBets = 0, 0
    for _, book in pairs(remoteBook) do
      for _, s in pairs(book) do
        if s and s > 0 then
          totalPool = totalPool + s
          totalBets = totalBets + (s / currentStake())
        end
      end
    end
    totalFS:SetText(string.format(
      "Global Pool: |cffffd100%d bets|r    Total Staked: |cffffd100%dg|r",
      totalBets, totalPool))
  else
    totalFS:SetText(string.format(
      "Your bets: |cffffd100%d/%d|r    staked: |cffffd100%dg|r",
      betsUsed(), hostMaxBets, totalStaked()))
  end
end

-- lock logic:
--  * stake/bets settings: only the current bank, and locked once bets exist
--    (until the race finishes).
--  * New Race: while a betting round is live only the bank may (re)roll, and
--    only before any bets; once a race is DONE (or none is active) it opens to
--    EVERYONE so any player can host the next one.
--  * Open Hosting: enabled ONLY if grouped, you are the active host, AND the race is inactive ("idle" or "done").
updateLocks = function()
  local grouped = netChannel() ~= nil
  local amHost  = (not grouped) or isHost or (hostName == nil)
  local lockSettings = hasAnyBets() and phase ~= "done"
  local settingsEnabled = amHost and phase ~= "running" and phase ~= "countdown" and not lockSettings
  
  for _, b in ipairs({ stakeDown, stakeUp, betsDown, betsUp }) do
    if b then b:SetEnabled(settingsEnabled) end
  end
  
  if newBtn then
    local newEnabled
    if phase == "running" or phase == "countdown" then newEnabled = false
    elseif phase == "betting" then newEnabled = amHost and not hasAnyBets()
    else newEnabled = true end                 -- idle / done: open to all hosts
    newBtn:SetEnabled(newEnabled)
  end
  
  if runBtn then
    runBtn:SetEnabled(amHost and phase == "betting" and race ~= nil and not raceRunning)
  end
  
  -- FIX: Force the button to check if you are the host AND if the race is not actively betting/running
  if relinquishBtn then
    local canOpen = (phase == "idle" or phase == "done")
                    or (phase == "betting" and not hasAnyBets())
    relinquishBtn:SetEnabled(grouped and isHost and canOpen)
  end

  if updateFakeBanner then updateFakeBanner() end
end
-- =====================================================================
--  History (SavedVariables) + popups
-- =====================================================================
local function pushHistory(e)
  SigmaDerbyDB = SigmaDerbyDB or {}
  SigmaDerbyDB.history = SigmaDerbyDB.history or {}
  table.insert(SigmaDerbyDB.history, 1, e)
  while #SigmaDerbyDB.history > 10 do table.remove(SigmaDerbyDB.history) end
end
local function buildHistoryText()
  local h = (SigmaDerbyDB and SigmaDerbyDB.history) or {}
  if #h == 0 then return "No races recorded yet." end
  local lines = { "Last " .. #h .. " races (most recent first):", "" }
  for _, e in ipairs(h) do
    local tag = e.hosted and "   |cffff8800(you hosted)|r" or ""
    local first = e.w and string.format("  (Horse %d 1st)", e.w) or ""
    lines[#lines + 1] = string.format("|cffffd100seed %d|r   winner %d-%d%s%s", e.seed, e.a, e.b, first, tag)
    local led = e.ledger
    if led and #led > 0 then
      if e.hosted then
        -- host perspective: exactly what each player pays you (or you pay them)
        local house = 0
        for _, pl in ipairs(led) do
          if pl.net < 0 then
            lines[#lines + 1] = string.format("      %s pays you |cff66ff66%dg|r", pl.name, -pl.net)
            house = house + (-pl.net)
          elseif pl.net > 0 then
            lines[#lines + 1] = string.format("      you pay %s |cffff6060%dg|r", pl.name, pl.net)
            house = house - pl.net
          else
            lines[#lines + 1] = string.format("      %s: even", pl.name)
          end
        end
        local hc = (house >= 0) and ("|cff66ff66+" .. house .. "g|r") or ("|cffff6060" .. house .. "g|r")
        lines[#lines + 1] = "      your take: " .. hc
      else
        -- bettor perspective
        for _, pl in ipairs(led) do
          local s
          if pl.net > 0 then s = "|cff66ff66collect " .. pl.net .. "g|r"
          elseif pl.net < 0 then s = "|cffff6060pays " .. (-pl.net) .. "g|r"
          else s = "even" end
          lines[#lines + 1] = string.format("      %s: %s", pl.name, s)
        end
      end
    else
      lines[#lines + 1] = "      (no bets)"
    end
    lines[#lines + 1] = ""
  end
  return table.concat(lines, "\n")
end

local RULES_TEXT =
"Chair's Cup - How to Play\n\n" ..
"Five horses race once around the oval. You bet on which TWO horses\n" ..
"finish 1st and 2nd, in either order (a quinella). Ten pairings are\n" ..
"shown, each with its payout odds (capped at 33 to 1).\n\n" ..
"The bank (whoever starts the race):\n" ..
"- Sets the single stake amount everyone bets with.\n" ..
"- Sets how many bets each player may place.\n" ..
"- Starts the race. Stake and bet count lock once betting begins.\n\n" ..
"Betting:\n" ..
"- Left-click a pairing to place one bet of the bank's stake on it.\n" ..
"- Right-click a pairing to take one bet back.\n" ..
"- You may stack several bets on the same pairing or spread them\n" ..
"  around, up to your bet allotment.\n\n" ..
"Payout:\n" ..
"- If a pairing you backed finishes 1-2 in any order it pays stake\n" ..
"  times odds. After the race you see one net for the round: a\n" ..
"  positive net you collect, a negative net you pay.\n" ..
"- The winning pairing is highlighted in gold until the next race.\n\n" ..
"Multiplayer:\n" ..
"- Form a party or raid. Everyone receives the same seed and sees\n" ..
"  identical odds and the same result. Gold is settled by hand.\n\n" ..
"Same seed, same race, on every screen."

local function makePopup(titleText, w, h)
  local p = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  p:SetSize(w, h); p:SetPoint("CENTER")
  p:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = false, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  p:SetBackdropColor(0.04, 0.04, 0.05, 0.97)
  p:SetBackdropBorderColor(0.55, 0.45, 0.18, 1)
  p:SetMovable(true); p:EnableMouse(true); p:RegisterForDrag("LeftButton")
  p:SetScript("OnDragStart", p.StartMoving); p:SetScript("OnDragStop", p.StopMovingOrSizing)
  p:SetFrameStrata("DIALOG"); p:Hide()
  local t = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  t:SetPoint("TOP", 0, -12); t:SetText(titleText)
  local c = CreateFrame("Button", nil, p, "UIPanelCloseButton")
  c:SetPoint("TOPRIGHT", -4, -4)
  local body = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  body:SetPoint("TOPLEFT", 16, -40); body:SetPoint("BOTTOMRIGHT", -16, 16)
  body:SetJustifyH("LEFT"); body:SetJustifyV("TOP")
  p.body = body
  return p
end

local function makeScrollPopup(name, titleText, w, h)
  local p = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
  p:SetSize(w, h); p:SetPoint("CENTER")
  p:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = false, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  p:SetBackdropColor(0.04, 0.04, 0.05, 0.97)
  p:SetBackdropBorderColor(0.55, 0.45, 0.18, 1)
  p:SetMovable(true); p:EnableMouse(true); p:RegisterForDrag("LeftButton")
  p:SetScript("OnDragStart", p.StartMoving); p:SetScript("OnDragStop", p.StopMovingOrSizing)
  p:SetFrameStrata("DIALOG"); p:Hide()
  local t = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  t:SetPoint("TOP", 0, -12); t:SetText(titleText)
  local c = CreateFrame("Button", nil, p, "UIPanelCloseButton")
  c:SetPoint("TOPRIGHT", -4, -4)
  local scroll = CreateFrame("ScrollFrame", name .. "Scroll", p, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 14, -40)
  scroll:SetPoint("BOTTOMRIGHT", -34, 14)
  local child = CreateFrame("Frame", nil, scroll)
  child:SetSize(w - 56, 10)
  scroll:SetScrollChild(child)
  local body = child:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  body:SetPoint("TOPLEFT", 0, 0)
  body:SetWidth(w - 56); body:SetJustifyH("LEFT"); body:SetJustifyV("TOP")
  p.body, p.child = body, child
  p.SetContent = function(self, txt)
    self.body:SetText(txt)
    self.child:SetHeight(math.max(10, self.body:GetStringHeight() + 12))
  end
  return p
end

local rulesPopup = makePopup("How to Play", 470, 470)
rulesPopup.body:SetText(RULES_TEXT)
helpBtn:SetScript("OnClick", function()
  if rulesPopup:IsShown() then rulesPopup:Hide() else rulesPopup:Show() end
end)

local histPopup = makeScrollPopup("ChairsCupHistory", "Race History", 560, 420)
histBtn:SetScript("OnClick", function()
  histPopup:SetContent(buildHistoryText())
  if histPopup:IsShown() then histPopup:Hide() else histPopup:Show() end
end)
local hostLedgerPopup = makeScrollPopup("ChairsCupLedger", "Race Results Ledger", 400, 350)
-- =====================================================================
--  Settlement
-- =====================================================================
local function netForBook(book)
  local bets, staked = {}, 0
  for idx, s in pairs(book) do
    if s and s > 0 then bets[#bets + 1] = { player = "p", comboIdx = idx, stake = s }; staked = staked + s end
  end
  local p = Engine.settle(race, bets)
  return (p["p"] or 0) - staked
end
-- the full ledger for this race. When the host has broadcast the authoritative
-- book (settleBook), everyone builds the identical record from it; otherwise
-- (solo, or before broadcast) fall back to self + whatever bets we've seen.
local function buildLedger()
  local L = {}
  if settleBook then
    for name, book in pairs(settleBook) do
      L[#L + 1] = { name = name, net = netForBook(book) }
    end
    return L
  end
  if next(localStakes) then
    L[#L + 1] = { name = shortName(ChairfacesCasino:MyName()), net = netForBook(localStakes) }
  end
  for player, book in pairs(remoteBook) do
    local had = false
    for _, s in pairs(book) do if s and s > 0 then had = true; break end end
    if had then L[#L + 1] = { name = shortName(player), net = netForBook(book) } end
  end
  return L
end
local function fmtNet(n)
  if n > 0 then return "collect " .. n .. "g"
  elseif n < 0 then return "pays " .. (-n) .. "g"
  else return "even" end
end
local function printLedger()
  local wc = Engine.COMBOS[race.winningCombo]
  print(string.format("|cffffd100Chair's Cup|r seed %d, winner %d-%d:", race.seed, wc[1], wc[2]))
  if next(localStakes) then
    print(string.format("  %s: %s", ChairfacesCasino:MyName(), fmtNet(netForBook(localStakes))))
  end
  for player, book in pairs(remoteBook) do
    print(string.format("  %s: %s", shortName(player), fmtNet(netForBook(book))))
  end
end

showPayouts = function()
  local wc = Engine.COMBOS[race.winningCombo]
  highlightWinner(race.winningCombo)
  highlightWinner(Engine.WIN_BASE + race.finishOrder[1])  -- winning WIN line too
  local staked = totalStaked()
  local myName = shortName(ChairfacesCasino:MyName())
  -- settle your own result from the host's authoritative book when we have it,
  -- so your net always matches what the host's ledger charges you.
  local net = settleBook and netForBook(settleBook[myName] or {}) or netForBook(localStakes)
  local amHost = (netChannel() == nil) or isHost

  local head = string.format("Winner |cffffd100%d-%d|r - Horse %d first.", wc[1], wc[2], race.finishOrder[1])
  local line
  if staked == 0 then
    line = head
  elseif amHost then
    if net > 0 then line = head .. string.format(" |cff66ff66You net +%dg|r.", net)
    elseif net < 0 then line = head .. string.format(" |cffff6060You net -%dg|r.", -net)
    else line = head .. " You broke even." end
  else
    local who = shortName(hostName)
    if net > 0 then line = head .. string.format(" |cff66ff66Collect %dg|r from %s.", net, who)
    elseif net < 0 then line = head .. string.format(" |cffff6060Pay %s %dg|r.", who, -net)
    else line = head .. " You broke even." end
  end
  resultFS:SetText(line)

pushHistory({ seed = race.seed, a = wc[1], b = wc[2], w = race.finishOrder[1],
                net = net, staked = staked,
                bets = betsUsed(), ledger = buildLedger(), hosted = amHost })
                
  if isHost then 
    printLedger() 
    
    -- Populate and show the on-screen ledger popup for the host
    local lines = {
      string.format("Winning Combo: |cffffd100%d-%d|r", wc[1], wc[2]),
      "--------------------------------",
      "Player Payouts & Collections:"
    }
    local houseNet = 0
    local ledgerData = buildLedger()
    
    for _, pl in ipairs(ledgerData) do
      if pl.net > 0 then
        table.insert(lines, string.format("|cff66ff66Pay|r %s: %dg", pl.name, pl.net))
        houseNet = houseNet - pl.net
      elseif pl.net < 0 then
        table.insert(lines, string.format("|cffff6060Collect|r from %s: %dg", pl.name, -pl.net))
        houseNet = houseNet + (-pl.net)
      else
        table.insert(lines, string.format("%s: Broke even", pl.name))
      end
    end
    table.insert(lines, "--------------------------------")
    
    if houseNet > 0 then
      table.insert(lines, string.format("House (You) Net: |cff66ff66+%dg|r", houseNet))
    elseif houseNet < 0 then
      table.insert(lines, string.format("House (You) Net: |cffff6060%dg|r", houseNet))
    else
      table.insert(lines, "House (You) Net: Even")
    end

    hostLedgerPopup:SetContent(table.concat(lines, "\n\n"))
    hostLedgerPopup:Show()

    -- Feed the casino's session debt ledger: each player's net is a debt
    -- to or from the host (the house), settled by hand like everything else
    local DebtLedger = ChairfacesCasino and ChairfacesCasino.DebtLedger
    if DebtLedger then
      local meShort = shortName(ChairfacesCasino:MyName())
      local debts = {}
      for _, pl in ipairs(ledgerData) do
        if pl.name ~= meShort and pl.net ~= 0 then
          if pl.net > 0 then
            debts[#debts + 1] = { debtor = meShort, creditor = pl.name, amount = pl.net }
          else
            debts[#debts + 1] = { debtor = pl.name, creditor = meShort, amount = -pl.net }
          end
        end
      end
      -- Terms frozen when this race was hosted, not the live toggle
      if #debts > 0 then DebtLedger:RecordDebts("derby", debts, raceFakePlay) end
    end

    -- Leaderboard: the host is the sole recorder. Record each bettor's net
    -- and the house's own net under "chairscup". Hands stage until the debt
    -- settles (RecordDebts above tells the leaderboard this race's pairs -
    -- and marks fun races so their staged hands are discarded).
    local LBoard = ChairfacesCasino and ChairfacesCasino.Leaderboard
    if LBoard and #ledgerData > 0 then
      local meShort = shortName(ChairfacesCasino:MyName())
      for _, pl in ipairs(ledgerData) do
        local outcome = pl.net > 0 and "win" or (pl.net < 0 and "lose" or "participated")
        LBoard:RecordHandResult("chairscup", pl.name, pl.net, outcome)
      end
      local houseOutcome = houseNet > 0 and "win" or (houseNet < 0 and "lose" or "participated")
      LBoard:RecordHandResult("chairscup", meShort, houseNet, houseOutcome)
    end
  end

  updateLocks()
end

-- =====================================================================
--  Race lifecycle
-- =====================================================================

-- Bank-offline grace timer: armed by onRosterUpdate (defined further down)
-- when the bank reads as disconnected. Declared here because every
-- race-state reset (applyRace, and resumeFinishedRace through it) must
-- cancel it, or a stale timer from the previous blip shortens the next
-- race's grace window.
local BANK_OFFLINE_GRACE = 120
local bankOfflineTimer
local function cancelBankOfflineTimer()
  if bankOfflineTimer then bankOfflineTimer:Cancel(); bankOfflineTimer = nil end
end

applyRace = function(seed)
  seed = seed or (math.floor(GetTime() * 1000) % 2147483647) + math.random(1, 9999)
  race        = Engine.buildRace(seed)
  timeline    = Engine.buildTimeline(race, 120)
  localStakes = {}
  remoteBook  = {}
  settleBook  = nil
  pendingBets = {}
  raceRunning = false
  phase       = "betting"
  cancelBankOfflineTimer()
  clearHighlight()
  for idx = 1, #cells do refreshCell(idx) end
  resetHorses()
  resultFS:SetText("Odds are up. Left-click a line to bet, right-click to take one back.")
  SigmaDerby_UpdateTotals()
  updateSeedText()
  updateLocks()
end

hostStartRace = function()
  -- One game at a time across the whole casino: no new race while another
  -- casino game is running in this group.
  local CC = _G.ChairfacesCasino
  local casinoLobby = CC and CC.UI and CC.UI.Lobby
  if casinoLobby and casinoLobby.IsOtherGameActive then
    local busy, other = casinoLobby:IsOtherGameActive("derby")
    if busy then
      print("|cffff6060Chair's Cup:|r can't open a race - a " ..
        casinoLobby:GetGameName(other) .. " game is already in progress.")
      return
    end
  end

  local seed = (math.floor(GetTime() * 1000) % 2147483647) + math.random(1, 9999)
  isHost = true
  hostName = ChairfacesCasino:MyName()
  do -- freeze the fun/real terms for this race at host time (explicit
     -- if\else on purpose: `x and true or nil` folds REAL into nil)
    local DL = CC and CC.DebtLedger
    if DL and DL.IsFakePlay then
      raceFakePlay = DL:IsFakePlay() and true or false
    else
      raceFakePlay = nil
    end
  end
  remoteFakePlay = nil   -- we're the host now; our own term governs
  applyRace(seed)
  -- Fake flag rides as a 5th field AFTER PROTO, so pre-2.5.4 hosts/clients
  -- (which parse only up to PROTO) ignore it and don't trip the version warn.
  netSend("NEW," .. seed .. "," .. currentStake() .. "," .. hostMaxBets .. "," ..
    PROTO .. "," .. (raceFakePlay and "1" or "0"))
end

local elapsed = 0
local finishedHorses = {}  -- horses that have crossed the line this race

-- Park a horse at the post: stop bobbing and return to the idle animation.
-- Only touches that horse - the rest of the field keeps galloping.
local function finishHorse(h)
  if not finishedHorses[h] then
    finishedHorses[h] = true
    horses[h].model:SetAnimation(IDLE_ANIM)
  end
  placeHorse(h, 1, 0)
end

onUpdate = function(_, dt)
  elapsed = elapsed + dt
  local ticks = #timeline[1]
  local prog = elapsed / RACE_SECONDS
  local tf = prog * (ticks - 1) + 1
  if tf >= ticks then
    for h = 1, Engine.HORSES do finishHorse(h) end
    driver:SetScript("OnUpdate", nil)
    raceRunning = false
    if stopRocketSound then stopRocketSound() end
    phase = "done"
    showPayouts()
    return
  end
  local t0 = math.floor(tf)
  local frac = tf - t0
  for h = 1, Engine.HORSES do
    local p0 = timeline[h][t0]
    local p1 = timeline[h][t0 + 1] or p0
    local p  = p0 + (p1 - p0) * frac
    if p >= 1 then
      -- This horse has touched the finish line (the timeline holds it at 1
      -- from its own finish tick onward) - idle at the post.
      finishHorse(h)
    else
      local bob = (math.floor(tf * 1) % 2 == 0) and 0 or 5
      placeHorse(h, p, bob)
    end
  end
end

-- Host snapshots everything it received and broadcasts the authoritative final
-- book, so every client (and the host) settles identical numbers even if some
-- BET messages were lost. One small message per bettor keeps each under the cap.
local function snapshotBook()
  local snap = {}
  for player, book in pairs(remoteBook) do
    local b = {}
    for idx, st in pairs(book) do if st and st > 0 then b[idx] = st end end
    if next(b) then snap[shortName(player)] = b end
  end
  return snap
end

-- The best full book this client can produce for a reconnecting bank. Prefer the
-- host's authoritative book if we received it; otherwise rebuild the whole table
-- from what we saw during betting - everyone else's bets (remoteBook) plus our
-- own (localStakes). This covers the case where the bank dropped during the
-- Run-Race countdown, before it ever broadcast the authoritative book, so no one
-- holds a settleBook but every client still knows the bets.
local function currentKnownBook()
  if settleBook and next(settleBook) then return settleBook end
  local book = {}
  local myShort = shortName(ChairfacesCasino:MyName())
  local mine = {}
  for idx, st in pairs(localStakes) do if st and st > 0 then mine[idx] = st end end
  if next(mine) then book[myShort] = mine end
  for player, pb in pairs(remoteBook) do
    local b = {}
    for idx, st in pairs(pb) do if st and st > 0 then b[idx] = st end end
    if next(b) then book[shortName(player)] = b end
  end
  return book
end
-- Wire out a book (BOOK header, then one PB line per player). Used by the host
-- to publish its authoritative book, and by a client relaying that same book to
-- a bank that reconnected after the race already started.
local function sendBook(book)
  netSend("BOOK")                     -- clients: clear and rebuild from PB msgs
  for player, b in pairs(book or {}) do
    local parts = {}
    for idx, st in pairs(b) do parts[#parts + 1] = idx .. ":" .. st end
    netSend("PB," .. player .. "," .. table.concat(parts, ","))
  end
end
local function broadcastFinalBook()
  settleBook = snapshotBook()
  sendBook(settleBook)
end

-- Among the players still present and online (excluding the requester), the one
-- with the lexicographically smallest short name answers a reconnecting bank's
-- REQ, so a single client replies instead of the whole group flooding books.
local function amReqResponder(requester)
  local me = shortName(ChairfacesCasino:MyName())
  local reqShort = shortName(requester)
  local best = me
  local n = GetNumGroupMembers()
  for i = 1, n do
    local unit = IsInRaid() and ("raid" .. i) or ("party" .. i)
    if UnitIsConnected(unit) then
      local uname = shortName(ChairfacesCasino:UnitFullName(unit))
      if uname and uname ~= reqShort and uname < best then best = uname end
    end
  end
  return best == me
end

-- Speedway race audio: rocket engines instead of hoofbeats. The game's
-- own rocket loops are short one-shots, so a ticker re-fires one for the
-- whole race; first fileID that actually plays wins (later-era sounds
-- can be absent from some clients - same fallback pattern as Crash).
local ROCKET_SOUND_FDIDS = {
  595154,   -- sound/creature/rocketmount/rocketmountfly.ogg (X-53 engine)
  550824,   -- sound/creature/goblinshredder/goblinshredderloop.ogg
  567190,   -- sound/doodad/doodadcompression/zeppelinengineloop.ogg
}
local rocketTicker
local function playRocketLoop()
  if not (f:IsShown() and raceRunning) then return end
  for _, id in ipairs(ROCKET_SOUND_FDIDS) do
    local ok, willPlay = pcall(PlaySoundFile, id, "Master")
    if ok and willPlay then return end
  end
end
stopRocketSound = function()
  if rocketTicker then rocketTicker:Cancel(); rocketTicker = nil end
end
local function startRocketSound()
  stopRocketSound()
  playRocketLoop()
  rocketTicker = C_Timer.NewTicker(2.4, playRocketLoop)
end

runRace = function()
  if not race or raceRunning then return end
  raceRunning = true
  phase = "running"
  if isHost then broadcastFinalBook() end   -- lock in the authoritative book
  elapsed = 0
  finishedHorses = {}
  resultFS:SetText("And they're off!")
  -- Race audio only for players actually watching the track
  if f:IsShown() then
    PlaySoundFile("Interface\\AddOns\\Chairfaces Casino\\Sounds\\Derby\\GunFire03.ogg", "Master")
    PlaySoundFile("Interface\\AddOns\\Chairfaces Casino\\Sounds\\Derby\\atoff.ogg", "Master")
    if currentTheme() == "speedway" then
      startRocketSound()
    else
      PlaySoundFile("Interface\\AddOns\\Chairfaces Casino\\Sounds\\Derby\\horses.ogg", "Master")
    end
  end
  setHorsesAnimation(RUN_ANIM)        -- mounts gallop while racing
  updateLocks()
  driver:SetScript("OnUpdate", onUpdate)   -- runs even if the window is closed
end

-- Host presses Run Race -> a synced 10s last-call for bets, then a 3s "on your
-- marks" countdown, then the race. Everyone runs identical timers off one GO.
local function startCountdown()
  if not race or raceRunning or phase == "countdown" or phase == "running" then return end
  phase = "countdown"
  countdownBetsOpen = true
  updateLocks()
  local function betTick(n)
    if phase ~= "countdown" then return end
    if n > 0 then
      resultFS:SetText(string.format(
        "|cffffd100Last call!|r Betting closes in %ds  (race in %ds)", n, n + 3))
      C_Timer.After(1, function() betTick(n - 1) end)
    else
      countdownBetsOpen = false
      updateLocks()
      local function goTick(m)
        if phase ~= "countdown" then return end
        if m > 0 then
          resultFS:SetText(string.format("|cffff6060Betting closed.|r Race in %d...", m))
          C_Timer.After(1, function() goTick(m - 1) end)
        else
          runRace()
        end
      end
      goTick(3)
    end
  end
  betTick(10)
end

newBtn:SetScript("OnClick", function() hostStartRace() end)
runBtn:SetScript("OnClick", function()
  if netChannel() and not isHost then return end
  if netChannel() and isHost then netSend("GO") end
  startCountdown()
end)

updateSeedText = function()
  local who
  if not netChannel() then who = "solo"
  else who = "race by " .. shortName(isHost and ChairfacesCasino:MyName() or hostName) end
  seedText:SetText(string.format("Seed: |cffffd100%s|r    %s",
    race and tostring(race.seed) or "-", who))
end

-- =====================================================================
--  Reconnect sync
--  A client that reloads mid-race sends REQ; the host answers with its
--  authoritative book (BOOK/PB) followed by a targeted STATE message.
--  Races are deterministic from the seed, so the client rebuilds the
--  identical race and either jumps the clock to the host's elapsed time
--  or - if it's already over - shows the finish, results and history.
-- =====================================================================
local resumeRunningRace, resumeFinishedRace

-- Rebuild the live board (every player's stakes and the totals) from the
-- authoritative book, so a reconnecting player - the bank especially - sees
-- exactly the bets that were on the table, not an empty board. Our own lines
-- go back into localStakes, everyone else's into the remote book.
local function restoreBoardFromBook(book)
  localStakes = {}
  remoteBook  = {}
  if book then
    local myShort = shortName(ChairfacesCasino:MyName())
    for player, b in pairs(book) do
      for i, st in pairs(b) do
        if st and st > 0 then
          if player == myShort then
            localStakes[i] = st
          else
            remoteBook[player] = remoteBook[player] or {}
            remoteBook[player][i] = st
          end
        end
      end
    end
  end
  for i = 1, #cells do refreshCell(i) end
  if SigmaDerby_UpdateTotals then SigmaDerby_UpdateTotals() end
  updateLocks()
end

resumeRunningRace = function(seed, hostElapsed)
  local keepBook = settleBook          -- applyRace clears it; the host's
  applyRace(seed)                      -- PB messages arrived just before
  settleBook = keepBook
  restoreBoardFromBook(keepBook)        -- put every player's bets back on the board
  phase = "running"
  raceRunning = true
  elapsed = math.min(hostElapsed or 0, RACE_SECONDS)
  finishedHorses = {}
  resultFS:SetText("Rejoined mid-race - and they're off!")
  setHorsesAnimation(RUN_ANIM)
  updateLocks()
  driver:SetScript("OnUpdate", onUpdate)
end

resumeFinishedRace = function(seed)
  -- If this race is already the newest history entry we saw the finish
  -- ourselves before reloading - don't record it twice.
  local hist = SigmaDerbyDB and SigmaDerbyDB.history
  if hist and hist[1] and hist[1].seed == seed then return end

  local keepBook = settleBook
  applyRace(seed)
  settleBook = keepBook
  restoreBoardFromBook(keepBook)        -- put every player's bets back on the board
  raceRunning = false
  if stopRocketSound then stopRocketSound() end
  phase = "done"
  finishedHorses = {}
  for h = 1, Engine.HORSES do finishHorse(h) end
  showPayouts()                        -- results + history from the host's book
end

-- =====================================================================
--  Networking + boot
-- =====================================================================
local function onAddonMsg(prefix, text, channel, sender)
  if prefix ~= PREFIX or isSelf(sender) then return end
  local cmd, a, b, c, d, e = strsplit(",", text)

  if cmd == "NEW" then
    local v = tonumber(d)
    if v and v ~= PROTO and not versionWarned then
      versionWarned = true
      print("|cffff6060Chair's Cup:|r addon version mismatch with " .. shortName(sender)
        .. " -- update so seeds, bets and payouts stay in sync.")
    end
    -- fun/real term for this race (5th field; nil from pre-2.5.4 hosts)
    remoteFakePlay = (e == "1") and true or (e == "0" and false or nil)
    isHost = false; hostName = sender
    syncSettingsUI(tonumber(b), tonumber(c))
    applyRace(tonumber(a))
    
    -- REMOVED: The line that forced the window open ( if not f:IsShown() then f:Show() end )

    -- Notify the player with a clickable game link, the same way every other
    -- casino game announces an open table.
    local CC = _G.ChairfacesCasino
    local link = (CC and CC.CreateGameLink) and CC:CreateGameLink("chairscup", "Chair's Cup")
        or "Chair's Cup"
    print("|cffffd100Chair's Cup:|r The horses are at the gate! " .. shortName(sender)
        .. " has started a new race. Click " .. link .. " to play.")
    if CC and CC.GameComm and CC.GameComm.PlayTableOpenChime and not f:IsShown() then
      CC.GameComm:PlayTableOpenChime("chairscup")
    end
    
    resultFS:SetText(shortName(sender) .. " started a race. Place your bets.")
    if SigmaDerbyDB and SigmaDerbyDB.autoOpen and not f:IsShown() then
      f:Show()
    end
  elseif cmd == "GO" then
    startCountdown()
  elseif cmd == "SET" then
    syncSettingsUI(tonumber(a), tonumber(b))
  elseif cmd == "OPEN" then
    isHost = false; hostName = nil       -- bank relinquished; anyone may host
    updateSeedText(); updateLocks()
  elseif cmd == "BOOK" then
    -- Host is (re)publishing the authoritative book. Ignore a redundant relayed
    -- book once we already hold one for a race in progress, so a second reconnect
    -- reply can't briefly wipe the bets we just restored.
    if not (race and settleBook and next(settleBook)
        and (phase == "running" or phase == "done")) then
      settleBook = {}
    end
  elseif cmd == "PB" then
    local rest = text:match("^PB,(.+)$")
    if rest then
      local fields = { strsplit(",", rest) }
      local name = fields[1]
      local book = {}
      for i = 2, #fields do
        local k, val = fields[i]:match("^(%d+):(%d+)$")
        if k then book[tonumber(k)] = tonumber(val) end
      end
      settleBook = settleBook or {}
      settleBook[name] = book
    end
  elseif cmd == "BET" then
    local idx, st = tonumber(a), tonumber(b)
    if idx then
      remoteBook[sender] = remoteBook[sender] or {}
      remoteBook[sender][idx] = (st and st > 0) and st or nil
      updateLocks()
      -- Every client now shows all players' bets, so refresh the line for
      -- everyone (not just the host).
      refreshCell(idx)
      if isHost then
        SigmaDerby_UpdateTotals()
      end
	end
  elseif cmd == "REQ" then
    -- Someone reloaded mid-race and wants the current state. Book first
    -- (addon messages are ordered), then the targeted STATE.
    if isHost and race then
      local ph = phase
      if ph == "countdown" then ph = "betting" end
      local el = (ph == "running") and math.floor(elapsed + 0.5) or 0
      -- Always ship the current book, even mid-betting, so a (re)joining
      -- player recovers their own placed bets and sees everyone else's.
      broadcastFinalBook()
      -- retHost placeholder "0" keeps the fake flag at a fixed field index
      netSend(table.concat({ "STATE", shortName(sender), race.seed,
        currentStake(), hostMaxBets, ph, el, PROTO, "0",
        (raceFakePlay and "1" or "0") }, ","))
    elseif race and (phase == "running" or phase == "done")
        and amReqResponder(sender) then
      -- The bank dropped after the race started and has now reconnected asking
      -- for state, but nobody is hosting anymore - the race was deterministic,
      -- so we (an elected client) carried it on and still hold the authoritative
      -- book the host published at the off. Relay that book (even if empty) and
      -- a STATE so the returning bank re-seeds its race and records the result.
      local el = (phase == "running") and math.floor(elapsed + 0.5) or 0
      -- If the requester is the bank we've been playing under, tell them so they
      -- reclaim hosting (nobody else is hosting) and come back fully restored.
      local retHost = (hostName and shortName(sender) == shortName(hostName)) and "1" or "0"
      -- Relay the full book. Falls back to our own view of the bets when nobody
      -- ever received an authoritative book (bank dropped during the countdown).
      sendBook(currentKnownBook())
      -- relay the fun/real term we learned as a bettor so the returning bank
      -- reclaims the correct settlement terms
      netSend(table.concat({ "STATE", shortName(sender), race.seed,
        currentStake(), hostMaxBets, phase, el, PROTO, retHost,
        (remoteFakePlay and "1" or (remoteFakePlay == false and "0" or "")) }, ","))
    end
  elseif cmd == "STATE" then
    local fields = { strsplit(",", text) }
    local target  = fields[2]
    local seedN   = tonumber(fields[3])
    local stakeV  = tonumber(fields[4])
    local maxB    = tonumber(fields[5])
    local ph      = fields[6]
    local el      = tonumber(fields[7]) or 0
    local v       = tonumber(fields[8])
    local retBank = fields[9] == "1"
    local fakeF   = fields[10]   -- fun/real term (may be "", nil from old peers)
    if target == shortName(ChairfacesCasino:MyName()) and seedN
        and not (race and race.seed == seedN) then
      if v and v ~= PROTO and not versionWarned then
        versionWarned = true
        print("|cffff6060Chair's Cup:|r addon version mismatch with " .. shortName(sender)
          .. " -- update so seeds, bets and payouts stay in sync.")
      end
      local fakeTerm = (fakeF == "1") and true or (fakeF == "0" and false or nil)
      if retBank then
        -- We are the original bank returning from a disconnect. Nobody else is
        -- hosting, so reclaim the bank: the relayed book restores the full
        -- ledger and board, so we settle and show results exactly as before.
        isHost = true
        hostName = shortName(ChairfacesCasino:MyName())
        -- restore the settlement terms our disconnect wiped, so the recorded
        -- debts match the race the table actually played
        if fakeTerm ~= nil then raceFakePlay = fakeTerm end
        remoteFakePlay = nil
        print("|cffffd100Chair's Cup:|r Welcome back - reclaiming your race and restoring every bet on the board...")
      else
        isHost = false; hostName = sender
        remoteFakePlay = fakeTerm
        -- Tell the player we found the active race and are syncing to it (the
        -- reconnect otherwise applies silently and looks like nothing happened).
        local phaseWord = (ph == "running") and "a race underway"
          or (ph == "done") and "a finished race" or "an open race"
        print("|cffffd100Chair's Cup:|r Found " .. shortName(sender) .. "'s game (" ..
          phaseWord .. ") - syncing your bets and board...")
      end
      syncSettingsUI(stakeV, maxB)
      if ph == "running" then
        resumeRunningRace(seedN, el)
      elseif ph == "done" then
        resumeFinishedRace(seedN)
      else
        -- Betting still open. The host's BOOK/PB messages arrived just before
        -- this STATE (addon messages are ordered), so restore the live book:
        -- our own lines go back into localStakes, everyone else's into the
        -- remote book, instead of applyRace wiping them all away.
        local keepBook = settleBook
        applyRace(seedN)
        if keepBook then
          local myShort = shortName(ChairfacesCasino:MyName())
          for player, book in pairs(keepBook) do
            if player == myShort then
              for i, st in pairs(book) do localStakes[i] = st end
            else
              remoteBook[player] = remoteBook[player] or {}
              for i, st in pairs(book) do remoteBook[player][i] = st end
            end
          end
          settleBook = nil   -- betting isn't settled yet; don't leave a book
          for i = 1, #cells do refreshCell(i) end
          SigmaDerby_UpdateTotals()
          updateLocks()
        end
        resultFS:SetText(shortName(sender) .. " has a race open. Place your bets.")
      end
      updateSeedText()
    end
  end
end

local function printModels()
  print("|cffffd100Chair's Cup|r mount display IDs (" .. modelKey() .. "):")
  for h = 1, Engine.HORSES do
    print(string.format("  lane %d: %d", h, mountDisplayID(h) or 0))
  end
  print("change one with: /cup setmodel <lane> <displayID>  -  swap themes with /cup theme")
end

SLASH_CHAIRSCUP1 = "/cup"
SLASH_CHAIRSCUP2 = "/chairscup"
SLASH_CHAIRSCUP3 = "/derby"
SlashCmdList["CHAIRSCUP"] = function(msg)
  msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if msg == "models" then
    printModels(); return
  end
  if msg == "theme" or msg == "rockets" or msg == "cars" then
    SigmaDerbyDB = SigmaDerbyDB or {}
    SigmaDerbyDB.theme = (currentTheme() == "speedway") and "turf" or "speedway"
    if applyTheme then applyTheme() end
    rocketCB:SetChecked(currentTheme() == "speedway")
    print("|cffffd100Chair's Cup|r theme: " ..
      (currentTheme() == "speedway" and "goblin speedway (rocket cars on asphalt)" or "classic turf"))
    return
  end
  local lane, id = msg:match("^setmodel%s+(%d+)%s+(%d+)$")
  lane, id = tonumber(lane), tonumber(id)
  if msg:match("^setmodel") then
    if lane and id and lane >= 1 and lane <= Engine.HORSES then
      SigmaDerbyDB = SigmaDerbyDB or {}
      SigmaDerbyDB.models = SigmaDerbyDB.models or {}
      local fac = modelKey()
      SigmaDerbyDB.models[fac] = SigmaDerbyDB.models[fac] or {}
      SigmaDerbyDB.models[fac][lane] = id
      applyAllMounts()
      print(string.format("|cffffd100Chair's Cup|r lane %d model set to %d.", lane, id))
    else
      print("Usage: /cup setmodel <lane 1-" .. Engine.HORSES .. "> <displayID>")
    end
    return
  end
  if f:IsShown() then f:Hide()
  else f:Show(); if not race then applyRace() end end
end

-- The floating horse icon has been removed. Chair's Cup is now opened from the
-- Chairface's Casino lobby "Derby" button, or via the /cup, /derby, /chairscup
-- slash commands.

-- Casino lobby bridge: expose the derby's phase in the shape the lobby's
-- game registry expects ("idle"/"settlement" = free, anything else = active),
-- so Chair's Cup participates in the one-game-at-a-time gating. A race only
-- counts as active once someone actually hosts one - opening the window
-- solo just previews odds and must not lock the casino.
do
  local CC = _G.ChairfacesCasino
  -- Trixie deals at the races too (helper lives in the casino lobby)
  if CC and CC.UI and CC.UI.Lobby and CC.UI.Lobby.AttachTrixie then
    CC.UI.Lobby:AttachTrixie(f, "derby")
  end
  -- Surface the casino-wide "newer version in your group" warning here too,
  -- so every game window (Chair's Cup included) flags a version mismatch.
  if CC and CC.ShowPendingVersionWarning then
    f:HookScript("OnShow", function() CC:ShowPendingVersionWarning() end)
  end
  if CC then
    CC.DerbyState = setmetatable({}, {
      __index = function(_, key)
        if key ~= "phase" then return nil end
        local hosted = isHost or hostName ~= nil
        local grouped = netChannel() ~= nil
          or (CC.TestMode and CC.TestMode.enabled)
        if hosted and grouped
            and (phase == "betting" or phase == "countdown" or phase == "running") then
          return "active"
        end
        return phase == "done" and "settlement" or "idle"
      end,
    })
  end
end

-- Host-drop protection: if the bank leaves the group mid-race the deal can no
-- longer be settled, so (like Roulette / Bingo / Death Roll) each client voids
-- the race locally - no stakes are owed - and hosting reopens for the next one.
-- A bank that merely DISCONNECTS (still in the group) gets a 2-minute grace to
-- reconnect before the same void; UNIT_CONNECTION drives that check.
-- (BANK_OFFLINE_GRACE / bankOfflineTimer are declared above applyRace, which
-- also cancels the timer on every race-state reset.)

local function voidBankLoss(chatMsg, panelMsg)
  print("|cffff6060Chair's Cup:|r " .. chatMsg)
  race = nil
  timeline = nil
  raceRunning = false
  if stopRocketSound then stopRocketSound() end
  phase = "idle"
  localStakes = {}
  remoteBook = {}
  settleBook = nil
  pendingBets = {}
  hostName = nil
  cancelBankOfflineTimer()
  if driver then driver:SetScript("OnUpdate", nil) end
  resetHorses()
  if resultFS then resultFS:SetText(panelMsg) end
  updateSeedText()
  updateLocks()
end

local function onRosterUpdate()
  if isHost or not hostName then return end
  if not netChannel() then return end
  if not (phase == "betting" or phase == "countdown" or phase == "running") then
    cancelBankOfflineTimer()
    return
  end
  if isSelf(hostName) then return end

  local shortHost = shortName(hostName)
  local present, online = false, false
  local n = GetNumGroupMembers()
  for i = 1, n do
    local unit = IsInRaid() and ("raid" .. i) or ("party" .. i)
    local uname = ChairfacesCasino:UnitFullName(unit)
    if uname and shortName(uname) == shortHost then
      present = true
      online = UnitIsConnected(unit)
      break
    end
  end

  if not present then
    voidBankLoss("The bank (" .. shortHost .. ") left the group - this race is void. No stakes are owed.",
      "The bank left - race voided. No stakes are owed.")
    return
  end

  if not online then
    if not bankOfflineTimer then
      print("|cffff6060Chair's Cup:|r The bank (" .. shortHost ..
        ") disconnected - waiting " .. BANK_OFFLINE_GRACE .. "s for them to return.")
      bankOfflineTimer = C_Timer.NewTimer(BANK_OFFLINE_GRACE, function()
        bankOfflineTimer = nil
        if not (phase == "betting" or phase == "countdown" or phase == "running") then return end
        -- Recheck directly - don't trust that a reconnect event fired
        local stillOnline = false
        local cnt = GetNumGroupMembers()
        for j = 1, cnt do
          local u = IsInRaid() and ("raid" .. j) or ("party" .. j)
          local un = ChairfacesCasino:UnitFullName(u)
          if un and shortName(un) == shortHost then
            stillOnline = UnitIsConnected(u)
            break
          end
        end
        if stillOnline then return end
        voidBankLoss("The bank (" .. shortHost .. ") did not return - this race is void. No stakes are owed.",
          "The bank disconnected - race voided. No stakes are owed.")
      end)
    end
  elseif bankOfflineTimer then
    cancelBankOfflineTimer()
    print("|cff60ff60Chair's Cup:|r The bank is back - the race stands.")
  end
end

-- Reconnect resync: a bank (or any player) that reloads or reconnects mid-race
-- comes back with fresh, empty state. A single one-shot REQ is unreliable right
-- after a reconnect - the group roster and addon comms often aren't ready for a
-- few seconds, so netChannel() is still nil and the REQ never goes out. Poll the
-- group until someone answers with a STATE (which sets `race`) or we give up.
local syncPollActive = false
local function requestRaceSync(attempt)
  attempt = attempt or 1
  if race then syncPollActive = false; return end   -- synced, stop
  if attempt > 10 then syncPollActive = false; return end
  syncPollActive = true
  if netChannel() and not isHost then netSend("REQ") end
  -- Poll faster early (roster settling), then ease off.
  C_Timer.After(attempt <= 4 and 2 or 4, function()
    requestRaceSync(attempt + 1)
  end)
end
-- Kick a poll if we're a fresh client in a group with no race yet.
local function maybeStartSyncPoll()
  if race or isHost or syncPollActive then return end
  if not netChannel() then return end
  requestRaceSync(1)
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("CHAT_MSG_ADDON")
boot:RegisterEvent("GROUP_JOINED")
boot:RegisterEvent("GROUP_ROSTER_UPDATE")
boot:RegisterEvent("UNIT_CONNECTION")  -- bank disconnect/reconnect watch
boot:SetScript("OnEvent", function(_, event, ...)
  if event == "CHAT_MSG_ADDON" then
    onAddonMsg(...)
  elseif event == "GROUP_ROSTER_UPDATE" or event == "UNIT_CONNECTION" then
    onRosterUpdate()
  elseif event == "GROUP_JOINED" then
    -- Joined a group mid-session: ask whoever is hosting for the current race
    -- and its book so we start with every bet already on the board.
    C_Timer.After(2, maybeStartSyncPoll)
  elseif event == "PLAYER_LOGIN" then
    SigmaDerbyDB = SigmaDerbyDB or {}
    SigmaDerbyDB.history = SigmaDerbyDB.history or {}
    SigmaDerbyDB.models = SigmaDerbyDB.models or {}
    local wp = SigmaDerbyDB.win
    if wp and wp.point then
      f:ClearAllPoints()
      f:SetPoint(wp.point, UIParent, wp.relPoint or wp.point, wp.x or 0, wp.y or 0)
    end
	SigmaDerbyDB.autoOpen = SigmaDerbyDB.autoOpen or false
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
      C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    end
    applyTheme()           -- saved theme + faction/overrides are known now
    updateLocks()
	autoOpenCB:SetChecked(SigmaDerbyDB.autoOpen)
    rocketCB:SetChecked(currentTheme() == "speedway")
    print("|cffffd100Chair's Cup|r loaded. Type |cff00ff00/cup|r to open.")
    -- Reconnect sync: if we reloaded/reconnected during someone's race, poll the
    -- group for the current state until it answers (roster may not be ready yet).
    C_Timer.After(3, function() requestRaceSync(1) end)
  end
end)
