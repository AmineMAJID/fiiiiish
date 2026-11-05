--[[   -- https://discord.gg/zqcBffbMZn ]]
local validGearSlots = {
    bait = true,
    hook = true,
    reel = true,
    line = true
}

local playerGear = {}
local activeCasts = {}
local pendingDecisions = {}
local catchDecisionNoticeShown = false
local lastCastTime = {}
local cachedOrderedFish = nil
local cachedFishLabels = nil
local cachedBaitInfo = nil
local cachedDepthBandIds = nil

local DEFAULT_MAX_ANGLE = 70.0
local BASE_PULL_SPEED = 0.025
local BASE_SLIP_SPEED = 0.005
local DEFAULT_DISTANCE = 10.0
local MIN_BITE_WAIT_MS = 1500
local CAST_POWER_PROB_FACTOR = 0.6
local MIN_CAST_POWER = 0.05
local CAST_POWER_EMPTY_SCALE = 0.45
local depthDistanceFalloff = { 1.0, 0.22, 0.035, 0.008 }
local rodSlotsOrder = { "bait", "hook", "reel", "line" }
local rateLimitInterval = 250
local activeLines = {}
local lastLineOutTime = {}
local activeDangles = {}
local lastDangleOutTime = {}
local playerSelectedRods = {}

local WEAK_CAST_PENALTY = 0.18
local FIGHT_SPECIMEN_QUALITY_SCALE = 0.15
local MAX_FIGHT_EASE_PERCENT = 40
local FIGHT_ANGLE_REDUCTION = 0.35
local FIGHT_PULL_REDUCTION = 0.45
local FIGHT_SLIP_MULTIPLIER = 2.2
local FIGHT_TURN_MULTIPLIER = 0.5
local BOAT_DETECTION_RADIUS = 30.0
local boatVehicleTypes = { boat = true, submarine = true }

function GetOrderedFish()
    if cachedOrderedFish then
        return cachedOrderedFish
    end

    cachedOrderedFish = {}
    for _, category in pairs(Config.Fish or {}) do
        for _, itemData in ipairs(category.items or {}) do
            local fishName = itemData[1]
            local fishLabel = itemData[2]
            local probability = tonumber(itemData[3]) or 0
            local maxDrop = math.max(math.floor(tonumber(itemData[4]) or 1), 1)
            local sellPrice = tonumber(itemData[5]) or 0
            local experience = tonumber(itemData[6]) or 0
            local depth = tostring(itemData[7] or ""):lower()
            local preferredBait = itemData[8] and tostring(itemData[8]):lower() or nil

            cachedOrderedFish[#cachedOrderedFish + 1] = {
                name = fishName,
                label = fishLabel,
                probability = probability,
                maxDrop = maxDrop,
                sellPrice = sellPrice,
                experience = experience,
                depth = depth,
                bait = preferredBait
            }
        end
    end

    table.sort(cachedOrderedFish, function(a, b)
        return a.probability > b.probability
    end)

    return cachedOrderedFish
end

function FishLabel(fishName)
    if not fishName then return nil end

    if not cachedFishLabels then
        cachedFishLabels = {}
        for _, fish in ipairs(GetOrderedFish()) do
            cachedFishLabels[fish.name] = fish.label
        end
    end

    return cachedFishLabels[fishName] or fishName
end

function GetBaitInfo()
    if cachedBaitInfo then
        return cachedBaitInfo
    end

    cachedBaitInfo = {}
    for _, fish in ipairs(GetOrderedFish()) do
        if fish.bait then
            if not cachedBaitInfo[fish.bait] then
                cachedBaitInfo[fish.bait] = {
                    depths = {},
                    fish = {}
                }
            end

            local baitEntry = cachedBaitInfo[fish.bait]
            local depthExists = false
            for _, depth in ipairs(baitEntry.depths) do
                if depth == fish.depth then
                    depthExists = true
                    break
                end
            end

            if not depthExists then
                baitEntry.depths[#baitEntry.depths + 1] = fish.depth
            end

            baitEntry.fish[#baitEntry.fish + 1] = fish.label
        end
    end

    return cachedBaitInfo
end

function DepthBandIds()
    if cachedDepthBandIds then
        return cachedDepthBandIds
    end

    cachedDepthBandIds = {}
    for _, band in ipairs(Config.Depth and Config.Depth.Bands or {}) do
        cachedDepthBandIds[#cachedDepthBandIds + 1] = band.id
    end

    return cachedDepthBandIds
end

function DepthBandAt(depth)
    local bands = Config.Depth and Config.Depth.Bands or {}
    for _, band in ipairs(bands) do
        local maxDepth = band.max or 0
        if depth <= maxDepth then
            return band.id
        end
    end

    return bands[1] and bands[1].id or nil
end

function DepthBandIndex(bandId)
    for index, id in ipairs(DepthBandIds()) do
        if id == bandId then
            return index
        end
    end
    return nil
end

function DepthMatch(fishDepth, castDepth)
    local fishIndex = DepthBandIndex(fishDepth)
    local castIndex = DepthBandIndex(castDepth)

    if not fishIndex or not castIndex then
        return depthDistanceFalloff[1]
    end

    local distance = math.abs(fishIndex - castIndex)
    return depthDistanceFalloff[distance + 1] or 0.0
end

function BaitMatch(attachedBait, fish)
    local baitConfig = Config.Bait or {}
    if not attachedBait then
        return baitConfig.None or 1.0
    end

    if fish.bait and tostring(attachedBait):lower() == fish.bait then
        return baitConfig.Favourite or 1.0
    end

    return baitConfig.Other or 1.0
end

lib.callback.register("qs-fisher:getFishingGuide", function()
    local baitMap = {}
    for _, baitEntry in ipairs(Config.FishingAttachments and Config.FishingAttachments.bait or {}) do
        baitMap[baitEntry.item:lower()] = baitEntry
    end

    local shoreDepth = tonumber(Config.Depth and Config.Depth.ShoreDepth) or 6.0
    local shoreBandId = nil
    for _, band in ipairs(Config.Depth and Config.Depth.Bands or {}) do
        if shoreDepth <= (band.max or 0) then
            shoreBandId = band.id
            break
        end
    end

    local guideFish = {}
    for _, fish in ipairs(GetOrderedFish()) do
        local baitConfig = fish.bait and baitMap[fish.bait] or nil
        local baitDetails = nil
        if baitConfig then
            baitDetails = {
                item = baitConfig.item,
                label = baitConfig.label,
                image = baitConfig.image,
                price = baitConfig.price,
                requiredLevel = baitConfig.requiredLevel
            }
        end

        guideFish[#guideFish + 1] = {
            name = fish.name,
            label = fish.label,
            depth = fish.depth,
            probability = fish.probability,
            maxDrop = fish.maxDrop,
            price = fish.sellPrice,
            experience = fish.experience,
            shoreOdds = DepthMatch(fish.depth, shoreBandId),
            requiredLevel = 1,
            bait = baitDetails
        }
    end

    return {
        fish = guideFish,
        tournament = GetNextTournamentInfo and GetNextTournamentInfo() or nil
    }
end)

function FindAttachment(slotName, itemName)
    for _, attachment in ipairs(Config.FishingAttachments and Config.FishingAttachments[slotName] or {}) do
        if attachment.item == itemName then
            return attachment
        end
    end
    return nil
end

function GetPlayerFisherLevel(source)
    local identifier = GetPlayeridentifier(source)
    if identifier and PlayersLevels[identifier] and PlayersLevels[identifier].level then
        return PlayersLevels[identifier].level
    end
    return 1
end

function IsRodTierUnlocked(source, tier, playerLevel)
    local reqLevel = tier.requiredLevel or 1
    return playerLevel >= reqLevel
end

function UsableRods(source)
    local playerLevel = GetPlayerFisherLevel(source)
    local result = {}
    for index, tier in ipairs(Config.RodTiers or {}) do
        if IsRodTierUnlocked(source, tier, playerLevel) then
            result[#result + 1] = {
                tier = tier,
                index = index
            }
        end
    end
    return result
end

function InventoryRods(source)
    local playerLevel = GetPlayerFisherLevel(source)
    local result = {}
    for index, tier in ipairs(Config.RodTiers or {}) do
        local count = GetItemCountFromInventory(source, tier.item) or 0
        if count > 0 then
            result[#result + 1] = {
                tier = tier,
                index = index,
                usable = playerLevel >= (tier.requiredLevel or 1)
            }
        end
    end
    return result
end

function GetRodTier(source)
    local rodTiers = Config.RodTiers or {}
    local playerLevel = GetPlayerFisherLevel(source)
    local selectedItem = playerSelectedRods[source]

    if selectedItem then
        for index, tier in ipairs(rodTiers) do
            if tier.item == selectedItem and IsRodTierUnlocked(source, tier, playerLevel) then
                return tier, index
            end
        end
        playerSelectedRods[source] = nil
    end

    for index = #rodTiers, 1, -1 do
        local tier = rodTiers[index]
        if IsRodTierUnlocked(source, tier, playerLevel) then
            return tier, index
        end
    end

    local defaultTier = rodTiers[1]
    if not defaultTier then
        defaultTier = {
            item = Config.FishingEquipment and Config.FishingEquipment.wooden_rod and Config.FishingEquipment.wooden_rod.item,
            slots = 4,
            bonusScale = 1.0,
            breakChance = Config.FishingRodBreakChance or 10,
            perks = {}
        }
    end

    return defaultTier, 1
end

function SelectRod(source, itemName)
    if type(itemName) ~= "string" then return false end

    local playerLevel = GetPlayerFisherLevel(source)
    for _, tier in ipairs(Config.RodTiers or {}) do
        if tier.item == itemName and IsRodTierUnlocked(source, tier, playerLevel) then
            playerSelectedRods[source] = itemName
            return true
        end
    end

    return false
end

function RodSlots(rodTier)
    local slotsMap = {}
    local maxSlots = math.min(rodTier.slots or #rodSlotsOrder, #rodSlotsOrder)
    for i = 1, maxSlots do
        slotsMap[rodSlotsOrder[i]] = true
    end
    return slotsMap
end

function GetGearBonus(source, bonusKey)
    local tier = GetRodTier(source)
    local allowedSlots = RodSlots(tier)
    local totalBonus = 0

    for slotName, itemName in pairs(playerGear[source] or {}) do
        if allowedSlots[slotName] and itemName then
            local attachment = FindAttachment(slotName, itemName)
            if attachment and attachment.bonus and attachment.bonus[bonusKey] then
                totalBonus = totalBonus + attachment.bonus[bonusKey]
            end
        end
    end

    local bonusScale = tier.bonusScale or 1.0
    totalBonus = totalBonus * bonusScale

    if tier.perks and tier.perks[bonusKey] then
        totalBonus = totalBonus + tier.perks[bonusKey]
    end

    return totalBonus
end

function AllowedDepth(source)
    local depthConfig = Config.Depth or {}
    local playerLevel = math.min(GetPlayerFisherLevel(source), Config.MaxBonusLevel or 60)
    local baseDepth = depthConfig.Base or 6.0
    local perLevel = depthConfig.PerLevel or 0
    local gearBonus = GetGearBonus(source, "depthRating") or 0
    local perGearPoint = depthConfig.PerGearPoint or 0

    return baseDepth + (playerLevel * perLevel) + (gearBonus * perGearPoint)
end

RegisterNetEvent("qs-fisher:lineOut", function(rodHandle, targetX, targetY, targetZ)
    local src = source
    local rod = tonumber(rodHandle)
    local x = tonumber(targetX)
    local y = tonumber(targetY)
    local z = tonumber(targetZ)

    if not (rod and x and y and z) then return end

    local now = GetGameTimer()
    if lastLineOutTime[src] and (now - lastLineOutTime[src]) < rateLimitInterval then
        return
    end

    lastLineOutTime[src] = now
    activeLines[src] = { rod = rod, x = x, y = y, z = z }
    TriggerClientEvent("qs-fisher:remoteLineOut", -1, src, rod, x, y, z, false)
end)

RegisterNetEvent("qs-fisher:lineIn", function()
    local src = source
    if not activeLines[src] then return end

    activeLines[src] = nil
    TriggerClientEvent("qs-fisher:remoteLineIn", -1, src)
end)

RegisterNetEvent("qs-fisher:dangleOut", function(rodHandle)
    local src = source
    local rod = tonumber(rodHandle)
    if not rod then return end

    local now = GetGameTimer()
    if lastDangleOutTime[src] and (now - lastDangleOutTime[src]) < rateLimitInterval then
        return
    end

    lastDangleOutTime[src] = now
    activeDangles[src] = true
    TriggerClientEvent("qs-fisher:remoteDangleOut", -1, src, rod)
end)

RegisterNetEvent("qs-fisher:dangleIn", function()
    local src = source
    if not activeDangles[src] then return end

    activeDangles[src] = nil
    TriggerClientEvent("qs-fisher:remoteLineIn", -1, src)
end)

AddEventHandler("playerDropped", function()
    local src = source
    lastLineOutTime[src] = nil
    lastDangleOutTime[src] = nil

    local wasActive = activeLines[src] or activeDangles[src]
    activeLines[src] = nil
    activeDangles[src] = nil

    if wasActive then
        TriggerClientEvent("qs-fisher:remoteLineIn", -1, src)
    end
end)

lib.callback.register("qs-fisher:getActiveLines", function()
    return activeLines
end)

lib.callback.register("qs-fisher:getDepthLimit", function(source)
    return AllowedDepth(source)
end)

RegisterNetEvent("qs-fisher:setGear", function(slotName, itemName)
    local src = source
    if not validGearSlots[slotName] then return end

    if not playerGear[src] then
        playerGear[src] = {}
    end

    if itemName == nil or itemName == false then
        playerGear[src][slotName] = nil
        return
    end

    if type(itemName) ~= "string" then return end

    local attachment = FindAttachment(slotName, itemName)
    if not attachment then return end

    local usable = UsableRods(src)
    if #usable == 0 then return end

    local rodTier = GetRodTier(src)
    local slots = RodSlots(rodTier)
    if not slots[slotName] then return end

    local playerLevel = GetPlayerFisherLevel(src)
    if playerLevel < (attachment.requiredLevel or 1) then return end

    local count = GetItemCountFromInventory(src, itemName)
    if not count or count <= 0 then return end

    playerGear[src][slotName] = itemName
end)

function GetAttachmentsData(source)
    local playerLevel = GetPlayerFisherLevel(source)
    local usableRodsList = UsableRods(source)
    local hasUsableRods = #usableRodsList > 0
    local currentRodTier, currentTierIndex = GetRodTier(source)
    local unlockedSlots = hasUsableRods and RodSlots(currentRodTier) or {}
    local nextRodTier = (Config.RodTiers or {})[currentTierIndex + 1]

    local attachmentsBySlot = {}
    for slotName, attachmentList in pairs(Config.FishingAttachments or {}) do
        attachmentsBySlot[slotName] = {}
        for _, attachment in ipairs(attachmentList or {}) do
            local count = GetItemCountFromInventory(source, attachment.item)
            if count and count > 0 then
                local baitInfo = (slotName == "bait") and GetBaitInfo()[attachment.item:lower()] or nil
                attachmentsBySlot[slotName][#attachmentsBySlot[slotName] + 1] = {
                    item = attachment.item,
                    label = attachment.label,
                    image = attachment.image,
                    requiredLevel = attachment.requiredLevel,
                    bonus = attachment.bonus,
                    count = count,
                    depths = baitInfo and baitInfo.depths or nil,
                    fish = baitInfo and baitInfo.fish or nil
                }
            end
        end
    end

    local slotStatusList = {}
    for _, slotName in ipairs(rodSlotsOrder) do
        local isUnlocked = unlockedSlots[slotName] == true
        local unlockedByTier = nil
        if not isUnlocked then
            for _, tier in ipairs(Config.RodTiers or {}) do
                if (tier.slots or 0) >= #slotStatusList + 1 then
                    unlockedByTier = {
                        label = tier.label,
                        requiredLevel = tier.requiredLevel
                    }
                    break
                end
            end
        end

        slotStatusList[#slotStatusList + 1] = {
            slot = slotName,
            unlocked = isUnlocked,
            unlockedBy = unlockedByTier
        }
    end

    local inventoryRodsList = {}
    for _, rodEntry in ipairs(InventoryRods(source)) do
        inventoryRodsList[#inventoryRodsList + 1] = {
            item = rodEntry.tier.item,
            label = rodEntry.tier.label,
            image = rodEntry.tier.image,
            palette = rodEntry.tier.palette or rodEntry.index,
            slots = rodEntry.tier.slots,
            bonusScale = rodEntry.tier.bonusScale or 1.0,
            breakChance = rodEntry.tier.breakChance or 0,
            perks = rodEntry.tier.perks or {},
            requiredLevel = rodEntry.tier.requiredLevel or 1,
            tier = rodEntry.index,
            usable = rodEntry.usable,
            selected = hasUsableRods and (rodEntry.tier.item == currentRodTier.item) or false
        }
    end

    local result = {
        attachments = attachmentsBySlot,
        playerLevel = playerLevel,
        rods = inventoryRodsList,
        slots = slotStatusList
    }

    if hasUsableRods then
        result.rod = {
            item = currentRodTier.item,
            label = currentRodTier.label,
            image = currentRodTier.image,
            palette = currentRodTier.palette or currentTierIndex,
            slots = currentRodTier.slots,
            bonusScale = currentRodTier.bonusScale or 1.0,
            breakChance = currentRodTier.breakChance or (Config.FishingRodBreakChance or 0),
            perks = currentRodTier.perks or {},
            requiredLevel = currentRodTier.requiredLevel or 1,
            tier = currentTierIndex,
            tiers = #(Config.RodTiers or {})
        }
    end

    if nextRodTier then
        result.nextRod = {
            label = nextRodTier.label,
            slots = nextRodTier.slots,
            bonusScale = nextRodTier.bonusScale or 1.0,
            breakChance = nextRodTier.breakChance or 0,
            perks = nextRodTier.perks or {},
            requiredLevel = nextRodTier.requiredLevel or 1,
            price = nextRodTier.price or 0
        }
    end

    return result
end

lib.callback.register("qs-fisher:getAttachments", function(source)
    return GetAttachmentsData(source)
end)

lib.callback.register("qs-fisher:selectRod", function(source, itemName)
    if not SelectRod(source, itemName) then
        return nil
    end
    return GetAttachmentsData(source)
end)

AddEventHandler("playerDropped", function()
    local src = source
    playerGear[src] = nil
    activeCasts[src] = nil
    lastCastTime[src] = nil
    playerSelectedRods[src] = nil
    pendingDecisions[src] = nil
end)

function GetBaitLevel(baitItem)
    if not baitItem then return 1 end
    local attachment = FindAttachment("bait", baitItem)
    return attachment and attachment.requiredLevel or 1
end

function ClampCastPower(rawPower)
    if not (Config.Cast and Config.Cast.Enabled) then
        return 1.0
    end
    local num = tonumber(rawPower) or 0
    return math.max(0, math.min(num, 1))
end

function DistanceForPower(power)
    if not (Config.Cast and Config.Cast.Enabled) then
        return DEFAULT_DISTANCE
    end
    local castConfig = Config.Cast
    local minD = castConfig.MinDistance
    local maxD = castConfig.MaxDistance
    return minD + ((maxD - minD) * power)
end

function CastPowerFor(probability)
    if not (Config.Cast and Config.Cast.Enabled) then
        return 0
    end
    local prob = probability or 0
    local raw = (100 - prob) / 100 * CAST_POWER_PROB_FACTOR
    return math.max(0, math.min(raw, 1))
end

function DrawFish(depthBand, attachedBait, extraChance, castPower, hotspotBoost)
    local candidateFish = {}
    local totalFishWeight = 0.0
    local maxFishProbability = 0.0

    for _, fish in ipairs(GetOrderedFish()) do
        local weight = fish.probability * DepthMatch(fish.depth, depthBand) * BaitMatch(attachedBait, fish)
        local requiredPower = CastPowerFor(fish.probability)
        if (castPower or 0) < requiredPower then
            weight = weight * WEAK_CAST_PENALTY
        end

        if weight > 0 then
            totalFishWeight = totalFishWeight + weight
            candidateFish[#candidateFish + 1] = {
                fish = fish,
                weight = weight
            }
            if maxFishProbability < fish.probability then
                maxFishProbability = fish.probability
            end
        end
    end

    local rarityMultiplier = hotspotBoost and tonumber(hotspotBoost.Rarity) or nil
    if rarityMultiplier and rarityMultiplier > 1.0 and maxFishProbability > 0 then
        totalFishWeight = 0.0
        for _, entry in ipairs(candidateFish) do
            local rarityFactor = 1 - (entry.fish.probability / maxFishProbability)
            entry.weight = entry.weight * (rarityMultiplier ^ rarityFactor)
            totalFishWeight = totalFishWeight + entry.weight
        end
    end

    local depthConfig = Config.Depth or {}
    local powerFactor = 1 - (math.min(math.max(castPower or 0, 0), 1) * CAST_POWER_EMPTY_SCALE)
    local emptyWeight = math.max((depthConfig.EmptyWeight or 0) * powerFactor, 0)

    if hotspotBoost then
        local emptyReduction = math.min(math.max(tonumber(hotspotBoost.EmptyChance) or 0, 0), 100) / 100
        emptyWeight = emptyWeight * (1 - emptyReduction)
    end

    DebugPrint(string.format("cast draw · depth %s · bait %s · power %.2f · fish weight %.1f vs empty %.1f",
        depthBand or "?",
        tostring(attachedBait),
        castPower or 0,
        totalFishWeight,
        emptyWeight
    ))

    local roll = math.random() * (totalFishWeight + emptyWeight)
    if roll >= totalFishWeight then
        return nil
    end

    local currentSum = 0.0
    local selectedEntry = candidateFish[#candidateFish]
    for _, entry in ipairs(candidateFish) do
        currentSum = currentSum + entry.weight
        if roll < currentSum then
            selectedEntry = entry
            break
        end
    end

    local selectedFish = selectedEntry.fish
    local multiChance = Config.MultiCatch and Config.MultiCatch.Chance or 0
    local catchAmount = 1

    if hotspotBoost and tonumber(hotspotBoost.MultiCatch) then
        multiChance = math.min(multiChance * hotspotBoost.MultiCatch, 100)
    end

    if selectedFish.maxDrop > 1 and multiChance > 0 then
        if multiChance >= math.random(1, 100) then
            catchAmount = math.random(2, selectedFish.maxDrop)
        end
    end

    local extraAwarded = false
    if extraChance > 0 and extraChance >= math.random(1, 100) then
        catchAmount = catchAmount + 1
        extraAwarded = true
    end

    return selectedFish, catchAmount, extraAwarded
end

function CalculateFightDifficulty(fish, specimenQuality, fightEase)
    local diffConfig = Config.FightDifficulty or {}
    if not diffConfig.Enabled or not fish then
        return 0
    end

    local tierBase = (diffConfig.Tiers and diffConfig.Tiers[fish.depth or ""]) or 0.5
    local qualityAdded = (tonumber(specimenQuality) or 0.5) * FIGHT_SPECIMEN_QUALITY_SCALE
    local combinedDiff = math.max(0, math.min(tierBase + qualityAdded, 1))

    local easePercent = math.min(math.max(tonumber(fightEase) or 0, 0), MAX_FIGHT_EASE_PERCENT)
    return combinedDiff * (1 - (easePercent / 100))
end

function BuildFightParameters(difficulty, lineStrengthBonus)
    local strengthMultiplier = 1 + ((lineStrengthBonus or 0) / 100)
    local maxAngle = (DEFAULT_MAX_ANGLE * strengthMultiplier) * (1 - (FIGHT_ANGLE_REDUCTION * difficulty))
    local pullSpeed = BASE_PULL_SPEED * (1 - (FIGHT_PULL_REDUCTION * difficulty))
    local slipSpeed = BASE_SLIP_SPEED * (1 + ((FIGHT_SLIP_MULTIPLIER - 1) * difficulty))
    local turnRate = 1 + (FIGHT_TURN_MULTIPLIER * difficulty)

    return {
        maxAngle = maxAngle,
        pullSpeed = pullSpeed,
        slipSpeed = slipSpeed,
        turnRate = turnRate
    }
end

-- Gate for the /testkeep helper in client/fishing.lua: same ace as the admin panel.
lib.callback.register("qs-fisher:testKeepAllowed", function(source)
    if IsPlayerAdmin then
        return IsPlayerAdmin(source) == true
    end
    return false
end)

lib.callback.register("qs-fisher:testFightSettings", function(source, difficultyInput)
    local clampedDiff = math.max(0.0, math.min(tonumber(difficultyInput) or 1.0, 1.0))
    local lineStrength = GetGearBonus(source, "lineStrength")
    return BuildFightParameters(clampedDiff, lineStrength)
end)

function BoatUnderPlayer(source)
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return false end

    if not GetVehicleType then return true end

    local vehicle = GetVehiclePedIsIn and GetVehiclePedIsIn(ped, false) or 0
    if vehicle ~= 0 then
        local vType = GetVehicleType(vehicle) or ""
        if boatVehicleTypes[vType] then
            return true
        end
    end

    if not GetAllVehicles then return true end

    local playerCoords = GetEntityCoords(ped)
    for _, veh in ipairs(GetAllVehicles() or {}) do
        local vehCoords = GetEntityCoords(veh)
        if vehCoords and #(playerCoords - vehCoords) <= BOAT_DETECTION_RADIUS then
            local vType = GetVehicleType(veh) or ""
            if boatVehicleTypes[vType] then
                return true
            end
        end
    end

    return false
end

lib.callback.register("qs-fisher:beginCast", function(source, castDepth, castPower, rawDepth)
    local src = source
    local depthValue = tonumber(rawDepth)

    if not depthValue or depthValue ~= depthValue or depthValue < 0 then
        return { ok = false, reason = "YOU_ARE_NOT_FACING_THE_WATER" }
    end

    local shoreDepth = tonumber(Config.Depth and Config.Depth.ShoreDepth) or 6.0
    if depthValue > shoreDepth and not BoatUnderPlayer(src) then
        depthValue = shoreDepth
    end

    local maxDepthAllowed = AllowedDepth(src)
    if depthValue > maxDepthAllowed then
        return {
            ok = false,
            reason = "DEPTH_TOO_DEEP_FOR_YOU",
            allowedDepth = math.floor((maxDepthAllowed * 10) + 0.5) / 10
        }
    end

    local bandId = DepthBandAt(depthValue)
    if not bandId then
        return { ok = false, reason = "YOU_ARE_NOT_FACING_THE_WATER" }
    end

    local clampedPower = ClampCastPower(castPower)
    if Config.Cast and Config.Cast.Enabled and clampedPower < MIN_CAST_POWER then
        return { ok = false, reason = "CAST_TOO_WEAK" }
    end

    local usable = UsableRods(src)
    if #usable == 0 then
        local lowestRequiredLevel = nil
        for _, tier in ipairs(Config.RodTiers or {}) do
            local count = GetItemCountFromInventory(src, tier.item) or 0
            if count > 0 then
                local reqLevel = tier.requiredLevel or 1
                if not lowestRequiredLevel or lowestRequiredLevel > reqLevel then
                    lowestRequiredLevel = reqLevel
                end
            end
        end

        if lowestRequiredLevel then
            return {
                ok = false,
                reason = "ROD_LEVEL_TOO_LOW",
                requiredLevel = lowestRequiredLevel
            }
        end

        return { ok = false, reason = "NOTIFY_NEED_ROD" }
    end

    local now = GetGameTimer()
    if lastCastTime[src] and (now - lastCastTime[src]) < 1500 then
        return { ok = false, reason = "CAST_REFUSED" }
    end

    if activeCasts[src] then
        return { ok = false, reason = "CAST_REFUSED" }
    end

    lastCastTime[src] = now
    local playerLevel = GetPlayerFisherLevel(src)
    local levelBonuses = GetLevelBonuses(playerLevel)

    local rawBiteTime = math.random(Config.BiteTime.min, Config.BiteTime.max) * 1000
    local biteReduction = math.min((GetGearBonus(src, "biteTimeReduction") + levelBonuses.biteTimeReduction) / 100, 0.9)
    local waitTime = math.max(math.floor(rawBiteTime * (1 - biteReduction)), MIN_BITE_WAIT_MS)

    local fightEaseBonus = GetGearBonus(src, "fightEase") + levelBonuses.fightEase
    local attachedGear = playerGear[src] or {}
    local castToken = string.format("%d-%d-%d", src, now, math.random(100000, 999999))
    local totalExtraChance = GetGearBonus(src, "extraCatchChance") + levelBonuses.extraCatchChance
    local hotspotBoost = HotspotBoostFor and HotspotBoostFor(src) or nil

    local drawnFish, catchAmount, extraAwarded = DrawFish(bandId, attachedGear.bait, totalExtraChance, clampedPower, hotspotBoost)
    local leadFishStats = nil
    if drawnFish then
        leadFishStats = RollFishStats(drawnFish.name, {
            level = playerLevel,
            power = clampedPower,
            depth = bandId,
            baitLevel = GetBaitLevel(attachedGear.bait),
            gearTrophy = GetGearBonus(src, "specimenSize")
        })
    end

    activeCasts[src] = {
        token = castToken,
        depth = bandId,
        bait = attachedGear.bait,
        readyAt = now + waitTime,
        power = clampedPower,
        level = playerLevel,
        fish = drawnFish,
        amount = catchAmount,
        extra = extraAwarded,
        lead = leadFishStats
    }

    local difficulty = CalculateFightDifficulty(drawnFish, leadFishStats and leadFishStats.quality or nil, fightEaseBonus)
    local fightParams = BuildFightParameters(difficulty, GetGearBonus(src, "lineStrength"))

    return {
        ok = true,
        token = castToken,
        waitTime = waitTime,
        bait = attachedGear.bait,
        depth = bandId,
        power = clampedPower,
        allowedDepth = maxDepthAllowed,
        distance = DistanceForPower(clampedPower),
        fight = fightParams
    }
end)

function ApplyCatch(source, identifier, catchRecord, isKept)
    local result = {
        kept = isKept == true
    }

    local specimens = catchRecord.specimens or { catchRecord.stats }
    local carriedCount = 0
    local missingItemName = nil

    if isKept then
        for _, specimen in ipairs(specimens) do
            local metadata = nil
            if Config.InventoryMetadata then
                metadata = {
                    weight = specimen.weight,
                    quality = specimen.quality,
                    trophy = specimen.trophy or nil,
                    description = string.format("%.2f kg", specimen.weight)
                }
            end

            local success, errCode = AddInventoryItem(source, catchRecord.fish.name, 1, metadata)
            if success == false then
                if errCode == "unknown_item" then
                    missingItemName = catchRecord.fish.name
                end
                break
            end
            carriedCount = carriedCount + 1
        end

        if missingItemName then
            TriggerClientEvent("qs-fisher:sendNotification", source, "notify", "error", Lang("NOTIFY_ITEM_DOES_NOT_EXIST"):format(WarnMissingItem("a fish in Config.Fish", missingItemName)))
        else
            if carriedCount < #specimens then
                result.inventoryFull = true
                TriggerClientEvent("qs-fisher:sendNotification", source, "notify", "error", Lang("NOTIFY_INVENTORY_FULL"))
            end
        end

        result.kept = carriedCount > 0
    end

    result.carried = carriedCount
    result.missingItem = missingItemName

    local awardedCount = missingItemName and #specimens or carriedCount
    local hasNewRecord = false

    for index, specimen in ipairs(specimens) do
        local keptThisOne = index <= awardedCount
        local expMultiplier = keptThisOne and (Config.CatchDecision.KeepExperience or 1.0) or (Config.CatchDecision.ReleaseExperience or 1.0)

        if not keptThisOne and specimen.trophy then
            expMultiplier = expMultiplier * (Config.CatchDecision.TrophyReleaseBonus or 1.0)
        end

        local expEarned = math.floor((catchRecord.fish.experience * expMultiplier) + 0.5)
        AddExperience(identifier, expEarned, source)

        if RecordCatch(identifier, catchRecord.fish.name, specimen, not keptThisOne) then
            hasNewRecord = true
        end
    end

    result.newRecord = hasNewRecord

    if ReportTournamentCatch then
        local fishWeight = catchRecord.stats and catchRecord.stats.weight or 0
        ReportTournamentCatch(source, identifier, fishWeight, catchRecord.fish.label, #specimens)
    end

    if awardedCount > 0 or Config.CatchDecision.ReleaseCountsForQuests then
        local questCount = Config.CatchDecision.ReleaseCountsForQuests and (catchRecord.amount or awardedCount) or awardedCount
        UpdateGroupQuestProgress(source, catchRecord.fish.name, questCount)

        if Config.QuasarInventoryQuests then
            TellQuasarInventory("UpdateQuestProgress", source, "catch_fish", 2)
        end
    end

    local unlockedAchievements = CheckAchievements(source, identifier)
    if #unlockedAchievements > 0 then
        TriggerClientEvent("qs-fisher:achievementsUnlocked", source, unlockedAchievements)
    end

    return result
end

lib.callback.register("qs-fisher:resolveCatch", function(source, token, isSuccess, isCancelled)
    local src = source
    local castData = activeCasts[src]

    if not castData or type(token) ~= "string" or castData.token ~= token then
        return nil
    end

    local now = GetGameTimer()
    if now < castData.readyAt then
        activeCasts[src] = nil
        return nil
    end

    activeCasts[src] = nil
    local identifier = GetPlayeridentifier(src)
    local result = {
        success = isSuccess == true
    }

    if isCancelled then
        result.cancelled = true
        return result
    end

    local baitSaverChance = GetGearBonus(src, "baitSaver")
    local baitSaved = math.random(1, 100) <= baitSaverChance
    result.baitSaved = baitSaved or (castData.bait ~= nil)

    if castData.bait and not baitSaved then
        local count = GetItemCountFromInventory(src, castData.bait) or 0
        if count > 0 then
            RemoveInventoryItem(src, castData.bait, 1)
        end

        if count <= 1 then
            if playerGear[src] then
                playerGear[src].bait = nil
            end
            TriggerClientEvent("qs-fisher:gearChanged", src, "bait", nil)
        end
    end

    if not isSuccess then
        local tier = GetRodTier(src)
        local breakChance = tier.breakChance or Config.FishingRodBreakChance or 0
        local durabilityBonus = GetGearBonus(src, "rodDurability") / 100
        local breakMultiplier = math.max(1 - durabilityBonus, 0.15)
        breakChance = breakChance * breakMultiplier

        if breakChance >= math.random(1, 100) then
            local rodCount = GetItemCountFromInventory(src, tier.item) or 0
            if rodCount > 0 then
                RemoveInventoryItem(src, tier.item, 1)
                result.rodBroke = true
            end
        end

        return result
    end

    local fish = castData.fish
    local amount = castData.amount
    local extra = castData.extra

    if not fish then
        AddInventoryItem(src, Config.GarbageItem, 1)
        result.garbage = true
        return result
    end

    local specimenParams = {
        level = castData.level,
        power = castData.power,
        depth = castData.depth,
        baitLevel = GetBaitLevel(castData.bait),
        gearTrophy = GetGearBonus(src, "specimenSize")
    }

    local specimens = {}
    if castData.lead then
        specimens[1] = castData.lead
    end

    for _ = #specimens + 1, amount do
        specimens[#specimens + 1] = RollFishStats(fish.name, specimenParams)
    end

    local bestSpecimen = specimens[1]
    for _, specimen in ipairs(specimens) do
        if specimen.quality > bestSpecimen.quality then
            bestSpecimen = specimen
        end
    end

    local catchSummary = {
        fish = fish,
        amount = amount,
        extra = extra,
        stats = bestSpecimen,
        specimens = specimens,
        identifier = identifier
    }

    result.item = fish.name
    result.label = fish.label
    result.amount = amount
    result.extra = extra
    result.stats = bestSpecimen
    result.specimens = specimens

    if not (Config.CatchDecision and Config.CatchDecision.Enabled) then
        -- This is the switch that silences the keep-it window. Say so out loud the
        -- first time it happens rather than leaving the owner hunting for a bug:
        -- the admin panel saves into qs_fisher_config and that overrides config.lua
        -- on every start, so the value that counts is rarely the one in the file.
        if not catchDecisionNoticeShown then
            catchDecisionNoticeShown = true
            local reason = Config.CatchDecision
                and "Config.CatchDecision.Enabled is false"
                or "Config.CatchDecision is missing entirely"
            print(string.format("^3[qs-fishingjob]^0 the keep-it window is off (%s), so every fish goes straight into the bag.\n"
                .. "  Check config/config.lua, then the admin panel: a saved setting in `qs_fisher_config`\n"
                .. "  overrides config.lua at every start. `SELECT * FROM qs_fisher_config WHERE path LIKE 'CatchDecision%%';`",
                reason))
        end

        local applied = ApplyCatch(src, identifier, catchSummary, true)
        result.kept = applied.kept
        result.newRecord = applied.newRecord
        result.inventoryFull = applied.inventoryFull
        result.carried = applied.carried
        result.missingItem = applied.missingItem
        return result
    end

    local previousRecord = LoadPlayerRecords(identifier)[fish.name]
    catchSummary.token = token
    pendingDecisions[src] = catchSummary

    result.decide = true
    result.timeout = Config.CatchDecision.Timeout
    result.previousBest = previousRecord and { weight = previousRecord.bestWeight } or nil

    CreateThread(function()
        local timeout = (Config.CatchDecision.Timeout or 9000) + 2500
        Wait(timeout)

        local pending = pendingDecisions[src]
        if pending and pending.token == token then
            pendingDecisions[src] = nil
            local defaultKeeps = Config.CatchDecision.TimeoutKeeps ~= false
            ApplyCatch(src, identifier, pending, defaultKeeps)
        end
    end)

    return result
end)

lib.callback.register("qs-fisher:decideCatch", function(source, token, isKept)
    local src = source
    local pending = pendingDecisions[src]

    if not pending or type(token) ~= "string" or pending.token ~= token then
        -- Already settled by the fallback timer, or the window answered twice.
        DebugPrint("decideCatch: nothing pending for", src, "token", tostring(token))
        return nil
    end

    pendingDecisions[src] = nil
    DebugPrint("decideCatch: keep =", isKept == true, "for", pending.fish and pending.fish.name)

    -- ApplyCatch hands out the item, pays the experience and writes the records.
    -- If any of that throws, the player must still be told what happened instead
    -- of the callback dying and the client sitting on a window that did nothing.
    local ok, applied = pcall(ApplyCatch, src, pending.identifier, pending, isKept == true)
    if not ok then
        print(string.format("^1[qs-fishingjob]^0 decideCatch could not settle the catch: %s", tostring(applied)))
        return {
            kept = false,
            failed = true,
            label = pending.fish and pending.fish.label or "?",
            amount = pending.amount
        }
    end

    return {
        kept = applied.kept,
        newRecord = applied.newRecord,
        inventoryFull = applied.inventoryFull,
        label = pending.fish.label,
        amount = pending.amount,
        carried = applied.carried,
        missingItem = applied.missingItem,
        stats = pending.stats,
        specimens = pending.specimens
    }
end)

lib.callback.register("qs-fisher:getRecords", function(source)
    local identifier = GetPlayeridentifier(source)
    if not identifier then
        return { records = {}, totals = {} }
    end

    return {
        records = GetPlayerRecords(identifier),
        totals = GetRecordTotals(identifier)
    }
end)

exports("getPlayerGear", function(targetSource)
    local gear = playerGear[targetSource]
    if not gear then
        return {}
    end

    return {
        bait = gear.bait,
        hook = gear.hook,
        reel = gear.reel,
        line = gear.line
    }
end)
--WKLeak9YOneITopR3 : https://discord.gg/zqcBffbMZn
--WKLeak-xGOnPLTop$W : https://discord.gg/zqcBffbMZn
--WKLeak_NMOnKITopRA : https://discord.gg/zqcBffbMZn
--WKLeak_tqOnxcTopw9 : https://discord.gg/zqcBffbMZn
--WKLeakavOnu5Top6L : https://discord.gg/zqcBffbMZn
