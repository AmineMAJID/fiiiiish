--[[   -- https://discord.gg/zqcBffbMZn ]]
local LocalCrabTraps = {}
local STREAM_DISTANCE = 180.0
local NearestTrap = nil
local TargetTrap = nil

local MAX_PULL_DIST = 3.5
local MAX_PLACE_DIST = 12.0
local MIN_TRAP_SPACING = 20.0

local TRAP_PROPS = {
    Cage = "xm_prop_x17_chest_closed",
    Buoy = "prop_dock_float_1",
    Float = 0.35,
    Anim = {
        dict = "anim@amb@clubhouse@tutorial@bkr_tut_ig3@",
        clip = "machinic_loop_mechandplayer",
        duration = 2500
    }
}

local IsPulling = false
local ActiveTrapUI = nil
local IsPlacing = false

function GetCrabTrapsConfig()
    return Config.CrabTraps or {}
end

function LoadModelSafe(model)
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

function ClearTrapEntities(trap)
    ClearTargetForTrap(trap)
    if trap.rope then
        DeleteRope(trap.rope)
        trap.rope = nil
    end
    if trap.buoy and DoesEntityExist(trap.buoy) then
        DeleteEntity(trap.buoy)
    end
    if trap.cage and DoesEntityExist(trap.cage) then
        DeleteEntity(trap.cage)
    end
    trap.buoy = nil
    trap.cage = nil
end

function SpawnTrapEntities(trap)
    if trap.buoy and DoesEntityExist(trap.buoy) then
        return true
    end

    local buoyModel = joaat(TRAP_PROPS.Buoy)
    local cageModel = joaat(TRAP_PROPS.Cage)
    if not LoadModelSafe(buoyModel) or not LoadModelSafe(cageModel) then
        return false
    end

    local buoyZ = trap.waterZ + TRAP_PROPS.Float
    local buoyObj = CreateObject(buoyModel, trap.x, trap.y, buoyZ, false, false, false)
    local cageObj = CreateObject(cageModel, trap.x, trap.y, trap.seaZ, false, false, false)

    trap.buoy = buoyObj
    trap.cage = cageObj

    SetModelAsNoLongerNeeded(buoyModel)
    SetModelAsNoLongerNeeded(cageModel)

    if DoesEntityExist(buoyObj) then
        SetEntityCollision(buoyObj, false, false)
        FreezeEntityPosition(buoyObj, true)
    end

    if DoesEntityExist(cageObj) then
        FreezeEntityPosition(cageObj, true)
        SetEntityHeading(cageObj, math.random(0, 359) + 0.0)
    end

    RopeLoadTextures()
    if RopeAreTexturesLoaded() and DoesEntityExist(buoyObj) and DoesEntityExist(cageObj) then
        local buoyPos = vector3(trap.x, trap.y, buoyZ)
        local cagePos = vector3(trap.x, trap.y, trap.seaZ)
        local ropeLen = math.max(#(buoyPos - cagePos), 1.0)
        local rope = AddRope(buoyPos.x, buoyPos.y, buoyPos.z, 0.0, 0.0, 0.0, ropeLen + 2.0, 5, ropeLen, ropeLen, 0.5, true, true, true, 1.0, false, 0)
        trap.rope = rope

        if rope and rope ~= 0 then
            AttachEntitiesToRope(rope, buoyObj, cageObj, buoyPos.x, buoyPos.y, buoyPos.z, cagePos.x, cagePos.y, cagePos.z, ropeLen, false, false, 0, 0)
            RopeForceLength(rope, ropeLen)
        else
            trap.rope = nil
        end
    end

    return true
end

function CreateTrapBlip(trap)
    if trap.blip or not trap.mine then
        return
    end

    local blipCfg = (GetCrabTrapsConfig().Blip) or {}
    local blip = AddBlipForCoord(trap.x, trap.y, trap.waterZ)
    trap.blip = blip

    SetBlipSprite(blip, blipCfg.sprite or 371)
    SetBlipColour(blip, blipCfg.color or 47)
    SetBlipScale(blip, blipCfg.scale or 0.7)
    SetBlipAsShortRange(blip, false)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString(Lang("CRABTRAP_BLIP"))
    EndTextCommandSetBlipName(blip)
end

function RemoveTrapBlip(trap)
    if trap.blip and DoesBlipExist(trap.blip) then
        RemoveBlip(trap.blip)
    end
    trap.blip = nil
end

function DeleteLocalTrap(id)
    local trap = LocalCrabTraps[id]
    if not trap then
        return
    end

    if NearestTrap and NearestTrap.id == id then
        NearestTrap = nil
    end
    if TargetTrap and TargetTrap.id == id then
        TargetTrap = nil
    end

    ClearTrapEntities(trap)
    RemoveTrapBlip(trap)
    LocalCrabTraps[id] = nil
end

function SyncLocalTrap(data)
    if not data or not data.id then
        return
    end

    DeleteLocalTrap(data.id)
    local trap = {
        id = data.id,
        x = data.x,
        y = data.y,
        seaZ = data.seaZ,
        waterZ = data.waterZ,
        mine = (data.mine == true),
        toFull = data.toFull or 0,
        toBreak = data.toBreak or 0,
        fullness = data.fullness or 0,
        readAt = GetGameTimer()
    }

    LocalCrabTraps[data.id] = trap
    CreateTrapBlip(trap)
end

RegisterNetEvent("qs-fisher:crabTrapAdded", function(data)
    SyncLocalTrap(data)
    CreateThread(function()
        local res = lib.callback.await("qs-fisher:getCrabTrap", false, data.id)
        if res and LocalCrabTraps[data.id] then
            LocalCrabTraps[data.id].mine = (res.mine == true)
            CreateTrapBlip(LocalCrabTraps[data.id])
        end
    end)
end)

RegisterNetEvent("qs-fisher:crabTrapRemoved", function(id)
    DeleteLocalTrap(id)
end)

CreateThread(function()
    while true do
        if not next(LocalCrabTraps) then
            Wait(1000)
        else
            local pCoords = GetEntityCoords(PlayerPedId())
            for _, trap in pairs(LocalCrabTraps) do
                local dist = #(vector3(trap.x, trap.y, trap.waterZ) - pCoords)
                if dist <= STREAM_DISTANCE then
                    SpawnTrapEntities(trap)
                elseif trap.buoy then
                    ClearTrapEntities(trap)
                end
            end
            Wait(1500)
        end
    end
end)

function CalculateTimeRemaining(trap, key)
    local elapsed = (GetGameTimer() - (trap.readAt or 0)) / 1000
    local remaining = (trap[key] or 0) - elapsed
    return math.max(remaining, 0)
end

function RefreshTrapData(trap)
    local res = lib.callback.await("qs-fisher:getCrabTrap", false, trap.id)
    if not res or not LocalCrabTraps[trap.id] then
        return
    end

    trap.mine = (res.mine == true)
    trap.toFull = res.toFull or 0
    trap.toBreak = res.toBreak or 0
    trap.fullness = res.fullness or 0
    trap.band = res.band
    trap.depth = res.depth
    trap.readAt = GetGameTimer()

    CreateTrapBlip(trap)
end

function PullCrabTrap(trap, isDismantle)
    if IsPulling then
        return
    end

    IsPulling = true
    local res = lib.callback.await("qs-fisher:pullCrabTrap", false, trap.id, isDismantle == true)
    IsPulling = false

    if not res or not res.ok then
        local reason = (res and res.reason) or "bad"
        if reason == "notyours" then
            CreateNotification("notify", "error", Lang("CRABTRAP_NOT_YOURS"))
        elseif reason == "far" then
            CreateNotification("notify", "error", Lang("CRABTRAP_TOO_FAR"))
        elseif reason == "gone" then
            CreateNotification("notify", "error", Lang("CRABTRAP_GONE"))
        else
            CreateNotification("notify", "error", Lang("CRABTRAP_FAILED"))
        end
        return
    end

    if res.dismantle then
        if res.broke then
            CreateNotification("notify", "error", Lang("CRABTRAP_PACKED_BROKE"))
        else
            CreateNotification("notify", "success", Lang("CRABTRAP_PACKED"))
        end
        return
    end

    CreateNotification("notify", "success", string.format(Lang("CRABTRAP_PULLED"), res.caught or 0, res.full or 0))

    if res.broke then
        CreateNotification("notify", "error", Lang("CRABTRAP_CAGE_BROKE"))
    end
    if res.missing then
        CreateNotification("notify", "error", string.format(Lang("NOTIFY_ITEM_DOES_NOT_EXIST"), res.missing))
    end
    if res.room == false then
        CreateNotification("notify", "error", Lang("NOTIFY_INVENTORY_FULL"))
    end
end

function CloseCrabTrapUI()
    if not ActiveTrapUI then
        return
    end
    ActiveTrapUI = nil
    SetNuiFocus(false, false)
    SendNUIMessage({ action = "crabTrap", show = false })
end

function OpenCrabTrapUI(trap)
    if ActiveTrapUI or IsPulling then
        return
    end

    RefreshTrapData(trap)
    ActiveTrapUI = trap
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = "crabTrap",
        show = true,
        id = trap.id,
        fullness = trap.fullness or 0,
        toFull = CalculateTimeRemaining(trap, "toFull"),
        toBreak = CalculateTimeRemaining(trap, "toBreak"),
        band = trap.band,
        depth = trap.depth,
        mine = (trap.mine == true)
    })
end

RegisterNUICallback("crabTrapClose", function(data, cb)
    cb("ok")
    CloseCrabTrapUI()
end)

RegisterNUICallback("crabTrapAction", function(data, cb)
    cb("ok")
    local trap = ActiveTrapUI
    CloseCrabTrapUI()
    if not trap then
        return
    end

    CreateThread(function()
        PullCrabTrap(trap, data and data.dismantle == true)
    end)
end)

function AddTargetForTrap(trap)
    if not Config.Target or not trap.buoy or trap.targeted then
        return
    end
    trap.targeted = true

    local targetPos = vector3(trap.x, trap.y, trap.waterZ + TRAP_PROPS.Float)

    if Config.TargetScript == "ox" then
        trap.zone = exports.ox_target:addSphereZone({
            coords = targetPos,
            radius = MAX_PULL_DIST,
            options = {
                {
                    name = "qs-fisher:crabTrap" .. trap.id,
                    label = Lang("TARGET_CRABTRAP_OPEN"),
                    icon = "fa-solid fa-box-archive",
                    distance = MAX_PULL_DIST,
                    onSelect = function()
                        CreateThread(function()
                            OpenCrabTrapUI(trap)
                        end)
                    end,
                    canInteract = function()
                        return trap.mine == true
                    end
                }
            }
        })
    elseif Config.TargetScript == "qb" then
        trap.zone = "qs-fisher:crabTrap" .. trap.id
        exports["qb-target"]:AddCircleZone(trap.zone, targetPos, MAX_PULL_DIST, {
            name = trap.zone,
            useZ = true
        }, {
            options = {
                {
                    num = 1,
                    label = Lang("TARGET_CRABTRAP_OPEN"),
                    icon = "fa-solid fa-box-archive",
                    action = function()
                        CreateThread(function()
                            OpenCrabTrapUI(trap)
                        end)
                    end,
                    canInteract = function()
                        return trap.mine == true
                    end
                }
            },
            distance = MAX_PULL_DIST
        })
    end
end

function ClearTargetForTrap(trap)
    if not trap or not trap.targeted then
        return
    end

    local zone = trap.zone
    trap.targeted = nil
    trap.zone = nil

    if not zone then
        return
    end

    if Config.TargetScript == "ox" then
        exports.ox_target:removeZone(zone)
    elseif Config.TargetScript == "qb" then
        exports["qb-target"]:RemoveZone(zone)
    end
end

CreateThread(function()
    local lastCheck = 0
    while true do
        local sleep = 1000
        if next(LocalCrabTraps) then
            local now = GetGameTimer()
            if (now - lastCheck) >= 200 then
                lastCheck = now
                local pCoords = GetEntityCoords(PlayerPedId())
                local closestTrap = nil
                local closestDist = MAX_PULL_DIST

                for _, trap in pairs(LocalCrabTraps) do
                    if trap.buoy and DoesEntityExist(trap.buoy) then
                        AddTargetForTrap(trap)
                        local dist = #(vector3(trap.x, trap.y, trap.waterZ) - pCoords)
                        if dist <= closestDist then
                            closestDist = dist
                            closestTrap = trap
                        end
                    end
                end
                TargetTrap = closestTrap
            end

            local activeTrap = TargetTrap
            if activeTrap then
                sleep = 0
                if NearestTrap ~= activeTrap then
                    NearestTrap = activeTrap
                    RefreshTrapData(activeTrap)
                end

                if not Config.Target and not ActiveTrapUI then
                    local textZ = activeTrap.waterZ + TRAP_PROPS.Float + 0.6
                    if activeTrap.mine then
                        if Config.DrawText3D then
                            local keyLabel = (Config.Keys and Config.Keys.InteractKeyLabel) or "E"
                            DrawText3D(activeTrap.x, activeTrap.y, textZ, Lang("CRABTRAP_PROMPT"), "crabtrap_" .. activeTrap.id, keyLabel)
                        end
                        local interactKey = (Config.Keys and Config.Keys.InteractKey) or 38
                        if IsControlJustReleased(0, interactKey) then
                            CreateThread(function()
                                OpenCrabTrapUI(activeTrap)
                            end)
                        end
                    else
                        if Config.DrawText3D then
                            DrawText3D(activeTrap.x, activeTrap.y, textZ, Lang("CRABTRAP_SOMEONE_ELSE"), "crabtrap_" .. activeTrap.id, "")
                        end
                    end
                end
            else
                NearestTrap = nil
                sleep = 300
            end
        end
        Wait(sleep)
    end
end)

function PlaceCrabTrap()
    if not GetCrabTrapsConfig().Enabled or IsPlacing then
        return
    end

    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped then
        CreateNotification("notify", "error", Lang("CRABTRAP_DRIVING"))
        return
    end

    if GetCrabTrapsConfig().RequireBoat == true and not OnBoat(ped) then
        CreateNotification("notify", "error", Lang("CRABTRAP_NEED_BOAT"))
        return
    end

    local pCoords = GetEntityCoords(ped)
    local probeCoords = GetOffsetFromEntityInWorldCoords(ped, 0.0, 2.0, 0.0)

    local hasWater, waterZ = GetWaterHeight(probeCoords.x, probeCoords.y, pCoords.z)
    if not hasWater then
        hasWater, waterZ = TestVerticalProbeAgainstAllWater(probeCoords.x, probeCoords.y, pCoords.z + 10.0, 0)
    end

    if not hasWater or not waterZ then
        CreateNotification("notify", "error", Lang("CRABTRAP_NEED_WATER"))
        return
    end

    if OnDryLand(ped, waterZ) then
        CreateNotification("notify", "error", Lang("CRABTRAP_ON_STRUCTURE"))
        return
    end

    local depth = DepthAt and DepthAt(probeCoords.x, probeCoords.y, waterZ)
    if not depth or depth <= 0 then
        CreateNotification("notify", "error", Lang("CRABTRAP_NO_BOTTOM"))
        return
    end

    local minDepth = tonumber(GetCrabTrapsConfig().MinDepth) or 10.0
    if depth < minDepth then
        CreateNotification("notify", "error", string.format(Lang("CRABTRAP_TOO_SHALLOW"), string.format("%.1f", depth), string.format("%.0f", minDepth)))
        return
    end

    local band = (DepthBandAt and DepthBandAt(depth)) or "deep"
    local animCfg = TRAP_PROPS.Anim
    if animCfg.dict and animCfg.clip then
        IsPlacing = true
        RequestAnimDict(animCfg.dict)
        local animTimeout = GetGameTimer() + 2000
        while not HasAnimDictLoaded(animCfg.dict) and GetGameTimer() < animTimeout do
            Wait(0)
        end

        if HasAnimDictLoaded(animCfg.dict) then
            local duration = animCfg.duration or 2500
            TaskPlayAnim(ped, animCfg.dict, animCfg.clip, 4.0, -4.0, duration, 49, 0, false, false, false)
            Wait(duration)
            ClearPedTasks(ped)
        end
        IsPlacing = false

        ped = PlayerPedId()
        if GetCrabTrapsConfig().RequireBoat == true and not OnBoat(ped) then
            CreateNotification("notify", "error", Lang("CRABTRAP_NEED_BOAT"))
            return
        end
        if OnDryLand(ped, waterZ) then
            CreateNotification("notify", "error", Lang("CRABTRAP_ON_STRUCTURE"))
            return
        end
    end

    local res = lib.callback.await("qs-fisher:placeCrabTrap", false, {
        x = probeCoords.x,
        y = probeCoords.y,
        waterZ = waterZ,
        depth = depth,
        band = band
    })

    if not res or not res.ok then
        local reason = (res and res.reason) or "bad"
        if reason == "limit" then
            CreateNotification("notify", "error", string.format(Lang("CRABTRAP_LIMIT"), res.limit or 1))
        elseif reason == "level" then
            CreateNotification("notify", "error", string.format(Lang("CRABTRAP_NEED_LEVEL"), res.level or 1))
        elseif reason == "crowded" then
            CreateNotification("notify", "error", Lang("CRABTRAP_CROWDED"))
        elseif reason == "shallow" then
            CreateNotification("notify", "error", string.format(Lang("CRABTRAP_TOO_SHALLOW"), string.format("%.1f", depth), string.format("%.0f", minDepth)))
        elseif reason == "noitem" then
            CreateNotification("notify", "error", Lang("CRABTRAP_NO_ITEM"))
        elseif reason == "far" then
            CreateNotification("notify", "error", Lang("CRABTRAP_TOO_FAR"))
        else
            CreateNotification("notify", "error", Lang("CRABTRAP_FAILED"))
        end
        return
    end

    CreateNotification("notify", "success", string.format(Lang("CRABTRAP_PLACED"), string.format("%.0f", depth), res.left or 0))
end

exports("useCrabTrap", PlaceCrabTrap)
RegisterNetEvent("qs-fisher:useCrabTrap", PlaceCrabTrap)

CreateThread(function()
    if not GetCrabTrapsConfig().Enabled then
        return
    end
    Wait(3000)
    local traps = lib.callback.await("qs-fisher:getCrabTraps", false) or {}
    for _, trapData in ipairs(traps) do
        SyncLocalTrap(trapData)
    end
end)

AddEventHandler("onResourceStop", function(resourceName)
    if GetCurrentResourceName() ~= resourceName then
        return
    end
    for id in pairs(LocalCrabTraps) do
        DeleteLocalTrap(id)
    end
end)
--WKLeak-5NOnqaTop9n : https://discord.gg/zqcBffbMZn
--WKLeak-ksOneITop3b : https://discord.gg/zqcBffbMZn
--WKLeaksxbOnLQTop5M : https://discord.gg/zqcBffbMZn
--WKLeak-rCOn48Toprr : https://discord.gg/zqcBffbMZn
--WKLeak_PBOn7LTop@K : https://discord.gg/zqcBffbMZn
