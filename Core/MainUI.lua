local _, TPP = ...

TPP.MainUI = {}

local MainUI = TPP.MainUI
local Utils = TPP.Utils
local Data = TPP.Data

local mainFrame, timeText, charCheckbox

function MainUI.Create()
    mainFrame = Utils.CreateStyledFrame("TimePlayed_PlusMainFrame", 260, 200)
    mainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 300)

    -- title
    local title = Utils.CreateFontString(mainFrame, 11, "TOP", mainFrame, "TOP", 0, -12)
    title:SetText("TimePlayed_Plus")
    title:SetTextColor(1, 0.82, 0)

    -- label
    local label = Utils.CreateFontString(mainFrame, 10, "TOP", title, "BOTTOM", 0, -8)
    label:SetText("Session Playtime:")

    -- time display
    timeText = Utils.CreateFontString(mainFrame, 16, "TOP", label, "BOTTOM", 0, -6)
    timeText:SetText("0s")

    -- buttons
    local statsBtn = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    statsBtn:SetSize(110, 24)
    statsBtn:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 16, -90)
    statsBtn:SetText("Stats")
    statsBtn:SetScript("OnClick", function() TPP.StatsUI.Toggle() end)

    local historyBtn = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    historyBtn:SetSize(110, 24)
    historyBtn:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -16, -90)
    historyBtn:SetText("History")
    historyBtn:SetScript("OnClick", function() TPP.HistoryUI.Toggle() end)

    local csvBtn = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    csvBtn:SetSize(110, 24)
    csvBtn:SetPoint("TOP", statsBtn, "BOTTOM", 0, -4)
    csvBtn:SetText("Export CSV")
    csvBtn:SetScript("OnClick", function() MainUI.ShowCSV() end)

    -- character filter checkbox
    charCheckbox = CreateFrame("CheckButton", "TPPCharCheckbox", mainFrame, "UICheckButtonTemplate")
    charCheckbox:SetSize(24, 24)
    charCheckbox:SetPoint("BOTTOMLEFT", mainFrame, "BOTTOMLEFT", 12, 8)
    charCheckbox.text = charCheckbox.text or _G["TPPCharCheckboxText"] or charCheckbox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    charCheckbox.text:SetPoint("LEFT", charCheckbox, "RIGHT", 2, 0)
    charCheckbox.text:SetText("Current character only")
    charCheckbox:SetScript("OnClick", function(self)
        TPP.characterFilter = self:GetChecked() and Utils.GetCharacterKey() or nil
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
    if not timeText then return end
    local duration = Data.GetSessionDuration()
    timeText:SetText(Utils.SecondsToHMS(duration))
    local r, g, b = Utils.GetColorForTime(duration)
    timeText:SetTextColor(r, g, b)
end

function MainUI.Toggle()
    if mainFrame:IsShown() then
        mainFrame:Hide()
    else
        MainUI.UpdateTimeDisplay()
        mainFrame:Show()
    end
end

function MainUI.ShowCSV()
    if not TPP.csvFrame then
        TPP.csvFrame = Utils.CreateStyledFrame("TimePlayed_PlusCSVFrame", 620, 220)

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
