--[[
    Chairface's Casino - UI/ChipPot.lua
    A visual pot: renders a gold (or tournament-chip) amount as stacks of
    the denomination chip art in Textures\chips\ (1g..1000g), decomposed
    greedily - one column per denomination, chips stacked with a slight
    rise. The printed number stays the truth; the stacks are theatre,
    capped per column so a monster pot doesn't wallpaper the table.

    Usage:
        local pot = BJ.UI.ChipPot:Attach(parentFrame)
        pot:SetPoint(...)
        pot:SetAmount(1234)     -- rebuilds the stacks (0 clears them)
]]

local BJ = ChairfacesCasino
local UI = BJ.UI
UI.ChipPot = {}
local CP = UI.ChipPot

local DENOMS = { 1000, 500, 100, 50, 25, 10, 5, 2, 1 }
local CHIP = 20          -- base chip size (px) before CP.SCALE
local STACK_DY = 3       -- vertical rise per chip in a stack
local COL_GAP = 0.62     -- column spacing as a fraction of chip size:
                         -- under 1 = the stacks sit close, overlapping
local MAX_PER_STACK = 6  -- visual cap per denomination

-- ONE scale for every chip pile in the addon (pots and player stacks).
-- Tune it live in debug/test mode with /cc chipscale <n>.
CP.SCALE = 2

local TEX_BASE = "Interface\\AddOns\\Chairfaces Casino\\Textures\\chips\\"

local function setAmount(f, amount)
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    local used = 0
    local s = CP.SCALE or 1
    local chip, dy = CHIP * s, STACK_DY * s
    local dx = math.floor(chip * COL_GAP)
    f:SetHeight(chip + dy * (MAX_PER_STACK - 1))

    if amount > 0 then
        local columns = {}
        local left = amount
        for _, d in ipairs(DENOMS) do
            local n = math.floor(left / d)
            if n > 0 then
                left = left - n * d
                table.insert(columns, { denom = d, count = math.min(n, MAX_PER_STACK) })
            end
        end

        for ci, col in ipairs(columns) do
            for i = 1, col.count do
                used = used + 1
                local tex = f.chips[used]
                if not tex then
                    tex = f:CreateTexture(nil, "ARTWORK")
                    f.chips[used] = tex
                end
                tex:SetSize(chip, chip)
                tex:SetTexture(TEX_BASE .. col.denom .. "g")
                tex:ClearAllPoints()
                tex:SetPoint("BOTTOMLEFT", (ci - 1) * dx, (i - 1) * dy)
                tex:Show()
            end
        end
        -- width follows the columns so a centered anchor stays centered
        f:SetWidth(math.max(10, (#columns - 1) * dx + chip))
    end

    for i = used + 1, #f.chips do
        f.chips[i]:Hide()
    end
end

function CP:Attach(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(10, (CHIP + STACK_DY * (MAX_PER_STACK - 1)) * (CP.SCALE or 1))
    f.chips = {}
    f.SetAmount = setAmount
    return f
end

-- Debug knob: change the global chip scale and let the next display
-- update re-render every pile (pots and stacks update constantly).
function CP:SetScale(n)
    CP.SCALE = math.max(0.5, math.min(6, tonumber(n) or 2))
    BJ:Print(("Chip scale set to %.2g (temporary - bake the keeper into UI/ChipPot.lua CP.SCALE)."):format(CP.SCALE))
end
