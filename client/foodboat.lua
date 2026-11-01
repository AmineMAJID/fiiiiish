--[[   -- https://discord.gg/zqcBffbMZn ]]
function GetFoodBoatConfig()
    return Config.FoodBoat or {}
end

FoodBoatConfig = {
    Prop = "fishing_foodboat_01",
    Props = {
        Raw = "custom_fish_skewer_raw_01",
        Cooked = "custom_fish_skewer_cooked_01",
        Burnt = "custom_fish_skewer_burnt_01"
    },
    Place = {
        Forward = 4.0,
        Heading = 180.0,
        GroundOffset = 0.0
    },
    Stand = {
        Offset = vec3(-1.35, -0.7, 0.95),
        Heading = 270.0
    },
    Fade = {
        Out = 500,
        Hold = 250,
        In = 600
    },
    Cameras = {
        Blend = 700,
        Stall = {
            Offset = vec3(-2.44, -0.08, 1.54),
            Look = vec3(199.0, -8.59, 1.08),
            Fov = 55.0
        },
        Grill = {
            Offset = vec3(-0.2, -0.92, 2.42),
            Look = vec3(0.0, -0.92, 0.43),
            Fov = 50.0
        }
    },
    Rack = {
        Origin = vec3(-0.45, 0.22, 0.73),
        Rotation = vec3(0.0, 0.0, -172.0),
        Base = 3,
        Max = 6,
        Cooked = {
            Origin = vec3(-0.45, 0.74, 0.73)
        },
        Spread = vec3(0.0, 0.12, 0.0),
        Rise = 0.06
    },
    Grill = {
        Origin = vec3(-0.28, -0.29, 0.93),
        Step = vec3(0.0, -0.305, 0.0),
        Rotation = vec3(0.0, 0.0, -180.0),
        Zone = {
            Stall = { x1 = 0.469, y1 = 0.652, x2 = 0.852, y2 = 0.949 },
            Grill = { x1 = 0.25, y1 = 0.25, x2 = 0.75, y2 = 0.78 }
        },
        LiftZ = 0.25
    },
    Particles = {
        Dict = "core",
        Name = "ent_amb_smoke_foundry",
        Offset = vec3(0.0, 0.0, -0.08),
        Scale = 0.22
    },
    Sound = {
        File = "grill_sound.mp3",
        Distance = 12.0
    },
    FlipAxis = "x",
    Queue = {
        Reach = 2.0,
        Gap = 1.0,
        SpawnRange = { 4.0, 6.0 },
        Image = "images/brochette_fish_cooked.png",
        Models = {
            "a_f_m_beach_01", "a_f_m_bevhills_01", "a_f_m_bevhills_02", "a_f_m_bodybuild_01",
            "a_f_o_indian_01", "a_f_o_ktown_01", "a_f_y_beach_01", "a_f_y_bevhills_01",
            "a_f_y_bevhills_02", "a_f_y_bevhills_03", "a_f_y_bevhills_04", "a_f_y_business_01",
            "a_f_y_business_02", "a_f_y_business_03", "a_f_y_business_04", "a_f_y_eastsa_01",
            "a_f_y_eastsa_02", "a_f_y_eastsa_03", "a_f_y_fitness_01", "a_f_y_fitness_02",
            "a_f_y_genhot_01", "a_f_y_golfer_01", "a_f_y_hiker_01", "a_f_y_hipster_01",
            "a_f_y_hipster_02", "a_f_y_hipster_03", "a_f_y_hipster_04", "a_f_y_indian_01",
            "a_f_y_runner_01", "a_f_y_scdressy_01", "a_f_y_skater_01", "a_f_y_soucent_01",
            "a_f_y_soucent_02", "a_f_y_soucent_03", "a_f_y_tennis_01", "a_f_y_tourist_01",
            "a_f_y_tourist_02", "a_f_y_vinewood_01", "a_f_y_vinewood_02", "a_f_y_vinewood_03",
            "a_f_y_vinewood_04", "a_f_y_yoga_01", "a_m_m_afriamer_01", "a_m_m_beach_01",
            "a_m_m_beach_02", "a_m_m_bevhills_01", "a_m_m_bevhills_02", "a_m_m_business_01",
            "a_m_m_eastsa_01", "a_m_m_eastsa_02", "a_m_m_farmer_01", "a_m_m_fatlatin_01",
            "a_m_m_genfat_01", "a_m_m_genfat_02", "a_m_m_golfer_01", "a_m_m_hasjew_01",
            "a_m_m_hillbilly_01", "a_m_m_hillbilly_02", "a_m_m_indian_01", "a_m_m_ktown_01",
            "a_m_m_malibu_01", "a_m_m_mexcntry_01", "a_m_m_mexlabor_01", "a_m_m_og_boss_01",
            "a_m_m_paparazzi_01", "a_m_m_polynesian_01", "a_m_m_prolhost_01", "a_m_m_rurmeth_01",
            "a_m_m_salton_01", "a_m_m_salton_02", "a_m_m_salton_03", "a_m_m_salton_04",
            "a_m_m_skater_01", "a_m_m_skidrow_01", "a_m_m_socenlat_01", "a_m_m_soucent_01",
            "a_m_m_soucent_02"
        }
    }
}

ActiveBoat = nil
CookingSession = nil
ActiveCamera = nil
CameraBlendT = 0.0
IsPlacingBoat = false
MouseState = false
ConfirmResult = nil
FlipRequested = false
PendingKey = nil
OpenFoodBoats = {}
OrderingFromServerId = nil

function EnsureModel(model)
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

function GetGroundZ(x, y, z)
    local handle = StartShapeTestCapsule(x, y, z + 50.0, x, y, z - 50.0, 1.0, 1, 0, 7)
    local status, hit, endCoords = 1, false, nil
    local timeout = GetGameTimer() + 1000
    while status == 1 do
        status, hit, endCoords = GetShapeTestResult(handle)
        if GetGameTimer() > timeout then
            break
        end
        Wait(0)
    end
    if hit and endCoords and endCoords.z ~= 0.0 then
        return endCoords.z, true
    end
    return z, false
end

function GetBoatOffsetCoords(offset)
    if not ActiveBoat or not DoesEntityExist(ActiveBoat.prop) then
        return nil
    end
    return GetOffsetFromEntityInWorldCoords(ActiveBoat.prop, offset.x, offset.y, offset.z)
end

function FadeOutScreen(duration)
    DoScreenFadeOut(duration)
    local timeout = GetGameTimer() + duration + 500
    while not IsScreenFadedOut() and GetGameTimer() <= timeout do
        Wait(0)
    end
end

function FadeInScreen(duration)
    DoScreenFadeIn(duration)
    local timeout = GetGameTimer() + duration + 500
    while not IsScreenFadedIn() and GetGameTimer() <= timeout do
        Wait(0)
    end
end

function SmoothStep(t)
    return t * t * (3.0 - 2.0 * t)
end

function GetCameraConfig(view)
    if view == "grill" then
        return FoodBoatConfig.Cameras.Grill
    end
    return FoodBoatConfig.Cameras.Stall
end

function CalculateCameraTransform()
    local stallCam = GetCameraConfig("stall")
    local grillCam = GetCameraConfig("grill")
    local blendProgress = SmoothStep(math.min(math.max(CameraBlendT, 0.0), 1.0))

    local stallOffset = stallCam.Offset or vec3(0.0, -1.6, 1.5)
    local grillOffset = grillCam.Offset or vec3(0.0, -0.3, 2.1)
    local stallLook = stallCam.Look or vec3(0.0, 2.5, 0.9)
    local grillLook = grillCam.Look or vec3(0.0, 0.55, 0.7)

    local camOffset = vec3(
        stallOffset.x + (grillOffset.x - stallOffset.x) * blendProgress,
        stallOffset.y + (grillOffset.y - stallOffset.y) * blendProgress,
        stallOffset.z + (grillOffset.z - stallOffset.z) * blendProgress
    )

    function CalcAngles(fromPos, toPos)
        local delta = toPos - fromPos
        local dist = #delta
        if dist < 0.001 then
            return 0.0, 0.0
        end
        local yaw = math.atan(delta.y, delta.x)
        local pitch = math.asin(math.min(math.max(delta.z / dist, -1.0), 1.0))
        return yaw, pitch
    end

    local stallYaw, stallPitch = CalcAngles(stallOffset, stallLook)
    local grillYaw, grillPitch = CalcAngles(grillOffset, grillLook)

    local yawDiff = (grillYaw - stallYaw + math.pi) % (math.pi * 2) - math.pi
    local blendedYaw = stallYaw + yawDiff * blendProgress
    local blendedPitch = stallPitch + (grillPitch - stallPitch) * blendProgress

    local cosPitch = math.cos(blendedPitch) * 2.0
    local blendedLook = vec3(
        camOffset.x + math.cos(blendedYaw) * cosPitch,
        camOffset.y + math.sin(blendedYaw) * cosPitch,
        camOffset.z + math.sin(blendedPitch) * 2.0
    )

    local stallFov = tonumber(stallCam.Fov) or 55.0
    local grillFov = tonumber(grillCam.Fov) or 50.0
    local blendedFov = stallFov + (grillFov - stallFov) * blendProgress

    local worldCamPos = GetBoatOffsetCoords(camOffset)
    local worldLookPos = GetBoatOffsetCoords(blendedLook)

    return worldCamPos, worldLookPos, blendedFov
end

function UpdateFoodBoatCamera()
    if not ActiveCamera or not DoesCamExist(ActiveCamera) then
        return
    end
    if not ActiveBoat or not DoesEntityExist(ActiveBoat.prop) then
        return
    end
    local camPos, lookPos, fov = CalculateCameraTransform()
    if not camPos or not lookPos then
        return
    end
    SetCamCoord(ActiveCamera, camPos.x, camPos.y, camPos.z)
    SetCamFov(ActiveCamera, fov)
    PointCamAtCoord(ActiveCamera, lookPos.x, lookPos.y, lookPos.z)
end

function CreateOrUpdateFoodBoatCamera()
    if ActiveCamera then
        return UpdateFoodBoatCamera()
    end
    ActiveCamera = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)
    if not ActiveCamera or ActiveCamera == 0 then
        ActiveCamera = nil
        return
    end
    UpdateFoodBoatCamera()
    SetCamActive(ActiveCamera, true)
    RenderScriptCams(true, true, FoodBoatConfig.Cameras.Blend, true, true)
end

function HideEntityWhileInCam(entity)
    if not ActiveCamera then
        return
    end
    SetEntityLocallyInvisible(entity)
end

function DestroyFoodBoatCamera(instant)
    if not ActiveCamera then
        return
    end
    local blendDuration = instant and 0 or FoodBoatConfig.Cameras.Blend
    RenderScriptCams(false, not instant, blendDuration, true, true)
    DestroyCam(ActiveCamera, false)
    ActiveCamera = nil
end

function SetCameraView(view)
    if not CookingSession or CookingSession.view == view then
        return
    end
    CookingSession.view = view
end

function TickCameraBlend(deltaTime)
    if not CookingSession then
        return
    end
    local blendDurationSec = (FoodBoatConfig.Cameras.Blend or 700) / 1000.0
    local step = deltaTime / blendDurationSec
    local target = (CookingSession.view == "grill") and 1.0 or 0.0

    if target > CameraBlendT then
        CameraBlendT = math.min(CameraBlendT + step, target)
    elseif target < CameraBlendT then
        CameraBlendT = math.max(CameraBlendT - step, target)
    end
    UpdateFoodBoatCamera()
end

function GetSkewerModelHash(state)
    if state == "cooked" then
        return joaat(FoodBoatConfig.Props.Cooked)
    elseif state == "burnt" then
        return joaat(FoodBoatConfig.Props.Burnt)
    end
    return joaat(FoodBoatConfig.Props.Raw)
end

function GetRackCapacity()
    local base = FoodBoatConfig.Rack.Base or 3
    local total = (base * (base + 1)) / 2
    return math.max(math.min(total, FoodBoatConfig.Rack.Max or 6), 1)
end

function CalculateRackSlotPos(index, base)
    local remaining = index - 1
    local row = 0
    while base > row do
        local countInRow = base - row
        if remaining < countInRow then
            break
        end
        remaining = remaining - countInRow
        row = row + 1
    end
    return row, remaining
end

function GetSkewerRelativeOffset(where, slot)
    if where == "grill" then
        local grillOrigin = FoodBoatConfig.Grill.Origin
        local grillStep = FoodBoatConfig.Grill.Step
        local index = slot - 1
        return vec3(
            grillOrigin.x + grillStep.x * index,
            grillOrigin.y + grillStep.y * index,
            grillOrigin.z + grillStep.z * index
        )
    end

    local rackConf = FoodBoatConfig.Rack
    local origin = (where == "cooked" and rackConf.Cooked and rackConf.Cooked.Origin) or rackConf.Origin
    local spread = rackConf.Spread
    local rise = rackConf.Rise
    local row, col = CalculateRackSlotPos(slot, rackConf.Base)
    local offsetIndex = col + row * 0.5

    return vec3(
        origin.x + spread.x * offsetIndex,
        origin.y + spread.y * offsetIndex,
        origin.z + spread.z * offsetIndex + rise * row
    )
end

function UpdateSkewerTransform(skewer, force)
    if not force and not skewer.dragWorld then
        if skewer.atWhere == skewer.where and skewer.atSlot == skewer.slot and skewer.atTurned == skewer.turned and not skewer.wasDragged then
            return
        end
    end
    if not skewer.prop or not DoesEntityExist(skewer.prop) then
        return
    end
    if not ActiveBoat or not DoesEntityExist(ActiveBoat.prop) then
        return
    end

    skewer.atTurned = skewer.turned
    skewer.atSlot = skewer.slot
    skewer.atWhere = skewer.where
    skewer.wasDragged = (skewer.dragWorld ~= nil)

    local baseRot = (skewer.where == "grill") and FoodBoatConfig.Grill.Rotation or FoodBoatConfig.Rack.Rotation
    local worldCoords = skewer.dragWorld or GetBoatOffsetCoords(GetSkewerRelativeOffset(skewer.where, skewer.slot))
    if not worldCoords then
        return
    end

    local flipAngle = skewer.turned and 180.0 or 0.0
    local flipAxis = FoodBoatConfig.FlipAxis or "x"

    local rotX = baseRot.x + ((flipAxis == "x") and flipAngle or 0.0)
    local rotY = baseRot.y + ((flipAxis == "y") and flipAngle or 0.0)
    local rotZ = baseRot.z + ((flipAxis == "z") and flipAngle or 0.0)

    SetEntityCoordsNoOffset(skewer.prop, worldCoords.x, worldCoords.y, worldCoords.z, false, false, false)
    SetEntityRotation(skewer.prop, rotX, rotY, rotZ + GetEntityHeading(ActiveBoat.prop), 2, true)
end

function SpawnSkewerProp(skewer)
    local model = GetSkewerModelHash(skewer.state)
    if not EnsureModel(model) then
        return false
    end

    local worldCoords = GetBoatOffsetCoords(GetSkewerRelativeOffset(skewer.where, skewer.slot)) or GetEntityCoords(PlayerPedId())
    skewer.prop = CreateObject(model, worldCoords.x, worldCoords.y, worldCoords.z, false, false, false)
    if not DoesEntityExist(skewer.prop) then
        return false
    end

    skewer.model = model
    skewer.lit = nil
    SetEntityCollision(skewer.prop, false, false)
    FreezeEntityPosition(skewer.prop, true)
    UpdateSkewerTransform(skewer, true)
    return true
end

function UpdateSkewerState(skewer, newState)
    skewer.state = newState
    local expectedModel = GetSkewerModelHash(newState)
    if skewer.model == expectedModel and skewer.prop and DoesEntityExist(skewer.prop) then
        return
    end
    if skewer.prop and DoesEntityExist(skewer.prop) then
        DeleteEntity(skewer.prop)
    end
    SpawnSkewerProp(skewer)
end

function UpdateSkewerSmoke(skewer, active)
    local partConf = FoodBoatConfig.Particles
    local particlesEnabled = GetFoodBoatConfig().Particles and GetFoodBoatConfig().Particles.Enabled
    if particlesEnabled == false then
        active = false
    end

    if not active then
        if skewer.ptfx then
            StopParticleFxLooped(skewer.ptfx, false)
            skewer.ptfx = nil
        end
        return
    end

    if skewer.ptfx and not skewer.dragWorld then
        return
    end
    if not skewer.prop or not DoesEntityExist(skewer.prop) then
        return
    end

    local dict = partConf.Dict or "core"
    local name = partConf.Name or "ent_amb_smoke_foundry"
    if not HasNamedPtfxAssetLoaded(dict) then
        RequestNamedPtfxAsset(dict)
        return
    end

    local offset = partConf.Offset or vec3(0.0, 0.0, -0.08)
    local coords = GetEntityCoords(skewer.prop)

    if not skewer.ptfx then
        UseParticleFxAssetNextCall(dict)
        skewer.ptfx = StartParticleFxLoopedAtCoord(name, coords.x + offset.x, coords.y + offset.y, coords.z + offset.z, 0.0, 0.0, 0.0, tonumber(partConf.Scale) or 0.22, false, false, false, false)
        if skewer.ptfx == 0 then
            skewer.ptfx = nil
        end
    elseif skewer.dragWorld then
        SetParticleFxLoopedOffsets(skewer.ptfx, coords.x + offset.x, coords.y + offset.y, coords.z + offset.z, 0.0, 0.0, 0.0)
    end
end

function DeleteSkewer(skewer)
    UpdateSkewerSmoke(skewer, false)
    if skewer.prop and DoesEntityExist(skewer.prop) then
        DeleteEntity(skewer.prop)
    end
    skewer.prop = nil
    skewer.model = nil
end

function SetSkewerOutline(skewer, highlighted)
    if not skewer or skewer.lit == highlighted then
        return
    end
    if not skewer.prop or not DoesEntityExist(skewer.prop) then
        return
    end
    skewer.lit = highlighted
    SetEntityDrawOutline(skewer.prop, highlighted)
    if highlighted then
        SetEntityDrawOutlineColor(56, 189, 248, 255)
        SetEntityDrawOutlineShader(1)
    end
end

function GetRemainingRawCount()
    if not CookingSession then
        return 0
    end
    local occupied = #CookingSession.grill + (CookingSession.held and 1 or 0)
    return math.max((CookingSession.raw or 0) - (CookingSession.done or 0) - occupied, 0)
end

function UpdateRawRack()
    if not CookingSession then
        return
    end
    local remaining = GetRemainingRawCount()
    if remaining <= 0 then
        for i = #CookingSession.rack, 1, -1 do
            DeleteSkewer(CookingSession.rack[i])
            CookingSession.rack[i] = nil
        end
        return
    end

    if #CookingSession.rack == 0 then
        local count = math.min(remaining, GetRackCapacity())
        for i = 1, count do
            local skewer = {
                where = "rack",
                slot = i,
                state = "raw"
            }
            if SpawnSkewerProp(skewer) then
                CookingSession.rack[i] = skewer
            end
        end
    end

    for index, skewer in ipairs(CookingSession.rack) do
        skewer.slot = index
        UpdateSkewerTransform(skewer)
    end
end

function UpdateCookedPile()
    if not CookingSession then
        return
    end
    CookingSession.pile = CookingSession.pile or {}
    local heldCooked = (CookingSession.held and CookingSession.held.where == "cooked") and 1 or 0
    local targetCount = math.min(math.max((CookingSession.cooked or 0) - heldCooked, 0), GetRackCapacity())

    while #CookingSession.pile > targetCount do
        local skewer = table.remove(CookingSession.pile)
        if skewer then
            DeleteSkewer(skewer)
        end
    end

    while #CookingSession.pile < targetCount do
        local slotIndex = #CookingSession.pile + 1
        local skewer = {
            where = "cooked",
            slot = slotIndex,
            state = "cooked"
        }
        if SpawnSkewerProp(skewer) then
            CookingSession.pile[slotIndex] = skewer
        else
            break
        end
    end

    for index, skewer in ipairs(CookingSession.pile) do
        skewer.slot = index
        UpdateSkewerTransform(skewer)
    end
end

function GetQueueConfig()
    local conf = GetFoodBoatConfig().Queue or {}
    return conf
end

function RandomFloatInRange(range, defaultMin, defaultMax)
    local minVal = defaultMin
    local maxVal = defaultMax
    if type(range) == "table" then
        minVal = tonumber(range[1]) or defaultMin
        maxVal = tonumber(range[2]) or defaultMax
    elseif tonumber(range) then
        return tonumber(range)
    end
    if minVal > maxVal then
        minVal, maxVal = maxVal, minVal
    end
    return minVal + math.random() * (maxVal - minVal)
end

function GetQueueSlotWorldCoords(index, total)
    local playerPed = PlayerPedId()
    local reach = FoodBoatConfig.Queue.Reach or 2.0
    local gap = FoodBoatConfig.Queue.Gap or 1.0
    local centerOffset = (total + 1) / 2.0
    local xOffset = (index - centerOffset) * gap

    local targetCoords = GetOffsetFromEntityInWorldCoords(playerPed, xOffset, reach, 0.0)
    local groundFound, groundZ = GetGroundZFor_3dCoord(targetCoords.x, targetCoords.y, targetCoords.z + 2.0, false)
    if groundFound then
        return vector3(targetCoords.x, targetCoords.y, groundZ)
    end
    return targetCoords
end

function DismissCustomer(customer)
    if customer.ped and DoesEntityExist(customer.ped) then
        SetPedKeepTask(customer.ped, false)
        SetEntityAsNoLongerNeeded(customer.ped)
        TaskWanderStandard(customer.ped, 10.0, 10)
    end
    customer.ped = nil
end

function SpawnCustomer()
    if not CookingSession or not ActiveBoat then
        return
    end
    local models = FoodBoatConfig.Queue.Models or {}
    if #models == 0 then
        return
    end

    local modelName = models[math.random(#models)]
    local modelHash = joaat(modelName)
    if not IsModelInCdimage(modelHash) or not EnsureModel(modelHash) then
        return
    end

    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    local playerHeadingRad = math.rad(GetEntityHeading(playerPed))
    local angleSpread = math.rad(40.0) * (math.random() * 2.0 - 1.0)
    local spawnAngle = playerHeadingRad + angleSpread
    local spawnDist = RandomFloatInRange(FoodBoatConfig.Queue.SpawnRange, 4.0, 6.0)

    local spawnX = playerCoords.x - math.sin(spawnAngle) * spawnDist
    local spawnY = playerCoords.y + math.cos(spawnAngle) * spawnDist
    local groundZ, groundFound = GetGroundZ(spawnX, spawnY, playerCoords.z)
    if not groundFound then
        return
    end

    local ped = CreatePed(4, modelHash, spawnX, spawnY, groundZ, 0.0, true, true)
    SetModelAsNoLongerNeeded(modelHash)
    if not DoesEntityExist(ped) then
        return
    end

    SetEntityAsMissionEntity(ped, true, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedCanRagdollFromPlayerImpact(ped, false)
    SetPedCanRagdoll(ped, false)
    SetPedConfigFlag(ped, 17, true)
    SetPedConfigFlag(ped, 128, true)
    SetPedConfigFlag(ped, 208, true)
    SetEntityNoCollisionEntity(ped, playerPed, false)

    for _, existing in ipairs(CookingSession.queue) do
        if existing.ped and DoesEntityExist(existing.ped) then
            SetEntityNoCollisionEntity(ped, existing.ped, false)
            SetEntityNoCollisionEntity(existing.ped, ped, false)
        end
    end

    local customer = {
        ped = ped,
        wants = math.floor(RandomFloatInRange(GetQueueConfig().Wants, 1, 3) + 0.5),
        got = 0,
        arrived = false
    }

    local patienceSec = tonumber(GetQueueConfig().Patience) or 0
    if patienceSec > 0 then
        customer.until_ = GetGameTimer() + math.floor(patienceSec * 1000)
    end

    CookingSession.queue[#CookingSession.queue + 1] = customer
end

function UpdateCustomers(deltaTime)
    if not CookingSession then
        return
    end
    local currentTime = GetGameTimer()
    local playerPed = PlayerPedId()

    for i = #CookingSession.queue, 1, -1 do
        local customer = CookingSession.queue[i]
        if customer.until_ and currentTime >= customer.until_ then
            if not customer.player then
                DismissCustomer(customer)
            end
            table.remove(CookingSession.queue, i)
        else
            if customer.ped and DoesEntityExist(customer.ped) then
                local slotCoords = GetQueueSlotWorldCoords(i, #CookingSession.queue)
                local pedCoords = GetEntityCoords(customer.ped)
                local dist = #(pedCoords - slotCoords)

                if dist > 0.6 then
                    customer.arrived = false
                    TaskGoToCoordAnyMeans(customer.ped, slotCoords.x, slotCoords.y, slotCoords.z, 1.0, 0, 0, 786603, 0xbf800000)
                else
                    if not customer.arrived then
                        customer.arrived = true
                        TaskTurnPedToFaceEntity(customer.ped, playerPed, 1000)
                    end
                end
            end
        end
    end
end

function ServeCustomer(customer)
    if not customer or not CookingSession then
        return false
    end

    TriggerServerEvent("qs-fisher:foodboat:serve", customer.player)
    customer.got = customer.got + 1
    CookingSession.cooked = math.max((CookingSession.cooked or 0) - 1, 0)
    CookingSession.sold = (CookingSession.sold or 0) + 1
    UpdateCookedPile()

    if customer.got >= customer.wants then
        if not customer.player then
            DismissCustomer(customer)
        end
        for index, item in ipairs(CookingSession.queue) do
            if item == customer then
                table.remove(CookingSession.queue, index)
                break
            end
        end
    end
    return true
end

function AddPlayerToQueue(playerId, wants)
    if not CookingSession then
        return
    end
    for _, item in ipairs(CookingSession.queue) do
        if item.player == playerId then
            return
        end
    end

    local customer = {
        player = playerId,
        wants = math.max(math.floor(tonumber(wants) or 1), 1),
        got = 0,
        arrived = true
    }

    local patienceSec = tonumber(GetQueueConfig().Patience) or 0
    if patienceSec > 0 then
        customer.until_ = GetGameTimer() + math.floor(patienceSec * 1000)
    end

    CookingSession.queue[#CookingSession.queue + 1] = customer
end

RegisterNetEvent("qs-fisher:foodboat:wants", function(playerId, wants)
    AddPlayerToQueue(playerId, wants)
end)

function GetFrontCustomer()
    if not CookingSession then
        return nil
    end
    for _, item in ipairs(CookingSession.queue) do
        if item.arrived then
            return item
        end
    end
    return nil
end

RegisterNUICallback("foodBoatMouse", function(data, cb)
    if data then
        if data.flip then
            FlipRequested = true
        else
            MouseState = (data.down == true)
        end
    end
    cb("ok")
end)

RegisterNUICallback("foodBoatConfirm", function(data, cb)
    ConfirmResult = (data and data.ok == true)
    cb("ok")
end)

RegisterNUICallback("foodBoatKey", function(data, cb)
    PendingKey = data and data.key
    cb("ok")
end)

function ConsumePendingKey(expectedKey)
    if PendingKey ~= expectedKey then
        return false
    end
    PendingKey = nil
    return true
end

function GetNormalizedCursorPosition()
    local cx, cy = GetNuiCursorPosition()
    local rx, ry = GetActiveScreenResolution()
    if not rx or rx == 0 then
        rx, ry = 1920, 1080
    end
    return cx / rx, cy / ry
end

function GetCurrentGrillZone()
    local zones = FoodBoatConfig.Grill.Zone
    if CookingSession and CookingSession.view == "grill" then
        return zones.Grill
    end
    return zones.Stall or { x1 = 0.469, y1 = 0.652, x2 = 0.852, y2 = 0.949 }
end

function IsCursorInGrillZone()
    local zone = GetCurrentGrillZone()
    local cx, cy = GetNormalizedCursorPosition()
    local minX = math.min(zone.x1, zone.x2)
    local maxX = math.max(zone.x1, zone.x2)
    local minY = math.min(zone.y1, zone.y2)
    local maxY = math.max(zone.y1, zone.y2)
    return cx >= minX and cx <= maxX and cy >= minY and cy <= maxY
end

function GetGrillSlotUnderCursor()
    if not IsCursorInGrillZone() then
        return nil
    end
    local zone = GetCurrentGrillZone()
    local cx, cy = GetNormalizedCursorPosition()
    local minX = math.min(zone.x1, zone.x2)
    local maxX = math.max(zone.x1, zone.x2)
    local slotsCount = tonumber(GetFoodBoatConfig().Grill and GetFoodBoatConfig().Grill.Slots) or 4

    local fraction = (cx - minX) / math.max(maxX - minX, 0.001)
    local slotIndex = math.floor(fraction * slotsCount) + 1
    return math.max(1, math.min(slotIndex, slotsCount))
end

function GetScreenToWorldRay()
    if not ActiveCamera or not CookingSession then
        return nil, nil
    end
    local camPos = GetCamCoord(ActiveCamera)
    local _, lookPos, fov = CalculateCameraTransform()
    if not camPos or not lookPos then
        return nil, nil
    end

    local forward = lookPos - camPos
    local forwardLen = #forward
    if forwardLen < 0.001 then
        return nil, nil
    end
    forward = forward / forwardLen

    local right = vector3(forward.y, -forward.x, 0.0)
    local rightLen = #right
    if rightLen < 0.001 then
        return camPos, forward
    end
    right = right / rightLen

    local up = vector3(
        right.y * forward.z - right.z * forward.y,
        right.z * forward.x - right.x * forward.z,
        right.x * forward.y - right.y * forward.x
    )

    local cx, cy = GetNormalizedCursorPosition()
    local rx, ry = GetActiveScreenResolution()
    if not rx or rx == 0 then
        rx, ry = 1920, 1080
    end

    local ndcX = cx * 2.0 - 1.0
    local ndcY = 1.0 - cy * 2.0
    local halfFovRad = math.rad(fov * 0.5)
    local tanHalfFov = math.tan(halfFovRad)
    local aspect = rx / math.max(ry, 1)

    local rayDir = forward + right * (ndcX * tanHalfFov * aspect) + up * (ndcY * tanHalfFov)
    local rayDirLen = #rayDir
    if rayDirLen < 0.001 then
        return camPos, forward
    end

    return camPos, rayDir / rayDirLen
end

function GetCursorWorldCoord(depth)
    local origin, dir = GetScreenToWorldRay()
    if not origin or not dir then
        return nil
    end
    local dist = math.max(depth or 2.0, 0.3)
    return origin + dir * dist
end

function GetDistancePointToSegment2D(x1, y1, x2, y2, px, py)
    local dx = x2 - x1
    local dy = y2 - y1
    local lenSq = dx * dx + dy * dy
    if lenSq < 1.0e-9 then
        local p1 = vector2(x1, y1)
        local pt = vector2(px, py)
        return #(p1 - pt)
    end

    local t = ((px - x1) * dx + (py - y1) * dy) / lenSq
    t = math.max(0.0, math.min(1.0, t))
    local proj = vector2(x1 + dx * t, y1 + dy * t)
    local pt = vector2(px, py)
    return #(proj - pt)
end

function ProjectEntityOffsetToScreen(entity, x, y, z)
    local worldPos = GetOffsetFromEntityInWorldCoords(entity, x, y, 0.0)
    return GetScreenCoordFromWorldCoord(worldPos.x, worldPos.y, worldPos.z)
end

function FindHoveredSkewer(tolerance)
    if not CookingSession then
        return nil
    end
    local cx, cy = GetNormalizedCursorPosition()
    local bestSkewer = nil
    local bestDist = (FoodBoatConfig.Grill.LiftZ or 0.25) + (tolerance or 0.05)

    function CheckSkewer(skewer)
        if not skewer.prop or not DoesEntityExist(skewer.prop) then
            return
        end
        local visible, sx, sy = ProjectEntityOffsetToScreen(skewer.prop, 0.0, 0.0, 0.0)
        if not visible then
            return
        end
        if math.abs(sx - cx) > bestDist or math.abs(sy - cy) > bestDist then
            return
        end

        local vis1, x1, y1 = ProjectEntityOffsetToScreen(skewer.prop, 0.0, -(FoodBoatConfig.Particles.Scale or 0.22), 0.0)
        local vis2, x2, y2 = ProjectEntityOffsetToScreen(skewer.prop, 0.0, FoodBoatConfig.Particles.Scale or 0.22, 0.0)

        if vis1 and vis2 then
            local dist = GetDistancePointToSegment2D(x1, y1, x2, y2, cx, cy)
            if dist < bestDist then
                bestDist = dist
                bestSkewer = skewer
            end
        end
    end

    for _, skewer in ipairs(CookingSession.grill) do
        CheckSkewer(skewer)
    end
    for _, skewer in ipairs(CookingSession.rack) do
        CheckSkewer(skewer)
    end
    for _, skewer in ipairs(CookingSession.pile or {}) do
        CheckSkewer(skewer)
    end

    return bestSkewer
end

function TickSkewerCooking(skewer, deltaTime)
    if skewer.where ~= "grill" or skewer.dragWorld then
        return
    end
    if skewer.state == "burnt" then
        return
    end

    local cookConf = GetFoodBoatConfig().Cook or {}
    local sideTime = math.max(tonumber(cookConf.Side) or 18.0, 0.5)
    local burnTime = math.max(tonumber(cookConf.Burn) or 30.0, sideTime + 0.5)
    local activeSide = skewer.turned and 2 or 1

    skewer.sides = skewer.sides or { 0.0, 0.0 }
    skewer.sides[activeSide] = skewer.sides[activeSide] + deltaTime

    if skewer.sides[activeSide] >= burnTime then
        return UpdateSkewerState(skewer, "burnt")
    end

    if skewer.sides[1] >= sideTime and skewer.sides[2] >= sideTime then
        return UpdateSkewerState(skewer, "cooked")
    end
end

function DrawSkewerProgressBar(skewer)
    if not skewer.prop or not DoesEntityExist(skewer.prop) or skewer.dragWorld then
        return
    end
    local coords = GetEntityCoords(skewer.prop)
    local visible, sx, sy = GetScreenCoordFromWorldCoord(coords.x, coords.y, coords.z)
    if not visible then
        return
    end

    sy = sy - 0.034
    local cookConf = GetFoodBoatConfig().Cook or {}
    local sideTime = math.max(tonumber(cookConf.Side) or 18.0, 0.5)
    local burnTime = math.max(tonumber(cookConf.Burn) or 30.0, sideTime + 0.5)
    local activeSide = skewer.turned and 2 or 1
    local currentSideTime = (skewer.sides and skewer.sides[activeSide]) or 0.0

    local isBurnt = (skewer.state == "burnt")
    local progressFraction = isBurnt and 1.0 or math.min(currentSideTime / burnTime, 1.0)
    local cookTargetFraction = sideTime / burnTime

    local r, g, b = 56, 189, 248
    if isBurnt or currentSideTime >= burnTime * 0.82 then
        r, g, b = 248, 113, 113
    elseif skewer.state ~= "raw" or currentSideTime >= sideTime then
        r, g, b = 251, 191, 36
    end

    local width, height = 0.042, 0.0075
    DrawRect(sx, sy, width + 0.01, height + 0.014, 15, 23, 43, 225)
    DrawRect(sx, sy, width + 0.0125, height + 0.017, 59, 130, 246, 255)
    DrawRect(sx, sy, width, height, 30, 41, 59, 255)

    local fillWidth = width * progressFraction
    local fillX = sx - (width * 0.5) + (fillWidth * 0.5)
    DrawRect(fillX, sy, fillWidth, height, r, g, b, 235)

    local targetX = sx - (width * 0.5) + (width * cookTargetFraction)
    DrawRect(targetX, sy, 0.0018, height + 0.004, 255, 255, 255, 255)
end

function ClaimSkewer(skewer)
    TriggerServerEvent("qs-fisher:foodboat:claim", skewer.state)
    CookingSession.done = (CookingSession.done or 0) + 1
    DeleteSkewer(skewer)
end

function CloseFoodBoatCooking()
    if not CookingSession then
        return
    end

    if CookingSession.held then
        DeleteSkewer(CookingSession.held)
    end

    for _, skewer in ipairs(CookingSession.rack or {}) do
        DeleteSkewer(skewer)
    end
    for _, skewer in ipairs(CookingSession.grill or {}) do
        DeleteSkewer(skewer)
    end
    for _, skewer in ipairs(CookingSession.pile or {}) do
        DeleteSkewer(skewer)
    end
    for _, customer in ipairs(CookingSession.queue or {}) do
        DismissCustomer(customer)
    end

    CookingSession = nil
    TriggerServerEvent("qs-fisher:foodboat:open", false)
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({
        action = "foodBoat",
        show = false
    })
end

function PackUpFoodBoat(instant, silent)
    if not ActiveBoat then
        return
    end
    CloseFoodBoatCooking()
    DestroyFoodBoatCamera(instant)

    if ActiveBoat.prop and DoesEntityExist(ActiveBoat.prop) then
        if not NetworkHasControlOfEntity(ActiveBoat.prop) then
            NetworkRequestControlOfEntity(ActiveBoat.prop)
            if not instant then
                local timeout = GetGameTimer() + 500
                while not NetworkHasControlOfEntity(ActiveBoat.prop) and GetGameTimer() <= timeout do
                    Wait(0)
                end
            end
        end
        SetEntityAsMissionEntity(ActiveBoat.prop, true, true)
        DeleteEntity(ActiveBoat.prop)
    end

    ActiveBoat = nil
    local playerPed = PlayerPedId()
    FreezeEntityPosition(playerPed, false)
    SetEntityInvincible(playerPed, false)
    ClearPedTasks(playerPed)

    if not silent then
        TriggerServerEvent("qs-fisher:foodboat:packed")
    end
end

exports("packUpFoodBoat", function()
    PackUpFoodBoat(true, true)
end)

function FoodBoatCookingLoop()
    local lastTimer = GetGameTimer()
    local lastNuiSync = 0

    while CookingSession and ActiveBoat do
        Wait(0)
        local now = GetGameTimer()
        local deltaTime = (now - lastTimer) / 1000.0
        lastTimer = now

        if not CookingSession or not ActiveBoat then
            break
        end

        local playerPed = PlayerPedId()
        DisableAllControlActions(0)
        EnableControlAction(0, 245, true)

        TickCameraBlend(deltaTime)
        HideEntityWhileInCam(playerPed)

        for i = #CookingSession.grill, 1, -1 do
            local skewer = CookingSession.grill[i]
            TickSkewerCooking(skewer, deltaTime)
            UpdateSkewerTransform(skewer)
            DrawSkewerProgressBar(skewer)
            UpdateSkewerSmoke(skewer, not skewer.dragWorld)
        end

        if GetQueueConfig().Enabled ~= false then
            UpdateCustomers(deltaTime)
            if now >= (CookingSession.nextAt or 0) then
                local maxQueue = tonumber(GetQueueConfig().Max) or 4
                if #CookingSession.queue < maxQueue then
                    local delaySec = RandomFloatInRange(GetQueueConfig().Every, 10, 30)
                    CookingSession.nextAt = now + math.floor(delaySec * 1000)
                    CreateThread(SpawnCustomer)
                end
            end

            if (CookingSession.cooked or 0) <= 0 and #CookingSession.grill <= 0 and GetRemainingRawCount() <= 0 and not CookingSession.held then
                if #CookingSession.queue > 0 then
                    CreateNotification("notify", "info", Lang("FOODBOAT_SOLD_OUT"))
                    for _, customer in ipairs(CookingSession.queue) do
                        DismissCustomer(customer)
                    end
                    CookingSession.queue = {}
                end
            end
        end

        local hovered = FindHoveredSkewer()
        for _, s in ipairs(CookingSession.rack) do
            SetSkewerOutline(s, s == hovered)
        end
        for _, s in ipairs(CookingSession.grill) do
            SetSkewerOutline(s, s == hovered)
        end
        for _, s in ipairs(CookingSession.pile or {}) do
            SetSkewerOutline(s, s == hovered)
        end

        if ConsumePendingKey("view") then
            SetCameraView((CookingSession.view == "stall") and "grill" or "stall")
        end

        local isMouseDown = MouseState
        if isMouseDown and not CookingSession.pressed then
            if not CookingSession.held and hovered then
                local camPos = GetScreenToWorldRay()
                UpdateSkewerSmoke(hovered, false)
                local depth = 2.0
                if camPos and hovered.prop and DoesEntityExist(hovered.prop) then
                    depth = #(GetEntityCoords(hovered.prop) - camPos)
                end
                hovered.depth = depth
                hovered.from = {
                    where = hovered.where,
                    slot = hovered.slot
                }

                local sourceList = (hovered.where == "grill" and CookingSession.grill)
                    or (hovered.where == "cooked" and CookingSession.pile)
                    or CookingSession.rack

                for idx, item in ipairs(sourceList or {}) do
                    if item == hovered then
                        table.remove(sourceList, idx)
                        break
                    end
                end

                hovered.sides = hovered.sides or { 0.0, 0.0 }
                CookingSession.held = hovered
            end
        elseif not isMouseDown and CookingSession.pressed then
            if CookingSession.held then
                local heldSkewer = CookingSession.held
                heldSkewer.dragWorld = nil
                CookingSession.held = nil

                local targetSlot = GetGrillSlotUnderCursor()
                local isSlotOccupied = false
                for _, s in ipairs(CookingSession.grill) do
                    if s.slot == targetSlot then
                        isSlotOccupied = true
                        break
                    end
                end

                local handled = false
                if heldSkewer.where == "cooked" then
                    local frontCust = GetFrontCustomer()
                    if frontCust and ServeCustomer(frontCust) then
                        DeleteSkewer(heldSkewer)
                        handled = true
                    end
                end

                if not handled then
                    if heldSkewer.where == "grill" and heldSkewer.state ~= "raw" and (not targetSlot or isSlotOccupied) then
                        ClaimSkewer(heldSkewer)
                        handled = true
                    end
                end

                if not handled then
                    local maxSlots = tonumber(GetFoodBoatConfig().Grill and GetFoodBoatConfig().Grill.Slots) or 4
                    if heldSkewer.where ~= "cooked" and targetSlot and not isSlotOccupied and #CookingSession.grill < maxSlots then
                        heldSkewer.where = "grill"
                        heldSkewer.slot = targetSlot
                        heldSkewer.from = nil
                        CookingSession.grill[#CookingSession.grill + 1] = heldSkewer
                        if heldSkewer.from and heldSkewer.from.where ~= "grill" then
                            TriggerServerEvent("qs-fisher:foodboat:sizzle")
                        end
                        UpdateRawRack()
                    else
                        local fallback = heldSkewer.from or { where = "rack", slot = 1 }
                        heldSkewer.where = fallback.where
                        heldSkewer.slot = fallback.slot
                        heldSkewer.from = nil

                        local destList = (fallback.where == "grill" and CookingSession.grill)
                            or (fallback.where == "cooked" and CookingSession.pile)
                            or CookingSession.rack

                        destList[#destList + 1] = heldSkewer
                        if fallback.where == "rack" then
                            UpdateRawRack()
                        elseif fallback.where == "cooked" then
                            UpdateCookedPile()
                        end
                    end
                end
                UpdateSkewerTransform(heldSkewer)
            end
        end

        CookingSession.pressed = isMouseDown

        if FlipRequested then
            FlipRequested = false
            if CookingSession.held then
                local held = CookingSession.held
                held.turned = not held.turned
                local origin = held.from or { where = "rack", slot = held.slot or 1 }
                held.dragWorld = nil
                held.where = origin.where
                held.slot = origin.slot
                held.from = nil

                local list = (origin.where == "grill" and CookingSession.grill)
                    or (origin.where == "cooked" and CookingSession.pile)
                    or CookingSession.rack

                list[#list + 1] = held
                CookingSession.held = nil

                if origin.where == "rack" then
                    UpdateRawRack()
                elseif origin.where == "cooked" then
                    UpdateCookedPile()
                end
                UpdateSkewerTransform(held)
            end
        end

        if CookingSession.held then
            local worldPos = GetCursorWorldCoord(CookingSession.held.depth)
            if worldPos then
                CookingSession.held.dragWorld = worldPos
            end
            UpdateSkewerTransform(CookingSession.held)
        end

        if ConsumePendingKey("leave") then
            if not CookingSession.asking then
                CookingSession.asking = true
            end
        end

        if ConfirmResult ~= nil then
            local ok = ConfirmResult
            ConfirmResult = nil
            CookingSession.asking = nil
            if ok then
                return PackUpFoodBoat()
            end
        end

        if IsEntityDead(playerPed) then
            return PackUpFoodBoat(true)
        end

        if ActiveBoat.expires and now >= ActiveBoat.expires then
            CreateNotification("notify", "info", Lang("FOODBOAT_PACKED"))
            return PackUpFoodBoat()
        end

        if (now - lastNuiSync) >= 100 then
            lastNuiSync = now
            local cookConf = GetFoodBoatConfig().Cook or {}
            local sideTime = math.max(tonumber(cookConf.Side) or 18.0, 0.5)
            local burnTime = math.max(tonumber(cookConf.Burn) or 30.0, sideTime + 0.5)

            local slotData = {}
            for _, skewer in ipairs(CookingSession.grill) do
                local face = skewer.turned and 2 or 1
                local side1Time = (skewer.sides and skewer.sides[face]) or 0.0
                local otherSideTime = (skewer.sides and skewer.sides[3 - face]) or 0.0
                slotData[#slotData + 1] = {
                    slot = skewer.slot,
                    state = skewer.state,
                    face = face,
                    done = math.min(side1Time / sideTime, 1.0),
                    char = math.min(side1Time / burnTime, 1.0),
                    other = math.min(otherSideTime / sideTime, 1.0)
                }
            end

            local queuePatienceMax = math.max(tonumber(GetQueueConfig().Patience) or 0, 0)
            local queueData = {}
            for _, customer in ipairs(CookingSession.queue) do
                local fraction = 1.0
                if queuePatienceMax > 0 and customer.until_ then
                    local left = math.max(customer.until_ - now, 0)
                    fraction = math.min(left / (queuePatienceMax * 1000), 1.0)
                end
                queueData[#queueData + 1] = {
                    wants = customer.wants or 1,
                    got = customer.got or 0,
                    arrived = customer.arrived == true,
                    patience = fraction
                }
            end

            SendNUIMessage({
                action = "foodBoat",
                show = true,
                view = CookingSession.view,
                raw = GetRemainingRawCount(),
                cooked = CookingSession.cooked or 0,
                grill = #CookingSession.grill,
                holding = (CookingSession.held ~= nil),
                canFlip = (CookingSession.held ~= nil),
                slots = slotData,
                asking = (CookingSession.asking == true),
                queue = queueData,
                sold = CookingSession.sold or 0,
                image = FoodBoatConfig.Queue.Image
            })
        end
    end

    if not ActiveBoat then
        CloseFoodBoatCooking()
    end
end

function OpenFoodBoatCooking()
    if ActiveBoat and CookingSession then
        return
    end

    local stock = lib.callback.await("qs-fisher:foodboat:stock", false) or {}
    local rawCount = stock.raw or 0
    local cookedCount = stock.cooked or 0

    if rawCount <= 0 then
        return CreateNotification("notify", "error", Lang("FOODBOAT_NO_SKEWERS"))
    end

    local delaySec = RandomFloatInRange(GetQueueConfig().Every, 10, 30)
    CookingSession = {
        raw = rawCount,
        cooked = cookedCount,
        done = 0,
        rack = {},
        grill = {},
        pile = {},
        queue = {},
        sold = 0,
        nextAt = GetGameTimer() + math.floor(delaySec * 1000),
        view = "stall"
    }

    CameraBlendT = 0.0
    UpdateRawRack()
    UpdateCookedPile()
    CreateOrUpdateFoodBoatCamera()

    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)

    if not CookingSession then
        return
    end

    local playerPed = PlayerPedId()
    FreezeEntityPosition(playerPed, true)
    SetEntityInvincible(playerPed, true)

    TriggerServerEvent("qs-fisher:foodboat:open", true)
    CreateThread(FoodBoatCookingLoop)
end

function PlaceAndStartFoodBoat()
    if ActiveBoat or IsPlacingBoat then
        return
    end
    if not GetFoodBoatConfig().Enabled then
        return
    end

    IsPlacingBoat = true
    if StowFishingRod then
        StowFishingRod()
    end

    local playerPed = PlayerPedId()
    if IsPedInAnyVehicle(playerPed, false) or IsEntityInWater(playerPed) then
        IsPlacingBoat = false
        return CreateNotification("notify", "error", Lang("FOODBOAT_BAD_GROUND"))
    end

    local stock = lib.callback.await("qs-fisher:foodboat:stock", false) or {}
    if (stock.raw or 0) <= 0 then
        IsPlacingBoat = false
        return CreateNotification("notify", "error", Lang("FOODBOAT_NO_SKEWERS"))
    end

    local modelHash = joaat(FoodBoatConfig.Prop)
    if not EnsureModel(modelHash) then
        IsPlacingBoat = false
        return CreateNotification("notify", "error", Lang("FOODBOAT_NO_PROP"))
    end

    local forwardOffset = FoodBoatConfig.Place.Forward or 4.0
    local targetPos = GetOffsetFromEntityInWorldCoords(playerPed, 0.0, forwardOffset, 0.0)
    local groundZ, groundFound = GetGroundZ(targetPos.x, targetPos.y, targetPos.z)
    if not groundFound then
        IsPlacingBoat = false
        return CreateNotification("notify", "error", Lang("FOODBOAT_BAD_GROUND"))
    end

    local fadeConf = FoodBoatConfig.Fade
    FadeOutScreen(fadeConf.Out or 500)

    local playerHeading = GetEntityHeading(playerPed)
    local boatHeading = (playerHeading + (FoodBoatConfig.Place.Heading or 180.0)) % 360.0

    local durationSec = tonumber(GetFoodBoatConfig().Duration) or 0
    local expiresAt = (durationSec > 0) and (GetGameTimer() + math.floor(durationSec * 1000)) or nil

    ActiveBoat = {
        heading = boatHeading,
        expires = expiresAt
    }

    local zPos = groundZ + (FoodBoatConfig.Place.GroundOffset or 0.0)
    ActiveBoat.prop = CreateObject(modelHash, targetPos.x, targetPos.y, zPos, true, true, false)

    if DoesEntityExist(ActiveBoat.prop) then
        SetEntityAsMissionEntity(ActiveBoat.prop, true, true)
    else
        ActiveBoat = nil
        IsPlacingBoat = false
        FadeInScreen(300)
        return CreateNotification("notify", "error", Lang("FOODBOAT_NO_PROP"))
    end

    SetEntityHeading(ActiveBoat.prop, ActiveBoat.heading)
    FreezeEntityPosition(ActiveBoat.prop, true)
    SetEntityCollision(ActiveBoat.prop, true, true)

    Wait(fadeConf.Hold or 250)

    local standOffset = FoodBoatConfig.Stand.Offset
    local standCoords = GetBoatOffsetCoords(standOffset)
    if standCoords then
        SetEntityCoordsNoOffset(playerPed, standCoords.x, standCoords.y, standCoords.z, false, false, false)
        SetEntityHeading(playerPed, ActiveBoat.heading + (FoodBoatConfig.Stand.Heading or 270.0))
    end

    OpenFoodBoatCooking()
    FadeInScreen(math.max(math.floor(tonumber(fadeConf.In) or 600), 0))
    IsPlacingBoat = false

    if not CookingSession then
        PackUpFoodBoat(true, true)
    end
end

function UseFoodBoat()
    CreateThread(PlaceAndStartFoodBoat)
end

exports("useFoodBoat", UseFoodBoat)
RegisterNetEvent("qs-fisher:useFoodBoat", UseFoodBoat)

CreateThread(function()
    while true do
        local sleep = 1000
        if ActiveBoat and ActiveBoat.prop and DoesEntityExist(ActiveBoat.prop) then
            local leashDist = tonumber(GetFoodBoatConfig().Place and GetFoodBoatConfig().Place.Leash) or 12.0
            local dist = #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(ActiveBoat.prop))

            if dist > leashDist then
                CreateNotification("notify", "info", Lang("FOODBOAT_PACKED"))
                PackUpFoodBoat()
            else
                if not CookingSession then
                    sleep = 0
                    if Config.DrawText3D then
                        local coords = GetEntityCoords(ActiveBoat.prop)
                        local keyLabel = Config.Keys.InteractKeyLabel or "E"
                        DrawText3D(coords.x, coords.y, coords.z + 1.6, Lang("FOODBOAT_PROMPT"), "foodboat", keyLabel)
                    end
                    local interactKey = Config.Keys.InteractKey or 38
                    if IsControlJustReleased(0, interactKey) and dist < 3.5 then
                        CreateThread(OpenFoodBoatCooking)
                    end
                end
            end
        end
        Wait(sleep)
    end
end)

RegisterNUICallback("foodBoatOrder", function(data, cb)
    cb("ok")
    SetNuiFocus(false, false)
    local targetServerId = OrderingFromServerId
    OrderingFromServerId = nil

    local amount = data and tonumber(data.amount)
    if not targetServerId or not amount or amount < 1 then
        return
    end
    TriggerServerEvent("qs-fisher:foodboat:order", targetServerId, math.floor(amount))
end)

RegisterNetEvent("qs-fisher:foodboat:open", function(serverId, isOpen)
    if isOpen then
        OpenFoodBoats[serverId] = true
    else
        OpenFoodBoats[serverId] = nil
    end
end)

function GetOpenFoodBoatPlayerPed(serverId)
    local clientPlayerId = GetPlayerFromServerId(serverId)
    if clientPlayerId and clientPlayerId ~= -1 then
        local ped = GetPlayerPed(clientPlayerId)
        if ped and DoesEntityExist(ped) then
            return ped
        end
    end
    return nil
end

CreateThread(function()
    while true do
        local sleep = 700
        if next(OpenFoodBoats) then
            local myPed = PlayerPedId()
            local myServerId = GetPlayerServerId(PlayerId())
            local myCoords = GetEntityCoords(myPed)

            for targetServerId, _ in pairs(OpenFoodBoats) do
                if targetServerId ~= myServerId then
                    local targetPed = GetOpenFoodBoatPlayerPed(targetServerId)
                    if targetPed then
                        local dist = #(myCoords - GetEntityCoords(targetPed))
                        if dist <= 3.0 then
                            sleep = 0
                            if Config.DrawText3D then
                                local targetCoords = GetEntityCoords(targetPed)
                                local keyLabel = Config.Keys.InteractKeyLabel or "E"
                                DrawText3D(targetCoords.x, targetCoords.y, targetCoords.z + 0.9, Lang("FOODBOAT_BUY_PROMPT"), "foodboat_buy", keyLabel)
                            end
                            local interactKey = Config.Keys.InteractKey or 38
                            if IsControlJustReleased(0, interactKey) then
                                OrderingFromServerId = targetServerId
                                SetNuiFocus(true, true)
                                SendNUIMessage({
                                    action = "foodBoatOrder",
                                    show = true
                                })
                            end
                        end
                    end
                end
            end
        end
        Wait(sleep)
    end
end)

RegisterNetEvent("qs-fisher:notify", function(notifyType, langKey)
    CreateNotification("notify", notifyType or "error", Lang(langKey or "SPEAR_FAILED"))
end)

CreateThread(function()
    if not GetFoodBoatConfig().Enabled then
        return
    end
    Wait(1500)
    local partConf = GetFoodBoatConfig().Particles or {}
    if partConf.Enabled ~= false then
        RequestNamedPtfxAsset(FoodBoatConfig.Particles.Dict)
    end
end)

AddEventHandler("onResourceStop", function(resourceName)
    if GetCurrentResourceName() ~= resourceName then
        return
    end
    PackUpFoodBoat(true, true)
end)
--WKLeakYMOncCTopgA : https://discord.gg/zqcBffbMZn
--WKLeakobOn6mTopVM : https://discord.gg/zqcBffbMZn
--WKLeak-6oOn-qTopAD : https://discord.gg/zqcBffbMZn
--WKLeak_WIOns4TopMY : https://discord.gg/zqcBffbMZn
--WKLeak_AFOnrfTopZH : https://discord.gg/zqcBffbMZn
