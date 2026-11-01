--[[   -- https://discord.gg/zqcBffbMZn ]]
local TABLE_NAME = "qs_fisher_crabtraps"
local ActiveCrabTraps = {}

local MAX_PULL_DIST = 3.5
local MAX_PLACE_DIST = 12.0
local MIN_TRAP_SPACING = 20.0

function GetCrabTrapsConfig()
    return Config.CrabTraps or {}
end

function GetDistance2D(x1, y1, x2, y2)
    local dx = x1 - x2
    local dy = y1 - y2
    return math.sqrt(dx * dx + dy * dy)
end

function ToNumberSafe(val)
    local num = tonumber(val)
    if num and num == num and num ~= math.huge and num ~= -math.huge then
        return num
    end
    return nil
end

function CalculateSoakFullness(trap)
    local soakCfg = GetCrabTrapsConfig().Soak or {}
    local fullAtSec = math.max(tonumber(soakCfg.FullAt) or 45, 1) * 60
    local elapsed = os.time() - (trap.placedAt or 0)

    if elapsed >= fullAtSec then
        return 1.0
    end
    if elapsed <= 0 then
        return soakCfg.MinYield or 0.15
    end

    local progress = elapsed / fullAtSec
    local curve = tonumber(soakCfg.Curve) or 1.5
    local minYield = tonumber(soakCfg.MinYield) or 0.15

    return minYield + (1.0 - minYield) * (progress ^ curve)
end

function GetSecondsToFull(trap)
    local soakCfg = GetCrabTrapsConfig().Soak or {}
    local fullAtSec = math.max(tonumber(soakCfg.FullAt) or 45, 1) * 60
    local elapsed = os.time() - (trap.placedAt or 0)
    return math.max(fullAtSec - elapsed, 0)
end

function GetSecondsToBreak(trap)
    local decayCfg = GetCrabTrapsConfig().Decay or {}
    local soakCfg = GetCrabTrapsConfig().Soak or {}
    local fullAtSec = math.max(tonumber(soakCfg.FullAt) or 45, 1) * 60
    local breakSec = math.max(tonumber(decayCfg.BreaksAfter) or 180, 1) * 60
    local expireTime = (trap.placedAt or 0) + fullAtSec + breakSec
    return math.max(expireTime - os.time(), 0)
end

function GetPlayerTrapLimit(identifier)
    local limitCfg = GetCrabTrapsConfig().Limit or {}
    local base = math.max(tonumber(limitCfg.Base) or 1, 1)
    local maxLimit = math.max(tonumber(limitCfg.Max) or 3, base)
    local perLevel = math.max(tonumber(limitCfg.PerLevel) or 15, 1)
    local playerLevel = (PlayersLevels and PlayersLevels[identifier] and PlayersLevels[identifier].level) or 1
    local bonus = math.floor((playerLevel - 1) / perLevel)
    return math.min(base + bonus, maxLimit)
end

function GetPlayerTraps(identifier)
    local list = {}
    for _, trap in pairs(ActiveCrabTraps) do
        if trap.identifier == identifier then
            list[#list + 1] = trap
        end
    end
    return list
end

function FormatCrabTrapData(trap)
    return {
        id = trap.id,
        x = trap.x,
        y = trap.y,
        seaZ = trap.seaZ,
        waterZ = trap.waterZ,
        toFull = GetSecondsToFull(trap),
        toBreak = GetSecondsToBreak(trap),
        fullness = math.floor(CalculateSoakFullness(trap) * 100),
        band = trap.band,
        depth = math.max((trap.waterZ or 0) - (trap.seaZ or 0), 0)
    }
end

function BroadcastTrapEvent(eventName, ...)
    TriggerClientEvent(eventName, -1, ...)
end

CreateThread(function()
    if not GetCrabTrapsConfig().Enabled then
        return
    end

    while GetResourceState(GetCurrentResourceName()) ~= "started" do
        Wait(100)
    end
    Wait(2000)

    local rows = MySQL.query.await(string.format("SELECT * FROM `%s`", TABLE_NAME)) or {}
    for _, row in ipairs(rows) do
        ActiveCrabTraps[row.id] = {
            id = row.id,
            identifier = row.identifier,
            x = row.x,
            y = row.y,
            seaZ = row.sea_z,
            waterZ = row.water_z,
            band = row.band,
            placedAt = row.placed_at
        }
    end

    local count = 0
    for _ in pairs(ActiveCrabTraps) do
        count = count + 1
    end
    print(string.format("^2[qs-fishingjob]^0 %d crab trap(s) back in the water.", count))
end)

lib.callback.register("qs-fisher:placeCrabTrap", function(source, data)
    local config = GetCrabTrapsConfig()
    if not config.Enabled then
        return { ok = false, reason = "disabled" }
    end
    if type(data) ~= "table" then
        return { ok = false, reason = "bad" }
    end

    local identifier = GetPlayeridentifier(source)
    if not identifier then
        return { ok = false, reason = "bad" }
    end

    local equipCfg = (Config.FishingEquipment and Config.FishingEquipment.crab_trap) or {}
    local reqLevel = equipCfg.requiredLevel or 1
    local pLevel = (PlayersLevels and PlayersLevels[identifier] and PlayersLevels[identifier].level) or 1
    if reqLevel > pLevel then
        return { ok = false, reason = "level", level = reqLevel }
    end

    local x = ToNumberSafe(data.x)
    local y = ToNumberSafe(data.y)
    local waterZ = ToNumberSafe(data.waterZ)
    local depth = ToNumberSafe(data.depth)
    if not (x and y and waterZ and depth) then
        return { ok = false, reason = "bad" }
    end

    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then
        return { ok = false, reason = "bad" }
    end

    local pCoords = GetEntityCoords(ped)
    if GetDistance2D(x, y, pCoords.x, pCoords.y) > MAX_PLACE_DIST then
        return { ok = false, reason = "far" }
    end

    depth = math.min(math.max(depth, 0.0), 400.0)
    local minDepth = tonumber(config.MinDepth) or 10.0
    if depth < minDepth then
        return { ok = false, reason = "shallow", need = config.MinDepth }
    end

    local band = (DepthBandAt and DepthBandAt(depth)) or "mid"
    local playerTraps = GetPlayerTraps(identifier)
    local limit = GetPlayerTrapLimit(identifier)
    if #playerTraps >= limit then
        return { ok = false, reason = "limit", limit = limit }
    end

    for _, trap in pairs(ActiveCrabTraps) do
        if GetDistance2D(x, y, trap.x, trap.y) < MIN_TRAP_SPACING then
            return { ok = false, reason = "crowded" }
        end
    end

    local trapItem = config.Item or "crab_trap"
    if RemoveInventoryItem(source, trapItem, 1) == false then
        return { ok = false, reason = "noitem" }
    end

    local seaZ = waterZ - depth
    local now = os.time()
    local insertId = MySQL.insert.await(
        string.format("INSERT INTO `%s` (identifier, x, y, sea_z, water_z, band, placed_at) VALUES (?, ?, ?, ?, ?, ?, ?)", TABLE_NAME),
        { identifier, x, y, seaZ, waterZ, band, now }
    )

    if not insertId then
        AddInventoryItem(source, trapItem, 1)
        return { ok = false, reason = "bad" }
    end

    local newTrap = {
        id = insertId,
        identifier = identifier,
        x = x,
        y = y,
        seaZ = seaZ,
        waterZ = waterZ,
        band = band,
        placedAt = now
    }
    ActiveCrabTraps[insertId] = newTrap
    BroadcastTrapEvent("qs-fisher:crabTrapAdded", FormatCrabTrapData(newTrap))

    return {
        ok = true,
        id = insertId,
        left = limit - (#playerTraps + 1)
    }
end)

function RollTrapLoot(trap, fullness, boost)
    local lootCfg = (GetCrabTrapsConfig().Loot and GetCrabTrapsConfig().Loot[trap.band]) or
                    (GetCrabTrapsConfig().Loot and GetCrabTrapsConfig().Loot.mid) or
                    (GetCrabTrapsConfig().Loot and GetCrabTrapsConfig().Loot.deep) or {}

    if #lootCfg == 0 then
        return {}
    end

    local maxWeight = 0
    for _, entry in ipairs(lootCfg) do
        local w = entry.weight or 0
        if w > maxWeight then
            maxWeight = w
        end
    end

    local rarityBoost = boost and tonumber(boost.Rarity)
    local totalWeight = 0
    local weightedList = {}

    for _, entry in ipairs(lootCfg) do
        local w = entry.weight or 0
        if rarityBoost and rarityBoost > 1.0 and maxWeight > 0 then
            local factor = rarityBoost ^ (1.0 - (w / maxWeight))
            w = w * factor
        end
        if w > 0 then
            totalWeight = totalWeight + w
            weightedList[#weightedList + 1] = { entry = entry, weight = w }
        end
    end

    if totalWeight <= 0 then
        return {}
    end

    local rollCount = math.max(math.floor((#lootCfg * fullness) + 0.5), 1)
    local result = {}

    for _ = 1, rollCount do
        local rnd = math.random() * totalWeight
        local accumulated = 0
        for _, item in ipairs(weightedList) do
            accumulated = accumulated + item.weight
            if rnd < accumulated then
                local entry = item.entry
                local minAmt = entry.min or 1
                local maxAmt = entry.max or minAmt
                local count = math.max(math.floor((math.random(minAmt, maxAmt) * fullness) + 0.5), 1)
                local itemName = entry[1]
                result[itemName] = (result[itemName] or 0) + count
                break
            end
        end
    end

    return result
end

function GiveTrapLoot(source, items)
    local totalGiven = 0
    local missingList = {}
    local remainingItems = 0

    for itemName, count in pairs(items) do
        local sizeCfg = Config.FishSizes and Config.FishSizes[itemName]
        local minW = (sizeCfg and sizeCfg.weight and sizeCfg.weight[1]) or 0.3
        local maxW = (sizeCfg and sizeCfg.weight and sizeCfg.weight[2]) or 1.2

        for i = 1, count do
            local metadata = nil
            if Config.InventoryMetadata then
                local weightVal = minW + math.random() * (maxW - minW)
                metadata = {
                    weight = tonumber(string.format("%.2f", weightVal)),
                    description = string.format("%.2f kg", weightVal)
                }
            end

            local success, err = AddInventoryItem(source, itemName, 1, metadata)
            if success == false then
                if err ~= "unknown_item" then
                    return totalGiven, false, missingList, remainingItems
                end
                missingList[#missingList + 1] = itemName
                remainingItems = remainingItems + (count - i + 1)
                break
            end
            totalGiven = totalGiven + 1
        end
    end

    return totalGiven, true, missingList, remainingItems
end

function DeleteCrabTrap(id)
    ActiveCrabTraps[id] = nil
    MySQL.query(string.format("DELETE FROM `%s` WHERE id = ?", TABLE_NAME), { id })
    BroadcastTrapEvent("qs-fisher:crabTrapRemoved", id)
end

lib.callback.register("qs-fisher:pullCrabTrap", function(source, trapId, isDismantle)
    local config = GetCrabTrapsConfig()
    if not config.Enabled then
        return { ok = false, reason = "disabled" }
    end

    local id = tonumber(trapId)
    local trap = id and ActiveCrabTraps[id]
    if not trap then
        return { ok = false, reason = "gone" }
    end

    local identifier = GetPlayeridentifier(source)
    if not identifier or trap.identifier ~= identifier then
        return { ok = false, reason = "notyours" }
    end

    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then
        return { ok = false, reason = "bad" }
    end

    local pCoords = GetEntityCoords(ped)
    if GetDistance2D(pCoords.x, pCoords.y, trap.x, trap.y) > (MAX_PULL_DIST + 2.0) then
        return { ok = false, reason = "far" }
    end

    local fullness = CalculateSoakFullness(trap)
    local breakChance
    if isDismantle then
        breakChance = tonumber(config.DismantleBreakChance) or 0
    else
        breakChance = tonumber(config.BreakChance) or 0
    end

    local broke = (breakChance > 0)
    if not broke then
        AddInventoryItem(source, config.Item or "crab_trap", 1)
    end

    local caughtCount = 0
    local hasRoom = true
    local missingItems = nil

    if not isDismantle then
        local hotspotBoost = nil
        if config.HotspotBoost and HotspotBoostFor then
            local activeHotspot = GetActiveHotspot and GetActiveHotspot()
            if activeHotspot and activeHotspot.coords then
                local dist = GetDistance2D(trap.x, trap.y, activeHotspot.coords.x, activeHotspot.coords.y)
                if dist <= (activeHotspot.radius or 0) then
                    hotspotBoost = (Config.Hotspots and Config.Hotspots.Boost) or {}
                end
            end
        end

        local rolledItems = RollTrapLoot(trap, fullness, hotspotBoost)
        local given, roomOk, missing = GiveTrapLoot(source, rolledItems)
        caughtCount = given
        hasRoom = roomOk
        missingItems = missing

        local xpPerFull = tonumber(config.Experience) or 0
        local xpEarned = math.floor(xpPerFull * fullness)
        if xpEarned > 0 then
            AddExperience(identifier, xpEarned, source)
        end
    end

    DeleteCrabTrap(id)

    local warnMessage = nil
    if missingItems and #missingItems > 0 then
        warnMessage = WarnMissingItem("a crab trap loot table in Config.CrabTraps.Loot", missingItems)
    end

    return {
        ok = true,
        dismantle = (isDismantle == true),
        broke = broke,
        caught = caughtCount,
        full = math.floor(fullness * 100),
        room = hasRoom,
        missing = warnMessage
    }
end)

lib.callback.register("qs-fisher:getCrabTraps", function(source)
    local identifier = GetPlayeridentifier(source)
    local list = {}
    for _, trap in pairs(ActiveCrabTraps) do
        local data = FormatCrabTrapData(trap)
        data.mine = (trap.identifier == identifier)
        list[#list + 1] = data
    end
    return list
end)

lib.callback.register("qs-fisher:getCrabTrap", function(source, trapId)
    local id = tonumber(trapId)
    local trap = id and ActiveCrabTraps[id]
    if not trap then
        return nil
    end

    local data = FormatCrabTrapData(trap)
    data.mine = (trap.identifier == GetPlayeridentifier(source))
    return data
end)

CreateThread(function()
    if not GetCrabTrapsConfig().Enabled then
        return
    end

    local warnedTraps = {}
    while true do
        Wait(60000)
        local warnThresholdSec = math.max(tonumber(GetCrabTrapsConfig().Decay and GetCrabTrapsConfig().Decay.WarnBefore) or 15, 0) * 60

        for id, trap in pairs(ActiveCrabTraps) do
            local secToBreak = GetSecondsToBreak(trap)
            if secToBreak <= 0 then
                warnedTraps[id] = nil
                DeleteCrabTrap(id)
                local ownerSrc = GetPlayerFromIdentifier(trap.identifier)
                if ownerSrc then
                    TriggerClientEvent("qs-fisher:sendNotification", ownerSrc, "notify", "error", Lang("CRABTRAP_BROKE"))
                end
            elseif warnThresholdSec > 0 and secToBreak <= warnThresholdSec then
                if not warnedTraps[id] then
                    warnedTraps[id] = true
                    local ownerSrc = GetPlayerFromIdentifier(trap.identifier)
                    if ownerSrc then
                        local minutesLeft = math.max(math.floor(secToBreak / 60), 1)
                        TriggerClientEvent("qs-fisher:sendNotification", ownerSrc, "notify", "warning", string.format(Lang("CRABTRAP_ROTTING"), minutesLeft))
                    end
                end
            end
        end
    end
end)
--WKLeaksfxOn8ATop1q : https://discord.gg/zqcBffbMZn
--WKLeak_htOn-MTopaB : https://discord.gg/zqcBffbMZn
--WKLeak_QIOn6bTopGe : https://discord.gg/zqcBffbMZn
--WKLeakzmOn1vTopFh : https://discord.gg/zqcBffbMZn
--WKLeak_TSOnd#Topnz : https://discord.gg/zqcBffbMZn
