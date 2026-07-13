--[[
    Chairface's Casino - SessionManager.lua
    Manages session locking to prevent multiple simultaneous games
]]

local BJ = ChairfacesCasino
BJ.SessionManager = {}
local SM = BJ.SessionManager

-- Session state
SM.activeSession = nil  -- { host = "name", startTime = time, settings = {} }
SM.isLocked = false
SM.lockTimeout = 300  -- 5 minutes max session lock

-- Message types for session management
SM.MSG = {
    SESSION_START = "SESS_START",
    SESSION_END = "SESS_END",
    SESSION_QUERY = "SESS_QUERY",
    SESSION_RESPONSE = "SESS_RESP",
    SESSION_RESET = "SESS_RESET",
}

-- Initialize session manager
function SM:Initialize()
    self.activeSession = nil
    self.isLocked = false
end

-- Check if we can start a new session
function SM:CanStartSession()
    if not self.isLocked then
        return true, nil
    end
    
    -- Check for timeout
    if self.activeSession and self.activeSession.startTime then
        local elapsed = time() - self.activeSession.startTime
        if elapsed > self.lockTimeout then
            BJ:Print("Previous session timed out. Clearing lock.")
            self:ClearSession()
            return true, nil
        end
    end
    
    local reason = "A session is already active"
    if self.activeSession and self.activeSession.host then
        reason = reason .. " (hosted by " .. self.activeSession.host .. ")"
    end
    
    return false, reason
end

-- Start a new session (as host)
function SM:StartSession(hostName, settings)
    local canStart, reason = self:CanStartSession()
    if not canStart then
        return false, reason
    end
    
    self.activeSession = {
        host = hostName,
        startTime = time(),
        settings = settings,
    }
    self.isLocked = true
    
    -- Broadcast session start
    BJ.Multiplayer:BroadcastSessionStart(settings)
    
    BJ:Debug("Session started by " .. hostName)
    return true
end

-- End current session
function SM:EndSession()
    if not self.activeSession then
        -- Even without active session, clear the lock
        self.isLocked = false
        return
    end
    
    local wasHost = self.activeSession.host == UnitName("player")
    
    self:ClearSession()
    
    -- Broadcast session end if we were the host
    if wasHost then
        BJ.Multiplayer:BroadcastSessionEnd()
    end
    
    BJ:Debug("Session ended")
end

-- Clear session state
function SM:ClearSession()
    self.activeSession = nil
    self.isLocked = false
end

-- Handle incoming session start from another player
function SM:OnRemoteSessionStart(hostName, settings)
    if self.isLocked and self.activeSession and self.activeSession.host ~= hostName then
        -- Conflict - another session was already active
        BJ:Debug("Session conflict: " .. hostName .. " tried to start but " .. 
            self.activeSession.host .. " already has a session")
        return false
    end
    
    self.activeSession = {
        host = hostName,
        startTime = time(),
        settings = settings,
    }
    self.isLocked = true
    
    BJ:Debug("Remote session started by " .. hostName)
    return true
end

-- Handle incoming session end
function SM:OnRemoteSessionEnd(hostName)
    if self.activeSession and self.activeSession.host == hostName then
        self:ClearSession()
        BJ:Debug("Remote session ended by " .. hostName)
    end
end

-- Force reset session (for stuck sessions)
function SM:ForceReset()
    local wasLocked = self.isLocked
    local oldHost = self.activeSession and self.activeSession.host or "unknown"
    
    self:ClearSession()
    
    -- Broadcast reset to all
    BJ.Multiplayer:BroadcastSessionReset()
    
    if wasLocked then
        BJ:Print("Session forcibly reset. Previous host was: " .. oldHost)
    else
        BJ:Print("No active session to reset.")
    end
end

-- Check if current player is the host
function SM:IsHost()
    return self.activeSession and self.activeSession.host == UnitName("player")
end

-- Get current host name
function SM:GetHost()
    return self.activeSession and self.activeSession.host or nil
end

-- Get session settings
function SM:GetSettings()
    return self.activeSession and self.activeSession.settings or nil
end

-- Get session age in seconds
function SM:GetSessionAge()
    if not self.activeSession or not self.activeSession.startTime then
        return 0
    end
    return time() - self.activeSession.startTime
end

-- Get formatted session info
function SM:GetSessionInfo()
    if not self.activeSession then
        return "No active session"
    end
    
    local info = "Host: " .. self.activeSession.host
    info = info .. " | Duration: " .. self:GetSessionAge() .. "s"
    
    if self.activeSession.settings then
        local s = self.activeSession.settings
        info = info .. " | Ante: " .. (s.ante or "?") .. "g"
    end
    
    return info
end
