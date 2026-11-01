--[[   -- https://discord.gg/zqcBffbMZn ]]
local activeCampfires = {}
local STREAM_DISTANCE = 140.0
local nearestCampfire = nil
local activeCookSession = nil
local activeMenuCampfire = nil
local closeMenuCallback = nil
local buildConfirmCallback = nil
local activeCookingCam = nil
local customCamOverrides = nil
local isBuildingCampfire = false
local isCookingBusy = false

local INTERACTION_DIST = 2.5
local PROMPT_DISTANCE = 6.0
local MARKER_DISTANCE = 4.0
local SKEWER_PULL_AWAY_DIST = 8.0
local SKEWER_TURN_EVERY_SECS = 4.0
local WARN_AWAY_SECS = 2.0
local MAX_AWAY_DIST = 2.5
local MAX_AWAY_SECS = 4.0

function GetCampfireConfig()
    return Config.Campfire or {}
end

function GetCampfireCookConfig()
    return (Config.Campfire and Config.Campfire.Cook) or {}
end

local CAMPFIRE_PROP_MODEL = "prop_beach_fire"

function GetCampfirePropZOffset()
    local propZ = tonumber(GetCampfireConfig().PropZ)
    return propZ or -0.8
end

local CAMPFIRE_PTFX = {
    dict = "core",
    name = "ent_amb_beach_campfire",
    scale = 1.0,
    height = 0.0
}

local SKEWER_MODELS = {
    Empty = "custom_fish_skewer_empty",
    Raw = "custom_fish_skewer_raw_01",
    Cooked = "custom_fish_skewer_cooked_01",
    Burnt = "custom_fish_skewer_burnt_01"
}

local BUILD_ANIM = {
    dict = "amb@world_human_gardener_plant@male@base",
    clip = "base",
    duration = 3000,
    flag = 1
}

local COOK_ANIM = {
    dict = "amb@world_human_bbq@male@idle_a",
    clip = "idle_c"
}

local EMPTY_SKEWER_DURATION_MS = 0
local SKEWER_ATTACH_OFFSET = vec3(0.02, 0.38, 0.42)
local SKEWER_ATTACH_ROTATION = vec3(65.0, 0.0, -445.0)
local INITIAL_SKEWER_ROLL = 294.2
local ROLL_PER_TURN_TRIGGER = 180.0

local COOK_CAM_CONFIG = {
    Offset = vec3(0.04, -0.43, 0.94),
    AimHeight = 0.25,
    Fov = 44.0,
    BlendIn = 900,
    BlendOut = 600,
    Sensitivity = 80.0
}

local NON_CAMPFIRE_MATERIALS = {
    "TARMAC",
    "TARMAC_PAINTED",
    "TARMAC_POTHOLE",
    "RUMBLE_STRIP",
    "CONCRETE",
    "CONCRETE_POTHOLE",
    "CONCRETE_DUSTY",
    "MARBLE",
    "CERAMIC",
    "LINOLEUM",
    "CARPET",
    "METAL_SOLID_SMALL",
    "METAL_SOLID_MEDIUM",
    "METAL_SOLID_LARGE",
    "METAL_GRATE_SMALL",
    "METAL_GRATE_LARGE",
    "METAL_MANHOLE",
    "GLASS_SHOOT_THROUGH",
    "PLASTIC"
}

function EnsureModelLoaded(model)
    if HasModelLoaded(model) then
        return true
    end

    RequestModel(model)
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(model) do
        if GetGameTimer() > timeout then
            return false
        end
        Wait(0)
    end

    return true
end

CreateThread(function()
    if not GetCampfireConfig().Enabled then return end
    Wait(1000)

    local preloadModels = {
        CAMPFIRE_PROP_MODEL,
        SKEWER_MODELS.Empty,
        SKEWER_MODELS.Raw,
        SKEWER_MODELS.Cooked,
        SKEWER_MODELS.Burnt
    }

    for _, modelName in ipairs(preloadModels) do
        local modelHash = joaat(modelName)
        if IsModelInCdimage(modelHash) then
            RequestModel(modelHash)
        end
        Wait(0)
    end

    local preloadAnims = { COOK_ANIM, BUILD_ANIM }
    for _, animData in ipairs(preloadAnims) do
        if animData.dict then
            RequestAnimDict(animData.dict)
        end
    end
end)

function ProbeGroundZ(x, y, z)
    local ray = StartShapeTestRay(x, y, z + 50.0, x, y, z - 50.0, 1, 0, 0)
    local status, hit, hitCoords
    local timeout = GetGameTimer() + 500

    while status == 1 and GetGameTimer() < timeout do
        status, hit, hitCoords = GetShapeTestResult(ray)
        if status ~= 1 then break end
        Wait(0)
    end

    if hit and hitCoords and hitCoords.z ~= 0.0 then
        return hitCoords.z, true
    end

    return z, false
end

function ProbeGroundAndMaterial(x, y, z)
    local ray = StartShapeTestRay(x, y, z + 50.0, x, y, z - 50.0, 1, 0, 0)
    local status, hit, hitCoords, normal, materialHash
    local timeout = GetGameTimer() + 500

    while status == 1 and GetGameTimer() < timeout do
        status, hit, hitCoords, normal, materialHash = GetShapeTestResultIncludingMaterial(ray)
        if status ~= 1 then break end
        Wait(0)
    end

    if hit and hitCoords and hitCoords.z ~= 0.0 then
        return hitCoords.z, materialHash
    end

    return nil, nil
end

local blockedMaterialHashes = nil

function NormalizeMaterialHash(hashValue)
    local val = tonumber(hashValue) or 0
    if val < 0 then
        val = val + 4294967296
    end
    return val
end

function IsSurfaceBlocked(materialHash)
    if not materialHash then return false end

    if not blockedMaterialHashes then
        blockedMaterialHashes = {}
        for _, name in ipairs(NON_CAMPFIRE_MATERIALS) do
            local hash = NormalizeMaterialHash(joaat(name))
            blockedMaterialHashes[hash] = true
        end
    end

    local normalized = NormalizeMaterialHash(materialHash)
    return blockedMaterialHashes[normalized] == true
end

function CheckCampfireZone(x, y)
    local zones = GetCampfireConfig().Ground and GetCampfireConfig().Ground.Zones or {}
    for _, zone in ipairs(zones) do
        local coords = zone.coords
        local radius = tonumber(zone.radius) or 0.0
        if coords and radius > 0 then
            local dx = x - coords.x
            local dy = y - coords.y
            local dist = math.sqrt((dx * dx) + (dy * dy))
            if dist <= radius then
                return zone.label or "that spot"
            end
        end
    end
    return nil
end

function ValidateCampfirePlacement(ped)
    local pedCoords = GetEntityCoords(ped)
    local forwardPos = GetOffsetFromEntityInWorldCoords(ped, 0.0, 1.2, 0.0)
    local groundZ, materialHash = ProbeGroundAndMaterial(forwardPos.x, forwardPos.y, pedCoords.z)

    if not groundZ then
        local found, gz = GetGroundZFor_3dCoord(forwardPos.x, forwardPos.y, pedCoords.z + 1.0, false)
        if not found then
            return nil, "ground"
        end
        groundZ = gz
        materialHash = nil
    end

    local groundConfig = GetCampfireConfig().Ground or {}
    if groundConfig.NoWater ~= false then
        local inWater, waterHeight = GetWaterHeight(forwardPos.x, forwardPos.y, pedCoords.z)
        if not inWater then
            inWater, waterHeight = TestVerticalProbeAgainstAllWater(forwardPos.x, forwardPos.y, pedCoords.z + 5.0, 0)
        end

        if inWater and waterHeight and waterHeight > (groundZ - 0.2) then
            return nil, "water"
        end
    end

    if IsSurfaceBlocked(materialHash) then
        return nil, "surface"
    end

    local zoneLabel = CheckCampfireZone(forwardPos.x, forwardPos.y)
    if zoneLabel then
        return nil, "zone", zoneLabel
    end

    return vector3(forwardPos.x, forwardPos.y, groundZ)
end

function GetPlacementErrorMessage(reason, zoneLabel)
    if reason == "water" then
        return Lang("CAMPFIRE_NO_WATER")
    elseif reason == "surface" then
        return Lang("CAMPFIRE_NO_SURFACE")
    elseif reason == "zone" then
        return Lang("CAMPFIRE_NO_ZONE"):format(zoneLabel or "?")
    end
    return Lang("CAMPFIRE_NEED_GROUND")
end

function DeleteCampfireEntity(campfire)
    ClearTargetForFire(campfire)

    if campfire.ptfx then
        StopParticleFxLooped(campfire.ptfx, 0)
        campfire.ptfx = nil
    end

    if campfire.prop and DoesEntityExist(campfire.prop) then
        DeleteEntity(campfire.prop)
    end
    campfire.prop = nil
end

function SettleCampfireOnGround(campfire)
    local prop = campfire.prop
    if not prop or not DoesEntityExist(prop) then return false end

    local groundZ, found = ProbeGroundZ(campfire.x, campfire.y, campfire.z)
    if not found or not DoesEntityExist(prop) then return false end

    groundZ = groundZ + GetCampfirePropZOffset()
    FreezeEntityPosition(prop, false)
    Wait(0)
    SetEntityCoords(prop, campfire.x, campfire.y, groundZ)
    Wait(0)
    FreezeEntityPosition(prop, true)
    campfire.settled = true

    return true
end

function SpawnCampfireEntity(campfire)
    if campfire.prop and DoesEntityExist(campfire.prop) then
        return true
    end

    local modelHash = joaat(CAMPFIRE_PROP_MODEL)
    if not EnsureModelLoaded(modelHash) then
        return false
    end

    local prop = CreateObject(modelHash, campfire.x, campfire.y, campfire.z, false, false, false)
    campfire.prop = prop

    if not DoesEntityExist(campfire.prop) then
        campfire.prop = nil
        return false
    end

    SetEntityHeading(campfire.prop, campfire.heading or 0.0)
    campfire.settled = false

    local fireId = campfire.id
    CreateThread(function()
        while activeCampfires[fireId] == campfire and campfire.prop and DoesEntityExist(campfire.prop) do
            if SettleCampfireOnGround(campfire) then
                return
            end
            Wait(500)
        end
    end)

    local ptfxDict = CAMPFIRE_PTFX.dict
    if not HasNamedPtfxAssetLoaded(ptfxDict) then
        RequestNamedPtfxAsset(ptfxDict)
        local timeout = GetGameTimer() + 2000
        while not HasNamedPtfxAssetLoaded(ptfxDict) and GetGameTimer() < timeout do
            Wait(0)
        end
    end

    if HasNamedPtfxAssetLoaded(ptfxDict) and DoesEntityExist(campfire.prop) then
        UseParticleFxAssetNextCall(ptfxDict)
        local fxHandle = StartParticleFxLoopedOnEntity(
            CAMPFIRE_PTFX.name,
            campfire.prop,
            0.0, 0.0, CAMPFIRE_PTFX.height,
            0.0, 0.0, 0.0,
            CAMPFIRE_PTFX.scale,
            false, false, false
        )
        if fxHandle and fxHandle ~= 0 then
            campfire.ptfx = fxHandle
        end
    end

    return true
end

function RemoveCampfire(campfireId)
    local campfire = activeCampfires[campfireId]
    if not campfire then return end

    if nearestCampfire and nearestCampfire.id == campfireId then
        nearestCampfire = nil
    end

    if activeMenuCampfire and activeMenuCampfire.id == campfireId then
        CloseCampfireMenu()
    end

    DeleteCampfireEntity(campfire)
    activeCampfires[campfireId] = nil
end

function AddOrUpdateCampfire(data)
    if not data or not data.id then return end

    if data.left ~= nil and data.left <= 0 then
        return
    end

    RemoveCampfire(data.id)
    activeCampfires[data.id] = {
        id = data.id,
        x = data.x,
        y = data.y,
        z = data.z,
        heading = data.heading or 0.0
    }
end

RegisterNetEvent("qs-fisher:campfireLit", function(data)
    AddOrUpdateCampfire(data)
end)

RegisterNetEvent("qs-fisher:campfireOut", function(fireId)
    RemoveCampfire(fireId)
end)

CreateThread(function()
    while true do
        if next(activeCampfires) == nil then
            Wait(1000)
        else
            local pedCoords = GetEntityCoords(PlayerPedId())
            for _, campfire in pairs(activeCampfires) do
                local dist = #(vector3(campfire.x, campfire.y, campfire.z) - pedCoords)
                if dist <= STREAM_DISTANCE then
                    SpawnCampfireEntity(campfire)
                else
                    if campfire.prop then
                        DeleteCampfireEntity(campfire)
                    end
                end
            end
            Wait(1500)
        end
    end
end)

function ShowBuildConfirmation(fuelData)
    if buildConfirmCallback or activeMenuCampfire then
        return false
    end

    local confirmResult = nil
    buildConfirmCallback = function(approved)
        confirmResult = approved
    end

    SetNuiFocus(true, true)
    SendNUIMessage({
        action = "campfire",
        show = true,
        mode = "build",
        item = fuelData.item,
        label = fuelData.label,
        amount = fuelData.amount,
        have = fuelData.have
    })

    local timeout = GetGameTimer() + 30000
    while confirmResult == nil and GetGameTimer() < timeout do
        Wait(50)
    end

    buildConfirmCallback = nil
    SetNuiFocus(false, false)
    SendNUIMessage({
        action = "campfire",
        show = false
    })

    return confirmResult == true
end

RegisterNUICallback("campfireBuild", function(data, cb)
    cb("ok")
    if buildConfirmCallback then
        buildConfirmCallback(data and data.ok == true)
    end
end)

function LightCampfireAction()
    if not GetCampfireConfig().Enabled or isBuildingCampfire or isCookingBusy then
        return
    end

    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then
        return CreateNotification("notify", "error", Lang("CAMPFIRE_IN_VEHICLE"))
    end

    if IsPedSwimming(ped) or IsPedSwimmingUnderWater(ped) then
        return CreateNotification("notify", "error", Lang("CAMPFIRE_NO_WATER"))
    end

    if activeCookSession then
        return CreateNotification("notify", "error", Lang("COOK_ALREADY"))
    end

    local placementPos, errReason, errZone = ValidateCampfirePlacement(ped)
    if not placementPos then
        return CreateNotification("notify", "error", GetPlacementErrorMessage(errReason, errZone))
    end

    if GetCampfireConfig().Confirm ~= false then
        isCookingBusy = true
        local fuelCheck = lib.callback.await("qs-fisher:getCampfireFuel", false)
        isCookingBusy = false

        if type(fuelCheck) ~= "table" or not fuelCheck.item then
            return CreateNotification("notify", "error", Lang("CAMPFIRE_NEED_WOOD"):format(fuelCheck and fuelCheck.amount or 1))
        end

        if not ShowBuildConfirmation(fuelCheck) then
            return
        end

        isCookingBusy = true
        local freshFuel = lib.callback.await("qs-fisher:getCampfireFuel", false, true)
        isCookingBusy = false

        if type(freshFuel) ~= "table" or not freshFuel.item then
            return CreateNotification("notify", "error", Lang("CAMPFIRE_NEED_WOOD"):format(freshFuel and freshFuel.amount or fuelCheck.amount or 1))
        end

        ped = PlayerPedId()
        if IsPedInAnyVehicle(ped, false) then
            return CreateNotification("notify", "error", Lang("CAMPFIRE_IN_VEHICLE"))
        end

        placementPos, errReason, errZone = ValidateCampfirePlacement(ped)
        if not placementPos then
            return CreateNotification("notify", "error", GetPlacementErrorMessage(errReason, errZone))
        end
    end

    if BUILD_ANIM.dict and BUILD_ANIM.clip then
        isBuildingCampfire = true
        RequestAnimDict(BUILD_ANIM.dict)
        local animTimeout = GetGameTimer() + 2000
        while not HasAnimDictLoaded(BUILD_ANIM.dict) and GetGameTimer() < animTimeout do
            Wait(0)
        end

        function CleanupBuildAnim()
            isBuildingCampfire = false
            local p = PlayerPedId()
            if DoesEntityExist(p) then
                FreezeEntityPosition(p, false)
            end
        end

        if HasAnimDictLoaded(BUILD_ANIM.dict) then
            local animDuration = math.max(math.floor(tonumber(BUILD_ANIM.duration) or 3000), 0)
            local animFlag = math.floor(tonumber(BUILD_ANIM.flag) or 1)

            TaskPlayAnim(ped, BUILD_ANIM.dict, BUILD_ANIM.clip, 4.0, -4.0, animDuration, animFlag, 0, false, false, false)

            local pbarSuccess, pbarResult = pcall(lib.progressBar, {
                duration = animDuration,
                label = Lang("CAMPFIRE_BUILDING"),
                useWhileDead = false,
                canCancel = true,
                disable = { car = true, combat = true, move = true }
            })

            if pbarSuccess then
                if pbarResult ~= true then
                    ClearPedTasks(PlayerPedId())
                    CleanupBuildAnim()
                    return CreateNotification("notify", "error", Lang("CAMPFIRE_CANCELLED"))
                end
            else
                print(string.format("^3[qs-fishingjob]^0 the campfire progress bar failed: %s", tostring(pbarResult)))
                Wait(animDuration)
            end

            ClearPedTasks(PlayerPedId())
        end

        CleanupBuildAnim()
        ped = PlayerPedId()
        if IsPedInAnyVehicle(ped, false) then
            return CreateNotification("notify", "error", Lang("CAMPFIRE_IN_VEHICLE"))
        end

        placementPos, errReason, errZone = ValidateCampfirePlacement(ped)
        if not placementPos then
            return CreateNotification("notify", "error", GetPlacementErrorMessage(errReason, errZone))
        end
    end

    isCookingBusy = true
    local lightResult = lib.callback.await("qs-fisher:lightCampfire", false, {
        x = placementPos.x,
        y = placementPos.y,
        z = placementPos.z,
        heading = GetEntityHeading(PlayerPedId())
    })
    isCookingBusy = false

    if not lightResult or not lightResult.ok then
        local reason = lightResult and lightResult.reason or "bad"
        if reason == "nofuel" then
            return CreateNotification("notify", "error", Lang("CAMPFIRE_NEED_WOOD"):format(lightResult and lightResult.amount or 1))
        elseif reason == "limit" then
            return CreateNotification("notify", "error", Lang("CAMPFIRE_LIMIT"):format(lightResult and lightResult.limit or 1))
        elseif reason == "crowded" then
            return CreateNotification("notify", "error", Lang("CAMPFIRE_CROWDED"))
        elseif reason == "zone" then
            return CreateNotification("notify", "error", Lang("CAMPFIRE_NO_ZONE"):format(lightResult and lightResult.label or "?"))
        elseif reason == "far" then
            return CreateNotification("notify", "error", Lang("CAMPFIRE_NEED_GROUND"))
        end
        return CreateNotification("notify", "error", Lang("CAMPFIRE_FAILED"))
    end

    CreateNotification("notify", "success", Lang("CAMPFIRE_LIT"):format(lightResult.minutes or 1))
end

exports("lightCampfire", LightCampfireAction)
RegisterNetEvent("qs-fisher:useCampfire", LightCampfireAction)

local cmdName = GetCampfireConfig().Command
if GetCampfireConfig().Enabled and cmdName and cmdName ~= "" then
    RegisterCommand(cmdName, function()
        CreateThread(LightCampfireAction)
    end, false)
end

local cachedCookableItems = {}

function FetchCookables()
    local result = lib.callback.await("qs-fisher:getCookables", false)
    if type(result) == "table" then
        cachedCookableItems = result
    end
end

function GetSkewerModelForState(state)
    if state == "raw" then
        return SKEWER_MODELS.Raw or SKEWER_MODELS.Empty
    elseif state == "cooked" then
        return SKEWER_MODELS.Cooked or SKEWER_MODELS.Empty
    elseif state == "burnt" then
        return SKEWER_MODELS.Burnt or SKEWER_MODELS.Empty
    end
    return SKEWER_MODELS.Empty
end

local rollAxis = "x"

function GetRollAxis()
    if rollAxis == "x" or rollAxis == "y" or rollAxis == "z" then
        return rollAxis
    end
    return "x"
end

function ApplySkewerRollOffset(rx, ry, rz, roll)
    local axis = GetRollAxis()
    if axis == "y" then
        return rx, ry + roll, rz
    elseif axis == "z" then
        return rx, ry, rz + roll
    end
    return rx + roll, ry, rz
end

function UpdateSkewerTransform(prop, roll)
    if not prop or not DoesEntityExist(prop) then return end

    local ped = PlayerPedId()
    local worldPos = GetOffsetFromEntityInWorldCoords(ped, SKEWER_ATTACH_OFFSET.x, SKEWER_ATTACH_OFFSET.y, SKEWER_ATTACH_OFFSET.z)
    local rx, ry, rz = ApplySkewerRollOffset(SKEWER_ATTACH_ROTATION.x, SKEWER_ATTACH_ROTATION.y, SKEWER_ATTACH_ROTATION.z, roll)

    SetEntityCoordsNoOffset(prop, worldPos.x, worldPos.y, worldPos.z, false, false, false)
    SetEntityRotation(prop, rx, ry, rz + GetEntityHeading(ped), 2, true)
end

function DestroySkewerProp()
    if activeCookSession and activeCookSession.prop and DoesEntityExist(activeCookSession.prop) then
        DeleteEntity(activeCookSession.prop)
    end
    if activeCookSession then
        activeCookSession.prop = nil
        activeCookSession.model = nil
    end
end

function CreateOrUpdateSkewerProp(state)
    if not activeCookSession then return end

    local modelHash = joaat(GetSkewerModelForState(state))
    if activeCookSession.model == modelHash and activeCookSession.prop and DoesEntityExist(activeCookSession.prop) then
        return
    end

    if not EnsureModelLoaded(modelHash) or not activeCookSession then
        return
    end

    DestroySkewerProp()

    local pedPos = GetEntityCoords(PlayerPedId())
    local prop = CreateObject(modelHash, pedPos.x, pedPos.y, pedPos.z, false, false, false)
    activeCookSession.prop = prop
    activeCookSession.model = modelHash

    if DoesEntityExist(prop) then
        SetEntityCollision(prop, false, false)
        FreezeEntityPosition(prop, true)
        UpdateSkewerTransform(prop, activeCookSession.roll or 0.0)
    end
end

function DestroyCookingCamera(instant)
    if not activeCookingCam then return end

    local blendOut = instant and 0 or math.max(math.floor(COOK_CAM_CONFIG.BlendOut), 0)
    RenderScriptCams(false, not instant, blendOut, true, true)

    if DoesCamExist(activeCookingCam) then
        DestroyCam(activeCookingCam, false)
    end
    activeCookingCam = nil
end

function UpdateCookingCamera(skewerProp)
    if not activeCookingCam or not DoesCamExist(activeCookingCam) then return end

    local ped = PlayerPedId()
    if customCamOverrides and customCamOverrides.ped then
        local camData = customCamOverrides.ped
        local eyePos = GetOffsetFromEntityInWorldCoords(ped, camData.eye.x, camData.eye.y, camData.eye.z)
        local lookPos = GetOffsetFromEntityInWorldCoords(ped, camData.look.x, camData.look.y, camData.look.z)
        SetCamCoord(activeCookingCam, eyePos.x, eyePos.y, eyePos.z)
        SetCamFov(activeCookingCam, tonumber(camData.fov) or 50.0)
        PointCamAtCoord(activeCookingCam, lookPos.x, lookPos.y, lookPos.z)
        return
    end

    local camOffset = (customCamOverrides and customCamOverrides.off) or COOK_CAM_CONFIG.Offset
    local aimHeight = (customCamOverrides and customCamOverrides.aim) or COOK_CAM_CONFIG.AimHeight
    local fov = (customCamOverrides and customCamOverrides.fov) or COOK_CAM_CONFIG.Fov

    local camPos = GetOffsetFromEntityInWorldCoords(
        ped,
        SKEWER_ATTACH_OFFSET.x + camOffset.x,
        SKEWER_ATTACH_OFFSET.y + camOffset.y,
        SKEWER_ATTACH_OFFSET.z + camOffset.z
    )

    SetCamCoord(activeCookingCam, camPos.x, camPos.y, camPos.z)
    SetCamFov(activeCookingCam, fov)

    local targetCoords = (skewerProp and DoesEntityExist(skewerProp)) and GetEntityCoords(skewerProp) or GetOffsetFromEntityInWorldCoords(ped, SKEWER_ATTACH_OFFSET.x, SKEWER_ATTACH_OFFSET.y, SKEWER_ATTACH_OFFSET.z)
    PointCamAtCoord(activeCookingCam, targetCoords.x, targetCoords.y, targetCoords.z + aimHeight)
end

function CreateCookingCamera(skewerProp, force)
    if activeCookingCam then return end

    if not force and GetCampfireCookConfig().Camera and GetCampfireCookConfig().Camera.Enabled == false then
        return
    end

    activeCookingCam = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)
    if not activeCookingCam or activeCookingCam == 0 then
        activeCookingCam = nil
        return
    end

    SetCamFov(activeCookingCam, COOK_CAM_CONFIG.Fov)
    UpdateCookingCamera(skewerProp)
    SetCamActive(activeCookingCam, true)

    local blendIn = math.max(math.floor(COOK_CAM_CONFIG.BlendIn), 0)
    RenderScriptCams(true, true, blendIn, true, true)
end

function HidePlayerWhileCooking(ped)
    if not activeCookingCam then return end
    SetEntityLocallyInvisible(ped)
end

local lastHudSendTime = 0

function UpdateCookHud(session)
    local now = GetGameTimer()
    local state = session.state or "raw"

    if (now - lastHudSendTime) < 100 and state == session.sentState then
        return
    end

    lastHudSendTime = now
    session.sentState = state

    local toCookedTime = math.max(tonumber(session.toCooked) or 25.0, 0.1)
    local elapsedSec = (now - (session.readAt or now)) / 1000
    local overFireTime = (session.overFire or 0) + elapsedSec
    local toBurntTime = math.max(tonumber(session.toBurnt) or (toCookedTime * 1.28), toCookedTime + 0.1)
    local sinceTurnTime = (session.sinceTurn or 0) + elapsedSec

    SendNUIMessage({
        action = "cookHud",
        show = true,
        label = session.label or Lang("COOK_RAW_SKEWER"),
        state = state,
        overFire = overFireTime,
        toCooked = toCookedTime,
        toBurnt = toBurntTime,
        sinceTurn = sinceTurnTime,
        turnEvery = SKEWER_TURN_EVERY_SECS,
        near = session.near ~= false,
        key = Config.Keys and Config.Keys.InteractKeyLabel or "E"
    })
end

function HideCookHud()
    lastHudSendTime = 0
    SendNUIMessage({
        action = "cookHud",
        show = false
    })
end

function ExitCookingSession(instant)
    if not activeCookSession then return end

    DestroySkewerProp()
    activeCookSession = nil
    HideCookHud()
    DestroyCookingCamera(instant)
    ClearPedTasks(PlayerPedId())
end

function NotifyCookResult(result)
    if not result or not result.ok then return end

    if result.state == "cooked" then
        CreateNotification("notify", "success", Lang("COOK_TOOK_COOKED"))
    elseif result.state == "burnt" then
        CreateNotification("notify", "error", Lang("COOK_TOOK_BURNT"))
    else
        CreateNotification("notify", "info", Lang("COOK_TOOK_RAW"))
    end
end

function RequestTakeSkewer()
    if not activeCookSession or isCookingBusy then return end

    isCookingBusy = true
    local takeResult = lib.callback.await("qs-fisher:takeSkewer", false)
    isCookingBusy = false

    if not takeResult or not takeResult.ok then
        local reason = takeResult and takeResult.reason or "bad"
        if reason == "full" then
            if activeCookSession and activeCookSession.blocked then
                ExitCookingSession()
                return CreateNotification("notify", "error", Lang("COOK_TOOK_RAW"))
            end
            if activeCookSession then
                activeCookSession.blocked = true
            end
            return CreateNotification("notify", "error", Lang("NOTIFY_INVENTORY_FULL"))
        elseif reason == "noitem" then
            return CreateNotification("notify", "error", Lang("NOTIFY_ITEM_DOES_NOT_EXIST"):format(takeResult.missing or "?"))
        elseif reason == "busy" then
            return
        end
        ExitCookingSession()
        return
    end

    ExitCookingSession()
    NotifyCookResult(takeResult)
end

function TriggerTakeSkewer()
    if not activeCookSession or activeCookSession.taking then return end

    if not activeCookSession.blocked and activeCookSession.retryAt and GetGameTimer() < activeCookSession.retryAt then
        return
    end

    activeCookSession.taking = true
    CreateThread(function()
        RequestTakeSkewer()
        if activeCookSession then
            activeCookSession.taking = nil
            activeCookSession.retryAt = GetGameTimer() + 3000
        end
    end)
end

RegisterNetEvent("qs-fisher:cookEnded", function(data)
    if not activeCookSession then return end

    if not data or not data.ok then
        if data and data.reason == "full" then
            CreateNotification("notify", "error", Lang("NOTIFY_INVENTORY_FULL"))
        elseif data and data.reason == "noitem" then
            CreateNotification("notify", "error", Lang("NOTIFY_ITEM_DOES_NOT_EXIST"):format(data.missing or "?"))
        end
        return
    end

    if data.why == "fireout" then
        CreateNotification("notify", "info", Lang("CAMPFIRE_WENT_OUT"))
    end

    ExitCookingSession()
    NotifyCookResult(data)
end)

RegisterNetEvent("qs-fisher:cookState", function(data)
    if not activeCookSession or type(data) ~= "table" then return end

    local prevState = activeCookSession.state
    activeCookSession.state = data.state or "raw"
    activeCookSession.overFire = tonumber(data.overFire) or 0
    activeCookSession.charred = tonumber(data.charred) or 0
    activeCookSession.sinceTurn = tonumber(data.sinceTurn) or 0
    activeCookSession.near = data.near ~= false
    activeCookSession.readAt = GetGameTimer()

    if activeCookSession.state ~= prevState then
        CreateOrUpdateSkewerProp(activeCookSession.state)
    end
end)

local disabledCookingControls = {
    1, 2, 21, 22, 23, 24, 25, 30, 31, 32, 33, 34, 35, 36, 44,
    140, 141, 142, 143, 263, 264
}

function DisableCookingControlsAndGetMouse()
    for _, control in ipairs(disabledCookingControls) do
        DisableControlAction(0, control, true)
    end
    return -GetDisabledControlNormal(0, 1)
end

function EnsureCookingAnimPlaying()
    if not COOK_ANIM.dict or not COOK_ANIM.clip then return end

    if not HasAnimDictLoaded(COOK_ANIM.dict) then
        RequestAnimDict(COOK_ANIM.dict)
        return
    end

    local ped = PlayerPedId()
    if not IsEntityPlayingAnim(ped, COOK_ANIM.dict, COOK_ANIM.clip, 3) then
        TaskPlayAnim(ped, COOK_ANIM.dict, COOK_ANIM.clip, 4.0, -4.0, -1, 49, 0.0, false, false, false)
    end
end

function CookingMinigameLoop()
    local rollThreshold = math.max(ROLL_PER_TURN_TRIGGER, 10.0)
    local sensitivity = math.max(COOK_CAM_CONFIG.Sensitivity, 1.0)
    local maxDist = MAX_AWAY_DIST
    local maxSecs = MAX_AWAY_SECS

    while true do
        Wait(0)
        local session = activeCookSession
        if not session then return end

        local ped = PlayerPedId()
        EnsureCookingAnimPlaying()

        local mouseDelta = DisableCookingControlsAndGetMouse()
        if mouseDelta ~= 0.0 then
            local addedRoll = mouseDelta * sensitivity
            session.roll = ((session.roll or 0.0) + addedRoll) % 360.0
            session.rolled = (session.rolled or 0.0) + math.abs(addedRoll)

            if session.rolled >= rollThreshold then
                session.rolled = 0.0
                TriggerServerEvent("qs-fisher:turnSkewer")
            end
        end

        UpdateSkewerTransform(session.prop, session.roll or 0.0)
        UpdateCookingCamera(activeCookSession and activeCookSession.prop)
        HidePlayerWhileCooking(ped)
        UpdateCookHud(session)

        local interactKey = Config.Keys and Config.Keys.InteractKey or 38
        if IsControlJustReleased(0, interactKey) then
            TriggerTakeSkewer()
        end

        local campfire = activeCampfires[session.fireId]
        if not campfire or IsPedInAnyVehicle(ped, false) or IsEntityDead(ped) then
            TriggerTakeSkewer()
        else
            local pedCoords = GetEntityCoords(ped)
            local dist = #(pedCoords - vector3(campfire.x, campfire.y, campfire.z))
            if dist > maxDist then
                session.away = (session.away or 0) + GetFrameTime()
                if session.away > maxSecs then
                    if not session.warnedAway then
                        session.warnedAway = true
                        CreateNotification("notify", "info", Lang("COOK_LEFT_FIRE"))
                    end
                    TriggerTakeSkewer()
                end
            else
                session.away = 0
                session.warnedAway = nil
            end
        end
    end
end

function StartCookingSession(campfire, cookableItem)
    if activeCookSession or isCookingBusy or not campfire or not cookableItem then
        return
    end

    isCookingBusy = true
    if StowFishingRod then
        StowFishingRod()
    end

    activeCookSession = {
        fireId = campfire.id,
        state = "empty",
        label = cookableItem.label,
        roll = INITIAL_SKEWER_ROLL,
        rolled = 0.0,
        away = 0.0,
        readAt = GetGameTimer()
    }

    local ped = PlayerPedId()
    local pedCoords = GetEntityCoords(ped)
    local targetHeading = GetHeadingFromVector_2d(campfire.x - pedCoords.x, campfire.y - pedCoords.y)
    SetEntityHeading(ped, targetHeading)

    CreateCookingCamera(nil)
    local initialEmptyDelay = math.max(math.floor(EMPTY_SKEWER_DURATION_MS), 0)

    activeCookSession.state = (initialEmptyDelay > 0) and "empty" or "raw"
    CreateOrUpdateSkewerProp(activeCookSession.state)
    EnsureCookingAnimPlaying()

    local startResponse = nil
    CreateThread(function()
        local res = lib.callback.await("qs-fisher:startCooking", false, campfire.id, cookableItem.item)
        startResponse = res or false
    end)

    local delayTimeout = GetGameTimer() + initialEmptyDelay
    local abortTimeout = GetGameTimer() + 15000
    local sensitivity = math.max(COOK_CAM_CONFIG.Sensitivity, 1.0)

    while GetGameTimer() < delayTimeout or startResponse == nil do
        Wait(0)
        local session = activeCookSession
        if not session then return end

        if GetGameTimer() > abortTimeout then
            ExitCookingSession()
            isCookingBusy = false
            return CreateNotification("notify", "error", Lang("COOK_FAILED"))
        end

        local mouseDelta = DisableCookingControlsAndGetMouse()
        if mouseDelta ~= 0.0 then
            session.roll = ((session.roll or 0.0) + (mouseDelta * sensitivity)) % 360.0
        end

        UpdateSkewerTransform(session.prop, session.roll or 0.0)
        UpdateCookingCamera(session.prop)
        HidePlayerWhileCooking(PlayerPedId())
        EnsureCookingAnimPlaying()
    end

    isCookingBusy = false
    if not startResponse or not startResponse.ok then
        ExitCookingSession()
        local reason = startResponse and startResponse.reason or "bad"
        if reason == "already" then
            return CreateNotification("notify", "error", Lang("COOK_ALREADY"))
        elseif reason == "noitem" then
            return CreateNotification("notify", "error", Lang("COOK_NO_FISH"))
        elseif reason == "gone" then
            return CreateNotification("notify", "error", Lang("CAMPFIRE_GONE"))
        elseif reason == "far" then
            return CreateNotification("notify", "error", Lang("CAMPFIRE_TOO_FAR"))
        end
        return CreateNotification("notify", "error", Lang("COOK_FAILED"))
    end

    if not activeCookSession then return end

    activeCookSession.state = "raw"
    activeCookSession.toCooked = startResponse.toCooked
    activeCookSession.toBurnt = startResponse.toBurnt
    activeCookSession.overFire = 0

    CreateOrUpdateSkewerProp("raw")
    CookingMinigameLoop()
end

function CloseCampfireMenu()
    if not activeMenuCampfire then return end
    activeMenuCampfire = nil
    SetNuiFocus(false, false)
    SendNUIMessage({
        action = "campfire",
        show = false
    })
end

closeMenuCallback = CloseCampfireMenu

function OpenCampfireMenu(campfire)
    if activeCookSession or isCookingBusy or activeMenuCampfire or not campfire then
        return
    end

    isCookingBusy = true
    FetchCookables()
    isCookingBusy = false

    if #cachedCookableItems == 0 then
        return CreateNotification("notify", "error", Lang("CAMPFIRE_NOTHING_TO_COOK"))
    end

    activeMenuCampfire = campfire
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = "campfire",
        show = true,
        items = cachedCookableItems
    })
end

RegisterNUICallback("campfireClose", function(data, cb)
    cb("ok")
    if buildConfirmCallback then
        buildConfirmCallback(false)
        return
    end
    CloseCampfireMenu()
end)

RegisterNUICallback("campfirePick", function(data, cb)
    cb("ok")
    local selectedCampfire = activeMenuCampfire
    CloseCampfireMenu()

    if not selectedCampfire or type(data) ~= "table" then return end

    local matchedItem = nil
    for _, item in ipairs(cachedCookableItems) do
        if item.item == data.item then
            matchedItem = item
            break
        end
    end

    if not matchedItem then return end

    CreateThread(function()
        StartCookingSession(selectedCampfire, matchedItem)
    end)
end)

function AddTargetForFire(campfire)
    if not Config.Target or not campfire.prop or campfire.targeted then
        return
    end

    campfire.targeted = true

    if Config.TargetScript == "ox" then
        exports.ox_target:addLocalEntity(campfire.prop, {
            {
                name = "qs-fisher:campfire" .. campfire.id,
                label = Lang("TARGET_CAMPFIRE_COOK"),
                icon = "fa-solid fa-fire",
                distance = INTERACTION_DIST,
                onSelect = function()
                    CreateThread(function()
                        OpenCampfireMenu(campfire)
                    end)
                end,
                canInteract = function()
                    return activeCookSession == nil
                end
            }
        })
    elseif Config.TargetScript == "qb" then
        exports["qb-target"]:AddTargetEntity(campfire.prop, {
            options = {
                {
                    num = 1,
                    label = Lang("TARGET_CAMPFIRE_COOK"),
                    icon = "fa-solid fa-fire",
                    action = function()
                        CreateThread(function()
                            OpenCampfireMenu(campfire)
                        end)
                    end,
                    canInteract = function()
                        return activeCookSession == nil
                    end
                }
            },
            distance = INTERACTION_DIST
        })
    end
end

function ClearTargetForFire(campfire)
    if not campfire or not campfire.targeted or not campfire.prop then
        return
    end

    campfire.targeted = nil
    if Config.TargetScript == "ox" then
        exports.ox_target:removeLocalEntity(campfire.prop)
    elseif Config.TargetScript == "qb" then
        exports["qb-target"]:RemoveTargetEntity(campfire.prop)
    end
end

function AtCampfire()
    if activeCookSession or activeMenuCampfire then
        return true
    end
    return not Config.Target
end

CreateThread(function()
    while true do
        local sleep = 500
        local markerConfig = GetCampfireConfig().Marker

        if markerConfig and markerConfig.enabled and next(activeCampfires) ~= nil then
            local pedCoords = GetEntityCoords(PlayerPedId())
            local maxDist = tonumber(markerConfig.distance) or 40.0
            local size = markerConfig.size or { x = 0.25, y = 0.25, z = 0.18 }
            local color = markerConfig.color or { r = 59, g = 130, b = 246, a = 170 }
            local height = tonumber(markerConfig.height) or 1.4
            local bobOffset = markerConfig.bob and (math.sin(GetGameTimer() / 400.0) * 0.05) or 0.0

            for _, campfire in pairs(activeCampfires) do
                local firePos = vector3(campfire.x, campfire.y, campfire.z)
                if #(pedCoords - firePos) <= maxDist then
                    sleep = 0
                    DrawMarker(
                        tonumber(markerConfig.type) or 0,
                        firePos.x, firePos.y, firePos.z + height + bobOffset,
                        0.0, 0.0, 0.0,
                        0.0, 0.0, 0.0,
                        size.x, size.y, size.z,
                        color.r, color.g, color.b, color.a,
                        markerConfig.bob == true,
                        false, 2, false, nil, nil, false
                    )
                end
            end
        end

        Wait(sleep)
    end
end)

CreateThread(function()
    while true do
        local sleep = 1000

        if next(activeCampfires) ~= nil and not activeCookSession and not activeMenuCampfire then
            local pedCoords = GetEntityCoords(PlayerPedId())
            local closestDist = INTERACTION_DIST
            local closestFire = nil

            for _, campfire in pairs(activeCampfires) do
                if campfire.prop and DoesEntityExist(campfire.prop) then
                    AddTargetForFire(campfire)
                    local dist = #(vector3(campfire.x, campfire.y, campfire.z) - pedCoords)
                    if dist <= closestDist then
                        closestDist = dist
                        closestFire = campfire
                    end
                end
            end

            if closestFire then
                sleep = 0
                nearestCampfire = closestFire

                if Config.DrawText3D and not Config.Target then
                    DrawText3D(
                        closestFire.x, closestFire.y, closestFire.z + 0.9,
                        Lang("CAMPFIRE_PROMPT"),
                        "campfire_" .. closestFire.id,
                        Config.Keys and Config.Keys.InteractKeyLabel or "E"
                    )
                end

                if not Config.Target then
                    local key = Config.Keys and Config.Keys.InteractKey or 38
                    if IsControlJustReleased(0, key) then
                        CreateThread(function()
                            OpenCampfireMenu(closestFire)
                        end)
                    end
                end
            else
                nearestCampfire = nil
                sleep = 300
            end
        end

        Wait(sleep)
    end
end)

CreateThread(function()
    if not GetCampfireConfig().Enabled then return end
    Wait(3000)

    local campfiresList = lib.callback.await("qs-fisher:getCampfires", false) or {}
    for _, fireData in ipairs(campfiresList) do
        AddOrUpdateCampfire(fireData)
    end
end)

AddEventHandler("onResourceStop", function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end

    ExitCookingSession(true)
    CloseCampfireMenu()

    if buildConfirmCallback then
        buildConfirmCallback = nil
        SetNuiFocus(false, false)
    end

    if isBuildingCampfire then
        isBuildingCampfire = false
        local ped = PlayerPedId()
        if DoesEntityExist(ped) then
            FreezeEntityPosition(ped, false)
            ClearPedTasks(ped)
        end
    end

    for fireId in pairs(activeCampfires) do
        RemoveCampfire(fireId)
    end
end)
--WKLeaksjdOn-rTop_c : https://discord.gg/zqcBffbMZn
--WKLeak_a5On9EToplg : https://discord.gg/zqcBffbMZn
--WKLeakzqOnK1Top-N : https://discord.gg/zqcBffbMZn
--WKLeak-siOnjVTopZI : https://discord.gg/zqcBffbMZn
--WKLeak_nrOnNuTopKH : https://discord.gg/zqcBffbMZn
