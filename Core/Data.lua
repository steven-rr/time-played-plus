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

function Data.StartSession()
    Data.sessionStart = time()
    Data.afkAccumulated = 0
    Data.afkStart = nil
    Data.isActive = true
    Data.character = TPP.Utils.GetCharacterKey()
    -- check if player is already AFK (e.g., after /reload while AFK)
    local success, isAFK = pcall(UnitIsAFK, "player")
    if success and isAFK then
        Data.afkStart = Data.sessionStart
    end
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
        local fy, fm, fd = firstDay:match("(%d+)-(%d+)-(%d+)")
        local firstTimestamp = time({ year = tonumber(fy), month = tonumber(fm), day = tonumber(fd) })
        calendarDays = math.floor((time() - firstTimestamp) / 86400) + 1
    end
    local overallAvg = calendarDays > 0 and (totalTime / calendarDays) or 0

    -- compute 7-day average (last 7 calendar days)
    local recentTotal = 0
    for i = 0, 6 do
        local dayKey = TPP.Utils.GetDayKey(time() - i * 86400)
        recentTotal = recentTotal + (days[dayKey] or 0)
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
            end
        end
    end

    -- update checkpoint (use session start time so sessions are properly matched)
    db.global.serverCheckpoints[character] = {
        serverTotal = serverTotal,
        timestamp = Data.sessionStart or time(),
    }
end
