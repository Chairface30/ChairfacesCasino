--[[
    Chairface's Casino - Arcade.lua
    The solo arcade: a persistent FAKE credit balance plus the pure game
    logic for the two machines (Slots and Jacks-or-Better video poker),
    in the spirit of the old handheld Vegas games.

    No gold, no group, no multiplayer, no leaderboard - just credits
    saved in ChairfacesCasinoDB.arcade that follow the character around.
    Because nothing is at stake between players, plain math.random is
    fine here (unlike the seeded, verifiable multiplayer games).

    This file is UI-free so the machine logic can be unit-tested outside
    the game; UI/SlotsFrame.lua and UI/VideoPokerFrame.lua render it.
]]

local BJ = ChairfacesCasino
BJ.Arcade = {}
local Arcade = BJ.Arcade

Arcade.STARTING_CREDITS = 1000

-- The broke-player comp is hardcoded and obfuscated (same spirit as the
-- banker name): the amount is decoded at load rather than sitting in the
-- source as an editable number.
local function ax(a,b) local r,c=0,1 for i=0,7 do local ba,bb=a%2,b%2 if ba~=bb then r=r+c end a,b,c=math.floor(a/2),math.floor(b/2),c*2 end return r end
local function an(s) local r="" for i=1,#s do r=r..string.char(ax(string.byte(s,i),6)) end return tonumber(r) or 0 end
Arcade.COMP_AMOUNT = an("36")

-- High-roller bet ladder shared by every machine. The +/- steppers walk the
-- full ladder; the MAX BET buttons cycle through the high tiers.
Arcade.BET_STEPS = { 1, 2, 3, 4, 5, 10, 15, 25, 50, 100, 500, 1000,
                     10000, 20000, 50000, 100000 }
Arcade.HIGH_STEPS = { 5, 10, 15, 25, 50, 100, 500, 1000,
                      10000, 20000, 50000, 100000 }

function Arcade:NextBetStep(current, dir)
    local steps = self.BET_STEPS
    local idx = 1
    for i, v in ipairs(steps) do
        if v == current then idx = i break end
        if v > current then idx = (dir > 0) and (i - 1) or i break end
    end
    idx = math.max(1, math.min(#steps, idx + dir))
    return steps[idx]
end

-- MAX BET commits what the bankroll can actually cover: the biggest ladder
-- step whose total cost (step x units, e.g. 9 slot lines) fits the balance.
function Arcade:MaxAffordableStep(units)
    units = units or 1
    local credits = self:GetCredits()
    local best = self.BET_STEPS[1]
    for _, v in ipairs(self.BET_STEPS) do
        if v * units <= credits then best = v end
    end
    return best
end

--[[
    CREDIT BALANCE (persistent, per character, entirely fake)
]]

function Arcade:GetDB()
    BJ.db = BJ.db or {}
    if not BJ.db.arcade then
        BJ.db.arcade = {
            credits = self.STARTING_CREDITS,
            refills = 0,
            totalWagered = 0,
            totalWon = 0,
            bestSlotsWin = 0,
            bestPokerWin = 0,
            bestBlackjackWin = 0,
            bestKenoWin = 0,
        }
    end
    return BJ.db.arcade
end

function Arcade:GetCredits()
    return self:GetDB().credits or 0
end

-- Returns true and deducts if the balance covers the wager
function Arcade:Spend(amount)
    local db = self:GetDB()
    if amount <= 0 or (db.credits or 0) < amount then return false end
    db.credits = db.credits - amount
    db.totalWagered = (db.totalWagered or 0) + amount
    self:SaveVault()
    return true
end

function Arcade:Award(amount)
    if amount <= 0 then return end
    local db = self:GetDB()
    db.credits = (db.credits or 0) + amount
    db.totalWon = (db.totalWon or 0) + amount
    self:SaveVault()
end

-- Lifetime comp counter. Lives in ChairfacesCasinoSaved (a different saved
-- variable from the settings/arcade DB) so wiping or resetting addon data does
-- NOT clear it - the pit boss never forgets.
function Arcade:GetLifetimeComps()
    ChairfacesCasinoSaved = ChairfacesCasinoSaved or {}
    return ChairfacesCasinoSaved.arcadeLifetimeComps or 0
end

function Arcade:BumpLifetimeComps()
    ChairfacesCasinoSaved = ChairfacesCasinoSaved or {}
    ChairfacesCasinoSaved.arcadeLifetimeComps = (ChairfacesCasinoSaved.arcadeLifetimeComps or 0) + 1
    return ChairfacesCasinoSaved.arcadeLifetimeComps
end

-- Broke? The pit boss takes pity. Only works when you can't cover a
-- single credit, so it can't be farmed while solvent.
function Arcade:CompMe()
    local db = self:GetDB()
    if (db.credits or 0) >= 1 then return false end
    db.credits = self.COMP_AMOUNT
    db.refills = (db.refills or 0) + 1
    self:BumpLifetimeComps()
    self:SaveVault()
    return true, db.refills
end

--[[
    THE CREDIT VAULT
    The balance is mirrored into ChairfacesCasinoSaved as an encrypted,
    checksummed record. SavedVariables live in the WTF folder - NOT the addon
    folder - so removing or reinstalling the addon never touches them. On top
    of that, the vault survives the addon's own data resets and defeats
    hand-editing of the plaintext DB: at login the vault is authoritative,
    so an edited balance simply snaps back.
]]

local function vaultChecksum(credits, comps)
    local n = 7919
    local key = "IBKCXLKIO"
    for i = 1, #key do n = (n * 33 + string.byte(key, i)) % 2147483647 end
    return (n + credits * 13 + comps * 7) % 2147483647
end

-- Second, off-site mirror: the LibScrying satellite addon exists solely to
-- own a SavedVariables file under an unrelated name (WTF/.../LibScrying.lua).
-- Someone hunting for casino data to delete won't connect it; wiping the
-- casino's own file leaves this copy standing, and vice versa.
local function offsite()
    if type(ScryingCache) == "table" then return ScryingCache end
    return nil
end

function Arcade:SaveVault()
    if not (BJ.Compression and BJ.Compression.EncodeForSave) then return end
    ChairfacesCasinoSaved = ChairfacesCasinoSaved or {}
    local db = self:GetDB()
    local credits = math.floor(db.credits or 0)
    local comps = ChairfacesCasinoSaved.arcadeLifetimeComps or 0
    local encoded = BJ.Compression:EncodeForSave({
        credits = credits, comps = comps, ts = time(),
        sum = vaultChecksum(credits, comps),
    })
    ChairfacesCasinoSaved.arcadeVault = encoded
    local sc = offsite()
    if sc then sc.d = encoded end
end

-- Decode + validate one vault blob; nil if missing/corrupt/tampered.
local function readVault(encoded)
    if not encoded then return nil end
    local rec = BJ.Compression:DecodeFromSave(encoded)
    if type(rec) == "table" and type(rec.credits) == "number"
        and rec.sum == vaultChecksum(rec.credits, rec.comps or 0) then
        return rec
    end
    return nil
end

function Arcade:LoadVault()
    if self.vaultLoaded then return end
    self.vaultLoaded = true
    if not (BJ.Compression and BJ.Compression.DecodeFromSave) then return end
    ChairfacesCasinoSaved = ChairfacesCasinoSaved or {}

    -- read both mirrors; the freshest valid record wins
    local main = readVault(ChairfacesCasinoSaved.arcadeVault)
    local sc = offsite()
    local off = sc and readVault(sc.d) or nil
    local rec = main
    if off and (not rec or (off.ts or 0) > (rec.ts or 0)) then
        rec = off
    end

    if rec then
        local db = self:GetDB()
        db.credits = rec.credits
        if (rec.comps or 0) > (ChairfacesCasinoSaved.arcadeLifetimeComps or 0) then
            ChairfacesCasinoSaved.arcadeLifetimeComps = rec.comps
        end
        -- re-mint both mirrors so a deleted/stale copy heals itself
        self:SaveVault()
    else
        -- first run (or both vaults corrupt): mint fresh ones from the DB
        self:SaveVault()
    end
end

do
    local vboot = CreateFrame("Frame")
    vboot:RegisterEvent("PLAYER_LOGIN")
    vboot:RegisterEvent("PLAYER_LOGOUT")
    vboot:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_LOGIN" then
            -- saved variables are in by now; restore the authoritative balance
            C_Timer.After(1, function() Arcade:LoadVault() end)
        else
            Arcade:SaveVault()
        end
    end)
end

--[[
    CREDIT GIFTS (one-way send)
    Fake credits can be gifted to another player running the addon: the sender
    deducts immediately and whispers an addon message; the receiver's balance
    grows when it arrives. One-way and fire-and-forget - if the target is
    offline or has no addon, the credits are gone (the pit boss keeps the
    difference). It's funny money; keep it simple.
]]

local GIFT_PREFIX = "CCArcade"

-- Sanity ceiling shared by every inbound/outbound credit transfer.
local MAX_TRANSFER = 100000000

-- Short (realm-less) form of a typed or wire-supplied character name.
local function shortName(name)
    return name and (name:match("^([^-]+)") or name) or nil
end

function Arcade:SendCredits(target, amount)
    amount = math.floor(tonumber(amount) or 0)
    target = target and target:gsub("^%s+", ""):gsub("%s+$", "")
    if not target or target == "" then return false, "No target named" end
    if amount < 1 then return false, "Amount must be at least 1" end
    local myName = BJ:MyName()
    if target:lower() == myName:lower() then return false, "You can't gift yourself" end
    if not self:Spend(amount) then return false, "Not enough credits" end

    C_ChatInfo.SendAddonMessage(GIFT_PREFIX, "GIFT|" .. amount, "WHISPER", target)
    BJ:Print("Sent |cffffd700" .. amount .. "|r arcade credits to " .. target ..
        ". |cff888888(One-way - if they're offline or addon-less, the house keeps it.)|r")
    if BJ.UI then
        if BJ.UI.Slots and BJ.UI.Slots.UpdateDisplay then BJ.UI.Slots:UpdateDisplay() end
        if BJ.UI.Reels and BJ.UI.Reels.RefreshAll then BJ.UI.Reels:RefreshAll() end
        if BJ.UI.VideoPoker and BJ.UI.VideoPoker.UpdateDisplay then BJ.UI.VideoPoker:UpdateDisplay() end
    end
    return true
end

--[[
    CREDIT GRANTS (debug, allowlisted characters only)
    Same wire as a gift, but the granter's own balance is never touched and
    the amount is conjured out of the house's pocket. The gate is the debug
    allow-list from TestMode (the one behind /cc db), enforced on BOTH ends:
    the sender's UI/command is hidden from everyone else, and the RECEIVER
    re-checks the sender's name before crediting - so a hand-crafted GRANT
    whisper from an unlisted character does nothing.
]]

function Arcade:CanGrantCredits()
    return (BJ.TestMode and BJ.TestMode.CanUseDebugMode
        and BJ.TestMode:CanUseDebugMode()) or false
end

-- The GRANT buttons are built only for allow-listed characters, and shown
-- only while debug mode (/cc db) is on.
function Arcade:GrantVisible()
    return (self:CanGrantCredits() and BJ.TestMode and BJ.TestMode.enabled) and true or false
end

function Arcade:UpdateGrantButtons()
    local UI = BJ.UI
    if not UI then return end
    if UI.Slots and UI.Slots.UpdateGrantButton then UI.Slots:UpdateGrantButton() end
    if UI.VideoPoker and UI.VideoPoker.UpdateGrantButton then UI.VideoPoker:UpdateGrantButton() end
end

function Arcade:GrantCredits(target, amount)
    if not self:CanGrantCredits() then return false, "Not authorized" end
    amount = math.floor(tonumber(amount) or 0)
    target = target and target:gsub("^%s+", ""):gsub("%s+$", "")
    if not target or target == "" then return false, "No target named" end
    if amount < 1 then return false, "Amount must be at least 1" end
    if amount > MAX_TRANSFER then return false, "Amount is too large" end

    -- Granting yourself never needs the wire (a whisper to yourself is
    -- dropped by the receiver anyway) - just move the balance.
    if strlower(shortName(target)) == strlower(BJ:MyName()) then
        local db = self:GetDB()
        db.credits = (db.credits or 0) + amount
        self:SaveVault()
        BJ:Print("|cffff00ffDEBUG:|r granted yourself |cffffd700" .. amount ..
            "|r credits. Balance: |cffffd700" .. db.credits .. "|r")
    else
        C_ChatInfo.SendAddonMessage(GIFT_PREFIX, "GRANT|" .. amount, "WHISPER", target)
        BJ:Print("|cffff00ffDEBUG:|r granted |cffffd700" .. amount ..
            "|r credits to " .. target ..
            ". |cff888888(One-way - nothing arrives if they're offline or addon-less.)|r")
    end

    if BJ.UI then
        if BJ.UI.Slots and BJ.UI.Slots.UpdateDisplay then BJ.UI.Slots:UpdateDisplay() end
        if BJ.UI.Reels and BJ.UI.Reels.RefreshAll then BJ.UI.Reels:RefreshAll() end
        if BJ.UI.VideoPoker and BJ.UI.VideoPoker.UpdateDisplay then BJ.UI.VideoPoker:UpdateDisplay() end
    end
    return true
end

do
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(GIFT_PREFIX)
    end
    local rx = CreateFrame("Frame")
    rx:RegisterEvent("CHAT_MSG_ADDON")
    rx:SetScript("OnEvent", function(_, _, prefix, msg, channel, sender)
        if prefix ~= GIFT_PREFIX or channel ~= "WHISPER" then return end
        local kind, amtStr = msg:match("^(%u+)|(%d+)$")
        if kind ~= "GIFT" and kind ~= "GRANT" then return end
        local amount = tonumber(amtStr or "")
        if not amount or amount < 1 or amount > MAX_TRANSFER then return end
        local short = shortName(sender)
        if short == BJ:MyName() then return end
        -- A grant is house money: only honor it from an allowlisted sender.
        if kind == "GRANT" and not (BJ.TestMode and BJ.TestMode.IsAuthorizedName
            and BJ.TestMode:IsAuthorizedName(short)) then
            return
        end
        local db = Arcade:GetDB()
        db.credits = (db.credits or 0) + amount
        Arcade:SaveVault()
        if kind == "GRANT" then
            BJ:Print("|cff00ff00The pit boss comped you " .. amount .. " arcade credits!|r " ..
                "Balance: |cffffd700" .. db.credits .. "|r")
        else
            BJ:Print("|cff00ff00" .. short .. " sent you " .. amount .. " arcade credits!|r " ..
                "Balance: |cffffd700" .. db.credits .. "|r")
        end
        BJ:PlaySfx("coin.ogg")
        if BJ.UI then
            if BJ.UI.Slots and BJ.UI.Slots.UpdateDisplay then BJ.UI.Slots:UpdateDisplay() end
            if BJ.UI.Reels and BJ.UI.Reels.RefreshAll then BJ.UI.Reels:RefreshAll() end
            if BJ.UI.VideoPoker and BJ.UI.VideoPoker.UpdateDisplay then BJ.UI.VideoPoker:UpdateDisplay() end
        end
    end)
end

--[[
    BUY CREDITS BY MAIL
    Mailing money to the casino banker buys arcade credits: every full
    PRICE_COPPER in the mail's attached money converts to CREDITS_PER_LOT.
    Detection is on the SENDER client (hooking their own SendMail call); the
    banker just collects the money. The banker name is hardcoded and
    obfuscated with the same scheme as the debug allow-list - purchases only
    ever credit mail sent to that one character. Mail whose subject mentions
    "pachinko" is a Gnomish Pachinko plays purchase to the same banker and
    is left to that addon.
]]

-- 10g buys 10000 credits.
Arcade.PRICE_COPPER = 100000
Arcade.CREDITS_PER_LOT = 10000

-- The price of `lots` lots as money text ("10g", "30g").
function Arcade:PriceText(lots)
    return BJ:FormatGold((lots or 1) * self.PRICE_COPPER / 10000)
end

local function bx(a,b) local r,c=0,1 for i=0,7 do local ba,bb=a%2,b%2 if ba~=bb then r=r+c end a,b,c=math.floor(a/2),math.floor(b/2),c*2 end return r end
local function bv(s) local r="" for i=1,#s do r=r..string.char(bx(string.byte(s,i),42)) end return r end
-- On WoW Forever every name has a surname, so the banker is the whole
-- "Chairface Chippendale"; elsewhere just "Chairface".
local BANKER = bv("IBKCXLKIO") .. (BJ.isForever and bv("\10IBCZZODNKFO") or "")

-- Display form of the banker name ("Chairface Chippendale" on Forever)
function Arcade:GetBankerName()
    return (BANKER:gsub("%f[%a]%l", string.upper))
end

-- Fill the Send Mail form with the waiting purchase. Each field is set on its
-- own, and a field the client refuses is named in chat so the player can type
-- it; nothing here clicks or drives Blizzard's mail frames.
function Arcade:ApplyPendingFill()
    local p = self.pendingFill
    if not p then return end
    self.pendingFill = nil
    local failed = {}
    local function try(label, fn)
        local ok = pcall(fn)
        if not ok then failed[#failed + 1] = label end
    end
    local banker = self:GetBankerName()
    try("recipient", function() SendMailNameEditBox:SetText(banker) end)
    try("subject", function() SendMailSubjectEditBox:SetText("arcade credits purchase") end)
    try("message", function()
        SendMailBodyEditBox:SetText(string.format("Buying %d arcade credits for %s.",
            p.credits, self:PriceText(p.lots)))
    end)
    -- The money goes into the VISIBLE money boxes: pressing Send reads them,
    -- and would overwrite a bare SetSendMailMoney with zero.
    try("money", function() MoneyInputFrame_SetCopper(SendMailMoney, p.copper) end)
    local okMoney, copper = pcall(MoneyInputFrame_GetCopper, SendMailMoney)
    if not (okMoney and copper == p.copper) then
        local seen = false
        for _, label in ipairs(failed) do if label == "money" then seen = true end end
        if not seen then failed[#failed + 1] = "money" end
    end

    local price = self:PriceText(p.lots)
    if #failed == 0 then
        BJ:Print("Mail filled out: " .. price .. " to " .. banker .. " for |cffffd700" ..
            p.credits .. "|r credits. Press Send to complete.")
    else
        BJ:Print("|cffff8800Could not fill in: " .. table.concat(failed, ", ") ..
            ".|r Send " .. price .. " to " .. banker .. " for |cffffd700" .. p.credits ..
            "|r credits (type what is missing, then press Send).")
    end
end

-- Get a purchase ready. At an open mailbox the Send Mail form is filled out
-- (now, or as soon as the player opens the Send Mail tab); the player still
-- presses Send themselves.
function Arcade:FillPurchaseMail(lots)
    lots = math.floor(tonumber(lots) or 0)
    if lots < 1 then return false, "Buy at least one lot (" .. self:PriceText(1) .. ")" end
    if not (MailFrame and MailFrame:IsShown()) then
        return false, "Visit a mailbox first - the helper fills the mail out there"
    end
    local copper = lots * self.PRICE_COPPER
    if GetMoney and GetMoney() < copper then
        return false, "You do not have " .. self:PriceText(lots) .. " on you"
    end
    self.pendingFill = { lots = lots, copper = copper, credits = lots * self.CREDITS_PER_LOT }
    if SendMailFrame and SendMailFrame:IsShown() then
        self:ApplyPendingFill()
    else
        -- The Fill Mail button opens the tab itself; say so only if it hasn't
        -- a moment later (Enter in the amount box, or no secure button).
        C_Timer.After(0.3, function()
            if self.pendingFill then
                BJ:Print("Open the mailbox's |cffffd700Send Mail|r tab and the purchase fills in.")
            end
        end)
    end
    return true
end

-- A shortcut right on the mailbox: buying credits IS mailing money to the
-- banker, so the button lives where the mail is. The settings panel can turn
-- it off (settings.showMailHelper); default is on.
function Arcade:UpdateMailHelperVisibility()
    local btn = self.mailHelperButton
    if not btn then return end
    local show = not (BJ.db and BJ.db.settings and BJ.db.settings.showMailHelper == false)
    if show then btn:Show() else btn:Hide() end
end

if MailFrame then
    local mailBtn = CreateFrame("Button", nil, MailFrame, "UIPanelButtonTemplate")
    mailBtn:SetSize(120, 22)
    mailBtn:SetPoint("TOPRIGHT", MailFrame, "BOTTOMRIGHT", -4, -2)
    mailBtn:SetText("Buy Casino Credits")
    mailBtn:SetScript("OnClick", function()
        if BJ.ShowBuyCreditsDialog then BJ:ShowBuyCreditsDialog() end
    end)
    mailBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Buy arcade credits: mail money to the casino")
        GameTooltip:AddLine(Arcade:PriceText(1) .. " = " .. Arcade.CREDITS_PER_LOT .. " credits", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    mailBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    Arcade.mailHelperButton = mailBtn
    -- the button is created before saved vars load, so re-check the setting
    -- every time the mailbox opens (a hidden child stays hidden otherwise)
    MailFrame:HookScript("OnShow", function() Arcade:UpdateMailHelperVisibility() end)
    -- A purchase waiting for the Send Mail tab fills in when it opens (a beat
    -- later, after Blizzard's own refresh of the form).
    if SendMailFrame then
        SendMailFrame:HookScript("OnShow", function()
            if Arcade.pendingFill then
                C_Timer.After(0.1, function() Arcade:ApplyPendingFill() end)
            end
        end)
    end
    MailFrame:HookScript("OnHide", function() Arcade.pendingFill = nil end)
end

do
    local pendingPurchase
    if type(SendMail) == "function" then
        hooksecurefunc("SendMail", function(recipient, subject)
            pendingPurchase = nil
            local money = GetSendMailMoney and GetSendMailMoney() or 0
            recipient = BJ:Readable(recipient) or ""
            local short = recipient:match("^([^-]+)") or recipient
            -- typed by hand, so tolerate stray or doubled spaces
            short = short:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
            -- the same banker sells Gnomish Pachinko plays: that mail says
            -- "pachinko" in its subject and is not a credit purchase
            local subjectText = (BJ:Readable(subject) or ""):lower()
            if subjectText:find("pachinko", 1, true) then return end
            if short:lower() == BANKER and money >= Arcade.PRICE_COPPER then
                pendingPurchase = { money = money }
            end
        end)
    end
    local mailRx = CreateFrame("Frame")
    mailRx:RegisterEvent("MAIL_SEND_SUCCESS")
    mailRx:SetScript("OnEvent", function()
        if not pendingPurchase then return end
        local lots = math.floor(pendingPurchase.money / Arcade.PRICE_COPPER)   -- whole lots only
        local credits = lots * Arcade.CREDITS_PER_LOT
        pendingPurchase = nil
        if credits <= 0 then return end
        local db = Arcade:GetDB()
        db.credits = (db.credits or 0) + credits
        Arcade:SaveVault()
        BJ:Print(string.format(
            "|cff00ff00Credit purchase!|r %s mailed to the casino: |cffffd700%d|r arcade credits. Balance: |cffffd700%d|r",
            Arcade:PriceText(lots), credits, db.credits))
        if BJ.UI then
            if BJ.UI.Slots and BJ.UI.Slots.UpdateDisplay then BJ.UI.Slots:UpdateDisplay() end
            if BJ.UI.Reels and BJ.UI.Reels.RefreshAll then BJ.UI.Reels:RefreshAll() end
            if BJ.UI.VideoPoker and BJ.UI.VideoPoker.UpdateDisplay then BJ.UI.VideoPoker:UpdateDisplay() end
        end
    end)
end

--[[
    SLOTS - "Azeroth Riches"
    Five reels, each showing a window five symbols tall (a 5x5 grid). Five
    paylines: top row, middle row, bottom row, and the two corner-to-corner
    diagonals. The player picks how many lines are active (left to right) and a
    per-line bet; wins pay only on active lines for 3+ matching symbols from the
    leftmost reel. A mini WoW Token is a scatter: 3+ of them on active-line cells
    triggers a randomly chosen bonus mini-game (chest / wheel / free spins).
]]

Arcade.Slots = {}
local Slots = Arcade.Slots

Slots.REELS = 5
Slots.ROWS  = 5

-- Symbol table: id, display texture, weight (stops per reel). "token" is the
-- WoW Token coin, "wild" substitutes for everything else, and the fruit and
-- coin family fills out the low end like a classic fruit machine.
Slots.SYMBOLS = {
    { id = "token",    icon = "Interface\\Icons\\wow_token01",                 weight = 1 },
    -- WILD: substitutes for every paying symbol (never the token coin).
    { id = "wild",     icon = "Interface\\AddOns\\Chairfaces Casino\\Textures\\icon",   weight = 2 },
    { id = "skull",    icon = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01", weight = 2 },
    { id = "gold",     icon = "Interface\\Icons\\INV_Misc_Coin_02",            weight = 3 },
    { id = "ruby",     icon = "Interface\\Icons\\INV_Misc_Gem_Ruby_01",        weight = 4 },
    { id = "emerald",  icon = "Interface\\Icons\\INV_Misc_Gem_Emerald_01",     weight = 4 },
    { id = "sapphire", icon = "Interface\\Icons\\INV_Misc_Gem_Sapphire_01",    weight = 4 },
    { id = "die",      icon = "Interface\\AddOns\\Chairfaces Casino\\Textures\\dice\\die_red6", weight = 4 },
    { id = "shroom",   icon = "Interface\\Icons\\INV_Mushroom_11",             weight = 4 },
    { id = "melon",    icon = "Interface\\Icons\\INV_Misc_Food_22",            weight = 5 },
    { id = "apple",    icon = "Interface\\Icons\\INV_Misc_Food_19",            weight = 6 },
    { id = "silver",   icon = "Interface\\Icons\\INV_Misc_Coin_03",            weight = 6 },
    { id = "copper",   icon = "Interface\\Icons\\INV_Misc_Coin_05",            weight = 6 },
}

-- Per-line, per-credit payouts by matching count from the leftmost reel.
-- Top-heavy schedule (simmed at ~96.7% RTP with everything below): the
-- 3-of-a-kind dribble stays small, 4-of-a-kinds pay double the old book,
-- 5-of-a-kinds pay ~4.3x it - the player barely loses over time, and the
-- return comes back as spaced BIG hits, not constant small change.
-- July 2026 mid-tier retune: 3/4-of-a-kind pays fattened so a single
-- mid-symbol hit clears 2x the 9-line total bet (medium wins land every
-- ~13 spins instead of ~25, worst droughts halved), funded by trimming
-- the 4/5-of-a-kind top shelf. Sim-verified line RTP ~77% -> ~99% total
-- with the side features (tools: 200k-spin lupa run of this file).
-- Sep 2026 balance (tools/slots_sim.py): two of a kind now pays on the six
-- best symbols, so nearly half of all spins pay something -- mostly a
-- fraction of the bet, which keeps a player in the game. The whole machine
-- returns ~95% at every bet size: the house keeps its edge, without
-- draining anyone fast.
Slots.LINE_PAY = {
    wild     = { [2] = 4, [3] = 50, [4] = 460, [5] = 4400 },
    skull    = { [2] = 3, [3] = 40, [4] = 320, [5] = 3000 },
    gold     = { [2] = 2, [3] = 24, [4] = 100, [5] = 750 },
    ruby     = { [2] = 2, [3] = 22, [4] = 96,  [5] = 330 },
    emerald  = { [2] = 2, [3] = 18, [4] = 68,  [5] = 250 },
    sapphire = { [2] = 2, [3] = 16, [4] = 56,  [5] = 175 },
    die      = { [3] = 16, [4] = 60,  [5] = 210 },
    shroom   = { [3] = 12, [4] = 44,  [5] = 135 },
    melon    = { [3] = 10, [4] = 36,  [5] = 115 },
    apple    = { [3] = 6,  [4] = 28,  [5] = 103 },
    silver   = { [3] = 2,  [4] = 10,  [5] = 64 },
    copper   = { [3] = 1,  [4] = 6,   [5] = 43 },
}


--[[
    FIRESHOT-STYLE COINS (hold & spin)
    Modelled on VGW's Fireshot machines (Stampede Fury et al): every WoW Token
    that lands is a COIN carrying a visible credit value (scaled by the total
    bet). Exactly 3 coins in view triggers one of the small side bonuses; 4 or
    more starts HOLD & SPIN - the coins lock, you get 3 respins, every new
    coin resets the respins to 3, and the round ends when you run dry. You are
    paid the sum of every locked coin, special coins pay the MINI / MINOR /
    MAJOR jackpots, and locking 20+ of the 25 positions hits the progressive
    GRAND, which grows with every wager made on the machine.
]]
Slots.FIRESHOT_TRIGGER = 4        -- coins in view to start hold & spin
Slots.SIDE_BONUS_COINS = 3        -- exactly this many -> chest/wheel/free spins
Slots.FIRESHOT_ROWS = { 1, 2, 3, 4, 5 } -- the hold & spin arena: ALL 25 cells
Slots.FIRESHOT_COIN_CHANCE = 0.05 -- per empty arena cell, per respin
Slots.GRAND_FILL = 20             -- lock this many of the 25 for the GRAND
-- Every jackpot is a real progressive pot (Quartermania-style): seeded, fed
-- by a slice of every wager, and - since the WoW API can't share a pot
-- realm-wide - topped up by a simulated community drip over wall-clock time,
-- online or off (jittered so it never looks metronomic; offline catch-up is
-- capped at a day so a long absence doesn't mint millions). A landing
-- jackpot coin CLAIMS its pot at settle time and the pot reseeds.
-- JACKPOT_PAY stays as a per-total-bet floor so a high roller never wins
-- less than the old fixed multiple.
Slots.JACKPOT_META = {
    mini  = { seed = 5000,    rate = 0.25, feed = 0.005  },
    minor = { seed = 25000,   rate = 0.6,  feed = 0.0075 },
    major = { seed = 60000,   rate = 1.0,  feed = 0.01   },
    grand = { seed = 100000,  rate = 1.5,  feed = 0.02   },
    -- MEGA: the whale pot. Seeds at a million and the simulated realm
    -- feeds it hard; only bets of 100+ are riding for it.
    mega  = { seed = 1000000, rate = 20,   feed = 0.05   },
}
Slots.JACKPOT_PAY = { mini = 10, minor = 25, major = 100, grand = 100, mega = 1000 }  -- floor, x total bet
-- Minimum total bet to be riding for each pot: below it a jackpot coin
-- falls back to its old fixed multiple and never touches the pot.
Slots.JACKPOT_MIN_BET = { mini = 5, minor = 5, major = 5, grand = 5, mega = 100 }

-- Weighted coin faces: plain credit values (x total bet) plus the rare
-- jackpot coins.
Slots.COIN_VALUES = {
    { v = 1,  w = 24 }, { v = 2,  w = 20 }, { v = 3, w = 16 },
    { v = 5,  w = 14 }, { v = 10, w = 10 }, { v = 25, w = 6 },
    { v = 50, w = 3 },
    { jackpot = "mini",  w = 4 },
    { jackpot = "minor", w = 2 },
    { jackpot = "major", w = 1 },
    { jackpot = "mega",  w = 1 },
}
do
    local t = 0
    for _, c in ipairs(Slots.COIN_VALUES) do t = t + c.w end
    Slots.COIN_WEIGHT_TOTAL = t
end

function Slots:RollCoin(totalBet)
    local r = math.random() * self.COIN_WEIGHT_TOTAL
    for _, c in ipairs(self.COIN_VALUES) do
        r = r - c.w
        if r <= 0 then
            if c.jackpot then
                if totalBet >= (self.JACKPOT_MIN_BET[c.jackpot] or 0) then
                    -- value is decided at settle time, when the coin
                    -- claims whatever its pot has grown to
                    return { jackpot = c.jackpot }
                end
                -- bet too small to ride for the pot: the coin lands as a
                -- plain coin at the old fixed multiple instead
                local v = (c.jackpot == "mega") and 100 or self.JACKPOT_PAY[c.jackpot]
                return { value = v * totalBet }
            end
            return { value = c.v * totalBet }
        end
    end
    return { value = totalBet }
end

-- The four progressive pots, stored in db.jackpots (the pre-progressive
-- grand pot migrates in on first touch).
local function jackpotPots(db)
    if not db.jackpots then
        db.jackpots = { grand = db.grandJackpot }
    end
    return db.jackpots
end

-- Lazy community accrual: called before any read/feed/claim, it advances
-- every pot by the simulated realm-wide drip since the last look.
function Slots:AccrueJackpots()
    local db = Arcade:GetDB()
    local pots = jackpotPots(db)
    local now = time()
    local last = db.jackpotLastTick or now
    local elapsed = math.min(math.max(now - last, 0), 86400)
    db.jackpotLastTick = now
    for tier, meta in pairs(self.JACKPOT_META) do
        local pot = pots[tier] or meta.seed
        if pot < meta.seed then pot = meta.seed end
        if elapsed > 0 then
            pot = pot + elapsed * meta.rate * (0.6 + math.random() * 0.8)
        end
        pots[tier] = pot
    end
end

function Slots:FeedJackpots(totalBet)
    self:AccrueJackpots()
    local pots = Arcade:GetDB().jackpots
    for tier, meta in pairs(self.JACKPOT_META) do
        pots[tier] = pots[tier] + totalBet * meta.feed
    end
end

function Slots:GetJackpot(tier)
    self:AccrueJackpots()
    return math.floor(Arcade:GetDB().jackpots[tier] or 0)
end

-- Pay out a pot, never less than the per-bet floor. Bets under the tier's
-- minimum collect the floor only and leave the pot alone.
--
-- A win pays the pot but no more than JACKPOT_CAP times the total bet: the
-- pots hold fixed credit amounts, and uncapped, a 9-credit spin could empty a
-- 25,000-credit pot -- the machine paid out several times what it took in
-- (tools/slots_sim.py, Sep 2026). What the cap leaves stays in the pot for
-- the next winner, so it keeps growing toward the bigger bets. Only a win
-- that empties the pot reseeds it and tells the community.
Slots.JACKPOT_CAP = { mini = 20, minor = 50, major = 150, grand = 400, mega = 120 }  -- x total bet
function Slots:ClaimJackpot(tier, totalBet)
    totalBet = totalBet or 1
    local floor = (self.JACKPOT_PAY[tier] or 0) * totalBet
    if totalBet < (self.JACKPOT_MIN_BET[tier] or 0) then
        return floor
    end
    local pot = self:GetJackpot(tier)
    local cap = (self.JACKPOT_CAP[tier] or math.huge) * totalBet
    local amount = math.max(math.min(pot, cap), floor)
    local seed = self.JACKPOT_META[tier].seed
    if amount >= pot then
        Arcade:GetDB().jackpots[tier] = seed
        -- tell the community this tier just reseeded (they'll drop it to seed too)
        if Arcade.BroadcastJackpotHit then Arcade:BroadcastJackpotHit(tier) end
    else
        Arcade:GetDB().jackpots[tier] = math.max(pot - amount, seed)
    end
    return amount
end

function Slots:GetGrand()   -- kept for older callers
    return self:GetJackpot("grand")
end

--[[
    PROGRESSIVE JACKPOT SYNC (one-time baseline + reset broadcasts)
    The arcade is otherwise non-networked, but the progressive pots feel
    communal, so we give them a light touch of sharing:
      * ONCE per session, the first time you open Slots, we ask peers for
        their current pot values and adopt the biggest per tier (a pot
        should never shrink when you sit down). After a short window the
        session locks and we only ever accrue locally from there.
      * When anyone CLAIMS a tier, they broadcast a HIT so everyone reseeds
        that tier - the pot visibly "resets when someone hits it".
    Reach: guild + party/raid ride free addon whispers (not hardware-gated);
    the realm gets it over the shared hidden "ChairfaceCasino" channel used
    by the LFG board (channel sends are hardware-gated, so they queue and
    flush the next time the Slots window opens). Heavy data (pot values) is
    returned by addon WHISPER, which reaches any realm player.
]]

local JP_PREFIX  = "CCArcadeJP"
local JP_CHANNEL = "ChairfaceCasino"
local JP_MARK    = "CCJP7"
local JP_TIERS   = { "mini", "minor", "major", "grand", "mega" }

local jpSynced  = false   -- session has adopted a baseline; stop pulling
local jpReqSent = false   -- one-time request already fired
local jpQueue   = {}      -- channel sends awaiting a hardware flush

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(JP_PREFIX)
end

local function jpPotsString()
    local db = Arcade:GetDB()
    Slots:AccrueJackpots()
    local parts = {}
    for i, t in ipairs(JP_TIERS) do
        parts[i] = math.floor(db.jackpots[t] or Slots.JACKPOT_META[t].seed)
    end
    return table.concat(parts, ",")
end

-- Flush any queued realm-channel sends (only works once we're actually in
-- the channel and, for SendChatMessage, in a hardware-event context).
function Arcade:FlushJackpotChannel()
    local idx = GetChannelName and GetChannelName(JP_CHANNEL)
    if not (idx and idx > 0) or #jpQueue == 0 then return end
    local q = jpQueue
    jpQueue = {}
    for _, m in ipairs(q) do
        BJ:SendToChannel(JP_PREFIX, JP_MARK, m, idx)
    end
end

-- Send to the free legs immediately; queue the realm-channel leg (flushed on
-- the next Slots-window open) unless we can flush it right now.
local function jpBroadcast(msg, flushNow)
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        if IsInGuild and IsInGuild() then C_ChatInfo.SendAddonMessage(JP_PREFIX, msg, "GUILD") end
        if IsInRaid and IsInRaid() then
            C_ChatInfo.SendAddonMessage(JP_PREFIX, msg, "RAID")
        elseif IsInGroup and IsInGroup() then
            C_ChatInfo.SendAddonMessage(JP_PREFIX, msg, "PARTY")
        end
    end
    jpQueue[#jpQueue + 1] = msg
    if flushNow then Arcade:FlushJackpotChannel() end
end

local function jpWhisper(target, msg)
    if target and C_ChatInfo and C_ChatInfo.SendAddonMessage then
        C_ChatInfo.SendAddonMessage(JP_PREFIX, msg, "WHISPER", target)
    end
end

local function jpRefreshDisplay()
    if BJ.UI then
        if BJ.UI.Slots and BJ.UI.Slots.UpdateDisplay then BJ.UI.Slots:UpdateDisplay() end
        if BJ.UI.Reels and BJ.UI.Reels.RefreshAll then BJ.UI.Reels:RefreshAll() end
        if BJ.UI.Slots and BJ.UI.Slots.UpdateJackpotMarquee then BJ.UI.Slots:UpdateJackpotMarquee() end
    end
end

-- Adopt a peer's pots ONCE (max per tier so the community pot never drops).
local function jpAdoptPots(str)
    if jpSynced then return end
    local db = Arcade:GetDB()
    Slots:AccrueJackpots()
    local vals = { strsplit(",", str or "") }
    local changed = false
    for i, t in ipairs(JP_TIERS) do
        local v = tonumber(vals[i])
        if v and v > (db.jackpots[t] or 0) then db.jackpots[t] = v; changed = true end
    end
    db.jackpotLastTick = time()
    if changed then jpRefreshDisplay() end
end

-- Reseed one tier everywhere a HIT is heard.
local function jpApplyHit(tier)
    local meta = Slots.JACKPOT_META[tier]
    if not meta then return end
    Slots:AccrueJackpots()
    Arcade:GetDB().jackpots[tier] = meta.seed
    jpRefreshDisplay()
end

local function jpHandle(msg, sender)
    if type(msg) ~= "string" then return end
    local short = sender and (sender:match("^([^-]+)") or sender)
    if short == BJ:MyName() then return end
    local cmd, rest = msg:match("^([^|]+)|?(.*)$")
    if cmd == "REQ" then
        jpWhisper(sender, "POTS|" .. jpPotsString())
    elseif cmd == "POTS" then
        jpAdoptPots(rest)
    elseif cmd == "HIT" then
        jpApplyHit(rest)
    end
end

do
    local rx = CreateFrame("Frame")
    rx:RegisterEvent("CHAT_MSG_ADDON")
    rx:SetScript("OnEvent", function(_, _, prefix, msg, _, sender)
        if prefix ~= JP_PREFIX then return end
        jpHandle(msg, sender)
    end)
    local crx = CreateFrame("Frame")
    crx:RegisterEvent("CHAT_MSG_CHANNEL")
    crx:SetScript("OnEvent", function(_, _, text, sender, _, _, _, _, _, _, chanName)
        -- The channel first: General and Trade are dropped before their text
        -- is touched. That text can be a secret string on Forever, which
        -- passes type() == "string" and then throws when read.
        chanName = BJ:Readable(chanName)
        if not (chanName and chanName:lower():find(JP_CHANNEL:lower(), 1, true)) then return end
        text, sender = BJ:Readable(text), BJ:Readable(sender)
        if not (text and sender) or text:sub(1, #JP_MARK) ~= JP_MARK then return end
        jpHandle((text:sub(#JP_MARK + 1):gsub("~", "|")), sender)
    end)
end

-- Called when the Slots window opens (a hardware context): flush any queued
-- channel sends, and the very first time, pull a shared baseline then lock.
function Arcade:SyncJackpotsOnLook()
    self:FlushJackpotChannel()
    if jpReqSent then return end
    jpReqSent = true
    jpBroadcast("REQ", true)              -- guild/group now, channel now if we can
    C_Timer.After(6, function() jpSynced = true end)
end

-- Announce that a tier was just claimed so all clients reseed it.
function Arcade:BroadcastJackpotHit(tier)
    if not (tier and Slots.JACKPOT_META[tier]) then return end
    jpBroadcast("HIT|" .. tier, true)
end

-- The nine paylines as ordered {reel,row} cell lists. Reels 1..5, rows 1(top)
-- ..5(bottom). Table order IS the activation order: middle first, then the
-- rows working outward, the two diagonals, then the V / ^ zig-zags.
Slots.LINES = {}
do
    local defs = {
        { name = "Middle (row 3)", tag = "3",  rows = { 3, 3, 3, 3, 3 } },
        { name = "Row 2",          tag = "2",  rows = { 2, 2, 2, 2, 2 } },
        { name = "Row 4",          tag = "4",  rows = { 4, 4, 4, 4, 4 } },
        { name = "Top (row 1)",    tag = "1",  rows = { 1, 1, 1, 1, 1 } },
        { name = "Bottom (row 5)", tag = "5",  rows = { 5, 5, 5, 5, 5 } },
        { name = "Slash /",        tag = "/",  rows = { 5, 4, 3, 2, 1 } },
        { name = "Backslash \\",   tag = "\\", rows = { 1, 2, 3, 4, 5 } },
        { name = "Top V",          tag = "V",  rows = { 1, 3, 5, 3, 1 } },
        { name = "Bottom ^",       tag = "^",  rows = { 5, 3, 1, 3, 5 } },
    }
    for i, d in ipairs(defs) do
        local cells = {}
        for reel = 1, Slots.REELS do
            cells[reel] = { reel = reel, row = d.rows[reel] }
        end
        Slots.LINES[i] = { index = i, name = d.name, tag = d.tag, cells = cells }
    end
end

-- Build the reel strip (each symbol repeated by weight), then shuffle it:
-- without the shuffle the weight copies sit adjacent on the strip, and the
-- 5-tall window keeps showing vertical runs of the same icon.
local function buildStrip(weights)
    local strip = {}
    for _, sym in ipairs(Slots.SYMBOLS) do
        local w = weights and (weights[sym.id] or sym.weight) or sym.weight
        for _ = 1, w do
            table.insert(strip, sym.id)
        end
    end
    for i = #strip, 2, -1 do
        local j = math.random(i)
        strip[i], strip[j] = strip[j], strip[i]
    end
    return strip
end
Slots.STRIP = buildStrip(nil)

-- The free-spins strip: a plainly better hit rate - high and mid symbols are
-- denser and the junk thins out. Tokens stay at the base rate so retriggers
-- (4+ tokens on a free spin = extra spins) are an uncommon treat, not a
-- perpetual-motion machine.
Slots.BONUS_WEIGHTS = {
    token = 1, wild = 2, skull = 3, gold = 4, ruby = 5, emerald = 5,
    sapphire = 5, die = 4, shroom = 5, melon = 5, apple = 5,
    silver = 3, copper = 2,
}
Slots.BONUS_STRIP = buildStrip(Slots.BONUS_WEIGHTS)
Slots.FREESPIN_RETRIGGER = 4   -- tokens in view on a free spin ...
Slots.FREESPIN_EXTRA = 3       -- ... award this many extra spins

-- GEM RUSH: 1 in 11 paid pulls rolls on a rich strip with everything below
-- the gems stripped out. No tokens on the strip, so a rush can never
-- combine with the coin bonuses - it's pure line pay. A rush always pays
-- (Spin re-rolls one that would not), about 4x the total bet on average: a
-- frequent, reliable lift rather than a rare lottery. No wilds on the rush
-- strip: they made it swing from nothing to hundreds of times the bet.
Slots.RICH_CHANCE = 1 / 11
Slots.RICH_WEIGHTS = {
    token = 0, wild = 0, skull = 3, gold = 3, ruby = 3, emerald = 3,
    sapphire = 3, die = 0, shroom = 0, melon = 0, apple = 0,
    silver = 0, copper = 0,
}
Slots.RICH_STRIP = buildStrip(Slots.RICH_WEIGHTS)

Slots.MAX_BET   = 100000   -- per line (high rollers welcome)
Slots.MAX_LINES = #Slots.LINES

function Slots:IconFor(id)
    for _, sym in ipairs(self.SYMBOLS) do
        if sym.id == id then return sym.icon end
    end
end

-- The five symbols on a payline -> pay multiplier, match count, symbol id.
-- Wins are 3+ identical from the leftmost reel; the token never line-pays.
-- WILDs substitute for any paying symbol (leading wilds adopt the first real
-- symbol, and a pure wild run has its own top-shelf pay). Best pay wins.
function Slots:EvaluateLine(syms)
    local first = syms[1]
    if not first or first == "token" then return 0 end

    local best, bestCount, bestSym = 0, nil, nil

    -- pure wild run from the left
    local wildRun = 0
    for i = 1, #syms do
        if syms[i] == "wild" then wildRun = wildRun + 1 else break end
    end
    local wtab = self.LINE_PAY.wild
    if wtab and wtab[wildRun] then
        best, bestCount, bestSym = wtab[wildRun], wildRun, "wild"
    end

    -- first real (non-wild) symbol anchors the line; wilds fill in for it
    local target
    for i = 1, #syms do
        if syms[i] ~= "wild" then target = syms[i] break end
    end

    if target and target ~= "token" then
        local count = 0
        for i = 1, #syms do
            if syms[i] == target or syms[i] == "wild" then count = count + 1 else break end
        end
        local tab = self.LINE_PAY[target]
        if tab and tab[count] and tab[count] > best then
            best, bestCount, bestSym = tab[count], count, target
        end

    end

    if best > 0 then return best, bestCount, bestSym end
    return 0
end

-- Random per-reel stops (used by spins and free spins). Pass a strip to roll
-- against something other than the base game's (e.g. BONUS_STRIP).
function Slots:RollStops(strip)
    local n = #(strip or self.STRIP)
    local stops = {}
    for reel = 1, self.REELS do stops[reel] = math.random(n) end
    return stops
end

-- Evaluate every active line on a grid (no spend/award). Returns wins list and
-- total pay. Used by the paid Spin and by free spins.
function Slots:EvaluateGrid(grid, betPerLine, activeLines)
    local wins, total = {}, 0
    for li = 1, activeLines do
        local ln = self.LINES[li]
        local syms = {}
        for i, cell in ipairs(ln.cells) do syms[i] = grid[cell.reel][cell.row] end
        local mult, count, sym = self:EvaluateLine(syms)
        if mult and mult > 0 then
            local pay = mult * betPerLine
            total = total + pay
            wins[#wins + 1] = { line = li, name = ln.name, count = count, sym = sym,
                                pay = pay, cells = ln.cells }
        end
    end
    return wins, total
end

-- Count distinct tokens sitting on active lines (bonus trigger = 3+).
function Slots:CountTokens(grid, activeLines)
    local seen, cells = {}, {}
    for li = 1, activeLines do
        for _, cell in ipairs(self.LINES[li].cells) do
            local key = cell.reel .. ":" .. cell.row
            if not seen[key] and grid[cell.reel][cell.row] == "token" then
                seen[key] = true
                cells[#cells + 1] = cell
            end
        end
    end
    return cells
end

-- Build the visible 5x5 grid from a per-reel stop (top row = strip[stop]).
function Slots:GridFromStops(stops, strip)
    strip = strip or self.STRIP
    local n = #strip
    local grid = {}
    for reel = 1, self.REELS do
        grid[reel] = {}
        for row = 1, self.ROWS do
            grid[reel][row] = strip[((stops[reel] + row - 2) % n) + 1]
        end
    end
    return grid
end

-- Spin: wager (betPerLine x activeLines), land the reels, settle. Returns nil,
-- err if the wager can't be covered.
function Slots:Spin(betPerLine, activeLines)
    betPerLine = math.floor(tonumber(betPerLine) or 1)
    if betPerLine < 1 then betPerLine = 1 end
    if betPerLine > self.MAX_BET then betPerLine = self.MAX_BET end
    activeLines = math.floor(tonumber(activeLines) or 1)
    if activeLines < 1 then activeLines = 1 end
    if activeLines > self.MAX_LINES then activeLines = self.MAX_LINES end

    local totalBet = betPerLine * activeLines
    if not Arcade:Spend(totalBet) then
        return nil, "Not enough credits"
    end

    -- GEM RUSH pull? (never while the test rig is forcing an outcome)
    local rich = (not self.forceNext) and (math.random() < self.RICH_CHANCE)
    local strip = rich and self.RICH_STRIP or nil
    if rich then
        -- lifetime tally, shown in the rush banner: proves the trigger
        -- is rolling on this client (the odds are sim-verified 1 in 20)
        local db = Arcade:GetDB()
        db.rushCount = (db.rushCount or 0) + 1
    end

    local stops = self:RollStops(strip)
    local grid = self:GridFromStops(stops, strip)
    if rich then
        -- A Gem Rush always pays something: a grid that pays nothing on the
        -- active lines is rolled again (a hundred misses in a row is
        -- vanishingly unlikely, even on one line).
        for _ = 1, 100 do
            local _, pay = self:EvaluateGrid(grid, betPerLine, activeLines)
            if pay > 0 then break end
            stops = self:RollStops(strip)
            grid = self:GridFromStops(stops, strip)
        end
    end

    -- Debug rig (set by /cc test slots ... while test mode is on): overwrite
    -- cells so a specific outcome can be tested. One-shot; cleared on use.
    if self.forceNext then
        local spec = self.forceNext
        self.forceNext = nil
        if spec.kind == "bonus" or spec.kind == "fireshot" then
            -- clear stray tokens first so the coin count is exact
            for reel = 1, self.REELS do
                for row = 1, self.ROWS do
                    if grid[reel][row] == "token" then grid[reel][row] = "gold" end
                end
            end
            if spec.kind == "bonus" then
                -- exactly three coins spread along the middle row
                local cells = self.LINES[1].cells
                for _, i in ipairs({ 1, 3, 5 }) do
                    grid[cells[i].reel][cells[i].row] = "token"
                end
            else
                -- five coins scattered around the view -> HOLD & SPIN
                grid[1][1] = "token"; grid[2][3] = "token"; grid[3][5] = "token"
                grid[4][2] = "token"; grid[5][4] = "token"
            end
        elseif spec.kind == "line" then
            local ln = self.LINES[math.min(spec.line or 1, activeLines)] or self.LINES[1]
            for i = 1, math.min(spec.count or 3, self.REELS) do
                grid[ln.cells[i].reel][ln.cells[i].row] = spec.sym
            end
            -- make sure the run stops where asked (break a longer accident)
            local nxt = ln.cells[(spec.count or 3) + 1]
            if nxt and grid[nxt.reel][nxt.row] == spec.sym then
                grid[nxt.reel][nxt.row] = (spec.sym == "dice" or spec.sym == "gold") and "ruby" or "gold"
            end
        end
    end

    local wins, totalPay = self:EvaluateGrid(grid, betPerLine, activeLines)

    -- Feed every progressive pot with its slice of the wager.
    self:FeedJackpots(totalBet)

    -- Every token in view is a coin with a rolled value. Exactly 3 -> side
    -- bonus; FIRESHOT_TRIGGER or more -> hold & spin.
    local coins, tokenCells, coinCount = {}, {}, 0
    for reel = 1, self.REELS do
        for row = 1, self.ROWS do
            if grid[reel][row] == "token" then
                coins[reel .. ":" .. row] = self:RollCoin(totalBet)
                tokenCells[#tokenCells + 1] = { reel = reel, row = row }
                coinCount = coinCount + 1
            end
        end
    end
    local fireshot = (coinCount >= self.FIRESHOT_TRIGGER)
    local bonus = (not fireshot) and (coinCount == self.SIDE_BONUS_COINS)

    -- NOTE: the line pay is NOT awarded here - the UI settles it via
    -- SettleSpin once the reels have visibly stopped, so the balance never
    -- leaks the result early.
    return {
        stops = stops,          -- per-reel strip index (UI scrolls to these)
        grid = grid,            -- grid[reel][row] symbol ids
        wins = wins,            -- winning active lines (for highlight)
        payout = totalPay,
        settled = false,
        coins = coins,          -- coins["reel:row"] = { value = n [, jackpot = tier] }
        coinCount = coinCount,
        fireshot = fireshot,    -- 4+ coins -> hold & spin
        bonus = bonus,          -- exactly 3 coins -> chest/wheel/free spins
        rich = rich,            -- GEM RUSH pull (high symbols only, no coins)
        tokenCells = tokenCells,
        betPerLine = betPerLine,
        activeLines = activeLines,
        totalBet = totalBet,
    }
end

-- Pay the spin line wins into the balance. Called by the UI when the last
-- reel locks; guarded so a result can only ever settle once.
function Slots:SettleSpin(result)
    if not result or result.settled then return end
    result.settled = true
    if (result.payout or 0) > 0 then
        Arcade:Award(result.payout)
        local db = Arcade:GetDB()
        if result.payout > (db.bestSlotsWin or 0) then db.bestSlotsWin = result.payout end
    end
end

--[[
    HOLD & SPIN state machine. The UI drives the pacing; the engine owns the
    randomness and the money.
]]

-- The round is fought across the whole 5x5 view: every cell is arena, so
-- triggering coins lock exactly where they landed.
function Slots:FireshotStart(coins, totalBet)
    local arenaKeys = {}
    local isArena = {}
    for reel = 1, self.REELS do
        for _, row in ipairs(self.FIRESHOT_ROWS) do
            local key = reel .. ":" .. row
            isArena[key] = true
            arenaKeys[#arenaKeys + 1] = key
        end
    end

    local locked, count = {}, 0
    for key, coin in pairs(coins) do
        locked[key] = coin
        count = count + 1
    end

    return {
        locked = locked, count = count, respins = 3,
        totalBet = totalBet, arenaKeys = arenaKeys, isArena = isArena,
        done = false,
    }
end

-- One respin: every empty ARENA cell has a chance to land a fresh coin. Any
-- new coin resets the respins to 3; none burns one. Returns the new coins.
function Slots:FireshotRespin(state)
    local newCoins = {}
    for _, key in ipairs(state.arenaKeys) do
        if not state.locked[key] and math.random() < self.FIRESHOT_COIN_CHANCE then
            local coin = self:RollCoin(state.totalBet)
            state.locked[key] = coin
            newCoins[key] = coin
            state.count = state.count + 1
        end
    end
    if next(newCoins) then
        state.respins = 3
    else
        state.respins = state.respins - 1
    end
    if state.respins <= 0 or state.count >= self.GRAND_FILL then
        state.done = true
    end
    return newCoins
end

-- Pay out every locked coin; GRAND only at GRAND_FILL+ locked positions (the
-- pot resets to seed). Returns total, grand amount (or nil), and a per-tier
-- jackpot-coin tally so the UI can call out which jackpots hit.
function Slots:FireshotSettle(state)
    local total = 0
    local jackpots = { mini = 0, minor = 0, major = 0, mega = 0 }
    for _, coin in pairs(state.locked) do
        if coin.jackpot then
            -- the coin claims its pot (which then reseeds; a second coin of
            -- the same tier collects the freshly seeded pot or the floor)
            local amt = self:ClaimJackpot(coin.jackpot, state.totalBet)
            coin.value = amt
            total = total + amt
            jackpots[coin.jackpot] = (jackpots[coin.jackpot] or 0) + 1
        else
            total = total + (coin.value or 0)
        end
    end
    local db = Arcade:GetDB()
    local grand = nil
    if state.count >= self.GRAND_FILL then
        grand = self:ClaimJackpot("grand", state.totalBet)
        total = total + grand
    end
    if total > 0 then
        Arcade:Award(total)
        if total > (db.bestSlotsWin or 0) then db.bestSlotsWin = total end
    end
    return total, grand, jackpots
end

--[[
    VIDEO KENO
    Pick 1-10 numbers from 1-80, the machine draws 20, matches pay by how
    many you picked (classic video-keno ladder, per credit wagered). Lives in
    the video card cabinet as its own tab.
]]

Arcade.Keno = {}
local Keno = Arcade.Keno

Keno.NUMBERS = 80
Keno.DRAWS = 20
Keno.MAX_PICKS = 20
Keno.MAX_BET = 100000

-- PAY[picks][matches] = multiplier (x bet). 0-match consolation on big cards.
Keno.PAY = {
    [1]  = { [1] = 3 },
    [2]  = { [2] = 15 },
    [3]  = { [2] = 2,  [3] = 45 },
    [4]  = { [2] = 1,  [3] = 5,  [4] = 90 },
    [5]  = { [3] = 3,  [4] = 15, [5] = 250 },
    [6]  = { [3] = 2,  [4] = 8,  [5] = 60,  [6] = 1000 },
    [7]  = { [4] = 3,  [5] = 25, [6] = 120, [7] = 2500 },
    [8]  = { [5] = 15, [6] = 80, [7] = 500, [8] = 5000 },
    [9]  = { [5] = 8,  [6] = 40, [7] = 200, [8] = 2000, [9] = 7500 },
    [10] = { [0] = 2,  [5] = 5,  [6] = 25,  [7] = 100,  [8] = 500, [9] = 2500, [10] = 10000 },
    [11] = { [0] = 2,  [5] = 1,  [6] = 10,  [7] = 50,   [8] = 250, [9] = 1000, [10] = 5000,  [11] = 25000 },
    [12] = { [0] = 2,  [6] = 5,  [7] = 25,  [8] = 150,  [9] = 600, [10] = 2500, [11] = 10000, [12] = 50000 },
    [13] = { [0] = 2,  [6] = 4,  [7] = 15,  [8] = 80,   [9] = 300, [10] = 1500, [11] = 5000,  [12] = 25000, [13] = 75000 },
    [14] = { [0] = 2,  [6] = 2,  [7] = 10,  [8] = 40,   [9] = 200, [10] = 750,  [11] = 2500,  [12] = 10000, [13] = 50000, [14] = 100000 },
    [15] = { [0] = 2,  [6] = 1,  [7] = 7,   [8] = 25,   [9] = 100, [10] = 350,  [11] = 1500,  [12] = 5000,  [13] = 20000, [14] = 50000, [15] = 100000 },
    [16] = { [0] = 2,  [7] = 5,  [8] = 15,  [9] = 60,   [10] = 200, [11] = 750, [12] = 2500,  [13] = 10000, [14] = 25000, [15] = 75000, [16] = 100000 },
    [17] = { [0] = 2,  [7] = 3,  [8] = 10,  [9] = 40,   [10] = 150, [11] = 500, [12] = 1500,  [13] = 5000,  [14] = 15000, [15] = 50000, [16] = 75000, [17] = 100000 },
    [18] = { [0] = 2,  [7] = 2,  [8] = 8,   [9] = 25,   [10] = 100, [11] = 300, [12] = 1000,  [13] = 2500,  [14] = 7500,  [15] = 25000, [16] = 50000, [17] = 75000, [18] = 100000 },
    [19] = { [0] = 2,  [8] = 5,  [9] = 20,  [10] = 75,  [11] = 250, [12] = 750, [13] = 2000,  [14] = 5000,  [15] = 15000, [16] = 35000, [17] = 60000, [18] = 80000, [19] = 100000 },
    [20] = { [0] = 3,  [8] = 4,  [9] = 15,  [10] = 50,  [11] = 150, [12] = 500, [13] = 1500,  [14] = 4000,  [15] = 10000, [16] = 25000, [17] = 50000, [18] = 75000, [19] = 90000, [20] = 100000 },
}

-- Buy a card up front (PLAY button): the bet is charged now, the draw comes
-- later once the player has picked their spots.
function Keno:BuyCard(bet)
    bet = math.floor(tonumber(bet) or 1)
    if bet < 1 then bet = 1 end
    if bet > self.MAX_BET then bet = self.MAX_BET end
    if not Arcade:Spend(bet) then return nil, "Not enough credits" end
    return bet
end

-- Run the draw for an already-paid card: draw 20, settle. picks is an array
-- of distinct numbers 1..80. Returns nil, err if the card cannot run.
function Keno:Play(picks, bet)
    bet = math.floor(tonumber(bet) or 1)
    if bet < 1 then bet = 1 end
    if not picks or #picks < 1 then return nil, "Pick at least one number" end
    if #picks > self.MAX_PICKS then return nil, "Too many picks" end

    -- draw 20 distinct numbers (partial Fisher-Yates)
    local pool = {}
    for n = 1, self.NUMBERS do pool[n] = n end
    local drawn, drawnSet = {}, {}
    for i = 1, self.DRAWS do
        local j = math.random(i, self.NUMBERS)
        pool[i], pool[j] = pool[j], pool[i]
        drawn[i] = pool[i]
        drawnSet[pool[i]] = true
    end

    local matches = 0
    for _, n in ipairs(picks) do
        if drawnSet[n] then matches = matches + 1 end
    end

    local ladder = self.PAY[#picks] or {}
    local payout = (ladder[matches] or 0) * bet
    if payout > 0 then
        Arcade:Award(payout)
        local db = Arcade:GetDB()
        if payout > (db.bestKenoWin or 0) then db.bestKenoWin = payout end
    end

    return {
        drawn = drawn,          -- draw order (UI reveals at a cadence)
        drawnSet = drawnSet,
        matches = matches,
        picks = #picks,
        payout = payout,
        bet = bet,
    }
end

--[[
    SLOTS BONUS MINI-GAMES
    Triggered by 3+ tokens on active lines; the type is picked at random.
    Prizes scale off the triggering total bet. Logic here; the reveal/animation
    lives in the UI, which awards the returned credits.
]]
Arcade.Bonus = {}
local Bonus = Arcade.Bonus

Bonus.TYPES = { "chest", "wheel", "freespins" }

function Bonus:RandomType()
    return self.TYPES[math.random(#self.TYPES)]
end

-- Loot chests: pick one of several hidden credit prizes (multiples of stake).
function Bonus:MakeChests(stake)
    stake = math.max(1, math.floor(stake or 1))
    local mults = { 3, 5, 8, 10, 12, 15, 30 }
    -- shuffle and take three
    for i = #mults, 2, -1 do
        local j = math.random(i)
        mults[i], mults[j] = mults[j], mults[i]
    end
    local chests = {}
    for i = 1, 3 do chests[i] = stake * mults[i] end
    return chests   -- credit values; UI reveals the picked one and Awards it
end

-- Bonus wheel: weighted wedges (credits), one jackpot.
function Bonus:MakeWheel(stake)
    stake = math.max(1, math.floor(stake or 1))
    return {
        stake * 3, stake * 15, stake * 5, stake * 8,
        stake * 30, stake * 4, stake * 10, stake * 6,
    }   -- UI spins and lands on an index, then Awards it
end

-- Free spins: a count and a global win multiplier.
function Bonus:MakeFreeSpins()
    local count = ({ 5, 7, 9 })[math.random(3)]
    local mult  = ({ 2, 3 })[math.random(2)]
    return count, mult
end

--[[
    VIDEO POKER - Jacks or Better
    Classic 9/6-style paytable, per credit wagered. A max (5 credit) bet
    upgrades the royal flush to the 800x jackpot, exactly like the old
    handhelds wanted you to play.
]]

Arcade.Poker = {}
local Poker = Arcade.Poker

Poker.RANKS = { "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A" }
Poker.SUITS = { "spades", "hearts", "diamonds", "clubs" }
Poker.RANK_VALUE = {}
for i, r in ipairs(Poker.RANKS) do Poker.RANK_VALUE[r] = i + 1 end  -- 2..14

Poker.MAX_BET = 100000
Poker.ROYAL_MIN_BET = 5     -- betting this or more upgrades the top royal
Poker.ROYAL_MAX_PAY = 800   -- per credit, at ROYAL_MIN_BET or higher

-- =====================================================================
-- Variations. Each has its own paytable (best first, per-credit pay), the
-- key of its top royal (which gets the max-bet bonus), and the name of the
-- evaluate method that maps a 5-card hand to a paytable key. The player
-- swaps variations inside the video-poker UI; the choice persists per
-- character in db.arcade.pokerVariation.
-- =====================================================================
Poker.VARIATIONS = {
    {
        id = "jacks", name = "Jacks or Better", eval = "EvalJacks",
        royalKey = "royal", royalMaxPay = 800,
        paytable = {
            { key = "royal",    name = "Royal Flush",     pay = 250 },  -- 800 at max bet
            { key = "sflush",   name = "Straight Flush",  pay = 50 },
            { key = "quads",    name = "Four of a Kind",  pay = 25 },
            { key = "fullhouse",name = "Full House",      pay = 9 },
            { key = "flush",    name = "Flush",           pay = 6 },
            { key = "straight", name = "Straight",        pay = 4 },
            { key = "trips",    name = "Three of a Kind", pay = 3 },
            { key = "twopair",  name = "Two Pair",        pay = 2 },
            { key = "jacks",    name = "Jacks or Better", pay = 1 },
        },
    },
    {
        id = "bonus", name = "Bonus Poker", eval = "EvalBonus",
        royalKey = "royal", royalMaxPay = 800,
        paytable = {
            { key = "royal",     name = "Royal Flush",    pay = 250 },  -- 800 at max bet
            { key = "sflush",    name = "Straight Flush", pay = 50 },
            { key = "quad_aces", name = "Four Aces",      pay = 80 },
            { key = "quad_234",  name = "Four 2s-4s",     pay = 40 },
            { key = "quad_5K",   name = "Four 5s-Ks",     pay = 25 },
            { key = "fullhouse", name = "Full House",     pay = 8 },
            { key = "flush",     name = "Flush",          pay = 5 },
            { key = "straight",  name = "Straight",       pay = 4 },
            { key = "trips",     name = "Three of a Kind",pay = 3 },
            { key = "twopair",   name = "Two Pair",       pay = 2 },
            { key = "jacks",     name = "Jacks or Better",pay = 1 },
        },
    },
    {
        id = "ddbonus", name = "Double Double Bonus", eval = "EvalDDB",
        royalKey = "royal", royalMaxPay = 800,
        -- generous 10/6 pay schedule; the kicker on premium quads doubles them
        paytable = {
            { key = "royal",       name = "Royal Flush",      pay = 250 },  -- 800 at max bet
            { key = "quad_aces_k", name = "Four Aces + 2-4",  pay = 400 },
            { key = "quad_234_k",  name = "Four 2s-4s + A-4", pay = 160 },
            { key = "quad_aces",   name = "Four Aces",        pay = 160 },
            { key = "quad_234",    name = "Four 2s-4s",       pay = 80 },
            { key = "quad_5K",     name = "Four 5s-Ks",       pay = 50 },
            { key = "sflush",      name = "Straight Flush",   pay = 50 },
            { key = "fullhouse",   name = "Full House",       pay = 10 },
            { key = "flush",       name = "Flush",            pay = 6 },
            { key = "straight",    name = "Straight",         pay = 4 },
            { key = "trips",       name = "Three of a Kind",  pay = 3 },
            { key = "twopair",     name = "Two Pair",         pay = 1 },
            { key = "jacks",       name = "Jacks or Better",  pay = 1 },
        },
    },
    {
        id = "deuces", name = "Deuces Wild", eval = "EvalDeuces",
        royalKey = "natroyal", royalMaxPay = 800,
        paytable = {
            { key = "natroyal",   name = "Royal Flush",      pay = 250 },  -- 800 at max bet
            { key = "fourdeuces", name = "Four Deuces",      pay = 200 },
            { key = "wildroyal",  name = "Wild Royal Flush", pay = 25 },
            { key = "fivekind",   name = "Five of a Kind",   pay = 15 },
            { key = "sflush",     name = "Straight Flush",   pay = 9 },
            { key = "quads",      name = "Four of a Kind",   pay = 5 },
            { key = "fullhouse",  name = "Full House",       pay = 3 },
            { key = "flush",      name = "Flush",            pay = 2 },
            { key = "straight",   name = "Straight",         pay = 2 },
            { key = "trips",      name = "Three of a Kind",  pay = 1 },
        },
    },
}

function Poker:GetVariationId()
    return Arcade:GetDB().pokerVariation or "jacks"
end

function Poker:SetVariationId(id)
    Arcade:GetDB().pokerVariation = id
end

function Poker:CurrentVariation()
    local id = self:GetVariationId()
    for _, v in ipairs(self.VARIATIONS) do
        if v.id == id then return v end
    end
    return self.VARIATIONS[1]
end

-- Advance to the next variation (wraps). Returns the new descriptor.
function Poker:CycleVariation()
    local id = self:GetVariationId()
    local idx = 1
    for i, v in ipairs(self.VARIATIONS) do
        if v.id == id then idx = i break end
    end
    local nxt = self.VARIATIONS[(idx % #self.VARIATIONS) + 1]
    self:SetVariationId(nxt.id)
    return nxt
end

-- Kept for compatibility: the current variation's display paytable.
function Poker:GetPaytable()
    return self:CurrentVariation().paytable
end

-- =====================================================================
-- Multi-hand ("Triple Play" / "Five Play"). One base hand is dealt and
-- held; every hand then draws its replacements from its OWN independent
-- deck (a fresh 52 minus the five dealt cards), exactly like the real
-- cabinets. The bet is per hand, so a Triple Play deal costs 3x.
-- =====================================================================
Poker.HAND_COUNTS = { 1, 3, 5 }

function Poker:GetHandCount()
    local n = Arcade:GetDB().pokerHands or 1
    for _, v in ipairs(self.HAND_COUNTS) do
        if v == n then return n end
    end
    return 1
end

function Poker:SetHandCount(n)
    Arcade:GetDB().pokerHands = n
end

-- Advance 1 -> 3 -> 5 -> 1. Returns the new count.
function Poker:CycleHandCount()
    local cur = self:GetHandCount()
    local idx = 1
    for i, v in ipairs(self.HAND_COUNTS) do
        if v == cur then idx = i break end
    end
    local nxt = self.HAND_COUNTS[(idx % #self.HAND_COUNTS) + 1]
    self:SetHandCount(nxt)
    return nxt
end

-- Fresh shuffled 52-card deck: { {rank="A", suit="spades"}, ... }
function Poker:NewDeck()
    local deck = {}
    for _, suit in ipairs(self.SUITS) do
        for _, rank in ipairs(self.RANKS) do
            table.insert(deck, { rank = rank, suit = suit })
        end
    end
    for i = #deck, 2, -1 do
        local j = math.random(i)
        deck[i], deck[j] = deck[j], deck[i]
    end
    return deck
end

-- Shared analysis of a 5-card hand with no wild cards.
function Poker:HandShape(hand)
    local counts, suits, values = {}, {}, {}
    for _, card in ipairs(hand) do
        local v = self.RANK_VALUE[card.rank]
        values[#values + 1] = v
        counts[v] = (counts[v] or 0) + 1
        suits[card.suit] = (suits[card.suit] or 0) + 1
    end
    table.sort(values)

    local isFlush = false
    for _, n in pairs(suits) do if n == 5 then isFlush = true end end

    local isStraight = true
    for i = 2, 5 do
        if values[i] ~= values[i - 1] + 1 then isStraight = false break end
    end
    if not isStraight and values[1] == 2 and values[2] == 3 and values[3] == 4
        and values[4] == 5 and values[5] == 14 then
        isStraight = true  -- the wheel A-2-3-4-5
    end

    local pairsN, trips, quads, highPair, quadVal = 0, false, false, false, nil
    for v, n in pairs(counts) do
        if n == 4 then quads = true; quadVal = v
        elseif n == 3 then trips = true
        elseif n == 2 then
            pairsN = pairsN + 1
            if v >= 11 then highPair = true end  -- J, Q, K, A
        end
    end

    return {
        values = values, isFlush = isFlush, isStraight = isStraight,
        pairsN = pairsN, trips = trips, quads = quads,
        highPair = highPair, quadVal = quadVal,
    }
end

-- Jacks or Better: classic categories.
function Poker:EvalJacks(hand)
    local s = self:HandShape(hand)
    if s.isStraight and s.isFlush then
        if s.values[1] == 10 then return "royal", "ROYAL FLUSH!" end
        return "sflush", "Straight Flush!"
    end
    if s.quads then return "quads", "Four of a Kind!" end
    if s.trips and s.pairsN == 1 then return "fullhouse", "Full House!" end
    if s.isFlush then return "flush", "Flush!" end
    if s.isStraight then return "straight", "Straight!" end
    if s.trips then return "trips", "Three of a Kind!" end
    if s.pairsN == 2 then return "twopair", "Two Pair!" end
    if s.pairsN == 1 and s.highPair then return "jacks", "Jacks or Better!" end
    return nil, ""
end

-- Bonus Poker: like Jacks, but four-of-a-kind pays split by the quad rank.
function Poker:EvalBonus(hand)
    local s = self:HandShape(hand)
    if s.isStraight and s.isFlush then
        if s.values[1] == 10 then return "royal", "ROYAL FLUSH!" end
        return "sflush", "Straight Flush!"
    end
    if s.quads then
        if s.quadVal == 14 then return "quad_aces", "Four Aces!"
        elseif s.quadVal >= 2 and s.quadVal <= 4 then return "quad_234", "Four of a Kind!"
        else return "quad_5K", "Four of a Kind!" end
    end
    if s.trips and s.pairsN == 1 then return "fullhouse", "Full House!" end
    if s.isFlush then return "flush", "Flush!" end
    if s.isStraight then return "straight", "Straight!" end
    if s.trips then return "trips", "Three of a Kind!" end
    if s.pairsN == 2 then return "twopair", "Two Pair!" end
    if s.pairsN == 1 and s.highPair then return "jacks", "Jacks or Better!" end
    return nil, ""
end

-- Double Double Bonus: Bonus Poker with a second double - the fifth-card
-- kicker upgrades premium quads (aces with a 2-4 kicker, low quads with an
-- ace-to-4 kicker). Two pair drops to even money to pay for it.
function Poker:EvalDDB(hand)
    local s = self:HandShape(hand)
    if s.isStraight and s.isFlush then
        if s.values[1] == 10 then return "royal", "ROYAL FLUSH!" end
        return "sflush", "Straight Flush!"
    end
    if s.quads then
        -- values is sorted, so the kicker sits at one end of the quad run
        local kicker = (s.values[1] == s.quadVal) and s.values[5] or s.values[1]
        if s.quadVal == 14 then
            if kicker >= 2 and kicker <= 4 then return "quad_aces_k", "FOUR ACES + KICKER!" end
            return "quad_aces", "Four Aces!"
        elseif s.quadVal >= 2 and s.quadVal <= 4 then
            if kicker == 14 or (kicker >= 2 and kicker <= 4) then
                return "quad_234_k", "Four of a Kind + Kicker!"
            end
            return "quad_234", "Four of a Kind!"
        end
        return "quad_5K", "Four of a Kind!"
    end
    if s.trips and s.pairsN == 1 then return "fullhouse", "Full House!" end
    if s.isFlush then return "flush", "Flush!" end
    if s.isStraight then return "straight", "Straight!" end
    if s.trips then return "trips", "Three of a Kind!" end
    if s.pairsN == 2 then return "twopair", "Two Pair!" end
    if s.pairsN == 1 and s.highPair then return "jacks", "Jacks or Better!" end
    return nil, ""
end

-- Deuces Wild: every 2 is a wild card. Minimum paying hand is three of a
-- kind; pairs and two pair pay nothing. We reason about what the wilds can
-- become rather than brute-forcing every assignment.
function Poker:EvalDeuces(hand)
    local wild, nats = 0, {}
    for _, c in ipairs(hand) do
        if c.rank == "2" then wild = wild + 1 else nats[#nats + 1] = c end
    end

    local rankCount, suitCount, vals = {}, {}, {}
    for _, c in ipairs(nats) do
        local v = self.RANK_VALUE[c.rank]
        rankCount[v] = (rankCount[v] or 0) + 1
        suitCount[c.suit] = (suitCount[c.suit] or 0) + 1
        vals[#vals + 1] = v
    end
    table.sort(vals)

    local maxRank, distinctRanks, pairs2, trips3 = 0, 0, 0, 0
    for _, n in pairs(rankCount) do
        distinctRanks = distinctRanks + 1
        if n > maxRank then maxRank = n end
        if n == 2 then pairs2 = pairs2 + 1
        elseif n == 3 then trips3 = trips3 + 1 end
    end
    local distinctSuits = 0
    for _ in pairs(suitCount) do distinctSuits = distinctSuits + 1 end
    local sameSuit = (distinctSuits <= 1)
    local noPairs = (distinctRanks == #nats)   -- naturals all distinct ranks

    local function canStraight()
        if not noPairs then return false end
        if #vals == 0 then return true end
        if vals[#vals] - vals[1] <= 4 then return true end
        if vals[#vals] == 14 then                     -- try Ace low
            local alt = {}
            for _, v in ipairs(vals) do alt[#alt + 1] = (v == 14) and 1 or v end
            table.sort(alt)
            if alt[#alt] - alt[1] <= 4 then return true end
        end
        return false
    end
    local function allRoyalRanks()
        if not noPairs or #vals == 0 then return false end
        for _, v in ipairs(vals) do
            if v < 10 then return false end           -- 10, J, Q, K, A only
        end
        return true
    end

    -- Best-paying category first.
    if wild == 0 and sameSuit and #vals == 5
        and vals[1] == 10 and vals[5] == 14 and canStraight() then
        return "natroyal", "ROYAL FLUSH!"
    end
    if wild == 4 then return "fourdeuces", "FOUR DEUCES!" end
    if sameSuit and allRoyalRanks() then return "wildroyal", "Wild Royal Flush!" end
    if maxRank + wild >= 5 then return "fivekind", "Five of a Kind!" end
    if sameSuit and canStraight() then return "sflush", "Straight Flush!" end
    if maxRank + wild >= 4 then return "quads", "Four of a Kind!" end
    if (wild == 0 and trips3 >= 1 and pairs2 >= 1)
        or (wild == 1 and pairs2 >= 2) then
        return "fullhouse", "Full House!"
    end
    if sameSuit then return "flush", "Flush!" end
    if canStraight() then return "straight", "Straight!" end
    if maxRank + wild >= 3 then return "trips", "Three of a Kind!" end
    return nil, ""
end

-- Evaluate a 5-card hand under the current variation -> key (or nil) + name.
function Poker:Evaluate(hand)
    local v = self:CurrentVariation()
    return self[v.eval](self, hand)
end

-- Per-credit payout for a paytable key at a given bet, under the current
-- variation (the top royal gets the max-bet bonus).
function Poker:PayFor(key, bet)
    if not key then return 0 end
    local v = self:CurrentVariation()
    if key == v.royalKey and bet >= self.ROYAL_MIN_BET then
        return v.royalMaxPay or self.ROYAL_MAX_PAY
    end
    for _, row in ipairs(v.paytable) do
        if row.key == key then return row.pay end
    end
    return 0
end

-- Start a hand: wager bet x hands, deal five. Returns nil, err if broke.
function Poker:Deal(bet)
    bet = math.floor(tonumber(bet) or 1)
    if bet < 1 then bet = 1 end
    if bet > self.MAX_BET then bet = self.MAX_BET end

    local numHands = self:GetHandCount()
    if not Arcade:Spend(bet * numHands) then
        return nil, "Not enough credits"
    end

    local deck = self:NewDeck()
    local hand, dealt = {}, {}
    for i = 1, 5 do
        hand[i] = table.remove(deck)
        dealt[i] = hand[i]
    end
    return { deck = deck, hand = hand, dealt = dealt, bet = bet, numHands = numHands }
end

-- A fresh shuffled deck with the five dealt cards removed - the private
-- draw pile each extra hand replaces from.
function Poker:NewDrawPile(dealt)
    local used = {}
    for _, c in ipairs(dealt) do used[c.rank .. c.suit] = true end
    local pile = {}
    for _, c in ipairs(self:NewDeck()) do
        if not used[c.rank .. c.suit] then pile[#pile + 1] = c end
    end
    return pile
end

-- Replace un-held cards, evaluate, and settle. holds is {bool x5}.
-- Multi-hand: the base hand draws from the deal's own deck; every extra
-- hand starts from the same dealt five and draws from its own pile.
-- Returns the base hand's key/name, the TOTAL payout, and per-extra-hand
-- results in .extras.
function Poker:Draw(game, holds)
    for i = 1, 5 do
        if not holds[i] then
            game.hand[i] = table.remove(game.deck)
        end
    end

    local key, name = self:Evaluate(game.hand)
    local total = self:PayFor(key, game.bet) * game.bet

    local extras = {}
    for h = 2, (game.numHands or 1) do
        local pile = self:NewDrawPile(game.dealt)
        local hand = {}
        for i = 1, 5 do
            if holds[i] then
                hand[i] = game.dealt[i]
            else
                hand[i] = table.remove(pile)
            end
        end
        local k, n = self:Evaluate(hand)
        local pay = self:PayFor(k, game.bet) * game.bet
        total = total + pay
        extras[#extras + 1] = { hand = hand, key = k, name = n, payout = pay }
    end

    if total > 0 then
        Arcade:Award(total)
        local db = Arcade:GetDB()
        if total > (db.bestPokerWin or 0) then db.bestPokerWin = total end
    end

    return { key = key, name = name, payout = total, extras = extras }
end

--[[
    VIDEO BLACKJACK
    Solo blackjack on the same fake-credit balance, played from the video-poker
    cabinet via the game toggle. Dealer stands on all 17s, blackjack pays 3:2,
    double allowed on the first two cards. UI-free logic so it's testable.
]]

Arcade.Blackjack = {}
local Blackjack = Arcade.Blackjack

Blackjack.RANKS = { "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A" }
Blackjack.SUITS = { "spades", "hearts", "diamonds", "clubs" }
Blackjack.MAX_BET = 100000

function Blackjack:NewDeck()
    local deck = {}
    for _, suit in ipairs(self.SUITS) do
        for _, rank in ipairs(self.RANKS) do
            deck[#deck + 1] = { rank = rank, suit = suit }
        end
    end
    for i = #deck, 2, -1 do
        local j = math.random(i)
        deck[i], deck[j] = deck[j], deck[i]
    end
    return deck
end

function Blackjack:CardValue(rank)
    if rank == "A" then return 11 end
    if rank == "K" or rank == "Q" or rank == "J" or rank == "10" then return 10 end
    return tonumber(rank)
end

-- Best total (aces drop from 11 to 1 as needed) plus a "soft" flag.
function Blackjack:HandValue(hand)
    local total, aces = 0, 0
    for _, c in ipairs(hand) do
        total = total + self:CardValue(c.rank)
        if c.rank == "A" then aces = aces + 1 end
    end
    while total > 21 and aces > 0 do
        total = total - 10
        aces = aces - 1
    end
    return total, (aces > 0)   -- soft if an ace is still counted as 11
end

function Blackjack:IsBlackjack(hand)
    return #hand == 2 and (self:HandValue(hand)) == 21
end

Blackjack.MAX_HANDS = 4   -- resplits allowed until you hold four hands

-- Start a round: wager, deal two each. The player side is a LIST of hands so
-- splits (and resplits) just add entries; `active` is the hand being played.
-- Naturals resolve immediately.
function Blackjack:Deal(bet)
    bet = math.floor(tonumber(bet) or 1)
    if bet < 1 then bet = 1 end
    if bet > self.MAX_BET then bet = self.MAX_BET end
    if not Arcade:Spend(bet) then return nil, "Not enough credits" end

    local deck = self:NewDeck()
    local game = {
        deck   = deck,
        dealer = { table.remove(deck), table.remove(deck) },
        hands  = { { cards = { table.remove(deck), table.remove(deck) },
                     bet = bet, done = false, doubled = false, split = false } },
        active = 1,
        over   = false,
        revealDealer = false,
    }

    -- Debug rig (/cc test bj pair): swap the second card for a rank match so
    -- the opening hand is always splittable. One-shot.
    if self.forceNextPair then
        self.forceNextPair = nil
        local hand = game.hands[1].cards
        for i, c in ipairs(game.deck) do
            if c.rank == hand[1].rank then
                hand[2], game.deck[i] = c, hand[2]
                break
            end
        end
    end

    if self:IsBlackjack(game.hands[1].cards) or self:IsBlackjack(game.dealer) then
        game.revealDealer = true
        self:Settle(game)
    end
    return game
end

function Blackjack:ActiveHand(game)
    return game and game.hands[game.active]
end

function Blackjack:CanDouble(game)
    local h = self:ActiveHand(game)
    return game and not game.over and h and not h.done
        and #h.cards == 2 and Arcade:GetCredits() >= h.bet
end

-- Split only a true pair - both cards the identical rank (K-K splits, K-10
-- does not), like proper blackjack. Resplits allowed up to MAX_HANDS hands.
function Blackjack:CanSplit(game)
    local h = self:ActiveHand(game)
    return game and not game.over and h and not h.done
        and #h.cards == 2 and #game.hands < self.MAX_HANDS
        and h.cards[1].rank == h.cards[2].rank
        and Arcade:GetCredits() >= h.bet
end

-- Mark the active hand finished and move play along; when every hand is done
-- the dealer draws and the round settles.
function Blackjack:Advance(game)
    local h = self:ActiveHand(game)
    if h then h.done = true end
    for i, hand in ipairs(game.hands) do
        if not hand.done then
            game.active = i
            -- A fresh split hand that landed on 21 has nothing left to decide.
            if (self:HandValue(hand.cards)) >= 21 then
                self:Advance(game)
            end
            return
        end
    end
    -- All hands played: dealer's turn (only if someone is still standing).
    game.revealDealer = true
    local anyLive = false
    for _, hand in ipairs(game.hands) do
        if (self:HandValue(hand.cards)) <= 21 then anyLive = true break end
    end
    if anyLive then
        while (self:HandValue(game.dealer)) < 17 do
            game.dealer[#game.dealer + 1] = table.remove(game.deck)
        end
    end
    self:Settle(game)
end

-- Player draws a card on the active hand. 21+ auto-finishes that hand.
function Blackjack:Hit(game)
    local h = self:ActiveHand(game)
    if not game or game.over or not h or h.done then return game end
    h.cards[#h.cards + 1] = table.remove(game.deck)
    if (self:HandValue(h.cards)) >= 21 then
        self:Advance(game)
    end
    return game
end

-- Double the active hand's wager, take exactly one card, hand is done.
function Blackjack:Double(game)
    if not self:CanDouble(game) then return game end
    local h = self:ActiveHand(game)
    Arcade:Spend(h.bet)              -- second, equal wager
    h.bet = h.bet * 2
    h.doubled = true
    h.cards[#h.cards + 1] = table.remove(game.deck)
    self:Advance(game)
    return game
end

-- Split the active pair into two hands, each drawing a fresh second card.
-- The new hand is inserted right after the active one so play order reads
-- left to right.
function Blackjack:Split(game)
    if not self:CanSplit(game) then return game end
    local h = self:ActiveHand(game)
    Arcade:Spend(h.bet)              -- stake the second hand
    local moved = table.remove(h.cards, 2)
    h.split = true
    h.cards[2] = table.remove(game.deck)
    table.insert(game.hands, game.active + 1, {
        cards = { moved, table.remove(game.deck) },
        bet = h.bet, done = false, doubled = false, split = true,
    })
    -- If the (re)split hand landed straight on 21, it plays itself out.
    if (self:HandValue(h.cards)) >= 21 then
        self:Advance(game)
    end
    return game
end

function Blackjack:Stand(game)
    local h = self:ActiveHand(game)
    if not game or game.over or not h or h.done then return game end
    self:Advance(game)
    return game
end

-- Decide every hand against the dealer and pay. payout per hand is what
-- returns to the balance (bets were escrowed by Spend): 0 on a loss, bet on a
-- push, 2x on a win, 2.5x on a natural (single un-split hand only - a 21 made
-- after splitting is just 21).
function Blackjack:Settle(game)
    local d = self:HandValue(game.dealer)
    local dBJ = self:IsBlackjack(game.dealer)
    local totalPayout, totalBet = 0, 0
    local wins, losses, pushes = 0, 0, 0

    for _, h in ipairs(game.hands) do
        local p = self:HandValue(h.cards)
        local pBJ = (#game.hands == 1) and not h.split and self:IsBlackjack(h.cards)
        local payout, result, key

        if pBJ and dBJ then
            payout, result, key = h.bet, "Push - both blackjack", "push"
        elseif pBJ then
            payout, result, key = h.bet + math.floor(h.bet * 3 / 2), "BLACKJACK! Pays 3:2", "blackjack"
        elseif dBJ then
            payout, result, key = 0, "Dealer has blackjack", "lose"
        elseif p > 21 then
            payout, result, key = 0, "Bust", "bust"
        elseif d > 21 then
            payout, result, key = h.bet * 2, "Dealer busts", "win"
        elseif p > d then
            payout, result, key = h.bet * 2, "Win", "win"
        elseif p < d then
            payout, result, key = 0, "Dealer wins", "lose"
        else
            payout, result, key = h.bet, "Push", "push"
        end

        h.done = true
        h.result, h.resultKey, h.payout = result, key, payout
        totalPayout = totalPayout + payout
        totalBet = totalBet + h.bet
        if key == "win" or key == "blackjack" then wins = wins + 1
        elseif key == "push" then pushes = pushes + 1
        else losses = losses + 1 end
    end

    game.over = true
    game.payout = totalPayout
    game.totalBet = totalBet

    -- Round summary (single hand keeps the classic wording).
    if #game.hands == 1 then
        game.result = game.hands[1].result
        game.resultKey = game.hands[1].resultKey
    else
        game.result = string.format("%d won, %d lost%s",
            wins, losses, pushes > 0 and (", " .. pushes .. " pushed") or "")
        local net = totalPayout - totalBet
        game.resultKey = (net > 0) and "win" or (net < 0) and "lose" or "push"
    end

    if totalPayout > 0 then
        Arcade:Award(totalPayout)
        local db = Arcade:GetDB()
        local net = totalPayout - totalBet
        if net > (db.bestBlackjackWin or 0) then db.bestBlackjackWin = net end
    end
    return game
end
