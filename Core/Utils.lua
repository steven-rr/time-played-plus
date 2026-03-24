local _, TPP = ...

TPP.Utils = {}
TPP.frames = {}

function TPP.Utils.SecondsToHMS(seconds)
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local secs = seconds % 60

    if hours > 0 then
        return string.format("%dh %dm %ds", hours, minutes, secs)
    elseif minutes > 0 then
        return string.format("%dm %ds", minutes, secs)
    else
        return string.format("%ds", secs)
    end
end

-- Session/history color: green < 1h, green→yellow 1-2h, yellow→red 2-3h, red 3h+
function TPP.Utils.GetColorForTime(seconds)
    if TPP.db and TPP.db.profile and not TPP.db.profile.colorTimer then
        return 0.2, 1.0, 0.2 -- always green
    end
    if seconds < 3600 then
        return 0.2, 1.0, 0.2 -- green
    elseif seconds < 7200 then
        local t = (seconds - 3600) / 3600
        return 0.2 + t * 0.8, 1.0 - t * 0.2, 0.2 -- green to yellow
    else
        local t = math.min((seconds - 7200) / 3600, 1.0)
        return 1.0, 0.8 - t * 0.8, 0.2 - t * 0.2 -- yellow to red
    end
end

-- Today color: green→yellow 0-4h, yellow→red 4-8h, red 8h+
function TPP.Utils.GetColorForDailyTime(seconds)
    if TPP.db and TPP.db.profile and not TPP.db.profile.colorTimer then
        return 0.2, 1.0, 0.2 -- always green
    end
    if seconds < 14400 then
        local t = seconds / 14400
        return 0.2 + t * 0.8, 1.0 - t * 0.2, 0.2 -- green to yellow over 4h
    elseif seconds < 28800 then
        local t = (seconds - 14400) / 14400
        return 1.0, 0.8 - t * 0.8, 0.2 - t * 0.2 -- yellow to red over 4-8h
    else
        return 1.0, 0, 0 -- red 8h+
    end
end

function TPP.Utils.GetColorHexForTime(seconds)
    local r, g, b = TPP.Utils.GetColorForTime(seconds)
    return string.format("|cff%02x%02x%02x", r * 255, g * 255, b * 255)
end

function TPP.Utils.FormatDate(timestamp)
    return date("%m/%d/%y", timestamp)
end

function TPP.Utils.FormatTime(timestamp)
    return date("%H:%M:%S", timestamp)
end

function TPP.Utils.FormatDateTime(timestamp)
    return date("%m/%d/%y %H:%M:%S", timestamp)
end

function TPP.Utils.GetCharacterKey()
    return UnitName("player") .. " - " .. GetRealmName()
end

function TPP.Utils.GetDayKey(timestamp)
    return date("%Y-%m-%d", timestamp)
end

function TPP.Utils.MakeFrameMovable(frame)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if TPP.db and TPP.db.profile and self:GetName() then
            local point, _, relPoint, x, y = self:GetPoint()
            TPP.db.profile.positions[self:GetName()] = { point, relPoint, x, y }
        end
    end)
end

function TPP.Utils.CreateStyledFrame(name, width, height, parent)
    local frame = CreateFrame("Frame", name, parent or UIParent, "BackdropTemplate")
    frame:SetSize(width, height)
    -- restore saved position or default to center
    if TPP.db and TPP.db.profile and TPP.db.profile.positions[name] then
        local pos = TPP.db.profile.positions[name]
        frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else
        frame:SetPoint("CENTER")
    end
    frame:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(0, 0, 0, 0.8)
    frame:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    TPP.Utils.MakeFrameMovable(frame)
    frame:Hide()
    table.insert(TPP.frames, frame)
    if TPP.db and TPP.db.profile then
        frame:SetScale(TPP.db.profile.scale or 1.0)
    end
    return frame
end

function TPP.Utils.ApplyScale(scale)
    for _, frame in ipairs(TPP.frames) do
        frame:SetScale(scale)
    end
end

function TPP.Utils.CreateFontString(parent, size, anchorPoint, relFrame, relPoint, xOff, yOff)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetFont("Fonts/FRIZQT__.TTF", size or 12)
    if anchorPoint then
        fs:SetPoint(anchorPoint, relFrame or parent, relPoint or anchorPoint, xOff or 0, yOff or 0)
    end
    return fs
end
