--[[
    Chairface's Casino - UI/Trixie.lua
    Trixie the dealer: one sprite player shared by every casino window.

    Every window keeps its own Button + texture and hands them to
    Trixie:Attach(frame, texture). That gives the frame:
      frame:Idle(fresh)       endless idle rotation (fresh = roll a new pose now)
      frame:React(mood, opts) a pose or clip for the mood, then back to idle
                              (opts.hold = seconds before a still goes back)
      frame:Play(name, opts)  one named entry; frame:Queue(a, b, ...) chains them
      frame:SetRandomWait/Deal/Shuffle/Cheer/Lose/Love/WinOrLove (old names)

    Moods: wait, win, lose, love, deal, shuf. Each mood's pool mixes the
    hand-drawn stills (Textures/dealer/trix_<mood><n>) with the animated
    AutoSprite clips in BJ.TrixieClips. Every clip starts and ends on the same
    "home" pose, so any clip can follow any other without a jump.
]]

local BJ = ChairfacesCasino

local T = {}
BJ.Trixie = T

local DIR = "Interface\\AddOns\\Chairfaces Casino\\Textures\\dealer\\"

T.MOODS = { "wait", "win", "lose", "love", "deal", "shuf" }
T.STILLS = { wait = 31, win = 9, lose = 12, love = 10, deal = 8, shuf = 12 }
T.ALIAS = { cheer = "win", shuffle = "shuf", idle = "wait" }
T.CLIP_SHARE = 0.75          -- chance a mood with clips picks a clip over a still
T.IDLE_STILL_HOLD = { 6, 12 } -- seconds an idle still stays while idle clips exist
T.IDLE_LOOPS = { 1, 3 }       -- times a looping idle clip repeats before the next pick

-- name -> entry, mood -> { stills = {}, clips = {} }, and every entry in order
T.byName, T.pools, T.order = {}, {}, {}

local function addEntry(e)
    T.byName[e.name] = e
    T.order[#T.order + 1] = e
    local pool = T.pools[e.mood]
    if not pool then
        pool = { stills = {}, clips = {} }
        T.pools[e.mood] = pool
    end
    table.insert(e.still and pool.stills or pool.clips, e)
end

function T:BuildPools()
    self.byName, self.pools, self.order = {}, {}, {}
    for _, mood in ipairs(self.MOODS) do
        for i = 1, self.STILLS[mood] do
            local name = "trix_" .. mood .. i
            addEntry({ name = name, mood = mood, file = DIR .. name, frames = 1, still = true })
        end
    end
    for _, c in ipairs(BJ.TrixieClips or {}) do
        local mood = self.ALIAS[c.mood] or c.mood
        addEntry({
            name = c.name, mood = mood, file = DIR .. "anim\\" .. c.file,
            frames = c.frames, cols = c.cols, fw = c.fw, fh = c.fh,
            texW = c.texW, texH = c.texH, fps = c.fps or 12, loop = c.loop,
        })
    end
end
T:BuildPools()

function T:HasClips(mood)
    local pool = self.pools[mood]
    return pool and #pool.clips > 0 or false
end

-- A random entry for the mood, never the one this widget showed last for it.
function T:Pick(mood, last)
    local pool = self.pools[mood]
    if not pool then return nil end
    local list = pool.stills
    if #pool.clips > 0 and (#pool.stills == 0 or math.random() < self.CLIP_SHARE) then
        list = pool.clips
    end
    if #list == 0 then return nil end
    local e = list[math.random(1, #list)]
    if #list > 1 and last and e.name == last then
        local i = math.random(1, #list - 1)
        if list[i].name == last then i = #list end
        e = list[i]
    end
    return e
end

-- The texcoords of one clip frame.
function T:FrameCoords(e, idx)
    local col = idx % e.cols
    local row = math.floor(idx / e.cols)
    return col * e.fw / e.texW, (col + 1) * e.fw / e.texW,
           row * e.fh / e.texH, (row + 1) * e.fh / e.texH
end

------------------------------------------------------------------------
-- Driver: one OnUpdate steps every visible widget that is mid-clip or
-- waiting out a hold. Hidden widgets don't advance; when one shows again
-- the clock catches it up (a finished clip just moves on).
------------------------------------------------------------------------
T.widgets = {}

local driver
local function tick()
    local now = GetTime()
    for _, w in ipairs(T.widgets) do
        local s = w.trix
        if s.cur and w:IsVisible() then
            local e = s.cur
            if not e.still then
                local idx = math.floor((now - s.start) * e.fps)
                if s.untilT and now >= s.untilT then idx = e.frames - 1 end
                idx = idx % e.frames
                if idx ~= s.frame then
                    s.frame = idx
                    s.tex:SetTexCoord(T:FrameCoords(e, idx))
                end
            end
            if s.untilT and now >= s.untilT then
                s.untilT = nil
                w:TrixieNext()
            end
        end
    end
end

local function wake()
    if driver then return end
    driver = CreateFrame("Frame")
    driver:SetScript("OnUpdate", tick)
end
T.Tick = tick

------------------------------------------------------------------------
-- Widget methods (mixed into each attached frame)
------------------------------------------------------------------------
local W = {}

-- Draw an entry. opts.hold = seconds a still stays (nil = until told);
-- opts.loops = times a clip plays (math.huge = forever).
function W:TrixieShow(e, opts)
    opts = opts or {}
    local s = self.trix
    local now = GetTime()
    s.cur, s.start, s.frame = e, now, 0
    s.last[e.mood] = e.name
    s.tex:SetTexture(e.file)
    if e.still then
        s.tex:SetTexCoord(0, 1, 0, 1)
        s.untilT = opts.hold and (now + opts.hold) or nil
    else
        s.tex:SetTexCoord(T:FrameCoords(e, 0))
        local loops = opts.loops or 1
        s.untilT = loops ~= math.huge and (now + e.frames * loops / e.fps) or nil
    end
    if BJ.TestMode and BJ.TestMode.enabled and BJ.TestMode.trixieDebugActive and self.debugLabel then
        self.debugLabel:SetText(e.name)
        self.debugLabel:Show()
    end
end

-- The current entry is done: next queued entry, else back to idle.
function W:TrixieNext()
    local s = self.trix
    local nextE = table.remove(s.queue, 1)
    if nextE then
        s.mode = "chain"
        self:TrixieShow(nextE)
    elseif s.cur and s.cur.still and s.mode ~= "idle" and not s.held then
        -- a still reaction with no hold stays until the game says otherwise
    else
        self:Idle(true)
    end
end

function W:Idle(fresh)
    local s = self.trix
    -- already idling on a clip: let it play out rather than jump
    if not fresh and s.mode == "idle" and s.cur and not s.cur.still then return end
    wipe(s.queue)
    s.mode, s.held = "idle", nil
    local e = T:Pick("wait", s.last.wait)
    if not e then return end
    if e.still then
        local hold
        if T:HasClips("wait") then hold = math.random(T.IDLE_STILL_HOLD[1], T.IDLE_STILL_HOLD[2]) end
        self:TrixieShow(e, { hold = hold })
    else
        self:TrixieShow(e, { loops = e.loop and math.random(T.IDLE_LOOPS[1], T.IDLE_LOOPS[2]) or 1 })
    end
end

function W:React(mood, opts)
    mood = T.ALIAS[mood] or mood
    if mood == "wait" then return self:Idle() end
    local s = self.trix
    -- the same mood's clip is already playing (deals fire per card): keep it going
    if s.cur and s.cur.mood == mood and not s.cur.still and s.untilT then return end
    local e = T:Pick(mood, s.last[mood])
    if not e then return end
    wipe(s.queue)
    s.mode = "react"
    s.held = opts and opts.hold and true or nil
    self:TrixieShow(e, { hold = opts and opts.hold })
end

-- Play entries by name, one after another, then idle.
function W:Queue(...)
    local s = self.trix
    wipe(s.queue)
    for i = 1, select("#", ...) do
        local e = T.byName[select(i, ...)]
        if e then s.queue[#s.queue + 1] = e end
    end
    s.held = true
    self:TrixieNext()
end

function W:Play(name, opts)
    local e = T.byName[name]
    if not e then return end
    wipe(self.trix.queue)
    self.trix.mode, self.trix.held = "chain", true
    self:TrixieShow(e, opts)
end

-- Old state names ("wait5", "deal3", "trix_love2") still work.
function W:SetState(state)
    local e = T.byName[state] or T.byName["trix_" .. state]
    if not e then return end
    self.trix.mode, self.trix.held = (e.mood == "wait") and "idle" or "react", nil
    wipe(self.trix.queue)
    self:TrixieShow(e)
end

function W:SetRandomWait() self:Idle() end
function W:SetRandomDeal() self:React("deal") end
function W:SetRandomShuffle() self:React("shuf") end
function W:SetRandomCheer() self:React("win") end
function W:SetRandomLose() self:React("lose") end
function W:SetRandomLove() self:React("love") end
-- big wins: one time in ten she blows a kiss instead of cheering
function W:SetRandomWinOrLove()
    if math.random(1, 10) == 1 then self:React("love") else self:React("win") end
end

-- Hand Trixie a frame and its texture. She starts idling straight away.
function T:Attach(frame, texture)
    frame.texture = frame.texture or texture
    frame.trix = { tex = texture, queue = {}, last = {}, frame = 0 }
    for k, fn in pairs(W) do frame[k] = fn end
    table.insert(self.widgets, frame)
    wake()
    frame:Idle(true)
    return frame
end

-- Debug browser (test mode): every entry in order, still or clip.
function T:Entries() return self.order end

function T:ShowEverywhere(name)
    local e = self.byName[name]
    if not e then return end
    for _, w in ipairs(self.widgets) do
        if w:IsVisible() then
            wipe(w.trix.queue)
            w.trix.mode, w.trix.held = "debug", true
            w:TrixieShow(e, { loops = math.huge })
        end
    end
end
