--[[
    Chairface's Casino - HostSettings.lua
    Host configuration menu for game settings
]]

local BJ = ChairfacesCasino
BJ.HostSettings = {}
local HS = BJ.HostSettings

-- Default settings
HS.defaults = {
    -- Blackjack settings
    ante = 10,
    maxMultiplier = 1,      -- 1 = no multiples allowed, 2/5/10 = max allowed
    maxPlayers = 20,        -- Max players per round (1-20)
    dealerHitsSoft17 = true, -- H17 (true) or S17 (false) - dealer hits/stands on soft 17
    countdownEnabled = false,
    countdownSeconds = 15,
    -- Poker settings
    pokerAnte = 10,
    pokerMaxRaise = 100,    -- Max raise per betting round
    pokerMaxPlayers = 10,   -- Max players for poker (2-10)
    pokerCountdownEnabled = false,
    pokerCountdownSeconds = 15,
}

-- Current settings (copied from defaults or saved)
HS.current = {}

-- Available options
HS.anteOptions = { 10, 25, 50, 100, 250, 500, 1000 }
HS.multiplierOptions = { 1, 2, 5, 10 }  -- 1 means "no multiples"
HS.maxPlayersOptions = { 1, 2, 3, 4, 5, 6, 8, 10, 15, 20 }  -- Max players options
HS.pokerMaxPlayersOptions = { 2, 3, 4, 5, 6, 7, 8, 9, 10 }  -- Poker max players (2-10)
HS.countdownOptions = { 10, 15, 20, 30, 45, 60 }
HS.maxRaiseOptions = { 25, 50, 100, 250, 500, 1000 }  -- Poker max raise options

-- Initialize settings
function HS:Initialize()
    -- Load from saved variables or use defaults
    if ChairfacesCasinoDB and ChairfacesCasinoDB.hostSettings then
        for k, v in pairs(self.defaults) do
            self.current[k] = ChairfacesCasinoDB.hostSettings[k] or v
        end
    else
        for k, v in pairs(self.defaults) do
            self.current[k] = v
        end
    end
end

-- Save settings
function HS:Save()
    if not ChairfacesCasinoDB then
        ChairfacesCasinoDB = {}
    end
    ChairfacesCasinoDB.hostSettings = {}
    for k, v in pairs(self.current) do
        ChairfacesCasinoDB.hostSettings[k] = v
    end
end

-- Get setting
function HS:Get(key)
    -- Use explicit nil check to handle boolean false correctly
    if self.current[key] ~= nil then
        return self.current[key]
    end
    return self.defaults[key]
end

-- Set setting
function HS:Set(key, value)
    self.current[key] = value
    self:Save()
end

-- Get display text for multiplier
function HS:GetMultiplierText(mult)
    if mult == 1 then
        return "None (Ante Only)"
    else
        return "Up to " .. mult .. "x"
    end
end

-- Get display text for countdown
function HS:GetCountdownText()
    if self.current.countdownEnabled then
        return self.current.countdownSeconds .. " seconds"
    else
        return "Disabled (Manual)"
    end
end

-- Validate settings before starting
function HS:Validate()
    local errors = {}
    
    if not self.current.ante or self.current.ante <= 0 then
        table.insert(errors, "Ante must be greater than 0")
    end
    
    if not self.current.maxMultiplier or self.current.maxMultiplier < 1 then
        table.insert(errors, "Invalid max multiplier")
    end
    
    if self.current.countdownEnabled and 
       (not self.current.countdownSeconds or self.current.countdownSeconds < 5) then
        table.insert(errors, "Countdown must be at least 5 seconds")
    end
    
    return #errors == 0, errors
end

-- Serialize settings for network transmission
-- Uses semicolon delimiter to avoid conflict with main message pipe delimiter
function HS:Serialize()
    return string.format("%d;%d;%d;%d;%d;%d",
        self.current.ante,
        self.current.maxMultiplier,
        self.current.maxPlayers or 20,
        self.current.countdownEnabled and 1 or 0,
        self.current.countdownSeconds or 0,
        self.current.dealerHitsSoft17 and 1 or 0
    )
end

-- Deserialize settings from network
function HS:Deserialize(str)
    local ante, mult, maxPlayers, cdEnabled, cdSeconds, hitsSoft17 = strsplit(";", str)
    return {
        ante = tonumber(ante) or 50,
        maxMultiplier = tonumber(mult) or 1,
        maxPlayers = tonumber(maxPlayers) or 20,
        countdownEnabled = (tonumber(cdEnabled) or 0) == 1,
        countdownSeconds = tonumber(cdSeconds) or 15,
        dealerHitsSoft17 = hitsSoft17 == nil or (tonumber(hitsSoft17) or 1) == 1,  -- Default to H17 if not present
    }
end

-- Initialize on load
HS:Initialize()
