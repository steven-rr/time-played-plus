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

    for _, session in ipairs(db.global.sessions) do
        local dayKey = TPP.Utils.GetDayKey(session.startTime)
        days[dayKey] = (days[dayKey] or 0) + session.duration
    end

    -- add current session to today
    if Data.isActive then
        local todayKey = TPP.Utils.GetDayKey(time())
        days[todayKey] = (days[todayKey] or 0) + Data.GetSessionDuration()
    end

    -- compute overall average
    local totalTime = 0
    local dayCount = 0
    for _, dayTotal in pairs(days) do
        totalTime = totalTime + dayTotal
        dayCount = dayCount + 1
    end
    local overallAvg = dayCount > 0 and (totalTime / dayCount) or 0

    -- compute 7-day average
    local sortedDays = {}
    for dayKey, dayTotal in pairs(days) do
        table.insert(sortedDays, { key = dayKey, total = dayTotal })
    end
    table.sort(sortedDays, function(a, b) return a.key > b.key end)

    local recentTotal = 0
    local recentCount = math.min(7, #sortedDays)
    for i = 1, recentCount do
        recentTotal = recentTotal + sortedDays[i].total
    end
    local recentAvg = recentCount > 0 and (recentTotal / recentCount) or 0

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
