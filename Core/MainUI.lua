local _, TPP = ...

TPP.MainUI = {}

local MainUI = TPP.MainUI
local Utils = TPP.Utils
local Data = TPP.Data

local mainFrame, timeText, todayText, charCheckbox

function MainUI.Create()
    mainFrame = Utils.CreateStyledFrame("TimePlayed+MainFrame", 260, 180)
    if not (TPP.db and TPP.db.profile and TPP.db.profile.positions["TimePlayed+MainFrame"]) then
        mainFrame:ClearAllPoints()
        mainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 300)
    end

    -- title
    local title = Utils.CreateFontString(mainFrame, 11, "TOP", mainFrame, "TOP", 0, -12)
    title:SetText("TimePlayed+")
    title:SetTextColor(1, 0.82, 0)

    -- label
    local label = Utils.CreateFontString(mainFrame, 10, "TOP", title, "BOTTOM", 0, -8)
    label:SetText("Today's Playtime:")

    -- today total (hero number)
    todayText = Utils.CreateFontString(mainFrame, 16, "TOP", label, "BOTTOM", 0, -6)
    todayText:SetText("0s")

    -- session time (secondary, faint)
    timeText = Utils.CreateFontString(mainFrame, 10, "TOP", todayText, "BOTTOM", 0, -6)
    timeText:SetText("Session: 0s")
    timeText:SetTextColor(0.6, 0.6, 0.6)

    -- buttons
    local statsBtn = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    statsBtn:SetSize(110, 24)
    statsBtn:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 16, -106)
    statsBtn:SetText("Stats")
    statsBtn:SetScript("OnClick", function() TPP.StatsUI.Toggle() end)

    local historyBtn = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    historyBtn:SetSize(110, 24)
    historyBtn:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -16, -106)
    historyBtn:SetText("History")
    historyBtn:SetScript("OnClick", function() TPP.HistoryUI.Toggle() end)

    -- character filter checkbox
    charCheckbox = CreateFrame("CheckButton", "TPPCharCheckbox", mainFrame, "UICheckButtonTemplate")
    charCheckbox:SetSize(24, 24)
    charCheckbox:SetPoint("BOTTOMLEFT", mainFrame, "BOTTOMLEFT", 12, 8)
    charCheckbox.text = charCheckbox.text or _G["TPPCharCheckboxText"] or charCheckbox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    charCheckbox.text:SetPoint("LEFT", charCheckbox, "RIGHT", 2, 0)
    charCheckbox.text:SetText("Current character only")
    charCheckbox:SetScript("OnClick", function(self)
        TPP.characterFilter = self:GetChecked() and Utils.GetCharacterKey() or nil
        MainUI.UpdateTimeDisplay()
        if TPP.StatsUI.Refresh then TPP.StatsUI.Refresh() end
        if TPP.HistoryUI.Refresh then TPP.HistoryUI.Refresh() end
    end)

    -- close button
    local closeBtn = CreateFrame("Button", nil, mainFrame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -2, -2)

    -- update ticker - compute elapsed on demand, no coroutine
    local ticker = C_Timer.NewTicker(1, function()
        if not mainFrame:IsShown() then return end
        MainUI.UpdateTimeDisplay()
    end)

    return mainFrame
end

function MainUI.UpdateTimeDisplay()
    if not todayText or not TPP.db then return end

    -- today is the hero
    local todayTotal = Data.GetTodayTotal(TPP.db, TPP.characterFilter)
    todayText:SetText(Utils.SecondsToHMS(todayTotal))
    local r, g, b = Utils.GetColorForDailyTime(todayTotal)
    todayText:SetTextColor(r, g, b)

    -- session is secondary
    if timeText then
        local duration = Data.GetSessionDuration()
        timeText:SetText("Session: " .. Utils.SecondsToHMS(duration))
    end
end

function MainUI.Toggle()
    if mainFrame:IsShown() then
        for _, frame in ipairs(TPP.frames) do
            frame:Hide()
        end
    else
        MainUI.UpdateTimeDisplay()
        mainFrame:Show()
    end
end

function MainUI.ShowCSV()
    if not TPP.csvFrame then
        TPP.csvFrame = Utils.CreateStyledFrame("TimePlayed+CSVFrame", 620, 220)

        local scrollFrame = CreateFrame("ScrollFrame", "TPPCSVScroll", TPP.csvFrame, "UIPanelScrollFrameTemplate")
        scrollFrame:SetPoint("TOPLEFT", 10, -10)
        scrollFrame:SetPoint("BOTTOMRIGHT", -30, 10)

        local editBox = CreateFrame("EditBox", "TPPCSVEditBox", scrollFrame)
        editBox:SetMultiLine(true)
        editBox:SetFontObject("ChatFontNormal")
        editBox:SetWidth(570)
        editBox:SetAutoFocus(false)
        scrollFrame:SetScrollChild(editBox)

        TPP.csvEditBox = editBox

        local closeBtn = CreateFrame("Button", nil, TPP.csvFrame, "UIPanelCloseButton")
        closeBtn:SetPoint("TOPRIGHT", TPP.csvFrame, "TOPRIGHT", -2, -2)
    end

    TPP.csvEditBox:SetText(Data.GetCSV(TPP.db, TPP.characterFilter))
    TPP.csvEditBox:HighlightText()
    TPP.csvFrame:Show()
end

function MainUI.GetFrame()
    return mainFrame
end
