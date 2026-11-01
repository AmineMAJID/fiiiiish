--[[   -- https://discord.gg/zqcBffbMZn ]]
function GetSpeargunConfig()
    return Config.Speargun or {}
end

SpeargunConfig = {
    Prop = "custom_fishing_speargun",
    Bone = 28422,
    Offset = vec3(0.08, 0.0, 0.0),
    Rotation = vec3(715.0, -290.0, -610.0),
    AimOffset = vec3(0.02, -0.03, -0.01),
    AimRotation = vec3(710.0, -985.0, -630.0),
    Spear = "custom_fishing_spear_shaft",
    SinkInto = {
        bone = 0,
        offset = vec3(0.44, 0.12, 0.07),
        rotation = vec3(-735.0, -245.0, -1310.0)
    },
    Line = {
        Slack = 0.08,
        MuzzleOffset = vec3(0.0, -0.95, 0.08),
        MuzzleForward = 0.05,
        SpearTail = 0.35,
        R = 235,
        G = 235,
        B = 225,
        A = 200
    },
    Aim = {
        Pose = "upper",
        AimProp = true,
        FollowCamera = false,
        Zoom = 12.0,
        EaseMs = 220,
        Try = {
            { dict = "weapons@first_person@aim_idle@generic@heavy@rpg@", clip = "aim_med_loop" },
            { dict = "anim@heists@box_carry@", clip = "idle" }
        }
    },
    FlightSpeed = 37.5,
    FlightMinMs = 140,
    HarvestReach = 6.0,
    Replicate = 120.0,
    CruiseSpeed = 2.2,
    FleeDistance = 55.0,
    HarvestAnim = {
        dict = "anim@heists@ornate_bank@grab_cash",
        clip = "grab"
    },
    TankAnim = {
        dict = "clothingshirt",
        clip = "try_shirt_positive_d"
    }
}

IsSpeargunEquipped = false
IsAimingSpeargun = false
SpeargunEntity = nil
SpearAmmo = 0
IsFiringSpear = false
NextFireAllowedAt = 0
CooldownDurationMs = 1800
MissLifetimeSec = 8
SharkSenseRange = 28.0
FleeDurationSec = 8.0

ActiveSharkHunt = nil
HuntRadiusBlip = nil
HuntCenterBlip = nil
ActiveSharkEntities = {}
ActivePlayerSpears = {}
RemoteSpearguns = {}
RemoteSpears = {}

AimCamera = nil
AimTargetFov = nil
AimAnimDict = nil
AimAnimClip = nil
IsAimAnimPlaying = false
LastAimPropPitch = nil
LastAimPropState = nil
LastHudState = nil
LastHudAmmo = nil

IsHarvesting = false
HasScubaTankEquipped = false
ScubaTankProp = nil
ScubaMaskProp = nil
RemainingOxygen = 0
IsOxygenHudVisible = false
HasOxygenLowWarned = false

function SpeargunIsOut()
    return IsSpeargunEquipped
end

function OnSharkHunt()
    return ActiveSharkHunt ~= nil
end

function IsPedUnderwater(ped)
    return IsPedSwimmingUnderWater(ped or PlayerPedId())
end

function GetCameraForwardDirection()
    local rot = GetGameplayCamRot(2)
    local rotZ = math.rad(rot.z)
    local rotX = math.rad(rot.x)
    local cosPitch = math.abs(math.cos(rotX))
    return vec3(-math.sin(rotZ) * cosPitch, math.cos(rotZ) * cosPitch, math.sin(rotX))
end

function GetPlayerPedFromServerIdSafe(serverId)
    local clientPlayer = GetPlayerFromServerId(serverId)
    if clientPlayer == -1 then
        return nil
    end
    local ped = GetPlayerPed(clientPlayer)
    if ped ~= 0 and DoesEntityExist(ped) then
        return ped
    end
    return nil
end

function DeleteRemoteSpeargun(serverId)
    local prop = RemoteSpearguns[serverId]
    if prop and DoesEntityExist(prop) then
        DetachEntity(prop, true, true)
        DeleteEntity(prop)
    end
    RemoteSpearguns[serverId] = nil
end

function DeleteRemoteSpear(serverId)
    local item = RemoteSpears[serverId]
    if item and item.prop and DoesEntityExist(item.prop) then
        DetachEntity(item.prop, true, true)
        DeleteEntity(item.prop)
    end
    RemoteSpears[serverId] = nil
end

function ClearAllRemoteEntities()
    for serverId in pairs(RemoteSpearguns) do
        DeleteRemoteSpeargun(serverId)
    end
    for serverId in pairs(RemoteSpears) do
        DeleteRemoteSpear(serverId)
    end
end

function StowSpeargunProp()
    UnloadSpeargunAssets()
    if SpeargunEntity and DoesEntityExist(SpeargunEntity) then
        DetachEntity(SpeargunEntity, true, true)
        DeleteEntity(SpeargunEntity)
    end
    SpeargunEntity = nil
    IsSpeargunEquipped = false
    IsAimingSpeargun = false
    TriggerServerEvent("qs-fisher:spearGunDrawn", false)
    SendNUIMessage({
        action = "spearHud",
        show = false
    })
end

function DrawSpeargunProp()
    local modelHash = joaat(SpeargunConfig.Prop)
    if not IsModelInCdimage(modelHash) then
        print(string.format("^1[qs-fishingjob]^0 the model %s is not in the game. Start qs-fishing-props.", SpeargunConfig.Prop))
        return false, "noprops"
    end

    RequestModel(modelHash)
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(modelHash) do
        if GetGameTimer() > timeout then
            return false, "slow"
        end
        Wait(0)
    end

    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    SpeargunEntity = CreateObject(modelHash, playerCoords.x, playerCoords.y, playerCoords.z, false, false, false)
    SetModelAsNoLongerNeeded(modelHash)

    if not DoesEntityExist(SpeargunEntity) then
        return false, "slow"
    end

    SetEntityCollision(SpeargunEntity, false, false)
    local offset = SpeargunConfig.Offset
    local rotation = SpeargunConfig.Rotation
    local boneIndex = GetPedBoneIndex(playerPed, SpeargunConfig.Bone)

    AttachEntityToEntity(SpeargunEntity, playerPed, boneIndex, offset.x, offset.y, offset.z, rotation.x, rotation.y, rotation.z, false, false, false, false, 2, true)
    TriggerServerEvent("qs-fisher:spearGunDrawn", true)
    return true
end

function GetSpeargunMuzzleWorldCoords()
    if SpeargunEntity and DoesEntityExist(SpeargunEntity) then
        local offset = SpeargunConfig.Line.MuzzleOffset
        return GetOffsetFromEntityInWorldCoords(SpeargunEntity, offset.x, offset.y, offset.z)
    end
    return GetEntityCoords(PlayerPedId())
end

function GetSpearTailWorldCoords(spearProp)
    if not spearProp or not DoesEntityExist(spearProp) then
        return nil
    end
    local tailOffset = SpeargunConfig.Line.SpearTail
    if tailOffset == 0.0 then
        return GetEntityCoords(spearProp)
    end
    return GetOffsetFromEntityInWorldCoords(spearProp, 0.0, -tailOffset, 0.0)
end

function StartAimCamera()
    if AimCamera then
        return
    end
    local gameplayFov = GetGameplayCamFov() or 50.0
    AimTargetFov = math.max(gameplayFov - (SpeargunConfig.Aim.Zoom or 12.0), 15.0)

    AimCamera = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)
    SetCamCoord(AimCamera, GetGameplayCamCoord())
    SetCamRot(AimCamera, GetGameplayCamRot(2), 2)
    SetCamFov(AimCamera, AimTargetFov)
    SetCamActive(AimCamera, true)
    RenderScriptCams(true, true, SpeargunConfig.Aim.EaseMs or 220, true, true)
end

function UpdateAimCamera()
    if not AimCamera then
        return
    end
    SetCamCoord(AimCamera, GetGameplayCamCoord())
    SetCamRot(AimCamera, GetGameplayCamRot(2), 2)
end

function StopAimCamera()
    if not AimCamera then
        return
    end
    local easeDuration = SpeargunConfig.Aim.EaseMs or 220
    local camToDestroy = AimCamera
    AimCamera = nil

    RenderScriptCams(false, true, easeDuration, true, true)
    CreateThread(function()
        Wait(easeDuration + 50)
        if DoesCamExist(camToDestroy) then
            DestroyCam(camToDestroy, false)
        end
    end)
end

function GetAimAnimFlags()
    if SpeargunConfig.Aim.Pose == "full" then
        return 1
    end
    return 49
end

function StartAimAnimation()
    if not AimAnimDict or SpeargunConfig.Aim.Pose == "none" then
        return
    end
    local playerPed = PlayerPedId()
    if not IsEntityPlayingAnim(playerPed, AimAnimDict, AimAnimClip, 3) then
        TaskPlayAnim(playerPed, AimAnimDict, AimAnimClip, 4.0, -4.0, -1, GetAimAnimFlags(), 0.0, false, false, false)
    end
    IsAimAnimPlaying = true
end

function StopAimAnimation()
    if not IsAimAnimPlaying then
        return
    end
    IsAimAnimPlaying = false
    if AimAnimDict then
        StopAnimTask(PlayerPedId(), AimAnimDict, AimAnimClip, 2.0)
    end
end

function UpdateSpeargunAttachment(isAiming)
    if SpeargunConfig.Aim.AimProp == false then
        return
    end
    if not SpeargunEntity or not DoesEntityExist(SpeargunEntity) then
        return
    end

    local playerPed = PlayerPedId()
    local rot = isAiming and (SpeargunConfig.AimRotation or SpeargunConfig.Rotation) or SpeargunConfig.Rotation
    local offset = isAiming and (SpeargunConfig.AimOffset or SpeargunConfig.Offset) or SpeargunConfig.Offset

    local pitch = (isAiming and SpeargunConfig.Aim.FollowCamera == true) and (GetGameplayCamRot(2).x or 0.0) or 0.0
    if LastAimPropState == isAiming and LastAimPropPitch and math.abs(pitch - LastAimPropPitch) < 1.0 then
        return
    end

    LastAimPropPitch = pitch
    LastAimPropState = isAiming
    local boneIndex = GetPedBoneIndex(playerPed, SpeargunConfig.Bone)
    AttachEntityToEntity(SpeargunEntity, playerPed, boneIndex, offset.x, offset.y, offset.z, rot.x + pitch, rot.y, rot.z, false, false, false, false, 2, true)
end

function PreloadSpeargunAssets()
    local spearModel = joaat(SpeargunConfig.Spear)
    RequestModel(spearModel)
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(spearModel) do
        if GetGameTimer() > timeout then
            break
        end
        Wait(0)
    end

    AimAnimDict = nil
    AimAnimClip = nil
    for _, animOption in ipairs(SpeargunConfig.Aim.Try or {}) do
        RequestAnimDict(animOption.dict)
        local animTimeout = GetGameTimer() + 2000
        while not HasAnimDictLoaded(animOption.dict) do
            if GetGameTimer() > animTimeout then
                break
            end
            Wait(0)
        end
        if HasAnimDictLoaded(animOption.dict) then
            local duration = GetAnimDuration(animOption.dict, animOption.clip) or 0.0
            if duration > 0.0 then
                AimAnimDict = animOption.dict
                AimAnimClip = animOption.clip
                break
            else
                RemoveAnimDict(animOption.dict)
            end
        end
    end
end

function UnloadSpeargunAssets()
    SetModelAsNoLongerNeeded(joaat(SpeargunConfig.Spear))
    StopAimAnimation()
    StopAimCamera()
    LastAimPropPitch = nil
    if AimAnimDict then
        RemoveAnimDict(AimAnimDict)
        AimAnimDict = nil
        AimAnimClip = nil
    end
end

function UpdateSpearHud(state)
    if not IsSpeargunEquipped then
        if LastHudState ~= nil then
            LastHudState = nil
            LastHudAmmo = nil
            SendNUIMessage({
                action = "spearHud",
                show = false
            })
        end
        return
    end

    state = state or "ready"
    if state == LastHudState and SpearAmmo == LastHudAmmo then
        return
    end

    LastHudState = state
    LastHudAmmo = SpearAmmo
    SendNUIMessage({
        action = "spearHud",
        show = true,
        ammo = SpearAmmo,
        state = state,
        key = Config.Keys.InteractKeyLabel or "E"
    })
end

function SpawnSpearProjectile(coords)
    local spearModel = joaat(SpeargunConfig.Spear)
    if not HasModelLoaded(spearModel) then
        RequestModel(spearModel)
        return nil
    end

    local prop = CreateObject(spearModel, coords.x, coords.y, coords.z, false, false, false)
    if not DoesEntityExist(prop) then
        return nil
    end

    SetEntityCollision(prop, false, false)
    local spearData = {
        prop = prop,
        at = coords
    }
    ActivePlayerSpears[#ActivePlayerSpears + 1] = spearData
    return spearData
end

function DrawCableLine(p1, p2, r, g, b, a)
    DrawLine(p1.x, p1.y, p1.z, p2.x, p2.y, p2.z, r, g, b, a)
    DrawLine(p1.x, p1.y, p1.z + 0.02, p2.x, p2.y, p2.z + 0.02, r, g, b, a)
    DrawLine(p1.x + 0.02, p1.y, p1.z, p2.x + 0.02, p2.y, p2.z, r, g, b, a)
end

function DrawCatenaryRope(fromCoords, toCoords, slackFraction)
    local lineConf = SpeargunConfig.Line
    local r, g, b, a = lineConf.R, lineConf.G, lineConf.B, lineConf.A
    local dist = #(toCoords - fromCoords)
    if dist < 0.05 then
        return
    end

    local totalSlack = (slackFraction or 0.0) * dist * (lineConf.Slack or 0.08)
    if totalSlack <= 0.001 then
        return DrawCableLine(fromCoords, toCoords, r, g, b, a)
    end

    local segments = 6
    local lastPoint = fromCoords
    for i = 1, segments do
        local fraction = i / segments
        local sag = math.sin(fraction * math.pi) * totalSlack
        local currentPoint = vec3(
            fromCoords.x + (toCoords.x - fromCoords.x) * fraction,
            fromCoords.y + (toCoords.y - fromCoords.y) * fraction,
            fromCoords.z + (toCoords.z - fromCoords.z) * fraction - sag
        )
        DrawCableLine(lastPoint, currentPoint, r, g, b, a)
        lastPoint = currentPoint
    end
end

function CheckSpearFlightCollision(spearData, startCoords)
    if not spearData or not spearData.prop or not DoesEntityExist(spearData.prop) then
        return
    end
    local currentPos = GetEntityCoords(spearData.prop)
    local probeRay = StartShapeTestCapsule(spearData.at.x, spearData.at.y, spearData.at.z, currentPos.x, currentPos.y, currentPos.z, 0.06, 12, PlayerPedId(), 4)
    local status, hit, hitCoords, _, hitEntity = GetShapeTestResult(probeRay)

    if hit == 1 then
        if hitEntity ~= 0 and DoesEntityExist(hitEntity) and ActiveSharkEntities[hitEntity] then
            spearData.hitShark = hitEntity
        end
    end
    spearData.at = currentPos
end

function OnSpearLandedWorld(spearData)
    if not spearData or not spearData.prop or not DoesEntityExist(spearData.prop) then
        return
    end
    spearData.landed = true
end

function AttachSpearToTarget(spearData, targetEntity)
    if not spearData or not spearData.prop or not DoesEntityExist(spearData.prop) then
        return
    end
    if not targetEntity or not DoesEntityExist(targetEntity) then
        return
    end

    local sinkConf = SpeargunConfig.SinkInto
    local offset = sinkConf.offset or vec3(0.0, 0.55, 0.28)
    local rotation = sinkConf.rotation or vec3(-55.0, 0.0, 0.0)
    local boneIndex = GetPedBoneIndex(targetEntity, tonumber(sinkConf.bone) or 0)

    AttachEntityToEntity(spearData.prop, targetEntity, boneIndex, offset.x, offset.y, offset.z, rotation.x, rotation.y, rotation.z, false, false, false, false, 2, true)
    SetEntityLodDist(spearData.prop, 300)
    spearData.shark = targetEntity
end

function DeleteSpear(spearData)
    if not spearData then
        return
    end
    spearData.landed = false
    if spearData.prop and DoesEntityExist(spearData.prop) then
        DetachEntity(spearData.prop, true, true)
        DeleteEntity(spearData.prop)
    end
    spearData.prop = nil

    for i = #ActivePlayerSpears, 1, -1 do
        if ActivePlayerSpears[i] == spearData then
            table.remove(ActivePlayerSpears, i)
        end
    end
    TriggerServerEvent("qs-fisher:spearCleared")
end

RegisterNetEvent("qs-fisher:remoteSpearGun", function(serverId, isDrawn)
    local id = tonumber(serverId)
    if not id or id == GetPlayerServerId(PlayerId()) then
        return
    end

    if not isDrawn then
        return DeleteRemoteSpeargun(id)
    end
    if RemoteSpearguns[id] then
        return
    end

    local targetPed = GetPlayerPedFromServerIdSafe(id)
    if not targetPed then
        return
    end

    local modelHash = joaat(SpeargunConfig.Prop)
    RequestModel(modelHash)
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(modelHash) do
        if GetGameTimer() > timeout then
            return
        end
        Wait(0)
    end

    targetPed = GetPlayerPedFromServerIdSafe(id)
    if not targetPed or RemoteSpearguns[id] then
        SetModelAsNoLongerNeeded(modelHash)
        return
    end

    local coords = GetEntityCoords(targetPed)
    local prop = CreateObject(modelHash, coords.x, coords.y, coords.z, false, false, false)
    SetModelAsNoLongerNeeded(modelHash)

    if not DoesEntityExist(prop) then
        return
    end

    SetEntityCollision(prop, false, false)
    local offset = SpeargunConfig.Offset
    local rot = SpeargunConfig.Rotation
    local boneIndex = GetPedBoneIndex(targetPed, SpeargunConfig.Bone)

    AttachEntityToEntity(prop, targetPed, boneIndex, offset.x, offset.y, offset.z, rot.x, rot.y, rot.z, false, false, false, false, 2, true)
    RemoteSpearguns[id] = prop
end)

RegisterNetEvent("qs-fisher:remoteSpearFired", function(serverId, fromX, fromY, fromZ, toX, toY, toZ, flightMs)
    local id = tonumber(serverId)
    if not id or id == GetPlayerServerId(PlayerId()) then
        return
    end

    local fromPos = vec3(tonumber(fromX) or 0.0, tonumber(fromY) or 0.0, tonumber(fromZ) or 0.0)
    local toPos = vec3(tonumber(toX) or 0.0, tonumber(toY) or 0.0, tonumber(toZ) or 0.0)

    DeleteRemoteSpear(id)
    local modelHash = joaat(SpeargunConfig.Spear)
    RequestModel(modelHash)
    local timeout = GetGameTimer() + 3000
    while not HasModelLoaded(modelHash) do
        if GetGameTimer() > timeout then
            return
        end
        Wait(0)
    end

    local prop = CreateObject(modelHash, fromPos.x, fromPos.y, fromPos.z, false, false, false)
    SetModelAsNoLongerNeeded(modelHash)
    if not DoesEntityExist(prop) then
        return
    end

    SetEntityCollision(prop, false, false)
    SetEntityRotation(prop, 0.0, 0.0, GetEntityHeading(prop), 2, true)

    RemoteSpears[id] = {
        prop = prop,
        from = fromPos,
        to = toPos,
        startedAt = GetGameTimer(),
        flight = math.max(tonumber(flightMs) or 140, 1),
        landed = false
    }
end)

RegisterNetEvent("qs-fisher:remoteSpearCleared", function(serverId)
    local id = tonumber(serverId)
    if id then
        DeleteRemoteSpear(id)
    end
end)

CreateThread(function()
    while true do
        local sleep = 500

        for i = 1, #ActivePlayerSpears do
            local spear = ActivePlayerSpears[i]
            if spear and spear.landed and spear.prop and DoesEntityExist(spear.prop) then
                if SpeargunEntity and DoesEntityExist(SpeargunEntity) then
                    sleep = 0
                    DrawCatenaryRope(GetSpeargunMuzzleWorldCoords(), GetSpearTailWorldCoords(spear.prop), 1.0)
                end
            end
        end

        if next(RemoteSpears) then
            sleep = 0
            for serverId, item in pairs(RemoteSpears) do
                if not item.prop or not DoesEntityExist(item.prop) then
                    RemoteSpears[serverId] = nil
                else
                    local elapsed = GetGameTimer() - item.startedAt
                    if not item.landed then
                        local progress = elapsed / item.flight
                        if progress >= 1.0 then
                            item.landed = true
                            SetEntityCoordsNoOffset(item.prop, item.to.x, item.to.y, item.to.z, false, false, false)
                        else
                            local currentPos = item.from + (item.to - item.from) * progress
                            SetEntityCoordsNoOffset(item.prop, currentPos.x, currentPos.y, currentPos.z, false, false, false)
                        end
                    end

                    local remoteGun = RemoteSpearguns[serverId]
                    if remoteGun and DoesEntityExist(remoteGun) then
                        local gunMuzzle = GetOffsetFromEntityInWorldCoords(remoteGun, SpeargunConfig.Line.MuzzleOffset.x, SpeargunConfig.Line.MuzzleOffset.y, SpeargunConfig.Line.MuzzleOffset.z)
                        local tailPos = GetSpearTailWorldCoords(item.prop)
                        DrawCatenaryRope(gunMuzzle, tailPos, item.landed and 1.0 or 0.2)
                    end
                end
            end
        end

        Wait(sleep)
    end
end)

function FireLocalSpear()
    local now = GetGameTimer()
    if IsFiringSpear or now < NextFireAllowedAt then
        return
    end

    local playerPed = PlayerPedId()
    if not IsPedUnderwater(playerPed) then
        return CreateNotification("notify", "error", Lang("SPEAR_NEED_UNDERWATER"))
    end
    if SpearAmmo <= 0 then
        return CreateNotification("notify", "error", Lang("SPEAR_NO_AMMO"))
    end

    IsFiringSpear = true
    SpearAmmo = SpearAmmo - 1
    NextFireAllowedAt = now + CooldownDurationMs

    CreateThread(function()
        local result = lib.callback.await("qs-fisher:fireSpear", false)
        if result and result.ok then
            SpearAmmo = result.spears or SpearAmmo
        else
            CreateNotification("notify", "error", Lang("SPEAR_NO_AMMO"))
            SpearAmmo = 0
        end
    end)

    local muzzleCoords = GetSpeargunMuzzleWorldCoords()
    local camCoords = GetGameplayCamCoord()
    local camForward = GetCameraForwardDirection()
    local maxRange = tonumber(GetSpeargunConfig().Range) or 25.0
    local targetRayEnd = camCoords + camForward * maxRange

    local shapeTest = StartExpensiveSynchronousShapeTestLosProbe(camCoords.x, camCoords.y, camCoords.z, targetRayEnd.x, targetRayEnd.y, targetRayEnd.z, 12, playerPed, 4)
    local _, hit, hitCoords, _, hitEntity = GetShapeTestResult(shapeTest)

    local impactPos = (hit == 1 and hitCoords) and hitCoords or targetRayEnd
    local hitSharkEntity = nil
    if hit == 1 and hitEntity ~= 0 and ActiveSharkEntities[hitEntity] then
        hitSharkEntity = hitEntity
    end

    local camHeading = GetGameplayCamRot(2).z
    local distToImpact = #(impactPos - muzzleCoords)
    local flightMs = math.max((distToImpact / SpeargunConfig.FlightSpeed) * 1000.0, SpeargunConfig.FlightMinMs)

    TriggerServerEvent("qs-fisher:spearFired", muzzleCoords.x, muzzleCoords.y, muzzleCoords.z, impactPos.x, impactPos.y, impactPos.z, flightMs)

    local spear = SpawnSpearProjectile(muzzleCoords)
    if spear and spear.prop then
        local startTime = GetGameTimer()
        SetEntityRotation(spear.prop, 0.0, 0.0, camHeading, 2, true)

        while (GetGameTimer() - startTime) < flightMs do
            local progress = (GetGameTimer() - startTime) / flightMs
            local currentPos = muzzleCoords + (impactPos - muzzleCoords) * progress
            SetEntityCoordsNoOffset(spear.prop, currentPos.x, currentPos.y, currentPos.z, false, false, false)
            CheckSpearFlightCollision(spear, muzzleCoords)
            Wait(0)
        end

        SetEntityCoordsNoOffset(spear.prop, impactPos.x, impactPos.y, impactPos.z, false, false, false)
        OnSpearLandedWorld(spear)
    end

    if hitSharkEntity then
        AttachSpearToTarget(spear, hitSharkEntity)
        AddTargetForShark(hitSharkEntity)
        local sharkInfo = ActiveSharkEntities[hitSharkEntity]
        if sharkInfo then
            sharkInfo.speared = true
            sharkInfo.spear = spear
        end
        ClearPedTasksImmediately(hitSharkEntity)
        SetEntityHealth(hitSharkEntity, 0)
        FreezeEntityPosition(hitSharkEntity, true)
        CreateNotification("notify", "success", Lang("SPEAR_HIT"))
    else
        if spear then
            spear.landed = false
            if spear.prop and DoesEntityExist(spear.prop) then
                FreezeEntityPosition(spear.prop, true)
            end
            local spearRef = spear
            CreateThread(function()
                Wait(MissLifetimeSec * 1000)
                DeleteSpear(spearRef)
            end)
        end

        local alertDuration = FleeDurationSec * 1000
        for sharkPed, sharkData in pairs(ActiveSharkEntities) do
            if DoesEntityExist(sharkPed) then
                local dist = #(GetEntityCoords(sharkPed) - impactPos)
                if dist < 30.0 then
                    sharkData.alerted = GetGameTimer() + alertDuration
                end
            end
        end
    end

    IsFiringSpear = false
end

function GetSharkTemperament()
    local sharkConf = GetSpeargunConfig().Sharks or {}
    local aggressiveChance = tonumber(sharkConf.AggressiveChance) or 25
    local roll = math.random(100)
    if roll <= aggressiveChance then
        return "aggressive"
    end
    local skittishChance = tonumber(sharkConf.SkittishChance) or 40
    if roll <= (aggressiveChance + skittishChance) then
        return "skittish"
    end
    return "passive"
end

function SharkCruiseAround(sharkEntity, sharkData)
    if not sharkEntity or not DoesEntityExist(sharkEntity) or not sharkData or not sharkData.home then
        return
    end

    local angle = math.random() * math.pi * 2.0
    local dist = 12.0 + math.random() * 18.0
    local targetPos = vec3(
        sharkData.home.x + math.cos(angle) * dist,
        sharkData.home.y + math.sin(angle) * dist,
        sharkData.home.z + (math.random() * 4.0 - 2.0)
    )

    if ActiveSharkHunt and ActiveSharkHunt.coords then
        local dx = targetPos.x - ActiveSharkHunt.coords.x
        local dy = targetPos.y - ActiveSharkHunt.coords.y
        local distFromCenter = math.sqrt(dx * dx + dy * dy)
        local maxRadius = (ActiveSharkHunt.radius or 60.0) * 0.85
        if distFromCenter > maxRadius and distFromCenter > 0.01 then
            targetPos = vec3(
                ActiveSharkHunt.coords.x + (dx / distFromCenter) * maxRadius,
                ActiveSharkHunt.coords.y + (dy / distFromCenter) * maxRadius,
                targetPos.z
            )
        end
    end

    local speed = SpeargunConfig.CruiseSpeed or 2.2
    TaskGoToCoordAnyMeans(sharkEntity, targetPos.x, targetPos.y, targetPos.z, speed, 0, 0, 786603, 0)
    local swimDuration = math.floor(dist / math.max(speed, 0.1) * 1000)
    sharkData.cruiseAgain = GetGameTimer() + swimDuration + 2000
end

function KeepSharkInWaterBounds(sharkEntity, sharkData)
    local coords = GetEntityCoords(sharkEntity)
    local waterFound, waterZ = GetWaterHeight(coords.x, coords.y, coords.z + 10.0)
    if not waterFound then
        return
    end

    local minDepth = (ActiveSharkHunt and ActiveSharkHunt.minDepth) or 6.0
    local maxZ = waterZ - minDepth
    if maxZ < coords.z then
        local pushDown = math.min(coords.z - maxZ, 0.65)
        SetEntityCoordsNoOffset(sharkEntity, coords.x, coords.y, coords.z - pushDown, false, false, false)
        sharkData.cruiseAgain = 0
    end
end

function CheckSharkHuntLeash(sharkEntity, sharkData)
    if not ActiveSharkHunt or not ActiveSharkHunt.coords then
        return
    end
    local coords = GetEntityCoords(sharkEntity)
    local dx = coords.x - ActiveSharkHunt.coords.x
    local dy = coords.y - ActiveSharkHunt.coords.y
    local maxDist = (ActiveSharkHunt.radius or 60.0) + (ActiveSharkHunt.leash or 25.0)

    if (dx * dx + dy * dy) > (maxDist * maxDist) then
        sharkData.fleeing = false
        sharkData.hunting = false
        sharkData.cruiseAgain = 0
    end
end

function ScanForWildSharksInZone()
    if not ActiveSharkHunt or not ActiveSharkHunt.coords then
        return
    end

    local validModels = {}
    local models = ActiveSharkHunt.models or { "a_c_sharktiger", "a_c_sharkhammer" }
    for _, modelName in ipairs(models) do
        validModels[joaat(modelName)] = true
    end

    local maxRadius = (ActiveSharkHunt.radius or 60.0) + (ActiveSharkHunt.leash or 25.0)
    local handle, ped = FindFirstPed()
    local success = true

    repeat
        if DoesEntityExist(ped) and not ActiveSharkEntities[ped] then
            if validModels[GetEntityModel(ped)] then
                local coords = GetEntityCoords(ped)
                local dist = #(coords - ActiveSharkHunt.coords)
                if dist <= maxRadius then
                    ActiveSharkEntities[ped] = {
                        temperament = GetSharkTemperament(),
                        spawnedAt = GetGameTimer(),
                        home = coords
                    }
                    SetBlockingOfNonTemporaryEvents(ped, true)
                    SetPedKeepTask(ped, true)
                end
            end
        end
        success, ped = FindNextPed(handle)
    until not success
    EndFindPed(handle)
end

function SpawnSharkAtCoords(huntCoords, radius)
    local models = (ActiveSharkHunt and ActiveSharkHunt.models) or { "a_c_sharktiger", "a_c_sharkhammer" }
    local modelName = models[math.random(#models)]
    local modelHash = joaat(modelName)

    if not IsModelInCdimage(modelHash) then
        return
    end
    RequestModel(modelHash)
    local timeout = GetGameTimer() + 4000
    while not HasModelLoaded(modelHash) do
        if GetGameTimer() > timeout then
            return
        end
        Wait(0)
    end

    local angle = math.random() * math.pi * 2.0
    local dist = math.random() * (radius * 0.75)
    local spawnX = huntCoords.x + math.cos(angle) * dist
    local spawnY = huntCoords.y + math.sin(angle) * dist

    local waterFound, waterZ = GetWaterHeight(spawnX, spawnY, huntCoords.z + 20.0)
    if not waterFound then
        SetModelAsNoLongerNeeded(modelHash)
        return
    end

    local groundZ, groundFound = GetGroundZ(spawnX, spawnY, waterZ)
    local waterDepth = waterZ - groundZ
    local minDepth = (ActiveSharkHunt and ActiveSharkHunt.minDepth) or 8.0

    if waterDepth < minDepth then
        SetModelAsNoLongerNeeded(modelHash)
        return
    end

    local spawnZ = groundZ + (waterDepth * 0.5)
    local sharkPed = CreatePed(28, modelHash, spawnX, spawnY, spawnZ, math.random(360), true, true)
    SetModelAsNoLongerNeeded(modelHash)

    if not DoesEntityExist(sharkPed) then
        return
    end

    SetEntityAsMissionEntity(sharkPed, true, true)
    SetBlockingOfNonTemporaryEvents(sharkPed, true)
    SetPedKeepTask(sharkPed, true)
    SetPedDiesInWater(sharkPed, false)
    SetPedCanRagdoll(sharkPed, false)
    SetEntityMaxHealth(sharkPed, 200)
    SetEntityHealth(sharkPed, 200)

    local sharkData = {
        temperament = GetSharkTemperament(),
        spawnedAt = GetGameTimer(),
        home = vec3(spawnX, spawnY, spawnZ)
    }
    ActiveSharkEntities[sharkPed] = sharkData
    SharkCruiseAround(sharkPed, sharkData)
end

function DeleteSharkEntity(ped)
    local info = ActiveSharkEntities[ped]
    if not info then
        return
    end
    if info.spear then
        DeleteSpear(info.spear)
    end
    ActiveSharkEntities[ped] = nil

    if DoesEntityExist(ped) then
        if Config.Target then
            if Config.TargetScript == "ox" then
                exports.ox_target:removeLocalEntity(ped)
            elseif Config.TargetScript == "qb" then
                exports["qb-target"]:RemoveTargetEntity(ped)
            end
        end
        SetEntityAsMissionEntity(ped, true, true)
        DeleteEntity(ped)
    end
end

function ClearAllSharkEntities()
    for ped in pairs(ActiveSharkEntities) do
        DeleteSharkEntity(ped)
    end
    ActiveSharkEntities = {}
end

function GetSharkFleeDistance()
    local fleeDist = SpeargunConfig.FleeDistance or 55.0
    if not ActiveSharkHunt or not ActiveSharkHunt.radius then
        return fleeDist
    end
    return math.max(math.min(fleeDist, ActiveSharkHunt.radius * 0.66), 12.0)
end

function UpdateSharkAI(sharkPed, sharkData, playerPed, distToPlayer)
    if sharkData.speared then
        return
    end

    local inSenseRange = distToPlayer <= SharkSenseRange

    if sharkData.alerted and GetGameTimer() < sharkData.alerted then
        if not sharkData.fleeing then
            sharkData.fleeing = true
            TaskSmartFleePed(sharkPed, playerPed, GetSharkFleeDistance(), -1, false, false)
        end
        return
    end

    if not inSenseRange then
        if sharkData.fleeing or sharkData.hunting then
            sharkData.fleeing = false
            sharkData.hunting = false
            sharkData.cruiseAgain = 0
        end

        if GetEntitySpeed(sharkPed) < 0.25 or GetGameTimer() >= (sharkData.cruiseAgain or 0) then
            SharkCruiseAround(sharkPed, sharkData)
        end
        return
    end

    if sharkData.temperament == "aggressive" then
        if not sharkData.hunting then
            sharkData.hunting = true
            if sharkData.willAttack == nil then
                local attackChance = tonumber(GetSpeargunConfig().Sharks and GetSpeargunConfig().Sharks.AttackChance) or 0
                sharkData.willAttack = (attackChance > 0)
            end
            if sharkData.willAttack then
                TaskCombatPed(sharkPed, playerPed, 0, 16)
            end
        end
    elseif sharkData.temperament == "skittish" then
        if not sharkData.fleeing then
            sharkData.fleeing = true
            TaskSmartFleePed(sharkPed, playerPed, GetSharkFleeDistance() * 0.8, -1, false, false)
        end
    end
end

function AddTargetForShark(ped)
    if not Config.Target or not ped or not DoesEntityExist(ped) then
        return
    end
    local targetOptions = {
        {
            name = "harvest_shark",
            icon = "fas fa-fish",
            label = Lang("TARGET_HARVEST_SHARK"),
            action = function(entity)
                HarvestShark(entity)
            end,
            canInteract = function(entity)
                local data = ActiveSharkEntities[entity]
                return data and data.speared and not IsHarvesting
            end
        }
    }

    if Config.TargetScript == "ox" then
        exports.ox_target:addLocalEntity(ped, targetOptions)
    elseif Config.TargetScript == "qb" then
        exports["qb-target"]:AddTargetEntity(ped, { options = targetOptions, distance = SpeargunConfig.HarvestReach })
    end
end

function PlayHarvestMinigame(ped)
    local animConf = SpeargunConfig.HarvestAnim
    local dict = animConf.dict or "anim@heists@ornate_bank@grab_cash"
    local clip = animConf.clip or "grab"
    local durationSec = 3

    local progressConfig = {
        Seconds = durationSec,
        Label = Lang("PROGRESS_HARVESTING"),
        Animation = {
            Dict = dict,
            Anim = clip,
            Flag = 49
        }
    }

    local playerPed = PlayerPedId()
    FreezeEntityPosition(playerPed, true)
    local success = ProgressBar(progressConfig)
    if not success then
        FreezeEntityPosition(playerPed, false)
        ClearPedTasks(playerPed)
        return false
    end

    local maxReach = SpeargunConfig.HarvestReach + 2.0
    local timeout = GetGameTimer() + durationSec * 1000
    while GetGameTimer() < timeout do
        Wait(100)
        if not DoesEntityExist(ped) or #(GetEntityCoords(playerPed) - GetEntityCoords(ped)) > maxReach then
            FreezeEntityPosition(playerPed, false)
            ClearPedTasks(playerPed)
            return false
        end
    end

    FreezeEntityPosition(playerPed, false)
    ClearPedTasks(playerPed)
    return true
end

function HarvestShark(ped)
    if IsHarvesting then
        return
    end
    local sharkData = ActiveSharkEntities[ped]
    if not sharkData or not sharkData.speared then
        return
    end

    IsHarvesting = true
    local harvestStart = GetGameTimer()
    local maxWaitMs = 23000

    CreateThread(function()
        while IsHarvesting and (GetGameTimer() - harvestStart) < maxWaitMs do
            Wait(500)
        end
        if IsHarvesting and (GetGameTimer() - harvestStart) >= maxWaitMs then
            IsHarvesting = false
        end
    end)

    local success = PlayHarvestMinigame(ped)
    if not success then
        IsHarvesting = false
        return
    end

    if not ActiveSharkEntities[ped] or not ActiveSharkEntities[ped].speared then
        IsHarvesting = false
        return
    end

    local result = lib.callback.await("qs-fisher:harvestShark", false)
    if not result or not result.ok then
        IsHarvesting = false
        local reason = result and result.reason or "bad"
        if reason == "full" then
            return CreateNotification("notify", "error", Lang("NOTIFY_INVENTORY_FULL"))
        elseif reason == "nohunt" then
            return CreateNotification("notify", "error", Lang("SPEAR_NO_HUNT"))
        elseif reason == "toofast" then
            return CreateNotification("notify", "error", Lang("SPEAR_TOO_FAST"))
        end
        return CreateNotification("notify", "error", Lang("SPEAR_HARVEST_FAILED"))
    end

    local recovered = (result.recovered == true)
    DeleteSharkEntity(ped)
    IsHarvesting = false

    if result.missing then
        CreateNotification("notify", "error", string.format(Lang("NOTIFY_ITEM_DOES_NOT_EXIST"), result.missing))
    else
        local weight = (result.stats and result.stats.weight) or 0
        local weightStr = string.format("%.2f", weight)
        CreateNotification("notify", "success", string.format(Lang("SPEAR_HARVESTED"), result.label or "?", weightStr))
    end

    CreateNotification("notify", recovered and "success" or "error", recovered and Lang("SPEAR_RECOVERED") or Lang("SPEAR_BENT"))
    if result.newRecord then
        CreateNotification("notify", "success", Lang("NEW_RECORD"))
    end
end

CreateThread(function()
    while true do
        local sleep = 500
        if IsSpeargunEquipped then
            sleep = 0
            local playerPed = PlayerPedId()
            local coords = GetEntityCoords(playerPed)

            local isAiming = IsControlPressed(0, 25)
            if isAiming and not IsAimingSpeargun then
                IsAimingSpeargun = true
                StartAimCamera()
                StartAimAnimation()
                UpdateSpeargunAttachment(true)
            elseif not isAiming and IsAimingSpeargun then
                IsAimingSpeargun = false
                StopAimCamera()
                StopAimAnimation()
                UpdateSpeargunAttachment(false)
            end

            if IsAimingSpeargun then
                UpdateAimCamera()
            end

            local hudState = IsAimingSpeargun and "aiming" or "ready"
            UpdateSpearHud(hudState)

            if IsControlJustPressed(0, 24) then
                FireLocalSpear()
            end

            for sharkEntity, sharkInfo in pairs(ActiveSharkEntities) do
                if sharkInfo.speared and DoesEntityExist(sharkEntity) then
                    local sharkCoords = GetEntityCoords(sharkEntity)
                    local dist = #(coords - sharkCoords)

                    if dist <= SpeargunConfig.HarvestReach then
                        if not Config.Target and Config.DrawText3D then
                            local keyLabel = Config.Keys.InteractKeyLabel or "E"
                            DrawText3D(sharkCoords.x, sharkCoords.y, sharkCoords.z + 0.5, Lang("SPEAR_HARVEST_PROMPT"), "shark", keyLabel)
                        end
                        local interactKey = Config.Keys.InteractKey or 38
                        if IsControlJustReleased(0, interactKey) then
                            CreateThread(function()
                                HarvestShark(sharkEntity)
                            end)
                        end
                    end
                end
            end
        else
            UpdateSpearHud(nil)
        end
        Wait(sleep)
    end
end)

CreateThread(function()
    while true do
        local sleep = 700
        local markerConf = GetSpeargunConfig().SharkMarker or {}

        if markerConf.enabled ~= false and next(ActiveSharkEntities) then
            local playerCoords = GetEntityCoords(PlayerPedId())
            local maxDist = tonumber(markerConf.Distance or markerConf.distance) or 60.0
            local size = markerConf.size or {}
            local color = markerConf.color or {}

            for sharkPed, sharkData in pairs(ActiveSharkEntities) do
                if DoesEntityExist(sharkPed) then
                    if sharkData.speared or markerConf.LiveSharks ~= false then
                        local sharkCoords = GetEntityCoords(sharkPed)
                        local dist = #(sharkCoords - playerCoords)

                        if dist <= maxDist then
                            sleep = 0
                            local markerType = tonumber(markerConf.type) or 0
                            local heightOffset = tonumber(markerConf.height) or 1.2
                            local sx = tonumber(size.x) or 0.6
                            local sy = tonumber(size.y) or 0.6
                            local sz = tonumber(size.z) or 0.5
                            local r = tonumber(color.r) or 59
                            local g = tonumber(color.g) or 130
                            local b = tonumber(color.b) or 246
                            local a = tonumber(color.a) or 190
                            DrawMarker(markerType, sharkCoords.x, sharkCoords.y, sharkCoords.z + heightOffset, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, sx, sy, sz, r, g, b, a, false, false, 2, false, nil, nil, false)
                        end
                    end
                end
            end
        end
        Wait(sleep)
    end
end)

CreateThread(function()
    while true do
        Wait(1000)
        if ActiveSharkHunt and ActiveSharkHunt.coords then
            local playerPed = PlayerPedId()
            local playerCoords = GetEntityCoords(playerPed)
            local distToHunt = #(playerCoords - ActiveSharkHunt.coords)

            if distToHunt <= ((ActiveSharkHunt.radius or 60.0) + (ActiveSharkHunt.leash or 25.0)) then
                ScanForWildSharksInZone()

                local activeCount = 0
                for sharkPed, sharkData in pairs(ActiveSharkEntities) do
                    if DoesEntityExist(sharkPed) then
                        activeCount = activeCount + 1
                        local sharkDist = #(GetEntityCoords(sharkPed) - playerCoords)
                        UpdateSharkAI(sharkPed, sharkData, playerPed, sharkDist)
                        KeepSharkInWaterBounds(sharkPed, sharkData)
                        CheckSharkHuntLeash(sharkPed, sharkData)
                    else
                        ActiveSharkEntities[sharkPed] = nil
                    end
                end

                local maxSharks = tonumber(ActiveSharkHunt.maxSharks) or 3
                if activeCount < maxSharks then
                    SpawnSharkAtCoords(ActiveSharkHunt.coords, ActiveSharkHunt.radius or 60.0)
                end
            end
        end
    end
end)

function CreateHuntBlips()
    if HuntCenterBlip then
        RemoveBlip(HuntCenterBlip)
        HuntCenterBlip = nil
    end
    if HuntRadiusBlip then
        RemoveBlip(HuntRadiusBlip)
        HuntRadiusBlip = nil
    end
    if not ActiveSharkHunt or not ActiveSharkHunt.coords then
        return
    end

    local coords = ActiveSharkHunt.coords
    local radius = ActiveSharkHunt.radius or 60.0

    HuntRadiusBlip = AddBlipForRadius(coords.x, coords.y, coords.z, radius)
    SetBlipColour(HuntRadiusBlip, 1)
    SetBlipAlpha(HuntRadiusBlip, 128)

    HuntCenterBlip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(HuntCenterBlip, 68)
    SetBlipColour(HuntCenterBlip, 1)
    SetBlipScale(HuntCenterBlip, 0.8)
    SetBlipAsShortRange(HuntCenterBlip, false)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString(Lang("BLIP_SHARK_HUNT") or "Shark Hunt")
    EndTextCommandSetBlipName(HuntCenterBlip)
end

RegisterNetEvent("qs-fisher:sharkHuntStarted", function(huntData)
    if not huntData then
        return
    end
    ActiveSharkHunt = huntData
    CreateHuntBlips()
    CreateNotification("notify", "success", string.format(Lang("SPEAR_HUNT_STARTED"), huntData.zone or "?"))
end)

RegisterNetEvent("qs-fisher:sharkHuntEnded", function()
    ClearAllSharkEntities()
    if HuntCenterBlip then
        RemoveBlip(HuntCenterBlip)
        HuntCenterBlip = nil
    end
    if HuntRadiusBlip then
        RemoveBlip(HuntRadiusBlip)
        HuntRadiusBlip = nil
    end
    ActiveSharkHunt = nil
end)

CreateThread(function()
    Wait(5000)
    local hunt = lib.callback.await("qs-fisher:getSharkHunt", false)
    if hunt then
        ActiveSharkHunt = hunt
        CreateHuntBlips()
    end
end)

function ToggleSpeargun()
    if not GetSpeargunConfig().Enabled then
        return
    end

    if IsSpeargunEquipped then
        StowSpeargunProp()
        return CreateNotification("notify", "info", Lang("SPEAR_STOWED"))
    end

    local playerPed = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(playerPed, false)
    if vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == playerPed then
        return CreateNotification("notify", "error", Lang("SPEAR_NOT_WHILE_DRIVING"))
    end

    if RodIsOut and RodIsOut() then
        return CreateNotification("notify", "error", Lang("SPEAR_BLOCKED_ROD"))
    end

    local response = lib.callback.await("qs-fisher:drawSpeargun", false)
    if not response then
        return CreateNotification("notify", "error", Lang("SPEAR_UNAVAILABLE"))
    end

    if not response.ok then
        local reason = response.reason or "bad"
        if reason == "level" then
            return CreateNotification("notify", "error", string.format(Lang("SPEAR_NEED_LEVEL"), response.level or 1))
        elseif reason == "noitem" then
            return CreateNotification("notify", "error", Lang("SPEAR_NO_GUN"))
        end
        return CreateNotification("notify", "error", Lang("SPEAR_UNAVAILABLE"))
    end

    SpearAmmo = response.spears or 0
    PreloadSpeargunAssets()
    local drawn, err = DrawSpeargunProp()
    if not drawn then
        return CreateNotification("notify", "error", Lang(err == "noprops" and "SPEAR_NO_PROPS" or "SPEAR_UNAVAILABLE"))
    end

    IsSpeargunEquipped = true
    UpdateSpearHud("ready")
    CreateNotification("notify", "success", Lang("SPEAR_DRAWN"))
end

exports("useSpeargun", ToggleSpeargun)
RegisterNetEvent("qs-fisher:useSpeargun", ToggleSpeargun)

function UpdateScubaProps(attach)
    local playerPed = PlayerPedId()
    if not attach then
        for _, prop in ipairs({ ScubaTankProp, ScubaMaskProp }) do
            if prop and DoesEntityExist(prop) then
                DetachEntity(prop, false, true)
                DeleteEntity(prop)
            end
        end
        ScubaTankProp = nil
        ScubaMaskProp = nil
        return
    end

    function EnsureLoaded(model)
        if HasModelLoaded(model) then
            return true
        end
        RequestModel(model)
        local timeout = GetGameTimer() + 3000
        while not HasModelLoaded(model) do
            if GetGameTimer() > timeout then
                return false
            end
            Wait(0)
        end
        return true
    end

    local tankHash = joaat("p_s_scuba_tank_s")
    local maskHash = joaat("p_d_scuba_mask_s")

    if not ScubaTankProp and EnsureLoaded(tankHash) then
        ScubaTankProp = CreateObject(tankHash, 1.0, 1.0, 1.0, true, true, false)
        local boneIdx = GetPedBoneIndex(playerPed, 24818)
        AttachEntityToEntity(ScubaTankProp, playerPed, boneIdx, -0.25, -0.25, 0.0, 180.0, 90.0, 0.0, true, true, false, false, 2, true)
        SetModelAsNoLongerNeeded(tankHash)
    end

    if not ScubaMaskProp and EnsureLoaded(maskHash) then
        ScubaMaskProp = CreateObject(maskHash, 1.0, 1.0, 1.0, true, true, false)
        local boneIdx = GetPedBoneIndex(playerPed, 12844)
        AttachEntityToEntity(ScubaMaskProp, playerPed, boneIdx, 0.0, 0.0, 0.0, 180.0, 90.0, 0.0, true, true, false, false, 2, true)
        SetModelAsNoLongerNeeded(maskHash)
    end
end

function GetMaxOxygenSeconds()
    local breathConf = GetSpeargunConfig().Breath or {}
    return math.max(math.floor(tonumber(breathConf.Seconds) or 180), 1)
end

function GetOxygenRegenSeconds()
    local breathConf = GetSpeargunConfig().Breath or {}
    return math.max(tonumber(breathConf.Regen) or 5, 0)
end

function RemoveScubaGear()
    if not HasScubaTankEquipped then
        return
    end
    HasScubaTankEquipped = false
    RemainingOxygen = 0
    HasOxygenLowWarned = false
    UpdateScubaProps(false)

    if IsOxygenHudVisible then
        IsOxygenHudVisible = false
        SendNUIMessage({
            action = "hideOxygenUI"
        })
    end
end

function ToggleScubaGear()
    if not GetSpeargunConfig().Enabled then
        return
    end

    if HasScubaTankEquipped then
        RemoveScubaGear()
        CreateNotification("notify", "info", Lang("TANK_REMOVED"))
        return
    end

    local animConf = SpeargunConfig.TankAnim
    local dict = animConf.dict or "clothingshirt"
    local clip = animConf.clip or "try_shirt_positive_d"
    local durationSec = 3

    local progressConfig = {
        Seconds = durationSec,
        Label = Lang("TANK_PUTTING_ON"),
        Animation = {
            Dict = dict,
            Anim = clip,
            Flag = 49
        }
    }

    local playerPed = PlayerPedId()
    FreezeEntityPosition(playerPed, true)
    local success = ProgressBar(progressConfig)
    FreezeEntityPosition(playerPed, false)

    if not success then
        ClearPedTasks(playerPed)
        return
    end

    HasScubaTankEquipped = true
    RemainingOxygen = GetMaxOxygenSeconds()
    HasOxygenLowWarned = false
    UpdateScubaProps(true)
    CreateNotification("notify", "success", Lang("TANK_EQUIPPED"))
end

exports("useDiveTank", ToggleScubaGear)
RegisterNetEvent("qs-fisher:useDiveTank", ToggleScubaGear)

CreateThread(function()
    while true do
        if HasScubaTankEquipped then
            local maxOxygen = GetMaxOxygenSeconds()
            local playerPed = PlayerPedId()

            if IsPedUnderwater(playerPed) then
                if not IsOxygenHudVisible then
                    IsOxygenHudVisible = true
                    SendNUIMessage({
                        action = "showOxygenUI"
                    })
                end

                RemainingOxygen = math.max(RemainingOxygen - 1, 0)
                SetPedMaxTimeUnderwater(playerPed, 20.0)
                SetPedDiesInWater(playerPed, false)

                local fraction = RemainingOxygen / maxOxygen
                SendNUIMessage({
                    action = "updateOxygenUI",
                    oxygen = math.floor(fraction * 100),
                    seconds = RemainingOxygen
                })

                if RemainingOxygen <= 0 then
                    SetPedDiesInWater(playerPed, true)
                    SetEntityHealth(playerPed, math.max(GetEntityHealth(playerPed) - 10, 0))
                elseif RemainingOxygen <= 15 then
                    if not HasOxygenLowWarned then
                        HasOxygenLowWarned = true
                        CreateNotification("notify", "error", Lang("WARNING_OXYGEN"))
                    end
                elseif RemainingOxygen > 10 then
                    HasOxygenLowWarned = false
                end
            else
                if IsOxygenHudVisible then
                    IsOxygenHudVisible = false
                    SendNUIMessage({
                        action = "hideOxygenUI"
                    })
                end

                RemainingOxygen = math.min(RemainingOxygen + GetOxygenRegenSeconds(), maxOxygen)
                HasOxygenLowWarned = false
            end
        end
        Wait(1000)
    end
end)

AddEventHandler("gameEventTriggered", function(eventName, data)
    if eventName ~= "CEventNetworkEntityDamage" then
        return
    end
    local victim = data[1]
    local playerPed = PlayerPedId()

    if victim == playerPed and IsPedDeadOrDying(victim, true) then
        if IsSpeargunEquipped then
            TriggerServerEvent("qs-fisher:loseSpeargun")
            StowSpeargunProp()
        end
        RemoveScubaGear()
        for _, s in ipairs(ActivePlayerSpears) do
            DeleteSpear(s)
        end
        ActivePlayerSpears = {}
    end
end)

AddEventHandler("onResourceStop", function(resourceName)
    if GetCurrentResourceName() ~= resourceName then
        return
    end
    StowSpeargunProp()
    RemoveScubaGear()
    ClearAllSharkEntities()
    ClearAllRemoteEntities()

    for _, s in ipairs(ActivePlayerSpears) do
        DeleteSpear(s)
    end
    ActivePlayerSpears = {}

    if HuntCenterBlip then
        RemoveBlip(HuntCenterBlip)
        HuntCenterBlip = nil
    end
    if HuntRadiusBlip then
        RemoveBlip(HuntRadiusBlip)
        HuntRadiusBlip = nil
    end
end)
--WKLeak-RaOnjATopH! : https://discord.gg/zqcBffbMZn
--WKLeaksOqOnavTop_r : https://discord.gg/zqcBffbMZn
--WKLeak-q7On3LTopFl : https://discord.gg/zqcBffbMZn
--WKLeak-zPOnYoTop5F : https://discord.gg/zqcBffbMZn
--WKLeak-WCOnAYTopFG : https://discord.gg/zqcBffbMZn
