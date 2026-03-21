local addonName, TPP = ...

local addon = LibStub("AceAddon-3.0"):NewAddon(addonName, "AceConsole-3.0")

TPP.characterFilter = nil

local dbDefaults = {
    global = {
        sessions = {},
        pendingSession = nil,
    },
    profile = {
        minimap = {
            hide = false,
        },
        scale = 1.0,
        positions = {},
    },
}

function addon:OnInitialize()
    TPP.db = LibStub("AceDB-3.0"):New("TimePlayed_PlusDB", dbDefaults, true)

    -- recover any pending session from a UI reload
    TPP.Data.RecoverPendingSession(TPP.db)

    -- create UI
    TPP.MainUI.Create()
    TPP.StatsUI.Create()
    TPP.HistoryUI.Create()
    TPP.Minimap.Setup(TPP.db)

    -- register options panel
    TPP.Options.Setup()

    -- apply saved scale
    TPP.Utils.ApplyScale(TPP.db.profile.scale)

    -- start tracking
    TPP.Data.StartSession()

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
local afkFrame = CreateFrame("Frame")
afkFrame:RegisterEvent("PLAYER_FLAGS_CHANGED")
afkFrame:SetScript("OnEvent", function(_, _, unit)
    if unit ~= "player" then return end
    if UnitIsAFK("player") then
        TPP.Data.OnAFKStart()
    else
        TPP.Data.OnAFKEnd()
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
