--[[   -- https://discord.gg/zqcBffbMZn ]]
local TOURNAMENT_TABLE = "qs_fisher_tournaments"
local activeTournament = nil
local isAnnouncementPending = false

function GetTournamentsConfig()
    return Config.Tournaments or {}
end

function IsPlayerEligible(src)
    local cfg = GetTournamentsConfig()
    if cfg.FishersOnly and IsPlayerFisher then
        return IsPlayerFisher(src) == true
    end
    return true
end

function GetEligiblePlayers()
    local eligible = {}
    for _, playerIdStr in ipairs(GetPlayers()) do
        local targetId = tonumber(playerIdStr)
        if targetId and IsPlayerEligible(targetId) then
            eligible[#eligible + 1] = targetId
        end
    end
    return eligible
end

function BroadcastToEligible(eventName, ...)
    for _, playerId in ipairs(GetEligiblePlayers()) do
        TriggerClientEvent(eventName, playerId, ...)
    end
end

function IsCoordsInZone(coords, zone)
    if not coords or not zone or not zone.coords or not zone.radius then
        return false
    end
    local dx = coords.x - zone.coords.x
    local dy = coords.y - zone.coords.y
    return (dx * dx + dy * dy) <= (zone.radius * zone.radius)
end

function GetTournamentRankings()
    if not activeTournament then
        return nil
    end

    local heaviestList = {}
    local mostList = {}

    for identifier, entry in pairs(activeTournament.entries) do
        if entry.heaviest > 0 then
            heaviestList[#heaviestList + 1] = {
                identifier = identifier,
                name = entry.name,
                weight = entry.heaviest,
                label = entry.heaviestLabel
            }
        end
        mostList[#mostList + 1] = {
            identifier = identifier,
            name = entry.name,
            count = entry.count
        }
    end

    table.sort(heaviestList, function(a, b)
        return a.weight > b.weight
    end)

    table.sort(mostList, function(a, b)
        return a.count > b.count
    end)

    return {
        heaviest = heaviestList,
        most = mostList
    }
end

function BroadcastTournamentUpdate()
    if not activeTournament then
        return
    end
    local rankings = GetTournamentRankings()
    local remaining = math.max(activeTournament.endsAt - os.time(), 0)

    BroadcastToEligible("qs-fisher:tournamentUpdate", {
        zone = activeTournament.zone.label,
        coords = activeTournament.zone.coords,
        radius = activeTournament.zone.radius,
        blip = GetTournamentsConfig().Blip,
        seconds = remaining,
        heaviest = rankings.heaviest,
        most = rankings.most
    })
end

function RecordTournamentWin(identifier, category)
    if not identifier then
        return
    end
    local winHeaviest = (category == "heaviest") and 1 or 0
    local winMost = (category == "most") and 1 or 0

    local query = ([[
        INSERT INTO `%s` (identifier, wins_heaviest, wins_most, wins_total, last_win)
        VALUES (?, ?, ?, 1, NOW())
        ON DUPLICATE KEY UPDATE
            wins_heaviest = wins_heaviest + VALUES(wins_heaviest),
            wins_most     = wins_most + VALUES(wins_most),
            wins_total    = wins_total + 1,
            last_win      = NOW()
    ]]):format(TOURNAMENT_TABLE)

    MySQL.query(query, { identifier, winHeaviest, winMost })
end

function GetTournamentWinsBoard(limit)
    local rawResults = nil
    if Config.Framework == "qb" then
        local query = ([[
            SELECT t.identifier, t.wins_total, t.wins_heaviest, t.wins_most, p.charinfo
            FROM `%s` t
            LEFT JOIN players p ON p.citizenid = t.identifier
            WHERE t.wins_total > 0
            ORDER BY t.wins_total DESC
            LIMIT ?
        ]]):format(TOURNAMENT_TABLE)
        rawResults = MySQL.query.await(query, { limit })
    else
        local query = ([[
            SELECT t.identifier, t.wins_total, t.wins_heaviest, t.wins_most, u.firstname, u.lastname
            FROM `%s` t
            LEFT JOIN users u ON u.identifier = t.identifier
            WHERE t.wins_total > 0
            ORDER BY t.wins_total DESC
            LIMIT ?
        ]]):format(TOURNAMENT_TABLE)
        rawResults = MySQL.query.await(query, { limit })
    end

    local leaderboard = {}
    for place, row in ipairs(rawResults or {}) do
        local playerName = "Unknown"
        if Config.Framework == "qb" then
            if row.charinfo then
                local charinfo = json.decode(row.charinfo)
                if charinfo then
                    local first = charinfo.firstname or "Unknown"
                    local last = charinfo.lastname or ""
                    playerName = first .. " " .. last
                end
            end
        else
            if row.firstname then
                local first = row.firstname
                local last = row.lastname or ""
                playerName = first .. " " .. last
            end
        end

        leaderboard[#leaderboard + 1] = {
            identifier = row.identifier,
            name = playerName,
            place = place,
            wins = tonumber(row.wins_total) or 0,
            winsHeavy = tonumber(row.wins_heaviest) or 0,
            winsMost = tonumber(row.wins_most) or 0
        }
    end
    return leaderboard
end

function GetNextTournamentInfo()
    local cfg = GetTournamentsConfig()
    if not cfg.Enabled then
        return nil
    end

    if activeTournament then
        local minsRemaining = math.max(math.floor((activeTournament.endsAt - os.time()) / 60), 0)
        return {
            live = true,
            zone = activeTournament.zone.label,
            minutes = minsRemaining
        }
    end

    local nextAt = nil
    local minDiffSec = nil
    local nowTime = os.time()
    local schedule = cfg.Schedule or {}

    for _, entry in ipairs(schedule) do
        local atStr = tostring(entry.at or "")
        local hourStr, minStr = atStr:match("^(%d+):(%d+)$")
        if hourStr then
            local nowTable = os.date("*t", nowTime)
            local targetTime = os.time({
                year = nowTable.year,
                month = nowTable.month,
                day = nowTable.day,
                hour = tonumber(hourStr),
                min = tonumber(minStr),
                sec = 0
            })
            if nowTime >= targetTime then
                targetTime = targetTime + 86400
            end
            local diffSec = targetTime - nowTime
            if not minDiffSec or diffSec < minDiffSec then
                minDiffSec = diffSec
                nextAt = entry.at
            end
        end
    end

    return {
        at = nextAt,
        inMinutes = minDiffSec and math.floor(minDiffSec / 60) or nil,
        random = (cfg.Random and cfg.Random.Enabled == true),
        duration = cfg.Duration
    }
end

function EndTournament()
    if not activeTournament then
        return
    end

    local rankings = GetTournamentRankings()
    local prizes = GetTournamentsConfig().Prizes or {}
    local minEntries = GetTournamentsConfig().MinimumEntries or 1

    local resultsPayload = {
        zone = activeTournament.zone.label,
        heaviest = {},
        most = {}
    }

    local categories = {
        heaviest = rankings.heaviest,
        most = rankings.most
    }

    for catKey, catList in pairs(categories) do
        local prizeTierList = prizes[catKey] or {}
        for place, entry in ipairs(catList) do
            local prize = prizeTierList[place]
            if not prize or #catList < minEntries then
                break
            end

            local targetPlayer = GetPlayerFromIdentifier(entry.identifier)
            if prize.money and prize.money > 0 and targetPlayer then
                AddMoney(targetPlayer, prize.money)
            end
            if prize.experience and prize.experience > 0 then
                AddExperience(entry.identifier, prize.experience, targetPlayer)
            end
            if place == 1 then
                RecordTournamentWin(entry.identifier, catKey)
            end

            local dest = resultsPayload[catKey]
            dest[#dest + 1] = {
                place = place,
                name = entry.name,
                weight = entry.weight,
                label = entry.label,
                count = entry.count,
                money = prize.money
            }
        end
    end

    local participants = {}
    for identifier, entry in pairs(activeTournament.entries) do
        local player = GetPlayerFromIdentifier(identifier) or entry.src
        if player then
            participants[player] = true
        end
    end

    local hasWinners = (#resultsPayload.heaviest > 0) or (#resultsPayload.most > 0)
    for _, playerId in ipairs(GetEligiblePlayers()) do
        local showResults = hasWinners and (participants[playerId] == true)
        TriggerClientEvent("qs-fisher:tournamentEnded", playerId, resultsPayload, showResults)
    end

    activeTournament = nil
end

function StartTournamentImmediate(zone, durationMins)
    if activeTournament then
        return false
    end

    local zones = GetTournamentsConfig().Zones or {}
    if not zone and #zones == 0 then
        return false
    end

    local chosenZone = zone or zones[math.random(1, #zones)]
    if not chosenZone then
        return false
    end

    local duration = math.max(tonumber(durationMins) or tonumber(GetTournamentsConfig().Duration) or 20, 1)
    activeTournament = {
        zone = chosenZone,
        endsAt = os.time() + (duration * 60),
        entries = {}
    }

    BroadcastToEligible("qs-fisher:tournamentStarted", {
        zone = chosenZone.label,
        coords = chosenZone.coords,
        radius = chosenZone.radius,
        seconds = duration * 60,
        blip = GetTournamentsConfig().Blip
    })

    BroadcastTournamentUpdate()
    return true
end

function AnnounceAndStartTournament(zone)
    if activeTournament or isAnnouncementPending then
        return
    end

    local announceMins = math.max(tonumber(GetTournamentsConfig().AnnounceBefore) or 0, 0)
    if announceMins <= 0 then
        return StartTournamentImmediate(zone)
    end

    local zones = GetTournamentsConfig().Zones or {}
    if not zone and #zones == 0 then
        return
    end

    local chosenZone = zone or zones[math.random(1, #zones)]
    isAnnouncementPending = true

    BroadcastToEligible("qs-fisher:tournamentAnnounced", {
        zone = chosenZone and chosenZone.label or "?",
        coords = chosenZone and chosenZone.coords or nil,
        minutes = announceMins
    })

    CreateThread(function()
        Wait(announceMins * 60000)
        isAnnouncementPending = false
        StartTournamentImmediate(chosenZone)
    end)
end

CreateThread(function()
    local lastBroadcast = 0
    while true do
        Wait(1000)
        if activeTournament then
            local now = os.time()
            if now >= activeTournament.endsAt then
                EndTournament()
            else
                if (now - lastBroadcast) >= 3 then
                    lastBroadcast = now
                    BroadcastTournamentUpdate()
                end
            end
        end
    end
end)

CreateThread(function()
    local randCfg = (GetTournamentsConfig().Random) or {}
    if not (GetTournamentsConfig().Enabled and randCfg.Enabled) then
        return
    end

    local checkInterval = math.max(tonumber(randCfg.CheckEvery) or 60, 1)
    while true do
        Wait(checkInterval * 60000)
        if not activeTournament and not isAnnouncementPending then
            local chance = randCfg.Chance or 0
            if math.random(1, 100) <= chance then
                AnnounceAndStartTournament()
            end
        end
    end
end)

function ComputeCronTime(hour, minute, offsetMinutes)
    local totalMinutes = (hour * 60 + minute - offsetMinutes) % 1440
    local targetHour = math.floor(totalMinutes / 60)
    local targetMinute = totalMinutes % 60
    return targetHour, targetMinute
end

CreateThread(function()
    local cfg = GetTournamentsConfig()
    if not cfg.Enabled then
        return
    end

    local schedule = cfg.Schedule or {}
    if #schedule == 0 then
        return
    end

    if not (lib and lib.cron) then
        return print("^1[qs-fishingjob]^0 ox_lib cron is unavailable; scheduled tournaments are off. Random ones and the admin panel still work.")
    end

    local announceOffset = math.max(tonumber(cfg.AnnounceBefore) or 0, 0)
    for _, entry in ipairs(schedule) do
        local atStr = tostring(entry.at or "")
        local hourStr, minStr = atStr:match("^(%d+):(%d+)$")
        local hour = tonumber(hourStr)
        local minute = tonumber(minStr)

        if hour and minute and hour < 24 and minute < 60 then
            local cronHour, cronMinute = ComputeCronTime(hour, minute, announceOffset)
            local cronExpr = ("%d %d * * *"):format(cronMinute, cronHour)
            lib.cron.new(cronExpr, function()
                AnnounceAndStartTournament()
            end)
        else
            print(("^1[qs-fishingjob]^0 tournament schedule entry \"%s\" is not a valid HH:MM; ignored."):format(tostring(entry.at)))
        end
    end
end)

function ReportTournamentCatch(src, identifier, weight, label, count)
    if not activeTournament or not identifier then
        return
    end
    if not IsPlayerEligible(src) then
        return
    end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then
        return
    end

    local playerCoords = GetEntityCoords(ped)
    if not IsCoordsInZone(playerCoords, activeTournament.zone) then
        return
    end

    local entry = activeTournament.entries[identifier]
    if not entry then
        entry = {
            name = ResolvePlayerName(src),
            count = 0,
            heaviest = 0,
            heaviestLabel = nil
        }
        activeTournament.entries[identifier] = entry
    end

    entry.src = src
    entry.count = entry.count + (count or 1)

    local safeWeight = weight or 0
    if safeWeight > entry.heaviest then
        entry.heaviest = weight
        entry.heaviestLabel = label
    end
end

lib.callback.register("qs-fisher:getTournamentInfo", function()
    local info = GetNextTournamentInfo()
    if info and info.live and activeTournament then
        info.coords = activeTournament.zone.coords
    end
    return info
end)

function StartTournament(zone, duration)
    return StartTournamentImmediate(zone, duration) == true
end

function StopTournament()
    if not activeTournament then
        return false
    end
    EndTournament()
    return true
end

function GetActiveTournament()
    if not activeTournament then
        return nil
    end
    local remaining = math.max(activeTournament.endsAt - os.time(), 0)
    return {
        zone = activeTournament.zone.label,
        seconds = remaining
    }
end

lib.callback.register("qs-fisher:getTournament", function(src)
    if not IsPlayerEligible(src) or not activeTournament then
        return nil
    end

    local rankings = GetTournamentRankings()
    local remaining = math.max(activeTournament.endsAt - os.time(), 0)

    return {
        zone = activeTournament.zone.label,
        coords = activeTournament.zone.coords,
        radius = activeTournament.zone.radius,
        seconds = remaining,
        blip = GetTournamentsConfig().Blip,
        heaviest = rankings.heaviest,
        most = rankings.most
    }
end)
--WKLeak-aWOn!LTop$j : https://discord.gg/zqcBffbMZn
--WKLeakU2On4ITopz7 : https://discord.gg/zqcBffbMZn
--WKLeak-v5On6DTop2C : https://discord.gg/zqcBffbMZn
--WKLeakb-OnhUTopJD : https://discord.gg/zqcBffbMZn
--WKLeak-MVOn9$Topah : https://discord.gg/zqcBffbMZn
