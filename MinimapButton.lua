--[[
    Chairface's Casino - MinimapButton.lua
    Free-floating button to open/close the addon (can be placed anywhere on screen)
]]

local BJ = ChairfacesCasino
BJ.MinimapButton = {}
local MB = BJ.MinimapButton

-- Button state
MB.isDragging = false
MB.defaultX = nil  -- Will be calculated to position near minimap
MB.defaultY = nil

-- Create the button
function MB:Create()
    if self.button then return end
    
    -- Create as a free-floating frame (parented to UIParent, not Minimap)
    -- Size is 1.75x the original (32 * 1.75 = 56)
    local button = CreateFrame("Button", "ChairfacesCasinoMinimapButton", UIParent)
    button:SetSize(56, 56)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:SetMovable(true)
    button:EnableMouse(true)
    button:RegisterForDrag("LeftButton")
    button:SetClampedToScreen(true)
    
    -- Icon texture (1.75x size, no border)
    local background = button:CreateTexture(nil, "ARTWORK")
    background:SetSize(56, 56)
    background:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\icon")
    background:SetPoint("CENTER", 0, 0)
    button.background = background
    
    -- Highlight on hover
    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetSize(56, 56)
    highlight:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\icon")
    highlight:SetPoint("CENTER", 0, 0)
    highlight:SetAlpha(0.3)
    highlight:SetBlendMode("ADD")
    
    -- Tooltip and hover scaling
    button:SetScript("OnEnter", function(self)
        if not MB.isDragging then
            -- Scale up slightly on hover
            local scale = MB.currentScale or 1.5
            local hoverScale = scale * 1.15  -- 15% larger on hover
            local baseSize = 32
            self:SetSize(baseSize * hoverScale, baseSize * hoverScale)
            if self.overlay then
                self.overlay:SetSize(53 * hoverScale, 53 * hoverScale)
            end
            if self.background then
                self.background:SetSize(20 * hoverScale, 20 * hoverScale)
            end
            
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:AddLine("Chairface's Casino", 1, 0.84, 0)
            GameTooltip:AddLine(" ", 1, 1, 1)
            GameTooltip:AddLine("|cffffffffLeft-click:|r Casino Lobby", 0.8, 0.8, 0.8)
            GameTooltip:AddLine("|cffffffffRight-click:|r Settings", 0.8, 0.8, 0.8)
            GameTooltip:AddLine("|cffffffffDrag:|r Move icon anywhere", 0.8, 0.8, 0.8)
            
            -- Show session status if active
            if BJ.SessionManager and BJ.SessionManager.isLocked then
                GameTooltip:AddLine(" ", 1, 1, 1)
                local host = BJ.SessionManager:GetHost()
                if host then
                    GameTooltip:AddLine("Active table: " .. host, 0, 1, 0)
                end
            end
            
            GameTooltip:Show()
        end
    end)
    
    button:SetScript("OnLeave", function(self)
        -- Return to normal size
        local scale = MB.currentScale or 1.5
        local baseSize = 32
        self:SetSize(baseSize * scale, baseSize * scale)
        if self.overlay then
            self.overlay:SetSize(53 * scale, 53 * scale)
        end
        if self.background then
            self.background:SetSize(20 * scale, 20 * scale)
        end
        
        GameTooltip:Hide()
    end)
    
    -- Click handler
    button:SetScript("OnClick", function(self, btn)
        if MB.isDragging then return end
        
        if btn == "LeftButton" then
            -- Toggle casino lobby (and hide game windows if shown)
            if BJ.UI then
                -- Check if any game windows are visible
                local bjVisible = BJ.UI.mainFrame and BJ.UI.mainFrame:IsShown()
                local pokerVisible = BJ.UI.Poker and BJ.UI.Poker.mainFrame and BJ.UI.Poker.mainFrame:IsShown()
                local lobbyVisible = BJ.UI.Lobby and BJ.UI.Lobby.frame and BJ.UI.Lobby.frame:IsShown()
                
                if bjVisible or pokerVisible then
                    -- Hide game windows
                    if bjVisible then BJ.UI:Hide() end
                    if pokerVisible then BJ.UI.Poker:Hide() end
                elseif lobbyVisible then
                    -- Toggle lobby off
                    BJ.UI.Lobby:Hide()
                else
                    -- Show lobby
                    BJ.UI:ShowLobby()
                end
            end
        elseif btn == "RightButton" then
            -- Open settings panel in lobby
            if BJ.UI and BJ.UI.Lobby then
                BJ.UI:ShowLobby()
                BJ.UI.Lobby:ShowSettings()
            end
        end
    end)
    
    -- Drag handlers - free floating anywhere on screen
    button:SetScript("OnDragStart", function(self)
        MB.isDragging = true
        GameTooltip:Hide()
        self:StartMoving()
    end)
    
    button:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        MB.isDragging = false
        MB:SavePosition()
    end)
    
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    
    self.button = button
    
    -- Load saved position
    self:LoadPosition()
end

-- Save position to saved variables (x, y from CENTER of screen)
function MB:SavePosition()
    if not self.button then return end
    if not ChairfacesCasinoDB then
        ChairfacesCasinoDB = {}
    end
    
    local point, relativeTo, relativePoint, x, y = self.button:GetPoint()
    ChairfacesCasinoDB.minimapPosX = x
    ChairfacesCasinoDB.minimapPosY = y
    ChairfacesCasinoDB.minimapPosPoint = point
    ChairfacesCasinoDB.minimapPosRelPoint = relativePoint
end

-- Load position from saved variables
function MB:LoadPosition()
    if not self.button then return end
    
    self.button:ClearAllPoints()
    
    if ChairfacesCasinoDB and ChairfacesCasinoDB.minimapPosX then
        -- Load saved position
        local point = ChairfacesCasinoDB.minimapPosPoint or "CENTER"
        local relPoint = ChairfacesCasinoDB.minimapPosRelPoint or "CENTER"
        local x = ChairfacesCasinoDB.minimapPosX
        local y = ChairfacesCasinoDB.minimapPosY
        self.button:SetPoint(point, UIParent, relPoint, x, y)
    else
        -- Default position: near top-right (near default minimap position)
        self.button:SetPoint("CENTER", Minimap, "CENTER", -80, 0)
    end
end

-- Show/hide the button
function MB:Show()
    if self.button then
        self.button:Show()
    end
end

function MB:Hide()
    if self.button then
        self.button:Hide()
    end
end

function MB:Toggle()
    if self.button then
        if self.button:IsShown() then
            self.button:Hide()
            if ChairfacesCasinoDB then
                ChairfacesCasinoDB.minimapHidden = true
            end
        else
            self.button:Show()
            if ChairfacesCasinoDB then
                ChairfacesCasinoDB.minimapHidden = false
            end
        end
    end
end

-- Initialize
function MB:Initialize()
    self:Create()
    
    -- Check if should be hidden
    if ChairfacesCasinoDB and ChairfacesCasinoDB.minimapHidden then
        self:Hide()
    end
    
    -- Apply saved scale (default to 1.5 if not set)
    local scale = 1.5
    if ChairfacesCasinoDB and ChairfacesCasinoDB.settings and ChairfacesCasinoDB.settings.minimapScale then
        scale = ChairfacesCasinoDB.settings.minimapScale
    end
    
    self.currentScale = scale  -- Store for hover sizing
    
    if self.button then
        local baseSize = 32
        local newSize = baseSize * scale
        self.button:SetSize(newSize, newSize)
        
        if self.button.overlay then
            local overlaySize = 53 * scale
            self.button.overlay:SetSize(overlaySize, overlaySize)
        end
        if self.button.background then
            local bgSize = 20 * scale
            self.button.background:SetSize(bgSize, bgSize)
        end
    end
end
