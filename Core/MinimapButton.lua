local _, TPP = ...

TPP.Minimap = {}

local Minimap = TPP.Minimap
local Utils = TPP.Utils
local Data = TPP.Data

function Minimap.Setup(db)
    local LDB = LibStub("LibDataBroker-1.1")
    local LDBIcon = LibStub("LibDBIcon-1.0")

    local dataObj = LDB:NewDataObject("TimePlayed+", {
        type = "data source",
        text = "TimePlayed+",
        icon = "Interface/Icons/INV_Misc_PocketWatch_01",
        OnClick = function(_, button)
            if button == "LeftButton" then
                TPP.MainUI.Toggle()
            elseif button == "RightButton" then
                TPP.Options.Open()
            end
        end,
        OnTooltipShow = function(tooltip)
            local sessionDuration = Data.GetSessionDuration()
            local todayTotal = Data.GetTodayTotal(db)

            local sessionColor = Utils.GetColorHexForTime(sessionDuration)
            local todayColor = Utils.GetColorHexForDailyTime(todayTotal)

            tooltip:AddLine("TimePlayed+", 1, 0.82, 0)
            tooltip:AddLine(" ")
            tooltip:AddLine("Session: " .. sessionColor .. Utils.SecondsToHMS(sessionDuration) .. "|r")
            tooltip:AddLine("Today: " .. todayColor .. Utils.SecondsToHMS(todayTotal) .. "|r")
            tooltip:AddLine(" ")
            tooltip:AddLine("|cff888888Left-click to toggle|r")
            tooltip:AddLine("|cff888888Right-click for options|r")
        end,
    })

    LDBIcon:Register("TimePlayed+", dataObj, db.profile.minimap)
end
