--[[   -- https://discord.gg/zqcBffbMZn ]]
Version = "2.0.0"

function Lang(key)
    local lang = Config and Config.Languages and Config.Languages[Config.Language]
    if lang and lang[key] then
        return lang[key]
    end
    local en = Config and Config.Languages and Config.Languages.en
    if en and en[key] then
        return en[key]
    end
    return key
end

function WarnMissingItem(context, item)
    local itemName
    if type(item) == "table" then
        itemName = table.concat(item, ", ")
    else
        itemName = tostring(item)
    end
    print(string.format("^3[qs-fishingjob]^0 no such item in the inventory: %s (%s). Register the item or change the config.", itemName, context))
    return itemName
end

function HasSupportedInventory()
    for _, inventoryName in ipairs({ "ox_inventory", "qs-inventory" }) do
        local state = GetResourceState(inventoryName)
        if state:find("start") then
            return true
        end
    end
    return false
end

CreateThread(function()
    while GetResourceState(GetCurrentResourceName()) ~= "started" do
        Wait(100)
    end
    if Config.RegisterUsableItemsManually or not HasSupportedInventory() then
        RegisterUsableItems()
    end
end)

function SplitReward(amount, partyCount)
    local total = math.floor(tonumber(amount) or 0)
    if total <= 0 then
        return 0
    end
    if partyCount <= 1 then
        return total
    end
    return math.max(math.floor(total / partyCount), 1)
end

function PayForMission(source, mission, partySize)
    if not source or not mission then
        return
    end
    local count = math.max(math.floor(tonumber(partySize) or 1), 1)
    if Config.RequireJob and IsPlayerFisher and not IsPlayerFisher(source) then
        TriggerClientEvent("qs-fisher:sendNotification", source, "notify", "error", Lang("NOTIFY_NOT_FISHER"))
        return
    end
    local identifier = GetPlayeridentifier(source)
    if not identifier then
        return
    end
    local moneyAmount = SplitReward(mission.money, count)
    if moneyAmount > 0 then
        if GetResourceState("qs-job-management") == "started" then
            exports["qs-job-management"]:AddJobMoney(source, moneyAmount, "fisher")
        else
            AddMoney(source, moneyAmount)
        end
        AddEarnings(identifier, moneyAmount)
        if SendWebhook then
            SendWebhook("MoneyPaid", source, "Paid", mission.name or "Mission payout", {
                WebhookField("Amount", "$" .. moneyAmount),
                WebhookField("For", "Mission")
            })
        end
    end
    AddExperience(identifier, SplitReward(mission.experience, count), source)
    TriggerClientEvent("qs-fisher:sendNotification", source, "notify", "success", Lang("QUEST_FINISHED") .. FormatCurrency(moneyAmount))
    if Config.QuasarInventoryQuests then
        TellQuasarInventory("UpdateQuestProgress", source, "finish_fisher_quests", 5)
    end
end

local playerDutyStatus = {}

RegisterNetEvent("qs-fisher:setDutyStatus", function(status)
    local src = tostring(source)
    playerDutyStatus[src] = (status == true)
end)

AddEventHandler("playerDropped", function()
    local src = tostring(source)
    playerDutyStatus[src] = nil
end)

exports("getOnDutyCount", function()
    local count = 0
    for _, onDuty in pairs(playerDutyStatus) do
        if onDuty then
            count = count + 1
        end
    end
    return count
end)

exports("isPlayerOnDuty", function(source)
    local src = tostring(source)
    return playerDutyStatus[src] == true
end)

function ResolvePlayerName(source)
    local fallbackName = GetPlayerName(source) or ("Player " .. tostring(source))
    local sourceMode = Config.PlayerNameSource or "character"
    if sourceMode == "cfx" then
        return fallbackName
    end
    local characterName = nil
    if type(GetUserName) == "function" then
        local ok, name = pcall(GetUserName, source)
        if ok then
            characterName = name
        end
    end
    if characterName then
        characterName = characterName:gsub("^%s*(.-)%s*$", "%1")
    else
        characterName = ""
    end
    if characterName == "" or characterName == "Unknown" then
        return fallbackName
    end
    if sourceMode == "both" then
        return string.format("%s (%s)", characterName, fallbackName)
    end
    return characterName
end

lib.callback.register(GetCurrentResourceName() .. ":getPlayerDisplayName", function(source)
    return ResolvePlayerName(source)
end)
--WKLeak_TTOngJTopH8 : https://discord.gg/zqcBffbMZn
--WKLeak3@OnVoTopOZ : https://discord.gg/zqcBffbMZn
--WKLeak_yqOndVTopwd : https://discord.gg/zqcBffbMZn
--WKLeakD8OnmqToprF : https://discord.gg/zqcBffbMZn
--WKLeak-G5On@BTopvZ : https://discord.gg/zqcBffbMZn
