--[[   -- https://discord.gg/zqcBffbMZn ]]
local cachedPeds = {}
local lastPedsUpdate = 0

function GetTargetPeds()
    local currentTime = GetGameTimer()
    if currentTime - lastPedsUpdate < 1000 then
        return cachedPeds
    end
    lastPedsUpdate = currentTime
    for i = #cachedPeds, 1, -1 do
        cachedPeds[i] = nil
    end

    if type(GetJobPeds) == "function" then
        for _, ped in ipairs(GetJobPeds()) do
            if ped and ped ~= 0 and DoesEntityExist(ped) then
                cachedPeds[#cachedPeds + 1] = ped
            end
        end
    elseif type(GetStationPed) == "function" then
        if Config.Stations then
            for i = 1, #Config.Stations do
                local ped = GetStationPed(i)
                if ped and ped ~= 0 and DoesEntityExist(ped) then
                    cachedPeds[#cachedPeds + 1] = ped
                end
            end
        end
    elseif type(GetJobPed) == "function" then
        local ped = GetJobPed()
        if ped and ped ~= 0 and DoesEntityExist(ped) then
            cachedPeds[#cachedPeds + 1] = ped
        end
    end
    return cachedPeds
end

CreateThread(function()
    while true do
        local sleep = 500
        local markerConfig = Config.PedMarker
        if markerConfig and markerConfig.enabled then
            local playerCoords = GetEntityCoords(PlayerPedId())
            local maxDistance = markerConfig.distance or 25.0
            local markerSize = markerConfig.size or { x = 0.25, y = 0.25, z = 0.18 }
            local markerColor = markerConfig.color or { r = 59, g = 130, b = 246, a = 170 }
            local heightOffset = markerConfig.height or 1.0
            local bobOffset = 0.0

            if markerConfig.bob then
                bobOffset = math.sin(GetGameTimer() / 400.0) * 0.05
            end

            for _, ped in ipairs(GetTargetPeds()) do
                if DoesEntityExist(ped) then
                    local pedCoords = GetEntityCoords(ped)
                    if #(playerCoords - pedCoords) <= maxDistance then
                        sleep = 0
                        DrawMarker(
                            markerConfig.type or 0,
                            pedCoords.x,
                            pedCoords.y,
                            pedCoords.z + heightOffset + bobOffset,
                            0.0, 0.0, 0.0,
                            0.0, 0.0, 0.0,
                            markerSize.x,
                            markerSize.y,
                            markerSize.z,
                            markerColor.r,
                            markerColor.g,
                            markerColor.b,
                            markerColor.a,
                            markerConfig.bob == true,
                            false,
                            2,
                            false,
                            nil,
                            nil,
                            false
                        )
                    end
                end
            end
        end
        Wait(sleep)
    end
end)
--WKLeak_YxOnIbTopf9 : https://discord.gg/zqcBffbMZn
--WKLeak-nkOnDmTopuL : https://discord.gg/zqcBffbMZn
--WKLeaks6TOnT3Topga : https://discord.gg/zqcBffbMZn
--WKLeakskROntATopE9 : https://discord.gg/zqcBffbMZn
--WKLeak-QAOngmTop79 : https://discord.gg/zqcBffbMZn
