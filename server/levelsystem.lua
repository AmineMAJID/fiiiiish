--[[   -- https://discord.gg/zqcBffbMZn ]]
PlayersLevels = {}
local leaderboardWinners = {}
local leaderboardData = {
    allTime = {},
    season = {},
    daily = {}
}

local leaderboardCategories = {
    { key = "allTime", experience = "total_experience", earnings = "total_earnings" },
    { key = "season", experience = "season_experience", earnings = "season_earnings" },
    { key = "daily", experience = "daily_experience", earnings = "daily_earnings" }
}

local defaultResetIdentifier = "default_identifier"
local isResettingDaily = false
local isResettingSeason = false

function CreateFisherAccount(identifier)
    if not identifier then return end
    MySQL.insert.await("INSERT IGNORE INTO qs_fisher (identifier, level, experience, total_experience, season_experience, season_earnings, total_earnings, daily_experience, daily_earnings) VALUES (?, 1, 0, 0, 0, 0, 0, 0, 0)", {
        identifier
    })
    LoadPlayer(identifier)
end

function obtainAndSendWinners()
    if not Config.EnableLeaderboard then return end

    MySQL.query("SELECT position, identifier, reward_amount, reward_type FROM qs_fisher_leaderboard_winners", {}, function(results)
        leaderboardWinners = {}
        for _, winner in ipairs(results or {}) do
            if winner.identifier then
                if Config.Framework == "esx" then
                    MySQL.query("SELECT firstname, lastname FROM users WHERE identifier = ?", { winner.identifier }, function(users)
                        local name = "Unknown"
                        if users and users[1] then
                            local firstName = users[1].firstname or "Unknown"
                            local lastName = users[1].lastname or ""
                            name = firstName .. " " .. lastName
                        end
                        leaderboardWinners[#leaderboardWinners + 1] = {
                            position = winner.position,
                            name = name,
                            reward_amount = winner.reward_amount,
                            reward_type = winner.reward_type
                        }
                    end)
                elseif Config.Framework == "qb" then
                    MySQL.query("SELECT charinfo FROM players WHERE citizenid = ?", { winner.identifier }, function(players)
                        local name = "Unknown"
                        if players and players[1] and players[1].charinfo then
                            local charInfo = json.decode(players[1].charinfo)
                            if charInfo then
                                local firstName = charInfo.firstname or "Unknown"
                                local lastName = charInfo.lastname or ""
                                name = firstName .. " " .. lastName
                            end
                        end
                        leaderboardWinners[#leaderboardWinners + 1] = {
                            position = winner.position,
                            name = name,
                            reward_amount = winner.reward_amount,
                            reward_type = winner.reward_type
                        }
                    end)
                end
            end
        end
    end)
end

function LoadPlayer(identifier)
    if not identifier then return end

    MySQL.query("SELECT level, experience, total_experience, season_experience, season_earnings, total_earnings, daily_experience, daily_earnings FROM qs_fisher WHERE identifier = ?", { identifier }, function(rows)
        if rows and rows[1] then
            PlayersLevels[identifier] = {
                level = rows[1].level,
                experience = rows[1].experience,
                total_experience = rows[1].total_experience,
                season_experience = rows[1].season_experience,
                season_earnings = rows[1].season_earnings,
                total_earnings = rows[1].total_earnings,
                daily_experience = rows[1].daily_experience,
                daily_earnings = rows[1].daily_earnings
            }
        else
            CreateFisherAccount(identifier)
        end
    end)

    MySQL.query("SELECT * FROM qs_fisher_rewards WHERE identifier = ?", { identifier }, function(rewards)
        local player = GetPlayerFromIdentifier(identifier)
        if not player then return end

        for _, reward in ipairs(rewards or {}) do
            AddMoney(player, reward.reward_amount)
            MySQL.update("DELETE FROM qs_fisher_rewards WHERE id = ?", { reward.id })
        end
    end)
end

function GetExperienceForLevel(level)
    local base = tonumber(Config.LevelExperience.BaseExperience) or 3500
    local growth = tonumber(Config.LevelExperience.GrowthFactor) or 1.1
    return math.max(math.floor(base * (growth ^ (level - 1))), 1)
end

function getPlayerLevel(identifier, callback)
    if PlayersLevels[identifier] then
        callback(PlayersLevels[identifier].level, PlayersLevels[identifier].experience)
    else
        callback(1, 0)
    end
end

function GetLevelBonuses(level)
    local cappedLevel = math.min(level or 1, Config.MaxBonusLevel or 60)
    return {
        fightEase = cappedLevel * Config.LevelExperience.FightEase,
        extraCatchChance = cappedLevel * Config.LevelExperience.ExtraCatchChance,
        biteTimeReduction = cappedLevel * Config.LevelExperience.BiteTimeReduction
    }
end

function AddExperience(identifier, amount, targetSource)
    local expToAdd = math.floor(tonumber(amount) or 0)
    if not identifier or expToAdd <= 0 then return end

    if not targetSource then
        targetSource = GetPlayerFromIdentifier(identifier)
    end

    getPlayerLevel(identifier, function(currentLevel, currentExp)
        local playerData = PlayersLevels[identifier]
        if not playerData then return end

        local newExp = currentExp + expToAdd
        local totalExp = (playerData.total_experience or 0) + expToAdd
        local seasonExp = (playerData.season_experience or 0) + expToAdd
        local dailyExp = (playerData.daily_experience or 0) + expToAdd
        local initialLevel = currentLevel
        local expNeeded = GetExperienceForLevel(currentLevel)
        local loops = 0

        while newExp >= expNeeded and loops < 1000 do
            newExp = newExp - expNeeded
            currentLevel = currentLevel + 1
            loops = loops + 1
            expNeeded = GetExperienceForLevel(currentLevel)

            if Config.QuasarInventoryQuests then
                TellQuasarInventory("UpdateQuestProgress", targetSource, "level_up_fisher", 5)
            end

            if targetSource then
                TriggerClientEvent("qs-fisher:sendNotification", targetSource, "notify", "success", Lang("LEVEL_UP") .. currentLevel .. "!")
            end
        end

        playerData.level = currentLevel
        playerData.experience = newExp
        playerData.total_experience = totalExp
        playerData.season_experience = seasonExp
        playerData.daily_experience = dailyExp

        MySQL.update("UPDATE qs_fisher SET level = ?, experience = ?, total_experience = ?, season_experience = ?, daily_experience = ? WHERE identifier = ?", {
            currentLevel,
            newExp,
            totalExp,
            seasonExp,
            dailyExp,
            identifier
        })

        if targetSource then
            TriggerClientEvent("qs-fisher:updateLevelAndExperience", targetSource, currentLevel, newExp, expNeeded)
        end

        if SendWebhook then
            local levelText = tostring(currentLevel)
            if initialLevel ~= currentLevel then
                levelText = string.format("%d \226\134\146 %d", initialLevel, currentLevel)
            end

            SendWebhook("ExperienceGiven", targetSource, "Experience", nil, {
                WebhookField("Gained", "+" .. math.floor(expToAdd)),
                WebhookField("Level", levelText),
                WebhookField("Toward next", string.format("%d / %d", math.floor(newExp), expNeeded)),
                WebhookField("Total", math.floor(totalExp))
            })
        end
    end)
end

function AddEarnings(identifier, amount)
    local earningsToAdd = math.floor(tonumber(amount) or 0)
    if not identifier or earningsToAdd <= 0 then return end

    local playerData = PlayersLevels[identifier]
    if playerData then
        playerData.total_earnings = (playerData.total_earnings or 0) + earningsToAdd
        playerData.season_earnings = (playerData.season_earnings or 0) + earningsToAdd
        playerData.daily_earnings = (playerData.daily_earnings or 0) + earningsToAdd
    end

    MySQL.update("UPDATE qs_fisher SET total_earnings = total_earnings + ?, season_earnings = season_earnings + ?, daily_earnings = daily_earnings + ? WHERE identifier = ?", {
        earningsToAdd,
        earningsToAdd,
        earningsToAdd,
        identifier
    })
end

lib.callback.register("qs-fisher:checkPlayerLevel", function(source)
    local identifier = GetPlayeridentifier(source)
    if not identifier then
        return 1, 0, GetExperienceForLevel(1)
    end

    local cachedData = PlayersLevels[identifier]
    if cachedData then
        return cachedData.level, cachedData.experience, GetExperienceForLevel(cachedData.level)
    end

    local row = MySQL.single.await("SELECT level, experience, total_experience, season_experience, season_earnings, total_earnings, daily_experience, daily_earnings FROM qs_fisher WHERE identifier = ?", {
        identifier
    })

    if not row then
        CreateFisherAccount(identifier)
        row = {
            level = 1,
            experience = 0,
            total_experience = 0,
            season_experience = 0,
            daily_experience = 0,
            total_earnings = 0,
            season_earnings = 0,
            daily_earnings = 0
        }
    end

    if not PlayersLevels[identifier] then
        PlayersLevels[identifier] = {
            level = row.level,
            experience = row.experience,
            total_experience = row.total_experience,
            season_experience = row.season_experience,
            season_earnings = row.season_earnings,
            total_earnings = row.total_earnings,
            daily_experience = row.daily_experience,
            daily_earnings = row.daily_earnings
        }
    end

    return row.level, row.experience, GetExperienceForLevel(row.level)
end)

lib.callback.register("qs-fisher:getPlayerIdentifier", function(source)
    return GetPlayeridentifier(source)
end)

function FetchLeaderboardCategory(categoryConfig, limitCount)
    local rows
    if Config.Framework == "qb" then
        local query = string.format([[
            SELECT f.identifier, f.%s AS experience, f.%s AS earnings, p.charinfo
            FROM qs_fisher f
            LEFT JOIN players p ON p.citizenid = f.identifier
            WHERE f.%s > 0
            ORDER BY f.%s DESC
            LIMIT ?
        ]], categoryConfig.experience, categoryConfig.earnings, categoryConfig.experience, categoryConfig.experience)
        rows = MySQL.query.await(query, { limitCount })
    else
        local query = string.format([[
            SELECT f.identifier, f.%s AS experience, f.%s AS earnings, u.firstname, u.lastname
            FROM qs_fisher f
            LEFT JOIN users u ON u.identifier = f.identifier
            WHERE f.%s > 0
            ORDER BY f.%s DESC
            LIMIT ?
        ]], categoryConfig.experience, categoryConfig.earnings, categoryConfig.experience, categoryConfig.experience)
        rows = MySQL.query.await(query, { limitCount })
    end

    local entries = {}
    for place, row in ipairs(rows or {}) do
        local name = "Unknown"
        if Config.Framework == "qb" then
            if row.charinfo then
                local charInfo = json.decode(row.charinfo)
                if charInfo then
                    local firstName = charInfo.firstname or "Unknown"
                    local lastName = charInfo.lastname or ""
                    name = firstName .. " " .. lastName
                end
            end
        else
            if row.firstname then
                name = row.firstname .. " " .. (row.lastname or "")
            end
        end

        entries[#entries + 1] = {
            identifier = row.identifier,
            name = name,
            place = place,
            experience = row.experience,
            earnings = row.earnings
        }
    end

    return entries
end

function FetchFishRecords(columnName, limitCount)
    local rows
    if Config.Framework == "qb" then
        local query = string.format([[
            SELECT r.identifier, r.fish, r.best_weight, r.best_quality, p.charinfo
            FROM qs_fisher_records r
            LEFT JOIN players p ON p.citizenid = r.identifier
            WHERE r.%s > 0
            ORDER BY r.%s DESC
            LIMIT ?
        ]], columnName, columnName)
        rows = MySQL.query.await(query, { limitCount })
    else
        local query = string.format([[
            SELECT r.identifier, r.fish, r.best_weight, r.best_quality, u.firstname, u.lastname
            FROM qs_fisher_records r
            LEFT JOIN users u ON u.identifier = r.identifier
            WHERE r.%s > 0
            ORDER BY r.%s DESC
            LIMIT ?
        ]], columnName, columnName)
        rows = MySQL.query.await(query, { limitCount })
    end

    local entries = {}
    for place, row in ipairs(rows or {}) do
        local name = "Unknown"
        if Config.Framework == "qb" then
            if row.charinfo then
                local charInfo = json.decode(row.charinfo)
                if charInfo then
                    local firstName = charInfo.firstname or "Unknown"
                    local lastName = charInfo.lastname or ""
                    name = firstName .. " " .. lastName
                end
            end
        else
            if row.firstname then
                name = row.firstname .. " " .. (row.lastname or "")
            end
        end

        local fishLabel = row.fish
        if FishLabel then
            local label = FishLabel(row.fish)
            if label then
                fishLabel = label
            end
        end

        entries[#entries + 1] = {
            identifier = row.identifier,
            name = name,
            place = place,
            fish = row.fish,
            label = fishLabel,
            weight = tonumber(row.best_weight) or 0,
            quality = tonumber(row.best_quality) or 0
        }
    end

    return entries
end

function UpdateLeaderboardCache()
    if not Config.EnableLeaderboard then return end

    local maxPlayers = math.max(tonumber(Config.MaxLeaderboardPlayers) or 100, 1)

    for _, cat in ipairs(leaderboardCategories) do
        leaderboardData[cat.key] = FetchLeaderboardCategory(cat, maxPlayers)
    end

    local recordsLimit = math.min(maxPlayers, 25)
    leaderboardData.heaviest = FetchFishRecords("best_weight", recordsLimit)

    if GetTournamentWinsBoard then
        leaderboardData.tournamentWins = GetTournamentWinsBoard(recordsLimit)
    end
end

lib.callback.register("qs-fisher:getLeaderboardInfo", function()
    if not Config.EnableLeaderboard then
        return {}, {}
    end
    return leaderboardData, leaderboardWinners
end)

if Config.EnableLeaderboard then
    lib.cron.new(string.format("*/%d * * * *", Config.UpdateLeaderboard), function()
        UpdateLeaderboardCache()
    end, { debug = false })
end

function FormatResetDate(dateValue, dateFormat, subLength)
    if not dateValue then return nil end

    local numValue = tonumber(dateValue)
    if numValue then
        return os.date(dateFormat, math.floor(numValue / 1000))
    end

    return tostring(dateValue):sub(1, subLength)
end

function resetDaily()
    if not Config.EnableLeaderboard or isResettingDaily then return end

    isResettingDaily = true
    local success, err = pcall(function()
        local currentTime = os.time()
        local currentDate = os.date("%Y-%m-%d", currentTime)
        local currentDateTime = os.date("%Y-%m-%d %H:%M:%S", currentTime)

        local resetRow = MySQL.single.await("SELECT last_daily_reset FROM qs_fisher_resets WHERE identifier = ?", {
            defaultResetIdentifier
        })

        if not resetRow then
            MySQL.insert.await("INSERT INTO qs_fisher_resets (identifier, last_daily_reset, last_season_reset) VALUES (?, ?, ?)", {
                defaultResetIdentifier,
                currentDateTime,
                currentDateTime
            })
            return
        end

        local formattedLastReset = FormatResetDate(resetRow.last_daily_reset, "%Y-%m-%d", 10)
        if formattedLastReset == currentDate then
            return
        end

        local rowsAffected = MySQL.update.await("UPDATE qs_fisher_resets SET last_daily_reset = ? WHERE identifier = ? AND (last_daily_reset IS NULL OR DATE(last_daily_reset) <> ?)", {
            currentDateTime,
            defaultResetIdentifier,
            currentDate
        })

        if not rowsAffected or rowsAffected == 0 then
            return
        end

        MySQL.update.await("DELETE FROM qs_fisher_leaderboard_winners WHERE reward_type = ?", { "daily" })

        local topDaily = MySQL.query.await("SELECT identifier FROM qs_fisher WHERE daily_experience > 0 ORDER BY daily_experience DESC LIMIT 3", {})

        for rank, winner in ipairs(topDaily or {}) do
            local rewardAmount = Config.LeaderBoardRewards.Daily[rank]
            if rewardAmount then
                local player = GetPlayerFromIdentifier(winner.identifier)
                if player then
                    AddMoney(player, rewardAmount)
                else
                    MySQL.insert.await("INSERT INTO qs_fisher_rewards (identifier, reward_type, reward_amount) VALUES (?, ?, ?)", {
                        winner.identifier,
                        "Daily",
                        rewardAmount
                    })
                end

                MySQL.insert.await("INSERT INTO qs_fisher_leaderboard_winners (position, identifier, reward_amount, reward_type) VALUES (?, ?, ?, ?)", {
                    rank,
                    winner.identifier,
                    rewardAmount,
                    "daily"
                })
            end
        end

        MySQL.update.await("UPDATE qs_fisher SET daily_experience = 0, daily_earnings = 0", {})

        for _, playerInfo in pairs(PlayersLevels) do
            playerInfo.daily_experience = 0
            playerInfo.daily_earnings = 0
        end

        print("[INFO] Fisher daily leaderboard reset.")
        obtainAndSendWinners()
    end)

    isResettingDaily = false
    if not success then
        print("[ERROR] Fisher daily reset failed:", err)
    end
end

function resetSeason()
    if not Config.EnableLeaderboard or isResettingSeason then return end

    isResettingSeason = true
    local success, err = pcall(function()
        local currentTime = os.time()
        local currentMonth = os.date("%Y-%m", currentTime)
        local currentDateTime = os.date("%Y-%m-%d %H:%M:%S", currentTime)

        local resetRow = MySQL.single.await("SELECT last_season_reset FROM qs_fisher_resets WHERE identifier = ?", {
            defaultResetIdentifier
        })

        if not resetRow then return end

        local formattedLastReset = FormatResetDate(resetRow.last_season_reset, "%Y-%m", 7)
        if formattedLastReset == currentMonth then
            return
        end

        local rowsAffected = MySQL.update.await('UPDATE qs_fisher_resets SET last_season_reset = ? WHERE identifier = ? AND (last_season_reset IS NULL OR DATE_FORMAT(last_season_reset, "%Y-%m") <> ?)', {
            currentDateTime,
            defaultResetIdentifier,
            currentMonth
        })

        if not rowsAffected or rowsAffected == 0 then
            return
        end

        MySQL.update.await("DELETE FROM qs_fisher_leaderboard_winners WHERE reward_type = ?", { "Season" })

        local topSeason = MySQL.query.await("SELECT identifier FROM qs_fisher WHERE season_experience > 0 ORDER BY season_experience DESC LIMIT 3", {})

        for rank, winner in ipairs(topSeason or {}) do
            local rewardAmount = Config.LeaderBoardRewards.Season[rank]
            if rewardAmount then
                local player = GetPlayerFromIdentifier(winner.identifier)
                if player then
                    AddMoney(player, rewardAmount)
                else
                    MySQL.insert.await("INSERT INTO qs_fisher_rewards (identifier, reward_type, reward_amount) VALUES (?, ?, ?)", {
                        winner.identifier,
                        "Season",
                        rewardAmount
                    })
                end

                MySQL.insert.await("INSERT INTO qs_fisher_leaderboard_winners (position, identifier, reward_amount, reward_type) VALUES (?, ?, ?, ?)", {
                    rank,
                    winner.identifier,
                    rewardAmount,
                    "Season"
                })
            end
        end

        MySQL.update.await("UPDATE qs_fisher SET season_experience = 0, season_earnings = 0", {})

        for _, playerInfo in pairs(PlayersLevels) do
            playerInfo.season_experience = 0
            playerInfo.season_earnings = 0
        end

        print("[INFO] Fisher season leaderboard reset.")
        obtainAndSendWinners()
    end)

    isResettingSeason = false
    if not success then
        print("[ERROR] Fisher season reset failed:", err)
    end
end

if Config.EnableLeaderboard then
    lib.cron.new("0 0 * * *", function()
        resetDaily()
    end, { debug = false })

    lib.cron.new("0 0 1 * *", function()
        resetSeason()
    end, { debug = false })
end

function LoadAllOnlinePlayers()
    for _, playerId in ipairs(GetPlayers()) do
        local identifier = GetPlayeridentifier(playerId)
        if identifier then
            LoadPlayer(identifier)
        end
    end
end

AddEventHandler("esx:playerLoaded", function(source, xPlayer)
    if xPlayer and xPlayer.identifier then
        LoadPlayer(xPlayer.identifier)
    end
end)

AddEventHandler("QBCore:Server:PlayerLoaded", function(playerData)
    if playerData and playerData.PlayerData and playerData.PlayerData.citizenid then
        LoadPlayer(playerData.PlayerData.citizenid)
    end
end)

AddEventHandler("onResourceStart", function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end

    EnsureSchema()
    Wait(1000)
    LoadAllOnlinePlayers()

    local currentDateTime = os.date("%Y-%m-%d %H:%M:%S")
    local existingReset = MySQL.single.await("SELECT identifier FROM qs_fisher_resets WHERE identifier = ?", {
        defaultResetIdentifier
    })

    if existingReset then
        MySQL.update.await("UPDATE qs_fisher_resets SET last_daily_reset = COALESCE(last_daily_reset, ?), last_season_reset = COALESCE(last_season_reset, ?) WHERE identifier = ?", {
            currentDateTime,
            currentDateTime,
            defaultResetIdentifier
        })
    else
        MySQL.insert.await("INSERT INTO qs_fisher_resets (identifier, last_daily_reset, last_season_reset) VALUES (?, ?, ?)", {
            defaultResetIdentifier,
            currentDateTime,
            currentDateTime
        })
    end

    if Config.EnableLeaderboard then
        UpdateLeaderboardCache()
        obtainAndSendWinners()
        resetDaily()
        Wait(1000)
        resetSeason()
    end
end)

lib.callback.register("qs-fisher:getDailyTimeRemaining", function()
    local dateInfo = os.date("*t")
    local hoursRemaining = 0 - dateInfo.hour
    local minutesRemaining = 0 - dateInfo.min

    if minutesRemaining < 0 then
        minutesRemaining = minutesRemaining + 60
        hoursRemaining = hoursRemaining - 1
    end

    if hoursRemaining < 0 then
        hoursRemaining = hoursRemaining + 24
    end

    return hoursRemaining, minutesRemaining
end)

lib.callback.register("qs-fisher:getTimeRemainingUntilNextMonth", function()
    local currentDate = os.date("*t")
    local targetYear = currentDate.year
    local targetMonth = currentDate.month + 1

    if targetMonth > 12 then
        targetMonth = 1
        targetYear = targetYear + 1
    end

    local nextMonthTimestamp = os.time({
        year = targetYear,
        month = targetMonth,
        day = 1,
        hour = 0,
        min = 0,
        sec = 0
    })

    local secondsRemaining = nextMonthTimestamp - os.time(currentDate)
    local days = math.floor(secondsRemaining / 86400)
    local hours = math.floor((secondsRemaining % 86400) / 3600)
    local minutes = math.floor((secondsRemaining % 3600) / 60)

    return days, hours, minutes
end)
--WKLeak-ovOnYTTopu0 : https://discord.gg/zqcBffbMZn
--WKLeaksyyOnk5Top3Y : https://discord.gg/zqcBffbMZn
--WKLeak5KOnfXTop7c : https://discord.gg/zqcBffbMZn
--WKLeaksLqOnYzTop0f : https://discord.gg/zqcBffbMZn
--WKLeak_E2On@!TopGf : https://discord.gg/zqcBffbMZn
