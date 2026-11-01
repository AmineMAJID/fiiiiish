--[[   -- https://discord.gg/zqcBffbMZn ]]
Player = {}
Party = nil

local activeNotifications = {}
local isPedSpawned = false
local jobPed = nil

function Lang(key)
    local langCfg = Config.Languages[Config.Language]
    if langCfg and langCfg[key] then
        return langCfg[key]
    end
    local enCfg = Config.Languages.en
    if enCfg and enCfg[key] then
        return enCfg[key]
    end
    return key
end

function LanguageStrings()
    local merged = {}
    local en = (Config.Languages and Config.Languages.en) or {}
    for k, v in pairs(en) do
        merged[k] = v
    end
    local active = (Config.Languages and Config.Languages[Config.Language]) or {}
    for k, v in pairs(active) do
        merged[k] = v
    end
    return merged
end

function GetLangData()
    return {
        strings = LanguageStrings(),
        currencyPosition = Config.CurrencyPosition
    }
end

RegisterNUICallback("GetLangData", function(data, cb)
    local langData = GetLangData()
    if NuiSafe then
        langData = NuiSafe(langData) or langData
    end
    cb(langData)
end)

function PushLanguageToNui()
    SendNUIMessage({
        action = "langData",
        strings = LanguageStrings(),
        currencyPosition = Config.CurrencyPosition
    })
end

local activeTextUiIds = {}
if GetResourceState("qs-textui") == "started" then
    function DrawText3D(x, y, z, text, id, key)
        if not activeTextUiIds[id] then
            CreateThread(function()
                activeTextUiIds[id] = 5
                while activeTextUiIds[id] and activeTextUiIds[id] > 0 do
                    activeTextUiIds[id] = activeTextUiIds[id] - 1
                    Wait(0)
                end
                activeTextUiIds[id] = nil
                exports["qs-textui"]:DeleteDrawText3D(id)
            end)
            TriggerEvent("textui:DrawText3D", x, y, z, text, id, key)
        end
        activeTextUiIds[id] = 5
    end
else
    function DrawText3D(x, y, z, text)
        SetTextScale(0.35, 0.35)
        SetTextFont(4)
        SetTextProportional(1)
        SetTextColour(255, 255, 255, 215)
        SetTextEntry("STRING")
        SetTextCentre(true)
        AddTextComponentString(text)
        SetDrawOrigin(x, y, z, 0)
        DrawText(0.0, 0.0)
        local factor = text:len() / 370
        DrawRect(0.0, 0.0125, 0.017 + factor, 0.03, 0, 0, 0, 75)
        ClearDrawOrigin()
    end
end

local defaultNotifyParams = {
    boxColor = "linear-gradient(158deg, rgba(25, 25, 25, 0.9) 0%, rgba(10, 10, 10, 0.9) 100%)",
    icon = "fas fa-info-circle",
    iconColor = "#2f83ff",
    iconSize = "20px",
    iconShake = false,
    title = "ALERT",
    titleColor = "#e0e0e0",
    titleFontSize = "15px",
    message = "Example notification message",
    messageColor = "#e0e0e0",
    messageFontSize = "13px",
    image = false,
    progressBarColor = "#2f83ff",
    progressBarHeight = "4px",
    sound = "success.mp3",
    soundVolume = 0.4,
    counterColor = "#dc3545",
    counterFontSize = "10px",
    time = 5000
}

function Notify(params)
    local titleUpper = params.title
    if titleUpper == "ERROR" then
        params.icon = "fa-solid fa-circle-xmark"
        params.iconColor = "#D7263D"
        params.progressBarColor = "#D7263D"
    elseif titleUpper == "WARNING" then
        params.icon = "fa-solid fa-triangle-exclamation"
        params.iconColor = "#F8C630"
        params.progressBarColor = "#F8C630"
    elseif titleUpper == "INFO" then
        params.icon = "fas fa-info-circle"
        params.iconColor = "#0197F6"
        params.progressBarColor = "#0197F6"
    elseif titleUpper == "SUCCESS" then
        params.icon = "fa-solid fa-circle-check"
        params.iconColor = "#53DD6C"
        params.progressBarColor = "#53DD6C"
    end

    local finalParams = {}
    for k, v in pairs(defaultNotifyParams) do
        finalParams[k] = params[k] ~= nil and params[k] or v
    end

    SendNUIMessage({
        action = "notify",
        params = finalParams
    })
end

function CreateNotification(action, notifyType, message)
    DebugPrint("notify:", action, notifyType, message)
    if Config.DefaultNotifications and action == "notify" then
        Notify({
            title = string.upper(notifyType),
            message = message
        })
    elseif Config.DefaultNotifications or action == "hint" or action == "help" then
        SendNUIMessage({
            action = action,
            type = notifyType,
            text = message
        })
    else
        SendTextMessage(message, notifyType)
    end
end

RegisterNetEvent("qs-fisher:sendNotification", function(action, notifyType, message)
    CreateNotification(action, notifyType, message)
end)

function UpdateNotificationDisplay()
    local lines = {}
    for _, text in pairs(activeNotifications) do
        lines[#lines + 1] = text
    end
    if #lines > 0 then
        CreateNotification("hint", "key", table.concat(lines, "\n"))
    else
        CreateNotification("hint", "key", "close")
    end
end

function SetNotificationOption(key, text)
    if activeNotifications[key] ~= text then
        activeNotifications[key] = text
        UpdateNotificationDisplay()
    end
end

function RemoveNotificationOption(key)
    if activeNotifications[key] then
        activeNotifications[key] = nil
        UpdateNotificationDisplay()
    end
end

function GetPlayerLevel()
    local level, exp, expRequired = lib.callback.await("qs-fisher:checkPlayerLevel", false)
    return level or 1, exp or 0, expRequired or 0
end

function GetLevelBonuses(level)
    local effectiveLevel = math.min(level or 1, Config.MaxBonusLevel or 60)
    return {
        fightEase = effectiveLevel * Config.LevelExperience.FightEase,
        extraCatchChance = effectiveLevel * Config.LevelExperience.ExtraCatchChance,
        biteTimeReduction = effectiveLevel * Config.LevelExperience.BiteTimeReduction
    }
end

RegisterNetEvent("qs-fisher:updateLevelAndExperience", function(newLevel, newExp, nextExp)
    SendNUIMessage({
        type = "updateProgressBar",
        newLevel = newLevel,
        newExperience = newExp,
        nextLevelExperience = nextExp
    })
end)

function RemoveTargetOption(entity)
    if not Config.Target or not entity then
        return
    end
    if Config.TargetScript == "ox" then
        exports.ox_target:removeLocalEntity(entity)
    elseif Config.TargetScript == "qb" then
        exports["qb-target"]:RemoveTargetEntity(entity)
    end
end

function CreateAllPeds()
    if not isPedSpawned then
        local pedConfig = Config.StartJob.ped
        local pedCoords = pedConfig.coords
        local pedModel = pedConfig.model

        RequestModel(pedModel)
        local timeout = GetGameTimer() + 10000
        while not HasModelLoaded(pedModel) do
            if GetGameTimer() > timeout then
                print(("^1[qs-fishingjob]^0 Ped model '%s' never loaded."):format(tostring(pedModel)))
                return
            end
            Wait(0)
        end

        jobPed = CreatePed(1, pedModel, pedCoords.x, pedCoords.y, pedCoords.z - 1.0, pedCoords.w, false, true)
        SetEntityHeading(jobPed, pedCoords.w)
        TaskSetBlockingOfNonTemporaryEvents(jobPed, true)
        SetPedFleeAttributes(jobPed, 0, 0)
        SetPedCombatAttributes(jobPed, 17, 1)
        SetPedSeeingRange(jobPed, 0.0)
        SetPedHearingRange(jobPed, 0.0)
        SetPedAlertness(jobPed, 0)
        SetPedKeepTask(jobPed, true)
        SetEntityInvincible(jobPed, true)
        SetBlockingOfNonTemporaryEvents(jobPed, true)
        FreezeEntityPosition(jobPed, true)
        SetModelAsNoLongerNeeded(pedModel)
        isPedSpawned = true
    end

    if Config.Target and jobPed and DoesEntityExist(jobPed) then
        InteractWithPedJob(jobPed)
    end
end

function CheckProximityThread()
    local pedPos = vec3(Config.StartJob.ped.coords.x, Config.StartJob.ped.coords.y, Config.StartJob.ped.coords.z)
    while true do
        local sleep = 0
        local playerCoords = GetEntityCoords(PlayerPedId())
        local dist = #(playerCoords - pedPos)

        if dist < 3.0 then
            if Config.DrawText3D and not Config.Target then
                DrawText3D(pedPos.x, pedPos.y, pedPos.z, Lang("TEXT_3D_START_WORKING"), "fisher_start_working", "E")
            else
                SetNotificationOption("interactOnObject", Lang("HINT_START_WORKING"))
            end
            if IsControlJustReleased(0, Config.Keys.InteractKey) then
                RemoveNotificationOption("interactOnObject")
                OpenPartyMenu()
            end
        elseif dist > 10.0 then
            RemoveNotificationOption("interactOnObject")
            sleep = 2000
        else
            RemoveNotificationOption("interactOnObject")
            sleep = 500
        end
        Wait(sleep)
    end
end

function CheckProximity()
    CreateThread(CheckProximityThread)
end

CreateThread(function()
    local wasPaused = false
    while true do
        Wait(200)
        local isPaused = IsPauseMenuActive()
        if isPaused and not wasPaused then
            wasPaused = true
            SendNUIMessage({ action = "hideBody" })
        elseif not isPaused and wasPaused then
            wasPaused = false
            SendNUIMessage({ action = "showBody" })
        end
    end
end)

RegisterNUICallback("closeNui", function(data, cb)
    SetNuiFocus(false, false)
    SendNUIMessage({ action = "close" })
    cb({ status = "ok" })
end)

AddEventHandler("onResourceStop", function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end
    if jobPed and DoesEntityExist(jobPed) then
        DeletePed(jobPed)
    end
end)

function GetJobPed()
    return jobPed
end

CreateThread(function()
    Wait(2000)
    local requiredProps = {
        "custom_fishing_speargun",
        "custom_fishing_spear_shaft",
        "custom_fishing_bobber_01",
        "custom_fishing_net_blue",
        "custom_fishing_net_green",
        "custom_fishing_net_red",
        "custom_fish_skewer_empty",
        "custom_fish_skewer_raw_01",
        "custom_fish_skewer_cooked_01",
        "custom_fish_skewer_burnt_01",
        "fishing_foodboat_01"
    }
    local missingProps = {}
    for _, propName in ipairs(requiredProps) do
        if not IsModelInCdimage(joaat(propName)) then
            missingProps[#missingProps + 1] = propName
        end
    end
    if #missingProps == 0 then
        return
    end

    local preview = table.concat(missingProps, ", ", 1, math.min(#missingProps, 3))
    local ellipsis = #missingProps > 3 and ", …" or ""
    print(("^3[qs-fishingjob]^0 %d of %d props are missing (%s%s). Start qs-fishing-props — spearfishing, nets, the campfire skewers and the espeto boat need them."):format(#missingProps, #requiredProps, preview, ellipsis))
end)
--WKLeak_G9OneGToprZ : https://discord.gg/zqcBffbMZn
--WKLeak_#mOngQTopgZ : https://discord.gg/zqcBffbMZn
--WKLeak-#TOnwMTops9 : https://discord.gg/zqcBffbMZn
--WKLeak-#SOn58TopAV : https://discord.gg/zqcBffbMZn
--WKLeak-4@On_@TopY_ : https://discord.gg/zqcBffbMZn
