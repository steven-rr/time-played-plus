local addonName, TPP = ...

local addon = LibStub("AceAddon-3.0"):NewAddon(addonName, "AceConsole-3.0")

TPP.characterFilter = nil

local dbDefaults = {
    global = {
        sessions = {},
        pendingSession = nil,
        serverCheckpoints = {},
    },
    profile = {
        minimap = {
            hide = false,
        },
        scale = 1.0,
        colorTimer = true,
        positions = {},
    },
}

function addon:OnInitialize()
    TPP.db = LibStub("AceDB-3.0"):New("TimePlayed_PlusDB", dbDefaults, true)

    -- create UI
    TPP.MainUI.Create()
    TPP.StatsUI.Create()
    TPP.HistoryUI.Create()
    TPP.Minimap.Setup(TPP.db)

    -- register options panel
    TPP.Options.Setup()

    -- apply saved scale
    TPP.Utils.ApplyScale(TPP.db.profile.scale)
end

-- suppress "Total time played" chat message during our request
local chatFramesUnregistered = {}

local function SuppressChatTimePlayed()
    for i = 1, 10 do
        local cf = _G["ChatFrame" .. i]
        if cf and cf:IsEventRegistered("TIME_PLAYED_MSG") then
            cf:UnregisterEvent("TIME_PLAYED_MSG")
            chatFramesUnregistered[cf] = true
        end
    end
end

local function RestoreChatTimePlayed()
    for cf in pairs(chatFramesUnregistered) do
        cf:RegisterEvent("TIME_PLAYED_MSG")
    end
    chatFramesUnregistered = {}
end

function addon:OnEnable()
    -- recover any pending session (player data is now available)
    TPP.Data.RecoverPendingSession(TPP.db)

    -- start tracking (UnitName/GetRealmName are reliable here)
    TPP.Data.StartSession()

    -- request server time for crash recovery cross-check (delayed to avoid login spam)
    TPP.Data.serverTimeRequested = true
    C_Timer.After(5, function()
        SuppressChatTimePlayed()
        RequestTimePlayed()
        -- safety: restore chat frames after 10 seconds in case TIME_PLAYED_MSG never fires
        C_Timer.After(10, function()
            RestoreChatTimePlayed()
        end)
    end)

    -- register slash commands
    local function handleSlash(input)
        local cmd = (input or ""):match("^%s*(%S+)") or ""
        cmd = cmd:lower()
        if cmd == "options" or cmd == "config" or cmd == "settings" then
            TPP.Options.Open()
        else
            TPP.MainUI.Toggle()
        end
    end
    self:RegisterChatCommand("tpp", handleSlash)
    self:RegisterChatCommand("timeplayed", handleSlash)
end

-- AFK tracking
local function SafeUnitIsAFK()
    local success, result = pcall(function()
        if UnitIsAFK("player") then return true end
        return false
    end)
    return success, (success and result)
end

local afkFrame = CreateFrame("Frame")
afkFrame:RegisterEvent("PLAYER_FLAGS_CHANGED")
afkFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
afkFrame:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_ENTERING_WORLD" then
        afkFrame:UnregisterEvent("PLAYER_ENTERING_WORLD")
        local success, isAFK = SafeUnitIsAFK()
        if success and isAFK and TPP.Data.sessionStart then
            TPP.Data.afkStart = TPP.Data.sessionStart
        end
        return
    end
    if unit ~= "player" then return end
    local success, isAFK = SafeUnitIsAFK()
    if not success then return end
    if isAFK then
        TPP.Data.OnAFKStart()
    else
        TPP.Data.OnAFKEnd()
    end
end)

-- server time cross-check for crash recovery
local timePlayedFrame = CreateFrame("Frame")
timePlayedFrame:RegisterEvent("TIME_PLAYED_MSG")
timePlayedFrame:SetScript("OnEvent", function(_, _, totalTime)
    if TPP.Data.serverTimeRequested then
        TPP.Data.serverTimeRequested = false
        RestoreChatTimePlayed()
        if totalTime and totalTime > 0 then
            TPP.Data.OnServerTimePlayed(totalTime, TPP.db)
        end
    end
end)

-- save on logout
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGOUT")
eventFrame:RegisterEvent("PLAYER_LEAVING_WORLD")
eventFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGOUT" then
        TPP.Data.SaveSession(TPP.db)
        TPP.db.global.pendingSession = nil
    elseif event == "PLAYER_LEAVING_WORLD" then
        TPP.Data.SavePendingSession(TPP.db)
    end
end)
