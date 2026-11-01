--[[   -- https://discord.gg/zqcBffbMZn ]]
local activeNets = {}
local POLL_INTERVAL = 2000
local SPEED_CAP = 12.0
local CATCH_RATE = 0.005
local BOAT_BASE_BOOST = 0.35
local BOAT_SPEED_MULTIPLIER = 1.25

function GetNetsConfig()
    return Config.FishingNets or {}
end

function MaxStepDistance()
    return SPEED_CAP * (POLL_INTERVAL / 1000)
end

function FindNetTier(itemName)
    local tiers = GetNetsConfig().Tiers or {}
    for _, tier in ipairs(tiers) do
        if tier.item == itemName then
            return tier
        end
    end
    return nil
end

function ComputeNetCatch(net)
    local metres = net.metres or 0
    local rawCatch = metres * CATCH_RATE * BOAT_SPEED_MULTIPLIER
    return math.min(rawCatch, net.capacity)
end

CreateThread(function()
    while true do
        Wait(POLL_INTERVAL)
        local maxStep = MaxStepDistance()
        for src, net in pairs(activeNets) do
            local ped = GetPlayerPed(src)
            if ped and ped ~= 0 then
                local coords = GetEntityCoords(ped)
                if coords then
                    if net.lastPos then
                        local hasBoat = true
                        if BoatUnderPlayer then
                            hasBoat = BoatUnderPlayer(src)
                        end
                        if hasBoat then
                            local dist = #(coords - net.lastPos)
                            if dist == dist then
                                net.metres = net.metres + math.min(dist, maxStep)
                            end
                        end
                    end
                    net.lastPos = coords
                end
            end
        end
    end
end)

function GetDepthBandIndex(bandId)
    local bandIds = DepthBandIds and DepthBandIds() or {}
    for index, id in ipairs(bandIds) do
        if id == bandId then
            return index
        end
    end
    return nil
end

function GetPlayerDepthBand(src)
    if not AllowedDepth or not DepthBandAt then
        return nil
    end
    return DepthBandAt(AllowedDepth(src))
end

lib.callback.register("qs-fisher:deployNet", function(src, tierItem)
    local cfg = GetNetsConfig()
    if not cfg.Enabled then
        return { ok = false, reason = "disabled" }
    end
    if activeNets[src] then
        return { ok = false, reason = "already" }
    end

    local tier = FindNetTier(tostring(tierItem or ""))
    if not tier then
        return { ok = false, reason = "bad" }
    end

    local identifier = GetPlayeridentifier(src)
    if not identifier then
        return { ok = false, reason = "bad" }
    end

    local playerLevel = (PlayersLevels and PlayersLevels[identifier] and PlayersLevels[identifier].level) or 1
    local requiredLevel = tier.requiredLevel or 1
    if playerLevel < requiredLevel then
        return { ok = false, reason = "level", level = requiredLevel }
    end

    if BoatUnderPlayer and not BoatUnderPlayer(src) then
        return { ok = false, reason = "noboat" }
    end

    if HasBoatRental and not HasBoatRental(src) then
        return { ok = false, reason = "norental" }
    end

    if RemoveInventoryItem(src, tier.item, 1) == false then
        return { ok = false, reason = "noitem" }
    end

    local ped = GetPlayerPed(src)
    local coords = (ped and ped ~= 0) and GetEntityCoords(ped) or nil

    activeNets[src] = {
        tier = tier,
        capacity = tier.capacity or 40,
        metres = 0.0,
        lastPos = coords,
        maxBand = GetPlayerDepthBand(src)
    }

    return {
        ok = true,
        item = tier.item,
        label = tier.label,
        capacity = tier.capacity,
        integrity = tier.integrity
    }
end)

function RollNetLoot(bandName, count, boost)
    local lootTable = GetNetsConfig().Loot or {}
    local lootList = lootTable[bandName] or lootTable.mid
    if not lootList or #lootList == 0 then
        return {}
    end

    local maxWeight = 0
    for _, entry in ipairs(lootList) do
        local weight = entry.weight or 0
        if weight > maxWeight then
            maxWeight = weight
        end
    end

    local rarityBoost = boost and tonumber(boost.Rarity) or nil
    local totalWeight = 0
    local pool = {}

    for _, entry in ipairs(lootList) do
        local weight = entry.weight or 0
        if rarityBoost and rarityBoost > 1.0 and maxWeight > 0 then
            local ratio = 1 - (weight / maxWeight)
            weight = weight * (rarityBoost ^ ratio)
        end
        if weight > 0 then
            totalWeight = totalWeight + weight
            pool[#pool + 1] = {
                name = entry[1],
                weight = weight
            }
        end
    end

    if totalWeight <= 0 then
        return {}
    end

    local results = {}
    for i = 1, count do
        local roll = math.random() * totalWeight
        local currentWeight = 0
        for _, item in ipairs(pool) do
            currentWeight = currentWeight + item.weight
            if roll < currentWeight then
                results[item.name] = (results[item.name] or 0) + 1
                break
            end
        end
    end
    return results
end

function GiveNetItems(src, itemList)
    local givenCount = 0
    local missingItems = {}
    local failedCount = 0

    for itemName, amount in pairs(itemList) do
        local sizeConfig = (Config.FishSizes and Config.FishSizes[itemName]) or {}
        local minWeight = (sizeConfig.weight and sizeConfig.weight[1]) or 0.3
        local maxWeight = (sizeConfig.weight and sizeConfig.weight[2]) or 1.2

        for i = 1, amount do
            local metadata = nil
            if Config.InventoryMetadata then
                local factor = math.random() ^ (1 / (1 - BOAT_BASE_BOOST * 0.9))
                local finalWeight = minWeight + (maxWeight - minWeight) * factor
                local roundedWeight = tonumber(("%.2f"):format(finalWeight))
                metadata = {
                    weight = roundedWeight,
                    description = ("%.2f kg"):format(finalWeight)
                }
            end

            local success, err = AddInventoryItem(src, itemName, 1, metadata)
            if success == false then
                if err ~= "unknown_item" then
                    return givenCount, false, missingItems, failedCount
                end
                missingItems[#missingItems + 1] = itemName
                failedCount = failedCount + (amount - i + 1)
                break
            end
            givenCount = givenCount + 1
        end
    end

    return givenCount, true, missingItems, failedCount
end

lib.callback.register("qs-fisher:haulNet", function(src, clientDistance, bandName, isTorn)
    local net = activeNets[src]
    if not net then
        return { ok = false, reason = "none" }
    end
    activeNets[src] = nil

    local identifier = GetPlayeridentifier(src)
    local safeDist = tonumber(clientDistance) or 0
    if safeDist ~= safeDist then
        safeDist = 0
    end

    local serverCatch = ComputeNetCatch(net)
    local totalCatch = math.min(math.max(safeDist, 0), serverCatch)
    local targetBand = tostring(bandName or "")
    local cfg = GetNetsConfig()

    if not cfg.Loot or not cfg.Loot[targetBand] then
        targetBand = "mid"
    end

    local chosenBandIndex = GetDepthBandIndex(targetBand)
    local maxBandIndex = GetDepthBandIndex(net.maxBand)
    if chosenBandIndex and maxBandIndex and chosenBandIndex > maxBandIndex then
        targetBand = net.maxBand
    end

    local toreNet = (isTorn == true)
    local catchCount = toreNet and 0 or math.floor(totalCatch)

    if not toreNet or cfg.BreakLosesNet == false then
        AddInventoryItem(src, net.tier.item, 1)
    end

    if catchCount <= 0 then
        return {
            ok = true,
            torn = toreNet,
            caught = 0,
            kept = not toreNet
        }
    end

    local hotspotBoost = nil
    if cfg.HotspotBoost and HotspotBoostFor then
        hotspotBoost = HotspotBoostFor(src)
    end

    local lootResults = RollNetLoot(targetBand, catchCount, hotspotBoost)
    local givenCount, hasRoom, missingItems, failedCount = GiveNetItems(src, lootResults)

    local expRate = tonumber(cfg.Experience) or 0
    local expAwarded = math.floor((givenCount + failedCount) * expRate)
    if expAwarded > 0 and identifier and AddExperience then
        AddExperience(identifier, expAwarded, src)
    end

    local missingReport = nil
    if missingItems and #missingItems > 0 and WarnMissingItem then
        missingReport = WarnMissingItem("a net loot table in Config.FishingNets.Loot", missingItems)
    end

    return {
        ok = true,
        torn = false,
        caught = givenCount,
        room = hasRoom,
        missing = missingReport,
        kept = true
    }
end)

AddEventHandler("playerDropped", function()
    local src = source
    activeNets[src] = nil
end)

function HasNetOut(src)
    return activeNets[src] ~= nil
end
--WKLeaksAROnisTop6R : https://discord.gg/zqcBffbMZn
--WKLeaks3sOnDuTop!8 : https://discord.gg/zqcBffbMZn
--WKLeaks5SOn$2TopW3 : https://discord.gg/zqcBffbMZn
--WKLeak_CcOnHpTopWx : https://discord.gg/zqcBffbMZn
--WKLeak_nyOnG7Topjj : https://discord.gg/zqcBffbMZn
