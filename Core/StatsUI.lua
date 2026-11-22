local _, TPP = ...

TPP.StatsUI = {}

local StatsUI = TPP.StatsUI
local Utils = TPP.Utils
local Data = TPP.Data

local statsFrame, periodText, avgText, recentAvgText, longestText

function StatsUI.Create()
    statsFrame = Utils.CreateStyledFrame("TimePlayed+StatsFrame", 300, 160)

    local title = Utils.CreateFontString(statsFrame, 11, "TOP", statsFrame, "TOP", 0, -12)
    title:SetText("Playtime Stats")
    title:SetTextColor(1, 0.82, 0)

    -- 7-day average: always the last seven days, so it stands above the season line
    local recentLabel = Utils.CreateFontString(statsFrame, 10, "TOPLEFT", statsFrame, "TOPLEFT", 16, -36)
    recentLabel:SetText("Last 7 Days Avg:")
    recentAvgText = Utils.CreateFontString(statsFrame, 10, "LEFT", recentLabel, "RIGHT", 8, 0)

    -- which period the two numbers under it cover, and the first day recorded in it
    periodText = Utils.CreateFontString(statsFrame, 9, "TOPLEFT", statsFrame, "TOPLEFT", 16, -64)
    periodText:SetTextColor(0.6, 0.6, 0.6)

    -- daily average
    local avgLabel = Utils.CreateFontString(statsFrame, 10, "TOPLEFT", statsFrame, "TOPLEFT", 16, -80)
    avgLabel:SetText("Daily Average:")
    avgText = Utils.CreateFontString(statsFrame, 10, "LEFT", avgLabel, "RIGHT", 8, 0)

    -- longest session
    local longestLabel = Utils.CreateFontString(statsFrame, 10, "TOPLEFT", avgLabel, "BOTTOMLEFT", 0, -10)
    longestLabel:SetText("Longest Session:")
    longestText = Utils.CreateFontString(statsFrame, 10, "LEFT", longestLabel, "RIGHT", 8, 0)

    local closeBtn = CreateFrame("Button", nil, statsFrame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", statsFrame, "TOPRIGHT", -2, -2)

    -- refresh ticker
    C_Timer.NewTicker(1, function()
        if statsFrame:IsShown() then
            StatsUI.Refresh()
        end
    end)

    return statsFrame
end

function StatsUI.Refresh()
    if not statsFrame or not TPP.db then return end

    local overallAvg, recentAvg, countedFrom = Data.GetDailyAverages(TPP.db, TPP.characterFilter)
    local longest = Data.GetLongestSession(TPP.db, TPP.characterFilter)

    -- the date is the first day recorded in the season, which is where the daily average starts counting
    periodText:SetText(Data.GetSeasonStart(TPP.db)
        and ((Data.GetSeasonName() or "This season") .. ", since " .. Utils.FormatDate(countedFrom))
        or "All time")

    avgText:SetText(Utils.GetColorHexForDailyTime(overallAvg) .. Utils.SecondsToHMS(overallAvg) .. "|r")
    recentAvgText:SetText(Utils.GetColorHexForDailyTime(recentAvg) .. Utils.SecondsToHMS(recentAvg) .. "|r")
    longestText:SetText(Utils.GetColorHexForDailyTime(longest) .. Utils.SecondsToHMS(longest) .. "|r")
end

function StatsUI.Toggle()
    if statsFrame:IsShown() then
        statsFrame:Hide()
    else
        StatsUI.Refresh()
        statsFrame:Show()
    end
end
