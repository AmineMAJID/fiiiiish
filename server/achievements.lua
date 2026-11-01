--[[   -- https://discord.gg/zqcBffbMZn ]]
local ACHIEVEMENTS_TABLE = "qs_fisher_achievements"
local playerAchievementsCache = {}
local SPECIES_PREFIX = "species:"
local cachedAchievementsList = nil

function GetAchievementsList()
    if cachedAchievementsList then
        return cachedAchievementsList
    end
    local list = {}
    local configAchievements = (Config.Achievements and Config.Achievements.List) or {}
    for _, item in ipairs(configAchievements) do
        list[#list + 1] = {
            id = item.id,
            icon = item.icon or "trophy",
            type = item.type,
            value = item.value or 1,
            reward = item.reward or 0,
            experience = item.experience or 0,
            species = nil
        }
    end
    local speciesReward = (Config.Achievements and Config.Achievements.SpeciesReward) or {}
    for _, fish in ipairs(GetOrderedFish()) do
        list[#list + 1] = {
            id = SPECIES_PREFIX .. fish.name,
            icon = "fish",
            type = "species",
            value = 1,
            reward = speciesReward.money or 0,
            experience = speciesReward.experience or 0,
            species = fish.name,
            label = fish.label
        }
    end
    cachedAchievementsList = list
    return list
end

function GetAchievementCurrentValue(achievement, totals, recordsByFish)
    local achType = achievement.type
    if achType == "species" then
        local fishData = recordsByFish[achievement.species]
        return (fishData and fishData.caught) or 0
    elseif achType == "totalCatches" then
        return totals.caught
    elseif achType == "speciesCount" then
        return totals.species
    elseif achType == "trophies" then
        return totals.trophies
    elseif achType == "released" then
        return totals.released
    elseif achType == "heaviest" then
        return totals.heaviest
    end
    return 0
end

function LoadPlayerAchievements(identifier)
    if not identifier then
        return {}
    end
    if playerAchievementsCache[identifier] then
        return playerAchievementsCache[identifier]
    end
    local status = {}
    local query = string.format("SELECT achievement, claimed_at FROM `%s` WHERE identifier = ?", ACHIEVEMENTS_TABLE)
    local result = MySQL.query.await(query, { identifier }) or {}
    for _, row in ipairs(result) do
        status[row.achievement] = (row.claimed_at ~= nil)
    end
    playerAchievementsCache[identifier] = status
    return status
end

function GetPlayerFishRecordsLookup(identifier)
    local lookup = {}
    for _, record in ipairs(GetPlayerRecords(identifier)) do
        lookup[record.fish] = record
    end
    return lookup
end

function CheckAchievements(source, identifier)
    local achievementsConfig = Config.Achievements or {}
    if not achievementsConfig.Enabled or not identifier then
        return {}
    end
    local playerStatus = LoadPlayerAchievements(identifier)
    local totals = GetRecordTotals(identifier)
    local recordsByFish = GetPlayerFishRecordsLookup(identifier)
    local unlockedNow = {}
    for _, achievement in ipairs(GetAchievementsList()) do
        if playerStatus[achievement.id] == nil then
            local currentVal = GetAchievementCurrentValue(achievement, totals, recordsByFish)
            if currentVal >= achievement.value then
                playerStatus[achievement.id] = false
                unlockedNow[#unlockedNow + 1] = achievement
                local query = string.format("INSERT IGNORE INTO `%s` (identifier, achievement) VALUES (?, ?)", ACHIEVEMENTS_TABLE)
                MySQL.query(query, { identifier, achievement.id })
            end
        end
    end
    return unlockedNow
end

function GetAchievementById(achievementId)
    for _, achievement in ipairs(GetAchievementsList()) do
        if achievement.id == achievementId then
            return achievement
        end
    end
    return nil
end

lib.callback.register("qs-fisher:claimAchievement", function(source, achievementId)
    local achievementsConfig = Config.Achievements or {}
    if not achievementsConfig.Enabled then
        return { ok = false, reason = "disabled" }
    end
    if type(achievementId) ~= "string" or achievementId == "" then
        return { ok = false, reason = "unknown" }
    end
    local identifier = GetPlayeridentifier(source)
    if not identifier then
        return { ok = false, reason = "unavailable" }
    end
    local achievement = GetAchievementById(achievementId)
    if not achievement then
        return { ok = false, reason = "unknown" }
    end
    local playerStatus = LoadPlayerAchievements(identifier)
    local status = playerStatus[achievementId]
    if status == nil then
        return { ok = false, reason = "locked" }
    end
    if status == true then
        return { ok = false, reason = "claimed" }
    end
    local query = string.format("UPDATE `%s` SET claimed_at = NOW() WHERE identifier = ? AND achievement = ? AND claimed_at IS NULL", ACHIEVEMENTS_TABLE)
    local affectedRows = MySQL.update.await(query, { identifier, achievementId }) or 0
    if affectedRows < 1 then
        playerStatus[achievementId] = true
        return { ok = false, reason = "claimed" }
    end
    playerStatus[achievementId] = true
    if achievement.experience > 0 then
        AddExperience(identifier, achievement.experience, source)
    end
    if achievement.reward > 0 then
        AddMoney(source, achievement.reward)
        AddEarnings(identifier, achievement.reward)
    end
    if SendWebhook and achievement.reward > 0 then
        SendWebhook("MoneyPaid", source, "Paid", "Achievement claimed: " .. achievementId, {
            WebhookField("Amount", "$" .. math.floor(achievement.reward)),
            WebhookField("For", "Claiming an achievement")
        })
    end
    return {
        ok = true,
        id = achievementId,
        reward = achievement.reward,
        experience = achievement.experience
    }
end)

lib.callback.register("qs-fisher:getAchievements", function(source)
    local achievementsConfig = Config.Achievements or {}
    if not achievementsConfig.Enabled then
        return {
            enabled = false,
            achievements = {},
            totals = {}
        }
    end
    local identifier = GetPlayeridentifier(source)
    if not identifier then
        return {
            enabled = true,
            achievements = {},
            totals = {}
        }
    end
    local playerStatus = LoadPlayerAchievements(identifier)
    local totals = GetRecordTotals(identifier)
    local recordsByFish = GetPlayerFishRecordsLookup(identifier)
    local achievementsList = {}
    for _, item in ipairs(GetAchievementsList()) do
        local rawValue = GetAchievementCurrentValue(item, totals, recordsByFish)
        local bestData = nil
        if item.species and recordsByFish[item.species] then
            local fishRecord = recordsByFish[item.species]
            bestData = {
                weight = fishRecord.bestWeight,
                caught = fishRecord.caught,
                trophies = fishRecord.trophies
            }
        end
        achievementsList[#achievementsList + 1] = {
            id = item.id,
            icon = item.icon,
            type = item.type,
            target = item.value,
            progress = math.min(rawValue, item.value),
            raw = rawValue,
            unlocked = (playerStatus[item.id] ~= nil),
            claimed = (playerStatus[item.id] == true),
            reward = item.reward,
            experience = item.experience,
            species = item.species,
            label = item.label,
            best = bestData
        }
    end
    local claimableCount = 0
    for _, entry in ipairs(achievementsList) do
        if entry.unlocked and not entry.claimed then
            claimableCount = claimableCount + 1
        end
    end
    return {
        enabled = true,
        achievements = achievementsList,
        totals = totals,
        claimable = claimableCount,
        records = GetPlayerRecords(identifier)
    }
end)

AddEventHandler("playerDropped", function()
    local identifier = GetPlayeridentifier(source)
    if identifier then
        playerAchievementsCache[identifier] = nil
    end
end)
--WKLeak-f@OnjeTopjU : https://discord.gg/zqcBffbMZn
--WKLeak_arOnj0TopHA : https://discord.gg/zqcBffbMZn
--WKLeak-KwOnd3Top0W : https://discord.gg/zqcBffbMZn
--WKLeaksYKOnN2TopZo : https://discord.gg/zqcBffbMZn
--WKLeaksUjOn@eTop9E : https://discord.gg/zqcBffbMZn
