--[[
    Chairface's Casino - Games/Pachinko/PachinkoEngine.lua
    Gnomish Pachinko: a Peggle-style peg shooter on the solo arcade's fake
    credit balance. Pure logic - field geometry, ball physics, peg layouts,
    the bucket, Fever, scoring and the pay table. No frame API, so
    tests/pachinko_test.py drives it headless; UI/PachinkoFrame.lua draws
    whatever this produces and owns the credits (Spend before NewRound,
    Award on the round_over event).

    Coordinates are field pixels with the origin top-left and y growing
    DOWNWARD (the UI anchors every texture TOPLEFT at (x, -y)).

    Round flow: NewRound -> AIM (Aim/Guide while the player points, Launch
    on click) -> FLIGHT (Step integrates every ball) -> back to AIM when the
    last ball is gone, or FEVER the moment the last orange peg lights ->
    OVER with state.result once every ball has landed in a bin.
]]

local BJ = ChairfacesCasino
BJ.Arcade = BJ.Arcade or {}
local Arcade = BJ.Arcade
Arcade.Pachinko = Arcade.Pachinko or {}
local PK = Arcade.Pachinko

-- Field geometry (pixels)
PK.FIELD_W, PK.FIELD_H = 540, 600
PK.BALL_R      = 7
PK.PEG_R       = 9
PK.LAUNCHER_Y  = 26          -- muzzle height; balls spawn just below it
PK.PEG_TOP     = 120         -- peg zone
PK.PEG_BOTTOM  = 500
PK.PEG_MARGIN  = 34          -- pegs keep this far from the side walls
PK.PEG_GAP     = 40          -- minimum centre distance (ball must fit through)

-- Physics
PK.GRAVITY      = 1000       -- px/s^2
PK.LAUNCH_SPEED = 480        -- px/s
PK.RESTITUTION  = 0.70
PK.STEP         = 1 / 120    -- fixed substep
PK.MAX_AIM_DEG  = 82         -- either side of straight down
PK.STUCK_SPEED  = 35         -- slower than this for STUCK_SECS = stuck
PK.STUCK_SECS   = 1.5

-- Bucket (free ball) and Fever bins
PK.BUCKET_W     = 84
PK.BUCKET_H     = 16
PK.BUCKET_SPEED = 130        -- px/s, straight back and forth
PK.FEVER_SLOWMO = 0.35       -- time scale once Fever starts
PK.FEVER_BINS   = { 1, 2, 5, 2, 1 }

-- Rules and pay table (multiples of the bet)
PK.BALLS          = 10
PK.ORANGE         = 25
PK.GREEN          = 2
PK.ALL_CLEAR_BASE = 4        -- x bin multiplier: 4x .. 20x
PK.BALL_BONUS     = 1        -- per ball still in the launcher at the clear
PK.PARTIAL_PAYS   = { { 23, 2 }, { 20, 1 } }   -- { oranges hit, pays } top down
PK.PEG_POINTS     = { blue = 10, orange = 100, green = 10 }

PK.PHASE = { AIM = "AIM", FLIGHT = "FLIGHT", FEVER = "FEVER", OVER = "OVER" }

local W, H = PK.FIELD_W, PK.FIELD_H
local sin, cos, sqrt, floor, abs = math.sin, math.cos, math.sqrt, math.floor, math.abs
-- WoW's Lua 5.1 has math.atan2; newer Luas (the test harness) fold it into atan
local atan2 = math.atan2 or math.atan
local pi = math.pi

-- Score multiplier climbs with oranges hit, like the original: x1 to 9,
-- x2 from 10, x3 from 15, x5 from 20, x10 on the last one.
function PK:ScoreMultiplier(orangesHit)
    if orangesHit >= 25 then return 10 end
    if orangesHit >= 20 then return 5 end
    if orangesHit >= 15 then return 3 end
    if orangesHit >= 10 then return 2 end
    return 1
end

-- ---------------------------------------------------------------------
-- Seeded RNG (Park-Miller). Layouts must be reproducible from a seed so a
-- test can replay a round and a bug report can name its layout.
local function newRng(seed)
    local s = floor(seed or 1) % 2147483647
    if s <= 0 then s = s + 2147483646 end
    -- rng()        -> float in [0, 1)
    -- rng(lo, hi)  -> integer in [lo, hi]
    local function rng(lo, hi)
        s = (s * 48271) % 2147483647
        local r = (s - 1) / 2147483646
        if lo then return lo + floor(r * (hi - lo + 1)) end
        return r
    end
    -- small seeds give tiny first draws; burn a few so seed 1..60 differ
    for _ = 1, 8 do rng() end
    return rng
end

-- ---------------------------------------------------------------------
-- Layouts. Each generator calls add(x, y) for every peg it wants; add
-- rejects pegs outside the zone or too close to one already placed.
local LAYOUTS = {}

-- Brickwork: staggered rows with a few bricks missing.
LAYOUTS[#LAYOUTS + 1] = { name = "Brickwork", build = function(rng, add)
    local rows = 7
    local spacing = (W - 2 * PK.PEG_MARGIN) / 8
    for r = 0, rows - 1 do
        local y = 150 + (470 - 150) * r / (rows - 1)
        local offset = (r % 2) * spacing / 2
        local cols = (r % 2 == 0) and 9 or 8
        for c = 0, cols - 1 do
            if rng() > 0.12 then add(PK.PEG_MARGIN + offset + c * spacing, y) end
        end
    end
end }

-- Rainbow: four arcs centred below the field, pegs every ~44px along each.
LAYOUTS[#LAYOUTS + 1] = { name = "Rainbow", build = function(rng, add)
    local cx, cy = W / 2, 760
    for _, rad in ipairs({ 300, 380, 460, 540 }) do
        local reach = (W / 2 - PK.PEG_MARGIN) / rad
        if reach > 1 then reach = 1 end
        local tmax = math.asin(reach)
        local n = floor(rad * 2 * tmax / 44) + 1
        for k = 0, n - 1 do
            local t = -tmax + 2 * tmax * k / (n - 1)
            add(cx + rad * sin(t), cy - rad * cos(t))
        end
    end
    -- a crown of three up top so the first shot has something to hit
    for _, x in ipairs({ W / 2 - 110, W / 2, W / 2 + 110 }) do add(x, 160) end
end }

-- Diamonds: three hollow diamonds and a floor row.
LAYOUTS[#LAYOUTS + 1] = { name = "Diamonds", build = function(rng, add)
    local function diamond(cx, cy, half, perEdge)
        for e = 0, 3 do
            local ax, ay = cx + (e == 0 and 0 or e == 1 and half or e == 2 and 0 or -half),
                           cy + (e == 0 and -half or e == 1 and 0 or e == 2 and half or 0)
            local bx, by = cx + (e == 0 and half or e == 1 and 0 or e == 2 and -half or 0),
                           cy + (e == 0 and 0 or e == 1 and half or e == 2 and 0 or -half)
            for k = 0, perEdge - 1 do
                local f = k / perEdge
                add(ax + (bx - ax) * f, ay + (by - ay) * f)
            end
        end
    end
    diamond(110, 330, 85, 3)
    diamond(W / 2, 250, 100, 4)
    diamond(W - 110, 330, 85, 3)
    for c = 0, 6 do add(60 + c * (W - 120) / 6, 475) end
    add(W / 2, 410)
end }

-- Rings: two concentric rings in the middle, columns down each side.
LAYOUTS[#LAYOUTS + 1] = { name = "Rings", build = function(rng, add)
    local cx, cy = W / 2, 300
    for _, ring in ipairs({ { r = 125, n = 16 }, { r = 62, n = 8 } }) do
        local spin = rng() * pi
        for k = 0, ring.n - 1 do
            local a = spin + 2 * pi * k / ring.n
            add(cx + ring.r * cos(a), cy + ring.r * sin(a))
        end
    end
    add(cx, cy)
    for r = 0, 6 do
        local y = 150 + r * 55
        add(PK.PEG_MARGIN + 8, y)
        add(W - PK.PEG_MARGIN - 8, y)
    end
    for c = 0, 5 do add(100 + c * (W - 200) / 5, 480) end
end }

-- Zigzag: slanted shelves alternating direction, the ball rolls along them.
LAYOUTS[#LAYOUTS + 1] = { name = "Zigzag", build = function(rng, add)
    local shelves = 5
    for s = 0, shelves - 1 do
        local y0 = 140 + s * 80
        local leftToRight = (s % 2 == 0)
        local n = 9
        for k = 0, n - 1 do
            local f = k / (n - 1)
            local x = PK.PEG_MARGIN + 10 + f * (W - 2 * PK.PEG_MARGIN - 20)
            local y = y0 + (leftToRight and f or (1 - f)) * 46
            add(x, y)
        end
    end
end }

PK.LAYOUTS = LAYOUTS

-- Build a peg list for a layout: generator pegs, then random fill to a
-- healthy count, then colours (ORANGE orange, GREEN green, the rest blue).
function PK:BuildPegs(rng, layoutIndex)
    local pegs = {}
    local gap2 = PK.PEG_GAP * PK.PEG_GAP
    local function add(x, y)
        if x < PK.PEG_MARGIN or x > W - PK.PEG_MARGIN then return false end
        if y < PK.PEG_TOP or y > PK.PEG_BOTTOM then return false end
        for _, p in ipairs(pegs) do
            local dx, dy = p.x - x, p.y - y
            if dx * dx + dy * dy < gap2 then return false end
        end
        pegs[#pegs + 1] = { x = x, y = y }
        return true
    end

    local layout = LAYOUTS[layoutIndex] or LAYOUTS[1]
    layout.build(rng, add)

    -- fill thin layouts with scatter so there is always enough to hit
    local tries = 0
    while #pegs < 56 and tries < 600 do
        tries = tries + 1
        add(PK.PEG_MARGIN + rng() * (W - 2 * PK.PEG_MARGIN),
            PK.PEG_TOP + rng() * (PK.PEG_BOTTOM - PK.PEG_TOP))
    end
    -- and thin out crowded ones
    while #pegs > 72 do table.remove(pegs, rng(1, #pegs)) end

    -- colours: shuffle indices, deal orange then green, blue for the rest
    local order = {}
    for i = 1, #pegs do order[i] = i end
    for i = #order, 2, -1 do
        local j = rng(1, i)
        order[i], order[j] = order[j], order[i]
    end
    for k, idx in ipairs(order) do
        local p = pegs[idx]
        if k <= PK.ORANGE then p.kind = "orange"
        elseif k <= PK.ORANGE + PK.GREEN then p.kind = "green"
        else p.kind = "blue" end
        p.lit = false
        p.gone = false
    end
    return pegs, layout.name
end

-- ---------------------------------------------------------------------
-- Round state

function PK:NewRound(bet, seed)
    local rng = newRng(seed or 1)
    local layoutIndex = rng(1, #LAYOUTS)
    local pegs, layoutName = self:BuildPegs(rng, layoutIndex)
    local state = {
        bet = bet or 1,
        seed = seed or 1,
        layout = layoutName,
        pegs = pegs,
        balls = {},
        ballsLeft = PK.BALLS,
        ballsFired = 0,
        orangeLeft = PK.ORANGE,
        orangeHit = 0,
        score = 0,
        phase = PK.PHASE.AIM,
        aim = 0,                       -- radians from straight down, +right
        time = 0,
        acc = 0,
        bucket = { x = W / 2, dir = 1 },
        feverBin = nil,                -- multiplier of the first bin landed in
        result = nil,
        rng = rng,
    }
    return state
end

local function clampAim(a)
    local lim = PK.MAX_AIM_DEG * pi / 180
    if a > lim then return lim end
    if a < -lim then return -lim end
    return a
end

-- Point the launcher at field position (tx, ty). Targets above the muzzle
-- still aim to whichever side the cursor is on, pinned at the limit.
function PK:Aim(state, tx, ty)
    local dx, dy = tx - W / 2, ty - PK.LAUNCHER_Y
    if dx == 0 and dy <= 0 then return state.aim end
    state.aim = clampAim(atan2(dx, dy))
    return state.aim
end

function PK:MuzzlePos(state)
    local a = state.aim or 0
    return W / 2 + sin(a) * 14, PK.LAUNCHER_Y + cos(a) * 14
end

local function hitsPeg(state, x, y)
    local rr = PK.BALL_R + PK.PEG_R
    for _, p in ipairs(state.pegs) do
        if not p.gone then
            local dx, dy = x - p.x, y - p.y
            if dx * dx + dy * dy < rr * rr then return p end
        end
    end
    return nil
end

-- Aim guide: the free-flight arc (gravity and walls only) sampled every
-- `every` seconds for up to `maxT`, cut off at the first peg it would
-- touch. Returns a list of {x, y} and that first peg (or nil).
function PK:Guide(state, maxT, every)
    maxT, every = maxT or 0.9, every or 0.045
    local pts = {}
    local a = state.aim or 0
    local x, y = self:MuzzlePos(state)
    local vx, vy = sin(a) * PK.LAUNCH_SPEED, cos(a) * PK.LAUNCH_SPEED
    local t, nextSample = 0, every
    local dt = PK.STEP
    local first
    while t < maxT do
        vy = vy + PK.GRAVITY * dt
        x, y = x + vx * dt, y + vy * dt
        if x < PK.BALL_R then x = PK.BALL_R; vx = -vx * PK.RESTITUTION end
        if x > W - PK.BALL_R then x = W - PK.BALL_R; vx = -vx * PK.RESTITUTION end
        if y > H then break end
        first = hitsPeg(state, x, y)
        if first then break end
        t = t + dt
        if t >= nextSample then
            pts[#pts + 1] = { x = x, y = y }
            nextSample = nextSample + every
        end
    end
    return pts, first
end

function PK:CanLaunch(state)
    return state.phase == PK.PHASE.AIM and state.ballsLeft > 0
end

function PK:Launch(state)
    if not self:CanLaunch(state) then return false end
    local a = state.aim or 0
    local x, y = self:MuzzlePos(state)
    state.balls[#state.balls + 1] = {
        x = x, y = y,
        vx = sin(a) * PK.LAUNCH_SPEED, vy = cos(a) * PK.LAUNCH_SPEED,
        slow = 0,
    }
    state.ballsLeft = state.ballsLeft - 1
    state.ballsFired = state.ballsFired + 1
    state.phase = PK.PHASE.FLIGHT
    return true
end

-- ---------------------------------------------------------------------
-- Simulation

local function push(events, ev)
    if events then events[#events + 1] = ev end
end

local function lightPeg(state, p, ball, events)
    p.lit = true
    p.hitAt = state.time
    local pts = PK.PEG_POINTS[p.kind] * PK:ScoreMultiplier(state.orangeHit)
    if p.kind == "orange" then
        state.orangeHit = state.orangeHit + 1
        state.orangeLeft = state.orangeLeft - 1
        pts = PK.PEG_POINTS.orange * PK:ScoreMultiplier(state.orangeHit)
    end
    state.score = state.score + pts
    push(events, { type = "peg", peg = p, points = pts, x = p.x, y = p.y })

    if p.kind == "green" then
        -- Multiball: a twin leaves the peg mirrored across the vertical.
        state.balls[#state.balls + 1] = {
            x = ball.x, y = ball.y, vx = -ball.vx, vy = ball.vy, slow = 0,
        }
        push(events, { type = "power", power = "multiball", x = p.x, y = p.y })
    end

    if p.kind == "orange" and state.orangeLeft == 0 and state.phase ~= PK.PHASE.FEVER then
        state.phase = PK.PHASE.FEVER
        push(events, { type = "fever" })
    end
end

-- Lit pegs leave the field (after a ball drains, or to free a stuck ball).
local function clearLitPegs(state, events)
    local n = 0
    for _, p in ipairs(state.pegs) do
        if p.lit and not p.gone then
            p.gone = true
            p.goneAt = state.time
            n = n + 1
        end
    end
    if n > 0 then push(events, { type = "clear", count = n }) end
    return n
end

local function bucketTop() return H - PK.BUCKET_H - 6 end
PK.BucketTop = bucketTop

local function moveBucket(state, dt)
    local b = state.bucket
    local lo, hi = PK.BUCKET_W / 2 + 4, W - PK.BUCKET_W / 2 - 4
    b.x = b.x + b.dir * PK.BUCKET_SPEED * dt
    if b.x > hi then b.x = hi; b.dir = -1 end
    if b.x < lo then b.x = lo; b.dir = 1 end
end

local function finishRound(state, events)
    local allClear = state.orangeLeft == 0
    local win = 0
    if allClear then
        local mult = state.feverBin or PK.FEVER_BINS[1]
        win = state.bet * PK.ALL_CLEAR_BASE * mult + state.bet * PK.BALL_BONUS * state.ballsLeft
    else
        for _, tier in ipairs(PK.PARTIAL_PAYS) do
            if state.orangeHit >= tier[1] then win = state.bet * tier[2]; break end
        end
    end
    state.result = {
        win = win,
        allClear = allClear,
        oranges = state.orangeHit,
        binMult = state.feverBin,
        ballsLeft = state.ballsLeft,
        score = state.score,
        layout = state.layout,
    }
    state.phase = PK.PHASE.OVER
    push(events, { type = "round_over", result = state.result })
end

local function integrateBall(state, ball, dt, events)
    ball.vy = ball.vy + PK.GRAVITY * dt
    ball.x = ball.x + ball.vx * dt
    ball.y = ball.y + ball.vy * dt

    -- walls and ceiling
    local R = PK.BALL_R
    if ball.x < R then ball.x = R; if ball.vx < 0 then ball.vx = -ball.vx * PK.RESTITUTION end end
    if ball.x > W - R then ball.x = W - R; if ball.vx > 0 then ball.vx = -ball.vx * PK.RESTITUTION end end
    if ball.y < R then ball.y = R; if ball.vy < 0 then ball.vy = -ball.vy * PK.RESTITUTION end end

    -- pegs
    local rr = R + PK.PEG_R
    for _, p in ipairs(state.pegs) do
        if not p.gone then
            local dx, dy = ball.x - p.x, ball.y - p.y
            local d2 = dx * dx + dy * dy
            if d2 < rr * rr then
                local d = sqrt(d2)
                local nx, ny
                if d < 0.0001 then nx, ny = 0, -1 else nx, ny = dx / d, dy / d end
                ball.x, ball.y = p.x + nx * rr, p.y + ny * rr
                local vn = ball.vx * nx + ball.vy * ny
                if vn < 0 then
                    local k = (1 + PK.RESTITUTION) * vn
                    ball.vx = ball.vx - k * nx
                    ball.vy = ball.vy - k * ny
                    push(events, { type = "bounce", peg = p, speed = -vn })
                end
                if not p.lit then lightPeg(state, p, ball, events) end
            end
        end
    end

    -- bottom: bins during Fever, the bucket otherwise
    if state.phase == PK.PHASE.FEVER then
        if ball.y + R >= H - 2 then
            local idx = floor(ball.x / (W / #PK.FEVER_BINS)) + 1
            if idx < 1 then idx = 1 elseif idx > #PK.FEVER_BINS then idx = #PK.FEVER_BINS end
            local mult = PK.FEVER_BINS[idx]
            if not state.feverBin then state.feverBin = mult end
            push(events, { type = "bin", index = idx, mult = mult, x = ball.x })
            return false
        end
    else
        local b = state.bucket
        local top = bucketTop()
        if ball.vy > 0 and ball.y + R >= top and ball.y - R <= top + PK.BUCKET_H then
            local half = PK.BUCKET_W / 2
            local off = ball.x - b.x
            if abs(off) <= half - R then
                state.ballsLeft = state.ballsLeft + 1
                push(events, { type = "bucket", x = ball.x })
                return false
            elseif abs(off) <= half + R then
                -- clipped a rim: a dull bounce off the lip
                ball.y = top - R
                ball.vy = -ball.vy * 0.45
                ball.vx = ball.vx + (off > 0 and 60 or -60)
            end
        end
    end
    if ball.y - R > H then
        push(events, { type = "lost", x = ball.x })
        return false
    end

    -- stuck detection: a ball resting on pegs clears the lit ones under it,
    -- and if it still won't move it is given up
    local speed = sqrt(ball.vx * ball.vx + ball.vy * ball.vy)
    if speed < PK.STUCK_SPEED then ball.slow = ball.slow + dt else ball.slow = 0 end
    if ball.slow > PK.STUCK_SECS then
        if clearLitPegs(state, events) > 0 then
            ball.slow = 0
            ball.vy = ball.vy + 20
        else
            push(events, { type = "lost", x = ball.x, stuck = true })
            return false
        end
    end
    return true
end

local function substep(state, dt, events)
    state.time = state.time + dt
    if state.phase ~= PK.PHASE.FEVER then moveBucket(state, dt) end
    if state.phase == PK.PHASE.AIM or state.phase == PK.PHASE.OVER then return end

    for i = #state.balls, 1, -1 do
        local ball = state.balls[i]
        if not integrateBall(state, ball, dt, events) then
            table.remove(state.balls, i)
        end
    end

    if #state.balls == 0 then
        if state.phase == PK.PHASE.FEVER then
            finishRound(state, events)
        else
            clearLitPegs(state, events)
            if state.ballsLeft > 0 then
                state.phase = PK.PHASE.AIM
                push(events, { type = "ready" })
            else
                finishRound(state, events)
            end
        end
    end
end

-- Advance the round by dt seconds of real time. Events (peg, bounce,
-- power, fever, clear, bucket, lost, bin, ready, round_over) are appended
-- to `events` when given. Fever runs in slow motion.
function PK:Step(state, dt, events)
    if dt > 0.1 then dt = 0.1 end
    if state.phase == PK.PHASE.FEVER then dt = dt * PK.FEVER_SLOWMO end
    state.acc = state.acc + dt
    local step = PK.STEP
    local guard = 0
    while state.acc >= step and guard < 60 do
        substep(state, step, events)
        state.acc = state.acc - step
        guard = guard + 1
    end
    return events
end

-- The pay table as rows for the UI: { label, pays } with pays in bets.
function PK:PayTableRows()
    local rows = {}
    local bins = PK.FEVER_BINS
    local best, worst = bins[1], bins[1]
    for _, m in ipairs(bins) do
        if m > best then best = m end
        if m < worst then worst = m end
    end
    rows[#rows + 1] = { label = "Clear all " .. PK.ORANGE .. " (center bin)", pays = PK.ALL_CLEAR_BASE * best }
    rows[#rows + 1] = { label = "Clear all " .. PK.ORANGE .. " (edge bin)", pays = PK.ALL_CLEAR_BASE * worst }
    rows[#rows + 1] = { label = "Each ball left at the clear", pays = PK.BALL_BONUS }
    for _, tier in ipairs(PK.PARTIAL_PAYS) do
        rows[#rows + 1] = { label = tier[1] .. "+ orange pegs", pays = tier[2] }
    end
    return rows
end
