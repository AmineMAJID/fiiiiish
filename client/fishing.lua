--[[   -- https://discord.gg/zqcBffbMZn ]]
local isFishing = false
local isFighting = false
local activeDecisionToken = nil

CurrentGear = {
    bait = nil,
    hook = nil,
    reel = nil,
    line = nil
}

local validGearSlots = {
    bait = true,
    hook = true,
    reel = true,
    line = true
}

local BONE_RIGHT_HAND = 57005
local BONE_LEFT_HAND = 18905

local FishingAnimations = {
    charge = {
        dict = "amb@world_human_stand_fishing@idle_a",
        clip = "idle_a",
        duration = -1,
        flag = 1
    },
    cast = {
        dict = "mini@tennis",
        clip = "forehand_ts_md_far",
        duration = 1500,
        flag = 48,
        releaseAt = 480
    },
    idle = {
        dict = "amb@world_human_stand_fishing@base",
        clip = "base",
        duration = -1,
        flag = 1
    },
    fight = {
        dict = "amb@world_human_stand_fishing@idle_a",
        clip = "idle_c",
        duration = -1,
        flag = 11
    }
}

function AttachRodToHand(ped)
    if not Player.rod or not DoesEntityExist(Player.rod) then
        return
    end
    local boneIndex = GetPedBoneIndex(ped, BONE_RIGHT_HAND)
    AttachEntityToEntity(Player.rod, ped, boneIndex, 0.14, 0.18, 0.07, 240.0, 180.0, 0.0, false, true, false, true, 0, true)
end

function AttachRodCast(ped)
    if not Player.rod or not DoesEntityExist(Player.rod) then
        return
    end
    local boneIndex = GetPedBoneIndex(ped, BONE_LEFT_HAND)
    AttachEntityToEntity(Player.rod, ped, boneIndex, 0.1, 0.05, 0.0, 80.0, 120.0, 160.0, false, true, false, true, 1, true)
end

function CleanPlayerLine()
    if Player.rope then
        DeleteRope(Player.rope)
        Player.rope = nil
    end
    if Player.invisibleProp and DoesEntityExist(Player.invisibleProp) then
        DeleteEntity(Player.invisibleProp)
    end
    Player.invisibleProp = nil
    if Player.lineAnnounced then
        Player.lineAnnounced = nil
        TriggerServerEvent("qs-fisher:lineIn")
    end
end

function DeleteFishingRod()
    if Player.rod and DoesEntityExist(Player.rod) then
        DetachEntity(Player.rod, true, true)
        DeleteEntity(Player.rod)
    end
    Player.rod = nil
    Player.rodIsIn = nil
end

function PlayRodWithdrawAnimation()
    local ped = PlayerPedId()
    local animDict = "amb@world_human_security_shine_torch@male@enter"
    RequestAnimDict(animDict)
    local timeout = GetGameTimer() + 3000
    while not HasAnimDictLoaded(animDict) do
        if GetGameTimer() > timeout then
            return
        end
        Wait(10)
    end
    TaskPlayAnim(ped, animDict, "enter", 1.0, 1.0, 1100, 48, 0, false, false, false)
    Wait(1100)
end

function RodIsOut()
    return Player.rodIsIn == "hand"
end

function StowFishingRod()
    if Player.rodIsIn ~= "hand" then
        return false
    end
    StopDangling()
    DeleteFishingRod()
    CleanPlayerLine()
    local ped = PlayerPedId()
    SetPedConfigFlag(ped, 48, false)
    SetPedConfigFlag(ped, 122, false)
    return true
end

function ToggleFishingRod()
    local ped = PlayerPedId()
    if Player.rodIsIn ~= "hand" and SpeargunIsOut and SpeargunIsOut() then
        CreateNotification("notify", "error", Lang("ROD_BLOCKED_SPEARGUN"))
        return
    end
    if Player.rodIsIn == "hand" then
        if isFighting or isFishing then
            CreateNotification("notify", "error", Lang("NOTIFY_ALREADY_FISHING"))
            return
        end
        if Config.FishingRodWithdrawAnimation then
            PlayRodWithdrawAnimation()
        end
        StowFishingRod()
        return
    end
    local selectedWeapon = GetSelectedPedWeapon(ped)
    if selectedWeapon ~= -1569615261 then
        TaskPlayAnim(ped, "reaction@intimidation@1h", "outro", 8.0, -8.0, 1000, 48, 0, false, false, false)
        RemoveAllPedWeapons(ped, false)
    end
    if Config.FishingRodWithdrawAnimation then
        PlayRodWithdrawAnimation()
    end
    local coords = GetEntityCoords(ped)
    local rodModel = -1910604593
    RequestModel(rodModel)
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(rodModel) do
        if GetGameTimer() > timeout then
            CreateNotification("notify", "error", Lang("NOTIFY_ROD_MODEL_FAILED"))
            return
        end
        Wait(0)
    end
    local rodEntity = CreateObject(rodModel, coords.x, coords.y, coords.z, true, true, false)
    SetModelAsNoLongerNeeded(rodModel)
    if not DoesEntityExist(rodEntity) then
        return
    end
    Player.rod = rodEntity
    Player.rodIsIn = "hand"
    AttachRodToHand(ped)
    SetPedConfigFlag(ped, 48, true)
    SetPedConfigFlag(ped, 122, true)
end

exports("toggleFishingRod", function()
    ToggleFishingRod()
end)

RegisterNetEvent("qs-fisher:toggleFishingRod", function()
    ToggleFishingRod()
end)

function OpenTackleBox()
    if isFighting or isFishing then
        CreateNotification("notify", "error", Lang("NOTIFY_ALREADY_FISHING"))
        return
    end
    local data = lib.callback.await("qs-fisher:getAttachments", false)
    if not data then
        return
    end
    local itemMap = {}
    local rawAttachments = data.attachments or {}
    for _, categoryList in pairs(rawAttachments) do
        for _, attData in ipairs(categoryList) do
            itemMap[attData.item] = attData
        end
    end
    local equippedItems = {}
    for slotName, equippedItemName in pairs(CurrentGear) do
        if equippedItemName and itemMap[equippedItemName] then
            equippedItems[slotName] = itemMap[equippedItemName]
        else
            equippedItems[slotName] = nil
            if equippedItemName and not itemMap[equippedItemName] then
                CurrentGear[slotName] = nil
            end
        end
    end
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = "openTackleBox",
        attachments = data.attachments or {},
        equipped = equippedItems,
        playerLevel = data.playerLevel or 1,
        rod = data.rod,
        rods = data.rods,
        nextRod = data.nextRod,
        slots = data.slots
    })
end

exports("toggleFishingKit", function()
    OpenTackleBox()
end)

RegisterNetEvent("qs-fisher:toggleFishingKit", function()
    OpenTackleBox()
end)

function SetGearSlot(slot, itemData)
    if CurrentGear[slot] == nil and itemData == nil then
        return
    end
    CurrentGear[slot] = itemData and itemData.item or nil
    TriggerServerEvent("qs-fisher:setGear", slot, CurrentGear[slot])
end

RegisterNUICallback("selectRod", function(data, cb)
    cb("ok")
    if type(data.item) ~= "string" then
        return
    end
    CreateThread(function()
        local result = lib.callback.await("qs-fisher:selectRod", false, data.item)
        if not result then
            return
        end
        local unlockedSlots = {}
        for _, slotInfo in ipairs(result.slots or {}) do
            if slotInfo.unlocked then
                unlockedSlots[slotInfo.slot] = true
            end
        end
        for slotKey in pairs(validGearSlots) do
            if not unlockedSlots[slotKey] then
                CurrentGear[slotKey] = nil
            end
        end
        SendNUIMessage({
            action = "tackleBoxUpdate",
            attachments = result.attachments or {},
            playerLevel = result.playerLevel or 1,
            rod = result.rod,
            rods = result.rods,
            nextRod = result.nextRod,
            slots = result.slots
        })
    end)
end)

RegisterNUICallback("equipAttachment", function(data, cb)
    if data.slot then
        SetGearSlot(data.slot, data.item)
    end
    cb("ok")
end)

RegisterNUICallback("closeTackleBox", function(data, cb)
    SetNuiFocus(false, false)
    for slotKey in pairs(validGearSlots) do
        local equippedItem = data.equipped and data.equipped[slotKey] or nil
        SetGearSlot(slotKey, equippedItem)
    end
    cb("ok")
end)

RegisterNUICallback("decideCatch", function(data, cb)
    cb("ok")
    local token = activeDecisionToken
    if not token then
        return
    end
    activeDecisionToken = nil
    SetNuiFocus(false, false)
    if token:sub(1, 5) == "test-" then
        return
    end
    CreateThread(function()
        local result = lib.callback.await("qs-fisher:decideCatch", false, token, data.keep == true)
        if result then
            ReportCatchSettled(result)
        end
    end)
end)

RegisterNUICallback("notifyInsufficientLevel", function(data, cb)
    CreateNotification("notify", "error", Lang("CANT_USE_EQUIPMENT"):format(data.label or "?", data.requiredLevel or 0, data.playerLevel or 0))
    cb("ok")
end)

RegisterNetEvent("qs-fisher:gearChanged", function(slot, item)
    if not validGearSlots[slot] then
        return
    end
    CurrentGear[slot] = item
end)

local FishingConfig = {
    MinBiteTime = 1500,
    BiteWindow = 3000,
    CastDistance = 10.0,
    MinDistance = 2.0,
    MaxAngle = 70.0,
    DeadZone = 8.0,
    PullSpeed = 0.025,
    SlipSpeed = 0.005,
    GainRate = 0.01,
    UpdateRate = 50
}

local CHARGE_ANIM_DURATION = 1100
local CAST_MAX_TIME = 6000
local PROBE_MAX_DIST = 5.0
local PROBE_MAX_DROP = 45.0
local PROBE_MIN_HEIGHT = 3.0
local DEFAULT_DEPTH = 6.0
local DRY_LAND_OFFSET = 2.0

function DepthAt(x, y, z)
    local ray = StartExpensiveSynchronousShapeTestLosProbe(x, y, z - 0.35, x, y, z - 500.0, 1, 0, 4)
    local hit, _, endCoords = GetShapeTestResult(ray)
    if hit == 1 or hit == true then
        return math.max(z - endCoords.z, 0.0), endCoords.z
    end
    return DEFAULT_DEPTH, z - DEFAULT_DEPTH
end

function DepthBandAt(depth)
    local bands = Config.Depth and Config.Depth.Bands or {}
    for _, band in ipairs(bands) do
        if depth <= (band.max or 0) then
            return band.id
        end
    end
    if #bands > 0 and bands[#bands].id then
        return bands[#bands].id
    end
    return nil
end

function OnDryLand(ped, waterZ)
    if not waterZ then
        return false
    end
    local coords = GetEntityCoords(ped)
    local hit, groundZ = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z + 1.0, false)
    if not hit then
        return false
    end
    return groundZ > (waterZ + DRY_LAND_OFFSET)
end

function OnBoat(ped)
    if IsPedInAnyBoat(ped) then
        return true
    end
    local coords = GetEntityCoords(ped)
    local ray = StartExpensiveSynchronousShapeTestLosProbe(coords.x, coords.y, coords.z + 0.5, coords.x, coords.y, coords.z - 3.0, 2, ped, 4)
    local hit, _, _, _, entityHit = GetShapeTestResult(ray)
    if not hit or hit == 0 or not entityHit or entityHit == 0 or not DoesEntityExist(entityHit) then
        return false
    end
    if IsEntityAVehicle(entityHit) then
        return GetVehicleClass(entityHit) == 14
    end
    return false
end

function TestWaterPoint(x, y, z, pedZ)
    local hit, waterZ = TestVerticalProbeAgainstAllWater(x, y, z, 0)
    if not hit then
        return nil
    end
    local heightDiff = pedZ - waterZ
    if heightDiff > PROBE_MAX_DROP or heightDiff < -PROBE_MIN_HEIGHT then
        return nil
    end
    local groundHit, groundZ = GetGroundZFor_3dCoord(x, y, waterZ + 60.0, true)
    if groundHit and groundZ > (waterZ + 0.5) then
        return nil
    end
    return waterZ
end

function ProbeWater(ped, maxDistance)
    if IsPedSwimming(ped) then
        return nil
    end
    local pedCoords = GetEntityCoords(ped)
    local forward = GetEntityForwardVector(ped)
    local steps = 16
    local probeZ = pedCoords.z + 2.0
    local isDryLand = not OnBoat(ped)
    local shoreDepth = tonumber(Config.Depth and Config.Depth.ShoreDepth) or 6.0
    local minDistanceCheck = 4.0

    for step = steps, 1, -1 do
        local distance = maxDistance * (step / steps)
        local sampleX = pedCoords.x + forward.x * distance
        local sampleY = pedCoords.y + forward.y * distance
        local waterZ = TestWaterPoint(sampleX, sampleY, probeZ, pedCoords.z)

        if waterZ and distance > minDistanceCheck then
            local losRay = StartExpensiveSynchronousShapeTestLosProbe(pedCoords.x, pedCoords.y, pedCoords.z + 1.1, sampleX, sampleY, waterZ + 1.6, 17, ped, 4)
            local losHit, losResult = GetShapeTestResult(losRay)
            if losResult then
                waterZ = nil
            end
        end

        if waterZ then
            local depth, bedZ = DepthAt(sampleX, sampleY, waterZ)
            if isDryLand then
                depth = shoreDepth
            end
            return {
                x = sampleX,
                y = sampleY,
                height = waterZ,
                distance = distance,
                depth = depth,
                band = DepthBandAt(depth),
                shore = isDryLand,
                bed = bedZ
            }
        end
    end
    return nil
end

function PlayFishingAnim(ped, animKey)
    local animData = FishingAnimations[animKey]
    if not animData or not animData.dict or not animData.clip then
        return false
    end
    RequestAnimDict(animData.dict)
    local timeout = GetGameTimer() + 3000
    while not HasAnimDictLoaded(animData.dict) do
        if GetGameTimer() > timeout then
            DebugPrint(("animation dictionary '%s' never loaded"):format(animData.dict))
            return false
        end
        Wait(0)
    end
    TaskPlayAnim(ped, animData.dict, animData.clip, 8.0, -8.0, animData.duration or -1, animData.flag or 1, 0, false, false, false)
    return true
end

function GetRodTipCoords()
    if not Player.rod or not DoesEntityExist(Player.rod) then
        return nil
    end
    return GetOffsetFromEntityInWorldCoords(Player.rod, 0.0, -0.01, 2.52)
end

function SpawnSplashPtfx(x, y, z)
    if not Config.Cast or not Config.Cast.Splash then
        return
    end
    local ptfxAsset = "core"
    if not HasNamedPtfxAssetLoaded(ptfxAsset) then
        RequestNamedPtfxAsset(ptfxAsset)
        local timeout = GetGameTimer() + 1500
        while not HasNamedPtfxAssetLoaded(ptfxAsset) do
            if GetGameTimer() > timeout then
                return
            end
            Wait(0)
        end
    end
    UseParticleFxAssetNextCall(ptfxAsset)
    StartNetworkedParticleFxNonLoopedAtCoord("water_splash_veh_in", x, y, z + 0.1, 0.0, 0.0, 0.0, 1.1, false, false, false, false)
end

function GetBobberModel()
    local hash = joaat("custom_fishing_bobber_01")
    if not IsModelInCdimage(hash) then
        return 136236575, false
    end
    return hash, true
end

CreateThread(function()
    Wait(1000)
    local model = GetBobberModel()
    RequestModel(model)
end)

function CastLineToWater(waterData)
    if not waterData then
        return false
    end
    local bobberModel, isCustomBobber = GetBobberModel()
    RequestModel(bobberModel)
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(bobberModel) do
        if GetGameTimer() > timeout then
            return false
        end
        Wait(0)
    end

    local startCoords = GetRodTipCoords() or vector3(waterData.x, waterData.y, waterData.height)
    Player.invisibleProp = CreateObject(bobberModel, startCoords.x, startCoords.y, startCoords.z, false, false, true)
    if not DoesEntityExist(Player.invisibleProp) then
        return false
    end

    SetEntityVisible(Player.invisibleProp, isCustomBobber, false)
    SetEntityCollision(Player.invisibleProp, false, false)
    FreezeEntityPosition(Player.invisibleProp, true)

    RopeLoadTextures()
    local ropeTimeout = GetGameTimer() + 5000
    while not RopeAreTexturesLoaded() do
        if GetGameTimer() > ropeTimeout then
            break
        end
        Wait(0)
    end

    local rodCoords = GetEntityCoords(Player.rod)
    Player.rope = AddRope(rodCoords.x, rodCoords.y, rodCoords.z, 0.0, 0.0, 0.0, 3.0, 5, 10.0, 15.0, 0.5, true, true, true, 1.0, false, 0)
    local targetPos = vector3(waterData.x, waterData.y, waterData.height)
    if Player.rope == 0 then
        Player.rope = nil
    end

    if Player.rope and DoesEntityExist(Player.rod) and DoesEntityExist(Player.invisibleProp) then
        local dist = #(targetPos - startCoords)
        local ropeLength = math.max(dist, 1.0)
        AttachEntitiesToRope(Player.rope, Player.rod, Player.invisibleProp, startCoords.x, startCoords.y, startCoords.z, startCoords.x, startCoords.y, startCoords.z, ropeLength, false, false, 0, 0)
    end

    local netId = NetworkGetNetworkIdFromEntity(Player.rod)
    if netId and netId ~= 0 then
        SetNetworkIdExistsOnAllMachines(netId, true)
        Player.lineAnnounced = true
        TriggerServerEvent("qs-fisher:lineOut", netId, targetPos.x, targetPos.y, targetPos.z)
    end

    local flightDuration = 750
    local flightDist = #(targetPos - startCoords)
    if flightDuration > 0 and flightDist > 1.0 then
        local arcHeight = flightDist * 0.16
        local flightStartTimer = GetGameTimer()
        while true do
            local elapsed = (GetGameTimer() - flightStartTimer) / flightDuration
            if elapsed >= 1.0 or not isFishing or not DoesEntityExist(Player.invisibleProp) then
                break
            end
            local curX = startCoords.x + (targetPos.x - startCoords.x) * elapsed
            local curY = startCoords.y + (targetPos.y - startCoords.y) * elapsed
            local curZ = startCoords.z + (targetPos.z - startCoords.z) * elapsed + math.sin(elapsed * math.pi) * arcHeight
            SetEntityCoordsNoOffset(Player.invisibleProp, curX, curY, curZ, false, false, false)
            local tipCoords = GetRodTipCoords()
            if tipCoords and Player.rope then
                local currentDist = #(vector3(curX, curY, curZ) - tipCoords)
                RopeForceLength(Player.rope, math.max(currentDist, 1.0))
            end
            Wait(0)
        end
    end

    if not DoesEntityExist(Player.invisibleProp) then
        return false
    end

    SetEntityCoordsNoOffset(Player.invisibleProp, targetPos.x, targetPos.y, targetPos.z, false, false, false)
    local tip = GetRodTipCoords()
    if tip and Player.rope then
        RopeForceLength(Player.rope, math.max(#(targetPos - tip), 1.0))
    end
    SpawnSplashPtfx(targetPos.x, targetPos.y, targetPos.z)
    return true
end

local RemoteLines = {}
local REMOTE_LINE_MAX_DIST = 150.0

function GetRemoteRodTip(rodEntity)
    return GetOffsetFromEntityInWorldCoords(rodEntity, 0.0, -0.01, 2.52)
end

function RemoveRemoteLine(serverId)
    local lineData = RemoteLines[serverId]
    if not lineData then
        return
    end
    RemoteLines[serverId] = nil
    if lineData.rope then
        DeleteRope(lineData.rope)
    end
    if lineData.box and DoesEntityExist(lineData.box) then
        DetachEntity(lineData.box, true, true)
        DeleteEntity(lineData.box)
    end
end

function ClearAllRemoteLines()
    for serverId in pairs(RemoteLines) do
        RemoveRemoteLine(serverId)
    end
end

function StartDangling()
    if Player.dangling or not Player.rod or not DoesEntityExist(Player.rod) then
        return
    end
    local netId = NetworkGetNetworkIdFromEntity(Player.rod)
    if not netId or netId == 0 then
        return
    end
    SetNetworkIdExistsOnAllMachines(netId, true)
    Player.dangling = true
    TriggerServerEvent("qs-fisher:dangleOut", netId)
end

function StopDangling()
    if not Player.dangling then
        return
    end
    Player.dangling = nil
    TriggerServerEvent("qs-fisher:dangleIn")
end

RegisterNetEvent("qs-fisher:remoteLineOut", function(serverId, rodNet, x, y, z, isInstant)
    if serverId == GetPlayerServerId(PlayerId()) or not rodNet or not x then
        return
    end
    RemoveRemoteLine(serverId)
    RemoteLines[serverId] = {
        rodNet = rodNet,
        target = vector3(x + 0.0, y + 0.0, z + 0.0),
        startedAt = GetGameTimer(),
        instant = (isInstant == true)
    }
end)

RegisterNetEvent("qs-fisher:remoteLineIn", function(serverId)
    RemoveRemoteLine(serverId)
end)

RegisterNetEvent("qs-fisher:remoteDangleOut", function(serverId, rodNet)
    if not rodNet then
        return
    end
    RemoveRemoteLine(serverId)
    RemoteLines[serverId] = {
        rodNet = rodNet,
        dangle = true,
        startedAt = GetGameTimer()
    }
end)

CreateThread(function()
    local bobberModel, isCustomBobber = GetBobberModel()
    while true do
        if next(RemoteLines) == nil then
            Wait(500)
        else
            local pedCoords = GetEntityCoords(PlayerPedId())
            local hasActiveLine = false

            for serverId, lineData in pairs(RemoteLines) do
                local rodEntity = nil
                if NetworkDoesNetworkIdExist(lineData.rodNet) then
                    local ent = NetworkGetEntityFromNetworkId(lineData.rodNet)
                    if ent ~= 0 and DoesEntityExist(ent) then
                        rodEntity = ent
                    end
                end

                local inRange = false
                if rodEntity then
                    inRange = #(GetEntityCoords(rodEntity) - pedCoords) <= REMOTE_LINE_MAX_DIST
                end

                if not rodEntity or not inRange then
                    if lineData.rope then
                        DeleteRope(lineData.rope)
                        lineData.rope = nil
                    end
                    if lineData.box and DoesEntityExist(lineData.box) then
                        DeleteEntity(lineData.box)
                        lineData.box = nil
                    end
                    if not rodEntity and (GetGameTimer() - lineData.startedAt) > 3600000 then
                        RemoveRemoteLine(serverId)
                    end
                else
                    hasActiveLine = true
                    local tipCoords = GetRemoteRodTip(rodEntity)

                    if not lineData.box or not DoesEntityExist(lineData.box) then
                        if not HasModelLoaded(bobberModel) then
                            RequestModel(bobberModel)
                        else
                            local boxEntity = CreateObject(bobberModel, tipCoords.x, tipCoords.y, tipCoords.z, false, false, true)
                            if DoesEntityExist(boxEntity) then
                                SetEntityVisible(boxEntity, isCustomBobber, false)
                                SetEntityCollision(boxEntity, false, false)
                                FreezeEntityPosition(boxEntity, true)
                                lineData.box = boxEntity
                                lineData.flightFrom = GetGameTimer()
                            end
                        end
                    end

                    if lineData.box and DoesEntityExist(lineData.box) then
                        local bobberPos = nil
                        if lineData.dangle then
                            bobberPos = vector3(tipCoords.x, tipCoords.y, tipCoords.z - 1.5)
                        else
                            local duration = lineData.instant and 0 or 750
                            if not lineData.flightStart then
                                lineData.flightStart = tipCoords
                            end
                            local totalDist = #(lineData.target - lineData.flightStart)
                            local progress = 1.0
                            if duration > 0 and totalDist > 1.0 then
                                local elapsed = GetGameTimer() - (lineData.flightFrom or 0)
                                progress = elapsed / duration
                                if progress > 1.0 then
                                    progress = 1.0
                                end
                            end
                            if progress >= 1.0 then
                                bobberPos = lineData.target
                                lineData.instant = true
                            else
                                local arc = totalDist * 0.16
                                local px = lineData.flightStart.x + (lineData.target.x - lineData.flightStart.x) * progress
                                local py = lineData.flightStart.y + (lineData.target.y - lineData.flightStart.y) * progress
                                local pz = lineData.flightStart.z + (lineData.target.z - lineData.flightStart.z) * progress + math.sin(progress * math.pi) * arc
                                bobberPos = vector3(px, py, pz)
                            end
                        end

                        SetEntityCoordsNoOffset(lineData.box, bobberPos.x, bobberPos.y, bobberPos.z, false, false, false)
                        local dist = #(bobberPos - tipCoords)
                        local ropeLength = lineData.dangle and math.max(dist, 0.05) or math.max(dist, 1.0)

                        if not lineData.rope then
                            RopeLoadTextures()
                            if RopeAreTexturesLoaded() then
                                if lineData.dangle then
                                    lineData.rope = AddRope(tipCoords.x, tipCoords.y, tipCoords.z, 0.0, 0.0, 0.0, ropeLength, 5, ropeLength, ropeLength, 0.1, true, true, true, 1.0, false, 0)
                                else
                                    lineData.rope = AddRope(tipCoords.x, tipCoords.y, tipCoords.z, 0.0, 0.0, 0.0, 3.0, 5, 10.0, 15.0, 0.5, true, true, true, 1.0, false, 0)
                                end
                                if lineData.rope == 0 then
                                    lineData.rope = nil
                                end
                                if lineData.rope and DoesEntityExist(rodEntity) and DoesEntityExist(lineData.box) then
                                    AttachEntitiesToRope(lineData.rope, rodEntity, lineData.box, tipCoords.x, tipCoords.y, tipCoords.z, bobberPos.x, bobberPos.y, bobberPos.z, ropeLength, false, false, 0, 0)
                                end
                            end
                        end

                        if lineData.rope then
                            RopeForceLength(lineData.rope, ropeLength)
                        end
                    end
                end
            end
            Wait(hasActiveLine and 0 or 250)
        end
    end
end)

CreateThread(function()
    Wait(1500)
    local lines = lib.callback.await("qs-fisher:getActiveLines", false) or {}
    for serverId, data in pairs(lines) do
        TriggerEvent("qs-fisher:remoteLineOut", tonumber(serverId), data.rod, data.x, data.y, data.z, true)
    end
end)

local ShowcaseCamConfig = {
    fishModel = 802685111,
    blendIn = 900,
    blendOut = 700,
    minTime = 2500,
    maxTime = 20000,
    dangle = 0.825,
    fishOffset = { x = 0.15, y = 0.85, z = 0.175 },
    fishPitch = -4.0,
    fishRoll = 0.0,
    fishYaw = 170.0,
    sway = {
        yaw = 4.0,
        speedYaw = 1.15,
        roll = 3.0,
        speedRoll = 0.8,
        pitch = 2.0,
        speedPitch = 1.35,
        bob = 0.012,
        speedBob = 1.7,
        tremor = 0.35,
        speedTremor = 3.3,
        every = 3000,
        lasts = 700,
        gain = 2.2
    },
    fishHealth = 20000,
    camSide = 1.75,
    camFront = 0.7,
    camHeight = 0.1,
    frameShift = 0.62,
    orbit = 6.0,
    maxShown = 4,
    spread = 0.3
}

local isShowcaseActive = false

function StopCatchShowcase(camData)
    if not camData then
        return
    end
    isShowcaseActive = false
    if camData.cam then
        RenderScriptCams(false, true, ShowcaseCamConfig.blendOut, true, true)
        DestroyCam(camData.cam, false)
    end
    for _, fishPed in ipairs(camData.fish or {}) do
        if DoesEntityExist(fishPed) then
            DetachEntity(fishPed, true, true)
            SetEntityAsMissionEntity(fishPed, true, true)
            DeleteEntity(fishPed)
        end
    end
    if camData.anchor and DoesEntityExist(camData.anchor) then
        SetEntityAsMissionEntity(camData.anchor, true, true)
        DeleteEntity(camData.anchor)
    end
    local ped = PlayerPedId()
    SetEntityVisible(ped, true, false)
    if Player.rod and DoesEntityExist(Player.rod) then
        SetEntityVisible(Player.rod, true, false)
    end
    AttachRodToHand(ped)
end

function GetSwayDelta(timeSec, baseAmp, speed, tremorSpeed, gain)
    local sway = ShowcaseCamConfig.sway
    return (math.sin(timeSec * speed) + sway.tremor * math.sin(timeSec * tremorSpeed)) * baseAmp * gain
end

function GetSwayGain(timeMs)
    local sway = ShowcaseCamConfig.sway
    local cycleTime = timeMs % sway.every
    if cycleTime >= sway.lasts then
        return 1.0
    end
    return 1.0 + (sway.gain - 1.0) * math.sin(math.pi * (cycleTime / sway.lasts))
end

function SetFishPedAttributes(camData, fishPed, index, total)
    if not fishPed or not DoesEntityExist(fishPed) then
        return
    end
    SetEntityHealth(fishPed, 0)
    ResurrectPed(fishPed)
    SetEntityCollision(fishPed, false, false)
    SetEntityInvincible(fishPed, true)
    SetPedCanRagdoll(fishPed, false)
    SetPedDiesInWater(fishPed, false)
    SetPedDiesInstantlyInWater(fishPed, false)
    SetPedDiesWhenInjured(fishPed, false)
    SetPedSuffersCriticalHits(fishPed, false)
    SetEntityProofs(fishPed, true, true, true, true, true, true, true, true)
    SetPedMaxHealth(fishPed, ShowcaseCamConfig.fishHealth)
    SetEntityMaxHealth(fishPed, ShowcaseCamConfig.fishHealth)
    SetEntityHealth(fishPed, ShowcaseCamConfig.fishHealth)
    SetEntityCanBeDamaged(fishPed, false)
    SetPedCanBeTargetted(fishPed, false)

    if camData.anchor and DoesEntityExist(camData.anchor) then
        local spreadX = 0.0
        local count = total or 1
        if count > 1 then
            spreadX = (index - (count + 1) / 2) * ShowcaseCamConfig.spread
        end
        AttachEntityToEntity(fishPed, camData.anchor, 0, spreadX, 0.0, 0.0, 0.0, 0.0, 0.0, false, false, false, true, 2, true)
    end
end

function AttachAllFish(camData)
    local count = #camData.fish
    for index, fishPed in ipairs(camData.fish) do
        SetFishPedAttributes(camData, fishPed, index, count)
    end
end

function StartCatchShowcase(canKeepCb, count, minTime, itemName)
    if isShowcaseActive then
        return
    end
    local ped = PlayerPedId()
    local tipCoords = GetRodTipCoords()
    if not tipCoords then
        return
    end
    isShowcaseActive = true
    local camData = { fish = {} }
    local duration = minTime or ShowcaseCamConfig.minTime
    local fishCount = math.max(1, math.min(math.floor(count or 1), ShowcaseCamConfig.maxShown))

    local modelName = itemName and Config.CatchModels and Config.CatchModels[itemName]
    local modelHash = modelName and GetHashKey(modelName) or ShowcaseCamConfig.fishModel

    RequestModel(modelHash)
    local timeout = GetGameTimer() + 3000
    while not HasModelLoaded(modelHash) do
        if GetGameTimer() > timeout then
            isShowcaseActive = false
            return
        end
        Wait(0)
    end

    for _ = 1, fishCount do
        local fishPed = CreatePed(4, modelHash, tipCoords.x, tipCoords.y, tipCoords.z - ShowcaseCamConfig.dangle, 0.0, false, false)
        if DoesEntityExist(fishPed) then
            SetEntityAsMissionEntity(fishPed, true, true)
            camData.fish[#camData.fish + 1] = fishPed
        end
    end
    SetModelAsNoLongerNeeded(modelHash)

    if #camData.fish == 0 then
        isShowcaseActive = false
        return
    end

    camData.anchorPos = GetOffsetFromEntityInWorldCoords(ped, ShowcaseCamConfig.fishOffset.x, ShowcaseCamConfig.fishOffset.y, ShowcaseCamConfig.fishOffset.z)
    camData.baseHeading = GetEntityHeading(ped)
    camData.anchor = CreateObject(136236575, camData.anchorPos.x, camData.anchorPos.y, camData.anchorPos.z, false, false, false)

    if DoesEntityExist(camData.anchor) then
        SetEntityVisible(camData.anchor, false, false)
        SetEntityCollision(camData.anchor, false, false)
        SetEntityRotation(camData.anchor, ShowcaseCamConfig.fishPitch, ShowcaseCamConfig.fishRoll, camData.baseHeading + ShowcaseCamConfig.fishYaw, 2, false)
        FreezeEntityPosition(camData.anchor, true)
    end

    AttachAllFish(camData)
    ClearPedTasks(ped)
    AttachRodToHand(ped)

    CreateThread(function()
        while isShowcaseActive do
            SetEntityLocallyInvisible(PlayerPedId())
            if Player.rod and DoesEntityExist(Player.rod) then
                SetEntityLocallyInvisible(Player.rod)
            end
            Wait(0)
        end
    end)

    camData.cam = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)
    SetCamActive(camData.cam, true)
    RenderScriptCams(true, true, ShowcaseCamConfig.blendIn, true, true)

    local startTimer = GetGameTimer()
    CreateThread(function()
        while isShowcaseActive do
            local now = GetGameTimer()
            local elapsed = now - startTimer
            local playerPed = PlayerPedId()
            local timeSec = now / 1000.0

            if camData.fish[1] and DoesEntityExist(camData.fish[1]) then
                local totalFish = #camData.fish
                for idx, fishPed in ipairs(camData.fish) do
                    SetEntityHealth(fishPed, ShowcaseCamConfig.fishHealth)
                    if IsPedDeadOrDying(fishPed, true) then
                        SetFishPedAttributes(camData, fishPed, idx, totalFish)
                    end
                end

                if camData.anchor and DoesEntityExist(camData.anchor) then
                    local sway = ShowcaseCamConfig.sway
                    local gain = GetSwayGain(now)
                    local rotPitch = ShowcaseCamConfig.fishPitch + GetSwayDelta(timeSec, sway.pitch, sway.speedPitch, sway.speedTremor * 1.27, gain)
                    local rotRoll = ShowcaseCamConfig.fishRoll + GetSwayDelta(timeSec, sway.roll, sway.speedRoll, sway.speedTremor * 0.83, gain)
                    local rotYaw = camData.baseHeading + ShowcaseCamConfig.fishYaw + GetSwayDelta(timeSec, sway.yaw, sway.speedYaw, sway.speedTremor, gain)
                    SetEntityRotation(camData.anchor, rotPitch, rotRoll, rotYaw, 2, false)

                    local bobZ = camData.anchorPos.z + math.sin(timeSec * sway.speedBob) * sway.bob * gain
                    SetEntityCoordsNoOffset(camData.anchor, camData.anchorPos.x, camData.anchorPos.y, bobZ, false, false, false)
                end

                local anchorCoords = GetEntityCoords(camData.anchor)
                local forward = GetEntityForwardVector(playerPed)
                local sideVector = vector3(forward.y, -forward.x, 0.0)
                local orbitOffset = math.sin(timeSec * 0.6) * (ShowcaseCamConfig.orbit / 60.0)

                local sideAmp = ShowcaseCamConfig.camSide + orbitOffset
                local frontAmp = ShowcaseCamConfig.camFront
                local camX = anchorCoords.x + sideVector.x * sideAmp + forward.x * frontAmp
                local camY = anchorCoords.y + sideVector.y * sideAmp + forward.y * frontAmp
                local camZ = anchorCoords.z + ShowcaseCamConfig.camHeight
                local camPos = vector3(camX, camY, camZ)

                local diff = anchorCoords - camPos
                local diffLen = math.sqrt(diff.x * diff.x + diff.y * diff.y)
                local frameVector = sideVector
                if diffLen > 0.01 then
                    frameVector = vector3(diff.y / diffLen, -diff.x / diffLen, 0.0)
                end

                SetCamCoord(camData.cam, camPos.x, camPos.y, camPos.z)
                local pointAtX = anchorCoords.x + frameVector.x * ShowcaseCamConfig.frameShift
                local pointAtY = anchorCoords.y + frameVector.y * ShowcaseCamConfig.frameShift
                local pointAtZ = anchorCoords.z
                PointCamAtCoord(camData.cam, pointAtX, pointAtY, pointAtZ)
            end

            if elapsed > ShowcaseCamConfig.maxTime then
                break
            end
            if elapsed >= duration and canKeepCb and not canKeepCb() then
                break
            end
            Wait(0)
        end
        StopCatchShowcase(camData)
    end)
end

function ResetFishingState()
    local ped = PlayerPedId()
    isFighting = false
    isFishing = false
    ClearPedTasks(ped)
    AttachRodToHand(ped)
    CleanPlayerLine()
    SendNUIMessage({
        action = "help",
        text = "close"
    })
end

function DepthLabel(depth)
    if not depth then
        return "?"
    end
    return Lang("DEPTH_" .. depth:upper())
end

function FormatWeight(weight)
    local num = tonumber(weight) or 0
    local unit = Config.WeightUnit or "kg"
    if unit == "lb" then
        local lbs = num * (Config.PoundsPerKilo or 2.20462)
        return ("%.2f"):format(lbs), "lb"
    end
    return ("%.2f"):format(num), "kg"
end

function DepthText(depth, band)
    return ("%.1f m · %s"):format(depth or 0, DepthLabel(band))
end

function DepthList(bands)
    local list = {}
    for _, band in ipairs(bands or {}) do
        list[#list + 1] = DepthLabel(band)
    end
    return table.concat(list, " / ")
end

function OpenCatchDecisionModal(token, catchData)
    activeDecisionToken = token
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = "catchDecision",
        label = catchData.label,
        item = catchData.item,
        amount = catchData.amount,
        stats = catchData.stats,
        specimens = catchData.specimens,
        previousBest = catchData.previousBest,
        timeout = catchData.timeout
    })
    CreateThread(function()
        local expireTimer = GetGameTimer() + (catchData.timeout or 9000)
        while activeDecisionToken == token and expireTimer > GetGameTimer() do
            Wait(100)
        end
        if activeDecisionToken ~= token then
            return
        end
        activeDecisionToken = nil
        SetNuiFocus(false, false)
        SendNUIMessage({ action = "catchDecisionClose" })
        local timeoutKeeps = Config.CatchDecision and Config.CatchDecision.TimeoutKeeps ~= false
        local result = lib.callback.await("qs-fisher:decideCatch", false, token, timeoutKeeps)
        if result then
            ReportCatchSettled(result)
        end
    end)
end

function ReportCatchSettled(data)
    if not data then
        return
    end
    if data.kept then
        CreateNotification("notify", "success", Lang("CATCH_KEPT"):format(data.carried or data.amount or 1, data.label or "?"))
    elseif not data.missingItem then
        CreateNotification("notify", "info", Lang("CATCH_RELEASED"):format(data.label or "?"))
    end
    if data.newRecord then
        CreateNotification("notify", "success", Lang("NEW_PERSONAL_BEST"):format(data.label or "?"))
    end
end

function ResolveCatch(token, success, cancelled)
    local result = lib.callback.await("qs-fisher:resolveCatch", false, token, success, cancelled)
    if not result then
        -- A nil answer means the server threw before it could settle the catch
        -- (a database error, usually). Say it out loud instead of losing the fish
        -- in silence: previously this was an empty `return` with no trace at all.
        print("^3[qs-fishingjob]^0 the server did not settle this catch — check the server console for the error above.")
        CreateNotification("notify", "error", Lang("CATCH_NOT_SETTLED"))
        return
    end
    if result.cancelled then
        return
    end
    if result.extra then
        CreateNotification("notify", "success", Lang("YOU_CAUGHT_AN_EXTRA_FISH"))
    end
    if result.garbage then
        CreateNotification("notify", "error", Lang("CATCH_GARBAGE"))
    elseif result.item then
        if result.stats and result.stats.trophy then
            CreateNotification("notify", "success", Lang("TROPHY_CATCH"):format(result.label or "?"))
        end
        if result.decide then
            activeDecisionToken = token
            StartCatchShowcase(function()
                return activeDecisionToken == token
            end, result.amount, 0, result.item)
            OpenCatchDecisionModal(token, result)
        else
            StartCatchShowcase(function()
                return false
            end, result.amount, nil, result.item)
        end
    end
    if result.rodBroke then
        DeleteFishingRod()
        local ped = PlayerPedId()
        SetPedConfigFlag(ped, 48, false)
        SetPedConfigFlag(ped, 122, false)
        CreateNotification("notify", "error", Lang("FISHING_ROD_BROKE"))
    end
end

function StartFishingFight(token, fightConfig)
    local ped = PlayerPedId()
    local pedCoords = GetEntityCoords(ped)
    local bobberCoords = GetEntityCoords(Player.invisibleProp)
    isFighting = true

    local cfg = fightConfig or {}
    local maxAngle = cfg.maxAngle or FishingConfig.MaxAngle
    local pullSpeed = cfg.pullSpeed or FishingConfig.PullSpeed
    local slipSpeed = cfg.slipSpeed or FishingConfig.SlipSpeed
    local turnRate = cfg.turnRate or 1.0
    local deadZone = FishingConfig.DeadZone
    local minDistance = FishingConfig.MinDistance
    local waterZ = bobberCoords.z

    local dx = pedCoords.x - bobberCoords.x
    local dy = pedCoords.y - bobberCoords.y
    local initialDist = math.max(math.sqrt(dx * dx + dy * dy), minDistance + 0.1)

    local targetSide = nil
    local tension = 0.0
    local randomDuration = (math.random(50, 100) / 100) / turnRate
    local tensionDecay = (math.random(10, 20) / 1000) * turnRate

    SendNUIMessage({
        action = "fishingStart",
        bait = CurrentGear.bait or CurrentGear.hook
    })

    function GetAngleDelta()
        local camRot = GetGameplayCamRot(2).z
        -- IMPORTANT: everything below must be in the SAME unit before it is compared.
        -- math.atan(y, x) returns RADIANS, while camRot is in DEGREES, so the two are
        -- combined in radians and converted once, at the end. Converting the atan to
        -- degrees first (and then converting the result again) multiplies the angle by
        -- ~57 twice and yields values in the thousands of degrees, which is instantly
        -- "absAngle > maxAngle" => the line snaps on the very first frame.
        local angleToBobber = math.deg(math.atan(bobberCoords.y - pedCoords.y, bobberCoords.x - pedCoords.x) - math.rad(camRot))
        local diff = angleToBobber
        if diff > 180 then
            diff = diff - 360
        elseif diff < -180 then
            diff = diff + 360
        end
        return diff - 90.0
    end

    if Config.FishParticles then
        CreateThread(function()
            local ptfx = "core"
            if not HasNamedPtfxAssetLoaded(ptfx) then
                RequestNamedPtfxAsset(ptfx)
                local timeout = GetGameTimer() + 3000
                while not HasNamedPtfxAssetLoaded(ptfx) do
                    if GetGameTimer() > timeout then
                        return
                    end
                    Wait(10)
                end
            end
            while isFighting do
                if Player.invisibleProp and DoesEntityExist(Player.invisibleProp) then
                    local propCoords = GetEntityCoords(Player.invisibleProp)
                    UseParticleFxAssetNextCall(ptfx)
                    StartNetworkedParticleFxNonLoopedAtCoord("water_splash_veh_in", propCoords.x, propCoords.y, propCoords.z + 0.15, 0.0, 0.0, 0.0, 0.8, false, false, false, false)
                end
                Wait(200)
            end
            RemoveNamedPtfxAsset(ptfx)
        end)
    end

    CreateThread(function()
        local lastUpdate = 0
        while isFighting do
            if not Player.invisibleProp or not DoesEntityExist(Player.invisibleProp) then
                break
            end
            pedCoords = GetEntityCoords(ped)
            bobberCoords = GetEntityCoords(Player.invisibleProp)

            local angle = GetAngleDelta()
            local absAngle = math.abs(angle)
            local dangerPct = math.floor((absAngle / maxAngle) * 100)

            if absAngle > maxAngle or IsControlJustPressed(0, 200) then
                isFighting = false
                SendNUIMessage({
                    action = "fishingEnd",
                    success = false
                })
                ResetFishingState()
                ResolveCatch(token, false)
                return
            end

            local side = "center"
            if angle > deadZone then
                side = "right"
            elseif angle < -deadZone then
                side = "left"
            end

            if not targetSide and side ~= "center" then
                targetSide = (side == "left") and "right" or "left"
            end

            local isPullingCorrectly = (side == targetSide)
            if isPullingCorrectly then
                tension = tension + (absAngle / maxAngle) * FishingConfig.GainRate
                if tension >= randomDuration then
                    targetSide = (targetSide == "left") and "right" or "left"
                    tension = 0.0
                    randomDuration = (math.random(50, 100) / 100) / turnRate
                    tensionDecay = (math.random(10, 20) / 1000) * turnRate
                end
            else
                tension = math.max(tension - tensionDecay, 0.0)
            end

            local deltaX = pedCoords.x - bobberCoords.x
            local deltaY = pedCoords.y - bobberCoords.y
            local currentDist = math.sqrt(deltaX * deltaX + deltaY * deltaY)
            local normX, normY = 0.0, 0.0
            if currentDist > 0 then
                normX = deltaX / currentDist
                normY = deltaY / currentDist
            end

            if isPullingCorrectly then
                currentDist = currentDist - (absAngle / maxAngle) * pullSpeed
            else
                currentDist = currentDist + slipSpeed
            end

            currentDist = math.max(math.min(currentDist, initialDist), minDistance)
            SetEntityCoords(Player.invisibleProp, pedCoords.x - normX * currentDist, pedCoords.y - normY * currentDist, waterZ, false, false, false, true)

            local progress = math.max(0.0, math.min((initialDist - currentDist) / (initialDist - minDistance), 1.0))
            local now = GetGameTimer()
            if (now - lastUpdate) >= FishingConfig.UpdateRate then
                lastUpdate = now
                SendNUIMessage({
                    action = "fishingStatus",
                    progress = math.floor(progress * 100),
                    danger = dangerPct,
                    side = targetSide
                })
            end

            if progress >= 1.0 then
                isFighting = false
                SendNUIMessage({
                    action = "fishingStatus",
                    progress = 100,
                    danger = dangerPct,
                    side = nil
                })
                SendNUIMessage({
                    action = "fishingEnd",
                    success = true
                })
                ResetFishingState()
                ResolveCatch(token, true)
                return
            end
            Wait(0)
        end

        if isFishing then
            SendNUIMessage({
                action = "fishingEnd",
                success = false
            })
            ResetFishingState()
            ResolveCatch(token, false)
        end
    end)
end

function ChargeCastPower()
    if not Config.Cast or not Config.Cast.Enabled then
        return 1.0
    end
    local castConfig = Config.Cast
    local animDuration = CHARGE_ANIM_DURATION
    local ped = PlayerPedId()
    local isCharging = false
    local startTime = 0
    local power = 0.0
    local expireTime = GetGameTimer() + CAST_MAX_TIME

    PlayFishingAnim(ped, "charge")
    AttachRodCast(ped)

    SendNUIMessage({
        action = "castStart",
        cancelKey = Config.Keys and Config.Keys.InteractKeyLabel or "E"
    })
    StartDangling()

    local cancelPressed = not IsControlPressed(0, Config.Keys and Config.Keys.InteractKey or 38)

    function CancelCast()
        SendNUIMessage({ action = "castEnd" })
        StopDangling()
        ClearPedTasks(ped)
    end

    while true do
        local now = GetGameTimer()
        DisableControlAction(0, 24, true)
        DisableControlAction(0, 25, true)
        DisableControlAction(0, 140, true)
        DisablePlayerFiring(PlayerId(), true)

        if not cancelPressed then
            if not IsControlPressed(0, Config.Keys and Config.Keys.InteractKey or 38) then
                cancelPressed = true
            end
        end

        if IsControlJustPressed(0, 200) or (cancelPressed and IsControlJustPressed(0, Config.Keys and Config.Keys.InteractKey or 38)) then
            CancelCast()
            return nil
        end

        if not isCharging then
            if IsDisabledControlJustPressed(0, 24) then
                isCharging = true
                startTime = now
                expireTime = now + CAST_MAX_TIME
                SendNUIMessage({ action = "castCharging" })
            elseif now > expireTime then
                CancelCast()
                return nil
            end
        else
            local cycle = (now - startTime) % (animDuration * 2) / animDuration
            if cycle <= 1.0 then
                power = cycle
            else
                power = 2.0 - cycle
            end
            local distRange = castConfig.MaxDistance - castConfig.MinDistance
            local calcDist = math.floor(castConfig.MinDistance + distRange * power + 0.5)

            SendNUIMessage({
                action = "castPower",
                power = math.floor(power * 100),
                distance = calcDist
            })

            if not IsDisabledControlPressed(0, 24) or now > expireTime then
                break
            end
        end
        Wait(0)
    end

    StopDangling()
    SendNUIMessage({
        action = "castEnd",
        power = math.floor(power * 100)
    })
    return power
end

function GetProbeMaxDistance()
    return PROBE_MAX_DIST
end

function GetMaxCastDistance()
    if not Config.Cast or not Config.Cast.Enabled then
        return FishingConfig.CastDistance
    end
    return Config.Cast.MaxDistance or FishingConfig.CastDistance
end

function StartFishing(cachedWaterData)
    if isFishing or isFighting then
        return
    end
    local ped = PlayerPedId()
    local waterData = cachedWaterData or ProbeWater(ped, GetProbeMaxDistance())
    if not waterData then
        CreateNotification("notify", "error", Lang("YOU_ARE_NOT_FACING_THE_WATER"))
        return
    end

    local power = ChargeCastPower()
    if not power then
        return
    end

    waterData = ProbeWater(ped, GetProbeMaxDistance())
    if not waterData then
        ClearPedTasks(ped)
        CreateNotification("notify", "error", Lang("YOU_ARE_NOT_FACING_THE_WATER"))
        return
    end

    local castResult = lib.callback.await("qs-fisher:beginCast", false, waterData.band, power, waterData.depth)
    if not castResult or not castResult.ok then
        ClearPedTasks(ped)
        local reasonMsg = Lang(castResult and castResult.reason or "CAST_REFUSED")
        if castResult and castResult.requiredLevel then
            reasonMsg = reasonMsg:format(castResult.requiredLevel)
        elseif castResult and castResult.allowedDepth then
            reasonMsg = reasonMsg:format(("%.1f"):format(castResult.allowedDepth))
        end
        CreateNotification("notify", "error", reasonMsg)
        return
    end

    isFishing = true
    local played = PlayFishingAnim(ped, "cast")
    AttachRodCast(ped)
    if played then
        Wait(300)
    end

    local finalDistance = castResult.distance or GetMaxCastDistance()
    waterData = ProbeWater(ped, finalDistance)
    if not waterData then
        ResetFishingState()
        ResolveCatch(castResult.token, false, true)
        CreateNotification("notify", "error", Lang("YOU_ARE_NOT_FACING_THE_WATER"))
        return
    end

    if not CastLineToWater(waterData) then
        ResetFishingState()
        CreateNotification("notify", "error", Lang("CAST_REFUSED"))
        return
    end

    PlayFishingAnim(ped, "idle")
    SendNUIMessage({
        action = "biteStart",
        wait = castResult.waitTime,
        window = FishingConfig.BiteWindow
    })

    CreateThread(function()
        local waitExpire = GetGameTimer() + castResult.waitTime
        SendNUIMessage({
            action = "help",
            text = Lang("REEL_IN_HINT"),
            type = "info"
        })

        while GetGameTimer() < waitExpire do
            if not isFishing then
                return
            end
            if IsControlJustPressed(0, 200) or IsControlJustPressed(0, Config.Keys and Config.Keys.InteractKey or 38) then
                SendNUIMessage({ action = "help", text = "close" })
                SendNUIMessage({ action = "biteClose" })
                ResetFishingState()
                ResolveCatch(castResult.token, false, true)
                CreateNotification("notify", "info", Lang("CAST_CANCELLED"))
                return
            end
            Wait(0)
        end

        SendNUIMessage({ action = "help", text = "close" })
        if not isFishing then
            return
        end

        local hooked = false
        local windowExpire = GetGameTimer() + FishingConfig.BiteWindow

        while GetGameTimer() < windowExpire do
            Wait(0)
            if not isFishing then
                return
            end
            if IsControlJustPressed(0, 200) then
                SendNUIMessage({ action = "biteClose" })
                ResetFishingState()
                ResolveCatch(castResult.token, false, true)
                CreateNotification("notify", "info", Lang("CAST_CANCELLED"))
                return
            end
            if IsControlJustPressed(0, Config.Keys and Config.Keys.InteractKey or 38) then
                hooked = true
                break
            end
        end

        SendNUIMessage({ action = "biteClose" })
        if not hooked then
            ResetFishingState()
            ResolveCatch(castResult.token, false)
            return
        end

        Wait(300)
        if not isFishing then
            return
        end

        PlayFishingAnim(PlayerPedId(), "fight")
        StartFishingFight(castResult.token, castResult.fight)
    end)
end

CreateThread(function()
    local cachedWater = nil
    local lastProbeTime = 0
    local lastDepthMeterState = {}
    local cachedDepthLimit = nil
    local lastDepthLimitCheck = 0

    function GetCachedDepthLimit()
        local now = GetGameTimer()
        if not cachedDepthLimit or (now - lastDepthLimitCheck) > 15000 then
            lastDepthLimitCheck = now
            cachedDepthLimit = lib.callback.await("qs-fisher:getDepthLimit", false) or 0
        end
        return cachedDepthLimit
    end

    local lastMeterThrottle = nil
    function UpdateDepthMeter(water, canCast, reason, hideAction)
        local THROTTLE_MS = 600
        if water then
            lastMeterThrottle = nil
        else
            if not lastMeterThrottle then
                lastMeterThrottle = GetGameTimer()
            end
            if lastDepthMeterState.band ~= nil and (GetGameTimer() - lastMeterThrottle) < THROTTLE_MS then
                return
            end
        end

        local band = water and water.band or nil
        local roundedDepth = water and (math.floor(water.depth * 10 + 0.5) / 10) or nil
        local isShore = water and water.shore or false

        if band == lastDepthMeterState.band
            and roundedDepth == lastDepthMeterState.depth
            and isShore == lastDepthMeterState.shore
            and canCast == lastDepthMeterState.canCast
            and reason == lastDepthMeterState.reason
            and hideAction == lastDepthMeterState.hideAction then
            return
        end

        lastDepthMeterState.depth = roundedDepth
        lastDepthMeterState.band = band
        lastDepthMeterState.shore = isShore
        lastDepthMeterState.reason = reason
        lastDepthMeterState.canCast = canCast
        lastDepthMeterState.hideAction = hideAction

        SendNUIMessage({
            action = "depthMeter",
            show = (band ~= nil),
            depth = roundedDepth,
            band = band,
            label = band and DepthLabel(band) or nil,
            shore = isShore,
            shoreTitle = isShore and Lang("DEPTH_SHORE_TITLE") or nil,
            shoreNote = isShore and Lang("DEPTH_SHORE_NOTE") or nil,
            canCast = canCast or false,
            key = Config.Keys and Config.Keys.InteractKeyLabel or "E",
            reason = reason,
            hideAction = hideAction or false
        })
    end

    while true do
        local sleep = 500
        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)
        local inVehicle = (veh ~= 0)
        local isBusy = isFishing or isFighting
        local rodInHand = (Player.rodIsIn == "hand")

        local jobPedCfg = Config.StartJob and Config.StartJob.ped or {}
        local noFishRadius = jobPedCfg.noFishingRadius or 0.0
        local isNearJobPed = false

        if noFishRadius > 0 and jobPedCfg.coords then
            local pCoords = GetEntityCoords(ped)
            local diffX = pCoords.x - jobPedCfg.coords.x
            local diffY = pCoords.y - jobPedCfg.coords.y
            isNearJobPed = (diffX * diffX + diffY * diffY) <= (noFishRadius * noFishRadius)
        end

        local netIsActive = NetIsOut and NetIsOut() or false
        local campfireActive = AtCampfire and AtCampfire() or false
        local canFishAction = rodInHand and not isBusy and not isNearJobPed and not netIsActive and not campfireActive and not inVehicle

        if rodInHand then
            sleep = 0
            local now = GetGameTimer()
            if (now - lastProbeTime) >= 200 then
                lastProbeTime = now
                cachedWater = ProbeWater(ped, GetProbeMaxDistance())
                if Config.Debug and cachedWater then
                    DebugPrint(("water at %.1fm out, %.1fm below · depth %.1fm (%s)"):format(
                        cachedWater.distance,
                        GetEntityCoords(ped).z - cachedWater.height,
                        cachedWater.depth,
                        cachedWater.band
                    ))
                end
            end

            local maxDepthLimit = GetCachedDepthLimit()
            local isTooDeep = cachedWater and maxDepthLimit > 0 and cachedWater.depth > maxDepthLimit
            local blockedReason = nil

            if netIsActive then
                blockedReason = Lang("FISH_BLOCKED_NET")
            elseif isNearJobPed then
                blockedReason = Lang("FISH_BLOCKED_NPC")
            elseif isTooDeep then
                blockedReason = Lang("DEPTH_TOO_DEEP_FOR_YOU"):format(("%.1f"):format(maxDepthLimit))
            elseif not canFishAction and not isBusy then
                blockedReason = inVehicle and Lang("FISH_BLOCKED_VEHICLE") or Lang("FISH_BLOCKED")
            end

            local canCastFinal = canFishAction and not isTooDeep
            UpdateDepthMeter(cachedWater, canCastFinal, blockedReason, isBusy)

            if cachedWater and canCastFinal then
                if IsControlJustPressed(0, Config.Keys and Config.Keys.InteractKey or 38) then
                    StartFishing(cachedWater)
                end
            end
        else
            cachedWater = nil
            lastProbeTime = 0
            UpdateDepthMeter(nil, false, nil, false)
            sleep = 500
        end

        Wait(sleep)
    end
end)

AddEventHandler("onResourceStop", function(resourceName)
    if GetCurrentResourceName() ~= resourceName then
        return
    end
    StopDangling()
    DeleteFishingRod()
    CleanPlayerLine()
    ClearAllRemoteLines()
    isShowcaseActive = false
    RenderScriptCams(false, false, 0, true, true)
    SetEntityVisible(PlayerPedId(), true, false)
    SetNuiFocus(false, false)
end)
--WKLeak_PCOnWiTopMf : https://discord.gg/zqcBffbMZn
--WKLeak_6MOn$lTopLw : https://discord.gg/zqcBffbMZn
--WKLeak-87On#eTop@f : https://discord.gg/zqcBffbMZn
--WKLeaksgnOnVOTopjq : https://discord.gg/zqcBffbMZn
--WKLeak_#WOns$TopB5 : https://discord.gg/zqcBffbMZn
