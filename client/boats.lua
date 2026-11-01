--[[   -- https://discord.gg/zqcBffbMZn ]]
local activeRental = {
    entity = nil,
    tier = nil,
    endsAt = nil
}
local isAnchored = false
local FADE_DURATION = 500
local ANCHOR_COOLDOWN = 400
local lastAnchorToggle = 0
local isReturningBoat = false

function GetRentedBoat()
    if activeRental.entity and DoesEntityExist(activeRental.entity) then
        return activeRental.entity
    end
    return nil
end

function AdoptRentedBoat(entity, tier)
    if not entity or not DoesEntityExist(entity) then
        return false
    end
    if activeRental.entity and DoesEntityExist(activeRental.entity) and activeRental.entity ~= entity then
        SetEntityAsMissionEntity(activeRental.entity, true, true)
        DeleteEntity(activeRental.entity)
    end
    activeRental.entity = entity
    activeRental.tier = tier or activeRental.tier
    activeRental.endsAt = nil
    isAnchored = false
    return true
end

function IsPlayerInBoatDriverSeat()
    if not activeRental.entity or not DoesEntityExist(activeRental.entity) then
        return false
    end
    return GetPedInVehicleSeat(activeRental.entity, -1) == PlayerPedId()
end

function UpdateBoatHud()
    local remainingSeconds = nil
    if activeRental.endsAt then
        local nowSec = GetGameTimer() / 1000
        remainingSeconds = math.max(math.floor(activeRental.endsAt - nowSec), 0)
    end

    local anchorKeyLabel = (Config.Keys and Config.Keys.AnchorKeyLabel) or "G"
    SendNUIMessage({
        action = "boatTimer",
        show = (activeRental.entity ~= nil and remainingSeconds ~= nil),
        seconds = remainingSeconds,
        image = activeRental.tier and activeRental.tier.image or nil,
        warn = (remainingSeconds ~= nil),
        anchorReady = IsPlayerInBoatDriverSeat(),
        anchored = isAnchored,
        anchorKey = anchorKeyLabel
    })
end

function DespawnRentedBoat()
    if activeRental.entity and DoesEntityExist(activeRental.entity) then
        RemoveVehiclekeys(activeRental.entity, GetVehicleNumberPlateText(activeRental.entity))
        SetEntityAsMissionEntity(activeRental.entity, true, true)
        DeleteEntity(activeRental.entity)
    end
    activeRental.entity = nil
    activeRental.tier = nil
    activeRental.endsAt = nil
    isAnchored = false
    UpdateBoatHud()
end

function ToggleAnchor()
    if not IsPlayerInBoatDriverSeat() then
        return
    end
    local now = GetGameTimer()
    if now < lastAnchorToggle then
        return
    end
    lastAnchorToggle = now + ANCHOR_COOLDOWN

    isAnchored = not isAnchored
    local boat = activeRental.entity
    if isAnchored then
        SetVehicleForwardSpeed(boat, 0.0)
        SetEntityVelocity(boat, 0.0, 0.0, 0.0)
        SetEntityAngularVelocity(boat, 0.0, 0.0, 0.0)
        SetBoatFrozenWhenAnchored(boat, true)
        SetBoatAnchor(boat, true)
    else
        SetBoatAnchor(boat, false)
        SetBoatFrozenWhenAnchored(boat, false)
        FreezeEntityPosition(boat, false)
    end

    UpdateBoatHud()
    CreateNotification("notify", "info", Lang(isAnchored and "BOAT_ANCHOR_DOWN" or "BOAT_ANCHOR_UP"))
end

CreateThread(function()
    local wasInDriverSeat = false
    local lastCheck = 0

    while true do
        if activeRental.entity then
            local now = GetGameTimer()
            if now - lastCheck >= 250 then
                lastCheck = now
                local inSeat = IsPlayerInBoatDriverSeat()
                if inSeat ~= wasInDriverSeat then
                    wasInDriverSeat = inSeat
                    UpdateBoatHud()
                end
            end

            if wasInDriverSeat then
                local anchorKey = (Config.Keys and Config.Keys.AnchorKey) or 47
                if IsControlJustPressed(0, anchorKey) then
                    ToggleAnchor()
                end
            end
            Wait(0)
        else
            if wasInDriverSeat then
                wasInDriverSeat = false
                lastCheck = 0
            end
            Wait(300)
        end
    end
end)

CreateThread(function()
    while true do
        Wait(1000)
        if activeRental.entity then
            UpdateBoatHud()
        end
    end
end)

function LoadBoatModel(modelName)
    local modelHash = joaat(modelName)
    RequestModel(modelHash)
    local timeout = GetGameTimer() + 8000
    while not HasModelLoaded(modelHash) do
        if GetGameTimer() > timeout then
            return nil
        end
        Wait(0)
    end
    return modelHash
end

function SpawnRentedBoat(tier, rentalDuration)
    local cfg = Config.BoatRental
    local spawnCoords = cfg.Spawn

    DoScreenFadeOut(FADE_DURATION)
    while not IsScreenFadedOut() do
        Wait(0)
    end

    local modelHash = LoadBoatModel(tier.model)
    if not modelHash then
        DoScreenFadeIn(FADE_DURATION)
        return CreateNotification("notify", "error", Lang("BOAT_MODEL_FAILED"))
    end

    if activeRental.entity and DoesEntityExist(activeRental.entity) then
        SetEntityAsMissionEntity(activeRental.entity, true, true)
        DeleteEntity(activeRental.entity)
    end

    local playerPed = PlayerPedId()
    local boat = CreateVehicle(modelHash, spawnCoords.x, spawnCoords.y, spawnCoords.z, spawnCoords.w, true, false)
    SetModelAsNoLongerNeeded(modelHash)

    if not DoesEntityExist(boat) then
        DoScreenFadeIn(FADE_DURATION)
        return CreateNotification("notify", "error", Lang("BOAT_MODEL_FAILED"))
    end

    SetEntityAsMissionEntity(boat, true, true)
    SetVehicleHasBeenOwnedByPlayer(boat, true)
    SetVehicleNeedsToBeHotwired(boat, false)
    SetVehRadioStation(boat, "OFF")
    SetPedIntoVehicle(playerPed, boat, -1)
    AddVehiclekeys(boat, GetVehicleNumberPlateText(boat))

    activeRental.entity = boat
    activeRental.tier = tier
    activeRental.endsAt = (rentalDuration and rentalDuration > 0) and (GetGameTimer() / 1000 + rentalDuration) or nil
    isAnchored = false

    UpdateBoatHud()
    DoScreenFadeIn(FADE_DURATION)
    CreateNotification("notify", "success", Lang("BOAT_RENTED"):format(tier.label))
end

RegisterNetEvent("qs-fisher:boatCrewAboard", function(targetCoords)
    DoScreenFadeOut(FADE_DURATION)
    while not IsScreenFadedOut() do
        Wait(0)
    end

    local playerPed = PlayerPedId()
    local offsetX = math.random(-2, 2) * 1.0
    local offsetY = math.random(-2, 2) * 1.0
    SetEntityCoords(playerPed, targetCoords.x + offsetX, targetCoords.y + offsetY, targetCoords.z, false, false, false, false)
    SetEntityHeading(playerPed, targetCoords.w)
    Wait(200)
    DoScreenFadeIn(FADE_DURATION)
    CreateNotification("notify", "info", Lang("BOAT_CREW_MOVED"))
end)

RegisterNUICallback("rentBoat", function(data, cb)
    cb("ok")
    local cfg = Config.BoatRental or {}
    if not cfg.Enabled then
        return
    end

    CreateThread(function()
        local response = lib.callback.await("qs-fisher:rentBoat", false, data.model)
        if not response or not response.ok then
            local reasonKey = (response and response.reason) or "BOAT_RENT_REFUSED"
            local reqLevel = (response and response.requiredLevel) or 0
            return CreateNotification("notify", "error", Lang(reasonKey):format(reqLevel))
        end
        SpawnRentedBoat(response.tier, response.seconds)
    end)
end)

RegisterNUICallback("returnBoat", function(data, cb)
    cb("ok")
    if isReturningBoat then
        return
    end
    if not activeRental.entity or not DoesEntityExist(activeRental.entity) then
        return CreateNotification("notify", "error", Lang("BOAT_NONE_OUT"))
    end

    local cfg = Config.BoatRental
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    local spawnVec = vector3(cfg.Spawn.x, cfg.Spawn.y, cfg.Spawn.z)
    local dist = #(playerCoords - spawnVec)
    local maxDist = cfg.ReturnRadius or 45.0

    if dist > maxDist then
        return CreateNotification("notify", "error", Lang("BOAT_TOO_FAR_TO_RETURN"):format(math.floor(dist)))
    end

    isReturningBoat = true
    CreateThread(function()
        local response = lib.callback.await("qs-fisher:returnBoat", false)
        isReturningBoat = false

        if response and response.reason then
            return CreateNotification("notify", "error", Lang(response.reason):format(math.floor(dist)))
        end

        DoScreenFadeOut(FADE_DURATION)
        while not IsScreenFadedOut() do
            Wait(0)
        end

        DespawnRentedBoat()

        if cfg.ReturnTo then
            SetEntityCoords(playerPed, cfg.ReturnTo.x, cfg.ReturnTo.y, cfg.ReturnTo.z, false, false, false, false)
            Wait(150)
        end

        DoScreenFadeIn(FADE_DURATION)

        if response and response.amount and response.amount > 0 then
            CreateNotification("notify", "success", Lang("BOAT_RETURNED_REFUND"):format(FormatCurrency(response.amount)))
        else
            CreateNotification("notify", "info", Lang("BOAT_RETURNED"))
        end
    end)
end)

RegisterNetEvent("qs-fisher:boatExpiring", function(duration)
    if activeRental.entity then
        activeRental.endsAt = (GetGameTimer() / 1000) + (duration or 0)
        UpdateBoatHud()
    end
    local mins = math.max(math.floor((duration or 0) / 60), 1)
    CreateNotification("notify", "warning", Lang("BOAT_EXPIRING"):format(mins))
end)

RegisterNetEvent("qs-fisher:boatExpired", function()
    if not activeRental.entity then
        return
    end
    DespawnRentedBoat()
    CreateNotification("notify", "error", Lang("BOAT_EXPIRED"))
end)

RegisterNUICallback("getBoatState", function(data, cb)
    local cfg = Config.BoatRental or {}
    cb({
        enabled = (cfg.Enabled == true),
        out = (activeRental.entity ~= nil and DoesEntityExist(activeRental.entity)),
        model = activeRental.tier and activeRental.tier.model or nil,
        refund = cfg.Refund or 0,
        tiers = cfg.Tiers or {}
    })
end)

AddEventHandler("onResourceStop", function(resourceName)
    if GetCurrentResourceName() ~= resourceName then
        return
    end
    if activeRental.entity and DoesEntityExist(activeRental.entity) then
        SetEntityAsMissionEntity(activeRental.entity, true, true)
        DeleteEntity(activeRental.entity)
    end
    DoScreenFadeIn(0)
end)
--WKLeak_MEOn5ZTopCE : https://discord.gg/zqcBffbMZn
--WKLeakEYOnf-Topfn : https://discord.gg/zqcBffbMZn
--WKLeak__lOnj5Topd8 : https://discord.gg/zqcBffbMZn
--WKLeaksBTOnTXTop4j : https://discord.gg/zqcBffbMZn
--WKLeak_RZOnUATop!S : https://discord.gg/zqcBffbMZn
