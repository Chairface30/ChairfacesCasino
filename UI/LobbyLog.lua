--[[
    Chairface's Casino - UI/LobbyLog.lua
    The casino log: a small chat-style window every BJ:Print / BJ:Debug
    line is copied into.
    Part of the lobby module (UI.Lobby), split out of UI/Lobby.lua.
]]

local BJ = ChairfacesCasino
local UI = BJ.UI
local Lobby = UI.Lobby

-- ========== LOG WINDOW ==========
function Lobby:CreateLogWindow()
    if self.logFrame then return end
    
    -- Shared casino window (UI/Chrome.lua): a small resizable chat-style log
    local frame = UI.Chrome:CreateWindow({
        name = "ChairfacesCasinoLog",
        title = "Casino Log",
        width = 350, height = 200,
        strata = "MEDIUM",
        noLobby = true,
    })
    frame.titleText:SetFontObject("CCFontNormal")
    frame:ClearAllPoints()
    frame:SetPoint("BOTTOMLEFT", 20, 200)
    frame:SetResizable(true)
    frame:SetResizeBounds(200, 100, 600, 400)
    local closeBtn = frame.closeBtn
    local clearBtn = UI.Chrome:HeaderButton(frame, "Clear", 50, function() Lobby:ClearLog() end)
    frame:AddHeaderRight(clearBtn)

    -- ScrollingMessageFrame supports |H...|h hyperlinks (FontString does not)
    local messageFrame = CreateFrame("ScrollingMessageFrame", nil, frame)
    messageFrame:SetPoint("TOPLEFT", 8, frame.BODY_TOP - 6)
    messageFrame:SetPoint("BOTTOMRIGHT", -8, 8)
    messageFrame:SetFontObject("CCFontSmall")
    messageFrame:SetJustifyH("LEFT")
    messageFrame:SetMaxLines(100)
    messageFrame:SetFading(false)
    messageFrame:SetHyperlinksEnabled(true)
    messageFrame:EnableMouseWheel(true)
    messageFrame:SetScript("OnMouseWheel", function(self, delta)
        if delta > 0 then
            if IsShiftKeyDown() then self:ScrollToTop() else self:ScrollUp() end
        else
            if IsShiftKeyDown() then self:ScrollToBottom() else self:ScrollDown() end
        end
    end)
    messageFrame:SetScript("OnHyperlinkClick", function(self, link, text, button)
        local linkType, game = strsplit(":", link)
        if linkType == "casinolink" then
            if game == "hilo" and BJ.UI and BJ.UI.HiLo then BJ.UI.HiLo:Show()
            elseif game == "blackjack" and BJ.UI and BJ.UI.Show then BJ.UI:Show()
            elseif game == "poker" and BJ.UI and BJ.UI.Poker then BJ.UI.Poker:Show()
            end
        else
            SetItemRef(link, text, button, self)
        end
    end)

    frame.messageFrame = messageFrame

    -- Resize handle
    local resizeBtn = CreateFrame("Button", nil, frame)
    resizeBtn:SetSize(16, 16)
    resizeBtn:SetPoint("BOTTOMRIGHT", -2, 2)
    resizeBtn:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeBtn:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeBtn:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")

    resizeBtn:SetScript("OnMouseDown", function()
        frame:StartSizing("BOTTOMRIGHT")
    end)
    resizeBtn:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
    end)

    frame:Hide()
    self.logFrame = frame
end

function Lobby:AddLogMessage(msg)
    if not self.logFrame then
        self:CreateLogWindow()
    end
    self.logFrame.messageFrame:AddMessage(tostring(msg))
    self.logFrame.messageFrame:ScrollToBottom()
end

function Lobby:ClearLog()
    if not self.logFrame then return end
    self.logFrame.messageFrame:Clear()
end

function Lobby:ShowLog()
    if not self.logFrame then
        self:CreateLogWindow()
    end
    self.logFrame:Show()
end

function Lobby:HideLog()
    if self.logFrame then
        self.logFrame:Hide()
    end
end

function Lobby:ToggleLog()
    if not self.logFrame then
        self:CreateLogWindow()
    end
    if self.logFrame:IsShown() then
        self.logFrame:Hide()
    else
        self.logFrame:Show()
    end
end
