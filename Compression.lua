--[[
    Chairface's Casino - Compression.lua
    Network message compression using LibCompress
    Also provides encoding for persistent saved data
]]

local BJ = ChairfacesCasino
BJ.Compression = {}
local Comp = BJ.Compression

-- Try to load LibCompress (bundled with Ace3)
local LibCompress = LibStub and LibStub:GetLibrary("LibCompress", true)
local LibCompressEncode = LibCompress and LibStub:GetLibrary("LibCompressAddonEncodeTable", true)
local AceSerializer = LibStub and LibStub:GetLibrary("AceSerializer-3.0", true)

-- Flag to track if compression is available
Comp.available = false
Comp.encoder = nil

-- Simple XOR key for obfuscation (not encryption, just discourages casual editing)
local XOR_KEY = { 0x43, 0x68, 0x61, 0x69, 0x72, 0x66, 0x61, 0x63, 0x65 } -- "Chairface"

-- Initialize compression
function Comp:Initialize()
    if LibCompress then
        self.available = true
        -- Get encoder for safe transmission (handles special characters)
        if LibCompressEncode then
            self.encoder = LibCompressEncode:GetAddonEncodeTable()
        end
        BJ:Debug("LibCompress loaded - compression enabled")
    else
        self.available = false
        BJ:Debug("LibCompress not available - compression disabled")
    end
end

-- Compress a string
-- Returns: compressed string (or original if compression unavailable/ineffective)
function Comp:Compress(data)
    if not self.available or not data or data == "" then
        return data, false
    end
    
    -- Only compress if data is substantial enough
    if #data < 50 then
        return data, false
    end
    
    local compressed = LibCompress:CompressHuffman(data)
    if not compressed then
        return data, false
    end
    
    -- Encode for safe transmission if encoder available
    if self.encoder then
        compressed = self.encoder:Encode(compressed)
    end
    
    -- Only use compressed version if it's actually smaller
    -- Add 1 byte for compression marker
    if #compressed + 1 < #data then
        return "~" .. compressed, true  -- ~ prefix marks compressed data
    end
    
    return data, false
end

-- Decompress a string
-- Returns: decompressed string
function Comp:Decompress(data)
    if not data or data == "" then
        return data
    end
    
    -- Check for compression marker
    if data:sub(1, 1) ~= "~" then
        return data  -- Not compressed
    end
    
    if not self.available then
        BJ:Debug("Received compressed data but LibCompress not available!")
        return nil  -- Can't decompress
    end
    
    -- Remove compression marker
    local compressed = data:sub(2)
    
    -- Decode if encoder was used
    if self.encoder then
        compressed = self.encoder:Decode(compressed)
    end
    
    -- Decompress
    local decompressed = LibCompress:Decompress(compressed)
    if not decompressed then
        BJ:Debug("Failed to decompress data")
        return nil
    end
    
    return decompressed
end

-- Check if compression is available
function Comp:IsAvailable()
    return self.available
end

-- Get compression stats for debugging
function Comp:GetStats(original, compressed)
    if not original or not compressed then
        return "N/A"
    end
    local ratio = (1 - (#compressed / #original)) * 100
    return string.format("%d -> %d bytes (%.1f%% reduction)", #original, #compressed, ratio)
end

--[[
    PERSISTENT DATA ENCODING
    XOR + Base64 encoding to discourage casual editing of saved data
    NOT cryptographically secure - just obfuscation
]]

-- Base64 encoding table
local b64chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'

-- Base64 encode
local function base64Encode(data)
    return ((data:gsub('.', function(x) 
        local r, b = '', x:byte()
        for i = 8, 1, -1 do r = r .. (b % 2^i - b % 2^(i-1) > 0 and '1' or '0') end
        return r
    end) .. '0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
        if #x < 6 then return '' end
        local c = 0
        for i = 1, 6 do c = c + (x:sub(i, i) == '1' and 2^(6-i) or 0) end
        return b64chars:sub(c+1, c+1)
    end) .. ({ '', '==', '=' })[#data % 3 + 1])
end

-- Base64 decode
local function base64Decode(data)
    data = string.gsub(data, '[^'..b64chars..'=]', '')
    return (data:gsub('.', function(x)
        if x == '=' then return '' end
        local r, f = '', (b64chars:find(x) - 1)
        for i = 6, 1, -1 do r = r .. (f % 2^i - f % 2^(i-1) > 0 and '1' or '0') end
        return r
    end):gsub('%d%d%d?%d?%d?%d?%d?%d?', function(x)
        if #x ~= 8 then return '' end
        local c = 0
        for i = 1, 8 do c = c + (x:sub(i, i) == '1' and 2^(8-i) or 0) end
        return string.char(c)
    end))
end

-- XOR obfuscation
local function xorData(data)
    local result = {}
    for i = 1, #data do
        local keyByte = XOR_KEY[((i - 1) % #XOR_KEY) + 1]
        local dataByte = string.byte(data, i)
        table.insert(result, string.char(bit.bxor(dataByte, keyByte)))
    end
    return table.concat(result)
end

-- Encode data for saving (serialize -> compress -> XOR -> base64)
function Comp:EncodeForSave(data)
    if not data then return nil end
    
    -- Serialize the table to string using AceSerializer
    local serialized
    if type(data) == "table" then
        if AceSerializer then
            serialized = AceSerializer:Serialize(data)
        else
            BJ:Debug("AceSerializer not available for encoding!")
            return nil
        end
    else
        serialized = tostring(data)
    end
    
    if not serialized then return nil end
    
    -- Compress if available and worthwhile
    local toEncode = serialized
    local wasCompressed = false
    if self.available and #serialized >= 50 then
        local compressed = LibCompress:CompressHuffman(serialized)
        if compressed and #compressed < #serialized then
            toEncode = compressed
            wasCompressed = true
        end
    end
    
    -- XOR obfuscate
    local xored = xorData(toEncode)
    
    -- Base64 encode
    local encoded = base64Encode(xored)
    
    -- Add marker prefix (CC1 = uncompressed, CC2 = compressed)
    local prefix = wasCompressed and "CC2:" or "CC1:"
    return prefix .. encoded
end

-- Decode saved data (base64 -> XOR -> decompress -> deserialize)
function Comp:DecodeFromSave(encoded)
    if not encoded then return nil end
    
    -- Check for marker
    if type(encoded) ~= "string" then return nil end
    
    local prefix = encoded:sub(1, 4)
    local wasCompressed = false
    
    if prefix == "CC2:" then
        wasCompressed = true
    elseif prefix ~= "CC1:" then
        return nil  -- Not encoded data or wrong format
    end
    
    -- Remove marker
    local data = encoded:sub(5)
    
    -- Base64 decode
    local decoded = base64Decode(data)
    if not decoded or decoded == "" then return nil end
    
    -- XOR de-obfuscate
    local deobfuscated = xorData(decoded)
    
    -- Decompress if needed
    local serialized = deobfuscated
    if wasCompressed then
        if not self.available then
            BJ:Debug("Cannot decompress - LibCompress not available!")
            return nil
        end
        serialized = LibCompress:Decompress(deobfuscated)
        if not serialized then
            BJ:Debug("Failed to decompress saved data")
            return nil
        end
    end
    
    -- Deserialize using AceSerializer
    if AceSerializer then
        local success, result = AceSerializer:Deserialize(serialized)
        if success then
            return result
        end
    end
    
    return nil
end
