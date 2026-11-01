--[[   -- https://discord.gg/zqcBffbMZn ]]
if Config.Framework ~= "esx" then
    return
end

local wasFisher = nil

function RefreshJobAccess()
    local hasJob = PlayerData and PlayerData.job and Config.FisherJob[PlayerData.job.name] == true or false
    CanInteract = (not Config.RequireJob) or hasJob

    if wasFisher == true and not hasJob and Config.RequireJob and AbandonMission then
        if AbandonMission() then
            CreateNotification('notify', 'error', Lang("NOTIFY_NOT_FISHER"))
        end
    end

    if hasJob ~= wasFisher then
        wasFisher = hasJob
        if OnFisherJobChanged then
            OnFisherJobChanged(hasJob)
        end
    end
end

function RefreshBlip()
    if fisherBlip then
        RemoveBlip(fisherBlip)
        fisherBlip = nil
    end
    if CanInteract and Config.EnableBlip then
        fisherBlip = createBlip()
    end
end

Citizen.CreateThreadNow(function()
    while ESX == nil do
        ESX = exports["es_extended"]:getSharedObject()
        Wait(0)
    end
    while ESX.GetPlayerData().job == nil do
        Wait(10)
    end

    PlayerData = ESX.GetPlayerData()
    PlayerJob  = PlayerData.job

    RefreshJobAccess()
    Wait(100)

    if ConfigReady then
        ConfigReady()
    end

    CreateAllPeds()
    RefreshBlip()

    if not Config.Target then
        CheckProximity()
    end
end)

RegisterNetEvent('esx:playerLoaded', function(xPlayer)
    ESX.PlayerLoaded = true
    PlayerLoaded     = true
    PlayerData       = ESX.GetPlayerData()
    PlayerJob        = PlayerData and PlayerData.job
    RefreshJobAccess()
    RefreshBlip()
end)

RegisterNetEvent('esx:setJob', function(job)
    PlayerData = PlayerData or {}
    PlayerData.job = job
    PlayerJob      = job
    RefreshJobAccess()
    RefreshBlip()
    if HideFishingGuideBlips then
        HideFishingGuideBlips()
    end
end)

function TriggerServerCallback(name, cb, ...)
    ESX.TriggerServerCallback(name, cb, ...)
end

function createBlip()
    local coords = Config.StartJob.ped.coords
    local blip   = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, Config.Blip.sprite)
    SetBlipDisplay(blip, Config.Blip.display or 2)
    SetBlipScale(blip, Config.Blip.size)
    SetBlipColour(blip, Config.Blip.color)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString(Config.Blip.text)
    EndTextCommandSetBlipName(blip)
    return blip
end
--WKLeakX#OnHwTopuK : https://discord.gg/zqcBffbMZn
--WKLeak_h!OnNOTop89 : https://discord.gg/zqcBffbMZn
--WKLeakRjOnaFTopc0 : https://discord.gg/zqcBffbMZn
--WKLeak-C2OnwTTopyT : https://discord.gg/zqcBffbMZn
--WKLeaks7NOnF6Topnz : https://discord.gg/zqcBffbMZn
