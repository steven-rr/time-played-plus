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
Data.lastBeat = nil
Data.gapAccumulated = 0

-- a gap this long between heartbeats means the addon wasn't running (PC sleep, clock jump)
local HEARTBEAT_GAP = 300

-- count any such gap as away time; skipped while AFK since the AFK interval already covers it
local function AccountGap(now)
    local last = Data.lastBeat
    Data.lastBeat = now
    if not last or Data.afkStart then return end
    local gap = now - last
    if gap > HEARTBEAT_GAP then
        Data.afkAccumulated = Data.afkAccumulated + gap
        Data.gapAccumulated = Data.gapAccumulated + gap
    end
end

-- Cache to avoid full session scan every second
local cache = {
    dayKey = nil,
    todayPast = 0,
    weeklyPast = 0,
    dailyTotals = nil,
    firstDay = nil,
    rows = nil,
    dirty = true,
    sessionCount = 0,
    characterFilter = nil,
}

-- a day runs from 6 AM to 6 AM, so a late night counts toward the evening it started in
local DAY_START_HOUR = 6

-- the start (6 AM) of the day a moment belongs to
local function GetDayStart(timestamp)
    local t = date("*t", timestamp)
    local start = time({ year = t.year, month = t.month, day = t.day, hour = DAY_START_HOUR })
    if timestamp < start then
        -- before 6 AM it is still the previous day; step back 12 hours to land safely inside it
        t = date("*t", start - 12 * 3600)
        start = time({ year = t.year, month = t.month, day = t.day, hour = DAY_START_HOUR })
    end
    return start
end

local function GetDayKey(timestamp)
    return date("%Y-%m-%d", GetDayStart(timestamp))
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

-- Weekly reset: asked from the game so it is right for every region
local function GetLastWeeklyReset()
    local now = time()
    local untilReset = C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset
        and C_DateAndTime.GetSecondsUntilWeeklyReset()
    if type(untilReset) == "number" and untilReset > 0 and untilReset <= 7 * 86400 then
        -- resets land on the hour; rounding keeps the answer steady from one call to the next
        return math.floor((now + untilReset) / 3600 + 0.5) * 3600 - 7 * 86400
    end

    -- fallback if the game can't say: the US schedule, Tuesday 15:00 UTC (10 AM EDT / 7 AM PDT)
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
    local todayStart = GetDayStart(now)
    local todayKey = date("%Y-%m-%d", todayStart)

    local todayPast = 0
    local weeklyPast = 0
    local resetTime = GetLastWeeklyReset()
    local days = {}
    local firstDay = nil

    for _, session in ipairs(db.global.sessions) do
        if not characterFilter or session.character == characterFilter then
            local wallEnd = session.startTime + session.duration + (session.afkDuration or 0)

            -- today's total (split at the day boundary)
            local overlap = SessionDayOverlap(session, todayStart)
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
            local startDay = GetDayStart(session.startTime)
            local endDay = GetDayStart(wallEnd)

            if startDay == endDay then
                -- session within one day (common case)
                local dk = date("%Y-%m-%d", startDay)
                days[dk] = (days[dk] or 0) + session.duration
                if not firstDay or dk < firstDay then firstDay = dk end
            else
                -- session crosses a day boundary — split proportionally
                local dayStart = startDay
                while dayStart <= endDay do
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
    cache.rows = nil -- built when the History or Stats window asks for them
    cache.dirty = false
    cache.sessionCount = #db.global.sessions
    cache.characterFilter = characterFilter
end

function Data.InvalidateCache()
    cache.dirty = true
end

-- Seasons whose start is known: each began at the weekly reset of the week starting at this moment (UTC).
-- Used once, for a season already under way when the addon first sees it.
local KNOWN_SEASON_WEEK = {
    [37] = 1787011200, -- Midnight Season 2: week of August 18, 2026
}

-- The game says which season it is, not when it began. Remember the number; when a higher one
-- appears, the season stats start over with the session in which it was first seen.
-- Retail only (interface 100000 and up): every other game version keeps all-time stats.
function Data.CheckSeason(db)
    if (select(4, GetBuildInfo()) or 0) < 100000 then return end
    local ok, id = pcall(function() return C_SeasonInfo.GetCurrentDisplaySeasonID() end)
    if not ok or type(id) ~= "number" or id <= 0 then return end
    local season = db.global.season
    if not season or id > season.id then
        local start = Data.sessionStart or time()
        local week = not season and KNOWN_SEASON_WEEK[id]
        if week then
            local reset = GetLastWeeklyReset()
            if reset > week then
                start = reset - math.floor((reset - week) / 604800) * 604800
            end
        end
        db.global.season = { id = id, start = start }
    end
end

-- start of the day the current season began, or nil where no season is tracked (anything but retail);
-- the daily average and the longest session count from here
function Data.GetSeasonStart(db)
    local season = db.global.season
    return season and GetDayStart(season.start) or nil
end

-- the game's own name for the current season, such as "Midnight Season 2"; nil if it gives none
function Data.GetSeasonName()
    local ok, name = pcall(function() return PVPUtil.GetCurrentSeasonText() end)
    return ok and type(name) == "string" and name ~= "" and name or nil
end

function Data.StartSession()
    Data.sessionStart = time()
    Data.lastBeat = Data.sessionStart
    Data.gapAccumulated = 0
    Data.afkAccumulated = 0
    Data.afkStart = nil
    Data.isActive = true
    Data.character = TPP.Utils.GetCharacterKey()
end

-- called every minute while logged in
function Data.Heartbeat()
    if not Data.sessionStart then return end
    AccountGap(time())
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
        local now = time()
        AccountGap(now)
        Data.afkStart = now
    end
end

function Data.OnAFKEnd()
    AccountGap(time())
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
    AccountGap(now)
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
        gapDuration = Data.gapAccumulated > 0 and Data.gapAccumulated or nil,
        character = Data.character,
    }

    table.insert(db.global.sessions, session)
    Data.isActive = false
    Data.InvalidateCache()
end

function Data.SavePendingSession(db)
    if not Data.sessionStart then return end

    local now = time()
    AccountGap(now)
    local afkTotal = Data.afkAccumulated
    if Data.afkStart then
        afkTotal = afkTotal + (now - Data.afkStart)
    end

    db.global.pendingSession = {
        startTime = Data.sessionStart,
        endTime = now,
        afkAccumulated = afkTotal,
        gapAccumulated = Data.gapAccumulated > 0 and Data.gapAccumulated or nil,
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
            gapDuration = pending.gapAccumulated,
            character = pending.character or TPP.Utils.GetCharacterKey(),
        }
        table.insert(db.global.sessions, session)
        Data.InvalidateCache()
    end

    db.global.pendingSession = nil
end

function Data.GetTodayTotal(db, characterFilter)
    local now = time()
    local todayKey = GetDayKey(now)

    -- rebuild cache if needed
    if cache.dirty or cache.dayKey ~= todayKey
        or cache.sessionCount ~= #db.global.sessions
        or cache.characterFilter ~= characterFilter then
        RebuildCache(db, characterFilter)
    end

    local total = cache.todayPast

    -- add live session
    if Data.isActive and Data.sessionStart then
        local todayStart = GetDayStart(now)
        if Data.sessionStart >= todayStart then
            -- session started today, no split needed
            total = total + Data.GetSessionDuration()
        else
            -- session started before today, use proportional split
            local afkTotal = Data.afkAccumulated
            if Data.afkStart then
                afkTotal = afkTotal + (now - Data.afkStart)
            end
            total = total + SessionDayOverlap({
                startTime = Data.sessionStart,
                duration = Data.GetSessionDuration(),
                afkDuration = afkTotal,
            }, todayStart)
        end
    end

    return total
end

function Data.GetDailyAverages(db, characterFilter)
    local now = time()
    local todayKey = GetDayKey(now)

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
        local todayStart = GetDayStart(now)
        local sessionDur = Data.GetSessionDuration()

        if Data.sessionStart >= todayStart then
            -- session started today, no split needed
            liveDays[todayKey] = sessionDur
            if not firstDay or todayKey < firstDay then
                firstDay = todayKey
            end
        else
            -- session started before today, split proportionally
            local afkTotal = Data.afkAccumulated
            if Data.afkStart then
                afkTotal = afkTotal + (now - Data.afkStart)
            end
            local liveSession = {
                startTime = Data.sessionStart,
                duration = sessionDur,
                afkDuration = afkTotal,
            }
            local dayStart = GetDayStart(Data.sessionStart)
            while dayStart <= todayStart do
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

    -- where the game has seasons, the overall average covers the current season only,
    -- counted from the first day played in it
    local seasonStart = Data.GetSeasonStart(db)
    local seasonDay = seasonStart and date("%Y-%m-%d", seasonStart)
    local seasonFirst = nil

    -- compute total playtime
    local totalTime = 0
    for dk, dayTotal in pairs(days) do
        if not seasonDay or dk >= seasonDay then
            totalTime = totalTime + dayTotal + (liveDays[dk] or 0)
            if not seasonFirst or dk < seasonFirst then seasonFirst = dk end
        end
    end
    for dk, liveTotal in pairs(liveDays) do
        if not days[dk] and (not seasonDay or dk >= seasonDay) then
            totalTime = totalTime + liveTotal
            if not seasonFirst or dk < seasonFirst then seasonFirst = dk end
        end
    end
    if seasonDay then
        firstDay = seasonFirst
    end

    -- compute overall average across every day since the first session, today included
    local calendarDays = 1
    local firstStart = GetDayStart(now)
    if firstDay and firstDay ~= todayKey then
        local fy, fm, fd = firstDay:match("(%d+)-(%d+)-(%d+)")
        firstStart = time({ year = tonumber(fy), month = tonumber(fm), day = tonumber(fd), hour = DAY_START_HOUR })
        calendarDays = math.floor((GetDayStart(now) - firstStart) / 86400 + 0.5) + 1
    end
    local overallAvg = calendarDays > 0 and (totalTime / calendarDays) or 0

    -- compute 7-day average (today and the six days before it)
    local recentTotal = 0
    for i = 0, 6 do
        local dk = GetDayKey(now - i * 86400)
        recentTotal = recentTotal + (days[dk] or 0) + (liveDays[dk] or 0)
    end
    local recentAvg = recentTotal / 7

    -- the third value is the start of the first day the overall average counts
    return overallAvg, recentAvg, firstStart
end

function Data.GetLongestSession(db, characterFilter)
    local seasonStart = Data.GetSeasonStart(db)
    local longest = 0
    for _, row in ipairs(Data.GetRows(db, characterFilter)) do
        if not seasonStart or row.startTime >= seasonStart then
            if row.duration > longest then
                longest = row.duration
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

-- a break shorter than this does not end a session: a reload or a quick relog carries on with it
local SESSION_BREAK = 300

-- The lines of the History window, newest first. Saved sessions of one character that follow each
-- other within SESSION_BREAK are shown as a single line; the saved sessions themselves are not changed.
-- The break is measured from the end of the earlier one's play time, so time away counts as part
-- of it: a night of PC sleep never joins two evenings. Time recovered after a crash is an estimate
-- and keeps a line of its own.
local function BuildRows(db, characterFilter)
    local sessions = Data.GetSessions(db, characterFilter)
    local oldestFirst, open = {}, {}
    for i = #sessions, 1, -1 do
        local session = sessions[i]
        local who = session.character or ""
        local playEnd = session.startTime + session.duration
        local row = open[who]
        if row and not row.recovered and not session.recovered
            and session.startTime - row.playEnd <= SESSION_BREAK then
            row.duration = row.duration + session.duration
            row.playEnd = math.max(row.playEnd, playEnd)
        else
            row = {
                startTime = session.startTime,
                duration = session.duration,
                character = session.character,
                recovered = session.recovered,
                playEnd = playEnd,
            }
            open[who] = row
            table.insert(oldestFirst, row)
        end
    end

    local rows = {}
    for i = #oldestFirst, 1, -1 do
        table.insert(rows, oldestFirst[i])
    end
    return rows
end

-- the History lines (see BuildRows), kept until the saved sessions change
function Data.GetRows(db, characterFilter)
    local todayKey = GetDayKey(time())

    -- rebuild cache if needed
    if cache.dirty or cache.dayKey ~= todayKey
        or cache.sessionCount ~= #db.global.sessions
        or cache.characterFilter ~= characterFilter then
        RebuildCache(db, characterFilter)
    end

    if not cache.rows then
        cache.rows = BuildRows(db, characterFilter)
    end
    return cache.rows
end

-- remove one session (the same table GetSessions returned); returns true if it was found
function Data.DeleteSession(db, session)
    for i, s in ipairs(db.global.sessions) do
        if s == session then
            table.remove(db.global.sessions, i)
            -- if the server check hasn't moved past this session yet, count its time as settled,
            -- otherwise the next login would add it back as a recovered session
            local checkpoint = db.global.serverCheckpoints and db.global.serverCheckpoints[session.character]
            if checkpoint and checkpoint.serverTotal and checkpoint.timestamp
                and session.startTime >= checkpoint.timestamp then
                checkpoint.serverTotal = checkpoint.serverTotal + session.duration
                    + (session.afkDuration or 0) - (session.gapDuration or 0)
            end
            Data.InvalidateCache()
            return true
        end
    end
    return false
end

function Data.GetCSV(db, characterFilter)
    local lines = { "Date,Start Time,Character,Duration (seconds)" }
    local sessions = Data.GetRows(db, characterFilter)
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
    local todayKey = GetDayKey(now)

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

-- active time recorded between two moments, across all characters
-- (a session that straddles a boundary is split in proportion to its wall-clock time, like the daily totals)
function Data.GetTotalBetween(db, fromTime, toTime)
    local total = 0
    for _, session in ipairs(db.global.sessions) do
        local wallEnd = session.startTime + session.duration + (session.afkDuration or 0)
        local overlap = math.min(wallEnd, toTime) - math.max(session.startTime, fromTime)
        local wallDuration = wallEnd - session.startTime
        if overlap > 0 and wallDuration > 0 then
            total = total + session.duration * overlap / wallDuration
        end
    end
    return total
end

-- the most recent day with play before the given day start: returns that day's start and its total
function Data.GetLastPlayedDay(db, beforeDayStart)
    local latest
    for _, session in ipairs(db.global.sessions) do
        if session.startTime < beforeDayStart and (not latest or session.startTime > latest.startTime) then
            latest = session
        end
    end
    if not latest then return nil end

    local wallEnd = latest.startTime + latest.duration + (latest.afkDuration or 0)
    local dayStart = GetDayStart(math.min(wallEnd, beforeDayStart - 1))
    local dayEnd = GetDayStart(dayStart + 36 * 3600) -- the next day start, whatever daylight saving does
    return dayStart, Data.GetTotalBetween(db, dayStart, dayEnd)
end

-- one chat line for the first login of the play day ("daily") or after the weekly reset ("weekly").
-- returns nil when there is nothing to say; db.global remembers what has already been reported
function Data.GetLoginSummary(db, mode)
    if mode ~= "daily" and mode ~= "weekly" then return nil end

    local now = time()
    local g = db.global
    local format = TPP.Utils.FormatDuration

    local todayStart = GetDayStart(now)
    local playDay = date("%Y-%m-%d", todayStart)
    local reset = GetLastWeeklyReset()
    -- resets are a week apart; the margin only guards against the reset time shifting by a few hours
    local weeklyDue = reset - (g.lastWeeklySummary or 0) > 2 * 86400

    if mode == "daily" then
        if g.lastDailySummary == playDay then return nil end
        g.lastDailySummary = playDay
    elseif not weeklyDue then
        return nil
    end

    -- once after each reset the weekly line takes the place of the daily one
    if weeklyDue then
        g.lastWeeklySummary = reset
        -- only describe weeks that were tracked from start to finish; a part-week average would mislead
        local firstSession = math.huge
        for _, session in ipairs(g.sessions) do
            if session.startTime < firstSession then firstSession = session.startTime end
        end
        local lastWeek = Data.GetTotalBetween(db, reset - 7 * 86400, reset)
        if lastWeek >= 60 and firstSession < reset - 7 * 86400 then
            local line = "Last week you played " .. format(lastWeek) .. ", about " .. format(lastWeek / 7) .. " a day."
            local weekBefore = Data.GetTotalBetween(db, reset - 14 * 86400, reset - 7 * 86400)
            if weekBefore >= 60 and firstSession < reset - 14 * 86400 then
                local change = math.floor((lastWeek - weekBefore) / weekBefore * 100 + 0.5)
                if change <= -100 then change = -99 end -- some time was played, so never "100% less"
                if change > 0 then
                    line = line .. " " .. change .. "% more than the week before."
                elseif change < 0 then
                    line = line .. " " .. (-change) .. "% less than the week before."
                else
                    line = line .. " About the same as the week before."
                end
            end
            return line
        end
    end

    if mode == "daily" then
        local lastDay, total = Data.GetLastPlayedDay(db, todayStart)
        if lastDay and total >= 1 then
            local daysAgo = math.floor((todayStart - lastDay) / 86400 + 0.5)
            if daysAgo <= 1 then
                return "Yesterday you played " .. format(total) .. "."
            elseif daysAgo < 7 then
                return "You last played on " .. date("%A", lastDay) .. ", for " .. format(total) .. "."
            else
                return "You last played on " .. TPP.Utils.FormatDate(lastDay) .. ", for " .. format(total) .. "."
            end
        end
    end

    return nil
end

-- Crash recovery via server time cross-check
local CRASH_THRESHOLD = 600 -- 10 minutes
local CRASH_MAX_RECOVERY = 28800 -- 8 hours max recovery

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
                    -- heartbeat-excluded time is not online time, so it must show up as a shortfall if it was real play
                    accounted = accounted + session.duration + (session.afkDuration or 0) - (session.gapDuration or 0)
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
                print("|cffffd100TimePlayed+|r: Found " .. TPP.Utils.FormatDuration(gap)
                    .. " of play time that wasn't recorded and added it to your history.")
            end
        end
    end

    -- update checkpoint (use session start time so sessions are properly matched)
    db.global.serverCheckpoints[character] = {
        serverTotal = serverTotal,
        timestamp = Data.sessionStart or time(),
    }
end
