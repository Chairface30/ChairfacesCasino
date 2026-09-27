--[[
    Chairface's Casino - TableFinder.lua
    An LFG board for gambling: players list themselves as hosting a table or
    looking to play, everyone else browses the live list and whispers/invites.

    Listings are ephemeral so nothing is saved to SavedVariables. Transport:
      - GUILD + PARTY/RAID addon messages (sendable any time)
      - the shared hidden "ChairfaceCasino" chat channel for realm-wide reach.
        SendChatMessage to a CHANNEL is hardware-protected, so channel sends
        are queued and flushed from real clicks (the finder UI's buttons).
    This module OWNS joining that channel at login (it inherited the job
    when the events calendar was removed), and the channel doubles as the
    presence signal: a member's CHAT_MSG_CHANNEL_LEAVE fires when they log
    out for ANY reason, and their listing is dropped on the spot.
]]

local BJ = ChairfacesCasino
BJ.TableFinder = {}
local TF = BJ.TableFinder

local PREFIX = "CCTableLFG"
local CHANNEL_NAME = "ChairfaceCasino"   -- joined below at login
local CHAN_MARK = "CCLFG7"               -- marks OUR traffic in that channel
local TTL = 15 * 60                      -- listings expire without a refresh
local HEARTBEAT = 4 * 60                 -- re-broadcast my listing this often
local FIELD_LIMITS = { stake = 24, note = 70 }

-- Games offered in the finder dropdown; keys match the casinolink games so a
-- listing can deep-link into the right window.
TF.GAMES = {
    { key = "any",       name = "Anything" },
    { key = "blackjack", name = "Blackjack" },
    { key = "poker",     name = "5 Card Stud" },
    { key = "holdem",    name = "Texas Hold'em" },
    { key = "hilo",      name = "High-Lo" },
    { key = "deathroll", name = "Death Roll" },
    { key = "bingo",     name = "Bingo" },
    { key = "roulette",  name = "Roulette" },
    { key = "liarsdice", name = "Liar's Dice" },
    { key = "crash",     name = "Crash" },
    { key = "chairscup", name = "Chair's Cup" },
}

function TF:GameName(key)
    for _, g in ipairs(self.GAMES) do
        if g.key == key then return g.name end
    end
    return "Anything"
end

local function validGameKey(key)
    for _, g in ipairs(TF.GAMES) do
        if g.key == key then return key end
    end
    return "any"
end

-- listings[shortName] = { name, kind = "host"|"seek", game, stake, note, seen }
-- `seen` is OUR clock at receipt - poster clocks aren't comparable.
TF.listings = {}
TF.myListing = nil
local announced = {}   -- players we already printed a chat notice for

local function shortName(name)
    return name and (name:match("^([^-]+)") or name) or "?"
end

-- Same security-relevant filtering as the calendar: no pipes (escape codes /
-- wire delimiter), no "~" (reserved by the channel transport), no controls.
local function sanitize(text, limit)
    text = tostring(text or "")
    text = text:gsub("|", "")
    text = text:gsub("~", "")
    text = text:gsub("[%z\1-\31\127]", " ")
    text = text:gsub("%s+", " ")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    if limit and #text > limit then text = text:sub(1, limit) end
    return text
end

-- ------------------------------------------------------------------- comm --
local channelQueue = {}

local function channelIndex()
    local idx = GetChannelName(CHANNEL_NAME)
    return (idx and idx > 0) and idx or nil
end

-- Channel joining (moved here from the retired events calendar).
-- A custom channel is assigned the LOWEST free slot when joined. Joining
-- before the server zone channels (General etc.) have claimed /1 would park
-- casino traffic on /1 - and every "/1 hello" the player types would land
-- in the casino pipe instead of General chat. Two defenses:
--   1. wait for slot 1 to be taken before joining (bounded - some players
--      opt out of General entirely, so give up waiting after ~40s)
--   2. after joining, shove our channel to the highest free slot, well out
--      of the low numbers players actually type
local function bumpChannelIndex()
    if not (C_ChatInfo and C_ChatInfo.SwapChatChannelsByChannelIndex) then return end
    local idx = channelIndex()
    if not idx or idx >= 11 then return end   -- already out of finger range
    local maxSlot = MAX_WOW_CHAT_CHANNELS or 10
    for target = maxSlot, idx + 1, -1 do
        local _, taken = GetChannelName(target)
        if not taken then
            C_ChatInfo.SwapChatChannelsByChannelIndex(idx, target)
            return
        end
    end
end

local joinTries = 0
local function joinCasinoChannel()
    if channelIndex() then
        -- auto-rejoined from a previous session, possibly at a low slot
        bumpChannelIndex()
        return
    end
    local _, slot1 = GetChannelName(1)
    joinTries = joinTries + 1
    if not slot1 and joinTries < 8 then
        C_Timer.After(5, joinCasinoChannel)   -- zone channels still settling
        return
    end
    if JoinChannelByName then JoinChannelByName(CHANNEL_NAME) end
    C_Timer.After(2, function()
        -- keep the pipe channel out of the player's chat tabs
        if ChatFrame_RemoveChannel and DEFAULT_CHAT_FRAME then
            ChatFrame_RemoveChannel(DEFAULT_CHAT_FRAME, CHANNEL_NAME)
        end
        bumpChannelIndex()
    end)
end

local function sendChannel(msg)
    local idx = channelIndex()
    if idx then
        SendChatMessage(CHAN_MARK .. msg:gsub("%|", "~"), "CHANNEL", nil, idx)
    end
end

-- Call ONLY from hardware-event contexts (the finder UI's button clicks).
function TF:FlushChannelQueue()
    -- Piggyback the leaderboard's realm HELLO on the same hardware event.
    if BJ.Leaderboard and BJ.Leaderboard.FlushRealmQueue then
        BJ.Leaderboard:FlushRealmQueue()
    end
    -- ...and any queued progressive-jackpot reset/request broadcasts.
    if BJ.Arcade and BJ.Arcade.FlushJackpotChannel then
        BJ.Arcade:FlushJackpotChannel()
    end
    if #channelQueue == 0 then return end
    local q = channelQueue
    channelQueue = {}
    for _, m in ipairs(q) do sendChannel(m) end
end

local function broadcast(msg, deferChannel)
    if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
    if IsInGuild() then
        C_ChatInfo.SendAddonMessage(PREFIX, msg, "GUILD")
    end
    if IsInRaid() then
        C_ChatInfo.SendAddonMessage(PREFIX, msg, "RAID")
    elseif IsInGroup() then
        C_ChatInfo.SendAddonMessage(PREFIX, msg, "PARTY")
    end
    if deferChannel then
        channelQueue[#channelQueue + 1] = msg
    else
        sendChannel(msg)
    end
end

local function whisperTo(target, msg)
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        C_ChatInfo.SendAddonMessage(PREFIX, msg, "WHISPER", target)
    end
end

local function listWire(l)
    return table.concat({ "LIST", l.kind, l.game, l.stake, l.note }, "|")
end

-- ---------------------------------------------------------------- actions --
-- Called from UI button clicks, so the channel leg goes out immediately.
function TF:ListMe(kind, game, stake, note)
    kind = (kind == "host") and "host" or "seek"
    self.myListing = {
        name = shortName(UnitName("player")),
        kind = kind,
        game = validGameKey(game),
        stake = sanitize(stake, FIELD_LIMITS.stake),
        note = sanitize(note, FIELD_LIMITS.note),
        seen = time(),
    }
    -- our own broadcasts never come back through onMessage (self-filtered),
    -- so put my listing on my own board directly
    self.listings[self.myListing.name] = self.myListing
    broadcast(listWire(self.myListing))
    BJ:Print(kind == "host"
        and ("Listed: hosting " .. self:GameName(self.myListing.game) .. ". Players can now find you.")
        or  ("Listed: looking for " .. self:GameName(self.myListing.game) .. ". Hosts can now find you."))
    self:StartHeartbeat()
end

function TF:Delist(silent)
    if not self.myListing then return end
    self.listings[self.myListing.name] = nil
    self.myListing = nil
    broadcast("DELIST")
    self:StopHeartbeat()
    if not silent then BJ:Print("Delisted from the table finder.") end
end

-- Keep my listing alive for guild/group peers. The channel leg is queued
-- (hardware rule) and rides out with the player's next finder click.
function TF:StartHeartbeat()
    if self.heartbeat then return end
    self.heartbeat = C_Timer.NewTicker(HEARTBEAT, function()
        if TF.myListing then
            TF.myListing.seen = time()
            broadcast(listWire(TF.myListing), true)
        end
    end)
end

function TF:StopHeartbeat()
    if self.heartbeat then
        self.heartbeat:Cancel()
        self.heartbeat = nil
    end
end

local lastReq = 0
-- Ask listed players to re-announce (opening/refreshing the browser).
function TF:RequestListings()
    local now = time()
    if now - lastReq < 30 then return end
    lastReq = now
    broadcast("REQ", true)
end

function TF:Prune()
    local now = time()
    for name, l in pairs(self.listings) do
        if (now - (l.seen or 0)) > TTL then
            self.listings[name] = nil
        end
    end
end

-- Sorted for the browser: hosts first, then freshest first.
function TF:GetListings()
    self:Prune()
    local out = {}
    for _, l in pairs(self.listings) do
        table.insert(out, l)
    end
    table.sort(out, function(a, b)
        if a.kind ~= b.kind then return a.kind == "host" end
        return (a.seen or 0) > (b.seen or 0)
    end)
    return out
end

-- ---------------------------------------------------------------- receive --
local lastReqReply = 0

local function refreshUI()
    if BJ.UI and BJ.UI.Finder and BJ.UI.Finder.Refresh then
        BJ.UI.Finder:Refresh()
    end
end

local function onMessage(msg, sender)
    local senderShort = shortName(sender)
    if senderShort == UnitName("player") then return end
    local kind, rest = msg:match("^(%u+)|?(.*)$")

    if kind == "LIST" then
        local lkind, game, stake, note = strsplit("|", rest)
        local isNew = not TF.listings[senderShort]
        TF.listings[senderShort] = {
            name = senderShort,
            kind = (lkind == "host") and "host" or "seek",
            game = validGameKey(game),
            stake = sanitize(stake, FIELD_LIMITS.stake),
            note = sanitize(note, FIELD_LIMITS.note),
            seen = time(),
        }
        -- one quiet chat notice per player per session, so the board is
        -- discoverable without becoming spam
        if isNew and not announced[senderShort] then
            announced[senderShort] = true
            local l = TF.listings[senderShort]
            local link = BJ.CreateGameLink and BJ:CreateGameLink("finder", "Table Finder") or "/cc lfg"
            BJ:Print(senderShort .. (l.kind == "host" and " is hosting " or " wants to play ") ..
                TF:GameName(l.game) .. " - " .. link)
        end
        refreshUI()

    elseif kind == "DELIST" then
        if TF.listings[senderShort] then
            TF.listings[senderShort] = nil
            refreshUI()
        end

    elseif kind == "REQ" then
        -- Someone opened their browser: if I'm listed, re-announce by
        -- whisper, staggered so a whole guild doesn't answer at once.
        if not TF.myListing then return end
        local now = time()
        if now - lastReqReply < 60 then return end
        lastReqReply = now
        C_Timer.After(math.random(10, 40) / 10, function()
            if TF.myListing then whisperTo(sender, listWire(TF.myListing)) end
        end)
    end
end

-- ------------------------------------------------------------------- boot --
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("CHAT_MSG_ADDON")
boot:RegisterEvent("CHAT_MSG_CHANNEL")
boot:RegisterEvent("CHAT_MSG_CHANNEL_LEAVE")
boot:SetScript("OnEvent", function(_, event, ...)
    if event == "CHAT_MSG_ADDON" then
        local prefix, msg, _, sender = ...
        if prefix == PREFIX then onMessage(msg, sender) end
    elseif event == "CHAT_MSG_CHANNEL" then
        -- Channel first, then the text, each through BJ:Readable: on
        -- Forever channel text can be a secret string (see Core.lua).
        local text, sender, _, _, _, _, _, _, chanName = ...
        chanName = BJ:Readable(chanName)
        if chanName and chanName:lower():find(CHANNEL_NAME:lower(), 1, true) then
            text, sender = BJ:Readable(text), BJ:Readable(sender)
            if text and sender and text:sub(1, #CHAN_MARK) == CHAN_MARK then
                onMessage(text:sub(#CHAN_MARK + 1):gsub("~", "|"), sender)
            end
        end
    elseif event == "CHAT_MSG_CHANNEL_LEAVE" then
        -- every addon user sits in the shared channel, so a member leaving
        -- IS the logout signal (camp, alt-f4, disconnect - all of it):
        -- their listing dies immediately instead of aging out on the TTL
        local _, who, _, _, _, _, _, _, chanName = ...
        who, chanName = BJ:Readable(who), BJ:Readable(chanName)
        if who and chanName
            and chanName:lower():find(CHANNEL_NAME:lower(), 1, true) then
            local short = shortName(who)
            if TF.listings[short] then
                TF.listings[short] = nil
                announced[short] = nil   -- a re-login announces fresh
                refreshUI()
            end
        end
    elseif event == "PLAYER_LOGIN" then
        if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
            C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
        end
        -- join the shared casino channel (quietly - it's addon traffic
        -- only; this module owns the join since the calendar retired)
        C_Timer.After(5, joinCasinoChannel)
        -- guild/group legs go out now; the channel leg is queued until the
        -- player's first finder click (hardware-event rule)
        C_Timer.After(12, function() broadcast("REQ", true) end)
    end
end)
