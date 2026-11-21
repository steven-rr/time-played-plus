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

-- edit mode (opened from the options panel): each row gets a delete control until the window closes
local titleText, confirmBtn, defaultStrata
local editMode = false
local armedSession = nil
local armToken = 0
local CONFIRM_SECONDS = 5

-- arming a row is step one of deleting it; it disarms by itself after a few seconds
local function SetArmed(session)
    armedSession = session
    armToken = armToken + 1
    if session then
        local token = armToken
        C_Timer.After(CONFIRM_SECONDS, function()
            if armToken == token then
                armedSession = nil
                HistoryUI.UpdateRows()
            end
        end)
    end
    HistoryUI.UpdateRows()
end

local function DeleteArmed()
    local session = armedSession
    if not session then return end
    armedSession = nil
    armToken = armToken + 1
    if Data.DeleteSession(TPP.db, session) then
        print("|cffffd100TimePlayed+|r: Deleted session from " .. Utils.FormatDateTime(session.startTime)
            .. " (" .. Utils.SecondsToHMS(session.duration) .. ").")
    end
    HistoryUI.Refresh(true)
    if TPP.StatsUI.Refresh then TPP.StatsUI.Refresh() end
    if TPP.MainUI.UpdateTimeDisplay then TPP.MainUI.UpdateTimeDisplay() end
end

local function SetEditMode(on)
    editMode = on
    titleText:SetText(on and "Edit Session History" or "Session History")
    -- the options panel sits on the HIGH strata; lift the window above it while editing
    historyFrame:SetFrameStrata(on and "DIALOG" or defaultStrata)
    SetArmed(nil)
end

function HistoryUI.Create()
    historyFrame = Utils.CreateStyledFrame("TimePlayed+HistoryFrame", 520, 240)
    defaultStrata = historyFrame:GetFrameStrata()

    titleText = Utils.CreateFontString(historyFrame, 11, "TOP", historyFrame, "TOP", 0, -12)
    titleText:SetText("Session History")
    titleText:SetTextColor(1, 0.82, 0)

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

        -- delete control: clicking x arms the row (click again to cancel), the red "Delete?" beside it confirms
        row.del = CreateFrame("Button", nil, historyFrame)
        row.del:SetSize(16, 16)
        row.del:SetPoint("TOPLEFT", historyFrame, "TOPLEFT", 470, rowY + 3)
        local delLabel = Utils.CreateFontString(row.del, 10, "CENTER")
        delLabel:SetText("x")
        delLabel:SetTextColor(0.6, 0.6, 0.6)
        row.del:SetScript("OnEnter", function() delLabel:SetTextColor(1, 0.3, 0.3) end)
        row.del:SetScript("OnLeave", function() delLabel:SetTextColor(0.6, 0.6, 0.6) end)
        row.del:SetScript("OnClick", function()
            SetArmed(armedSession ~= row.session and row.session or nil)
        end)
        row.del:Hide()

        rows[i] = row
    end

    -- one shared confirm control, moved next to whichever row is armed
    confirmBtn = CreateFrame("Button", nil, historyFrame)
    confirmBtn:SetSize(52, 16)
    local confirmBg = confirmBtn:CreateTexture(nil, "BACKGROUND")
    confirmBg:SetAllPoints()
    confirmBg:SetColorTexture(0.6, 0.1, 0.1, 1)
    local confirmLabel = Utils.CreateFontString(confirmBtn, 9, "CENTER")
    confirmLabel:SetText("Delete?")
    confirmLabel:SetTextColor(1, 1, 1)
    confirmBtn:SetScript("OnClick", DeleteArmed)
    confirmBtn:Hide()

    -- closing the window always ends edit mode
    historyFrame:SetScript("OnHide", function()
        if editMode then SetEditMode(false) end
    end)

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

-- keepScroll: stay at the current scroll position (used after deleting a row) instead of jumping to the top
function HistoryUI.Refresh(keepScroll)
    if not historyFrame or not TPP.db then return end

    cachedSessions = Data.GetSessions(TPP.db, TPP.characterFilter)

    local maxScroll = math.max(0, #cachedSessions - ROWS_VISIBLE)
    scrollOffset = keepScroll and math.min(scrollOffset, maxScroll) or 0
    historyFrame.slider:SetMinMaxValues(0, maxScroll)
    historyFrame.slider:SetValue(scrollOffset)

    HistoryUI.UpdateRows()
end

function HistoryUI.UpdateRows()
    confirmBtn:Hide()

    for i = 1, ROWS_VISIBLE do
        local idx = scrollOffset + i
        local row = rows[i]
        local session = cachedSessions[idx]
        row.session = session

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

            if editMode then
                row.del:Show()
                if session == armedSession then
                    -- armed row: red text, with the confirm control beside its x
                    row.date:SetTextColor(1, 0.3, 0.3)
                    row.time:SetTextColor(1, 0.3, 0.3)
                    row.duration:SetTextColor(1, 0.3, 0.3)
                    row.character:SetTextColor(1, 0.3, 0.3)
                    confirmBtn:ClearAllPoints()
                    confirmBtn:SetPoint("RIGHT", row.del, "LEFT", -4, 0)
                    confirmBtn:Show()
                end
            else
                row.del:Hide()
            end
        else
            row.date:Hide()
            row.time:Hide()
            row.duration:Hide()
            row.character:Hide()
            row.del:Hide()
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

-- opened from the options panel: the same window, in edit mode until it is closed
function HistoryUI.OpenForEdit()
    if not historyFrame then return end
    if not historyFrame:IsShown() then
        HistoryUI.Refresh()
        historyFrame:Show()
    end
    SetEditMode(true)
    historyFrame:Raise()
end
