--[[   -- https://discord.gg/zqcBffbMZn ]]
local isConfigReady = false
local isAdminOpen = false

function GetAdminConfig()
    return Config.AdminPanel or {}
end

function ParseConfigPath(pathStr)
    local parts = {}
    for part in tostring(pathStr):gmatch("[^%.]+") do
        parts[#parts + 1] = tonumber(part) or part
    end
    return parts
end

function ReconstructVectors(value)
    if type(value) ~= "table" then
        return value
    end
    if value.__vec then
        if value.w ~= nil then
            return vector4(value.x, value.y, value.z, value.w)
        elseif value.z ~= nil then
            return vector3(value.x, value.y, value.z)
        else
            return vector2(value.x, value.y)
        end
    end
    local cleaned = {}
    for k, v in pairs(value) do
        cleaned[k] = ReconstructVectors(v)
    end
    return cleaned
end

function SetConfigPathValue(pathStr, value)
    local parts = ParseConfigPath(pathStr)
    local current = Config
    for i = 1, #parts - 1 do
        local key = parts[i]
        if current[key] == nil then
            current[key] = {}
        end
        if type(current[key]) ~= "table" then
            return false
        end
        current = current[key]
    end
    current[parts[#parts]] = ReconstructVectors(value)
    return true
end

function ApplyConfigOverrides(overrideList)
    local appliedCount = 0
    for _, entry in ipairs(overrideList or {}) do
        if entry.path and SetConfigPathValue(entry.path, entry.value) then
            appliedCount = appliedCount + 1
        end
    end
    return appliedCount
end

function ConfigReady()
    while not isConfigReady do
        Wait(0)
    end
    return true
end

CreateThread(function()
    local savedConfigs = lib.callback.await("qs-fisher:config:pull", false)
    local applied = ApplyConfigOverrides(savedConfigs)
    isConfigReady = true
    if PushLanguageToNui then
        PushLanguageToNui()
    end
    TriggerEvent("qs-fisher:configReady")
    if applied > 0 and Config.Debug then
        DebugPrint(("%d saved setting(s) applied on this client."):format(applied))
    end
end)

function NuiSafe(val)
    local valType = type(val)
    if valType == "vector2" or valType == "vector3" or valType == "vector4" then
        local vec = { __vec = true, x = val.x, y = val.y }
        if valType ~= "vector2" then
            vec.z = val.z
        end
        if valType == "vector4" then
            vec.w = val.w
        end
        return vec
    end
    if valType ~= "table" then
        return val
    end

    local count = 0
    local maxIndex = 0
    local hasNonNumericKey = false
    for k in pairs(val) do
        count = count + 1
        if type(k) == "number" then
            if k > maxIndex then
                maxIndex = k
            end
        else
            hasNonNumericKey = true
        end
    end

    local isSequentialArray = (not hasNonNumericKey) and (count == maxIndex)
    local safeTable = {}
    for k, v in pairs(val) do
        local key = (isSequentialArray and k) or tostring(k)
        safeTable[key] = NuiSafe(v)
    end
    return safeTable
end

function CloseAdminPanel()
    if not isAdminOpen then
        return
    end
    isAdminOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({
        action = "fisherAdmin",
        show = false
    })
end

function OpenAdminPanel()
    if isAdminOpen then
        return CloseAdminPanel()
    end
    local response = lib.callback.await("qs-fisher:admin:load", false)
    if not response or not response.allowed then
        return CreateNotification("notify", "error", Lang("ADMIN_NO_PERMISSION"))
    end
    isAdminOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = "fisherAdmin",
        show = true,
        data = NuiSafe(response)
    })
end

function ForwardAdminCallback(eventName, cb, payload, fallbackResult)
    local success, result = pcall(lib.callback.await, eventName, false, payload)
    if not success then
        print(("^1[qs-fishingjob]^0 %s failed: %s"):format(eventName, tostring(result)))
        return cb(NuiSafe(fallbackResult))
    end
    cb(NuiSafe(result ~= nil and result or fallbackResult))
end

RegisterNUICallback("fisherAdminClose", function(data, cb)
    cb("ok")
    CloseAdminPanel()
end)

RegisterNUICallback("fisherAdminSet", function(data, cb)
    ForwardAdminCallback("qs-fisher:admin:set", cb, data, { ok = false, reason = "error" })
end)

RegisterNUICallback("fisherAdminReset", function(data, cb)
    ForwardAdminCallback("qs-fisher:admin:reset", cb, data, { ok = false, reason = "error" })
end)

RegisterNUICallback("fisherAdminEvent", function(data, cb)
    ForwardAdminCallback("qs-fisher:admin:event", cb, data, { ok = false, reason = "error" })
end)

RegisterNUICallback("fisherAdminRefresh", function(data, cb)
    ForwardAdminCallback("qs-fisher:admin:load", cb, nil, { allowed = false })
end)

RegisterNUICallback("fisherAdminEvents", function(data, cb)
    ForwardAdminCallback("qs-fisher:admin:events", cb, nil, { allowed = false })
end)

RegisterNUICallback("fisherAdminHere", function(data, cb)
    local playerPed = PlayerPedId()
    local coords = GetEntityCoords(playerPed)
    if data and data.heading then
        cb({
            x = coords.x,
            y = coords.y,
            z = coords.z,
            w = GetEntityHeading(playerPed)
        })
    else
        cb({
            x = coords.x,
            y = coords.y,
            z = coords.z
        })
    end
end)

RegisterNUICallback("fisherAdminGoTo", function(data, cb)
    cb("ok")
    local targetX = tonumber(data and data.x)
    local targetY = tonumber(data and data.y)
    local targetZ = tonumber(data and data.z)
    if not targetX or not targetY or not targetZ then
        return
    end

    local playerPed = PlayerPedId()
    SetNuiFocus(false, false)
    DoScreenFadeOut(300)

    local fadeTimeout = GetGameTimer() + 800
    while not IsScreenFadedOut() and GetGameTimer() < fadeTimeout do
        Wait(0)
    end

    SetEntityCoords(playerPed, targetX, targetY, targetZ, false, false, false, false)
    if data.w then
        SetEntityHeading(playerPed, tonumber(data.w) or 0.0)
    end

    Wait(200)
    DoScreenFadeIn(400)

    if isAdminOpen then
        SetNuiFocus(true, true)
    end
end)

RegisterNUICallback("fisherAdminWaypoint", function(data, cb)
    cb("ok")
    local targetX = tonumber(data and data.x)
    local targetY = tonumber(data and data.y)
    if not targetX or not targetY then
        return
    end
    SetNewWaypoint(targetX, targetY)
    CreateNotification("notify", "success", Lang("WAYPOINT_SET"):format(data.label or "?"))
end)

CreateThread(function()
    local adminConfig = GetAdminConfig()
    local commandName = adminConfig.ConfigCommand or "fisheradmin"
    if adminConfig.Enabled == false or commandName == "" then
        return
    end
    RegisterCommand(commandName, OpenAdminPanel, false)
end)

AddEventHandler("onResourceStop", function(resourceName)
    if GetCurrentResourceName() ~= resourceName then
        return
    end
    if isAdminOpen then
        SetNuiFocus(false, false)
    end
end)
--WKLeak-WlOnOqTopf0 : https://discord.gg/zqcBffbMZn
--WKLeak-#-Onu@TopRE : https://discord.gg/zqcBffbMZn
--WKLeaksnqOngTTopoj : https://discord.gg/zqcBffbMZn
--WKLeak_0iOnaQTopAo : https://discord.gg/zqcBffbMZn
--WKLeakBOOn1#Top2C : https://discord.gg/zqcBffbMZn
