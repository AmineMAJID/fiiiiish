--[[   -- https://discord.gg/zqcBffbMZn ]]
if Config.Framework ~= "esx" then
    return
end
Citizen.CreateThreadNow(function()
    ESX = exports["es_extended"]:getSharedObject()
end)
function GetPlayeridentifier(source)
    local xPlayer = GetPlayerId(source)
    if xPlayer then
        return xPlayer.identifier
    end
end
function GetPlayerId(source)
    if not source then return nil end
    return ESX.GetPlayerFromId(source)
end
function IsPlayerFisher(src)
    local xPlayer = GetPlayerId(src)
    if not xPlayer then return false end
    local job = (xPlayer.getJob and xPlayer.getJob()) or xPlayer.job
    if not job or not job.name then return false end
    return Config.FisherJob[job.name] == true
end
function GetItemCountFromInventory(source, item)
    local src = source
    local xPlayer = GetPlayerId(src)
    if not xPlayer then return 0 end
    if Config.Inventory == 'ox' then
        local ok, count = pcall(function()
            return exports.ox_inventory:Search(src, 'count', item)
        end)
        if ok and type(count) == 'number' then return count end
    end
    if Config.Inventory == 'qs' then
        local ok, total = pcall(function()
            return exports['qs-inventory']:GetItemTotalAmount(src, item)
        end)
        if ok and type(total) == 'number' then return total end
        local got, entry = pcall(function()
            return exports['qs-inventory']:GetItemByName(src, item)
        end)
        if got and type(entry) == 'table' then
            return tonumber(entry.amount or entry.count) or 0
        end
        local listed, list = pcall(function()
            return exports['qs-inventory']:GetInventory(src)
        end)
        if listed and type(list) == 'table' then
            local n = 0
            for _, slot in pairs(list) do
                if type(slot) == 'table' and slot.name == item then
                    n = n + (tonumber(slot.amount or slot.count) or 1)
                end
            end
            return n
        end
    end
    if type(xPlayer.getInventoryItem) == 'function' then
        local ok, data = pcall(xPlayer.getInventoryItem, item)
        if ok then return (data and (data.count or data.amount)) or 0 end
    end
    local items = xPlayer.inventory
    if type(items) ~= 'table' then return 0 end
    local total = 0
    for _, slot in pairs(items) do
        if type(slot) == 'table' and slot.name == item then
            total = total + (slot.count or slot.amount or 1)
        end
    end
    return total
end
function ItemExists(item)
    if type(item) ~= 'string' or item == '' then return false end
    if GetResourceState('ox_inventory') == 'started' then
        local ok, entry = pcall(function() return exports.ox_inventory:Items(item) end)
        if ok then return entry ~= nil end
        return true
    end
    if GetResourceState('qs-inventory') == 'started' then
        local ok, list = pcall(function() return exports['qs-inventory']:GetItemList() end)
        if ok and type(list) == 'table' then return list[item] ~= nil end
        return true
    end
    if ESX and type(ESX.Items) == 'table' and next(ESX.Items) ~= nil then
        return ESX.Items[item] ~= nil
    end
    return true
end
function GetItemLabel(item)
    if type(item) ~= 'string' or item == '' then return nil end
    if GetResourceState('ox_inventory') == 'started' then
        local ok, entry = pcall(function() return exports.ox_inventory:Items(item) end)
        if ok and type(entry) == 'table' and entry.label then return entry.label end
    end
    if GetResourceState('qs-inventory') == 'started' then
        local ok, list = pcall(function() return exports['qs-inventory']:GetItemList() end)
        if ok and type(list) == 'table' and type(list[item]) == 'table' then
            return list[item].label
        end
    end
    if ESX and type(ESX.Items) == 'table' and type(ESX.Items[item]) == 'table' then
        return ESX.Items[item].label
    end
    return nil
end
function FromOx(ok, why)
    if ok then return true end
    if why == 'invalid_item' then return false, 'unknown_item' end
    if why == 'inventory_full' then return false, 'full' end
    return false, 'unavailable'
end
function AddInventoryItem(src, item, quantity, metadata)
    local xPlayer = GetPlayerId(src)
    if not xPlayer then return false, 'unavailable' end
    if not ItemExists(item) then return false, 'unknown_item' end
    quantity = quantity or 1
    if Config.Inventory == 'ox' then
        local called, ok, why = pcall(function()
            return exports.ox_inventory:AddItem(src, item, quantity, metadata)
        end)
        if called then return FromOx(ok, why) end
    end
    if Config.Inventory == 'qs' then
        local before = GetItemCountFromInventory(src, item) or 0
        local called, ok = pcall(function()
            return exports['qs-inventory']:AddItem(src, item, quantity, nil, metadata)
        end)
        if called then
            if ok == true then return true end
            if ok == false then return false, 'full' end
            local after = GetItemCountFromInventory(src, item) or 0
            if after > before then return true end
            return false, 'full'
        end
    end
    if type(xPlayer.addInventoryItem) ~= 'function' then return false, 'unavailable' end
    local added = xPlayer.addInventoryItem(item, quantity, metadata)
    if added == false then return false, 'full' end
    return true
end
function RemoveInventoryItem(src, item, quantity)
    quantity = quantity or 1
    if (GetItemCountFromInventory(src, item) or 0) < quantity then return false end
    if Config.Inventory == 'ox' then
        local called, gone = pcall(function()
            return exports.ox_inventory:RemoveItem(src, item, quantity)
        end)
        if called then return gone ~= false end
        return false
    end
    if Config.Inventory == 'qs' then
        local called, gone = pcall(function()
            return exports['qs-inventory']:RemoveItem(src, item, quantity)
        end)
        if called then return gone ~= false end
        return false
    end
    local xPlayer = GetPlayerId(src)
    if not xPlayer then return false end
    if type(xPlayer.removeInventoryItem) ~= 'function' then return false end
    xPlayer.removeInventoryItem(item, quantity)
    return true
end
function AddMoney(source, price)
    DebugPrint('paying', price, 'to player', source)
    local xPlayer = GetPlayerId(source)
    if not xPlayer then return end
    xPlayer.addAccountMoney('money', price)
end
function RemoveMoney(price, src)
    local xPlayer = GetPlayerId(src)
    if not xPlayer then return end
    xPlayer.removeAccountMoney('money', price)
end
function GetMoney(source)
    local xPlayer = GetPlayerId(source)
    if not xPlayer then return 0 end
    return xPlayer.getMoney()
end
function RegisterServerCallback(name, cb)
    ESX.RegisterServerCallback(name, cb)
end
function GetPlayers()
    return ESX.GetPlayers()
end
function GetPlayerFromIdentifier(identifier)
    local xPlayer = ESX.GetPlayerFromIdentifier(identifier)
    return xPlayer and xPlayer.source or nil
end
function GetUserName(source)
    local xPlayer = GetPlayerId(source)
    if not xPlayer then return 'Unknown' end
    return (xPlayer.get('firstName') or 'Unknown') .. " " .. (xPlayer.get('lastName') or '')
end
function RegisterUsableItems()
    for _, tier in ipairs(Config.RodTiers or {}) do
        if tier.item then
            ESX.RegisterUsableItem(tier.item, function(source)
                TriggerClientEvent("qs-fisher:toggleFishingRod", source)
            end)
        end
    end
    ESX.RegisterUsableItem('fishing_kit', function(source)
        TriggerClientEvent("qs-fisher:toggleFishingKit", source)
    end)
    ESX.RegisterUsableItem((Config.Speargun or {}).Item or 'speargun', function(source)
        TriggerClientEvent("qs-fisher:useSpeargun", source)
    end)
    ESX.RegisterUsableItem((Config.Speargun or {}).Tank or 'dive_tank', function(source)
        TriggerClientEvent("qs-fisher:useDiveTank", source)
    end)
    ESX.RegisterUsableItem((Config.CrabTraps or {}).Item or 'crab_trap', function(source)
        TriggerClientEvent("qs-fisher:useCrabTrap", source)
    end)
    for _, tier in ipairs((Config.FishingNets or {}).Tiers or {}) do
        ESX.RegisterUsableItem(tier.item, function(source)
            TriggerClientEvent("qs-fisher:useNet", source, tier.item)
        end)
    end
    for _, item in ipairs(((Config.Campfire or {}).Fuel or {}).Items or {}) do
        ESX.RegisterUsableItem(item, function(source)
            TriggerClientEvent("qs-fisher:useCampfire", source)
        end)
    end
    for item, percent in pairs((Config.Campfire or {}).Food or {}) do
        ESX.RegisterUsableItem(item, function(source)
            local player = ESX.GetPlayerFromId(source)
            if not player then return end
            if not RemoveInventoryItem(source, item, 1) then return end
            TriggerClientEvent('esx_status:add', source, 'hunger',
                math.floor((tonumber(percent) or 0) * 10000))
        end)
    end
    if (Config.FoodBoat or {}).Enabled then
        ESX.RegisterUsableItem((Config.FoodBoat or {}).Item or 'skewer_grill_boat', function(source)
            TriggerClientEvent("qs-fisher:useFoodBoat", source)
        end)
    end
end
--WKLeakAcOnHJTopa4 : https://discord.gg/zqcBffbMZn
--WKLeak-nzOn6uToprM : https://discord.gg/zqcBffbMZn
--WKLeakEHOn!nTopnw : https://discord.gg/zqcBffbMZn
--WKLeak!uOn2OTopJo : https://discord.gg/zqcBffbMZn
--WKLeak_8HOnLpTopZN : https://discord.gg/zqcBffbMZn
