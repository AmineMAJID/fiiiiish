--[[   -- https://discord.gg/zqcBffbMZn ]]
function GetFoodBoatConfig()
    return Config.FoodBoat or {}
end

function GetPlayerRawCookableFish(source)
    local cookable = (GetCookableFish and GetCookableFish()) or {}
    local result = {}
    local total = 0
    local ordered = (GetOrderedFish and GetOrderedFish()) or {}
    for _, fish in ipairs(ordered) do
        if fish.name and cookable[fish.name] then
            local count = GetItemCountFromInventory(source, fish.name) or 0
            if count > 0 then
                result[#result + 1] = {
                    item = fish.name,
                    count = count
                }
                total = total + count
            end
        end
    end
    return result, total
end

local activeOrders = {}
local ORDER_TIMEOUT_SECONDS = 180

function GetFoodBoatItemPrice()
    local queueConfig = GetFoodBoatConfig().Queue or {}
    local pay = queueConfig.Pay
    if type(pay) == "table" then
        pay = pay[1]
    end
    return math.max(math.floor(tonumber(pay) or 24), 0)
end

function ArePlayersNear(src1, src2)
    local ped1 = GetPlayerPed(src1)
    local ped2 = GetPlayerPed(src2)
    if not ped1 or not ped2 or ped1 == 0 or ped2 == 0 then
        return false
    end
    local coords1 = GetEntityCoords(ped1)
    local coords2 = GetEntityCoords(ped2)
    return #(coords1 - coords2) <= 12.0
end

AddEventHandler("playerDropped", function()
    local droppedSrc = source
    activeOrders[droppedSrc] = nil
    for buyerSrc, order in pairs(activeOrders) do
        if order.seller == droppedSrc then
            activeOrders[buyerSrc] = nil
        end
    end
end)

lib.callback.register("qs-fisher:foodboat:stock", function(source)
    if not GetFoodBoatConfig().Enabled then
        return { raw = 0, cooked = 0 }
    end
    local _, rawCount = GetPlayerRawCookableFish(source)
    local cookedItem = GetFoodBoatConfig().Cooked or "brochette_fish_cooked"
    local cookedCount = GetItemCountFromInventory(source, cookedItem) or 0
    return {
        raw = rawCount,
        cooked = cookedCount
    }
end)

RegisterNetEvent("qs-fisher:foodboat:claim", function(cookOutcome)
    local playerSrc = source
    if not GetFoodBoatConfig().Enabled then
        return
    end
    local cookableList = GetPlayerRawCookableFish(playerSrc)
    local removedItem = nil
    for _, fish in ipairs(cookableList) do
        if RemoveInventoryItem(playerSrc, fish.item, 1) then
            removedItem = fish.item
            break
        end
    end
    if not removedItem then
        return
    end
    local resultItem = GetFoodBoatConfig().Cooked or "brochette_fish_cooked"
    if cookOutcome == "burnt" then
        resultItem = GetFoodBoatConfig().Burnt or "brochette_fish_burn"
    end
    AddInventoryItem(playerSrc, resultItem, 1)
end)

RegisterNetEvent("qs-fisher:foodboat:serve", function(targetBuyer)
    local sellerSrc = source
    local config = GetFoodBoatConfig()
    if not config.Enabled then
        return
    end
    local queueConfig = config.Queue or {}
    if queueConfig.Enabled == false then
        return
    end
    local cookedItem = config.Cooked or "brochette_fish_cooked"
    local itemPrice = GetFoodBoatItemPrice()

    local buyerSrc = tonumber(targetBuyer)
    if buyerSrc then
        local order = activeOrders[buyerSrc]
        if not order or order.seller ~= sellerSrc or order.left <= 0 then
            TriggerClientEvent("qs-fisher:notify", sellerSrc, "error", "FOODBOAT_NO_ORDER")
            return
        end
        if os.time() > order.until_ then
            activeOrders[buyerSrc] = nil
            TriggerClientEvent("qs-fisher:notify", sellerSrc, "error", "FOODBOAT_NO_ORDER")
            return
        end
        if not GetPlayerId(buyerSrc) or not ArePlayersNear(sellerSrc, buyerSrc) then
            TriggerClientEvent("qs-fisher:notify", sellerSrc, "error", "FOODBOAT_BUYER_GONE")
            return
        end
        local buyerMoney = GetMoney(buyerSrc) or 0
        if itemPrice > buyerMoney then
            TriggerClientEvent("qs-fisher:notify", sellerSrc, "error", "FOODBOAT_BUYER_BROKE")
            return
        end
        if not RemoveInventoryItem(sellerSrc, cookedItem, 1) then
            return
        end
        if not AddInventoryItem(buyerSrc, cookedItem, 1) then
            AddInventoryItem(sellerSrc, cookedItem, 1)
            TriggerClientEvent("qs-fisher:notify", sellerSrc, "error", "FOODBOAT_BUYER_FULL")
            return
        end
        RemoveMoney(itemPrice, buyerSrc)
        AddMoney(sellerSrc, itemPrice)
        order.left = order.left - 1
        if order.left <= 0 then
            activeOrders[buyerSrc] = nil
        end
        return
    end

    if RemoveInventoryItem(sellerSrc, cookedItem, 1) then
        AddMoney(sellerSrc, itemPrice)
    end
end)

RegisterNetEvent("qs-fisher:foodboat:sizzle", function()
    local playerSrc = source
    local config = GetFoodBoatConfig()
    if not config.Enabled then
        return
    end
    local soundConfig = config.Sound or {}
    if soundConfig.Enabled == false then
        return
    end
    if GetResourceState("xsound") ~= "started" then
        return
    end
    local ped = GetPlayerPed(playerSrc)
    local coords = GetEntityCoords(ped)
    if not coords then
        return
    end
    local soundUrl = string.format("nui://%s/sounds/grill_sound.mp3", GetCurrentResourceName())
    local soundId = string.format("foodboat_%s_%s", playerSrc, math.random(1000, 9999))
    pcall(function()
        exports.xsound:PlayUrlPos(-1, soundId, soundUrl, tonumber(soundConfig.Volume) or 0.01, coords)
        exports.xsound:Distance(-1, soundId, 12.0)
    end)
end)

RegisterNetEvent("qs-fisher:foodboat:order", function(targetSeller, count)
    local buyerSrc = source
    if not GetFoodBoatConfig().Enabled then
        return
    end
    local sellerSrc = tonumber(targetSeller)
    local orderCount = math.min(math.max(math.floor(tonumber(count) or 1), 1), 10)
    if not sellerSrc or sellerSrc == buyerSrc then
        return
    end
    if not GetPlayerId(sellerSrc) then
        return
    end
    local itemPrice = GetFoodBoatItemPrice()
    local buyerMoney = GetMoney(buyerSrc) or 0
    if buyerMoney < (itemPrice * orderCount) then
        TriggerClientEvent("qs-fisher:notify", buyerSrc, "error", "FOODBOAT_CANNOT_AFFORD")
        return
    end
    activeOrders[buyerSrc] = {
        seller = sellerSrc,
        left = orderCount,
        until_ = os.time() + ORDER_TIMEOUT_SECONDS
    }
    TriggerClientEvent("qs-fisher:foodboat:wants", sellerSrc, buyerSrc, orderCount)
end)

RegisterNetEvent("qs-fisher:foodboat:open", function(isOpen)
    local playerSrc = source
    if not GetFoodBoatConfig().Enabled then
        return
    end
    TriggerClientEvent("qs-fisher:foodboat:open", -1, playerSrc, isOpen == true)
end)

RegisterNetEvent("qs-fisher:foodboat:packed", function()
    local playerSrc = source
    if not GetFoodBoatConfig().Enabled then
        return
    end
    DebugPrint(string.format("food boat packed up for %s", playerSrc))
end)
--WKLeak-WMOnx0TopLO : https://discord.gg/zqcBffbMZn
--WKLeak-CVOnM!Topqb : https://discord.gg/zqcBffbMZn
--WKLeaksy8On9aTopdG : https://discord.gg/zqcBffbMZn
--WKLeak_jLOnRNTopo9 : https://discord.gg/zqcBffbMZn
--WKLeaksVeOncWTop8a : https://discord.gg/zqcBffbMZn
