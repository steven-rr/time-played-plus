local _, TPP = ...

TPP.Data = {}

local Data = TPP.Data

-- Session state (not persisted directly, computed at runtime)
Data.sessionStart = nil
Data.afkAccumulated = 0
Data.afkStart = nil
Data.isActive = false
Data.character = nil
Data.serverTimeRequested = false

-- Cache to avoid full session scan every second
local cache = {
    dayKey = nil,
    todayPast = 0,
    weeklyPast = 0,
    dailyTotals = nil,
    firstDay = nil,
    dirty = true,
    sessionCount = 0,
    characterFilter = nil,
}

local function GetMidnight(timestamp)
    local t = date("*t", timestamp)
    return time({ year = t.year, month = t.month, day = t.day, hour = 0 })
end

-- Compute how much active time a session contributes to a given day
local function SessionDayOverlap(session, dayStart)
    local dayEnd = dayStart + 86400
    local wallEnd = session.startTime + session.duration + (session.afkDuration or 0)
    local overlapStart = math.max(session.startTime, dayStart)
    local overlapEnd = math.min(wallEnd, dayEnd)
    if overlapEnd <= overlapStart then return 0 end
    local wallDuration = wallEnd - session.startTime
    if wallDuration <= 0 then return 0 end
    return session.duration * (overlapEnd - overlapStart) / wallDuration
end

-- Weekly reset: Tuesday 15:00 UTC (10 AM EDT / 7 AM PDT)
local function GetLastWeeklyReset()
    local now = time()
    local t = date("!*t", now)
    -- wday: 1=Sun, 2=Mon, 3=Tue, 4=Wed, 5=Thu, 6=Fri, 7=Sat
    local daysSinceTuesday = (t.wday - 3) % 7
    -- go back to last Tuesday midnight UTC, then add 15 hours
    local tuesdayMidnight = now - daysSinceTuesday * 86400 - t.hour * 3600 - t.min * 60 - t.sec
    local resetTime = tuesdayMidnight + 15 * 3600
    -- if we haven't hit reset time yet today (and today is Tuesday), go back a week
    if resetTime > now then
        resetTime = resetTime - 7 * 86400
    end
    return resetTime
end

local function RebuildCache(db, characterFilter)
    local now = time()
    local todayMidnight = GetMidnight(now)
    local todayKey = date("%Y-%m-%d", now)

    local todayPast = 0
    local weeklyPast = 0
    local resetTime = GetLastWeeklyReset()
    local days = {}
    local firstDay = nil

    for _, session in ipairs(db.global.sessions) do
        if not characterFilter or session.character == characterFilter then
            local wallEnd = session.startTime + session.duration + (session.afkDuration or 0)

            -- today's total (with midnight split)
            local overlap = SessionDayOverlap(session, todayMidnight)
            if overlap > 0 then
                todayPast = todayPast + overlap
            end

            -- weekly total (since Tuesday reset)
            if wallEnd > resetTime then
                if session.startTime >= resetTime then
                    weeklyPast = weeklyPast + session.duration
                else
                    local wallDuration = wallEnd - session.startTime
                    if wallDuration > 0 then
                        local weekOverlap = wallEnd - resetTime
                        weeklyPast = weeklyPast + session.duration * weekOverlap / wallDuration
                    end
                end
            end

            -- daily totals for averages (split across day boundaries)
            local startMidnight = GetMidnight(session.startTime)
            local endMidnight = GetMidnight(wallEnd)

            if startMidnight == endMidnight then
                -- session within one day (common case)
                local dk = date("%Y-%m-%d", session.startTime)
                days[dk] = (days[dk] or 0) + session.duration
                if not firstDay or dk < firstDay then firstDay = dk end
            else
                -- session spans midnight — split proportionally
                local dayStart = startMidnight
                while dayStart <= endMidnight do
                    local portion = SessionDayOverlap(session, dayStart)
                    if portion > 0 then
                        local dk = date("%Y-%m-%d", dayStart)
                        days[dk] = (days[dk] or 0) + portion
                        if not firstDay or dk < firstDay then firstDay = dk end
                    end
                    dayStart = dayStart + 86400
                end
            end
        end
    end

    cache.dayKey = todayKey
    cache.todayPast = todayPast
    cache.weeklyPast = weeklyPast
    cache.dailyTotals = days
    cache.firstDay = firstDay
    cache.dirty = false
    cache.sessionCount = #db.global.sessions
    cache.characterFilter = characterFilter
end

function Data.InvalidateCache()
    cache.dirty = true
end

function Data.StartSession()
    Data.sessionStart = time()
    Data.afkAccumulated = 0
    Data.afkStart = nil
    Data.isActive = true
    Data.character = TPP.Utils.GetCharacterKey()
end

function Data.GetSessionDuration()
    if not Data.sessionStart then return 0 end
    local now = time()
    local afkTotal = Data.afkAccumulated
    if Data.afkStart then
        afkTotal = afkTotal + (now - Data.afkStart)
    end
    return math.max(0, now - Data.sessionStart - afkTotal)
end

function Data.OnAFKStart()
    if not Data.afkStart then
        Data.afkStart = time()
    end
end

function Data.OnAFKEnd()
    if Data.afkStart then
        local afkDuration = time() - Data.afkStart
        if afkDuration > 0 then
            Data.afkAccumulated = Data.afkAccumulated + afkDuration
        end
        Data.afkStart = nil
    end
end

function Data.SaveSession(db)
    if not Data.sessionStart then return end

    local now = time()
    local afkTotal = Data.afkAccumulated
    if Data.afkStart then
        afkTotal = afkTotal + (now - Data.afkStart)
    end
    local duration = now - Data.sessionStart - afkTotal
    if duration < 5 then return end -- don't save trivially short sessions

    local session = {
        startTime = Data.sessionStart,
        duration = duration,
        afkDuration = afkTotal,
        character = Data.character,
    }

    table.insert(db.global.sessions, session)
    Data.isActive = false
    Data.InvalidateCache()
end

function Data.SavePendingSession(db)
    if not Data.sessionStart then return end

    local now = time()
    local afkTotal = Data.afkAccumulated
    if Data.afkStart then
        afkTotal = afkTotal + (now - Data.afkStart)
    end

    db.global.pendingSession = {
        startTime = Data.sessionStart,
        endTime = now,
        afkAccumulated = afkTotal,
        character = Data.character,
    }
end

function Data.RecoverPendingSession(db)
    local pending = db.global.pendingSession
    if not pending then return end

    local endTime = pending.endTime or time()
    local duration = endTime - pending.startTime - (pending.afkAccumulated or 0)
    if duration > 5 then
        local session = {
            startTime = pending.startTime,
            duration = duration,
            afkDuration = pending.afkAccumulated or 0,
            character = pending.character or TPP.Utils.GetCharacterKey(),
        }
        table.insert(db.global.sessions, session)
        Data.InvalidateCache()
    end

    db.global.pendingSession = nil
end

function Data.GetTodayTotal(db, characterFilter)
    local now = time()
    local todayKey = date("%Y-%m-%d", now)

    -- rebuild cache if needed
    if cache.dirty or cache.dayKey ~= todayKey
        or cache.sessionCount ~= #db.global.sessions
        or cache.characterFilter ~= characterFilter then
        RebuildCache(db, characterFilter)
    end

    local total = cache.todayPast

    -- add live session
    if Data.isActive and Data.sessionStart then
        local todayMidnight = GetMidnight(now)
        if Data.sessionStart >= todayMidnight then
            -- session started today, no split needed
            total = total + Data.GetSessionDuration()
        else
            -- session spans midnight, use proportional split
            local afkTotal = Data.afkAccumulated
            if Data.afkStart then
                afkTotal = afkTotal + (now - Data.afkStart)
            end
            total = total + SessionDayOverlap({
                startTime = Data.sessionStart,
                duration = Data.GetSessionDuration(),
                afkDuration = afkTotal,
            }, todayMidnight)
        end
    end

    return total
end

function Data.GetDailyAverages(db, characterFilter)
    local now = time()
    local todayKey = date("%Y-%m-%d", now)

    -- rebuild cache if needed
    if cache.dirty or cache.dayKey ~= todayKey
        or cache.sessionCount ~= #db.global.sessions
        or cache.characterFilter ~= characterFilter then
        RebuildCache(db, characterFilter)
    end

    local days = cache.dailyTotals
    local firstDay = cache.firstDay

    -- add live session to daily totals
    local liveDays = {}
    if Data.isActive and Data.sessionStart then
        local todayMidnight = GetMidnight(now)
        local sessionDur = Data.GetSessionDuration()

        if Data.sessionStart >= todayMidnight then
            -- session started today, no split needed
            liveDays[todayKey] = sessionDur
            if not firstDay or todayKey < firstDay then
                firstDay = todayKey
            end
        else
            -- session spans midnight, split proportionally
            local afkTotal = Data.afkAccumulated
            if Data.afkStart then
                afkTotal = afkTotal + (now - Data.afkStart)
            end
            local liveSession = {
                startTime = Data.sessionStart,
                duration = sessionDur,
                afkDuration = afkTotal,
            }
            local dayStart = GetMidnight(Data.sessionStart)
            while dayStart <= todayMidnight do
                local portion = SessionDayOverlap(liveSession, dayStart)
                if portion > 0 then
                    local dk = date("%Y-%m-%d", dayStart)
                    liveDays[dk] = portion
                    if not firstDay or dk < firstDay then
                        firstDay = dk
                    end
                end
                dayStart = dayStart + 86400
            end
        end
    end

    -- compute total playtime
    local totalTime = 0
    for dk, dayTotal in pairs(days) do
        totalTime = totalTime + dayTotal + (liveDays[dk] or 0)
    end
    for dk, liveTotal in pairs(liveDays) do
        if not days[dk] then
            totalTime = totalTime + liveTotal
        end
    end

    -- compute overall average across all calendar days since first session
    local calendarDays = 1
    if firstDay and firstDay ~= todayKey then
        local fy, fm, fd = firstDay:match("(%d+)-(%d+)-(%d+)")
        local firstTimestamp = time({ year = tonumber(fy), month = tonumber(fm), day = tonumber(fd) })
        calendarDays = math.floor((now - firstTimestamp) / 86400) + 1
    end
    local overallAvg = calendarDays > 0 and (totalTime / calendarDays) or 0

    -- compute 7-day average (last 7 calendar days)
    local recentTotal = 0
    for i = 0, 6 do
        local dk = date("%Y-%m-%d", now - i * 86400)
        recentTotal = recentTotal + (days[dk] or 0) + (liveDays[dk] or 0)
    end
    local recentAvg = recentTotal / 7

    return overallAvg, recentAvg
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

function Data.GetWeeklyTotal(db, characterFilter)
    local now = time()
    local todayKey = date("%Y-%m-%d", now)

    -- rebuild cache if needed
    if cache.dirty or cache.dayKey ~= todayKey
        or cache.sessionCount ~= #db.global.sessions
        or cache.characterFilter ~= characterFilter then
        RebuildCache(db, characterFilter)
    end

    local total = cache.weeklyPast

    -- add live session
    if Data.isActive and Data.sessionStart then
        local resetTime = GetLastWeeklyReset()
        local sessionDur = Data.GetSessionDuration()
        if Data.sessionStart >= resetTime then
            total = total + sessionDur
        else
            local afkTotal = Data.afkAccumulated
            if Data.afkStart then
                afkTotal = afkTotal + (now - Data.afkStart)
            end
            local wallDuration = now - Data.sessionStart
            if wallDuration > 0 then
                local overlap = now - resetTime
                total = total + sessionDur * overlap / wallDuration
            end
        end
    end

    return total
end

-- Crash recovery via server time cross-check
local CRASH_THRESHOLD = 600 -- 10 minutes
local CRASH_MAX_RECOVERY = 28800 -- 8 hours max recovery (same cap as TimeTracker)

function Data.OnServerTimePlayed(serverTotal, db)
    local character = Data.character
    if not character or not db then return end

    -- initialize per-character checkpoint table
    if not db.global.serverCheckpoints then
        db.global.serverCheckpoints = {}
    end

    local checkpoint = db.global.serverCheckpoints[character]

    if checkpoint and checkpoint.serverTotal then
        local serverDiff = serverTotal - checkpoint.serverTotal

        if serverDiff > 0 then
            -- sum our recorded sessions + afk since last checkpoint
            local accounted = 0
            for _, session in ipairs(db.global.sessions) do
                if session.character == character and session.startTime >= checkpoint.timestamp then
                    accounted = accounted + session.duration + (session.afkDuration or 0)
                end
            end

            local gap = serverDiff - accounted
            if gap >= CRASH_THRESHOLD and gap < CRASH_MAX_RECOVERY then
                -- unaccounted time — likely a crashed session
                -- estimate start time: use the latest session end for this character, or checkpoint time
                local latestEnd = checkpoint.timestamp
                for _, session in ipairs(db.global.sessions) do
                    if session.character == character then
                        local sessionEnd = session.startTime + session.duration + (session.afkDuration or 0)
                        if sessionEnd > latestEnd then
                            latestEnd = sessionEnd
                        end
                    end
                end
                local recoveredSession = {
                    startTime = latestEnd,
                    duration = gap,
                    afkDuration = 0,
                    character = character,
                    recovered = true,
                }
                table.insert(db.global.sessions, recoveredSession)
                Data.InvalidateCache()
            end
        end
    end

    -- update checkpoint (use session start time so sessions are properly matched)
    db.global.serverCheckpoints[character] = {
        serverTotal = serverTotal,
        timestamp = Data.sessionStart or time(),
    }
end
