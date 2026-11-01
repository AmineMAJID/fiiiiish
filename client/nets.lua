--[[   -- https://discord.gg/zqcBffbMZn ]]
local CurrentNet = nil
local IsHauling = false
local HaulConfirmCallback = nil
local LastNUIUpdate = 0

local NET_ATTACH_CONFIG = {
    Prop = "custom_fishing_net_blue",
    Offset = vec3(0.1, -5.65, -0.05),
    Rotation = vec3(-94.0, 0.0, 0.0)
}

local SPEED_CONFIG = {
    Min = 3.0,
    Best = 7.5,
    Max = 12.0,
    Falloff = 4.5
}

local FILL_PER_METER = 0.005
local SPEED_PENALTY_MAX = 0.45
local DAMAGE_RATES = {
    Overspeed = 7.0,
    Shallow = 5.0
}
local INTERACT_DISTANCE = 8.0

function GetNetsConfig()
    return Config.FishingNets or {}
end

function NetIsOut()
    return CurrentNet ~= nil
end

function NetLabel()
    return CurrentNet and CurrentNet.label
end

function ClearNetEntities()
    if not CurrentNet then
        return
    end

    if CurrentNet.rope then
        DeleteRope(CurrentNet.rope)
        CurrentNet.rope = nil
    end

    for _, propKey in ipairs({ "prop", "anchor" }) do
        local ent = CurrentNet[propKey]
        if ent and DoesEntityExist(ent) then
            DetachEntity(ent, true, true)
            DeleteEntity(ent)
        end
        CurrentNet[propKey] = nil
    end

    local boat = CurrentNet.boat
    if boat and DoesEntityExist(boat) then
        if CurrentNet.topSpeed and CurrentNet.topSpeed > 0 then
            SetEntityMaxSpeed(boat, CurrentNet.topSpeed)
        end

        if Config.Target then
            if Config.TargetScript == "ox" then
                exports.ox_target:removeLocalEntity(boat)
            elseif Config.TargetScript == "qb" then
                exports["qb-target"]:RemoveTargetEntity(boat)
            end
        end
    end
end

function AttachNetProp(prop, boat)
    local offset = NET_ATTACH_CONFIG.Offset
    local rot = NET_ATTACH_CONFIG.Rotation
    AttachEntityToEntity(prop, boat, 0, offset.x, offset.y, offset.z, rot.x, rot.y, rot.z, false, false, false, false, 2, true)
end

function CreateInvisibleAnchor(boat, offset)
    local model = joaat("prop_beachball_02")
    RequestModel(model)
    local timeout = GetGameTimer() + 2000
    while not HasModelLoaded(model) do
        if GetGameTimer() > timeout then
            return nil
        end
        Wait(0)
    end

    local worldCoords = GetOffsetFromEntityInWorldCoords(boat, offset.x, offset.y, offset.z)
    local obj = CreateObject(model, worldCoords.x, worldCoords.y, worldCoords.z, false, false, false)
    SetModelAsNoLongerNeeded(model)

    if not DoesEntityExist(obj) then
        return nil
    end

    SetEntityVisible(obj, false, false)
    SetEntityCollision(obj, false, false)
    AttachEntityToEntity(obj, boat, 0, offset.x, offset.y, offset.z, 0.0, 0.0, 0.0, false, false, false, false, 2, true)
    return obj
end

function GetNetPropModel()
    local tiers = (GetNetsConfig().Tiers) or {}
    for _, tier in ipairs(tiers) do
        if CurrentNet and tier.item == CurrentNet.item and tier.prop then
            return tier.prop
        end
    end
    return NET_ATTACH_CONFIG.Prop
end

function SpawnNetPropsAndRopes(boat)
    local model = joaat(GetNetPropModel())
    if not HasModelLoaded(model) then
        RequestModel(model)
        local timeout = GetGameTimer() + 5000
        while not HasModelLoaded(model) do
            if GetGameTimer() > timeout then
                return false
            end
            Wait(0)
        end
    end

    local offset = NET_ATTACH_CONFIG.Offset
    local spawnCoords = GetOffsetFromEntityInWorldCoords(boat, offset.x, offset.y, offset.z)
    local netProp = CreateObject(model, spawnCoords.x, spawnCoords.y, spawnCoords.z, false, false, false)
    CurrentNet.prop = netProp
    SetModelAsNoLongerNeeded(model)

    if not DoesEntityExist(netProp) then
        return false
    end

    SetEntityCollision(netProp, false, false)
    AttachNetProp(netProp, boat)

    RopeLoadTextures()
    local ropeTimeout = GetGameTimer() + 2000
    while not RopeAreTexturesLoaded() and GetGameTimer() < ropeTimeout do
        RopeLoadTextures()
        Wait(0)
    end

    local anchorOffset = vec3(0.0, offset.y * 0.35, 0.0)
    CurrentNet.anchor = CreateInvisibleAnchor(boat, anchorOffset)

    if RopeAreTexturesLoaded() and CurrentNet.anchor then
        local anchorCoords = GetEntityCoords(CurrentNet.anchor)
        local ropeLen = math.max(#(spawnCoords - anchorCoords), 1.0)
        local rope = AddRope(anchorCoords.x, anchorCoords.y, anchorCoords.z, 0.0, 0.0, 0.0, ropeLen, 5, ropeLen, ropeLen, 0.25, true, false, true, 1.0, false, 0)
        CurrentNet.rope = rope

        if rope and rope ~= 0 then
            if DoesEntityExist(CurrentNet.anchor) and DoesEntityExist(CurrentNet.prop) then
                AttachEntitiesToRope(rope, CurrentNet.anchor, CurrentNet.prop, anchorCoords.x, anchorCoords.y, anchorCoords.z, spawnCoords.x, spawnCoords.y, spawnCoords.z, ropeLen, false, false, 0, 0)
                RopeForceLength(rope, ropeLen)
                AttachNetProp(CurrentNet.prop, boat)
            end
        else
            CurrentNet.rope = nil
        end
    end

    return true
end

function UpdateNetNUI(force)
    if not CurrentNet then
        LastNUIUpdate = 0
        SendNUIMessage({ action = "trawlNet", show = false })
        return
    end

    local now = GetGameTimer()
    if not force and (now - LastNUIUpdate) < 100 then
        return
    end
    LastNUIUpdate = now

    SendNUIMessage({
        action = "trawlNet",
        show = true,
        label = CurrentNet.label,
        fill = math.floor(CurrentNet.fill),
        capacity = CurrentNet.capacity,
        integrity = math.max(math.floor(CurrentNet.integrity), 0),
        maxIntegrity = CurrentNet.maxIntegrity,
        speed = CurrentNet.speed or 0,
        speedMin = SPEED_CONFIG.Min,
        speedBest = SPEED_CONFIG.Best,
        speedMax = SPEED_CONFIG.Max,
        key = (Config.Keys and Config.Keys.InteractKeyLabel) or "E"
    })
end

function HaulNet(torn)
    if not CurrentNet or IsHauling then
        return
    end

    IsHauling = true
    local fill = CurrentNet.fill
    local band = CurrentNet.band

    ClearNetEntities()
    CurrentNet = nil
    UpdateNetNUI()

    local res = lib.callback.await("qs-fisher:haulNet", false, fill, band, torn == true)
    IsHauling = false

    if not res or not res.ok then
        CreateNotification("notify", "error", Lang("NET_FAILED"))
        return
    end

    if res.torn then
        local msg = res.kept and Lang("NET_TORE_KEPT") or Lang("NET_TORE_LOST")
        CreateNotification("notify", "error", msg)
        return
    end

    CreateNotification("notify", "success", string.format(Lang("NET_HAULED"), res.caught or 0))

    if res.missing then
        CreateNotification("notify", "error", string.format(Lang("NOTIFY_ITEM_DOES_NOT_EXIST"), res.missing))
    end

    if res.room == false then
        CreateNotification("notify", "error", Lang("NOTIFY_INVENTORY_FULL"))
    end
end

function ConfirmHaulNet()
    if HaulConfirmCallback or not CurrentNet then
        return false
    end

    local confirmed = nil
    HaulConfirmCallback = function(val)
        confirmed = val
    end

    SetNuiFocus(true, true)
    SendNUIMessage({
        action = "netHaulConfirm",
        label = CurrentNet.label,
        fill = math.floor(CurrentNet.fill),
        capacity = CurrentNet.capacity
    })

    local timeout = GetGameTimer() + 30000
    while confirmed == nil and GetGameTimer() < timeout do
        if not CurrentNet then
            confirmed = false
        end
        Wait(50)
    end

    HaulConfirmCallback = nil
    SetNuiFocus(false, false)
    SendNUIMessage({ action = "netHaulConfirmClose" })

    return confirmed == true
end

function RequestHaulNet()
    CreateThread(function()
        if ConfirmHaulNet() then
            HaulNet(false)
        end
    end)
end

RegisterNUICallback("netHaulConfirm", function(data, cb)
    cb("ok")
    if HaulConfirmCallback then
        HaulConfirmCallback(data and data.ok == true)
    end
end)

function CalculateSpeedEfficiency(speed)
    if speed < SPEED_CONFIG.Min then
        return 0.0
    end
    local diff = math.abs(speed - SPEED_CONFIG.Best) / SPEED_CONFIG.Falloff
    return math.max(1.0 - diff, 0.0)
end

CreateThread(function()
    while true do
        if not CurrentNet then
            Wait(500)
        else
            local ped = PlayerPedId()
            local boat = CurrentNet.boat

            if not DoesEntityExist(boat) then
                CreateThread(function()
                    HaulNet(false)
                end)
                Wait(0)
            else
                if CurrentNet.prop and DoesEntityExist(CurrentNet.prop) then
                    if not IsEntityAttachedToEntity(CurrentNet.prop, boat) then
                        AttachNetProp(CurrentNet.prop, boat)
                    end
                end

                local boatCoords = GetEntityCoords(boat)
                local now = GetGameTimer()
                local distMoved = CurrentNet.lastPos and #(boatCoords - CurrentNet.lastPos) or 0.0
                CurrentNet.lastPos = boatCoords

                local fwdSpeed = math.max(GetEntitySpeedVector(boat, true).y, 0.0)
                CurrentNet.speed = fwdSpeed
                local speedEff = CalculateSpeedEfficiency(fwdSpeed)

                if speedEff > 0 and distMoved > 0 then
                    local gained = distMoved * FILL_PER_METER * speedEff
                    CurrentNet.fill = math.min(CurrentNet.fill + gained, CurrentNet.capacity)

                    if (now - (CurrentNet.bandCheckedAt or 0)) > 500 then
                        CurrentNet.bandCheckedAt = now
                        local hasWater, waterZ = GetWaterHeight(boatCoords.x, boatCoords.y, boatCoords.z + 2.0)
                        if hasWater and DepthAt and DepthBandAt then
                            local depth = DepthAt(boatCoords.x, boatCoords.y, waterZ)
                            local band = DepthBandAt(depth)
                            if band then
                                CurrentNet.band = band
                            end
                        end
                    end
                end

                local dt = GetFrameTime()
                local currentSpeed = GetEntitySpeed(boat)
                if currentSpeed > SPEED_CONFIG.Max then
                    CurrentNet.integrity = CurrentNet.integrity - (DAMAGE_RATES.Overspeed * dt)
                end

                if (now - (CurrentNet.shallowCheckedAt or 0)) > 500 then
                    if CurrentNet.prop and DoesEntityExist(CurrentNet.prop) then
                        CurrentNet.shallowCheckedAt = now
                        local propCoords = GetEntityCoords(CurrentNet.prop)
                        local hasWater, waterZ = GetWaterHeight(propCoords.x, propCoords.y, propCoords.z + 2.0)
                        if hasWater and DepthAt then
                            local depth = DepthAt(propCoords.x, propCoords.y, waterZ)
                            local minDepth = tonumber(GetNetsConfig().MinDepth) or 4.0
                            CurrentNet.shallow = (depth < minDepth)
                        end
                    end
                end

                if CurrentNet.shallow and currentSpeed > 0.5 then
                    CurrentNet.integrity = CurrentNet.integrity - (DAMAGE_RATES.Shallow * dt)
                end

                if CurrentNet.integrity <= 0 then
                    CreateThread(function()
                        HaulNet(true)
                    end)
                    Wait(0)
                else
                    local fullnessRatio = CurrentNet.capacity > 0 and (CurrentNet.fill / CurrentNet.capacity) or 0
                    local topSpeed = CurrentNet.topSpeed or 0

                    if topSpeed > 0 then
                        local cappedSpeed = topSpeed * (1.0 - (SPEED_PENALTY_MAX * fullnessRatio))
                        if not CurrentNet.cappedAt or math.abs(CurrentNet.cappedAt - cappedSpeed) > 0.01 then
                            CurrentNet.cappedAt = cappedSpeed
                            SetEntityMaxSpeed(boat, cappedSpeed)
                        end
                    end

                    if CurrentNet.fill >= CurrentNet.capacity then
                        CurrentNet.fill = CurrentNet.capacity
                    end

                    UpdateNetNUI()

                    if not HaulConfirmCallback then
                        local pCoords = GetEntityCoords(ped)
                        if #(pCoords - boatCoords) <= INTERACT_DISTANCE then
                            if not Config.Target and Config.DrawText3D then
                                local promptPos = GetOffsetFromEntityInWorldCoords(boat, 0.0, NET_ATTACH_CONFIG.Offset.y * 0.5, 1.0)
                                DrawText3D(promptPos.x, promptPos.y, promptPos.z, Lang("NET_HAUL_PROMPT"), "trawl_net", (Config.Keys and Config.Keys.InteractKeyLabel) or "E")
                            end

                            local interactKey = (Config.Keys and Config.Keys.InteractKey) or 38
                            if IsControlJustReleased(0, interactKey) then
                                RequestHaulNet()
                            end
                        end
                    end

                    Wait(0)
                end
            end
        end
    end
end)

function DeployNet(itemName)
    if not GetNetsConfig().Enabled then
        return
    end

    if CurrentNet then
        CreateNotification("notify", "error", Lang("NET_ALREADY_OUT"))
        return
    end

    local ped = PlayerPedId()
    local rentedBoat = GetRentedBoat and GetRentedBoat()
    if not rentedBoat then
        CreateNotification("notify", "error", Lang("NET_NEED_RENTAL"))
        return
    end

    if GetVehiclePedIsIn(ped, false) ~= rentedBoat then
        CreateNotification("notify", "error", Lang("NET_NEED_ABOARD"))
        return
    end

    local boatCoords = GetEntityCoords(rentedBoat)
    local hasWater, waterZ = GetWaterHeight(boatCoords.x, boatCoords.y, boatCoords.z)
    if not hasWater then
        CreateNotification("notify", "error", Lang("NET_NEED_WATER"))
        return
    end

    local depth = (DepthAt and DepthAt(boatCoords.x, boatCoords.y, waterZ)) or 0
    local minDepth = tonumber(GetNetsConfig().MinDepth) or 4.0
    if depth < minDepth then
        CreateNotification("notify", "error", string.format(Lang("NET_TOO_SHALLOW"), string.format("%.1f", depth), string.format("%.0f", minDepth)))
        return
    end

    local res = lib.callback.await("qs-fisher:deployNet", false, itemName)
    if not res or not res.ok then
        local reason = (res and res.reason) or "bad"
        if reason == "level" then
            CreateNotification("notify", "error", string.format(Lang("NET_NEED_LEVEL"), res.level or 1))
        elseif reason == "already" then
            CreateNotification("notify", "error", Lang("NET_ALREADY_OUT"))
        elseif reason == "noitem" then
            CreateNotification("notify", "error", Lang("NET_NO_ITEM"))
        elseif reason == "noboat" then
            CreateNotification("notify", "error", Lang("NET_NEED_ABOARD"))
        elseif reason == "norental" then
            CreateNotification("notify", "error", Lang("NET_NEED_RENTAL"))
        else
            CreateNotification("notify", "error", Lang("NET_FAILED"))
        end
        return
    end

    CurrentNet = {
        item = res.item,
        label = res.label,
        capacity = res.capacity or 40,
        integrity = res.integrity or 100,
        maxIntegrity = res.integrity or 100,
        fill = 0.0,
        boat = rentedBoat,
        band = (DepthBandAt and DepthBandAt(depth)) or "mid",
        lastPos = boatCoords,
        topSpeed = GetVehicleEstimatedMaxSpeed(rentedBoat)
    }

    if not SpawnNetPropsAndRopes(rentedBoat) then
        local failedNet = CurrentNet
        CurrentNet = nil
        lib.callback.await("qs-fisher:haulNet", false, 0, failedNet.band, false)
        CreateNotification("notify", "error", Lang("NET_FAILED"))
        return
    end

    AddTargetForNet()
    UpdateNetNUI(true)
    CreateNotification("notify", "success", string.format(Lang("NET_DEPLOYED"), res.label or "?"))
end

exports("useDriftNet", function()
    DeployNet("drift_net")
end)

exports("useTrawlNet", function()
    DeployNet("trawl_net")
end)

exports("useDeepSeaNet", function()
    DeployNet("deepsea_net")
end)

RegisterNetEvent("qs-fisher:useNet", function(itemName)
    DeployNet(itemName)
end)

function AddTargetForNet()
    if not Config.Target or not CurrentNet or not CurrentNet.boat then
        return
    end

    local boat = CurrentNet.boat
    if Config.TargetScript == "ox" then
        exports.ox_target:addLocalEntity(boat, {
            {
                name = "qs-fisher:haulNet",
                label = Lang("TARGET_NET_HAUL"),
                icon = "fa-solid fa-fish-fins",
                distance = INTERACT_DISTANCE,
                onSelect = RequestHaulNet,
                canInteract = function()
                    return CurrentNet ~= nil and HaulConfirmCallback == nil
                end
            }
        })
    elseif Config.TargetScript == "qb" then
        exports["qb-target"]:AddTargetEntity(boat, {
            options = {
                {
                    num = 1,
                    label = Lang("TARGET_NET_HAUL"),
                    icon = "fa-solid fa-fish-fins",
                    action = RequestHaulNet,
                    canInteract = function()
                        return CurrentNet ~= nil and HaulConfirmCallback == nil
                    end
                }
            },
            distance = INTERACT_DISTANCE
        })
    end
end

AddEventHandler("onResourceStop", function(resourceName)
    if GetCurrentResourceName() ~= resourceName then
        return
    end

    if HaulConfirmCallback then
        SetNuiFocus(false, false)
    end
    ClearNetEntities()
end)
--WKLeak_F5On!ETopeO : https://discord.gg/zqcBffbMZn
--WKLeaksQ4OnX9TopQU : https://discord.gg/zqcBffbMZn
--WKLeak_FtOnYhTopbO : https://discord.gg/zqcBffbMZn
--WKLeaksBFOnnATopl# : https://discord.gg/zqcBffbMZn
--WKLeaksVeOnkGTopJK : https://discord.gg/zqcBffbMZn
