local _, TPP = ...

TPP.StatsUI = {}

local StatsUI = TPP.StatsUI
local Utils = TPP.Utils
local Data = TPP.Data

local statsFrame, avgText, recentAvgText, longestText

function StatsUI.Create()
    statsFrame = Utils.CreateStyledFrame("TimePlayed+StatsFrame", 300, 180)

    local title = Utils.CreateFontString(statsFrame, 11, "TOP", statsFrame, "TOP", 0, -12)
    title:SetText("Playtime Stats")
    title:SetTextColor(1, 0.82, 0)

    -- daily average
    local avgLabel = Utils.CreateFontString(statsFrame, 10, "TOPLEFT", statsFrame, "TOPLEFT", 16, -36)
    avgLabel:SetText("Daily Average:")
    avgText = Utils.CreateFontString(statsFrame, 10, "LEFT", avgLabel, "RIGHT", 8, 0)

    -- 7-day average
    local recentLabel = Utils.CreateFontString(statsFrame, 10, "TOPLEFT", avgLabel, "BOTTOMLEFT", 0, -10)
    recentLabel:SetText("Last 7 Days Avg:")
    recentAvgText = Utils.CreateFontString(statsFrame, 10, "LEFT", recentLabel, "RIGHT", 8, 0)

    -- longest session
    local longestLabel = Utils.CreateFontString(statsFrame, 10, "TOPLEFT", recentLabel, "BOTTOMLEFT", 0, -10)
    longestLabel:SetText("Longest Session:")
    longestText = Utils.CreateFontString(statsFrame, 10, "LEFT", longestLabel, "RIGHT", 8, 0)

    -- share button
    local shareBtn = CreateFrame("Button", nil, statsFrame, "UIPanelButtonTemplate")
    shareBtn:SetSize(110, 24)
    shareBtn:SetPoint("BOTTOM", statsFrame, "BOTTOM", 0, 10)
    shareBtn:SetText("Share")
    shareBtn:SetScript("OnClick", function()
        local url = Data.GenerateShareURL(TPP.db, TPP.characterFilter)
        TPP.MainUI.ShowCopyableText("Share Your Stats", url)
    end)

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

    local overallAvg, recentAvg = Data.GetDailyAverages(TPP.db)
    local longest = Data.GetLongestSession(TPP.db, TPP.characterFilter)

    avgText:SetText(Utils.GetColorHexForTime(overallAvg) .. Utils.SecondsToHMS(overallAvg) .. "|r")
    recentAvgText:SetText(Utils.GetColorHexForTime(recentAvg) .. Utils.SecondsToHMS(recentAvg) .. "|r")
    longestText:SetText(Utils.GetColorHexForTime(longest) .. Utils.SecondsToHMS(longest) .. "|r")
end

function StatsUI.Toggle()
    if statsFrame:IsShown() then
        statsFrame:Hide()
    else
        StatsUI.Refresh()
        statsFrame:Show()
    end
end
