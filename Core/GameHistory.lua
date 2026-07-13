--[[
    Chairface's Casino - GameHistory.lua
    Shared persistence for per-game history logs (last N games).
    Stored encoded in ChairfacesCasinoSaved under a per-game key.
]]

local BJ = ChairfacesCasino
BJ.GameHistory = {}
local GH = BJ.GameHistory

GH.DEFAULT_MAX = 5

-- Push a finished game onto the front of a history list, trimming to max
function GH:Add(history, game, maxEntries)
    table.insert(history, 1, game)
    while #history > (maxEntries or self.DEFAULT_MAX) do
        table.remove(history)
    end
end

-- Save a history list to SavedVariables (encoded)
function GH:Save(key, history)
    if not ChairfacesCasinoSaved then
        ChairfacesCasinoSaved = {}
    end

    if BJ.Compression and BJ.Compression.EncodeForSave then
        ChairfacesCasinoSaved[key] = BJ.Compression:EncodeForSave(history)
    end
end

-- Load a history list from SavedVariables; returns the table or nil
function GH:Load(key)
    if not ChairfacesCasinoSaved or not ChairfacesCasinoSaved[key] then
        return nil
    end

    if BJ.Compression and BJ.Compression.DecodeFromSave then
        local decoded = BJ.Compression:DecodeFromSave(ChairfacesCasinoSaved[key])
        if decoded and type(decoded) == "table" then
            return decoded
        end
    end

    return nil
end
