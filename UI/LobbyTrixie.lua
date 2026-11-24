--[[
    Chairface's Casino - UI/LobbyTrixie.lua
    Trixie the host: sound switches, her voice lines and pools, the table
    calls / greetings / banter, and mounting her beside a window
    (Lobby:AttachTrixie, used through UI.GameWindow:EmbedTrixie).
    Part of the lobby module (UI.Lobby), split out of UI/Lobby.lua.
]]

local BJ = ChairfacesCasino
local UI = BJ.UI
local Lobby = UI.Lobby

-- Easter egg: Trixie poke sounds (default 1 in 500 chance on click)
local DEFAULT_POKE_CHANCE = 500

-- Voice frequency multipliers (how often Trixie speaks during game events)
-- Lower = more frequent, Higher = less frequent
local VOICE_FREQ_OPTIONS = {
    { name = "Always", value = 1 },      -- Always plays
    { name = "Frequent", value = 2 },    -- 50% chance
    { name = "Normal", value = 3 },      -- 33% chance (default)
    { name = "Occasional", value = 5 },  -- 20% chance
    { name = "Rare", value = 10 },       -- 10% chance
}

function Lobby:GetPokeChance()
    -- Try to load from encrypted storage first
    if ChairfacesCasinoSaved and ChairfacesCasinoSaved.pokeChanceEnc then
        if BJ.Compression and BJ.Compression.DecodeFromSave then
            local decoded = BJ.Compression:DecodeFromSave(ChairfacesCasinoSaved.pokeChanceEnc)
            if decoded and type(decoded) == "number" then
                return decoded
            end
        end
    end
    -- Fallback to old unencrypted location (migration)
    if BJ.db and BJ.db.settings and BJ.db.settings.pokeChance then
        local value = BJ.db.settings.pokeChance
        -- Migrate to encrypted storage
        self:SetPokeChance(value)
        BJ.db.settings.pokeChance = nil  -- Clear old storage
        return value
    end
    return DEFAULT_POKE_CHANCE
end

function Lobby:SetPokeChance(value)
    if not ChairfacesCasinoSaved then
        ChairfacesCasinoSaved = {}
    end
    if BJ.Compression and BJ.Compression.EncodeForSave then
        ChairfacesCasinoSaved.pokeChanceEnc = BJ.Compression:EncodeForSave(value)
    end
end

function Lobby:GetVoiceFrequency()
    if BJ.db and BJ.db.settings and BJ.db.settings.voiceFrequency then
        return BJ.db.settings.voiceFrequency
    end
    return 3  -- Default to "Normal"
end

function Lobby:SetVoiceFrequency(value)
    if BJ.db and BJ.db.settings then
        BJ.db.settings.voiceFrequency = value
    end
end

-- The frequency slider, as the chance a line is spoken when its moment comes.
-- Keyed by the saved voiceFrequency value (the slider's five stops store
-- 1, 2, 3, 5, 10, as they always have). Always is every time; Rare is very
-- rarely. Whether she is already speaking is checked separately, first.
Lobby.VOICE_CHANCE = { [1] = 1.0, [2] = 0.6, [3] = 0.35, [5] = 0.15, [10] = 0.04 }
function Lobby:ShouldPlayVoice()
    local chance = self.VOICE_CHANCE[self:GetVoiceFrequency()] or 0.35
    return chance >= 1 or math.random() < chance
end

-- Whether a line of Trixie's is still playing. Clip lengths come from
-- UI/TrixieVoiceLengths.lua (tools/voice_lengths.py), since the client cannot
-- say how long a sound is.
local VOICE_GAP = 0.2
local VOICE_FALLBACK = 4
function Lobby:TrixieSpeaking()
    return self.voiceEndsAt ~= nil and GetTime() < self.voiceEndsAt
end

local function startClip(name)
    local base = "Interface\\AddOns\\Chairfaces Casino\\Sounds\\Trixie\\" .. name
    -- .ogg first, then .mp3. PlaySoundFile returns willPlay=false for a
    -- missing file without erroring.
    local willPlay, handle = PlaySoundFile(base .. ".ogg", "SFX")
    if not willPlay then willPlay, handle = PlaySoundFile(base .. ".mp3", "SFX") end
    return willPlay, handle
end

-- Plays one Trixie clip by file name (no extension) and marks her as speaking
-- for its length. Returns true if it played (or is lined up to).
-- opts.lineUp: the line can wait. It starts when every Trixie on screen has
-- reached the seam where she switches to talking, so the talk animation and
-- the voice begin together. She counts as speaking from now, so nothing else
-- slips in while she waits. Only for lines that aren't tied to a moment
-- (greeting, banter, nudges, the intro); reactions play at once.
-- opts.intro: remember the handle so Let's Play! can cut the line off.
local LINEUP_MAX = 4
function Lobby:PlayTrixieClip(name, opts)
    local lengths = BJ.TRIXIE_LENGTHS or {}
    local len = lengths[name] or VOICE_FALLBACK
    local lead = 0
    if opts and opts.lineUp and BJ.Trixie and BJ.Trixie.TalkLead then
        lead = math.min(BJ.Trixie:TalkLead(), LINEUP_MAX)
    end
    if lead < 0.05 then
        local willPlay, handle = startClip(name)
        if not willPlay then return false end
        self.voiceEndsAt = GetTime() + len + VOICE_GAP
        self.voiceHandle = handle
        if opts and opts.intro then self.introSoundHandle = handle end
        if BJ.Trixie then BJ.Trixie:TalkEverywhere(len) end
        return true, handle
    end
    local token = { intro = opts.intro }
    self.voiceLineUp = token
    self.voiceEndsAt = GetTime() + lead + len + VOICE_GAP
    BJ.Trixie:TalkEverywhere(lead + len)   -- each one switches at its seam
    C_Timer.After(lead, function()
        if self.voiceLineUp ~= token then return end   -- cancelled
        self.voiceLineUp = nil
        local willPlay, handle
        if self.voiceEnabled then willPlay, handle = startClip(name) end
        if not willPlay then
            self.voiceEndsAt = nil
            BJ.Trixie:StopTalkEverywhere()
            return
        end
        self.voiceEndsAt = GetTime() + len + VOICE_GAP
        self.voiceHandle = handle
        if token.intro then self.introSoundHandle = handle end
    end)
    return true
end

-- Drops a lined-up line that hasn't started yet. Returns true if there was one.
function Lobby:CancelLinedUpVoice()
    if not self.voiceLineUp then return false end
    self.voiceLineUp = nil
    self.voiceEndsAt = nil
    if BJ.Trixie and BJ.Trixie.StopTalkEverywhere then BJ.Trixie:StopTalkEverywhere() end
    return true
end

function Lobby:TryPlayPokeSound()
    return self:TryPlayPoke()
end
-- ========== AUDIO SYSTEM ==========
Lobby.sfxEnabled = true
Lobby.voiceEnabled = true

function Lobby:InitializeAudio()
    -- Ensure db is initialized
    if not BJ.db then
        BJ.db = ChairfacesCasinoDB or { settings = {} }
    end
    if not BJ.db.settings then
        BJ.db.settings = {}
    end
    
    -- Load saved settings
    if BJ.db.settings.sfxEnabled ~= nil then
        self.sfxEnabled = BJ.db.settings.sfxEnabled
    else
        self.sfxEnabled = true  -- Default SFX on
    end
    
    if BJ.db.settings.voiceEnabled ~= nil then
        self.voiceEnabled = BJ.db.settings.voiceEnabled
    else
        self.voiceEnabled = true  -- Default Voice on
    end
end

function Lobby:ToggleSFX()
    self.sfxEnabled = not self.sfxEnabled
    self:SaveAudioSettings()
    self:UpdateAudioControls()
end

function Lobby:ToggleVoice()
    self.voiceEnabled = not self.voiceEnabled
    self:SaveAudioSettings()
    self:UpdateAudioControls()
end

function Lobby:SaveAudioSettings()
    if not BJ.db then
        BJ.db = ChairfacesCasinoDB or { settings = {} }
    end
    if not BJ.db.settings then
        BJ.db.settings = {}
    end
    
    BJ.db.settings.sfxEnabled = self.sfxEnabled
    BJ.db.settings.voiceEnabled = self.voiceEnabled
end

function Lobby:UpdateAudioControls()
    if not self.settingsFrame then return end
    
    local frame = self.settingsFrame
    
    -- Update SFX button - green background when ON
    if frame.sfxBtn then
        local on = self.sfxEnabled and true or false
        BJ.Theme:SetButton(frame.sfxBtn, on and "SFX ON" or "SFX OFF", true, on and "go" or "secondary")
    end
    
    -- Update Voice button
    if frame.voiceBtn then
        local on = self.voiceEnabled and true or false
        BJ.Theme:SetButton(frame.voiceBtn, on and "VOICE ON" or "VOICE OFF", true, on and "go" or "secondary")
    end
end

-- Play sound effects (called from game code)
function Lobby:PlayBustSound()
    if not self.sfxEnabled then return end
    if not self:IsAnyCasinoWindowOpen() then return end
    PlaySound(8959, "SFX")
end

function Lobby:PlayWinSound()
    if not self.sfxEnabled then return end
    -- Only play sounds if a casino window is actually open
    if not self:IsAnyCasinoWindowOpen() then return end
    local soundFile = "Interface\\AddOns\\Chairfaces Casino\\Sounds\\fanfare.ogg"
    PlaySoundFile(soundFile, "SFX")
end

-- Check if any casino window is open
function Lobby:IsAnyCasinoWindowOpen()
    local UI = BJ.UI
    if not UI then return false end
    
    -- Check lobby
    if self.frame and self.frame:IsShown() then return true end
    
    -- Check blackjack
    if UI.mainFrame and UI.mainFrame:IsShown() then return true end
    
    -- Check poker
    if UI.Poker and UI.Poker.mainFrame and UI.Poker.mainFrame:IsShown() then return true end

    -- Check hold'em
    if UI.Holdem and UI.Holdem.mainFrame and UI.Holdem.mainFrame:IsShown() then return true end

    -- Check hi-lo
    if UI.HiLo and UI.HiLo.frame and UI.HiLo.frame:IsShown() then return true end

    -- Every other game window uses module.frame — a window missing here is a
    -- muted game (all Lobby:Play*Sound calls gate on this function).
    for _, mod in ipairs({ UI.DeathRoll, UI.Bingo, UI.Roulette, UI.LiarsDice,
                           UI.Crash, UI.Slots, UI.SlotFloor, UI.Reels, UI.VideoPoker, UI.Debts }) do
        if mod and mod.frame and mod.frame:IsShown() then return true end
    end

    -- Derby lives in its own global frame
    if SigmaDerbyFrame and SigmaDerbyFrame:IsShown() then return true end

    return false
end

function Lobby:PlayShuffleSound()
    if not self.sfxEnabled then return end
    if not self:IsAnyCasinoWindowOpen() then return end
    local soundFile = "Interface\\AddOns\\Chairfaces Casino\\Sounds\\shuffle.ogg"
    PlaySoundFile(soundFile, "SFX")
end

function Lobby:PlayCardSound()
    if not self.sfxEnabled then return end
    if not self:IsAnyCasinoWindowOpen() then return end
    local soundFile = "Interface\\AddOns\\Chairfaces Casino\\Sounds\\flycard.ogg"
    PlaySoundFile(soundFile, "SFX")
end

-- Trixie voice lines (play at ~25% chance)
-- The intro is asked for: it stops whatever she was saying and plays.
function Lobby:PlayTrixieIntroVoice()
    if not self.voiceEnabled then return end
    self:CancelLinedUpVoice()
    if self.voiceHandle and self:TrixieSpeaking() then StopSound(self.voiceHandle) end
    self:PlayTrixieClip("trix_intro", { lineUp = true, intro = true })
end

function Lobby:StopTrixieIntroVoice()
    if self.voiceLineUp and self.voiceLineUp.intro then self:CancelLinedUpVoice() end
    if self.introSoundHandle then
        StopSound(self.introSoundHandle)
        if self.voiceHandle == self.introSoundHandle then self.voiceEndsAt = nil end
        self.introSoundHandle = nil
    end
end

--[[
    CENTRAL TRIXIE VOICE POOLS
    Every situation maps to a list of .ogg basenames in Sounds\Trixie\. Record
    any subset you like - a missing file just no-ops in PlaySoundFile, so pools
    can grow as you add clips. Add a new basename here and it plays as soon as
    the file exists. Existing recorded clips (trix_woohoo/cheer*/bad*/bust*/
    blackjack) are kept in their pools for backward compatibility.
]]
-- category = how many clips exist (trix_<cat>1 .. trix_<cat>N in Sounds\Trixie).
-- Bump the number here AND add the matching lines to tools/gen_trixie_voices.py,
-- then re-run it, to give her more variety. A too-high count is harmless
-- (missing files just no-op). Filenames are trix_<category><index>.ogg/.mp3.
Lobby.TRIXIE_VOICE = {
    -- Counts are synced to the clips ACTUALLY on disk via
    -- `gen_trixie_voices.py --counts-disk`. Every line was re-recorded in
    -- ElevenLabs' Eleven v4 with tools/regen_v4.py (2026-09-28), which also
    -- filled the 19 clips earlier batches had left queued.
    -- lobby / ambient
    greet = 40, banter = 52, bye = 32,
    -- generic outcomes, shared by every game
    win = 52, lose = 52, bust = 36, blackjack = 32,
    -- big moments
    jackpot = 32, bigwin = 32,
    -- money changing hands
    debt = 32, paid = 26,
    -- per-game "table just opened" announcements (keyed open_<gameKey>)
    open_blackjack = 24, open_poker = 24, open_holdem = 24, open_hilo = 24,
    open_deathroll = 24, open_liarsdice = 24, open_bingo = 24,
    open_roulette = 24, open_crash = 24,
    -- game-specific dramatic moments
    deathroll_bust = 26, crash_bail = 26, crash_boom = 26,
    deathroll_close = 24, roulette_nobets = 24, bingo_win = 24,
    liarsdice_challenge = 24, liarsdice_bluff = 24,
    -- card-game moments
    bj_dealerbust = 24, bj_push = 24, bj_double = 24, poker_showdown = 24,
    poker_fold = 24,
    -- crash moments
    crash_takeoff = 24, crash_flyaway = 24, crash_high = 24,
    -- Hold'em tournament
    tourney_champ = 24, tourney_bustout = 24,
    -- table flow
    turn_nudge = 24, countdown = 24,
}

-- Play a random clip from a category. In order:
--   MUTE (voiceEnabled) is always honored.
--   ONE AT A TIME: while a line is still playing, a new one is dropped, never
--     queued and never played over her.
--   FREQUENCY (the slider, ShouldPlayVoice) decides whether she speaks at
--     all; at Always she speaks every time. Only the table-open call skips it
--     (opts.noFreq), so a table going live always reaches the group.
--   opts.cd: a per-category cooldown in seconds.
--   opts.lineUp: the line can wait for her talk animation (PlayTrixieClip).
-- Returns true only if a clip actually started playing.
Lobby.lastVoiceAt = {}
function Lobby:PlayTrixieVoice(cat, opts)
    if not self.voiceEnabled then return false end          -- mute (always)
    opts = opts or {}
    if self:TrixieSpeaking() then return false end          -- dropped, not queued
    local n = self.TRIXIE_VOICE[cat]
    if not n or n < 1 then return false end
    if not opts.noFreq and not self:ShouldPlayVoice() then return false end  -- frequency
    local now = GetTime()
    if opts.cd and self.lastVoiceAt[cat] and (now - self.lastVoiceAt[cat]) < opts.cd then
        return false
    end
    if self:PlayTrixieClip("trix_" .. cat .. math.random(1, n), { lineUp = opts.lineUp }) then
        self.lastVoiceAt[cat] = now
        return true
    end
    return false
end

-- Back-compat wrappers: the games call these by name all over the codebase.
function Lobby:PlayTrixieBlackjackVoice() self:PlayTrixieVoice("blackjack") end
function Lobby:PlayTrixieBadVoice()       self:PlayTrixieVoice("lose") end
function Lobby:PlayTrixieBustVoice()      self:PlayTrixieVoice("bust") end
function Lobby:PlayTrixieWoohooVoice()    self:PlayTrixieVoice("win") end

function Lobby:PlayGameStartSound()
    local soundFile = "Interface\\AddOns\\Chairfaces Casino\\Sounds\\chips.ogg"
    PlaySoundFile(soundFile, "SFX")
end

--[[
    TRIXIE THE HOST - SCRIPTED CHATTER
    Trixie barks out every table that opens on the addon network (by name and
    host), drops a greeting when you open the lobby, and tosses the odd bit of
    idle banter while you loiter. All gated by db.settings.trixieChatter
    (default on) and throttled so she's flavor, never spam.
]]

-- Coloured chat line in Trixie's voice. Routes to chat + the casino log.
function Lobby:TrixieSay(text)
    BJ:Print("|cffff77ccTrixie:|r |cffffe6f5" .. text .. "|r")
end

function Lobby:TrixieChatterOn()
    if BJ.db and BJ.db.settings and BJ.db.settings.trixieChatter == false then return false end
    return true
end

-- Called from GameComm when any game's TABLE_OPEN arrives (never for your own
-- broadcast - the comm preamble self-filters). displayName is the game's
-- user-facing name; hostName is the opener.
Lobby.lastTableCall = {}
Lobby.TABLE_CALL_LINES = {
    "Heads up, sugar - <host> just threw open a <game> table! Grab a seat before it fills up.",
    "Ding ding ding! <host> is hostin' <game>. Bring your gold and your nerve.",
    "Ooooh, <host> opened up <game>! You feelin' lucky tonight, hon?",
    "<host>'s <game> table is LIVE. Don't make me come find you.",
    "Fresh <game> table, courtesy of <host> - the chips are waitin', darlin'.",
    "Word on the floor: <host> is runnin' <game>. Get in there!",
    "<game>, hosted by <host>, now takin' all comers. The house says hi.",
    "Step right up! <host> just racked 'em for a round of <game>.",
}
-- Returns true if Trixie SPOKE a table-open line (so the caller can skip the
-- fallback chime). The chat line is gated by the chatter toggle; the spoken
-- game-specific announcement is gated by voice mute + frequency.
function Lobby:TrixieAnnounceTable(displayName, hostName, gameKey)
    if not displayName then return false end
    local key = gameKey or displayName
    local now = GetTime()
    local last = self.lastTableCall[key]
    if last and (now - last) < 60 then return false end   -- one call per game per minute
    self.lastTableCall[key] = now
    if self:TrixieChatterOn() then
        local host = hostName and (hostName:match("^([^-]+)") or hostName) or "Somebody"
        local line = self.TABLE_CALL_LINES[math.random(1, #self.TABLE_CALL_LINES)]
        line = line:gsub("<host>", host):gsub("<game>", displayName)
        self:TrixieSay(line)
    end
    -- "Blackjack's open!" - a game-specific spoken call so other addon holders
    -- in the group/raid hear a table went live. NOT gated by the frequency
    -- slider (still respects mute) so the alert is reliable.
    return self:PlayTrixieVoice("open_" .. (gameKey or ""), { noFreq = true, lineUp = true })
end

-- A one-liner when you open the lobby, throttled so re-opening isn't chatty.
Lobby.GREETING_LINES = {
    "Well look who's back! Pull up a chair, the felt's still warm.",
    "Welcome to Chairface's, hon. Tables are hot tonight - go make some bad decisions.",
    "There's my favorite high roller. What are we losin' - I mean WINNIN' - today?",
    "Doors are open, drinks are flowin'. Pick your poison off the board.",
    "Evenin', sugar. The house always wins... but tonight it could be your house.",
    "You hear that? That's the sound of gold changin' hands. Let's add yours.",
}
-- She always says something when the casino opens (unless she is mid-line);
-- the chat text is throttled so re-opening doesn't fill the chat.
function Lobby:TrixieGreeting()
    local now = GetTime()
    if self:TrixieChatterOn() and not (self.lastGreeting and (now - self.lastGreeting) < 600) then
        self.lastGreeting = now
        self:TrixieSay(self.GREETING_LINES[math.random(1, #self.GREETING_LINES)])
    end
    self:PlayTrixieVoice("greet", { noFreq = true, lineUp = true })
end

-- Hello and goodbye: the casino counts as open while any of its windows is
-- (or the first-run intro is up). Going from closed to open she greets you,
-- from open to closed she says goodbye; both skip the frequency slider, and
-- like every line they're dropped if she's already speaking. One watcher
-- covers every way in or out (lobby, game windows, Escape, the minimap
-- button, links), and a close must hold for two checks so the hop between
-- a game window and the lobby (or a window refresh) isn't a goodbye.
local CASINO_CHECK_SECS = 0.2
function Lobby:IntroUp()
    if self.introPendingUntil and GetTime() < self.introPendingUntil then return true end
    return self.introContainer ~= nil and self.introContainer:IsShown()
end

-- The lobby's side windows replace it while they're up (settings, help, the
-- boards, the finder), so they count as the casino being open too.
local SIDE_WINDOWS = { "ChairfacesCasinoSettings", "ChairfacesCasinoFinder",
                       "CasinoAllTimeLeaderboard", "ChairfacesCasinoDebts" }
function Lobby:CasinoUp()
    if self:IsAnyCasinoWindowOpen() or self:IntroUp() then return true end
    if self.helpPanel and self.helpPanel:IsShown() then return true end
    for _, name in ipairs(SIDE_WINDOWS) do
        local f = _G[name]
        if f and f.IsShown and f:IsShown() then return true end
    end
    return false
end

function Lobby:CheckCasinoOpen()
    local open = self:CasinoUp()
    if open then
        self.casinoClosedChecks = 0
        if not self.casinoOpen then
            self.casinoOpen = true
            -- the intro is her hello on the very first run
            if not self:IntroUp() then self:TrixieGreeting() end
        end
    elseif self.casinoOpen then
        self.casinoClosedChecks = (self.casinoClosedChecks or 0) + 1
        if self.casinoClosedChecks >= 2 then
            self.casinoOpen = false
            self:PlayTrixieVoice("bye", { noFreq = true })
        end
    end
end

function Lobby:StartCasinoWatch()
    if self.casinoWatch then return end
    self.casinoWatch = C_Timer.NewTicker(CASINO_CHECK_SECS, function() self:CheckCasinoOpen() end)
end
C_Timer.After(0, function() Lobby:StartCasinoWatch() end)

-- Idle banter: while the lobby is up, she occasionally pipes up. Started on
-- Show, self-cancels when the lobby hides.
Lobby.BANTER_LINES = {
    "Still browsin'? The chips don't stack themselves, darlin'.",
    "Psst - Death Roll's quick if you're feelin' brave. Or foolish. Same thing.",
    "I once saw a gnome win the mega on a two-copper bet. Could be you.",
    "House rule number one: it's only gamblin' if you stop while you're ahead.",
    "That zeppelin in Crash? She always blows. Question is when you jump.",
    "Fancy a spin on Azeroth Riches? The pots are lookin' plump tonight.",
    "No rush, hon. The tables'll still be riggeddd- I mean, RUNNING, when you're ready.",
}
function Lobby:StartBanterTicker()
    if self.banterTicker then return end
    self.banterTicker = C_Timer.NewTicker(75, function()
        if not (self.frame and self.frame:IsShown()) then
            if self.banterTicker then self.banterTicker:Cancel(); self.banterTicker = nil end
            return
        end
        if not self:TrixieChatterOn() then return end
        if math.random(1, 100) > 40 then return end   -- ~40% of ticks
        self:TrixieSay(self.BANTER_LINES[math.random(1, #self.BANTER_LINES)])
        self:PlayTrixieVoice("banter", { lineUp = true })
    end)
end
function Lobby:StopBanterTicker()
    if self.banterTicker then self.banterTicker:Cancel(); self.banterTicker = nil end
end

-- Attach the Trixie dealer to the right side of a game window. Rolls a
-- fresh pose each time the window opens, respects the show-Trixie
-- setting, and keeps the poke easter egg.
-- gameKey (optional): drives the "<gameKey>ShowTrixie" setting so each game's
-- Trixie can be toggled independently in the settings panel. Callers that pass
-- no key (the solo arcade machines) fall back to the shared lobby toggle.
function Lobby:AttachTrixie(parentFrame, gameKey)
    local tf = CreateFrame("Button", nil, parentFrame)
    tf:SetSize(274, 350)
    tf:SetPoint("LEFT", parentFrame, "RIGHT", 0, 0)

    local tex = tf:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    BJ.Trixie:Attach(tf, tex)

    tf:SetScript("OnClick", function()
        Lobby:TryPlayPoke()
    end)

    local settingKey = gameKey and (gameKey .. "ShowTrixie") or "showLobbyTrixie"
    local function refresh()
        local show = true
        if BJ.db and BJ.db.settings then
            show = BJ.db.settings[settingKey] ~= false
        end
        if show then
            tf:Idle(true)
            tf:Show()
        else
            tf:Hide()
        end
    end
    parentFrame:HookScript("OnShow", refresh)
    if parentFrame:IsShown() then refresh() end

    -- Register the refresh so the settings panel can toggle this game's Trixie
    -- live (each game frame is built once, so one refresh per key).
    Lobby.gameTrixies = Lobby.gameTrixies or {}
    local regKey = gameKey or "lobby"
    Lobby.gameTrixies[regKey] = Lobby.gameTrixies[regKey] or {}
    table.insert(Lobby.gameTrixies[regKey], refresh)

    parentFrame.trixieFrame = tf   -- so games can make her react
    return tf
end

-- Play a reaction (a clip, or a still held for holdSecs), then back to
-- waiting. Safe to call on any frame that mounted her via AttachTrixie;
-- overlapping reactions just replace each other.
function Lobby:TrixieReact(parentFrame, mood, holdSecs)
    local tf = parentFrame and parentFrame.trixieFrame
    if not tf or not tf.React or not tf:IsShown() then return end
    tf:React(mood, { hold = holdSecs or 4 })
end

-- Re-run the visibility refresh for a game that mounts Trixie via AttachTrixie.
function Lobby:RefreshGameTrixie(gameKey)
    if not self.gameTrixies then return end
    local list = self.gameTrixies[gameKey]
    if not list then return end
    for _, fn in ipairs(list) do fn() end
end
