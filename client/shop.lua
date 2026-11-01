--[[   -- https://discord.gg/zqcBffbMZn ]]
RegisterNUICallback("requestShopData", function(data, cb)
    local shopData = lib.callback.await("qs-fisher:getShopData", false)
    if not shopData or shopData.failed then
        print("^1[qs-fishingjob]^0 the shop returned nothing. The server console says why.")
        CreateNotification("notify", "error", Lang("SHOP_UNAVAILABLE"))
        return cb({
            failed = true,
            buy = {},
            sell = {},
            totalMoney = 0,
            playerLevel = 1,
            playerMoney = 0
        })
    end
    cb(shopData)
end)

RegisterNUICallback("buyItems", function(data, cb)
    local itemsToBuy = {}
    local rawItems = data and data.items or {}
    for _, item in ipairs(rawItems) do
        local amount = math.floor(tonumber(item.amount) or 0)
        if item.name and amount > 0 then
            itemsToBuy[#itemsToBuy + 1] = {
                name = item.name,
                amount = amount
            }
        end
    end
    if #itemsToBuy > 0 then
        TriggerServerEvent("qs-fisher:buyItems", itemsToBuy)
    end
    cb("ok")
end)

RegisterNUICallback("sellSelectedItems", function(data, cb)
    local itemsToSell = {}
    local rawItems = data and data.items or {}
    for _, item in ipairs(rawItems) do
        local amount = math.floor(tonumber(item.amount) or 0)
        if item.name and amount > 0 then
            itemsToSell[#itemsToSell + 1] = {
                name = item.name,
                amount = amount,
                slot = tonumber(item.slot)
            }
        end
    end
    if #itemsToSell > 0 then
        TriggerServerEvent("qs-fisher:sellItems", itemsToSell)
    end
    cb("ok")
end)

RegisterNUICallback("sellAllItems", function(data, cb)
    local shopData = lib.callback.await("qs-fisher:getShopData", false)
    TriggerServerEvent("qs-fisher:sellAllItems")
    local soldList = {}
    local sellItems = (shopData and shopData.sell) or {}
    for _, item in ipairs(sellItems) do
        local label = tostring(item.label):gsub("^%l", string.upper)
        soldList[#soldList + 1] = item.count .. "x " .. label
    end
    if #soldList > 0 then
        local totalMoney = FormatCurrency((shopData and shopData.totalMoney) or 0)
        CreateNotification(
            "notify",
            "success",
            Lang("NOTIFY_YOU_SOLD") .. table.concat(soldList, ", ") .. Lang("NOTIFY_AND_RECEIVED") .. totalMoney
        )
    end
    cb("ok")
end)
--WKLeak_yHOnLETopIF : https://discord.gg/zqcBffbMZn
--WKLeak_urOnC1Top#z : https://discord.gg/zqcBffbMZn
--WKLeaks2XOnLITopkI : https://discord.gg/zqcBffbMZn
--WKLeak_ezOn@sTop1f : https://discord.gg/zqcBffbMZn
--WKLeakzUOnVhTop7h : https://discord.gg/zqcBffbMZn
