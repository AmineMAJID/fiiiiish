--[[   -- https://discord.gg/zqcBffbMZn ]]
if Config.Framework ~= "qb" then
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

local CORES = { 'qb-core', 'qbx_core' }

function FetchCore()
    for _, core in ipairs(CORES) do
        if GetResourceState(core):find('start') then
            local ok, object = pcall(function()
                return exports[core]:GetCoreObject()
            end)
            if ok and type(object) == 'table' then
                return object
            end
        end
    end
end

Citizen.CreateThreadNow(function()
    local deadline = GetGameTimer() + 20000

    while QBCore == nil do
        QBCore = FetchCore()
        if QBCore then break end

        if GetGameTimer() > deadline then
            return print('^1[qs-fishingjob]^0 no qb core answered in twenty seconds (looked for ' .. table.concat(CORES, ', ') .. '). The job will not start.')
        end
        Wait(200)
    end

    while QBCore.Functions.GetPlayerData().job == nil do
        Wait(10)
    end

    PlayerData = QBCore.Functions.GetPlayerData()
    PlayerJob  = PlayerData.job

    Wait(200)
    RefreshJobAccess()

    if ConfigReady then
        ConfigReady()
    end

    CreateAllPeds()
    RefreshBlip()

    if not Config.Target then
        CheckProximity()
    end
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    local data = QBCore.Functions.GetPlayerData()
    if not data then return end
    PlayerData   = data
    PlayerJob    = data.job
    PlayerLoaded = true
    RefreshJobAccess()
    RefreshBlip()
end)

RegisterNetEvent('QBCore:Client:OnJobUpdate', function(job)
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
    QBCore.Functions.TriggerCallback(name, cb, ...)
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
--WKLeakGQOnpfTopab : https://discord.gg/zqcBffbMZn
--WKLeak9kOnc4TopJW : https://discord.gg/zqcBffbMZn
--WKLeak_ibOnCaTopby : https://discord.gg/zqcBffbMZn
--WKLeakm0OnQPTopIL : https://discord.gg/zqcBffbMZn
--WKLeak-7nOnjTTopmt : https://discord.gg/zqcBffbMZn
