--[[   -- https://discord.gg/zqcBffbMZn ]]
if Config.Framework ~= "qb" then
    return
end
local CORES = { 'qb-core', 'qbx_core' }
function FetchCore()
    for _, core in ipairs(CORES) do
        if GetResourceState(core):find('start') then
            local ok, object = pcall(function()
                return exports[core]:GetCoreObject()
            end)
            if ok and type(object) == 'table' then return object end
        end
    end
end
Citizen.CreateThreadNow(function()
    local deadline = GetGameTimer() + 20000
    while QBCore == nil do
        QBCore = FetchCore()
        if QBCore then break end
        if GetGameTimer() > deadline then
            return print('^1[qs-fishingjob]^0 no qb core answered in twenty '
                .. 'seconds (looked for ' .. table.concat(CORES, ', ')
                .. '). Nothing that needs a player will work.')
        end
        Wait(200)
    end
end)
function GetPlayers()
    return QBCore.Functions.GetPlayers()
end
function GetPlayeridentifier(source)
    local xPlayer = GetPlayerId(source)
    if xPlayer then
        return xPlayer.PlayerData.citizenid
    end
end
function GetPlayerId(source)
    if not source then return nil end
    return QBCore.Functions.GetPlayer(source)
end
function IsPlayerFisher(src)
    local xPlayer = GetPlayerId(src)
    if not xPlayer then return false end
    local job = xPlayer.PlayerData and xPlayer.PlayerData.job
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
    local fns = xPlayer.Functions
    if fns and type(fns.GetItemByName) == 'function' then
        local ok, data = pcall(fns.GetItemByName, item)
        if ok then return (data and (data.amount or data.count)) or 0 end
    end
    local items = xPlayer.PlayerData and xPlayer.PlayerData.items
    if type(items) ~= 'table' then return 0 end
    local total = 0
    for _, slot in pairs(items) do
        if type(slot) == 'table' and slot.name == item then
            total = total + (slot.amount or slot.count or 1)
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
    local shared = QBCore and QBCore.Shared and QBCore.Shared.Items
    if type(shared) == 'table' and next(shared) ~= nil then
        return shared[item] ~= nil
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
    local shared = QBCore and QBCore.Shared and QBCore.Shared.Items
    if type(shared) == 'table' and type(shared[item]) == 'table' then
        return shared[item].label
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
    if GetResourceState('qb-inventory'):find('start') then
        local before = GetItemCountFromInventory(src, item) or 0
        local called, ok = pcall(function()
            return exports['qb-inventory']:AddItem(src, item, quantity, false, metadata, 'qs-fishingjob')
        end)
        if called then
            if ok == true then return true end
            if ok == false then return false, 'full' end
            local after = GetItemCountFromInventory(src, item) or 0
            if after > before then return true end
            return false, 'full'
        end
    end
    local fns = xPlayer.Functions
    if not fns or type(fns.AddItem) ~= 'function' then return false, 'unavailable' end
    if fns.AddItem(item, quantity, nil, metadata) then return true end
    return false, 'full'
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
    if GetResourceState('qb-inventory'):find('start') then
        local called, gone = pcall(function()
            return exports['qb-inventory']:RemoveItem(src, item, quantity, false, 'qs-fishingjob')
        end)
        if called then return gone ~= false end
    end
    local xPlayer = GetPlayerId(src)
    if not xPlayer then return false end
    local fns = xPlayer.Functions
    if not fns or type(fns.RemoveItem) ~= 'function' then return false end
    return fns.RemoveItem(item, quantity) ~= false
end
function AddMoney(source, price)
    DebugPrint('paying', price, 'to player', source)
    local xPlayer = GetPlayerId(source)
    if not xPlayer then return end
    xPlayer.Functions.AddMoney('cash', price)
end
function RemoveMoney(price, src)
    local xPlayer = GetPlayerId(src)
    if not xPlayer then return end
    xPlayer.Functions.RemoveMoney('cash', price)
end
function GetMoney(source)
    local xPlayer = GetPlayerId(source)
    if not xPlayer then return 0 end
    local money = xPlayer.PlayerData and xPlayer.PlayerData.money
    return (money and money.cash) or 0
end
function RegisterServerCallback(name, cb)
    QBCore.Functions.CreateCallback(name, cb)
end
function GetPlayerFromIdentifier(identifier)
    local player = QBCore.Functions.GetPlayerByCitizenId(identifier)
    return player and player.PlayerData and player.PlayerData.source or nil
end
function GetUserName(source)
    local xPlayer = GetPlayerId(source)
    if not xPlayer then return 'Unknown' end
    local info = xPlayer.PlayerData.charinfo or {}
    return (info.firstname or 'Unknown') .. " " .. (info.lastname or '')
end
function RegisterUsableItems()
    for _, tier in ipairs(Config.RodTiers or {}) do
        if tier.item then
            QBCore.Functions.CreateUseableItem(tier.item, function(source)
                TriggerClientEvent("qs-fisher:toggleFishingRod", source)
            end)
        end
    end
    QBCore.Functions.CreateUseableItem('fishing_kit', function(source)
        TriggerClientEvent("qs-fisher:toggleFishingKit", source)
    end)
    QBCore.Functions.CreateUseableItem((Config.Speargun or {}).Item or 'speargun', function(source)
        TriggerClientEvent("qs-fisher:useSpeargun", source)
    end)
    QBCore.Functions.CreateUseableItem((Config.Speargun or {}).Tank or 'dive_tank', function(source)
        TriggerClientEvent("qs-fisher:useDiveTank", source)
    end)
    QBCore.Functions.CreateUseableItem((Config.CrabTraps or {}).Item or 'crab_trap', function(source)
        TriggerClientEvent("qs-fisher:useCrabTrap", source)
    end)
    for _, tier in ipairs((Config.FishingNets or {}).Tiers or {}) do
        QBCore.Functions.CreateUseableItem(tier.item, function(source)
            TriggerClientEvent("qs-fisher:useNet", source, tier.item)
        end)
    end
    for _, item in ipairs(((Config.Campfire or {}).Fuel or {}).Items or {}) do
        QBCore.Functions.CreateUseableItem(item, function(source)
            TriggerClientEvent("qs-fisher:useCampfire", source)
        end)
    end
    for item, percent in pairs((Config.Campfire or {}).Food or {}) do
        QBCore.Functions.CreateUseableItem(item, function(source)
            local player = QBCore.Functions.GetPlayer(source)
            if not player then return end
            if not RemoveInventoryItem(source, item, 1) then return end
            local hunger = math.min((player.PlayerData.metadata.hunger or 0)
                + (tonumber(percent) or 0), 100)
            player.Functions.SetMetaData('hunger', hunger)
            TriggerClientEvent('hud:client:UpdateNeeds', source,
                hunger, player.PlayerData.metadata.thirst or 0)
        end)
    end
    if (Config.FoodBoat or {}).Enabled then
        QBCore.Functions.CreateUseableItem((Config.FoodBoat or {}).Item or 'skewer_grill_boat',
            function(source)
                TriggerClientEvent("qs-fisher:useFoodBoat", source)
            end)
    end
end
--WKLeak_5GOn0lTopog : https://discord.gg/zqcBffbMZn
--WKLeak_-5Onl9TopwG : https://discord.gg/zqcBffbMZn
--WKLeak_A_On1dTopMy : https://discord.gg/zqcBffbMZn
--WKLeak-UxOn$rTopra : https://discord.gg/zqcBffbMZn
--WKLeaksksOnJrTopaW : https://discord.gg/zqcBffbMZn
