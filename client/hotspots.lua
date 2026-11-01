--[[   -- https://discord.gg/zqcBffbMZn ]]
local activeHotspot = nil
local hotspotBlip = nil
local radiusBlip = nil
local isInsideHotspot = false
local isEligible = true

function ClearHotspotBlips()
    if hotspotBlip and DoesBlipExist(hotspotBlip) then
        RemoveBlip(hotspotBlip)
    end
    if radiusBlip and DoesBlipExist(radiusBlip) then
        RemoveBlip(radiusBlip)
    end
    hotspotBlip = nil
    radiusBlip = nil
end

function SetupHotspotBlips(hotspotData)
    ClearHotspotBlips()
    if not hotspotData or not hotspotData.coords then
        return
    end
    local blipConfig = hotspotData.blip or {}
    radiusBlip = AddBlipForRadius(hotspotData.coords.x, hotspotData.coords.y, hotspotData.coords.z, hotspotData.radius or 150.0)
    SetBlipColour(radiusBlip, blipConfig.color or 5)
    SetBlipAlpha(radiusBlip, blipConfig.alpha or 128)

    hotspotBlip = AddBlipForCoord(hotspotData.coords.x, hotspotData.coords.y, hotspotData.coords.z)
    SetBlipSprite(hotspotBlip, blipConfig.sprite or 304)
    SetBlipColour(hotspotBlip, blipConfig.color or 5)
    SetBlipScale(hotspotBlip, blipConfig.scale or 1.0)
    SetBlipAsShortRange(hotspotBlip, false)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString(string.format("%s — %s", Lang("HOTSPOT"), hotspotData.zone or "?"))
    EndTextCommandSetBlipName(hotspotBlip)
end

function UpdateHotspotUI()
    if not activeHotspot or not isInsideHotspot then
        return SendNUIMessage({ action = "hotspot", show = false })
    end
    local remaining = math.max((activeHotspot.endsAt or 0) - (GetGameTimer() / 1000), 0)
    SendNUIMessage({
        action = "hotspot",
        show = true,
        zone = activeHotspot.zone,
        seconds = remaining
    })
end

function ResetHotspot()
    activeHotspot = nil
    isInsideHotspot = false
    ClearHotspotBlips()
    SendNUIMessage({ action = "hotspot", show = false })
end

function SetActiveHotspot(hotspotData)
    activeHotspot = hotspotData
    activeHotspot.endsAt = (GetGameTimer() / 1000) + (hotspotData.seconds or 0)
    SetupHotspotBlips(hotspotData)
    isInsideHotspot = false
end

CreateThread(function()
    while true do
        if not activeHotspot then
            Wait(1000)
        else
            local playerCoords = GetEntityCoords(PlayerPedId())
            local dx = playerCoords.x - activeHotspot.coords.x
            local dy = playerCoords.y - activeHotspot.coords.y
            local inside = (dx * dx + dy * dy) <= (activeHotspot.radius * activeHotspot.radius)
            if inside ~= isInsideHotspot then
                isInsideHotspot = inside
                UpdateHotspotUI()
            end
            Wait(500)
        end
    end
end)

CreateThread(function()
    while true do
        Wait(15000)
        if activeHotspot and isInsideHotspot then
            UpdateHotspotUI()
        end
    end
end)

RegisterNetEvent("qs-fisher:hotspotStarted", function(hotspotData)
    if not isEligible then
        return
    end
    SetActiveHotspot(hotspotData)
    local msg = Lang("HOTSPOT_STARTED"):format(hotspotData.zone or "?", hotspotData.minutes or 0)
    CreateNotification("notify", "success", msg)
end)

RegisterNetEvent("qs-fisher:hotspotEnded", function(data)
    local zone = (activeHotspot and activeHotspot.zone) or (data and data.zone) or "?"
    ResetHotspot()
    CreateNotification("notify", "info", Lang("HOTSPOT_ENDED"):format(zone))
end)

function CheckRunningHotspot(delayed)
    CreateThread(function()
        if delayed then
            Wait(5000)
        end
        if not isEligible then
            return
        end
        local currentHotspot = lib.callback.await("qs-fisher:getHotspot", false)
        if not currentHotspot then
            return ResetHotspot()
        end
        SetActiveHotspot(currentHotspot)
        if delayed then
            local mins = math.max(math.floor((currentHotspot.seconds or 0) / 60), 1)
            CreateNotification("notify", "info", Lang("HOTSPOT_ALREADY_RUNNING"):format(currentHotspot.zone or "?", mins))
        end
    end)
end

function OnFisherHotspotJobChanged(hasJob)
    if hasJob == nil then
        local hotspotsConfig = Config.Hotspots or {}
        isEligible = hotspotsConfig.FishersOnly ~= true
    else
        isEligible = hasJob
    end
    if hasJob then
        CheckRunningHotspot(true)
    else
        ResetHotspot()
    end
end

AddEventHandler("onResourceStop", function(resourceName)
    if GetCurrentResourceName() ~= resourceName then
        return
    end
    ClearHotspotBlips()
end)
--WKLeaks9!OnWiTopz2 : https://discord.gg/zqcBffbMZn
--WKLeak1$On05Topdk : https://discord.gg/zqcBffbMZn
--WKLeak_72OnBsTopK@ : https://discord.gg/zqcBffbMZn
--WKLeaks6OnV#TopOl : https://discord.gg/zqcBffbMZn
--WKLeaks!YOng9Topdy : https://discord.gg/zqcBffbMZn
