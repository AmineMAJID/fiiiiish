--[[   -- https://discord.gg/zqcBffbMZn ]]
local ActiveCampfires = {}
local NextCampfireId = 0
local ActiveCooks = {}
local RateLimits = {}
local CookablesCache = {}
local FuelCache = {}
local CachedCookableFish = nil

local MAX_COOK_INTERACT_DIST = 2.5
local MAX_LIGHT_DIST_2D = 6.0
local MAX_LIGHT_DIST_Z = 4.0
local MIN_CAMPFIRE_SPACING = 8.0
local CHAR_INTERVAL = 4.0
local CHAR_BURNT_LIMIT = 2.0
local MAX_TURN_DIST = 2.5

function GetCampfireConfig()
    return Config.Campfire or {}
end

function GetCookConfig()
    return (Config.Campfire and Config.Campfire.Cook) or {}
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

function CheckRateLimit(src, action, cooldownMs)
    local now = GetGameTimer()
    if not RateLimits[src] then
        RateLimits[src] = {}
    end
    local lastTime = RateLimits[src][action]
    if lastTime and (now - lastTime) < cooldownMs then
        return true
    end
    RateLimits[src][action] = now
    return false
end

function GetPlayerCoordsSafe(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then
        return nil
    end
    return GetEntityCoords(ped)
end

function GetForbiddenZone(x, y)
    local zones = (GetCampfireConfig().Ground and GetCampfireConfig().Ground.Zones) or {}
    for _, zone in ipairs(zones) do
        local coords = zone.coords
        local radius = tonumber(zone.radius) or 0.0
        if coords and radius > 0 then
            if GetDistance2D(x, y, coords.x, coords.y) <= radius then
                return zone.label or "that spot"
            end
        end
    end
    return nil
end

function GetCookableFishMap()
    if CachedCookableFish then
        return CachedCookableFish
    end
    CachedCookableFish = {}
    local exclude = GetCookConfig().Exclude or {}
    local orderedFish = (GetOrderedFish and GetOrderedFish()) or {}
    for _, fish in ipairs(orderedFish) do
        if fish.name and not exclude[fish.name] then
            CachedCookableFish[fish.name] = fish.label or fish.name
        end
    end
    return CachedCookableFish
end

function GetCookableFish()
    return GetCookableFishMap()
end

function FormatCampfireData(fire)
    return {
        id = fire.id,
        x = fire.x,
        y = fire.y,
        z = fire.z,
        heading = fire.heading,
        left = math.max((fire.outAt or 0) - os.time(), 0)
    }
end

function GetPlayerCampfireCount(identifier)
    local count = 0
    for _, fire in pairs(ActiveCampfires) do
        if fire.identifier == identifier then
            count = count + 1
        end
    end
    return count
end

lib.callback.register("qs-fisher:lightCampfire", function(source, coords)
    local campfireCfg = GetCampfireConfig()
    if not campfireCfg.Enabled then
        return { ok = false, reason = "disabled" }
    end
    if type(coords) ~= "table" then
        return { ok = false, reason = "bad" }
    end
    if CheckRateLimit(source, "light", 2000) then
        return { ok = false, reason = "bad" }
    end

    local identifier = GetPlayeridentifier(source)
    if not identifier then
        return { ok = false, reason = "bad" }
    end

    local x = ToNumberSafe(coords.x)
    local y = ToNumberSafe(coords.y)
    local z = ToNumberSafe(coords.z)
    if not (x and y and z) then
        return { ok = false, reason = "bad" }
    end

    local pCoords = GetPlayerCoordsSafe(source)
    if not pCoords then
        return { ok = false, reason = "bad" }
    end

    if GetDistance2D(x, y, pCoords.x, pCoords.y) > MAX_LIGHT_DIST_2D then
        return { ok = false, reason = "far" }
    end
    if math.abs(z - pCoords.z) > MAX_LIGHT_DIST_Z then
        return { ok = false, reason = "far" }
    end

    local limit = math.max(math.floor(tonumber(campfireCfg.Limit) or 2), 1)
    if GetPlayerCampfireCount(identifier) >= limit then
        return { ok = false, reason = "limit", limit = limit }
    end

    for _, fire in pairs(ActiveCampfires) do
        if GetDistance2D(x, y, fire.x, fire.y) < MIN_CAMPFIRE_SPACING then
            return { ok = false, reason = "crowded" }
        end
    end

    local zoneLabel = GetForbiddenZone(x, y)
    if zoneLabel then
        return { ok = false, reason = "zone", label = zoneLabel }
    end

    local fuelCfg = campfireCfg.Fuel or {}
    local fuelAmount = math.max(math.floor(tonumber(fuelCfg.Amount) or 1), 1)
    local fuelItems = fuelCfg.Items or { "oak_wood" }
    local usedFuel = nil

    for _, itemName in ipairs(fuelItems) do
        if RemoveInventoryItem(source, itemName, fuelAmount) == true then
            usedFuel = itemName
            break
        end
    end

    if not usedFuel then
        return { ok = false, reason = "nofuel", amount = fuelAmount }
    end

    local burnMinutes = math.max(tonumber(campfireCfg.BurnMinutes) or 20, 1)
    NextCampfireId = NextCampfireId + 1

    local heading = (ToNumberSafe(coords.heading) or 0.0) % 360.0
    local campfireData = {
        id = NextCampfireId,
        identifier = identifier,
        x = x,
        y = y,
        z = z,
        heading = heading,
        outAt = os.time() + math.floor(burnMinutes * 60)
    }

    ActiveCampfires[campfireData.id] = campfireData
    TriggerClientEvent("qs-fisher:campfireLit", -1, FormatCampfireData(campfireData))

    return {
        ok = true,
        id = campfireData.id,
        minutes = math.floor(burnMinutes)
    }
end)

lib.callback.register("qs-fisher:getCampfires", function()
    local now = os.time()
    local list = {}
    for _, fire in pairs(ActiveCampfires) do
        if (fire.outAt or 0) > now then
            list[#list + 1] = FormatCampfireData(fire)
        end
    end
    return list
end)

lib.callback.register("qs-fisher:getCampfireFuel", function(source, force)
    if not GetCampfireConfig().Enabled then
        return nil
    end

    local cached = FuelCache[source]
    if cached and (GetGameTimer() - cached.at) < 800 then
        if force == true and CheckRateLimit(source, "fuel", 500) then
            return cached.fuel
        elseif force ~= true then
            return cached.fuel
        end
    end

    local fuelCfg = GetCampfireConfig().Fuel or {}
    local fuelAmount = math.max(math.floor(tonumber(fuelCfg.Amount) or 1), 1)
    local result = { amount = fuelAmount }
    local fuelItems = fuelCfg.Items or {}

    for _, itemName in ipairs(fuelItems) do
        local count = GetItemCountFromInventory(source, itemName) or 0
        if count >= fuelAmount then
            result.item = itemName
            result.label = (GetItemLabel and GetItemLabel(itemName)) or nil
            result.have = count
            break
        end
    end

    FuelCache[source] = {
        at = GetGameTimer(),
        fuel = result
    }
    return result
end)

lib.callback.register("qs-fisher:getCookables", function(source)
    if not GetCampfireConfig().Enabled then
        return {}
    end

    local cached = CookablesCache[source]
    if cached and (GetGameTimer() - cached.at) < 800 then
        return cached.list
    end

    local list = {}
    local rawItem = (GetCampfireConfig().Items and GetCampfireConfig().Items.Raw) or "brochette_fish_raw"
    local rawCount = GetItemCountFromInventory(source, rawItem) or 0
    if rawCount > 0 then
        list[#list + 1] = {
            item = rawItem,
            label = Lang("COOK_RAW_SKEWER"),
            count = rawCount,
            skewer = true
        }
    end

    local orderedFish = (GetOrderedFish and GetOrderedFish()) or {}
    local cookableMap = GetCookableFishMap()
    for _, fish in ipairs(orderedFish) do
        if cookableMap[fish.name] then
            local count = GetItemCountFromInventory(source, fish.name) or 0
            if count > 0 then
                list[#list + 1] = {
                    item = fish.name,
                    label = fish.label or fish.name,
                    count = count
                }
            end
        end
    end

    CookablesCache[source] = {
        at = GetGameTimer(),
        list = list
    }
    return list
end)

lib.callback.register("qs-fisher:startCooking", function(source, fireId, itemName)
    if not GetCampfireConfig().Enabled then
        return { ok = false, reason = "disabled" }
    end
    if CheckRateLimit(source, "cook", 900) then
        return { ok = false, reason = "bad" }
    end
    if ActiveCooks[source] then
        return { ok = false, reason = "already" }
    end

    local fire = tonumber(fireId) and ActiveCampfires[tonumber(fireId)]
    if not fire then
        return { ok = false, reason = "gone" }
    end

    local pCoords = GetPlayerCoordsSafe(source)
    if not pCoords then
        return { ok = false, reason = "bad" }
    end

    if GetDistance2D(pCoords.x, pCoords.y, fire.x, fire.y) > (MAX_COOK_INTERACT_DIST + 1.5) then
        return { ok = false, reason = "far" }
    end

    if type(itemName) ~= "string" or itemName == "" then
        return { ok = false, reason = "bad" }
    end

    local rawItem = (GetCampfireConfig().Items and GetCampfireConfig().Items.Raw) or "brochette_fish_raw"
    if itemName ~= rawItem then
        if not GetCookableFishMap()[itemName] then
            return { ok = false, reason = "bad" }
        end
    end

    if RemoveInventoryItem(source, itemName, 1) ~= true then
        return { ok = false, reason = "noitem" }
    end

    local now = GetGameTimer()
    ActiveCooks[source] = {
        fireId = fire.id,
        overFire = 0.0,
        charred = 0.0,
        lastTurnAt = now,
        tickedAt = now
    }

    local cookCfg = GetCookConfig()
    return {
        ok = true,
        toCooked = tonumber(cookCfg.ToCooked) or 25.0,
        toBurnt = tonumber(cookCfg.ToBurnt) or 32.0
    }
end)

RegisterNetEvent("qs-fisher:turnSkewer", function()
    local src = source
    local cookData = ActiveCooks[src]
    if not cookData then
        return
    end

    local now = GetGameTimer()
    if (now - cookData.lastTurnAt) < 500 then
        return
    end

    local fire = ActiveCampfires[cookData.fireId]
    if not fire then
        return
    end

    local pCoords = GetPlayerCoordsSafe(src)
    if not pCoords then
        return
    end

    if GetDistance2D(pCoords.x, pCoords.y, fire.x, fire.y) > (MAX_TURN_DIST + 1.5) then
        return
    end

    cookData.lastTurnAt = now
end)

function GetSkewerState(cookData)
    if cookData.charred >= CHAR_BURNT_LIMIT then
        return "burnt"
    end
    local toCooked = tonumber(GetCookConfig().ToCooked) or 25.0
    if cookData.overFire < toCooked then
        return "raw"
    end
    local toBurnt = tonumber(GetCookConfig().ToBurnt) or 32.0
    if cookData.overFire <= toBurnt then
        return "cooked"
    end
    return "burnt"
end

function SettleCooking(source, why)
    local cookData = ActiveCooks[source]
    if not cookData then
        return { ok = false, reason = "nothing" }
    end
    if cookData.settling then
        return { ok = false, reason = "busy" }
    end
    cookData.settling = true

    local itemsCfg = (GetCampfireConfig().Items) or {}
    local state = GetSkewerState(cookData)
    local rewardItem
    if state == "cooked" then
        rewardItem = itemsCfg.Cooked or "brochette_fish_cooked"
    elseif state == "burnt" then
        rewardItem = itemsCfg.Burnt or "brochette_fish_burn"
    else
        rewardItem = itemsCfg.Raw or "brochette_fish_raw"
    end

    local success, err = AddInventoryItem(source, rewardItem, 1)
    if success == false then
        cookData.settling = nil
        if err == "unknown_item" then
            WarnMissingItem("Config.Campfire.Items", rewardItem)
            return { ok = false, reason = "noitem", missing = rewardItem }
        end
        return { ok = false, reason = "full" }
    end

    ActiveCooks[source] = nil

    if state == "cooked" then
        local xp = math.floor(tonumber(GetCookConfig().Experience) or 0)
        if xp > 0 then
            local identifier = GetPlayeridentifier(source)
            if identifier then
                AddExperience(identifier, xp, source)
            end
        end
    end

    return { ok = true, state = state, why = why }
end

lib.callback.register("qs-fisher:takeSkewer", function(source)
    if not ActiveCooks[source] then
        return { ok = false, reason = "nothing" }
    end
    return SettleCooking(source, "taken")
end)

CreateThread(function()
    if not GetCampfireConfig().Enabled then
        return
    end

    while true do
        Wait(1000)
        local nowMs = GetGameTimer()
        local nowSec = os.time()

        for id, fire in pairs(ActiveCampfires) do
            if nowSec >= (fire.outAt or 0) then
                ActiveCampfires[id] = nil
                TriggerClientEvent("qs-fisher:campfireOut", -1, id)
                local ownerSrc = GetPlayerFromIdentifier(fire.identifier)
                if ownerSrc then
                    TriggerClientEvent("qs-fisher:sendNotification", ownerSrc, "notify", "info", Lang("CAMPFIRE_BURNT_OUT"))
                end
            end
        end

        for src, cookData in pairs(ActiveCooks) do
            local fire = ActiveCampfires[cookData.fireId]
            local deltaSec = math.min((nowMs - cookData.tickedAt) / 1000.0, 5.0)
            cookData.tickedAt = nowMs

            if not fire then
                local res = SettleCooking(src, "fireout")
                local prev = cookData.stranded or res.reason
                if prev ~= res.reason then
                    cookData.stranded = res.reason
                    TriggerClientEvent("qs-fisher:cookEnded", src, res)
                end
            else
                local pCoords = GetPlayerCoordsSafe(src)
                local isNear = (pCoords ~= nil)
                local isBurnt = (GetSkewerState(cookData) == "burnt")

                if isNear and not isBurnt then
                    cookData.overFire = cookData.overFire + deltaSec
                    local sinceTurn = (nowMs - cookData.lastTurnAt) / 1000.0
                    if sinceTurn > CHAR_INTERVAL then
                        cookData.charred = cookData.charred + deltaSec
                    end
                elseif isBurnt then
                    cookData.lastTurnAt = nowMs
                else
                    cookData.lastTurnAt = nowMs
                end

                TriggerClientEvent("qs-fisher:cookState", src, {
                    state = GetSkewerState(cookData),
                    overFire = cookData.overFire,
                    charred = cookData.charred,
                    sinceTurn = (nowMs - cookData.lastTurnAt) / 1000.0,
                    near = isNear
                })
            end
        end
    end
end)

AddEventHandler("playerDropped", function()
    local src = source
    ActiveCooks[src] = nil
    RateLimits[src] = nil
    CookablesCache[src] = nil
    FuelCache[src] = nil
end)
--WKLeaksy0On@pTopzi : https://discord.gg/zqcBffbMZn
--WKLeak_mcOnL9TopEV : https://discord.gg/zqcBffbMZn
--WKLeak-nNOnDaTopXd : https://discord.gg/zqcBffbMZn
--WKLeak-sCOn1XTopSS : https://discord.gg/zqcBffbMZn
--WKLeak_1aOnqATopJp : https://discord.gg/zqcBffbMZn
