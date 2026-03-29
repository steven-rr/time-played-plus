local _, TPP = ...

TPP.HistoryUI = {}

local HistoryUI = TPP.HistoryUI
local Utils = TPP.Utils
local Data = TPP.Data

local historyFrame
local rows = {}
local ROWS_VISIBLE = 8
local scrollOffset = 0
local cachedSessions = {}

function HistoryUI.Create()
    historyFrame = Utils.CreateStyledFrame("TimePlayed+HistoryFrame", 520, 240)

    local title = Utils.CreateFontString(historyFrame, 11, "TOP", historyFrame, "TOP", 0, -12)
    title:SetText("Session History")
    title:SetTextColor(1, 0.82, 0)

    -- header
    local headerY = -32
    local headers = {
        { text = "Date", x = 16 },
        { text = "Start", x = 100 },
        { text = "Duration", x = 180 },
        { text = "Character", x = 300 },
    }
    for _, h in ipairs(headers) do
        local fs = Utils.CreateFontString(historyFrame, 10, "TOPLEFT", historyFrame, "TOPLEFT", h.x, headerY)
        fs:SetText(h.text)
        fs:SetTextColor(0.8, 0.8, 0.8)
    end

    -- session rows
    for i = 1, ROWS_VISIBLE do
        local rowY = headerY - 16 - ((i - 1) * 20)
        local row = {}
        row.date = Utils.CreateFontString(historyFrame, 9, "TOPLEFT", historyFrame, "TOPLEFT", 16, rowY)
        row.time = Utils.CreateFontString(historyFrame, 9, "TOPLEFT", historyFrame, "TOPLEFT", 100, rowY)
        row.duration = Utils.CreateFontString(historyFrame, 9, "TOPLEFT", historyFrame, "TOPLEFT", 180, rowY)
        row.character = Utils.CreateFontString(historyFrame, 9, "TOPLEFT", historyFrame, "TOPLEFT", 300, rowY)
        rows[i] = row
    end

    -- scroll slider (plain Slider, no deprecated template)
    local slider = CreateFrame("Slider", "TPPHistorySlider", historyFrame)
    slider:SetWidth(16)
    slider:SetPoint("TOPRIGHT", historyFrame, "TOPRIGHT", -8, -48)
    slider:SetPoint("BOTTOMRIGHT", historyFrame, "BOTTOMRIGHT", -8, 16)
    slider:SetOrientation("VERTICAL")
    slider:SetMinMaxValues(0, 1)
    slider:SetValueStep(1)
    slider:SetValue(0)
    slider:SetObeyStepOnDrag(true)

    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(16, 24)
    thumb:SetColorTexture(0.6, 0.6, 0.6, 0.8)
    slider:SetThumbTexture(thumb)

    local bg = slider:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.1, 0.1, 0.1, 0.5)

    slider:SetScript("OnValueChanged", function(self, value)
        scrollOffset = math.floor(value)
        HistoryUI.UpdateRows()
    end)

    historyFrame.slider = slider

    -- mouse wheel scrolling
    historyFrame:EnableMouseWheel(true)
    historyFrame:SetScript("OnMouseWheel", function(self, delta)
        local newVal = scrollOffset - delta
        newVal = math.max(0, math.min(newVal, math.max(0, #cachedSessions - ROWS_VISIBLE)))
        scrollOffset = newVal
        slider:SetValue(newVal)
    end)

    -- export CSV button
    local csvBtn = CreateFrame("Button", nil, historyFrame, "UIPanelButtonTemplate")
    csvBtn:SetSize(110, 24)
    csvBtn:SetPoint("BOTTOMRIGHT", historyFrame, "BOTTOMRIGHT", -16, 8)
    csvBtn:SetText("Export CSV")
    csvBtn:SetScript("OnClick", function() TPP.MainUI.ShowCSV() end)

    local closeBtn = CreateFrame("Button", nil, historyFrame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", historyFrame, "TOPRIGHT", -2, -2)

    return historyFrame
end

function HistoryUI.Refresh()
    if not historyFrame or not TPP.db then return end

    cachedSessions = Data.GetSessions(TPP.db, TPP.characterFilter)
    scrollOffset = 0

    local maxScroll = math.max(0, #cachedSessions - ROWS_VISIBLE)
    historyFrame.slider:SetMinMaxValues(0, maxScroll)
    historyFrame.slider:SetValue(0)

    HistoryUI.UpdateRows()
end

function HistoryUI.UpdateRows()
    for i = 1, ROWS_VISIBLE do
        local idx = scrollOffset + i
        local row = rows[i]
        local session = cachedSessions[idx]

        if session then
            row.date:SetText(Utils.FormatDate(session.startTime))
            row.time:SetText(Utils.FormatTime(session.startTime))
            row.duration:SetText(Utils.SecondsToHMS(session.duration))
            row.character:SetText(session.character)

            local r, g, b = Utils.GetColorForDailyTime(session.duration)
            row.duration:SetTextColor(r, g, b)
            row.date:SetTextColor(1, 1, 1)
            row.time:SetTextColor(1, 1, 1)
            row.character:SetTextColor(1, 1, 1)

            row.date:Show()
            row.time:Show()
            row.duration:Show()
            row.character:Show()
        else
            row.date:Hide()
            row.time:Hide()
            row.duration:Hide()
            row.character:Hide()
        end
    end
end

function HistoryUI.Toggle()
    if historyFrame:IsShown() then
        historyFrame:Hide()
    else
        HistoryUI.Refresh()
        historyFrame:Show()
    end
end
