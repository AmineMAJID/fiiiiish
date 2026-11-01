--[[   -- https://discord.gg/zqcBffbMZn ]]
local RECORDS_TABLE = "qs_fisher_records"
local playerRecordsCache = {}

local LEVEL_WEIGHT = 0.012
local POWER_WEIGHT = 0.85
local BAIT_WEIGHT = 0.1
local TROPHY_GEAR_WEIGHT = 0.02
local DEPTH_WEIGHTS = { shallow = 0.0, mid = 0.12, deep = 0.26, abyss = 0.4 }
local JITTER_FACTOR = 0.06
local TROPHY_THRESHOLD = 0.9

function Clamp(val, minVal, maxVal)
    return math.max(minVal, math.min(maxVal, val))
end

function RandomFloat()
    return math.random()
end

function Jitter(factor)
    return 1 + (RandomFloat() * 2 - 1) * factor
end

function GetFishSizeConfig(fishName)
    local sizes = Config.FishSizes or {}
    return sizes[fishName] or Config.FishStats.Default
end

function CalculateBonus(options)
    local bonus = 0.0
    local maxLevel = Config.MaxBonusLevel or 60
    local level = math.min(options.level or 1, maxLevel)
    bonus = bonus + (level * LEVEL_WEIGHT)
    local power = Clamp(options.power or 0, 0, 1)
    bonus = bonus + (power * POWER_WEIGHT)
    local baitLevel = math.max((options.baitLevel or 1) - 1, 0)
    bonus = bonus + (baitLevel * BAIT_WEIGHT)
    local depth = options.depth or ""
    bonus = bonus + (DEPTH_WEIGHTS[depth] or 0)
    local gearTrophy = options.gearTrophy or 0
    bonus = bonus + (gearTrophy * TROPHY_GEAR_WEIGHT)
    return math.max(bonus, 0)
end

function RollFishStats(fishName, options)
    local statsConfig = Config.FishStats
    local fishSize = GetFishSizeConfig(fishName)
    local minWeight = fishSize.weight[1]
    local maxWeight = fishSize.weight[2]
    if not statsConfig.Enabled then
        local defaultWeight = tonumber(string.format("%.2f", (minWeight + maxWeight) / 2))
        return {
            weight = defaultWeight,
            quality = 0.5,
            trophy = false
        }
    end
    local bonus = CalculateBonus(options or {})
    local quality = Clamp(RandomFloat() ^ (1 / (1 + bonus)), 0, 1)
    local rawWeight = minWeight + ((maxWeight - minWeight) * quality)
    local weight = Clamp(rawWeight * Jitter(JITTER_FACTOR), minWeight, maxWeight)
    DebugPrint(string.format("catch %s · quality %.3f (bonus %.3f) → %.2f kg", fishName, quality, bonus, weight))
    return {
        weight = tonumber(string.format("%.2f", weight)),
        quality = tonumber(string.format("%.3f", quality)),
        trophy = quality >= TROPHY_THRESHOLD
    }
end

function LoadPlayerRecords(identifier)
    if not identifier then
        return {}
    end
    if playerRecordsCache[identifier] then
        return playerRecordsCache[identifier]
    end
    local records = {}
    local query = string.format("SELECT fish, caught, released, best_weight, best_quality, trophies FROM `%s` WHERE identifier = ?", RECORDS_TABLE)
    local result = MySQL.query.await(query, { identifier }) or {}
    for _, row in ipairs(result) do
        records[row.fish] = {
            caught = tonumber(row.caught) or 0,
            released = tonumber(row.released) or 0,
            bestWeight = tonumber(row.best_weight) or 0,
            bestQuality = tonumber(row.best_quality) or 0,
            trophies = tonumber(row.trophies) or 0
        }
    end
    playerRecordsCache[identifier] = records
    return records
end

function RecordCatch(identifier, fishName, stats, wasReleased)
    if not identifier or not fishName or not stats then
        return false
    end
    local records = LoadPlayerRecords(identifier)
    local record = records[fishName]
    if not record then
        record = { caught = 0, released = 0, bestWeight = 0, bestQuality = 0, trophies = 0 }
        records[fishName] = record
    end
    local isNewRecord = stats.weight > record.bestWeight
    record.caught = record.caught + 1
    record.released = record.released + (wasReleased and 1 or 0)
    record.bestWeight = math.max(record.bestWeight, stats.weight)
    record.bestQuality = math.max(record.bestQuality, stats.quality)
    record.trophies = record.trophies + (stats.trophy and 1 or 0)
    local query = string.format([=[
        INSERT INTO `%s`
            (identifier, fish, caught, released, best_weight, best_quality, best_at, trophies)
        VALUES (?, ?, 1, ?, ?, ?, NOW(), ?)
        ON DUPLICATE KEY UPDATE
            caught       = caught + 1,
            released     = released + VALUES(released),
            trophies     = trophies + VALUES(trophies),
            best_at      = IF(VALUES(best_weight) > best_weight, VALUES(best_at), best_at),
            best_weight  = GREATEST(best_weight, VALUES(best_weight)),
            best_quality = GREATEST(best_quality, VALUES(best_quality))
    ]=], RECORDS_TABLE)
    MySQL.query(query, {
        identifier,
        fishName,
        wasReleased and 1 or 0,
        stats.weight,
        stats.quality,
        stats.trophy and 1 or 0
    })
    return isNewRecord
end

function GetPlayerRecords(identifier)
    local records = LoadPlayerRecords(identifier)
    local list = {}
    for fish, data in pairs(records) do
        list[#list + 1] = {
            fish = fish,
            caught = data.caught,
            released = data.released,
            bestWeight = data.bestWeight,
            bestQuality = data.bestQuality,
            trophies = data.trophies
        }
    end
    return list
end

function GetRecordTotals(identifier)
    local records = LoadPlayerRecords(identifier)
    local totals = { caught = 0, released = 0, trophies = 0, species = 0, heaviest = 0 }
    for _, data in pairs(records) do
        if data.caught > 0 then
            totals.species = totals.species + 1
        end
        totals.caught = totals.caught + data.caught
        totals.released = totals.released + data.released
        totals.trophies = totals.trophies + data.trophies
        totals.heaviest = math.max(totals.heaviest, data.bestWeight)
    end
    return totals
end

AddEventHandler("playerDropped", function()
    local identifier = GetPlayeridentifier(source)
    if identifier then
        playerRecordsCache[identifier] = nil
    end
end)
--WKLeak-SbOnKxTop2v : https://discord.gg/zqcBffbMZn
--WKLeak_f2OnUbTopap : https://discord.gg/zqcBffbMZn
--WKLeak_OtOnOvTophE : https://discord.gg/zqcBffbMZn
--WKLeakmLOnYUTopUG : https://discord.gg/zqcBffbMZn
--WKLeak_DbOnGATopUK : https://discord.gg/zqcBffbMZn
