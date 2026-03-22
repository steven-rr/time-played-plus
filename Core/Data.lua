local _, TPP = ...

TPP.Data = {}

local Data = TPP.Data

-- Session state (not persisted directly, computed at runtime)
Data.sessionStart = nil
Data.afkAccumulated = 0
Data.afkStart = nil
Data.isActive = false

function Data.StartSession()
    Data.sessionStart = time()
    Data.afkAccumulated = 0
    Data.afkStart = nil
    Data.isActive = true
end

function Data.GetSessionDuration()
    if not Data.sessionStart then return 0 end
    local elapsed = time() - Data.sessionStart - Data.afkAccumulated
    if Data.afkStart then
        elapsed = elapsed - (time() - Data.afkStart)
    end
    return math.max(0, elapsed)
end

function Data.OnAFKStart()
    if not Data.afkStart then
        Data.afkStart = time()
    end
end

function Data.OnAFKEnd()
    if Data.afkStart then
        Data.afkAccumulated = Data.afkAccumulated + (time() - Data.afkStart)
        Data.afkStart = nil
    end
end

function Data.SaveSession(db)
    if not Data.sessionStart then return end

    local duration = Data.GetSessionDuration()
    if duration < 5 then return end -- don't save trivially short sessions

    local session = {
        startTime = Data.sessionStart,
        duration = duration,
        character = TPP.Utils.GetCharacterKey(),
    }

    table.insert(db.global.sessions, session)
    Data.isActive = false
end

function Data.SavePendingSession(db)
    if not Data.sessionStart then return end

    db.global.pendingSession = {
        startTime = Data.sessionStart,
        afkAccumulated = Data.afkAccumulated,
    }
end

function Data.RecoverPendingSession(db)
    local pending = db.global.pendingSession
    if not pending then return end

    local duration = time() - pending.startTime - (pending.afkAccumulated or 0)
    if duration > 5 then
        local session = {
            startTime = pending.startTime,
            duration = duration,
            character = TPP.Utils.GetCharacterKey(),
        }
        table.insert(db.global.sessions, session)
    end

    db.global.pendingSession = nil
end

function Data.GetTodayTotal(db)
    local todayKey = TPP.Utils.GetDayKey(time())
    local total = 0

    for _, session in ipairs(db.global.sessions) do
        if TPP.Utils.GetDayKey(session.startTime) == todayKey then
            total = total + session.duration
        end
    end

    -- add current active session
    if Data.isActive then
        total = total + Data.GetSessionDuration()
    end

    return total
end

function Data.GetDailyAverages(db)
    local days = {}
    local firstDay = nil

    for _, session in ipairs(db.global.sessions) do
        local dayKey = TPP.Utils.GetDayKey(session.startTime)
        days[dayKey] = (days[dayKey] or 0) + session.duration
        if not firstDay or dayKey < firstDay then
            firstDay = dayKey
        end
    end

    -- add current session to today
    if Data.isActive then
        local todayKey = TPP.Utils.GetDayKey(time())
        days[todayKey] = (days[todayKey] or 0) + Data.GetSessionDuration()
        if not firstDay or todayKey < firstDay then
            firstDay = todayKey
        end
    end

    -- compute total playtime
    local totalTime = 0
    for _, dayTotal in pairs(days) do
        totalTime = totalTime + dayTotal
    end

    -- compute overall average across all calendar days since first session
    local todayKey = TPP.Utils.GetDayKey(time())
    local calendarDays = 1
    if firstDay and firstDay ~= todayKey then
        -- count days between firstDay and today
        -- parse year, month, day from firstDay (YYYY-MM-DD)
        local fy, fm, fd = firstDay:match("(%d+)-(%d+)-(%d+)")
        local firstTimestamp = time({ year = tonumber(fy), month = tonumber(fm), day = tonumber(fd) })
        calendarDays = math.floor((time() - firstTimestamp) / 86400) + 1
    end
    local overallAvg = calendarDays > 0 and (totalTime / calendarDays) or 0

    -- compute 7-day average (last 7 calendar days, not just active days)
    local recentTotal = 0
    for i = 0, 6 do
        local dayKey = TPP.Utils.GetDayKey(time() - i * 86400)
        recentTotal = recentTotal + (days[dayKey] or 0)
    end
    local recentAvg = recentTotal / 7

    return overallAvg, recentAvg
end

function Data.GetSessions(db, characterFilter)
    local sessions = {}
    for _, session in ipairs(db.global.sessions) do
        if not characterFilter or session.character == characterFilter then
            table.insert(sessions, session)
        end
    end
    -- newest first
    table.sort(sessions, function(a, b) return a.startTime > b.startTime end)
    return sessions
end

function Data.GetLongestSession(db, characterFilter)
    local longest = 0
    for _, session in ipairs(db.global.sessions) do
        if not characterFilter or session.character == characterFilter then
            if session.duration > longest then
                longest = session.duration
            end
        end
    end
    return longest
end

function Data.GetSessionCount(db, characterFilter)
    local count = 0
    for _, session in ipairs(db.global.sessions) do
        if not characterFilter or session.character == characterFilter then
            count = count + 1
        end
    end
    return count
end

function Data.GetDaysPlayed(db, characterFilter)
    local days = {}
    for _, session in ipairs(db.global.sessions) do
        if not characterFilter or session.character == characterFilter then
            local dayKey = TPP.Utils.GetDayKey(session.startTime)
            days[dayKey] = true
        end
    end
    local count = 0
    for _ in pairs(days) do
        count = count + 1
    end
    return count
end

function Data.GetShareData(db, characterFilter)
    local overallAvg = Data.GetDailyAverages(db)
    local longest = Data.GetLongestSession(db, characterFilter)
    local daysPlayed = Data.GetDaysPlayed(db, characterFilter)
    local character = characterFilter or TPP.Utils.GetCharacterKey()

    -- get class, faction, and race
    local _, englishClass = UnitClass("player")
    local faction = UnitFactionGroup("player") or "Neutral"
    local _, englishRace = UnitRace("player")

    return {
        character = character,
        dailyAvg = math.floor(overallAvg),
        longest = longest,
        daysPlayed = daysPlayed,
        class = englishClass or "WARRIOR",
        faction = faction,
        race = englishRace or "Human",
    }
end

-- Simple base64 encoding for share URLs
local b64chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
local function base64Encode(str)
    local result = {}
    local pad = (3 - #str % 3) % 3
    str = str .. string.rep("\0", pad)
    for i = 1, #str, 3 do
        local a, b, c = string.byte(str, i, i + 2)
        local n = a * 65536 + b * 256 + c
        table.insert(result, string.sub(b64chars, math.floor(n / 262144) + 1, math.floor(n / 262144) + 1))
        table.insert(result, string.sub(b64chars, math.floor(n / 4096) % 64 + 1, math.floor(n / 4096) % 64 + 1))
        table.insert(result, string.sub(b64chars, math.floor(n / 64) % 64 + 1, math.floor(n / 64) % 64 + 1))
        table.insert(result, string.sub(b64chars, n % 64 + 1, n % 64 + 1))
    end
    -- remove padding chars
    for i = 1, pad do
        result[#result] = nil
    end
    return table.concat(result)
end

function Data.GenerateShareURL(db, characterFilter)
    local data = Data.GetShareData(db, characterFilter)
    -- character|dailyAvg|longest|daysPlayed|class|faction|race
    local payload = string.format("%s|%d|%d|%d|%s|%s|%s",
        data.character, data.dailyAvg, data.longest, data.daysPlayed,
        data.class, data.faction, data.race)
    local encoded = base64Encode(payload)
    return "https://timeplayed-plus.github.io/share#" .. encoded
end

function Data.GetCSV(db, characterFilter)
    local lines = { "Date,Start Time,Character,Duration (seconds)" }
    local sessions = Data.GetSessions(db, characterFilter)
    -- reverse so CSV is chronological
    for i = #sessions, 1, -1 do
        local s = sessions[i]
        table.insert(lines, string.format("%s,%s,%s,%d",
            TPP.Utils.FormatDate(s.startTime),
            TPP.Utils.FormatTime(s.startTime),
            s.character,
            s.duration
        ))
    end
    return table.concat(lines, "\n")
end
