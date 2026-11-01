--[[   -- https://discord.gg/zqcBffbMZn ]]
local CATEGORY_ORDER = {
    equipment = 1,
    hook = 2,
    reel = 3,
    line = 4,
    bait = 5
}

local ITEM_ORDER = {
    fishing_kit = 10,
    crab_trap = 20,
    speargun = 40,
    spear = 41,
    dive_tank = 42,
    skewer_grill_boat = 50
}
local DEFAULT_ITEM_ORDER = 60

local CachedBuyCatalog = nil
local CachedSellCatalog = nil
local ShopCooldowns = {}

function CanSellDiveTank()
    local breathCfg = (Config.Speargun and Config.Speargun.Breath) or {}
    local shopSetting = tostring(breathCfg.Shop or "auto")
    if shopSetting == "always" then
        return true
    end
    if shopSetting == "never" then
        return false
    end
    local extRes = breathCfg.ExternalResource
    if not extRes or extRes == "" then
        return true
    end
    return GetResourceState(extRes) ~= "started"
end

function GetBuyCatalog()
    if CachedBuyCatalog then
        return CachedBuyCatalog
    end

    local catalog = {}
    local tankItem = (Config.Speargun and Config.Speargun.Tank) or "dive_tank"
    local allowTank = CanSellDiveTank()

    for _, eq in pairs(Config.FishingEquipment or {}) do
        if eq.item and eq.price and (eq.item ~= tankItem or allowTank) then
            catalog[eq.item] = {
                label = eq.label or eq.item,
                price = eq.price,
                requiredLevel = eq.requiredLevel or 1,
                category = "equipment",
                image = eq.image,
                order = ITEM_ORDER[eq.item] or DEFAULT_ITEM_ORDER
            }
        end
    end

    for idx, rod in ipairs(Config.RodTiers or {}) do
        if rod.item and rod.price then
            catalog[rod.item] = {
                label = rod.label or rod.item,
                price = rod.price,
                requiredLevel = rod.requiredLevel or 1,
                category = "equipment",
                bonus = rod.perks,
                image = rod.image,
                order = idx,
                rod = {
                    slots = rod.slots,
                    bonusScale = rod.bonusScale or 1.0,
                    breakChance = rod.breakChance or 0
                }
            }
        end
    end

    local netTiers = (Config.FishingNets and Config.FishingNets.Tiers) or {}
    for idx, net in ipairs(netTiers) do
        if net.item and net.price then
            catalog[net.item] = {
                label = net.label or net.item,
                price = net.price,
                requiredLevel = net.requiredLevel or 1,
                category = "equipment",
                image = net.image,
                order = 30 + idx
            }
        end
    end

    for catName, items in pairs(Config.FishingAttachments or {}) do
        for idx, att in ipairs(items or {}) do
            if att.item and att.price then
                local data = {
                    label = att.label or att.item,
                    price = att.price,
                    requiredLevel = att.requiredLevel or 1,
                    category = catName,
                    bonus = att.bonus,
                    image = att.image,
                    order = idx
                }

                if catName == "bait" and GetBaitInfo then
                    local baitMap = GetBaitInfo()
                    local info = baitMap and baitMap[att.item:lower()] or {}
                    data.depths = info.depths or {}
                    data.fish = info.fish or {}
                end

                catalog[att.item] = data
            end
        end
    end

    CachedBuyCatalog = catalog
    return catalog
end

function CalculateScaledFishPrice(itemName, basePrice, weight)
    local wpCfg = Config.WeightPricing or {}
    if not wpCfg.Enabled then
        return basePrice
    end
    if not weight and not Config.InventoryMetadata then
        return basePrice
    end

    local sizeCfg = Config.FishSizes and Config.FishSizes[itemName]
    local minW = sizeCfg and sizeCfg.weight and sizeCfg.weight[1]
    if not minW or minW <= 0 then
        return basePrice
    end

    local extraRatio = weight and math.max((weight / minW) - 1, 0) or 0
    local pct = wpCfg.Percent or 0
    local multiplier = 1 + (extraRatio * pct / 100)
    return math.ceil(basePrice * multiplier)
end

function FormatWeight(weight)
    local val = tonumber(weight) or 0
    local unit = Config.WeightUnit or "kg"
    if unit == "lb" then
        local ratio = Config.PoundsPerKilo or 2.20462
        return string.format("%.2f", val * ratio)
    end
    return string.format("%.2f", val)
end

function GetOxItemSlots(source, itemName)
    if not Config.InventoryMetadata or Config.Inventory ~= "ox" then
        return nil
    end
    local ok, res = pcall(function()
        return exports.ox_inventory:Search(source, "slots", itemName)
    end)
    if ok and type(res) == "table" then
        return res
    end
    return nil
end

function RemoveInventoryItemFromSlot(source, itemName, count, slot)
    if Config.Inventory == "ox" then
        local ok, res = pcall(function()
            return exports.ox_inventory:RemoveItem(source, itemName, count, nil, slot)
        end)
        if ok then
            return res
        end
    end
    return RemoveInventoryItem(source, itemName, count)
end

function GetPlayerSellableItemSummary(source, itemName, basePrice)
    local oxSlots = GetOxItemSlots(source, itemName)
    if oxSlots then
        local totalCount = 0
        local totalEarned = 0
        local specimens = {}

        for _, entry in ipairs(oxSlots) do
            local count = entry.count or entry.amount or 1
            local weight = entry.metadata and entry.metadata.weight
            local unitPrice = CalculateScaledFishPrice(itemName, basePrice, weight)

            totalCount = totalCount + count
            totalEarned = totalEarned + (unitPrice * count)
            specimens[#specimens + 1] = {
                slot = entry.slot,
                count = count,
                price = unitPrice,
                weight = weight,
                text = weight and FormatWeight(weight) or nil
            }
        end

        table.sort(specimens, function(a, b)
            local wA = a.weight or 0
            local wB = b.weight or 0
            if wA ~= wB then
                return wA > wB
            end
            return (a.slot or 0) < (b.slot or 0)
        end)

        return totalCount, totalEarned, specimens
    end

    local count = GetItemCountFromInventory(source, itemName) or 0
    return count, count * basePrice, nil
end

function RemovePlayerSellableItems(source, itemName, basePrice, maxAmount)
    if maxAmount <= 0 then
        return 0, 0
    end

    local oxSlots = GetOxItemSlots(source, itemName)
    if oxSlots then
        table.sort(oxSlots, function(a, b)
            local wA = (a.metadata and a.metadata.weight) or 0
            local wB = (b.metadata and b.metadata.weight) or 0
            return wA < wB
        end)

        local totalRemoved = 0
        local totalEarned = 0

        for _, entry in ipairs(oxSlots) do
            if maxAmount and totalRemoved >= maxAmount then
                break
            end

            local entryCount = entry.count or entry.amount or 1
            local take = maxAmount and math.min(entryCount, maxAmount - totalRemoved) or entryCount
            local weight = entry.metadata and entry.metadata.weight

            if RemoveInventoryItemFromSlot(source, itemName, take, entry.slot) ~= false then
                totalRemoved = totalRemoved + take
                local unitPrice = CalculateScaledFishPrice(itemName, basePrice, weight)
                totalEarned = totalEarned + (unitPrice * take)
            end
        end

        return totalRemoved, totalEarned
    end

    local available = GetItemCountFromInventory(source, itemName) or 0
    local toRemove = maxAmount and math.min(maxAmount, available) or available

    if toRemove > 0 and RemoveInventoryItem(source, itemName, toRemove) then
        return toRemove, toRemove * basePrice
    end

    return 0, 0
end

function RemovePlayerSellableSpecificSlots(source, itemName, basePrice, slotRequests)
    if basePrice <= 0 then
        return 0, 0
    end

    local oxSlots = GetOxItemSlots(source, itemName)
    if not oxSlots then
        return 0, 0
    end

    local slotMap = {}
    for _, item in ipairs(oxSlots) do
        slotMap[item.slot] = item
    end

    local totalRemoved = 0
    local totalEarned = 0
    local visitedSlots = {}

    for _, req in ipairs(slotRequests) do
        local slotData = slotMap[req.slot]
        if slotData and not visitedSlots[req.slot] then
            visitedSlots[req.slot] = true
            local available = slotData.count or slotData.amount or 1
            local take = math.min(req.amount, available)

            if take > 0 then
                local weight = slotData.metadata and slotData.metadata.weight
                if RemoveInventoryItemFromSlot(source, itemName, take, req.slot) ~= false then
                    totalRemoved = totalRemoved + take
                    local unitPrice = CalculateScaledFishPrice(itemName, basePrice, weight)
                    totalEarned = totalEarned + (unitPrice * take)
                end
            end
        end
    end

    return totalRemoved, totalEarned
end

function GetSellCatalog()
    if CachedSellCatalog then
        return CachedSellCatalog
    end

    local catalog = {}

    for _, zone in pairs(Config.Fish or {}) do
        for _, itemDef in ipairs(zone.items or {}) do
            catalog[itemDef[1]] = {
                label = itemDef[2],
                price = itemDef[5]
            }
        end
    end

    if Config.GarbageItem then
        catalog[Config.GarbageItem] = {
            label = Lang("GARBAGE_ITEM_LABEL"),
            price = Config.GarbagePrice or 1
        }
    end

    local crabSell = (Config.CrabTraps and Config.CrabTraps.Sell) or {}
    for itemName, data in pairs(crabSell) do
        catalog[itemName] = {
            label = data.label or itemName,
            price = data.price or 1
        }
    end

    CachedSellCatalog = catalog
    return catalog
end

function CheckShopCooldown(source)
    local now = GetGameTimer()
    local last = ShopCooldowns[source]
    if last and (now - last) < 400 then
        return false
    end
    ShopCooldowns[source] = now
    return true
end

AddEventHandler("playerDropped", function()
    ShopCooldowns[source] = nil
end)

function BuildShopData(source)
    local identifier = GetPlayeridentifier(source)
    local playerLevel = (identifier and PlayersLevels and PlayersLevels[identifier] and PlayersLevels[identifier].level) or 1

    local buyList = {}
    for itemName, itemData in pairs(GetBuyCatalog()) do
        buyList[#buyList + 1] = {
            name = itemName,
            label = itemData.label,
            price = itemData.price,
            requiredLevel = itemData.requiredLevel,
            category = itemData.category,
            bonus = itemData.bonus,
            depths = itemData.depths,
            fish = itemData.fish,
            image = itemData.image,
            rod = itemData.rod,
            order = itemData.order,
            owned = GetItemCountFromInventory(source, itemName)
        }
    end

    table.sort(buyList, function(a, b)
        local catA = CATEGORY_ORDER[a.category] or 99
        local catB = CATEGORY_ORDER[b.category] or 99
        if catA ~= catB then
            return catA < catB
        end
        local ordA = a.order or 99
        local ordB = b.order or 99
        if ordA ~= ordB then
            return ordA < ordB
        end
        if a.requiredLevel ~= b.requiredLevel then
            return a.requiredLevel < b.requiredLevel
        end
        if a.price ~= b.price then
            return a.price < b.price
        end
        return a.name < b.name
    end)

    local sellList = {}
    local totalSellValue = 0

    for itemName, itemData in pairs(GetSellCatalog()) do
        local count, earned, specimens = GetPlayerSellableItemSummary(source, itemName, itemData.price)
        if count > 0 then
            totalSellValue = totalSellValue + earned
            sellList[#sellList + 1] = {
                name = itemName,
                label = itemData.label,
                count = count,
                earned = earned,
                specimens = specimens,
                price = count > 0 and math.floor((earned / count) + 0.5) or itemData.price,
                base = itemData.price
            }
        end
    end

    table.sort(sellList, function(a, b)
        return a.price > b.price
    end)

    local wpCfg = Config.WeightPricing or {}
    return {
        buy = buyList,
        sell = sellList,
        totalMoney = totalSellValue,
        playerLevel = playerLevel,
        playerMoney = GetMoney(source),
        boatsEnabled = (Config.BoatRental and Config.BoatRental.Enabled) == true,
        weightPricing = {
            active = wpCfg.Enabled == true,
            percent = wpCfg.Percent or 0,
            unit = Config.WeightUnit or "kg"
        }
    }
end

lib.callback.register("qs-fisher:getShopData", function(source)
    local ok, res = pcall(BuildShopData, source)
    if ok then
        return res
    end
    print(string.format("^1[qs-fishingjob]^0 the shop could not be built: %s", tostring(res)))
    return {
        failed = true,
        buy = {},
        sell = {},
        totalMoney = 0,
        playerLevel = 1,
        playerMoney = 0
    }
end)

RegisterNetEvent("qs-fisher:buyItems", function(items)
    local src = source
    if type(items) ~= "table" or not CheckShopCooldown(src) then
        return
    end

    local identifier = GetPlayeridentifier(src)
    if not identifier then
        return
    end

    local playerLevel = (PlayersLevels and PlayersLevels[identifier] and PlayersLevels[identifier].level) or 1
    local buyCatalog = GetBuyCatalog()
    local maxLimit = Config.MaxShopPurchase or 100

    local itemQuantities = {}
    for _, entry in ipairs(items) do
        if type(entry) == "table" and entry.name and buyCatalog[entry.name] then
            local amount = math.floor(tonumber(entry.amount) or 0)
            if amount > 0 and playerLevel >= buyCatalog[entry.name].requiredLevel then
                itemQuantities[entry.name] = (itemQuantities[entry.name] or 0) + amount
            end
        end
    end

    local sanitizedOrder = {}
    local totalCost = 0
    for itemName, amount in pairs(itemQuantities) do
        local clamped = math.min(amount, maxLimit)
        sanitizedOrder[#sanitizedOrder + 1] = {
            name = itemName,
            amount = clamped
        }
        totalCost = totalCost + (clamped * buyCatalog[itemName].price)
    end

    if #sanitizedOrder == 0 or totalCost <= 0 then
        return
    end

    if totalCost > GetMoney(src) then
        TriggerClientEvent("qs-fisher:sendNotification", src, "notify", "error", Lang("NOT_ENOUGH_MONEY"))
        return
    end

    local itemsGiven = 0
    local actualSpent = 0
    local missingItems = {}
    local fullCount = 0
    local unavailableCount = 0

    for _, orderItem in ipairs(sanitizedOrder) do
        local success, err = AddInventoryItem(src, orderItem.name, orderItem.amount)
        if success == true then
            itemsGiven = itemsGiven + 1
            actualSpent = actualSpent + (orderItem.amount * buyCatalog[orderItem.name].price)
        elseif err == "unknown_item" then
            missingItems[#missingItems + 1] = orderItem.name
        elseif err == "unavailable" then
            unavailableCount = unavailableCount + 1
        else
            fullCount = fullCount + 1
        end
    end

    if #missingItems > 0 then
        local warn = WarnMissingItem("the shop catalogue: Config.FishingEquipment, Config.RodTiers, Config.FishingNets.Tiers or Config.FishingAttachments", missingItems)
        TriggerClientEvent("qs-fisher:sendNotification", src, "notify", "error", string.format(Lang("NOTIFY_ITEM_DOES_NOT_EXIST"), warn))
    end
    if fullCount > 0 then
        TriggerClientEvent("qs-fisher:sendNotification", src, "notify", "error", Lang("NOTIFY_INVENTORY_FULL"))
    end
    if unavailableCount > 0 then
        TriggerClientEvent("qs-fisher:sendNotification", src, "notify", "error", Lang("NOTIFY_INVENTORY_UNAVAILABLE"))
    end

    if itemsGiven > 0 then
        RemoveMoney(actualSpent, src)
        TriggerClientEvent("qs-fisher:sendNotification", src, "notify", "success", Lang("NOTIFY_YOU_BOUGHT") .. FormatCurrency(actualSpent))
    end
end)

RegisterNetEvent("qs-fisher:sellItems", function(items)
    local src = source
    if type(items) ~= "table" or not CheckShopCooldown(src) then
        return
    end

    local sellCatalog = GetSellCatalog()
    local totalPayout = 0
    local slotOrders = {}
    local genericOrders = {}

    for _, entry in ipairs(items) do
        if type(entry) == "table" and entry.name and sellCatalog[entry.name] then
            local price = sellCatalog[entry.name].price
            if price > 0 then
                local amount = math.floor(tonumber(entry.amount) or 0)
                local slot = tonumber(entry.slot)
                if amount > 0 then
                    if slot and Config.InventoryMetadata then
                        if not slotOrders[entry.name] then
                            slotOrders[entry.name] = {}
                        end
                        slotOrders[entry.name][#slotOrders[entry.name] + 1] = {
                            slot = slot,
                            amount = amount
                        }
                    else
                        genericOrders[entry.name] = (genericOrders[entry.name] or 0) + amount
                    end
                end
            end
        end
    end

    for itemName, requests in pairs(slotOrders) do
        local removed, earned = RemovePlayerSellableSpecificSlots(src, itemName, sellCatalog[itemName].price, requests)
        totalPayout = totalPayout + earned
    end

    for itemName, count in pairs(genericOrders) do
        local removed, earned = RemovePlayerSellableItems(src, itemName, sellCatalog[itemName].price, count)
        totalPayout = totalPayout + earned
    end

    if totalPayout <= 0 then
        return
    end

    AddMoney(src, totalPayout)
    AddEarnings(GetPlayeridentifier(src), totalPayout)

    if SendWebhook then
        SendWebhook("MoneyPaid", src, "Paid", "Catch sold at the shop", {
            WebhookField("Amount", "$" .. math.floor(totalPayout)),
            WebhookField("For", "Selling fish")
        })
    end
end)

RegisterNetEvent("qs-fisher:sellAllItems", function()
    local src = source
    if not CheckShopCooldown(src) then
        return
    end

    local totalPayout = 0
    for itemName, itemData in pairs(GetSellCatalog()) do
        local removed, earned = RemovePlayerSellableItems(src, itemName, itemData.price, nil)
        totalPayout = totalPayout + earned
    end

    if totalPayout <= 0 then
        return
    end

    AddMoney(src, totalPayout)
    AddEarnings(GetPlayeridentifier(src), totalPayout)

    if SendWebhook then
        SendWebhook("MoneyPaid", src, "Paid", "Whole catch sold at the shop", {
            WebhookField("Amount", "$" .. math.floor(totalPayout)),
            WebhookField("For", "Selling fish")
        })
    end
end)

lib.callback.register("qs-fisher:checkItem", function(source, itemName)
    local count = GetItemCountFromInventory(source, itemName)
    return (count and count > 0) or false
end)
--WKLeaksfVOnKQTopXB : https://discord.gg/zqcBffbMZn
--WKLeak-WfOnLDTopJW : https://discord.gg/zqcBffbMZn
--WKLeak_FuOn2qTop9S : https://discord.gg/zqcBffbMZn
--WKLeaksLzOnaDTopMa : https://discord.gg/zqcBffbMZn
--WKLeak-AnOn0DTopSV : https://discord.gg/zqcBffbMZn
